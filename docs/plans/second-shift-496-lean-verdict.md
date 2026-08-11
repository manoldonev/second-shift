# lean review verdict — #496

verdict=approve
run_id: review-496-1
session_id: 3a825aab-f272-4174-81dd-e1e137e4dbab
rounds: 1
pr: #508
reviewed_head: 8e05f55f1c97851e76a353720949b9b0fa9b3567
reviewed_patch_id: 428c406e2970c5872e1d7a67f7631fd7e30de04b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 1, full branch range (`3cf27cd..8e05f55`, 7 files, +751/-117). The change does what the
spec says: `lean-gate.sh 4`'s twenty `fail_milestone 4` sites each carry an explicit class, the
scheduler routes each class to a distinct action, and `PRECHECK` becomes a documented
`LEAN_GATE_OBSERVE` seam that classifies without recording. All ten `AC-n` are satisfied and
independently verified. Six reviewers ran, none dark, all `approve`; `scope-completeness-reviewer`
returned `approve` with one minor note on the two departures the spec already discloses. No
blockers — two warnings, both about artifact accuracy rather than behavior.

## Strengths

- **The vacuity controls are the best part of this diff.** Every new zero-or-absence assertion is
  paired with a positive control that proves the measurement is live: `(r7)` drives the fake gate
  *without* the seam so `(r5)`'s zero recording-path calls is a measurement rather than a dead
  writer; `(ac5)` reruns the same evaluation on the recording path so `(ac4)`'s unmoved counter
  means something; `(ac-d3)` restores the fixture to show `(ac-d1)`/`(ac-d2)` each turned on their
  one fact; and both config cases assert their corrupt fixture really fails `jq empty` before
  relying on it. That is precisely the shared-fixture vacuity class this repo has been bitten by.
- **`(ac1)` is scoped as a backstop, not a substitute.** It pins the site count and class multiset
  — the one thing no behavioral case can cover, since a twenty-first unclassified site defaults to
  `1` silently — while all twenty arms that *do* exist keep their own behavioral rc assertion,
  including the two (`(ac-d1)`/`(ac-d2)`) that no case previously reached.
- **AC-5's documentation half is guarded structurally, not by grepping prose.** The seam's usage
  lines sit inside `--help`'s `sed -n '2,160p'` range, which case `(w)` guards against silent
  truncation. Grepping the help text for `LEAN_GATE_OBSERVE` would have been the prose-presence
  guard the repo forbids; this avoids it.
- **Both mechanical rationales are correct and load-bearing.** The config check sits outside `cfg`
  because `cfg` is called as `$(cfg …)` where an `exit` kills only the subshell, and `resolve_pr`'s
  refusal moved to the caller because a `return 1` inside `PR="$(…)"` is invisible. The new
  `attempt_count` helper's capture-then-default likewise avoids `grep -c`'s "prints 0 *and* exits
  1" trap — in a suite whose whole purpose is asserting a zero.

## Critical (must fix before merge)

None.

## Warnings (should fix)

- **[Maintainability] `docs/plans/second-shift-496-lean.md:47` (confidence: 95) — the site table's
  line numbers are `origin/main`'s, not "this head" as the table's own parenthetical claims.**
  The section says "(line numbers at this head; the ticket's cite the pre-#492 file, uniformly 141
  lines earlier)", but every one of the twenty numbers is 49 lines low against `8e05f55`:
  `:2521`→`:2570`, `:2565`/`:2570`→`:2614`/`:2619`, … `:2720`→`:2769`. The class *assignment* is
  correct at every site — I verified all twenty independently — and `(ac1)` pins the mapping by
  content rather than by line, so nothing consumes these numbers. But the register is meant to be
  the reader's index into `cmd_4`, and opening `lean-gate.sh:2521` now lands on unrelated code
  while the artifact asserts it will not. Re-derive the twenty numbers at this head, or say plainly
  that they are `main`'s.

- **[Cross-cutting] `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:936` (confidence: 85) —
  the "misreports the cause" defect survives in one residue: a P10 refusal read after milestone 4's
  budget is spent still reports `4`.** Budget exhaustion outranks the class in the observe path
  (`[ "$count" -ge "$FIX_BUDGET" ] && return 4`, before `return "$class"`), so a class-`6` red on a
  milestone whose count already reached the budget reaches the scheduler as `4` and prints "HARD
  STOP: the verdict gate exhausted its fix budget" for an integrity violation — the exact
  substitution the ticket's opening paragraph is about. The spec argues the case is safe "because
  the scheduler never retries a `6` at all", which answers the *looping* half of the defect but not
  the *messaging* half, and messaging is the half this line decides. It is reachable, not
  theoretical: `build-lean` SKILL.md step 5 has the build session run `bash G 4 <issue>` on the
  recording path and `cmd_all`'s real loop reaches `cmd_4` recording, so three build-side reds
  across a multi-round run spend the budget before the fourth read is ever classified.
  **Not a regression** — pre-`#496` that same state also produced `4` — so this is an unfixed
  residue of the class, not something the PR introduces. Worth either narrowing (let `6` outrank
  exhaustion, since a `6` is terminal in both directions anyway) or recording as a known limit.

## Suggestions (consider)

- `(r10)` and `(ac8)` — the "absent config is legal" half of AC-9 — have no probe row. Their
  corrupt-config siblings are probed (P7/P14, both killed), but nothing demonstrates the
  absent-config cases would red, and they are the pair's guard against an over-broad fail-closed
  regression. A "refuse when the config is absent" probe would close it.

## Plan Compliance

Implementation matches the spec. All ten ACs satisfied (scoring below). The two departures from
the ticket's literal guard obligations are disclosed in the spec's own `## Deviations` section —
every class-flip probe reds `(ac1)` in addition to its named case, and the re-key count is 24 (plus
8 in the liveness file) rather than the ticket's stated 22. Both are descriptive corrections, not
dropped work; the binding obligation ("every one") is met. `tools/mutation-baseline.tsv` is named
in the ticket's file list but untouched — the spec records a measured diff-scoped sweep showing all
four survivor ids are rows that already exist and no ordinal moved, which I confirmed holds.

### Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | 20 sites, class signature `11122555555555555566` (3×`1`, 2×`2`, 13×`5`, 2×`6`) — computed independently, matching the spec's site table site-for-site. `0`/`4` unchanged: `(c1)` `5554`, `(lean-budget)` `5554` with its `budget-exhausted` write. `5`/`6` avoid `2`/`3`/`4`. |
| AC-2 | **satisfied** | `(ac2)` `all`→6 with no milestone-3 marker; `(ac3)` `all`→5; `(lean-taxonomy)`'s `all` triple `1/5/6`. Probe P6 (flat `1` under observe) killed. |
| AC-3 | **satisfied** | 21 `rc -eq 1` assertions re-keyed by call site (16→`5`, 4→`6`, 1→`2`), `(c1)`'s sequence `1114`→`5554`, 8 more in the liveness file. Every re-keyed case still greps its original message; none deleted. |
| AC-4 | **satisfied** | `(r1)`–`(r4)`. Independently probed: P8 (retry loop disabled) → `(r1)(r2)`; P9 (class-6 arm removed) → `(r4)`; P10 (`exit 6` removed) → `(r4)`; P11 (retry bound removed) → `(r2)(r3)`. |
| AC-5 | **satisfied** | Seam documented at `lean-gate.sh:153–158`, inside `--help`'s `2,160p` range that `(w)` guards. `(ac4)`+`(ac5)` control pair; `(ac6)` returns `4` on a spent budget with an unmoved counter. Probes P4 (observe records) and P5 (observe swallows exhaustion) killed. |
| AC-6 | **satisfied** | `verdict_rc` runs `env -u RUN_ID LEAN_GATE_OBSERVE=1`. `(r5)` zero recording-path calls over a full needs-work→approve round, with `(r7)` as its positive control; `(r6)` asserts the seam on the call itself. Probe P12 killed. |
| AC-7 | **satisfied** | Grepped `orchestrate-lean.sh` for every record-read shape — none. Its whole input stays gate rcs, `git rev-parse`, read-only `gh`, and #492's opaque `progress` token. |
| AC-8 | **satisfied** | `resolve_pr` emits `.[].number`; the caller counts and names both. `(r8)`; probe P13 killed. |
| AC-9 | **satisfied** | Both copies guarded, up front and outside `cfg`. Gate: `(ac7)`/`(ac8)`; orchestrator: `(r9)`/`(r10)`; each corrupt case first asserts its fixture really fails `jq empty`. Probes P7 and P14 killed. |
| AC-10 | **satisfied** | `run-lean/SKILL.md` is exactly 60 lines; step 4 lists `0`/`1`/`2`/`4`/`5`/`6` and step 5 routes `5` to a hand review-lean and `4`/`6` to a stop. Substitutive — the surrounding prose was compressed to pay for it. `(n0)` green. |

Design fidelity: **not-applicable**. The repo's config declares no `design.provider`, so the
spec's `## Design` section is not a design-lane declaration (no handoff link, no `| RS-n |` rows),
the render lane is unarmed, and no render receipt is expected.

## Verification run in this round

Cold, in an isolated detached worktree at `8e05f55`, with `CLAUDE_CODE_SESSION_ID`, `RUN_ID` and
`LEAN_RUN_MODEL` scrubbed:

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- `lean-gate-selftest.sh` — all green.
- `orchestrate-lean-selftest.sh` — all green (54 passes).
- `scenario-liveness-selftest.sh` — 90 passed, 0 failed.

CI at this head: `lint-and-selftests` pass, `mutation-sweep-pr` pass, `selftests (macos, bash 3.2)`
pass. `pr-gates` fails on exactly one thing — the absent verdict record — which is what this
record supplies.

**Probe re-run, independently.** Fourteen probes applied verbatim in a worktree isolated from the
one the panel read — 13 of the PR body's 14 rows, plus one of my own — each anchor asserted to
occur exactly once in the whole file before applying (the trap that scored a vacuous green on a
previous run; note `grep -cF` cannot do this for a multi-line anchor, it splits the pattern into
alternatives), each `cmp`-checked to have changed the file and `bash -n`-checked to still parse,
each reverted and revert-verified. **Nothing survived, and every red set matched the PR body's
claim exactly.** Measured:

| Probe | Suite | Cases redded | PR body claims |
| --- | --- | --- | --- |
| P0 — a site's class argument dropped entirely (mine) | gate | `(ac1)` `(j3)` | not in table |
| P1 — class `5`→`1`, missing-`run_id` arm | gate | `(ac1)` `(j3)` | same |
| P2 — class `6`→`1`, P10 build-session arm | gate | `(ac1)` `(n2)` | same |
| P4 — observe mode records an attempt | gate | `(ac4)` `(ac5)` `(ac6)` | same |
| P5 — observe mode swallows budget exhaustion | gate | `(ac6)` | same |
| P6 — observe mode collapses the class into `1` | gate | `(ac2)` `(ac3)` | same |
| P7 — config guard swallows an unparseable file | gate | `(ac7)` | same |
| P8 — class `5` collapsed into the generic arm | orchestrator | `(r1)` `(r2)` | same |
| P9 — class-`6` routing arm removed | orchestrator | `(r4)` | same |
| P10 — class `6` falls through to a round spend | orchestrator | `(r4)` | same |
| P11 — class-`5` REVIEW retry bound removed | orchestrator | `(r2)` `(r3)` | same |
| P12 — `verdict_rc` reverted to the recording call | orchestrator | `(r5)` `(r6)` | same |
| P13 — the caller's >1-PR refusal removed | orchestrator | `(r8)` | same |
| P14 — config guard swallows an unparseable file | orchestrator | `(r9)` | same |

P3 (the chain break moved from `5` to `6`) was not re-run; it is the same class-flip shape as
P1/P2, both of which reproduced. **P0 is the one that mattered most to add:** it drops a class
argument rather than changing it, which is the "twenty-first site added unclassified" shape
`(ac1)` exists for, and confirms that guard is non-vacuous against its actual threat rather than
only against a flipped digit.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 1 | 88 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(default `apps/web/**/*.{tsx,jsx}`). `db`/`pipeline`/`unit-test-mutation` not triggered — no DB,
queue, or co-located-unit-spec surface in the diff.

## Suppressed (below confidence threshold)

- `lean-gate.sh:934` (45) — `LEAN_GATE_OBSERVE` is env-settable, but observe mode never writes a
  `satisfied` line, so no milestone can be credited through it; `PRECHECK` was equally settable.
- `lean-gate.sh:938` (40) — the exhaustion-over-class ordering; promoted to a warning above with
  its reachability established.
- `orchestrate-lean.sh:395` (55) — the observe seam removes the incidental ledger trace of
  scheduler-side verdict reads. That is the intended fix (AC-6), and `lean-reconcile.sh`
  reconciles the committed record rather than scheduler reads.

**Ready to merge?** Yes

**Reasoning:** Every AC is satisfied and independently verified, all three suites are green cold
with the environment scrubbed, and fifteen hand-applied probes confirm the new assertions are
non-vacuous. The two warnings are artifact accuracy (a stale line-number index) and a disclosed,
non-regressing residue of the misreport class — neither is a defect in the shipped behavior.
