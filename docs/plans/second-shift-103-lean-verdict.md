# Lean verdict — #103

verdict=approve
run_id: run103-6499920
rounds: 1

## Summary

Scoped, correct fix for #103: `config-lint.sh` now rejects `topology.type==monorepo`
configs with more than one `repos` entry or no entry with `path=="."`, pointing at
`commands.<id>.lanes`/`extraLanes`. Verified by hand-running `config-lint.sh` against
both the new invalid fixture (fails with the expected message, exit 1) and the existing
`valid-monorepo-github.json` (still passes, exit 0) — AC-1 and AC-2 hold. AC-3 (fixture +
selftest assertion) is present and the full `config-lint-selftest.sh` suite is green.
AC-4 (onboard `SKILL.md` guidance on lanes/extraLanes for a second monorepo surface) is
present and accurate. Commit trailers carry a proper `Changelog:` entry, the verb is the
honest `fix:` (patch bump, matching a lint-coverage bugfix, not a new capability), no
frozen release files are touched by the branch's own commits, shellcheck is clean on the
touched scripts, and the mutation-baseline row for `config-lint.sh` (`fail-open::1`,
anchored to the unrelated `exit 1` at line 16) is unaffected by the insertion since the
new `err()` block adds no `exit 1` literal. No lockstep obligation applies (config-lint-
vs-schema is explicitly excluded from `scripts/lockstep-manifest.tsv`).

## Findings

- note (confidence 90, non-blocking): the branch was cut from a commit (`6499920`) that is
  4 commits behind `origin/main` at review time, so a raw two-dot diff shows unrelated
  large deletions from commits this branch does not touch. Confirmed via
  `git diff --stat 6499920..<head>` that the branch's own commits touch only the 5 files
  matching the plan's stated scope. `git rebase origin/main` was attempted before opening
  the PR but was denied by the operator's tool-permission policy; a normal GitHub PR (merge-
  base diff) shows the clean 5-file diff regardless, matching the precedent noted (and left
  unaddressed) in the #207 verdict record. Not a defect in this change.
