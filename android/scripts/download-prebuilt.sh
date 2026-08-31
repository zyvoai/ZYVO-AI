#!/usr/bin/env bash
# Download the prebuilt Android runtime from guysoft/opencode-termux
#
# Extracts into $PREBUILT_DIR:
#   opencode.bin   - Bun cross-compiled for Android (bionic), proven to run
#                    opencode 1.17.9's module graph
#   *.so           - runtime shared libraries the phone needs in $PREFIX/lib

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=== Downloading prebuilt Android runtime ==="

if [ -f "$PREBUILT_DIR/opencode.bin" ]; then
    echo ">>> Already downloaded at $PREBUILT_DIR"
    exit 0
fi

mkdir -p "$PREBUILT_DIR"
ZIP_FILE="$PREBUILT_DIR/runtime.zip"

echo ">>> Downloading $PREBUILT_URL"
curl -fL --retry 3 --progress-bar "$PREBUILT_URL" -o "$ZIP_FILE"

echo ">>> Extracting..."
unzip -o "$ZIP_FILE" -d "$PREBUILT_DIR" >/dev/null
rm -f "$ZIP_FILE"

echo ">>> Contents of $PREBUILT_DIR:"
ls -lh "$PREBUILT_DIR"

[ -f "$PREBUILT_DIR/opencode.bin" ] || {
    echo "ERROR: opencode.bin not found in the prebuilt archive"
    exit 1
}
echo ""
echo "=== Prebuilt runtime ready ==="
