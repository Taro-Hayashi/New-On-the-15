//! VBUS-linked backlight check.
//!
//! NOTE: this feature has been integrated into main.rs. This binary is kept
//! as-is for isolated regression testing.
//!
//! Full production configuration (USB + BLE + Vial + watchdog + Mem::<8192> +
//! MPSL timeslot flash) so the board keeps working as a keyboard, plus one
//! extra task that polls vbus_sense (P0.03, divider from the 5V rail) and
//! drives the SK6812 backlight (P1.15) only while 5V is present.
//!
//! Hardware rationale: the SK6812 chain lives on the 5V domain. On battery
//! the 5V rail is down, and driving P1.15 high would back-power the dead
//! domain through the SK6812 protection diodes. Therefore the data line is
//! held Low whenever 5V is not detected.
//!
//! VBUS detection follows the field-proven method from
//! rmk_firmware/src/bin/battery_usb_backlight_check.rs: plain digital read of
//! P0.03 with an internal pull-down (no ADC, no explicit threshold - the
//! divider output is read as a logic level). Debounced here with 2
//! consecutive matching reads at a 100 ms poll interval.

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
use rmk::watchdog::Nrf52Watchdog;
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

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

const L2CAP_TXQ: u8 = 3;
const L2CAP_RXQ: u8 = 3;
const L2CAP_MTU: usize = 251;
const UNLOCK_KEYS: &[(u8, u8)] = &[(0, 0), (1, 0)];

// SK6812 bit-bang parameters, verified on hardware by led_check.rs.
const SK6812_COUNT: usize = 34;
const T0H_CYCLES: u32 = 12;
const T0L_CYCLES: u32 = 42;
const T1H_CYCLES: u32 = 38;
const T1L_CYCLES: u32 = 16;

/// Modest fixed backlight color (brightness values proven in led_check.rs).
const BACKLIGHT_ON: Color = Color {
    red: 8,
    green: 8,
    blue: 8,
};

/// vbus_sense poll interval.
const VBUS_POLL: Duration = Duration::from_millis(100);
/// Consecutive matching reads required to accept a state change.
const VBUS_DEBOUNCE_COUNT: u8 = 2;

#[derive(Clone, Copy)]
struct Color {
    red: u8,
    green: u8,
    blue: u8,
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

/// Sends one full frame to the SK6812 chain inside a critical section.
///
/// NOTE (MPSL/BLE coexistence): masking interrupts blocks the MPSL RADIO /
/// TIMER0 / RTC0 high-priority handlers. One frame here is 34 LEDs x 24 bits
/// x ~1.4 us ~= 1.1 ms, which can glitch an ongoing BLE connection event.
/// Acceptable for this test firmware, but do NOT extend this critical
/// section (e.g. multiple frames, animations) - long blocks starve the MPSL
/// radio timeslots and can drop the BLE link entirely.
fn write_solid_color(pin: &mut Output<'static>, color: Color) {
    cortex_m::interrupt::free(|_| {
        for _ in 0..SK6812_COUNT {
            write_color(pin, color);
        }
        pin.set_low();
    });
}

/// Polls vbus_sense and gates the SK6812 backlight on 5V presence.
///
/// - 5V detected (debounced): send the ON color once.
/// - 5V lost (debounced): stop transmitting, hold the data line Low so the
///   unpowered 5V domain is never back-powered through P1.15.
#[embassy_executor::task]
async fn backlight_vbus_task(vbus_sense: Input<'static>, mut backlight: Output<'static>) -> ! {
    let mut powered = false;
    let mut pending: Option<bool> = None;
    let mut pending_count: u8 = 0;

    loop {
        let raw = vbus_sense.is_high();

        if raw == powered {
            // Stable in the current state; cancel any half-finished debounce.
            pending = None;
            pending_count = 0;
        } else {
            // Candidate state change; count consecutive confirmations.
            if pending == Some(raw) {
                pending_count += 1;
            } else {
                pending = Some(raw);
                pending_count = 1;
            }

            if pending_count >= VBUS_DEBOUNCE_COUNT {
                powered = raw;
                pending = None;
                pending_count = 0;

                if powered {
                    info!("5V detected: backlight on");
                    write_solid_color(&mut backlight, BACKLIGHT_ON);
                } else {
                    info!("5V lost: backlight line held low");
                    // Do not transmit anything: the 5V rail is down. Just
                    // make sure the data line idles Low.
                    backlight.set_low();
                }
            }
        }

        Timer::after(VBUS_POLL).await;
    }
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
    info!("On the 15 v4 RMK firmware (backlight VBUS check)");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;
    nrf_config.gpiote_interrupt_priority = interrupt::Priority::P3;
    nrf_config.time_interrupt_priority = interrupt::Priority::P3;
    interrupt::USBD.set_priority(interrupt::Priority::P2);
    interrupt::CLOCK_POWER.set_priority(interrupt::Priority::P2);

    let p = embassy_nrf::init(nrf_config);

    let led_indicator_1 = Output::new(p.P0_28, Level::High, OutputDrive::Standard);
    let led_indicator_2 = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    // Backlight data line idles Low until 5V is confirmed (no back-powering).
    let led_backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);
    spawner.spawn(indicator_task(led_indicator_1, led_indicator_2).unwrap());

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
    // 8192 bytes: confirmed on hardware - the full SDC feature set does NOT
    // fit in 4096 (mem4096-check fails to boot; R2).
    let mut sdc_mem = sdc::Mem::<8192>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));
    let mut host_resources = HostResources::new();
    let stack = build_ble_stack(sdc, ble_addr(), &mut host_resources).await;

    pac::CLOCK.tasks_hfclkstart().write_value(1);
    while pac::CLOCK.events_hfclkstarted().read() != 1 {}

    let driver = Driver::new(p.USBD, Irqs, HardwareVbusDetect::new(Irqs));
    // MPSL timeslot-aware flash, same as the working main.rs.
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

    // Same proven detection as battery_usb_backlight_check.rs: digital read
    // of the 5V-rail divider on P0.03 with an internal pull-down.
    let vbus_sense = Input::new(p.P0_03, Pull::Down);
    let _vbat_sense_pin = p.P0_02;
    spawner.spawn(backlight_vbus_task(vbus_sense, led_backlight).unwrap());

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

    let debouncer = DefaultDebouncer::new();
    let mut matrix =
        Hc595Matrix::<_, _, _, _, ROW, COL>::new(spi, latch, row_pins, debouncer).await;
    let mut keyboard = Keyboard::new(&keymap);
    let host_ctx = rmk::host::KeyboardContext::new(&keymap);
    let mut host_service = HostService::new(&host_ctx, &rmk_config);
    let mut usb_transport = UsbTransport::new(driver, rmk_config.device_config);
    let mut ble_transport = BleTransport::new(&stack, rmk_config).await;
    let mut wpm_processor = WpmProcessor::new();
    let mut watchdog_runner = Nrf52Watchdog::default_runner(p.WDT);

    run_all!(
        matrix,
        storage,
        usb_transport,
        ble_transport,
        wpm_processor,
        keyboard,
        host_service,
        watchdog_runner
    )
    .await;
}
