# Intake receipt — #1035 dev-pipeline: a lane run checks twice before review starts, and review waits on the second pass

Receipt: v2

## Intake steps

Requirements: the ticket body as written — spec-reviewer: 4 gaps at first intake (no acceptance criteria, resolved by D-5; option 1's dependencies, moot under D-1; the filter selector and a narrowed build's checks, both resolved). Re-intake 2026-10-13 after #1038 split run-selftest.sh re-opened D-1, D-3, D-4 and D-5
Split: not triggered — one deliverable, no epic label
Explore: done — run.sh build_prompt, the round loop's checks block, run_checks/checks_list, the review prompt; re-checked on main at 7e120903: both option-2 targets present, eight run*-selftest.sh suites after #1038. Implementability probe: ran on the first-intake body (14 guess-points, each resolved or moot); not re-run at re-intake, because scope shrank to two prompt lines and a comment
Fan-out: skipped — by the operator at the pre-flight notice; no reason given
Dup-scan: 1 candidate at threshold 12 — #1033, overlapping file, distinct work (D-14)
Post-merge scan: no post-merge AC
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which of the ticket's options this ticket delivers | Option 2 only. Option 3 (a case filter) was dropped at re-intake: #1038 split run-selftest.sh into eight suites, so a build can already rerun just the suite it touched. Option 1 (REVIEW concurrent with the scheduler's checks) is out of scope | user-answered | intent |
| D-2 | What the build prompt tells the BUILD about checks | The list stays in the prompt, framed as what the scheduler runs at the pushed head: a red comes back as findings and spends a checks-red attempt. Before pushing, the build runs the checks that cover what it changed; a whole-list run is not required (not forbidden, so `build_allowlist` keeps granting every listed check). The scheduler's pass is unchanged and stays the authority. The comment above the round loop's checks block stops saying "the checks the build did not run" | user-answered | intent |
| D-3 | A case filter for the selftest suites | Retired at re-intake: no filter is built (D-1) | user-answered | intent |
| D-4 | A line telling a build how to iterate | One generic line in `build_prompt`, naming no repo path: while iterating, rerun only the test file or suite your change touches. No CLAUDE.md change | user-answered | intent |
| D-5 | The ticket's acceptance criteria | Rewritten at re-intake: AC-1..AC-3 match D-2 and D-4; AC-4 and AC-5 (the filter) are retired (https://github.com/manoldonev/second-shift/issues/1035) | user-answered | intent |
| D-6 | What happens to option 1 | Nothing filed; whether the remaining single pass is worth a concurrent review is judged from later runs' timings | user-answered | intent |
| D-7 | The review prompt's claim that the scheduler ran the checks before spawning it | Stays true and unedited: the scheduler's pass still precedes REVIEW — run: `grep -c 'scheduler ran them at this head before spawning you' plugins/dev-pipeline/skills/run/run.sh` → 1 | codebase-derived | fact |
| D-9 | Whether the interactive /dev-pipeline:build gets the same prompt | Yes: `build_prompt` writes the prompt before the handoff branch — run: `grep -n 'build_prompt "$ROUND"' plugins/dev-pipeline/skills/run/run.sh` → 1257, the `HANDOFF` branch at 1258 | codebase-derived | fact |
| D-10 | How a build-prompt change is guarded | A run*-selftest.sh case that greps the build prompt the fake claude received, as the existing prompt rules are — run: `grep -c 'prompt-1.txt' plugins/dev-pipeline/skills/run/run-selftest.sh` → 13 | codebase-derived | fact |
| D-12 | Test and release conventions this change follows | A behavior change to run.sh lands with a run*-selftest.sh case that fails without it; a new capability is `feat:` on the PR title; every plugins/** PR carries a `Changelog:` trailer — cited (convention): CLAUDE.md:120, CLAUDE.md:64, CLAUDE.md:35 | codebase-derived | fact |
| D-13 | The selftest layout this change lands in | #1038 split the run.sh scenario into eight suites — run: `ls plugins/dev-pipeline/skills/run/run*-selftest.sh \| wc -l` → 8 | codebase-derived | fact |
| D-14 | Dup-scan candidate #1033 (claimed, PR #1041) | Overlapping file, distinct work: #1041 edits run.sh's verdict grammar, while this ticket edits build_prompt and the round-loop comment. #1035 is queued only after #1041 merges, so the per-file staleness check cannot stop it mid-run | user-answered | intent |

D-8 and D-11 were facts about the case filter; both retired at re-intake with D-3, and their IDs are not reused.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether a build that no longer runs the whole list pushes reds more often and reaches `checks-red-spent` sooner; the checks-red cap stays at its default | reversible-default-and-flag |

OR-1's default is reversible cheaply: the cap is `run.checksRedMax` in the consumer config, so raising it is a config edit, and a build may still run the whole list when its change is broad. The build changes no cap.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The build prompt's checks paragraph | decided (D-2) |
| S-2 | The build prompt's iteration line | decided (D-4) |
| S-4 | The comment above the round loop's checks block | decided (D-2) |
| S-5 | This repo's CLAUDE.md | out-of-scope — D-4 adds no doc pointer |
| S-6 | The review prompt's line on who ran the checks | decided (D-7) |
| S-7 | The prompt /dev-pipeline:build hands the calling session | decided (D-9) |
| S-8 | The ticket's acceptance criteria | decided (D-5) |
| S-9 | The run*-selftest.sh suites and tools/run-selftests.sh | decided (D-3) |
| S-10 | The run log and terminal slugs | out-of-scope — no terminal or log line changes; OR-1 flags the checks-red rate |
| S-11 | docs/testing.md | out-of-scope — no filter or doc pointer is added (D-3, D-4) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice; no reason given
