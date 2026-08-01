# #299 — schema-validate the GitHub issue forms + close the two gaps the schema cannot cover

Split out of #83 (follow-ups from #34). Adds a pinned `check-jsonschema` CI step that
validates `.github/ISSUE_TEMPLATE/*.yml` against GitHub's own issue-forms/issue-config
JSON Schemas, proven by a rejection assertion against checked-in bad fixtures. Two defect
classes the schema structurally cannot catch (`render:` on a `required:` field; `id`
uniqueness) stay owned by the local selftest, which also gets a glob-based form list and a
hard-fail (not skip) when no YAML parser is available.

## Acceptance criteria

- AC-1: `.github/workflows/ci.yml` installs `check-jsonschema` via `pipx` at a pinned
  version, confirmed (empirically, ahead of wiring) to expose both
  `vendor.github-issue-forms` and `vendor.github-issue-config` as builtin schema ids.
- AC-2: The new step validates every `.github/ISSUE_TEMPLATE/*.yml` except `config.yml`
  (discovered by glob, not named) against `vendor.github-issue-forms`, and validates
  `config.yml` against `vendor.github-issue-config`.
- AC-3: The same step runs a rejection assertion against the fixtures added under AC-4: the
  step fails if `check-jsonschema` *accepts* any of them.
- AC-4: `tests/issue-forms-fixtures/` gains one bad fixture per catchable defect class,
  confirmed empirically (not assumed) to be rejected by the pinned schema/version: illegal
  `type:`, a misplaced key (`id:` on a `markdown` block), a bogus `render:` language, and a
  top-level key typo. Any class the schema does not actually reject is dropped rather than
  included as a fixture that can't fail red. Fixtures live outside
  `.github/ISSUE_TEMPLATE/` so GitHub never renders them.
- AC-5: `tests/issue-forms-selftest.sh` gains an `id` uniqueness check within each real
  form (the schema enforces `uniqueItems` only on dropdown `options`, not on field ids).
- AC-6: `tests/issue-forms-selftest.sh` gains a check that no field carries `render:`
  together with `validations.required: true` (the schema has no `not` keyword, so this
  combination is schema-legal but is this ticket's own headline uncatchable example).
- AC-7: `tests/issue-forms-selftest.sh`'s hardcoded `FORMS=(...)` list is replaced by a
  glob over `.github/ISSUE_TEMPLATE/*.yml` minus `config.yml` (already handled separately),
  so a new form is covered on arrival with no selftest edit. The explicit
  `expect_required` table for the three known forms is kept as-is.
- AC-8: `tests/issue-forms-selftest.sh`'s YAML-parser resolution (ruby → python3+PyYAML)
  becomes a hard FAIL when neither is available, mirroring
  `scripts/check-workflows-selftest.sh:29-42`. Today's `yaml_parses()` reports absent-ruby
  as a PASS ("YAML parse skipped"); that is the change.
- AC-9: No `tools/mutation-exclusions.tsv` / `tools/mutation-catalog.tsv` entry and no new
  `scripts/check-*.sh` — this is a CI-step-only addition (`.yml` fixtures are outside the
  mutation guard universe: git-tracked `*.sh` not matching `*-selftest.sh`).

## Out of scope

- Validating `.github/workflows/*.yml` (owned by actionlint).
- Vendoring the schema into `schema/` — the pinned tool version pins the schema.

## Verification notes

Stage 6's INERT lane skips lint/test on `.sh`/`.yml`/`.md`-only diffs; the full local sweep
(shellcheck + `*-selftest.sh` + jq) is run by hand and reported in the PR body. Commit verb
`ci:`/`test:`; `Changelog: none` (no `plugins/**` change). No frozen release artifact
touched.
