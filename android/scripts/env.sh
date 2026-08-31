#!/usr/bin/env bash
# Environment variables for building OpenCode for Android aarch64
# Source this file before running any build scripts:
#   source scripts/env.sh
#
# Based on guysoft/opencode-termux (MIT), adapted for opencode v1.18.x:
#   - Bun 1.3.11: last cmake-era Bun (1.3.12+ moved off CMake) and produces
#     the 52-byte CompiledModuleGraphFile stride that host Bun >= 1.3.11 emits.
#   - WebKit commit + ICU pinned to what Bun 1.3.11 expects
#     (scripts/build/deps/webkit.ts -> 00e8255..., oven-sh/WebKit Dockerfile -> ICU 75.1).

set -euo pipefail

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Versions
# We no longer cross-compile Bun/WebKit/ICU ourselves: the pipeline uses the
# PROVEN prebuilt Android runtime (opencode.bin + runtime .so files) published
# by guysoft/opencode-termux (v0.2.1), which ships opencode 1.17.9. We pin our
# OpenCode source to that same version for maximum runtime compatibility, and
# only build libopentui.so (for @opentui/core 0.4.5) + bundle our own code.
export OPENCODE_VERSION="${OPENCODE_VERSION:-1.17.9}"
export HOST_BUN_VERSION="${HOST_BUN_VERSION:-1.3.2}"
export ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
export OPENTUI_TAG="${OPENTUI_TAG:-v0.4.5}"
export ANDROID_API="${ANDROID_API:-24}"

# Prebuilt Android runtime from guysoft/opencode-termux v0.2.1
export PREBUILT_URL="${PREBUILT_URL:-https://github.com/guysoft/opencode-termux/releases/download/v0.2.1/opencode-1.17.9-android-aarch64.zip}"

# Android NDK
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"
export ANDROID_ABI=arm64-v8a
export ANDROID_ARCH=aarch64
export ANDROID_TRIPLE="aarch64-linux-android"
export ANDROID_TRIPLE_API="${ANDROID_TRIPLE}${ANDROID_API}"

# NDK toolchain paths
export NDK_TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
export NDK_SYSROOT="${NDK_TOOLCHAIN}/sysroot"
export ANDROID_CC="${NDK_TOOLCHAIN}/bin/${ANDROID_TRIPLE_API}-clang"
export ANDROID_CXX="${NDK_TOOLCHAIN}/bin/${ANDROID_TRIPLE_API}-clang++"
export ANDROID_AR="${NDK_TOOLCHAIN}/bin/llvm-ar"
export ANDROID_RANLIB="${NDK_TOOLCHAIN}/bin/llvm-ranlib"
export ANDROID_STRIP="${NDK_TOOLCHAIN}/bin/llvm-strip"
export ANDROID_NM="${NDK_TOOLCHAIN}/bin/llvm-nm"
export ANDROID_LD="${NDK_TOOLCHAIN}/bin/ld.lld"

# Build directories (all relative to REPO_ROOT)
export WORK_DIR="${WORK_DIR:-${REPO_ROOT}/build}"
export OPENTUI_SRC="${WORK_DIR}/opentui-src"
export OPENCODE_SRC="${WORK_DIR}/opencode-src"
export PREBUILT_DIR="${WORK_DIR}/prebuilt"

export DIST_DIR="${WORK_DIR}/dist"

# Number of parallel jobs (can be overridden for low-RAM machines)
export JOBS="${JOBS:-$(nproc)}"

echo "=== OpenCode Android Build Environment ==="
echo "Repo root:     ${REPO_ROOT}"
echo "Work dir:      ${WORK_DIR}"
echo "Prebuilt URL:  ${PREBUILT_URL}"
echo "OpenTUI tag:   ${OPENTUI_TAG}"
echo "OpenCode ver:  ${OPENCODE_VERSION} (host bun: ${HOST_BUN_VERSION})"
echo "Jobs:          ${JOBS}"
echo "==========================================="
