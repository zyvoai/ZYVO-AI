# zyvo

<div align="center">

**AI coding agent for the terminal — built Android/Termux first.**

Runs directly on your phone. No PC required.

</div>

---

zyvo is a fork of [opencode](https://github.com/anomalyco/opencode) (MIT) with
a **native Android build** — a real arm64 binary compiled for Android itself,
so it runs directly inside [Termux](https://termux.dev) with **no proot, no
glibc layer, and no extra overhead**.

## 📱 Install on Android (Termux)

**Install Termux first** — from
[F-Droid](https://f-droid.org/en/packages/com.termux/) or
[GitHub Releases](https://github.com/termux/termux-app/releases)
(the Play Store version is outdated and unsupported).

Then open Termux and run:

```bash
curl -fsSL https://raw.githubusercontent.com/zyvoai/ZYVO-AI/main/install.sh | bash
```

That's it — the installer checks your phone's architecture, installs
`ripgrep`, downloads the latest build and verifies it runs.

**Start using it:**

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # or OPENAI_API_KEY, etc.
opencode
termux-wake-lock                        # optional: keep long sessions alive
```

**বাংলা:** টারমাক্স খুলে উপরের এক লাইনের কমান্ডটা paste করলেই install হয়ে
যাবে। এরপর যেকোনো AI-এর API key দিয়ে `opencode` লিখে শুরু করো।

### Requirements

| | |
|---|---|
| Phone | Any aarch64 (64-bit ARM) Android phone — i.e. almost every modern phone |
| Android | 7.0+ |
| App | [Termux](https://github.com/termux/termux-app/releases) (F-Droid / GitHub build) |
| Download | ~60–80 MB |

## 🖥️ Other platforms

zyvo tracks upstream opencode — on PC (Windows / macOS / Linux) you can use
upstream's installers while the zyvo-branded desktop builds are worked on:

```bash
npm i -g opencode-ai@latest
```

## 🔨 How the Android build works

opencode ships as a compiled Bun binary, and Bun has no official Android
target — so this repo cross-compiles the whole stack (Bun, WebKit/JavaScriptCore,
ICU, OpenTUI) for Android's own libc (bionic). The result is a single
standalone binary that runs natively in Termux.

Builds happen on GitHub Actions (`.github/workflows/android-build.yml`) and are
published to [Releases](https://github.com/zyvoai/ZYVO-AI/releases). The build
system lives in [`android/`](android/README.md), based on
[guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) (MIT).

## 🗺️ Roadmap

- [x] Native Android (aarch64) build for Termux
- [x] One-command installer for Termux
- [ ] Rebrand → `zyvo` command, config, TUI
- [ ] Custom system prompt & TUI theming
- [ ] Extra providers / commands / tools
- [ ] x86_64 build (emulators, Chromebooks)

## 📄 License

MIT — see [LICENSE](LICENSE). Based on
[opencode](https://github.com/anomalyco/opencode) and
[guysoft/opencode-termux](https://github.com/guysoft/opencode-termux), both MIT.
