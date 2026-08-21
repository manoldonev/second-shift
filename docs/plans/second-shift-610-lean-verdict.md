# lean review verdict — #610

verdict=needs-work
run_id: review-610-2
session_id: 6cc27e31-4dbf-4af8-872f-ac6f107a66d3
rounds: 2
pr: #625
reviewed_head: 768ceea488540a121c0ac45e1af435e7f12c1e33
reviewed_patch_id: 3142263a15bd4f56f1cc3a5341569fd3dcf2349c
inherited_patch_id: 4ea3297097df04d30a53846e91ad3d171c83ae05
inherited_from_verdict: 1b800d54fba0585f8ca7a91fbc2aca05cb0742d5
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, inheriting round 1's coverage of patch `4ea3297097df`. Delta read:
`1b800d54..768ceea4` (7 files) — the single fix commit answering round 1's three blockers.
Verdict: **needs-work** — one blocker, and it is not in the diff.

All three round-1 blockers are fixed, and I verified each one rather than reading the
commit message:

- **B-1 (mutation survivors) — fixed, verified cold.** The first sweep I ran returned
  `killed=8 survived=0` with **0 verdicts computed and 8 served from cache**, which proves
  nothing. Re-run against an isolated cache dir: `applied=8 killed=8 survived=0`, 9 verdicts
  computed live, rc=0. Both coverage gaps are genuinely closed — the fixture-tree copy of the
  tool makes the derived root answer, and the 190-character construct plus a length comparison
  distinguishes `--full` from the 160-character excerpt.
- **B-2 (wider counts unreported) — fixed.** `check` now prints
  `tiers: stop=12 (default), bold=58, all=226 - the default excludes 214 wider construct(s).`
  The three tier counts are each checked against an independently computed census, and the
  difference against their arithmetic. I probed all three: deleting the line, breaking the
  subtraction, and making `n_bold` wrong each fail exactly the case written for it.
- **B-3 (lockstep pinned a false sentence) — fixed correctly.** The anchor now pins only the
  hard-stop and the rc report, and each of the four sites carries its own tail. I read all four:
  `intake-interviewer` hands the draft over, `plan-interview` hands nothing off, and the two
  `intake-orchestrator` sites label nothing and create nothing. The contradiction is gone and
  the anchor no longer forces three correct sites to follow a fourth. `check-lockstep-pairs.sh`
  passes 27/27.

The two round-1 warnings that were code are also closed and probe-confirmed: the caps-`ABORT`
arm now takes the raw text as a parameter (removing it fails "a bare shouted ABORT is a stop"),
and the `refusal` noun form gained its case (narrowing the alternation fails it). The third
warning was the PR body's incomplete prose-budget accounting; the body now names all three
stale rows including `onboard`.

## Blocker

### B-4 — the branch cannot merge, and the reviewed head has no CI at all

`mergeable: CONFLICTING`, `mergeable_state: dirty`. #627 landed on `main` after this branch was
cut and conflicts with it in `plugins/dev-pipeline/skills/build-lean/SKILL.md` and
`tools/run-selftests-selftest.sh`. GitHub runs no checks on an unmergeable PR, so
`gh api .../commits/768ceea4/check-runs` returns **zero** check-runs — where round 1's head
carried five. `pr-gates` and `mutation-sweep-pr` are not red here; they have not run.

That leaves this round with no CI evidence, and local green is not a substitute in this repo —
the bash-3.2 lane, ubuntu's gawk, and the shellcheck version skew each red things that pass
here, and `prose-blockers.sh` is a new awk-heavy tool of exactly that class. What I can say is
what I ran locally, cold, from the reviewed head: the full sweep is **72 scored, 72 run,
0 failed**; `shellcheck -e SC1091,SC2015,SC2181` is clean on both changed shell files;
`prose-blockers.sh check` exits 0 reporting 12 constructs over 26 files against 34 rows; the
PR-scoped mutation sweep is 8/8 killed. That is a strong local signal and it is not the lane.

The second half of this blocker is why it cannot be waived: **resolving the conflict edits `+`
lines in two files that are inside the reviewed patch**, so a verdict written now is void on
arrival — milestone 4 recomputes `reviewed_patch_id` and refuses it. Approving would certify a
patch that cannot land and will not survive being made landable.

Two things I checked so the resolution is not guesswork:

- **The census survives the merge.** I ran the census over #627's `build-lean/SKILL.md` and over
  the branch-base version: both carry the same 8 construct ids, and #627 mints **none** that the
  triage record lacks a row for. So the resolution is "apply this branch's prune on top of #627's
  step-9 `close-out` rewrite", and `check` stays green. AC-6 is not at risk.
- **`run-selftests-selftest.sh` needs a real merge, not a side-take.** Main's side adds
  `LEAN_JOB_CEILING=2` (so a dropped scrub fails everywhere, not only under concurrency); this
  branch's side adds `-u LEAN_SELFTEST_CACHE_DIR` to the scrub. They are complementary — taking
  either side whole silently drops the other's coverage, in a test file, where the loss reads as
  green. The resolution keeps both.

## Warnings

- **The `EXIT`-trap fix is real and unguarded.** `(census) >"$tmp_census" || exit $?` closes a
  genuine leak: `check` arms its trap for two temp files and then calls `census`, whose own
  unconditional `trap … EXIT` replaces it. Measured in the real temp dir (`mktemp` ignores
  `TMPDIR` on this host, so a `TMPDIR`-scoped count reads 0 either way and proves nothing):
  the shipped form leaks **0** files per `check`, the reverted form leaks **2**. Reverting it
  fails **no** case — the suite still passes 50/50. The mutation sweep does not cover it either:
  its 8 mutants are budget-capped (`sites_beyond_budget: cmp-z:4+logic:23+default:1`), so
  `killed=8/8` proves eight mutants died, not that this site is reachable. One assertion counting
  the tool's temp files before and after a `check` run closes it.
- **Slow-list drift, introduced by this branch.** The sweep warns that
  `tools/prose-blockers-selftest.sh` measured **13s** against a 5s bar while
  `tools/mutation-slow-suites.tsv` has no row at or above it, so its guard stays in the PR lane.
  Warn, never red, by that tool's own contract — but the suite is new here and the row is this
  branch's to add.
- **The tool header's `promoted` gloss is false of every promoted row.** `prose-blockers.sh:11`
  reads "promoted — it is worth enforcing, so a gate now does". All four promoted rows
  (`pb-0426581f`, `pb-21641fc1`, `pb-ce91bffc`, `pb-3bdd8454`) are `filed` against #622/#623/#624
  with no gate, which AC-4 explicitly authorizes. The record is right and the header overstates
  it — worth one line in a tool whose subject is prose that claims more control than it has.

## Panel

Seven reviewers selected. Six returned; **`test-coverage-reviewer` went dark** (died after its
automatic retry — turn-budget cap, no text on either attempt). Coverage gap: the test-adequacy
dimension was not reviewed this round by that reviewer. Not a void round — six usable results —
and I read the suite myself and probed eight assertions, which is why this does not change the
verdict. Security, performance, maintainability and complexity approve with no findings.
`scope-completeness-reviewer` approves. `unit-test-mutation-reviewer` returned one minor finding
at confidence 82 — the unguarded trap fix — which I probed and promoted to the warning above; it
is the one finding the budget-capped sweep could not have surfaced.

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matches the
resolved web-component surface (`apps/web/**/*.{tsx,jsx}`, the shipped default — this repo
declares no `stageParams.webComponentGlobs`). `db-reviewer` and `pipeline-reviewer` were not
triggered. Not coverage gaps.

`scope-completeness-reviewer` noted that it was dispatched with base `1b800d54` and re-scoped
itself to `ab0a2d68...768ceea4` before judging. That base is correct for a delta round — the gate
derives it from the committed records — but the reviewer is right that scope must be judged
against the whole branch, and it did so.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Round 1's only gap was the unreported wider counts; `check` now prints stop/bold/all and the excluded difference, guarded against absence and against a wrong count (three probes, all killed). Census, corpus, block unit, lockstep grouping, content-derived ids and the behavioral selftest were verified in round 1 and are unchanged. |
| AC-2 | satisfied | Inherited. Re-confirmed live: 34 rows, `check` rc=0, zero undispositioned. The delta does not touch the record. |
| AC-3 | satisfied | Inherited from round 1, which read the enforcers rather than trusting the cells. Unchanged in the delta. |
| AC-4 | satisfied | Inherited; re-verified that #622, #623 and #624 are all still OPEN. All four promoted rows are `filed`, per D-1. |
| AC-5 | satisfied | Inherited. Six-column TSV, unchanged in the delta. |
| AC-6 | satisfied | `check` exits 0 on the pruned tree — and, per B-4's first check, still would after the conflict is resolved, since #627 mints no construct the record lacks. |
| AC-7 | satisfied | `prose-budget.sh --check` on the reviewed head: every row this branch touches reads `ok`, and exactly the three pre-existing failures (`QUERIES.md`, `figma-faithful-spec-reviewer.md`, `capability-parity-check-selftest.sh`) remain red rather than laundered green. The five rows this round moved are regenerated. |

Design fidelity: `not-applicable`. The spec disarms it (`Design: none — this repo configures no
design provider`) and the repo's config declares no `design.provider`, so the disarm is justified.

## What round 3 needs

Merge `origin/main` in, resolving both conflicts as described above; push; then a fresh review
context. If CI is green on the merged head, the only open items are the three warnings, none of
which is a blocker on its own.

## Strengths

- The B-1 fix is diagnosed at the right level. "Every case supplied `PROSE_BLOCKERS_ROOT`, so the
  derivation never ran" is the actual reason those mutants survived, and putting a copy of the
  tool inside the fixture tree makes the derivation answer instead of stubbing it — the harness
  now exercises the branch rather than asserting around it.
- The B-3 fix moves the right sentence. It would have been easier to reword the fourth site to
  match the other three; instead the anchor was narrowed to what is actually common and each
  site kept its own tail, which is what the lockstep mechanism is for.
- The tier line is reported with its own guard against being silently wrong, not just against
  being absent — the counts are checked against independently computed censuses, so a line that
  prints confidently false numbers fails.
- The prose-budget regeneration stayed surgical under a second round of pressure: five rows
  moved, five rows regenerated, and the three unrelated pre-existing failures still red.
