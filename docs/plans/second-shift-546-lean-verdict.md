# lean review verdict — #546

verdict=approve
run_id: review-546-2
session_id: aa685318-925d-4c33-af97-5f20b9e1f942
rounds: 2
pr: #615
reviewed_head: 7c71fad3d9fdb03d06254950cb2786b4e3aeb983
reviewed_patch_id: 5d700f838a0b179b55635ac20b6b327e7ec09d1d
inherited_patch_id: 062382144fc2c06334672b161d3480240f19e835
inherited_from_verdict: 996ac3392796742e00c6e096f1e5f6fd9824b156
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Review — round 2

Round 1's blocker was a red lane, not an unmet criterion: `mutation-sweep-pr` was failing on
three baseline-absent survivors inside this PR's own new code. The delta is one commit and one
file — `cost-block-selftest.sh`, +90/-8, no production code — and it closes that blocker plus
both round-1 warnings. **CI is green on every arm except `pr-gates`, which reds solely on the
round-1 `verdict=needs-work` record this push replaces.**

I certified each fix by mechanism rather than by CI's green, in an isolated worktree at
`7c71fad3` against a 56/56 baseline.

### B1 — CLOSED. The three survivors are killed, each by the case that names it.

CI run 32413810403: `pipeline-cost-block.sh applied=12 killed=11 survived=1`, against round 1's
`applied=12 killed=8 survived=4`. Same 12 sites, three more kills — the arithmetic accounts for
exactly the three, with no coverage traded away. I reproduced each locally, applying the flip the
way `mutation-sweep.sh` does (`awk 'NR==n' | sed -E -e "$flip"`, spliced back), and asserting the
flip touched exactly one line:

| mutant | site | killed by | suite |
| --- | --- | --- | --- |
| `default::c2c7786871fb` | `:163` `${SECOND_SHIFT_CONFIG:-…}` | `(AC-6) configured state dir` | 55/1 |
| `logic::1e2b5beb13a7` | `:168` `cfg()`'s AND | `(AC-6) absent config key` | 55/1 |
| `cmp-eq::8d37545e081b` | `:266` summary `-eq 1` | both `(AC-3)` summary cases | 54/2 |

Clean fire/no-fire pairs off a green baseline. The two config fixtures are **not**
interchangeable, exactly as round 1 measured: the `logic::` mutant is untouched by the
moved-state-dir repo and dies only on the config that EXISTS but OMITS the key, where `jq -r`
yields the literal string `null`. Two throwaway repos was the right count, not defensive excess.

The `(review included)` assertions are the part worth more than a mutant score. That
parenthetical is the only operator-visible signal that AC-3's union fired, and AC-3 makes the
non-union degrade deliberately silent — so it is the one thing separating "close-out run from the
wrong checkout" from "legitimate pre-review invocation", which is this ticket's own defect class.
It is now asserted in both directions.

### W1 — CLOSED, and verified by re-running round 1's own probe verbatim.

Re-inserting `record '"skipped-telemetry-off"'` at its original site (the no-readable-metrics
branch) now **reds** the suite — `55 passed, 1 failed`. Round 1 measured that same revert green.
The preceding case, which asserts the branch's own diagnostic, still passes under the revert, so
the guard is not green by failing to arrive. The mechanism is portable: `file_mtime` tries
`stat -c` then `stat -f`, both `stat`, so the stubbed `stat` disables both forms — which is why
this reaches the branch on the ubuntu and macOS lanes alike.

### W2 — CLOSED, and its blast radius checked.

`COST_LOG_FILE="$CL2"` now precedes `bash`, so it is environment rather than argv. Now that it is
effective it writes a row at `:734`; `$CL2` is read only at `:705` (before), and the AC-13 block
is the last in the file. Nothing downstream observes it, so the fix stays inert as intended.

### Verification

56/56 under bash 5.3 and stock `/bin/bash` 3.2; `shellcheck -e SC1091,SC2015,SC2181` clean;
`check-lockstep-pairs.sh` 25 anchors, 0 failed. Every remaining survivor is baseline-present
(`catalog::cost-block-cache-numerator` row 23; `retro-corpus.sh` rows 83–84), so the sweep's green
is 23 computed verdicts, not a 0-verdict pass. Suite cost is ~2.7s CPU — still under the 5s
slow-list bar, so the five added cases create no new slow-suite obligation.

Panel (security, performance, maintainability, complexity, test-coverage, scope-completeness) ran
full over the delta: **6/6 approve, zero blockers, zero majors, no reviewer dark.**

## Blockers

None.

## Warnings

None. Round 1's two warnings are both closed above and are not re-raised.

## Suggestions

- **`issue_stderr` and `issue_stderr_at` are near-duplicates** (`:492` / `:608`) — same
  "run it, keep stderr, drop stdout" idiom, differing only in cwd source and the
  `env -u SECOND_SHIFT_CONFIG` scrub. Each is four lines with a clear comment, so this is a
  readability nit, not debt. (Maintainability, confidence 55 — below threshold.)
- **`retro-corpus-selftest.sh` slow-list drift persists** — the sweep still warns it measured 11s
  (was 15s at round 1) without a row at that bar in `tools/mutation-slow-suites.tsv`. Carried
  forward from round 1 as informational; the sweep itself says to fix it by ordinary PR, and it is
  a warning rather than the red. Not escalated.

## Dismissed

- **Scope-completeness noted the dispatched base was an intra-branch commit** and re-classified
  against `merge-base f51f7d87` with `origin/main`. That is the correct widening for scope scoring
  — the delta bounds what I re-read, never what must be found — and it is a process note, not a
  defect.
- **Security's two suppressed notes** (PATH prepend of a stubbed `stat`; `git init` into fixture
  repos) are both scoped to a single subshell inside a `mktemp -d` tree. Agreed, no leak — I
  confirmed the stub does not survive its invocation.
- **An exported `STATECTL_STATE_DIR` defeats the two new config cases** — but it reds 23 cases
  suite-wide, so it is a pre-existing property of the whole fixture design, fails closed, and is
  not a gap this delta introduces.

## AC scoring

Production code is byte-identical to the patch round 1 reviewed (`062382144fc2`); the delta is
test-only. AC-1 through AC-14 are inherited on that basis and re-confirmed green by the suite.
AC-15 is strictly stronger than at round 1.

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 derived fence | satisfied | inherited; round 1 reproduced it on this run's own production record |
| AC-2 derived session set | satisfied | inherited; lockstep `lean-session-set` passes |
| AC-3 review session unioned | satisfied | **strengthened** — the union is now asserted in both directions via the summary suffix |
| AC-4 honest title | satisfied | inherited; both titles driven |
| AC-5 explicit args win | satisfied | inherited; each override driven in isolation |
| AC-6 underivable fence is rc=2 | satisfied | **strengthened** — which record is read is now driven, not assumed |
| AC-7 `--close-out` restores the row | satisfied | inherited |
| AC-8 cross-era schema | satisfied | inherited; key set and the byTier/byLabel split asserted |
| AC-9 identity (ticketKey, runId) | satisfied | inherited; replace-vs-append pair driven |
| AC-10 no rollup, no row | satisfied | inherited |
| AC-11 `--prs` | satisfied | inherited |
| AC-12 prose sites corrected | satisfied | inherited |
| AC-13 dead `record` call removed | satisfied | **strengthened** — the branch it sat on is now entered, and a revert is caught |
| AC-14 `--help` range | satisfied | inherited |
| AC-15 every new assertion driven | satisfied | 51 → 56 cases; three previously-undriven paths now carry fire/no-fire pairs |

Fifteen of fifteen satisfied, none undeterminable.
