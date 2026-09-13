#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
BUILD="$DYA_ZMK/build/dya-settings-rpc-x15-onthe15-zmk-1fc72aaf"
CONFIG="$BUILD/zephyr/.config"
ELF="$BUILD/zephyr/zmk.elf"
ARTIFACT="$MODULE/dya-settings-rpc-x15-onthe15-zmk-1fc72aaf.uf2"
WEB="$MODULE/modules/onthe15-studio/web"

"$MODULE/verify_dya_power_sync.sh"
"$MODULE/build_dya.sh" settings-rpc-x15

grep -qx 'CONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_POWER_SETTINGS_SYNC_API=y' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=64' "$CONFIG"
grep -qx 'CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160' "$CONFIG"
grep -aq 'zmk__settings' "$ELF"
grep -aq 'onthe15/power_v1/state' "$ELF"
grep -aq 'zmk_power_settings_save' "$ELF"
(cd "$WEB" && npm test -- --runInBand && npm run build)
test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA settings RPC x15 verification passed"
