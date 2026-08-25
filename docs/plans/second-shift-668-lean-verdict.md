# lean review verdict — #668

verdict=needs-work
run_id: review-668-1
session_id: 6588c2b2-e647-48b6-96c8-94e476fbafc6
rounds: 1
pr: #685
reviewed_head: 1effbb3f86f6a0d7182a65a017056da3236ef39c
reviewed_patch_id: fcf5f143d970240fcfb93000a5bed05a6d6c7795
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR 685 (#668)

Range read: `295f4ea..1effbb3` — FULL branch diff (root round, nothing to inherit).
Panel: 6 selected, 6 returned, **none dark**, zero blockers from the panel. The one blocker
below is extrinsic to the diff and was found in CI; both of the panel's suppressed
sub-80 notes independently name it and the AC-3 record-location warning.

## Verdict: needs-work — 1 blocker, 2 warnings

The change itself is correct, minimal and genuinely covered. It cannot merge as it stands:
`pr-gates` is red.

## Blocker

**B1 — `pr-gates` fails: guard/test shell mass grew +46 with no `Guard-mass:` trailer.**
[CI run 32879544935, job 97905459585] Reproduced locally at the reviewed head:

```
$ bash scripts/check-guard-budget.sh origin/main
[guard-budget] ✗ guard/test shell mass grew by 46 lines with no reason recorded:
                 base 51793 (295f4ea), HEAD 51839.
[guard-budget]   Guard-mass: +46 <reason>
```

The branch carries both required `Changelog:` trailers, and the frozen-files and changelog-trailer
steps pass; only this one fails. Because the job's shell is `-e`, the failure **short-circuits the
two steps after it** — *pipeline chain reconciliation* and *lean chain reconciliation* never ran on
this head, so their result is unknown rather than green.

Remedy (one empty commit, no code change):

```
git commit --allow-empty -m "chore(dev-pipeline): record the guard-mass for #668" \
  -m "Guard-mass: +46 three behavioural fixture cases (ad6-ad8) pinning both forms of milestone 3's terminal line, plus the counted-suffix branch in cmd_3." \
  -m "Changelog: none."
```

Note for the next round: a trailer-only/empty commit changes no `+`/`-` line, so the branch's patch
identity is unchanged. That does not void this record — but it also means `G delta` has nothing new
to hand the next round, which will re-read the full branch diff (the #637/PR 677 shape).

## Warnings

**W1 — the spec's AC-3 asks for the explicit slow-suite result "recorded here"; the spec doc
records nothing.** `docs/plans/second-shift-668-lean.md` AC-3 requires the deferred suite to "be
run explicitly and its result recorded here". The result table lives in the PR body instead, which
does become the squash commit message, so the substance is met — but the committed spec, the
artifact the pipeline treats as the definition of done, carries no run result. Scored satisfied on
the substance; flagged so the next spec of this shape says where the record goes.

**W2 — `cmd_3`'s per-invocation `LANE_ADVISORY_COUNT=0` reset is unreachable, and the PR's design
note over-claims it.** The note says the reset means "`all` — which runs the milestones in one
process — cannot carry a count in". `cmd_all` runs `run_milestone` once per milestone 1..5, so a
second in-process `cmd_3` has no caller, and the file-scope `LANE_ADVISORY_COUNT=0` already
initialises it. Measured: deleting the two reset lines and re-running the suite in an isolated
worktree at this head → **all green** (a surviving mutant). This is defensive-by-construction code,
not a coverage gap: keep the line, drop the claim that it is guarding a reachable path. No test is
owed for it.

## What was verified independently (not read on trust)

| Check | Result |
| --- | --- |
| `lean-gate-selftest.sh` at the reviewed head | **all green**, 514 passes (rc=0) |
| the same suite with `lean-gate.sh` reverted to `main` (mutation confirmed applied: 0 occurrences of `LANE_ADVISORY_COUNT`, −15 lines) | **2 FAILURE(S) — exactly (ad6) and (ad7)**; (ad8) passes on both sides, so it is a control, not a duplicate |
| `SKIP_STRESS=1 tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` at the head | **75 scored, 75 run, 0 failed** |
| `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files | clean |
| `bash G delta 668` from both the installed 11.0.0 gate and the branch's own copy | identical FULL-range answer |
| every `pass_milestone 3` site | exactly one (`:3974`) — no second path prints an unqualified green |
| every `lane_advisory` call site | exactly two (`:3867` fixed-key loop, `:3955` extraLanes loop), both in `cmd_3`'s own body — plain `for` loops, no pipeline or `( … )` subshell, so the increments reach the caller |
| the durable row | `pass_milestone` → `append_satisfied`, which writes `\| milestone-3 \| satisfied` with **no reason field** — the counted string reaches stdout only, so no progress-row or reconciliation surface moves |
| consumers of the terminal line | repo-wide `grep '✓ milestone'` outside the suite → only the gate's own two `say` sites; `orchestrate-lean.sh` reads rc and progress records, never this text |
| the `Changelog: none.` on the spec commit | harmless here — `extract_trailers` ends a block at the un-indented `Co-Authored-By:`, and `render_bullet` drops a whole-block `none.`, so the squash renders the substantive trailer only |

## AC scoring (against the committed spec, every AC every round)

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 (oracle) — terminal line names the count when nonzero; fixture reds on the unconditional form | **satisfied** | `(ad6)` pins `green gate (1 advisory)` with `grep -qFx`, `(ad7)` pins `(2 advisory)` **and** asserts 2 durable advisory rows, so a hardcoded suffix cannot pass it. Both die on the reverted gate, reproduced here. |
| AC-2 (critic) — rc, verdict routing, progress-row text and every consumer unchanged; zero-advisory text byte-identical | **satisfied** | `(ad8)`'s `grep -qFx` is the byte-identity assertion, and `-x` is load-bearing exactly as its comment says (`green gate (0 advisory)` would pass a substring match). The suffix is appended only under `-gt 0`; rows carry no reason; no consumer greps the line. |
| AC-3 (oracle) — sweep green, `Changelog:` trailer, deferred suite run explicitly and recorded | **satisfied** (see W1 on where it is recorded) | Full sweep re-run here: 75/75, 0 failed. Explicit `lean-gate-selftest.sh` run: green. `Changelog:` trailer present on the fix commit and enforced green by CI. |

Design fidelity: **not-applicable** — the spec has no `## Design` section and no render receipt;
no changed path is in a web-component surface, so `a11y` and the design-fidelity dimension were
not routed (config declares no `stageParams.webComponentGlobs`, so the shipped
`apps/web/**/*.{tsx,jsx}` default applied).

## Strengths

- The counter is incremented inside `lane_advisory` itself rather than at the two call sites, so
  the two shapes (fixed keys, extraLanes) cannot drift apart — there is one increment site by
  construction, which is why the untested extraLanes shape is not a hole.
- `(ad8)` is a real control, not a second copy of `(ad6)`: it passes on both sides of the mutation
  by design, and the PR says so rather than presenting it as a third kill.
- The decision not to add a `tools/mutation-catalog.tsv` row is correct and correctly reasoned:
  this suite is on `tools/selftest-suite-timings.tsv`, so `mutation-sweep-pr` defers it and a
  catalog row would pass in seconds having graded nothing.
- Counting rather than re-deriving from the progress file is the right call for the stated reason —
  that file accumulates across fix rounds, so a derived number would qualify the wrong run.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Scope Completeness | Pass | 0 | — |

Not routed (not dark): `a11y-reviewer` + design-fidelity — no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`); `unit-test-mutation-reviewer` — no
co-located unit spec surface in this repo, and an executed mutation probe was run in-session
instead; `db-reviewer` / `pipeline-reviewer` — no DB or queue surface.
