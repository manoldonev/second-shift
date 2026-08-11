# 397 — the thin orchestrator: `run-lean` becomes the lane's front door, the build payload moves to `build-lean`

Issue: #397 · lane: run-lean · pre-flight ledger: `.claude/pipeline-state/397-ledger.md` (binding)

`/dev-pipeline:run-lean` — the name users type — becomes a thin orchestrator that automates the
block flow. The build-session checklist survives intact under a sibling name, `build-lean`,
mirroring `review-lean`. Every block stays individually invokable; the two-terminal manual flow
remains first-class.

The rename and the orchestrator ship in **one PR** (ledger D-10): the orchestrator claims the name
the payload vacates, and either half alone leaves `/dev-pipeline:run-lean` broken or double-claimed
for the duration.

## Binding inputs from the pre-flight receipt

D-1 (script, not prose loop, with an env-overridable spawn seam), D-2 (missing intake is a
reject-and-stop, **not** a spawned intake session — this overrides the issue body), D-3 (velocity
principles land as a doc section + this PR's own review criteria + a *measured* profiling pass
recorded in the PR body; no blind parallelization refactor), D-4/D-5 (BUILD's model comes from the
ticket's `opus`/`sonnet` label, placed at intake exit; absent ⇒ the driving skill sizes and says so
in the run log), D-6/D-7 (a spawned session gets a fresh session id and a live ledger; `RUN_ID` and
`LEAN_RUN_MODEL` inherit and are scrubbed), D-8 (three rounds, the fourth is a hard stop),
D-9 (the rename's real blast radius), D-11 (the skill directory *is* the command name).

Open regions OR-1 (config-resolved tiers, owned by #351), OR-2 (profiling volume) and OR-3 (spawn-seam
fidelity is unprovable in a model-free CI) each take their stated default and are surfaced, not paused on.

## Acceptance criteria

### The rename

- **AC-1** — `plugins/dev-pipeline/skills/build-lean/` holds the whole build payload, moved with
  history: `SKILL.md` (frontmatter `name: build-lean`), `lean-gate.sh`, `lean-gate-selftest.sh`,
  `lean-evidence.sh`, `lean-evidence-selftest.sh`, `lean-reconcile.sh`, `lean-reconcile-selftest.sh`,
  `branch-prefix.sh`, `branch-prefix-selftest.sh`. None of those nine files exists under
  `skills/run-lean/` afterwards.

- **AC-2** — Behavior is unchanged by the move: the repo's `test` command
  (`bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`) is green, and no
  moved file's body changes except where a path or the skill's own name is being corrected.

- **AC-3** — Every **live** reference to the old location or to `run-lean`-as-the-build-payload is
  updated to `build-lean`, across: `README.md`, `docs/{onboarding,team-rollout,config-schema,live-render,testing}.md`,
  `schema/second-shift.config.schema.json`, `plugins/dev-pipeline/.claude-plugin/plugin.json`,
  `plugins/dev-pipeline/skills/review-lean/SKILL.md`, `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md`,
  `plugins/dev-pipeline/skills/run/{SKILL.md,pipeline-cost-block.sh,scenario-liveness-selftest.sh}`,
  `plugins/dev-pipeline/skills/run/tools/{check-bounded-exploration.sh,check-bounded-exploration-selftest.sh,cost-block-selftest.sh,retro-corpus.sh}`,
  `plugins/dev-pipeline/skills/run/tools/tracker/{README.md,jira/README.md}`,
  `plugins/dev-pipeline/skills/run/workflows/design-sync-selftest.mjs`,
  `plugins/second-shift/skills/onboard/SKILL.md`,
  `plugins/second-shift/templates/consumer/{SECOND-SHIFT.md,second-shift-ci-check.sh,second-shift-ci-check-selftest.sh}`,
  `scripts/{check-lean-chain.sh,check-lean-chain-selftest.sh,check-pipeline-chain.sh,check-pipeline-chain-selftest.sh}`,
  and `tools/capability-parity.tsv`. `CHANGELOG.md`, `docs/plans/` and `.claude/pipeline-state/` are
  historical and stay untouched.

- **AC-4** — The four path-anchored TSVs are re-keyed, not re-derived: `tools/mutation-baseline.tsv`
  (the 12 `skills/run-lean/…` rows, ordinals unchanged — the rename changes no guard content),
  `tools/mutation-catalog.tsv` (9 rows), `scripts/lockstep-manifest.tsv` (9 rows) and
  `.claude/prose-budget.baseline.tsv` (the `run-lean/SKILL.md` row, plus a new row for the
  orchestrator's own `SKILL.md`). `bash scripts/check-lockstep-pairs.sh` and
  `tools/mutation-sweep.sh --mode pr` run clean on the branch.

- **AC-5** — The consumer CI template's `lean-evidence` fetch path moves with the payload, and the
  break it creates for a consumer whose pin predates this release is stated as a `Migration:` line on
  the `Changelog:` trailer — the template fetches `?ref=$LOCK_REF`, so taking the new template without
  moving the pin 404s and reds their gate by design.

### The orchestrator

- **AC-6** — `plugins/dev-pipeline/skills/run-lean/` contains exactly `SKILL.md`
  (frontmatter `name: run-lean`), `orchestrate-lean.sh` and `orchestrate-lean-selftest.sh`.
  `SKILL.md` is ≤ 60 lines including frontmatter, matching the payload skill's own cap.

- **AC-7** — `orchestrate-lean.sh <issue>` drives the block flow end to end with **zero operator
  latency between phases**: preflight → BUILD session → resolve the PR from the tracker → REVIEW
  session → read the verdict gate's exit code → terminal, or the next round. It reads gate exit
  codes and tracker state only; it parses no artifact content and interprets no findings.

- **AC-8** — Preflight is a **reject-and-stop**, never a spawn: with the queue label absent (github)
  and no `--intake-attested`, the script exits 2 having invoked the spawn binary zero times. The
  ticket's "spawn an INTAKE session" is deliberately not implemented (ledger D-2).

- **AC-9** — Preflight's independent probes run **concurrently**, and one invocation reports **every**
  failing probe rather than aborting on the first. Asserted by a case in which two probes fail and
  both appear in a single run's output.

- **AC-10** — Every spawn is a fresh top-level session: the recorded argv carries `-p` and
  `--model <m>` and carries **no** `--resume`, `--continue` or `-c`. Asserted over a `needs-work`
  round, where the review spawn of round 2 must be a new context rather than round 1's resumed.

- **AC-11** — Every spawn scrubs `RUN_ID` from the child environment and sets `LEAN_RUN_MODEL` to
  that phase's model. Asserted from the environment the fake spawn records, for both a BUILD spawn
  and a REVIEW spawn, with a deliberately-poisoned `RUN_ID`/`LEAN_RUN_MODEL` in the parent.

- **AC-12** — BUILD's model is supplied by the caller (`--build-model`), REVIEW defaults to `opus`
  and is overridable (`--review-model`). The script resolves no label itself and sizes no ticket —
  that is the driving skill's job, per the contract that forbids the orchestrator content judgment.

- **AC-13** — The round budget is three, and the fourth is a hard stop: `orchestrate-lean.sh` exits
  **4** with no rescue attempt, both when the verdict gate itself returns 4 and when `--max-rounds`
  is reached with the gate still returning 1. Asserted for both routes.

- **AC-14** — The orchestrator makes **no tracker writes**: across a full approved run and a full
  hard-stop run, the recorded tracker-CLI invocations contain no mutating subcommand
  (`issue edit`, `issue comment`, `pr comment`, `pr edit`, `pr merge`, `api --method`/`-X` with a
  non-GET verb). Asserted against a recording fake.

- **AC-15** — The identity refusals hold under orchestration, asserted rather than assumed: the
  orchestrator passes no session id to any spawn and sets none in the child environment, so the
  build-vs-review separation `lean-gate.sh verdict` enforces rests on the harness's per-session
  stamp (ledger D-6) and not on the orchestrator's cooperation.

- **AC-16** — Every seam the selftest drives is an env override with a shipped default that points
  at the real thing: `LEAN_SPAWN_BIN` (`claude`), `LEAN_GATE` (the sibling `build-lean/lean-gate.sh`),
  `GH` (`gh`). No selftest-only branch exists in the production path.

- **AC-17** — `orchestrate-lean.sh` is exercised by `orchestrate-lean-selftest.sh` in the same
  directory, so it pairs by the directory-scoped same-stem rule. No row is added to
  `tools/mutation-exclusions.tsv` or `tools/mutation-pair-map.tsv`.

### The velocity principles

- **AC-18** — The three velocity principles land as a doc section in
  [`docs/pipeline-manifesto.md`](../pipeline-manifesto.md), stated as binding on the orchestrator and
  every building block, and framed the way that document already frames P1–P10: a judgment aid and a
  review criterion, not a gate (P5 forbids the prose-presence lint that would police them).

- **AC-19** — A **measured** profiling pass over the existing lane gates is recorded in the PR body:
  for each concrete serial-execution-of-independent-steps finding, the site and its measurement. If
  the volume is near zero, that is the recorded result (OR-2's stated risk), not a gap. No gate is
  refactored in this PR.

### The intake half

- **AC-20** — `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` states that intake places
  an `opus` or `sonnet` sizing label alongside the queue label at exit, and its issue-creation
  commands carry it. `run-lean/SKILL.md` states the fallback: an unlabeled ticket is sized by the
  driving skill, which passes its pick and prints a one-line justification in the run log — which is
  what makes a missing label loud rather than silent (ledger D-5).

### Docs

- **AC-21** — Doc updates are AC-scoped and complete: no live doc, skill or schema description
  describes `run-lean` as the build payload after this change, and each of `README.md`,
  `docs/onboarding.md`, `docs/team-rollout.md` and the consumer `SECOND-SHIFT.md` names the split
  (`run-lean` = the front door that drives the flow; `build-lean` / `review-lean` = the payload
  blocks, still individually invokable).

## Out of scope

- Parallelizing `lean-gate.sh` / `lean-evidence.sh` (ledger D-3: findings recorded, tickets filed by
  the operator, no refactor here).
- Config-resolved model tiers — #351 owns replacing the literal model name (OR-1).
- Deleting the staged lane — #348 owns it; this PR only makes the recycled name available.
- An operator-run end-to-end proving a real `claude -p` build session completes unattended (OR-3):
  CI is model-free by design, so the suite proves control flow, not spawn fidelity.
