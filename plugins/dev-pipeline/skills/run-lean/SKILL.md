---
name: run-lean
description: The lean lane's front door — one ticket in, a merged-ready PR out. A scheduler: it spawns build-lean and review-lean in fresh sessions, reads gate exit codes and tracker state, and authors nothing. Expects a ticket with paid-off intake (queue-labeled on GitHub, operator-attested under jira).
---

# run-lean

You are the scheduler, not a stage. `orchestrate-lean.sh` (`O`, here) runs the loop; your job is
the three things it leaves to you, then getting out of its way.

The blocks it drives — `/dev-pipeline:build-lean` and `/dev-pipeline:review-lean` — stay
individually invokable. The two-terminal manual flow is first-class: it is the debugging and
rescue path, and the fallback if headless sessions ever leave the subscription.

## Checklist

1. **Route.** One `ticketTag` → one cwd. Launch from the repo the ticket's tag routes to; the
   lane has no per-repo worktree map, so the invocation cwd *is* the routing.
2. **Resolve the build model from tracker state.** Read the ticket's `opus` / `sonnet` label —
   where intake recorded the sizing — and pass it as `--build-model` with `--model-basis label`.
   No label? Size it yourself, pass your pick, and say why in `--model-basis`
   (`sized-here: <one line>`) — that line is the whole detector for a missing label.
3. **Run it.** `bash O <issue> --build-model <m> --model-basis label` — then watch. Between phases
   there is no human in the middle: build → review chains the moment the PR exists.
4. **Read the exit code, and nothing else.** `0` approved and closed out · `1` a phase failed ·
   `2` preflight rejected · `3` preflight rejected, RESUMABLE — the ticket is unintaken ·
   `4` hard stop, budget spent · `5` the review half produced no verdict usable against this head,
   twice · `6` the verdict was authored by the build run or build session (P10) · `7` the run's
   premise expired mid-flight — the ticket closed, or the base moved into this branch's files.
5. On `3`, run `/intake-toolkit:intake` yourself and re-launch — or, watching, `operator-override.sh
   attend` first and the reject prints how to record the decision instead of re-labelling. On `2`,
   fix what preflight named. On `5`, run `/dev-pipeline:review-lean <pr>` by hand: a rebuild fixes
   nothing. On `7`, rebase and re-launch, or abandon. On `4`/`6`, **stop** — re-entry is from the top.

## Rules that are not negotiable

- **Never re-label a ticket to get past a reject.** A ticket claimed by a run this lane stopped is
  already intaken; preflight reads its claim marker and re-enters.
- **You author nothing under your own identity.** Every tracker comment, label swap, commit and
  record is made by a payload block or by the gate, under the build side's bot identity; a write
  of your own would put a third identity into a two-identity contract.
- **Never interpret a finding.** The verdict gate's exit code is the whole signal. Reading the
  record to decide what comes next is content judgment — how this lane grew stage choreography.
- **Never resume a review context.** Each round's review is a new session (`-p`, never
  `--resume`): round 2 inheriting round 1's context is round 1 agreeing with itself.
- **The velocity principles bind here** ([manifesto](../../../../docs/pipeline-manifesto.md)):
  never idle-block, fan out independent work. A gate that is right but slow is not done.

## When it stops

Every non-zero exit leaves the worktree and the claim in place — the state a rescue needs. Pick the
blocks up by hand from the routed repo, or just re-launch: preflight accepts the claim the stopped
run left, so re-entry costs no tracker write and no re-labelling.
The staleness check that produces `7` runs at the spawn boundary; the gate re-asks at the build
session's own handoff (`mark`), so a ticket closing mid-spawn costs that session, not the review
round after it. `--dry-run` previews and spawns nothing.
