# second-shift #575 — the capability-parity gate must test its rows' claims, not just their shape

Issue: https://github.com/manoldonev/second-shift/issues/575
Pre-flight receipt: `.claude/pipeline-state/575-ledger.md` (binding input; D-n references below are its rows).

## Problem

`tools/capability-parity-check.sh` is the enforcement of #476 — "a staged-lane capability cannot be
deleted without a recorded disposition". It lints the register's **shape**: four tab-separated
cells, no empties, no duplicate capability, a disposition inside a closed enum. It has never
checked whether a row's disposition is **true**.

So a row may assert `already-covered`, name a successor in its free-text note that does not exist
or that nothing reaches, and the guard stays green. That is exactly #348: `design-sync.mjs` and
`figma.mjs` were on disk the whole time, their only `scriptPath` dispatcher died with the stage
docs, and three rows (56, 61, 63) claimed coverage for four engines with no caller at all until
#574 corrected them.

Two facts about the ticket, both settled in the receipt and both load-bearing here:

- The ticket's *second* problem — "the coverage clause is permanently vacuous because `STAGES_DIR`
  points at a deleted directory" — is **not live**. #577 (`7620251`) deleted the clause outright.
  There is nothing to repair; the work is adding a real second half. (D-12)
- The ticket's day-one exhibit — "run against `main` today this would fail rows 56, 61 and 63" — is
  **spent**. #574 fixed those rows by flipping them to `dropped`, and the ticket's own proposal
  exempts `dropped`. The exhibit survives here as a permanent selftest fixture, not a live red.
  No AC asserts that `main` goes red on landing. (D-13)

## Approach

A row's checkable claim moves out of the prose note and into a machine-readable cell: a new
**4th column, `successor`**, with `note` shifted to 5th (D-1). The note stays free text — it is
the only cell a reader writes in sentences, and row 41's `claim-issue.sh itself is shared, not
stage-owned` is a mention, not a claim, so extracting claims from prose manufactures claims the
register never made.

The guard then gains a second half with three rules:

1. **Require by disposition** — `ported` and `already-covered` must name a successor.
2. **Check by presence** — any row whose cell is not the none-token `-` has *every* token resolved,
   including `dropped` and `choreography` (D-3). This is deliberately wider than the ticket's two
   arms: rows 56/61/63 stopped being false by *changing class*, not by becoming true, and a
   `dropped` row that still asserts a survivor in prose is the same failure mode one disposition
   over.
3. **Probe reachability where existence provably is not enough** — `.mjs` tokens only (D-6).
   Existence alone would **not** have caught #348; only the missing dispatch would. Per-shape
   reachability for `.sh`, skill and agent tokens is out of scope — three new discovery mechanisms
   for a failure nobody has observed.

The probe reuses #574's reproduce **semantics** — the needle `scriptPath` over
`plugins/*/skills/**/*.md` and `plugins/dev-pipeline/workflows/*.mjs` — but as a scan rooted at the
register's own tree, **not** `git grep` (D-7). `git grep` inside the selftest's `mktemp` sandbox
errors with empty output, which a probe reads as "nothing dispatches anything": it would false-red
every `.mjs` fixture, or invite a not-a-repo skip arm that is fail-open by construction. Same file
set, same needle, same verdict in CI — and a sandbox that can fixture both the reachable and the
orphaned case.

## Acceptance criteria

**AC-1 — The register carries a `successor` column.** `tools/capability-parity.tsv` is five
tab-separated cells per data row, ordered `capability`, `paths`, `disposition`, `successor`, `note`.
Its header documents the new column, the comma-separated multi-token form, and `-` as the sole
none-token, and no longer describes the stages-file coverage clause #577 deleted.

**AC-2 — Every row's successor cell is backfilled.** All 37 rows carry a non-empty cell: the 16
`already-covered` rows and the 6 `dropped` rows whose notes assert a surviving successor
(Decision-Ledger hydration, design FE-spec produce, pre-implementation plan review gate, unit-test
mutation gate, design-faithful implement and live-render verify, doc update) name repo-relative
paths; the remaining 15 rows carry `-` (D-8). Each named path resolves under the repo root, and
each token is one that the row's own note asserts — no successor is invented for a row that claims
none.

**AC-3 — The shape lint moves to five cells.** `tools/capability-parity-check.sh` reds on a row
with any field count other than 5, and reds on an *empty* successor cell exactly as it already reds
on an empty capability, paths or note cell. An empty cell is never read as "no successor": `-` is
the only way to record that (D-2).

**AC-4 — Require by disposition.** A row whose disposition is `ported` or `already-covered` and
whose successor cell is `-` reds, naming the capability and the line.

**AC-5 — Check by presence.** For every row whose successor cell is not `-`, each comma-separated
token is resolved as a path relative to the register's tree root (the register's parent directory's
parent), and a token that does not exist there reds. All tokens must resolve — one unresolvable
token reds the row (D-5). Violations are emitted one per failing token, in the guard's existing
`line <n>: capability '<cap>' …` shape (D-16), so a multi-token row reports every failure rather
than the first. An empty token (a doubled or trailing comma), an absolute token, and a token
containing `..` each red: those are not repo-relative paths, and a token resolved outside the tree
would go green on whatever the host machine happens to carry.

**AC-6 — Dispatch probe for `.mjs` successors.** A token ending in `.mjs` must additionally be
*reached*: some file under `plugins/*/skills/**/*.md` or `plugins/dev-pipeline/workflows/*.mjs`
within the same tree root, excluding selftest and probe harnesses, carries the token's basename and
the literal `scriptPath` on one line. A `.mjs` successor that exists on disk but has no such
dispatcher reds — the #348 shape. The scan is rooted at the register's tree and uses no `git`
subcommand, so it produces the same verdict inside a non-repo sandbox (D-7).

**AC-7 — The success line reports the successor work.** A clean run prints the row count, the
number of rows whose successor claim resolved, the number of `.mjs` tokens dispatch-probed, and the
number of rows claiming none — e.g. `OK — 37 capability row(s), every disposition in enum; 22
successor claim(s) resolved, 1 dispatch-probed, 15 row(s) claim none.` A clause that silently stops
running is what produced this ticket; a drop to `0 successor claim(s) resolved` must be legible in
a CI log without reading the source (D-11).

**AC-8 — The selftest drives every new red path, in both directions.**
`tools/capability-parity-check-selftest.sh` gains cases that fail if any AC-3..AC-7 clause is
removed: a 4-field row reds; an empty successor cell reds; an `already-covered` row with `-` reds;
a `dropped` row with `-` stays green; a named successor that does not exist reds; a second token
that does not exist reds while the first resolves; an absolute or `..` token reds; a `.mjs`
successor with a `scriptPath` dispatcher is green; **a `.mjs` successor that exists but is
undispatched reds** — the permanent fixture for the pre-#574 claim shape (D-10); and the success
line names the successor counts.

**AC-9 — The guard's stale LIFETIME prose is deleted.** The header block documenting "the coverage
clause below" — code #577 removed — is gone, replaced by prose describing the successor clause and
its scope; the selftest's header paragraph about cases (k)/(l) and its case-(a) label "against the
real stage docs" are corrected to what those cases now assert (D-9).

## Successor mapping (OR-1 default, flagged for review)

OR-1 is a reversible default-and-flag: D-4 states the rule the mapping follows — a milestone or
checklist-step successor names the file that **enforces** it, not the prose that describes it — and
a mis-mapped row is a one-cell edit. The full mapping is in the PR body so the review round grades
it rather than discovers it. Two rows are known-contestable and called out there by name:
`deterministic verify green gate` and `PR creation with ticket linkage`, whose notes cite
milestones rather than any artifact; both resolve to
`plugins/dev-pipeline/skills/build-lean/lean-gate.sh` under D-4's rule.

OR-2 (whether the 15 non-claiming rows should carry a reason token instead of a bare `-`) keeps its
default: the bare `-` ships here.

## Out of scope

- Repairing the coverage clause — #577 deleted it (D-12).
- Any change to the disposition enum, including retiring `ported` despite its zero rows: rows are
  permanent record and the enum outlives its data.
- Per-shape reachability for `.sh`, skill and agent successors (D-6).
- Re-litigating any #574 disposition; rows 56/61/63 keep `dropped`.
- `.github/workflows/ci.yml`, `docs/`, `CLAUDE.md` and `scripts/lockstep-manifest.tsv`: the guard is
  repo-local with no second copy and no documentation reference (D-15), and the CI step name is
  already generic.
