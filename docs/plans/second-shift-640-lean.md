# #640 — An approve may not stand at zero CI, and the response spends no round

A reviewer may not record `verdict=approve` when the PR's head was never evaluated by CI, observed as
the absence of `refs/pull/<n>/merge` on the remote. The observation is stamped into the verdict
record as `ci_state:`, the merge boundary refuses an approve carrying a non-`evaluated` value, and the
scheduler stops a zero-CI lane AHEAD of the REVIEW spawn so no round and no review session is spent.

## The mechanism, and what it cannot see

`git ls-remote <remote> refs/pull/<n>/head refs/pull/<n>/merge` gives three outcomes:

| Read | `ci_state` |
| --- | --- |
| both refs listed | `evaluated` |
| head listed, merge absent (after a short bounded re-read — GitHub creates the merge ref asynchronously after a push) | `never-evaluated` |
| the listing fails, or lists no head ref (the remote does not serve this PR's refs, so absence proves nothing) | `unknown` |

It distinguishes merge-ref-present from merge-ref-absent. It does not distinguish red from green and
the lane does not claim to.

## Acceptance criteria

- **AC-1** — `milestone-gate.sh verdict --verdict approve` is refused when the PR's merge ref is
  absent. The refusal names the state it saw (`never-evaluated`) and says red vs green is not read.
- **AC-2** — The writer stamps `ci_state: <evaluated|never-evaluated|unknown>` as a header key,
  emitted unconditionally, and the key joins `LANE_VERDICT_HEADER_KEYS`. `boundary-evidence.sh`'s
  `arm_verdict` refuses an `approve` whose header-anchored `ci_state` is `never-evaluated`,
  `unknown`, or any value outside the enum.
- **AC-3** — A record with no `ci_state` key passes that arm exactly as today (the
  `reviewed_patch_id` precedent). The fail-open carries its row in `scripts/fail-open-sites.tsv`
  under a new `by-design` disposition, which `check-fail-open-shapes.sh` accepts with `converted`'s
  rules: the anchor must resolve, and must not cover a live `| grep -q` site.
- **AC-4** — Milestone 4 invoked with `--pr <n>` and no verdict record checks the merge ref and
  returns a new class **12** on `never-evaluated`. `orchestrate.sh`'s `verdict_rc` passes `--pr`,
  and the pre-spawn chain routes 12 to a new terminal `ci-never-evaluated` beside rc 3 and rc 2, so no
  REVIEW is spawned and no round is counted. `orchestrate-selftest.sh` asserts no REVIEW spawn, no
  BUILD re-spawn and no round line on that path.
- **AC-5** — `needs-work` writes at `never-evaluated` and stamps it. The selftest drives both arms,
  approve refused and needs-work written, so the rule is not "no verdict at zero CI".
- **AC-6** — An unreadable read is `unknown`, never either state. The writer refuses `approve` at
  `unknown` as an environment error (rc 2) naming the state (D-2); `needs-work` writes and stamps it.
  Milestone 4 with `--pr` returns 2 on `unknown`, which the scheduler already routes ahead of the
  spawn to `verdict-gate-unreadable` (D-3).
- **AC-7** — The read goes through a declared seam in the gate's seam list: `LANE_PR_REMOTE` (the
  remote listed, default `origin`) plus `MERGE_REF_TRIES` / `MERGE_REF_BACKOFF` for the re-read. The
  selftests point the remote at a local bare repository and stay offline. Without `--pr`, milestone
  4 makes no network read, so `all`'s pre-pass keeps its no-network property.
- **AC-8** — The rule is stated once, in the gate. `review/SKILL.md` gains only the instruction the
  reviewer needs: don't write approve when the writer reports `never-evaluated`, and stop rather than
  re-run.
- **AC-9** — Registers paid: a `tools/gate-ablation-classes.tsv` row `m4/ci-never-evaluated` keyed on
  milestone 4 (D-6), the AC-3 fail-open row, `scripts/gate-buckets.tsv` rows for each new refusal site
  (`gates-signal` — OR-3: no operator override), `tools/lane-bench-classes.tsv` for the new terminal,
  and `scenario-liveness-selftest.sh` extended with a non-vacuity case: the same branch whose approve
  reaches milestone 4 with an evaluated merge ref is refused, and writes no record, with the ref
  removed.

## Open regions

All three carry the receipt's defaults unchanged. **OR-1** hand-back: the scheduler stops
`ci-never-evaluated`; the operator re-launches once CI has run. **OR-2** yes: the writer refusal fires
in a hand-run review. **OR-3** no override.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the zero-CI stop happens when the scheduler drives | Both layers. (a) Milestone 4's observe read (`verdict_rc`, `orchestrate.sh:1356`) checks for the merge ref ahead of the REVIEW spawn and returns a NEW rc with its own terminal token, routed in the pre-spawn `if/elif` chain beside rc 3 and rc 2 (`orchestrate.sh:1555-1575`), so no REVIEW session is spawned and no round is spent. (b) The `cmd_verdict` writer refusal of AC-1 stays, covering hand-run reviews (OR-2) and a ref that vanishes between the two reads. Accepted cost: in scheduler runs AC-5's needs-work-at-zero-CI is reachable only by a hand-run review; #597 r1's hand-checks missed the defect CI later found, so little is lost. | user-answered |
| D-2 | Writer disposition when the merge-ref read is UNKNOWN (AC-6) | `approve` is refused as an environment error (rc 2, no fix budget), and the message names the UNKNOWN state. `needs-work` still writes and stamps the key's unknown value. The merge boundary refuses `approve` carrying either never-evaluated or unknown; the writer should make approve+unknown unreachable, and the boundary refusal is defense against a hand-edited record. | user-answered |
| D-3 | Pre-spawn read UNKNOWN (the D-1 (a) layer) | Routed to the existing rc 2 `verdict-gate-unreadable` stop ahead of the spawn: an environment refusal, not a verdict, and no REVIEW is spawned on a guess. Same reason as rc 2's current pre-spawn arm. | codebase-derived |
| D-4 | Stale names in the issue body (filed 2026-08-22, before the lean→lane rename) | Read as: `lean-gate.sh` → `plugins/dev-pipeline/skills/build/milestone-gate.sh`; `LEAN_VERDICT_HEADER_KEYS` → `LANE_VERDICT_HEADER_KEYS` (`milestone-gate.sh:4009`); `check-lean-chain.sh` → `scripts/check-lane-chain.sh`, whose verdict arm is `arm_verdict` in `plugins/dev-pipeline/skills/build/boundary-evidence.sh:1009`; `review-lean/SKILL.md` → `plugins/dev-pipeline/skills/review/SKILL.md`; `checked-call.sh` lives at `plugins/dev-pipeline/tools/checked-call.sh`. | codebase-derived |
| D-5 | The #840 hand-back mechanism (rc 11, `verdict --hand-back ratification`, `review-paused`) landed after filing | Not reused. It is an intent-gap/ratification channel that the merge boundary gates on `ratified:`. Zero CI is not a ratification question, and a record there would demand an operator ruling that cannot clear the condition. D-1's pre-spawn rc supersedes AC-4's "hand-back writes no record, rc 5" premise. The new rc takes the next value free in both the gate's and the scheduler's rc vocabularies (0-6, 8, 9 and 11 are in use). | codebase-derived |
| D-6 | AC-9 ablation-row disposition | With D-1 (a) the refusal also fires at milestone 4, so the `tools/gate-ablation-classes.tsv` row keys on milestone 4. The writer-time refusal has no milestone and is covered by the same row's reason. | codebase-derived |
| D-7 | Where AC-3's fail-open row lives, given `fail-open-sites.tsv` only admits grep-q pipeline sites | A new `by-design` disposition in `check-fail-open-shapes.sh`, checked with `converted`'s rules (anchor resolves, covers no live site). Every existing disposition requires or forbids site coverage in a way a key-absence fallthrough cannot meet. | codebase-derived |
| D-8 | Milestone 4 network posture | The merge-ref read runs only when `--pr` is passed. `cmd_all`'s pre-pass and a build session's `G 4` pass none, so they stay network-free (#374 AC-7); the scheduler passes it. | codebase-derived |
