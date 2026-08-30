# lean review verdict — #670

verdict=needs-work
run_id: review-670-1
session_id: 1dc65a2e-fbfc-49ba-b8b8-abc85525890c
rounds: 1
pr: #728
reviewed_head: 51ba24efecb781f2aaad6670e814b5964f6f52be
reviewed_patch_id: e6c645925724127402db1d9c00c8441c42ad5d4d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1. Full branch diff `ff3f6f8..51ba24e` (root round — nothing to inherit).

The defect this ticket names is really fixed: `cmd_mark` now resolves through
`resolve_open_pr`, and the mutant that restores its own `--state open` list is killed by
three new cases plus the composed leg. Two blockers, both about what the new *evidence*
claims rather than what the code does — and both are the same species as the defect
#670 exists to repair: an assertion that certifies something it never crosses.

## Findings

| # | Sev | Site | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `scenario-liveness-selftest.sh:2275-2277` | The leg's explicit non-vacuity assertion passes in exactly the world it names as the failure. |
| B2 | blocker | `docs/plans/second-shift-670-lean.md` AC-4 | The AC's own oracle returns **1** at head, not the zero it states. |
| W1 | warning | `lean-gate-selftest.sh:5520-5523` | `(pm7c)` — the case AC-1 points at for "posts nothing to a merged PR" — cannot fail. |
| W2 | warning | `docs/plans/second-shift-670-lean.md` AC-7 | Names `tools/mutation-catalog-selftest.sh`, which does not exist in the tree. |
| N1 | note | commit trailer | `Guard-mass:` says "the four lean-gate cases AC-1 mandates" and lists three. |
| N2 | note | `lean-gate.sh:2817`, `:2806` | Two advisory message strings are unasserted (unit-test-mutation, conf 82/80). |

### B1 — the composed leg's non-vacuity assertion cannot fail (blocker)

`scenario-liveness-selftest.sh:2271-2277` asserts, in its own words, that "the fake must
actually have been asked for open PRs and actually have answered 'none'. Without this the
leg would still pass with the pre-#670 gate if the fake had quietly served the merged
record to every query." Its test is `grep -q -- '--state open' "$CO_GH_LOG"`.

**Measured.** I deleted the fake's entire `--state` arm — `:1661`,
`*"--state open"*) cat "${RE_PR_OPEN:-$RE_PR}" ;;` — which restores verbatim "a fake that
answers every query the same way", the condition the assertion names. Result:
`[scenario-liveness] summary: 76 passed, 0 failed`. Both merged-leg cases green, this one
included.

**Why.** After the fix nothing reaches that arm. `cmd_mark` and `resolve_open_pr` both ask
`--state all`; the only `pr list --state open` in the composed lane is the scheduler's
`resolve_pr()` (`orchestrate-lean.sh:731`), and it carries `--jq`, so the earlier
`*"--jq"*` arm captures it and answers `$RE_PR_NUMS` — the record, not "none". So
`RE_PR_OPEN` / `CO_PR_NONE` is dead fixture; the grep matches a query that was answered
*with the PR*; and the fake's log would carry that string whatever the arm did.

This also falsifies AC-2's entailed clause — "the suite's gh fake discriminates on
`--state`, so an `--state open` call no longer receives the record an `--state all` call
gets". For the one `--state open` call the leg actually makes, it still does.

**Not in dispute:** the leg's *first* assertion is a genuine killer. With `cmd_mark`'s
pre-#670 resolver restored, `(lean-closeout-merged)` fails
`rc=1 spawns=2 milestone-5-rows=0`. The leg works; the assertion certifying that it works
is the empty one, which is worse than not having it — it launders the leg as
non-vacuous, so a later change that stops any query reaching the arm is invisible.

### B2 — AC-4's oracle returns 1, not zero (blocker)

Run verbatim from the worktree root at `51ba24e`, the AC's command prints exactly one line:

```
docs/testing.md:887:  `docs/onboarding.md`. #642 falsified the reason all seven gave — "milestone 5 requires an OPEN
```

At `ff3f6f8` the same command prints the seven declared sites (verified — one per row of
the AC's table, no more). The surviving match is inside the declined-coupling row **AC-5
mandates**, quoting the falsified sentence as evidence.

The substance of AC-4 holds: all seven live sites are corrected, and a deliberately
broader sweep (`milestone 5|exit milestone|close-out` intersected with
`open pr|pre-merge|still in flight|requires.*open`, plus a read of the three other files
mentioning `second-shift-unclaim`) turns up no eighth live assertion. What fails is the
AC as committed — it states a measured result that is false at its own head, and the
AC-5 row's "the three frozen-record classes … are excluded on purpose" list is one class
short of what its sibling oracle now needs. Extend the exclusion set (`':!docs/testing.md'`)
or narrow the regex, and re-run before relying on it. Independently found by
scope-completeness-reviewer at confidence 95.

### W1 — `(pm7c)` asserts nothing (warning)

AC-1 requires "On a MERGED PR it posts nothing". `(pm7c)` is the case for that half and
tests `[ ! -s "$BOT_SPOOL" ]`. Its session `sess-mark-670` is not one of the four
`mark_attest` calls (`sess-mark-1/2/3/jb`), so `cmd_mark`'s build-session guard refuses
the write two guards past the merged branch no matter what that branch does.

**Measured.** With the merged early-return deleted, `(pm7c)` still PASSES — the run's
refusal is `this session ('sess-mark-670') is not a recorded BUILD session`. Add
`mark_attest sess-mark-670` and re-run the same mutant and `(pm7c)` FAILS, with the marker
body in the spool. So the write path is reachable; the fixture just never lets it be
reached. Note the cheap fix is not quite one line: a fourth `mark_attest` reds `(ms11)`
(`mark wrote to the progress file: rows=4`) in my control run, so reusing an
already-attested id for the merged case is the smaller change.

Not a blocker: `(pm7b)`'s `rc=0` + `already MERGED` assertion does kill the early-return's
removal. The property is guarded — by its sibling, not by the case that claims it.

### W2 — AC-7 names a script that is not in the tree (warning)

`tools/mutation-catalog-selftest.sh` exists at neither `ff3f6f8` nor head; the catalog's
suite is `tools/mutation-sweep-selftest.sh`. The substantive obligation is met, verified
by hand instead: all **26** `mutation-catalog.tsv` rows anchored in `lean-gate.sh` still
apply, under the sweep's own invocation (`sed -E`, per `tools/mutation-sweep.sh:1852`) —
zero anchor-drift no-ops, `lean-gate-mark-session-guard` included, whose anchor
`if ! session_in_build_set "$msid"; then` this change does not touch. Independently found
by scope-completeness-reviewer at confidence 92.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(pm7b)` drives `GH=<stub>` with no `--pr-file`, rc=0 naming the merged PR; `(k7b)` passes milestone 5 over the live path. Both fail when `cmd_mark`'s `--state open` resolver is restored. The behaviour is present; see W1 on the coverage of its second half. |
| AC-2 | **unsatisfied** | The leg exists and is a real killer, but the "Entailed and included" clause is false for the only `--state open` call the leg makes, and the assertion written to certify it cannot fail (B1). |
| AC-3 | satisfied | `(k7)` now reads "resolve_open_pr accepts a MERGED PR through the --pr-file seam" — the reachability claim moved to `(k7b)`. |
| AC-4 | **unsatisfied** | Substance met at all seven sites; the declared oracle returns 1, not zero (B2). |
| AC-5 | satisfied | `docs/testing.md:882-907` — what is duplicated, why `verbatim` LOCKSTEP is wrong for seven differently-addressed arguments, why the #674 derive-it shape does not fit, and the excluded frozen-record classes. `check-lockstep-pairs.sh` green. |
| AC-6 | satisfied | Verb is `fix(dev-pipeline):`; `Changelog:` trailer present. CI oracle: `pr-gates` step "changelog trailer guard" **success** at head `51ba24e` (run 33323966796). |
| AC-7 | satisfied in substance | All 26 lean-gate.sh catalog seds re-derived as still applying; the named oracle does not exist (W2). |

Design: `not-applicable` — the spec disarms with `Design: none`, and the repo's config
carries no `design.provider`, so the disarm is justified rather than a missed arm.

## Verification

- Both changed suites run directly at head: `lean-gate-selftest.sh` **all green**;
  `scenario-liveness-selftest.sh` **76 passed, 0 failed**. Milestone 3's sweep defers both,
  so the gate's green is not evidence for them; CI's `--full` sweep is —
  `lint-and-selftests` **pass** and `selftests (macos, bash 3.2)` **pass**, both at head
  `51ba24e`.
- Mutants, each in its own detached worktree: **M1** `cmd_mark`'s `--state open` resolver
  restored → kills `(k7b)`, `(pm7)`, `(pm7b)` and `(lean-closeout-merged)`. **M2**
  merged early-return deleted → kills `(pm7b)` only; `(pm7c)` survives. **M3** the fake's
  `--state` arm deleted → **nothing fails, 76/76**. **M4** M2 + `mark_attest sess-mark-670`
  → kills `(pm7b)`, `(pm7c)`, `(ms11)`. **M5** head + that attestation alone → `(ms11)` only.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all four changed shell files;
  `jq empty` clean on the schema; `check-lockstep-pairs.sh` rc=0; `ledger-lint.sh` OK
  (11 rows).
- Panel of 7, none dark, on the full branch diff: security, performance, maintainability,
  complexity, test-coverage all `approve` with zero findings; unit-test-mutation two
  message-text nits (N2); scope-completeness surfaced B2 and W2 independently.
  a11y + design-fidelity not routed — no changed path is a web component.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on its `lean chain reconciliation` step alone; every other step in that
job — frozen files, changelog trailer, guard budget, pipeline chain — is green. That step
requires a committed `verdict=approve`, so it cannot be green before this record exists.
Expected state, not a finding.
