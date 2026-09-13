/* SPDX-License-Identifier: MIT */

#include <stddef.h>

#include <zmk_feature/power_settings.h>

static bool settings_equal(const struct zmk_power_settings *left,
                           const struct zmk_power_settings *right) {
    return left->idle_timeout_ms == right->idle_timeout_ms &&
           left->deep_sleep_timeout_ms == right->deep_sleep_timeout_ms;
}

enum zmk_power_settings_sync_decision zmk_power_settings_sync_resolve(
    const struct zmk_power_settings_snapshot *current,
    const struct zmk_power_settings_snapshot *incoming) {
    if (current == NULL || incoming == NULL ||
        !zmk_power_settings_is_valid(&current->settings) ||
        (incoming->status == ZMK_POWER_SETTINGS_SYNC_STATUS_AVAILABLE &&
         !zmk_power_settings_is_valid(&incoming->settings))) {
        return ZMK_POWER_SETTINGS_SYNC_INVALID;
    }
    if (incoming->status == ZMK_POWER_SETTINGS_SYNC_STATUS_UNAVAILABLE) {
        return ZMK_POWER_SETTINGS_SYNC_DEFER_UNAVAILABLE;
    }
    if (incoming->status == ZMK_POWER_SETTINGS_SYNC_STATUS_TIMEOUT) {
        return ZMK_POWER_SETTINGS_SYNC_DEFER_TIMEOUT;
    }
    if (incoming->generation > current->generation) {
        return ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING;
    }
    if (incoming->generation < current->generation) {
        return ZMK_POWER_SETTINGS_SYNC_REJECT_STALE;
    }
    if (settings_equal(&current->settings, &incoming->settings)) {
        return ZMK_POWER_SETTINGS_SYNC_KEEP_CURRENT;
    }

    if (incoming->source_id == ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID &&
        current->source_id != ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID) {
        return ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING;
    }
    return ZMK_POWER_SETTINGS_SYNC_REJECT_CONFLICT;
}
