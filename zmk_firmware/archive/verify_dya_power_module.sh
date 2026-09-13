#!/bin/sh
# Verify the isolated generic Power Settings Phase 2 target.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD_DIR="$DYA_ZMK/build/dya-power-module-x15-onthe15-zmk-1fc72aaf"
BUILD_CONFIG="$BUILD_DIR/zephyr/.config"
ARTIFACT="$MODULE/dya-power-module-x15-onthe15-zmk-1fc72aaf.uf2"
TEST_BIN="${TMPDIR:-/tmp}/zmk-power-settings-validation-test"
WEB="$MODULE/modules/onthe15-studio/web"

cc -std=c11 -Wall -Wextra -Werror \
    -I"$MODULE/modules/zmk-feature-power-settings/include" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_validation.c" \
    "$MODULE/modules/zmk-feature-power-settings/tests/power_settings_validation_test.c" \
    -o "$TEST_BIN"
"$TEST_BIN"

"$MODULE/build_dya.sh" power-module-x15

grep -qx 'CONFIG_ZMK_POWER_SETTINGS=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH="onthe15/power_v1"' "$BUILD_CONFIG"
grep -qx '# CONFIG_ONTHE15_POWER_SETTINGS is not set' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=64' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -aq 'onthe15/power_v1/state' "$BUILD_DIR/zephyr/zmk.elf"
grep -aq 'zmk_power_settings_set_memory' "$BUILD_DIR/zephyr/zmk.elf"
grep -aq 'cormoran_ble' "$BUILD_DIR/zephyr/zmk.elf"

(cd "$WEB" && npm test -- --runInBand && npm run build)

test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA generic Power Settings Phase 2 verification passed"
