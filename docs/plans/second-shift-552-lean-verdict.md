# lean review verdict — #552

verdict=needs-work
run_id: review-552-1
session_id: 003f1149-4bb3-48fa-ab23-97fce6025425
rounds: 1
pr: #561
reviewed_head: 82042f6ed443f1aa1d468580d308c3ac832c79c5
reviewed_patch_id: cf0c7e27093a6ddaf2777f407b008a63e51448b5
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #561 / issue #552 (shell prose ratchet)

Range read: `54aec70..82042f6` (root round — full branch diff, per `lean-gate.sh delta 552`).
Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness.
Five approve, one request-changes (scope, dismissed below). Two blockers found by the round
itself, neither of which the panel raised.

Verdict: **needs-work**. Fidelity: **not-applicable** (`Design: none`, justified — no design
provider configured in this repo and the change renders nothing outside a terminal and two TSVs).

## Findings

| # | Severity | Where | Finding |
|---|---|---|---|
| 1 | blocker | `tools/mutation-baseline.tsv:95` | AC-12 unmet: `prose-budget.sh::detector::2` re-keyed to a new site and its mutant is now KILLED, but the row was left in place. |
| 2 | blocker | `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh:540` | The `n/a` short-circuit now reports "nothing to measure" in the exact repo shape where the new shell path DID measure. This diff makes an existing operator message false. |
| 3 | warning | PR body, "AC-7" section | Path labels in the reproduced table are wrong (`.claude/skills/…`); the measured files are under `plugins/dev-pipeline/skills/…`. Values are correct. |
| 4 | warning | issue #552 body | The AC-8 amendment is ratified in an issue COMMENT; the issue BODY still carries the superseded clause with no deferral language. |

### 1 — blocker. AC-12: `detector::2` was not re-derived

AC-12: "`tools/mutation-baseline.tsv` rows keyed `prose-budget.sh::detector::2` and
`prose-budget.sh::logic::1` are **re-derived**". The diff touches neither file. The PR body
declines to act on row 95 on the ground that the local sweep printed `ADVISORY RUN — kill
verdicts are not comparable to the committed baseline`.

That is the wrong basis, and this repo has already written down why: an ordinal re-key is a
**positional** fact provable by arithmetic, and a kill/survive verdict on a single site is
provable by an isolated probe. Neither needs a baseline-comparable sweep. Both were run this
round.

Ordinals are `grep -nE -- "$opmatch"` line order (`tools/mutation-sweep.sh:1553-1582`), with
`K_BUDGET=2` applied per operator per guard. The `detector` operator over `prose-budget.sh`:

```
base  54aec70   detector::1  line  86   | grep -v -- '-fixtures/'            (tracked_files)
                detector::2  line 128   grep -vc '^#' "$REPO_BASELINE"       (update confirmation)
                (2 sites total)

head  82042f6   detector::1  line 118   | grep -v -- '-fixtures/'            (tracked_files)      unchanged
                detector::2  line 163   | grep -v -- '-fixtures/'            (tracked_shell_files) NEW CODE
                detector::3  line 180   grep -c '[^[:space:]]'               NEW, beyond K=2
                detector::4  line 181   grep -c '^[[:space:]]*#'             NEW, beyond K=2
                detector::5  line 214   grep -vc '^#' "$REPO_BASELINE"       ← the OLD ::2, beyond K=2
                detector::6  line 228   grep -vc '^#' "$SHELL_BASELINE"      NEW, beyond K=2
                (7 sites total)
```

So row 95 now names a different site, and the site it was granted for is no longer applied at
all. Probed the new `detector::2` in an isolated copy of the reviewed head — flip line 163's
pattern to `__MUTANT_NEVER_MATCHES__`, `bash -n` clean, then run the paired suite:

```
clean tree : [prose-budget-selftest] 30 passed, 0 failed     (rc=0)
mutant     : [prose-budget-selftest] 29 passed, 1 failed     (rc=1)   → KILLED
```

Correct re-derivation is therefore **drop row 95**, which is what `mutation-sweep.sh:1896`
itself would say (`baseline row is now KILLED: … — drop the row.`).

Why CI did not catch it: `mutation-sweep-pr` is green and non-vacuous here —
`prose-budget-selftest.sh` carries no `tools/mutation-slow-suites.tsv` row, so the guard was
genuinely swept — but the shrink-warn that names a now-killed row is gated on
`[[ "$MODE" == "full" ]]`, so the PR lane structurally cannot report it. It surfaces on the
next nightly, as a recurring warn.

Impact if shipped: not a red — `warn_baseline` is non-fatal. But the row is a standing
pre-authorized amnesty at an id whose meaning has changed, which is the precise failure mode
CLAUDE.md's "editing a guard re-keys its generic survivor ordinals — re-baseline those rows in
the same diff" exists to prevent.

Verified clean, for the record, so the fix stays one line:
- `logic::1` / `logic::2` — same code at base and head (`SCRIPT_DIR=…&& pwd`, `REPO=…||{…}`). Not re-keyed. AC-12's second row needs no edit.
- `cmp-z::1/2` — unchanged sites.
- `default::2` DID re-key (base `${PROSE_ROOTS:-}` → head `${PROSE_SHELL_TOLERANCE_PP:-5}`), but there is no baseline row for it and CI's sweep is green, so no obligation.
- `tools/mutation-catalog.tsv:54` — `stale == rows` is single-site at head (only line 369); the `sh_rows`/`sh_stale` naming holds. **AC-12's catalog clause is satisfied.**

**Fix:** delete line 95 of `tools/mutation-baseline.tsv`.

### 2 — blocker. The doctor's `n/a` branch swallows a measured shell verdict

`pipeline-doctor.sh:540-544`, unchanged by this PR:

```sh
if pb=$(bash "$SCRIPT_DIR/prose-budget.sh" 2>&1); then
  if grep -q 'n/a — no instruction layer' <<< "$pb"; then
    ok "prose-budget: n/a — no instruction layer in this repo (nothing to measure)"
  else
    ok "prose-budget: $(tail -1 <<< "$pb" | sed 's/\[prose-budget\] //')"
```

Before this PR that message was true: markdown `n/a` meant nothing was measured, and the tool
`exit 0`'d on that branch. AC-4 deliberately removes that early exit so a repo with `tools/*.sh`
and no `skills/`/`agents/` root reaches a shell verdict. The doctor's predicate was not revisited,
so the shell verdict is now computed and then discarded.

Probed in a fixture of exactly that shape (`tools/x.sh`, `tools/y.sh`, no instruction-layer root):

```
[prose-budget] n/a — no instruction layer in this repo (no skills/ or agents/ root found).
[prose-budget] note: no shell baseline — every shell file reports NEW. …
[prose-budget] 0 fail(s), 2 warning(s)  (coverage: md n/a, sh measured; tolerance: …)   rc=0

doctor branch taken → ok "prose-budget: n/a — no instruction layer in this repo (nothing to measure)"
```

Two shell files measured, two warnings raised, and the operator is told nothing was measured.
The `tail -1` line the ledger's D-4 went out of its way to keep combined is the line this branch
throws away.

This is not exotic: the tool's own comment calls the no-instruction-layer shape "the expected
state for a repo whose skills and agents come from the plugin cache" — i.e. every consumer that
is not this repo. Dogfooding here is blind to it because second-shift has `plugins/*/skills`, so
the branch never fires locally.

Scoped honestly: AC-10's letter ("stays reachable from `pipeline-doctor.sh`, whose branch set
gains one arm per shell failure state") is met — the three failure arms exist and the tool is
invoked. This is a blocker **outside** the AC set, on the ground that the diff introduces a new
gap: it makes a shipped operator-facing message false. Push back with reasoning if you read the
boundary differently.

Coverage note: `T11 n/a` uses a bare `mkrepo` with no shell files, so it passes and does not
codify this. `S5b` asserts the tool's own summary line, not the doctor's rendering of it — which
is why nothing in the suite fires.

**Fix sketch:** gate the short-circuit on both paths being `n/a` (the summary line already carries
`coverage: md n/a, sh n/a`), falling through to the `tail -1` arm otherwise; add a T11 case for
`md n/a + sh measured`.

### 3 — warning. PR body AC-7 table mislabels the paths

The body prints `.claude/skills/lean-gate.sh` and `.claude/skills/orchestrate-lean.sh`. The files
measured — and the rows in the committed baseline — are
`plugins/dev-pipeline/skills/build-lean/lean-gate.sh` and
`plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh`. Re-derived independently at `3e83e46`:

```
plugins/dev-pipeline/skills/build-lean/lean-gate.sh        4875 / 4612 / 2494   round=541  trunc=540
plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh    922 /  872 /  520   round=596  trunc=596
tools/run-selftests.sh                                      581 /  543 /  245   round=451  trunc=451
```

Values reproduce AC-7 exactly, and confirm AC-6's claim that `lean-gate.sh` is the only one of
the three that discriminates rounding from truncation. Body-only defect, so it costs no round.

### 4 — warning. The AC-8 amendment is ratified in a comment, not the body

`scope-completeness-reviewer` returned `request-changes` at confidence 92 on AC-8: the issue body
still says "existing markdown baseline rows keep their current values" while the diff moves ~30
rows, and it found no deferral language in the body.

**Dismissed as a merge blocker.** The committed lean spec is the definition of done here, its
AC-8 is the amended text, and the amendment followed the sanctioned route: the gap was
`undeclared`, the build paused rather than taking a default it was not entitled to, and the
operator ratified explicitly at
`https://github.com/manoldonev/second-shift/issues/552#issuecomment-5309460053` — in their own
words, naming the choice ("refresh … rather than shipping the new nightly job red on arrival")
and the amendment ("AC-8 is amended accordingly"). An issue comment can redirect scope, and a
user-answered disposition overrides the generic scope gate. The reviewer reads the body only, so
it could not see this.

Carried as a warning because the reviewer's underlying point survives: a future reader of the
issue body alone meets a clause the merged diff contradicts, with nothing on that page pointing
at the ratification. Worth folding the operator's sentence into the issue body — but it is a
tracker-hygiene action, not a code remedy, and it does not gate this PR.

## Per-AC scoring

| AC | Score | Evidence |
|---|---|---|
| AC-1 | satisfied | Four fields per file; `comment_lines_of` = `grep -c '^[[:space:]]*#'` (shebang counts); `nonblank_of` is the denominator. S2 asserts `6 5 3 60.0%` by value, so a total-lines denominator fails there rather than reading as rounding noise. |
| AC-2 | satisfied | `shell_roots()` = `prose_roots()` + `tools/` under the same `[[ -d ]]` filter; `-fixtures/` excluded in `tracked_shell_files`. S5 pins the `tools/` inclusion with no skills/agents root. |
| AC-3 | satisfied | `find $roots -type f -name '*.sh'` — generic. 106 baseline rows, no hardcoded list. |
| AC-4 | satisfied | `SH_COVERAGE` computed from `sh_tracked` + `raw_shell_matches()`, independent of `MD_COVERAGE`; the markdown `n/a` `exit 0` is removed. Probed directly: a `tools/`-only repo reaches `coverage: md n/a, sh measured`. S1/S4 pin the n/a-vs-vacuous asymmetry, S5b pins the summary rather than the table (correct — the table prints above the removed short-circuit). |
| AC-5 | satisfied | Own file, 106 rows, columns `path/total/nonblank/comments/ratio_tenths`, ceiling reads col 5. Markdown baseline header byte-identical (no `#` line in the diff) and every data row still 4 fields. No stub companion; absence yields `have_shell_baseline=0` → NEW. |
| AC-6 | satisfied | `ratio_tenths` = `(c*1000 + n/2)/n` — round half up, verified against `lean-gate.sh` @ `3e83e46` (541 rounded vs 540 truncated). `sh_ceiling = sh_base + SH_TOL_PP*10` — additive points. `PROSE_SHELL_TOLERANCE_PP` default 5. S2b (5/9 → 55.6%) is the only case that discriminates the two forms, and it does. S3/S3b prove the tolerance is consulted and read in points. |
| AC-7 | satisfied | Reproduced independently at `3e83e46`: 54.1 / 59.6 / 45.1, exactly. Committed baseline carries this branch's values (`lean-gate.sh` = 539). No selftest pins a repo-file ratio. Path labels in the PR body are wrong — finding 3, body-only. |
| AC-8 (amended) | satisfied | 17 pre-existing cases untouched and passing (30 passed / 0 failed on the clean tree); markdown format and column-2 lookup unchanged; the empty-snapshot refusal and `PROSE_ALLOW_EMPTY_BASELINE` hatch stay markdown-keyed. Amendment operator-ratified — see finding 4. |
| AC-9 | satisfied | S1 (n/a), S2/S2b (measured + rounding), S3/S3b (over tolerance, both directions), S4 (vacuous), S5/S5b (`tools/` inclusion, independence), S6 (no cross-file leak), S8, S9. Every case names its AC and its non-vacuity argument. |
| AC-10 | satisfied | Read-only, never reds the lean lane; three new `pipeline-doctor.sh` arms, one per shell failure state; one standalone `prose-budget` job on `ubuntu-latest` in `nightly-guards.yml`. Ran the tool on the reviewed tree: `0 fail(s), 20 warning(s)`, rc 0 — the nightly is green on arrival. (The doctor's green-path reporting defect is finding 2, scored outside this AC.) |
| AC-11 | satisfied | `FAIL vacuous shell coverage` / `FAIL stale shell baseline` / `FAIL ratio grew` — none a substring of its markdown counterpart, and the markdown arms sit earlier in the chain so the direction that matters is the one T11s asserts. Last line is one combined summary naming both tolerances. |
| AC-12 | **unsatisfied** | Catalog clause holds (`stale == rows` single-site at head, confirmed). `logic::1` positionally unchanged. `detector::2` re-keyed and now KILLED, and the row was not re-derived — finding 1. |

Score: 11 satisfied, 1 unsatisfied, 0 undeterminable.

## What is good here

- **D-7 was the trap and the build walked around it.** Round-half-up is not a detail — a
  truncating implementation reproduces two thirds of the ticket's own table and still violates
  AC-6, and `lean-gate.sh` is the single file that notices. S2b was added specifically because
  the original S2 fixture (3/5 = exactly 60.0%) could not see the difference.
- **S5b was rewritten after it was found vacuous.** It originally asserted a table row, which
  prints *above* the removed early exit and therefore survived a restored short-circuit. Moving
  it to the summary verdict is what makes AC-4's independence actually guarded, and the PR body
  says so plainly instead of quietly.
- **The comment-as-mutation-site fix.** `-ness` containing `-ne`, and a comment spelling the
  literal a catalog row anchors on, are both real and both non-obvious. Removing the sites rather
  than baselining the noise is the right direction, and the `sh_rows`/`sh_stale` naming that
  keeps catalog row 54 single-site was carried from D-11 into the code and then re-verified.
- **The intent gap was paused on, not defaulted through.** No open region covered it, the build
  said so, recommended the conservative horn, and let the operator override it.

## CI at the reviewed head (`82042f6`)

| Check | Result |
|---|---|
| `lint-and-selftests` | success |
| `selftests (macos, bash 3.2)` | success |
| `mutation-sweep-pr` | success — non-vacuous (`prose-budget-selftest.sh` has no slow-suite row, so the guard was swept) |
| `pr-gates` | failure — sole failing step is `lean chain reconciliation`, the missing-verdict arm. Expected pre-review; not a finding. |
| `release-pr-gates` | skipped |

## To clear this round

1. Delete `tools/mutation-baseline.tsv:95`.
2. Fix the `pipeline-doctor.sh` `n/a` short-circuit so a measured shell verdict is not reported
   as "nothing to measure", and add the `md n/a + sh measured` case to T11.
3. Optional, no round cost: correct the AC-7 path labels in the PR body; fold the operator's
   ratification sentence into the issue #552 body.
