# lean review verdict — #597

verdict=approve
run_id: review-597-3
session_id: bab5294e-3394-4230-ba9b-28816b9322de
rounds: 3
pr: #601
reviewed_head: c6e3a0feec87c6a15dd6f90149bb7b0e834888c5
reviewed_patch_id: fa5d2710f0bdcb6095601670da9e68f79521c10a
inherited_patch_id: 56dd73a57dd7a997fda0275ece11ba1466ef1683
inherited_from_verdict: 5733432c707119746a8e8bef336ea524070b8893
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3 (`review-597-3`), inheriting rounds 1–2's coverage of patch `56dd73a57dd7`.
Read range `5733432..HEAD` — the single new commit `c6e3a0f`, touching three files:
the spec (`AC-6` amended), `lean-evidence-selftest.sh` (+23), `lean-gate-selftest.sh` (+22).
Panel dispatched over the branch's own contribution at this head (`origin/main...HEAD`) so the
composition was re-read rather than only the increment: security, performance, maintainability,
test-coverage, unit-test-mutation, scope-completeness. **6/6 returned — no dark reviewer.**

## Verdict: approve — round 2's blocker is closed, and I verified it by execution

Round 2's **B-1** was a baseline-absent surviving mutant, `lean-evidence.sh::cmp-eq::4480dc581ad4`,
at the PR's own new empty-contribution guard. It is closed on **both** copies of the lockstep
block, and the two copies needed two different kinds of evidence.

**Evidence side — closed by CI at this head.** `mutation-sweep-pr` is green on `c6e3a0f`:

```
[mutation-sweep] early exit (first 'FAIL:' line, scored as KILLED):
  plugins/dev-pipeline/skills/build-lean/lean-evidence.sh::cmp-eq::4480dc581ad4
  via plugins/dev-pipeline/skills/build-lean/lean-evidence-selftest.sh
[mutation-sweep] swept …/lean-evidence.sh — applied=11 killed=11 survived=0
```

The exact id round 2 recorded as surviving is now named as killed, by the exact suite the new
case was added to.

**Gate side — CI cannot answer, so I probed it.** The same run reads:

```
[mutation-sweep] defer …/lean-gate.sh -> nightly: slow suite (…/lean-gate-selftest.sh, 147s)
…/lean-gate.sh   deferred-to-nightly   0  0  0
```

`--emit-site-keys` confirms the twin carries the identical content key — the block is
byte-identical, so the survivor exists in both files under one id:

```
plugins/dev-pipeline/skills/build-lean/lean-evidence.sh   cmp-eq   1   4480dc581ad4
plugins/dev-pipeline/skills/build-lean/lean-gate.sh       cmp-eq   6   4480dc581ad4
```

Round 2's standing warning was that merging without a gate-side case moves the red to the nightly
rather than resolving it. Since the PR lane will never score it, I applied the mutant by hand in an
isolated worktree at `c6e3a0f` — `tools/mutation-operators.tsv`'s `cmp-eq`
(`s/-eq/__MUT__/g; s/-ne/-eq/g; s/__MUT__/-ne/g`) against `lean-gate.sh:888` — and ran the suite:

| Case | Clean tree | Under the mutant |
| --- | --- | --- |
| `(vb4)` empty-contribution fail-open | PASS | **FAIL — `expected rc=0 …, got 5`** |
| `(vb3)` unreadable-`reviewed_head` fail-open | PASS | PASS |
| `(vb4a)` fixture-shape pin | PASS | PASS |

Exactly one FAIL in 332 scored cases, and it is `(vb4)`. That is a three-way proof rather than one:
`(vb4)` kills the mutant; `(vb3)` demonstrably **cannot**, which confirms round 2's root-cause
diagnosis that both prior cases drove the same route; and the kill comes from the assertion, not
from the non-vacuity pin.

The remedy was also the *right* one. `tools/mutation-slow-suites.tsv` carries a
`lean-gate-selftest.sh 147 2026-08-14` row that is **byte-identical at `origin/main`** — pre-existing,
not chargeable here — and the PR touched nothing under `tools/`. A new row there would have deferred
the guard instead of closing it; a `mutation-baseline.tsv` row would have asserted the site
unkillable, which the probe above disproves. A case was the only true remedy, and it is what landed.

## The in-commit spec amendment — checked, and legitimate

`AC-6` was amended in the same commit as its own fix, which is the shape this repo treats as a
blocker. It is not one here, because the amendment is **purely additive and strictly stronger**.
Nothing was removed — the original sentence survives verbatim and the change appends after an
em-dash:

> … rather than inferable only from the code **— and BOTH routes into that class are driven by a
> case: a `reviewed_head` this checkout cannot read, and both sides computing with one contribution
> coming out EMPTY. The second is the one with teeth, since an unguarded reader compares the empty
> side against the full one and INVALIDATES; a guard covering only the first route reads as complete
> while the second stays dark.**

The blocker class is a spec bent so an unmet AC reads as met. This is the opposite: round 2 already
scored AC-6 satisfied under the *original* wording, so the amendment rescues nothing. It promotes a
review finding into a durable contract, and the diff then satisfies the harder version. Contracts
landing mid-run is sanctioned; narrowing one to fit the diff is not, and no narrowing occurred.

## AC scoring — all 7 satisfied

Re-scored against the whole spec at this head, per the inheritance rule.

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Both milestone-4 arms consult `contribution_state`; the boundary's `arm_freshness` consults `contribution_delta`. `(vb1)`, `(s2)`/`(s2a)`, `(lean-base-advance)`. Inherited, untouched by the delta. |
| AC-2 | satisfied | `orchestrate-lean.sh` routes `verdict_rc` rc=3/rc=2 ahead of the REVIEW spawn; `(vr1)`–`(vr3)`, non-vacuity `(vr4)`. Inherited. |
| AC-3 | satisfied | rc=1 emits `path<TAB>count<TAB>first-offending-line` into every `fail_milestone 4` / `note_violation`; `(vb2)`. Inherited. |
| AC-4 | satisfied | `contribution_lines` diffs each side against its **own** merge-base; the column-0 state machine excludes context and the `---`/`+++` headers. Inherited. |
| AC-5 | satisfied | Three tiers present and non-vacuous: `(vb0)`, `(s2a)`, `(vr4)`. Inherited. |
| AC-6 | **satisfied under the amended, stricter wording** | Both routes into the rc=2 class are now case-driven — `(s3)`/`(vb3)` the unreadable head, `(s4)`/`(vb4)` the empty contribution — and the second is confirmed by execution on both copies (CI on the evidence side, the mutant probe above on the gate side). |
| AC-7 | satisfied | `build-lean/SKILL.md:36` and `review-lean/SKILL.md:131-136` both state the base-merge case. Inherited. |

Scope-completeness re-scored the issue against the diff independently: **approve, 0 findings**.

## Warnings and suggestions — none blocking

**W-3 — the `(s4a)`/`(vb4a)` pins are two-thirds load-bearing, one-third tautological.**
Raised independently by maintainability (82), test-coverage (85) and unit-test-mutation (85 ×2),
and it matches my own reading. `s4_head` is assigned `git rev-parse refs/remotes/origin/main`, so

```sh
s4_own="$(git diff --name-only "$(git merge-base refs/remotes/origin/main "$s4_head")" "$s4_head")"
```

reduces to `diff(X, X)`, empty by construction whatever the repo state — and *also* empty if
`merge-base` fails outright, so the conjunct cannot distinguish a correct fixture from a broken one.
The other two halves carry the pin and are genuinely load-bearing: `cat-file -e "$s4_head^{commit}"`
is what separates this case from `(s3)`'s unreadable-head route, and `[ -n "$s4_new" ]` is what stops
both sides going empty and the case decaying into a `cmp`-equal pass. So the pin does its declared
job; one of its three clauses just adds nothing. Not a blocker — the mutant probe shows the kill comes
from `(vb4)`'s own assertion, and `(vb4a)` passes under the mutant, so no green is resting on the
tautological clause. Worth tightening whenever this block is next touched.

**S-3 — "BOTH routes" is two of three, strictly.** `contribution_delta` also reaches rc=2 via
`d="$(mktemp -d 2>/dev/null)" || return 2`. Not fixture-reachable and not a survivor (CI killed all
11 applied evidence-side mutants), and the function's own header deliberately collapses
"unresolvable merge-base / absent head / empty range" into one refusal because splitting them
"produces an arm no case can kill". Spec prose imprecision, nothing more.

**W-1 and S-2 carried forward unchanged** from rounds 1–2 — the force-push/history-rewrite path
reaching `reduced-strength` rather than a violation, and `contribution_lines` reading only `+`/`-`
body lines so a mode change or pure rename produces no contribution. Both sit inside OR-1, whose
D-5 is `user-answered`. Deliberately not re-litigated.

## Independent verification at this head

`lean-gate-selftest.sh` 470/470 PASS · `lean-evidence-selftest.sh` all green (both run cold, no
`SKIP_STRESS`, with `CLAUDE_CODE_SESSION_ID`/`LEAN_RUN_MODEL`/`RUN_ID` unset) · target cases scored
by description: `(s3)(s4)(s4a)(vb3)(vb4)(vb4a)` all PASS · `check-lockstep-pairs.sh` 24/24 including
`contribution-compare` · `check-frozen-files.sh origin/main` clean · shellcheck clean on all changed
`*.sh` · `Changelog: none.` present on `c6e3a0f` · no `plugin.json` / `CHANGELOG.md` /
`marketplace.json` touched anywhere on the branch.

CI at this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr`
pass. `pr-gates` is red solely because the standing record read `verdict=needs-work` — its log names
that and nothing else — which this record resolves.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 (1 suppressed) | — |
| Security | Pass | 0 (2 suppressed) | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 1 nit | 82 |
| Test Coverage | Pass | 1 minor | 85 |
| Unit Test Mutation | Pass | 2 minor | 85 |

No reviewer went dark this round — `test-coverage-reviewer`, dark in round 2, returned. `a11y` and
the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). `db-reviewer` and
`pipeline-reviewer` were not triggered. Those are triggers that did not fire, not coverage gaps.

## Note on the nightly

The gate-side twin remains unscored by the PR lane by pre-existing configuration, so its first
automated scoring will be tonight's wholesale sweep. My probe is the reason that is acceptable
rather than a deferral: the case that will run there has already been shown to fail on the mutant.
