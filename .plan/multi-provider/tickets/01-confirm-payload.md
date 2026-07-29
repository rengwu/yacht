---
type: task
blocked_by: []
assets: [.plan/multi-provider/assets/kimi-usages-fixture.json]
claimed_by: s97027c8afc1a
claimed_at: 2026-07-29T18:55:42Z
---

# Confirm the usage payload under partial quota

## Question

The captured fixture was taken at **100/100 on both windows**, so the single most load-bearing
assumption in [`spec.md`](../spec.md) — that `used = limit - remaining`, and that `remaining`
decrements as work is done — is asserted, not observed.

Capture a second payload while quota is partially consumed and confirm or correct:

1. `remaining` decrements (rather than, say, `limit` shrinking, or a separate used counter
   appearing).
2. The 5-hour `limits[]` entry and the top-level weekly `usage` object move **independently**.
3. `resetTime` on the 5-hour window rolls forward as expected, and the weekly one holds at the
   subscription anniversary.
4. Whether row count or `window` values ever differ from the fixture — if a second window
   appears in `limits[]`, decision 3 (hardcoded 5h primary / weekly secondary) needs revisiting
   and this ticket should say so.

Also settle the open plan question: the fixture reports `membership.level: LEVEL_BASIC` and
`subType: TYPE_PURCHASE`, naming no tier. Confirm against the Kimi console that this endpoint
describes the plan actually being paid for — if the weekly `limit` of 100 does not match the
console, the number Yacht would show is wrong at the source.

**Requires the human** only to have used kimi recently enough for a valid token (decision 4 —
Yacht never refreshes, and neither does this ticket). Capture and analysis are the agent's.

Save the second capture alongside the first as an asset, userId redacted. Record in the answer
what changed, and flag explicitly if anything here contradicts the spec.
