---
type: task
blocked_by: []
assets: [.plan/codex-provider/spec.md]
claimed_by: s2364dfca532d
claimed_at: 2026-07-31T16:55:56Z
---

# Bar keys on the provider's primary window

## Question

The menu bar's figure is hardcoded to the 5-hour window, justified by a comment stating that
*"both providers have exactly these two windows and nothing else."* Codex falsifies that: it
reports one window, the weekly, and a Codex account would therefore render as the no-data template
forever. Make the bar key on the row the **provider** calls primary, and teach the model to carry a
window it does not have a name for.

This ticket exists before any Codex code so that its proof stays legible: **Claude's rendered
output must be byte-identical afterwards.** Bundled with Codex work, a render regression and a
Codex bug become indistinguishable.

Implements [`spec.md`](../spec.md) decisions 3, 4 and 10.

## What to build

- **The bar's figure is the primary row**, declared by the adapter rather than hardcoded to a
  window. Claude and Kimi declare 5-hour — today's behaviour, unchanged. `{pct_7d}` renders `—`
  when the provider has no distinct second window.
- **`UsageWindow` gains `other(minutes:)`** so a window whose duration is neither 300 nor 10080
  becomes a row in its own right, labelled from its duration (`24h`, `30d`) rather than dropped.
- **Hand-written `Codable` for `UsageWindow`**, replacing the raw-value conformance that
  *Show Kimi's last-known figures instead of blanking on token expiry*
  ([`../../multi-provider/tickets/08-stale-kimi-figures.md`](../../multi-provider/tickets/08-stale-kimi-figures.md))
  introduced for its disk cache. An associated value has no raw value.
- **Warn/critical beats dimmed.** That ticket dimmed stale figures and accepted losing the colour
  channel *on the explicit premise* that the bar's primary sits near zero — false for a weekly
  primary by construction. It named this carve-out as the remedy in advance; take it now.

## Acceptance criteria

- [x] Every existing `DisplayTests` assertion passes with its **expectations untouched** — this is
      the load-bearing regression test, not a formality
- [x] A snapshot carrying only a weekly row renders that figure in the bar, rather than the no-data
      template
- [x] A snapshot carrying only a 5-hour row still renders it, and `{pct_7d}` reads `—`
- [x] A window of an unrecognised duration renders as its own dropdown row, labelled from the
      duration
- [x] A cache file written before this change still loads — same back-compat discipline as the
      v0.1.4 fixture in `ConfigTests`
- [x] A stale figure at or above the warn threshold keeps its warn/critical tone instead of dimming;
      a stale figure below it still dims

## Answer

The bar now keys on `Snapshot.primary`, a `UsageWindow` each adapter declares. `UsageWindow` gained
`other(minutes:)` and hand-written `Codable`, and the stale-figure carve-out is taken.
`swift run UsageCoreTests`: **255 pass, 0 fail**, up from 234.

**What changed**

- **`Snapshot` gains `primary`** (`Model.swift`), defaulting to `.fiveHour`, plus two derived
  accessors: `primaryRow` (the bar's figure — `nil` is *no data*, never 0%) and `secondaryRow`
  (`{pct_7d}`). `SnapshotReader` and `KimiUsageParser` both pass `primary: .fiveHour` explicitly
  rather than leaning on the default, so decision 3's "these adapters *declare* it" is visible at the
  two places that do the declaring. The default exists for the decode path, below.
- **`render(...)`** (`ViewModel.swift`) drops the `barWindow`/`barSecondaryWindow` constants for
  `snapshot.primaryRow` / `snapshot.secondaryRow`. No signature changed; no new display seam.
- **`UsageWindow`** is no longer `String`-backed. Its on-disk spelling moved to the file that owns
  the cache format (`KimiSnapshotCache.swift`), preserving `five_hour`/`weekly` byte-for-byte and
  adding `other_<minutes>`.
- **Warn/critical beats dimmed**: `barTone(_:settings:stale:)` dims a stale figure only when the live
  tone would be `.normal`.

**Meeting each clause**

- *`DisplayTests` untouched* — `git diff --stat -- Tests/UsageCoreTests/DisplayTests.swift` is empty.
  Not one expectation edited, and all ~130 pass. Claude's rendered output is byte-identical.
- *Weekly-only renders in the bar; 5-hour-only still does with `{pct_7d}` as `—`; unrecognised
  duration becomes its own labelled row* — new `PrimaryWindowTests.swift`, asserted at the display
  seam. It also pins the converse, which is the rule doing its job: rows `[weekly]` with
  `primary: .fiveHour` still reads as no data, so a Claude account missing the window that binds it
  never has the other row promoted into the bar.
- *Old cache loads* — a hand-written fixture of exactly what the shipping build wrote (raw-value
  `window`, no `primary` key), decoded and compared whole. `primary` decodes with
  `decodeIfPresent ?? .fiveHour`: every such file was a Claude or Kimi snapshot, whose primary is
  that anyway.
- *Warn/critical beats dimmed* — `StaleFigureTests`. This required **reversing that suite's one
  pinned assertion** (`"a stale figure is dimmed even over the critical threshold"`), which is the
  single test expectation this ticket changes. It is the carve-out ticket 08 authorised in advance,
  not a quiet deviation. Replaced with three: critical at 95% and warn at exactly 75 both survive
  staleness; 74.9% still dims.

**Two judgment calls, neither of them a re-decision**

1. **`1440 → 24h`, not `1d`.** The spec's two examples (`24h`, `30d`) are inconsistent under any
   single "largest whole unit" rule — 1440 minutes *is* one day. Implemented rule: days from two days
   up, hours below that, minutes when neither divides evenly. Both spec examples hold, and a lone
   `1d` sitting next to `5h`/`7d` would have scanned as a count rather than a duration.
2. **`{pct_7d}` is "the first reported row that is not the primary"**, not "the weekly row". For
   Claude and Kimi it resolves to the weekly window exactly as the hardcoded constant did. **Flagged
   for the next reader:** the token name is now mildly a misnomer — a Codex plan with a weekly
   primary and, say, a 24-hour secondary would render that 24-hour figure under a token spelled
   `{pct_7d}`. Renaming a documented user-facing template token is a product decision and out of this
   ticket's scope; nothing today can reach that state, since Codex reports one window.

**Deliberately not done**

No Codex code of any kind — no `Provider.codex`, no adapter, no `AccountSourceState.codex`. That is
tickets 02/03, and keeping this one Codex-free is what makes its proof legible. An unnamed window and
a declared primary are reachable today only from a directly-constructed `Snapshot`, which is what the
new tests do.

One consequence worth naming: an unrecognisable `window` string now **fails** the cache decode, where
before every value was one of two known cases. `KimiSnapshotCache.load` already swallows any failure
as "no cached figure", so the blast radius is a dash until the next poll — the honest outcome for a
row whose identity this build cannot establish, and consistent with decision 8's "never write a
default".
