# lean review verdict — #590

verdict=approve
run_id: review-590-1
session_id: 6ecc9dbd-9127-4d66-9ece-9a360985a92c
rounds: 1
pr: #627
reviewed_head: 1733cb30f1bce200d3b0161dbaa0f2c29511d1ba
reviewed_patch_id: 29b059491260ee3ba57909078c6dd5c35e56ef25
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full branch range `ab0a2d68..1733cb30` (13 files, +1101 −417). The change replaces the
lane's third model session with `lean-gate.sh close-out <issue>`, moves #546's three cost
obligations into it as asserted rows, reorders one guard in `cmd_mark`, and deletes the
scheduler's continuation budget, its progress-token delta and three-quarters of its close-out
terminal vocabulary. The two-identity contract survives: every close-out write goes through
`closeout_writer`, which is the bot wherever one is configured, and the scheduler's call scrubs
both `RUN_ID` and `CLAUDE_CODE_SESSION_ID` — asserted at the seam by `(b1a)`.

All 15 ACs are satisfied. The panel (security, performance, maintainability, complexity,
test-coverage, scope-completeness) returned six approves and zero findings; the three warnings
below are the orchestrator's own reading of the diff, not reviewer findings, and none of them
blocks.

Verification performed in this review, beyond reading:

- **Both re-anchored `tools/mutation-catalog.tsv` rows apply.** Run under `sed -E`, exactly as
  `mutation-sweep.sh:1850` invokes them, each changes exactly one line
  (`lean-gate.sh:5949` and `:5945`) and neither is a silent no-op. This is checked by hand because
  a stale anchor reads as green — `--mode pr` can exit 0 having produced zero verdicts. Both
  mutants are killed by the cases this PR adds: dropping `close-out` from the entry-attestation
  arm reds `(ea5a)` and `(ea5)`; dropping it from the lane-tree arm reds `(lt1)`, which iterates
  all nine subcommands.
- **`scripts/check-lockstep-pairs.sh`: 27 anchors, 0 failed** — the new `lean-cost-block-bounds`
  pair is discovered and its two copies agree, so `COST_BLOCK_TERMINATOR` cannot drift away from
  the renderer that emits it.
- **The writer and the reader of the closing comment agree.** `closeout_comment` emits
  `` - Verdict record: `$VERDICT_REL` `` and `cmd_5`'s github arm selects on
  `(.body // "") | contains($VERDICT_REL)`, so the backticks do not defeat the match. `VERDICT_REL`
  is a file-scope global (`lean-gate.sh:962`), not a `cmd_verdict` local, so it is bound on this
  path.
- **The detail field does not disturb the obligation record.** `append_obligation`'s new
  `${4:+ | $4}` sits after the triple, and both `obligation_state` and the idempotence bound match
  the triple as a fixed substring — so a row carrying a detail is read and deduped exactly as a
  bare one. Checked the near-collision explicitly: the fixed key `| obligation | cost-block | met`
  does not occur inside a `pr-cost-block` row, because the character before `cost-block` there is
  `-`, not a delimiter.
- **`lean-gate.sh` runs `set -uo pipefail`, not `set -e`**, so `[ -n "$LEAN_COST_SKIP" ] && detail=…`
  at the end of a `&&` chain cannot abort the command, and `run_milestone "$n"; rc=$?` reads a real
  exit code.
- **AC-10 measured**: `run-lean/SKILL.md` is 60 lines on `main` and 60 lines here.
- **AC-14 recomputed** from `--numstat`: +1101 −417, net +684, matching the PR body. The
  per-surface table sums to +675; the missing +9 is the AC-15 file, which the body reports in its
  own section.
- **CI**: `lint-and-selftests` and `selftests (macos, bash 3.2)` pass; `mutation-sweep-pr` passes.
  `pr-gates` fails at 6s, which is the expected pre-handoff state — the verdict record this review
  writes is the thing it is missing.

## Strengths

- **The composed leg is the real writer now, and the PR says so honestly.** Leg 10 was previously
  a scheduler driving a *fake* close-out session; it now drives a real `bash G close-out` through
  the actual scheduler to a terminal write, with the failure injected at the code host
  (`GH_POST_FAIL`) rather than simulated in the record. The re-cut leg is strictly stronger than
  the one it replaces.
- **The teardown assertion documents its own marginal value instead of overclaiming it.** The
  comment states that two mutants were run, that both also red the rc/spawn assertions above, and
  that the line earns its keep only by being the sole assertion that reads the lane tree on a
  *stopped* close-out and by failing in AC-5's vocabulary. That is the opposite of the vacuous-
  green habit this repo keeps having to detect.
- **The PR-description replacement is bounded rather than truncate-to-EOF, and all four shapes are
  covered** — mid-body replace with human text below (`co1`), append when absent (`co2`), a marker
  whose terminator moved reported rather than performed silently (`co3`), and CRLF (`co4`). The CRLF
  case in particular guards a failure that would have passed every fixture while appending a second
  block to every real PR forever.
- **AC-15 fixes the leak by making it fail everywhere, not by removing the symptom.** Putting a
  hostile `LEAN_JOB_CEILING=2` in front of the scrub converts "reds only on a machine running
  enough lanes" into "reds on any machine", which is the right direction for a defect whose whole
  problem was that somebody else's concurrency decided whether the suite passed.

## Critical (must fix before merge)

None.

## Warnings (should fix)

- **`closeout_comment` is the one close-out write that is not idempotent, so a retried close-out
  posts a duplicate closing comment.** `lean-gate.sh` — the comment is posted unconditionally on
  the github arm, and everything downstream of it can still red: `cmd_5`'s `exit-artifacts` (draft
  PR, a missing `Closes #n`, an unlinked spec) and its `cmd_mark` call all run *after* the post. On
  that path `cmd_close_out` returns non-zero, the scheduler retries once, and the second call posts
  a second identical comment before reding again. The other two writes degrade correctly by
  construction — `append_obligation` dedups on the triple and the PR-body patch is a replace — and
  `cmd_mark` has exactly the guard this lacks. `cmd_5` already computes the predicate that would
  make it idempotent (`any comment containing $VERDICT_REL`); reusing it as a pre-check in
  `closeout_comment` is a few lines. Not a blocker: the lane's evidence predicate is `>= 1`, no
  gate misreads a duplicate, and it only manifests on a run already heading for a hand rescue.

- **The composed leg substitutes its own comment body, so the `closeout_comment` → `cmd_5`
  coupling is verified nowhere.** `scenario-liveness-selftest.sh` — the fake code host's `-X POST`
  arm appends `$GH_POST_BODY_MARK`, a body the *fixture* supplies, rather than the body production
  actually wrote (which is right there in `$*` as `-F body=@<file>`). So if `closeout_comment` ever
  stopped emitting `$VERDICT_REL` — a rename to a URL, a reformat — `(lean-closeout)` would stay
  green while every real lane redded at `verdict-reference` forever. I verified the two agree today
  by reading both sides; the point is that nothing would catch them diverging. `cat`ing the real
  body into the sink instead of `GH_POST_BODY_MARK` closes it at the cost of one fixture line, and
  this is the exact class the repo's "no mirror harnesses" rule exists for — a fixture asserting
  content it authored itself.

- **`cmd_close_out`'s non-skip cost branch is composed nowhere, and it is the branch this repo's
  own host will take.** The liveness leg deliberately points `OTEL_METRICS_FILE` at nothing, so its
  cost block is always a documented skip and `closeout_patch_pr_body` is never reached through
  `cmd_close_out`; `co1`–`co6` drive `closeout_patch_pr_body` and `closeout_cost_log_row` directly
  in `LEAN_GATE_LIB=1` library mode, not through the command. What is left untested is the glue
  between them — that a rendered block reaches the patch call, that the patch's note becomes the
  `pr-cost-block` detail, that `closeout_cost_log_row` is consulted only on the non-skip arm. AC-13
  anticipates the tier split, but it assigns this glue to neither tier. It is ~6 lines and it fails
  loudly (obligation unmet → close-out reds → the tree stands for rescue) rather than silently, so
  it is not a blocker — but this PR's own cost block proves the maintainer's host renders a real
  figure, which means the first production run of this command executes code no suite has run.

## Suggestions (consider)

- **The `m5_missing_milestones` precondition inside `cmd_close_out` is unreachable.** The `for n in
  1 2 3 4` loop immediately above it returns on any non-zero `run_milestone`, and a zero return
  means `satisfied` was appended — so `missing` is always empty by the time it is read. The comment
  acknowledges the loop is what makes the precondition holdable; worth saying explicitly that the
  check is retained as a belt-and-braces invariant rather than a reachable arm, or a later reader
  will try to construct the case that trips it.
- **An obligation's detail is first-write-wins.** Because the idempotence bound counts the triple,
  a close-out that recorded `cost-block met | …a documented skip…` and is later re-run on a host
  whose collector has since come up keeps the stale detail while the PR body gains a real figure —
  the record and the artifact then disagree about the same run. The state (`met`) stays correct in
  both, so this is cosmetic, and the trade is deliberate per `append_obligation`'s comment; it is
  only worth a line there noting that the detail describes the *first* time the pair was recorded.

## Plan Compliance

Implementation matches the committed spec (`docs/plans/second-shift-590-lean.md`). AC-2's D-2
scope growth — pulling three cost obligations into the command, against the issue body's
"Out: the cost block's derivation rule" — is amended in the spec with its rationale and is
carried in the PR body, so it is declared rather than silent. No scope creep found beyond AC-15,
which the spec declares as incidental and explains.

## Pre-existing gaps (not blocking this PR)

- The read-only-tracker arm keys on `TRACKER_TYPE = "jira"` rather than on a `tracker.writes`
  flag, in both `cmd_close_out` and `cmd_5`. A future `writes: false` adapter that is not jira
  would get a closing comment it cannot accept. `cmd_close_out` follows `cmd_5`'s existing shape
  exactly, so this PR introduces no new gap.
- `closeout_writer` falls back to `$GH_CLI` when no bot is configured, while `cmd_mark` uses
  `${GH_BOT:?…}` and hard-fails. The fallback is the safer direction and is documented at the
  function, but the two differ on the same question.

## Suppressed (below confidence threshold)

- security-reviewer (45): `LEAN_COST_BLOCK_TOOL` is an env-controlled path executed via `bash` —
  the same trusted-local seam as the pre-existing `GH_CLI`/`GH_BOT` overrides.
- security-reviewer (40): `closeout_writer`'s operator-identity fallback on a bot-less consumer.
- security-reviewer (55): post-reorder, a non-build session can get rc=0 from `mark` on the
  already-marked no-op path. Nothing is written and no consumer reads `mark`'s exit code as an
  identity attestation — this is AC-6's intended behavior, and `(ms2b)` asserts it.
- security-reviewer (50): `gh` stderr folded into operator-visible error strings; matches the
  pre-existing `mark`/`cmd_5` error paths and carries no credentials.
- scope-completeness-reviewer (70): the D-2 scope growth, recorded as a Note.
- scope-completeness-reviewer (65): the AC-14 LOC accounting lives in the PR body, which is the
  surface the issue specifies.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `close-out` in both guard arms (`lean-gate.sh:5945`, `:5949`, probed above); calls `cmd_5` unchanged then `cmd_teardown`; `bash G 5` keeps its behavior — `resolve_open_pr`/`m5_missing_milestones` are extractions, not rewrites. `(ea5a)`, `(lt1)`. |
| AC-2 | satisfied | Order is re-compute → PR-body replace → comment; all through `closeout_writer`; jira arm skips the comment and says so. |
| AC-3 | satisfied | `LEAN_M5_OBLIGATIONS` carries five in execution order; `obligations_report` iterates it; no sixth row for the comment. Detail-vs-triple analysis above. |
| AC-4 | satisfied | Skip → three `met` rows with the reason named; non-zero → `cost-block` unmet and `return` *before* any post, since the block is computed first. Composed leg asserts the skip degradation. |
| AC-5 | satisfied | `cmd_teardown` is reachable only past `cmd_5 \|\| return $?`. Both halves asserted — tree absent after the green run, present after the stopped one. |
| AC-6 | satisfied | The guard moved behind the no-op and still precedes the only write (`mktemp`/`-X POST`). `(ms2a)` keeps #446's refusal, `(ms2b)` adds the pass the close-out needs, and the composed leg reds on a refusal if the order regresses. |
| AC-7 | satisfied | `closeout_rc` runs from `lane_worktree` with `env -u RUN_ID -u CLAUDE_CODE_SESSION_ID`; `(b1a)` asserts both scrubs. Continuation loop and token delta deleted. |
| AC-8 | satisfied | The four ids are gone from all executable surfaces — the single remaining mention is historical narrative in a selftest comment explaining why they died. `closeout-incomplete` echoes `closeout_report`; `(p2)`, `(p2a)`. |
| AC-9 | satisfied | Step 9 is one line. The jira note's "no closing comment (9)" and the two-tracker-writes rule both remain true under the gate-written comment. |
| AC-10 | satisfied | Restated to "authors nothing under your own identity" with the third-identity rationale intact; 60 lines before and after. |
| AC-11 | satisfied | Discontinuity note in `perf-retro/SKILL.md` and `cost-tracking-setup.md`; the step-9 description now names the gate. |
| AC-12 | satisfied | Leg 10 re-cut to BUILD → REVIEW → real `bash G close-out` → one retry → terminal row; the nv arm stops under `closeout-incomplete` with zero `milestone-5 satisfied` rows. |
| AC-13 | satisfied | Unit tier: `(ea5a)`, `(lt1)`, `(ms2b)`, `co1`–`co4`, `co5`–`co6`. Composed tier: the three obligations, the skip, teardown ordering. Split as specified. See Warning 3 for the seam the split leaves uncovered. |
| AC-14 | satisfied | +1101 −417 net +684, recomputed from `--numstat`; the deletion/addition narrative is honest about adding ~309 lines of production shell. |
| AC-15 | satisfied | The scrub goes in behind `LEAN_JOB_CEILING=2`, so dropping it clips the asserted `jobs=3` on any host rather than only a busy one. |

**Fidelity:** not-applicable — the spec has no `## Design` section and declares no render states.

**Ready to merge?** Yes.

**Reasoning:** Every AC is met, the guards added are non-vacuous (both catalog anchors verified to
apply and to be killed by the new cases; the composed leg's non-vacuity arm reaches no terminal
write), and the three warnings are all coverage-shape observations on paths that fail loudly
rather than correctness defects in shipped behavior.
