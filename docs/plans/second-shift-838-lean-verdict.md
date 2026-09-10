# lean review verdict — #838

verdict=approve
run_id: review-838-3
session_id: 96856e44-0157-4c1b-a01b-26db61b701d8
rounds: 3
pr: #841
reviewed_head: 69a902cfdfa81589ab7afceabe0c6b3a313b7e60
reviewed_patch_id: db86b87dd0584306e02077a625345b2a54b0e04c
inherited_patch_id: 9bc3c7b94c87e4e56c33555e12ceae7516c5ce29
inherited_from_verdict: 79e7db3aed7ebbd0f68b7db25816764135646a30
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 3 over the delta `79e7db3a..HEAD` — a single base-merge commit (`69a902cf`) bringing
`origin/main`'s #839 into the branch. `G delta 838` printed that range and named round 2's record
as the inheritance source (`reviewed_patch_id` `9bc3c7b94c87`). No new authored commit: the round
exists because the merge moved two of the branch's own lines.

Panel: `review-toolkit:scope-completeness-reviewer` — the only subagent whose trigger fired (an
issue is referenced; it spawns unconditionally). Lead pass covered performance, complexity,
maintainability, test coverage and security. Not-selected notes, per Step 4c:

- `security-reviewer` not selected: the delta is a base merge and a two-line TSV re-key — no auth /
  tenancy / session / upload / query-construction surface — and the repo carries no
  `.claude/second-shift/review-context/security-reviewer.md`. The lead pass owns the dimension.
- `a11y-reviewer` + design-fidelity not routed: no changed path matched
  `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), and the spec disarms design
  with `Design: none` — justified, this repo declares no `design.provider`.

Verdict: **approve**. The merge is verified clean, the one branch-owned change it forced is correct
and necessary, and all 14 ACs still hold at this head.

## What this round had to answer

`e3f9607b` (#839) renamed `lean-gate.sh` → `milestone-gate.sh`, `lean-evidence.sh` →
`boundary-evidence.sh`, `check-lean-chain.sh` → `check-lane-chain.sh` and six more, and touched
**8 of the same files this branch touches**. That is the "a base merge can red a guard neither side
fails" class, so the round was scoped to it rather than to a re-read of already-approved prose.

### M-1 — the merge preserved every one of #839's lines, with exactly one deliberate exception

Measured, not inspected. For each of the 8 shared files, every line #839 *added* was searched for
at this head:

| File | #839 additions missing at HEAD |
| --- | --- |
| `docs/extending.md` | 0 |
| `plugins/dev-pipeline/skills/review/SKILL.md` | 0 |
| `plugins/dev-pipeline/tools/config-lint.sh` | 0 |
| `plugins/review-toolkit/skills/review-lead/SKILL.md` | 0 |
| `plugins/second-shift/skills/onboard/SKILL.md` | 0 |
| `schema/second-shift.config.schema.json` | 0 |
| `tools/mutation-catalog.tsv` | 0 |
| `docs/prose-blocker-triage.tsv` | 1 — `pb-ee87cbe1`, and that one is M-2 |

The complementary direction is measured too: the branch's own contribution against main is
**byte-identical** before and after the merge — 239 added lines both sides, and a line-by-line diff
of the two contribution diffs differs in exactly the two lines M-2 describes. So the merge
reverted nothing of main's and altered nothing of the branch's beyond the re-key.

### M-2 — the content-derived prose-blocker row was correctly re-keyed, and had to be

`docs/prose-blocker-triage.tsv`'s ids are derived from the construct's content. The branch edits
`plugins/dev-pipeline/skills/review/SKILL.md:48` (AC-5) and #839 renamed that row's enforcer
(`lean-evidence.sh::scorecard` → `boundary-evidence.sh::scorecard`), so the id moved on both sides.
The merge resolved it to `pb-ee87cbe1` → `pb-77e3865d`, appending a second `Re-keyed from` clause to
the row's rationale.

Verified in both directions, in an isolated worktree cut from this head:

- as merged → `bash tools/prose-blockers.sh check` reports `29 construct(s) / 52 row(s)`,
  `✓ zero undispositioned constructs`, exit 0.
- control, with the pre-merge ids restored → `UNDISPOSITIONED … pb-77e3865d` plus
  `STALE … pb-b9763de2`, non-zero.

So the re-key is the thing that changed the answer, not a guard that accepts anything. The chained
`Re-keyed from` narrative is the file's own convention (`pb-5b044e83` carries three).

### M-3 — no stale pre-#839 grammar entered the shipped surface

`grep` over every line the branch adds outside `docs/plans/**` for `lean-gate`, `LEAN_`,
`build-lean`, `review-lean`, `run-lean`: **no match**.

Two hits do exist inside the committed spec (`second-shift-838-lean.md:231,309`, citing
`lean-gate.sh` and `check-lean-chain.sh` in D-5's rationale). Not a finding: #839 deliberately left
the old names standing in ~80 `docs/plans/**` specs and verdict records at this exact head,
including `second-shift-833-lean.md`. Plans and verdicts are records frozen at their authoring
head, not maintained pointers, and this spec is consistent with that convention rather than an
exception to it.

### M-4 — round 1's two fixes survived the merge

Both landed in files #839 also touched, so both were re-measured rather than inherited:

- **B-1** (no `dev-pipeline:` namespace token in a toolkit) — CI's own step re-run from this
  checkout, both greps with the exact `TOOLKITS` array from `.github/workflows/ci.yml:176-194`:
  rule 3(a) no match (rc 1), rule 3(b) no match (rc 1).
- **B-2** (the illustrative opt-in row's arity) — `review-lead/SKILL.md:237` and
  `docs/extending.md:154` both still carry the 4-column spec-mode row; the committed spec's own
  ledger lints clean at this head (`14 ledger row(s)` / `OK`).

## Warnings

### W-1 (carried from rounds 1-2, unchanged) — #838's body was never narrowed to the ratified receipt

`scope-completeness-reviewer` returned `block` on the same two items, at confidence 95 and 92,
reaching the prior rounds' reading independently: both are accurate readings of #838's Proposal
paragraph, and neither is a defect in this diff.

1. The ticket-label carrier (`review:security`, `review:a11y`, `review:mutation`) ships nowhere;
   the per-repo config key `reviewers.default[]` substitutes for it.
2. #838's body says the surface triggers "stay as the *opt-in* condition's second half"; the diff
   drops them on the pipeline path outright.

Both are ratified operator decisions in the pre-flight receipt
`.claude/pipeline-state/838-ledger.md` — D-1 and D-2, both `user-answered` / `intent`. D-2 settles
the first item in words (**"No tracker label, no jira mirror"**) and D-1 the second (**"Their
surface triggers are DROPPED on the pipeline path"**). **A scope-gate block is overridden outright
by a `user-answered` pre-flight ledger row**, which is why this is a warning rather than a blocker.

**Re-measured this round rather than inherited, and the prior rounds' wording is corrected.**
Rounds 1-2 recorded that both rows are "carried verbatim" into the committed spec's Decision
Ledger. Cell-by-cell they are not *identical* — the receipt row carries a trailing `Kind` cell the
spec row does not. That difference is the spec-mode arity B-2 fixed, not a drift: with the `Kind`
cell set aside, the `Decision`, `Resolution` and `Provenance` cells of D-1 and D-2 are
**byte-identical** between receipt and committed spec. The ratification the override rests on is
intact; only the earlier description of it was loose.

The remedy is unchanged and is operator action, not build action — narrow #838's body to D-1/D-2
with `gh issue edit --body-file`. Until then the gate blocks every round of this PR and any
successor.

### W-2 (carried, unchanged) — the two carriers spell reviewers two different ways

The ledger row takes short names (`security`), the config key full names (`security-reviewer`).
Deliberate, flagged at D-10, explained in the shipped prose. Noted, not contested.

### W-3 (carried, re-verified) — the t6 deferral in #838's body still links no follow-up issue

The scope gate raised this at `minor` / confidence 88 and scored it non-blocking itself: #838's
§"Two things … 2." defers the stale-body-vs-receipt gate behavior *with* rationale, which is
body-level deferral language; only the promised follow-up link is missing. Re-checked at this head,
not assumed — `gh issue list --state open` matching `stale|body|receipt|scope-completeness` returns
#838 itself and #355 (an unrelated cross-family build proof). No follow-up exists. Operator action,
and the same remedy as W-1 would carry it.

## Suppressed (below threshold)

- `docs/plans/second-shift-838-lean.md` — Confidence: 60 — the lane spec's `AC-1..AC-14` are
  build-authored and absent from the issue body, so the gate did not treat them as tracker scope
  items. Correct handling; recorded for awareness, not a finding.

## Strengths

- **The merge did the hard part correctly and did nothing else.** #839 renamed eleven files and
  touched eight this branch also touches; the resolution kept every one of main's lines, kept every
  one of the branch's, and changed exactly the one row whose id is *derived* from content both
  sides edited. That is the smallest correct resolution available.
- **The re-key is the case the content-derived registry exists to catch**, and it was caught at
  merge time rather than by CI: leaving `pb-ee87cbe1` in place reds `prose-blockers.sh` in both an
  UNDISPOSITIONED and a STALE direction, as the control probe above measures.
- **The two mutation-catalog rows still anchor after their targets were renamed.** Both `sed`
  expressions still apply at this head, so AC-13's rows predict a real kill rather than a no-op —
  the failure mode a rename most easily introduces, and the one a green sweep would not have shown.
- **The branch's contribution is provably unchanged.** 239 added lines before the merge, 239 after,
  differing in two lines with a measured reason. A reviewer inheriting rounds 1-2's coverage can do
  so on evidence rather than on the shape of the commit graph.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `review-lead/SKILL.md:193-214` re-read at this head — "A caller may declare it; this skill never infers it", "no mode sniff, no cwd test and no config flag", the three-row suppression table, "Every other row is untouched" (210), "a caller that says nothing gets the table above exactly as written". #839 touched this file; every line it added is still present (M-1) and the branch's additions are byte-identical (M-1). |
| AC-2 | satisfied | `SKILL.md:224-246` names both carriers with the required cells: Decision `review panel`, Resolution a comma-separated list of `security`/`a11y`/`unit-test-mutation`, Provenance `user-answered` or `user-delegated`, "Any other provenance selects nothing", `ticket-sourced` excluded with reason. Illustrative row is 4-column (B-2, re-verified M-4). |
| AC-3 | satisfied | `SKILL.md:247-254` — "selects nobody. Name it once in the Review Summary … It is never a blocker and never a `[Coverage gap]`". Unmoved by the merge. |
| AC-4 | satisfied | `SKILL.md:255-262` carries the mandatory panel line and "Their Verdicts rows follow Step 4c: omitted, except `security-reviewer`, whose row reads `Lead pass — ✅/❌`". |
| AC-5 | satisfied | `plugins/dev-pipeline/skills/review/SKILL.md:48-58` re-read at this head: step 5 declares the panel, names both carriers and where each is read from, and states `review-lead` never infers it. This is the file whose edit forced M-2's re-key, so it was read directly rather than inherited. |
| AC-6 | satisfied | `schema/second-shift.config.schema.json` → `reviewers.properties.default` is `{"type":"array","items":{"type":"string"}}` with a description; `reviewers.additionalProperties` is `false`. `jq empty` over every `*.json` in the tree → exit 0 (AC-14). |
| AC-7 | satisfied | `config-lint.sh:200` adds `"default"` to the `reviewers` key allowlist; `:204` types the array; `:205` rejects a non-string entry. Re-read at this head — #839 touched this file and left all three arms intact (M-1). |
| AC-8 | satisfied | `config-lint-selftest.sh:68-75` — three scenario cases (`invalid-reviewers-default-type` → "must be array", `invalid-reviewers-default-entry` → "every entry must be a string", `valid-reviewers-default` → no "unknown keys"), backed by three fixtures. Green in this round's own cold sweep. |
| AC-9 | satisfied | `check-reviewer-references.sh:306-311` emits `DEFAULT-UNKNOWN: …` and appends to `errors`; the `(c2)` contract is documented at `:38-44`. Executed at this head over the real tree → exit 0, silent, which is the AC's second half. |
| AC-10 | satisfied | `check-reviewer-references-selftest.sh:122-138` — case `(c2)` (expects exit 1 *and* a `DEFAULT-UNKNOWN` line) plus `default-green` (expects exit 0 *and* no such line), backed by two fixtures. The two directions discriminate, so the case is not vacuous. Green in the cold sweep. |
| AC-11 | satisfied | `docs/extending.md:149` — "can put a reviewer *into* the pipeline's panel; it can never take one out, and naming a subset does not drop the reviewers you left out"; `:19` still reads "The two places that *can* subtract". This file took the merge's only textual conflict resolution, so §3.3b was re-read in full, not grepped. |
| AC-12 | satisfied | `onboard/SKILL.md:139` enumerates `.default` alongside `.add`, `.remove`, `.modelOverrides`, `.tierMap`. |
| AC-13 | satisfied | **Re-probed, because #839 renamed both targets.** `tools/mutation-catalog.tsv:54` (`config-lint-reviewers-default-type`) and `:68` (`reviewer-references-default-unknown`) each still *apply* at this head — applying each row's `sed -E` expression changes its target file's hash, so neither degraded into a no-op. Each names its AC-8 / AC-10 killer case. |
| AC-14 | satisfied | **Executed cold at this head, not cited.** CI run `34526985689` (head `69a902cf`) passes `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr`, but its runner adds `--cache-dir` and reported `79 scored, 76 run, 3 served from cache` — three suites CI did not execute, so its command is not AC-14's. Run locally instead: the `find … shellcheck -e SC1091,SC2015,SC2181` sweep → exit 0, no output; `find … jq empty` → exit 0, no output; `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` → `79 scored, 79 run, 0 served from cache, 0 failed`, exit 0. |

## Merge-boundary state (recorded, not a blocker)

`pr-gates`'s "lane chain reconciliation" step is red at this head, and names its own cause exactly:
the committed record is round 2's, whose `reviewed_patch_id` `9bc3c7b94c87` no longer matches the
branch's `db86b87dd058` because "2 reviewed line(s) across 1 file(s) — docs/prose-blocker-triage.tsv"
moved. Those are M-2's two lines. That is precisely the artifact this round produces, and it clears
when this record lands.

Every CORRECTNESS lane is green at this exact head: `lint-and-selftests`, `selftests (macos, bash
3.2)` and `mutation-sweep-pr` all pass on run `34526985689`, head
`69a902cfdfa81589ab7afceabe0c6b3a313b7e60`. `install-topology` is `skipping`, per the PR-lane
exclusion. The `Changelog:` trailer and frozen-files checks are not red.
