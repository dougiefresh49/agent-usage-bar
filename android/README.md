# Android

Kotlin/Jetpack Compose port of Agent Usage Bar with home-screen widgets.

## What you get

- One-page usage overview (Claude / Codex / Cursor), matching the macOS popover
- Settings for polling, notification thresholds, and session tokens
- Two home-screen widgets:
  - **Usage Overview** (≈4×2): all three providers at a glance
  - **Provider Usage** (≈2×2): focused detail for the provider chosen in Settings
- Encrypted local storage for Claude OAuth + OpenAI/Cursor session tokens
- QR import for selected settings and connections from the macOS app
- Background refresh via WorkManager (every 15 minutes minimum — Android platform limit)

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
4. Open the app, connect providers, pull to refresh / wait for the worker — widgets update after each successful refresh

## First-run setup in the app

1. Complete the welcome / polling screen
2. **Claude:** Sign in with Claude → browser opens → paste `code#state` back into the app
3. **OpenAI / Codex:** Settings → paste the ChatGPT usage bearer token (same as macOS)
4. **Cursor:** Settings → paste `WorkosCursorSessionToken` (same as macOS)

Alternatively, open **Settings → Devices → Add Device** on the Mac, choose what
to transfer, then use **Settings → Devices → Scan QR Code** on Android. The QR
contains only a one-time handshake and the Mac's public key—not credentials.
Confirm the matching six-digit code on both devices, then approve the phone on
the Mac. Selected settings and OpenAI/Cursor/ElevenLabs credentials are
encrypted specifically for that phone. Pairing expires after 10 minutes and
uses the local network; there is no cloud sync server.

Tokens never leave the phone except when calling Anthropic / OpenAI / Cursor APIs.

## Findings / Android constraints worth knowing

| Topic | What it means |
| --- | --- |
| **Widgets need an installed app** | Widgets are registered by the APK. No Play Store listing is required; sideload is enough. |
| **Widget update cadence** | `updatePeriodMillis` cannot reliably fire faster than ~30 minutes. We also use WorkManager every **15 minutes** (Android’s minimum for periodic work) to refresh usage + push widget updates. Opening the app refreshes immediately. |
| **Battery optimizations** | Aggressive OEMs can delay WorkManager. On Pixel this is usually fine; if widgets go stale, disable battery restriction for the app under **Settings → Apps → Agent Usage Bar → Battery**. |
| **Claude OAuth** | Same public client + PKCE flow as macOS. Android opens the browser; you paste the callback code. No custom URL scheme is required for this flow. |
| **Session tokens** | OpenAI/Cursor tokens still come from private dashboard/session endpoints — same instructions as the macOS app. They expire; when they do, Settings will show an auth error. |
| **Cross-device pairing** | The Mac and phone perform P-256 ECDH, confirm a matching code, and transfer settings with AES-GCM. Imported credentials are written to EncryptedSharedPreferences; Claude OAuth remains a separate sign-in because copying its rotating refresh token could invalidate a session on either device. |
| **Device removal** | The Mac keeps a device ledger. Removing a phone stops future sync and queues deletion of credentials originally transferred by that Mac. The wipe is delivered when the phone next reaches the running Mac on the same local network; use the provider's session/key controls for immediate remote revocation. |
| **Notifications** | Thresholds are stored (parity with macOS). Local notification firing is stubbed for this first Android cut — widgets + in-app UI are the primary glance surfaces. |
| **Install source warning** | First sideload may ask you to allow installing unknown apps for the installer you used (`adb` usually skips that UI). |

## Project layout

```text
android/
├── app/src/main/java/com/agentusagebar/android/
│   ├── data/           # models, encrypted credentials, API client, repository
│   ├── ui/             # Compose home + settings (popover-like main screen)
│   ├── widget/         # Glance App Widgets
│   └── worker/         # WorkManager polling + boot reschedule
├── app/src/main/res/   # widget metadata, icons, strings
└── README.md           # this file
```

## Troubleshooting

- **`adb devices` empty** — unlock phone, replug USB, accept RSA prompt, try another cable/port.
- **Install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`** — uninstall the previous build first: `adb uninstall com.agentusagebar.android.debug`
- **Widgets show Connect / empty** — open the app and confirm providers are configured; tap refresh.
- **Claude sign-in fails with state mismatch** — start Sign in again and paste the newest code without restarting the flow mid-way.


## Importing settings from your Mac

1. On macOS, open **Settings → Devices → Add Device**.
2. Select polling, appearance, notifications, and any configured connections
   you want to copy.
3. Generate the QR code.
4. On Android, open **Settings → Devices → Scan QR Code** and scan it.
5. Verify that the six-digit codes match, then approve the phone on the Mac.

The QR carries no connection values. The encrypted transfer expires after 10
minutes, and Android stores imported credentials in encrypted app storage.
Claude still uses the browser OAuth flow separately on each device.


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
