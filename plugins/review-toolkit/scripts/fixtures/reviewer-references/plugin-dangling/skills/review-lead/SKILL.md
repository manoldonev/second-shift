# review-lead (fixture — dangling registry entry)

Reviewer selection happens in-session: choose from the effective reviewer registry — the plugin-shipped panel (security-reviewer, performance-reviewer, db-reviewer) plus/minus the consumer config deltas — and pass the selected agentType[] as args.reviewers.

## Reviewer Routing

- **security-reviewer** — always
- **performance-reviewer** — always
- **db-reviewer** — conditional

## Spawning Reviewers

One dispatch substrate — the code-review.mjs Workflow.

## Verdicts
| Reviewer        | Verdict       | Findings | Confidence Range |
|-----------------|---------------|----------|------------------|
| Security        | Pass / Fail   | N        | N-N              |
| Performance     | Pass / Fail   | N        | N-N              |
| Database        | Pass / Fail   | N        | N-N              |

end
