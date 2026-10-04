# #921 — intake receipt

Pre-flight by `/intake-toolkit:plan-interview` on 2026-10-04. Engineer-logged story. No design handoff: the work is scheduler and contract text and renders nothing. Duplicate scan: rc 0, no candidates.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Who asserts overflow/clipping, and at which scales | The consumer's `smokeCommand` asserts it; second-shift supplies the scale. With an optional `{textScale}` placeholder in `smokeCommand`, each armed row's smoke runs at `1` and at `2` (WCAG 1.4.4's 200%). At each scale the command exits non-zero unless must-show is satisfied and no text overflows or is clipped (operator, ticket body "Decided" 1, 2026-10-04) | user-answered | intent |
| D-2 | `smokeCommand` without `{textScale}` | Runs once at 1x as today. The run prints `scaled smoke: not configured (smokeCommand takes no {textScale})` once per run; never a red, never silent; no configVersion bump, no migration (operator, ticket body "Decided" 2) | user-answered | intent |
| D-3 | config-grill advisory when `smokeCommand` lacks `{textScale}` | No advisory. The per-run note (D-2) plus onboarding's `{textScale}` offer cover it. A grill finding has no waiver key since v3, so it would WARN on every doctor run for a consumer who deliberately stays 1x. config-grill.sh and its selftest are untouched | user-answered | intent |
| D-4 | What `{textScale}` means for the harness | Text-only resize: scale text (e.g. root font-size x textScale) while viewport and px boxes stay put. Not page zoom or deviceScaleFactor, which scale fixed-px boxes along with the text and hide the escape class. docs/live-render.md defines overflow/clipping as an element whose scrollWidth/scrollHeight exceeds its client box; whitelisting intentional `text-overflow: ellipsis` is the harness's call. The determinism list gains text size | user-answered | intent |
| D-5 | Smoke/render commands read the rows heredoc as stdin | Fix in this ticket: `</dev/null` on the render and smoke `lane` calls in `route_smoke`. Today a stdin-reading command swallows the remaining rows and the round goes green (3 rows, only RS-1 ran). Add a run-selftest case: a stdin-reading smoke over 3 rows must run all 3 | user-answered | intent |
| D-6 | Where the not-configured note is set | Once, at section-6 entry after `design_declared` (run.sh ~:747), when rows are armed and `smokeCommand` is set without `{textScale}`. Rows (read at `$FIRST`) and `SMOKE_CMD` are fixed by then, so every terminal that reaches a PR carries it, including checks-red-spent before any smoke. It is printed via `say` and kept in its own run-block notes variable rendered by `cost_block`, not `STATUS_NOTES`, which is scoped to verdict status posts. It never goes into the smoke log. This departs from the ticket's "inside route_smoke after :403/:404" | user-answered | intent |
| D-7 | Wall-clock bound on the doubled smoke | Stays unbounded, as `lane` is today. docs/live-render.md states that `{textScale}` doubles smoke invocations per row (2N harness boots for the reference harness). Not admitted: no consumer has hit a hang | user-answered | intent |
| D-8 | Row id for the new behavior | H14. H13 is already the render-unavailable rule (run.sh:848, run-selftest.sh:679-684, :705-708), so the ticket's "e.g. H13" collides. Tag the `route smoke` header (run.sh:384, `H7-H12` becomes `H7-H12, H14`) and the new selftest labels | codebase-derived | fact |
| D-9 | Placeholder substitution order in `smokeCommand` | Substitute `{textScale}` first, then `{route}` and `{mustShow}`. `subst` (run.sh:389-398) rescans inserted text, so substituting it last rewrites a must-show copy string that contains the literal token (fan-out probe: `Size {textScale}x` became `Size 2x`) | codebase-derived | fact |
| D-10 | Red and ok lines | With the placeholder: red `RS-n at text scale N: smoke failed: <substituted command>`, and the ok line names the scale. Both scales run even after a scale-1 red. Without the placeholder the unscaled lines stay as today (`must-show '...' not satisfied`). No existing selftest asserts the must-show red or ok wording, so the new red gets its own case (operator, ticket body "Scope") | user-answered | intent |
| D-11 | Render command, PNG and hash detector | Unchanged: one render per row at the default scale. `{textScale}` is substituted only in `smokeCommand` and stays literal in `command`. The review-facing PNG is not scaled (operator, ticket body "Scope"/"Not in scope") | user-answered | intent |
| D-12 | Contract-text surfaces | The ticket's list (live-render.md :3-5 :19 :41-55 :62-74, config-schema.md:13, schema liveRender/smokeCommand descriptions, interviewing-baseline:192-193, plan-interview:149, ledger-lint.sh:508, onboard SKILL.md :116-118 :129-131) plus: the live-render.md "Reference harness shape" Smoke-spec bullet (:125-126), which must carry the D-4 duty; the ledger-lint-selftest.sh:685 comment, reworded with :508 (its grep at :692 matches only the message prefix); and `{textScale}` following the existing UNQUOTED-placeholder rule. Left as is: config-grill.sh:210 and intake-orchestrator SKILL.md:369-370 (still accurate about must-show), and docs/migrations/v2-to-v3.md (historical record of that migration) | codebase-derived | fact |
| D-13 | config-lint | No change: `smokeCommand` is only type-checked as a string (config-lint.sh:271) | codebase-derived | fact |
| D-14 | Meaning of "once per run" | Once per run.sh process. `--resume` starts a new process and RUN_ID, so it prints the note again; `write_run_block` strips the earlier block, so the PR still shows one (run.sh:646-651, selftest E15). `--handoff` ends before any smoke and writes no block (run.sh:776-781) | codebase-derived | fact |
| D-15 | A harness that takes `{textScale}` but ignores it | Accepted limit, undetectable from second-shift's side. Unlike `{state}`, there is no 2x artifact to hash. The catch depends on the consumer's detector, verified by the pre-registered replay in the ticket's "Limits, stated" (operator, ticket body) | user-answered | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Scheduler stdout smoke ok/red lines, per row and scale | decided (D-10) |
| S-2 | Smoke log handed to the next build session as findings | decided (D-10) |
| S-3 | Not-configured note in stdout and the PR run block | decided (D-6) |
| S-4 | docs/live-render.md contract, reference harness and determinism list | decided (D-12) |
| S-5 | Schema descriptions and docs/config-schema.md | decided (D-12) |
| S-6 | Onboarding's smokeCommand question | decided (D-12) |
| S-7 | config-grill and doctor output | decided (D-3) |
| S-8 | ledger-lint must-show violation message | decided (D-12) |
| S-9 | Review-facing render PNG | out-of-scope — stays one default-scale render per row (ticket "Not in scope") |
| S-10 | Build and review session prompts | out-of-scope — no plugin file outside config, doctor and onboard tooling reads smokeCommand |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: contract-surface-parity opus 5/6 · substitution-probe fable 5/6 · run-lifecycle-once-per-run opus 6/6 · consumer-adopter-walkthrough fable 6/6 · premortem fable 3/6
Tally: rows added 6 · snapshot claims overturned 0 · questions added 3
Checkouts: none passed — the consumer harness's detector is out of scope (ticket "Not in scope")

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | contract-surface-parity | H13 is already the render-unavailable rule (run.sh:848) | already-had | became D-8 |
| F-2 | contract-surface-parity | live-render.md reference-harness Smoke-spec bullet (:125-126) is outside the ticket's ranges and says the smoke checks must-show only | new | became D-12 |
| F-3 | contract-surface-parity | Four more must-show-only texts outside Scope (config-grill.sh:210, intake-orchestrator:369-370, ledger-lint-selftest.sh:685, v2-to-v3.md:73-75) | new | became D-12 |
| F-4 | contract-surface-parity | Substituting {textScale} after {mustShow} rewrites a must-show value containing the literal token (probe) | new | became D-9 |
| F-5 | contract-surface-parity | Today's must-show red names no command; working-tree line refs drift by one | already-had | became D-10 |
| F-6 | substitution-probe | subst replaces every occurrence; {textScale} in `command` reaches the harness literally | already-had | became D-11 |
| F-7 | substitution-probe | A mixed-red probe of the two-scale loop behaves as the ticket's scope describes | not material | not material — confirms the ticket's loop design |
| F-8 | substitution-probe | A stdin-reading command swallows the remaining rows and the round goes green (run.sh:256, :432-433) | new | became D-5 |
| F-9 | substitution-probe | Once-per-run needs a flag outside route_smoke; STATUS_NOTES reaches the run block | already-had | became D-6 |
| F-10 | substitution-probe | A double-quoted {textScale} delivers a literally-quoted argument, as for the other placeholders | new | became D-12 |
| F-11 | run-lifecycle-once-per-run | H13 taken; the header still says H7-H12 | already-had | became D-8 |
| F-12 | run-lifecycle-once-per-run | route_smoke runs on every NEED_CHECKS=1 pass, including a review re-spawn after the head moved | new | became D-6 |
| F-13 | run-lifecycle-once-per-run | Once per run means once per process; --resume reprints, --handoff runs no smoke | new | became D-14 |
| F-14 | run-lifecycle-once-per-run | Option: compute the note at section-6 entry so checks-red terminals carry it | new | became D-6 |
| F-15 | run-lifecycle-once-per-run | The existing harness can count per-scale calls and notes (FIXTURE_CONFIG, $OUT, pr-body.md) | not material | not material — test mechanics for the build session |
| F-16 | run-lifecycle-once-per-run | No selftest asserts the must-show red or ok wording | new | became D-10 |
| F-17 | consumer-adopter-walkthrough | T4.design-liverender cannot carry a {textScale} advisory; it would be a new trigger | new | became D-3 |
| F-18 | consumer-adopter-walkthrough | Grill finding vs per-run note: different audience and timing | new | became D-3 |
| F-19 | consumer-adopter-walkthrough | Once per run is not free at the call site; STATUS_NOTES is scoped to verdict posts | already-had | became D-6 |
| F-20 | consumer-adopter-walkthrough | The doubled smoke is unbounded (`lane` has no watchdog) | new | became D-7 |
| F-21 | consumer-adopter-walkthrough | No shipped text says what a unitless 2 does in a browser or what counts as overflow | already-had | became D-4 |
| F-22 | consumer-adopter-walkthrough | A grill advisory would WARN forever with no waiver key since v3 | new | became D-3 |
| F-23 | premortem | A harness that takes {textScale} and ignores it runs green, undetectably | new | became D-15 |
| F-24 | premortem | 2N harness boots per run, unbounded | new | became D-7 |
| F-25 | premortem | The per-run note normalizes into noise; argues for the advisory | new | became D-3 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Who asserts overflow/clipping; scales run | consumer command asserts; scheduler runs each armed row at 1 and 2 when smokeCommand takes {textScale} (ticket, operator 2026-10-04) |
    | D-2 | No {textScale} in smokeCommand | 1x only, note `scaled smoke: not configured (smokeCommand takes no {textScale})` once per run via say + PR run block; never red; no configVersion bump (ticket) |
    | D-3 | T4 config-grill advisory when smokeCommand lacks {textScale} | OPEN — recommend no: the per-run note reaches already-onboarded consumers every run, onboarding offers the placeholder at the moment smokeCommand is written |
    | D-4 | What a text scale means in the contract | OPEN — recommend text-only scaling (root font-size x textScale), not page zoom/deviceScaleFactor: zoom scales the fixed-px boxes with the text, so the ticket's escape class (fixed px dims clipping text) cannot show |
    | D-5 | Row id for the new behavior | H14 — H13 is taken (run.sh:848 render-unavailable; run-selftest.sh:679-684); the ticket's "e.g. H13" collides |
    | D-6 | Where the note lands in the run block | a run-scoped notes var printed like STATUS_NOTES in cost_block (run.sh:607-633); set once behind a run-wide flag |
    | D-7 | config-lint | no change: smokeCommand only type-checked as string (config-lint.sh:271) |
    | D-8 | Render command / PNG / hash detector | unchanged; {textScale} literal in `command` (ticket) |
    | D-9 | Red/ok message form with placeholder | `RS-n at text scale N: smoke failed: <cmd>`; ok line names scale; without placeholder keep `must-show not satisfied` (ticket) |
    | D-10 | Duplicate scan | rc 0, nothing recorded |
    | D-11 | Design frames on this repo | not required — this repo's config sets no design.provider |
