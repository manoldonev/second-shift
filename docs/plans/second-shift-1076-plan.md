# Plan — #1076 The design-fidelity seat checks UI overrides and justification comments against the installed library

Decision record: [second-shift-1076-decisions.md](second-shift-1076-decisions.md).

## 1. Repo-wide default web-component glob

- [ ] 1.1 Test: with `reviewers.webComponentGlobs` absent, config-grill reports the resolved default as `**/*.{tsx,jsx,vue,svelte,css,scss,less}`, and a component file at any depth with one of those extensions satisfies it (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-7]
- [ ] 1.2 Change the resolved default in config-grill.sh and restate it wherever the default is stated: review-lead SKILL.md, onboard SKILL.md, docs/onboarding.md, the config schema, docs/config-schema.md and README.md (plugins/second-shift/skills/onboard/tools/config-grill.sh, plugins/review-toolkit/skills/review-lead/SKILL.md, plugins/second-shift/skills/onboard/SKILL.md, docs/onboarding.md, schema/second-shift.config.schema.json, docs/config-schema.md, README.md)

## 2. The build authoring rule, UI libraries only

- [ ] 2.1 Test: the build prompt run.sh generates for a ticket with no design frames carries the UI-library authoring sentence (plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-5]
- [ ] 2.2 Add the unconditional sentence to run.sh build_prompt, and the same rule to the figma-faithful and design-faithful skills (plugins/dev-pipeline/skills/run/run.sh, plugins/design-toolkit/skills/figma-faithful/SKILL.md, plugins/design-toolkit/skills/design-faithful/SKILL.md)

## 3. The library-conformance check in both fidelity seats

- [ ] 3.1 Add the check to figma-faithful-reviewer: resolve each import, open the installed wrapper and base library, classify each override and wrapper prop, verify each justification comment, cite the installed line, one summary line when source is absent, one summary line per checked override, severities, and the narrowed escape hatch (plugins/design-toolkit/agents/figma-faithful-reviewer.md)
- [ ] 3.2 Add the same check to design-faithful-reviewer, with the narrowed arbitrary-values rule and the narrowed accessibility-attributes line (plugins/design-toolkit/agents/design-faithful-reviewer.md)
- [ ] 3.3 Narrow the named-constant escape hatch in the figma-faithful skill so it never waives a library-redundant value (plugins/design-toolkit/skills/figma-faithful/SKILL.md)
- [ ] 3.4 Name library conformance in review-lead's statement of what the design-fidelity dimension asserts (plugins/review-toolkit/skills/review-lead/SKILL.md)

## 4. One shared library-conformance skill

- [ ] 4.1 Move the conformance procedure into the library-conformance skill, loaded by both fidelity seats; each seat keeps its stack's override forms; every conformance class a Warning; design-faithful-reviewer gets the turn-10 deadline (plugins/design-toolkit/skills/library-conformance/SKILL.md, plugins/design-toolkit/agents/figma-faithful-reviewer.md, plugins/design-toolkit/agents/design-faithful-reviewer.md)

## 5. review-lead renders the seat summary

- [ ] 5.1 Carry a fidelity seat's summary lines into the Review Summary, and document an explicit empty web-component glob (plugins/review-toolkit/skills/review-lead/SKILL.md)

## 6. An empty web-component glob is a declared no-surface

- [ ] 6.1 Test: config-grill treats an explicit [] as declared and lands it in notEvaluated, with and without a UI file in the tree (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh)
- [ ] 6.2 Recognize the explicit [] in config-grill; state the switch in the schema, config-schema.md, onboarding.md and README.md; set it in this repo's config (plugins/second-shift/skills/onboard/tools/config-grill.sh, schema/second-shift.config.schema.json, docs/config-schema.md, docs/onboarding.md, README.md, .claude/second-shift.config.json)

## 7. Eval fixture 12 and turn counts

- [ ] 7.1 Add the size-keyed stand-in entry and fixture 12, move the two Button citations, bump the fixture set to v3, and record turns per changelog row (plugins/design-toolkit/evals/figma-faithful-reviewer-eval/, plugins/review-toolkit/evals/agent-eval-kit/run-eval.py)
