# Pre-flight receipt — #886: the intake receipt carries the checks and the design frames

Hand-written 2026-09-23 (the intake producer this ticket adds does not exist yet). Sizing: `opus`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the two sections' contract is stated | `interviewing-baseline/SKILL.md` is the canonical receipt contract (its own header says so); `plan-interview/SKILL.md` adds only the elicitation steps; `ledger-lint.sh --receipt` enforces the shape. Mirrors stay in lockstep via the existing `LOCKSTEP-BEGIN` markers | codebase-derived | fact |
| D-2 | Whether `## Checks` is mandatory in receipt mode | Yes, with an explicit empty form, exactly as Open Regions and Surface Inventory are handled (an absent section is a silent claim that nothing beyond the configured lanes verifies this change) | codebase-derived | fact |
| D-3 | When `## Design frames` is required | Only when the repo's config sets `design.provider` (the scheduler's `env-design-undeclared` rule, #881 D-4); the lint reads the same config the scheduler does (`SECOND_SHIFT_CONFIG`, else `<repo>/.claude/second-shift.config.json`) | codebase-derived | fact |
| D-4 | The heading rule | The gate's, kept by the scheduler: exact title, any depth, case-insensitive, any heading closes, first section decides; `## Design` accepted as well as `## Design frames` | codebase-derived | fact |
| D-5 | The `must-show` value's form | Free text, non-empty (#881 ledger D-4: "a data-test id or a copy string taken from the frame"); the lint checks presence only, the skill text carries the guidance | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The lint's violation text for each new rejection | decided (D-2, D-3) |
| S-2 | The receipt template the interviewer writes (section order, empty forms) | decided (D-1) |
| S-3 | This repo's own receipts under `.claude/pipeline-state/` | decided (D-2 — they gain `## Checks`; gitignored) |

## Checks

- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`
- `find plugins/intake-toolkit -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
