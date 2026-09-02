# lean review verdict — #564

verdict=approve
run_id: review-564-1
session_id: 8cca89e2-3488-4c61-ba4b-ef91b90e99bd
rounds: 1
pr: #781
reviewed_head: 64d948f1d73f7aca5b24f16cb19ef6b764727d9a
reviewed_patch_id: 27a87d055b7e9e9d90384a42d2d4835605cdc641
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — #564 / PR #781

**Verdict: approve.** No blockers. Range `d8ea88aa..64d948f1` (root round, full branch diff:
4 files, all Markdown, no executable surface).

## Review Summary

A docs-only slice delivering a pre-registered two-lane concurrency exercise, its evidence record,
and a re-runnable operator procedure. The round re-derived the record's load-bearing factual
claims from the tree rather than taking them, and every one held. The record's central discipline
— the bar was fixed in a commit that contains no measurement, and it did not move afterwards — is
verifiable from the commit graph, not merely asserted.

Panel: `review-toolkit:scope-completeness-reviewer` (returned `approve-with-nits`). The four
collapsed dimensions and security were reviewed by the lead pass in-session. `security-reviewer`
not selected: a prose-only diff carries no security surface and the repo has no
`review-context/security-reviewer.md`; the lead pass owned the dimension. a11y + design-fidelity
not routed: no changed path matched `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`). The spec has no `## Design` section, so it is unarmed and
`--fidelity not-applicable` is the correct value, not a skipped check.

## What was independently verified

Every claim below was re-derived from the tree at the reviewed head, not read off the record:

- **"Discovers 78, excludes 14, runs 64."** 78 `*-selftest.sh` files discovered.
  `tools/selftest-suite-timings.tsv` carries 15 rows and a `# threshold-seconds 9` directive;
  `exitplan-ledger-gate-selftest.sh` (5s) falls below it, leaving 14 deferred. `install-topology`
  is inside that 14 and is also the lane's `--exclude`, so the union is 14. 78 − 14 = 64. Exact.
- **"The two deferred fixture producers are the only ones."** `tools/fixture-stamp.sh` has exactly
  two non-test consumers — `lean-gate-selftest.sh` (212s) and `orchestrate-lean-selftest.sh` (28s)
  — and `tools/reap-lean-fixtures.sh:133` walks exactly those two prefixes. Both are deferred.
  C-1 is therefore genuinely unreachable through a milestone-3 lane, as the record says.
- **"Two of three cacheable suites are deferred."** `tools/selftest-cache-inputs.tsv` names three
  distinct suites; `lean-gate-selftest.sh` (212s) and `check-lean-chain-selftest.sh` (67s) defer,
  leaving `cost-block-selftest.sh` as the single cacheable suite. Arm 3's `63 run, 1 served`
  reconciles to 64.
- **Every line citation resolves.** `run-selftests.sh:240` (entry reap), `:94`
  (`JOBS="${SELFTEST_JOBS:-4}"`), `:492-517` (`cache_hit` fail-safe / `cache_put` temp-then-`mv -f`);
  `lean-gate.sh:1952-1975` (`lane_apply_selftest_cache`), `:1962` and `:4828` (both cite the #566
  ceiling deletion), `:461` (`lane-registry` surviving only as a `--ticket-source` label),
  `:3684` (`SEAM_SCRUB` contains `LEAN_ATTEND_MODE` and does **not** contain `LEAN_RUN_MODEL` —
  the record's SO-1 claim is exactly right). `docs/testing.md:1799` is
  `## Adversarial tier (operator-run, never CI)`, so D-9's shape precedent and AC-8's sibling
  requirement both check out against line numbers unmoved by this diff.
- **The ordering is real, not claimed.** `c122830b` (13:22) lands the pre-registration and the
  spec and contains no evidence file. `0a08d2fe` (13:33) adds only the baseline section and fixes
  the 86.12 s bar; it carries no two-lane number. `64d948f1` (13:58) lands the arms. The bar
  provably predates the data.
- **The arithmetic.** 1.5 × 57.41 = 86.12; 76.36/57.41 = 1.330 and 76.23/57.41 = 1.328; margin
  9.75 s ("~9.8 s"); CPU/wall 2.67 (B8-1) and 2.16 (arm 2 A); SO-2 at 1.23× / 1.22× of the
  285.65 s control. All reproduce.
- **The progress-record counts were true when written.** `.claude/pipeline-state/564-lean-progress.md`
  now holds 23 `milestone-3` rows; 21 of them predate the record's authoring time (10:58Z), the
  remaining two coming from a later gate invocation at 10:59–11:00Z. "7 under 291" reconciles
  exactly to lane B's three arm invocations (3 × started/concluded + one `satisfied`).
- **The struck criterion is ratified, not waved away.** The issue body heads its criteria
  `## Shape (spec work to settle)` and says "Decide at intake"; the pre-flight ledger
  `.claude/pipeline-state/564-ledger.md` records D-1 (the re-aim) as `user-answered` / `intent`
  and D-10 (the strike) as `codebase-derived` / `fact`. The spec transcribes both verbatim.
- **The spec was not amended to fit the diff.** `docs/plans/second-shift-564-lean.md` has been
  untouched since `c122830b`, the slice's first commit.
- **#780 is filed, open, and accurate** — its own account of the defer mechanics matches what this
  round measured independently.

## Strengths

- **The pre-registration is falsifiable by construction.** Arm 1 is explicitly denied a bar
  because two as-shipped lanes are under-subscribed and would clear any envelope by arithmetic;
  the bar lives only on arm 2, "the only arm on which #566's claim can be false". C-3 additionally
  pre-commits the escape hatch it must *not* take — if the baselines showed CPU saturation, the
  criterion was to be scored FAIL-uninformative rather than claimed as a finding. The record then
  publishes CPU alongside wall time (2.69 cores of 10) so a reader can check that condition rather
  than trust it.
- **The void attempt is recorded rather than discarded.** SO-1 produced four identical red suites
  in both lanes — the exact shape of a contention finding — and the record isolates it to
  `LEAN_ATTEND_MODE` reaching the suites through a bare `run-selftests.sh` invocation that bypassed
  `SEAM_SCRUB`, settles it with a single-lane control, and writes the lesson into the operator
  procedure. Suppressing it would have been invisible; publishing it is what stops the next
  operator paying for it.
- **The reaper lesson is a genuine methodological find.** "Simultaneous launch is the wrong shape"
  — the reaper runs on sweep *entry*, so two lanes started together both walk an empty directory
  and the ownership guard is never asked a question. That is why the pre-registered arms could not
  score C-1, and the staggered SO-2 observation that fixes it is clearly fenced off as
  supplementary rather than smuggled in as a pre-registered pass.
- **The record's self-limitation is unusually honest.** It states that every exercised criterion
  passed and that "a green from an instrument never seen to go red is weaker evidence than a green
  from one that has" — a caveat nothing obliged it to write.

## Warnings (should fix — none blocking)

- **[Maintainability] `docs/plans/second-shift-564-evidence.md` (Scores table) — the score of
  record for C-2 is stated two ways.** The table reads "**PASS on the letter**, NOT EXERCISED in
  substance"; the paragraph immediately below it reads "C-1 and C-2 are reported as unreachable
  through the pre-registered lane unit rather than as passes", and the PR body says "C-1 and C-2 —
  VACUOUS, not passed". C-2's table cell says PASS and the two prose statements say not-a-pass. A
  future reader cannot tell which is the score. One wording, either way, would settle it.
- **[Maintainability] `docs/plans/second-shift-564-evidence.md` ("Host and trees") — the stamped
  lane-A SHA is the baseline tree, not the arm tree.** The table records lane A @ `c122830b`, and
  that is correct for the baselines, which ran between 13:22 and 13:33. The arms ran after
  `0a08d2fe` was committed at 13:33, so lane A's tree during arms 1–3 was `0a08d2fe`; the
  "When this record goes stale" stamp gives lane A no SHA at all. **Measured inert:**
  `git diff --name-only c122830b 0a08d2fe` names one path,
  `docs/plans/second-shift-564-evidence.md`, so the executable content is byte-identical, ordering
  rule 3 still holds against lane B, and C-4's verdict-equality oracle is unaffected. Every use
  the record puts the SHA to survives; only the stamp's literal accuracy does not.
- **[Maintainability] "neighbour" in the Scores table** — British spelling, against the repo's US
  English convention. The pre-registration spells it "neighbor" three lines away.

## Suggestions (consider)

- **[Maintainability] The progress-record location is given as a rule, not a path.** AC-5 asks for
  "the progress-record path it was written to"; the record gives the directory
  (`.claude/pipeline-state/`), the issue-keyed naming rule, and the row counts. The path resolves
  (`.claude/pipeline-state/564-lean-progress.md` — confirmed on this host), so the item is
  satisfied, but a literal path would cost one clause. `scope-completeness-reviewer` raised the
  same point independently and reached the same conclusion.

## Notes carried, not findings

- **[Scope completeness]** `scope-completeness-reviewer` flagged (minor, confidence 92) that the
  issue body's first criterion is struck with no deferral language in the body itself. Resolved
  against the pre-flight ledger, which the body's own "Decide at intake" defers to: D-1 is
  `user-answered`, so the re-aim is a human decision, and D-10 is `codebase-derived` with three
  in-tree citations this round re-verified. Not a blocker; a one-line ratification comment on #564
  would close it on the tracker as well as in the ledger.
- **[Merge boundary, recorded not blocking]** `pr-gates` is red on
  "lean chain reconciliation (lean PRs carry their evidence set)". That is the expected
  pre-approval state — the evidence set is incomplete until this record is pushed — and it is a
  policy gate, not a correctness lane. `mutation-sweep-pr` is green; `lint-and-selftests` and
  `selftests (macos, bash 3.2)` were still running at review time and carry no executable diff to
  regress. No `Changelog:` obligation: the diff touches no `plugins/**` path.
- **Rounding nit, immaterial:** 1.5 × 57.41 = 86.115, recorded as 86.12 (half-up). Both lanes
  clear by ~9.8 s, so the third significant digit decides nothing.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `c122830b` is the slice's first commit; it lands `docs/plans/second-shift-564-preregistration.md` and `-lean.md` only — no evidence file, no measurement data. Lane A's trees at measurement time were `c122830b` (baselines) and `0a08d2fe` (arms), both at-or-descended-from it. Lane B's tree is `d8ea88aa`, not a descendant — but requiring it to be one contradicts D-3 and ordering rule 3, which put the two lanes on separate branches with byte-identical executable content; lane B is apparatus, not the tree under measurement. The temporal ordering AC-1 exists to fix is verified from the commit graph: 13:22 (bar) < 13:33 (baselines) < 13:58 (arms). |
| AC-2 | satisfied | Exactly four criteria, C-1 through C-4, one per D-11 surface (fixture-reaper ownership, shared pass-cache store, per-lane wall-clock) plus terminal-and-correct verdict. The strike is recorded in the pre-registration's opening section and names #566 as the deletion that voided it, citing `lean-gate.sh:1962`, `:4828` and `tools/run-selftests-selftest.sh:191` — all three re-verified in the tree this round, along with `lean-gate.sh:461` as the only surviving `lane-registry` mention. |
| AC-3 | satisfied | C-3 is stated as a rule: "each lane's arm-2 wall-clock ≤ 1.5 × the slowest of the three B8 baseline samples", with the arm's job count defined as `ceil(cores × 0.8)` and `cores` resolved by `sysctl -n hw.ncpu` / `nproc`. The arm table marks arm 1 (as-shipped) "**no.** Recorded descriptively" in its "Carries a bar?" column, and the text gives the reason — two as-shipped lanes are under-subscribed, so any envelope is met by arithmetic. |
| AC-4 | satisfied | Four B4 samples and three B8 samples, all single-lane, committed in `0a08d2fe` at 13:33. That commit's diff adds only the baseline section and the derived 86.12 s bar; it contains no two-lane measurement. The arms landed 25 minutes later in `64d948f1`. Both measured job levels clear the "at least three" floor. |
| AC-5 | satisfied | Per measured run: load mean/max (host 1-minute average, 2s sampling, disclosed as including the build session and sampler); wall, user and sys time plus a derived CPU/wall column; sweep verdict (`64 run, 0 failed`, rc, and the milestone-3 concluded rc=0 row). Tree SHAs for both lanes, host `hw.ncpu` = 10, and the date 2026-09-02 are stamped. Two fidelity gaps, both carried as warnings above rather than as failures: the progress record is located by rule (`.claude/pipeline-state/`, issue-keyed) rather than by literal path — the rule resolves, confirmed on this host — and the stamped lane-A SHA is the baseline tree while the arms ran one docs-only commit later. |
| AC-6 | divergent-inert | C-2, C-3 and C-4 carry PASS. C-1 carries "VACUOUS — not exercised" rather than a PASS/FAIL token. **measured:** scored against C-1's committed wording, both prongs hold vacuously — zero `[reap-lean-fixtures] removed:` lines across all ten runs makes prong (i)'s universal quantifier true, and neither fixture-producing suite ran, so prong (ii) is true — meaning the letter yields PASS and the record declines it. The substitution is strictly conservative (it refuses a green the wording grants, never softens a red), it follows the pre-registration's own doctrine that "a criterion that cannot be failed is a vacuous green" and its C-3 precedent of a qualified "FAIL-uninformative" score, and the round independently confirmed the unreachability is real (both fixture producers deferred at the 9s threshold). There are zero FAILs, so the "FAIL as a FAIL without re-scoping" and "cites a filed follow-up for each FAIL" clauses hold vacuously, and #780 is filed and cited regardless. **follow-up:** #780. |
| AC-7 | satisfied | A dedicated "What this does NOT prove" section states in the record's own words that no scheduler- or session-level contention is covered, that a lane here is a `lean-gate.sh 3` invocation rather than a `run-lean` session, and that this is the shape which produced #525's motivating pain. It adds two limits AC-7 did not require: nothing beyond this host, and nothing about the instrument's ability to detect a red. |
| AC-8 | satisfied | `## Concurrent-lane tier (operator-run, never CI)` at `docs/testing.md:1832`, a true top-level sibling of `## Adversarial tier (operator-run, never CI)` at `:1799` (verified unmoved by this diff). It carries the seven-step re-runnable procedure — including the sampler script, the stagger requirement, and the seam-scrub warning — and a "When to run it" paragraph naming the same three void triggers the record stamps. |

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 2 | 85–92 |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ❌ | 3 | 80–90 |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** Yes.

**Reasoning:** No blocker in any dimension. The three maintainability findings are wording and
stamp-accuracy issues inside a docs-only diff; each was measured to be inert against every use the
record puts the affected value to, and none changes a number, a score, or a conclusion. The
slice's one irreversible property — that the bar was fixed before the data existed — is proved by
the commit graph rather than asserted, and the record's central factual claims were re-derived
from the tree and hold exactly.
