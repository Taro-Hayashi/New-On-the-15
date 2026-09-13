#![no_std]
#![no_main]

use core::future::pending;

use defmt::info;
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use nrf_mpsl as _;
use panic_probe as _;

const SHIFT_REGISTER_BITS: usize = 16;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    info!("On the 15 v4 power baseline check firmware");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;

    let p = embassy_nrf::init(nrf_config);

    // Keep every visible or externally powered LED control inactive.
    let _indicator_1 = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let _indicator_2 = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    let _backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);

    // Clear both 74HC595s once, then stop clocking the matrix completely.
    let mut mosi = Output::new(p.P0_04, Level::Low, OutputDrive::Standard);
    let mut sck = Output::new(p.P0_05, Level::Low, OutputDrive::Standard);
    let mut latch = Output::new(p.P1_11, Level::Low, OutputDrive::Standard);
    for _ in 0..SHIFT_REGISTER_BITS {
        mosi.set_low();
        sck.set_high();
        sck.set_low();
    }
    latch.set_high();
    latch.set_low();

    // No matrix scan, BLE, USB, storage, watchdog, high-frequency clock
    // request, or periodic timer. The executor can remain in CPU sleep.
    pending::<()>().await;
}
