#!/bin/sh
set -eu

MODULE="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="$MODULE/dependencies.lock"
DEPS_ROOT="${ZMK_DEPS_ROOT:-$MODULE/.build/deps}"
PYTHON="${PYTHON:-python3}"

mkdir -p "$DEPS_ROOT"

prepare_repo() {
    name="$1"
    repository="$2"
    revision="$3"
    patches="$4"
    destination="$DEPS_ROOT/$name"

    if [ -d "$destination/.git" ]; then
        current_url="$(git -C "$destination" remote get-url origin)"
        if [ "$current_url" != "$repository" ]; then
            echo "$name has unexpected origin: $current_url" >&2
            exit 1
        fi
    elif [ -e "$destination" ]; then
        echo "$destination exists but is not a Git checkout" >&2
        exit 1
    else
        git clone --filter=blob:none "$repository" "$destination"
    fi

    current_revision="$(git -C "$destination" rev-parse HEAD)"
    if [ "$current_revision" != "$revision" ] &&
       [ -n "$(git -C "$destination" status --short)" ]; then
        echo "$name has local changes at the wrong revision; refusing to overwrite them" >&2
        exit 1
    fi

    if ! git -C "$destination" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$destination" fetch origin "$revision"
    fi
    git -C "$destination" checkout --detach "$revision"

    # Generated cormoran checkouts are fetch-only. This deliberately invalid
    # push URL prevents an accidental write while keeping normal fetches.
    case "$repository" in
        https://github.com/cormoran/*)
            git -C "$destination" remote set-url --push origin no_push://cormoran-read-only
            ;;
    esac

    if [ -n "$patches" ]; then
        old_ifs="$IFS"
        IFS=','
        for patch_rel in $patches; do
            patch="$MODULE/$patch_rel"
            if git -C "$destination" apply --reverse --check "$patch" 2>/dev/null; then
                :
            elif git -C "$destination" apply --check "$patch"; then
                git -C "$destination" apply "$patch"
            else
                echo "$patch_rel is neither applicable nor already applied to $name" >&2
                exit 1
            fi
        done
        IFS="$old_ifs"
    fi
}

while IFS='|' read -r name repository revision patches; do
    case "$name" in
        ''|'#'*) continue ;;
    esac
    prepare_repo "$name" "$repository" "$revision" "$patches"
done < "$LOCK_FILE"

prepare_west_workspace() {
    workspace="$1"
    ready="$workspace/.reproducible-build-ready-v1"

    if [ ! -x "$workspace/.venv/bin/west" ]; then
        "$PYTHON" -m venv "$workspace/.venv"
        "$workspace/.venv/bin/pip" install west
    fi

    if [ ! -d "$workspace/.west" ]; then
        (cd "$workspace" && .venv/bin/west init -l app)
    fi

    if [ ! -f "$ready" ]; then
        (cd "$workspace" && \
            .venv/bin/west update && \
            .venv/bin/west zephyr-export && \
            .venv/bin/west packages pip --install)
        : > "$ready"
    fi
}

prepare_west_workspace "$DEPS_ROOT/zmk-stable"
prepare_west_workspace "$DEPS_ROOT/zmk-dya"

SDK_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$DEPS_ROOT/zephyr-sdk}"
if [ ! -f "$SDK_DIR/Zephyr-sdkConfig.cmake" ] &&
   [ ! -f "$SDK_DIR/cmake/Zephyr-sdkConfig.cmake" ]; then
    (cd "$DEPS_ROOT/zmk-dya" && \
        .venv/bin/west sdk install \
            --install-dir "$SDK_DIR" \
            --toolchains arm-zephyr-eabi)
fi

printf 'ZMK dependencies are ready at %s\n' "$DEPS_ROOT"
