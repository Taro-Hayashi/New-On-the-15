//! Power setup for the unused onboard P25Q16H flash on XIAO nRF52840.

use embassy_nrf::qspi::{Config, DeepPowerDownConfig};

pub fn deep_power_down_config() -> Config {
    let mut config = Config::default();
    config.deep_power_down = Some(DeepPowerDownConfig {
        // Zephyr's XIAO BLE board definition specifies 3 ms to enter and
        // 8 ms to exit DPD. Embassy expresses both values in 16 us units.
        enter_time: 188,
        exit_time: 500,
    });
    config
}
