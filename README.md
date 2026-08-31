# zyvo

AI coding agent for the terminal — Android/Termux first.

Fork of [opencode](https://github.com/anomalyco/opencode) (MIT) with a native
Android (aarch64) build that runs directly in [Termux](https://termux.dev) —
no proot, no glibc layer.

## Install (Termux)

```bash
curl -fsSL https://raw.githubusercontent.com/zyvoai/zyvo/main/install.sh | bash
```

Requirements: aarch64 phone (any modern Android), Termux from
[F-Droid](https://f-droid.org/en/packages/com.termux/) or
[GitHub](https://github.com/termux/termux-app/releases).

After install, set a provider key and run `opencode`.

- Android build system: [android/README.md](android/README.md)
- License: MIT (see [LICENSE](LICENSE))
