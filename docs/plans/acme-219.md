# Plan — plan-lint Check 6 must tolerate formatter-owned byte differences (#219)

## Context

`plan-lint.sh` Check 6 (#190) enforces the forward direction of Decision Ledger hydration: every
`| D-n |` row in the backing `{issue}-ledger.md` must reappear in the plan's `## Decision Ledger`
with a matching Decision, Resolution, and Provenance cell. Both sides are read through `trim()`,
so the compare is **trimmed-equal** — leading/trailing padding is already neutralized, internal
whitespace is not, and nothing else is.

That makes the gate fail on byte differences nobody authored. The reported case: a backing row
written with `*object*` against a plan copy carrying `_object_` — semantically identical, and the
only way forward was to hand-edit the backing ledger to match. That inverts the intended direction:
the backing ledger is the pre-flight source of truth, the plan is the hydration target.

The issue's stated mechanism ("Stage 3 runs the consumer's configured formatter over the plan")
does **not** hold — `stages/3-write-plan.md` invokes no formatter, and `commands.<host>.format` is
resolved by `verifyctl.sh` at Stage 6, after the Stage-4 gate that runs Check 6. The bug is real
regardless: whoever authors the hydrated copy rewrites the bytes — a plan-writing agent re-typing a
row, or a repo whose own conventions mandate a markdown formatter before the advisory self-lint. The
fix does not depend on the mechanism claim, so this plan corrects the record and implements the fix.

## Assumptions

- The backing ledger and the plan are authored by different actors; formatting differences between
  them are expected, and semantic differences are not.
- `sed -E` is available on both developer machines (BSD sed) and CI (GNU sed). Both support `-E`.
- Ledgers carry a handful of rows, so per-cell subshells in the compare loop are not a cost concern.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which cells does the normalization cover | All three compared cells — Decision, Resolution, and Provenance. The issue says "byte match on the Resolution cell"; the code emits a separate violation per cell, so normalizing only Resolution would leave the same failure live on the other two | codebase-derived |
| D-2 | What does the AC-2 fixture actually guard | Internal whitespace runs, not column padding. Padding is already neutralized by `trim()` and covered by the existing `(pl-ab)` case, so a padding-only fixture would pass on unmodified code — a test that cannot fail | codebase-derived |
| D-3 | Closure of the normalization | Only whitespace and PAIRED emphasis delimiters are neutralized. Every other byte difference, GFM pipe escaping included, stays a violation. The raw-pipe-vs-escaped-pipe asymmetry is out of scope: such a backing row is already dropped by the column-count guard before Check 6 compares it | codebase-derived |
| D-4 | Emphasis folding strategy | Fold paired delimiters only via `sed -E` — `__x__` to `**x**`, `_x_` to `*x*`. A blanket underscore-to-asterisk fold would equate `snake_case` with `snake*case`; paired-only keeps single-underscore identifiers intact. Still textual, no markdown parser | codebase-derived |
| D-5 | Are the contract docs in scope | Yes. Normalizing the compare falsifies two shipped statements — the Check-6 header comment saying internal whitespace is significant, and the Stage-3 hydration contract. Both are corrected here so behavior and documented contract do not diverge | codebase-derived |
| D-6 | Where the new fixtures live | Checked-in files under `plan-lint-fixtures/`, named so the state fixture derives its sibling ledger inside that same directory. The derivation is `dirname(state)/$(basename state .json)-ledger.md`, so the pair must be `hydration.json` and `hydration-ledger.md` — mirroring the real `{issue}.json` / `{issue}-ledger.md` pairing. This satisfies the acceptance criterion literally without copying files at test time and without rewriting the existing inline Check-6 cases | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — the `norm_cell()` helper, the three Check-6
  compare sites, the Check-6 inline header comment, and the file-header check-list entry for Check 6.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` — three new Check-6 cases.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/hydration.json` `[NEW]` — the state
  fixture. Named so `basename hydration.json .json` + `-ledger.md` resolves to the file below;
  a `hydration-state.json` would derive `hydration-state-ledger.md` and silently no-op Check 6.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/hydration-ledger.md` `[NEW]` — the backing
  ledger the three plan fixtures hydrate from, resolved as the sibling of the state fixture above.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/hydration-emphasis-plan.md` `[NEW]` — AC-1.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/hydration-whitespace-plan.md` `[NEW]` — AC-2.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/hydration-wording-plan.md` `[NEW]` — AC-3.
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — the hydration contract sentence that
  currently promises a verbatim byte match.

## Reuse inventory

- `trim()` — `plan-lint.sh`. `norm_cell()` composes it rather than re-implementing the
  leading/trailing strip, so the existing padding tolerance keeps exactly one implementation.
- `make_ledger_plan()` / `make_backing_ledger()` — `plan-lint-selftest.sh`. The existing inline
  Check-6 cases keep using them untouched; the new fixture-file cases sit alongside, not on top.
- `lint_rc()` — `plan-lint-selftest.sh`. The new cases drive the lint through it like every other case.
- The `PIPE_SENTINEL` masking idiom — `plan-lint.sh`. Unchanged; `norm_cell()` runs after splitting,
  so pipe masking is unaffected.

## Implementation steps

Steps 1–3 land the tests first, so each new case is observed failing against unmodified
`plan-lint.sh` before the fix exists.

1. Add the five fixture files. The backing ledger carries three rows chosen to exercise every case:
   an emphasis-bearing Resolution, a multi-word Resolution for the whitespace case, and an
   identifier carrying **exactly one** underscore that paired folding must leave intact (a second
   underscore in that cell would pair and the invariant would be false). The three plan fixtures are
   otherwise-clean, complete plans — all ten mandated sections present, traceability rows matching
   the state fixture's AC ids, no ungrounded paths — so Check 6 is the only check that can speak.
2. Add three cases to `plan-lint-selftest.sh` under the Check-6 section, each naming the invariant it
   guards.
3. Run the three cases against unmodified `plan-lint.sh` and confirm the emphasis, whitespace, and
   wording cases are red, red, and red-for-the-right-reason respectively. A case that is already
   green here is a can't-fail test and must be re-authored before proceeding.
4. Add `norm_cell()` to `plan-lint.sh` directly below `trim()`. It trims, collapses internal
   whitespace runs to a single space, then folds paired emphasis delimiters with one `sed -E`.
   Document the closure from D-3 and the accepted `a_b_c` false-equal from D-4 in the comment above it.
5. Route the three Check-6 compares through `norm_cell()` on both sides. Keep the raw cell values in
   the violation messages so the operator still sees what they actually wrote.
6. Reword the trailing parenthetical of the three Check-6 violation messages so a reported drift no
   longer claims a verbatim byte match is required. Keep each message's leading text (`<id> Decision
   cell drifted`, `<id> Resolution cell drifted`, `<id> Provenance`) byte-stable — the existing
   selftest cases grep those prefixes.
7. Update the two contract statements from D-5: the Check-6 inline header comment in `plan-lint.sh`
   (including the file-header check list) and the hydration sentence in `stages/3-write-plan.md`.

## Test strategy

Test-first: steps 1–3 write the three fixture cases and confirm them red against unmodified
`plan-lint.sh` before the helper exists, so each case is proven capable of failing. This is the
explicit guard against the can't-fail-test class the repo's conventions call out — and it is
load-bearing here, because the AC-2 case as originally worded would have been green from the start
(D-2).

The fixtures directory has a second consumer, `scenario-liveness-selftest.sh`. It asserts the
directory exists and reads `valid-plan.md` **by name** — it does not glob — so adding files to the
directory cannot perturb it.

Coverage tier: these are per-tool behavioral cases against fixtures, so they belong in
`plan-lint-selftest.sh` next to the tool. No scenario is added to `scenario-liveness-selftest.sh`:
this change alters the comparison semantics **inside** an existing check, not the verdict path — a
Check-6 violation still fails the Stage-4 gate through the same route the liveness scenarios already
drive, so there is no new composed path for a scenario to reach. No prose-presence guard is added for
the D-5 doc edits; that class is forbidden, and the doc text is not byte-anchorable against a second
copy, so there is nothing to add to `scripts/lockstep-manifest.tsv` either.

Invariants guarded by each new case:

- Emphasis-delimiter differences are formatter-owned and must not read as drift.
- Internal whitespace runs are formatter-owned and must not read as drift.
- A genuine wording change still fails, and the emphasis fold is paired-only — a lone underscore
  swapped for an asterisk is a real difference, not a formatting one.

## Acceptance-criteria traceability

| AC ID | Criterion (short)                              | Step(s) | Test(s)                                    |
| ----- | ---------------------------------------------- | ------- | ------------------------------------------ |
| AC-1  | Emphasis-only difference passes Check 6         | 1, 4, 5 | plan-lint-selftest emphasis case (AC-1)    |
| AC-2  | Whitespace-only difference passes Check 6       | 1, 4, 5 | plan-lint-selftest whitespace case (AC-2)  |
| AC-3  | Real wording difference still fails Check 6     | 1, 4, 5 | plan-lint-selftest wording case (AC-3)     |
| AC-4  | Fixtures land in the fixtures dir and are run   | 1, 2    | all three cases above drive the fixtures   |

## Verification commands

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}`

## Risks / rollback notes

- **Over-normalization weakening the gate.** Paired folding equates `a_b_c` with `a*b*c`, because
  the interior `_b_` pairs. This is symmetric across both sides, so it can never cause a false
  failure — only a false pass, and only when one side uses underscores and the other asterisks in the
  same interior position. The wording fixture pins the boundary that matters: an identifier carrying
  a single underscore has nothing to pair with and is not folded.
- **`sed -E` portability.** Both BSD and GNU sed accept `-E`. If a consumer's environment disagreed,
  the compare would error under `set -euo pipefail` rather than silently pass — a loud failure.
- **Rollback** is reverting the commit: the helper is additive and the compare sites return to raw
  `trim()`-equality with no state or on-disk format to migrate.

## Out-of-scope

- The raw-`|`-vs-escaped-`\|` asymmetry (D-3). A backing row containing a raw pipe splits past the
  column-count guard and is dropped before Check 6 compares it — a separate pre-existing gap.
- Any other formatter rewrite class: dash and quote substitution, link-reference rewriting, line
  rewrapping. Closure is deliberate per D-3.
- `ledger-lint.sh`, which validates the backing ledger's own shape and enum and performs no
  cross-file comparison.
- The historical `docs/plans/acme-190.md` record of the original trim-only decision. It documents
  what was decided then and is not rewritten.
