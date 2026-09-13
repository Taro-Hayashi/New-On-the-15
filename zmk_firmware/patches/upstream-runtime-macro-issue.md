# Upstream report draft — cormoran/zmk-feature-runtime-macro

Target: <https://github.com/cormoran/zmk-feature-runtime-macro>
Filed as: not filed yet
Observed on: `38530962eb7061b60efcb98e84585cfb1f0cb6de`
Local fix: none (configuration worked around; no module patch carried)

Two related paper cuts found in the same session, filed together because both
surface as the same misleading message. Split into two issues if you prefer.

---

## Title

Rename fails when every slot is taken, and unrelated `-ENOSPC` failures are all
reported as "Macro pool full"

## Body

### 1. Rename needs a free slot (and double the pool) that it should not need

`zmk_runtime_macro_rename()` creates the entry under the new name first, then
deletes the old one:

```c
ret = zmk_runtime_macro_create(new_name, encoded, encoded_size, mode, NULL);
if (ret < 0) {
    return ret;
}
return zmk_custom_setting_keyspace_delete(&runtime_macros, old_key);
```

So a rename transiently needs one slot more than the keyboard actually uses.
With `CONFIG_ZMK_RUNTIME_MACRO_COUNT=4` and four macros defined, renaming any
of them fails with `-ENOSPC`. Renaming does not add a macro, so this is
surprising: the user is told to delete a macro in order to rename one.

The same applies to the shared pool. Both entries exist at once during the
rename, so key + body is needed twice over. On a tight
`CONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES` a rename can fail even when a slot is
free.

Reproduced on hardware: 4 macros defined out of 4 slots, rename any of them,
"Macro pool full: delete or shrink another macro". Deleting one macro makes the
rename succeed.

A keyspace-level "replace this entry's key, keep its blob" operation would fix
both halves. Swapping the order to delete-then-create would also free the slot,
but it loses the macro if the create then fails, so it does not look like the
right trade.

### 2. Every `-ENOSPC` is reported as a full pool

The dispatcher maps the errno unconditionally:

```c
if (ret == -ENOSPC) {
    set_error(resp, "Macro pool full: delete or shrink another macro");
}
```

But `-ENOSPC` also comes from places that have nothing to do with the pool:

- `append_item()` in `decode_macro()`, when a body decodes into more queued
  actions than `CONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE`
- `append_uvar()` / `append_key_tap_sequence_step()` / the step-copy path in the
  edit handlers, when the encode buffer would overflow
- `list_macros_cb()`, when more macros exist than the response array holds

The queue case is easy to hit: a key-tap-sequence step consumes one queue entry
per key, so a string step longer than `QUEUE_SIZE` fails — while the Web UI's
size counter, which tracks the `MAX_BYTES` body budget, still shows plenty of
room.

Instrumented firmware log from that case, with the pool nearly empty:

```
DIAG write ret=0 pool_used=61 pool_size=512      <- pool has 451 bytes free
DIAG append_seq keys=63 capacity=192 offset=2    <- encode buffer is fine too
DIAG rpc request_type=7 ret=-28                  <- SetMacroStep returns -ENOSPC
```

The message sent the investigation the wrong way for a while: it names a
resource that is not exhausted, and the suggested remedy (delete or shrink
another macro) cannot help, because the limit is per-macro. Distinguishing the
queue/encode cases from a genuinely full pool — even just "macro is too long to
play back: reduce its steps" versus "pool full" — would make this
self-explanatory.

### 3. `QUEUE_SIZE` cannot always be raised to match `MAX_BYTES`

Related, and the reason the queue limit is reachable at all: the Kconfig help
for `ZMK_RUNTIME_MACRO_QUEUE_SIZE` says to raise it alongside `MAX_BYTES`, but
its `range` is `1 128` while `MAX_BYTES` goes higher. A pure key-tap body
consumes roughly one queue entry per body byte, so any `MAX_BYTES` above ~131
admits bodies that can never be decoded. Either the range needs to track
`MAX_BYTES`, or the create/write path should reject a body whose decoded action
count cannot fit, with a message that says so.

### Setup

nRF52840 (Seeed XIAO BLE), `CONFIG_ZMK_RUNTIME_MACRO_COUNT=4`,
`POOL_BYTES=512`, `MAX_BYTES=192`, `QUEUE_SIZE=48` originally (raised to 128
locally, which fixed the string-length failures up to the new limit).
