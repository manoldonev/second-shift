# Plan — correct wrong and duplicated text in shipped prompts

AC-1 to AC-4 are exempt (shipped prompt text). The diff and the receipt's grep checks score them.
AC-5 and AC-6 hold: the existing checks stay green at the head.

## 1. Checks that stay green

- [ ] 1.1 The lockstep, frontmatter, reviewer-reference and model-tier checks and the runtime-shim, text-contract, audit and doctor selftests pass (scripts/check-lockstep-pairs.sh, scripts/check-frontmatter.sh, plugins/review-toolkit/scripts/check-reviewer-references.sh, plugins/review-toolkit/scripts/check-model-tiers.sh, plugins/review-toolkit/workflows/runtime-shim-selftest.mjs, plugins/review-toolkit/scripts/text-contract-selftest.sh, plugins/audit-toolkit/scripts/audit-selftest.sh, plugins/second-shift/skills/doctor/tools/doctor-selftest.sh) [AC-5]
- [ ] 1.2 Shellcheck, the JSON check and the selftest sweep pass (tools/run-selftests.sh) [AC-6]

## 2. Reviewer output contract

- [ ] 2.1 Rewrite the reviewer-baseline Output Mode for the schema-free REVIEW_RESULT block; keep the severity map and suppressed[] (plugins/review-toolkit/skills/reviewer-baseline/SKILL.md)
- [ ] 2.2 Drop the StructuredOutput text from the triage nudge and the stale intake comment (plugins/review-toolkit/workflows/code-review.mjs, plugins/review-toolkit/workflows/intake-review.mjs)
- [ ] 2.3 Point codebase-explorer and mutation-review at the text contract (plugins/review-toolkit/agents/codebase-explorer.md, plugins/review-toolkit/skills/mutation-review/SKILL.md)
- [ ] 2.4 Reword the artifact reviewers' Output bullet and add design-faithful-plan-reviewer to the lockstep group (plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md, plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md, plugins/design-toolkit/agents/design-faithful-plan-reviewer.md)
- [ ] 2.5 Delete the diff reviewers' Output deltas; keep the summary-line rule (plugins/design-toolkit/agents/figma-faithful-reviewer.md, plugins/design-toolkit/agents/design-faithful-reviewer.md)

## 3. Review-lead

- [ ] 3.1 Remove the schema from the dispatch shape, the Opus version, the dead-key report line, the restating comment, "Filter aggressively" and three restating Rules bullets (plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 3.2 Cap over-engineering at Warning in the checklist and the complexity reviewer (plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md, plugins/review-toolkit/agents/complexity-reviewer.md)

## 4. Design agents

- [ ] 4.1 Remove the engine name and history; keep the return shapes as the output contract (plugins/design-toolkit/agents/design-faithful.md, plugins/design-toolkit/agents/design-faithful-spec.md, plugins/design-toolkit/skills/design-faithful/SKILL.md, plugins/design-toolkit/skills/design-faithful/README.md, plugins/design-toolkit/skills/design-faithful-spec/SKILL.md)
- [ ] 4.2 Resolve the extractor import from the skill's base directory (plugins/design-toolkit/skills/design-faithful-spec/SKILL.md)
- [ ] 4.3 Correct the design agent count (plugins/second-shift/templates/consumer/SECOND-SHIFT.md)

## 5. Prose a script already prints

- [ ] 5.1 Delete the doctor check list and shorten the doctor and local-dev-refresh descriptions (plugins/second-shift/skills/doctor/SKILL.md, plugins/second-shift/skills/local-dev-refresh/SKILL.md)
- [ ] 5.2 Delete the never-emit key lists; keep the extraLanes routing sentence (plugins/second-shift/skills/onboard/SKILL.md)
- [ ] 5.3 Delete the lint-refusal lists, the word-limit repeats and the restated avoid list (plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md, plugins/intake-toolkit/skills/intake/receipt.md)
- [ ] 5.4 Delete the repeated PR body order (plugins/dev-pipeline/skills/build/SKILL.md)

## 6. Audit toolkit

- [ ] 6.1 Remove the gate-evidence claims and the manual-mode wiring, and delete the settings template (plugins/audit-toolkit/skills/audit/SETUP.md, plugins/audit-toolkit/skills/audit/QUERIES.md, plugins/audit-toolkit/skills/audit/SKILL.md, plugins/audit-toolkit/hooks/audit-tool-calls.sh, plugins/audit-toolkit/scripts/audit-history.sh, plugins/audit-toolkit/scripts/audit-selftest.sh, plugins/audit-toolkit/.claude-plugin/plugin.json, plugins/audit-toolkit/templates/settings.audit-template.json)
