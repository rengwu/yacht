---
type: task
blocked_by: [01, 02, 03]
assets: [.plan/multi-provider/assets/kimi-usages-fixture.json]
claimed_by: s91b64fb038ed
claimed_at: 2026-07-30T17:00:55Z
---

# Build the Kimi provider: credentials, poller, cadence, error states

## Question

AFK build ticket — decisions 1, 4, 5 and 8 of [`spec.md`](../spec.md). Deliver Kimi as a second
source feeding the N-row model from
[Generalise UsageCore](./03-generalise-usagecore.md).

1. **Credential read — strictly read-only.** Load the bearer token from the account's
   `KIMI_CODE_HOME` (default `~/.kimi-code`). **Never write that file, never perform a refresh
   grant, never hold a rotated refresh token.** Kimi persists rotated refresh tokens, so any
   write-back can log the user out of Kimi with no trace of the cause. Structure the code so a
   future contributor cannot add a refresh without deleting a comment that says why not.
2. **Parser**, against the real fixture and the confirmations from
   [Confirm the usage payload](./01-confirm-payload.md). Mind every trap in the spec: no labels
   (derive from `window.duration` + `timeUnit`), `remaining` not `used`, **numbers arrive as
   strings**, and the two windows come from two differently-shaped places — top-level `usage`
   for weekly, the sole `limits[]` entry for the 5-hour. Ignore `extra_usage`, `totalQuota` and
   `parallel`.
3. **Adaptive poller** on the signal chosen in
   [Find a reliable signal](./02-session-liveness.md): ~60s live, ~15min otherwise, plus an
   immediate poll on dropdown open. No configurable interval.
4. **Error states**, per decision 8: the dropdown distinguishes *token expired — run kimi to
   refresh* from *couldn't reach Kimi*; the bar renders the existing dimmed no-data state for
   both, adding no new bar vocabulary. Expiry is a **routine** state here, not an error — an
   expired token after a few days away is the normal resting state and must read that way.
5. **Tests run offline.** The suite must not touch the network: drive the parser and the state
   machine from the saved fixture and from synthetic error responses (401, 5xx, timeout,
   malformed body). Note that under decision 11 a *shape change that still parses* is an
   accepted risk and is deliberately **not** guarded — do not add a schema guard here; if that
   trade looks wrong once built, say so in the answer rather than building one.

Kimi is best-effort by decision; Claude remains the authoritative provider. A Kimi failure must
never degrade a Claude account's numbers or block its rendering.

## Answer

Built the Kimi provider as a standalone UsageCore adapter and adaptive poller.

- **Credentials stay read-only.** `KimiCredentialStore` reads only
  `<KIMI_CODE_HOME>/credentials/kimi-code.json` (with a helper for the default
  `~/.kimi-code`), decodes only `access_token` and epoch-seconds `expires_at`, and has no write
  or refresh operation. The safety boundary is stated immediately above the read: Kimi rotates
  and persists refresh tokens, so a future contributor cannot add refresh support without
  deleting the warning explaining how it can log the user out. Unknown keys, including any
  refresh token, are never decoded or retained.
- **The real upstream shape feeds N rows.** `KimiUsageParser` is built against the saved live
  full and partial fixtures. It maps the sole 300-minute `TIME_UNIT_MINUTE` limit to `.fiveHour`
  and top-level `usage` to `.weekly`, deriving the shared `5h`/`7d` labels from
  `UsageWindow`. Numeric quota fields decode as optional strings with absence meaning zero;
  `used` wins when present and otherwise falls back to `limit - remaining`, including the
  expected exhausted-window case where `remaining` is absent. `parallel`, `totalQuota`,
  `extra_usage`, membership and other unrelated fields are ignored.
- **Polling is adaptive without refreshing.** `KimiPollSchedule` uses a 60-second live network
  cadence and 15-minute idle network phase. Credential liveness is exactly
  `expires_at > now`; the cheap local credential check remains every 60 seconds in the idle
  phase, so a token refreshed by kimi triggers an immediate request instead of waiting up to
  15 minutes. Opening the dropdown overrides the due time and requests immediately when a live
  token exists. An expired, missing or unreadable credential publishes the routine expiry state
  without making a guaranteed-401 request. `KimiUsagePoller` supplies the real timer and an
  injectable transport; the production transport performs only the documented-by-observation
  GET to `/coding/v1/usages`, with bearer auth, JSON accept, and an 8-second timeout.
- **Failure states are provider-local.** A parsed 200 publishes a `Snapshot`; 401 publishes
  `.tokenExpired`; 5xx, timeout, transport failure and malformed 200 publish `.unreachable`.
  Both failure states deliberately clear only that Kimi account's snapshot, so the existing
  dimmed no-data menu-bar rendering is used and stale Kimi numbers cannot survive a failure.
  The dropdown renders `token expired — run kimi to refresh` in a dimmed, routine tone and
  `couldn't reach Kimi` as a warning. `AccountState` carries provider runtime state independently
  per account, and the mixed-provider test pins that an unreachable Kimi account does not alter
  Claude's bar figure or dropdown rows.
- **Tests are entirely offline.** `swift run UsageCoreTests` now passes **193 assertions**
  (145 pre-existing, 48 Kimi), driven by the three saved live payloads plus synthetic
  credentials, exhaustion, 401, 5xx, timeout, network failure and malformed-body cases. The
  suite constructs and inspects the request but never creates a URLSession task.
  `swift build -c release` also succeeds.

Deliberately not added: a schema-drift guard, token refresh/write-back, fuel packs, parallel
limits, configurable cadence, provider persistence, or Settings registration. The last two are
ticket 05's explicit scope: this ticket supplies a poller that accepts one concrete
`KIMI_CODE_HOME`, exposes `dropdownOpened()`, and emits provider-neutral state for that ticket's
composition-root wiring.
