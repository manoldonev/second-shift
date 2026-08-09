# second-shift #439 — gate-written markdown reds the consumer's format check

## Problem

`lean-gate.sh` writes two markdown artifacts into `$PLANS_DIR` and requires both to be
committed. Neither is written in the form a Prettier-formatted repo would produce, and
`$PLANS_DIR` sits inside the format gate of at least one consumer — so the artifact that
proves a milestone is also the artifact that reds the PR, and the failure surfaces only at
CI, after the milestone went green.

- **Render manifest** (`cmd_3_render`, `lean-gate.sh:1583-1585`): the table is emitted with
  single-space cell padding. Prettier pads every cell to its column's widest content, and one
  column is a 64-char sha256 — so the emitted form is *guaranteed* to differ.
- **Verdict record** (`cmd_verdict`, `lean-gate.sh:2133-2159`): a generated header plus a
  reviewer-authored body, written unformatted. Review bodies are table-heavy by convention.

Observed three times in the same consumer. The consumer-side workaround (`prettier --write`
between the gate call and the commit) has to be remembered at two separate write sites on
every round, and the gate's own success path never mentions it.

## Scope

Binding input: `.claude/pipeline-state/439-ledger.md` (D-1 … D-12, OR-1, OR-2). Where a row
there conflicts with the issue body, the row wins.

The two sites take **different** treatments, and the asymmetry is forced rather than
preferred (D-1). `cmd_3_render` re-derives the manifest on every milestone-3 run and
byte-compares it to HEAD (`lean-gate.sh:1593`), so a post-hoc `prettier --write` on that path
reds milestone 3 permanently: gate writes unpadded, operator formats, commits, gate
re-derives unpadded, diff, repeat. The manifest must therefore be emitted already-padded. The
verdict record has no such re-derive, and its body is arbitrary authored markdown that
padding cannot reach — so it is formatted by an external formatter, guarded.

**Not in scope** (D-8): agent-authored markdown in `$PLANS_DIR` — the spec and the intent-gap
record. The gate formats only what it authors. Those files sit inside `branch_patch_id`, so a
gate-side rewrite would move `reviewed_patch_id` and void an in-flight verdict; the manifest
is safe to rewrite precisely because it is excluded from the render binding
(`lean-gate.sh:419-428`). AC-7 gives the author a local signal for them instead.

**Not in scope** (D-7): a new config key, and any reuse of `commands.<repo>.format` — in at
least one consumer that key is bound to the *check* variant, and the shipped fixture
`run/tools/config-lint-fixtures/valid-be-fe-pair-jira.json` carries exactly that
(`"format": "yarn format:check"`). The resolver in AC-4 needs no consumer onboarding.

**Known open flank** (OR-1): the manifest's own header block (`rendered_from:` / `issue:` /
`spec:`) stays unformatted prose, so a consumer running `proseWrap: "always"` still fails
`--check` on it. Making that block prettier-inert touches the committed artifact shape and
all three lockstep readers, and is a separate change. Taking the default costs a red CI,
never a corrupt record — which is also what AC-5's guard exists to survive on the verdict
record, where that same config would otherwise join the header into one line.

**Known open flank** (OR-2): AC-1 computes width from character count; Prettier uses *display*
width, so a wide-glyph `route`/`state` cell would mis-pad. Manifest cells are `RS-n`, a route,
a state, a path and a hex digest — ASCII in the reported consumer. The failure mode is one red
CI run on the branch that introduced the wide cell, never a mis-read artifact.

**Known open flank** (OR-3, surfaced in review round 1): the padder splits on `|` with no escape
handling and `render_manifest_rows` reads the result positionally, so a literal `|` in an
author-written `route`/`state` cell both mis-pads the table and shifts the receipt's png/sha
columns. Strictly worse than OR-2's flank — a mis-read artifact rather than one red format check
— so it is recorded separately rather than folded into it. Left untreated: escaping would have to
round-trip through the padder *and* the reader for a cell no consumer has produced, and the
milestone-3 re-derive surfaces the damage on the run that introduces it rather than silently.
Carried in `md_table_prettier`'s header comment so the next author meets it at the code.

## Acceptance criteria

**AC-1 — The manifest table is emitted in Prettier's exact form.** `cmd_3_render` pads every
cell of the table it writes: each column's width is `max(3, longest cell over the header row
and every body row)`, the delimiter row carries exactly that many dashes, and every cell —
header, delimiter and body alike — is surrounded by one space on each side (D-2, measured
against prettier 3.7.4, the version `verifyctl.sh:296` pins as its own fallback).

**AC-2 — The padding is computed at the write site, from rows the gate already holds.** No
formatter is invoked on the manifest path and no new dependency is taken there; two runs over
an unchanged row set write byte-identical manifests, so the `git diff --quiet HEAD` re-derive
comparison at `lean-gate.sh:1593` still converges (D-1).

**AC-3 — No reader changes, and previously committed manifests keep parsing.**
`render_manifest_rows()` extracts the same `RS-n<TAB>png<TAB>sha256` rows from a padded
manifest and from an unpadded one written before this change (D-3).

**AC-4 — The verdict record is formatted with a locally resolved formatter.** After writing
`$rec`, `cmd_verdict` resolves a prettier binary — the worktree's `node_modules/.bin/prettier`,
then the main checkout's — and runs it in write mode over the record path. The `npx --yes
prettier@x` rung of `verifyctl.sh`'s ladder is deliberately **not** carried: a gate call must
not reach the network (D-5). The shared two rungs are carried as a `verbatim` row in
`scripts/lockstep-manifest.tsv` against `verifyctl.sh`'s `resolve_prettier`.

**AC-5 — Formatting never damages the header contract.** The pre-format bytes are retained;
after the formatter runs, every header key the writer emitted is re-read through
`header_key()`. On any missing or changed value — or on a non-zero formatter exit — the
unformatted bytes are restored and exactly one warn line is emitted. Grounded: `header_key()`
is `^key:`-anchored across three lockstep readers, and prettier under `proseWrap: "always"`
joins the header block into one line, which silently degrades the round to a chain root and
drops `fidelity:` (D-4).

**AC-6 — An absent formatter is a consumer fact, not a run defect.** When neither rung
resolves, the format step is skipped with one warn line. Neither this nor AC-5's revert path
fails the `verdict` call or any milestone (D-6).

**AC-7 — Both commit instructions name the formatting obligation.** The milestone-3 "commit it
and re-run milestone 3" message and the milestone-4 "commit and push it" messages state that,
in a repo whose format gate covers `$PLANS_DIR`, the markdown committed alongside — the spec
and the intent-gap record, which D-8 leaves untouched — must be formatted first. This lands
**as well as** AC-1 and AC-4, not instead of them (D-9). The milestone-3 message additionally
states, on a re-derive, that the padded rewrite moves `reviewed_patch_id` and therefore voids
an in-flight verdict, costing one review round (D-12) — the #372 re-stamp precedent is not
extended to a formatting-only delta. Both halves are guarded, on separate cases: the milestone-3
message and each of milestone 4's two refusal branches (never-committed, committed-but-dirty),
which are a different code path and could have taken the notice on one and missed the other.

**AC-8 — The Prettier-exact claim is bound by byte-exact fixtures, and CI takes no node
dependency.** `lean-gate-selftest.sh` gains golden cases for width-from-value,
width-from-header, a single-row table in the shipped five-column shape, and the minimum-3-dash
case. The last is unreachable through the render path — every manifest column is wider than
three characters — so the padder is exercised through a **library-mode** source of the real
`lean-gate.sh` rather than a copy of it in the suite. One live-prettier diff case re-derives
**every** golden — each pair is kept as it is declared, because the two variables are reassigned
in place and a reader at the end would otherwise only ever see the last and narrowest — and is
reported **SKIP**, never a failure, when no formatter resolves. That case splices an unpadded
delimiter row into each input before handing it over: the padder's contract is that the row is
*not* supplied, but markdown needs it for a table to exist, so without the splice Prettier reads
a paragraph, rewrites nothing, and the case fails wherever a formatter resolves instead of
re-deriving anything. AC-5's revert path is driven by a fake formatter installed at the rung the
resolver actually probes, which joins the
header block — deterministic, no prettier needed — alongside a benign-formatter case, so a gate
that silently formatted nothing cannot pass. AC-3 is covered by parsing a padded and a legacy
unpadded manifest through the same reader. No workflow gains a node or prettier install; a future
Prettier table-format change is caught by whoever runs the suite locally (D-10, D-11).

**AC-9 — Two docs are brought current.** `docs/live-render.md`'s lean-lane wiring section
records that the receipt is written pre-padded to Prettier's table form and that the gate never
reaches the network to format, so a consumer reading it after a red `format:check` finds the
answer and the OR-1/OR-2 flanks. `docs/testing.md` records the library-mode seam AC-8 introduces
— what it is for, and the positional-parameter caveat — because it is a newly sanctioned way to
reach a pure production helper from a suite, and an author who does not know it exists writes
the mirror harness the same page forbids.

**AC-10 — `lean-gate-selftest.sh` is hermetic against an exported `RUN_ID`.** Found while
verifying this change, and in scope because it blocks the milestone that verifies it: the
checklist tells every run to export `RUN_ID`, `(d5)`'s linked-worktree `entry` call is the one
gate invocation that does not unset it, and `entry` seeds `<issue>-run-id` from what it
resolves — so `(k6)`'s milestone-5 `mark` later finds an identity the comment fixture's marker
does not carry, posts instead of skipping, and reds on the `GH_BOT` that same helper unset. The
suite unsets the variable once at the top, beside the `LEAN_RUN_MODEL` guard it already carries
for exactly this failure mode; cases that need a value set one. Verified by running the suite
with and without `RUN_ID` in the environment.
