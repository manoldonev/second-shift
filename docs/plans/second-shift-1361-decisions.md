# Decision record — #1361 Lane review pass 1 can read the decision record: blindness is prose-only

Receipt: v4

## Summary

Pass 1 of the lane review becomes its own blind session. It reuses the plain review's copy of the head and its denials, with the lane's pass-1 prompt. The review session then runs pass 2 in the worktree with the pass-1 findings. `/dev-pipeline:review` gets the same blind pass 1 through a new `--prompt` option on `plain-review.sh run`. `run.joinedReview` is retired, and the planted mode of the review benchmark is deleted.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Shape of the blind pass 1 | Pass 1 is its own headless session in each review round. It is built from the parts the plain review uses: `plain-review.sh` `tree`, `deny` and `args`. It runs beside the plain review. The review session starts after pass 1 and runs pass 2 in `$WT` with the pass-1 findings. No new rule carries pass-1 blockers into the verdict. | user-answered | intent |
| D-2 | Inputs of pass 1 | Pass 1 gets the plain review's inputs only: the stripped ticket text (under jira, the fetch instruction) and the diff without the plans directory. When the ticket read fails, pass 1 reviews the diff alone, as the plain review does. `review-context.md`, the ticket comments, the design render, the design-fidelity reviewer, the scheduler input and a re-spawn's broken rules belong to pass 2. | user-answered | intent |
| D-3 | Output of pass 1 and its failure | Pass 1 ends its output in the plain review's format: a `verdict:` line, then `## Findings`, holding `None.` when it finds nothing. The existing `plain-review.sh draft` extractor reads it. A pass-1-only check requires the `## Findings` section; the plain review's check does not change. A pass 1 that runs past its time limit or returns no findings block is a review miss. The plain session is still awaited, its cost is counted, and its draft is discarded. No review session starts, and the existing single retry applies. A `None.` result is valid. | user-answered | intent |
| D-4 | Time and cost limits | Pass 1 and the review session each run under `run.reviewTimeoutSeconds`. Both costs count toward `run.costCeilingUsd`. The round count does not change. | user-answered | intent |
| D-5 | Pass 1 in `/dev-pipeline:review` | `plain-review.sh run` gets a `--prompt <file>` option. The skill runs pass 1 with the pass-1 prompt file that `run.sh` reads, in its own out dir, and starts pass 2 only on its findings. Inputs: `--prompt <file>` (optional; default `plugins/dev-pipeline/skills/run/plain-review.md`); every existing option unchanged. Outputs: unchanged — `<out>/verdict.md`, `ticket`, `result.json`, `start`, `end`, `wall`, and `why` on a failure. Errors: exit 2 when the `--prompt` file cannot be read; exit 1 with `<out>/why` when no draft returns, as today; exit 2 on other usage errors, as today. | user-answered | intent |
| D-6 | The shared review-rules block | Split it. The completeness, correctness, severity and over-engineering rules go into the new pass-1 prompt file. The sentences about record rows stay word for word in the pass-2 text of `run.sh` and `review/SKILL.md`. The accepted-break sentence splits: its ticket half goes to pass 1, its record-row half stays in pass 2. No rule changes. Text that now has one site loses its lockstep markers; the record-row text keeps them in both files. | user-answered | intent |
| D-7 | `run.joinedReview` | Retired. The plain review always runs in the lane, in `/dev-pipeline:review` and in `/review-toolkit:review-lead`. `RUN_JOINED_REVIEW`, `plain-review.sh enabled` and every "plain review off" path go, with their docs, fixtures and selftest cases. `CHANGELOG.md` and earlier decision records are not edited: the changelog is frozen, and a record is history. | user-answered | intent |
| D-8 | A config that still sets `run.joinedReview` | No special handling, because no consumer sets the key. It leaves the schema and the `run` allowlist of `config-lint.sh`, which then reports it as an unknown `run` key. There is no migration note and no `configVersion` bump. | user-answered | intent |
| D-9 | Planted mode of `code-review-bench-eval` | Deleted, with its docs and references. Nothing has run it since 2026-10-29, and each change to the review functions of `run.sh` had to repair it. The public-PR mode stays, because the release checklist uses it. | user-answered | intent |
| D-10 | Criteria with no test | AC-7 and AC-9 are exempt from a test. AC-7 is skill prose, and AC-6's test covers the option it uses. AC-9 is a deletion. The review scores both from the diff. | user-answered | intent |
| D-11 | What the blind copy leaves out | The copy has no `.git`, no plans directory, no `.claude/`, no `.mcp.json` and no `CLAUDE.local.md`. run: `grep -n 'exclude).claude' plugins/dev-pipeline/tools/plain-review.sh` → 68: `git archive … ":(exclude)$3" ":(exclude).claude" …` | codebase-derived | fact |
| D-12 | Reach of the PR description, PR comments and earlier verdicts | Pass 1 cannot reach them, and it cannot follow a link in a Jira body. The deny list holds Agent, Bash, Write, WebFetch and WebSearch, and denies transcript reads. A github spawn loads no MCP server and is allowed Read, Grep and Glob only. run: `bash plugins/dev-pipeline/tools/plain-review.sh deny AskUserQuestion /x` → `AskUserQuestion,Agent,Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,…,Read(//x/**),Read(//Users/<user>/.claude/projects/**)` | codebase-derived | fact |
| D-13 | What a pass-1 retry runs again | The whole review attempt, the plain review included. Each attempt starts the plain session inside the round loop. run: `grep -n 'plain_start "$RA"' plugins/dev-pipeline/skills/run/run.sh` → 2114 | codebase-derived | fact |
| D-14 | The run selftests after the retirement | Every run suite turns the plain review off today, so each suite's fake session must now answer the pass-1, plain and review sessions of a round. run: `grep -n RUN_JOINED_REVIEW plugins/dev-pipeline/skills/run/run-selftest-lib.sh` → 56: `export RUN_JOINED_REVIEW=false` | codebase-derived | fact |
| D-15 | A failed pass 1 in `/dev-pipeline:review` | The skill runs the pass-1 block once more. A second failure starts no pass 2: the session waits for the plain review, tells the operator why pass 1 failed, and posts nothing. Added in build: D-5 says the skill starts pass 2 only on the pass-1 findings, and no row says what it does when there are none; this mirrors the lane's single retry of D-3. | user-delegated | intent |
| D-16 | Notes in the pass-1 output | Pass 1 may end its output with an optional `## Notes` section after `## Findings`. It holds only the lines that the ticket half of the accepted-break and prescribed-mechanism rules writes there. The review session reads it with the findings. Added in build: D-6 moves those ticket rules to pass 1, and each of them writes a `## Notes` line, which the plain review's output form has no place for. | user-delegated | intent |
| D-17 | An out dir under a denied path | `/dev-pipeline:review` writes pass 1 to the sibling of `plain-review.sh out-dir <head>` with `-pass-1` appended, outside its scratch dir. `plain-review.sh run` exits 2 when `--out` is at or inside the worktree or a `--deny-read` path, before it clears or runs anything. Added in build: the review found that a pass-1 out dir inside the denied scratch dir denies the session its own tree, and D-5's errors did not cover that case. | user-delegated | intent |

Options weighed:

- D-1: a separate blind pass-1 session; the plain review as the only blind review; or one blind session that writes both drafts. The operator chose the separate session. A rule that carries pass-1 blockers into the verdict was proposed and cut.
- D-2: pass 1 gets the plain review's inputs; or the harness also pastes `review-context.md` and the ticket comments into it. The operator chose the plain review's inputs.
- D-3: a failed pass 1 is a review miss; or pass 2 runs without it and says so. The operator chose the review miss.
- D-4: one time limit per session; or one limit shared by both passes. The operator chose one limit per session.
- D-5: a `--prompt` option; or the skill calls each part of `plain-review.sh` itself. The operator chose the option.
- D-6: split the rules block; or copy it whole into the blind prompt. The operator chose the split.
- D-7: retire the key in this ticket; or file the retirement as its own ticket. The operator chose this ticket.
- D-8: reject the key by name with a migration pointer; or no special handling. The operator chose no special handling.
- D-9: delete the planted mode; delete the whole benchmark; or update its lane arm. The operator chose to delete the planted mode.
- D-10: `holds` or `exempt` for AC-9; exempt or a test for AC-7. The operator chose exempt for both.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9

AC-1: with a record committed at the head, the pass-1 session's working tree has no `.git`, no plans directory and no `.claude/`, and its flags deny Bash, Agent, Write and WebFetch and reads of the lane worktree, the main checkout, the lane scratch and session transcripts
AC-2: the pass-1 prompt holds the pass-1 rules, the stripped ticket text and the diff without the plans directory, and names no record path, no PR description and no earlier verdict
AC-3: the review session starts after pass 1, its prompt holds the pass-1 findings and no pass-1 review section, and it still names the record at its first commit and at the head
AC-4: a pass 1 that returns no findings block, or runs past its limit, starts no review session and leads to one retry, while a `None.` result starts the review session
AC-5: pass 1 runs under the review time limit, and its cost is added to the run's cost
AC-6: `plain-review.sh run --prompt <file>` sends that file's prompt, no option sends `plain-review.md`, and an unreadable `--prompt` file exits 2
AC-7: exempt — the skill is written instructions, and AC-6's test covers the option it uses
AC-8: with no `RUN_JOINED_REVIEW` and no `run.joinedReview`, a lane review round starts the plain session, and a config that sets `run.joinedReview` fails `config-lint.sh`
AC-9: exempt — a deletion of the planted mode, scored from the diff

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The sessions a lane review round starts | decided (D-1) |
| S-2 | The pass-1 session's tree, denials and inputs | decided (D-2) |
| S-3 | The review session's prompt, now pass 2 only | decided (D-6) |
| S-4 | A pass 1 that fails or times out | decided (D-3) |
| S-5 | The run's time limit and cost cap | decided (D-4) |
| S-6 | The `plain-review.sh run` command line | contract (D-5) |
| S-7 | `/dev-pipeline:review`'s pass-1 step | decided (D-5) |
| S-8 | The `run.joinedReview` key, env var and `enabled` command | decided (D-7) |
| S-9 | `config-lint.sh` on a config that sets the retired key | decided (D-8) |
| S-10 | `/review-toolkit:review-lead`'s plain review | decided (D-7) |
| S-11 | The planted benchmark and its docs | decided (D-9) |
| S-12 | The verdict comment and the join of the two drafts | out-of-scope — the ticket keeps the verdict grammar and the join as they are. |
| S-13 | `/review-toolkit:review-lead` reading a record on a foreign PR | out-of-scope — it has no blind pass today, and this ticket adds none. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`
- `bash scripts/check-dispatchers-and-readers.sh`

## Intake steps

Requirements: the ticket body as written, with no acceptance criteria. spec-reviewer: not implementable as written; its three blockers were operator decisions, settled in the interview. The body was rebuilt from the decided rows and replaced the issue body on the operator's yes. The implementability probe ran on the new body and returned 7 guess-points. Two needed the operator (D-3, D-6), and five the code answered (D-11 to D-14). Its record round found no build-blocking point and no departure. Its five guess-points were folded into D-2, D-3, D-6 and D-7.

Split: not triggered. No epic label and one deliverable. The operator kept the `run.joinedReview` retirement and the benchmark deletion in this ticket.

Explore: done. Read `run.sh`'s review prompt, spawn loop and plain-review functions, `plain-review.sh`, `review/SKILL.md`, `plain-review.md`, `verdict-join.sh`, the benchmark and the joined verdicts on the last 60 PRs.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
