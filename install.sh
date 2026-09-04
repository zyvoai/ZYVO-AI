#!/data/data/com.termux/files/usr/bin/bash
#
# Zyvo installer + updater for Termux (Android aarch64)
#
# Usage (in Termux):
#   curl -fsSL https://raw.githubusercontent.com/zyvoai/ZYVO-AI/main/install.sh | bash
#
# Always performs a full download and install of the latest release.
# Model-list/config updates ride along in the same pass.

set -euo pipefail

GITHUB_REPO="${1:-${ZYVO_REPO:-zyvoai/ZYVO-AI}}"

BINARY_NAME="zyvo"
ASSET_PATTERN="android-aarch64.tar.zst"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}==>${NC} $1"; }
die()   { echo -e "${RED}ERROR:${NC} $1" >&2; exit 1; }

# ---------------------------------------------------------------
# 1. Environment checks
# ---------------------------------------------------------------
[ -d "/data/data/com.termux" ] || die "This installer is for Termux only. Install Termux from F-Droid or GitHub: https://github.com/termux/termux-app/releases"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "Unsupported architecture: $(uname -m). Currently only aarch64 (64-bit ARM) phones are supported." ;;
esac

command -v curl >/dev/null 2>&1 || { info "Installing curl..."; pkg install -y curl; }
command -v unzip >/dev/null 2>&1 || { info "Installing unzip..."; pkg install -y unzip; }
command -v zstd >/dev/null 2>&1 || { info "Installing zstd..."; pkg install -y zstd; }

# ---------------------------------------------------------------
# 2. Dependencies
# ---------------------------------------------------------------
if ! command -v rg >/dev/null 2>&1; then
  info "Installing ripgrep..."
  pkg install -y ripgrep
else
  info "ripgrep already installed"
fi

if [ ! -d "$HOME/storage/shared" ] && command -v termux-setup-storage >/dev/null 2>&1; then
  info "Requesting storage permission — press ALLOW (sessions will appear in /storage/emulated/0/ZYVO)"
  termux-setup-storage || true
fi

# Latest wrapper is deployed on every run so wrapper fixes reach phones
# without a new binary release.
mkdir -p "$PREFIX/bin"
WRAPPER_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/android/wrapper.sh"
if curl -fsSL "$WRAPPER_URL" -o "$PREFIX/bin/${BINARY_NAME}.new" 2>/dev/null && [ -s "$PREFIX/bin/${BINARY_NAME}.new" ]; then
  chmod 755 "$PREFIX/bin/${BINARY_NAME}.new"
  mv "$PREFIX/bin/${BINARY_NAME}.new" "$PREFIX/bin/${BINARY_NAME}"
fi

# ---------------------------------------------------------------
# 3. Latest release
# ---------------------------------------------------------------
info "Checking the latest release in ${GITHUB_REPO}..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
TMP_JSON="$(mktemp)"
HTTP_CODE="$(curl -sSL -o "$TMP_JSON" -w '%{http_code}' "$API_URL" || echo 000)"
if [ "$HTTP_CODE" = "404" ]; then
  rm -f "$TMP_JSON"
  die "No release published yet in ${GITHUB_REPO}.
Run the 'Build Zyvo for Android/Termux (aarch64)' workflow first, then retry."
elif [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TMP_JSON"
  die "GitHub API returned HTTP $HTTP_CODE. Check your internet connection."
fi
RELEASE_JSON="$(cat "$TMP_JSON")"
rm -f "$TMP_JSON"

LATEST_VERSION="$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*android-v//; s/"//')"
[ -n "$LATEST_VERSION" ] || LATEST_VERSION="latest"
info "Latest version: v${LATEST_VERSION}"

# ---------------------------------------------------------------
# 4. Full download (resumable + integrity-checked)
# ---------------------------------------------------------------
ASSET_URL="$(echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET_PATTERN}\"" | head -1 | grep -o 'https[^"]*' || true)"
if [ -z "$ASSET_URL" ]; then
  warn "No tar.zst asset found - falling back to the zip package"
  ASSET_PATTERN="android-aarch64.zip"
  ASSET_URL="$(echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET_PATTERN}\"" | head -1 | grep -o 'https[^"]*' || true)"
fi
[ -n "$ASSET_URL" ] || die "No package asset found in the latest release of ${GITHUB_REPO}."

info "Downloading: $ASSET_URL"
TMP_DIR="$(mktemp -d)"
ZIP_FILE="${TMP_DIR}/${BINARY_NAME}.pkg"
download_pkg() {
  curl -fL -C - --retry 3 --retry-delay 2 --progress-bar "$ASSET_URL" -o "$ZIP_FILE"
}
download_pkg || download_pkg || die "Download failed twice. Check your connection and retry."
if [ "${ASSET_PATTERN##*.}" = "zip" ]; then
  check_pkg() { unzip -t "$1" >/dev/null 2>&1; }
  extract_pkg() { unzip -o "$1" -d "$2"; }
else
  check_pkg() { tar --zstd -tf "$1" >/dev/null 2>&1; }
  extract_pkg() { tar --zstd -xf "$1" -C "$2"; }
fi
if ! check_pkg "$ZIP_FILE"; then
  warn "Archive looks corrupted — re-downloading once..."
  rm -f "$ZIP_FILE"
  curl -fL --progress-bar "$ASSET_URL" -o "$ZIP_FILE" || die "Download failed again."
  check_pkg "$ZIP_FILE" || die "Archive is still corrupted. Please retry later."
fi

# ---------------------------------------------------------------
# 5. Install (archive = Termux prefix layout)
# ---------------------------------------------------------------
info "Installing..."
extract_pkg "$ZIP_FILE" "$TMP_DIR"
USR_DIR="${TMP_DIR}/data/data/com.termux/files/usr"
[ -f "${USR_DIR}/bin/${BINARY_NAME}" ] || die "Downloaded archive does not contain ${BINARY_NAME}."

mkdir -p "$PREFIX/bin" "$PREFIX/libexec/zyvo" "$PREFIX/lib"
cp "${USR_DIR}/bin/${BINARY_NAME}" "$PREFIX/bin/${BINARY_NAME}"
chmod 755 "$PREFIX/bin/${BINARY_NAME}"
if [ -f "${USR_DIR}/libexec/zyvo/zyvo.bin" ]; then
  cp "${USR_DIR}/libexec/zyvo/zyvo.bin" "$PREFIX/libexec/zyvo/zyvo.bin"
  chmod 755 "$PREFIX/libexec/zyvo/zyvo.bin"
else
  die "Downloaded archive does not contain the zyvo binary."
fi
for so in "${USR_DIR}"/lib/*.so; do
  [ -f "$so" ] && cp "$so" "$PREFIX/lib/"
done
rm -f "$PREFIX/bin/opencode" 2>/dev/null || true
rm -rf "$PREFIX/libexec/opencode" 2>/dev/null || true
rm -rf "$TMP_DIR"

# ---------------------------------------------------------------
# 6. Config (model list) — refreshed on every run, backup kept
# ---------------------------------------------------------------
CONFIG_DIR="$HOME/.config/zyvo"
CONFIG_FILE="$CONFIG_DIR/zyvo.json"
CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/config/zyvo.json"
mkdir -p "$CONFIG_DIR"
if curl -fsSL "$CONFIG_URL" -o "$CONFIG_FILE.tmp" 2>/dev/null && [ -s "$CONFIG_FILE.tmp" ]; then
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
  fi
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  info "Model list config refreshed (backup: zyvo.json.bak)"
else
  rm -f "$CONFIG_FILE.tmp"
  warn "Could not refresh config — keeping what you have"
fi

# ---------------------------------------------------------------
# 7. Smoke test
# ---------------------------------------------------------------
info "Verifying installation..."
if "$PREFIX/bin/${BINARY_NAME}" --version; then
  echo ""
  echo -e "${GREEN}✔ ${BINARY_NAME} v${LATEST_VERSION} installed successfully!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Set an AI provider key, e.g.:"
  echo "       export ANTHROPIC_API_KEY=\"sk-ant-...\""
  echo "     (add it to ~/.bashrc to persist)"
  echo "  2. Start using it:"
  echo "       ${BINARY_NAME}"
  echo ""
  echo "Keep the screen on during long sessions:"
  echo "       termux-wake-lock"
else
  die "Installed binary did not run. Please open an issue with the output of:
  ${BINARY_NAME} --version"
fi
