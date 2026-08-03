# lean review verdict — #346

verdict=needs-work
run_id: review-346-2
session_id: 8f05884c-ef64-4173-a6e1-e1da47841dd2
rounds: 2
pr: #368
reviewed_head: af5661cb23a4a68ef3ce763382bb1f230016fae2

## Verdict: needs-work (round 2)

Round 1's blocker is **fully discharged** — every refusal it named now has a kill criterion, and
I re-verified each one by applying the mutant myself rather than taking the PR body's word. The
rebase onto `origin/main` is clean authoring, and `SKILL.md` is back at exactly 60/60.

The new blocker is a **regression introduced by round 2's own compression**, and round 1 asked
for it. AC-7 names two things `run-lean`'s SKILL.md must say; the pass that freed the lines
deleted one of them.

## Blocker

**B-1 — AC-7's second clause is no longer met at `run-lean/SKILL.md`.**

AC-7 reads: "… `run-lean`'s SKILL.md names **when BUILD writes one** and **what the merge
boundary does with it**."

Head state, `plugins/dev-pipeline/skills/run-lean/SKILL.md:52-53`:

> **A decision the receipt never covered is not yours to make (P9).** Write the intent-gap
> record (schema: `interviewing-baseline`) and follow its region's declared disposition.

That names *when*. It does not name what the merge boundary does with it — the clause carrying
that ("ratify before the handoff — the merge boundary refuses a record still reading
`ratified: no`") was the one round 2 cut. Nothing else in the file supplies it: `:43`'s "the
gate and the merge boundary both refuse it" is about the **verdict** record, and `:58-59` names
`check-lean-chain.sh` generically without the ratification consequence.

**This is round 1's error, not the build session's.** Round 1's O-1 triaged that clause as
"courtesy; this is the compressible clause" and recommended routing it to gate stderr. The build
session did exactly that. But a reviewer's triage is not a spec amendment, and round 1 scored
AC-7 satisfied **while the clause was still present** — so the advice contradicted the AC it had
just scored. Recording that here so round 3 does not oscillate.

**AC-7 is doc-scope, so there is no substance to appeal to over the letter.** It specifies what
a named file must say. Operationally the information is reachable — `interviewing-baseline`
carries the full consequence, and `lean-gate.sh`'s milestone-4 stderr now fires at the handoff
moment — but AC-7 assigns this sentence to *this file*, which is the one document a build
session is told to read start-to-finish (`SKILL.md:11`, "Read this file, then work the
checklist"). An unmet `AC-n` is a blocker regardless of size.

**Remedy, and what NOT to do.** Restore the clause *inside the existing two-line budget* — do
**not** revert the stderr routing, which is a genuine improvement and not an alternative to the
doc line. Lines 44 and 50 are already long unwrapped lines, so this fits at 60/60:

```
- **A decision the receipt never covered is not yours to make (P9).** Write the intent-gap
  record (schema: `interviewing-baseline`), follow its region's disposition, and ratify before the handoff — the merge boundary refuses `ratified: no`.
```

## Round 1's B-1 — discharged, re-verified by execution

Every kill claim in the PR body was checked by applying the exact mutant and confirming the case
count, not by reading the table:

| Round-1 finding | New case | Mutant applied here | Result |
| --- | --- | --- | --- |
| C-1 `-$KEY` issue-scoping | `(S0b)` | dropped `-$KEY` from the `case` pattern | **exactly 1 case reds**, `(S0b)` |
| C-2 `open` requires `deferred` | `(ll-aa)` | condition → `if false` | **exactly 1 case reds**, `(ll-aa)` |
| C-3 Kind-enum default arm | `(ll-ab)` | `violate` line deleted | **exactly 1 case reds**, `(ll-ab)` |
| C-4 open-region arity | `(ll-ac)` | `violate` line deleted | **exactly 1 case reds**, `(ll-ac)` |
| C-4 empty Region cell | `(ll-ad)` | `violate` line deleted | **exactly 1 case reds**, `(ll-ad)` |
| C-4 duplicate `OR-n` | `(ll-ae)` | `violate` line deleted | **exactly 1 case reds**, `(ll-ae)` |
| C-5 `ledger-lint --help` | `(ll-af)` | `2,51p` → `2,45p` | **exactly 1 case reds**, `(ll-af)` |
| C-5 `check-lean-chain --help` | `(T)` | `sed -n` → `sed -z` | **exactly 1 case reds**, `(T)` |

`(S0b)` is the one that mattered, and it is the right shape: it declares a real, non-fixture
record for issue **99** and asserts the gate still reports absence for 42 — so it separates the
`-$KEY` predicate from the fixture-path exclusion `(S0)` already covers. Ordered before every
`acme-42` record, so nothing else can be what satisfies the scan.

**`(T)`'s two-directional assertion is load-bearing and I checked why.** The `cmp-z` operator is
`s/-n /-z /`, so the mutant is `sed -z '2,87p'`. On BSD sed that is `illegal option -- z` and the
output is empty — verified locally, the case reds on the *presence* assertion. On GNU sed `-z`
is legal, `-n` is gone so auto-print is on, and the file has no NUL bytes, so the whole file
including `set -uo pipefail` is emitted — which is why the second, *absence* assertion is the
one that kills it there. A presence-only case would have survived on the ubuntu lane. That
matters directly: retiring `scripts/check-lean-chain.sh::cmp-z::2` from the baseline is only
safe because both directions are pinned.

**The retired baseline row is correctly identified.** I enumerated the operator's sites at both
ends: ordinal 1 is the comment at `:13` (`AC-n ` matches `-n `) at both base and head, ordinal 2
is the `--help` line — `2,83p` on `origin/main`, `2,87p` at head. Site set unmoved, ordinal 2's
content changed, and `(T)` now kills it. Removing the row rather than re-keying it is right; a
stale row would let the mutant resurrect without redding a lane.

## Warnings — verified, not blocking

All three come from `unit-test-mutation-reviewer` and I confirmed each survives by applying it.
They are **not** round-1 B-1's class, and the distinction is the reason they are not blockers:
C-1–C-5 were `violate()` **refusals** — a deleted refusal is a contract rule that silently stops
being enforced. None of these three is.

| # | Site | Surviving mutant | Why not a blocker |
| --- | --- | --- | --- |
| W-1 | `ledger-lint.sh:136` `normalize_arity` | drop-branch → `if false` (35/35 still green) | a **tolerance**, not a refusal. Its absence never admits a bad receipt — it degrades one message ("malformed row" instead of the specific empty-cell violation). The guard `$1 == $3+1 && last cell blank` is what stops it normalizing a legitimate 6-cell row |
| W-2 | `ledger-lint.sh:62` two-positional-args | guard deleted (35/35 still green) | a usage error, not a contract surface. Removing it lints the *second* path instead of exiting 2; no caller passes two |
| W-3 | `check-lean-chain.sh:430` `break` | `break` removed (suite still green) | tie-break among **off-contract** states. The schema is explicit — "One record per issue" — so first-wins vs last-wins only differs on input the contract forbids |

W-1 is the one worth a case if any: `normalize_arity` is new logic in this diff and its comment
claims a specific behavior nothing drives. One fixture row with a trailing space after the
closing pipe would pin it. Cheap, but it does not gate the merge.

## Per-AC scoring

| AC | Rung | Score | Evidence |
| --- | --- | --- | --- |
| AC-1 | oracle | **satisfied** | `ledger-lint-selftest.sh` 35/35. `(ll-q)` drives all three illegal `intent` backings, `(ll-r)` discriminates, `(ll-s)` the mirror error, `(ll-t)`/`(ll-u)` uncited vs dangling, `(ll-aa)` the third leg. Mode isolation pinned both directions by `(ll-y1)`/`(ll-y2)`. Default mode unchanged with no fixture edits — `exitplan-ledger-gate-selftest.sh` 25/0 still green |
| AC-2 | oracle | **satisfied** | `check-lean-chain-selftest.sh` all green. `(S0)`–`(S4)` cover fixture exclusion, the unratified refusal, the uncited-`yes` refusal, the clearing case, and the first-match read; `(S0b)` adds the cross-issue arm |
| AC-3 | proxy | **satisfied** | `BASELINE.md`: 5/5 seeded, 4/5 class agreement, 4 grounded extras. The S-4 disagreement resolved in the probe's favor per the README's own rule; the two extra hand-verified facts and the dispatch-by-body caveat are both disclosed. Unchanged since round 1 |
| AC-4 | critic | **satisfied** | loop rule 8 in `interviewing-baseline`, applied at both the interviewer and the orchestrator; `spec-reviewer`'s Discovery Coverage carries all four named sub-items. Unchanged since round 1 |
| AC-5 | oracle | **satisfied** | `check-lockstep-pairs.sh` — 13 pairs, 0 failed, both `provenance-enum` rows green. Ordinals independently enumerated at base and head for the operator whose row moved; the one retired row is the `--help` line and `(T)` kills it in both sed dialects. `catalog::ledger-lint-empty-decision` still anchors |
| AC-6 | critic | **satisfied** | `check-changelog-trailer.sh origin/main` — OK. `bb10475` and `f8cc8ae` carry substantive trailers |
| AC-7 | critic | **unsatisfied** | `interviewing-baseline` carries all four required items in full (Kind axis, ratification bar, Open Regions, intent-gap schema incl. the merge-boundary consequence). `run-lean`'s SKILL.md names *when* BUILD writes one but **not what the merge boundary does with it** — see B-1 |

The spec is byte-identical to the tree round 1 scored (`git diff 181a805..HEAD -- docs/plans/second-shift-346-lean.md` is empty), so nothing was amended after the fact to match the diff.

## Strengths

- **The kill claims are real and independently reproducible.** Eight mutants applied by hand,
  eight single-case reds. The PR body's "verified by applying the exact mutant" is not a
  formality here — `(S0b)` and `(T)` in particular could each have been written in a shape that
  looks like coverage and is not, and neither was.
- **`(T)` is the rare help-text case that is not theater.** Asserting both the last header line's
  presence *and* the first code line's absence is what makes it portable across BSD and GNU sed —
  and it is the direct reason a baseline row could be retired rather than re-keyed.
- **The `(S)` block's ordering rationale is correct and non-obvious.** Committing the gap record
  first and the verdict on top is both the real shape and the only order `#367`'s one-differing-
  path tolerance permits; committing them together would have redded every case on staleness
  instead of on what it asserts.
- **The rebase resolved by authoring, not by picking a side.** Main's post-`#365` tracker-delta
  block and `#367`'s `reviewed_head` wording both survive intact, and the two lines were paid for
  by compressing prose whose dropped clauses a script already enforces.

## Reviewers

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 (2 suppressed) | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Pass (nits) | 3 | 80–82 |

No reviewer went dark. Every relayed finding was re-verified by executing the mutant; none was
taken on the reviewer's word. B-1 is the orchestrator's own finding — no reviewer raised it,
because no reviewer was given the spec.

## Verification run

Worktree `second-shift-346` at `af5661c`, clean, in sync with `origin/lean/second-shift-346`,
rebased onto `origin/main` at `8f9174c`.

- Full `*-selftest.sh` sweep, `-P 4`, **without** `SKIP_STRESS` — `rc=0`, 62 suites, zero failures
- `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` — clean
- `jq empty` over all `*.json` — clean
- `check-lockstep-pairs.sh` — 13 pairs, 0 failed
- `check-frozen-files.sh origin/main` — clean; `check-changelog-trailer.sh origin/main` — OK
- CI: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass. `pr-gates` fails on the
  round-1 `verdict=needs-work` record and its stale `181a805` head with no `reviewed_head` — the
  designed state for a lean PR awaiting its review, and what this record replaces
