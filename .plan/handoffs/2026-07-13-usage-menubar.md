# Handoff — Claude Code usage menu bar app

**Date:** 2026-07-13
**Repo:** `~/Desktop/Projects/claude-usage-menubar` (new, git-initialised, nothing committed yet)
**Status:** Designed and specified. **Nothing built.** Next session implements.

> ⚠️ This work is **not** part of the `wayfinder` project. The session's shell happened to
> start in `~/Desktop/Projects/wayfinder`, and the Pocock skills were read from there, but
> every artifact belongs to `claude-usage-menubar`. Do not write code into wayfinder.

## Read first

**[`.plan/usage-menubar/spec.md`](../usage-menubar/spec.md)** — the full spec. Problem, solution,
34 user stories, implementation decisions with rationale, three test seams, out-of-scope.
It is the product of a `grill-me` session; every decision in it was put to the user and
chosen by them. **Do not re-litigate those decisions** — implement them, or come back with
new evidence.

This document covers only what the spec does *not*: environment facts, what's on disk,
what's still unverified, and the traps.

## The one thing that could invalidate the design

**It is unverified that `CLAUDE_CONFIG_DIR` is visible to the status line subprocess.**

The entire multi-account design rests on a single shared tap script discovering *which*
account it is running for by reading that environment variable. The reasoning is sound —
the alias sets it as an env prefix, `claude` inherits it, and its children should inherit
it in turn — but **it was never actually tested**, because doing so requires installing the
tap into a `settings.json`, and the user (rightly) had not yet approved that.

**Verify this before writing any Swift.** It is cheap: install the tap into `~/.claude2`
only, run `claude2`, and confirm the snapshot lands in `~/.claude2/` and not `~/.claude/`.

If the variable does **not** propagate, the design is not dead — the fallback is one tap
script per config directory with its own path baked in, at the cost of the "single shared
script" property. The spec's domain model survives either way.

## Environment facts (all verified this session)

| Fact | Value |
|---|---|
| Claude Code | v2.1.207, at `~/.local/bin/claude` |
| Two accounts | `alias claude2='CLAUDE_CONFIG_DIR=~/.claude2 claude'`; plain `claude` → `~/.claude` |
| macOS | 27.0 |
| Swift / SwiftPM | 5.9.2 / 5.9 |
| `jq` | 1.7.1 (present; the tap depends on it) |
| Menu bar hosts | **None** — no SwiftBar, no xbar. Hence a native app. |
| Existing LaunchAgents | 7 (yabai, skhd, sketchybar, alt-tab, …) — the user is at home with this mechanism |

**The data source.** `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` arrives
in the status line JSON payload. Confirmed two ways: documented at
<https://code.claude.com/docs/en/statusline> ("appears only for Claude.ai subscribers
(Pro/Max) after the first API response in the session"), and all five field names found in
the installed binary. `used_percentage` may be **fractional** (docs example: `23.5`).
`resets_at` is **unix epoch seconds**.

**Approaches already ruled out — do not re-derive these:**

- There is **no pull endpoint**. No `claude usage` subcommand exists (checked the CLI's full
  command list). The data is *pushed* to a status line or not at all.
- **Analytics API / Usage-and-Cost API** — Admin-API, org-scoped, Team/Enterprise. Does not
  expose an individual Pro/Max subscriber's rate limit windows.
- **OpenTelemetry** — exports while Claude Code runs, so it is session-bound exactly like the
  tap, but needs a collector. Strictly more infrastructure for no more data.
- **The undocumented OAuth endpoint** (what third-party pollers use, with a token lifted from
  the keychain) — the *only* way to get truly continuous data, and **explicitly rejected by the
  user's design**: unsupported, breaks silently on a server change, and the failure mode is
  confidently-wrong numbers about a limit they're relying on.

## State on disk

**Exists, to be replaced:**

- `Sources/main.swift` — a working **single-account prototype**. It builds, runs, renders
  `◐ 24% · 41%` in the menu bar, and its dropdown was visually confirmed. It is superseded:
  it knows nothing of accounts, settings, or the tap. Mine it for the AppKit patterns that
  are known to work (`NSStatusItem`, `LSUIElement` accessory policy, attributed menu items),
  then delete it.
- `build.sh` — `swiftc` → `.app` bundle with a hand-written `Info.plist` (`LSUIElement`). Works.
  Must be rewritten to bundle the **SwiftPM** binary instead.

**Deliberately deleted (do not go looking for them):**

- `~/.claude/statusline-usage.sh` — the first tap. Had the hardcoded-config-dir bug.
- `~/.claude/usage-snapshot.json` — held **fake** test values (23.5 / 41.2). Removed so the
  first numbers the user sees are genuinely their own.

**Untouched, and this matters:**

- **Neither `settings.json` has been modified.** Verified current keys:
  - `~/.claude` → `attribution, effortLevel, enabledPlugins, model, permissions, skipDangerousModePermissionPrompt, theme`
  - `~/.claude2` → `attribution, model, theme`

  The user **interrupted a settings.json edit earlier in the session.** They hand-maintain
  these files. Write to them only on an explicit click in the app, never as a build step, and
  the tap installer must preserve all seven keys — that is the load-bearing test at seam 3.

## The tap contract (verified, minus one fix)

The original single-account script was tested against every edge case and **passed all of
them**: wrote on a good payload; did **not** clobber a good snapshot when `rate_limits` was
missing or `null`; survived garbage input; always exited 0; printed nothing; left no temp
files. The core was:

```bash
tmp=$(mktemp "${snapshot}.XXXXXX") || exit 0
if jq -ce 'select(.rate_limits != null)
           | {rate_limits: .rate_limits, updated_at: now}' >"$tmp" 2>/dev/null; then
  mv -f "$tmp" "$snapshot"        # atomic; the app may read at any moment
else
  rm -f "$tmp"                    # no rate_limits is NORMAL, not an error — write nothing
fi
exit 0
```

`jq -e` exits non-zero when `select` yields nothing, which is what makes the no-clobber
behaviour fall out of the pipeline rather than needing a second parse.

**The required change is untested:** `snapshot` must become
`"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-snapshot.json"`. That is the fix for the
account-collision bug *and* the thing the open question above is about.

## Suggested next steps

1. **Verify `CLAUDE_CONFIG_DIR` propagation** (above). Everything else is downstream of it.
2. Run the **`SMAppService` experiment**. The bundle is `adhoc, linker-signed`, `Info.plist=not
   bound`, `Sealed Resources=none` — raw `swiftc` output, which is exactly what that API tends
   to reject. Seal the bundle properly (`codesign --force --deep --sign -`) and try to register
   for real. If it refuses, fall back to a `~/Library/LaunchAgents` plist. **Decide this by
   experiment, not by reading.** The checkbox must report the system's actual state, not a
   stored intention.
3. Restructure to SwiftPM (`UsageCore` library, no AppKit + `ClaudeUsage` executable + tests),
   then build against the three seams in the spec.
4. Ask before committing — the user has not been asked yet, and `.plan/` is meant to be committed.

## Suggested skills

*(Only if available in your environment.)*

- **`to-tickets`** — break the spec into tracer-bullet tickets before writing code; the work
  splits cleanly along the three seams.
- **`domain-modeling`** — no `CONTEXT.md` exists yet. `Account`, `Snapshot`, `Limit Window`
  and `Tap` are now load-bearing terms with precise, hard-won meanings (especially *Account =
  (label, config dir)*, where the config dir is the identity and the shell alias is
  incidental). Worth crystallising before the code fixes sloppier names in place.
- **`codebase-design`** — `UsageCore` is meant to be a deep module: one pure
  (accounts, settings, now) → view model function, with the UI as a dumb projection. That
  principle is easy to erode the moment AppKit gets a decision of its own.
- **`review-code`** — once built, especially over the tap installer.
- **`grill-me`** — only if the `CLAUDE_CONFIG_DIR` verification fails and the design needs
  re-opening. Otherwise the decisions are made; implement them.
