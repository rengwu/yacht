---
type: task
blocked_by: []
claimed_by: sfa6334503ffe
claimed_at: 2026-07-30T16:46:19Z
---

# Go provider-agnostic in repo and docs naming

## Question

AFK build ticket — decision 9 of [`spec.md`](../spec.md).

The naming is already inconsistent *before* Kimi arrives: the git remote is
`rengwu/another-claude-tracker`, the README's download badge points at `rengwu/yacht`, and the
working directory is `claude-usage-menubar`. A second provider makes the Claude-first framing
wrong as well as inconsistent.

1. **Settle on Yacht** across README, `docs/`, and the repo itself; describe the product as
   usage for coding agents rather than for Claude Code.
2. **`tap/claude-usage-tap.sh` keeps its filename.** It is Claude-specific by nature, and its
   absolute path is written into users' `statusLine` settings across five released versions —
   renaming it strands every existing install. Leave it, and leave a comment saying why so it
   does not get "tidied" later.
3. **Check the release path end to end** before declaring this done: the README download badge
   URL, `.github/workflows/release.yml`, and anything else naming the repo. A GitHub rename
   leaves redirects for repo URLs, but confirm rather than assume for the
   `releases/latest/download/Yacht.dmg` asset link — a broken download button is the one failure
   a user sees before anything else.
4. **Do not rename the `.plan/usage-menubar/` effort** or rewrite its history. It is a dated
   record of work already done; renaming it to match today's vocabulary makes the record lie
   about what it was called at the time.

The GitHub repo rename itself is the human's to perform — hand over a precise list of what to
click and what to verify afterwards, rather than assuming it has happened.
