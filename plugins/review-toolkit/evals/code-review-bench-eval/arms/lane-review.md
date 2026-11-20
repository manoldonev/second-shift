spawn: claude
allow: Read,Grep,Glob,Write,Bash(git *)
---
{rules}

You review this change as the lane's pass-1 session does, in this one session: worktree
`{checkout}`, base `{base}`, head `{head}` (`git -C {checkout} diff {base} {head}`). There is no
ticket and no decision record, so review it for correctness only, and write your findings to
`{out}`. The block below is the pass-1 session's own instruction: `check-lockstep-pairs.sh` holds it
to `plugins/dev-pipeline/skills/run/pass-1-review.md`.

<!-- LOCKSTEP-BEGIN review-correctness -->
Review the diff for correctness. For each unit that the diff changes, read its callers and its consumers. Check that each of them still works with the change. When the change adds a rule over stored data, read the data that the rule meets. Check the rule against the data that already exists. Walk every path through the change: each branch, each early return, each error and each empty input. Report each problem as a finding with its file:line and a concrete scenario: the input or state, and the wrong outcome it produces. A problem with no scenario is not a finding.
Report only relevant findings. A finding is relevant when a distinguished engineer who knew of it would definitely address it before merge. Every reported finding makes the verdict `needs-work`, a `[note]` the same as a `[blocker]`. The tag names the kind of problem, never whether it gates. A completeness or correctness problem is a `[blocker]`. A maintainability, test-coverage or repo-convention problem is a `[note]` only, never a `[blocker]`.
A finding that shows existing data or an existing caller breaking under the change is a `[blocker]`. The ticket's scope list or parity with an older version never removes it or makes it a note. It is not a finding only when the ticket names that exact case and accepts it. The ticket's own text counts as the operator's. A break that only the ticket text accepts gets one line in `## Notes` that quotes that text. A finding that shows the change does not do what the ticket asks, for input that existing callers send, is a completeness `[blocker]`. A requirement is an outcome, a behavior, an acceptance criterion or an external surface the ticket states. An internal structure that the ticket's scope or prose prescribes is not a requirement: its absence is never a completeness `[blocker]`, and it gets no finding.
Over-engineering is always a `[note]`: a new abstraction, layer, option, extension point or generalization that nothing needs. A need is a present caller in the checkout, or an external surface the ticket asks for. An external surface is something a party outside the diff's own code reads or calls: a config key, an entry point or command, an API, or a stored or on-disk format. It needs no named caller. A ticket line or any other decision that prescribes the mechanism is not a need. A need expected only in the future is not a need either. Name the simpler shape, and cite the callers or show that there are none. When the ticket's own text prescribes the mechanism, the operator decided it: it is not a finding, and it gets one line in `## Notes` that starts with its file:line and quotes that text. Quote any other prescribing decision in the finding.
<!-- LOCKSTEP-END review-correctness -->

Write to `{out}` every finding that you report, one per numbered item, in the output form above.
Put the finding's scenario in its item.
