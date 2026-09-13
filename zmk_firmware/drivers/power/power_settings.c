/* SPDX-License-Identifier: MIT */

#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>

#include <zmk/activity.h>

#include <onthe15/power_settings.h>

#define POWER_SETTINGS_PATH "onthe15/power_v1/state"
#define MIN_IDLE_TIMEOUT_MS 1000U
#define MAX_IDLE_TIMEOUT_MS 3600000U
#define MIN_DEEP_SLEEP_TIMEOUT_MS 60000U
#define MAX_DEEP_SLEEP_TIMEOUT_MS 86400000U

static struct onthe15_power_settings current_settings = {
    .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
    .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
};
static struct onthe15_power_settings saved_settings = {
    .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
    .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
};
K_MUTEX_DEFINE(power_settings_lock);

static bool valid_timeout(uint32_t value, uint32_t minimum, uint32_t maximum) {
    return value == 0U || (value >= minimum && value <= maximum);
}

static bool valid_settings(const struct onthe15_power_settings *settings) {
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

static int apply_settings(const struct onthe15_power_settings *settings) {
    return zmk_activity_set_timeouts(settings->idle_timeout_ms,
                                     settings->deep_sleep_timeout_ms);
}

#if IS_ENABLED(CONFIG_SETTINGS)
static int power_settings_set(const char *name, size_t len,
                              settings_read_cb read_cb, void *cb_arg) {
    const char *next;
    struct onthe15_power_settings loaded;

    if (!settings_name_steq(name, "state", &next) || next) {
        return -ENOENT;
    }
    if (len != sizeof(loaded)) {
        return -EINVAL;
    }

    int rc = read_cb(cb_arg, &loaded, sizeof(loaded));
    if (rc < 0) {
        return rc;
    }
    if (!valid_settings(&loaded)) {
        return -EINVAL;
    }

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    current_settings = loaded;
    saved_settings = loaded;
    k_mutex_unlock(&power_settings_lock);
    return 0;
}

static int power_settings_commit(void) {
    struct onthe15_power_settings settings;
    onthe15_power_settings_get(&settings);
    return apply_settings(&settings);
}

SETTINGS_STATIC_HANDLER_DEFINE(onthe15_power, "onthe15/power_v1", NULL,
                               power_settings_set, power_settings_commit, NULL);
#endif

void onthe15_power_settings_get(struct onthe15_power_settings *settings) {
    if (settings == NULL) {
        return;
    }
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    *settings = current_settings;
    k_mutex_unlock(&power_settings_lock);
}

bool onthe15_power_settings_has_unsaved_changes(void) {
    bool dirty;
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    dirty = current_settings.idle_timeout_ms != saved_settings.idle_timeout_ms ||
            current_settings.deep_sleep_timeout_ms !=
                saved_settings.deep_sleep_timeout_ms;
    k_mutex_unlock(&power_settings_lock);
    return dirty;
}

int onthe15_power_settings_set_memory(
    const struct onthe15_power_settings *settings) {
    if (!valid_settings(settings)) {
        return -EINVAL;
    }

    int rc = apply_settings(settings);
    if (rc < 0) {
        return rc;
    }

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    current_settings = *settings;
    k_mutex_unlock(&power_settings_lock);
    return 0;
}

int onthe15_power_settings_save(void) {
    struct onthe15_power_settings settings;
    onthe15_power_settings_get(&settings);

#if IS_ENABLED(CONFIG_SETTINGS)
    int rc = settings_save_one(POWER_SETTINGS_PATH, &settings, sizeof(settings));
    if (rc < 0) {
        return rc;
    }
#endif

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    saved_settings = settings;
    k_mutex_unlock(&power_settings_lock);
    return 0;
}

void onthe15_power_settings_discard(void) {
    struct onthe15_power_settings settings;
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    settings = saved_settings;
    k_mutex_unlock(&power_settings_lock);
    (void)onthe15_power_settings_set_memory(&settings);
}

void onthe15_power_settings_reset(void) {
    const struct onthe15_power_settings defaults = {
        .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
        .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
    };
    (void)onthe15_power_settings_set_memory(&defaults);
}

