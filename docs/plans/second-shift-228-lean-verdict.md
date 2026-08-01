# #228 — lean review verdict

run_id: lean-228-1785606409
round: 1
verdict: approve

## Summary

Correct, well-scoped fix for #228. `exitplan-ledger-gate.sh` now probes `-newermB` support
once (a cheap self-referential `find` call), falls back to `-newer` (mtime) on GNU find, and
— the core of AC-2 — distinguishes a genuinely-erroring scan (find exit != 0, any cause,
including after the fallback) from a legitimate zero-candidates result: the former now calls
`block_scan_error()` (exit 2, distinct stderr message "tier-3 candidate scan failed..."), the
latter still calls `allow_warn()` ("no plan file newer..."). Reviewer traced the full control
flow in `exitplan-ledger-gate.sh:128-164` and verified via two independent `find` shims in the
selftest — `(t3h)` (rejects `-newermB` only, falls back and blocks) and `(t3i)`/`(t3j)`
(rejects everything, blocks with a distinguishable message) — that both actually exercise the
intended code paths, not just assert an exit code.

All 5 committed ACs met: AC-1 (probe+fallback+block, `t3d`/`t3h`), AC-2 (distinct scan-error
path, `t3i`/`t3j`), AC-3 (never-exit-1 contract reasserted via `(x1)` covering the new cases),
AC-4 (`CLAUDE.md`'s "Characterization is not endorsement" bullet and its now-empty
surrounding prose both removed cleanly; `(t3h)` updated to assert fixed behavior; the
`NEWERMB` per-case branching removed from `t3d`/`t3e`/`t3f`), AC-5 (`docs/testing.md`'s
dangling `(t3h)` citation dropped, principle kept).

Verification run by hand (Stage 6 INERT lane skips `.sh`/`.md` diffs): targeted selftest
25/25 passed; shellcheck clean repo-wide; `jq empty` clean repo-wide; `check-lockstep-pairs.sh`
13/13 passed; `check-frozen-files.sh` and `check-changelog-trailer.sh` both clean; the full
`*-selftest.sh` sweep passed 269/0 with zero failures across every suite.

## Finding addressed post-review (AC-6)

One non-blocking warning: `tools/mutation-sweep.sh:56`'s ENFORCING-vs-ADVISORY comment cited
the same now-fixed GNU-find divergence as its example of a platform-divergent guard — false
after this fix, since tier 3 now behaves identically on both platforms, and no replacement
example exists in the repo. Fixed in a follow-up commit (dropped the stale parenthetical,
kept the still-true general point); re-verified via `tools/mutation-sweep-selftest.sh` (all
cases pass) and milestone-2/3 re-run. Not re-reviewed: comment-only, mechanical, directly
responsive to the reviewer's own suggestion.
