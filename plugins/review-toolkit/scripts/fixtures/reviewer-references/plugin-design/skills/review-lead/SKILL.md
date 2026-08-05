# review-lead (fixture — panel names a design-toolkit-shipped reviewer)

Reviewer selection happens in-session: choose from the effective reviewer registry — the plugin-shipped panel (security-reviewer, performance-reviewer, design-toolkit:design-faithful-reviewer) plus/minus the consumer config deltas — and pass the selected agentType[] as args.reviewers.

The panel entry is written QUALIFIED (`design-toolkit:`) to pin that the pre-flight parse strips
the plugin qualifier; the Routing entry below is written BARE because the Routing regex excludes `:`.

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
