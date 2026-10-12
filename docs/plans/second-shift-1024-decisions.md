# Intake receipt — #1024 a stale remote ref never stands in for the committed record

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the check tells "unreachable" from "no such branch" | Probe first with `git ls-remote --exit-code origin refs/heads/$BRANCH` from MAIN_ROOT, replacing the `fetch \|\| true` at run.sh:932. rc 2 → not committed, read the receipt. rc 0 → fetch the branch (a failed fetch refuses env-remote-unreadable), then `cat-file -e` the record at the SHA ls-remote returned, never the tracking ref. Any other rc → env-remote-unreadable. Options weighed: the probe; keep the fetch and parse its stderr for "couldn't find remote ref" (locale- and version-dependent); `fetch --prune` with an explicit refspec (still rc 128 both ways, so it needs the stderr parse too) | user-answered | intent |
| D-2 | The stale `refs/remotes/origin/$BRANCH` when the remote says the branch is gone | Delete it with `git update-ref -d` right after the rc-2 probe, and say so in the run log, so phase 5 (run.sh:1004) cuts a fresh branch from base. Options weighed: keep it and gate phase 5 on the remote's answer (two readers of one fact) | user-answered | intent |
| D-3 | A local `refs/heads/$BRANCH`, or a worktree at $WT on $BRANCH or detached, when the remote is reachable and has no such branch | Refuse before the claim under a new slug, `env-branch-unpushed`, deleting nothing. The message names what it found and both ways out: push it (`git push -u origin $BRANCH`) to resume it, or remove the worktree and branch to start fresh from the receipt. `committed_record_exists` no longer reads `refs/heads/$BRANCH`. A worktree on a different named branch still falls through to env-worktree-mismatch (D-6). Options weighed: trust the local branch (today's behavior, which keeps the bug through another ref); ignore it and read the receipt (phase 5 would still attach to the old record) | user-answered | intent |
| D-4 | The AC-1 refusal message | `cannot reach origin to read $BRANCH — whether the record is already committed is unknown, so neither it nor the receipt is read`, in the phrasing of run.sh:750 and :754. Options weighed: a terse `cannot reach origin to check $BRANCH for a committed record` | user-answered | intent |
| D-5 | The git exit codes D-1 keys on | Missing branch on a reachable remote → 2, unreachable remote → 128, while `fetch` gives 128 for both; probed in a scratch bare-origin repo, git 2.55.0 — run: `git ls-remote --exit-code origin refs/heads/b; git fetch -q origin b; git remote set-url origin /nonexistent; git ls-remote --exit-code origin refs/heads/b` → "missing rc=2", "fetch-missing rc=128", "unreachable rc=128" | codebase-derived | fact |
| D-6 | Exit code of both refusals, and D-3's trigger | env-* exits 2, so `env-branch-unpushed` needs no exit_code_for edit — run: `sed -n 114p plugins/dev-pipeline/skills/run/run.sh` → `usage-*\|env-*\|claimed-elsewhere) echo 2 ;;`. A worktree on another branch keeps its existing refusal — run: `grep -n "fixture ad2" plugins/dev-pipeline/skills/run/run-selftest.sh` → 785: worktree on branch `other` → expect env-worktree-mismatch | codebase-derived | fact |
| D-7 | The fresh run (no branch upstream yet) | Unchanged: reachable remote, rc 2, no local branch → reads the receipt as today. Only an unreachable remote refuses earlier than before (AC-1) — run: `sed -n 1004,1007p plugins/dev-pipeline/skills/run/run.sh` → with no origin or local ref, `worktree add -q -b "$BRANCH" "$WT" "$base"` | codebase-derived | fact |
| D-8 | Interaction with #1022 | #1022's launch lint skips committed records through this check, so after this fix a stale ref no longer suppresses that lint. Nothing to change in either ticket — run: `gh issue view 1022 --json body --jq .body \| grep -c "that check's own defect is #1024"` → 1 | codebase-derived | fact |
| D-9 | Duplicate scan | No candidates — run: `dup-scan.sh --issue 1024` → "no candidates at or above threshold 12" | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The env-remote-unreadable refusal at preflight when the probe cannot reach origin | decided (D-4) |
| S-2 | The env-branch-unpushed refusal and its two ways out | decided (D-3) |
| S-3 | The run-log line when a stale tracking ref is deleted | decided (D-2) |
| S-4 | The existing "record: already committed" and receipt-path log lines | decided (D-1) |
| S-5 | SKILL.md's exit-code table and run.sh's header slug list | decided (D-6) |
| S-6 | The base fetch at run.sh:944 (`git fetch -q origin \|\| true`), which has the same stale-ref pattern for origin/<base> | out-of-scope — not this check; named to the operator for filing |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
