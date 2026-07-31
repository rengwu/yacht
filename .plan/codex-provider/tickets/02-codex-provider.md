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
