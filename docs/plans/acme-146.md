# Plan — #146: persist the Stage-9 run report to disk

## Context / problem framing

The run report is the only artifact the operator reads per run, and it is the one artifact
with no durability guarantee: it exists solely as streamed model output at the end of Stage 9.
When the API connection drops mid-response, the report is gone and the log reads as total
failure for a run that shipped.

Two runs on 2026-07-20 demonstrate it: `issue-105.log` and `issue-110.log` each contain nothing
but two `strictTypes` warnings and `API Error: Connection closed mid-response`, while PR #132
and PR #144 respectively were opened and merged.

**Root-cause correction (intake finding).** The issue's "Aggravating detail" attributes #105's
stuck `"status": "in_progress"` to the state write being "not reliably ordered against the
narration". That is not what happened. Verified against the artifacts in the main checkout:

- `.claude/pipeline-state/105-eval.json` does not exist, and `105.json` carries
  `stages.9.status: "in_progress"`.
- [`statectl.sh`](../../plugins/dev-pipeline/skills/run/statectl.sh) `require_eval_file` refuses
  the terminal `completed` write when the self-eval is missing, and
  [`stages/9-open-pr.md`](../../plugins/dev-pipeline/skills/run/stages/9-open-pr.md) requires the
  eval write to precede `mark-completed`.
- `110-eval.json` exists and that run reached `completed`.

So #105's state file is an accurate record of where the session died — before the eval write —
not a mis-ordered one. Both runs died in the Stage-9 tail and differ only in how far they got.
There is no ordering bug. This matters for placement: the report write must land **early** in the
Stage-9 tail, because the #105-class death happens before the eval write.

**Mechanism correction (intake finding).** Direction (1) in the issue frames the fix as
"persist it before streaming it", premised on the narration being "composed before it is emitted".
That premise is false for streamed model output — there is no pre-composed buffer to flush ahead
of emission. The fix is therefore a **new explicit file-write step**, with the terminal narration
becoming an echo of the written file. Not a reordering of an existing compose/emit pair.

## Assumptions

- The pipeline stages are prose contracts executed by the model; a prose-only instruction has no
  enforcement. The repo's established remedy is a `statectl` refusal
  ([`pipeline-retro/SKILL.md`](../../plugins/dev-pipeline/skills/pipeline-retro/SKILL.md) names
  "statectl precondition on evidence shape" as the cheapest enforcement route), which is why this
  plan pairs the prose step with a gate rather than shipping prose alone.
- `.claude/pipeline-state/` is already gitignored, so a new artifact there dirties no tree.
- The report is operator-facing narrative, not machine-consumed state. No schema beyond a
  presence/non-triviality check.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Scope to issue direction (1) only; defer (2) and (3) | codebase-derived | (2)'s premise is disproven above — the state file is accurate, so there is no mis-ordering to reconcile. (3) has no owning component inside the plugin: the `wave1-logs/*.log` captures are operator-side terminal redirection, and a session killed mid-response has no execution point left to self-annotate. |
| D-2 | Report path is `.claude/pipeline-state/{issue}-report.md` in the MAIN checkout | codebase-derived | Mirrors the `{issue}-brief.md` lifecycle: main repo (not the worktree) so it survives Stage-10 cleanup, under an already-gitignored dir. A report written inside the worktree would be deleted by cleanup — reintroducing the exact durability gap this issue is about. |
| D-3 | Write the report immediately after `pr-add`, not just before `mark-completed` | codebase-derived | The #105-class death occurs before the eval write. Placing the write at the earliest point where the PR URL exists covers both observed failures; the later placement covers only #110. |
| D-4 | Enforce with a `mark-completed` refusal, mirroring `require_eval_file` | codebase-derived | Prose alone is exactly the class of contract that silently does not happen. The eval gate is the working precedent, and it is already selftest-covered. |
| D-5 | The report states what had not yet run at write time | codebase-derived | Because of D-3 the report predates the cost block, eval and completion write. Naming those as outstanding makes a truncated run self-describing from inside the plugin — the property issue direction (3) wanted, without owning the operator's log. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — new report-write sub-step + template
- `plugins/dev-pipeline/skills/run/statectl.sh` — `require_report_file` gate on `mark-completed`
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — gate coverage
- `plugins/dev-pipeline/skills/run/state-schema.md` — artifact entry + terminal-gate prose
- `plugins/dev-pipeline/skills/run/SKILL.md` — Run report contract alongside Post-Run Eval

## Reuse inventory

- `require_eval_file` (`statectl.sh`) — the shape the new `require_report_file` [NEW] mirrors
  (existence check + a plausibility check that defeats `touch`).
- `state_path` (`statectl.sh`) — resolves the state file honoring `paths.pipelineStateDir` and
  ticket-key lowercasing; the report path derives from `dirname "$(state_path "$key")"`, exactly
  as `require_eval_file` derives the eval path.
- `cmd_mark_completed` (`statectl.sh`) — existing call site for the terminal gates.
- No new helpers introduced beyond `require_report_file`.

## Implementation steps

1. `statectl.sh` — add `require_report_file <key>` next to `require_eval_file`: resolve
   `{dir}/{lower}-report.md`, refuse when missing, and refuse when it lacks the
   `<!-- dev-pipeline-report -->` marker or carries no prose beyond it (the `touch` defeat).
   Error text names the path and the authoring step, matching the eval gate's tone.
2. `statectl.sh` — call it from `cmd_mark_completed` alongside `require_eval_file`, and extend
   the header comment block (lines ~22–24) that documents the terminal gates.
3. `stages/9-open-pr.md` — insert the **Run report** sub-step immediately after the `pr-add`
   block, with the report template and the explicit statement that the terminal narration is an
   echo of this file.
4. `state-schema.md` — add `{issue}-report.md` to the artifact documentation and extend the
   `mark-completed` terminal-gates paragraph with gate (c).
5. `SKILL.md` — document the Run report next to Post-Run Eval, and note it in Known Limitations
   where the streamed-output fragility currently goes unmentioned.
6. `statectl-selftest.sh` — add the gate cases.

## Test strategy

Verify-after (infra/contract change, no runtime behavior in a product surface). The enforcement
lives in `statectl.sh`, which has an existing selftest harness; the prose changes are contract
text with no executable surface.

Selftest cases to add:

- `mark-completed` refused when `{issue}-report.md` is absent (eval present, all stages complete)
- `mark-completed` refused when the report exists but is empty / marker-less (`touch` defeat)
- `mark-completed` succeeds when both the eval and a well-formed report are present
- the report gate is not bypassed by `--force`

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

The Stage-1 intent snapshot carried no acceptance criteria (the issue has no
`## Acceptance Criteria` heading), so the table is intentionally empty per the AC-ID positional
fallback rule.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **A new fail-closed gate can strand runs.** A run that opens a PR but dies before the report
  write now cannot reach `completed` — the same failure mode #105 already exhibits via the eval
  gate, so this adds no new class, and D-3's early placement makes the window smaller than the
  eval gate's. `--force` does not bypass it (matching the eval gate), so the documented recovery
  is to write the report and retry.
- **In-flight runs on the installed plugin cache** keep the old contract until refreshed; the gate
  only fires on runs using the new `statectl.sh`.
- Rollback is removing the `require_report_file` call from `cmd_mark_completed`; the prose and the
  artifact are inert without it.

## Out-of-scope

- Tracker reconciliation on resume (issue direction 2) — premise disproven above.
- Self-describing truncated operator logs (issue direction 3) — no owning component inside the
  plugin; partially subsumed by D-5.
- Backfilling reports for the already-lost #105 / #110 runs.
- The adjacent `Connection closed mid-response` handling in schema'd dispatches (#82) and the
  wall-clock ceiling burn (#106 run).

Unverified references: none.
