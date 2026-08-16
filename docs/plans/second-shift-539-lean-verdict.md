# lean review verdict — #539

verdict=approve
run_id: review-539-2
session_id: 98a59819-636d-4a88-981b-996c30acf810
rounds: 2
pr: #547
reviewed_head: 2a9f6f9524d370c2b792d0fc2bca01377ffc149b
reviewed_patch_id: 054af755abb8f1a2b2a3d97cab845173f8528d99
inherited_patch_id: d4298fb1cca1fb50fcfa118065e6d855e5b0c95a
inherited_from_verdict: 21b8d4c404e4fdc39f3360f4d6c671008aae72c9
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2, delta range `21b8d4c..HEAD` — one file, `lean-gate-selftest.sh`. Coverage of `dc2db95..a1c938c` inherited from round 1's record (patch `d4298fb1cca1`); its findings were read first, and each is scored below.

## Verdict

**approve** — no blockers. Round 1's B-1 is closed at the lane that raised it, and the fix is structural rather than a margin bump: the pgid read moved ahead of the settle, the settle is now bounded in wall-clock seconds instead of `ps` forks, and the fixture lane outruns it 8x.

## Round 1 findings, re-scored

| # | Round 1 | Now |
| --- | --- | --- |
| **B-1** | `(dj14b)` red on `selftests (macos, bash 3.2)` — `pgid=none`, the settle spending 6–7s of an 8s fixture window before the read | **closed** |
| W-1 | escape ships off by default; nothing turns it on | **still open** — carried forward, see below |
| W-2 | round carries no mutation kill evidence | **still true** — see below |
| N-1 | `m3_reap_runners`: `own` holds a pgid, compared against a pid | **not addressed** — outside this delta, still a nit |
| N-2 | `(dj19)`'s `Killed: 9  sleep 30` job-control line in a replayed log | **closed** |

**B-1.** The fix takes the diagnosis apart rather than widening the window alone. `dj14b_pgid` is now read as soon as `dj_runner_pid` returns, before the settle — sound on that arm specifically, since a forked subshell is in its launcher's group from birth with no pending syscall that could move it. `dj_wait_own_pgid` is bounded by `SECONDS` against `DJ_SETTLE_SECS=5` rather than 100 `ps` forks, so its cost no longer scales with the runner's load, and it distinguishes *vanished* (2) from *decided it never led* (1) so the case reds instead of banking a pass from a settle that never ran. `DJ_ESC_LANE_SECS` 8→40 with the waiter ceiling moved 30→120 clear of it.

`selftests (macos, bash 3.2)` is **success** at head — the exact lane and the exact case. Round 1 flagged that a bare re-run could come back green and hide a load-dependent failure, so that green is corroborated by the two probes below rather than taken alone.

**N-2.** `disown "$dj19_fake"`. Verified on the shell that raised it — stock `/bin/bash` 3.2.57 accepts a bare pid (not only a jobspec), and a negative control on that shell reproduces the exact line and shows `disown` suppressing it:

```
WITHOUT disown → /bin/bash: line 1:   233 Killed: 9   sleep 30
WITH    disown → (nothing)
```

The dropped `wait "$dj19_fake"` is correct — a disowned job is not waitable.

## Guard liveness — probes at head, isolated worktrees, scored by case id

| Probe | Mutation | Result |
| --- | --- | --- |
| **P1** | `m3_new_session() { return 0; }` — the *default* path starts escaping its session | **(dj14b)** red `pgid=18742 settle=0`, **(dj15)** red. 393 PASS + 2 FAIL |
| **P3** | `DJ_ESC_LANE_SECS` 40→1 — the fixture starved back below the settle | **(dj14b)** red `pgid=85745 settle=2`. 394 PASS + 1 FAIL |

P1 answers the question the reordering raises: with the early read moved ahead of the settle, is `(dj14b)` still a live negative control? It is, and both arms fire — the early read caught `pgid == pid` here, and `settle=0` caught it independently, which is what covers the ordering where the read wins the race against `setsid(2)` and only the settle can see the move.

P3 answers the fail-closed direction, which is round 1's B-1 shape reproduced deliberately: a runner that vanishes mid-settle scores `settle=2` and **reds**, where the old code's empty `ps` read fell through to the pass direction. `(dj14b)` cannot pass off a corpse.

Arithmetic: 395 cases at head, and both probes account for all 395. No case count drift — the delta changes mechanics, not the roster.

## Local verification

| Revision | rc | PASS | user+sys |
| --- | --- | --- | --- |
| `21b8d4c` (round 1's head) | 0 | 395 | 155s |
| `2a9f6f9` (head) | 0 | 395 | 126s |

CPU, not wall — a co-running probe inflates wall and would invent a regression. The commit's "at no suite wall-clock cost" claim holds and is in fact a small win: the settle's fixed 5s replaces 6–7s of load-priced `ps` forks, and the 40s lane never elapses because both cases kill the runner the moment their read is made.

`shellcheck -e SC1091,SC2015,SC2181` clean locally (0.11.0) and on CI's own version (`lint-and-selftests` green).

## AC scoring

Every AC scored against the whole spec; AC-2..AC-6 inherit round 1's evidence unchanged, since nothing outside `lean-gate-selftest.sh` moved this round.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — escape behind an env seam defaulting to today's shape, with its own lower ceiling | **satisfied** | Production unchanged since round 1 (`m3_new_session` / `m3_spawn_new_session` / `cmd_m3_run`, `M3_WAIT_CEILING_ESCAPE_DEFAULT=300`, argv handshake, `SEAM_SCRUB_ENV`). Its guard set is what this delta repairs: `(dj14)`/`(dj14b)`/`(dj15)`/`(dj16)`/`(dj17)`/`(dj18)` all green at head on both CI lanes, and `(dj14b)` re-proven live (P1) and fail-closed (P3). |
| AC-2 — `cmd_teardown` reaps the recorded runner before `worktree_destroy` | **satisfied** | Unchanged. `(dj19)`/`(dj20)` green; `(dj19)`'s only edit is the `disown`, which does not touch what it asserts — the reap is still read with `kill -0` on the recorded pid. |
| AC-3 — a live recorded runner with no marker counts as a death to recover from | **satisfied** | Unchanged since round 1: `infra_token`'s `n="$unclosed"`, `m3infra-v2:` token space, `(ir4)`–`(ir8)` on the read's own diagnostic. |
| AC-4 — the falsified prose is corrected wherever the gate asserts it | **satisfied** | Unchanged since round 1. |
| AC-5 — a liveness scenario fails when the runner does not survive a simulated turn end | **satisfied** | Unchanged. `(lean-turnend)` + `(lean-turnend-nv)` green in both CI selftest jobs at head. |
| AC-6 — the mutation obligations are settled in this diff, either way | **satisfied** | Re-checked for this delta, not inherited blind. All five `lean-gate-m3-*` catalog rows anchor `sed` patterns into `lean-gate.sh`; `mutation-baseline.tsv` has no row targeting `lean-gate-selftest.sh`. A delta that edits only a *killer* cannot move a target's ordinals, so round 1's answer stands unchanged. |

## Warnings carried forward

**W-1 — the escape ships off by default, and nothing records when the lane turns it on.** `LEAN_GATE_M3_NEW_SESSION` still appears only in `lean-gate.sh`, its two selftests and the spec; no skill, no scheduler, no config sets it, and `SEAM_SCRUB_ENV` strips it from milestone 3's lane children. Default-off is what AC-1 mandates and what OR-1 ratified, so this is not a defect in the diff — but the issue's Impact ("milestone 3 is structurally unreachable in the lean lane here") is not closed by merging this. Worth a recorded follow-up rather than leaving the gap to be rediscovered. Not scored against any AC.

**W-2 — this round again carries no mutation kill evidence.** `mutation-sweep-pr` green with 0 verdicts: `lean-gate.sh` is deferred to nightly as a slow suite. Accurate, and recorded so the green is not read as a kill result. P1/P3 above are what stand in for it.

## Nits

- **N-3** — `dj_wait_own_pgid` returns 2 on the *first* empty `ps` read, with no retry. Under fork pressure a transient `ps` failure is indistinguishable from a dead runner and reds the case. The direction is right (fail closed is exactly what round 1 asked for, and this is no longer a *timing* exposure — the margin is 8x), but one retry before concluding "vanished" would remove the last non-deterministic path through this helper.
- **N-4** — `SECONDS=0` in `dj_wait_own_pgid` is not `local`, so the helper clobbers the shell's global `SECONDS`. Inert today — nothing else in the suite reads it — and `local SECONDS` would keep it that way for the next case that wants a stopwatch.
- **N-5** — `(dj14)` fails through the same helper but reports only `pgid=`, so a vanished runner and one that never led a group are indistinguishable in its message, where `(dj14b)` now spells out `settle=`. The pair shares the helper; it could share the diagnostic.
- **N-1** (round 1, unaddressed, outside this delta) — `m3_reap_runners`: `own` holds a **pgid** and is compared against a recorded **pid**; `own_pgid` would make that self-evident.

## CI at the reviewed head

| Check | Result |
| --- | --- |
| `lint-and-selftests` | success |
| `selftests (macos, bash 3.2)` | **success** — B-1's lane and case |
| `mutation-sweep-pr` | success — 0 verdicts (slow-suite deferral), see W-2 |
| `pr-gates` | failure — `check-lean-chain.sh` naming the round-1 record: *"reads 'verdict=needs-work', not 'verdict=approve'"*. That is the record this round replaces; frozen-files and changelog-trailer arms are green. |

## Coverage

Round 1's panel covered the whole branch and its record is inherited here. This round's delta is 59 lines in one test file with no production change, so it was covered directly rather than by re-fanning the panel: the full suite run at both revisions, the two production/fixture probes above, a bash-3.2 negative control for the `disown`, and the mutation-obligation re-check. Fidelity is `not-applicable` — the spec arms no `## Design` section and the repo configures no design provider.
