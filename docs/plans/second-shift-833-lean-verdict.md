# lean review verdict — #833

verdict=approve
run_id: review-833-2
session_id: f973e172-4c4a-4b07-b285-8f9dcd60ad8f
rounds: 2
pr: #839
reviewed_head: f3b9a631f2e6f5f783bbdb762e85674d87b288d8
reviewed_patch_id: d775685fb7f0e5d7b2f0bd632640e06feb11195f
inherited_patch_id: 8c39e7ecc8ceface6e5e022bea590f6c33b324ff
inherited_from_verdict: 4c83dc580f2cba66c9774e1f77ab46bef430011f
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 2 — PR #839 / issue #833

Range read: `4c83dc58..f3b9a631` (5 commits, 17 files, +119/−41), inheriting the coverage of
patch `8c39e7ec` from `docs/plans/second-shift-833-lean-verdict.md` (round 1). Reviewed from a
checkout of the PR head at `f3b9a631f2e6f5f783bbdb762e85674d87b288d8`. Every AC-n was re-scored
against the whole spec, not only the delta.

**Verdict: approve.** Round 1's two blockers are both closed, and both fixes were verified by
execution rather than by reading the diff. Three warnings remain, all of them factual errors in
prose the diff itself wrote this round; none changes behavior and none has a gate that reads it.

## Round 1's blockers

### 1 — `dev-pipeline:` in the sibling toolkits — **FIXED**

`docs/namespaces.md` rule 3, run at this head with the workflow's own two greps
(`.github/workflows/ci.yml:176-194`), against the same four toolkit roots:

```
rule 3(a)  grep -rn 'dev-pipeline:' plugins/{review,intake,design,audit}-toolkit …   -> 0 hits
rule 3(b)  grep -rnE 'dev-pipeline/(workflows|model-tiering)|\.\./dev-pipeline/' …   -> 0 hits
```

(Run with `/usr/bin/grep`; the interactive shell aliases `grep` to a wrapper whose `-E`
alternation semantics differ, and the first measurement of these two was taken with it.)

Corroborated by CI: `lint-and-selftests` **passes** at `f3b9a631`
([job 103015698176](https://github.com/manoldonev/second-shift/actions/runs/34520256551/job/103015698176)),
the job whose *namespace direction check* step was the only red at the round-1 head.

The repair is the right one and not merely the one that clears the grep. All 18 flagged lines across
12 files — 19 occurrences of the token, one line carrying two — now
names the ROLE a sibling can rely on — "the design-sighted REVIEW session", "the pipeline's REVIEW
session", "the BUILD session's step 4", "a pipeline run" — rather than a command a
`design-toolkit`-only consumer cannot resolve. Bare `dev-pipeline` survives throughout, so no
sentence lost its subject, and no site was repaired by deleting the reference.

And the deletion it repairs is complete: `git grep -nE '(build-lean|review-lean|run-lean)' --
':!docs/plans' ':!CHANGELOG.md'` returns **32 hits, all in the AC-9-frozen class** —
`docs/skill-ablation*.md`'s pinned measurements and `dup-scan`'s live corpus. Zero in any shipped
skill, agent or register.

### 2 — the half-cleared `LANE_SELFTEST_CACHE` pair, and (n)'s blind match — **FIXED**

Both halves verified by execution in an isolated worktree at `f3b9a631` (never the reviewed one):

**The leak is closed.** `LEAN_SELFTEST_CACHE=0 bash …/milestone-gate-selftest.sh` →
**621 PASS, all green, rc=0**, with **zero** `[lane-env] notice:` lines anywhere in the output.
Round 1 measured 4 failures — (pg5), (pg8), (sc1), (sc2) — on this exact command at `4e984e1`.

**The guard is live, not decorative.** Mutating only the fix — reverting
`milestone-gate-selftest.sh:58` to `unset LEAN_SELFTEST_CACHE_DIR LEAN_GATE_ANY_TREE`:

```
control (unmutated)  PASS: (n) all 18 (file, knob) scrub pair(s) clear the retired spelling too
mutant               FAIL: (n) 18 (file, knob) scrub pair(s) found, and these clear only the
                           current spelling …: milestone-gate-selftest.sh:LANE_SELFTEST_CACHE
```

**And the whole-token change is what makes that possible.** Re-applying the OLD substring form on
top of the same mutant, with nothing else changed:

```
substring form + mutant   PASS: (n) all 22 (file, knob) scrub pair(s) clear the retired spelling too
```

— a green report over a live defect. This reproduces the PR body's `22 → 18` claim exactly, and
confirms the four it drops were defenses the substring match invented rather than defenses removed.

The new `scrub_token_set()` awk was read against the tree it scans rather than in the abstract. Its
narrowings are safe on this corpus: no `unset -v`/`-f` anywhere (`0` hits), no quoted `unset`
operand (`0`), no trailing-comment `unset LANE_/LEAN_` that could be miscounted as a defense (`0`),
and no `unset` operand list wrapped across a line continuation. `;`/`|`/`&`/`()` are split into
their own words before scanning, so `$( unset X` yields the operator and a `;` still terminates an
operand list.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `docs/plans/second-shift-833-lean.md:105` | AC-9 says "**Five** more members of this class surfaced" and then enumerates **six** bullets. The PR body says six. |
| 2 | Warning | `milestone-gate-selftest.sh:54-56`, and the same claim in the spec and PR body | The stated reason for dropping `LEAN_GATE` from the retired-half scrub — "there is no bare `LANE_GATE` knob … nothing reads the stem" — is false. The removal is still correct; the premise is not, and two sibling suites depend on it being false. |
| 3 | Warning | `docs/prose-blocker-triage.tsv:88,89` | This round's `interviewing-baseline/SKILL.md` re-wording added a line at `:128` and shifted two sibling rows' anchors off by one; `:140` and `:146` are blank lines at this head. |
| 4 | Note | `lane-env-selftest.sh:293` | `retired="LEAN_${t#LANE_}"` derives the retired spelling mechanically, which is wrong for AC-15's two non-prefix pairs. Latent — nothing scrubs either token today — and it fails closed. |

### 1 — WARNING: AC-9's "five more members" enumerates six

`docs/plans/second-shift-833-lean.md:105` opens the frozen sub-list with "Five more members of this
class surfaced during implementation", and the bullets under it are:

```
107  the `lean chain reconciliation` STEP name
114  corpus-live.json
116  the eval records' narrative            <- added this round (round 1's finding 4)
122  docs/skill-ablation*.md
125  the retired `lean/` branch namespace
127  audit-toolkit's adjectival "lean"
```

Six. The PR body's own version of the paragraph says "Six more members of that class surfaced". The
list is the authority and every item on it is correctly frozen, so no AC's outcome moves — but the
branch's last commit (`f3b9a63`, "the frozen-step rationale drops a wrong count") was specifically
about removing a wrong count from this same paragraph, and left the one two lines above it.

### 2 — WARNING: "nothing reads the stem" is false; the removal is right for a different reason

`ff05a6c` drops `LEAN_GATE` from `milestone-gate-selftest.sh`'s suite-scope scrub, on this recorded
ground (`:54-56`, and restated in the spec's departures section and the PR body):

> There is no bare `LANE_GATE` knob: `LANE_GATE_ANY_TREE`, `LANE_GATE_OBSERVE` and `LANE_GATE_LIB`
> are each their own token and nothing reads the stem …

`LANE_GATE` is a bare knob, and it is read exactly as a knob:

```
orchestrate.sh:231-232   lane_env_promote LANE_SPAWN_BIN … LANE_SPAWN_CLOCK LANE_GATE \
                           LANE_OVERRIDE_TOOL LANE_LAUNCH_ID
orchestrate.sh:257       GATE="${LANE_GATE:-$SCRIPT_DIR/../build/milestone-gate.sh}"
```

It is in `lane-env-selftest.sh`'s own `ALL_KNOBS` census for that reason, and two sibling suites
clear its retired half deliberately, each saying so in the same words this note contradicts:

```
orchestrate-selftest.sh:25-30        "This suite scrubs the `LANE_GATE` and `LANE_SPAWN_*` seams
scenario-liveness-selftest.sh:78-83   … an ambient LEAN_GATE would walk straight through a scrub
                                        that named only the current name"
                                      unset LEAN_GATE …
```

`scenario-liveness-selftest.sh:1801` runs the real `orchestrate.sh`, so that is not a precaution
against a hypothetical reader. The PR body's supporting clause — "the only `LEAN_GATE` on `main` was a
local variable holding a path" — is wrong the same way: `main`'s `orchestrate-lean.sh:247` is
`GATE="${LEAN_GATE:-…}"` and `:202` documents it in the script's own knob list.

**The removal itself is correct.** `milestone-gate-selftest.sh` sets `GATE="$HERE/milestone-gate.sh"`
at `:22` and never invokes `orchestrate.sh`, so no reader of `LANE_GATE` runs under it and the scrub
was inert *there*. The honest reason is scope — "this suite drives no reader of that knob" — not
nonexistence. As written, the note argues equally for deleting `LEAN_GATE` from
`orchestrate-selftest.sh:30` and `scenario-liveness-selftest.sh:83`, where it is load-bearing, and
`lane-env-selftest.sh` case (n) would not catch that: (n) requires the retired half only for knobs a
file also scrubs under the CURRENT spelling, and neither suite `unset`s bare `LANE_GATE`.

Same class as round 1's finding 3, which this round corrected: a correct decision recorded on a
premise that does not survive one look at the code.

### 3 — WARNING: two triage anchors now point at blank lines

`add2330` grew `interviewing-baseline/SKILL.md`'s milestone-gate paragraph from four lines to five
(`@@ -125,10 +125,11 @@`) and shifted everything below it. `docs/prose-blocker-triage.tsv` still
anchors two rows at the pre-shift positions:

```
row 88  pb-be1ceaa2  …/interviewing-baseline/SKILL.md:140   -> blank line (construct is at :141)
row 89  pb-db3589f8  …/interviewing-baseline/SKILL.md:146   -> blank line (construct is at :147)
```

At `main` and at the round-1 head `4c83dc58`, `:140` was the "Put an `OR-n` on every region" bullet
and `:146` the "environment refusal … spends none of milestone 1's fix budget" paragraph — exactly
what those two rows describe.

Not a red, and correctly so: `tools/prose-blockers.sh` derives identity from content ("relocating a
rule within a file — or between files — re-keys nothing", `:30-31`), and `bash tools/prose-blockers.sh
check` is green at this head (29 constructs / 52 rows, zero undispositioned). But the same commit
re-keyed `pb-1bb19015 → pb-efe96c8c` in that file, so the register was already open; the two sibling
line numbers are a two-character fix left on the table. Neighbours are unaffected: `pb-0fcf3243`
(`:183`) is a `prose-deleted` historical row, and every `figma-faithful/SKILL.md` anchor (`:51`,
`:188`, `:223`) sits above that file's `-1` line at `:242`.

### 4 — NOTE: (n)'s retired-spelling derivation is wrong for AC-15's two pairs

`lane-env-selftest.sh:293` computes `retired="LEAN_${t#LANE_}"`. AC-15's two knobs are renamed, not
re-prefixed — `LANE_BENCH_ROOT` ← `LEAN_BENCH_SS_ROOT`, `LANE_BENCH_BIN` ← `LEAN_BENCH_LANE_BIN` —
so for those the derivation names tokens that do not exist. Latent only: neither is `unset` or
`env -u`'d anywhere (`0` hits), so (n) never derives them, and if one ever is, (n) reds on a
correctly-paired file rather than passing a leak. The safe direction, and `lane-env-selftest.sh:111`
already records that these two "cannot be derived" — worth the same sentence beside the derivation
itself.

## Dismissed

- **AC-14's sweep evidence is recorded at `4e984e1`, three functional commits behind the head**
  (`scope-completeness-reviewer`, blocker, 88). The observation is accurate about the *committed*
  record and is the right thing for that reviewer to raise; it is answered by execution this round,
  at `f3b9a631`, for both halves of AC-14 — see the AC-14 row. Same disposition as round 1's
  identical finding. This verdict record is where that measurement becomes committed evidence.
- **Two `CLOSEOUT-BASELINE.md` concept-noun lines survive** (`scope-completeness-reviewer`,
  suppressed, 70). Round 1's finding 4 offered "either convert them or record them"; round 2
  recorded them, in AC-9's frozen class rather than the departures section, which is the stronger
  of the two placements. Verified the three cited lines exist and read as claimed
  (`figma-faithful-plan-reviewer-eval:62`, `figma-faithful-spec-reviewer-eval:47,:64`).
- **`gate-ablation-adjudication.tsv` is named by AC-6 with "(14)" but is unchanged**
  (`scope-completeness-reviewer`, suppressed, 65). Correct and already dispositioned: the spec's
  departures section drops it from AC-6 on the measured ground that all 14 hits are
  `<issue>-lean-progress.md` citations, a frozen artifact family. Re-measured: 0 retired basenames.

## Verification performed this round

Executed from a checkout of the PR head at `f3b9a631`, in a **scheduler-spawned session with
`LEAN_ATTEND_MODE=headless` and `LEAN_RUN_MODEL=opus` ambient** — the retired spellings this PR's
fallback resolves, and the exact environment the round-1 hermeticity defect lived in:

- `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  → **79 scored, 79 run, 0 served from cache, 0 failed**, rc=0. Cold: no `--cache-dir`.
- `bash tools/install-topology-selftest.sh` → **54 ran, 54 passed, 3 skipped, 0 red**, rc=0, run alone on an otherwise idle host
- `LEAN_SELFTEST_CACHE=0 bash …/milestone-gate-selftest.sh` → 621 PASS, all green, rc=0, zero
  `[lane-env] notice` lines in captured output (round 1: 4 failures at `4e984e1`).
- Mutation probe on the fix, isolated worktree: scrub reverted → (n) reds naming the pair; scrub
  reverted + substring match restored → (n) greens at 22 pairs. Both halves of the round-1 blocker
  are independently load-bearing.
- `docs/namespaces.md` rule 3(a) and 3(b) with the workflow's own greps → 0 hits each.
- `bash tools/prose-blockers.sh check` → green, 29 constructs / 52 rows, zero undispositioned.
- `git grep -F 'LEAN_' -- ':!docs/plans' ':!CHANGELOG.md'` → 23 files, unchanged from round 1;
  the two the delta touched are both documented compatibility sites. Control: `git grep -E '\bLEAN_'`
  → 0, as the spec warns.
- Ten path-keyed registers re-grepped for the six retired basenames → 0 each.
- `tools/mutation-catalog.tsv`'s two `lane-env` rows: both `sed` anchors still resolve in
  `lane-env.sh` (comment-only change this round). No catalog row targets a `-selftest.sh` — 0 of
  155 — so the guard-vs-subject convention is unchanged, not sidestepped.
- Commit trailers across all 17 branch commits; frozen files (`CHANGELOG.md`, `plugin.json`,
  `marketplace.json`) untouched.
- CI at `f3b9a631`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Re-measured at this head: `git ls-files` matches none of the six retired basenames or their selftests. Inherited from round 1, which read the 11 `git mv`s and classified the four surviving retired-path mentions as compat sites that name the path *as* retired |
| AC-2 | satisfied | Inherited from round 1 (fallback reader, promote census, bash 3.2.57 execution). Re-measured this round: `lane-env-selftest.sh` (l) reports **39** discovered knobs, all promoted, green in the cold sweep at this head. The delta's own change is to (n), not to the reader |
| AC-3 | satisfied | Inherited from round 1 (one notice per token per process, fd 2 only, end to end through both a sourcing script and the inline twin). Re-measured: green at this head, and independently — `LEAN_SELFTEST_CACHE=0 …/milestone-gate-selftest.sh` produced **zero** notice lines in 621 passing cases, which is the same assertion from the caller's side |
| AC-4 | satisfied | Inherited from round 1: `operator-override.sh:313-325` reads `.claude/lane-overrides.tsv` first with a one-time stderr fallback, outside the `override-record-reader` LOCKSTEP block, which stays byte-identical. Untouched by the delta |
| AC-5 | satisfied | Re-measured: `git grep -F 'LEAN_' -- ':!docs/plans' ':!CHANGELOG.md'` → 23 files, identical to round 1's set. The two the delta touched (`lane-env-selftest.sh`, `milestone-gate-selftest.sh`) are the suite that proves the fallback and a suite-scope retired-half scrub — both named exemptions. `git grep -E '\bLEAN_'` → 0, as the spec warns |
| AC-6 | satisfied | Re-measured at this head: all ten registers (the eight AC-6 names plus `mutation-exclusions.tsv` and `gate-ablation-adjudication.tsv`) grepped for the six retired basenames → **0 hits each** |
| AC-7 | satisfied | Inherited from round 1. Re-measured: no catalog row id names a renamed script; both `lane-env` rows' mutation anchors still resolve in `lane-env.sh`; `mutation-sweep-pr` green in CI at this head |
| AC-8 | satisfied | `plugins/dev-pipeline/skills/` holds `build perf-retro pipeline-retro pr-revision review run` — the three alias directories are gone. Its consequence, round 1's blocker 1, is closed under AC-13 |
| AC-9 | satisfied | Re-measured: `LANE_PR_MARKER_TAG='lean-pr-marker'` with `LOCKSTEP-BEGIN lean-pr-marker` intact in `boundary-evidence.sh:627,637`; all four `# lean …` title lines present at `milestone-gate.sh:1302,4458,4852,5618`; `lean chain reconciliation` unchanged at `ci.yml:323`. Round 1's finding 3 is fixed — the corrected rationale ("a `- name:` step inside `pr-gates`, not a required status check") is verified true: `gh pr checks` keys on `pr-gates`, and the step name appears only at `:323`. The three eval-record lines round 1 raised are now enumerated in this AC's frozen class. Finding 1 (the list says six, the sentence says five) is in this AC's prose and moves nothing it freezes |
| AC-10 | satisfied | Inherited from round 1: `second-shift-ci-check.sh:172` fetches the new `boundary-evidence.sh` path; the retired `SECOND_SHIFT_LEAN_EVIDENCE` seam resolves once with a stderr notice at `:166-168`. Untouched by the delta |
| AC-11 | satisfied | Re-measured across all 17 branch commits: `f7aab59` is `feat(dev-pipeline)!:` with a `Changelog:` trailer naming the `second-shift-ci-check.sh` re-copy and the alias removal, plus a `BREAKING CHANGE:` footer; the other sixteen carry `Changelog: none.` with only a `Co-Authored-By` line after it. No frozen file is touched |
| AC-12 | satisfied | Inherited from round 1 (zero stale script paths in the six named docs or the schema). Re-measured: `jq empty schema/second-shift.config.schema.json` clean, and the schema's two `description` strings no longer name a deleted alias |
| AC-13 | satisfied | Round 1 scored this `unsatisfied` on two grounds and both are answered. (a) `docs/namespaces.md` rule 3(a)/3(b) → 0 hits each at this head with the workflow's own greps, and `lint-and-selftests` passes in CI at `f3b9a631`; the 19 sites now name a role rather than a namespace, so the dangle is repaired without breaking the one-directional dependency. (b) The two `CLOSEOUT-BASELINE.md` concept-noun lines are recorded — in AC-9's frozen class, with a third alongside them. No `build-lean`/`review-lean`/`run-lean` reference survives in any shipped skill, agent or register: 32 hits remain and all 32 are AC-9-frozen measurements or the frozen `dup-scan` corpus |
| AC-14 | satisfied | Both halves executed at **this head**, not inherited. (a) `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` → 79 scored, 79 run, 0 served from cache, 0 failed, rc=0 — cold, and from a scheduler-spawned session carrying ambient `LEAN_ATTEND_MODE` and `LEAN_RUN_MODEL`, which is the environment the hermeticity work is for. (b) `bash tools/install-topology-selftest.sh` → **54 ran, 54 passed, 3 skipped, 0 red**, rc=0, run alone on an otherwise idle host. CI corroborates (a) on two platforms with `--cache-dir`; (b) has no CI to cite at this head — its workflow is `skipping`, the push filter being deliberately too narrow for a shipped-suite content change, which is why it was run directly |
| AC-15 | satisfied | Re-measured: `LANE_BENCH_LANE_BIN` and `LANE_BENCH_SS_ROOT` appear only inside two comments explaining why they do not ship (`lane-env-selftest.sh:111`, `lane-bench.sh:89`); `lane-bench.sh` wires `LANE_BENCH_ROOT`/`LANE_BENCH_BIN` each to its own retired spelling. Finding 4 is about the guard's derivation for these two, not about what ships |

## Design fidelity

Not applicable. The spec disarms with `Design: none — this change renames files, identifiers and
prose. It renders no UI, adds no screen and no component, and the repo configures no
`design.provider`.` Re-confirmed at this head: `jq '.design'` on the resolved config returns null,
`stageParams.webComponentGlobs` is unset, and no changed path is a web-component surface. The
disarm is justified on a repo that configures no provider, and the delta does not arm it.

## Panel

`review-toolkit:scope-completeness-reviewer` was selected and returned (`request-changes`, one
blocker, dismissed above with its own measurement). No other subagent met a trigger: no security
surface in the diff and no `.claude/second-shift/review-context/security-reviewer.md` in the repo,
so the security dimension was the lead pass's; no DB, queue-processor or co-located-unit-spec
surface; and no changed path matched `stageParams.webComponentGlobs` (unset → the shipped default
`apps/web/**/*.{tsx,jsx}`), so a11y and the design-fidelity dimension were not routed. Performance,
maintainability, complexity and test-coverage were the lead pass's this round, as the collapsed
panel intends. No reviewer went dark.

## Merge-boundary state (recorded, not a finding)

`pr-gates` is red at 7s, on its `lean chain reconciliation` step only:
`✗ verdict record … reads 'verdict=needs-work', not 'verdict=approve' — freshness is undefined for
a non-approve record`. That is the chain gate reading round 1's record; it cannot be green before
an approve record exists. Every other CI job at this head is green or correctly skipped.
