# second-shift #149 — reconcile a non-terminal state file against the tracker on resume

## Problem

A `/dev-pipeline:run` session can die in the Stage-9 tail — after `gh pr create` but
before `statectl pr-add` / `mark-completed` — leaving `.claude/pipeline-state/{issue}.json`
at `status: in_progress` even though the tracker already shows the issue closed via a
merged PR. This is not state-file corruption (the file accurately records where the
session stopped); it is misleading on resume, and it corrupts `perf-retro`'s corpus:
the file still matches the corpus filter (`has("stages")`, not `*-released-*`), so its
truncated stage windows skew per-stage medians (see issue comment, 2026-07-28 perf-retro,
runs #245/#167/#127).

`statectl reclaim <issue> --release` already exists and quarantines a stale state file
to `{key}-released-{ts}.json`, which the corpus filter already excludes — so reconciling
via `reclaim` fixes the corpus-corruption angle for free. The gap named in the issue is
that nothing calls `reclaim` automatically; today's resume logic (`SKILL.md` "Resume
logic" rule 2) goes straight from `status: in_progress` to resuming `currentStage`, with
no tracker read at all.

## Decisions (resolving the issue's two open questions)

- **Report + narrow auto-action, not full auto-complete.** `mark-completed`'s three
  terminal-write gates (all stages `completed`, a real `{issue}-eval.json`, a real
  `{issue}-report.md`) are not `--force`-bypassable for existence — see
  `statectl.sh` `cmd_mark_completed` / `require_eval_file` / `require_report_file`.
  Reconciling by forcing a terminal write would have to fabricate evidence for gates
  designed to refuse exactly that. So reconcile does **not** call `mark-completed`; it
  quarantines via the existing `reclaim --release` path and stops.
- **No synthesized eval or report.** A reconciled run stays explicitly un-scored — the
  closing comment says so, so `pipeline-retro` / `perf-retro` never mistake a quarantined
  file for scored evidence.

## Scope

1. **AC-1 — pure-logic verdict tool.** Add
   `plugins/dev-pipeline/skills/run/tools/tracker-reconcile-check.sh`, mirroring
   `predecessor-gate.sh`'s split: the stage/resume prose owns the one tracker read
   (`gh issue view <issue> --json closed,closedByPullRequestsReferences`), the tool is
   pure logic fed via args — no network, nothing to mock, bash-3.2-compatible.

   ```
   tracker-reconcile-check.sh verdict <run-status> <tracker-closed> [<pr-number> <pr-url>]
   ```

   - `<run-status>`: exactly `in_progress` | `completed` | `failed` (case-sensitive) — else usage error.
   - `<tracker-closed>`: exactly `true` | `false` — else usage error.
   - `<pr-number>` / `<pr-url>`: both-or-neither (supplying exactly one is a usage error).

   | run-status | tracker-closed | PR pair | verdict | exit | stdout |
   | --- | --- | --- | --- | --- | --- |
   | completed/failed | any valid | any | `not-applicable` | 0 | `verdict=not-applicable` |
   | in_progress | false | any | `resume-normal` | 0 | `verdict=resume-normal` |
   | in_progress | true | absent | `resume-normal` | 0 | `verdict=resume-normal` |
   | in_progress | true | present | `reconcile-recommended` | 4 | `verdict=reconcile-recommended`, `closingPrNumber=<n>`, `closingPrUrl=<u>` |

   Usage errors (missing/unknown mode, missing/unknown run-status or tracker-closed value,
   exactly one of the PR pair, stray args) exit 2 with a usage message on stderr — never a
   silent `resume-normal`.

2. **AC-2 — per-tool selftest.** Add
   `plugins/dev-pipeline/skills/run/tools/tracker-reconcile-check-selftest.sh` (same
   harness shape as `predecessor-gate-selftest.sh`: `pass`/`fail` helpers, exit code =
   failure count). Cover every row of the table above, both terminal statuses, both usage
   errors on malformed run-status/tracker-closed, the one-of-the-pair usage error, no-arg
   and unknown-mode usage errors, and case-sensitivity (`True`/`CLOSED` etc. are usage
   errors, not silent resumes).

3. **AC-3 — wire into resume logic.** Edit `plugins/dev-pipeline/skills/run/SKILL.md`:
   - Rule 2 (`status: "in_progress"`) runs the tracker check before resuming:
     ```bash
     read -r CLOSED PRN PRU <<<"$(gh issue view "$ISSUE_NUMBER" \
       --json closed,closedByPullRequestsReferences \
       --jq '[(.closed|tostring), (.closedByPullRequestsReferences[0].number // ""|tostring), (.closedByPullRequestsReferences[0].url // "")] | @tsv')"
     bash tools/tracker-reconcile-check.sh verdict in_progress "$CLOSED" "$PRN" "$PRU"
     ```
     - `reconcile-recommended` (rc=4) → **do not resume stage work.** Instead:
       `statectl reclaim <issue> --release` (quarantines the state file); one `$GH_BOT`
       comment stating the tracker already shows the issue closed via the merged PR, that
       the pipeline session died before Stage 9, that the state file was quarantined to
       `{issue}-released-{ts}.json`, and that **no eval or report was synthesized** — the
       run stays un-scored for retro purposes; remove the `in-progress` label via
       `$GH_BOT` if still present; stop.
       In autonomous mode this happens without prompting (no operator decision is being
       made — the tracker is already the source of truth); interactive mode may still
       narrate it, but does not ask permission to quarantine an already-shipped run.
     - `resume-normal` / any other rc → continue exactly as today (no behavior change).
   - Update the "Orphaned claims" paragraph to reflect that this check is now automatic
     on every `in_progress` resume, not something the operator triggers by hand; keep the
     manual `statectl reclaim` guidance for the case the tracker check can't apply (e.g.
     the tool errors, or the issue was closed without a linked PR).

4. **AC-4 — composed scenario coverage.** Add a case to `scenario-liveness-selftest.sh`
   exercising the full composed path: a stale `in_progress` state fixture +
   `tracker-reconcile-check.sh verdict in_progress true <n> <u>` → `reconcile-recommended`
   → `statectl reclaim <issue> --release` → assert the file is quarantined to
   `{key}-released-{ts}.json` and that it now fails the perf-retro corpus filter's
   `*-released-*` exclusion (i.e. `case "$f" in *-released-*) ;; esac` would skip it).
   This is a new composed path, distinct from — and does not claim to close — the
   pre-existing "reclaim --release quarantine -> fresh init" debt line already on record
   in that suite's header comment.

## Non-goals

- No change to `mark-completed`, `perf-retro`'s corpus filter, or `pipeline-doctor.sh` —
  the perf-retro corpus-corruption angle is already fixed for free once a run is
  quarantined via the existing `*-released-*` exclusion.
- No jira-adapter-specific handling: `closedByPullRequestsReferences` is a GitHub-only
  concept; a jira consumer's tracker check is out of scope for this issue (the existing
  tracker adapter abstraction already documents no-op operations per `tracker.type`).
