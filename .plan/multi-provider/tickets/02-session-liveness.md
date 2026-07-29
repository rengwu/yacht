---
type: task
blocked_by: []
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
