# second-shift #103 — reject undriveable two-id monorepo configs

## Problem

`topology.type == "monorepo"` with two `repos` entries (e.g. `api`/`web`) is
`config-lint`-legal but undriveable: `verifyctl.sh` hard-dies (`exit 2`, no
`topology.repos` entry with `path: "."`) because the per-repo `--repo` loop is
gated on `topology.type == "be-fe-pair"`. A two-id monorepo config lints clean
and then silently can't run.

## Decision (maintainer, locked)

**REJECT**: `config-lint` rejects a two-id monorepo config and points at
`commands.<id>.lanes` / `extraLanes` for the second surface. The Stage-6
`--repo` loop is **not** extended to `monorepo` topology (deferred,
out of scope here).

## Scope

In scope:
- `config-lint.sh` topology rule for `monorepo`.
- Fixture + selftest coverage for the new rule.
- Onboard `SKILL.md` guidance on the supported multi-surface monorepo pattern.

Out of scope (explicitly deferred):
- Extending the Stage-6 `--repo` loop to `monorepo` topology.
- The `collect_format_files` double-prefix sub-defect (moot once two-id
  configs are rejected at lint time).

## Acceptance Criteria

- **AC-1**: `config-lint` FAILS (non-zero exit + a message pointing to
  `commands.<id>.lanes`/`extraLanes`) on a `topology.type == "monorepo"`
  config that has more than one `topology.repos` entry, or has no entry with
  `path == "."`.
- **AC-2**: the existing single-id monorepo shape (one `repos` entry,
  `path == "."`) still passes config-lint — no regression against
  `config-lint-fixtures/valid-monorepo-github.json`.
- **AC-3**: a new fixture
  `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/invalid-monorepo-two-id.json`
  is added, and `config-lint-selftest.sh` asserts it is rejected with the
  `lanes`/`extraLanes` pointer message.
- **AC-4**: multi-surface monorepo guidance (single trio + root fan-out
  scripts, or `extraLanes` for the second workspace) is documented in the
  `second-shift:onboard` skill's `SKILL.md`.
