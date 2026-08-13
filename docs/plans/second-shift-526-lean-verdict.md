# lean review verdict — #526

verdict=needs-work
run_id: review-526-1
session_id: 19c92065-03a2-439b-bd14-72ac52e194d6
rounds: 1
pr: #536
reviewed_head: 9d424599442090f48a0ff067ba7938f40bda67d3
reviewed_patch_id: 4f5c0eb67676a88287aef8b566368bfb9b8af341
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full branch range (`fa99191..HEAD`) — nothing to inherit. Panel: security,
performance, maintainability, complexity, test-coverage, unit-test-mutation,
scope-completeness. 7/7 returned; none dark. a11y and the design-fidelity dimension were not
routed — no changed path matches `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`); this diff is shell, markdown and TSV.

The code is right. Every AC is met, the arithmetic and the degradation contract are exactly what
the ticket asked for, and I could not falsify the ceiling logic. The one blocker is that the
feature's **activation** is unguarded: delete the two lines that turn it on and the gate's own
suite stays green, while every lane silently reverts to the pre-#526 whole-machine sizing.

## Blocker

**B-1 — deleting `lane_register` and `lane_deregister` leaves 320/320 cases green.**
`lean-gate.sh:1508` (`cmd_entry`) and `lean-gate.sh:1301` (`cmd_teardown`) are the only two call
sites that make the registry exist at all, and both wrappers are advisory by design
(`lean-gate.sh:1240-1256`: output suppressed, `return 0` on every path). No test sets
`LEAN_LANE_REGISTRY` on an `entry` or a `teardown` invocation — the variable appears in
`lean-gate-selftest.sh` only at `:4641` and `:4667`, both inside the `(jc)` cases, and both invoke
milestone 3 directly against a pre-staged file.

Measured, not inferred. Replacing both call sites with `:` (function bodies left intact, so this
is a wiring mutant), `bash -n` clean, applied diff exactly two lines:

```
-  lane_deregister      -  lane_register
+  :                    +  :
```

`lean-gate-selftest.sh` → **320 PASS, 0 FAIL, "all green"**.

Why this is the blocking one rather than a coverage note: AC-1's subject is the gate at `entry`
and `teardown`, not the helper. `lane-registry-selftest.sh` checks the registry against itself and
the `(jc)` cases check the gate's *read* against a file someone else wrote; the join between them
is checked by nothing. With the join gone the registry stays empty, `basis` resolves `empty`, the
ceiling is the whole machine, and milestone 3 *announces a ceiling* the whole time — the failure is
silent and wears the fix's own output. This is the shape `CLAUDE.md`'s Scenario-first paragraph
names ("every one of them checked a component against itself") and the Test-the-tests contract
makes an obligation of the same diff.

Fix is local and in-tier: take one existing `entry` case and one `teardown` case in
`lean-gate-selftest.sh`, set `LEAN_LANE_REGISTRY` (and `LEAN_LANE_PS_DIR`, or `--pid`/`LEAN_LANE_PID`
to keep the pid deterministic), and assert the row appears and then disappears.

## Warnings

**W-1 — the ancestor walk's pid-0/pid-1 stop is unguarded.** `lane-registry.sh:142`
(`case "$next" in ''|0|1) break ;; esac`). Rewriting it to `case "$next" in '') break ;; esac`
leaves `lane-registry-selftest.sh` **all 24 cases green** (mutant applied, `bash -n` clean). Cases
(a)–(e) never stage process facts for pid 1, so `_ps_field` fails and the walk breaks for the wrong
reason; case (n) bypasses the walk with `--pid $$`. On a real machine `ps -o comm= -p 1` answers, so
this is the branch that stops every lane resolving onto init. Degradation is toward today (all lanes
collapse onto one never-dying row → lanes=1 → whole machine), so it is not a blocker — but it is an
untested guard on the one pid that never dies. Suggest staging a non-shell ancestor at pid 1
(`stage_proc "$PS_C" 200 1 launchd "s"`) and asserting the walk still falls back.

**W-2 — `_is_shell`'s exactness is unguarded, and its comment names the wrong hazard.**
`lane-registry.sh:118`. Dropping `-x` (`grep -qxF` → `grep -qF`) leaves all 24 cases green. Separately,
the comment at `:76-78` justifies `-x` with "no accidental prefix match on a command named
`bashful`" — but `$c` is the *pattern* and `SHELL_NAMES` the input, so `bashful` never matches with
or without `-x`. What `-x` actually prevents is the inverse: a short `comm` (`sh`, `as`, `k`) matching
as a substring of a longer shell name. Worth a case and a corrected comment.

**W-3 — the PR body's "survived=0" contradicts CI's own sweep, and its own table.** The Verification
section claims `lean-gate.sh` 20/20, survived=0. `mutation-sweep-pr` on this exact head reports
`applied=20 killed=17 survived=3` — survivors `lean-gate.sh::cmp-eq::1`, `::default::1`, `::default::2`.
The lane is green because all three are accepted rows in `tools/mutation-baseline.tsv`, and they are
the same three prose ordinals the PR body enumerates two paragraphs earlier with their line numbers
unmoved. So the analysis is right and no ordinal was re-keyed — only the summary phrase is wrong. It
should read `survived=3, all three the accepted baseline rows named above`. PR-body only; no commit
owed, so this costs no round.

**W-4 — the PR title is verbless, so a `feat:` lands as a patch release.** `derive-release.sh:147`
matches `^feat(\([^)]*\))?:` against the **squash subject**, and this repo's
`squash_merge_commit_title` is `COMMIT_OR_PR_TITLE` with two commits on the branch — so the subject
will be the PR title, "A lean lane sizes its milestone-3 sweep to its share of the machine", which
carries no conventional type and derives **patch**. The commit itself is honestly typed
`feat(dev-pipeline):`, and `CLAUDE.md` is explicit that a new capability here is `feat:` because
typing it otherwise "silently downgrades a minor release to a patch". Retitling to
`feat(dev-pipeline): a lean lane sizes its milestone-3 sweep to its share of the machine` fixes it.
Title-only; no commit owed. (Noted: several recent merges landed verbless the same way, so this is
a standing repo drift rather than something this PR invented.)

**W-5 — milestone 3 has a fifth execution site, and it is the repo's other big pool.**
`lean-gate.sh:2671` runs `tools/mutation-sweep.sh` outside the `env ${SEAM_SCRUB_ENV[@]…}` idiom
AC-6 enumerates, and that sweep sizes its own worker pool at `min(cores-2, 8)`
(`mutation-sweep.sh:174-181`) with no knowledge of `LEAN_JOB_CEILING`. On the ten-core box the
ticket measured, five lanes still ask for 5×8 = 40 mutation workers. Strictly outside the ACs — AC-6
enumerates four sites and AC-7 makes honoring the variable optional — but it is repo-local tooling
that *could* read it, and `mutation-sweep.sh:498` already records that pool contention can turn a
would-be survivor into a cached timeout KILL. Worth a follow-up under #525 rather than scope creep
here; flagging so it is a decision rather than an oversight.

## Suggestions

- `lane-registry.sh:271-274` — `cmd_list` has no caller in `lean-gate.sh` and no case in the suite.
  It is in the spec's subcommand list, so it is spec'd surface, not accidental; drop it or wire it.
- `lean-gate.sh:1274-1281` — only the `live` and `absent` arms of the basis message map are
  exercised at gate level (`jc1`–`jc4`); `unreadable`, `empty`, `stale` and the `*` fallback are
  covered one layer down but never rendered by the gate in a test. Message text only.
- `run-selftests.sh:170` — the `JOBS == LEAN_JOB_CEILING` boundary is untested; `-gt` → `-ge`
  survives, costing only a redundant announcement.
- `lane-registry.sh:181-245` — `reap` and `cmd_deregister` are read-modify-write over the shared
  file with `mv -f`; two lanes registering in the same instant can lose a row. Individually atomic,
  and a lost row under-counts (higher ceiling → toward today), which is the direction the file's own
  contract asks for — noting it so the choice is visible.

## What I verified rather than took on trust

- The catalog row `lane-registry-recycled-pid` applies cleanly, stays syntactically valid, and is
  killed by case (j) exactly as it claims.
- Four independent mutants of the runner's ceiling block (comparison inverted, guard removed so it
  becomes an override, validation removed, block never fires) are each killed by a distinct,
  correctly-named case.
- Removing the single `SEAM_SCRUB_ENV+=("LEAN_JOB_CEILING=$ceil")` append (`lean-gate.sh:1285`)
  fails `(jc1)` and `(jc4)` with `child='unset'` and nothing else — the AC-6 injection guard is real
  and precisely targeted.
- `lean-gate.sh --help` still terminates at the last header line after the `2,160p` → `2,165p` bump.
- CI on this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass (48 verdicts computed, not a deferred no-op). The merge ref's first
  parent is `322ef75` = current `origin/main`, so those greens cover main's newest copy of every
  file they read. `pr-gates` is red at exactly one arm — `lean chain reconciliation`, the missing
  verdict record — with the frozen-files, changelog-trailer and pipeline-chain arms all passing.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 registers at `entry`, deregisters at `teardown`, keyed on pid + start time, stale rows reaped | satisfied | `lean-gate.sh:1508`, `:1301`; key at `lane-registry.sh:163-164`, written `:204-217`; `reap` `:181-187`. Recycled-pid catalog mutant killed by case (j). **The wiring itself is unguarded — B-1.** |
| AC-2 `max(1, cores/live_lanes)` exported; runner applies `min()` after the parse loop; unset is a no-op incl. `--jobs 10`; non-positive rejected through the same `die`; both halves of the `getconf` precedent reused | satisfied | `cmd_ceiling` `lane-registry.sh:247-269`, `cores()` `:193-199`; runner `run-selftests.sh:167-174`, sited between the `--jobs` validation and `[[ -d "$ROOT" ]]`. Six cases; four mutants, four distinct kills. |
| AC-3 ceiling and lane count announced, "advertised, not enforced" | satisfied | `lean-gate.sh:1273-1284`; `(jc2)`, `(jc3)`. |
| AC-4 unreadable / empty / stale degrade to the single-lane answer and name which; never a confident zero | satisfied | Four bases not three (`absent` added); floor at `lane-registry.sh:264,267`; cases (f)(g)(h)(i)(m) and `(jc4)`. |
| AC-5 CI unaffected; asserted by a runner case, not assumed | satisfied | `run-selftests-selftest.sh` "absent leaves the default at 4"; and empirically both CI selftest lanes are green on this head. |
| AC-6 the ceiling reaches every enumerated milestone-3 site, injected at the shared array, outside the lockstep markers | satisfied | One append at `lean-gate.sh:1285`; consumed at `:2479`, `:2560`, `:2572`, `:2653`; markers at `:2076-2078` untouched. Removing the append fails only `(jc1)`/`(jc4)`. See W-5 for the site outside the enumeration. |
| AC-7 consumer generality — a convention a consumer may honor | satisfied | `docs/testing.md` maps it onto `vitest --maxWorkers` / `pytest -n` / `cargo test --jobs`; `(jc3)` pins the announcement. |
| AC-8 docs beside the runner contract; runner `USAGE` names it; nothing else made stale | satisfied | `docs/testing.md` "The lane job ceiling"; `run-selftests.sh:65`. |

8/8 satisfied, 0 unsatisfied, 0 undeterminable. Verdict is `needs-work` on B-1 alone — a blocker
outside the AC set, which is where a missing guard on a new contract belongs in this repo.

Fidelity: `not-applicable` — the spec's `## Design` section is architecture prose with no handoff
link and no `| RS-n |` rows, and the repo configures no design provider.
