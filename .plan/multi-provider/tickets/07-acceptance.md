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

## Acceptance run — started 2026-07-31, not yet resolved

This is not the Answer. Real use has not happened yet: this section records what the run was
started with and what was settled before it, so the session that resolves this ticket is judging
days rather than re-deriving the setup.

**Shipped.** `Yacht.app` 0.2.0-rc1 (`./build.sh 0.2.0-rc1`, ad-hoc signed) replaced the v0.1.4
bundle that had been running continuously since 2026-07-14 in `/Applications`. `swift run
UsageCoreTests` 201 passed / 0 failed, `bash tap/test_tap.sh` 21 passed / 0 failed. The user then
registered `~/.kimi-code` through the real Add Account → Kimi flow, so the config now holds three
accounts — `John`, `Meiyin` and `kimi-code` — with both Claude labels and their taps intact
across the v0.1.4 config upgrade. The clock on clause 1's real-days observation starts here.

**Clause 5 is settled mechanically, ahead of the by-eye check.** v0.1.4's `UsageCore` and HEAD's
were each compiled against one identical probe that reads the *real* config, the *real* two
Claude snapshot files and the real `rowTemplate`, and prints every menu-bar segment, every
dropdown row, its tone and its note. Output was **byte-identical at `now`, +3h, +6h, +24h, +120h
and +200h** — that is, across both accounts' 5-hour resets, the inferred-empty wording, and past
the weekly boundary. The N-row refactor is invisible to Claude's display on this Mac's own data,
not merely on fixtures written against the new code. The by-eye check in the running bar is still
the clause's own standard.

**Clause 4 is pre-verified at the render seam, on the real snapshots.** A Kimi account in
`.tokenExpired` and in `.unreachable` leaves both Claude accounts' dropdown rows, tones and notes
identical to the Claude-only render, and their menu-bar segments a byte-exact prefix of it — the
Kimi segment only appends. Five corruptions of a credential file in a scratch `KIMI_CODE_HOME`
(truncated JSON, empty, wrong types, missing `expires_at`, not JSON) each read as no credential
and planned no request, and the file's mtime and size were unchanged by every read; a missing home
directory was not recreated. The real `~/.kimi-code/credentials/kimi-code.json` was never written
by any of this work — mtime `Jul 31 00:38:24`, 1502 bytes, before and after. The live check the
clause actually asks for — Wi-Fi off, watch the real bar — is the human's.

**Clause 2's first console comparison passed, on a live payload.** At 02:46 on 2026-07-31 the
user ran a kimi turn to refresh the token; a single `GET /coding/v1/usages` through the app's own
credential read, transport and parser returned HTTP 200 with weekly `limit 100, used 51,
remaining 49` and the sole 300-minute row `limit 100, remaining 100` (no `used` key — the
zero-omission ticket 01 documented). The app renders that as `5h 0%` and `7d 51%`, and **the user
compared both figures against the Kimi console and reported they agree.** One comparison is not
the fortnight this clause asks for, but the safety net under decision 11 has now actually been
pulled once, on live data, rather than assumed.

**One observation that bears directly on the map's second fog patch.** The three saved live
payloads put Kimi's 5-hour window at **0%, 0% and 1%** while its weekly sat at **27%**, and the
live payload above repeats the pattern more starkly: the bar reads `kimi-code 0%` while the
number actually moving is the weekly **51%**. That is the "is the 5-hour window the right primary
for Kimi" question showing up on the very first render. Put to the user at that moment, the
decision was explicitly to **let real use decide** rather than reopen decision 3 now — so it
stays fog, with a live data point recorded against it.

Also worth the next session's attention: both windows' `resetTime` share the same `:16:12`
minute-and-second offset, which looks like an anchored schedule rather than a window rolling from
first use — the first fog patch's concern, not yet evidence either way.

**Two things to watch that only real use can judge:**

- `menuWillOpen` is new in this work (v0.1.4 had no `NSMenuDelegate`). The dropdown-open poll is a
  network round trip, so a fresh Kimi figure can only ever land in the *next* open, and
  `refresh()` reassigns `statusItem.menu` while the current one is opening. If the dropdown ever
  flickers, closes, or shows a Kimi row one open behind, that is the mechanism.
- The token was expired at install time (`expires_at` 00:53, checked 02:38), which is the routine
  clause-3 state after under two hours of not using kimi — not several days. Whether it *reads*
  as routine is still the human's judgement in the bar.

Left for the run itself: clauses 1, 2 and 3 in full, the by-eye halves of 4 and 5, and the verdict
on decisions 5 and 11.
