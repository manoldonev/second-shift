spawn: claude
allow: Read,Grep,Glob,Write,Bash(git *)
---
{rules}

You review this change as the pipeline's review session does, in this one session: worktree
`{checkout}`, base `{base}`, head `{head}` (`git -C {checkout} diff {base} {head}`). There is no
ticket and no decision record, so review it for correctness only. Pass 2 of the block below does
not apply here, and your pass-1 findings are what you write to `{out}`. The block below is the
review session's own instruction: `check-lockstep-pairs.sh` holds it to `review_prompt()` in
`plugins/dev-pipeline/skills/run/run.sh`.

<!-- LOCKSTEP-BEGIN review-correctness -->
Review the diff for correctness. For each unit that the diff changes, read its callers and its consumers. Check that each of them still works with the change. When the change adds a rule over stored data, read the data that the rule meets. Check the rule against the data that already exists. Walk every path through the change: each branch, each early return, each error and each empty input. Report each problem as a finding with its file:line and a concrete scenario: the input or state, and the wrong outcome it produces. A problem with no scenario is not a finding.
A completeness or correctness problem is a `[blocker]` when it must change before merge. A maintainability, test-coverage or repo-convention problem is a `[note]` only, never a `[blocker]`.
A finding that shows existing data or an existing caller breaking under the change is a `[blocker]`. The ticket's scope list, a record row or parity with an older version never makes it a note. It drops to a note only when the ticket or a record row names that exact case, accepts it, and names who decided. The ticket's own text counts as the operator's. A row names who decided when its provenance is `user-answered`, or `ticket-sourced` with its comment URL. A `user-delegated` or `codebase-derived` row never accepts a break. The finding then quotes that line. A finding that shows the change does not do what the ticket asks, for input that existing callers send, is a completeness `[blocker]`.
The review runs in two passes. Pass 1 is the completeness and correctness review, from the ticket and the code alone. Pass 1 does not open the decision record, the plan or the PR description. It reads the diff with the plans directory excluded. It writes its findings to the scratch directory before pass 2 starts. When there is a record, pass 2 reads it at its first commit and at the head, and scores every row. A record row never removes, dismisses or downgrades a pass-1 finding. When a row decided the behavior that a finding shows breaking an existing caller, existing data or the ticket, the finding keeps its severity and names the row. Only two record grounds make a pass-1 finding a note: the accepted break above, and the test intent's exemption of an acceptance criterion from a test. A pass-1 finding is never posted as `Dismissed.` or `Suppressed.` on a record's ground.
<!-- LOCKSTEP-END review-correctness -->

Write to `{out}` every `[blocker]` and every `[note]` that you did not dismiss or suppress, one per
numbered item, in the output form above. Put the finding's scenario in its item.
