# Comparison 1 evidence

- `ticket-<n>.md` — the issue body handed to every run.
- `prompt-template.txt` — the prompt, identical across runs; the ticket is appended to it.
- `bare-<n>-plan.md` — the **registered** run, in the repository worktree at the ticket's base.
- `bare-ablated-<n>-plan.md` — the **disclosed post-hoc sensitivity** run: same base checkout with
  every `plugins/**/SKILL.md` and `plugins/**/agents/*.md` deleted, everything else — `lean-gate.sh`
  included — left in place.
- `consumer-<arm>-<n>-plan.md` — **arm 1 of #671**, the consumer-shaped re-run registered in
  [`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §A: gate and skills absent
  from the working tree, installed plugin cache present and readable. Four `<arm>` values —
  `max` and `min` are the addendum's registered pair, `sealed` and `sealed-min` are disclosed
  post-hoc arms that additionally put the kit out of reach of `git show HEAD:`. The realised
  substrate for each, and the two apparatus findings that produced the post-hoc arms, are in
  `consumer-substrate.md`.
- `consumer-max-confined-<n>-plan.md` — arm 1's **first pass**, kept because it is the evidence for
  both of those findings. Superseded: its sessions could not reach the plugin cache, so it does not
  realise the registered substrate and is not scored.

The registered run is confounded: the kit's prose is a file in the tree and both sessions read it.
See `docs/skill-ablation.md` §1.
