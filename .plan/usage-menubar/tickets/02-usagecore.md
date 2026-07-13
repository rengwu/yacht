---
type: task
blocked_by: []
assets: [Sources/UsageCore/Model.swift, Sources/UsageCore/SnapshotReader.swift, Sources/UsageCore/ViewModel.swift, Tests/UsageCoreTests/DisplayTests.swift]
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

## Answer

Built and green, 2026-07-13. `swift run UsageCoreTests`: **80/80 pass** (21 installer +
59 display/reader), plus the tap's 21 — all three seams now have suites.

**The scaffold.** Three targets: `UsageCore` (library, no AppKit), `ClaudeUsage`
(executable — placeholder main until the UI ticket), `UsageCoreTests` (executable test
runner). `build.sh` rewritten: `swift build -c release` → `.app` bundle with the
`LSUIElement` plist → `codesign --force --deep --sign -`. Pipeline proven end to end:
the bundle launches, and `codesign -dv` now shows `Info.plist entries=8` and
`Sealed Resources version=2` — **the seal the handoff said was missing is in place**,
which is the precondition for the launch-at-login ticket's SMAppService experiment.

**The core.** `Model.swift` (Account = label + configDir; Snapshot; LimitWindow;
AppSettings with **derived critical = midpoint of warn and 100**, so the pair cannot be
mis-ordered; AccountState as the gathered render input). `SnapshotReader.swift` (malformed /
non-object / missing `updated_at` → nil — unreadable never becomes 0%). `ViewModel.swift`:
the single pure `render(accounts:settings:now:) → ViewModel` — every string, tone, bar,
countdown for menu bar and dropdown; time injected everywhere; semantic `Tone` mapped to
colour only by the UI.

**Display-rule choices made within the spec's decisions** (wording, not policy):
never-reported notes per tap status ("waiting for a session…", "tap not installed —
install it from Settings", "another status line is configured — see Settings"); past-reset
detail "reset passed — empty until a session confirms"; a note also shows when a snapshot
exists but the tap has gone missing (frozen data is explained, not silent).

Covered at the seam: absent/malformed/partial snapshots; reset boundary before/at/after
(number, bar, and tone all flip); dash ≠ zero; warn and derived-critical exactly on
threshold, per account independently; rounding and bar glyphs at extremes; countdown and
staleness across unit boundaries; registration ordering; zero accounts.
