#!/bin/sh
# Build the x7 Eneloop discharge-curve firmware with both indicators held on.
set -eu

ZMK="${ZMK:-/Volumes/Primary/GitHub/zmk}"
MODULE="$(cd "$(dirname "$0")" && pwd)"
WEST="$ZMK/.venv/bin/west"
EXPECTED_ZMK="faaf39d9f59cd2a27eca3739cdd9eb197654299b"
BUILD_NAME="battery-curve-x7-onthe15-zmk-faaf39d9"

actual_zmk="$(git -C "$ZMK" rev-parse HEAD)"
if [ "$actual_zmk" != "$EXPECTED_ZMK" ]; then
    echo "ZMK HEAD must be $EXPECTED_ZMK (found $actual_zmk)" >&2
    exit 1
fi

(cd "$ZMK" && PATH="$ZMK/.venv/bin:$PATH" "$WEST" build -p -s app \
    -d "build/$BUILD_NAME" -b "xiao_ble//zmk" -- \
    -DSHIELD=on_the_15 \
    -DSNIPPET="nrf52840-nosd;studio-rpc-usb-uart" \
    -DZMK_CONFIG="$MODULE/config/studio" \
    -DZMK_EXTRA_MODULES="$MODULE" \
    -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x7-battery-curve.overlay" \
    -DCONFIG_ZMK_STUDIO=y \
    -DCONFIG_ZMK_RGB_UNDERGLOW=n \
    -DCONFIG_ONTHE15_STATUS_INDICATOR=n \
    -DCONFIG_ONTHE15_LIGHTING=n \
    -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
    -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60 \
    -DCONFIG_ZMK_SLEEP=n)

cp "$ZMK/build/$BUILD_NAME/zephyr/zmk.uf2" "$MODULE/$BUILD_NAME.uf2"
