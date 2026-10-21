---
title: Verification setup
updated: 2026-10-21
---

# Verification setup

Use the repository's native Swift tools. Core tests are an executable: `swift run UsageCoreTests`. Tap tests use Bash and `jq`: `bash tap/test_tap.sh`. `./build.sh` builds arm64 and x86_64 separately and combines them with `lipo`, preserving Command Line Tools support.

The current verification host has macOS 27, Swift 6.3, Apple Silicon, Rosetta, `jq`, `create-dmg`, and Node 22. Intel execution under Rosetta is available; physical Intel and macOS 13 machines are not available in this session.

## Instances and data

Normal Yacht uses `~/Library/Application Support/Yacht/config.json`. Hash that file before isolated checks; never wipe or replace it. A normal run reads existing registered profiles and may refresh Yacht-owned usage caches. Tap installation and login-item changes are separate side effects and are not part of this preflight.

`open -n build/Yacht.app --args --demo` starts fictional accounts entirely in memory. Demo disables provider requests, configuration writes, tap installation, and launch-at-login changes. Command-U opens Usage Preview. `--light` and `--contrast` change only the demo's appearance.

When verifying an exact copy from the DMG, temporarily stop the normal repository instance by its exact executable path, then launch the copied app with `--demo`. This avoids two instances with the same bundle identifier. Record its binary hash and bundle version before using native computer controls. Restore the normal repository app afterward. Do not replace `/Applications/Yacht.app`.

## Packaging

The CI recipe is `.github/workflows/release.yml`. For local headless verification, add `--skip-jenkins` to create-dmg so Finder styling is skipped. Mount with `hdiutil attach -readonly -nobrowse -noautoopen`, copy out `Yacht.app`, verify with `codesign`, and eject with `hdiutil detach`. This path was executed during the [0.2.0 preflight](runs/2026-10-21-v0.2.0-preflight.md).

Evidence belongs under `evidence/<run-id>/`. Save sanitized outcomes and fingerprints, never provider credentials or raw authenticated responses. Temporary fixtures and apps stay outside the repository. Only stop/remove resources created for the run.
