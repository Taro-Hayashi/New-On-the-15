#!/bin/sh
# Verify the fixed Phase 8 Runtime Macro x15 test target.
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
DYA_ZMK="${DYA_ZMK:-/Volumes/Primary/GitHub/zmk-dya}"
MACRO_MODULE="${RUNTIME_MACRO_MODULE:-/Volumes/Primary/GitHub/zmk-feature-runtime-macro}"
EXPECTED_MACRO="38530962eb7061b60efcb98e84585cfb1f0cb6de"
ARTIFACT="$MODULE/dya-runtime-macro-x15-onthe15-zmk-1fc72aaf.uf2"
BUILD_DIR="$DYA_ZMK/build/dya-runtime-macro-x15-onthe15-zmk-1fc72aaf"
CONFIG="$BUILD_DIR/zephyr/.config"
ELF="$BUILD_DIR/zephyr/zmk.elf"

MACRO_PATCH="$MODULE/patches/dya-runtime-macro-rename-when-slots-full.patch"
MACRO_DIAG_PATCH="$MODULE/patches/dya-runtime-macro-diagnostics.patch"

test "$(git -C "$MACRO_MODULE" rev-parse HEAD)" = "$EXPECTED_MACRO"
# The module carries the rename fix, which is not upstream yet, so its tree
# cannot be clean. Pin the expected working-tree state instead: the fix patch
# reverse-applies (i.e. is present) and the diagnostics patch does not (i.e.
# diagnostic logging cannot reach a verified artifact).
git -C "$MACRO_MODULE" apply --reverse --check "$MACRO_PATCH"
! git -C "$MACRO_MODULE" apply --reverse --check "$MACRO_DIAG_PATCH" 2>/dev/null

(cd "$MACRO_MODULE/web" && npm run generate && npm test -- --runInBand && npm run build)
"$MODULE/build_dya.sh" runtime-macro-x15

for expected in \
    CONFIG_ZMK_RUNTIME_MACRO=y \
    CONFIG_ZMK_RUNTIME_MACRO_STUDIO_RPC=y \
    CONFIG_ZMK_RUNTIME_MACRO_COUNT=8 \
    CONFIG_ZMK_RUNTIME_MACRO_POOL_BYTES=2048 \
    CONFIG_ZMK_RUNTIME_MACRO_MAX_BYTES=192 \
    CONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE=128 \
    CONFIG_ZMK_CUSTOM_SETTINGS_LARGE_VALUE_MAX_SIZE=192 \
    CONFIG_ZMK_STUDIO_RPC_RX_BUF_SIZE=256 \
    CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE=160 \
    CONFIG_ZMK_STUDIO_RPC_CUSTOM_SUBSYSTEM_REQUEST_PAYLOAD_MAX_BYTES=192 \
    CONFIG_ZMK_STUDIO_RPC_THREAD_STACK_SIZE=4096 \
    CONFIG_ZMK_LOW_PRIORITY_THREAD_STACK_SIZE=2048 \
    CONFIG_MAIN_STACK_SIZE=2048 \
    CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=2048 \
    CONFIG_ZMK_RUNTIME_COMBO=y \
    CONFIG_ZMK_RUNTIME_COMBO_STUDIO_RPC=y
do
    grep -qx "$expected" "$CONFIG"
done

grep -aq 'cormoran__runtime_macro' "$ELF"
grep -aq 'cormoran__runtime_combo' "$ELF"
grep -q 'runtime_macro' "$BUILD_DIR/zephyr/zephyr.dts"
test -s "$ARTIFACT"
shasum -a 256 "$ARTIFACT"
wc -c "$ARTIFACT"

echo "DYA Runtime Macro x15 verification passed"
