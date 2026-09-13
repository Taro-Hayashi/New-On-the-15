/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>

/*
 * Per-function switches for the two-LED status indicator.
 *
 * Each field turns one indication off without touching the others, so a user
 * who only dislikes the layer pulses does not have to give up the disconnected
 * warning as well. The low-battery warning is deliberately absent:
 * it already has its own switch under `onthe15.battery` (`low_warning`), and
 * duplicating it here would leave two settings fighting over one indication.
 *
 * Only `connected_indicator_enabled` defaults to false, matching the existing
 * behaviour - a green LED lit for the whole session was judged too noisy by
 * default. Every other indication is a state the user asked to be told about,
 * so those default to true and stay opt-out.
 */
struct onthe15_status_settings {
    bool connected_indicator_enabled;
    bool disconnected_indicator_enabled;
    bool layer_change_indicator_enabled;
    bool feedback_indicator_enabled;
};

#define ONTHE15_STATUS_SETTINGS_DEFAULT                                                   \
    {                                                                                    \
        .connected_indicator_enabled = false,                                            \
        .disconnected_indicator_enabled = true,                                          \
        .layer_change_indicator_enabled = true,                                          \
        .feedback_indicator_enabled = true                                               \
    }

void onthe15_status_settings_get(struct onthe15_status_settings *settings);
bool onthe15_status_settings_has_unsaved_changes(void);
int onthe15_status_settings_set_memory(const struct onthe15_status_settings *settings);
int onthe15_status_settings_save(void);
void onthe15_status_settings_discard(void);
void onthe15_status_settings_reset(void);
