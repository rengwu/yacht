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

## Answer

Built provider-aware account registration and wired registered Kimi accounts into the existing
provider adapter.

- **Provider persists without breaking old configs.** `Account` now carries a `Provider`
  (`claude` or `kimi`) and encodes it in `AppConfig`. Its custom decoder defaults a missing
  provider to Claude, so the complete v0.1.4 fixture still loads both accounts in order instead
  of falling back to an empty config. Relabeling preserves the provider while directory remains
  the account identity.
- **Add Account is provider-first.** The generic **Add Account…** action first presents a
  Claude/Kimi picker, then opens a directory chooser whose copy names the selected provider's
  directory. Claude registration retains discovery, tap detection, installation and
  replacement. Kimi registration ends when the selected `KIMI_CODE_HOME` is registered; it
  never presents a tap-install step.
- **Settings projects provider facts from UsageCore.** Every account row identifies its
  provider. `Provider.usesTap` lives in UsageCore, so the Kimi row omits tap status and tap
  controls entirely rather than rendering a permanent not-installed fault or an empty
  placeholder. `AppDelegate.installTap` also refuses non-tap providers as a backstop.
- **Registration stays explicit.** Discovery remains Claude-only and a fixture `.kimi-code`
  directory is pinned as undiscovered. A Kimi credential file therefore cannot add anything to
  the account list.
- **Registered Kimi accounts now run.** The AppKit composition root owns one adaptive
  `KimiUsagePoller` per registered Kimi directory, removes it with the account, renders its
  provider-local state, and forwards dropdown opens for the immediate-poll trigger. Claude
  accounts continue through their independent snapshot/tap gatherer, so a Kimi failure cannot
  degrade Claude numbers.

Verification: `swift run UsageCoreTests` passes **201 assertions** with no failures, including
provider round-trip, v0.1.4 compatibility, provider-preserving relabel, no Kimi discovery, and
provider presentation facts. `swift build -c release` succeeds for both Yacht and the test
executable.

Deliberately left out: automatic Kimi discovery, any tap operation for Kimi, credential refresh
or write-back, schema-drift guards, and real-days acceptance; those remain out of scope or ticket
07 work.
