# Plan: bring `plan-reviewer` under the emit-deadline contract (#232)

## Context / problem framing

`plan-reviewer` dies at its turn cap before emitting a verdict, and `check-emit-deadline.sh` — the lint built to catch exactly that — cannot see it.

The lint's jurisdiction gate is one line:

```bash
[ "$cap" -gt "$DEFAULT_CAP" ] || continue     # check-emit-deadline.sh:83, DEFAULT_CAP=15
```

`plan-reviewer.md` carries `maxTurns: 15` — exactly the default — so it is skipped, and the lint reports `clean — 0 above-default agent(s)` while the agent it exists to protect dies on ordinary workloads (#212 Stage 4: three `plan-review.mjs` dispatches for one verdict, four of six agents empty, 17.3 min).

The threshold encodes an assumption the script states in prose:

> Agents AT or BELOW the default cap are not required to carry a deadline: they are held by the dispatch-time bounding nudge instead, which is `check-bounded-exploration.sh`'s jurisdiction.

**For `plan-reviewer` that sentence is false.** Its dispatch site declares the nudge dormant:

```js
// bounded-exploration-dormant: BOUNDED_PLAN_GROUNDING -- defined for probe lockstep; deliberately not appended (measured no-nudge arm)
```
— `plugins/dev-pipeline/skills/run/workflows/plan-review.mjs:60`

So `plan-reviewer` is held by **neither** mechanism: not bounded at dispatch (deliberately, as the measurement control arm), and not deadline-linted in its doc (because it sits at the cap). It falls through the gap between two complementary lints. That is the actual defect, and it is narrower than "the threshold is wrong" — the threshold is fine for the 15 agents whose dispatches *are* nudged.

## Assumptions

- `plan-reviewer`'s dormant bounding nudge stays dormant. This plan does not touch `plan-review.mjs`; the deadline is the doc-side complement, per the issue's "the deadline is the fix; the cap is not".
- The two above-default agents (`scope-completeness-reviewer`, `unit-test-mutation-reviewer`) keep their current behavior verbatim (AC-3).
- CI discovers `*-selftest.sh` by glob, so `check-emit-deadline-selftest.sh` needs no registration and is the enforcement path.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the default-cap opt-in lives: agent doc marker vs. lint script list | Lint script (`DEADLINE_AT_DEFAULT` name list). Removing an enrollment is then visible in the lint's own diff, not buried in an agent's prose. A doc-side marker would be a one-line silent un-enrollment — reproducing the invisibility class this issue fixes — and the existing `emit-deadline-exempt` waiver requires a stated reason precisely because silent waivers were the hazard; an opt-*in* marker has no such guard. A script-side list also cannot loosely sweep in `security-reviewer.md`, which already carries a conforming deadline at cap 15. | codebase-derived |
| D-2 | The deadline turn number for `plan-reviewer` | Turn 10. The lint requires `D <= ceil(2N/3)`, computed as `(2*15+2)/3 = 10` in integer arithmetic, so 10 is the only value that both maximizes exploration and passes. `security-reviewer.md:54` is the in-tree precedent at the same cap: "By **turn 10** (of your 15 maximum)". | codebase-derived |
| D-3 | Whether the deadline ships with a degradation clause | Yes. All three in-tree deadline holders pair the deadline with an explicit under-budget contract (`security-reviewer.md:54`, `scope-completeness-reviewer.md:140`, `unit-test-mutation-reviewer.md:53`). Without one, forcing an emit at turn 10 risks converting today's loud dark verdict into a silent `pass` — `plan-reviewer.md:102` states "a clean plan with zero findings is the correct output" — which would make the gate weaker, not stronger, on the workload being fixed. | codebase-derived |
| D-4 | How the selftest exercises enrollment without coupling fixtures to production enrollment | `DEADLINE_AT_DEFAULT` is env-overridable (`${DEADLINE_AT_DEFAULT:-plan-reviewer}`). Fixtures set their own name; the real-tree case uses the built-in default and so proves `plan-reviewer` specifically is enrolled. Mirrors the established `BRANCH_PREFIX` env seam in `tools/max-pushed-slice.sh`. `:-` (not `-`) means an exported empty value cannot silence the lint. | codebase-derived |
| D-5 | Scope of the "enrolled name resolved to a real file" assertion | Live-scan only (no explicit dir args). With explicit dirs the caller has scoped the scan, so a missing agent there carries no signal — and running it unconditionally would fail every existing fixture case, which passes synthetic single-agent dirs. | codebase-derived |
| D-6 | Whether the lint's operator-facing text is in scope | In scope. Scope item 2 changes the lint's jurisdiction, and the FAIL message, both summary lines, and the header rationale block all assert the old jurisdiction. Left alone, an enrolled default-cap failure would print "maxTurns:15 is above the default 15" — self-contradictory — and the header would keep asserting a claim that is false for the one agent being enrolled. | codebase-derived |

## Affected files/modules

| File | Change |
| --- | --- |
| `plugins/review-toolkit/agents/plan-reviewer.md` | Add the emit deadline + degradation clause to the `## Workflow` section. Body only — frontmatter untouched. |
| `plugins/review-toolkit/scripts/check-emit-deadline.sh` | Add the `DEADLINE_AT_DEFAULT` `[NEW]` enrollment list, widen the jurisdiction gate, add the enrollment-resolution assertion, reword the jurisdiction-asserting messages + header block. |
| `plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh` | Add fixture cases A10–A13 `[NEW]` and real-tree cases B3–B4 `[NEW]`. Existing A1–A9, B1–B2 unchanged. |

All three exist (read at `origin/main` @ `d2fdc2b`). No new files. Unverified references: none.

## Reuse inventory

- `check-emit-deadline.sh`'s existing downstream checks — waiver extraction, deadline regex, `cited != cap`, `deadline >= cap`, `ceil(2N/3)` ratio — are reused **unchanged** for both jurisdictions. Only the gate that decides *whether* an agent is checked moves.
- `write_agent()` (`check-emit-deadline-selftest.sh:32-45`) — the existing fixture builder, reused for A10–A13.
- `run_check()` (`:47-50`) — existing fixture runner; A10–A13 need the env override, so they call `bash "$CHECK"` with `DEADLINE_AT_DEFAULT=` prefixed rather than extending the helper's signature.
- `security-reviewer.md:54` — the deadline + degradation sentence shape, mirrored (not copied verbatim; the degraded output differs per agent).
- `none — no new helpers introduced`.

## Implementation steps

1. **Selftest first (red).** Add cases A10–A13 `[NEW]` + B3–B4 `[NEW]` to `check-emit-deadline-selftest.sh` and run it. Expect A10, A12, B3, B4 to FAIL against the unmodified lint — this proves the cases are non-vacuous before any production edit. (A11 and A13 pass trivially pre-change, since an unenrolled cap-15 agent is skipped; they become meaningful once the gate widens.)
2. **`check-emit-deadline.sh` — enrollment list.** Add `DEADLINE_AT_DEFAULT` `[NEW]` — `DEADLINE_AT_DEFAULT="${DEADLINE_AT_DEFAULT:-plan-reviewer}"` — next to the existing `DEFAULT_CAP`, with a comment recording *why* enrollment lives here (D-1) and the "add a name only on a demonstrated death, not prophylactically" boundary.
3. **`check-emit-deadline.sh` — widen the gate.** Hoist `name`/`agent` computation above the cap filter, then replace `[ "$cap" -gt "$DEFAULT_CAP" ] || continue` with the negated two-way OR: skip only when the agent is at-or-below the default cap **and** not enrolled. Track each enrolled agent actually seen.
4. **`check-emit-deadline.sh` — FAIL message.** Branch the no-deadline message on jurisdiction so an enrolled default-cap agent reads "is at the default cap and is enrolled in the deadline contract" instead of the self-contradictory "above the default 15".
5. **`check-emit-deadline.sh` — enrollment-resolution assertion.** In live-scan mode only (D-5), FAIL for any enrolled name that matched no agent file, naming it. A typo'd or renamed enrollment must be loud, not a silent no-op.
6. **`check-emit-deadline.sh` — summaries + header.** Change both summary lines from "above-default agent(s)" to the jurisdiction-neutral "linted agent(s)", and rewrite the header's "Agents AT or BELOW the default cap…" paragraph to state the enrollment exception and record that `plan-reviewer`'s dispatch nudge is dormant, so it was covered by neither lint.
7. **`plan-reviewer.md` — deadline.** Add to `## Workflow`: `By **turn 10** (of your 15 maximum) you MUST be writing the verdict block.` plus the degradation clause — no further tool use after turn 10 except emitting; unverified checks are named rather than silently dropped; a truncated review must not return `pass` with zero findings.
8. **Green.** Re-run the selftest (expect all cases pass), then the repo's three verification sweeps.

## Test strategy

Verify-after for the lint mechanics, but **test-first for the new cases** (step 1): each new assertion is confirmed red against the unmodified lint before the lint changes, so none of them can be a case that passes for the wrong reason. This is the repo's stated bar — a case that cannot fail is not coverage.

Per-tool behavioral selftest is the correct tier here (`docs/testing.md`): this guards one script's behavior against fixtures. No scenario, lockstep row, or runtime-shim case applies — `check-emit-deadline.sh` composes into no pipeline verdict path, and no second copy of its contract exists.

New cases:

| Case | Fixture | Expect | Guards |
| --- | --- | --- | --- |
| A10 | enrolled agent, `maxTurns: 15`, no deadline | rc=1, message names enrollment | AC-2 negative — the core new behavior |
| A11 | enrolled agent, `maxTurns: 15`, "turn 10 (of your 15 maximum)" | rc=0 | AC-2 positive |
| A12 | enrolled agent, `maxTurns: 15`, "turn 11 (of your 15 maximum)" | rc=1 | ratio rule applies at the default cap too (the D-2 arithmetic) |
| A13 | **non**-enrolled agent, `maxTurns: 15`, no deadline, while another name is enrolled | rc=0 | enrollment is per-agent, not a blanket cap-15 requirement — the deferred scope stays mechanically deferred |
| B3 | live tree, `DEADLINE_AT_DEFAULT` set to a non-existent agent | rc=1 | a typo'd enrollment is loud, not silently unchecked |
| B4 | live tree, default enrollment | `plan-reviewer` appears in lint output | `plan-reviewer` cannot be silently dropped from the lint — the B2 coverage shape |

Existing A6 (`default-cap agent without a deadline is accepted`) is left **unchanged** and is load-bearing: with A13 it is the pair that keeps the explicit non-goal — deadlines for all 16 default-cap agents — mechanically deferred.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `plan-reviewer.md` declares a lint-parseable deadline below its cap | 7 | B1, B4 (live tree passes the lint with `plan-reviewer` in jurisdiction) |
| AC-2 | Lint checks `plan-reviewer`; removing the deadline FAILs | 2, 3, 4, 5 | A10 (AC-2), A11 (AC-2), B4 (AC-2) |
| AC-3 | Above-default behavior unchanged | 3 (gate widened by OR, never narrowed) | A1–A5, A7–A9, B1, B2 — all unmodified |
| AC-4 | Selftest covers the new default-cap case and the unchanged above-default cases | 1 | A10–A13, B3, B4 added; A1–A9, B1–B2 retained |

## Verification commands

```bash
# Targeted (the tier that owns this change)
bash plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh
bash plugins/review-toolkit/scripts/check-emit-deadline.sh

# Repo sweeps (CLAUDE.md)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

The diff is `.md` + `.sh` only, so Stage 6's verifyctl lanes are inert here; the sweeps above are run by hand and reported.

## Risks / rollback notes

- **A forced emit could produce a confidently ungrounded `pass`** — the substantive risk, and the reason D-3 pairs the deadline with a degradation clause. Residual risk remains (the clause is prose an agent must honor, and no lint can verify that a given verdict was well-grounded). It is bounded: today's failure mode is a *guaranteed* empty result on the affected workload; the new one is a possible weaker verdict that at least names its gaps. Effectiveness is only observable across future Stage-4 runs, so this stays a watch item rather than a claim.
- **Enrollment is a manual list.** A future default-cap agent that starts dying is not auto-detected. Accepted deliberately — auto-enrolling all 16 is the explicitly deferred scope. B3 keeps the list honest about names it does contain.
- **Rollback:** revert the commit. The lint's above-default path is untouched, so a revert cannot leave the two above-default agents unguarded.

## Out-of-scope

- Adding deadlines to the other 15 default-cap agents (explicit non-goal; guarded by A6 + A13).
- Raising `plan-reviewer`'s `maxTurns` — measured to fail twice (#175: 15→30, died again at 31/33 calls).
- Un-dormanting `BOUNDED_PLAN_GROUNDING` in `plan-review.mjs`. That is the deliberate no-nudge measurement arm; changing it would destroy the control and is a separate decision.
- `check-bounded-exploration.sh` — different jurisdiction (`.mjs` dispatch sites, not agent docs).
