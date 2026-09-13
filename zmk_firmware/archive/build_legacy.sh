#!/bin/sh
# Build all On the 15 v4 ZMK firmware variants and copy the UF2s here.
# Requires the pinned ZMK west workspace described in README.md.
set -eu

ZMK="${ZMK:-/Volumes/Primary/GitHub/zmk}"
MODULE="$(cd "$(dirname "$0")" && pwd)"
LIGHTING_MODULE="${LIGHTING_MODULE:-/Volumes/Primary/GitHub/zmk-matrix-lighting}"
if [ -x "$ZMK/.venv/bin/west" ]; then
    WEST="$ZMK/.venv/bin/west"
elif [ -x "$ZMK/.venv/Scripts/west.exe" ]; then
    WEST="$ZMK/.venv/Scripts/west.exe"
else
    echo "west was not found in $ZMK/.venv" >&2
    exit 1
fi
EXPECTED_ZMK="faaf39d9f59cd2a27eca3739cdd9eb197654299b"

actual_zmk="$(git -C "$ZMK" rev-parse HEAD)"
if [ "$actual_zmk" != "$EXPECTED_ZMK" ]; then
    echo "ZMK HEAD must be $EXPECTED_ZMK (found $actual_zmk)" >&2
    exit 1
fi

build() {
    name="$1"
    shield="$2"
    snippets="$3"
    shift 3
    (cd "$ZMK" && PATH="$ZMK/.venv/bin:$PATH" "$WEST" build -p -s app -d "build/$name" -b "xiao_ble//zmk" -- \
        -DSHIELD="$shield" -DSNIPPET="$snippets" \
        -DZMK_EXTRA_MODULES="$MODULE;$LIGHTING_MODULE" -DCONFIG_ZMK_RGB_UNDERGLOW=n "$@")
    cp "$ZMK/build/$name/zephyr/zmk.uf2" "$MODULE/$name.uf2"
}

build_test() {
    build test-x7x8-onthe15-zmk-faaf39d9 on_the_15 nrf52840-nosd \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/non-split-leds.overlay;$MODULE/config/test-leds-on.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH=\"onthe15/test_lighting_v1\"
    build_test_x15
}

build_test_x15() {
    build test-x15-onthe15-zmk-faaf39d9 on_the_15_x15 nrf52840-nosd \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/test-leds-on.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH=\"onthe15/test_lighting_v1\"
}

build_studio() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    studio_args="-DZMK_CONFIG=$MODULE/config/studio -DCONFIG_ZMK_STUDIO=y"

    # shellcheck disable=SC2086
    build studio-non-split-x7x8-onthe15-zmk-faaf39d9 on_the_15 "$studio_snippets" $studio_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/non-split-leds.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
    build_studio_x15
    # Only the split central carries the USB Studio RPC transport.
    # shellcheck disable=SC2086
    build left-central-split-x7x8-onthe15-zmk-faaf39d9 on_the_15_split_left "$studio_snippets" $studio_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/split-left-leds.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
    # shellcheck disable=SC2086
    build right-peripheral-split-x7x8-onthe15-zmk-faaf39d9 on_the_15_split_right nrf52840-nosd $studio_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/studio/on_the_15_split_right.overlay;$MODULE/config/split-right-leds.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

build_studio_x15() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    studio_args="-DZMK_CONFIG=$MODULE/config/studio -DCONFIG_ZMK_STUDIO=y"

    # shellcheck disable=SC2086
    build studio-x15-onthe15-zmk-faaf39d9 on_the_15_x15 "$studio_snippets" $studio_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

build_personal() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    build_personal_x15
    # Only the split central carries the USB Studio RPC transport.
    # shellcheck disable=SC2086
    build personal-left-central-faaf39d9 on_the_15_split_left "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/split-left-leds.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y \
        -DCONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
    # shellcheck disable=SC2086
    build personal-right-peripheral-faaf39d9 on_the_15_split_right nrf52840-nosd $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/studio/on_the_15_split_right.overlay;$MODULE/config/split-right-leds.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

build_personal_x15() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    # shellcheck disable=SC2086
    build personal-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

build_x15() {
    build_test_x15
    build_studio_x15
    build_personal_x15
}

build_power_test() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y"
    sleep_args="-DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=60000"

    # Keep this separate from the daily-use personal build until wake from the
    # 74HC595-backed matrix has been verified on hardware.
    # shellcheck disable=SC2086
    build power-test-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        $sleep_args
    # Keep the central awake in normal idle so a waking peripheral can reconnect;
    # a central in system-off cannot be woken over BLE by the peripheral.
    # shellcheck disable=SC2086
    build power-test-left-central-faaf39d9 on_the_15_split_left "$studio_snippets" \
        $personal_args
    # shellcheck disable=SC2086
    build power-test-right-peripheral-faaf39d9 on_the_15_split_right nrf52840-nosd \
        $personal_args $sleep_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/studio/on_the_15_split_right.overlay"
}

build_indicator_test() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    # shellcheck disable=SC2086
    build indicator-test-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/indicator-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y
}

build_sk6812_test() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    # USB-powered, low-brightness solid-color test. Keep separate from daily use
    # until power-off behavior and BLE stability have been verified on hardware.
    # shellcheck disable=SC2086
    build sk6812-test-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/sk6812-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y
}

build_battery_test() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    # Report Eneloop AAA state of charge every 60 seconds.
    # shellcheck disable=SC2086
    build battery-test-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

build_battery_settings_test() {
    studio_snippets="nrf52840-nosd;studio-rpc-usb-uart"
    personal_args="-DZMK_CONFIG=$MODULE/config/personal -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000"

    # Dedicated test image: only this overlay binds &bat_set 0/1.
    # shellcheck disable=SC2086
    build battery-settings-test-x15-faaf39d9 on_the_15_x15 "$studio_snippets" $personal_args \
        -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay;$MODULE/config/battery-settings-test.overlay" \
        -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
        -DCONFIG_ONTHE15_LIGHTING=y \
        -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
        -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
        -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
}

case "${1:-all}" in
    test)
        build_test
        ;;
    studio)
        build_studio
        ;;
    personal)
        build_personal
        ;;
    x15)
        build_x15
        ;;
    power-test)
        build_power_test
        ;;
    indicator-test)
        build_indicator_test
        ;;
    sk6812-test)
        build_sk6812_test
        ;;
    battery-test)
        build_battery_test
        ;;
    battery-settings-test)
        build_battery_settings_test
        ;;
    settings-reset)
        build settings-reset-xiao-ble-zmk-faaf39d9 settings_reset nrf52840-nosd
        ;;
    all)
        build_test
        build_studio
        build_personal
        build settings-reset-xiao-ble-zmk-faaf39d9 settings_reset nrf52840-nosd
        ;;
    *)
        echo "usage: $0 [all|test|studio|personal|x15|power-test|indicator-test|sk6812-test|battery-test|battery-settings-test|settings-reset]" >&2
        exit 2
        ;;
esac
