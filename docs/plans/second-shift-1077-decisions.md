# Decision record — #1077 A planted-defect UI fixture measures the library-conformance check

Receipt: v4

## Summary

The operator-run figma-faithful-reviewer eval gains library-conformance fixtures and a conformance control. They sit on a fictional `acme-ui` stand-in that only a reading of its source can judge. A CI selftest checks that every expected file parses and that every disproving citation points at a real line. This lands before #1076, and its baseline run on today's seat is what #1076 must beat.

Open regions: OR-1, the expected-file schema. OR-2, the defect set. OR-3, the fixtures' surface. OR-4, the stand-in's shape. All are flagged defaults.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the seat's recall is measured | Extend `plugins/design-toolkit/evals/figma-faithful-reviewer-eval/` with conformance fixtures. The operator runs it. A lane review is not the measure. | user-answered | intent |
| D-2 | Source of the "installed" library | The fictional `acme-ui` stand-in only. No real MUI is vendored or installed. Every disproving line points into the stand-in. The MUI-internal "the hook reads false first" premise is dropped. | user-answered | intent |
| D-3 | A design-faithful-reviewer twin eval | None. No current consumer uses `design.provider: claude-design`. The twin is added when one does. | user-answered | intent |
| D-4 | Post-merge checks this ticket carries | PM-6 only: the operator runs the eval on today's seat and records the baseline row in its changelog. PM-1 to PM-4 live on #1076. | user-answered | intent |
| D-5 | The eval's rubric lock | No campaign is open. #707 is closed, and #1076 changes the seat's prompt, which voids the baseline. Extend in place, bump `RUBRIC_VERSION` and `FIXTURE_VERSION`, and mark the old baseline superseded. The judge prompt grades a citation and a comment flagged false. run: `gh issue view 707 --json state -q .state` → CLOSED; cited (convention): plugins/design-toolkit/evals/eval-criteria.md:7-8 | codebase-derived | fact |
| D-6 | What the selftest checks | Every `.expected.json` parses, and every cited `path:line` exists in the stand-in. It does not pin the line's content. | user-answered | intent |
| D-7 | Order | This ticket lands before #1076. #1076 is queued when this one closes. | user-answered | intent |

Options weighed:
- D-1: extend the existing eval, or a new fixture with a lane review. The operator chose to extend the eval.
- D-2: a committed `node_modules` subset with real MUI, the stand-in only, or an operator install. The operator chose the stand-in only.
- D-3: a twin on the same stand-in, a twin on a shadcn stand-in, or no twin. The operator chose no twin at the intake review.
- D-4: the baseline here with the scoring checks on #1076, or all checks here. The operator chose the baseline here.
- D-6: parse and line-exists, or also a pinned snippet. The operator chose parse and line-exists.
- D-7: this ticket first as #1076's gate, or both in parallel. The operator chose this ticket first.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The `.expected.json` citation field | reversible-default-and-flag |
| OR-2 | Which defects make up the six planted fixtures | reversible-default-and-flag |
| OR-3 | Which surface the conformance fixtures sit on | reversible-default-and-flag |
| OR-4 | The stand-in's shape and the existing stubs | reversible-default-and-flag |

Defaults, all chosen by the intake session. Each costs one fixture-harness edit to reverse, before any campaign runs.
- OR-1 default: each expected file carries `disproving: [{"path", "line"}]`. The paths are relative to the eval's `--repo-root`.
- OR-2 default: two fixtures per class. The classes are a theme-redundant `sx`, a false justification comment, and wrapper-API misuse (`ellipsis`+`sx`, a misrouted `aria-label`). Five of six then needs every class caught at least once.
- OR-3 default: the conformance fixtures sit on the console (fixed-theme) surface and carry no token violations. So a token finding on the control is a false positive.
- OR-4 default: the stand-in stays at `fixtures/app/packages/acme-ui/` and gains a `package.json` with a version. A fixture-app `package.json` declares it as a workspace, so `@acme/acme-ui` resolves to it. Only the stubs the fixtures touch get bodies. Fixture 02's export stubs stay greppable. The design-tokens docs stay silent on the new overrides. The `run.sh` prompt's "export stubs" wording is updated.

## Test intent

ACs: AC-6

AC-6: the selftest fails on an expected file that does not parse, or on a cited line missing from the stand-in; it passes on the shipped fixtures

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The eval's results and changelog rows | decided (D-1) |
| S-2 | A conformance fixture's expected file | decided (D-2) |
| S-3 | The selftest's failure message | decided (D-6) |
| S-4 | The baseline document after the version bump | decided (D-5) |
| S-5 | The eval README's stub section | decided (D-2) |
| S-6 | The consumer's lane reviews | out-of-scope — the eval runs the seat directly. |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written on #1069. spec-reviewer: needs spec work, 3 blockers. The operator reworked the blocker sections in session, and #1069 was amended.

Split: split #1069 into #1076, #1077 and #1078. At the intake review, #1078 was closed, and this ticket now precedes #1076. This receipt is for #1077.

Explore: done. Read the figma-faithful-reviewer eval, its rubric, baseline and runner, the eval kit, the `acme-ui` stubs, and this repo's config.

Fan-out: ran once for the #1069 split — 3 items touch this slice, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. PM-6 lives here, and PM-1 to PM-4 live on #1076, on the operator's answers (D-4).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1069 split — slices #1076, #1077, #1078
Refuter: cross (opus/fable alternating)
Lenses: premise-replay opus 6/6 · seat-drop-paths fable 3/6 · installed-source-reachability opus 6/6 · contract-seams fable 6/6 · premortem fable 2/6
Tally: rows added 0 · snapshot claims overturned 0 · questions added 0

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | installed-source-reachability | second-shift has no install and no setup lane, and its config routes no fidelity seat to a fixture `.tsx`. | new | became D-1 |
| F-2 | installed-source-reachability | Without an install, the options are vendoring MUI, a stand-in only, or an operator install; full MUI is 15M. | already-had | became D-2 |
| F-3 | installed-source-reachability | PM-1 needs an install step, or every disproving line must point into the stand-in. | already-had | became D-2 |

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
