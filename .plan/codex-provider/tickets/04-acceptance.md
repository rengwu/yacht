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
- [ ] Codex's figure matches what codex itself reports
- [ ] Verified from a Yacht actually launched at login, not from a terminal
- [ ] Each open fog patch in [`map.md`](../map.md) is either struck or restated with what was learned
- [ ] Any wrong Codex *number* is filed as a bug; a dark Codex section after a codex upgrade is
      recorded as expected breakage — decision 12 draws that line, and acceptance is where it is
      first tested
