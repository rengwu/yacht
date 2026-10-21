---
title: Release packaging and upgrade checks
updated: 2026-10-21
---

# Release packaging and upgrade checks

**ID:** FEAT-release

The user requested autonomous release preparation through jstack work-until-grill, including a version bump. The next candidate is **0.2.0**, following published 0.1.6. Distribution remains the existing ad-hoc-signed GitHub DMG; publication has not occurred.

## Expected outcomes

- `VERSION`, the bundle version, and the release tag agree.
- `./build.sh` produces a universal Apple Silicon/Intel `build/Yacht.app`, with its icons and license inside the bundle and a valid ad-hoc signature.
- Tag releases run core and tap tests before publishing. The release includes the prepared version-specific notes.
- The DMG contains `Yacht.app` and an Applications link. A copy outside the checkout launches and renders its bundled provider icons.
- Upgrading preserves registered accounts and settings. Offline demo edits do not write the saved configuration.
- Existing live profiles produce usage; expired Kimi/Grok credentials remain read-only and require the provider CLI to renew them.

## Verification recipe

Use [shared setup](../verification/setup.md). Run `swift run UsageCoreTests`, `bash tap/test_tap.sh`, and `./build.sh`. Inspect both version keys with `plutil`, run `lipo build/Yacht.app/Contents/MacOS/Yacht -verify_arch arm64 x86_64`, and run `codesign --verify --deep --strict build/Yacht.app`.

Create a local DMG with the release workflow's create-dmg arguments plus `--skip-jenkins` for a headless packaging check. Mount it read-only without opening Finder, copy its app into a temporary directory, verify its signature and binary hash, then eject the image. Launch that exact copy with `--demo`, check first-click rename and a display control, and inspect the usage menu with Command-U. Stop only the process created for this check, restore the normal instance, and compare the saved configuration hash.

Inspect Add Account discovery and cancel without saving. Live provider checks need existing signed-in profiles. Never write credentials or record tokens. Intel core execution under Rosetta is a separate check from native Intel UI validation.

## Coverage and limits

Automated suites cover config migration, account identity, percentage semantics, stale states, provider payloads, and tap preservation. A local DMG launch is not a downloaded/quarantined install, and the current host cannot establish macOS 13 or physical Intel compatibility. Full VoiceOver operation and a login/logout cycle are outside this preflight.

## Verification history

- [0.2.0 preflight](../verification/runs/2026-10-21-v0.2.0-preflight.md): packaging and exercised checks passed; fresh Kimi request remains untested because credentials are expired.
