# Comparison 2 evidence

- `ground-truth-<pr>-r1-verdict.md` — the lane's own round-1 verdict record, read at the verdict
  commit on the PR ref. This is the oracle; this slice did not author it.
- `bare-<pr>-review.md` — the bare session's review of the same head.
- `codereview-<pr>-review.md` — the **arm-2a challenger**: the built-in `/code-review` at effort
  `max` on the same head, run under `docs/skill-ablation-addendum.md` §B. Each file records the
  realised invocation and the capture's apparatus, then the session's output verbatim — the report
  tool's payload where it filed one, and every `result` event's assistant text.
- `scoring.tsv` — per-blocker adjudication. `bare_result` / `adjudication` are the bare arm's;
  `codereview_result` / `codereview_adjudication` are the challenger's.

The bare arm here is a plugin-free session given `prompt-template.txt`, **not** the built-in
`/code-review` that issue #644's scope item 2 names. That departure, its direction of bias and its
successor are declared in `docs/skill-ablation.md` §2.

Bare recall 4/5. Two further blockers bare raised on #660 appear in no round of the lane's own
review; both were live on `main` when the bare arm ran — filed as #670 and #674, both since fixed.
See `docs/skill-ablation.md` §2.

Challenger recall 4/5 as well — but on a **different four**: it hits the #654 blocker bare missed
and misses #660's B2, which bare hit. Neither arm dominates. See `docs/skill-ablation.md` §2.
