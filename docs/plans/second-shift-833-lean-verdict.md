# lean review verdict — #833

verdict=needs-work
run_id: review-833-1
session_id: 73dc2a6b-18d5-49b5-ab49-2ff840de0e03
rounds: 1
pr: #839
reviewed_head: 4e984e1d113be12aaa3b1c2d49955f43af29c0e4
reviewed_patch_id: 8c39e7ecc8ceface6e5e022bea590f6c33b324ff
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — PR #839 / issue #833

Range read: `3113cb95..4e984e1d` (root round, full branch diff — 140 files, +3151/−2341).
Reviewed from a checkout of the PR head at `4e984e1d113be12aaa3b1c2d49955f43af29c0e4`.

**Verdict: needs-work.** Two blockers. The rename itself is well executed — every subject and
selftest moved, all ten path-keyed registers carry zero stale anchors, the frozen wire values and
LOCKSTEP anchors are intact, and the three inline twins of the compatibility reader are
byte-identical. Both blockers are in the *consequences* of the change, not in the renames.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | 12 files across the four sibling toolkits | AC-8's alias deletion was repaired by re-pointing the dangling pointers at `/dev-pipeline:*`, which `docs/namespaces.md` rule 3(a) forbids inside a toolkit. **`lint-and-selftests` is RED at this head.** |
| 2 | **Blocker** | `milestone-gate-selftest.sh:48` vs `:8593`, `:8612` | The `LANE_SELFTEST_CACHE` / `LEAN_SELFTEST_CACHE` scrub pair is half-cleared, so a documented operator export falsifies four cases through AC-2's own fallback — and `lane-env-selftest.sh` case (n), added to catch exactly this, scores the pair clean because its match is a substring. |
| 3 | Warning | `docs/plans/second-shift-833-lean.md` AC-9 | The rationale for freezing `lean chain reconciliation` is factually wrong: it is a *step* name, not a required status check. |
| 4 | Warning | two `CLOSEOUT-BASELINE.md` files | AC-13's concept-noun rule leaves two "the lean lane's build session" lines unconverted. |
| 5 | Note | `lane-env.sh:35` | The stderr notice lands inside any caller that captures `2>&1` — two of finding 2's four failures are that, not the leaked value. |

### 1 — BLOCKER: 18 `dev-pipeline:` references introduced into the sibling toolkits; `lint-and-selftests` is red

CI job [102995894789](https://github.com/manoldonev/second-shift/actions/runs/34514332895/job/102995894789),
step **namespace direction check (docs/namespaces.md rule 3)**:

```
##[error]rule 3(a): a toolkit references the dev-pipeline: namespace
##[error]Process completed with exit code 1.
```

Every other step in that job passed, including `run all selftests`. This is the only red step.

Measured at both ends of the range, with the guard's own grep:

```
grep -rn 'dev-pipeline:' plugins/review-toolkit plugins/intake-toolkit plugins/design-toolkit \
  plugins/audit-toolkit --include='*.md' --include='*.mjs' --include='*.sh' --include='*.json'
  HEAD (4e984e1) -> 18 hits in 12 files
  base (3113cb9) -> 0
```

The 12 files: `review-lead/SKILL.md` (3), `intake/SKILL.md`, `interviewing-baseline/SKILL.md`,
`plan-interview/SKILL.md` (4 between them), the four `design-toolkit/agents/*.md` and three
`design-toolkit/skills/*/SKILL.md` (10), `audit-history/SKILL.md` (1).

This is the direct cost of AC-8: #834 cleared the shipped *invocations* while the aliases still
resolved, and the spec's own departures section counts the seventeen pointers that become dangling
once the directories go. Re-spelling them `/dev-pipeline:review` fixes the dangle and trips rule
3(a), which exists so a toolkit stays installable without dev-pipeline — a consumer who installed
only `design-toolkit` is now told to invoke a command their machine does not have.

**This is a correctness lane, not a policy gate.** The merge-boundary carve-out covers gates that
score release hygiene (the `Changelog:` trailer, frozen files) and are cleared by a mechanical
commit. This one scores plugin coupling, is enforced in `lint-and-selftests`, and its fix is a
wording decision across ten shipped files that a reviewer's judgement has to shape — which spelling
replaces the alias without naming the sibling namespace. It stays a blocker.

Worth deciding deliberately rather than by search-and-replace: the guard forbids the `dev-pipeline:`
token, so `/dev-pipeline:review` is out, and the sentences need a phrasing that survives it (the
pre-#834 text said "the design-sighted `review-lean` session", i.e. named no namespace at all).

### 2 — BLOCKER: the fallback re-opens a hermeticity hole, and the new guard is blind to it

`LANE_SELFTEST_CACHE` is a promoted knob (`milestone-gate.sh:287`), so the retired
`LEAN_SELFTEST_CACHE` resolves through AC-2's fallback. The suite's retired-half scrub does not
name it:

```
milestone-gate-selftest.sh:48   unset LEAN_GATE LEAN_SELFTEST_CACHE_DIR LEAN_GATE_ANY_TREE
milestone-gate-selftest.sh:8593 out="$( unset RUN_ID … LANE_SELFTEST_CACHE_DIR LANE_SELFTEST_CACHE
milestone-gate-selftest.sh:8612 out="$( unset RUN_ID … LANE_SELFTEST_CACHE
```

`LEAN_SELFTEST_CACHE_DIR` is scrubbed; `LEAN_SELFTEST_CACHE` is not.

**Measured**, cold, in an isolated worktree at `4e984e1`:

```
LEAN_SELFTEST_CACHE=0 bash plugins/dev-pipeline/skills/build/milestone-gate-selftest.sh
  -> 617 PASS, 4 FAILURE(S)
     (pg5) an attempt row moved the milestone-5-scoped token
     (pg8) expected m5sat-v1:0 with no file created
     (sc1) expected the announced default store to reach the child … child='unset'
     (sc2) expected the operator store to be the announced one
   every one carrying: [lane-env] notice: LEAN_SELFTEST_CACHE is the retired spelling of
   LANE_SELFTEST_CACHE and still resolves.
```

**New, not pre-existing.** On `3113cb9` the same two cases read
`unset RUN_ID … LEAN_SELFTEST_CACHE_DIR LEAN_SELFTEST_CACHE` (`lean-gate-selftest.sh:8575`, `:8594`)
and there was no second spelling to leak, so the ambient was fully controlled. This PR renames the
scrub to the current spelling and leaves the retired half resolving.

**The knob is one the repo tells operators to export.** `docs/testing.md:420` — "It has an off
switch. `LANE_SELFTEST_CACHE=0` runs the lane cold, announced"; and the measurement recipe at
`docs/testing.md:1873` hands the operator `env RUN_ID=<id> SELFTEST_JOBS=<n> LANE_SELFTEST_CACHE=<0|1>`.
Anyone whose shell still carries the pre-rename spelling of that recipe reds four cases.

**The sweep does not shield it.** `tools/run-selftests.sh:188` scrubs
`-u LANE_SELFTEST_CACHE_DIR -u LEAN_SELFTEST_CACHE_DIR` and nothing else, so the ambient reaches
every suite — AC-14's own command reds under it too.

**Why `lane-env-selftest.sh` case (n) says the pair is clean.** Its retired-half test is a substring
glob over the whole file's scrub lines:

```
case "$sf_retired" in
  *"unset "*"$retired"*|*"-u $retired"*) : ;;      # $retired = LEAN_SELFTEST_CACHE
```

and `LEAN_SELFTEST_CACHE_DIR` *contains* `LEAN_SELFTEST_CACHE`, so the `_DIR` scrub satisfies the
requirement for the bare token. Extracting (n)'s own logic and running it against this file:

```
LANE_SELFTEST_CACHE -> scrub COUNTED ; (n) says PAIRED
                       (literal 'LEAN_SELFTEST_CACHE' present as its own token? NO)
```

The scrub-detection side has the same shape, so a file that scrubs only `LANE_SELFTEST_CACHE_DIR`
would also be counted as defending `LANE_SELFTEST_CACHE`. The same prefix relation is latent on
`LANE_GATE` against `LANE_GATE_ANY_TREE` / `_OBSERVE` / `_LIB` / `_TEST_STALL_DIR` — those happen to
be genuinely paired today, so no second leak, but (n) cannot tell the difference.

This matters beyond the one knob: the spec's departures section presents (n) as the guard that
found and closed this class after it falsified four suites. It closed the instances it could see.
A guard that reports PAIRED on a superstring is the fail-open shape, in the file whose whole
purpose is to refuse it — and the ticket's own history is the argument for fixing it here rather
than filing it. Word-boundary the match (both halves) and re-run; expect (n) to name this pair.

### 3 — WARNING: AC-9's reason for freezing `lean chain reconciliation` does not hold

AC-9 freezes the name on the ground that it is "a required status check keyed BY NAME in branch
protection, here and in every consumer that gates on it, so renaming it is a settings migration …
and it would red this PR's own merge."

It is a **step** name inside the `pr-gates` job (`.github/workflows/ci.yml:323`,
`- name: lean chain reconciliation (pipeline PRs carry their evidence set)`). Branch protection keys
on the job, `pr-gates`. Renaming the step is a one-line change that migrates no settings and reds no
merge.

Freezing it is still the right outcome — it is churn with no payoff — but the recorded reason is
false, and a future ticket reading AC-9 would refuse a legitimate rename on a premise that does not
survive one look at the workflow. Correct the rationale rather than the freeze.

### 4 — WARNING: two AC-13 concept-noun lines survive

```
plugins/design-toolkit/evals/figma-faithful-plan-reviewer-eval/CLOSEOUT-BASELINE.md:62
  … #705 closed it: the lean lane's build session dispatches this agent at milestone 3 …
plugins/design-toolkit/evals/figma-faithful-spec-reviewer-eval/CLOSEOUT-BASELINE.md:64
  … The agent is the only reachable spec-side owner on the lean lane, and …
```

Of the 10 word-bounded sibling-plugin `lean` lines left at this head, eight are AC-9's frozen class
(audit-toolkit's adjectival "lean" ×4, the `dup-scan` corpus ×2, `doctor-selftest.sh`'s `PRE-LEAN`
and its frozen `# lean run` fixture). These two are neither: they are prose using "lean" as a
concept noun, which AC-13 says reads as "the lane". Neither file is touched by this PR and neither
line names anything that dangles, so the cost is cosmetic — but the spec claims AC-13 is "verified
by a grep returning empty", and that grep does not return empty. Either convert them or record them
in the departures section the way `docs/skill-ablation*.md` is recorded.

### 5 — NOTE: the deprecation notice reaches `2>&1` captures

Two of finding 2's four failures — (pg5) and (pg8) — do not fail on the leaked *value*; they fail
because `[lane-env] notice: …` lands inside output the case captured with `2>&1` and compared. D-6
picked stderr because "these scripts' stdout is PARSED by their callers", which is right, but this
repo's own suites routinely capture both streams. Nothing else in the tree hits it at this head, so
it is not a blocker on its own — it is what makes finding 2 cost four cases instead of two, and it
is worth a line in `lane-env.sh`'s header so the next caller knows.

## Dismissed

- **`SECOND_SHIFT_LEAN_EVIDENCE` is outside AC-5's exemption** (scope-completeness-reviewer, 82).
  The spec's Scope → In names it explicitly: "`SECOND_SHIFT_LEAN_EVIDENCE`, the consumer template's
  own seam, renamed `SECOND_SHIFT_BOUNDARY_EVIDENCE` with its own inline fallback: it carries the
  literal `LEAN_` that AC-5's fixed-string grep would otherwise find." In scope, and correct.
- **`boundary-evidence.sh` is not executable after the rename** (suppressed, 60). `100644` at both
  `3113cb9` and HEAD — the mode is unchanged, and it is a fetched payload invoked via `bash`.
- **AC-14 has no evidence on the branch** (scope-completeness-reviewer, blocker, 88). Answered by
  execution rather than by the PR body — see the AC-14 row below.

## Verification performed this round

- `git grep -F 'LEAN_' -- ':!docs/plans' ':!CHANGELOG.md'` → 23 files; read every hit, all are
  documented compatibility sites. (The PR body says 22 — off by one, immaterial to the AC.)
- Token-set comparison base→head: every `LEAN_*` token on `3113cb9` has a `LANE_*` counterpart at
  HEAD; no knob was dropped.
- Independent promote census: every `${LANE_X:-…}` environment read in a non-selftest script is
  covered by a `lane_env_promote` / `lane_env` call in its own file (line continuations folded).
- `${LANE_X+…}` / `${LANE_X-…}` audit → zero, so promote-in-place is behavior-preserving as claimed.
- LOCKSTEP `lane-env-fallback`: `lane-env.sh`, `boundary-evidence.sh` and `run-selftests.sh` twins
  are byte-identical (`md5` 8b28caf236231b904139df395adc2e45).
- `lane_env` executed under stock `/bin/bash` 3.2.57: indirection and `printf -v` resolve, the
  notice is stderr-only, and it fires once per token per process.
- Ten path-keyed registers grepped for the six retired basenames → 0 stale anchors each.
- `LEAN_SELFTEST_CACHE=0 bash …/milestone-gate-selftest.sh` at 4e984e1 → 4 failures (finding 2).
- `bash tools/install-topology-selftest.sh` at 4e984e1, run alone → see AC-14.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `git ls-files` matches none of the six retired basenames or their selftests; 11 `git mv`s; the only surviving textual references are four compat-site mentions that name the retired path *as* retired (`operator-override.sh:306,313`, `second-shift-ci-check.sh:162`, `docs/config-schema.md:33`) |
| AC-2 | satisfied | `lane-env.sh` reads `LANE_*` first, falls back to `LEAN_*`; independent census confirms every `${LANE_X:-…}` environment read in a non-selftest script is promoted in its own file; no `LEAN_` token from the base lacks a `LANE_` counterpart at HEAD; verified executing under bash 3.2.57 |
| AC-3 | satisfied | executed: `LEAN_ATTEND_MODE=headless` + two `lane_env` reads of the same token emit exactly one `[lane-env] notice:` line, on fd 2, nothing on fd 1; `lane-env-selftest.sh` cases (g)–(k) drive the same end to end through both a sourcing script and the inline twin |
| AC-4 | satisfied | `operator-override.sh:313-325` — `override_register_path()` takes `.claude/lane-overrides.tsv` first, falls back to `.claude/lean-overrides.tsv` with a one-time stderr notice, and sits outside the `override-record-reader` LOCKSTEP block, which stays byte-identical on both sides |
| AC-5 | satisfied | `git grep -F 'LEAN_' -- ':!docs/plans' ':!CHANGELOG.md'` → 23 files; each hit read and classified as a documented compatibility site (2 fallback readers, 9 sourcing scripts, 5 suite-scope retired-half scrubs, `lane-env-selftest.sh`, 1 catalog row, docs/register notes). `git grep -E '\bLEAN_'` returns zero on this path, as the spec warns |
| AC-6 | satisfied | all ten registers grepped for the six retired basenames (`lean-gate`, `lean-evidence`, `lean-reconcile`, `orchestrate-lean`, `check-lean-chain`, `lean-overrides`) → 0 hits each, including the two the departures section drops from the list |
| AC-7 | satisfied | no `tools/mutation-catalog.tsv` row id names a renamed script; the surviving `lean-*` ids name frozen artifact families (plan / open-regions / measure records), which AC-9 freezes and re-keying would falsify. `mutation-sweep-pr` green at this head |
| AC-8 | satisfied | `plugins/dev-pipeline/skills/` holds `build perf-retro pipeline-retro pr-revision review run` — the three alias directories are gone. The cost of the deletion is finding 1, scored under AC-13 |
| AC-9 | satisfied | `LANE_PR_MARKER_TAG='lean-pr-marker'` with `LOCKSTEP-BEGIN lean-pr-marker` intact in both `milestone-gate.sh:2641,2651` and `boundary-evidence.sh:627,637` — name moved, value and anchor frozen; all four `# lean …` title lines present; `lean chain reconciliation` unchanged at `ci.yml:323`. Its stated *rationale* is wrong (finding 3) but the freeze itself is correct |
| AC-10 | satisfied | `second-shift-ci-check.sh:172` fetches `plugins/dev-pipeline/skills/build/boundary-evidence.sh`; the retired `SECOND_SHIFT_LEAN_EVIDENCE` seam still resolves once with a stderr notice at `:166-168` |
| AC-11 | satisfied | `f7aab59` is `feat(dev-pipeline)!:` with a `Changelog:` trailer naming the `second-shift-ci-check.sh` re-copy and the alias removal, plus a `BREAKING CHANGE:` footer; the other twelve commits carry `Changelog: none.` with no trailing prose |
| AC-12 | satisfied | zero stale script paths in `CLAUDE.md`, `docs/testing.md`, `docs/config-schema.md`, `docs/releasing.md`, `docs/lane-bench.md`, `docs/pipeline-manifesto.md` or the schema; `jq empty schema/second-shift.config.schema.json` clean |
| AC-13 | unsatisfied | the re-pointing introduced 18 `dev-pipeline:` references across 12 sibling-toolkit files (0 at `3113cb9`), violating `docs/namespaces.md` rule 3(a) and redding `lint-and-selftests` at this head — finding 1; and two `CLOSEOUT-BASELINE.md` concept-noun lines are unconverted — finding 4 |
| AC-14 | satisfied | (a) `run all selftests` green in CI job 102995894789 (linux) and `selftests (macos, bash 3.2)` job 102995894418 green, both at 4e984e1; CI adds `--cache-dir`, which the build's own cold local run (79 scored / 79 run / 0 cached / 0 failed) covers. (b) executed this round: `bash tools/install-topology-selftest.sh` at 4e984e1 — **54 ran, 54 passed, 3 skipped, 0 red**, matching the PR body. A first attempt reported 1 red on `orchestrate-selftest.sh` (sig2), a signal-timing case, while a second heavy suite shared the host; re-run alone it is green |
| AC-15 | satisfied | `LANE_BENCH_LANE_BIN` and `LANE_BENCH_SS_ROOT` appear only inside comments explaining why they do not ship; `lane-bench.sh:91-92` wires `LANE_BENCH_ROOT`/`LANE_BENCH_BIN` each to its own retired spelling via `lane_env`'s fourth argument |

## Design fidelity

Not applicable. The spec disarms with `Design: none — this change renames files, identifiers and
prose. It renders no UI, adds no screen and no component, and the repo configures no
`design.provider`.` Confirmed: `jq '.design'` on the resolved config returns null, and no changed
path is a web-component surface. The disarm is justified on a repo that configures no provider.

## Panel

`review-toolkit:scope-completeness-reviewer` returned. Performance, maintainability, complexity and
test-coverage were the lead pass's this round; `security-reviewer` was not selected — the diff
carries no authentication, tenancy, upload or external-input query-construction surface and the repo
carries no `review-context/security-reviewer.md`, so the lead pass owned the security dimension and
found nothing. No reviewer went dark.

## Merge-boundary state (recorded, not a finding)

`pr-gates` is red at 9s — the chain gate cannot be green before an approve record exists. Recorded,
not scored.
