I've read enough to commit to a plan. One factual correction to the ticket first, since it changes the shape of the work:

**`lean-gate.sh entry` does not cut the lane worktree today.** `cmd_entry` (lean-gate.sh:2663) attests the ledger, records the ticket, and calls `cmd_entry_sweep` — which *removes* stale lane worktrees and explicitly skips the caller's own. The cut is freehand, done by the build session at `build-lean/SKILL.md` step **3**, *after* `entry` (step 1) and `claim` (step 2). So a copy bolted onto `entry` as-is is a no-op on every fresh run — it would only ever fire on a re-entry. AC-1 ("after `entry` cuts a lane worktree") and AC-3 ("a re-entry that reuses the worktree") only read coherently if `entry` gains ownership of the cut, so that is what I plan to build. This is the one decision I'd want you to confirm; everything below assumes it.

---

# Plan of record — #647

## Phase 0 · Pickup (produces: run state, branch, worktree)

| # | Artifact | Where | Contents | Producer |
|---|---|---|---|---|
| 0.1 | Restored working tree | `/private/tmp/746-arm1/max-647` | `plugins/**` is tracked (373 files) but deleted on disk — `git restore` it first; nothing else in this plan is runnable otherwise | me |
| 0.2 | Run id + entry attestation | `.claude/pipeline-state/647-lean-progress.md` (gitignored) | `export RUN_ID=…`; `bash G entry 647` writes the `\| entry \| ledger=… \|` row | `lean-gate.sh entry` |
| 0.3 | Claim | GitHub issue #647 | `bash G claim 647` — label swap + bot-authored `lean-claimed` marker | `lean-gate.sh claim` |
| 0.4 | Branch + worktree | `claude/second-shift-647` at `../second-shift-worktrees/…` | cut from the configured base | me (this run predates the fix) |

## Phase 1 · Spec — milestone 1

**1.1 `docs/plans/second-shift-647-lean.md`** — me. The living definition of done; `bash G 1 647` prints the exact path it wants and refuses without it. Contents:

- Problem statement, restating the measured evidence (two runs of #641, 2026-08-22).
- **`AC-1`–`AC-6` copied verbatim from the ticket**, plus:
  - `AC-7` (doc): `build-lean/SKILL.md` steps 1 and 3 describe the relocated cut and the inherited posture; a doc left stale by this change is an AC, per CLAUDE.md.
  - `AC-8` (doc): `orchestrate-lean.sh`'s `LEAN_SPAWN_PERMISSION_MODE` header block (line ~209) records that the lane worktree now inherits the operator's posture, so `bypassPermissions` is an escape and not the remedy — this is what keeps the ticket's out-of-scope note from being re-litigated by the next run.
- **`## Decision Ledger`**, with at minimum:
  - `D-1` — **`entry` cuts-or-reuses the lane worktree.** Rationale as above. Consequence recorded honestly: the cut moves from *after* the claim to *before* it, so a lost claim race can now leave a stray branch+worktree. Mitigation: `cmd_entry_sweep` already runs immediately before, `require_ticket_live` (exit 10) has already refused a closed/unresolvable ticket by then, and `teardown` reaps. Alternative considered and rejected: a separate `bash G worktree <issue>` subcommand — smaller blast radius, but it makes AC-1 literally false and leaves the guarantee dependent on the session typing the right command, which is the class of defect this ticket is about.
  - `D-2` — copy via `cat src > dst`, never `cp`, never `ln -s`. A fresh regular destination file, so a symlinked *source* cannot make the destination one either.
  - `D-3` — provisioning is **advisory**: it warns and returns 0. `entry`'s exit status is owned by the audit-ledger predicate alone (`cmd_entry_sweep`'s stated posture); a settings copy must not become a second reason a run cannot start.
  - `D-4` — it **says out loud** what it copied. A permission-posture change nobody can see in the transcript is unauditable, which is the same failure mode as the silent one being fixed.
- **`## Open Regions`** — `OR-1`, the ticket's: whether to copy `.claude/settings.json` when it is tracked. Reversible default taken: **never clobber**, so a tracked file (already in the worktree from git) is skipped, and only an *untracked* origin `settings.json` is copied. One rule covers AC-3 and OR-1 at once. Flagged in the PR per the ticket.
- No `## Design` section — this repo declares no `design.provider`, so milestone 3 is disarmed and no render receipt exists.

## Phase 2 · Implementation — milestone 2/3

**2.1 `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`** — me. Two additions, in a new `# --- lane worktree provisioning (#647)` section placed beside the existing worktree block (~line 1928, ahead of `cmd_entry_sweep`):

- `provision_lane_settings <worktree>` — for `settings.local.json` and `settings.json` under `$MAIN_ROOT/.claude`: skip when the destination already exists (AC-3 + OR-1's default), skip when the source is absent (AC-1's negative fixture: no file, no error), otherwise `mkdir -p <wt>/.claude` and `cat src > dst`. No-op when `<wt>` is `$MAIN_ROOT`. Every copy and every skip gets a `say` line.
- `cmd_entry`, after `cmd_entry_sweep` and before `return 0`: resolve registered worktrees with the existing `lean_worktrees_for_branch "$LEAN_BRANCH"`; **reuse** and provision each when present; **cut** one when absent, at `$(resolve-worktrees-dir.sh)/<branch slug>` — reusing `plugins/dev-pipeline/tools/resolve-worktrees-dir.sh` rather than re-deriving `../<repo>-worktrees` a second time — then provision it. A failed cut warns and names the manual `git worktree add`; it does not change `entry`'s rc.
- File-header docs: the `entry` usage block (~line 79) and a paragraph explaining *why* a git worktree structurally cannot inherit a gitignored allowlist, with the `git check-ignore` evidence from the ticket.

**2.2 `plugins/dev-pipeline/skills/build-lean/SKILL.md`** — me. Step 1 gains "…and cuts (or reuses) this run's lane worktree, provisioning it with the operator's Claude settings"; step 3 becomes "`cd` into the worktree `entry` named" instead of "Cut a worktree on `<lean prefix><issue>`". (AC-7)

**2.3 `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh`** — me. Comment-only edit at the `LEAN_SPAWN_PERMISSION_MODE` documentation block. (AC-8)

**2.4 `.claude/settings.json`** — me. The interim, this-repo-only remedy (AC-4). Adds a `permissions.allow` array with the three allows the dogfood lane needs — invoking `lean-gate.sh`, `gh`, and `git fetch` — plus `"//"`-keyed comment lines naming **#647** and stating that this block retires once AC-1 ships. `"//"` comment keys are established precedent here (`plugins/audit-toolkit/templates/settings.audit-template.json`) and survive `jq empty`, which lints every JSON in the repo. **This file must be committed to take effect** — an uncommitted one is invisible to the worktree for the identical reason the ticket describes.

## Phase 3 · Tests — the oracles

**3.1 `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`** — me. A new `(ws*)` case block, sited next to the existing `(d5)` linked-worktree `entry` case (~line 585), which is the suite's established idiom for driving real `entry` against a fixture worktree. Each case builds a throwaway `git init` main checkout, seeds the audit ledger `entry` requires, runs the real gate, and asserts on disk:

| case | AC | asserts |
|---|---|---|
| ws1 | AC-1 | origin has `.claude/settings.local.json` → worktree copy is byte-identical |
| ws2 | AC-1 | origin has none → worktree cut, no file, `rc=0`, no error text |
| ws3 | AC-2 | copy is `-f` and **not** `-L` |
| ws4 | AC-2 | writing to the worktree copy leaves the origin's bytes unchanged |
| ws5 | AC-3 | a pre-seeded, *different* worktree copy survives a re-entry unmodified |
| ws6 | OR-1 | a **tracked** origin `settings.json` is not overwritten in the worktree |
| ws7 | OR-1 | an **untracked** origin `settings.json` is copied |

Naming the invariant and why no existing scenario covers it, per CLAUDE.md's "scenario-first" rule.

**3.2 `tools/mutation-catalog.tsv`** — me. One row anchoring the no-clobber guard: a sed that deletes the destination-exists early return must be killed by `(ws5)`. This is the "test-the-tests" obligation for a newly added guard.

**3.3 `docs/testing.md`, *Couplings considered and declined*** — me. Records why the three allows in `.claude/settings.json` are **not** lockstep-paired to the gate call sites they cover (the coupling is real but not byte-anchorable, and the block is interim by construction), and why this change adds no `scenario-liveness-selftest.sh` case (it reaches no verdict path — it is advisory and returns 0 unconditionally).

## Phase 4 · Verification — milestone 3 (AC-5)

Mine, run from the lane worktree, all three from CLAUDE.md's Verification section:

```
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

`rc=0` from `bash G 3 647` is the only evidence it passed. I expect churn in `lean-gate-selftest.sh` and `scenario-liveness-selftest.sh` from the relocated cut; fixing that fallout is part of this phase, not a follow-up.

## Phase 5 · Commits and PR — milestone 3→4 handoff

**5.1 Commits** — me, through `bot-commit.sh`. Verb is **`feat(dev-pipeline):`**, not `chore:` — consumers gain a behavior they did not have, and CLAUDE.md is explicit that typing it `chore:` silently downgrades a minor release to a patch. Body carries (AC-6):

```
Changelog: the lean lane's build worktree now inherits the operator's Claude
  settings from the origin checkout, so a build session runs with the allowlist
  the operator consented to instead of falling through to the classifier.
  Migration: none required. The gate copies .claude/settings.local.json (and an
  untracked .claude/settings.json) into the worktree at `entry` and never
  clobbers an existing file; an operator who wants the old behavior deletes the
  copy. `entry` now also cuts the lane worktree, which build-lean step 3 used
  to do by hand.
```

I will **not** touch `CHANGELOG.md` or any `plugin.json` `version` — `scripts/check-frozen-files.sh` reds the PR for either.

**5.2 Cost block** — `pipeline-cost-block.sh --stateless --issue 647`.

**5.3 The PR** — me. Ready (non-draft), against `main`, with: summary, link to `docs/plans/second-shift-647-lean.md`, `Closes #647`, the cost block in the description, and an explicit **"Open region OR-1"** paragraph stating the reversible default taken on tracked `settings.json`. Then `bash G mark 647` — at step 7, not milestone 5, because a PR comment fires no `pull_request` event.

## Phase 6 · Review — milestone 4 (not mine)

**6.1 `docs/plans/second-shift-647-lean-verdict.md`** — produced by a **separate** top-level session, `/dev-pipeline:review-lean <pr>`, with its own identity. I dispatch no reviewer and I do not write this file; `lean-gate.sh` refuses `verdict` inside a build session by design (P10). `bash G 4 647` passes only on a committed `verdict=approve` whose `reviewed_patch_id` is this branch's current patch. On `needs-work` I fix every blocker, push, and request a **new** review context — never a resumed one.

## Phase 7 · Close-out — milestone 5

**7.1** `bash G all 647` (re-evaluates everything against the current tree), then **`bash G close-out 647`** — one call: recomputes the published cost figure, writes the `cost-log.jsonl` row, replaces the stale block in the PR description, posts the single closing comment, asserts milestone 5, and tears the worktree down. I leave the `claimed` label alone; the repo's unclaim workflow releases it when the issue closes.

**7.2 Merge** — the operator's, gated by CI: `check-frozen-files.sh`, `check-changelog-trailer.sh`, `check-lean-chain.sh`, both selftest jobs, and `mutation-sweep-pr`.

---

Two things I want your call on before I write code:

1. **D-1** — moving the worktree cut into `entry`. It's the only reading under which AC-1 and AC-3 are satisfiable, but it is a larger change than the ticket's prose implies, and it reorders the cut ahead of the claim.
2. The ticket's causal claim is that the worktree's missing allowlist is what the classifier fell through to. `orchestrate-lean.sh:717` spawns the payload with the *scheduler's* cwd, which is the main checkout, so the session's project directory — and the settings it loads at startup — should be the main checkout's. I'm not able to confirm the mechanism from the repo alone. The fix is worth making regardless (the worktree genuinely has no allowlist, and any gate call resolving settings from its cwd hits exactly the described hole), but I'd rather say so than write a spec that asserts a mechanism I could not verify.
