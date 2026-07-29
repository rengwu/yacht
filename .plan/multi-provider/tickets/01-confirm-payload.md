---
type: task
blocked_by: []
assets:
  - .plan/multi-provider/assets/kimi-usages-fixture.json
  - .plan/multi-provider/assets/kimi-usages-partial-a.json
  - .plan/multi-provider/assets/kimi-usages-partial-b.json
  - .plan/multi-provider/assets/kimi-console-2026-07-29.png
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

## Answer

Two live payloads captured 2026-07-29, two minutes apart, at partial quota — saved as
[`kimi-usages-partial-a.json`](../assets/kimi-usages-partial-a.json) (18:58:42Z) and
[`kimi-usages-partial-b.json`](../assets/kimi-usages-partial-b.json) (19:00:42Z), userId
redacted. Between them the human ran `kimi`, so the pair brackets ~4 turns of real work.

The load-bearing assumption holds. **One spec statement is wrong**, and it is wrong in a way
that can produce a crash or a wrong number at exactly the worst moment.

### Correction — `used` exists upstream; zero-valued numerics are omitted entirely

[`spec.md`](../spec.md) lists as a confirmed trap:

> **`remaining`, not `used`.** Percentage math inverts: `used = limit - remaining`.

There *is* a `used` field. It was invisible in the original fixture only because that capture
was at 100/100, and **a numeric that is zero is omitted from the JSON rather than serialised as
`"0"`**. Capture *a* proves this inside a single response — same payload, same schema, one row
each way:

```json
"usage":  {"limit":"100","used":"27","remaining":"73",...}     // non-zero -> key present
"limits":[{"detail":{"limit":"100","remaining":"100",...}}]    // zero     -> no `used` key
```

Two minutes later in capture *b*, after the turns landed, `limits[0].detail.used` has appeared
as `"1"`. The arithmetic the spec relies on is still correct — `27 = 100-73`, `1 = 100-99`,
`used` and `limit - remaining` agreed in every observation — so **decision 2's row model
survives untouched**. What changes is the parsing contract, and this is the part worth carrying
into ticket 04:

- Every numeric string field is **optional**, and absent means `0`. A decoder that requires
  `used`, or that treats a missing key as a decode failure, breaks on ordinary payloads.
- By the same rule, **`remaining` should be expected to vanish when a window is exhausted.**
  That is an inference, not an observation — I never got a window to zero — but it follows from
  the mechanism, and it is precisely the moment the user most needs the number. An adapter that
  errors on missing `remaining` would blank the row at 100% used.
- Suggested rule for the adapter: parse every numeric as "absent ⇒ 0", and take `used` from the
  `used` field when present, falling back to `limit - remaining`. Both sources agreed here, so
  there is no conflict to arbitrate today.

This is a correction to an observation the spec recorded, not a re-opening of a decision. No
decision changes.

### The four clauses

1. **`remaining` decrements — confirmed.** Weekly moved `100 → 73` between the 2026-07-28
   fixture and capture *a*; the 5-hour moved `100 → 99` between *a* and *b*. `limit` held at
   `"100"` on both windows in all three payloads — it does not shrink. No separate counter
   appeared beyond the `used` field described above.
2. **The two windows move independently — confirmed, directly.** In the two minutes between *a*
   and *b* the 5-hour went `used 0 → 1` while the weekly held at `used 27`. They are separate
   counters that step at separate times.
3. **`resetTime` behaves as expected, and the 5-hour is better than "rolling".** The weekly
   `resetTime` is byte-identical across all three captures (`2026-08-04T02:16:12.750803Z`) —
   anniversary-anchored, as assumed. The 5-hour advanced from `2026-07-28T11:16:12.750803Z` to
   `2026-07-29T22:16:12.750803Z`: **exactly 35h = 7 × 5h**, and it carries the same
   `.750803` sub-second fraction as the weekly. A window rolling from first use would carry the
   microseconds of the moment the user started working, and would not coincidentally match the
   weekly's to six places. So the 5-hour resets on a **fixed grid off an account anchor**, not
   from first use. (Two observations, so this is a strong inference rather than proof. The two
   grids are not aligned to each other — the weekly reset is not an integer number of 5-hour
   steps from the 5-hour one.) This matters for the map's open question about whether the
   reset-boundary rule survives; it points to *yes*, and more predictably than feared.
4. **Row count and `window` values never differed.** `limits[]` held exactly one entry,
   `{duration: 300, timeUnit: TIME_UNIT_MINUTE}`, in every capture. No second window appeared.
   **Decision 3 stands** — nothing here asks for it to be revisited.

### Two things found on the way, for ticket 04

- **The request needs only `Authorization: Bearer` and `Accept: application/json`**, with an 8s
  timeout — read from `fetchManagedUsage` in the kimi binary and confirmed by both captures
  succeeding with nothing else. The `X-Msh-Device-Id` / `X-Msh-Platform` identity headers the
  binary attaches elsewhere are **not** required for `/usages`.
- **Access tokens live 900 seconds** (`expires_in: 900`). The stored token was 32 hours expired
  when this session started. This does not contradict decision 5, but it sharpens it: outside a
  live kimi session the token is essentially *always* expired, so decision 8's "token expired —
  run kimi to refresh" is the **normal resting state** of the Kimi rows, not an edge case. Worth
  designing the dropdown copy for something the user will see most of the time.

### The quota unit is not a turn — flagged, not resolved

Cross-checking the local `usage.record` events: 113 turns since the weekly window opened
(2026-07-28T02:16Z) against `used: 27`, and 4 turns in the current 5-hour window against
`used: 1`. Both land at ~4.2 turns per unit, consistent enough to suggest one underlying
fractional unit that the two windows report as independently-stepping integers. Yacht does not
need to know what the unit is — it renders what the server reports — but it does mean **"73 of
100" is not "73 requests left"**, and any dropdown wording that implies a request count would be
wrong. Relevant to the map's open question on rendering count-based rows.

### Deliberately not done

- **Never refreshed the token** (decision 4). The watcher polled the credential file read-only
  and captured only when the human's own `kimi` run had put a live token there; the refresh
  token was never read or used, and nothing under `~/.kimi-code/` was written.
- **No exhausted-window capture.** Driving a window to zero to observe whether `remaining`
  disappears would have burned the human's real quota. The prediction is recorded above instead.
### The console agrees — the endpoint describes the plan being paid for

Settled. The human read the Kimi console while the captures were live; screenshot saved as
[`kimi-console-2026-07-29.png`](../assets/kimi-console-2026-07-29.png). It matches capture *b*
on every figure:

| Console | Payload |
| --- | --- |
| Weekly usage **27%**, "Resets in 5d 7h 9min" | `usage.used "27"` / `limit "100"`, resetTime 5d 7h 9min out |
| Rate limit details **1%**, "Resets in 3h 9min" | `limits[0].detail.used "1"` / `limit "100"`, resetTime 3h 9min out |
| My benefits: **Moderato** | `membership.level: LEVEL_BASIC`, `subType: TYPE_PURCHASE` |

Both percentages match to the digit and both countdowns to the minute, against reset timestamps
computed independently. **The `/usages` endpoint is the same source the console renders**, so
the weekly `limit` of `100` is the real ceiling of the paid plan. The number Yacht would show is
correct at the source.

Three consequences worth carrying forward:

- **`limit: 100` is a percentage denominator, not a request count.** The console renders both
  windows as bare percentages, and `used` is numerically the percentage precisely because the
  limit is 100. Combined with the ~4.2-turns-per-unit finding above, this says the map's open
  question on rendering count-based rows most likely **resolves to "render Kimi as a percentage,
  same as Claude"** — no new template tokens needed. Caveat: this account is Moderato; whether
  every tier reports `limit: 100` is unknown, and `{used, limit}` under decision 2 absorbs it
  either way.
- **The tier name is not in the payload.** `LEVEL_BASIC` is what Moderato looks like on the
  wire, so Yacht cannot display the plan name from this endpoint. Harmless — under decision 7 an
  account is a user-supplied `(label, directory)` pair.
- **The console's own labels are "Weekly usage" and "Rate limit details"** for the two windows,
  which is a reasonable source for the derived labels the adapter has to synthesise (there is no
  `label` field upstream).
