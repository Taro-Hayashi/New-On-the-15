#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DEPS_ROOT="${ZMK_DEPS_ROOT:-$MODULE/.build/deps}"
TARGET="${1:-power-x15}"

ZMK_DEPS_ROOT="$DEPS_ROOT" "$MODULE/prepare_zmk_build.sh"

case "$TARGET" in
    host-rgb-split-*)
        HOST_RGB_MODULE="$DEPS_ROOT/zmk-host-rgb-sync-split"
        ;;
    *)
        HOST_RGB_MODULE="$DEPS_ROOT/zmk-host-rgb-sync-x15"
        ;;
esac

ARTIFACT_ROOT="${UF2_OUTPUT_ROOT:-$MODULE/.build/artifacts}"
mkdir -p "$ARTIFACT_ROOT"

ZMK_DEPS_ROOT="$DEPS_ROOT" \
DYA_ZMK="$DEPS_ROOT/zmk-dya" \
STABLE_ZMK="$DEPS_ROOT/zmk-stable" \
LIGHTING_MODULE="$DEPS_ROOT/zmk-matrix-lighting" \
HOST_RGB_MODULE="$HOST_RGB_MODULE" \
BLE_MANAGEMENT_MODULE="$DEPS_ROOT/zmk-module-ble-management" \
DEFAULT_LAYER_MODULE="$DEPS_ROOT/zmk-feature-default-layer" \
CUSTOM_SETTINGS_MODULE="$DEPS_ROOT/zmk-feature-custom-settings" \
OS_DETECTION_MODULE="$DEPS_ROOT/zmk-feature-os-detection" \
DEVICE_INFO_MODULE="$DEPS_ROOT/zmk-feature-device-info" \
RUNTIME_COMBO_MODULE="$DEPS_ROOT/zmk-feature-runtime-combo" \
RUNTIME_MACRO_MODULE="$DEPS_ROOT/zmk-feature-runtime-macro" \
KSCAN_DIAG_MODULE="$DEPS_ROOT/zmk-feature-kscan-diagnostics" \
ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$DEPS_ROOT/zephyr-sdk}" \
DYA_BUILD_ROOT="${DYA_BUILD_ROOT:-$MODULE/.build/output}" \
UF2_OUTPUT_ROOT="$ARTIFACT_ROOT" \
exec "$MODULE/build_dya.sh" "$@"
