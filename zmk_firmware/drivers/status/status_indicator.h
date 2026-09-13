/* SPDX-License-Identifier: MIT */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include <onthe15/status_settings.h>
#include "../battery/battery_curve.h"

void onthe15_status_toggle_connected_indicator(void);
void onthe15_status_show_auto_off(bool enabled);
void onthe15_status_show_profile(uint8_t profile);
void onthe15_status_show_clear(void);
void onthe15_status_show_studio_lock_state(bool unlocked);
void onthe15_status_set_synced_layer(uint8_t layer);
void onthe15_status_battery_settings_changed(bool enabled);
void onthe15_status_battery_type_changed(enum onthe15_battery_type type);
