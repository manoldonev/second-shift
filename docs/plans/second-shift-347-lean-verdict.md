# lean review verdict — #347

verdict=approve
run_id: review-347-2
session_id: 2e80eb6e-b847-4cab-8536-eed734d627b2
rounds: 2
pr: #369
reviewed_head: 7c6f89e58c11ac69149f9ec80d09313a279914f7
model: unknown

## Review summary

Round 2 on PR #369 (issue #347), reviewing commit `7c6f89e` on top of the round-1 tree. Both
round-1 blockers are fixed, and fixed the way round 1 asked rather than the way that would have
been cheaper — B1 by strengthening the assertion instead of baselining the survivor, B2 by
guarding the call site instead of catching the tool's failure after the fact. Two round-1
warnings (W1, W2) were also closed in the same commit. Four reviewers ran (scope-completeness,
test-coverage, maintainability, security); none went dark, all returned approve.

**Verdict: approve.** All eight ACs of the committed spec are satisfied. Three warnings and two
suggestions below; none is an unmet AC, and none is a new risk this diff introduces. W1 is the
one that needs its own issue — it is a pre-existing windowing defect that this diff's guard
converts from a quiet degradation into a silent total loss.

The spec grew an AC-8 in this commit. That is the legitimate direction and worth stating
explicitly, because the opposite direction is a blocker by rule: the diff `33c9d0b..HEAD` on
`docs/plans/second-shift-347-lean.md` is **append-only** (zero deleted lines), so AC-1's narrow
text — the narrowing round 1 named as its finding — was not rewritten to match the code. AC-8
records a new obligation the review discovered, and the code meets it.

## Verification run for this round

- Full local selftest sweep, **without** `SKIP_STRESS`: exit 0. `retro-corpus-selftest.sh` 9/9,
  `statectl-selftest.sh` 274/274.
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: zero findings.
- CI on `7c6f89e`: `lint-and-selftests` **pass** (7m45s) and `selftests (macos, bash 3.2)`
  **pass** (11m1s). That first lane carries the PR-scoped mutation sweep on the **GNU** runner
  that produced B1's survivor, which is the only place B1's remedy could be proven.
- `pr-gates` **fail**, correctly and expectedly: `check-lean-chain.sh` reads round 1's committed
  `verdict=needs-work`, and separately reports that record approves `33c9d0b` while 5 files
  changed after it, and that it carries no `reviewed_head` key. All three clear when this
  round's record lands — round 1's record predates `#367` in this branch's history, so it was
  written by a `lean-gate.sh` that did not yet emit that key.

## Per-AC scoring (against `docs/plans/second-shift-347-lean.md`)

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(AC-1)` green, and now asserts two things, not one: the artifact-only fixture yields zero `era: "stage"` rows (the signal the guard reads), and `stage-envelopes.sh` still hard-exits on that same fixture. Confirmed the second assertion reaches the intended arm — the message is `no run-state files under <dir>`, the stage-empty one. |
| AC-2 | satisfied | mixed-era fixture aggregates to both eras in one array. |
| AC-3 | satisfied | ticketKey 345 present in the corpus output. |
| AC-4 | satisfied | pass-through and the `unknown` default both asserted; the producer side is now asserted too — see AC-8/W1 closure below. See Suggestion 1 for a prose imprecision that does not affect the field. |
| AC-5 | satisfied | `open-prs` flags 701, clears 702, ignores the non-lean 703. |
| AC-6 | satisfied | unchanged since round 1's verification of both SKILL.md diffs; this commit only adds to `perf-retro`. |
| AC-7 | satisfied | `Changelog:` trailer on all five commits. |
| AC-8 | satisfied | Guard present at `perf-retro/SKILL.md` Step 1; Step 3 (`:90-91`) and Step 6 (`:141-147`, `:159-162`) each state `0 stage-era run(s) in window` and omit their table rather than emitting it empty. The selftest half is the extended `(AC-1)` case. See Warning 2 for a third report surface the AC's letter does not reach. |

## Blocker closure, verified by applying the mutants

Not taken on the commit message's word — each fix was re-broken locally to confirm the new
assertion is what catches it, then restored (`git diff` clean afterward).

**B1 (help-window survivor) — closed, on both platform arms.** The point of B1 was that the
`(help)` case's `grep -qF 'Usage:'` could not kill `sed -n` → `sed -z`, because GNU sed's
auto-print dumps a whole file that also contains `Usage:`. Both arms now die:

| Mutant | Result |
| --- | --- |
| `sed -z '2,40p' "$0"` (BSD arm, verbatim mutant) | **killed** — `rc=0, 1 line(s)`, empty output fails the `Usage:` presence check |
| `cat "$0"` (the GNU arm's observable effect — whole-file dump) | **killed** — `241 line(s)`, fails both the `set -uo pipefail` absence check and `-le 39` |

Correctly, no `retro-corpus.sh::cmp-z` row was added to `tools/mutation-baseline.tsv` — the four
rows it does add are the genuinely-unkillable ones, each with a per-row rationale rather than a
shared "seeded by the canonical seed run". The `-le 39` bound is exact: `--help` emits exactly
39 lines today, so one added usage line reds the case.

**B2 (era-awareness stopped at the enumerator) — closed.** Verified every `stage-envelopes.sh`
reference in `perf-retro/SKILL.md` is now downstream of the Step 1 count: `:50-52` (the guard),
`:91` (Step 3), `:95` (the p90 sentence, inside Step 3's guarded block), `:141` and `:159`
(Step 6's two templates). `stage-times.sh` was already guarded by "Per selected `era: "stage"`
run". `pipeline-retro/SKILL.md` never calls `stage-envelopes.sh` at all.

**W1 (`model:` untested at the producer) — closed.** `lean-gate-selftest.sh` now asserts the key
at both writers: `(m1b)` for `ensure_progress_file()`, and `(p5)` extended for `cmd_verdict()`.
That was the mirror-harness gap — the fixture helper hand-authors the header, so without these
the producers had no coverage for the key at all.

**W2 (`REPO_ROOT`/`MAIN_ROOT` anchor drift) — closed, and guarded.** `retro-corpus.sh:151` now
resolves the verdict record from `MAIN_ROOT`. The new `(verdict-detect-worktree)` case is
non-vacuous — I reverted the line to `REPO_ROOT` and the case failed with
`expected true from a worktree caller, got hv901=false`, which is the exact cross-checkout
disagreement round 1 reproduced on the live corpus. The pre-existing `(verdict-detect)` case
could not catch this because `$TREE` stood in for both anchors; the new case adds a real
worktree so they differ.

## Warnings

**W1 — the era-mixing window now silently deletes the stage profile instead of shrinking it.**
Carried over from round 1's W3, **not addressed**, and materially worse in combination with this
commit's guard. `retro-corpus.sh:159` applies `--window` *after* merging and date-sorting both
eras, and artifact rows are always the most recent. Re-measured on the live corpus, unchanged
from round 1: at the SKILL's `--window 15`, **5 artifact + 10 stage**, against **16 stage rows
available** — six already displaced. Ten more lean runs fill the window with artifact rows, the
`era: "stage"` count reaches zero, and the new guard then skips `stage-envelopes.sh` entirely and
prints `0 stage-era run(s) in window` — while 16 stage runs sit in the state dir unread.

This is not a reason to hold the PR: it is a pre-existing defect, no AC covers windowing, round 1
filed the same finding as a warning, and the guard is precisely the remedy round 1 prescribed for
B2. But the failure mode changed shape. Before this commit, full displacement produced a loud
hard exit; after it, it produces a confident, wrong, quiet report line. Per-era window budgets
(or a stage-row floor) is the fix, and it wants its own issue rather than a late edit here.

**W2 — Step 6's Cost-envelopes table is the one surface the zero-stage guard does not name.**
`stage-envelopes.sh` emits three things, and Step 1's guard skips the whole call. Step 6 states
replacement text for two of them (the Profile corpus line, the Over-envelope table) and says
nothing about `## Cost envelopes (per bucket)` — so a retro following the SKILL literally emits
that table empty, which is the exact reading the fix's own env14 citation condemns two paragraphs
later ("'measured nothing' must not read as 'measured and found nothing'").

Outside AC-8's letter, which names the guard and the `0 stage-era run(s) in window` text and both
of which are present — hence not a blocker. Also confirmed no data is *stranded*: the hard exit
at `stage-envelopes.sh:132` precedes the `COST_LOG` read at `:169`, so cost envelopes are
unobtainable on a stage-empty corpus either way, and nothing in `run-lean/` writes
`cost-log.jsonl` (the live log holds 3 rows, newest 2026-07-23 — all stage-era). One line in the
template closes it.

**W3 — model identity still ships inert.** Round 1's W4, unaddressed and correctly so — it needs
a decision, not a line. Nothing exports `LEAN_RUN_MODEL`; all five live artifact rows read
`model: unknown`, including this run's. AC-4 passes by its letter and the key is now genuinely
tested at both producers, but the ratified directive it implements ("cross-model deltas are
queryable") stays unmet in production until something sets the variable. `run-lean/SKILL.md` is at
its 60-line cap, so this is a routing decision.

## Suggestions

1. **`perf-retro/SKILL.md:60-61` says an artifact row "reads it from the progress/verdict
   record's `model:` key"; the code reads only the progress record.** (scope-completeness, conf
   92 — verified: `retro-corpus.sh:141` reads `$f`, the progress record; the verdict record is
   opened only for `hasApprovedVerdict` at `:146-153`.) Reading the progress record alone is the
   right design — it is the artifact that always exists, including mid-run — so the fix is to
   drop `/verdict` from the sentence, not to add a fallback. No scope impact; AC-4's oracle
   asserts the progress-record path.
2. **The strengthened `(help)` case catches over-emission but only partly catches truncation.**
   Header growth *above* `Usage:` is caught (it pushes `Usage:` past line 40, failing the
   presence check), but growth *between* `Usage:` and line 40 silently drops the tail seam docs —
   the `#363` regression shape. Asserting the last line of the block, not just `Usage:`, would
   close it.

## Dismissed

- *The new `(verdict-detect-worktree)` case leaks git worktree metadata* (maintainability, conf
  55 — suppressed at source). `$TREE` lives inside `$WORK`, and the `EXIT` trap removes `$WORK`
  whole, so both the repo and its worktree registration go with it. No state escapes the fixture.
- *`record_key`'s `[A-Za-z0-9._/-]+` class admits `..`, so `verdict_record:` could resolve
  outside `$MAIN_ROOT`* (security, conf 45 — suppressed at source). Pre-existing: the class
  predates this commit, which only re-anchored the prefix; the value is pipeline-authored, and
  only a boolean is observed. Agreed, not a finding.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 1 nit | 92 |
| Test Coverage | Pass | 0 | — |
| Maintainability | Pass | 0 (1 suppressed) | — |
| Security | Pass | 0 (2 suppressed) | — |

Coverage note: performance and complexity were not re-dispatched this round — both returned zero
findings in round 1 and `7c6f89e` touches neither surface (one guard line, one selftest, one
Markdown template, one spec append).
