/* SPDX-License-Identifier: MIT */

#pragma once

/*
 * Command parameters for the settings behaviors that carry no lighting: the
 * battery chemistry and warning, the four status indications, and the sleep
 * timeouts. Each behavior groups one page of the DYA Studio settings UI, so a
 * user who wants a switch on a key finds it under the same heading it has in
 * the browser.
 *
 * None of these keys ship in a default keymap. They exist so that a keyboard
 * assigned from Studio can carry them, which is why the destructive commands -
 * clearing bonds, resetting settings - are not among them.
 */

#define ONTHE15_BATTERY_LOW_WARNING_TOG_CMD 0
#define ONTHE15_BATTERY_TYPE_TOG_CMD 1

#define ONTHE15_STATUS_CONNECTED_TOG_CMD 0
#define ONTHE15_STATUS_DISCONNECTED_TOG_CMD 1
#define ONTHE15_STATUS_LAYER_CHANGE_TOG_CMD 2
#define ONTHE15_STATUS_FEEDBACK_TOG_CMD 3

/*
 * The sleep timeouts are not here: they belong to the reusable power settings
 * module, which names its own commands in
 * <dt-bindings/zmk-power-settings/power_settings.h>.
 */
