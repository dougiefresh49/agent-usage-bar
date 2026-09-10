# Android

Kotlin/Jetpack Compose port of Agent Usage Bar with home-screen widgets.

## What you get

- One-page usage overview (Claude / Codex / Cursor / ElevenLabs)
- Settings for pairing, polling, widget provider, primary/secondary stats,
  appearance, and notification thresholds
- Five home-screen widgets:
  - **Usage Grid (4 × 3)**: four-provider grid with size-aware charts
  - **Usage Dashboard (4 × 4)**: grid plus Settings and Refresh actions when space allows
  - **Usage Row (4 × 1)**: starts with provider charts arranged left to right
  - **Usage Column (1 × 3)**: starts with provider charts arranged top to bottom
  - **Provider Usage** (≈2 × 2): focused detail for the provider chosen in Settings
- Every overview widget is fully resizable. It automatically switches between a
  row, a column, and a 2 × 2 grid, scales each orbit to fill its cell, and hides
  secondary values or dashboard actions when the resized footprint is too small.
  This includes intermediate launcher sizes such as 2 × 3 and 2 × 4 without
  requiring separate picker entries.
- Pairing with the Mac over the tailnet. The phone displays the Mac's usage
  snapshot and does not store provider credentials
- QR import for selected settings (polling, appearance, notifications) from the
  macOS app
- Snapshot pull while the app is open (every 60 seconds) and a WorkManager
  background refresh (every 15 minutes, Android's periodic minimum)

## Requirements to build

- JDK 17+ (tested with Homebrew `openjdk@21`)
- Android SDK with Platform 35 + Build-Tools 35
- This folder's Gradle wrapper (`./gradlew`)

On this machine the SDK was installed to `~/Library/Android/sdk` and pointed at by
`android/local.properties` (gitignored).

```sh
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

cd android
./gradlew assembleDebug
```

Debug APK output:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## Install on a Pixel without Play Store (sideload)

### 1. Enable developer mode on the phone

1. Open **Settings → About phone**
2. Tap **Build number** 7 times until it says you are a developer
3. Back to **Settings → System → Developer options**
4. Enable **USB debugging**
5. (Optional but useful) Enable **Wireless debugging** if you prefer no cable

### 2. Connect the phone

**USB**

```sh
adb devices
```

Accept the “Allow USB debugging?” prompt on the Pixel the first time.

**Wireless (Android 11+)**

On the phone: Developer options → Wireless debugging → Pair device with pairing code.
Then:

```sh
adb pair <phone-ip>:<pairing-port>
adb connect <phone-ip>:<debug-port>
adb devices
```

### 3. Install the debug APK

```sh
cd android
./gradlew installDebug
# or
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The debug package id is `com.agentusagebar.android.debug`.

### 4. Add widgets

1. Long-press an empty spot on a home screen (or long-press the app icon → **Widgets**)
2. Find **Agent Usage Bar**
3. Drag **Usage Overview** and/or **Provider Usage** onto the home screen
4. Open the app, pair with the Mac, pull to refresh / wait for the worker — widgets update after each successful snapshot pull

## First-run setup in the app

1. Complete the welcome / polling screen
2. Open **Settings → Devices → Scan QR Code**
3. On the Mac, open **Settings → Devices → Add Device** and scan that code
4. Confirm the matching six-digit code, then approve the phone on the Mac

Both devices need to be on the tailnet. The phone then pulls the Mac's usage
snapshot (the same credential-free document the `ai-usage` skill reads). Provider
logins stay on the Mac. Reset credits from the phone ask the Mac to redeem.

The QR contains only a one-time handshake and the Mac's public key. Pairing
expires after 10 minutes. There is no cloud sync server.

## Findings / Android constraints worth knowing

| Topic | What it means |
| --- | --- |
| **Widgets need an installed app** | Widgets are registered by the APK. No Play Store listing is required; sideload is enough. |
| **Widget update cadence** | `updatePeriodMillis` cannot reliably fire faster than ~30 minutes. The open app pulls the Mac snapshot every **60 seconds**. WorkManager runs every **15 minutes** (Android’s minimum for periodic work) for widgets and background updates. Opening the app refreshes immediately. |
| **Battery optimizations** | Aggressive OEMs can delay WorkManager. On Pixel this is usually fine; if widgets go stale, disable battery restriction for the app under **Settings → Apps → Agent Usage Bar → Battery**. |
| **No provider credentials on the phone** | Claude / OpenAI / Cursor / ElevenLabs logins live on the Mac. A one-time upgrade wipe deletes any tokens previously stored in `agent_usage_bar_secure`. |
| **Mac unreachable** | If the Mac is asleep or off the tailnet, the last snapshot stays on screen and the footer reads `Mac unreachable` / `Mac unreachable since …`. The reset-credit button is disabled until a pull succeeds. |
| **Cross-device pairing** | The Mac and phone perform P-256 ECDH, confirm a matching code, and transfer settings with AES-GCM. Snapshot and redeem traffic uses the same pairing keys over the tailnet. |
| **Device removal** | The Mac keeps a device ledger. Removing a phone stops snapshot pulls and queues a wipe that forgets that Mac and drops its cached snapshot. |
| **Notifications** | Thresholds are stored (parity with macOS). Local notification firing is stubbed for this first Android cut — widgets + in-app UI are the primary glance surfaces. |
| **Install source warning** | First sideload may ask you to allow installing unknown apps for the installer you used (`adb` usually skips that UI). |

## Project layout

```text
android/
├── app/src/main/java/com/agentusagebar/android/
│   ├── data/           # models, pairing/snapshot client, repository
│   ├── ui/             # Compose home + settings (popover-like main screen)
│   ├── widget/         # Glance App Widgets
│   └── worker/         # WorkManager polling + boot reschedule
├── app/src/main/res/   # widget metadata, icons, strings
└── README.md           # this file
```

## Troubleshooting

- **`adb devices` empty** — unlock phone, replug USB, accept RSA prompt, try another cable/port.
- **Install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`** — uninstall the previous build first: `adb uninstall com.agentusagebar.android.debug`
- **Widgets show Connect / empty** — open the app and confirm a Mac is paired and reachable on the tailnet; tap refresh.
- **Mac unreachable** — the Mac app needs to be running on the tailnet. Stale numbers stay until the next successful pull.


## Importing settings from your Mac

1. On macOS, open **Settings → Devices → Add Device**.
2. Generate the QR code.
3. On Android, open **Settings → Devices → Scan QR Code** and scan it.
4. Verify that the six-digit codes match, then approve the phone on the Mac.

The QR carries no connection values. The encrypted transfer expires after 10
minutes. Settings (polling, appearance, notifications) can still sync; provider
tokens are not sent. The phone then pulls the usage snapshot from the Mac.


## Wireless updates (no USB cable)

Sideloaded debug apps do **not** auto-update from Play Store. Options:

### A. Wireless debugging (still uses `adb`, no cable)

On the Pixel: **Developer options → Wireless debugging → Pair device with pairing code**.

```sh
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb pair <phone-ip>:<pairing-port>    # enter the pairing code
adb connect <phone-ip>:<debug-port>
adb install -r android/AgentUsageBar-debug.apk
```

Phone and Mac must be on the same Wi‑Fi.

### B. Download the APK on the phone

1. On the Mac: `make android-apk`
2. Copy `android/AgentUsageBar-debug.apk` to the phone (AirDrop via Files, Google Drive, Dropbox, email to yourself, or a local HTTP server):

```sh
cd android && python3 -m http.server 8765
# then open http://<your-mac-lan-ip>:8765/AgentUsageBar-debug.apk on the phone browser
```

3. Open the downloaded APK → Install (allow “Install unknown apps” for Chrome/Files if prompted).

There is no silent OTA for a local debug build unless you add something like Firebase App Distribution later.

### C. Install signed GitHub releases

Tag-driven Android releases publish `AgentUsageBar.apk` on the repository's
GitHub Releases page. Every release is signed with the same private release key,
so installing a newer APK updates an existing release installation in place as
long as its `versionCode` is higher.

The local debug app uses `com.agentusagebar.android.debug`, while the signed
release app uses `com.agentusagebar.android`. The first signed release therefore
installs alongside an existing debug build. Configure or pair the release app
once, then remove the debug app when it is no longer needed.

The release keystore and passwords are stored only as GitHub Actions secrets.
Never commit `.jks`, `.keystore`, or `.p12` files to the repository. Losing the
release keystore prevents publishing compatible updates to existing installs.
