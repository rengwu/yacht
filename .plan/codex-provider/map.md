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

_None yet — the design is settled in [`spec.md`](./spec.md); these tickets execute it._

## Not yet specified

- **Whether the weekly window is the right thing for the Codex bar to show.**
  [`spec.md`](./spec.md) decision 3 takes the bar's figure from whatever the wire calls `primary`,
  and on this plan that is the weekly. It is the only window Codex reports, so there is no
  alternative today — but whether a weekly percentage is *useful at a glance* is a different
  question from whether it is correct, and real use decides it, not argument.
  <clears-with: 04>

- **Whether "can't find codex" actually fires when it matters.** The launchd PATH problem is
  reasoned from `launchctl getenv PATH` being unset, not observed in a shipped login item. The
  failure it produces must be verified from a real Yacht launched at login, not from a
  terminal-launched debug build, which inherits a PATH the login item will not have.
  <clears-with: 04>

- **Whether ignoring `rateLimitReachedType` bites.** [`spec.md`](./spec.md) decision 11 knowingly
  accepts that Yacht will show a comfortable figure on a day Codex blocks the user below 100%. On a
  Plus plan with no credits enabled this may never occur; if it does, the recorded remedy is to pin
  the tone, not to redesign.
  <clears-with: 04>

- **Whether Codex ever populates `secondary` on this account.** Every observation so far has
  `secondary: null`. The primary-row rule is built to follow a restored 5-hour window automatically,
  but that path has never executed against a real payload.

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
