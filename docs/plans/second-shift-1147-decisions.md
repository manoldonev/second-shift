# Decision record — #1147 The planted bench runs a three-stage blind-prove review arm

Receipt: v4

## Summary

`planted.py run --arm blind-prove` runs three sessions per case-run. Hunt reads the neutral `after` checkout and names candidate breaks. Prove turns them into probe commands, and the harness runs those probes. Intent reads the ticket, the record and the evidence, and writes a verdict in plain's format, which is scored unchanged. The harness rule that amends that verdict is the successor, #1148.

Open regions: OR-1 the flag and file names. OR-2 the blindness scope per stage. OR-3 how the orchestrator calls the probe runner.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The model per stage | Hunt `claude-opus-5-5`, prove `claude-fable-5-1` and intent `claude-opus-5-5`. The judge stays `claude-sonnet-5-5`. The run refuses a prove model in hunt's family. | user-answered | intent |
| D-2 | The cost cap | `$3` per case-run, overridden by `--max-cost`. The summed cost is checked after each stage. Over the cap, the case-run stops, and its status names the stage. | user-answered | intent |
| D-3 | What hunt and prove hand over | Prose plus one fenced block each. Hunt writes ```` ```candidates ```` with `[{id, site, input}]`, where `site` is a `path:line`. Prove writes ```` ```probes ```` with `[{candidate, cmd, files}]`. A missing or unparsable block counts as zero items and is recorded. The whole text passes on verbatim. | user-answered | intent |
| D-4 | Whether prove runs probes while writing them | Yes, only through a wrapper bound to its own case that hides the case id. Only the harness's final probe runs count. | user-answered | intent |
| D-5 | Hunt's tools | Read-only, with plain's read set: Read, Grep, Glob and git. Hunt never runs code. | user-answered | intent |
| D-6 | What intent sees | Plain's checkout, plan file included, with the ticket in the prompt as plain has it. The prompt also carries the record, hunt's full output, prove's prose and the probe blocks. | user-answered | intent |
| D-7 | How probe results reach intent | One block per candidate: id, site, command, verdict, and each side's rc. Each side gets the first 2,000 characters of normalized stdout and stderr, and the block states the cap. The full JSON stays in the record. | user-answered | intent |
| D-8 | A stage that fails | The case-run stops at that stage, and no later stage is spawned. The status names the stage, for example `prove: timeout`, and `tally` counts it unscorable. Zero candidates or zero probes is not a failure, so intent still runs. | user-answered | intent |
| D-9 | The changelog row | Each run writes its own row with `agent=blind-prove` and the stage models, unless `--no-record` is set. The arm refuses to run beside `--arm plain` or `--arm lane`. | user-answered | intent |
| D-10 | Timeouts and the probe budget | `--reviewer-timeout-s` applies to each stage session. Each probe uses the 120 s per side from #1146. At most 8 probes run per case-run, and extras are recorded as dropped. `wall_s` sums stages and probes. | user-answered | intent |
| D-11 | Whether `build()` takes the new arm | No, it raises on an arm outside `ARMS`. The arm builds through #1146's neutral path and plain's `build()` path. run: `grep -n 'if arm not in ARMS' planted.py` → 569 | codebase-derived | fact |
| D-12 | The judge-family guard with these models | It passes. Families come from `claude-([a-z]+)-`, so opus and fable differ from sonnet. run: `grep -n '^FAMILY_RE' bench.py` → `FAMILY_RE = re.compile(r"claude-([a-z]+)-")` | codebase-derived | fact |
| D-13 | The Fable model id | `claude-fable-5-1`, as the repo already names it. run: `grep -rn 'claude-fable-5-1' plugins \| wc -l` → 5 | codebase-derived | fact |
| D-14 | Flag and file names | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-15 | The blindness scope per stage | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-16 | How the orchestrator calls the probe runner | Parked under OR-3 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: Opus/Fable/Opus, Fable/Opus/Fable, or all Opus. The operator chose Opus/Fable/Opus.
- D-2: `$3` per case-run, or no cap. The operator chose `$3`.
- D-3: prose plus a fenced JSON block, or separate files. The operator chose the fenced block.
- D-4: prove runs probes through `probe` only, or prove writes only. The operator chose running through `probe`.
- D-5: read-only like plain, or allowed to run tests. The operator chose read-only.
- D-6: plain's checkout with prompt context, or the lane's checkout. The operator chose plain's checkout.
- D-7: per-candidate blocks with a cap, or the full JSON uncapped. The operator chose capped blocks.
- D-8: stop and mark unscorable, or degrade and continue. The operator chose to stop.
- D-9: a row per run with the arm alone, or no row. The operator chose a row.
- D-10: per stage with the existing flag, or one shared budget. The operator chose per stage.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Flag, prompt-file and selftest names | reversible-default-and-flag |
| OR-2 | The blindness scope per stage | reversible-default-and-flag |
| OR-3 | How the orchestrator calls the probe runner | reversible-default-and-flag |

- OR-1 default: `--hunt-model`, `--prove-model` and `--intent-model`, with D-1's values as defaults. The prompts are `arms/hunt.md`, `arms/prove.md` and `arms/intent.md`, and the selftest is `blind-prove-selftest.sh`. The intake chose them. Reversing them is a rename.
- OR-2 default: all three stages keep the existing check against the corpus root, since the ticket and the record reach intent through its prompt. Hunt and prove get only the `after` checkout and scratch. A read of plain's checkout voids them. The intake chose it. Reversing it is a scanner change.
- OR-3 default: an in-process call to #1146's probe code, on `before` and `after` checkouts built once per case-run. The selftest injects a fake probe function. The intake chose it. Reversing it is a call-site change.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6

AC-1: `run --arm blind-prove` spawns hunt, prove, the probes and intent in order, while `gate()` and `verify` still handle plain and lane only
AC-2: a record holds three session ids, three resolved models, three blindness results, the probe results and one summed cost
AC-3: a hunt or prove session that touches the ticket, the record, the plan file or `case.json` is voided, and an intent session only for `case.json`
AC-4: the text hunt and prove wrote reaches the next stage byte for byte
AC-5: intent's verdict goes through `collect("plain", …)` and `score_review` unchanged
AC-6: `blind-prove-selftest.sh` drives the orchestrator with fake sessions and a fake probe, and checks order, verbatim handoff, blindness voids, a stage failure and the cost cap

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The three stage prompts | decided (D-3) |
| S-2 | The record's per-stage fields | decided (D-2) |
| S-3 | A stopped case-run's status | decided (D-8) |
| S-4 | The probe blocks intent reads | decided (D-7) |
| S-5 | The changelog row for the arm | decided (D-9) |
| S-6 | `run --arm blind-prove` flags | decided (D-14) |
| S-7 | The amended verdict and `compare` | out-of-scope — the successor slice owns the harness rule and `compare`. |
| S-8 | The lane and plain review prompts | out-of-scope — this slice does not touch them. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/probe-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`

## Intake steps

Requirements: the parent #1145 as filed. spec-reviewer found three blockers. The split answered them.

Split: split into #1146, #1147 and #1148 (sequential). This slice's register passed ten decisions, so the operator split it again. This receipt is for #1147.

Explore: done. Read review_one, session_args, collect, blindness_violations and the family guard. The hand prototype ran the three stages on two cases.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC is post-merge. The pre-registered run is #1148's PM-1.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
