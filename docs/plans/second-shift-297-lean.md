# Spec — issue #297: arm the fourth spinning-idiom site, and stop reporting budget-darkness as silence

## Problem

`plugins/second-shift/skills/onboard/tools/scaffold-review-context.sh:69` carries the standard
EOF-tolerant read idiom that `cmp-z` inverts into a permanent-true clause — the mutation class that
spun a guard at 100% CPU and killed three nightly shards. The site is at `cmp-z` **ordinal 5**, and
the generic tier's per-operator budget is `MUTATION_SWEEP_K=2`, so it has never been mutated. It is
unswept for a budget reason, not a safety one.

Two consequences, and the second is the wider defect:

1. That named site is dark.
2. The report cannot say so. A guard with **no applicable site** for an operator and a guard whose
   sites all sit **beyond the budget** produce the identical report row — silence — which is what let
   this sit unnoticed until a shard death forced an audit.

Prose in `tools/mutation-sweep.sh` and `docs/testing.md` asserts the site is unarmed; landing AC-1
falsifies both.

## Binding input

`.claude/pipeline-state/297-ledger.md` (pre-flight receipt). D-1..D-10 are adopted verbatim. D-11
(the `MUTATION_SWEEP_K` budget itself) is deferred under **OR-1**, disposition
`reversible-default-and-flag`: `k` stays 2, and nothing here forecloses raising it. Out of scope by
that disposition; the `sites_beyond_budget` column this ticket adds is the standing evidence a later
decision would rest on.

## Acceptance criteria

**AC-1 — the fourth site is armed by a catalog row, not by a `k` raise.**
`tools/mutation-catalog.tsv` gains one row whose `guard` is
`plugins/second-shift/skills/onboard/tools/scaffold-review-context.sh` and whose `sed` is
pattern-addressed on `while IFS= read -r line || [ -n "$line" ]` — the guard's only `while IFS= read`
line, and the anchor that excludes the six other `-n `/`-z ` sites in the same file (lines 37, 39,
50, 58, 78, 94), any of which a looser anchor would also flip. `MUTATION_SWEEP_K` is unchanged at
its default of 2, and no baseline row is added (D-5: a spinning mutant scores KILLED by timeout, and
only survivors are baselined).

**AC-2 — the catalog's `note` contract admits a timeout-kill row.**
`tools/mutation-catalog.tsv`'s header block documents `note` as "what a survivor would MEAN". A row
whose expected verdict is a timeout-kill has no survivor to mean anything, so the header block is
amended to state the class explicitly: such a row's value is being **armed** plus **anchor-drift
LOUD** — it reds if the spinning idiom is ever refactored away — and it depends on the killer time
bound rather than on a survivor prediction. Without this amendment AC-1's row contradicts the file it
lives in.

**AC-3 — the report distinguishes "no applicable site" from "site beyond budget".**
The report TSV gains a `sites_beyond_budget` column, **appended last**. It carries per-operator
detail in the existing `paired_selftest` plus-joined style — `cmp-z:3`, `cmp-z:3+cmp-eq:1` — because
a bare count would say a guard is dark without saying of which mutation class. A site counts when
the enumeration loop declined to mutate it *solely* because the per-operator budget was already
spent; sites skipped as `bash -n`-invalid or as no-op flips are harness artifacts, not budget
darkness, and are not counted. The column is **report-only and can never red a lane** (D-3), matching
`tools/mutation-operators.tsv`'s stated posture that non-application is data.

Position is load-bearing, not stylistic (D-4): `report_row()` in `tools/mutation-sweep-selftest.sh`
parses `$5/$6/$7` positionally, and `--mode merge` compares shard report headers byte-wise — an
inserted column breaks both.

**AC-4 — the column and the row are guarded, and each new assertion is probed.**
`tools/mutation-sweep-selftest.sh` gains cases pinning that a guard with sites beyond the budget
reports `<operator>:<count>` and a guard fully within budget reports empty. Every added assertion is
probed: the probe must red the case it is meant to guard, and the probe must be shown to have
applied (a mutation that silently matches nothing scores as a vacuous green).

**AC-5 — the prose this change falsifies is corrected in the same PR.**
`tools/mutation-sweep.sh`'s spinning-idiom comment block (its "THREE live guards" table and the
sentence "The third is not safe, only out of budget: raising `MUTATION_SWEEP_K` to 5 arms it") and
the matching paragraph in `docs/testing.md` both assert this site is unarmed and name a `k` raise as
the only way to arm it. Both are updated to the state this PR lands, including the mechanism that
replaced the `k` raise. `docs/testing.md`'s account of the report TSV also names the new column and
its report-only posture.

## Out of scope

- Raising `MUTATION_SWEEP_K`, and the general question of the generic tier's per-operator budget
  (OR-1 / D-11, deferred; to be filed as a follow-up once this lands so it does not close as an
  orphan).
- Any baseline re-seed. `k` is unchanged, so the `# k=2` baseline header and the verdict cache key
  are untouched (D-6).
- The `.mjs` / `.md` / `.yml` catalog corpus (already deferred elsewhere).

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
```
