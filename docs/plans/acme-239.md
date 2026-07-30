# Plan — #239: enum-validate in-pipeline Decision Ledger provenance

## Context

`plan-lint.sh` Check 4 is named "Decision Ledger provenance legality" but validates only the
human-attributed subset. It scans every cell of a `| D-n | … |` row for a cell whose entire
trimmed content is `user-answered` or `user-delegated`, and when it finds one with no backing
`{issue}-ledger.md` it fails. That is the **fabrication guard** — a run cannot claim a human
made a call it never asked about. It is the only thing Check 4 does.

Everything else in a provenance cell passes unexamined. `ledger-lint.sh` holds the full
five-value enum, but it only ever runs against a backing pre-flight ledger file, which an
autonomous run that authors its ledger in-pipeline does not have. So for the common case —
`plan-interview` was not run — **no gate enum-validates provenance at all**, including the
literal `assumed` that `ledger-lint` singles out as illegal.

Run #217 demonstrated it: `docs/plans/acme-217.md` passed both `plan-lint` invocations (the
Stage-3 advisory and the Stage-4 hard gate) while failing `ledger-lint` with three violations —
rows annotating a legal enum value with a parenthetical. That damage was cosmetic. The hole is
not: nothing distinguishes those rows from a row reading `assumed`, or from free prose.

This change widens Check 4 to a positional full-cell enum assertion, keeping the fabrication
guard as a separate violation class, and reconciles the lockstep manifest row that currently
describes a narrowing which will no longer exist.

## Assumptions

- Committed plans under `docs/plans/` are never re-linted. `plan-lint.sh` runs only against the
  current run's own plan, at Stage 3 (advisory) and Stage 4 (hard gate) — verified: the only
  invocation sites are `stages/3-write-plan.md`:49 and `stages/4-plan-review.md`:17, both passing
  `"$WORKTREE/$PLAN_REL"`. So tightening the check cannot retro-break history.
- Stage 4 lints this run's own plan using the **installed plugin-cache** copy of `plan-lint.sh`,
  not the edited worktree copy, so there is no bootstrapping hazard from tightening the check in
  the same run that must pass it.
- The canonical Decision Ledger column order is `ID | Decision | Resolution | Provenance`. Three
  independent sites agree: `interviewing-baseline`'s canonical table, `ledger-lint.sh`'s positional
  parse, and `plan-lint.sh` Check 6's positional parse.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Whether the widened check may rely on column position, given a non-uniform historical corpus | Yes — the canonical `ID \| Decision \| Resolution \| Provenance` order is normative. Seven older plans (`acme-93/99/102/105/110/145/146`) use `Provenance` in column 3, and `acme-187` uses a 3-column shape, but none is ever re-linted; everything from `acme-186` on is canonical. The violation message names the expected schema so a drifted table reads as a column-order problem, not an illegal value | codebase-derived |
| D-2 | What column counts the widened check accepts | 5 or 6 raw fields after the `IFS='\|'` split (leading empty + 4 cells + optional trailing empty), matching Check 6's existing tolerance. Anything else is a named violation, not a skip | codebase-derived |
| D-3 | Whether to correct the stale advice clause in the fabrication-guard message, which says an autonomous run may only use `codebase-derived`/`deferred` while the canon also permits `ticket-sourced` | Left untouched this run. AC-3 pins the current message and the issue Scope calls it good; the contradiction is pre-existing and the widening neither introduces nor worsens it. Recorded as a follow-up for the maintainer | deferred |
| D-4 | How to reconcile the lockstep manifest once plan-lint holds the full enum | Two anchors, two rows. `verbatim` compares the entire extracted block and `subset-of`'s `first_enum()` takes `head -n1` of the quoted literals, so co-locating both literals in one anchor would make the existing row's outcome depend on declaration order — and invisibly, since both literals are subsets | codebase-derived |
| D-5 | Whether to implement the `ticket-sourced` Resolution-URL citation check | Out of scope per the issue; it needs its own decision about what counts as a citation. Recorded as a follow-up recommendation in the PR body, no issue filed — that call is the maintainer's | deferred |
| D-6 | Where the canonical column schema becomes normative for a Stage-3 author | `stages/3-write-plan.md`, which today describes the Decision Ledger's lint tiers but never states the column schema the new hard gate enforces | codebase-derived |

## Affected files

- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — widen Check 4; add the full-enum literal
  under a new lockstep anchor; move `HUMAN_PROVENANCE` to its own anchor.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` — add the AC-1..AC-3 cases plus a
  malformed-row case.
- `scripts/lockstep-manifest.tsv` — replace the single `subset-of` row with a `verbatim` row and a
  re-pointed `subset-of` row; rewrite the header prose that asserts the narrowing.
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — state the canonical Decision Ledger
  column schema (per D-6).

## Reuse inventory

- `trim()` (`plan-lint.sh`:75) — the quoting-safe whitespace trim already used by Checks 2/4/6.
- `violate()` (`plan-lint.sh`:72) — the violation accumulator; new messages follow its existing
  `"$id row: …"` shape.
- The masked-split row-parse idiom (`plan-lint.sh`:348-356, Check 6) — mask `\|` to `${PIPE_SENTINEL:-…}`,
  `IFS='|' read -r -a cells`, validate the field count, `trim()` each cell. Check 4's widened parse
  mirrors it rather than inventing a second convention.
- `PROVENANCE_ENUM` (`ledger-lint.sh`:43) — the canonical literal; plan-lint's new copy carries the
  identical variable name so the `verbatim` lockstep pair can compare whole blocks.
- The `LOCKSTEP-BEGIN`/`LOCKSTEP-END <anchor>` marker convention, consumed by
  `scripts/check-lockstep-pairs.sh`.

No new helpers introduced.

## Implementation steps

1. In `plan-lint.sh` Check 4, split the single lockstep block into two anchors: the existing
   `provenance-enum` anchor is repurposed to hold exactly the full-enum assignment `[NEW]`
   `PROVENANCE_ENUM='user-answered|user-delegated|codebase-derived|deferred|ticket-sourced'`
   (one line between the markers, so the `verbatim` compare matches `ledger-lint.sh`'s block), and
   a `[NEW]` `human-provenance-enum` anchor holds the existing `HUMAN_PROVENANCE` assignment
   unchanged.
2. Rewrite Check 4's header comment: it currently states the check guards the human subset only.
   Describe the two violation classes and the normative column order.
3. In the Check 4 row loop, keep the existing every-cell human-token scan and the `HUMAN_ROWS`
   accumulation **before** any early exit, so a malformed row still cannot smuggle a human
   provenance past the fabrication guard.
4. Add the field-count assertion after the human scan: a row whose split yields fewer than 5 or
   more than 6 fields raises a malformed-row violation naming the row id and the canonical schema,
   then skips the enum assertion for that row.
5. Add the positional enum assertion on `cells[4]`. Split the failure into two messages: a cell
   that starts with a legal enum value followed by anything else gets the annotation message
   ("the cell must be the bare enum value"); anything else gets the not-in-enum message, which
   names the full enum, the canonical column order, and the `assumed` carve-out.
6. Leave the fabrication-guard block and all three of its messages byte-unchanged.
7. In `plan-lint-selftest.sh`, extend the Check 4 block with five `[NEW]` cases —
   `(pl-u1)` `assumed` (AC-1), `(pl-u2)` free prose (AC-1), `(pl-u3)` a legal value with a trailing
   parenthetical (AC-2), `(pl-u4)` a `ticket-sourced`-only plan passing (AC-3), and `(pl-u5)` a
   malformed 3-column row carrying no human token (D-2's class, which today passes silently).
8. In `scripts/lockstep-manifest.tsv`, change the `provenance-enum` row's relation to `verbatim`
   and add a `[NEW]` `human-provenance-enum subset-of` row pointing at the new plan-lint anchor;
   rewrite the header comment block above them.
9. In `stages/3-write-plan.md`, add the canonical column schema to the Decision Ledger bullet.
10. Run the red-on-mutation demo: revert step 5's enum assertion, confirm the new AC-1/AC-2 cases
    go red, restore it, and record the transcript in the commit body.

## Test strategy

Verify-after — this is a lint tightening in shell with an existing behavioral selftest. New cases
extend `plan-lint-selftest.sh`'s existing Check 4 block (`[plan-lint-selftest] Decision Ledger
provenance legality (Check 4)`), reusing its `make_ledger_plan` fixture builder and `lint_rc`
helper, with mnemonic ids continuing the block's series.

Regression surface checked ahead of the change — every existing ledger row in the corpus the suite
exercises already carries a bare enum value, so the widened check does not retro-break them:

- Check 6 fixtures (`hydration-ledger.md`, `hydration-wording-plan.md`, `hydration-emphasis-plan.md`,
  `hydration-whitespace-plan.md`) — all `codebase-derived`.
- Inline selftest rows for `(pl-n)`…`(pl-ab)` — all bare enum values.
- `(pl-t)` (malformed row + human token) asserts only `rc=1` and a `D-1` mention; it now fails for
  two reasons instead of one and stays green.
- `(pl-u)` (enum named in prose cells, provenance `codebase-derived`) passes by construction under a
  positional parse.
- `scenario-liveness-selftest.sh` builds its plans from `valid-plan.md`, which carries no `D-n` rows.

AC-4's red-on-mutation demo is the mutation evidence: reverting the step-5 assertion must turn the
new AC-1/AC-2 cases red while every pre-existing case stays green.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Out-of-enum provenance cell fails, naming the row | 5 | `(pl-u1)` assumed, `(pl-u2)` free prose |
| AC-2 | Annotated legal value fails, message says bare enum value | 5 | `(pl-u3)` trailing parenthetical |
| AC-3 | Fabrication guard unchanged; grounded/ticket-sourced plans pass | 3, 6 | `(pl-n)`, `(pl-s)` unchanged; `(pl-p)` unchanged; `(pl-u4)` ticket-sourced |
| AC-4 | Selftest covers AC-1..AC-3; commit body records red-on-mutation | 7, 10 | `(pl-u1)`–`(pl-u4)` plus the recorded mutation transcript |
| AC-5 | Manifest reconciled; `check-lockstep-pairs.sh` green | 1, 8 | — no test (covered-by-selftest) |

## Verification commands

```bash
bash plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh
bash scripts/check-lockstep-pairs.sh
bash plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh
bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **A future Stage-3 run authoring a wrong-column-order ledger now hard-fails at Stage 4.** This is
  the intended tightening, but the failure could read as "your provenance value is illegal" when
  the real problem is the table shape. Mitigated by naming the canonical schema in the message
  (step 5) and stating it in `stages/3-write-plan.md` (step 9).
- **`verbatim` is a stricter lockstep relation than `subset-of`.** Any future edit to
  `ledger-lint.sh`'s enum block — including a comment moved inside the markers — now fails
  `check-lockstep-pairs.sh` until plan-lint's block is updated to match. That is the point of the
  relation, but it is a tighter coupling than exists today.
- Rollback is a straight revert: the three code/manifest edits are independent of any state schema
  or contract consumed elsewhere.

## Out-of-scope

- Making `ticket-sourced` Resolution-URL citation a `plan-lint` check (D-5). It needs its own
  decision about what counts as a citation. Recommended as a follow-up in the PR body.
- Correcting the stale `codebase-derived/deferred` advice clause in the fabrication-guard message
  (D-3). AC-3 pins the current message.
- Re-linting or migrating the historical `docs/plans/` corpus. Those files are never re-linted.
- Any change to `ledger-lint.sh` — it is the canonical side of the lockstep pair and stays as-is.

Unverified references: none.
