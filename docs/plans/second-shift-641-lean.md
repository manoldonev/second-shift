# #641 — the restraint half of the manifesto gets a mechanical counterpart

**Issue:** https://github.com/manoldonev/second-shift/issues/641
**Pre-flight receipt:** none — the design is ratified in the issue body and its three operator
comments (cited in the Decision Ledger below); there is no `.claude/pipeline-state/641-ledger.md`.
**Base:** `main` @ b8cc982
**Re-cut:** this issue was re-cut 2026-08-22 after PR #645 (an earlier, worse version of this
spec) was closed unmerged. Nothing from that PR is inherited except the two pieces named under
*Salvage* below, which are re-authored here rather than carried.

## Design

Design: none — this is shell/CI tooling with no rendered surface. `design.provider` is
unconfigured in this repo's `.claude/second-shift.config.json`.

## Intent

`docs/pipeline-manifesto.md`'s growth principles (P2/P3) are enforced mechanically; its restraint
principles (P4 "as much as it takes, and none more", P5 "every word earns its place") are not,
and the document says so in its own text. Guard/test shell mass grew 8x in five weeks
(6,296 -> 50,247 lines) while product shell grew 1.9x and has been shrinking since 2026-08-15.

**The mechanism is a derived comparison, never a stored ceiling.** `scripts/check-guard-budget.sh`
computes guard/test shell mass twice — once at `origin/<baseBranch>`, once at the PR's own tree —
and compares. Nothing is committed, so nothing can drift out of sync with what the tree actually
measures. The escape hatch for a genuine increase is a `Guard-mass: +<n> <reason>` commit trailer,
reusing the extracted-grep-anywhere mechanism `scripts/check-changelog-trailer.sh` already
establishes, rather than a file edit that needs its own update path.

**Five hand-maintained ratchet files retire alongside it** — 180 rows, every one a number a
command can produce in one call: two prose-budget baselines, three suite-timing tables that
independently drifted while recording the same measurement for overlapping suites, and one
known-red allowlist that emptied out and outlived its purpose.

## Scope

1. **`scripts/check-guard-budget.sh`** (+ same-stem selftest), wired into `pr-gates`. Classifies a
   `.sh` file as guard/test via the same predicate PR #645 established (kept behaviorally
   identical): `*-selftest.sh`, `check-*.sh`, `*-lint.sh`, `*/skills/*/lean-gate.sh`,
   `run-selftests.sh`, `mutation-sweep.sh`, `gate-ablation.sh`. Measures the current tree with
   `find` (matches CI's checked-out working copy) and the base ref via `git ls-tree` + `git show`
   (no second checkout). Escape hatch: a `Guard-mass:` commit trailer on the branch.

2. **Retire the five ratchet files:**
   - `.claude/prose-budget.baseline.tsv` and `.claude/prose-budget-shell.baseline.tsv` — both
     deleted. The shell half is subsumed by scope item 1 (shell mass now derives from the same
     comparison, not a separate comment-density baseline). The markdown half becomes a single
     derived total in the nightly `prose-budget` job's own output — no per-file baseline, no
     drift state. `prose-budget.sh` keeps its per-file `NEW`/warning behavior for narrative docs
     (that half is not a measurement register — see the new manifesto paragraph — it is a
     judgment about what counts as narrative bloat) but no longer persists or reads a committed
     shell-comment baseline. The shipped neutral stub at
     `plugins/dev-pipeline/tools/prose-budget.baseline.tsv` is untouched (a consumer template
     default, not a register).
   - `tools/selftest-slow-suites.tsv`, `tools/mutation-slow-suites.tsv`,
     `tools/selftest-sweep-baseline.tsv` collapse into one file,
     `tools/selftest-suite-timings.tsv`: one row per suite (`suite<TAB>seconds<TAB>measured_at`),
     union of the old pair with conflicting values resolved to a single row. The two threshold
     constants move out of table directives and into their consumers — `run-selftests.sh` /
     `check-sweep-bound.sh` at 9s (unchanged), `mutation-sweep.sh` at 5s (already there,
     unchanged) — as `# threshold-seconds` comment directives in the SAME file, one per
     consumer, so `check-sweep-bound.sh`'s existing directive-read pattern needs only a new
     default path and its own directive key. `check-sweep-bound.sh`'s aggregate ratchet
     (`baseline-seconds`/`allowance-percent`, previously `selftest-sweep-baseline.tsv`) moves into
     the same file as two more comment directives — same explicit-reviewed-commit re-baseline
     contract as before (#629 is unaffected in substance, only in which file its two numbers
     live). `mutation-sweep.sh`'s seed mode, which previously overwrote
     `mutation-slow-suites.tsv` wholesale from its own precheck timings, now **merges**: it
     replaces only the rows for suites it prechecked this run, leaving every other suite's row
     (including ones only `run-selftests.sh` defers, which mutation-sweep never measures)
     untouched. An overwrite would silently delete `tools/install-topology-selftest.sh`'s 584s
     row on the next mutation seed run — this is implementation-correctness, not a new design
     decision, so it carries no ledger row.
   - `tools/install-topology-known-red.tsv` and its read path in
     `tools/install-topology-selftest.sh` — deleted outright. The file currently carries 0 data
     rows (drained by #421); a suite listed nowhere is already the guard's "everything must
     pass" posture once the allowlist plumbing is gone.

3. **Two manifesto paragraphs** beside P4/P5 (Judgment aids, never gates — P5 forbids a lint that
   polices this file's wording): the asymmetry note (pointing at scope item 1's mechanism) and
   the register rule (a register's rows must be judgments, not measurements). `docs/testing.md`
   cross-references the register rule rather than restating it.

4. **`tools/gate-ablation-classes.tsv` gains an `earn_your_keep` column**, naming the regression
   class each decision point alone catches (salvaged wording from PR #645, re-authored).

### Salvage from PR #645

The manifesto paragraph and the `gate-ablation-classes.tsv` column are re-authored here from
scratch (the wording differs because the mechanism they describe changed from a stored ceiling to
a derived comparison); nothing else is carried forward.

### Explicitly NOT touched

The judgment registers, whose rows cannot be computed and whose deletion would cost real
coverage: `gate-ablation-adjudication.tsv`, `gate-ablation-classes.tsv` (gains a column, loses no
rows), `prose-blocker-triage.tsv`, `mutation-catalog.tsv`, `mutation-operators.tsv`,
`mutation-exclusions.tsv`, `mutation-pair-map.tsv`, `fail-open-sites.tsv`, `capability-parity.tsv`,
`review-harness-manifest.tsv`, `selftest-cache-inputs.tsv`, `mutation-baseline.tsv`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Mechanism for the guard-mass check | Derived comparison (base ref vs HEAD, computed fresh each run) — no committed ceiling. Ratified in the issue body, https://github.com/manoldonev/second-shift/issues/641 | ticket-sourced |
| D-2 | Escape hatch for a genuine guard-mass increase | A `Guard-mass: +<n> <reason>` commit trailer, reusing `check-changelog-trailer.sh`'s extracted-grep-anywhere mechanism — not a file edit. Ratified in the issue body, https://github.com/manoldonev/second-shift/issues/641 | ticket-sourced |
| D-3 | Whether the ratchet-file deletion lands in this slice or a follow-up | This slice — deferring it was PR #645's own review finding. Ratified in the issue body, https://github.com/manoldonev/second-shift/issues/641 | ticket-sourced |
| D-4 | Scope: add a new TSV, or replace the three existing ratchets that do a worse version of its job | Replace, not add — amended after the operator's "what is the goal of these endless rows of tsv" question, https://github.com/manoldonev/second-shift/issues/641#issuecomment-5380196852 | ticket-sourced |
| D-5 | Whether the register rule (state the asymmetry rule that would have prevented the 180 retired rows) belongs in this slice | Yes, beside P4/P5, as a second manifesto paragraph — approved as a scope addition, https://github.com/manoldonev/second-shift/issues/641#issuecomment-5380232575 | ticket-sourced |
| D-6 | One shared `# threshold-seconds` directive vs. one per consumer (scope item 2 said "its own directive key") | One shared key — `run-selftests.sh` and `check-sweep-bound.sh` bound the identical 9s quantity, and two same-valued keys reintroduce the drift this file exists to remove. See Build-time amendments. | codebase-derived |
| D-7 | AC-7 clause (a)'s row-count bar: hold 170, or correct it | Corrected to **168** — DEPARTURE from the filed AC-7. 170 was the operator's rounding of the 180 rows named in scope item 2 and omitted the 15-row unified timing table the same scope item mandates as their replacement; the spec's own derivation is 180 retired - 15 added - 3 net elsewhere = 168. Additional rows were explicitly NOT retired to reach 170 — round 2's B6 refuses that remedy by name. Amended in the issue body under *Operator amendment — AC-7 clause (a), 2026-08-22*, with a dated record at https://github.com/manoldonev/second-shift/issues/641#issuecomment-5382870407 | user-answered |

## Acceptance Criteria

- **AC-1** (oracle — selftest): `scripts/check-guard-budget.sh` derives mass at base and at HEAD
  and compares. Fixture cases: mass decreased -> pass; unchanged -> pass; increased with no
  `Guard-mass:` trailer -> fail naming the delta; increased with the trailer -> pass. **No case
  may assert `rc` alone** — each asserts the printed measured value, so a wrong number is
  distinguishable from a right one.
- **AC-2** (oracle — selftest): the classification predicate's negative case holds — a product
  `.sh` file added does not count toward guard mass — and each `classify()` arm is independently
  covered, such that neutering any one arm fails at least one case.
- **AC-3** (oracle — CI): the check runs in `pr-gates`, passes on this PR, and reds a synthetic
  guard-mass-increasing branch that carries no trailer. **The PR's own steps after it must not be
  `skipped`** — lean chain reconciliation has to run on this PR.
- **AC-4** (oracle — selftest): the five ratchet files of scope item 2 are gone; one timing table
  replaces the three, both consumers read it with their own threshold, and a suite that appeared
  in the old pair at conflicting values resolves to a single row.
- **AC-5** (oracle — selftest): `tools/install-topology-known-red.tsv` and its read paths are
  gone, and `tools/install-topology-selftest.sh` still passes.
- **AC-6** (oracle): `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  is green, and the nightly `prose-budget` job stays green.
- **AC-7** (proxy): committed TSV row count drops by at least **168** (amended 2026-08-22 by the
  operator — see D-7; the filed 170 omitted the 15-row unified timing table the same scope item
  mandates), and **net guard/test shell mass is lower than `origin/main` at merge** — this
  slice's own check, applied to itself, must pass without a `Guard-mass:` trailer.
- **AC-8** (critic): `docs/pipeline-manifesto.md` carries both paragraphs beside P4/P5 with no
  restatement elsewhere, and `docs/testing.md` links to the register rule rather than repeating it.
- **AC-9** (critic): `Changelog:` trailer.

Ratified at filing (operator, 2026-08-22): derived comparison rather than a stored ceiling;
trailer escape hatch rather than a file edit; the deletion half lands in this slice, not a
follow-up. AC-7 is the anti-regression: a slice about guard mass that increases guard mass has
failed regardless of its other ACs.

## Build-time amendments

- **AC-7 self-check**: `scripts/check-guard-budget.sh` applied to this branch's own diff against
  `origin/main` measures **`base 50308, HEAD 50282 (delta -26)`**, rc=0 — the new check plus its
  selftest (263 lines) are more than offset by deleting
  `plugins/dev-pipeline/tools/prose-budget-selftest.sh`'s now-dead baseline-ratchet cases
  (525 -> 269 lines) and `tools/install-topology-selftest.sh`'s known-red machinery
  (312 -> 260 lines), plus tightened comment density in the new/touched files themselves. No
  `Guard-mass:` trailer is carried, per AC-7's own text.
  Clause (a), measured the same way: committed `.tsv` data rows (non-comment, non-blank) go
  `origin/main` **615** -> HEAD **447** = **-168**, against the amended bar of 168. Per file:
  `-89` / `-65` prose-budget baselines, `-14` selftest-slow-suites, `-10` mutation-slow-suites,
  `-2` selftest-sweep-baseline, `-2` mutation-baseline, `-1` mutation-catalog, `+15` the unified
  `tools/selftest-suite-timings.tsv`. This bullet superseded a round-1 reading of `delta 0`,
  which round 2's B6 correctly called stale and flattering. The figure above is re-measured
  after the round-2 fix commit, whose W1 boundary rows cost 7 lines of the earlier -33.
- **prose-budget.sh's `--update-baseline`** is kept as an accepted no-op (prints and exits 0)
  rather than removed as an unknown flag, so a caller still wired to it (pipeline-doctor.sh's own
  remediation hints, referenced nowhere else) does not regress to a usage error.
- **A pre-existing, unrelated environment sensitivity was found and is NOT fixed here** (out of
  scope for a guard-mass slice): `operator-override-selftest.sh` (and likely the sibling
  attended/headless-checking lean-lane suites) false-reds when the sweep runs from inside a
  spawned `build-lean` session, because `orchestrate-lean.sh`'s `LEAN_ATTEND_MODE=headless` env
  var leaks into the suite's otherwise-isolated fixture subshells. Confirmed pre-existing (no file
  in this PR's diff is on that suite's call path) and confirmed environmental (scrubbing
  `LEAN_ATTEND_MODE`/`LEAN_RUN_MODEL`/`LEAN_SPAWN_PERMISSION_MODE` alongside the documented
  `CLAUDE_CODE_SESSION_ID` turns the same full sweep from 4 failures to 74/74 green). AC-6's
  `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh is green` is
  satisfied under that scrub.
- **D-6 — scope item 2's threshold directive is ONE shared key, not one per consumer** (departure,
  flagged undeclared in round 1 review, documented here rather than reverted). The scope text said
  "one per consumer… and its own directive key"; shipped a single `# threshold-seconds` directive
  in `tools/selftest-suite-timings.tsv`, read identically by `run-selftests.sh` and
  `check-sweep-bound.sh`. Both consumers bound the SAME quantity — milestone 3's local sweep and
  its nightly aggregate check both defer at 9s — and `check-sweep-bound.sh`'s header names the
  reason directly: "THE THRESHOLD HAS ONE HOME." Two independently-keyed directives holding the
  identical value is exactly the drift shape this file replaces three ratchet files to avoid — a
  hand-edit to one key with no obligation to touch the other. Reverting to two same-valued keys
  would reintroduce that drift risk to satisfy the letter of the scope text against its own intent.
  `mutation-sweep.sh`'s separate 5s bar is unaffected — it stays its own hardcoded consumer-side
  constant, per the scope text's own "already there, unchanged." Provenance: codebase-derived.
- **Round-1 review fixes** (PR #648, `run_id=review-641-pr648-1`, needs-work): (1) added a
  `tools/mutation-baseline.tsv` row for `pipeline-doctor.sh::detector::3726bf79a636` — the same
  accepted survivor as the deleted `fd42dbc00b25` row, re-keyed because #641 dropped `, sh n/a`
  from the grepped literal; (2) AC-2's classify_ref() arms were unguarded — `classify_worktree()`
  and `classify_ref()` were two separate implementations of the same predicate, not "the SAME case
  statement" the header claimed, and every existing fixture drove only the worktree side (a file
  added on the checked-out feature branch). Fixed at the root rather than adding a second,
  duplicate arm list to fixture: both functions now call one shared `is_guard_path()`, so a
  worktree-side arm fixture exercises the ref side's classification too, and there is nothing left
  to drift. What `classify_ref()` alone still owns — the git-ls-tree READ, not the classification —
  gets its own "ref-mechanism" case (a file present only at the base, absent on feature), because
  every AC-1 case reuses one path present on both sides and so cannot tell a broken ref-read from a
  correct one; (3) the `>= threshold` filter in both `run-selftests.sh` and `check-sweep-bound.sh`
  had no fixture row below its own threshold, so every existing case passed unchanged whether the
  filter deferred everything with a table row or nothing at all — added one boundary row to each
  suite's existing table fixture (folded into `run-selftests-selftest.sh`'s standing table rather
  than a separate case, since its assertions were already free to extend); (4) D-6 above; (5)
  AC-7's own net-negative requirement — see the updated AC-7 self-check bullet.
- **Round-2 review fixes** (PR #648, `run_id=review-641-pr648-2`, needs-work, one blocker):
  (1) **B6, clause (a)** — resolved by the operator amendment carried above as D-7, not by
  retiring rows. The bar is 168; the branch measures -168. Round 2's B6 named this as its
  option (i) and refused the alternative by name.
  (2) **B6, the stale record** — the AC-7 self-check bullet above now states the measurement it
  actually took (`delta -26`, and clause (a)'s 615 -> 447 = -168 with its per-file breakdown)
  instead of the superseded round-1 `delta 0`. The PR body is restated to match. This half of
  B6 stood on its own merits and was owed regardless of where the bar sat.
  (3) **W1** — `tools/check-sweep-bound-selftest.sh`'s `(a2)` case claimed an at-threshold
  boundary it did not construct: `table()` hardcodes every fixture row at 99s, so `at-selftest.sh`
  sat at 99s against a 10s bar and the case only ever distinguished clearly-under from
  clearly-over. Both boundary rows are now written by hand at the exact seconds the case is about
  (9s under, 10s at). The same gap existed in the other consumer —
  `tools/run-selftests-selftest.sh`'s table had rows at 147s and 8s against a 9s bar and none at
  9s — so `tools/quick-selftest.sh` is now tabled at exactly 9s there. Probed on an isolated
  worktree, one site at a time: `-ge` -> `-gt` at `check-sweep-bound.sh:109`, at
  `check-sweep-bound.sh:209`, and at `run-selftests.sh:221` each now reds its suite
  (1, 1, and 2 failures against green baselines); all three survived before this fix.
  (4) **W2 and W3 are carried forward unfixed**, as round 2 classified them: W2's non-numeric
  `die` in `check-sweep-bound.sh` remains unguarded on that side (the same arm is well covered in
  `run-selftests.sh`), and W3's four reflowed `scenario-liveness-selftest.sh` comments are named
  here rather than re-wrapped — four lines of the net-negative are reflow, not deletion, which is
  worth stating plainly in the PR that introduces a line-counting metric.
