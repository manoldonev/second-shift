# lean review verdict — #426

verdict=approve
run_id: review-426-2
session_id: 680523dd-1014-4b9a-8a6e-5f46c56dbefe
rounds: 2
pr: #466
reviewed_head: fd27d39b486326837325faefd0e026c246496e45
reviewed_patch_id: 05642822361333d2425860d849e0b97382277125
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review Summary

Round 2, full range `aa39901..HEAD`. Round 1 approved this branch at `e23bad6`
(`reviewed_patch_id 564517d8…`); `origin/main` then moved by one commit (#462) and the branch
was rebased onto it, resolving an append-append conflict in `scripts/lockstep-manifest.tsv`.
That resolution moved the reviewed patch to `05642822…`, which voids the round-1 record — so
this round re-certifies rather than inherits. The gate offered no inheritance, correctly: the
patch the earlier record names no longer exists on the branch.

**What actually changed between the two rounds is one comment block's position.** I measured it
per file rather than reasoning about it: with the branch diff re-based on `aa39901`, the patch
text of `config-lint-selftest.sh`, `check-review-context-sections-selftest.sh`,
`install-topology-selftest.sh`, `install-topology-known-red.tsv` and the lean spec is
**byte-identical** to what round 1 scored. Only `scripts/lockstep-manifest.tsv` moves, and only
in its context lines — this branch's `monorepo-probe` block now follows #462's DROPPED entry
instead of the previous tail. The resolved file carries both blocks in full, with no marker
residue, and `scripts/check-lockstep-pairs.sh` reports 25 pairs / 0 failed, the same count as
before the rebase.

Every acceptance criterion re-verified on the rebased tree. No blockers, no warnings. Approve.

`Design: none` is justified — the repo's `.claude/second-shift.config.json` has `design: null`,
so no provider is configured and the fidelity arm does not arm. Fidelity `not-applicable`.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Re-run on the rebased tree. Staged a version-keyed cache outside any git repo (`git rev-parse --show-toplevel` there: `fatal: not a git repository`), cwd a separate `git init`'d consumer dir. Both suites exit `77` and print one `SKIP: ` line naming their artifact. |
| AC-2 | **satisfied** | Measured in round 1: `bash tools/install-topology-selftest.sh` gave `57 ran, 55 passed, 2 known-red, 2 skipped, 0 stale row(s), 0 red`, both suites hoisted as `SKIP:` lines carrying their own reason, in `SKIPPED`, absent from `RAN` (59 staged = 57 + 2), neither pass nor red, neither leaving a stale row. Carried forward deliberately: the guard and both suites are byte-identical here (per-file patch-id, above), and the guard never reads `lockstep-manifest.tsv`, so the rebase cannot have moved this result. It is a nightly guard, off the PR lane — re-running it would have bought a restatement, not evidence. |
| AC-3 | **satisfied** | Re-run on the rebased tree. Assertion counts repo→cache: config-lint 62→57, review-context 13→11, **0 failures** in both cache runs; the ones that vanish are exactly the artifact-dependent set. Negative half probed in round 1 — a failing non-artifact assertion injected into each cache copy (`cmp`-verified non-inert) gives `rc=1` and zero SKIP lines. |
| AC-4 | **satisfied** | Re-run on the rebased tree: `config-lint selftest: all green` / `check-review-context-sections-selftest: ALL PASS`, tier cases and enum mirror executing. Round 1 also confirmed both green under stock `/bin/bash` 3.2, a live nightly lane for these guards. |
| AC-5 | **satisfied** | Re-run on the rebased tree: the fabricated-tree case passes in both suites, in the checkout and from the cache — inner run `rc=1`, no SKIP line. |
| AC-6 | **satisfied** | Both rows remain absent from `tools/install-topology-known-red.tsv`; the remaining four are the fixed-hop-count / environment-dependent class the spec puts out of scope. |

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| — | — | — | None. No blockers, no warnings. |

## Verification run in this round

- Per-file patch-id comparison of the pre- and post-rebase branch diffs, establishing that only
  the manifest's patch text moved.
- `shellcheck -e SC1091,SC2015,SC2181` on all three edited scripts — clean.
- `scripts/check-lockstep-pairs.sh` — 25 pairs, 0 failed, `monorepo-probe` passing, count
  unchanged across the rebase.
- Both suites in the checkout and from a freshly staged install cache — four runs.
- Conflict-resolution integrity: no marker residue in the resolved manifest, both appended
  blocks present in full.

The reviewer panel was **not** re-dispatched. In round 1 it returned six approvals and zero
findings across security, performance, maintainability, complexity, test-coverage and
scope-completeness, and the code it read is byte-identical here. Re-running it could only
restate that. The checks that *could* have changed under a new base — the lockstep pair count,
the suites' own behavior, the resolved file's integrity — are the ones re-run above.

## Notes, not findings

- The lockstep pins the marker test but not the differing `ROOT=` up-count, unavoidable at two
  different depths. Covered twice over: a mis-counted hop makes the monorepo run exit 77, which
  reds the repo sweep (`run-selftests.sh` fails any non-zero rc), and the AC-5 case fails
  independently. Worth knowing, not worth fixing.
- `SECOND_SHIFT_SELFTEST_FABRICATED_TREE` is a recursion guard, so a harness exporting it would
  silently delete the AC-5 case from both suites. That is OR-1 taking its declared
  `reversible-default-and-flag` default; the name is namespaced and set nowhere else in the tree.
- Round 1 also verified the probe against the **real** installed marketplace cache, not only the
  staged fixture: from `~/.claude/plugins/cache/second-shift/dev-pipeline/<version>/skills/run/tools`
  the five-up `ROOT` lands on the cache root, which carries neither `.claude-plugin/marketplace.json`
  nor `plugins/`. That check is base-independent and stands unchanged.
