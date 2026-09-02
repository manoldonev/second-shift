# lean review verdict — #783

verdict=approve
run_id: review-783-1
session_id: d1c6d83c-2dbb-4ad9-bbe1-24dba62bb6af
rounds: 1
pr: #785
reviewed_head: dbb30f6d41a39925f348faa1c2e7bd145146b4ad
reviewed_patch_id: 091aa2dead508d28b6b2d9e73dfb76ff3bfbc238
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

## Verdict

**approve** — round 1, full branch range `0978ee14..dbb30f6d` (root round; nothing to inherit).

The change does what the ticket asked and nothing else: `cmd_5`'s three `exit-artifacts`
assertions become one `pr_exit_artifacts_check` predicate, and `cmd_mark` — checklist step 7's
own call, already holding the resolved PR object — calls it too, so a step-7 body omission
refuses where it is created instead of after a review round is spent. No blockers.

Every AC was verified against the diff and the tree, not against the spec's own claims. Four
things I checked because they were the ones most able to be wrong, and all four held:

- **The placement is guarded on BOTH sides.** AC-2 puts the check after the MERGED short-circuit
  and before the idempotency no-op. `(pm11)` pins the second half. The first half is pinned by
  the pre-existing `(pm7b)`, whose merged fixture body (`"Closes #8"`) carries no spec link — so
  a check hoisted above the merged return flips its expected `rc=0` to 1. The ordering is not
  merely asserted in a comment.
- **No catalog anchor was orphaned.** Editing a guard's code re-anchors its
  `tools/mutation-catalog.tsv` rows. I extracted all 36 rows whose file column is `lean-gate.sh`
  and applied each `sed` expression to the current file: all 36 still match. Probe validated with
  a positive control (a deliberately dead anchor is reported dead) and a negative control (the
  `lean-gate-mark-session-guard` anchor still applies). AC-9's "no re-anchoring owed" holds.
- **D-18's departure premise is exact, not approximate.** `MAX_ROWS_PER_GUARD=36`
  (`tools/mutation-sweep-selftest.sh:2669`); `lean-gate.sh` carries exactly 36 rows at both base
  and head. A 37th breaches the per-guard cap lint. The departure is forced, not chosen.
- **Close-out diagnosis is unchanged.** `cmd_5` calls `cmd_mark` unconditionally, so the predicate
  runs twice on that path — but `cmd_5`'s own check (`lean-gate.sh:5819`) runs *before* the
  `cmd_mark` call (`:5832`/`:5863`), so `mark`'s new refusal can never preempt `cmd_5`'s message.
  AC-3's byte-identical property survives at the call site that actually reports it.

The three message literals are byte-identical to their pre-#783 form (diff-verified, all three
arms). `set -uo pipefail` with `local -a arr=()` and `${#arr[@]}` on an empty array is safe on
bash 3.2.57 — probed directly, since that is this repo's macOS CI lane and the obvious way this
refactor could have broken only there.

`pr-gates` is red. It fails on exactly one arm — `no committed verdict record` — which is the
artifact this round produces; I reproduced the run locally and both policy guards
(`check-frozen-files.sh`, `check-changelog-trailer.sh`) pass at this head. Recorded, not a blocker.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `pr_exit_artifacts_check` defined `lean-gate.sh:5700`; called from `cmd_mark:2688` and `cmd_5:5819`. Both sites in one file, so a shared call, not a LOCKSTEP pair (D-3). |
| AC-2 | satisfied | `cmd_mark:2688` hard-refuses `return 1`. Placement after the MERGED short-circuit (`:2668-2672`) and before the idempotency no-op (`:2711`); both halves guarded — `(pm11)` for the no-op side, pre-existing `(pm7b)` for the merged side (its fixture body lacks the spec link, so a hoisted check flips its expected rc=0). |
| AC-3 | satisfied | All three literals byte-identical to base, verified in the diff: draft/`Closes #`/`Closes [ ]`/spec-link arms unchanged. Joined multi-obligation message guarded by `(pm10)`, which asserts all three named in one refusal. |
| AC-4 | satisfied | `resolve_open_pr:5762-5764` already requests `number,url,body,isDraft,state` — the predicate adds no call. `cmd_mark` contains no `append_attempt`/`append_absent`/`append_obligation`, so a refusal writes no progress row and charges no fix budget. |
| AC-5 | satisfied | The predicate's arms are exactly draft, Closes, spec link. No cost-block and no summary arm; both stay out of the checked set. |
| AC-6 | satisfied | `pr-mark.json` gains `isDraft`+compliant `body`; new `pr-mark-jira.json` repoints `(pm6)`/`(pm6b)`, whose ACME-8 identity the github body would not satisfy. Both cases green in CI and locally. |
| AC-7 | satisfied | `scenario-liveness-selftest.sh` leg 1c composes `mark` refusing a spec-link-less step-7 body, then the same session posting once fixed. Suite green locally on bash 3.2.57: 84 passed, 0 failed. |
| AC-8 | satisfied | `(pm8)` draft, `(pm9)` spec link, `(pm10)` joined multi-obligation, `(pm11)` D-4 placement vs. the idempotency no-op. Green in both CI selftest lanes at this head. |
| AC-9 | satisfied | No catalog row added; `lean-gate.sh` row count is 36 at base and 36 at head. All 36 `sed` anchors still apply to the current file (probed, with positive and negative controls), so `lean-gate-mark-session-guard` needs no re-anchoring. |
| AC-10 | satisfied | `plugins/dev-pipeline/skills/build-lean/SKILL.md` is not in the diff — `git diff --name-only 0978ee14..HEAD` returns five files, none of them a SKILL.md. |
| AC-11 | satisfied | `bash tools/prose-blockers.sh check` exits 0: "zero undispositioned constructs" (29 constructs over 52 files, 52 record rows). |
| AC-12 | satisfied | The predicate carries `grep -c -i -E "closes[[:space:]]+#$ISSUE"` verbatim from `cmd_5`. OR-1's blind spot is inherited and disclosed in both the spec and the PR body, as the ticket's default disposition requires. |
| AC-13 | satisfied | CI at the reviewed head `dbb30f6d`: `lint-and-selftests` SUCCESS (job 100294408083, 4m47s) and `selftests (macos, bash 3.2)` SUCCESS (job 100294408037, 9m2s), run 33644145852 — the sweep and the bash-3.2 lane both green. `shellcheck -e SC1091,SC2015,SC2181` clean locally on all three changed shell files. |

## Findings

No blockers. Four non-blocking observations, none of which should hold the merge:

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | suggestion | `lean-gate.sh:5728` | The trailing `"; "` trim (`${PR_EXIT_ARTIFACTS_MISSING%; }`) is what makes AC-3's byte-identical property true for the single-obligation case, but every consuming assertion is a `grep -q` substring match — none is an equality comparison. Deleting the trim would leave a stray `"; "` on every single-obligation message and no test would notice. The code is correct; the guard on it is weaker than the AC it upholds. |
| 2 | suggestion | test fixtures | D-13 decided that "an absent key must not read as a pass". The implementation honors it — `jq -r '.[0].isDraft'` yields `null` on an absent key, which fails `[ "$draft" = "false" ]` (probed directly). But no fixture omits `isDraft`, so a change to `.isDraft // false` would fail open through the `--pr-file` seam unguarded. |
| 3 | suggestion | `lean-gate.sh:5719` | The spec-link arm's `grep -c -F` would survive dropping `-F`: every fixture `SPEC_REL` contains only `.` and `-`, which self-match as regex. Inherited verbatim from `cmd_5` per AC-12, so pre-existing rather than introduced here. |
| 4 | nit | `lean-gate.sh:2689` | `cmd_mark`'s wrapper prose ("is missing checklist step 7's PR-body obligations:") is untested independently — all assertions grep substrings of `$PR_EXIT_ARTIFACTS_MISSING`, which the wrapper does not affect. Cosmetic. |

Findings 1, 3 and 4 are the mutation reviewer's, verified against the code rather than relayed;
finding 2 is the lead pass's.

## Panel

- `review-toolkit:scope-completeness-reviewer` — approve, no findings.
- `review-toolkit:unit-test-mutation-reviewer` — approve-with-nits (findings 1, 3, 4 above); its
  predicted-killed set independently reproduced my own ordering analysis for `(pm7b)`/`(pm11)`.
- Lead pass (in-session, not spawned): performance, complexity, maintainability, test coverage,
  and security — the security conditional did not fire (no auth/tenancy/session/upload/
  query-construction surface, and the repo carries no `review-context/security-reviewer.md`), so
  the lead pass owned that dimension. No blocker in any of the five.
- Not routed: `a11y-reviewer` and the design-fidelity dimension — no changed path matches
  `stageParams.webComponentGlobs` (unset; resolves to the default `apps/web/**/*.{tsx,jsx}`).
  `db-reviewer` and `pipeline-reviewer` — no DB or async-worker surface.

Design is disarmed (`Design: none`) and the disarm is justified: this consumer's
`.claude/second-shift.config.json` has `design: null`, so no provider is configured, and the diff
touches no UI surface. Recorded `fidelity: not-applicable`.
