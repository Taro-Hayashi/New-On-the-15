/* SPDX-License-Identifier: MIT */
#pragma once
#include <onthe15/battery_settings.h>

static inline void onthe15_battery_settings_toggle_warning(struct onthe15_battery_settings *state) {
    state->low_warning_enabled = !state->low_warning_enabled;
}

static inline void onthe15_battery_settings_toggle_type(struct onthe15_battery_settings *state) {
    state->battery_type = state->battery_type == ONTHE15_BATTERY_NIMH
                              ? ONTHE15_BATTERY_ALKALINE
                              : ONTHE15_BATTERY_NIMH;
}
