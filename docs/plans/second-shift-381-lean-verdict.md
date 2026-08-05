# lean review verdict — #381

verdict=needs-work
run_id: review-381-1
session_id: 0580097a-d2b2-44d2-bfcf-59247588b726
rounds: 1
pr: #384
reviewed_head: 8a653ce042eb98f87270c636046572445cd4d97d
reviewed_patch_id: 5a65320522faf01cff1b33fbd51914dcfea89f99
model: unknown

## Verdict: needs-work

One blocker, in the one artifact on this branch that reaches consumers and that no lane can red
on. The code itself is clean: five specialist reviewers returned zero findings, the twelve ACs of
the committed spec are satisfied, and the seven new selftest cases assert what the pool and the
cache actually *did* rather than diffing two reports against each other.

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | commit `5f67a57` (message body) | The `Changelog:` trailer documents `tools/mutation-serial-suites.tsv`, a file this branch does not create and a mechanism D-5 retired. It ships verbatim into `CHANGELOG.md`. |
| 2 | Warning | issue #381 body | AC-11's widening is recorded only in branch-local artifacts; the issue still reads `tools/` and `docs/`. Scope gate raised it at confidence 92 — overridden, with the reasoning stated below. |
| 3 | Warning | `tools/mutation-sweep.sh:479` | `CACHE_ENV_TAG` carries the killer-bound knobs but not `MUTATION_SWEEP_EARLY_EXIT` / `MUTATION_SWEEP_FAIL_PATTERN`, which change what a verdict means by the identical argument. |

### 1 — Blocker: the release note names a file that does not exist

`5f67a57`'s trailer reads:

> A suite that cannot tolerate a concurrent sibling is pinned in
> `tools/mutation-serial-suites.tsv`. Migration: none.

There is no such file — `git ls-files | grep serial` is empty, and a `grep -rn mutation-serial-suites`
over `*.sh` / `*.md` / `*.tsv` returns nothing. D-5 retired the serial-pin design in favor of fixing
the three suites with `mktemp`; the spec says so in as many words ("so **no serial-pin mechanism
exists**", `docs/plans/second-shift-381-lean.md:173`). The trailer is the *first* commit's plan,
never corrected when the design changed at `d54aab6` / `47eca23` — both of which carry
`Changelog: none.`

Why this is not cosmetic:

- `scripts/derive-release.sh:117` extracts every `^Changelog:` block **grep-anywhere**, and
  `render_bullet` (`:234-243`) prints every non-`none` block verbatim into the release notes and
  `CHANGELOG.md`. So this sentence is the published description of the change.
- `scripts/check-changelog-trailer.sh` checks **presence**, not truth. No lane can catch it.
- It is also incomplete in the same breath: the three fixed suites — the consumer-visible half of
  AC-7 — are not mentioned at all, while the mechanism that replaced them is.
- Adding a corrective trailer in a new commit does **not** fix it. Blocks accumulate; both would
  render. The fix is rewriting `5f67a57`'s message.

That rewrite is message-only, so the patch bytes are unchanged and it does not void a verdict
record under review-lean's rebase rule — but this record is round 1 and the branch has no record
yet, so the ordinary path applies: fix, then a fresh review context writes round 2.

Suggested replacement body for the trailer:

```
Changelog: the mutation sweep memoizes mutant verdicts, scores mutants in a
  worker pool, and stops a killed mutant at the first FAIL: line. New knobs:
  MUTATION_SWEEP_JOBS, MUTATION_SWEEP_CACHE, MUTATION_SWEEP_CACHE_DIR,
  MUTATION_SWEEP_CACHE_MAX, MUTATION_SWEEP_EARLY_EXIT, MUTATION_SWEEP_FAIL_PATTERN.
  The cache is advisory-lane only — never read or written under GITHUB_ACTIONS.
  Three selftests that wrote to a fixed /tmp path now write under their own mktemp
  tree, since two mutants of one guard run the same suite concurrently.
  Migration: none.
```

### 2 — Warning: AC-11's widening lives only in branch-local artifacts

`scope-completeness-reviewer` is right on the fact and I am overriding its `request-changes`
rather than letting the override be implied. Issue #381's AC-11 reads "the diff stays inside
`tools/` and `docs/`"; the diff also touches three files under
`plugins/dev-pipeline/skills/run/tools/`.

Overridden because:

1. In this lane the **committed lean spec is the definition of done**, and its AC-11
   (`:71-73`) admits exactly those three files.
2. The widening is not a self-serving amendment. It is **D-5** in
   `.claude/pipeline-state/381-ledger.md`, provenance `user-answered` — a human decision taken at
   intake. Its file mtime (00:41) predates the spec commit `17222b2` (00:50) and the code change
   `d54aab6` (01:37).
3. AC-7 itself offers "**either fixed or pinned serial**". The collision was a real conflict
   between two of the issue's own ACs, and D-5 resolved it toward the option AC-7 names first —
   which is also the stronger one: a fixed suite cannot race, whereas a serial pin only hides it.

What survives as a warning: the spec's AC-11 *text* was rewritten at `47eca23` (02:07), after the
three files changed at `d54aab6` (01:37), and `.claude/pipeline-state/` is gitignored. So the only
committed record of a human decision is a branch artifact written after the fact, and issue #381
still reads the old way. Record the D-5 widening on the issue — not because this diff needs
permission, but because the next reader of #381 will hit the same contradiction the scope gate did.

### 3 — Warning: the early-exit knobs are outside the cache key

`CACHE_ENV_TAG` is `RUNNER_OS | SKIP_STRESS | KILLER_TIMEOUT_S | FACTOR | MIN_S | MAX_PROCS`. The
stated rationale for including the killer bounds is that "those decide whether a spinning mutant
scores as a timeout KILL, so a run with a different bound is not answering the same question"
(`:477-479`). `MUTATION_SWEEP_FAIL_PATTERN` and `MUTATION_SWEEP_EARLY_EXIT` meet that description
exactly, and `docs/testing.md` now advertises both as operator knobs — but neither is in the key.

Concretely: a local run with a custom `MUTATION_SWEEP_FAIL_PATTERN` computes verdicts under a
different kill criterion and a later default-pattern run serves them. D-3's standing assertion does
not close this — the precheck only asserts that the *unmutated* suite is silent, so a mutated guard
whose suite prints the custom pattern while exiting 0 caches a false KILLED.

Narrow, and confined to the advisory lane by D-2, so AC-8 is still satisfied by the letter of the
key the spec defines. Adding two fields to one string is the whole fix.

Related but deliberately *not* asked for: `MUTATION_SWEEP_JOBS` is also absent from the key, and
pool contention can turn a would-be survivor into a timeout KILL that then persists. `docs/testing.md`
already names that direction ("the direction that hides a weak test rather than inventing a
finding") but not its persistence in the cache. Keying on JOBS would cost most of the hit rate;
a sentence in the invalidation paragraph would not.

## Per-AC scoring — the committed spec is the definition of done

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — cached on the stated key; unchanged tree runs **zero** paired suites, identical survivor set | **satisfied** | `cache_key()` `:490-492`. Case (ad) asserts `computed==0` on the warm run and diffs the report against the cold one. The probe-before-precheck ordering (Phase 2 before Phase 3) is what makes "zero" literal — a precheck *is* an execution, so a fully-cached guard skips it rather than caching it. |
| AC-2 — editing a paired selftest invalidates every verdict for its guard | **satisfied** | Case (ae) turns a cached SURVIVED into KILLED by adding one case, **and asserts `guard.sh` is byte-identical across both runs** — so it isolates the suite key instead of observing an incidental miss. |
| AC-3 — concurrent, own sandbox, configurable pool, default `min(cores-2, …)` | **satisfied** | `JOBS = min(max(cores-2,1), 8)` `:166-174`, `MUTATION_SWEEP_JOBS` override. One sandbox per worker, restored between items `:1128-1143`. |
| AC-4 — parallel and serial produce identical survivor sets and counts | **satisfied** | Case (ac) diffs the `JOBS=1` and `JOBS=4` report TSVs and exit statuses — **after** asserting the parallel run really overlapped (max concurrent killers > 1 across > 1 sandboxes). Without that precondition two serial runs would also agree. Corpus-level A–E byte-identity recorded in the spec. |
| AC-5 — first-`FAIL:` kill, scores identically to the full run, first-case and last-case fixtures | **satisfied** | (ag/first) and (ag/last) run each shape with `MUTATION_SWEEP_EARLY_EXIT` on and off and compare verdicts; killer **completions** (1 vs 2) are counted, so "did not run to completion" is observed. (ag/noisy) drives D-3. |
| AC-6 — measured wall time for cold, partial-hit, full-hit | **satisfied** | Spec's Measurements table, rows A–F, each read off the run's own closing `timing:` line. The invalid first F attempt is recorded rather than dropped. |
| AC-7 — concurrency-hostile suites identified and fixed or pinned, reason recorded | **satisfied** | Three found and fixed with `mktemp`. Case (k)'s corpus lint is live — I ran its regex against `origin/main` and it catches all 7 pre-fix redirect sites (2/2/3), and returns clean across every `*-selftest.sh` at HEAD. |
| AC-8 — bounded, outside the repo, never committed, survives no environment change, corrupt entry → real run | **satisfied** | Case (af) drives all five: malformed entry, well-formed-first-line-plus-junk, an env change, a harness edit (D-7 self-hash), the per-repo subdirectory, and `git status --porcelain` empty after the run. |
| AC-9 — sandbox disk bounded and reclaimed on every exit path incl. reaps | **satisfied** | `pool × ~7MB`; `cleanup` on EXIT/INT/TERM; killers run under a harness-owned `TMPDIR` removed unconditionally, which is what covers the SIGKILL paths. Case (ah) runs the spin/reap shape under its own `TMPDIR` and asserts zero leftovers and the worktree count back to 1. |
| AC-10 — `docs/testing.md` states the key, invalidation, authoritative vs advisory | **satisfied** | New section covers all three, including the "it is not sound" admission and `MUTATION_SWEEP_CACHE=0`. |
| AC-11 — diff inside `tools/` and `docs/` plus the three D-5 selftests | **satisfied** | Diff is exactly those seven files. See finding 2 for the override. |
| AC-12 — the PR carries a `Changelog:` trailer | **satisfied** (by its letter) | `5f67a57` carries one. AC-12 speaks to presence; its *content* is finding 1. |

## Verification run for this review

From the PR head, `env -u CLAUDE_CODE_SESSION_ID`, **without** `SKIP_STRESS`:

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — exit 0
- `jq empty` over every `*.json` — exit 0
- every `*-selftest.sh`, `-P 4` — exit 0
- `--mode pr --base origin/main` sweeps zero guards (no in-universe guard is touched;
  `tools/mutation-sweep.sh` is the registered recursion-guard exclusion), which is why
  `tools/mutation-baseline.tsv` correctly needs no re-baseline.

## What the diff does well

- **The pool cases refuse to be vacuous.** (ac) asserts the run overlapped before asserting the
  reports match; (ad) reads the counters out of the run's own `timing:` line; (ag) counts killer
  completions. Each new case can fail for a reason a report-diff could not.
- **The phase ordering is the proof, not a comment about one.** Enumerate → probe → precheck →
  pool → serial aggregate makes the survivor set independent of pool size by construction, and
  putting the probe *before* the precheck is what lets AC-1's "zero" be literal rather than
  approximately true.
- **D-7's self-hash removes a discipline that would have failed silently.** A hand-bumped schema
  constant outlives the meaning it recorded; hashing the harness makes invalidation conservative
  and automatic, and case (af) proves a trailing comment re-keys every entry.
- **The invalid measurement is in the record.** F's first attempt (wrong worktree basename, 36
  computed / 0 served) is documented rather than quietly replaced — the failure mode being
  "a number that would have read as *the cache does not work*".

## Suppressed (below threshold)

- `cache_prune`'s `rm -rf "${CACHE_DIR:?}"/*` honors an operator-supplied `MUTATION_SWEEP_CACHE_DIR`
  (conf 40) — the path always gains a `$(basename "$REPO_ROOT")` component, so it is
  self-inflicted-only.
- Verdict-record fields are echoed into report text (conf 45) — shape-validated to a two-verdict
  allowlist, never `eval`'d, and off under `GITHUB_ACTIONS`.
- `pool_worker` scans the whole manifest per worker (conf 40) and the unrunnable-guard drop is a
  linear scan per mutant (conf 35) — both match the file's declared "sizes are in the tens" trade
  and its bash-3.2 constraint.

## Pre-existing, not this PR

`git worktree list` on this machine still shows one leaked
`mutation-sweep-sandbox.*` registration at `33e84bd` — a commit that predates this branch, so the
leak is the old harness's. Case (ah) is the guard that would catch a new one. Worth a
`git worktree prune` on the operator's box, not a change here.

## Reviewer verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail (overridden — see finding 2) | 1 | 92 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
