/*
 * The split transport the synchronization contract was written for.
 *
 * power_settings_sync.c settled how two copies of the settings are compared -
 * source ids, generations, who wins on reconnect - but nothing ever carried a
 * snapshot from one board to the other, so the contract sat unused. Both
 * halves sleep on their own timers, so a peripheral that never hears about a
 * change keeps whatever its firmware was built with: told to sleep after a
 * minute, the right half would still sit awake for the compiled-in fifteen.
 *
 * The central sends its snapshot whenever the settings change, and the
 * peripheral asks for one as soon as it has a link to ask over, so a half that
 * was off or out of range during the change catches up on reconnect rather
 * than waiting for the next edit. Conflict resolution stays where it was:
 * zmk_power_settings_sync_apply_snapshot() runs the incoming snapshot through
 * zmk_power_settings_sync_resolve() and drops it if the local copy is newer.
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <zmk/event_manager.h>

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
#include <zmk/split/central.h>
#else
#include <zmk/events/split_peripheral_status_changed.h>
#endif

#include <zmk_feature/power_settings.h>

LOG_MODULE_REGISTER(zmk_power_settings_split, CONFIG_ZMK_LOG_LEVEL);

/*
 * `save` carries whether the peripheral should persist what it applied, so the
 * halves still agree after a reboot rather than only until the next change.
 */
struct zmk_power_settings_relay {
    uint8_t source;
    bool save;
    struct zmk_power_settings_snapshot snapshot;
};

struct zmk_power_settings_relay_request {
    uint8_t source;
};

ZMK_EVENT_DECLARE(zmk_power_settings_relay);
ZMK_EVENT_DECLARE(zmk_power_settings_relay_request);

ZMK_EVENT_IMPL(zmk_power_settings_relay);
ZMK_EVENT_IMPL(zmk_power_settings_relay_request);

/* Turn a received relay frame back into the event, on either half. */
ZMK_RELAY_EVENT_HANDLE(zmk_power_settings_relay, pss, source);
ZMK_RELAY_EVENT_HANDLE(zmk_power_settings_relay_request, psr, source);

#if IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
ZMK_RELAY_EVENT_CENTRAL_TO_PERIPHERAL(zmk_power_settings_relay, pss, source);

static void send_snapshot(bool save) {
    struct zmk_power_settings_relay ev = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
        .save = save,
    };

    zmk_power_settings_sync_get_local_snapshot(&ev.snapshot);
    raise_zmk_power_settings_relay(ev);
}

/*
 * SYNCHRONIZED means the change arrived from elsewhere. The central never
 * applies a snapshot today, but sending one back out on that reason is how a
 * loop would start if it ever did.
 */
static void settings_changed(const struct zmk_power_settings_snapshot *snapshot,
                             enum zmk_power_settings_change_reason reason) {
    ARG_UNUSED(snapshot);

    if (reason == ZMK_POWER_SETTINGS_CHANGE_SYNCHRONIZED) {
        return;
    }

    send_snapshot(reason == ZMK_POWER_SETTINGS_CHANGE_SAVED);
}

static int power_settings_relay_answer(const zmk_event_t *event) {
    if (as_zmk_power_settings_relay_request(event) != NULL) {
        send_snapshot(false);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(zmk_power_settings_relay_answer, power_settings_relay_answer);
ZMK_SUBSCRIPTION(zmk_power_settings_relay_answer, zmk_power_settings_relay_request);

static int power_settings_split_init(void) {
    return zmk_power_settings_sync_set_listener(settings_changed);
}

#else /* peripheral */

ZMK_RELAY_EVENT_PERIPHERAL_TO_CENTRAL(zmk_power_settings_relay_request, psr, source);

/*
 * Ask for the central's copy, and keep asking until an answer arrives.
 *
 * A peripheral counts as connected as soon as the BLE link is up, which is
 * before the central has discovered the service, subscribed and raised the
 * link's security. The transport drops what it cannot send at that moment
 * rather than holding it, so a single request at connect time can be lost with
 * nothing to notice it: the half stays on whatever it had until the setting is
 * changed again. The answer cancels the remaining attempts, and the limit
 * keeps a peripheral that never gets one from asking forever.
 */
#define RELAY_REQUEST_MAX_ATTEMPTS 8
#define RELAY_REQUEST_RETRY_DELAY K_MSEC(750)

static void power_settings_relay_request_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(power_settings_relay_request_work,
                        power_settings_relay_request_work_handler);
static uint8_t power_settings_relay_request_attempts;

static void power_settings_relay_request_work_handler(struct k_work *work) {
    const struct zmk_power_settings_relay_request request = {
        .source = ZMK_RELAY_EVENT_SOURCE_SELF,
    };

    raise_zmk_power_settings_relay_request(request);

    if (++power_settings_relay_request_attempts < RELAY_REQUEST_MAX_ATTEMPTS) {
        k_work_reschedule(&power_settings_relay_request_work, RELAY_REQUEST_RETRY_DELAY);
    }
}

static int power_settings_relay_apply(const zmk_event_t *event) {
    const struct zmk_power_settings_relay *ev = as_zmk_power_settings_relay(event);

    if (ev == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    /* The answer arrived; stop asking, whatever the resolver makes of it. */
    k_work_cancel_delayable(&power_settings_relay_request_work);

    const int rc = zmk_power_settings_sync_apply_snapshot(&ev->snapshot);

    /* -EALREADY only means the local copy was the newer of the two. */
    if (rc < 0 && rc != -EALREADY) {
        LOG_WRN("Failed to apply relayed power settings: %d", rc);
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (rc == 0 && ev->save) {
        (void)zmk_power_settings_save();
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(zmk_power_settings_relay_apply, power_settings_relay_apply);
ZMK_SUBSCRIPTION(zmk_power_settings_relay_apply, zmk_power_settings_relay);

static int power_settings_relay_request(const zmk_event_t *event) {
    const struct zmk_split_peripheral_status_changed *split_status =
        as_zmk_split_peripheral_status_changed(event);

    if (split_status == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (split_status->connected) {
        power_settings_relay_request_attempts = 0;
        k_work_reschedule(&power_settings_relay_request_work, K_NO_WAIT);
    } else {
        k_work_cancel_delayable(&power_settings_relay_request_work);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(zmk_power_settings_relay_request, power_settings_relay_request);
ZMK_SUBSCRIPTION(zmk_power_settings_relay_request, zmk_split_peripheral_status_changed);

static int power_settings_split_init(void) { return 0; }

#endif

SYS_INIT(power_settings_split_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
