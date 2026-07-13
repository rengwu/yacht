---
type: task
blocked_by: []
assets: [tap/claude-usage-tap.sh, tap/test_tap.sh, Sources/UsageCore/TapInstaller.swift, Tests/UsageCoreTests/main.swift]
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

## Answer

**The experiment: `CLAUDE_CONFIG_DIR` propagates. Single shared script confirmed.**
Installed a status line into `~/.claude2/settings.json` only (2026-07-13); the live
`claude2` session hot-reloaded it and the tap fired within seconds. Evidence:
`CLAUDE_CONFIG_DIR=/Users/rengwu/.claude2` was visible to the subprocess, the snapshot
landed in `~/.claude2/usage-snapshot.json` with the account's *real* rate limits
(five_hour 9%, seven_day 40%), and `~/.claude/` stayed clean. Settings were restored
byte-identical afterwards. The genuine snapshot was deliberately left in `~/.claude2/`.

**The tap** — [`tap/claude-usage-tap.sh`](../../../tap/claude-usage-tap.sh): the handoff's
verified core plus `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-snapshot.json"`. Black-box
suite [`tap/test_tap.sh`](../../../tap/test_tap.sh): 21/21 pass — writes on good payload;
no clobber on null/missing `rate_limits`; survives garbage/empty input; always exit 0;
prints nothing; no temp files; env routing (set → named dir, unset → `~/.claude`); missing
dir is a silent no-op.

**The installer** — `TapInstaller` in `UsageCore` (minimal SwiftPM scaffold created;
ticket 02 extends it). Pure `Data → Data` core + file wrappers; detect returns
installed / notInstalled / foreign(command); refuses (throws, file untouched) settings it
cannot parse. 21/21 pass, preservation of all seven real keys being the load-bearing case.

**Facts later tickets depend on:**

- **No XCTest on this machine** (Command Line Tools only, no Xcode). Tests are a plain
  executable target — `swift run UsageCoreTests` — with a tiny harness
  (`Tests/UsageCoreTests/Harness.swift`). Ticket 02's display-seam tests must extend this
  suite, not XCTest.
- The installer takes the tap command string as a parameter; the deployed script location
  (recommendation: copy into `~/Library/Application Support/ClaudeUsage/` and `chmod +x`
  on install) is wired up by the settings UI in ticket 03.
- The prototype moved to [`assets/prototype-main.swift`](../assets/prototype-main.swift);
  `build.sh` still points at the old path and stays broken until ticket 02 rewrites it.
