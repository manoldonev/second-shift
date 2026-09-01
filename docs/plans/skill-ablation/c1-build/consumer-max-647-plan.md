I read the ticket, the gate, the orchestrator, and the repo conventions. Two things I found change the plan, so I state them before the artifact list.

## Blockers / premise corrections

**B1 — the working tree is not at the base commit.** 374 tracked files are missing from disk: all of `plugins/` and `.claude-plugin/`. `git status` shows them as ` D`, no untracked files. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` — this ticket's target — is one of them. `git checkout -- .` requires an approval I cannot obtain in a non-interactive session, so **step A0 below is blocked on you**. Everything after it is planned against the HEAD blob contents, which I read via `git show`.

**B2 — the ticket's mechanism sentence is false about today's code.** The ticket says `lean-gate.sh entry` copies the settings "when it cuts it." `entry` does not cut the worktree, and says so explicitly:

- `lean-gate.sh:2611` — *"`entry` runs before checklist step 3 cuts this run's worktree, so it is always executing outside it"*
- `SKILL.md` step 3 — *"Cut a worktree on `<lean prefix><issue>` from the configured base"* — is a **session** instruction, not a gate call. The gate's only other mention of cutting is a refusal that tells the operator to do it by hand (`lean-gate.sh:5330`).

So AC-1's "after `entry` cuts a lane worktree" describes a capability that does not exist yet. There is no seam at the cut for a copy to hook into, and a fresh run has no worktree at `entry` time to copy *into*. **My resolution: `entry` takes ownership of the cut** — it ensures the lane worktree exists at `<worktreesDir>/<branch-slug>`, seeds it, and prints the path; `SKILL.md` step 3 becomes "cd to the worktree `entry` named." That is the only reading under which AC-1 is literally satisfiable and under which the fix works for consumers, whose sessions cannot be relied on to call a seed helper by hand. The smaller alternative — a separate `bash G seed <issue>` the session calls after cutting — covers only re-entries and pushes the obligation back onto the caller, which is the failure mode the ticket is fixing. I record this as **D-1** and flag it in the PR; it is reversible to the smaller shape.

**B3 — a hazard the ticket does not name, and it is load-bearing.** `.claude/settings.local.json` is *not* in this repo's `.gitignore`; it is ignored only by the operator's global ignore. In a consumer whose ignore rules do not cover it, a copied file lands **untracked**, making `git status --porcelain` in the worktree non-empty. That is the exact predicate `worktree_inflight()` returns 8 on, which the orchestrator turns into a `build-inflight` HARD STOP (`orchestrate-lean.sh:1048`). Shipping the copy naively converts a random classifier failure into a deterministic hard stop for every consumer. The seed must therefore either write into a path the run's own dirty-tree predicate excludes, or `entry` must assert the destination is ignored before copying — same posture `.gitignore:18-24` already takes for `.claude/lean-renders/`. This becomes **D-5** and gets its own AC and selftest case.

## Plan of record

**A0. Restore the checkout** (you) — `git checkout -- .`, verified by `git status --porcelain` empty. Nothing below can start until this lands.

**A1. Branch and worktree** (me) — `claude/second-shift-647` from `origin/main`, worktree under `../second-shift-worktrees/`, per `.claude/second-shift.config.json`'s `worktreesDir`.

**A2. Gate entry and claim** (me) — export `RUN_ID`, then `bash G entry 647` and `bash G claim 647`. Produces the progress record under `.claude/pipeline-state/` (gitignored) and the bot-authored `lean-claimed` marker. Records, not committed files.

**A3. Spec/AC file** — `docs/plans/second-shift-647-lean.md` (me). Path confirmed by `bash G 1 647`; `plansDir` defaults to `docs/plans` (`lean-gate.sh:560`). Contains AC-1…AC-6 verbatim from the ticket plus **AC-7** for D-5 (a seeded worktree does not read as dirty to `inflight`/`teardown`), and a `## Decision Ledger`: D-1 (entry owns the cut, B2), D-2 (copy never symlink), D-3 (never clobber), D-4 (skip a tracked `.claude/settings.json` — the ticket's stated reversible default), D-5 (the ignore-assertion, B3). Open Regions with dispositions. This file is the living definition of done; milestone 1 gates on it.

**A4. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`** (me) — the fix. A new `lane_settings_seed()` reusing the existing `lean_worktrees_for_branch()` (`:1963`); `cp` only, regular-file destination, no-clobber; source is `$MAIN_ROOT/.claude/`, never `$REPO_ROOT`. Wired into `cmd_entry` (`:2663`) alongside the worktree-ensure, and **advisory like `cmd_entry_sweep`** — it must never reach `entry`'s exit status, for the same reason the sweep does not: the audit-ledger predicate is the sole decider of whether a run may start. Carries a house-style WHY block naming #647 and the two-runs-of-#641 evidence.

**A5. `plugins/dev-pipeline/skills/build-lean/SKILL.md`** (me) — step 3 rewritten for D-1. Blast radius to sweep in the same edit: the `require_lane_tree` refusal text at `:5330`, and any `run-lean` prose describing who cuts the worktree.

**A6. `.claude/settings.json`** (me) — AC-4, the interim. A `permissions.allow` block with the three allows (the gate script, `gh`, `git fetch`) and a `"//647"` comment key naming this ticket so its removal after AC-1 ships is traceable. The file is already tracked, so it takes effect on commit.

**A7. `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`** (me) — the oracles. Hermetic `mktemp -d` cases in the file's existing idiom: AC-1 present/absent fixtures, AC-2 `[ ! -L ]` plus a write-isolation assertion, AC-3 re-entry no-clobber, AC-7 `git status --porcelain` clean after seeding. Auto-discovered — no registration.

**A8. `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh`** (me) — CLAUDE.md:201: *"A new gate contract extends the liveness scenario."* A composed case driving a seeded worktree through to a terminal write, so the seed cannot pass its unit oracle while breaking the `inflight` path.

**A9. `tools/mutation-catalog.tsv`** (me) — one row if the new guard has a kill criterion the existing rows do not cover; the diff-scoped `mutation-sweep-pr` CI job runs it.

**A10. Verification** (me) — the three CLAUDE.md commands verbatim, including AC-5's `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`, plus `shellcheck -e SC1091,SC2015,SC2181` and `jq empty`.

**A11. Commits** (me) — through `bot-commit.sh`. `feat(dev-pipeline):` — CLAUDE.md:50 is explicit that a new capability here is `feat`, not `chore`. Body carries AC-6's trailer: `Changelog:` with a `Migration:` line (consumers gain the inherited-posture behavior and, under D-1, a moved worktree-cut responsibility). **I do not touch** `CHANGELOG.md`, `plugin.json`'s `version`, or `marketplace.json` — `check-frozen-files.sh` reds the PR if I do.

**A12. Milestones 2, 3, cost block, PR** (me) — `bash G 2 647`, `bash G 3 647`, then `pipeline-cost-block.sh --stateless --issue 647`. A **ready, non-draft** PR: summary, spec link, `Closes #647`, cost block in the description, and the D-4 open region flagged as the ticket instructs. Then `bash G mark 647` at step 7, not step 9.

**A13. Verdict record** — `docs/plans/second-shift-647-lean-verdict.md`. **Not mine.** Milestone 4 arrives from outside: a separate top-level `/dev-pipeline:review-lean <pr>` session with its own identity authors it, and `lean-gate.sh`'s P10 authorship check refuses to let this session write it. I hand off and stop.

**A14. Close-out** (me, after an approve) — `bash G all 647`, then `bash G close-out 647`: republished cost block, `cost-log.jsonl` row, closing comment, milestone 5, worktree teardown.

## The one thing I want your call on before A0

D-1 (B2) is the decision with real blast radius — it moves the worktree cut from the session to the gate. I have chosen it because it is the only shape that satisfies AC-1 as written and works for consumers, and I will proceed on it unless you say otherwise. Everything else I will resolve myself and record in the ledger.

Stopping here as instructed — no code written. A0 needs your approval to unblock.
