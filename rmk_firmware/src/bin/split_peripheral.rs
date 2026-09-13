//! Split peripheral firmware: scans the local half's matrix and sends key
//! events to the central over BLE. No USB/host/Vial stack - a host USB port
//! only charges the battery (and powers the backlight). One binary serves
//! both x7 and x8 boards via the shared 3 x 16 / 38-LED superset; the
//! central maps the events into the combined keymap.

#![no_std]
#![no_main]

/// SK6812 chain length for the x7/x8 superset (see `backlight.rs`).
pub const BACKLIGHT_LED_COUNT: usize = 38;

#[path = "../backlight.rs"]
mod backlight;
#[path = "../battery.rs"]
mod battery;
#[path = "../low_power_hc595_matrix.rs"]
mod low_power_hc595_matrix;
#[path = "../status_indicator.rs"]
mod status_indicator;
#[path = "../xiao_qspi.rs"]
mod xiao_qspi;

use core::convert::Infallible;

use backlight::backlight_vbus_task;
use battery::BatteryMonitor;
use defmt::{info, unwrap};
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Input, Level, Output, OutputDrive, Pull};
use embassy_nrf::interrupt::{self, InterruptExt};
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::{QSPI, RNG, USBD};
use embassy_nrf::qspi;
use embassy_nrf::saadc;
use embassy_nrf::{bind_interrupts, pac, rng, usb};
use embassy_time::{Duration, Timer};
use embedded_hal_async::spi::{Operation, SpiDevice};
use low_power_hc595_matrix::LowPowerHc595Matrix;
use nrf_mpsl::Flash;
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use panic_probe as _;
use rmk::ble::build_ble_stack;
use rmk::config::StorageConfig;
use rmk::debounce::default_debouncer::DefaultDebouncer;
use rmk::futures::future::join;
use rmk::split::peripheral::run_rmk_split_peripheral;
use rmk::storage::new_storage_for_split_peripheral;
use rmk::watchdog::Nrf52Watchdog;
use rmk::{HostResources, run_all};
use static_cell::StaticCell;
use status_indicator::StatusIndicator;

/// Local scan matrix size (superset shared by x7/x8, same as the central).
const ROW: usize = 3;
const COL: usize = 16;

bind_interrupts!(struct Irqs {
    USBD => usb::InterruptHandler<USBD>;
    RNG => rng::InterruptHandler<RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler, usb::vbus_detect::InterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    QSPI => qspi::InterruptHandler<QSPI>;
    SAADC => saadc::InterruptHandler;
});

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

const L2CAP_TXQ: u8 = 3;
const L2CAP_RXQ: u8 = 3;
const L2CAP_MTU: usize = 251;

/// Peripheral SDC: advertising/peripheral role only, no scanning.
fn build_sdc<'d, const N: usize>(
    p: nrf_sdc::Peripherals<'d>,
    rng: &'d mut rng::Rng<Async>,
    mpsl: &'d MultiprotocolServiceLayer,
    mem: &'d mut sdc::Mem<N>,
) -> Result<nrf_sdc::SoftdeviceController<'d>, nrf_sdc::Error> {
    sdc::Builder::new()?
        .support_adv()
        .support_peripheral()
        .support_dle_peripheral()
        .support_phy_update_peripheral()
        .support_le_2m_phy()
        .peripheral_count(1)?
        .buffer_cfg(L2CAP_MTU as u16, L2CAP_MTU as u16, L2CAP_TXQ, L2CAP_RXQ)?
        .build(p, rng, mpsl, mem)
}

fn ble_addr() -> [u8; 6] {
    let ficr = pac::FICR;
    let high = u64::from(ficr.deviceid(1).read());
    let addr = high << 32 | u64::from(ficr.deviceid(0).read());
    let addr = addr | 0x0000_c000_0000_0000;
    unwrap!(addr.to_le_bytes()[..6].try_into())
}

struct BitBangSpi {
    mosi: Output<'static>,
    sck: Output<'static>,
}

impl BitBangSpi {
    fn new(mosi: Output<'static>, sck: Output<'static>) -> Self {
        Self { mosi, sck }
    }

    async fn write_bytes(&mut self, words: &[u8]) {
        for word in words {
            for bit in (0..8).rev() {
                if word & (1 << bit) == 0 {
                    self.mosi.set_low();
                } else {
                    self.mosi.set_high();
                }
                self.sck.set_high();
                self.sck.set_low();
            }
        }
    }
}

impl embedded_hal_async::spi::ErrorType for BitBangSpi {
    type Error = Infallible;
}

impl SpiDevice<u8> for BitBangSpi {
    async fn transaction(
        &mut self,
        operations: &mut [Operation<'_, u8>],
    ) -> Result<(), Self::Error> {
        for operation in operations {
            match operation {
                Operation::Read(words) => words.fill(0),
                Operation::Write(words) => self.write_bytes(words).await,
                Operation::Transfer(read, write) => {
                    read.fill(0);
                    self.write_bytes(write).await;
                }
                Operation::TransferInPlace(words) => {
                    self.write_bytes(words).await;
                    words.fill(0);
                }
                Operation::DelayNs(_) => {}
            }
        }
        Ok(())
    }
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    info!("On the 15 v4 split peripheral");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;
    nrf_config.gpiote_interrupt_priority = interrupt::Priority::P3;
    nrf_config.time_interrupt_priority = interrupt::Priority::P3;
    interrupt::CLOCK_POWER.set_priority(interrupt::Priority::P2);

    let mut p = embassy_nrf::init(nrf_config);

    let qspi = qspi::Qspi::new(
        p.QSPI,
        Irqs,
        p.P0_21,
        p.P0_25,
        p.P0_20,
        p.P0_24,
        p.P0_22,
        p.P0_23,
        xiao_qspi::deep_power_down_config(),
    );
    drop(qspi);

    let led_indicator_green = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let led_indicator_red = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);

    let vbus_sense = Input::new(p.P0_03, Pull::Down);

    let backlight_hold = Output::new(p.P1_15.reborrow(), Level::Low, OutputDrive::Standard);

    let mpsl_p =
        mpsl::Peripherals::new(p.RTC0, p.TIMER0, p.TEMP, p.PPI_CH19, p.PPI_CH30, p.PPI_CH31);
    let lfclk_cfg = mpsl::raw::mpsl_clock_lfclk_cfg_t {
        source: mpsl::raw::MPSL_CLOCK_LF_SRC_RC as u8,
        rc_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_CTIV as u8,
        rc_temp_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_TEMP_CTIV as u8,
        accuracy_ppm: mpsl::raw::MPSL_DEFAULT_CLOCK_ACCURACY_PPM as u16,
        skip_wait_lfclk_started: mpsl::raw::MPSL_DEFAULT_SKIP_WAIT_LFCLK_STARTED != 0,
    };

    static MPSL: StaticCell<MultiprotocolServiceLayer> = StaticCell::new();
    static SESSION_MEM: StaticCell<mpsl::SessionMem<1>> = StaticCell::new();
    let mpsl = MPSL.init(unwrap!(mpsl::MultiprotocolServiceLayer::with_timeslots(
        mpsl_p,
        Irqs,
        lfclk_cfg,
        SESSION_MEM.init(mpsl::SessionMem::new())
    )));
    spawner.spawn(mpsl_task(&*mpsl).unwrap());
    Timer::after(Duration::from_millis(10)).await;

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    let mut rng = rng::Rng::new(p.RNG, Irqs);
    // 8192 is generous for the peripheral-only SDC feature set (the example
    // uses 4624), but matches the known-good value from the single-board
    // firmware.
    let mut sdc_mem = sdc::Mem::<8192>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));
    let mut host_resources = HostResources::new();
    let stack = build_ble_stack(sdc, ble_addr(), &mut host_resources).await;

    // Storage holds the pairing/bond info towards the central.
    let storage_config = StorageConfig {
        start_addr: 0xA0000,
        num_sectors: 6,
        ..Default::default()
    };
    let flash = Flash::take(mpsl, p.NVMC);
    let mut storage = new_storage_for_split_peripheral(flash, storage_config).await;
    battery::configure(
        storage
            .user_setting(battery::LOW_BATTERY_WARNING_USER_ID)
            .await
            .unwrap_or(1)
            != 0,
        storage
            .user_setting(battery::BATTERY_TYPE_USER_ID)
            .await
            .unwrap_or(battery::BatteryType::Nimh as u8),
    );
    backlight::configure(true, false, 12, 10, 1, 0, false, false, false, false);
    let mut status_indicator = StatusIndicator::peripheral(led_indicator_green, led_indicator_red);

    let row_pins = [
        Input::new(p.P1_14, Pull::Down), // row0: XIAO D11 / MISO
        Input::new(p.P1_13, Pull::Down), // row1: XIAO D10 / SCK
        Input::new(p.P1_12, Pull::Down), // row2: XIAO D9 / RX, side switches
    ];
    let latch = Output::new(p.P1_11, Level::Low, OutputDrive::Standard); // cs: XIAO D8 / TX
    let mosi = Output::new(p.P0_04, Level::Low, OutputDrive::Standard); // mosi: XIAO D6 / SDA
    let sck = Output::new(p.P0_05, Level::Low, OutputDrive::Standard); // sck: XIAO D7 / SCL
    let spi = BitBangSpi::new(mosi, sck);

    interrupt::SAADC.set_priority(interrupt::Priority::P3);
    let mut battery_channel = saadc::ChannelConfig::single_ended(p.P0_02);
    battery_channel.time = saadc::Time::_40US;
    let mut battery_adc_config = saadc::Config::default();
    battery_adc_config.resolution = saadc::Resolution::_12bit;
    battery_adc_config.oversample = saadc::Oversample::Over4x;
    let battery_adc = saadc::Saadc::new(p.SAADC, Irqs, battery_adc_config, [battery_channel]);
    let mut battery_monitor = BatteryMonitor::new(battery_adc, 1);
    drop(backlight_hold);
    spawner.spawn(backlight_vbus_task(vbus_sense, p.PWM0, p.P1_15, false).unwrap());

    let debouncer = DefaultDebouncer::new();
    let mut matrix = LowPowerHc595Matrix::<_, _, _, _, ROW, COL, 0, 0, true>::new(
        spi, latch, row_pins, debouncer,
    )
    .await;
    let mut watchdog_runner = Nrf52Watchdog::default_runner(p.WDT);

    join(
        run_all!(
            matrix,
            storage,
            battery_monitor,
            status_indicator,
            watchdog_runner
        ),
        run_rmk_split_peripheral(0, &stack),
    )
    .await;
}
