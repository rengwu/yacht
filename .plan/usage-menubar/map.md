# Map — Claude Code usage menu bar app

## Destination

A working `ClaudeUsage.app`: a macOS menu bar app implementing [`spec.md`](./spec.md) —
both accounts' 5-hour usage live in the bar, both windows in the dropdown, fed by an
installed tap, launching at login, running on this Mac. Built and tested along the spec's
three seams; run for real, not just green tests.

## Notes

- **Domain:** native macOS (AppKit) menu bar utility, no Dock icon. Two Claude Code
  subscriptions = two config dirs (`~/.claude`, `~/.claude2`). See [`spec.md`](./spec.md) for
  the settled design and [`../handoffs/2026-07-13-usage-menubar.md`](../handoffs/2026-07-13-usage-menubar.md)
  for environment facts and traps.
- **Execution override.** This is an *execution* map, not a planning one: the design is
  already settled by a completed `grill-me` spec — **do not re-litigate its decisions**;
  implement them. Tickets carry code and experiments, not fresh decisions. Every ticket is
  therefore `task` type.
- **Implementation stays off the user's desk.** The build tickets are deliberately coarse and
  AFK — the agent runs them solo; the user never needs to open them. Do not split the build
  into finer tickets for its own sake, and do not ask the user about implementation choices.
  Surface something for their attention **only** when it is a genuine product design/behaviour
  question the spec didn't already decide — the acceptance ticket and the fog below are where
  that attention lives. The user is token-conscious; respect it.
- **Skills to consult:** `codebase-design` (UsageCore is a deep module — one pure function,
  UI as dumb projection), `domain-modeling` (Account, Snapshot, Limit Window, Tap are
  load-bearing terms), `review-code` (once built, especially the tap installer).
- **Two experiments decide real design** and must be run against the actual machine, not
  reasoned about: `CLAUDE_CONFIG_DIR` propagation and `SMAppService` viability. Everything
  downstream of each is blocked on it; nothing else is.
- **Never resolve more than one ticket per session.** Claim before working (set `claimed_by`
  + `claimed_at`, commit). This adapter is single-session — no concurrent work.
- **Ask before committing** anything to git — the user has not been asked yet.
- Open tickets are found by querying `tickets/` (frontier = open, unblocked, unclaimed), not
  listed here. Progress is derived by counting tickets, never written down.

## Decisions so far

<!-- one line per resolved ticket: gist + link. Empty until the first ticket resolves. -->

## Not yet specified

- **Reset-boundary UX, judged in practice.** The app treats a window past its reset time as
  empty, but has not *observed* it empty (no fresh session). Whether that should read as
  "empty" or as "unknown" is a product-behaviour call to make from watching real daily use, not
  up front. <clears-with: 05>
- **The permanent-dash explanation.** An API-key account registers fine and correctly shows a
  dash forever (no subscription rate limits). Whether that silent dash needs the tap-status
  badge to *say why* is a behaviour call decided by whether it actually confuses in use.
  <clears-with: 05>

## Out of scope

Ruled out by the spec's Out-of-Scope section, never charted as tickets — see
[`spec.md`](./spec.md#out-of-scope) for the reasoning: historical usage / trends / charts;
cost or token accounting; polling usage while Claude Code is not running (the rejected
keychain-OAuth path); threshold notifications (colour is the alert); any control over Claude
Code itself; Windows/Linux; distribution (signing, notarisation, updater); a configurable
poll interval.
