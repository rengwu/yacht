---
type: task
blocked_by: []
assets: [.plan/codex-provider/spec.md]
---

# Bar keys on the provider's primary window

## Question

The menu bar's figure is hardcoded to the 5-hour window, justified by a comment stating that
*"both providers have exactly these two windows and nothing else."* Codex falsifies that: it
reports one window, the weekly, and a Codex account would therefore render as the no-data template
forever. Make the bar key on the row the **provider** calls primary, and teach the model to carry a
window it does not have a name for.

This ticket exists before any Codex code so that its proof stays legible: **Claude's rendered
output must be byte-identical afterwards.** Bundled with Codex work, a render regression and a
Codex bug become indistinguishable.

Implements [`spec.md`](../spec.md) decisions 3, 4 and 10.

## What to build

- **The bar's figure is the primary row**, declared by the adapter rather than hardcoded to a
  window. Claude and Kimi declare 5-hour — today's behaviour, unchanged. `{pct_7d}` renders `—`
  when the provider has no distinct second window.
- **`UsageWindow` gains `other(minutes:)`** so a window whose duration is neither 300 nor 10080
  becomes a row in its own right, labelled from its duration (`24h`, `30d`) rather than dropped.
- **Hand-written `Codable` for `UsageWindow`**, replacing the raw-value conformance that
  *Show Kimi's last-known figures instead of blanking on token expiry*
  ([`../../multi-provider/tickets/08-stale-kimi-figures.md`](../../multi-provider/tickets/08-stale-kimi-figures.md))
  introduced for its disk cache. An associated value has no raw value.
- **Warn/critical beats dimmed.** That ticket dimmed stale figures and accepted losing the colour
  channel *on the explicit premise* that the bar's primary sits near zero — false for a weekly
  primary by construction. It named this carve-out as the remedy in advance; take it now.

## Acceptance criteria

- [ ] Every existing `DisplayTests` assertion passes with its **expectations untouched** — this is
      the load-bearing regression test, not a formality
- [ ] A snapshot carrying only a weekly row renders that figure in the bar, rather than the no-data
      template
- [ ] A snapshot carrying only a 5-hour row still renders it, and `{pct_7d}` reads `—`
- [ ] A window of an unrecognised duration renders as its own dropdown row, labelled from the
      duration
- [ ] A cache file written before this change still loads — same back-compat discipline as the
      v0.1.4 fixture in `ConfigTests`
- [ ] A stale figure at or above the warn threshold keeps its warn/critical tone instead of dimming;
      a stale figure below it still dims
