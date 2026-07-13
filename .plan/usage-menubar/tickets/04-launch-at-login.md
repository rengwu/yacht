---
type: task
blocked_by: [03]
claimed_by: claude-code-session-2026-07-13-opus
claimed_at: 2026-07-13T00:00:00Z
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
