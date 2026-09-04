#!/usr/bin/env bash
# Create distribution packages for OpenCode Android
#
# Usage: ./scripts/make-packages.sh
#
# Creates three package formats, all containing:
#   opencode       -> $PREFIX/bin/         (standalone binary, our build)
#   opencode.bin   -> $PREFIX/libexec/opencode/  (prebuilt android bun runtime)
#   *.so           -> $PREFIX/lib/         (runtime shared libraries)
#
# 1. ZIP: opencode-${VERSION}-android-aarch64.zip
# 2. Pacman: opencode-${VERSION}-1-aarch64.pkg.tar.xz (Termux pacman format)
# 3. Deb: opencode_${VERSION}_aarch64.deb

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OPENCODE_BINARY="$DIST_DIR/zyvo"
PKG_DIR="$WORK_DIR/packages"

if [ ! -f "$OPENCODE_BINARY" ]; then
    echo "ERROR: Zyvo binary not found at $OPENCODE_BINARY"
    echo "       Run scripts/build-opencode.sh first."
    exit 1
fi

echo "=== Creating packages for OpenCode v${OPENCODE_VERSION} ==="

BINARY_SIZE=$(stat -c%s "$OPENCODE_BINARY")
BUILD_DATE=$(date +%s)

# Clean up
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

# Termux prefix layout inside the package
PREFIX_DIR="data/data/com.termux/files/usr"

# ==========================================
# 1. ZIP package (used by install.sh)
# ==========================================
# Layout (matches the wrapper script's expectations):
#   bin/opencode                    <- wrapper sh script (Android env fixes)
#   libexec/zyvo/zyvo.bin   <- OUR standalone binary (this build)
#   lib/libopentui.so, libtagfix.so, libc++_shared.so
echo ">>> Creating ZIP package..."
ZIP_NAME="zyvo-${OPENCODE_VERSION}-android-aarch64.zip"
ZIP_STAGING="$PKG_DIR/zip-staging"
mkdir -p "$ZIP_STAGING/$PREFIX_DIR/bin" \
         "$ZIP_STAGING/$PREFIX_DIR/libexec/zyvo" \
         "$ZIP_STAGING/$PREFIX_DIR/lib"

cp "$DIST_DIR/opencode-wrapper" "$ZIP_STAGING/$PREFIX_DIR/bin/zyvo"
cp "$DIST_DIR/zyvo"         "$ZIP_STAGING/$PREFIX_DIR/libexec/zyvo/zyvo.bin"
for so in "$DIST_DIR"/*.so; do
    [ -f "$so" ] && cp "$so" "$ZIP_STAGING/$PREFIX_DIR/lib/"
done

cd "$ZIP_STAGING"
chmod 755 "$PREFIX_DIR/bin/zyvo" "$PREFIX_DIR/libexec/zyvo/zyvo.bin" 2>/dev/null || true
zip -9 -r "$PKG_DIR/$ZIP_NAME" data
echo "    Created $ZIP_NAME"

# ==========================================
# 1b. ZSTD package (smaller + faster to unpack on the phone)
# ==========================================
echo ">>> Creating ZSTD package..."
ZSTD_NAME="zyvo-${OPENCODE_VERSION}-android-aarch64.tar.zst"
cd "$ZIP_STAGING"
tar --zstd -cf "$PKG_DIR/$ZSTD_NAME" data
echo "    Created $ZSTD_NAME"

# ==========================================
# 2. Pacman package (Termux)
# ==========================================
echo ">>> Creating pacman package..."
# ==========================================
echo ">>> Creating pacman package..."
PACMAN_STAGING="$PKG_DIR/pacman-staging"
mkdir -p "$PACMAN_STAGING"
cp -r "$ZIP_STAGING/data" "$PACMAN_STAGING/"

cat > "$PACMAN_STAGING/.PKGINFO" << EOF
pkgname = zyvo
pkgver = ${OPENCODE_VERSION}-1
pkgdesc = AI-powered coding assistant for the terminal
url = https://github.com/zyvoai/zyvo
builddate = ${BUILD_DATE}
packager = zyvo
size = ${BINARY_SIZE}
arch = aarch64
license = MIT
depend = ripgrep
EOF

PACMAN_NAME="zyvo-${OPENCODE_VERSION}-1-aarch64.pkg.tar.xz"
cd "$PACMAN_STAGING"
tar cf - .PKGINFO data | xz -9 > "$PKG_DIR/$PACMAN_NAME"
echo "    Created $PACMAN_NAME"

# ==========================================
# 3. Deb package (old Termux format)
# ==========================================
echo ">>> Creating deb package..."
DEB_STAGING="$PKG_DIR/deb-staging"
mkdir -p "$DEB_STAGING/DEBIAN"
cp -r "$ZIP_STAGING/data" "$DEB_STAGING/"

INSTALLED_SIZE=$((BINARY_SIZE / 1024))
cat > "$DEB_STAGING/DEBIAN/control" << EOF
Package: zyvo
Version: ${OPENCODE_VERSION}
Architecture: aarch64
Maintainer: zyvo
Installed-Size: ${INSTALLED_SIZE}
Depends: ripgrep
Section: utils
Priority: optional
Homepage: https://github.com/zyvoai/zyvo
Description: AI-powered coding assistant for the terminal
 OpenCode is an AI-powered coding assistant that runs in the terminal.
 This package provides a standalone binary compiled for Android/Termux.
EOF

DEB_NAME="zyvo_${OPENCODE_VERSION}_aarch64.deb"
cd "$DEB_STAGING/data"
tar czf "$DEB_STAGING/data.tar.gz" data
cd "$DEB_STAGING/DEBIAN"
tar czf "$DEB_STAGING/control.tar.gz" control
echo "2.0" > "$DEB_STAGING/debian-binary"
cd "$DEB_STAGING"
ar rc "$PKG_DIR/$DEB_NAME" debian-binary control.tar.gz data.tar.gz
echo "    Created $DEB_NAME"

# ==========================================
# Build id (lets the installer detect new builds even when the
# opencode version string is unchanged)
# ==========================================
BUILD_ID="ci-$(date +%Y%m%d%H%M%S)-${OPENCODE_VERSION}"
echo "$BUILD_ID" > "$PKG_DIR/build-id.txt"
echo "    build id: $BUILD_ID"

# ==========================================
# Summary
# ==========================================
echo ""
echo "=== Packages created ==="
echo ""
ls -lh "$PKG_DIR"/*.{zip,xz,deb} 2>/dev/null
echo ""
echo "Install on Termux:"
echo "  pacman -U $PACMAN_NAME"
echo "  dpkg -i $DEB_NAME"
echo "  # or via install.sh with the zip"
