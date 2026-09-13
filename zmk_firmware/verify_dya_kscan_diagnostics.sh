#!/bin/sh
# Verify the Phase 9 manufacturing / repair-only Kscan Diagnostics x15 target.
#
# This target is never promoted to a release artifact: it opens the diagnostics
# RPC while the device is locked (a keyboard with dead keys cannot type the
# unlock combo) and drops the lighting effects. The checks below pin that
# intent so the image cannot quietly drift toward a distributable build.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
KSCAN_DIAG_MODULE="${KSCAN_DIAG_MODULE:-/Volumes/Primary/GitHub/zmk-feature-kscan-diagnostics}"
EXPECTED_KSCAN_DIAG="1432f7fe0cfe903cd7d3c9931ae6bd6f2e1f328e"
ARTIFACT="$MODULE/onthe15-test-x15-zmk.uf2"
BUILD="$DYA_ZMK/build/onthe15-test-x15-zmk"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"

test "$(git -C "$KSCAN_DIAG_MODULE" rev-parse HEAD)" = "$EXPECTED_KSCAN_DIAG"
test -z "$(git -C "$KSCAN_DIAG_MODULE" status --short)"

"$MODULE/build_dya.sh" kscan-diagnostics-x15

for expected in \
    CONFIG_ZMK_KSCAN_DIAGNOSTICS=y \
    CONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC=y \
    CONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC_UNSECURED=y \
    CONFIG_ZMK_KSCAN_DIAGNOSTICS_MAX_POSITIONS=64 \
    CONFIG_ZMK_STUDIO=y \
    CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=256 \
    CONFIG_ZMK_DEVICE_INFO=y \
    CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y \
    CONFIG_ONTHE15_STATUS_INDICATOR=y \
    CONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON=y \
    CONFIG_ONTHE15_KEYMAP_FORCE_STOCK=y \
    CONFIG_USB_CDC_ACM=y
do
    grep -qx "$expected" "$CONFIG"
done

# Repair-image intent: no reactive lighting, and none of the runtime editing
# subsystems that only belong in the distributed image.
grep -qx '# CONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS is not set' "$CONFIG"
# Those modules are not in this build at all, so Kconfig emits no symbol for
# them - assert the enabled form is absent rather than expecting "is not set".
! grep -qx 'CONFIG_ZMK_RUNTIME_COMBO=y' "$CONFIG"
! grep -qx 'CONFIG_ZMK_RUNTIME_MACRO=y' "$CONFIG"

# Device info is deliberately readable while locked in this repair image.
grep -qx '# CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK is not set' "$CONFIG"

# Hardware-test conventions shared with build.sh's build_test_x15: the shield's
# own A-Z-in-physical-order keymap (not a config/ overlay keymap), and lighting
# state kept out of the daily "onthe15/underglow_v8" subtree.
grep -qx 'CONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH="onthe15/test_lighting_v1"' "$CONFIG"
grep -q "KEYMAP_FILE:STRING=$MODULE/boards/shields/on_the_15_x15/on_the_15_x15.keymap" \
    "$BUILD/CMakeCache.txt"
grep -q 'default-underglow-enabled' "$BUILD/zephyr/zephyr.dts"

grep -aq 'cormoran__kscan_diagnostics' "$ELF"
grep -aq 'zmk__device_info' "$ELF"

test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

# The test image stays locked: only the unlocked repair target below drops it.
grep -qx 'CONFIG_ZMK_STUDIO_LOCKING=y' "$CONFIG"

# The repair-only sibling: the same target with Studio locking removed, so the
# keymap and behavior RPCs answer on a board that cannot type the unlock combo.
# It ships as its own artifact so an unlocked-by-build image is never mistaken
# for the test one.
DIAG_ARTIFACT="$MODULE/onthe15-diag-x15-zmk.uf2"
DIAG_BUILD="$DYA_ZMK/build/onthe15-diag-x15-zmk"
DIAG_CONFIG="$DIAG_BUILD/zephyr/.config"

"$MODULE/build_dya.sh" kscan-diagnostics-unlocked-x15

grep -qx '# CONFIG_ZMK_STUDIO_LOCKING is not set' "$DIAG_CONFIG"
grep -qx 'CONFIG_ZMK_KSCAN_DIAGNOSTICS=y' "$DIAG_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO=y' "$DIAG_CONFIG"
grep -qx 'CONFIG_ONTHE15_KEYMAP_FORCE_STOCK=y' "$DIAG_CONFIG"
grep -qx 'CONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH="onthe15/test_lighting_v1"' "$DIAG_CONFIG"
! grep -qx 'CONFIG_ZMK_RUNTIME_COMBO=y' "$DIAG_CONFIG"
! grep -qx 'CONFIG_ZMK_RUNTIME_MACRO=y' "$DIAG_CONFIG"

test -s "$DIAG_ARTIFACT"
shasum -a 256 "$DIAG_ARTIFACT"
wc -c "$DIAG_ARTIFACT"

echo "DYA Kscan Diagnostics x15 verification passed"
