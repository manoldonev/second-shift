# 546 — the lean cost block derives its own time fence and session set

The published cost figure is only as good as the close-out session's reconstruction of two
values it is structurally least able to know: when the run began, and how many sessions it
spent. `pipeline-cost-block.sh --stateless` takes both as arguments and validates neither, so
a plausible-but-wrong fence renders a well-formed block that no gate reads and no human
questions. One shipped run published 43 min / 1 session for a 98-minute, three-session run.

Both values are already written down — in the run's own append-only progress record. This
change makes the script read them, and restores the machine-readable `cost-log.jsonl` row that
the lean era dropped, so cost-effectiveness has a corpus to be measured against again.

## Acceptance criteria

**AC-1 — `--issue <n>` derives the time fence from the progress record.** Invoked with
`--issue <n>`, `pipeline-cost-block.sh --stateless` resolves the run's lean progress record and
takes the fence from it: `--start` = the record's FIRST timestamped row, `--end` = its LAST, at
invocation time. The record is append-only, so first/last are also earliest/latest.

**AC-2 — `--issue <n>` derives the session set from the same record.** The set is the header
`session_id:` UNION every `| session | <id>` row, with the empty string and `unset` excluded —
`build_session_set()`'s definition in `lean-gate.sh`, which is already what the `mark` refusal
uses. The two copies are held by a `LOCKSTEP-BEGIN lean-session-set` marker on each.

**AC-3 — the review session is unioned in when its record exists.** When the progress header's
`verdict_record:` names a file that exists in the worktree, that record's header `session_id:`
joins the set. A pre-review or aborted invocation finds no such file and degrades to the
build-only set — silently, not as an error.

**AC-4 — a set that includes review is titled honestly.** With the review session unioned in,
the rendered total row reads `Run total (build + review — …)`. Without it the row is unchanged
(`Session total (lean run — …)`). The block must never say "Session total (lean run)" while
counting a session that was not the build's.

**AC-5 — explicit arguments still win.** `--sessions`, `--start` and `--end` override their
derived counterparts individually. Without `--issue`, the script's contract is byte-for-byte
what it is today: both inputs required, `rc=2` naming whichever is missing.

**AC-6 — an underivable fence is a usage error, not a plausible default.** With `--issue`, a
progress record that is absent, unreadable, or carries no timestamped row exits `2` naming the
resolved path. Deriving nothing and rendering anyway is the defect this ticket exists to close.

**AC-7 — `--close-out` restores the `cost-log.jsonl` row.** `--close-out` (which requires
`--issue`) appends or updates one row per run in `${COST_LOG_FILE:-<stateDir>/cost-log.jsonl}`.
Without the flag the script writes no row, so the step-7 snapshot leaves the corpus untouched.

**AC-8 — the row's schema is cross-era readable.** The row carries `at`, `ticketKey`,
`sessionIds`, `totalUsd`, `durationMin`, `models`, `cacheHitRate` and `prs` — every key a
staged-era row carried — plus `runId`. It carries `byTier` where staged rows carried `byLabel`,
and carries no `byLabel` at all: that presence split is the era discriminator, and no marker
field is added. `tiers` is not restated, being `[byTier[].tier] | unique`.

**AC-9 — the row's identity is (`ticketKey`, `runId`).** A write REPLACES an existing row
carrying the same pair and APPENDS otherwise. A re-entered close-out updates its own row; an
abort→retry under a new run id appends, so aborted runs stay in the corpus as real cost.

**AC-10 — no rollup, no row.** Every `skip(...)` exit — telemetry-off, rotated-out,
session-not-exporting, zero-datapoints — records its stderr verdict and writes nothing, matching
the retired writer. So does `--close-out` on a run whose rollup is empty.

**AC-11 — `--prs` supplies the row's PR references.** Optional, comma- or space-separated;
absent, `prs` is `[]`. The script opens no network connection and amends no PR body.

**AC-12 — the prose sites that assert "no cost-log row" are corrected in the same change.**
`pipeline-cost-block.sh`'s header, `build-lean/SKILL.md` steps 7 and 9, and
`cost-tracking-setup.md` (both the state-less-contract paragraph and the rollup note) state the
new contract. `build-lean/SKILL.md` step 9 additionally states that the close-out re-derives the
figure and REPLACES the PR-body block, keyed on the existing `<!-- pipeline-cost-block -->`
marker, rather than leaving the step-7 snapshot standing as the run's published figure.

**AC-13 — the dead `record` call is removed.** `pipeline-cost-block.sh:239` calls `record`, a
function that has not existed since #584 retired the state file. It is on the no-readable-
metrics path, where `set -uo pipefail` turns it into a stderr line and a continue. Delete it.

**AC-14 — `--help` still prints the whole header and none of the code.** The `-h` branch's
hand-maintained line range moves with the header it prints.

**AC-15 — every new assertion is driven by `cost-block-selftest.sh`.** Fixture progress records
(and a verdict record) drive AC-1 through AC-11 against the real script end-to-end: a derived
fence that differs from a wrong hand-supplied one, an override that wins, an absent record's
`rc=2`, the two titles, the row's key set, the replace-vs-append pair, and a skip path that
writes nothing.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Time-fence derivation for the stateless cost block | New `--issue <n>` mode derives the fence from the lean progress record: first timestamped row → last timestamped row, at invocation time. `--start`/`--end` stay as explicit overrides, per the issue body https://github.com/manoldonev/second-shift/issues/546#issuecomment-5309506584 | ticket-sourced |
| D-2 | Session-set derivation | Reuse `build_session_set()` semantics (progress header `session_id:` ∪ every `\| session \|` row, excluding empty/`unset`) — already the `mark` refusal's definition in `lean-gate.sh`. `--sessions` stays as an override. Confirmed against HEAD in https://github.com/manoldonev/second-shift/issues/546#issuecomment-5309506584 | ticket-sourced |
| D-3 | Review session inclusion | Include. When the verdict record exists at compute time, union its `session_id` header into the session set; retitle the rendered total honestly (e.g. "Run total (build + review)"). Pre-review/abort invocations degrade to build-only set. | user-answered |
| D-4 | Publication point of the full-run figure | Step 7 keeps a fence-labeled snapshot in the PR body; close-out re-derives and posts the full figure in the closing comment AND replaces the PR-body block (keyed on the existing `<!-- pipeline-cost-block -->` marker). The cost-log row is written only by the close-out invocation. | user-answered |
| D-5 | Restore the machine-readable cost-log row | Stateless mode with `--issue` appends/updates a `cost-log.jsonl` row again — the cross-run cost corpus ended 2026-07-31 when the lean era began; cost-effectiveness currently has nothing to be measured against. Supersedes D-36's live half; the three prose sites asserting "no row" (`pipeline-cost-block.sh` header, `build-lean/SKILL.md`, `cost-tracking-setup.md`) update in the same change. https://github.com/manoldonev/second-shift/issues/546#issuecomment-5309506584 | ticket-sourced |
| D-6 | Lean row schema | Keep every cross-era key (`at`, `ticketKey`, `sessionIds`, `totalUsd`, `durationMin`, `models`, `cacheHitRate`, `prs`); write `byTier` where staged rows had `byLabel`, and no `byLabel` at all — the byTier/byLabel presence split is the era discriminator, no extra marker field. | user-answered |
| D-7 | Cost-log row identity | Add `runId` to the row; the writer replaces an existing row carrying the same (`ticketKey`, `runId`), appends otherwise. Re-entered close-out updates its own row; an abort→retry (new run id) appends — aborted runs stay in the corpus as real cost. | user-answered |
| D-8 | Row on skip paths | No rollup → no row, matching the retired writer: every `skip(...)` exit (telemetry-off, rotated-out, session-not-exporting, zero-datapoints) records its stderr verdict only (`pipeline-cost-block.sh` four-way discrimination, #432 D-4). | codebase-derived |

Decisions taken here, under the ledger rather than beside it:

- **D-4 is a skill contract, not a PR-amend path.** The script still performs no PR I/O; the
  close-out session replaces the block it pasted. Re-adding the retired bot-identity amend
  ladder to reach a body the session already owns would buy nothing and cost the ladder.
- **`--close-out` is the row's only trigger.** Verdict-record presence cannot serve: it is true
  from the moment milestone 4 passes, which is not the close-out.
- **`prs` arrives as an argument.** The close-out caller holds the PR URL; the alternatives are
  a network call or reconstructing a URL from a bare number in the verdict header.

## Verification

`shellcheck`, `bash tools/run-selftests.sh` (which discovers `cost-block-selftest.sh`), and
`scripts/check-lockstep-pairs.sh` for the two new marker groups.
