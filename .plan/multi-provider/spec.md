# Spec — Kimi Code alongside Claude in Yacht

Settled 2026-07-27/28 in a `grill-me` session (eleven decisions, one question at a time).
This document is the design; the map's tickets implement it and do not re-litigate it.

## The problem

Yacht shows Claude Code subscription usage in the menu bar. The user also runs Kimi Code
(`kimi`) on a paid plan and wants both visible in one glance.

## Why the tap does not extend

Yacht's whole architecture rests on Claude Code's status-line hook: it fires every turn,
hands over a `rate_limits` block for free, and the app is a passive reader of a file it never
had to ask for. No network, no credentials, no failure modes.

**Kimi has no equivalent.** No status-line concept; `hooks = []` in `config.toml` is a
different mechanism. Locally it records `usage.record` events with raw per-turn token counts,
but those cannot answer "how much of my plan is left": they never learn the plan ceiling and
silently miss anything run on another machine or on kimi.com.

Server-side truth is reachable at an authenticated endpoint. That makes Kimi a **pull**
provider in an app built entirely around **push** — the central asymmetry every decision below
navigates.

## Accepted risk — a deliberate reversal

[`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope) rejected exactly this
architecture:

> **Polling usage while Claude Code is not running.** This would require reaching an
> undocumented endpoint with credentials lifted from the keychain. […] it is unsupported, it
> can break without warning on a server change, and the failure mode is silently wrong numbers
> about a limit the user is relying on.

That rejection assumed a supported alternative existed. It did, for Claude. It does not for
Kimi: it is poll or carry no Kimi number at all.

The reversal was put to the user on 2026-07-28 together with the option of a payload
schema-guard that would render dimmed-with-reason on drift instead of a number. **The user
declined the guard.** Kimi is therefore explicitly **best-effort**: Claude remains the
authoritative provider, and a Kimi server-side change can render wrong numbers without warning
until a human notices. This is a known, accepted cost — not an oversight, and not a bug to be
filed later.

## The endpoint

`GET https://api.kimi.com/coding/v1/usages`, bearer-authenticated. Undocumented; the path is
built by `managedUsageUrl(baseUrl)` in the kimi binary as `${base_url}/usages`.

**Do not trust `toWireUsage` in that binary** — it is the *local `kimi web` server* reshaping
this payload for its own UI, a different layer, and an earlier reading of it produced a wrong
schema. The real response, captured live 2026-07-28 (HTTP 200) and saved as
[`assets/kimi-usages-fixture.json`](./assets/kimi-usages-fixture.json):

```json
"usage":  {"limit":"100","remaining":"100","resetTime":"2026-08-04T02:16:12Z"},
"limits": [{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
            "detail":{"limit":"100","remaining":"100","resetTime":"2026-07-28T11:16:12Z"}}],
"parallel":{"limit":"10"}, "totalQuota":{}, "subType":"TYPE_PURCHASE",
"user":{"membership":{"level":"LEVEL_BASIC"}}
```

Traps, all confirmed against the live response:

- **No `label` field.** A row's identity is its `window` — `{duration: 300, timeUnit:
  TIME_UNIT_MINUTE}` is the 5-hour window. Labels are derived, never read.
- **`remaining`, not `used`.** Percentage math inverts: `used = limit - remaining`.
- **Numbers are strings.** `"100"`, not `100`.
- **The two windows are shaped differently.** Weekly is the top-level `usage` object with no
  `window` at all; the 5-hour is the sole entry in `limits[]`. The adapter synthesises two rows
  from two different shapes — this is not one uniform array.
- **No `extra_usage` upstream.** `totalQuota` is `{}`.
- **`parallel.limit` is a concurrency cap**, not a usage window. Not a row.
- The capture was taken at full quota (100/100 on both), so *decrementing is unverified*.
  Membership reads `LEVEL_BASIC` / `TYPE_PURCHASE`, which names no plan tier.

## Decisions

1. **Source.** Poll the authenticated `/usages` endpoint. Not local wire-log estimation —
   that can neither learn the ceiling nor see other machines.
2. **Model.** Generalise `Snapshot` from fixed `fiveHour`/`sevenDay` to N rows of
   `{label, used, limit, resetsAt}`; Claude becomes the two-row case. Rows carry **absolute**
   counts because Kimi counts and Claude reports percentages — `{used, limit}` absorbs both
   without a per-provider special case.
3. **Bar rows.** Hardcode 5-hour primary, weekly secondary. A per-provider row picker was
   designed and then **dropped** on 2026-07-28, when the live payload showed Kimi has exactly
   two windows of the same two kinds as Claude — the picker could only ever offer the choice
   between the only two things there are. The N-row model stays for a future third provider.
4. **Credentials — read-only, never refresh.** Yacht reads `~/.kimi-code/credentials/` and
   never writes it. Expired token renders as the existing dimmed no-data state until the user
   next runs `kimi`. **This is safety-critical:** kimi persists rotated refresh tokens
   (`data.refresh_token || refreshToken`), so a write-back — or an in-memory refresh that drops
   a rotated token — can log the user out of Kimi entirely, with no trace of the cause. Do not
   "improve" this into a refresh.
5. **Cadence.** Adaptive: ~60s while a kimi session is live, ~15min otherwise, plus an
   immediate poll when the dropdown opens. Under decision 4 the token is only valid while kimi
   is in use, so the slow phase is exactly when polling is least useful.
6. **Fuel packs.** Ignored — moot, the field does not exist upstream.
7. **Onboarding.** Register Kimi accounts through a provider picker in the existing Add Account
   flow; the Kimi path skips tap installation. No auto-detection: the account list stays
   something the user put there. `KIMI_CODE_HOME` is the analogue of `CLAUDE_CONFIG_DIR`, so an
   account stays a `(label, directory)` pair and multi-account works unchanged.
8. **Failure states.** The dropdown distinguishes "token expired — run kimi to refresh" from
   "couldn't reach Kimi". The bar stays dimmed for both — no new bar vocabulary. Expiry is
   routine under decision 4, so it must explain itself or the app reads as broken.
9. **Naming.** Repo and docs go provider-agnostic, settling the existing
   `another-claude-tracker` / `yacht` / `claude-usage-menubar` mismatch. **`claude-usage-tap.sh`
   keeps its filename** — it is written as an absolute path into users' `statusLine` settings
   across five released versions, and renaming it strands every existing install.
10. **Verification-first.** A real payload is captured before code is built. Done 2026-07-28;
    it invalidated decision 3 and the assumed schema, which is the whole argument for the rule.
11. **Best-effort, no schema guard.** See *Accepted risk* above.

## Out of scope

- **Refreshing the Kimi token**, in any form. See decision 4 — this is a safety boundary.
- **A payload schema-drift guard.** Offered and declined 2026-07-28.
- **Fuel packs / `extra_usage`.** No such field upstream.
- **`parallel.limit` as a displayed figure.** A concurrency cap is not a usage window.
- Everything ruled out by [`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope)
  that this effort does not explicitly reverse: history and trends, cost/token accounting,
  threshold notifications, any control over the agent itself, Windows/Linux, a configurable
  poll interval.
