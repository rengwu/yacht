---
title: Native implementation
updated: 2026-10-21
order: 3
---

# Native implementation

The [accepted design](design-handoff.md) is implemented in Swift/AppKit on the existing `redesign/native-dashboard` branch. The user delegated discretion while requiring native behavior. All eight boards on the [Final canvas page](https://claude.ai/artifact/E9ZV6c1fjk6HKqyCJ9pMSM#page-9539465e2f90) were inspected before implementation.

## What changed

- Native status button content supports labels over percentages or monochrome Lobe provider marks beside percentages. Build review moved the two-line style's figure down one point for a little more separation.
- A system NSMenu contains compact account views, muted separators between accounts, and standard Refresh, Settings, and Quit actions. It retains native keyboard handling and menu scrolling.
- Settings uses NSTableView with compact single-line rows in a rounded group, uniform system colors, standard headers and separators, resizable columns, and an integrated +/− footer. The footer shows the selected folder and the existing Install/Replace Tap action for Claude when needed. Folder identity remains stable for editing, reordering, and removal. Labels look plain when idle, edit on the first click, and grow with their contents up to the column boundary. One quota window or Off is chosen per account. Off only affects the menu bar.
- Native segmented controls select Icons/Labels, Used/Remaining, and Countdown/Exact time. The warning slider keeps the existing derived critical threshold.
- The Add Account sheet validates the folder and label, rejects duplicate folder registration, and offers discovered folders for all four providers. Codex discovery includes `~/.codex` and `.codex*` sibling directories; Kimi discovery includes `~/.kimi-code` and `.kimi-code*` siblings, then legacy `.kimi*` folders containing `credentials/kimi-code.json`. Discovery checks file presence without reading credentials. Selecting a folder does not authenticate an account.
- Passed reset times and missing readings share a muted dash and dashed meter. Missing readings use one unlabelled placeholder row; the model still reports no fabricated quota windows. Stale readings show a clock without elapsed-time text and retain the hover explanation; threshold colors win over dimming.
- Four small PDF vector marks are bundled with the MIT notice. Runtime needs no third-party UI framework, SVG parser, web view, or icon downloads.

The existing provider adapters, credential boundaries, caches, and launch-at-login mechanism remain. Old configuration fields and the core template-rendering API are retained for compatibility; the native UI uses the structured presentation in `UsagePresentation.swift`.

For immediate label editing, `AccountsTableView` approves editable descendant text fields in AppKit's [first-responder validation hook](https://developer.apple.com/documentation/appkit/nsresponder/validateproposedfirstresponder%28_%3Afor%3A%29). Other controls keep the standard table behavior.

The table follows Apple’s [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) guidance for descriptive headings and column resizing. The single-pane window follows [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) guidance for its title and disabled minimize/maximize actions. These guide the implementation without requiring a replica of System Settings.

## Validation

The newer [0.2.0 release preflight](verification/runs/2026-10-21-v0.2.0-preflight.md) records the versioned universal bundle, packaged-app smoke check, and current live-provider limits. Earlier checks below retain their original scope.

Commands:

```sh
swift build
swift run UsageCoreTests
./build.sh
node docs/wiki/_build.mjs
node docs/wiki/_build.mjs --check
```

The core suite currently reports **448 passed, zero failed**: the original 405 checks, 38 checks for native presentation and persistence, and five Codex/Kimi discovery regression checks. Coverage includes remaining/used semantics, warning precedence, reset boundaries, unknown values, selected/missing windows, Off, same-provider registration, duplicate rejection, reorder identity, rename preservation, and old-config decoding. Discovery checks cover default and sibling profiles, file exclusion, provider isolation, credential-bearing legacy Kimi profiles, unrelated Kimi folders, and an unreadable home.

The release bundle is `build/Yacht.app`, built and ad-hoc signed by `build.sh`. It has not replaced an installed copy. Publication is pending the final release decision.

Computer-use checks on the offline native demo:

- Settings and Add Account sheet rendered with system controls.
- Eight-account dropdown rendered normal, warning, critical, stale, past-reset, and missing-data fixtures.
- Icons/Labels, Remaining/Used, and Exact/Countdown controls changed their corresponding presentation.
- Off removed the selected status figure while retaining its account and windows in the dropdown.
- Refresh returned to the native window normally.
- Adding an additional local folder for the same provider completed and appeared in the account list.
- Editing a label and tabbing away updated the preview while preserving the account's folder identity.
- High-contrast light rendering kept the labels, meters, provider marks, and warning states legible.

Folder discovery, live authentication failures, tap installation, actual login registration, and live provider network behavior were not exercised in the demo. The provider regression tests passed. Full VoiceOver operation and manual drag gestures still need a real-user check; reorder identity is covered by core tests. Do not interpret offline UI validation as a live-provider performance guarantee.

On 2026-10-21, the refined Accounts table was checked in a separately identified offline demo bundle in dark and light appearances. First-click editing, short-to-long editor growth, committing and trimming a rename, updating its accessibility label, restoring an empty label, selected-folder updates, Off, removing a demo account, opening Add Account, and cancelling while preserving selection were verified. Automated drag attempts did not change the order, so native drag/drop remains unverified; the existing core reorder tests still pass. The simplification uses semantic system colors and removes hover-specific handle behavior. Following the user’s final direction, custom header and separator drawing were also removed in favor of standard AppKit rendering; column resizing and system scrollbar preferences are respected, and the Settings window does not minimize.

A follow-up alignment fix replaces hard-coded vertical frames and the label’s fixed height with center constraints and AppKit intrinsic control sizes. Idle and editing rows were visually checked in the offline demo.

Settings now fits its stack's measured height with a 20 pt bottom margin and resizes after account changes. Header titles use an 8 pt paragraph inset within the standard header cells. A narrow clip removes the final header divider, and a native header view fills the corner above the scrollbar. Header typography, colors, column resizing, and system scrollbar preferences remain AppKit-controlled. The release build passed; the eight-account demo and four-account normal window were visually checked, and the saved configuration hash was unchanged across the final restart.

AppKit's `.gap` drag feedback was tried and then removed after the user reported that it felt bad. Reordering uses the default insertion indicator again. The existing drop handler remains the only place that changes account order, so hovering or cancelling a drag does not save a new order. The alignment fix is retained.

The demo was stopped and the current repository release restarted in normal mode. Its Settings window was visually verified with the four saved accounts intact. The saved configuration's SHA-256 was unchanged through the demo checks; no real account registrations were edited.

A subsequent normal-mode setup check confirmed that Codex discovery lists `~/.codex` and marks an existing registration as “Added as codex.” Existing accounts were preserved during the rebuild.

Kimi discovery was subsequently wired into the same sheet and verified with filesystem fixtures for current and legacy profiles. Local metadata confirmed both `~/.kimi-code` and `~/.kimi` contain the credential file. The release rebuilt and restarted in normal mode, but the native UI tool reported no available window after relaunch, so the final Kimi sheet was not visually verified. Saved account registrations were not changed.

## Safe local inspection

```sh
open -n build/Yacht.app --args --demo
```

Demo mode uses fictional account fixtures entirely in memory, bypassing configuration loading/writing and provider startup. It disables tap installation and launch-at-login changes. The demo's Yacht menu includes **Usage Preview (Demo)** (⌘U), which opens the same native usage menu beside Settings even if the macOS menu bar is crowded.

Add `--light` or `--contrast` for per-app light/high-contrast-light inspection; these do not change the system preference. Normal launch uses the user's actual configuration and existing provider adapters.

## Resource behavior

The UI uses one timer, scheduled for the next minute boundary or pending reset. Provider completions refresh immediately. This replaces the old five-second redraw; existing provider adaptive schedules remain unchanged.

Initial profiling on macOS 27 found continuous AppKit status-item replicant snapshots when live text controls were attached to the status button: about 87% of one CPU core at idle. The status button now holds a cached image drawn with AppKit; it is regenerated when the presentation or effective appearance changes. The Settings preview shares the drawing code.

The same eight-account release demo with Settings open and high-contrast light appearance then recorded no CPU-time increase at `ps`'s 0.01-second resolution over 20 seconds. Its ending resident set was about 96 MiB. Evidence: [before](evidence/native-2026-10-20/idle-before.json) and [after](evidence/native-2026-10-20/idle-after.json). These short observations establish that the redraw loop stopped, not a zero-CPU or fixed-memory guarantee.

A [65-second sample of the initial native release](evidence/native-2026-10-20/idle-final.json), in system dark appearance with Settings open, included a minute-boundary update. It consumed 0.08 CPU seconds, averaging **0.123% of one core**, with an ending resident set of about **110 MiB**. The evidence records the tested binary's SHA-256.

Resource measurements are reported for the offline release process only. Live provider requests and Codex child processes require separate measurement with representative signed-in profiles.

## Working tree continuity

Before implementation, the working tree was copied to `/var/folders/00/h_k67s0j5dq0qvg6ylqysk2w0000gn/T/yacht-before-native-0youz3gy`. The earlier rejected redesign backup is separate and was not used as implementation source. Existing uncommitted Grok work is preserved.
