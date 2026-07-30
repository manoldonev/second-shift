# Plan — intake-orchestrator internal dedup (#259)

## Context / problem framing

`plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` is loaded into the calling
session on **every** Stage-1 intake, so its prose is a per-run context cost. At the base
branch it is 468 lines / 5361 words, and four clusters within it say the same thing more
than once:

- the jira tracker delta, stated as a canonical blockquote and then re-explained at nine
  further sites;
- Step 0.5's quarantine rules, each wrapped in a rationale essay;
- the dispatch-for-real mandate — in particular its dependency-analysis-runs-inline half —
  stated four times: the top-of-file HTML preamble, the intro paragraph, Pre-flight, and
  the subroutine header;
- the merge-vs-split illustrations under Thresholds, which carry one positive example and
  five negative bullets across two lists.

This is slice 3 of 3 for the plugin-by-plugin debloat; the review-toolkit and
design-toolkit slices already landed. Only duplicated **explanation** is removed — every
operative rule keeps a home.

## Assumptions

- The prose-budget gate is a flat growth-guard, so a re-snapshot is required and a
  reduction is never itself a gate. Per-file word targets are a program-level aim.
- The base branch already carries the predecessor slice, so the shared baseline file is
  current as of `889e5f1`.
- No behavior outside this one skill file changes; the baseline row change is a derived
  measurement, not a contract edit.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What does AC-3's "audit preamble is stated once" refer to, given the preamble occurs exactly once at HEAD? | The dispatch-for-real mandate is stated three times: the HTML preamble, the Pre-flight section, and the Dependency Analysis subroutine. **Operative prose stays canonical; the HTML preamble reduces to its audit-is-observability-only sentence.** Cross-file single-homing is excluded by the ticket's own scope line and relocation guardrail; deleting the mandate outright is excluded as rule loss. | codebase-derived |
| D-2 | Does AC-1's "short tag at each write site" permit dropping operative jira rules? | No. AC-1 inherits AC-2's preservation posture: a site is reduced to a tag only **after** its unique content has been absorbed into the canonical blockquote. Three sites (Inputs, the Step 0 read path, the Tracker-body invariant) are not write sites and carry rules found nowhere else. | codebase-derived |
| D-3 | Which cluster does AC-4's "threshold worked examples" name? | The merge-vs-split illustration set. The counterfactual YES/NO bullets are the rule itself, and the two cap-driven-gaming bullets are distinct escalation triggers — both out of scope. Reduction applies to the shared-abstraction pair: one positive example, one negative. | codebase-derived |
| D-4 | Which lockstep pair binds this edit? | `decomposition-economy`, anchored **inside** the target file at the `LOCKSTEP-BEGIN/END` markers and mirrored in `decomposition-reviewer`. The AC-ID mirror the ticket's Guardrails name is anchored outside this plugin and is untouched here. The `decomposition-economy` block is not edited. | codebase-derived |
| D-5 | Is AC-2's protected set limited to "bucket, tag and posture"? | No — Step 0.5 also carries the user-guardrails-outrank-both-buckets precedence rule and the Tracker-body invariant, neither of which uses that vocabulary. Working rule: Step 0.5 loses only explanatory rationale; every imperative sentence survives. | codebase-derived |
| D-6 | D-1 was recorded at intake with the preamble as the canonical home; this plan inverts it. | Refinement in the same direction, disclosed rather than silent. Keeping mandates in operative prose (where a reader acts) and trimming the HTML comment is strictly safer than pointing operative sections at a comment. Same AC-3 outcome: the mandate is stated once. | codebase-derived |
| D-7 | AC-4 mandates exactly one negative instance, but the three "NOT a shared abstraction" bullets are distinct illustrations, so a bare count reduction is content loss. | AC-4 governs the count. The loss is neutralized rather than accepted: the surviving bullet states the discriminating principle (shared infrastructure ≠ shared abstraction) that the three instances jointly taught, so the rule survives at one instance instead of three. | codebase-derived |

## Affected files/modules

- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` — all prose edits
- `.claude/prose-budget.baseline.tsv` — whole-repo re-snapshot (AC-5)

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — the ratchet + `--update-baseline` re-snapshot; reused as-is.
- `scripts/check-lockstep-pairs.sh` — verifies the `decomposition-economy` verbatim pair; reused as-is.
- `scripts/check-intake-tracker-namespaces.sh` — asserts any file naming `mcp__atlassian__` also names `mcp__plugin_atlassian_atlassian__` and `mcp__claude_ai_Atlassian_Rovo__`; reused as-is and load-bearing for the AC-1 edits.
- `scripts/lockstep-manifest.tsv` — the pair registry; read, not edited.

No new helpers introduced.

## Implementation steps

1. **AC-1a — absorb the orphaned jira rules into the canonical blockquote.** Before touching
   any site, fold into the blockquote at the top of the file the rules that currently live
   only at their site: the `$KEY`-for-`$ISSUE_NUMBER` substitution, the no-queue-labels
   fact, the resume guards' non-applicability (all from the Step 0 read path), the
   connected-Atlassian-MCP session assumption (Inputs), the state-file-plus-brief audit
   trail, and the operator-enforced ordering with no machine gate (sub-issue creation).
   Keep all three MCP namespace prefixes in the blockquote — `check-intake-tracker-namespaces.sh`
   keys on their co-location.
2. **AC-1b — reduce each jira site to a short tag.** Step 0, the Inputs assumption, the
   Step 6 write-ops preamble, the sub-issue-creation note, the parent-update note, and
   Escalation each become a short pointer to the callout. Sites already reduced to a
   parenthetical tag stay as they are. Delete the two verbatim repeats of the
   `$GH_BOT`-convention and `requiredLabels`-override sentences, both of which the
   blockquote already states.
3. **AC-2 — trim Step 0.5 rationale.** Compress the epic-value paragraph, the
   bias-toward-quarantine essay, and the author-posture justification down to their
   imperatives. Every bucket, tag, posture, precedence and tracker-body rule survives,
   including the `AC-n` positional-fallback cross-reference to the pipeline state-schema.
4. **AC-3 — single-home the dispatch mandate.** The mandate has two halves and four homes.
   Reduce the top-of-file HTML preamble to its audit-is-observability-only sentence. The
   Pre-flight section becomes the single canonical home for both halves — do-not-inline for
   the two sub-agents, and dependency-analysis-runs-inline as its exception. The intro
   paragraph and the Step-2 bullet drop their duplicate restatements of the inline rule,
   keeping only what is unique to their position; the subroutine header keeps a bare
   runs-inline statement without re-deriving the rationale.
5. **AC-4 — reduce the merge-vs-split illustrations.** Keep one positive worked example and
   one "NOT a shared abstraction" bullet. The three negative bullets are distinct
   illustrations rather than repetitions, so the surviving bullet **carries the
   discriminating principle explicitly** (shared infrastructure is not a shared
   abstraction) instead of standing as a bare instance — AC-4's count is met without
   losing the rule the three instances jointly taught.
6. **AC-5 — re-snapshot and verify.** Run the full verification matrix below, then
   `prose-budget.sh --update-baseline` from the repo root, and diff the resulting
   `.claude/prose-budget.baseline.tsv` against the base branch. The flag is whole-repo, so
   the diff is inspected before it is committed: a row that **shrank** is a legitimate
   re-snapshot, but a row that **grew** is another file's bloat being laundered past the
   growth guard by this PR. Any grown non-target row is called out by name in the PR body
   as absorbed drift; if a grown row is unrelated to this change, its baseline value is
   restored to the base-branch figure so the guard keeps biting on it.

## Test strategy

Verify-after — this is a prose refactor with no executable behavior change. Per the repo's
testing rules, **no new selftest is written**: grepping a literal out of a markdown file
asserts only that prose contains words and cannot fail for a reason a reader of the diff
would not already see. The existing mechanical guards are the coverage:

- `check-lockstep-pairs.sh` fails if the `decomposition-economy` block drifts from its mirror.
- `check-intake-tracker-namespaces.sh` fails if the namespace co-location is broken.
- `prose-budget.sh` fails if the file grows past its baseline ceiling.

The `unitTestScope` is unset for this repo, so there is no mutation surface and the unit
test gate skips.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | jira delta stated once; write sites carry a short tag | 1, 2 | — no test (non-functional) |
| AC-2 | Step 0.5 keeps every rule; only rationale removed | 3 | — no test (non-functional) |
| AC-3 | audit preamble stated once | 4 | — no test (non-functional) |
| AC-4 | threshold examples reduced to one positive, one negative | 5 | — no test (non-functional) |
| AC-5 | baseline re-snapshot committed; selftests + shellcheck + jq green | 6 | covered-by-selftest (`prose-budget-selftest.sh`, `check-lockstep-pairs-selftest.sh`, `check-intake-tracker-namespaces-selftest.sh`) |

Unverified references: none.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-lockstep-pairs.sh .
bash scripts/check-intake-tracker-namespaces.sh .
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --report
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline
```

## Absorbed baseline drift (AC-5 guardrail)

`prose-budget.sh --update-baseline` is whole-repo, so the re-snapshot rewrote rows for files
this branch never touched. Enumerated here per the ticket guardrail — the committed record,
mirrored in the PR body:

| Baseline row | Before | After | Δ words | This branch's doing? |
| --- | --- | --- | --- | --- |
| `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` | 5361 / 37032 | 5055 / 34892 | −306 | **Yes** — the intended change |
| `plugins/dev-pipeline/skills/run/state-schema.md` | 10948 / 87798 | 11340 / 90409 | +392 | No |
| `plugins/dev-pipeline/skills/run/stages/8-code-review.md` | 3970 / 29079 | 3909 / 28596 | −61 | No |
| `plugins/dev-pipeline/skills/run/SKILL.md` | 8813 / 72466 | 8821 / 72486 | +8 | No |

The three non-target rows are **untouched base-branch content** — each was verified
byte-identical to `origin/main` (`git diff --quiet origin/main -- <path>` clean, and
`wc -w` equal to `git show origin/main:<path> | wc -w`). Their baseline rows were stale
because intervening merged PRs did not re-snapshot. All three sit inside the +5% tolerance,
so the gate reports them as warnings with zero fails.

They are **not** restored to their old figures, which is a deliberate departure from step 6's
first draft: the old figures describe content that no longer exists on the base branch, so
committing them would produce a baseline that `origin/main` itself violates. Recorded as a
deviation in the run's Stage-7 ledger.

## Risks / rollback notes

- **Highest risk: clipping a rule that sits mid-paragraph with its rationale.** Step 0.5 and
  the Step 0 read path both interleave imperatives with justification. Mitigation: the
  absorb-before-tag ordering in step 1, and a rule-by-rule read-back of the diff before
  commit.
- **Second risk: a jira rule silently losing its only home.** Mitigation: the same ordering
  — no site is reduced until its unique content is in the blockquote.
- The `decomposition-economy` block is a verbatim lockstep pair; editing it breaks the
  mirror. It sits at the run-cost-bias subsection, roughly 85 lines above AC-4's edit
  region rather than adjacent to it, so the collision risk is lower than a first read of
  the file suggests — but the constraint is unchanged. Mitigation: D-4, plus
  `check-lockstep-pairs.sh` in the matrix.
- Rollback is a single-file revert plus a baseline re-snapshot.

## Out-of-scope

- Cross-file dedup of the audit preamble (four skills carry byte-identical copies) — excluded
  by the ticket's scope line and by the relocation guardrail: skills load into separate
  contexts, so there is no loadable canonical home and any move would be drift-prevention,
  not a token win.
- The AC-ID byte-for-byte mirror in `scope-completeness-reviewer` — explicitly guarded by the ticket.
- The counterfactual YES/NO bullets and the two cap-driven-gaming triggers (D-3).
- Any change to `decomposition-reviewer` or to the lockstep manifest.
