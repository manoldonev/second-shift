# lean review verdict — #552

verdict=approve
run_id: review-552-2
session_id: d5afb92b-4fc1-4d8d-9050-3a2a4f498008
rounds: 2
pr: #561
reviewed_head: 537b6cb1402be3b2b30b3d52193ee53d3274d0ff
reviewed_patch_id: ecc2eedd1b48b65c8a6490319d6417148391c8c8
inherited_patch_id: cf0c7e27093a6ddaf2777f407b008a63e51448b5
inherited_from_verdict: d7ca4a0182ad0c8481572253ca5de2f1bc32616b
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #561 / issue #552 (shell prose ratchet)

Range read: `d7ca4a0..537b6cb` (per `lean-gate.sh delta 552`), inheriting the coverage of patch
`cf0c7e27093a` — round 1's record, read first. Three files: `pipeline-doctor.sh`,
`prose-budget-selftest.sh`, `tools/mutation-baseline.tsv`.

Panel: security, performance, maintainability, test-coverage, scope-completeness. **Five approve**,
one nit (finding 3 below). Reviewer lineup reduced per prior-round context — the round-1 blockers
were the round's own, and both are in this delta.

Verdict: **approve**. Fidelity: **not-applicable** (`Design: none`, justified — no design provider
configured and the change renders nothing outside a terminal).

## Both round-1 blockers are discharged, re-derived independently

**Blocker 1 — `tools/mutation-baseline.tsv:95` (AC-12).** Row `prose-budget.sh::detector::2` is
dropped. Re-derived rather than accepted: enumerating the `detector` operator over
`prose-budget.sh` at head gives six sites, `::2` being the new `tracked_shell_files` grep at line
163 and the site the row was granted for now at `::5`, beyond `K_BUDGET=2`. Applied that mutant in
an isolated copy of the reviewed head (the sweep's own mechanic — extract the line, apply the flip
unaddressed, splice back; `diff` shows exactly 1 changed line, `bash -n` clean):

```
clean  : [prose-budget-selftest] 31 passed, 0 failed   (rc 0)
mutant : [prose-budget-selftest] 30 passed, 1 failed   (rc 1)   → KILLED by S4
```

CI corroborates it from the other direction: `mutation-sweep-pr` at this head swept
`prose-budget.sh` **applied=9 killed=7 survived=2** and is green with the row already gone, so the
drop is proven by a real sweep and not only by my probe.

**Blocker 2 — the doctor's `n/a` short-circuit.** Fixed as sketched: the predicate now reads the
combined summary `coverage: md n/a, sh n/a`, so only a run that measured nothing on *either* path
claims that arm. The literal occurs exactly once in `pipeline-doctor.sh`, in the branch itself, so
the selftest precondition that reads it is not vacuous.

**The AC-12 obligation the fix created was handled correctly, and I checked it rather than took
it.** Editing that predicate is an in-place *content* change to `pipeline-doctor.sh::detector::2`.
Comparing the matched-**text** sequence per operator (`diff <(grep -oE -- "$match" OLD) <(grep -oE
-- "$match" NEW)`) across all six operators in `tools/mutation-operators.tsv`:

```
fail-open  IDENTICAL (0 sites)   cmp-eq  IDENTICAL (2)    cmp-z  IDENTICAL (18)
logic      IDENTICAL (41)        default IDENTICAL (13)
detector   13 → 13, one line differs — exactly the edited predicate
```

So the ordinal→site map is preserved, the row keeps its number, and re-wording its rationale
(rather than re-keying or dropping it) is right. Its "still a survivor" claim also holds: there is
no `tools/mutation-pair-map.tsv` row for either file, so `prose-budget-selftest.sh` — which *does*
grep that literal — is not in `pipeline-doctor.sh`'s kill set. Confirmed in the file.

Round-1 warnings 3 and 4 are both closed, at no round cost: the PR body's AC-7 table now labels the
files under `plugins/dev-pipeline/skills/…`, and issue #552's body carries the AC-8 amendment as an
attributed note pointing at the operator's ratification comment.

## Findings

| # | Severity | Where | Finding |
|---|---|---|---|
| 1 | warning | `prose-budget-selftest.sh:472-492` | T11b does not guard the regression it was added for, and its committed non-vacuity argument is false. The case never reads `pipeline-doctor.sh`. |
| 2 | warning | `prose-budget-selftest.sh:440-443` | The guard that *does* hold blocker 2 is an existence check, so it is blind to placement: the round-1 bug can be reintroduced with the suite fully green. One line closes it. |
| 3 | note | `prose-budget-selftest.sh:440` | Scope reviewer's nit: AC-8's "existing cases untouched" clause deviates by one line. Dismissed — compelled by the round-1 fix and outside the amended AC's scope. |

### 1 — warning. T11b is decorative for blocker 2

T11b's own comment states its non-vacuity argument:

> Restore the old `n/a — no instruction layer` predicate and this case fails on it while every
> other T11 case, and S5b, stay green.

That is not what happens. `run_tool` runs `prose-budget.sh` only (`OUT="$(cd "$repo" && bash
"$TOOL" …)"`, line 47) — T11b never reads `pipeline-doctor.sh`, so no edit to the doctor can fail
it. Probed in an isolated copy of the reviewed head, restoring the round-1 predicate verbatim:

```
  FAIL T11 precondition: doctor no longer contains 'coverage: md n/a, sh n/a'
  OK   T11b md n/a + sh measured falls through to doctor's summary arm, not its n/a arm (AC-4)
  [prose-budget-selftest] 31 passed, 1 failed
```

T11b passes. The precondition loop is what reds. The PR body's own probe table reports exactly this
diagnostic — the evidence was right there and the conclusion drawn from it was not.

What T11b actually asserts, once the doctor is out of the picture, is that a `tools/`-only repo
prints `coverage: md n/a, sh measured` plus the markdown n/a marker at rc 0. Its first clause
(`! grep -qF 'coverage: md n/a, sh n/a'`) is *entailed* by its second (`grep -qF 'coverage: md n/a,
sh measured'`): line 418 prints one coverage pair, so the two can never both hold, and clause 1 can
never be the sole failing clause. What remains is S5b's assertion with a different fixture. That
matches the build's second probe, where dropping `tools/` from `shell_roots()` failed "T11b
alongside S5 and S5b" — three cases, one fact.

Not a blocker: the behavior is fixed and the realistic regression direction *is* caught (by the
precondition). But "probe every new assertion — one still green is decorative" is this repo's rule,
and a committed comment asserting a probe result the probe contradicts is worse than no comment,
because the next reader budgets coverage against it.

### 2 — warning. The surviving guard is existence-only, so it is placement-blind

With T11b out, blocker 2 rests entirely on one line: `grep -qF -- "$DOCTOR_NA_PAT" "$DOCTOR"`. That
asserts the new literal is *somewhere in the file*, not that it is the predicate that runs first.
Probed the placement direction — reintroduce the round-1 arm ahead of it and keep the new one below:

```sh
  if grep -q 'n/a — no instruction layer' <<< "$pb"; then
    ok "prose-budget: n/a — no instruction layer in this repo (nothing to measure)"
  elif grep -q 'coverage: md n/a, sh n/a' <<< "$pb"; then
    …
```

`bash -n` clean, exact round-1 defect restored — **31 passed, 0 failed**. T11b green. Nothing in the
suite moves. And there is no mutation-side net either: `pipeline-doctor.sh::detector::2` is a
*baselined survivor*, i.e. the repo has already recorded that nothing kills a mutation of this very
line.

The cheap close is one line in the same precondition block, and it is placement-robust by
construction rather than by another fixture — the markdown-only marker is now **absent** from
`pipeline-doctor.sh` (verified: zero occurrences), so:

```sh
! grep -qF -- "$NA_PAT" "$DOCTOR" || bad "T11 precondition: doctor branches on the markdown-only n/a marker again"
```

You cannot branch on a literal that is not in the file, so this kills both probe shapes. Worth
taking with T11b's comment correction in the same edit; a fix here costs a round, so it is your call
whether it is worth one — the approve does not depend on it.

### 3 — note. AC-8's "untouched" clause, one line

`scope-completeness-reviewer` (confidence 85, verdict approve) notes that T11's precondition loop
was edited: `$NA_PAT` out, `$DOCTOR_NA_PAT` in. Correct as an observation, dismissed as a finding.
The edit is *compelled* by the round-1 fix — the doctor no longer contains `n/a — no instruction
layer`, so leaving the assertion would red the suite for asserting a property the fix deliberately
removed. AC-8's amended text scopes its guarantee to the markdown path's behavior (format, column-2
lookup, the pre-existing cases' outcomes), and T11 is a doctor-routing case whose outcome is
unchanged. Recorded so the deviation is visible rather than silent.

The same reviewer flagged, in `suppressed[]`, that the dispatch base `d7ca4a0` is the round-1 head
rather than the merge base — it re-derived from `54aec70..537b6cb` on its own. That is the delta
range working as designed, and the reviewer handled it correctly.

## Per-AC scoring

| AC | Score | Evidence |
|---|---|---|
| AC-1 | satisfied | Unchanged since round 1; not in the delta, inherited from `cf0c7e27093a`. |
| AC-2 | satisfied | Inherited. |
| AC-3 | satisfied | Inherited. |
| AC-4 | satisfied | Inherited at the tool. The delta extends it to the consumer: the doctor no longer discards a measured shell verdict, verified by reading the branch and by the fixture shape S5/S5b describe. |
| AC-5 | satisfied | Inherited. |
| AC-6 | satisfied | Inherited. |
| AC-7 | satisfied | Inherited; the body's path labels are corrected (round-1 finding 3 closed). |
| AC-8 (amended) | satisfied | 31 passed / 0 failed on the clean reviewed head. Markdown-path behavior unchanged; the one edited line is T11's doctor-literal precondition — finding 3. Amendment now also carried in the issue body (round-1 finding 4 closed). |
| AC-9 | satisfied | Every case the AC enumerates (measured, over tolerance, n/a, vacuous root, `tools/` inclusion) is present and unchanged. T11b is an addition beyond the AC, so finding 1 does not bear on this score. |
| AC-10 | satisfied | Three shell arms plus the corrected n/a arm; nightly job unchanged; still read-only. |
| AC-11 | satisfied | Marker distinctness unchanged (T11s); the combined last line is what the corrected predicate now reads. |
| AC-12 | **satisfied** | `detector::2` dropped and independently proved KILLED (probe + CI sweep); `logic::1` positionally unchanged; catalog `prose-budget-stale-gate` still single-site; the new obligation the fix created — `pipeline-doctor.sh::detector::2`'s stale rationale — is discharged by re-wording with the ordinal proved unmoved by matched-text sequence. |

Score: **12 satisfied, 0 unsatisfied, 0 undeterminable.**

## What is good here

- **The ordinal question was answered by matched-text sequence, not by site count.** Equal counts
  are compatible with a removal above plus an addition below; the build ran the per-operator diff
  and kept the row's number on that basis. That is the stronger technique, and it is the one that
  licenses re-wording instead of re-keying.
- **The kill set was checked before inferring a kill.** `prose-budget-selftest.sh` greps
  `pipeline-doctor.sh`, which reads like coverage; the build looked up `mutation-pair-map.tsv`,
  found no row, and correctly kept the survivor. The tempting inference was the wrong one.
- **The doctor fix names the shape it protects.** The comment says out loud that the broken shape is
  every consumer whose skills and agents come from the plugin cache, and that dogfooding here cannot
  see it. That is the sentence a future reader needs.

## CI at the reviewed head (`537b6cb`)

| Check | Result |
|---|---|
| `lint-and-selftests` | success |
| `selftests (macos, bash 3.2)` | success |
| `mutation-sweep-pr` | success — non-vacuous: swept `pipeline-doctor.sh` (applied=10 killed=2 survived=8) and `prose-budget.sh` (applied=9 killed=7 survived=2), no slow-suite row for either |
| `pr-gates` | failure — sole failing step is `lean chain reconciliation`, the missing-verdict arm. Expected pre-review; not a finding. |
| `release-pr-gates` | skipped |
