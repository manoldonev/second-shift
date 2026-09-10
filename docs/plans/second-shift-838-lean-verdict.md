# lean review verdict — #838

verdict=approve
run_id: review-838-2
session_id: f3e79133-eb41-4125-af86-def6d284ac7b
rounds: 2
pr: #841
reviewed_head: 53812cc505e10ad4440c346e92673d84b60e3021
reviewed_patch_id: 9bc3c7b94c87e4e56c33555e12ceae7516c5ce29
inherited_patch_id: 7a6d02643dea34422bfacfd264e6fc8217e3dced
inherited_from_verdict: a761b6c83955a4fbcba700c23141a8d46b69c69a
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 2 over the delta `a761b6c8..53812cc5` (2 files, +5/−5, both prose) — `G delta 838` printed
that range and named the round-1 record as the inheritance source (`reviewed_patch_id`
`7a6d02643dea`). The delta is the fix commit for round 1's two blockers and nothing else.

Panel: `review-toolkit:scope-completeness-reviewer` — the only subagent whose trigger fired (an
issue is referenced; it spawns unconditionally). Lead pass covered performance, complexity,
maintainability, test coverage and security. Not-selected notes, per Step 4c:

- `security-reviewer` not selected: no auth / tenancy / session / upload / query-construction
  surface in a 5-line prose delta, and the repo carries no
  `.claude/second-shift/review-context/security-reviewer.md`. The lead pass owns the dimension.
- `a11y-reviewer` + design-fidelity not routed: no changed path matched
  `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), and the spec disarms design
  with `Design: none` — justified, this repo declares no `design.provider`.

Verdict: **approve**. Both round-1 blockers are fixed, both fixes were verified by executing the
guard that caught them, and the delta introduced nothing new.

## Round 1 blockers — both cleared

### B-1 — `dev-pipeline:` namespace tokens in a toolkit — CLEARED

`plugins/review-toolkit/skills/review-lead/SKILL.md:197-199` now reads "The pipeline's review
session declares it (its step 5); the standalone `/review-toolkit:review-lead` invocation and the
pipeline's `pr-revision` skill do not". Both `dev-pipeline:` tokens are gone.

Verified by running CI's own command from this checkout — the workflow step's exact `TOOLKITS`
array and both greps (`.github/workflows/ci.yml:176-194`):

- rule 3(a) — `grep -rn 'dev-pipeline:'` over the four toolkit roots → no match (rc 1).
- rule 3(b) — the hard-path grep → no match (rc 1).

The replacement is *stricter* than the file's own pre-existing usage, not merely compliant: lines
31 and 427 already carry a bare `dev-pipeline` (allowed — rule 3(a) matches the namespace token),
and the new wording avoids even that. The referent is not dangling: the file establishes "the
pipeline" as the caller at lines 8, 14, 35, 55 and 140, and "its step 5" resolves to a real
checklist step — `plugins/dev-pipeline/skills/review/SKILL.md:48-58` declares the panel and names
both carriers, which is AC-5.

### B-2 — the illustrative opt-in row's arity — CLEARED

Both sites now show the 4-column spec-mode row, and only the trailing `| intent` was dropped:

- `plugins/review-toolkit/skills/review-lead/SKILL.md:237`
- `docs/extending.md:154`

Measured, both directions, with the shipped linter
(`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`):

- the documented row as it now reads → `ledger-lint: 1 ledger row(s)` / `ledger-lint: OK`, exit 0.
- the row as round 1 found it (control) → `VIOLATION: malformed ledger row (expected 4 columns:
  ID | Decision | Resolution | Provenance)`, exit 1.

No site was missed: `grep -rn '| review panel |'` over `docs/` and `plugins/` returns exactly the
two fixed sites plus two occurrences inside the round-1 verdict record itself, which correctly
quote the defect as historical evidence. `plugins/dev-pipeline/skills/review/SKILL.md` describes
the carrier in prose and carries no illustrative row, so there was nothing to fix there.

Dropping the `Kind` cell loses no information: the surrounding prose at `SKILL.md:230-233` states
that the two accepted provenances are "the two `intent`-kind values of the ledger's closed
provenance enum", and in spec mode there is no `Kind` column for the cell to occupy — showing one
was the defect.

The committed spec's own ledger still lints clean at this head: `14 ledger row(s)` / `OK`.

## Warnings

### W-1 (carried from round 1, unchanged) — #838's body was never narrowed to the ratified receipt

`scope-completeness-reviewer` returned `block` on the same two items as round 1, at confidence 92
and 90, and reached round 1's disposition independently: both are accurate readings of #838's
Proposal paragraph, and neither is a defect in this diff.

1. The ticket-label carrier (`review:security`, `review:a11y`, `review:mutation`) ships nowhere;
   the per-repo config key `reviewers.default[]` substitutes for it.
2. #838's body says the surface triggers "stay as the *opt-in* condition's second half"; the diff
   drops them outright (`SKILL.md:242`, "dispatched unconditionally on the pipeline path"). The
   readings diverge on `a11y-reviewer` opted in with no glob match.

Both are ratified operator decisions in the pre-flight receipt
`.claude/pipeline-state/838-ledger.md` — D-2 and D-1, both `user-answered` / `intent` — and both
are carried verbatim into the committed spec's Decision Ledger, which milestone 1's
`ledger-lint --reconcile` binds. **A scope-gate block is overridden outright by a `user-answered`
pre-flight ledger row**, which is why this is a warning rather than a blocker, and why round 1's
classification is carried rather than escalated.

Re-verified at this head, not assumed: `gh issue view 838` shows the body still names the
ticket-label carrier and the second-half clause. The remedy is unchanged and is operator action,
not build action — narrow #838's body to D-1/D-2 with `gh issue edit --body-file`. Until then the
gate blocks every round of this PR and any successor. No follow-up issue for the body-vs-receipt
gate behavior exists yet, though the spec's `### Out`, the receipt's S-7 and #838's own
§"Two things … 2." each promise one.

### W-2 (carried from round 1, unchanged) — the two carriers spell reviewers two different ways

The ledger row takes short names (`security`), the config key full names (`security-reviewer`).
Deliberate, flagged at D-10, and explained in the shipped prose. Noted, not contested.

## Suppressed (below threshold)

- `plugins/review-toolkit/skills/review-lead/SKILL.md:197` — Confidence: 40 — "The pipeline's
  review session declares it (its step 5)" attaches a checklist step to a *session* rather than to
  the skill the session runs. The file already speaks of sessions running skills (line 14), and no
  reader is misled. Below threshold.

## Strengths

- **The fix is exactly the blocker set and nothing else.** +5/−5 across two files, both sites of
  each blocker, no opportunistic edits and no scope creep into a round whose job was to clear two
  named defects.
- **Both fixes were verified by re-running the guard that caught them**, in both directions for
  B-2 — the linter accepts the new row and still rejects the old one, so the fix is confirmed to
  be the thing that changed the answer rather than a linter that accepts anything.
- **The prose fix preserves the normative content and costs no precision.** AC-1's "a caller
  declares it, this skill never infers it", AC-2's two carriers with their exact cells, and AC-11's
  additive-only claim all survive the rewording verbatim; only the identifying token changed.
- **No collateral in the content-derived registries.** `bash tools/prose-blockers.sh check` is
  clean (29 constructs / 52 rows, zero undispositioned) even though the delta edits prose whose
  ids are content-derived, and `check-reviewer-references.sh` exits 0.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `review-lead/SKILL.md:193-214` — "A caller may declare it; this skill never infers it", "no mode sniff, no cwd test and no config flag", the three-row suppression table, "Every other row is untouched" (210), and "a caller that says nothing gets the table above exactly as written". The delta reworded only which caller declares it; the normative content is unchanged. |
| AC-2 | satisfied | `SKILL.md:224-246` names both carriers with exactly the required cells: Decision `review panel`, Resolution a comma-separated list of `security`/`a11y`/`unit-test-mutation`, Provenance `user-answered` or `user-delegated`, and "Any other provenance selects nothing". Config carrier spelled as `remove[]` spells it. Round 1's B-2 caveat is discharged — the illustrative row is now 4-column and lints clean. |
| AC-3 | satisfied | `SKILL.md:247-254` — "selects nobody. Name it once in the Review Summary … It is never a blocker and never a `[Coverage gap]`". Untouched by the delta. |
| AC-4 | satisfied | `SKILL.md:255-262` carries the panel line and "Their Verdicts rows follow Step 4c: omitted, except `security-reviewer`, whose row reads `Lead pass — ✅/❌`"; `SKILL.md:500-504` supersedes the Step 4c bullets for the three opt-in reviewers. `panel:` is stated where `--panel` lives, `review/SKILL.md:57-59`. Untouched by the delta. |
| AC-5 | satisfied | `plugins/dev-pipeline/skills/review/SKILL.md:48-58` declares the panel and names both carriers and where each is read from. Untouched by the delta; re-read at this head because B-1's fix now points at it ("its step 5"). |
| AC-6 | satisfied | Re-read at this head: `schema/second-shift.config.schema.json` → `reviewers.properties.default` is `{"type":"array","items":{"type":"string"}}` with a description, and `reviewers.additionalProperties` is `false`. `jq empty` over every `*.json` in the tree is clean. |
| AC-7 | satisfied | `config-lint.sh:200,204-205`; the AC-8 selftest exercises all three arms and passed in the sweep below. Inherited from round 1's measurement; code unchanged in the delta. |
| AC-8 | satisfied | `config-lint-selftest.sh:68-75` plus the `valid-*.json` sweep at line 28; the suite ran green in this round's own full sweep. Round 1 probed both directions with the catalog mutants applied. |
| AC-9 | satisfied | `check-reviewer-references.sh:306-311` emits `DEFAULT-UNKNOWN: …` and exits 1; re-run at this head over the real tree → exit 0 (silent on a registry-clean repo, which is the AC's second half). |
| AC-10 | satisfied | `check-reviewer-references-selftest.sh:122-140` (case `(c2)` plus `default-green`), backed by two fixtures; green in this round's sweep. |
| AC-11 | satisfied | Re-read at this head: `docs/extending.md:149` states additive-only ("can put a reviewer *into* the pipeline's panel; it can never take one out") and re-affirms the §1 claim; `docs/extending.md:19` still reads "The two places that *can* subtract — `reviewers.remove` and `gates`". |
| AC-12 | satisfied | `onboard/SKILL.md:139` enumerates `.default` alongside `.add`, `.remove`, `.modelOverrides`, `.tierMap`. |
| AC-13 | satisfied | Re-read at this head: `tools/mutation-catalog.tsv:54` (`config-lint-reviewers-default-type`) and `:68` (`reviewer-references-default-unknown`), each naming its AC-8 / AC-10 killer case. The delta touches no `.tsv`, so no existing row moved. |
| AC-14 | satisfied | **Measured at this head, not cited** — CI run `34521666447` was still `in_progress`, so the oracle was executed locally instead: the `find ... -name '*.sh'` sweep into `shellcheck -e SC1091,SC2015,SC2181` → exit 0, no output; the `find ... -name '*.json'` sweep into `jq empty` → exit 0, no output; `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` → `summary: 78 scored, 78 run, 0 served from cache, 0 failed`, exit 0. |

## Merge-boundary state (recorded, not a blocker)

`pr-gates`'s "lean chain reconciliation" step is red at this head because the committed record is
round 1's, whose `reviewed_patch_id` no longer matches the branch. That is exactly the artifact
this round produces, and it clears when this record lands. The frozen-files and `Changelog:`
trailer steps were green at the previous head and the delta touches neither a frozen file nor a
commit trailer.
