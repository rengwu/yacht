---
type: task
blocked_by: []
claimed_by: s01TLfv49Dsg
claimed_at: 2026-07-31T00:00:00Z
---

# Show Kimi's last-known figures instead of blanking on token expiry

## Question

Raised by the user from the [acceptance run](./07-acceptance.md), on real use: **the Kimi numbers
disappear from the bar within minutes.** Liveness is `expires_at > now` (decision, ticket 02); the
token lives 900s and kimi renews it only lazily, so the poller's *resting* state is
`.tokenExpired` about fifteen minutes after the last kimi turn.
`AccountState.init(account:kimi:)` then nulls the snapshot, and the bar falls back to the no-data
template. Kimi's figure is therefore on screen roughly only while kimi is actively running —
which is the one time the user does not need to look at the bar to know they are using Kimi.

Render the last successful poll instead of hiding it, marked so it cannot be mistaken for fresh.

## Why this is not the truthfulness regression it looks like

The blanking was over-cautious, and the codebase already contains the argument against it.
`ViewModel.swift:141` explains why Claude shows no "updated Nm ago": a figure only goes stale
when usage accrues, and usage only accrues while a session runs — which is exactly when the
snapshot is rewritten. That reasoning transfers to Kimi intact: the token is live precisely when
quota is being spent, so a frozen Kimi figure is frozen exactly when nothing is moving it.

Two further protections already hold, unchanged by this ticket:

- `effectivePercentage` renders any row past its own `resetsAt` as empty, so a days-old snapshot
  self-corrects across both windows' resets rather than showing a quota that has since refilled.
- The residual wrongness case — quota spent on another machine or in Kimi's web app — is the case
  `ViewModel.swift:146` already states a clock cannot detect, and the one decision 11 already
  books as accepted risk.

So this makes Kimi's display *more* consistent with Claude's, not less.

## Decided

1. **The last successful snapshot is carried forward** when the poll cannot run (`tokenExpired`)
   or fails (`unreachable`). Only "no successful poll has ever happened" renders as no data.
2. **The menu-bar segment renders `.dimmed` while stale** — the user's call, chosen over an
   unmarked segment and over a glyph like `~0%`. Recorded trade-off: staleness therefore takes
   the colour channel that otherwise means "how full", so a stale warn/critical figure loses its
   alarm colour. Accepted because the bar's primary is the 5-hour window, which sits near zero on
   this account. **If a stale high figure ever reads wrong in real use, the fix is a carve-out —
   warn/critical wins over dimmed — not a redesign.**
3. **The dropdown note states the age**, relatively (`last fetched 12m ago`), not as a wall clock.
   The note's job is to size the doubt, and "3d ago" does that where "Tue 2:46am" does not.
   Dimmed for the routine expired-token case, `.warn` when the last poll actually failed.
4. **Staleness never expires.** No maximum age past which the figure is withdrawn: the reset
   boundary already empties each window on schedule, so an age cap would only re-create the
   blanking this ticket removes, on a slower timer.
5. **The snapshot is cached to disk** (`~/Library/Application Support/Yacht/kimi-cache.json`,
   keyed by config directory) and reloaded at launch. In-memory only would blank the bar after
   every reboot or app update — the same complaint, less often. Writes go to Yacht's own support
   directory; **decision 4's boundary is untouched — nothing under `KIMI_CODE_HOME` is written.**

## Built — 2026-07-31, awaiting the same real-use judgement as 07

`Yacht.app` 0.2.0-rc2 in `build/`, not yet installed. `swift run UsageCoreTests` 234 passed / 0
failed (201 before this ticket, all with expectations untouched — a poller with no cached figure
still produces `.tokenExpired` exactly as it did); `bash tap/test_tap.sh` 21 passed / 0 failed.

Shape of the change: `KimiResponseStateMachine.carryForward` is a second pure step beside
`reduce` — `reduce` judges one response, `carryForward` decides what the account shows given what
was last known — so the poller holds no display rule of its own and "no figure yet" versus "this
outcome over a figure" is one decision in one place. `KimiProviderState.stale(Snapshot, reason:)`
and `KimiAvailability.stale(_)` carry it to the renderer, which keeps snapshot and standing
inseparable: a stale figure cannot reach the display without its mark.

Verified against the **real** config by probe, rendering all three accounts at `now`: the Kimi
section changes from a lone `token expired — run kimi to refresh` to both window rows plus
`last fetched 42m ago — kimi hasn't run since`, and **both Claude accounts' segments, rows, tones
and notes are byte-identical before and after** — clauses 4 and 5 of [`07`](./07-acceptance.md)
still hold at the render seam.

Two things the run should watch:

- **The cache starts empty.** On first launch of rc2 the Kimi row still reads `—` until the next
  successful poll, i.e. until kimi is next run. That is the old behaviour once, not a regression.
- **Decision 2's trade-off is now live**, pinned by a test: a stale figure over the warn threshold
  renders dimmed rather than amber. The 5-hour primary sits near zero on this account, so it may
  simply never come up.

## Answer

<!-- resolved on acceptance in the real bar, alongside 07 -->
