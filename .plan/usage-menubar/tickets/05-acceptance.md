---
type: task
blocked_by: [01, 03, 04]
---

# Acceptance: watch the real product with you

## Question

**HITL** — this is the ticket that wants your attention. Reaching the destination: on this Mac,
register both real accounts (`~/.claude`, `~/.claude2`), install the tap into each via the
app's own UI, run a real Claude Code session as each, and look at the result *together* —
both accounts' live 5-hour figures in the bar, both windows in the dropdown with correct
countdowns, freshness and colour.

This is where the product's design and behaviour get judged in the flesh rather than against
green tests, and where the deferred questions in **Not yet specified** get decided from real
use: does a past-reset window reading as "empty" mislead (vs "unknown")? does an API-key
account's permanent dash need the explanatory badge? Resolve when you're satisfied the app does
what the spec promised; graduate or re-open anything real use surfaces.

## Answer

**Accepted on evidence from thirteen days of real use, not a staged demo.** The judgement the
ticket asked for was made against a running product: `Yacht.app` 0.1.4 (`local.yacht`) has been
up continuously since 2026-07-14 16:15, and the user's verdict on 2026-07-27 was that it does
what the spec promised with no issues. Both accounts are genuinely tapped — `~/.claude` and
`~/.claude2` each point `statusLine` at the single installed
`~/Library/Application Support/Yacht/claude-usage-tap.sh`, vindicating ticket 01's
`CLAUDE_CONFIG_DIR` finding in production — and both were writing live subscription figures
minutes before resolution (`~/.claude` 5h 2% / 7d 86%, `~/.claude2` 5h 4% / 7d 73%, both
5-hour windows resetting 22:30 that evening). Two accounts, two independent snapshot files,
both windows, real numbers, sustained.

**Both fog patches close without code changes.**

*Reset-boundary UX: "empty" is right, and stays.* Thirteen days of use crossed many 5-hour
resets with no fresh session to confirm them, so the inferred-empty state was on screen
repeatedly rather than hypothetically. It never read as the app claiming something it did not
know. The spec's honest fallback — showing the window as unknown — is therefore *not* taken;
the dropdown's plain wording about the inference carries the weight on its own. The question is
settled by observation, which is exactly why it was deferred to here.

*The permanent-dash explanation: closed unbuilt.* The case never arose — both registered
accounts are subscriptions producing data, so no account ever sat silently dashed. Rather than
build an explanation for a confusion that has not happened, the tap-status badge stays as it
is. Re-open only if an API-key account is ever registered here.

**One claim in the destination is knowingly unexercised: launch at login has never faced a
real boot.** This Mac last booted 2026-07-13 18:47 and the app was started by hand the next
day, so the login path has not run for real. Ticket 04 proved the mechanism as far as a
running system can be asked to prove it — `SMAppService.mainApp.register()` succeeded on the
ad-hoc sealed bundle, a *fresh* process read `.enabled`, and `sfltool dumpbtm` listed the item
enabled against the bundle id — but registration proven is not a login observed. The user
chose to accept it on that evidence and let the next natural restart be the test. If the icon
does not appear on its own after a reboot, this ticket re-opens; nothing else is waiting on it.
