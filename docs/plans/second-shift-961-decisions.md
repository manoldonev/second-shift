# Intake receipt — #961

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the clause lands | A paragraph in lead-pass Grounding right after "Producer ≠ persister" (`plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md:165-167`): for a dependency the repo does not own, the defining artifact is its published types, docs or a recorded real response, never a test double. Not mirrored into reviewer-baseline, and not added to the Silent-failure schema coupling Warning. Options weighed: Grounding only; Grounding plus a reviewer-baseline mirror; a schema-coupling sub-clause | user-answered | intent |
| D-2 | BUILD-prompt sentence | Add one sentence to the run.sh BUILD prompt next to the stored-field sentence (`plugins/dev-pipeline/skills/run/run.sh:536`), limited to error and empty paths: a test double of a dependency this repo does not own that returns an error or empty result cites where that shape comes from (the dependency's types, docs or a recorded real response). Options weighed: this sentence; review-side only | user-answered | intent |
| D-3 | Replay before shipping | No replay. The prompt change is judged in review and by later consumer reviews, as with #950 | user-answered | intent |
| D-4 | What "a dependency the repo does not own" means | Its source is not in the repo under review: a third-party SDK, an external API, or another team's service even in the same org. A workspace package in the same repo counts as owned. Same line as #950's persisted-field definition | user-answered | intent |
| D-5 | Output when no defining artifact can be opened | The existing Grounding question form, `unable to verify — pointer needed: <the dependency's types, docs or a recorded response>` (`lead-pass-checklist.md:162-163`); no new severity or label | codebase-derived | fact |
| D-6 | Guard for D-2 | A `run-selftest.sh` grep case on the round-1 build prompt (`prompt-1.txt`) for the new sentence, next to the stored-field case at `run-selftest.sh:252`; red on main because the sentence is absent (CLAUDE.md: a run.sh behavior change lands with a run-selftest case) | codebase-derived | fact |
| D-7 | Guard for D-1 | None: a checklist prose change has no script reader, and prose-presence guards are disallowed (`docs/testing.md`, writing-tests skill) | codebase-derived | fact |
| D-8 | PR form | Title `feat(review-toolkit,dev-pipeline): …`; a `Changelog:` trailer; no edits to plugin versions, `CHANGELOG.md` or marketplace `metadata.version` (CLAUDE.md) | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Review report: a finding, or a clean claim, about behavior of an unowned dependency that rests on a test double | decided (D-1) |
| S-2 | Review report: the question line when no defining artifact for the dependency can be opened | decided (D-5) |
| S-3 | The lane BUILD prompt the build session reads | decided (D-2) |
| S-4 | reviewer-baseline Grounding read by specialist reviewers | out-of-scope — not mirrored, per D-1 |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
