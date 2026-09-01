# #760 — the scorecard's write-time entry point is dark in its paired suite

A merge-time mutation sweep filed
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh::cmp-eq::a6021e53b187` as a survivor
absent from `tools/mutation-baseline.tsv`.

## Problem

The survivor is `lean-evidence.sh:459`, `if [ "$PRINT_SCHEMA" -eq 1 ]; then` → `-ne 1`. Both arms
of the flip are live defects:

- `scorecard --print-schema` falls through to the argument checks and envfails `rc=2` with empty
  stdout, so `lean-gate.sh`'s refusal quotes an empty schema at the reviewer.
- `scorecard --spec … --verdict …` prints the schema and exits 0 whatever the body says, and
  `lean-gate.sh` reads those five lines as scorecard violations — refusing every verdict write
  while the reconciliation it is refusing on never runs.

The root cause is a pairing gap rather than a weak assertion. `lean-evidence.sh`'s kill set is its
directory-scoped same-stem suite alone — it has no `tools/mutation-pair-map.tsv` row — and
`lean-evidence-selftest.sh` invokes only `--help`, `all`, `check` and `classify`. Its `(sc1)`–`(sc16)`
block reaches `ac_scorecard_violations` through `all`, entering below the dispatch at line 455 and
never touching line 459. The `scorecard` subcommand is exercised only by `lean-gate-selftest.sh`,
which is not in the kill set.

## Approach

Add a case block to `lean-evidence-selftest.sh` that invokes `lean-evidence.sh scorecard`
directly, covering the entry point rather than only the reported site: the schema arm, the two
reconciliation outcomes, and the dispatch's own argument refusals. `lean-evidence.sh` is not
edited — the defect is coverage, not behavior.

The schema arm is asserted against the production constants themselves, sourced out of the tool
the way `(dd)` already sources `LEAN_OUTPUT_DISPOSITIONS`, so the case is an oracle rather than a
second copy of the schema text.

## Acceptance criteria

- **AC-1**: `lean-evidence-selftest.sh` gains cases that invoke `bash lean-evidence.sh scorecard`
  directly. Before this change the suite invokes that subcommand zero times; after it, every arm
  of the `SUB = scorecard` dispatch is reached: `--print-schema`; a conforming body; a
  contradictory body; `--spec` absent; `--spec` naming a path that does not exist; `--verdict`
  outside the two-value enum.
- **AC-2**: `--print-schema` exits 0 and prints a schema naming `AC_SCORECARD_HEADING`,
  `AC_SCORECARD_COLUMNS` and every value of `AC_SCORECARD_SCORES`, each read out of
  `lean-evidence.sh` at run time rather than restated in the suite.
- **AC-3**: the reconciliation arm asserts this entry point's own contract, which is not the
  boundary's: a contradictory body prints the violation and **still exits 0** — the writer's
  caller decides what a violation costs — where the same contradiction through `all` exits 1.
- **AC-4**: the three argument refusals each exit 2 and name what was wrong on stderr.
- **AC-5**: the kill is demonstrated by probe, not inferred. In an isolated copy of the tree,
  `-eq 1` → `-ne 1` at line 459 makes `lean-evidence-selftest.sh` exit non-zero and the record
  names which of the new cases failed; restoring the line returns it to green. The probe's
  transcript is quoted in the PR body, because this guard is deferred off the PR lane and a green
  CI run proves nothing about the kill.
- **AC-6**: nothing else is touched. `lean-evidence.sh` is unedited; no row is added to
  `tools/mutation-baseline.tsv`, `tools/mutation-pair-map.tsv`, `tools/mutation-catalog.tsv` or
  `tools/selftest-cache-inputs.tsv`; `scenario-liveness-selftest.sh` is unchanged. The new cases
  reuse the suite's existing fixture tree — `$SPEC` and the `SC_HDR` body — and add no new one.
- **AC-7**: the new cases sit in their own case block with their own case-id prefix and their own
  header comment naming the reader they drive, rather than being appended to the `(sc)` block,
  whose header scopes it to the merge boundary.
- **AC-8**: `bash plugins/dev-pipeline/skills/build-lean/lean-evidence-selftest.sh` exits 0, and
  the repo's cold verification recipe — shellcheck, `jq empty`, and
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  — is green.
- **AC-9**: the PR body flags OR-1's gap — that a guard can carry entry points its kill set never
  invokes, and the pair map enforces only that *a* killer exists.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Discharge the survivor by killing it, baselining it, or re-pairing the guard | Kill it with new cases in the paired suite `lean-evidence-selftest.sh`. Not a `mutation-baseline.tsv` row (writing-tests defines one as recording a site unkillable *by construction*, and this one is trivially killable), and not a `mutation-pair-map.tsv` row to `lean-gate-selftest.sh` (212s vs 26s: ~40min added to the merge sweep across ~11 mutants, and the paired suite would stay blind to the entry point) | user-answered |
| D-2 | Coverage scope of the new cases | The whole `scorecard` entry point, not only the reported site: `--print-schema` prints the schema and exits 0; `--spec`/`--verdict` is silent on a conforming body and names the violation on a contradictory one; the missing-`--spec` and bad-`--verdict` envfails. `k=2` mutated only 2 of the guard's 5 cmp-eq sites, so the reported id is the site that got picked, not the only exposed one | user-answered |
| D-3 | Whether the new coverage also earns a `tools/mutation-catalog.tsv` row | No row. The generic tier already grades this line on every merge sweep, and the existing `lean-evidence.sh` catalog rows all anchor arms a blind sed cannot express — this one is expressible generically. A row here would also have no PR oracle, since the guard is slow-deferred | user-answered |
| D-4 | Whether BUILD must demonstrate the kill | Yes, by probe: apply the exact cmp-eq flip to line 459 in an isolated copy, run `lean-evidence-selftest.sh`, require it red and name the failing case; restore and require green. The guard is deferred off the PR lane, so CI green on the PR proves nothing about the kill | user-answered |
| D-5 | Whether `lean-evidence.sh` itself is edited | Not edited. The defect is coverage, not behavior — the guard's `scorecard` dispatch is correct. Keeping it untouched also avoids the re-anchor obligation writing-tests puts on any edit to a guard's code | codebase-derived |
| D-6 | Fixtures for the new cases | Reuse what the suite already has: `$SPEC` (`$TREE/docs/plans/acme-42-lean.md`, declaring exactly `AC-1`, per the suite's own line 1043 comment) and the `SC_HDR` scorecard body block. No new fixture tree | codebase-derived |
| D-7 | Where the cases sit and how they are labelled | Their own case block with its own prefix and header comment, not appended to `(sc)`. That block's header scopes it to "#622: the per-AC scorecard, at the merge boundary", and these cases drive the write-time layer — a different reader | codebase-derived |
| D-8 | Whether this extends `scenario-liveness-selftest.sh` | No. writing-tests obliges a scenario extension for a *new* gate contract; #622 shipped the contract and `8200f1c3` already extended the scenario. This adds per-tool coverage of an existing entry point | codebase-derived |
| D-9 | Whether `tools/selftest-cache-inputs.tsv` needs a change | No. `lean-evidence-selftest.sh` has no row there, so it never participates in the pass cache and declares no inputs to keep current | codebase-derived |
| D-10 | Commit verb and changelog trailer | `test:` (patch bump per CLAUDE.md's verb table) with the trailer exactly `Changelog: none` and no prose after it — the change is not consumer-visible, and trailing prose renders into the release notes even though the presence-only gate passes | codebase-derived |
| D-11 | Whether the pair-map's completeness axis is audited here | Deferred under OR-1 (owner: operator; resolve when the next merge-sweep survivor of this shape lands, or sooner by choice). The universe rule enforces that *a* killer exists, never that the killer reaches every entry point of its guard | deferred |
| D-12 | Build model for the handoff | `opus`. The receipt leaves nothing architectural open, but the deliverable is not a prose diff: it is new cases in a bash-3.2 selftest under writing-tests' scenario-first and no-mirror-harness rules, and D-4 obliges a mutation probe — an operation this repo has recorded three distinct ways to run vacuously (restored tree under the probe, probe outside the repo, wrong worktree). Precedent agrees: the comparable bot-filed sweep-red defects #663 and #585 both ran `opus` | user-answered |

Carried forward from the pre-flight receipt with no departures.

## Notes taken from the code, not decided here

- `tools/selftest-suite-timings.tsv` already carries a row for this suite (26s, 2026-08-21). That
  file's header obliges a re-measure when a listed suite's work changes, so the row is re-measured
  and rewritten only if the added cases move it across a consumer threshold (9s for
  `run-selftests.sh` and `check-sweep-bound.sh`, 5s for `mutation-sweep.sh`) or by more than the
  20% allowance. A single sample on a contended machine is otherwise a worse number than the one
  already there.
- AC-1's fifth arm — `--spec` naming a path that does not exist — is inside D-2's "the whole
  `scorecard` entry point" but is not one of the four arms its Resolution enumerates. It is one
  line of the same dispatch and one case; it is named here so the widening is visible rather than
  discovered in the diff.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether other guards carry entry points dark in their paired suite — the completeness axis the pair map does not enforce | reversible-default-and-flag |

Carried unresolved from the receipt, at its recorded default: the audit does not run in this
ticket, and the gap is flagged in the PR body (AC-9). Reversing that stays cheap — it is a
read-only sweep comparing each guard's dispatched subcommands against what its kill set invokes,
and nothing in this diff constrains how or when it runs.
