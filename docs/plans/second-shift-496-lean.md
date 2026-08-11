# second-shift #496 — the verdict gate's rc carries a taxonomy, and the scheduler routes on it

`orchestrate-lean.sh` decides a round's next move from `lean-gate.sh 4`'s exit code alone, and
twenty distinct milestone-4 failures all funnel through `fail_milestone 4`, which returns `1` for
every one of them. So a dark review (no record produced) is indistinguishable from a review that
found problems: it spends a round, re-spawns BUILD, and after three of them the operator is told
the gate "exhausted its fix budget" — when no review was produced and no fix was attempted. A P10
authorship refusal — the trust boundary this two-session lane exists to enforce — reaches the
operator as `verdict: needs-work.` and is _retried in a loop_.

Predecessor **#492** landed as PR #501 and is merged; this is written against that shape.
Pre-flight receipt: `.claude/pipeline-state/496-ledger.md` (binding input; D-1…D-16 there).

## Design

### S1 — `lean-gate.sh 4` gains a failure taxonomy

| Code | Meaning                                                                                                                           |
| ---- | --------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | approve; fresh, reconcilable — unchanged                                                                                          |
| `1`  | a usable record that does not approve, **or** whose remedy is a BUILD action                                                      |
| `5`  | **no verdict usable against the current head** — absent, uncommitted, dirty, missing a reconciliation key, stale, or chain-broken |
| `6`  | **integrity refusal** — the record is authored by the build run or the build session (P10)                                        |
| `4`  | fix budget exhausted — unchanged                                                                                                  |
| `2`  | usage, precondition, or environment — unchanged                                                                                   |

`fail_milestone` takes an optional third argument, the class, defaulting to `1`; the twenty
`cmd_4` sites pass theirs explicitly. Control flow and the recording path are untouched (ledger
D-9): a red still appends its `attempt` line and still hard-stops at `4` when the budget is spent.
Only the _return mapping_ changes. **Budget exhaustion outranks the class in both paths** — `4`
keeps its exact current meaning, which is what leaves `(lean-budget)`'s 4th-red hard stop and
`(c1)`'s `…4` intact. It is safe to let a `6` be reported as `4` on the fourth call because the
scheduler never retries a `6` at all (S2), so the misreport this ticket exists to remove is closed
where it actually happens.

Every site, by class (line numbers at this head; the ticket's cite the pre-#492 file, uniformly
141 lines earlier):

| Class | Sites                                                                                                   | Why                                                                                                                         |
| ----- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `1`   | `:2524` verdict≠approve · `:2666` no render receipt · `:2675` receipt stale                             | the remedy is a BUILD action — the receipt arms say "re-run milestone 3 and commit the receipt"                             |
| `5`   | `:2521` `:2530` `:2533` `:2541` `:2592` `:2599` `:2625` `:2634` `:2661` `:2679` `:2705` `:2713` `:2720` | absent, unreconcilable, uncommitted, chain-broken, or stale against this head — every message ends "get a new review round" |
| `6`   | `:2565` `:2570`                                                                                         | the two P10 authorship refusals, and only those                                                                             |
| `2`   | `:2671` `:2701`                                                                                         | "cannot compute patch identity — fetch origin and re-run" is an environment error, not a code fix                           |

### S2 — orchestrator routing, one action per class

The gate rc routes through this table **first** (ledger D-8); #492's advancement/continuation test
applies only _within_ a phase spawn, never across verdict classes.

| Class           | Action                                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `0`             | close out and verify, per #492                                                                                                             |
| `1`             | spend a round, re-spawn BUILD — today's behavior, now correctly scoped                                                                     |
| `5`             | **no BUILD spawn, no round spent.** Exactly one bounded REVIEW re-spawn on its own counter; still `5` ⇒ exit `5` naming the missing record |
| `6`             | **exit `6` immediately**, naming the violation. Never retried                                                                              |
| `4` / `3` / `2` | unchanged                                                                                                                                  |

### S3 — the observe seam

`PRECHECK` already evaluates without recording, but it is an undocumented ambient variable and it
returns `1` before the budget compare, so it _swallows_ `rc=4`. It is promoted to
**`LEAN_GATE_OBSERVE=1`**, documented in the usage block, and it now:

- classifies exactly as the recording path does, returning the S1 taxonomy;
- appends no `attempt`/`absent` line, consumes no budget, writes no `satisfied` line;
- **still reports budget exhaustion as its own value** — `4` when the recording path _would_
  hard-stop, i.e. when the existing count already reaches the budget. Same treatment for
  `block_milestone`'s absent budget, for the same reason.

`verdict_rc` uses it: the last recording call the scheduler made. #492 already made the other two
reads non-recording by construction.

### S4 — hardenings found in the same pass

- `resolve_pr` emits **all** matching open PR numbers, one per line; the **caller** counts and
  refuses on more than one, naming them (ledger D-15 — a `return 1` from inside `PR="$(…)"` is
  invisible).
- A config file that exists but does not parse is a **refusal**, not a silent fall-through to the
  defaults — today `jq`'s failure is swallowed and `tracker.type` resolves to `github`, the arm
  that attests less. Fixed in **both** copies (ledger D-14): `orchestrate-lean.sh` and
  `lean-gate.sh`. The check is made **once, up front, outside any command substitution**, because
  `cfg` is called as `$(cfg …)` where an `exit` kills only the subshell — the same invisibility
  D-15 avoids for `resolve_pr`.

### S5 — the orchestrator's exit taxonomy

`0` approved and closed out · `1` a phase failed, a build phase spent its continuation budget, the
lane's PR was ambiguous, or a close-out left step 9's obligations unmet · `2` usage or preflight
reject · `4` budget exhausted · **`5` no usable verdict record after the bounded REVIEW retry** ·
**`6` integrity refusal**.

## Acceptance Criteria

- **AC-1** — `lean-gate.sh 4` returns the S1 taxonomy, and **every one of the twenty
  `fail_milestone 4` sites maps to a code per S1's site table**. `0` and `4` keep their exact
  current meaning; `5` and `6` avoid `2`/`3`/`4`.
- **AC-2** — `cmd_all` propagates `5`/`6` verbatim, and its cheap pre-pass classifies to the same
  taxonomy rather than collapsing to `1`.
- **AC-3** — Every existing `gate 4` assertion expecting `rc -eq 1` is triaged and re-keyed to its
  class per S1's site table — the P10 identity cases to `6`, the missing/uncommitted/missing-key
  cases to `5`, the unresolvable-base case to `2`. A re-keyed case keeps asserting its original
  message; none is deleted to make the suite pass. The re-key is by **call site**, not by label.
- **AC-4** — The orchestrator routes each S2 class distinctly, and routes the class **before** any
  advancement test. A `5` never spawns BUILD and never spends a review round. A `6` exits without
  any further spawn.
- **AC-5** — The observe seam is documented in `lean-gate.sh`'s usage block, records nothing, and
  still reports budget exhaustion as its own value — asserted by a case that exhausts a milestone's
  budget and then reads it through the observe path, getting the exhaustion signal with no
  `attempt` line written.
- **AC-6** — `verdict_rc` reads through the observe seam, so a full round appends **zero**
  `attempt` lines on the scheduler's behalf, asserted by a scenario driving a complete round.
  (#494 owns whether _absence_ should charge on the recording path; this AC binds only the
  scheduler.)
- **AC-7** — The orchestrator reads no verdict-record content. Its whole input stays gate exit
  codes, `git rev-parse`, read-only `gh` reads, and #492's opaque `progress` token — unchanged and
  still asserted.
- **AC-8** — `resolve_pr` emits all matching PR numbers and its caller refuses on more than one,
  naming them.
- **AC-9** — The config read fails closed on an unparseable file and open on an absent one, in
  **both** copies, each with its own suite case.
- **AC-10** — `run-lean/SKILL.md` states S5's exit taxonomy. The file is at its 60-line cap, so
  this lands substitutively — the existing exit-code list is rewritten, not appended to — and case
  `(n0)`'s cap assertion still passes.

## Guard obligations

Each probe applied verbatim, `cmp`-checked to have changed the file and `bash -n`-checked to still
parse, each redding **exactly one** named case. The **Suite** column is load-bearing (ledger
D-13): the orchestrator suite drives a fixture-fed fake gate, so a mutation of the real gate can
never red an orchestrator-suite case.

| Probe                                                  | Suite                     | Must red                                        |
| ------------------------------------------------------ | ------------------------- | ----------------------------------------------- |
| collapse gate classification `5` → `1`                 | gate                      | the class-5 site-mapping case                   |
| collapse gate classification `6` → `1`                 | gate                      | the P10 site-mapping case                       |
| move the chain break from `5` to `6`                   | gate                      | the case pinning the chain break as recoverable |
| make observe mode record an attempt                    | gate                      | the AC-5 zero-attempt case                      |
| make observe mode swallow budget exhaustion            | gate                      | the AC-5 exhaustion case                        |
| `cmd_all` pre-pass collapses `6` to `1`                | gate                      | the AC-2 case                                   |
| collapse the orchestrator's routing of `5` into `1`    | orchestrator              | the AC-4 dark-review case                       |
| collapse the orchestrator's routing of `6` into `1`    | orchestrator              | the AC-4 integrity case                         |
| let class `6` fall through to a round spend            | orchestrator              | the AC-4 integrity-is-terminal case             |
| remove the class-5 REVIEW retry bound                  | orchestrator              | the AC-4 retry-bound case                       |
| revert `verdict_rc` to the recording call              | orchestrator              | the AC-6 zero-attempt case                      |
| revert the caller's >1-PR refusal                      | orchestrator              | the AC-8 case                                   |
| config parse guard reverted to swallowing `jq` failure | orchestrator **and** gate | the AC-9 case in each suite                     |

## Files

- `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` — S1, S3, S4
- `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` — AC-1/2/3/5/9
- `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` — S2, S4, S5
- `plugins/dev-pipeline/skills/run-lean/orchestrate-lean-selftest.sh` — AC-4/6/7/8/9
- `plugins/dev-pipeline/skills/run-lean/SKILL.md` — AC-10
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — the composed taxonomy leg, and
  the milestone-4 rcs the existing lean legs assert
- `tools/mutation-baseline.tsv` — re-key generic survivor ordinals for the edited guards

## Deviations

- The ticket's AC-3 says "all 22" `rc -eq 1` assertions downstream of a `gate 4` call. **24** are
  measured in `lean-gate-selftest.sh` at this head, plus 8 more milestone-4 rc assertions in
  `scenario-liveness-selftest.sh`, which the ticket's file list did not name. All are triaged; the
  count is descriptive, the obligation ("every one") is what binds. The liveness file is added to
  the file list for the same reason CLAUDE.md gives — a new gate contract extends the liveness
  scenario for every verdict path it touches.
