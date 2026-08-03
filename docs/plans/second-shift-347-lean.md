# Re-key retros to the artifact schema; lean runs enter the retro corpus — #347

Child of the block-decomposition epic (#343). Predecessor: #345 (already merged — its
progress/verdict records are the live artifact-schema fixtures this change targets).
Lands before #348 (the stage-choreography deletion child) so retro tooling never breaks in
the interval between them.

## Problem

`pipeline-retro` and `perf-retro` consume only the stage-schema shape
(`.claude/pipeline-state/{issue}.json` with a top-level `stages` key). A lean run's only
artifact in that directory is `{issue}-lean-progress.md` — wrong extension and wrong shape —
so both the `has("stages")` filter and the `*.json` glob make it invisible at every
enumeration site (`perf-retro` Step 1, `stage-envelopes.sh`). Lean/block runs never enter the
retro corpus, and the deletion child (#348) would otherwise land with no era-aware reader in
place for the runs it leaves behind.

A later ratified comment on this issue adds one requirement: retro corpus rows must carry
model identity per run, so cross-model deltas are queryable, without minting a new per-run
artifact.

## Shape of the change

**New shared tool, `retro-corpus.sh`** (`plugins/dev-pipeline/skills/run/tools/`, alongside
`stage-envelopes.sh`/`stage-times.sh`). `corpus` mode enumerates the state dir for BOTH
schema eras side by side — the existing `has("stages")` JSON scan (era `stage`) plus a
structural scan for progress records (any file carrying a `verdict_record:` header key, era
`artifact` — detected by shape, not by the `-lean-` filename literal, so a future non-lean
implementation reusing the same receipt shape is covered without a second reader). Neither
scan errors when the other era's files are the only ones present, and a state dir with zero
files of one era and N of the other is a normal, complete corpus. `open-prs` mode sweeps open
lean-prefixed PRs and flags ones whose linked issue carries no comment referencing the
expected verdict-record path — the operator-visible backlog signal pipeline-retro's existing
unattended branch (SKILL.md, "Approval gate (no-auto-commit)") now calls.

**Model identity rides the existing records.** `lean-gate.sh`'s `ensure_progress_file()` and
`cmd_verdict()` each gain one more header line, `model: <token>`, sourced from an optional
`LEAN_RUN_MODEL` env var (read once, at the same point `run_id`/`session_id` are captured —
no new cache file, no new artifact type). Absent, it reads `model: unknown`, which
`retro-corpus.sh` surfaces as-is rather than erroring — a pre-existing record predates the
field by construction. `retro-corpus.sh` reads it with the same first-match `key: value`
extraction shape `lean-gate.sh`/`lean-reconcile.sh` already use on these records.

**`pipeline-retro` and `perf-retro` are rewired to the shared tool.** `perf-retro` Step 1's
raw `*.json` enumeration loop is replaced with `retro-corpus.sh corpus --json`, and its
Step-6 report labels both eras rather than folding artifact rows into per-stage timing they
cannot produce (no `stages` object to compute against). `pipeline-retro` Step 1 branches per
target issue on which schema exists and gathers the matching artifact set (progress record +
committed verdict record + hook ledger + PR/tracker trail for `artifact`; the existing state
file family for `stage`); Step 3's stage-mechanics-only checklist items (skills-loaded ledger
diff, stage checkpoints, the mutation-gate audit) read N/A for an `artifact`-schema run rather
than silently skipping.

## Open regions, dispositions taken

- **Eval-criteria mapping for block/artifact runs** — not taken. The five staged eval
  criteria assume stages; this issue does not invent a mapping. `pipeline-retro` Step 2
  routes a Criteria proposal for an `artifact`-schema run instead of re-scoring against
  criteria that do not fit — the operator owns the eval frame, per the issue body.
- **The scheduled/unattended retro runner itself** (epic #286–290) — not built here, same as
  #345's own deferral. This issue only extends `pipeline-retro`'s existing unattended branch
  (the "record each actionable route as proposed" posture) with one more proposed action:
  the verdict-less-PR sweep.
- **Model-identity value source** — reversible default taken: an optional `LEAN_RUN_MODEL`
  env var, read once at record-creation time, default `unknown`. #356/#357 own the
  neutrality/format of the id string itself; this issue only wires its presence as a corpus
  key, per the ratified comment.

## ACs

- **AC-1** (oracle — selftest): `retro-corpus.sh corpus --json` against a fixture state dir
  containing only artifact-schema records (no stage `.json` files) exits 0 and emits a
  complete JSON array with at least one `era: "artifact"` row — no longer the
  `has("stages")`-glob hard failure the raw enumeration produces on the same fixture.
- **AC-2** (oracle — selftest): a mixed-era fixture (one stage-schema `.json` plus one
  artifact-schema progress file in the same state dir) aggregates without error into one
  array carrying both an `era: "stage"` and an `era: "artifact"` row.
- **AC-3** (oracle — selftest): corpus-membership — a lean-schema run's ticket key appears in
  `retro-corpus.sh corpus --json`'s output array (the sweep's input set) once its progress
  file is placed in the state dir.
- **AC-4** (oracle — selftest): each artifact-schema corpus row carries a `model` field,
  sourced from the progress/verdict record's `model:` header key and defaulting to
  `"unknown"` when the key is absent (a record written before this change, or with
  `LEAN_RUN_MODEL` never exported) — the corpus-key directive from the ratified comment.
- **AC-5** (oracle — selftest): `retro-corpus.sh open-prs`, given a `--pr-list-file` fixture
  and a fixture comments set, flags a lean-branch PR as verdict-less when its linked issue's
  comment trail carries no reference to the expected verdict-record path, and does not flag
  one whose comment trail does.
- **AC-6** (critic — docs): `pipeline-retro/SKILL.md` Step 1 branches per issue on which
  schema exists instead of assuming stage files; Step 2 routes a Criteria proposal (not an
  invented mapping) for an artifact-schema run; Step 3's stage-only checklist items read N/A
  for one. `perf-retro/SKILL.md` Step 1 sources its corpus from `retro-corpus.sh corpus
  --json`; its Step-6 report template labels both eras.
- **AC-7** (critic): the PR carries a `Changelog:` trailer.
