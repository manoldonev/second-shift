# lean review verdict — #432

verdict=approve
run_id: review-432-1
session_id: 7239ad2e-12d2-4e5b-800f-9d37e5d4b4dd
rounds: 1
pr: #459
reviewed_head: 1a79364535c01cae56221dbe5ff69de588c4ea2f
reviewed_patch_id: 0255b6e5f700f7aefc1694132ddc817b15a4df38
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 — full branch diff (`c19f19e..HEAD`, no prior record to inherit from).
Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness —
all six returned, all `approve`, zero findings above threshold. No dark reviewer, no coverage gap.
Design fidelity `not-applicable`: the spec has no `## Design` section, the repo configures no
`design.provider`, and no changed path is a web component.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `lean-gate.sh` `telemetry_probe_target` | The `'[::1]'\|::1` loopback arm is unreachable. `host="${rest%%:*}"` on `[::1]:4317` yields `[`, and on `http://[::1]` the port parse yields `:1]`, which fails the numeric-port test. Probed against the real function: every IPv6 form (`http://[::1]:4317`, `http://[::1]`, `http://::1:4317`) returns empty, i.e. skip. Behavior is still correct per AC-3 — an unparseable endpoint skips the reachability half and reports `on` — so this is dead code claiming a capability, not a wrong answer. Every other documented form was probed and behaves as specified: `http://localhost:4317` → probe, bare host → default port 4317, trailing slash → probe, path-bearing → skip, `https` → skip. |
| 2 | Warning | spec Scope table + AC-9 | The scope table lists `tools/mutation-baseline.tsv` as changed and AC-9 asserts the two edited guards' "generic survivor ordinals" re-key, so their rows "are re-baselined here". The diff does not touch that file. Verified the obligation is genuinely nil rather than skipped: enumerated all six operators from `tools/mutation-operators.tsv` over `pipeline-cost-block.sh` at base and at head — the first three matched lines per operator are byte-identical, because every insertion lands after them; and CI's PR sweep swept `lean-gate.sh` and returned exactly the three already-baselined survivor ids (`cmp-eq::1`, `default::1`, `default::2`). So the record is right and the spec's prediction was wrong. Fix the spec text, not the baseline. |
| 3 | Note | `pipeline-cost-block.sh` | `pipeline-cost-block.sh` was `deferred-to-nightly` in the PR sweep (0 mutants applied), so the new selection/discrimination code carries no automated mutation evidence on this PR — only the build's 19 hand-probed mutants. That is the documented slow-guard norm, recorded here so the nightly result is read rather than assumed. |

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cmd_entry` resolves `telemetry_state()` and prints one of three branches before the return path; the `off` and `nocoll` messages both name the unrecoverable consequence. `(tel1)` asserts rc=0 together with the warning, so the never-refuses half is pinned, not assumed. |
| AC-2 | satisfied | Row is `… \| lines=<n> \| telemetry=<state> \| session=<id>`; `ENTRY_ROW_MARKER` is still `"\| entry \| ledger="` and `entry_row_present` is presence-only. `(ea1)` pins the new shape, `(ea2)` idempotence, `(tel6)` that a legacy row without the field still attests. The only other reader, `lean-reconcile.sh:484`, greps the same marker and renders the tail — unaffected. |
| AC-3 | satisfied | All three states reached under a controlled environment: `(tel1)` off, `(tel2)` nocoll against a resolved dead port, `(tel5)` on against a live listener (so the probe is not a constant failure), `(tel3)`/`(tel4)` the skip branches. Endpoint resolution independently probed here — see finding 1 for the one unreachable arm. |
| AC-4 | satisfied | Glob derives from the resolved `$METRICS_FILE`; selection keys on `file_mtime`, and both fixture pairs are named to contradict their mtime so a filename-parsing implementation fails in every timezone. `iso_to_epoch`/`file_mtime` validate the digits rather than the exit status, which is what makes the BSD/GNU pair portable — and CI's ubuntu leg is the evidence the macOS-only form was wrong. Fence-disabled reads the live file alone. One `jq -s` pass over `"${METRICS_FILES[@]}"`. |
| AC-5 | satisfied | `rowCount`/`fenceRowCount`/`oldestScannedAt`/`rotatedOut` all come off the one `compute_bucket_rollup` pass; the branch keys on `ROW_COUNT`, not `TOTAL_COST`. All four values asserted end-to-end via the recorded `costBlockApplied`, and the rotated-out case deliberately also carries in-fence foreign rows, so it pins the precedence rather than just the value. |
| AC-6 | satisfied | Both checks added inside the `otel-telemetry-classify` sentinels; `(ot1)`–`(ot5)` re-host the real block with `ok`/`warn` stubbed, so the assertions drive production branches. `(ot4)` covers the literal `0` — presence is not enablement — and `(ot5)` the enabled direction, so neither branch can be a constant. Both remain warnings. |
| AC-7 | satisfied | `state-schema.md` and `cost-tracking-setup.md` each carry the two new values and the narrowed `skipped-zero-datapoints`; §3 leads with the user-scope `~/.claude/settings.json` `env` block with direnv demoted to the per-repo alternative. |
| AC-8 | satisfied | Every new behavior has a paired guard, and the guards drive production code rather than a copy. Per D-12 no liveness scenario is added, correctly: the change introduces no gate contract and touches no verdict path. One defensive branch is untested (see Suppressed). |
| AC-9 | satisfied | Obligation is nil, verified empirically rather than taken on the spec's word — see finding 2. The two `mutation-catalog.tsv` rows for the cost block still match their anchored text, and `catalog::lean-gate-entry-row` was KILLED in CI despite the row it anchors gaining a field, because the anchor ends at `ledger=.*$`. |
| AC-10 | satisfied | One suite-level `unset RUN_ID` beside the existing `LEAN_RUN_MODEL` guard, plus per-call unsets of both telemetry variables in `pgate`/`pgate_tel` — without which `(ea1)` and the `(tel*)` cases would assert whatever the operator's own shell exports. |

## Suppressed (below threshold)

- `pipeline-cost-block.sh` — the unparseable-`FENCE_LO` branch in `select_metrics_files`, the newest-candidate backstop, and the "no readable metrics file could be selected" belt-and-braces exit have no direct case (confidence 65). All three are defensive and AC-8 does not name them.
- `lean-gate.sh` / `pipeline-cost-block.sh` both carry BSD/GNU date-portability idioms; the repo has no shared-lib convention for cross-script bash helpers, and the two serve different purposes.
- The `("" |0|false|FALSE|False)` off-value case is duplicated verbatim in `lean-gate.sh` and `pipeline-doctor.sh` — three lines, within the repo's stated preference for duplication over a helper.

## Verdict

`approve`. No blocker. Both warnings are documentation-grade: finding 1 is dead code behind a
correct answer, finding 2 is spec text that over-claims an obligation the diff correctly did not
need to pay. Neither is worth a round; fold them into the next touch of these files.
