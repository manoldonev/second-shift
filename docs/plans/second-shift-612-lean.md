# second-shift #612 — the Decision Ledger receipt-to-plan carry-forward is hand-transcribed between two arities

Issue: [#612](https://github.com/manoldonev/second-shift/issues/612) (part of
[#605](https://github.com/manoldonev/second-shift/issues/605))
Pre-flight ledger: `.claude/pipeline-state/612-ledger.md` (binding input — gitignored, so its
load-bearing content is carried into the Decision Ledger below)

## Problem, as pinned

The pre-flight intake receipt carries a **five**-column Decision Ledger (`ID | Decision |
Resolution | Provenance | Kind`); a committed plan carries **four** (no `Kind`). `ledger-lint.sh`
enforces each arity EXACTLY — a measured decision recorded at the source, since a permissive
column range collapses receipt mode and plan mode into one parser — so a receipt row carried
across by hand fails on column count before anyone reads what it says. On a recent run milestone 1
ran four times in six minutes and spent 2 of its 3 fix attempts on column count alone; one more
formatting slip would have hard-stopped the run on a table, not on a design problem. The lint also
reports a receipt-shaped ledger as "0 ledger rows" and then adds a violation for the emptiness it
manufactured.

The lint's stance is not changed here. The fix is a mechanical projection, so the model never
retypes a row between two schemas.

## Acceptance criteria

- **AC-1:** WHEN the helper is given a receipt THEN it emits the plan-shape Decision Ledger:
  the same rows in the same order under the same `D-n` ids, with the `Decision`, `Resolution` and
  `Provenance` cells reproduced byte-for-byte (their surrounding padding included) and the `Kind`
  cell dropped. An escaped pipe (`\|`) inside a cell survives the projection unchanged.
- **AC-2:** WHEN the helper is run twice THEN the second run is a no-op — projecting its own
  output reproduces that output byte-for-byte — and WHEN a `| D-n |` row cannot be parsed at
  either arity THEN the helper fails loudly, naming the offending row, and writes NOTHING to
  stdout. A row is never silently dropped, and a partial projection is never emitted.
- **AC-3:** WHEN a receipt passes `ledger-lint.sh --receipt` THEN `ledger-lint.sh` in default
  (plan) mode passes the helper's output for that receipt. `ledger-lint.sh`'s arity semantics are
  untouched.
- **AC-4:** WHEN `build-lean`'s milestone-1 step describes the carry-forward THEN it names the
  helper as the route. The milestone-1 refusal path is unchanged — rows must still match the
  receipt's ids and Resolution text, or be marked `DEPARTURE — <reason>`. The helper is the *how*;
  the gate remains the *whether*.
- **AC-5:** WHEN the helper's behavioral selftest runs THEN it covers a multi-row receipt carrying
  an escaped pipe, a receipt in the explicit empty form, a malformed receipt row (loud error, no
  stdout), and idempotence — plus the AC-3 composition against the real `--receipt` fixture.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Remedy shape | ledger-lint keeps exact arity (a recorded, measured design decision at the source — a permissive range collapses receipt and plan modes); the fix is a mechanical projection helper that drops the Kind cell and preserves everything else byte-for-byte, loud on unparseable rows, idempotent; the lint itself is unchanged. | codebase-derived |
| D-2 | Where the helper lives and what it is called | `plugins/intake-toolkit/skills/plan-interview/tools/ledger-carry-forward.sh`, beside `ledger-lint.sh` — the ticket says "beside the existing ledger tools", and siting it there means `resolve_sibling` finds it under both the monorepo and the install-cache layout exactly as it already finds the lint. | codebase-derived |
| D-3 | What the helper writes | The whole `## Decision Ledger` section — heading, canonical 4-column header and separator, then the rows — not a bare table. AC-3 asks whether `ledger-lint.sh` passes the output; the lint's first check is the section heading, so a bare table could not be linted on its own and the caller would have to hand-assemble the part the lint checks first. | codebase-derived |
| D-4 | How cells are split, given that byte-preservation is the contract | A left-to-right walk that treats `\|` as one character and yields the RAW inter-pipe substrings, rather than `ledger-lint.sh`'s mask-with-a-sentinel-and-split idiom. The lint's parse is destructive by design (it trims and normalizes); a projector must not be. The walk also has no sentinel to be corrupted by a cell that happens to contain it. It reproduces `read -a`'s arity exactly, including dropping the empty field after a trailing pipe. | codebase-derived |
| D-5 | Which arities the helper accepts | Both: 5 columns (a receipt row) drops `Kind`; 4 columns (an already-projected row) passes through. Accepting 4 is what makes AC-2's idempotence reachable at all. This is NOT the permissive parser D-1 rejects — the lint still refuses each arity in the other's mode; the projector is the one place where reading both is the job. Anything else is a loud error. One trailing blank cell is ignored when dropping it lands on a legal arity, the idiom `ledger-lint.sh`'s `normalize_arity` already uses. | codebase-derived |
| D-6 | Whether the helper re-checks the receipt's validity | No. It refuses only what it cannot project: no `\| D-n \|` rows AND no explicit empty form. Provenance enums, the `Kind` bar, duplicate ids and the ticket-sourced citation are `ledger-lint.sh`'s to judge, in whichever mode the caller runs. A second validator here would be the third parser #562 already declined to add. | codebase-derived |
| D-7 | Whether the helper needs its own copy of the section detector | No — keying the refusal on "no rows and no empty form" answers the same question from content, so no second copy of that grep is created. The empty-form literal IS copied, because the helper must emit it byte-for-byte, and that copy is held by a `LOCKSTEP-BEGIN ledger-empty-form` pair over the two shell assignments. A drifting empty form would otherwise make the helper emit a line the lint rejects. | codebase-derived |
| D-8 | How AC-4 is guarded | It is not, and deliberately: AC-4's whole deliverable is a sentence in `build-lean/SKILL.md`, and CLAUDE.md forbids prose-presence guards — a grep for a literal in markdown asserts only that prose contains words. The edit is visible in the diff, which is where it is reviewed. The behavioral weight of this change is in the helper, which AC-5 covers, and the shipped-suite guard comes free from `install-topology-selftest.sh`'s discovery glob. | codebase-derived |

## Design

Design: none — this repo configures no `design.provider`, and the change adds a CLI helper and one
sentence of skill prose. No route, no render state, no user-visible surface.

## Implementation

### 1. `ledger-carry-forward.sh` (AC-1, AC-2, AC-3)

New, beside `ledger-lint.sh`. `ledger-carry-forward.sh <receipt-path>`, plus `-h|--help`.

- Rows are found with the same whole-file `grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|'` the
  lint uses, so "the rows" means the same set on both sides.
- `split_row` walks the line, treating `\|` as one character, and appends the raw inter-pipe
  substrings to `CELLS`; a single empty trailing element is dropped so arity means what it means
  in `ledger-lint.sh`.
- Arity 6 cells (5 columns) → emit cells 1–4. Arity 5 (4 columns) → emit cells 1–4 unchanged.
  A blank last cell is ignored when that lands on 6 or 5. Anything else is a loud error naming
  the row.
- Output is **buffered**: on any error nothing reaches stdout, so a partial projection can never
  be redirected into a file. The row count goes to stderr, which is the receipt that no row was
  dropped.
- Zero rows: the explicit empty form is required in the input and reproduced in the output;
  absent, that is a loud error rather than a manufactured claim that no decisions were made.

Exit codes mirror the lint: `0` clean, `1` a projection this input does not admit, `2` usage/IO.

### 2. `ledger-lint.sh` (AC-3, D-7)

Comment markers only — a `LOCKSTEP-BEGIN ledger-empty-form` pair around the existing
`EMPTY_FORM=` assignment, matched by the helper's copy. No behavior, and no arity semantics,
change.

### 3. `build-lean/SKILL.md` milestone-1 step (AC-4)

The step-4 sentence about the pre-flight ledger gains the helper as the named route. The refusal
it describes is unchanged.

### 4. `ledger-carry-forward-selftest.sh` (AC-5)

Beside the helper; discovered by `tools/run-selftests.sh`'s glob, so no registration. Cases:

- the real `ledger-lint-fixtures/valid-receipt.md` projects to 5 rows, `D-2`'s `\|` intact, no
  `intent`/`fact`/`open` token left in the output;
- that output passes `ledger-lint.sh` in default mode (the AC-3 composition) — and the fixture
  passes `--receipt`, so the premise is real rather than assumed;
- projecting the output again reproduces it byte-for-byte;
- a receipt in the explicit empty form projects to the explicit empty form, and that is
  idempotent too;
- a 6-column row and a 3-column row each exit 1, name the row on stderr, and write nothing to
  stdout;
- a receipt with neither rows nor the empty form exits 1 and says so;
- a missing file exits 2.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
bash scripts/check-lockstep-pairs.sh
```

## Out of scope

- `ledger-lint.sh`'s arity semantics, and the receipt schema (columns, `Kind` enum) — both named
  out of scope by the ticket and by D-1.
- `prose-budget.sh`'s `build-lean/SKILL.md` row. That baseline is already stale on `main`
  (1488 recorded, 1656 measured before this change), so the nightly advisory is red there
  today. Re-recording it here would absorb growth this change did not cause; the sentence
  AC-4 adds is 33 words.
- Teaching `lean-gate.sh` to call the helper. The gate's job at milestone 1 is to refuse a spec
  that did not carry the receipt forward; producing the rows is the session's, and a gate that
  wrote them would be grading its own output.
