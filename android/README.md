# Android (Termux) native build — aarch64

This directory contains the build system that cross-compiles OpenCode as a
**native Android (bionic) binary** so it runs directly in Termux — no proot,
no glibc layer.

Based on [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux)
(MIT), adapted for opencode v1.18.x.

## How it works

OpenCode ships as a compiled Bun binary. Bun has no official Android target,
so this pipeline:

1. **Cross-compiles Bun** for `aarch64-linux-android` (bionic libc) from
   source, applying Android compatibility patches:
   - `patches/bun/android-support.patch` — CMake/Zig build system, syscall
     fallbacks, Bionic libc compatibility, JIT signal handling, TLS alignment
   - `patches/webkit/android-support.patch` — WebKit/JavaScriptCore (the JS
     engine inside Bun) for Android
   - `patches/zig/posix-android-sigaction.patch` — Bun's vendored Zig:
     raw-syscall sigaction/sigprocmask (Bionic's struct layout differs)
2. **Builds supporting native libraries** for Android: ICU 75.1,
   WebKit/JSC, TinyCC, and `libopentui.so` (OpenTUI core, pinned to
   `$OPENTUI_TAG` to match the `@opentui/core` version OpenCode depends on)
3. **Builds OpenCode** with the host Bun (same version as the Android Bun,
   so the serialized module-graph format matches), swaps the x86_64
   `libopentui.so` for the Android one, then extracts the compiled module
   graph from the host standalone binary and appends it to the Android Bun
   binary ("binary surgery") to produce the final standalone executable.

## Version pins (see `scripts/env.sh`)

| Component   | Version | Why |
|-------------|---------|-----|
| Bun (target + host) | 1.3.11 | Last cmake-era Bun (1.3.12+ dropped CMake, which this pipeline builds with); host and target must match so module graph strides agree |
| WebKit/JSC  | `00e8255...` | Commit pinned by Bun 1.3.11 (`scripts/build/deps/webkit.ts`) |
| ICU         | 75.1 | Matches oven-sh/WebKit's build for this commit |
| OpenTUI     | v0.4.5 | `@opentui/core` version OpenCode depends on |
| OpenCode    | 1.18.25 | Latest upstream release at fork time |
| Android API | 24 | Minimum supported by the NDK toolchain |
| NDK         | r28b | |

## Building

The build runs on GitHub Actions (`.github/workflows/android-build.yml`)
because it requires Linux + Android NDK (~2-3 hours on a hosted runner,
cached afterward). To build manually on a Linux machine with the Android
NDK installed:

```bash
source android/scripts/env.sh
./android/scripts/apply-patches.sh
./android/scripts/build-icu.sh
./android/scripts/build-webkit.sh
./android/scripts/build-tinycc.sh
./android/scripts/build-bun.sh
./android/scripts/build-opentui.sh
./android/scripts/build-opencode.sh
./android/scripts/make-packages.sh
```

Outputs land in `$WORK_DIR/packages/` (zip + pacman + deb formats).

## License / attribution

- Build system and Android patches based on
  [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) (MIT).
- OpenCode is MIT licensed (see repository LICENSE).
