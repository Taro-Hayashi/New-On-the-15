#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HEX_DIR="$ROOT/target/firmware-images"
mkdir -p "$HEX_DIR"

build_uf2() {
    output="$1"
    binary="$2"
    features="$3"
    hex="$HEX_DIR/$output.hex"

    cargo objcopy --release --bin "$binary" --no-default-features \
        --features "$features" -- -O ihex "$hex"
    cargo hex-to-uf2 --input-path "$hex" --output-path "$ROOT/$output.uf2" \
        --family nrf52840
}

build_test() {
    build_uf2 test-x7x8-onthe15 usb-check keymap-distribution
    build_uf2 test-x15-onthe15 usb-check keymap-distribution,test-x15
}

build_distribution() {
    build_uf2 distribution-x7x8-onthe15 on-the-15-v4-rmk keymap-distribution
    build_uf2 distribution-x15-onthe15 x15 keymap-distribution
    build_uf2 distribution-split-left-onthe15 split-central \
        keymap-distribution,split,left-central
    build_uf2 distribution-split-right-onthe15 split-peripheral keymap-distribution,split
}

build_personal() {
    build_uf2 personal-x15-onthe15 x15 keymap-personal
    build_uf2 personal-split-left-onthe15 split-central keymap-personal,split,left-central
    build_uf2 personal-split-right-onthe15 split-peripheral keymap-personal,split
}

build_battery_settings_test() {
    build_uf2 battery-settings-test-x15-onthe15 x15 \
        keymap-personal,battery-settings-test
}

build_settings_reset() {
    build_uf2 rmk-settings-reset-onthe15 settings-reset keymap-distribution
}

case "${1:-all}" in
    test) build_test ;;
    distribution) build_distribution ;;
    personal) build_personal ;;
    battery-settings-test) build_battery_settings_test ;;
    settings-reset) build_settings_reset ;;
    all)
        build_test
        build_distribution
        build_personal
        build_settings_reset
        ;;
    *)
        echo "usage: $0 [all|test|distribution|personal|battery-settings-test|settings-reset]" >&2
        exit 2
        ;;
esac
