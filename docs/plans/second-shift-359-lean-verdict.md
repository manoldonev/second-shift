# lean review verdict — #359

verdict=needs-work
run_id: review-359-1
session_id: 6631bfd2-6804-4f10-b9ad-a017c8b7aacc
rounds: 1
pr: #430
reviewed_head: d79c3e52a081d00753681898ebeb3be24bb5c901
reviewed_patch_id: a59198db47818ca0377ce843245d125d8cdc9228
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Round 1 — `needs-work`

Range read: `a2b158f..HEAD` (full branch; `delta` reported nothing verifiable to inherit).
18 files, +2024/−179. Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness (all six returned; none dark).

The design of this change is right and the test surface is unusually strong — the delegation is
real (one implementation, not two), the arms fail closed everywhere, and every new assertion I
probed dies under a targeted mutation. One blocker: the consumer CI template cannot execute the
arm it now ships.

### Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `plugins/second-shift/templates/consumer/second-shift-ci.yml:22-23` | The template's `permissions:` block grants only `contents: read`, but the new check (c) runs `lean-evidence.sh`, whose identity arm calls `gh api repos/$GH_REPO/issues/$PR_NUMBER/comments` (`lean-evidence.sh:395`). Specifying any permission sets every unspecified one to `none` — GitHub documents no public-repo exception — so `issues` and `pull-requests` are `none` and that call is denied. The payload treats a failed fetch as an environment error and `exit 2`; the check script maps `2` → `bad`. Net effect: **every lean PR in an adopting consumer fails the "second-shift evidence" check**, and the failure text (`the workflow is not supplying what the payload at '<ref>' needs`) points the operator at the step env rather than at the token scope. This repo's own `pr-gates` job already grants exactly `issues: read` + `pull-requests: read`, with an inline comment saying they exist for the chain check's comment read (`.github/workflows/ci.yml:151-155`) — the requirement is known here and simply not mirrored into the template. Compounding it, the template's comment at line 21 reads *"never widen this job's permissions"*, so an adopter hitting the red is steered away from the fix. Consumer-side enforcement is this issue's whole deliverable, and as shipped it is a permanently red gate rather than a gate. Fix: add the two read scopes, amend the line-18-21 comment to say read-only scopes the arms require are permitted (the blast-radius argument is about *write*), and pin them in `second-shift-ci-check-selftest.sh` beside the existing `yml: step env carries …` rows — that block's own rationale ("an input whose absence makes the payload exit 2 … would red every adopting repo's lean PRs") applies verbatim. |
| 2 | Warning | `lean-evidence.sh:457-460` | `arm_freshness` on a non-approve record emits its own violation restating what `arm_verdict` already emitted, so a `needs-work` record counts **2** violations for one fact. The comment directly above it names that ("restates the verdict arm's finding … which is the 'one fact printed as three violations' defect") and then does it anyway. Suppressing it entirely would make `check --arms freshness` alone vacuous on a non-approve record, so the arm is right to refuse — but the *combined* run should not double-count. `(h)` currently asserts the message is present and prints the count in its label without pinning it. Fails safe; message quality only. |
| 3 | Note | `scripts/check-lean-chain.sh:369-370` | `[[ -n "$APPLICABLE" ]] \|\| envfail "the evidence payload returned no applicability verdict"` is not killed by any case — I neutralized the guard and `check-lean-chain-selftest.sh` stayed fully green. Nearly unreachable for the committed payload (`classify` always prints the key and exits 0), so it is a belt for a vendored/drifted `LEAN_EVIDENCE`; recording it rather than asking for a case. |
| 4 | Note (environment) | — | **CI has never run on this branch.** `gh api .../commits/d79c3e5/check-runs` → `total_count: 0`, and `actions/runs?branch=lean/second-shift-359` → `0`, 13h after PR open. Repo-wide, a run from 2026-08-06T17:29Z is still `queued`. So `pr-gates` has produced no verdict on this PR — neither red nor green — and nothing about that is caused by this diff. Local verification stands in for it (below). Worth an operator eye before merge. |

Suppressed below the confidence threshold (from the panel, all ≤45): the fetch-and-`bash` of
`lean-evidence.sh` at the pinned ref as an RCE surface (consistent with the pre-existing
config-lint fetch at the same ref under the same token); `RESOLVED_RUN_ID` interpolated into the
`jq test()` regex in `cmd_mark` (locally generated, and a mismatch only duplicates a marker);
the marker publishing `run_id`/`session_id` on a public PR (identifiers, not credentials,
identical to the existing issue-side claim marker); `gh` stderr echoed on fetch failure.

### AC scoring — `docs/plans/second-shift-359-lean.md`

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 payload selftest | **satisfied** | All nine enumerated assertions exist as `(a)`–`(cc2)`; hermetic (both fixture seams, no network, no remote). 36/36 green. Probed: `select(.user.type == "Bot")` → `select(true)` kills `(n)` alone; `-lt 1` → `-lt 0` kills `(m)`/`(n)`; deleting the `marker_sessions` loop kills `(l)` alone; `-z "$VERDICT_REVIEWED_PATCH_ID"` → `false` kills `(r)` alone; dropping `":(exclude)$VERDICT"` kills `(t)`; `GH_CLI="${GH:-gh}"` → `${GH:-}` kills `(cc2)` alone; the no-key `exit 1` → `exit 0` kills `(cc1)` alone. |
| AC-2 template selftest | **satisfied** (by its letter) | Probes: retargeting the payload path kills *"lean payload 404: FAIL names the payload path and the 404"*; `bad` → `warn` on the 404 branch kills three cases; `1) bad` → `1) ok` and `*) bad` → `*) ok` each kill their own case; neutering the `PR_HEAD_REF` guard kills both not-applicable cases. `fetch-depth: 0` and the six env vars are pinned. Finding 1 is a gap in what the YAML supplies, not in what this AC enumerates. |
| AC-3 delegation | **satisfied** | Classification, verdict, identity, intent-gap and the declared-patch-id branch all route through the payload; the gate re-*reads* the record's keys but emits no refusal about them (documented at the site). 71/71 green with `(Y1)`–`(Y5)` added. Probes: not folding the payload's count kills 10 cases incl. `(Y1)`–`(Y3)`; dropping the `rc=2` propagation kills `(U5)`/`(U6)`; an unreachable payload kills `(Y5)`. |
| AC-4 writer | **satisfied** | `(pm1)`–`(pm7)` cover post / idempotent-by-identity / second session / right-delimited run-id / human marker / jira skip / no-open-PR, and `cmd_5` calls it; `scenario-liveness` composes both the write and the re-entry no-op. Confirmed live: PR #430 carries a marker authored by the configured bot app (`user.type: Bot`), carrying `run_id: lean-359-a`, a session id, and `stage: lean-pr-marker`. |
| AC-5 config resolution | **satisfied** | `(z1)`/`(z2)` drive the committed-config path, `(z3)` proves env wins, `(f)` proves the mutual non-prefix refusal is an environment error. |
| AC-6 jira degrade | **satisfied** | `(aa1)` pins the printed reduced-strength line, `(aa2)` pins that a jira consumer's missing verdict still exits 1. Probe: `= "jira"` → `= "zzzz"` kills `(aa1)` alone. |
| AC-7 mutation baseline | **satisfied** | Verified independently, not taken on report: `mutation-sweep.sh --mode pr --base origin/main` with `MUTATION_SWEEP_CACHE=0` (49 verdicts, 431s, advisory/local). Survivor ids are **exactly** the baselined set on all four guards — `lean-evidence` `{cmp-eq::1, cmp-eq::2, default::1}`, `lean-gate` `{cmp-eq::1, default::1, default::2}`, `ci-check` `{cmp-eq::1, cmp-z::1, logic::2, default::1}` + the already-baselined `catalog::ci-check-lint-path`, `check-lean-chain` `{cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2}`. Zero unbaselined. The new `catalog::ci-check-evidence-path` is killed, and `ci-check-lint-path`'s re-anchor is real — the old `LINT_PATH=` anchor matches nothing at HEAD. |
| AC-8 doc | **satisfied** | `SECOND-SHIFT.md` documents the arm, its fail-closed posture and the required-status wiring plus the per-tracker strength note; `SKILL.md` step 7 names `bash G mark`; `lockstep-manifest.tsv` carries the `lean-pr-marker` row and the `lean-branch-prefix` row, with the artifact-suffix coupling recorded as an explicit DROPPED entry. `check-lockstep-pairs.sh` 19/19. |
| AC-9 critic | **satisfied** | `check-changelog-trailer.sh origin/main` rc=0; all five commits carry a trailer. No consumer identity anywhere in the diff — fixtures are `acme-*`/`acme-bot`; the only real names are this repo's own. |

### Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit `Design: none — this is
shell/CI plumbing with no rendered surface` disarm, and the repo's committed config declares no
`design.provider` (`.design` is null), so the disarm is justified and steps (i)–(iii) do not apply.

### Verification I ran (from this checkout of the PR head)

- Full sweep, **no `SKIP_STRESS`**, `CLAUDE_CODE_SESSION_ID` and `RUN_ID` unset: 64/64 suites green.
- The pollution case the branch's last commit fixes, re-checked independently — `RUN_ID` exported
  *and* a real `GH_BOT` present: `lean-gate-selftest` 199/0, `lean-evidence-selftest` 36/0,
  `scenario-liveness-selftest` 75/0, `check-lean-chain-selftest` 71/0. No suite reached a live
  wrapper.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all nine changed shell files.
- `check-lockstep-pairs.sh` 19/19, `check-changelog-trailer.sh` rc=0, `check-frozen-files.sh` clean
  (one advisory: the PR edits `.github/workflows/ci.yml`).
- 15 hand-probed mutations across `lean-evidence.sh`, `check-lean-chain.sh` and
  `second-shift-ci-check.sh`: 14 killed by a named case, 1 survivor (finding 3).

### Strengths

- The delegation is genuinely one implementation. `check-lean-chain.sh` keeps only the arms a
  read-only tracker cannot have, reads the payload's violation **count** rather than collapsing it
  to an exit code, and propagates `rc=2` as its own — so this repo's CI exercises the exact bytes a
  consumer executes, and the asymmetry (two identity sources here, one there) is disclosed rather
  than levelled down.
- Zero-markers-is-a-violation, and the jira degrade printed per-arm rather than silently skipped,
  are the right posture and are both pinned by cases that die when the branch is neutralized.
- `(cc1)`/`(cc2)` are real coverage repair, not baseline padding: both came from the sweep, and the
  `${GH:-gh}` one is killed by driving a stub `gh` on `PATH` instead of the fixture seam — the only
  way to reach the line a consumer's CI actually depends on.
- The intent-gap record states the provenance of its own ratification (operator-approved
  in-session, keystrokes delegated to the run) and explains why the boundary cannot tell the
  difference. That is the disclosure the arm cannot make for itself.
