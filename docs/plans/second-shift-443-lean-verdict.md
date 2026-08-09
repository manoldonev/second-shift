# lean review verdict — #443

verdict=approve
run_id: review-443-1
session_id: ec27f5a9-9679-4f71-b33a-31792e53e85c
rounds: 1
pr: #451
reviewed_head: 37454007c6525373f5374b5cab725c9b5ac9c1cd
reviewed_patch_id: 0dbd633359a764065099a60199e1c2a514e2c81c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

# Review round 1 — PR #451 (issue #443)

Range read: `b55e701..HEAD` (full branch diff — `lean-gate.sh delta 443` reports FULL,
nothing verifiable to inherit). Reviewed head `3745400`.

**Verdict: approve.** No blockers. Two warnings and two pre-existing gaps, none of which
holds up a merge.

## What was verified, and how

The headline risk in a "make the gate silent" change is that the suites become vacuous —
that each removed `grep '✓ …'` is replaced by something that would stay green if the arm
stopped running. Probed directly rather than read:

| Probe | Result |
| --- | --- |
| An arm resumes narrating on the green path (`echo` injected into `check-lean-chain.sh`'s green path) | **KILLED — 23 of the suite's cases red.** The `silent()` assertions are live and strong, not an exit-status demotion. |
| The closed-vocabulary refusal is neutered in `check-lean-chain.sh` (`*) envfail …` → `*) : ;;`) | **SURVIVED — suite all green.** See W-1. |
| `tools/mutation-sweep.sh --mode pr --base b55e701` | 33 verdicts, 12 survivors, **zero baseline-absent**, no pool disagreement. |

Suites run green from a clean checkout of the head (`env -u CLAUDE_CODE_SESSION_ID -u RUN_ID`):
`check-lean-chain-selftest.sh`, `lean-evidence-selftest.sh`, `second-shift-ci-check-selftest.sh`,
`scenario-liveness-selftest.sh` (82 passed, 0 failed), `lean-gate-selftest.sh` (run **with**
`RUN_ID` exported, which is AC-10's letter), and `check-lockstep-pairs.sh` (23 pairs, 0 failed,
including the new `lean-output-dispositions` row). `shellcheck -e SC1091,SC2015,SC2181` clean over
all seven changed shell files.

## The red lane, and why it is not a blocker

`lint-and-selftests` is **red**, and it is not this diff's debt. The failing step is the PR-scoped
mutation sweep, and the failure is a **pool disagreement** on
`plugins/dev-pipeline/skills/run-lean/lean-evidence.sh::cmp-z::1` — the sweep's own words:

> was scored SURVIVED by the worker pool but is KILLED by a serial re-run of the same kill set
> outside it — the harness is at fault, not the guard. Reporting the corrected KILLED verdict;
> do NOT add a baseline row for this mutant.

Three independent facts say the same thing: the sweep's serial re-verify killed the mutant; my
local run of the same tree scored it KILLED too; and the survivor set CI reports (12, across the
three guards) is **identical** to the local one and is **entirely baseline-present**, with no
baseline-absent survivor anywhere. The mutant is correctly absent from
`tools/mutation-baseline.tsv` because it is normally killed.

**The remedy is a job re-run, not a code change** — and specifically not a baseline row, which
the tool explicitly forbids. Note for whoever acts on this: a content push to fix "the red" would
change a line, void this record and cost a fresh review round for no reason. Re-run the job. If a
cold re-run reproduces the disagreement on the same mutant, that is a sweep-harness bug to file
against the sweep, still not against this PR.

`pr-gates` is red for the expected reason — this record did not exist when it ran.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — chain gate silent + rc=0 on an all-class-(a) lean PR | **satisfied** | Case (A) asserts rc=0 AND zero bytes over a `2>&1` capture. Probe B proves the assertion kills. |
| AC-2 — `lean-evidence.sh` `check`/`all` silent; `classify` exempt | **satisfied** | Case (a). `say()` deleted outright; `classify`'s `applicable=`/`trigger=`/`key=`/`spec_in_diff=` output untouched, so the delegation contract at `check-lean-chain.sh:399` still parses. |
| AC-3 — exactly one line, arm name + closed disposition, rc=0 | **satisfied** | `class_b()` anchors the whole line and asserts the class-(b) line **count** is 1. (dd1)/(dd2) drive the real emitter bytes for an accepted reserved disposition and a rejected unknown one. |
| AC-4 — precedence-skip and no-inherited-coverage are class (a) | **satisfied** | Both branches inverted and their echoes deleted (`-n`→`-z` on `VERDICT_REVIEWED_PATCH_ID`, `-z`→`-n` on `VERDICT_INHERITED_PATCH_ID`, `!=`→`==` on `design_armed`). (W2) is the sharp one: (W1) first asserts the merge landed files an unguarded inferred arm *would* fire on, so silence there is the precedence assertion, not a restatement of it. |
| AC-5 — failure-path output unchanged | **satisfied** | Diffed every `note_violation`/`fail`/`envfail` string literal in both guards, base vs head: byte-identical, with exactly one addition — the new out-of-vocabulary `envfail`. |
| AC-6 — no verbose/opt-in flag; silence means both streams | **satisfied** | Arg parsing unchanged but for the `--help` `sed` range. Both suites fold stderr into stdout before asserting emptiness. |
| AC-7 — every arm retains a kill criterion; no bare-rc demotion | **satisfied** | Probe B is the direct evidence: the replacement assertion reds 23 cases when an arm narrates. Negative cases are unchanged. (V6a) is a genuine new rc-observable — a root whose body quotes a **non-resolving** value, which a first-match read walks and dangles on — and it re-arms (V6b) one level down. The one loss, (V3b)'s link count, is argued unreplaceable in D-5 and ratified by the operator; the sweep, AC-7's own stated witness, is clean. |
| AC-8 — contributor-doc paragraph | **not scored** (the spec declares it non-scored) | The paragraph is in `docs/pipeline-manifesto.md`. See W-2 on its provenance. |
| AC-9 — in-repo text this change makes inaccurate is corrected | **satisfied** | `second-shift-ci-check.sh`'s `ok` message and the comment above it now name the class-(b) decline line as the rc=0 discriminator instead of pointing at payload output that no longer exists. `scenario-liveness-selftest.sh`'s `lr_lean()` moved to the `lean-chain: not-applicable` token. |
| AC-10 — `lean-gate-selftest.sh` passes with `RUN_ID` exported | **satisfied** | `(d5)` now carries `env -u RUN_ID` like every sibling `entry` case; suite green with `RUN_ID` exported. The base-version negative was deliberately **not** run: the whole point of the bug is that it falls through to the live `$GH_BOT` write path, and reproducing it risks a real PR comment. |

Out-of-scope respected: `pipeline-doctor.sh`, `check-pipeline-chain.sh` and all of `lean-gate.sh`
are untouched. `lean-gate-selftest.sh` is edited, but only for AC-10 — the gate's own output
surface is unchanged.

## Warnings (should fix, not blocking)

**W-1 — the closed vocabulary is enforced in two files and guarded in one.**
`scripts/check-lean-chain.sh:207-211`. `inapplicable()`'s `case … esac` refusal is duplicated
verbatim from `lean-evidence.sh`, but the `lean-output-dispositions` lockstep row is `verbatim`
over the `LEAN_OUTPUT_DISPOSITIONS=` block only — the emitter sits deliberately outside the
markers — and `(dd1)`/`(dd2)` live in `lean-evidence-selftest.sh` alone. Probe-confirmed:
neutering the `envfail` arm in the chain gate leaves the whole suite green. No AC is unmet and
nothing misbehaves today (all three call sites pass bare literals), so this is a warning rather
than a blocker. It lands on the successors: #444 AC-1/AC-3 emit `postdated` from *both* files,
and a chain-gate call site that typos a disposition would print it rather than refuse it. A
`(dd1)`/`(dd2)` twin in `check-lean-chain-selftest.sh`, or extending the lockstep block to cover
the function body, closes it.

Related and same surface: the allowlist is glob-active — `case " $LEAN_OUTPUT_DISPOSITIONS " in
*" $2 "*)` matches `$2` as a **pattern**, so a disposition containing `*`, `?` or `[` would be
accepted and echoed as if it were in the set. Unreachable today for the same reason (literal call
sites); worth folding into the same fix if W-1 is addressed.

**W-2 — the spec mis-cites the issue for AC-8.**
`docs/plans/second-shift-443-lean.md`, AC-8: "(The issue numbers this AC-6; it is renumbered here
…)". Issue #443's AC-6 is the *no-verbose-flag* criterion, and the issue has no contributor-doc AC
at all — the obligation traces to parent epic **#436, R5** ("Adding an arm means shipping its
producer, its not-applicable path, and its silence-on-green"), which the manifesto paragraph
restates faithfully. The content is correctly sourced; only the citation is wrong. Not a spec
amended after the fact to match the diff, and not scope creep — but the spec is the definition of
done, so a wrong pointer in it is worth a one-line correction.

## Pre-existing gaps (not blocking this PR)

- **The decline note's conditional content is unasserted.** `check-lean-chain.sh:414-416`'s
  `DECLINE_NOTE` ("A lean-marked spec IS present …") is folded into the class-(b) reason, and no
  chain-suite case greps for it — `class_b()` matches on line shape and only requires a non-empty
  reason. Verified equally unasserted at `b55e701`, so this PR neither introduces nor worsens it;
  it reshaped three untested lines into one untested clause.
- **The `design-evidence: not-applicable` branch is unexercised.** `check-lean-chain.sh:768-772`
  (armed spec + committed receipt + absent verdict record). No case drives that combination.
  Also pre-existing: the plain `echo` it replaces was equally untested at `b55e701`. Harmless in
  isolation — a missing verdict is independently a violation via `delegate verdict`.

## Strengths

- **The silencing is print-only.** Every exit path is untouched: `run_arms` still returns 1 on
  violations, `check-lean-chain.sh` still exits 1, and `delegate` still propagates the payload's
  rc=2. A gate that got quieter did not get more permissive.
- **The new emitter fails closed.** An unknown disposition routes to `envfail` (rc=2), and the
  consumer template maps rc=2 to `bad`, not to a pass — a vocabulary typo cannot become a silent
  green.
- **(dd1)/(dd2) lift the real function bytes** out of the tool rather than re-declaring them, which
  is the shell analogue of `runtime-shim-lib.mjs` and the right answer to this repo's
  mirror-harness ban.
- **The cases that genuinely lost an observable were re-armed, not downgraded.** (X2b) moved onto
  (X3)'s failure line *and* to the point where the receipt actually exists to do the shadowing;
  (M2) was vacuous before this change (it drove the body fallback on a prefixed branch, which
  never reaches the body) and now runs outside the namespace. (V6a) is new coverage the ticket did
  not require.
- **The one unreplaceable loss is disclosed rather than papered over** — in D-5, in the case
  comment, in the intent-gap record and in the PR body, with the operator's ratification cited.

## Panel

`maintainability` and `test-coverage` went dark on the first fan-out and were **re-dispatched**;
both returned on the retry, so this round has full panel coverage — no coverage gap.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | Pass | 12/12 scope items satisfied |
| Security | Pass | 0 (3 suppressed, < 80) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 (1 nit) |
| Maintainability | Pass | 0 |
| Test coverage | Pass | 0 |
| Unit-test mutation | Pass | 3 minor → 1 warning (W-1), 2 pre-existing |

`a11y` and design-fidelity were not routed: no changed path matches
`stageParams.webComponentGlobs` (unset; resolves to the `apps/web/**/*.{tsx,jsx}` default).
This is a shell/docs diff.

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — both artifacts are shell guards and their
CI job log; there is no rendered surface`, and the repo's config declares no `design.provider`.
The disarm is justified on its face: nothing in the diff renders.
