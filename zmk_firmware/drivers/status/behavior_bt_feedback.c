/* SPDX-License-Identifier: MIT */

#define DT_DRV_COMPAT onthe15_behavior_bt_feedback

#include <errno.h>
#include <zephyr/device.h>

#include <drivers/behavior.h>
#include <dt-bindings/zmk/bt.h>
#include <zmk/behavior.h>
#include <zmk/ble.h>

#include "status_indicator.h"

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

static int on_binding_pressed(struct zmk_behavior_binding *binding,
                              struct zmk_behavior_binding_event event) {
  switch (binding->param1) {
  case BT_SEL_CMD: {
    const int rc = zmk_ble_prof_select(binding->param2);
    if (rc >= 0) {
#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR)
      onthe15_status_show_profile(binding->param2);
#endif
    }
    return rc;
  }
  case BT_CLR_CMD:
    zmk_ble_clear_bonds();
#if IS_ENABLED(CONFIG_ONTHE15_STATUS_INDICATOR)
      onthe15_status_show_clear();
#endif
    return 0;
  default:
    return -ENOTSUP;
  }
}

static int on_binding_released(struct zmk_behavior_binding *binding,
                               struct zmk_behavior_binding_event event) {
  return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api bt_feedback_driver_api = {
    .binding_pressed = on_binding_pressed,
    .binding_released = on_binding_released,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = zmk_behavior_get_empty_param_metadata,
#endif
};

BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                        CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,
                        &bt_feedback_driver_api);

#endif
