# Plan — #1063 doctor and onboard propose testRunners for a vitest or jest repo

## 1. Tests

- [ ] 1.1 a vitest repo with no testRunners gets the T6 finding: its `value` passes the in-repo config-lint as a `vitest-json` entry, the proposal embeds the same JSON, the evidence names vitest and its version from yarn.lock (berry and v1) and pnpm-lock.yaml, the configured and the direct command forms, and zero matches gives no value (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-1]
- [ ] 1.2 a jest repo gets the T6 finding: its `value` passes the in-repo config-lint as a `jest-json` entry, its evidence names jest and its package-lock.json version, npm gets `--`, and a jest config file raises the caveat (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-2]
- [ ] 1.3 a non-empty testRunners, including the drafted `value` itself, silences the finding, and an empty array does not (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-3]
- [ ] 1.4 neither runner, both runners, and a tree outside git give no finding and a notEvaluated line naming what the grill saw (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-4]
- [ ] 1.5 another root-manifest script that runs the same runner with `--config` or `-c` is named in the evidence as not covered (plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh) [AC-5]

## 2. Implementation

- [ ] 2.1 add_finding takes an optional `value`; trigger 6 detects the runner, reads the lockfile version, builds the entry, counts its globs with `case` semantics, and names config files and second suites (plugins/second-shift/skills/onboard/tools/config-grill.sh)
- [ ] 2.2 onboard drafts the finding's `value` into `commands.<id>.testRunners` and re-runs the grill; the schema doc stops saying onboard does not draft the key (plugins/second-shift/skills/onboard/SKILL.md, docs/config-schema.md)
