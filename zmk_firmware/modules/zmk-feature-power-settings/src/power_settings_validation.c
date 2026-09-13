/* SPDX-License-Identifier: MIT */

#include <stddef.h>

#include <zmk_feature/power_settings.h>

#define MIN_IDLE_TIMEOUT_MS ZMK_POWER_SETTINGS_MIN_IDLE_TIMEOUT_MS
#define MAX_IDLE_TIMEOUT_MS ZMK_POWER_SETTINGS_MAX_IDLE_TIMEOUT_MS
#define MIN_DEEP_SLEEP_TIMEOUT_MS ZMK_POWER_SETTINGS_MIN_DEEP_SLEEP_TIMEOUT_MS
#define MAX_DEEP_SLEEP_TIMEOUT_MS ZMK_POWER_SETTINGS_MAX_DEEP_SLEEP_TIMEOUT_MS

static bool valid_timeout(uint32_t value, uint32_t minimum, uint32_t maximum) {
    return value == 0U || (value >= minimum && value <= maximum);
}

bool zmk_power_settings_is_valid(const struct zmk_power_settings *settings) {
    if (settings == NULL ||
        !valid_timeout(settings->idle_timeout_ms, MIN_IDLE_TIMEOUT_MS,
                       MAX_IDLE_TIMEOUT_MS) ||
        !valid_timeout(settings->deep_sleep_timeout_ms,
                       MIN_DEEP_SLEEP_TIMEOUT_MS, MAX_DEEP_SLEEP_TIMEOUT_MS)) {
        return false;
    }

    return settings->idle_timeout_ms == 0U ||
           settings->deep_sleep_timeout_ms == 0U ||
           settings->deep_sleep_timeout_ms >= settings->idle_timeout_ms;
}
