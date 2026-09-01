# lean review verdict — #752

verdict=approve
run_id: review-752-2
session_id: a599b6a7-e8c7-4d58-9d52-dcb3913a6f82
rounds: 2
pr: #771
reviewed_head: 782cde4f396dc09c0279b496efd642008105bdf4
reviewed_patch_id: cec03495d738f164c551d9885bc777dcd8534f21
inherited_patch_id: 9de555c3fdaa2e9ed195677e3d57a480d1020468
inherited_from_verdict: 55dbebbad69cfee3fe112e06cdd2d9b1923d97da
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review — #752 / PR #771, round 2

Range reviewed: `55dbebba..782cde4f` (delta since the tree round 1 covered, patch `9de555c3fdaa`).
Read wider than the range where the delta was misleading: the whole `tools/mutation-catalog.tsv`
and the round-1 record's findings.
Reviewed from the PR head checkout at `782cde4f`; head unchanged during the round.

## Verdict

`approve` — no blockers. One warning, one suggestion, one scope nit.

Round 1's single blocker and all three warnings are closed, and three of the four closures were
verified by probe rather than by reading the fix. The corrected decision-of-record comment is now
true claim by claim against the job-level and run-level conclusions of the three runs it cites.

## Round-1 findings — closure

**B-1 (blocker, AC-6) — CLOSED.** Every factual claim in the rewritten comment
(`.github/workflows/mutation-sweep.yml:277-296`) verified independently via `gh run view <id>
--json jobs`:

| claim in the comment | measured |
| --- | --- |
| operator-cancelled run 33425839962 resolves `cancelled` at the RUN level | ✓ run-level `cancelled` |
| ...and every one of its `sweep` jobs does | ✓ all 10 `sweep` jobs `cancelled` |
| a step-bound kill resolves `failure` — runs 33488186736, 33425785614, `sweep (6)` ~45m | ✓ both `failure`; 45m18s and 45m21s |
| ...and leaves `merge` `failure` | ✓ both `failure` |
| "as the STEP-vs-JOB note above says" | ✓ `mutation-sweep.yml:124-128`, untouched |
| "No behavior change" | ✓ zero non-comment `+`/`-` lines in the file; `if:` byte-identical at line 301 |

The base-inherited clause round 1 did not flag — that a dead shard "leaves `merge` `skipped`" —
is gone too, and was equally false: `merge` is `if: always()` and resolved `failure` on all three
runs, the cancelled one included. Rewriting the sentence and keeping that clause would have
shipped the same defect class a second time.

The remaining lost-runner claim is correctly marked UNMEASURED rather than asserted, which is
what makes the recorded reason ("declined for what it RISKS") survive its own evidence standard.

**W-1 (duplicate case labels) — CLOSED.** `(au)`, `(au1)`–`(au4)` are unique in the suite; the
pre-existing `(l)`/`(l1)`/`(l2)` at lines 760/767/777 are untouched, and `docs/testing.md:1356`
was updated to name `(au)`. Verified by grep over the whole file, not the hunk.

**W-2 (fixtures assert the extractor, not the red) — CLOSED, and probed non-vacuous.** The
enforcing half is now `catalog_cap_lint()`, driven by `(au3)`/`(au4)`. Probed in an isolated
worktree at `782cde4f` by replacing the `lint_fail` call inside `catalog_cap_lint` with a no-op:

```
(au) per-guard catalog cap — case (k)'s cap arm, driven against a fixture catalog
  ok   a guard at exactly 36 rows draws no breach
  ok   one row over names the offending guard and its count, and only that guard
  FAIL (au3) expected one (k) FAIL naming tools/at-cap.sh; got delta=0
  ok   a catalog at the cap raises no failure and prints nothing
[mutation-sweep-selftest] 1 case(s) failed
```

`(au1)`/`(au2)` stay green under that mutant — exactly the hole round 1 named — and `(au3)` is
the case that closes it. The parent-shell `$FAILS` delta is the right instrument: a command
substitution is where the increment would not be observable.

**W-3 (unbound duplicate `36`) — CLOSED with the sanctioned mechanism, and drift-probed.** The
two copies now carry `LOCKSTEP-BEGIN mutation-catalog-per-guard-cap`, which is what
`writing-tests` prescribes in place of a prose-presence guard. Live tree:
`PASS: mutation-catalog-per-guard-cap (verbatim): docs/testing.md tools/mutation-sweep-selftest.sh
agree` (30 anchors, 0 failed). Probed in an isolated copy with the doc's value changed to 37:
`FAIL: mutation-catalog-per-guard-cap (verbatim): docs/testing.md and
tools/mutation-sweep-selftest.sh have DRIFTED`. CI runs the checker at `.github/workflows/ci.yml:144`.

**Suggestion (cap loop outside the `-f` guard) — CLOSED.** `catalog_cap_lint` is now called
inside `if [[ -f "$REPO_ROOT/tools/mutation-catalog.tsv" ]]`, with the reason recorded at the
call site.

## Warnings

**W-1 — `tools/mutation-sweep-selftest.sh:2688` — the new comment describing the new cases
states the opposite of what they do, and the same file says so 160 lines below.** (confidence 95)

> `# and never enforced. Case (au3)/(au4) drive it and read $FAILS in a subshell.`

They do not. Both cases run `catalog_cap_lint` in the current shell with stdout redirected to a
file, and read the `$FAILS` delta in the parent — which the comment at lines 2851-2853 states
explicitly and gives the reason for: *"Run in THIS shell rather than a command substitution,
because a subshell is exactly where a `$FAILS` increment would not be observable."* Both comments
were added in the same commit.

This is the same defect class as this round's own blocker — a claim its own file contradicts —
and it is worth naming as that rather than as a typo. It is a warning and not a blocker on two
grounds, and only those two: no AC makes this comment a deliverable (AC-6 made the workflow
comment one, which is what made B-1 a blocker), and a maintainer who acts on it reds loudly
rather than silently — moving the call into a command substitution yields `delta=0` and `(au3)`
fails by name. Fix is one clause: *"…drive it and read the `$FAILS` delta in this shell."*

## Suggestions

- `tools/mutation-sweep-selftest.sh:2663` — the comment "36 is a MEASUREMENT — the largest count
  for that guard observed to finish inside the bound" restates the cap value three lines above
  the `LOCKSTEP` block that now binds the other two copies, so it is the one copy nothing holds.
  Raising `MAX_ROWS_PER_GUARD` touches three sites, two of them enforced. `docs/testing.md` was
  de-duplicated in exactly the right way this round ("**It** is a measurement rather than a
  preference"); the same edit applies here. Adjacency to the declaration is what keeps this a
  suggestion rather than a repeat of W-3.

## Verified independently

- **The catalog is byte-identical to round 1's reviewed head.** `git diff 9dd4f339..HEAD --
  tools/mutation-catalog.tsv` is empty, so round 1's anchoring verification (all 97 surviving
  rows applied, `drift=0 errors=0`) transfers by content rather than by assertion. Re-counted at
  this head: 36 rows for `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, at the cap.
- **The suite is green cold at this head**, including all four cap cases:
  `[mutation-sweep-selftest] all cases passed`. Run without a cache dir, from the PR head
  checkout — milestone 3's bounded lane defers this 135s suite, so it is not covered by the
  build's own green.
- **`shellcheck -e SC1091,SC2015,SC2181` is clean** on the changed suite (0.11.0 locally). The
  parent-shell `$FAILS` idiom is the shape that passes; the obvious command-substitution one
  emits SC2030/SC2031.
- **No mutation-catalog obligation is owed by this delta.** The sweep's universe excludes
  `*-selftest.sh`, and no catalog row names `tools/mutation-sweep-selftest.sh` as a guard, so
  editing it re-anchors nothing.
- **Correctness CI is green at `782cde4f`** — `lint-and-selftests` SUCCESS, `selftests (macos,
  bash 3.2)` SUCCESS, `mutation-sweep-pr` SUCCESS.
- **The PR body's net-diff figures are accurate to the digit.** Re-measured:
  `git diff --numstat 87bd913c..HEAD -- . ':!docs/plans/'` = 171 added / 23 removed / **+148
  lines**; content bytes 9,783 added / 12,378 removed / **−2,595**. The operator's ratification
  comment (2026-09-01T12:17:47Z, OWNER) recorded the #717 net-diff clause as an explicit
  override whose obligation transferred as "land a net-negative diff, **or come back stating why
  none exists**". The PR body does the latter, reports both metrics rather than the flattering
  one, and attributes the round-2 growth to the fixes this review demanded. Discharged.

## The AC-6 amendment

Raised explicitly, because a spec amended after the fact to match the diff is a blocker and this
is an amendment the build session made to its own spec. Scored legitimate:

- The superseded clause — "the reason the obvious narrowing **does not separate the two cases**"
  — presupposed a proposition round 1 measured false. The narrowing *does* separate them. No true
  statement could have satisfied AC-6 as written.
- The amendment is disclosed in the spec with the superseded text quoted verbatim and the
  falsification named, not silently rewritten.
- It preserves the deliverable in kind: a recorded reason, now obliged to be a true one. The
  reason actually recorded is more evidenced than the bar asked for.
- The operator decision it encodes (D-7, `user-answered`: leave the match broad) is untouched;
  only its supporting reasoning moved. That is the same shape as D-5's `CORRECTED here:`
  precedent already in this ledger.

This is the narrowest amendment that makes AC-6 satisfiable, not one shaped to fit the diff.

## Merge-boundary refusal, recorded not blocking

`pr-gates` is FAILURE at this head for the single expected pre-approve reason —
`verdict record 'docs/plans/second-shift-752-lean-verdict.md' reads 'verdict=needs-work', not
'verdict=approve'` — which this record resolves. No policy gate (`Changelog:` trailer, frozen
files) is red.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, and the repo's config carries no
`design` key, so no provider is configured and no render states are declared.

## Panel

`review-toolkit:scope-completeness-reviewer` returned `approve-with-nits`. Its one minor
(confidence 88) is round 1's nit unchanged: issue #752's `## Expected Behavior` item 2 still
reads "A run an operator cancels files nothing", never amended after the owner resolved OR-2 in
a ticket comment. It confirmed the deferral is real and operator-authored, and that the yml diff
is comments-only. No code remedy exists and amending a ticket's acceptance criteria is a
human-authority action, so this is carried as a nit rather than a scope failure. The gate passes.

The four collapsed dimensions (performance, complexity, maintainability, test coverage) plus
security were the lead pass's; the warning and the suggestion above are its findings.
`security-reviewer` was not selected — the workflow hunk is comments-only, `permissions:` is
untouched, no auth/tenancy/session/upload/query surface is in the delta, and the repo carries no
`review-context/security-reviewer.md` — so the lead pass owned the security dimension and found
nothing. a11y and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`).

## Suppressed (below threshold)

- `tools/mutation-sweep-selftest.sh:2686` — Confidence 65 — "split out for the same reason and
  not the same reason twice" reads as a slip for "for the same reason, and not for the same
  reason twice"; the two halves are in fact split for two different reasons (testability of the
  parse vs testability of the red), which is what the sentence is trying to say.
- `docs/plans/second-shift-752-lean.md:110` — Confidence 60 — carried from round 1: the ground
  given for retiring `lean-gate-panel-token-anchors` is over-broad as stated. Inherited from
  `lean-gate.sh:3195`, unchanged this round.

## AC scorecard

| AC-n | score | evidence |
| ---- | ----- | -------- |
| AC-1 | satisfied | Inherited by content, not by reference: `git diff 9dd4f339..HEAD -- tools/mutation-catalog.tsv` is empty, so round 1's per-row anchoring verification (97 rows applied with `sed -E`, `drift=0 errors=0`) holds at this head unchanged. Re-counted here: 36 rows for `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, exactly at the cap; branch `--numstat` on the file is 6 added / 20 removed, the 6 being the header block. |
| AC-2 | satisfied | `tools/mutation-sweep-selftest.sh:2691-2697` — `catalog_cap_lint` emits `lint_fail "guard carries $cap_n catalog rows, over the per-guard cap of 36: $cap_g"`, naming both guard and count, through `bad()` which increments `FAILS`. Silence at exactly 36 asserted by `(au1)` (extractor) and `(au4)` (no failure, no output). Suite green cold at `782cde4f`; CI `lint-and-selftests` and `selftests (macos, bash 3.2)` both SUCCESS at this head. |
| AC-3 | satisfied | `tools/mutation-sweep-selftest.sh:2808-2874` — fixtures at 36 and 37 rows for one guard plus a second guard under the cap, driving the same `catalog_cap_breaches` AND the same `catalog_cap_lint` that case (k) calls, not copies. Round 1's gap is closed and probed: with the `lint_fail` call inside `catalog_cap_lint` replaced by a no-op, `(au1)`/`(au2)` stay green and `(au3)` reds `delta=0` — `[mutation-sweep-selftest] 1 case(s) failed`. |
| AC-4 | satisfied | `docs/testing.md:1354-1382` states the cap by name (`MAX_ROWS_PER_GUARD`), its value in a `LOCKSTEP`-bound block, its derivation (largest count for `lean-gate.sh` observed inside the 45-minute step bound, 24m25s at 54%), and that a row count is a proxy for `rows x killer-suite seconds` with the reason a cost-weighted cap would fail open. The pair is live (`30 anchor(s) checked, 0 failed`) and drift-probed (doc value 36 to 37 yields `DRIFTED`); CI runs the checker at `.github/workflows/ci.yml:144`. |
| AC-5 | satisfied | `tools/mutation-catalog.tsv:39-44` states the cap by name and the obligation verbatim — "A guard already at the cap must RETIRE a row before it gains one" — routing value and derivation to the selftest and the reasoning to `docs/testing.md`. Unchanged this round; re-read at head, carries no stale value. |
| AC-6 | satisfied | `.github/workflows/mutation-sweep.yml:277-296` records the decision (broad match stays), the accepted false digest, and a reason verified true claim by claim: run 33425839962 is `cancelled` at the RUN level with all ten `sweep` jobs `cancelled`; runs 33488186736 and 33425785614 resolved `sweep (6)` `failure` at 45m18s/45m21s with `merge` `failure`; the STEP-vs-JOB note at lines 124-128 says the same and is untouched. "No behavior change" holds — zero non-comment diff lines, `if:` byte-identical at line 301. The AC's own amendment this round is scored legitimate; grounds under "The AC-6 amendment" above. |
