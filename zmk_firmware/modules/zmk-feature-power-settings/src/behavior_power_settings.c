/* SPDX-License-Identifier: MIT */

#define DT_DRV_COMPAT zmk_behavior_power_settings

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/sys/util.h>

#include <drivers/behavior.h>
#include <dt-bindings/zmk-power-settings/power_settings.h>
#include <zmk/behavior.h>

#include <zmk_feature/power_settings.h>

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

#define BEHAVIOR_NODE DT_DRV_INST(0)
#define IDLE_STEP_MS ((uint32_t)DT_PROP(BEHAVIOR_NODE, idle_step_ms))
#define DEEP_SLEEP_STEP_MS ((uint32_t)DT_PROP(BEHAVIOR_NODE, deep_sleep_step_ms))

/*
 * Steps one timeout, staying inside the range the module validates against.
 *
 * A timeout of zero means the feature is off, and these keys leave that state
 * alone in one direction only: stepping up from off starts at the minimum,
 * which is the useful reading of "more", while stepping down from off has
 * nothing below it. Turning a timeout off outright stays a Studio action - it
 * is the one change here a user cannot undo by pressing the opposite key.
 */
static uint32_t stepped_timeout(uint32_t value, int32_t step, uint32_t minimum,
                                uint32_t maximum) {
    if (value == 0U) {
        return step > 0 ? minimum : 0U;
    }

    if (step < 0 && value <= minimum + (uint32_t)(-step)) {
        return minimum;
    }

    if (step > 0 && value + (uint32_t)step >= maximum) {
        return maximum;
    }

    return (uint32_t)((int64_t)value + step);
}

static int on_binding_pressed(struct zmk_behavior_binding *binding,
                              struct zmk_behavior_binding_event event) {
    ARG_UNUSED(event);

    struct zmk_power_settings settings;
    zmk_power_settings_get(&settings);

    switch (binding->param1) {
    case ZMK_POWER_SETTINGS_IDLE_INC_CMD:
    case ZMK_POWER_SETTINGS_IDLE_DEC_CMD: {
        const int32_t step = binding->param1 == ZMK_POWER_SETTINGS_IDLE_INC_CMD
                                 ? (int32_t)IDLE_STEP_MS
                                 : -(int32_t)IDLE_STEP_MS;
        settings.idle_timeout_ms =
            stepped_timeout(settings.idle_timeout_ms, step,
                            ZMK_POWER_SETTINGS_MIN_IDLE_TIMEOUT_MS,
                            ZMK_POWER_SETTINGS_MAX_IDLE_TIMEOUT_MS);
        /* Sleeping before going idle is not a state the module accepts. */
        if (settings.deep_sleep_timeout_ms != 0U &&
            settings.deep_sleep_timeout_ms < settings.idle_timeout_ms) {
            settings.deep_sleep_timeout_ms = settings.idle_timeout_ms;
        }
        break;
    }
    case ZMK_POWER_SETTINGS_DEEP_SLEEP_INC_CMD:
    case ZMK_POWER_SETTINGS_DEEP_SLEEP_DEC_CMD: {
        const int32_t step =
            binding->param1 == ZMK_POWER_SETTINGS_DEEP_SLEEP_INC_CMD
                ? (int32_t)DEEP_SLEEP_STEP_MS
                : -(int32_t)DEEP_SLEEP_STEP_MS;
        settings.deep_sleep_timeout_ms =
            stepped_timeout(settings.deep_sleep_timeout_ms, step,
                            ZMK_POWER_SETTINGS_MIN_DEEP_SLEEP_TIMEOUT_MS,
                            ZMK_POWER_SETTINGS_MAX_DEEP_SLEEP_TIMEOUT_MS);
        if (settings.deep_sleep_timeout_ms != 0U &&
            settings.deep_sleep_timeout_ms < settings.idle_timeout_ms) {
            settings.idle_timeout_ms = settings.deep_sleep_timeout_ms;
        }
        break;
    }
    default:
        return -ENOTSUP;
    }

    int rc = zmk_power_settings_set_memory(&settings);
    if (rc < 0) {
        return rc;
    }

    rc = zmk_power_settings_save();
    if (rc < 0) {
        return rc;
    }

    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_binding_released(struct zmk_behavior_binding *binding,
                               struct zmk_behavior_binding_event event) {
    return ZMK_BEHAVIOR_OPAQUE;
}

#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
static const struct behavior_parameter_value_metadata command_values[] = {
    {
        .display_name = "Idle Timeout +",
        .value = ZMK_POWER_SETTINGS_IDLE_INC_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Idle Timeout -",
        .value = ZMK_POWER_SETTINGS_IDLE_DEC_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Deep Sleep Timeout +",
        .value = ZMK_POWER_SETTINGS_DEEP_SLEEP_INC_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Deep Sleep Timeout -",
        .value = ZMK_POWER_SETTINGS_DEEP_SLEEP_DEC_CMD,
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

static const struct behavior_driver_api power_settings_driver_api = {
    .binding_pressed = on_binding_pressed,
    .binding_released = on_binding_released,
    .locality = BEHAVIOR_LOCALITY_GLOBAL,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = get_parameter_metadata,
#endif
};

BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                        CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &power_settings_driver_api);

#endif
