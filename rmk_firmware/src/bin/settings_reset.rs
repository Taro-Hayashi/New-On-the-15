//! One-shot reset image for RMK settings stored in internal flash.
//!
//! This erases only `0xA0000..0xA6000`, the six sectors reserved by every
//! On the 15 v4 RMK production binary. Both indicators turn on after the erase
//! completes, then the firmware automatically returns to the Adafruit UF2
//! bootloader so a normal image can be flashed immediately.

#![no_std]
#![no_main]

use defmt::info;
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use embassy_nrf::nvmc::Nvmc;
use embassy_time::{Duration, Timer};
use embedded_storage::nor_flash::NorFlash;
use nrf_mpsl as _;
use panic_probe as _;

const RMK_STORAGE_START: u32 = 0xA0000;
const RMK_STORAGE_END: u32 = 0xA6000;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    info!("Erasing On the 15 v4 RMK settings");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;

    let p = embassy_nrf::init(nrf_config);

    let mut indicator_green = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let mut indicator_red = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    let _backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);

    let mut flash = Nvmc::new(p.NVMC);
    flash
        .erase(RMK_STORAGE_START, RMK_STORAGE_END)
        .expect("RMK settings erase failed");
    drop(flash);

    indicator_green.set_high();
    indicator_red.set_high();
    info!("RMK settings erased");

    // Keep the success indication visible before returning to UF2. The
    // bootloader then waits for the user to copy a normal firmware image.
    Timer::after(Duration::from_millis(750)).await;
    rmk::boot::jump_to_bootloader();

    unreachable!()
}
