#![no_std]
#![no_main]

#[path = "../backlight.rs"]
mod backlight;
#[cfg(not(feature = "test-x15"))]
#[path = "../keymaps/test/single.rs"]
mod keymap;
#[cfg(feature = "test-x15")]
#[path = "../keymaps/test/x15.rs"]
mod keymap;

use core::convert::Infallible;

use defmt::info;
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Input, Level, Output, OutputDrive, Pull};
use embassy_nrf::interrupt::InterruptExt;
#[cfg(feature = "settings-reset")]
use embassy_nrf::nvmc::Nvmc;
use embassy_nrf::usb::vbus_detect::HardwareVbusDetect;
use embassy_nrf::usb::{self, Driver};
use embassy_nrf::{bind_interrupts, peripherals};
use embedded_hal_async::spi::{Operation, SpiDevice};
#[cfg(feature = "settings-reset")]
use embedded_storage::nor_flash::NorFlash;
use keymap::{COL, ROW};
use nrf_mpsl as _;
use panic_probe as _;
use rmk::config::{BehaviorConfig, DeviceConfig, PositionalConfig, RmkConfig};
use rmk::debounce::default_debouncer::DefaultDebouncer;
use rmk::host::HostService;
use rmk::keyboard::Keyboard;
use rmk::matrix::hc595_matrix::Hc595Matrix;
use rmk::processor::builtin::wpm::WpmProcessor;
use rmk::types::morse::{MorseMode, MorseProfile};
use rmk::usb::UsbTransport;
use rmk::{KeymapData, run_all};

#[cfg(not(feature = "test-x15"))]
pub const BACKLIGHT_LED_COUNT: usize = 38;
#[cfg(feature = "test-x15")]
pub const BACKLIGHT_LED_COUNT: usize = 66;

// The production backlight task also informs the low-power matrix code about
// VBUS changes. The storage-free USB check uses RMK's regular matrix instead,
// so only the compatible notification entry point is needed here.
mod low_power_hc595_matrix {
    pub fn set_vbus_present(_present: bool) {}
}

#[cfg(feature = "settings-reset")]
const RMK_STORAGE_START: u32 = 0xA0000;
#[cfg(feature = "settings-reset")]
const RMK_STORAGE_END: u32 = 0xA6000;

#[cfg(not(feature = "test-x15"))]
const PRODUCT_NAME: &str = "On the 15 v4 X7/X8 USB Check";
#[cfg(feature = "test-x15")]
const PRODUCT_NAME: &str = "On the 15 v4 X15 USB Check";

bind_interrupts!(struct Irqs {
    USBD => usb::InterruptHandler<peripherals::USBD>;
    CLOCK_POWER => usb::vbus_detect::InterruptHandler;
});

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
async fn main(_spawner: Spawner) {
    info!("On the 15 v4 USB check firmware");

    let mut config = embassy_nrf::config::Config::default();
    config.gpiote_interrupt_priority = embassy_nrf::interrupt::Priority::P3;
    config.time_interrupt_priority = embassy_nrf::interrupt::Priority::P3;
    embassy_nrf::interrupt::USBD.set_priority(embassy_nrf::interrupt::Priority::P2);
    embassy_nrf::interrupt::CLOCK_POWER.set_priority(embassy_nrf::interrupt::Priority::P2);

    let p = embassy_nrf::init(config);

    #[cfg(feature = "settings-reset")]
    let mut led_indicator_green = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    #[cfg(feature = "settings-reset")]
    let mut led_indicator_red = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    #[cfg(not(feature = "settings-reset"))]
    let _led_indicator_green = Output::new(p.P0_28, Level::High, OutputDrive::Standard);
    #[cfg(not(feature = "settings-reset"))]
    let _led_indicator_red = Output::new(p.P0_29, Level::High, OutputDrive::Standard);

    #[cfg(feature = "settings-reset")]
    {
        info!("Erasing On the 15 v4 RMK settings");
        let mut flash = Nvmc::new(p.NVMC);
        flash
            .erase(RMK_STORAGE_START, RMK_STORAGE_END)
            .expect("RMK settings erase failed");
        led_indicator_green.set_high();
        led_indicator_red.set_high();
        info!("RMK settings erased; storage-free matrix is active");
    }
    #[cfg(not(feature = "settings-reset"))]
    let _nvmc = p.NVMC;
    // Keep every SK6812 visibly lit during the hardware check: LEDs 1-6 are
    // underglow and the remaining LEDs are per-key backlight.
    backlight::configure(true, true, 12, 10, 1, 0, false, false, false, false);
    backlight::set_test_brightness_level(13); // approximately 5% of 255
    _spawner.spawn(
        backlight::backlight_vbus_task(Input::new(p.P0_03, Pull::Down), p.PWM0, p.P1_15, true)
            .unwrap(),
    );

    embassy_nrf::pac::CLOCK.tasks_hfclkstart().write_value(1);
    while embassy_nrf::pac::CLOCK.events_hfclkstarted().read() != 1 {}

    let driver = Driver::new(p.USBD, Irqs, HardwareVbusDetect::new(Irqs));

    let row_pins = [
        Input::new(p.P1_14, Pull::Down),
        Input::new(p.P1_13, Pull::Down),
        Input::new(p.P1_12, Pull::Down),
    ];
    let latch = Output::new(p.P1_11, Level::Low, OutputDrive::Standard);
    let mosi = Output::new(p.P0_04, Level::Low, OutputDrive::Standard);
    let sck = Output::new(p.P0_05, Level::Low, OutputDrive::Standard);
    let spi = BitBangSpi::new(mosi, sck);

    let keyboard_device_config = DeviceConfig {
        vid: 0x4F54,
        pid: 0x1537,
        manufacturer: "Hayashi",
        product_name: PRODUCT_NAME,
        serial_number: "vial:4f543135:000001",
    };
    let rmk_config = RmkConfig {
        device_config: keyboard_device_config,
        ..Default::default()
    };

    let mut keymap_data = KeymapData::new(keymap::get_default_keymap());
    let key_config = PositionalConfig::default();
    let mut behavior_config = BehaviorConfig::default();
    behavior_config.morse.default_profile =
        MorseProfile::new(None, Some(MorseMode::HoldOnOtherPress), Some(200), None);
    let keymap =
        rmk::keymap::KeyMap::new(&mut keymap_data, &mut behavior_config, &key_config).await;

    let debouncer = DefaultDebouncer::new();
    let mut matrix =
        Hc595Matrix::<_, _, _, _, ROW, COL>::new(spi, latch, row_pins, debouncer).await;
    let mut keyboard = Keyboard::new(&keymap);
    let host_ctx = rmk::host::KeyboardContext::new(&keymap);
    let mut host_service = HostService::new(&host_ctx, &rmk_config);
    let mut usb_transport = UsbTransport::new(driver, rmk_config.device_config);
    let mut wpm_processor = WpmProcessor::new();

    run_all!(matrix, usb_transport, wpm_processor, keyboard, host_service).await;
}
