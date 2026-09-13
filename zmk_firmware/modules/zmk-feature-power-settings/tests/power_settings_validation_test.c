#include <assert.h>
#include <stddef.h>

#include <zmk_feature/power_settings.h>

int main(void) {
    assert(!zmk_power_settings_is_valid(NULL));

    const struct zmk_power_settings defaults = {30000U, 900000U};
    const struct zmk_power_settings disabled = {0U, 0U};
    const struct zmk_power_settings idle_disabled = {0U, 60000U};
    const struct zmk_power_settings sleep_disabled = {1000U, 0U};
    assert(zmk_power_settings_is_valid(&defaults));
    assert(zmk_power_settings_is_valid(&disabled));
    assert(zmk_power_settings_is_valid(&idle_disabled));
    assert(zmk_power_settings_is_valid(&sleep_disabled));

    const struct zmk_power_settings idle_too_short = {999U, 60000U};
    const struct zmk_power_settings idle_too_long = {3600001U, 3600001U};
    const struct zmk_power_settings sleep_too_short = {1000U, 59999U};
    const struct zmk_power_settings sleep_too_long = {1000U, 86400001U};
    const struct zmk_power_settings reversed = {60001U, 60000U};
    assert(!zmk_power_settings_is_valid(&idle_too_short));
    assert(!zmk_power_settings_is_valid(&idle_too_long));
    assert(!zmk_power_settings_is_valid(&sleep_too_short));
    assert(!zmk_power_settings_is_valid(&sleep_too_long));
    assert(!zmk_power_settings_is_valid(&reversed));
    return 0;
}
