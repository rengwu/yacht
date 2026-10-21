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

## Answer

Done. The product-facing identity is now simply **Yacht**, described in the README as a macOS
menu bar app for coding-agent rate-limit usage rather than expanded as "yet another claude
headroom tracker" or introduced as a Claude-only product. Claude remains named where it is the
domain truth — the current setup instructions and the Claude acquisition adapter — and the
formerly global "How it works" section is now explicitly "How Claude usage collection works".
That matters ahead of the Kimi adapter: the statement that this adapter never talks to the
network no longer falsely describes the whole product.

The repo's existing provider-agnostic names were audited rather than churned:

- The Swift package, executable target, source directory, app bundle/display names, executable,
  and bundle identifier are already `Yacht` / `local.yacht`.
- `docs/` contains only the existing demo image assets. It has no textual product or repository
  naming to rewrite, and those assets were left in place.
- Outside the dated `.plan/` records and Claude-specific implementation, no tracked
  `another-claude-tracker`, `claude-usage-menubar`, "Claude usage", or "usage menubar" product
  name remains.
- `.plan/usage-menubar/` is still present and byte-unchanged. The two historical handoff files
  that name the old working directory were also deliberately left alone; rewriting them would
  make dated records inaccurate.

### The tap filename is an explicit compatibility boundary

`tap/claude-usage-tap.sh` keeps its filename. A warning directly below its header now records
that five released versions wrote this absolute path into users' `statusLine` settings, so a
rename would strand installed accounts. The identical warning is in `TapDeployment.script`,
which must stay byte-for-byte equal to the canonical script. The README's project-layout entry
also records why the legacy filename is intentional.

### Release path — audited end to end

The names line up:

1. The README badge targets
   `https://github.com/rengwu/yacht/releases/latest/download/Yacht.dmg`.
2. `.github/workflows/release.yml` builds `build/Yacht.app`, creates the versioned
   `build/yacht-${GITHUB_REF_NAME}.dmg`, copies it to the exact case-sensitive
   `build/Yacht.dmg`, and uploads both assets.
3. `./build.sh` completed locally and produced the ad-hoc-signed `build/Yacht.app`.
4. A live redirect check on 2026-07-31 followed the README URL to
   `/rengwu/yacht/releases/download/v0.1.4/Yacht.dmg`, then to GitHub's release-asset store,
   ending at HTTP 200 with `content-disposition: attachment; filename=Yacht.dmg`.
5. The legacy
   `https://github.com/rengwu/another-claude-tracker/releases/latest/download/Yacht.dmg`
   first returned HTTP 301 to the Yacht URL, then followed the same chain to the same HTTP 200
   asset. The old repository page likewise returns HTTP 301 to `/rengwu/yacht`, while the Yacht
   repository page returns HTTP 200.

This exposed one piece of external state that differs from the ticket's premise: **the GitHub
repository has already been renamed to `rengwu/yacht`**. I made no GitHub mutation. This clone's
`origin` still says `git@github.com:rengwu/another-claude-tracker.git`; it works through GitHub's
redirect, but should be made explicit by the human who owns the rename.

### Human rename / post-rename handoff

1. On GitHub, open `rengwu/yacht` → **Settings** → **General** → **Repository name**. Confirm it
   reads `yacht`. If it still shows the old name in the authenticated settings view, enter
   `yacht` and click **Rename**.
2. Do not create a new repository named `another-claude-tracker`;
   [GitHub documents](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)
   that reusing an old name breaks the rename redirects.
3. In this clone, run
   `git remote set-url origin git@github.com:rengwu/yacht.git`, then verify both fetch and push
   rows from `git remote -v` name `rengwu/yacht`.
4. Open both repository URLs. Confirm `/rengwu/yacht` loads directly and
   `/rengwu/another-claude-tracker` redirects to it.
5. Click the README download badge. Confirm it downloads a file named `Yacht.dmg`; do not stop
   at seeing a release page.
6. After the next `v*.*.*` tag, open **Actions** → **Release**, confirm the workflow succeeded,
   then open that release and confirm both the versioned DMG and the unversioned `Yacht.dmg`
   asset are attached. Re-click the README badge to prove `releases/latest` advanced.

### Verification

- `swift run UsageCoreTests` — **145 passed, 0 failed**.
- `bash tap/test_tap.sh` — **21 passed, 0 failed**.
- `./build.sh` — production build succeeded and assembled/signed `build/Yacht.app`.
- `git diff --check` — clean.
- Standards review — no documented-standard violation or applicable code smell; the duplicate
  tap comment is required because the deployable script and its embedded copy are intentionally
  equality-tested.
- Spec review — all four ticket clauses are covered; no neighbouring Kimi implementation or UI
  work was pulled into this naming ticket.

Deliberately not done: no GitHub rename or remote rewrite, no local working-directory rename, no
tap filename change, no historical `.plan/` rewrite, and no Kimi feature/documentation claims
before the Kimi implementation lands.
