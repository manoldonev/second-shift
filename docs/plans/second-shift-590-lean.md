# The close-out stops being a model session

`orchestrate-lean.sh` spawns a third full model session after the approve to discharge
milestone 5. Every one of that session's outputs is a deterministic command. This replaces the
spawn with a gate subcommand that performs the same writes under the bot identity the lane
already commits and comments with, and has the scheduler invoke it.

**The constraint that survives.** The lane runs a two-identity contract: the scheduler authors
nothing, the review block owns milestone 4 and nothing else. The close-out's writes must
therefore carry the build identity, not a third one. A gate command writing through the bot
wrapper satisfies that — the bot is already the author of the claim marker, the PR marker and
every lane commit — so no new party appears on a close-out artifact.

**The issue body is stale on scope.** It was written before #546 landed and claims the close-out
writes one comment plus a teardown. Post-#546 the close-out also re-computes the cost block,
writes a `cost-log.jsonl` corpus row and replaces the stale block in the PR description. D-2
amends the ticket's "Out: the cost block's derivation rule" line accordingly: those three move
into the command and become asserted obligations, because deleting the session that performs
them without moving them means nobody performs them.

## Acceptance criteria

- **AC-1** — `lean-gate.sh` gains a `close-out <issue>` subcommand in the build role, under the
  same two guards the milestone calls carry: `require_lane_tree` (rc=9 from any checkout not on
  the lane branch) and `require_entry_attested` (rc=2 before `entry` was recorded). It performs
  the close-out's writes, then runs the existing milestone-5 assertions by calling `cmd_5`
  unchanged, then tears the lane down. `bash G 5 <issue>` is untouched and stays a pure verifier
  (D-1).

- **AC-2** — The writes, in order, through the bot wrapper wherever the adapter has one (D-6):
  1. re-compute the published figure — `pipeline-cost-block.sh --stateless --issue <n>
     --close-out --prs <pr-url>`, whose `--close-out` is also what writes the corpus row;
  2. replace the PR description's stale block, keyed on its `<!-- pipeline-cost-block -->`
     marker, appending when the body carries none;
  3. post one closing comment on the issue carrying the PR link, the verdict-record path and
     that block — **github only**. Under `tracker.writes: false` no comment is posted and the PR
     body stays the verdict reference's only carrier, exactly as before.

- **AC-3** — Three new milestone-5 obligations, recorded in the existing obligation namespace and
  surfaced by `progress --obligations` (D-2): `cost-block`, `cost-log-row`, `pr-cost-block`. The
  closing comment gets no fourth — the existing `verdict-reference` obligation already asserts
  it, under both adapters, on the surface each one allows. An obligation row may carry a trailing
  detail, so a documented skip is legible in the record instead of reading as a real figure.

- **AC-4** — The cost obligations degrade honestly rather than fail closed. `pipeline-cost-block.sh`
  exits 0 and emits no block on a documented skip (telemetry off, no collector, window rotated
  out), and "no rollup, no row" is its own structural contract — so `cost-log-row` and
  `pr-cost-block` are recorded **met, with the skip named**. A non-zero exit — the fence or the
  session set could not be derived, which is the defect #546 exists to close — is `cost-block`
  **unmet**, and the close-out reds there without posting anything.

- **AC-5** — Teardown runs only on a fully met close-out (D-6): `close-out` reaches it only after
  `cmd_5` returned 0. A close-out that reds leaves the worktree, the branch and the claim
  standing for a manual rescue. `bash G teardown` remains separately invokable.

- **AC-6** — `cmd_mark`'s "this PR already carries this run's marker" no-op is decided **before**
  its build-session refusal, so the gate invoked by the scheduler — which lends no session
  identity — passes when checklist step 7 already stamped the marker, and still refuses when one
  would have to be written. The `session_in_build_set` test, its message and its wording are
  unchanged; only the order is. What the refusal protects is unchanged too: nothing is written on
  the path that now no-ops, so no foreign identity can reach a marker.

- **AC-7** — `orchestrate-lean.sh` discharges the close-out by invoking `bash G close-out <issue>`
  from the lane worktree with `RUN_ID` and `CLAUDE_CODE_SESSION_ID` scrubbed, instead of spawning
  a third session. `MAX_CLOSEOUT_CONTINUATIONS`, its continuation loop and the progress-token
  delta comparison are deleted (D-3, D-5): the gate's exit code is the verdict, which is already
  the lane's evidence rule everywhere else. One retry, then a stop. The in-flight read still runs
  after the close-out, on its existing two terminals.

- **AC-8** — Terminal vocabulary. `closeout-session-failed`, `closeout-idle`,
  `closeout-continuations-spent` and `closeout-progress-unreadable` are retired;
  `closeout-incomplete` replaces all four and prints the gate's own per-obligation report, so the
  stop still names which obligation is outstanding without the scheduler reading the record.
  `closeout-inflight` and `closeout-inflight-unreadable` are unchanged.

- **AC-9** — `build-lean/SKILL.md` step 9 becomes the one line a manual two-terminal operator
  types (S-5). The jira delta note and the two-tracker-writes rule stay true under it.

- **AC-10** — `run-lean/SKILL.md`'s authors-nothing rule is restated from "the scheduler writes
  nothing" to "the scheduler authors nothing under its own identity", with its stated rationale
  intact, at **no more lines than it has today** — the file sits at its sixty-line cap (D-13).

- **AC-11** — OR-1's discontinuity is flagged where the corpus is actually read:
  `perf-retro/SKILL.md` and `cost-tracking-setup.md` (D-7). `cost-tracking-setup.md`'s step-9
  description is corrected to name the gate, not the session, as the caller.

- **AC-12** — The liveness scenario's close-out leg and its paired non-vacuity arm are re-cut
  against the composed shape: BUILD → REVIEW → a gate close-out that discharges only part of
  milestone 5 → the one retry → the terminal satisfied row. The non-vacuity arm's obligation
  never becomes met, the run stops under `closeout-incomplete`, and no terminal write lands
  (D-11).

- **AC-13** — `orchestrate-lean-selftest.sh`'s close-out cases re-key to the new terminal, the
  new spawn count and the exit-code read; `lean-gate-selftest.sh` gains behavioral cases for
  `close-out` — the three obligations, the skip degradation, teardown-only-after-green, and both
  refusals from AC-1.

- **AC-14** — The PR body reports **measured** net LOC over the whole change, naming what was
  deleted against what was added. "It removes a session" does not discharge the deletion
  doctrine on its own, and D-2 adds surface the ticket did not budget for.

## Out of scope

- Renaming `build-lean` — retired, not deferred: with the close-out no longer a session the block
  owns milestones 1-3 and the name is accurate on its own.
- Any schema change to `cost-log.jsonl` or to `retro-corpus.sh`. D-7 takes the reversible default:
  the row changes shape, no discriminator field is added, and readers date-fence on the timestamp
  and run id every row already carries.
- The manifesto. D-9 found no verbatim restatement of the scheduler's rule there to update.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does milestone 5 survive as a milestone, or get replaced by the close-out command? | Milestone 5 survives. Add a close-out subcommand that performs the writes and then runs the existing milestone-5 assertions; the bare milestone-5 call stays a pure verifier. Nothing re-keys the scheduler's satisfied-token predicate, the all-progression, retro-corpus or lean-reconcile. | user-answered |
| D-2 | Does the close-out command own the three cost obligations #546 added? | Yes. The re-compute, the corpus-row write and the PR-description replacement move into the gate command AND become asserted obligations. This amends the ticket's "Out: the cost block's derivation rule" line, which predates #546. Rationale: deleting the session that performs them without moving them means nobody performs them, since the scheduler authors nothing. | user-answered |
| D-3 | OR-2, first half: the close-out continuation budget and its retry loop | Deleted. It exists only because a model session can exit zero having done nothing; a gate command cannot. The ticket's own D-5 (one retry, then a terminal naming the outstanding obligation) replaces it. | user-answered |
| D-4 | OR-2, second half: milestone 5's fix-budget attempt rows | Kept. They are the general fix-budget machinery shared with milestones 1 through 4, not close-out-specific, and the milestone-5 verifier still runs. Deleting them would fork that machinery for one milestone with no gain. | user-answered |
| D-5 | How the scheduler verifies the close-out | Trust the gate command's exit code; retire the progress-token delta comparison. The verified-not-credited rule exists against a model session ending its turn early, which a gate command cannot do, and a gate exit code is already the lane's evidence rule everywhere else. Side benefit: removes the acknowledged wart where a legitimate second lane run over an already-closed issue is reported as a failure because the satisfied-append is idempotent. | user-answered |
| D-6 | Identity for the PR-description cost-block replacement | The bot wrapper, same as every other close-out write. Mechanically available already — the gate posts the claim marker and the PR marker through that wrapper today, so a PR patch is the same shim and the same identity. Preserves the ticket's binding constraint that no third identity appears on a close-out artifact. | user-answered |
| D-7 | OR-1: cost-corpus comparability once the close-out session disappears | Reversible default. The row changes shape; no schema field is added and retro-corpus code is unchanged in this ticket. The discontinuity note lands in perf-retro's SKILL prose — where the corpus is actually read — as well as the cost-tracking setup doc. Grounding: the timing corpus already excludes milestone 5 as bookkeeping, so only the cost axis moves; #546 AC-8 declined a marker field on this exact log in favor of a structural presence split; rows carry a timestamp and a run id, so a date fence separates the eras. Adding a field later to an append-only log is contained. | user-delegated |
| D-8 | Does anything outside this tree parse the rows OR-2 was protecting? | No. The continuation budget is a local variable in the scheduler with no external reader — the only other mention is frozen prose in a historical verdict record. Milestone-5 attempt rows are read only by the gate's own attempt counter. Milestone-5 satisfied rows are deliberately excluded by the timing corpus, never grepped by lean-reconcile, and reached only generically by doctor's tail read. The portable consumer-pinned boundary script carries zero milestone-5 references. | codebase-derived |
| D-9 | Does the manifesto restate the scheduler's writes-nothing rule? | No. Only run-lean's SKILL carries it, at the authors-nothing bullet. The manifesto speaks to identity and record-authorship generally but contains no verbatim restatement, so the ticket's "any manifesto restatement" clause resolves to no edit. | codebase-derived |
| D-10 | Which external consumer depends on the closing comment, and does a bot author satisfy it? | The open-PRs mode of retro-corpus, whose predicate is any issue comment whose body contains the verdict-record path. It filters on content, never on author, so a bot-written comment satisfies it identically. | codebase-derived |
| D-11 | What re-keys when the continuation arm is deleted? | Its two terminal ids are asserted only by the scheduler's own selftest and the liveness scenario suite; no external document names them. Both suites re-key, and the liveness close-out leg extends per the repo's gate-contract rule. | codebase-derived |
| D-12 | Duplicate scan | Clean. No candidates at or above threshold, over a corpus of five scanned. | codebase-derived |
| D-13 | Prose budget for the rule restatement | run-lean's SKILL sits at exactly its sixty-line cap, so the restatement must be net-neutral or shrinking. build-lean's has headroom. | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Cost-corpus comparability across the lane-shape change | reversible-default-and-flag |
| OR-2 | Whether a templated, gate-written closing comment loses context a model-written one carried | reversible-default-and-flag |

**OR-1** takes its default under AC-11: the row changes shape, and the change is flagged where
the corpus is read rather than encoded as a schema field. **OR-2** takes its default under AC-2:
the template carries the PR link, the verdict-record reference and the cost block — which is what
the current step-9 instruction already specifies and what the sole machine consumer keys on. What
is lost is a model session's freedom to add a sentence of context on an unusual run; if that
turns out to matter, the template grows.
