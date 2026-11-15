# Plan — scope-named majors, no-op migrations, a frozen marketplace version and single PR numbers

AC-5 is exempt (doc and CI-label wording). Every other AC has its cases in the release selftest.

## 1. Breaking commits major only the plugins they name

- [ ] 1.1 Cases: a `feat(alpha, gamma)!:` commit touching alpha and beta majors alpha, gives beta a minor and leaves gamma out, with no BREAKING line under beta; a verbless footer-only commit majors both touched plugins; a scope naming only untouched or near-miss names falls back to every touched plugin (scripts/derive-release-selftest.sh) [AC-1]
- [ ] 1.2 Record each commit's type level and the plugins that take its major; aggregate per plugin; render the BREAKING line only under those plugins (scripts/derive-release.sh)

## 2. `Migration: none` is a no-op

- [ ] 2.1 Cases: bare, punctuated, mid-line and two-block no-op migrations give no What-breaks entry; `none` followed by prose and a real migration render their whole blocks; a breaking commit keeps its entry without the no-op block (scripts/derive-release-selftest.sh) [AC-2]
- [ ] 2.2 Render under What breaks only the Changelog blocks whose migration is not a no-op (scripts/derive-release.sh)

## 3. The marketplace version is frozen

- [ ] 3.1 Case: a branch that changes `metadata.version` in `.claude-plugin/marketplace.json` fails the frozen-files check (scripts/derive-release-selftest.sh) [AC-3]
- [ ] 3.2 Add the hard marketplace row (scripts/check-frozen-files.sh)

## 4. One PR number per generated line

- [ ] 4.1 Cases: the CHANGELOG bullet, the What-breaks entry and the subject-only line each carry `(#N)` once (scripts/derive-release-selftest.sh) [AC-4]
- [ ] 4.2 Strip the subject's trailing `(#N)` before the suffix is appended at the three render sites (scripts/derive-release.sh)

## 5. Docs and CI labels

- [ ] 5.1 State the scope rule, the no-op migration rule and the marketplace freeze (CLAUDE.md, docs/releasing.md, scripts/derive-release.sh, scripts/check-frozen-files.sh, .github/workflows/ci.yml)
- [ ] 5.2 Describe the release-PR check as a version-string change, not a derived bump (docs/releasing.md, .github/workflows/ci.yml, scripts/check-plugin-version-bumps.sh)
- [ ] 5.3 List v16.0.0, v17.0.0 and v18.0.0 as non-config majors and correct the configVersion sentences (docs/migrations/README.md)
