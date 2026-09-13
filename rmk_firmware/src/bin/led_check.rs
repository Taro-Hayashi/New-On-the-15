#![no_std]
#![no_main]

use cortex_m::asm;
use defmt::info;
use defmt_rtt as _;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use embassy_time::{Duration, Timer};
use nrf_mpsl as _;
use panic_probe as _;

const SK6812_COUNT: usize = 34;

const T0H_CYCLES: u32 = 12;
const T0L_CYCLES: u32 = 42;
const T1H_CYCLES: u32 = 38;
const T1L_CYCLES: u32 = 16;

#[derive(Clone, Copy)]
struct Color {
    red: u8,
    green: u8,
    blue: u8,
}

const COLORS: [Color; 5] = [
    Color {
        red: 16,
        green: 0,
        blue: 0,
    },
    Color {
        red: 0,
        green: 16,
        blue: 0,
    },
    Color {
        red: 0,
        green: 0,
        blue: 16,
    },
    Color {
        red: 8,
        green: 8,
        blue: 8,
    },
    Color {
        red: 0,
        green: 0,
        blue: 0,
    },
];

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

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    info!("On the 15 v4 LED check firmware");

    let mut nrf_config = embassy_nrf::config::Config::default();
    nrf_config.dcdc.reg0_voltage = Some(embassy_nrf::config::Reg0Voltage::_3V3);
    nrf_config.dcdc.reg0 = true;
    nrf_config.dcdc.reg1 = true;

    let p = embassy_nrf::init(nrf_config);
    let mut indicator_1 = Output::new(p.P0_28, Level::Low, OutputDrive::Standard);
    let mut indicator_2 = Output::new(p.P0_29, Level::Low, OutputDrive::Standard);
    let mut backlight = Output::new(p.P1_15, Level::Low, OutputDrive::Standard);

    loop {
        for (index, color) in COLORS.iter().copied().enumerate() {
            if index & 1 == 0 {
                indicator_1.set_high();
                indicator_2.set_low();
            } else {
                indicator_1.set_low();
                indicator_2.set_high();
            }

            Timer::after(Duration::from_micros(300)).await;
            write_solid_color(&mut backlight, color);
            Timer::after(Duration::from_millis(600)).await;
        }
    }
}
