# lean review verdict — #582

verdict=approve
run_id: review-582-1
session_id: 4befead3-b728-406c-880e-c3957074da7f
rounds: 1
pr: #598
reviewed_head: cb0bfa3549271c267757beed615fe79da976d8d9
reviewed_patch_id: bb2a943d69f3bf9896dd8d13674f214ec0ec14fe
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1. Range read: `06e48be..cb0bfa3` (full branch diff — `G delta` reported nothing
verifiable to inherit). 4 files, +131/-0: `tools/mutation-sweep.sh`,
`tools/mutation-sweep-selftest.sh`, `docs/testing.md`, `docs/plans/second-shift-582-lean.md`.

Verdict: **approve**. No blockers. Two warnings and two suggestions, all in the
test-coverage dimension; none of them makes an AC unmet.

## Per-AC scoring (against `docs/plans/second-shift-582-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — all-deferred run prints one unmissable line naming count + reason(s), textually distinct from a clean sweep | **satisfied** | `tools/mutation-sweep.sh:1107-1113`. Probe P1 (replace `warn "$ALL_DEFERRED_MSG"` with `:`) → suite reds at `(l3b)`. Probe P4 (break the `"slow suite"*` case arm) → suite reds at `(l3b)`, so the *reason clause* is pinned too, not just the line. The line is a `WARN:` on stderr, distinct from the pre-existing `info "defer <g> -> nightly: ..."` and from `info "nothing left to sweep after deferral."` |
| AC-2 — under `GITHUB_ACTIONS`, additionally a `::warning::` annotation, plus a `GITHUB_STEP_SUMMARY` block when set; exit stays 0 | **satisfied** | `ENFORCING` is defined at `:336-337` as exactly `GITHUB_ACTIONS` set, matching the spec's wording. Probe P2 (neuter the `::warning::` echo) → suite reds at `(l3b)`. CI runs the sweep unredirected (`.github/workflows/ci.yml:210`), so the annotation reaches the check surface. Exit code is untouched — `warn()` increments `WARNINGS`, which `finish()` only reports. The summary-block half is correct by inspection but has **zero coverage** — see W2 |
| AC-3 — a run that sweeps ≥1 guard is byte-for-byte unchanged | **satisfied** | The new statements are confined to `if [[ ${#PR_SWEPT[@]} -eq 0 ]]`; the only other addition is a `case` that increments counters and emits nothing. Probe P3 (loosen the gate to `-ge 0`) → suite reds at `(r)`'s new control, so the AC-3 boundary is genuinely guarded rather than asserted |
| AC-4 — a case pins AC-1 on an all-deferred run and a control pins its absence on a partial defer; both fail if the line is removed or the gate is loosened | **satisfied** | `(l3b)` and the `(r)` control. Probes P1/P2/P4 red `(l3b)`; P3 reds `(r)`. Both directions are live, not vacuous: `(r)` runs under `enf` (`GITHUB_ACTIONS=1`) with `2>&1`, so its two negative greps could fire |
| AC-5 (doc) — `docs/testing.md`'s "A green PR does not mean a green nightly" passage describes the new warn | **satisfied** | `docs/testing.md:845-851`. Delivered as a paragraph rather than the one sentence the AC asks for; the extra content is accurate (count, reasons, CI annotation, summary block, and the "≥1 swept is unchanged" boundary) |

Design: spec carries no armed `## Design` section, so fidelity is `not-applicable`.

## Verification performed this round

Six full runs of `tools/mutation-sweep-selftest.sh` (one control + five mutants), each in its
own copy of the reviewed head so the mutants could not interfere:

| Probe | Mutant | Result |
| --- | --- | --- |
| P0 | none (control) | `EXIT=0`, "all cases passed" — the suite is green at `cb0bfa3` |
| P1 | `warn "$ALL_DEFERRED_MSG"` → `:` | **killed** — `FAIL (l3b)` |
| P2 | `echo "::warning::…"` → `:` | **killed** — `FAIL (l3b)` |
| P3 | `${#PR_SWEPT[@]} -eq 0` → `-ge 0` | **killed** — `FAIL (r) a partial defer wrongly fired the all-deferred warn/annotation` |
| P4 | case arm `"slow suite"*` → `"slow suitX"*` | **killed** — `FAIL (l3b)`; dumped output shows the degraded `(reasons: )` |
| P5 | case arm `"multi-suite union"*` → `"multi-suite unionX"*` | **SURVIVED** — `EXIT=0`, "all cases passed" (see W1) |

Also checked, all clean:

- `shellcheck -e SC1091,SC2015,SC2181` on both changed scripts (0.11.0 locally; CI runs 0.9.0).
- **bash 3.2**, which a second macOS CI job runs: `${#PR_SWEPT[@]}` on an *empty* array under
  `set -euo pipefail` was executed on stock `/bin/bash 3.2.57` and does not trip `unbound
  variable` (the hazard the surrounding code guards elsewhere with `${PR_SWEPT[@]+…}`). The
  `[[ cond ]] && var=…` reason-assembly idiom likewise does not trip `set -e` on 3.2.
- **Production no-fire arm**: this PR's own `mutation-sweep-pr` job (job 96247359260) exits at
  `PR mode: no in-universe guards touched … — nothing to sweep`, with no WARN and no annotation
  — the new code correctly stays silent on a diff whose only guards are exclusion-listed.
- `pr-gates` is red for exactly one reason — the missing verdict record this file supplies.
- Reviewer panel: 6 selected, 6 returned, none dark. Security, performance, maintainability,
  complexity and scope-completeness all `approve`; test-coverage `approve-with-nits` with the
  finding recorded below as W2 (found independently by this session as well).

## Findings

### Warnings (should fix; neither blocks)

**W1 — the `multi-suite union` reason arm is unguarded, and it is the *other reachable*
category.** `tools/mutation-sweep.sh:1090-1092`. `(l3b)` pins `reasons: slow suite: 1` and P4
proves that arm is live, but P5 mutated the sibling `"multi-suite union"*` arm and the entire
69-case suite still passed. The consequence is not cosmetic: with the arm not matching, the AC-1
line degrades to `… 0 swept (reasons: ). See tools/…` — the count survives, the reason vanishes,
and AC-1's "naming … the reason(s)" is quietly half-met. That shape is observed, not predicted —
P4's failure dump prints it verbatim. This matters more than usual here because
`tools/mutation-sweep.sh` is exclusion-listed in `tools/mutation-exclusions.tsv:22` (recursion
guard), so its co-located selftest is the *only* net; the mutation sweep will never find this.
The fixture already exists: case `(q)` (`tools/mutation-sweep-selftest.sh:905-921`) constructs a
one-guard two-killer PR run — i.e. an all-deferred multi-suite run — under `enf` with `2>&1`.
One added `grep -q 'reasons: multi-suite union: 1'` on `(q)`'s existing `$OUT` closes it.

**W2 — the `GITHUB_STEP_SUMMARY` block has zero coverage.** `tools/mutation-sweep.sh:1115-1121`.
No case in the suite sets `GITHUB_STEP_SUMMARY` (zero matches for the name in the whole file);
`(l3b)` and `(r)` both run under `enf`, which sets `GITHUB_ACTIONS`/`RUNNER_OS`/`SKIP_STRESS`/
`MUTATION_SWEEP_CACHE` but not that variable. So a whole conditional branch of a claimed AC — the
group redirect, the heading, and the interpolation — is never executed by any test, on a file the
mutation sweep is contractually forbidden to reach. Pointing it at a temp file in `(l3b)` and
asserting the block lands (and, in `(r)`, that the file stays empty) is a few lines.

### Suggestions

**S1 — the `PR-lane cap` reason category is unreachable in the message that consumes it.**
`tools/mutation-sweep.sh:1093, 1097`. `defer_cap` is incremented only when the cap fires, and the
cap fires only at `fast_count >= PR_FAST_GUARD_CAP` (`:1083`, a hard `6` at `:170`, not
env-overridable). `fast_count` increments on exactly the branch that appends to `PR_SWEPT`
(`:1095-1096`), so `defer_cap > 0` implies `${#PR_SWEPT[@]} >= 6`, which is precisely when the
all-deferred branch does not run. The `PR-lane cap: N` clause is therefore dead by arithmetic,
and P3 corroborates it: only after loosening the gate did `(r)` — the cap fixture — produce the
message at all. The spec asked for three categories, so this is faithful implementation of a spec
detail rather than an implementation error; worth a one-line comment or a drop, not a fix round.

**S2 — the `ENFORCING` gate on the annotation has no negative case.** Nothing asserts that an
advisory (local, `GITHUB_ACTIONS` unset) all-deferred run does *not* emit `::warning::`, so
deleting the `if [[ $ENFORCING -eq 1 ]]` wrapper would survive the suite. Not required by any AC
— AC-2 only constrains the CI direction — and the suite already has an `adv()` helper for it.

### Note (not a finding)

The ticket's premise that "nothing … distinguishes" an all-deferred run is very slightly
overstated: `info "nothing left to sweep after deferral."` (`:1140`) pre-dates this PR. It is an
`info` on stdout, names no count or reason, and reaches no check surface, so the fix is still
warranted — recorded only so a later reader does not mistake that line for the new one.

## Strengths

- The `(r)` control is the load-bearing half and it was written deliberately, with its reasoning
  in the comment: `(l3b)` alone would pass a mutant that loosened the gate to fire on any defer.
  P3 confirms the control is what catches it.
- The gate is placed where its precondition is already established — the empty-diff case exits at
  `:1011` before this block — so `pr_scope_count` is provably ≥ 1 and the message cannot report
  "all 0 in-scope guard(s)". A PR touching only exclusion-listed guards (this PR itself) takes the
  earlier exit, which the CI job log confirms.
- `warn` rather than `warn_baseline` is the right class: `finish()` renders it as "the baseline is
  not one of them" instead of sending the reader to a file that needs nothing.
- Scope discipline held. `SLOW_THRESHOLD_S`, `PR_FAST_GUARD_CAP`, deferral eligibility, and the
  exit contract are all untouched, exactly as the ticket's out-of-scope list requires.
