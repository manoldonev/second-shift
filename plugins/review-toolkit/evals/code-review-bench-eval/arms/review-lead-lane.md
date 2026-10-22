spawn: claude
allow: Read,Grep,Glob,Agent,Skill,Workflow,Write,Bash(git *),Bash(find *),Bash(cp *),Bash(jq *),Bash(shasum *),Bash(bash *check-review-context.sh*)
bgwait: 1
plugin-dir: ../../..
---
{rules}

Invoke the `review-toolkit:review-lead` skill to review this change: worktree `{checkout}`, base
`{base}`, head `{head}` (`git -C {checkout} diff {base} {head}`). Invoke it as the pipeline's
review session does: every reviewer whose surface the diff touches is dispatched, and the lead pass
runs all its dimensions. There is no ticket and no decision record, so no scope seat and no forced
seat: this is the lane's review of a diff with no record rows. Let the
skill run exactly as it is written; stage its workflow script under `{scratch}`.

When it has produced its consolidated report, write to `{out}` every finding the report presents
as a finding to act on (not suppressed, dismissed or below-threshold items), one per numbered item,
in the output form above. Transcribe; add nothing of your own.
