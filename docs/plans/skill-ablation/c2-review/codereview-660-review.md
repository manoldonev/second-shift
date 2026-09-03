# C2-c — the built-in `/code-review` on PR #660

The arm-2a challenger session for sample **C2-c**, run 2026-09-03 against the pinned clone. Registered at [`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §B; scored against the frozen C2 rule at [`docs/skill-ablation-pre-registration.md`](../../../skill-ablation-pre-registration.md):146-161. Everything below the rule is this session's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2-c-660
printf '%s' '/code-review max pr-660' | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT \
  -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob,Bash" \
    --output-format stream-json --verbose
```

Byte-identical to the registered form. `RUN_ID`, `LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` were additionally absent from the launching environment, so no lane variable leaked into the challenger; the registered `env -u` list itself is unchanged.

## Apparatus

| fact | value |
| --- | --- |
| pinned base (`main`) | `bf231bdc48c5a6d2d4af4f24aa5bf4c1b93b2194` |
| pinned head (`pr-660`) | `642a6b13d94aaab9b2de4e84edd4e8fa79f54d8a` |
| pre-run assertion | both `git rev-parse` tests passed; clone tree clean |
| `plugins/` in the working tree | present (spec D-1) |
| exit code | `0` |
| stderr | empty |
| wall clock | 2026-09-03T10:34:37Z → 2026-09-03T11:10:31Z |
| capture | 5,656,308 bytes, 2,035 lines, sha256 `1f1576d287976236…` |
| `tools/classify-capture.sh` | exit 0 — [classify-capture] COMPLETE — /private/tmp/c2-c-660.stream.json ran to completion successfully (subtype=success, is_error=false). |
| parent `tool_use` | `Read` 4, `ReportFindings` 2 |
| subagent `tool_use` | `Bash` 354, `Grep` 9, `Read` 104 |
| `result` events | 2 |
| tool calls touching `review-lean` | 0 |

Only an exit-0 capture is scored (§B *A capture must be proven complete before it is scored*); this one classified `COMPLETE`, so its findings were read out of it.

---

## Report-tool sink — `ReportFindings` call 2 of 2 (the last governs)

```json
{
  "level": "max",
  "findings": [
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 2759,
      "category": "correctness",
      "verdict": "CONFIRMED",
      "short_summary": "cmd_mark still queries --state open, so AC-8 does not work",
      "summary": "`cmd_mark` carries its own `gh pr list --head \"$LEAN_BRANCH\" --state open` lookup that the MERGED widening never reached, so milestone 5 still reds on a merged PR \u2014 the exact defect AC-8 was filed to remove.",
      "failure_scenario": "Operator merges the lane PR, then runs `bash G close-out 642`. `resolve_open_pr` now returns the MERGED PR (rc=0), so close-out writes the cost block, the cost-log row, patches the PR description and posts the closing comment. It then calls `cmd_5`, which calls `cmd_mark` (line 4647; 4616 on the jira arm). `cmd_mark` runs `--state open`, gets `[]`, and returns 1 at line 2764 before ever reaching the existing-marker no-op at 2787. `block_milestone 5 \"could not stamp the build identity on the PR\"` reds milestone 5, `cmd_teardown` never runs. Reproduced: `LEAN_GATE_LIB=1 . lean-gate.sh` with a stub gh returning `[]` for `--state open` and a MERGED PR for `--state all` gives `resolve_open_pr rc=0` and `cmd_mark rc=1`. Live by default \u2014 BOT_ENABLED defaults true under tracker.type=github."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4891,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "Merged-PR retry re-posts the closing comment each time",
      "summary": "Widening the resolver moved the merged-PR refusal from before the close-out's public writes to after them, and `closeout_comment` has no idempotence guard.",
      "failure_scenario": "Pre-#642, `resolve_open_pr` refused at line 4852 before anything was written. Now it succeeds on MERGED, `closeout_comment` POSTs (it deliberately carries no `<!-- stage: -->` marker, so nothing dedupes it), then `cmd_5` \u2192 `cmd_mark` reds per finding #1. Each retry re-posts. Because the identity-stamp red now runs on ABSENT_BUDGET=10 rather than FIX_BUDGET=3, a bot-enabled consumer accumulates up to ten duplicate '\ud83e\udd16 Closed out by /dev-pipeline:build-lean' comments on the tracker issue \u2014 public writes the lane cannot revert, on the exact scenario the ticket added support for. `closeout_patch_pr_body` is idempotent; `closeout_comment` is not."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4848,
      "category": "correctness",
      "verdict": "CONFIRMED",
      "short_summary": "close-out still charges fix budget for the demoted facts",
      "summary": "The absent-verb demotion was applied to `cmd_5` but not to `cmd_close_out`, so the same two conditions charge FIX_BUDGET or nothing depending only on which subcommand asked \u2014 and close-out is the path the scheduler actually takes.",
      "failure_scenario": "Verified by reading both sites: `cmd_5` uses `block_milestone 5 \"progress file is not current\u2026\"` (4565) and `block_obligation exit-artifacts` (4581); `cmd_close_out` still uses `fail_milestone 5` for the identical two facts at 4848 and 4852. `orchestrate-lean.sh`'s `closeout_rc()` invokes `bash G close-out`, never `bash G 5`. An orchestrated close-out with a stale milestone record or a transient `gh` outage appends `| milestone-5 | attempt |` and charges the 3-attempt budget; the scheduler retries once per round, so three rounds return rc=4 and `terminal verdict-budget-spent` fires on an announcement #642 declared free. The budget counter is shared, so `bash G 5` on the same branch then returns 4 too. `tools/gate-ablation-classes.tsv` matches both emitters on message text and labels both points 'ABSENT-verb since #642', so every future ablation report claims these points spend no fix budget while half their firings do. Line 4852 also writes no `obligation` row, unlike 4581, so `closeout_report` prints `exit-artifacts: not recorded` for the run that failed on exactly that obligation."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3857,
      "category": "correctness",
      "verdict": "CONFIRMED",
      "short_summary": "lane_advisory swallows the reserved infra exit code 3",
      "summary": "`lint`, `test` and extraLanes no longer reach `lane_failure_class`, so the reserved `LANE_INFRA_RC=3` ('nothing was evaluated, re-invoke') is recorded as an ordinary advisory red and milestone 3 concludes green.",
      "failure_scenario": "This repo's own `test` lane is `tools/run-selftests.sh`, which exits 3 when every failing suite is the no-verdict class \u2014 the workers were killed, so nothing was learned about the tree (run-selftests.sh:710). Before: `fail_milestone 3 \u2026 \"$(lane_failure_class 3)\"` returned INFRA_CLASS=7, charged nothing, and the scheduler re-spawned the build session. Now: `lane_advisory \"test failed (rc=3)\"`, return 0, `pass_milestone 3 \"green gate\"`. The run proceeds to open a PR and hand off a review having never obtained a test verdict, and the distinction between 'the suite is red' and 'the suite never ran' is erased for the two lanes that actually produce the code. This is also the one case the manifesto's own condition excludes: at rc=3 the local answer is not correct-but-later, it is unknown."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3960,
      "category": "correctness",
      "verdict": "CONFIRMED",
      "short_summary": "Milestone 3 prints 'green gate' on a red tree",
      "summary": "Milestone 3 prints `\u2713 milestone-3: green gate` and appends `| milestone-3 | satisfied` on a run whose only configured verify lane went red, and #392's zero-lane guard cannot see it.",
      "failure_scenario": "A consumer configures `lint` and `test` with `typecheck` null and no extraLanes \u2014 a shape config-lint accepts, and this repo's own dogfood config leaves typecheck null. Both lanes exit 1. `any_verifying` is set at line 3847 BEFORE the lane runs, so it is 1 and the 'must not report green having verified nothing' guard at 3885 is skipped; each red takes the `*)` arm and records only an advisory row; line 3960 writes the satisfied row. `m5_missing_milestones` (4515), `progress_token`'s satisfied count, the retro corpus and `bash G progress` all read milestone 3 as green, and gate-ablation.awk explicitly does not count `advisory` rows as firings. Milestone 3 in that config is structurally incapable of redding on a lane result \u2014 the exact state the guard was written to make impossible."
    },
    {
      "file": "plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh",
      "line": 730,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "Scheduler's resolve_pr still lists --state open only",
      "summary": "The scheduler's own PR resolver was not widened alongside the gate's, so the two now disagree about what 'this lane's PR' is and the post-merge loop AC-8 describes is still blocked one layer above the gate.",
      "failure_scenario": "`resolve_pr()` is still `gh pr list --head \"$BRANCH\" --state open --json number`. Its callers at 906 (attended) and 1019 (loop) treat an empty result as 'the build turn has not happened yet'. After the PR merges, every re-invocation of `run-lean` reads no open PR and routes to `attended_handoff BUILD \"/dev-pipeline:build-lean $ISSUE\"` (terminal 9) \u2014 forever. The lane never reaches `verdict_rc`, never reaches close-out, and the run's cost-log row is never written, which is verbatim the failure mode quoted in the #642 rationale at lean-gate.sh:4540-4542."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 2197,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "progress_token cannot see absent or advisory rows",
      "summary": "`progress_token` counts only `satisfied` and `attempt` rows, so the five sites converted to `absent` and the new `advisory` rows leave the scheduler's continuation token unmoved \u2014 and its header stating those are 'the only rows a milestone EVALUATION writes' is now false.",
      "failure_scenario": "A BUILD continuation whose only gate write is a milestone-5 refusal (transient `gh` outage \u2192 `LEAN_PR_ERROR`) or a milestone-3 advisory leaves `tok_after == tok_before` and `infra_after == infra_before`, so orchestrate-lean.sh:1074 fires `terminal build-idle 1 \"no open PR on '$BRANCH' after the BUILD session \u2014 nothing to review\"`. Before #642 the `attempt` row moved the token and the loop spent a continuation and re-spawned BUILD, which succeeded on retry. The run now hard-stops on a transient network error while telling the operator the session was idle, when the record shows it refused. The (pg) selftest fixture at lean-gate-selftest.sh:6004 contains no `absent` or `advisory` row and was not extended."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4897,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "Teardown keeps the worktree forever on the merged path",
      "summary": "Nothing downstream of `resolve_open_pr` was re-examined against MERGED: `cmd_teardown` \u2192 `worktree_destroy` \u2192 `worktree_inflight` requires `refs/remotes/origin/$LEAN_BRANCH` to resolve, which delete-branch-on-merge has removed.",
      "failure_scenario": "On the merged path the fetch at line 1947 fails and the predicate at 1948-1949 returns 1 ('origin/<br> is unresolvable, so nothing proves its work is pushed'), so the worktree is KEPT \u2014 permanently, since re-running cannot make a deleted branch reappear. The stale-remote-ref comment at 1944-1946 argues this is 'wrong only ever in the SAFE direction', which was true only while merged PRs could not reach teardown at all. The scenario #642 enables ends with `teardown: kept (\u2026)` in the obligations report and a lane worktree no automated path will ever remove \u2014 the manual rescue close-out exists to eliminate. Also unreviewed on merged: `cmd_5`'s draft assertion (4585) is vacuous, and `closeout_patch_pr_body` rewrites the description of a PR whose review is closed."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 2495,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "entry sweep reaps a merged lane's worktree before close-out",
      "summary": "`cmd_entry_sweep` destroys the worktree of any lane branch with no OPEN PR, counting MERGED as reapable \u2014 never reconciled with AC-8's premise that close-out survives a merge.",
      "failure_scenario": "`n_open` comes from `--state all` filtered to OPEN (2482-2496, pinned by selftest (wt9)), and the sweep skips only the CALLER's own worktree (2470). Operator merges lane A's PR before its close-out; any other lane's `bash G entry` \u2014 routine on a multi-lane host \u2014 sees `n_open == 0` for A's branch and reaps A's worktree. `cmd_close_out` then cannot run at all (`require_lane_tree`, rc=9; or `worktree-missing`/rc 3 from the scheduler), so the state #642 made reachable is destroyed by an unrelated lane in the window between the merge and the close-out."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 1628,
      "category": "correctness",
      "verdict": "CONFIRMED",
      "short_summary": "block_milestone copies fail_milestone, drops the INFRA arm",
      "summary": "`block_milestone` is a 17-line copy of `fail_milestone` that has already diverged: it takes a `class` argument 'mirroring fail_milestone' but omits the `INFRA_CLASS` short-circuit on both the observe and the recording path.",
      "failure_scenario": "Verified by reading both bodies (1585-1608 and 1628-1645): they differ only in the row verb, the counter, the budget constant and two warn strings \u2014 everything else, including the observe arm, the exhaustion line and the class return, is duplicated. `fail_milestone` honours `class == $INFRA_CLASS` at 1589 and 1594-1598 so an infra red spends nothing and can never report 4. `block_milestone` has neither arm, so the first caller writing `block_milestone <n> \"\u2026\" \"$INFRA_CLASS\"` \u2014 the natural call the new signature invites, already modelled by the call site at 3856 \u2014 appends an `absent` row, charges ABSENT_BUDGET, prints '(absent N/10 \u2014 not a fix attempt)' instead of the INFRASTRUCTURE wording, and on the eleventh call returns 4, telling the caller 'out of attempts' about a call that by contract took none. That is exactly the inversion the comment at 1579-1584 says the class exists to prevent. #642 widened block_milestone from one call site to four without closing the gap. One `record_red <verb> <counter> <budget> <milestone> <reason> [class]` would carry both and would have carried the INFRA arm to both for free."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3855,
      "category": "design",
      "verdict": "CONFIRMED",
      "short_summary": "Blocking-vs-advisory hard-coded to lane name, no opt-in",
      "summary": "Blocking-vs-advisory is encoded as a hard-coded lane NAME plus an unconditional `lane_advisory` for every extraLane, rather than as a property of the lane \u2014 so every consumer inherits this repo's CI topology with no way to opt out.",
      "failure_scenario": "`case \"$key\" in typecheck) fail ;; *) lane_advisory ;; esac` encodes 'my merge boundary re-runs lint/test' as a global truth in shipped plugin code. Nothing reads the consumer's CI, and grep for '642' returns no opt-out key, env var or flag. A consumer whose CI does not re-run its `test` lane, or whose extraLane is by definition repo-specific (the schema's own slot for 'an integration/e2e tier'), silently loses milestone 3's only real gate on plugin upgrade. The schema already carries the slot: `extraLanes[].failureClass` is `required` (schema/second-shift.config.schema.json:131) and config-lint enforces its enum, yet nothing in the gate reads it at run time \u2014 it is now pure ceremony. The Changelog's migration remedy ('configure the lane under `typecheck`, which still blocks') asks consumers to file a test suite under the typecheck key, which then also mis-anchors the reserved infra-code contract. A `blocking: true|false` on the lane, defaulted per key, is the depth this belongs at."
    },
    {
      "file": "schema/second-shift.config.schema.json",
      "line": 127,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Schema still says extraLanes block; failureClass now dead",
      "summary": "The cross-repo JSON schema was not touched and still documents the blocking behavior #642 removed, including a `required` `failureClass` that the gate no longer reads.",
      "failure_scenario": "`extraLanes.description` reads 'No advisory mode \u2014 a lane blocks lean-gate.sh milestone 3 or it does not exist'; `failureClass.description` (:139) reads 'Blocking; the attempt-budget behavior belongs to the consuming lane'; the sibling `lanes` description (:113) routes users to extraLanes 'for additive VERIFY-style lanes that carry a real failure class and the standard fix budget'. Since `lane_advisory` (3945) every extraLane failure is rc-0 advisory with no budget. A consumer configures an e2e tier on the schema's written promise that it blocks; the lane reds, milestone 3 exits 0, and the session opens a PR against a branch the consumer believed was gated. `docs/extending.md` carries the same claim at lines 108, 174, 314 and 367 ('a blocking verify lane with a real failureClass', 'nonzero \u2192 TEST_FAILURE, standard budget'), and `docs/onboarding.md:293` repeats it."
    },
    {
      "file": "docs/config-schema.md",
      "line": 22,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Reserved exit-3 cross-repo contract left stale and now false",
      "summary": "The cross-repo reserved-exit-code-3 contract still says milestone 3 classifies a `3` from lint/test/extraLanes as infrastructure, which #642 made false \u2014 and both updated docs point consumers here as the authority.",
      "failure_scenario": "Lines 22-29 still read: exit 3 'applies to the fixed lint/typecheck/test keys and to every extraLanes entry \u2026 milestone 3 reads a 3 as infrastructure: it reds with exit 7 \u2026 charges no fix attempt, and the lean scheduler re-spawns the build session', and 'the failure direction is a run that retries when it should have stopped \u2026 never a red branch reported green'. All three sentences are now false for lint, test and extraLanes. The doc's own stated mitigation ('Have such a lane exit any other non-zero code') is useless because every non-zero code on those keys is advisory. lean-gate.sh:219 and docs/testing.md:105 were both updated for #642 and both cite this file as 'the cross-repo contract', so a reader reconciling them cannot tell which is authoritative."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3796,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "lane_advisory writes to the record under LEAN_GATE_OBSERVE",
      "summary": "`lane_advisory` calls `append_line` with no `LEAN_GATE_OBSERVE` guard, making it the only new verdict-recording path in the file that ignores the seam.",
      "failure_scenario": "`fail_milestone` (1587), `block_milestone` (1630) and `pass_milestone` (1648) all check the seam first; lean-gate.sh:4952 states 'Observe promises to record nothing' and 4956-4962 explicitly dispatches `3) cmd_3` under it. So `LEAN_GATE_OBSERVE=1 bash G 3 <issue>` on a branch with a red lane creates the progress file (healing its run_id header) and appends `| milestone-3 | advisory | \u2026`; the subsequent real evaluation appends it again, since `append_line` is not deduped. `tools/gate-ablation.awk:117/244` publishes per-milestone `advisory` counts as a headline metric, so the row #642 is scored on is double-reported. `block_obligation`/`fail_obligation` (1439-1449) have the same exposure via `append_obligation` \u2192 `ensure_progress_file`, and `run_milestone`'s observe arm does dispatch `5) cmd_5`."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3945,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "Config-derived newlines land raw in the progress record",
      "summary": "`lane_advisory` interpolates config-derived command text straight into an append-only record row with no newline sanitization, and this is the site reached with the least-controlled string.",
      "failure_scenario": "`$el_cmd` comes from `jq -r '.[$i].commands[$j]'` on the consumer's config and can contain literal newlines (a heredoc or multi-line shell snippet \u2014 both valid JSON strings config-lint accepts). `append_line` is a bare `echo \"$1\" >> \"$PROGRESS_FILE\"` (1344), so the second line is written raw and un-timestamped into a record whose readers treat every line as a first-class row. `count_matches` is a fixed-substring grep, so a continuation line containing `| milestone-5 | satisfied` makes `m5_missing_milestones` (4512) and `progress_token --satisfied 5` report a milestone 5 that was never certified, and orchestrate-lean.sh:1136 exits `terminal lane-closed-out 0` over an unfinished run. Milestone 2's own advisory row already applies the fix (`tr '\\n' ' '`, line 3293)."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4552,
      "category": "correctness",
      "verdict": "PLAUSIBLE",
      "short_summary": "resolve_open_pr's jq: `//` fires on null, non-objects abort",
      "summary": "Two jq semantics problems in the new selection program: `(.state // \"OPEN\")` classifies an explicit JSON `null` as OPEN and outranks a genuinely MERGED sibling, and a non-object element aborts the whole program into a misleading 'no PR found' error.",
      "failure_scenario": "(a) `//` fires on `null` and `false`, not just an absent key, and the OPEN bucket is concatenated first \u2014 so `[{\"number\":8,\"state\":null},{\"number\":9,\"state\":\"MERGED\"}]` resolves to #8. `cmd_5` then reads `.[0].isDraft` \u2192 null, `draft != \"false\"`, and reds 'PR \u2026 is still a draft (D-27 requires a ready PR)', three hops from the cause. (b) If any element is not an object, jq aborts with 'Cannot index string with string' (exit 5); `2>/dev/null` swallows it, `pr` becomes empty, and `jq -e` on empty input exits 4 \u2014 so a shape error is reported as 'no open or merged PR found for branch $LEAN_BRANCH' and, via `block_obligation`, charges the ABSENT budget."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4647,
      "category": "design",
      "verdict": "PLAUSIBLE",
      "short_summary": "cmd_mark's five failure meanings collapse onto one verb",
      "summary": "`cmd_mark || block_milestone 5 \"could not stamp the build identity on the PR\"` routes a return code with at least five distinct meanings onto the single announcement verb, where only one of them is 'the checklist's next step has not happened yet'.",
      "failure_scenario": "cmd_mark returns 1 for: no open PR found (2764), comment-trail fetch failure (2772), the #446 session-not-in-recorded-build-set refusal (2813), a bot API POST failure, and a genuinely not-yet-posted marker. The identity refusal is a P10 self-review / fabrication defense \u2014 the strongest identity the merge boundary compares (2810-2812) \u2014 and is now recorded as `| milestone-5 | absent |` ('an artifact that was never written') on the 10-call ABSENT budget, so a review session mistakenly driving close-out retries ten times and leaves a record reading as bookkeeping rather than an identity violation. An expired bot token likewise burns ten calls with `attempt_count` reading 0 throughout, so the retro corpus records the run as having spent no fix rounds on a failure that consumed ten. gate-buckets.tsv:134 classes the site on a rationale true for one of the five reasons."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/SKILL.md",
      "line": 32,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Checklist step 9 contradicts itself in one sentence",
      "summary": "Step 9 adds 'a MERGED PR satisfies milestone 5' and leaves 'milestone 5 requires an open PR' standing twenty words later as the justification for the label rule.",
      "failure_scenario": "The line reads '\u2026asserts milestone 5 \u2014 which a MERGED PR satisfies as well as an open one (#642), so close-out stays reachable after a merge \u2026' and then 'But **leave the claimed label alone**: milestone 5 requires an open PR, so review is still in flight and the label is correct.' A session closing out a merged PR follows the second clause and leaves `in-progress` on an already-merged ticket; the stated fallback ('the repository's unclaim workflow releases it when the item closes') fires on issue close, not PR merge, and rests on the premise #642 removed. The same false premise also teaches the operator that close-out is unreachable post-merge \u2014 the regression AC-8 exists to fix."
    },
    {
      "file": "tools/gate-ablation-classes.tsv",
      "line": 58,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Demotion rationales cite counts from the retired corpus",
      "summary": "Rows added by this PR cite firing counts from the retired 52-record corpus while the same PR regenerates the report against a 74-line/70-record one.",
      "failure_scenario": "Line 58 says m5/progress-current is 'ABSENT-verb since #642 (adjudicated `unchanged` 3/3)' \u2014 the re-cut report gives it 0 firings and lists it under Never fired (docs/gate-ablation.md:213, 464); scripts/gate-buckets.tsv:228 repeats the dead claim. Line 45 says m3/test's '13 firings \u2026 were all adjudicated `changed`' \u2014 the report says 36. Line 50 says m4/verdict-absent is 'unchanged 4/4' \u2014 24. Line 65 says m5/identity-stamp is 'unchanged 2/2' \u2014 3. Line 63 calls m5/verdict-reference:closing-comment 'the second-largest firing class in the corpus' \u2014 at 8 it is fifth, behind spec-absent 83, test 36, verdict-absent 24 and no-open-pr 17. `gate-ablation.sh check` is not wired into CI, so nothing reconciles these against the block; a successor slice ranking points by volume demotes the wrong one on a number that does not exist."
    },
    {
      "file": "tools/gate-ablation-adjudication.tsv",
      "line": 29,
      "category": "docs-consistency",
      "verdict": "PLAUSIBLE",
      "short_summary": "Adjudication table untouched while the corpus was replaced",
      "summary": "The manifest was replaced with a wholly disjoint record set while the adjudication table was left alone, so every citation names a record absent from the pin, two rows are orphans, and the AC-4 false-red floor silently collapsed to zero.",
      "failure_scenario": "Citations 528, 375, 356, 357, 345, 346, 531, 516, 500 appear in no row of docs/gate-ablation-manifest.tsv. The generator hard-fails only on a gate point with NO adjudication row; it never checks that a citation resolves, and has no orphan check \u2014 so the rows for `m4/head-missing` and `m4/head-tree-diff` (41-42) survive gate points this PR deleted, while docs/gate-ablation.md:138 still cites m4/head-missing as a live never-fired example. Two visible consequences: the Earn-your-keep table (477-479) pairs first-firing dates from the NEW corpus with 'what changed' narratives about records 528 and 375, and the only `false_red yes` row (531:m5/exit-artifacts:no-open-pr, line 46) is keyed to a dropped record, so the AC-4 floor went from 1 firing to '**Lower bound: 0 firings.**' with an empty table and no diagnostic. An auditor following the report's own instruction \u2014 'read the cited record' \u2014 cannot resolve a single one."
    },
    {
      "file": "docs/gate-ablation.md",
      "line": 104,
      "category": "docs-consistency",
      "verdict": "PLAUSIBLE",
      "short_summary": "Re-cut banner's absent-verb claim contradicts its own tables",
      "summary": "The banner says six points 'now record under the `absent` verb' and are 'visible in it directly', but the generated block 100 lines below contradicts it for five of the six \u2014 and a historical corpus cannot show a verb change at all.",
      "failure_scenario": "The Decision points table shows m4/verdict-absent 24 attempt / \u2014 absent (205), m5/exit-artifacts:no-open-pr 17 / \u2014 (213), m5/verdict-reference:closing-comment 8 / \u2014 (214), m5/identity-stamp 3 / \u2014 (220), and m5/progress-current in the Never-fired table (464). Only m1/spec-absent has `absent` rows and those predate #642. The banner is the one paragraph a reader consults to know which figures are current: a reviewer verifying AC-3 reads it, believes the tables evidence the widening, and passes the AC on a table showing zero `absent` firings for five of the six named points. The genuine evidence for AC-3 lives only in the selftest."
    },
    {
      "file": "docs/gate-ablation.md",
      "line": 46,
      "category": "docs-consistency",
      "verdict": "PLAUSIBLE",
      "short_summary": "Method and Reproducing sections still describe the old pin",
      "summary": "Three prose blocks above the 'read them as dated' banner still describe the retired 52-record pin, and the banner explicitly scopes only 'the numbered findings that follow'.",
      "failure_scenario": "Line 46: 'the mechanical column resolves to a real content diff for **six** firings' \u2014 the regenerated block has 3. Lines 54-56: 'only 10 of 52 records reach `milestone-4 satisfied` and 6 reach `milestone-5 satisfied`' \u2014 the Corpus table (178-179) now says 31 and 27 out of 70, which materially weakens the `no-response` disclaimer's whole argument ('it is mostly a statement about record truncation'). Line 99's '(74 records pinned, 70 scored)' reads 74 off the file's line count (4 are comments), describing a pinned\u2260scored state `gate-ablation.sh` cannot produce, since it exits 3 on any row that does not hash clean. Lines 71-73 and 87-90 describe a three-lane registry-era manifest header ('cut against three (`546 609 611`)') that this PR's own manifest diff deleted \u2014 the re-cut header names exactly one, `642`. That paragraph exists to teach the one thing `--exclude` cannot recover from, and its worked example no longer matches the file."
    },
    {
      "file": "docs/testing.md",
      "line": 31,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Never-fired table disagrees with the report in the same PR",
      "summary": "The new 'Never-fired decision points' table disagrees with the ablation report regenerated in the same PR about which points never fired.",
      "failure_scenario": "The Kept(18) table lists `m1/ledger-lint` and `m1/preflight-reconcile` as never-fired-but-reachable, while the re-cut report records 4 and 2 firings for them (docs/gate-ablation.md:190-191). It omits `m3/lint`, `m4/chain-break`, `m4/patch-stale` and `m5/progress-current`, which the re-cut report's Never-fired table (442) now contains. This section is a live reference doc, not a dated report, so the reachability argument it is supposed to carry is attached to the wrong points."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 1622,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "block_milestone header cites a never-fired point as evidence",
      "summary": "The `block_milestone` header claims the absent-verb set is 'exactly the reasons docs/gate-ablation.md adjudicates `unchanged`' and names m5/progress-current, but the report regenerated in this same PR lists that point under 'Never fired' with zero firings.",
      "failure_scenario": "AC-3's oracle is the report's adjudication. The re-cut corpus (436-440) yields five demotion candidates \u2014 m1/spec-absent, m4/verdict-absent, m5/exit-artifacts:no-open-pr, m5/verdict-reference:closing-comment, m5/identity-stamp \u2014 while the code converts six, including m5/progress-current, which line 458 now lists as never fired. A future reviewer checking the comment against the report finds one point the evidence does not support, and the selftest's hard-coded count of 8 absent-verb sites (ac1b) pins the implementation rather than the oracle."
    },
    {
      "file": "docs/gate-ablation.md",
      "line": 470,
      "category": "docs-consistency",
      "verdict": "CONFIRMED",
      "short_summary": "Earn-your-keep table names the points being demoted",
      "summary": "The regenerated report names m3/test and m3/extra-lane in its 'Earn-your-keep' table \u2014 points with a firing adjudicated as changing what shipped \u2014 and the same commit demotes both to advisory, with no reconciliation.",
      "failure_scenario": "docs/pipeline-manifesto.md:101 (added by this PR) states a point is demotable 'only where CI duplication is DEMONSTRATED and where deleting the local refusal leaves the local answer correct-but-later rather than wrong'. The report shipped in the same commit is the artifact that says m3/test blocks for a reason \u2014 36 firings adjudicated `changed` and the corpus's single largest rework figure \u2014 and m3/extra-lane 8. The CI-duplication claim lives only in the Routing section, which the report itself heads 'not part of the measurement'; its extraLane row points at `mutation-sweep-pr`, which #580 deleted from milestone 3, so the one extraLane whose duplication was ever demonstrated no longer runs there. Meanwhile m3/lint \u2014 also demoted \u2014 has zero firings, so nothing was measured for it at all. A reader auditing the demotion against the evidence finds the evidence arguing the other way."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
      "line": 1691,
      "category": "test-coverage",
      "verdict": "CONFIRMED",
      "short_summary": "AC-8's oracle is vacuous: fixture bypasses the live query",
      "summary": "AC-8's coverage is vacuous: (k7)/(k10) drive the merged-PR path through `--pr-file`, which `cmd_mark` reads through the same `$PR_FILE` global, so the fixture answers cmd_mark's open-PR query with the merged fixture.",
      "failure_scenario": "`bgate 5 7 --pr-file \"$WORK/pr-merged.json\"` makes both `resolve_open_pr` and `cmd_mark` read the same file (cmd_mark honours `$PR_FILE` at 2755), so the `--state open` query never happens and finding #1 cannot red the case. The scenario suite has the same hole: its fake gh's `pr)` arm routes anything without `--json number,state` to the OPEN fixture (scenario-liveness-selftest.sh:1545-1547), so cmd_mark is served an open PR there too. A case that stubs `gh` to answer `[]` for `--state open` and a MERGED PR for `--state all` \u2014 the shape the real defect has \u2014 is what AC-8 needs, and is what both suites lack."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh",
      "line": 1952,
      "category": "test-coverage",
      "verdict": "PLAUSIBLE",
      "short_summary": "New gate contracts composed by no scenario leg",
      "summary": "Neither AC-8 nor the absent-verb widening is composed by any scenario leg, against CLAUDE.md's explicit 'a new gate contract extends the liveness scenario for every verdict path it touches'.",
      "failure_scenario": "This diff went into the very leg that would carry AC-8 \u2014 `lean-closeout`, which composes scheduler \u2192 real `bash G close-out` in a real worktree \u2192 the gate's writes \u2192 the `| milestone-5 | satisfied` row \u2014 and pinned its PR fixture to `\"state\": \"OPEN\"` (this line, plus :1491 and :1759) rather than adding a merged leg; `grep -i merged` over the file returns only a `git merge` and a stub comment. Likewise `grep 'absent |'` returns only milestone-1 and milestone-4 rows: `block_milestone 5`, ABSENT_BUDGET and the `absent-exhausted` rc=4 hard stop never execute outside a `--pr-file` fixture. The per-tool cases also do not state why no scenario covers them, which the Scenario-first rule requires. Finding #1 is precisely the failure this rule predicts: (k7)-(k10) green, live path permanently red."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
      "line": 6120,
      "category": "test-coverage",
      "verdict": "PLAUSIBLE",
      "short_summary": "Both new guards miss the drift they claim to detect",
      "summary": "`(ac1)`'s 'all 18 milestone-4 failure sites carry an explicit class' is no longer true of the file it inspects, and its companion `(ac1b)` cannot detect the regression its own comment names.",
      "failure_scenario": "(ac1) greps only `fail_milestone 4 \"`, but this diff moved the verdict-absent site to `block_milestone 4 \"...\" 5` (lean-gate.sh:3980) \u2014 19 sites, one outside the checked set. Drop the trailing `5` and `block_milestone` applies its `class=\"${3:-1}\"` default, so an absent verdict returns 1 instead of 5 and a scheduler re-spawns BUILD to fix code that was never judged; (ac1) counts 18 and passes, (ac1b) counts 8 and passes. (ac1b)'s own comment says 'a new one added as a fail_milestone silently re-charges the fix budget, and only a whole-file count can say so' \u2014 but it counts `block_*` sites only, so that regression is invisible to it by construction, and its regex `block_milestone [145] \"[a-z]|block_obligation [a-z-]+ \"` misses a block on milestone 2 or 3, a reason starting with `$VAR` or a capital, and an added-plus-deleted pair. `scripts/check-gate-buckets.sh` already enumerates every refusal site per primitive in both directions; the verb belongs as a column there, not as a scalar in a selftest."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
      "line": 1487,
      "category": "test-coverage",
      "verdict": "PLAUSIBLE",
      "short_summary": "fixture_patch_id: 3 copies, and it can silently emit empty",
      "summary": "The library-mode patch-id incantation exists in three hand-maintained copies, and its `&&` chain cannot detect the failure it guards against, because `branch_patch_id` returns 0 with empty stdout when the merge-base lookup fails.",
      "failure_scenario": "`fixture_patch_id` (1487) is copied verbatim at 4392 (differing only in `$PTREE`/`acme-8` vs `$TREE`/`acme-7`) while `lean_pid` in scenario-liveness-selftest.sh:251 is already the generalized form \u2014 give `fixture_patch_id` that signature and call it from both. The invocation is fragile in the ways its own comments enumerate (positionals consumed by the `.`, mandatory `SECOND_SHIFT_CONFIG`, `set -u` on a bare `$1`), so any change to library mode's contract must be found at three sites. Separately, lean-gate.sh:929-930 `return 0`s with empty stdout when `merge-base origin/$BASE_BRANCH <head>` fails, and the result is consumed unchecked at 1500 \u2014 #642 is what made that dangerous, since milestone 4 now hard-refuses a record with no `reviewed_patch_id` (4170-4172, class 5). A fixture tree that forgets `git update-ref refs/remotes/origin/main HEAD` writes `reviewed_patch_id: ` empty and reds every (j*)/(t*)/(v*) case with the identical rc and substring (u2) asserts as correct, pointing the debugging trail at the gate rather than the fixture. Each call also sources the whole 5232-line gate (~380ms, ~20-25 subprocesses); ~28 such sources are added across both suites."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3844,
      "category": "efficiency",
      "verdict": "CONFIRMED",
      "short_summary": "Milestone 3 no longer short-circuits on a red cheap lane",
      "summary": "Milestone 3 no longer short-circuits, so a red cheap lane now pays for every expensive lane after it, on every attempt \u2014 and the lane order was not revisited.",
      "failure_scenario": "With `lint` red, `[ \"$rc\" -eq 0 ] && continue` falls through to `lane_advisory` and the loop proceeds through `typecheck`, `test` (this repo: `tools/run-selftests.sh`, ~12 min per ci.yml:192), every extraLane, then `cmd_3_render`, which on an armed ticket boots the consumer's live-render harness per RS-n row. The ordering rationale above cmd_3_render ('cheap deterministic lanes first, then the expensive ones') existed to make fail-fast cheap and now buys nothing \u2014 nothing upstream can stop the render, so it is reached on 100% of invocations. SKILL.md mandates `bash G all` before step 9 and `cmd_close_out` re-runs milestones 1-4 itself, so one lint-red branch pays that sweep three times. Cheapest fix: run `typecheck` first, since it is now the only lane that can refuse. The extraLanes path already applies the right reasoning (`break` after an advisory red because a lane's later commands are meaningless once an earlier one red); it was not applied across lanes. Compounding it, the milestone-5 announcements moved from FIX_BUDGET=3 to ABSENT_BUDGET=10, so a session running `bash G all` before step 7 now gets ten of those full sweeps instead of three."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 4527,
      "category": "efficiency",
      "verdict": "PLAUSIBLE",
      "short_summary": "resolve_open_pr: 20 bodies, 3 jq passes, refetched per call",
      "summary": "`resolve_open_pr` widened to `--state all --limit 20 --json \u2026,body,\u2026`, runs three `jq` passes where one would do, and refetches on every call despite its header saying 'resolved once'.",
      "failure_scenario": "The selection is 'first OPEN, else first MERGED', which two narrow calls express exactly (`--state open --limit 1`, then `--state merged --limit 1` only on empty) \u2014 one 1-body round trip on the common path. Instead, a lane branch that has been re-cut accumulates closed PRs and every call transfers up to 20 full bodies, each carrying the summary, spec link and rendered cost block. `cmd_close_out` resolves at 4852 then calls `cmd_5` at 4894, which resolves the identical query again at 4581 in the same process, purely to re-read a cost block this process just wrote \u2014 a `[ -n \"$LEAN_PR_JSON\" ] && return 0` memo removes it. The `jq -e 'type == \"array\"'` pre-check at 4536 is redundant with the post-check at 4554 (a non-array makes the selection program error, `2>/dev/null` swallows it, and `jq -e` on empty input exits 4), and its only effect is to set a third copy of the `could not list PRs for $LEAN_BRANCH` literal that must stay in sync with the ablation row's pattern. `--limit 20` is an unexplained magic number in a file where every other bound is a named constant with a rationale paragraph."
    },
    {
      "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
      "line": 3864,
      "category": "docs-consistency",
      "verdict": "PLAUSIBLE",
      "short_summary": "extraLanes block comment still claims fail-fast",
      "summary": "The extraLanes block comment still describes the pre-#642 control flow ('in declaration order, fail-fast') and is contradicted by the inner comment 80 lines below it.",
      "failure_scenario": "After the demotion extraLanes do not fail fast: a red lane calls `lane_advisory` and `break`s only its own command loop (3945), the next lane runs, and milestone 3 concludes 0. The inner comment at 3942-3944 documents exactly that; the outer one was left behind. The two disagree about the one property a reader of this block most needs, and a maintainer trusting the outer comment reads `break` as the fail-fast it names and will not notice that every subsequent lane plus the armed render at 3957 still run. SKILL.md step 6 points the operator at this surface for advisory reds. Related: `lane_failure_class` (3783) now has exactly one call site while its header still opens 'ONE resolver rather than a test at each call site', which no longer describes anything, and `block_obligation`/`fail_obligation` (1439-1449) are 3-line twins differing only in which verb they call \u2014 a fork that already produced the wrong choice at cmd_close_out."
    }
  ]
}
```

The session filed 2 `ReportFindings` calls; the earlier one carries the same 32 findings under the same `file`/`line`/`summary` keys and is omitted as a superseded duplicate.

---

## Assistant text — `result` event 1 of 2

Both selftests are green (lean-gate 505/0, scenario-liveness 71/0), shellcheck is clean, `check-gate-buckets.sh`, `check-lockstep-pairs.sh` and every `mutation-catalog.tsv` sed anchor still apply. The findings below survived verification; #1 I reproduced empirically by sourcing the gate in library mode against a stub `gh`.

```json
[
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2759,
    "summary": "cmd_mark still queries `gh pr list --state open`, so milestone 5 and close-out still red on a merged PR — AC-8's stated fix does not work on the real path.",
    "failure_scenario": "Operator merges the lane PR, then `bash G close-out 642` runs. `resolve_open_pr` now returns the MERGED PR (rc=0), so close-out writes the cost block, the cost-log row, patches the PR description and posts the closing comment. It then calls `cmd_5`, which calls `cmd_mark` (line 4647; also 4616 on the jira arm). `cmd_mark` runs `gh pr list --head \"$LEAN_BRANCH\" --state open --json number,url --limit 1`, gets `[]`, and returns 1 with '✗ mark: no open PR found for branch … — open it first (checklist step 7)' — the existing-marker no-op at line 2787 is never reached because the PR lookup fails first. `block_milestone 5 \"could not stamp the build identity on the PR\"` reds milestone 5 and `cmd_teardown` never runs, so the worktree is never collected. Every retry re-posts a duplicate closing comment (`closeout_comment` has no idempotence guard). Reproduced: `LEAN_GATE_LIB=1 . lean-gate.sh` with a stub gh returning `[]` for `--state open` and a MERGED PR for `--state all` gives `resolve_open_pr rc=0` and `cmd_mark rc=1`. Live by default: BOT_ENABLED defaults to true under tracker.type=github."
  },
  {
    "file": "docs/config-schema.md",
    "line": 22,
    "summary": "The cross-repo reserved-exit-code-3 contract still says milestone 3 classifies a `3` from lint/test/extraLanes as infrastructure, which #642 made false — and the gate's own new comment points consumers at this doc.",
    "failure_scenario": "A consumer reads 'It applies to the fixed lint/typecheck/test keys and to every extraLanes entry … milestone 3 reads a 3 as infrastructure: it reds with exit 7 … and the lean scheduler re-spawns the build session', wires its integration runner to exit 3 on a killed worker under `commands.<repo>.test`, and gets a silent advisory row and milestone 3 exit 0 instead — no rc=7, no re-spawn. The doc's own stated mitigation ('Have such a lane exit any other non-zero code') is now useless because every non-zero code on lint/test/extraLanes is advisory. lean-gate.sh:219 and docs/testing.md:105 were both updated for #642 and both cite this file as 'the cross-repo contract'; this file was not."
  },
  {
    "file": "docs/extending.md",
    "line": 108,
    "summary": "extending.md still asserts 'There is no advisory mode: a lane blocks lean-gate.sh milestone 3 or it doesn't exist', and schema/second-shift.config.schema.json still documents the required `failureClass` as 'Blocking'.",
    "failure_scenario": "extraLanes are now unconditionally advisory (lean-gate.sh:3945). A consumer following extending.md §3.2 / §EP-2 (lines 108, 174, 314, 367 — 'a blocking verify lane with a real failureClass', 'nonzero → TEST_FAILURE, standard budget') adds an API-test tier expecting it to block milestone 3 and gets a lane that reports and always passes. `failureClass` is `required` in the schema (line 131) and config-lint enforces its enum, yet nothing in the gate reads it at run time — the field is now pure ceremony whose description states the opposite of the behavior."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 3960,
    "summary": "Milestone 3 prints `✓ milestone-3: green gate` and appends `| milestone-3 | satisfied` on a run whose only configured verify lane went red.",
    "failure_scenario": "A consumer configures only `commands.<repo>.test`. The lane runs, exits 1, `lane_advisory` records `| milestone-3 | advisory |`, `any_verifying` is still 1 so the #392 zero-lane guard does not fire, and `pass_milestone 3 \"green gate\"` writes the satisfied row. Every downstream reader — `progress_token`'s satisfied count, the close-out's `m5_missing_milestones`, the retro corpus, `bash G progress` — sees milestone 3 green with no indication that nothing verified green; gate-ablation.awk explicitly does not count `advisory` rows as firings. The message literally says 'green gate' on a red tree. At minimum the pass line and the satisfied row should name the advisories."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 1622,
    "summary": "The block_milestone header claims the absent-verb set is 'exactly the reasons docs/gate-ablation.md adjudicates `unchanged`' and names m5/progress-current, but the report regenerated in this same PR lists m5/progress-current under 'Never fired' with zero firings.",
    "failure_scenario": "AC-3's oracle is the report's adjudication. The re-cut corpus (docs/gate-ablation.md:436-440) yields five demotion candidates — m1/spec-absent, m4/verdict-absent, m5/exit-artifacts:no-open-pr, m5/verdict-reference:closing-comment, m5/identity-stamp — while the code converts six points, including m5/progress-current, which docs/gate-ablation.md:458 now lists as never fired. A future reviewer checking the comment against the report finds one point the evidence does not support, and the selftest's hard-coded count of 8 absent-verb sites (ac1b) pins the implementation rather than the oracle."
  },
  {
    "file": "tools/gate-ablation-classes.tsv",
    "line": 58,
    "summary": "Rows added by this PR cite firing counts from the retired 52-record corpus while the same PR regenerates the report against a 74-record one.",
    "failure_scenario": "Line 58 says m5/progress-current is 'ABSENT-verb since #642 (adjudicated `unchanged` 3/3)' — the re-cut report gives it 0 firings. Line 45 says m3/test's '13 firings … were all adjudicated `changed`' — the report says 36. Line 50 says m4/verdict-absent is 'unchanged 4/4' — the report says 24. Line 65 says m5/identity-stamp is 'unchanged 2/2' — the report says 3. Line 63 calls m5/verdict-reference:closing-comment 'the second-largest firing class in the corpus' — at 8 it is now fifth, behind spec-absent 83, test 36, verdict-absent 24 and no-open-pr 17. Anyone auditing a demotion against its cited evidence gets a number that does not exist."
  },
  {
    "file": "docs/testing.md",
    "line": 31,
    "summary": "The new 'Never-fired decision points' table disagrees with the ablation report regenerated in the same PR about which points never fired.",
    "failure_scenario": "The Kept(18) table lists `m1/ledger-lint` and `m1/preflight-reconcile` as never-fired-but-reachable, while the re-cut report records 4 and 2 firings for them (docs/gate-ablation.md:190-191, and citations 180/185/188/190 and 158/179). It omits `m3/lint`, `m4/chain-break`, `m4/patch-stale` and `m5/progress-current`, which the re-cut report's Never-fired table (line 442) now contains. The section is a live reference doc, not a dated report, so the reachability argument it is supposed to carry is attached to the wrong points."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/SKILL.md",
    "line": 32,
    "summary": "Checklist step 9 contradicts itself in a single sentence: it adds 'a MERGED PR satisfies milestone 5' and leaves 'milestone 5 requires an open PR' as the justification for the label rule.",
    "failure_scenario": "The line reads '…asserts milestone 5 — which a MERGED PR satisfies as well as an open one (#642), so close-out stays reachable after a merge …' and then 'But **leave the claimed label alone**: milestone 5 requires an open PR, so review is still in flight and the label is correct.' A build session closing out a merged PR follows the second clause, leaves the `in-progress` label on a ticket that is already merged, and the stated fallback ('the repository's unclaim workflow releases it when the item closes') does not apply because the premise it rests on — review still in flight — is exactly what #642 removed."
  },
  {
    "file": "docs/gate-ablation.md",
    "line": 470,
    "summary": "The regenerated report names m3/test and m3/extra-lane in its 'Earn-your-keep' table — points with a firing adjudicated as changing what shipped — and the same commit demotes both to advisory, with no reconciliation.",
    "failure_scenario": "docs/pipeline-manifesto.md:101 (added by this PR) states a point is demotable 'only where CI duplication is DEMONSTRATED and where deleting the local refusal leaves the local answer correct-but-later rather than wrong'. The report shipped in the same commit is the artifact that says m3/test and m3/extra-lane block for a reason ('a red selftest sweep; the remedy is a source or fixture edit, and 528 took three of them across four sessions'). Meanwhile m3/lint — also demoted — has zero firings in the re-cut corpus, so nothing was measured for it at all. A reader auditing the demotion against the evidence finds the evidence arguing the other way."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 3855,
    "summary": "Blocking-vs-advisory is hard-coded to the lane NAME in the gate rather than expressed as a lane property, so every consumer inherits this repo's CI topology with no opt-in.",
    "failure_scenario": "`case \"$key\" in typecheck) fail ;; *) lane_advisory ;; esac` encodes 'my merge boundary re-runs lint/test' as a global truth. A consumer whose CI does not re-run its `test` lane silently loses milestone 3's only real gate, with nothing in the gate, config-lint or the schema letting it declare otherwise. The Changelog's migration remedy — 'configure the lane under `typecheck`, which still blocks' — asks consumers to file a test suite under the typecheck key, which then also mis-anchors the reserved infra-code contract. The schema already carries a required per-lane `failureClass` (and `when`) on extraLanes; a `blocking: true|false` there, defaulted per-key, is the depth this belongs at."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 3850,
    "summary": "Milestone 3 no longer short-circuits, so a red cheap lane now pays for every expensive lane after it on every attempt.",
    "failure_scenario": "With `lint` red, `[ \"$rc\" -eq 0 ] && continue` falls through to `lane_advisory` and the loop proceeds: the full `test` lane still runs (this repo: `tools/run-selftests.sh`, ~5 minutes cold, and the config also names extraLanes), then every extraLane, then `cmd_3_render`, which on an armed ticket spawns the repo's browser render command per RS-n row. The ordering rationale immediately above cmd_3_render ('cheap deterministic lanes first, then the expensive ones') existed to make fail-fast cheap and now buys nothing. The extraLanes path already applies the correct reasoning — `break` after an advisory red because 'a lane's later commands are still meaningless once an earlier one red' — but the same reasoning was not applied across lanes."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 1628,
    "summary": "block_milestone is a 17-line copy of fail_milestone that has already diverged: it is missing the INFRA_CLASS short-circuit.",
    "failure_scenario": "The two functions now differ only in the row verb (`append_absent` vs `append_attempt`), the counter (`absent_count` vs `attempt_count`) and the budget constant (`ABSENT_BUDGET` vs `FIX_BUDGET`) — everything else, including the observe arm, the exhaustion line and the class return, is duplicated. fail_milestone honours `class == $INFRA_CLASS` before appending (lines 1589, 1594) so an infra red spends nothing; block_milestone has no such arm, so the first caller that passes class 7 will silently charge the absent budget. #642 widened block_milestone from one call site to four without closing that gap. One `record_red <verb> <counter> <budget> <milestone> <reason> [class]` would carry both and would have carried the INFRA arm to both for free."
  },
  {
    "file": "plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
    "line": 1691,
    "summary": "AC-8's oracle is vacuous: (k7)/(k10) drive the merged-PR path through `--pr-file`, which cmd_mark reads through the same $PR_FILE global, so the fixture answers cmd_mark's open-PR query with the merged fixture.",
    "failure_scenario": "`bgate 5 7 --pr-file \"$WORK/pr-merged.json\"` makes both `resolve_open_pr` and `cmd_mark` read the same file, so cmd_mark's `--state open` query never happens and finding #1 cannot red the case. The scenario suite has the same hole: its fake gh's `pr)` arm routes anything without `--json number,state` to the OPEN fixture (scenario-liveness-selftest.sh:1545-1547), so cmd_mark is served an open PR there too. A case that stubs `gh` to answer `[]` for `--state open` and a MERGED PR for `--state all` — the shape the real defect has — is what AC-8 needs, and is what both suites currently lack."
  }
]
```

---

## Assistant text — `result` event 2 of 2

Review complete — eight angles ran, findings deduplicated and ranked, 32 reported. Both selftests were green throughout (lean-gate 505/0, scenario-liveness 71/0), shellcheck is clean, and `check-gate-buckets.sh` / `check-lockstep-pairs.sh` pass, so nothing here is caught by the existing harness.

The shape of the review: **the PR's two headline changes are each incomplete in the same way — the predicate was widened at one site and left alone at its twins.**

- **AC-8 does not work on the live path.** `resolve_open_pr` accepts MERGED; `cmd_mark` (lean-gate.sh:2759), `cmd_close_out` (4848/4852) and the scheduler's own `resolve_pr` (orchestrate-lean.sh:730) all still ask `--state open`. On a merged PR close-out now gets *past* the resolver, performs its public writes, and then reds at the identity stamp — so the merged-PR case is strictly worse than before (duplicate closing comments, worktree never torn down), and an entry sweep from an unrelated lane can reap the worktree in the meantime. Both suites miss it because `--pr-file` short-circuits `cmd_mark` too.
- **The milestone-3 demotion loses the reserved infra code.** `lint`/`test`/extraLanes no longer reach `lane_failure_class`, so `exit 3` ("nothing was evaluated") is recorded as an advisory row and milestone 3 prints `✓ green gate`. `#392`'s zero-lane guard can't see it because `any_verifying` is set before the lane runs. The blocking/advisory decision is hard-coded to the lane *name*, while the schema's `required` `failureClass` — which says "Blocking" — is now read by nothing.

Three doc/data clusters follow from those: the un-updated cross-repo contracts (`docs/config-schema.md`, the JSON schema, `docs/extending.md`), the self-contradicting `SKILL.md` step 9, and the ablation registers, where the demotion rationales cite firing counts from the corpus this same PR retired (m5/progress-current is cited "3/3" and has zero firings in the new pin) while `gate-ablation-adjudication.tsv` was never re-cut at all.

One finding didn't fit the 32-item cap, so noting it here: the head commit is typed `feat(dev-pipeline):` but ships behavior removal plus migration prose. Per `CLAUDE.md`'s bump table and the repo's own precedent (#595, #584 — both `feat(dev-pipeline)!:` for the same shape), it needs `!` or a `BREAKING CHANGE:` footer, otherwise `derive-release.sh` cuts a minor.
