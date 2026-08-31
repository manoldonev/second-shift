# lean review verdict — #739

verdict=needs-work
run_id: review-739-2
session_id: 5add023b-f0bd-40d3-92c4-4516fc85ec05
rounds: 2
pr: #750
reviewed_head: d3e741eaa0055f71a204fc41ffb4604b73a13afd
reviewed_patch_id: 2838072784f98adf47a8b93a423238a21da66ea8
inherited_patch_id: a6e3209933b2807f747b49ca18eddda1377a82f1
inherited_from_verdict: d3e741eaa0055f71a204fc41ffb4604b73a13afd
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: unknown
capabilities: pr-marker

Range read: `cf060ab1..HEAD` (FULL range — `bash G delta 739` reports nothing verifiable to
inherit; 24 files). Reviewed head: `d3e741eaa0055f71a204fc41ffb4604b73a13afd`.
Round 1's findings were read first and are carried forward below.

Panel: `review-toolkit:scope-completeness-reviewer` returned. `review-toolkit:test-coverage-reviewer`
was selected and went **dark** (stopped at its turn limit with no report); its intended subject —
coverage of the new gate arms — is covered by first-party greps below, so the round is not voided.

**Verdict: needs-work.** Two blockers, both introduced by the rebase onto `cf060ab1` (v12.2.2)
rather than by any edit of this branch, and both the same defect in two places: the branch's
claude-design plan grammar is one release behind the gate's.

## Why this round exists

Round 1 approved head `1854bd35` against base `c68d2321`. The branch was then rebased onto
`cf060ab1`, and the rebase resolved a conflict by **altering one of the branch's own `+` lines**.
Verified by diffing the two branch diffs: everything else is blob-index and hunk-offset churn, and
the single content change is `design_plan_gate`'s absent-plan refusal, which absorbed main's
`$PLAN_NODE_COLUMN`/`$PLAN_RS_COLUMN`/`$PLAN_PX_COLUMN` clause from #711/#744 on both its `-` and
`+` sides. That is the "conflict resolved by editing a line" case, so the round-1 record is void:
`reviewed_patch_id a6e32099` (which I reproduced exactly against the old base, confirming I had
the formula right) is now `2838072784`.

**`pr-gates` is green on a documented fail-open, not on a pass.** Run `33433003571` at this head
logs, from the gate's own mouth:

> `· freshness: reduced-strength — the patch identity moved from a6e3209933b2 to 2838072784f9 and
> the +/- comparison could NOT be computed, so this arm FAILED OPEN and the verdict stands`

The comparison could not be computed because the force-push orphaned `reviewed_head 1854bd35`, so
the CI checkout holds no object to resolve it against. Running the identical gate **locally**,
where that object still exists, returns the violation:

> `✗ verdict record … reviewed patch a6e3209933b2, but this branch's diff against origin/main now
> hashes to 2838072784f9 and the branch's own lines moved with it: 2 reviewed line(s) across 1
> file(s) … Run another review round.`

Recorded for the operator, and it generalizes past this PR: on a **rebase**, this lane's
merge-boundary freshness arm cannot see staleness, because the evidence it needs is exactly what
the force-push destroys. Green there is not evidence that a verdict covers the head.

## Blockers

### B-1 — `design-faithful`'s new plan step under-specifies the plan the gate now demands, so an armed claude-design run that follows its own documentation burns a fix attempt (AC-3)

`plugins/design-toolkit/skills/design-faithful/SKILL.md:54-55` mandates exactly two tables — a
`why this component` table and a `dimensions` table. At the rebased base, `_plan_table_walk`
(`lean-gate.sh:4060-4064`) additionally requires **`node`, `rs` and `px` columns on the table that
declares `dimensions`**. That check is family-agnostic: it keys on the `dimensions` column, not on
the design family. It did not exist at the old base —
`git show c68d2321:…/lean-gate.sh | grep -c PLAN_NODE_COLUMN` → **0**.

Proved, not argued. I extracted the guard's awk verbatim and ran a plan written to the letter of
the new step:

```
the table declaring a "dimensions" column declares no "node" column — …
the table declaring a "dimensions" column declares no "rs" column — …
the table declaring a "dimensions" column declares no "px" column — …
```

Control: the figma-shaped plan from `figma-faithful/SKILL.md:199-206` through the same probe →
**zero violations, rc 0**. The check is sound; the design-faithful step is what is short.

Those violations feed `fail_milestone 3` (`lean-gate.sh:4272`), and `fail_milestone` calls
`append_attempt` (`:1550`) — it **charges a fix attempt**, unlike the absent-plan
`block_milestone` path. The mitigation that the absent-plan refusal now lists the three columns
does not reach this path: a run that followed the step has *written* a plan, so it never sees that
refusal.

Three things make this the slice's own thesis rather than an imported standard:

- The spec's stated purpose is the producer side — D-1: "only `figma-faithful` step 7 says how to
  write one; without a claude-design step the new reviewer grades an artifact improvised against a
  gate error string." At this head that is still true, in a narrower way.
- **D-3's own rule now mandates the columns.** It admits "only what a reader exists for". A reader
  now exists: `plan_violations` grades them, and `plan_node_rows` (`:4114`, consumed at `:4610`)
  compares the `px` values against the rendered rects.
- The agent this slice ships does not grade them either — `### Per-node dimensions`
  (`design-faithful-plan-reviewer.md:128-141`) checks only the prose `dimensions` cell. So the
  gate, the step and the agent disagree about what a complete claude-design plan is.

**Why no suite caught it.** The only plan fixture in `lean-gate-selftest.sh` is figma-shaped
(`DPLAN_DROW`, `:3711` — `| node | RS | px | dimensions | overflow |`), and `(dpr7)`, the sole
claude-design case, calls `dplan_sync` and reuses it. No test anywhere exercises a plan written to
the design-faithful step's documented shape.

### B-2 — the eval fixtures encode that same stale grammar, and the clean control's `must_not_flag` trains the reviewer to pass a plan the gate rejects (AC-6)

All three fixtures carrying a dimensions table use `| node | dimensions | overflow |` —
`02-name-match-resolution.md:34`, `03-unwired-state-no-analog.md:36`,
`04-control-clean.md:45`. Run through the same extracted walker,
`04-control-clean.md` yields:

```
the table declaring a "dimensions" column declares no "rs" column — …
the table declaring a "dimensions" column declares no "px" column — …
```

(twice, once per dimensions-declaring table). The control is the sharpest case, because
`04-control-clean.expected.json:6` lists under **`must_not_flag`**:

> "the `dimensions` table — one row per sized node, each with an overflow decision, including the
> wrap-then-scroll behavior of the chip rows"

So the instrument's calibration case explicitly scores a reviewer *down* for flagging a plan shape
milestone 3 refuses outright. Independently raised by scope-completeness and reproduced here.

**Disposal for both** (small and mechanical, and free right now): give the step the three columns
as `figma-faithful` step 7 carries them, with the worked example; extend the agent's Per-node
dimensions check to the same triple; re-shape the three fixtures and correct the control's
`must_not_flag`. Because the baseline is **OWED** (D-14/OR-1), fixing the corpus costs nothing
today and costs the reading once one is taken. Do **not** relax the gate.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied, deviation recorded | Frontmatter is the artifact-stage shape; no token-arithmetic section. Checklist ships **seven** sections — `Placement` (`:143`) beyond D-2's six. Carried from round 1: the deviation runs safe and D-3/AC-3 mandate a placement decision, so the AC's enumeration is short, not the code. AC-4 was amended in flight (`513ac83d`) and AC-1 was not; one word at `docs/plans/second-shift-739-lean.md:19-23` closes it. |
| AC-2 | satisfied | `design_family_plan_reviewer()` resolves `claude-design` (`lean-gate.sh:3225-3231`). `(dpr7)` asserts rc 1, the namespaced agent name, no `figma-faithful-plan-reviewer`, no `ships no plan-stage reviewer`, **0** milestone-3 attempts, **0** render calls. PASS in my own full run. |
| AC-3 | **unsatisfied** | B-1. The AC's criterion is stated by reference to "the two **gate-asserted** tables"; at this head the gate asserts three further columns on the `dimensions` table and the step mandates none of them. Under the narrowest literal reading the two named tables are present — but D-1's purpose, which is what AC-3 encodes, fails either way. |
| AC-4 | satisfied | `(dpr7)` inverted (`:4522-4546`); catalog row 140 re-anchored onto the `claude-design)` arm. Re-probed at THIS head — see Mutation evidence. |
| AC-5 | satisfied | Both oracles re-run from this checkout: `git grep -n 'DOES NOT EXIST' -- ':!docs/plans/'` and `git grep -n 'OR-1 of' -- ':!docs/plans/'` → no output. The `ships no plan-stage reviewer` refusals survive, describing the unreachable `*)` fall-through. |
| AC-6 | **unsatisfied** | B-2. Structurally complete — `rubric.py`, `run.sh`, `README.md`, `changelog.md`, `CLOSEOUT-BASELINE.md` recording OWED, four fixtures with `.expected.json` siblings; `check-eval-model-identity.sh` rc 0 over 97 files. But the corpus encodes a plan grammar the current gate rejects, and the control's `must_not_flag` entrenches it. |
| AC-7 | satisfied | The `<provider>-faithful-plan-reviewer` template survives only in `docs/plans/` records and a triage row's rationale prose — not in `build-lean/SKILL.md:27`. |
| AC-8 | satisfied | `docs/extension-points.md:20` names the agent; `evals/README.md:3` reads "Four eval directories", the table carries the row, the campaign table carries the `OWED` row. |
| AC-9 | satisfied | `prose-blockers.sh check` rc 0 — 28 constructs over 52 files, 50 rows, zero undispositioned. |
| AC-10 | satisfied | `check-gate-buckets.sh` rc 0, `check-lockstep-pairs.sh` rc 0 (29 anchors), `check-reviewer-references.sh` rc 0. `e56a7976` takes `feat(design-toolkit):` with a consumer-facing `Changelog:`. |

Design fidelity: **not-applicable** — the spec declares no `## Design` section and no `RS-n` rows.

## Majors carried forward from round 1 (re-verified at this head, none blocking)

1. **`design_plan_gate`'s family selector still has zero coverage on either arm.**
   `grep -c 'translation-plan step\|step-7 plan'` over `lean-gate-selftest.sh` → **0**, over
   `tools/mutation-catalog.tsv` → **0**. A mutant collapsing or swapping the two arms survives the
   full suite. Not a blocker: it selects the *guidance text* of a refusal that fires identically
   either way. B-1's disposal is the natural place to fix it.
2. **AC-1's enumeration is one section short of the code** — see AC-1 above.
3. **The control fixture is not demonstrably clean** on a second, independent axis from B-2:
   `04-control-clean.md`'s ledger row D-1 resolves the signing secret "Rotate-only — the field is
   read-only", while `:39` resolves it to an editable `TextField type='password'` with a reveal
   `endAdornment`, and nothing mounts a Rotate control. A correct reviewer flags that and scores
   0 of 6 on the control. Same free-to-fix window as B-2.

## Mutation evidence

`mutation-sweep-pr` went green in **15s having graded nothing** — the sole in-scope guard is
deferred as a slow suite — so the re-anchored row has no CI oracle at this head either. Probed by
hand, in an isolated detached worktree at the reviewed head (never the reviewed checkout):

- Applied row 140's sed with `sed -E`, as `tools/mutation-sweep.sh` applies it. It edits **exactly
  one line** — deleting `    claude-design) printf 'design-faithful-plan-reviewer' ;;` — leaving
  the `figma)` and `*)` arms intact. Not a vacuous mutant. (Under plain BSD `sed` the row's `\)`
  is unbalanced and the mutant no-ops, which would read as a vacuous green.)
- Full suite against the mutant: **exactly 1 failure across 588 cases**, and it is the declared
  killer — `FAIL: (dpr7) rc=1 attempts=1 renders=2`. The mutated gate declined the mandate, walked
  past it into the render pass (`renders=2` against `0` unmutated) and charged a fix attempt.
- Unmutated at the same head: `all green`, 588/588.

## Verification I ran, rather than cited

- **`lean-gate-selftest.sh` in full at this head** — `all green`, exit 0, **588** cases (up from
  round 1's 570; main added cases in #742/#744/#749). Run separately because milestone 3's
  slow-suite table defers it.
- **Five guards from this checkout**, all rc 0: `check-gate-buckets.sh`, `check-lockstep-pairs.sh`,
  `check-eval-model-identity.sh`, `check-reviewer-references.sh`, `prose-blockers.sh check`.
- **The extracted-awk probe, its figma control, and the fixture runs** — the evidence for B-1/B-2.
- **`lean-evidence.sh --arms freshness` locally**, which is what exposed the CI fail-open.
- **Both CI selftest jobs pass at this head** — `lint-and-selftests` (4m39s) and
  `selftests (macos, bash 3.2)` (5m12s), run `33433003571`, head `d3e741ea`, both `pass`. Cited,
  not re-run: same command and same head as the repo recipe.

**Census figures moved with the base, not the branch.** `check-gate-buckets.sh` now reports
310 sites / 166 rows against round 1's 305 / 161 — main's additions absorbed by the rebase. No
branch line moved them.

## Dismissed

- **The scope-completeness FAIL on issue item 3's second clause**, dismissed on authority in round
  1 (D-5/D-6 record the departure in the branch's first commit and in the pre-flight ledger, and
  the `*)` arm is unreachable through every public entry point). Unchanged at this head; the
  dismissal stands and I did not re-litigate it.
- **`mutation-sweep-pr` green** — vacuous, as above. Recorded so no later reader mistakes it for
  mutation coverage.
- **D-8 and D-13 respected** — nothing in the diff touches `scenario-liveness-selftest.sh` or the
  closed #710 records.
