# lean review verdict — #585

verdict=approve
run_id: review-585-1
session_id: e8fa327c-28fa-4469-9309-12404bea3334
rounds: 1
pr: #588
reviewed_head: 688c02dc41d27e27dbfcd07d0589021c0b463080
reviewed_patch_id: 212c803fa7d33362e819c19c0b2e890c5726819c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict: approve — round 1, 0 blockers, 1 warning

All twelve ACs scored **satisfied**. Every kill claim in the PR body was reproduced
independently — in an isolated detached worktree at the reviewed head, never in the build
worktree — and each was checked in **both** directions plus a **negative control** proving the
fixture edit is what does the killing. The panel (7 reviewers, none dark) returned zero findings.

The one warning is a nightly guard outside this ticket's ACs that this PR tips over its ratchet.
It is not a blocker, for reasons stated below.

---

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** | satisfied | `grep -nE -- 'exit 1'` over `orchestrate-lean.sh` at head returns **0** lines. The `detector` ERE no longer matches line 251 (sequence replay below). Meaning preserved: the reworded paragraph still states the thirteen sites, the one that conflated three remedies, and that every run-ending exit prints a stable slug. |
| **AC-2** | satisfied | Comment-only — the diff on that file touches no executable line. Replaying **every** operator in `tools/mutation-operators.tsv` base(`d344956`)→head and byte-comparing the matched-line **sequences**: `cmp-eq` 8→8, `cmp-z` 12→12, `logic` 49→49, `default` 7→7 all **byte-identical**; `detector` 5→4 as a pure `1d0` — head is base-minus-line-251, remaining order preserved. |
| **AC-3** | satisfied | `git diff d344956..HEAD -- tools/mutation-baseline.tsv tools/mutation-catalog.tsv` is **empty**. `tools/capability-parity-check.sh` has **0** baseline and **0** catalog rows, and all six of its operator sequences are byte-identical base→head. The "no new row is owed" half is **CI-confirmed, not asserted**: in the dispatched sweep, `orchestrate-lean.sh::detector::1` and `::detector::2` both logged as **KILLED**. |
| **AC-4** | satisfied | `report-state-excerpt-lean-newest` keeps its name, its position (still immediately after `report-state-excerpt-lean-preferred`), and both assertions (`newer-lean-run-marker` present / `lean-era-abort-reason` absent). The only functional change is the printf target, `99-`→`11-`. No new case, no new fixture tree. |
| **AC-5** | satisfied | `doctor.sh` unmodified; all six operator sequences byte-identical base→head. |
| **AC-6** | satisfied | Reproduced. Unmutated: `doctor-selftest.sh` rc=0. Mutant `[[ -z "$newest" ‖ … ]]` → `[[ -n "$newest" ‖ … ]]` (the operator's own sed, applied to that one line, `bash -n` clean): rc=1 with **exactly one** failure — `✗ report-state-excerpt-lean-newest`. **Negative control:** restoring the pre-#585 `99-` fixture name under the *same* mutant returns the case to `✓` and the suite to rc=0 — so the rename is what kills, not an unrelated break. |
| **AC-7** | satisfied | CI on the head commit: `lint-and-selftests` **pass** (4m26s) and `selftests (macos, bash 3.2)` **pass** (4m38s). |
| **AC-8** | satisfied | Run [`32180931782`](https://github.com/manoldonev/second-shift/actions/runs/32180931782) — `workflow_dispatch`, `headSha` `688c02d` (byte-equal to the reviewed head), **all 10 shards + merge success**. Enforcing mode confirmed in-log: `enforcing mode: event='workflow_dispatch', baseline present=yes`. And the guards genuinely produced **verdicts** rather than being deferred — shard 9: `orchestrate-lean.sh applied=13 killed=12 survived=1`, `doctor.sh applied=13 killed=6 survived=7`; shard 2: `capability-parity-check.sh applied=7 killed=7 survived=0`. |
| **AC-9** | satisfied | The PR body carries the corrected triage table, with the `doctor.sh::cmp-z::1` shard/date correction stated explicitly. |
| **AC-10** | satisfied | `(c)` keeps its name, its position, and its `rc == 1` assertion; the only functional change is dropping the trailing `\n` from the `write_register` format. No new case, no new helper, no other case's fixture touched. |
| **AC-11** | satisfied | `tools/capability-parity-check.sh` unmodified; all six operator sequences byte-identical base→head. |
| **AC-12** | satisfied | Reproduced, all three directions. Unmutated: 14 passed / 0 failed. `logic` ord 2 (`‖`→`&&` on `while IFS= read -r line ‖ [[ -n "$line" ]]`): 13 passed / **1 failed**, and the failure is **case (c) specifically** — `FAIL: (c) off-enum disposition did NOT red — rc=0`. `logic` ord 1 (`&&`→`‖` on the `HERE=` assignment): 1 passed / 13 failed — killed, so the whole `k=2` window is covered. **Negative control:** restoring the trailing `\n` under the ord-2 mutant returns the suite to 14 passed / 0 failed — the termination removal is what kills. Independently corroborated by the dispatched sweep's `survived=0`. |

**Fidelity: not-applicable.** The spec has no `## Design` section and the repo config declares no
`design.provider`, so the design-sighted arm has nothing to score.

---

## Warning (should fix — not blocking)

**[prose-budget] `tools/capability-parity-check-selftest.sh` — this PR tips the shell prose
ratchet over its tolerance.**

`plugins/dev-pipeline/tools/prose-budget.sh` is a **nightly** guard
(`.github/workflows/nightly-guards.yml`), and its own header says a red there "blocks no PR" but
"reds like every other guard in this file". Measured on both trees:

| Tree | `tools/capability-parity-check-selftest.sh` | Result |
| --- | --- | --- |
| base `d344956` | 162 total / 137 non-blank / 40 comments — **29.2%** | ok (baseline 28.1%, +1.1pp) |
| head `688c02d` | 171 total / 146 non-blank / 49 comments — **33.6%** | **FAIL** — `ratio grew 28.1%->33.6% (>+5pp)` |

The +4.4pp jump is entirely the AC-10 fix's 9-line explanatory comment. Whole-run totals: base
**2 fail(s)**, head **3 fail(s)** — the added row is this one.

**Why this is a warning and not a blocker.** The other two failures
(`plugins/second-shift/skills/onboard/SKILL.md`, `tools/capability-parity-check.sh` at 53.4%) are
already present at the merge base and are **not** this PR's — `capability-parity-check.sh`'s own
row is the same #577-deletion-shrinks-the-file effect one layer over. So `nightly-guards` reds
tonight with or without #585, and merging this does not flip a green job red. The guard is also
explicitly advisory to the lean lane, appears in no AC, and the ticket's "green moat" is scoped in
the spec to the nightly **`mutation-sweep`**, a different workflow — which this PR does deliver.

**Suggested remedy, at the operator's discretion:** either shorten the new comment block, or
update that one baseline row. Prefer a **targeted** row edit over a bare `--update-baseline`,
which would also silently absorb main's two pre-existing failures into this diff. Worth noting the
mechanism is the mirror of what the PR itself documents: a change elsewhere moves a measurement,
and a guard nowhere near the change goes red.

There is a second-order note only: the same run reports `3 of 89 shell baseline row(s) no longer
resolve` and `1 of 65` markdown — stale rows from #577/#584 deletions, pre-existing and untouched
here.

---

## Reviewer panel

7 reviewers selected, **7 returned, 0 dark**. All approve, zero findings above threshold.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Pass | 0 | — |

Not routed (not dark): `db-reviewer`, `pipeline-reviewer` — no DB or queue-worker surface;
`a11y-reviewer` and the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`).

Suppressed below threshold, recorded for visibility: scope-completeness noted (conf 70) that the
issue text asked to "add the behavioral case" while the diff strengthens the existing one in place
— the plan records that choice explicitly (AC-4/AC-10 both say "in place"), and the mutant is
killed, so intent is satisfied. It also noted (conf 65) that D-4's "#585 before #579" ordering is
operator discipline, not mechanically enforced. Neither is a scope miss.

---

## Checks not required by an AC, run anyway

- **The new comments cannot manufacture new phantom sites.** This is the exact defect class the PR
  fixes, and two of the three new comment blocks quote the operator shapes verbatim (`-z `, `||`,
  `grep`-plus-quoted-string). Safe on both counts: `tools/mutation-sweep.sh` enumerates guards that
  are **not** `*-selftest.sh`, so the two selftest comments are never mutation-enumerated; and the
  one comment that *is* in a swept guard was replayed against all six EREs and matches none — which
  is what the byte-identical `cmp-eq`/`cmp-z`/`logic`/`default` sequences in AC-2 demonstrate.
- **No fixture-name collision from the `99-`→`11-` rename.** `11-lean-progress.md` is referenced
  once; the only other `*-lean-progress.md` in that fixture tree is `88-`, and the preceding case's
  `88-lean-progress.md` assertion runs before `11-` is created.
- **Spec-amended-after-the-fact:** checked and clean. `cfa9c0b` (the AC-10/11/12 amendment) is
  authorized by an operator comment on #585 timestamped 2026-08-18 19:56:07Z that explicitly widens
  the ticket, and it lands **before** its own code commit `688c02d` — spec-first, not
  retrofitted-to-match.
- **`Changelog:` trailers** present on all four commits.
- **`pr-gates` is red for exactly one reason** — `[lean-evidence] ✗ no committed verdict record`.
  That is this record. No other gate in that job failed.

## Strengths

- The evidence discipline is the strongest part of this PR. Every kill is claimed with the
  operator's own sed applied to the named ordinal, in both directions, and the AC set demands the
  unmutated pass alongside the mutated fail — so a case that reds because the suite is broken
  cannot be mistaken for a kill.
- Remedying the fourth cause **at the site** rather than by a baseline row is the right call under
  "never re-baseline blind", and it is the reason the diff acquires zero rows while closing three
  survivors.
- The `deletion-pulls-a-site-into-budget` root cause is correctly generalized rather than treated
  as a one-off: an ordinal shift arming a never-mutated idiom is a class, and naming it makes the
  next instance diagnosable.
- Each fixture edit carries an in-file note explaining why the specific value is load-bearing
  (`11-` must sort ahead of `88-`; the missing `\n` must not be tidied). Both are exactly the
  invariant a future editor would otherwise silently break — which is how the original survivors
  were born.

**Ready to merge?** Yes — after the warning above is either addressed or accepted by the operator.
Merging as-is does not change `nightly-guards`' conclusion, which is red at the merge base
independently of this PR.
