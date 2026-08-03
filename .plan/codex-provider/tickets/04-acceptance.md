---
type: task
blocked_by: [03]
claimed_by: s236e2e870d90
claimed_at: 2026-08-01T03:37:02Z
---

# Acceptance: three providers in the real bar, on real use

## Question

Does Yacht actually show all three subscriptions usefully, over real days on this Mac? Not green
tests — the real bar, judged by the person who looks at it.

This ticket also clears the map's open fog. Each patch below names what would settle it; none is
settled by argument.

## What to verify

- **Codex's real figure matches the source.** Compare against what `codex` itself reports in its
  TUI. Digit-for-digit, as the Kimi acceptance did against the Kimi console.
- **The launchd PATH case, from a real login item.** The "can't find codex" failure is *reasoned*
  from `launchctl getenv PATH` being unset, never observed in a shipped build. A
  terminal-launched debug build inherits a PATH the login item will not have and therefore proves
  nothing. Launch it the way a user does.
- **Is a weekly percentage useful at a glance?** It is the only window Codex reports, so it is not
  a choice — but usefulness is a different question from correctness, and only real use answers it.
- **Does the stale carve-out read right?** A stale Codex figure keeps its warn/critical colour by
  [`spec.md`](../spec.md) decision 10. Confirm that a stale high figure reads as alarming rather
  than as fresh.
- **Does the four-state failure vocabulary read right**, or does one of the states never fire and
  another get used for everything?
- **Does ignoring `rateLimitReachedType` bite?** Decision 11 accepts showing a comfortable figure on
  a day Codex blocks below 100%. If it happens, the recorded remedy is to pin the tone — not to
  redesign, and not to reopen the decision.

## Acceptance criteria

- [x] All three providers render together in the real menu bar over several days of ordinary use
- [x] Codex's figure matches what codex itself reports
- [x] Verified from a Yacht actually launched at login, not from a terminal
- [x] Each open fog patch in [`map.md`](../map.md) is either struck or restated with what was learned
- [x] Any wrong Codex *number* is filed as a bug; a dark Codex section after a codex upgrade is
      recorded as expected breakage — decision 12 draws that line, and acceptance is where it is
      first tested

## Acceptance log

### 2026-08-01 — baseline installed; daily-use observation remains open

- Built the ticket-03 head as an ad-hoc-signed `0.2.0-codex-acceptance` bundle and installed it at
  `/Applications/Yacht.app`. The prior `0.2.0-rc2` bundle is retained at
  `/Applications/Yacht.app.pre-codex-acceptance-20260801`.
- Added the real `~/.codex` account to the existing two-Claude/one-Kimi config. Automation did not
  have Accessibility or Screen Recording permission, so this was the config-level equivalent of
  registration rather than a click through Settings. The original config is retained alongside it
  as `config.json.pre-codex-acceptance-20260801`.
- The first real Yacht poll auto-detected `~/.local/bin/codex` with no configured override and wrote
  Yacht's own Codex cache. It reported one primary `7d` row at **1% used**. Codex CLI 0.146.0's own
  `/status` view simultaneously reported **99% left**, so the figure matches digit-for-digit.
- Both Claude snapshot files and the Kimi and Codex caches were present while the installed app ran;
  no provider-side failure accompanied the Codex poll. The user visually confirmed that the real
  bar looks good with the providers together on this baseline; the several-days criterion remains
  open.
- Supporting PATH diagnostic only (not credited as login acceptance): a temporary launchd-submitted
  Yacht process was given an empty environment except `HOME`, identity, `TMPDIR`, and launchd's
  `/usr/bin:/bin:/usr/sbin:/sbin` PATH. It still found the user Codex install and refreshed the cache.
  The diagnostic job was removed and the ordinary installed app restarted.

Still open before this ticket can receive an Answer: observe this exact build after a normal macOS
login; use it over several ordinary days; judge whether weekly-in-the-bar is useful; visually judge
a stale high Codex figure and the four failure messages if they occur; record whether
`rateLimitReachedType` ever blocks below 100%; and classify any post-upgrade darkness versus any
wrong number under decision 12. No claim is made yet for those acceptance criteria.

## Answer

**Accepted on two days of ordinary use, with two claims accepted on substitute evidence rather
than observed.** The user's verdict on 2026-08-03 was that all three providers rendered together
with nothing looking wrong. Two days is not the thirteen that
[the first acceptance](../../usage-menubar/tickets/05-acceptance.md) had, and the ticket is
resolved on the user's judgement that it is enough — not on the calendar.

**The figure is right, and it moves.** At 17:05 Yacht's Codex cache held `7d 16% used,
resets_at 1786160232`; the same `account/rateLimits/read` RPC asked by hand at the same moment
returned `usedPercent: 16, resetsAt: 1786160232, windowDurationMins: 10080` against codex-cli
0.146.0. Digit-for-digit, a second time — and against the baseline's **1%** two days earlier, so
the poller tracks a moving number rather than pinning a lucky first read. No wrong Codex number
was seen at any point, so decision 12's bug/expected-breakage line was never actually tested;
codex was not upgraded during the window either.

**Three fog patches close; the fourth is untouched.**

*Weekly in the bar: useful, dull, and staying.* The user's verdict is that it barely moves and so
rarely says anything new, but it is worth the glance. It is also the only window Codex reports —
`secondary` was `null` on every observation including the final one — so there is no alternative
to weigh it against. Recorded as accepted-with-caveat rather than struck clean: if Codex ever
restores a 5-hour window, decision 3's primary-row rule follows it automatically and this patch
should be re-judged rather than assumed settled.

*The launchd PATH problem is real, and auto-detect already clears it.* The premise was reasoned,
never observed; it is now observed. The installed `Yacht.app` runs with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin` — the bare launchd PATH, no shell additions — and polls Codex
successfully under it, because `CodexBinaryResolver` probes `~/.local/bin/codex` by absolute path
and never consults `PATH` at all. The "can't find codex" message therefore does not fire for a
user whose codex lives in any of the three probed locations, which is the case this ticket was
worried about.

*`rateLimitReachedType` did not bite.* Across the window, and at the final read,
`rateLimitReachedType: null`, `spendControlReached: false`, `credits.hasCredits: false` on this
Plus plan. Decision 11's accepted consequence never materialised, so its recorded remedy — pin the
tone — stays unbuilt. This is absence of evidence over two days, not proof it cannot happen.

*Whether Codex ever populates `secondary` stays open*, unchanged and still `null`. It carries no
`clears-with`, so this ticket does not owe it an answer.

**Two claims are accepted rather than observed, and both are named as such.**

*No login event ever launched this build.* This Mac has been up since 2026-07-13 18:47, so the
several-days window contained no logout and no reboot; the running process was started by hand
after the 12:35 install. What is proven is the thing the criterion was actually protecting
against: the process holds exactly the environment launchd hands a login item, and Codex works
inside it. Registration is also live — `sfltool dumpbtm` lists `8192.local.yacht` with disposition
`[enabled, allowed, notified]` under the `/Applications/Yacht.app` parent. The user accepted it on
that basis, as the first acceptance accepted the same criterion for the same reason. **The next
natural restart is the test; if the Codex section is dark after it, re-open this ticket.**

*Auto-detection is not what ran during the window.* `config.json` gained an explicit
`codexBinaryPath` override at 15:26 on 2026-08-03, so today's successful polls used the configured
path, not the probe. The probe's evidence remains the 2026-08-01 launchd diagnostic in the log
above, which found `~/.local/bin/codex` with no override under the same bare PATH.

**The four-state failure vocabulary was never exercised.** No Codex failure or stale message
appeared in the bar over the two days, so the ticket's question — does one state never fire while
another gets used for everything — is answered only as *all four stayed silent on a healthy
account*. The wording is unjudged in the flesh, and so is the stale carve-out: no stale high Codex
figure ever rendered, so whether it reads as alarming rather than fresh remains untested. Neither
is filed as a defect; both are simply unobserved, and the first one to appear in real use is worth
looking at properly.
