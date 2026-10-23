# Plan — consumer docs, onboard and intake describe the single-session lane review

## 1. Deprecate `reviewers.default`

- [ ] 1.1 Test that config-grill reports a set `reviewers.default` as an advisory finding and stays silent when the key is absent (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-12]
- [ ] 1.2 Add the `reviewers.default` finding to config-grill (plugins/second-shift/skills/onboard/tools/config-grill.sh)
- [ ] 1.3 Test that the commit hook passes an unknown name in `reviewers.default` (plugins/review-toolkit/scripts/check-reviewer-references-selftest.sh) [AC-12]
- [ ] 1.4 Drop the `DEFAULT-UNKNOWN` class from the commit hook (plugins/review-toolkit/scripts/check-reviewer-references.sh)
- [ ] 1.5 Mark the key deprecated in the schema and in config-lint's selftest comment (schema/second-shift.config.schema.json, plugins/dev-pipeline/tools/config-lint-selftest.sh)

## 2. Doctor's upgrade-skew check

- [ ] 2.1 Test that the skew check fails on a review-toolkit that lacks `workflows/intake-fanout.mjs` and passes one that lacks `workflows/code-review.mjs` (plugins/second-shift/skills/doctor/tools/doctor-selftest.sh) [AC-12]
- [ ] 2.2 Check the files each reader reads: the intake workflows for intake-toolkit, `model-tiering.md` for dev-pipeline (plugins/second-shift/skills/doctor/tools/doctor.sh)

## 3. Retire the `review panel` row

- [ ] 3.1 Drop plan-interview's ask for the row (plugins/intake-toolkit/skills/plan-interview/SKILL.md)
- [ ] 3.2 Drop the row's exact-text exception (plugins/intake-toolkit/skills/intake/receipt.md)
- [ ] 3.3 Drop the row and `reviewers.default` as opt-in carriers, and say no shipped caller declares the trimmed panel (plugins/review-toolkit/skills/review-lead/SKILL.md, plugins/review-toolkit/agents/scope-completeness-reviewer.md)

## 4. Docs and onboard

- [ ] 4.1 Describe the one-session lane review in the consumer docs (docs/config-schema.md, docs/extending.md, docs/onboarding.md, docs/extension-points.md, plugins/second-shift/skills/onboard/SKILL.md)
- [ ] 4.2 Describe it in the consumer template, this repo's copy, the README and the review-toolkit manifest description (plugins/second-shift/templates/consumer/SECOND-SHIFT.md, .claude/SECOND-SHIFT.md, README.md, plugins/review-toolkit/.claude-plugin/plugin.json)
- [ ] 4.3 Reword the knowledge-base reader line and the grill's webComponentGlobs benefit (plugins/review-toolkit/scripts/section-catalog.txt, plugins/second-shift/skills/onboard/tools/config-grill.sh)
