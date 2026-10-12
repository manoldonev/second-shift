# Intake receipt — #1010: lane builds are told to act on notes, and verdict findings no longer carry their confidence

Engineer-logged ticket, `plan-interview` pre-flight. No design handoff exists for this surface (the change edits prompt text, a skill sentence and a selftest; the repo sets no `design.provider`). Author: the operator.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | What the needs-work build prompt hands the build | The whole bound verdict body (header, row table, `## Findings`, `## Panel`, `## Notes` prose), under one `## Review findings` heading, on every build attempt of round 2 or later, red retries included; round 1 carries no findings — run: `grep -n 'FINDINGS="$STATE/verdict-body.md"' plugins/dev-pipeline/skills/run/run.sh` → `1222:  FINDINGS="$STATE/verdict-body.md"; RED_LOG=""; NEED_BUILD=1`; the instruction is the else-arm at run.sh:605 under `[ "$1" -eq 1 ]` | codebase-derived | fact |
| D-2 | Whether carrying confidence and file:line needs a checker change | No. The checker reads only `- [blocker] B<n> ` or `- [note] N<n> ` (the id, then one literal space) and ignores the rest of the line; it never requires a number — run: `grep -n 'B\[0-9\]+ /' plugins/dev-pipeline/tools/verdict-check.sh` → `79:  if ($0 ~ /^- \[blocker\] B[0-9]+ /)`; a fan-out probe body with `- [blocker] B1 confidence 85 run.sh:605 ...` passed verdict-check.sh with rc=0, and one with `B1(confidence 85)` failed `Findings not in the grammar` | codebase-derived | fact |
| D-3 | Where the grammar is edited | At both lockstep sites word-for-word in the same PR, run.sh's review-prompt heredoc and review/SKILL.md step 8, plus the checker's unmarked header paraphrase (verdict-check.sh:9-21) by hand — run: `grep -rn 'LOCKSTEP-BEGIN verdict-grammar' plugins` → `plugins/dev-pipeline/skills/run/run.sh:633` and `plugins/dev-pipeline/skills/review/SKILL.md:87`; a fan-out probe that edited run.sh's copy alone made `bash scripts/check-lockstep-pairs.sh` print `FAIL: verdict-grammar (verbatim) ... DRIFTED`, rc=1 | codebase-derived | fact |
| D-4 | Where the review session gets a finding's confidence and file:line from | review-lead's report already writes them per finding and per suppressed bullet; the verdict transcribes, it does not score — cited (convention): plugins/review-toolkit/skills/review-lead/SKILL.md:578 (`[Reviewer] file:line (confidence: N) — description`) and :606 (Suppressed bullets) | codebase-derived | fact |
| D-5 | Selftest coverage of the needs-work build instruction | None today: case (b) checks only that the verdict body reaches the round-2 prompt — run: `grep -c 'fix each' plugins/dev-pipeline/skills/run/run-selftest.sh` → 0; run-selftest.sh:253 is `grep -q 'verdict: needs-work' "$FAKE_GH/prompt-3.txt"` | codebase-derived | fact |
| D-6 | Which needs-work shapes a build can receive | Two: a body with `[blocker]` lines, or a body whose only cause is a record row scored violated or undeterminable (findings `None.` or notes only). A render-unavailable needs-work ends the run before any build; a notes-only body with honored rows does not bind — run: `bash plugins/dev-pipeline/tools/verdict-check.sh <fan-out probe body> rec.md rec.md` → violated-row body with findings None. rc=0; notes-only body with honored rows rc=1 `needs-work with no blocker`; and run.sh:1221 `terminal env-not-ready` on the render line | codebase-derived | fact |
| D-7 | What the needs-work build prompt orders, and whether the build still sees `[note]`s | The whole verdict stays handed over as today. The order: fix or rebut each `[blocker]` finding in a PR comment, and fix each record row scored violated or undeterminable (or edit the row per the departure rule). A `[note]` finding requires nothing: the build fixes one only by choice and never rebuts or replies to one. The wording names `[note]` findings, not the `## Notes` prose. Options weighed: this; the same with notes rebuttable; stripping `[note]` lines from the handover (a second parser of the grammar) | user-answered | intent |
| D-8 | How a finding carries its confidence, and which findings carry one | Mirror review-lead's form after the id: `- [blocker] B1 [Reviewer] file:line (confidence: N) — text`, file:line only where the finding has one, the id followed by one literal space (D-2). A finding the review raises from a rule (a violated or undeterminable row, an untraced test-expectation change) or as a process note names its rule and carries no number, so no score is invented into the record a later 80-cut test reads. Options weighed: this; a number on every finding; the trailing `(<reviewer>, confidence N)` form #1000's verdict used by habit | user-answered | intent |
| D-9 | Enforcement of the confidence clause | Prompt-only: the grammar asks for it at both sites, verdict-check.sh gains no rule, and a verdict without the number still binds. A later metric that reads the field adds the checker rule when it has a reader. Option weighed: a checker rule failing a `[Reviewer]`-tagged finding with no `(confidence: N)`, at the cost of a review re-spawn per miss | user-answered | intent |
| D-10 | The run-selftest.sh case shape that fails without the change | A two-round case with a mixed needs-work verdict (one `[blocker]`, one `[note]`) asserting on the round-2 prompt: both finding lines reach it, the new order is present, and the old `fix each, or rebut it` sentence is absent. It is a grep on the emitted prompt, and says so in the check, since the fake build never reads the prompt (docs/testing.md:316) — run: `bash <scratchpad>/probes/dp/skills/run/b3-selftest.sh` → against HEAD, 2 of 4 assertions FAIL (`does not split blockers from notes`, `still orders every finding addressed`); against run.sh:605 replaced → 4 pass; the keep-old-add-new and strip-notes wrong versions each fail exactly one assertion | codebase-derived | fact |
| D-11 | The interactive build skill's needs-work sentence | In scope: build/SKILL.md:42 (`On needs-work, address or rebut each finding in this session and push`) gets the same order as D-7, blockers and bad rows mandatory, notes requiring nothing. Option weighed: run.sh only, filing the hand path separately | user-answered | intent |

Out of this ticket's scope, named for the record: which confidence survives review-lead's merge of two findings at one location, and its re-filter at 80, is review-toolkit's rule (review-lead/SKILL.md:431-438); the verdict transcribes what the report says. Record-row scores never carried a confidence and the ticket asks none of them.

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The needs-work build prompt, round 2 and later, red retries included | decided (D-7) |
| S-2 | The verdict comment's finding lines on the PR | decided (D-8) |
| S-3 | review/SKILL.md step 8, the manual reviewer's copy of the grammar | decided (D-3) |
| S-4 | The build's PR comments: rebuttals on blockers, none on notes | decided (D-7) |
| S-5 | build/SKILL.md's needs-work sentence for the hand build | decided (D-11) |
| S-6 | verdict-check.sh's header paraphrase of the grammar | decided (D-3) |
| S-7 | The did-not-bind notice and its failed-rule names | out-of-scope — no checker rule is added (D-9), so the notice is unchanged |
| S-8 | The round-1 build prompt | out-of-scope — it carries no findings |
| S-9 | The Decision record rows table's score cells | out-of-scope — the ticket asks confidence on findings only; rows never carried one |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Design frames

Design: none — the change renders no screen; it edits prompt text, a skill sentence and a selftest.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: build-input-trace opus 6/6 · confidence-provenance fable 4/6 · grammar-lockstep-and-checker opus 6/6 · selftest-that-bites fable 6/6 · premortem fable 4/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | build-input-trace | One call site feeds a build its findings; after a bound needs-work arg2 is the verbatim verdict body and the Address line prints only when ROUND > 1 (run.sh:1129, :1222, :605) | already-had | D-1 |
| F-2 | build-input-trace | A red retry in round 2+ gets the Address line and the previous verdict again beside the red log; in round 1 it gets neither (run.sh:1022-1025) | already-had | D-1 |
| F-3 | build-input-trace | A review re-spawn and a hand verdict never reach a build through run.sh; the interactive build skill carries its own every-finding sentence (build/SKILL.md:42) | new | became D-11 |
| F-4 | build-input-trace | A needs-work with zero blockers binds when a row is violated/undeterminable; the build prompt never names rows | already-had | D-6, D-7 |
| F-5 | build-input-trace | render-unavailable never reaches a build; notes-only with honored rows is rejected | already-had | D-6 |
| F-6 | build-input-trace | Confidence as free text after the id binds and reaches the build; case (b) greps only the verdict line | already-had | D-2, D-5 |
| F-7 | confidence-provenance | No lane rule ever asked for confidence; pre-#1000 verdicts carried it by habit, and #1000's diff touches no line with the word | new | no row — the clause is a new rule, not a restore; informs D-8 |
| F-8 | confidence-provenance | #1000's own grammar-era verdict carried confidence at line end, `(unit-test-mutation, confidence 82)`, which the checker accepts | new | became an option weighed in D-8 |
| F-9 | confidence-provenance | Three drop/merge points precede the lane reviewer; no rule says which confidence survives a review-lead merge | not material | not material — review-toolkit's merge rule, out of scope; named in prose under the ledger |
| F-10 | confidence-provenance | Row scores never carried a confidence anywhere in the chain | not material | not material — the ticket asks findings only; S-9 |
| F-11 | grammar-lockstep-and-checker | check-lockstep-pairs.sh keeps the two grammar copies in step; verdict-check.sh's header paraphrase has no marker | new | folded into D-3 (header paraphrase updated by hand) and S-6 |
| F-12 | grammar-lockstep-and-checker | A one-sided grammar edit fails the lockstep check, rc=1 | already-had | D-3 |
| F-13 | grammar-lockstep-and-checker | The checker accepts text only after `B<n>` plus one literal space; a misplaced number cascades to an unbound verdict | new | folded into D-2 and D-8 (id, then one space) |
| F-14 | grammar-lockstep-and-checker | Confidence on a continuation line and a finding with no file:line both pass; nothing requires either | already-had | D-2, D-9 |
| F-15 | grammar-lockstep-and-checker | No suite asserts the Address sentence; prompt-3.txt carries the whole verdict so a case can grep it | already-had | D-5, D-10 |
| F-16 | grammar-lockstep-and-checker | verdict-check.sh:79 is the only parser of finding lines in the repo | already-had | D-2 |
| F-17 | selftest-that-bites | A drafted mixed-verdict case fails 2 of 4 assertions against HEAD and passes with run.sh:605 replaced | new | became D-10 |
| F-18 | selftest-that-bites | The keep-old-add-new and strip-notes wrong versions are each caught by exactly one assertion | new | folded into D-10 |
| F-19 | selftest-that-bites | The case is a grep on the emitted prompt; the suite has no other instrument for a wording change, and docs/testing.md asks the check to say why | new | folded into D-10 |
| F-20 | selftest-that-bites | Scope 2 gets no run-selftest bite: a reviewer that omits the number binds all the same | already-had | D-9 |
| F-21 | selftest-that-bites | The grammar edit must land at both lockstep sites in one PR | already-had | D-3 |
| F-22 | selftest-that-bites | Does the build keep seeing `[note]`s, or are they stripped from the handover? | new | became an option weighed in D-7 |
| F-23 | premortem | A violated-row needs-work under 'fix each [blocker]' alone names nothing: a no-op push and a spent round | already-had | D-6, D-7 |
| F-24 | premortem | The grammar wording also binds the manual /dev-pipeline:review path, whose verdict no scheduler reads | already-had | D-3, S-3 |
| F-25 | premortem | A mandatory number forces invented scores onto process notes and the review's own rule blockers, into the very record the 80-cut test would read | overturned (snapshot: "confidence always, the review scores its own findings on the baseline scale") | became D-8 (rule findings carry no number) |
| F-26 | premortem | The handover holds `## Notes` prose beside `[note]` findings, and a violated row is not a finding | new | folded into D-7's wording |

### Snapshot

    # Snapshot — #1010, explore-first register before the fan-out pool was read

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | What the needs-work build prompt hands the build | The whole bound verdict body, notes included, under `## Review findings` (`FINDINGS="$STATE/verdict-body.md"`, run.sh:1222; instruction at run.sh:605) |
    | D-2 | Whether carrying confidence needs a checker change | No: verdict-check.sh matches `^- \[blocker\] B[0-9]+ ` / `^- \[note\] N[0-9]+ ` (lines 79-80) and ignores the rest of the line |
    | D-3 | Where the grammar is edited | Both lockstep sites identically: run.sh:633-646 heredoc and review/SKILL.md:87-100; check-lockstep-pairs.sh discovers the pair by marker |
    | D-4 | Where the review gets the number from | review-lead's report already writes `file:line (confidence: N)` per finding and `Confidence: N` per suppressed bullet (review-lead/SKILL.md:578,606; reviewer-baseline:82) |
    | D-5 | Selftest coverage of the needs-work build prompt | None on the instruction text: case (b) run-selftest.sh:253 only checks the verdict body reaches prompt-3 — a new case is needed |
    | D-6 | Needs-work verdicts with no `[blocker]` | Legal: a violated/undeterminable row, or render-unavailable (no second build, H13 run-selftest.sh:957). "Fix each [blocker]" alone names nothing on a violated-row needs-work |
    | D-7 | Build-prompt instruction on a needs-work round (ask) | rec: fix or rebut each `[blocker]`; fix each row scored violated/undeterminable; a `[note]` requires nothing — fix one only by choice, never rebut or reply to one |
    | D-8 | Finding-line form for confidence and file:line (ask) | rec: mirror review-lead's form: `- [blocker] B1 <file:line> (confidence: N) — <text>`, file:line omitted when none, confidence always |
    | D-9 | Enforcement of the confidence field (ask) | rec: prompt-only now, no verdict-check.sh rule; a later metric adds the rule when it reads the field |

    Surfaces: needs-work build prompt (D-7) · verdict finding lines (D-8) · review/SKILL.md grammar (D-3, D-8) · the build's PR comments on notes (D-7) · did-not-bind notice (D-9: unchanged) · round-1 prompt out of scope (no findings).
    Checks: run-selftest.sh, check-lockstep-pairs.sh, verdict-check-selftest.sh. Open regions: none proposed.
