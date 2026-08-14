# lean review verdict — #528

verdict=needs-work
run_id: review-528-2
session_id: b9a86b94-8407-4fa0-9708-06f0e228b5a5
rounds: 2
pr: #540
reviewed_head: 84814ae792ec42c5e8afe56bf6d9aa3153b7f82c
reviewed_patch_id: 9a22f54e9aadc9f43aa518456af8c1e10141478f
inherited_patch_id: 0e7aa587092a758b3f06e498749ccc3e831c8f75
inherited_from_verdict: c6b4d5d8becc57bcdd41ef71f2a41184ccc755c8
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #540 (#528), `review-528-2`

Range read: `c6b4d5d..HEAD` (`84814ae`), inheriting the coverage of patch `0e7aa587092a` recorded
by `review-528-1`. Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.

**Verdict: needs-work.** One blocker, and it is round 1's B2 unchanged: `mutation-sweep-pr` is
still red on this exact head. Everything else round 1 raised is genuinely closed — B1, B3, B4, W1,
W2 and W3 all verified below, four of them by kill probe rather than by reading. All three ACs
score satisfied; the red lane is a blocker outside the AC set.

---

## Blockers

### B2 (carried) — `mutation-sweep-pr` still times out, on this head

Not a stale run: run 31801507447, job 94770340622, head `84814ae` — the commit this record names.

| head | mutants | pool started | ended | outcome |
| --- | ---: | --- | --- | --- |
| `0899d16` (round-1 head) | 50 | 11:14:34 | 11:28:04 | timeout |
| `c6b4d5d` (round-1 verdict commit) | 50 | 11:44:12 | 11:57:25 | timeout |
| **`84814ae` (this head)** | **53** | **12:45:14** | **12:58:26** | **timeout** |

Three consecutive runs, none of which emitted a result set. The elapsed column is flat only
because the 15-minute budget is fixed — it measures the ceiling, not progress, so "13m12 vs 13m30"
is not an improvement and must not be read as one. The mutant count went **up**, 50 → 53, because
`tools/fixture-stamp.sh` joined the swept surface.

The round-2 fix is well aimed and is not a no-op: I probed the `kill -0` early bail directly and it
fires — an exited-but-unreaped background child does *not* answer `kill -0` under either bash 5.3
or stock 3.2 on this platform, so the coordinators do bail rather than spinning the ceiling. What
the fix did not do is move CI below the cliff. So round 1's *diagnosis* — that the ceiling spin was
the whole gap — is the part that did not survive contact: closing it recovered less than the ~5 min
that diagnosis predicted, and 3 extra mutants ate whatever was left.

The PR body's "mutation sweep 53 mutants across 4 guards / 0 survivors" is again a local result on
a wider pool. Round 1 recorded exactly why that measurement cannot settle this question — the cost
is wall-clock sleep, which a wide local pool overlaps away and CI's 2 workers serialize. CI is the
authority and it has never produced a result set for this branch.

This is the lane's to close, not the diff's to argue around, and the remedies are the build's call:
raise the job's timeout, shrink the racing cases' ceiling further, skip them under the sweep, or
re-diagnose per-mutant cost from a CI run rather than a local one. **What would settle it is one
green `mutation-sweep-pr` on the reviewed head** — no local sweep substitutes.

---

## Round-1 findings: verified closed

**B1 — the ownership interlock. Closed by construction, not merely tested.** There is now exactly
one expression (`tools/fixture-stamp.sh`), sourced by the reaper and by both producing suites, so
the two sides cannot disagree — and the sanitizer is made insensitive to the trailing-whitespace
difference that caused the disagreement (`tr -cs` squeeze, then strip one leading and one trailing
separator). Ownership gained the third `unknown` answer, and it resolves toward keeping. Probed:
removing the stub-path `unknown` branch reds the suite (`an unresolvable-ownership fixture was
reaped`). The reaper `die`s when the library is absent rather than falling back to age alone.

**B3 — the heal cases. Closed, and the new case is the live one.** Reverting
`heal_progress_run_id` to the pre-#528 fixed `.heal` sibling, scored by case id:

```
(rc3)  PASS   <- still vacuous, as round 1 found (byte-identical writers)
(rc4)  PASS   <- still cannot kill it (the pre-fix `mv` removes the temp on success)
(rc4a) FAIL   <- MUTANT KILLED
suite: [lean-gate-selftest] 1 FAILURE(S)
```

`(rc4a)` — a bystander file planted at the pre-fix fixed path, required to survive a heal — is the
guard, and it is deterministic and single-writer, which is what a race case structurally could not
be here. The spec now says plainly that `(rc3)` cannot observe the collision rather than claiming
it does.

**B4 — the falsified soundness argument. Eliminated rather than re-argued.** `append_satisfied` is
append-only again (atomic `mkdir` claim → re-check inside → `append_line` → release), so
`progress_token`'s "these rows are append-only… cannot go up and back down" is true rather than
standing while false, and the `attempt`-row budget cannot be silently un-charged. The paragraph at
`lean-gate.sh:1495` is corrected to say why. This is the stronger of the two available fixes.

**W1 — default floors. Closed, probed.** Round 1 measured `86400 → 0` passing the whole suite. Now:

```
MIN_AGE_LEGACY 86400 -> 0   suite rc=1  (the default floors did not govern)
MIN_AGE_OWNED    600 -> 0   suite rc=1  (the default floors did not govern)
```

**W2 — closed.** The trap-before-`mktemp` reorder is mirrored into `orchestrate-lean-selftest.sh`,
with the same shellcheck dual-code note.

**W3 — closed.** A fixture root carrying an executable reaper proves the guard fires, with an
absent-tool control. The case's own comment states precisely what it does *not* pin (the `|| true`
token, since that harness is not `set -e`) — which is the right way to record a measured limit.

Round-1 suggestions are all addressed: the dot-field header comment, the stream assertion
(`(rc5a)`), the orchestrator's announcement filter, the `file_mtime` lockstep decision (declined,
with the reasoning recorded), and the `mutation-baseline`/`mutation-catalog` zero-edit conclusion.

---

## Warnings

- **N1 — `clear_satisfied_claims`' comment claims more than the code can.** It reads *"a claim still
  present here was orphaned by a killed writer, never held by a live one"*, and `entry` is not a
  point where that holds: the progress file is issue-keyed, so a second same-issue session running
  `entry` can `rm -rf` a claim a first session is holding *inside* its critical section. The
  duplicate row then needs the sweep to land in a microsecond-wide window and a second writer to
  reach the same milestone before the first appends — so the practical risk is very low, and I did
  not construct the interleaving (the existing stall seam parks a writer *before* the `mkdir`, so
  reproducing it means adding a seam). Stated as read, not measured. But this is the same shape as
  B4 — an in-tree correctness claim the diff does not support — and the cheap fix is to narrow the
  sentence to what is true rather than to change the sweep.
- **N2 — the optional-library fallback and the reaper's `die` path are unexercised.** Both producers
  guard on `[ -r "$STAMP_LIB" ]` and no case takes the false branch; nothing asserts `WORK`'s
  basename carries (or lacks) a stamp segment. Inverting the producers' check is the *safe*
  direction (unstamped names fall to the 24h floor), so this is a warning; inverting the reaper's
  `die` is not, and it is equally unguarded.
- **N3 — the real-path `unknown` fallback is untested.** The stub-path branch is killed by the new
  case (probed above); its non-stub twin — a pid that is alive while `fixture_stamp_for_pid` fails —
  has no case, because the one real-`ps` case uses the suite's own pid, which always resolves.

---

## Verified

- Kill probes, all in an isolated worktree, scored by case id: heal reverted to the fixed `.heal`
  sibling → **(rc4a) FAIL**; `MIN_AGE_LEGACY 86400→0` → **suite red**; `MIN_AGE_OWNED 600→0` →
  **suite red**; stub-path `unknown` branch removed → **suite red**. Baseline copy green (rc=0).
- `tools/reap-lean-fixtures-selftest.sh` green at head, including all four new cases.
- `kill -0` on an exited-unwaited background child fails under bash 5.3.9 and stock 3.2 — the early
  bail is genuinely effective, which is what makes B2 a diagnosis problem rather than a fix that
  was never applied.
- `orchestrate-lean.sh:353` takes `rc` before filtering and the script is `set -uo pipefail` with no
  `-e`, so the `grep -v` returning 1 on an all-filtered capture cannot abort or be misread as the
  gate's status. The comment says so.
- `lint-and-selftests` (ubuntu) and `selftests (macos, bash 3.2)` both **pass** on this head.
- `pr-gates` red is the expected pre-review state (round-1 record reads `verdict=needs-work`); no
  other arm fails.
- Scope-completeness gate: **PASS** — the reviewer widened to the true merge-base on its own and
  found all three ACs implemented.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** — orphans reaped, age-and-ownership guarded, never deletes a live lane's fixture | **satisfied** | The safety half is now one shared expression rather than two agreeing by accident, made whitespace-insensitive, with `unknown` as a third answer that keeps. The reaping half was already right. Guarded: the `unknown` branch and both default floors are kill-probed live. N2/N3 are unexercised branches, not defects. |
| **AC-2** — `append_satisfied` + `heal_progress_run_id` atomic, no blocking waiter | **satisfied** | Both seams ship the mechanism the spec specifies, and both are now guarded by a case that can fail for the defect: `(rc1)` for the append half (round 1), `(rc4a)` for the heal half (probed here). The `append_satisfied` shape is append-only, so it no longer falsifies `progress_token`. N1 is an over-claiming comment on the orphan sweep, carried separately. |
| **AC-3** — resolved config path announced | **satisfied** | Unchanged since round 1, where removal was kill-probed against `(rc5)`/`(rc6)`. Round 2 adds `(rc5a)`, which captures the two streams apart so the stream choice is asserted rather than merged away, and filters the line out of the scheduler's one-line preflight verdict. |
