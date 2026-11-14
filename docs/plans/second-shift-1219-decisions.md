# Decision record — #1219 Shipped prompts give reviewers and design agents wrong or duplicated instructions

Receipt: v4

## Summary

The ticket corrects false, contradictory and duplicated text in shipped prompts across six plugins. Reviewers stop being told to call StructuredOutput. Over-engineering gets one Warning ceiling. Stale engine text, gate-evidence claims and prose that a script already prints are removed.

Open regions: OR-1, the shortened description fields of two skills, with a stated default.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Amend the ticket body before the interview | Yes, facts only. The amendment fixed citations and reasons, added two missed sites and re-anchored line numbers to b1763e05. No AC or scope changed. | user-answered | intent |
| D-2 | The artifact reviewers' Output bullet, where items 1 and 12 conflict | Keep the bullet in the lockstep block, reworded. Drop the StructuredOutput sentence and the former-dispatcher clause. Keep "end with REVIEW_RESULT and one fenced JSON block (verdict, findings[], summary)". design-faithful-plan-reviewer.md joins the group. The canonical comment loses its StructuredOutput reason. | user-answered | intent |
| D-3 | The Output deltas of the two diff reviewers | Delete them, and reword figma-faithful-reviewer.md:150 to drop StructuredOutput. Keep the design-faithful-reviewer.md:36 rule that library-conformance summary lines go in `summary`. The dispatch prompt already names the block. run: `grep -n 'REVIEW_RESULT' plugins/review-toolkit/workflows/code-review.mjs` → :343 FINDINGS_EPILOGUE sends the sentinel and block shape | codebase-derived | fact |
| D-4 | What the rewritten reviewer-baseline Output Mode says | Reviewers run schema-free. They write the review, then end with REVIEW_RESULT and one fenced JSON block. Keep the Critical/Warning/Pre-existing to blocker/major/minor/nit table. Keep suppressed[] routing, retargeted to the block. Keep the heading name "Output Mode". run: `sed -n 339,345p plugins/review-toolkit/workflows/code-review.mjs` → "Write your review, grounding as much as you need" then "severity": "blocker\|major\|minor\|nit" and "suppressed": [] | codebase-derived | fact |
| D-5 | Where the Warning ceiling for over-engineering applies | In lead-pass-checklist.md and complexity-reviewer.md. All three Complexity "Critical" items (:392-401) move under Warning. The complexity-reviewer.md:27 heading "Critical Rules (block merge if violated)" becomes a Warning heading. | user-answered | intent |
| D-6 | Workflow files that change besides code-review.mjs:372-374 | Fix or delete the comment at intake-review.mjs:209-214, which item 1 makes false. stall-probe.mjs stays unchanged: its schema-forced arms measure StructuredOutput dispatch on purpose. | user-answered | intent |
| D-7 | The fix for review-lead SKILL.md:93 | Delete only "Filter aggressively.". Keep the sentence before it. The dismissal rule at :661 owns how a finding is dropped. | user-answered | intent |
| D-8 | The design agents' return shapes behind PRODUCE_SCHEMA | Keep { summary, artifactPath }, { summary, committed, changedFiles } and { summary, failClosed: { reason } } as the output contract, under a plain name. Remove the PRODUCE_SCHEMA name, the engine sentences and the tool-grant history. | user-answered | intent |
| D-9 | Which review-lead Rules bullets (:893-:902) go | Delete :893, :898 and :902, which restate Step 1 (:631), the verdict format and the gate (:672-674). Keep the :897 rules "2-4 most specific" and one bullet per file. They may stay in place or move into the Strengths template. run: `grep -n 'Strengths' plugins/review-toolkit/skills/review-lead/SKILL.md` → the template at :789 has no 2-4 or per-file rule; only :897 has them | codebase-derived | fact |
| D-10 | What goes at review-lead SKILL.md:60 | Delete only "The config grill reports a config that sets it.". Keep "Do not read it: it selects nothing on any path.". No other line tells the session not to read the key. run: `sed -n 232,236p plugins/second-shift/skills/onboard/tools/config-grill.sh` → trigger 7 reports a set reviewers.default | codebase-derived | fact |
| D-11 | How items 10 and 11 delete text | Delete whole sentences, not line ranges. Several ranges end mid-sentence (:418, :487, :385). Keep sentences the lint cannot print: :133-134, :419, :487-488, receipt.md:205-206 and :214-215. Keep receipt.md:132 "Max 25 words". Delete the repeats at :139, :145, :161 and :178, but keep the :178 "max 15 words" rule. build/SKILL.md deletes through :60, because run.sh prompt item 7 covers the steer rows. run: `grep -cE '25\|words' plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` → 0 | codebase-derived | fact |
| D-12 | What goes with the deleted audit template | Remove every manual-mode instruction: SETUP.md :11-19, :45 and :72, audit SKILL.md :44 and :59, audit-history.sh:60-61, audit-tool-calls.sh:5-6 and the audit-selftest.sh:235 comment. Remove "settings template" from the plugin.json:3 description. Its version stays frozen. Manual mode has no working form, because the template's paths need the plugin, which already wires the hook. run: `git grep -n 'settings.audit-template\|settings template' -- plugins` → 5 files, plugin.json:3 among them | codebase-derived | fact |
| D-13 | How item 2's import may resolve | AC-2 lets the build delete the snippet or resolve the path from the skill's stated base directory. A shell variable cannot work. The Bash tool leaves it unset, and the snippet's single quotes block expansion. run: `echo "${CLAUDE_PLUGIN_ROOT:-unset} ${SKILL_DIR:-unset}"` → unset unset | codebase-derived | fact |
| D-14 | The fix for mutation-review SKILL.md:41 | Drop the clause about the schema-forced turn and the StructuredOutput staller. Keep the propose/execute rule. No explorer carries a schema. run: `sed -n 502,503p plugins/review-toolkit/workflows/code-review.mjs` → "no explorer carries a schema, and the emitter cannot explore" | codebase-derived | fact |
| D-15 | Commit verb and trailer | `fix` on the PR title, a patch: the change corrects shipped prompts and adds nothing. It is not breaking. A consumer's own copy of the template keeps working, and plugin mode is unchanged. The Changelog trailer names the removed template and the complexity ceiling. Migration: none. cited (convention): CLAUDE.md:63 | codebase-derived | fact |
| D-16 | The shortened description fields of doctor and local-dev-refresh | Parked under OR-1. The build uses the stated default. | deferred | open |
| D-17 | Test form of AC-1 to AC-4 | Exempt. They are shipped prompt text. No selftest proves them without a prose-presence guard. The diff and the receipt checks score them. | user-answered | intent |
| D-18 | Test form of AC-5 and AC-6 | Holds. The listed check scripts, the selftests and the three CLAUDE.md commands are green on main and stay green. | user-answered | intent |

Options weighed:

- D-1: amend the facts in the body, keep the body and fix it in rows, or have the operator rewrite it. The operator chose the facts-only amendment.
- D-2: keep the bullet reworded, or delete it as item 1 said. The operator chose to keep it reworded.
- D-5: checklist and agent, or checklist only. The operator chose checklist and agent.
- D-6: fix the comment and keep the probe, code-review.mjs only, or also the probe. The operator chose to fix the comment and keep the probe.
- D-7: delete the imperative, or reword it to point at :661. The operator chose to delete it.
- D-8: keep the shapes and drop the engine, or delete the contracts. The operator chose to keep the shapes.
- D-17: exempt all four, or test some. The operator chose to exempt all four.
- D-18: holds, or exempt. The operator chose holds.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Length and wording of the shortened doctor and local-dev-refresh description fields | reversible-default-and-flag |

OR-1 default: keep what the skill does and when to run it, and drop the list of checks. Intake chose it from item 7's own wording. A reversal is a one-line edit per skill.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6

AC-1: exempt — shipped prompt text; no selftest proves it without a prose-presence guard, so the diff scores it
AC-2: exempt — shipped prompt text; no selftest proves it without a prose-presence guard, so the diff scores it
AC-3: exempt — shipped prompt text; no selftest proves it without a prose-presence guard, so the diff scores it
AC-4: exempt — shipped prompt text; the receipt's grep check scores it
AC-5: holds — the lockstep, frontmatter, reviewer-reference and model-tier checks and the runtime-shim, text-contract, audit and doctor selftests stay green
AC-6: holds — shellcheck, the JSON check and the selftest sweep from CLAUDE.md stay green

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Over-engineering severity in the review-lead report | decided (D-5) |
| S-2 | Strengths section of the review-lead report | decided (D-9) |
| S-3 | A diff reviewer's REVIEW_RESULT block | decided (D-4) |
| S-4 | An artifact reviewer's REVIEW_RESULT block | decided (D-2) |
| S-5 | The /audit-history message when no ledger exists | decided (D-12) |
| S-6 | The audit-toolkit description in the plugin list | decided (D-12) |
| S-7 | A design wrapper agent's return to its dispatcher | decided (D-8) |
| S-8 | Doctor and local-dev-refresh lines in the skill list | out-of-scope — their wording is parked under OR-1 with a stated default. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`
- `bash scripts/check-frontmatter.sh`
- `bash plugins/review-toolkit/scripts/check-reviewer-references.sh </dev/null`
- `bash plugins/review-toolkit/scripts/check-model-tiers.sh </dev/null`
- `! git grep -q -e PRODUCE_SCHEMA -e 'Opus 4' -- plugins`
- `! git grep -q settings.audit-template -- plugins`

## Intake steps

Requirements: the ticket body as written. spec-reviewer found 1 blocker, which did not hold against the code. The operator chose a facts-only amendment for 8 gaps.

Split: not split. It is a prompt-text fix, and items 1 and 12 edit the same lockstep block. codebase-explorer was not dispatched.

Explore: done. Read reviewer-baseline, code-review.mjs, the design reviewers' lockstep block, lead-pass-checklist, review-lead, the audit referrers and the check scripts.

Fan-out: ran — 17 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: dispatch-path-trace failed · guard-and-lockstep-coupling fable 4/6 · script-owns-it-verification opus 3/6 · installed-consumer-surface fable 5/6 · premortem fable 5/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | guard-and-lockstep-coupling | Items 1 and 12 give two end states for one lockstep bullet; the third copy matches minus the clause (`design-faithful-plan-reviewer.md:212-225`). | already-had | became D-2 |
| F-2 | guard-and-lockstep-coupling | The design Output deltas carry the block's key list, and the eval rubrics read that block (`figma-faithful-spec-reviewer-eval/rubric.py:65-67`). | new | became D-2 and D-3 |
| F-3 | guard-and-lockstep-coupling | check-model-tiers.sh blocks on open stdin and needs `</dev/null` (`check-model-tiers.sh:106-107`). | already-had | became a Checks line |
| F-4 | guard-and-lockstep-coupling | Four files name the template, and no selftest fails if one is left (`audit-history.sh:61`). | new | became D-12 and a Checks line |
| F-5 | script-owns-it-verification | doctor SKILL.md:22 already names a file doctor.sh never checks (`doctor.sh:323-324`). | new | not material — item 7 already deletes that line |
| F-6 | script-owns-it-verification | ledger-lint.sh owns no word limit, and receipt.md:205-206 and :214-215 have no lint equivalent. | new | became D-11 |
| F-7 | script-owns-it-verification | Several cited ranges end mid-sentence; run.sh prompt item 7 covers the build steer rows (`run.sh:1096`). | new | became D-11 |
| F-8 | installed-consumer-surface | The repo-root import fails from a consumer directory; the lib loads by absolute path (`design-faithful-spec/SKILL.md:53`). | already-had | became D-13 |
| F-9 | installed-consumer-surface | Plugin path variables are unset in the Bash tool, and single quotes block expansion. | new | became D-13 |
| F-10 | installed-consumer-surface | Sibling skills resolve plugin files by base directory or by plugin root (`review-lead/SKILL.md:27-31`). | new | became D-13 |
| F-11 | installed-consumer-surface | It is unverified whether the harness substitutes the plugin root in skill text (`receipt.md:11`). | new | became D-13; D-13 does not rely on it |
| F-12 | installed-consumer-surface | The audit plugin.json description still advertises the template (`plugin.json:3`). | new | became D-12 |
| F-13 | premortem | The baseline rewrite must keep the severity map and suppressed[] that the block still uses (`code-review.mjs:343-345`). | new | became D-4; the ticket keeps its post-merge check |
| F-14 | premortem | Item 10 does not name which "max 25 words" copy stays (`receipt.md:132`). | new | became D-11 |
| F-15 | premortem | A variable inside the snippet's single-quoted string does not resolve (`design-faithful-spec/SKILL.md:52-53`). | new | became D-13 |
| F-16 | premortem | The Complexity Critical list has three items, and complexity-reviewer.md:27 grades them Critical. | overturned (snapshot: "The Complexity Premature abstraction item leaves the Critical list") | became D-5 |
| F-17 | premortem | AC-1 misses workflows, and stall-probe.mjs holds a copy of the triage nudge (`stall-probe.mjs:154-159`). | new | became D-6 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Amend the ticket body before the interview | Yes, facts only: citations, reasons, two missed sites, line numbers re-anchored to b1763e05. No AC or scope change. Operator chose it. |
    | D-2 | Items 1 and 12 both edit the artifact reviewers' Output bullet | Open. Recommend: keep the bullet in the lockstep group, without the StructuredOutput sentence and the provenance clause; it still names the REVIEW_RESULT block shape that no caller names. |
    | D-3 | Diff reviewers' Output deltas (figma-faithful-reviewer :58,:150; design-faithful-reviewer :36) | Delete them once the baseline is right; keep the design-faithful-reviewer :36 rule that library-conformance summary lines go in `summary`. |
    | D-4 | What the rewritten reviewer-baseline Output Mode says | Reviewers run schema-free; the dispatch prompt names the wire format: the REVIEW_RESULT sentinel, then one fenced JSON block, last. With no wrapper, the prose format applies. |
    | D-5 | Severity ceiling for over-engineering in lead-pass-checklist | Warning. The Complexity "Premature abstraction" item leaves the Critical list (:168-170 caps the class at Warning). |
    | D-6 | QUERIES.md:18-25 | Open. Recommend: keep the reasons for the pair (SETUP.md:29 points at them); cut the origin-story sentences per the no-archeology rule. |
    | D-7 | Stale comment at intake-review.mjs:209-214 | Open. Recommend: in scope; it says reviewer-baseline makes structured output the sole output under schema dispatch, which item 1 makes more false. |
    | D-8 | Positive ACs for items 4 and 6-11 | Open. Recommend: none; the body lists every site, and the scope review scores the diff against it. |
    | D-9 | Delete settings.audit-template.json | Yes. Its own note says its hook paths resolve only when the plugin is present, and with the plugin present hooks.json already wires the same hook. |
    | D-10 | Commit verb and trailer | fix (patch): corrections to shipped prompts, nothing new, not breaking. Changelog trailer names the removed template; Migration: none. |

</details>
