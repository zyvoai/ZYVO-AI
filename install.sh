#!/data/data/com.termux/files/usr/bin/bash
#
# Zyvo / OpenCode one-click installer for Termux (Android aarch64)
#
# Usage (in Termux):
#   curl -fsSL https://raw.githubusercontent.com/zyvoai/zyvo/main/install.sh | bash
#   # or: bash install.sh zyvoai/zyvo
#
# Installs the native Android build released by this repo's GitHub Actions
# workflow. Direct binary — no proot, no glibc layer.

set -euo pipefail

# ---------------------------------------------------------------
# Config: repo that hosts the release (owner/name).
# Override with:  bash install.sh zyvoai/zyvo   or   ZYVO_REPO=zyvoai/zyvo
# ---------------------------------------------------------------
GITHUB_REPO="${1:-${ZYVO_REPO:-zyvoai/zyvo}}"

BINARY_NAME="opencode"
ASSET_PATTERN="android-aarch64.zip"

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

# ---------------------------------------------------------------
# 2. Install ripgrep (OpenCode uses it for file search)
# ---------------------------------------------------------------
if ! command -v rg >/dev/null 2>&1; then
  info "Installing ripgrep..."
  pkg install -y ripgrep
else
  info "ripgrep already installed"
fi

# ---------------------------------------------------------------
# 3. Resolve the latest release asset
# ---------------------------------------------------------------
info "Looking up the latest Android build in ${GITHUB_REPO}..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
TMP_JSON="$(mktemp)"
HTTP_CODE="$(curl -sSL -o "$TMP_JSON" -w '%{http_code}' "$API_URL" || echo 000)"
if [ "$HTTP_CODE" = "404" ]; then
  rm -f "$TMP_JSON"
  die "No release published yet in ${GITHUB_REPO}.
The Android build has not finished (or has not been run).
Open the repo's Actions tab on github.com and run 'Build OpenCode for
Android/Termux (aarch64)', wait for it to finish, then try again."
elif [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TMP_JSON"
  die "GitHub API returned HTTP $HTTP_CODE. Check your internet connection."
fi
RELEASE_JSON="$(cat "$TMP_JSON")"
rm -f "$TMP_JSON"

ASSET_URL="$(echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET_PATTERN}\"" | head -1 | grep -o 'https[^"]*')"
[ -n "$ASSET_URL" ] || die "No ${ASSET_PATTERN} asset found in the latest release of ${GITHUB_REPO}.

If the Android build has not been built yet, run the 'Build OpenCode for
Android/Termux (aarch64)' GitHub Actions workflow first (Actions tab)."

info "Downloading: $ASSET_URL"
TMP_DIR="$(mktemp -d)"
ZIP_FILE="${TMP_DIR}/${BINARY_NAME}.zip"
curl -fL --progress-bar "$ASSET_URL" -o "$ZIP_FILE" || die "Download failed."

# ---------------------------------------------------------------
# 4. Install
# ---------------------------------------------------------------
info "Installing to \$PREFIX/bin/${BINARY_NAME}..."
unzip -o "$ZIP_FILE" -d "$TMP_DIR" >/dev/null
[ -f "${TMP_DIR}/${BINARY_NAME}" ] || die "Downloaded archive does not contain ${BINARY_NAME}."
chmod +x "${TMP_DIR}/${BINARY_NAME}"
mv "${TMP_DIR}/${BINARY_NAME}" "$PREFIX/bin/${BINARY_NAME}"
rm -rf "$TMP_DIR"

# ---------------------------------------------------------------
# 5. Smoke test
# ---------------------------------------------------------------
info "Verifying installation..."
if "$PREFIX/bin/${BINARY_NAME}" --version; then
  echo ""
  echo -e "${GREEN}✔ ${BINARY_NAME} installed successfully!${NC}"
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
  die "Installed binary did not run. If your device is a Pixel 8/9 or other
ARMv9 (MTE) phone, please open an issue with the output of:
  ${BINARY_NAME} --version"
fi
