#!/bin/sh
# Build the isolated x15 DYA Studio compatibility image.
set -eu

DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
MODULE="$(cd "$(dirname "$0")" && pwd)"
STUDIO_MODULE="$MODULE/modules/onthe15-studio"
LIGHTING_MODULE="${LIGHTING_MODULE:-/Volumes/Primary/GitHub/zmk-matrix-lighting}"
HOST_RGB_MODULE="${HOST_RGB_MODULE:-/Volumes/Primary/GitHub/zmk-host-rgb-sync}"
POWER_SETTINGS_MODULE="$MODULE/modules/zmk-feature-power-settings"
BLE_MANAGEMENT_MODULE="${BLE_MANAGEMENT_MODULE:-/Volumes/Primary/GitHub/zmk-module-ble-management}"
DEFAULT_LAYER_MODULE="${DEFAULT_LAYER_MODULE:-/Volumes/Primary/GitHub/zmk-feature-default-layer}"
CUSTOM_SETTINGS_MODULE="${CUSTOM_SETTINGS_MODULE:-/Volumes/Primary/GitHub/zmk-feature-custom-settings}"
OS_DETECTION_MODULE="${OS_DETECTION_MODULE:-/Volumes/Primary/GitHub/zmk-feature-os-detection}"
DEVICE_INFO_MODULE="${DEVICE_INFO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-device-info}"
RUNTIME_COMBO_MODULE="${RUNTIME_COMBO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-runtime-combo}"
RUNTIME_MACRO_MODULE="${RUNTIME_MACRO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-runtime-macro}"
KSCAN_DIAG_MODULE="${KSCAN_DIAG_MODULE:-/Volumes/Primary/GitHub/zmk-feature-kscan-diagnostics}"
EXPECTED_DYA_ZMK="1fc72aaff7a42bd533c1f4c9b3f23c5317c745f4"
EXPECTED_BLE_MANAGEMENT="57738cc4fc6ba80e82a7ac57741a0339cb186cd4"
EXPECTED_DEFAULT_LAYER="ef1f5b61b14e4f78172d3b6590afb3a39412fafe"
EXPECTED_CUSTOM_SETTINGS="c6a7fef3a3be3d3ace5de9a4b0628c6418cd1f3f"
EXPECTED_OS_DETECTION="3052679f645b8fc1997275c2eaa6b86bdd55ca01"
EXPECTED_DEVICE_INFO="8cedd2dd9f04e19ea5a17b94914dd47a09d8db11"
EXPECTED_MATRIX_LIGHTING="6a11550240e2f2dd3175d607490faead46290c6d"
EXPECTED_HOST_RGB="e2e6a4749f73b9ee95a35c6199a93b5347286f3a"
EXPECTED_RUNTIME_COMBO="d9490e7b5d41c516221d131241009e81740efcee"
EXPECTED_RUNTIME_MACRO="38530962eb7061b60efcb98e84585cfb1f0cb6de"
EXPECTED_KSCAN_DIAG="1432f7fe0cfe903cd7d3c9931ae6bd6f2e1f328e"
POWER_PATCH="$MODULE/patches/dya-runtime-power-settings.patch"
CUSTOM_SETTINGS_PATCH="$MODULE/patches/dya-custom-settings-array-ref-growth.patch"
RUNTIME_COMBO_PATCH="$MODULE/patches/dya-runtime-combo-list-skip-unreadable-slot.patch"
RUNTIME_COMBO_DIAG_PATCH="$MODULE/patches/dya-runtime-combo-diagnostics.patch"
CUSTOM_SETTINGS_BEHAVIOR_LOAD_PATCH="$MODULE/patches/dya-custom-settings-behavior-load-order.patch"
CUSTOM_SETTINGS_DIAG_PATCH="$MODULE/patches/dya-custom-settings-diagnostics.patch"
RUNTIME_COMBO_DIAG=""
RUNTIME_MACRO_PATCH="$MODULE/patches/dya-runtime-macro-rename-when-slots-full.patch"
RUNTIME_MACRO_DIAG_PATCH="$MODULE/patches/dya-runtime-macro-diagnostics.patch"
RUNTIME_MACRO_DIAG=""

if [ -x "$DYA_ZMK/.venv/bin/west" ]; then
    WEST="$DYA_ZMK/.venv/bin/west"
    TOOL_PATH="$DYA_ZMK/.venv/bin"
elif [ -x /Volumes/Primary/GitHub/zmk/.venv/bin/west ]; then
    WEST=/Volumes/Primary/GitHub/zmk/.venv/bin/west
    TOOL_PATH=/Volumes/Primary/GitHub/zmk/.venv/bin
else
    echo "west was not found in the DYA or stable ZMK workspace" >&2
    exit 1
fi

actual_dya_zmk="$(git -C "$DYA_ZMK" rev-parse HEAD)"
if [ "$actual_dya_zmk" != "$EXPECTED_DYA_ZMK" ]; then
    echo "DYA ZMK HEAD must be $EXPECTED_DYA_ZMK (found $actual_dya_zmk)" >&2
    exit 1
fi

if ! git -C "$DYA_ZMK" apply --reverse --check "$POWER_PATCH"; then
    echo "DYA ZMK must have the runtime power settings patch applied" >&2
    exit 1
fi

DEFAULT_LAYER_CONFIG=""
ZMK_CONFIG_DIR="$MODULE/config/studio"
LIGHTING_SETTINGS_PATH="onthe15/underglow_v8"
INDICATOR_TEST_CONFIG=""
RPC_RX_BUF_SIZE=64
RPC_TX_BUF_SIZE=160
POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=y"
POWER_SETTINGS_EXTRA_MODULE=""
DEVICE_INFO_CONFIG=""
DEVICE_INFO_EXTRA_MODULE=""
RUNTIME_COMBO_CONFIG=""
RUNTIME_COMBO_EXTRA_MODULE=""
RUNTIME_MACRO_CONFIG=""
RUNTIME_MACRO_EXTRA_MODULE=""
KSCAN_DIAG_CONFIG=""
KSCAN_DIAG_EXTRA_MODULE=""
HOST_RGB_EXTRA_MODULE=""
HOST_RGB_FIRMWARE_VERSION=""
HOST_RGB_DEVICE_NAME=""
HOST_RGB_DEVICE_VENDOR=""
TARGET_EXTRA_OVERLAY=""
BUILD_SOURCE_DATE_EPOCH=""
NANOPB_ERRMSG_CONFIG=""

case "${1:-power-x15}" in
    runtime-combo-diag-x15)
        # Diagnostic-only target: same configuration as power-x15 plus a second
        # USB CDC ACM console carrying the Runtime Combo DIAG log lines
        # (patches/dya-runtime-combo-diagnostics.patch). Never promote this to a
        # release artifact.
        ARTIFACT="dya-runtime-combo-diag-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart;zmk-usb-logging"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=4 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=4 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=96"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        RPC_RX_BUF_SIZE=128
        RUNTIME_COMBO_DIAG="y"
        ;;
    kscan-diagnostics-x15)
        # Manufacturing / repair only. Never include this in the distributed
        # image or the personal daily image: the diagnostics RPC is opened
        # while the device is locked (see below), and the target carries no
        # lighting effects.
        ARTIFACT="dya-kscan-diagnostics-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        # A repair image wants a quiet board: no reactive effects competing
        # with the key-press visualization in the diagnostics web UI.
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=n"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        # 62 physical positions on the x15 layout; 64 covers it with slack.
        # The module statically allocates two per-position tables, so the
        # 128 default would waste RAM on a board this size.
        KSCAN_DIAG_CONFIG="-DCONFIG_ZMK_KSCAN_DIAGNOSTICS=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC_UNSECURED=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_MAX_POSITIONS=64"
        KSCAN_DIAG_EXTRA_MODULE=";$KSCAN_DIAG_MODULE"
        # MCU ID, reset cause, build ID and init state are worth having in
        # front of a failing board. Unlock is not required here for the same
        # reason as the diagnostics RPC: a keyboard with dead keys cannot type
        # the unlock combo.
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=n"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RPC_TX_BUF_SIZE=256
        # Adopt the existing hardware-test conventions (see build.sh
        # build_test_x15): the shield's own A-Z-in-physical-order keymap, both
        # status indicators held on, and the SK6812 groups lit from boot, with
        # lighting state kept in the test-only settings subtree so a repair
        # session never disturbs the daily "onthe15/underglow_v8" state.
        ZMK_CONFIG_DIR=""
        TARGET_EXTRA_OVERLAY=";$MODULE/config/test-leds-on.overlay"
        INDICATOR_TEST_CONFIG="-DCONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON=y -DCONFIG_ONTHE15_KEYMAP_FORCE_STOCK=y"
        LIGHTING_SETTINGS_PATH="onthe15/test_lighting_v1"
        ;;
    power-x15)
        ARTIFACT="dya-power-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        # The payload cap comes from the Runtime Macro block below, which needs
        # the larger of the two; the combo requests fit inside it.
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=16 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=5"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        RUNTIME_MACRO_CONFIG="-DCONFIG_ZMK_RUNTIME_MACRO=y -DCONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_MACRO_COUNT=8 -DCONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 -DCONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 -DCONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 -DCONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192"
        RUNTIME_MACRO_EXTRA_MODULE=";$RUNTIME_MACRO_MODULE"
        # The RX buffer takes the whole inbound frame, so it has to stay clear
        # of the 192-byte payload cap (see the runtime-macro-x15 comment).
        # No &rmacro binding ships in the distributed keymap: macros are
        # assigned to keys from Studio instead.
        RPC_RX_BUF_SIZE=256
        BUILD_SOURCE_DATE_EPOCH="1784356243"
        ;;
    power-module-x15)
        ARTIFACT="dya-power-module-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\""
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        ;;
    power-sync-x15)
        ARTIFACT="dya-power-sync-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        ;;
    settings-rpc-x15)
        ARTIFACT="dya-settings-rpc-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        ;;
    power-ui-cleanup-x15)
        ARTIFACT="dya-power-ui-cleanup-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        ;;
    device-info-x15)
        ARTIFACT="dya-device-info-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        BUILD_SOURCE_DATE_EPOCH="1784354484"
        ;;
    runtime-combo-x15)
        ARTIFACT="dya-runtime-combo-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=4 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=4 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=96"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        TARGET_EXTRA_OVERLAY=";$MODULE/config/runtime-combo-defaults.overlay"
        RPC_RX_BUF_SIZE=128
        BUILD_SOURCE_DATE_EPOCH="1784356243"
        ;;
    # Diagnostic-only twin of runtime-macro-x15: identical configuration plus a
    # second USB CDC ACM console. The Runtime Macro RPC handler already logs the
    # raw nanopb error behind "Failed to decode request", which is otherwise
    # invisible. Never promote this to a release artifact.
    runtime-macro-diag-x15)
        ARTIFACT="dya-runtime-macro-diag-x15-onthe15-zmk-1fc72aaf"
        RUNTIME_MACRO_DIAG="y"
        NANOPB_ERRMSG_CONFIG="-DCONFIG_NANOPB_NO_ERRMSG=n"
        # Experiment: the shared 160-byte TX ring is the only Studio-wide
        # buffer this target does not size for its larger payloads. Widen it
        # here only, to see whether the intermittent behavior-enumeration
        # stall follows it.
        RPC_TX_BUF_SIZE=512
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart;zmk-usb-logging"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=4 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=4"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        RUNTIME_MACRO_CONFIG="-DCONFIG_ZMK_RUNTIME_MACRO=y -DCONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_MACRO_COUNT=8 -DCONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 -DCONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 -DCONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 -DCONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192"
        RUNTIME_MACRO_EXTRA_MODULE=";$RUNTIME_MACRO_MODULE"
        TARGET_EXTRA_OVERLAY=";$MODULE/config/runtime-macro-test.overlay"
        # The RX buffer holds the whole inbound frame, not just the custom
        # subsystem payload: the Studio RPC envelope plus the CallRequest
        # wrapper (including the 23-byte "cormoran__runtime_macro" subsystem
        # id) share it with the payload. Sizing it equal to
        # REQUEST_PAYLOAD_MAX_BYTES therefore makes a full-size request
        # impossible to receive - it arrives truncated and nanopb reports
        # "Failed to decode request" before any validation runs. Keep a margin
        # over the payload cap, the way the runtime-combo target does
        # (payload 96 / RX 128).
        RPC_RX_BUF_SIZE=256
        ;;
    runtime-macro-x15)
        ARTIFACT="dya-runtime-macro-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=16 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=5"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        RUNTIME_MACRO_CONFIG="-DCONFIG_ZMK_RUNTIME_MACRO=y -DCONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_MACRO_COUNT=8 -DCONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 -DCONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 -DCONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 -DCONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192"
        RUNTIME_MACRO_EXTRA_MODULE=";$RUNTIME_MACRO_MODULE"
        TARGET_EXTRA_OVERLAY=";$MODULE/config/runtime-macro-test.overlay"
        # The RX buffer holds the whole inbound frame, not just the custom
        # subsystem payload: the Studio RPC envelope plus the CallRequest
        # wrapper (including the 23-byte "cormoran__runtime_macro" subsystem
        # id) share it with the payload. Sizing it equal to
        # REQUEST_PAYLOAD_MAX_BYTES therefore makes a full-size request
        # impossible to receive - it arrives truncated and nanopb reports
        # "Failed to decode request" before any validation runs. Keep a margin
        # over the payload cap, the way the runtime-combo target does
        # (payload 96 / RX 128).
        RPC_RX_BUF_SIZE=256
        BUILD_SOURCE_DATE_EPOCH="1784336411"
        ;;
    ble-x15)
        ARTIFACT="dya-ble-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        ;;
    personal-default-layer-x15)
        # Daily-use personal image: the same feature set as the distribution
        # power-x15 target, plus the per-OS default layers, and built from the
        # personal keymap instead of config/studio. Keeping it in step with
        # power-x15 also means Runtime Macro gets real-world use here before it
        # is promoted into the distributed image.
        ARTIFACT="dya-personal-default-layer-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        DEFAULT_LAYER_CONFIG="-DCONFIG_ZMK_DEFAULT_LAYER=y -DCONFIG_ZMK_DEFAULT_LAYER_MIN_INDEX=1 -DCONFIG_ZMK_DEFAULT_LAYER_MAX_INDEX=2 -DCONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=y -DCONFIG_ZMK_DEFAULT_LAYER_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION_USB=y -DCONFIG_ZMK_OS_DETECTION_BLE=y -DCONFIG_ZMK_OS_DETECTION_STUDIO_RPC=y -DCONFIG_ZMK_CUSTOM_SETTINGS=y -DCONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
        POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=16 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=5"
        RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
        RUNTIME_MACRO_CONFIG="-DCONFIG_ZMK_RUNTIME_MACRO=y -DCONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_MACRO_COUNT=8 -DCONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 -DCONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 -DCONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 -DCONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192"
        RUNTIME_MACRO_EXTRA_MODULE=";$RUNTIME_MACRO_MODULE"
        ZMK_CONFIG_DIR="$MODULE/config/personal-default-layer"
        # See the runtime-macro-x15 comment: the RX buffer takes the whole
        # frame, so it must stay clear of the 192-byte payload cap.
        RPC_RX_BUF_SIZE=256
        ;;
    power-static-x15)
        ARTIFACT="dya-power-static-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=n"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        ;;
    power-breathing-thread-x15)
        ARTIFACT="dya-power-breathing-thread-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=n"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        ;;
    power-breathing-rx64-x15)
        ARTIFACT="dya-power-breathing-rx64-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=n"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        ;;
    power-effects-rx64-x15)
        ARTIFACT="dya-power-effects-rx64-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        ;;
    host-rgb-x15)
        ARTIFACT="dya-host-rgb-x15-onthe15-zmk-1fc72aaf"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG="-DCONFIG_ZMK_HOST_RGB_OPENRGB=y -DCONFIG_USB_CDC_ACM=n -DCONFIG_CONSOLE=n -DCONFIG_UART_CONSOLE=n"
        HOST_RGB_EXTRA_MODULE=";$HOST_RGB_MODULE"
        HOST_RGB_FIRMWARE_VERSION="ZMK On the 15"
        HOST_RGB_DEVICE_NAME="On the 15"
        HOST_RGB_DEVICE_VENDOR="DYA Studio"
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        # OpenRGB's QMK detector requires Raw HID interface 1. The CDC ACM
        # Studio transport consumes interfaces 0-1, so this image uses BLE
        # for DYA Studio and keeps USB interfaces 0-1 for keyboard + Raw HID.
        BUILD_SNIPPETS="nrf52840-nosd"
        ;;
    *)
        echo "usage: $0 [power-x15|power-module-x15|power-sync-x15|settings-rpc-x15|power-ui-cleanup-x15|device-info-x15|runtime-combo-x15|runtime-macro-x15|ble-x15|personal-default-layer-x15|power-static-x15|power-breathing-thread-x15|power-breathing-rx64-x15|power-effects-rx64-x15|host-rgb-x15]" >&2
        exit 2
        ;;
esac

EXTRA_MODULES="$MODULE;$STUDIO_MODULE;$LIGHTING_MODULE$HOST_RGB_EXTRA_MODULE$POWER_SETTINGS_EXTRA_MODULE$DEVICE_INFO_EXTRA_MODULE$RUNTIME_COMBO_EXTRA_MODULE$RUNTIME_MACRO_EXTRA_MODULE$KSCAN_DIAG_EXTRA_MODULE"

if [ ! -d "$LIGHTING_MODULE/.git" ]; then
    echo "Matrix Lighting module was not found at $LIGHTING_MODULE" >&2
    exit 1
fi
actual_matrix_lighting="$(git -C "$LIGHTING_MODULE" rev-parse HEAD)"
if [ "$actual_matrix_lighting" != "$EXPECTED_MATRIX_LIGHTING" ]; then
    echo "Matrix Lighting HEAD must be $EXPECTED_MATRIX_LIGHTING (found $actual_matrix_lighting)" >&2
    exit 1
fi
if [ -n "$HOST_RGB_EXTRA_MODULE" ]; then
    actual_host_rgb="$(git -C "$HOST_RGB_MODULE" rev-parse HEAD 2>/dev/null || true)"
    if [ "$actual_host_rgb" != "$EXPECTED_HOST_RGB" ]; then
        echo "Host RGB Sync HEAD must be $EXPECTED_HOST_RGB (found ${actual_host_rgb:-missing})" >&2
        exit 1
    fi
fi
if [ -n "$DEVICE_INFO_CONFIG" ]; then
    if [ ! -d "$DEVICE_INFO_MODULE/.git" ]; then
        echo "Device Info module was not found at $DEVICE_INFO_MODULE" >&2
        exit 1
    fi
    actual_device_info="$(git -C "$DEVICE_INFO_MODULE" rev-parse HEAD)"
    if [ "$actual_device_info" != "$EXPECTED_DEVICE_INFO" ]; then
        echo "Device Info HEAD must be $EXPECTED_DEVICE_INFO (found $actual_device_info)" >&2
        exit 1
    fi
fi
if [ -n "$KSCAN_DIAG_CONFIG" ]; then
    if [ ! -d "$KSCAN_DIAG_MODULE/.git" ]; then
        echo "Kscan Diagnostics module was not found at $KSCAN_DIAG_MODULE" >&2
        exit 1
    fi
    actual_kscan_diag="$(git -C "$KSCAN_DIAG_MODULE" rev-parse HEAD)"
    if [ "$actual_kscan_diag" != "$EXPECTED_KSCAN_DIAG" ]; then
        echo "Kscan Diagnostics HEAD must be $EXPECTED_KSCAN_DIAG (found $actual_kscan_diag)" >&2
        exit 1
    fi
    if [ -n "$(git -C "$KSCAN_DIAG_MODULE" status --short)" ]; then
        echo "Kscan Diagnostics module must be clean" >&2
        exit 1
    fi
fi
if [ -n "$RUNTIME_MACRO_CONFIG" ]; then
    actual_runtime_macro="$(git -C "$RUNTIME_MACRO_MODULE" rev-parse HEAD 2>/dev/null || true)"
    if [ "$actual_runtime_macro" != "$EXPECTED_RUNTIME_MACRO" ]; then
        echo "Runtime Macro HEAD must be $EXPECTED_RUNTIME_MACRO (found ${actual_runtime_macro:-missing})" >&2
        exit 1
    fi
    # The rename fallback patch is a fix and must always be present. The
    # diagnostics patch is generated on top of it and shares no hunks, so both
    # are checked independently.
    if ! git -C "$RUNTIME_MACRO_MODULE" apply --reverse --check \
        "$RUNTIME_MACRO_PATCH" 2>/dev/null; then
        echo "Runtime Macro must have the rename-when-slots-full patch applied" >&2
        exit 1
    fi
    # Diagnostic-only logging patch: required by the diagnostic target, rejected
    # everywhere else so it can never reach a release artifact.
    if [ -n "$RUNTIME_MACRO_DIAG" ]; then
        if ! git -C "$RUNTIME_MACRO_MODULE" apply --reverse --check \
            "$RUNTIME_MACRO_DIAG_PATCH" 2>/dev/null; then
            echo "Runtime Macro must have the diagnostics patch applied for this target" >&2
            exit 1
        fi
    elif git -C "$RUNTIME_MACRO_MODULE" apply --reverse --check \
        "$RUNTIME_MACRO_DIAG_PATCH" 2>/dev/null; then
        echo "Runtime Macro still has the diagnostics patch applied - revert it first" >&2
        exit 1
    fi
fi
if [ -n "$RUNTIME_COMBO_CONFIG" ]; then
    for dependency in \
        "$RUNTIME_COMBO_MODULE:$EXPECTED_RUNTIME_COMBO:Runtime Combo" \
        "$CUSTOM_SETTINGS_MODULE:$EXPECTED_CUSTOM_SETTINGS:Custom settings"
    do
        dependency_path="${dependency%%:*}"
        dependency_rest="${dependency#*:}"
        dependency_revision="${dependency_rest%%:*}"
        dependency_name="${dependency_rest#*:}"
        if [ ! -d "$dependency_path/.git" ]; then
            echo "$dependency_name module was not found at $dependency_path" >&2
            exit 1
        fi
        actual_dependency="$(git -C "$dependency_path" rev-parse HEAD)"
        if [ "$actual_dependency" != "$dependency_revision" ]; then
            echo "$dependency_name HEAD must be $dependency_revision (found $actual_dependency)" >&2
            exit 1
        fi
    done
    if ! git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check "$CUSTOM_SETTINGS_PATCH"; then
        echo "Custom settings must have the DYA indexed-array growth patch applied" >&2
        exit 1
    fi
    if ! git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check \
        "$CUSTOM_SETTINGS_BEHAVIOR_LOAD_PATCH" 2>/dev/null; then
        echo "Custom settings must have the behavior load-order patch applied" >&2
        exit 1
    fi
    # The DIAG logging patch is diagnostic-only: required by the diagnostic
    # target, rejected everywhere else so it can never reach a release image.
    # It is generated on top of the unreadable-slot listing patch and shares
    # its hunks, so "diagnostics applied" already implies "listing patch
    # applied" - only the non-diagnostic path checks the listing patch itself.
    if [ -n "$RUNTIME_COMBO_DIAG" ]; then
        if ! git -C "$RUNTIME_COMBO_MODULE" apply --reverse --check \
            "$RUNTIME_COMBO_DIAG_PATCH" 2>/dev/null; then
            echo "Runtime Combo must have the diagnostics patch applied for this target" >&2
            exit 1
        fi
        if ! git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check \
            "$CUSTOM_SETTINGS_DIAG_PATCH" 2>/dev/null; then
            echo "Custom settings must have the diagnostics patch applied for this target" >&2
            exit 1
        fi
    else
        if git -C "$RUNTIME_COMBO_MODULE" apply --reverse --check \
            "$RUNTIME_COMBO_DIAG_PATCH" 2>/dev/null; then
            echo "Runtime Combo still has the diagnostics patch applied - revert it first" >&2
            exit 1
        fi
        if git -C "$CUSTOM_SETTINGS_MODULE" apply --reverse --check \
            "$CUSTOM_SETTINGS_DIAG_PATCH" 2>/dev/null; then
            echo "Custom settings still has the diagnostics patch applied - revert it first" >&2
            exit 1
        fi
        if ! git -C "$RUNTIME_COMBO_MODULE" apply --reverse --check \
            "$RUNTIME_COMBO_PATCH" 2>/dev/null; then
            echo "Runtime Combo must have the unreadable-slot listing patch applied" >&2
            exit 1
        fi
    fi
fi
if [ -n "$BLE_MANAGEMENT_CONFIG" ]; then
    if [ ! -d "$BLE_MANAGEMENT_MODULE/.git" ]; then
        echo "BLE management module was not found at $BLE_MANAGEMENT_MODULE" >&2
        exit 1
    fi
    actual_ble_management="$(git -C "$BLE_MANAGEMENT_MODULE" rev-parse HEAD)"
    if [ "$actual_ble_management" != "$EXPECTED_BLE_MANAGEMENT" ]; then
        echo "BLE management HEAD must be $EXPECTED_BLE_MANAGEMENT (found $actual_ble_management)" >&2
        exit 1
    fi
    EXTRA_MODULES="$EXTRA_MODULES;$BLE_MANAGEMENT_MODULE"
fi

if [ -n "$DEFAULT_LAYER_CONFIG" ]; then
    if [ ! -d "$DEFAULT_LAYER_MODULE/.git" ]; then
        echo "Default Layer module was not found at $DEFAULT_LAYER_MODULE" >&2
        exit 1
    fi
    actual_default_layer="$(git -C "$DEFAULT_LAYER_MODULE" rev-parse HEAD)"
    if [ "$actual_default_layer" != "$EXPECTED_DEFAULT_LAYER" ]; then
        echo "Default Layer HEAD must be $EXPECTED_DEFAULT_LAYER (found $actual_default_layer)" >&2
        exit 1
    fi
    for dependency in \
        "$CUSTOM_SETTINGS_MODULE:$EXPECTED_CUSTOM_SETTINGS:Custom settings" \
        "$OS_DETECTION_MODULE:$EXPECTED_OS_DETECTION:OS detection"
    do
        dependency_path="${dependency%%:*}"
        dependency_rest="${dependency#*:}"
        dependency_revision="${dependency_rest%%:*}"
        dependency_name="${dependency_rest#*:}"
        if [ ! -d "$dependency_path/.git" ]; then
            echo "$dependency_name module was not found at $dependency_path" >&2
            exit 1
        fi
        actual_dependency="$(git -C "$dependency_path" rev-parse HEAD)"
        if [ "$actual_dependency" != "$dependency_revision" ]; then
            echo "$dependency_name HEAD must be $dependency_revision (found $actual_dependency)" >&2
            exit 1
        fi
    done
    EXTRA_MODULES="$EXTRA_MODULES;$CUSTOM_SETTINGS_MODULE;$OS_DETECTION_MODULE;$DEFAULT_LAYER_MODULE"
fi

# An empty ZMK_CONFIG_DIR means "use the shield's own keymap" - the hardware
# test keymap that walks A-Z in physical order - instead of a config/ overlay
# keymap. Passing an empty -DZMK_CONFIG= would not do that, so omit the flag.
if [ -n "$ZMK_CONFIG_DIR" ]; then
    ZMK_CONFIG_ARG="-DZMK_CONFIG=$ZMK_CONFIG_DIR"
else
    ZMK_CONFIG_ARG=""
fi

if [ -n "$BUILD_SOURCE_DATE_EPOCH" ]; then
    export SOURCE_DATE_EPOCH="$BUILD_SOURCE_DATE_EPOCH"
fi

set --
if [ -n "$HOST_RGB_FIRMWARE_VERSION" ]; then
    set -- \
        "-DCONFIG_ZMK_HOST_RGB_FIRMWARE_VERSION=\"$HOST_RGB_FIRMWARE_VERSION\"" \
        "-DCONFIG_ZMK_HOST_RGB_DEVICE_NAME=\"$HOST_RGB_DEVICE_NAME\"" \
        "-DCONFIG_ZMK_HOST_RGB_DEVICE_VENDOR=\"$HOST_RGB_DEVICE_VENDOR\""
fi

(cd "$DYA_ZMK" && PATH="$TOOL_PATH:$PATH" "$WEST" build -p -s app \
    -d "build/$ARTIFACT" -b "xiao_ble//zmk" -- \
    -DSHIELD=on_the_15_x15 \
    -DSNIPPET="$BUILD_SNIPPETS" \
    $ZMK_CONFIG_ARG \
    -DZMK_EXTRA_MODULES="$EXTRA_MODULES" \
    -DEXTRA_DTC_OVERLAY_FILE="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay$TARGET_EXTRA_OVERLAY" \
    -DCONFIG_ZMK_STUDIO=y \
    -DCONFIG_ZMK_ONTHE15_STUDIO_RPC=y \
    -DCONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE="$RPC_RX_BUF_SIZE" \
    -DCONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE="$RPC_TX_BUF_SIZE" \
    -DCONFIG_ZMK_LOW_PRIORITY_THREAD_STACK_SIZE=2048 \
    -DCONFIG_ZMK_SLEEP=y \
    -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000 \
    -DCONFIG_ZMK_RGB_UNDERGLOW=n \
    -DCONFIG_ONTHE15_STATUS_INDICATOR=y \
    -DCONFIG_ZMK_MATRIX_LIGHTING=y \
    -DCONFIG_ZMK_MATRIX_LIGHTING_SETTINGS_PATH=\"$LIGHTING_SETTINGS_PATH\" \
    -DCONFIG_ONTHE15_LIGHTING_STARTUP=y \
    $LOCAL_EFFECTS_CONFIG \
    -DCONFIG_ONTHE15_BATTERY_NIMH_DIAGNOSTIC=y \
    -DCONFIG_ONTHE15_BATTERY_SETTINGS=y \
    $POWER_SETTINGS_CONFIG \
    -DCONFIG_ZMK_BATTERY_REPORT_INTERVAL=60 \
    $BLE_MANAGEMENT_CONFIG \
    $DEFAULT_LAYER_CONFIG \
    $DEVICE_INFO_CONFIG \
    $RUNTIME_COMBO_CONFIG \
    $RUNTIME_MACRO_CONFIG \
    $KSCAN_DIAG_CONFIG \
    $INDICATOR_TEST_CONFIG \
    $NANOPB_ERRMSG_CONFIG \
    "$@" \
    $HOST_RGB_CONFIG)

cp "$DYA_ZMK/build/$ARTIFACT/zephyr/zmk.uf2" "$MODULE/$ARTIFACT.uf2"
shasum -a 256 "$MODULE/$ARTIFACT.uf2"
