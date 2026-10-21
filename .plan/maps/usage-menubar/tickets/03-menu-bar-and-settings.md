---
type: task
blocked_by: [01, 02]
assets: [Sources/ClaudeUsage/AppDelegate.swift, Sources/ClaudeUsage/SettingsWindowController.swift, Sources/ClaudeUsage/Style.swift, Sources/UsageCore/AppConfig.swift, Sources/UsageCore/TapDeployment.swift]
---

# Build the UI: menu bar projection + settings/registration window

## Question

AFK build ticket. The AppKit layer as a **dumb projection** of UsageCore's view model (no
display decision of its own), plus the settings window:

- **Menu bar + dropdown:** status item (5-hour per account, labelled, coloured) and dropdown
  (both windows, bar + % + reset countdown + freshness + tap status). Driven by a short poll
  timer (not a file watcher; interval not configurable). `.accessory` policy, no Dock icon.
- **Settings / accounts:** auto-discover config dirs adjacent to the default + one-click
  accept; manual folder picker for unusual locations; human labels; remove; supports N
  accounts. Per-account tap status via the detector, one-click install via the installer — a
  registered account with no data is *explained*, never a silent dash. Warn threshold is one
  number (critical derived). Add/relabel updates the bar without restarting.

If a genuine product-behaviour question surfaces here (e.g. auto-discovery guessing wrong in a
way the spec didn't foresee), raise it — otherwise build to spec.

## Answer

Built and verified live, 2026-07-13. `swift run UsageCoreTests`: **91/91**.

**The projection.** `AppDelegate` is the composition root: load config → gather
`AccountState`s → `render(…, now)` → apply. The status item concatenates the view model's
styled segments; the dropdown renders each account's windows (mono bar + % + countdown),
freshness, and note; `Style.swift` is the only place tones become colours. 5s timer on the
`.common` run-loop mode (so countdowns keep ticking while the menu is open). Settings…
and Quit in the menu.

**Settings window.** Registered accounts with inline-editable labels, tap status per
account (installed ✓ / not installed / foreign command shown) with an explicit
Install/Replace button, Remove; discovered `.claude*` home directories with one-click Add
(hidden-files-aware folder picker as the escape hatch); warn slider 50–95 with the derived
red threshold displayed. Every mutation saves and refreshes the bar immediately — no
restart.

**Core additions** (UI stayed decision-free): `AppConfig`/`ConfigStore` (accounts +
threshold at `~/Library/Application Support/ClaudeUsage/config.json`; missing/garbage →
defaults), `Discovery` (`.claude*` dirs adjacent to home), `TapDeployment` (writes the
shared script to Application Support, 0755; a test locks the embedded script byte-for-byte
to the black-box-tested `tap/claude-usage-tap.sh`), and the dropdown's empty-state string
moved into the view model.

**Live verification.** Zero-config launch: bare `◐` in the real menu bar (screenshot).
With a throwaway config naming both real accounts: `◐ claude — · claude2 0%` — dash for
the never-reported account, and **the reset-boundary rule fired on real data**: the
ticket-01 snapshot (9%, reset 06:30Z) was 55 minutes past reset at capture time, and the
app showed empty rather than the stale 9%. Story 13, observed rather than simulated. The
throwaway config was removed and the app quit — acceptance (05) gets a clean stage to
register accounts through the app's own UI.
