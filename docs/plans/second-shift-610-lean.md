# second-shift #610 — census and triage of prose blocking constructs

Issue: [#610](https://github.com/manoldonev/second-shift/issues/610) (part of
[#605](https://github.com/manoldonev/second-shift/issues/605))
Predecessor: [#609](https://github.com/manoldonev/second-shift/issues/609) — its report,
`docs/gate-ablation.md`, is binding input where a construct has a record-backed gate analog.
Pre-flight ledger: `.claude/pipeline-state/610-ledger.md` (binding input — gitignored, so its
load-bearing content is carried into the Decision Ledger below)

## Problem, as pinned

Blocking constructs sit in `SKILL.md` prose across the plugin tree with nothing saying which of
them is a control. The manifesto already condemns most: **P2** says an outcome gate must be
impossible to skip, not discouraged — a prose-only blocker is by construction only discouraged —
and **P5** says a rule enforced by a gate does not also live as prose. So each one is exactly one
of three things, and today nothing records which: restated gate prose, a rule worth enforcing, or
a rule that was never a control.

The parent epic's approximate count (≈80 across 17 skills) came from a grep, not a predicate. This
slice pins the predicate, produces the census from it, dispositions every construct, and executes
the prune — which is also the prerequisite for the parent's classification register, since that
register keys on enforced gates with durable identities and not on prose lines it would have to
chase.

## Acceptance criteria

- **AC-1:** WHEN `tools/prose-blockers.sh census` runs THEN it emits one row per blocking
  construct — id, comma-joined sites, excerpt — over the pinned corpus (skills' `SKILL.md` under
  `plugins/`, fixture copies excluded by path), and the run is reproducible: same tree, same rows.
  The census UNIT is a markdown block (a list item with its continuation lines, a paragraph, or a
  table row) carrying at least one marker of the pinned predicate; a construct whose normalized
  text is identical at two sites, or whose sites share one `LOCKSTEP` anchor, is ONE construct
  carrying both addresses. Ids are content-derived, so relocating a construct re-keys nothing.
  The predicate is tiered with a reversible default (OR-1): `stop` — a construct must name a stop
  — widenable to `bold` and `all` by flag, and the wider counts are reported so the default is
  honest about what it excludes. The command has a behavioral selftest.
- **AC-2:** WHEN the triage record is read THEN every censused construct carries exactly one of
  `gate-backed`, `promoted`, `deleted`. A `gate-backed` row names its enforcing gate and its
  duplicating prose is deleted, a pointer surviving only where the skill's checklist flow would
  otherwise dangle. A `deleted` row carries the one-line reason it was never a control. The
  all-dark-panel rule triages like any other row; its bucket is pre-settled, its disposition is not.
- **AC-3:** WHEN a row is `gate-backed` or `promoted` THEN its `enforcer` cell is non-empty and
  names a real, resolvable enforcement site; no rule reaches `deleted` while some gate still
  enforces it. Every enforcer named in the record resolves in the tree.
- **AC-4:** WHEN a construct is `promoted` THEN either the guard shipped in this PR with its
  paired selftest case (one-guard-small: one small guard addition, extending an existing script or
  adding one check with one fixture case), or the record's `enforcer` cell carries the follow-up
  issue that owns it. No promotion is recorded without one of the two.
- **AC-5:** WHEN the triage record is parsed THEN it is TSV with six declared columns
  (`id`, `disposition`, `action`, `sites`, `enforcer`, `note`); `gate-backed` and `promoted` rows
  key their enforcer on a repo-relative path plus a subcommand-or-check-name tuple; the key format
  is declared reversible so the phase-2 register may re-key, and the `sites`/`id` columns
  regenerate from the census command.
- **AC-6:** WHEN `tools/prose-blockers.sh check` runs over the pruned tree THEN it exits 0
  reporting zero undispositioned constructs, and it exits 3 naming any construct present in the
  tree with no row — and any row recorded `deleted` whose construct is still in the tree. No new
  standing CI guard is wired in this slice; the result is recorded in the PR.
- **AC-7:** WHEN this prune touches a file that #566, #553, #554 or #541 claims THEN the triage
  record names which ticket owns the residual, rather than doing that ticket's work here. The
  tracked prose-budget baselines are regenerated in this PR if the prune moves them.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Promotion sizing threshold | One-guard-small executes in-slice (one small guard addition with its selftest case, extending an existing script or adding one check with one fixture case); anything larger is filed as its own named follow-up owned by the open parent epic and linked from the triage record. | user-answered |
| D-2 | Sequencing and register home | This triage precedes the parent's classification register by design; the register will key on enforced gates in code, never on prose — a prose-presence guard and a centrally-registered prose census are both rejected shapes. | user-answered |
| D-3 | Classification predicate constraint | A gate defending against model fabrication or self-approval is gates-llm; a gate encoding an assumed-absent human is gates-process. Pre-settled classifications constrain a construct's bucket only, never its disposition — the all-dark-panel rule triages like any row, its merge-boundary backing weighed like any other gate analog. | user-answered |
| D-4 | Census corpus | Skills' SKILL.md files under the plugins tree; fixture copies excluded by path; agent contract files are a named out-of-census residual routed to the phase-2 register intake. A construct with no ablation analog gets no default from the ablation report. | codebase-derived |
| D-5 | Record shape defaults | Gate-backed prose defaults to deletion (a pointer survives only where the skill's checklist flow would dangle); the triage record keys on a repo-relative path plus subcommand-or-check-name tuple, declared reversible for phase-2 re-keying; duplicated constructs are one contract with two sites, pinned with the lockstep-marker mechanism where both survive. | codebase-derived |
| D-6 | What "blocking" means in the predicate (OR-1's default) | A construct must NAME A STOP — refuse, abort, hard-stop, blocker, reject, hand back, not negotiable. A bare prohibition is not enough: `**Do not pad with "no issues found."**` is guidance, and nothing stops if you read past it. Deleting that class would strip working instruction under a triage that was never about it. The wider tiers exist and are counted (`bold` adds bolded prohibitions, `all` adds every clause-initial one) so the narrow default is a stated choice rather than a hidden one. | codebase-derived |
| D-7 | No exclusion list, anywhere | The predicate takes the tree as it finds it. A hand-maintained roster of "lines that look like blockers but are not" is exactly the centrally-registered prose census D-2 rejects: it conflicts on every PR that appends to it and goes blind to whatever it never named. The cost — a handful of blocks that carry a stop word inside a larger instruction — is accepted, and those blocks triage on their merits like any other. | codebase-derived |
| D-8 | Where the record's authority stops | The census is computed; the disposition is authored. `check` compares the two and can only report a construct with no row, or a `deleted` row whose prose is still there. It cannot verify that a `gate-backed` row's named gate really enforces that rule — that is a reading, and AC-3 is discharged by review plus a resolvability check on the enforcer path, not by a guard claiming judgment it does not have. | codebase-derived |
| D-9 | Why no CI wiring | AC-6 says so, and the parent's register owns the living coverage guard. Wiring `check` now would pin a predicate the register is expected to re-key, and would red every PR that edits a construct's prose — content-derived ids re-key on edit by design, so the record is re-read rather than silently inherited. | codebase-derived |

## Design

Design: none — this repo configures no `design.provider`. The change is a census script, a
committed record, and prose deletions. No route, no render state, no user-visible surface.

## Out-of-census residual (named, not dropped)

Agent contract files under `plugins/*/agents/` carry the same construct class and are **not**
censused here (D-4). They are routed to the phase-2 register intake. Recorded in the triage record
header so the residual has an owner rather than an omission.
