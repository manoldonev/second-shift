# lean review verdict — #739

verdict=approve
run_id: review-739-1
session_id: 6c6cf9a5-9a8b-4aae-8c96-c3ed3b40d896
rounds: 1
pr: #750
reviewed_head: 1854bd3530c7298236974693e9cc4a62e0cf8e1f
reviewed_patch_id: a6e3209933b2807f747b49ca18eddda1377a82f1
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #750 (issue #739)

Range read: `c68d2321..HEAD` (root round, whole branch diff — 23 files, +1111/-29).
Reviewed head: `1854bd3530c7298236974693e9cc4a62e0cf8e1f`.
Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.

**Verdict: approve.** No blockers. Three majors are recorded below; each is either a
spec-wording correction or a cheap follow-up, and none of them makes an `AC-n` unmet in
substance.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — agent file, artifact-stage frontmatter, checklist = the D-2 set, no token arithmetic | **satisfied, with a recorded deviation** | `plugins/design-toolkit/agents/design-faithful-plan-reviewer.md` carries `model: opus`, `effort: high`, `tools: Read, Grep, Glob, Bash`, `skills: reviewer-baseline`, no `maxTurns`. No token-arithmetic section — the load-bearing clause — and `## What this plan is NOT` states why. The checklist ships **seven** sections, not six: a `### Placement` section beyond the D-2 enumeration. See major 2. |
| AC-2 — `design_family_plan_reviewer()` resolves `claude-design`; `bash G 3` reds before any render naming the agent, spending no fix attempt | **satisfied** | `lean-gate.sh:3220-3226`. The absent-record arm is `block_milestone 3` (`lean-gate.sh:4131`), which by construction writes no `\| milestone-3 \| attempt \|` line. Asserted by the inverted `(dpr7)`: `rc=1`, output contains `design-toolkit:design-faithful-plan-reviewer`, does **not** contain `figma-faithful-plan-reviewer` or `ships no plan-stage reviewer`, `attempts=0`, `renders=0`. |
| AC-3 — `design-faithful/SKILL.md` plan step, its mandated contents, the dispatch-and-record obligation, no token map | **satisfied** | New `## Write the translation plan (pre-implementation gate)` section: the `<plansDir>/<key>-lean-plan.md` path, the `planned_from:` header, the `why this component` and `dimensions` tables, the analog, the placement decision, the file list, the explicit **No token map table** paragraph, and the lean-lane dispatch/record obligation naming `lean-gate.sh plan-review`. |
| AC-4 — `(dpr7)` inverted; catalog row re-anchored onto the `claude-design)` arm; mutant probed and killed | **satisfied** | `(dpr7)` rewritten at `lean-gate-selftest.sh:4446-4479`; `tools/mutation-catalog.tsv:140` sed is now `s#^    claude-design\) printf .design-faithful-plan-reviewer. ;;$##`. **Independently probed** — see Mutation evidence. |
| AC-5 — the stale-gap prose is gone, on a decidable oracle | **satisfied** | Ran both oracles from the reviewed checkout: `git grep -n 'DOES NOT EXIST' -- ':!docs/plans/'` → rc 1, no output; `git grep -n 'OR-1 of' -- ':!docs/plans/'` → rc 1, no output. The `ships no plan-stage reviewer` refusals survive at `lean-gate.sh:4117` and `:4262`, both now describing the unreachable `*)` fall-through. |
| AC-6 — the eval instrument ships; `check-eval-model-identity.sh` green | **satisfied, with a fixture caveat** | Four flat fixtures each with an `.expected.json` sibling, `04-control-clean` the control; `rubric.py`, `run.sh` (`--agent-name design-toolkit:design-faithful-plan-reviewer`), `README.md`, `changelog.md` (no rows, states why), `CLOSEOUT-BASELINE.md` recording **OWED** with the installed-cache reason and the operator recipe. `bash scripts/check-eval-model-identity.sh` → rc 0, 97 runnable eval files. The control's cleanliness is major 3. |
| AC-7 — step 6 drops the `<provider>-faithful-plan-reviewer` template | **satisfied** | `build-lean/SKILL.md:27` now reads "(Agent tool — the refusal prints the exact agent name, which is not derivable from the provider string)". The old template string is gone from the tree. |
| AC-8 — extension-points row + evals README count | **satisfied** | `docs/extension-points.md:20` names `design-faithful-plan-reviewer` in the design-tokens reader row; `evals/README.md:3` reads "Four eval directories, one per static design reviewer", the table gained the row, and the campaign table gained an `OWED` row with its reason. |
| AC-9 — `prose-blockers.sh check` green | **satisfied** | rc 0 — 28 constructs over 52 files, 50 record rows, zero undispositioned. Three triage rows moved: `pb-f643817e` (re-keyed from `pb-cbe0e255` by the `build-lean/SKILL.md` edit), `pb-c66b4201` (new, the agent), `pb-1a8a2039` (new, the skill step). |
| AC-10 — the three guards green; `feat(design-toolkit):` verb; `Changelog:` trailer | **satisfied** | `check-gate-buckets.sh` rc 0 (305 sites / 161 rows), `check-lockstep-pairs.sh` rc 0 (29 anchors), `check-reviewer-references.sh` rc 0. `c68b0720` is `feat(design-toolkit):` and carries a consumer-facing `Changelog:` with `Migration:`; the other three commits carry `Changelog: none.` |

## Findings

### Majors (should fix; none blocks)

1. **`design_plan_gate`'s new family selector is shipped with zero coverage on either arm.**
   `lean-gate.sh:4188-4194` adds `fam="$(design_family < ...)"` and a two-arm `case` picking
   between `"the design-faithful translation-plan step"` and `"the figma-faithful step-7 plan"`
   for the absent-plan refusal. Verified from the reviewed checkout: `grep -n 'translation-plan
   step\|step-7 plan'` over `lean-gate-selftest.sh` returns **nothing**, and over
   `tools/mutation-catalog.tsv` returns **nothing**. `(dp0)`/`(dp1)` reach this branch only
   through the figma fixture config and assert neither string; `(dpr7)` runs `dplan_sync` first,
   so the manifest exists and this branch is never entered under `claude-design`. A mutant
   collapsing both arms to the figma wording — or swapping them — survives the full suite.
   Raised independently by test-coverage (conf 85) and unit-test-mutation (conf 88); confirmed
   by grep here.
   **Why it is not a blocker:** the `case` selects the *guidance text* of a refusal that fires
   identically either way — it is not a gate decision, and no `AC-n` mandates coverage for it.
   D-12 files this site as one of the six stale-prose corrections, not as a new contract.
   The cheap disposal is one selftest case analogous to `(dp1)` on the claude-design config
   asserting the refusal names the design-faithful step, plus a catalog row on the `case`.

2. **AC-1's "sections are exactly the D-2 set" is literally unsatisfied — one section over.**
   The checklist is Component-resolution suitability, Per-node dimensions, **Placement**, Analog
   suitability, State→code wiring, File coverage, Decision Ledger. D-2 enumerates six; Placement
   is the seventh. The deviation runs in the **safe** direction and is required by the same spec:
   D-3 and AC-3 both mandate a placement decision in the plan, and D-3 says each mandated element
   maps to a D-2 check. Deleting the section to satisfy AC-1 as written would leave a mandated
   element with no reader — the exact shape this slice exists to end — so the code is right and
   the AC's enumeration is short. The figma sibling carries the same check under "Layout context
   — sibling spacing & placement", so there is direct precedent. Disposal: extend AC-1's
   enumeration with placement at close-out; do not delete the section.

3. **The control fixture is not demonstrably clean, so it may deflate its own baseline.**
   `fixtures/04-control-clean.md`'s ledger row D-1 resolves "Rotate-only — the field is read-only
   with a separate Rotate action, per the handoff", but the resolved-component table renders the
   signing secret as `TextField type='password'` with an `endAdornment` reveal toggle inside an
   editable form with Save/Cancel, states no `readOnly`, and neither the component list, the
   dimensions table, the placement decision nor the file list mounts a Rotate control. That is a
   grounded internal inconsistency against real rows, reachable from the agent's own File-coverage
   and Component-resolution checks, and `must_not_flag` does not cover it. A correct reviewer
   flagging it returns `fix-and-go`, scoring **0 of 6** on `d1_verdict_correctness` for the
   control — the calibration measurement the control exists to take.
   **Why it is not a blocker:** the baseline is OWED per D-14/OR-1, no reading exists, and nothing
   downstream binds to the absent number, so the fixture can be corrected at zero cost before the
   operator's first run. `CLOSEOUT-BASELINE.md` already routes that run through the operator.

### Dismissed

- **Scope-completeness returned FAIL (blocker, conf 88)** on issue #739 item 3's second clause —
  *"Keep a case for a family that still has no reviewer, or the arm goes untested again."*
  **Dismissed on authority, not on merits.** The committed lean spec is the definition of done
  here, and it records this departure explicitly rather than silently: **D-6** names the clause
  verbatim and states it "is not satisfiable end-to-end, per D-5's reach", and **D-5** decides the
  `*)` arm's fate and the catalog re-anchor. Both rows are in the branch's **first** commit
  (`222c90bb`, the spec commit, which precedes the code commit `c68b0720`), and both appear
  verbatim in the pre-flight ledger at `.claude/pipeline-state/739-ledger.md` (rows D-5/D-6, plus
  S-11/S-12 marking the selftest case and catalog row as decided). That is a pre-flight decision,
  not a spec amended to match the diff.
  The substance also holds, and I verified it independently rather than taking the comment's word:
  `design_family()` (`lean-gate.sh:3128-3150`) emits only `figma` or `claude-design`; `design_state`
  (`:3446`) returns `error:` for a handoff link classifying to neither, and again for a
  host/`design.provider` disagreement; `cmd_plan_review` (`:4252-4257`) and `cmd_3_render` both
  refuse on that `error:` before `design_family_plan_reviewer` is ever called. With both families
  now resolving, the `*)` arm and both decline paths (`:4117`, `:4262`) are unreachable through
  every public entry point — so item 3's second clause is not writable as an end-to-end scenario,
  which is what D-6 says. The reviewer reached the same conclusion on the code and then scored the
  clause unsatisfied anyway because the deferral is not in the *issue body*; on this lane the spec
  and its pre-flight ledger are the higher authority.
- **`mutation-sweep-pr` green is vacuous, and is not evidence.** The job graded **nothing**:
  `all 1 in-scope guard(s) deferred to the merge-time sweep, 0 swept (reasons: slow suite: 1)`.
  Recorded so no later reader mistakes that green for mutation coverage. The PR body already
  discloses the deferral; the hand probe below is the actual evidence.
- **`pr-gates` is red.** Expected on an unapproved lean PR — the chain reconciliation arm naming
  its own reason. A merge-boundary policy state, not a review finding.
- Security, performance, maintainability and complexity returned clean with no findings above
  threshold. Security's two suppressed items (conf 40 / 30) are fixture-prose observations with no
  credential values present; both correctly below threshold.

## Verification I ran, rather than cited

- **Both CI selftest jobs pass at the reviewed head.** `lint-and-selftests` (4m6s) and
  `selftests (macos, bash 3.2)` (5m25s), run `33424979260`, head
  `1854bd3530c7298236974693e9cc4a62e0cf8e1f` — same head, same command as the repo recipe. Cited,
  not re-run. Both are conclusion `pass`, so no step was skipped by an earlier red.
- **`lean-gate-selftest.sh` in full, locally, at the reviewed head** — `all green`, exit 0,
  570 cases, with `(dpr7)` PASS. Run separately because milestone 3's slow-suite table defers it,
  so the build's green gate said nothing about the case this PR rewrites.
- **All five guards run from the reviewed checkout**: `check-gate-buckets.sh`,
  `check-lockstep-pairs.sh`, `check-eval-model-identity.sh`, `check-reviewer-references.sh`,
  `prose-blockers.sh check` — all rc 0.
- **`shellcheck -e SC1091,SC2015,SC2181`** on the three changed shell files — rc 0 (local 0.11.0;
  CI's own lint step passed at 0.9.0, which is the binding one).
- **The lockstep-exclusion claim is true, and checked.** The agent's `<!-- ... -->` note says the
  two reviewer-baseline deltas are deliberately outside the `artifact-reviewer-baseline-deltas`
  group because that block's Output delta names the figma.mjs engine as the agent's former
  dispatcher. Read the group at `figma-faithful-plan-reviewer.md:150-155`: it does carry
  "(its former gate dispatcher, the figma.mjs engine, was retired in #574)", which is false of this
  agent. Dropping the provenance clause rather than copying it verbatim is the honest call.
- **The AC-4 amendment in `1854bd35` is legitimate.** It corrects a clause that contradicted
  itself — the original said the row was "re-anchored to the surviving `*)` arm" while the same
  sentence described a mutant that deletes `claude-design)`. The mutant, its killer and the
  asserted behavior are unchanged; only the description of which line the sed edits moved. Not a
  spec amended to match the diff.

## Mutation evidence

`mutation-sweep-pr` graded nothing, so the re-anchored row has **no CI oracle**. Probed by hand,
in an isolated detached worktree at the reviewed head (never the reviewed checkout):

- Applied `tools/mutation-catalog.tsv`'s `lean-gate-plan-review-family-universal` sed with
  `sed -E`, which is how `tools/mutation-sweep.sh:1897` applies it. The row is well-formed under
  ERE and edits **exactly one line** — `3223c3223`, deleting
  `    claude-design) printf 'design-faithful-plan-reviewer' ;;` — leaving the `figma)` and `*)`
  arms intact. Not a vacuous mutant.
- Ran the full suite against the mutant: **1 failure out of 570 cases**, and it is `(dpr7)` —
  `FAIL: (dpr7) rc=1 attempts=1 renders=2`. The mutated gate declined the mandate, walked past it
  into the render pass (`renders=2`, against `0` on the unmutated tree) and charged a fix attempt.
  The unmutated run at the same head is 570/570 green. The row's declared killer is real and the
  kill is not incidental — `(dpr1)` and the other armed cases drive a figma host and stayed green
  under the mutant, which is exactly why the inversion was needed.
- The two hand-probed gaps `(dpr7)` does **not** cover are major 1's `case` arms, which no mutant
  in the catalog anchors.

## What was not reviewed

- **Design fidelity: not applicable.** This repo's `.claude/second-shift.config.json` configures
  no `design.provider`, and `docs/plans/second-shift-739-lean.md` carries no `## Design` section,
  so the design lane is disarmed and step 5b does not run. `--fidelity not-applicable`.
- **a11y and the design-fidelity review dimension were not routed** — no changed path is a web
  component; the diff is bash, markdown, TSV, JSON and one Python rubric.
- **`db-reviewer` and `pipeline-reviewer` were not selected** — this repo has no DB layer and no
  async worker surface.
- The eval instrument is **not executed** anywhere in this review, by design: it is operator-run
  and model-billed, CI here is model-free, and D-14 defers the reading to after release.
