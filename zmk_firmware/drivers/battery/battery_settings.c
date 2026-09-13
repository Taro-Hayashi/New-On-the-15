/* SPDX-License-Identifier: MIT */
#define DT_DRV_COMPAT onthe15_behavior_battery_settings

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>
#include <drivers/behavior.h>
#include <zmk/behavior.h>
#include <zmk/event_manager.h>
#include <dt-bindings/onthe15/settings.h>
#include "battery_settings.h"
#include "../status/status_indicator.h"

#if IS_ENABLED(CONFIG_ONTHE15_BATTERY_SETTINGS_SPLIT_SYNC)
#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
#include <zmk/split/central.h>
#else
#include <zmk/events/split_peripheral_status_changed.h>
#endif
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(onthe15_battery_sync, CONFIG_ZMK_LOG_LEVEL);

/*
 * The battery settings as the central sends them, and the peripheral's request
 * for them once it has a link to ask over.
 *
 * Both fields are the peripheral's business as much as the central's: each
 * half measures its own cell, turns that voltage into a percentage with the
 * chemistry curve it holds, and raises its own low warning. Left unsynced, the
 * two halves report on different curves after a change made from Studio.
 * `save` carries whether the peripheral should persist what it applied.
 */
struct onthe15_battery_sync {
    uint8_t source;
    bool save;
    struct onthe15_battery_settings settings;
};

struct onthe15_battery_sync_request {
    uint8_t source;
};

ZMK_EVENT_DECLARE(onthe15_battery_sync);
ZMK_EVENT_DECLARE(onthe15_battery_sync_request);
#endif

static struct onthe15_battery_settings state = ONTHE15_BATTERY_SETTINGS_DEFAULT;
static struct onthe15_battery_settings saved_state = ONTHE15_BATTERY_SETTINGS_DEFAULT;
K_MUTEX_DEFINE(state_lock);

bool onthe15_battery_low_warning_enabled(void) {
    bool enabled;
    k_mutex_lock(&state_lock, K_FOREVER);
    enabled = state.low_warning_enabled;
    k_mutex_unlock(&state_lock);
    return enabled;
}
enum onthe15_battery_type onthe15_battery_type_get(void) {
    enum onthe15_battery_type type;
    k_mutex_lock(&state_lock, K_FOREVER);
    type = state.battery_type == ONTHE15_BATTERY_ALKALINE ? ONTHE15_BATTERY_ALKALINE
                                                          : ONTHE15_BATTERY_NIMH;
    k_mutex_unlock(&state_lock);
    return type;
}

void onthe15_battery_settings_get(struct onthe15_battery_settings *settings) {
    if (!settings) return;
    k_mutex_lock(&state_lock, K_FOREVER);
    *settings = state;
    k_mutex_unlock(&state_lock);
}

bool onthe15_battery_settings_has_unsaved_changes(void) {
    bool dirty;
    k_mutex_lock(&state_lock, K_FOREVER);
    dirty = state.low_warning_enabled != saved_state.low_warning_enabled ||
            state.battery_type != saved_state.battery_type;
    k_mutex_unlock(&state_lock);
    return dirty;
}

static int apply_settings(const struct onthe15_battery_settings *settings) {
    if (!settings || settings->battery_type > ONTHE15_BATTERY_ALKALINE) return -EINVAL;

    bool warning_changed;
    bool type_changed;
    k_mutex_lock(&state_lock, K_FOREVER);
    warning_changed = state.low_warning_enabled != settings->low_warning_enabled;
    type_changed = state.battery_type != settings->battery_type;
    state = *settings;
    k_mutex_unlock(&state_lock);

#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR)
    if (warning_changed) onthe15_status_battery_settings_changed(settings->low_warning_enabled);
    if (type_changed) onthe15_status_battery_type_changed((enum onthe15_battery_type)settings->battery_type);
#endif
    return 0;
}

#if IS_ENABLED(CONFIG_ONTHE15_BATTERY_SETTINGS_SPLIT_SYNC)
ZMK_EVENT_IMPL(onthe15_battery_sync);
ZMK_EVENT_IMPL(onthe15_battery_sync_request);

/* Turn a received relay frame back into the event, on either half. */
ZMK_RELAY_EVENT_HANDLE(onthe15_battery_sync, bas, source);
ZMK_RELAY_EVENT_HANDLE(onthe15_battery_sync_request, bar, source);

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
ZMK_RELAY_EVENT_CENTRAL_TO_PERIPHERAL(onthe15_battery_sync, bas, source);
#else
ZMK_RELAY_EVENT_PERIPHERAL_TO_CENTRAL(onthe15_battery_sync_request, bar, source);
#endif

static void sync_settings_to_peripherals(bool save) {
#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
    struct onthe15_battery_sync ev = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
        .save = save,
    };

    onthe15_battery_settings_get(&ev.settings);
    raise_onthe15_battery_sync(ev);
#else
    ARG_UNUSED(save);
#endif
}

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
static int battery_sync_request_listener(const zmk_event_t *event) {
    if (as_onthe15_battery_sync_request(event) != NULL) {
        sync_settings_to_peripherals(false);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_battery_sync_answer, battery_sync_request_listener);
ZMK_SUBSCRIPTION(onthe15_battery_sync_answer, onthe15_battery_sync_request);
#else
/*
 * Ask for the central's copy, and keep asking until an answer arrives. See the
 * same retry in drivers/status/status_indicator.c for why one request at
 * connect time is not enough.
 */
#define SYNC_REQUEST_MAX_ATTEMPTS 8
#define SYNC_REQUEST_RETRY_DELAY K_MSEC(750)

static void battery_sync_request_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(battery_sync_request_work, battery_sync_request_work_handler);
static uint8_t battery_sync_request_attempts;

static void battery_sync_request_work_handler(struct k_work *work) {
    const struct onthe15_battery_sync_request request = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
    };

    raise_onthe15_battery_sync_request(request);

    if (++battery_sync_request_attempts < SYNC_REQUEST_MAX_ATTEMPTS) {
        k_work_reschedule(&battery_sync_request_work, SYNC_REQUEST_RETRY_DELAY);
    }
}

/*
 * Applied without going back through the public setter, which would try to
 * relay it onwards.
 */
static int battery_sync_listener(const zmk_event_t *event) {
    const struct onthe15_battery_sync *ev = as_onthe15_battery_sync(event);

    if (ev != NULL) {
        /* The answer arrived; stop asking. */
        k_work_cancel_delayable(&battery_sync_request_work);
        (void)apply_settings(&ev->settings);
        if (ev->save) {
            (void)onthe15_battery_settings_save();
        }
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_battery_sync_apply, battery_sync_listener);
ZMK_SUBSCRIPTION(onthe15_battery_sync_apply, onthe15_battery_sync);

static int battery_sync_request_on_connect(const zmk_event_t *event) {
    const struct zmk_split_peripheral_status_changed *split_status =
        as_zmk_split_peripheral_status_changed(event);

    if (split_status == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (split_status->connected) {
        battery_sync_request_attempts = 0;
        k_work_reschedule(&battery_sync_request_work, K_NO_WAIT);
    } else {
        k_work_cancel_delayable(&battery_sync_request_work);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_battery_sync_request_send, battery_sync_request_on_connect);
ZMK_SUBSCRIPTION(onthe15_battery_sync_request_send, zmk_split_peripheral_status_changed);
#endif
#else
static void sync_settings_to_peripherals(bool save) { ARG_UNUSED(save); }
#endif

int onthe15_battery_settings_set_memory(const struct onthe15_battery_settings *settings) {
    const int rc = apply_settings(settings);

    if (rc == 0) {
        sync_settings_to_peripherals(false);
    }
    return rc;
}

#if IS_ENABLED(CONFIG_SETTINGS)
static int battery_settings_set(const char *name, size_t len, settings_read_cb read_cb, void *cb_arg) {
    const char *next;
    void *value;
    size_t expected;
    if (settings_name_steq(name, "warning", &next) && !next) {
        value = &state.low_warning_enabled;
        expected = sizeof(state.low_warning_enabled);
    } else if (settings_name_steq(name, "type", &next) && !next) {
        value = &state.battery_type;
        expected = sizeof(state.battery_type);
    } else return -ENOENT;
    if (len != expected) return -EINVAL;
    int rc = read_cb(cb_arg, value, expected);
    if (rc >= 0 && state.battery_type > ONTHE15_BATTERY_ALKALINE) state.battery_type = ONTHE15_BATTERY_NIMH;
    if (rc >= 0) saved_state = state;
    return rc < 0 ? rc : 0;
}
SETTINGS_STATIC_HANDLER_DEFINE(onthe15_battery, "onthe15/battery_v1", NULL,
                               battery_settings_set, NULL, NULL);
#endif

int onthe15_battery_settings_save(void) {
    struct onthe15_battery_settings current;
    onthe15_battery_settings_get(&current);
#if IS_ENABLED(CONFIG_SETTINGS)
    int rc = settings_save_one("onthe15/battery_v1/warning", &current.low_warning_enabled,
                               sizeof(current.low_warning_enabled));
    if (rc < 0) return rc;
    k_mutex_lock(&state_lock, K_FOREVER);
    saved_state.low_warning_enabled = current.low_warning_enabled;
    k_mutex_unlock(&state_lock);

    rc = settings_save_one("onthe15/battery_v1/type", &current.battery_type,
                           sizeof(current.battery_type));
    if (rc < 0) return rc;
#endif
    k_mutex_lock(&state_lock, K_FOREVER);
    saved_state = current;
    k_mutex_unlock(&state_lock);
    /* Tell the other half to keep it too, so a reboot does not part them. */
    sync_settings_to_peripherals(true);
    return 0;
}

void onthe15_battery_settings_discard(void) {
    struct onthe15_battery_settings settings;
    k_mutex_lock(&state_lock, K_FOREVER);
    settings = saved_state;
    k_mutex_unlock(&state_lock);
    (void)onthe15_battery_settings_set_memory(&settings);
}

void onthe15_battery_settings_reset(void) {
    const struct onthe15_battery_settings settings = ONTHE15_BATTERY_SETTINGS_DEFAULT;
    (void)onthe15_battery_settings_set_memory(&settings);
}

static int on_binding_pressed(struct zmk_behavior_binding *binding, struct zmk_behavior_binding_event event) {
    ARG_UNUSED(event);
    struct onthe15_battery_settings settings;
    onthe15_battery_settings_get(&settings);
    if (binding->param1 == ONTHE15_BATTERY_LOW_WARNING_TOG_CMD) {
        onthe15_battery_settings_toggle_warning(&settings);
    } else if (binding->param1 == ONTHE15_BATTERY_TYPE_TOG_CMD) {
        onthe15_battery_settings_toggle_type(&settings);
    } else return -ENOTSUP;
    int rc = onthe15_battery_settings_set_memory(&settings);
    if (rc < 0) return rc;
    rc = onthe15_battery_settings_save();
    if (rc < 0) return rc;
    return ZMK_BEHAVIOR_OPAQUE;
}
static int on_binding_released(struct zmk_behavior_binding *binding, struct zmk_behavior_binding_event event) {
    return ZMK_BEHAVIOR_OPAQUE;
}
#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
static const struct behavior_parameter_value_metadata command_values[] = {
    {
        .display_name = "Low Battery Warning",
        .value = ONTHE15_BATTERY_LOW_WARNING_TOG_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Battery Type (NiMH / Alkaline)",
        .value = ONTHE15_BATTERY_TYPE_TOG_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
};

static const struct behavior_parameter_metadata_set metadata_set = {
    .param1_values = command_values,
    .param1_values_len = ARRAY_SIZE(command_values),
};

static const struct behavior_parameter_metadata metadata = {
    .sets = &metadata_set,
    .sets_len = 1,
};

static int get_parameter_metadata(const struct device *behavior,
                                  struct behavior_parameter_metadata *param_metadata) {
    ARG_UNUSED(behavior);
    *param_metadata = metadata;
    return 0;
}
#endif

static const struct behavior_driver_api api = {
    .binding_pressed = on_binding_pressed, .binding_released = on_binding_released,
    .locality = BEHAVIOR_LOCALITY_GLOBAL,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = get_parameter_metadata,
#endif
};
BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                        CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &api);
#endif
