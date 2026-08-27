# lean review verdict — #693

verdict=approve
run_id: review-693-1
session_id: 1ee2da6c-b790-446c-ad16-58309aa9e35c
rounds: 1
pr: #696
reviewed_head: c1510a01a900ece8b5ef5a9b923963c00f08ba6e
reviewed_patch_id: 79d4a1f6eb945ecfadcd11a5add58b541e016e1d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Review round 1 — PR #696 (#693)

Range read: `fae20baa..c1510a01` (root round — `G delta` printed the FULL branch diff, nothing
verifiable to inherit). Panel: 7/7 reviewers returned, none dark. No blockers.

The change is well-matched to its own stated scope. The guard is refused at the writer with the
placement its comment claims (verified: the block ends at `lean-gate.sh:4559`, the review run-id
cache comment sits at `:4563`), it is provider-gated so no consumer without a design axis is
touched, and it declines a milestone-4 backstop for a reason that holds — a legacy record is
byte-indistinguishable from a stripped one. The honest-scope framing (tamper-evidence, not
fidelity) is carried identically in the gate comment, `docs/live-render.md`, `review-lean` step 5b
and the PR body, so no artifact overclaims.

### Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Suggestion | `lean-gate.sh:4548` | The `fid_refs` boundary leg (`(^\|[^A-Za-z0-9])`) is behaviorally live but exercised by no case. Re-derived here: the shipped form reads `AC-1 D-1` from `AC-1 and TRAC-1 and XD-2 and D-1 and 9AC-7`; dropping the alternation reads `AC-1 AC-7 D-1 D-2`. A boundary-less mutant only WIDENS the known-refs set, so every added `(fe*)` case survives it and the dangling-citation arm silently loosens on a spec whose prose carries a suffix collision. Same class `(fe9)` exists for; worth one fixture and a catalog row. |
| 2 | Suggestion | `lean-gate.sh:3171,3174` | The section terminator (`insec && /^#+[[:space:]]/`) and the `!found` early `exit` are inert against the fixtures: no `--summary-file` fixture carries markdown BELOW the evidence table, which is the shape a real reviewer summary always has (findings table, per-AC scoring). Probed independently — the terminator does work: a `## Other` section carrying `\| RS-9 \|` after the evidence table is correctly ignored. Coverage-completeness only, not a guard weakness. |
| 3 | Suggestion | `lean-gate.sh:4557` | `match(v, /(AC\|D)-[0-9]+/)` resolves only the FIRST reference in a `verdict` cell, so `deviation (AC-1, AC-99)` is accepted with `AC-99` dangling (probed). This is faithful to the cited precedent — `ledger-lint.sh:522` is `grep -oE 'D-[0-9]+' \| head -n1` — and the published grammar is single-ref, so tamper-evidence survives (a resolving criterion IS named). The spec's and the PR body's phrasing "plus `grep -oE '(AC\|D)-[0-9]+'` for the reference" elides the precedent's `head -n1` and reads as all-matches; AC-17's letter covers the multi-ref cell and the code does not. |

None of the three is a blocker: no `AC-n` is left unsatisfied by any of them, and none weakens the
guard against the shape the ticket was filed for.

### Merge-boundary state (recorded, not a blocker)

`pr-gates` is red at this head on the `lean chain reconciliation` step only — `lean-evidence` on a
missing verdict record. That is the expected pre-approve state of a lean PR, not a finding. The
three correctness lanes are green at the reviewed head: `lint-and-selftests`,
`selftests (macos, bash 3.2)`, `mutation-sweep-pr` (run `33068446147`, `headSha`
`c1510a01a900ece8b5ef5a9b923963c00f08ba6e`).

### Verification I performed rather than inherited

- **AC-12 by CI citation** (command and head both match this review). Run `33068446147` at
  `c1510a01`, both selftest jobs running the recipe of record
  (`--full --exclude tools/install-topology-selftest.sh`): `76 scored, 75 run, 1 served from
  cache, 0 failed` on each. The one cached suite is `cost-block-selftest.sh`, outside this diff.
  `lean-gate-selftest.sh` RAN on both (156s Linux job `98504280624`, 389s macOS/bash-3.2 job
  `98504280665`) and all 23 `(fe*)` cases passed on BOTH awks;
  `scenario-liveness-selftest.sh` ran on both and `(lean-design-evidence)` passed.
- **AC-15 re-derived, because nothing on the PR lane grades it.** `lean-gate-selftest.sh` is
  slow-listed, so `mutation-sweep-pr` defers these six rows and passed in 15s having graded them
  with nothing. Independently: all six seds apply under the sweep's own `sed -E` and each changes
  exactly one line (no anchor drift). Driving the extracted guard against each mutant, four flip
  exactly their predicted case at the accept/refuse level (`…-undeclared-row`→`(fe4)`,
  `…-missing-row`→`(fe3)`, `…-dangling-citation`→`(fe9)`, `…-enum-boundary`→`(fe8b)`), with the
  baseline-conforming table still accepted under every mutant. `…-column-superset` does NOT flip
  accept/refuse — the per-row cell-count arm reds the 7-column table either way — but it drops the
  `header row must name exactly 6 columns` line, which is precisely what `(fe5d)` asserts and
  precisely what that case's comment says it asserts. `…-absent-spec` degrades the message from
  `no spec at …` to the `design_state reports 'unarmed'` catch-all, which `(fe14)` greps for.
- **AC-9 by inspection of the hunk list**: `lean-gate.sh` changes at 5 sites only — the header
  comment, the `--help` range, the new function, one `local` declaration, and the new block. No
  hunk falls inside `cmd_4`. `(fe15)` composes the same fact.
- **AC-13 counted at this head**: ten armed `--fidelity pass` writes repaired by adding a
  conforming body — seven in `lean-gate-selftest.sh`, three in `scenario-liveness-selftest.sh`.
  None re-pointed to `not-applicable`; the three prettier verify-and-revert cases still assert
  `fidelity: pass`.
- **The `--help` range** now ends at line 269, which is the last header line
  (`# bash 3.2 compatible …`). Correct.
- **The two new `docs/prose-blocker-triage.tsv` rows** anchor on the constructs they name
  (`review-lean/SKILL.md:70` and `:84`) and cite an enforcer that really enforces them
  (`lean-gate.sh::verdict`).

### Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(fe1)` omitted `--summary-file`, `(fe1b)` prose-only summary — both refused naming the section; `(fe1c)` pins that the refusal caches no review identity. |
| AC-2 | satisfied | `(fe3)` omission direction, `(fe4)` undeclared direction. Independently reproduced. |
| AC-3 | satisfied | `(fe5)` misnamed column, `(fe5b)` no separator, `(fe5c)` nested/case-folded heading accepted, `(fe5d)` seven-column superset refused BY THE HEADER message. |
| AC-4 | satisfied | `(fe6)` names row and column. Scoped to rows the `RS-[0-9]+` anchor recognizes — which is the reader shape the ticket itself prescribes — so a row with an empty first cell is dropped rather than named. Reproduced; not a defect against the AC as written. |
| AC-5 | satisfied | `(fe7)` heading + header + separator and nothing else is refused. |
| AC-6 | satisfied | `(fe2)` multi-row-per-state with a cited deviation is accepted. |
| AC-7 | satisfied | `(fe10)` `not-applicable`/`fail` need no table; `(fe11)` an unarmed consumer is demanded nothing. |
| AC-8 | satisfied | `(fe12)` disarmed, `(fe13)` `error:`, `(fe14)` absent spec under a configured provider — three of `design_state`'s four outcomes refused at the writer. |
| AC-9 | satisfied | `(fe15)` a stripped legacy record still walks milestone 4; no hunk inside `cmd_4`. |
| AC-10 | satisfied | `figma-faithful/SKILL.md` step 7 no longer claims a pipeline dispatches or branches; it carries an explicit **Dispatch … yourself** instruction and keeps `block`/`fix-and-go`/`pass`. The `review-lead-skip` marker names the operator at step 7 and denies review-lead. |
| AC-11 | satisfied | `review-lean/SKILL.md` step 5b carries the six-column table verbatim plus the enum rule and the "does not force `fail`" clause. |
| AC-12 | satisfied | 23 `(fe*)` cases over AC-1–AC-9, AC-14, AC-16–AC-18; `scenario-liveness-selftest.sh` gains `(lean-design-evidence)`. Verified green on both CI lanes at this head (citation above). |
| AC-13 | satisfied | Ten writes repaired, re-derived at this head rather than by the ticket's line numbers. |
| AC-14 | satisfied | `(fe16)` reads `rounds` and `reviewed_patch_id` through the gate's OWN `record_key` over a record whose table carries cells shaped like the `rounds` and `reviewed_patch_id` keys; `(fe16b)` walks milestone 4 on it. |
| AC-15 | satisfied | Six rows, all applying and all killed — re-derived here rather than inherited, because the PR lane grades none of them. |
| AC-16 | satisfied | `(fe8)` a free-text reason is refused. |
| AC-17 | satisfied | `(fe9)` a dangling `AC-9` is refused naming the reference. Finding 3 records the multi-reference cell the first-match parse lets through; it matches the cited precedent and leaves a resolving criterion named, so it does not unsatisfy the AC. |
| AC-18 | satisfied | `(fe2)` a cited deviation writes at `fidelity: pass`; no new `fidelity` value. |
| AC-19 | satisfied | `docs/live-render.md`'s closing section states what the gate enforces about the record's SHAPE, that it is tamper-evidence and not fidelity, and that there is deliberately no milestone-4 backstop. Added mid-run in the implementation commit and declared as such in the spec — it ADDS a doc obligation the diff then satisfies, not a narrowing to match the diff. |

Design fidelity: **not-applicable** — the spec carries no `## Design` section and this repo
configures no `design.provider`, so step 5b does not arm. The new guard is inert on this PR by
construction; its coverage is fixture-driven, and a green run on this branch is not the arm firing.

### Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Pass | 2 | 81–84 |

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`). Not a coverage gap — nothing was
dispatched.

**Verdict: approve.**
