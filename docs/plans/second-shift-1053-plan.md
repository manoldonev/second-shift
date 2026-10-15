# Plan — #1053 the fails-without-the-change check judges each named test

## 1. Tests

- [ ] 1.1 plan-coverage --files emits a backtick-quoted file::case holding spaces, parentheses or > as one tab-separated row, and an unterminated backtick or a bare case that needs quoting as a red unparseable line (plugins/dev-pipeline/tools/plan-coverage-selftest.sh) [AC-8]
- [ ] 1.2 config-lint refuses a reporting runner missing its placeholders or required flags, a placeholder its format does not take, a space-form flag, a second reporter, an outputFile sub-key and an unknown format; accepts every format's valid form and testSupport (plugins/dev-pipeline/tools/config-lint-selftest.sh) [AC-10]
- [ ] 1.3 the json runners' judge through run.sh: a named test that passes beside an unrelated failing one, a missing, skipped or wrong-form named test, a file that does not load and a vitest beforeAll failure (file-level at the head, red when the head fails), three files in one call per leg for vitest and for jest, two matching rows, and a timeout, a missing report and failed rows with exit 0 (plugins/dev-pipeline/skills/run/run-judge-selftest.sh) [AC-1] [AC-2] [AC-3] [AC-4] [AC-6] [AC-7]
- [ ] 1.4 the cases runner through run.sh and the real run-selftest-lib.sh: folded fixture blocks judged by name with testSupport bringing the head's lib, red naming testSupport when no case line prints, only the selected blocks launching run.sh with unselected blocks silent, and a selected block that fails at the head red (plugins/dev-pipeline/skills/run/run-cases-selftest.sh) [AC-9] [AC-11]

## 2. Implementation

- [ ] 2.1 the plan grammar: backtick spans lexed across the task line, file::case tokens, the tab-separated --files map (plugins/dev-pipeline/tools/plan-coverage.sh)
- [ ] 2.2 config-lint, the JSON schema and the shadowing rows learn format and testSupport (plugins/dev-pipeline/tools/config-lint.sh, schema/second-shift.config.schema.json, plugins/dev-pipeline/tools/check-config-shadowing.sh)
- [ ] 2.3 the lib prints one case line per fixture block at exit and honors SELFTEST_CASES (plugins/dev-pipeline/skills/run/run-selftest-lib.sh)
- [ ] 2.4 run.sh's judge: per-format calls, the batch, testSupport, the per-test judge, the head leg, report copies, the run block's file-level label (plugins/dev-pipeline/skills/run/run.sh)
- [ ] 2.5 the wording: the build prompt, docs/config-schema.md, build/SKILL.md, interviewing-baseline's Test intent paragraph (plugins/dev-pipeline/skills/run/run.sh, docs/config-schema.md, plugins/dev-pipeline/skills/build/SKILL.md, plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md)
- [ ] 2.6 the existing suites read the tab-separated map (plugins/dev-pipeline/tools/plan-coverage-selftest.sh)
