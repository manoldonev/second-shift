# Bind the lean verdict record to the head it reviewed — #363

## What this closes, precisely

Issue #363 was filed at 14:05 on 2026-08-03; PR #361 (its parent, #345) merged at 15:46 and
its round-2 fix landed a freshness arm in both `lean-gate.sh` milestone 4 and
`scripts/check-lean-chain.sh`. So the issue's problem statement — "a verdict authored against
head A stays green over head B" — is *partly* closed already, and this spec must not pretend
otherwise.

What landed is **inferred** freshness: `git log -1 -- <record>` finds the commit that carries
the verdict record, and nothing but the record itself may differ between that commit and the
head. It binds the record to **where it was committed**.

What #363 asks for is **declared** freshness: the reviewer states which commit it read, and
that statement is compared against the head. It binds the record to **what was reviewed**.

The two are not the same, and neither subsumes the other:

| Failure | inferred arm | declared arm |
| --- | --- | --- |
| review head A, commit record, then push code | reds | reds |
| review head A, code lands at B, *then* commit the record on top of B | **green** | reds |
| record declares a head later than the one it sits on | reds | green |
| branch rebased/force-pushed after approval | **green** (record moves with the rebase) | reds (the declared SHA is orphaned) |

Row 2 is the residual hole this issue names — "it does not bind that record to the commit it
reviewed" — and rows 3–4 are why the inferred arm stays. **Both arms are kept.** Removing
either re-opens a column above.

## Decisions

- **D-1 — the key is `reviewed_head:`, a full 40-char SHA.** It rides the same
  `<key>: <token>` shape `run_id:`/`session_id:` already use, so all three readers' existing
  extractors (`record_key`, `extract_key`, the jq `capture`) work unchanged and no key can
  capture another as a substring.
- **D-2 — the value is derived from git at write time, never passed in.** `cmd_verdict` reads
  `git rev-parse HEAD` in the checkout it runs from. `review-lean` step 3 checks out the PR
  head, so that *is* the reviewed head. An `--reviewed-head` flag was rejected for the reason
  `lean-reconcile.sh` already refuses an operator-named review session: a value the caller
  supplies is a value the caller can get wrong, and here getting it wrong is the failure the
  key exists to catch. A reviewer who runs `verdict` from the wrong checkout gets a red at
  milestone 4, which is fail-closed.
- **D-3 — the comparison predicate is the one already in use**: `git diff --name-only
  <reviewed_head> <head>` must yield nothing but the verdict record path. This takes the
  issue's stated "exact match" *effect* — any push after approval reds, including a docs-only
  or comment-only one — while reusing the established one-path tolerance rather than inventing
  a second freshness semantics for the same file. The record itself must be tolerated because
  the reviewer commits it on top of the head it names.
- **D-4 — a declared head absent from the checkout is a violation, not an environment
  error.** CI checks out with `fetch-depth: 0`, so every commit reachable from the PR head is
  present; a `reviewed_head` that is not means the branch was rewritten under the review
  (rebase or force-push after approval). The messages name that cause and the remedy.
- **D-5 — migration: a record with no `reviewed_head` fails, with no waiver.** In-flight
  key-less records are refused at all three readers, exactly as a missing `run_id` is. The
  remedy exists and is cheap — re-run the review round on a refreshed plugin — which is why
  this is a hard fail rather than the transitional note `check-lean-chain.sh` carries for
  pre-session-id claim comments (that one has *no* available remedy, because the claim comment
  must fall inside the immutable PR-open window). The one open lean PR at the time of writing
  (#365) carries no verdict record yet, so nothing in flight is stranded.
- **D-6 — out of scope, as the issue directs:** the author/reviewer double-role hole (one
  session authoring a verdict and then implementing its fixes) is a distinct contract and
  wants its own issue.

## Acceptance criteria

- **AC-1** (oracle — selftest): `check-lean-chain-selftest.sh` — a verdict naming a head other
  than the PR head fails; a matching one passes; a record missing the key fails for the same
  reason a missing verdict does; a record naming a commit absent from the checkout fails.
- **AC-2** (oracle — selftest): `lean-gate-selftest.sh` — `verdict` writes `reviewed_head`
  resolved from git; milestone 4 refuses a record naming a different head, refuses one missing
  the key, and passes a matching one. The refusal is attributable: the different-head case is
  constructed so the *inferred* arm passes, so only the declared arm can red it.
- **AC-3** (oracle — selftest): `lean-reconcile-selftest.sh` re-anchored to the new key — a
  key-less record is a reconciliation failure, and a record whose declared head is not an
  ancestor of its own commit is a reconciliation failure.
- **AC-4** (oracle — scenario): the lean legs of `scenario-liveness-selftest.sh` compose it —
  the all-green leg's record names the reviewed head, and a leg whose record declares an
  earlier head while sitting on the current one reds. That leg is the composed proof of row 2
  of the table above, and it is green under the inferred arm alone.
- **AC-5** (oracle — mutation sweep): generic-survivor ordinals re-baselined for every edited
  guard in the same diff; affected catalog rows re-anchored.
- **AC-6** (critic — docs): `review-lean/SKILL.md` states the record is head-bound and that
  any push after approval — a rebase included — requires a new review round;
  `run-lean/SKILL.md`'s milestone-4 step says the same from the build side, without breaching
  its 60-line cap.
- **AC-7** (critic): the `scripts/lockstep-manifest.tsv` DROPPED entry for the verdict-record
  key schema names `reviewed_head` and its readers, and the `Changelog:` trailer carries a
  real `Migration:` line for in-flight key-less records.

## AC-5 evidence

The diff-scoped sweep swept all three edited guards and produced survivor sets **identical**
to the committed baseline — 17 ids across `lean-gate.sh` (4), `lean-reconcile.sh` (6) and
`check-lean-chain.sh` (7), diffed id-for-id. Nothing shifted, so there is nothing to
re-baseline; `tools/mutation-catalog.tsv` carries no row anchored to any of the three, so
there is nothing to re-anchor either.

Stated plainly rather than as a coverage claim: at `K_BUDGET=2` the generic operators are
spent on the first two sites per operator per guard, all of which sit above the code this
change adds, so the sweep did **not** grade the new arms. What grades them is behavioral —
`lean-gate-selftest.sh` (u1)–(u4), `check-lean-chain-selftest.sh` (R1)–(R4),
`lean-reconcile-selftest.sh` (L1)–(L3), and the composed `(lean-declared)` leg. The local run
is advisory (macOS, `GITHUB_ACTIONS` unset); the PR lane re-runs it in the canonical
environment.
