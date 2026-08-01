---
type: task
blocked_by: [02]
claimed_by: s5cc1648a02ae
claimed_at: 2026-07-31T18:28:02Z
---

# Settings: register a Codex account

## Question

Make the Codex provider reachable. The user picks Codex in the existing Add Account flow, points at
a `CODEX_HOME` directory, and sees a figure — without meeting a second way to register a
subscription.

Implements [`spec.md`](../spec.md) decisions 7 (the visible half) and the `Provider` additions.

## What to build

- **`Provider` gains `.codex`** — displayed as "Codex", folder picker labelled for a *home* folder
  (`CODEX_HOME` is a home directory, like Kimi's, not a config directory like Claude's), and
  `usesTap` false so the Kimi precedent of skipping tap installation carries over unchanged.
- **No auto-detection.** The account list stays something the user deliberately put there — the
  principle multi-provider decision 7 settled. The presence of `~/.codex` on disk never creates an
  account.
- **Multi-account works unchanged.** Two Codex accounts are two `CODEX_HOME` directories; the
  `(provider, label, directory)` identity already carries it.
- **The resolved codex binary path is shown in Settings and is editable**, persisted once per
  machine rather than per account — the binary is a property of the install, the account is a
  directory. Showing it is the point: this is the same trap acceptance caught once with the tap,
  where *"a working status line is silent, so a broken one looks identical to 'no session yet.'"*
  A wrong pick must be diagnosable.
- **Config back-compat.** A settings file written before this change must lose nothing — the
  discipline `AppConfig` already documents, where every field decodes optionally.

## Acceptance criteria

- [ ] Codex appears in the provider picker and registers against a chosen `CODEX_HOME`
- [ ] The Codex path shows no tap installation step or status
- [ ] Two Codex accounts on different directories track independently
- [ ] The resolved binary path is visible, editable, and persisted across launches
- [ ] An override path that does not exist reports "can't find codex" rather than failing silently
- [ ] A config written before this change still loads with all accounts and settings intact
- [ ] Registering a Codex account leaves existing Claude and Kimi accounts untouched

## Answer

Built the complete registration and Settings path from an explicitly chosen `CODEX_HOME` to the
Codex provider core landed in ticket 02.

**Provider and registration.** `Provider.codex` now projects “Codex”, labels the folder picker
“Codex home folder”, and declares `usesTap == false`. The existing Add Account picker therefore
registers Codex through the same flow as Claude and Kimi, while the existing `.claude*` discovery
remains the only discovery path — a `.codex` directory is explicitly tested not to appear there.
Account registration still appends one `(provider, label, directory)` entry without rewriting the
list, and two Codex entries with different directories survive persistence independently.

**Runtime composition and display.** `AppDelegate` owns one `CodexUsagePoller` per registered
Codex directory, restores and writes each account's last-known snapshot through the Yacht-owned
Codex cache, forwards dropdown opens to every poller, and maps each poller's state into the pure
`AccountState`/`render` seam. The renderer exposes all four settled actionable failures, carries
stale figures with their age and failure reason, and leaves Claude and Kimi on their existing
independent paths. A normal Codex snapshot now produces the weekly figure in the bar; tests render
two registered Codex homes with distinct percentages.

**One machine-wide executable.** `AppConfig.codexBinaryPath` is optional on decode and global to
the install, not stored on an account. Settings always shows the exact configured path or, when
unset, the path found by `CodexBinaryLocator`; it is editable, accepts `~`, persists immediately,
and has an Auto-detect action that clears the override. A configured path is authoritative: if it
is not executable Yacht leaves that wrong path visible and drives the existing “can't find codex”
state instead of silently executing a different candidate. Changing, installing, or removing the
resolved executable rebuilds the per-account clients without affecting other providers.

**Compatibility and evidence.** The v0.1.4 fixture still loads both accounts and every historical
setting, defaulting only the absent Codex path. A mixed Claude/Kimi config remains byte-for-byte in
place when Codex accounts are appended, and the new global path plus both Codex accounts round-trip
through `ConfigStore`.

- `swift run UsageCoreTests`: **351 pass, 0 fail** (329 before this ticket).
- `swift build -c release`: passes, including the AppKit target.
- `git diff --check`: clean.

Deliberately not done here: no account auto-detection, credential access, live installed-binary
probe, or login-item/daily-use acceptance run. Those first two are out of scope by design; ticket
04 owns the latter two real-environment checks.
