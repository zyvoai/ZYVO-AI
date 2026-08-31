#!/usr/bin/env bash
# Clone upstream repos and apply Android patches
#
# Usage: ./scripts/apply-patches.sh
#
# This script:
# 1. Clones oven-sh/bun at the pinned tag
# 2. Clones oven-sh/WebKit at the pinned commit
# 3. Applies patches from patches/
# 4. The Zig vendor patch is applied later by build-bun.sh after Bun's
#    build system downloads Zig
#
# Based on guysoft/opencode-termux (MIT). The bun patch was authored against
# Bun 1.2.13; since we now build Bun 1.3.11, `git apply` failures fall back
# to `patch -p1 --fuzz=3` to absorb upstream drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$SCRIPT_DIR/scripts"
source "$SCRIPT_DIR/env.sh"

apply_patch() {
    local repo_dir="$1"
    local patch_file="$2"
    local name="$3"
    cd "$repo_dir"
    git checkout -- . 2>/dev/null || true
    if git apply --check "$patch_file" 2>/dev/null; then
        git apply "$patch_file"
        echo "    $name patch applied cleanly (git apply)"
    elif patch --dry-run -p1 --fuzz=3 < "$patch_file" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 < "$patch_file"
        echo "    $name patch applied with fuzz (upstream drift absorbed)"
    else
        echo "ERROR: $name patch does not apply to this source version."
        echo "       The patch needs rebasing for the new upstream version."
        exit 1
    fi
}

echo "=== Applying Patches ==="

# --- Clone Bun ---
if [ ! -d "$BUN_SRC/.git" ]; then
    echo ">>> Cloning Bun v${BUN_VERSION}..."
    git clone --depth 1 --branch "${BUN_TAG}" https://github.com/oven-sh/bun.git "$BUN_SRC"
else
    echo ">>> Bun source already exists at $BUN_SRC"
fi

# Apply Bun patch
echo ">>> Applying Bun Android patches..."
apply_patch "$BUN_SRC" "$REPO_ROOT/patches/bun/android-support.patch" "Bun"

# --- Clone WebKit ---
if [ ! -d "$WEBKIT_SRC/.git" ]; then
    echo ">>> Cloning WebKit at commit ${WEBKIT_COMMIT}..."
    mkdir -p "$WEBKIT_SRC"
    cd "$WEBKIT_SRC"
    git init
    git remote add origin https://github.com/oven-sh/WebKit.git
    git fetch --depth=1 origin "${WEBKIT_COMMIT}"
    git checkout FETCH_HEAD
else
    echo ">>> WebKit source already exists at $WEBKIT_SRC"
fi

# Apply WebKit patch
echo ">>> Applying WebKit Android patches..."
apply_patch "$WEBKIT_SRC" "$REPO_ROOT/patches/webkit/android-support.patch" "WebKit"

echo ""
echo "=== Patches Applied ==="
echo "Bun source:    $BUN_SRC"
echo "WebKit source: $WEBKIT_SRC"
echo ""
echo "NOTE: The Zig vendor patch (patches/zig/posix-android-sigaction.patch)"
echo "      will be applied by build-bun.sh after Zig is downloaded by the"
echo "      Bun build system."
