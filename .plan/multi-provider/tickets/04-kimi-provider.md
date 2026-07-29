---
type: task
blocked_by: [01, 02, 03]
assets: [.plan/multi-provider/assets/kimi-usages-fixture.json]
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
