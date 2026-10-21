---
title: First-principles plan
updated: 2026-10-21
order: 1
---

# First-principles plan

## Current phase

The accepted design has been implemented locally in native Swift/AppKit. All eight Final boards were inspected through computer use. For that implementation, the user treated the canvas as a mockup and delegated discretion while keeping the app native. See [native implementation and validation](native-implementation.md) for the current build, tested scope, and limits.

The Accounts table refinement is implemented in AppKit. The user selected compact layout A and [approved the refined review](journal/2026-10-20-grill-21c6d8e7-5273-49e5-9839-1436d77ca537.md): “yup this is nice. go for it”. The follow-up Developer Tools screenshot reinforces simplicity and `rule-lean`: use the grouped list as a guide, without overfitting its appearance. The result keeps plain single-line rows, native table headers and separators, an integrated +/− footer with the selected folder, and a label editor that grows with its contents.

## Accepted direction

These requirements come from the user's instructions and [round 1 answers](journal/2026-10-19-grill-8ef2fa34-9d14-4577-827c-f7a1b51f04f7.md):

- Primary job: answer how much usage each account has left and when its limits reset.
- Optimize the first version for the user's own workflow.
- Minimal UI and low resource use are both hard constraints; numerical budgets remain open.
- Native Swift. SwiftUI is acceptable if the app remains minimal; this does not require SwiftUI or accept the rejected layout.
- Menu bar dropdown and settings only. A dashboard or separate account-detail window is outside the accepted surface scope.
- Four to eight accounts should be comfortable to monitor.
- Initial providers: Claude, Codex, Kimi, and Grok.
- Use jstack's wiki, plan, and grill-form workflows for this project.
- Remove only the rejected redesign edits and preserve earlier work, including the pre-existing Grok implementation.

The [round 2 answers](journal/2026-10-19-grill-b89a23b6-c6c3-4fbb-934f-22325c1fb909.md) establish:

- Closed menu bar: customizable, supporting short usage figures for each enabled account. This replaces the recommendation to show only one selected account. Round 3 specifies one user-chosen quota window per account.
- Percentage convention: remaining versus used is a setting. Round 4 sets the default to used.
- Dropdown: show all reported quota windows for every account without requiring account expansion. Do not invent missing windows.
- Account organization: one flat list in an order the user controls, rather than provider groups or automatic sorting.
- Visual structure: initially open for alternatives; the later mockup review selected layout C, described below.
- Reset presentation is user-selectable. Round 3 resolves the earlier ambiguity: offer countdown or exact time, without a combined mode.
- Freshness: adaptive background updates plus refresh on opening. Exact polling intervals and resource budgets remain implementation questions.
- Failed refresh with a previous reading: preserve that reading with a visible stale marker and age.
- After a cached reset time passes: show an unknown percentage and reset-passed/awaiting-update state until new data arrives.
- No usage notifications; indicators remain visual.

The [round 3 answers](journal/2026-10-20-grill-6f40375f-6228-48e1-972d-055c180fcfbe.md) complete the pre-mockup behavior discussion:

- Each account's menu bar figure uses one quota window chosen by the user. Multiple figures for different windows of the same account are not requested.
- Entry identity is customizable: an editable per-entry label and the ability to enable the provider icon per entry. Do not impose a mandatory provider icon or email identity. The original implementation is a reference for customization, not an approved layout. *Revised in mockup round 2 review:* icons are all-or-none, not per entry (see [Mockup review](#mockup-review)).
- Account setup must support multiple accounts from the same provider. The user asked for the cleanest implementation under jstack's `rule-lean`, rather than selecting an onboarding option; see the recommendation below.
- The dropdown monitors usage, with refresh and settings. Keep the scope simple and add no invented features.
- Reset-display choices are countdown or exact time, with no combined mode.
- Apply jstack's `rule-lean` to relevant implementation decisions.

The [round 4 answers](journal/2026-10-20-grill-1664761b-a44e-468f-a6d4-1ce37f6b63ad.md) settle choices raised by the mockups:

- Provider icons come from Lobe Icons, with letter tiles as the fallback for a provider without a mark.
- One "Show accounts as: Icons / Labels" setting controls both the menu bar and the dropdown. Icons gives menu bar style 2 (icon + percentage) and an icon beside each dropdown label. Labels gives style 4 (label over percentage) and labels only.
- Defaults: show accounts as labels; percentages as used; resets as a countdown.
- A stale figure in the menu bar is dimmed only. The dropdown keeps the clock glyph with the age.
- Meter colour uses configurable thresholds (details in round 5).
- The dropdown keeps "Quit Yacht".
- Local-profile account setup is accepted (below).

The [round 5 answers](journal/2026-10-20-grill-94e43e24-0344-4592-9f1e-8eee6e7b6cb6.md) complete the visual states:

- **Reset passed:** an hourglass glyph replaces the percentage and the meter becomes a dashed track. The glyph is neutral grey. Natively this is the SF Symbol `hourglass`.
- **Thresholds:** keep the existing model. One warning threshold is set by a slider (50–95% used, default 75%); critical is derived halfway to 100%, so the two can never be out of order. Thresholds are stored as usage used, and the Settings label follows the chosen percentage convention.
- **Colour reach:** threshold colours apply to both the dropdown meters and the menu bar figures. In icons mode the icon stays monochrome and only the percentage is coloured.
- **Precedence:** a warning colour overrides stale dimming (the existing behaviour). Below the threshold, a stale reading still dims.
- **Colours:** fixed system orange for warning and red for critical, which adapt to light mode, dark mode, and accessibility contrast.
- **Normal meters:** neutral text colour, so colour appears only when something needs attention.

### Native build review

The user's follow-up review requests muted separators between account groups and immediate editing when clicking a label field. It also removes the elapsed stale age (such as `19m`) from the dropdown header; the clock glyph remains. This supersedes the earlier clock-plus-age presentation. In the two-line menu bar style, the figure moves down one point (two Retina pixels) to increase the gap beneath its label.

The next review replaces the reset-passed hourglass with a muted dash in both the menu bar and dropdown. Expired/no-data accounts should look similar to awaiting-refresh accounts: use the same dashed meter, dash alignment, and row height. With no reported windows, the dropdown uses an unlabelled placeholder row rather than adding a fabricated window to the model. Hover help retains the specific cause.

### Accounts table refinement

**0.2.0 is released.** After merging PR #1, the user instructed “i merged. lets release,” resolving the pending publication decision. The tag workflow and downloaded-asset checks passed; see the [publication record](verification/runs/2026-10-21-v0.2.0-publication.md). The earlier [release preflight](verification/runs/2026-10-21-v0.2.0-preflight.md) retains its scope and limits: fresh Kimi verification remains untested because the saved CLI sessions were expired.

The [table review](journal/2026-10-20-grill-38baa3c1-ee26-4927-a545-81600f42bc14.md) selects compact layout A over the version showing every folder path. Keep the selected folder in the bottom bar, native row selection, reordering, provider identity, and each account's menu-bar window choice.

The label editor starts at a small minimum width and grows with the entered text, instead of filling the Account column. The native implementation uses 72 pt as the minimum and caps growth at the column boundary; these measurements are assistant-chosen implementation details, not separate user requirements. Keep immediate first-click editing and show the field border only while editing.

The grouped lists in macOS **Input Monitoring** and **Developer Tools** guide the rounded container, uniform row backgrounds, inset separators, and integrated add/remove footer. The user approved the refinement, then explicitly asked not to overcomplicate or overfit it. The later instruction to follow Apple’s native guidelines takes precedence over matching screenshot details. Yacht uses NSTableView’s standard headers, separators, selection, and column resizing, plus semantic system colors. Custom header/separator drawing was removed, and scrollbars follow the system preference. The drag handles stay quietly visible; there is no hover-specific behavior or custom light/dark palette. The screenshots do not establish which public control or internal implementation System Settings uses.

The selected Claude account's existing Install/Replace Tap action remains available in the footer when needed. Up to six rows are visible before scrolling. The window fits the settings content and adjusts when accounts are added or removed, leaving a normal bottom margin.

Follow-up feedback adds breathing room inside the column headings and removes the stray divider at the group's trailing edge. Header titles have an 8 pt text inset; AppKit still renders the header, handles column resizing, and supplies its appearance. The corner above the scrollbar uses a matching native header view.

The user tried AppKit's gap feedback for reordering, then rejected how it felt. The table returns to AppKit's default insertion indicator. Account order is still saved only when the row is dropped; the row alignment fix remains.

The submitted preview state records interaction with fictional sample accounts. Its removal of Codex and addition of Client are not instructions to change real account registrations.

## Account setup

**Accepted in round 4** (previously a recommendation): retain local profile registration. Choose the provider, select an existing account/config folder, and assign a label. Use a different folder for each account from the same provider. Retain existing discovery as an optional shortcut into the same registration path.

This is the simplest complete fit for the established monitoring task because the current account model and provider adapters already use local folders. Reusing that path preserves multiple accounts without introducing a new credential lifecycle. The provider's existing tools remain responsible for signing in and preparing each profile. Selecting a folder does not itself create or authenticate an account.

Observed in the current source:

- `Sources/UsageCore/Model.swift` stores provider, label, and config directory per account. Separate local profiles can belong to the same provider.
- `Sources/Yacht/SettingsWindowController.swift` already offers provider selection and a native folder picker, and registers discovered folders through the same function.
- `Sources/UsageCore/AppConfig.swift` discovers the standard profile folders for all four providers: `.claude*`, `.codex*`, `.kimi-code*`, and `.grok*` directories under the user's home. Codex and Kimi discovery were added after the user's fresh-start tests exposed the missing paths. Kimi also lists legacy `.kimi*` folders containing `credentials/kimi-code.json`, after the current Code homes; this finds older signed-in profiles without including unrelated folders such as `.kimi-webbridge`. Discovery is a convenience, not proof of valid credentials; the manual path supports other/custom locations.

Following `rule-lean`, reuse that implementation where it fits rather than expanding discovery or sign-in scope for hypothetical needs. Do not assume universal provider discovery.

## Mockup review

The mockups are on a private design canvas: <https://claude.ai/artifact/E9ZV6c1fjk6HKqyCJ9pMSM>. Each round has its own page. All data on it is fictional. Round 3 uses real provider marks from Lobe Icons and Hugeicons (both MIT-licensed; the logos remain their owners' trademarks).

Round 1 feedback (2026-10-20):

- **Closed menu bar:** the user liked style 2 (provider icon + percentage) and style 4 (two lines: label over value). Label + percentage and icon + label + percentage were not chosen. No final style has been selected.
- **Dropdown:** accepted direction is layout C. Each account name is followed by one row per reported window, with a meter, percentage, and reset. The plain menu (A) and compact table (B) were not chosen.
- **Data states:** the user does not want many words in the UI. Indicators should be compact icons, dots, or glyphs.
- **Settings:** the user said the Settings layout "seems okay". That layout has an account list with per-entry icon toggle, label, provider, and menu bar window. It also has percentage and reset-time controls and launch at login. The add-account sheet appeared in the same review screenshot but was not singled out, so the local-profile recommendation still awaits explicit approval.

Round 2 proposals, not yet accepted:

- A merged menu bar style: icon or label over the value, chosen by the per-entry icon setting. It fits eight accounts beside the notch.
- Layout C with fewer words: bare percentages and reset values, without "left" or "in". The words "left" and "used" come from the setting.
- Glyph states: stale is dimmed, with a clock glyph and age. Reset passed shows `?` with an awaiting-update glyph. No data shows a dash and no windows.

Round 2 feedback (2026-10-20):

- **Menu bar:** style 2 (icons + percentage) and style 4 (labels over values) are both good. Never merge different styles; the merged style is rejected.
- **No mixing:** either every entry shows an icon or none does. This replaces the round 3 per-entry icon toggle, because a bar that mixes icons and labels reads as inconsistent.
- **Provider icons:** use real provider marks, with letter tiles kept as the fallback. Lucide has none. Hugeicons (free) has Claude, ChatGPT, Grok, and Kimi but no Codex. Lobe Icons has all four.
- **Dropdown:** layout C with fewer words looks great, subject to the all-or-none icon rule.
- **Reset passed:** the refresh-arrow glyph is rejected because it can be confused with a refresh button. The `?` glyph is rejected in favour of a better glyph.

Round 3 proposals and their outcome in interview round 4:

- A single "Show accounts as: Icons / Labels" setting. **Accepted**, defaulting to labels.
- Icon source. **Lobe Icons accepted** over Hugeicons, with letter tiles as the fallback.
- Reset-passed glyph options: hourglass, three dots, or a dashed ring. **Hourglass accepted** in interview round 5. The stale clock and the no-data dash are unchanged.

## Superseded proposal

The assistant implemented a SwiftUI dashboard, usage-card popover, sidebar settings, visual branding, and a preview app before eliciting requirements. On 2026-10-20 the user rejected that direction and requested a first-principles discussion. None of those design choices are accepted requirements.

## Cleanup baseline (before native implementation)

- The checked-out branch is `redesign/native-dashboard`.
- The rejected redesign source, tests, screenshots, and preview build have been removed from the working tree. The preview process was stopped.
- Grok support was already present as uncommitted work before the redesign began.
- At the cleanup checkpoint, the tracked diff matched the initial scope and size: 10 files, 228 insertions, 35 deletions. The pre-existing Grok adapter, Grok tests, model, rendering, and other provider/config tests were verified unchanged by content hashes; restored README, config, and settings files also matched their pre-redesign Git blob hashes. The subsequent native implementation extends this baseline and is also uncommitted.
- A recovery copy of the rejected edits is outside the project at `/var/folders/00/h_k67s0j5dq0qvg6ylqysk2w0000gn/T/yacht-rejected-redesign-q96kmw06`. It is not an active implementation or an accepted design.
- The new project wiki was retained as requested. No replacement interface was implemented during the interview; native implementation began after the design review.
- Cleanup validation: `swift build` succeeded; `swift run UsageCoreTests` returned 405 passes and zero failures; `./build.sh` rebuilt the earlier app successfully. This verifies the cleanup, not a replacement design.

## Design handoff

The [design handoff](design-handoff.md) is the entry point for implementation. It is the build specification for the accepted design and links back here for decisions. The final mockups are on the canvas's **Final** page. The earlier [mockup handoff](mockup-handoff.md) is complete and kept as history.

## Implementation decisions

The user explicitly delegated discretion on 2026-10-20 while reiterating native implementation. This supersedes the handoff's request to seek separate approval for routine implementation choices:

- AppKit throughout: one system status item and NSMenu, native text/image/meter views, NSTableView for account reordering, standard controls, and an Add Account sheet.
- Bundle four preconverted PDF vectors and the Lobe MIT notice. SwiftPM and `build.sh` include them; there is no network icon loading or runtime SVG dependency.
- Retain existing adaptive provider schedules (roughly 60 seconds active / 15 minutes idle), with refresh on opening and manual refresh. Replace the fixed five-second redraw with a single timer for the next minute or quota reset. Provider callbacks still update immediately.
- Keep system semantic colors. Exact spacing, the 320 pt dropdown width, standard menu behavior, and the sheet layout follow native controls rather than reproducing browser CSS.
- Keep existing account registrations, provider integrations, executable overrides, thresholds, and legacy configuration fields. The new interface uses structured presentation rather than the old text templates.
- Keep the last in-process Claude snapshot when a subsequent file read fails, visibly marked stale. The established pulled-provider caches remain unchanged.

No measured live-provider CPU/memory/wakeup guarantee is claimed. Offline UI measurements and remaining verification limits belong in the implementation page.

When figures exceed the space beside the notch, macOS may hide the status item. Reopening Yacht opens Settings, where the accepted per-account "Off" option reduces its width; no automatic truncation has been requested. Provider setup requirements must be verified before changing the existing integration paths.

## Decision history

- 2026-10-20: User rejected the dashboard redesign, reiterated lightweight/minimal/native Swift, and requested a reset through grill-form.
- 2026-10-20: User identified `../jstack` as the skill source and explicitly adopted wiki, plan, and grill-form for this project.
- 2026-10-20: Round 1 settled the primary usage/reset job, personal audience, resource/UI constraints, SwiftUI permissibility, dropdown-and-settings boundary, four-to-eight-account target, four-provider scope, and selective cleanup. The rejected redesign was removed within that boundary.
- 2026-10-20: Round 2 settled customizable multi-account menu bar figures, selectable percentage convention, all reported windows, a user-ordered flat account list, adaptive updates, explicit stale/expired states, and no notifications. The user requested rough layout alternatives and plans to hand mockup design to another session. A short final round addresses behavior needed for those mockups.
- 2026-10-20: Round 3 settled one chosen menu bar window per account, per-entry label/icon customization, monitoring-only actions, and countdown-or-exact reset modes. The user invoked `rule-lean` and requested setup advice while preserving same-provider multi-account support. Source review supports recommending the existing local-profile registration path; that recommendation remains open for mockup review. The handoff is ready.
- 2026-10-20: Mockup round 1 reviewed. Menu bar narrowed to icon + percentage and two-line styles; dropdown layout C accepted as the direction; Settings layout judged okay; state indicators should use glyphs rather than words. Round 2 mockups were added for review.
- 2026-10-20: Mockup round 2 reviewed. Menu bar styles 2 and 4 are both accepted, with no merging and no mixing of icons and labels; the per-entry icon toggle is replaced by all-or-none. Real provider marks are requested, with letter fallback. The refresh-arrow and `?` reset-passed glyphs are rejected. Round 3 mockups were added for review.
- 2026-10-20: Interview round 4 settled Lobe Icons, one icons-or-labels setting, the defaults (labels, used, countdown), dim-only stale figures in the menu bar, configurable colour thresholds, keeping Quit, and local-profile account setup. The reset-passed glyph is held until the options can be shown visually.
- 2026-10-20: Interview round 5 accepted the hourglass glyph for a passed reset. It kept the existing single warning threshold with critical derived, applied threshold colours to meters and menu bar figures, and let warnings override stale dimming. It also fixed system orange and red as the colours and made normal meters neutral. Design questions are closed.
- 2026-10-20: A final mockup was added to the canvas's Final page, and the [design handoff](design-handoff.md) was written for another agent to implement. Assistant-chosen details are marked there as not separately reviewed: the grey stale clock (orange is reserved for warnings), sizes, and opacities.
- 2026-10-20: User supplied the exact Final page, described it as a mockup, delegated discretion, and required native implementation. All eight boards were visually inspected. The design was implemented with AppKit, preserving provider work; see the implementation page for validation.
- 2026-10-20: User reopened the Accounts table design, supplied the macOS Sound device table as a reference, and requested a couple of mock redesigns through the updated jstack grill-form. Two interactive studies were created and visually inspected in the default browser. Feedback is pending; no app code or registrations changed for this review.
- 2026-10-20: Table review submitted: A selected, with a content-sized label editor and the Input Monitoring grouped table as the specific reference. Both attached images were inspected. A revised mockup was prepared, preserving the user's fictional preview state; native app implementation remains pending.
- 2026-10-21: Refined table approved for implementation. The user reinforced `rule-lean` with the Developer Tools list as a simplicity reference. The compact AppKit table is implemented. A final instruction prioritizes Apple’s native guidelines over custom styling; validation and remaining limits are recorded on the native implementation page.
- 2026-10-21: User merged PR #1 and directly authorized release, superseding the pending release-choice form. Published v0.2.0 from merged commit `e3b7293`. The user also supplied a screenshot for the README; it was added unchanged and pushed separately from the release tag.
