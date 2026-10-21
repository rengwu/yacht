---
title: AI subscription tracker
updated: 2026-10-21
order: 0
---

# AI subscription tracker

The accepted native Swift/AppKit design is released as **0.2.0**. Start with the publication and implementation pages for current validation and limits. The earlier dashboard redesign remains rejected.

- [Current plan and open decisions](plan.md)
- [Native implementation and validation](native-implementation.md)
- [0.2.0 publication and download verification](verification/runs/2026-10-21-v0.2.0-publication.md)
- [0.2.0 release preflight](verification/runs/2026-10-21-v0.2.0-preflight.md)
- [Feature verification](features/index.md)
- [Design handoff: start here to implement](design-handoff.md)
- [Mockup handoff (completed)](mockup-handoff.md)
- [Round 1 submitted answers](journal/2026-10-19-grill-8ef2fa34-9d14-4577-827c-f7a1b51f04f7.md)
- [Round 2 submitted answers](journal/2026-10-19-grill-b89a23b6-c6c3-4fbb-934f-22325c1fb909.md)
- [Round 3 submitted answers](journal/2026-10-20-grill-6f40375f-6228-48e1-972d-055c180fcfbe.md)
- [Round 4 submitted answers](journal/2026-10-20-grill-1664761b-a44e-468f-a6d4-1ce37f6b63ad.md)
- [Round 5 submitted answers](journal/2026-10-20-grill-94e43e24-0344-4592-9f1e-8eee6e7b6cb6.md)
- [Accounts table review: compact layout and refinements](journal/2026-10-20-grill-38baa3c1-ee26-4927-a545-81600f42bc14.md)
- [Accounts table refinement: approved for implementation](journal/2026-10-20-grill-21c6d8e7-5273-49e5-9839-1436d77ca537.md)

## Project workflow

At the user's request, this project uses the sibling `../jstack` workflows:

- `plan` interprets and records decisions in this wiki.
- `grill-form` presents interview rounds using the `grill-me` decision process.
- `wiki` maintains these Markdown pages and the offline HTML reader.
- `rule-lean` guides implementation choices toward the simplest complete solution for the accepted requirements.

Markdown is authoritative. Rebuild the reader with `node docs/wiki/_build.mjs`, then validate it with `node docs/wiki/_build.mjs --check`.

## Existing records

Earlier implementation and acceptance records remain under `.plan/maps/usage-menubar`, `.plan/maps/multi-provider`, and `.plan/maps/codex-provider`. Those records describe earlier work, not requirements for the new design. They have not been moved or rewritten.

Interview transcripts are saved under `journal/` when a form is submitted and collected. Submitted answers are interpreted into the plan; recommendations alone are not accepted decisions.
