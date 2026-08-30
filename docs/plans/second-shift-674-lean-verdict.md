# lean review verdict — #674

verdict=approve
run_id: review-674-2
session_id: a7ffad3a-3993-49e8-aef4-67550db2f309
rounds: 2
pr: #703
reviewed_head: 8b4dd6f402504f09d4dd98179a8398682317d41a
reviewed_patch_id: 1537f7f54d98a4fc760647eed68601c42760da60
inherited_patch_id: abb41944319f3a2dff072efa92bb0421ac2ca46a
inherited_from_verdict: 1cee89b6aa7dd3c686c67a209b30871fa4e26bc9
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — #674 / PR 703 — approve

Range: `1cee89b..HEAD` (the round-1 fix commit `8b4dd6f` alone), inheriting the coverage of patch
`abb41944319f` recorded by round 1. Reviewed from the lane worktree with `claude/second-shift-674`
checked out, head matching `origin` and `gh pr view` (`8b4dd6f`) before and after the read.

All three round-1 findings are discharged, and the way B1 was discharged is the interesting part.
The reviewer offered two remedies and the build took the better one — delete the dead `${…:-0}`
defaults rather than baseline a permanent exception for them — then discovered that deleting a
site does not clear the lane, because the k=2 mutation budget is *ordinal*: ordinals 3 and 4
(`${verdict:-}`, `${lanes:-}`) get promoted into the swept window. Writing the case for round 1's
W1 is what actually closed it, and writing that case found a real defect nobody had reported:
`IFS=$'\t' read -r verdict lanes row` collapses runs of tabs, because tab is an IFS *whitespace*
character. On the one row shape the unnameable-row arm exists to catch — empty middle field — the
two tabs folded into one, the row text slid into `lanes`, and the arm could not fire at all. It
was not merely undriven; it was dead. That is the strongest possible vindication of the round-1
warning, and it is recorded honestly in D-10 rather than quietly fixed.

Two warnings, neither a blocker. No AC is unsatisfied.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `scripts/check-lane-class-doc.sh:213` | The `row` field extraction is asserted by no case. Setting `row=""` outright leaves all 17 cases green. Diagnostic text only — no correctness consequence. |
| W2 | warning | PR #703 body, "Verification" | Still describes round 1: "13 cases" (the head has 17) and "Full sweep at milestone 3: **64 scored**" (both CI selftest jobs score 77 at this head). |
| N1 | nit | `scripts/check-lane-class-doc-selftest.sh:200,206` | Two different cases are both labelled `(l)`. 17 cases, 16 distinct ids. |

### W1 — the offending-row text in two messages is unasserted

`row` is derived at `:213` and used only as the interpolated suffix of the two messages at `:215`
and `:218`. Both driving cases assert the fixed prefix and stop there:

```
(k)  grep -q 'carries neither \*\*reserved\*\* nor'
(p)  grep -qF 'names no backticked lane'
```

Confirmed by mutation in an isolated copy of the reviewed head — not predicted, executed:

```
row=""                       ->  [lane-class-selftest] 17 passed, 0 failed
```

So the extraction can be blanked entirely and the suite stays green. The consequence is bounded
and I want to be precise about it: exit code, red/green, and the clause that *names the cause* are
all unaffected, so the guard never passes wrongly. What degrades is the message a human reads off
a CI failure — `a lane row names no backticked lane: ` with nothing after the colon.

**This does not make AC-5 unsatisfied.** AC-5 requires each case to assert "the message that names
the cause"; the cause is named by the prefix, and `$row` is the offending subject, not the cause.
I am scoring AC-5 on its own words, not on the stronger thing I would have written.

Worth closing because the file's own siblings already set the higher bar — `(c)`, `(d)` and `(i)`
assert the interpolated value (`'does not mark them \*\*reserved\*\*.*lint'`, `'has no row for
them.*format'`). Extending `(k)` and `(p)` to match is a one-line change per case. The mutation
sweep will not catch this for you: its operator set applied 8 mutants at this head and none
touches `#*` vs `%%*`.

### W2 — the PR body's verification section is a round-1 measurement

The body claims 13 selftest cases and enumerates 12 refusals; the reviewed head has 17 cases and
15 refusals, and the round-1 fix commit is precisely what changed that. "Full sweep at milestone
3: 64 scored" is likewise the round-1 figure — both CI selftest jobs report `77 scored, 76 run,
1 served from cache, 0 failed` at `8b4dd6f`.

Recorded as a warning rather than a blocker, deliberately. The PR body is not a checked-in
artifact, no gate reads it, and it *under*-claims coverage, so it cannot mislead a reader into
thinking the change is better tested than it is. It is also fixable without a commit, so fixing it
does not void this record — do it in the merge dialog. I raise it at all because this branch's
whole thesis is that an asserted measurement rots, and the body is what the merging human reads.

## Verification of the round-1 findings

**B1 — `mutation-sweep-pr`: fixed, and the green is not vacuous.** Run
[33316714935](https://github.com/manoldonev/second-shift/actions/runs/33316714935), job
`mutation-sweep-pr`, head `8b4dd6f`, conclusion **success**. I checked the log rather than the
badge, because this lane can pass in seconds having graded nothing:

```
[mutation-sweep] pool: 2 worker(s), 8 mutant(s) to score, 0 served from cache.
[mutation-sweep] swept scripts/check-lane-class-doc.sh — applied=8 killed=8 survived=0
```

It swept. Both baseline-absent survivors are gone, and no row was added to
`tools/mutation-baseline.tsv` — correct, since remedy 2 removes the sites from enumeration rather
than recording a permanent exception. The third same-operator site the round-1 review flagged as
sitting past the k=2 budget (`${FIXEDSITES:-0}` in the message string at old `:160`) was taken
too, and the two sites the deletion *promoted* are themselves gone, replaced by the positional
split. One `default` site remains in the file (`${1:-…}` at `:65`) and it is not a survivor.

**B2 — the fabricated duration: fixed, and the replacement is true.** The header now reads
"survived PR #660's three review rounds and its full panel looking true". Re-derived rather than
inherited: `docs/plans/second-shift-642-lean-verdict.md` carries `rounds: 3` and `pr: #660`, and
the round-2 record in that file's history (`7e2781d`) says "Six selected, **six returned, none
dark** — the first full panel in three rounds." All three copies of the claim — the selftest
header, `docs/config-schema.md`, and `docs/testing.md:767` — now agree, and all three are accurate.

**W1 — the four undriven arms: fixed, and each new case is the sole killer of its arm.** Verified
by mutation in an isolated copy, one arm at a time:

| Mutant | Case that fails | Baseline |
| --- | --- | --- |
| revert to `IFS=$'\t' read -r verdict lanes row` | `(p)` — rc=0 | the r1 defect: the arm goes dead |
| drop the `"$BEGIN_N" -ne 1 \|\|` clause | `(n)` — rc=0 | the one arm with a live consequence |
| drop the `FIXEDSITES -ne 1` arm | `(m)` — rc=0 | |
| drop the `-z "$DOCROWS"` arm | `(o)` — rc=2, wrong messages | |
| drop the `-z "$lanes"` arm | `(p)` — rc=0 | |

The first row is the one that matters: it is the executed proof that the tab-collapse defect was
real and that case `(p)` is its kill criterion, not a fixture written to pass.

## AC scoring

Every AC scored against the whole spec, not only the delta.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — doc claim matches the measured caller set | **satisfied** | Re-derived by hand this round, independently of the guard: `grep -n lane_failure_class` on the gate returns the definition at `:4115` and exactly one call at `:4200`, the `typecheck)` arm. The doc region carries rows for all five families, exactly one `**reserved**`, and it is `typecheck`. |
| AC-2 — guard derives the set and reds on drift both ways | **satisfied** | `MISSING_IN_DOC` / `MISSING_IN_CODE` are separate `comm` arms with distinct messages; the arm-neutralisation probe maps `:237`→`(c)` and `:240`→`(d)`. Guard exits 0 on the live tree. |
| AC-3 — fails closed on an unmodelled dispatch | **satisfied** | `:149`→`(e)`, `:150`→`(f)`, `:151`→`(g)`, `:161`→`(h)`, each driven and message-asserted. |
| AC-4 — completeness arm | **satisfied** | `:245`→`(i)`; `FIXED_KEYS` derived from `for key in lint typecheck test` at `lean-gate.sh:4188`, and all three keys carry doc rows. The loop-count arm `:164` is now driven too, by `(m)`. |
| AC-5 — the guard is exercised, **and every refusal it implements is driven** | **satisfied** | The widened criterion was measured, not assumed. Neutralising each of the guard's 15 `bad "` refusals in turn, in an isolated copy: **0 of 15 undriven** — every one makes at least one case fail. 17 cases green in the worktree, green under stock `/bin/bash` 3.2 locally, and green in both CI selftest jobs at this head. |
| AC-6 — runs at the merge boundary | **satisfied** | `.github/workflows/ci.yml:151`. Cited from CI rather than re-run: the `lint-and-selftests` job at head `8b4dd6f` logs the step green (`[lane-class] 0 failed check(s)`). |
| AC-7 — the route is written down | **satisfied** | `docs/testing.md:521` Contract-tier row; the `### When the second copy is not prose: derive it (#674)` section states both properties; `.claude/skills/writing-tests/SKILL.md` gains the matching tier-map row and narrows the dead `prose in a markdown file → nothing` row to "that asserts nothing checkable". |
| AC-8 — `Changelog:` and `Guard-mass:` trailers | **satisfied** | `Changelog: none.` with no indented prose following it; `Guard-mass: +0 files, +4 selftest cases (17 total)`. The 17-total figure is accurate. `lint-and-selftests` green covers both checks. |

## Spec amendment

`docs/plans/second-shift-674-lean.md` was amended in the fix commit: AC-5 widened, and D-9/D-10
added. I checked this against the rule that a spec amended to match the diff is itself a blocker.
It is not that shape. The amendment is a **strengthening** — "every refusal in AC-2, AC-3 and
AC-4" ⊂ "every refusal the guard can emit" — so it gives the diff more to satisfy, not less, and
it is disclosed inline in the AC rather than quietly substituted. And I did not take the widened
criterion on its word: the 15-arm probe above is that criterion executed against the head that
claims it. D-9 and D-10 are 4-column rows with `codebase-derived` provenance, matching the other
eight.

## CI at this head

| Job | Conclusion | Read |
| --- | --- | --- |
| `lint-and-selftests` | pass (3m59s) | shellcheck, the guard step green, and `77 scored, 76 run, 1 served from cache, 0 failed` |
| `selftests (macos, bash 3.2)` | pass (6m21s) | same sweep totals under stock bash 3.2 |
| `mutation-sweep-pr` | **pass (18s)** | swept for real — `applied=8 killed=8 survived=0` |
| `pr-gates` | fail (8s) | expected: the lean-chain step requires `verdict=approve`, which this record supplies. Recorded, not a blocker. |

The new suite has no row in `tools/selftest-cache-inputs.tsv`, so it cannot be cache-skipped; the
CI log shows it running (`pass 1s scripts/check-lane-class-doc-selftest.sh`, `17 passed, 0
failed`). The CI green is evidence, not a badge.

## Panel

Seven selected, **seven returned, zero dark**. `security`, `performance`, `maintainability`,
`complexity`, `test-coverage` and `scope-completeness` returned zero findings;
`unit-test-mutation` returned the single minor finding that became W1, which I reproduced by
execution before recording it. No changed path matched `stageParams.webComponentGlobs` (unset →
`apps/web/**/*.{tsx,jsx}`), so `a11y-reviewer` and the design-fidelity dimension were not routed.

`scope-completeness-reviewer` noted that the dispatch base `1cee89b` is this branch's own round-1
head and re-measured against `808aa29...8b4dd6f` before scoring — the correct call, and its PASS
covers the whole PR rather than the delta.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (1 suppressed <80) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 0 |
| Unit Test Mutation | Pass | 1 minor (88) → W1 |
| Scope Completeness | Pass | 0 |

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, the repo config sets no
`design.provider`, and the diff carries no web-component surface.
