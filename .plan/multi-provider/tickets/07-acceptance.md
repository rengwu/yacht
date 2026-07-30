---
type: task
blocked_by: [04, 05, 06]
claimed_by: s001c264b975f
claimed_at: 2026-07-30T18:36:34Z
---

# Acceptance: both providers in the real bar, on real use

## Question

HITL — the destination. Not a test run: the app ships to the user's own menu bar and is judged
on real daily use, the way
[the previous acceptance](../../usage-menubar/tickets/05-acceptance.md) was judged over thirteen
days.

What has to hold:

1. **Both providers live in one bar** — Claude accounts fed by the tap, the Kimi account fed by
   the poller — with 5-hour primary and weekly secondary reading correctly for each.
2. **Kimi's numbers match the Kimi console** when checked against it. This is the only real
   check on decision 11: there is no schema guard, so a human comparing the two is the entire
   safety net, and this ticket is where that comparison actually happens.
3. **The routine expired-token state reads as routine.** Leave kimi unused for several days,
   then look at the bar: the dimmed state and its dropdown explanation should read as "nothing
   has happened lately", not as a broken app.
4. **A Kimi failure never touches Claude.** Kill the network, corrupt the credential file, and
   confirm the Claude accounts render exactly as before.
5. **Claude's own display is unchanged** from v0.1.4 by the N-row refactor — judged by eye in
   the real bar, not only by the test suite.

Resolve by recording what real use showed, including anything that argues a spec decision was
wrong. Decisions 5 (cadence) and 11 (best-effort, no guard) are the two most likely to look
different after a fortnight than they did on paper — say so plainly if they do, rather than
accepting around them.
