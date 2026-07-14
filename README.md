# ⛵️ Yacht (yet another Claude headroom tracker)

<img src="https://i.imgur.com/u4zyU6o.png" />

A macOS menu bar app that shows Claude Code rate-limit usage — the 5-hour and
7-day windows, per account — without leaving the menu bar.

[![Download for macOS](https://img.shields.io/badge/Download-macOS-blue?style=for-the-badge)](https://github.com/rengwu/yacht/releases/latest/download/Yacht.dmg)

## Features

- Multiple accounts, each pointed at its own `~/.claude`-style config
  directory (auto-discovered, or add any folder by hand)
- Per-account 5-hour and 7-day usage bars with reset countdowns
- Configurable warning/critical color thresholds
- Customizable menu bar text, dropdown row text, separators, and icon
  (with a preset picker)
- Optional launch at login

<img src="https://i.imgur.com/e7lnzoe.png"/>

## Requirements

- macOS 13+
- Xcode Command Line Tools (no full Xcode install needed) — Swift 5.9+

## Build

```
./build.sh
```

Builds a release binary and assembles an ad-hoc-signed `build/Yacht.app`.
Move it to `/Applications` (or run it in place) and launch it like any other
app.

To build with a specific version stamped into the bundle:

```
./build.sh 1.2.0
```

## Usage

1. Launch the app — it lives entirely in the menu bar (no Dock icon).
2. Click the menu bar item → **Settings…**.
3. Under **Accounts**, add a Claude config directory (discovered folders are
   offered automatically, or use **Add Claude Config Folder…** for anything
   else).
4. Click **Install Tap** next to the account. This writes the tap script to
   `~/Library/Application Support/Yacht/` and points that account's
   `settings.json` `statusLine` at it, preserving every other key already in
   the file. If another status line command is already installed, the app
   tells you rather than overwriting it silently.
5. Usage data appears after Claude Code's next turn for that account.

All settings persist to
`~/Library/Application Support/Yacht/config.json`.

## How it works

Claude Code can run a `statusLine` command on every turn. This app installs a
small script (the "tap") as that command for each account you register. The
tap reads the status line's JSON payload from stdin and, whenever it carries
`rate_limits`, writes a snapshot to `usage-snapshot.json` inside that
account's Claude config directory. The app polls those snapshot files and
renders them in the menu bar and dropdown — it never talks to any network
itself.

The tap is deliberately inert: it prints nothing (so it never appears as a
visible status line), always exits `0`, and writes atomically, so it can
never break the Claude Code session hosting it.

## Development

```
swift build
swift run UsageCoreTests
```

Tests are a plain executable, not an XCTest bundle — this repo targets a
Command Line Tools–only toolchain, and XCTest ships with Xcode.

Project layout:

- `Sources/UsageCore` — model, config, tap install/deploy, and view-model
  rendering. No AppKit dependency, so it's testable headless.
- `Sources/Yacht` — the app: status item, settings window, launch-at-login.
  A thin projection of `UsageCore`'s view model.
- `Tests/UsageCoreTests` — the test suite.
- `tap/claude-usage-tap.sh` — the tap script, kept in sync with the copy
  embedded in `UsageCore` (test-enforced).

## Releasing

Push a tag matching `v*.*.*`:

```
git tag v1.0.0
git push origin v1.0.0
```

This triggers `.github/workflows/release.yml`, which builds the app, stamps
the version, packages it as a DMG, and publishes a GitHub Release with the
DMG attached. Every push and PR to `main` also runs
`.github/workflows/ci.yml` (build + test).

The app is ad-hoc signed, not notarized — anyone downloading the DMG will
need to right-click → Open the first time to get past Gatekeeper.
