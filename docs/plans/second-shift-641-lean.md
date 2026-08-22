# second-shift #641 — a declared ceiling on guard/test shell mass, and earn-your-keep on new gates

**Issue:** [#641](https://github.com/manoldonev/second-shift/issues/641)
**Branch:** `claude/second-shift-641`

## Problem

`docs/pipeline-manifesto.md` enforces its expansive principles (P2, P3) mechanically and its
restraining principles (P4 "as much as it takes, and none more", P5 "every word earns its place")
not at all — the document says so in its own text, calling itself "a judgment aid... not itself a
gate". Guard/test shell in the tree grew 8x in five weeks (49% → 80% of all `.sh` lines) while
product shell shrank. Phase 0 of the 2026-08-22 backlog recalibration: a mechanical stopping rule
for the growth side, so the two deletion slices sequenced behind it (#642, #643) land against a
ceiling that cannot silently regrow.

## Approach

Three independent, small mechanisms, none of which is itself a new gate framework:

1. **A declared ceiling on guard/test `.sh` mass** (`tools/guard-budget.tsv`), checked at PR time
   (`scripts/check-guard-budget.sh`, wired into `pr-gates`). A PR that pushes the measured total
   over the committed ceiling reds; a PR that raises the ceiling itself must carry a reason in the
   same diff.
2. **Earn-your-keep on the gate-ablation register.** `tools/gate-ablation-classes.tsv` gets a 6th
   column naming the regression class each decision point alone catches; `tools/gate-ablation.awk`
   reds naming any row that leaves it empty.
3. **A manifesto pointer**, not a restatement — P5 forbids restating an already-gated rule as
   prose.

## Findings that amend the issue

- **F-1 — the issue's headline 50,247 was an ad hoc, non-reproducible count; this ships the first
  reproducible instrument, and its number differs slightly (50,531 at HEAD of this branch).** The
  issue's table is described as "reproducible from `git ls-tree` over first-parent history" but no
  script producing it exists in the tree. `scripts/check-guard-budget.sh`'s `classify()` — every
  `*-selftest.sh`, `check-*.sh`, `*-lint.sh`, any `lean-gate.sh`, and the named standing-guard
  entry points `run-selftests.sh` / `mutation-sweep.sh` / `gate-ablation.sh` — measures **50,308**
  lines against `main`, within 0.1% of the issue's number and independent confirmation the
  direction is real. The committed ceiling is **50,531**: the *post-merge* measurement, including
  this PR's own new guard files (the checker and its selftest, ~220 lines) — "non-blocking on day
  one" is a design requirement the ratified 50,247 literal cannot satisfy on its own once this PR's
  own tooling is counted, so the ceiling is set to what the tree actually measures at HEAD rather
  than to the pre-PR ad hoc figure. See D-a.
- **F-2 — the "ceiling lowers automatically on every merge to main" mechanism (issue prose) is not
  implemented as CI-triggered auto-commit.** Every workflow in this repo runs with `contents: read`
  and nothing here commits back to `main` unattended (T0 note: push rulesets are unavailable on
  this public, user-owned repo, so a workflow-editing bot-commit path would be exactly as
  unsupervised as the freeze gap it documents). The check instead prints an advisory naming the
  lower value whenever the tree measures under the committed ceiling, and lowering is a normal,
  reviewed, no-reason-required edit — same review-visibility property the issue wants for a raise,
  extended to the automatic case rather than carved out of it. See D-b, Known trades.
- **F-3 — round-1 review (B-1) found F-1/F-2's departures from the issue's ratified line recorded
  only here, not where the operator reads.** Both are now amended into #641's own body: the
  committed-ceiling value (50,531 vs. the ratified 50,247, F-1/D-a) and the deferral of the
  automatic-commit ratchet half to a linked follow-up, **#646**, rather than to this spec's Known
  trades alone.

## Design decisions

- **D-a — the ceiling is the post-merge measured value, not the pre-PR ad hoc figure.** F-1. Every
  future PR measures against a ceiling that already includes whatever guard mass currently ships,
  so "non-blocking on day one" holds by construction rather than by hoping the two methodologies
  agree to the line.
- **D-b — ratchet-down is advisory, not automatic-commit.** F-2. `check-guard-budget.sh` never
  writes `tools/guard-budget.tsv`; an operator applies the printed advisory as an ordinary commit.
  A raise still requires a reason in the same diff (AC-1's third case) — that half of the escape
  hatch is unaffected.
- **D-c — the classifier is one predicate, read from one place.** `classify()` lives once in
  `scripts/check-guard-budget.sh`; the selftest drives the *shipped* function via fixture repos
  rather than a reimplementation, so a classifier edit cannot silently diverge from what its own
  test proves.
- **D-d — the earn-your-keep validation lives in the reader, not a separate lint.** Every consumer
  of `gate-ablation-classes.tsv` already goes through `tools/gate-ablation.awk`'s `readfile()`; a
  standalone format-lint would be a second parser of the same file that could disagree with the
  first.

## Acceptance criteria

- **AC-1** `tools/guard-budget.tsv` exists and `scripts/check-guard-budget-selftest.sh` drives
  `scripts/check-guard-budget.sh` over fixture repos: a tree under the ceiling passes; a tree over
  it fails naming the overage; a ceiling raised in the same diff without a reason line fails (and
  passes when a reason is given); a ceiling lowered needs no reason; the ceiling's first-ever
  commit is not scored as a raise.
- **AC-2** `tools/gate-ablation-classes.tsv` carries a 6th `earn_your_keep` column on every row,
  and `tools/gate-ablation.awk` reds — naming the row — when that column is empty or absent.
  Covered by two new cases in `tools/gate-ablation-selftest.sh`.
- **AC-3** `scripts/check-guard-budget.sh` runs as a step in `pr-gates` (`.github/workflows/ci.yml`)
  and reds a synthetic over-budget tree — proven by the selftest's Case 2, which is the same
  gate the CI step invokes, exercised over a fixture the check must reject.
- **AC-4** `docs/pipeline-manifesto.md` carries one pointer paragraph under the P4/P5 bullets
  naming the two mechanisms above, with no restatement of either rule's text.
- **AC-5** `Changelog:` trailer on the landing commit.

## Known trades

- **The ratchet's automatic half is advisory, not enforced** (D-b, F-2). A stale ceiling sitting
  well above the measured total is not itself a red — only growth past it is. That is a real gap
  against the issue's literal "automatically", accepted because the alternative is a CI workflow
  with write access to `main`, which this repo's own T0 note treats as an open risk rather than
  something to add casually. The mechanism that closes this gap — a scheduled workflow that opens
  a PR rather than committing directly — is filed as **#646** and is explicitly deferred there in
  #641's own body (round-1 review B-1), not decided silently in this spec.
- **The classifier is a defined predicate, not the issue's original (unspecified) methodology.**
  Two independent measurements landing within 0.1% of each other (F-1) is treated as sufficient
  confirmation that both are measuring the same real thing, rather than chasing byte-parity with an
  ad hoc count that has no script behind it to reproduce exactly.

## Sequencing

Phase 0 of the 2026-08-22 backlog recalibration. #642 (gate prune), #643 (scheduler value) and
#644 (skill-vs-bare-session ablation) are sequenced behind this — each needs the ceiling in place
first so their deletions register as ratchet room rather than vanishing into an uncapped total.
