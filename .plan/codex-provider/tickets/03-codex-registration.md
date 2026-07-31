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
