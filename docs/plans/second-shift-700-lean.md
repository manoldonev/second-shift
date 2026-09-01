# second-shift #700 — a bullet-form `## Open regions` section extracts zero ids

`lean-gate.sh`'s `pause_and_ask_ids` parses open-region ids with `awk -F` on the pipe character,
so it recognizes a region only when it is written as a GFM table row. A section that declares its
regions as bullets extracts zero ids, and milestone 1's pause-and-ask refusal returns CLEAR having
checked nothing.

Intake measured the corpus and found the defect is **three fail-opens in the same two functions**,
not one:

1. **The row parse.** A bullet carries no pipes, so `id` is empty and `disp` is the whole line.
   7 of the 11 issue bodies that declare regions with ids use bullets; the table form has not been
   used in an issue body since #381.
2. **The section extractor's depth handling.** `open_regions_section` terminates on *any* following
   heading, so a heading-per-region section (`### OR-1`) yields zero non-blank content lines and
   reads as an empty section rather than an unparseable one.
3. **The section heading anchor.** The heading regex is anchored to end-of-line, so
   `## Open regions (BUILD flags, does not pause)` (#636, #622) is not recognized as the section at
   all — the most severe of the three, because nothing is misparsed and so no refusal can fire.

The fix widens what can be enumerated, and — the load-bearing half — makes a section that asserts
regions the parser *cannot* enumerate fail closed, so shape coverage is no longer the only thing
standing between the gate and the next unanticipated form.

Both declared sources (the pre-flight receipt's `## Open Regions` table and the issue body) go
through the one `pause_and_ask_ids`, so one fix covers both. The receipt half is genuinely exposed
at build time: milestone 1 runs `ledger-lint --reconcile`, whose header states it "says nothing
about the receipt's `OR-n` regions, which the lean gate's own `check_pause_and_ask` already owns."

## Acceptance Criteria

**Enumeration — what the parser can now read**

- **AC-1** `open_regions_section` recognizes a section heading carrying trailing text after the
  words "open regions" (e.g. `## Open regions (BUILD flags, does not pause)`) as the section, and
  still recognizes the bare heading. Case-insensitivity is unchanged.
- **AC-2** `open_regions_section` terminates the section only on a heading of depth equal to or
  shallower than the section heading's own. A deeper heading (`### OR-1` under `## Open regions`)
  stays inside the section, so its content is visible to the row parse.
- **AC-3** A bullet row declaring an `OR-n` is enumerated, and its disposition is found when the
  token sits on a **continuation line** of that bullet — a bullet being its first line plus the
  following more-indented lines, up to the next bullet or a dedent. Both `pause-and-ask` and
  `reversible-default-and-flag` are recognized, backticked or bare.
- **AC-4** Table rows keep working unchanged, including the trailing-pipe-less variant. The
  existing cases `(y2)`, `(y5)`, `(y6)`, `(y12)` and `(y14)` of `lean-gate-selftest.sh` stay green with no
  edit to their fixtures or expectations.

**Fail-closed — the load-bearing half**

- **AC-5** `check_pause_and_ask` returns **2** with a reason when a declared source's
  `## Open regions` section carries non-blank content, yields zero `OR-n` rows in any recognized
  shape, and is not the explicit empty form. A bullet section written in prose with no `OR-n`
  anywhere (the shape of #441, #427, #426, #363) is such a section.
- **AC-6** `check_pause_and_ask` returns **2** with a reason naming the region when an `OR-n` is
  parsed but carries no recognizable disposition token anywhere in its row or folded continuation
  (the shape of #640's OR-3). It is not read as "not pause-and-ask".
- **AC-7** Neither AC-5 nor AC-6 fires, and the check clears, for each of: no `## Open regions`
  section at all; a section whose body matches `^No open regions` (prefix, not the full canonical
  sentence); a section declaring only `reversible-default-and-flag` regions; and a section heading
  with no non-blank content under it.
- **AC-8** Both declared sources are covered — a defect-shaped section in the pre-flight ledger and
  the same section in the issue body each produce the AC-5/AC-6 refusal. Under
  `tracker.type: jira` the issue-body arm stays skipped, as today.

**Operator-facing behavior**

- **AC-9** The AC-5/AC-6 refusal is a single message naming **every** unenumerable source and
  **every** `OR-n` found without a disposition — not the first — and pointing at the shape contract
  of AC-11. Two problems in one run are discoverable in one round-trip.
- **AC-10** The refusal spends no fix attempt: it reaches the caller as the same environment
  refusal the existing rc=2 arms take, and the run's progress record gains no
  `| milestone-1 | attempt |` row from it.
- **AC-11** `interviewing-baseline`'s "Open Regions" section states the accepted shapes for both
  sources: table row and bullet for an issue body, table row for a receipt (which
  `ledger-lint --receipt` already mandates), plus the explicit empty form for either.
- **AC-12** The existing unresolved-region refusal sentence — the one the file marks as byte-for-byte
  unchanged for headless runs — is not altered. The new refusal is an additional message, not an
  edit to that one.

**Test obligations**

- **AC-13** New scenario cases in `lean-gate-selftest.sh` cover AC-1 through AC-10, driven through
  the `--issue-file` / `--ledger-file` seams rather than the network.
- **AC-14** CLAUDE.md's two obligations on ordinary PRs are discharged, and shown to be:
  every existing `tools/mutation-catalog.tsv` row addressing `lean-gate.sh` is verified to still
  bite after the edit (none was anchored on this code, so none needed re-anchoring), and
  `scenario-liveness-selftest.sh` gains a leg for the new verdict path.
- **AC-15** The new guard code is itself armed: `tools/mutation-catalog.tsv` gains rows naming the
  regression classes this change introduces the risk of, and each is **probed** — applied, and the
  paired suite run — rather than credited by construction. `lean-gate-selftest.sh` is 212s against
  the sweep's 5s slow threshold, so the `mutation-sweep-pr` job defers these rows to nightly and a
  row credited without a probe would be graded by nothing at PR time. A row's note must name the
  regression its own `sed` produces: a note describing a different mutant is what a probe that was
  run and READ would have caught, so the note is part of what the probe checks.

## Scope boundary

Not in this PR, and each recorded as a ledger row: no heading-per-region *parser* (D-8 — the
extractor fix makes that shape red instead, which is the catch-all the ticket asked for); no
`ledger-lint --receipt` run at milestone 1 (D-12); no change to the attended-session override
affordance or the rc=0 unresolved-region path (D-12, AC-12).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What milestone 1 does when a `## Open regions` section is present but no region can be enumerated from it | Red when the section carries non-blank content, yields zero `OR-n` rows in any recognized shape, and is not the explicit empty form. NOT the ticket's literal "zero pause-and-ask ids": measured, a table declaring only `reversible-default-and-flag` rows and the explicit empty form each legitimately yield zero ids, and the first is pinned CLEAR today by `lean-gate-selftest.sh` cases `(y5)` (issue body) and `(y14)` (`LEDGER_FLAG_ONLY`) | user-answered |
| D-2 | Which of `check_pause_and_ask`'s three return codes the new red takes | rc=2, UNKNOWN — an environment refusal that spends no fix attempt. Neither the issue body nor the gitignored receipt is the build role's to edit, which is exactly the function's own stated rule for rc=2 ("no edit the build role can make will fix it"); the two gh read arms and the `--issue-file` jq arm all return 2 | user-answered |
| D-3 | How much of a bullet the bullet arm reads | Fold continuation lines: a bullet is its first line plus the following indented lines, to the next bullet or a dedent. Measured — #640 OR-1 and OR-2, #639 OR-1, and #637 OR-1 all carry the disposition token on a continuation line, and #639 is OPEN with a `pause-and-ask` sitting there | user-answered |
| D-4 | A section whose bullets carry no `OR-n` at all (#441, #427, #426, #363) | Reds, as a direct consequence of D-1 — zero `OR-n` rows in any recognized shape. No separate arm is written for it. All four measured instances are CLOSED, so there is no live blast radius | codebase-derived |
| D-5 | An `OR-n` that is parsed but carries no recognizable disposition token anywhere in it | Unenumerable, so rc=2 — D-1's principle one level down. Reading it as "not pause-and-ask" is precisely the fail-open this ticket closes. Measured: #640 OR-3 ("Default **no** … Flagged because") is the only open instance | user-answered |
| D-6 | How the gate recognizes the explicit empty form | Prefix match on `^No open regions`, a recognizer rather than a fifth copy of `ledger-lint.sh`'s `OPEN_EMPTY_FORM`. `--reconcile`'s own header assigns receipt wording to ledger-lint and region enumeration to this gate, and the issue-body source has no lint to teach an operator the exact sentence | user-answered |
| D-7 | Whether the accepted shapes are stated where sections are authored | Yes. The shape contract goes into `interviewing-baseline`, the canonical source for the section, covering both sources — bounded by OR-2 below. Measured: 7 of the 11 recent issue bodies carrying rows chose bullets freehand because nothing states a shape, so a gate that reds with no documented form turns a silent pass into a silent stall | user-answered |
| D-8 | Heading-per-region (`### OR-1`) handling | Change `open_regions_section` to terminate only on a heading of equal-or-shallower depth, so the content becomes visible and reds as "content, zero rows". Do NOT add a heading-arm parser. DEPARTURE from the ticket's "at minimum: table row, bullet, and a heading-per-region" — measured zero occurrences across 15 issue bodies and 39 on-disk receipts, so a parser for it is speculative machinery, and the D-1 red is the catch-all the ticket asks for | user-answered |
| D-9 | The section heading regex is anchored to end-of-line, so a decorated heading makes the whole section invisible | Widen it to match `^#+ +open regions` with trailing text tolerated. This is the most severe of the three instances — the section is not misparsed, it is unseen, so no red fires at all. Measured: #636 and #622 carry `## Open regions (BUILD flags, does not pause)`, both bullet-form with `OR-n` rows that parse cleanly once seen | user-answered |
| D-10 | What the new rc=2 refusal tells the operator | One message naming every unenumerable source and every `OR-n` found without a disposition, plus a pointer to the D-7 shape contract. Grounded in the ergonomic the sibling refusal already states verbatim — every unresolved region, not just the first, so an operator clearing two does not pay two round-trips | user-answered |
| D-11 | Whether the widened parse covers the pre-flight receipt as well as the issue body | Yes, automatically — both callers go through the one `pause_and_ask_ids` (`lean-gate.sh:3009` and `:3025`). The receipt half is genuinely exposed at build time: lean-gate runs `ledger-lint --reconcile`, whose header states it "says nothing about the receipt's `OR-n` regions, which the lean gate's own `check_pause_and_ask` already owns" | codebase-derived |
| D-12 | Whether this ticket also runs `ledger-lint --receipt` at milestone 1 to close the build-time receipt-shape hole | Out of scope, and not needed: with D-1 and D-5 the gate itself reds an unenumerable receipt section and a row whose disposition it cannot read, which is the part of receipt check B this gate depends on | codebase-derived |
| D-13 | Effect on the three OPEN tickets whose sections this changes the reading of | Accepted as the fix working. None of #638, #639, #640 carries a queue label, so none is eligible to run before this lands. #639 OR-1's `pause-and-ask` becomes visible (correct — it passes vacuously today); #640 OR-3 becomes an rc=2 until its disposition is stated | codebase-derived |
| D-14 | Test obligations this change inherits | Per CLAUDE.md: editing a guard's code re-anchors its `tools/mutation-catalog.tsv` rows, and a new gate contract must extend the liveness scenario (`scenario-liveness-selftest.sh` already carries pause-and-ask cases). New cases sit beside `(y1)`–`(y12)` in `lean-gate-selftest.sh`; `(y3)` / `LEDGER_FLAG_ONLY` and `(y6)` / AC-15 are the non-regression pins and must stay green | codebase-derived |
| D-15 | A `## Open regions` heading with nothing under it at all | Clears. D-1's predicate is keyed on non-blank content, so a bare heading asserts nothing and is not the unenumerable case. `ledger-lint --receipt` still reds it on the receipt side at intake | codebase-derived |
| D-16 | Build model for this ticket | `opus`. Sizing basis: the deliverable is new contract arms in a shared gate function (two awk rewrites, two new red paths, a new rc=2 message), and it inherits a mutation-catalog re-anchor plus a liveness-scenario extension (D-14) and a cross-plugin doc contract (D-7). Per `intake-orchestrator` SKILL.md's sizing rule, a new guard surface is `opus`; the two open regions are both reversible with stated defaults, which does not lower it | codebase-derived |

