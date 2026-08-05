# lean review verdict — #381

verdict=approve
run_id: review-381-2
session_id: 306ddcb6-e836-411a-825a-4fd80ebda82b
rounds: 2
pr: #384
reviewed_head: 5312772ce107382181c6b0d84b8fe5b27a2e3a29
reviewed_patch_id: 91659d875501c5499cc9f53e0c783f88a4a87a93
model: unknown

## Verdict: approve

Round 1's blocker is resolved, and I verified it independently rather than against round 1's
own suggested wording. No new blocker. Five specialist reviewers returned zero findings on the
whole branch diff; the sixth went dark and was re-dispatched over the delta, also zero. The
full gate is green from the PR head, and the two assertions the round-2 fix added are killable
— I probed both.

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | PR #384 body, Verification section | "`mutation-sweep-selftest.sh` grew by nine cases" — it grew by **seven** (`(ac)`…`(ai)`). The round-2 delta added two *assertions* inside the existing case `(af)`, and the count was bumped as if they were cases. |
| 2 | Warning (carried from round 1) | issue #381 body | AC-11's widening is still recorded only in branch-local artifacts. `scope-completeness-reviewer` re-raised it at confidence 92; overridden again, with the reasoning and the substituted remedy stated below. |

### Round 1's blocker — RESOLVED, verified three ways

The false `Changelog:` trailer naming `tools/mutation-serial-suites.tsv` is gone. What I
checked, independently of the fix commit's own claims:

- **Exactly one non-`none` `Changelog:` block on the branch**, on the feature commit
  `e148a28`. The other seven commits carry `Changelog: none.`, so `derive-release.sh` renders
  one bullet, not two.
- **Every claim in the new trailer is true against the final tree.** Its six named knobs —
  `MUTATION_SWEEP_JOBS`, `_CACHE`, `_CACHE_DIR`, `_CACHE_MAX`, `_EARLY_EXIT`, `_FAIL_PATTERN`
  — are *exactly* the set this branch adds: `git show main:tools/mutation-sweep.sh` names only
  `MUTATION_SWEEP_K` and the three `_KILLER_*` knobs, so the delta is those six and no seventh
  is omitted. "Advisory-lane only — never read or written under `GITHUB_ACTIONS`" is
  `tools/mutation-sweep.sh:465-468`. "Three selftests that wrote to a fixed `/tmp` path now
  write under their own mktemp tree" is the three-file diff under
  `plugins/dev-pipeline/skills/run/tools/`.
- **The rewrite is provably patch-preserving.** `git diff main...8a653ce | git patch-id
  --stable` — the *pre*-rewrite reviewed head — is `5a65320522faf01cff1b33fbd51914dcfea89f99`,
  byte-for-byte the `reviewed_patch_id` round 1 recorded, and the post-rewrite `5274de0`
  hashes to the same value. Only the commit messages moved. That is what round 1 said the
  remedy had to be, and it is what happened.

### Round 1's third point — the cache key — RESOLVED and killable

`CACHE_ENV_TAG` (`tools/mutation-sweep.sh:491`) now carries `$EARLY_EXIT|$FAIL_PATTERN`.
`EARLY_EXIT` and `FAIL_PATTERN` are assigned at `:199-200`, well above the tag, so neither
field can be empty at key time. Case `(af)` gained **two** assertions rather than one, and I
probed each field separately by editing it out of the tag and re-running the suite:

| Probe | Result |
| --- | --- |
| drop `$FAIL_PATTERN` from the tag | `FAIL (af) a MUTATION_SWEEP_FAIL_PATTERN change hit the cache (computed=0)` — that assertion and **only** it |
| drop `$EARLY_EXIT` from the tag | `FAIL (af) a MUTATION_SWEEP_EARLY_EXIT change hit the cache (computed=0)` — that assertion and **only** it |

Restored by the inverse edit, not `git checkout`; `git status --porcelain` is empty afterwards,
so the tree I reviewed is the tree the record names. One combined assertion would have passed
with either field present — this is the shape that makes the new key field guarded rather than
merely written.

The adjacent point round 1 raised without requesting is also addressed: `MUTATION_SWEEP_JOBS`
stays out of the key, and its persistence residual is now stated in `docs/testing.md:226-232`
*and* in the code comment at `:486-490`, in both cases naming `MUTATION_SWEEP_CACHE=0` as the
escape.

### 1 — Warning: the PR body's verification count is wrong

`mutation-sweep-selftest.sh` gained seven cases on this branch —
`git diff origin/main...HEAD -- tools/mutation-sweep-selftest.sh | grep -cE '^\+echo "\('`
returns 7, and they are `(ac)` pool equivalence, `(ad)` verdict cache, `(ae)` suite bytes in
the key, `(af)` cache fail-safe, `(ag)` early exit, `(ah)` sandbox disk, `(ai)` enforcing-lane
inertness. Round 1's PR body said "seven cases" and was right; the fix round rewrote it to
"nine" by counting the two new `(af)` assertions as cases.

This is a **warning, not a blocker, and the difference from round 1's blocker is the point.**
Round 1 blocked on three facts together: the trailer *ships verbatim to consumers* through
`derive-release.sh`, no lane can red on it, and a corrective block would render *alongside* the
false one rather than replace it. This claim has only the middle fact. The PR body is not an
input to `derive-release.sh` — that script reads commit trailers — so nothing published depends
on it, and editing a PR body changes no line of the patch, so the remedy costs neither a round
nor a re-review. The substantive half of the same sentence is true and I reproduced it: 63
selftests, every one exit 0.

### 2 — Warning (carried): AC-11's widening is still branch-local

`scope-completeness-reviewer` returned `request-changes` at confidence 92 on exactly the
finding it raised in round 1: issue #381's AC-11 confines the diff to `tools/` and `docs/`, and
three files under `plugins/dev-pipeline/skills/run/tools/` are in it. **I am overriding it to a
warning again, and stating the override rather than leaving it implied** — the grounds are
unchanged and I re-checked them rather than inheriting them:

1. In this lane the committed lean spec is the definition of done, and its AC-11
   (`docs/plans/second-shift-381-lean.md:71-73`) admits exactly those three files.
2. The widening is **D-5** in the pre-flight receipt, provenance `user-answered`, whose mtime
   predates both the spec commit and the code change — not a self-serving amendment.
3. #381's own AC-7 offers "either fixed or pinned serial". The collision was a real conflict
   between two of the issue's ACs, and D-5 resolved it toward the option AC-7 names first,
   which is also the stronger one: a fixed suite cannot race, a serial pin only hides it.

**What changed since round 1, and why I am not escalating.** Round 1's named remedy was to
record the widening *on the issue*. The build round declined that specific remedy and folded it
into the closing comment instead, citing the lane's two-tracker-writes rule. I checked that the
rule is real rather than convenient: `run-lean/SKILL.md:50` — "**Two tracker writes per clean
run**, github only: the claim comment and the closing comment (an abort adds one)." A
reviewer's suggested remedy is not a licence to break a non-negotiable lane rule, and the
substitution was stated in the PR header rather than performed silently. Escalating a round-1
warning to a round-2 blocker on a point the build addressed within the rules would be the
review moving the goalposts.

**What survives, unchanged:** until that closing comment is posted, a reader of #381 hits the
contradiction, and `.claude/pipeline-state/` is gitignored, so the only committed record of the
human decision is a branch artifact. That is a residual of *when* the record lands, not of
whether it was decided.

## Coverage

`maintainability-reviewer` went **dark** on the full `origin/main...HEAD` range — no text on
either attempt, the turn-budget death this repo already tracks. I re-dispatched it on the same
substrate over the round-2 delta (`5274de0...HEAD`), where it returned `approve` with zero
findings. So the delta is covered; the pre-delta patch is covered by round 1's own
maintainability pass on the identical bytes (`reviewed_patch_id 5a65320`, proven above to be
this branch's patch modulo commit messages). No maintainability domain is unreviewed, but the
round-2 pass over the *whole* diff is inherited rather than re-run, and that is stated rather
than papered over.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 cached key; unchanged tree runs zero paired suites | satisfied | `cache_key()` `:502-504`; case `(ad)` asserts `computed==0` and diffs the report. The cache probe running *before* the precheck is what makes "zero" literal. |
| AC-2 suite edit invalidates its guard's verdicts | satisfied | Case `(ae)`, which asserts `guard.sh` is byte-identical across both runs — it isolates the suite key rather than observing an incidental miss. |
| AC-3 concurrent, own sandbox, pool `min(cores-2, …)` | satisfied | `:166-174` (pool sizing, cap 8), `pool_worker`/`run_pool` `:1131-1160`. |
| AC-4 parallel ≡ serial | satisfied | Case `(ac)` diffs the `JOBS=1` / `JOBS=4` reports **after** asserting the parallel run really overlapped; measured rows A–E are byte-identical report TSVs, including against the old harness. |
| AC-5 first-`FAIL:` kill, scores as a full run, first- and last-case | satisfied | `run_killer` `:1072-1079` returns 125 on the first match; `(ag/first)`, `(ag/last)` compare early-exit on/off and count killer completions; `(ag/noisy)` drives D-3's unrunnable-pair assertion. |
| AC-6 cold / partial-hit / full-hit measured | satisfied | Spec rows A–F, each read off the run's own `timing:` line; the invalid first F attempt is recorded rather than dropped. |
| AC-7 hostile suites fixed or pinned | satisfied | All three `/tmp` writers rewritten to per-instance paths; case `(k)`'s corpus lint stops a fourth. |
| AC-8 bounded, outside repo, no env survival, corrupt → real run | satisfied | Case `(af)`: malformed entry, trailing-junk entry, killer-bound change, **and now both kill-criterion fields** — the two I probed above. Plus the D-7 self-hash and the per-repo subdirectory (`:275`). |
| AC-9 sandbox disk bounded and reclaimed | satisfied | Case `(ah)`; `KILLER_TMPDIR` is removed unconditionally on the reap paths (`:1040-1043`). |
| AC-10 `docs/testing.md` states key / invalidation / authority | satisfied | `:200-232`, now including both kill-criterion fields in the key block and the `MUTATION_SWEEP_JOBS` residual as its own paragraph. |
| AC-11 diff scope | satisfied | Exactly the seven files the spec's Files-in-scope names, plus the two `docs/plans/` artifacts. Override stated above. |
| AC-12 `Changelog:` trailer present | satisfied | Present **and** true — which is what round 1's blocker was about; AC-12's own letter only asserts presence. |

## Verification run for this review

From the PR head (`5312772`), `env -u CLAUDE_CODE_SESSION_ID`, **without** `SKIP_STRESS`:

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — exit 0
- `jq empty` over every `*.json` — exit 0
- `scripts/check-lockstep-pairs.sh` — 13 pairs, 0 failed
- all **63** selftests — every one exit 0, no reds
- the two cache-key probes above, each reproduced and reverted by the inverse edit

CI on this exact head (`5312772`) is green on `lint-and-selftests` and on the macOS **stock
bash 3.2** lane. `pr-gates` fails, and fails in the shape that proves the evidence chain is
being read rather than broken: `✓ spec`, `✓ claim`, `✓ authorship`, then two restatements of
`verdict=needs-work` and `✗ 2 evidence artifact(s) missing`. This record is what clears it.

## Reviewer verdicts

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (4 suppressed, all pre-existing or non-attacker-reachable) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 0 |
| Maintainability | Dark on full range; Pass on the delta re-dispatch | 0 |
| Scope Completeness | Fail (overridden — see finding 2) | 1 @ conf 92 |

## Suppressed

- `tools/mutation-sweep.sh:491` (conf ~35) — `CACHE_ENV_TAG` joins fields with `|`, and a
  custom `MUTATION_SWEEP_FAIL_PATTERN` may legitimately contain `|` (a BRE alternation is
  written `\|`). A field-boundary collision would need a second knob to contain a compensating
  `|` as well, and the same ambiguity already exists for `SKIP_STRESS` and the killer bounds in
  the pre-#381 tag. Not a new gap; not worth a delimiter change.
- Security's four suppressed findings are all pre-existing shapes present on `origin/main`
  (sandbox `mktemp -d`/`rmdir`/`git worktree add` race, `reap_group`'s group signal, cache
  read-back, `MUTATION_SWEEP_CACHE_DIR` eviction) — none introduced here.

## Not this PR

`git worktree list` still shows a leaked `mutation-sweep-sandbox.*` registration at a commit
predating this branch — the old harness's leak, which case `(ah)` is the guard against
recurring. A `git worktree prune` on the operator's box, not a change here. Unchanged from
round 1.
