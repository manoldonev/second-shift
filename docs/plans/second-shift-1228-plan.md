# Plan — remove `reviewers.default`

## 1. config-lint

- [ ] 1.1 Selftest: a config carrying `reviewers.default`, with a list or with `[]`, fails naming the key and `docs/migrations/v2-to-v3.md`, and prints no bare `reviewers: unknown keys`; retire the two type cases (plugins/dev-pipeline/tools/config-lint-selftest.sh) [AC-1]
- [ ] 1.2 Reject the key by name, drop its type checks, keep the allowlist entry as message routing; rename the valid fixture to `invalid-removed-reviewers-default.json`, add an `[]` fixture, delete the two type fixtures (plugins/dev-pipeline/tools/config-lint.sh, plugins/dev-pipeline/tools/config-lint-fixtures/)
- [ ] 1.3 Delete `properties.reviewers.properties.default` from the schema (schema/second-shift.config.schema.json)

## 2. config-grill

- [ ] 2.1 Selftest: a config that sets `reviewers.default` yields no finding on the key; retire the trigger-7 cases (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-2]
- [ ] 2.2 Delete the trigger-7 block (plugins/second-shift/skills/onboard/tools/config-grill.sh)

## 3. doctor

- [ ] 3.1 Selftest scenario: a configVersion 3 config carrying the key gives one FAIL naming it and the migration doc (plugins/second-shift/skills/doctor/tools/doctor-selftest.sh, plugins/second-shift/skills/doctor/tools/doctor-fixtures/config-reviewers-default.json)
- [ ] 3.2 Name the key in the removed-key list (plugins/second-shift/skills/doctor/tools/doctor.sh)

## 4. check-reviewer-references

- [ ] 4.1 Retire the `default-unknown` and `default-green` cases, their fixture dirs and the header comment (plugins/review-toolkit/scripts/check-reviewer-references-selftest.sh, plugins/review-toolkit/scripts/check-reviewer-references.sh, plugins/review-toolkit/scripts/fixtures/reviewer-references/)

## 5. Prose

- [ ] 5.1 Drop the key from review-lead (plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 5.2 Delete `docs/extending.md` §3.3b and move its panel paragraph into §3.3 (docs/extending.md)
- [ ] 5.3 Drop the key from onboard, onboarding and the config-schema reviewers row; state the removal rule (plugins/second-shift/skills/onboard/SKILL.md, docs/onboarding.md, docs/config-schema.md, docs/migrations/README.md)
- [ ] 5.4 Add the `Dead-key removal` section to the migration note (docs/migrations/v2-to-v3.md)
