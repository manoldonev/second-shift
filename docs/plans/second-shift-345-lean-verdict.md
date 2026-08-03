# lean review verdict — #345

verdict=approve
run_id: review-345-2
session_id: 844fcaa1-0a3a-4b30-b209-069fd763ade7
rounds: 2
pr: #361

## Provenance — read this before trusting the record

**This review session also authored two of the commits it reviews** (`452f79f`, `7bc8724`,
`bc42eb4` — the round-1 remediation). The gate's authorship check passes because the progress
file records build session `91d8b183`, which is not this one; that comparison is true but it is
not the whole truth, and the record says so rather than letting the keys imply an independence
that only partly holds. `4ebcd68` / `637fe2d` / `eb80c04` were written by that build session and
are independently reviewed here; the round-2 commits are not.

Why it was done this way: `review-lean` ships *in this PR*, so the command that would have run
an independent review does not exist on any machine until this merges. The operator was told,
chose to proceed, and will override the merge-boundary red. Recorded so the next reader does not
have to reconstruct it.

The specialist fan-out below IS independent — seven fresh contexts, none of which wrote any of
this code. What is not independent is the synthesis and this verdict line.

## Fan-out — round 2, over `origin/main...bc42eb4`

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | Pass | 0 |
| Security | Pass | 0 (3 suppressed, 35–45) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 (1 suppressed, 65) |
| Unit test mutation | Fail → addressed | 1 major (85) |
| Test coverage | **Dark (no output)** | — |

**[Coverage gap] test-coverage-reviewer died after its automatic retry** (turn-budget, no emit
deadline — the known class). Its domain went unreviewed this round. Merge readiness below is
assessed without it. Round 1 covered the same domain over the smaller diff and its one finding
(the `-z "$CLAIM_RUN_ID"` arm) is fixed and now cased at `(N5)`.

**The one finding, fixed in `bc42eb4`.** `PR_HEAD_SHA`'s two guards anchor evidence 5 and had no
case. Dropping either does not make the check fail, it makes it PASS: `git diff --name-only
<commit> ""` errors, `STALE` comes back empty, and the gate prints its freshness tick having
compared nothing — the same fail-open shape as the `verdict=` substring hole this PR closes.
Cases `(Q1)` empty and `(Q2)` sha-shaped-but-unresolvable now pin both.

Suppressed and not acted on: the claim comment now carries a session id into a public comment
(40 — a local transcript identifier, not a credential, and CI reading it is the design);
`$ISSUE` interpolated into state paths (45 — pre-existing, operator-supplied); `PR_HEAD_SHA`
into `git cat-file` (35 — single quoted argv, no metacharacter path); `count_in ''` used to
count all ledger lines (65 — works, reads oddly, pre-existing).

## Verification, run by hand

The INERT lane skips lint/test on a `.sh`/`.md` diff, so this is the substitute:

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- every `*.json` through `jq empty` — clean.
- 62 selftest suites, `-P 4`, **without** `SKIP_STRESS` — exit 0.
- diff-scoped mutation sweep at head — no baseline-absent survivor on any of the four edited
  guards. `lean-gate.sh::detector::2` is now killed by the new milestone-4 cases and its row is
  dropped; `check-lean-chain.sh` needed no re-key despite +146 lines, measured rather than
  assumed.
- merge boundary dry-run with the real PR values: spec, verdict record, claim and authorship all
  tick; freshness refuses the round-1 record, which is the check working.

## AC scoring — 16/16 satisfied

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `check-lean-chain-selftest.sh` (N1) build run_id, (N2) missing run_id, (N3) missing session_id, (H) missing verdict, (N4) distinct-pass |
| AC-2 | satisfied | `lean-gate-selftest.sh` (n1) run_id, (n2) session_id, (n3) build run-id CACHE arm, (j1) missing, (j4) distinct-pass |
| AC-3 | satisfied | (o) — verdict record byte- and mtime-identical across a full `all` sweep, mtime backdated first so an identical-bytes rewrite would still show |
| AC-4 | satisfied | cases A–M retained; suite green |
| AC-5 | satisfied | ordinals re-keyed for every edited guard and re-measured at this head; catalog anchor `LOOKBACK=40` untouched. Advisory macOS run, labeled as the surrounding rows are |
| AC-6 | satisfied | four `Changelog:` trailers on the branch |
| AC-7 | satisfied | (C) no review ledger, (D) review session postdates the commit, (J3) no session_id at all, (A)/(G)/(K) |
| AC-8 | satisfied | `design-sync-selftest.mjs` I-discovery + I-discovery-nv; `check-bounded-exploration-selftest.sh` C1a real tree + C1b planted dir |
| AC-9 | satisfied | (p1)–(p7) |
| AC-10 | satisfied | `scenario-liveness-selftest.sh` legs 1, 4, 5 |
| AC-11 | satisfied | `run-lean/SKILL.md` dispatches no reviewer; `review-lean/SKILL.md` is the REVIEW entry; `docs/testing.md` and manifesto P10 updated |
| AC-12 | satisfied | `run-lean/workflows/` absent from the tree and from both lints' enumeration |
| AC-13 | satisfied | `lean-gate-selftest.sh` (s) and `check-lean-chain-selftest.sh` (P) — a needs-work record whose body quotes the approve token is refused at both readers |
| AC-14 | satisfied | (t1)–(t5) in-gate, (O1)/(O2) at the boundary, leg 5 composed; (Q1)/(Q2) pin the boundary's own inputs fail-closed |
| AC-15 | satisfied | (m4) — an evaluation with `RUN_ID` set creates no build cache; (m2)/(m3) keep the seeding `entry`/`claim` still owe |
| AC-16 | satisfied | (N6) session collision refused despite a distinct run_id, (N7) the pre-existing-claim note passes |

## Why approve

The property the PR exists to establish holds at all three enforcement points, and round 2
closed the two ways it could have been satisfied without being true: a verdict value that could
be forged by prose, and an approve that named no tree. Each new guard has an oracle that fails
for the right reason — (s)/(P) for the substring, (t2)/(O1)/leg 5 for staleness, (m4) for the
cache trap, C1b and I-discovery-nv for the two lints that could have gone vacuous, (Q1)/(Q2) for
the freshness check's own inputs.

Against that: one reviewer domain is unreviewed this round, and the synthesis is not
independent. Neither is hidden above. An operator reading this record should treat it as a
strong artifact review with a named provenance defect, not as the independent verdict the
mechanism is designed to produce — and the first PR that uses `review-lean` for real will be
the one that demonstrates the mechanism end to end.
