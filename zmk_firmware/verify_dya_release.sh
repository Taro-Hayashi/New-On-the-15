#!/bin/sh
# Verify the fixed x15 DYA Studio release target and its Web UI.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
ARTIFACT="$MODULE/onthe15-x15-zmk.uf2"
BUILD_CONFIG="$DYA_ZMK/build/onthe15-x15-zmk/zephyr/.config"
WEB="$MODULE/modules/onthe15-studio/web"
TEST_BIN="${TMPDIR:-/tmp}/zmk-power-settings-validation-test"
SYNC_TEST_BIN="${TMPDIR:-/tmp}/zmk-power-settings-sync-test"

cc -std=c11 -Wall -Wextra -Werror \
    -I"$MODULE/modules/zmk-feature-power-settings/include" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_validation.c" \
    "$MODULE/modules/zmk-feature-power-settings/tests/power_settings_validation_test.c" \
    -o "$TEST_BIN"
"$TEST_BIN"

cc -std=c11 -Wall -Wextra -Werror \
    -I"$MODULE/modules/zmk-feature-power-settings/include" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_validation.c" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_sync.c" \
    "$MODULE/modules/zmk-feature-power-settings/tests/power_settings_sync_test.c" \
    -o "$SYNC_TEST_BIN"
"$SYNC_TEST_BIN"

"$MODULE/build_dya.sh" power-x15

grep -qx 'CONFIG_ZMK_POWER_SETTINGS=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH="onthe15/power_v1"' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SYNC_API=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx '# CONFIG_ONTHE15_POWER_SETTINGS is not set' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=256' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEVICE_INFO=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=16' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=5' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_MACRO=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_MACRO_COUNT=8' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128' "$BUILD_CONFIG"
grep -qx '# CONFIG_ZMK_HOST_RGB_OPENRGB is not set' "$BUILD_CONFIG"
grep -qx 'CONFIG_USB_CDC_ACM=y' "$BUILD_CONFIG"
grep -aq 'cormoran_ble' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'onthe15/power_v1/state' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'zmk_power_settings_set_memory' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'zmk__settings' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'zmk__device_info' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'cormoran__runtime_combo' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
grep -aq 'cormoran__runtime_macro' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zmk.elf"
# The distributed keymap must not bind a runtime macro: macros are assigned
# from Studio, and a compiled-in &rmacro would leave a stale behavior
# reference behind if the module were ever dropped.
! grep -q 'rmacro' "$DYA_ZMK/build/onthe15-x15-zmk/zephyr/zephyr.dts"

(cd "$WEB" && npm test -- --runInBand && npm run build)

test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA x15 release verification passed"
