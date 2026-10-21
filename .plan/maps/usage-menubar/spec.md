# Claude Code usage menu bar app

## Problem Statement

I run two Claude subscriptions side by side on one Mac, selected at the shell by two
aliases that point Claude Code at two different config directories with two separate
auth sessions. Today the only way to see how much of either subscription I have left
is to open a Claude Code session and type `/usage` — per account, one at a time.

That is the wrong shape for the question. "How much have I got left?" is a background
concern I want answered continuously and at a glance; instead it costs me a context
switch, and it only answers for whichever account that session happens to be running
as. I want to stop checking and just *know*, for every subscription at once.

## Solution

A macOS menu bar app that shows, permanently, the 5-hour usage of every subscription
I have registered:

```
◐ john 24% · jane 55%
```

Opening it reveals the full picture for each account — both the 5-hour and the 7-day
window, each with a bar, a percentage, and a countdown to when it resets — plus how
fresh the numbers are. A settings window lets me register accounts, label them,
choose when a number turns orange, and have the app launch at login.

### How it gets the numbers, and the constraint that follows

There is no endpoint to poll. Claude Code exposes subscription rate limits **only** by
pushing them into the JSON payload it hands to a status line command on each render.
So the app cannot pull; it must be *fed*.

The mechanism is therefore a **tap**: each account's Claude Code config is given a
status line command that writes the rate limit block to a snapshot file inside that
same config directory, and prints nothing (so no status line appears). The app watches
those snapshot files. This costs no tokens, makes no network calls, and needs no
credentials.

The unavoidable consequence — and the app must be honest about it rather than hide it —
is that **an account's numbers only refresh while that account is actually running
Claude Code.** Between sessions the snapshot is frozen. The app mitigates this two ways:
it always displays how stale the data is, and because each snapshot carries the window's
reset timestamp, the app can still show a live, correct countdown, and can *know* a
window has emptied once its reset time passes even with no fresh session to confirm it.

## User Stories

### Seeing usage

1. As a developer with a Claude subscription, I want my 5-hour usage visible in the menu bar at all times, so that I never have to open a session and type `/usage` to find out where I stand.
2. As a developer running two subscriptions, I want every registered account's 5-hour usage in the menu bar at once, so that I can see both without switching accounts.
3. As a developer, I want each account's number prefixed by a label I chose, so that I can tell at a glance which subscription is which.
4. As a developer, I want the 7-day figure kept out of the menu bar, so that the bar stays narrow enough to coexist with my other menu bar items.
5. As a developer, I want the dropdown to show both the 5-hour and 7-day window for every account, so that the deliberate, considered check is one click away even though the urgent number is always on screen.
6. As a developer, I want each window rendered as a bar as well as a percentage, so that I can read my position without parsing a number.
7. As a developer, I want a countdown to when each window resets, so that I can decide whether to stop working or just wait it out.
8. As a developer approaching my limit, I want the number to turn orange, so that I get warned before I get cut off rather than after.
9. As a developer very close to my limit, I want the number to turn red, so that "warning" and "about to fail" are visibly different states.
10. As a developer, I want each account coloured independently, so that one account being near its cap does not make a healthy account look alarming.

### Trusting what I see

11. As a developer, I want to see how long ago each account last reported, so that I can tell a live number from a stale one.
12. As a developer, I want an account that has never reported to show a dash rather than 0%, so that "I don't know" is never disguised as "you've used nothing".
13. As a developer, I want a window whose reset time has passed to show as empty, so that a stale pre-reset number does not keep alarming me about a limit that no longer applies.
14. As a developer, I want the countdowns to keep ticking even while no Claude Code session is running, so that the app stays useful when I'm not actively working.
15. As a developer whose account is registered but producing no data, I want to be told *why*, so that I am not left staring at a dash wondering whether the app is broken.

### Registering accounts

16. As a developer, I want the app to find my Claude config directories by itself, so that setting it up does not mean typing paths I could have been offered.
17. As a developer, I want to accept a discovered directory with one click, so that the common case is nearly zero-effort.
18. As a developer, I want to give each account a human label, so that the menu bar says "john" and "jane" rather than ".claude" and ".claude2".
19. As a developer, I want to register a config directory that lives somewhere unusual, so that auto-discovery being wrong is an inconvenience rather than a dead end.
20. As a developer, I want to remove an account, so that a subscription I no longer hold stops taking up menu bar space.
21. As a developer who adds a third subscription later, I want to register it the same way, so that the app is not silently built for exactly two.

### Installing the tap

22. As a developer, I want the app to tell me when a registered account is missing the tap, so that a silent dash becomes an explained, fixable state.
23. As a developer, I want to install the tap into an account with one click, so that I do not have to hand-edit JSON to get the app working.
24. As a developer who hand-maintains his Claude settings, I want the app to leave every other setting in that file untouched, so that installing the tap cannot cost me my model choice, permissions, plugins, or effort level.
25. As a developer, I want nothing written to my settings until I explicitly ask for it, so that registering an account is safe to do exploratorily.
26. As a developer, I want the tap to leave my Claude Code status line looking exactly as it does now, so that gaining a menu bar app does not cost me a row of terminal UI I never asked for.
27. As a developer running two accounts, I want each account's snapshot written inside its own config directory, so that one subscription's numbers can never overwrite the other's.

### Settings and lifecycle

28. As a developer, I want a settings window, so that the accounts list has somewhere to live that a dropdown menu could not host.
29. As a developer, I want to choose the percentage at which a number turns orange, so that the warning fires where *my* comfort threshold is.
30. As a developer, I want the app to launch at login, so that "constantly visible" survives a reboot.
31. As a developer, I want the launch-at-login checkbox to reflect whether it is *actually* registered with the system, so that the checkbox is a fact rather than a stored intention that may have silently failed.
32. As a developer, I want to quit the app from its own menu, so that it is not a process I have to hunt down.
33. As a developer, I want the app to have no Dock icon or app-switcher entry, so that a menu bar utility behaves like one.
34. As a developer, I want to add or relabel an account and see the menu bar update without restarting, so that configuration feels immediate.

## Implementation Decisions

### Domain model

- **An Account is a `(label, config directory)` pair, and the config directory is its identity.** The shell alias that selects it is incidental: it lives in the user's shell alias table, is unreadable to a GUI process, and does not even map one-to-one (two aliases may select one directory; a directory may be used with no alias). Registering "the `claude2` command" would force the app to shell out to an interactive shell and string-parse an alias definition to recover a path it could simply have been given. The config directory is a real path on disk, holds the auth session that defines the subscription, and is where that account's data will live.
- **A Snapshot is the rate limit block plus the time it was captured**, and it lives *inside the config directory it describes*. This makes each account self-locating and makes cross-account contamination structurally impossible rather than merely avoided.
- A snapshot holds up to two **Limit Windows** (5-hour, 7-day), each a used-percentage and a reset timestamp. Either may be independently absent, and both are absent for accounts that are not on a subscription plan or have not yet made an API call in a session.

### Architecture

- Two processes, deliberately: a **tap** written in shell that Claude Code executes, and a **reader** (the app) that Claude Code knows nothing about. They are coupled only by the snapshot file's location and shape. The app never launches Claude Code, and Claude Code never launches the app.
- The tap is **a single shared script referenced by every account**, made account-aware by reading the Claude config directory environment variable and defaulting to the standard location when it is unset. One script, N accounts. It must not hardcode the default config directory, or the second account will silently overwrite the first account's snapshot — the single most likely bug in this design.
- The tap **prints nothing and always exits successfully**, whatever it is fed. It is running inside the user's editor on every render; it must be incapable of either drawing UI they did not ask for or breaking the session that hosts it.
- The tap **declines to write** when the payload carries no rate limit block, rather than writing an empty one. Those payloads are normal (they occur before an account's first API response in a session), and treating them as data would erase a good snapshot with a null one on every fresh session.
- The tap writes **atomically** (write to a temporary file, then move into place), because the app may read the file at any moment and must never see a half-written one.

### The app

- The code splits into a **core library with no UI dependency** and a **thin UI layer that is a dumb projection of it**. The core owns the model, all display logic, and the tap installer; the UI layer owns only windowing, menus, and the status item.
- All display logic funnels through **one pure function from (accounts, settings, current time) to a fully-described view model** — every string, every colour, every bar, for both the menu bar and the dropdown. The UI renders that view model without making a single decision of its own. This is the app's primary test seam and the reason nearly all of its behaviour is testable without AppKit or a real clock.
- **Time is injected, never read ambiently**, in the core. The reset-boundary rule, the countdowns, and the staleness display are all functions of "now", and a core that reaches for the system clock cannot be tested at the boundaries that matter.
- The app **polls the snapshot files on a short timer** rather than watching them for changes. The timer is needed regardless — countdowns and staleness are relative to now and must redraw even when no file has changed — so a file watcher would be a second mechanism earning nothing.
- **The polling interval is not configurable.** It was proposed and cut: the app polls a local file whose freshness it cannot influence, so no value the user picks changes anything they can perceive. It would be a control that only appears to control something.

### Display rules

- The menu bar carries **the 5-hour window only, one figure per account**, labelled. The 5-hour window is the one that interrupts work; the 7-day is a slow burn checked deliberately. With N accounts and two windows each, showing everything would double the width of an already crowded bar to display a number that rarely moves.
- The dropdown carries **both windows for every account**, grouped by account, each with bar, percentage and reset countdown, plus the account's freshness and its tap status.
- **Colour is per-account and threshold-driven**: at or above the user's warn threshold a figure is orange, and at or above a derived critical threshold it is red. The user sets **one** number, and critical is derived from it. Two independently-settable thresholds would have to be kept correctly ordered by the user for the display to make sense, which is a constraint the app can simply enforce instead.
- **Absent data and zero usage are rendered differently.** A never-reported account shows a dash. A window past its reset time shows as empty, because it *is* empty — but the app has no fresh session to confirm this, so the dropdown says so plainly rather than presenting an inference as an observation.

### Tap installation

- The app **detects** whether each registered account's Claude settings already reference the tap, and surfaces the answer per account. An account that cannot produce data must never simply appear to have none.
- Installation is **offered, never performed silently**. The user hand-maintains these settings files; the app writes to one only on an explicit click.
- Installation **preserves every unrelated key** in the settings file. The target files carry model selection, permission rules, enabled plugins, and effort level. Clobbering them would be the most damaging thing this app could do, and it would do it to the very file the user is least likely to have backed up.

### Launch at login

- The modern system login-item API is preferred, **but it is not assumed to work**: the app bundle is ad-hoc signed rather than developer-signed, which is precisely the condition that API is known to reject. The bundle will be properly sealed and registration tested against the real system before this is committed to.
- If it will not register, the app falls back to a per-user launch agent, which works irrespective of code signing.
- Either way, **the checkbox reports the state the system actually holds**, queried live, rather than a preference the app stored and hopes was honoured. A launch-at-login toggle that silently failed and kept claiming success is worse than not having one.

## Testing Decisions

A good test here observes behaviour at a boundary someone outside the module could
also observe, and would survive the internals being rewritten. It fixes the inputs
that are ordinarily ambient — the clock, the home directory, the config directories —
and asserts on what the user would see or on the file that lands on disk. It does not
reach inside to check that a particular helper was called.

Three seams, and no more:

### The display seam (primary)

The pure (accounts, settings, now) → view model function is where nearly all logic
lives, so it is where nearly all tests live. Fixture config directories in a temporary
location, a frozen clock, and assertions on the resulting view model. Covered:

- snapshot absent, malformed, and partial (one window present, the other missing)
- the reset boundary — immediately before, exactly at, and after a window's reset time
- a never-reported account rendering as a dash, and a genuinely-empty window rendering as zero, kept distinct
- warn and critical colouring, per account and independently, including exactly on each threshold
- percent rounding of fractional inputs, bar glyph counts at the extremes, countdown and staleness formatting across their unit boundaries
- account ordering, and the app with zero accounts registered

No AppKit is loaded, no real clock is consulted, and no real home directory is read.

### The tap seam

The tap is a separate process in another language and cannot share the display seam.
It is tested as a black box: fixtures piped in, snapshot file and exit status asserted.
Covered: writes on a well-formed payload; **does not clobber an existing good snapshot
when the payload has a null or missing rate limit block**; survives malformed input;
always exits successfully; prints nothing; and writes into the config directory named
by the environment rather than the default one — the case that protects the second
account from the first.

### The tap installer seam

Given a settings file and a config directory, install and assert on the file that
results. The load-bearing test is preservation: a settings file already carrying model,
permissions, plugins and effort level must emerge with every one of them intact and a
status line added. Also covered: detection reports the truth on files with, without,
and with a *foreign* status line already configured; and installing is idempotent.

### Not tested automatically

**Login-item registration.** It is a system side effect on a signed bundle; a unit test
against a mocked protocol would prove only that the app satisfies an interface the app
itself defined, while the actual question — will this ad-hoc signed bundle register? —
went unasked. It is verified against the real system, on the real machine, and the
result determines which mechanism ships.

### Prior art

None — this is a new project with no existing tests.

## Out of Scope

- **Historical usage, trends, or charts.** The tap only ever sees the present. Building history would mean the app accumulating its own store, which is a different product.
- **Cost or token accounting.** Session transcripts could be parsed for token counts, but that answers a different question than "how much of my subscription is left", and the rate limit block already answers this one exactly.
- **Polling usage while Claude Code is not running.** This would require reaching an undocumented endpoint with credentials lifted from the keychain. It is the only way to get truly continuous data, and it is rejected: it is unsupported, it can break without warning on a server change, and the failure mode is silently wrong numbers about a limit the user is relying on.
- **Notifications or alerts at a threshold.** Colour is the alert. Push notifications are a plausible follow-up but not this.
- **Any control over Claude Code itself** — switching accounts, launching sessions, changing models. This app observes; it does not drive.
- **Windows or Linux.** The deliverable is a macOS menu bar app.
- **Distribution.** No notarisation, no signing identity, no updater, no release. This is built and run locally.
- **A configurable poll interval**, cut for the reason given above.

## Further Notes

- The rate limit fields are only populated for Claude.ai subscription accounts (Pro/Max), and only after the first API response of a session. An API-key account will register fine and correctly show a dash forever. If that becomes confusing, the tap-status badge is the natural place to explain it.
- The reset-time inference deserves a second look in practice. The app treats a window whose reset time has passed as empty, which is correct, but it has not *observed* it to be empty. The dropdown is explicit about this. If it proves misleading in daily use, the honest fallback is to show the window as unknown rather than zero.
- Auto-discovery scans for config directories adjacent to the default one. It will find the user's actual setup with no configuration; it is a convenience, and the manual folder picker is what makes it non-binding.
- The project is not yet under version control. It should be, before any of this is built — `.plan/` is meant to be committed.
