# review-lead (fixture)

Reviewer selection happens in-session: choose from the effective reviewer registry — the plugin-shipped panel (security-reviewer, performance-reviewer) plus/minus the consumer config deltas — and pass the selected agentType[] as args.reviewers.

## Reviewer Routing

- **security-reviewer** — always
- **performance-reviewer** — always
- **repo-local domain reviewers** — registered via config `reviewers.add` (e.g. an `orders-reviewer` on domain paths); backticked prose examples here must not parse into the plugin registry.

## Spawning Reviewers

One dispatch substrate — the code-review.mjs Workflow.

## Verdicts
| Reviewer        | Verdict       | Findings | Confidence Range |
|-----------------|---------------|----------|------------------|
| Security        | Pass / Fail   | N        | N-N              |
| Performance     | Pass / Fail   | N        | N-N              |

end
