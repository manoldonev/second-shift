# #527 — a killed evaluation is distinguishable from an idle session

An infrastructure death of the milestone-3 sweep is today indistinguishable from a broken branch
(topology **T-B**: the sweep dies under a surviving runner and is charged a fix attempt) and
invisible to the scheduler (topology **T-A**: the runner dies at turn end, `m3_wait` returns 7, and
the run's progress token is byte-identical to an idle session's — so `orchestrate-lean.sh` stops
with both continuations unspent).

Binding input: `.claude/pipeline-state/527-ledger.md` (D-1 … D-13, OR-1, OR-2). D-12 re-anchors
every line citation in the ticket; the numbers below are re-measured against this branch's base.

## Acceptance criteria

### AC-1 — the sweep names its own infrastructure class

`tools/run-selftests.sh` reserves exit code **3** for "every failing suite failed for
infrastructure reasons". The per-suite classification already exists (`rc=125`, the
no-verdict-written class, `:501`/`:510`); only the parent collapses it at `:546-552`.

- Failing suites, **all** of them `rc=125` ⇒ exit **3**.
- Failing suites, **any** of them a real suite failure ⇒ exit **1**, unchanged.
- No failing suites ⇒ exit **0**, unchanged. Count reconciliation ⇒ exit **2**, unchanged.
- The `summary:` line reports the infra/real split so the class is readable in a log, not only
  in an exit code.

`3` per D-2: `0`/`1`/`2` are taken, and the `125`-`127` band is the shell's own
"could not execute" range, which a consumer lane can hit by accident once the code is reserved
cross-repo.

### AC-2 — milestone 3 honors the reserved code, uniformly

`lean-gate.sh` `cmd_3` treats a verify lane exiting **3** as infrastructure, and reds the milestone
with **rc=7** rather than 1. Applied uniformly (D-1) to:

- the fixed `lint` / `typecheck` / `test` keys (`:3201-3208`) — which is the path the repo-carried
  sweep takes; it has no separate call site;
- `extraLanes` (`:3284-3289`).

Setup `lanes[]` are out of scope: they are already INFRA-classed and are not verify lanes.

`7` per D-3: its documented meaning is already "NOTHING WAS EVALUATED … THE EVALUATION DID NOT
COMPLETE", with the same remedy (re-invoke), so no new operator path appears in `build-lean/SKILL.md`.

### AC-3 — an infra-classed red charges no fix attempt

`fail_milestone` honors the class it is already passed (`:1149`) **before** the `append_attempt`
at `:1156`:

- an infra-classed red appends no `| milestone-N | attempt |` row, spends no fix budget, and warns
  in terms that say nothing was evaluated;
- observe mode (`LEAN_GATE_OBSERVE=1`) reports the same class and, as before, records nothing;
- every non-infra class is byte-unchanged, including budget exhaustion outranking the class.

Budget exhaustion needs no carve-out (D-8): `count > FIX_BUDGET` cannot fire on a call that
appended nothing.

### AC-4 — the interrupted budget is per-milestone

Without this the fix is self-defeating: it stops charging fix attempts and re-spawns, and the run
then hard-stops at `rc=4` on unclosed `started` rows instead — `unclosed_count` never decrements.

- Milestone 3 carries its own budget of **8**, above the 6 spawns a scheduler can generate at
  `--max-rounds 3` × `--max-continuations 2`.
- Milestones 1/2/4/5 keep `INTERRUPTED_BUDGET=5` and its existing sizing rationale unchanged.
- The announce line and the refusal line each report the milestone's own budget.

Per-row classing was rejected (D-7): the residue describes only the latest runner, so a historical
unclosed row carries no class. The gate-side bound is retained because a hand-run
`bash G 3 <issue>` has no `--max-continuations` at all.

### AC-5 — the scheduler-readable infra token

`lean-gate.sh progress <issue> --infra` prints `m3infra-v1:<n>`, derived from residue because
under T-A nothing survives to write a class (SIGKILL cannot be trapped).

- `n` = `unclosed_count 3` less the number of globbed `<issue>-lean-m3-*.pid` records naming a
  **live** pid, floored at 0. Under the shipped one-worktree-per-issue topology that is exactly
  D-5's "less 1"; with more than one live record it is OR-1's fail-closed generalization — any
  live runner subtracts, so an honest in-flight evaluation is never reported as a death.
- Never empty: "no infra death" is `m3infra-v1:0`. `orchestrate-lean.sh:497` rejects an empty
  token.
- The record is located by **glob** (D-4), not by computing `m3_paths`' key: that key hashes
  `REPO_ROOT`, which is cwd-derived, so a gate run from `$MAIN_ROOT` — which is where the
  scheduler runs it — cannot name the build worktree's record.
- A stderr diagnostic names how many runner records were found and how many were live (OR-1).
- Read-only, in the strict sense `progress` and `staleness` already carry: it writes nothing and
  does not call `ensure_progress_file`.
- `--infra` and `--satisfied` are mutually exclusive; `--infra` on any other subcommand is a usage
  error, validated at parse time beside `--satisfied`'s existing guard.

Not a new progress ROW kind (D-6): `progress_token`'s row set was closed deliberately, because
counting `started`/`concluded` makes every dead spawn read as advancement. Not a new subcommand:
`orchestrate-lean.sh:495` already forwards `"$@"`.

### AC-6 — the scheduler routes on the delta

`orchestrate-lean.sh` reads the infra token on **both sides** of a BUILD spawn, in the
`tok_before`/`tok_after` shape already at `:532`/`:547`, and routes on the **difference**:

- progress unmoved **and** infra unmoved ⇒ the existing `exit 1` ("nothing to review"), unchanged;
- progress unmoved **and** infra moved ⇒ fall through to the existing continuation path —
  `continuations` is incremented and `--max-continuations` bounds it (D-9), with a line naming
  the infrastructure death as the reason;
- an infra read that cannot be completed is fail-closed, exactly like its `progress` sibling: the
  run stops rather than spawning against a predicate nothing answered.

Never the LEVEL (D-10): the record is append-only, so one infra death leaves a level test true for
the rest of the run and every later idle session would read as recoverable — a fresh instance of
the bug being removed.

### AC-7 — the reserved code is documented where a consumer reads it

- `lean-gate.sh`'s header documents exit code 3 as a verify-lane input beside the 0/1/2/4/5/6/7
  taxonomy it already carries.
- `docs/config-schema.md` documents it as a `commands.<host>` lane contract, naming OR-2's
  exposure: a consumer lane that already exits 3 for a genuine failure is reclassified as
  infrastructure and charged no fix attempt. No config opt-out ships here; the failure direction
  is a run that retries when it should have stopped, bounded by `--max-continuations` and by
  AC-4's budget, never a red branch reported green.

### AC-8 — the guards

Per D-11 and the tier map in `CLAUDE.md`:

- `lean-gate-selftest.sh` — AC-2, AC-3, AC-4 and AC-5. Gate behavior does **not** go at the
  orchestrator boundary, where `fake-gate.sh` stands in and a case would assert the fake.
- `orchestrate-lean-selftest.sh` — AC-6. Case **j2** ("spawn exits 0, progress unmoved ⇒ exit 1")
  keeps its meaning and stays green because its infra stream is unmoved too; its anti-vacuity
  partner **j3** is re-derived to assert both predicates were read on both sides of the spawn, so
  the flipped routing cannot pass with the feature absent. A new case drives infra-moved and
  asserts the continuation.
- `tools/run-selftests-selftest.sh` — AC-1, in all three polarities (all-infra, mixed, clean).
- Editing `fail_milestone`, `run_milestone` and `run-selftests.sh` re-keys their generic survivor
  ordinals: `tools/mutation-baseline.tsv` is re-baselined in this same diff, and any
  `tools/mutation-catalog.tsv` row addressing those functions is re-anchored (D-13).

## Out of scope

- A per-lane config declaration that `3` means a real failure (OR-2's opt-out). Additive, and can
  land later without moving anything shipped here.
- Keying the infra read on the worktree the claim records (OR-1's tightening). A local change to
  one resolver, cheap to reverse into.
- Charging T-B to anything: after AC-2/AC-3 it is charged to nothing, which is the point.
