I read the repo's own lane contract, the shipped precedent, the CI job layout, and measured the corpus before planning. Here is the plan of record.

## Environment facts that shape it (established, not assumed)

- **The `plugins/` tree is missing from this checkout.** All 374 working-tree changes are deletions of tracked files (`plugins/**`, `.claude-plugin/**`); nothing is modified or untracked. Four of the five in-scope files live there. `git restore .` was denied by the permission layer, so **restoring it is the first thing I need approval for** — the corpus cannot be enumerated, and `lean-gate.sh` cannot run, until it is back.
- **`origin` is `/Users/mdonev/github/second-shift`, a local path, and HEAD is detached.** Every tracker/PR-side step below (claim comment, ready PR, bot marker, closing comment, the separate review session, CI) is part of the plan of record but is **not executable in this sandbox**. I will produce every committed artifact and run every local gate; the GitHub-side steps I will name as blocked rather than fake.
- Config is present (`.claude/second-shift.config.json`): `tracker.branchPrefix: claude/second-shift-`, base `main` → branch `claude/second-shift-636`, spec at `docs/plans/second-shift-636-lean.md`.

---

# Plan of record

## Phase 0 — pick up the ticket (lane entry)

| # | Artifact | Where | Who |
| --- | --- | --- | --- |
| 0.1 | Restored working tree | `plugins/**`, `.claude-plugin/**` | me (`git restore .`, needs approval) |
| 0.2 | Run-id record + `lean-claimed` bot marker, label swap | `.claude/pipeline-state/636-run-id`, issue #636 | `bash G entry 636`, `bash G claim 636` after `export RUN_ID=…` — **blocked: no GitHub remote** |
| 0.3 | Lane worktree | `../second-shift-worktrees/…` on `claude/second-shift-636` from `main` | me |
| 0.4 | Progress file (gitignored, harness-written) | `.claude/pipeline-state/` | the gate |

## Phase 1 — the spec, before any code (milestone 1)

**Artifact 1: `docs/plans/second-shift-636-lean.md`.** Modelled on `second-shift-613-lean.md`. Must contain:

- Problem + the three-bucket-plus-`not-a-gate` table, restated as this slice's contract.
- **Deliverables** section naming each file below.
- **AC-1 … AC-10** as numbered criteria (the gate requires ≥1 `AC-n`; the ticket's ten carry over).
- **`## Decision Ledger`** — rows carried forward from `.claude/pipeline-state/636-ledger.md` if a pre-flight receipt exists (`ledger-carry-forward.sh`, never retyped), then my own build-time rows, at minimum:
  - D — **naming**: `scripts/check-gate-buckets.sh` / `scripts/gate-buckets.tsv` / `scripts/check-gate-buckets-selftest.sh`. Deliberately *not* `gate-classes`: `tools/gate-ablation-classes.tsv` already owns "classes" and means reason-strings-by-ERE, which the ticket explicitly says is not the key.
  - D — **key**: the register adopts `path::name` from `docs/prose-blocker-triage.tsv` unchanged (settled at intake). Keys repeat across rows; the path half is the file the anchor is checked against.
  - D — **OR-1 resolved to its default**: one row per `envfail` class, with AC-4's covered-count printing. Measured pressure for this default: ~59 `envfail` lines in `lean-gate.sh`, ~23 in `operator-override.sh`.
  - D — **OR-2 resolved to its default**: `unwired — <reason>` is legal indefinitely; the guard checks form only (AC-6).
  - D — **the non-vacuity arm** (see Phase 2.1): the guard declares its corpus as (file × refusal-primitive) pairs and reds when a declared pair enumerates **zero** sites. Without it, renaming `note_violation` empties the denominator and every arm passes green — the exact vacuity this slice exists to prevent, and my reading of AC-10's "non-vacuity case".
  - D — **AC-3 gap closed by measurement**: the ticket's primitive list omits `lean-evidence.sh`. Measured: it carries its own `envfail` (line 165) **and** `note_violation` (line 168) — the same two names `check-lean-chain.sh` uses, in a different file. Both are declared; both helper *definitions* self-exclude by name.
  - D — **AC-10 discharged conditionally, and stated**: this slice adds no refusal to the five files, so (a) no new `tools/gate-ablation-classes.tsv` reason row is due, (b) `scenario-liveness-selftest.sh` gains nothing because no verdict path changes. Each non-payment is recorded with its reason rather than silently skipped; if implementation does end up touching a refusal branch, the obligation is paid in the same PR.
  - D — **AC-7 reading**: the new step closes #610 D-9's pointer ("the parent's register owns the living coverage guard"). `tools/prose-blockers.sh check` stays unwired — its corpus is prose constructs, and widening the census is named out of scope.
- **`## Design`** → `Design: none — a CI shell guard and a TSV; no rendered surface.`
- **Out of scope**, including the named residual: the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates.

Gate: `bash G 1 636` must return `rc=0` before implementation.

## Phase 2 — implementation, in this order

**2.1 — `scripts/check-gate-buckets.sh`** (new; the enumerator *is* the denominator). Written before the register, because the register is generated from its `--list`.

- Header (this is AC-8's home) records: why the guard exists; the closed enum and what `not-a-gate` is for; **every self-exclusion by name** (each primitive's own `<name>() {` definition line, this script, its selftest, `docs/plans/`, `*.tsv`), following `check-fail-open-shapes.sh:69`; and the out-of-scope residual.
- **Corpus declaration** — the five files paired with their primitives:
  `lean-gate.sh` → `fail_milestone`, `envfail`, `ticket_refuse`, `fail_obligation`, `block_milestone`; `check-lean-chain.sh` → `note_violation`, `fail`; `lean-evidence.sh` → `envfail`, `note_violation`; `operator-override.sh` → `envfail`; `orchestrate-lean.sh` → `terminal` **with a non-zero first argument** (the `terminal … 0` success calls at `:764`/`:923`/`:982` are enumerated and dispositioned `not-a-gate`).
- `enumerate()` prints `relpath<TAB>lineno<TAB>text`, sorted — same shape as the precedent.
- `--list` prints the denominator and checks nothing; exit code = violation count (doctor convention); `-h` prints the header range.
- Legs: **(a)** enumerated site with no row → UNCLASSIFIED; **(b)** anchor absent from its file → ANCHOR DRIFT; **(c)** row covering zero live sites → outlived its site; **(d)** schema — closed enum, 5 fields, `not-a-gate` needs a stated *what-it-is-instead*; **(e)** AC-5 safety: `gates-llm`/`gates-signal`/`not-a-gate` MUST have an empty yield cell, and a yield cell naming an `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value forces `gates-process`; **(f)** AC-6 form: every `gates-process` yield is an enum value or `unwired — <reason>`; **(g)** the non-vacuity arm above.
- Per-row covered-site count printed on the clean path (AC-4).
- Anchors matched via `ENVIRON`-passed awk, never `awk -v` — the precedent's escape-swallowing lesson.

**2.2 — `scripts/gate-buckets.tsv`** (new; the register). Columns: `enforcer (path::name) <TAB> bucket <TAB> anchor <TAB> yield <TAB> why`, with the same header discipline as `fail-open-sites.tsv` (text anchors never line numbers; "the count is not the contract"). Rows generated from `--list` and dispositioned by hand: `m3/lint|typecheck|test|extra-lane|setup-lane|no-verify-lane` and `m2/frozen-files|changelog-trailer` → `gates-signal`; the verdict/identity/freshness/ratification/override arms → `gates-llm`; the attendance-premised ones → `gates-process` with `intake-unqueued` / `spec-open-region` where wired and `unwired — <reason>` elsewhere; `envfail` classes and the three `terminal … 0` calls → `not-a-gate` with the reason. A `gates-process` row whose consumer sits outside the lane cites **#631** rather than claiming the path works.

**2.3 — `scripts/check-gate-buckets-selftest.sh`** (new). Fixture-driven, one temp tree per case: the three AC-2 reds independently, the all-green arm, the AC-5 safety arm (a `gates-signal` row wired to a yield must red), the AC-6 form arm, the unknown-enum-value arm, and the non-vacuity arm (a corpus pair that enumerates zero sites reds).

**2.4 — `.github/workflows/ci.yml`**: one step in the **`lint-and-selftests`** job (line ~150, beside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`), with a comment saying why it is there and not in `pr-gates`. Note: `.github/workflows/**` has **no** server-side freeze on this repo (manifesto T0 probe result, HTTP 422) — the edit is procedurally controlled by operator review, and `check-frozen-files.sh` will surface it advisorily in the PR log.

**2.5 — `docs/pipeline-manifesto.md`** (`### Where a gate may yield…`, lines 126-139): add the `gates-signal` bullet and a pointer to `scripts/gate-buckets.tsv`. Per P5 it states the principle and does **not** restate the enforcement.

**2.6 — Obligation reconciliation** (AC-10), each either paid or recorded as not-due:
`scripts/fail-open-sites.tsv` rows for any enumerated shape my own guard introduces; `tools/mutation-catalog.tsv` row(s) naming the regression class the new selftest alone catches, plus `tools/mutation-baseline.tsv` reconciliation for survivors the PR-scoped sweep reports; `tools/gate-ablation-classes.tsv` and `scenario-liveness-selftest.sh` per the ledger rows above.

**Commits** through `bot-commit.sh`, carrying `Changelog:` (or `Changelog: none`) if `plugins/**` is touched, and **`Guard-mass:`** — mandatory, because a new `check-*.sh` plus a `*-selftest.sh` grows guard mass and `scripts/check-guard-budget.sh` reds without it. Verb: `feat:` (a new capability; `chore:` would silently downgrade the release).

## Phase 3 — milestones 2 and 3

`bash G 2 636`, then `bash G 3 636`. Locally, before that: shellcheck over all `.sh`, `jq empty` over all `.json`, `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`, plus a diff-scoped `tools/mutation-sweep.sh` so survivors are handled in-PR rather than at CI.

## Phase 4 — the PR

Cost block from `pipeline-cost-block.sh --stateless --issue 636`; a **ready** (non-draft) PR whose body carries the summary, the spec link, `Closes #636`, and the cost block; then `bash G mark 636` (the bot identity marker, at this step and not milestone 5). **Blocked here** — no GitHub remote.

## Phase 5 — review (milestone 4, authored outside this session)

**Artifact: `docs/plans/second-shift-636-lean-verdict.md`**, written by a separate `/dev-pipeline:review-lean <pr>` session with its own identity — never by me. `bash G 4 636` passes only on a committed `verdict=approve` whose `reviewed_patch_id` is this branch's current patch. Any `needs-work` → fix every blocker, push, request a **fresh** review context; each content push costs another round.

## Phase 6 — close-out and merge

`bash G close-out 636` (re-computes the published cost figure, writes the `cost-log.jsonl` row, replaces the PR block, posts the one closing comment referencing the verdict record, asserts milestone 5, tears down the worktree). CI must be green including `check-lean-chain.sh`'s evidence set. Merge; leave the `claimed` label to the unclaim workflow.

---

## Artifact inventory

| Artifact | New/edit | Producer |
| --- | --- | --- |
| `docs/plans/second-shift-636-lean.md` | new | me |
| `scripts/check-gate-buckets.sh` | new | me |
| `scripts/gate-buckets.tsv` | new | me |
| `scripts/check-gate-buckets-selftest.sh` | new | me |
| `.github/workflows/ci.yml` (one step) | edit | me |
| `docs/pipeline-manifesto.md` (bucket section) | edit | me |
| `scripts/fail-open-sites.tsv`, `tools/mutation-catalog.tsv`, `tools/mutation-baseline.tsv` | edit, if due | me |
| `tools/gate-ablation-classes.tsv`, `scenario-liveness-selftest.sh` | expected **not due**, recorded either way | me |
| `.claude/pipeline-state/636-*` (progress, run-id) | new, gitignored | the gate |
| `docs/plans/second-shift-636-lean-verdict.md` | new | a separate review session |
| `CHANGELOG.md`, `plugin.json` versions | **never touched** — release-derived | `derive-release.sh` |

## Open items I will flag rather than decide silently

1. **Restoring `plugins/`** is a hard prerequisite and needs your approval.
2. **Everything GitHub-side is blocked** in this sandbox; I will deliver committed artifacts and local gate results, and say plainly which lane steps did not run.
3. **AC-10 is conditional by construction** here — my reading (record each non-payment with its reason; "non-vacuity" lands as the guard's own zero-enumeration red) is written into the Decision Ledger so review can overturn it cheaply.
4. **AC-4's two halves** (one row per site / an anchor may cover several) are reconciled as: per-site is the default, multi-site anchors are legal where OR-1's default calls for them, and the printed covered-count is what keeps a loose anchor visible.

Stopping here — no implementation.
