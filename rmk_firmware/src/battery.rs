use core::sync::atomic::{AtomicBool, AtomicU8, Ordering};

use defmt::{info, warn};
use embassy_nrf::saadc::Saadc;
use embassy_time::{Duration, Timer};
use rmk::core_traits::Runnable;
use rmk::event::{BatteryStatusEvent, publish_event};
use rmk::types::battery::{BatteryStatus, ChargeState};

const SAMPLE_INTERVAL: Duration = Duration::from_secs(60);
const VOLTAGE_AVERAGE_SAMPLES: usize = 3;

pub const LOW_BATTERY_WARNING_USER_ID: u8 = 26;
pub const BATTERY_TYPE_USER_ID: u8 = 27;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum BatteryType {
    Nimh = 0,
    Alkaline = 1,
}

static LOW_BATTERY_WARNING_ENABLED: AtomicBool = AtomicBool::new(true);
static BATTERY_TYPE: AtomicU8 = AtomicU8::new(BatteryType::Nimh as u8);

// RL12 1 MOhm above the sense node and RL13 470 kOhm below it.
const DIVIDER_OUTPUT_OHMS: u32 = 470_000;
const DIVIDER_TOTAL_OHMS: u32 = 1_470_000;

// Panasonic BK-4MCC typical 160 mA discharge curve at 25 C, after a one-hour
// rest. The measured pack voltage is divided by the configured series cell
// count before this per-cell table is applied.
const ENELOOP_AAA_CURVE: &[(u16, u8)] = &[
    (1000, 0),
    (1130, 5),
    (1200, 10),
    (1242, 20),
    (1258, 30),
    (1268, 40),
    (1275, 50),
    (1282, 60),
    (1290, 70),
    (1305, 80),
    (1340, 90),
    (1450, 100),
];

// Energizer EN92 AAA, 21 C, 24-ohm intermittent low-drain curve, digitized by
// elapsed service fraction. This is the same provisional manufacturer-derived
// table used by the ZMK firmware.
const ENERGIZER_EN92_CURVE: &[(u16, u8)] = &[
    (800, 0),
    (900, 5),
    (1000, 12),
    (1100, 25),
    (1200, 45),
    (1250, 58),
    (1300, 70),
    (1350, 80),
    (1400, 88),
    (1450, 94),
    (1500, 98),
    (1520, 100),
];

pub fn configure(low_battery_warning_enabled: bool, battery_type: u8) {
    LOW_BATTERY_WARNING_ENABLED.store(low_battery_warning_enabled, Ordering::Relaxed);
    BATTERY_TYPE.store(
        normalize_battery_type(battery_type) as u8,
        Ordering::Relaxed,
    );
}

pub fn low_battery_warning_enabled() -> bool {
    LOW_BATTERY_WARNING_ENABLED.load(Ordering::Relaxed)
}

pub fn battery_type() -> BatteryType {
    normalize_battery_type(BATTERY_TYPE.load(Ordering::Relaxed))
}

pub fn set_low_battery_warning_enabled(enabled: bool) {
    LOW_BATTERY_WARNING_ENABLED.store(enabled, Ordering::Relaxed);
}

pub fn set_battery_type(value: u8) -> BatteryType {
    let value = normalize_battery_type(value);
    BATTERY_TYPE.store(value as u8, Ordering::Relaxed);
    value
}

pub fn toggle_battery_type() -> BatteryType {
    let next = match battery_type() {
        BatteryType::Nimh => BatteryType::Alkaline,
        BatteryType::Alkaline => BatteryType::Nimh,
    };
    BATTERY_TYPE.store(next as u8, Ordering::Relaxed);
    next
}

fn normalize_battery_type(value: u8) -> BatteryType {
    if value == BatteryType::Alkaline as u8 {
        BatteryType::Alkaline
    } else {
        BatteryType::Nimh
    }
}

pub struct BatteryMonitor<'a> {
    adc: Saadc<'a, 1>,
    series_cell_count: u8,
    samples: [u16; VOLTAGE_AVERAGE_SAMPLES],
    sample_sum: u32,
    sample_count: usize,
    sample_index: usize,
}

impl<'a> BatteryMonitor<'a> {
    pub fn new(adc: Saadc<'a, 1>, series_cell_count: u8) -> Self {
        assert!(series_cell_count > 0);
        Self {
            adc,
            series_cell_count,
            samples: [0; VOLTAGE_AVERAGE_SAMPLES],
            sample_sum: 0,
            sample_count: 0,
            sample_index: 0,
        }
    }

    fn record_sample(&mut self, pack_mv: u16) -> u16 {
        if self.sample_count == VOLTAGE_AVERAGE_SAMPLES {
            self.sample_sum -= self.samples[self.sample_index] as u32;
        } else {
            self.sample_count += 1;
        }

        self.samples[self.sample_index] = pack_mv;
        self.sample_sum += pack_mv as u32;
        self.sample_index = (self.sample_index + 1) % VOLTAGE_AVERAGE_SAMPLES;

        (self.sample_sum / self.sample_count as u32) as u16
    }

    async fn sample_and_publish(&mut self) {
        let mut raw = [0_i16; 1];
        self.adc.sample(&mut raw).await;

        if raw[0] < 0 {
            warn!("negative battery ADC sample: {}", raw[0]);
            return;
        }

        let pack_mv = raw_to_pack_mv(raw[0] as u16);
        let averaged_pack_mv = self.record_sample(pack_mv);
        let cell_mv = averaged_pack_mv / self.series_cell_count as u16;
        let level = state_of_charge(battery_type(), cell_mv);

        info!(
            "battery: raw={}, pack={}mV, average={}mV, cell={}mV, level={}%",
            raw[0], pack_mv, averaged_pack_mv, cell_mv, level
        );

        publish_event(BatteryStatusEvent(BatteryStatus::Available {
            charge_state: ChargeState::Discharging,
            level: Some(level),
        }));
    }
}

impl Runnable for BatteryMonitor<'_> {
    async fn run(&mut self) -> ! {
        self.adc.calibrate().await;

        loop {
            self.sample_and_publish().await;
            Timer::after(SAMPLE_INTERVAL).await;
        }
    }
}

fn raw_to_pack_mv(raw: u16) -> u16 {
    // Internal 0.6 V reference with gain 1/6 gives a 3.6 V full-scale input.
    // Keep the divider calculation in u64 so intermediate multiplication
    // cannot overflow on a malformed or saturated sample.
    let sense_mv = (raw as u64 * 3_600 + 2_048) / 4_096;
    ((sense_mv * DIVIDER_TOTAL_OHMS as u64 + (DIVIDER_OUTPUT_OHMS / 2) as u64)
        / DIVIDER_OUTPUT_OHMS as u64) as u16
}

fn state_of_charge(battery_type: BatteryType, cell_mv: u16) -> u8 {
    let curve = match battery_type {
        BatteryType::Nimh => ENELOOP_AAA_CURVE,
        BatteryType::Alkaline => ENERGIZER_EN92_CURVE,
    };
    interpolate(curve, cell_mv)
}

fn interpolate(curve: &[(u16, u8)], cell_mv: u16) -> u8 {
    if cell_mv <= curve[0].0 {
        return curve[0].1;
    }

    for points in curve.windows(2) {
        let (lower_mv, lower_percent) = points[0];
        let (upper_mv, upper_percent) = points[1];
        if cell_mv <= upper_mv {
            return lower_percent
                + ((cell_mv - lower_mv) as u32 * (upper_percent - lower_percent) as u32
                    / (upper_mv - lower_mv) as u32) as u8;
        }
    }

    curve[curve.len() - 1].1
}

#[cfg(test)]
mod tests {
    use super::{BatteryType, normalize_battery_type, raw_to_pack_mv, state_of_charge};

    #[test]
    fn curve_matches_reference_points_and_interpolates() {
        assert_eq!(state_of_charge(BatteryType::Nimh, 1000), 0);
        assert_eq!(state_of_charge(BatteryType::Nimh, 1242), 20);
        assert_eq!(state_of_charge(BatteryType::Nimh, 1275), 50);
        assert_eq!(state_of_charge(BatteryType::Nimh, 1450), 100);
        assert_eq!(state_of_charge(BatteryType::Nimh, 1278), 55);
    }

    #[test]
    fn alkaline_curve_matches_reference_points_and_clamps() {
        assert_eq!(state_of_charge(BatteryType::Alkaline, 799), 0);
        assert_eq!(state_of_charge(BatteryType::Alkaline, 1200), 45);
        assert_eq!(state_of_charge(BatteryType::Alkaline, 1300), 70);
        assert_eq!(state_of_charge(BatteryType::Alkaline, 1500), 98);
        assert_eq!(state_of_charge(BatteryType::Alkaline, 1600), 100);
    }

    #[test]
    fn unknown_battery_type_falls_back_to_nimh() {
        assert_eq!(normalize_battery_type(0), BatteryType::Nimh);
        assert_eq!(normalize_battery_type(1), BatteryType::Alkaline);
        assert_eq!(normalize_battery_type(255), BatteryType::Nimh);
    }

    #[test]
    fn adc_conversion_applies_board_divider() {
        // About 0.8 V at the sense node becomes about 2.5 V at the pack.
        assert!((raw_to_pack_mv(910) as i32 - 2500).abs() <= 5);
    }
}
