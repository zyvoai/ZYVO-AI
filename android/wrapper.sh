#!/data/data/com.termux/files/usr/bin/sh
# zyvo/opencode — launcher wrapper for Android/Termux
#
# Based on guysoft/opencode-termux's wrapper (MIT), with zyvo additions:
#   - TMPDIR/OPENCODE_TMPDIR point at Termux's writable tmp ($PREFIX/tmp)
#   - ZYVO_SESSION_ROOT: browsable session folder on shared storage
#
# The real opencode binary is opencode.bin; this script LD_PRELOAD's libtagfix.so
# (a constructor that calls mallopt to turn off heap tagging) before exec'ing it.
# Without this, Bun/JSC's NaN-boxing clears the 0xB4 top-byte tag on heap
# pointers, causing bionic to SIGABRT on free(): "Pointer tag ... was truncated".

set -e

dir="$(cd "$(dirname "$0")" && pwd)"
export ANDROID_ROOT="${ANDROID_ROOT:-/system}"
export TERMUX_VERSION="${TERMUX_VERSION:-opencode-termux}"

# zyvo: Termux's own writable tmp. The Android rootfs /tmp is read-only, and
# Bun's os.tmpdir() may fall back to it — so pin it explicitly (both names).
ZYVO_TMP="${OPENCODE_TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
export OPENCODE_TMPDIR="$ZYVO_TMP"
export TMPDIR="$ZYVO_TMP"
export TEMP="$ZYVO_TMP"
export TMP="$ZYVO_TMP"
mkdir -p "$TMPDIR" 2>/dev/null || true

# zyvo: browsable sessions live on shared storage when it's writable
# (grant access once with: termux-setup-storage). Otherwise fall back silently.
ZYVO_ROOT="${ZYVO_SESSION_ROOT:-$HOME/storage/shared/ZYVO}"
if mkdir -p "$ZYVO_ROOT" 2>/dev/null && [ -w "$ZYVO_ROOT" ]; then
  export ZYVO_SESSION_ROOT="$ZYVO_ROOT"
else
  unset ZYVO_SESSION_ROOT
fi

export OPENCODE_DISABLE_TUI_AUDIO="${OPENCODE_DISABLE_TUI_AUDIO:-1}"

# Locate the native libraries we ship alongside the wrapper.
# In the flat zip layout they sit next to the wrapper; in the Termux package
# layout they are under ../lib.
NATIVE_LIB_DIR=""
for candidate in \
    "$dir/../lib" \
    "${PREFIX:-/data/data/com.termux/files/usr}/lib" \
    "$dir"
do
    if [ -f "$candidate/libtagfix.so" ]; then
        NATIVE_LIB_DIR="$candidate"
        break
    fi
done

if [ -n "$NATIVE_LIB_DIR" ]; then
    export LD_PRELOAD="${NATIVE_LIB_DIR}/libtagfix.so${LD_PRELOAD:+:$LD_PRELOAD}"
    # Bun's JIT-compiled modules need libc++_shared.so. Android's /system/lib64/
    # does not contain it, so point the linker at the directory where we ship it.
    export LD_LIBRARY_PATH="${NATIVE_LIB_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    # Bun's /$bunfs/root/ virtual paths are not intercepted on Android, so load
    # opentui's renderer library and bun-pty's PTY library from the real filesystem.
    export OPENTUI_LIB_PATH="${NATIVE_LIB_DIR}/libopentui.so"
    if [ -f "${NATIVE_LIB_DIR}/librust_pty_arm64.so" ]; then
        export BUN_PTY_LIB="${NATIVE_LIB_DIR}/librust_pty_arm64.so"
    fi
    # @parcel/watcher only bundles the host-arch native binding in our build;
    # disable it on Android/Termux to avoid a dlopen architecture mismatch.
    export OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER="${OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER:-true}"
    # If a real Bun binary is shipped next to opencode, use it for plugin installs.
    if [ -x "$NATIVE_LIB_DIR/bun" ]; then
        export OPENCODE_BUN_PATH="$NATIVE_LIB_DIR/bun"
    fi
else
    echo "zyvo: warning: native library directory not found, may crash on Android 11+" >&2
fi

# Locate opencode.bin. Prefer the package layout first so upgrades do not
# accidentally execute a stale flat-layout binary left in $PREFIX/bin.
for candidate in \
    "$dir/../libexec/zyvo/zyvo.bin" \
    "${PREFIX:-/data/data/com.termux/files/usr}/libexec/zyvo/zyvo.bin" \
    "$dir/opencode.bin"
do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "zyvo: error: could not find opencode.bin" >&2
exit 127
