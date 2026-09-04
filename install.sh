#!/data/data/com.termux/files/usr/bin/bash
#
# Zyvo installer + smart updater for Termux (Android aarch64)
#
# Usage (in Termux):
#   curl -fsSL https://raw.githubusercontent.com/zyvoai/ZYVO-AI/main/install.sh | bash
#   bash install.sh --force          # full reinstall even if up to date
#
# Smart update: if the installed version matches the latest release, the
# ~50MB binary download is SKIPPED — only the tiny model-list config is
# refreshed. Binary downloads happen only when a new build is released.

set -euo pipefail

GITHUB_REPO="${1:-${ZYVO_REPO:-zyvoai/ZYVO-AI}}"
FORCE=false
for arg in "$@"; do
  [ "$arg" = "--force" ] && FORCE=true
done

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

# ---------------------------------------------------------------
# 3. Latest release info
# ---------------------------------------------------------------
info "Checking the latest release in ${GITHUB_REPO}..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
TMP_JSON="$(mktemp)"
HTTP_CODE="$(curl -sSL -o "$TMP_JSON" -w '%{http_code}' "$API_URL" || echo 000)"
if [ "$HTTP_CODE" = "404" ]; then
  rm -f "$TMP_JSON"
  die "No release published yet in ${GITHUB_REPO}.
Run the 'Build OpenCode for Android/Termux (aarch64)' workflow first, then retry."
elif [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TMP_JSON"
  die "GitHub API returned HTTP $HTTP_CODE. Check your internet connection."
fi
RELEASE_JSON="$(cat "$TMP_JSON")"
rm -f "$TMP_JSON"

LATEST_VERSION="$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*android-v//; s/"//')"
[ -n "$LATEST_VERSION" ] || LATEST_VERSION="unknown"

# Build id: changes on EVERY successful build, even when the opencode
# version string stays the same (UI tweaks, config-driven features etc.)
REMOTE_BUILD_ID="$(echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*build-id.txt\"" | head -1 | grep -o 'https[^"]*')"
REMOTE_BUILD_ID="$(curl -fsSL "$REMOTE_BUILD_ID" 2>/dev/null | head -1 || echo unknown)"

# ---------------------------------------------------------------
# 4. Config refresh function (tiny — always runs)
# ---------------------------------------------------------------
refresh_config() {
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
}

# ---------------------------------------------------------------
# 5. Smart update check — skip the big download when possible
# ---------------------------------------------------------------
CONFIG_DIR="$HOME/.config/zyvo"
CONFIG_FILE="$CONFIG_DIR/zyvo.json"

INSTALLED_VERSION=""
if [ -x "$PREFIX/bin/${BINARY_NAME}" ]; then
  INSTALLED_VERSION="$("$PREFIX/bin/${BINARY_NAME}" --version 2>/dev/null | head -1 | tr -d '[:space:]')"
fi

# Always ship the latest wrapper (fixes reach phones without a new release)
WRAPPER_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/android/wrapper.sh"
mkdir -p "$PREFIX/bin"
if curl -fsSL "$WRAPPER_URL" -o "$PREFIX/bin/${BINARY_NAME}.new" 2>/dev/null && [ -s "$PREFIX/bin/${BINARY_NAME}.new" ]; then
  chmod 755 "$PREFIX/bin/${BINARY_NAME}.new"
  mv "$PREFIX/bin/${BINARY_NAME}.new" "$PREFIX/bin/${BINARY_NAME}"
fi

LOCAL_BUILD_ID="none"
[ -f "$PREFIX/libexec/zyvo/build-id" ] && LOCAL_BUILD_ID="$(cat "$PREFIX/libexec/zyvo/build-id" | head -1)"

NEEDS_BINARY=false
if [ "$FORCE" = true ]; then NEEDS_BINARY=true
elif [ -z "$INSTALLED_VERSION" ]; then NEEDS_BINARY=true
elif [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then NEEDS_BINARY=true
elif [ "$REMOTE_BUILD_ID" != "$LOCAL_BUILD_ID" ]; then NEEDS_BINARY=true
fi

if [ "$NEEDS_BINARY" = false ]; then
  info "Already up to date (v${LATEST_VERSION}, build ${LOCAL_BUILD_ID})"
  refresh_config
  echo ""
  echo -e "${GREEN}✔ Config is current — binary untouched (no big download needed).${NC}"
  echo "Start it with:  ${BINARY_NAME}"
  exit 0
fi

if [ -n "$INSTALLED_VERSION" ]; then
  info "Update available: v${INSTALLED_VERSION} -> v${LATEST_VERSION} — downloading new build..."
else
  info "Fresh install of v${LATEST_VERSION}..."
fi

if [ -n "$INSTALLED_VERSION" ]; then
  info "Update available: v${INSTALLED_VERSION} -> v${LATEST_VERSION} — downloading new build..."
else
  info "Fresh install of v${LATEST_VERSION}..."
fi

# ---------------------------------------------------------------
# 6. Download the build
# ---------------------------------------------------------------
ASSET_URL="$(echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET_PATTERN}\"" | head -1 | grep -o 'https[^"]*')"
[ -n "$ASSET_URL" ] || die "No ${ASSET_PATTERN} asset found in the latest release of ${GITHUB_REPO}."

info "Downloading: $ASSET_URL"
TMP_DIR="$(mktemp -d)"
ZIP_FILE="${TMP_DIR}/${BINARY_NAME}.zip"
curl -fL --progress-bar "$ASSET_URL" -o "$ZIP_FILE" || die "Download failed."

# ---------------------------------------------------------------
# 7. Install (zip = Termux prefix layout)
# ---------------------------------------------------------------
info "Installing..."
unzip -o "$ZIP_FILE" -d "$TMP_DIR" >/dev/null
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
# Always ship the latest wrapper from the repo (wrapper fixes reach phones
# without a full binary release)
WRAPPER_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/android/wrapper.sh"
if curl -fsSL "$WRAPPER_URL" -o "$PREFIX/bin/${BINARY_NAME}.new" 2>/dev/null && [ -s "$PREFIX/bin/${BINARY_NAME}.new" ]; then
  chmod 755 "$PREFIX/bin/${BINARY_NAME}.new"
  mv "$PREFIX/bin/${BINARY_NAME}.new" "$PREFIX/bin/${BINARY_NAME}"
fi
mkdir -p "$PREFIX/libexec/zyvo"
printf '%s
' "$REMOTE_BUILD_ID" > "$PREFIX/libexec/zyvo/build-id"
rm -f "$PREFIX/bin/opencode" 2>/dev/null || true
rm -rf "$PREFIX/libexec/opencode" 2>/dev/null || true
rm -rf "$TMP_DIR"

# ---------------------------------------------------------------
# 8. Config + smoke test
# ---------------------------------------------------------------
refresh_config

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
  echo ""
  echo "Model-list updates only: re-run this installer — no big download."
else
  die "Installed binary did not run. Please open an issue with the output of:
  ${BINARY_NAME} --version"
fi
