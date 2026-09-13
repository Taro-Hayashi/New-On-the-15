/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>
#include <stdint.h>

enum onthe15_battery_type {
    ONTHE15_BATTERY_NIMH = 0,
    ONTHE15_BATTERY_ALKALINE = 1,
};

struct onthe15_battery_settings {
    bool low_warning_enabled;
    uint8_t battery_type;
};

#define ONTHE15_BATTERY_SETTINGS_DEFAULT                                                   \
    {                                                                                      \
        .low_warning_enabled = true, .battery_type = ONTHE15_BATTERY_NIMH                  \
    }

bool onthe15_battery_low_warning_enabled(void);
enum onthe15_battery_type onthe15_battery_type_get(void);
void onthe15_battery_settings_get(struct onthe15_battery_settings *settings);
bool onthe15_battery_settings_has_unsaved_changes(void);
int onthe15_battery_settings_set_memory(const struct onthe15_battery_settings *settings);
int onthe15_battery_settings_save(void);
void onthe15_battery_settings_discard(void);
void onthe15_battery_settings_reset(void);
