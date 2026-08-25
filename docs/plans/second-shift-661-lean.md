# #661 — measure the reviewer panel's return rate and yield, then decide per panelist class

Operator-directed, 2026-08-24, from the PR 660 round-1 verdict's own observation that three
consecutive rounds produced no panel blocker while a third of the panel went dark.

## Problem, restated in one line

The panel is paid for on every round, and nobody has ever measured what each panelist returns for
that payment — so both "keep it, it might catch something" and "cut it, it never does" are
anecdote.

## What this slice is

**Measure, then decide.** Two deliverables and one mitigation:

1. a committed measurement over a pinned corpus of review rounds — per panelist: dispatches, dark
   events, degraded returns, blockers raised, blockers upheld, non-blocker findings carried;
2. a per-panelist-class decision (keep / demote to conditional dispatch / retire), each citing its
   own measurement row;
3. the emit-deadline mitigation for the dark-reviewer shape the measurement finds, which scope item
   3 obliges "whatever lands".

**No dispatch-routing edit lands on this branch.** AC-1 places the measurement *before* any
dispatch change, and the routing edit that consumes these decisions is #667's — which was filed
after this ticket, carries the routing design, and is the change AC-2's "each dispatch change cites
its measurement row" binds. Landing the routing here would leave two branches editing the same
`review-lead/SKILL.md` sub-registries.

## The corpus, and why it is pinned this way

Every **distinct blob** of `docs/plans/*-lean-verdict.md` first committed on or after 2026-08-16 and
reachable from any ref — 56 record-versions across 43 issues, one per review round. Re-derivable:

```
git log --all --diff-filter=AM --date=short --pretty='%H %ad' --name-only -- 'docs/plans/*-lean-verdict.md'
```

then `git rev-parse <sha>:<path>` per version, deduplicated on the blob. **Blob dedup is
load-bearing**: a record committed on a lane branch and again on `main` at merge is one round, and
counting the commits instead of the contents inflates every denominator (68 versions collapse to
56 rounds here).

The window is the recent corpus scope item 1 names, not all history: it spans the current dispatch
shape, and every round in it is readable end to end rather than sampled.

## Acceptance Criteria

- **AC-1** (oracle) — `docs/review-panel-yield.md` is committed carrying, per panelist:
  dispatches, dark events, degraded returns, blockers raised, blockers upheld, and non-blocker
  findings carried; over the corpus above, with its derivation stated as a runnable command. Rounds
  the corpus contains but the measurement cannot attribute are **enumerated by class and count**, not
  dropped — a denominator that silently excludes what it could not read reads as complete coverage.
- **AC-2** (critic) — every per-panelist decision (`keep` / `demote` / `retire`) cites its own
  measurement row, and no decision rests on a round outside the pinned corpus. Out-of-window
  evidence may corroborate and must be labelled as corroboration. No dispatch-routing edit is on
  this branch.
- **AC-3** (oracle) — the emit-deadline defect class covers the dark-reviewer shape: every panelist
  this measurement records going dark is inside `check-emit-deadline.sh`'s jurisdiction and carries
  a conforming turn-numbered deadline, pinned by a behavioral case that reds if **either** the
  enrollment **or** the deadline is removed. `bash tools/run-selftests.sh --full --exclude
  tools/install-topology-selftest.sh` green.
- **AC-4** (critic) — a `Changelog:` trailer on the branch.

## Do not touch

`plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`,
`.claude-plugin/marketplace.json` `metadata.version` — release artifacts, derived at release time.

## Decision Ledger

No pre-flight ledger exists for #661, so this table is the run's own; every row is grounded in the
ticket text or in the codebase, never assumed.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Scope item 2 says "decide"; does the dispatch change land here? | No. AC-1 says the measurement lands "before any dispatch change", and #667 — filed after this ticket — carries the routing design and the sub-registry constraints. This slice produces the decisions #667 cites. (source: the issue body at https://github.com/manoldonev/second-shift/issues/661, and #667's Scope) | ticket-sourced |
| D-2 | The ablation register is named as the template. Does the decision register ship as a TSV? | No — as a table in `docs/review-panel-yield.md` with the same columns (`class`, `decision`, `basis`, `earn_your_keep`). `tools/gate-ablation-classes.tsv` is a TSV because `gate-ablation.awk` reads it; nothing reads this one, and `prose-budget.sh`'s own header states this repo's posture — "a register's rows must be judgments, not measurements" — for registers with no consumer. The template is the row shape, which is carried. | codebase-derived |
| D-3 | What counts as panel yield? | A finding counts only where the record **names** the panelist that raised it. These records are explicit when a finding is a panelist's and equally explicit when it is the session's own (#590: "the three warnings below are the orchestrator's own reading of the diff, not reviewer findings"), so crediting unattributed findings to the panel would invent yield the records deny. | codebase-derived |
| D-4 | Which panelists get the emit-deadline enrollment? | Exactly those this measurement records going dark, and no others. `check-emit-deadline.sh`'s own enrollment rule is "a DEMONSTRATED death — an agent observed hitting its cap without emitting — never prophylactically", so the dark column is the enrollment predicate and a zero in it is a refusal. | codebase-derived |
| D-5 | The dispatch-time bounding nudge already covers these reviewers. Is a doc deadline redundant? | No. `code-review.mjs` appends `BOUNDED_EXPLORATION` to every generic-branch reviewer, and test-coverage-reviewer still went dark in 10 of 41 measured dispatches — the same shape `check-emit-deadline.sh`'s header records for spec-reviewer, where a nudge was in place and the death happened anyway. Its stated lesson: "a demonstrated death earns both, not either." | codebase-derived |
| D-6 | Cost per panelist, with no token meter in existence | Reported in dispatches and in **turn ceiling** (`dispatches x maxTurns`), with the dark subtotal called out separately as the one figure that is measured rather than bounded: a dark agent ran to the cap on both attempts by definition, so `2 x maxTurns` is its actual consumption for zero output. | codebase-derived |
