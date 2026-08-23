# lean review verdict — #641

verdict=approve
run_id: review-641-pr648-3
session_id: 8d5ed576-1329-47fe-b403-0699a6c14d1e
rounds: 3
pr: #648
reviewed_head: 0734db7c2413b74da31c0e121393cf7a5fe4254e
reviewed_patch_id: bf9996f13f5ccf5c48f070ac0d715e108dd47e3d
inherited_patch_id: 144ab7cc17ee86bdc0a2ef5f49f78a1c0fb1c3b6
inherited_from_verdict: 439da23282134c6e34099bb9d150e7bd155116f0
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 3 — PR #648 (issue #641)

Range read: `439da23..HEAD` — one commit, `0734db7` "close round-2 blocker B6 and warning W1".
Inherits the coverage of `144ab7cc17ee` (round 2, `review-641-pr648-2`, needs-work).
Reviewed head: `0734db7c2413b74da31c0e121393cf7a5fe4254e`, re-checked unmoved against
`origin/claude/second-shift-641` immediately before this record.

**Verdict: approve.** Round 2's single blocker is closed on both of its halves, and round 2's
W1 is closed in **both** consumers rather than the one it named. Every claim the fix commit
makes was re-derived here rather than accepted: the four mutants it says now die, die; the
arithmetic it restates reproduces exactly; the operator amendment it leans on is in the issue
body where it says it is. Two acceptance criteria that earlier rounds could not settle —
AC-5's "still passes" and AC-6's nightly `prose-budget` clause — are settled here by running
both at HEAD and comparing against the base commit's own nightly.

I dismissed one scope-completeness blocker on evidence. That override is stated in full below
rather than buried, because it is the one judgment in this record a later reader might make
differently.

## Round 2's blocker: B6 — closed, both halves

### Clause (a) — the row-count bar

Resolved by operator amendment, which is round 2's own option (i), not by retiring rows.

I read the amendment at source: issue #641's body carries a dated section
*"Operator amendment — AC-7 clause (a), 2026-08-22"* moving the bar 170 → 168, with its
derivation (`180 retired − 15 added by the unified table − 3 net elsewhere`) and an explicit
refusal of the alternative — *"Retiring two arbitrary rows to satisfy a number I mis-derived is
precisely the behavior this recalibration exists to end."* Carried into the spec as **D-7**,
provenance user-answered. This is an operator correcting a constant they mis-derived at filing,
against the spec's own scope items — not a spec bent to fit a diff, which would itself be a
blocker.

Measured independently, counting non-comment non-blank rows across every committed `.tsv` at
both ends: `origin/main` **615** → HEAD **447** = **−168**, against a bar of 168. Per-file it
reproduces the spec's breakdown exactly (`−89`/`−65` prose-budget baselines, `−14`
selftest-slow-suites, `−10` mutation-slow-suites, `−2` selftest-sweep-baseline, `−2`
mutation-baseline, `−1` mutation-catalog, `+15` the unified timing table). ✓

### Clause (b) — net guard/test shell mass

`bash scripts/check-guard-budget.sh origin/main` from the reviewed head:
`base 50308, HEAD 50282 (delta -26)`, rc=0. No `Guard-mass:` trailer — checked with the
script's own anchored predicate (`git log origin/main..HEAD --format=%B | grep -cE '^Guard-mass:'`
→ 0). The four unanchored `Guard-mass` strings in the branch's commit messages are prose inside
backticks and do not match. ✓

### The stale record — closed, and the new number is right

Round 2's second half was the substantive one: the spec bullet stated a superseded `delta 0`.
It now states `base 50308, HEAD 50282 (delta -26)`, and the arithmetic it offers for the change
from round 2's `−33` checks out under measurement rather than assertion:

| | guard mass vs `origin/main` | the two touched selftests |
| --- | --- | --- |
| `7e0be28` (round-2 head) | `50275` (delta **−33**) | 1502 lines |
| `0734db7` (this head) | `50282` (delta **−26**) | 1509 lines |

`50282 − 50275 = 7 = 1509 − 1502`. The W1 fix cost exactly the 7 lines the bullet claims. The
PR body was restated to match and agrees with both figures.

This is the trap the run walked into once already — a measured AC re-stales on every commit that
touches a counted file, and restating it *before* the last commit is what left round 2's number
wrong. The build measured after, then amended. Correct.

## Round 2's W1 — closed in both consumers, probe-confirmed

W1 was a false coverage claim: `table()` hardcodes every fixture row at 99s, so
`check-sweep-bound-selftest.sh`'s `(a2)` case sat at 99s against a 10s bar and never constructed
the at-threshold boundary its success message named. The fix drops the row from `table()`'s args
and writes both boundary rows by hand at the exact seconds the case is about (9s under, 10s at),
and — beyond what round 2 asked — repairs the same gap in the other consumer, tabling
`tools/quick-selftest.sh` at exactly 9s in `run-selftests-selftest.sh`.

Probed on an isolated worktree at `/private/tmp/probe-641-r3`, one site mutated at a time,
each verified applied before scoring and restored diff-clean after:

| mutant | suite | result |
| --- | --- | --- |
| `check-sweep-bound.sh:109` `-ge` → `-gt` (deferral) | sweep-bound | **1 failure** — `(a2)` |
| `check-sweep-bound.sh:209` `-ge` → `-gt` (warning) | sweep-bound | **1 failure** — `(d)` |
| `run-selftests.sh:221` `-ge` → `-gt` (deferral) | run-selftests | **FAIL (2)** |
| `run-selftests.sh:358` dedupe `grep -qxF … && continue` neutered | run-selftests | **FAIL (1)** |

The first three reproduce the commit message's claimed `1, 1, and 2` exactly, against green
baselines (`0 failure(s)` / `PASS`). All three survived before this fix, per round 2.

**The fourth mutant is mine, and it is the question the fix invited.** Tabling
`quick-selftest.sh` moves the shared `$RSL` fixture's expected count from `1 excluded, 2 to run`
to `2 excluded, 1 to run`, which the explicit+table dedupe case asserts on — so the fix could
have quietly drained the one case that guards the dedupe. It did not: neutering the dedupe still
reds that case (rc=2, "every discovered suite is excluded"). I also walked every other `$RSL`
consumer (`--full` at :847, the stale-row cases at :871/:882, malformed at :889, directive-less
at :896) — the later ones overwrite the table, and `--full` ignores it. No sibling assertion was
weakened.

## The scope-completeness blocker I dismissed, and why

`scope-completeness-reviewer` returned `request-changes` with one blocker at confidence 88:
AC-5's second clause unsatisfied, because `install-topology-selftest.sh` exits rc=1 at HEAD. It
named its own remedy — *"evidence (last night's nightly-guards install-topology run on main)
that the red pre-dates this branch"* — and said plainly it could not gather that evidence within
budget. I gathered it.

| | result | the single red |
| --- | --- | --- |
| **base** `b8cc982`, nightly run [32615665437](https://github.com/manoldonev/second-shift/actions/runs/32615665437) (2026-08-23 03:33) | `53 ran, 52 passed, 0 known-red, 3 skipped, 0 stale row(s), 1 red` | `pipeline-doctor-selftest.sh — rc=1 — ok: (d3) completed + failed at 24h → never stale` |
| **HEAD** `0734db7`, my own run | `53 ran, 52 passed, 3 skipped, 1 red` | *byte-identical line* |

Same suite count, same pass count, same single red, same case. The base commit — this PR's own
base, on a nightly that ran **after** round 2 — already produces it.

**The reviewer's attribution is refuted on its own terms.** It reasoned that the staged-install
red is *"the context the now-deleted known-red allowlist used to be able to absorb"*. The base
nightly's own summary line reads `0 known-red`: the allowlist was **empty** at the base — drained
by #421, as the spec says — so it absorbed nothing, and deleting it cannot have exposed this. The
red is `pipeline-doctor-selftest.sh`'s `(d3)` case failing under a staged install, which this
diff touches only in ten decorative comment lines, and which is green in-repo at both ends.

The half of the remedy I cannot satisfy is "plus explicit deferral language in the issue" — an
operator edit to #641. I am not treating its absence as a blocker: rounds 1 and 2 both reached
this same conclusion on *weaker* evidence, and escalating on stronger evidence pointing the same
way would be incoherent. Requiring an operator ritual to record that a base-commit defect is not
this PR's is also precisely the shape #641 exists to abolish. The pre-existing red is real and
owes a ticket — see W6.

## Warnings

- **W4 (new) — the `nightly-guards.yml` rationale for the bash-3.2 twin now points at a file this
  PR deletes.** `.github/workflows/nightly-guards.yml:37` still reads *"Several
  install-topology-known-red.tsv rows are explicitly environment-dependent, so the bash-3.2 copy
  carries signal ubuntu does not."* That file is deleted by this PR, and it held 0 rows before
  that. Not a read path — AC-5's first clause is about read paths and is satisfied — and it gates
  nothing, so it is not a blocker. But it is the same class the run has now spent two rounds on:
  a record justifying a decision by pointing at something that no longer exists. It is a one-line
  fix in a file this PR already edits, and the PR rewrote the *neighbouring* comment block for
  #641 while leaving the one #641 invalidated. Found independently by
  `scope-completeness-reviewer` (nit, confidence 90).
- **W5 (new) — AC-7 clause (a) lands exactly on its bar with zero margin.** `−168` against
  "at least 168". Any committed `.tsv` row added to this branch before merge puts it under. This
  record is a `.md` and moves neither counter (verified after committing). Raised by
  `scope-completeness-reviewer` at confidence 70 and worth carrying to the merge boundary.
- **W6 (new) — the pre-existing staged-install red owes a ticket.** Three rounds have now
  dismissed `pipeline-doctor-selftest.sh`'s `(d3)` case failing under `install-topology-selftest.sh`
  as pre-existing and out of scope, correctly each time. Nobody has filed it. It reds the nightly
  `install-topology` job on `main` every night, and since #632 moved that guard off the PR lane it
  surfaces a day late by design. Naming it precisely so it is filable: `(d3) completed + failed at
  24h → never stale (terminal by contract)`, green in-repo, red only from the staged install cache.
- **W7 (new) — the PR body's verification list understates its own coverage.**
  It records `scripts/check-guard-budget-selftest.sh: 12/12`; the suite is **13 passed, 0 failed**
  at this head (the `ref-mechanism` case landed in the round-1 fix). Same record-accuracy class as
  B6's second half, but in the PR body rather than the committed spec, and wrong in the direction
  that under-claims — so it costs nothing and blocks nothing. The spec's own numbers are all
  correct.
- **W2 and W3 carried forward unfixed, as round 2 classified them** and as the spec's Build-time
  amendments now record by name. W2: `check-sweep-bound.sh`'s non-numeric-seconds `die` remains
  unguarded on that side (the same arm is well covered in `run-selftests.sh` — 72 failures). W3:
  four `scenario-liveness-selftest.sh` comments were reflowed rather than deleted, so four lines
  of the net-negative are reflow. Naming W3 in the spec is the right disposition for a PR that
  introduces a line-counting metric — it does not pretend the metric is unfoolable.
- **Round 1's four warnings still stand**, none addressed and none blocking: `# baseline-seconds
  106` living as a measurement inside the file whose own new rule forbids them; the `--seed`
  full-overwrite artifact; the silently widened PR-lane deferral set; the shell prose ratchet's
  narrowed coverage. The first remains the one worth a line somewhere.

## What I verified rather than inherited

Every AC was re-scored against the whole spec, as the round contract requires. These were
measured at this head rather than carried:

- **AC-6, both clauses, and the second one is new information.** My own sweep from the reviewed
  head, env-scrubbed (`-u CLAUDE_CODE_SESSION_ID -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL
  -u LEAN_SPAWN_PERMISSION_MODE`): `75 discovered, 1 excluded, 74 to run` →
  **`74 scored, 74 run, 0 served from cache, 0 failed`**, rc=0. Then the clause no earlier round
  checked directly — *"the nightly `prose-budget` job stays green"*. That job runs exactly
  `bash plugins/dev-pipeline/tools/prose-budget.sh`, unchanged by this PR's workflow edit. On the
  **base** it is **red**: run 32615665437 gives `4 fail(s), 27 warning(s)`, rc=4 — three markdown
  files past their `.claude/prose-budget.baseline.tsv` ceilings and one shell file past its
  `.claude/prose-budget-shell.baseline.tsv` ratio, plus 4 stale baseline rows. At **HEAD** the
  identical command gives **`0 fail(s), 17 warning(s)`**, rc=0. Every one of those four failures
  is a baseline-ratchet failure against a file this PR deletes. The clause is satisfied, and the
  honest framing is that the job goes green because the ratchet it redded on was deliberately
  retired — which is the ratified design (D-1, scope item 2), not an accident. Round 1's
  narrowed-coverage warning is the right place for the residual concern, and it stands.
- **AC-5**, upgraded from round 2's `undeterminable` — see the dismissal section above. Both ends
  measured directly rather than inferred.
- **AC-1**: 13 passed, 0 failed, run at this head.
- **AC-3**: `pr-gates` on run [32602447468](https://github.com/manoldonev/second-shift/actions/runs/32602447468)
  (`headSha 0734db7`) — step 5 *"guard budget guard"* **success**; steps 6 and 7 both **ran**,
  neither `skipped`. Step 7's failure is read from the log and is solely
  `verdict record … reads 'verdict=needs-work', not 'verdict=approve'` — this record's own
  precondition, and nothing else.
- **AC-4**: the unified table read at HEAD — one file, 15 rows, one date column; the five
  retired files absent; three consumers reading it (`run-selftests.sh` and `check-sweep-bound.sh`
  at the shared 9s directive, `mutation-sweep.sh` at its own hardcoded 5s).
- **AC-8**: the manifesto diff read directly — both paragraphs beside P4/P5, and
  `judgments, not measurements` occurs exactly once in the repo's prose, with `docs/testing.md:11`
  pointing at it rather than repeating it.
- `shellcheck -e SC1091,SC2015,SC2181` clean over the delta files and both consumers (local
  0.11.0; CI's 0.9.0 lane is green on this head).

## Strengths

- **W1 was fixed wider than it was reported.** Round 2 named one consumer; the build found the
  identical gap in the other and closed both. The pattern holds from round 2, where B2 was fixed
  by deleting the duplicate implementation rather than adding the fixture the review asked for —
  this build keeps answering the finding rather than the sentence.
- **The commit message's probe numbers are exact.** `1, 1, and 2 failures` is what I measured,
  independently, on my own worktree. A build that reports mutation results precisely enough to be
  falsified — and survives the falsification — is the thing that makes round 3 cheap.
- **The `(a2)` fix removes the hardcode rather than working around it.** `table "$T" 10` now takes
  no suite argument and both boundary rows are written by hand, so the case's success message and
  the fixture it runs against finally say the same thing. The rewritten comment states exactly
  which comparison the rows pin (`>=` vs `>`) instead of asserting coverage generically — the
  defect W1 was.
- **The operator amendment is argued, not asserted.** The issue body derives 168 from the spec's
  own scope items, says which mis-derivation produced 170, and refuses the row-deleting
  alternative by name. D-7 carries it as a departure rather than silently restating AC-7. That is
  the correct handling of a bar that turns out to be wrong — and the build did not touch a single
  register row to reach it.
- **This PR turns a red nightly job green.** `prose-budget` has been failing on `main` on four
  baseline rows; deleting the two baselines is what fixes it. Neither the PR body nor either
  earlier round noticed.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | `check-guard-budget-selftest.sh` **13 passed, 0 failed** at this head. Every case asserts the printed measured value. (PR body says 12 — see W7.) |
| AC-2 | **satisfied** | Inherited from round 2's single-arm mutation table (all 7 `is_guard_path()` arms + `classify_ref()`'s tree read). The delta does not touch the predicate or its fixtures; one implementation, so the property holds by construction. |
| AC-3 | **satisfied** | Run 32602447468, `headSha 0734db7`: step 5 success, steps 6 and 7 both ran, step 7 fails solely on `verdict=needs-work` (read from the job log). |
| AC-4 | **satisfied** | Verified at this head: five retired files absent, one 15-row `selftest-suite-timings.tsv`, three consumers with their own thresholds, conflicting old values resolved to single rows. D-6's shared-key departure recorded. |
| AC-5 | **satisfied** | Deletion clause: `install-topology-known-red.tsv` gone, no read path remains (one comment does — W4). Pass clause: HEAD `53 ran, 52 passed, 3 skipped, 1 red` vs base nightly `53 ran, 52 passed, 0 known-red, 3 skipped, 0 stale row(s), 1 red` — identical red line, and the allowlist held 0 rows at the base so it absorbed nothing. Scored on the no-regression reading; the literal "passes" is false at **both** ends, which is W6's ticket, not this PR's defect. This is the one score a reader might take differently — the override is argued in full above. |
| AC-6 | **satisfied** | Own env-scrubbed sweep: `74 scored, 74 run, 0 failed`, rc=0. Nightly `prose-budget` clause settled for the first time: red at base (`4 fail(s)`, rc=4), **green at HEAD** (`0 fail(s), 17 warning(s)`, rc=0) under the identical command the workflow runs. |
| AC-7 | **satisfied** | Clause (a): 615 → 447 = **−168** against the amended bar of 168 (D-7, operator-amended in the issue body — read at source). Clause (b): `base 50308, HEAD 50282 (delta -26)`, rc=0, no anchored `Guard-mass:` trailer. Zero margin on (a) — W5. |
| AC-8 | **satisfied** | Both paragraphs beside P4/P5 in the manifesto diff; `judgments, not measurements` occurs once repo-wide; `docs/testing.md:11` links rather than restates. `prose-budget.sh`'s cited one-clause pointer is a citation, not the second authority AC-8 forbids. |
| AC-9 | **satisfied** | `0734db7` carries `Changelog: none`; the branch's feature commit carries the consumer-visible entry with `Migration: none`. |

## Panel

scope-completeness ❌ (1 blocker, dismissed on base-commit evidence above; 1 nit upheld as W4) ·
maintainability ✅ (0 findings) · complexity ✅ (0 findings) · **test-coverage — `Dark (no output)`**.

**Coverage gap:** `test-coverage-reviewer` went dark — died after its automatic retry, emitting
no text on either attempt (`maxTurns` cap reached mid-exploration, the known emit-deadline stall
shape). Its domain was test coverage of the delta, which is this delta's entire substance, so I
am naming what stands in for it rather than letting the gap pass as green: I probed that domain
directly and adversarially — four mutants across three production files, every one applied,
verified applied, scored, and restored diff-clean, including one mutant the reviewers did not
propose (the dedupe). That is stronger evidence than the dark reviewer would have produced, but
it is my own work checking a fix, not an independent second reading, and the record should say so.

One usable result was returned by three of four reviewers, so the round is intact under Step 4b,
not void under 4b-void. a11y and the design-fidelity dimension were not routed: no changed path
matches the web-component surface and the repo declares no `stageParams.webComponentGlobs`.
`fidelity` scores `not-applicable` — the spec's `## Design` reads `Design: none — this is
shell/CI tooling with no rendered surface`, and the repo configures no `design.provider`, so the
unjustified-disarm blocker does not apply.

## Round mechanics

`run_id=review-641-pr648-3`, PR-scoped to match rounds 1 and 2 so this PR's rounds stay
distinguishable from the `review-641-*` ids spent on the abandoned PR #645. Reviewed on the
branch's own gate — the branch does not touch `lean-gate.sh`, so the installed 11.0.0 copy is the
branch's copy. Every probe ran in a throwaway worktree at `/private/tmp/probe-641-r3`, never the
lane worktree; both the probe worktree and the lane worktree were confirmed diff-clean at
`0734db7` afterwards. The head was re-fetched and re-checked unmoved immediately before this
record was written.
