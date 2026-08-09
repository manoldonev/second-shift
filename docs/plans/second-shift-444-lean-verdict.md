# lean review verdict — #444

verdict=approve
run_id: review-444-1
session_id: a159e959-c837-4c7a-bbb6-25fd485df560
rounds: 1
pr: #470
reviewed_head: b20bff87e76eb2b3078a44cae69f962488e1cc1e
reviewed_patch_id: 3d2d27c95c27d93c1753848187324217c6bbe4da
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch range `6a6922c..b20bff8` — no prior record to inherit from.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| — | — | — | No blockers and no warnings. |

The six-reviewer panel (security, performance, complexity, maintainability, test-coverage,
scope-completeness) returned `approve` with zero findings each. Nothing went dark. Three
security observations landed below the confidence threshold and are recorded as notes below
rather than as findings — each is a decision the spec argues explicitly, and none is a defect
in the diff.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `arm_identity` emits `inapplicable identity postdated` and returns 0 before any violation can be counted. `(ac1)` asserts exactly one class-(b) line at `since:` minus one second, on `markers-none.json` — a trail that is a violation inside the window, so rc=0 can only mean the arm declined. `(Z1)` and `(lr4)` repeat it through the delegating boundary. |
| AC-2 | satisfied | `(ac2)` drives the boundary second itself and asserts rc=1 with the `no bot-authored` violation and no `identity: postdated` line. `(lr4)`'s paired call and `(eb2)` cover the same direction on the gate side. |
| AC-3 | satisfied | `(ac3)` drops the variable entirely (`PR_CREATED_AT_OVERRIDE=none`) and asserts rc=0 with a `postdated` decline — rc=2 would be the regression. `scripts/check-lean-chain.sh:351` is untouched and keeps its hard requirement. `(ac4)` covers OR-1: a malformed value takes the absent path and is named on stderr. |
| AC-4 | satisfied | `lean-evidence.sh` documents `PR_CREATED_AT` as optional in its env block and reads it at the cutoff. `second-shift-ci.yml` supplies `${{ github.event.pull_request.created_at }}`, pinned by a whole-line anchored `second-shift-ci-check-selftest.sh` case scoped to the step's own `env:` block. |
| AC-5 | satisfied | `LEAN_IDENTITY_SINCE='2026-08-08T17:05:14Z'`, `ENTRY_SINCE='2026-08-07T13:22:51Z'`, and `check-lean-chain.sh`'s issue-side claim arm carries none. Both anchors verified against the real history: `ca269a9` (#430) is committed `2026-08-08T17:05:13Z`, so the `+1s` is D-14 as specified, and `9c0a689` (#422) is authored `2026-08-07T13:22:51Z`. Both values are pinned behaviorally by one-second straddles — `(ac1)`/`(ac2)` and `(eb1)`/`(eb2)` — rather than by grepping the constant, and `(Z2)` proves the claim arm still gates a PR the marker arm exempted. |
| AC-6 | satisfied | `(eb1)` asserts rc=0, the announcing `note:` line, the absence of the attestation refusal, and zero `entry` rows. `(lean-entry-since)` composes it: the de-blocked run walks milestone 1 to its terminal record while attesting nothing, and the paired un-aged branch is still refused — the discriminator that keeps the leg from passing for a precondition that stopped guarding anything. |
| AC-7 | satisfied | `(eb2)` asserts rc=2, the original `no entry attestation` wording, and the second cause (`host-local and gitignored`) — the paragraph a rewrite is likeliest to drop. |
| AC-8 | satisfied | `(eb3)` drives a `-05:00` author date whose local clock reads before the cutoff but whose UTC instant is after (fail-open direction); `(eb4)` drives `+05:30` in the mirror direction and asserts the normalized `2026-08-07T12:30:00Z` in the output. Structural half: `(ac6)` and `(eb7)` assert neither file reaches for `date -d` or `date -r`. The macOS bash-3.2 CI lane is green on this head. |
| AC-9 | satisfied | `(lean-entry-since)` and `(lr4)` are both present in `scenario-liveness-selftest.sh`, one per new verdict path, and `(Z1)`/`(Z2)` in `check-lean-chain-selftest.sh` compose the differing-windows property no per-tool suite can see. Re-run in this checkout: the scenario suite exits 0 with both new legs passing. |
| AC-10 | satisfied | The DROPPED entry in `scripts/lockstep-manifest.tsv` states why the duplication is forced (the consumer's CI checkout fetches `lean-evidence.sh` and nothing else, so neither file can source the other) and why no relation fits — `verbatim` would bind two deliberately different shapes, and `subset-of` reads the first quoted literal of each block, which here is a lone ISO instant the two sides are *meant* to differ on. It follows the `lean evidence TOKEN SCOPES` precedent and names the revisit condition. |
| AC-11 | satisfied | `git diff 6a6922c..HEAD -- tools/` is empty, and `tools/mutation-baseline.tsv` carries exactly the five rows the PR body names (`lean-evidence.sh::cmp-eq::1`, `::default::1`; `lean-gate.sh::cmp-eq::1`, `::default::1`, `::default::2`). The claim that no ordinal moved is not taken on assertion: `mutation-sweep-pr` is green on this head, and a survivor absent from the baseline is exactly what that job reds on. |

## Verification run in this checkout

`lean-evidence-selftest.sh`, `lean-gate-selftest.sh`, `check-lean-chain-selftest.sh`,
`second-shift-ci-check-selftest.sh` and `scenario-liveness-selftest.sh` all exit 0, run with
`env -u CLAUDE_CODE_SESSION_ID -u RUN_ID` so no ambient session identity leaks into a fixture.
`shellcheck -e SC1091,SC2015,SC2181` is clean over all seven changed shell files.

On CI at this head: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr`
all pass. `pr-gates` fails on exactly one thing — the absent verdict record this document is —
and its log shows the identity arm *enforcing*, since the run's own `PR_CREATED_AT`
(`2026-08-09T22:53:02Z`) sits after `LEAN_IDENTITY_SINCE`. The repo's own gate therefore
exercises the enforcing side of the new comparator on every PR, which is what the lockstep
entry claims as its live signal.

## Notes, not findings

- **The `since:` literals are load-bearing constants with no independent check.** Both were
  verified here against the merges they name, but nothing in the tree would catch a future
  typo that moved one — the straddle cases would simply move with it. That is inherent to the
  design (the spec argues correctly that deriving the date fails open), and it is the right
  trade; recording it so the next reader knows the anchor comments are the only provenance.
- **The gate's de-block keys on the git author date, which an operator can set.** A backdated
  first commit waives the entry-attestation precondition. This does not cross a trust boundary
  — the gate is self-enforcement on the build host, and an operator willing to forge
  `GIT_AUTHOR_DATE` can more cheaply just run `bash G entry`. Author date is also the correct
  key, per the spec's rebase argument.
- **Consumers whose committed workflow predates this change silently lose the identity arm**
  until they re-adopt the template. That is the explicit AC-3/AC-4 posture, and it is not
  silent in the output: the decline names `<no usable PR_CREATED_AT>` as the instant it
  compared, so the reason is legible from the CI log.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, this repo's config has no `design`
key at all, and the diff is shell and YAML with no rendered surface — so the arming signal is
absent on both halves and the disarm needs no justification.
