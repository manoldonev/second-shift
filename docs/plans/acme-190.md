# Plan — plan-lint must hard-verify pre-flight ledger hydration (#190)

## Context / problem framing

Stage 3 mandates hydrating a pre-flight `/plan-interview` ledger
(`.claude/pipeline-state/{issue}-ledger.md`) into the plan's Decision Ledger section
**verbatim** (`plugins/dev-pipeline/skills/run/stages/3-write-plan.md`). Nothing
machine-checks this. `plan-lint.sh` Check 4 only gates the *reverse* direction —
human-attributed provenance rows require the backing ledger to *exist* (existence-only,
never content). So a run that ignores an existing pre-flight ledger, or drifts from its
recorded resolutions, passes every gate; only `pipeline-retro`'s post-hoc audit notices.

This change teaches `plan-lint.sh` the forward direction: when a backing ledger with
material rows exists, its `D-n` rows must be hydrated into the plan with matching
Provenance and Resolution. Violations route through the existing Stage-4 hard gate
(`plan-structure-invalid`) — no new failure reason.

## Assumptions

- The issue names this "Check 5", but `plan-lint.sh` already ships a Check 5 (the `[NEW]`
  grounding-tag gate from #175, `plugins/dev-pipeline/skills/run/tools/plan-lint.sh:208`).
  The new gate is therefore numbered **Check 6**; semantics are exactly the issue's intent.
- The backing ledger is authored by `/plan-interview` per the canonical
  `ID | Decision | Resolution | Provenance` schema, validated pre-flight by
  `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`. Check 6 relies on
  that pre-flight validation for the backing file's shape/enum legality and only checks
  *hydration completeness*, not re-validating the backing ledger itself.
- macOS ships bash 3.2 → no associative arrays; Check 6 uses parallel indexed arrays, the
  file's existing idiom.

## Decision Ledger

_No pre-flight `/plan-interview` ledger exists for #190; rows authored in-pipeline,
codebase-derived only (autonomous contract forbids human-attributed provenance)._

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Number of the new check | Check 6 — Check 5 is already the `[NEW]` grounding-tag gate (#175); the issue's "Check 5" name predates it | codebase-derived |
| D-2 | Hardness scope of the missing-section rule | Hard only when the backing ledger carries at least one `D-n` row; an empty-form / zero-row backing ledger keeps the section advisory, preserving `pl-o` and AC-2 byte-identity | codebase-derived |
| D-3 | Whitespace normalization for the Resolution compare | `trim()` leading/trailing only (existing helper, `plan-lint.sh:60`); internal whitespace significant — neutralizes prettier per-table column padding | codebase-derived |
| D-4 | Cell-location rule for the plan/ledger compare | Positional per the canonical `ID / Decision / Resolution / Provenance` schema (`ledger-lint.sh:60-68`) that verbatim hydration preserves: cells[3]=Resolution, cells[4]=Provenance | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — the new Check 6 block + the
  header check-list comment + the `SECTIONS`-array anti-resync guard comment (`plan-lint.sh:74`).
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` — new Check-6 cases.
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — the Decision Ledger bullet's
  advisory-tier wording becomes now-conditional.

## Reuse inventory

- `trim()` — `plan-lint.sh:60`. Reused verbatim for the Resolution/Provenance compare (D-3).
- `LEDGER_FILE` derivation — `plan-lint.sh:175-176` (sibling-of-state-path). Reused by
  Check 6; not re-derived.
- Pipe-mask + `IFS='|' read -r -a cells` row parse — `plan-lint.sh:180-181` /
  `ledger-lint.sh:58-59`. Reused to parse both the backing ledger and the plan's `D-n` rows.
- Decision-Ledger section-presence grep — `plan-lint.sh:244`. Reused for the
  missing-section check.
- `make_ledger_plan()` selftest helper — `plan-lint-selftest.sh:155`. Extended by the new
  cases rather than duplicated.
- No new helpers introduced.

## Implementation steps

1. Extend `plan-lint.sh` with a **Check 6** block, positioned after Check 5 and before the
   advisory Decision-Ledger-presence check. When `$LEDGER_FILE` is empty or absent → no-op
   (behavior unchanged). Otherwise parse the backing ledger's `D-n` rows into parallel
   indexed arrays (id / resolution / provenance, each `trim()`-ed).
2. When the backing ledger has zero `D-n` rows → no-op (empty-form / zero-row backing, D-2).
3. When the backing ledger has at least one `D-n` row: if the plan has no Decision Ledger
   section (reusing the section grep) → one named violation. Then parse the plan's `D-n`
   rows the same way and, per backing id: a missing plan row, a differing Provenance, or a
   differing (trimmed) Resolution each becomes one named violation citing the `D-n` id.
4. Refresh the header `# Checks` comment block to document Check 6, and reword the
   `SECTIONS`-array anti-resync guard comment (`plan-lint.sh:74`) to state the
   now-conditional hardness (section still out of the unconditional `SECTIONS` array —
   `pl-l` invariant holds — but hydration is hard when a backing ledger carries rows).
5. Reword the Decision Ledger bullet in `stages/3-write-plan.md` from flat
   "advisory-tier" to the conditional rule: advisory absent a backing ledger, hard when a
   pre-flight ledger with material rows exists.
6. Extend `plan-lint-selftest.sh` with the Check-6 cases (below).

## Test strategy

Verify-after (shell gate change; no product behavior). Coverage via
`plan-lint-selftest.sh` new cases, each asserting rc + a named violation where applicable:

- `pl-v` hydrated-ok: backing `D-1`,`D-2` + verbatim plan rows → rc 0.
- `pl-w` missing `D-n` row: backing `D-1`,`D-2`; plan omits `D-2` → rc 1, names `D-2`.
- `pl-x` mutated provenance: plan `D-1` provenance differs → rc 1, names `D-1`.
- `pl-y` drifted resolution: plan `D-1` resolution differs → rc 1, names `D-1`.
- `pl-z` missing section with a backing ledger (>=1 row) → rc 1, names the missing section.
- `pl-aa` no-backing-file unchanged: plan with ledger rows, no backing file → rc 0.
- `pl-ab` padding-only resolution difference (prettier column padding) → rc 0 (trim, D-3).
- `pl-ac` empty-form backing ledger (zero `D-n` rows) + plan without the section → rc 0 (D-2).

AC-2 byte-identity is covered by the whole existing corpus (`pl-a`..`pl-u`, `pl-n1`..`pl-n5`)
staying green.

Unit test surface: `commands.second-shift.unitTestScope` is `null` → no mutation surface → skip.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Backing ledger present: omit/mutate/drift/missing-section fails plan-lint with a named violation, Stage-4 stops | 1, 3 | `plan-lint-selftest.sh` `pl-w`/`pl-x`/`pl-y`/`pl-z` |
| AC-2 | No backing ledger: output byte-identical on the existing selftest corpus | 1, 2 | `plan-lint-selftest.sh` `pl-a`..`pl-u`, `pl-aa`, `pl-ac` |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **False positives from column-order variance** (spec-reviewer #1): the positional parse
  (D-4) assumes the canonical schema. A plan that reorders its Decision Ledger columns
  while claiming verbatim hydration is itself a drift, so a violation there is correct, not
  a false positive — documented in the Check 6 comment.
- **Regressing the existing corpus** (AC-2): mitigated by the zero-row no-op (D-2) and by
  running the full selftest in verification. Rollback is a single-file revert of
  `plan-lint.sh` (the doc/test edits are inert without it).

## Out-of-scope

- Editing `ledger-lint.sh` or `interviewing-baseline` (canonical schema unchanged; Check 6
  compares rather than re-enumerates provenance, so no enum lockstep burden).
- Any new `failureContext.reason` (violations reuse `plan-structure-invalid`).
- Re-validating the backing ledger's own shape/enum (owned by pre-flight `ledger-lint.sh`).
