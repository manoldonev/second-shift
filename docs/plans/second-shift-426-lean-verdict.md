# lean review verdict — #426

verdict=approve
run_id: review-426-1
session_id: 680523dd-1014-4b9a-8a6e-5f46c56dbefe
rounds: 1
pr: #466
reviewed_head: e23bad6c2b2745b569ede9f7b0113e816abbfdcb
reviewed_patch_id: 564517d8f14d02e055319d528cd3ee9e2a11c11d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review Summary

Round 1, full branch range `6a6922c..HEAD` (6 files, 243 insertions / 12 deletions) — nothing
to inherit. Two shipped suites that hard-FAILed on a repo-only artifact now decide for
themselves whether they are in the monorepo, and `install-topology-selftest.sh` scores what
they decide. The mechanism is sound and, more to the point, it is sound in the **deployed**
topology and not only in the fixture: I resolved `ROOT` from the real installed marketplace
cache (`~/.claude/plugins/cache/second-shift/dev-pipeline/4.1.2/skills/run/tools`, five up)
and it lands on `~/.claude/plugins/cache/second-shift`, which carries neither
`.claude-plugin/marketplace.json` nor `plugins/`. The probe is intrinsic exactly as claimed.

Every acceptance criterion is satisfied on measured evidence, re-derived independently of the
PR body rather than read off it. No blockers, no warnings. Approve.

`Design: none` is justified — the repo's `.claude/second-shift.config.json` has `design: null`,
so no provider is configured and step 5b does not arm. Fidelity scored `not-applicable`.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Staged a version-keyed cache (`<tmp>/cache/second-shift/<plugin>/4.1.2/...`) outside any git repo — `git rev-parse --show-toplevel` there is `fatal: not a git repository` — with cwd a separate `git init`'d consumer dir. Both suites exit `77` and print one `SKIP: ` line naming their artifact. |
| AC-2 | **satisfied** | `bash tools/install-topology-selftest.sh` (the venue CLAUDE.md names; not on the PR lane): `57 ran, 55 passed, 2 known-red, 2 skipped, 0 stale row(s), 0 red`. Both suites appear as `SKIP:` lines carrying the suite's own hoisted reason verbatim, counted in `SKIPPED`, absent from `RAN` (59 staged = 57 + 2), scored as neither pass nor red, and neither leaves a stale row. |
| AC-3 | **satisfied** | Assertion counts repo→cache: config-lint 62→57, review-context 13→11, with **0 failures** in both cache runs. The five and two that vanish are exactly the artifact-dependent ones (4 schema-tier cases + the enum mirror; the docs template lockstep + the alias-target case). Negative half probed directly: injecting a failing non-artifact assertion into each cache copy (`cmp`-verified non-inert) gives `rc=1` and **zero** SKIP lines — a real failure outranks the skip. |
| AC-4 | **satisfied** | Both suites from this checkout: `config-lint selftest: all green` / `check-review-context-sections-selftest: ALL PASS`, with the tier cases and the enum mirror executing. Also green under stock `/bin/bash` 3.2, which is a live CI lane for both guards. |
| AC-5 | **satisfied** | The fabricated-tree case passes in both suites, in the checkout and from the cache, under bash 5 and bash 3.2 — inner run `rc=1`, no SKIP line. The up-count is guarded twice over, which the lockstep alone cannot do: a wrong `ROOT=` on either side makes the monorepo run exit 77, and `tools/run-selftests.sh` scores any non-zero rc as FAIL. |
| AC-6 | **satisfied** | The two rows are gone from `tools/install-topology-known-red.tsv`; the remaining four are the fixed-hop-count / environment-dependent class the spec puts out of scope. The `Seeded from the guard's first run` header is left as-is, as the spec directs. |

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| — | — | — | None. No blockers, no warnings. |

## Verification run in this review

- `shellcheck -e SC1091,SC2015,SC2181` on all three edited scripts — clean.
- `scripts/check-lockstep-pairs.sh` — 25 pairs, 0 failed, including the new `monorepo-probe`
  pair.
- Both suites in the checkout, from a staged cache, and under stock bash 3.2 — six runs.
- AC-3 negative probe (injected failing assertion, `cmp`-verified non-inert) on both suites
  from the cache.
- `tools/install-topology-selftest.sh` end to end.
- Reviewer panel (security, performance, maintainability, complexity, test-coverage,
  scope-completeness): six selected, six returned, **all approve, zero findings**. No dark
  reviewer. a11y + design-fidelity not routed — no changed path is a web component.

## Notes, not findings

- The lockstep pins the marker test but not the differing `ROOT=` up-count, which is
  unavoidable given the two sites sit at different depths. The gap is covered by the AC-5
  fabricated-tree case plus the repo sweep's non-zero-rc rule, so a mis-counted hop cannot
  land green. Worth knowing rather than worth fixing.
- `SECOND_SHIFT_SELFTEST_FABRICATED_TREE` is a recursion guard, so a harness that exported it
  would silently delete the AC-5 case from both suites. That is open region OR-1 taking its
  declared `reversible-default-and-flag` default; the variable is namespaced and set nowhere
  else in the tree.
- The guard's run also emitted two `listed known-red but PASSED` warnings, for
  `cost-block-selftest.sh` and `preflight-selftest.sh`. Both rows declare themselves
  ENVIRONMENT-DEPENDENT and both pass on a developer machine for the reason their cause
  states — the TSV header says not to act on that from a single green run. Unrelated to this
  diff, and warnings are never red.
- CI: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr` all pass.
  `pr-gates` is red for exactly one reason — `no committed verdict record` — which is the
  pre-handoff state by design and is what this record resolves.
