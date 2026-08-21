# lean review verdict — #613

verdict=approve
run_id: review-613-2
session_id: 16ded2e0-7357-41e2-86ce-0503599ca27e
rounds: 2
pr: #626
reviewed_head: 02caa5c5b089eac4d9654844f12bae98cd466590
reviewed_patch_id: 9f631d92701df28da26b1b1a1548517fc9d57870
inherited_patch_id: 843e20baeb12833f224b0a402047c746575b6ffc
inherited_from_verdict: f1935f3954a3a6df9041b8d6a55e2fcd51aee350
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 2, inheriting the coverage of patch `843e20baeb12`. Delta range `f1935f39..HEAD` — the three
fix commits, the `origin/main` merge, and the two post-merge commits. Read wider than the delta:
the panel ran over the branch's whole contribution (`origin/main...HEAD`, 21 files / +1983), since
`origin/main` is merged in and a scope gate on a fix-only range would be meaningless.

**Round 1's blocker is closed, and closed at the surface that was missing.** `(AA1)`/`(AA2)` in
`check-lean-chain-selftest.sh` mirror the intent-gap arm's `(S1)`/`(S3)` rungs, and both of round
1's mutants now red there and nowhere else. The two suggestions were taken and each is guarded by
a case that dies when the fix is reverted.

One warning carried forward: the round-1 `record` warning is **two-thirds fixed**. The costly half
— a typo'd `--gate` leaving an unreadable block in the right file and hard-refusing every later
`check` — is genuinely closed and guarded. The path half is not, and the comment that says it is
became the stated reason a working guard was deleted.

Panel: 6 of 6 reviewers usable, none dark. Five returned clean; security-reviewer returned the one
finding below (confidence 90), which I reproduced independently before adopting it.

## Verification performed in this session

| Check | Result |
| --- | --- |
| CI on the reviewed head `02caa5c5` | `lint-and-selftests` ✓ · `selftests (macos, bash 3.2)` ✓ · `mutation-sweep-pr` ✓ · `pr-gates` fails ONLY on the round-1 `verdict=needs-work` record (expected pre-handoff) |
| `mutation-sweep-pr` is not a vacuous green | log reads `8 mutant(s) to score, 0 served from cache` → `applied=8 killed=7 survived=1`, `9 verdict(s) computed`, cache explicitly disabled in the enforcing lane |
| shellcheck (CI recipe, 8 changed scripts) | clean |
| `check-lockstep-pairs.sh` | 28 anchors, 0 failed |
| `check-fail-open-shapes.sh` | 13 sites, all dispositioned — unchanged, so AC-6's reconciliation clause still holds |
| Suites at the reviewed head | `operator-override` 35/0 · `lean-gate` green · `check-lean-chain` green · `lean-evidence` green · `scenario-liveness` 69/0 · `orchestrate-lean` green · `run-selftests` PASS · `branch-prefix` green |
| Base merge is real and complete | `origin/main` == the merge's parent 2; recomputing `merge-tree` of the two parents differs from the landed tree in exactly the two files the commit message claims, and no others |
| `--help` range resolution (`orchestrate-lean.sh`) | 222 is correct for the merged file — first non-`#`, non-blank body line is 223 |
| **Probe A** — B-1 mutant 1: `delegate override` DELETED | `bash -n` clean → **`(AA1)` FAILS**. Round 1's exact mutant is now caught. |
| **Probe B** — B-1 mutant 2: typo'd to `delegate overide` | `bash -n` clean → **`(AA1)` FAILS**. The worse mutant (zero arms, zero violations, exit 0) is caught too. `(AA2)` stays green under both, which is correct — it is the non-vacuity arm, not the killer. |
| **Probe C** — W-1 mutant: pure reorder, append moved back ahead of the parse | **`(u1)` and `(u2)` both FAIL** (stray record present; destination record modified) while **`(u3)` stays PASS** — so they bind to the staging's timing and not to a dead writer. First attempt at this mutant mangled the block writer and failed `(u3)` as well; it proved nothing and was rerun surgically. |
| **Probe D** — suggestion mutant: affordance collapsed back to `${1%%,*}` | **`(yo4b)` FAILS** while `(yo4)` holds — the two-region case is a real kill criterion, not a restatement of `(yo4)`. |
| **Probe E** — the finding below, sandboxed with `--repo-root` pinned | `--issue` = `5<newline>../../../etc/x` → **rc=0, "✓ recorded override 1", record lands at `docs/etc/x-lean-override.md`** — outside `plansDir`. With the deleted numeric guard restored: **rc=2, nothing written.** The suite reports 35/0 either way. |

## Blockers

None.

## Warnings

**W-2 — the staged parse does not hold the record's path, and the comment asserting that it does
is why the guard was removed.** `plugins/dev-pipeline/tools/operator-override.sh:308-313`
(comment), `:314-342` (`cmd_record`). Carried forward from round 1's W-1, not escalated.

`record_path` (:165) interpolates `--issue` into the destination path **raw**. The reader's `awk`
is line-oriented and takes the first line matching `^issue:` (:226-232). Those two views of the
same value come apart on any value containing a newline: the validator sees a clean `issue: 5`
while the path builder used the whole thing. Probed in a sandbox (Probe E) — the record is written
outside `plansDir`, `record` exits 0 and prints `✓ recorded override 1`.

The reason this is a warning and not a blocker: `record` is only ever run by a human from the
command the refusal prints, the two wired consumers call only `check` (read-only), and no
untrusted input reaches `--issue`. Nothing is bypassed — an escaped record is invisible to `check`
and to the boundary alike, so it yields nothing; it is an orphan file. Round 1 scored the strictly
worse version of this same defect (where *every* malformed record landed) as a warning, and a
round-1 warning does not become a round-2 blocker.

What does need fixing before the next reader trusts it is the **claim**. Commit `02caa5c5` deleted
the numeric argument guard on the reasoning that it was unkillable — "deleted, every case stayed
green" — and wrote that conclusion into the code as a load-bearing comment: *"THIS IS ALSO WHAT
HOLDS THE PATH, which is why no separate check on `--issue` sits above."* Probe E falsifies both
halves. Restoring the guard refuses exactly the input the staged parse admits, so the guard **is**
killable; what was actually measured is the suite's coverage, not the guard's necessity. The
delete-it-and-see-if-the-suite-reds technique can only ever discover what the suite already tests,
and here it did not test this.

Either remedy closes it: restore the one-line `case "$issue" in ''|*[!0-9]*)` guard **and add the
newline case that kills it** (which also makes the guard non-redundant on the record), or leave
the guard out and delete the "THIS IS ALSO WHAT HOLDS THE PATH" sentence. What must not ship is a
comment stating an invariant the code does not have, on the exact line a future reader will cite
when removing something else.

## Suggestions

None this round.

## Not findings (checked, and they hold)

- **`record` ignoring `SECOND_SHIFT_REPO_ROOT`.** Not an inconsistency: `:50` documents that the
  variable names the *main checkout*, where the shared token lives, while `record`/`check` resolve
  the *caller's* repo (`--repo-root`, else `git rev-parse --show-toplevel`) because the record must
  land on the lane branch. D-11 records the reasoning. Confirmed live — a deliberately mis-rooted
  `record` printed exactly the carry-forward NOTE the design promises.
- **`mktemp -t <prefix>.XXXXXX`.** The established convention at eight existing sites
  (`mutation-sweep.sh`, `preflight.sh`, `lean-gate.sh` ×4, `check-lean-chain.sh`); not a new
  BSD/GNU dual form.
- **The `trap "rm -f '$staged'" EXIT` in `cmd_record`.** The only `trap` in the file, set after
  `mktemp` succeeds with no window between, in a script that runs one subcommand per process and
  is never sourced. `envfail` exits through it.
- **`preflight.sh` is in the diff** despite AC-6. One token added to the lockstep'd `SEAM_SCRUB`
  superset so a configured command lane cannot inherit `LEAN_ATTEND_MODE`. No gate behavior changes.
- **The single baselined mutation survivor.** `operator-override.sh::default::1b0909258639` — the
  `GH_CLI="${GH:-gh}"` fallback, carrying the same accepted verdict five other guards already have,
  and argued from the same fact: with the mutant token in place a `command not found` and an absent
  `gh` produce byte-identical rc-2 answers. The other three survivors from the first sweep were
  fixed with real cases rather than baselined.
- **The base merge's two hand-resolved conflicts.** Both are hand-maintained line numbers, not
  logic, and both resolutions verify: the `--help` extent is arithmetically correct for the merged
  file, and the `SELFTEST_JOBS` case took the base's superset. Every suite of a file the base
  touched is green above.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | inherited — `operator-override-selftest.sh` (a)–(g),(p) cover absent / corrupt / session-mismatch / run-mismatch / marked-headless / self-asserted-env, and **(g)** is the one AC-1 names: a hand-forged token resolves attended and still yields nothing. Untouched by this delta; suite re-run green at this head. |
| AC-2 | satisfied | inherited — (h)(i)(i2–i5) bind gate/region/issue/scope identity; (n) refuses persistence in a per-issue record; (m1–m5) cover the register's live / expired / unevaluable / unjustified / date-shaped rows. |
| AC-3 | satisfied | inherited — `orchestrate-lean-selftest.sh` (g1) rc=3 + `preflight-rejected-resumable` + byte-unchanged wording + `attendance: headless`; (g1b)(g2b)(ov1)(ov2)(ov3). (ov2)'s post-merge spawn-count correction (3→2) is in this delta and the suite is green. |
| AC-4 | satisfied | (yo1)–(yo5) inherited; **(yo4b) is new in this delta and probed** (Probe D) — two unresolved regions now print two commands, and reverting to the first-region-only form reds it while (yo4) holds. The affordance now does what its own sentence promises. |
| AC-5 | **satisfied** (round 1's guard gap is closed) | the record names gate/run/decision/scope; the yield path refuses before the record exists (yo4, ov1); the boundary refuses malformed and mis-expired records. The missing half — that the chain still *delegates* the arm — is now held by `(AA1)`/`(AA2)`, **probed against both of round 1's mutants** (Probes A and B). The local-gate residual is stated in `docs/pipeline-manifesto.md`. |
| AC-6 | satisfied | closed `OVERRIDE_GATES` enum with (k) proving a third gate is an error; `check-fail-open-shapes.sh` unchanged at 13 dispositioned sites, so no `fail-open-sites.tsv` row is owed; the only file outside the two consumers is `preflight.sh`'s one-token scrub-list addition, which changes no gate's behavior. |
| AC-7 | satisfied | inherited — `scenario-liveness-selftest.sh` `(lean-override)` composes an attended-session record through a HEADLESS milestone-1 run with `(lean-override-nv)` proving non-vacuity; 69/0 green at this head. `docs/pipeline-manifesto.md` carries the trust posture. |

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass (1 minor) | 1 | 90 |
| Test Coverage | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Orchestrator (this session) | Pass (1 warning) | 1 | 95 |

No reviewer went dark this round; round 1's `test-coverage-reviewer` gap did not recur.
`a11y` + design-fidelity were not routed — no changed path matches
`stageParams.webComponentGlobs` (key absent; default `apps/web/**/*.{tsx,jsx}`). Not a coverage
gap: this is a pure-shell repo with no web-component surface.

**Ready to merge?** Yes.

**Reasoning:** round 1's blocker is fixed at the right surface and both of its mutants now red in
`check-lean-chain-selftest.sh` and nowhere else; every other round-1 item is fixed and each fix
carries a case that dies when reverted. The one open warning is a defense-in-depth residue on an
operator-only entry point that bypasses no gate — but its comment asserts an invariant the code
does not have, and that sentence should not outlive this PR.
