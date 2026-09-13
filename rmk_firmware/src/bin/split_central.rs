//! Split central firmware: runs the local half's matrix, talks to the host
//! over USB/BLE (with Vial), and pulls the other half's key events in over a
//! BLE link. The supported split uses the left half as central.

#![no_std]
#![no_main]

/// SK6812 chain length for the x7/x8 superset (see `backlight.rs`).
pub const BACKLIGHT_LED_COUNT: usize = 38;

#[path = "../backlight.rs"]
mod backlight;
#[path = "../battery.rs"]
mod battery;
#[path = "../keymap_split.rs"]
mod keymap_split;
#[path = "../low_power_hc595_matrix.rs"]
mod low_power_hc595_matrix;
#[path = "../status_indicator.rs"]
mod status_indicator;
#[path = "../xiao_qspi.rs"]
mod xiao_qspi;
mod vial_split {
    include!(concat!(env!("OUT_DIR"), "/config_split_generated.rs"));
}

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
use embassy_nrf::usb::Driver;
use embassy_nrf::usb::vbus_detect::HardwareVbusDetect;
use embassy_nrf::{bind_interrupts, pac, rng, usb};
use embassy_time::{Duration, Timer};
use embedded_hal_async::spi::{Operation, SpiDevice};
use keymap_split::{COL, HALF_ROW, PERIPHERAL_COL_OFFSET, PERIPHERAL_ROW_OFFSET};
use low_power_hc595_matrix::{LowPowerHc595Matrix, remote_activity_task};
use nrf_mpsl::Flash;
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use panic_probe as _;
use rmk::ble::{BleTransport, build_ble_stack};
use rmk::config::{
    BehaviorConfig, BleBatteryConfig, DeviceConfig, PositionalConfig, RmkConfig, StorageConfig,
    VialConfig,
};
use rmk::debounce::default_debouncer::DefaultDebouncer;
use rmk::futures::future::join;
use rmk::host::HostService;
use rmk::keyboard::Keyboard;
use rmk::processor::builtin::wpm::WpmProcessor;
use rmk::split::ble::central::scan_peripherals;
use rmk::split::central::run_peripheral_manager;
use rmk::types::morse::{MorseMode, MorseProfile};
use rmk::usb::UsbTransport;
use rmk::watchdog::Nrf52Watchdog;
use rmk::{HostResources, KeymapData, initialize_keymap_and_storage, run_all};
use static_cell::StaticCell;
use status_indicator::{INDICATOR_TOGGLE_USER_ID, StatusIndicator};
use vial_split::{VIAL_KEYBOARD_DEF, VIAL_KEYBOARD_ID};

#[cfg(not(feature = "left-central"))]
compile_error!("Enable the `left-central` feature for the split central firmware.");

const PRODUCT_NAME: &str = "On the 15 v4 L";

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
const UNLOCK_KEYS: &[(u8, u8)] = &[(0, 0), (1, 0)];

/// Central SDC: on top of the single-board feature set, scanning and the
/// central role are needed for the link to the peripheral half.
fn build_sdc<'d, const N: usize>(
    p: nrf_sdc::Peripherals<'d>,
    rng: &'d mut rng::Rng<Async>,
    mpsl: &'d MultiprotocolServiceLayer,
    mem: &'d mut sdc::Mem<N>,
) -> Result<nrf_sdc::SoftdeviceController<'d>, nrf_sdc::Error> {
    sdc::Builder::new()?
        .support_scan()
        .support_central()
        .support_adv()
        .support_peripheral()
        .support_dle_central()
        .support_dle_peripheral()
        .support_phy_update_central()
        .support_phy_update_peripheral()
        .support_le_2m_phy()
        .central_count(1)?
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
    info!("On the 15 v4 split central ({})", PRODUCT_NAME);

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;
    nrf_config.gpiote_interrupt_priority = interrupt::Priority::P3;
    nrf_config.time_interrupt_priority = interrupt::Priority::P3;
    interrupt::USBD.set_priority(interrupt::Priority::P2);
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
    // 8192 bytes matches the nrf52840_ble_split central example, which uses
    // the same feature set including the central role.
    let mut sdc_mem = sdc::Mem::<8192>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));
    let mut host_resources = HostResources::new();
    let stack = build_ble_stack(sdc, ble_addr(), &mut host_resources).await;

    let driver = Driver::new(p.USBD, Irqs, HardwareVbusDetect::new(Irqs));
    let flash = Flash::take(mpsl, p.NVMC);

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
    let keyboard_device_config = DeviceConfig {
        vid: 0x4F54,
        pid: 0x1537,
        manufacturer: "Hayashi",
        product_name: PRODUCT_NAME,
        serial_number: "vial:4f543135:000001",
    };
    let vial_config = VialConfig::new(VIAL_KEYBOARD_ID, VIAL_KEYBOARD_DEF, UNLOCK_KEYS);
    let ble_battery_config = BleBatteryConfig::new(None::<Input<'static>>, false, None, false);
    let storage_config = StorageConfig {
        start_addr: 0xA0000,
        num_sectors: 6,
        clear_layout: false,
        ..Default::default()
    };
    let rmk_config = RmkConfig {
        device_config: keyboard_device_config,
        vial_config,
        ble_battery_config,
        storage_config,
    };

    // Vial packs these one-bit selectors as left then right. 0b10 selects
    // left x7 (choice 1) and right x8 (choice 0).
    let mut keymap_data =
        KeymapData::new(keymap_split::get_default_keymap()).with_layout_options(0b10);
    let key_config = PositionalConfig::default();
    let mut behavior_config = BehaviorConfig::default();
    behavior_config.morse.default_profile =
        MorseProfile::new(None, Some(MorseMode::HoldOnOtherPress), Some(200), None);
    let (keymap, mut storage) = initialize_keymap_and_storage(
        &mut keymap_data,
        flash,
        &storage_config,
        &mut behavior_config,
        &key_config,
    )
    .await;
    let indicator_enabled = storage
        .user_setting(INDICATOR_TOGGLE_USER_ID)
        .await
        .unwrap_or(0)
        != 0;
    battery::configure(
        storage
            .user_setting(battery::LOW_BATTERY_WARNING_USER_ID)
            .await
            .unwrap_or(1)
            != 0,
        storage
            .user_setting(battery::BATTERY_TYPE_USER_ID)
            .await
            .unwrap_or(0),
    );
    let values = (
        storage.user_setting(12).await.unwrap_or(1) != 0,
        storage.user_setting(13).await.unwrap_or(0) != 0,
        storage.user_setting(14).await.unwrap_or(12),
        storage.user_setting(16).await.unwrap_or(10),
        storage.user_setting(18).await.unwrap_or(1),
        storage.user_setting(20).await.unwrap_or(1),
        storage.user_setting(22).await.unwrap_or(0) != 0,
        storage.user_setting(23).await.unwrap_or(0) != 0,
        storage.user_setting(24).await.unwrap_or(0) != 0,
    );
    let brightness_model_version = storage
        .user_setting(backlight::BRIGHTNESS_MODEL_VERSION_USER_ID)
        .await;
    let (underglow_brightness_offset, brightness_migration_pending) =
        backlight::brightness_storage_state(values.4, values.5, brightness_model_version);
    backlight::configure(
        values.0,
        values.1,
        values.2,
        values.3,
        values.4,
        underglow_brightness_offset,
        values.6,
        values.7,
        values.8,
        brightness_migration_pending,
    );
    drop(backlight_hold);
    spawner.spawn(backlight_vbus_task(vbus_sense, p.PWM0, p.P1_15, false).unwrap());
    spawner.spawn(remote_activity_task().unwrap());
    let mut status_indicator =
        StatusIndicator::central(led_indicator_green, led_indicator_red, indicator_enabled);

    // Peripheral BLE addresses persisted from earlier pairings; empty slots
    // make scan_peripherals look for an unpaired peripheral half.
    let peripheral_addrs = storage.read_peripheral_addresses::<1>().await;

    let debouncer = DefaultDebouncer::new();
    let mut matrix = LowPowerHc595Matrix::<_, _, _, _, HALF_ROW, COL, 0, 0, true>::new(
        spi, latch, row_pins, debouncer,
    )
    .await;
    let mut keyboard = Keyboard::new(&keymap);
    let host_ctx = rmk::host::KeyboardContext::new(&keymap);
    let mut host_service = HostService::new(&host_ctx, &rmk_config);
    let mut usb_transport = UsbTransport::new(driver, rmk_config.device_config);
    let mut ble_transport = BleTransport::new(&stack, rmk_config).await;
    let mut wpm_processor = WpmProcessor::new();
    let mut watchdog_runner = Nrf52Watchdog::default_runner(p.WDT);

    join(
        run_all!(
            matrix,
            storage,
            usb_transport,
            ble_transport,
            wpm_processor,
            keyboard,
            host_service,
            battery_monitor,
            status_indicator,
            watchdog_runner
        ),
        join(
            run_peripheral_manager::<HALF_ROW, COL, PERIPHERAL_ROW_OFFSET, PERIPHERAL_COL_OFFSET, _>(
                0,
                &peripheral_addrs,
                &stack,
            ),
            scan_peripherals(&stack, &peripheral_addrs),
        ),
    )
    .await;
}
