#!/bin/sh
# Verify the isolated personal x15 Default Layer + OS detection trial.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD_DIR="$DYA_ZMK/build/onthe15-private-x15-zmk"
BUILD_CONFIG="$BUILD_DIR/zephyr/.config"
ELF="$BUILD_DIR/zephyr/zmk.elf"
ARTIFACT="$MODULE/onthe15-private-x15-zmk.uf2"

"$MODULE/build_dya.sh" personal-default-layer-x15

grep -qx 'CONFIG_ZMK_DEFAULT_LAYER=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEFAULT_LAYER_MIN_INDEX=1' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEFAULT_LAYER_MAX_INDEX=2' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_DEFAULT_LAYER_OS_DETECTION=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_OS_DETECTION=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_OS_DETECTION_USB=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_OS_DETECTION_BLE=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_OS_DETECTION_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx '# CONFIG_ZMK_OS_DETECTION_LAYER_AUTO_SWITCH is not set' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_CUSTOM_SETTINGS=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=128' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT=y' "$BUILD_CONFIG"
grep -qx 'CONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y' "$BUILD_CONFIG"

grep -aq 'cormoran__default_layer' "$ELF"
grep -aq 'cormoran__os_detection' "$ELF"
grep -aq 'cormoran_ble' "$ELF"
grep -aq 'onthe15__studio' "$ELF"

test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA personal x15 Default Layer verification passed"
