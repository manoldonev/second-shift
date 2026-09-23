---
name: run
description: The pipeline's front door — one ticket in, a merge-ready PR out. Drives run.sh, a scheduler that claims the ticket, commits its intake record, and spawns fresh build and review sessions until a review approves the current head or a budget is spent; you author nothing. Expects a ticket with paid-off intake: an intake record, plus the queue label on GitHub (under jira there is no label to check, so launching is the operator's attestation).
---

# run

You drive `run.sh` (`R`, here — it sits beside this file, in this skill's base directory). It does
the whole lane: claim → worktree on the lane branch → the intake record committed as the branch's
first commit → up to `run.maxRounds` rounds of a fresh BUILD session, the scheduler's own checks
(config lanes plus the record's `## Checks`, read from that first commit) and route smoke, then a
fresh REVIEW session whose one PR comment is the verdict. `bash R -h` prints the header: usage,
env, phases and the exit table. It is the truth; this file only says what is yours to do.

## Checklist

1. **Route.** Launch from a checkout of the repo the ticket belongs to: the cwd picks the repo, and
   `R` resolves the config, the worktree root and the `commands` key from that repo's main
   checkout, even when launched from a linked worktree.
2. **Resolve the build model.** On GitHub, `R` reads the ticket's `opus` / `sonnet` label itself.
   No label, or under jira (there is no label to read), size it yourself and pass
   `--build-model <opus|sonnet> --model-basis 'sized-here: <one line>'` — that line is the whole
   record that the sizing was yours. Review runs on `opus`; a different `--review-model` needs
   `--review-model-basis`.
3. **Launch detached, then watch.** `bash R <issue> [--build-model <m> --model-basis <why>] --detach`.
   From an agent session `--detach` is the launch that works: a foreground call is reaped long
   before a run ends (a build session alone may take two hours). It prints the log path; watch that
   log until its last line, `detached run exited rc=<n>`. `--dry-run` previews and writes nothing.
4. **Read the terminal and nothing else.** The log's `terminal: <slug>` line and `rc` are the whole
   signal:

   | rc | slugs | what you do |
   | --- | --- | --- |
   | `0` | `approved`, `dry-run` | Report the PR. Merging is a human's act. |
   | `1` | `build-no-pr`, `build-blocked`, `build-inflight(-unreadable)`, `pr-ambiguous`, `closeout-inflight(-unreadable)`, `staleness-unreadable` | Stop and report the slug and its detail line; a human decides. Worktree and claim are left in place. |
   | `2` | `usage-*`, `env-*`, `claimed-elsewhere` | Fix what the detail line names and re-launch the same command. On `claimed-elsewhere`, stop: `--resume` takes over someone else's claim, and that is the operator's call. |
   | `3` | `not-queued`, `env-no-record` | Resumable. Pay off intake (`/intake-toolkit:intake`, or `/intake-toolkit:plan-interview <issue>` for a missing record) and re-launch the same command. |
   | `4` | `rounds-spent`, `checks-red-spent`, `cost-spent` | Stop. A spent budget is a human's read, never an automatic re-launch. |
   | `5` | `review-unbound` | Run `/dev-pipeline:review <pr>` by hand in a fresh session: a rebuild fixes nothing. |
   | `7` | `ticket-closed`, `staleness-expired` | Closed: stop. Stale: the base moved into this branch's files — rebase the branch, then re-launch; the claim marker lets it re-enter. |
   | `130` / `143` | interrupted | The claim is left in place; re-launch to re-enter. |

## Rules that are not negotiable

- **Never re-label a ticket to get past a reject.** A ticket the lane claimed re-enters on its own
  claim marker; a blocker label is someone's decision, not an obstacle.
- **You author nothing.** Claim, record commit, cost block and closing comment are `R`'s writes
  (through the bot when one is configured); code and PR are the build session's; the verdict is the
  review session's. A write of yours would be a third identity in that record.
- **Never interpret a finding.** The terminal is the signal. Reading the verdict to decide what
  comes next is content judgment the lane does not ask of you.
- **Never resume a review context.** Every review is a fresh process; a round inheriting the last
  round's context is that round agreeing with itself.
