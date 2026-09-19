# lean review verdict — #672

verdict=approve
run_id: review-672-1
session_id: c343fcad-7efe-4ef5-949c-310ffca18e95
rounds: 1
pr: #860
reviewed_head: b6f89869d7d7df5c57f24ed693c8c4c214a6ea3f
reviewed_patch_id: b5f561d99966e5fb87daa4d9474a818d75f2f9fa
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full range `49147157..b6f89869` (docs-only, 5 files). Panel: pipeline default (scope-completeness only); no opt-ins taken. Security-, performance-, maintainability-, complexity- and test-coverage dimensions covered by the lead pass (pure-prose diff, no executable surface). a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`.

The claims were verified against the private bench, not taken on the PR's word:

- All 15 sha256 pins in addendum 3 reproduce from bench commit `f90bd943` (`intake/`).
- Ordering holds: bench pins committed 16:04:55, addendum 3 (`533c2670`) 16:06:12, captures (`ab44a0fc`) 16:13:08; no pinned file changed between `f90bd943` and `ab44a0fc`; `533c2670` touches no `c4-intake/` file.
- Re-running `score.py --selfcheck` on all six roles: zero hits on each own body.
- Re-scoring all 36 captures with the pinned `score.py` reproduces every `sha256_16` and every per-gap hit in `runs.tsv` (all 1).
- A recount from the stream-json captures gives: `Skill` invocations 1 in each of the 18 kit runs and 0 in the 18 bare runs, model `claude-opus-5` in all 36, and `spec-reviewer` + `codebase-explorer` dispatched in 9/9 orchestrator kit runs (`implementability-probe` in 3).

Verdict under the registered table: bare 6/6 ≥ kit 6/6 and all 6 → `delete` for both, as the PR records. No blockers.

## Findings

| # | severity | file | finding |
| --- | --- | --- | --- |
| 1 | nit | docs/skill-ablation.md:3-6 | The header still says raw arm outputs under `docs/plans/skill-ablation/` are "one file per session, verbatim"; `c4-intake/` is numbers-only by design (captures in the private bench). One clause would keep the header true. Non-blocking. |
| 2 | nit | docs/plans/skill-ablation/c4-intake/README.md (Detector audit) | The audit paraphrases and quotes a few words of arm output ("already built", "already done") and names substrate features. The substrate is synthetic and carries no consumer identity (D-2's concern), and the audit is what makes the O3 flag-path scoring checkable, so this is accepted rather than scored against AC-3's "no arm output". Non-blocking. |

Suppressed (scope reviewer, confidence 50): the issue's "same children" candidate metric was weighed in D-1 and not adopted; the issue lists candidates, not mandates.

CI at head `b6f89869`: `pr-gates` red solely on the missing verdict record (this record); `mutation-sweep-pr` pass; `lint-and-selftests` and `selftests (macos, bash 3.2)` pending at review time — no AC here is proved by a selftest, and the diff touches no `*.sh`/`*.json`.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `docs/skill-ablation-addendum-3.md` extends (pre-registration and addenda 1–2 untouched in the diff), pins subjects/trees, substrate pin, 15 private hashes (all re-verified), construction, invocation bar, replicates, both thresholds tables; carries no result; committed in `533c2670`, which precedes `b6f89869` and touches no `c4-intake/` file. |
| AC-2 | satisfied | Addendum 3 "The two metrics": O1–O3 carry two between-children, two no-owner, two vacuous-child gaps; `score.py --selfcheck` re-run: zero hits on every role body; interviewer proxy over 6 ambiguities in 3 roles, registered unable to license `keep`. |
| AC-3 | satisfied | 36/36 runs in `runs.tsv` with rc, capture_bytes, sha256_16, classify_rc, model, skill_calls, per-gap hits; hits and sha prefixes reproduced by re-scoring the bench captures. |
| AC-4 | satisfied | Both verdict-table rows, the §3 `Not adjudicated` subsection, and both §4 P6 rows replaced with `delete` and reasons; headline 1,477/4,951 (487 + 711 + 279) → 70% unmeasured, arithmetic checked; §5 #672 bullet updated. |
| AC-5 | satisfied | Non-empty cut filed as #858 (open, "Execute addendum 3's delete verdicts…"), cited from §3 and §4; no `SKILL.md` in the diff. |
