# lean review verdict — #503

verdict=needs-work
run_id: review-503-1
session_id: a91bf332-cce6-48e4-acb9-e95bd169bd2d
rounds: 1
pr: #507
reviewed_head: 36a6bbffed8643ce56b2bed99db7b03d28c2f790
reviewed_patch_id: b3b2c4179e794929eb6b0f6e38d16e9144cd07cc
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full branch diff (`3cf27cd..36a6bbf`, 8 files). Panel: 7/7 reviewers returned, none
dark. Design lane not applicable — the repo configures no `design.provider`, and the spec has
no `## Design` section to arm.

The implementation is good and the ACs all land. One blocker sits outside the AC set: the new
mandated receipt section breaks two sibling skills that build receipts to the old shape, one of
which runs this very lint as its own exit gate.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:386`, `plugins/intake-toolkit/skills/intake-interviewer/SKILL.md:227` | Both skills instruct their agent to emit a receipt in the pre-#503 shape — "five columns, plus a `## Open Regions` section" — and `intake-orchestrator` Step 5.5 then runs `ledger-lint.sh --receipt` on exactly what it just told the agent to write. After this diff that lint refuses it. Measured: a receipt built verbatim to that prose lints `OK` (rc=0) at `3cf27cd` and `FAIL — 2 violation(s)` (rc=1) at this head, on `missing mandated receipt section: Surface Inventory` plus `has no rows and no explicit empty form`. `intake-orchestrator`'s Receipt Exit Gate is therefore unpassable by construction, and its red-lint remediation prose explains only the ratification-bar failure ("an `intent` row backed by `codebase-derived`…"), so an agent hitting the new refusal is given no path — while `intake-interviewer` states as fact that the old shape "is the artifact `ledger-lint.sh --receipt` checks", which is now false. Fix is two prose edits: add `## Surface Inventory` to both shape statements, and extend Step 5.5's remediation note to cover the new refusal. |
| 2 | Warning | `docs/plans/second-shift-503-lean.md:44-46`, PR body | The blast-radius claim — "`--receipt` has **no** automated caller in the pipeline … so it is operator-run plus the selftest and one fixture" — is the reasoning that produced finding 1. It is true of CI and of the merge boundary, and false of the skill layer: `intake-orchestrator` Step 5.5 is a mandated in-skill caller. Worth correcting in the spec so the next change to this lint scopes against skill-driven callers too, not only automated ones. |
| 3 | Warning | `plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:10` | The canonical-source notice was correctly widened to cover the surface inventory ("Every other site that restates it…"), which makes finding 1 a violation of a contract this same diff strengthens, rather than an incidental oversight. Same fix; noted separately because it is the rule that should have caught it. |
| 4 | Suggestion | `ledger-lint.sh:347` | `grep -oE 'D-[0-9]+' \| head -n1` takes the first citation in a `decided` cell; `head`→`tail` survives every case, since no fixture puts two `D-n` tokens in one cell. Equivalent-mutant territory and it mirrors the pre-existing `OR-n` extraction it was modelled on — not worth a case unless the multi-citation form is ever given meaning. (unit-test-mutation-reviewer, confidence 82) |
| 5 | Informational | `plugins/intake-toolkit/evals/` | The issue's Notes float a `plan-interview` eval as finding 2's regression guard; the spec declines it under Out of scope and ships the lint instead. Correct call for a repo whose CI is model-free by design, and the deterministic guard is strictly stronger than an API-billed one. Recorded because the deferral rationale lives in the spec rather than the issue body. (scope-completeness-reviewer, PASS, confidence 85) |

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `plan-interview/SKILL.md` step 2 leads with five product/UX categories (states and transitions — loading/empty/partial/error/not-found; copy the user reads; first paint; degraded and missing dependencies; composition and placement) under a *What the user gets* heading, with the six engineering categories retained below under *How it is built*. The AC's "empty / error / edge surfaces" is folded into the states bullet rather than standing alone; every named concept is present. |
| AC-2 | satisfied | New step 3 enumerates surfaces and checks the register against them as an independent axis, and names `## Surface Inventory` as the residue for a pre-flight receipt. Steps renumbered 3→4, 4→5, 5→6 consistently; step 6's exit criterion now reads "the register is empty *and* every surface is accounted for". |
| AC-3 | satisfied | Escalation section gains the implausibly-**thin** register trigger alongside the existing >~10 fat-register one. |
| AC-4 | satisfied | P8 gains the batch-blessing paragraph naming the move exactly as the AC specifies, plus a matching bullet under "What all interviewers must avoid". |
| AC-5 | satisfied | New numbered loop rule 9, widen-and-slow, with a second avoid-list bullet ("Reading repeated pushback as fatigue and narrowing in response"). |
| AC-6 | satisfied | `### The Surface Inventory` documents row grammar (worked 3-row table), the closed `decided \| out-of-scope` enum, the `D-n` citation requirement, and the explicit empty form. Canonical-source notice widened to match. |
| AC-7 | satisfied | All eight refusals implemented as distinct named violations (`ledger-lint.sh:304-397`), a well-formed inventory lints clean, and `${SURFACE_ROW_COUNT} surface(s)` prints alongside the ledger-row and open-region counts. Verified by probe, not by reading — see Verification. |
| AC-8 | satisfied | 14 new cases `(ll-ag)`–`(ll-as)`; `(ll-af)`'s `--help` line-range guard holds after the header grew to 67 lines. Suite is 48 cases, 48 passed / 0 failed at this head. |
| AC-9 | satisfied | `intake/SKILL.md` gains a pre-dispatch attribute section ahead of the scenario table, with three dispositions; the handoff table row is narrowed to "**is the input**" and a note routes the merely-exists case to the attribute. Dispatch rule updated to announce the attribute result. |
| AC-10 | satisfied | The intake-receipt DROPPED entry names `SURFACE_DISPOSITION_ENUM`, both empty forms, why neither `verbatim` nor `subset-of` reaches a fenced code block, and re-points the behavioral guard at `ll-o`–`ll-as`. |
| AC-11 | satisfied | `valid-receipt.md` carries S-1/S-2 `decided` and S-3 `out-of-scope`; `docs/testing.md` correctly untouched (cases added to an existing suite, no new tier). |

All 11 satisfied. The blocker is a regression outside the AC set — the ACs bound what the spec
asked for, not what the diff may break.

## Verification performed at the reviewed head

- `ledger-lint-selftest.sh`: **48 passed, 0 failed** (run with `CLAUDE_CODE_SESSION_ID` unset).
- `shellcheck -e SC1091,SC2015,SC2181` over both changed scripts: clean (local 0.11.0; CI's
  0.9.0 lane is green on the PR).
- CI at this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass. `pr-gates` fails on exactly one thing — the absent verdict record
  this round produces (`no committed verdict record (a file named *-503-lean-verdict.md)`).
- **Independent mutation probe of every new assertion.** 15 mutants, each applied to an
  isolated copy of the tool, each proven to differ from pristine (`cmp`) and to still parse
  (`bash -n`), scored by which selftest case id flipped: **15 killed, 0 survived.** Covered:
  the section-presence check, the empty-Surface-cell check, the uncited-`decided` check, the
  out-of-scope-reason check, the closed-enum default arm, the duplicate-`S-n` check, the
  explicit-empty-form check, the dangling-citation loop, the surface-count stdout line, the
  arity check, the prefix-boundary regex weakened to a bare prefix test, the receipt-mode gate
  leaked into default mode, and two positive discriminators (always-dangling citation, empty
  form never accepted) which killed via `(ll-o)`/`(ll-r)`/`(ll-aj)`.
- **`(ll-as)` is not vacuous.** Its fixture was linted in the other mode: the same file that
  returns rc=0 in default mode returns rc=1 with four violations under `--receipt` (blank
  Surface cell, out-of-enum disposition, duplicate `S-1`, dangling `D-9`). The mode-isolation
  case therefore discriminates "the parser is gated off" from "the parser found nothing", which
  is what it claims.

## Strengths

- The new block is a deliberate structural sibling of Open Regions — same `normalize_arity`
  discipline, same masked-pipe split, same dupe pass, same citation-resolution loop — so it
  reads as one parser rather than a second dialect, and it inherits the arity reasoning that
  comment block already earned.
- The prefix-boundary anchor (`^(enum)([^A-Za-z0-9-]|$)`) is the non-obvious detail, and
  `(ll-ao)` is the case that makes it load-bearing: without it the enum check degrades to a
  substring test and `decidedly unclear` lints clean as a decided surface.
- Scope honesty is written into the artifact itself — header comment, skill prose and spec all
  state that the inventory cannot prove the enumeration was complete, only that an unlisted
  surface becomes visible. That is the rare case of a guard documenting its own ceiling.
- `(ll-as)` chooses the malformed-on-every-axis fixture over the trivially-empty one, which is
  exactly the distinction that makes a mode-isolation case worth having.
