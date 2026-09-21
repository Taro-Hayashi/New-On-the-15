#!/bin/sh
# Build the isolated x15 DYA Studio compatibility image.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DEPS_ROOT="${ZMK_DEPS_ROOT:-$MODULE/.build/deps}"
DYA_ZMK="${DYA_ZMK:-$DEPS_ROOT/zmk-dya}"
STABLE_ZMK="${STABLE_ZMK:-$DEPS_ROOT/zmk-stable}"
DYA_BUILD_ROOT="${DYA_BUILD_ROOT:-$DYA_ZMK/build}"
UF2_OUTPUT_ROOT="${UF2_OUTPUT_ROOT:-$MODULE}"
STUDIO_MODULE="$MODULE/modules/onthe15-studio"
SETTINGS_RESET_MODULE="$MODULE/modules/onthe15-settings-reset"
LIGHTING_MODULE="${LIGHTING_MODULE:-$DEPS_ROOT/zmk-matrix-lighting}"
case "${1:-power-x15}" in
    host-rgb-split-*) DEFAULT_HOST_RGB_MODULE="$DEPS_ROOT/zmk-host-rgb-sync-split" ;;
    *) DEFAULT_HOST_RGB_MODULE="$DEPS_ROOT/zmk-host-rgb-sync-x15" ;;
esac
HOST_RGB_MODULE="${HOST_RGB_MODULE:-$DEFAULT_HOST_RGB_MODULE}"
POWER_SETTINGS_MODULE="$MODULE/modules/zmk-feature-power-settings"
BLE_MANAGEMENT_MODULE="${BLE_MANAGEMENT_MODULE:-$DEPS_ROOT/zmk-module-ble-management}"
DEFAULT_LAYER_MODULE="${DEFAULT_LAYER_MODULE:-$DEPS_ROOT/zmk-feature-default-layer}"
CUSTOM_SETTINGS_MODULE="${CUSTOM_SETTINGS_MODULE:-$DEPS_ROOT/zmk-feature-custom-settings}"
OS_DETECTION_MODULE="${OS_DETECTION_MODULE:-$DEPS_ROOT/zmk-feature-os-detection}"
DEVICE_INFO_MODULE="${DEVICE_INFO_MODULE:-$DEPS_ROOT/zmk-feature-device-info}"
RUNTIME_COMBO_MODULE="${RUNTIME_COMBO_MODULE:-$DEPS_ROOT/zmk-feature-runtime-combo}"
RUNTIME_MACRO_MODULE="${RUNTIME_MACRO_MODULE:-$DEPS_ROOT/zmk-feature-runtime-macro}"
KSCAN_DIAG_MODULE="${KSCAN_DIAG_MODULE:-$DEPS_ROOT/zmk-feature-kscan-diagnostics}"
EXPECTED_DYA_ZMK="1fc72aaff7a42bd533c1f4c9b3f23c5317c745f4"
EXPECTED_BLE_MANAGEMENT="57738cc4fc6ba80e82a7ac57741a0339cb186cd4"
EXPECTED_DEFAULT_LAYER="ef1f5b61b14e4f78172d3b6590afb3a39412fafe"
EXPECTED_CUSTOM_SETTINGS="c6a7fef3a3be3d3ace5de9a4b0628c6418cd1f3f"
EXPECTED_OS_DETECTION="3052679f645b8fc1997275c2eaa6b86bdd55ca01"
EXPECTED_DEVICE_INFO="8cedd2dd9f04e19ea5a17b94914dd47a09d8db11"
EXPECTED_MATRIX_LIGHTING="7d2882629d07e1477b739c3a1c8bdde4fa21cf91"
EXPECTED_HOST_RGB="e2e6a4749f73b9ee95a35c6199a93b5347286f3a"
EXPECTED_HOST_RGB_SPLIT="34b324468ee386de4635e2cb7d1562c316dfe225"
EXPECTED_RUNTIME_COMBO="d9490e7b5d41c516221d131241009e81740efcee"
EXPECTED_RUNTIME_MACRO="38530962eb7061b60efcb98e84585cfb1f0cb6de"
EXPECTED_KSCAN_DIAG="1432f7fe0cfe903cd7d3c9931ae6bd6f2e1f328e"
POWER_PATCH="$MODULE/patches/dya-runtime-power-settings.patch"
MOUSE_METADATA_PATCH="$MODULE/patches/dya-mouse-behavior-metadata.patch"
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
elif [ -x "$STABLE_ZMK/.venv/bin/west" ]; then
    WEST="$STABLE_ZMK/.venv/bin/west"
    TOOL_PATH="$STABLE_ZMK/.venv/bin"
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

# Without it the mouse move and scroll behaviors carry no parameter metadata,
# so Studio lists them and then refuses every binding: the firmware accepts
# only a zero parameter from a behavior that declares nothing.
if ! git -C "$DYA_ZMK" apply --reverse --check "$MOUSE_METADATA_PATCH"; then
    echo "DYA ZMK must have the mouse behavior metadata patch applied" >&2
    exit 1
fi

DEFAULT_LAYER_CONFIG=""
ZMK_CONFIG_DIR="$MODULE/config/studio"
LIGHTING_SETTINGS_PATH="onthe15/underglow_v8"
INDICATOR_TEST_CONFIG=""
RPC_RX_BUF_SIZE=64
RPC_TX_BUF_SIZE=160
POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=y"
# Every target but the split peripheral answers Studio over the custom RPC
# subsystem. The peripheral has no Studio connection of its own, and the RPC
# protobuf headers are only generated where the transport is built, so the
# handlers have to be compiled out there rather than merely left unused.
ONTHE15_STUDIO_RPC_CONFIG="-DCONFIG_ZMK_ONTHE15_STUDIO_RPC=y"
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
# Empty means ZMK's default, which is locking on. Only the repair-only
# kscan-diagnostics-unlocked-* targets turn it off.
STUDIO_LOCKING_CONFIG=""
# Empty means the keymap that goes with ZMK_CONFIG_DIR, or the shield's own
# when that is empty. Only a target that picks a non-default physical layout
# has to name a keymap of its own: the keymap is as long as the layout.
KEYMAP_FILE_ARG=""
SPLIT_BATTERY_CONFIG=""
TARGET_EXTRA_OVERLAY=""
# Every target below the x15 block overrides these two. They travel together:
# the LED overlay is only valid for the shield whose strip it describes.
SHIELD_NAME="on_the_15_x15"
BASE_OVERLAYS="$MODULE/config/x15-leds.overlay;$MODULE/config/x15-battery-test.overlay"
BUILD_SOURCE_DATE_EPOCH=""
NANOPB_ERRMSG_CONFIG=""
# The advertised BLE name, and with it the USB product string. Every image gets
# its own, because a host lists two keyboards of the same name as one row: with
# an x15 and a split both called "On the 15", connecting to the second did
# nothing visible and both typed at once through what looked like a single
# entry. ZMK caps the name at 16 characters, which is what is left of the
# 31-byte advertising packet after the flags, appearance and service UUIDs.
KEYBOARD_NAME=""
HOST_RGB_FIRMWARE_VERSION=""
HOST_RGB_DEVICE_NAME=""
HOST_RGB_DEVICE_VENDOR=""
HOST_RGB_EXPECTED="$EXPECTED_HOST_RGB"
IS_HOST_RGB_SPLIT=false

case "${1:-power-x15}" in
    settings-reset)
        # Erases the settings partition, then reboots to the bootloader. It
        # shares none of the x15 configuration - different shield, no Studio,
        # no lighting - so it builds and exits here. The one module it does take
        # is the reboot into the bootloader, which ZMK's own settings_reset
        # shield has no equivalent of: without it the image erases and then sits
        # there with no USB drive to copy the next UF2 onto. It is its own
        # module rather than part of this repository's driver tree because
        # taking the repository would also take its board_root, and the shield
        # defconfigs there reference lighting symbols this image does not build.
        RESET_ARTIFACT="settings-reset-zmk"
        (cd "$DYA_ZMK" && PATH="$TOOL_PATH:$PATH" "$WEST" build -p -s app \
            -d "$DYA_BUILD_ROOT/$RESET_ARTIFACT" -b "xiao_ble//zmk" -- \
            -DZMK_EXTRA_MODULES="$SETTINGS_RESET_MODULE" \
            -DSHIELD=settings_reset -DSNIPPET=nrf52840-nosd)
        cp "$DYA_BUILD_ROOT/$RESET_ARTIFACT/zephyr/zmk.uf2" "$UF2_OUTPUT_ROOT/$RESET_ARTIFACT.uf2"
        shasum -a 256 "$UF2_OUTPUT_ROOT/$RESET_ARTIFACT.uf2"
        exit 0
        ;;
    kscan-diagnostics-x15|kscan-diagnostics-unlocked-x15)
        # Manufacturing / repair only. Never include this in the distributed
        # image or the personal daily image: the diagnostics RPC is opened
        # while the device is locked (see below), and the target carries no
        # lighting effects.
        #
        # Two images out of one target so they cannot drift apart:
        # kscan-diagnostics-x15 is the hardware test image, unchanged, and
        # kscan-diagnostics-unlocked-x15 is the repair image that also drops
        # Studio locking - see STUDIO_LOCKING_CONFIG at the end of this block.
        ARTIFACT="onthe15-test-x15-zmk"
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
        if [ "$1" = "kscan-diagnostics-unlocked-x15" ]; then
            # The shield's own test keymap carries no &studio_unlock, so this
            # image would stay locked for good: only the two unsecured
            # subsystems above answer, and the keymap and behavior RPCs - what
            # the web UI draws the board from - do not. Dropping locking is the
            # only way to reach them on a keyboard that cannot type the combo.
            # It is also why this stays a separate artifact from the test
            # image: an unlocked-by-build image must never be mistaken for one.
            ARTIFACT="onthe15-diag-x15-zmk"
            KEYBOARD_NAME="On the 15 x15 D"
            STUDIO_LOCKING_CONFIG="-DCONFIG_ZMK_STUDIO_LOCKING=n"
        fi
        ;;
    power-x15)
        ARTIFACT="onthe15-x15-zmk"
        KEYBOARD_NAME="On the 15 x15"
        HOST_RGB_CONFIG=""
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
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
    personal-default-layer-x15|signalrgb-x15)
        # Daily-use personal image: the same feature set as the distribution
        # power-x15 target, plus the per-OS default layers, and built from the
        # personal keymap instead of config/studio. Keeping it in step with
        # power-x15 also means Runtime Macro gets real-world use here before it
        # is promoted into the distributed image.
        if [ "$1" = "signalrgb-x15" ]; then
            # Isolated host-RGB trial derived from the current personal image.
            # Keep its keymap, Default Layer/OS detection, DYA features, settings
            # paths, and USB CDC; only add vendor HID and distinct identities.
            ARTIFACT="onthe15-signalrgb-trial-x15-zmk"
            KEYBOARD_NAME="On15 RGB Trial"
            HOST_RGB_CONFIG="-DCONFIG_ZMK_HOST_RGB_OPENRGB=y -DCONFIG_ZMK_HOST_RGB_TIMEOUT_MS=5000"
            HOST_RGB_EXTRA_MODULE=";$HOST_RGB_MODULE"
            HOST_RGB_FIRMWARE_VERSION="ZMK On the 15"
            HOST_RGB_DEVICE_NAME="On the 15"
            HOST_RGB_DEVICE_VENDOR="DYA Studio"
        else
            ARTIFACT="onthe15-private-x15-zmk"
            KEYBOARD_NAME="On the 15 x15 P"
            HOST_RGB_CONFIG=""
        fi
        BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
        DEFAULT_LAYER_CONFIG="-DCONFIG_ZMK_DEFAULT_LAYER=y -DCONFIG_ZMK_DEFAULT_LAYER_MIN_INDEX=1 -DCONFIG_ZMK_DEFAULT_LAYER_MAX_INDEX=2 -DCONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=y -DCONFIG_ZMK_DEFAULT_LAYER_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION_USB=y -DCONFIG_ZMK_OS_DETECTION_BLE=y -DCONFIG_ZMK_OS_DETECTION_STUDIO_RPC=y -DCONFIG_ZMK_CUSTOM_SETTINGS=y -DCONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y"
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
    power-x7|power-x8)
        # Standalone (non-split) x7 and x8 on the single-board on_the_15 shield,
        # with the same feature set as power-x15 so the split work has a known
        # good one-piece baseline to start from.
        #
        # The two models need two images even though they share the shield and
        # the keymap: the x7 strip is 34 SK6812 and the x8 strip is 38, the
        # chain snakes so the two orders diverge from the seventh LED, and the
        # lighting module asserts at build time that led-positions covers
        # exactly chain-length LEDs. One image cannot carry both tables.
        #
        # The scan matrix is the x8 superset either way - on x7 the eighth
        # column of each half scans open - so config/studio's eight-wide keymap
        # and the x8 physical layout serve both, and the x7 layout stays
        # selectable from Studio through the shield's position map.
        SHIELD_NAME="on_the_15"
        KEYBOARD_NAME="On the 15 x7/x8"
        if [ "$1" = "power-x7" ]; then
            ARTIFACT="onthe15-standalone-x7-zmk"
            BASE_OVERLAYS="$MODULE/config/x7-leds.overlay"
        else
            ARTIFACT="onthe15-standalone-x8-zmk"
            BASE_OVERLAYS="$MODULE/config/x8-leds.overlay"
        fi
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
        # See the power-x15 comment: the RX buffer takes the whole frame, so it
        # must stay clear of the 192-byte payload cap.
        RPC_RX_BUF_SIZE=256
        ;;
    power-split-left-x7|power-split-left-x8|power-split-right-x7|power-split-right-x8|\
    host-rgb-split-left-x7|host-rgb-split-right-x8|\
    personal-default-layer-split-left-x7|personal-default-layer-split-right-x8)
        # BLE split x7/x8, with the same feature set as the standalone power-x7
        # and power-x8 targets above.
        #
        # Four images cover all four combinations - x7/x8, x8/x7, x7/x7, x8/x8 -
        # because neither axis depends on the other half. The role splits the
        # build because only the central carries the USB Studio RPC transport,
        # and the model splits it for the same reason the standalone targets
        # split: 34 LEDs against 38, and led-positions must cover exactly
        # chain-length entries. The combination itself is not a build-time
        # choice - config/studio/on_the_15_split.overlay declares all four as
        # Studio-selectable physical layouts, and the right half sits at a fixed
        # x offset of 1150 in every one of them, so a board's own LED table is
        # the same whichever model it is paired with.
        # left-x7, right-x8 and so on, whichever prefix the target carries.
        SPLIT_SPEC="${1##*split-}"
        SPLIT_ROLE="${SPLIT_SPEC%-x?}"
        SPLIT_MODEL="${SPLIT_SPEC##*-}"
        if [ "${1#host-rgb-}" != "$1" ]; then
            IS_HOST_RGB_SPLIT=true
        fi
        SHIELD_NAME="on_the_15_split_$SPLIT_ROLE"
        if [ "$SPLIT_ROLE" = "right" ]; then
            # The peripheral also takes the col-offset overlay that shifts
            # every Studio transform into the right half of the matrix.
            BASE_OVERLAYS="$MODULE/config/studio/on_the_15_split_right.overlay;"
        else
            BASE_OVERLAYS=""
        fi
        BASE_OVERLAYS="$BASE_OVERLAYS$MODULE/config/split-$SPLIT_ROLE-$SPLIT_MODEL-leds.overlay"
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=y -DCONFIG_ZMK_MATRIX_LIGHTING_REACTIVE_RIPPLE=y"
        if [ "$SPLIT_ROLE" = "left" ]; then
            # The central is the half Studio talks to over USB, so it carries
            # the whole settings feature set, exactly as power-x7 and power-x8
            # do on the one-piece boards.
            BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
            BLE_MANAGEMENT_CONFIG="-DCONFIG_ZMK_BLE_MANAGEMENT=y -DCONFIG_ZMK_BLE_MANAGEMENT_STUDIO_RPC=y"
            POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y"
            POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
            DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y"
            DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
            RUNTIME_COMBO_CONFIG="-DCONFIG_ZMK_RUNTIME_COMBO=y -DCONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_COMBO_MAX_COMBOS=16 -DCONFIG_ZMK_RUNTIME_COMBO_MAX_POSITIONS_PER_COMBO=5"
            RUNTIME_COMBO_EXTRA_MODULE=";$CUSTOM_SETTINGS_MODULE;$RUNTIME_COMBO_MODULE"
            RUNTIME_MACRO_CONFIG="-DCONFIG_ZMK_RUNTIME_MACRO=y -DCONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y -DCONFIG_ZMK_RUNTIME_MACRO_COUNT=8 -DCONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 -DCONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 -DCONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 -DCONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 -DCONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192"
            RUNTIME_MACRO_EXTRA_MODULE=";$RUNTIME_MACRO_MODULE"
            # Each half measures its own cell, and only the central talks to
            # the host, so without this the host is told about one battery and
            # the right half can run flat unannounced. The central subscribes
            # to the peripheral's battery service and proxies it as a second
            # battery level, which is also what makes the chemistry setting
            # observable on the half that has no Studio connection.
            SPLIT_BATTERY_CONFIG="-DCONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y -DCONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y"
            # See the power-x15 comment: the RX buffer takes the whole frame,
            # so it must stay clear of the 192-byte payload cap.
            RPC_RX_BUF_SIZE=256
        else
            # The peripheral has no Studio transport, and without one the RPC
            # protobuf headers are never generated, so every custom subsystem
            # has to be compiled out rather than left enabled and idle. What it
            # keeps is what it actually runs by itself: its own half of the
            # lighting, the status indicator and the battery reporting. Studio
            # itself stays on so the layout the central selects reaches this
            # half and its led-positions are read against the right layout.
            BUILD_SNIPPETS="nrf52840-nosd"
            BLE_MANAGEMENT_CONFIG=""
            ONTHE15_STUDIO_RPC_CONFIG="-DCONFIG_ZMK_ONTHE15_STUDIO_RPC=n"
            # The power settings are the one add-on the peripheral needs for
            # itself: it sleeps on its own timers, so it has to be told what
            # the central was set to. It takes the module without the Studio
            # RPC - there is no Studio connection here - and the split sync
            # carries the central's snapshot over.
            POWER_SETTINGS_CONFIG="-DCONFIG_ONTHE15_POWER_SETTINGS=n -DCONFIG_ZMK_POWER_SETTINGS=y -DCONFIG_ZMK_POWER_SETTINGS_SETTINGS_PATH=\"onthe15/power_v1\" -DCONFIG_ZMK_POWER_SETTINGS_SYNC_API=y -DCONFIG_ZMK_POWER_SETTINGS_SPLIT_SYNC=y -DCONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=n"
            POWER_SETTINGS_EXTRA_MODULE=";$POWER_SETTINGS_MODULE"
        fi
        if [ "${1#personal-default-layer-}" != "$1" ] || [ "$IS_HOST_RGB_SPLIT" = true ]; then
            # Daily-use personal pair, fixed at x7 on the left and x8 on the
            # right: the distributed split feature set plus the per-OS default
            # layers, built from config/personal-default-layer instead of
            # config/studio. It stands to power-split-* exactly as
            # personal-default-layer-x15 stands to power-x15.
            ZMK_CONFIG_DIR="$MODULE/config/personal-default-layer"
            if [ "$SPLIT_ROLE" = "left" ]; then
                DEFAULT_LAYER_CONFIG="-DCONFIG_ZMK_DEFAULT_LAYER=y -DCONFIG_ZMK_DEFAULT_LAYER_MIN_INDEX=1 -DCONFIG_ZMK_DEFAULT_LAYER_MAX_INDEX=2 -DCONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=y -DCONFIG_ZMK_DEFAULT_LAYER_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION=y -DCONFIG_ZMK_OS_DETECTION_USB=y -DCONFIG_ZMK_OS_DETECTION_BLE=y -DCONFIG_ZMK_OS_DETECTION_STUDIO_RPC=y -DCONFIG_ZMK_CUSTOM_SETTINGS=y -DCONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=y"
            else
                # The peripheral never evaluates the keymap - the central owns
                # that - so the OS switching itself belongs on the central
                # alone. Both halves nonetheless build from the one keymap
                # file, and it references &df and behaviors/default_layer.dtsi,
                # so the module still has to be present here. Every RPC of it
                # stays off, for the same reason as the subsystems above.
                DEFAULT_LAYER_CONFIG="-DCONFIG_ZMK_DEFAULT_LAYER=y -DCONFIG_ZMK_DEFAULT_LAYER_MIN_INDEX=1 -DCONFIG_ZMK_DEFAULT_LAYER_MAX_INDEX=2 -DCONFIG_ZMK_DEFAULT_LAYER_STUDIO_RPC=n -DCONFIG_ZMK_DEFAULT_LAYER_OS_DETECTION=n -DCONFIG_ZMK_OS_DETECTION=n -DCONFIG_ZMK_CUSTOM_SETTINGS=y -DCONFIG_ZMK_CUSTOM_SETTINGS_STUDIO_RPC=n"
            fi
            if [ "$IS_HOST_RGB_SPLIT" = true ]; then
                ARTIFACT="onthe15-host-rgb-trial-split-$SPLIT_SPEC-zmk"
                KEYBOARD_NAME="On15 RGB $SPLIT_ROLE"
                HOST_RGB_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_SPLIT_HOST_FRAMES=y -DCONFIG_ZMK_MATRIX_LIGHTING_SPLIT_HOST_TIMEOUT_MS=5000 -DCONFIG_USB_DEVICE_PID=0x615F"
                TARGET_EXTRA_OVERLAY="$TARGET_EXTRA_OVERLAY;$MODULE/config/host-rgb-split-$SPLIT_SPEC.overlay"
                if [ "$SPLIT_ROLE" = "left" ]; then
                    HOST_RGB_CONFIG="$HOST_RGB_CONFIG -DCONFIG_ZMK_HOST_RGB_OPENRGB=y -DCONFIG_ZMK_HOST_RGB_TIMEOUT_MS=5000"
                    HOST_RGB_EXTRA_MODULE=";$HOST_RGB_MODULE"
                    HOST_RGB_EXPECTED="$EXPECTED_HOST_RGB_SPLIT"
                    HOST_RGB_FIRMWARE_VERSION="ZMK On the 15 split"
                    HOST_RGB_DEVICE_NAME="On the 15 split"
                    HOST_RGB_DEVICE_VENDOR="DYA Studio"
                fi
            else
                ARTIFACT="onthe15-private-$SPLIT_SPEC-zmk"
                KEYBOARD_NAME="On the 15 $SPLIT_MODEL P"
            fi
        else
            ARTIFACT="onthe15-split-$SPLIT_SPEC-zmk"
            if [ "$SPLIT_ROLE" = "left" ]; then
                KEYBOARD_NAME="On the 15 $SPLIT_MODEL L"
            else
                KEYBOARD_NAME="On the 15 $SPLIT_MODEL R"
            fi
        fi
        ;;
    kscan-diagnostics-x7x8|kscan-diagnostics-unlocked-x7|kscan-diagnostics-unlocked-x8)
        # Manufacturing / repair only, same caveat as kscan-diagnostics-x15:
        # the diagnostics RPC is opened while the device is locked, so this
        # never goes into a distributed or daily image.
        #
        # One image covers both models here, unlike the two power targets
        # above. It carries no coordinate-driven effects
        # (LOCAL_EFFECTS=n), so the only thing the x8 LED table costs on an x7
        # board is four trailing frame bytes clocked into a strip that ends
        # early - which the SK6812 chain simply discards.
        #
        # The checks it replaces are the old build_legacy.sh test-x7x8: the
        # shield's own A-Z-in-physical-order keymap, both status indicators
        # held on, and the SK6812 groups lit from boot. Kscan diagnostics and
        # device info are the current line's addition, and give the same
        # per-key visualization the x15 repair image has.
        ARTIFACT="onthe15-test-x7x8-zmk"
        SHIELD_NAME="on_the_15"
        BASE_OVERLAYS="$MODULE/config/x8-leds.overlay"
        BLE_MANAGEMENT_CONFIG=""
        HOST_RGB_CONFIG=""
        LOCAL_EFFECTS_CONFIG="-DCONFIG_ZMK_MATRIX_LIGHTING_LOCAL_EFFECTS=n"
        BUILD_SNIPPETS="nrf52840-nosd;studio-rpc-usb-uart"
        # 34 physical positions on the x8 layout, 30 on the x7; 64 covers both
        # with slack and matches the x15 target's allocation.
        KSCAN_DIAG_CONFIG="-DCONFIG_ZMK_KSCAN_DIAGNOSTICS=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_STUDIO_RPC_UNSECURED=y -DCONFIG_ZMK_KSCAN_DIAGNOSTICS_MAX_POSITIONS=64"
        KSCAN_DIAG_EXTRA_MODULE=";$KSCAN_DIAG_MODULE"
        DEVICE_INFO_CONFIG="-DCONFIG_ZMK_DEVICE_INFO=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y -DCONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=n"
        DEVICE_INFO_EXTRA_MODULE=";$DEVICE_INFO_MODULE"
        RPC_TX_BUF_SIZE=256
        ZMK_CONFIG_DIR=""
        TARGET_EXTRA_OVERLAY=";$MODULE/config/test-leds-on.overlay"
        INDICATOR_TEST_CONFIG="-DCONFIG_ONTHE15_STATUS_INDICATOR_TEST_ALWAYS_ON=y -DCONFIG_ONTHE15_KEYMAP_FORCE_STOCK=y"
        LIGHTING_SETTINGS_PATH="onthe15/test_lighting_v1"
        # The repair images, the x7/x8 counterpart of
        # kscan-diagnostics-unlocked-x15: Studio locking dropped so the keymap
        # and behavior RPCs answer on a board that cannot type the unlock
        # combo. Unlike the test image above these are split per model, one
        # image each: with the board in front of a repair session the exact LED
        # table costs nothing, and it keeps the x7 strip from being driven from
        # the x8 table.
        if [ "$1" = "kscan-diagnostics-unlocked-x7" ]; then
            ARTIFACT="onthe15-diag-x7-zmk"
            KEYBOARD_NAME="On the 15 x7 D"
            BASE_OVERLAYS="$MODULE/config/x7-leds.overlay"
            # The shield defaults to the x8 physical layout and the x8 test
            # keymap. Both have to move together: the keymap is as long as the
            # chosen layout, and on x7 the eighth column of each half is not
            # populated, so the x8 layout would draw four keys that can never
            # answer - which is exactly what the diagnostics UI showed.
            TARGET_EXTRA_OVERLAY="$TARGET_EXTRA_OVERLAY;$MODULE/config/x7-layout.overlay"
            KEYMAP_FILE_ARG="-DKEYMAP_FILE=$MODULE/boards/shields/on_the_15/on_the_15_x7.keymap"
            STUDIO_LOCKING_CONFIG="-DCONFIG_ZMK_STUDIO_LOCKING=n"
        elif [ "$1" = "kscan-diagnostics-unlocked-x8" ]; then
            ARTIFACT="onthe15-diag-x8-zmk"
            KEYBOARD_NAME="On the 15 x8 D"
            STUDIO_LOCKING_CONFIG="-DCONFIG_ZMK_STUDIO_LOCKING=n"
        fi
        ;;
    *)
        echo "usage: $0 [power-x15|signalrgb-x15|personal-default-layer-x15|kscan-diagnostics-x15|kscan-diagnostics-unlocked-x15|power-x7|power-x8|power-split-left-x7|power-split-left-x8|power-split-right-x7|power-split-right-x8|host-rgb-split-left-x7|host-rgb-split-right-x8|personal-default-layer-split-left-x7|personal-default-layer-split-right-x8|kscan-diagnostics-x7x8|kscan-diagnostics-unlocked-x7|kscan-diagnostics-unlocked-x8|settings-reset]" >&2
        echo "Completed measurement and test targets live in archive/build_dya_completed.sh" >&2
        exit 2
        ;;
esac

# The power settings keys need the module that answers them, so the node
# travels with it rather than with any one shield's overlay.
if [ -n "$POWER_SETTINGS_EXTRA_MODULE" ]; then
    TARGET_EXTRA_OVERLAY="$TARGET_EXTRA_OVERLAY;$MODULE/config/power-keys.overlay"
fi

# Same for the macro binding: without the module there is nothing to play.
if [ -n "$RUNTIME_MACRO_EXTRA_MODULE" ]; then
    TARGET_EXTRA_OVERLAY="$TARGET_EXTRA_OVERLAY;$MODULE/config/macro-keys.overlay"
fi

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
    if [ ! -d "$HOST_RGB_MODULE/.git" ]; then
        echo "Host RGB Sync module was not found at $HOST_RGB_MODULE" >&2
        exit 1
    fi
    actual_host_rgb="$(git -C "$HOST_RGB_MODULE" rev-parse HEAD)"
    if [ "$actual_host_rgb" != "$HOST_RGB_EXPECTED" ]; then
        echo "Host RGB Sync HEAD must be $HOST_RGB_EXPECTED (found $actual_host_rgb)" >&2
        exit 1
    fi
    if [ -n "$(git -C "$HOST_RGB_MODULE" status --short)" ]; then
        echo "Host RGB Sync module must be clean" >&2
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

# The name is the one argument with spaces in it, so it travels in the
# positional parameters rather than in a word-split variable like the rest.
# Nothing below reads the target argument any more.
if [ -n "$KEYBOARD_NAME" ]; then
    set -- "-DCONFIG_ZMK_KEYBOARD_NAME=\"$KEYBOARD_NAME\""
else
    set --
fi
if [ -n "$HOST_RGB_FIRMWARE_VERSION" ]; then
    set -- "$@" \
        "-DCONFIG_ZMK_HOST_RGB_FIRMWARE_VERSION=\"$HOST_RGB_FIRMWARE_VERSION\"" \
        "-DCONFIG_ZMK_HOST_RGB_DEVICE_NAME=\"$HOST_RGB_DEVICE_NAME\"" \
        "-DCONFIG_ZMK_HOST_RGB_DEVICE_VENDOR=\"$HOST_RGB_DEVICE_VENDOR\""
fi

# One-off arguments for a diagnostic build, which the targets themselves should
# not carry:
#   EXTRA_BUILD_ARGS="-DCONFIG_ZMK_USB_LOGGING=y" ./build_dya.sh power-split-right-x8
# Word splitting is deliberate - the variable holds several arguments.
if [ -n "${EXTRA_BUILD_ARGS:-}" ]; then
    set -- "$@" $EXTRA_BUILD_ARGS
fi

if [ -n "$BUILD_SOURCE_DATE_EPOCH" ]; then
    export SOURCE_DATE_EPOCH="$BUILD_SOURCE_DATE_EPOCH"
fi

# ZMK defaults the external power behavior on, and no board here switches an
# external rail. Left enabled it reaches the keymap editor as a key that cannot
# be assigned - it declares no parameter metadata, so the firmware refuses the
# binding - and it would drive nothing even if it could be assigned.
(cd "$DYA_ZMK" && PATH="$TOOL_PATH:$PATH" "$WEST" build -p -s app \
    -d "$DYA_BUILD_ROOT/$ARTIFACT" -b "xiao_ble//zmk" -- \
    -DSHIELD="$SHIELD_NAME" \
    -DSNIPPET="$BUILD_SNIPPETS" \
    $ZMK_CONFIG_ARG \
    $KEYMAP_FILE_ARG \
    -DZMK_EXTRA_MODULES="$EXTRA_MODULES" \
    -DEXTRA_DTC_OVERLAY_FILE="$BASE_OVERLAYS$TARGET_EXTRA_OVERLAY" \
    -DCONFIG_ZMK_STUDIO=y \
    $ONTHE15_STUDIO_RPC_CONFIG \
    -DCONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE="$RPC_RX_BUF_SIZE" \
    -DCONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE="$RPC_TX_BUF_SIZE" \
    -DCONFIG_ZMK_LOW_PRIORITY_THREAD_STACK_SIZE=2048 \
    -DCONFIG_ZMK_SLEEP=y \
    -DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000 \
    -DCONFIG_ZMK_RGB_UNDERGLOW=n \
    -DCONFIG_ZMK_EXT_POWER=n \
    -DCONFIG_ZMK_POINTING=y \
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
    $STUDIO_LOCKING_CONFIG \
    $SPLIT_BATTERY_CONFIG \
    $INDICATOR_TEST_CONFIG \
    $NANOPB_ERRMSG_CONFIG \
    "$@" \
    $HOST_RGB_CONFIG)

cp "$DYA_BUILD_ROOT/$ARTIFACT/zephyr/zmk.uf2" "$UF2_OUTPUT_ROOT/$ARTIFACT.uf2"
shasum -a 256 "$UF2_OUTPUT_ROOT/$ARTIFACT.uf2"
