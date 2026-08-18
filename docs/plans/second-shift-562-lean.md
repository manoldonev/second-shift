# #562 — the lean lane never lints the committed ledger

Issue: [#562](https://github.com/manoldonev/second-shift/issues/562). Spin-out of #268's T6
datapoint, filed as a precondition of parking that epic.

## The gap

`ledger-lint.sh` (intake-toolkit) exists only in plan-time surfaces — the plan-interview tool and
the `exitplan-ledger-gate` hook. `lean-gate.sh` never invoked it, so an invented provenance value
in a committed lean spec's `## Decision Ledger` passed every lean gate — and did, reaching a
committed artifact on an open PR (the T6 datapoint, `issue-specified` at
`docs/plans/second-shift-83-lean.md:20-26`, five rows deep, outside the closed enum
`user-answered | user-delegated | codebase-derived | deferred | ticket-sourced`).

## Acceptance criteria

- **AC-1**: `lean-gate.sh` milestone 1 refuses a committed spec whose `## Decision Ledger` rows
  carry a provenance value outside the interviewing-baseline enum, reusing `ledger-lint.sh` — not
  a re-implementation.
- **AC-2**: a selftest case exercises the refusal with an invented-provenance fixture and the pass
  with a valid one.
- **AC-3**: distinct from #517 (row carry-forward): this guards provenance *validity*, #517 guards
  row *presence*. A spec with no `## Decision Ledger` section at all is unaffected by this ticket.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Which seam: milestone 1 or `lean-evidence.sh` | Milestone 1 (`cmd_1`). It already reads the committed spec's content directly (the `AC-n` count, the `## Design` section), so a Decision Ledger check is the same class of read at the same call site. `lean-evidence.sh:824`'s own comment says the provenance enum is "single-sited in `ledger-lint.sh`, and a second copy here would be duplicate machinery" — about `arm_intent_gap`'s disposition check specifically, but the same reasoning argues against adding a *second* enum-aware reader at the merge boundary when milestone 1 can be the only one. | codebase-derived |
| D-2 | Conditional on the section existing | The check only runs when the spec already carries a `## Decision Ledger` header (same detector `ledger-lint.sh` itself uses for its own "missing mandated section" violation). A spec with no ledger section is unaffected — AC-3 scopes row-*presence* to #517, not this ticket. | codebase-derived |
| D-3 | Lint mode: default vs `--receipt` | Default (4-column: ID / Decision / Resolution / Provenance). The 5-column receipt shape (with a `Kind` cell) lives only in `.claude/pipeline-state/*-ledger.md`, which `.gitignore` excludes from every commit — a committed lean spec's ledger is never receipt-shaped in this tree (confirmed: no `docs/plans/*.md` carries a `Kind` column). | codebase-derived |
| D-4 | Cross-plugin resolution | **Superseded by round 1's Blocker 1** (see below) — was "re-derive `resolve_sibling`'s ladder at this file's own hop depth", which round 1 found byte-identical to the canonical copy and therefore anchorable, not legitimately divergent. Resolved instead: `resolve_sibling()` (`pipeline-doctor.sh`, #419) is extracted into a new sourced lib, `plugins/dev-pipeline/tools/resolve-sibling.sh`. Each caller keeps computing its OWN `PLUGIN_DIR`/`PLUGINS_DIR` at its own hop depth (`skills/build-lean` sits two directories under its plugin root, `tools` sits one — that part legitimately differs and stays caller-side; D-8 is what made that true of the whole ladder rather than of two rungs of three) and sources the lib for the ladder itself, so there is exactly one implementation with two callers rather than two implementations. `lean-gate.sh` already sets this precedent for `branch-prefix.sh`. No env-override knob: nothing else branches on an intake-toolkit root, so one would be machinery with no consumer, unlike the `SEAM_SCRUB`-denylisted `*_ROOT` variables. | codebase-derived |
| D-5 | Unresolvable `ledger-lint.sh` | Fails closed: `envfail` (rc=2, infrastructure, no fix-budget charge) — the same posture `claim` already takes when its own `claim-issue.sh` helper is missing (`lean-gate.sh:2418`). `exitplan-ledger-gate.sh`'s hook-side fail-open ("allowing (fix the install)") is a different posture for a different consumer: that hook must never block an unrelated tool call on a broken install, but a lean milestone gate never silently passes an unevaluated check — `design_state`'s `error:*` handling is the same-file precedent. | codebase-derived |
| D-6 | Round 1's Blocker 2 (cache-rung coverage) | **Amended by round 2's Blocker 1 — the "no new fixture needed" half was wrong** (see D-8). Was: discharged by inheritance from D-4's extraction, since `resolve_ledger_lint()` now calls the same `resolve_sibling()` `pipeline-doctor-selftest.sh`'s `(rs)` case already drove against a fabricated two-version cache straddling 10. What survives: the marker-lift-and-execute target is correctly re-pointed at `resolve-sibling.sh` rather than `pipeline-doctor.sh` post-extraction, and the version-ordering rung (rung 3) is genuinely covered. What did not: that case injected `SCRIPT_DIR`/`PLUGINS_DIR` as environment, so it exercised the ladder and neither caller's hop arithmetic — see D-8. | codebase-derived |
| D-7 | Round 1's Blocker 3 (section-detector drift) | Not reused — `lean-gate.sh:2962`'s detector decides whether to *run* the lint, `ledger-lint.sh:121`'s decides whether it *found* a section; collapsing them would mean the gate re-shells out to the lint just to decide whether to shell out to the lint. Instead pinned by coverage: (a8) commits a bold-heading (`**Decision Ledger**`) ledger with an invented provenance and asserts the refusal, closing the gap a mutant narrowing the detector to only the `#{1,6}` branch would previously have survived. | codebase-derived |
| D-8 | Round 2's Blocker 1 (rung 2 depth-coupled, and five claims of a parity that did not hold) | Took the review's option 1 (fix the line), not option 2 (correct the claims): `resolve_sibling()` derives this plugin's version from the caller-supplied `PLUGIN_DIR` (`basename`) instead of re-doing hop arithmetic on the caller's `SCRIPT_DIR`, so all three rungs are depth-agnostic and the parity D-4 asserts becomes true rather than needing to be walked back. `pipeline-doctor.sh:20` already supplied `PLUGIN_DIR`; `resolve_ledger_lint()` now computes it alongside the `PLUGINS_DIR` it already computed. Option 2 was rejected on cost, as the review said it would be: it would have had to amend this spec, three code comments, the selftest comment AND the lockstep entry's "the RUNG ORDER is the contract" language, to record a ladder that is shared for two rungs of three. Coverage for the rung is the other half — see the Tests section. | codebase-derived |

## Tests

`lean-gate-selftest.sh`, new cases (a4)-(a8) alongside the existing milestone-1 block (a1)-(a3):

- (a4) AC-1/AC-2: a Decision Ledger row with an invented provenance value (`issue-specified`)
  refuses milestone 1, naming the ledger-lint violation.
- (a5) AC-2: a Decision Ledger with only enum-legal provenance values passes.
- (a6) AC-3: a spec with no `## Decision Ledger` section at all is unaffected — the discriminator
  against #517's scope.
- (a7) the explicit empty form (`No material decisions — all choices codebase-derived.`) is itself
  a clean pass.
- (a8) D-7 (round 1 Blocker 3): the same invented-provenance refusal as (a4), under a
  `**Decision Ledger**` bold heading instead of `## Decision Ledger`.

Placed after (a3)/(b1)/(b2) rather than between them: (b1)/(b2) assert cumulative counters against
the progress file (a1)-(a3) leave behind, and inserting a `reset_progress` there would silently
zero that history instead of exercising it.

`pipeline-doctor-selftest.sh`, where the old single `(rs)` case became four (D-6/D-8). It is still
the sole guard on the cache rungs — every in-repo suite runs the real scripts at their real
monorepo paths, where rung 1 short-circuits and rungs 2 and 3 are dead code, so only a fabricated
cache can tell them apart:

- (rs1-gate) / (rs1-doctor) — rung 2: a version-matched sibling must beat a newer one. **New**, and
  the killer this rung has never had at any depth. Reverting D-8's one-line fix reds `(rs1-gate)`
  alone and leaves `(rs1-doctor)` green — the exact asymmetry round 2 found.
- (rs3-gate) / (rs3-doctor) — rung 3: with no version-matched sibling, the highest version wins,
  not the lexically-last (`9.0.0` vs `10.0.0`). This is the old `(rs)`, now run at both depths.

Both are driven through **stubs written at each caller's real path inside the staged cache**, built
from the real function and each caller's real prep lines lifted by sentinel (`# >>> resolve-sibling`,
`# >>> ledger-lint-resolver`, `# >>> plugin-dirs`). Round 2's finding is why: the old case injected
`SCRIPT_DIR`/`PLUGINS_DIR` as environment, which exercises the ladder and no caller's hop
arithmetic — so a wrong hop count in either caller was unguarded. It is guarded now, and probed
both ways: mutating `resolve_ledger_lint()`'s `dirname` count reds the two `-gate` cases only, and
mutating `pipeline-doctor.sh`'s reds the two `-doctor` cases only.

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`

Load-bearing suite: `lean-gate-selftest.sh`.

## Design

Design: none — a shell-script gate change with no UI surface; `design.provider` is unset in this
repo's config.
