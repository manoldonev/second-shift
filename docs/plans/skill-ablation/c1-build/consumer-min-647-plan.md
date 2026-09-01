I've read the code the ticket targets. Before the plan, three findings that change it — all verified, none of which block the work.

## Findings that reshape the ticket's stated remedy

**1. The checkout is not at the base commit.** 708 tracked files — all of `plugins/**`, including `lean-gate.sh` itself — are deleted in the working tree (`git status` shows ` D`, unstaged). Nothing is staged or committed. `git restore` recovers all of it. Nothing can be built or verified until that's done.

**2. `lean-gate.sh entry` does not cut the worktree — it runs *before* the worktree exists.** The gate's own comment above `cmd_entry_sweep` says it: *"`entry` runs before checklist step 3 cuts this run's worktree, so it is always executing outside it."* SKILL.md step 3 is freehand prose ("Cut a worktree on `<lean prefix><issue>` from the configured base") — `git grep 'worktree add'` finds **no production site at all**; every hit is a selftest fixture or `pr-revision/SKILL.md`. So AC-1's literal wording ("after `entry` cuts a lane worktree") describes a call that does not exist.

The seam is still clean, and better than the ticket assumed: `lean-gate.sh` already resolves `REPO_ROOT` (cwd's tree) and `MAIN_ROOT` (`--git-common-dir/..`, the origin checkout) at lines 498–510 of every invocation. `REPO_ROOT != MAIN_ROOT` *is* "I am running in a lane worktree." The copy needs no new path resolution.

**3. The copy in `entry` alone cannot fix the first run of a ticket.** A session reads its permission settings at launch. On a first run, `entry` executes in the main checkout, the worktree does not exist, and there is nothing to copy into; the same session then cuts the worktree at step 3 and works in it — with settings already loaded. A copy performed at `entry` benefits the *next* session in that worktree, not the one doing the copying. I will still satisfy AC-1/AC-2/AC-3 exactly as written (they are pure worktree-content oracles and are satisfiable at the `entry` site), but I'll extend the copy to the milestone-1 call as well so the fix reaches a first run, and I'll flag the residual in the PR rather than claim a closure the mechanism doesn't deliver. See D-2 below.

I am **not** blocking on these. The plan below carries them as decision-ledger rows.

---

## Plan of record

### Phase 0 — restore the checkout (me, before anything else)
`git restore -- .` to bring the 708 deleted tracked files back. Then a baseline `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` so AC-5's green is measured against a known-green start, not asserted at the end against an unknown one.

### Phase 1 — the lane's opening calls (me, driving `build-lean`)
1. `bash G entry 647` — audit-ledger attestation, progress file, worktree sweep.
2. `bash G claim 647` with `RUN_ID` exported — bot label swap + `lean-claimed` marker.
3. Cut the worktree at `../second-shift-worktrees/647` on `claude/second-shift-647` from `main` (per `.claude/second-shift.config.json`).

### Phase 2 — the spec (me) — `docs/plans/second-shift-647-lean.md`
The living definition of done, gating milestone 1. Contains: issue link; the ticket's AC-1…AC-6 restated as the binding `AC-n` set; and a `## Decision Ledger` carrying at minimum —

- **D-1** — `entry` does not cut the worktree (finding 2). AC-1's wording is read as *"after a lane worktree exists, it carries the operator's settings"*, and the copy site is `entry` plus milestone 1.
- **D-2** — the launch-time-settings gap (finding 3). Records that the copy is additive to the *next* session in the tree, names what it does and does not close, and refuses to overstate it.
- **D-3** — the ticket's Open Region: **skip `.claude/settings.json` when tracked** (it is tracked in this repo, so the worktree already has it), copy only when the origin has it and the worktree lacks it. Reversible default, flagged in the PR.
- **D-4** — `.claude/settings.json` already exists and is tracked, so AC-4 is an *edit* adding a `permissions.allow` block, not a new file. The "comment naming this ticket" lands as a `"//"` key, since JSON has no comments; if the settings loader rejects unknown keys I fall back to the PR body and say so.

### Phase 3 — implementation (me), in this commit order
1. **`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`** — one new function, `provision_worktree_settings()`. No-ops when `REPO_ROOT = MAIN_ROOT`; copies `$MAIN_ROOT/.claude/settings.local.json` → `$REPO_ROOT/.claude/settings.local.json` only when the source exists and the destination does not (AC-3); plain `cp`, never `ln -s` (AC-2); advisory — it can never change any caller's exit status. Called from `cmd_entry` and from the milestone-1 path.
2. **`.claude/settings.json`** — AC-4's interim: `permissions.allow` for the gate script, `gh`, and `git fetch`, plus the `"//"` provenance key naming #647.
3. **`plugins/dev-pipeline/skills/build-lean/SKILL.md`** — step 3's prose gains the fact that the gate provisions settings into the tree, so the checklist and the code are one story.

### Phase 4 — tests (me) — `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`
New cases for AC-1 (present / absent-fixture-yields-none-and-no-error), AC-2 (`[ ! -L ]`, plus write-to-copy leaves origin byte-identical), AC-3 (pre-existing file survives re-entry). They go here — per-tool behavioral, next to the tool — and each case comment must name the invariant and why no `scenario-liveness-selftest.sh` scenario covers it, per CLAUDE.md. My position, stated in the spec: the copy is advisory and reaches no verdict path, so it extends no liveness scenario; that reasoning is recorded rather than assumed.

### Phase 5 — the registry obligations this change triggers (me)
These are non-obvious and easy to miss; each is *checked*, then filled only if the check reds:
- `scripts/check-gate-buckets.sh` / `scripts/gate-buckets.tsv` — #654 requires every enumerated refusal site to declare a yield bucket. The design is advisory precisely so it adds none; I verify rather than assert.
- `scripts/check-fail-open-shapes.sh` / `scripts/fail-open-sites.tsv` — a copy that degrades silently is a fail-open shape and may need a `safe` row with its mechanism named.
- `tools/mutation-catalog.tsv` — evaluate whether a row earns its keep by naming a regression class it alone catches; add only if so.
- `docs/prose-blocker-triage.tsv` — the corpus the bucket guard reads.

### Phase 6 — gates and the PR (me)
`bash G 2`, `bash G 3`, then `bash G all 647`. AC-5's full sweep, plus `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` and `jq empty` over every `*.json`. Commits via `bot-commit.sh`. Then the cost block (`pipeline-cost-block.sh --stateless --issue 647`), a **ready** PR with `Closes #647` and the D-3 Open Region flagged, and `bash G mark 647`.

**Commit trailers** — `feat(dev-pipeline):` (a new capability; CLAUDE.md is explicit that `chore:` here would silently downgrade the release), carrying:
- `Changelog:` with a **`Migration:`** line (AC-6 — consumers gain behavior they did not have);
- **`Guard-mass:`** — `check-guard-budget.sh` classifies `*/skills/*/lean-gate.sh` and `*-selftest.sh` as guard mass, and this PR grows both, so without this trailer CI reds.

I will not touch `CHANGELOG.md`, any `plugin.json` `version`, or `marketplace.json` `metadata.version` — `check-frozen-files.sh` rejects a feature PR that does.

### Phase 7 — review, close-out, merge (not me)
- **`docs/plans/second-shift-647-lean-verdict.md`** — written by a separate `/dev-pipeline:review-lean` session with its own identity. Milestone 4 passes only on a committed `verdict=approve` whose `reviewed_patch_id` is this branch's head.
- **CI** — `mutation-sweep-pr`, both selftest jobs, the trailer and frozen-file guards.
- **`bash G close-out 647`** — bot-authored closing comment, `cost-log.jsonl` row, milestone 5, worktree teardown.

---

Two things I want your call on before I start, though I have a default for each and will proceed on it if you'd rather not adjudicate:

- **D-2 is the one that matters.** If the copy at `entry` cannot help the session that cuts the worktree, the honest fix may be to give the gate the worktree-cutting step outright (`lean-gate.sh worktree <issue>`, called by SKILL.md step 3) rather than leaving it as freehand prose. That is a larger change than the ticket scopes, so my default is the narrow fix plus a follow-up ticket — but say the word and I'll design the wider one.
- **Phase 0's restore.** It's the only way to reach the ticket's target files, and it's reversible, but it does discard the working tree's current state — confirm you want it, or tell me the deletions are deliberate and I'll re-plan around them.
