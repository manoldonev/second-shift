# second-shift #579 — comment lines stop enumerating as mutation sites (lean spec)

Issue: https://github.com/manoldonev/second-shift/issues/579
Parent: #567 (mutation-sweep reshape). Successor: #583 — workable only once this lands, and
based on `main` AFTER it, never stacked on this branch.
Pre-flight ledger: none filed for #579. `.claude/pipeline-state/567-ledger.md` is the parent
receipt the ticket cites; its D-4/D-5/D-6/D-9/D-10 are binding sequencing input and are not
re-litigated here.

## Problem

Site enumeration in `tools/mutation-sweep.sh` treats every line an operator's ERE matches as a
mutation site, including comment lines. A comment flip is unkillable by construction — nothing
behavioural can observe it — so each such site is a guaranteed survivor that must be carried in
`tools/mutation-baseline.tsv` forever, and, because the per-guard-per-operator budget is `k=2`,
it displaces real code sites out of the swept window entirely. That is the vacuous-green class:
a green sweep proves count and labels, never identity.

Re-measured on this branch's base (`d344956`, post-#348 and post-#584) — every figure below is
reproduced, not inherited from the ticket:

| Measure | Value |
| --- | --- |
| Generic (ordinal-keyed) baseline rows | 142 |
| …whose site is a comment line | **41** (29%) |
| …whose ordinal changes once comments stop enumerating | **6** |
| …unchanged | 95 |
| Comment sites sweep-wide, all ordinals | 72 site-instances over 70 distinct lines |
| Comment sites inside the `k=2` window | **43** (41 baselined + 2 unbaselined, below) |
| Real code sites promoted from beyond-budget into budget | **28** |
| Operator×guard pairs whose sites are *entirely* comments | **6**, across 6 guards |

## The rule

Exclude lines matching `^[[:space:]]*#` from the operator's matched-line list, **between** the
`grep -nE --` that enumerates sites and the `while read` that walks them — not as a `continue`
inside the mutation loop, which would consume the ordinal. The heredoc-and-quote-aware
classifier is rejected per the ticket: an order of magnitude more code, living inside the one
file the sweep is forbidden to sweep (`tools/mutation-exclusions.tsv`, recursion guard), and a
net add under the 2026-08-16 deletion doctrine.

## Acceptance criteria

- **AC-1 — the filter sits before the ordinal counter.** Lines matching `^[[:space:]]*#`
  are removed from `SITES` immediately after the enumerating `grep -nE --` and before the
  `while read` loop, so an excluded line contributes no mutant **and consumes no ordinal**. An
  in-loop skip is not acceptable: the selftest case in AC-6 distinguishes the two.
- **AC-2 — the baseline sheds its comment rows.** Every generic baseline row whose site was a
  comment line is deleted: **41** rows, reconciled in the PR body against the 41 the ticket
  measured.
- **AC-3 — surviving rows are re-keyed in the same diff.** The **6** rows whose ordinal moves
  are re-keyed here and named individually in the PR body.
- **AC-4 — the two unaccounted sites are resolved with CI evidence.** The PR body states, per
  site, whether it was a live kill or an unbaselined survivor, citing a CI run.
- **AC-5 — both accepted residues are stated with current sizes.** Trailing comments still
  enumerate (measured: 4 of 142 generic rows sit on a code line containing a `#`); `#`-leading
  heredoc payload stops enumerating (measured: 0 such lines in today's swept universe).
- **AC-6 — a falsifiable selftest case.** `tools/mutation-sweep-selftest.sh` gains a case whose
  fixture guard's first matched line for an operator is a comment and whose next lines are real
  code, and which asserts by **survivor ordinal** that the code site is ordinal 1 — an assertion
  that reds both under no filter and under an in-loop skip. `mutants_applied` alone is not the
  assertion. The case is shown falsifiable by hand-reverting the filter once; the resulting red
  is recorded in the PR body.
- **AC-7 — an all-comment operator is reported, not silent.** When every matched line for an
  operator in a guard is excluded, the report says so in a **third tally**, distinct from "no
  applicable site". It follows `sites_beyond_budget`'s precedent: appended last, per-operator
  plus-joined detail, report-only, never red.
- **AC-8 — the baseline is edited by hand.** No `--seed` run: re-seeding flattens the
  hand-written rationale on 32 rows and stamps a macOS environment header that reds CI.
- **AC-9 — contract surfaces describe the exclusion.** `tools/mutation-operators.tsv`'s header
  ("A SITE IS A MATCHED LINE … Ordinals index this operator's FULL matched-line list") and
  `docs/testing.md` state it. `docs/testing.md`'s standing `k=2` passage argues from
  displacement evidence this change invalidates; it is re-derived against the numbers above,
  not left standing.

## Non-goals

- Content-keyed survivor ids (#583, the successor slice).
- `tools/mutation-catalog.tsv` rows — `catalog::<cid>` ids are not ordinal-keyed.
- The nightly sweep of record, the merge boundary, never-self-merge.

## Cross-lane note

#585 is in flight and rewords `orchestrate-lean.sh`'s line 251 so the two operator literals in
that comment stop matching — the same two sites AC-4 resolves. This change removes them
structurally, for every comment in the tree rather than one; the two are compatible and whichever
lands second rebases. Nothing here depends on #585.
