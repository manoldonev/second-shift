# lean review verdict — #413

verdict=approve
run_id: review-413-2
session_id: 49a66c8f-8661-42cb-9e1b-658a7868ef47
rounds: 2
pr: #438
reviewed_head: 9250a88e2e55ff7942ba8d0869614099d2f39181
reviewed_patch_id: 1d8f9a2e8ece087a042258d2540758ed8b11baeb
inherited_patch_id: e2a480d6b5da0e3e48bbe3eafface815c9953832
inherited_from_verdict: 0b7b5365a0de2e31360633e8bcf15a277175d881
fidelity: not-applicable
model: unknown

Round 2, inheriting the coverage of round 1's record (`review-413-1`, patch `e2a480d6b5da`).
`bash G delta 413` printed `0b7b536..HEAD` — 2 commits, 8 files, +168/−30 — and that is the range
this round READ. Every `AC-n` is scored below against the whole spec regardless.

**Verdict: approve.** Both round-1 blockers are closed, all three warnings and the one suggestion
with them. Each fix was verified by execution from this checkout and by a kill-probe that redded
exactly its target case; the full 67-suite sweep is green with `SKIP_STRESS` and
`CLAUDE_CODE_SESSION_ID` both unset. One new warning, no blockers.

## Round-1 blockers — both closed

### B-1 — the sole applicability arm now fails CLOSED

`changed_files()`'s two `return 0` fall-throughs are `envfail`s, and the stale comment that
justified them is gone. Reproduced at this head with round 1's own commands:

```
# control
$ PIPELINE_BRANCH_PREFIX=claude/second-shift- PR_HEAD_REF=claude/second-shift-413 \
  PR_HEAD_SHA=9250a88 PR_BASE_REF=main PR_BODY='Closes #413' bash lean-evidence.sh classify
applicable=1 / trigger=lean-artifact (docs/plans/second-shift-413-lean.md)      rc=0

$ env -u PR_BASE_REF …                                                          rc=2
[lean-evidence] PR_BASE_REF is unset or empty — the PR's changed-file list is the SOLE …
$ PR_BASE_REF=develop-does-not-exist …                                          rc=2
[lean-evidence] cannot resolve the merge-base of origin/develop-does-not-exist …
```

And through both merge boundaries — the arm round 1 showed passing at rc=0:

```
$ env -u PR_BASE_REF … bash scripts/check-lean-chain.sh --comments-file /dev/null      rc=2
$ env -u PR_BASE_REF … bash scripts/check-pipeline-chain.sh --comments-file /dev/null  rc=2
[pipeline-chain] the lean evidence payload failed to classify this PR — refusing to guess
```

**The call-site half is the part that would have been easy to miss, and it is real.** Probe B
reverted only the consumption (`files="$(changed_files)"` + `<<<` back to `< <(changed_files)`),
leaving both `envfail`s intact: `(bb2b)` and `(bb2c)` red with the diagnostic PRINTED and
`rc=0`, `applicable=` emitted anyway — the subshell swallows the exit exactly as the new comment
claims. The fix is load-bearing, not defensive prose.

### B-2 — AC-11's stream, reconciled toward the mechanism

The notice is on stderr and `classify`'s stdout stays a pure `key=value` block; verified by
running both streams separately at this head. AC-11 is amended to the mechanism, with an
`## Amendments` section recording every AC that moved and why. This is the remedy round 1 named
("the implementation is the correct half; the spec line is the stale half"), not a retrofit —
see the amendment audit below.

## Amendment audit — no obligation was weakened

Diffed the AC set head-to-head (`d6b96d4` → HEAD). **Nothing removed; AC-17 added.**

| AC | Move | Net |
| --- | --- | --- |
| AC-17 | new | **Adds** an obligation (the fail-closed scan) and meets it. |
| AC-11 | stdout → stderr | Reconciles a spec gloss to the mechanism, per B-2's stated remedy. Its other two clauses are untouched. |
| AC-8 | "no second copy exists" → "not duplicated as an *unrecorded* coupling" | **Adds** the DROPPED-note obligation (round 1's W-3) while keeping every enumerated obligation verbatim; "no new row" tightens to "no new **live** row". |
| AC-15 | two sites added | **Adds** the `ci.yml` comment and the retro recipe's empty-`BR` refusal. |

## Warnings

- **W-4 (new) — the DROPPED note's stated rationale is wrong in three particulars.** The note is
  required and present (AC-8's letter is met), but its *reasoning* does not survive reading:
  - *"the two sides share no literal to anchor"* — both sides hardcode `-lean.md` today:
    `lean-evidence.sh:206` `LEAN_SPEC_SUFFIX='-lean.md'` and `retro-corpus.sh:194`
    `local suffix="-lean.md"`. The note's closing line — *"Revisit if either side ever grows a
    shared literal — most plausibly if the `-lean.md` suffix is hoisted into the config schema"*
    — describes as a future trigger a condition that already holds.
  - *"shell `case` patterns over a `find` walk"* — the coupling the note names is
    `classify() <-> open-prs`, and `classify()` walks the PR's changed-file list, not a `find`
    tree. The `find` walk is `find_artifact()`, a different function on a different path.
  - *"the suffix is a variable on one side and inlined in a pattern on the other"* — it is a
    variable interpolated into a pattern on **both** sides.

  The DROP itself still stands: `check-lockstep-pairs.sh` supports only `verbatim` and
  `subset-of`, and neither can bind `LEAN_SPEC_SUFFIX='-lean.md'` to `local suffix="-lean.md"`.
  So the decision is right and the record of it is inaccurate — which is the specific failure a
  DROPPED note exists to prevent. Same class as #363's manifest-paragraph defects; scored as a
  warning, not a blocker, because AC-8 asks for the note and the note is there.

## Suggestions

- `scripts/check-lean-chain.sh:360` propagates the payload's rc with `|| exit $?` and prints no
  `[lean-chain]` line of its own, so the operator sees only the payload's stderr with no
  indication of which gate was running. `check-pipeline-chain.sh:139` prints that context line.
  Cosmetic, and outside every AC.

## Dismissed

`scope-completeness-reviewer` returned one blocker (confidence 88): *"check-pipeline-chain.sh's
body-key derivation still diverges from lean-evidence.sh's."* This is round 1's second dismissed
finding, re-raised verbatim, and it is dismissed on the same grounds plus two new ones:

- **Ledger `D-21` disposes of it** (`.claude/pipeline-state/413-ledger.md` rev 2, posted to the
  issue as a comment): *"`check-pipeline-chain.sh` keeps its own first-match body derivation
  unchanged — its mismatch arm is fail-closed, so a phantom body key there produces a red, not a
  vacuous green."* Re-verified independently at this head: `check-pipeline-chain.sh:170-173` hard
  `fail`s on `KEY_BODY != KEY_BRANCH`, and `:164-166` hard `fail`s when a pipeline-authored
  branch carries no body key at all. A divergence cannot produce a silent exemption.
- **The file is not in this round's delta.** `check-pipeline-chain.sh` is byte-identical to
  `0b7b536`; nothing about it changed since round 1 adjudicated it.
- The reviewer concedes both the mitigation and that the issue's wording (*"by first match"*) is
  partly stale, since `main` already carries the `Closes`-over-`Part of` precedence.

Recorded as a disagreement, not a suppression: the finding is accurate about the code and lacks
the ledger. `D-21`'s provenance is `codebase-derived`/`fact` rather than `user-answered`, so it
is noted here as a verified fact rather than an authority claim — the verification above is what
carries the dismissal.

## Independent verification performed in this round

Everything below was run from a checkout of the reviewed head. Kill-probes ran in an isolated
worktree at the same commit, so the reviewed tree was never mutated.

| Check | Result |
| --- | --- |
| Full `*-selftest.sh` sweep, 67 suites, `-P 4`, `env -u CLAUDE_CODE_SESSION_ID`, `SKIP_STRESS` unset | **exit 0.** Zero anchored `FAIL:`/`✗` outside `install-topology`'s two allow-listed `known:` rows |
| `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`; `jq empty` over every `*.json` | clean / clean |
| `scripts/check-lockstep-pairs.sh` | 22 pairs, 0 failed |
| **Probe A** — restore `return 0` on an unset `PR_BASE_REF` | `lean-evidence-selftest` reds `(bb2b)` alone: *"expected rc=2 and no applicable= line, got 0: applicable=0"*. KILLED |
| **Probe B** — keep both `envfail`s, revert only to `< <(changed_files)` | `(bb2b)` **and** `(bb2c)` red, each with the diagnostic printed and `rc=0` — the swallowed-exit shape. KILLED, and it proves the call-site fix is the load-bearing half |
| **Probe C** — `check-pipeline-chain.sh`'s delegation `\|\| envfail` → `\|\| true` | `check-pipeline-chain-selftest` reds exactly the new composed case. KILLED. (It still exits 2 via the empty-`LEAN_APPLICABLE` guard — defense in depth behind the primary refusal) |
| **Probe D** — `branch-prefix.sh --help` range `2,38p` → `2,36p` (round 1's suggestion, verbatim) | `branch-prefix-selftest (g)` reds. KILLED — the two-line-short defect no longer passes |
| AC-11 stream, both streams captured separately | stdout: 4 pure `key=value` lines, rc=0. stderr: the retirement notice only |
| AC-13 / AC-14 — `LEAN_BRANCH_PREFIX` at HEAD | Zero occurrences in `.github/workflows/ci.yml` or under `templates/`; the survivors are the payload's own deprecation arm, its selftest, and prose recording the retirement |
| Manifest citations checked against the suites | `lean-evidence-selftest (d)`/`(z2)` and `retro-corpus-selftest (AC-5)`/`(AC-5b)` all exist and assert what the note claims |
| Frozen files / `Changelog:` trailers | No `plugin.json`, `CHANGELOG.md` or `marketplace.json` in the branch diff; every commit carries a trailer |
| CI on this head (run 31281592320) | `lint-and-selftests` **PASS**; `pr-gates` fails on the single arm *"verdict record reads 'verdict=needs-work'"* — round 1's record, the expected pre-round-2 shape. Both chain gates classified correctly: `[pipeline-chain] lean-lane change … classified lean via lean-artifact`, `[lean-chain] applicable via lean-artifact` |
| Head unmoved | `HEAD == origin/claude/second-shift-413 == 9250a88`; `git status --porcelain` empty before and after probing |

## Reviewer panel

`review-lead` fan-out over the delta range (`0b7b536...HEAD`). Reduced lineup per the round-2
rule: performance is not re-run (round-1 Pass, no perf surface in the delta).

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (3 suppressed, all ≤ 50) |
| Maintainability | Pass | 0 (1 suppressed at 55 — the retro recipe's `else` branch leaving `PR_URL` unset; it is a doc recipe whose next line already reads *"if a PR exists"*) |
| Complexity | Pass | 0 |
| Test coverage | Pass | 0 — **and it emitted this round**, closing round 1's stated coverage gap |
| Scope completeness | Fail | 1 blocker, dismissed above |

**Not routed:** `a11y-reviewer` and the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`).
`db-reviewer`, `pipeline-reviewer`, `unit-test-mutation-reviewer` — no DB layer, no queue/worker
files, no co-located unit specs. `performance-reviewer` — deliberately not re-run, see above.
No dark reviewers this round.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, the repo's config sets no
`design.provider`, and the delta has no UI surface (shell, YAML, TSV, Markdown). The merge
boundary agrees on this head: *"spec declares no armed design render lane — design evidence not
applicable."*

## AC scoring

Inherited rows were scored in round 1 against code this delta does not touch; they are re-stated,
not re-derived. Rows marked *this round* were re-verified here.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | inherited — `LEAN_BRANCH="$BRANCH_PREFIX$BRANCH_KEY"`; the delivering branch is `claude/second-shift-413` |
| AC-2 | satisfied | inherited — key-only lowercase; `lean-gate-selftest (e3)` |
| AC-3 | satisfied | inherited — `branch-prefix.sh` rung 2; `(b1)`–`(b3)` |
| AC-4 | satisfied | inherited — rung 3 refuses with the full tally; `(d1)`–`(d3)` |
| AC-5 | satisfied | inherited — one `resolve_branch_prefix()`; `retro-corpus-selftest (AC-5d)`/`(AC-5e)` |
| AC-6 | satisfied | *this round* — real CI on this head classifies via `lean-artifact`; the `ci.yml` comment that contradicted it is corrected |
| AC-7 | satisfied | *this round* — **now proven at the composed boundary**: the delegation exits 2 on an unreadable diff (executed, and probe C reds the new case). AC-7's *"an environment error, never a silent exemption"* was previously true only of a missing payload |
| AC-8 | satisfied | *this round* — live row + both marker blocks gone, same-named DROPPED note rewritten, the `retro-corpus.sh` re-statement now carries its own DROPPED note, no new live row, 22 pairs 0 failed. See **W-4** on the note's rationale |
| AC-9 | satisfied | inherited — replayed against #420's API data in round 1 |
| AC-10 | satisfied | inherited — arm (a) returns before the body scan; `(z2)` kills a body-key-first mutant |
| AC-11 | satisfied | *this round* — notice on **stderr**, stdout pure `key=value`, never an `envfail`; `(f)` + `(bb1b)`. Scored against the amended letter, which the amendment audit shows is a reconciliation and not a retrofit |
| AC-12 | satisfied | inherited — `(AC-5)`, `(AC-5b)`, `(AC-5c)` |
| AC-13 | satisfied | *this round* — no `LEAN_BRANCH_PREFIX` in `ci.yml`; `PR_BASE_REF`/`PR_HEAD_SHA` on both gate steps |
| AC-14 | satisfied | *this round* — zero `LEAN_BRANCH_PREFIX` under `templates/`; the consumer template passes `PR_BASE_REF` under `fetch-depth: 0`, which the new refusal now requires |
| AC-15 | satisfied | *this round* — both added sites land: the `ci.yml` step comment is rewritten to the artifact discriminator, and the retro recipe refuses on an empty `BR` instead of letting `gh pr list --head ""` answer with the newest open PR |
| AC-16 | satisfied | *this round* — the new cases sit at the right tiers: `(bb2a)`–`(bb2c)` per-tool at the payload with `(bb2a)` as the non-vacuity side, and the composed refusal at `check-pipeline-chain-selftest`, which is where AC-7's letter actually binds |
| AC-17 | satisfied | *this round* — both conditions are `envfail`s, the refusal survives its call site, and both delegating gates propagate rc=2. Executed three ways and killed by two independent probes |

**17 satisfied, 0 unsatisfied, 0 undeterminable.**

## Strengths

- **The fix went one level deeper than the finding.** Round 1 named the two `return 0`s. Closing
  them alone would have produced a gate that printed a refusal and still exited 0, because
  `< <(changed_files)` swallows the exit — a fail-open wearing the fix's own diagnostic. Probe B
  is the proof that the extra step was necessary, not tidiness.
- **The new cases assert the failure mode, not the symptom.** `(bb2b)`/`(bb2c)` require rc=2
  **and** that no `applicable=` line was emitted — the second clause is what distinguishes a real
  refusal from the swallowed-subshell shape, and it is exactly the clause probe B trips.
- **`(bb2a)` is the non-vacuity side, and it is not decorative.** The three cases drive the live
  git path with no `--diff-files-file`, so a fixture that stopped exercising the real
  `merge-base`/`diff` calls would fail the control before the refusals could pass vacuously.
- **The three bypassing `check-pipeline-chain-selftest` cases were fixed rather than routed
  around.** Making the delegation strict broke three pre-existing cases that skipped the
  `run_chain` helper; each gained a `--diff-files-file` so it still tests the arm it was written
  for, instead of the refusal being softened to keep them green.
- **The amendments are auditable.** Every moved AC is listed with its originating finding in a
  dedicated section, so the reconciliation can be checked against round 1's record without
  reading the diff — and the audit confirms nothing was removed.
