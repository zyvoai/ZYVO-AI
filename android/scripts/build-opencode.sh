#!/usr/bin/env bash
# Build OpenCode standalone binary for Android aarch64
#
# Usage: ./scripts/build-opencode.sh
#
# This script:
# 1. Clones OpenCode if needed (pinned to v$OPENCODE_VERSION)
# 2. Installs dependencies (host Bun) incl. all platform variants of the
#    native packages, so bundling picks up the right files
# 3. Swaps x86_64 libopentui.so with the ARM64 Android version
# 4. Runs the TypeScript build script to create the standalone binary
#
# Requires:
# - Android Bun binary built (scripts/build-bun.sh)
# - libopentui.so built (scripts/build-opentui.sh)
# - Host Bun installed (for bundling)
#
# Based on guysoft/opencode-termux (MIT).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

HOST_BUN="${HOST_BUN:-bun}"

echo "=== Building OpenCode v${OPENCODE_VERSION} for Android aarch64 ==="

# Clone OpenCode if needed
if [ ! -d "$OPENCODE_SRC/.git" ]; then
    echo ">>> Cloning OpenCode..."
    git clone --depth 1 --branch "v${OPENCODE_VERSION}" https://github.com/anomalyco/opencode.git "$OPENCODE_SRC"
else
    echo ">>> OpenCode source exists at $OPENCODE_SRC"
fi

OPENCODE_PKG="$OPENCODE_SRC/packages/opencode"

# Install OpenCode dependencies
echo ">>> Installing OpenCode dependencies..."
cd "$OPENCODE_SRC"
if ! "$HOST_BUN" install; then
    echo ">>> bun install failed (lockfile may be from a newer Bun)."
    echo ">>> Removing bun.lock and resolving fresh..."
    mv bun.lock bun.lock.android-build.bak 2>/dev/null || true
    if ! "$HOST_BUN" install; then
        echo ">>> Still failing — removing packageManager pin and retrying..."
        sed -i '/"packageManager"/d' package.json
        "$HOST_BUN" install
    fi
fi

# OpenCode's own build script installs all platform variants of the native
# packages (mirroring packages/opencode/script/build.ts) so the bundler can
# embed platform-specific assets regardless of the build host.
echo ">>> Installing all platform variants of native packages..."
cd "$OPENCODE_PKG"
"$HOST_BUN" install --os='*' --cpu='*' @opentui/core@0.4.5
"$HOST_BUN" install --os='*' --cpu='*' @parcel/watcher@2.5.1
"$HOST_BUN" install --os='*' --cpu='*' @ff-labs/fff-bun@0.9.4

# Find the Android bun binary (prebuilt runtime from guysoft release,
# downloaded into $PREBUILT_DIR by the workflow / download-prebuilt.sh)
ANDROID_BUN="$PREBUILT_DIR/opencode.bin"
if [ ! -f "$ANDROID_BUN" ]; then
    echo "ERROR: Android bun binary not found at $ANDROID_BUN"
    echo "       Download the prebuilt runtime first (PREBUILT_URL)."
    exit 1
fi

# Find ARM64 libopentui.so (prebuilt, matching @opentui/core version)
# On Android the .so is loaded from the real filesystem via OPENTUI_LIB_PATH
# (set by the wrapper script), not from the bunfs virtual path.
ARM64_LIBOPENTUI="$PREBUILT_DIR/libopentui.so"
if [ ! -f "$ARM64_LIBOPENTUI" ]; then
    echo "ERROR: ARM64 libopentui.so not found at $ARM64_LIBOPENTUI"
    echo "       Run scripts/download-prebuilt.sh first."
    exit 1
fi

# Find x86_64 libopentui.so in node_modules and swap it
# On Linux x64 build hosts, Bun embeds @opentui/core-linux-x64's .so;
# at runtime the loader resolves the same embedded path, so swapping the
# file contents is enough to ship the Android library inside the binary.
OPENTUI_NODE_MODULE=""
for candidate in \
    "$OPENCODE_SRC/node_modules/@opentui/core-linux-x64/libopentui.so" \
    "$OPENCODE_PKG/node_modules/@opentui/core-linux-x64/libopentui.so" \
    "$OPENCODE_SRC/node_modules/.bun/@opentui+core-linux-x64@*/node_modules/@opentui/core-linux-x64/libopentui.so"
do
    # Handle glob
    for f in $candidate; do
        if [ -f "$f" ]; then
            OPENTUI_NODE_MODULE="$f"
            break 2
        fi
    done
done

BACKUP_FILE=""
if [ -n "$OPENTUI_NODE_MODULE" ]; then
    echo ">>> Swapping x86_64 libopentui.so with ARM64 version..."
    BACKUP_FILE="${OPENTUI_NODE_MODULE}.x64.bak"
    cp "$OPENTUI_NODE_MODULE" "$BACKUP_FILE"
    cp "$ARM64_LIBOPENTUI" "$OPENTUI_NODE_MODULE"
    echo "    Backed up to $BACKUP_FILE"
else
    echo "WARNING: Could not find x86_64 libopentui.so in node_modules"
    echo "         The build may embed the wrong architecture"
fi

# Create dist directory
mkdir -p "$DIST_DIR"

# Ship the prebuilt runtime pieces: wrapper script (Android env fixes), the
# original prebuilt binary (reference/backup), and the runtime .so files
# (libopentui, libtagfix heap-tagging fix, libc++_shared for the JIT).
for f in "$PREBUILT_DIR"/*.so; do
    [ -f "$f" ] && cp "$f" "$DIST_DIR/"
done
[ -f "$PREBUILT_DIR/opencode" ] && cp "$PREBUILT_DIR/opencode" "$DIST_DIR/opencode-wrapper"
[ -f "$PREBUILT_DIR/opencode.bin" ] && cp "$PREBUILT_DIR/opencode.bin" "$DIST_DIR/opencode-prebuilt.bin"

# Run the TypeScript build script
# Copy it into the OpenCode package tree so Bun can resolve @opentui/solid/bun-plugin
# from node_modules (Bun resolves bare imports relative to the script file's location)
echo ">>> Building OpenCode standalone binary..."
BUILD_SCRIPT="$REPO_ROOT/scripts/build-opencode-android.ts"
BUILD_SCRIPT_LOCAL="$OPENCODE_PKG/build-opencode-android.ts"
cp "$BUILD_SCRIPT" "$BUILD_SCRIPT_LOCAL"
cd "$OPENCODE_PKG"

OPENCODE_VERSION="$OPENCODE_VERSION" \
    ANDROID_BUN="$ANDROID_BUN" \
    OUTPUT_DIR="$DIST_DIR" \
    OPENCODE_DIR="$OPENCODE_PKG" \
    "$HOST_BUN" run "$BUILD_SCRIPT_LOCAL"

# Clean up copied script
rm -f "$BUILD_SCRIPT_LOCAL"

# Restore original libopentui.so
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    echo ">>> Restoring original x86_64 libopentui.so..."
    mv "$BACKUP_FILE" "$OPENTUI_NODE_MODULE"
fi

# Verify output
OPENCODE_BINARY="$DIST_DIR/opencode"
if [ ! -f "$OPENCODE_BINARY" ]; then
    echo "ERROR: OpenCode binary not found at $OPENCODE_BINARY"
    exit 1
fi

echo ""
echo "=== OpenCode build complete ==="
echo "Binary: $OPENCODE_BINARY"
echo "Size: $(du -h "$OPENCODE_BINARY" | cut -f1)"
file "$OPENCODE_BINARY"
