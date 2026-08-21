# lean review verdict — #610

verdict=needs-work
run_id: review-610-3
session_id: 9b47bef0-4132-4895-8798-c2ffdfe9cc16
rounds: 3
pr: #625
reviewed_head: 80ca11d6c916d2e9fc34bfb99b29fd74202f65a9
reviewed_patch_id: ae9a73a241a4a8081985dccd7cae87551cc4239c
inherited_patch_id: 3142263a15bd4f56f1cc3a5341569fd3dcf2349c
inherited_from_verdict: 650c4d99f0cc022125ed42808e702d5675cb32fe
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3, inheriting round 2's coverage of patch `3142263a15bd`. Delta read: `650c4d99..80ca11d6`
— the `origin/main` merge plus the two fix commits. I read wider than the range: the whole
branch contribution (`42dfb2a5..80ca11d6`, 18 files), because the merge puts #627's content in
the delta and reading only the range would confuse main's work for this branch's.

Verdict: **needs-work** — one blocker, and it is the CI lane the previous two rounds never got
an answer from.

Round 2's blocker and all three of its warnings are genuinely closed, each verified rather than
read off a commit message:

- **B-4 (base drift) — fixed.** `origin/main` (42dfb2a5) is an ancestor of the head, the PR is
  `MERGEABLE`, and GitHub created five check-runs where the conflicted head had zero. Both
  conflicts kept BOTH sides, as the round-2 record asked: `run-selftests-selftest.sh` carries
  main's hostile `LEAN_JOB_CEILING=2` *and* this branch's `-u LEAN_SELFTEST_CACHE_DIR` in one
  scrub line (the AC-4 env case passes on the merged head), and `build-lean/SKILL.md` step 9 is
  main's single `close-out` call under this branch's prune. I checked the merge lost nothing
  else: of the 14 files #627 touched, only the two conflicted ones and `run-lean/SKILL.md`
  differ from main at the head, and each difference is this prune's own edit — #627's rewrite of
  the run-lean authorship rule survives verbatim.
- **W-1 (the `EXIT`-trap fix was unguarded) — closed, and non-redundantly.** Reverting the
  `(census)` subshell now fails exactly one case (51/1). With that one assertion deleted the
  revert is invisible again (51 passed, 0 failed), so the new assertion is the sole killer, not
  a second copy of an existing one.
- **W-2 (slow-list row) — closed.** `tools/prose-blockers-selftest.sh 15 2026-08-21` parses, and
  `mutation-sweep-selftest.sh`'s own TSV lint (suite exists / integer seconds / ISO date) covers
  the row.
- **W-3 (the `promoted` gloss) — closed.** The header now says "or a filed issue owns doing it",
  which is true of all four `filed` rows.

## Blocker

### B-5 — the macOS bash-3.2 lane is RED on the reviewed head, and it is a real leak

`selftests (macos, bash 3.2)` failed on 80ca11d6 — on the very case round 3 added:

```
FAIL  tools/prose-blockers-selftest.sh (rc=1)
  FAIL check removes every temp file it created
     want '0', got '2'
prose-blockers-selftest.sh: 51 passed, 1 failed
[run-selftests] summary: 72 scored, 71 run, 1 served from cache, 1 failed (0 infrastructure)
```

**The guard is right and the tool is wrong.** Reproduced locally and diagnosed to the line. The
shim records five `mktemp` calls per `check`; calls **#4 and #5** are what survive, and those are
the two `census` temps allocated inside

```
n_bold=$(census --tier bold | awk 'END {print NR}')
n_all=$(census  --tier all  | awk 'END {print NR}')
```

`census` cleans up through `trap "rm -f '$tmp'" EXIT`, and **bash 3.2 does not run an `EXIT`
trap set inside a pipeline element of a command substitution.** Minimal model, same tree:
`(census)` leaks nothing under either shell; `$(census | wc -l)` leaks the inner temp under
3.2.57 and nothing under 5.3.9. So `prose-blockers.sh check` leaks two temp files per run on the
repo's stock macOS shell — the tier-count block, which is round 2's own fix for round-1's B-2
(768ceea4), and which the 3.2 lane never graded because round 2's head was unmergeable and
carried no CI at all.

The subshell at line 311 is not the problem and should stay. A remedy I verified in an isolated
worktree: an explicit `rm -f "$tmp"` at the end of `census`, after `done | LC_ALL=C sort`. With
it the suite is **52 passed, 0 failed under both** `/bin/bash` 3.2.57 and bash 5.3.9; the
`(census)` revert still fails that one case. Take that or something better — the requirement is
that `census` not depend on an `EXIT` trap firing in a context 3.2 does not fire it in.

**A local run will not reproduce this.** The suite invokes the tool as `bash "$TOOL"`, which on
this host resolves to brew bash 5.x even when the suite itself is started with `/bin/bash` — so
the ordinary `bash tools/prose-blockers-selftest.sh` is 52/0 with the bug present. Force the
tool's own shell to 3.2 to see it, e.g. a `bash` shim on `PATH` that `exec`s `/bin/bash`; under
that harness the suite reproduces CI exactly (51 passed, 1 failed).

## Warnings

- **`mutation-sweep-pr` is green on this head and computed ZERO verdicts.** The slow-list row
  this round added defers `tools/prose-blockers.sh` wholesale, so the CI job graded nothing:
  `PR mode graded NOTHING: all 1 in-scope guard(s) deferred to nightly, 0 swept` and
  `0 verdict(s) computed`. That is the designed trade and the row belongs here — but the green
  asserts nothing about this tree, and it is the only mutation signal the merge boundary sees.
  I closed the substance instead of assuming it: PR-scoped sweep on the FINAL head with the
  deferral overridden (`MUTATION_SWEEP_SLOW_THRESHOLD_S=999`) and an isolated cache dir —
  `applied=8 killed=8 survived=0`, **9 verdicts computed live, 0 served from cache**, 64s. The
  trap-isolation site is still outside the mutant budget (`sites_beyond_budget:
  cmp-z:4+logic:23+default:1`), which is exactly why the hand-written case in B-5 is the thing
  that found the leak.
- **The new case's anti-vacuity half is weaker than its comment claims.** `CREATED >= 2` is
  described as pinning `check`'s own two temps, but `census` contributes three more through the
  same shim — measured `CREATED=5` on the real tree — so the bar is cleared by `census` alone. A
  mutant that stops `check` allocating through `mktemp` at all still scores `CREATED=3` and
  passes both halves (verified). It does still prove the shim was reached, which is its stated
  job, so this is a note on the comment rather than a defect in the assertion.
- **The PR body's prose-budget figure for `build-lean` is stale.** It says main was failing at
  1847 words; main at 42dfb2a5 measures 1868 (the #627 step-9 rewrite landed after that
  sentence was written). The head is 1645 against a regenerated 1624 row and reads `ok` inside
  tolerance. Body-only, so it costs no round — worth one edit when the blocker is fixed.

## Panel

Seven reviewers selected, six returned, all `approve` with **zero** findings between them
(security, performance, maintainability, complexity, unit-test-mutation, scope-completeness).
Two sub-80 suppressions from security, both correctly suppressed.

`test-coverage-reviewer` went **dark** for the second consecutive round — died after its
automatic retry, no text on either attempt, turn-budget cap. Coverage gap: the test-adequacy
dimension was again not reviewed by that reviewer. Not a void round (six usable results), and it
did not change the verdict — I read the suite myself and probed four assertions, which is what
produced B-5. Two rounds of the same reviewer dying the same way is an infrastructure datapoint,
not a finding against this PR.

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matches the
resolved web-component surface (`apps/web/**/*.{tsx,jsx}` — the shipped default; this repo
declares no `stageParams.webComponentGlobs`). `db-reviewer` and `pipeline-reviewer` were not
triggered. Not coverage gaps.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited from rounds 1-2 and re-confirmed live on the merged tree: 12 rows, two consecutive censuses byte-identical, tier line prints `stop=12 (default), bold=58, all=226 - the default excludes 214`. The behavioral selftest exists and is 52 cases; its one failing case is the guard correctly reporting B-5's defect, not a gap in this AC. |
| AC-2 | satisfied | 34 rows, one disposition each — 29 `gate-backed`, 4 `promoted`, 1 `deleted`. `check` rc=0 with zero undispositioned over the MERGED tree, so the merge minted no construct the record lacks and un-pruned nothing it recorded deleted. The all-dark rule keeps its operative site (`pb-94ee597a`, step 5c, `pointer-kept`) and only its duplicate went (`pb-bdd633e7`). |
| AC-3 | satisfied | Every enforcer resolves — mechanically for the paths, and by reading for the seven whose `::` half is a label rather than a literal token (`milestone-preconditions`, `exit-codes`, `topology.repos.baseBranch`, `exit-2`, `refuse-overwrite`, `reject-empty-body`, `verdict-record`). I opened each named site; each really enforces the rule its row claims. `check-lockstep-pairs.sh`: 28 anchors, 0 failed. |
| AC-4 | satisfied | All four `promoted` rows are `filed`, and #622, #623 and #624 are all still OPEN. No guard shipped, which D-1 authorizes for anything larger than one-guard-small. |
| AC-5 | satisfied | Six columns on all 34 rows; dispositions and actions both inside the declared enums. Unchanged in the delta. |
| AC-6 | satisfied | `check` on the merged tree: `12 construct(s) over 26 file(s); record: 34 row(s)`, `✓ zero undispositioned constructs`, rc=0 — under bash 3.2 as well as bash 5. No standing CI guard wired, per D-9. |
| AC-7 | satisfied | `prose-budget.sh --check`: **6 fails on main, 3 on this head**. The three that remain (`QUERIES.md`, `figma-faithful-spec-reviewer.md`, `capability-parity-check-selftest.sh`) are the pre-existing ones and are still red, not laundered. `build-lean` 1868 -> 1645, `review-lean` 1805 -> 1657, `onboard` 5154 -> 5106 are real reductions, and the regenerated rows record post-prune truth. The shell baseline gains exactly the two new files. |

Design fidelity: `not-applicable`. The spec disarms it (`Design: none`) and the repo's config
declares no `design.provider`, so the disarm is justified.

## What round 4 needs

Fix B-5 in `tools/prose-blockers.sh` — `census` must not rely on an `EXIT` trap that bash 3.2
does not fire inside a command substitution — push, and get the macOS lane green. Nothing else
is outstanding: the three warnings above are notes, not gates, and the two body edits cost no
round. Re-run the suite with the tool forced under `/bin/bash`, not just the ordinary harness,
or the fix will look landed when it is not.

## Strengths

- **The round-3 guard earned its keep immediately.** It was added to close a warning about an
  unguarded fix, and instead of merely pinning the subshell it surfaced a live, shipped,
  shell-specific leak two rounds of green local runs had walked straight past. That is what a
  guard written against a mechanism rather than an outcome buys.
- **The merge is a real merge.** Both conflicts were resolved by keeping both sides, in a test
  file where taking either side whole would have read as green while dropping the other's
  coverage — and the commit message says which half came from where, so the next reader does
  not have to reconstruct it.
- **The slow-list row is the honest move even though it costs the PR its own mutation signal.**
  The row is measured from the sweep's precheck rather than a stopwatch, and it takes the guard
  into the nightly by the documented trade rather than leaving a 15s cost on every push.
- **The census survived a base merge without re-keying anything.** Content-derived ids over a
  file the merge edited, and `check` is still rc=0 with the same 12/34 — the id scheme's central
  claim, tested by an event nobody staged for it.
