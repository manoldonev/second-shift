# Plan — cover the dark enforcing gates (#215, PR 2 of 5 for #213)

## Context

Four enforcing surfaces have zero or near-zero behavioral coverage. Two are the dangerous
kind — they fail in the *pass* direction, so a regression is invisible:

- `scripts/check-plugin-version-bumps.sh` — a merge-blocking release gate whose error
  branches all degrade to PASS.
- `plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` — a live PreToolUse hook whose
  resolution failures land in warn-and-allow, approving every plan forever with no red.

The other two are narrower: `plugins/dev-pipeline/skills/run/workflows/mutation-gate.mjs`
has only `computeVerdict` covered (its `RESULT_RE` last-match parser is unpinned), and
`plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` has no behavioral coverage of
its pure state-file branch.

This is a coverage PR. It changes no gate's behavior.

## Assumptions

- Intake decision **D2** holds: AC-1 is test-only. "Red fixture case" means *capable of
  going red on a regression*, not *failing today* — the repo's own vocabulary
  (`CLAUDE.md`, mirror-harness ban). `scripts/check-plugin-version-bumps.sh` keeps its
  current exit semantics.
- Intake decision **D1** holds: the ledger-lint apostrophe fix and its regression case
  `(ll-k)` already landed; this PR asserts the guard still exists and ships no
  `ledger-lint.sh` change.
- Intake decision **D3** holds: AC-4's target is block 8 (stale claims), not block 5e
  (a delegation with no logic of its own).

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does AC-1 authorize changing `check-plugin-version-bumps.sh` behavior? | No. Scope 2 explicitly authorizes a production fix and Scope 1 does not; the asymmetry is deliberate. Fixtures pin current rc in both directions. | codebase-derived |
| D-2 | Where does the `RESULT_RE` extraction anchor come from? | Add `// >>> parse` / `// <<< parse` sentinels to `mutation-gate.mjs`, mirroring the `// >>> verdict` idiom already in that same file. Comment-only. | codebase-derived |
| D-3 | Shim case or extraction for `RESULT_RE`? | Extraction. The shim is for dispatch ladders; `parseResult` is a pure function and the same file already carries the extraction idiom. | codebase-derived |
| D-4 | How is pipeline-doctor block 8 reached without booting the whole doctor? | Sentinel-extract its jq program and execute it against fixture state files. No `--only` seam is added to the doctor. | codebase-derived |
| D-5 | How does tier 3 of the ledger gate behave under GNU find, which lacks `-newermB`? | The `find` errors, `|| true` yields zero candidates, and the hook warn-and-allows. The suite probes support and asserts the platform-correct contract on each; neither platform is skipped. | codebase-derived |
| D-6 | Is the GNU-find tier-3 vacuity fixed here? | Deferred. It is a real gap (on Linux the hook can never lint a session-fresh plan) but a behavior change outside AC-2, which asks for coverage. Recorded as a finding for follow-up. | deferred |
| D-7 | pipeline-doctor block 8 skips a state file with no `lastUpdatedAt`, contradicting its own comment. Fix here? | Deferred, same posture as D-6. `(.lastUpdatedAt // empty) \| fromdateiso8601? // 0` short-circuits on an absent field, so a truncated state file is invisible to the stale-claim check. Case (d5a) pins the real behavior and names it a known fail-open. | deferred |

## Affected files/modules

**Created**

- `scripts/check-plugin-version-bumps-selftest.sh` **[NEW]**
- `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh` **[NEW]**
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor-selftest.sh` **[NEW]**

**Modified**

- `plugins/dev-pipeline/skills/run/workflows/mutation-gate.mjs` — add `// >>> parse` /
  `// <<< parse` sentinels around `RESULT_RE` + `parseResult` (comment-only).
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — add
  `# >>> stale-claim-jq` / `# <<< stale-claim-jq` sentinels around block 8's jq program
  (comment-only).
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — extend case `(mg)` with the
  parser fixtures; turn the node-absent `SKIP` into a `fail`.
- `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh` — assert
  `(ll-k)` still guards the quoting-safe `trim`.
- `CLAUDE.md` — the "Genuinely uncovered, and tracked — not exempt" debt register
  (lines 78-81) names both `check-plugin-version-bumps.sh` and
  `exitplan-ledger-gate.sh` as "#215 scope"; landing this PR makes that entry false, so
  it moves to the covered list.

## Conventions this PR must satisfy

- **Scenario-first justification.** Each of the three new per-tool suites carries a header
  naming the invariant it guards and why no scenario in
  `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` covers it (`CLAUDE.md`,
  "What to write when you add a test").
- **`Changelog:` trailer.** This PR touches `plugins/**`, so at least one commit carries a
  `Changelog:` trailer (CI-enforced by `scripts/check-changelog-trailer.sh`).
- **No frozen-file edits.** No `plugin.json` `version`, no `CHANGELOG.md`, no
  `marketplace.json` `metadata.version` (CI-enforced by `scripts/check-frozen-files.sh`).
- **bash 3.2.** CI runs the full selftest set on stock macOS bash — no `mapfile`, no
  associative arrays.

## Reuse inventory

- `scripts/derive-release-selftest.sh` — the throwaway-git-repo-with-tags fixture idiom
  (`mkplugin`, `git init -q`, `git tag`, `ok`/`bad` counters). Reused verbatim in shape
  by the version-bump suite.
- `plugins/dev-pipeline/skills/run/tools/pre-commit-typecheck-selftest.sh` — the hook
  fixture idiom (`ok`/`bad` counters, pure-local, no network). The ledger-gate hook reads
  stdin unconditionally at line 30, so it is driven as a subprocess with a fixture
  payload rather than sourced.
- `plugins/dev-pipeline/skills/run/tools/claim-selftest.sh` — the fixture-suite shape for
  a tool that shells out.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` case `(mg)` — the existing
  sed-extract-and-node-execute block, extended rather than duplicated.
- New helpers introduced: none — no new helpers introduced.

## Implementation steps

1. **`mutation-gate.mjs` sentinels** — wrap `RESULT_RE` + `parseResult` in
   `// >>> parse` / `// <<< parse`. No code change.
2. **`statectl-selftest.sh` case (mg)** — extract the parse block alongside the verdict
   block; add fixtures for last-match-wins (prompt echo before the real line), the three
   legal tokens, leading/trailing whitespace, a lowercase token (must not match), an
   absent token, and `null`/`undefined` input. Replace the node-absent `SKIP` branch with
   `fail`.
3. **`pipeline-doctor.sh` sentinels** — wrap block 8's jq program in
   `# >>> stale-claim-jq` / `# <<< stale-claim-jq`. No code change.
4. **`pipeline-doctor-selftest.sh`** — extract the jq program; drive it with fixture state
   JSON: `in_progress` older than 30 min emits a line; `in_progress` fresh emits nothing;
   `completed` and `failed` emit nothing regardless of age; missing `lastUpdatedAt`
   anchors at epoch and is flagged ancient; a non-string `runId` or non-object `stages`
   is filtered out. The quarantine filename filter (`*-released-*`, `*-stale-*`) is
   exercised as **executed code** — the extracted block is run over a fixture state dir
   containing a quarantined file that would otherwise be flagged, asserting it is not —
   never by grepping the doctor's `case` pattern out of its source (banned
   prose-presence / mirror-harness class).
5. **`check-plugin-version-bumps-selftest.sh`** — build a fixture repo with two plugins and
   a `v1.0.0` tag, then assert rc and stdout for: content changed without a bump (rc 1 —
   the fail direction); content changed with a bump (rc 0); no content change (rc 0);
   no tag at all (rc 0, "first release" message); a plugin absent at BASE (rc 0, "new
   plugin" message); a plugin whose manifest at BASE is unreadable, which takes the same
   empty-`old_ver` path (rc 0, "new plugin" message — the characterized degradation);
   **empty `new_ver` against a non-empty `old_ver`** — a plugin that loses its `version`
   field entirely: equality is false, so the gate prints `✓` and passes (rc 0), the
   silent-pass branch the ACs did not name; explicit `base-ref` argument honored; and the
   `HEAD^`-has-no-tag path falling through to the second `git describe`. Add the fail-open
   mutant check: copy the gate, rewrite its `exit 1` to `exit 0`, and assert the rc-1 case
   then goes red.
6. **`exitplan-ledger-gate-selftest.sh`** — drive the hook as a subprocess with fixture
   JSON on stdin, `SECOND_SHIFT_REPO_ROOT` pointed at a fixture repo:
   - tier 1: `tool_input.plan` inline, valid ledger → rc 0; invalid → rc 2.
   - tier 2: `tool_input.plan_path`, `plan_file_path`, `file_path` each resolve; valid →
     rc 0, invalid → rc 2; a path field naming a missing file falls through.
   - tier 3: probe `find -newermB` support. Where supported, assert exactly-one-candidate
     lints (valid → 0, invalid → 2), zero candidates warn-and-allow, and multiple
     candidates warn-and-allow. Where unsupported, assert the documented degradation
     (rc 0 with the zero-candidates warning) so the case is live on both platforms.
   - `PLAN_INTERVIEW_SKIP=1` → rc 0 without linting.
   - no plans dir → rc 0; no `transcript_path` → rc 0.
   - **fail-open branches** (the headline risk class named in Context): `ledger-lint.sh`
     absent or non-executable → rc 0 with the "fix the install" warning; `jq` unavailable
     on `PATH` → rc 0. Both allow without linting, so both need a live case.
   - **`resolve_plans_dir` config branch**: a fixture repo whose
     `.claude/second-shift.config.json` sets `paths.plansDir` resolves candidates there
     rather than at the `.claude/plans` default.
   - never-exit-1: assert rc is in `{0,2}` across every case above.
7. **`ledger-lint-selftest.sh`** — widen the existing `(ll-k)` apostrophe guard
   behaviorally: add a row carrying double quotes, a backslash, and an unmatched quote
   (the classic `xargs` abort), plus a discrimination case proving the Provenance cell is
   still parsed out of that row. Grepping `ledger-lint.sh` for the absence of `xargs`
   was rejected — that is the prose-presence class `CLAUDE.md` bans, and it would miss
   any other quoting-unsafe rewrite.
8. **`CLAUDE.md`** — close the debt register (both files are now covered), and record the
   two characterized fail-opens (D-6, D-7) so "pinned" is never mistaken for "endorsed".

## Test strategy

Verify-after — this is test infrastructure, and every step's deliverable *is* a test.
Each new suite is exercised in both directions (a passing fixture and a failing fixture)
so it cannot converge on green. Step 5 additionally carries an explicit mutation check
(fail-open mutant of the gate under test), which is the strongest available guard against
a vacuous suite.

Mutation surface: the repo declares no `unitTestScope`, so the Stage-5 mutation gate does
not apply.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | version-bump gate: red case per silent-pass branch; fail-open mutant caught | 5 | `check-plugin-version-bumps-selftest.sh` — branch cases + mutant case (AC-1) |
| AC-2 | ledger gate: 3 tiers, skip hatch, never-exit-1; apostrophe fix guarded | 6, 7 | `exitplan-ledger-gate-selftest.sh` (AC-2); `ledger-lint-selftest.sh` guard assertion |
| AC-3 | `RESULT_RE` executed under node; (mg) fails when node absent | 1, 2 | `statectl-selftest.sh` case (mg) parser fixtures (AC-3) |
| AC-4 | pipeline-doctor pure branches covered; suite operator-safe | 3, 4 | `pipeline-doctor-selftest.sh` (AC-4) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

New suites need no CI registration — CI discovers them by the `*-selftest.sh` glob.
All three new suites must be bash-3.2-safe (CI runs the full set on macOS stock bash).

## Risks / rollback notes

- **Fixture-repo leakage.** Every suite builds under `mktemp -d` with a `trap` cleanup, and
  none touches the real repo, `gh`, or the network — matching the existing suites.
- **`git describe` in a fixture repo** can pick up tags from an enclosing repo if the
  fixture is not a fresh `git init`. Each fixture is its own `git init -q` under `mktemp`.
- **Platform split on tier 3** is handled by an explicit probe rather than a skip; if the
  probe itself is wrong, the failure is loud (the case asserts a concrete rc either way).
- Rollback is deleting the three new files and reverting four small edits; no gate's
  behavior changes, so nothing downstream depends on this PR.

## Out-of-scope

- Fixing the GNU-find tier-3 vacuity in `exitplan-ledger-gate.sh` (D-6, deferred).
- Changing `check-plugin-version-bumps.sh` exit semantics (D-1).
- The other coverage gaps in the audit map that belong to sibling PRs of #213
  (audit-toolkit CI reachability and the design-toolkit shim landed in PR 1;
  `pipeline-cost-block.sh` wrapper resolution and `stage-times.sh` degenerate inputs are
  not in this ticket's scope).
- `install-gh-bot.sh` and `_effective-registry.sh` coverage.

Unverified references: none.
