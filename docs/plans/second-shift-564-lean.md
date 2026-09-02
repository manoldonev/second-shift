# #564 — two concurrent lanes get a verification artifact

Epic #525 hardened the lane machinery for concurrent use, merged all eight children, and was never
run two-lanes-at-once afterwards. This slice does not add hardening and does not change any gate.
It produces the missing artifact: a **pre-registered** exercise, a **recorded** measurement, and a
**re-runnable operator procedure**.

Three files, no executable diff:

| Artifact | Path |
| --- | --- |
| Pre-registered criteria (lands first, before any measurement) | `docs/plans/second-shift-564-preregistration.md` |
| The evidence record | `docs/plans/second-shift-564-evidence.md` |
| The operator procedure | a new section in `docs/testing.md` |

The issue body's first criterion — "aggregate workers ≤ job ceiling" — is **struck as
unimplementable** and replaced; see D-10 and the pre-registration's opening section.

## Acceptance criteria

- AC-1: This slice's first commit lands `docs/plans/second-shift-564-preregistration.md` and
  contains no measurement data. Every measurement in the evidence record is taken on a tree
  descended from that commit.
- AC-2: The pre-registration enumerates exactly four criteria — one per shared surface named in
  D-11 (fixture-reaper ownership under a live neighbor; the shared selftest pass-cache store;
  per-lane wall-clock) plus both lanes reaching a terminal, correct verdict — and records that the
  issue body's "aggregate workers ≤ ceiling" criterion is struck, naming the deletion that voided
  it.
- AC-3: The wall-clock criterion is stated as a rule, not a constant: each lane's oversubscribed-arm
  wall-clock ≤ 1.5 × the slowest single-lane baseline sample at the same per-lane `SELFTEST_JOBS`,
  with that job count derived as `ceil(cores × 0.8)`. The as-shipped arm carries no bar and is
  recorded descriptively.
- AC-4: At least three single-lane baseline samples per measured job level are committed **before**
  any two-lane measurement is taken.
- AC-5: `docs/plans/second-shift-564-evidence.md` records, for every measured run: host load
  samples, per-lane wall and CPU time, per-lane sweep verdict and the progress-record path it was
  written to; plus the tree SHA of each lane, the host core count, and the date.
- AC-6: The evidence record scores every pre-registered criterion PASS or FAIL against the wording
  as committed, records a FAIL as a FAIL without re-scoping it, and cites a filed follow-up issue
  for each FAIL.
- AC-7: The evidence record states in its own words what the exercise does not prove — that it
  covers no scheduler- or session-level contention.
- AC-8: `docs/testing.md` gains a new top-level section, sibling to
  `## Adversarial tier (operator-run, never CI)`, carrying the re-runnable operator procedure and
  naming the changes that void the record.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What the exercise is pre-registered to verify, now that the ceiling named in the issue body is gone | Re-aimed at #566's own untested claim — "the quick check is short enough that the contention class the registry protected against no longer exists" — plus the surviving cross-lane guards enumerated in D-11: fixture-reaper ownership under a live neighbor, the shared selftest pass-cache store, and both lanes reaching a terminal and correct verdict. | user-answered |
| D-2 | Deliverable form: one-shot operator procedure vs. opt-in stress selftest | A documented operator procedure plus one committed evidence record. No new always-on bash and no new opt-in suite — the 2026-08-16 deletion directive the issue body itself cites, and the direction #566 took. | user-answered |
| D-3 | What physically constitutes a "lane" in the exercise | Two concurrent `lean-gate.sh 3` invocations, in two separate worktrees on two real branches. Every surface D-11 names lives inside milestone 3, the gate emits the terminal verdict the fourth criterion scores, and no model billing is incurred, so the procedure is re-runnable. Scope boundary, stated in the record: this proves nothing about scheduler- or session-level contention (OR-1). | user-answered |
| D-4 | How the wall-clock criterion survives measurement noise | A band, not a point. At least 3 single-lane baseline samples on the same tree, committed before any two-lane measurement is taken; the envelope is stated against the SLOW end of the observed range. A bar keyed to one sample measures variance rather than contention. | user-answered |
| D-5 | Where the envelope is set, given two as-shipped lanes are under-subscribed (8 workers on this 10-core host) | Two arms. Arm 1 as-shipped (`SELFTEST_JOBS=4` per lane) is recorded descriptively, with no bar. Arm 2 is oversubscribed and carries the pre-registered envelope, because it is the only arm on which #566's claim can be false. A criterion that cannot fail is a vacuous green. | user-answered |
| D-6 | The envelope rule itself | Two-lane wall-clock ≤ **1.5× the slowest** of the D-4 baseline samples, on arm 2 only. Arm 2 runs at `SELFTEST_JOBS = ceil(cores × 0.8)` per lane — 8 each on this 10-core host, 16 workers ≈ 1.6× subscription — stated as a rule, not a constant, so the procedure ports to another machine. 1.5 sits above the aggregate variance of 63 sub-9s suites and well inside the 2× serialization-equivalence ceiling, so a red reads as contention rather than as noise or as arithmetic. | user-answered |
| D-7 | What closes the ticket — a recorded run, or a green one | A recorded run, green or red. A failed criterion is written down as failed and filed as a follow-up ticket the record cites. Pre-registration is worthless if a red can be re-run or re-scoped away, and the fix for cross-lane contention is a different ticket's work. Nothing here gates a merge. | user-answered |
| D-8 | How the record declares its own staleness | The record stamps tree SHA, machine core count and date. The procedure names the triggers that void it: a change to `tools/run-selftests.sh` job handling, to `tools/reap-lean-fixtures.sh` or `tools/fixture-stamp.sh`, or to `lean-gate.sh`'s milestone-3 block. No automated staleness guard — that mass is what D-2 chose the procedure form to avoid. | user-answered |
| D-9 | Placement of the three artifacts | Pre-registered criteria: a committed file under `docs/plans/`, landed in the slice's FIRST commit before any measurement — shape and ordering precedent `docs/plans/second-shift-643-preregistration.md`, whose AC-1 audit established that a tracker comment is not a commitment. Operator procedure: a new sibling section in `docs/testing.md` following the shape of `## Adversarial tier (operator-run, never CI)` (`docs/testing.md:1799`), which `CLAUDE.md` already routes to as the operator-run recipe home. | codebase-derived |
| D-10 | Whether the issue body's first criterion ("aggregate workers ≤ ceiling") is implementable | No — struck, and D-1 replaces it. #566 deleted `lane-registry.sh`, its advisory wrappers, and #526's job-ceiling calculation; a repo-wide grep confirms nothing in the tree counts live lanes (`lean-gate.sh:1962`, `:4828` and `tools/run-selftests-selftest.sh:191` each cite the deletion; `lane-registry` survives only as a `--ticket-source` label at `lean-gate.sh:461`). | codebase-derived |
| D-11 | Which cross-lane surfaces the exercise must actually contend on | Three, verified live. (a) The stamped `${TMPDIR}` fixture families and `tools/reap-lean-fixtures.sh`, which `run-selftests.sh` runs over the shared directory *before it discovers anything* (`docs/testing.md:227`) — so each lane reaps while its neighbor's fixtures are live, and the pid+`lstart` ownership guard is the only thing between them. (b) The shared `LEAN_SELFTEST_CACHE_DIR` store (`lean-gate.sh:1952-1975`). (c) Sweep workers — `SELFTEST_JOBS`, default 4, no core detection and no lane awareness (`tools/run-selftests.sh:94`). Excluded: `.claude/pipeline-state/` is issue-keyed, so concurrent lanes on different tickets do not collide — #525's own correction table already settled this. | codebase-derived |
| D-12 | Who takes the measurement — the build session, or the operator | The build session. D-9 already fixes the ordering (criteria land in the slice's FIRST commit, before any measurement), and D-3's lane unit is model-free, so nothing about the exercise requires an operator to be present. The concurrent invocations run under `CLAUDE.md`'s documented long-call shape — `nohup <cmd> > <log> 2>&1` under the harness's `run_in_background`, which stays harness-tracked past the ~120s foreground reap. "Operator procedure" in D-2 describes the artifact's re-runnable FORM, not who runs it first. | codebase-derived |
| D-13 | Build model sizing | `opus`. Basis: the diff is prose-only and the receipt leaves nothing architectural open — by shape alone this is a `sonnet` ticket. It is sized up because the deliverable's entire value is a measurement taken correctly, under exactly the concurrency mechanics this repo has repeatedly gotten wrong (contending lanes, signal-killed sweeps, background jobs and stdin), and because the session must score itself against a bar it is forbidden to move once the data is in. A confidently mis-measured pre-registered record is worse than no record. | user-delegated |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Scheduler- and session-level contention — two full `run-lean` sessions, the shape that actually produced #525's measurement | reversible-default-and-flag |
| OR-2 | Whether a red on the oversubscribed arm implicates #566's deletion of the ceiling, or is charged elsewhere | reversible-default-and-flag |

**OR-1** — default: not covered. D-3 scopes the exercise to two `lean-gate.sh 3` invocations, so
the record states the exclusion in its own words (AC-7) rather than letting a reader infer
coverage. Reversing is cheap: the same procedure runs against full sessions later, at model cost,
and nothing here forecloses that.

**OR-2** — default: the record names the failing criterion and files a follow-up ticket; it does
not propose a fix and does not re-open #566. This follows D-7 — the deliverable is the honest
measurement, not the remedy. Reversing is cheap because attribution is a judgment made on the
recorded data, which the record preserves in full.
