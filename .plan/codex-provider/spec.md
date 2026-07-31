# Spec — Codex CLI alongside Claude and Kimi in Yacht

Settled 2026-07-31 in a `grill-me` session (eleven decisions, one question at a time), on top of a
live verification pass done *before* any question was asked — the rule
[`../multi-provider/spec.md`](../multi-provider/spec.md) decision 10 exists to enforce. This
document is the design; the map's tickets implement it and do not re-litigate it.

## Problem Statement

Yacht shows Claude Code and Kimi Code subscription usage in the menu bar. The user has now
subscribed to Codex CLI and runs it daily on the same Mac. Codex has its own weekly quota that can
be exhausted, and today Yacht cannot see it at all — so the one place the user looks to answer
"how much have I got left?" answers it for two of their three subscriptions.

Worse than absent: **registering a Codex account today would render as a permanently dimmed bar
segment**, because the menu bar's figure is hardcoded to the 5-hour window and Codex reports no
5-hour window at all.

## Solution

A third provider. Register a Codex account through the existing Add Account picker by pointing at
a `CODEX_HOME` directory; Yacht then reads that account's usage by asking the codex binary itself,
over its first-party app-server RPC, and renders it through the same bar and dropdown as everything
else.

Unlike Kimi, this requires no credential handling, no undocumented endpoint, and no accepted risk of
silently wrong numbers.

## Verification, done first

Every fact below was captured live on this Mac against **codex-cli 0.146.0**, `plan_type: "plus"`,
on 2026-07-31, before any design question was put to the user.

**The interface.** `codex app-server` speaks JSON-RPC over stdio. After an `initialize`/`initialized`
handshake, `account/rateLimits/read` (params: `null`) returns the account's quota state. The
protocol has a **generated, versioned schema** — `codex app-server generate-json-schema --out DIR`
emits it, and `GetAccountRateLimitsResponse.json` is vendored at
[`assets/GetAccountRateLimitsResponse.schema.json`](./assets/GetAccountRateLimitsResponse.schema.json).
This is the single most important difference from Kimi and the reason most of the decisions below
diverge from that effort.

**The payload**, captured live and saved as
[`assets/appserver-ratelimits-plus.json`](./assets/appserver-ratelimits-plus.json):

```json
"rateLimits": {
  "limitId": "codex", "limitName": null,
  "primary":   {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1786010209},
  "secondary": null,
  "credits":   {"hasCredits": false, "unlimited": false, "balance": "0"},
  "individualLimit": null, "spendControlReached": false,
  "planType": "plus", "rateLimitReachedType": null
},
"rateLimitsByLimitId": {"codex": { …same… }},
"rateLimitResetCredits": {"availableCount": 0, "credits": []}
```

Traps and facts, each confirmed against a live response or the generated schema:

- **`secondary` is `null`.** Codex Plus reports **one** window, and it is the 10080-minute weekly.
  There is no 5-hour Codex figure to show. This is the fact that breaks the existing bar rule.
- **Windows are identified by duration, not by name.** `windowDurationMins` is a number. Older
  Codex builds put the 5-hour window in `primary` and the weekly in `secondary`; this plan has
  dropped the 5-hour and promoted the weekly into `primary`. **The position is a live signal, not
  a fixed fact about Codex.**
- **`usedPercent` is the only required field** in `RateLimitWindow` per the generated schema.
  `resetsAt` and `windowDurationMins` are both nullable, and `primary` itself is nullable.
- **Type differs by surface.** The RPC returns `usedPercent` as an integer (`10`); the rollout JSONL
  writes it as a float (`10.0`). Yacht reads only the RPC, but a decoder that hard-refuses a float
  is brittle for no gain.
- **`resetsAt` is a Unix timestamp in seconds**, not an ISO string — unlike both other providers.
- **`planType` is a real plan name** (`plus`), from a closed enum of thirteen. Kimi's endpoint
  offered nothing equivalent.
- **`CODEX_HOME` is honoured by the app-server**, verified by pointing it at an empty directory and
  watching `initialize` echo back that path. The `(label, directory)` account identity survives
  intact, exactly as `CLAUDE_CONFIG_DIR` and `KIMI_CODE_HOME` do.
- **Signed-out is a clean, distinguishable error**, not a hang or a zero:
  `-32600 "codex account authentication required to read rate limits"`.
- **A renamed or removed method is loud.** Calling a bad method name returns `-32600` with the full
  list of valid methods enumerated in the message. Method-level protocol drift is self-announcing
  and cannot silently produce a wrong number.
- **`auth.json` is not written by a read.** Codex owns and refreshes its own token; Yacht never
  reads, writes, or refreshes a Codex credential. The hazard that makes
  [`../multi-provider/spec.md`](../multi-provider/spec.md) decision 4 safety-critical **does not
  exist here**, because Yacht never touches the credential at all.
- **Cost per call**, measured: 0.31s to spawn and handshake, then 0.72–0.87s per RPC — a live
  network round-trip every time, no caching. An idle app-server holds **73 MB RSS**.
- **Spawning app-server writes to the user's `logs_*.sqlite` and `state_*.sqlite` WAL**, but
  **creates no rollout file** — verified across every probe in the session. This matters for
  liveness detection below.
- **`account/usage/read` also exists** and returns lifetime and daily token counts. Deliberately
  unused: token accounting is out of scope in both prior specs.

## Why this is not the Kimi architecture again

The Kimi effort reversed the original spec's rejection of credential-polling, and booked the
consequence as accepted risk: *a Kimi server-side change can render wrong numbers without warning
until a human notices.* That reversal was forced — for Kimi it was poll an undocumented endpoint or
carry no number at all.

**Codex forces nothing.** There is a first-party method, with a generated schema, reached by asking
the vendor's own binary, which handles its own authentication. Every element of the Kimi risk is
absent: no credential in Yacht's hands, no undocumented path, no schema reverse-engineered from a
binary that lied about it. Decision 11 of that spec is **left standing and not extended** — it
describes Kimi, and Codex does not inherit it.

## Decisions

1. **Source — the app-server RPC.** Yacht runs `codex app-server`, handshakes, and calls
   `account/rateLimits/read`. Rejected: tailing the rollout JSONL (free and passive, but only as
   fresh as the last codex turn and absent before the first); an authenticated HTTP poll of the
   ChatGPT backend (reintroduces the exact credential hazard decision 4 exists to prevent, for no
   gain now that a first-party method exists); and a hybrid of the two (two schemas, two ways to be
   wrong).

2. **Process lifecycle — spawn per poll, then exit.** Roughly 1s end to end. Holding one resident
   would save 0.31s and cost 73 MB, and the obvious prize — subscribing to the
   `account/rateLimits/updated` notification — is illusory: that notification fires only for turns
   running inside *our* app-server, and Yacht never runs turns. Nothing of Yacht's stays alive
   between polls. Also rejected: `codex app-server proxy` into the ChatGPT desktop app's resident
   server, which couples Yacht to another app's lifecycle.

3. **The bar shows the wire's `primary`.** The menu-bar figure is whichever row the provider calls
   primary, not a hardcoded window. Codex says so on the wire, so if OpenAI restores a 5-hour
   window it lands in `primary` and the bar follows with no code change and no wrong number. Claude
   and Kimi have no such field, so their adapters **declare** 5-hour primary — today's behaviour,
   preserved exactly. `{pct_7d}` renders `—` for a provider with no distinct second window.

   This supersedes the hardcoded `barWindow`/`barSecondaryWindow` rule, whose stated justification
   was that *"both providers have exactly these two windows and nothing else"* — a premise Codex
   falsifies. The per-provider row picker dropped on 2026-07-28 is **not** reinstated: the bar's
   meaning is still fixed per provider and still not a user setting.

4. **Window identity gains `other(minutes:)`.** `windowDurationMins` maps 300 → `fiveHour`,
   10080 → `weekly`; any other duration becomes a row in its own right, labelled from its duration
   (`24h`, `30d`). Nothing is silently dropped, and the N-row model finally does the job it was
   built for. Consequence to absorb: an associated value means `UsageWindow` needs hand-written
   `Codable` for the ticket-08 disk cache, since a raw value no longer suffices.

5. **Cadence — adaptive, ~60s live / ~15min idle, immediate on dropdown open.** Same shape as
   Kimi's decision 5, so one poller pattern serves both. **The justification is different and must
   not be confused**: Kimi's slow phase existed because the token is only valid mid-session, whereas
   a Codex poll returns true numbers at any time. Here the fast phase exists solely because quota
   moves only while codex runs.

6. **Liveness — the newest rollout file's mtime.** `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`.
   Verified faithful: for the three newest files, mtime matched the last event's own timestamp to
   the second. Immune to Yacht's own polling, because an app-server that starts no thread writes no
   rollout. Per-account for free, since it lives under `CODEX_HOME`.

   Rejected: `history.jsonl` mtime (one stat, but only moves on prompt submission — a 20-minute
   agent run would read as idle throughout); a running-process scan (rejected for Kimi on evidence,
   and worse here because the ChatGPT desktop app keeps a codex app-server resident permanently, so
   it would report "live" forever); and value-change backoff (the only option that would notice
   quota spent on another machine, but it can only speed up *after* seeing a change, missing the
   first turn after an idle spell by up to 15 minutes).

7. **Finding the binary — search known paths, prefill an editable field.** Yacht is a login item.
   `launchctl getenv PATH` is unset, so a launchd-spawned Yacht sees only
   `/usr/bin:/bin:/usr/sbin:/sbin`, and codex installs to `~/.local/bin` — **invisible**. Yacht
   probes `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, the npm global prefix, and the
   ChatGPT.app bundle, then shows the resolved path in Settings where the user can correct it.
   Prefer the user's own install over the bundled one, whose version may differ from the CLI's.

   The resolved path is **visible on purpose**. This is the same trap acceptance already caught once
   with the tap, recorded at `TapDeployment`: *"a working status line is silent, so a broken one
   looks identical to 'no session yet.'"* A wrong pick must be diagnosable, not silent.

8. **Strict decode — drift renders as a failure, never as a number.** A missing or retyped required
   field produces the failure state. Critically, `primary: null` means **no data, never 0%** — the
   alternative is a comfortable, catastrophically wrong "0% used". This is the guard **declined** for
   Kimi on 2026-07-28, and the reversal is deliberate: there it was extra machinery layered over an
   undocumented endpoint, here it is simply *not writing a default*, and it closes the last path to a
   silently wrong Codex figure now that method-level drift is already self-announcing. Additive
   changes (unknown keys, a new window duration) are absorbed, not rejected — see decision 4.

9. **Four named failure states**, one per user action:
   - **can't find codex** → point Yacht at it
   - **signed out** → run codex to sign in
   - **couldn't reach OpenAI** → wait
   - **unexpected reply from codex** → update Yacht

   Naming drift separately is what makes decision 8 pay off; folded into "unreachable", a contract
   change would hide inside the one error a user learns to ignore. This exceeds Kimi's two states
   (decision 8 there) because Codex genuinely has four distinguishable, differently-actionable
   causes — the first of which is, given decision 7, the likeliest thing a new user hits.

10. **Staleness — reuse ticket 08, and take its carve-out now: warn/critical beats dimmed.**
    Carry forward the last successful snapshot, cache it to disk, state the age in the dropdown, all
    as [`../multi-provider/tickets/08-stale-kimi-figures.md`](../multi-provider/tickets/08-stale-kimi-figures.md)
    decided. But that ticket's decision 2 accepted losing the colour channel to dimming **on the
    explicit premise** that *"the bar's primary is the 5-hour window, which sits near zero on this
    account."* Codex's primary is the weekly window — by construction the one that climbs toward
    100%. The premise is false here, and ticket 08 already names the remedy in advance: *"the fix is
    a carve-out — warn/critical wins over dimmed — not a redesign."* Taken now rather than shipped
    broken and waited on.

11. **Credits and block-state are ignored entirely.** `credits`, `rateLimitResetCredits`,
    `rateLimitReachedType` and `spendControlReached` are all read past. Yacht keeps exactly one
    vocabulary — a window of `{used, limit, resetsAt}` — consistent with both prior specs putting
    cost accounting and fuel packs out of scope, and with the codebase, which has never handled
    Claude's `extra_usage` either.

    **Accepted consequence, deliberate and recorded:** both `rateLimitReachedType` and
    `spendControlReached` can block Codex at *under* 100% of the window. Yacht will therefore show a
    comfortable figure on the day something blocks the user early. This was put to the user with the
    alternative of pinning the tone to critical on those flags, and **the user chose to ignore them**.
    Not an oversight, and not a bug to be filed later.

12. **Standing — authoritative for correctness, caveated for availability.** The two axes the Kimi
    spec ran together are split here. *Correctness:* Codex stands with Claude — first-party schema,
    self-announcing method drift, strict decode, no credentials touched; it cannot silently lie.
    *Availability:* `codex app-server` is marked `[experimental]` and the protocol already carries
    v1/v2, so it may break and the Codex section may go dark. **The spec records a stability risk,
    not an accepted-wrongness risk.**

## User Stories

1. As a Codex subscriber, I want my Codex weekly usage in the menu bar, so that one glance answers "how much have I got left?" for every subscription I pay for, not just two of three.
2. As a user with Claude, Kimi and Codex accounts, I want all three rendered by the same rules, so that I can compare them without translating between three display conventions.
3. As a Codex user, I want the bar to show the window Codex says binds me, so that the figure means something on a plan that has no 5-hour limit.
4. As a Claude user, I want my bar to keep showing the 5-hour window exactly as it does today, so that adding a third provider costs me nothing.
5. As a user, I want `{pct_7d}` to render "—" for a provider with only one window, so that I am not shown the same number twice and left wondering which is which.
6. As a user whose Codex plan gains a new quota window, I want it to appear as its own row labelled by its duration, so that a limit I am subject to is never invisible.
7. As a user whose Codex plan regains a 5-hour window, I want the bar to follow it automatically, so that I do not need a Yacht update to see the limit that now binds me.
8. As a user registering a Codex account, I want to pick a CODEX_HOME directory in the same Add Account flow, so that I do not learn a second way to register a subscription.
9. As a user with two Codex accounts, I want each one tracked separately by its own CODEX_HOME, so that multi-account works the same way it does for Claude and Kimi.
10. As a user registering Codex, I want no tap installation step, so that I am not asked to install something into a tool that does not have the concept.
11. As a user, I want Yacht to find my codex binary without being told where it is, so that registration works on a normal install with no configuration.
12. As a user with codex installed somewhere unusual, I want to correct the path in Settings, so that an unlucky install layout does not lock me out of the feature.
13. As a user, I want to see which codex binary Yacht resolved, so that a wrong pick is diagnosable rather than presenting as "Codex just doesn't work".
14. As a user who launches Yacht at login, I want Codex to work from a login item, so that the feature is not quietly broken in the only way I actually start the app.
15. As a user actively running codex, I want the figure refreshed about every minute, so that the number is sharp at the moment I am burning quota.
16. As a user not running codex, I want polling to back off, so that Yacht is not spawning a process a minute all day to track a number that is not moving.
17. As a user, I want opening the dropdown to poll immediately, so that deliberately looking always gets me the current number.
18. As a user, I want Yacht's own polling never to be mistaken for codex activity, so that the app cannot trap itself in permanent fast polling.
19. As a user, I do not want Yacht to touch my Codex credentials in any way, so that no Yacht bug can affect my ability to sign in to Codex.
20. As a user, I want a signed-out Codex account to say "signed out — run codex to sign in", so that I know the fix is thirty seconds of my time.
21. As a user, I want "can't find codex" said plainly, so that the launchd PATH problem is a message rather than a mystery.
22. As a user, I want a network failure distinguished from a contract change, so that I know whether to wait or to update Yacht.
23. As a user, I want a Codex payload Yacht cannot parse to show a failure, so that I am never shown a number that was invented from a missing field.
24. As a user, I want an absent `primary` to read as no data rather than 0%, so that "you have used nothing" is never a lie told by a default value.
25. As a user, I want my last known Codex figure carried forward when a poll fails, so that a network blip does not blank the bar I rely on.
26. As a user, I want a carried-forward figure marked as such, so that I can tell a live number from an old one.
27. As a user, I want a stale figure at 95% to keep its alarm colour, so that staleness never mutes the warning at the exact moment it matters most.
28. As a user, I want the dropdown to state how old a stale figure is in relative terms, so that I can size my doubt without doing clock arithmetic.
29. As a user, I want my Codex figure restored at launch from disk, so that a reboot or an app update does not blank the bar until the first poll returns.
30. As a user, I want a Codex row past its own reset to render empty, so that a days-old cached snapshot self-corrects rather than showing a quota that has since refilled.
31. As a user, I do not want Yacht holding a 73 MB process resident, so that a menu bar utility stays a menu bar utility.
32. As a user, I want Codex failures never to affect my Claude or Kimi figures, so that one provider's outage cannot degrade the others.
33. As a maintainer, I want the captured payload and generated schema committed, so that the decoder is built and tested against reality rather than against a reading of a binary.
34. As a maintainer, I want Codex's standing recorded as correctness-authoritative but availability-caveated, so that the next reader knows a dark Codex section is expected breakage and a wrong Codex number is a bug.
35. As a maintainer, I want Kimi's best-effort risk left scoped to Kimi, so that a posture forced by one provider's constraints is not inherited by a provider that does not share them.

## Implementation Decisions

**Modules built**

- **`CodexBinaryLocator`** — pure: an ordered list of candidate paths plus an injected existence/executability probe, yielding a resolved path or not-found. Candidates in order: the user's configured override, `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, npm global prefix, the ChatGPT.app bundle. No shell is invoked.
- **`CodexUsageParser`** — pure: RPC result bytes → `Snapshot` or a typed failure. Strict on required fields; tolerant of int-or-float `usedPercent`; ignores unknown keys. Maps `windowDurationMins` through decision 4 and converts the Unix-seconds `resetsAt` to a `Date`.
- **`CodexResponseStateMachine`** — pure: one RPC outcome (result, JSON-RPC error, spawn failure, timeout, decode failure) → `CodexProviderState`, mirroring `KimiResponseStateMachine.reduce`. A `carryForward(_:lastKnown:)` step matching the one added for Kimi in ticket 08.
- **`CodexPollSchedule`** — pure: liveness mtime, clock, and trigger → a poll decision carrying the interval, mirroring `KimiPollSchedule.plan`.
- **`CodexClient`** (impure, below the seams) — spawns the binary, performs the `initialize`/`initialized` handshake, issues `account/rateLimits/read`, enforces a timeout, and terminates the process.

**Modules modified**

- **`Provider`** gains `.codex`: `displayName` "Codex", `configDirectoryLabel` "Codex home folder" (`CODEX_HOME` is a home directory, like Kimi's), `usesTap` false.
- **`UsageWindow`** gains `other(minutes:)` and hand-written `Codable`, replacing the raw-value conformance ticket 08 introduced.
- **`Snapshot`** gains a notion of which row is primary, so the bar can key on it. Claude and Kimi declare 5-hour; Codex takes it from the wire.
- **`AccountSourceState`** gains a `.codex(CodexAvailability)` case carrying the four failure reasons of decision 9.
- **`AppConfig`** gains a global codex binary path override — one per machine, not per account, since the binary is a property of the install and the account is a directory.
- **`render(...)`** replaces the `barWindow` constant with the primary-row rule, and applies the warn/critical-beats-dimmed carve-out of decision 10.
- **Settings** gains the Codex option in the provider picker and the resolved-binary path field.

**Contracts**

- Request: `initialize` with `clientInfo{name, version}`, then the `initialized` notification, then `account/rateLimits/read` with `params: null`.
- Response: `GetAccountRateLimitsResponse`. Yacht reads only `rateLimits.primary` and `rateLimits.secondary`; `rateLimitsByLimitId`, `credits`, `rateLimitResetCredits`, `individualLimit`, `planType`, `limitName`, `spendControlReached` and `rateLimitReachedType` are all read past (decision 11).
- Environment: `CODEX_HOME` set to the account's directory. Nothing under it is ever written.
- Cache writes go to Yacht's own support directory, alongside ticket 08's Kimi cache.

## Testing Decisions

A good test here asserts **externally observable behaviour** — the text and tone Yacht renders, or the state a pure function returns — never how it got there. The existing suite is the model: `DisplayTests` asserts rendered strings against templates, and its ~130 assertions must pass **untouched** for Claude, which is the load-bearing regression test that decision 3 costs existing users nothing.

Seams under test, in preference order:

1. **`render(...)`** — the existing top seam, and where most Codex behaviour is proved: the primary-row rule, `{pct_7d}` rendering "—", `other(minutes:)` labels, the four failure messages, the reset boundary, and the warn/critical-beats-dimmed carve-out. **No new display seam is introduced.**
2. **`CodexUsageParser`** — fed by the committed live fixture. Asserts strict decode: absent `usedPercent` fails rather than defaulting; `primary: null` yields no data rather than 0%; int and float `usedPercent` both parse; unknown keys are ignored; unknown durations become `other(minutes:)`; Unix-seconds `resetsAt` converts correctly.
3. **`CodexPollSchedule`** — injected clock and mtime. Asserts the live/idle transition, the immediate poll on dropdown open and on a live transition, and that a poll is not triggered by Yacht's own activity.
4. **`CodexBinaryLocator`** — injected probe. Asserts candidate ordering, the user override winning, preference for the user's install over the bundled one, and the not-found result.

Prior art to follow directly: `KimiProviderTests` for the parser and state machine, `StaleFigureTests` for carry-forward, `ConfigTests` for provider projection and config back-compat. Back-compat is non-negotiable and already has a pattern — `ConfigTests` keeps a v0.1.4 fixture; the `UsageWindow` `Codable` change of decision 4 needs the equivalent, proving a cache written before this work still loads.

Process spawning and the JSON-RPC handshake stay **below** the seams and are not directly tested, matching how Kimi's URLSession call is treated. Tests run via `swift run UsageCoreTests` — no XCTest on this machine.

## Out of Scope

- **Reading, writing, or refreshing any Codex credential**, in any form. Yacht never opens `auth.json`. Codex owns its own token; that is the whole point of decision 1.
- **Token and cost accounting.** `account/usage/read` exists and returns lifetime and daily token counts. Deliberately unused — ruled out by [`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope) and not reversed here.
- **Credits, reset credits, and spend-control state** — decision 11, with its consequence explicitly accepted.
- **Tailing the rollout JSONL for usage figures.** It is read for one mtime and nothing else (decision 6).
- **Holding a resident app-server**, or proxying into the ChatGPT desktop app's — decision 2.
- **Pinning or version-gating the codex binary.** Yacht must not go dark because the user stayed current.
- **A user-configurable poll interval**, **history and trends**, **threshold notifications**, **any control over codex itself**, **Windows/Linux** — all inherited from [`../usage-menubar/spec.md`](../usage-menubar/spec.md#out-of-scope) and not reversed.
- **Reinstating the per-provider row picker** dropped on 2026-07-28. Decision 3 solves the same problem without a user-facing setting.
- **Extending Kimi's best-effort posture to Codex** — decision 12.

## Further Notes

- **Two decisions here are reversals of prior positions**, both deliberate and both argued from evidence that did not exist when the prior position was taken. Decision 3 supersedes the hardcoded 5-hour bar window, whose justification named a premise Codex falsifies. Decision 8 adopts the schema guard **declined** for Kimi, because over a first-party generated schema it costs nothing but the discipline of not writing a default.
- **Decision 10 is a carve-out ticket 08 authorised in advance.** It is not a re-litigation of that ticket; it is the escape hatch that ticket wrote for exactly this case, exercised on arrival rather than after the failure.
- **The in-flight collision is real and small.** Ticket 08 is mid-flight and has just made `UsageWindow` a `String`-backed `Codable` for its disk cache. Decision 4 replaces that with hand-written `Codable`. Sequence after 08 lands; do not race it.
- **Do not reach for the rollout JSONL as a usage source.** It carries a complete `rate_limits` block on every turn and looks like a free push-style tap, which is genuinely tempting. It was considered and rejected in decision 1: it is only as fresh as the last codex turn, absent before the first, and it encodes `usedPercent` as a float where the RPC uses an integer — a second schema to track for a strictly worse number.
- **The 73 MB figure is per resident app-server.** The ChatGPT desktop app already keeps one alive on this machine; decision 2 means Yacht does not add a second.
- **Verification-first held, and paid off again.** Every design question in this session was put to the user *after* the live capture. The capture is what revealed the null `secondary` — which alone invalidated the existing bar rule — and the launchd PATH problem, which no reading of documentation would have surfaced.
