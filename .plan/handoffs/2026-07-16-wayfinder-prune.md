# Handoff — `wayfinder-prune` skill

**Date:** 2026-07-16
**Repo:** `~/Desktop/Projects/claude-usage-menubar`
**Status:** Skill designed, written, and linted. **Not yet used on a real map.** Also just reported as "adopted to another repo" — see the open question below before touching it further.

## What this session did

1. Re-traced a prior session (2026-07-12, `~/.claude2` account, this repo, session
   `3d7764ed-6c6c-4650-aa14-9e73fe958053.jsonl`) where `wayfinder` charted a 10-ticket map for
   this app and the user pushed back: most tickets were implementation-detail grilling they
   didn't have the tokens or expertise to weigh in on.
2. Ran a full `grill-me` session to design a fix, then wrote it up with `writing-great-skills`
   discipline: **[`.pocock-skills/wayfinder-prune/SKILL.md`](../../.pocock-skills/wayfinder-prune/SKILL.md)**.
3. Linted the result against `writing-great-skills`' own failure modes (duplication, no-ops)
   and fixed three findings — see git-free diff history in this conversation if you need the
   before/after; nothing here duplicates that.

## What `wayfinder-prune` is (read the file for the full spec — this is just orientation)

A companion skill, **one-directionally dependent on `wayfinder`**: it reads and relies on
`wayfinder/SKILL.md`, but `wayfinder` itself is untouched and has no idea it exists. You invoke
it by name, separately from `wayfinder`.

Key design decisions, in case they need re-litigating rather than just re-reading:

- **It's a sweep, not a starting choice.** You always chart with plain `wayfinder` first — a
  map's shape isn't visible until charting is underway. You reach for `wayfinder-prune`
  whenever the map (or the remaining frontier) starts feeling overwhelming: mid-charting,
  right after commit, or later mid-resolution. This was a **correction mid-session** — the
  first draft wrongly assumed you'd decide upfront, "instead of" `wayfinder`.
- **The prune test:** exempt categories (design, prototyping, tech-stack, *material or
  hard-to-reverse* cost, *user-facing* product behavior — open class, not closed) always get
  grilled. Genuine tradeoffs get grilled. Everything else that clears the **one-breath test**
  (defensible in one sentence, no serious counter-argument) gets decided on the spot.
  - The cost/behavior wording was deliberately **narrowed** from the user's first, broader
    phrasing ("any cost," "any meaningful system behavior") because the broad version would
    have re-grilled the exact tickets (tap script, `SMAppService`, `CLAUDE_CONFIG_DIR`) that
    started this whole thread. If pruning stops feeling effective, check whether this
    exemption has crept back toward the broad version before touching anything else.
- **Recording:** a pruned ticket is written **already-resolved** (Question + Answer in one
  pass, never claimed, tagged `(pruned)` in prose) — no new frontmatter field, no new ticket
  type, so the markdown adapter needs zero changes. **The user explicitly flagged they might
  revert this and switch to the no-ticket/inline-entry alternative** if this doesn't work well
  in practice. If asked to make that switch, the rejected alternatives (bundled single ticket,
  inline no-ticket entry) are already reasoned through in this conversation — don't re-derive
  from scratch, ask to see the transcript instead.
- **Pre-noted sub-questions:** a ticket that survives charting can still carry sub-questions
  that independently clear the one-breath test. Those get a recommendation pre-noted, and at
  resolution are answered without asking **only if still sound** (not undermined by a
  since-resolved decision) — otherwise they resurface and get asked live. Exemption cascades:
  no pre-noting inside an exempt-topic ticket, ever.

## Open question — needs the user, don't guess

**The user says the skill is "now adopted to another repo": <https://github.com/rengwu/skills/tree/main/pocock>.**
This was mentioned in passing, mid-handoff-request, with no detail on mechanics. Unresolved:

- Is `.pocock-skills/wayfinder-prune/SKILL.md` in *this* repo now stale/superseded by whatever
  is at that URL, or was it copied there and both are meant to stay in sync manually?
- Note that **`.pocock-skills/` is gitignored in this repo** (`.gitignore:4`) — the local file
  has never been committed anywhere in this repo's history. If the GitHub repo is meant to be
  the real home going forward, the local copy is the only thing that currently exists and
  nothing here backs it up.
- Ask the user directly before assuming either direction (pull from GitHub, or push this local
  version up) — don't fetch the URL and start reconciling unprompted.

## Suggested next steps

1. Resolve the open question above first.
2. Once resolved, the natural next step is trying `wayfinder-prune` on a real map (this repo's
   own `.plan/usage-menubar/map.md` is sitting right there with a resolved history to sweep
   against, if the user wants a live test rather than a synthetic one).

## Suggested skills

*(Only if available in your environment.)*

- **`wayfinder-prune`** (this repo, `.pocock-skills/`) — the artifact this session produced;
  read it before using it.
- **`writing-great-skills`** — if the recording mechanism gets revised (per the flagged
  possible revert above), re-lint after editing, same as this session did.
- **`grill-me`** — if the open question above surfaces new forks in how the two repos should
  relate, rather than a single factual answer.
