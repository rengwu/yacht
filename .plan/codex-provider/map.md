# Map — Codex CLI alongside Claude and Kimi in Yacht

## Destination

Yacht showing **all three** subscriptions in one menu bar — Claude fed by the installed tap, Kimi by
a read-only poller, Codex by its own first-party app-server RPC — implementing
[`spec.md`](./spec.md), and accepted on real daily use on this Mac. Not green tests: the real bar,
judged over real days.

## Notes

- **Domain:** the same AppKit menu bar utility as [`../usage-menubar/`](../usage-menubar/map.md) and
  [`../multi-provider/`](../multi-provider/map.md), now serving three providers. Claude **pushes**
  (status-line hook writes a snapshot every turn); Kimi and Codex must be **pulled**. Codex is
  pulled by *asking the vendor's own binary*, which is why almost none of Kimi's awkwardness
  repeats here.

- **Execution override.** This is an *execution* map. The design is settled by a completed
  `grill-me` session recorded in [`spec.md`](./spec.md) — **do not re-litigate its twelve
  decisions**; implement them. Every ticket is `task` type.

- **Implementation stays off the user's desk.** Build tickets are deliberately coarse and AFK. Nine
  natural slices were merged to four, on the user's instruction. **Do not split them back out**, and
  do not ask the user about implementation choices. Surface something only when it is a genuine
  product design/behaviour question the spec did not already decide. The user is token-conscious;
  respect it.

- **Codex is authoritative for correctness, caveated for availability**
  ([`spec.md`](./spec.md) decision 12). A dark Codex section after a codex upgrade is *expected
  breakage*; a wrong Codex number is a *bug*. Do not file the first as the second, and do not
  extend Kimi's best-effort posture (that spec's decision 11) to Codex — it is scoped to Kimi on
  purpose.

- **Two boundaries are safety-critical.** Yacht never reads, writes, or refreshes a Codex
  credential — it never opens `auth.json` at all, because codex owns its own token. And a Codex
  failure must never degrade a Claude or Kimi account's numbers.

- **Build against the committed evidence, never against the binary.** The live capture is
  [`assets/appserver-ratelimits-plus.json`](./assets/appserver-ratelimits-plus.json) and the
  vendor's own generated contract is
  [`assets/GetAccountRateLimitsResponse.schema.json`](./assets/GetAccountRateLimitsResponse.schema.json).
  Regenerate with `codex app-server generate-json-schema --out DIR`. The multi-provider effort lost
  a session to reading schema out of a binary that described a different layer; do not repeat it.

- **Only the first ticket can regress existing users**, and its entire proof is that Claude's
  rendered output is byte-identical. Keep it that way: land it before any Codex code exists, so a
  render regression can never be confused with a Codex bug.

- **Skills to consult:** `codebase-design` (UsageCore stays a deep module — one pure function, UI as
  dumb projection), `domain-modeling` (Provider, Row, Window, Account are the load-bearing terms),
  `review-code` (especially the subprocess client and the strict decoder).

- Tests run via `swift run UsageCoreTests` — no XCTest on this machine.

- **Never resolve more than one ticket per session.** Claim before working (set `claimed_by` +
  `claimed_at`, commit). This adapter is single-session — no concurrent work.

- **Ask before committing** anything to git.

- Open tickets are found by querying `tickets/` (frontier = open, unblocked, unclaimed), not listed
  here. Progress is derived by counting tickets, never written down.

## Decisions so far

<!-- one line per resolved ticket: gist + link. -->

The design is settled in [`spec.md`](./spec.md); these tickets execute it. What landed:

- **The bar reads `Snapshot.primary`**, a `UsageWindow` each adapter declares — Claude and Kimi say
  5-hour, a Codex adapter takes it from the wire. `{pct_7d}` is the first reported row that is not
  the primary, `—` when there is none. `UsageWindow` gained `other(minutes:)` and hand-written
  `Codable`; stale figures at or above warn keep their tone.
  ([01](./tickets/01-primary-window-rule.md))

- **All three providers accepted in the real bar**, on two days of ordinary use judged by the user.
  Codex's figure matched codex's own `account/rateLimits/read` digit-for-digit twice, at **1%** and
  then **16%**, so the poller tracks a moving number. **The launchd PATH worry is resolved by
  absolute-path probing, not by PATH**: the installed app runs with
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and still finds `~/.local/bin/codex`. **Weekly-in-the-bar is
  useful but dull** — accepted with caveat, and the only window Codex reports.
  **`rateLimitReachedType` never bit** on this Plus plan. Two claims are accepted on substitute
  evidence and named as such: no login event ever launched this build (uptime since 2026-07-13), and
  a `codexBinaryPath` override — not the probe — served the polls from 2026-08-03 15:26.
  ([04](./tickets/04-acceptance.md))

## Not yet specified

- **Whether Codex ever populates `secondary` on this account.** Every observation so far has
  `secondary: null`, including acceptance's final read on 2026-08-03. The primary-row rule is built
  to follow a restored 5-hour window automatically, but that path has never executed against a real
  payload. If it ever does, the weekly-in-the-bar verdict below is worth re-judging rather than
  assuming settled.

- **How the four failure states and the stale carve-out actually read.** Acceptance ran two days on
  a healthy account: no Codex failure and no stale Codex figure ever reached the bar, so the
  wording of all four messages and the "stale keeps its warn/critical tone" carve-out
  ([`spec.md`](./spec.md) decision 10) are unjudged in the flesh. Not a defect — unobserved. Look
  properly at the first one that appears in real use.

## Out of scope

- **Reading, writing, or refreshing any Codex credential**, in any form — a safety boundary, not a
  deferral. Yacht never opens `auth.json`; codex owns its own token.
- **Token and cost accounting.** `account/usage/read` exists and returns lifetime and daily token
  counts. Deliberately unused.
- **Credits, reset credits, and spend-control state** — [`spec.md`](./spec.md) decision 11, with its
  consequence explicitly accepted by the user rather than deferred.
- **Tailing the rollout JSONL for usage figures.** It is read for one mtime and nothing else.
- **Holding a resident app-server**, or proxying into the ChatGPT desktop app's.
- **Pinning or version-gating the codex binary.** Yacht must not go dark because the user stayed
  current.
- **Reinstating the per-provider row picker** dropped on 2026-07-28 — decision 3 solves the same
  problem without a user-facing setting.
- Everything ruled out by [`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope) that
  this effort does not explicitly reverse — history and trends, threshold notifications, control
  over the agents themselves, Windows/Linux, a configurable poll interval.
