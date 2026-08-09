# second-shift #432 — cost attribution fails silently, and the diagnostic blames the collector

Three failures share one symptom (an empty cost block) and one message that names none of them: a
session that never exported telemetry, a fence that predates a rotated metrics file, and a
catch-all that points at the collector. The fix moves the first signal to minute zero, teaches the
reader about rotation, and replaces the guess with a discrimination.

Binding input: `.claude/pipeline-state/432-ledger.md`. Where it and the issue body disagree, the
ledger wins — specifically D-3, which supersedes the issue's suggestion that `entry` gain a
refusal.

## Scope

| File | Change |
| --- | --- |
| `plugins/dev-pipeline/skills/run-lean/lean-gate.sh` | entry-side telemetry probe; the state stamped onto the entry attestation row |
| `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` | rotation-aware file selection; four-way discrimination |
| `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` | telemetry env check; rotation-aware metrics-file check |
| `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` | §3 primary recipe; two new troubleshooting rows |
| `plugins/dev-pipeline/skills/run/state-schema.md` | two new `costBlockApplied` enum rows |
| `plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh` | AC-1/AC-2 guards; the AC-10 hermeticity fix |
| `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` | AC-3/AC-4 guards |
| `plugins/dev-pipeline/skills/run/tools/pipeline-doctor-selftest.sh` | AC-5 guards |
| `tools/mutation-baseline.tsv` | re-baselined generic-survivor ordinals for the two edited guards |

Out of scope by ledger decision: any `entry` refusal (D-3), the classic `run` lane's entry side
(D-10), `run-lean/SKILL.md` (D-14), release artifacts (D-15).

## Acceptance criteria

**AC-1 — `lean-gate.sh entry` reports the session's telemetry state, and never refuses on it.**
`cmd_entry` resolves one of three states before it returns, and prints it on stdout. The state
never changes the return code: a run whose session exports nothing still passes `entry` with
`rc=0`, exactly as today. The message names the consequence — that step 7's cost block will be
empty and cannot be recovered afterwards — so the gap is actionable while the run is still cheap
to restart.

**AC-2 — the state is stamped on the durable entry attestation row.**
The row becomes:

```
<iso> | entry | ledger=<path> | lines=<n> | telemetry=<state> | session=<id>
```

`<state>` ∈ `off` | `nocoll` | `on`. `ENTRY_ROW_MARKER` is unchanged, so a row written by an
earlier gate (no `telemetry=` field) still satisfies `entry_row_present` and
`require_entry_attested`; a mid-flight run never re-reds because the format moved. Idempotence is
unchanged — a second `entry` call does not append a second row, and does not rewrite the first.

**AC-3 — the two probed signals, and what each state means.**

- `off` — `CLAUDE_CODE_ENABLE_TELEMETRY` is unset, empty, `0`, or `false` in the gate's own
  inherited environment. The gate is a bash child of the `claude` process, so its own environment
  *is* the export decision the run never had.
- `nocoll` — the variable is set, and a reachability probe of a **loopback** OTLP endpoint found
  nothing accepting connections.
- `on` — the variable is set and either the probe connected, or the probe was skipped.

Endpoint resolution (OR-1): unset `OTEL_EXPORTER_OTLP_ENDPOINT` falls back to the documented
`127.0.0.1:4317`. A value that parses as `http://<loopback-host>[:<port>]` with no path is
probed. Anything else — `https`, a path-bearing URL, a non-loopback host, an unparseable value —
**skips the reachability half** and reports `on` on the environment variable alone, saying that
reachability was not checked. A warning that fires on a working remote collector would train the
operator to ignore it, and restricting the probe to loopback is also what keeps a `/dev/tcp`
connect from being able to hang the gate.

**AC-4 — `pipeline-cost-block.sh` reads the rotated backups that cover the fence.**
File selection derives a glob from the **resolved** `METRICS_FILE` (so an `OTEL_METRICS_FILE`
override keeps working): `<dir>/<stem>-*.jsonl`. A backup is selected when its **mtime** is at or
after `FENCE_LO`; the live file is always included. mtime, not the filename timestamp, is the key
— the shipped exporter sets `localtime: true`, so a backup named `metrics-2026-08-01T14-30-31.920-size.jsonl`
carries a *local* timestamp while the fence is ISO-8601 `Z`, and comparing them directly is an
off-by-the-tz-offset bug that reads correct only in UTC. When the fence is disabled (empty
bounds — the degraded session-only path) the live file is read alone: there is no window to
cover. Every selected file is passed to the one existing `jq -s` pass; no second read.

**AC-5 — the catch-all diagnostic is replaced by a four-way discrimination.**
Evidence comes from the same single `compute_bucket_rollup` pass, extended with two fields
alongside the `.rowCount` it already emits: in-fence rows for **any** session, and the oldest
scanned row's timestamp. The branch keys on row counts, not on `TOTAL_COST` being zero — which is
what conflates "no rows" with "rows, no money" today.

| Condition | `costBlockApplied` | What the operator is told |
| --- | --- | --- |
| no in-fence rows at all | `skipped-telemetry-off` (existing) | collector down, or nothing exporting |
| in-fence rows present, none for these session ids | `skipped-session-not-exporting` (new) | this session did not export — telemetry was off when it launched |
| the fence starts before the oldest retained row | `skipped-rotated-out` (new) | the covering metrics file has aged out of retention |
| rows for these ids, zero cost | `skipped-zero-datapoints` (existing, narrowed) | rows arrived but carried no cost datapoints |

Distinct values, because the field is the durable record an operator reads back and one value
carrying four remedies is unqueryable. Under `--stateless` `record()` is a no-op, so on the lean
path the discrimination is stderr only — sufficient, because AC-2's row already carries the state
in the progress file, which survives worktree teardown.

**AC-6 — `pipeline-doctor.sh` stops reporting a healthy OTel section for a machine that exports
nothing.** Its OTel section gains a `CLAUDE_CODE_ENABLE_TELEMETRY` check beside the two already
there, and its metrics-file check accepts a non-empty rotated backup as evidence of a live
collector, so a rotated-but-healthy machine stops reading as absent. Both remain warnings, never
failures — cost tracking is opt-in.

**AC-7 — the docs carry the new states and the recipe that prevents them.**
`state-schema.md`'s `costBlockApplied` list and `cost-tracking-setup.md`'s troubleshooting list
each gain the two new values, and `skipped-zero-datapoints` is re-worded to its narrowed meaning.
`cost-tracking-setup.md` §3's **primary** recipe becomes a user-scope `~/.claude/settings.json`
`env` block; direnv stays documented below it as the per-repo alternative. §2 already frames the
collector as "a single global daemon … one instance serves every repo's telemetry, keyed by
`session.id`", so per-repo opt-in was always the mismatched half — and it is what let one terminal
launch an exporting session and another not.

**AC-8 — every new behavior has a paired guard.**
`lean-gate-selftest.sh` covers AC-1/AC-2/AC-3: each of the three states reached under a controlled
environment, the stamped row's shape, the skip-on-non-loopback branch, that `entry` still returns
0 in the `off` state, and that a legacy row with no `telemetry=` field still satisfies
`entry_row_present`. `cost-block-selftest.sh` covers AC-4/AC-5: a backup covering the fence is
read and a backup predating it is not, the fence-disabled path reads the live file alone, and each
of the four discrimination branches records its own value. `pipeline-doctor-selftest.sh` covers
AC-6. Per D-12 no `scenario-liveness-selftest.sh` scenario is added: the change introduces no gate
contract and touches no verdict path — `entry` still passes or refuses on exactly the ledger
predicate.

**AC-9 — the mutation-sweep obligations of the diff are paid in the diff.**
Editing `lean-gate.sh` and `pipeline-cost-block.sh` re-keys their generic survivor ordinals, so
their `tools/mutation-baseline.tsv` rows are re-baselined here. The two `tools/mutation-catalog.tsv`
rows addressing the cost block are anchored on `sed` expressions rather than line numbers; they
are re-checked and re-anchored only if their matched text moves.

**AC-10 — `lean-gate-selftest.sh` is hermetic against an ambient `RUN_ID`.**
Added during the build, after the suite red the run's own milestone-3 gate. `gate()` and
`attest_at()` unset `RUN_ID` per call, but nine cases invoke the gate directly and inherit the
caller's value — and SKILL.md step 2 tells every lean run to export one, so the leak is the
normal state of the shell the sweep runs from. The observable is `(k6)`: milestone 5 calls
`mark`, whose no-op test keys on the resolved run id; the leaked id matches no marker in the
fixture trail, so the case reds with `GH_BOT must point at the bot wrapper` — a message that
reads like a bot-wrapper defect in whatever diff is in flight. Confirmed pre-existing: the same
case fails identically at this branch's base. One suite-level `unset`, mirroring the
`LEAN_RUN_MODEL` guard directly above it and for the same reason.

## Open regions

Both are ledger-parked and ship on their reversible default.

- **OR-1** — endpoint-probe behavior on an unparseable or remote OTLP endpoint. Shipped as AC-3's
  loopback-only probe. Reversing it later is one parser branch.
- **OR-2** — peak memory when the fence spans a rotation. `compute_bucket_rollup` uses `jq -s`,
  which slurps its inputs; AC-4's selection bounds the realistic worst case to two 50 MB files.
  Shipped unchanged, with the ceiling flagged in the script header. If a longer fence ever selects
  more, the contained fix is inside `compute_bucket_rollup` alone — per-file rollup then merge, or
  `--stream` — with no change to any caller or to the emitted shape.

## Verification

`shellcheck` over the changed scripts, `jq empty` over changed JSON, and the full selftest sweep
per `CLAUDE.md`, run without `SKIP_STRESS` and with `env -u CLAUDE_CODE_SESSION_ID`. Diff-scoped
mutation sweep over the two edited guards.
