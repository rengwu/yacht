---
type: task
blocked_by: [03]
claimed_by: s7df0a44c0624
claimed_at: 2026-07-30T17:43:41Z
---

# Settings: provider picker and Kimi account registration

## Question

AFK build ticket — decision 7 of [`spec.md`](../spec.md).

`Account` today is a `(label, configDir)` pair whose directory is its identity. Kimi keeps that
shape — `KIMI_CODE_HOME` is the analogue of `CLAUDE_CONFIG_DIR` — so accounts gain a provider,
not a new concept.

1. **`Account` carries a provider**, persisted in `AppConfig`. An existing config written by
   v0.1.4 has no such key and **must** load as Claude rather than failing or emptying the list.
2. **Add Account asks the provider first**, then takes a directory. The Claude path is unchanged,
   tap install and all. The Kimi path **skips tap installation entirely** — there is nothing to
   install — so the flow must not present, imply, or leave space for an Install Tap step there.
3. **No auto-detection.** A Kimi credential file on disk does not put an account in the bar. The
   account list stays something the user built deliberately; nothing appears unbidden.
4. **The account row in Settings reflects its provider** — a Kimi account shows no tap status,
   because tap status is meaningless for it, and showing a permanent "not installed" would read
   as a fault.

The settings window is `Sources/Yacht/SettingsWindowController.swift`, the largest file in the
app; keep it a dumb projection over `UsageCore` rather than growing provider logic inside it.
