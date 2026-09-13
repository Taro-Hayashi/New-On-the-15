/* SPDX-License-Identifier: MIT */

#define DT_DRV_COMPAT onthe15_behavior_status_settings

#include <errno.h>
#include <zephyr/device.h>

#include <drivers/behavior.h>
#include <dt-bindings/onthe15/settings.h>
#include <zmk/behavior.h>

#include "status_indicator.h"

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

/*
 * One key per status indication, matching the four switches on the indicator
 * page of the settings UI. The older ind_tog behavior stays as it is: it
 * predates the other three switches, and keymaps already carry it.
 */
static int on_binding_pressed(struct zmk_behavior_binding *binding,
                              struct zmk_behavior_binding_event event) {
    ARG_UNUSED(event);

    struct onthe15_status_settings settings;
    onthe15_status_settings_get(&settings);

    switch (binding->param1) {
    case ONTHE15_STATUS_CONNECTED_TOG_CMD:
        settings.connected_indicator_enabled = !settings.connected_indicator_enabled;
        break;
    case ONTHE15_STATUS_DISCONNECTED_TOG_CMD:
        settings.disconnected_indicator_enabled = !settings.disconnected_indicator_enabled;
        break;
    case ONTHE15_STATUS_LAYER_CHANGE_TOG_CMD:
        settings.layer_change_indicator_enabled = !settings.layer_change_indicator_enabled;
        break;
    case ONTHE15_STATUS_FEEDBACK_TOG_CMD:
        settings.feedback_indicator_enabled = !settings.feedback_indicator_enabled;
        break;
    default:
        return -ENOTSUP;
    }

    int rc = onthe15_status_settings_set_memory(&settings);
    if (rc < 0) {
        return rc;
    }

    rc = onthe15_status_settings_save();
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
        .display_name = "Connected Indicator",
        .value = ONTHE15_STATUS_CONNECTED_TOG_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Disconnected Indicator",
        .value = ONTHE15_STATUS_DISCONNECTED_TOG_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Layer Change Indicator",
        .value = ONTHE15_STATUS_LAYER_CHANGE_TOG_CMD,
        .type = BEHAVIOR_PARAMETER_VALUE_TYPE_VALUE,
    },
    {
        .display_name = "Feedback Indicator",
        .value = ONTHE15_STATUS_FEEDBACK_TOG_CMD,
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

static const struct behavior_driver_api status_settings_driver_api = {
    .binding_pressed = on_binding_pressed,
    .binding_released = on_binding_released,
    .locality = BEHAVIOR_LOCALITY_GLOBAL,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = get_parameter_metadata,
#endif
};

BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                        CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &status_settings_driver_api);

#endif
