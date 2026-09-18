# lean review verdict — #844

verdict=approve
run_id: review-844-1
session_id: 1844de75-553e-497c-af60-c12709641eed
rounds: 1
pr: #854
reviewed_head: b13baeb85ce59ddc3e711f509bbbf5656212f870
reviewed_patch_id: dd54a73cca37ef22d5d9f58a36d89d6010fb434f
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full branch range `1b0bb02a..HEAD` (32 files, +578/-1088). The change is strictly
subtractive plus a mechanical rename, and every load-bearing claim in it is mechanically
checkable — so this round checked them rather than reading for them. No blockers.

panel: pipeline default (scope-completeness only); no opt-ins taken — the committed spec's
Decision Ledger carries no `review panel` row and the repo config has no `reviewers.default[]`.
The spec has no `## Design` section, so the design-fidelity dimension is not armed and
`fidelity` is `not-applicable`. security-reviewer, a11y-reviewer and unit-test-mutation-reviewer
were not selected by the declared panel; the security dimension was covered by the lead pass.

Two of the three scope-completeness findings are dismissed on evidence: both asserted that AC-10
and AC-11 carry no oracle output. They are oracle ACs whose commands CI does not run, so this
round **executed** them at the reviewed head rather than citing anything. The third is recorded
below as a departure note.

**Gate run from the branch's own `milestone-gate.sh`**, not the installed 13.1.0 cache — the two
differ and the branch is the subject. The merge-base is `origin/main`'s tip, so main's reader and
the branch's writer are the same generation apart from this diff.

## Independently executed at `b13baeb8`

| Check | Result |
| --- | --- |
| `SKIP_STRESS=1 tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`, cold | 78 scored, 78 run, **0 served from cache**, 0 failed |
| `tools/install-topology-selftest.sh` directly | 53 ran, 53 passed, 3 skipped, 0 red |
| `tools/mutation-sweep.sh --emit-site-keys` | 3694 sites over 72 guards, **0 `lane-env` sites** |
| `mutation-baseline.tsv` keys vs live site keys | 129 rows (103 content keys + 26 catalog ids), **0 stale** |
| `mutation-pair-map.tsv` / `selftest-cache-inputs.tsv` subjects | 0 missing files |
| every `mutation-catalog.tsv` `sed` on a file this PR edits | all still anchor (0 no-ops) |
| `check-lockstep-pairs.sh` | 30 anchors, 0 failed — **31 at base**, so exactly `lane-env-fallback` went |
| `shellcheck -e SC1091,SC2015,SC2181`, `jq empty` | clean |
| `check-frozen-files.sh`, `check-changelog-trailer.sh`, `check-configversion-migration-doc.sh` | pass |
| `operator-override-selftest.sh` with ambient `LANE_ATTEND_MODE=headless` | at `origin/main`: **41 passed, 2 failed** — (s1), (s2). At this head: **43 passed, 0 failed** |

The last row is the falsification of AC-14's own claim, and it holds: the hole reds at
`origin/main` on a lane machine, so deleting the retired-half scrub under AC-5 made it
reproducible rather than caused it.

## The one real correctness risk, and why it is closed

`lane_env_promote` DEFINED each knob (as the empty string) before any read. Dropping it makes a
bare `$LANE_X` an unbound-variable error under `set -u`, and makes a set-but-empty knob
indistinguishable from an unset one for any `${X+…}` reader. Both were checked exhaustively over
the 4+11+2+9+1+1+3+4+4+1 formerly-promoted names:

- Every bare read that remains sits inside an enclosing `${X:-}` test — `boundary-evidence.sh:521`,
  `milestone-gate.sh:1295`/`:1297`, `operator-override.sh:123`, `check-lane-chain.sh:524`,
  `lane-bench-arm.sh:92`/`:103`/`:113`, `run-selftests.sh:258`. Nothing can reach one unguarded.
- `grep -rE '\$\{LANE_[A-Z_]+(\+|:\+)'` over every `*.sh`: **zero matches**. No reader ever
  distinguished set-but-empty from unset, which is what makes the promote's removal a no-op rather
  than a behavior change.

The three consumer-facing knobs the portable payload lost (`LANE_TRACKER_TYPE`,
`LANE_BOT_ENABLED`, `LANE_MARKER_AUTHOR`) all resolve `${X:-}` → empty → **the committed config**,
so a stale `LEAN_*` export now falls back to the repo's own answer rather than to a weaker
default. No consumer template exports any of them.

## Strengths

- The rename is genuinely identifiers-only. Verified from the other side: `lane-progress`,
  `lane-claimed`, `-lane.md`, `-lane-verdict.md` and `lane-pr-marker` all return **zero files** at
  head, so no wire value was swept up by the substitution AC-8 forbids.
- Rewording the two `mutation-baseline.tsv` notes instead of excluding them is the right call and
  the diff is minimal — word-diff shows four token-level edits, no row re-keyed.
- The `seam-scrub` LOCKSTEP pair moved on both sides, which is the one edit in here a one-sided
  rename could have made silently wrong.

## Critical (must fix before merge)

None.

## Warnings (should fix)

None.

## Suggestions (consider)

- [Complexity] `plugins/dev-pipeline/tools/operator-override.sh:301` — with the retired-path
  fallback gone, `override_register_path()` is a one-line `printf '%s' "$1/$OVERRIDE_REGISTER_REL"`
  with exactly one caller (`:503`). It is now pure indirection; inlining it would delete the last
  trace of the two-path resolver. Not a defect, and keeping the name is defensible.

## Departure note (not a blocker)

- [Scope completeness] `docs/plans/second-shift-844-lean.md:114` — **AC-14 exists in the committed
  spec and not in issue #844's body**, which carries AC-1..AC-13. The commit it authorizes
  (`b13baeb8`) is one line, is forced by AC-5's deletion of the retired-half scrubs, and its
  premise is measured above. The spec is the definition of done for this lane, so the criterion is
  scored, but a human reader comparing issue to PR will not find AC-14 on the issue. AC-9's literal
  "one PR, two commits" is likewise contradicted by the branch's four commits — the milestone-1
  spec commit and this AC-14 fix are the two extra, and neither is the removal or the rename, so
  every operative clause of AC-9 (verbs, `BREAKING CHANGE:` footer, the four migration steps, the
  separate rename commit with `Changelog: none`) holds.

## Dismissed subagent findings

- [Scope completeness] "AC-10 not evidenced: no cold full sweep and no install-topology run in
  evidence" (blocker, confidence 90) — **dismissed**. Both were executed in this round at this head;
  counts in the table above. The reviewer was reading the diff and the progress record, where an
  oracle AC's output does not live; milestone-3's 71s run is not AC-10 and defers the subject suite,
  which is why AC-10 names the two commands explicitly.
- [Scope completeness] "AC-11 not evidenced: no `--emit-site-keys` evidence" (major, confidence 85) —
  **dismissed**, same ground. Run in this round: 3694 sites, 0 `lane-env`, 0 stale register rows.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
|---|---|---|---|
| Scope Completeness | Pass (3 findings; 2 dismissed on executed evidence, 1 recorded as a departure note) | 3 | 85-90 |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 1 | 75 |
| Maintainability | Lead pass — ✅ | 0 | — |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** Yes

**Reasoning:** Every acceptance criterion is satisfied and the two oracle ACs were executed rather
than cited. The one genuine hazard in a promote removal — `set -u` on a bare read, and `+`-form
readers — was checked exhaustively and is closed. The scope gate's two blockers rest on absent
evidence that this round produced.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lane-env.sh` + both inline twins deleted (lockstep 31→30 anchors, exactly `lane-env-fallback`); all 8 load sites and their `exit 2` branches, all 10 `lane_env_promote` calls and lane-bench's 2 explicit `lane_env` mappings gone — `git grep -F lane_env` = 0. No read site changed; every remaining bare read is `${X:-}`-guarded and no `${LANE_*+…}` form exists. |
| AC-2 | satisfied | `operator-override.sh:211` holds `OVERRIDE_REGISTER_REL='.claude/lane-overrides.tsv'` alone; `OVERRIDE_REGISTER_REL_RETIRED` and the fallback arm are gone, both outside the `override-record-reader` block, which `check-lockstep-pairs.sh` passes. |
| AC-3 | satisfied | `second-shift-ci-check.sh` reads `SECOND_SHIFT_BOUNDARY_EVIDENCE` only — the promote block at `:158-168` and the seam's doc line at `:39` removed; `git grep -F SECOND_SHIFT_LEAN_EVIDENCE` = 0. |
| AC-4 | satisfied | `git grep -F 'LEAN_'` / `'lean_'` / `'lean-overrides'` outside `docs/plans/` and `CHANGELOG.md` = **0, 0, 0**. The two `mutation-baseline.tsv` notes are reworded, not excluded (word-diff: 4 token edits, no row re-keyed). |
| AC-5 | satisfied | `lane-env-selftest.sh` deleted (-359). All 6 suite-scope and 3 non-suite retired-half scrubs removed; checked each for a current-spelling hole left behind — only `operator-override-selftest.sh` had one, which AC-14 closes. |
| AC-6 | satisfied | 2 `mutation-catalog.tsv` rows, 8 `mutation-pair-map.tsv` rows and 3 `selftest-cache-inputs.tsv` closures + comment block dropped. Re-validated live: 129 baseline rows 0 stale, 0 missing subject files, every catalog `sed` on a touched file still anchors. |
| AC-7 | satisfied | `docs/config-schema.md` keeps the current-naming statement and drops every compatibility clause and the `lean-overrides` sentence; the `WHY THIS EXISTS` headers went with their sites; `reconcile-selftest.sh:164` rewritten. Nothing describes the layer in the past tense. |
| AC-8 | satisfied | Verified from the negative side: `lane-progress`, `lane-claimed`, `-lane.md`, `-lane-verdict.md`, `lane-pr-marker` return **0 files** at head. `LANE_PR_MARKER_TAG='lean-pr-marker'` and the `lean-pr-marker` block id retained. |
| AC-9 | satisfied | `516b8481` is `feat(dev-pipeline)!` with a `BREAKING CHANGE:` footer and a `Changelog:` trailer carrying all four migration steps; `b9ac811a` is the separate rename commit with `Changelog: none`. `check-changelog-trailer.sh` and `check-frozen-files.sh` both pass. The branch carries four commits, not two — the milestone-1 spec commit and the AC-14 fix; see the departure note. |
| AC-10 | satisfied | Executed this round, not cited. Cold sweep: **78 scored, 78 run, 0 served from cache, 0 failed**. `install-topology-selftest.sh` directly: **53 ran, 53 passed, 3 skipped, 0 red**. |
| AC-11 | satisfied | Executed this round: `--emit-site-keys` → 3694 sites over 72 guards, **no `lane-env` site**; 129 baseline rows 0 stale; `mutation-pair-map.tsv` and `selftest-cache-inputs.tsv` name 0 missing files. CI's `mutation-sweep-pr` is green at this head. |
| AC-12 | satisfied | 0 `lean_` occurrences remain. Word-diff over all 5 files shows identifier-only substitution — no quoted, slashed, dotted or hyphenated occurrence moved. `lean_count` → `lane_prog_count`, avoiding `milestone-gate.sh`'s existing `lane_count`. |
| AC-13 | satisfied | 10 `lean-*` block ids renamed (`lane-output-dispositions`, `lane-verdict-suffix`, `lane-producer-capabilities`, `lane-inherited-key`, `lane-session-set`, `lane-design-armed`, `lane-design-provider-family`, `lane-cost-block-bounds`, `lane-record-key`, `lane-progress-ts-re`); `lean-pr-marker` kept. `check-lockstep-pairs.sh`: 30 anchors, 0 failed. |
| AC-14 | satisfied | `operator-override-selftest.sh:67` now `unset LANE_ATTEND_MODE` suite-wide. Measured both sides with an ambient `LANE_ATTEND_MODE=headless`: `origin/main` → 41 passed, **2 failed** ((s1), (s2)); this head → **43 passed, 0 failed**. The hole predates the PR, as the spec claims. |
