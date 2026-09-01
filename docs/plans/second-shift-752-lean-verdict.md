# lean review verdict — #752

verdict=needs-work
run_id: review-752-1
session_id: 898bec8d-6166-4c67-870f-45fa12fdbc23
rounds: 1
pr: #771
reviewed_head: 9dd4f33938b0aa9ccfcb23e3656752a6d55ad9f1
reviewed_patch_id: 9de555c3fdaa2e9ed195677e3d57a480d1020468
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review — #752 / PR #771, round 1

Range reviewed: `87bd913c..9dd4f339` (full branch diff — root round, nothing to inherit).
Reviewed from the PR head checkout at `9dd4f339`; head unchanged during the round.

## Verdict

`needs-work` — one blocker, on AC-6.

The engineering is sound and unusually well-evidenced: the diagnosis (round-robin shards balance
guard *count*, not cost; a guard's mutants are atomic to one residue class) is correct, the cap is
a real measurement rather than a round number, and the PR states the coverage it deletes instead of
hiding it. The blocker is not the decision — it is that the reason AC-6 requires the workflow to
record is factually wrong, and falsified by the two runs this ticket cites as its own evidence.

## Blocker

**B-1 — `.github/workflows/mutation-sweep.yml:280,288` — the recorded reason for declining OR-2's
narrowing is contradicted by the measured run history and by the file's own comment.** (AC-6,
confidence 95)

The edit makes two claims about a step-bound shard kill:

- line 280 (changed): "a shard that blows its **step bound**, or whose runner dies, resolves as
  `cancelled` and leaves `merge` `skipped`"
- line 288 (added): "a shard killed at its **step bound** still resolves `cancelled` at the **JOB**
  level and would still file"

Both are false. Measured from the two runs the spec's own timing table names:

| run | head | `sweep (6)` wall | `sweep (6)` conclusion | `merge` conclusion |
| --- | --- | --- | --- | --- |
| 33488186736 | `153188f5` | 45m18s (08:39:53→09:25:11) | **failure** | **failure** |
| 33425785614 | `a95919be` | 45m21s (18:34:45→19:20:06) | **failure** | **failure** |

A step-bound kill resolves `failure`, not `cancelled`, and leaves `merge` `failure`, not `skipped`.
This is not a matter of inference: the same file already says so, 150 lines above at line 128 —
"Blowing a JOB timeout cancels the job… Blowing a **STEP** timeout is an **ordinary step failure**,
under which the job unambiguously proceeds to its always() steps." The pre-edit wording was
correct: "blows its **60-minute** bound" named the *job* bound (`timeout-minutes: 60`, line 92),
which is the bound that does yield `cancelled`. The edit replaced a correct statement with an
incorrect one.

Why this blocks rather than being a nit: AC-6's deliverable *is* the recorded reason. As written it
tells the next reader that narrowing to `!cancelled()` would surrender step-bound detection. It
would not — a step-bound kill is already caught by the `failure` arm. The operator-cancelled run
(33425839962) has every `sweep` job `cancelled` and the run itself `cancelled`, so run-level
`!cancelled()` would suppress exactly it, while runner death (job `cancelled`, run not cancelled)
and the step bound (job `failure`) both still file. A future maintainer who trusts this comment will
decline a narrowing for a cost that does not exist.

**D-7 is not being re-litigated.** The operator resolved OR-2 as "leave the match broad" and that
decision stands; only its stated justification is defective. The remedy is a comment rewrite —
no behavior change, and it touches no line whose behavior this round assessed.

The hedge already in the comment ("inferred from GitHub's status-function docs, not measured")
covers the run-vs-job *status-function* semantics. It does not cover the step-bound→`cancelled`
claim, which is contradicted by this repo's own note and by run data that was already in hand.

## Warnings

**W-1 — `tools/mutation-sweep-selftest.sh:2793,2820,2827` — duplicate case labels `(l)`, `(l1)`,
`(l2)`.** (confidence 95) The suite already has `echo "(l) PR mode …"` at line 760 with `bad "(l1)"`
at 767 and `bad "(l2)"` at 777. Both `(l)` headings print in one run. Every other label in the file
(a–at, j, k) is unique, so this is new, not the surrounding pattern. This suite is the killer for
`tools/mutation-sweep.sh`, and case (g4) exists precisely to guarantee a red *names its failing
case* — an ambiguous id degrades exactly that. Suggest `(v2)`/`(au)` or similar.

**W-2 — `tools/mutation-sweep-selftest.sh:2818-2833` — the fixture cases assert the extractor, not
the red.** (confidence 85) `(l1)`/`(l2)` compare `catalog_cap_breaches`' stdout. The enforcement —
the `while read … lint_fail` loop at 2735-2739 that turns a breach into a `FAILS` increment — is
un-asserted. Delete that loop and both fixture cases still pass, the live tree is compliant by
construction so case (k) never reds, and the cap is silently unenforced. That is the same "goes
quietly dead" shape the block's own comment names; the fix covered the parsing half of it. AC-3's
stated rationale is parsing-scoped, so this does not fail the AC, but one more assertion on
`FAILS` (or on the `lint_fail` message) would close it.

**W-3 — `tools/mutation-sweep-selftest.sh:2666` and `docs/testing.md:1354` — the cap value `36` is
duplicated with nothing binding the copies.** (confidence 82) AC-4 requires the doc to state the
value, so the duplication is mandated; the repo has `LOCKSTEP-BEGIN`/`LOCKSTEP-END` markers
(`scripts/check-lockstep-pairs.sh`) for exactly this class and they were not used. Raising
`MAX_ROWS_PER_GUARD` later leaves `docs/testing.md` silently asserting 36.

## Suggestions

- `tools/mutation-sweep-selftest.sh:2735` — the cap loop calls `catalog_cap_breaches` on
  `tools/mutation-catalog.tsv` unconditionally, outside the `if [[ -f … ]]` guard the adjacent
  catalog lint uses. With the file absent, awk writes an error to stderr and the arm silently
  finds no breach. Inert today (the file always exists); one line to make consistent.

## Verified independently

- **The prune is exactly what the spec declares.** 56 → 36 rows for
  `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` (counted at base and head); the 20 removed
  ids are precisely the *Rows removed* table, no more and no less; `--numstat` on
  `tools/mutation-catalog.tsv` is `6 added / 20 removed`, and all 6 additions are the header
  comment block. No other row added, removed or edited.
- **All 97 surviving catalog rows still anchor.** Applied every row's `sed -E` (ERE — the sweep's
  dialect; a BRE probe false-reds 18 rows) against its guard: `anchored=97 drift=0 errors=0`.
  The cap is met by live rows, not by rows that had already gone dead.
- **The spec's two load-bearing measurements hold at this head.** `tools/mutation-baseline.tsv`
  carries 26 `catalog::` survivors and zero are `lean-gate.sh` rows — every retired row was killing
  something. No removed id is referenced by any lint, script or registry; the only references are
  in historical `*-lean-verdict.md` records, which nothing parses.
- **The cap arm is live on the PR lane.** `tools/mutation-sweep-selftest.sh` is not deferred
  (`.github/workflows/ci.yml:122` passes `--full`), and it is discovered by glob. Local cold run at
  `9dd4f339`: `[mutation-sweep-selftest] all cases passed`, including both new cap cases. CI agrees
  — `lint-and-selftests` and `selftests (macos, bash 3.2)` are SUCCESS at this head.
- **AC-6's "no behavior change" is real.** The only non-comment line in the workflow hunk is
  context; `file-audit-red`'s `if:` is byte-identical.
- **`mutation-sweep-pr` is SUCCESS** at this head. `pr-gates` is FAILURE for the single expected
  pre-approve reason — `no committed verdict record (a file named *-752-lean-verdict.md)` — which
  this record resolves. Not a blocker.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, and the repo's config carries no
`design` key, so no provider is configured and no render states are declared.

## Panel

`review-toolkit:scope-completeness-reviewer` returned `approve-with-nits` (one minor, confidence 92:
issue #752's body still lists "a run an operator cancels files nothing" as Expected Behavior 2,
never amended after the owner resolved OR-2 in a ticket comment — bookkeeping, and it fetched the
issue itself rather than taking the framing from dispatch). The scope gate passes.

The four collapsed dimensions (performance, complexity, maintainability, test coverage) plus
security were reviewed by the lead pass; W-1/W-2/W-3 and the suggestion are its findings.
`security-reviewer` was not selected — no auth/tenancy/session/upload/query surface in the diff and
no `review-context/security-reviewer.md` in the repo — and the lead pass found nothing: the
workflow hunk is comments only and the `permissions:` block is untouched. a11y and the
design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`).

## Suppressed (below threshold)

- `docs/plans/second-shift-752-lean.md:110` — Confidence 60 — the ground given for retiring
  `lean-gate-panel-token-anchors` ("no shipped reviewer name contains another's") is over-broad and
  false as stated: `plan-reviewer` is a substring of `unit-test-plan-reviewer`, `spec-reviewer` of
  `figma-faithful-spec-reviewer`. The retirement still holds on the narrower true fact — all three
  `panel_has` call sites (`lean-gate.sh:5144,5394`, `check-lean-chain.sh:973`) pass only
  `design_family_reviewer` output, and neither fidelity reviewer's name is contained in another's.
  Not raised: `lean-gate.sh:3195` already carries the same over-broad phrasing, so the spec
  inherited it rather than introducing it.
- `tools/mutation-sweep-selftest.sh:2668` — Confidence 55 — `catalog_cap_breaches`' `NF < 2` skip
  would also swallow a malformed one-field row rather than reporting it; the existing (k) shape
  lints cover row width separately.

## AC scorecard

| AC-n | score | evidence |
| ---- | ----- | -------- |
| AC-1 | satisfied | Counted at base and head: `lean-gate.sh` 56 → 36 rows, at the cap by construction. The 20 removed ids match the spec's *Rows removed* table exactly. `git diff --numstat -- tools/mutation-catalog.tsv` = 6/20; all 6 additions are the header block, so no other row is added, removed or edited. All 97 surviving rows re-verified to anchor (`sed -E`, drift=0, errors=0). |
| AC-2 | satisfied | `tools/mutation-sweep-selftest.sh:2735-2739` — case (k) emits `lint_fail "guard carries <n> catalog rows, over the per-guard cap of 36: <guard>"`, naming both guard and count, via `bad()` which increments `FAILS`. Silence at exactly 36 demonstrated by fixture case (l1). Suite green cold at `9dd4f339` and on CI `lint-and-selftests`. |
| AC-3 | satisfied | `tools/mutation-sweep-selftest.sh:2793-2833` — fixture catalogs at 36 and 37 rows for one guard plus a second guard under the cap, driving the same `catalog_cap_breaches` case (k) calls, not a copy. (l1) asserts silence at 36; (l2) asserts the exact breach line at 37 and that only the offender is named. Both pass. See W-2: the assertion stops at the extractor rather than the red, which AC-3's own parsing-scoped rationale does not require but which would close the arm end to end. |
| AC-4 | satisfied | `docs/testing.md:1354-1378` states the cap (`MAX_ROWS_PER_GUARD`), its value (36), its derivation (largest count for `lean-gate.sh` observed inside the 45-minute step bound, 24m25s at 54%), and explicitly that a row count is a proxy for `rows x killer-suite seconds` with the reason a cost-weighted cap fails open. |
| AC-5 | satisfied | `tools/mutation-catalog.tsv:39-44` states the cap by name and the obligation verbatim — "A guard already at the cap must RETIRE a row before it gains one" — and routes value/derivation to the selftest and reasoning to `docs/testing.md`. AC-5 requires the cap and the obligation, not the value (AC-4 owns the value), so the single-source-of-truth split satisfies it. |
| AC-6 | unsatisfied | Decision, accepted false digest and no-behavior-change are all recorded correctly (`file-audit-red`'s `if:` is byte-identical). The third mandated element — the reason the narrowing does not separate the two cases — is false. `.github/workflows/mutation-sweep.yml:280,288` assert a step-bound shard kill resolves `cancelled` at job level; measured, both step-bound kills resolved **failure** (`sweep (6)`: run 33488186736 / `153188f5`, 45m18s; run 33425785614 / `a95919be`, 45m21s), with `merge` **failure**, not `skipped`. The file's own line 128 already states it ("Blowing a STEP timeout is an ordinary step failure"), and the pre-edit "60-minute bound" correctly named the job bound. See B-1. |
