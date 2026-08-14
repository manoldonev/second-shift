# second-shift #528 — signal-killed suites orphan their fixtures, and same-issue progress writes are not atomic

Part of #525. Two seams that assume a lane is alone: fixture directories orphaned by
signal-killed suites, and progress-file writes that are idempotent but not atomic.

`#526` (the lane registry) has not landed at the time of this build — its unmerged PR is still
in review. AC-1 therefore takes the first of the ticket's two offered options: stamping
ownership directly into the two `mktemp` templates, rather than depending on unmerged code.

## Acceptance criteria

**AC-1 — orphan fixture directories are reaped, age-and-ownership guarded.**
`lean-gate-selftest.sh` and `orchestrate-lean-selftest.sh` each tag their `mktemp -d -t`
template with `<pid>.<stamp>`, where `<stamp>` is that pid's process start time from
`ps -o lstart=`, sanitized to `[A-Za-z0-9_]` and treated as an opaque string — never parsed,
never reformatted (BSD/GNU render `lstart` differently). A new tool, `tools/reap-lean-fixtures.sh`,
scans `${TMPDIR:-/tmp}` for `leangate.*`/`orchestrate-lean-selftest.*` directories and removes
one only when BOTH hold:

- **Ownership says it is not live**: the embedded pid is gone, or a different process now holds
  a recycled pid (its current `ps -o lstart=` no longer matches the embedded stamp).
- **Age clears a floor**: a short one (10 min) when ownership already answered the safety
  question, a long one (24h) for a name with no ownership signal at all (a legacy pre-fix
  orphan, or anything unparseable) — age is the floor beneath ownership, never a substitute.

`tools/run-selftests.sh` invokes the reaper once, near entry, guarded on the tool's presence
under the sweep's own `--root` — inert for a synthetic fixture tree (run-selftests-selftest.sh),
live for a real sweep. A reap failure is best-effort and never fails the sweep it runs from.

`lean-gate-selftest.sh` also moves its `trap` above its `mktemp` call, closing the second,
smaller window the ticket named: a signal in the five lines between the old order left `WORK`
unprotected even though a trap was about to be installed.

Cross-lane safety: the reaper's ownership check happens immediately before its `rm -rf`, and a
candidate that vanishes mid-walk (removed by a concurrent reaper) is reported as skipped, never
treated as fatal.

**AC-2 — `append_satisfied` and `heal_progress_run_id` are atomic against a concurrent
same-issue writer, introducing no blocking waiter.**

- `heal_progress_run_id` moves from a fixed `$PROGRESS_FILE.heal` sibling to a unique
  `mktemp`-generated temp file before its atomic rename — two concurrent heals no longer stomp
  each other's in-flight write.
- `append_satisfied` moves from a bare read-then-`>>`-append to the same unique-temp +
  atomic-rename shape, with one addition unique-temp + rename alone does not supply: it
  re-verifies the row's absence against the copy it is about to commit, immediately before
  deciding to append. That is what keeps "exactly one satisfied line" true regardless of how
  wide the gap between two writers' checks and writes is — not merely when they happen to land
  close together.

  A persistent per-milestone claim/lock (`mkdir`-based) was tried and rejected: it cannot tell
  "held by a genuinely concurrent same-epoch writer" from "orphaned by a progress file that was
  deleted and recreated since" — a real, anticipated path (the gate already recreates a deleted
  file; `seed_build_progress`-style resets do the same) — and a claim that outlives that reset
  permanently blocks the milestone it names from ever being recorded satisfied again. That is a
  worse failure than the duplicate line it replaces.

  The residual risk this design accepts: a same-issue write can still overwrite a line a
  different `append_attempt`/`append_absent`/`append_started`/`append_concluded` call wrote in
  the narrow instant between this call's own read and its rename. Self-correcting on the next
  `bash G all`, and out of scope for the same reason the ticket scopes AC-2 to same-issue
  re-entry rather than a cross-lane race.

Tested with a genuine, controlled two-writer race (not timing-dependent): a test-only seam,
`LEAN_GATE_TEST_STALL_DIR` (never set in CI or by an operator, alongside the existing
`LEAN_GATE_OBSERVE`/`LEAN_GATE_WAIT_CEILING_SECS`/`RUN_SELFTESTS_DROP_LAST` precedents), pauses
the caller between its absence check and its write so two real background gate processes can be
forced to both observe "absent" before either commits.

**AC-3 — the resolved config path is announced.** `lean-gate.sh` prints `config: <path>` to
stderr once per invocation (via the existing `warn` helper), for every subcommand except
`progress` — whose own contract is a bare, machine-read token
(`orchestrate-lean.sh`'s `progress_token()` captures this script's stdout verbatim and compares
it byte-for-byte across two reads; even a stderr-only announcement would ride along in any
merged capture, so it is skipped there specifically). A config re-point mid-run is now visible
in the output of the next invocation, rather than needing to be inferred from file timestamps
afterward.

## Explicitly out of scope

Unchanged from the ticket: `cost-log.jsonl` atomicity, a marker-file naming contract pending
#511, and a shared fixture harness across ~64 suites. Also out of scope here: retroactively
reaping fixture orphans created by a pre-fix version of the two selftest templates (they carry
no ownership stamp and fall to the reaper's long, unstamped-name floor — a one-time manual
clearing, same as this repo's existing documented recipe, rather than a guarantee this reaper
makes).

## Tests

- `tools/reap-lean-fixtures-selftest.sh` (new): a live-owner fixture kept regardless of age; a
  dead-owner fixture removed once past the short floor and kept below it; a recycled-pid
  (stamp-mismatch) fixture treated as not-owned; an unstamped legacy name governed by the long
  floor alone; unrelated tmp content never touched; an unreadable ownership source degrades to
  not-owned rather than crashing; `--dry-run` reports without removing; a candidate removed by a
  concurrent reaper does not fail the run; the usage floor.
- `lean-gate-selftest.sh` (+7 cases, `(rc1)`-`(rc7)`): two genuinely concurrent
  `append_satisfied` calls for the same milestone leave exactly one satisfied row, and neither
  writer's temp file survives; two genuinely concurrent heals of the same frozen header leave it
  healed exactly once, and neither temp file survives; the config path is announced on an
  ordinary subcommand and re-announced with a NEW path after a mid-run re-point; the
  announcement does not fire on `progress`.
- `run-selftests-selftest.sh`: unaffected by construction — every fixture root it builds lacks
  `tools/reap-lean-fixtures.sh`, so the reaper call is inert there without a dedicated seam.
