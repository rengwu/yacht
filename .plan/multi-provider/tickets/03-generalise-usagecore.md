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
