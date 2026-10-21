---
title: Mockup handoff
updated: 2026-10-20
order: 3
---

# Mockup handoff

> **Completed.** The mockup work this page started is done. To implement the final design, start from the [design handoff](design-handoff.md). This page is kept as history.

Start here when continuing the design in another session. The user wants mockups for a lightweight, minimal macOS menu bar AI usage tracker, implemented eventually in native Swift. The previous dashboard redesign was rejected because it was built before the requirements discussion.

## Read first

- [Accepted requirements, open decisions, and working tree facts](plan.md) — authoritative interpretation of the interview.
- [Round 1 answers](journal/2026-10-19-grill-8ef2fa34-9d14-4577-827c-f7a1b51f04f7.md) — purpose, scope, and constraints.
- [Round 2 answers](journal/2026-10-19-grill-b89a23b6-c6c3-4fbb-934f-22325c1fb909.md) — everyday reading and display behavior.
- [Round 3 answers](journal/2026-10-20-grill-6f40375f-6228-48e1-972d-055c180fcfbe.md) — entry customization, account scope, reset modes, and the setup advice request.

All three rounds are collected and interpreted in the plan. There is enough direction to start rough alternatives without another interview round. The user asked for the leanest account setup; the researched recommendation in the plan is still a proposal to review through the mockups.

## Design task

Explore rough visual alternatives before selecting a direction. A plain native menu and a compact native table are useful candidates for comparison, not accepted designs. Keep the scope to a dropdown and settings, and represent the four-to-eight-account workload rather than only a single ideal account.

Suggested review material:

- A closed menu bar with multiple enabled account figures, including a crowded example.
- The dropdown with four accounts and with eight accounts, preserving the same user-controlled flat order and showing each account's reported windows.
- Settings for the accepted customization choices: per-entry labels and optional provider icons, one chosen menu bar quota window per account, used/remaining convention, and countdown/exact reset mode. Placement, defaults, and the scope of display settings remain proposals.
- A compact account-setup sketch using the proposed local-profile registration flow, with two accounts from the same provider. Label this flow as recommended, not already approved.
- Normal, stale, reset-passed/awaiting-update, and no-data examples. Label fictional fixture data clearly.
- A short explanation of the readability and density tradeoffs between alternatives.

These are proposed design exercises, not additional product requirements. Do not hide reported windows behind account expansion to make a mockup smaller. Do not combine independent account quotas into a single percentage.

Keep actions within the accepted monitoring scope: refresh and settings. The user explicitly requested simplicity and no invented features. “Full customization” establishes the requested entry label/icon controls; it is not a request for an unrestricted theme or extension system.

Use mockups to settle structure and placement. Visual choices, presentation defaults, truncation/overflow behavior, and light/dark treatments are still proposals until reviewed. Minimal appearance alone does not establish low resource use.

## Scope and continuity

This handoff requests design exploration. It does not authorize building the replacement app. No final layout, AppKit-versus-SwiftUI decision, numerical resource budget, or authentication redesign has been accepted.

The repository is on `redesign/native-dashboard`, but that branch name reflects the rejected attempt. Its redesign files have been removed. Earlier uncommitted Grok work remains and must be preserved. See the plan for cleanup evidence and the recovery-copy location.

Use `../jstack` for wiki, plan, grill-form, and `rule-lean`. Ask only consequential questions still open after reading the plan; do not repeat settled interview rounds. Record reviewed design decisions in the plan and rebuild/check the wiki. Existing code and historical `.plan/maps` are factual references, not a mandate to retain their UI.

## Starter prompt for the next session

> Read `docs/wiki/mockup-handoff.md` and `docs/wiki/plan.md`. Use `../jstack` wiki, plan, grill-form, and rule-lean. Help me explore rough alternatives for the lightweight native Swift menu bar tracker before choosing a design. Respect the accepted requirements, add no invented features, and distinguish proposals from decisions. Include the local-profile account setup recommendation for review. Preserve the existing working tree. Start with mockups; do not implement the replacement app yet.
