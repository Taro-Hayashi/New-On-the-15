# archive

Build and verification scripts for work that is finished. Nothing here is part
of the current line; they are kept so a recorded measurement can be traced back
to the image it came from, and rebuilt if that is ever needed.

| File | What it built |
| --- | --- |
| `build_dya_completed.sh` | The 18 DYA targets as they stood when the phases closed, including the fifteen retired ones: power module, power sync, settings RPC, power UI cleanup, device info, runtime combo and macro (and their diagnostic variants), BLE, host RGB, and the four power-measurement images |
| `build_legacy.sh` | The zmk @faaf39d9 line: x7/x8, the split halves, and the x15 images that predate the DYA line |
| `build_battery_curve_x7.sh` | The x7 battery discharge curve measurement |
| `verify_dya_*.sh` | The acceptance checks that went with the retired targets |

`build_dya_completed.sh` is a frozen copy rather than a trimmed one. Splitting
the retired targets out would have meant duplicating the shared build
invocation, and a duplicate drifts: the point of keeping these is that they
still reproduce what was measured.

They reference module checkouts at pinned SHAs, so a rebuild needs those
checkouts at those revisions. `build_legacy.sh` additionally needs the zmk
workspace at faaf39d9, which is not the current one.

The current line is `../build_dya.sh`: `power-x15` (distributed),
`personal-default-layer-x15`, `kscan-diagnostics-x15` and `settings-reset`.
