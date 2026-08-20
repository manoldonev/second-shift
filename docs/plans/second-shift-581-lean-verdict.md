# lean review verdict — #581

verdict=approve
run_id: review-581-1
session_id: a6b169ec-4c22-4872-8a5e-a42ed5e21c85
rounds: 1
pr: #602
reviewed_head: 12e29a2e90e717c327e154be74c17a544c7eab67
reviewed_patch_id: 381323ed2b986f9b1601b0680b7ef97947ae2142
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full branch diff (`602b0f0..HEAD`, nothing to inherit). Docs-only change: `CLAUDE.md`
(+4), `docs/testing.md` (+14), and the new committed spec. No shell, no `.mjs`, no CI, no
register TSV edited.

Every evidentiary claim in the PR body was re-derived independently in this checkout rather than
read. All six ACs are satisfied. Two warnings, both in the new `docs/testing.md` paragraph;
neither is a blocker.

## Independent verification

A standalone replay of `mutation-sweep.sh`'s own three catalog checks (`tools/mutation-sweep.sh:1849-1866`
— sed exit code, byte-identical-output = anchor drift, `bash -n`) was written against every data
row of `tools/mutation-catalog.tsv` at the reviewed head:

```
=== total=66 stable=66 drift=0 invalid_sed=0 bash_n_fail=0 missing_guard=0
```

The PR body's per-row table was then set-compared against the TSV: 66 body rows vs 66 TSV rows,
zero ids in one and not the other, zero duplicates, and zero mismatches in the guard column
across all 66. The table is a faithful per-row rendering, not an aggregate dressed up as one.

The `scope-completeness-reviewer` reached PASS having built and run its own replay of the same
three checks — an independent path to the same 66/66.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `docs/testing.md:518` | Cross-reference points the wrong way |
| 2 | Warning | `docs/testing.md:512`, `CLAUDE.md:195` | "execution surfaces" is named as a bound row kind but has no referent |
| 3 | Suggestion | PR body | AC-1's triage evidence leaves no repo artifact |
| 4 | Suggestion | `CLAUDE.md:194-197` | No lockstep row pairs the two statements of the rule |

### 1 — Warning: `(comment exclusion, above)` points below, not above

`docs/testing.md:518` reads "That class shrinks by removing the site from enumeration (comment
exclusion, above)". The comment-exclusion paragraph — **A comment line is not a site.** — is at
line 524, six lines *below* the reference. Grepping every `comment` mention earlier in the file
returns only lines 205, 261 and 273-274, none of which discuss comment exclusion. So a reader
following "above" finds nothing and has to read forward to recover the referent.

One word. Not a blocker: the sentence's claim is correct and the referent is six lines away, so
nothing is misdirected for long. Worth fixing whenever this paragraph is next touched.

### 2 — Warning: "execution surfaces" has no referent in the register schema

Both new statements scope the rule the same way — `docs/testing.md:512` "It binds **catalog rows
and execution surfaces**", `CLAUDE.md:195` "that binds catalog rows and execution surfaces". The
sentence's subject in both is a *register row* ("A register row survives only if…"), but the
register set is exactly four files — baseline, catalog, pair-map, exclusions — and none of them
has a row kind called an execution surface. In the parent ticket's own vocabulary an execution
surface is a place the sweep *runs* (the milestone-3 lane, the PR CI job, the nightly cron —
intake Q10/Q11/Q13), which is not a row at all.

The prose then explains only the catalog half concretely ("every `tools/mutation-catalog.tsv`
`note` states what a survivor would mean") and never says what an execution surface is or where
one lives, so the scope half of the rule is not actionable by the next reader.

Not a blocker, for two reasons. The term is inherited verbatim from binding intake decision D-10
("The test binds catalog rows and execution surfaces only") and is written into AC-5 itself, so
the PR satisfies the AC as written — re-deciding it here would be re-litigating a settled intake
decision. More importantly the load-bearing half of AC-5 is the *exemption*, and that half is
stated correctly and unambiguously in both surfaces: the failure mode the AC exists to prevent
(a future reader deleting unkillable-by-construction baseline rows and redding the next sweep) is
prevented.

### 3 — Suggestion: AC-1's evidence is PR-body-only

The 66-row triage table, AC-3's origin check and AC-4's register-mass table live only in the PR
description, which is unversioned and editable after merge. Both the issue's AC-1 and the spec's
AC-1 name the PR body as the delivery surface, so this is compliant, not a deviation — but the
entire evidentiary artifact for a 66-row triage leaves no trace in the repo. If this triage is
ever to be re-run for comparison, the replay script is the thing worth keeping, not the table.

### 4 — Suggestion: no lockstep row for the two statements of the rule

`CLAUDE.md:194-197` and `docs/testing.md:510-523` now state overlapping contract text with no
`scripts/lockstep-manifest.tsv` row pairing them. Raised and dismissed: this is precisely the
sanctioned "it summarizes, it does not duplicate" pattern that CLAUDE.md uses throughout, each
instance closing with "Full contract: `docs/testing.md`" — and the new sentence sits immediately
before exactly that line. No other CLAUDE.md → docs/testing.md summary carries a manifest row
either, and the one pair that was considered (the test-tier map) is recorded DROPPED at
`scripts/lockstep-manifest.tsv:86-94` as deliberately non-parallel. Adding a row here would be
inconsistent with the file's own established practice.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — every catalog row triaged, per row | **satisfied** | Replayed all three checks over all 66 rows at the reviewed head: 66 stable, 0 drift, 0 invalid sed, 0 `bash -n` failure, 0 missing guard. Body table id-set is an exact match to the TSV (66/66, no extras, no dupes), guard column matches on all 66. Classification (a) for every row is reproduced, not taken on trust. |
| AC-2 — a DROPPED row states what is lost | **satisfied** (vacuous) | AC-1 dropped no row, so no regression class is lost. The PR body states the vacuity explicitly rather than leaving it silent, which is what the AC asks for. |
| AC-3 — exclusions rows still cite their origin | **satisfied** | `tools/mutation-exclusions.tsv` is unchanged base→HEAD (empty `git diff --stat`). Both rows restating CLAUDE.md's register (`_effective-registry.sh`, `install-gh-bot.sh`) still end "Origin: CLAUDE.md, not this file." The other two are the ones CLAUDE.md itself names as the sweep's alone. No pair moved. |
| AC-4 — register mass re-derived, not quoted | **satisfied** | Measured at the reviewed head: baseline 159, catalog 107, pair-map 36, exclusions 22, total 324 — reproducing the PR body's figures exactly. See the warning below on the literal wording. |
| AC-5 — rule written into a contract surface, scoped | **satisfied** | Both `docs/testing.md:510-523` and `CLAUDE.md:194-197` state the rule, name the kinds it binds, and name the exempt kind (baseline rows recording an unkillable-by-construction site) with the consequence spelled out. The exemption is correct against `docs/testing.md:542` — a survivor absent from the baseline is exactly what reds a lane, so deleting such a row would red the next sweep as claimed. Findings 1 and 2 attach here. |
| AC-6 — no baseline row deleted by this slice | **satisfied** | `tools/mutation-baseline.tsv` blob is `d20f868b5b549f01a1ced2b1940ba9f5ef089a9d` at both `602b0f0` and HEAD — byte-identical, not merely diff-clean. |

### AC-4, on the literal wording

The issue's AC-4 says the parent ticket's figures "must not be quoted"; the PR body does
reproduce them, in a column labelled `ticket's filing-time figure (2026-08-16, stale)`. The
committed spec restates the AC as "next to the parent ticket's stale filing-time figures — not a
substitute for them," which is a real softening of the ticket's literal constraint.

Scored satisfied rather than blocked. The harm the AC guards against is a reader taking 427 as
current, and the body's presentation prevents that harm rather than causing it: the measured
figures are the primary column, the stale ones are labelled stale and dated, and the delta is the
thing that makes the register-shrink argument legible at all. Treating a side-by-side comparison
that loudly marks its own staleness as a violation of "must not be quoted" would be gate-lawyering
against the AC's evident purpose. Flagged so the deviation is visible rather than absorbed.

## Prose-budget and gate context (not findings)

`prose-budget.sh` reports 3 FAILs at this head — `plugins/second-shift/skills/onboard/SKILL.md`,
`tools/capability-parity-check.sh`, `tools/capability-parity-check-selftest.sh`. All three
reproduce identically on a clean `602b0f0` worktree and sit on files this PR does not touch:
pre-existing, not this PR's. `check-lockstep-pairs.sh` is green (23 pairs, 0 failed). Neither
frozen file nor changelog-trailer rules are at risk — no `plugins/**` path is touched and both
commits carry a `Changelog:` trailer regardless.

## Panel

Trivial-inert routing (every changed file is Markdown outside `.claude/`): `maintainability-reviewer`
+ `scope-completeness-reviewer` (unconditional, issue referenced). Both returned `approve` with
zero findings; no reviewer went dark. `a11y-reviewer` and the design-fidelity dimension were not
routed — no changed path matches `stageParams.webComponentGlobs` (unset, so the shipped default
`apps/web/**/*.{tsx,jsx}`). The spec declares no `## Design` section and no `| RS-n |` rows, so
the fidelity arm is unarmed and scored `not-applicable`.

Noted against the routing: `CLAUDE.md` is agent-instruction prose and behaviorally the same class
of self-modifying surface the trivial-inert carve-out protects when it sits under `.claude/**`,
even though it does not literally live there. The compensation was the mechanical verification
above rather than a deeper reviewer lineup, since security/performance/complexity have no surface
to assess on a pure-prose diff — the risk on this diff is a *false statement* in a contract, and
that was checked claim by claim against the code.

## Verdict

**approve.** No blockers. Every AC is satisfied against evidence re-derived in this checkout, and
the two warnings are both prose defects in a paragraph whose load-bearing claim — the exemption
that stops a future reader from deleting unkillable-by-construction baseline rows — is correct.
