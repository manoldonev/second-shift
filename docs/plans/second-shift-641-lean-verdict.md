# lean review verdict — #641

verdict=approve
run_id: review-641-3
session_id: 73a2c98e-ceef-4135-9311-f9f230f3bdb0
rounds: 3
pr: #645
reviewed_head: 73534a915c725a0b9a997b0b1075f0732849e05d
reviewed_patch_id: b940751b804c9fdbfcf2ce4dcac5cc2a5aeb32ae
inherited_patch_id: 95f97f1e44fd2832e39359cde7993b86325edcb6
inherited_from_verdict: b804b36d077f5d0e5744256233526d98df7c03ef
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 3 — delta `b804b36..73534a9` (2 files, +4/-3), inheriting rounds 1–2's coverage of
`b8cc982..b804b36`. Verdict: **approve**.

Both of round 2's blockers are closed, and closed with execution evidence rather than by
assertion. B-2 in particular went from *seven of seven mutants surviving* to *eight of eight
killed* on a re-run of round 2's own probe. Every `AC-n` is satisfied. Two warnings are carried
below; neither blocks, and one of them is the more interesting finding of the round.

## Per-AC scoring (against `docs/plans/second-shift-641-lean.md`)

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `tools/guard-budget.tsv` exists; `check-guard-budget-selftest.sh` drives the shipped script over eight fixture git repos covering all six required behaviours. Ran here at the reviewed head: **10 passed, 0 failed**. Case 7 now asserts the measured value, not just the exit code (see B-2 below). |
| AC-2 | satisfied | All 33 data rows of `tools/gate-ablation-classes.tsv` carry a non-empty 6th column (verified by an independent `awk` pass over the committed file, zero offenders); `gate-ablation.awk:57` reds naming the row on blank **and** on absent. `gate-ablation-selftest.sh`: ALL CASES PASSED here, cases (t)/(t2)/(t3) included. |
| AC-3 | satisfied | The step is wired in `pr-gates` (`ci.yml:280-286`) and — new this round — **ran green on the real merge tree**: CI run `32574669326`, job `pr-gates`, step 5 `completed/success`. Case 2 reds a synthetic over-budget tree. |
| AC-4 | satisfied | One pointer paragraph at `docs/pipeline-manifesto.md:68` in the `**Pn posture:**` form, no restatement of P4/P5's text. Unchanged this round. |
| AC-5 | satisfied | Four `Changelog:` trailers across the branch; CI's trailer guard (`pr-gates` step 4) is `completed/success`. The round-3 commit carries no trailer of its own, which is fine — trailers are extracted grep-anywhere and survive the squash. |

Fidelity: **not-applicable** — the spec declares no armed `## Design` section (`## Design
decisions` is prose, with no handoff link and no `| RS-n |` rows), and the repo's config declares
no `design.provider`. Step 5b does not apply.

## Round-2 blockers — disposition

**B-1 — the ceiling had zero headroom and redded this PR's own `pr-gates` step. CLOSED.**

`tools/guard-budget.tsv:20` is raised `50531 → 50560` with a reason in the same diff, which is
the mechanism's own contract for a raise. Verified in both directions:

- At the reviewed head, from the PR's own checkout: `bash scripts/check-guard-budget.sh main` →
  `[guard-budget] at budget: measured 50560 lines, ceiling 50560.` rc=0. Same result against
  `origin/main`.
- On CI's merge tree, which is the answer the diff cannot give: run `32574669326`, `pr-gates`
  step 5 `completed/success`.

Round 2's downstream tell is closed with it. Step 6 (pipeline chain reconciliation) is now
`completed/success` — it had been `skipped` behind the red at every prior commit, so this PR's
evidence set had never been reconciled by CI. Step 7 (lean chain) now *runs* and fails for the
one correct reason: `verdict record ... reads 'verdict=needs-work', not 'verdict=approve'` — the
standing round-2 record. That is the expected pre-handoff shape, not a finding.

**B-2 — Case 7 could not fail in the narrowing direction. CLOSED, and verified by re-running
round 2's probe verbatim.**

`scripts/check-guard-budget-selftest.sh:121` now asserts the output (`at budget: measured 61`)
rather than only `rc -eq 0`, which was the fix round 2 prescribed. Re-probed in an isolated
scratch tree at the reviewed head — each `classify()` arm neutered one at a time to a
non-matching pattern, `bash -n` clean throughout, scored by case id:

| arm neutered | round 2 | round 3 |
| --- | --- | --- |
| `-name '*-selftest.sh'` | ok (survived) | **FAIL** — `measured 56, ceiling 61` |
| `-name 'check-*.sh'` | ok (survived) | **FAIL** — `measured 51` |
| `-name '*-lint.sh'` | ok (survived) | **FAIL** — `measured 54` |
| `-path '*/skills/*/lean-gate.sh'` | ok (survived) | **FAIL** — `measured 52` |
| `-name 'run-selftests.sh'` | ok (survived) | **FAIL** — `measured 50` |
| `-name 'mutation-sweep.sh'` | ok (survived) | **FAIL** — `measured 48` |
| `-name 'gate-ablation.sh'` | ok (survived) | **FAIL** — `measured 55` |
| *(control)* broaden to `-name '*.sh'` | FAIL | **FAIL** — `measured 1061` |

**7/7 surviving → 8/8 killed**, control preserved. Each mutant's diagnostic names a distinct
`measured` value, so the kills are the arms and not one shared accident.

## Warnings (should fix, neither blocking)

**W-1 — after this merges, the guard's *second* check can no longer fire on the real tree.**
`scripts/check-guard-budget.sh:80`

The raise-without-reason arm is armed by exactly one condition: the reason column at HEAD being
blank. Round 3's own delta is what makes that column permanently non-blank on `main`. Probed as a
matched fire/no-fire pair against the shipped script:

| fixture | result |
| --- | --- |
| base carries #645's reason; a later PR raises `100 → 500` leaving the reason **verbatim** | **rc=0, arm silent** |
| base carries an empty reason; the identical raise | rc=1, `ceiling raised from 100 to 500 with no reason recorded` |

So from merge day, a future author can raise the ceiling to any value and the gate stays green as
long as they leave PR #645's reason string sitting beside it. AC-1's third case still passes —
its fixture constructs the empty-reason base that the real tree no longer has.

Not raised as a blocker, on three grounds, and I want the reasoning on the record rather than the
conclusion alone. AC-1 is satisfied by its letter and by both fixture directions. A raise remains
a visible, deliberate edit in a reviewed diff whether or not the gate speaks — the gate's marginal
contribution was only ever forcing blank → non-blank. And the primary check (measured > ceiling)
is fully live and is where nearly all of the mechanism's value sits. This was seen at round 1
(S-4) and round 2 (S-2) and adjudicated discretionary both times; what changed is that it moved
from hypothetical to live, which is worth recording even though the call is the same. The fix
wants the reason compared against the merge-base copy, not merely tested for emptiness — a real
design decision, and a natural addition to **#646**'s scope.

Two smaller findings in the same file, not separately raised: `ceiling_row()` exits on the first
data row, so a second appended row is silently ignored despite the header's "ONE data row"
(probed: appending `99999` below the live row leaves the ceiling at the first value, rc=0), and
the date column is never validated. Both are round 2's S-2, unchanged.

**W-2 — the spec and the issue both state a committed ceiling the tree contradicts.**
`docs/plans/second-shift-641-lean.md:33,39,54`

F-1 says *"The committed ceiling is **50,531**"* in the present tense; D-a and F-3 repeat the
figure; #641's `## Build-time amendments` bullet states it as fact. The committed row is
**50,560**. Rounds 2 and 3 moved the number and the prose did not follow.

This is the inverse of the shape the review contract treats as a blocker — the spec was *not*
amended to agree with the diff, it simply went stale — and it is self-correcting for a reader,
because `tools/guard-budget.tsv`'s reason column is in the same diff and names rounds 2/3
explicitly. The issue's section is also titled "(PR #645 round 1)", which scopes its literals.
Carried as a warning rather than a blocker for those reasons; the honest remedy is one edit
replacing the literal with "the post-merge measured value", which is what D-a actually decided.
Raised by `scope-completeness-reviewer` at confidence 92, and confirmed here against both files.

## Suggestions

- **S-1** Round 1's S-2 is now closed — the PR body carries the `--full` = 74 / `--exclude`-only
  = 61 distinction. Worth noting the body was edited *after* CI started, so `pr-gates`' captured
  copy of it still shows the round-1 text; harmless, but it is why the CI log and the PR disagree.
- **S-2** Round 3's commit message says the probe covered "the six untested `classify()` arms" and
  then lists five. Understated rather than overstated — the probe here confirms all seven arms are
  killed — so it costs nothing but the count in the message is wrong.

## Strengths

- **The B-2 fix is the smallest thing that could possibly work, and it works completely.** One
  line, from an exit-code assertion to an output assertion, converting a case that could not fail
  in the direction it advertised into one that kills every arm of a seven-way classifier. Round
  2 prescribed exactly this line; the build applied exactly it, and did not pad around it.
- **The ceiling raise pays the mechanism's own price in public.** `tools/guard-budget.tsv:20`
  carries the number, the date, and a reason naming the specific commits that consumed the
  budget. The PR that introduces "a raise needs a stated reason in the same diff" is the first
  thing to be held to it, and it did not carve itself an exemption.
- **`pr-gates` now reaches the chain-reconciliation steps for the first time on this branch.**
  Steps 6 and 7 had been skipped behind a red step 5 at every prior commit; closing B-1 also
  restored the evidence path that was silently unexercised, which was the part of round 2's
  finding that was easy to miss.
- **`mutation-sweep-pr` produced real verdicts, not a vacuous green.** 6 applied, 6 killed, 0
  survived on `scripts/check-guard-budget.sh` with 7 verdicts computed by running the paired
  suite — worth stating explicitly, because an rc=0 from PR-mode can also mean nothing was swept.

## Suppressed / not carried

- `scope-completeness-reviewer` (conf 84) — no `earn_your_keep` cell carries a dated incident,
  though the header adopts the convention. The scope clause is conditional ("where one exists")
  and there is no incident registry to check a row against. Round 2 adjudicated the same clause
  the same way; not carried, for consistency rather than by re-deciding it.
- `security-reviewer` (conf 30) — the free-text reason column is committed prose in a
  repo-controlled file with no injection or disclosure sink. Correct, and below threshold.
- Not a finding, recorded so a later round does not re-derive it: `echo "$OUT" | grep -q` under
  `set -o pipefail` can score a match as a miss when the writer is large enough to block. Both
  directions were exercised here (the clean run passes, all eight mutants fail through this
  line), the payload is one short line, and the idiom is pre-existing at `:55` and `:67`.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 2 (1 major, 1 minor) | 84–92 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

No reviewer went dark; all five selected returned usable results. Complexity was not selected
(the delta is Small — 2 files, +4/-3). a11y + design-fidelity were not routed: no changed path
matched `stageParams.webComponentGlobs`, which resolves to the shipped default
`apps/web/**/*.{tsx,jsx}` because the repo's config declares neither the key nor a
`design.provider`. Neither is a coverage gap.

**W-1 is an orchestrator finding**, from a fire/no-fire probe of the shipped script rather than
from the diff — as were both of round 2's blockers. The panel found nothing stronger than the
stale literals in W-2, which is the right outcome for a four-line delta whose job was to close
two specific findings.

## Verification run at the reviewed head

- `bash scripts/check-guard-budget.sh main` → rc=0, `at budget: measured 50560 lines, ceiling 50560`.
- `bash scripts/check-guard-budget-selftest.sh` → 10 passed, 0 failed.
- `bash tools/gate-ablation-selftest.sh` → ALL CASES PASSED.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files → clean.
- CI at `73534a9`: `lint-and-selftests` success, `selftests (macos, bash 3.2)` success,
  `mutation-sweep-pr` success, `pr-gates` failing only on step 7 for the standing needs-work
  record.
- No `tools/mutation-catalog.tsv`, `mutation-baseline.tsv`, `mutation-exclusions.tsv` or
  `LOCKSTEP-BEGIN` obligation attaches to either changed file; round 3 edited a selftest and a
  data row, not guard code, so no anchor is re-keyed.
