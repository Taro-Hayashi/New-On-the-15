#!/bin/sh
# Verify the isolated split-ready Power Settings Phase 3 target.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD_DIR="$DYA_ZMK/build/dya-power-sync-x15-onthe15-zmk-1fc72aaf"
BUILD_CONFIG="$BUILD_DIR/zephyr/.config"
ARTIFACT="$MODULE/dya-power-sync-x15-onthe15-zmk-1fc72aaf.uf2"
TEST_BIN="${TMPDIR:-/tmp}/zmk-power-settings-sync-test"

cc -std=c11 -Wall -Wextra -Werror \
    -I"$MODULE/modules/zmk-feature-power-settings/include" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_validation.c" \
    "$MODULE/modules/zmk-feature-power-settings/src/power_settings_sync.c" \
    "$MODULE/modules/zmk-feature-power-settings/tests/power_settings_sync_test.c" \
    -o "$TEST_BIN"
"$TEST_BIN"

"$MODULE/build_dya.sh" power-sync-x15

grep -qx 'CONFIG_ZMK_POWER_SETTINGS=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SYNC_API=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH="onthe15/power_v1"' "$BUILD_CONFIG"
grep -qx '# CONFIG_ONTHE15_POWER_SETTINGS is not set' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=64' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$BUILD_CONFIG"
grep -aq 'zmk_power_settings_sync_resolve' "$BUILD_DIR/zephyr/zmk.elf"
grep -aq 'zmk_power_settings_sync_get_local_snapshot' "$BUILD_DIR/zephyr/zmk.elf"
grep -aq 'onthe15/power_v1/state' "$BUILD_DIR/zephyr/zmk.elf"

test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA split-ready Power Settings Phase 3 verification passed"
