# Record of the intake session for issue 77, stages Requirements to Interview

Ticket: issue 77, "Headless build session ends its run when it backgrounds a long check and ends
its turn". The body is `TICKET.md`.

## Stage outcomes

**Requirements.** A written ticket. The body is used as written. No Requirements interview ran and
no question about acceptance criteria was asked. The ticket has no AC block. spec-reviewer:
implementable, no gap that only the operator can close. No design handoff. Knowledge source: the
repo has no `.claude/second-shift/intake-context.md`.

**Split.** Not triggered. The ticket has no `epic` label and one deliverable: a change to how the
scheduler starts the build session.

**Explore.** What I read and ran in the repo:

- `grep -n '^spawn()' plugins/dev-pipeline/skills/run/run.sh` → `708:spawn() { # spawn <role> <model> <id> <allowlist> <max-turns> <prompt-file> -> rc (124 past the bound)`.
  It is the one function that starts every session. The build call is at line 732 and the review
  call is at line 771. The environment of a spawned session is set there.
- `grep -n 'cap BUILD_TO' plugins/dev-pipeline/skills/run/run.sh` → `189:cap BUILD_TO "${RUN_BUILD_TIMEOUT:-}" .run.buildTimeoutSeconds 7200`.
  The scheduler already holds one bound for a build session: `RUN_BUILD_TIMEOUT`, else the config
  key `run.buildTimeoutSeconds`, else 7200 seconds.
- `grep -c 'BASH_DEFAULT_TIMEOUT_MS\|BASH_MAX_TIMEOUT_MS\|DISABLE_BACKGROUND' plugins/dev-pipeline/skills/run/run.sh` → `0`.
  The scheduler sets none of these variables today.
- `grep -n '^worktree_inflight()' plugins/dev-pipeline/skills/run/run.sh` → `476:worktree_inflight() { # 0 collected · 8 in flight · 1 unreadable`.
  This is the check that ends the run with `build-inflight`.
- `grep -n '^say()' plugins/dev-pipeline/skills/run/run.sh` → `94:say() { echo "$(now) [run] $*"; }`.
  Every line of the run log goes through it.

Note to self, from Explore: I will add one log line, `build: background tasks off`, so the operator
sees it in the run log.

**Fan-out.** Not run. After the printed notice the operator wrote: "skip fan-out. It is a
one-function change."

## The interview

**Turn 1. Interviewer:** The ticket names three ways to stop the build session from ending its run
while a long check runs in the background. Which one does the fix use?

1. Keep the checks in the foreground: the scheduler starts the build session with
   `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS` and `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`
   in its environment. It changes `spawn()` only. (Recommended: it removes the cause, and the
   scheduler keeps one fresh process per session.)
2. Re-enter the session: after an exit 0 with a dirty tree, continue it with `claude -p --resume`
   a bounded number of times. It adds a retry loop and a new terminal for "re-entries spent".
3. A line in the build prompt only. It costs nothing and depends on the model obeying it.

**Operator:** Prevent it with the env, so the checks stay in the foreground. No re-entry.

**Turn 2. Interviewer:** `spawn()` starts both the build session and the review session. Which
sessions get that environment?

1. Both. One code path, and a review session that waits on a long command has the same risk.
   (Recommended.)
2. The build session only.

**Operator:** BUILD only. REVIEW's panel runs as a background task.

**Turn 3. Interviewer:** What values do the two Bash timeout variables get?

1. Both at the build bound times 1000, so the scheduler's wall-clock bound stays the only cap and
   no new config key is needed. (Recommended.)
2. A fixed 30 minutes.
3. A new config key.

**Operator:** Your call.

**Turn 4. Interviewer:** Does the build prompt also get a line that says the session is headless
and must not end a turn while it waits on a background task?

1. No line. The environment already enforces the behavior, and a prompt line would be a second
   statement of it that can drift. (Recommended.)
2. Add the line as a second safeguard.

**Operator:** No preference. Go with what you would do.

**Turn 5. Interviewer:** `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` may also change the Agent
subagents that a build session starts, for example a plan check. I could only exercise Bash. Do we
set the variable anyway, or leave it out until that is known?

**Operator:** I don't know. Park it. I will look after the first consumer run.

The interview ended here. The operator said nothing else in this session.

## Handed in for the Receipt stage

The duplicate scan is a gate of the Receipt stage. The tracker is offline in this replay, so its
result is supplied here: `dup-scan.sh --issue 77` exited 0, with no candidate at or above the
threshold.
