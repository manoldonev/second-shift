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
| D-4 | Cross-plugin resolution | A new `resolve_ledger_lint()` in `lean-gate.sh`, re-deriving (not copying) `check-model-tiers.sh`'s `resolve_sibling_plugin_root` two-rung ladder (monorepo path, then newest cache sibling) for this file's own hop depth (`skills/build-lean` sits three levels under its plugin root, `scripts` sits one) — the divergence `lockstep-manifest.tsv`'s `cross-plugin-sibling-plugin-root` entry already calls legitimate when hop counts differ. No env-override knob: nothing else branches on an intake-toolkit root, so one would be machinery with no consumer, unlike the `SEAM_SCRUB`-denylisted `*_ROOT` variables. | codebase-derived |
| D-5 | Unresolvable `ledger-lint.sh` | Fails closed: `envfail` (rc=2, infrastructure, no fix-budget charge) — the same posture `claim` already takes when its own `claim-issue.sh` helper is missing (`lean-gate.sh:2418`). `exitplan-ledger-gate.sh`'s hook-side fail-open ("allowing (fix the install)") is a different posture for a different consumer: that hook must never block an unrelated tool call on a broken install, but a lean milestone gate never silently passes an unevaluated check — `design_state`'s `error:*` handling is the same-file precedent. | codebase-derived |

## Tests

`lean-gate-selftest.sh`, new cases (a4)-(a7) alongside the existing milestone-1 block (a1)-(a3):

- (a4) AC-1/AC-2: a Decision Ledger row with an invented provenance value (`issue-specified`)
  refuses milestone 1, naming the ledger-lint violation.
- (a5) AC-2: a Decision Ledger with only enum-legal provenance values passes.
- (a6) AC-3: a spec with no `## Decision Ledger` section at all is unaffected — the discriminator
  against #517's scope.
- (a7) the explicit empty form (`No material decisions — all choices codebase-derived.`) is itself
  a clean pass.

Placed after (a3)/(b1)/(b2) rather than between them: (b1)/(b2) assert cumulative counters against
the progress file (a1)-(a3) leave behind, and inserting a `reset_progress` there would silently
zero that history instead of exercising it.

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`

Load-bearing suite: `lean-gate-selftest.sh`.

## Design

Design: none — a shell-script gate change with no UI surface; `design.provider` is unset in this
repo's config.
