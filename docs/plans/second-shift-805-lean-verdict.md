# lean review verdict — #805

verdict=approve
run_id: review-805-3
session_id: dedc1d6f-deef-41d3-876e-3f3c269338a8
rounds: 3
pr: #810
reviewed_head: 9a93630f6d2673373a1d5874432f71ea569cd490
reviewed_patch_id: a5f2c10ef897f410f30ebee625e99521dd6d4ec0
inherited_patch_id: a761670383a881a60b2ae1c61036c5b5710e16aa
inherited_from_verdict: 63843b51da6b09ad8a5c0146ee139f0e9d61f5d4
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer,review-toolkit:pipeline-reviewer
model: opus
capabilities: pr-marker

Round 3, delta `63843b51..HEAD` (the single fix commit `9a93630f`, two files), inheriting the
coverage of patch `a761670383a8` from round 2's record. Read wider than the range where the delta
was misleading: the whole branch against `origin/main` for AC-11's accounting and for the panel's
scope read, and `origin/main` itself for the shape of every mechanism the narrowing removed.

**Round 2's blocker is fixed, and this time the fix is guarded by a case that can fail.** `(bg7a)`
drives mid-flight `staleness-expired` — the arm that genuinely exits from inside the poll loop and
has a session id by then — and asserts the slug and exit code alongside the transcript, so a run
that settled normally cannot pass it while proving the opposite. The three closes now have
disjoint killers, measured as control/mutant pairs in a throwaway worktree at this head:

| Mutant | Verdict | Killed by |
| --- | --- | --- |
| control (unmutated) | 124 pass / 0 fail | — |
| `spawn_close` deleted from `spawn_cleanup` | KILLED, 1 failure | `(bg7a)` — transcript 0 bytes |
| `spawn_close` deleted from `spawn()` | KILLED, 2 failures | `(y2a)`, `(z1)` |
| the `SPAWN_CLOSED` idempotency guard dropped | KILLED, 1 failure | `(bg2b)` — "got 2" close blocks |
| the `failed`/`stopped` handle clear removed | KILLED, 1 failure | `(j1a)` — `stops=[stop sess1]` |

Every row reproduces the PR body's own table exactly. Round 2's two remaining warnings are also
closed: `failed` and `stopped` clear the handle, and the private-HOME comment no longer names the
job-record read the narrowing deleted.

No blockers. Two warnings and one measured divergence, below.

## Warnings

**W-1 — a four-line comment this branch ADDS above `probe_spawn` asserts a preflight listing
check that exists nowhere on the branch.**

`orchestrate-lean.sh:652-655` reads: *"D-18. The listing is checked HERE, before a run costs
anything, because it is the only thing this loop has to tell a finished payload from an abandoned
one … A refusal at preflight is the cheap version of discovering it three unreadable polls into a
live session."* `probe_spawn`'s body (`:656-661`) runs `command -v "$SPAWN_BIN"` and
`[ -x "$SPAWN_BIN" ]` and nothing else — it never invokes `claude agents --json --all` and never
parses a listing.

This is newly introduced, not inherited: `origin/main` carries **no comment at all** above
`probe_spawn`, and the header is a `+` line on this branch. The function body is byte-identical to
`main`'s, which round 2 verified and this round re-verified — so the comment describes a mechanism
the narrowing removed and that the branch's own AC-11 lists among the removals ("`probe_spawn`'s
listing validation"). The branch knows how to record a removal correctly: the silence-ceiling arm
at `:908-914` states plainly that the private job record is **not** read and why. This site does
the opposite.

Scored a warning rather than a blocker on the round-2 precedent for the identical shape — a stale
comment describing deleted code was carried as a warning there and fixed this round — and because
it fails the second half of the Critical trigger: no concrete failure follows from it today. The
remedy is a deletion, not new machinery: drop the header, or reduce it to one sentence saying the
listing is deliberately NOT validated at preflight. `review-toolkit:scope-completeness-reviewer`
raised it at confidence 92; confirmed independently against `origin/main`.

**W-2 — the new `failed|stopped` handle clear is guarded for `stopped` only. Reverting the
`failed` half is invisible to the suite.**

`orchestrate-lean.sh:1013` adds `case "$SPAWN_STATE" in failed|stopped) SPAWN_ID="" ;; esac`, which
is the correct fix for round 2's warning — both states name a session the supervisor already ended.
`(j1a)` gained the regression assertions (`! grep -q 'still in flight'`, `[ ! -s "$SPAWN_LOG_DIR/stops" ]`)
but drives only `stopped`. `(j1)`, the pre-existing sibling that drives `failed`, asserts rc,
`spawn_count`, `gate_count`, the message substring and the slug — none of the re-stop hygiene.

Measured, control/mutant pairs in an isolated worktree at this head (control: 124 pass / 0 fail):

- `failed|stopped)` → `stopped)` — the `failed` half reverted: **124 pass / 0 fail, all green. SURVIVED.**
- `failed|stopped)` → `failed)` — the `stopped` half reverted: **KILLED**, exactly one failure,
  `(j1a)` reporting `stops=[stop sess1]`.

The asymmetry is exactly as `review-toolkit:unit-test-mutation-reviewer` predicted at confidence 85.

Not a blocker, on severity ordering: the behavior this protects is the one round 2 itself classified
as *"harmless — `stop_session` tolerates a failed stop — but the sentence is false"*. A future
regression risk on a cosmetic-severity operator message cannot outrank the present defect it
descends from, and the remedy is three copied assertions — net-additive guard machinery on a file
whose guard share is already the thing the repo is trying to bend down. Recorded here so the hole
is addressable rather than undiscovered: the killing assertion for the `failed` arm is `(j1)`
gaining `(j1a)`'s two checks.

## Suggestions

- Carried unchanged from rounds 1 and 2, untouched by this delta: AC-6's INT/TERM trap still has no
  case; the forwarded telemetry variables are asserted for none of the six; the malformed-id
  disjunct of the dispatch guard is undriven; `poll_session` still sleeps before its first read;
  `OTEL_EXPORTER_OTLP_HEADERS` reaches the child on argv via `--settings` and is readable via `ps`
  (low severity on a single-operator machine).
- `(bg2b)`'s count capture is `"$(grep -c … || echo 0)"`. When the file is absent `grep -c` prints
  `0` **and** exits non-zero, so the fallback appends a second line and `[ "$bg2b_n" -eq 1 ]` errors
  rather than comparing. It fails in the safe direction — the case reds — so it is a robustness nit,
  not a defect.

## Verification performed by this review

- `orchestrate-lean-selftest.sh` at the reviewed head, clean env
  (`env -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL -u RUN_ID`, stdin closed): **124 pass / 0 fail**,
  matching the PR body.
- `scenario-liveness-selftest.sh` at the reviewed head, same clean env: **84 pass / 0 fail**,
  matching the PR body.
- Six mutants across two probe runs, every one in a throwaway `git worktree add --detach 9a93630f`,
  never in the reviewed checkout; both trees restored and removed, and the reviewed worktree
  verified `git diff --quiet origin/claude/second-shift-805` before this record was written.
- AC-11's four named removals each re-checked at this head: no `job_idle` and no read of
  `~/.claude/jobs/<id>/state.json` (the one surviving mention is the `working` arm's comment
  stating the file is deliberately not read); no `build-blocked` / `review-blocked` slug outside
  `docs/plans/`; `probe_spawn`'s body byte-identical to `origin/main`'s; the
  `lean-orchestrate-stuck-idle-read` catalog row absent.
- All 39 `mutation-catalog.tsv` rows anchored on `orchestrate-lean.sh` or `lean-gate.sh` still bite
  — each row's `sed -E` expression changes the file. The delta edits no region any row anchors on,
  so nothing is owed a re-anchor.
- `bash scripts/check-gate-buckets.sh` green: **317 sites across 5 files, 165 rows**, matching the
  PR body. `bash scripts/check-lockstep-pairs.sh` green, 30 anchors. `bash tools/prose-blockers.sh check`
  green, 29 stop-tier constructs, zero undispositioned. `shellcheck -e SC1091,SC2015,SC2181` clean
  over both changed scripts.
- CI at this head, cited rather than re-run (run 34072394283, `headSha` 9a93630f, identical to the
  reviewed head): `lint-and-selftests` **pass** (4m57s), `selftests (macos, bash 3.2)` **pass**
  (5m20s), `mutation-sweep-pr` **pass** (20s). `pr-gates` is red, which is the lean chain's
  pre-approve state and not a finding.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Untouched by the delta and re-verified at this head: the `--bg` dispatch, the id read out of the `backgrounded` line, the fail-close on a dispatch yielding no readable id, `--disallowedTools AskUserQuestion`, `--name lean-<issue>-<role>-r<round>` and the `--settings` env block are all present in `spawn()` at `:966-983`. Round 2 verified the deletions (no `SPAWN_BG_WAIT_CEILING_MS`, no `PIPESTATUS` read, no `env -u RUN_ID` on the spawn) and the delta restores none of them. |
| AC-2 | satisfied | The delta refines this arm and the criterion's postcondition is preserved. `failed`, `stopped` and `blocked` still share one `*)` arm reaching `terminal "$lower-session-failed" 1` with the state named. What changed is that only `blocked` — the one state still running — carries its handle into `spawn_cleanup` to be stopped; `failed` and `stopped` name sessions the supervisor already ended, so the AC's "stops the session" holds as a postcondition on all three while the redundant stop, and the false "still in flight" sentence it printed, are gone. Measured: `(j1a)` asserts the slug, `ended stopped`, the absence of `still in flight` and an empty stops file, and it kills the mutant that reverts the `stopped` half; `(bg2)` still asserts the stop landing for `blocked`. The unguarded `failed` half is W-2. |
| AC-3 | satisfied | Untouched by the delta. The `working` arm is the wall-clock ceiling alone at `:915-919` — stop, `state=stuck` in the launch ledger, proceed as for `done` — and the harness's private job record is not read; the only mention is the comment at `:908-914` stating that it deliberately is not. `(bg4)` fires the ceiling at zero and asserts the stop and the ledger row; `(bg4a)` is the non-vacuity twin. |
| AC-4 | satisfied | Untouched. Four not-a-state shapes plus the unmodelled-state arm reach `terminal spawn-unreadable 1` after three polls, and `(bg5a)` proves the counter resets only inside the recognized arms. |
| AC-5 | satisfied | Untouched, and now driven twice. `staleness_rc` re-runs each tick; rc=7 stops the child then takes `terminal staleness-expired 7` with the partial-operation wording. `(bg7)` asserts rc=7, the slug, one spawn, the mid-flight stop and `index.lock`; the delta's `(bg7a)` drives the same scenario for the transcript invariant and re-asserts rc=7 and the slug as its non-vacuity check. |
| AC-6 | satisfied | Untouched. `trap 'spawn_cleanup; exit 130' INT` and `trap 'spawn_cleanup; exit 143' TERM` are installed above `terminal`, and `spawn_cleanup` closes the transcript before stopping the id. Scored on the code; that no case exercises the trap is carried as a suggestion, as in rounds 1 and 2. |
| AC-7 | satisfied | The close mechanism is correct and, as of this delta, fully guarded. `spawn_close` is idempotent via `SPAWN_CLOSED` and sits in `spawn_cleanup`, the funnel every run-ending exit goes through, so `spawn-unreadable` and mid-flight `staleness-expired` no longer leave at 0 bytes the file their own remedies name. Measured this round: deleting it from `spawn_cleanup` reds `(bg7a)` with a 0-byte transcript; deleting it from `spawn()` reds `(y2a)` and `(z1)`; dropping the idempotency flag reds `(bg2b)` with two close blocks. Three disjoint killers, no mutant surviving. |
| AC-8 | satisfied | Untouched. The `spawn` row carries `id=<short id>` and `spawn-end` carries `state=`; `(bg4)` reads `state=stuck` out of the ledger file. |
| AC-9 | satisfied | Untouched by the delta and re-verified: `bash scripts/check-gate-buckets.sh` green at this head with **317 sites over 5 files and 165 rows**, the figures the PR body states. The collapsed `$lower-session-failed` row still anchors after the delta's edit to that same terminal's arm, `spawn-unreadable` keeps its own row, and `blocked` has none because it routes through the collapsed one. |
| AC-10 | satisfied | Round 2's blocker is closed. The enumerated case "the transcript surviving a terminal reached from inside the poll" now exists as `(bg7a)`, driving mid-flight `staleness-expired` — an arm that genuinely exits from within the loop — and it kills the exact mutant round 2 measured surviving: `spawn_close` deleted from `spawn_cleanup` alone reds `(bg7a)` and nothing else. `(bg2b)` is re-aimed at the property its own path has, asserting exactly one close block, and is the unique killer of the dropped `SPAWN_CLOSED` guard. Every other case AC-10 enumerates is present and passing at 124/0; `scenario-liveness-selftest.sh` composes against the transport at 84/0; all 39 catalog anchors on the touched files still bite and the delta re-anchors none. The `failed` arm's unguarded handle clear (W-2) is a property of the round-2 warning fix, not one of the cases AC-10 lists — both `failed` and `stopped` are driven, by `(j1)` and `(j1a)`. |
| AC-11 | divergent-inert | The disposition holds and all four named removals re-verified individually at this head. What diverges is the arithmetic: the AC states the branch "adds **389** and deletes **92**" executable lines and the PR body states raw `+805 / −178`, net `+627`. measured: at this head the same commands give executable `+406 / −92` and raw `+809 / −178`, net `+631` — the round-3 fix commit added 17 executable lines and the figures were not restated. Inert with respect to what this criterion protects: the sign, the conclusion ("no cut depth reaches the bar"), and the operator's ratification question are all unchanged, and the branch understates rather than flatters itself only in magnitude. The PR body gives the reproducing commands, which do reproduce — they reproduce the current numbers, not the quoted ones. follow-up: #805, whose `Ratified:` comment AC-11 explicitly defers to — the operator's ratification call should be made against `+406 / −92` executable and `+631` net, not the quoted figures. |
| AC-12 | satisfied | Untouched by the delta and re-verified: zero `claude -p` spawn-primitive claims left in `orchestrate-lean.sh`, and `bash tools/prose-blockers.sh check` green at this head with 29 stop-tier constructs and zero undispositioned. The delta's own prose change is a correction — the private-HOME comment no longer names the deleted job-record read, closing round 2's third warning. W-1 is a prose defect in the same file but outside this criterion's enumerated D-17 list: it describes D-18's removed listing validation, not `-p`'s turn semantics. |

## Panel

`review-toolkit:scope-completeness-reviewer` (approve-with-nits, one finding at confidence 92 —
W-1, confirmed independently against `origin/main` and adopted), `review-toolkit:unit-test-mutation-reviewer`
(approve-with-nits, one major at confidence 85 and one minor at 82 — the major is W-2 and its
predicted survivor was reproduced exactly; the minor independently traced `(bg7a)` and `(bg2b)` as
non-decorative and agrees with this record's measurement), `review-toolkit:pipeline-reviewer`
(approve, zero findings). All three returned usable results in the fan-out; no reviewer went dark
and no Step 4b re-dispatch was needed.

`review-toolkit:security-reviewer` was not selected: the delta carries no authentication, tenancy,
session-handling, upload or query-construction surface, and the repo has no
`.claude/second-shift/review-context/security-reviewer.md`, so the lead pass owned the security
dimension — its one finding is the argv-credential suggestion carried above. The performance,
complexity, maintainability and test-coverage dimensions are lead-pass dimensions by design; W-1's
confirmation and the round's mutation measurements are lead-pass work. `review-toolkit:a11y-reviewer`
and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset in this repo, so the shipped default
`apps/web/**/*.{tsx,jsx}`).

Design fidelity: the spec declares no `## Design` section, so the dimension is not applicable and
no fidelity reviewer was routed.
