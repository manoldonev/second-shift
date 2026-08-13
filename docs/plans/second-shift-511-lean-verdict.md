# lean review verdict — #511

verdict=approve
run_id: review-511-3
session_id: 86362dd9-60eb-40d5-a8a0-967c24b4b2df
rounds: 3
pr: #535
reviewed_head: d1c59254ed72f3181289dec2c90e9030d017251e
reviewed_patch_id: af0abbd579a73b001264db2f380aace01a547772
inherited_patch_id: c63e4ac1f271e19652a0da5c53cc60de32c6b9b8
inherited_from_verdict: 204e7ac7ecc0d63767d79941a54b35a35f95fe35
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 3 read `204e7ac..HEAD` (one commit, 4 files), inheriting the coverage of patch `c63e4ac1f271`
under round 2's record. Round 2's single blocker is **closed**, and the closure was verified by
mutating the fix back out rather than by reading the new assertion. No blockers this round.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness — all
six returned, **none dark**, zero findings above threshold; scope-completeness PASS against the
issue body's own items. Two suppressed, both correctly under the bar: `m3_joinable`'s TOCTOU at
confidence 40 (single-operator repo-local state dir, and the losing race relaunches — the
recoverable direction) and `(dj13)`'s fixture token literal at 30. `test-coverage-reviewer`'s first
attempt returned empty and the fan-out's own on-substrate retry landed it, so the domain closest to
this commit is covered rather than papered over. Scope-completeness noted for itself that the
round's delta range is not the PR base and re-classified against the full PR range — the right
call, and it still passed. The findings below are mine; the panel has returned zero for three
rounds running.

## Verified this round — round 2's blocker

**B3 closed.** `m3_joinable` (`lean-gate.sh:2349-2353`) refuses a join when a marker bearing the
record's own token is already on disk, and the call falls through to the launch arm, which clears
the marker and evaluates the caller's tree. The stamp is `m3_run_detached`'s last statement, so a
marker under the record's token is proof that launch is over — the predicate keys on the one fact
that separates the two states, where the token could not.

Certified by mutation, not by reading. Degrading `m3_joinable` back to bare liveness (the committed
`lean-gate-m3-samelaunch-join` sed, applied verbatim) reds **`(dj13)` alone** against a 13-case green
baseline, and it reds with the harm itself rather than a proxy:

    FAIL: (dj13) expected a relaunch to rc=0 with the planted pid still live,
          got rc=99 alive=1 started 1 -> 1: [lean-gate] milestone-3: an evaluation is
          already running in this worktree (pid 57807) — JOINING it rather than launching a second.

`rc=99` is the planted stale code returned through the join arm with the progress record unmoved —
verbatim the state PROBE-C produced last round.

**The re-anchor of `lean-gate-m3-no-join` was obligatory, and I checked rather than assumed it.**
Round 2's sed (`s#^  if m3_runner_live; then$#...#`) applied to this head changes **0 lines**;
`tools/mutation-sweep.sh:1567-1569` reds `catalog anchor drift` on exactly that, so CI would have
failed rather than silently passed. The re-anchored row applies one line and reds `(dj4)` — plus
`(dj5)`, `(dj6)`, `(dj11)`, since removing the join arm takes every case that means to join.

**No regression toward #500's livelock.** A refused join can only mean the marker exists, and
nothing writes that marker but the runner's final statement, so `m3_joinable` cannot refuse a runner
that is genuinely still evaluating. `(dj4)` holds the other direction and still kills.

## Warnings

- **The commit's own rejection argument applies to code it ships.** It rejects "have the runner
  delete its own pid record" partly because "an unconditional delete there can remove a LATER
  launch's record, whose waiter then reads the missing pidfile as a death and returns 7". Both
  `rm -f "$M3_PID"` sites in `m3_wait` (2380, 2394) are unconditional in the same sense — they
  delete whatever record is on disk, not necessarily the launch this wait was attached to. The
  interleaving is narrow (a second gate process must complete `rm` marker → spawn → write pid
  between one waiter's marker read and its `rm`, and the two arrivals this design serializes are
  "seconds to minutes apart"), and the consequence is the recoverable direction — an `rc=7` naming a
  runner that is actually alive, then a second sweep on the next call. **Not a blocker and not new:**
  those two lines are round 2's AC-13 second half, outside this round's delta, and this round scored
  them on `(dj12)` as before. It is the reasoning that is asymmetric, not the risk that is fresh. If
  it is ever closed, the discriminator this fix already established closes it in one line — delete
  only while the record still carries the token this wait was on.
- **AC-11 overstates the harness's blindness to a drifted anchor.** It says a row left on the old
  literal "would match nothing, apply nothing, and report SURVIVED for a mutant that was never
  introduced". The sweep reds loudly instead (`catalog anchor drift`, `mutation-sweep.sh:1567-1569`),
  which the 0-line result above confirms. Wrong in the safe direction — the obligation the AC draws
  from it is real either way — but it is a claim about a guard, in the file that is the definition of
  done.
- **Carried from round 2, deliberately not re-raised:** an unparseable marker still maps to `rc=7`
  with no `warn` (`m3_marker_mine:2320`), unreachable through the tmp+`mv` write;
  `LEAN_GATE_WAIT_CEILING_SECS` is still outside `SEAM_SCRUB`, documented at the header and not
  widenable from this side. Two of round 2's warnings are **closed** by this commit: the ceiling
  arm's remedy text now says a re-invocation rejoins the runner *while it runs*, and `(dj3)`'s pass
  message no longer names a mechanism it cannot fail on.

## Strengths

- The fix is placed where the decision is made rather than where the residue is written, and the
  alternative is rejected on a stated failure mode (`kill -9` in the window after the stamp) rather
  than on taste. Both halves are in the spec and in the code comment, not only in the commit.
- `(dj13)` is `(dj11)`'s state with one token in place of two, which is the smallest construction
  that isolates the blind spot — and it asserts the *live* pid (`alive=1`) so it cannot pass down the
  launch arm for the wrong reason, the trap this suite has been burned on before.
- Every catalog row for this guard was apply-probed against the real file with BSD sed and changes
  exactly one line each (all five, re-checked this round) — the check that forecloses the
  ALL-SURVIVED harness-break class.
- The mutation arithmetic closes exactly, and the one row with no log line is accounted for rather
  than assumed: 23 early-exit notes + 3 survivors = 26 against `applied=27`, so precisely one kill is
  silent — `lean-gate-m3-samelaunch-join`, whose killer `(dj13)` is the suite's last case, leaving no
  cases to truncate.

## Verification run this round

- `lean-gate-selftest.sh` at the reviewed head, cold, in an isolated worktree with `env -u
  CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u TMPDIR`: **rc=0**, 347 assertions, all 13
  `(dj)` cases plus `(x3d)`.
- Two mutation probes, each in its own worktree: `lean-gate-m3-samelaunch-join` → `(dj13)` alone;
  `lean-gate-m3-no-join` (re-anchored) → `(dj4)`, `(dj5)`, `(dj6)`, `(dj11)`. Both `bash -n` valid
  before running, so neither could no-op silently.
- All five `lean-gate-m3-*` catalog seds re-probed against the real file: one line each. Round 2's
  anchor against this head: zero lines.
- CI at `d1c5925`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr`
  pass at `applied=27 killed=24 survived=3` with survivors exactly the three committed
  `lean-gate.sh` baseline rows (`cmp-eq::1`, `default::1`, `default::2`) — no baseline-absent
  survivor, so AC-11's refusal to re-baseline from an advisory local sweep costs nothing.
  `pr-gates` fails on one arm only — `verdict=needs-work`, which is round 2's record, with the
  freshness arms not evaluated behind it.
- `scripts/check-frozen-files.sh` against the real merge base (`add4dec`): clean. The branch is 10
  ahead / **0 behind** `origin/main`, so CI's verdicts are on a current base.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 detached evaluation, caller blocks, log replayed | satisfied | `(dj1)` |
| AC-2 launch-or-JOIN, `kill -0` liveness, no `pgrep -f` | satisfied | `(dj4)`; the only `pgrep` in either file is the comment forbidding it |
| AC-3 a JOIN records nothing | satisfied | `(dj4)`, `(dj11)`; `(dj13)` asserts the converse — a *refused* join records one started row |
| AC-4 three terminal states | satisfied | `(dj1)` marker, `(dj6)` death, `(dj5)` ceiling |
| AC-5 `rc=7`, in the `Exit:` taxonomy, both readings recorded | satisfied | `(dj6)`, `(dj7)`; the scheduler invokes `staleness`, `4` and `progress` only, so the two readings never meet at a call site |
| AC-6 3600s default, seam validated before the spawn, breach spares the runner | satisfied | `M3_WAIT_CEILING_DEFAULT=3600`, `(dj8)`, `(dj5)` |
| AC-7 milestone 3 only; `3` and `all` share one key; observe stays inline | satisfied | `(x3d)`, `(dj9)` |
| AC-8 the prose half in both blocks, build-lean under the 60-line cap | satisfied | `build-lean/SKILL.md:40` (47 lines, `(f)`), `review-lean/SKILL.md:100-107` |
| AC-9 the `Workflow` exposure is measured, not assumed | satisfied | a fourth datapoint: this non-interactive session dispatched the six-agent fan-out and was re-entered with its result |
| AC-10 the mechanism is selftested, the prose half deliberately not | satisfied | 13 `(dj)` cases + `(x3d)`, green cold; the unguarded prose half remains a stated decision under `CLAUDE.md`'s no-prose-presence-guards rule |
| AC-11 five catalog rows, `no-join` re-anchored, baseline deliberately unedited | satisfied | five rows present, each one line; the re-anchor verified obligatory (old sed → 0 lines → `catalog anchor drift` red); `mutation-baseline.tsv` is not in the branch diff and CI reports no baseline-absent survivor. The AC's account of what a drifted anchor *does* is wrong — see Warnings — but the obligation it states is met |
| AC-12 forked subshell, `(dj10)` asserts what both broken shapes violated | satisfied | `(dj10)` on the inner call's own `spawned detached` |
| AC-13 a wait returns only its own evaluation's code; the pid does not outlive a consumed evaluation | satisfied | falsified last round on the ceiling/reap arm, now closed by AC-14 — every remaining exit is this launch's marker or `7`. Second half unchanged and still isolated by `(dj12)` |
| AC-14 a runner is joinable only while its evaluation is UNFINISHED | satisfied | `(dj13)`, which reds alone under the committed mutant with `rc=99` through the join arm |
