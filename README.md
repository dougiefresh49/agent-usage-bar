<p align="center">
  <img src="macos/Resources/icon.png" width="128" alt="Agent Usage Bar icon">
</p>

# Agent Usage Bar

Keep Claude, OpenAI/Codex, and Cursor subscription usage visible from one small macOS menu-bar app.

Now it's just a glimpse away — always sitting at the top of your screen.

<p align="center">
  <img src="macos/Resources/demo.png" width="400" alt="Agent Usage Bar demo">
</p>

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-BSD--2--Clause-green)

## What it does

A tiny macOS menu bar app that shows your AI subscription usage at a glance. Click it for the full picture:

- Menu bar icon with a mini dual-bar showing 5-hour and 7-day utilization
- Claude 5-hour, 7-day, extra usage, and dynamic per-model limits such as Fable
- OpenAI/Codex usage windows, reset timers, and available reset-credit announcements
- Cursor first-party/API usage plus on-demand spend and billing-cycle reset
- Extra usage tracking with USD currency display
- Usage history chart — see how your usage evolves over time (1h / 6h / 1d / 7d / 30d)
- Hover over the chart to see exact values at any point
- Configurable polling interval (5m / 15m / 30m / 1h)
- Built-in update checks via Sparkle
- Claude OAuth via browser; local session-token configuration for OpenAI and Cursor
- Minimal dependencies — SwiftUI, Swift Charts, Foundation, and Sparkle for updates

## Install

### Download

1. Download `AgentUsageBar.dmg` from the [latest release](https://github.com/Blimp-Labs/claude-usage-bar/releases/latest)
2. Open the disk image and drag `AgentUsageBar.app` into `Applications`
3. Launch the app from `/Applications`
4. macOS may require right-click → **Open** on first launch

### Build from source

Requires Xcode 15+ / Swift 5.9+ and macOS 14 (Sonoma) or later.

```sh
git clone https://github.com/Blimp-Labs/claude-usage-bar.git
cd claude-usage-bar
make app            # build .app bundle
make dmg            # build drag-to-Applications disk image
make install        # copy to /Applications
```

## Usage

1. Launch the app — a menu bar icon appears
2. Click the icon → **Sign in with Claude** → authorize in your browser
3. Paste the code back into the app
4. The icon updates automatically (default: every 30 minutes)
5. Release builds show **Check for Updates…** in the popover so you can pull newer versions without re-downloading manually

### Connect OpenAI and Cursor

Open **Settings…** from the popover:

- **OpenAI / Codex:** paste the bearer token from the `Authorization` header of the
  ChatGPT `backend-api/wham/usage` request.
- **Cursor:** paste the `WorkosCursorSessionToken` cookie value from `cursor.com`.
  A copied Cookie header or cURL request also works.

These private dashboard endpoints use browser sessions. An OpenAI platform API key
and a Cursor API key do not expose the subscription limits shown on their account
dashboards. Tokens are saved only to the local credentials file with `0600`
permissions. For development, `OPENAI_SESSION_TOKEN` and `CURSOR_SESSION_TOKEN`
environment variables are also supported.

Click the icon anytime to see:
- 5-hour and 7-day usage with progress bars and reset timers
- Per-model breakdown (Opus / Sonnet) when available
- Extra usage credits and limits
- Usage history chart with adjustable time range and hover details

## Data storage

All data is stored locally in `~/.config/claude-usage-bar/`:

| File | Purpose |
|------|---------|
| `credentials.json` | Claude OAuth credentials (permissions: `0600`) |
| `service-credentials.json` | OpenAI and Cursor session tokens (permissions: `0600`) |
| `history.json` | Usage history for the chart (30-day retention) |

History is buffered in memory and flushed to disk every 5 minutes and on app quit.
Usage requests go directly to Anthropic, OpenAI, and Cursor; no credentials or usage
data are sent anywhere else.

## Agent skill

The app writes a usage snapshot to
`~/Library/Application Support/AgentUsageBar/usage-snapshot.json` after every
refresh, so coding agents can check remaining quota (e.g. to pick which model to
route subagent work to) without touching provider APIs or credentials.

Install the bundled Claude Code skill with:

```bash
make install-skill   # copies skills/ai-usage to ~/.claude/skills/
```

Agents read the snapshot directly when it is fresh. When it is older than
2 minutes, the skill's `get-usage.sh` posts a Darwin notification
(`notifyutil -p com.agentusagebar.refresh`) that asks the running app to
refresh; the app honors at most one such request per 2 minutes, so scripted
callers cannot cause API spam.

## Development

```sh
make build          # release build only (SwiftPM Keychain access disabled)
make app            # build + create .app bundle
make zip            # build + bundle + zip + verify distribution artifact
make dmg            # build + bundle + DMG + verify distribution artifact
make release-artifacts  # build once, then create and verify both ZIP and DMG
make verify-release # inspect the packaged ZIP and DMG artifacts
make install        # build + install to /Applications
make clean          # remove build artifacts
```

## Publishing updates

This repo now uses a tag-driven release flow. Pushing a `v*` tag will:

- build the `.app` bundle once
- produce `AgentUsageBar.zip` for Sparkle and `AgentUsageBar.dmg` for manual installs
- verify the packaged artifacts contain the expected app bundle resources and updater framework
- create the GitHub Release
- reuse GitHub-generated release notes for both the GitHub Release and the Sparkle update entry
- generate a signed Sparkle `appcast.xml` from that exact zip
- deploy the appcast to GitHub Pages

Publishing a release is just:

```sh
git tag v0.0.5
git push origin v0.0.5
```

One-time repo setup:

1. Enable GitHub Pages and set the source to `GitHub Actions`.
2. Add a repository Actions secret named `SPARKLE_PRIVATE_KEY`.

Local source builds intentionally ship with Sparkle disabled unless `SU_FEED_URL` is injected during packaging. This prevents forks and local builds from auto-updating to upstream binaries.

Manual installs should prefer the DMG. The ZIP remains the source of truth for Sparkle updates and appcast generation.

You can export the current Sparkle private key from your local Keychain with:

```sh
macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account claude-usage-bar -x /tmp/claude-usage-bar.sparkle.key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/claude-usage-bar.sparkle.key
```

The appcast feed URL used by release builds is:

```text
https://blimp-labs.github.io/claude-usage-bar/appcast.xml
```

### Project structure

```
macos/                           # macOS menu bar app (Swift/SwiftUI)
├── Sources/ClaudeUsageBar/
│   ├── AgentUsageBarApp.swift       # App entry point, menu bar setup
│   ├── UsageService.swift           # OAuth, polling, API calls
│   ├── UsageModel.swift             # API response types
│   ├── UsageHistoryModel.swift      # History data types, time ranges
│   ├── UsageHistoryService.swift    # Persistence, downsampling
│   ├── UsageChartView.swift         # Swift Charts trajectory view
│   ├── PopoverView.swift            # Main popover UI
│   ├── SettingsView.swift           # Settings window
│   ├── NotificationService.swift    # Usage threshold notifications
│   ├── MenuBarIconRenderer.swift    # Menu bar icon drawing
│   ├── PollingOptionFormatter.swift # Polling interval display labels
│   ├── AppUpdater.swift             # Sparkle update integration
│   └── Resources/
│       ├── claude-logo.png          # Pre-rendered menu bar logo (512px)
│       └── en.lproj/Localizable.strings
├── Tests/ClaudeUsageBarTests/
├── Resources/                       # App bundle resources (not SwiftPM)
│   ├── Info.plist
│   ├── Assets.xcassets/             # App icon
│   └── claude-logo.svg             # Source SVG for menu bar logo
├── scripts/
│   ├── build.sh                     # Build + bundle + codesign
│   └── generate-logo-png.swift      # Regenerate logo PNG from SVG
└── Package.swift

scripts/                         # Shared tooling
└── mock-server.py               # Local mock API for development
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing with the mock server, and submission guidelines.

## License

[BSD 2-Clause](LICENSE)
