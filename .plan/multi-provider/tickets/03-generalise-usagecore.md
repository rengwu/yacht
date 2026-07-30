---
type: task
blocked_by: []
claimed_by: s8b128be56303
claimed_at: 2026-07-30T05:47:06Z
---

# Generalise UsageCore from two fixed windows to N rows

## Question

AFK build ticket — no product decisions, all settled by [`spec.md`](../spec.md) decision 2.
This is the load-bearing refactor and the riskiest one in the effort: it rewrites the app's
most-tested seam.

Deliver:

1. **`Snapshot` becomes N rows** of `{label, used, limit, resetsAt}`, replacing the fixed
   `fiveHour`/`sevenDay` pair in `Sources/UsageCore/Model.swift`. Rows carry **absolute
   counts**, not percentages — Kimi counts, Claude reports percentages, and `{used, limit}`
   holds both. Percentage is derived at render time, where `effectivePercentage`'s
   past-its-reset rule already lives.
2. **The Claude reader maps onto it** — `SnapshotReader` keeps parsing the same tap snapshot and
   produces two rows. Claude's `rate_limits` gives percentages with no denominator, so decide
   and document how a percentage-only source expresses `{used, limit}` (a 0–100 scale is the
   obvious answer; say so in code rather than leaving it implicit).
3. **`render` takes rows**, with 5-hour primary and weekly secondary selected by the hardcoded
   rule in decision 3 — *not* a user setting, and not "worst row wins".
4. **Claude's rendered output does not change.** This is the acceptance bar for the whole
   ticket: the existing display-seam suite in `Tests/UsageCoreTests/DisplayTests.swift` must pass
   with its expectations **unedited**, except where a test asserts the shape of `Snapshot` itself.
   Any change to a rendered string is a regression, not a migration.
5. **Config compatibility.** `AppConfig` decoding already tolerates missing keys so an older
   settings file loses only what it lacks. Confirm a v0.1.4 config still loads with every
   account intact — an account list silently emptied by a strict decode is the worst outcome
   this refactor could produce.

Note: `Tests/` runs via `swift run UsageCoreTests` — there is no XCTest on this machine (see
[`../../usage-menubar/tickets/01-the-tap.md`](../../usage-menubar/tickets/01-the-tap.md)).

## Answer

Done. `Snapshot` is N rows of absolute counts, the Claude reader produces two of them, the bar
picks its two figures by window, and **every one of the 130 pre-existing assertions still passes
with its expected strings untouched** — 145 now, the 15 added being 6 new reader assertions and
9 for config compatibility. Claude's rendered output is byte-identical.

### The model — identity is separate from the label

Decision 2 names the row `{label, used, limit, resetsAt}`, but the spec's own first trap says a
row's identity *is* its window and "labels are derived, never read". Those pull in opposite
directions if `label` is the only field, so the row carries both: a `UsageWindow` enum
(`.fiveHour` / `.weekly`) that is the identity and the only thing the display rule may key on,
and a `label` string that is display-only, defaulting to the window's shared label. Neither
provider sends a label — Claude names its windows with the JSON keys `five_hour`/`seven_day`,
Kimi identifies one by `window: {duration: 300, timeUnit: TIME_UNIT_MINUTE}` and the other by
being the top-level `usage` object with no window at all — so each adapter maps its own shape
onto the enum and the label follows from there.

`Snapshot.row(_:)` looks a row up by window. `rows` stays in the adapter's significance order
(5-hour, then weekly) because that is the order the dropdown lists them in, and the dropdown now
renders *every* row the provider reported rather than two hardcoded slots. Ordering is
deliberately not how the bar picks its figure — see below.

`percentage` is derived on the row, unclamped, guarded against a non-positive `limit`. That
guard is a floor rather than a state the UI distinguishes: no adapter can produce one, but a NaN
would reach `Int(_:)` in the formatter and trap the app.

### A percentage-only source is a count out of 100

Claude's `rate_limits` reports a percentage with no denominator, so `SnapshotReader` supplies
the one a percentage implies — `percentageScale = 100`, stated as a named constant with the
reasoning next to it rather than left implicit at the call site. `used` is the reported figure
verbatim, fraction and overshoot included (the server does report past 100).

This is not Claude being translated into Kimi's units. Ticket [`01`](./01-confirm-payload.md)
established that Kimi's `limit` is *also* 100, and for the same underlying reason: it is a
percentage denominator, not a request count. The two providers genuinely coincide on a 0–100
scale.

### This clears the map's "count-based row" question

[`../map.md`](../map.md) carried *how a count-based row renders* as unspecified, pending this
ticket: `{pct}`/`{bar}` have no way to say a raw count, and a weekly quota of 100 might read
better as one. **It needs no new template tokens, and a count rendering would be wrong.**
Because Kimi's `limit` is 100, `used / limit * 100 == used` — the percentage *is* the count, and
`{pct}` and `{bar}` already render Kimi correctly. Going the other way and showing "73 left"
would actively mislead: the spec's trap list records the underlying unit as coarser than a turn
(~4.2 turns per unit), so a bare count invites reading it as requests remaining. The question
dissolves rather than being deferred — not because the row model abstracted the difference away,
but because there was only ever one scale.

### The bar's two figures are hardcoded, and not by row order

`barWindow` / `barSecondaryWindow` are file-private constants keyed on `UsageWindow`, so a
snapshot carrying only a weekly row reads as "no 5-hour data" rather than promoting whatever row
happens to be first. That is the point of keying on identity instead of position: neither "row 0
wins" nor "worst row wins" is the rule. Decision 3, written out at the constants so the next
reader does not re-derive it.

### Config compatibility — confirmed, and now pinned by a test

`AppConfig` and `Account` are **byte-identical to `v0.1.4`** (verified with `git show
v0.1.4:...`), and `Snapshot` was never persisted, so the refactor could not have reached the
settings file. But "could not have" is the kind of claim that rots, so
`Tests/UsageCoreTests/ConfigTests.swift` now decodes a complete v0.1.4-shaped config — all nine
keys, `configDir` as a bare path, **two** accounts — and asserts every account survives in
order alongside all nine settings. Two accounts rather than one because the failure being
guarded is not a wrong setting but a silently emptied account list, which leaves the app looking
freshly installed rather than broken.

### For ticket 04

- The Kimi adapter's whole job at this seam is producing `[UsageRow]`: synthesise the 5-hour row
  from `limits[0]` and the weekly from top-level `usage`, tagging each with its `UsageWindow`.
  Nothing downstream needs to know which provider a row came from.
- Read `used` when present, else `limit - remaining`, treating every absent numeric as `0` per
  ticket [`01`](./01-confirm-payload.md). Do not require `remaining`.
- `UsageRow.label` accepts an override that no adapter currently uses. It is there because
  decision 2 names `label` as a row field; if Kimi's windows want the same "5h"/"7d" that Claude
  uses — which is likely — the override stays unused and can be dropped.
