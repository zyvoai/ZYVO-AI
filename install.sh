#!/data/data/com.termux/files/usr/bin/bash
#
# Zyvo installer + delta updater for Termux (Android aarch64)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zyvoai/ZYVO-AI/main/install.sh | bash
#
# Update modes:
#   - runtime unchanged: downloads ONLY the code graph (~11MB) and re-attaches
#   - runtime changed / fresh install: full package
#   - wrapper + model-list config: always refreshed (KB)

set -euo pipefail

GITHUB_REPO="${1:-${ZYVO_REPO:-zyvoai/ZYVO-AI}}"
FORCE=false
for arg in "$@"; do [ "$arg" = "--force" ] && FORCE=true; done

BINARY_NAME="zyvo"
BIN="$PREFIX/libexec/zyvo/zyvo.bin"
META="$PREFIX/libexec/zyvo/update-meta"

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
command -v zstd >/dev/null 2>&1 || { info "Installing zstd..."; pkg install -y zstd; }
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

mkdir -p "$PREFIX/bin" "$PREFIX/libexec/zyvo" "$HOME/.config/zyvo"

# Latest wrapper deploys on every run
WRAPPER_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/android/wrapper.sh"
if curl -fsSL "$WRAPPER_URL" -o "$PREFIX/bin/${BINARY_NAME}.new" 2>/dev/null && [ -s "$PREFIX/bin/${BINARY_NAME}.new" ]; then
  chmod 755 "$PREFIX/bin/${BINARY_NAME}.new"
  mv "$PREFIX/bin/${BINARY_NAME}.new" "$PREFIX/bin/${BINARY_NAME}"
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
  die "No release published yet in ${GITHUB_REPO}. Run the build workflow first, then retry."
elif [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TMP_JSON"
  die "GitHub API returned HTTP $HTTP_CODE. Check your internet connection."
fi
RELEASE_JSON="$(cat "$TMP_JSON")"
rm -f "$TMP_JSON"

asset_url() { echo "$RELEASE_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*$1\"" | head -1 | grep -o 'https[^"]*' || true; }

LATEST_VERSION="$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*android-v//; s/"//')"
[ -n "$LATEST_VERSION" ] || LATEST_VERSION="latest"
REMOTE_BUILD_ID="$(asset_url "build-id.txt" | xargs curl -fsSL 2>/dev/null | head -1 || echo unknown)"
GRAPH_META_URL="$(asset_url "graph-meta.txt")"
GRAPH_URL="$(asset_url "graph.bin.zst")"
REMOTE_CORE=""; REMOTE_GRAPH=""; REMOTE_TOTAL=""
if [ -n "$GRAPH_META_URL" ]; then
  GRAPH_META="$(curl -fsSL "$GRAPH_META_URL" 2>/dev/null || true)"
  REMOTE_CORE="$(echo "$GRAPH_META" | grep '^core=' | cut -d= -f2 || true)"
  REMOTE_GRAPH="$(echo "$GRAPH_META" | grep '^graph=' | cut -d= -f2 || true)"
  REMOTE_TOTAL="$(echo "$GRAPH_META" | grep '^total=' | cut -d= -f2 || true)"
fi
info "Latest: v${LATEST_VERSION} (build ${REMOTE_BUILD_ID})"

CONFIG_FILE="$HOME/.config/zyvo/zyvo.json"
refresh_config() {
  CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/config/zyvo.json"
  if curl -fsSL "$CONFIG_URL" -o "$CONFIG_FILE.tmp" 2>/dev/null && [ -s "$CONFIG_FILE.tmp" ]; then
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    info "Model list config refreshed (backup: zyvo.json.bak)"
  else
    rm -f "$CONFIG_FILE.tmp"
    warn "Could not refresh config — keeping what you have"
  fi
}

# ---------------------------------------------------------------
# 4. Local state
# ---------------------------------------------------------------
INSTALLED=false; [ -f "$BIN" ] && INSTALLED=true
LOCAL_BUILD="none"; LOCAL_CORE=""; LOCAL_GRAPH=""
if [ -f "$META" ]; then
  LOCAL_BUILD="$(grep '^build=' "$META" | cut -d= -f2 || echo none)"
  LOCAL_CORE="$(grep '^core=' "$META" | cut -d= -f2 || echo 0)"
  LOCAL_GRAPH="$(grep '^graph=' "$META" | cut -d= -f2 || echo 0)"
fi

save_meta() {
  {
    echo "build=$REMOTE_BUILD_ID"
    echo "core=$REMOTE_CORE"
    echo "graph=$REMOTE_GRAPH"
    echo "total=$REMOTE_TOTAL"
  } > "$META"
}

# ---------------------------------------------------------------
# 5. Decide the update path
# ---------------------------------------------------------------
CURRENT=false
[ "$INSTALLED" = true ] && [ "$LOCAL_BUILD" = "$REMOTE_BUILD_ID" ] && CURRENT=true

NEED_FULL=false
NEED_GRAPH=false
if [ "$FORCE" = true ]; then NEED_FULL=true
elif [ "$CURRENT" = true ]; then NEED_FULL=false
elif [ "$INSTALLED" = false ]; then NEED_FULL=true
elif [ "$LOCAL_BUILD" = "none" ]; then NEED_FULL=true
elif [ -z "$REMOTE_CORE" ]; then NEED_FULL=true
elif [ "$REMOTE_CORE" = "$LOCAL_CORE" ]; then NEED_GRAPH=true
else NEED_FULL=true
fi

# ---------------------------------------------------------------
# 5a. Fast path: everything current
# ---------------------------------------------------------------
if [ "$CURRENT" = true ] && [ "$NEED_FULL" = false ] && [ "$NEED_GRAPH" = false ]; then
  refresh_config
  echo ""
  echo -e "${GREEN}✔ Everything up to date (v${LATEST_VERSION}, build ${REMOTE_BUILD_ID}).${NC}"
  echo "Start it with:  ${BINARY_NAME}"
  exit 0
fi

refresh_config

# ---------------------------------------------------------------
# 5b. Delta path: graph-only update (~11MB)
# ---------------------------------------------------------------
if [ "$NEED_GRAPH" = true ]; then
  info "Delta update available — downloading only the changed code graph..."
  TMP_DIR="$(mktemp -d)"
  GRAPH_ZST="${TMP_DIR}/graph.bin.zst"
  GRAPH_BIN="${TMP_DIR}/graph.bin"
  NEW_BIN="${TMP_DIR}/zyvo.new"

  curl -fL -C - --retry 3 --progress-bar "$GRAPH_URL" -o "$GRAPH_ZST" || die "Graph download failed."
  zstd -d -f "$GRAPH_ZST" -o "$GRAPH_BIN" || die "Graph decompress failed."
  ACTUAL=$(stat -c%s "$GRAPH_BIN" 2>/dev/null || echo 0)
  [ "$ACTUAL" = "$REMOTE_GRAPH" ] || die "Graph size mismatch ($ACTUAL != $REMOTE_GRAPH)."

  CORE_SIZE="$LOCAL_CORE"
  cp "$BIN" "${TMP_DIR}/old.bin"
  head -c "$CORE_SIZE" "${TMP_DIR}/old.bin" > "$NEW_BIN"
  cat "$GRAPH_BIN" >> "$NEW_BIN"
  TOTAL=$((CORE_SIZE + REMOTE_GRAPH + 8))
  i=0
  while [ $i -lt 8 ]; do
    b=$(( (TOTAL >> (8*i)) & 255 ))
    printf "\\$(printf '%03o' "$b")" >> "$NEW_BIN"
    i=$((i+1))
  done
  chmod 755 "$NEW_BIN"

  cp "$BIN" "${TMP_DIR}/zyvo.bak"
  mv "$NEW_BIN" "$BIN"
  if "$BIN" --version >/dev/null 2>&1; then
    save_meta
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}✔ Delta update applied (v${LATEST_VERSION}) — graph-only download.${NC}"
    echo "Start it with:  ${BINARY_NAME}"
    exit 0
  else
    warn "New binary failed smoke test — rolling back and doing a full download..."
    cp "${TMP_DIR}/zyvo.bak" "$BIN"
    rm -rf "$TMP_DIR"
  fi
fi

# ---------------------------------------------------------------
# 5c. Full path: download + install the complete package
# ---------------------------------------------------------------
ASSET_PATTERN="android-aarch64.tar.zst"
FULL_URL="$(asset_url "android-aarch64.tar.zst")"
if [ -z "$FULL_URL" ]; then
  ASSET_PATTERN="android-aarch64.zip"
  FULL_URL="$(asset_url "android-aarch64.zip")"
fi
[ -n "$FULL_URL" ] || die "No package asset found in the latest release of ${GITHUB_REPO}."

info "Downloading full package: $FULL_URL"
TMP_DIR="$(mktemp -d)"
PKG_FILE="${TMP_DIR}/${BINARY_NAME}.pkg"
download_pkg() {
  curl -fL -C - --retry 3 --retry-delay 2 --progress-bar "$FULL_URL" -o "$PKG_FILE"
}
download_pkg || download_pkg || die "Download failed twice. Check your connection and retry."

if [ "${ASSET_PATTERN##*.}" = "zip" ]; then
  check_pkg() { unzip -t "$1" >/dev/null 2>&1; }
  extract_pkg() { unzip -o "$1" -d "$2"; }
else
  check_pkg() { tar --zstd -tf "$1" >/dev/null 2>&1; }
  extract_pkg() { tar --zstd -xf "$1" -C "$2"; }
fi
if ! check_pkg "$PKG_FILE"; then
  warn "Archive looks corrupted — re-downloading once..."
  rm -f "$PKG_FILE"
  curl -fL --progress-bar "$FULL_URL" -o "$PKG_FILE" || die "Download failed again."
  check_pkg "$PKG_FILE" || die "Archive is still corrupted. Please retry later."
fi

info "Installing..."
extract_pkg "$PKG_FILE" "$TMP_DIR"
USR_DIR="${TMP_DIR}/data/data/com.termux/files/usr"
[ -f "${USR_DIR}/bin/${BINARY_NAME}" ] || die "Downloaded archive does not contain ${BINARY_NAME}."

mkdir -p "$PREFIX/bin" "$PREFIX/libexec/zyvo" "$PREFIX/lib"
cp "${USR_DIR}/bin/${BINARY_NAME}" "$PREFIX/bin/${BINARY_NAME}"
chmod 755 "$PREFIX/bin/${BINARY_NAME}"
if [ -f "${USR_DIR}/libexec/zyvo/zyvo.bin" ]; then
  cp "${USR_DIR}/libexec/zyvo/zyvo.bin" "$BIN"
  chmod 755 "$BIN"
else
  die "Downloaded archive does not contain the zyvo binary."
fi
for so in "${USR_DIR}"/lib/*.so; do
  [ -f "$so" ] && cp "$so" "$PREFIX/lib/"
done
rm -f "$PREFIX/bin/opencode" 2>/dev/null || true
rm -rf "$PREFIX/libexec/opencode" 2>/dev/null || true
rm -rf "$TMP_DIR"

if [ -n "$REMOTE_CORE" ]; then save_meta; fi

# ---------------------------------------------------------------
# 6. Config (model list) + smoke test
# ---------------------------------------------------------------
refresh_config

info "Verifying installation..."
if "$PREFIX/bin/${BINARY_NAME}" --version; then
  echo ""
  echo -e "${GREEN}✔ ${BINARY_NAME} v${LATEST_VERSION} installed successfully!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Set an AI provider key (e.g. export ANTHROPIC_API_KEY=...)"
  echo "  2. Start:  ${BINARY_NAME}"
  echo "  Update later with:  ${BINARY_NAME} update"
  echo ""
  echo "Keep the screen on during long sessions:  termux-wake-lock"
else
  die "Installed binary did not run. Please report with the output of:  ${BINARY_NAME} --version"
fi
