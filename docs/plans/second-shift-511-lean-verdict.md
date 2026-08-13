# lean review verdict — #511

verdict=needs-work
run_id: review-511-1
session_id: 1b1ea189-ecb4-47eb-b02c-c3277303e2d8
rounds: 1
pr: #535
reviewed_head: 53333c856c74dc76920ef798d237fe25d7fe7d23
reviewed_patch_id: 0818dd2da8c9e62051980465569c4fa8d31a1cb6
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 read the whole branch diff (`322ef75..53333c8`, 6 files) — `bash G delta 511` reported a
FULL range with nothing verifiable to inherit. Panel: security, performance, maintainability,
complexity, test-coverage, scope-completeness (all six returned, none dark). Every finding below
is mine after probing; the panel returned zero findings above threshold.

The mechanism is the right shape and the write-up is unusually honest about how it got there. Two
blockers, both reproduced with a probe rather than argued.

## Blockers

### B1 — the JOIN arm hands back a previous evaluation's exit code without evaluating

`lean-gate.sh:2209-2218`. The stale-marker guard is on the launch arm only (`rm -f "$M3_RC" …` at
2223, reached after `m3_runner_live` has already decided to join). A join goes straight into
`m3_wait`, whose first act is `[ -f "$M3_RC" ]` — so if a marker is on disk, the call returns that
code immediately, having evaluated nothing.

Both files that make this reachable persist forever. `$M3_RC` is written by every *successful*
evaluation and cleared only at the next launch; `$M3_PID` is written at 2240 and **never removed** —
not at completion, not by `teardown`, not by the entry sweep (it is the only one of the three paths
with no `rm`). So the steady state after any green milestone 3 is `.pid=<dead pid>` + `.rc=0` sitting
in `.claude/pipeline-state/` indefinitely. This repo's own state dir holds
`511-lean-m3-458849663.pid` = **19013** right now, against a current pid of ~20995.

Probe, in an isolated worktree at the reviewed head, appended to the `(dj)` block so it reuses
`dj_tree`/`dj_gate`: run a real evaluation (leaves `.rc`), overwrite the marker with `99` (a code no
evaluation can produce, standing in for the previous run's code), plant a live pid, re-invoke.

    PROBE-A: first real evaluation rc-marker = 0
    PROBE-A rc=99 elapsed=0s record 5 -> 5
    PROBE-A out: [lean-gate] milestone-3: an evaluation is already running in this worktree
                 (pid 8566) — JOINING it rather than launching a second.

`rc=99` in `0s` with the progress record unmoved. Substitute the real `rc=0` for the 99 and this is a
green milestone 3 on a tree it never ran against — the exact harm the new
`lean-gate-m3-stale-marker` catalog row names, reached through the arm that row does not cover.
`(dj3)` guards the launch arm and passes; nothing guards this one.

The trigger is pid reuse, and the in-code note at 2091-2095 mis-states both its likelihood and its
consequence: "the window is a whole pid wraparound against a marker that is removed at every launch,
and the failure mode is one extra ceiling wait rather than a wrong verdict." The marker is *not*
removed on the path that reads it, so the failure mode is a wrong verdict, returned instantly. And
the window is not a wraparound in the practical sense — `kern.maxproc` is 6000 and pids recycle
through 99999 within a day of ordinary use here, while a reboot restarts allocation low and walks
straight back through a recorded 19013 within minutes.

Note the fix is not simply hoisting the `rm -f` above the liveness check: a genuinely live runner
that has just stamped its marker would lose its result. Binding the marker to the pid that produced
it, or clearing `$M3_PID` once a wait has consumed a marker, both close it without that.

The milder half of the same defect is already live on disk: the current state (`.pid` present,
`.rc` absent) makes the next `bash G 3 511` join pid 19013 if it is live and block for the full
3600s default before returning 7.

### B2 — `(dj10)` cannot fail on the bug AC-12 names it as guarding

AC-12: "`(dj10)` asserts the property both broken shapes violated — a milestone-3 lane child runs
its own detached milestone 3, evidenced by a `started`/`concluded` pair in the inner tree's own
record rather than by the lane's exit code, which the inline bug also produced."

The inner pair is no better a discriminator than the exit code it was chosen over. `append_started` /
`append_concluded` live inside `m3_run_detached` (2179-2186), so the pair is written whether that
function was reached through the fork at 2237 or called inline — and calling it inline *is* the
inline bug.

Probe: reintroduced the pre-final handshake verbatim in shape in an isolated worktree — an inline arm
at the top of `m3_launch_or_join` keyed on `LEAN_GATE_M3_RUNNER`, and `export LEAN_GATE_M3_RUNNER=1`
inside the spawned subshell so it reaches the runner's lane children exactly as the shipped bug did.
Instrumented the inline arm to prove it fired rather than no-opping:

    $ cat /tmp/rev511-inline-arm.txt
    INLINE-ARM-TAKEN cwd=<WORK>/dj-nest_inner issue=7
    $ grep '(dj10)' probeB2.log
      PASS: (dj10) a milestone-3 lane child runs its own detached milestone 3 — nothing is
            inherited from the outer runner
    suite rc=0, 0 FAILURES

The lane child took the inline arm — `cwd` is `dj-nest_inner`, so this is (dj10)'s own nested call,
the mechanism absent exactly as described in AC-12 — and the whole suite stayed green, `(dj10)`
included. It reads as coverage for the defect this ticket was re-cut around and cannot fail on it,
which is the failure mode `CLAUDE.md` calls out under "No mirror harnesses".

Cheap fix, and the case already has the material: `dj_base` reads the gate's `runner state:`
announcement, so asserting the inner tree got a `.pid` of its own — or that the inner call's own
output says `spawned detached` — is a discriminator only a fork satisfies.

## Warnings

- **`LEAN_GATE_WAIT_CEILING_SECS` is a new env var the gate reads and `SEAM_SCRUB` (2026) does not
  scrub**, so milestone 3's lane children inherit it — and in this repo those children *are*
  `lean-gate.sh`. This is the shape of dogfood finding 1, applied to the one seam the ticket
  shipped: an operator who exports a short ceiling to debug gets spurious `rc=7` from the nested
  suite's own milestone-3 calls. Not a blocker — `LEAN_GATE_OBSERVE` is unscrubbed on the same
  terms, and the register is a `verbatim` lockstep row against `verifyctl.sh` that cannot be
  widened unilaterally. Worth a header note at minimum.
- **`build-lean/SKILL.md` never mentions `rc=7`.** AC-5 only requires the gate header, and the
  warn text carries the remedy inline, so this is not an AC miss — but the block's rc vocabulary in
  SKILL.md still reads "the 4th red (`rc=4`) hard-stops", and 7 is the one code whose correct
  response is neither a fix nor a stop.
- **AC-1 still specifies `nohup … &`**, which AC-12 supersedes with the forked subshell. The two ACs
  are reconcilable in order, but AC-1 as written no longer describes the diff.

## Strengths

- The three-terminal-state wait (2122-2166) is the right correction to #496's silence class, and the
  one-grace-re-check at 2143-2147 is a real race, correctly reasoned, not defensive padding.
- The launch-arm vacuity guard and its `(dj3)` case are exactly right — a stale marker planted with
  `99` plus a second `started` row, non-vacuous in both directions.
- Every `(dj)` case gets its own fixture tree, and `dj_base` reads the paths out of the gate's own
  announcement instead of re-deriving `m3_paths`' key. The `$WORK` sentinel for the unannounced case
  is the correct answer to a suite that once wrote `./.pid` into the checkout.
- Refusing to re-baseline from an advisory local sweep (AC-11) was the right call, and CI settles it:
  `mutation-sweep-pr` passed with `applied=23 killed=20 survived=3` against exactly the three
  committed `lean-gate.sh` baseline rows, and all three new catalog rows killed.
- The write-up records both discarded runner shapes with measurements rather than quietly shipping
  the third.

## Verification run this round

- `bash plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` at the reviewed head, cold, in
  an isolated worktree with `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL`: **rc=0**.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean (0.11.0; CI pins 0.9.0,
  which is strictly less strict).
- Apply-probed all three new `tools/mutation-catalog.tsv` seds against the real file with BSD sed —
  each changes exactly one line, so no anchor drift and no `ALL-SURVIVED` harness break.
- CI at `53333c8`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr`
  pass. `pr-gates` fails only on the absent verdict record, which is this artifact.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 detached evaluation, caller blocks, log replayed | satisfied | `(dj1)`; the `nohup` wording is superseded by AC-12, see Warnings |
| AC-2 launch-or-JOIN, `kill -0` liveness, no `pgrep -f` | satisfied | `(dj4)`; no `pgrep` anywhere in the diff |
| AC-3 a JOIN records nothing | satisfied | `(dj4)` record unmoved; independently reconfirmed by PROBE-A (5 → 5 rows) |
| AC-4 three terminal states | satisfied | `(dj1)` marker, `(dj6)` death, `(dj5)` ceiling |
| AC-5 `rc=7`, in the `Exit:` taxonomy | satisfied | `(dj6)`, `(dj7)`, header 136-141 |
| AC-6 3600s default, seam validated before the spawn, breach spares the runner | satisfied | `M3_WAIT_CEILING_DEFAULT=3600`, `(dj8)`, `(dj5)` |
| AC-7 milestone 3 only; `3` and `all` share one key; observe stays inline | satisfied | `(x3d)`, `(dj9)`, the `run_milestone` dispatch |
| AC-8 the prose half in both blocks, build-lean under the 60-line cap | satisfied | both bullets present; SKILL.md is 47 lines, `(f)` |
| AC-9 the `Workflow` exposure is measured, not assumed | satisfied | prose says await; this review session's own `review-lead` fan-out under `-p` is a second datapoint for the same result |
| AC-10 the mechanism is selftested, the prose half deliberately not | satisfied | the `(dj)` block covers AC-1..AC-7 and each case is non-vacuous; the unguarded prose half is a stated decision consistent with the no-prose-guards rule |
| AC-11 three catalog rows, baseline deliberately unedited | satisfied | all three killed in CI; the three survivors are exactly the committed baseline rows |
| AC-12 forked subshell, `(dj10)` asserts what both broken shapes violated | **unsatisfied** | the production half is correct; the assertion half is B2 — `(dj10)` passes with the handshake bug reintroduced and firing |
