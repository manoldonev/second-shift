# Intake receipt — #1035 dev-pipeline: a lane run checks twice before review starts, and review waits on the second pass

Receipt: v2

## Intake steps

Requirements: the ticket body as written — spec-reviewer: implementable once intake chose an option; 4 gaps: no acceptance criteria (resolved by D-5, AC-1..5 appended), option 1's unstated dependencies (moot under D-1), no case selector in run-selftest.sh (D-3), what a narrowed build still runs (D-2)
Split: not triggered — one deliverable, no epic label, 6 material decisions
Explore: done — run.sh build_prompt, the round loop's checks block, run_checks/checks_list, bounded/reap, the review prompt; run-selftest.sh's flat case layout; the repo's commands config; check timings of past lane runs (36 s to about 14 min); implementability probe: 14 guess-points, each resolved by D-1..D-4, D-8 or D-10, or moot under D-1
Fan-out: skipped — by the operator at the pre-flight notice; no reason given
Dup-scan: no candidates at or above threshold 12
Post-merge scan: no post-merge AC
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which of the ticket's options this ticket delivers | Options 2 and 3. Option 1 (REVIEW concurrent with the scheduler's checks) is out of scope. Option 3 is the filter for `run-selftest.sh` only, as the ticket words it: `tools/run-selftests.sh` and every other suite are unchanged | user-answered | intent |
| D-2 | What the build prompt tells the BUILD about checks | The list stays in the prompt, framed as what the scheduler runs at the pushed head: a red comes back as findings and spends a checks-red attempt. Before pushing, the build runs the checks that cover what it changed; a whole-list run is not required (not forbidden, so `build_allowlist` keeps granting every listed check). The scheduler's pass is unchanged and stays the authority. The comment above the round loop's checks block stops saying "the checks the build did not run" | user-answered | intent |
| D-3 | The case filter's interface on run-selftest.sh | Positional case-id arguments, exact match on `fixture <id>`; a case runs from its `fixture` call to the next one. A filtered run prints the cases it ran; an id that matches no case exits 2; no arguments runs the whole suite as today | user-answered | intent |
| D-4 | Where a build learns to use the filter | A generic line in `build_prompt` (while iterating, run only the cases you added or changed where a suite takes a case filter) that names no repo-specific path, plus a line in this repo's CLAUDE.md verification section naming `run-selftest.sh <case-id>...` | user-answered | intent |
| D-5 | Whether the ticket body gains acceptance criteria | Yes: AC-1..AC-5 appended to the body at intake, derived from D-1..D-4 (https://github.com/manoldonev/second-shift/issues/1035) | user-answered | intent |
| D-6 | What happens to option 1 | Nothing filed; whether the remaining single pass is worth a concurrent review is judged from later runs' timings | user-answered | intent |
| D-7 | The review prompt's claim that the scheduler ran the checks before spawning it | Stays true and unedited: the scheduler's pass still precedes REVIEW — run: `grep -c 'scheduler ran them at this head before spawning you' plugins/dev-pipeline/skills/run/run.sh` → 1 | codebase-derived | fact |
| D-8 | What a skipped case must still leave defined | Helper functions are defined at top level between cases, so a filter that skips a case's lines must not skip them — run: `grep -nE '^[a-z_]+\(\) *\{' plugins/dev-pipeline/skills/run/run-selftest.sh` → 17 definitions after line 215 (255 440 625 824 838 841 871 907 914 972 973 1009 1030 1179 1462 1472 1494) | codebase-derived | fact |
| D-9 | Whether the interactive /dev-pipeline:build gets the same prompt | Yes: `build_prompt` writes the prompt before the handoff branch — run: `grep -n 'build_prompt "$ROUND"' plugins/dev-pipeline/skills/run/run.sh` → 1257, the `HANDOFF` branch at 1258 | codebase-derived | fact |
| D-10 | How a build-prompt change is guarded | A `run-selftest.sh` case that greps the build prompt the fake claude received, as the existing prompt rules are — run: `grep -c 'prompt-1.txt' plugins/dev-pipeline/skills/run/run-selftest.sh` → 19 | codebase-derived | fact |
| D-11 | Precedent for a selftest case filter | None in the repo; the filter's shape is D-3's — run: `find plugins tools -name '*selftest*' -type f \| xargs grep -lE -- '--only\|--case\|SELFTEST_ONLY\|_CASES=' \| wc -l` → 0 | codebase-derived | fact |
| D-12 | Test and release conventions this change follows | A behavior change to run.sh lands with a run-selftest.sh case that fails without it; a new capability is `feat:` on the PR title; every plugins/** PR carries a `Changelog:` trailer — cited (convention): CLAUDE.md:120, CLAUDE.md:64, CLAUDE.md:35 | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether a build that no longer runs the whole list pushes reds more often and reaches `checks-red-spent` sooner; the checks-red cap stays at its default | reversible-default-and-flag |

OR-1's default is reversible cheaply: the cap is `run.checksRedMax` in the consumer config, so raising it is a config edit, and a build may still run the whole list when its change is broad. The build changes no cap.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The build prompt's checks paragraph | decided (D-2) |
| S-2 | The build prompt's filter line | decided (D-4) |
| S-3 | run-selftest.sh output on a filtered run and on an unknown id | decided (D-3) |
| S-4 | The comment above the round loop's checks block | decided (D-2) |
| S-5 | This repo's CLAUDE.md verification section | decided (D-4) |
| S-6 | The review prompt's line on who ran the checks | decided (D-7) |
| S-7 | The prompt /dev-pipeline:build hands the calling session | decided (D-9) |
| S-8 | The ticket's acceptance criteria | decided (D-5) |
| S-9 | tools/run-selftests.sh and every other suite | decided (D-1) |
| S-10 | The run log and terminal slugs | out-of-scope — no terminal or log line changes; OR-1 flags the checks-red rate |
| S-11 | docs/testing.md | out-of-scope — D-4 places the filter's pointer in CLAUDE.md |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice; no reason given
