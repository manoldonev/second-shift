# Comparison 1 evidence

- `ticket-<n>.md` — the issue body handed to both runs.
- `prompt-template.txt` — the prompt, identical across runs; the ticket is appended to it.
- `bare-<n>-plan.md` — the **registered** run, in the repository worktree at the ticket's base.
- `bare-ablated-<n>-plan.md` — the **disclosed post-hoc sensitivity** run: same base checkout with
  every `plugins/**/SKILL.md` and `plugins/**/agents/*.md` deleted, everything else — `lean-gate.sh`
  included — left in place.

The registered run is confounded: the kit's prose is a file in the tree and both sessions read it.
See `docs/skill-ablation.md` §1.
