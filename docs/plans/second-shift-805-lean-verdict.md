# lean review verdict — #805

verdict=needs-work
run_id: review-805-4
session_id: cbb5948b-615b-452a-9deb-4c2c1d01c69c
rounds: 4
pr: #810
reviewed_head: 94933368a5cf96269ce17b8b9a478c07a4ec3ea6
reviewed_patch_id: 8f00eb89426791d7fedbdcd3f46894af7cbd2620
inherited_patch_id: a5f2c10ef897f410f30ebee625e99521dd6d4ec0
inherited_from_verdict: c732ea63553c0f191017215b1bdcd7004b4ed6cb
fidelity: not-applicable
panel: review-toolkit:security-reviewer,review-toolkit:pipeline-reviewer,review-toolkit:unit-test-mutation-reviewer,review-toolkit:scope-completeness-reviewer
model: unknown
capabilities: pr-marker

# Review round 4 — #805 / PR #810 — needs-work

Reviewed at `94933368`, delta `c732ea63..HEAD` (four commits, nine files), inheriting round 3's
coverage of `9a93630f`. Round 3 APPROVED; these four commits landed after it and voided that
record. They are not a fix round — nothing was outstanding — so this round reads them as new work.

Three blockers, one of them CI-red at this exact head. Everything else below is a warning.

## Blockers

**B-1 — `lint-and-selftests` is RED at this head, and the cause is in the delta.**
`plugins/dev-pipeline/skills/run-lean/orchestrate-lean-selftest.sh:2015-2016` asserts
`grep -c "\tspawn\t"` and `grep -c "\tspawn-end\t"`. GNU grep does not read `\t` as a tab in a BRE;
BSD grep does. So `(bg7f)` passes on `selftests (macos, bash 3.2)` and fails on the ubuntu lane —
job 101717947557, `1 FAILURE(S)`, `orchestrate-lean-selftest.sh (rc=1)`. The failure message dumps
the ledger and it contains exactly one `spawn` row, one `spawn-end` row and `state=staleness-expired`,
so the product is correct and the assertion is what breaks. Measured locally: `/usr/bin/grep -c
"\tspawn\t"` returns 1, and `/usr/bin/grep -c "$(printf '\t')spawn$(printf '\t')"` also returns 1 —
the portable form works on both lanes. That second form is the repo's established idiom
(`lean-gate.sh:1762`, `tools/mutation-sweep.sh:210`, and this same suite's own `:1817`/`:1831`,
which embed a literal tab); `(bg7f)` is the only place in the tree using `"\t"` inside a grep
pattern.

**B-2 — the new catalog row `lean-orchestrate-session-ceiling-lowered` is a measured SURVIVOR.**
Probed at this head in an isolated worktree, suite run directly:

| run | mutation | verdict |
| --- | --- | --- |
| control | none | `all green` (rc 0) |
| mutant | `LEAN_SPAWN_SESSION_CEILING_MS:-7200000` → `:-1800000` (the row's own sed) | `all green` (rc 0) — **SURVIVED** |

Root cause is a duplicated constant: `orchestrate-lean-selftest.sh:423` has `run_tool` export
`LEAN_SPAWN_SESSION_CEILING_MS="${SESSION_CEILING_OVERRIDE:-7200000}"` on **every** case, so
`${LEAN_SPAWN_SESSION_CEILING_MS:-7200000}` in the product is unreachable from the suite and what
`(bg4c)` actually pins is the suite's own copy of the literal. `(bg4c)`'s stated property — "lower
the default back toward the BUILD distribution and it reds" — is therefore false, and so is
b4ef1fc8's "killed by bg4c alone". The regression this round exists to fix is the one left
unguarded. `mutation-sweep-pr` cannot catch it: it reported
`orchestrate-lean.sh deferred-to-nightly — multi-suite union (2 killers)`, `applied=0`.
Same masking applies to `LEAN_SPAWN_STALENESS_SECS` (`run_tool` pins `${STALENESS_SECS_OVERRIDE:-0}`),
so the shipped 300s default is exercised by no case either — see W-8.

**B-3 — the ratified 30-minute ceiling ships as a 2-hour whole-session ceiling, and the PR body
still describes the thing the code repudiates.** #805's `Ratified:` comment names "a 30-minute
silence ceiling as the documented fallback"; AC-3 declares "a bounded silence ceiling (env seam,
default 30 minutes)". `orchestrate-lean.sh:849` ships `SESSION_CEILING_MS=7200000` bounding total
session runtime. The measurement behind it is sound and is the strongest thing in the delta (55
BUILD spawns, median 12.6 min, max 100.5, 11 of 55 past 30 minutes) — but a pre-authorized
narrowing licenses landing LESS, not re-deciding a ratified parameter. Compounding it, PR body
bullet 2 tells the operator "A documented wall-clock silence ceiling now bounds it", which is
verbatim what `orchestrate-lean.sh:833` was written to deny ("THE CEILING IS ON THE WHOLE SESSION,
NOT ON A SILENCE"). An operator ratifying from the PR body cannot see that the bound moved 30 min →
2 h or that its semantics changed. Remedy is disclosure plus an operator decision, not a code
change: name the departure and its measurement in the body, correct the wording, and amend AC-3 (or
narrow the code back).

## Warnings

- **W-1 (carried from round 3, unfixed).** `orchestrate-lean.sh:688-691`, the `D-18` block above
  `probe_spawn`, still claims "The listing is checked HERE, before a run costs anything… A refusal
  at preflight is the cheap version of discovering it three unreadable polls into a live session."
  `probe_spawn`'s body is `command -v` + `[ -x ]`. AC-11 lists that validation among the
  narrowing's removals. Round 3 scored this a warning and it is unchanged at this head.
- **W-2** (`unit-test-mutation-reviewer`, conf 88). The `spawn-settings-unwritable` fail-closed
  guard (`orchestrate-lean.sh:1128`, plus the `|| return 1` inside `spawn_settings`) has no case at
  all. Its own message states the stakes — dispatching without the block "would spawn a session
  able to mint its own attendance". A mutant dropping either half survives the suite.
- **W-3** (conf 85). The two new `SPAWN_STATE="spawn-unreadable"` assignments before the mid-poll
  `terminal spawn-unreadable` calls exist so the closing ledger row names the refusal rather than
  `unknown`. No case greps the ledger for `state=spawn-unreadable`, though `(bg7f)` does exactly
  that for `staleness-expired`.
- **W-4** (conf 82). `spawn_end_note`'s `rm -f "$SPAWN_SETTINGS_FILE"` — the credential-window
  narrowing for `OTEL_EXPORTER_OTLP_HEADERS` — is asserted nowhere. Mitigated: `PROBE_DIR` is
  `mktemp -d` 0700 and the EXIT trap removes it regardless, so this narrows a window rather than
  being the boundary.
- **W-5.** The other new row, `lean-orchestrate-poll-staleness-failopen`, was probed at this head
  and **hangs rather than failing**: with `st_unread` pinned at 0 the tolerance is never reached,
  the loop spins on `working` at `LEAN_SPAWN_POLL_SECS=0`, and the run was still alive after 5×
  the control's runtime when it was killed. `(bg7d)` does not return a verdict on it. A timeout is
  a weaker signature than the row's description ("killed by bg7d, with bg7e holding the other
  side") claims.
- **W-6** (`scope-completeness-reviewer`, conf 90). Commit 94933368 lands #811 OR-5 scope —
  `SECOND_SHIFT_CONFIG` forwarding, `docs/consumer-eval.md`, cases in both suites — and the PR body
  never mentions `SECOND_SHIFT_CONFIG`, #811, or `consumer-eval.md`, including in the "Two things
  the receipt did not cover" section that discloses the analogous D-27 telemetry carry. The code is
  guarded ((d4), (d4a), and the composed `lean-reentry` leg); the disclosure is what is missing, on
  the surface the operator ratifies from.
- **W-7.** The PR body is stale for this round throughout: "124 pass / 0 fail" (the suite now
  carries the round-4 cases and is red on ubuntu), "36s"/"86s" against a committed table now
  reading 58s/106s, and "317 sites, 165 rows" against a measured `check-gate-buckets.sh` green of
  **319 sites / 166 rows** at this head. Nothing here is wrong about the code; it all describes an
  earlier head.
- **W-8.** `run_tool` pins `LEAN_SPAWN_STALENESS_SECS=${STALENESS_SECS_OVERRIDE:-0}` on every case,
  so the shipped 300s default is never exercised — `(bg7c)` drives 99999. Same duplicated-constant
  class as B-2, without a catalog row claiming otherwise.

## Verified green at this head, by me

- `bash scripts/check-gate-buckets.sh` — 319 enumerated refusal sites across 5 files, all bucketed
  by 166 register rows. The new `spawn-settings-unwritable` row is required by the new terminal
  site, not a discretionary edit.
- `orchestrate-lean-selftest.sh` run directly on macOS — `all green`. The ubiquitous local pass is
  a grep-implementation artifact (B-1), not evidence the suite is sound on both lanes.
- The read-first/sleep-last restructure: every arm sleeps exactly once per iteration — the two
  `continue` paths carry their own `sleep "$POLL_SECS"` and the recognised-state path falls to the
  bottom-of-loop sleep. No path spins, none sleeps twice, and `elapsed_ms` is computed before every
  branch, so the ceiling stays reachable. Independently traced by `unit-test-mutation-reviewer`.
- `SPAWN_ENDED` vs `SPAWN_CLOSED`: every run-ending path reaches `spawn_cleanup → spawn_close →
  spawn_end_note`, both flags are idempotent, and the one window where a settings file outlives its
  note — the no-id refusal, where `SPAWN_ENDED` is still 1 — is covered by the EXIT trap's
  `rm -rf "$PROBE_DIR"`. No row can be opened and left unclosed, and none is closed twice.
- `security-reviewer` returned approve with zero findings: the settings file strictly improves on
  the argv form it replaces (`ps auxww` / `/proc/<pid>/cmdline` are world-readable; a 0700
  `mktemp -d` is not), and launcher and payload are the same trust domain.

## Merge-boundary refusals, recorded not blocking

`pr-gates` is red only because round 3's verdict record names patch `a5f2c10ef897` while the branch
now hashes to `8f00eb894267`. That is this round's record landing, not a finding.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | divergent-inert | `--bg` dispatch, id read and state return are present and unchanged. The `--settings` env block carries one key AC-1 does not enumerate, `SECOND_SHIFT_CONFIG`. measured: `(d4a)` drives a launcher with no `SECOND_SHIFT_CONFIG` and asserts no key is written, so on every run AC-1 describes the block is exactly AC-1's enumeration; `(d4)` and the composed `lean-reentry` leg cover the forwarding arm. The re-added `env -u RUN_ID` scrubs a variable the AC lists as deleted and is documented as a belt. follow-up: #811 |
| AC-2 | satisfied | `session_row` polls `agents --json --all` keyed on the returned `sessionId`; `done` proceeds, `failed`/`stopped`/`blocked` reach the collapsed role terminal; `blocked` still has no slug; cadence is `LEAN_SPAWN_POLL_SECS`, default 30 |
| AC-3 | unsatisfied | AC-3 declares a bounded SILENCE ceiling, env seam, default 30 minutes. `orchestrate-lean.sh:849` ships `SESSION_CEILING_MS=7200000` bounding TOTAL session runtime, renamed `LEAN_SPAWN_SESSION_CEILING_MS`. The measurement behind the change is sound and recorded in-file, but the bound and its semantics both moved and the ratified parameter was re-decided rather than narrowed. See B-3 |
| AC-4 | satisfied | three consecutive unreadable or unmodelled listings reach `terminal spawn-unreadable 1` naming the id; the counter resets only in the recognised arms |
| AC-5 | divergent-inert | AC-5's declared outcome — exit 7 as a LIVE abort, the premise re-asked during the session, `claude stop` then `terminal staleness-expired 7` with the revised partial-operation message — holds. measured: the re-ask moved off every tick onto `STALENESS_SECS` (default 300), so detection latency inside the session moves from ≤POLL_SECS to ≤STALENESS_SECS and nothing else does; the cost measured in-file is ~25 tracker round trips plus ~25 base fetches per median BUILD collapsing to ~2. `(bg7c)` drives the throttle. The added fail-closed `staleness-unreadable` arm converts a silent fall-through into a refusal and weakens nothing AC-5 declares. follow-up: #805 |
| AC-6 | satisfied | `trap 'spawn_cleanup; exit 130' INT` / `exit 143` TERM stop the dispatched id; unchanged this round (the uncased trap is a round-1 carried warning) |
| AC-7 | satisfied | transcript created at spawn and closed from the funnel; one control line at spawn naming the id and `claude attach`, one per transition, one at spawn-end; `session_reach` keeps the attach sentence off the one arm where the scheduler already stopped the session |
| AC-8 | satisfied | `spawn` row carries `id=`, `spawn-end` carries `state=`; the close moved into `spawn_end_note` so the three mid-poll terminals no longer leave the row open. The ledger content is correct at this head — the CI failure dump in B-1 is itself the evidence — but the guard for it is broken on the ubuntu lane |
| AC-9 | divergent-inert | the collapsed `build-session-failed`/`review-session-failed` row, the `staleness-expired` re-anchor and `spawn-unreadable`'s own row are all present and `blocked` still has none. measured: `bash scripts/check-gate-buckets.sh` green at this head, 319 sites / 166 rows; the one row AC-9 does not enumerate, `spawn-settings-unwritable`, is compelled by the new refusal site the same check would otherwise red on. follow-up: #805 |
| AC-10 | unsatisfied | the suite drives the transport and the new cases are real, but it is RED on the ubuntu CI lane at this head (B-1), and AC-10's catalog obligation is not met: `lean-orchestrate-session-ceiling-lowered` is a probe-measured survivor with no killer in any case (B-2), and `lean-orchestrate-poll-staleness-failopen` is signalled by a hang rather than a case verdict (W-5) |
| AC-11 | unsatisfied | AC-11's deliverable is the negative "measured at this head". Measured at `94933368`: executable-only **+569 / −99** against the 389/92 the spec and body both carry, and raw **+1193 / −187**, net **+1006**, against the body's +805/−178 / +627. The sign and the conclusion survive; the magnitude the operator's ratification call turns on does not, and this is the second consecutive round the figure went stale on the round's own commits. Commands: `git diff --numstat origin/main -- . ':!docs/plans/'` and the `-U0` awk split the body already names |
| AC-12 | satisfied | the `-p` prose in `orchestrate-lean.sh`, the three lean `SKILL.md` files, the two `lean-gate.sh` header claims and `operator-override.sh`'s `headless` contract all follow the code; `build-lean/SKILL.md` gained the session-ceiling sentence this round. The `probe_spawn` D-18 block (W-1) is a claim about a removed mechanism rather than a surviving `-p` reference, and is carried from round 3 at its round-3 severity |
