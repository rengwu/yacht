---
type: task
blocked_by: [01, 02]
claimed_by: claude-code-session-2026-07-13-fable
claimed_at: 2026-07-13T05:45:41Z
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
