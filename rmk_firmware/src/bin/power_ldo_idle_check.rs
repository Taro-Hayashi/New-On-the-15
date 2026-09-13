//! System ON idle diagnostic matching `power-baseline-check`, except both
//! nRF52840 DC/DC regulators remain disabled (Embassy's default LDO mode).

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
    info!("On the 15 v4 power LDO idle check firmware");

    let p = embassy_nrf::init(embassy_nrf::config::Config::default());

    let _indicator_1 = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let _indicator_2 = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    let _backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);

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

    pending::<()>().await;
}
