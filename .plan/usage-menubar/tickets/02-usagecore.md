---
type: task
blocked_by: []
claimed_by: claude-code-session-2026-07-13-fable
claimed_at: 2026-07-13T03:23:16Z
---

# Build UsageCore: model + pure display view-model + display-seam tests

## Question

AFK build ticket — the heart of the app, all behaviour already specified. Scaffold the SwiftPM
package (`UsageCore` library with **no AppKit**, `ClaudeUsage` executable, test target; rewrite
`build.sh` to bundle the SwiftPM binary). Then in `UsageCore`:

- The domain model: `Account` = (label, config dir); `Snapshot` living inside its config dir;
  `LimitWindow` (used-% + reset time), either independently absent.
- The single pure function `(accounts, settings, now) → view model` producing every string,
  colour, bar and countdown for both bar and dropdown. **Time injected, never ambient.**

Test the display seam (fixture dirs, frozen clock, assert on the view model — no AppKit, no
real clock/home): snapshot absent/malformed/partial; the reset boundary (before/at/after);
never-reported dash vs empty-window zero; warn/critical colouring per account on the threshold;
fractional-percent rounding, bar glyphs at extremes, countdown/staleness across unit
boundaries; ordering; zero accounts. Needs neither experiment — snapshot shape is fixed.
