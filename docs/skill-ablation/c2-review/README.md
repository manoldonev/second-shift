# Comparison 2 evidence

- `ground-truth-<pr>-r1-verdict.md` — the lane's own round-1 verdict record, read at the verdict
  commit on the PR ref. This is the oracle; this slice did not author it.
- `bare-<pr>-review.md` — the bare session's review of the same head.
- `scoring.tsv` — per-blocker adjudication.

Bare recall 4/5. Two further blockers bare raised on #660 appear in no round of the lane's own
review; one is live on `main`. See `docs/skill-ablation.md` §2.
