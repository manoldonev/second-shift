# lean review verdict — #641

verdict=needs-work
run_id: review-641-pr648-2
session_id: d91ae7c8-7c42-45aa-a900-66f2d113844b
rounds: 2
pr: #648
reviewed_head: 7e0be285cecb8bce5161b4a0324b4baf81e6ef0f
reviewed_patch_id: 144ab7cc17ee86bdc0a2ef5f49f78a1c0fb1c3b6
inherited_patch_id: d7bad4e2e770b0ae63e2b42ff0b0194bcef6f721
inherited_from_verdict: d24c766451cf27af821c7ca0869b98f3e3ae0d95
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #648 (issue #641)

Range read: `d24c766..HEAD` — one commit, `7e0be28` "close round-1 review blockers B1–B5".
Inherits the coverage of `d7bad4e2e770` (round 1, `review-641-pr648-1`, needs-work).
Reviewed head: `7e0be285cecb8bce5161b4a0324b4baf81e6ef0f`, re-checked unmoved against
`origin/claude/second-shift-641` immediately before this record.

**Verdict: needs-work.** One blocker. Four of round 1's five blockers are genuinely closed, and
two of them are closed *better* than the review asked for — B2 was fixed at the root rather than
by adding fixtures, and I probe-confirmed the result rather than taking the header's word for it.
What remains is the half of AC-7 the fix commit did not touch: the row-count clause moved from
−169 to **−168** against a "at least 170" bar, because the review's own B1 remedy cost a row. The
spec bullet the commit message points at as "the updated AC-7 self-check bullet" was never
updated and now states a number that is wrong in the *favorable* direction.

## Blockers

### B6 — AC-7 still unsatisfied on the row-count clause, and its record is stale

AC-7 verbatim: *"committed TSV row count drops by **at least 170**, and net guard/test shell mass
is lower than `origin/main` at merge."*

| clause | round 1 | round 2 | bar | |
| --- | --- | --- | --- | --- |
| (a) committed TSV data rows | −169 | **−168** | ≥ 170 | ✗ |
| (b) net guard/test shell mass | delta 0 | **−33** | < 0 | ✓ |

Clause (b) is closed — `bash scripts/check-guard-budget.sh origin/main` from the reviewed head
prints `base 50308, HEAD 50275 (delta -33)`, rc=0, with no `Guard-mass:` trailer on the branch.
That was the substantive half, and I said so in round 1; it is real work and it is done.

Clause (a) is not, and it moved the wrong way. Counting non-comment, non-blank rows across every
committed `.tsv` at both ends: `origin/main` 615 → HEAD 447 = **−168**. The delta between rounds
is exactly the `tools/mutation-baseline.tsv` row B1's remedy added — so closing one blocker
opened two rows of daylight under another. `scope-completeness-reviewer` measured this
independently and arrived at the same 615/447/−168 with the same per-file breakdown.

The record is the other half of this. `docs/plans/second-shift-641-lean.md`'s round-2 note lists
fix (5) as *"AC-7's own net-negative requirement — see the updated AC-7 self-check bullet"*, but
the bullet it points at is unchanged from round 1 and still reads:

> `scripts/check-guard-budget.sh` applied to this branch's own diff against `origin/main`
> **measures delta 0** … No `Guard-mass:` trailer is carried, per AC-7's own text.

That number is now wrong (−33, not 0), it is wrong in the direction that flatters the PR, and the
PR body repeats it (*"measures a net delta of 0"*). A record that misstates its own measurement is
the thing the merge boundary reads.

**Fix — and the cheap one is not the code.** Deleting two more register rows to reach 170 is the
ritual this slice exists to abolish; I am not asking for it. Either (i) the operator amends AC-7's
number with a stated basis — 170 was a guess at filing, and the slice's own arithmetic
(180 retired − 15 legitimately added by the unified table − 3 net elsewhere = 168) is a better
one — or (ii) two rows that are genuinely measurements-not-judgments are retired. Either way the
AC-7 self-check bullet and the PR body must be restated to the measured `−33` / `−168`.

## What round 1's blockers actually did

Each was re-derived from the diff, not accepted on the commit message.

**B1 — closed.** `mutation-sweep-pr` is green on the reviewed head
([run 32597005266](https://github.com/manoldonev/second-shift/actions/runs/32597005266/job/97089475521),
`headSha 7e0be28`): `pipeline-doctor.sh` swept, 6 survivors, all baselined. The new
`::detector::3726bf79a636` row states the re-key honestly — same site as the retired
`fd42dbc00b25`, same acceptance, and it names *why* the id moved (`, sh n/a` dropped from the
grepped literal). Round 1 offered kill-or-baseline; baseline is the option taken and the reason
holds.

**B2 — closed, and closed at the root.** The fix does not add a second arm-list fixture; it
deletes the second arm list. `classify_worktree()` and `classify_ref()` now both call one
`is_guard_path()`, so there is nothing left to drift. Probed on an isolated worktree, one arm
neutered at a time:

| mutant | suite |
| --- | --- |
| drop `*/skills/*/lean-gate.sh` | **12 passed, 1 failed** |
| drop `*-selftest.sh` | **11 passed, 2 failed** |
| drop `check-*.sh` | **8 passed, 5 failed** |
| drop `*-lint.sh` | **12 passed, 1 failed** |
| drop `run-selftests.sh` | **12 passed, 1 failed** |
| drop `mutation-sweep.sh` | **12 passed, 1 failed** |
| drop `gate-ablation.sh` | **12 passed, 1 failed** |
| `classify_ref` reads `HEAD` instead of `$1` | **12 passed, 1 failed** |

All seven arms and the ref-side read mechanism now kill; round 1's three surviving mutants are
dead. The new `ref-mechanism` case is what catches the last row — AC-1's cases all reuse a path
present on both sides, so only a base-only file exposes a broken tree read. I also checked the
refactor is behaviorally identical rather than merely plausible: old and new predicates produce
byte-identical path sets on the real tree (105 worktree, 105 at HEAD, 103 at `origin/main`).

**B3 — closed for the arm round 1 named.** Deleting the `>= threshold` filter now reds both
suites: `run-selftests-selftest: FAIL (2)` and `[sweep-bound-selftest] 1 failure(s)`, against
green baselines. `-ge` → `-le` in `run-selftests.sh` also dies (3 failures). See W1 for the arm
that is still open.

**B4 — closed.** `D-6` is in the decision ledger and the Build-time amendments section carries
the reasoning: one shared key because both consumers bind the identical 9s quantity, and two
same-valued keys reintroduce the drift the file exists to delete. That is a departure recorded,
not a clause quietly re-decided.

## Warnings

- **W1 — the `(a2)` case's success message claims a boundary it does not construct, and the
  `-ge`/`-gt` arm survives in BOTH consumers.** `tools/check-sweep-bound-selftest.sh:108` asserts
  *"the at-threshold row, timed 999s, is excluded"*, but `table()` hardcodes every fixture row at
  **99s** regardless of the threshold argument, so `at-selftest.sh` sits at 99s against a 10s bar —
  the case distinguishes clearly-under from clearly-over, never equality. Probe-confirmed: `-ge` →
  `-gt` leaves `[sweep-bound-selftest] 0 failure(s)` and `run-selftests-selftest: PASS`. The
  production table has no row at exactly 9s either, so nothing live differs today — this is a
  false coverage claim rather than a live fail-open, which is why it is a warning and not a
  blocker. It is also the exact shape round 1 blocked B2 on: a sentence asserting coverage that
  the fixture does not provide. Fix is one line — append an at-threshold row by hand the way the
  under-threshold row already is. `test-coverage-reviewer` found this independently (confidence 82,
  same reading).
- **W2 — `check-sweep-bound.sh`'s non-numeric-seconds `die` is still unguarded.** Deleting it
  leaves the suite at 0 failures; the same arm in `run-selftests.sh` is well covered (72
  failures). Round 1 listed this mutant inside B3's evidence table but its stated remedy was the
  sub-threshold row, which landed — so this is carried forward as a warning, not a re-opened
  blocker.
- **W3 — four of the lines the net-negative was bought with are reflow, not deletion.**
  `scenario-liveness-selftest.sh`'s four `# CLAUDE.md: a new gate contract …` comments were
  re-wrapped from two lines into one 146–148-character line each in a file that otherwise wraps at
  ~95, and the paraphrase drops the rule's operative qualifier (*"for every verdict path it
  touches"* → *"too"*). Four lines of "mass" removed, zero words removed. The metric this PR
  introduces counts lines, so reflow lowers it for free — worth naming inside the PR that
  introduces the metric, since P5 is about words earning their place. Not a lockstep anchor
  (`check-lockstep-pairs.sh`: 29 anchors, 0 failed), so nothing breaks. The other ~60 lines are
  genuine decorative `# ---` / `# ═══` rule deletions across nine selftests with no content loss —
  I read all of them, and `maintainability-reviewer` and `test-coverage-reviewer` independently
  confirmed the same.

## Inherited from round 1, unchanged by this delta

Round 1's four warnings (`# baseline-seconds 106` as a measurement in a file whose own new rule
forbids them; the `--seed` full-overwrite artifact; the silently widened PR-lane deferral set; the
shell prose ratchet's narrowed coverage) all still stand and none is addressed here. None was a
blocker then and none is now, but the first is the one worth a line somewhere before merge.

**AC-5's "still passes" clause** remains **undeterminable**, inherited. `scope-completeness-reviewer`
raised it again as a blocker at confidence 90, having reproduced the red at HEAD. It is the same
red round 1 confirmed pre-existing two ways, and nothing since changes that: the most recent
`nightly-guards` run is still
[32548858450](https://github.com/manoldonev/second-shift/actions/runs/32548858450) on **`b8cc982`,
this PR's own base**, already failing with the identical `(d3)` signature — there is no newer
nightly. This delta's only touch of `pipeline-doctor-selftest.sh` is ten decorative separator
lines, and the suite is green in the plain sweep at both ends. Dismissed as pre-existing, not
softened: the deletion half of AC-5 is verified done, the pass half cannot be judged against a
base that is already red.

## Strengths

- **B2 was fixed by deletion, not by addition.** The review asked for a second fixture leg; the
  build removed the duplicate implementation instead, so the property is now true by construction
  rather than by a test that could rot. That is the strictly better answer and it is the one the
  repo's own doctrine prefers.
- The `is_guard_path()` extraction is provably behavior-preserving — I checked the old and new
  predicates against each other on the real tree rather than trusting the header, and they agree
  on all 105/103 paths.
- The header sentence round 1 called out as false is not patched, it is replaced with an accurate
  one: *"is_guard_path() below, called by BOTH … so there is one arm list, not two hand-kept ones
  a fixture could exercise on only one side."*
- The `ref-mechanism` case's comment states exactly what it covers and what it does not (the
  git-ls-tree read, not the classification) — that distinction is what makes it a real case rather
  than a duplicate of the arm fixtures.
- The `D-6` departure record argues its own inversion on the merits instead of recording it
  apologetically, and it correctly scopes `mutation-sweep.sh`'s separate 5s bar out.
- The bulk comment trim is honest housekeeping: nine files, decorative rules only, no case
  explanation lost.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | `check-guard-budget-selftest.sh` **13 passed, 0 failed** at the reviewed head (12 in round 1; the `ref-mechanism` case is new). Every case still asserts the printed measured value. |
| AC-2 | **satisfied** | Was unsatisfied in round 1. All 7 `is_guard_path()` arms and `classify_ref()`'s tree read now kill under single-arm mutation (table above), on an isolated worktree. The predicate is one implementation, so "neutering any one arm fails at least one case" is true by construction. |
| AC-3 | **satisfied** | `pr-gates` step 5 *"guard budget guard"* = **success** on run 32597005266 (`headSha 7e0be28`). Steps 6 and 7 both ran; nothing `skipped`. Step 7 fails only on the expected pre-verdict `lean-chain` arm (`verdict=needs-work`), which is this record's own precondition. |
| AC-4 | **satisfied** | Files/dedup half inherited from round 1. The threshold-read arm now has an oracle in both consumers (probe table above), closing B3; B4's departure is recorded as D-6. W1's boundary gap is a coverage-claim defect, not an unread threshold. |
| AC-5 | **undeterminable** | Inherited. Deletion half verified in round 1; pass half fails against a base commit that already reds identically, and no nightly newer than `b8cc982` exists. See above. |
| AC-6 | **satisfied** | My own run from the reviewed head, env-scrubbed (`-u CLAUDE_CODE_SESSION_ID -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL -u LEAN_SPAWN_PERMISSION_MODE`): `75 discovered, 1 excluded, 74 to run` → **`74 scored, 74 run, 0 served from cache, 0 failed`**, rc=0. `prose-budget.sh`: `0 fail(s), 17 warning(s)`, rc=0. `shellcheck -e SC1091,SC2015,SC2181` clean over every file the delta touches. |
| AC-7 | **unsatisfied** | B6 — clause (b) now satisfied (`delta -33`, rc=0, no trailer); clause (a) at **−168** against "at least 170", worse by one row than round 1, and the self-check bullet still records the superseded `delta 0`. |
| AC-8 | **satisfied** | Inherited; untouched by this delta. |
| AC-9 | **satisfied** | `7e0be28` carries `Changelog: none`; the branch's feature commit carries the consumer-visible entry with `Migration: none`. |

## Panel

security ✅ · complexity ✅ · maintainability ✅ · test-coverage ✅ (1 nit — W1, found
independently) · scope-completeness ❌ (2 blockers: AC-7 upheld as B6; AC-5 dismissed as
pre-existing on the base-nightly evidence above). **Zero dark reviewers** — all five selected
returned usable results. a11y and the design-fidelity dimension were not routed: no changed path
matches the web-component surface, and the repo declares no `design.provider`. `fidelity` scores
`not-applicable` — the spec carries no armed `## Design` section.

## Round mechanics

`run_id=review-641-pr648-2`, PR-scoped so this PR's rounds stay distinguishable from the
`review-641-*` ids spent on the abandoned PR #645. Reviewed on the branch's own gate
(`lean-gate.sh` at HEAD is byte-identical to the installed 11.0.0 copy). Probes ran in a throwaway
worktree at `/private/tmp/probe-641-r2`, never the lane worktree; every mutant was verified
applied before its verdict was scored, and every file was restored and diffed clean afterwards.
