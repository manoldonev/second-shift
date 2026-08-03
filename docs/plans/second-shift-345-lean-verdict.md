# lean review verdict — #345

verdict=approve
run_id: review-345-1
session_id: 4a0531d3-3195-490d-af80-cbf460448ca8
rounds: 1
pr: #361

Reviewed via `review-lead` fan-out (6 reviewers: security, performance, complexity,
maintainability, test-coverage, scope-completeness — all `approve`, 0 findings, 0 dark),
plus an independent read of the full diff and a by-hand run of the repo's verification.

## Verification (run by hand — the INERT lane skips lint/test on a .sh/.md diff)

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- every `*.json` through `jq empty` — clean.
- full selftest sweep, **without** `SKIP_STRESS`, 62 suites, `-P 4` — exit 0 (4m06s).

## AC scoring — 12/12 satisfied

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `check-lean-chain-selftest.sh` (N1) build run_id, (N2) missing run_id, (N3) missing session_id, (H) missing verdict, (N4) distinct-pass |
| AC-2 | satisfied | `lean-gate-selftest.sh` (n1) run_id, (n2) session_id, (n3) build run-id CACHE arm, (j1) missing, (j4) distinct-pass |
| AC-3 | satisfied | (o) — verdict record byte- and mtime-identical across a full `all` sweep, mtime backdated first so an identical-bytes rewrite would still show |
| AC-4 | satisfied | cases A-M retained unchanged; suite green |
| AC-5 | satisfied | `lean-gate.sh` detector::1→::2, `lean-reconcile.sh` +detector::1, `check-bounded-exploration.sh` fail-open::1→::2 with logic::1 dropped, `check-lean-chain.sh` unchanged; catalog anchor `LOOKBACK=40` untouched. Ordinals are from a local advisory macOS sweep, self-labeled "confirm at the first nightly" — consistent with the existing lean rows |
| AC-6 | satisfied | two `Changelog:` trailers on the branch |
| AC-7 | satisfied | (C) no review ledger, (D) review session postdates the commit, (A)/(G)/(J); the build-ledger `lean-review` row requirement is gone from `write_ledger` |
| AC-8 | satisfied | `design-sync-selftest.mjs` I-discovery (31/31); `check-bounded-exploration-selftest.sh` C1a real tree + C1b planted unlisted dir in a $TMP mirror (32/32) |
| AC-9 | satisfied | (p1) build session, (p1b) refusal writes nothing, (p2) no identity provisioned, (p3) identity equals build's, (p4) unverifiable build session, (p5) both keys + body, (p6) role-keyed caches, (p7) composes with milestone 4 |
| AC-10 | satisfied | `scenario-liveness-selftest.sh` leg 1 (review-authored all-green) + leg 4 (reds on build run_id and on build session_id); 50/50 |
| AC-11 | satisfied | `run-lean/SKILL.md` dispatches no reviewer and states the verdict arrives from outside; `review-lean/SKILL.md` is the REVIEW entry; `docs/testing.md` two-directory note updated; manifesto P10 no longer owed-and-pending |
| AC-12 | satisfied | `run-lean/workflows/` absent from the tree and reduced to one entry in both lints' enumeration |

## Findings

No blockers. Two warnings and two nits, all non-blocking.

**W1 — a review session running a build-role subcommand clobbers the build run-id cache**
(`lean-gate.sh`, the RUN_ID persistence section; confidence 90). The `verdict` path resolves
without persisting, but every other subcommand still calls `resolve_cached_id "$RUN_ID_CACHE" 1`,
which writes `$RUN_ID` into the BUILD cache. `review-lean/SKILL.md` step 1 mandates exporting a
review `RUN_ID` before anything else, so a review session that runs `bash G 4 <issue>` — a
natural verification step, forbidden nowhere — poisons the build cache and then permanently reds
milestone 4 against a valid, review-authored record. Reproduced:

    1. milestone 4, clean env, review-authored record   rc=0   build cache: r-build-1
    2. review session runs `G 4` with RUN_ID exported   rc=1   build cache: review-7-1
    3. milestone 4 again, clean env, SAME record        rc=1   (permanent)

Fails CLOSED — never a false approve — and the merge boundary is unaffected because it reads the
claim comment rather than the cache, while the progress-file header still holds the true build id.
So nothing irrecoverable is lost; it is a new operational trap rather than a weakened gate.
Cheapest fix: persist to `RUN_ID_CACHE` only for the build-role subcommands (`entry`, `claim`).

**W2 — the new AUTHORSHIP header overclaims the session-id guarantee** (`lean-gate.sh` header;
confidence 80). It reads "This one is not merely tamper-evident: the session id is
harness-assigned, not agent-chosen." `CLAUDE_CODE_SESSION_ID` is an ordinary environment variable
the invoker can set, so the `cmd_verdict` session check is defeatable in-shell. Both sibling files
in this same PR state the altitude correctly — `lean-reconcile.sh` ("strong tamper-evidence, not
cryptographic proof ... forge a second session's hook ledger") and `check-lean-chain.sh` ("HONEST
ALTITUDE: like its sibling, this is tamper-EVIDENCE, not proof"). The distinction being drawn is
real and worth keeping (RUN_ID is agent-chosen; the session id is merely agent-overridable); the
"not merely tamper-evident" clause is the part that overreaches.

**N1** — `--pr` is checked only for non-emptiness while `--verdict` and `--rounds` are validated,
and its value is echoed into the committed record. Non-escalating: all three readers take
`head -n1`, so an injected key loses to the authentic one. Inconsistent with the file's
fail-closed posture.

**N2** — `--rounds 0` passes the `''|*[!0-9]*` guard despite the message saying "positive integer".

## Why approve

The separation holds at all three enforcement points (in-gate milestone 4, the merge boundary,
and the operator reconcile), and each is backed by an oracle that fails for the right reason —
(o) for the read-only property, (n3) for the cache arm a plausible implementation omits, and C1b
for the lint that could otherwise have gone silently vacuous on the directory removal. W1 and W2
are worth a follow-up commit; neither weakens the property this PR exists to establish.
