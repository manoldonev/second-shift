# #514 — the lean scheduler's re-entry admission, composed to a terminal write

#510 gave `orchestrate-lean.sh`'s preflight a second accepting state: a ticket carrying the
claimed label **and** this lane's bot-authored `lean-claimed` marker is admitted as re-entry
rather than rejected at exit 2 (`orchestrate-lean.sh:312-329`, `claim_marker_run_id` at :275).
It is covered only by `orchestrate-lean-selftest.sh` cases (s1)–(s10), which drive a **fake
gate** and a fake session binary — the component checked against itself. `scenario-liveness-selftest.sh`
has lean legs, but no leg has ever invoked the scheduler; its only mention of it is a comment.

This adds the first leg in that file to drive `orchestrate-lean.sh` itself, composing the
admission through to the lane's terminal write. The pre-flight ledger
(`.claude/pipeline-state/514-ledger.md`) is binding input; D-n references below are its rows.

## Acceptance

- **AC-1** — `scenario-liveness-selftest.sh` gains a leg that runs the **real**
  `orchestrate-lean.sh` against a ticket presenting the claimed label plus a bot-authored
  `lean-claimed` marker, and the composed run reaches the lane's terminal write: the scheduler
  exits **0** reporting `done`, having observed a **NEW** `| milestone-5 | satisfied` row in
  the run's progress file (D-1). The chain is real end to end — real scheduler → real
  `lean-gate.sh` → a real `git worktree` on `<prefix><key>` — with only the tracker CLI and the
  session binary faked (D-5, D-6).

- **AC-2** — the same leg asserts the admission was **named as re-entry** and carries the
  marker's run id. A re-entry admission is recorded in no artifact, so the scheduler's stdout
  line plus the run id is the only evidence the arm — rather than some other accepting path —
  is what let the run proceed (OR-2).

- **AC-3** — the session fake advances the run **only** by calling the real gate, never by
  writing a progress row itself (D-6). Hand-written rows are the mirror-harness failure
  CLAUDE.md forbids and would keep the leg green after writer and reader drifted apart.

- **AC-4** — non-vacuity, in-suite: the same leg re-run against a comment trail whose
  `lean-claimed` marker is **not bot-authored** must reject at **exit 2**, spawn nothing, and
  leave **zero** `| milestone-5 | satisfied` rows in its own progress file (D-2a). The arm
  varies the **fixture**, never production — the idiom `(lean-nv)` already uses.

- **AC-5** — non-vacuity, mutation tier: `tools/mutation-catalog.tsv` carries a row flipping
  the real re-entry arm in `orchestrate-lean.sh`, and `tools/mutation-pair-map.tsv` carries the
  row that puts `scenario-liveness-selftest.sh` in that guard's kill set, so the prediction is
  machine-checkable rather than prose (D-2b). The row is **verified in this build** by applying
  its sed verbatim, confirming the new leg reds, and reverting — a catalog row is a prediction
  until someone runs it, and a green `mutation-sweep.sh --mode pr` is not evidence (D-3).

- **AC-6** — the two header lists the file requires be kept current are current (D-10): the
  `Scenarios:` roster names the new leg, and the reach-boundary list records the leg's ceiling —
  a scripted session fake cannot prove a real `claude -p` build session re-enters (OR-1) — under
  **(A) out of reach BY CONTRACT**, because CI is model-free by design.

## Design

Design: none — no user-facing surface; this ticket adds a selftest leg and two mutation-tier
rows.

## Notes on scope

**Not in scope, and why.** The milestone-5 PR-marker **bytes**: leg 1b `(lean-mark)` already
owns them, and D-1 fixes this leg's terminal assertion at the progress row. The marker is
pre-seeded in the comments fixture so `cmd_mark` takes its no-op branch, as leg 1 does (D-7);
no `GH_BOT` stub is needed on that branch. `worktree teardown` is likewise left out: it is not
the terminal write D-1 names, and destroying the leg's own fixture buys nothing.

**#502's abandoned branch is not a design input** (D-9). Its ledger specifies a three-part
conjunction behind a new read-only gate subcommand; #510 shipped a two-part conjunction inline
in `probe_intake`. Cases re-derived against that ledger would assert a contract the code does
not have.

**No production behavior changes.** `orchestrate-lean.sh` and `lean-gate.sh` are not edited, so
no generic mutation ordinals re-key and no baseline rows move (D-10).

## Deviation from the receipt

The ledger's D-2(b) asks for a catalog row "naming this leg as its predicted killer". The sweep
resolves a guard's killers from directory-scoped same-stem pairing plus `mutation-pair-map.tsv`,
and `orchestrate-lean.sh` today resolves only to `orchestrate-lean-selftest.sh` — so without a
pair-map row the prediction would be a prose claim nothing checks, which is the shape this repo
rejects. The row is therefore part of the deliverable, with one stated consequence: a guard
whose kill set includes a slow suite is `deferred-to-nightly` on the PR lane
(`docs/testing.md`), so `orchestrate-lean.sh`'s generic mutants move from PR-time to nightly.
That trade is already accepted for `plan-lint.sh`, `statectl.sh` and `scenario-lib.sh`, each of
which carries a `scenario-liveness-selftest.sh` row for the same reason.
