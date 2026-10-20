---
title: Design handoff
updated: 2026-10-21
order: 2
---

# Design handoff

Start here to implement the accepted design. This page is the build specification. [The plan](plan.md) remains the authority for decisions, their reasons and their history. Where the two differ, the plan wins; report the difference rather than guessing.

Implementation update: the user subsequently delegated discretion while requiring a native app. The [plan](plan.md#implementation-decisions) records the AppKit and resource choices; [native implementation](native-implementation.md) records validation. Sizes and browser styling here are visual guidance, not pixel-exact native requirements.

The final mockups are on the **Final** page of the design canvas: <https://claude.ai/artifact/E9ZV6c1fjk6HKqyCJ9pMSM>. The canvas is private to the owner's account. If you cannot open it, ask the user to share it; this page is written so the build does not depend on it. All accounts, percentages and times on the canvas are fictional fixture data.

## Scope

Build exactly four surfaces: the menu bar status item, its dropdown, the Settings window, and the Add Account sheet. There is no dashboard, account-detail window, notification, or onboarding flow. The dropdown's only actions are Refresh, Settings… and Quit Yacht.

The existing code is a factual reference, not a layout to keep. Apply `../jstack` `rule-lean`. Reuse the account model, provider adapters, threshold logic and folder registration where they fit, rather than rebuilding them.

## Menu bar

One status item shows one entry per account, in the user's order. Accounts whose menu bar window is set to Off are left out. Each entry shows the window the user chose for that account.

| Setting | Entry layout |
| --- | --- |
| Show accounts as: **Labels** (default) | Two lines, centred: label at about 9 pt regular, over the percentage at about 11 pt semibold |
| Show accounts as: **Icons** | Provider mark (14 pt monochrome template image), then the percentage at 13 pt |

- Entries are about 10 pt apart.
- Never mix icons and labels within the bar, and never combine the two layouts.
- The percentage follows the Percentages setting: used (default) or remaining.
- Threshold colour applies to the percentage only. In Icons mode the mark stays monochrome.
- When the item is too wide for the space beside the notch, macOS hides it. The remedy is setting some accounts' menu bar window to Off. No automatic truncation has been requested.

## Dropdown

This is layout C, with no section headers, grouping or expansion. Accounts appear in the user's order. Each block is:

1. **Header:** the provider mark (Icons mode only), then the label at 13 pt semibold. On the right, a stale reading shows a clock glyph in secondary colour, without elapsed-time text (revised during native build review).
2. **One row per window the provider reports,** in the adapter's order (5h before Weekly). Do not invent missing windows. Columns:
   - window name in secondary text, about 12 pt;
   - a meter about 4 pt high with rounded ends, filled to the displayed percentage;
   - the percentage, right-aligned, with no "left" or "used" suffix;
   - the reset value, right-aligned, in secondary text.

Reset values are either a countdown (`2h 14m`, `3d 4h`, `22h 0m`) or an exact time (`11:55` today, `Fri 13:40` on another day), chosen by the Reset times setting. The two are never combined.

If there is no reading, show one unlabelled placeholder row with a muted dashed meter and a dash in the percentage column. This gives expired credentials and awaiting-refresh states the same visual structure without claiming a quota window or reset time that has not been reported.

Muted native separators divide the account groups. After the accounts come a separator and **Refresh** (⌘R), **Settings…** (⌘,) and **Quit Yacht** (⌘Q). The mockup's menu is about 300 pt wide.

## States and colours

The thresholds apply to usage **used**, whichever convention is displayed. The warning threshold is the Settings value (default 75%). Critical is derived as `warn + (100 − warn) / 2`, so 87.5% by default. This matches `AppSettings.criticalThreshold` in `Sources/UsageCore/Model.swift` and `tone`/`barTone` in `Sources/UsageCore/ViewModel.swift`.

| State | Trigger | Menu bar entry | Dropdown |
| --- | --- | --- | --- |
| Normal | Below the warning threshold | Default text colour | Neutral meter (`labelColor`) and default text |
| Warning | At or above the warning threshold | Percentage in `systemOrange` | Meter and percentage in `systemOrange` |
| Critical | At or above the critical threshold | Percentage in `systemRed` | Meter and percentage in `systemRed` |
| Stale | Refresh failed; previous reading kept | Dimmed (about 40% opacity) | Clock glyph in the header; rows dimmed (about 50%) |
| Stale + threshold | Stale and at or above warning | Colour wins; not dimmed | Coloured rows are not dimmed; the clock still shows |
| Reset passed | The cached reset time has passed and no new data has arrived | Muted `—` replaces the percentage | Muted `—` in the percentage column; dashed meter track; no reset value |
| No data | No reading, including expired credentials without a saved reading | Muted `—` | Unlabelled placeholder row with the same dashed meter and muted `—`; no reset value |

Use the SF Symbol `clock` for the stale marker. Use system colours, not fixed hex values, so light mode, dark mode and Increase Contrast adapt automatically. The canvas approximates them.

## Settings window

Use one window with three grouped sections:

- **Accounts:** a compact, single-line reorderable table (layout A, selected in the [table review](journal/2026-10-20-grill-38baa3c1-ee26-4927-a545-81600f42bc14.md) and [approved after refinement](journal/2026-10-20-grill-21c6d8e7-5273-49e5-9839-1436d77ca537.md)). This is implemented in AppKit and supersedes the earlier two-line rows. Dragging sets the order of both the dropdown and the menu bar. Each row has:
  - a drag handle and the provider mark;
  - an editable label that looks like plain text when idle. On first click, its editor starts at a small minimum width and grows with the text, capped at the available Account column;
  - the provider name;
  - a **Menu bar** pop-up listing the windows that provider reports, plus **Off**.

  Show the selected account's folder in the bottom bar. `+` opens the Add Account sheet and `−` removes the selected account. The selected Claude account's Install/Replace Tap action also appears here when needed. Use a rounded group, uniform row backgrounds, and an integrated footer, guided by macOS Input Monitoring and Developer Tools. The user’s final instruction prioritizes Apple’s native guidelines over matching screenshot details: use standard AppKit table headers, separators, selection, resizable columns, and system colors. See [Accounts table refinement](plan.md#accounts-table-refinement).
- **Display:**
  - **Show accounts as:** Icons / **Labels**.
  - **Percentages:** Remaining / **Used**.
  - **Reset times:** **Countdown** / Exact time.
  - **Warning threshold:** a slider from 50 to 95, default 75. Its caption reads "orange at 75%, red at 87% used". With remaining selected, it reads in that convention (for example, "orange at 25% left").
  - **Menu bar preview** showing the current figures.
- **General:** Launch at login.

The existing `Sources/Yacht/SettingsWindowController.swift` already has the threshold slider, its caption, the folder picker, and Launch at login.

## Add Account sheet

This is the accepted local-profile flow. The fields are:

- **Provider:** pop-up.
- **Folder:** field plus **Choose…**.
- **Label:** field.

Under the fields is one line of help: choose the folder the provider's own CLI already signs in to; Yacht only reads it; each account of the same provider uses its own folder.

A **Found on this Mac** list offers discovered folders. Each shows **Use**, or "Added as <label>" if it is already registered. The buttons are **Cancel** and **Add Account** (default).

Claude accounts then offer Install Tap, as the current app does. Selecting a folder does not create or authenticate an account. See [Account setup](plan.md#account-setup).

## Defaults

| Setting | Default | Status |
| --- | --- | --- |
| Show accounts as | Labels | Accepted (round 4) |
| Percentages | Used | Accepted (round 4) |
| Reset times | Countdown | Accepted (round 4) |
| Warning threshold | 75% used | Accepted (round 5; existing value) |
| Menu bar window per account | The adapter's declared primary: 5h for Claude and Kimi, weekly for Codex and Grok | Existing behaviour; not separately reviewed |
| Launch at login | Existing behaviour | Not separately reviewed |

## Provider marks

Use [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT), package `@lobehub/icons-static-svg` 1.95.1. The files are `icons/claude.svg`, `icons/codex.svg`, `icons/grok.svg` and `icons/kimi.svg`, for example <https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.95.1/icons/claude.svg>. Each is a single-colour 24×24 path. The logos remain their owners' trademarks; keep the MIT notice with the bundled files.

Render them as monochrome template images so they tint with the menu bar and menu. A provider without a mark falls back to a letter tile: a rounded 14 pt square with the provider's initial. All four current providers have marks.

## Implementation planning at handoff

These were left for implementation planning at handoff. The user's later discretion instruction supersedes the request for another approval round; current decisions are in the plan:

- **UI framework:** AppKit or SwiftUI. SwiftUI is allowed if the app stays minimal.
- **Budgets:** numerical CPU, memory, wake-up and polling budgets. Updates are adaptive in the background, plus a refresh when the dropdown opens.
- **Icon loading:** how to bundle and load the marks. It must suit the SwiftPM and `build.sh` build (no asset catalogue) and macOS 13.
- **Contrast:** check `systemOrange` text in a light menu bar and with Increase Contrast.

The assistant chose these details in the final mockup without a separate review. Keep them unless the user says otherwise:

- the grey stale clock (orange is reserved for warnings);
- the font sizes, spacing, menu width and dimming opacities above;
- the dashed track pattern.

The keyboard shortcuts match the current app (`Sources/Yacht/AppDelegate.swift`).

## Working tree

- The branch is `redesign/native-dashboard`. That name comes from a rejected attempt; it is not a design mandate.
- Earlier uncommitted work, including the Grok provider and its tests, must be preserved. Do not commit, push or discard anything without the user's approval.
- The rejected redesign's recovery copy (see [the plan](plan.md#cleanup-baseline-before-native-implementation)) is not a source for this build.
- Baseline checks: `swift build`, `swift run UsageCoreTests` (405 passing at cleanup) and `./build.sh`.
- Record implementation decisions in [the plan](plan.md), then rebuild and check the wiki with `node docs/wiki/_build.mjs` and `node docs/wiki/_build.mjs --check`.

## Starter prompt for the next session

> Read `docs/wiki/design-handoff.md`, `docs/wiki/plan.md`, and `docs/wiki/native-implementation.md`. Use `../jstack` plan, wiki and rule-lean. Continue the native AppKit implementation, respecting the accepted behavior and the user's delegated discretion on native details. Reuse existing models, adapters and threshold logic where they fit. Preserve existing uncommitted work, including Grok support; do not commit or install over another copy without instruction.
