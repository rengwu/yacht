---
type: task
blocked_by: [01]
assets:
  - .plan/codex-provider/assets/appserver-ratelimits-plus.json
  - .plan/codex-provider/assets/GetAccountRateLimitsResponse.schema.json
claimed_by: s99be713285f7
claimed_at: 2026-07-31T17:32:11Z
---

# Build the Codex provider: binary, client, parser, cadence, error states

## Question

Given a `CODEX_HOME` directory, produce a correct Codex usage figure — or a correctly-named
failure. Everything between the directory and a `Snapshot`.

Deliberately coarse: this merges five natural slices on the user's instruction. **Do not split it.**
It is the largest ticket in the map and the one at risk of overflowing a session; if it does, the
answer is to finish and hand off, not to re-cut the map.

Implements [`spec.md`](../spec.md) decisions 1, 2, 5, 6, 7, 8, 9, 10 and 11.

## What to build

- **Locate the binary.** Yacht is a login item and `launchctl getenv PATH` is unset, so a
  launchd-spawned Yacht sees only `/usr/bin:/bin:/usr/sbin:/sbin` — and codex installs to
  `~/.local/bin`, invisible to it. Probe in order: user override, `~/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, npm global prefix, the ChatGPT.app bundle. Prefer the
  user's own install over the bundled one, whose version may differ. No shell is invoked.
- **Call the RPC.** Spawn `codex app-server` with `CODEX_HOME` set to the account's directory,
  `initialize` → `initialized` → `account/rateLimits/read` (params `null`), then **exit**. Roughly
  1s end to end; nothing of Yacht's stays alive between polls. Enforce a timeout.
- **Decode strictly.** A missing or retyped required field is a failure, never a number. `primary:
  null` means **no data, never 0%** — the alternative is a comfortable, catastrophically wrong "0%
  used". Absorb additive change: ignore unknown keys, accept `usedPercent` as int or float, map
  unrecognised `windowDurationMins` through `other(minutes:)`. `resetsAt` is Unix **seconds**.
- **Read past** `credits`, `rateLimitResetCredits`, `individualLimit`, `planType`, `limitName`,
  `spendControlReached`, `rateLimitReachedType` and `rateLimitsByLimitId`. Decision 11 — the
  consequence is accepted, not overlooked.
- **Schedule adaptively:** ~60s while live, ~15min otherwise, immediate on dropdown open. The fast
  phase exists because quota moves only while codex runs — *not* for Kimi's reason (a token valid
  only mid-session); a Codex poll returns true numbers at any time.
- **Liveness is the newest rollout file's mtime** under `$CODEX_HOME/sessions/YYYY/MM/DD/`. Verified
  faithful to the second. An app-server that starts no thread writes no rollout, so Yacht's own
  polling cannot trigger its own fast phase — preserve that property.
- **Four failure states**, one per user action: can't find codex / signed out / couldn't reach
  OpenAI / unexpected reply. Signed out is verifiably distinguishable:
  `-32600 "codex account authentication required to read rate limits"`.
- **Carry forward and cache**, matching the Kimi treatment: last successful snapshot survives a
  failed poll, is cached to Yacht's own support directory, and reloads at launch. Nothing under
  `CODEX_HOME` is ever written.

## Acceptance criteria

- [ ] The committed live fixture parses to a weekly row of 10% resetting at the captured instant
- [ ] A payload with `primary: null` yields no data — asserted explicitly *not* to be 0%
- [ ] A payload missing `usedPercent` fails rather than defaulting
- [ ] `usedPercent` parses from both `10` and `10.0`; unknown keys are ignored
- [ ] Each of the four failure states is reachable and distinctly identified
- [ ] The schedule moves to its fast phase on a fresh rollout mtime and backs off without one
- [ ] Yacht's own poll does not advance the liveness signal
- [ ] A failed poll after a successful one carries the figure forward; a failed poll with no prior
      success reads as no data
- [ ] Nothing under `CODEX_HOME` is created or modified — assert it, do not assume it
- [ ] A Codex failure leaves Claude and Kimi accounts rendering unchanged

## Answer

Built the complete provider core from a `CODEX_HOME` boundary to a provider-neutral `Snapshot`,
without taking on ticket 03's registration or AppKit wiring.

**What landed**

- `CodexBinaryLocator` produces the settled candidate order — override, `~/.local/bin`, Homebrew,
  `/usr/local`, injected npm global prefix, then ChatGPT's bundled binary — and selects only an
  executable file. It never consults PATH or invokes a shell, prefers the user's installation, and
  exposes not-found instead of inventing a path.
- `CodexClient` spawns the resolved executable directly as `codex app-server`, sets the selected
  account directory as `CODEX_HOME`, sends `initialize` → `initialized` →
  `account/rateLimits/read` with `params: null`, and terminates the process after one result. The
  whole exchange has an eight-second timeout. Request construction and the child environment are
  exposed as pure seams and pinned in tests; the process itself remains below the seam, as the spec
  directs.
- `CodexUsageParser` decodes the committed JSON-RPC fixture against the generated response shape.
  It reads only `rateLimits.primary` and `.secondary`; all credit, plan, spend-control, per-limit,
  and additive fields are ignored. `usedPercent` is required and accepts both integer and floating
  JSON numbers; durations map 300 → five-hour, 10080 → weekly, and every other value to
  `other(minutes:)`; reset timestamps are Unix seconds. A null or unusable primary returns an empty
  snapshot, never a fabricated 0% row and never a promoted secondary.
- `CodexResponseStateMachine` names four actionable failures exactly: binary not found, signed out,
  OpenAI unreachable, and unexpected reply. The verified `-32600` authentication message maps only
  to signed-out; timeout and recognisable network failures map to unreachable; malformed payloads
  and other protocol errors map to unexpected reply.
- `CodexRolloutLiveness` reads only modification metadata for
  `sessions/YYYY/MM/DD/rollout-*.jsonl`. `CodexPollSchedule` checks that cheap signal every minute,
  polls about every minute while a rollout is fresh, backs off to fifteen minutes when it ages out,
  polls immediately on startup/dropdown open, and immediately enters the fast phase when a fresh
  rollout appears. Because no other file is a liveness input, Yacht's poll cannot advance the
  signal.
- `CodexUsagePoller` holds one account's in-memory state, prevents overlapping requests, carries the
  last successful snapshot across every failure, and starts from a disk-cached figure marked as
  awaiting refresh. `CodexSnapshotCache` keys figures by standardized `CODEX_HOME` path while
  writing only to the Yacht-owned URL supplied by the composition root.

**Acceptance evidence**

- The live fixture produces one weekly primary row at 10%, resetting at epoch `1786010208` — the
  exact instant committed in the fixture.
- Tests explicitly pin null primary as no rows/no primary row/not a 0% row; missing or string-typed
  `usedPercent` fails; `10` and `10.0` both parse; unknown keys and durations are absorbed.
- All four failure states and their user-action messages are independently asserted, including the
  exact signed-out message and the separation between network failure and contract drift.
- Cadence tests cover idle startup, live transition, minute polling, dropdown override, and backing
  off without spending a final fast-phase poll. Filesystem tests prove only rollout files in the
  dated hierarchy affect liveness and that a provider poll does not move their mtimes.
- Poller tests cover success → failed poll carry-forward, cold-start failure with no figure,
  unresolved binary, cache round-trip/relaunch, and account scoping.
- A complete byte-and-mtime snapshot of a synthetic `CODEX_HOME`, including `auth.json`, is equal
  before and after all Yacht-owned liveness/poller/cache work. Production Codex code contains no
  credential read and no `CODEX_HOME` write; the cache target is outside it.
- Claude and Kimi are rendered before and after a synthetic Codex failure and compared whole; their
  view model is byte-for-byte unchanged. The existing `DisplayTests.swift` was not edited.

`swift run UsageCoreTests`: **329 pass, 0 fail** (up from 255). `swift build -c release` also passes.
The only emitted warning is the machine's pre-existing Command Line Tools/XCTest platform-path
warning; this repository deliberately uses the executable test harness instead.

**Safety caveat exposed rather than hidden**

The acceptance sentence “nothing under `CODEX_HOME` is created or modified” cannot be literally
true of a real end-to-end app-server run: this same settled spec's verification section records that
the vendor process updates its own `logs_*.sqlite` / `state_*.sqlite` WAL while serving the request.
The implementable safety boundary is the one the spec otherwise states: **Yacht itself** never opens
`auth.json`, never writes any Codex-owned file, and uses the vendor process over stdio for
authentication. Tests assert that boundary over every Yacht-owned filesystem operation; they do
not falsely claim control over the documented side effects of the vendor binary. A human should
reopen the acceptance wording if it was intended literally.

**Deliberately left out**

No `.codex` provider registration, settings field, AppKit composition, account-source projection,
or real-login-item acceptance run. Ticket 03 owns making this core reachable; ticket 04 owns daily
use and the launchd-path/real-account checks. The installed codex binary was not queried: parser
work uses only the committed fixture and generated schema, as required.
