#pragma once

#include <stdbool.h>
#include <stdint.h>

struct zmk_power_settings {
    uint32_t idle_timeout_ms;
    uint32_t deep_sleep_timeout_ms;
};

/* Zero disables a timeout; any other value has to fall inside its range. */
#define ZMK_POWER_SETTINGS_MIN_IDLE_TIMEOUT_MS 1000U
#define ZMK_POWER_SETTINGS_MAX_IDLE_TIMEOUT_MS 3600000U
#define ZMK_POWER_SETTINGS_MIN_DEEP_SLEEP_TIMEOUT_MS 60000U
#define ZMK_POWER_SETTINGS_MAX_DEEP_SLEEP_TIMEOUT_MS 86400000U

#define ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID 0U

enum zmk_power_settings_sync_status {
    ZMK_POWER_SETTINGS_SYNC_STATUS_AVAILABLE = 0,
    ZMK_POWER_SETTINGS_SYNC_STATUS_UNAVAILABLE,
    ZMK_POWER_SETTINGS_SYNC_STATUS_TIMEOUT,
};

enum zmk_power_settings_sync_decision {
    ZMK_POWER_SETTINGS_SYNC_KEEP_CURRENT = 0,
    ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING,
    ZMK_POWER_SETTINGS_SYNC_REJECT_STALE,
    ZMK_POWER_SETTINGS_SYNC_REJECT_CONFLICT,
    ZMK_POWER_SETTINGS_SYNC_DEFER_UNAVAILABLE,
    ZMK_POWER_SETTINGS_SYNC_DEFER_TIMEOUT,
    ZMK_POWER_SETTINGS_SYNC_INVALID,
};

enum zmk_power_settings_change_reason {
    ZMK_POWER_SETTINGS_CHANGE_APPLIED = 0,
    ZMK_POWER_SETTINGS_CHANGE_SAVED,
    ZMK_POWER_SETTINGS_CHANGE_DISCARDED,
    ZMK_POWER_SETTINGS_CHANGE_RESET,
    ZMK_POWER_SETTINGS_CHANGE_SYNCHRONIZED,
};

struct zmk_power_settings_snapshot {
    uint8_t source_id;
    enum zmk_power_settings_sync_status status;
    uint32_t generation;
    struct zmk_power_settings settings;
};

struct zmk_power_settings_sync_result {
    uint32_t applied_sources;
    uint32_t failed_sources;
    uint32_t timeout_sources;
    uint32_t unavailable_sources;
};

typedef void (*zmk_power_settings_listener_t)(
    const struct zmk_power_settings_snapshot *snapshot,
    enum zmk_power_settings_change_reason reason);

bool zmk_power_settings_is_valid(const struct zmk_power_settings *settings);
void zmk_power_settings_get(struct zmk_power_settings *settings);
void zmk_power_settings_get_saved(struct zmk_power_settings *settings);
bool zmk_power_settings_has_unsaved_changes(void);
int zmk_power_settings_set_memory(const struct zmk_power_settings *settings);
int zmk_power_settings_save(void);
int zmk_power_settings_discard(void);
int zmk_power_settings_reset(void);

enum zmk_power_settings_sync_decision zmk_power_settings_sync_resolve(
    const struct zmk_power_settings_snapshot *current,
    const struct zmk_power_settings_snapshot *incoming);
void zmk_power_settings_sync_get_local_snapshot(
    struct zmk_power_settings_snapshot *snapshot);
int zmk_power_settings_sync_apply_snapshot(
    const struct zmk_power_settings_snapshot *snapshot);
int zmk_power_settings_sync_set_listener(zmk_power_settings_listener_t listener);
