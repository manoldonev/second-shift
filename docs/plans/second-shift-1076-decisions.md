# Decision record — #1076 The design-fidelity seat checks UI overrides and justification comments against the installed library

Receipt: v4

## Summary

Both design-fidelity seats check UI overrides, wrapper props and justification comments against the installed library source, and cite the line behind each verdict. The shipped default web-component glob becomes repo-wide, so the seats fire on UI files without per-repo config. Builds check a UI-library claim against the installed source before writing it in a comment. #1077's eval lands first, and this change stays only if it beats that baseline.

Open regions: OR-1, which theme the app mounts. Default: an override the component applies itself needs no mount check; one reached through a provider is cited from the design-tokens reference when it states the surface's theme, else read from the app entry; when neither tells, the seat does not flag.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `user-delegated` = the session decided on the operator's standing instruction.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which seat owns the check | figma-faithful-reviewer and design-faithful-reviewer. The lead pass does not own it. | user-answered | intent |
| D-2 | What the check covers | Overrides: `sx`/`style` blocks, nested `.Mui*`/`.k-*` selectors, style-only wrappers, hand-rolled primitives the library ships. Wrapper props the wrapper drops or misroutes. Justification comments. Copy-paste stays with maintainability. The seats' "accessibility attributes are out of scope" line narrows to allow wrapper prop routing. a11y-reviewer keeps its scope, and the overlap is accepted. | user-answered | intent |
| D-3 | Consumer declaration of the installed library | None. The seat resolves each import in the diff the way the repo resolves it, reads the version from the installed `package.json`, and opens the compiled component and theme-override files of the wrapper and of the base library it wraps. AC-4 is retired. The seat reads only for diff lines that carry an override, a wrapper prop or a library claim, and greps every theme layer for the component's key and for the key of the root it renders. Changed in build: the review of PR #1082 showed composition and a two-layer theme merge put the applied value in a file the import name never reaches. | user-delegated | intent |
| D-4 | Installed source not on disk | One line per review: "Installed source not present; library conformance not checked." It is never a silent pass, and it is not repeated per override. Approval stays possible. | user-answered | intent |
| D-5 | Calibration of a conformance finding | Evidence decides. A finding is flagged at full confidence only with the installed line that proves it. Without that line it is not flagged. The passing bias stays for the existing token and component rules. | user-answered | intent |
| D-6 | Severity of a proven conformance finding | A redundant override, a false justification comment and a dropped or misrouted wrapper prop are each a Warning. Changed in build: the operator demoted the wrapper-prop class in session on 2026-10-16; the fidelity seat is design-blind and does not block on behavior, and the human who reads the verdict decides. | user-answered | intent |
| D-7 | Seat model | Both seats keep their current tier. The #1077 eval decides: if a seat misses PM-1, the operator reruns with an opus `modelOverrides` entry and decides on that run. | user-answered | intent |
| D-8 | Emit-deadline enrollment of design-faithful-reviewer | Not enrolled. The list enrolls only on a demonstrated death, or a required-seat departure such as #992's. Neither applies. cited (convention): plugins/review-toolkit/scripts/check-emit-deadline.sh:130-143 | codebase-derived | fact |
| D-9 | Fate of the named-constant escape hatch | The waiver stays for an off-scale value with no token that the library does not already apply. It no longer waives a library-redundant value. The change lands where the hatch is stated: the figma-faithful reviewer and skill, and design-faithful-reviewer's arbitrary-values rule. Eval fixture 04 still approves. run: `grep -c SEAT_COUNT_OPTICAL_INSET plugins/design-toolkit/evals/figma-faithful-reviewer-eval/fixtures/04-control-clean.expected.json` → 1, in `must_not_flag`; `grep -n "escape hatch\|named module-level constant" plugins/design-toolkit/skills/figma-faithful/SKILL.md` → lines 159, 333 | codebase-derived | fact |
| D-10 | The build authoring rule | UI libraries only. Before a build writes a comment that claims a UI library does or does not do something, it opens the installed source and checks. One unconditional sentence in `run.sh` `build_prompt`, and the same rule in the figma-faithful and design-faithful skills. | user-answered | intent |
| D-11 | Citation form | A build comment cites the installed file when the claim is not obvious. There is no mandated format. A seat finding cites the installed `path:line` that proves it. | user-answered | intent |
| D-12 | A copy of the rule in the build skill | None. `/dev-pipeline:build` hands the session the `run.sh` prompt verbatim. run: `sed -n 11p plugins/dev-pipeline/skills/build/SKILL.md` → "spawn a build session. You do the build in this session. The prompt that it gives you is the prompt" | codebase-derived | fact |
| D-13 | Test for the `run.sh` sentence | A `run-selftest.sh` case greps the generated build prompt of a ticket with no design frames for the sentence. A `run.sh` behavior change needs a case that fails without it. run: `grep -c "A test double of a dependency this repo does not own" plugins/dev-pipeline/skills/run/run-selftest.sh` → 1; cited (convention): CLAUDE.md "A session-launch fix lands in the scheduler" | codebase-derived | fact |
| D-14 | Where a necessary override is recorded | One line per checked override in the seat's prose and `summary`, with its disposition and citation: redundant, prop exists, or necessary. These lines are not findings and do not count against the verdict. | user-answered | intent |
| D-15 | Test for AC-3 | Exempt. AC-3 is reviewer-prompt prose. CI is model-free, and a prose-presence guard is banned. #1077's operator-run eval measures it. | user-answered | intent |
| D-16 | Post-merge checks this ticket carries | PM-1 to PM-3 moved here from #1077 and score this change on its eval. PM-4 is a spot-check of a few consumer UI lane PRs. PM-5 is the keep-or-revert rule. | user-answered | intent |
| D-17 | Default web-component glob | `**/*.{tsx,jsx,vue,svelte,css,scss,less}` when `reviewers.webComponentGlobs` is absent, replacing `apps/web/**/*.{tsx,jsx}`. A configured key still wins. It changes in review-lead `SKILL.md`, onboard's `config-grill.sh` and its selftest, onboard `SKILL.md` and `docs/onboarding.md`. AC-7. | user-answered | intent |
| D-18 | Order and keep-or-revert | This ticket is queued after #1077 closes. The prompt change stays only if its eval score beats #1077's baseline by 10+ points over 3+ runs. Otherwise it is reverted. | user-answered | intent |
| D-19 | Severity of a prop-exists override | An override that a prop or variant of the component already does is a Warning, the same as a redundant override. Its recommendation is to use the prop or variant. Added in build: D-6 names only the redundant override, and the ticket lists prop-exists as its own disposition. | user-delegated | intent |
| D-20 | Other sites that state the default glob | The schema's `default`, `docs/config-schema.md` and `README.md` also state the new default. Added in build: AC-7 asks for the default wherever it is stated, and D-17's list missed these three. | user-delegated | intent |
| D-21 | Where the conformance procedure lives | One shared design-toolkit skill, `library-conformance`, loaded by both seats through their `skills:` frontmatter. Each seat keeps only its own stack's override forms. Added in build: the review of PR #1082 found the section copied into two agents and already drifted; the operator chose the shared skill in session on 2026-10-16. | user-answered | intent |
| D-22 | Opting a repo out of the web-component surface | `reviewers.webComponentGlobs: []` declares no web-component surface. On an unarmed diff neither reviewer is routed and review-lead's Unmatched note reads "declared: no web-component surface". An armed record still spawns the fidelity seat. config-grill reports the key as declared. This repo sets it, because its only `.tsx` files are the eval stand-in. Added in build: the review found no documented off-switch, and this repo's eval fixtures routed a fidelity seat over deliberately defective code. | user-delegated | intent |
| D-23 | design-faithful-reviewer deadline | By turn 10 of its 15, the same line the figma seat carries. Not enrolled in the emit-deadline lint; D-8 stands. Added in build: the review found the seat got the installed-source reads with no numbered deadline. | user-delegated | intent |
| D-24 | Condition rule for a cited line | A cited installed line counts only when it applies under the diff's variant, size, state and breakpoint condition; otherwise the seat suppresses. Added in build: the review's pre-mortem showed a size-keyed theme value flagged as redundant on the default size. | user-delegated | intent |
| D-25 | Reader of the summary lines | review-lead carries a fidelity seat's `summary` lines into its Review Summary, one line per seat. Added in build: the review found nothing rendered the D-4 and D-14 lines. | user-delegated | intent |
| D-26 | Eval additions | Fixture 12, a condition-keyed theme value that must not flag; `turns=` (max/mean `num_turns`) in every changelog row; fixture set v3. Tool-call counts are not recorded because the `claude -p` envelope does not carry them. Added in build: the review asked for turn counts in the keep-or-revert read and a must-not-flag fixture for the condition rule. | user-delegated | intent |

Options weighed:
- D-1: the fidelity seat, the lead-pass checklist, or a new dedicated seat. The operator chose the fidelity seat.
- D-2: overrides only, overrides plus wrapper-API misuse, or every audit class. The operator chose overrides plus wrapper-API misuse.
- D-3: a design-tokens heading, a new review-context section, extending `UI stack & design system`, or no declaration. The operator chose no declaration.
- D-4: one summary line, one line per override, fail the seat, or fall back to types. The operator chose one summary line at the intake review.
- D-5: evidence decides, or keep the passing bias. The operator chose evidence decides.
- D-6: Warning with Critical for broken props, all Critical, or all Warning. The operator chose Warning with Critical for broken props.
- D-7: the current tier with the eval deciding, or opus now. The operator chose the current tier at the intake review.
- D-10: UI libraries with verify-and-cite, every build and any dependency with a mandated citation, or no rule. The operator chose UI libraries at the intake review.
- D-11: a cited file with no format, or `pkg@version path:line`. The operator chose a cited file at the intake review.
- D-14: one summary line each, note-level findings, or nothing. The operator chose one summary line each.
- D-15: exempt, or unchecked on the eval tier. The operator chose exempt.
- D-16: carry the eval's checks here, or keep them on #1077. The operator chose here, with #1077 recording the baseline.
- D-17: a repo-wide default, harness enforcement in #1078, or no default change. The operator chose the repo-wide default and closed #1078.
- D-18: #1077 first as this ticket's gate, or both in parallel. The operator chose #1077 first.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether a wrapper's theme overrides apply to the changed screen | reversible-default-and-flag |

OR-1 default: an override the component applies itself needs no mount check. An override reached through a provider applies where that provider is mounted: the seat cites the design-tokens reference when it states the surface's theme, else reads the app entry for the mounted ThemeProvider. When neither tells, it does not flag the claim. Changed in build: the review of PR #1082 found the app entry unreadable in the eval and in the consumer, and the design-tokens reference already states the theme per surface. Reversing it changes one skill paragraph.

## Test intent

ACs: AC-3 AC-5 AC-7

AC-3: exempt — reviewer-prompt prose; CI is model-free, and #1077's operator-run eval measures it

AC-5: the build prompt `run.sh` generates for a ticket with no design frames carries the UI-library authoring sentence

AC-7: with `reviewers.webComponentGlobs` absent, config-grill reports the resolved default as `**/*.{tsx,jsx,vue,svelte,css,scss,less}`

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Seat finding for a library-redundant override | decided (D-5) |
| S-2 | Seat finding for a false justification comment | decided (D-6) |
| S-3 | Seat finding for a dropped or misrouted wrapper prop | decided (D-6) |
| S-4 | Seat line when installed source is absent | decided (D-4) |
| S-5 | Seat summary lines for necessary overrides | decided (D-14) |
| S-6 | The build-prompt authoring sentence | decided (D-10) |
| S-7 | A citation in a build-written comment | decided (D-11) |
| S-8 | Eval control fixture 04 verdict | decided (D-9) |
| S-9 | Seats firing in a repo with no glob config | decided (D-17) |
| S-10 | config-grill's reported default glob | decided (D-17) |
| S-11 | The consumer's `design-tokens/*.md` | out-of-scope — D-3 adds no declaration, so the file does not change. |
| S-12 | a11y-reviewer output | out-of-scope — its scope does not change, and the overlap is accepted. |
| S-13 | A repo with no web-component surface | decided (D-22) |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written on #1069. spec-reviewer: needs spec work, 3 blockers. The operator reworked the blocker sections in session, and #1069 was amended.

Split: split #1069 into #1076, #1077 and #1078. At the intake review, #1078 was closed, and #1077 now precedes #1076. This receipt is for #1076.

Explore: done. Read both fidelity reviewers, both design skills, `run.sh` `build_prompt` and its selftests, the reviewer eval, the glob-default sites, and the consumer's lane reviews.

Fan-out: ran once for the #1069 split — 14 items touch this slice, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. PM-1 to PM-5 live here on the operator's answers (D-16, D-18).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1069 split — slices #1076, #1077, #1078
Refuter: cross (opus/fable alternating)
Lenses: premise-replay opus 6/6 · seat-drop-paths fable 3/6 · installed-source-reachability opus 6/6 · contract-seams fable 6/6 · premortem fable 2/6
Tally: rows added 1 · snapshot claims overturned 0 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | premise-replay | `ellipsis` with a caller's `sx` loses the ellipsis; only the compiled wrapper JS shows it (consumer `Typography.js:19,26-28`). | new | became D-3 |
| F-2 | premise-replay | `aria-label` lands on the wrapper's FormControl, not the combobox (consumer `DropDownList.js:20-45`). | new | became D-3 |
| F-3 | premise-replay | The wrapper's changelog and TextField override zero multiline root padding (consumer `MuiTextField.js:47-51`). | new | became D-3 |
| F-4 | premise-replay | Bare MUI rotates the chevron 180°, but the wrapper override rotates it 90°; a seat needs both files. | new | became D-3 and OR-1 |
| F-5 | premise-replay | The wrapper re-exports MUI's `useMediaQuery`, so "no media-query hook" is false (consumer `dist/index.js:611`). | new | became D-3 |
| F-6 | premise-replay | Types never show prop routing; the compiled dist JS settles wrapper-API misuse. | new | became D-3 |
| F-7 | installed-source-reachability | The lane installs nothing itself; a consumer setup lane runs before the review session (`run.sh:531-535`). | new | became D-4 |
| F-8 | installed-source-reachability | The consumer's lane worktree holds the installed wrapper as readable compiled dist. | new | became D-4 |
| F-9 | installed-source-reachability | Standalone review reads whatever checkout it runs in; neither seat prompt mentions `node_modules`. | new | became D-4 |
| F-10 | contract-seams | All three seat prompts give accessibility attributes to a11y-reviewer (`figma-faithful-reviewer.md:135`). | new | became D-2 |
| F-11 | contract-seams | The escape hatch is also taught in the figma-faithful skill; design-faithful-reviewer's hatch is arbitrary values. | new | became D-9 |
| F-12 | contract-seams | A new review-context catalog row is breaking-class, and the selftest mirrors it in `docs/extension-points.md`. | new | became D-3 |
| F-13 | contract-seams | The consumer already records installed-library facts in `design-tokens`, not `review-context.md`. | already-had | became D-3 |
| F-14 | contract-seams | Adding the rule to `build_prompt` is a `run.sh` behavior change that needs a `run*-selftest.sh` case. | already-had | became D-13 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | P-1 | Check owner | the design-fidelity seat (figma-faithful-reviewer / design-faithful-reviewer) — operator, Requirements |
    | P-2 | UI-diff trigger and enforcement | hard `signal: ui` in #993 review-signals.sh; shipped list ∪ webComponentGlobs; seat required; #994 post-check — operator |
    | P-3 | AC shape | review-time AC-1..AC-6; model runs as PM-1..PM-4 — operator |
    | P-4 | Fixture host | mini app in this repo — operator (location was tools/planted-defects/ui in the option text) |
    | P-5 | Proof the check ran | seat returned is enough — operator |
    | P-6 | Check scope | overrides + wrapper-API misuse; copy-paste deferred to maintainability — operator |
    | A-1 | #1076: where the installed-library declaration lives | OPEN — design-tokens/*.md already read by both seats and the build skills, and the consumer's copy already records the installed package version; vs a new review-context section |
    | A-2 | #1076: commented-constant escape hatch | keep it for an off-scale value with no token; withdraw it only for a library-redundant value; figma-faithful-reviewer-eval fixture 04 must stay approve |
    | A-3 | #1076: "bias toward passing" vs the conformance check | OPEN |
    | A-4 | #1076: seat budget | OPEN — sonnet, maxTurns 15; code-review.mjs says a deadline, not a bigger cap, cures turn deaths |
    | A-5 | #1076: build-prompt line condition | OPEN — run.sh states the figma-faithful sequence only with frames rows |
    | A-6 | #1076: citation format | OPEN — installed path:line plus version? |
    | A-7 | #1076: run.sh prompt test | run-selftest greps the generated prompt (precedent run-selftest.sh:146) |
    | B-1 | #1077: fixture shape | OPEN — an existing operator-run figma-faithful-reviewer-eval (acme-ui stand-in, expected.json, rubric) could be extended instead of a new tools/planted-defects/ui app |
    | B-2 | #1077: PM-1 "lane review" vs agent eval | OPEN |
    | B-3 | #1077: real @mui/material install vs stubs carrying theme overrides | OPEN |
    | C-1 | #1078: mechanics on #993/#994 output format | OPEN — both unbuilt; defer |
    | C-2 | #1078: shipped UI list | *.tsx *.jsx *.vue *.svelte *.css *.scss *.less (derived, unconfirmed) |
    | C-3 | #1078: design-toolkit absent on ui signal | void (derived from "never silently skipped") |

</details>
