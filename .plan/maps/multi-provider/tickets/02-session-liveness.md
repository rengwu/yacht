---
type: task
blocked_by: []
claimed_by: s15b7d3f90b15
claimed_at: 2026-07-30T16:36:04Z
---

# Find a reliable signal that a kimi session is live

## Question

Decision 5 makes polling adaptive — ~60s while a kimi session is live, ~15min otherwise. That
rests on a signal nobody has identified yet, and the mechanism chosen shapes the poller's
design, so settle it before building one.

Investigate the candidates against the real machine, not by reasoning:

- **Process scan.** `kimi` runs as a Node-backed binary; establish what a running session looks
  like to `pgrep`/`NSRunningApplication`, and whether a backgrounded or `-p` print-mode run is
  distinguishable from an interactive one.
- **Session file mtime.** `~/.kimi-code/sessions/wd_*/session_*/` carries `state.json` and
  `agents/main/wire.jsonl`. Both are written during a turn. A recent mtime across the tree may
  be a cheaper and more honest "work is happening" signal than process presence — a sitting idle
  TUI is a live process doing nothing.
- **Token freshness.** `expires_at` in the credential file moves when kimi refreshes, which only
  happens on use. Coarse, but free and already being read.

Pick one (or a cheap composite), and say why the rejected ones lose. The bar to clear: it must
not spin up a filesystem watch or a poll loop that costs more than the network poll it is meant
to avoid, and a false "live" reading must degrade to wasted requests rather than wrong numbers.

Record the chosen signal and its observed behaviour — later tickets depend on it, and a wrong
guess here silently turns adaptive polling into fixed polling at one rate or the other.

## Answer

**The signal is `expires_at > now` in the account's credential file** —
`$KIMI_CODE_HOME/credentials/kimi-code.json`, the same file decision 4 already opens to read the
bearer token. No second file, no process scan, no filesystem watch. One `stat` + one small JSON
read, measured at **1.7 µs per `stat`** on this machine.

It wins on a property that only showed up once measured: **the access token's lifetime is 900
seconds**, and kimi renews it **lazily — only once it has actually lapsed**. That makes
`expires_at > now` mean, exactly, *"kimi made a Kimi API call within the last 15 minutes."* It is
not a proxy for liveness that happens to correlate; it is the same predicate as *"the token we
are permitted to use still works"*, which is the precondition for the poll being worth making at
all. Under decision 4 those two questions are one question, and this signal answers both with one
read.

### Observed, on this machine

The credential file carries `expires_in: 900`, `token_type: Bearer`, and `expires_at` as UTC
epoch **seconds** (no parsing ambiguity, no timezone handling).

| # | Observation | Result |
|---|---|---|
| 1 | Baseline: an interactive `kimi` TUI, PID 72913, state `S+`, alive **2 d 6 h** (since 2026-07-28 18:28) | Its token had been **expired 21 hours** (`expires_at` = 2026-07-30 03:13). Its own session tree's last write was 2026-07-28 18:33 — idle for two days. |
| 2 | One `kimi -p` turn, 2026-07-31 00:38 | Credential file rewritten at 00:38:24; `expires_at` jumped 1785352418 → 1785430404 (now + 15 min). The signal moves, on disk, on use. |
| 3 | A **second** `kimi -p` turn at 00:40, token still valid (~13 min left) | Credential file **not touched** — same mtime 00:38:24, same `expires_at`. |

Observation 3 is the load-bearing one, and it contains the trap this ticket was written to catch:

> **Use `expires_at`, never the file's mtime.** Refresh is lazy, so during continuous work the
> file can sit untouched for up to 15 minutes at a stretch. An mtime-freshness rule with any
> threshold under 15 minutes flaps between fast and slow *while the user is actively working* —
> precisely the "silently turns adaptive polling into fixed polling" failure the ticket warns
> about. The `expires_at` predicate does not flap: kimi renews the moment it lapses, so the
> predicate stays continuously true across an active session even though the mtime does not.

### Why the other two lose

**Process scan — wrong in both directions, and unfixable.** Observation 1 is the false positive
the ticket anticipated, and it is not a corner case: it is the state this machine was found in.
`ps` reports `S+` for two days on a TUI that has done nothing since minute one, so a process-scan
poller would sit at 60 s indefinitely against a token that has been dead for 21 hours — every
request a guaranteed 401. The false *negative* is just as bad: observation 2's `-p` run lived
**~5 seconds** end to end, so any sampler slower than that misses non-interactive runs entirely.
It also cannot be fixed by looking harder at the process: `argv` is the bare string `kimi` with
no arguments visible for the interactive case, and `kimi web`, `kimi acp`, `kimi vis` and
`kimi export` all present identically. Worst of all it is **global, and decision 7 is
per-account** — a process scan cannot say *which* `KIMI_CODE_HOME` is live, so with two Kimi
accounts registered it would drive both pollers fast whenever either one ran.

**Session-file mtime — honest, affordable, and answering a different question.** It is the most
truthful record of "a turn happened": `agents/main/wire.jsonl` was appended at 00:38:26 during
the probe. Cost is not what disqualifies it — a targeted glob of `sessions/*/*/agents/main/wire.jsonl`
runs in 0.77 ms, a full walk of the tree in 4.2 ms; both are free next to a network round trip,
though the walk grows with the session archive while the glob does not. Two things sink it:

1. **It answers "did kimi do work", not "can we reach the API".** Those come apart whenever kimi
   runs a turn against a non-Kimi provider — `config.toml` takes arbitrary `[providers.*]`
   entries and `-m/--model` selects per invocation. Session files are written, the Kimi token is
   never touched, the Kimi quota never moves. The tree would read "live" and drive fast polling
   at numbers that cannot have changed. (Structural, not observed — this machine has only
   `managed:kimi-code` configured.)
2. **Only the leaves carry the truth, so it cannot be shortcut.** Directory mtimes track entry
   creation, not turn activity: `wd_chartr-landing_…` shows 18:28:32 while its newest file is
   18:33:13, and `session_43d4a6d1…/` shows 02:58:48 while its own `state.json` shows 02:59:39.
   `state.json` is rewritten in place rather than atomically renamed, which is why the parent
   never moves. Any correct implementation must stat leaf files across the whole archive.

A **composite** was considered and is strictly wasted work: session-mtime can only add "live"
readings in the window where the token is dead, and in that window there is nothing to fetch.
It would buy nothing but 401s.

### The contract ticket 04 should build against

- **Predicate:** `credential.expires_at > now()`. Nothing else. Absent or unreadable file → not
  live, and no poll is possible anyway (decision 8's routine expired state).
- **Check it cheaply and often; poll the network adaptively.** The 1.7 µs `stat` is not the thing
  being rationed — the HTTP request is. Re-evaluating the predicate on a fixed ~60 s tick and
  letting it gate the request keeps start-of-session detection latency under a minute without
  costing anything, and satisfies decision 5's ~60 s / ~15 min cadence.
- **Both failure directions degrade correctly, as the ticket's bar requires.** False live (the
  ≤15 min tail after work stops) costs a handful of wasted requests against a still-valid token —
  correct numbers, slightly early. False not-live (a >15 min pause mid-session) costs staleness
  until the next turn, and the request it skipped would have 401'd regardless. Neither can
  produce a wrong number.

### Flagged for ticket 04 — not decided here

Two consequences of the 900-second TTL that the spec did not anticipate, both 04's to resolve:

1. **In the slow phase the poll is a guaranteed 401.** Expiry is knowable locally, before the
   request, from the same field. Decision 5's ~15 min slow poll is settled and I have not touched
   it, but 04 should note it can render decision 8's expired state without spending a request,
   and that the slow poll's real job is therefore to detect *recovery*, which the predicate
   already detects for free.
2. **"Token expired" is reachable with a kimi session open on screen** — any pause over 15
   minutes gets there, and observation 1 is that exact state. Decision 8's wording must not imply
   kimi isn't running; something closer to *"run a turn in kimi to refresh"* than *"kimi isn't
   running"*. Wording is a product call, not mine to make.

### Deliberately not done

- **No poller code.** Ticket 04 owns the credential read, the cadence and the error states, and
  names this ticket as its input. This one settles the signal and stops there.
- **The credential file was never written by anything I ran.** Both rewrites at 00:38:24 were
  kimi refreshing its own token during a normal `kimi -p` invocation — decision 4's boundary is
  intact.
- **Probe litter left in place:** the two probe turns created
  `~/.kimi-code/sessions/wd_kimi-probe_2c27c7b909d2/` and appended to `session_index.jsonl`.
  Deleting them means writing into kimi's own store, which is not a thing this effort does
  unasked. They cost two turns of Kimi quota and are safe to remove by hand.
