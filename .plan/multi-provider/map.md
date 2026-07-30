# Map — Kimi Code alongside Claude in Yacht

## Destination

Yacht showing **both** subscriptions in one menu bar — Claude accounts fed by the installed tap,
the Kimi account fed by a read-only poller — implementing [`spec.md`](./spec.md), renamed to a
provider-agnostic identity, and accepted on real daily use on this Mac. Not green tests: the
real bar, judged over real days.

## Notes

- **Domain:** the same AppKit menu bar utility as
  [`../usage-menubar/`](../usage-menubar/map.md), now serving two providers with fundamentally
  different data acquisition. Claude **pushes** (status-line hook writes a snapshot every turn);
  Kimi must be **pulled** (authenticated poll of an undocumented endpoint). Every awkward part of
  this effort traces back to that asymmetry.
- **Kimi is best-effort, and this is a deliberate reversal.** The previous spec explicitly
  rejected credential-polling an undocumented endpoint because it can silently report wrong
  numbers. That rejection assumed a supported alternative existed — true for Claude, false for
  Kimi. A schema-drift guard was offered and **declined** on 2026-07-28. Claude stays the
  authoritative provider; a Kimi server change can produce wrong numbers until a human notices.
  See [`spec.md`](./spec.md#accepted-risk--a-deliberate-reversal). Do not re-open this as a bug.
- **Execution override.** This is an *execution* map. The design is settled by a completed
  `grill-me` session recorded in [`spec.md`](./spec.md) — **do not re-litigate its decisions**;
  implement them. Every ticket is `task` type.
- **Implementation stays off the user's desk.** Build tickets are deliberately coarse and AFK.
  Do not split them for its own sake, and do not ask the user about implementation choices.
  Surface something only when it is a genuine product design/behaviour question the spec did not
  already decide. The user is token-conscious; respect it.
- **Two decisions are safety-critical**, both in [`spec.md`](./spec.md): never refresh or write
  the Kimi credential file (decision 4 — a write-back can log the user out of Kimi), and never
  let a Kimi failure degrade a Claude account's numbers.
- **The binary lies about the schema.** `toWireUsage` inside the kimi executable describes the
  *local `kimi web` server's* reshaping, not the upstream API. An earlier session read it and
  produced a wrong schema. Build against
  [`assets/kimi-usages-fixture.json`](./assets/kimi-usages-fixture.json), captured live.
- **Skills to consult:** `codebase-design` (UsageCore stays a deep module — one pure function, UI
  as dumb projection), `domain-modeling` (Provider, Row, Account are the load-bearing terms),
  `review-code` (especially the credential read and the poller).
- Tests run via `swift run UsageCoreTests` — no XCTest on this machine.
- **Never resolve more than one ticket per session.** Claim before working (set `claimed_by` +
  `claimed_at`, commit). This adapter is single-session — no concurrent work.
- **Ask before committing** anything to git.
- Open tickets are found by querying `tickets/` (frontier = open, unblocked, unclaimed), not
  listed here. Progress is derived by counting tickets, never written down.

## Decisions so far

<!-- one line per resolved ticket: gist + link. -->

- Payload confirmed at partial quota: `remaining` decrements, the two windows step
  independently, `limits[]` stays one 5h entry (decision 3 stands). **`used` does exist upstream
  — zero-valued numerics are omitted from the JSON entirely**, correcting a trap in
  [`spec.md`](./spec.md); expect `remaining` to vanish at an exhausted window. Console (Moderato)
  matches the payload digit-for-digit, so `limit: 100` is the real paid ceiling and reads as a
  percentage denominator, not a request count. — [`01`](./tickets/01-confirm-payload.md)
- `Snapshot` is now N `UsageRow`s of absolute `{used, limit}`, with identity in a `UsageWindow`
  enum kept separate from the display label — the bar keys on the window, never on row order, so
  a weekly-only snapshot reads as "no 5-hour data" rather than promoting it. A percentage-only
  source is a count out of 100, which is also Kimi's real denominator, so both providers share
  one 0–100 scale. Claude's rendered output is unchanged: all 130 prior assertions pass with
  expectations untouched. **Count-based rows need no new template tokens and a raw count would
  mislead**, since `limit: 100` makes the percentage and the count the same number and the
  underlying unit is coarser than a turn. — [`03`](./tickets/03-generalise-usagecore.md)

## Not yet specified

- **Whether the reset-boundary rule survives an anniversary-anchored window.** The existing rule
  — a figure past its own `resets_at` renders empty, and inferred-empty reads as true — assumes
  windows reset on a rolling schedule. Kimi's weekly is anchored to the subscription
  anniversary, and its 5-hour window is described as *rolling*, which may not mean the same thing
  Claude's does. <clears-with: 04>
- **Whether the 5-hour window is the right primary for Kimi.** Decision 3 hardcodes 5h primary
  for both providers because that is the binding constraint for Claude. With a weekly quota of
  100, the weekly may be what actually bites on Kimi — in which case the bar shows the less
  useful number for that provider. Real use decides this, not argument. <clears-with: 07>

## Out of scope

- **Refreshing or writing the Kimi credential file**, in any form — a safety boundary, not a
  deferral. See [`spec.md`](./spec.md) decision 4.
- **A payload schema-drift guard.** Offered and declined 2026-07-28; the consequence is recorded
  as accepted risk in the Notes above rather than tracked as work.
- **Fuel packs / `extra_usage`**, and **`parallel.limit`** — the first does not exist upstream,
  the second is a concurrency cap rather than a usage window.
- **Local token-count estimation** from `~/.kimi-code/sessions/*/wire.jsonl` — it can neither
  learn the plan ceiling nor see usage from another machine, so it answers a different question.
- Everything ruled out by
  [`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope) that this effort does not
  explicitly reverse — history and trends, cost accounting, threshold notifications, control over
  the agents themselves, Windows/Linux, a configurable poll interval.
