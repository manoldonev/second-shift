# lean review verdict — #711

verdict=approve
run_id: review-711-1
session_id: b8773896-40a1-4232-ab6e-25396b25ac88
rounds: 1
pr: #744
reviewed_head: 6f810c0f3fb7025661339f1a91cfebc9fdeb1d64
reviewed_patch_id: 71c73c5f4083f4a76cb6688c94b9901fddea3c69
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:security-reviewer,review-toolkit:performance-reviewer,review-toolkit:maintainability-reviewer,review-toolkit:complexity-reviewer,review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Round 1 — PR #744 (issue #711) — approve

Range read: `d901b05b..HEAD` — the whole branch diff (17 files, +935/-65). Root round, nothing
to inherit. Read the spec, the plan-walk, the whole new milestone-3 arm, both selftest suites,
`docs/live-render.md`, and the four repo registers the change touches.

Panel 5/6 alive (security, performance, maintainability, complexity, scope-completeness), zero
panel blockers. `test-coverage-reviewer` went **dark** (`died-after-retry`, turn-budget cap) —
`[Coverage gap]`. Its domain is the one this change leans on hardest, so I derived it myself
rather than assume it: I enumerated every arm of `render_measure_state` against the `(dpx*)` case
list, probed the one arm with no case, and executed three of the nine new catalog mutants.

## Verdict

**approve.** No blockers. 11/11 ACs satisfied. Two warnings and one nit, all recorded below;
none of them makes an AC unmet and none is worth a build-and-review pair.

`pr-gates` is red on exactly one thing — `[lean-evidence] ✗ no committed verdict record` — which
is this artifact. Steps 3–5 (frozen files, `Changelog:` trailer, pipeline chain) all passed; step
6 is the last step in the job, so nothing was skipped behind it. Not scored.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `lean-gate.sh` `render_measure_state` (the `mw[node] == "!"` arm) | The only new arm with **no fixture**. `(dpx1)`–`(dpx12)` cover every other refusal — separator, non-integer axis, missing node, omitted axis, missing file, unparseable file, both comparison arms, the stray RS row, the tolerance guard, the receipt row. A rects entry that is *present but not an object of numeric width/height* has neither a case nor a catalog row. It is also the arm that puts a non-numeric axis on the **absent** budget while its `(dpx8)` sibling (axis omitted) is on the **fix** budget — a live distinction nothing pins, so a later edit could swap them silently. |
| W2 | warning | `lean-gate.sh` `render_measure_state` PASS 2 (`if (nax > 0)`) | A state whose every `px` cell is `-×-` yields `nax == 0` and **no comparison at all** — no `shape`, no `scale`, green. Node existence is still checked, so it is partial rather than total blindness, and guess-point 4 blesses an RS row with nothing to report, so closing it would contradict a decided point. The PR body flags it. Recording it because it is the one remaining shape in which an armed run reaches a green milestone 3 having graded no number, and nothing counts stated axes or says so in the log. |
| N1 | nit | `plugins/dev-pipeline/skills/review-lean/SKILL.md:64` | 5b (ii) still reads "hash-verify every **PNG** the receipt lists". The receipt now carries an `RS-n.rects` row per state, and the paragraph this PR adds twelve lines below tells the reviewer to *cite* those numbers. A reviewer following both literally cites bytes it never hash-verified. Harmless in effect — milestone 3 and `render_bytes_ok` both hash the sibling — but the sentence is now inaccurate about what the receipt contains. |

W1 is a coverage gap, not a defect: I extracted `rects_entries` + `render_measure_state` into an
isolated detached worktree and drove four payload shapes through them —

```
{ "Control": 5 }                      → Control ! !  → B  "…is not an object of numeric width/height"
{ "Control": { "height": "32px" } }   → Control - !  → B  (same)
{ "Control": { "height": null } }     → Control - !  → B  (same)
{ "Control": [32] }                   → Control ! !  → B  (same)
{ "Control": { "height": 32 } }       → Control - 32 → (no finding)          ← control
{ "Control": { "height": 70 } }       → Control - 70 → F  "k=2.188 (scale)"  ← control
```

The arm fires correctly on all four. Nothing in the suite would notice if it stopped.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(dpx1)`: `-×32` / `{Control:{height:107}}` reds rc=1 asserting `RS-1`, `Control`, `design 32`, `rendered 107`, `attempts=1`, **and no manifest**. At one stated axis `k=107/32` makes `shape` exactly 0 and `scale` the reporter — D-16's claim, confirmed by hand. |
| AC-2 | satisfied | `(dpx2)` both halves: 33-vs-32 reaches `rendered 2 state(s)` with zero `out of proportion` / `(scale)` hits; the same tree at `tolerancePx: 0` reds naming `tolerancePx=0` and `rendered 33`, no manifest. |
| AC-3 | satisfied | Both halves separated: `(dpx5)` no sibling → absent budget (`attempts=0`, no manifest); `(dpx6)` node absent from the file → **fix** budget (`attempts=1`), which is D-4's anti-free-retry reading. `(dpx8)` adds the third silence — an axis the plan states and the entry omits. |
| AC-4 | satisfied | `(dpx12)` three legs: the receipt carries 2 `RS-n.rects` rows whose sha the case **recomputes** rather than reads back; the committed receipt is idempotent (`dcalls` unchanged); editing the sibling forces a re-render. Proved live — `lean-measure-rects-row-unanchored` applied to a clean worktree fails exactly that third leg (`1 FAILURE(S)`: "an edited rects file did not stale the receipt, calls=2 (was 2)"). |
| AC-5 | satisfied | Four fixtures + `config-lint-selftest.sh` cases; `schema/…json` `integer`/`minimum: 0`/`default: 2`. jq's `or` short-circuits, so a string `tolerancePx` never reaches `floor` and errors. `docs/config-schema.md`'s `design` row carries the full semantics (optional non-negative integer, default 2, the `.rects.json` join, `shape` vs `scale`), not just the key name. `mutation-sweep-pr` swept `config-lint.sh` for real this PR: applied=10 killed=8, and **both** survivors (`catalog::config-lint-lanes-name`, `…::fail-open::1725a6b8fb0b`) are pre-existing `mutation-baseline.tsv` rows present on `main`, with the baseline untouched by this diff. |
| AC-6 | satisfied | The AC's own §3 enumeration — missing file, missing node, unparseable `px`, `shape`, `scale` — has a row each, plus four more (both verdict raisers, the receipt anchor, the plan columns). **The named one is proved**: `lean-measure-scale-arm-waived` in an isolated worktree gives `4 FAILURE(S)`, and `(dpx3)` fails with `scale=0 shape=0` — the fail-open flank reported by nothing, exactly as D-15 predicted. `lean-plan-measured-columns-waived` → `3 FAILURE(S)`, `(dp12)`/`(dp13)`/`(dp14)`. Liveness extended: `(lean-design-measure)`, a red/green pair through the whole armed chain. `feat(dev-pipeline):` + a `Changelog:` naming the harness migration. |
| AC-7 | satisfied | `(dpx3)`: heights 70/110 against 32/50 → `k=2.194`, `scale` named **once**, `shape` zero. Re-derived by hand: `r=[2.1875, 2.2]`, `k=2.19375`, per-node shape residuals 0.2 and 0.3125, both inside tolerance. The liveness leg walks the same class at `k=2.000`. |
| AC-8 | satisfied | `(dpx4)`: four stated axes at 0.9/0.9/1.1/1.1 put `k` at exactly 1.0, so **no** node is explained by a common factor — the exact complement of `(dpx3)`. Asserts 4 `out of proportion` occurrences (counted, not `grep -c`), Header/Body/Footer all named, and `attempts=1`. |
| AC-9 | satisfied | `docs/live-render.md` states `{out}.rects.json` in the placeholder list beside `{out}`, the literal path derivation, the CSS-pixel obligation with the `deviceScaleFactor: 2` consequence, the `{}`-for-nothing rule, and omit-the-key-and-be-red for an unresolvable node and for an unresolvable axis. It also retires its own "would need a ticket of its own" deferral rather than leaving it contradicting the shipped arm. |
| AC-10 | satisfied | `review-lean/SKILL.md` 5b gains "A sizing row cites the measurement, not the picture" — the `rendered` cell is the rects value, not a reading off the PNG. (See N1 for the sentence twelve lines above it that did not move.) |
| AC-11 | satisfied | `figma-faithful` step 7 declares `node`/`RS`/`px` beside `dimensions` with a worked two-row table using `320×604` / `-×412`, and states why `dimensions` stays prose. `step 9` in the new text agrees with the file's existing self-verify reference at `:303`. |

## What I re-derived rather than took on the PR's word

**The separator is one byte-identical character in both files.** `sep='×'` in the gate hexdumps
to `c3 97`; `320×604` in `figma-faithful/SKILL.md` hexdumps to `c3 97`. An ASCII `x` in either
would red every armed run at milestone 3 with an unactionable message, and no test spans both
files. `index`/`substr`/`length` are internally consistent under both a byte-oriented awk and a
character-oriented one, so the two CI lanes agree.

**The catalog anchor obligation, which CI could not check here.** `mutation-sweep-pr` **deferred**
`lean-gate.sh` (`slow suite … 212s`), so its anchor-drift check never ran on the guard this PR
rewrites 330 lines of. I applied all **55** `lean-gate.sh` rows (46 inherited + 9 new) to this
head with the sweep's own `sed -E`: 0 invalid programs, 0 byte-identical results. Ids unique
across the file.

**The three mutants I executed, each in its own detached worktree at this head:**

| Row | Result | Cases |
| --- | --- | --- |
| `lean-measure-scale-arm-waived` | `4 FAILURE(S)` | `(dpx1)`, `(dpx2)`×2, `(dpx3)` — and `(dpx3)`'s diagnostic is `scale=0 shape=0` |
| `lean-measure-rects-row-unanchored` | `1 FAILURE(S)` | `(dpx12)` third leg only — a precise, non-collateral kill |
| `lean-plan-measured-columns-waived` | `3 FAILURE(S)` | `(dp12)`, `(dp13)`, `(dp14)` |

The remaining six I verified apply non-trivially, and `mutation-merge.yml` grades them where a
slow-suite row is actually graded.

**No lockstep break on the widened receipt anchor.** Every other `RS-[0-9]+` anchor in the repo
(`check-lean-chain.sh:393`, `lean-gate.sh:3104/3247/3351`) reads the **spec's** `## Design` table
or the verdict record's evidence table, never the render manifest. `check-lean-chain.sh` reads
only `rendered_from` from the receipt, so the second row per state reaches no other parser.

**The suites ran; the green is not cached.** Neither `lean-gate-selftest.sh` nor
`scenario-liveness-selftest.sh` has a row in `tools/selftest-cache-inputs.tsv`, so neither could
be the "1 served from cache" in `lint-and-selftests`' `77 scored, 76 run, 0 failed`. Both CI
selftest jobs ran at `headSha 6f810c0f` — this exact head — so I cite them rather than re-run.

**Repo registers, re-run locally at this head:** `check-gate-buckets.sh` rc=0 (5 new rows for 5
new refusal sites), `check-lockstep-pairs.sh` rc=0, `prose-blockers.sh check` ✓ zero
undispositioned (census 26 over 51 files — the SKILL.md additions name no stop).

## Design fidelity

`not-applicable`. The spec carries no `## Design` section (unarmed, not disarmed), and this
repo's config declares no `design.provider` — so step 5b does not apply and there is no disarm
to justify.
