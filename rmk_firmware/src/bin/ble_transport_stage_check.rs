//! Extended stage check: reproduces the *production* main.rs configuration
//! (MPSL with_timeslots + full SDC feature set + BleTransport) step by step,
//! showing progress on the indicator LEDs / SK6812 backlight before every
//! stage. Unlike ble_stage_check, this binary actually constructs
//! `BleTransport` and runs it inside `run_all!`, which is the only part of
//! the production firmware that no previous check binary exercised (R1).
//!
//! Intentionally excluded: the watchdog (kept out so R3 does not mix into
//! this measurement).
//!
//! LED pattern -> last completed stage:
//!   stage 1 RED     : embassy init + GPIO done, entering MPSL init
//!   stage 2 GREEN   : MPSL with_timeslots + mpsl_task spawned
//!   stage 3 BLUE    : full SDC controller built (Mem::<8192>)
//!   stage 4 CYAN    : trouble-host BLE stack built
//!   stage 5 MAGENTA : HFCLK + USB driver + MPSL timeslot flash taken
//!   stage 6 YELLOW  : keymap + storage initialized
//!   stage 7 WHITE   : BleTransport::new completed
//!   heartbeat blink : run_all! (incl. ble_transport) is being polled

#![no_std]
#![no_main]

#[path = "../keymap.rs"]
mod keymap;
#[path = "../vial.rs"]
mod vial;

use core::convert::Infallible;

use cortex_m::asm;
use defmt::{info, unwrap};
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Input, Level, Output, OutputDrive, Pull};
use embassy_nrf::interrupt::{self, InterruptExt};
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::{RNG, USBD};
use embassy_nrf::usb::Driver;
use embassy_nrf::usb::vbus_detect::HardwareVbusDetect;
use embassy_nrf::{bind_interrupts, pac, rng, usb};
use embassy_time::{Duration, Timer};
use embedded_hal_async::spi::{Operation, SpiDevice};
use keymap::{COL, ROW};
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
use rmk::host::HostService;
use rmk::keyboard::Keyboard;
use rmk::matrix::hc595_matrix::Hc595Matrix;
use rmk::processor::builtin::wpm::WpmProcessor;
use rmk::usb::UsbTransport;
use rmk::{HostResources, KeymapData, initialize_keymap_and_storage, run_all};
use static_cell::StaticCell;
use vial::{VIAL_KEYBOARD_DEF, VIAL_KEYBOARD_ID};

bind_interrupts!(struct Irqs {
    USBD => usb::InterruptHandler<USBD>;
    RNG => rng::InterruptHandler<RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler, usb::vbus_detect::InterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
});

const SK6812_COUNT: usize = 34;
const T0H_CYCLES: u32 = 12;
const T0L_CYCLES: u32 = 42;
const T1H_CYCLES: u32 = 38;
const T1L_CYCLES: u32 = 16;

const L2CAP_TXQ: u8 = 3;
const L2CAP_RXQ: u8 = 3;
const L2CAP_MTU: usize = 251;
const UNLOCK_KEYS: &[(u8, u8)] = &[(0, 0), (1, 0)];

#[derive(Clone, Copy)]
struct Color {
    red: u8,
    green: u8,
    blue: u8,
}

const RED: Color = Color {
    red: 20,
    green: 0,
    blue: 0,
};
const GREEN: Color = Color {
    red: 0,
    green: 20,
    blue: 0,
};
const BLUE: Color = Color {
    red: 0,
    green: 0,
    blue: 20,
};
const CYAN: Color = Color {
    red: 0,
    green: 16,
    blue: 16,
};
const MAGENTA: Color = Color {
    red: 16,
    green: 0,
    blue: 16,
};
const YELLOW: Color = Color {
    red: 16,
    green: 16,
    blue: 0,
};
const WHITE: Color = Color {
    red: 12,
    green: 12,
    blue: 12,
};

struct StageOutput {
    indicator_1: Output<'static>,
    indicator_2: Output<'static>,
    backlight: Output<'static>,
}

impl StageOutput {
    fn new(
        indicator_1: Output<'static>,
        indicator_2: Output<'static>,
        backlight: Output<'static>,
    ) -> Self {
        Self {
            indicator_1,
            indicator_2,
            backlight,
        }
    }

    async fn show(&mut self, stage: u8, color: Color) {
        if stage & 0b01 == 0 {
            self.indicator_1.set_low();
        } else {
            self.indicator_1.set_high();
        }

        if stage & 0b10 == 0 {
            self.indicator_2.set_low();
        } else {
            self.indicator_2.set_high();
        }

        write_solid_color(&mut self.backlight, color);
        Timer::after(Duration::from_millis(350)).await;
    }

    fn into_parts(self) -> (Output<'static>, Output<'static>, Output<'static>) {
        (self.indicator_1, self.indicator_2, self.backlight)
    }
}

fn write_bit(pin: &mut Output<'static>, high_cycles: u32, low_cycles: u32) {
    pin.set_high();
    asm::delay(high_cycles);
    pin.set_low();
    asm::delay(low_cycles);
}

fn write_byte(pin: &mut Output<'static>, byte: u8) {
    for bit in (0..8).rev() {
        if byte & (1 << bit) == 0 {
            write_bit(pin, T0H_CYCLES, T0L_CYCLES);
        } else {
            write_bit(pin, T1H_CYCLES, T1L_CYCLES);
        }
    }
}

fn write_color(pin: &mut Output<'static>, color: Color) {
    write_byte(pin, color.green);
    write_byte(pin, color.red);
    write_byte(pin, color.blue);
}

fn write_solid_color(pin: &mut Output<'static>, color: Color) {
    cortex_m::interrupt::free(|_| {
        for _ in 0..SK6812_COUNT {
            write_color(pin, color);
        }
        pin.set_low();
    });
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

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

#[embassy_executor::task]
async fn indicator_task(mut indicator_1: Output<'static>, mut indicator_2: Output<'static>) -> ! {
    loop {
        indicator_1.set_high();
        indicator_2.set_low();
        Timer::after(Duration::from_millis(500)).await;
        indicator_1.set_low();
        indicator_2.set_high();
        Timer::after(Duration::from_millis(500)).await;
    }
}

/// Same full SDC feature set as the production main.rs.
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

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    info!("On the 15 v4 BLE transport stage check firmware");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;
    nrf_config.gpiote_interrupt_priority = interrupt::Priority::P3;
    nrf_config.time_interrupt_priority = interrupt::Priority::P3;
    interrupt::USBD.set_priority(interrupt::Priority::P2);
    interrupt::CLOCK_POWER.set_priority(interrupt::Priority::P2);

    let p = embassy_nrf::init(nrf_config);

    let indicator_1 = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let indicator_2 = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    let backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);
    let mut stage = StageOutput::new(indicator_1, indicator_2, backlight);

    stage.show(1, RED).await;

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

    stage.show(2, GREEN).await;

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    let mut rng = rng::Rng::new(p.RNG, Irqs);
    let mut sdc_mem = sdc::Mem::<8192>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    stage.show(3, BLUE).await;

    let mut host_resources = HostResources::new();
    let stack = build_ble_stack(sdc, ble_addr(), &mut host_resources).await;

    stage.show(4, CYAN).await;

    pac::CLOCK.tasks_hfclkstart().write_value(1);
    while pac::CLOCK.events_hfclkstarted().read() != 1 {}

    let driver = Driver::new(p.USBD, Irqs, HardwareVbusDetect::new(Irqs));
    let flash = Flash::take(mpsl, p.NVMC);

    stage.show(5, MAGENTA).await;

    let row_pins = [
        Input::new(p.P1_14, Pull::Down),
        Input::new(p.P1_13, Pull::Down),
        Input::new(p.P1_12, Pull::Down),
    ];
    let latch = Output::new(p.P1_11, Level::Low, OutputDrive::Standard);
    let mosi = Output::new(p.P0_04, Level::Low, OutputDrive::Standard);
    let sck = Output::new(p.P0_05, Level::Low, OutputDrive::Standard);
    let spi = BitBangSpi::new(mosi, sck);

    let _vbus_sense = Input::new(p.P0_03, Pull::Down);
    let _vbat_sense_pin = p.P0_02;

    let keyboard_device_config = DeviceConfig {
        vid: 0x4F54,
        pid: 0x1537,
        manufacturer: "Hayashi",
        product_name: "On the 15 v4 X7",
        serial_number: "vial:4f543135:000001",
    };
    let vial_config = VialConfig::new(VIAL_KEYBOARD_ID, VIAL_KEYBOARD_DEF, UNLOCK_KEYS);
    let ble_battery_config = BleBatteryConfig::new(None::<Input<'static>>, false, None, false);
    let storage_config = StorageConfig {
        start_addr: 0xA0000,
        num_sectors: 6,
        clear_layout: true,
        ..Default::default()
    };
    let rmk_config = RmkConfig {
        device_config: keyboard_device_config,
        vial_config,
        ble_battery_config,
        storage_config,
    };

    let mut keymap_data = KeymapData::new(keymap::get_default_keymap());
    let key_config = PositionalConfig::default();
    let mut behavior_config = BehaviorConfig::default();
    let (keymap, mut storage) = initialize_keymap_and_storage(
        &mut keymap_data,
        flash,
        &storage_config,
        &mut behavior_config,
        &key_config,
    )
    .await;

    stage.show(6, YELLOW).await;

    let debouncer = DefaultDebouncer::new();
    let mut matrix =
        Hc595Matrix::<_, _, _, _, ROW, COL>::new(spi, latch, row_pins, debouncer).await;
    let mut keyboard = Keyboard::new(&keymap);
    let host_ctx = rmk::host::KeyboardContext::new(&keymap);
    let mut host_service = HostService::new(&host_ctx, &rmk_config);
    let mut usb_transport = UsbTransport::new(driver, rmk_config.device_config);
    let mut ble_transport = BleTransport::new(&stack, rmk_config).await;
    let mut wpm_processor = WpmProcessor::new();
    // No watchdog in this binary on purpose (keeps R3 out of this measurement).
    let _wdt = p.WDT;

    stage.show(7, WHITE).await;

    // From here on the indicator LEDs switch to the heartbeat pattern.
    // Heartbeat blinking = run_all! (including ble_transport) is being polled.
    // Frozen LEDs = a panic or non-yielding loop inside run_all!.
    let (indicator_1, indicator_2, _backlight) = stage.into_parts();
    spawner.spawn(indicator_task(indicator_1, indicator_2).unwrap());

    run_all!(
        matrix,
        storage,
        usb_transport,
        ble_transport,
        wpm_processor,
        keyboard,
        host_service
    )
    .await;
}
