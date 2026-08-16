# lean review verdict — #503

verdict=approve
run_id: review-503-2
session_id: 2db9fff7-3a1e-4892-918a-5b426f176144
rounds: 2
pr: #507
reviewed_head: d258f19be5ab127179c21587ff73fe8359a987ef
reviewed_patch_id: d1ae8937d66cdb428152e715d0448c2f8cbaf9c0
inherited_patch_id: b3b2c4179e794929eb6b0f6e38d16e9144cd07cc
inherited_from_verdict: 871dfc329d746e41b8fbaae45d29c50596b42b0c
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, inheriting round 1's coverage of patch `b3b2c4179e79` by reference to the record at
`871dfc3`. Read this round: `871dfc3..d258f19`, 4 files (spec, `intake-orchestrator/SKILL.md`,
`intake-interviewer/SKILL.md`, `scripts/lockstep-manifest.tsv`) — plus the canonical receipt
contract, `ledger-lint.sh`'s receipt-mode parser and every site in the repo that restates the
receipt shape, read wider than the delta because the delta's whole subject is a cross-file
contract. Panel: 4/4 reviewers returned, none dark. Design lane not applicable — the repo
configures no `design.provider` and the spec has no `## Design` section to arm.

Round 1's blocker is fixed, and fixed at the mechanism rather than at the symptom: both sites
now name `## Surface Inventory` alongside `## Open Regions`, and Step 5.5's remediation prose
gained the refusal class it was missing. One warning is carried forward — the canonical-source
notice that should have caught the drift still does not name the two sites that drifted.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:10` | The canonical-source notice asserts that *"Every other site that restates them (`plan-interview/tools/ledger-lint.sh`, this plugin's `hooks/exitplan-ledger-gate.sh` via that lint, `review-toolkit:plan-reviewer`) carries a mirror marker and must be updated in lockstep."* `intake-orchestrator/SKILL.md:386` and `intake-interviewer/SKILL.md:227` demonstrably restate the intake-receipt contract, carry no mirror marker, and appear in neither the notice's list nor the paragraph the same diff widened to cover the surface inventory. The enumeration is now false by omission at exactly the site whose job is to be complete. The repair went to `scripts/lockstep-manifest.tsv` instead, which is the register CLAUDE.md designates and which records the obligation explicitly ("A change that adds or tightens a mandated section MUST move both, and the check is empirical") — so this is a placement judgment, not an unrecorded coupling. Kept as a warning rather than escalated: the runtime break is closed and measured, and adding these two to a list whose predicate is "carries a mirror marker" is a wider change than the delta. Two reviewers reached this independently (maintainability 88, test-coverage 82); it matches round 1's finding 3, unresolved at the site that owns it. |
| 2 | Informational | `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:398-408` | The split remediation prose names 3 of the 8 receipt-mode refusals explicitly (missing section; `decided` citing no `D-n` or an undeclared one; `out-of-scope` with no reason) plus the empty-form path, and covers the rest with a generic instruction. That is adequate rather than a gap: the five unnamed refusals are the mechanical ones (row arity, blank Surface cell, out-of-enum disposition, duplicate `S-n`, neither-rows-nor-form), and each of `ledger-lint.sh`'s messages for them states the expected shape inline, so an agent hitting one is not left without a path. AC-12's claim is about the refusal *class*, and the class is covered. |
| 3 | Informational | `plugins/intake-toolkit/evals/` | Scope-completeness returned PASS with one nit: the issue's Notes float a `plan-interview` eval as finding 2's regression guard, the check was performed, and the guard shipped as a deterministic lint instead — but the deferral is argued only in the PR's spec, not in the issue body, and no follow-up is linked. Same observation as round 1's finding 5; correct call for a repo whose CI is model-free by design. Not a scope miss: the issue's imperative was "check", and the eval clause is subjunctive. |
| 4 | Suggestion | `ledger-lint.sh:347` | Round 1's finding 4 (`grep -oE 'D-[0-9]+' \| head -n1` — `head`→`tail` is an equivalent mutant while no cell carries two citations) is unchanged and inherited. Still not worth a case unless the multi-citation form is given meaning. |

No blockers.

## Acceptance criteria

Every `AC-n` is scored against the whole spec, not against the delta. AC-1 through AC-11 were
satisfied at `36a6bbf`, are unmodified by this delta except where noted, and are re-affirmed
here; AC-10 and AC-12 were re-verified directly at this head.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Unchanged by the delta. Product/UX categories lead `plan-interview` step 2 under *What the user gets*; the six engineering categories retained below under *How it is built*. |
| AC-2 | satisfied | Unchanged. New step 3 enumerates surfaces and checks the register against them as an independent axis; names `## Surface Inventory` as the residue; step 6's exit criterion widened to "the register is empty *and* every surface is accounted for". |
| AC-3 | satisfied | Unchanged. Thin-register escalation present alongside the fat-register one. |
| AC-4 | satisfied | Unchanged. P8's batch-blessing paragraph plus the matching avoid-list bullet. |
| AC-5 | satisfied | Unchanged. Loop rule 9, widen-and-slow, plus the second avoid-list bullet. |
| AC-6 | satisfied | Unchanged. `### The Surface Inventory` documents row grammar, the closed enum, the `D-n` citation requirement and the explicit empty form. |
| AC-7 | satisfied | Unchanged; re-read at this head. All eight refusals are distinct named violations in receipt check D (`ledger-lint.sh:304-397`), each message stating the expected shape; `${SURFACE_ROW_COUNT} surface(s)` prints alongside the ledger-row and open-region counts. |
| AC-8 | satisfied | Re-run at this head with `CLAUDE_CODE_SESSION_ID` unset: `ledger-lint-selftest.sh` **48 passed, 0 failed**; `exitplan-ledger-gate-selftest.sh` **26 passed, 0 failed**. |
| AC-9 | satisfied | Unchanged. `intake/SKILL.md`'s pre-dispatch attribute section precedes the scenario table; handoff row narrowed to "**is the input**". |
| AC-10 | satisfied | Re-verified. The intake-receipt DROPPED entry covers the new section and its enum, and the delta extends it with the skill layer as a caller class of its own plus the empirical check the next tightening should run. Strengthened, not weakened. |
| AC-11 | satisfied | Unchanged. `valid-receipt.md` carries S-1/S-2 `decided` and S-3 `out-of-scope`; `docs/testing.md` correctly untouched. |
| AC-12 | satisfied | Both shape statements name `## Surface Inventory` (`intake-orchestrator:386-388`, `intake-interviewer:227`); Step 5.5's remediation splits into a ratification failure and a surface-inventory failure, and states that the empty form is for work rendering nothing rather than a way to clear the section. "A receipt built verbatim to the corrected prose lints clean" verified independently — see Verification. |

AC-12 is a legitimate strengthening of the spec, not the after-the-fact amendment the lean
contract treats as a blocker: it adds an obligation the diff then discharges, rather than
relaxing one the diff failed. The spec's blast-radius paragraph is corrected in the same
direction — it now names the skill layer as a second caller class instead of claiming the
blast radius was the selftest and one fixture.

## Verification performed at the reviewed head

- **Independent probe of the fix, built from the prose rather than from the fixture.** Three
  receipts authored verbatim to what each prose statement prescribes, linted with this
  checkout's `ledger-lint.sh --receipt`:
  - pre-fix shape ("five columns, plus a `## Open Regions` section") → **rc=1**, exactly two
    violations: `missing mandated receipt section: Surface Inventory` and `Surface Inventory
    has no rows and no explicit empty form`. The round-1 blocker reproduces.
  - corrected shape, rows branch → **rc=0** (`2 ledger row(s) / 0 open region(s) / 2
    surface(s) / OK`).
  - corrected shape, explicit-empty-form branch → **rc=0** (`0 surface(s) / OK`).
  Both branches of "each carrying rows or its own explicit empty form" therefore hold, which
  the build's own measurement did not separate.
- **Mirror-site enumeration re-run independently**, not taken from the PR body. Grepped the
  repo for `--receipt`, `Open Regions`, `five columns` and `receipt shape`: the only sites
  prescribing or restating the receipt shape are the canonical `interviewing-baseline`, the
  two this delta fixes, and `plan-interview/SKILL.md:47` — which already names
  `## Surface Inventory` and correctly states the section is receipt-only to the lint. No
  site was left behind. The two further sites the canonical notice names
  (`exitplan-ledger-gate.sh`, `review-toolkit:plan-reviewer`) mirror the ledger schema and
  provenance enum, neither of which this PR changes.
- **Cross-cutting check the delta does not show.** `intake-orchestrator` Step 5.5 writes the
  receipt to `.claude/pipeline-state/{ISSUE}-ledger.md`, which `dev-pipeline`'s `plan-lint.sh`
  Check 6 also parses as the backing pre-flight ledger. Verified no collision: `plan-lint.sh`
  anchors on `^\|[[:space:]]*D-[0-9]+[[:space:]]*\|` (lines 304, 385, 402), so `| S-n |` rows
  in the new section are invisible to it. `exitplan-ledger-gate.sh` runs the lint in default
  mode, where the surface block is gated off entirely.
- **CI at this head**: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass. `pr-gates` fails on exactly one thing — the round-1 `needs-work`
  record this round replaces (`reads 'verdict=needs-work', not 'verdict=approve'`).
- Round 2 changes no shell, so the guard set, the mutation baseline and the catalog anchors
  are untouched; round 1's mutation evidence is inherited rather than re-derived.
- Delta re-checked immediately before writing this record: PR head still `d258f19`, and
  `871dfc3..HEAD` is still the same four files.

## Strengths

- The fix repairs the mechanism, not just the two broken sentences. Step 5.5's remediation
  prose previously had one story for a red lint (the ratification one); an agent hitting a
  surface-inventory refusal would have been told to reclassify a Kind cell that was never the
  problem. Splitting it by cause is what makes the gate passable *and* diagnosable.
- The empty-form sentence is the load-bearing addition nobody asked for: "it is not a way to
  clear the section" closes the obvious escape hatch an agent under a red lint would reach for
  first, and closes it in the same paragraph that introduces the form.
- The blast-radius correction is written as a taxonomy ("two caller classes, and only one of
  them is automated") rather than as an erratum, so the distinction that produced the bug —
  automated callers red in CI, skill-layer callers fail silently at agent runtime — is now the
  shape of the paragraph rather than a fact buried in it.
- The lockstep entry states the check as an *empirical* one ("build a receipt verbatim to the
  prose and lint it") rather than as a reading obligation. That is the difference between a
  register a future author can act on and one they can only agree with.
