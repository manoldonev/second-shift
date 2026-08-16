# lean review verdict — #539

verdict=needs-work
run_id: review-539-1
session_id: 72d32f4f-f2cb-4086-a7a9-90910233429d
rounds: 1
pr: #547
reviewed_head: a1c938c7de56cc78d6680977ce0cc09a3db50a8c
reviewed_patch_id: d4298fb1cca1fb50fcfa118065e6d855e5b0c95a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full-branch range `dc2db95..a1c938c` (no prior record to inherit — `delta` printed FULL).

## Verdict

**needs-work** — one blocker, outside the AC set: the `selftests (macos, bash 3.2)` CI lane is red on `(dj14b)`, a case this PR adds. All six ACs are satisfied and every new guard was proven live by a production-break probe.

## Blocker

**B-1 — `(dj14b)` fails on the macOS bash-3.2 CI lane; the case has no timing margin.**
`plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` (the `dj14b` block)

CI, head `a1c938c`, job `selftests (macos, bash 3.2)` — the only failing suite, the only failing case:

```
FAIL: (dj14b) expected the default runner NOT to lead its own group, got pid=96277 pgid=none
```

`pgid=none` means `ps -o pgid= -p <pid>` returned empty: the runner was already gone when the pgid was read. The case reads the pgid *after* `dj_wait_own_pgid`, and on the default path that helper can only ever return by timeout — the forked-subshell runner never becomes its own group leader, so the loop always runs its full 100 iterations of `ps` fork + `sleep 0.05` fork. Measured on an unloaded fast Mac: **6–7s**. The fixture lane is `sleep 8`. Subtract gate startup before the record appears and the margin is ~1s, on a 3-core CI runner sweeping four suites at a time.

This reproduces the shape rather than a bash-3.2 incompatibility: locally the whole suite is green at head (395 PASS, rc=0, homebrew bash), and the ubuntu `lint-and-selftests` lane is green. It is load-dependent, so a bare re-run may come back green and hide it.

The symmetric settle is what costs the margin, and it buys nothing on the arm that pays for it — the comment justifies it as making "it never became its own leader" a decided answer, but on the default path an early read is *already* decisive, because that runner is forked into its launcher's group and cannot leave it. Cheapest correct fix: capture `dj14b_pgid` immediately after `dj_runner_pid` returns, then let the settle run (or drop it) — the assertion is unchanged and the 8s window is no longer spent before the read.

## Warnings

**W-1 — the escape ships off by default, and nothing records when the lane turns it on.**
`lean-gate.sh:2747` (`m3_new_session`). `LEAN_GATE_M3_NEW_SESSION` appears only in `lean-gate.sh`, its two selftests and the spec; no skill, no scheduler, no config sets it, and `SEAM_SCRUB_ENV` strips it from milestone 3's lane children. Default-off is **not** a defect — AC-1 mandates it and the operator's OR-1 ruling ratified it in the same breath ("so a regression cannot silently become the default path"). But the issue's Impact — "milestone 3 is structurally unreachable in the lean lane here" — is not closed by merging this, and the same ruling says the documented-limitation fallback was rejected precisely because it would leave that true. Worth a recorded follow-up (flip the default, or have the lane export the seam) rather than leaving the gap to be rediscovered. Not scored against any AC.

**W-2 — this round carries no mutation kill evidence.**
`mutation-sweep-pr` is green with **0 verdicts**: both edited guards are deferred to nightly as slow suites (`lean-gate.sh` → `lean-gate-selftest.sh`, 147s; `orchestrate-lean.sh` → its pair). The PR body says so, and it is accurate — recorded here so the green is not read as a kill result. AC-6's two checks and the probe below are what stand in for it this round.

## Nits

- **N-1** — `m3_reap_runners`: `own` holds a **pgid** and is compared against a recorded **pid**. `own_pgid` would make the comparison self-evident without leaning on the comment block. (maintainability-reviewer, confidence 82)
- **N-2** — `(dj19)`'s `sleep 30 &` + `kill -9` leaks a job-control line into the suite's replayed output on the macOS lane (`lean-gate-selftest.sh: line 5857: 99295 Killed: 9  sleep 30`). Cosmetic, in a log that is read as one contiguous block.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — escape behind an env seam defaulting to today's shape, with its own lower ceiling | **satisfied** | `m3_new_session` / `m3_spawn_new_session` / `cmd_m3_run`; `M3_WAIT_CEILING_ESCAPE_DEFAULT=300` selected by the seam with `LEAN_GATE_WAIT_CEILING_SECS` outranking both; the default arm is the unchanged `( trap '' HUP; m3_run_detached ) & disown`. Handshake is a positional `m3-run` subcommand, not an inherited var, and the seam is added to `SEAM_SCRUB_ENV`. Guarded by (dj14)/(dj14b)/(dj15)/(dj16)/(dj17)/(dj18). |
| AC-2 — `cmd_teardown` reaps the recorded runner before `worktree_destroy` | **satisfied** | `m3_reap_runners` called before the no-worktree early return; located by the issue-keyed glob, pgid-then-pid, own-group suicide ruled out, record cleared either way. (if5b) re-derived to reap the recorded runner explicitly. |
| AC-3 — a live recorded runner with no marker counts as a death to recover from | **satisfied** | `infra_token`'s `n="$unclosed"`; token space moved to `m3infra-v2:`; `live` kept as the stderr diagnostic, and (ir4)–(ir8) re-derived onto that diagnostic so they can still fail apart. `orchestrate-lean.sh` + its selftest follow the prefix. |
| AC-4 — the falsified prose is corrected wherever the gate asserts it | **satisfied** | The header's "There is NO seam and no flag…" register is replaced by the seam entry; "the evaluation is a different process and keeps going" is now scoped to within-one-turn with the turn-boundary measurement stated; `m3_wait`'s "Re-invoking rejoins it WHILE IT RUNS" names the seam. The re-exec cost note and the `setsid`-is-unavailable note are both corrected (command vs syscall). No residual assertion of the falsified premise. |
| AC-5 — a liveness scenario fails when the runner does not survive a simulated turn end | **satisfied** | `(lean-turnend)` + `(lean-turnend-nv)` in `scenario-liveness-selftest.sh`, reusing (if5)'s `set -m` / group-kill idiom, asserting alive **and** that the next call JOINs; the paired leg requires `dead + relaunch` with the seam off. Both green locally at head. |
| AC-6 — the mutation obligations are settled in this diff, either way | **satisfied** | Re-run independently, not taken from the PR body. (i) All five `lean-gate-m3-*` catalog anchors match **exactly one** line on both `dc2db95` and `a1c938c`. (ii) With the committed operator patterns: `lean-gate.sh` `default::1`/`default::2` are the same two Seams-block prose lines on both revisions (181/182 → 193/194) and `cmp-eq::1` the same comment line (180 → 192); `orchestrate-lean.sh` `default::1` is unmoved at 148. Line numbers moved, ordinals did not — `mutation-baseline.tsv` needs no re-keying, as the body states. |

## Guard liveness — production-break probe

Run in an isolated worktree at `a1c938c` (never the reviewed checkout), three production behaviors reverted at their call sites in one pass, scored by case id:

| Probe | Cases that red |
| --- | --- |
| `m3_new_session() { false; }` | `(dj14)`, `(dj15)`, `(dj16)`, `(lean-turnend)` — and `(dj14b)`/`(lean-turnend-nv)` correctly stayed green |
| `m3_reap_runners` call removed from `cmd_teardown` | `(dj19)`, `(dj20)` |
| `n=$((unclosed - live))` restored | `(ir4)` |

6 failures, every one attributable; no new assertion is decorative. `(dj17)`/`(dj18)` were not independently probed — they are parse-time refusals whose message is emitted by the block under test and nowhere else.

Baseline at head, same worktree: `lean-gate-selftest.sh` 395 PASS rc=0, `scenario-liveness-selftest.sh` rc=0.

## Coverage

`test-coverage-reviewer` went **dark** (died-after-retry, turn-budget) — its domain went unreviewed by the panel. Covered directly instead: both affected suites run at head, and the production-break probe above. Security, performance, complexity, pipeline, maintainability and scope-completeness all returned; scope-completeness scored all four extracted scope items in-diff (PASS), so the Scope Completeness Gate does not fire.

`a11y` + design-fidelity were not routed: no changed path matches `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`). Fidelity is `not-applicable` — the spec arms no `## Design` section and the repo configures no design provider.

## CI at the reviewed head

| Check | Result |
| --- | --- |
| `lint-and-selftests` | success |
| `mutation-sweep-pr` | success — **0 verdicts** (both edited guards deferred to nightly), see W-2 |
| `selftests (macos, bash 3.2)` | **failure** — B-1 |
| `pr-gates` | failure — the missing verdict record only, which this round produces. Frozen-files, changelog-trailer and pipeline-chain arms all green. |
