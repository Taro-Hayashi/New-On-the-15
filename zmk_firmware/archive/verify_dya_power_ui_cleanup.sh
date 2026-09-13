#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD="$DYA_ZMK/build/dya-power-ui-cleanup-x15-onthe15-zmk-1fc72aaf"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"
WEB="$MODULE/modules/onthe15-studio/web"
ARTIFACT="$MODULE/dya-power-ui-cleanup-x15-onthe15-zmk-1fc72aaf.uf2"

(cd "$WEB" && npm test -- --runInBand && npm run build)
"$MODULE/build_dya.sh" power-ui-cleanup-x15

grep -qx 'CONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y' "$CONFIG"
grep -aq 'zmk__settings' "$ELF"
grep -aq 'onthe15__studio' "$ELF"
grep -aq 'onthe15/power_v1/state' "$ELF"
test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA On the 15 Power UI cleanup verification passed"
