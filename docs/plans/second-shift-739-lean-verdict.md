# lean review verdict — #739

verdict=approve
run_id: review-739-3
session_id: a8d0964a-a154-4d54-8fec-ed3b7be10216
rounds: 3
pr: #750
reviewed_head: cdd4f7751b45f58b64aa9ac15c37582820a0a860
reviewed_patch_id: 46cecaad55133b6a6b8a7817066e72c2765ce41e
inherited_patch_id: 2838072784f98adf47a8b93a423238a21da66ea8
inherited_from_verdict: 2a5073fac50a78da411685ec3ed43a998dee2c10
fidelity: not-applicable
panel: none
model: unknown
capabilities: pr-marker

# Review round 3 — PR #750 (issue #739)

Range read: `2a5073fa..HEAD` (13 files, the single fix commit `cdd4f775`), inheriting the coverage
of patch `2838072784f9` — round 2's record. Reviewed head:
`cdd4f7751b45f58b64aa9ac15c37582820a0a860`. Round 1's and round 2's findings were read first and
are reconciled below.

Panel: `scope-completeness-reviewer`, `test-coverage-reviewer`, `maintainability-reviewer`,
`complexity-reviewer` — all four returned, none dark. Lineup reduced under review-lead's prior-round
rule: security and performance have no surface in a delta of Markdown, JSON fixtures, one TSV row
and one selftest case. a11y and the design-fidelity dimension were not routed — no changed path
matches `stageParams.webComponentGlobs` (unset, so the shipped `apps/web/**/*.{tsx,jsx}` default).

**Verdict: approve.** Both round-2 blockers are fixed, and each is proved rather than argued. Two
majors, neither blocking; one suggestion; one dismissal carried from rounds 1 and 2.

## Round-2 blockers — both closed

### B-1 (AC-3) — the claude-design plan step under-specified the plan the rebased gate demands

`design-faithful/SKILL.md:55-75` now mandates the `node`/`RS`/`px` triple beside the prose
`dimensions` cell, with a two-row worked example, and states what each column is for.

Proved with the same instrument that found the defect: `_plan_table_walk`'s awk extracted verbatim
from this checkout's `lean-gate.sh`, its constants re-declared, run over

- **a plan written to the letter of the new step** (its two mandated tables, nothing else) →
  **no output, rc 0**. That is AC-3's own stated oracle, and it now holds;
- `design-faithful/SKILL.md` itself → the whole-document `no table declares a "why this component"
  column` line and nothing more — byte-identical to the control, `figma-faithful/SKILL.md`, whose
  step-7 example is the shape the gate was already known to accept.

The three violations round 2 reproduced (`declares no "node"/"rs"/"px" column`) are gone.

### B-2 (AC-6) — the eval corpus encoded the same stale grammar

All three dimensions-carrying fixtures now declare the triple, and through the same extracted
walker each emits **nothing**:

| fixture | walker output |
| --- | --- |
| `02-name-match-resolution.md` | (empty) |
| `03-unwired-state-no-analog.md` | (empty) |
| `04-control-clean.md` | (empty) |
| `01-missing-dimension-rows.md` | `no table declares a "dimensions" column` — its planted defect, unchanged |

The control's `must_not_flag` now names the triple explicitly, so the instrument no longer scores a
reviewer down for flagging a shape milestone 3 refuses. Fixtures 02 and 03 additionally gained a
`### States the spec declares` table, which is what makes their `RS` cells resolvable at all — the
fix went past the letter of the disposal there, correctly.

Every `px` cell was read against its own prose cell: `264×-` beside "fixed 264px inline, fill block",
`-×40` beside "fill inline, 40px block", `-×-` beside "fill inline, hug block". No contradiction in
any of the 16 rows, which matters because the agent's own new Warning grades exactly that.

## Round-2 / round-1 majors — all three closed

1. **The family selector's second arm had zero coverage.** `(dpr9)`
   (`lean-gate-selftest.sh:4548-4572`) drives the absent-plan path on the claude-design host and
   asserts the refusal names `the design-faithful translation-plan step`, does **not** name
   `figma-faithful step-7`, spends **0** fix attempts and makes **0** render calls. Probed for
   non-vacuity, not taken on the commit message — see Mutation evidence.
2. **AC-1's enumeration was one section short of the code.** Closed by amending the AC, which is
   the disposal round 2 prescribed: `docs/plans/second-shift-739-lean.md:23-24` now reads "the D-2
   set … plus the **placement** section D-3 makes the plan carry". The agent ships exactly seven
   checklist sections and the AC now names seven.
3. **The control fixture's ledger contradicted its own tables.** `04-control-clean.md:76` D-1 now
   resolves to "Editable in place — the handoff draws a masked field with a reveal toggle and mounts
   no Rotate affordance", which agrees with the component row (`TextField type='password'` with an
   `endAdornment`) and with RS-2's wiring row. `must_not_flag` gained a clause naming that
   agreement, so the control now defends the fix.

## Majors this round (neither blocking)

### M-1 — the agent's undeclared-`RS` bullet is graded `[Warning]` on a rationale that is false at this head

`design-faithful-plan-reviewer.md:142-144`:

> **[Warning]** an `RS` cell naming a render state the spec's own `RS-n` table does not declare.
> The row is then measured against no rendered file at all, which reads as a sized node and is not
> one.

The gate does not let that happen. `cmd_3_render` (`lean-gate.sh:4617-4626`) joins the plan's `RS`
values against the spec's declared ids and calls `fail_milestone 3` on any stray — with the comment
"Refused BEFORE the harness runs" — and `fail_milestone` calls `append_attempt`
(`lean-gate.sh:1550`). So the row is never silently unmeasured: the run reds and is charged a fix
attempt, which is *precisely* the justification the sibling bullet four lines above cites for
grading the missing-column case a `[Blocker]`. Two bullets about the same table, refused by the same
function, at two severities.

Not a blocker: the defect is still surfaced (a Warning names it), and the local ladder's own
criterion — "`Blocker` = the plan, implemented as written, produces a wrong or dead result" — is
arguably not met, since nothing wrong ships. The cost is one milestone-3 fix attempt on a
`fix-and-go`. Disposal is a severity bump and one clause, not a rewrite; the sentence to correct is
the consequence, which describes the pre-#711 world.

Its two neighbours are sound and were checked, not assumed: the `px`-shape `[Blocker]` is matched by
the gate's own `F`-class refusal (`lean-gate.sh:4457-4463`, "not `<w>×<h>`" / "axes are not each a
positive integer or `-`"), and the px-vs-prose `[Warning]` has no gate reader at all, so the agent is
correctly its only one.

### M-2 — the four new grading rules ship with no fixture exercising them (raised by `test-coverage-reviewer`, confidence 82)

None of fixtures 01-04 plants a missing `node`/`RS`/`px` column, a malformed `px`, an undeclared
`RS`, or a px/prose contradiction. `01`'s defect is a wholly absent dimensions table, which is a
different shape. Outside the literal disposal round 2 wrote, and outside AC-6, which asks that every
dimensions-carrying fixture be *conformant* — which it now is. Free to fix while the baseline is
**OWED** (D-14/OR-1), and it costs a re-reading once one is taken. Recommended as a follow-up, and
noted here so a later reader does not mistake a green corpus for coverage of these rules.

## Suggestion

`(dpr9)` makes the absent-plan step selector killable, and `tools/mutation-catalog.tsv` carries no
row for it — so the merge-time sweep still has no oracle for the arm. Row 140's own rationale is the
template. Not owed by any AC or guard, and this commit edits no guard code, so nothing was
re-anchored.

## Dismissed

**`scope-completeness-reviewer` returned a blocker on issue item 3's second clause** ("Keep a case
for a family that still has no reviewer") — the same finding rounds 1 and 2 dismissed, and the
reviewer states the dismissal path itself. Dismissed on **authority, not on merits**: D-5 and D-6
name the clause verbatim, sit in the branch's first commit (`f40b3278`, the spec commit, before the
code commit), and appear in the pre-flight ledger, which outranks the issue body. The reviewer's code
reasoning is sound and worth preserving — it independently re-proved the `*)` arm unreachable through
`design_family`. Not re-litigated.

## Mutation evidence

`mutation-sweep-pr` is green in **11s having graded nothing**, for the third round running. From the
job log of run `33444168151`:

> `[mutation-sweep] defer …/lean-gate.sh -> merge-time sweep: slow suite (…/lean-gate-selftest.sh, 212s)`
> `PR mode graded NOTHING: all 1 in-scope guard(s) deferred to the merge-time sweep, 0 swept`

So the hand probe is again the only mutation evidence. Run in an **isolated detached worktree** at
the reviewed head, never the reviewed checkout:

- **Mutant:** delete `claude-design) step="the design-faithful translation-plan step" ;;`
  (`lean-gate.sh:4263`) — the arm `(dpr9)` exists to cover. One line, verified by diff; the `*)`
  fallback then answers for claude-design.
- **Result: 588 PASS / 1 FAIL**, and the single failure is the declared killer —
  `FAIL: (dpr9) rc=1 attempts=0 renders=0`. The mutated gate still refuses, still spends no attempt,
  and names *figma's* step. Sole killer, not vacuous.
- **Unmutated at the same head: `all green`, 589/589.**

## Verification I ran, rather than cited

- `lean-gate-selftest.sh` in full at this head — **589 PASS / 0 FAIL**, `all green` (up from round
  2's 588; `(dpr9)` is the new case). Run separately because milestone 3's slow-suite table defers
  it, and with stdin closed.
- The extracted-awk probe, its `figma-faithful` control, a synthetic step-conformant plan, and all
  four fixtures — the evidence for B-1 and B-2 above.
- **Seven guards from this checkout**, all rc 0: `check-gate-buckets.sh` (310 sites / 166 rows),
  `check-lockstep-pairs.sh` (29 anchors), `check-eval-model-identity.sh` (97 files),
  `check-reviewer-references.sh`, `tools/prose-blockers.sh check` (29 constructs / 52 files / 51
  rows, zero undispositioned), `check-frozen-files.sh` and `check-changelog-trailer.sh` against
  `origin/main`.
- The three `docs/prose-blocker-triage.tsv` line anchors, each read at its stated line:
  `pb-a8f2922b` → both SKILLs' "asserted artifact" paragraph, `pb-1a8a2039` → design-faithful's
  dispatch paragraph (re-keyed 69→86 by the insert), `pb-2aea412a` → the new column `[Blocker]`.
- The spec's `## Decision Ledger` **table** is untouched this round; the amendments are prose bullets
  and AC text.

Cited, not re-run: `lint-and-selftests` (4m54s) and `selftests (macos, bash 3.2)` (7m30s), run
`33444168151`, head `cdd4f775`, both `pass` — same command and same head as the repo recipe.
`pr-gates` is red on `verdict=needs-work` from round 2's record, which is the expected pre-approve
state of the lean chain and not a finding.

## Spec amendments — checked in the direction that matters

Every AC amended this round was made **stricter**, and none was rewritten to match what the code
already did:

- AC-1 gained the seventh checklist section *and* a new obligation ("grade the `node`/`RS`/`px`
  triple, not the prose cell alone");
- AC-3 gained the three columns, a worked-example requirement, and a stated falsifiable oracle;
- AC-4 gained the second-selector coverage obligation `(dpr9)` then satisfies;
- AC-6 gained the corpus-conformance obligation;
- the notes gained a D-3 bullet deriving the columns from D-3's own "only what a reader exists for"
  rule.

AC-1's placement clause is the one amendment that follows the diff, and it is the disposal round 2
prescribed in writing after establishing that deleting the section would have produced the
mandated-element-with-no-reader defect the ticket exists to end.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Artifact-stage frontmatter, no token-arithmetic section, seven checklist sections matching the amended D-2-plus-placement enumeration. The Per-node dimensions section now grades the `node`/`RS`/`px` triple (four new rules at `design-faithful-plan-reviewer.md:134-149`). M-1 is a severity/rationale flaw inside one of those rules, not an absent one. |
| AC-2 | satisfied | `design_family_plan_reviewer()` resolves `claude-design` (`lean-gate.sh:3225-3231`); `(dpr7)` asserts rc 1, the namespaced agent name, no figma name, no decline string, 0 attempts, 0 renders. PASS in my own full run at this head. |
| AC-3 | satisfied | B-1 closed. The step mandates the triple with a worked example, and the AC's own oracle holds: a plan written to the letter of the step returns no `plan_violations` output. Control — `figma-faithful/SKILL.md` — emits the identical single whole-document line. |
| AC-4 | satisfied | `(dpr7)` inverted; catalog row 140 re-anchored and re-probed at this head (588/1, sole killer). The amended second clause is satisfied by `(dpr9)`, probed the same way. |
| AC-5 | satisfied | Both oracles re-run from this checkout: `git grep -n 'DOES NOT EXIST' -- ':!docs/plans/'` and `git grep -n 'OR-1 of' -- ':!docs/plans/'` return nothing. |
| AC-6 | satisfied | B-2 closed. All three dimensions-carrying fixtures pass the extracted walker; the control's `must_not_flag` names the triple and D-1's agreement with the component table; `check-eval-model-identity.sh` rc 0 over 97 files; `CLOSEOUT-BASELINE.md` still records the baseline as OWED. M-2 is a coverage gap for the new rules, not a corpus defect. |
| AC-7 | satisfied | The `<provider>-faithful-plan-reviewer` template survives only in `docs/plans/` records and one triage row's rationale prose — not in `build-lean/SKILL.md:27`. |
| AC-8 | satisfied | `docs/extension-points.md:20` names the agent; `evals/README.md` reads "Four eval directories" with the table row and the campaign `OWED` row present. |
| AC-9 | satisfied | `tools/prose-blockers.sh check` rc 0 — 29 constructs over 52 files, 51 rows, zero undispositioned. The three anchors this commit moves or adds each resolve to the construct they name. |
| AC-10 | satisfied | `check-gate-buckets.sh`, `check-lockstep-pairs.sh`, `check-reviewer-references.sh` all rc 0. `cdd4f775` takes `fix(design-toolkit):` with a consumer-facing `Changelog:` trailer; `check-changelog-trailer.sh` and `check-frozen-files.sh` rc 0 against `origin/main`. |

Design fidelity: **not-applicable** — the spec declares no `## Design` section and no `RS-n` render
states, so step 5b does not arm.
