# review-lead (fixture — panel names a design-toolkit-shipped reviewer)

Reviewer selection happens in-session: choose from the effective reviewer registry — the plugin-shipped panel (review-toolkit:security-reviewer, review-toolkit:performance-reviewer, design-toolkit:design-faithful-reviewer) plus/minus the consumer config deltas — and pass the selected agentType[] as args.reviewers.

Every panel entry is written QUALIFIED — `review-toolkit:` for this root's own agents,
`design-toolkit:` for the sibling's — which is what failure class (e) requires, and which pins that
the pre-flight parse strips the qualifier for every other reader. The Routing entries below stay
BARE because the Routing regex excludes `:`.

## Reviewer Routing

- **security-reviewer** — always
- **performance-reviewer** — always
- **design-faithful-reviewer** — conditional, and shipped by the sibling design-toolkit plugin

## Spawning Reviewers

One dispatch substrate — the code-review.mjs Workflow.

## Verdicts
| Reviewer        | Verdict       | Findings | Confidence Range |
|-----------------|---------------|----------|------------------|
| Security        | Pass / Fail   | N        | N-N              |
| Performance     | Pass / Fail   | N        | N-N              |
| Design Faithful | Pass / Fail   | N        | N-N              |

end
