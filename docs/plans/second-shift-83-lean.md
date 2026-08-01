# Lean spec — #83: verifyctl leaks pipeline seam vars into configured lane commands

## Context

`verifyctl.sh` runs consumer-configured lane commands (`setup`, `format`, `lint`,
`type-check`, `test`, `lint --fix`/recheck, `extraLanes`) as `bash -c "$cmd"` children
that inherit its **entire** exported environment. When this repo dogfoods itself, the
configured `test` command is the very selftest sweep that honors
`SECOND_SHIFT_CONFIG` / `SECOND_SHIFT_REPO_ROOT` / `STATECTL_STATE_DIR` as documented
overrides, so ambient pipeline values leak in and clobber the fixtures — this produced
~20 spurious failures during run #34 while `main` was green in a clean env. The sibling
tool that runs the same lanes, `preflight.sh:245`'s `run_lane()`, already scrubs three
of these vars with `env -u`; `verifyctl.sh` has no equivalent, and preflight's own list
is narrower than the seam set that actually leaks.

## Decision Ledger (from the issue)

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Root cause | `verifyctl.sh`'s ten `bash -c`/prettier child sites inherit the full exported env; `preflight.sh:245` already scrubs a narrower list for the same lane shape. | codebase-derived |
| D-2 | Fix shape | One `SEAM_SCRUB` single-quoted pipe literal per file, inside a `LOCKSTEP-BEGIN/END` marker block, expanded to `env -u` at every child site via the existing `${VA_REPO[@]+"${VA_REPO[@]}"}`-style guarded-array idiom (bash-3.2-safe). | issue-specified |
| D-3 | Denylist | `SECOND_SHIFT_CONFIG` (first — order is load-bearing for the mutation sed), `SECOND_SHIFT_REPO_ROOT`, `SECOND_SHIFT_EXTENSION_MANIFEST`, `SECOND_SHIFT_PLUGIN_ROOT`, `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT`, `SECOND_SHIFT_DEV_PIPELINE_ROOT`, `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT`, `SECOND_SHIFT_SECTION_CATALOG`, `STATECTL_STATE_DIR`, `STATECTL_WRITER`, `DEV_PIPELINE_MODE`, `BRANCH_PREFIX`, `KEY_PATTERN`. preflight.sh additionally scrubs its own `PREFLIGHT_DOCTOR_CMD`. | issue-specified |
| D-4 | Never scrubbed | `GH_BOT`, `CLAUDE_CODE_SESSION_ID` (operator/harness identity), `SKIP_STRESS`, `CI` (this repo's own test command sets/asserts them), `PATH`, `VERIFYCTL_TEST_MARKERS` (load-bearing for the selftest shim). Never `env -i`. | issue-specified |
| D-5 | Representation is forced | The pipe-literal `'...|...'` form is required so `scripts/check-lockstep-pairs.sh`'s `first_enum` (`head -n1` of `'[^']*|[^']*'`) has something to compare; a bare `env -u` fragment or shell array carries no such literal. Already recorded as a DROPPED trap in `scripts/lockstep-manifest.tsv`. | codebase-derived, confirmed at `scripts/lockstep-manifest.tsv` |
| D-6 | Marker-block hygiene | Each `LOCKSTEP-BEGIN/END` block contains only the `SEAM_SCRUB=` line — no comments, no apostrophes (an apostrophe anywhere in the block breaks `first_enum`; a second quoted pipe-literal silently becomes the compared one). | issue-specified |
| D-7 | Existing `unset` lines in the eight selftests stay | They defend the direct-invocation path (operator sweep, CI's `find *-selftest.sh` glob) that never goes through verifyctl; removing them turns defense-in-depth into a single point of failure. | issue-specified (Out of scope) |

## Acceptance Criteria

- AC-1: `plugins/dev-pipeline/skills/run/verifyctl.sh` defines one `SEAM_SCRUB` variable
  holding the single-quoted pipe-separated denylist from D-3 (repo-scoped list, 13
  tokens, `SECOND_SHIFT_CONFIG` first), inside a `LOCKSTEP-BEGIN/END` marker block
  containing only that assignment line. All ten child-invocation sites (the two
  `resolve_prettier` calls at the INERT-lane `--check` and SUITE-lane `--write` sites,
  the setup-lane loop, the config-mode `format` command, the concurrent
  lint/type-check/test trio, the `lint --fix` command, the `lint` recheck, and the
  `extraLanes` loop) expand `$SEAM_SCRUB` into `env -u` arguments ahead of `bash -c` (or
  the prettier invocation), using the guarded-array idiom already established at
  `verifyctl.sh:654` (`${VA_REPO[@]+"${VA_REPO[@]}"}`) rather than a bare `"${A[@]}"`,
  so `set -u` on bash 3.2 does not break on an empty expansion.
- AC-2: `plugins/dev-pipeline/skills/run/tools/preflight.sh`'s `run_lane()` (currently
  `env -u SECOND_SHIFT_REPO_ROOT -u SECOND_SHIFT_CONFIG -u PREFLIGHT_DOCTOR_CMD`) is
  widened to the same 13-token `SEAM_SCRUB` list plus its own
  `PREFLIGHT_DOCTOR_CMD`, in a matching `LOCKSTEP-BEGIN/END` marker block containing
  only the `SEAM_SCRUB=` assignment.
- AC-3: `scripts/lockstep-manifest.tsv` gets one new `subset-of` row, `fileA` =
  `preflight.sh` (the superset — it carries the extra `PREFLIGHT_DOCTOR_CMD` token),
  `fileB` = `verifyctl.sh`, both anchored on the `SEAM_SCRUB` block. `bash
  scripts/check-lockstep-pairs.sh` passes.
- AC-4: `verifyctl-selftest.sh` gets new `(vNN)`-style cases (fixture pattern at the
  top of the file, PATH-shimmed `yarn` driven by marker files):
  - Positive: export poison values for `SECOND_SHIFT_CONFIG`, `SECOND_SHIFT_REPO_ROOT`,
    and `STATECTL_STATE_DIR` in the selftest's own shell, point a configured lane's
    command at a one-line child script asserting each is unset/empty inside the child,
    and assert the run still reaches verdict `pass`. Cover at least the `test` lane,
    a `setup` lane, and an `extraLanes` lane — not `test` alone.
  - Negative (over-scrub guard): the same child additionally asserts `PATH` and
    `VERIFYCTL_TEST_MARKERS` **are** still present, catching a future `env -i`
    regression.
  - Existing cases stay green unmodified (none of them pass `SECOND_SHIFT_CONFIG` to a
    *child* lane's env, only to verifyctl's own).
- AC-5: End-to-end proof recorded in the PR body — a full `verifyctl-selftest.sh` run
  with `SECOND_SHIFT_CONFIG` / `SECOND_SHIFT_REPO_ROOT` / `STATECTL_STATE_DIR`
  deliberately exported in the invoking shell stays green (the exact condition that
  produced #34's spurious failures).
- AC-6: Mutation obligations, all in this diff:
  - `tools/mutation-catalog.tsv` gets one new row for the `SEAM_SCRUB` sed, pattern-
    anchored on the canonical literal (e.g. a token-drop from the quoted string), not
    on an `env -u` fragment (which does not exist under the pipe-literal
    representation); its predicted killer is the new AC-4 case, not
    `check-lockstep-pairs.sh` (dropping one token from the `subset-of` side keeps it a
    valid subset, so lockstep alone would stay green under that mutant).
  - `tools/mutation-baseline.tsv` re-baselines `verifyctl.sh`'s existing generic
    ordinals (currently 6 rows, `plugins/dev-pipeline/skills/run/verifyctl.sh::*`) and
    `preflight.sh`'s existing generic ordinals (currently 5 rows,
    `plugins/dev-pipeline/skills/run/tools/preflight.sh::*`) to whatever the edit
    re-keys them to.
  - The two existing catalog rows `preflight-queue-label` and `verifyctl-targetrepos`
    are re-anchored if the edit moved their line addresses.
- AC-7: `stages/6-verify.md` and `docs/config-schema.md` state the env-hermeticity
  contract for a configured lane command (which vars are scrubbed and why); a new
  paragraph in `docs/testing.md` explains why both `preflight.sh` and `verifyctl.sh`
  carry the scrub independently (they run the same lanes via two different code paths)
  and why the eight existing selftest `unset` lines are additionally kept (D-7).
- AC-8: shellcheck, jq, and the full `*-selftest.sh` sweep (`-P 4`, `SKIP_STRESS=1`)
  stay green. `bash tools/mutation-sweep.sh --mode pr --base origin/main` is clean
  against the new/re-anchored rows.

## Out of scope

- Removing any of the eight existing `unset` lines in direct-invocation selftests
  (D-7) — they cover a different call path than this fix.
- #75 (baseline-red signalling) — adjacent, separate.
- The issue-form half of the original two-part #83, tracked separately.
