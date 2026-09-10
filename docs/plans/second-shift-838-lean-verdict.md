# lean review verdict — #838

verdict=needs-work
run_id: review-838-1
session_id: 41956201-cb9d-4409-9d2d-0ccaf375caad
rounds: 1
pr: #841
reviewed_head: e3cc5216ff7f4811b6f83e5c1610e2e9b3a7fc69
reviewed_patch_id: 7a6d02643dea34422bfacfd264e6fc8217e3dced
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 1 over the full branch diff (`3113cb95..e3cc5216`, 17 files, +379/−4) — `G delta 838`
printed the FULL range: nothing verifiable to inherit.

Panel: `review-toolkit:scope-completeness-reviewer` (the only subagent whose trigger fired — an
issue is referenced). Lead pass covered performance, complexity, maintainability, test coverage,
and security (its conditional did not fire: no auth/tenancy/session/upload/query-construction
surface in the diff, and the repo carries no `review-context/security-reviewer.md`). a11y and the
design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), and the spec disarms design
with `Design: none` — justified, this repo declares no `design.provider`.

Verdict: **needs-work** on two blockers. The work itself is sound: every machine-checkable arm was
probed and reds, and the three-arm guard story holds. Both blockers are in the shipped prose.

## Blockers

### B-1 — `dev-pipeline:` namespace tokens in a toolkit plugin; `lint-and-selftests` is RED at this head

`plugins/review-toolkit/skills/review-lead/SKILL.md:197-198` introduces two `dev-pipeline:`
namespace tokens into a toolkit plugin, which `docs/namespaces.md` rule 3(a) forbids:

```
197: a caller that says nothing gets the table above exactly as written. `/dev-pipeline:review` declares
198: it (its step 5); the standalone `/review-toolkit:review-lead` invocation and `dev-pipeline:pr-revision`
```

- CI, head `e3cc5216`: run `34519497176`, job `103013166937` (`lint-and-selftests`) — step
  **"namespace direction check (docs/namespaces.md rule 3)"** = `failure`; every other step in that
  job succeeded.
- Reproduced locally with the workflow's own command: the grep over the four toolkit roots returns
  exactly those two lines.
- New, not inherited: `git show 3113cb95:plugins/review-toolkit/skills/review-lead/SKILL.md |
  grep -c 'dev-pipeline:'` → `0`.

This is a red CORRECTNESS lane, not a policy gate, so it is a blocker rather than a recorded
merge-boundary refusal.

**Fix:** the same file already refers to the pipeline the allowed way twice — line 31 ("from
another skill running in the main session, e.g., dev-pipeline") and line 427 ("in dev-pipeline
`auto` mode"). Say "the pipeline review session declares it (its step 5); the standalone
`/review-toolkit:review-lead` invocation and the pipeline's `pr-revision` skill do not."
`/review-toolkit:review-lead` is a review-toolkit token and stays.

### B-2 — the documented per-ticket opt-in row is a 5-column RECEIPT row, and the committed spec's lint rejects it

Two sites, both under prose that says the row lives in the **committed spec**:

- `plugins/review-toolkit/skills/review-lead/SKILL.md:237` — under "1. **Per ticket — a Decision
  Ledger row in the committed spec.** The spec found by Process step 4 … carries a
  `## Decision Ledger` table."
- `docs/extending.md:154` — under "The **per-ticket** opt-in … a row in the committed spec's
  `## Decision Ledger`".

Both show:

```
| D-4 | review panel | security, a11y | user-answered | intent |
```

That is the **receipt** arity. `ledger-lint.sh` sets `EXPECTED_CELLS` by mode:
`COLUMN_SHAPE='4 columns: ID | Decision | Resolution | Provenance'` by default, and the
5-column `… | Kind` form only under `--receipt`. Measured — a spec carrying the documented row:

```
ledger-lint: VIOLATION: malformed ledger row (expected 4 columns: ID | Decision | Resolution | Provenance): | D-4 | review panel | security, a11y | user-answered | intent |
ledger-lint: FAIL — 1 violation(s)
```

Milestone 1 lints that section — the spec's own D-2 says so ("milestone 1 already lints that
section"). So an operator who copies the example into a spec gets a milestone-1 red; and a reader
who anchors on a 5-cell template against a real 4-cell row can fail to match it, which is a
**silently** dropped opt-in — the one failure the section's own "never silent" rule exists to
prevent, and the one this design makes expensive to notice.

The prose itself is correct and is what AC-2 requires; only the illustration is wrong, and in a
4-column row Provenance is still cell 4, so the reading rule is unambiguous.

**Fix:** drop the trailing `| intent` at both sites, or keep the 5-column form only where the
receipt is being discussed and show the 4-column spec row beside it.

## Warnings

### W-1 — #838's body was never narrowed to the ratified receipt, so the scope gate blocks every round

`scope-completeness-reviewer` returned `block` on two items (confidence 92 and 85), both accurate
readings of #838's Proposal paragraph:

1. the ticket-label carrier (`review:security`, `review:a11y`, `review:mutation`) ships nowhere;
   the new per-repo config key `reviewers.default[]` substitutes for it;
2. "the existing surface triggers stay as the *opt-in* condition's second half rather than the
   default" — the diff drops them outright (`SKILL.md:242`, "dispatched unconditionally on the
   pipeline path"). The two readings diverge on `a11y-reviewer` opted in with no glob match.

**Neither is a defect in this diff.** Both are ratified operator decisions in the pre-flight
receipt `.claude/pipeline-state/838-ledger.md`:

- D-2, `user-answered` / `intent`: "Two carriers, either selects… **No tracker label, no jira
  mirror.**"
- D-1, `user-answered` / `intent`: "Their surface triggers are **DROPPED** on the pipeline path:
  only an explicit opt-in dispatches them."

Both were written 2026-09-10 18:44Z — four minutes **before** the build claimed the ticket
(claim comment `createdAt` 2026-09-10T18:48:04Z) — and both are carried verbatim into the
committed spec's Decision Ledger, which milestone 1's `ledger-lint --reconcile` binds. A pre-flight
receipt is binding input that overrides the issue as filed, so the build built what it was told to
build.

What is unresolved is the record, not the code: `userContentEdits` on #838 is **empty** — the body
has never been edited — so it still reads the other way and will keep blocking every round of
this PR and any successor. No follow-up issue for the body-vs-receipt gate behavior exists either,
though the spec's `### Out`, the receipt's S-7 and #838's own §"Two things … 2." all promise one.
The recorded remedy is to narrow the body to D-1/D-2 rather than carry the exception. Operator
action, not build action.

### W-2 — the two carriers spell reviewers two different ways

The ledger row takes short names (`security`) and the config key takes full names
(`security-reviewer`). Deliberate and flagged — D-10 names the asymmetry and the SKILL.md
paragraph explains why ("the config key sits beside `remove[]` and is validated against the shipped
registry by the same string compare … while the ledger row is prose an operator types"). Noted
rather than contested: it is a real ergonomics cost, and the unrecognized-name rule (AC-3) is what
keeps a cross-spelled name visible instead of silent.

## Suppressed (below threshold)

- `plugins/review-toolkit/scripts/check-reviewer-references.sh:307-311` — Confidence: 45 — the
  `defaults` loop duplicates the `removes` loop rather than sharing a helper. Three lines, and the
  duplication is what makes `default[]` fail the same way `remove[]` does (D-12). Consistent.
- `docs/prose-blocker-triage.tsv:50` — Confidence: 50 — the row re-key (`pb-dd909897` →
  `pb-b9763de2`) touches a file the spec's `### In` list does not name. It is the mandated
  consequence of editing the review step's prose (ids are content-derived), and
  `bash tools/prose-blockers.sh check` is clean at this head. Not scope creep worth a finding.

## Strengths

- **The guard arms were verified, not asserted.** I probed all three independently in a throwaway
  worktree at this head, and each reds by exactly the new case: the `reviewers.default` array check
  → `✗ invalid-reviewers-default-type.json fails`; the `reviewers` key allowlist → `✗
  valid-reviewers-default.json passes`; `DEFAULT-UNKNOWN` → `FAIL (c2) default-unknown expected
  exit 1`. CI's `mutation-sweep-pr` at this head (job `103013166924`) agrees — neither new catalog
  row appears in its survivor list.
- **The name check is in the right script.** D-12's reasoning holds on inspection: `config-lint.sh`
  never reads review-lead's SKILL.md, so `default[]` gets the same type-check / name-check split
  `remove[]` already has, and the two keys now fail the same way for the same reason.
- **`default[]` stays out of the effective registry** (D-13), and the `default-green` fixture
  asserts exactly that — a `default` entry demands no consumer agent file, which is what keeps it
  from silently behaving like an `add`.
- **The trim does not touch the design-fidelity gate.** `lean-gate.sh` `design_family` / `panel_has`
  and `check-lean-chain.sh` arm 8 both key on the armed-spec case only; neither imposes a minimum
  panel breadth, so a one-reviewer `--panel` is compatible with both by construction.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `review-lead/SKILL.md:193-214` — "A caller may declare it; this skill never infers it", the three-row suppression table, "Every other row is untouched" (210), and "a caller that says nothing gets the table above exactly as written". |
| AC-2 | satisfied | `SKILL.md:224-246` names both carriers with exactly the required cells: Decision `review panel`, Resolution a comma-separated list of `security`/`a11y`/`unit-test-mutation`, Provenance `user-answered` or `user-delegated`, and "Any other provenance selects nothing". Config carrier spelled as `remove[]` spells it. The illustrative row's arity is wrong (B-2), but the normative prose is what this AC asks for. |
| AC-3 | satisfied | `SKILL.md:247-254` — "selects nobody. Name it once in the Review Summary … It is never a blocker and never a `[Coverage gap]`". |
| AC-4 | satisfied | `SKILL.md:255-262` carries the panel line and "Their Verdicts rows follow Step 4c: omitted, except `security-reviewer`, whose row reads `Lead pass — ✅/❌`". The fourth clause is D-6's "as today" — a no-change assertion; nothing in the diff alters `panel:`, and `review/SKILL.md:55` states it where `--panel` actually lives. |
| AC-5 | satisfied | `plugins/dev-pipeline/skills/review/SKILL.md:49-58` declares the panel and names both carriers and where each is read from. |
| AC-6 | satisfied | `schema/second-shift.config.schema.json` — `reviewers.default` is an array of strings with a description, `reviewers.additionalProperties` is still `false` (read back with jq), and `jq empty` on the file is clean. |
| AC-7 | satisfied | `config-lint.sh:200,204-205`; measured — the valid fixture lints clean, the non-array fixture says `reviewers.default: must be array`, the non-string-entry fixture says `reviewers.default: every entry must be a string`, and `valid-reviewers-default.json` no longer trips `reviewers: unknown keys`. |
| AC-8 | satisfied | `config-lint-selftest.sh:68-75` plus the `valid-*.json` sweep at line 28. Probed at this head: reverting the allowlist reds "✗ valid-reviewers-default.json passes"; the catalog mutant on the array check reds "✗ invalid-reviewers-default-type.json fails". |
| AC-9 | satisfied | `check-reviewer-references.sh:306-311` emits `DEFAULT-UNKNOWN: reviewers.default names '<n>' but it is not a plugin-shipped reviewer …` and exits 1; the `default-green` fixture proves silence on a registry member. The `effective_registry` computation is untouched in the diff. |
| AC-10 | satisfied | `check-reviewer-references-selftest.sh:122-140` (case `(c2)` plus `default-green`), backed by two fixtures. Probed: the catalog mutant kills by exactly "FAIL (c2) default-unknown expected exit 1". |
| AC-11 | satisfied | `docs/extending.md:149` states additive-only and re-affirms the §1 claim; `docs/extending.md:19` still reads "The two places that *can* subtract — `reviewers.remove` and `gates`". |
| AC-12 | satisfied | `onboard/SKILL.md:139-140` enumerates `.default` alongside `.add`, `.remove`, `.modelOverrides`, `.tierMap`. |
| AC-13 | satisfied | Two rows added (`config-lint-reviewers-default-type`, `reviewer-references-default-unknown`); the diff shows no other row changed. Both probed to kill by exactly the AC-8 / AC-10 cases at this head, and neither appears in CI `mutation-sweep-pr`'s survivor list (job `103013166924`). |
| AC-14 | satisfied | Cited from CI at head `e3cc5216`, run `34519497176`: job `103013166937` steps `shellcheck` = success, `validate JSON (manifests, schema, fixtures)` = success, `run all selftests` = success; job `103013167013` (`selftests (macos, bash 3.2)`) = success. Same commands, same head, so not re-run. The same job's separate namespace-direction step fails — that is B-1, and it is not one of AC-14's three oracles. |

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red at this head on its "lean chain reconciliation" step alone; reproduced locally,
the sole violation is `✗ no committed verdict record (a file named *-838-lean-verdict.md)` — the
artifact this round produces. Its frozen-files and `Changelog:` trailer steps both pass.
