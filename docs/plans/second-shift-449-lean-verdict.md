# lean review verdict — #449

verdict=approve
run_id: review-449-1
session_id: ad30709c-1c41-44e0-9d11-d5373fbe91f5
rounds: 1
pr: #462
reviewed_head: c2cd72c8f56e50696e11f6dc698e3e4fde083eb6
reviewed_patch_id: 2e949bd010550690020a858dcc28d65d51c0a7f0
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch range (`6a6922c..c2cd72c`) — nothing verifiable to inherit, so this round
read the whole diff. Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness. All six returned; none dark. Verdict: **approve, no blockers.**

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Envelope is `{findings, notEvaluated, unadopted}`; `unadopted` is present-and-empty when nothing fires (asserted by the `envelope: three arrays` case and by the three adopted-seam cases). Entries carry `id`/`key`/`evidence`/`proposal`. Exit 0 on every run that ran, 3 on missing/non-JSON/no-arg — all four re-verified by running the suite. |
| AC-2 | satisfied | Ran the matrix directly against the checker: all-three-absent fires `T1.extension-points`; each of `stageWorkflows`, `implementDelegates`, `planGates` individually silences it; `[]` and `null` do **not**. Evidence names the three keys; the proposal names all three with what each buys (§3.6/§3.7/§3.8) and ends with the standard `waiver_hint` string every other check emits. |
| AC-3 | satisfied | `add_unadopted` applies the same `jq -e 'has($k)'` lookup against the same `$WAIVERS` as `add_finding`, inside the checker, so both front doors suppress from one place. Id carries no repo id. Confirmed live: a `grillWaivers: {"T1.extension-points": …}` config emits `unadopted: []` while the unrelated `T2.*` findings still fire. |
| AC-4 | satisfied | doctor's new loop is `echo "[doctor] note …"`, never `bad`, and `FAILS` is untouched. `grill-unadopted` pins rc **0** alongside the text, and `grill-unadopted-waived` pins `summary: 0 failed` plus an explicit absence grep — so the pairing AC-4 turns on cannot pass on a FAIL. |
| AC-5 | satisfied | `onboard/SKILL.md` renders `unadopted[]` as a blocking line, evidence then proposal verbatim, identically to a finding; the accept predicate is restated as "no unwaived `findings[]` and no unwaived `unadopted[]`". The never-author-a-reason rule is retained and now keys off "the entry's `id`". Prose-only and unguardable by CLAUDE.md's rule — read, not mechanized. |
| AC-6 | satisfied | Questions 4, 5, 6, 8 and 9 each gain exactly one benefit clause plus a pointer, no restated paragraph. Every pointer resolves: `docs/extending.md` §3.3 and §3.5 exist, as do `docs/live-render.md`, `docs/team-rollout.md`, and `docs/extension-points.md`'s "Authoring the review-context surface" heading (L39). No new `AskUserQuestion` item; the at-most-one-batch and not-a-wizard framing are unamended. |
| AC-7 | satisfied | `scripts/lockstep-manifest.tsv` gains a DROPPED entry in the house comment form: the coupling, why neither `verbatim` nor `subset-of` can express it, what holds it instead, and a revisit condition. `check-lockstep-pairs.sh`: 24 pairs, 0 failed. |
| AC-8 | satisfied | `config-grill-selftest.sh` gains fires-on-all-absent, silent-per-key (one case each, so a single-key predicate cannot pass), empty-array-is-not-adoption, waiver-suppresses, never-leaks-into-`findings[]`, present-and-empty, and the widened envelope case. `doctor-selftest.sh` gains `grill-unadopted` (rc-pinned) and its waived counterpart. Both suites run green here; both CI selftest lanes pass. |
| AC-9 | satisfied | The antecedent is empty and that was verified, not assumed. With `k=2`, ordinals 1–2 for every operator sit on identical lines at `main` and at this head for `doctor.sh` — `cmp-eq` 139/172, `cmp-z` 68/71, `logic` 28/56, `detector` 230/231, `default` 28/32 — because the added lines land at 371+, past the budget. So `logic::1/2`, `detector::1/2`, `default::1/2` still name the same sites and no row was re-keyed. `config-grill.sh` owns no baseline or catalog row and swept 7 applied / 7 killed / 0 survived. `mutation-sweep-pr` PASSED having computed 22 real verdicts — not a zero-verdict green. |
| AC-10 | satisfied | The `grillWaivers` row now says the key waives **two severities** and states which front door does what with each: a finding blocks onboard and is a doctor `FAIL`; an unadopted entry blocks onboard and is a doctor **note** that leaves the exit code alone. Scope held: `docs/extending.md`'s grill paragraph is scoped to the "a key nothing *sets*" rot and stays true unchanged. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no user-facing rendered surface`, and that
disarm is justified rather than convenient: the change is a CLI checker's JSON envelope, two
callers' terminal output, and skill/doc prose, and this repo's `.claude/second-shift.config.json`
configures no `design.provider`. No handoff link, no `| RS-n |` rows, nothing to hash-verify.

## CI evidence

`lint-and-selftests` PASS · `selftests (macos, bash 3.2)` PASS · `mutation-sweep-pr` PASS ·
`release-pr-gates` skipped. `pr-gates` is red, and its log names exactly one cause — `✗ no
committed verdict record (a file named *-449-lean-verdict.md)`. That is the pre-verdict state the
lean lane is designed to sit in, not a blocker; this record is what clears it.

## Findings

No blockers. Two non-blocking notes and one dismissal.

| # | Severity | Where | Note |
| --- | --- | --- | --- |
| 1 | dismissed | `docs/plans/second-shift-449-lean.md:97` | scope-completeness (conf. 85) read AC-9's "the mutation register is re-keyed in this diff" against a diff that touches neither `tools/mutation-baseline.tsv` nor `tools/mutation-catalog.tsv`, and flagged the gap. It does not hold: the AC is conditional on ordinals actually having re-keyed, and they did not — see the AC-9 row above for the per-operator line numbers, and `mutation-sweep-pr`'s 22 computed verdicts for the empirical half. Recorded so it is not re-raised next round. |
| 2 | note | `doctor.sh:363` | On the commonest repo shape after this ships — no findings, one unadopted seam — doctor prints `ok config grill: no unwaived findings` and then a note about an unadopted capability. Both lines are literally accurate and the exit code is right; the `ok` just lands one line before the thing the reader is about to be told. Cosmetic. |
| 3 | note | `config-grill.sh:392` | `EP_ADOPTED` captures *which* seam silenced the check, but only its emptiness is ever read. Harmless, and the name documents intent — worth a sentence only if a future round wants to say which seam it found. |

## Strengths

- The severity argument is made where it has to survive: the third array's rationale is written
  into `config-grill.sh`'s header, `doctor.sh`'s 7.9 block and `onboard/SKILL.md` in three
  non-duplicating forms, so the next reader of any one of the three front doors finds the reason
  a default is not a defect.
- The silence-on-any-one-seam predicate is guarded one case per key. A predicate that hard-coded
  the first key someone thought of would pass a single-case suite and fail here — which is
  precisely the mutant the PR body reports as killed.
- `grill-unadopted` pins the exit code next to the text. AC-4 is a *pairing*, and a text-only
  assertion would have passed just as happily on a FAIL; the suite refuses that.
- AC-10 was added mid-run for a doc the change falsified, rather than left to a follow-up.
