# lean review verdict — #805

verdict=needs-work
run_id: review-805-2
session_id: f2e7e8b1-d776-4c46-92aa-c3afe6038d40
rounds: 2
pr: #810
reviewed_head: 363585a230072d0f91bf3c81d98fc58213b95a26
reviewed_patch_id: a761670383a881a60b2ae1c61036c5b5710e16aa
inherited_patch_id: 270b43f222f5c50980af8a96be226886b36cb843
inherited_from_verdict: 27392d48bcce9c5bf8640a07434b9c479e0c277e
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer,review-toolkit:pipeline-reviewer
model: opus
capabilities: pr-marker

Round 2, delta `27392d48..HEAD` (the single fix commit `363585a2`), inheriting the coverage of
patch `270b43f222f5` from round 1's record. Read wider than the range where the delta was
misleading: the whole branch for AC-11's accounting, and `origin/main` for the shape of every
mechanism the narrowing removed.

Round 1's three blockers are all addressed at the behavior level, and two of the three are
genuinely well done. **B-1** is taken rather than argued: all four items the operator's
pre-authorized narrowing named are gone from the branch, and the negative is recorded with
commands that reproduce. **B-3** is fixed and now guarded — `(h4)` asserts
`claude attach <id>' reaches` rather than the prose alone. **B-2**'s behavior is fixed and
measured correct. What stops the round is that B-2's fix is unguarded, and the case the branch
added for it cannot see the mechanism it names.

## Blockers

**B-1 — AC-10: the enumerated case "the transcript surviving a terminal reached from inside the
poll" does not exist, and the case that claims to be it drives a path that no longer terminals
from inside the poll.**

The fix has two independent halves. The first is a routing change: `blocked` now RETURNS from
`poll_session` instead of calling `terminal` from inside the loop, so `spawn()`'s own
`spawn_close` reaches it on the ordinary return path. The second is the mechanism the fix's
commit message and comment are actually about — `spawn_close` inside `spawn_cleanup`, the funnel
`terminal` goes through — which is what covers the two arms that still exit from inside the poll:
`spawn-unreadable` (three unreadable or three unmodelled reads) and mid-flight
`staleness-expired`.

`(bg2b)` drives `blocked`. After this round's routing change that is the FIRST half, not the
second. Measured, control/mutant pair in an isolated worktree at the reviewed head, clean env:

- Control: the suite is 123 pass / 0 fail.
- Mutant — `spawn_close` deleted from `spawn_cleanup` ONLY, leaving `spawn()`'s call intact:
  the suite is **123 pass / 0 fail, all green**. `(bg2b)` does not notice.

So the half of the fix that closes the transcript on the paths whose own remedies point at it is
addressed by nothing. `(bg2b)`'s own comment states the opposite — *"A run that ends from INSIDE
the poll never returns to `spawn`… Driven through `blocked`"* — and the PR body's Verification
section repeats the claim. AC-10 enumerates this case by name.

The gap is guardable in six lines, and the guard is verified. Patch `(bg7)`, which is the
mid-flight `staleness-expired` case and reaches its terminal from inside the loop with
`SPAWN_SID` already set by tick 1:

```
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n0\n7\n' > "$STALENESS_RC_FILE"
mkdir -p "$CASE_HOME/.claude/projects/some-cwd-slug"
jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"FINAL-MESSAGE-FROM-BUILD"}]}}' \
  > "$CASE_HOME/.claude/projects/some-cwd-slug/sess1-full.jsonl"
out="$(LAUNCH_ID_OVERRIDE=bg7probe run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
bg7_log="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-bg7probe-1-build.log"
```
…then assert `[ -s "$bg7_log" ]` and `grep -q FINAL-MESSAGE-FROM-BUILD "$bg7_log"`.

Measured with exactly that assertion added:

- On the branch as pushed: all green, the transcript carries the final message.
- On the same tree with `spawn_close` removed from `spawn_cleanup`: **exactly one failure**,
  `(bg7probe)`, transcript **0 bytes**.

Disjoint from every other case, and it kills the mutant the shipped suite survives.

## Warnings

- **A `stopped` session is stopped again, and the operator is told it was "still in flight".**
  Round 1 cleared `SPAWN_ID` unconditionally after `poll_session`; round 2 clears it only in the
  `done|stuck` arm, deliberately, so `terminal` can stop a `blocked` one. The side effect is that
  `failed` and `stopped` now also reach `spawn_cleanup` with the handle live. Measured by dumping
  the fake's stops file at case `(j1a)`: `stops=[stop sess1]` and one occurrence of
  `still in flight` in the output, for a session the listing had just reported as `stopped`.
  Harmless — `stop_session` tolerates a failed stop — but the sentence is false on the one path
  where an operator is reading closely. `review-toolkit:unit-test-mutation-reviewer` reached the
  same site from the other direction at confidence 82: the `done|stuck) SPAWN_ID=""` clear is now
  load-bearing and no case exercises it, so a mutant dropping it makes `build-no-pr` re-stop a
  finished session and every assertion still passes.
- **AC-11's "Kept" inventory under-describes the branch.** It reads *"the prose corrections, the
  session id at dispatch, and `claude stop` for exit 7 — plus the poll those two require in order
  to exist at all"*. The branch also keeps the silence ceiling, the three-strike fail-closed
  refusal, the INT/TERM trap, the transcript's final-message close, the launch-ledger state
  change, the `gate-buckets.tsv` reconciliation, `--name` and `--disallowedTools`. None of those
  is entailed by an id at dispatch plus a stop on exit 7. The PR body's own feature bullets and
  raw figures do disclose them, so the operator has the true inventory — but the ratification
  decision AC-11 hands back should be made against that inventory, not against this sentence.
  Scored as a warning rather than a blocker because the disposition itself is the one the
  ratification pre-authorized, the four named removals are all real, and how deep the cut should
  go is the operator's call, not a reviewer's.
- **A stale comment left by this round's own deletion.** `orchestrate-lean-selftest.sh:325-330`
  still says the tool reads "two harness-owned paths" under the private HOME, naming
  `~/.claude/jobs/<id>/state.json` "for D-8's idle read" and adding "no job record (D-8 degrades
  to its ceiling)". The narrowing deleted `job_idle` and that read; only
  `~/.claude/projects/*/<sid>.jsonl` remains, and the private HOME is still needed for it. The
  mechanism is right, the comment describes a mechanism that is gone.
- **Round 1's carried warnings that this round did not touch** stand as they were, minus one that
  the routing change closed: AC-6's INT/TERM trap still has no case; the six forwarded telemetry
  variables are still asserted for none of them; the malformed-id disjunct of the dispatch guard
  is still undriven. `terminal()`'s `spawn_cleanup` stop is now genuinely asserted — `(bg2)`
  reaches it through the collapsed terminal and checks the stops file, so deleting the stop from
  `spawn_cleanup` fails a case. `probe_spawn`'s unguarded listing validation is moot: the
  narrowing reverted it to `main`'s form byte-for-byte.

## Suggestions

- `poll_session` still sleeps before its first read, so a session that settles in two seconds
  costs a full `POLL_SECS`. Read first, sleep after.
- `OTEL_EXPORTER_OTLP_HEADERS` typically carries a credential and `--settings` puts it on the
  child's argv, readable via `ps`. A `0600` temp file passed by path keeps D-27's behavior
  without widening the exposure. Low severity on a single-operator machine; carried from round 1.
- If `spawn_close` is touched again, assert the appended block appears exactly ONCE. `(y2a)` and
  `(bg2b)` both check presence, so dropping the `SPAWN_CLOSED=1` line would duplicate the block
  silently. `review-toolkit:unit-test-mutation-reviewer`, confidence 70.

## Verification performed by this review

- `orchestrate-lean-selftest.sh` at the reviewed head, clean env
  (`env -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL -u RUN_ID`, stdin closed): **123 pass / 0 fail**,
  matching the PR body.
- The B-1 control/mutant pair and the `(bg7probe)` guard, both in an isolated detached worktree
  at `363585a2`, never in the reviewed one.
- The `(j1a)` stops-file probe for the first warning.
- The narrowing's four removals, each checked directly: no `job_idle` and no
  `~/.claude/jobs/<id>/state.json` read in the tool; no `build-blocked` / `review-blocked` slug
  anywhere outside the plan prose; `probe_spawn` byte-identical to `origin/main`'s; the
  `lean-orchestrate-stuck-idle-read` catalog row gone.
- AC-11's figures reproduced at the reviewed head: raw `+763 / −178`, net **+585**; executable
  lines only, comments and blanks excluded both sides, `+389 / −92`. Both match the PR body and
  the spec exactly. `orchestrate-lean.sh` alone is `+331 / −83`, matching the 83 the spec claims.
- All 39 `mutation-catalog.tsv` rows anchored on `orchestrate-lean.sh` or `lean-gate.sh` still
  bite after the edit — each row's `sed -E` expression changes the file.
- `bash scripts/check-gate-buckets.sh` green: **317 sites, 165 rows**, matching the PR body.
  `bash tools/prose-blockers.sh check` green, 29 stop-tier constructs, zero undispositioned.
  `bash scripts/check-lockstep-pairs.sh` green, 30 anchors. `shellcheck -e SC1091,SC2015,SC2181`
  clean over both changed scripts.
- CI at this head, cited rather than re-run: `lint-and-selftests` **pass** (4m55s),
  `selftests (macos, bash 3.2)` **pass** (7m34s), `mutation-sweep-pr` **pass**. `pr-gates` is red,
  which is the lean chain's pre-approve state and not a finding.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Unchanged by the delta and re-verified at this head: the `--bg` dispatch, the id read out of the `backgrounded` line, the fail-close on an unreadable one, `--disallowedTools AskUserQuestion`, `--name lean-<issue>-<role>-r<round>` and the `--settings` env block are all present. Zero occurrences of `SPAWN_BG_WAIT_CEILING_MS` or `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`; the only `PIPESTATUS` left is the comment saying there is none to read; all eight `env -u RUN_ID` sites are gate invocations, none on the spawn. |
| AC-2 | satisfied | Amended this round and the code matches: `failed`, `stopped` and `blocked` share one arm returning to `spawn`, which reaches `terminal "$lower-session-failed" 1` naming the state. `(bg2)` asserts the slug, `ended blocked`, `waiting on an answer` and the stop landing in the stops file; `(bg2a)` drives REVIEW and gets `review-session-failed`, proving the slug is composed rather than literal. `(bg1a)` still asserts `--all` on every listing call. |
| AC-3 | satisfied | Narrowed as the spec now states. `job_idle` and the `~/.claude/jobs/<id>/state.json` read are gone from the file; the `working` arm is the wall-clock ceiling alone, stopping the session, ledgering `state=stuck` and proceeding as for `done`. `(bg4)` fires it at a pinned ceiling of zero and asserts the stop plus `state=stuck` in the launch ledger; `(bg4a)` is the non-vacuity twin — four `working` ticks under the shipped ceiling, no stop. |
| AC-4 | satisfied | Untouched by the delta. Four not-a-state shapes plus the unmodelled-state arm all reach `terminal spawn-unreadable 1` after three polls with `gate_count` zero, and `(bg5a)` proves the counter resets only inside the recognized arms. |
| AC-5 | satisfied | Untouched. `staleness_rc` re-runs each tick; rc=7 stops the child then takes `terminal staleness-expired 7` with the partial-operation wording. `(bg7)` asserts rc=7, the slug, one spawn, the stop mid-flight and `index.lock` in the message. |
| AC-6 | satisfied | Untouched. `trap 'spawn_cleanup; exit 130' INT` and `trap 'spawn_cleanup; exit 143' TERM` are installed above `terminal`, and `spawn_cleanup` now closes the transcript before stopping the id. Scored on the code; that no case exercises the trap is carried as a warning, as in round 1. |
| AC-7 | satisfied | Round 1's B-2 is fixed and the fix is behaviorally right. `spawn_close` is idempotent and sits in `spawn_cleanup`, the funnel every run-ending exit goes through, so `spawn-unreadable` and mid-flight `staleness-expired` no longer leave the file their own remedies name at 0 bytes. Measured: with the mechanism present `(bg7)`'s transcript carries the session's final message; with it removed the same file is 0 bytes. `blocked` additionally became a return rather than an exit, so it closes on the ordinary path. The absence of a case for any of this is scored against AC-10, which enumerates it, not here. |
| AC-8 | satisfied | Untouched. The `spawn` row carries `id=<short id>` and `spawn-end` carries `state=`; `(bg4)` reads `state=stuck` straight out of the ledger file. |
| AC-9 | satisfied | Amended and matched: the `blocked` register row is deleted and `blocked` routes through the collapsed `terminal "$lower-session-failed" 1` row; `spawn-unreadable` keeps its own; `staleness-expired` still anchors. `bash scripts/check-gate-buckets.sh` green at this head, 317 sites over 5 files, 165 rows — the figures the PR body states. |
| AC-10 | unsatisfied | Every other case AC-10 enumerates is present and passing, and the catalog and liveness obligations are met — all 39 catalog anchors on the touched files still bite, and the deleted row's anchor addressed deleted code. But the enumerated case "the transcript surviving a terminal reached from inside the poll" is not among them: `(bg2b)` drives `blocked`, which this same round converted into a return rather than a terminal-from-inside-the-poll, so `spawn()`'s own close covers it. Measured — deleting `spawn_close` from `spawn_cleanup` and leaving `spawn()`'s call intact leaves the suite 123 pass / 0 fail. See B-1 for the six-line guard and its verified control/mutant pair. |
| AC-11 | satisfied | The disposition is taken rather than argued, which is what round 1 asked for. All four named removals verified individually at this head. The negative is recorded rather than the bar claimed, and both figures reproduce exactly with the commands given: raw `+763 / −178`, net **+585**; executable-only `+389 / −92`. The ratifiability question is handed to the operator explicitly, which is where round 1 said it belonged. The "Kept" inventory's under-description is carried as a warning, not against this criterion — the operator has the true inventory from the PR body's feature bullets and the raw figures. |
| AC-12 | satisfied | Untouched by the delta and re-verified: zero `claude -p` spawn-primitive claims left in `orchestrate-lean.sh`, and `bash tools/prose-blockers.sh check` is green at this head with 29 stop-tier constructs and zero undispositioned. The one prose defect this round introduced is in the selftest's private-HOME comment, which is outside D-17's list; carried as a warning. |

## Panel

`review-toolkit:scope-completeness-reviewer` (approve, zero findings — it fetched #805 and the
ratification comment itself and confirms every scope item is in-diff, suppressing the AC-3
job-record concern at confidence 70 on the ground that the same comment pre-authorizes the
narrowing and the branch records the negative), `review-toolkit:unit-test-mutation-reviewer`
(request-changes, 1 major at confidence 82 and 2 minors — the major is carried as this record's
first warning, both minors as suggestions or as a moot item), `review-toolkit:pipeline-reviewer`
(approve, zero findings; its one suppressed note, that the dispatch-failure path reaches
`spawn_close` with an empty `SPAWN_SID`, is correct and not a defect — `transcript_close`'s no-id
branch handles it and that terminal's remedy does not reference the transcript). No reviewer went
dark and none needed a re-dispatch. `review-toolkit:security-reviewer` was not selected: the delta
carries no auth, tenancy, session-handling, upload or query-construction surface and the repo has
no `.claude/second-shift/review-context/security-reviewer.md`, so the lead pass owned the security
dimension — its one finding is the argv-credential suggestion above. The performance, complexity,
maintainability and test-coverage dimensions are lead-pass dimensions by design; B-1 and the first
three warnings are lead-pass findings. The a11y and design-fidelity dimensions were not routed: no
changed path is in a web-component surface.

Design fidelity: the spec declares no `## Design` section, so the dimension is not applicable and
no fidelity reviewer was routed.
