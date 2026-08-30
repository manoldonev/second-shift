# lean review verdict — #704

verdict=needs-work
run_id: review-704-2
session_id: 945304c5-2896-42ab-84ba-8aecd53c0dc5
rounds: 2
pr: #713
reviewed_head: 373096a319d685bae1d0c3a169bd7470a0db3d93
reviewed_patch_id: 28470ade906bf7f00741b9d1f1f40e3cd5c5f303
inherited_patch_id: 1214fc71cff081219b20b7bafe23e272142c8fa3
inherited_from_verdict: 8d6e3b08d5ff471ef5db7c18a9411df217911a1f
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #713 (issue #704)

**Range read:** `8d6e3b0..HEAD` (3 files), inheriting the coverage of patch `1214fc71cff0`.
**Reviewed from:** `/Users/mdonev/github/second-shift-worktrees/704` @ `373096a`.

Panel: 7/7 reviewers alive, **none dark** (security, performance, maintainability, complexity,
test-coverage, pipeline, scope-completeness). `a11y` + design-fidelity not routed: no changed path
matched `stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). Round 1's
findings were read first.

## Verdict

**needs-work** — two blockers in the record itself, plus a red correctness lane.

Round 1's B1 is **fixed and independently re-verified**. Both new blockers are the *same failure
mode as B1, recurring inside the fix commit*: a partial rewrite corrected a claim in one place and
left the identical claim standing, uncorrected, elsewhere in the same file.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | `.../figma-faithful-spec-reviewer-eval/CLOSEOUT-BASELINE.md:95` | The `d3` over-reach claim is false in every clause, and contradicts the corrected table at `:39` in the same file. It asserts the **control fixture** over-reached; it scored a perfect 6/6. |
| B2 | **Blocker** | `docs/plans/second-shift-704-lean.md:176` (D-13 row) | "All three are rewritten in the **D-2 lockstep commit set**" is false, and is contradicted by the prose form of D-13 at `:142-143` edited in the same commit. |
| B3 | **Blocker** (infrastructure — re-run to discharge) | CI `selftests (macos, bash 3.2)` | Red at this head on `scenario-liveness-selftest.sh` `(lean-inline-m3-nv)`. Did **not** reproduce locally; no causal path from the diff. Evidence below. |
| W1 | Warning | `docs/plans/second-shift-704-lean.md:213-216` (AC-7) | AC-7 says the two near-misses "are in the grep set" — but the grep it names is D-13's `N/A` sweep, and **neither cited line contains `N/A`**. They are hits of the broader `reached nothing` sweep, which D-13's row names and AC-7 drops. |
| N1 | Note | `results-*.json` `agent_sha` vs baseline headline | The kit stamps `agent_sha` from `git rev-parse HEAD` in `--repo-root`, so the JSON records `fee85c8` while the headline states `6dd9f70`. The headline is **correct** (last commit touching the prompt); the same-named JSON field is not the same quantity. A re-deriver comparing them gets a false mismatch. |
| N2 | Note | `.../CLOSEOUT-BASELINE.md` provenance | Raw results are **gitignored**. I could re-derive B1 only because the build worktree still holds `results-20260830T145540Z.json`; on a fresh clone nothing in the repo can falsify the per-dimension tables. `373096a`'s commit message calls it "the committed results-…json" — it is not committed. |
| N3 | Note | issue #704 body | Scope-completeness returned **FAIL** on AC-3 (and the prose "one autoresearch campaign per agent"), because the issue body still lists AC-3 unqualified. The pre-flight ledger's D-1 re-cut overrides it and the committed spec is the definition of done, so this is **not** a blocker — same disposition as round 1's N2. Amending the issue body is operator authority, not this lane's. |

### B1 — the corrected table and the uncorrected prose now disagree, and the prose libels the control

`373096a` rewrote the `d3_no_fabrication` Notes cell (`:39`) to read *"fixture 01 is **clean** here
(6/6) — the 6 lost points are fixtures 02 (2/6) and 03 (4/6)"*. That correction is **exactly right**;
I re-derived it from `.detail[fixture].runs[].per_dim` in `results-20260830T145540Z.json`.

Fifty-six lines later, `:95` still says:

> The three over-reaches on `d3_no_fabrication` (one run each on fixtures 02, 03 and 04) are the
> secondary signal: a mild tendency to add a Warning the fixture's ground truth calls correct.

Ground truth, per-run `d3` (max 2/run):

| fixture | run 0 | run 1 | run 2 | total |
| --- | :-: | :-: | :-: | ---: |
| 01 | 2 | 2 | 2 | 6/6 clean |
| 02 | 1 | 1 | 0 | 2/6 |
| 03 | 2 | 2 | 0 | 4/6 |
| **04 (control)** | 2 | 2 | 2 | **6/6 clean** |

Four independent falsehoods in two sentences:

1. **"fixtures 02, 03 and 04"** — fixture **04 is the control and lost nothing on `d3`**. Its only
   deduction is run 2 (`d1`=4, `d2`=1). A measurement record asserting the control fabricated
   findings is the precise failure `## The control fixture was corrected before this baseline`
   exists to prevent, one section earlier in the same file.
2. **"one run each"** — fixture 02 over-reached in **all three** runs.
3. **"three over-reaches"** — four runs carry a deduction, and by the judge's own justifications the
   fabricated-finding count is ≥ 7: *"At least two Warnings directly contradict must_not_flag"*
   (02 run 2), *"At least three Warnings contradict must_not_flag items"* (03 run 2).
4. **"a mild tendency to add a Warning"** — two of the four runs hit `rubric.py`'s **most severe**
   `d3` band (`0` = "two or more are, or any single one is extreme"), and 02 run 0's over-reach was
   a **Blocker** (F3), not a Warning.

Why this is a blocker rather than a nit: the sentence's conclusion — *"Worth watching during a
campaign, not worth a prompt edit on n=3"* — is operational guidance handed to **#707**, whose first
act is re-measuring against this file. It points #707 at the wrong fixtures and understates the
severity band. And `373096a`'s own commit message states the correction — *"on `d3` fixture 01 is
clean at 6/6, so 'spread across fixtures 02-04' was wrong about the control too"* — so the build
knew the claim was false and fixed only one of its two occurrences.

**Fix:** rewrite `:95` from the table above. Suggested: *"Four of twelve runs over-reached on
`d3_no_fabrication`, all on fixtures 02 (3 runs) and 03 (1 run); two of them hit the rubric's `0`
band. Fixtures 01 and 04 are clean at 6/6 — the control fabricated nothing. Worth watching during a
campaign, not worth a prompt edit on n=3."*

### B2 — D-13's row misattributes the commit, and contradicts its own prose form

`docs/plans/second-shift-704-lean.md:176`, the D-13 Resolution cell, ends:

> **All three are rewritten in the D-2 lockstep commit set.**

The prose form of D-13, at `:142-143`, edited in the **same commit**, states it correctly:

> All three are rewritten on this branch: the two agent files in the lockstep commit,
> `lean-gate.sh` in the round-1 fix that also corrected this row.

The prose is right and the row is wrong. Verified:

- `git show --stat 086b336` (the D-2 lockstep commit) touches **only** the two agent files.
- `git log --oneline origin/main..HEAD -- .../lean-gate.sh` returns exactly one commit: `373096a`,
  the round-1 fix.

This is a blocker for the same reason round 1's B1 was: D-13 is the ledger row AC-7 is scored on,
and a reader re-deriving it gets two different answers from one file. It is a six-word fix — replace
the sentence with the `:142-143` formulation.

### B3 — `selftests (macos, bash 3.2)` is red, and I could not reproduce it

`scenario-liveness-selftest.sh` (rc=1), 167s: `FAIL: (lean-inline-m3-nv) a lane child outlived the
gate's process group — milestone 3 detached`. Suite summary `73 passed, 1 failed`; runner summary
`78 scored, 77 run, 1 served from cache, 1 failed (0 infrastructure)`.

I am recording this as a blocker because the skill's rule is unconditional — a red `selftests` lane
is evidence about the code. But **do not go looking for a code fix**; every discriminator I ran says
it is the runner:

| Probe | Result |
| --- | --- |
| macOS job at `8d6e3b0` (this commit's parent) | **success** |
| macOS job at `086b336` (round 1's head) | **success** |
| macOS job on `main`, `release/next`, `#663`, `#664`, `#674` (11 recent runs) | **success** — the red appears only at `373096a` |
| `lint-and-selftests` (Linux, same `--full` suite set) at this head | **pass** |
| The suite re-run locally on macOS at this head | `(lean-inline-m3-nv)` **PASSED** |
| Causal path from the diff | none — the `lean-gate.sh` hunk is 100% `#`-comment lines |

My local run did fail one *different* case, `(lean-override)`, which is the known `LEAN_ATTEND_MODE`
environment leak in my shell (`build-state='headless (marked-headless)' (want headless)`) and not
the CI failure.

The assertion is a **5-second budget** (`50` × `sleep 0.1`) for a process group to become
unreachable after `kill -9 -$pgid`. `kill -0 -$pgid` succeeds while any member is still a
not-yet-reaped zombie, so on a loaded runner — this job ran 78 suites at concurrency 4 — the budget
can be exceeded without anything having detached. **Re-run the lane; if it goes green the blocker is
discharged with no code change** (and, changing no line, it does not void a subsequent record).

### Recorded, not a blocker — `pr-gates` guard-budget

`pr-gates` fails at this head, and the failing step has **moved** since round 1: it is now
`guard budget guard`, not `lean chain reconciliation`. Read from the job's step list, because that
job's shell is `-e` and the two steps after it never ran:

```
✓ frozen files guard      ✓ changelog trailer guard
X guard budget guard      - pipeline chain reconciliation   - lean chain reconciliation
```

Reproduced locally: `guard/test shell mass grew by 1 lines with no reason recorded: base 53291, HEAD 53292`.

This is a **policy** gate, so per the lane's rule it is recorded and does not itself make the verdict
`needs-work`. Two things the build should know:

- **Round 1's own record caused it.** B1's fix note asserted *"a `Guard-mass:` trailer is not owed
  for a comment-only edit inside an existing script … comment-only sites are excluded."* That is
  false — the guard counts raw shell lines, comments included, and the fix split one comment line
  into two. My round-1 counterpart got this wrong and the build reasonably acted on it.
- **Add the trailer on a NEW commit, do not `git commit --amend`.** The guard's hint says to amend,
  but `373096a` is under the round-1 verdict record; rewriting it rewrites that record's commit.
  Trailers are extracted grep-anywhere across the branch, so an empty commit carrying
  `Guard-mass: +1 <reason>` clears it and leaves every reviewed line intact (precedent: #637).

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Inherited from round 1, which verified it structurally (flat `glob("*.md")` discovery, every `run.sh` flag present in `run-eval.py`'s argparse, namespaced agent names). This delta changes no eval structure. |
| AC-2 | **satisfied** | All four mandated shapes present in all three baselines. The per-dimension table this delta corrected is now **exactly right** — re-derived by me from the raw per-run JSON, not read: d1 52/72 (01 = 0/18, 02 = 18/18, 03 = 18/18, 04 = 16/18), d2 17/24 (0/6, 6/6, 6/6, 5/6), d3 18/24 (6/6, 2/6, 4/6, 6/6); per-fixture 6+26+28+27 = 87/120 = 72.50%, every percentage exact. Sibling baselines re-derived too: reviewer 120/120, plan-reviewer 119/120 (the single lost point is fixture 03 run 2, `d3`=1) — both match their prose. **B1 is a defect inside this file that AC-2's enumeration does not reach**, not an unmet AC. |
| AC-3 | **satisfied** | Out of scope per D-1. No baseline reports a post-edit re-measurement; all three read `Campaign status: OPEN — baseline only` and name #707, which is open and cross-links. See N3 on the scope gate. |
| AC-4 | **satisfied** | Inherited; delta touches neither agent file. Re-confirmed at this head that no sentence in either claims the old behaviour, and additionally checked the one thing a lockstep pair can hide: `figma-faithful-plan-reviewer.md:148`'s `LOCKSTEP-BEGIN artifact-reviewer-baseline-deltas` block is held verbatim to the spec reviewer, but its subject is reviewer-baseline deltas, **not** the `N/A` condition — so AC-4's edit could not have drifted a mirror. |
| AC-5 | **satisfied** | `373096a` carries `Changelog: none`; no `plugin.json` `version`, `CHANGELOG.md` or `marketplace.json` in the delta. `frozen files guard` and `changelog trailer guard` both green at this head. |
| AC-6 | **satisfied** | Re-run at `373096a`, not inherited: `check-eval-model-identity.sh` → `✓ 86 runnable eval file(s)`; `shellcheck -e SC1091,SC2015,SC2181` clean on all three `run.sh`; `jq empty` clean on all twelve `*.expected.json`. |
| AC-7 | **satisfied** | Round 1's blocker is discharged. `lean-gate.sh:3775` now reads *"an agent that, at the time, returned N/A … (narrowed by #704's AC-4 — a lean-lane spec is in scope for it now)"*, which is accurate against the branch's agent prompt. I re-ran the sweep rather than accepting the correction: the literal `N/A` grep over `*.md`/`*.sh`/`*.mjs`/`*.json` outside `docs/plans/` returns **no fourth stale site**, and a deliberately broader sweep (`reached nothing`, `deferred to an agent`, `no owner on the lean lane`, `declines`, plus every reference to the agent by name and to the old `Copy Index / Components / Screens` condition) returns only sites that are already correct. Both discharged near-misses check out: `lean-gate-selftest.sh:3987` and `scenario-liveness-selftest.sh:1370` state the pre-#694 condition in the past tense and assert nothing about current behaviour. `figma-faithful-spec/SKILL.md:13,107` references the agent but not its `N/A` condition. **B2 and W1 are about the accuracy of the row that records this measurement, not about the measurement**, which holds. |

## CI

| Lane | Result |
| --- | --- |
| `lint-and-selftests` | **pass** (4m33s) |
| `selftests (macos, bash 3.2)` | **fail** (6m54s) — B3; one case, not reproduced, green on the parent commit and on Linux |
| `mutation-sweep-pr` | **pass** (16s) — honest defer, no in-universe guard touched by the delta |
| `pr-gates` | **fail** on `guard budget guard`; recorded above, not a review blocker |

## Design fidelity

`not-applicable` — the spec carries no `## Design` section and declares no `RS-n` render states, so
step 5b is not armed. Consistent with D-16: the design arm and `review-lean` step 5b are #705's.

## Strengths

- **The round-1 fix re-ran the reviewer's measurement instead of trusting it,** and found an error
  round 1 missed — that `d3`'s "spread across fixtures 02–04" was wrong about the control. That is
  the right instinct, and it is why B1 is a half-applied fix rather than an undetected one.
- **D-13's count was corrected rather than quietly widened.** The row says "three sites, not two —
  corrected at review round 1" and keeps the miss visible. A row that silently changed `two` to
  `three` would have erased the only evidence that the AC's re-run requirement did any work.
- **The near-misses are discharged in the AC's text,** so the next re-run does not re-triage
  `reached nothing` hits that are correct. Both check out.

## Reading beyond the delta

Read wider than `8d6e3b0..HEAD` in four places, none of it inherited: the whole
`CLOSEOUT-BASELINE.md` (which produced B1 at `:95`, outside the changed hunks); the D-13 prose form
at `:140-144` against the row at `:176` (B2); the raw `results-*.json` for all three evals,
per-run and per-dimension, plus the judge justifications; and the full `N/A` blast-radius sweep
re-run at this head with a broader regex than the branch used.
