#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD="$DYA_ZMK/build/dya-device-info-x15-onthe15-zmk-1fc72aaf"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"
WEB="$MODULE/modules/onthe15-studio/web"
ARTIFACT="$MODULE/dya-device-info-x15-onthe15-zmk-1fc72aaf.uf2"
DEVICE_INFO_MODULE="${DEVICE_INFO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-device-info}"
EXPECTED_DEVICE_INFO="8cedd2dd9f04e19ea5a17b94914dd47a09d8db11"
READELF="/Volumes/Primary/GitHub/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin/arm-zephyr-eabi-readelf"

test "$(git -C "$DEVICE_INFO_MODULE" rev-parse HEAD)" = "$EXPECTED_DEVICE_INFO"
test -z "$(git -C "$DEVICE_INFO_MODULE" status --short)"
(cd "$WEB" && npm test -- --runInBand && npm run build)
"$MODULE/build_dya.sh" device-info-x15

grep -qx 'CONFIG_ZMK_DEVICE_INFO=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_DEVICE_INFO_STUDIO_RPC_REQUIRE_UNLOCK=y' "$CONFIG"
grep -qx 'CONFIG_HWINFO=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=64' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$CONFIG"
grep -aq 'zmk__device_info' "$ELF"
grep -aq '8cedd2d' "$ELF"
grep -aq '2026-07-18T06:01:24Z' "$ELF"
"$READELF" -n "$ELF" | grep -q 'Build ID:'
test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA Device Info x15 verification passed"
