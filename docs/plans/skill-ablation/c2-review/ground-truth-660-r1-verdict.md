# lean review verdict — #642

verdict=needs-work
run_id: review-642-1
session_id: f6ee9c56-5d21-433f-a272-88fbe07af11e
rounds: 1
pr: #660
reviewed_head: 642a6b13d94aaab9b2de4e84edd4e8fa79f54d8a
reviewed_patch_id: 7698981723b370c033362e8dec398e6ecccea011
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR 660 (#642)

Range read: `bf231bd..642a6b1` (full branch diff; round 1, nothing to inherit).
Reviewed from the lane worktree with the branch checked out. Head re-verified unchanged
after review.

**Verdict: needs-work — 2 blockers, both on AC-3.** Every other AC is satisfied. The two
blockers are narrow and both live inside AC-3's own contract; nothing in AC-4, AC-8 or the
deletions is wrong.

## Blockers

### B1 — AC-3 is half-applied: two announcement-class reasons still charge the fix budget on the `close-out` path

AC-3: *"every reason `docs/gate-ablation.md` adjudicates `unchanged` reaches `append_absent`."*

The milestone-5 **assert** path was correctly re-verbed. The **`close-out`** path was not:

| site | call | verb written |
| --- | --- | --- |
| `lean-gate.sh:4565` (`cmd_5`) | `block_milestone 5 "progress file is not current — …"` | `absent` ✅ |
| `lean-gate.sh:4846` (`cmd_close_out`) | `fail_milestone 5 "progress file is not current — …"` | **`attempt`** ❌ |
| `lean-gate.sh:4581` (`cmd_5`) | `block_obligation exit-artifacts "$LEAN_PR_ERROR"` | `absent` ✅ |
| `lean-gate.sh:4852` (`cmd_close_out`) | `fail_milestone 5 "$LEAN_PR_ERROR"` | **`attempt`** ❌ |

Both close-out reason strings classify into two of the six reasons AC-3 names. Verified by
running the **production** predicate table against the literal strings, not by reading:

```
close-out reason #1 (progress-current text) CLASSIFIES AS: m5/progress-current
close-out reason #2 (no-PR text)            CLASSIFIES AS: m5/exit-artifacts:no-open-pr
```

Chain closed: `gate-ablation.awk:151-154` matches predicates against the **reason field**
(`classify(ms, reason)`), and `:122` makes an unclassified reason a hard error — so these
firings certainly land in those classes. `fail_milestone` (class 1, not INFRA) calls
`append_attempt` → `| milestone-5 | attempt | <reason>`, which `attempt_count()` sees.

This is the exact half-application the ticket diagnoses for `m1/spec-absent` ("18 of 54
firings under `absent`, 36 under the older `attempt` verb"). The operator's own 2026-08-23
issue comment shows this firing as `(attempt 1/3)` — the charging verb — on close-out.

**Why the new completeness guard does not catch it.** `(ac1b)` counts
`block_milestone [145] "[a-z]|block_obligation [a-z-]+ "` and asserts `== 8`. It guards the
*inclusion* direction only. A `fail_milestone 5` site carrying one of the six predicates
leaves the count at 8 and passes. The guard needs the exclusion direction too: no
`fail_milestone` site's reason may match one of the six reasons' predicates.

Fix: route both close-out sites through `block_milestone`/`block_obligation`, and extend
`(ac1b)` with the exclusion assertion.

### B2 — AC-3's fixture-per-reason is unsatisfied for `m5/identity-stamp`

AC-3 requires the routing be *"driven by a fixture case per reason; a case asserts no
fix-budget charge."* Five of six reasons have behavioral cases — `(c3)`, `(c2b)`, `(k5b)`,
`(k9)`, `(k3b)`. `m5/identity-stamp` has none:

```
grep -rn 'could not stamp' plugins/dev-pipeline/skills/build-lean/*selftest*.sh   → no hits
```

Its only coverage is the static `(ac1b)` site count, which greps call sites textually and can
never observe that a failed identity stamp records `absent` and charges zero attempts. The
routing itself is correct (`:4616`, `:4647`), so this is a coverage gap, not a behavior defect.

Fix: a milestone-5 fixture forcing `cmd_mark` to fail, asserting `| milestone-5 | absent |` ≥ 1
and `| milestone-5 | attempt |` == 0, in the shape of `(k3b)`/`(k9)`.

## Warnings

**W1 — the re-cut corpus shares ZERO records with the corpus it replaces, and drops both dated
incidents the kept-blocking rationale cites.** Base manifest: 52 records (345–539). Head: 70
records (72–650). `comm` overlap is **0** — the two interleave across the same span (base has
345/346/347, head has 344/348/351) yet coincide nowhere. Consequence: `m4/patch-stale`
(2026-08-03, record `345`) and `m4/chain-break` (2026-08-04, record `375`) go from 1 firing to
**zero**, so under the corpus this PR ships they are *never-fired* points — and they are exactly
the two the issue's "Explicitly out of scope" keeps blocking *because* they carry those
incidents. AC-2 is nonetheless **satisfied**: its register is `gate-ablation-classes.tsv`'s
`earn_your_keep` (verified populated for all 31 declared points) plus the `docs/testing.md`
table, and both points carry substantive reasons in the tsv. The report also honestly dates its
two eras. What is off is the count: `docs/testing.md` states "**Kept (18)**" as current fact,
while the shipped corpus yields **20** never-fired points, and two of that table's 18 entries
(`m1/ledger-lint`, `m1/preflight-reconcile`) fired 4 and 2 times — so they are not never-fired
at all. Actual testing.md coverage of never-fired points is 16/20. Worth dating the table the
way the report dates its findings.

**W2 — "74 records pinned" is not reproducible from any delivered artifact.** The manifest
carries **70** non-comment rows; the generated table says `scored records | 70`; the header
names **1** excluded in-flight lane (`642`). The figure "74" appears in the report's prose note,
the commit body and the PR body. Relatedly, the operator's 2026-08-24 amendment clause (c)
ratifies "18/18", which has the same provenance as W1's count.

**W3 — three-reviewer coverage gap.** `maintainability`, `test-coverage` and
`unit-test-mutation` all went dark (turn-budget, died after retry). `test-coverage` is precisely
the domain of B2, which was instead caught by `scope-completeness` and confirmed by hand.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Both points gone as code; residual mentions are deletion-documenting comments plus `(u4)` asserting absence. Deleted rows were in `gate-ablation-classes.tsv:43-44` at base (predicate rows — which is why the literal id never appeared in the gate). Sweep green: see AC-5 citation. |
| AC-2 | satisfied | Register = `earn_your_keep` (all **31** declared points populated; zero empty) + `docs/testing.md` table. Deletions argued in the commit body. See W1 on the count. |
| **AC-3** | **unsatisfied** | **B1** (routing half-applied on `close-out`) and **B2** (no fixture for `m5/identity-stamp`). The other five reasons route and are driven correctly. |
| AC-4 | satisfied | `case "$key"`: `typecheck` → `fail_milestone` with class; `*` (= `lint`\|`test`, the loop is over `lint typecheck test`) → `lane_advisory`; extraLanes → `lane_advisory` (`:3945`). Non-vacuity is real: `(ad3)` typecheck still refuses and charges; `(ad5)` `no-verify-lane` still refuses; `(ad4)` the demoted lane still executes. |
| AC-5 | satisfied (by citation) | CI's own run at the reviewed head `642a6b13`, per the operator's verification-economy instruction — not re-executed locally. `lint-and-selftests` **pass** 4m33s (job 97496045108); `selftests (macos, bash 3.2)` **pass** 7m8s (job 97496044422); `mutation-sweep-pr` **pass** (job 97496044809). `pr-gates` fails at 8s on the absent verdict record — expected pre-handoff, not a finding. |
| AC-6 | satisfied vs the amended bar | Independently re-measured: `lean-gate.sh` 5518→5232 (**−286**), selftest 7043→7230 (**+187**), combined −99 on 12,561 = **−0.79%** (matches the −0.8% claimed). `check-guard-budget.sh origin/main` → **−31**, matching clause (b) exactly. Clause (d) −293 comment lines verified exactly (2782→2489). Clause (a) verified. Clause (c)'s "18/18" — see W1. |
| AC-7 | satisfied | 2 `Changelog:` trailers on the branch. |
| AC-8 | satisfied | `:4553` appends MERGED after OPEN and takes `.[0:1]` — open wins when both exist, closed-unmerged matches nothing. Driven by `(k7)` merged passes, `(k8)` closed-unmerged satisfies nothing, `(k10)` open wins over merged. |
| AC-9 | satisfied | Corpus re-cut, report regenerated, `SKILL.md` / `docs/testing.md` / `docs/pipeline-manifesto.md` updated. See W1 and W2. |

Design: `Design: none` — no `## Design` section in the spec, so step 5b did not run.
Fidelity scored `not-applicable`.

## Ledger provenance

Checked against the operator's attestation that nothing was communicated to the build session.
`D-5` (`user-answered`) cites the 2026-08-22 ratification present in the **original** issue body
— attested. `D-2` (`ticket-sourced`) cites the dated 2026-08-23 comment — attested. `D-1` and
`D-6` are `codebase-derived` and claim no operator provenance. **No unattested operator-provenance
row.** The issue body's AC-6 amendment was authored by `manoldonev` at 2026-08-24T15:57:35Z —
**after** the build handed off (PR marker 15:51:20; session time-fenced 14:07–15:50), verified via
`userContentEdits.editor.login`. So it is not a spec amended by the build to match its own diff:
the build recorded AC-6 as unmet, declined to chase it, and left the call to the operator; the
operator then made that call. That is the sanctioned #641 shape, and it is why AC-6 is scored
against the amended bar.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Fail | 1 blocker (B2) — independently confirmed |
| Security | Pass | 0 |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Dark (no output) | — |
| Test Coverage | Dark (no output) | — |
| Unit Test Mutation | Dark (no output) | — |

a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`).

B1 was found by hand-derivation, not by the panel — the four reviewers that returned produced
zero code findings between them.
