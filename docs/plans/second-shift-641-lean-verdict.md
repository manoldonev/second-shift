# lean review verdict — #641

verdict=needs-work
run_id: review-641-pr648-1
session_id: e3a87c36-36f7-4594-bdfd-08f2f9424508
rounds: 1
pr: #648
reviewed_head: 39fda97f1ba6ed39e9f5ac7587980ccd649a4451
reviewed_patch_id: d7bad4e2e770b0ae63e2b42ff0b0194bcef6f721
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #648 (issue #641)

Range read: `b8cc982..HEAD` (full branch diff — round 1, nothing to inherit).
Reviewed head: `39fda97f1ba6ed39e9f5ac7587980ccd649a4451`, re-checked unmoved immediately before this record.

**Verdict: needs-work.** Five blockers. The direction is right and the deletion half is real
work — 180 measurement rows retired, three drifting timing tables reconciled into one, an
allowlist that had outlived its purpose gone. What blocks is that the PR's own enforcing lane is
red, two of the arms this design rests on are unguarded, one ratified scope clause was inverted
without a departure record, and the slice's own anti-regression AC lands short on both halves.

## Blockers

### B1 — `mutation-sweep-pr` is RED on this PR: a baseline-absent survivor the diff created

`plugins/dev-pipeline/tools/pipeline-doctor.sh::detector::3726bf79a636`
([run 32592962902](https://github.com/manoldonev/second-shift/actions/runs/32592962902/job/97079518962)).
CI re-verified it serially, outside the pool, and agrees: *"really does survive its kill set."*

Cause is in the diff. The prose-budget short-circuit probe changed from
`grep -q 'coverage: md n/a, sh n/a' <<< "$pb"` to `grep -q 'coverage: md n/a' <<< "$pb"`. Survivor ids
are content-keyed, so editing the matched line re-keys the site `fd42dbc00b25` → `3726bf79a636`.
The diff correctly deletes the old key's baseline row (`mutation-baseline.tsv`) but adds none for
the new key, and `pipeline-doctor-selftest.sh` does not kill it.

Fix: kill the mutant in `pipeline-doctor-selftest.sh` (preferred — the arm is live behavior), or
add the baseline row with a reason that says why it is unkillable.

### B2 — AC-2 unsatisfied: 6 of `classify_ref()`'s 7 arms are unguarded (probe-confirmed)

`scripts/check-guard-budget.sh:54-65`, `scripts/check-guard-budget-selftest.sh:118-141`.

`arm_case()` builds a fixture whose base branch holds **no** guard file, so `BASE_MASS` is 0 and
only `classify_worktree()` is exercised. Cases 1-4 put one `check-thing.sh` in the base, so
`classify_ref()`'s `check-*.sh` arm is the single ref-side arm any case touches.

Probed on an isolated copy, mutating one arm at a time:

| mutant | suite |
| --- | --- |
| drop `*-selftest.sh` from `classify_ref` (line 61) | **12 passed, 0 failed** |
| drop `*-lint.sh` from `classify_ref` (line 61) | **12 passed, 0 failed** |
| delete `classify_ref`'s `*/skills/*/lean-gate.sh` arm (line 58) | **12 passed, 0 failed** |

The script's own header is the load-bearing justification and it is false:

> `classify_worktree()`/`classify_ref()` below are two entry points over the SAME case statement,
> so a fixture for one exercises the rule the other enforces too.

They are not one case statement — one is a `find` expression, the other a `case`. The comment at
lines 39-41 then warns "add an arm to both, or [that] property stops being true", which is the
exact maintenance mistake nothing here would catch.

Failure scenario: a future arm (or an edit to an existing one) lands in `classify_worktree` only.
`BASE_MASS` under-counts every file matching it, `DELTA` is inflated, and every subsequent PR reds
on guard mass it never added — with the suite green. AC-2's text ("each `classify()` arm is
independently covered, such that neutering any one arm fails at least one case") is not met.

This is the same class as PR #645 r2's finding, moved to the other function. The worktree side was
fixed there; the ref side inherited the gap.

Fix: give `arm_case()` a second leg that seeds the file in the **base** commit and deletes it on
the branch, asserting the printed base mass. One fixture change covers all seven ref arms.

### B3 — the `>= threshold` filter is unguarded in BOTH consumers (probe-confirmed)

`tools/run-selftests.sh:221` and `tools/check-sweep-bound.sh:109` — both new in this PR, both the
arm that makes the shared-table design work.

| mutant | suite |
| --- | --- |
| delete `run-selftests.sh:221` (`[[ "$sl_secs" -ge "$SLOW_THRESHOLD_S" ]] \|\| continue`) | `run-selftests-selftest: PASS` |
| delete `check-sweep-bound.sh:109` (same predicate) | unchanged from baseline |
| delete `check-sweep-bound.sh:108` (the non-numeric-seconds `die`) | unchanged from baseline |

Every fixture row in both suites is written at 99s or 147s — always above the 9s threshold — so no
case can distinguish "filtered correctly" from "no filter at all".

Failure scenario: without the filter, **every** row in the shared table is deferred regardless of
seconds. `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh` (5s, a row that exists
only for `mutation-sweep.sh`'s lower bar) silently drops out of the default bounded sweep — the form
`lean-gate.sh` milestone 3 runs — and out of `check-sweep-bound.sh`'s un-deferred sum, weakening the
#629 aggregate bound. The set grows on its own: `mutation-sweep.sh --seed` writes every suite it
measures at >= 5s into this same file. Nothing else catches it — exclusions are computed before
dispatch, so `N discovered, M excluded, N-M to run` stays self-consistent.

AC-4 names this arm directly ("both consumers read it with their own threshold"); it is the one
part of AC-4 with no oracle.

Fix: one case per consumer with a sub-threshold row, asserting the suite still runs (and, for
`check-sweep-bound.sh`, that its seconds land in the un-deferred sum).

### B4 — spec scope item 2 inverted without a departure record

Committed spec, scope item 2, verbatim:

> ...as `# threshold-seconds` comment directives in the SAME file, **one per consumer**, so
> `check-sweep-bound.sh`'s existing directive-read pattern needs only a new default path **and its
> own directive key**.

Shipped: one shared `# threshold-seconds	9` in `tools/selftest-suite-timings.tsv:20`, sed-read by
both `run-selftests.sh:212` and `check-sweep-bound.sh:98`. `check-sweep-bound.sh` got the new
default path but no directive key of its own.

The build made this call deliberately — `run-selftests.sh:205-208` says "THE THRESHOLD HAS ONE HOME"
and `docs/testing.md` documents the sharing — and the reasoning is defensible (one key cannot
drift). What is missing is the record: the Build-time amendments section lists three amendments and
this is not among them, so a ratified clause was re-decided silently. The coupling is real, not
cosmetic: with one key you cannot raise `run-selftests.sh`'s deferral bar without simultaneously
changing what counts as deferred in `check-sweep-bound.sh`'s #629 sum, which is what the
per-consumer key existed to prevent.

Fix (cheap): add a Build-time amendments row stating the inversion and why. Or split the key.

### B5 — AC-7 unsatisfied on both halves, and reinterpreted after the fact

**(a) Row count.** Committed `.tsv` data rows (non-comment, non-blank) across every tracked file:
`origin/main` 615 → `HEAD` 446 = **−169**, against AC-7's "at least 170". Per-file: prose-budget-shell
−89, prose-budget −65, selftest-slow-suites −14, mutation-slow-suites −10, selftest-sweep-baseline
−2, install-topology-known-red −0, mutation-baseline −3, mutation-catalog −1,
selftest-suite-timings +15. (180 rows are retired, as the PR body says; the AC measures the net.)

**(b) Net guard mass.** `bash scripts/check-guard-budget.sh origin/main` from the reviewed head:
`base 50308, HEAD 50308 (delta 0)`. AC-7 says "net guard/test shell mass is **lower** than
`origin/main` at merge". Zero is not lower.

The Build-time amendments section records the delta-0 outcome and treats it as satisfying "AC-7's
own text" — that is an after-the-fact reinterpretation of *lower* as *not higher*, which the review
contract calls out by name.

I do not think this is a technicality. The ticket's premise is that guard/test shell grew 8x while
product shell grew 1.9x, and #641 is the delete-first slice. A slice about guard mass that lands at
exactly net zero — because the new check plus its selftest consumed everything the deletions freed —
has not moved the number it exists to move.

Fix: trim enough comment mass in the new/touched guard files to clear both clauses (169 → 170 is one
row; delta 0 → negative is a handful of lines), or get AC-7 amended explicitly by the operator rather
than reinterpreted in the build's own notes.

## Warnings

- **`# baseline-seconds	106` is a measurement in a file whose own new rule forbids them.**
  `tools/selftest-suite-timings.tsv:21` carries a measured sum, while the manifesto paragraph this
  PR adds says "a register's rows must be judgments, not measurements... a row recording something
  the tree can compute — a file's size, a suite's runtime, a count". The `selftest-sweep-baseline.tsv`
  essay justifying it was deleted with the file and the reasoning survives in `docs/testing.md`, so
  this is a consistency note rather than a gate — but the slice writes a rule its own new file bends.

- **The CI `--seed` path still produces a full-overwrite artifact.** The merge-not-overwrite guard
  (`tools/mutation-sweep.sh:2118-2140`) fires only when `SOUT == SLOW_SUITES`. `workflow_dispatch`
  with `seed=true` — per `docs/testing.md:1243` the *only* re-seed entry point — passes
  `--slow-out sweep-out/mutation-slow-suites.tsv`, so the published artifact is a wholesale rewrite
  carrying neither the three `#` directives nor any suite the mutation lane does not measure
  (including `install-topology-selftest.sh`'s 584s row — the exact hazard the spec names). Mitigated,
  not fixed: the filename differs from the committed one, and adopting it would `die` loudly in both
  consumers on the missing `# threshold-seconds`. Worth a line in the re-seed docs.

- **The PR-lane mutation deferral set widens silently.** The union table has 15 rows >= 5s where
  `mutation-slow-suites.tsv` had 10, so the guards paired to `install-topology`, `orchestrate-lean`,
  `retro-corpus`, `config-grill` and `doctor` selftests now report `deferred-to-nightly` on every PR.
  That is real grading moving off the PR lane, and it is a consequence of the union the spec ratified
  rather than a defect — but it is unnamed anywhere in the diff.

- **The shell prose ratchet's coverage narrowed, not just its mechanism.**
  `.claude/prose-budget-shell.baseline.tsv` measured comment density across all shell under the scan
  roots; `check-guard-budget.sh` measures total line count of guard/test shell only. Product shell
  comment bloat is now unmeasured. "Subsumed" (spec, scope item 2) overstates it.

## Pre-existing — not blocking, and not this PR's to fix

**AC-5's "still passes" clause fails for a reason that predates the branch.** The scope reviewer
raised this as a blocker and hedged it as "plausibly pre-existing"; it is pre-existing, confirmed
two ways:

1. The nightly `install-topology` job on **`b8cc982` — this PR's own base commit** — already reds
   with the identical signature:
   `RED: plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh — rc=1 — ok: (d3) ...` /
   `53 ran, 52 passed, 0 known-red, 3 skipped, 0 stale row(s), 1 red`
   ([run 32548858450](https://github.com/manoldonev/second-shift/actions/runs/32548858450)).
2. Staging every plugin into a version-keyed cache outside any git repo and running
   `pipeline-doctor-selftest.sh` from a `git init`'d consumer cwd gives byte-identical verdicts on
   the branch and on `origin/main`: 41 passed, 1 failed, failing case `(inv/sibling)`.

The known-red allowlist carried 0 rows, so deleting it changed no verdict — the red was already a
red. Scored **undeterminable** rather than unsatisfied: the deletion half is done and verified, the
pass half cannot be judged against a base that is already red.

## Strengths

- The derive-don't-store pivot is the right answer to why PR #645 was closed, and it is carried
  through cleanly: no committed ceiling, no update path, no operator ritual, and the escape hatch
  reuses `check-changelog-trailer.sh`'s grep-anywhere trailer mechanism rather than inventing one.
- `grep -c` instead of `grep -q` at `check-guard-budget.sh:91`, with the header explaining that `-q`
  + SIGPIPE + `pipefail` scores a match as a miss. That is the repo's own recorded footgun, avoided
  and documented at the site.
- AC-1's "no case may assert `rc` alone" is honored literally — all four fixture cases assert the
  printed base/HEAD/delta, which is what makes a wrong number distinguishable from a right one.
- The three-way table reconciliation is real reconciliation: all four conflicting pairs
  (`lean-evidence` 11/26, `lean-reconcile` 9/10, `check-lean-chain` 35/67, `preflight` 15/8) resolve
  to one row, and `run-selftests-selftest.sh` guards it against the **live** corpus with a duplicate
  check rather than a fixture.
- All 33 `gate-ablation-classes.tsv` rows carry a non-empty `earn_your_keep` cell — the column is
  populated, not declared.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | `check-guard-budget-selftest.sh` 12/12 green, run from the reviewed head. Cases 1-4 each assert the printed measured value. |
| AC-2 | **unsatisfied** | B2 — 3 probed single-arm mutants on `classify_ref()` each leave the suite 12/12 green. |
| AC-3 | **satisfied** | pr-gates step 5 `=> success` on run 32592962902; steps 6 and 7 both ran (7 fails on the expected pre-verdict lean-chain arm). Nothing was `skipped` because of this step. The "reds a synthetic branch" clause has no CI evidence — fixture case 3 covers the logic and a non-zero exit fails a `run:` step unconditionally, so noted rather than blocking. |
| AC-4 | **unsatisfied** | Files/dedup half satisfied (five files gone, one table replaces three, DUPES case on the live corpus, four conflicts resolved). Blocked on B3 (the threshold arm is unguarded in both consumers) and B4 (no per-consumer directive key). |
| AC-5 | **undeterminable** | Deletion half verified: `KNOWN_RED`, `known_red_index()`, `KR_SEEN` and the file all gone, no residual reference. Pass half fails on a red present at the base commit — see Pre-existing. |
| AC-6 | **satisfied** | My own run from the reviewed head, env-scrubbed: `74 scored, 74 run, 0 served from cache, 0 failed`, rc=0. `prose-budget.sh` exits 0 (`0 fail(s), 17 warning(s)`), so the nightly job stays green. |
| AC-7 | **unsatisfied** | B5 — −169 rows against ">= 170", and delta 0 against "lower". |
| AC-8 | **satisfied** | Both paragraphs at `docs/pipeline-manifesto.md:68-78`, beside the P-posture block. `docs/testing.md`'s new "What survives as a register" section links to the rule and states it is "its consequence, not a second copy of it". |
| AC-9 | **satisfied** | `Changelog:` trailer on `39fda97`, with a `Migration: none` line. |

## Round mechanics

- **Design fidelity: `not-applicable`, and the disarm is justified.** The spec's `## Design` section
  reads `Design: none — this is shell/CI tooling with no rendered surface`, and I confirmed
  `.design` is `null` in this repo's `.claude/second-shift.config.json`. No design provider is
  configured, so this is not the "disarm on a repo that configures a provider" blocker.
- **Coverage gap: `test-coverage-reviewer` went dark** (died after its automatic retry — turn budget
  exhausted mid-exploration, no text emitted on either attempt). Its domain is partly covered by the
  probes behind B2 and B3, which I ran myself, but not exhaustively. Security, performance,
  maintainability and complexity all returned approve with no findings above threshold.
- Panel verdicts: security ✅, performance ✅, maintainability ✅, complexity ✅,
  test-coverage `Dark (no output)`, scope-completeness ❌ block.
