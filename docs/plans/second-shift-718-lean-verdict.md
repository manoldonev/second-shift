# lean review verdict — #718

verdict=approve
run_id: review-718-1
session_id: 56f148ab-19d3-4258-9fda-c8f3fd6e05db
rounds: 1
pr: #734
reviewed_head: 9345c4f27671753023ec48bfa55c35bd5f8a0dcf
reviewed_patch_id: 2b6eedc7ee0c1c5df8d1ded4469de79cfe7498c1
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:security-reviewer,review-toolkit:performance-reviewer,review-toolkit:maintainability-reviewer,review-toolkit:complexity-reviewer,review-toolkit:test-coverage-reviewer,review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — PR #734 / issue #718

**Verdict: approve.** Range read: `1d714d4..9345c4f` (root round, full branch diff — `G delta` printed
FULL, nothing verifiable to inherit). Fidelity: not-applicable — the spec carries no `## Design`
section, so step 5b does not arm.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness — 6
selected, 6 returned, none dark. Zero blockers from the panel; every finding below the blocker line
is reproduced in the Warnings/Suggestions sections.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | The amended (D-G) alternation reds on neither file: `grep -cE` returns **0** on `OL` and **0** on `LG` at head, against **33** and **22** at `1d714d4`. |
| AC-2 | satisfied | `(h4)` carries all three arms. Arm 1 asserts `rc=1`, `spawn_count=1`, `inflight_reads=0`, slug `build-no-pr`; arm 2 asserts `rc=1`, `spawn_count=1`, `inflight_reads=1`, slug `build-inflight`, plus the `CWD: $TREE` / no-`RUN_ID` shape; arm 3 asserts `rc=2` with zero spawns on the removed flag. Oracle: CI run 33389198129 at head `9345c4f` — `lint-and-selftests` **success** and `selftests (macos, bash 3.2)` **success**. |
| AC-3 | satisfied | `wc -l` at head: 1044 + 5922 + 1631 + 8479 = **17076** ≤ 17087. Base at `1d714d4`: 1146 + 5997 + 1826 + 8568 = **17537**. Delta −461 against a −450 floor. Both re-derived here, not read from the PR body. |
| AC-4 | satisfied | Multiset `comm` at base vs head. `LGS` 572 → 563: removed exactly `(ir1) (ir2) (ir3) (ir4) (ir9) (ir10) (pg1) (pg2) (pg3) (pg4)`, added exactly `(pg13)`, no third difference. `OLS` 119 → 103: removed exactly `(o1)`–`(o8) (oi1)`–`(oi5) (t1) (t1b) (t3) (t4) (j3) (v4)`, added `(h4)`×3. The seven ids the AC protects — `(ob7) (td2) (if9) (pg7) (pg8) (pg9) (pg10)` — are all present at head. |
| AC-5 | satisfied | `bash scripts/check-gate-buckets.sh` rc=0, 291 sites across 162 rows. The four deleted terminals' rows are gone and `build-no-pr` has one. |
| AC-6 | satisfied | `git grep -o … \| wc -l` returns **6** over **4** lines: `OL:332` names the flag three times (`--max-continuations)`, `usage-max-continuations`, `--max-continuations was removed`), and `OLS:786/788/789` once each. Base 25. `docs/config-schema.md` no longer names it. |
| AC-7 | satisfied | Hand-probed at head, not inferred: bare `progress 718` → rc=2, `unknown progress form: …`; `--satisfied 5` → `m5sat-v1:0` rc=0; `--satisfied 0` → `m5sat-v1:0` rc=0; `--obligations` → the 7-line report rc=0; `--infra` → rc=2 `unknown option`; `--obligations --satisfied 5` → rc=2 refused; `--satisfied` on `staleness` → rc=2 refused. Pinned as `(pg13)`. |
| AC-8 | satisfied | `(lean-inline-m3)` and `(lean-inline-m3-nv)` both present and now assert directly over the `started`/`concluded` residue — the non-vacuity leg survives, which is the mutant the AC names. No `progress --infra` call remains in any shipped script (the four residual hits are `CHANGELOG.md` and three comments). Leg 9 `lean-infrakill` is deleted. |
| AC-9 | satisfied | `jq -e '.hooks.Stop == null'` → true, and `git diff 1d714d4..HEAD -- plugins/dev-pipeline/hooks/hooks.json` is empty. |

## What I verified beyond the AC set

- **Every mutation-catalog anchor on the two changed guards still matches.** All 39 rows keyed to
  `orchestrate-lean.sh` / `lean-gate.sh` were re-applied with `sed -E` against head; all 39 changed
  the file. The probe is not vacuous — a deliberately non-matching control row was appended and
  reported `STALE-ANCHOR` as expected. This matters because `mutation-sweep-pr` **graded nothing**
  at this head: both in-scope guards deferred to nightly (slow suite / multi-suite union), so the
  PR lane supplied no oracle for catalog anchoring at all.
- **`(t4)`'s surviving half is covered even though the spec only claims `(t3)`'s is.** `(t4)` pinned
  "the in-flight check is NOT consulted on the no-PR path"; that ordering survives verbatim in the
  new phase, and `(h4)` arm 1's `inflight_reads == 0` asserts it.
- **`(t2)`** — the in-flight-unreadable stop under a distinct slug — survives and its production arm
  (`*) terminal build-inflight-unreadable`) is intact.
- **D-G is a correction, not a laundering.** `verdict-progress-unreadable` appears twice in `OL` at
  the ticket's OWN base `ff3f6f8`, twice at `1d714d4`, and twice at head — this branch does not touch
  it. The unanchored alternand was unsatisfiable when the ticket was written without deleting a slug
  AC-7 depends on, so anchoring it on `terminal progress-unreadable` narrows nothing the ticket meant
  to catch.
- **Both `--help` sed ranges are correct after the shrink.** `OL`'s header comment ends at 208 and
  `set -uo pipefail` is line 209 (`2,208p`); `LG`'s ends at 262 with code at 263 (`2,262p`).
- **No dangling consumer of a deleted slug.** Repo-wide grep for `build-idle`,
  `build-continuations-spent`, `infra-unreadable`, `MAX_CONTINUATIONS`, `m3infra`, `progress-v1`
  outside `CHANGELOG.md`/`docs/plans` finds only the `(h4)` fixture, the usage refusal itself, and one
  stale comment (see Warnings). `docs/testing.md` and `run-lean/SKILL.md` — named in the ticket's
  Delete list — carried zero continuation prose at `ff3f6f8` already, so that bullet was vacuous when
  written and owes nothing.
- **The re-anchored cases are not vacuous.** `(td2)`, `(pg7)` and `(if9)` each gained an explicit
  anti-vacuity control in place of the discriminating power the deleted broad token used to supply,
  and `(pg9)` still works as `(pg8)`'s positive control. This is the exact failure mode AC-4's mutant
  is aimed at, and the diff does not commit it.

## Warnings (should fix, not blocking)

- **[Test infrastructure] `tools/mutation-catalog.tsv:94`** — the `lean-orchestrate-terminal-code`
  row's rationale names its killers as "(g1) at 2, (i1) at 4, (r2) at 5, (r4) at 6, **(t1) at 1** and
  (v5) at 7 — so a mutant that flattens them all is caught six ways over". This PR deletes `(t1)`.
  The other five ids are present at head, and the row's `sed` anchor still matches, so the mutant is
  still applied and still killed — `(h4)`'s two new arms assert exit 1 and exit 2 directly, which is
  the class `(t1)` uniquely supplied in that citation list. Nothing machine-reads the rationale
  column, so no gate catches this; the cost is that an operator triaging a survivor greps for a case
  id that no longer exists. Swap `(t1) at 1` for `(h4) at 1`.

## Suggestions

- **`orchestrate-lean-selftest.sh:1570`** — an illustrative comment still contrasts
  `staleness-expired` with `build-idle` as terminal classes. It asserts nothing, but it is the one
  place left in a live file where the retired slug reads as current vocabulary. `build-no-pr` is the
  drop-in.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red at this head on the expected pre-verdict condition — no committed verdict record.
`mutation-sweep-pr` is green but graded nothing (both guards deferred to nightly); its real verdicts
come from the nightly run. `lint-and-selftests` and `selftests (macos, bash 3.2)` are both green at
`9345c4f`, which is the head this record names.
