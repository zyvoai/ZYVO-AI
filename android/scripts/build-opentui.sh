#!/usr/bin/env bash
# Build libopentui.so for Android aarch64
#
# Usage: ./scripts/build-opentui.sh
#
# OpenCode's TUI renderer (@opentui/core) uses a native Zig library.
# The upstream build targets aarch64-linux (musl), which fails on Android
# because getauxval cannot be resolved. We build for aarch64-linux-android.
#
# Based on guysoft/opencode-termux (MIT). The opentui clone is pinned to the
# version OpenCode depends on (@opentui/core $OPENTUI_TAG).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

ZIG_BIN="${ZIG_BIN:-zig}"

echo "=== Building libopentui.so for Android aarch64 (${OPENTUI_TAG}) ==="

# Clone opentui if needed (pinned to the version opencode depends on)
if [ ! -d "$OPENTUI_SRC/.git" ]; then
    echo ">>> Cloning opentui at ${OPENTUI_TAG}..."
    git clone --depth 1 --branch "${OPENTUI_TAG}" https://github.com/anomalyco/opentui.git "$OPENTUI_SRC"
else
    echo ">>> opentui source exists at $OPENTUI_SRC"
fi

# Apply Android libc linking patch
# Without this patch, the .so won't have NEEDED: libc.so, and Android's
# dlopen() will fail because it can't resolve symbols like getauxval.
OPENTUI_PATCH="$REPO_ROOT/patches/opentui/android-libc-link.patch"
if [ -f "$OPENTUI_PATCH" ]; then
    echo ">>> Applying opentui Android patch..."
    cd "$OPENTUI_SRC"
    if ! git apply --check "$OPENTUI_PATCH" 2>/dev/null; then
        echo "    Patch already applied or does not apply cleanly, skipping"
    else
        git apply "$OPENTUI_PATCH"
        echo "    Patch applied successfully"
    fi
fi

OPENTUI_ZIG_DIR="$OPENTUI_SRC/packages/core/src/zig"

if [ ! -f "$OPENTUI_ZIG_DIR/build.zig" ]; then
    echo "ERROR: build.zig not found at $OPENTUI_ZIG_DIR"
    exit 1
fi

# Android (bionic) has dl and pthread inside libc — there are no separate
# libdl.so/libpthread.so for zig to find, and linking them fails with
# "unable to find dynamic system library". Guard the linux branch so they
# are only linked on non-android linux. We only ever build android here,
# so wrap the two linkSystemLibrary calls in the .linux switch branch.
if grep -q 'artifact.linkSystemLibrary("dl");' "$OPENTUI_ZIG_DIR/build.zig"; then
    echo ">>> Guarding dl/pthread link calls for Android (bionic has them in libc)..."
    sed -i \
        -e 's|artifact.linkSystemLibrary("dl");|{ if (!target.result.abi.isAndroid()) { artifact.linkSystemLibrary("dl"); artifact.linkSystemLibrary("pthread"); } }|' \
        -e '/^            artifact.linkSystemLibrary("pthread");$/d' \
        "$OPENTUI_ZIG_DIR/build.zig"
    echo "    Done."
fi

echo ">>> Building with Zig (target: aarch64-linux-android)..."

# Zig does not bundle bionic libc. Provide NDK sysroot paths via a libc.txt
# so the C/C++ parts (yoga, miniaudio shim) can compile against bionic.
if [ ! -d "$NDK_SYSROOT/usr/include" ]; then
    echo "ERROR: Android NDK sysroot not found at $NDK_SYSROOT"
    echo "       Set ANDROID_NDK_HOME (see env.sh)."
    exit 1
fi
LIBC_TXT="$WORK_DIR/android-libc.txt"
mkdir -p "$WORK_DIR"
# NDK clang finds arch headers (asm/, machine/) via the triple-specific
# include dir; zig libc.txt takes colon-separated include paths.
TRIPLE_INC="$NDK_SYSROOT/usr/include/${ANDROID_TRIPLE}"
cat > "$LIBC_TXT" << EOF
include_dir=$NDK_SYSROOT/usr/include:$TRIPLE_INC
sys_include_dir=$NDK_SYSROOT/usr/include:$TRIPLE_INC
crt_dir=$NDK_SYSROOT/usr/lib/${ANDROID_TRIPLE}/${ANDROID_API}
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF
echo "    libc paths: $LIBC_TXT"

cd "$OPENTUI_ZIG_DIR"

"$ZIG_BIN" build \
    -Dtarget=aarch64-linux-android \
    -Doptimize=ReleaseSafe \
    --libc "$LIBC_TXT" \
    --prefix . 2>&1

# The build.zig installs to dest_dir="../lib/{output_name}" relative to
# the --prefix dir.  With --prefix=. (= OPENTUI_ZIG_DIR), the .so ends
# up one directory above: packages/core/src/lib/aarch64-linux-android/
LIBOPENTUI="$OPENTUI_ZIG_DIR/../lib/aarch64-linux-android/libopentui.so"
if [ ! -f "$LIBOPENTUI" ]; then
    echo "ERROR: libopentui.so not found"
    echo "  Expected at: $LIBOPENTUI"
    echo "  Searching for any libopentui.so under opentui-src..."
    find "$OPENTUI_SRC" -name "libopentui.so" -type f 2>/dev/null || true
    exit 1
fi

echo ""
echo "=== libopentui.so build complete ==="
echo "Output: $LIBOPENTUI"
echo "Size: $(du -h "$LIBOPENTUI" | cut -f1)"
file "$LIBOPENTUI"

# Verify the .so has NEEDED: libc.so (required for Android dlopen)
if readelf -d "$LIBOPENTUI" 2>/dev/null | grep -q "NEEDED.*libc.so"; then
    echo "OK: libopentui.so has NEEDED: libc.so (required for Android)"
else
    echo "ERROR: libopentui.so is missing NEEDED: libc.so dependency"
    echo "       Android dlopen() will fail without this."
    echo "       Ensure ANDROID_NDK_HOME is set and the opentui patch was applied."
    readelf -d "$LIBOPENTUI" 2>/dev/null | grep NEEDED || echo "       (no NEEDED entries found)"
    exit 1
fi
