# Lean review verdict — second-shift#277

- run_id: 20260801T101810Z-lean-277
- issue: 277
- round: 1
- verdict=approve

## Summary

The #277 fix is correct, complete against all four ACs, and thoroughly tested.
`cmd_comment_add` in `statectl.sh` now requires `--url` to match
`/issues/<ticketKey>#issuecomment-<digits>` for the state file's own `ticketKey`, routed
through `guard_fire`/`guards_settle` so `--force` still folds a `waivers[]` entry
(verified `statectl.sh:2907-2919`; `guards_settle` moved outside the `code-review`-only
if-block so the new guard is honored for every marker, not just `code-review`). New
selftest case `(cr6)` in `statectl-selftest.sh` covers every AC-1 negative shape (PR URL,
PR review URL, PR conversation comment, wrong-issue comment, fragment-less issue URL),
AC-2's well-formed/GHES-host acceptance and unchanged `code-review` ordering (`cr5` still
passes), and AC-3's `--force` waiver recording. Every existing `comment-add` call site
across `scenario-lib.sh`, `scenario-liveness-selftest.sh`,
`stage8-perrepo-review-selftest.sh`, and `e2e-replay-selftest.sh`'s minted `gh` shim was
updated to post real issue-comment-shaped permalinks (AC-4). Ran the full relevant suite
locally: `statectl-selftest.sh` 260/260, `scenario-liveness-selftest.sh` 44/44,
`e2e-replay-selftest.sh` 31/31, `stage8-perrepo-review-selftest.sh` 4/4, all green;
shellcheck clean on every changed `.sh` file; `check-frozen-files.sh` and
`check-changelog-trailer.sh` both pass; commit carries an honest `fix:` verb and a
`Changelog:` trailer with `Migration: none`. `docs/testing.md` and `state-schema.md` were
updated in step with the code (Guard-id vocabulary entry added).

## Findings

- **warning** (non-blocking) — `plugins/dev-pipeline/skills/run/workflows/intake-review.mjs`:
  the review's two-dot diff (`origin/main..e89691f9`) was scoped against an `origin/main`
  that had advanced one commit (#314) after this branch's fork point, making the diff
  view look like a revert of #314. Verified via `git merge-base` that the branch's actual
  diff (`cb67129..e89691f9`) touches only the 9 files genuinely part of this fix, with no
  trace of #314 — a normal merge/rebase will not drop it. Rebasing the local worktree onto
  the current `origin/main` tip was attempted and denied by the session's permission
  gate; deferred to the PR merge (GitHub diffs against the true merge-base, not a stale
  two-dot comparison, so this does not affect the PR content).
- **note** (non-blocking) — `statectl.sh:2918`: the receipt-shape regex matches the
  `/issues/<ticketKey>#issuecomment-<digits>` path tail without an org/repo anchor, so an
  issue-comment permalink for the same issue *number* in an unrelated repo would still
  pass. Explicitly out of scope per the plan (host-agnostic matching, no tracker-existence
  check) and the state schema carries no owner/repo field to check against.
