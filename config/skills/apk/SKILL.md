---
name: apk
description: Build Android APKs on GitHub Actions — scaffold a modern Material 3 Android app (with good UI design), push to GitHub, get a signed APK download link. Zero load on the user's phone. Use when the user asks to create/build/make an Android app or APK.
---

# Android APK Builder (GitHub cloud build)

Build Android apps WITHOUT any load on the user's phone. You write the
project files, push them to GitHub, and GitHub Actions compiles the APK in
the cloud (free for public repos). The phone only writes text files.

## Golden rules

1. The phone NEVER runs gradle/java/aapt — all compilation happens on
   GitHub Actions.
2. Always produce a MODERN, good-looking UI (Material 3 style) — never ship
   a bare default-looking app. Follow the Design System section below, and
   when the app type is unusual, fetch design inspiration with WebFetch from
   https://m3.material.io/components and similar pages.
3. Keep sources in `$HOME/<project>` — never in shared storage
   (`/storage` is mounted noexec and git there is unreliable).
4. NEVER put the user's GitHub token inside any committed file.

## Requirements checklist (do this first)

- `git` installed: `pkg install -y git` (skip if present)
- User has a GitHub account
- User has a **Personal Access Token** with BOTH `repo` and `workflow`
  scopes (workflow is required — the project always pushes GitHub Actions
  files). Give them this DIRECT link, which lands on the token-creation
  page with both scopes ALREADY pre-checked:
  https://github.com/settings/tokens/new?scopes=repo,workflow&description=Zyvo%20APK%20builder
  The user only scrolls down, clicks "Generate token", and copies it —
  the token is shown only once, so they must paste it to you immediately.
  (ask the user for it if not provided; store nothing in files)
- GitHub username known (ask if needed)

If the user has no token, show them exactly the steps above and wait.

## Step 1 — Ask the user (missing info only)

1. What should the app do? (feature list)
2. App name + package id (default: `com.zyvo.<shortname>`)
3. GitHub username + Personal Access Token
4. Repo name (default: the app shortname). Ask: public (free builds) or
   private? Default public.

## Step 2 — Design pass

- Look at the Design System below and pick a color pair (primary + dark
  surfaces) that fits the app's purpose.
- If the app type is uncommon, use WebFetch on
  `https://m3.material.io/components` and
  `https://m3.material.io/styles/color/overview` to pick components.
- Decide the template: **native Java UI** (calculator/notes/tools) or
  **WebView app** (HTML/CSS/JS UI — fastest path, full CSS design freedom).
  Default to WebView for content-heavy apps, native for tool-like apps.

## Step 3 — Scaffold the project

Create under `$HOME/<appname>/` (write every file completely — never leave
TODOs):

```
<appname>/
  settings.gradle
  build.gradle
  gradle.properties
  .github/workflows/build.yml
  app/build.gradle
  app/src/main/AndroidManifest.xml
  app/src/main/java/<package path>/<MainActivity>.java
  app/src/main/res/values/colors.xml
  app/src/main/res/values/themes.xml
  app/src/main/res/values/strings.xml
  app/src/main/res/layout/activity_main.xml   (native template only)
```

### settings.gradle
```gradle
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "<AppName>"
include ':app'
```

### build.gradle (root)
```gradle
plugins { id 'com.android.application' version '8.5.2' apply false }
```

### gradle.properties
```gradle
org.gradle.jvmargs=-Xmx1024m
org.gradle.daemon=false
org.gradle.parallel=false
android.useAndroidX=true
android.nonTransitiveRClass=true
```

### app/build.gradle
```gradle
plugins { id 'com.android.application' }
android {
    namespace '<package>'
    compileSdk 34
    defaultConfig {
        applicationId '<package>'
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    buildFeatures { viewBinding true }
}
dependencies { implementation 'androidx.appcompat:appcompat:1.7.0' }
```

### AndroidManifest.xml (minimum)
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="@string/app_name" android:theme="@style/Theme.Zyvo"
    android:icon="@mipmap/ic_launcher" android:supportsRtl="true">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
```
NOTE: `@mipmap/ic_launcher` needs an icon — simplest is to REMOVE the
icon attribute (system default icon is used) unless you add res/mipmap
files. Prefer removing it.

### Design System (use in layouts/themes/colors)

- Colors: define primary (brand), onPrimary, surface (#10131a-style dark or
  light per app), and use 12–16dp corner radius on cards/buttons.
- Typography: title 20sp medium, body 14–16sp regular, captions 12sp muted.
- Spacing: 16dp screen padding, 8dp between related items, 24dp between
  sections.
- Dark mode: provide values-night/colors.xml with darkened surface colors.
- Buttons: filled pill shape for primary action; outlined for secondary.
- Lists: CardView-style rounded cards with 8dp internal padding and subtle
  elevation.

### WebView template (fast, full design freedom)

If the app is content/UI-heavy (dashboard, landing page, simple tools),
make it a WebView app: put the entire app in
`app/src/main/assets/index.html` (+ css/js files) with a modern responsive
design (inline CSS), and a tiny MainActivity:

```java
public class MainActivity extends Activity {
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        WebView w = new WebView(this);
        w.getSettings().setJavaScriptEnabled(true);
        w.setWebViewClient(new WebViewClient());
        setContentView(w);
        w.loadUrl("file:///android_asset/index.html");
    }
}
```
Write the HTML/CSS with the same design system: dark/light surfaces,
rounded cards, brand color accents, responsive layout.

## Step 4 — GitHub Actions workflow

`.github/workflows/build.yml`:
```yaml
name: Build APK
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - run: gradle assembleDebug --no-daemon
      - uses: actions/upload-artifact@v4
        with: { name: app-debug, path: app/build/outputs/apk/debug/app-debug.apk }
      - name: Attach to release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: apk-${{ github.run_number }}
          files: app/build/outputs/apk/debug/app-debug.apk
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
No gradle wrapper needed (setup-gradle action provides gradle). Never
commit a gradle-wrapper jar you cannot verify.

## Step 5 — Push to GitHub

1. Create the repo with the user's token (public unless they chose private):
```
curl -s -X POST -H "Authorization: token <TOKEN>" \
  -d '{"name":"<repo>","private":false}' https://api.github.com/user/repos
```
2. Then:
```
cd $HOME/<appname>
git init -b main
git config user.name "<github username>"
git config user.email "<username>@users.noreply.github.com"
git add -A && git commit -m "zyvo: initial app"
git remote add origin "https://<TOKEN>@github.com/<user>/<repo>.git"
git push -u origin main
```
3. The build starts automatically. Tell the user: first build takes 5–10
   minutes.

## Step 6 — Give the user the APK

Watch the run:
```
curl -s -H "Authorization: token <TOKEN>" \
  https://api.github.com/repos/<user>/<repo>/actions/runs?per_page=1
```
(status → completed + conclusion success). Then give the user:

- **Download link (no login):**
  `https://github.com/<user>/<repo>/releases` → latest → app-debug.apk
- The user opens it in their browser, taps the APK, allows
  "install unknown apps" for their browser once, and installs.

If the run FAILED: read the log via
`https://api.github.com/repos/<user>/<repo>/actions/runs/<id>/logs`
(fetch the zip, unzip, read) — fix the reported file/line, commit, push
again. Common causes: syntax error in XML/Java, missing icon resource,
gradle typo, wrong namespace.

## Pitfalls

- JDK: setup-java uses 17 — matches AGP 8.5.x. Don't bump Java to 21 with
  older AGP.
- compileSdk 34 everywhere (manifest/gradle) — mixing versions breaks.
- Never reference `@mipmap/ic_launcher` unless you ship it.
- Shared storage (`/storage`, `~/storage`) is noexec — never build there.
- Never echo the token into logs or commit it.
- Public repos give unlimited free Actions minutes; private repos have
  a 2000 min/month free limit.

## After the first build

- Code changes: edit files → commit → push → new APK automatically.
- New features: repeat the design pass (Step 2) before coding.
- If the user wants updates without git: re-run Step 5 with `--force`
  (push -f) after editing.
