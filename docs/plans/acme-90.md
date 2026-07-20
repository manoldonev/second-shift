# Plan: acme-90 — plan-lint xargs-apostrophe bug

## Context

`plan-lint.sh` trims the Acceptance-criteria traceability table cells by piping each through `xargs`:

```sh
id="$(echo "${cells[1]}" | xargs)"
steps="$(echo "${cells[3]}" | xargs)"
tests="$(echo "${cells[4]}" | xargs)"
```

`xargs` reads its input with shell-like quoting rules, so a single quote in any parsed cell — a test named `coverage-can't-fail`, a criterion phrased "the run's verdict" — makes it abort with `xargs: unterminated quote`. Under `set -euo pipefail` the command substitution's failure propagates and `plan-lint.sh` returns non-zero. In run `2026-07-13T212453Z-Mac-fd3f3c6e` (#67) this hard-failed the Stage-4 plan-structure gate on a legitimate plan; the workaround was to keep every table cell apostrophe-free.

Intake narrowed the blast radius: the sibling `ledger-lint.sh` was already fixed in an earlier change. It carries a quoting-safe parameter-expansion `trim()` ([`ledger-lint.sh`](../../plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh):39-44, under its explanatory comment at line 38) and its selftest already asserts an apostrophe-bearing ledger row lints clean ([`ledger-lint-selftest.sh`](../../plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh):104). A repo-wide `grep -rn xargs plugins/**/*.sh` returns only the three `plan-lint.sh` lines plus that file's explanatory comment. **The bug lives only in `plan-lint.sh`.**

## Assumptions

- `ledger-lint.sh` needs no code change; AC-3 is a verification-only criterion satisfied by the existing selftest case `(ll-k)`.
- The replacement is **trim-only**. `xargs` additionally collapsed internal whitespace runs, stripped quotes, and removed backslashes; none of that was intentional or relied upon. The `— no test (<category>)` matcher ([`plan-lint.sh`](../../plugins/dev-pipeline/skills/run/tools/plan-lint.sh):96) already tolerates internal whitespace runs via `[[:space:]]*`, and an `AC-n` id with internal double-spaces never matched the anchored row grep at line 102 in the first place.
- Each plugin keeps its own local `trim()` helper. `dev-pipeline` and `intake-toolkit` are independently distributed plugins; a shared sourced module would cross that boundary for four lines of parameter expansion.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Preserve xargs' internal-whitespace collapsing and quote/backslash stripping, or trim only? | Trim only — mirror `ledger-lint.sh`'s existing `trim()`. The extra normalization was incidental to the xargs idiom, and the two downstream consumers (the no-test regex, the anchored AC-id grep) are insensitive to it. | codebase-derived |
| D-2 | Extract a shared trim helper across the two plugins? | No — keep a local copy per plugin. They are independently distributed; `ledger-lint.sh` already carries its own. | codebase-derived |
| D-3 | Change `ledger-lint.sh` as the issue's third bullet asks? | No code change — the fix is already present. Reframe AC-3 as verification of the existing state. | codebase-derived |

## Affected files/modules

- [`plugins/dev-pipeline/skills/run/tools/plan-lint.sh`](../../plugins/dev-pipeline/skills/run/tools/plan-lint.sh) — replace the three `xargs` trims with a local `trim()` helper.
- [`plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh`](../../plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh) — add an apostrophe-bearing positive case.
- [`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`](../../plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh) — read-only reference for the helper's shape; not modified.

## Reuse inventory

- `trim()` in [`ledger-lint.sh`](../../plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh):39-44 — the reference implementation, copied verbatim into `plan-lint.sh` (including its explanatory comment, adjusted for context). Not a new invention.
- `pass()` / `fail()` / `lint_rc()` in [`plan-lint-selftest.sh`](../../plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh):13-21 — the new selftest case uses the existing harness helpers.
- No new helpers introduced beyond the copied `trim()`.

## Implementation steps

1. In `plan-lint.sh`, add the quoting-safe `trim()` helper next to `violate()` (~line 41), matching `ledger-lint.sh`'s implementation and comment.
2. Replace the three `xargs` pipes at lines 88-90 with `trim` calls: `id="$(trim "${cells[1]}")"` and likewise for `steps` / `tests`.
3. In `plan-lint-selftest.sh`, add positive case `(pl-m)`: derive a plan from `valid-plan.md` whose Test(s) cell contains `coverage-can't-fail`, assert `rc == 0`. Place it with the other positive cases, before the mutants block.
4. Verify `ledger-lint.sh` and its selftest already satisfy AC-3 — confirm `grep -n xargs ledger-lint.sh` returns only the line-38 explanatory comment (no functional `xargs` call), that `git status --porcelain plugins/intake-toolkit/` stays empty, and that selftest case `(ll-k)` passes. No edit.

## Test strategy

Verify-after: this is a bug fix in a lint script whose own selftest is the regression harness. The new case is written to fail against the pre-fix script (it reproduces the reported `xargs: unterminated quote` abort) and pass after — confirmed by running the selftest against a stashed copy of the original before landing the fix.

No unit-test-surface work: the repo's `commands.second-shift.unitTestScope` is `null`, so there is no mutation-gate surface. Selftests are the repo's test lane.

## Acceptance-criteria traceability

| AC ID | Criterion (short)                          | Step(s) | Test(s)                                       |
| ----- | ------------------------------------------ | ------- | --------------------------------------------- |
| AC-1  | Apostrophe in a Test cell passes plan-lint | 1, 2    | plan-lint-selftest (pl-m)                     |
| AC-2  | Selftest covers an apostrophe-bearing cell | 3       | plan-lint-selftest (pl-m)                     |
| AC-3  | ledger-lint carries the same fix + covered | 4       | ledger-lint-selftest (ll-k) — already present |

## Verification commands

- `bash plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh`
- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`
- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}`

## Risks / rollback notes

- **Behavior change on cells with internal double spaces / backslashes / quotes.** Previously normalized by `xargs`, now preserved. Assessed as inert: the no-test regex tolerates internal whitespace runs, and AC ids are matched by an anchored grep that a multi-space id would already have missed. Rollback is a three-line revert.
- **Low blast radius.** `plan-lint.sh` is advisory at Stage 3 and gating at Stage 4; a regression surfaces immediately as a Stage-4 abort on the next pipeline run, not silently.
- **Repo convention:** this touches `plugins/**`, so the implementation commit must carry a `Changelog:` trailer (enforced by `scripts/check-changelog-trailer.sh`). Versions and `CHANGELOG.md` stay untouched — they are derived at release time by `scripts/derive-release.sh`.

Unverified references: none — every path and function above was read or grepped in this worktree.

## Out-of-scope

- Extracting a shared trim helper across the `dev-pipeline` and `intake-toolkit` plugins (D-2).
- Any change to `ledger-lint.sh` (D-3) — already fixed.
- Auditing other scripts for unrelated `xargs` usage; the repo's verification lanes use `xargs -0` with NUL delimiters, which is not affected by quote semantics.
- Broader parsing hardening of the traceability table (escaped-pipe masking already exists at line 81).
