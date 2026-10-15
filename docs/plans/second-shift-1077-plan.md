# Plan — #1077 A planted-defect UI fixture measures the library-conformance check

Decision record: [second-shift-1077-decisions.md](second-shift-1077-decisions.md).

## 1. Fixture checker

- [ ] 1.1 Selftest: the checker passes on the shipped fixtures and counts at least six planted-defect conformance fixtures and one conformance control; it fails on an expected file that does not parse, on a cited line past the end of its file, on a missing file, on a path outside the stand-in, on a non-positive line, and on an empty citation list; it refuses an empty fixture set (plugins/design-toolkit/evals/figma-faithful-reviewer-eval/check-fixtures-selftest.sh) [AC-6]
- [ ] 1.2 The checker: every `fixtures/*.expected.json` parses, and every `disproving` entry names a file under the stand-in and a line that exists in it (plugins/design-toolkit/evals/figma-faithful-reviewer-eval/check-fixtures.sh)

## 2. The `acme-ui` stand-in

- [ ] 2.1 A versioned `package.json` for `@acme/acme-ui`, and a fixture-app `package.json` that declares it as a workspace (fixtures/app/package.json, fixtures/app/packages/acme-ui/package.json)
- [ ] 2.2 Theme overrides, an `sx` merge helper, and bodies for the components the conformance fixtures touch: Button, Tag, Menu, Typography (`ellipsis`), TextField (`aria-label` routing); the other export stubs stay greppable (fixtures/app/packages/acme-ui/src/**)

## 3. Conformance fixtures

- [ ] 3.1 Six planted-defect diffs on the console surface, two per class: theme-redundant `sx`, a false justification comment, wrapper-API misuse; each with an `.expected.json` that carries `disproving` (fixtures/05-*.md … fixtures/10-*.md)
- [ ] 3.2 A conformance clean control with an `.expected.json` that carries `disproving` (fixtures/11-conformance-control-clean.*)

## 4. Eval machinery and docs

- [ ] 4.1 Bump `RUBRIC_VERSION` and `FIXTURE_VERSION`; the judge prompt grades an installed-source citation and a comment flagged false (rubric.py)
- [ ] 4.2 The `run.sh` prompt names the installed workspace package instead of export stubs (run.sh)
- [ ] 4.3 README fixture table and stand-in section; the old baseline is marked superseded (README.md, CLOSEOUT-BASELINE.md)
