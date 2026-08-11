---
name: run-lean
description: The lean lane's front door — one ticket in, a merged-ready PR out. A scheduler: it spawns build-lean and review-lean in fresh sessions, reads gate exit codes and tracker state, and authors nothing. Expects a ticket with paid-off intake (queue-labeled on GitHub, operator-attested under jira).
---

# run-lean

You are the scheduler, not a stage. `orchestrate-lean.sh` (`O`, here) runs the loop; your job is
the three things it refuses to do for you, then getting out of its way.

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
3. **Run it.**
   ```
   bash O <issue> --build-model <m> --model-basis label
   ```
   Then watch. Between phases there is no human in the middle: build → review chains the moment
   the PR exists.
4. **Read the exit code, and nothing else.** `0` approved and closed out · `1` a phase failed ·
   `2` preflight rejected (nothing was spawned) · `4` hard stop, budget spent · `5` the review
   half produced no verdict usable against this head, twice · `6` the verdict was authored by the
   build run or build session (P10).
5. On `2`, fix what the preflight named — most often: run `/intake-toolkit:intake` yourself and
   re-label the ticket. On `5`, run `/dev-pipeline:review-lean <pr>` by hand and read its output:
   the review lane is what failed, so re-running the build fixes nothing. On `4` and `6`, **stop**.
   Re-entry is from the top, not a rescue attempt.

## Rules that are not negotiable

- **A missing queue label is a reject, not a prompt and not a spawned intake session.** Intake
  elicits through questions a headless session cannot answer, so a spawned one either hangs or
  fabricates a receipt the Decision Ledger has no legal provenance for. Run intake yourself.
- **You author nothing and the scheduler writes nothing.** Every tracker comment, label swap,
  commit and record in a lean run is made by a payload block under its own identity. Adding a
  write here puts a third identity into a two-identity contract.
- **Never interpret a finding.** The verdict gate's exit code is the whole signal. Reading the
  verdict record to decide what to do next is content judgment, which is how this lane grew
  stage choreography the first time.
- **Never resume a review context.** Each round's review is a new session — `orchestrate-lean.sh`
  spawns with `-p` and never `--resume`. Round 2 inheriting round 1's context is round 1 agreeing
  with itself.
- **The velocity principles bind here** ([manifesto](../../../../docs/pipeline-manifesto.md)):
  never idle-block on work the next step does not consume, and fan out independent work. A gate
  that is right but slow is not done.

## When it stops

Every non-zero exit leaves the worktree and the claim in place — the state a manual rescue needs.
Pick the blocks up by hand from the routed repo, or re-run once the reject is fixed.
`--dry-run` prints the schedule and spawns nothing: the cheap way to check routing first.
