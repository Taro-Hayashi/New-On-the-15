/*
 * On the 15 v4 two-LED status indicator.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stddef.h>
#include <string.h>

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>
#include <zephyr/sys/util.h>

#include <zmk/activity.h>
#include <zmk/ble.h>
#include <zmk/endpoints.h>
#include <zmk/event_manager.h>
#include <zmk/keymap.h>
#include <zmk/usb.h>
#include <zmk/events/activity_state_changed.h>
#include <zmk/events/battery_state_changed.h>
#include <zmk/events/endpoint_changed.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/events/usb_conn_state_changed.h>

#if IS_ENABLED(CONFIG_ZMK_STUDIO)
#include <zmk/studio/core.h>
#endif

#if IS_ENABLED(CONFIG_ZMK_SPLIT) && !IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
#include <zmk/events/split_peripheral_status_changed.h>
#endif

#include "status_indicator.h"
#include "../battery/battery_settings.h"

#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR_SPLIT_SYNC)
#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
#include <zmk/split/central.h>
#else
#include <zmk/events/split_peripheral_status_changed.h>
#endif
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(onthe15_status_sync, CONFIG_ZMK_LOG_LEVEL);

/*
 * The indicator settings as the central sends them, and the peripheral's
 * request for them once it has a link to ask over.
 *
 * This mirrors what the lighting module does, and for the same reason: the
 * ind_tog behavior is global, so a key toggle already lands on both halves,
 * but Studio only ever talks to the central. `save` carries whether the
 * peripheral should persist what it applied, so the halves still agree after
 * a reboot.
 */
struct onthe15_status_sync {
    uint8_t source;
    bool save;
    struct onthe15_status_settings settings;
};

struct onthe15_status_sync_request {
    uint8_t source;
};

ZMK_EVENT_DECLARE(onthe15_status_sync);
ZMK_EVENT_DECLARE(onthe15_status_sync_request);
#endif


#define LOW_BATTERY_PERCENT 20
#define LOW_BATTERY_RELEASE_PERCENT 25
#define LOW_BATTERY_CONFIRM_DELAY K_SECONDS(30)

enum low_battery_transition {
    LOW_BATTERY_TRANSITION_NONE,
    LOW_BATTERY_TRANSITION_ENTER,
    LOW_BATTERY_TRANSITION_EXIT,
};

static const struct gpio_dt_spec green_led =
    GPIO_DT_SPEC_GET(DT_NODELABEL(indicator_green), gpios);
static const struct gpio_dt_spec red_led = GPIO_DT_SPEC_GET(DT_NODELABEL(indicator_red), gpios);

enum indicator_mode {
    INDICATOR_OFF,
    INDICATOR_USB,
    INDICATOR_BLE,
    INDICATOR_DISCONNECTED,
    INDICATOR_LOW_BATTERY,
    INDICATOR_FEEDBACK_GREEN,
    INDICATOR_FEEDBACK_RED,
    INDICATOR_FEEDBACK_BATTERY_TYPE,
};

static enum indicator_mode current_mode;
static uint8_t pattern_phase;
static uint8_t battery_percent = 100;
static bool low_battery_active;
static enum low_battery_transition low_battery_transition;
static struct onthe15_status_settings indicator_settings = ONTHE15_STATUS_SETTINGS_DEFAULT;
static struct onthe15_status_settings saved_indicator_settings = ONTHE15_STATUS_SETTINGS_DEFAULT;
K_MUTEX_DEFINE(indicator_settings_lock);
static bool feedback_active;
/*
 * Studio unlock is the one pulse train that ignores the feedback switch: it
 * answers "did the key I just pressed reach the firmware", and a user who has
 * turned the other feedback off still needs that answer.
 */
static bool feedback_forced;
static bool feedback_green;
static bool feedback_battery_type;
static uint8_t feedback_pulses;
static bool feedback_first_green;
#if IS_ENABLED(CONFIG_ZMK_SPLIT) && !IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
static bool split_connected;
#endif

static void set_leds(bool green, bool red) {
#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON)
    green = true;
    red = true;
#endif
    gpio_pin_set_dt(&green_led, green);
    gpio_pin_set_dt(&red_led, red);
}

#if !IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
static bool host_endpoint_is_connected(void) {
    const struct zmk_endpoint_instance endpoint = zmk_endpoint_get_selected();

    switch (endpoint.transport) {
    case ZMK_TRANSPORT_USB:
        return zmk_usb_is_hid_ready();
    case ZMK_TRANSPORT_BLE:
        return zmk_ble_active_profile_is_connected();
    default:
        return false;
    }
}
#endif

/*
 * Layers are announced as a one-shot pulse train rather than a pattern held for
 * as long as the layer is active.
 *
 * The earlier design classified layers by index, then by display name, and both
 * broke for a different reason: the index shifted as soon as the personal keymap
 * inserted its per-OS default layers, and the name stopped matching as soon as a
 * layer was renamed over Studio. Neither could say anything about a layer the
 * firmware had never heard of.
 *
 * Pulsing the layer's own index N times says which layer was entered without the
 * driver needing to know what that layer is for, and it leaves the steady state
 * free to keep showing connection and battery. Returning to the base layer says
 * nothing: it is the resting state, and a pulse for it would fire on every
 * momentary-layer release.
 */
#define LAYER_NOTIFY_MAX_PULSES 5

static uint8_t notified_layer;

static void notify_layer_change(uint8_t layer) {
    if (layer == notified_layer) {
        return;
    }
    notified_layer = layer;

    if (layer == 0) {
        return;
    }

    struct onthe15_status_settings settings;
    onthe15_status_settings_get(&settings);
    if (!settings.layer_change_indicator_enabled) {
        return;
    }

    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = false;
    feedback_green = true;
    feedback_pulses = MIN(layer, LAYER_NOTIFY_MAX_PULSES);
    pattern_phase = 0;
}

static enum indicator_mode select_mode(void) {
    const enum zmk_activity_state activity = zmk_activity_get_state();
    const bool usb_powered = zmk_usb_is_powered();

    struct onthe15_status_settings settings;
    onthe15_status_settings_get(&settings);

    if (feedback_active) {
        if (!settings.feedback_indicator_enabled && !feedback_forced) {
            /* Drop the pulse train rather than sit on it, so the indicator
             * returns to the underlying state immediately. */
            feedback_active = false;
            feedback_forced = false;
            feedback_battery_type = false;
        } else if (feedback_battery_type) {
            return INDICATOR_FEEDBACK_BATTERY_TYPE;
        } else {
            return feedback_green ? INDICATOR_FEEDBACK_GREEN : INDICATOR_FEEDBACK_RED;
        }
    }

    if (activity == ZMK_ACTIVITY_SLEEP) {
        return INDICATOR_OFF;
    }

    const bool low_warning_enabled =
#if IS_ENABLED(CONFIG_ONTHE15_BATTERY_SETTINGS)
        onthe15_battery_low_warning_enabled();
#else
        true;
#endif
    if (low_battery_active && low_warning_enabled && !usb_powered) {
        return INDICATOR_LOW_BATTERY;
    }

#if IS_ENABLED(CONFIG_ZMK_SPLIT) && !IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
    if (!split_connected) {
        return settings.disconnected_indicator_enabled ? INDICATOR_DISCONNECTED : INDICATOR_OFF;
    }

    if (!settings.connected_indicator_enabled) {
        return INDICATOR_OFF;
    }

    return INDICATOR_BLE;
#else
    if (!host_endpoint_is_connected()) {
        /*
         * A sleeping host looks exactly like a disconnected one, so the plain
         * disconnected pattern blinked red for as long as the PC was asleep -
         * a fault indication for a perfectly normal state.
         *
         * This was first scoped to usb_powered, on the assumption that a
         * battery-powered keyboard still wants to advertise that it is not
         * connected. That was wrong: whether VBUS survives the host's sleep is
         * the host's business (many Windows machines drop it), while the
         * situation the user is in is identical either way - and on battery the
         * pattern then ran until the 15-minute deep sleep, wasting current too.
         *
         * Keep the warning for the case it is actually useful, "I am typing and
         * nothing is getting through", and go dark once the user stops. Tapping
         * any key brings it back, so nothing is really hidden.
         */
        if (activity != ZMK_ACTIVITY_ACTIVE) {
            return INDICATOR_OFF;
        }

        return settings.disconnected_indicator_enabled ? INDICATOR_DISCONNECTED : INDICATOR_OFF;
    }

    if (!settings.connected_indicator_enabled) {
        return INDICATOR_OFF;
    }

    return zmk_endpoint_get_selected().transport == ZMK_TRANSPORT_USB ? INDICATOR_USB
                                                                     : INDICATOR_BLE;
#endif
}

static void status_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(status_work, status_work_handler);

static void schedule_next(k_timeout_t delay) { k_work_reschedule(&status_work, delay); }

static void status_work_handler(struct k_work *work) {
    ARG_UNUSED(work);

    switch (current_mode) {
    case INDICATOR_OFF:
        set_leds(false, false);
        break;
    case INDICATOR_USB:
        set_leds(true, false);
        break;
    case INDICATOR_BLE:
        set_leds(true, false);
        break;
    case INDICATOR_DISCONNECTED:
        set_leds(false, pattern_phase == 0);
        schedule_next(K_MSEC(500));
        pattern_phase = (pattern_phase + 1) % 2;
        break;
    case INDICATOR_LOW_BATTERY: {
        static const uint16_t delays[] = {150, 150, 150, 150, 4400};
        set_leds(false, pattern_phase == 0 || pattern_phase == 2);
        schedule_next(K_MSEC(delays[pattern_phase]));
        pattern_phase = (pattern_phase + 1) % ARRAY_SIZE(delays);
        break;
    }
    case INDICATOR_FEEDBACK_GREEN:
    case INDICATOR_FEEDBACK_RED:
        set_leds(current_mode == INDICATOR_FEEDBACK_GREEN &&
                     pattern_phase < feedback_pulses * 2 &&
                     pattern_phase % 2 == 0,
                 current_mode == INDICATOR_FEEDBACK_RED &&
                     pattern_phase < feedback_pulses * 2 &&
                     pattern_phase % 2 == 0);
        if (pattern_phase >= feedback_pulses * 2) {
            feedback_active = false;
            feedback_forced = false;
            feedback_battery_type = false;
            current_mode = select_mode();
            pattern_phase = 0;
            schedule_next(K_NO_WAIT);
        } else {
            schedule_next(K_MSEC(150));
            pattern_phase++;
        }
        break;
    case INDICATOR_FEEDBACK_BATTERY_TYPE: {
        const bool first = pattern_phase < 2;
        const bool lit = pattern_phase % 2 == 0;
        const bool green = first ? feedback_first_green : !feedback_first_green;
        set_leds(lit && green, lit && !green);
        if (pattern_phase >= 3) {
            feedback_active = false;
            feedback_forced = false;
            feedback_battery_type = false;
            current_mode = select_mode();
            pattern_phase = 0;
            schedule_next(K_NO_WAIT);
        } else {
            pattern_phase++;
            schedule_next(K_MSEC(150));
        }
        break;
    }
    }
}

static void refresh_indicator(void) {
    current_mode = select_mode();
    pattern_phase = 0;
    k_work_reschedule(&status_work, K_NO_WAIT);
}

static void low_battery_work_handler(struct k_work *work) {
    ARG_UNUSED(work);

    if (low_battery_transition == LOW_BATTERY_TRANSITION_ENTER &&
        battery_percent <= LOW_BATTERY_PERCENT) {
        low_battery_active = true;
    } else if (low_battery_transition == LOW_BATTERY_TRANSITION_EXIT &&
               battery_percent >= LOW_BATTERY_RELEASE_PERCENT) {
        low_battery_active = false;
    }

    low_battery_transition = LOW_BATTERY_TRANSITION_NONE;
    refresh_indicator();
}

K_WORK_DELAYABLE_DEFINE(low_battery_work, low_battery_work_handler);

static void update_low_battery_state(void) {
    enum low_battery_transition requested = LOW_BATTERY_TRANSITION_NONE;

    if (!low_battery_active && battery_percent <= LOW_BATTERY_PERCENT) {
        requested = LOW_BATTERY_TRANSITION_ENTER;
    } else if (low_battery_active &&
               battery_percent >= LOW_BATTERY_RELEASE_PERCENT) {
        requested = LOW_BATTERY_TRANSITION_EXIT;
    }

    if (requested == LOW_BATTERY_TRANSITION_NONE) {
        k_work_cancel_delayable(&low_battery_work);
        low_battery_transition = LOW_BATTERY_TRANSITION_NONE;
    } else if (requested != low_battery_transition) {
        low_battery_transition = requested;
        k_work_reschedule(&low_battery_work, LOW_BATTERY_CONFIRM_DELAY);
    }
}

#if IS_ENABLED(CONFIG_SETTINGS)
static int status_settings_set(const char *name, size_t len, settings_read_cb read_cb,
                               void *cb_arg) {
    const char *next;

    /*
     * One record per switch under the existing "onthe15/status_v2" subtree
     * rather than a new versioned blob: the pre-existing "connected" record
     * keeps loading unchanged, and a board that has never stored the newer
     * switches simply keeps their defaults. No migration step is needed.
     */
    static const struct {
        const char *key;
        size_t offset;
    } fields[] = {
        {"connected", offsetof(struct onthe15_status_settings, connected_indicator_enabled)},
        {"disconnected", offsetof(struct onthe15_status_settings, disconnected_indicator_enabled)},
        {"layer_change", offsetof(struct onthe15_status_settings, layer_change_indicator_enabled)},
        {"feedback", offsetof(struct onthe15_status_settings, feedback_indicator_enabled)},
    };

    for (size_t i = 0; i < ARRAY_SIZE(fields); i++) {
        if (!settings_name_steq(name, fields[i].key, &next) || next) {
            continue;
        }

        if (len != sizeof(bool)) {
            return -EINVAL;
        }

        bool *target = (bool *)((uint8_t *)&indicator_settings + fields[i].offset);
        int rc = read_cb(cb_arg, target, sizeof(*target));
        if (rc >= 0) {
            saved_indicator_settings = indicator_settings;
        }
        return rc < 0 ? rc : 0;
    }

    return -ENOENT;
}

SETTINGS_STATIC_HANDLER_DEFINE(onthe15_status, "onthe15/status_v2", NULL, status_settings_set, NULL,
                               NULL);
#endif

void onthe15_status_toggle_connected_indicator(void) {
    struct onthe15_status_settings settings;
    onthe15_status_settings_get(&settings);
    settings.connected_indicator_enabled = !settings.connected_indicator_enabled;
    (void)onthe15_status_settings_set_memory(&settings);
    (void)onthe15_status_settings_save();
}

void onthe15_status_settings_get(struct onthe15_status_settings *settings) {
    if (!settings) return;
    k_mutex_lock(&indicator_settings_lock, K_FOREVER);
    *settings = indicator_settings;
    k_mutex_unlock(&indicator_settings_lock);
}

bool onthe15_status_settings_has_unsaved_changes(void) {
    bool dirty;
    k_mutex_lock(&indicator_settings_lock, K_FOREVER);
    dirty = memcmp(&indicator_settings, &saved_indicator_settings,
                   sizeof(indicator_settings)) != 0;
    k_mutex_unlock(&indicator_settings_lock);
    return dirty;
}

static int apply_settings(const struct onthe15_status_settings *settings) {
    if (!settings) return -EINVAL;
    k_mutex_lock(&indicator_settings_lock, K_FOREVER);
    indicator_settings = *settings;
    k_mutex_unlock(&indicator_settings_lock);
    refresh_indicator();
    return 0;
}

#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR_SPLIT_SYNC)
ZMK_EVENT_IMPL(onthe15_status_sync);
ZMK_EVENT_IMPL(onthe15_status_sync_request);

/* Turn a received relay frame back into the event, on either half. */
ZMK_RELAY_EVENT_HANDLE(onthe15_status_sync, sis, source);
ZMK_RELAY_EVENT_HANDLE(onthe15_status_sync_request, sir, source);

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
ZMK_RELAY_EVENT_CENTRAL_TO_PERIPHERAL(onthe15_status_sync, sis, source);
#else
ZMK_RELAY_EVENT_PERIPHERAL_TO_CENTRAL(onthe15_status_sync_request, sir, source);
#endif

static void sync_settings_to_peripherals(bool save) {
#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
    struct onthe15_status_sync ev = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
        .save = save,
    };

    onthe15_status_settings_get(&ev.settings);
    raise_onthe15_status_sync(ev);
#else
    ARG_UNUSED(save);
#endif
}

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
static int status_sync_request_listener(const zmk_event_t *event) {
    if (as_onthe15_status_sync_request(event) != NULL) {
        sync_settings_to_peripherals(false);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_status_sync_answer, status_sync_request_listener);
ZMK_SUBSCRIPTION(onthe15_status_sync_answer, onthe15_status_sync_request);
#else
/*
 * Ask the central for its copy, and keep asking until an answer arrives.
 *
 * One request at connect time was not enough. A peripheral counts as connected
 * as soon as the BLE link is up, which is before the central has discovered
 * this service, subscribed to the relay characteristic and raised the link's
 * security - and the transport drops what it cannot send at that moment rather
 * than holding it. Nothing asked again, so a half that was away while a
 * setting changed kept the old one until that setting was touched again.
 *
 * Retrying costs a handful of small frames on a link that is otherwise idle at
 * that moment, and the answer cancels the rest. The attempt limit is what
 * keeps a peripheral that never gets an answer from asking forever.
 */
#define SYNC_REQUEST_MAX_ATTEMPTS 8
#define SYNC_REQUEST_RETRY_DELAY K_MSEC(750)

static void status_sync_request_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(status_sync_request_work, status_sync_request_work_handler);
static uint8_t status_sync_request_attempts;

static void status_sync_request_work_handler(struct k_work *work) {
    const struct onthe15_status_sync_request request = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
    };

    raise_onthe15_status_sync_request(request);

    if (++status_sync_request_attempts < SYNC_REQUEST_MAX_ATTEMPTS) {
        k_work_reschedule(&status_sync_request_work, SYNC_REQUEST_RETRY_DELAY);
    }
}

/*
 * Applied without going back through the public setter, which would try to
 * relay it onwards.
 */
static int status_sync_listener(const zmk_event_t *event) {
    const struct onthe15_status_sync *ev = as_onthe15_status_sync(event);

    if (ev != NULL) {
        /* The answer arrived; stop asking. */
        k_work_cancel_delayable(&status_sync_request_work);
        (void)apply_settings(&ev->settings);
        if (ev->save) {
            (void)onthe15_status_settings_save();
        }
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_status_sync_apply, status_sync_listener);
ZMK_SUBSCRIPTION(onthe15_status_sync_apply, onthe15_status_sync);

static int status_sync_request_on_connect(const zmk_event_t *event) {
    const struct zmk_split_peripheral_status_changed *split_status =
        as_zmk_split_peripheral_status_changed(event);

    if (split_status == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (split_status->connected) {
        status_sync_request_attempts = 0;
        k_work_reschedule(&status_sync_request_work, K_NO_WAIT);
    } else {
        k_work_cancel_delayable(&status_sync_request_work);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_status_sync_request_send, status_sync_request_on_connect);
ZMK_SUBSCRIPTION(onthe15_status_sync_request_send, zmk_split_peripheral_status_changed);
#endif
#else
static void sync_settings_to_peripherals(bool save) { ARG_UNUSED(save); }
#endif

int onthe15_status_settings_set_memory(const struct onthe15_status_settings *settings) {
    const int rc = apply_settings(settings);

    if (rc == 0) {
        sync_settings_to_peripherals(false);
    }
    return rc;
}

int onthe15_status_settings_save(void) {
    struct onthe15_status_settings current;
    onthe15_status_settings_get(&current);

#if IS_ENABLED(CONFIG_SETTINGS)
    const struct {
        const char *name;
        const bool *value;
    } records[] = {
        {"onthe15/status_v2/connected", &current.connected_indicator_enabled},
        {"onthe15/status_v2/disconnected", &current.disconnected_indicator_enabled},
        {"onthe15/status_v2/layer_change", &current.layer_change_indicator_enabled},
        {"onthe15/status_v2/feedback", &current.feedback_indicator_enabled},
    };

    for (size_t i = 0; i < ARRAY_SIZE(records); i++) {
        int rc = settings_save_one(records[i].name, records[i].value, sizeof(bool));
        if (rc < 0) {
            return rc;
        }
    }
#endif
    k_mutex_lock(&indicator_settings_lock, K_FOREVER);
    saved_indicator_settings = current;
    k_mutex_unlock(&indicator_settings_lock);
    /* Tell the other half to keep it too, so a reboot does not part them. */
    sync_settings_to_peripherals(true);
    return 0;
}

void onthe15_status_settings_discard(void) {
    struct onthe15_status_settings settings;
    k_mutex_lock(&indicator_settings_lock, K_FOREVER);
    settings = saved_indicator_settings;
    k_mutex_unlock(&indicator_settings_lock);
    (void)onthe15_status_settings_set_memory(&settings);
}

void onthe15_status_settings_reset(void) {
    const struct onthe15_status_settings settings = ONTHE15_STATUS_SETTINGS_DEFAULT;
    (void)onthe15_status_settings_set_memory(&settings);
}

void onthe15_status_show_auto_off(bool enabled) {
    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = false;
    feedback_green = enabled;
    feedback_pulses = 2;
    refresh_indicator();
}

void onthe15_status_show_profile(uint8_t profile) {
    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = false;
    feedback_green = true;
    feedback_pulses = profile + 1;
    refresh_indicator();
}

void onthe15_status_show_clear(void) {
    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = false;
    feedback_green = false;
    feedback_pulses = 3;
    refresh_indicator();
}

void onthe15_status_show_studio_lock_state(bool unlocked) {
    feedback_active = true;
    feedback_forced = true;
    feedback_battery_type = false;
    feedback_green = unlocked;
    feedback_pulses = unlocked ? 2 : 1;
    refresh_indicator();
}

void onthe15_status_set_synced_layer(uint8_t layer) {
    notify_layer_change(layer);
    refresh_indicator();
}

void zmk_matrix_lighting_auto_off_changed(bool enabled) {
  onthe15_status_show_auto_off(enabled);
}

void zmk_matrix_lighting_layer_changed(uint8_t layer) {
  onthe15_status_set_synced_layer(layer);
}

void onthe15_status_battery_settings_changed(bool enabled) {
    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = false;
    feedback_green = enabled;
    feedback_pulses = 3;
    refresh_indicator();
}

void onthe15_status_battery_type_changed(enum onthe15_battery_type type) {
    feedback_active = true;
    feedback_forced = false;
    feedback_battery_type = true;
    feedback_first_green = type == ONTHE15_BATTERY_NIMH;
    current_mode = INDICATOR_FEEDBACK_BATTERY_TYPE;
    pattern_phase = 0;
    k_work_reschedule(&status_work, K_NO_WAIT);
}

static int status_event_listener(const zmk_event_t *event) {
    const struct zmk_activity_state_changed *activity = as_zmk_activity_state_changed(event);

    /*
     * Darken the LEDs here rather than through the work item.
     *
     * ZMK raises this event from the same system workqueue item that then
     * suspends the devices and calls sys_poweroff(), so anything queued behind
     * it never runs: the pins kept whatever level they held and the indicator
     * stayed lit through deep sleep, drawing milliamps from a cell that was
     * supposed to be down at microamps. Writing the pins in the listener is
     * what makes the board actually go dark. Cancelling the work stops a
     * blink pattern from lighting them again in the window before poweroff.
     */
    if (activity != NULL && activity->state == ZMK_ACTIVITY_SLEEP) {
        k_work_cancel_delayable(&status_work);
        current_mode = INDICATOR_OFF;
        pattern_phase = 0;
        set_leds(false, false);
        return ZMK_EV_EVENT_BUBBLE;
    }

    const struct zmk_battery_state_changed *battery = as_zmk_battery_state_changed(event);

    if (battery != NULL) {
        battery_percent = battery->state_of_charge;
        update_low_battery_state();
    }

#if IS_ENABLED(CONFIG_ZMK_SPLIT) && !IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
    const struct zmk_split_peripheral_status_changed *split_status =
        as_zmk_split_peripheral_status_changed(event);
    if (split_status != NULL) {
        split_connected = split_status->connected;
    }
#else
    /* A peripheral has no keymap of its own to watch; it is told which layer is
     * active by the central through onthe15_status_set_synced_layer(). */
    if (as_zmk_layer_state_changed(event) != NULL) {
        notify_layer_change(zmk_keymap_highest_layer_active());
    }
#endif

#if IS_ENABLED(CONFIG_ZMK_STUDIO) &&                                                               \
    (!IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL))
    const struct zmk_studio_core_lock_state_changed *lock_state =
        as_zmk_studio_core_lock_state_changed(event);
    if (lock_state != NULL) {
        /* Studio only ever talks to the central, so this stays on the half that
         * holds the lock state; the peripheral is not told. */
        onthe15_status_show_studio_lock_state(lock_state->state ==
                                              ZMK_STUDIO_CORE_LOCK_STATE_UNLOCKED);
        return ZMK_EV_EVENT_BUBBLE;
    }
#endif

    refresh_indicator();
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(onthe15_status_indicator, status_event_listener);
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_activity_state_changed);
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_battery_state_changed);
#if !IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_endpoint_changed);
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_layer_state_changed);
#endif
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_usb_conn_state_changed);
#if IS_ENABLED(CONFIG_ZMK_STUDIO) &&                                                               \
    (!IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL))
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_studio_core_lock_state_changed);
#endif
#if IS_ENABLED(CONFIG_ZMK_SPLIT) && !IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
ZMK_SUBSCRIPTION(onthe15_status_indicator, zmk_split_peripheral_status_changed);
#endif

static int status_indicator_init(void) {
    if (!gpio_is_ready_dt(&green_led) || !gpio_is_ready_dt(&red_led)) {
        return -ENODEV;
    }

    int ret = gpio_pin_configure_dt(&green_led, GPIO_OUTPUT_INACTIVE);
    if (ret < 0) {
        return ret;
    }

    ret = gpio_pin_configure_dt(&red_led, GPIO_OUTPUT_INACTIVE);
    if (ret < 0) {
        return ret;
    }

    refresh_indicator();
    return 0;
}

SYS_INIT(status_indicator_init, APPLICATION, 90);
