# #667 — the always-spawn core becomes a checklist-structured lead pass

`review-lead` spawns four reviewers on every round of any size — `performance-reviewer`,
`maintainability-reviewer`, `complexity-reviewer`, `test-coverage-reviewer` — that authored
**zero** blockers across 248 committed verdict-record versions, while accounting for the entire
dark surface (test-coverage in 19 of 24 dark events, maintainability in 6). The Sub-Agent Trust
Model already obliges the reviewing session to read the whole diff and re-verify every finding, so
those four dimensions are being paid for twice and gating on neither.

This slice collapses them into a **checklist-structured lead pass** the reviewing session performs
itself, and demotes `security-reviewer` from always-spawn to a **surface-conditional** trigger. It
is a routing edit plus one reference file. The reviewer registry, the scope-completeness gate,
every conditional/domain reviewer, `code-review.mjs`, and every lane contract are untouched.

The measurement register this consumes is `docs/review-panel-yield.md`, whose Decisions table
forward-references this routing edit.

## Design

Design: none — this slice edits skill prose, a reference file, a section catalog and a repo doc.
It ships no web component and this repo configures no `design.provider`, so there is no render
state to declare.

## Acceptance criteria

- AC-1: **Routing — the four are no longer spawned at any change size.**
  `plugins/review-toolkit/skills/review-lead/SKILL.md` no longer selects
  `performance-reviewer`, `maintainability-reviewer`, `complexity-reviewer` or
  `test-coverage-reviewer` at Trivial-inert, Small, Medium or Large; their dimensions are covered
  by the lead pass of AC-3. Every prose site the change touches is updated in the same commit, so
  the skill does not contradict itself: the "Always spawn (core reviewers)" section, the
  Trivial-inert carve-out's "always get full core review" sentence, the Review Depth Routing
  table's Reviewers column on all four rows, and Step 4b's dark-accounting example naming
  maintainability + test-coverage.

- AC-2: **The Depth Routing table's surviving role is stated explicitly**, not left implicit: the
  table calibrates how deeply the lead pass reads per change size, plus the AC-4 security
  conditional. Conditional reviewers remain exempt from it, as today.

- AC-3: **A lead-pass checklist reference file** ships in the review-lead skill directory, folded
  from all five collapsed/demoted agents' calibration content. It carries: a generalized Pre-Emit
  Gate (anchored? / concrete-today? / distinct-from-the-surrounding-pattern?), the two-condition
  Critical triggers, each dimension's What-NOT-to-flag block, new-vs-pre-existing classification,
  and the confidence ≥ 80 threshold with sub-threshold findings kept visible as suppressed. Its
  structure is one read of the diff, then per-dimension sections, with out-of-diff reads taken
  only against a named risk. SKILL.md references it at the point the lead pass runs.

- AC-4: **`security-reviewer` spawns conditionally, on surface triggers.** The trigger is model
  judgment over the diff — auth / tenancy / session / upload / query-construction surface — **or**
  the repo under review carrying `.claude/second-shift/review-context/security-reviewer.md`. This
  is the matching posture the design-fidelity dimension already uses, not a mechanical pathspec
  match. When the conditional does not fire, that is a Step 4c not-selected note, never silent;
  the lead pass owns the security dimension for that round. When it does fire, the lead pass's
  security section defers to the spawned reviewer under ordinary dedup.

- AC-5: **The lead pass loads the consumer extension surface the collapsed reviewers used to
  self-load** — `.claude/second-shift/review-context.md` plus each collapsed reviewer's
  `.claude/second-shift/review-context/<reviewer-name>.md` when present. Without this, consumer
  calibration content goes unread while every lint stays green, which is the silent-loss class
  `check-review-context.sh` exists to prevent.

- AC-6: **The section catalog and the extension-points doc are reconciled, with the reader tokens
  unchanged.** `plugins/review-toolkit/scripts/section-catalog.txt` keeps the existing reviewer
  names in its readers column — they remain effective-registry members, and the format's legal
  column values are registry names or `all`. The semantic ("the section calibrates that dimension,
  applied by whoever reviews it — a spawned reviewer or the lead pass") is stated once in the
  catalog header, and `docs/extension-points.md`'s "Read by:" lines are reconciled to it. The
  catalog's active section NAMES are unchanged, so
  `check-review-context-sections-selftest.sh`'s catalog↔docs-template lockstep case stays green.

- AC-7: **The registry stays intact.** All five reviewer names remain in the panel parenthetical,
  the effective registry computed from it, and `REVIEWER_MODEL` in `code-review.mjs` — spawnable
  on demand or by config. This is what makes consumer migration zero-mandatory on the lint
  surface: no `REMOVE-UNKNOWN` commit denials, no `UNKNOWN-REVIEWER-FILE` pre-flight reds, and
  `reviewers.modelOverrides` keys stay live. Removing a `REVIEWER_MODEL` key would additionally
  break bare-name normalization, per that map's own header.

- AC-8: **The three sub-registries `check-reviewer-references.sh` hard-diffs stay consistent.** All
  four collapsed reviewers keep their Verdicts-table rows with their first-column labels
  unchanged, and the Verdicts header row is not reflowed (the lint's awk anchor matches its
  literal spacing). Their Verdict *cells* render `Lead pass — ✅/❌` so a round's coverage stays
  legible. A `Lead pass` summary row may be added in addition to, never instead of, those four
  rows. The Verdict-rules line "only include rows for reviewers that were spawned" carries an
  explicit exception for the four collapsed rows, which this AC requires present.

- AC-9: **Empty-selection short-circuit.** With the core no longer always-spawned, routing can now
  select zero subagents (docs-only diff, no issue reference, security conditional not firing).
  `code-review.mjs` throws on an empty `reviewers[]`, so review-lead's dispatch mode **skips the
  Workflow invocation entirely** when the selected set is empty and runs the lead pass plus
  synthesis alone.

- AC-10: **Step 4b-void is re-worded for a non-empty lead pass.** Void applies to the *selected
  subagents* only: a completed lead pass means the round reviewed something, so an all-dark
  selected set no longer voids a round the lead pass covered. A dark
  `scope-completeness-reviewer` keeps Step 4's hard-gate force exactly as today — `BLOCKED` is
  treated as `FAIL` and "Ready to merge?" is No. `review-lean` is untouched; its hand-back
  behavior on that verdict is already the lane's.

- AC-11: **`plugins/dev-pipeline/workflows/code-review.mjs` is untouched by this branch.** The
  surviving subagents still need the transport ladder, `PROGRESSIVE_EMIT`, the ceiling and the
  dark markers.

- AC-12: **`docs/review-panel-yield.md` is brought in step with what actually shipped.** Its
  Decisions table dispositions the four as `demote` ("dispatched only on a diff matching its
  domain") and forward-references this routing edit; landing a collapse instead would leave that
  table asserting a dispatch rule the tree no longer has. A short note under Decisions records
  that the routing edit consumed those rows as a collapse into the lead pass rather than a
  domain-gated dispatch, on the broader corpus that decided it, and that every panelist stays
  spawnable. The measured columns above it are not restated or revised.

- AC-13: **The branch carries a `Changelog:` trailer** describing the consumer-visible behavior
  change, and telling consumers carrying `review-context/` files for the collapsed reviewers that
  the lead pass now reads them. No config migration is required.

- AC-14: **The validation surface is green**: `check-reviewer-references.sh`,
  `check-review-context.sh` and `check-review-context-sections.sh` against the edited SKILL.md,
  `bash tools/prose-blockers.sh check`, and the full selftest sweep per `CLAUDE.md`. No new guard
  is owed — the change is prose routing already covered by those lints, and a grep-style guard on
  the new checklist text would be the banned prose-presence class.

## Explicitly out of scope

- Any lane-contract change (external-session review, patch-bound verdict record, per-AC scoring,
  delta/inheritance, hand-back semantics).
- `scope-completeness-reviewer`, `unit-test-mutation-reviewer`, and all conditional/domain
  reviewers.
- A blocker-critic agent or any default-refute rule on blockers.
- Deleting the five agent `.md` files or slimming `code-review.mjs`.
- Revising the measured columns of `docs/review-panel-yield.md` — it is a pinned measurement, and
  AC-12 touches only the disposition note that this edit makes stale.
