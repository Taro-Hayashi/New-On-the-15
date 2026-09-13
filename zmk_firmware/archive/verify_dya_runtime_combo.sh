#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD="$DYA_ZMK/build/dya-runtime-combo-x15-onthe15-zmk-1fc72aaf"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"
ARTIFACT="$MODULE/dya-runtime-combo-x15-onthe15-zmk-1fc72aaf.uf2"
RUNTIME_COMBO_MODULE="${RUNTIME_COMBO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-runtime-combo}"
CUSTOM_SETTINGS_MODULE="${CUSTOM_SETTINGS_MODULE:-/Volumes/Primary/GitHub/zmk-feature-custom-settings}"
EXPECTED_RUNTIME_COMBO="d9490e7b5d41c516221d131241009e81740efcee"
EXPECTED_CUSTOM_SETTINGS="c6a7fef3a3be3d3ace5de9a4b0628c6418cd1f3f"
RUNTIME_COMBO_PATCH="$MODULE/patches/dya-runtime-combo-list-skip-unreadable-slot.patch"
RUNTIME_COMBO_DIAG_PATCH="$MODULE/patches/dya-runtime-combo-diagnostics.patch"
CUSTOM_SETTINGS_PATCH="$MODULE/patches/dya-custom-settings-array-ref-growth.patch"
CUSTOM_SETTINGS_BEHAVIOR_LOAD_PATCH="$MODULE/patches/dya-custom-settings-behavior-load-order.patch"
CUSTOM_SETTINGS_DIAG_PATCH="$MODULE/patches/dya-custom-settings-diagnostics.patch"
EXPECTED_SHA256="ce3b3f0cdbaca7d8e4054491e71210adfea851c2521933a37bc17f4788e1f285"
EXPECTED_SIZE="575488"
READELF="/Volumes/Primary/GitHub/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin/arm-zephyr-eabi-readelf"

test "$(git -C "$RUNTIME_COMBO_MODULE" rev-parse HEAD)" = "$EXPECTED_RUNTIME_COMBO"
test "$(git -C "$CUSTOM_SETTINGS_MODULE" rev-parse HEAD)" = "$EXPECTED_CUSTOM_SETTINGS"

# Both modules carry DYA fix patches that are not upstream yet, so neither tree
# can be clean. Pin the exact expected working-tree state instead: every fix
# patch reverse-applies (i.e. is present), and neither diagnostics patch does
# (i.e. diagnostic logging cannot reach a verified artifact). Drop the
# corresponding check once a fix lands upstream and EXPECTED_* moves to the
# commit that carries it.
git -C "$RUNTIME_COMBO_MODULE" apply --reverse --check "$RUNTIME_COMBO_PATCH"
git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check "$CUSTOM_SETTINGS_PATCH"
git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check "$CUSTOM_SETTINGS_BEHAVIOR_LOAD_PATCH"
! git -C "$RUNTIME_COMBO_MODULE" apply --reverse --check "$RUNTIME_COMBO_DIAG_PATCH" 2>/dev/null
! git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check "$CUSTOM_SETTINGS_DIAG_PATCH" 2>/dev/null
(cd "$RUNTIME_COMBO_MODULE/web" && npm test -- --runInBand && npm run build)
"$MODULE/build_dya.sh" runtime-combo-x15

grep -qx 'CONFIG_ZMK_RUNTIME_COMBO=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=4' "$CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=4' "$CONFIG"
grep -qx 'CONFIG_ZMK_CUSTOM_SETTINGS=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=128' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=96' "$CONFIG"
grep -qx 'CONFIG_ZMK_LOW_PRIORITY_THREAD_STACK_SIZE=2048' "$CONFIG"
grep -aq 'cormoran__runtime_combo' "$ELF"
grep -aq 'cormoran_custom_settings' "$ELF"
grep -aq 'Test Short' "$ELF"
grep -aq 'Test Long' "$ELF"
"$READELF" -n "$ELF" | grep -q 'Build ID:'
test "$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')" = "$EXPECTED_SHA256"
test "$(wc -c < "$ARTIFACT" | tr -d ' ')" = "$EXPECTED_SIZE"

echo "DYA Runtime Combo x15 verification passed"
