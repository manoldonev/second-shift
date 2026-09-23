# Eval Keep-or-Revert Threshold

The rule an agent-prompt eval campaign (the design-toolkit evals under
`plugins/design-toolkit/evals/`) uses to decide whether a prompt edit stays. The pass rate is the
eval's own score (`overall_pct` in its results JSON).

**This file and the eval's rubric are LOCKED during a campaign. Never edit either mid-loop.**
**If the eval is wrong, stop the campaign, fix the eval, restart from scratch.**

- **Keep** a change if the pass rate improves by 10+ percentage points across 3+ test runs.
- **Revert** if the pass rate drops or improves by less than 10 points (noise, not signal).
- A campaign needs a prior reading to compare against; with none, there is no campaign.
