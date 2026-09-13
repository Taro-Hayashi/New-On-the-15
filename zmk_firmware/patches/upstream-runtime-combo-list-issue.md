# Upstream report draft — cormoran/zmk-feature-runtime-combo

Target: <https://github.com/cormoran/zmk-feature-runtime-combo>
Filed as: <https://github.com/cormoran/zmk-feature-runtime-combo/issues/15>
Observed on: `d9490e7b5d41c516221d131241009e81740efcee`
Local fix: `patches/dya-runtime-combo-list-skip-unreadable-slot.patch`

---

## Title

ListCombos returns an error for the whole list when a single slot holds an
unresolvable behavior, leaving the Web UI empty and unrecoverable

## Body

### Summary

`handle_list_combos()` skips only `-ENOENT` and returns any other error from
`fill_combo_message()`, which aborts the entire listing. A single slot whose
stored behavior local ID does not resolve in the running firmware makes
`zmk_runtime_combo_read()` return `-ENODEV`, so `ListCombos` fails as a whole
and the Web UI shows no combos at all — including the healthy ones.

Because every slot becomes invisible, the UI also offers no way to edit, reset
or delete the offending slot, so the keyboard cannot be recovered through
Studio. Only a full settings erase clears it.

### How I hit it

I have two firmware images: one with both `zmk-feature-runtime-combo` and
`zmk-feature-runtime-macro`, and one with runtime-combo only. A combo created
on the first image was bound to a `&rmacro` behavior. After flashing the
combo-only image, that behavior no longer exists, so its local ID does not
resolve. This is not an exotic situation — any keymap or module change that
removes a behavior reproduces it.

### Symptoms

- Combo list is empty in the Web UI, and Refresh does not help
- Newly created combos work physically (the decoded cache is fine)
- Creating a new combo silently overwrites the existing one, because the UI
  allocates the next index from an empty list and always picks 0
- Everything looks unsaved after a reboot, even though it was persisted

That last point cost the most time: writing and saving both succeed, so the
data really is in flash. Only reading it back fails.

### Evidence

Firmware log with diagnostic `LOG_ERR` lines added to `handle_list_combos()`,
`zmk_runtime_combo_write()` and `handle_save()`:

```
DIAG write idx=0 persist=0 req_size=2 combo_ret=0 behavior_ret=0 name_ret=0 sizes combos=2 behaviors=2 names=2
DIAG rpc request_type=3 ret=0
DIAG list_combos count=2 max=4
DIAG list_combos slot=0 fill_ret=0        <- healthy slot
DIAG list_combos slot=1 fill_ret=-19      <- -ENODEV, stale behavior reference
DIAG rpc request_type=1 ret=-19           <- whole ListCombos aborted
DIAG save ret=0 affected=9                <- save succeeded
```

`-ENODEV` originates in `read_combo_behavior()`
(`src/runtime_combo/runtime_combo.c`), when
`zmk_behavior_find_behavior_name_from_local_id()` returns `NULL`.

### Suggested fix

Skip any slot that cannot be listed instead of failing the whole request:

```c
for (uint32_t i = 0; i < count; i++) {
    int ret = fill_combo_message(i, &result.combos[result.combos_count]);
    if (ret < 0) {
        LOG_WRN("Runtime combo slot %u is not listable (%d) - skipping", i, ret);
        continue;
    }
    result.combos_count++;
}
```

This is what the attached patch does, and it restores the list on my hardware.

### Worth considering

Skipping keeps the healthy slots visible, but the broken slot stays invisible
and cannot be cleared from the UI. It may be better to still emit the combo
with its raw stored behavior ID and no resolved device, so the UI can show it
as broken and let the user re-bind or delete it. That is a larger change to
`zmk_runtime_combo_read()`'s contract — the decoded cache must keep refusing to
invoke such a binding — so I did not attempt it. Happy to follow whichever
direction you prefer.
