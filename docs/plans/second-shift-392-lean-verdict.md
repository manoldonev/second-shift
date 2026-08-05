# lean review verdict — #392

verdict=needs-work
run_id: review-392-1
session_id: 4adb3fdd-26b4-4ff3-9b2a-b0948056eeb2
rounds: 1
pr: #400
reviewed_head: 3c5f583123fb3d20150a0eab4d3d695f0be4072c
reviewed_patch_id: 86d23d218593c533c63de573199d83d5b5b51caa
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

# Review round 1 — PR #400 / issue #392

Range read: `3eb0e53..HEAD` (full branch — round 1, nothing to inherit).
Reviewer: `review-lead` panel of 7 (0 dark) + operator-run execution probes.

## Verdict: needs-work

All five `AC-n` are satisfied. The blockers are outside the AC set: the guard this PR adds
has two observable effects that **no suite can kill**, proven by execution, and the repo's
automated mutation lane structurally cannot reach the guard to catch either.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Both sub-cases red and name all three tokens. Verified by direct probe on a no-config fixture: `✗ milestone-3: no verifying lane configured for 'acme' … config read from <path> … commands.acme.allowUnverified=true`. Slug, config path and `allowUnverified` all present. `(iz1)`/`(iz2)` are the oracle. |
| AC-2 | satisfied | `(iz3)` passes; dropping `any_verifying=1` (L967) reds the suite (rc=1), so the inertness is pinned in the killing direction. |
| AC-3 | satisfied | `(iz4)` passes — a `when`-scoped `extraLanes` entry missing on the diff keeps the guard inert via `el_count`, never via execution. |
| AC-4 | satisfied in substance; its named oracle cannot observe it | The re-baseline clause holds — independently verified, see W1. The kill clause is TRUE (probes below) but the diff-scoped sweep the AC names as its oracle never mutated the guard. See W1. |
| AC-5 | satisfied | `docs/config-schema.md:9` names `lean-gate.sh` milestone 3 in the `allowUnverified` consumer list (`#98/#392`); commit body carries a `Changelog:` trailer with `Migration: none`. |

## Blockers

| # | Finding | Location |
| --- | --- | --- |
| B-1 | **The opt-out branch's `append_line` is unkillable.** Deleting the line leaves `lean-gate-selftest.sh` AND `scenario-liveness-selftest.sh` **fully green** (both rc=0). `(i-392)` greps stdout for the `say`, never `$PROG` for the record. This is the audit trail saying a lean run verified nothing — the same class of silent-green the issue exists to close, one level up. The predecessor's analogous skip line is asserted in **two** places (`lean-gate-selftest.sh:404` via `el_count_in … "$prog"`, `scenario-liveness-selftest.sh:1312`), so the precedent was available and not applied. Remedy: one `grep -qF 'milestone-3 \| skipped \| no verifying lane configured — allowUnverified opt-out' "$PROG"` after `(i-392)`. | `lean-gate.sh:999` |
| B-2 | **The red branch's milestone number is unkillable.** Rewriting `fail_milestone 3` → `fail_milestone 2` on that line leaves **both** suites green (both rc=0). `(iz1)`/`(iz2)` assert rc, the reason text, the config path and the `allowUnverified` token — none of which vary with the milestone literal. A mis-keyed call mis-attributes the failure to the operator and keys the attempt/fix-budget state to the wrong milestone, with no lane going red. Not reachable by any sweep operator either (`fail-open`/`cmp-eq`/`cmp-z`/`logic`/`detector`/`default` do not touch a bare integer literal). Remedy: assert the `milestone-3` token in `(iz1)`'s output. | `lean-gate.sh:1001` |
| B-3 | **No composed coverage for either new verdict path.** The gate contract added here has two verdict paths (red; green-with-notice). `scenario-liveness-selftest.sh`'s only change is to add `allowUnverified: true` to **both** lean fixtures — which makes the new guard inert in the one suite that composes milestone 3 through to a terminal write. The green-with-notice path is now traversed by `(lean-green)`/`(lean-jira)` but asserted by nothing; the red path is not traversed at all. `CLAUDE.md`: "A new gate contract extends the liveness scenario for every verdict path it touches." `docs/testing.md:42-44`: "If a new gate has a verdict path, extend `scenario-liveness-selftest.sh`." The immediately-prior milestone-3 gate contract (#379, one commit earlier, same file) added `(lean-el-skip)` **and** `(lean-el-red)` and its own comment names this rule as its reason. Counter-argument, stated so it can be answered with evidence: `(lean-el-red)` already composes *a* milestone-3 red to `all`-stops + milestone-4-never-satisfied, so the mechanism is covered and only this trigger is not — #379 made exactly that argument for itself and added the leg regardless. | `scenario-liveness-selftest.sh:886,1163` |

## Warnings

| # | Finding |
| --- | --- |
| W1 | **AC-4's cited evidence does not demonstrate its own first clause, and no red-on-mutation demo exists in the record.** The guard's sites are `cmp-eq` ordinal **11** and `logic` ordinal **67**; `mutation-sweep.sh:139` sets `K_BUDGET=2`, and the site loop `continue`s past every ordinal beyond it (`mutation-sweep.sh:1273`). So the "10 mutants applied, 7 killed, 3 survivors" run **never mutated this guard** — 10 is exactly the pre-existing ordinals-1-and-2 budget. Separately, `docs/testing.md`: "Every new guard ships a red-on-mutation demo … break the thing, watch the guard go red, restore it, and say so in the commit body. This is a repo idiom, not a suggestion" — the commit body has none. The property itself is true: `-eq`→`-ne` reds the suite (rc=3), `&&`→`\|\|` reds it (rc=2). It is the citation and the record that are missing, not the kill. |
| W2 | **`(iz2)` under-asserts AC-1's no-config sub-case.** AC-1 requires the red to name the slug, the config path and `allowUnverified` — `(iz2)` greps only `allowUnverified`. The behavior is correct (verified by direct probe, see AC-1 row), so this is assertion strength, not a defect; but as written `(iz2)` would pass on a message that dropped two of the three required tokens. |
| W3 | **The machine contract is now stale.** `schema/second-shift.config.schema.json:112`'s `allowUnverified` description still names only Stage 6 and `preflight` as consumers. `docs/config-schema.md:3` points at that schema as the machine contract, and its prose half was updated. Outside the spec's declared file scope, so not an AC failure. |

## Suggestions

- **S-1** No fixture sets a fixed key **and** a non-empty `extraLanes` together, so the `(1, >0)` state is never driven. No live mutant survives from this gap (the `cmp-eq` mutant already dies via the `(0,0)` state in `(iz1)`); defensive only.
- **S-2** Setup `lanes[]` still execute before the guard reds, so a zero-verify-lane repo carrying an install lane pays the install before the red. The spec's placement rationale optimized only the sweep side. Matches the spec as written, so not a deviation.

## Verified green (not findings)

- `lean-gate-selftest.sh` and `scenario-liveness-selftest.sh` both pass with `env -u CLAUDE_CODE_SESSION_ID` and **without** `SKIP_STRESS` (63/63 on the scenario suite).
- `shellcheck -e SC1091,SC2015,SC2181` clean on all three changed shell files.
- **Mutation ordinals independently verified unmoved** — not inferred from survivor-id equality. Matched-line lists were diffed between `3eb0e53` and HEAD per operator: `cmp-eq` 17→18 sites (the one new site is the guard line itself, at ordinal 11), `logic` 110→111 (same line), `default`/`cmp-z`/`detector`/`fail-open` unchanged. Baselined rows `cmp-eq::1` (L107), `default::1` (L108), `default::2` (L124) are byte-identical in both revisions, so AC-4's re-baseline clause is satisfied with nothing to re-key. No `mutation-catalog.tsv` row anchors this guard.
- The guard is a faithful copy of the staged lane's predicate: `preflight.sh:335-346` counts the same fixed keys plus `extraLanes` length and treats empty-string commands as unconfigured, which `cfg` + `[ -n "$cmd" ]` reproduces.
- Reviewer panel: 7 dispatched, 7 returned, **0 dark**. security / performance / maintainability / complexity / test-coverage / scope-completeness all `approve`; unit-test-mutation `approve-with-nits`. B-1 and B-2 were independently raised by unit-test-mutation-reviewer at confidence 85 and 80; both are recorded here at blocker severity on the strength of the execution probes, not its classification.

## Round-1 method note

Every probe above was applied to a working-tree copy of `lean-gate.sh` and reverted with
`cp` from a pristine snapshot, never `git checkout`; `git status --porcelain` was confirmed
empty after each. The reviewed tree is unmodified.
