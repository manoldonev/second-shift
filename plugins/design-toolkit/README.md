# design-toolkit

Builds frontend screens that match a design handoff, using the repo's own components and design tokens instead of hand-rolled copies.

- From a Claude Design handoff: `design-faithful-spec` writes the frontend spec, and `design-faithful` implements it and checks the rendered result against the handoff screenshot.
- From Figma: `figma-faithful-spec`, `figma-faithful`, and `figma-iterate` for quick interactive iteration.
- Plan, spec and fidelity reviewer agents for each provider, plus the `library-conformance` procedure both fidelity reviewers use.

Which provider is active comes from the repo config (`design.provider`). Only offer it on a repo that renders a UI.

## What it runs and sends

- Figma: reads design files through the Figma plugin or a Figma MCP server named `figma`. That needs a Dev or Full Figma seat.
- Claude Design: reads the handoff through Claude Code's design sync.
- Runs the repo's own frontend to render and screenshot the result, and commits with `git`.
- The `evals/` folder holds maintainer-run benchmarks. Nothing in it runs unless you start it.

## More

[The second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.
