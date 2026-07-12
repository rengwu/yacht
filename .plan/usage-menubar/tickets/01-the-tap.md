---
type: task
blocked_by: []
---

# Build the tap: status-line script + installer, per spec

## Question

AFK build ticket — no product decisions here, all settled by [`spec.md`](../spec.md). Deliver
the tap end to end:

1. **First, the one experiment that could change the design:** verify `$CLAUDE_CONFIG_DIR`
   reaches the status-line subprocess (install a throwaway script into `~/.claude2` only,
   preserving all keys; run `claude2`; confirm the snapshot lands in `~/.claude2/` not
   `~/.claude/`; clean up). If it propagates → one shared script,
   `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-snapshot.json"`. If not → one script per config
   dir. Either way the product behaviour is identical; record which path is real.
2. **The tap script** (shell): writes `rate_limits` atomically into the account's own config
   dir, prints nothing, always exits 0; does **not** clobber a good snapshot on a null/missing
   `rate_limits`; survives garbage. Black-box tested (fixtures in → snapshot + exit asserted).
3. **The installer** (in UsageCore): install + detect, writing only on explicit request. The
   load-bearing test is **preservation** — a settings file carrying model/permissions/plugins/
   effort emerges with every key intact plus a status line. Idempotent; detection truthful on
   files with / without / with a foreign status line.

Save the script as a linked asset. Surface only a genuine surprise from the experiment.
