# Comparison 2 evidence

- `ground-truth-<pr>-r1-verdict.md` — the lane's own round-1 verdict record, read at the verdict
  commit on the PR ref. This is the oracle; this slice did not author it.
- `bare-<pr>-review.md` — the bare session's review of the same head.
- `scoring.tsv` — per-blocker adjudication.

The bare arm here is a plugin-free session given `prompt-template.txt`, **not** the built-in
`/code-review` that issue #644's scope item 2 names. That departure, its direction of bias and its
successor are declared in `docs/skill-ablation.md` §2.

Bare recall 4/5. Two further blockers bare raised on #660 appear in no round of the lane's own
review; **both** are live on `main` — filed as #670 and #674. See `docs/skill-ablation.md` §2.
