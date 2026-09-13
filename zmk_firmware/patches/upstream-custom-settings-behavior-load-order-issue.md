# Upstream report draft — cormoran/zmk-feature-custom-settings

Target: <https://github.com/cormoran/zmk-feature-custom-settings>
Filed as: <https://github.com/cormoran/zmk-feature-custom-settings/issues/57>
Observed on: `c6a7fef3a3be3d3ace5de9a4b0628c6418cd1f3f`
Local fix: `patches/dya-custom-settings-behavior-load-order.patch`

---

## Title

BEHAVIOR values are dropped on every boot when ZMK assigns behavior local IDs
through the settings table

## Body

### Summary

`value_from_storage()` validates a persisted value before applying it, and for
`ZMK_CUSTOM_SETTING_VALUE_TYPE_BEHAVIOR` that validation resolves the stored
behavior local ID through `zmk_behavior_find_behavior_name_from_local_id()`.

With `CONFIG_ZMK_BEHAVIOR_LOCAL_ID_TYPE_SETTINGS_TABLE`, that ID table is
populated by `settings_load()` itself: stored IDs arrive through the `behavior`
subtree's set handler, and any behavior still without an ID is numbered in that
subtree's **commit** handler, after every set callback in the pass has run. A
`custom_settings` record that loads before the table is complete cannot resolve
its ID yet, so validation fails with `-EINVAL` and the persisted value is
silently discarded. The setting falls back to its default and the binding is
lost on every single boot.

Scalar and BYTES values in the same subsystem load fine, so the failure looks
like partial corruption rather than an ordering problem.

### Evidence

From `zmk-feature-runtime-combo`, which stores each combo as a BYTES body plus a
parallel BEHAVIOR array. Firmware log with diagnostic `LOG_ERR` lines added to
the load and save paths:

```
# during settings_load() at boot
load record cormoran__runtime_combo/names/0     len=11 ret=0
load record cormoran__runtime_combo/combos/0    len=16 ret=0
load record cormoran__runtime_combo/behaviors/0 len=6  ret=-22   <- dropped
load size record cormoran__runtime_combo/behaviors/_size size=1 ret=0

# 12 seconds after boot, from a delayed work item
boot behaviors[0] read_ret=0 id=0          <- default, the stored value is gone
reload subtree ret=0
load record cormoran__runtime_combo/behaviors/0 len=6 ret=0      <- now valid
after-reload behaviors[0] read_ret=0 id=4  <- the real value, restored
```

The same record is rejected at boot and accepted twelve seconds later. Saving
was never the problem — every `settings_save_one()` returned 0.

### Suggested fix

A persisted behavior value was already validated when it was written, and any
reader has to cope with an unresolvable ID anyway (behaviors can disappear
across a firmware update). So the load path can range-check it and leave
resolution to the reader:

```c
static bool applying_persisted_value;

static int validate_behavior_value(const struct zmk_custom_setting_behavior_value *behavior) {
    if (behavior->behavior_id >= UINT16_MAX) {
        return -ERANGE;
    }
    if (applying_persisted_value) {
        return 0;
    }
    /* ...unchanged runtime validation... */
}
```

`applying_persisted_value` is set around the `zmk_custom_setting_validate()`
call in `value_from_storage()`, which already runs under
`custom_settings_lock`. `validate_behavior_id_constraint()` needs the same
exemption, since an INT32 setting carrying a `BEHAVIOR_ID` constraint hits the
identical ordering problem. Runtime writes over RPC are unaffected and still
validate fully.

That is what the attached patch does; with it, the record loads at boot
(`ret=0`) and the binding survives reboots on my hardware.

### Alternative

Re-applying the subtree from this module's own commit handler would also work
and would keep load-time validation strict, but commit ordering between the
`behavior` and `custom_settings` subtrees is link order, not something the
module can rely on. Skipping the resolution check seemed the more robust of
the two. Happy to follow whichever direction you prefer.
