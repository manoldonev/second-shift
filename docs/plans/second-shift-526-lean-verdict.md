# lean review verdict — #526

verdict=approve
run_id: review-526-2
session_id: ed61155c-e2cf-4056-b533-96aa6d2d8265
rounds: 2
pr: #536
reviewed_head: ad87b005069a961368f2b9e40c163a5e751a8e64
reviewed_patch_id: 16c8f03d1cceab239c0285f7bad37b8a39d186f7
inherited_patch_id: 4f5c0eb67676a88287aef8b566368bfb9b8af341
inherited_from_verdict: ba147e3a77bd96743ac708aea6bd2a19e8b671a8
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, full branch range (`add4dec..HEAD`). The rebase onto `origin/main` (#523, #534) left
nothing verifiable to inherit, so `delta` printed the whole branch diff and this round read it —
the same range round 1 read, not a narrowed one. Panel: security, performance, complexity,
unit-test-mutation, scope-completeness returned; **maintainability and test-coverage went dark**
(died after the fan-out's own retry, the emit-deadline stall). a11y and design-fidelity were not
routed — no changed path matches `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`); this diff is shell, markdown and TSV.

Round 1's blocker is closed, and closed the way the repo asks for: the fix is a guard, and the
guard has its own killer on each side. No new blockers. `approve`.

## Coverage gap

`test-coverage-reviewer` and `maintainability-reviewer` produced no output this round, so those two
domains were not reviewed by the panel. Named rather than papered over. For the test-coverage
dimension specifically — which is what this round is almost entirely about — the eight execution
probes below are stronger evidence than that reviewer would have produced, since each one applies a
mutant and reads which named case dies. Maintainability is genuinely unreviewed this round; round 1
had it live over the same range and it raised nothing.

## B-1 is closed — round 1's probe re-run verbatim, and each half of the join probed alone

Round 1's finding was that the two lines activating the feature (`lane_register` in `cmd_entry`,
`lane_deregister` in `cmd_teardown`) were guarded by nothing: replacing both with `:` left
`lean-gate-selftest.sh` at **320 PASS / 0 FAIL** while every lane silently reverted to
whole-machine sizing. Re-run verbatim against this head, that mutant now **reds**.

All eight runs below are in an isolated worktree at `ad87b00` — never the reviewed checkout —
each mutant `bash -n` clean and changing exactly the lines shown, scored by **case id** rather than
message text:

| # | Mutant | Result |
| --- | --- | --- |
| P0 | none — gate suite baseline | all green |
| P1 | **both** call sites → `:` (round 1's probe, verbatim) | rc=2 — `(jw1)`, `(jw2)` FAIL |
| P2 | `lane_register` only → `:` | rc=2 — `(jw1)`, `(jw2)` FAIL |
| P3 | `lane_deregister` only → `:` | rc=1 — `(jw3)` FAIL, alone |
| P4 | the catalog row's **own** sed under BSD `sed -E` | 1 line changed — rc=2, `(jw1)`, `(jw2)` FAIL |
| P5 | drop the walk's `''\|0\|1` stop | `(c2)` FAIL — `got '1', wanted 200` |
| P6 | `grep -qxF` → `grep -qF` | `(b3)` FAIL — `got '300', wanted 200` |
| P7 | none — registry suite baseline | all green |

**P1 and P3 together are the point.** Under the combined mutant `(jw3)` still **passes** — with
`register` gone there is no row for `teardown` to fail to remove, so the assertion is satisfied by
an empty registry. A reviewer who ran only round 1's probe and saw two reds would have concluded
both halves were guarded; only P3 shows that the teardown guard enforces anything. The build round
found this itself and probed each site alone, which is why the coverage is real rather than
apparent.

**The catalog row is not vacuous.** `lane-join-entry-dropped` applied through its own
`s#^  lane_register$#  :#` under BSD `sed -E` changes exactly one line (the anchor cannot match
`lane_register() {` at `:1271`), stays syntactically valid, and kills. It also ran in CI: 13 catalog
rows target `lean-gate.sh` and 12 printed an early-exit note, so 13 catalog + 10 generic = 23
applied and 12 + 1 + 7 = 20 killed. The 20th kill with no note is this row — consistent with a kill
that leaves no cases behind it, not with a row that was never applied.

**W-1 and W-2 close on the failure they were written for, not on a message.** `(c2)` under P5
resolves the lane onto **pid 1** — the never-dying row that would collapse every future lane count
to 1. `(b3)` under P6 resolves onto **300**, the ancestor past the real non-shell one. Both are the
described failure, observed.

## Warnings

None new. Round 1's five are all disposed of:

- **W-1, W-2** — fixed, and the `lane-registry.sh:76-81` comment now states what `-x` actually
  prevents (a short `comm` matching inside a longer shell name) instead of the `bashful` example
  that the flag does not address.
- **W-3** — fixed, and verified against CI rather than the body: `mutation-sweep-pr` on this head
  reports `lane-registry.sh 11/11/0`, `lean-gate.sh 23/20/3`, `run-selftests.sh 14/14/0`, matching
  the PR body's table exactly, with `survivor_ids` = `lean-gate.sh::cmp-eq::1`, `::default::1`,
  `::default::2` — the three accepted `mutation-baseline.tsv` prose rows, unmoved.
- **W-4** — fixed; the title now carries `feat(dev-pipeline):`, so the squash subject derives a
  minor.
- **W-5** — deliberately not addressed, and correctly so. `tools/mutation-sweep.sh` sizing its own
  pool at `min(cores-2, 8)` outside the `SEAM_SCRUB_ENV` idiom is outside AC-6's enumeration and
  belongs to #525. Stated as a decision in the PR body rather than left silent, which is what a
  deferral owes.

## Suggestions

- `tools/mutation-catalog.tsv` — the join is catalogued on the **entry** side only. `(jw3)` guards
  the teardown side behaviorally (P3), so nothing is uncovered; what the missing row costs is the
  sweep-level re-application that keeps a guard honest as the file moves underneath it. A symmetric
  `lane-join-teardown-dropped` on `s#^  lane_deregister$#  :#` would make the two sides equally
  durable. Not owed by any AC, and not worth a round.
- `lane-registry.sh:275-278` — `cmd_list` still has no caller in `lean-gate.sh` and no case in the
  suite. Carried from round 1; it is spec'd surface, so wire it or drop it.
- Housekeeping, not in the PR: the reviewed checkout carries an untracked
  `plugins/dev-pipeline/skills/build-lean/lean-gate.sh.orig` (byte-identical to the tracked file,
  timestamped before the last commit — a rebase leftover). It is untracked and not gitignored, so
  it is one `git add -A` away from landing. Not part of this diff and not a finding against it.

## Dismissed

- `scope-completeness-reviewer` (suppressed, 70): that the ceiling block lands after
  `run-selftests.sh:150`'s `--jobs` validation rather than "between the parse loop and the `--root`
  validation". AC-2's landmark is the **`--root`** validation, and the block sits at `:165-174`
  with `[[ -d "$ROOT" ]]` at `:175`. It is exactly where AC-2 asks. Not a placement nuance.
- `security-reviewer` (all suppressed, 35-45): predictable `$REG.reap.$$` / `$REG.dereg.$$` temp
  names, `$issue` interpolated into the TSV row unescaped, and the `LEAN_LANE_PS_DIR` seam being
  unscrubbed for children. No lower-privileged actor in this threat model, and the worst outcome of
  each is a wrong lane count — which degrades toward a *higher* ceiling, the direction the file's
  contract asks for. The read-modify-write race the same class implies was already recorded as a
  visible choice in round 1.

## What I verified rather than took on trust

- The eight probes above, in an isolated worktree.
- CI on this head: `lint-and-selftests` (the ubuntu lane, which runs **without** `SKIP_STRESS`),
  `selftests (macos, bash 3.2)` and `mutation-sweep-pr` all pass — 51 verdicts computed, not a
  deferred no-op. `pr-gates` is red at exactly one arm, `lean chain reconciliation`, with
  frozen-files, changelog-trailer and pipeline-chain all green. That is the missing-verdict arm and
  nothing else.
- The spec is **unchanged** since round 1 (`git diff 1d1d218 e94ba81` empty), and round 1's verdict
  record is untouched — no retrofit in either direction.
- The branch's own contribution to `lean-gate.sh` is identical to round 1's reviewed version except
  the `--help` range re-pin the rebase forced (`2,172p` → `2,177p`); `2,177p` terminates exactly at
  the last header line, with `set -uo pipefail` at `:178`. `lane-registry.sh`, `run-selftests.sh`,
  `run-selftests-selftest.sh` and `docs/testing.md` are byte-identical to round 1's head.
- Both new commits carry `Changelog: none.`, which is the real no-op form here —
  `derive-release.sh:242` lowercases and strips the trailing period, and drops only a block that is
  entirely the no-op word.
- `lane-registry.sh` needs no packaging registration: plugins stage by whole-directory `cp -R`
  (`install-topology-selftest.sh:194`) and suites are glob-discovered (`:222`).

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 registers at `entry`, deregisters at `teardown`, keyed on pid + start time, stale rows reaped | satisfied | `lean-gate.sh:1665`, `:1328`; key at `lane-registry.sh:167-168`, `reap` `:185-191`. **The wiring is now guarded on both sides** — `(jw1)`/`(jw2)` for register, `(jw3)` for deregister, each with its own measured killer (P2, P3). |
| AC-2 `max(1, cores/live_lanes)` exported; runner applies `min()` after the parse loop; unset is a no-op incl. `--jobs 10`; non-positive rejected through the same `die`; both halves of the `getconf` precedent reused | satisfied | `cmd_ceiling` `lane-registry.sh:251-273`, `cores()` `:197-203`; runner `run-selftests.sh:165-174`, between the `--jobs` `die` and `[[ -d "$ROOT" ]]`. Six cases; CI sweeps the runner 14/14. |
| AC-3 ceiling and lane count announced, "advertised, not enforced" | satisfied | `lean-gate.sh:1297-1310`; `(jc2)`, `(jc3)`. |
| AC-4 unreadable / empty / stale degrade to the single-lane answer and name which; never a confident zero | satisfied | Four bases not three (`absent` added); floor at `lane-registry.sh:268,271`; cases (f)(g)(h)(i)(m) and `(jc4)`. |
| AC-5 CI unaffected; asserted by a runner case, not assumed | satisfied | `run-selftests-selftest.sh` "absent leaves the default at 4", plus the `--jobs 10` companion; and both CI selftest lanes are green on this head. |
| AC-6 the ceiling reaches every enumerated milestone-3 site, injected at the shared array, outside the lockstep markers | satisfied | One append at `lean-gate.sh:1310`; markers untouched. Round 1 measured that removing the append fails only `(jc1)`/`(jc4)`. See the W-5 deferral for the site outside the enumeration. |
| AC-7 consumer generality — a convention a consumer may honor | satisfied | `docs/testing.md` maps it onto `vitest --maxWorkers` / `pytest -n` / `cargo test --jobs`; `(jc3)` pins the announcement. |
| AC-8 docs beside the runner contract; runner `USAGE` names it; nothing else made stale | satisfied | `docs/testing.md` "The lane job ceiling"; `run-selftests.sh:65`; the gate's own header at `:155-159`. |

8/8 satisfied, 0 unsatisfied, 0 undeterminable. No blockers. `approve`.

Fidelity: `not-applicable` — the spec's `## Design` section is architecture prose with no handoff
link and no `| RS-n |` rows, and the repo configures no design provider.
