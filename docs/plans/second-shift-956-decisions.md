# Intake receipt — #956

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Detector mechanism | Widen the three built-in patterns in `review_input` (`plugins/dev-pipeline/skills/run/run.sh`): test paths anchored `(^\|/)` plus `__tests__/`, `test_*.py`, `conftest.py`, `_spec.`; skips adding `@pytest.mark.skip`/`skipif`/`xfail`, `t.Skip(`/`t.Skipf(`, `@Disabled`, `#[ignore]`, `test.todo`, `fit(`; config names adding `pyproject.toml`, `pytest.ini`, `setup.cfg`, `.coveragerc`, `Makefile`, nested `package.json`, `eslint.config.*`. Weighed: widen built-ins (ticket), a consumer-declared glob key (rejected, D-3), moving detectors to a separate script (rejected: one call site, no second reader) | user-answered | intent |
| D-2 | Broad build files (Makefile, pyproject.toml, setup.cfg) in the CI-config section | Listed on any edit, filename match only — advisory; a false positive costs a glance, a miss reads as clean evidence. Weighed: test/coverage-key line match; leaving broad files out | user-answered | intent |
| D-3 | Consumer-declared test/config globs (config key) | Out of scope — built-in patterns only; no configVersion/schema/doctor change | user-answered | intent |
| D-4 | Manual review skill parallel path | Update `plugins/dev-pipeline/skills/review/SKILL.md` step 4 in this PR: name stack-neutral idioms (pytest skip/xfail, `t.Skip`, `@Disabled`, `#[ignore]`) and add configured lanes the diff did not trigger as a question the diff must answer | user-answered | intent |
| D-5 | PR title verb | `fix(dev-pipeline): …` (patch); `Changelog:` trailer per CLAUDE.md | user-answered | intent |
| D-6 | Source of the new section **Configured lanes not run on this diff** | `config_checks` already decides each when-scoped `extraLanes` entry's hit against `$CHANGED` (`run.sh:383-404`); record the `name` of each no-hit lane (name is mandatory per `lanes_malformed`, `run.sh:374-380`) and print it, `(none)` when every lane ran; the existing all-skipped log line (`run.sh:428`) stays | codebase-derived | fact |
| D-7 | Section 1 empty form | Prints `(none)` when empty, like its siblings (`run.sh:504-508`) | codebase-derived | fact |
| D-8 | Gating | Advisory only — no section gates the run; the review reads them, as today | codebase-derived | fact |
| D-9 | Duplicate scan | `dup-scan.sh --issue 956` rc 0 — no candidates at or above threshold | codebase-derived | fact |
| D-10 | How the no-hit lane names reach `review_input` | `config_checks`' per-lane `when` match is extracted into `lane_hit`, which both `config_checks` and a new `skipped_lanes` call — one predicate, so the lanes run and the lanes listed cannot disagree. Reason: `config_checks` runs inside `$(checks_list)`, a subshell, so a name it recorded in a variable would never reach `review_input` | user-delegated | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Review input section: Deleted or renamed test files (incl. empty form) | decided (D-1) |
| S-2 | Review input section: Added skips / forced-green lines | decided (D-1) |
| S-3 | Review input section: CI or check configuration edited | decided (D-2) |
| S-4 | Review input section: Configured lanes not run on this diff (new) | decided (D-6) |
| S-5 | Section 1 empty state | decided (D-7) |
| S-6 | Manual review skill step 4 prose | decided (D-4) |
| S-7 | Scheduler log line when every lane is skipped | decided (D-6) |
| S-8 | Consumer config / schema / doctor output | out-of-scope — no config key is added (D-3) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
