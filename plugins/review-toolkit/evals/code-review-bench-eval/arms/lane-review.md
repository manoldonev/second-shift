spawn: claude
allow: Read,Grep,Glob,Write,Bash(git *)
---
{rules}

You review this change as the pipeline's review session does, in this one session: worktree
`{checkout}`, base `{base}`, head `{head}` (`git -C {checkout} diff {base} {head}`). There is no
ticket and no decision record, so review it for correctness only. The block below is the review
session's own instruction: `check-lockstep-pairs.sh` holds it to `review_prompt()` in
`plugins/dev-pipeline/skills/run/run.sh`.

<!-- LOCKSTEP-BEGIN review-correctness -->
Review the diff for correctness. For each unit that the diff changes, read its callers and its consumers. Check that each of them still works with the change. When the change adds a rule over stored data, read the data that the rule meets. Check the rule against the data that already exists. Walk every path through the change: each branch, each early return, each error and each empty input. Report each problem as a finding with its file:line and a concrete scenario: the input or state, and the wrong outcome it produces. A problem with no scenario is not a finding.
A completeness or correctness problem is a `[blocker]` when it must change before merge. A maintainability, test-coverage or repo-convention problem is a `[note]` only, never a `[blocker]`.
<!-- LOCKSTEP-END review-correctness -->

Write to `{out}` every `[blocker]` and every `[note]` that you did not dismiss or suppress, one per
numbered item, in the output form above. Put the finding's scenario in its item.
