# UsageKit

<img width="439" height="466" alt="image" src="https://github.com/user-attachments/assets/ef883e3a-80e7-4f8d-a21e-262bc3ddcd02" />

> Forked from [Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar)

A macOS menu bar app that shows your **Claude** and **Codex** usage at a glance — always sitting at the top of your screen.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-BSD--2--Clause-green)

## What it does

Two menu bar icons — one for Claude (Anthropic), one for Codex (OpenAI) — each with:

- Dual progress bars showing remaining capacity in the 5-hour and 7-day windows
- Detailed popover with per-window usage, reset timers, and credits
- Usage history chart (1h / 6h / 1d / 7d / 30d) with hover details
- Configurable polling interval (5m / 15m / 30m / 1h)
- OAuth sign-in via browser — no API keys to manage
- Built-in update checks via Sparkle

| | Claude | Codex |
|---|---|---|
| Icon | Claude logo + bars (orange) | OpenAI logo + bars (green) |
| Auth | claude.ai OAuth → paste code | auth.openai.com OAuth → localhost callback |
| API | `/api/oauth/usage` | `/backend-api/wham/usage` |
| Extras | Per-model breakdown, extra usage ($) | Credits (balance) |

## Install

### Download

1. Download `UsageKit.dmg` from the [latest release](../../releases/latest)
2. Open the disk image and drag `UsageKit.app` into `Applications`
3. Launch the app from `/Applications`
4. macOS may require right-click → **Open** on first launch

### Build from source

Requires Xcode 15+ / Swift 5.9+ and macOS 14 (Sonoma) or later.

```sh
make app            # build .app bundle
make run            # build, kill existing, and launch
make install        # copy to /Applications
```

## Usage

1. Launch UsageKit — two menu bar icons appear (Claude + Codex)
2. Click either icon → **Sign in** → authorize in your browser
3. Icons update automatically (default: every 30 minutes)

Progress bars show **remaining capacity** (100% = fully available, decreasing as you use more).

## Data storage

All data is stored locally:

| Path | Purpose |
|------|---------|
| `~/.config/usagekit/credentials.json` | Claude OAuth token |
| `~/.config/usagekit/history.json` | Claude usage history (30-day retention) |
| `~/.config/usagekit/codex/credentials.json` | Codex OAuth token |
| `~/.config/usagekit/codex/history.json` | Codex usage history (30-day retention) |

No data is sent anywhere other than the Anthropic and OpenAI APIs.

## Development

```sh
make build          # release build only
make app            # build + create .app bundle
make run            # build + kill existing + launch (fast dev loop)
make zip            # build + bundle + zip + verify
make dmg            # build + bundle + DMG + verify
make release-artifacts  # create and verify both ZIP and DMG
make install        # build + install to /Applications
make clean          # remove build artifacts
```

### Project structure

```
macos/
├── Sources/UsageKit/
│   ├── UsageKitApp.swift            # App entry point, dual MenuBarExtra
│   ├── UsageService.swift           # Claude OAuth, polling, API
│   ├── UsageModel.swift             # Claude API response types
│   ├── CodexUsageService.swift      # Codex OAuth (localhost callback), polling
│   ├── CodexUsageModel.swift        # Codex API response types
│   ├── PopoverView.swift            # Claude popover UI
│   ├── CodexPopoverView.swift       # Codex popover UI
│   ├── MenuBarIconRenderer.swift    # Claude menu bar icon
│   ├── CodexMenuBarIcon.swift       # Codex menu bar icon
│   ├── WindowUtils.swift            # Popover mutual exclusivity
│   ├── UsageHistoryService.swift    # History persistence, downsampling
│   ├── UsageChartView.swift         # Swift Charts view
│   ├── SettingsView.swift           # Settings window
│   ├── NotificationService.swift    # Usage threshold notifications
│   └── Resources/
│       ├── claude-logo.png          # Claude menu bar logo (512px)
│       ├── openai-logo.png          # OpenAI menu bar logo (512px)
│       └── en.lproj/Localizable.strings
├── Tests/UsageKitTests/
├── Resources/                       # App bundle resources
│   ├── Info.plist
│   └── Assets.xcassets/
├── scripts/
│   ├── build.sh                     # Build + bundle + codesign
│   └── verify-release.sh            # Release artifact verification
└── Package.swift
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing with the mock server, and submission guidelines.

## License

[BSD 2-Clause](LICENSE)
