# lean review verdict — #492

verdict=needs-work
run_id: review-492-1
session_id: 8d44dca3-08b7-45f7-8f08-c67f80046c15
rounds: 1
pr: #501
reviewed_head: 6ee1a0558e5e9cbe1551eed22a4a87d7872d69ff
reviewed_patch_id: 11eaf8f04eb0fe97ba02c012b9c238ecb5eff947
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Verdict: needs-work — one blocker, and it is not in the code

The implementation is clean. All eight ACs of the committed spec are satisfied, the six-reviewer
panel returned zero substantive findings, and the new guards are genuinely load-bearing: ten
hand-applied mutants of the new production logic were each killed by a named new case. The single
blocker is the branch's state, not its diff — PR #501 cannot merge and has never run CI.

## Blocker

**B-1 — the branch is unmergeable against `main`, and consequently has zero CI evidence.**

Verified facts:

- `mergeStateStatus: DIRTY`; `git merge-tree --write-tree origin/main HEAD` exits 1. The conflict
  is with #491 (`a downgraded review model now costs a stated reason`), which merged at 15:22Z —
  **38 minutes before this PR was opened at 16:00Z**. Overlap: `orchestrate-lean.sh` and
  `orchestrate-lean-selftest.sh`.
- `git ls-remote origin 'refs/pull/501/*'` returns only `refs/pull/501/head` — there is no
  `refs/pull/501/merge`. GitHub could not construct the merge commit the `pull_request` event
  builds against, which is the evident reason no workflow was ever queued.
- `statusCheckRollup` is empty and `gh run list --branch claude/second-shift-492` returns nothing.
  Sibling PR #499 on this repo carries six checks (`lint-and-selftests`, `mutation-sweep-pr`,
  `pr-gates`, `selftests (macos, bash 3.2)`, …). This branch has run none of them, ever.

Two consequences make this a blocker rather than a note:

1. **The PR body's green claims are unverified by the lane's own machinery.** "both suites green"
   I did reproduce locally. "Generic mutation survivor ordinals on both edited guards are unmoved
   from the base, so nothing is owed to `tools/mutation-baseline.tsv`" is exactly what
   `mutation-sweep-pr` exists to check, and that job has never executed here. Neither has the
   stock-bash-3.2 macOS lane.
2. **An `approve` recorded now could not survive to the merge boundary.** Resolving the conflict
   changes lines, and this lane's contract voids a verdict record on any push that changes a line
   — a conflict-resolving rebase included. Certifying a patch that provably cannot land is not a
   cheaper path; it spends the round and buys nothing.

**Remedy.** Rebase onto `origin/main` (now `7b708f7`, which also carries #499). The reconciliation
is mechanical but touches three places this diff also edits, so it is real work, not a replay:

- the option parser — main split the columns and added `--review-model-basis`; this branch adds
  `--max-continuations` to the same block;
- the `-h|--help` range — main moved it to `sed -n '2,62p'`, this branch to `sed -n '2,95p'`; the
  merged header needs its own number. Case `(n)` guards it (asserts the output reaches
  `Exit: 0 = approved` and stops before `set -uo pipefail`), so a bad number reds rather than
  drifting;
- the `say "build model: …"` line — main appends `$REVIEW_BASIS_NOTE`, this branch appends
  `· continuations: $MAX_CONTINUATIONS`.

Then re-run both suites and let CI run for the first time.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `orchestrate-lean.sh` build phase re-spawns when the token moved; prompt is the unchanged `/dev-pipeline:build-lean $ISSUE`. Cases `(o1)` (second spawn, run reaches REVIEW) and `(o2)` (fresh `-p`, no `--resume`/`--continue`/`-c`). |
| AC-2 | satisfied | `--max-continuations`, default 2; exhaustion is a `HARD STOP` naming the cap. Reset is per build phase — `continuations=0` at the top of each round's inner loop, whose only exit is a PR. Cases `(o3)` (ordinal against the shipped default), `(o5)` (bound honored and named), `(o6)` (`0` restores pre-#492), `(o7)` (non-numeric is a usage refusal). |
| AC-3 | satisfied | Token equality → today's message, one spawn. `(j2)` unchanged, and `(j3)` is the anti-vacuity check that `(j2)` reached its stop *by reading* the predicate — without it `(j2)` would pass with the feature absent. |
| AC-4 | satisfied | The scheduler never invokes a milestone evaluation. Verified in-source that `cmd_progress` reaches neither `record_build_session` (called only from `cmd_entry`/`cmd_claim`) nor `ensure_progress_file`; `(pg8)` asserts the file is not even created. The gate's `rc=4` path is untouched. |
| AC-5 | satisfied | Predicate lives in the new read-only `lean-gate.sh progress`, returning `progress-v1:<n>`. Bookkeeping excluded — `(pg1)` scores the mixed fixture at 2 over `entry`/`session`/`budget-exhausted`/`skipped`/`armed`/`verdict` rows, including a reason string saying both verbs in prose. `(pg10)` pins the generation prefix. |
| AC-6 | satisfied | `(o1)`, `(j2)`+`(j3)`, `(o5)` — the three cases the AC enumerates, plus `(o4)` measuring that the read is made from the main checkout with `RUN_ID` scrubbed. |
| AC-7 | satisfied | Close-out compares `progress --satisfied 5` across the spawn and requires a **new** row; verify-only. `(p1)` (uncredited ⇒ non-zero naming what is unmet, not `done`), `(p2)` (not re-spawned — three spawns, not four — and the check is milestone-scoped), `(p3)` the positive control. |
| AC-8 | satisfied | `progress` exercised by `(pg1)`–`(pg12)`; AC-7's cases in the orchestrator suite; `(pg8)` non-creation; `(pg9)` the positive control that a build-role call on that same unattested run *does* refuse, which is what makes `(pg8)`'s ungated read mean something. Confirmed in-source that `progress` is absent from `require_entry_attested`'s set. |

## Guard quality — probed, not assumed

Ten mutants applied to the new production logic, each scored against the case expected to catch
it. **All ten were killed.**

| Mutant | Killed by |
| --- | --- |
| broad token counts every timestamped row (the naive "did the file change") | `(pg2)` |
| `--satisfied` loses its `satisfied`-only narrowing | `(pg5)` |
| `cmd_progress` gains `ensure_progress_file` | `(pg8)` |
| `--satisfied` numeric validation dropped | `(pg11)` |
| `--satisfied` accepted on a subcommand that ignores it | `(pg12)` |
| unreadable predicate degrades to an empty token instead of non-zero | `(o8)` |
| close-out credited on exit status again (the pre-#492 defect) | `(p1)` |
| continuation cap removed | `(o5)` |
| no-progress stop removed | `(j2)` |
| close-out's `before` read loses its milestone-5 scoping | `(p1)`, `(p3)` |

Both suites are green at this head, run with `env -u CLAUDE_CODE_SESSION_ID`.

## Warning

**W-1 — a re-entered lane can never be credited with its close-out, and that is undocumented.**
`append_satisfied` is idempotent (`lean-gate.sh:776` appends only when the count is 0), and the
progress file is keyed by issue, not by run. So on a second full lane run over an issue whose
record already carries `| milestone-5 | satisfied`, the close-out's `m5_after` necessarily equals
`m5_before`, and a correct close-out is reported as a failure. This is the deliberate fail-closed
side of D-8's "the row must be NEW", and the failure is loud, hand-recoverable, and far preferable
to a false `done` — so it is not a blocker. But neither the spec nor the code comment says the
requirement *also* costs the legitimate re-entry, and a future reader will hit it as a puzzle.
One sentence in the AC-7 comment naming the trade would close it. Reachability is low within a
run: `all` stops at milestone 4 during the build phase, so milestone 5 is satisfied only at
close-out.

## Suppressed / dismissed

- **`scope-completeness-reviewer`, confidence 92 — "AC-7 ships although issue #492 lists the
  close-out spawn as out of scope."** Dismissed: the reviewer read the issue body only. A later
  comment on the same issue explicitly proposes AC-7 to fold in, and pre-flight ledger D-8/D-9
  record the mechanism override with reasons (`ticket-sourced`, citing that comment). The spec was
  not amended to match the diff — the widening predates the build and is traceable to two
  artifacts. The spec's refutation of the issue's original rationale is also technically correct:
  step 9 ends with `teardown`, so a scheduler-invoked `bash G 5` has no worktree on the happy
  path, and a failing one would consume milestone 5's fix budget in violation of AC-4.
- `security-reviewer`, confidence 30 — hardcoded `--help` sed range is a drift risk. Pre-existing
  pattern, and case `(n)` guards it.
- `security-reviewer`, confidence 40 — `progress_token` discards gate stderr via `2>/dev/null`.
  The explicit non-zero return keeps the failure loud; `(o8)` covers it.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 1 (dismissed above) |
| Security | Pass | 0 |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 |
| Test Coverage | Pass | 0 |

No reviewer went dark. a11y and the design-fidelity dimension were not routed: no changed path
matches `stageParams.webComponentGlobs` (unset; default `apps/web/**/*.{tsx,jsx}`). The spec has
no armed `## Design` section, so fidelity is `not-applicable`.

## What the code does well

- The predicate is genuinely opaque at the seam. The scheduler compares two strings and never
  parses one, so `orchestrate-lean.sh`'s stated boundary survives it gaining a third thing to
  read — and the `progress-v1:` prefix makes a caller reaching for `-gt` notice it is not an
  ordinal.
- The soundness argument for a count-as-token is stated *and* true: I verified the only rewriter,
  `heal_progress_run_id`, uses an exact-string awk compare bounded to the `run_id: unset` header,
  so no body line can be rewritten and the count cannot go up and back down within a spawn.
- The fail-open path everyone gets wrong is closed. An unreadable gate returns non-zero rather
  than an empty token, precisely because empty-equals-empty would read as "did not advance" —
  the same error-reads-as-success shape the ticket exists to remove, which would otherwise have
  been reintroduced one layer down.
- The selftest fake earns its keep: past the end of a scripted token stream the last line repeats,
  so a case that scripts two reads cannot have a third invent a change, and the loop advances on
  the tool's logic rather than the fixture's exhaustion.
- `(j3)` and `(pg9)` are both anti-vacuity controls for assertions that would otherwise pass with
  the feature absent. That is the habit this repo keeps asking for and rarely gets.
