# lean review verdict — #356

verdict=approve
run_id: review-356-1
session_id: ed5f60f4-7f20-42ff-970c-700022c346cc
rounds: 1
pr: #475
reviewed_head: 9382ce19510dab23d375fec13f0fb8e54ec64ceb
reviewed_patch_id: 6b29114810793e245bd43e675cd2cb2506482123
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 — full branch range `1413ca7..HEAD` (root round, nothing to inherit).

Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness, unit-test-mutation — all seven returned, none dark. Six approve;
unit-test-mutation returned `request-changes` in advisory mode, triaged below. a11y and
the design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`).

The spec carries no `## Design` section, so the design arm is not armed — fidelity
`not-applicable`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — no default in the runnable surface; refusal before any billed subprocess, naming flag + env var | satisfied | `--model` / `--reviewer-model` / `--judge-model` all `default=None`. Ran the runner with no model: rc=1, `Set --reviewer-model or --model (env REVIEWER_MODEL)`; with the reviewer pinned and the judge absent: rc=1, `(env JUDGE_MODEL)`. `resolve_model` precedes every `claude -p` in `main()`. No wrapper, smoke, or template supplies a fallback. |
| AC-2 — the four aliases refused case-insensitively for every role; any other string taken verbatim | satisfied | `--model opus` and `--model OPUS` both rc=1 with the pinning rationale; `--judge-model haiku` rc=1; `--mock-model fable` rc=1. Invented ids from no vendor (`claude-opus-9-9`, `claude-sonnet-9-9`, `claude-haiku-9-9`) were accepted verbatim and passed the gate — the rejection-not-allowlist property, demonstrated rather than asserted. |
| AC-3 — mock role neutralized through the template; startup failure when the token is present with no `--mock-model` | satisfied | Both templates carry `"model": "{{mock_model}}"`. Template + no `--mock-model`: rc=1 at startup, `Set --mock-model (env MOCK_MODEL)`. Template + alias: rc=1. Template + valid pin: passes the gate and proceeds. |
| AC-4 — five wrappers require, never default, and name the missing variable | satisfied | All five refuse with rc=1 naming the absent variable; `MOCK_MODEL` is required in exactly the two template-carrying wrappers. `review-lead-eval`'s `${REVIEWER_MODEL:-<literal>}` and `plan-reviewer-eval`'s `${REVIEWER_MODEL:+…}` conditional are both replaced by the one `:?` form. D-8's cost rationale is retained in `intake-orchestrator-eval/run.sh`'s header. |
| AC-5 — the calibration smoke joins the contract, importing the same check | satisfied | `re_mod.resolve_model("judge", os.environ.get("JUDGE_MODEL"), "JUDGE_MODEL")` — imported, not restated. Missing: rc=1; `JUDGE_MODEL=sonnet`: rc=1 — both before either billed judge call. `gate-2-e2e-one-fixture.sh` names the three variables its `run.sh` call now requires. |
| AC-6 — documented invocation carries no vendor identity; `Default` column reads required-no-default | satisfied | Flag table reads **none** for all four model flags with a "see below" Required column and an explanatory paragraph; A/B recipe uses `<pin-A>` / `<pin-B>`; the skeleton carries the two `:?` guards and both flags. An independent grep of the whole eval surface leaves exactly two alias mentions in machinery — `run-eval.py:119` (the rejection list itself) and `README.md:175-176` (prose naming what is rejected). Neither is a model position, and a rejection list cannot be written without naming its tokens. |
| AC-7 — regression guard with its own contract, plus a same-named behavioral selftest | satisfied | Guard is green on the real tree scanning **27** files — exactly 38 eval files minus the 11 record-named ones. The selftest is 22/22 green. Independently probed: the pin form, and all three alias positions, red; both flag-position shapes (bare and with a `\` continuation, which is the shape every real wrapper uses) red; prose and note strings stay green; empty scan rc=2; nonexistent root rc=2. Warnings W1/W2 attach here — coverage, not correctness. |
| AC-8 — the guard runs | satisfied | Step `eval-harness model identity (plugins/*/evals/**)` present in the `lint-and-selftests` job, and CI reports it **success** on this head. Static text scan only — no runner invoked, CI stays model-free. |
| AC-9 — the historical record is byte-unchanged | satisfied | No `changelog.md` / `FINAL-REPORT.md` / `CLOSEOUT-BASELINE.md` / `BASELINE.md` / `KNOWN_ISSUES.md` / `FIXTURE-AUDIT.md` appears anywhere in the range. |

**9/9 satisfied. No blockers.**

## CI

`lint-and-selftests` ✅ · `mutation-sweep-pr` ✅ · `selftests (macos, bash 3.2)` ✅.
`pr-gates` ❌ at exactly one arm — `lean chain reconciliation (lean PRs carry their
evidence set)` — the verdict record this review writes. Every other arm of that job is
green (frozen files, changelog trailer, pipeline chain). That is the expected
pre-review shape, not a finding.

Spec hygiene: the spec landed as the branch's first commit and the one later amendment
(`9382ce1`) is a rename plus **added** coverage clauses and the rename rationale — no AC
was removed or weakened to match the diff.

## Findings

### Warnings (should fix; none blocking)

**W1 — three surviving mutants against the new guard's paired selftest.**
`scripts/check-eval-model-identity.sh:71,106,111`. Confirmed by applying each mutant to a
copy and re-running the suite, with an unmutated control that goes green first, so the
harness is not vacuous:

| Mutant | Result |
| --- | --- |
| drop `\|fable` from `ALIASES` (:71) | SURVIVED |
| drop `-i` from `grep -inoE "$PIN_RE"` (:106) | SURVIVED |
| drop `-i` from `grep -inoE "$POS_RE"` (:111) | SURVIVED |

The suite's three position cases use `sonnet` / `haiku` / `opus` and every fixture literal
is already lowercase, so nothing exercises `fable` or a mixed-case input.

This is **coverage, not correctness** — the shipped guard is right on all seven of the
corresponding inputs (`fable` reds in each of the three positions; `Claude-Opus-4-7`,
`CLAUDE-OPUS-4-7`, `--judge-model Sonnet`, `REVIEWER_MODEL=HAIKU` all red). Not a blocker:
AC-7's selftest enumeration is "each of the violation **forms**", and the suite covers both
forms and all three positions. Nor does it contradict the PR body's "8 applied, 8 killed, 0
survived" — neither mutant is in `mutation-operators.tsv`'s set, so the sweep never reached
them, which is why `mutation-sweep-pr` is green. Cheapest fix costs no new cases: rotate one
existing position case to `fable`, and one fixture literal to mixed case.

**W2 — the pin form misses Anthropic's own legacy family-last ids.**
`scripts/check-eval-model-identity.sh:67`. `PIN_RE='claude-[a-z]+-[0-9][a-z0-9.-]*'` requires
letters immediately after `claude-`, so `--judge-model claude-3-5-sonnet-20241022` scans
clean — form 2 does not catch it either, since that arm only matches the four bare aliases.
AC-7 defines the form as `claude-<family>-<digits>…` and the guard implements exactly that,
so the AC is met by its letter; but a copy-pasted pre-4.x pin lands in the runnable surface
unguarded, which is the one thing this guard exists to prevent. Widening the family group to
admit a leading digit run would close it.

**W3 — two stale references the PR names as out of scope.** The kit README's `run.sh`
skeleton still points the runner at a consumer-side `.claude/pipeline-state/agent-eval-kit/`
path, and `plan-reviewer-eval/run.sh`'s `--fixtures-dir` names a directory absent from this
repo. Both pre-existing, both correctly declared in the PR body as outside the AC set —
recorded so they are not lost.

### Pre-existing (not this PR)

- `docs/eval-fixtures/` does not exist in this repo at all, so no eval harness here is
  runnable end-to-end regardless of model identity — `gate-1-shim-loader.sh`, byte-identical
  to main, fails on exactly that today. This is why the ACs above are verified through the
  refusal paths rather than through a green eval run, and it is outside the AC set.
- `build_agents_json` splices `mock_model` via raw `text.replace()` while `{{canned_*}}`
  values are JSON-escaped, so a value containing a quote would yield invalid JSON
  (`run-eval.py:~275`). Security-reviewer suppressed this at confidence 40 and the
  suppression is right: the value is the operator's own env on a local harness, and
  `resolve_model` has already validated it.
- Mutation-reviewer's remaining two: the rel-path trim is checked only by a substring match
  (report rendering only, no effect on the guard's verdict), and `resolve_model` plus the
  wrapper `:?` guards have no automated suite. The second is CLAUDE.md's declared "eval
  runners — by design, no independent contract" exemption, which that reviewer noted itself;
  both paths were exercised by hand this round.

### Strengths

- The rename rationale is the unusually good part: naming the guard for *identity* rather
  than *neutrality* so its own filename cannot contain `-ne` is a fix aimed at the mutation
  sweep's per-guard budget, not at the reader — and the spec records why, so the next person
  cannot "tidy" it back.
- The guard's zero-file arm (`rc=2`, distinct from a violation's `rc=1`) is the right shape
  for a surface that has already been relocated once, and the selftest pins both codes
  separately rather than collapsing them to non-zero.
- The record-file exemption cases each carry **the same literal that reds elsewhere**, so a
  green there cannot come from a vacuously clean fixture — the failure mode that makes most
  exemption tests worthless.
- Stating alias rejection as a rejection rather than an allowlist is what makes the
  invented-vendor ids pass without a code change, and the runner's comment explains the
  inverse relationship to `check-model-tiers.sh` instead of leaving the next reader to
  rediscover that the two alphabets cannot share a map.

**Verdict: approve.** 9/9 ACs satisfied, no blockers, no dark reviewers. W1 and W2 are worth
a follow-up on the guard's own coverage; neither withholds this merge.
