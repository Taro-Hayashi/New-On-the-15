/* SPDX-License-Identifier: MIT */

#include <errno.h>

#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>

#include <zmk/activity.h>
#include <zmk_feature/power_settings.h>

#define POWER_SETTINGS_PATH CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH "/state"

static struct zmk_power_settings current_settings = {
    .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
    .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
};
static struct zmk_power_settings saved_settings = {
    .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
    .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
};
#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
static uint32_t settings_generation;
static zmk_power_settings_listener_t settings_listener;
#endif
K_MUTEX_DEFINE(power_settings_lock);

static bool settings_equal(const struct zmk_power_settings *left,
                           const struct zmk_power_settings *right) {
    return left->idle_timeout_ms == right->idle_timeout_ms &&
           left->deep_sleep_timeout_ms == right->deep_sleep_timeout_ms;
}

static int apply_settings(const struct zmk_power_settings *settings) {
    return zmk_activity_set_timeouts(settings->idle_timeout_ms,
                                     settings->deep_sleep_timeout_ms);
}

#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
static void notify_listener(enum zmk_power_settings_change_reason reason) {
    zmk_power_settings_listener_t listener;
    struct zmk_power_settings_snapshot snapshot;

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    listener = settings_listener;
    snapshot = (struct zmk_power_settings_snapshot){
        .source_id = ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID,
        .status = ZMK_POWER_SETTINGS_SYNC_STATUS_AVAILABLE,
        .generation = settings_generation,
        .settings = current_settings,
    };
    k_mutex_unlock(&power_settings_lock);
    if (listener != NULL) {
        listener(&snapshot, reason);
    }
}
#else
#define notify_listener(reason) ((void)(reason))
#endif

static int power_settings_set(const char *name, size_t len,
                              settings_read_cb read_cb, void *cb_arg) {
    const char *next;
    struct zmk_power_settings loaded;

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
    if (!zmk_power_settings_is_valid(&loaded)) {
        return -EINVAL;
    }

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    current_settings = loaded;
    saved_settings = loaded;
    k_mutex_unlock(&power_settings_lock);
    return 0;
}

static int power_settings_commit(void) {
    struct zmk_power_settings settings;
    zmk_power_settings_get(&settings);
    return apply_settings(&settings);
}

SETTINGS_STATIC_HANDLER_DEFINE(zmk_power_settings,
                               CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH, NULL,
                               power_settings_set, power_settings_commit, NULL);

void zmk_power_settings_get(struct zmk_power_settings *settings) {
    if (settings == NULL) {
        return;
    }
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    *settings = current_settings;
    k_mutex_unlock(&power_settings_lock);
}

void zmk_power_settings_get_saved(struct zmk_power_settings *settings) {
    if (settings == NULL) {
        return;
    }
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    *settings = saved_settings;
    k_mutex_unlock(&power_settings_lock);
}

bool zmk_power_settings_has_unsaved_changes(void) {
    bool dirty;
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    dirty = !settings_equal(&current_settings, &saved_settings);
    k_mutex_unlock(&power_settings_lock);
    return dirty;
}

#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
static int set_memory_with_reason(
    const struct zmk_power_settings *settings,
    enum zmk_power_settings_change_reason reason) {
    if (!zmk_power_settings_is_valid(settings)) {
        return -EINVAL;
    }

    int rc = apply_settings(settings);
    if (rc < 0) {
        return rc;
    }

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    if (!settings_equal(&current_settings, settings)) {
        settings_generation++;
    }
    current_settings = *settings;
    k_mutex_unlock(&power_settings_lock);
    notify_listener(reason);
    return 0;
}
#endif

int zmk_power_settings_set_memory(const struct zmk_power_settings *settings) {
#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
    return set_memory_with_reason(settings, ZMK_POWER_SETTINGS_CHANGE_APPLIED);
#else
    if (!zmk_power_settings_is_valid(settings)) {
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
#endif
}

int zmk_power_settings_save(void) {
    struct zmk_power_settings current;
    struct zmk_power_settings saved;
    zmk_power_settings_get(&current);
    zmk_power_settings_get_saved(&saved);

    if (settings_equal(&current, &saved)) {
        return 0;
    }

    int rc = settings_save_one(POWER_SETTINGS_PATH, &current, sizeof(current));
    if (rc < 0) {
        return rc;
    }

    k_mutex_lock(&power_settings_lock, K_FOREVER);
    saved_settings = current;
    k_mutex_unlock(&power_settings_lock);
    notify_listener(ZMK_POWER_SETTINGS_CHANGE_SAVED);
    return 0;
}

int zmk_power_settings_discard(void) {
    struct zmk_power_settings settings;
    zmk_power_settings_get_saved(&settings);
#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
    return set_memory_with_reason(&settings, ZMK_POWER_SETTINGS_CHANGE_DISCARDED);
#else
    return zmk_power_settings_set_memory(&settings);
#endif
}

int zmk_power_settings_reset(void) {
    const struct zmk_power_settings defaults = {
        .idle_timeout_ms = CONFIG_ZMK_IDLE_TIMEOUT,
        .deep_sleep_timeout_ms = CONFIG_ZMK_IDLE_SLEEP_TIMEOUT,
    };
#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
    return set_memory_with_reason(&defaults, ZMK_POWER_SETTINGS_CHANGE_RESET);
#else
    return zmk_power_settings_set_memory(&defaults);
#endif
}

#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS_SYNC_API)
void zmk_power_settings_sync_get_local_snapshot(
    struct zmk_power_settings_snapshot *snapshot) {
    if (snapshot == NULL) {
        return;
    }
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    *snapshot = (struct zmk_power_settings_snapshot){
        .source_id = ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID,
        .status = ZMK_POWER_SETTINGS_SYNC_STATUS_AVAILABLE,
        .generation = settings_generation,
        .settings = current_settings,
    };
    k_mutex_unlock(&power_settings_lock);
}

int zmk_power_settings_sync_apply_snapshot(
    const struct zmk_power_settings_snapshot *snapshot) {
    struct zmk_power_settings_snapshot current;
    zmk_power_settings_sync_get_local_snapshot(&current);
    if (zmk_power_settings_sync_resolve(&current, snapshot) !=
        ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING) {
        return -EALREADY;
    }

    int rc = apply_settings(&snapshot->settings);
    if (rc < 0) {
        return rc;
    }
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    current_settings = snapshot->settings;
    settings_generation = snapshot->generation;
    k_mutex_unlock(&power_settings_lock);
    notify_listener(ZMK_POWER_SETTINGS_CHANGE_SYNCHRONIZED);
    return 0;
}

int zmk_power_settings_sync_set_listener(zmk_power_settings_listener_t listener) {
    k_mutex_lock(&power_settings_lock, K_FOREVER);
    settings_listener = listener;
    k_mutex_unlock(&power_settings_lock);
    return 0;
}
#endif
