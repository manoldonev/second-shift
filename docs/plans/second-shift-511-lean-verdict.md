# lean review verdict — #511

verdict=needs-work
run_id: review-511-2
session_id: aca69924-f024-48a9-8611-2cf86546f540
rounds: 2
pr: #535
reviewed_head: a3f7f21a808bdb97e15b63992f31676ee5cccceb
reviewed_patch_id: c63e4ac1f271e19652a0da5c53cc60de32c6b9b8
inherited_patch_id: 0818dd2da8c9e62051980465569c4fa8d31a1cb6
inherited_from_verdict: 7849f6640cf587a6549aba7af1028099b087a29e
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2 read the whole branch diff (`add4dec..HEAD`, 7 files) — `bash G delta 511` reported a FULL
range with nothing verifiable to inherit, because round 1's `reviewed_head` (`53333c8`) is no longer
an ancestor: the branch was rebased onto the new base after that round. Panel: security,
performance, maintainability, complexity, test-coverage, scope-completeness — all six returned, none
dark, zero findings above threshold. The finding below is mine, reproduced with a probe.

**Round 1's two blockers are both closed, and both closures were verified by re-running round 1's own
probes rather than by reading the diff.** A third defect of the same class remains, on the one arm
AC-13 deliberately exempts.

## Blocker

### B3 — a wait still returns a code it did not earn, on the arm that keeps the pid record

`lean-gate.sh:2371-2377` (the ceiling arm) is the only `m3_wait` exit that leaves `$M3_PID` on disk,
and it is deliberate: AC-13 says "that runner is alive and a re-invocation must be able to rejoin
it." That premise stops being true the moment the runner finishes — and when it does, the retained
pid record and the marker the runner then stamps **carry the same token, because they are from the
same launch**. The token binding cannot discriminate them, and the join arm consumes the marker in
0s having evaluated nothing.

Probed in an isolated worktree at the reviewed head, appended to the `(dj)` block so it reuses
`dj_tree`/`dj_gate`. Stage (a) fabricates nothing — a fixture whose lint lane is `sleep 5` under a
1s ceiling reaches the real ceiling arm, and the runner then stamps on its own:

    PROBE-C stage-a rc=7 (expect 7 = ceiling)
    PROBE-C residue after 5s: pid=[59344 59005-1-7938] rc=[59005-1-7938 0]
    PROBE-C the retained pid record and the stale marker CARRY THE SAME TOKEN (59005-1-7938)

Stage (b) substitutes only the pid *number* for a live one — standing in for the OS handing that
number to another process, which is the trigger AC-13 itself names — and leaves the token exactly as
the launch wrote it:

    PROBE-C stage-b rc=0 elapsed=0s record 4 -> 4 (ceiling was 20s)
    PROBE-C stage-b out: [lean-gate] milestone-3: an evaluation is already running in this worktree
                         (pid 71267) — JOINING it rather than launching a second.

`rc=0` in `0s` with the progress record unmoved: a **green milestone 3 on a tree it never
evaluated**, which is verbatim the harm B1 named and the `lean-gate-m3-stale-marker` catalog row
describes.

**The ceiling arm is not the only way in, and this is what sets the severity.** The two `rm -f
"$M3_PID"` sites are both inside `m3_wait` (2349, 2363); there is no trap, and neither `teardown`
nor `cmd_entry_sweep` touches the runner state. So a waiter killed by the harness's reap — the
routine case this ticket exists for, and one this PR's own body records happening in production —
leaves the identical residue: `.pid` retained, `.rc` stamped later by the surviving runner with that
same token. Nothing clears it until the next milestone-3 *launch* on that key, so an abandoned or
hard-stopped run leaves it on disk indefinitely, which is precisely the interval over which pid
reuse becomes likely.

The in-code note at 2267-2275 states the opposite as settled: "a waiter attached to a recycled pid
waits for a marker stamped by THAT launch, which never comes, so the cost is a ceiling wait and
`rc=7`." The marker stamped by THAT launch is exactly what is on disk. This is the same shape round
1 flagged at 2091-2095 — a reachability argument in a comment that is wrong in the direction that
makes the defect invisible — rewritten in a new place rather than re-derived.

Two fixes that close it without giving up the rejoin the carve-out exists for, since neither
touches the window where the runner is genuinely alive: have `m3_run_detached` `rm -f "$M3_PID"`
after its stamp (the runner is the one process that knows the evaluation is over), or have the join
arm refuse to join when a marker carrying the joined runner's token is *already* on disk and
relaunch instead.

## Verified this round — round 1's blockers

Both closures were probed, not read. Each mutation isolates to exactly one case against a green
baseline (`base` suite `rc=0`, 0 failures):

- **B2 closed.** Round 1's probe reintroduced verbatim: an inline arm on `LEAN_GATE_M3_RUNNER` at the
  top of `m3_launch_or_join`, plus `export LEAN_GATE_M3_RUNNER=1` inside the spawned subshell, with
  the inline arm instrumented so its firing is evidence rather than inference. It fired in the case's
  own nested tree (`INLINE-ARM-TAKEN cwd=<WORK>/dj-nest_inner issue=7`) and `(dj10)` was the **sole**
  failure — where round 1's identical probe left the whole suite green. `spawned detached`, read off
  the inner call's own captured stdout, is a discriminator only the fork satisfies.
- **B1's named arm closed.** Stripping the token comparison in `m3_marker_mine` reds `(dj11)` alone,
  and it reds with `got rc=99` — the planted stale code returned through the join arm, exactly the
  failure the case claims to notice.
- **AC-13's second half guarded.** Dropping `rm -f "$M3_PID"` from the marker-consumption path reds
  `(dj12)` alone.

## Warnings

- **A completed evaluation whose waiter never consumed it is discarded, and the message says
  otherwise.** After a ceiling breach or a reap, if the runner finishes before the next invocation,
  that invocation finds a dead pid, takes the launch arm and re-runs the whole sweep — the stamped
  answer is thrown away. The ceiling arm's own remedy text says "Re-invoking rejoins it", which holds
  only while the runner is alive. Cost and prose, not correctness; the fix for B3 does not change it.
- **`(dj3)`'s pass message no longer describes what the case can fail on.** It still reads "a stale
  rc marker is cleared at launch", but with the token match in place removing the launch `rm -f
  "$M3_RC"` alone leaves it green, and removing the token check alone leaves it green too (the
  launch clearing hides the planted marker) — only removing both reds it. The block comment above it
  concedes this and the catalog row was correctly re-anchored off that clearing; the message string
  did not follow.
- **An unparseable marker returns `rc=7` silently.** `m3_marker_mine:2319` maps a non-numeric code to
  7 — the right fail-closed answer — but the marker arm prints no `warn`, so the operator gets a bare
  7 with none of the diagnosis the death and ceiling arms carry. Unreachable through the tmp+`mv`
  write, so it costs nothing today.
- Carried from round 1, not re-raised: `LEAN_GATE_WAIT_CEILING_SECS` is still outside `SEAM_SCRUB` and
  so is inherited by milestone-3 lane children, which in this repo are `lean-gate.sh`. The header now
  says so at 183-192, which is what round 1 asked for; the register is a `verbatim` lockstep row and
  is not widenable from this side.

## Strengths

- The token is the right mechanism, and both cases resting on it are non-vacuous in a way this repo
  has been burned on: `(dj11)` and `(dj12)` each isolate under their own mutation, and `(dj10)`'s
  re-anchoring onto `spawned detached` is exactly the discriminator round 1 named as available.
- The catalog work is honest. `lean-gate-m3-stale-marker` moved off a clearing that no longer
  enforces anything and onto the comparison that does, a fourth row pins the pid-lifetime half, and
  all four seds apply-probed against the real file with BSD sed change exactly one line each — the
  5-second check that forecloses the ALL-SURVIVED harness-break class.
- `rc=7`'s collision with the `staleness` arm the base gained mid-flight is recorded rather than left
  to be discovered. Verified rather than accepted: `orchestrate-lean.sh` invokes only `staleness`,
  `4` under `LEAN_GATE_OBSERVE=1`, and `progress`, so neither reader is ever handed the other's code.
- The commit message and the spec amendments describe what round 1 found without softening it, and
  AC-13 was added rather than an existing AC quietly reworded — the spec diff removes no obligation.

## Verification run this round

- `lean-gate-selftest.sh` at the reviewed head, cold, in an isolated worktree with `env -u
  CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL`: **rc=0**, all 12 `(dj)` cases pass.
- Three mutation probes, each in its own worktree, each isolating to one case: `(dj10)`, `(dj11)`,
  `(dj12)`. Details above.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean (0.11.0 locally; CI
  installs from apt and its `lint-and-selftests` job is green on this head).
- CI at `a3f7f21`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr`
  pass. `pr-gates` fails on one arm only — `verdict=needs-work`, which is round 1's record, and the
  freshness arms are not evaluated behind it.
- The mutation table was read rather than the body's claim: `applied=26 killed=23 survived=3`, and
  the three survivors are exactly the three committed `lean-gate.sh` baseline rows
  (`cmp-eq::1`, `default::1`, `default::2`). 15 catalog rows are named killed in the log and
  `lean-gate-m3-stale-marker` is not among them — the arithmetic closes only if it is the 16th
  applied and the 23rd kill, which is consistent with its kill coming from `(dj11)`, the suite's last
  case, and with the P2 probe above. AC-11's refusal to re-baseline from an advisory local sweep
  stands.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 detached evaluation, caller blocks, log replayed | satisfied | `(dj1)`; the superseded `nohup` wording is corrected this round |
| AC-2 launch-or-JOIN, `kill -0` liveness, no `pgrep -f` | satisfied | `(dj4)`; the only `pgrep` in either file is the comment forbidding it |
| AC-3 a JOIN records nothing | satisfied | `(dj4)`, `(dj11)`; PROBE-C independently shows 4 → 4 |
| AC-4 three terminal states | satisfied | `(dj1)` marker, `(dj6)` death, `(dj5)` ceiling |
| AC-5 `rc=7`, in the `Exit:` taxonomy, both readings recorded | satisfied | `(dj6)`, `(dj7)`, header 144-156; the scheduler never invokes `3`, so the readings never meet at a call site |
| AC-6 3600s default, seam validated before the spawn, breach spares the runner | satisfied | `M3_WAIT_CEILING_DEFAULT=3600`, `(dj8)`, `(dj5)` |
| AC-7 milestone 3 only; `3` and `all` share one key; observe stays inline | satisfied | `(x3d)`, `(dj9)`, the `run_milestone` dispatch |
| AC-8 the prose half in both blocks, build-lean under the 60-line cap | satisfied | both bullets present; SKILL.md is 47 lines, `(f)`; `rc=7` now named there too |
| AC-9 the `Workflow` exposure is measured, not assumed | satisfied | this review session is a third datapoint — a non-interactive session dispatched a six-agent `Workflow` and was re-entered with its result |
| AC-10 the mechanism is selftested, the prose half deliberately not | satisfied | every `(dj)` case this round probed isolates; the unguarded prose half remains a stated decision |
| AC-11 four catalog rows, baseline deliberately unedited | satisfied | CI `applied=26 killed=23 survived=3`, survivors exactly the committed baseline rows; all four seds apply-probed to one line |
| AC-12 forked subshell, `(dj10)` asserts what both broken shapes violated | satisfied | the handshake bug reintroduced and instrumented as firing now reds `(dj10)` alone |
| AC-13 a wait returns only its own evaluation's code; the pid does not outlive a consumed evaluation | **unsatisfied** | second half satisfied — `(dj12)`, and dropping its `rm` reds that case alone. First half falsified by PROBE-C on the ceiling/reap arm: same-launch pid record and marker share a token, so a recycled pid returns `rc=0` in 0s having evaluated nothing (B3) |
