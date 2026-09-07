# second-shift #813 — Lane bench: arm wrapper and cell runner on the post-#805 lane

Slice 2 of the lane bench (#811), and the half that depends on #805: the arm wrapper that loads a
second-shift ref into the lane's payload sessions, and the runner that takes one bench cell
(ticket, arm, repeat) end to end on the private eval substrate and appends a scored row.
Predecessor: #812, which landed the protocol document, the terminal-class map and the scorer.

## Goal

Land `tools/lane-bench-arm.sh` and `tools/lane-bench.sh run`, so one cell runs end to end through
the post-#805 lane on the private eval substrate and appends exactly one scored row to the bench
repo's results file.

## Scope

### In

- `tools/lane-bench-arm.sh`, used as `LEAN_SPAWN_BIN`, with a same-directory
  `tools/lane-bench-arm-selftest.sh` over a `claude` fake.
- `tools/lane-bench.sh run`, and the cases it adds to `tools/lane-bench-selftest.sh` over a lane
  stub at the `LEAN_BENCH_LANE_BIN` seam plus a `gh` fake.
- The three doc sentences that this slice makes false: `docs/lane-bench.md`'s closing line,
  `tools/lane-bench-classes.tsv`'s "WHO READS THIS" note, and `tools/lane-bench.sh`'s own header.

### Out

- The protocol document and `score` — the predecessor slice, unchanged here except for the header
  sentences AC-13 names.
- The isolation probe run, the AC-4 dry run, the series baseline: operator-run, tracked on #811.
- The `SECOND_SHIFT_CONFIG` forward in `orchestrate-lean.sh` — #805's, landed via #811 OR-5.
- Any edit under `plugins/**`.

## Acceptance Criteria

- AC-2: WHEN `tools/lane-bench-arm.sh` is invoked as `LEAN_SPAWN_BIN` with `LEAN_ARM_MANIFEST` set
  THEN a session-dispatch argv reaches the session binary verbatim (permission mode, model,
  prompt, `--settings`, and every flag #805 adds) followed by `--setting-sources ''` and exactly
  one `--plugin-dir` per manifest entry, and nothing else; a selftest over a `claude` fake asserts
  the full argv for a six-directory and a two-directory manifest, asserts that an
  `agents --json --all` and a `stop <id>` invocation reach the fake unmodified, asserts that the
  fake's stdout line (`backgrounded · <id>`) and exit status reach the caller unchanged and
  unprefixed, and asserts an exit-2 stderr refusal for an unset, unreadable, or empty manifest and
  for an entry naming a missing directory.
- AC-7: WHEN `tools/lane-bench.sh run` runs a cell THEN it creates a clean arm worktree, asserts
  the eval config's tracker host is the substrate, files a fresh issue as the operator, applies
  the queue label, writes the receipt to the gate's ledger path, launches `orchestrate-lean.sh`
  detached with explicit `--build-model`, `--review-model`, `--review-model-basis`,
  `--max-rounds`, `SECOND_SHIFT_CONFIG`, `LEAN_SPAWN_BIN` and `LEAN_ARM_MANIFEST`, reads the
  terminal row from the launch ledger, reads the resolved model ids from the payload transcripts,
  calls `score`, and appends exactly one row; a selftest over a lane stub at the
  `LEAN_BENCH_LANE_BIN` seam (writing a launch ledger, a progress record, and an exit status) plus
  a `gh` fake covers `approved`, `paused`, `no-pr`, `pr-unapproved`, `lane-error` with its single
  re-run, `unscorable`, the duplicate-cell refusal, the in-arm drift refusal, the dirty-worktree
  refusal, and the wrong-tracker-host refusal.
- AC-10: No arm run writes a comment, label, or state row to the second-shift tracker or any
  consumer tracker; enforced by the runner's pre-cell assertion that the eval config's tracker
  host is the substrate repo (AC-7), and audited by the bench repo's results file carrying only
  substrate issue numbers.
- AC-11: No second-shift artifact of this work (issue, comment, PR, commit, doc) names a consumer
  repo, org, or GitHub App; checked by a denylist grep the operator keeps outside the repo, run
  over every PR of this work before merge.
- AC-12: No PR of this work edits a plugin `version` field or `CHANGELOG.md`.
- AC-13: WHEN this slice lands THEN no shipped prose still says the runner or the arm wrapper is
  unwritten: `docs/lane-bench.md`'s closing sentence, `tools/lane-bench-classes.tsv`'s "WHO READS
  THIS" note and `tools/lane-bench.sh`'s file header each describe `run` as shipped and name what
  it reads, and `docs/lane-bench.md` states the runner's own contract — the arm worktree, the
  manifest, the detached launch, the terminal-row poll, the resolved-model-id read, the
  single-re-run rule, and the four pre-cell refusals.

AC-1 and AC-8 are the predecessor's; AC-3 through AC-6 and AC-9 are the epic's operator-run parts
and are not this slice's to satisfy. AC-11 and AC-12 bind every PR of the work and are restated
here so this slice is graded against them.

## Design

Design: none — this slice ships two shell tools and their selftests. It renders no UI and no
`design.provider` is configured for this repo.

## Decision Ledger

Carried forward from `.claude/pipeline-state/811-ledger.md` (D-25 through D-47), which is the
epic's pre-flight receipt; this slice has no pre-flight ledger of its own, so the rows below are
the epic's under their original ids where they bind this slice, plus this slice's own build-time
decisions from D-48 on.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-25 | Scoring rule for terminals | A PR always gets the overlay; class from the launch ledger's terminal slug, the progress record, and PR presence, by `tools/lane-bench-classes.tsv`; `paused` = `build-no-pr` + a milestone-1 `pause-and-ask` row; an unmapped slug is `lane-error` and the cell is re-run once | codebase-derived |
| D-26 | Settings the ablation removes | `--setting-sources ''` drops grants and settings-declared hooks in every arm alike; the wrapper adds no `--settings` of its own, because `LEAN_RUN_MODEL` is per-role and the scheduler already writes it | codebase-derived |
| D-28 | Queue label and receipt path | `tracker.labels.queue` from the eval config; the receipt is written to `<stateDir>/<issue>-ledger.md` as the gate computes it, with `retro-corpus.sh`'s ladder (`STATECTL_STATE_DIR`, else `<root>/<paths.pipelineStateDir>`, default `.claude/pipeline-state`); `orchestrate-lean.sh` has no `--ledger-file` pass-through | codebase-derived |
| D-29 | Wrapper transparency and scope | `exec` into the session binary; the child's stdout, stderr and exit status are the wrapper's; only a session dispatch (argv carrying `--bg`, `-p` or `--print`) gets the appended flags; `agents` and `stop` route through the same handle and pass unmodified; refusals go to stderr with exit 2 | codebase-derived |
| D-31 | Terminal-slug source | The launch ledger `<stateDir>/<issue>-lean-launches.tsv` terminal row, not the control stdout (the launch is detached under `nohup`) and not the many-to-one exit code | codebase-derived |
| D-32 | Runner/scorer seam | One script with `run` and `score` subcommands; `run` appends the row and then calls `score`, which rewrites columns 13..19 | codebase-derived |
| D-36 | Manifest generation | `run` creates the arm worktree and writes an absolute-path manifest into the cell's scratch dir; no checked-in manifests; an empty manifest or a missing directory is a wrapper refusal | codebase-derived |
| D-37 | Results file and resume | `--results <path>` is required; a cell id already present is refused; there is no default scratch file | codebase-derived |
| D-39 | AC-10 rung | `run` asserts the eval config's tracker host is the substrate before each cell; the results file carries only substrate issue numbers | codebase-derived |
| D-46 | Model identity on the row | `--model opus` is an alias that moves with releases, so `run` reads each payload session's resolved model id from its transcript and writes the id, never the alias | codebase-derived |
| D-48 | Cell identity on the command line | The usage sketch in the ticket names no flag carrying the arm's NAME, but `cell_id` is `t<role>-<arm>-r<repeat>` and an arm ref does not spell one. `run` takes `--arm <name>` as required identity, alongside `--arm-ref <ref>` or `--skeleton --control-ref <sha>` which say what to check out. Same route the predecessor took for `score --issue`: the committed spec is the definition of done and no AC binds the CLI signature | codebase-derived |
| D-49 | Corpus body and title | The fixture issue's body is `--body <file>` from the bench repo, and its title is that file's first `# ` heading — refused when absent. One flag rather than two, and the corpus file carries its own title, so a role's issue text is fixed by the corpus and not by the invocation | codebase-derived |
| D-50 | What "the tracker host is the substrate" is asserted against | `--substrate <owner/repo>`, an operator-supplied value, compared against `gh repo view --json nameWithOwner` run from the substrate root the eval config resolves. Not a literal in this repo (the anonymization rule) and not inferred from the config's own repo key, which is the gate's path key and need not equal the GitHub repo name. A `gh` read that errors is a refusal, not a pass | codebase-derived |
| D-51 | Which copy of the wrapper and of the scheduler each cell uses | The scheduler is the ARM worktree's `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` — the arm ref is the harness under test. The wrapper is the RUNNER's own sibling `tools/lane-bench-arm.sh`, constant across arms: a wrapper that varied with the arm would be a confound on the quantity being measured | codebase-derived |
| D-52 | `review_model` when no REVIEW session ever spawned | `n/a`, the same word `review_catch` carries for the same reason. Empty is not available: `score` refuses a row with a blank column 1..10, and a `review-dark` arm has no REVIEW spawn row to read a model id from | codebase-derived |
| D-53 | A spawn row whose transcript cannot be read | A refusal (exit 2), no row appended. A series is keyed on the resolved model id, so a row carrying a guessed or blank one is worse than a missing cell — the alias is exactly what D-46 exists to keep off the row | codebase-derived |
| D-54 | Session id in the ledger vs transcript filename | The ledger's `spawn` row records the CLI's short id (`8794d0e0`) while the transcript is `<full uuid>.jsonl`, so the read globs `$HOME/.claude/projects/*/<id>*.jsonl` — the glob-not-slug-derivation precedent of `orchestrate-lean.sh:transcript_close`, widened to a prefix. More than one match is a refusal, not a first-wins pick | codebase-derived |
| D-55 | Choosing between a slug's two class rows | By the class PAIR the table gives, never by the slug: `{paused, no-pr}` is decided by a milestone-1 `pause-and-ask` row in the progress record, `{pr-unapproved, no-pr}` by PR presence on the lane branch. An unknown slug, or a pair the runner does not model, is `lane-error`. The condition column stays prose for the reader; the code reads the classes | codebase-derived |
| D-56 | Seams the runner ships | `LEAN_BENCH_LANE_BIN` (the scheduler, default the arm worktree's), `LEAN_BENCH_SS_ROOT` (the second-shift checkout the arm worktree is cut from, default this script's own repo), `LEAN_BENCH_POLL_SECS` (default 30), `LEAN_BENCH_CELL_CEILING_SECS` (default 28800), and `${GH:-gh}` as the predecessor already uses. Every one has a shipped default pointing at the real thing, the convention `orchestrate-lean.sh` states for its own | codebase-derived |
| D-57 | A cell whose lane never writes a terminal row | The ceiling above is reached, the class is `lane-error`, and the cell takes its one re-run. A lane that did not terminate is a class the bench cannot read, which is what `lane-error` means | codebase-derived |
| D-58 | The new suite's timings row | `tools/lane-bench-selftest.sh` measures 11s, past both consumers' bars, so it gets an honest row in `tools/selftest-suite-timings.tsv` rather than none. The consequence is disclosed rather than discovered: milestone 3 and the PR-lane mutation sweep both defer it from here on, and the suite's evidence is CI's two selftest jobs, the merge-time sweep, and this session's direct runs. That file is a cost record, and shaving a measurement to keep one lane green is the trade it exists to prevent | codebase-derived |
| D-59 | Which new sites earn a catalog row | Four, each probed and killed in an isolated worktree rather than credited: the wrapper's one dispatch discrimination, the tracker-host assertion (AC-10's only mechanical rung), the pause-and-ask discrimination that corpus role 2 is measured on, and the `n/a` review model without which every skeleton cell is appended and then refused. The three survivors the generic tier found are baseline rows, not coverage gaps: each is a seam the suite must bind in every case | codebase-derived |

## Notes

`--bare` is never added by the wrapper and never refused: it kills subscription auth, and the
decision to pass one belongs to the caller, not to a transparent handle.

OR-4 (whether a permission grant must be restored identically across arms under empty setting
sources) keeps its default of none — the wrapper adds no `--settings`. The epic's AC-4 dry run
decides it, and a grant added later is identical across arms and named in the pre-registration.
