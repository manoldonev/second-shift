Before the plan, two things I found in the code that the plan has to account for.

**1. The ticket's fix site does not exist.** The ticket says `lean-gate.sh entry` copies settings into the lane worktree "when it cuts it." `entry` never cuts a worktree, and neither does anything else in the repo:

- `lean-gate.sh:2611-2612` — "`entry` runs before checklist step 3 cuts this run's worktree, so it is always executing outside it."
- `build-lean/SKILL.md` step 3 — "Cut a worktree on `<lean prefix><issue>` from the configured base" is prose addressed to the session, not a command.
- `tools/resolve-worktrees-dir.sh:8-9` — "The lean lane cuts its worktree **by hand** per `build-lean` step 3, so it is not a caller."

There is no `git worktree add` for the lane anywhere outside `mutation-sweep.sh`'s sandbox pool. So AC-1's "after `entry` cuts a lane worktree" is unsatisfiable as written, and the plan below resolves it by making it true (D-1).

**2. This base predates a merged implementation of this same ticket.** `main` carries `53a6753` — "The lane worktree inherits the operator's Claude settings, so a build session no longer gambles on the permission classifier (#657)" — plus `f8f7c14` and `bbef4d9`. My HEAD `b657907` is not a descendant of it; the worktree is `/private/tmp/ablation-644/wt-c1-647` and `refs/ablation/pr657` exists, so this reads as the #652 campaign's arm-c replay of #647 from a pre-merge base. I have **not** read that implementation and will not — it would contaminate the comparison. Consequence for the plan: the terminal state is a PR on `claude/second-shift-647`, and "merged into `main`" is not literally reachable from this base. Tell me if this is a real lane run and I will re-derive the base.

Everything below is written as a real lane run, which is what you asked for.

---

# Plan of record — #647

## Phase 0 — pick-up (no code)

| # | Artifact | Where | Who |
|---|---|---|---|
| 0.1 | `entry` attestation row | `.claude/pipeline-state/647-lean-progress.md` (gitignored, main checkout) | `bash G entry 647` |
| 0.2 | Intake confirmation | read-only | me |
| 0.3 | Claim writes: `queue`→`claimed` label swap + bot `lean-claimed` marker comment | issue #647 | `bash G claim 647` via `gh-bot.sh` |
| 0.4 | Lane worktree + branch `claude/second-shift-647` | `<worktreesDir>/647` | me, by hand (step 3) |

`export RUN_ID` before 0.3; it keys every record and seeds `647-run-id`.

**0.5 — read the pre-flight ledger.** If `.claude/pipeline-state/647-ledger.md` exists it is binding input, not advice. Every `user-answered`/`user-delegated` row is projected into the spec with `plugins/intake-toolkit/skills/plan-interview/tools/ledger-carry-forward.sh` under the same `D-n` id and Resolution text, or carries `DEPARTURE — <reason>`. Never retyped. If a bound row's subject is gone, I abort to intake rather than re-decide it.

## Phase 1 — the spec (milestone 1)

**Artifact: `docs/plans/second-shift-647-lean.md`.** Author: me. Committed through `bot-commit.sh` before any implementation. Contents:

- The problem statement and the measured evidence, restated from the code at this head, not from the ticket prose.
- `AC-1`…`AC-6` verbatim from the ticket, plus `AC-7` (below) — ≥1 numbered `AC-n` is what `bash G 1` counts.
- A `## Decision Ledger` — 4-column `| D-n | Decision | Resolution | Provenance |` rows, validated by `ledger-lint.sh` (`cmd_1` runs it whenever the section is present):

| D | Decision | Resolution I will carry |
|---|---|---|
| D-1 | Where the copy happens, given `entry` cuts nothing | `entry` gains an idempotent *ensure-then-seed*: resolve lane worktrees for the branch (`lean_worktrees_for_branch`, #530); if none, cut one from the configured base at `resolve-worktrees-dir.sh`'s path; then seed. This is the only site where AC-1's sentence can be literally true, and `entry` is the one mandatory attested call that precedes step 3. Step 3 becomes "cd into the worktree `entry` cut," with the hand form kept as the rescue path. |
| D-2 | Failure posture, split | **Cut failure is fatal** (the run has no tree). **Seed failure is a loud WARN, never fatal** — an absent source file is the normal case (AC-1 second half), and refusing a run because a convenience copy failed is worse than the classifier gamble. Precedent: `cmd_entry_sweep` "can never fail its caller"; the telemetry warn in `cmd_entry`. |
| D-3 | Seeding a file no ignore rule covers | **Refuse to write it.** An unignored `.claude/settings.local.json` in the worktree makes `git status --porcelain` non-empty, which dirties `worktree_inflight()` and the pre-flight `workingTreeClean` attestation. The seed checks ignore coverage of the *destination* first and says why when it declines. |
| D-4 | The ticket's open region — copy `.claude/settings.json` when tracked | Take the ticket's reversible default: **skip it**, copy only what the worktree lacks, and flag it in the PR. |
| D-5 | Breadth of AC-4's `gh` allow | Narrow (`Bash(gh api:*)`, `Bash(gh pr:*)`) rather than `Bash(gh:*)`, and the committed prose must match what is committed — a tracked allow the file's own comment disowns is a finding. |

- An `## Open Regions` section naming D-1 and D-4 for operator ratification. D-1 exceeds the ticket's literal instruction because the machinery it presumes is absent; per P9 I write it down and flag it rather than deciding it silently. It is **not** a `pause-and-ask` block — I do not stall the run on it.
- No `## Design` section: this repo configures no `design.provider`.

**AC-7 I am adding** (oracle — selftest): the seed refuses to write a destination no ignore rule covers, and says so; a worktree seeded by `entry` leaves `git status --porcelain` empty. Without this, AC-1's own success breaks the in-flight predicate.

Gate: `bash G 1 647` green (AC count, ledger lint, receipt reconciliation, no unresolved pause-and-ask region).

## Phase 2 — implementation

Author: me. All commits through `bot-commit.sh` (re-passing identity on any `--amend`).

| # | Artifact | Change |
|---|---|---|
| 2.1 | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` | `seed_lane_settings <dest>` + `ensure_lane_worktree`, wired into `cmd_entry` **after** `cmd_entry_sweep` (so the sweep never considers the tree just cut) and before `return 0`. Copy with `cp`, never `ln -s`. Never clobber an existing destination. Ignore-coverage check per D-3. Update the stale `cmd_entry_sweep` header comment at :2611. |
| 2.2 | `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` | New cases, one per oracle: AC-1 present / AC-1 absent-and-silent / AC-2 regular-file + write-isolation from the origin copy / AC-3 no-clobber on re-entry / AC-7 ignore-refusal + clean `porcelain`. Each fixture pins its **own** `.gitignore` or `core.excludesFile` — a fixture that inherits the operator's global ignore is measuring their home directory, not the code. |
| 2.3 | `plugins/dev-pipeline/skills/build-lean/SKILL.md` | Step 1 and step 3 rewritten for D-1. Budgeted by `tools/prose-budget.sh`. |
| 2.4 | `.claude/settings.json` | AC-4: `permissions.allow` with the gate script, narrow `gh`, `git fetch`, plus a top-level `"//"` key naming #647 so its removal is traceable. Verify the settings loader tolerates the key; if it warns, the note moves to `.claude/SECOND-SHIFT.md` and the ledger records why. |
| 2.5 | `scripts/gate-buckets.tsv` | A bucket row for every new refusal site the shape enumerator sees (`gates-signal` for the cut failure). An unclassified site reds — this landed at HEAD in #654. |
| 2.6 | `scripts/fail-open-sites.tsv` | A row for D-2's warn-only seed if `check-fail-open-shapes.sh` enumerates it. |
| 2.7 | `tools/mutation-catalog.tsv` | Probe every new assertion; add a row only where it names a regression class no existing suite catches, and re-anchor any row whose guard code I edited (anchors are literal seds). |
| 2.8 | `docs/testing.md` | Only if a coupling is real but not byte-anchorable → *Couplings considered and declined*. |

Not touched: `plugin.json` versions, `CHANGELOG.md`, `marketplace.json` — `check-frozen-files.sh` rejects a feature PR that does.

## Phase 3 — verification (before any handoff)

1. `find . -name '*.sh' -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181` — CI runs 0.9.0, brew is 0.11.0; skew is real.
2. `find . -name '*.json' -print0 | xargs -0 -n1 jq empty`.
3. **AC-5:** `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` — green, backgrounded (it outruns the 2-minute Bash cap), under `caffeinate -dims`.
4. `bash G 2 647`, then `bash G 3 647`.
5. The `pr-gates` steps locally: `check-changelog-trailer.sh`, `check-frozen-files.sh`, `check-guard-budget.sh`, `check-gate-buckets.sh`, `check-fail-open-shapes.sh`, `check-lockstep-pairs.sh`, `tools/prose-budget.sh`, and `mutation-sweep.sh` in PR mode.
6. Anything in the ticket's ACs that is a *measurement* gets re-measured after the last commit, not before it.

I will not wait on CI before the handoff — `pr-gates` cannot be green pre-handoff, since the verdict check is one of its steps.

## Phase 4 — the PR

- **Commit(s)**: `feat(dev-pipeline): …` (a new capability is `feat`, not `chore`), with **AC-6's `Changelog:` + `Migration:` lines** — consumers gain a behavior they did not have, so `Migration: none` is wrong here; it names what a consumer sees on their next `entry`. Plus `Guard-mass:` if guard/test shell mass grows.
- **Cost block**: `pipeline-cost-block.sh --stateless --issue 647` — derived, never reconstructed.
- **PR**: ready (non-draft) on `claude/second-shift-647`. Summary, link to the spec, unbackticked `Closes #647`, cost block in the description, and an explicit flag of the D-1 and D-4 open regions.
- `bash G mark 647` — at step 7, not milestone 5, so the marker is visible to the CI run that gates the merge.

## Phase 5 — review (produced outside this session)

- **`docs/plans/second-shift-647-lean-verdict.md`** — author: a separate `/dev-pipeline:review-lean <pr>` session, committed and pushed to the head branch by it. Never me.
- `bash G 4 647` passes only on a committed `verdict=approve` whose `reviewed_patch_id` **is** this branch's current patch.
- On `needs-work`: fix every blocker, push, request a **new** review context. Any content pushed after an approve costs another round.

## Phase 6 — close-out

- `bash G all 647` (re-evaluates everything against the current tree), then `bash G close-out 647` — one call: recomputed cost row, PR description replacement, the single closing comment, milestone 5, worktree teardown. Leave the `claimed` label alone.
- **Retro and memory writes before cleanup**, not after.
- **Merge only on your explicit per-action authorization.** I will not merge on my own.

---

Two answers would change the work, and neither blocks me from starting: (a) real lane run vs. ablation replay — it decides the base and whether Phase 4–6 exist; (b) whether you ratify D-1 (fold the cut into `entry`) or prefer a separate `bash G worktree <issue>` subcommand, which keeps `entry`'s exit contract untouched but leaves the cut skippable. My recommendation is D-1 as written. I have not written any code.
