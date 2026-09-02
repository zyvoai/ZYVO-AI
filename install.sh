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

BINARY_NAME="zyvo"
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

# zyvo: session folders live on shared storage — request access once
if [ ! -d "$HOME/storage/shared" ] && command -v termux-setup-storage >/dev/null 2>&1; then
  info "Requesting storage permission — press ALLOW in the dialog (sessions will appear in /storage/emulated/0/ZYVO)"
  termux-setup-storage || true
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
#    The zip contains a Termux prefix layout:
#      data/data/com.termux/files/usr/bin/zyvo
#      data/data/com.termux/files/usr/libexec/zyvo/zyvo.bin
#      data/data/com.termux/files/usr/lib/*.so
# ---------------------------------------------------------------
info "Installing..."
unzip -o "$ZIP_FILE" -d "$TMP_DIR" >/dev/null
USR_DIR="${TMP_DIR}/data/data/com.termux/files/usr"
[ -f "${USR_DIR}/bin/${BINARY_NAME}" ] || die "Downloaded archive does not contain ${BINARY_NAME}."

mkdir -p "$PREFIX/bin" "$PREFIX/libexec/opencode" "$PREFIX/lib"
cp "${USR_DIR}/bin/${BINARY_NAME}" "$PREFIX/bin/${BINARY_NAME}"
chmod +x "$PREFIX/bin/${BINARY_NAME}"
# Android bun runtime (used by the binary for worker processes) + shared libs
[ -f "${USR_DIR}/libexec/zyvo/zyvo.bin" ] && \
  cp "${USR_DIR}/libexec/zyvo/zyvo.bin" "$PREFIX/libexec/zyvo/zyvo.bin"
for so in "${USR_DIR}"/lib/*.so; do
  [ -f "$so" ] && cp "$so" "$PREFIX/lib/"
done
rm -rf "$TMP_DIR"

# ---------------------------------------------------------------
# 4b. Deploy the Zyvo default config (50 free models via omniroute)
# ---------------------------------------------------------------
CONFIG_DIR="$HOME/.config/zyvo"
CONFIG_FILE="$CONFIG_DIR/zyvo.json"
CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/config/zyvo.json"
if [ ! -f "$CONFIG_FILE" ]; then
  info "Installing Zyvo default config (free models)..."
  mkdir -p "$CONFIG_DIR"
  if curl -fsSL "$CONFIG_URL" -o "$CONFIG_FILE" 2>/dev/null && [ -s "$CONFIG_FILE" ]; then
    info "Config ready: models appear inside zyvo automatically"
  else
    warn "Could not download config — you can add it later from the repo (config/opencode.json)"
  fi
else
  info "Existing config kept ($CONFIG_FILE)"
fi

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
