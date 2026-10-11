# Intake receipt — #978 the AC-ID heading rule accepts a bare `## Acceptance`

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the AC-ID rule and the headings tickets use are brought into agreement | Widen the reader. AC IDs exist under the first heading whose text, case-insensitively, contains `Acceptance Criteria` or is exactly `Acceptance` (`scope-completeness-reviewer.md:63`). Every heading the rule matches today still matches; a heading such as `## Acceptance demo` still does not. Weighed: normalizing the writers and having spec-reviewer flag the bare form (the bare form comes from session-filed tickets by the operator and the app bot, which no skill in this repo writes and which never pass spec-reviewer, and the 16 existing bare-form tickets would stay un-ID'd unless amended), and both together (a Warning on a form the reader now accepts) | user-answered | intent |
| D-2 | The second reader, intake-orchestrator's single-section check | `intake-orchestrator/SKILL.md:208` stops naming one heading and refers to "the AC section heading per the rule in `scope-completeness-reviewer`", by name and not as a copy. The rule's single-site comment (`scope-completeness-reviewer.md:64-68`) asks for exactly that, and `:148` already points there the same way | codebase-derived | fact |
| D-3 | Writers | Unchanged. intake-interviewer still writes `## Acceptance Criteria` (`intake-interviewer/SKILL.md:200`), and spec-reviewer does not flag the bare form (D-1). No existing ticket is edited | codebase-derived | fact |
| D-4 | Other readers of the heading | None. A grep over `plugins/`, `scripts/`, `tools/` and `.github/` finds no script, `run.sh` line or selftest that parses the heading. Only the two prompt sites in D-1 and D-2 key on it. `run.sh:606` names acceptance criteria only in prose | codebase-derived | fact |
| D-5 | How the change is verified | No before/after replay of the scope reviewer. The edit writes down what the reviewer already does (#967's verdicts numbered #964's `## Acceptance` items AC-1..5), so a replay would most likely show the same output on both sides. The edit guards against a run that reads the regex literally, as `docs/plans/acme-68.md:97` recorded, and that is run-to-run variance a single replay does not reproduce. No selftest: a test that checks the prompt for the new wording is barred by the writing-tests rules | user-answered | intent |
| D-6 | Commit verb and trailer | `fix(review-toolkit,intake-toolkit):` on the PR title, because the written rule disagreed with what tickets use (CLAUDE.md, "Commit verbs decide the version bump"). Add a `Changelog:` trailer saying the scope reviewer numbers ACs under a bare `## Acceptance` heading too, `Migration: none` | codebase-derived | fact |
| D-7 | Duplicate scan | `dup-scan.sh --issue 978` returned 0: no candidates at or above threshold | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | AC IDs in the scope reviewer's output and the lane verdict for a ticket with a bare `## Acceptance` heading | decided (D-1) |
| S-2 | intake-orchestrator's clean-marker skip decision on such a ticket | decided (D-2) |
| S-3 | spec-reviewer findings on a bare `## Acceptance` heading | decided (D-3) |
| S-4 | Ticket bodies intake-interviewer emits | decided (D-3) |
| S-5 | The release-note line | decided (D-6) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
