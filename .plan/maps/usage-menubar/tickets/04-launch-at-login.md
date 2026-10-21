---
type: task
blocked_by: [03]
assets: [Sources/ClaudeUsage/LaunchAtLogin.swift, Sources/ClaudeUsage/SettingsWindowController.swift]
---

# Build launch-at-login + lifecycle

## Question

AFK build ticket. Launch-at-login, decided by experiment on this machine: seal the bundle
(`codesign --force --deep --sign -`) and try `SMAppService`; if it refuses the ad-hoc bundle,
fall back to a per-user `~/Library/LaunchAgents` plist. Add the checkbox to the settings
window; **it reports the system's actual live state**, never a stored intention. Wire "Quit"
into the app's own menu.

Product behaviour is identical whichever mechanism wins, so surface nothing unless the login
item cannot be made to work at all.

## Answer

**The experiment settled it: `SMAppService` ships.** Against the real sealed bundle on this
Mac (macOS 27.0, ad-hoc `codesign --sign -`), `SMAppService.mainApp.register()` *succeeded* —
the condition that API is "known to reject" did not bite here. Proven it is a real system fact,
not an in-process claim: a **fresh** process read `.enabled` after registration, and
`sfltool dumpbtm` listed the item under the bundle id (`[enabled, allowed, notified]`) pointing
at the app URL; `unregister()` cleared it back to `.notRegistered`. So the launch-agent fallback
is not needed — it stays as `LaunchAgentLoginItem`, a compile-guarded (`-DLOGIN_USE_LAUNCH_AGENT`)
documented path behind the same `LoginItem` contract for a future context where an ad-hoc bundle
*is* refused.

**The checkbox is a live fact, not a stored intention.** `LaunchAtLogin.isEnabled` reads
`SMAppService.mainApp.status` every time the settings window builds; toggling calls
`register`/`unregister`, surfaces any throw in an alert, then snaps the box back to whatever the
system *actually* holds. Verified through the real GUI: clicking it went 0→1 and BTM showed the
item enabled; quitting and **relaunching** re-read the system and showed the box checked (live
state survived the process); unchecking cleared BTM with no residue.

**Quit** was already wired into the status menu in ticket 03 (`NSApplication.terminate`);
confirmed it terminates the app cleanly from its own menu. The experiment scaffolding was removed
from the shipping binary; its outcome lives in a comment on `chooseMechanism()`.
