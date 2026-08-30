# lean review verdict — #674

verdict=needs-work
run_id: review-674-1
session_id: 6f4fb83b-ab09-4ef6-98a6-89835469a9a5
rounds: 1
pr: #703
reviewed_head: 1b090acb6f12442f9e9c7c8871a6862fcb955371
reviewed_patch_id: abb41944319f3a2dff072efa92bb0421ac2ca46a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — #674 / PR 703 — needs-work

Range: `808aa29..1b090ac` (full branch diff; round 1, nothing to inherit). Reviewed from the
lane worktree with `claude/second-shift-674` checked out, head matching `origin`.

The slice is well built and the design decision at its centre is the right one. D-1 rejects the
`LOCKSTEP` marker for the correct reason — a lockstep holds two *prose* copies identical and can
never notice a `case` arm gaining `lint`, so it would have been a wrong-axis guard that passes
forever. The derivation is real, the fail-closed arms are genuinely closed (I read the awk and
each of AC-3's four shapes reds), and the tier-map fix under AC-7 addresses why this class went
unguarded rather than only the sentence that rotted.

It does not merge as it stands: `mutation-sweep-pr` is RED at this head on lines this PR wrote.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | **blocker** | `scripts/check-lane-class-doc.sh:156,159` | `mutation-sweep-pr` is RED at the reviewed head — two baseline-absent survivors, both on lines this branch wrote. Reproduced locally. |
| B2 | **blocker** | `scripts/check-lane-class-doc-selftest.sh:7` | "the sentence it guards **spent a year** looking true" is false. PR #660 merged 2026-08-24; today is 2026-08-30 — six days. |
| W1 | warning | `scripts/check-lane-class-doc.sh:159,166,196,204` | Four fail-closed `bad(...)` arms are driven to red by no selftest case. Independently found by `test-coverage-reviewer` (85) and `unit-test-mutation-reviewer` (85). |

### B1 — `mutation-sweep-pr` is red, and the remedy belongs in this PR

CI run [33315328109](https://github.com/manoldonev/second-shift/actions/runs/33315328109), job
`mutation-sweep-pr`, head `1b090ac`, conclusion **failure**:

```
[mutation-sweep] swept scripts/check-lane-class-doc.sh — applied=10 killed=8 survived=2
[mutation-sweep] RED: baseline-absent survivor: scripts/check-lane-class-doc.sh::default::b06aa1378f8f
[mutation-sweep] RED: baseline-absent survivor: scripts/check-lane-class-doc.sh::default::7c675bd3fdb5
```

`bash tools/mutation-sweep.sh --emit-site-keys` resolves both ids to the `default` operator's
ordinals 1 and 2 — the two lines that carry a `${…:-…}` expansion *and* an arithmetic comparison:

- `:156` `if [[ "${SITES:-0}" -eq 0 ]]; then`
- `:159` `if [[ "${FIXEDSITES:-0}" -ne 1 ]]; then`

I applied each mutation by hand in this checkout and ran the paired selftest: **exit 0 both
times.** The survivors are real, and they are *equivalent mutants* — in bash arithmetic context
`__MUTANT_DEFAULT__` is an unset variable name, so it evaluates to `0`, exactly what the original
default supplies:

```
$ X=""; [[ "${X:-__MUTANT_DEFAULT__}" -eq 0 ]] && echo TRUE   # TRUE
$ X=""; [[ "${X:-0}" -eq 0 ]] && echo TRUE                    # TRUE
```

So this is not a hole in the 13 cases — no case *could* kill these. That does not make the red go
away, and this repo has already written down what to do about it. `docs/testing.md:1474`:

> **`baseline-absent survivor: <guard>::<operator>::<key>`** … Copy each named id into
> `tools/mutation-baseline.tsv` as `<survivor_id><TAB><note>` and commit it **in the PR that
> wrote the site**.

That obligation lands on this PR by name, and the branch does not discharge it. Two remedies, both
acceptable:

1. Add the two rows to `tools/mutation-baseline.tsv`, each with a note saying *why* it is
   unkillable (the arithmetic-context equivalence above), not merely that it survived. The runbook
   prescribes this and the failing log already names both ids.
2. Drop the `:-0` defaults — `[[ "$SITES" -eq 0 ]]`, `[[ "$FIXEDSITES" -ne 1 ]]` — which removes
   the sites from enumeration entirely. Behaviourally identical (`[[ "" -eq 0 ]]` is already true),
   and it deletes dead syntax rather than recording a permanent exception for it. If you take this
   one, `${FIXEDSITES:-0}` in the message string at `:160` is a third site of the same operator,
   currently past the k=2 budget — take it too, or a later budget change reds this lane again.

`mutation-sweep-pr` is a correctness lane, not a policy one: it is evidence about the code, and
`review-lean`'s merge-boundary carve-out names it alongside `lint-and-selftests` and `selftests`
as the lanes whose red stays a blocker. `pr-gates` is also red at 7s; that one is the expected
lean-chain refusal pending this verdict and is **recorded, not a blocker**.

### B2 — a fabricated duration, in the file that states the doctrine

`scripts/check-lane-class-doc-selftest.sh:7`:

> A guard never observed failing is indistinguishable from one that cannot fail — and for this
> subject that is the whole point, since the sentence it guards **spent a year** looking true.

`gh pr view 660 --json mergedAt` → `2026-08-24T19:16:17Z`. Today is 2026-08-30. The sentence stood
for **six days**.

The branch already knows this. The same claim was drafted into `docs/config-schema.md` and the
`ci.yml` comment and corrected in both before commit — each now says "three review rounds and its
full panel", which I verified and which is accurate (`docs/plans/second-shift-642-lean-verdict.md`
records `rounds: 3`, and round 2's own record says "Six selected, six returned, none dark — the
first full panel in three rounds"). The third copy was missed.

A rhetorical intensifier is still an assertion, and this one sits in the header that states the
guard class other authors will copy. On a branch whose entire thesis is that a prose claim about
code must be derived rather than asserted, shipping a false measurement in its own doctrine
comment is not a nit. Replace it with the measured figure or drop the duration clause.

### W1 — four fail-closed arms no case drives

Two reviewers converged here independently at confidence 85. Verified against the cases:

| Arm | Message | Why no case reaches it |
| --- | --- | --- |
| `:159` | `expected exactly one \`for key in …\` fixed-key loop, found N` | every fixture carries exactly one loop; none carries zero or two |
| `:166` | `expected exactly one LANE-CLASS-BEGIN and one LANE-CLASS-END` | case (j) deletes only `$ME`; the `BEGIN_N -ne 1` half of the `||` is never driven |
| `:196` | `the LANE-CLASS region has no lane rows` | no fixture has a well-delimited but empty region |
| `:204` | `a lane row names no backticked lane` | no fixture supplies such a row |

This is not an unmet AC — AC-5 binds the refusals enumerated in AC-2, AC-3 and AC-4, and every one
of those has a message-asserting red case. These four are arms the guard added beyond the spec.

I am also not claiming the guard is unsafe: for `:166` and `:196` a doc missing its BEGIN marker
still reds, just through the neighbouring arm with the wrong message — and this selftest's own
header is the thing that says a guard reding for the wrong reason "will red on the wrong day".
The one case with a live consequence is a **doubled** `LANE-CLASS-BEGIN` with a single `END`: drop
the `"$BEGIN_N" -ne 1 ||` clause and the region parse still yields the right rows, so the guard
goes green over a malformed doc.

Worth closing while the fix round is open, since B1 reopens the file anyway. If any of the four is
deliberately unguarded, say so in the guard header the way D-4's limit is stated, rather than
leaving it silent.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — doc claim matches the measured caller set | **satisfied** | The region carries rows for all five families; exactly one `**reserved**`, and it is `typecheck`. `git grep -n lane_failure_class` in the gate returns the definition at `:4115` and one call at `:4200`, the `typecheck)` arm. |
| AC-2 — guard derives the set and reds on drift both ways | **satisfied** | `MISSING_IN_DOC` / `MISSING_IN_CODE` are two separate `comm` arms with distinct messages; selftest (c) and (d) drive each and assert the message. Guard green on the live tree, exit 0. |
| AC-3 — fails closed on an unmodelled dispatch | **satisfied** | Read the awk: a non-`$key` `case` subject → `!subject`; a call in no `case` or not on an arm-label line → `!shape`; a glob arm → `!glob`; `sites == 0` → its own red. Cases (e)(f)(g)(h) drive all four and assert the messages. The narrow modelled shape (`case "$key"`, arm label and call on one line) is what makes an unquoted `case $key in` red rather than derive silently. |
| AC-4 — completeness arm | **satisfied** | `FIXED_KEYS` from the `for key in lint typecheck test` loop, `UNDOCUMENTED` comm against the doc region; case (i) drives it. |
| AC-5 — the guard is exercised | **satisfied** | 13 cases, green here (`13 passed, 0 failed`). Every refusal named in AC-2/3/4 has a red case asserting the message. Scored on AC-5's own words; W1 records the arms outside that enumeration. |
| AC-6 — runs at the merge boundary | **satisfied** | `.github/workflows/ci.yml:148-151`, `lint-and-selftests` job, immediately after `check-lockstep-pairs.sh`. That job passed at this head (4m34s), so the step ran green in CI, not only locally. |
| AC-7 — the route is written down | **satisfied** | `docs/testing.md:521` Contract-tier row names the guard; `### When the second copy is not prose: derive it (#674)` states both properties; `.claude/skills/writing-tests/SKILL.md:45` carries the matching tier-map row, and the dead `prose in a markdown file → nothing` row is narrowed to "that asserts nothing checkable". |
| AC-8 — `Changelog:` and `Guard-mass:` trailers | **satisfied** | `Changelog: none.` with no indented prose after it (which would render into CHANGELOG.md anyway); `Guard-mass: +2 files`. `lint-and-selftests` green covers both checks. |

No AC is unsatisfied. The verdict is `needs-work` on B1 and B2, which is the ordinary case —
a finding is not an unmet AC.

## CI at this head

| Job | Conclusion | Read |
| --- | --- | --- |
| `lint-and-selftests` | pass (4m34s) | shellcheck, the full selftest sweep and the new CI step, green |
| `selftests (macos, bash 3.2)` | pass (5m12s) | the guard runs clean under stock `/bin/bash` 3.2 |
| `mutation-sweep-pr` | **fail (17s)** | B1 |
| `pr-gates` | fail (7s) | expected: the lean-chain step requires `verdict=approve`. Recorded, not a blocker. |

## Panel

Seven selected, **seven returned, zero dark**. `security`, `performance`, `maintainability`,
`complexity`, `scope-completeness` returned zero findings; `test-coverage` and
`unit-test-mutation` returned the W1 cluster. No changed path matched
`stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), so `a11y-reviewer` and the
design-fidelity dimension were not routed.

Neither blocker came from the panel. B1 came from reading the PR's CI, B2 from checking a stated
duration against `gh pr view`.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (2 suppressed <80) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 1 minor (85) |
| Unit Test Mutation | Pass | 2 major + 1 minor (80–85) |
| Scope Completeness | Pass | 0 |

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, the repo config sets no
`design.provider`, and the diff carries no web-component surface.
