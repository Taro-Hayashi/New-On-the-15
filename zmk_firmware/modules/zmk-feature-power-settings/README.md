# ZMK Power Settings

Reusable runtime idle and deep-sleep timeout settings for ZMK. The module validates a
complete settings pair before applying either value, keeps current and saved snapshots,
and exposes memory-only Set/Discard/Reset plus explicit Save operations.

The host ZMK tree must provide `zmk_activity_set_timeouts()`. On the 15 supplies that
boundary through `patches/dya-runtime-power-settings.patch`; the module does not modify a
ZMK workspace itself.

For compatibility with an existing firmware, set
`CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH` to its existing Zephyr settings subtree. The
On the 15 Phase 2 target uses `onthe15/power_v1`, preserving the existing
`onthe15/power_v1/state` payload (`idle_timeout_ms`, then `deep_sleep_timeout_ms`, both
`uint32_t`).

## Keymap bindings

`compatible = "zmk,behavior-power-settings"` gives the timeouts four keys, named in the
behavior's parameter metadata so a Studio client lists them by name:
`IDLE_INC`, `IDLE_DEC`, `DEEP_SLEEP_INC`, `DEEP_SLEEP_DEC` from
`<dt-bindings/zmk-power-settings/power_settings.h>`. Steps come from `idle-step-ms`
(30 s by default) and `deep-sleep-step-ms` (5 min), and every press stays inside the
range the module validates, keeping deep sleep at or beyond idle.

A timeout of `0` means disabled. Stepping up from `0` starts at the minimum; stepping
down from `0` leaves it there. Disabling a timeout is not on a key, because it is the
one change the opposite key could not undo.

`CONFIG_ZMK_POWER_SETTINGS_SYNC_API` enables the split-ready contract without enabling a
transport. Source `0` is central or an integrated keyboard; source `1+` is reserved for
peripherals. Snapshots carry a generation and availability state. Newer generations win;
for different values at the same generation, source `0` wins. Unavailable and timeout are
deferred explicitly, and `zmk_power_settings_sync_result` reports applied, failed, timeout,
and unavailable source masks independently.
