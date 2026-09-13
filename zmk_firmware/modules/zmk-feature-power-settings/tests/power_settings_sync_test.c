#include <assert.h>

#include <zmk_feature/power_settings.h>

static struct zmk_power_settings_snapshot snapshot(uint8_t source, uint32_t generation,
                                                   uint32_t idle, uint32_t sleep) {
    return (struct zmk_power_settings_snapshot){
        .source_id = source,
        .status = ZMK_POWER_SETTINGS_SYNC_STATUS_AVAILABLE,
        .generation = generation,
        .settings = {idle, sleep},
    };
}

int main(void) {
    struct zmk_power_settings_snapshot central = snapshot(0, 4, 30000, 900000);
    struct zmk_power_settings_snapshot peripheral = snapshot(1, 5, 60000, 900000);
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING);

    peripheral.generation = 3;
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_REJECT_STALE);

    peripheral = snapshot(1, 4, 30000, 900000);
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_KEEP_CURRENT);

    peripheral.settings.idle_timeout_ms = 60000;
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_REJECT_CONFLICT);
    assert(zmk_power_settings_sync_resolve(&peripheral, &central) ==
           ZMK_POWER_SETTINGS_SYNC_ACCEPT_INCOMING);

    peripheral.status = ZMK_POWER_SETTINGS_SYNC_STATUS_UNAVAILABLE;
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_DEFER_UNAVAILABLE);
    peripheral.status = ZMK_POWER_SETTINGS_SYNC_STATUS_TIMEOUT;
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_DEFER_TIMEOUT);

    peripheral = snapshot(1, 5, 999, 900000);
    assert(zmk_power_settings_sync_resolve(&central, &peripheral) ==
           ZMK_POWER_SETTINGS_SYNC_INVALID);
    return 0;
}
