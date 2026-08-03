# lean review verdict — #346

verdict=needs-work
run_id: review-346-1
session_id: 23342127-c7a0-4b97-afb3-fe031a5917fb
rounds: 1
pr: #368

## Verdict: needs-work (round 1)

The work itself is strong and all seven ACs are satisfied on the diff as it stands. The
blocker is not an AC miss: **this head cannot be the merged head**, so a verdict naming it
would be void on arrival.

## Blocker

**B-1 — the PR does not merge, and the rebase is a judgment call, not a conflict-marker
cleanup.** `git merge-tree --write-tree origin/main HEAD` conflicts in
`plugins/dev-pipeline/skills/run-lean/SKILL.md`. `312a0b4` (#365, jira tracker adapter)
landed on main after this branch was cut and rewrote the *same* paragraphs this branch
compressed — the opening block, checklist item 8, and the "Anything pushed after an approve"
rule. Both sides are additive against a file already at exactly 60/60, which
`lean-gate-selftest.sh` case (f) asserts:

- main (post-#365): 60 lines, including a new tracker-delta block
- this branch: 60 lines, including the new 3-line P9 bullet
- union: ~63 lines, from prose already compressed twice

So the rebase has to find three more lines. It cannot be resolved by taking either side.

Since milestone 4 binds a verdict to the tree it covered, the rebase reopens it regardless —
which is why this is `needs-work` rather than an approve with a rebase note attached.

**Where the three lines should come from.** The cap is an anti-process-accretion forcing
function, not a token budget, so the triage question is *does a script already refuse this?*
Applied to the new bullet:

| Clause | Gated? | Disposition |
| --- | --- | --- |
| "Write the intent-gap record (schema: `interviewing-baseline`)" | **No** — absence is legal and merely printed; no script can detect that a decision surfaced | load-bearing, keeps its budget |
| "follow its region's disposition" | **No** — the gate deliberately does not re-validate `disposition:` | load-bearing |
| "ratify before the handoff — the merge boundary refuses a record still reading `ratified: no`" | **Yes** — `check-lean-chain.sh` refuses it with a full remediation string | courtesy; this is the compressible clause |

The third clause is the one to spend. Routing it into gate stderr rather than SKILL.md lines
is the release valve; the first two genuinely cannot be gated and should survive the pass.

## Coverage cluster (land in the same push — the branch is moving anyway)

Five new refusals have no oracle. Confirmed by grep against the selftests, all counts zero —
and by AC-5's own evidence these are also out of the mutation sweep's reach, since every edit
landed below each operator's first two sites and `K=2` never arrives. A green sweep is not
coverage of them, which the PR body says plainly and then leaves standing.

| # | Site | Untested refusal | Surviving mutant |
| --- | --- | --- | --- |
| C-1 | `scripts/check-lean-chain.sh:401` | `*-$KEY$LEAN_INTENT_GAP_SUFFIX` issue-scoping | drop `-$KEY` → any issue's record satisfies this PR. Every fixture is `acme-42`, so the whole suite passes. Strongest of the five: it is the predicate binding a ratification to the issue being merged. |
| C-2 | `ledger-lint.sh:190` | `open` kind requires provenance `deferred` | delete the check — every `open` row in the suite is already `deferred`, so it is never driven to violate |
| C-3 | `ledger-lint.sh:202` | Kind-enum default arm | delete it — no fixture carries an out-of-enum Kind |
| C-4 | `ledger-lint.sh:239,247,260` | Check B: malformed OR-row arity, empty Region cell, duplicate `OR-n` | delete any one — no malformed, blank, or duplicated open-region row exists in any fixture |
| C-5 | `ledger-lint.sh:27` | `-h\|--help` | header growth silently shifts `sed -n '2,51p'` out from under it. Both ranges are correct today (verified: header ends at 51, `set -euo pipefail` at 52; chain gate's `2,80` likewise) — untested, and this repo has already been burned by exactly this |

C-1 is the one I would not ship without; C-2 through C-5 are cheap and mechanical.

## Per-AC scoring

| AC | Rung | Score | Evidence |
| --- | --- | --- | --- |
| AC-1 | oracle | **satisfied** | `(ll-q)` drives all three illegal `intent` backings; `(ll-r)` discriminates; `(ll-s)` the mirror error; `(ll-t)`/`(ll-u)` uncited vs dangling; `(ll-y1)`/`(ll-y2)` prove mode isolation both directions. Default mode unchanged: 29/29 green, no fixture edits, `plan-lint` 43/43 and `exitplan-ledger-gate` 25/25 still green. The exact-arity fix is the right call — `[5,6]` did accept a canonical 5-column receipt in 4-column mode. |
| AC-2 | oracle | **satisfied** | `(R0)`–`(R4)` cover all four clauses, incl. the fixture-path exclusion and first-match reads. `(R4)` — header `no`, prose quoting `yes` — is the case that matters. |
| AC-3 | proxy | **satisfied** | `BASELINE.md` records 5/5 seeded, 4/5 class agreement, 4 grounded extras. The S-4 disagreement is correctly resolved in the probe's favor per the README's rule, and the two extra facts are flagged as hand-verified. Dispatch-by-body is disclosed with what it changes. |
| AC-4 | critic | **satisfied** | loop rule 8 in `interviewing-baseline`; applied at the interviewer (assemble from rows, no mid-interview whole-spec draft) and the orchestrator (decomposition section, "a slice boundary nobody disposed of is a decision you made wearing the costume of a finding"). `spec-reviewer`'s Discovery Coverage carries all four named sub-items. |
| AC-5 | oracle | **satisfied** | lockstep 13 pairs / 0 failed, both `provenance-enum` rows green. Ordinals enumerated per operator over base and head; unmoved, so no re-baseline is owed — which is the shape the restated AC asks for. `catalog::ledger-lint-empty-decision`'s anchor still matches at `ledger-lint.sh:158`. |
| AC-6 | critic | **satisfied** | `Changelog:` on `71e0f6d`, `Changelog: none` on `e15c646`. |
| AC-7 | critic | **satisfied** | `interviewing-baseline` carries the Kind axis, the bar, Open Regions, and the full intent-gap record schema; `run-lean` names when BUILD writes one and what the merge boundary does — subject to B-1. |

The AC-5 mid-run restatement is legitimate, not a spec amended to match the diff: the original
text demanded re-baselining ordinals that had not moved, which is undischargeable, and an
undischargeable criterion is one that gets scored by substituting a nearby bar.

## Strengths

- The two-mode arity fix is the good kind of small: `normalize_arity` drops one trailing blank
  cell *only* when doing so lands on the expected count, so a genuinely empty last column still
  earns its specific violation instead of a generic "malformed row".
- `(ll-q)` drives all three illegal backings rather than one. A bar that rejected `deferred`
  while accepting `codebase-derived` would have passed a single-case test and let the commonest
  evasion straight through.
- The lockstep entry is a **DROPPED** row with its reasoning recorded, not an invented canonical
  constant manufactured so two sites could be compared. It also names the deliberate
  non-coupling — the chain gate checks ratification only — which is what keeps the disposition
  enum single-sited.
- `BASELINE.md` corrects the answer key rather than the probe, and says so.

## Reviewers

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test Coverage | Pass (nits) | 1 | 85 |
| Unit Test Mutation | Fail | 5 | 82–85 |

No reviewer went dark. Every mutation/coverage finding above was re-verified by grep before
being relayed; none was taken on the reviewer's word.

## Verification run

`shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` — clean. `jq empty` over all `*.json` —
clean. Full `*-selftest.sh` sweep, `-P 4`, **without** `SKIP_STRESS` — `rc=0`, 58 suites green,
zero failures. `check-lockstep-pairs.sh` — 13 pairs, 0 failed.
