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

- [ ] All three providers render together in the real menu bar over several days of ordinary use
- [x] Codex's figure matches what codex itself reports
- [ ] Verified from a Yacht actually launched at login, not from a terminal
- [ ] Each open fog patch in [`map.md`](../map.md) is either struck or restated with what was learned
- [ ] Any wrong Codex *number* is filed as a bug; a dark Codex section after a codex upgrade is
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
