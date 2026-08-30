# #663 — an unrunnable-pair red names its failing cases, and lean-gate's coverage comes back

**Issue:** https://github.com/manoldonev/second-shift/issues/663

## Goal

Two things, in the order the ticket sets them, because the second is not diagnosable without the
first:

1. **The diagnostic.** When the mutation sweep declares an `unrunnable pair`, its CI log must name
   the paired suite's failing case(s). Today it prints `tail -40` of the killer log and nothing
   else, so any suite that reports failures as it goes and then keeps running — which is every
   suite in this repo — buries them under the trailing PASSes.
2. **The red.** `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` exits 2 against the
   sweep's unmutated sandbox, so `lean-gate.sh` — 13 of 63 catalog rows, the most covered guard in
   the tree — has been scored by nothing since 2026-08-20. The PR lane defers it as a slow suite;
   the nightly cannot run its killer.

## Measured at `808aa29`, not inherited from the ticket

The ticket's evidence is five nightlies old. Re-derived here:

| claim | at head | source |
| --- | --- | --- |
| red since 2026-08-20 | still red, every night through 2026-08-30 | `gh run list --workflow mutation-sweep.yml` — 08-23…08-30 all `failure` |
| the diagnostic shows only PASS lines | confirmed | run `33303512585`, job `99235849651` (shard 6): 40 `PASS:` lines, then `[lean-gate-selftest] 2 FAILURE(S)` |
| exit 2 | confirmed, and it is a **case count** — the suite's `exit "$FAILS"` convention, so exactly two cases fail | `lean-gate-selftest.sh` tail |
| the suite is green outside the sandbox | confirmed | the same SHA's `selftests` job is green |

The red is a shard-6 failure only; the other nine shards are green, which is why the run's
conclusion is `failure` with the rest of the sweep's evidence intact.

## The diagnostic gap, precisely

`tools/mutation-sweep.sh`'s `save_pre_log()` was `tail -n "$PRE_LOG_LINES" "$KILLER_LOG"`. That
window answers *"did the suite get anywhere at all"* — which is the question #526 added it for,
and it does answer it. It does not answer *"which case"*, and on a 550-case suite the two are
never the same lines. The fix is additive: the snapshot leads with the `$FAIL_PATTERN` matches
(capped, and the overflow counted out loud), then the same tail. The tail arm stays because it is
still the only thing that separates a suite that ran from one reaped at line 1.

Deliberately **not** done: raising `PRE_LOG_LINES`. A bigger blind window is the same defect with
a worse cost — the suite that motivated this would need ~500 lines of log per red to be covered by
one, and the class it belongs to (a suite that fails early and keeps going) has no bound at all.

## Root cause of the exit-2

Recorded in "Findings" below once the named cases are in hand — the ticket's own step order.

## Decision Ledger

No pre-flight ledger was recorded for this ticket; every row below is derived in this lane.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Widen the blind tail, or hoist the matches out of it? | Hoist. A larger window is unbounded in exactly the direction the failure runs; matches-first is bounded by the number of failing cases. Both are printed. | codebase-derived |
| D-2 | Where does the new guard live? | `tools/mutation-sweep-selftest.sh`, as `(g4)`/`(g4c)` — the per-tool behavioral tier, next to `(g2)` which guards the snapshot's survival but not its usefulness. Placed **after** `(g3)`, which reads `(g2)`'s `$OUT`. | codebase-derived |
| D-3 | Baseline or exclude around the lean-gate red? | No — the ticket forbids it, and the guard is the one whose coverage matters most. | user-answered |
| D-4 | How is the exit-2 diagnosed, given no local repro path? | Two oracles, in parallel: a local emulation of the sandbox conditions (detached-worktree cwd + a GNU-`mktemp` shim so `-t` honours `TMPDIR`, which is the Linux behaviour macOS lacks), and a `workflow_dispatch` of the patched sweep on this branch. CI is authoritative; the emulation is what makes iteration cheap. | codebase-derived |

## Acceptance Criteria

- **AC-1** — an `unrunnable pair` red's CI log names the failing case(s) of the paired suite. The
  matches are emitted *in addition to* the tail, both under one framed block, and a suite that
  fails without matching the trigger at all says so rather than printing a bare tail.
- **AC-2** — the root cause of the `lean-gate-selftest.sh` exit-2 is identified with its failing
  cases cited by name in this file, and fixed.
- **AC-3** — a full-mode sweep covering `lean-gate.sh` completes green, with the dispatch run
  cited in this file and in the PR body.
- **AC-4** — a `Changelog:` trailer per repo convention.
- **AC-5** — the AC-1 behaviour is guarded by a selftest case that fails on the pre-fix code: the
  fixture buries its `FAIL:` line under more than `PRE_LOG_LINES` of passing chatter, so a
  tail-only diagnostic cannot show it. The no-match arm is guarded separately, and the tail arm is
  asserted alongside the match arm so that dropping the tail is not scored as an improvement.

AC-5 is not in the issue. It is carried because AC-1 is a behaviour change to a guard, and this
repo's `writing-tests` contract routes one-script behaviour to a per-tool selftest; shipping AC-1
without it would leave the diagnostic exactly as unfalsifiable as the red it exists to explain.

## Findings

*(the named cases, their cause, and the fix — filled in from the first patched sweep)*
