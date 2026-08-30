# lean review verdict — #704

verdict=needs-work
run_id: review-704-1
session_id: a6d4254b-ba78-4878-9608-18adcbc3a53e
rounds: 1
pr: #713
reviewed_head: 086b336b7b1430e07ff8d9325e5f60534bc1d6b6
reviewed_patch_id: 1214fc71cff081219b20b7bafe23e272142c8fa3
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #713 (issue #704)

**Range read:** `808aa29..086b336` (full branch diff — round 1, nothing to inherit).
**Reviewed from:** `/Users/mdonev/github/second-shift-worktrees/704` @ `086b336`.

Panel: 6/6 reviewers alive (security, performance, maintainability, complexity, test-coverage,
scope-completeness). Zero panel blockers. `a11y` + design-fidelity not routed: no changed path
matched `stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`); the `.tsx`
files in the diff are eval fixture stubs under `plugins/design-toolkit/evals/`, not this repo's
web surface. This repo has no FE app.

## Verdict

**needs-work** — one blocker, on AC-7.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3775` | D-13's radius measurement is false at the branch head, so AC-7 is unmet: one site outside the two agent files still asserts the pre-AC-4 behaviour in the present tense. |
| N1 | Note | `plugins/design-toolkit/evals/figma-faithful-spec-reviewer-eval/CLOSEOUT-BASELINE.md:36-37` | Per-dimension Notes overstate slightly: "the entire deficit is fixture 01" is 18 of 20 lost `d1` points and 6 of 7 lost `d2` points, not all of them. |
| N2 | Note | issue #704 body | AC-3's deferral to #707 lives in an issue comment and the plan ledger, not in the issue body's acceptance criteria. Tracker-recorded and #707 exists, so not a blocker. |

### B1 — AC-7's own measurement does not hold at the branch head

D-13 states the blast radius of the AC-4 lockstep is **bounded to the two agent files**, derived by
"grepping every `*.md`/`*.sh`/`*.mjs`/`*.json` outside `docs/plans/`". AC-7 is scored on that
measurement "holding at the branch head, re-run rather than asserted".

Re-run at `086b336`, it does not hold. One further site is in that grep set and is not named:

```
plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3775
# suitability was deferred to an agent that returns N/A on every lean-lane spec.
```

It is a `.sh` file outside `docs/plans/`, and the relative clause is **present tense** — it asserts
what `figma-faithful-spec-reviewer` does now. After this PR that is false: the agent's `N/A` is
narrowed to "not a design artifact at all", and a lean-lane spec is in scope.

This is not a pre-existing gap the PR merely inherits. The line was true when #694 wrote it; **this
change is what makes it false** — which is exactly what AC-7 ("no documentation is left stale by
this change") targets. It also carries weight beyond tense: the comment is the recorded rationale
for the #694 armed-plan arm ("both checks written to grade it reached nothing"), so a future reader
re-deriving whether that arm is still needed reads one of its two premises from a statement that no
longer holds.

Every other site the broad sweep returned is already correct — each states the old behaviour in the
past tense with the fix named (`figma-faithful-plan-reviewer.md:46-47` "used to return … is now
narrowed", `evals/README.md:112` "the defect #704's AC-4 fixes", the spec-reviewer
`CLOSEOUT-BASELINE.md:47` "said outright"). B1 is the single outlier.

**Fix — one line, and update D-13 to name the third site:**

```
# suitability was deferred to an agent that, at the time, returned N/A on every lean-lane
# spec (narrowed by #704's AC-4 — a lean-lane spec is in scope for it now).
```

Note that a `Guard-mass:` trailer is not owed for a comment-only edit inside an existing script;
`guard-budget` is already green on this branch and comment-only sites are excluded.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Three eval dirs exist, each with 4 `<name>.md` + `<name>.expected.json` pairs, no orphans either way (checked mechanically). "Runnable" verified structurally, not asserted: each `run.sh` passes `--fixtures-dir "$HERE/fixtures"`, which resolves to a committed in-repo directory; the kit's `load_fixtures` discovers flat pairs with `fixtures_dir.glob("*.md")` — **non-recursive**, so the reviewer eval's `fixtures/design-tokens/` and `fixtures/app/` subtrees are not mis-discovered as fixtures, and neither contains an `expected.json`, so the directory-per-fixture branch stays empty too. All three pass the namespaced `design-toolkit:<agent>` name (`7deca9f`), and every flag used (`--eval-dir`, `--repo-root`, `--reviewer-user-prompt-template`, `--judge-agent-name`, `--judge-description`) exists in `run-eval.py`'s argparse. Shapes required by the AC are all present. |
| AC-2 | **satisfied** | Three `CLOSEOUT-BASELINE.md`, each carrying Headline / Per-fixture / Per-dimension / Provenance / Exact invocation, matching `intake-orchestrator-eval/CLOSEOUT-BASELINE.md`'s shape. **Re-derived rather than accepted:** all three score sets are internally consistent — reviewer 120/120; plan-reviewer 119/120 (30+30+29+30 per fixture, 72+24+23 per dimension, 96.7% = 29/30, 95.8% = 23/24); spec-reviewer 87/120 = 72.50% (6+26+28+27 per fixture, 52+17+18 per dimension, all four percentages exact). The claimed agent-prompt SHA `6dd9f70` re-derives as the last commit touching each of the three agent files at `fee85c8`. The provenance claim "verified byte-identical to the installed 4.0.3" **verifies**: `diff` of each pre-edit blob against `~/.claude/plugins/cache/second-shift/design-toolkit/4.0.3/agents/` is empty for all three. Model pins in `changelog.md` match each agent's own frontmatter tier (sonnet / opus / opus), so the reviewer eval's Sonnet row is correct, not a comparator swap. Taken before the AC-4 edit by construction (`6f18b80` precedes `086b336`). |
| AC-3 | **satisfied** | Out of scope per D-1. Nothing in the diff runs a keep-or-revert campaign; every baseline states `Campaign status: OPEN — baseline only` and names #707. #707 exists, is open, and cross-links. |
| AC-4 | **satisfied** | `086b336` narrows the `N/A` condition to "not a design artifact at all" at `figma-faithful-spec-reviewer.md:21/23/25/155`, and rewrites all three `figma-faithful-plan-reviewer.md` paragraphs in the **same commit**: the "interactive lane only" deferral, the "nothing is dropped" clause, and the "no owner on the lean lane" copy-capture claim. Component suitability is explicitly kept dual-owned. No sentence in **either file** claims the old behaviour. |
| AC-5 | **satisfied** | Every commit carries a `Changelog:` trailer; the three prompt-bearing ones name the change. No `plugin.json` `version`, no `CHANGELOG.md`, no `marketplace.json` edit in the diff. The `frozen files guard`, `changelog trailer guard` and `guard budget guard` steps of `pr-gates` are all **success** at this head. |
| AC-6 | **satisfied** | Re-run locally at `086b336`: `scripts/check-eval-model-identity.sh` → `✓ 86 runnable eval file(s) carry no vendor model identity`; `shellcheck -e SC1091,SC2015,SC2181` clean on all three `run.sh`; `jq empty` clean on all twelve `*.expected.json`. |
| AC-7 | **UNSATISFIED** | See B1. D-13's radius claim, which AC-7 is scored on, is falsified by `lean-gate.sh:3775` at the branch head. |

## CI

| Lane | Result |
| --- | --- |
| `lint-and-selftests` | **pass** (5m00s) |
| `selftests (macos, bash 3.2)` | **pass** (5m44s) |
| `mutation-sweep-pr` | **pass** — log read, not the badge: "PR mode: no in-universe guards touched by `origin/main...HEAD` — nothing to sweep". Honest defer; the diff touches no guard shell. |
| `pr-gates` | **fail**, on the `lean chain reconciliation` step **only** — expected state before an `approve` verdict record exists, not a blocker. Every policy step in that job (frozen files, changelog trailer, guard budget, pipeline chain) is green. |

## Design fidelity

`not-applicable` — the spec carries no `## Design` section and declares no `RS-n` render states, so
step 5b is not armed. Consistent with D-16: the design arm and `review-lean` step 5b are #705's.

## Strengths

- **The measurement is auditable end-to-end.** The provenance blocks name the one thing that
  actually determines what got measured — that `claude -p --agent` resolves from the *installed*
  plugin cache, not the branch — and then discharge it with a `diff` a reviewer can re-run. That is
  the failure mode where an eval silently measures the wrong prompt, closed by evidence.
- **The corrected control fixture is recorded, not quietly replaced.** The spec-reviewer's first
  control scored 56.7% on two findings that were correct *about the fixture*; both measurements are
  kept, with fixture 01 shown not to move across the correction — which is what makes it a usable
  oracle rather than a number.
- **Two ceiling results reported as a finding rather than a win.** "#692's failure was dispatch, not
  capability" is a stronger and more useful conclusion than a tuned score, and it is derived from
  the data rather than asserted alongside it.
- **The namespaced-agent-name failure survives in the append-only log** (`agent=figma-faithful-plan-reviewer
  … score=0.0% … cost=$0.00`) instead of being cleaned up — the row a future operator needs to
  recognise the same red.

## Reading beyond the delta

Round 1 read the whole branch. Two claims were additionally re-derived rather than read: the D-13
radius (swept repo-wide, not just the two agent files — this is what produced B1) and the baseline
arithmetic and provenance (recomputed from the committed tables and re-diffed against the installed
plugin cache).
