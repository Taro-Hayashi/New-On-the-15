#pragma once

#include <stdbool.h>
#include <stdint.h>

struct onthe15_power_settings {
    uint32_t idle_timeout_ms;
    uint32_t deep_sleep_timeout_ms;
};

void onthe15_power_settings_get(struct onthe15_power_settings *settings);
bool onthe15_power_settings_has_unsaved_changes(void);
int onthe15_power_settings_set_memory(const struct onthe15_power_settings *settings);
int onthe15_power_settings_save(void);
void onthe15_power_settings_discard(void);
void onthe15_power_settings_reset(void);

