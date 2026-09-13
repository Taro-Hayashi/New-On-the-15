/* SPDX-License-Identifier: MIT */
#include <assert.h>
#include <stdio.h>

#include "../drivers/battery/battery_curve.h"
#include "../drivers/battery/battery_settings.h"

int main(void) {
    struct onthe15_battery_settings defaults = ONTHE15_BATTERY_SETTINGS_DEFAULT;
    assert(defaults.low_warning_enabled);
    assert(defaults.battery_type == ONTHE15_BATTERY_NIMH);
    onthe15_battery_settings_toggle_warning(&defaults);
    onthe15_battery_settings_toggle_type(&defaults);
    assert(!defaults.low_warning_enabled);
    assert(defaults.battery_type == ONTHE15_BATTERY_ALKALINE);
    struct onthe15_battery_settings restored = defaults;
    assert(!restored.low_warning_enabled);
    assert(restored.battery_type == ONTHE15_BATTERY_ALKALINE);

    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 999) == 0);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 1000) == 0);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 1242) == 20);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 1275) == 50);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 1450) == 100);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_NIMH, 1500) == 100);

    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 799) == 0);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 800) == 0);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 1200) == 45);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 1300) == 70);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 1500) == 98);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 1520) == 100);
    assert(onthe15_battery_state_of_charge(ONTHE15_BATTERY_ALKALINE, 1600) == 100);

    puts("battery curve tests passed");
    return 0;
}
