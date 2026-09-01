# #723 — cost per merged PR is a committed number

`pipeline-cost-block.sh` already renders a dollar figure into a "Cost (USD)" Markdown table cell,
but only as a cell a human reads — no surface carries it as a key a script can grep. This adds a
`cost_usd:` key to both surfaces `cmd_close_out` already writes — a bullet in the closing comment
(present on every closed-out run) and a line inside the PR description's cost-block region (present
whenever a block is published) — and documents a `gh`/`jq` recipe in `cost-tracking-setup.md` that
reads the last 10 merged PRs back, with a labeled legacy fallback and its own coverage line. No new
script, hook, mode, or channel; no `pipeline-cost-block.sh` change. Part of #717.

## Decision Ledger

Carried from the pre-flight ledger at `.claude/pipeline-state/723-ledger.md` (11 rows, 1 open
region), via `ledger-carry-forward.sh`; ids and Resolutions are its own.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which surface carries the machine-readable figure | Both surfaces `cmd_close_out` already writes: the closing comment on the issue and the PR description's cost-block region. NOT the verdict record — it is committed at milestone 4, strictly before close-out renders the figure, so a key there could only be back-filled by amending a committed record, moving the branch and costing a review round. | user-answered |
| D-2 | Does #723 build the reader its kill criterion names | No new shell. The figure lands on the D-1 surfaces; the reader is a documented `gh` + `jq` recipe in `plugins/dev-pipeline/cost-tracking-setup.md`. The kill criterion is re-worded from "`retro-corpus.sh` prints" to "the documented recipe prints", keeping the ticket's net diff near flat per epic #717's rule. | user-answered |
| D-3 | What the key says on a run with no dollar figure | The closing comment carries `cost_usd:` on EVERY closed-out run — a bare number, or `unavailable` plus a reason. The PR description carries it only when a cost block is published; close-out's skip behavior is unchanged. Presence of the key is therefore the discriminator between an unpriced run and a comment predating this ticket. | user-answered |
| D-4 | The recipe's window and aggregate | Window is the last 10 merged lean PRs by merge date. Print the mean over the priced subset AND the coverage explicitly (e.g. "$33.10 mean over 7 of the last 10 merged PRs; 3 unpriced"). Nothing is imputed and no unpriced run is scored as zero. | user-answered |
| D-5 | Does #723 close the ~36% unpriced-run gap | Out of scope. #723 publishes whatever figure exists; the recipe's printed coverage line is the standing measurement, and no follow-up ticket is filed now. Cause is recorded for whoever picks it up: the scheduler spawns plain `claude -p`, and a headless `-p` session writes no `cost-state` record, while `--output-format json` would return `total_cost_usd`. | user-answered |
| D-6 | Whether the recipe reads pre-#723 PRs | Yes, as a labeled legacy fallback: read `cost_usd:` first, then for a PR with no key grep `\$[0-9]+\.[0-9]{2}` out of the rendered cost block, and label in the output which figure came from which. This makes the kill criterion demonstrable in the merge PR itself instead of after ten further runs. | user-answered |
| D-7 | The reason vocabulary behind `unavailable` | Exactly two values, both derivable from state close-out already holds: a block was rendered but carries no `Cost (USD)` column, versus `LEAN_COST_SKIP` is set and no block exists at all. Naming which of the four `skip(…)` verdicts fired is NOT available — close-out deliberately does not capture the tool's stderr ("the tool's stderr is the operator's evidence and is deliberately not captured", `lean-gate.sh` `closeout_cost_block`), and this ledger does not reopen that. | codebase-derived |
| D-8 | Value format | A bare decimal with no currency sign — `cost_usd: 70.41`. The repo's `record_key` idiom (the `lean-record-key` LOCKSTEP block shared by `lean-gate.sh` and `retro-corpus.sh`) matches `[A-Za-z0-9._/-]+`, which a leading `$` does not satisfy, so `$70.41` would read back as an absent key. | codebase-derived |
| D-9 | Where the key sits within the closing comment | A visible bullet beside the existing `- PR:` and `- Verdict record:` entries — that function's own house style — and OUTSIDE the rendered cost block. Inside the block it would inherit the block's absence on a skip verdict. An HTML-comment form would also have been safe: `scripts/check-pipeline-chain.sh` selects run families strictly on `<!-- stage: … -->`, so a non-`stage` token does not enrol this comment. The bullet is chosen for legibility, not for safety. | codebase-derived |
| D-10 | The local cost corpus | Unchanged. `.claude/pipeline-state/cost-log.jsonl` and `perf-retro`'s use of it are untouched; this ticket adds a tracker-side figure and migrates nothing. | codebase-derived |
| D-11 | Build model for the handoff | `sonnet`. Basis: the receipt leaves zero decisions open to the builder, the deliverable is a bullet plus a key in one already-touched function and a documented recipe in one markdown file, and it introduces no new guard surface and no architectural call. Sibling sizing agrees — #719 and #721 ran `sonnet` on comparable single-surface edits. | user-delegated |

### OR-1 (Key coverage under a `tracker.writes: false` (jira) adapter — reversible-default-and-flag)

Under jira, `cmd_close_out` posts no closing comment at all — the PR body carries the verdict
reference instead — so D-3's guarantee ("every closed-out run carries the key") holds on the
github adapter only. The default taken is the github-complete / jira-partial one: on jira the key
rides the PR-body arm alone (D-1's PR-description surface) and is absent on skip-verdict runs.
Reversing this later is cheap and additive, which is why it is flagged rather than paused on and
why this build adds no jira-specific code.

## Design

Design: none — this is a shell-string change plus a documentation recipe, no web surface, and this
repo configures no `design.provider`.

## Acceptance criteria

- AC-1 (D-1, D-9): `lean-gate.sh close-out`'s `closeout_comment()` posts a `- cost_usd: <value>`
  bullet beside its existing `- PR:` / `- Verdict record:` bullets, OUTSIDE the pasted cost block,
  on every github closed-out run — including a full skip, where no block exists at all.
- AC-2 (D-1, D-3): The cost block `closeout_patch_pr_body()` writes into the PR description
  carries its own `cost_usd: <value>` line, present exactly when a cost block is published
  (unchanged skip behavior — a full skip still patches nothing into the PR description).
- AC-3 (D-8): The value is a bare decimal with no `$` when a priced block rendered (e.g.
  `cost_usd: 70.41`), and `unavailable (<reason>)` otherwise, naming which of D-7's two reasons
  applies — a block rendered with no `Cost (USD)` column, or no block rendered at all.
- AC-4: The two surfaces' copies are computed independently from one shared, PRISTINE
  `$LEAN_COST_BLOCK` — the block `closeout_comment` pastes never itself carries a `cost_usd:`
  line, so the comment says the key exactly once (the bullet), never twice.
- AC-5: A re-entered close-out (a second `bash lean-gate.sh close-out` on the same PR, e.g. after
  a fix round) replaces the PR-description's `cost_usd:` line along with the rest of the block —
  never two such lines, never a stale one left behind as preserved text below the terminator.
- AC-6 (D-2, D-4, D-6): `plugins/dev-pipeline/cost-tracking-setup.md` documents a runnable recipe
  — `gh pr list` + `jq`, no new script — that reads the last 10 merged **lean** PRs (filtered on
  the configured `tracker.branchPrefix` via `headRefName`, matching D-4) by merge date: `cost_usd:`
  first, a labeled legacy `\$[0-9]+\.[0-9]{2}` block-grep fallback for a PR predating this ticket,
  the mean over the priced subset, and the coverage explicitly (nothing imputed, no unpriced run
  scored as zero).
- AC-7: No change to `pipeline-cost-block.sh`, `retro-corpus.sh`, `.claude/pipeline-state/cost-log.jsonl`,
  or `perf-retro` (D-2, D-10). No new script file. No jira-adapter code (OR-1 stays flagged, not built).
- AC-8: `lean-gate-selftest.sh` gains coverage for: a priced run's resolved value and both surfaces'
  copies, an unpriced-but-rendered run's `unavailable` reason, a full-skip run's `unavailable`
  reason and comment-only coverage, the re-entry non-duplication case (AC-5), and the
  comment-says-it-once case (AC-4).
- AC-9: `feat(dev-pipeline):` commit verb — new capability, not a bugfix or refactor — with a
  `Changelog:` trailer. No `plugin.json` `version`, `CHANGELOG.md`, or marketplace `version` edits.

## Implementation notes (non-binding detail, subordinate to the ACs above)

1. `lean-gate.sh`: `resolve_cost_usd()` sets `$LEAN_COST_USD` from `$LEAN_COST_BLOCK`/`$LEAN_COST_SKIP`
   (D-7/D-8), called from `closeout_cost_block()` on both arms so a value exists whether or not a
   block rendered. `cost_block_with_usd_key()` echoes `$LEAN_COST_BLOCK` with a `cost_usd: …` line
   inserted right after the block's own thematic break (`---`), not right after the marker line —
   inserting it directly under the marker would leave it as a setext-H2 paragraph with the `---`
   read as the underline, swallowing the block's `<hr>` on GitHub's renderer (round 1 finding) —
   never mutating the shared `$LEAN_COST_BLOCK` — and `closeout_patch_pr_body()` calls it in place
   of the raw block when building the patched PR body. `closeout_comment()` adds the
   `- cost_usd: $LEAN_COST_USD` bullet directly, unconditional on whether `$LEAN_COST_BLOCK` is set.
2. `cost-tracking-setup.md`: a new section documenting the `cost_usd:` key and the `gh pr list` +
   `jq` recipe (D-4, D-6) — window of 10 by `mergedAt`, `cost_usd:` capture with a legacy
   `\$[0-9]+\.[0-9]{2}` block fallback labeled in the output, the priced-subset mean, and the
   coverage line.
3. `lean-gate-selftest.sh`: new cases in the `(co)` block — `resolve_cost_usd` on a priced block, an
   unpriced-rendered block, and a full skip; `cost_block_with_usd_key`'s re-entry
   non-duplication over the real `closeout_patch_pr_body` call; `closeout_comment`'s bullet on a
   priced run and on a full-skip run, each checked for exactly one `cost_usd:` occurrence.

## Out of scope

Fixing the ~36% of historical runs that publish no dollar figure (D-5). Any `cost-log.jsonl` /
`retro-corpus.sh` change (D-2, D-10). A verdict-record key (D-1). The jira PR-body arm's own
`cost_usd:` coverage (OR-1). Anything under `pipeline-cost-block.sh` itself.
