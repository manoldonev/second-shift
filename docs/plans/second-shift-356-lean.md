# 356 — eval-harness model-id neutrality

Lean spec. Binding input: the pre-flight receipt `.claude/pipeline-state/356-ledger.md`
(D-1…D-10, OR-1/OR-2). Where the receipt and the issue body differ, the receipt wins — it
does so once, in D-1: the ticket offered "the same tier seam **or** explicit flags" and the
receipt withdrew the tier-seam route on evidence, so **nothing here reads `models.tierMap`
and nothing here depends on #351**.

## Problem

The eval harnesses under `plugins/*/evals/**` hardcode vendor model identity in the surface
that *runs*: `run-eval.py`'s `--model` default, five `run*.sh` wrappers, two
`agents-template*.json` mock definitions, one smoke, and the invocation examples in the kit
README. Two distinct costs:

1. **Vendor coupling in shipped tooling.** Epic #350's hedge asks that concrete backend
   targets live with the operator, not in the repo (its D-3). These files put a specific
   vendor's model ids in every consumer's checkout of two plugins.
2. **Uninterpretable baselines.** `changelog.md` records `model=<reviewer_model>` as the
   comparability key between two eval rows. Today that string can be anything the caller
   passed — including a floating dispatch alias, whose meaning moves under the row. A row
   reading `model=opus` is not comparable to any later run.

The dispatch side of the repo has the opposite requirement: `check-model-tiers.sh`'s
`KNOWN_TIERS_RE` admits only `opus`, `sonnet`, `haiku` and raises UNKNOWN-MODEL on anything
else, so a *versioned pin* is a lint error there while a *floating alias* is the only legal
value. Evals need exactly the inverse. One map cannot serve both alphabets (D-1) — hence a
runner-local environment contract, and **no lockstep row** between this surface and #351's
map (OR-2).

## Acceptance criteria

**AC-1 — no default model anywhere in the runnable surface (D-2).** `run-eval.py`'s
`--model`, `--reviewer-model` and `--judge-model` all default to unset. When the effective
model for the reviewer or the judge role resolves to nothing, the runner exits non-zero
**before spawning any billed subprocess**, with a message naming the flag and the wrapper
environment variable that feeds it. No wrapper, smoke, or template supplies a fallback.

**AC-2 — floating dispatch aliases are rejected at runtime (D-3).** The bare tokens `opus`,
`sonnet`, `haiku` and `fable` (matched case-insensitively) are refused for **every** role —
reviewer, judge, and mock — with a message stating the pinning rationale. Any other string
is accepted verbatim as the operator's pin. This is stated as a **rejection, not an
allowlist**: the check must not assert what a valid id from another backend looks like, so
adding a fifth vendor's id requires no change here.

**AC-3 — the mock role is neutralized through the template (D-5, D-7).** Both
`agents-template.json` and `agents-template.structured.json` carry `"model":
"{{mock_model}}"` in place of the vendor literal. `run-eval.py` gains `--mock-model`,
substitutes it into the template alongside the existing `{{canned_*}}` tokens, and validates
it under AC-2. A template that carries the token while no `--mock-model` is supplied is a
**startup** failure (AC-1's before-any-billed-call rule applies: the template is inspected
once at config time, not per fixture).

**AC-4 — the five wrappers require, and never default, their role variables (D-2, D-7).**
`intake-orchestrator-eval/run.sh`, `intake-orchestrator-eval/run-structured.sh`,
`plan-reviewer-eval/run.sh`, `review-lead-eval/run.sh` and `security-reviewer-eval/run.sh`
each read the role variables they actually use — `REVIEWER_MODEL`, `JUDGE_MODEL`, and
`MOCK_MODEL` for the two wrappers that pass an agents template — and fail with a message
**naming the missing variable** when one is absent. `review-lead-eval/run.sh`'s
`${REVIEWER_MODEL:-claude-opus-4-7}` and `plan-reviewer-eval/run.sh`'s conditional
pass-through are both replaced by the same unconditional required-variable form, so the five
wrappers state one contract rather than three.

Role→model correspondence is unchanged in substance (D-8) — reviewer, judge and mock remain
three separately-settable slots, and the cost rationale for running judge and mocks below the
reviewer tier stays recorded in `intake-orchestrator-eval/run.sh`'s header. What changes is
who supplies the value.

**AC-5 — the calibration smoke joins the contract (D-5).**
`smokes/gate-3-judge-calibration.py` takes its judge model from `JUDGE_MODEL` and validates
it through the **same** function `run-eval.py` exposes — it already loads the runner as a
module, so the check is imported, not restated. `smokes/gate-2-e2e-one-fixture.sh` names the
variables its `run.sh` call now requires in its usage header.

**AC-6 — the documented invocation carries no vendor identity (D-5).**
`agent-eval-kit/README.md`'s flag table and A/B recipe, and the header comments of the
wrappers that carry invocation examples, describe the environment contract without naming a
vendor model. The README's flag-table `Default` column for the three model flags reads as
required-no-default, matching AC-1.

**AC-7 — a regression guard with its own contract (D-6).** A new
`scripts/check-eval-model-neutrality.sh` fails when the **runnable** eval surface under
`plugins/*/evals/**` contains vendor model identity, in either of two forms:

- a versioned vendor pin (`claude-<family>-<digits>…`, case-insensitive);
- a floating alias in a *model position* — a `--…model` flag value, a JSON `"model":` value,
  or a `*_MODEL=` assignment whose value is one of AC-2's four tokens.

The D-5 record files — `changelog.md`, `FINAL-REPORT.md`, `CLOSEOUT-BASELINE.md`,
`BASELINE.md`, `KNOWN_ISSUES.md`, `FIXTURE-AUDIT.md` — are excluded **by path**, as are the
runner's own `results-*.json` output and `__pycache__`. The guard **fails when it scans zero
files**, so a surface that moves out from under it reds rather than reporting a vacuous
green. It takes an optional root argument so a fixture tree can be scanned.

CLAUDE.md exempts "the eval runners" from selftest coverage for having no independent
contract; this lint has one, so it ships with a same-named behavioral selftest
(`scripts/check-eval-model-neutrality-selftest.sh`) covering: a clean tree passes; each of
the two violation forms reds and names its file; the identical literal inside each excluded
record file still passes; a zero-file scan reds; and the **real repo tree** passes.

**AC-8 — the guard runs.** `scripts/check-eval-model-neutrality.sh` is invoked as a step of
the `lint-and-selftests` job in `.github/workflows/ci.yml`, next to the other repo-level
lints. This does not contradict D-10: D-10 records that CI never *invokes the eval runners*,
so fail-closed runners cannot red a lane. A static text lint invokes no runner and makes no
model call — CI stays model-free.

**AC-9 — the historical record is byte-unchanged (D-5).** No edit lands in `changelog.md`,
`FINAL-REPORT.md`, `CLOSEOUT-BASELINE.md`, `BASELINE.md`, `KNOWN_ISSUES.md` or
`FIXTURE-AUDIT.md` in any eval directory. Those rows attribute a score to the model that
produced it; neutralizing them would destroy the attribution the pins exist for.

## Out of scope

- **`models.tierMap` / #351** — D-1. No dependency, no shared map, no lockstep row (OR-2).
- **Recording the *resolved* model id from the `claude -p` JSON envelope** — OR-1's parked
  default. `changelog.md` keeps recording the *requested* string, which AC-2 now guarantees
  is a pin. Confirming the envelope even carries a resolved id needs a live billed call.
- **OR-2 (unifying with the tier seam once #351 lands)** is dispositioned `pause-and-ask` and
  is conditioned on a future event — #351 has not shipped, and nothing in this diff decides
  it. No operator comment is owed for this run.
- **Consumer-side or CI behavior.** D-10: CI never invokes these harnesses.

## Verification

`shellcheck` over the changed shell, `jq empty` over the changed JSON, the repo selftest
sweep (which discovers the new suite by glob), the new lint over the real tree, and
`python3 -c 'import ast; ast.parse(...)'`-class syntax checking plus a fail-closed exercise of
`run-eval.py`'s and the smoke's new refusal paths without spawning a billed call.
