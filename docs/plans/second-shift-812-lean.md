# second-shift #812 — Lane bench: protocol document and cell scorer

Slice 1 of the lane bench (#811). It is the half that does not depend on #805: the protocol
document and the scorer. The arm wrapper and the runner are the successor slice, #813.

## Goal

Land `docs/lane-bench.md`, `tools/lane-bench-classes.tsv` and `tools/lane-bench.sh score`, so a
past or future lane cell on the private eval substrate can be scored against its hidden-test
overlay and its seeded-defect list from a results row and a cell id.

## Scope

### In

- `docs/lane-bench.md`, in the `docs/consumer-eval.md` style.
- `tools/lane-bench-classes.tsv` — the terminal-class map, as data.
- `tools/lane-bench.sh score` and its `tools/lane-bench-selftest.sh`.

### Out

- The arm wrapper, `lane-bench.sh run`, the isolation probe, and anything that touches the lane's
  spawn — #813, after #805.
- The substrate, the bench repo, the corpus, the pre-registration, the series baseline: all
  operator-authored, tracked on the epic.
- Any edit under `plugins/**`.

## Acceptance Criteria

- AC-1: WHEN the protocol document lands in second-shift THEN it states the arm definition
  (control, skeleton, candidate ref), the two tiers, the seven corpus roles, the gold definition
  with the per-defect detector pair, the results-row columns, the terminal-class table over the
  lane's full slug vocabulary, the comparability rule for `rounds` and `wall_min`, the cost bound
  (sequential cells on the subscription rate limit, `--max-rounds 2`, three repeats at the full
  tier), the pre-registration rule with its noise band and minimum detectable effect, the series
  definition with its re-baseline and append-only rules, and the anonymization rule, naming the
  private repos only as "the private eval substrate".
- AC-8: WHEN `tools/lane-bench.sh score` scores a cell THEN the row carries cell id, ticket role,
  arm, repeat, `harness_sha`, `cli_version`, build model, review model, terminal slug, terminal
  class, rounds, wall-clock minutes, `pr_head_sha`, hidden tests passed/total, `defects_at_head`
  (seeded defects whose test id fails at head), `defects_named` (seeded defects whose verdict
  regex matches any verdict record on the branch), `review_catch` (`defects_named` over defects
  seeded, `n/a` when no verdict record exists), and `scored_at`; a selftest over a fixture PR
  tree, overlay, and defect list covers every column, `n/a`, an unapplicable overlay, and an
  ambiguous PR.
- AC-11: No second-shift artifact of this work (issue, comment, PR, commit, doc) names a consumer
  repo, org, or GitHub App; checked by a denylist grep the operator keeps outside the repo, run
  over every PR of this work before merge.
- AC-12: No PR of this work edits a plugin `version` field or `CHANGELOG.md`.

AC-2 through AC-7, AC-9 and AC-10 are the epic's and are not this slice's to satisfy; AC-11 and
AC-12 bind every PR of the work and are restated here so this slice is graded against them.

## Design

Design: none — this slice ships a protocol document, a TSV, and a shell tool. It renders no UI
and no `design.provider` is configured for this repo.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Per-test verdict channel for the hidden overlay | Each ticket's overlay directory carries `run.sh`, executed by `score` from the PR-head worktree; it prints one `TEST <id> PASS\|FAIL` line per hidden test and exits non-zero on any FAIL. `tests_total` = TEST lines, `tests_passed` = PASS lines, `defects_at_head` = FAIL lines whose id equals a seeded defect's `test_id`. The substrate's configured `test` command is not run by `score`; it stays the lane's milestone-3 concern. Refines epic D-3/D-11 | user-answered |
| D-2 | Which verdict records count for `defects_named` | Every committed version of `<plansDir>/<repo-slug>-<issue>-lean-verdict.md` on the lane branch: `score` walks `git log --format=%H -- <path>` from `pr_head_sha` and matches each defect's `verdict_regex` (ERE) against each `git show <sha>:<path>`; a defect named in any version counts once. `n/a` when no version exists | user-answered |
| D-3 | Where the overlay is applied | A temporary `git worktree` of the substrate at `pr_head_sha` under `${TMPDIR:-/tmp}/lane-bench-score.XXXXXX` (explicit-template `mktemp -d`, the #780 form), overlay copied in with `cp -R`, removed on exit; never an in-place checkout (the lane's own worktree discipline; `orchestrate-lean.sh` never checks out in place) | codebase-derived |
| D-4 | PR resolution and `pr_head_sha` | `gh pr list --head <branchPrefix><issue> --state all --json number,headRefOid`; exactly one → its `headRefOid` at scoring time is `pr_head_sha` (a head that moved after the terminal is scored as found); zero → score columns empty; more than one → `terminal_class` set to `unscorable` (epic D-33) | codebase-derived |
| D-5 | Terminal-class table as data | `tools/lane-bench-classes.tsv` (`slug`, `class`, `condition`), the `tools/gate-ablation-classes.tsv` precedent; `score` reads it only to write `unscorable`; the doc links the file and does not duplicate its rows (`docs/testing.md`: no prose-presence guards, so a doc copy would be unguardable) | codebase-derived |
| D-6 | Refusal vs `unscorable` | `unscorable` (a row value): more than one PR, overlay `cp` failure, `run.sh` exits without printing any TEST line. Refusal (exit 2 on stderr, row untouched): `--results` row for the cell missing or lacking the pre-score columns, `--overlay` without `run.sh`, a defect `test_id` absent from the overlay's TEST lines on a successful run, config unreadable, `git worktree add` failure | codebase-derived |
| D-7 | Idempotence of `score` | Re-scoring a cell overwrites that row's columns from `pr_head_sha` onward and refreshes `scored_at`; earlier columns are never written by `score` (epic D-32) | codebase-derived |
| D-8 | Row parsing | TSV keyed on `cell_id`, header row required and validated against the 19-column contract; `score` rewrites the file atomically (`mktemp` + `mv` in the same directory, then restore the exec bit is not needed for a TSV) | codebase-derived |
| D-9 | Config resolution | `--config <eval config>` is read with the same `cfg` ladder `retro-corpus.sh` uses (`:105`, `:143`): `paths.plansDir` default `docs/plans`, `paths.pipelineStateDir` default `.claude/pipeline-state`, `tracker.branchPrefix`, the `topology.repos` key whose `path` is `.` as the repo slug; substrate root = the directory containing the config's `.claude/` | codebase-derived |
| D-10 | Doc structure | `docs/lane-bench.md` follows `docs/consumer-eval.md` section order: why the measurement exists, the arm definition, the corpus obligation, the gold definition, the pinned-base recipe by reference to `consumer-eval.md`, the metrics with one exact source each, the terminal-class table by link to D-5's file, the comparability rule, recording, and the pre-registration rule naming its fields (OR-1) | codebase-derived |
| D-11 | Selftest shape | `tools/lane-bench-selftest.sh` builds a fixture substrate repo under `mktemp -d "${TMPDIR:-/tmp}/lane-bench-selftest.XXXXXX"` with a lane branch, two committed verdict-record versions, a PR resolved through a `gh` fake on `PATH` (argv-discriminated, the `orchestrate-lean-selftest.sh` precedent), an overlay with a `run.sh` that reads a case-written outcome file; scenario-first cases per AC-8: every column, `n/a`, unapplicable overlay, ambiguous PR, each D-6 refusal, idempotent re-score | codebase-derived |
| D-12 | Sweep bookkeeping | New refusal guards get `tools/mutation-catalog.tsv` rows (writing-tests skill); `${VAR:-default}` sites are baseline-absent survivors on first push; suite timing row added to `tools/selftest-suite-timings.tsv` | codebase-derived |
| D-13 | Changelog trailer | `Changelog: none` — nothing lands under `plugins/**` | codebase-derived |
| D-14 | Pre-registration values named by the doc | parked under OR-1 (owner: operator, in the bench repo, before the first scored row) | deferred |
| D-15 | Where the terminal-class table's completeness is guarded | A case in `tools/lane-bench-selftest.sh` derives the slug vocabulary out of the shipped `orchestrate-lean.sh` (command-position `terminal`/`envfail` call sites, plus the one `terminal-vocabulary:` announcement) and requires `tools/lane-bench-classes.tsv` to name exactly that set, in both directions, failing closed when a call site does not match the modelled shape. The `scripts/check-lane-class-doc.sh` tier is declined for one reason: it would need its own CI step, and the subject here is the data file `lane-bench.sh` itself reads, which the tool's own suite already owns | codebase-derived |
| D-16 | The class of each slug | The epic's Data Contracts derivation is taken verbatim rather than re-reasoned: `approved` → `approved`; `build-no-pr` → `paused` with a milestone-1 `pause-and-ask` row in the progress record, else `no-pr`; `build-session-failed`, `review-session-failed` → `no-pr`; `rounds-spent`, `review-dark`, `verdict-gate-failed`, `verdict-budget-spent`, `verdict-self-authored` → `pr-unapproved` with a PR, else `no-pr`; `pr-ambiguous` → `unscorable`; every other slug, and any slug the table does not list, → `lane-error`. The two conditional families carry their condition in the row's third column; `lane-closed-out` and the `closeout-*` family are `lane-error` by that rule, which is the epic's call and not this slice's (https://github.com/manoldonev/second-shift/issues/811) | ticket-sourced |
| D-17 | `review-skipped-approved` | It is announced with a `terminal-vocabulary:` prefix but is not a terminal — the run falls into the close-out and terminals under another slug — so it carries a row whose class column is `-`, and the guard requires that. A results row can never hold it, and omitting it would leave the completeness guard unable to tell an announced member from a missing one | codebase-derived |
| D-18 | Suite cost | `tools/lane-bench-selftest.sh` gets a `tools/selftest-suite-timings.tsv` row only if it measures at or above that file's 9s threshold; below it, a row would be a stale-row hard error waiting to happen and the aggregate ratchet already counts it. Measured at implementation time and recorded in the PR body | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The keep-or-revert rule, noise band and minimum detectable effect the protocol document describes as the pre-registration's content; their values are the operator's, written in the bench repo, never in second-shift | reversible-default-and-flag |

OR-1's default, taken: the document names the fields and the rule that they are fixed before any
scored row, and carries no values. Reversing costs one doc edit.
