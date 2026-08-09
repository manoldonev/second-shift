# lean review verdict — #432

verdict=approve
run_id: review-432-1
session_id: f2ba7aaf-90c5-4ebe-acd2-6864426b96db
rounds: 1
pr: #459
reviewed_head: 4cca8e390fe2b8504b2f22d500eaa2be647e8020
reviewed_patch_id: 4228cc669921efde78f85c9c7fbe14c0abd07688
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 — RE-STAMPED at the rebased head. Range `cccd575..HEAD` (the gate's `delta` prints the
full branch diff: the prior record's patch id no longer resolves, so there is nothing verifiable
to inherit and this covers everything).

**Why a re-stamp and not a round 2.** The round-1 record (`review-432-1`, reviewed head
`1a79364`) was invalidated by a rebase of the branch from base `c19f19e` onto `cccd575` (#456),
which dropped an intervening `--no-ff` merge of main and replayed the four build commits. The
merge-base-anchored contribution diff is byte-identical across the replay:

```
diff <(git diff c19f19e..1a79364  -- . ':(exclude)<record>') \
     <(git diff cccd575..HEAD     -- . ':(exclude)<record>')
```

1104 lines each side; 22 differing lines, **zero** matching `^[<>] [+-]` — every one is an
`index <blob>..<blob>` line, an `@@` hunk offset, or a context line that main's #456 moved. The
reverse direction (`c19f19e..cccd575` against `1a79364..HEAD`) likewise carries no `+`/`-`
divergence, so main's side came in whole. `reviewed_patch_id` moved only because `git patch-id`
hashes context lines, which is the mechanical limitation #372 identified — not evidence that a
line of reviewed content changed. Per the skill's own rule ("a rebase that replays the branch
unchanged does not [void the record]: the patch is the same") the round stands.

**What this session verified independently**, rather than re-asserting round 1's panel result: all
ten ACs re-scored below against the code at this head, first-hand; and the two surfaces the base
move newly touches, which round 1's panel could not have seen because they did not exist at
`c19f19e`. The six-reviewer panel is not re-dispatched — it would read a byte-identical tree.

**Base-move interaction (new since round 1), both clean.** #456 rewrote `cmd_entry`'s
neighborhood in the same file this PR edits, and the rebase resolved without conflict; a clean
textual merge is not by itself evidence the two compose.

- `record_build_session` lands *after* the entry-row block and outside its idempotence branch, so
  the `telemetry=` field this PR inserts is on a row it never parses. `build_session_set` reads
  the `session_id:` header via `record_key` plus `| session | <id>` rows — the entry row's
  `session=<id>` uses neither key, so #456's stated "first match of that key" hazard is not
  reachable through the new field.
- `lean-reconcile.sh`'s entry-attestation reader (`sed -E 's/^.*\| (lines=.*)$/\1/'`) is
  tail-anchored, so it now renders `lines=<n> | telemetry=<state> | session=<id>` where it
  previously rendered two fields. Correct and strictly more informative; the surrounding check is
  presence-only on the unchanged `| entry | ledger=` marker.

**CI at this head** (`4cca8e3`): `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass. `pr-gates` is the expected pre-record red, and its sole failing arm is
`lean-evidence`'s patch-id comparison — precisely what this record re-stamps. `mutation-sweep-pr`
passing is also the empirical half of AC-9 below: had the two edited guards' generic survivor
ordinals re-keyed, the PR-scoped sweep would have reported baseline-absent survivors and redded.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `lean-gate.sh` `telemetry_probe_target` | The `'[::1]'\|::1` arm of the loopback host case is unreachable, and so is `telemetry_state`'s matching `host="${host#[}"; host="${host%]}"` strip. Re-derived by hand at this head: on `http://[::1]:4317`, `rest` is `[::1]:4317` and `host="${rest%%:*}"` is `[`; on `http://[::1]`, `host` is `[` and `port` is `:1]`, which fails the numeric-port test; on `http://::1:4317`, `host` is empty. Every IPv6 form falls through to `return 0`. Behavior is still correct per AC-3 — an unparseable endpoint skips the reachability half and reports `on` — so this is dead code behind a right answer, not a defect. Worth deleting or making real on the next touch. |
| 2 | Warning | spec Scope table + AC-9 | The Scope table lists `tools/mutation-baseline.tsv` as changed and AC-9 asserts the two edited guards' generic survivor ordinals re-key, so their rows "are re-baselined here". The diff does not touch that file. The obligation is genuinely nil rather than skipped — round 1 established it by enumerating the operators over `pipeline-cost-block.sh` at base and head, and CI's green `mutation-sweep-pr` at this head confirms it independently. The spec text over-claims an obligation the diff correctly did not need to pay; fix the Scope row, not the diff. |
| 3 | Note | `pipeline-cost-block.sh` | `pipeline-cost-block.sh` was `deferred-to-nightly` in the PR sweep (0 mutants applied), so the new selection/discrimination code carries no automated mutation evidence on this PR — only the build's 19 hand-probed mutants. That is the documented slow-guard norm, recorded so the nightly result is read rather than assumed. |

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cmd_entry` resolves `telemetry="$(telemetry_state)"` and prints one of three branches on the path to `return 0`; nothing between the `case` and the return can change the code. The `off` and `nocoll` messages each name the unrecoverable consequence and point at `cost-tracking-setup.md`. `(tel1)` asserts rc=0 *together with* the warning, so the never-refuses half is pinned rather than assumed. |
| AC-2 | satisfied | The appended row is `… \| lines=$lines \| telemetry=$telemetry \| session=$sid`. `ENTRY_ROW_MARKER` is still `"\| entry \| ledger="` and `entry_row_present` is a presence count over it, so a legacy row without the field still satisfies it and `require_entry_attested`. `(ea1)` pins the new shape, `(ea2)` idempotence, `(tel6)` the legacy row. Both downstream readers re-checked at this head — see the base-move note above. |
| AC-3 | satisfied | All three states are reached under a controlled environment: `(tel1)` off, `(tel2)` nocoll against a resolved dead port, `(tel5)` on against a live listener (so the probe cannot be a constant failure), `(tel3)`/`(tel4)` the two skip branches, `(tel4)` deliberately reusing `(tel2)`'s port so it pins the *path* rather than the port. Endpoint resolution independently re-derived here; one arm is dead, see finding 1, which does not change any state's answer. |
| AC-4 | satisfied | The glob derives from the resolved `$METRICS_FILE`; selection keys on `file_mtime` against `iso_to_epoch "$FENCE_LO"`, and both helpers validate the *digits* rather than the exit status, which is what makes the BSD/GNU pair portable — CI's ubuntu leg is the evidence the macOS-only form was wrong and is now right. Fence-disabled reads the live file alone. `select_metrics_files` fills one `METRICS_FILES` array consumed by the single existing `jq -s` pass. Confirmed the script is `set -uo pipefail` with no `-e`, so the unparseable-fence branch logs and degrades rather than aborting. |
| AC-5 | satisfied | `ROW_COUNT` / `FENCE_ROW_COUNT` / `OLDEST_SCANNED` / `ROTATED_OUT` all come off the one `compute_bucket_rollup` pass, and the branch at line 612 keys on `ROW_COUNT -eq 0`, not on `TOTAL_COST`; `skipped-zero-datapoints` is now the *narrowed* fall-through below it. Precedence is rotated-out → session-not-exporting → telemetry-off, and the rotated-out fixture deliberately also carries in-fence foreign rows, so the ordering is pinned rather than just the value. |
| AC-6 | satisfied | Both checks sit inside the `otel-telemetry-classify` sentinels the suite extracts: a `case "${CLAUDE_CODE_ENABLE_TELEMETRY:-}"` warn/ok pair, and `_otel_backup_present` accepting any non-empty `<stem>-*.jsonl` while honoring `$OTEL_METRICS_FILE` so it tracks what `pipeline-cost-block.sh` resolves. `(ot1)`–`(ot5)` re-host the real block with `ok`/`warn` stubbed, so the assertions drive production branches; `(ot4)` covers the literal `0` (presence is not enablement) and `(ot5)` the enabled direction, so neither can be a constant. Both remain warnings. |
| AC-7 | satisfied | `state-schema.md` 352–354 and `cost-tracking-setup.md` 148/155/156 each carry the two new values and the narrowed `skipped-zero-datapoints`, each with its own remedy and each saying plainly that the datapoints are unrecoverable for the run in question. §3 leads with the user-scope `~/.claude/settings.json` `env` block, direnv demoted to the per-repo alternative. |
| AC-8 | satisfied | Every new behavior has a paired guard that drives production code rather than a copy: `lean-gate-selftest.sh` `(ea1)`/`(ea2)`/`(tel1)`–`(tel6)`, `cost-block-selftest.sh` +172 lines, `pipeline-doctor-selftest.sh` +78. Per D-12 no liveness scenario is added, correctly — the change introduces no gate contract and touches no verdict path. Three defensive branches are untested; see Suppressed. |
| AC-9 | satisfied | The obligation is nil, and verified two ways rather than taken on the spec's word: round 1's operator-by-operator enumeration at base and head, and `mutation-sweep-pr` green at this head, which is the check that would red on an unbaselined generic survivor. The spec text that says otherwise is finding 2. The two `mutation-catalog.tsv` rows for the cost block still match their anchored text, and `catalog::lean-gate-entry-row` survives the row gaining a field because its anchor ends at `ledger=.*$`. |
| AC-10 | satisfied | One suite-level `unset RUN_ID` at line 46, beside the existing `unset LEAN_RUN_MODEL` at 36 and for the same reason, plus per-call unsets of both telemetry variables in the entry helpers — without which `(ea1)` and the `(tel*)` cases would assert whatever the operator's own shell exports, and the suite is very likely running inside an exporting session. |

## Suppressed (below threshold)

- `pipeline-cost-block.sh` — the unparseable-`FENCE_LO` branch in `select_metrics_files`, the
  newest-candidate backstop, and the "no readable metrics file could be selected" exit have no
  direct case (confidence 65). All three are defensive and AC-8 does not name them.
- `lean-gate.sh` and `pipeline-cost-block.sh` both carry BSD/GNU date-portability idioms; the repo
  has no shared-lib convention for cross-script bash helpers and the two serve different purposes.
- The `("" |0|false|FALSE|False)` off-value case is duplicated verbatim in `lean-gate.sh` and
  `pipeline-doctor.sh` — three lines, within the repo's stated preference for duplication over a
  helper.

## Verdict

`approve`, round 1, re-stamped. No blocker. Both warnings are documentation-grade: finding 1 is
dead code behind a correct answer, finding 2 is spec text that over-claims an obligation the diff
correctly did not need to pay. Neither is worth a round; fold them into the next touch of these
files.
