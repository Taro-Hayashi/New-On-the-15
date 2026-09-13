#!/bin/sh
set -eu

DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
MODULE="$(cd "$(dirname "$0")/.." && pwd)"
HOST_RGB_MODULE="${HOST_RGB_MODULE:-/Volumes/Primary/GitHub/zmk-host-rgb-sync}"
EXPECTED_HOST_RGB="e2e6a4749f73b9ee95a35c6199a93b5347286f3a"
BUILD="$DYA_ZMK/build/onthe15-signalrgb-trial-x15-zmk"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"
UF2="$MODULE/onthe15-signalrgb-trial-x15-zmk.uf2"

test -f "$CONFIG"
test -f "$ELF"
test -f "$UF2"

actual_host_rgb="$(git -C "$HOST_RGB_MODULE" rev-parse HEAD 2>/dev/null || true)"
if [ "$actual_host_rgb" != "$EXPECTED_HOST_RGB" ]; then
    echo "Host RGB Sync HEAD must be $EXPECTED_HOST_RGB (found ${actual_host_rgb:-missing})" >&2
    exit 1
fi

require_config() {
    if ! grep -qx "$1" "$CONFIG"; then
        echo "missing config: $1" >&2
        exit 1
    fi
}

require_config 'CONFIG_ZMK_HOST_RGB_OPENRGB=y'
require_config 'CONFIG_ZMK_KEYBOARD_NAME="On15 RGB Trial"'
require_config 'CONFIG_ZMK_HOST_RGB_TIMEOUT_MS=5000'
require_config 'CONFIG_USB_CDC_ACM=y'
require_config 'CONFIG_USB_HID_DEVICE_COUNT=2'
require_config 'CONFIG_ZMK_USB=y'
require_config 'CONFIG_ZMK_STUDIO=y'
require_config 'CONFIG_ZMK_ONTHE15_STUDIO_RPC=y'
require_config 'CONFIG_ZMK_MATRIX_LIGHTING=y'
require_config 'CONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y'
require_config 'CONFIG_ZMK_POWER_SETTINGS=y'
require_config 'CONFIG_ZMK_RUNTIME_COMBO=y'
require_config 'CONFIG_ZMK_RUNTIME_MACRO=y'
require_config 'CONFIG_ZMK_DEVICE_INFO=y'
require_config 'CONFIG_ZMK_BLE_MANAGEMENT=y'
require_config 'CONFIG_ZMK_DEFAULT_LAYER=y'
require_config 'CONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=y'
require_config 'CONFIG_ZMK_OS_DETECTION=y'
require_config 'CONFIG_ZMK_OS_DETECTION_USB=y'
require_config 'CONFIG_ZMK_OS_DETECTION_BLE=y'
require_config 'CONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y'

if ! grep -q 'ZMK_CONFIG:.*=.*/zmk_firmware/config/personal-default-layer' \
    "$BUILD/CMakeCache.txt"; then
    echo "trial was not built from the personal-default-layer config" >&2
    exit 1
fi

if grep -q 'CONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH="onthe15/underglow_v8"' "$CONFIG" &&
   grep -q 'CONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH="onthe15/power_v1"' "$CONFIG"; then
    :
else
    echo "normal settings paths were not preserved" >&2
    exit 1
fi

for symbol in host_rgb_thread zmk_openrgb_process zmk_lighting_host_release; do
    if ! nm "$ELF" | grep -q " $symbol$"; then
        echo "missing ELF symbol: $symbol" >&2
        exit 1
    fi
done

PYTHONPYCACHEPREFIX=/tmp/onthe15-host-rgb-pycache \
    python3 -m py_compile "$HOST_RGB_MODULE/tools/host_rgb_diag.py"
cc -std=c11 -Wall -Wextra -Werror \
    -I"$HOST_RGB_MODULE/include" \
    "$HOST_RGB_MODULE/tests/openrgb_protocol_test.c" \
    "$HOST_RGB_MODULE/src/openrgb_protocol.c" \
    -o /tmp/onthe15-openrgb-protocol-test
/tmp/onthe15-openrgb-protocol-test
node "$HOST_RGB_MODULE/integrations/signalrgb/test_plugin.mjs"

shasum -a 256 "$UF2"
echo "SignalRGB trial static verification: PASS"
