# Plan: derive plugin versions + CHANGELOG at release time (#119)

## Context / problem framing

Every PR currently hand-bumps `plugins/<name>/.claude-plugin/plugin.json` and appends to `CHANGELOG.md`; both are single-writer files, so concurrent PRs conflict and version numbers are guesses about merge order. #119 (as amended by the DE decisions comment and the intake gap resolutions) moves both writes to release time: a checked-in derivation script + a GitHub Actions release-PR workflow compute versions and the CHANGELOG section from conventional commits and changed paths; merging the accumulating release PR tags and publishes the GitHub Release. PR-time CI swaps the bump-discipline gate for its inverse (frozen files) plus a `Changelog:` trailer-presence gate.

Verified ground facts this plan builds on:
- Squash settings preserve commit bodies: `squash_merge_commit_message: COMMIT_MESSAGES`, `squash_merge_commit_title: COMMIT_OR_PR_TITLE` (repo API, verified at intake). Trailers must be extracted grep-anywhere — git recognizes trailers only in the final body paragraph.
- `.github/workflows/ci.yml` runs the `version-bump discipline` step on BOTH `push: main` and `pull_request`; it must be removed from both (release-PR-only re-landing) or main goes red between releases.
- Cutover state on main: plugin versions already ahead of tag `v2.4.1` (`dev-pipeline` 2.2.11 vs 2.2.7, `review-toolkit` 2.1.5 vs 2.1.4, `second-shift` 1.4.3 vs 1.4.2) and `CHANGELOG.md` carries an open `## v2.4.2 (in progress)` section — the derivation must reconcile both (max rule, prose preserved).

## Assumptions

- Merges to `main` remain squashes (linear history; one commit per PR, subject carries `(#NN)`).
- The repo's GitHub App (`cadenza-dev-pipeline`) can be used by Actions via `secrets` to author the release PR so that `pull_request` CI runs on it (a `GITHUB_TOKEN`-pushed PR does not trigger workflows — see Risks). Wiring the two secrets is a one-time maintainer setup step documented in releasing.md; the workflow fails loud with a setup pointer when they are absent.
- The release PR branch name is the constant `release/next`; the release PR squash subject is `release: vX.Y.Z`.
- Marketplace `metadata.version` at the last tag is authoritative as the previous release version (currently 2.4.1).

## Decision Ledger

| ID | Decision | Choice | Provenance |
| --- | --- | --- | --- |
| D-1 | Release version rule | Max bump level across changed plugins applied to previous marketplace version (release-please manifest rule) | user-answered (issue DE comment) |
| D-2 | Trailer extraction | Grep-anywhere `^Changelog:` blocks with indented continuations, collected in order; never git interpret-trailers | user-answered (issue DE comment) |
| D-3 | Cutover baseline | Per plugin derived = max(tag version + bump, committed main version); first release PR reconciles the in-progress CHANGELOG section once, prose preserved | user-answered (issue DE comment) |
| D-4 | Release branch ownership | Bot-owned `release/next`: wholesale regenerate + force-push per re-derive, Actions concurrency group serializes; human edits land late and superseded human commits get a loud PR comment | codebase-derived (intake gap resolution) |
| D-5 | Migration-doc gate condition | Fires on configVersion/schema change per releasing.md step 7, not on any major bump | codebase-derived (intake gap resolution) |
| D-6 | ci.yml bump step | Removed from all PR/push contexts; check-plugin-version-bumps.sh re-invoked only on the release PR | codebase-derived (intake gap resolution) |
| D-7 | Actions token for release PR | Mint an App token via actions/create-github-app-token with repo secrets; GITHUB_TOKEN cannot author a CI-triggering PR | codebase-derived |
| D-8 | Release publish trigger | pull_request closed + merged + head == release/next (not push-to-main subject sniffing) | codebase-derived |

Rationale notes: D-7 is forced by the GitHub Actions recursion guard (events caused by `GITHUB_TOKEN` do not trigger workflows), and the release PR must run the frozen-file exemption + bump-discipline gates. D-8 avoids parsing squash subjects on main.

## Affected files/modules

Created:
- `CLAUDE.md` [NEW] — repo-local conventions the pipeline bootstraps from at Stage 3. Carries the frozen-release-artifacts rule (the durable fix for the #100 class: without it a run re-derives the retired bump convention from surrounding evidence and only discovers the change at PR-time CI), the `Changelog:` trailer requirement, and the commit-verb→bump-level mapping. The repo had no `CLAUDE.md`; the config that could otherwise carry a local verify lane is gitignored, so a committed root file is the only branch-portable channel.
- `scripts/derive-release.sh` [NEW] — the derivation script (see steps).
- `scripts/derive-release-selftest.sh` [NEW] — fixture-repo selftest (auto-discovered by ci.yml's `find . -name '*-selftest.sh'`).
- `scripts/check-frozen-files.sh` [NEW] — PR-time inverse guard (AC-1 enforcement).
- `scripts/check-changelog-trailer.sh` [NEW] — PR-time trailer-presence guard (AC-5).
- `.github/workflows/release-pr.yml` [NEW] — push-to-main + workflow_dispatch → derive → force-push `release/next` → open/update release PR.
- `.github/workflows/release-publish.yml` [NEW] — merged release PR → tag + GitHub Release.

Modified:
- `.github/workflows/ci.yml` — remove the `version-bump discipline` step; add PR-time invocations of the two new guards (skipped when `github.head_ref == 'release/next'`); add a `release-pr-gates` job (only `release/next`) running `scripts/check-plugin-version-bumps.sh` + the configVersion→migration-doc check.
- `scripts/check-plugin-version-bumps.sh` — unchanged logic; header comment updated to name its new call site (release PR gate, not PR-time).
- `docs/releasing.md` — rewritten checklist: release-PR flow; trace-gate-not-on-bot-PRs statement (AC-6); @main mid-cycle staleness note; human-edits-land-late convention; steps 6/8 become release-PR body checklist items.
- `.claude/skills/release/SKILL.md` — **deleted** (scope change from the AC-6 amendment's "demote", decided mid-implementation — see `deviations[]`). After demotion it would have been a wrapper around one `gh workflow run` plus pointers to the release-PR body checklist and `/second-shift:local-dev-refresh`, i.e. a third copy of the release contract and a new drift surface. The trigger + verification commands move inline into `docs/releasing.md`.
- `plugins/second-shift/skills/local-dev-refresh/SKILL.md` — note: between releases main's plugin.json lags content so `plugin update` no-ops mid-cycle; reinstall is the escape.

Written at release time by the workflow (no change in this PR): `plugins/*/.claude-plugin/plugin.json`, `CHANGELOG.md`, `.claude-plugin/marketplace.json`, `docs/onboarding.md:97` (the single pinned-ref example site, verified by grep).

## Reuse inventory

- `scripts/check-plugin-version-bumps.sh` — reused as the release-PR bump-discipline gate (its diff-vs-last-tag logic is exactly the release-PR check); only the invocation context moves.
- ci.yml's standalone-script-plus-step gate shape (existing `namespace direction check` / bump step) — the two new guards follow it.
- Selftest conventions from existing `*-selftest.sh` (e.g. `tests/issue-forms-selftest.sh`, `plugins/second-shift/skills/onboard/tools/pin-resolve-selftest.sh`): mktemp fixture dirs, PASS/FAIL counters, exit = fails.
- `docs/migrations/README.md` contract + `docs/migrations/` naming — reused by the migration-doc gate.
- No new helpers beyond the four [NEW] scripts; no new config keys.

## Implementation steps

1. **`scripts/derive-release.sh`** [NEW]. Pure bash+git+jq, bash-3.2-safe (no mapfile), shellcheck-clean. Interface:
   - `derive-release.sh manifest` → JSON to stdout: `{previousTag, previousVersion, releaseVersion, plugins: {<name>: {old, new, level}}, prs: [{sha, subject, prNumber, plugins, level, changelog: [...blocks], breaking: [...], noTrailer: bool}]}`.
   - `derive-release.sh apply` → runs manifest, then writes: per-plugin `plugin.json` version, `marketplace.json` `metadata.version`, CHANGELOG section insertion under the preamble, `docs/onboarding.md` pinned-ref example, and prints the release PR body (What-breaks preview + steps-6/8 human checklist + no-trailer flags) to a file arg.
   - `derive-release.sh release-notes` → the GitHub Release body (What-breaks from `BREAKING CHANGE:`/`Changelog:` prose, explicit "Nothing breaks." when none, boilerplate upgrade recipe lifted from releasing.md step 6).
   - Derivation rules: commit list = `git log <lastTag>..HEAD --format=%H` minus commits whose subject matches `^release: ` (explicit exclusion); per-commit plugins from `git show --name-only` paths under `plugins/<name>/`; level from subject `^type(!)?:`/`(scope)(!)`: `!` or `BREAKING CHANGE:` in body → major, `feat` → minor, else patch; per-plugin level = max; release level = max across plugins; per-plugin new = max(bump(tagVersion, level), committed version) — the D-3 cutover rule; release version = bump(previousVersion, releaseLevel) with the same max guard vs committed `metadata.version`.
   - Trailer extraction (D-2): scan the full squashed body; each `^Changelog:` line opens a block, subsequent indented (`^[[:space:]]`) lines continue it; blocks collected in order; a block whose content is exactly `none` renders nothing but still counts as trailer-present.
   - CHANGELOG rendering: `## vX.Y.Z` heading; per-plugin ``### `name` old → new`` subheadings; one bullet per PR: `**subject** (#NN)` + trailer prose as the bullet body (`Migration:` lines kept verbatim); no-trailer commits render subject-only and are listed in the PR-body flags section. Cutover: an existing `## vX.Y.Z (in progress)` section is absorbed — its hand-written per-plugin bullets are kept verbatim under the generated heading (before generated bullets for commits not already covered), the `(in progress)` heading is removed; second derivation run produces byte-identical output (idempotent).
2. **`scripts/derive-release-selftest.sh`** [NEW]. Builds a throwaway git repo fixture in mktemp with plugins/A, plugins/B, tag v1.0.0, then commits covering: feat(A), fix(B), one commit touching A+B, `feat!:` breaking with `BREAKING CHANGE:` body, mid-body `Changelog:` trailer with indented continuation (not final paragraph), `Changelog: none`, no-trailer commit, a `release: v1.0.0` commit that must be excluded, and a pre-bumped plugin.json + `(in progress)` section for the cutover/max-rule case. Asserts manifest JSON fields, rendered CHANGELOG shape (the worked example fixture per DE decision), release-notes What-breaks assembly incl. "Nothing breaks." case, and apply-mode idempotency (run twice, diff empty).
3. **`scripts/check-frozen-files.sh`** [NEW]. Args: base ref. Fails (exit 1, named offenders) when `git diff <base>...HEAD` modifies `CHANGELOG.md` or changes any `plugins/*/.claude-plugin/plugin.json` `.version` (jq-compare base vs head blob; non-version manifest edits pass).
4. **`scripts/check-changelog-trailer.sh`** [NEW]. Args: base ref. When the diff touches `plugins/**`: pass iff at least one commit in `<base>..HEAD` body-matches `^Changelog:` (the `none` form counts); else fail with the trailer-writing hint.
5. **`.github/workflows/ci.yml`**: delete the `version-bump discipline` step; in the PR context add both guards gated `if: github.event_name == 'pull_request' && github.head_ref != 'release/next'` (base ref = `${{ github.event.pull_request.base.sha }}`); add job `release-pr-gates` with `if: github.event_name == 'pull_request' && github.head_ref == 'release/next'` running `bash scripts/check-plugin-version-bumps.sh` and the configVersion gate (inline: configVersion differs at last tag vs PR head ⇒ `docs/migrations/v<old>-to-v<new>.md` must exist).
6. **`.github/workflows/release-pr.yml`** [NEW]: `on: push: branches: [main]` + `workflow_dispatch`; `concurrency: release-pr`; permissions contents:write/pull-requests:write; steps: checkout `fetch-depth: 0`; mint App token (`actions/create-github-app-token@v1` with `secrets.RELEASE_APP_ID`/`secrets.RELEASE_APP_PRIVATE_KEY`; absent secrets → fail with the releasing.md setup pointer); run `derive-release.sh apply`; exit clean ("nothing to release") when no plugin changed since tag; commit derived files to `release/next` and force-push; before force-push, detect non-bot commits on the existing remote branch and post the superseded-head comment (D-4); create-or-update the PR (`release: vX.Y.Z`) with the generated body.
7. **`.github/workflows/release-publish.yml`** [NEW]: `on: pull_request: types: [closed]`; `if: merged == true && head.ref == 'release/next'`; read `metadata.version` at the merge commit → `git tag vX.Y.Z` + push (App token) → `gh release create vX.Y.Z` with `derive-release.sh release-notes` output.
8. **Docs**: rewrite `docs/releasing.md` (new numbered flow: merge feature PRs with trailers → release PR accumulates → human checklist on release PR (section-catalog step 6, renames step 8, migration prose) → merge = tag + Release → maintainer-machine refresh; plus AC-6 trace-gate statement, @main staleness note, human-edits-land-late, one-time secrets setup, and the trigger/verify commands inline). Delete `.claude/skills/release/` — the demoted skill would duplicate the release contract a third time. Add the mid-cycle staleness note to `plugins/second-shift/skills/local-dev-refresh/SKILL.md`.

## Test strategy

Verify-after (infra/tooling, no runtime app behavior): the derivation logic is exercised by `scripts/derive-release-selftest.sh` [NEW] (auto-collected by the existing test lane), covering every AC-mapped case in the traceability table below; the two PR-time guards get selftest cases in the same file (fixture diffs, pass/fail both directions). Workflows are thin shells around the scripts; they are validated by `jq`/YAML parse in CI and a live canary release PR after merge (see Risks — actionlint is not in this repo's CI). Existing selftests + shellcheck + jq lanes must stay green.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | PRs stop touching plugin.json/CHANGELOG; no cross-PR conflict | 3, 5 | derive-release-selftest.sh frozen-guard cases (AC-1) |
| AC-2 | Changed plugins from paths; bump level from commit type; bumps land in release PR | 1, 6 | derive-release-selftest.sh manifest cases (AC-2) |
| AC-3 | CHANGELOG section: per-plugin headings, bullet per PR, trailer prose rendered | 1 | derive-release-selftest.sh rendering cases (AC-3) |
| AC-4 | No-trailer bullet correct; BREAKING → major + note; mid-body trailer renders | 1 | derive-release-selftest.sh trailer cases (AC-4) |
| AC-5 | CI fails plugins/** PR without Changelog:/Changelog: none | 4, 5 | derive-release-selftest.sh trailer-guard cases (AC-5) |
| AC-6 | releasing.md rewritten (+trace-gate statement, checklist, SKILL.md demotion) | 8 | — no test (non-functional) |
| AC-7 | Tag-pinned consumers see same version fields, written later | 1, 6 | derive-release-selftest.sh apply-mode field-shape case (AC-7) |
| AC-8 | Merge → tag + Release with What-breaks body + recipe; script selftest-covered | 1, 2, 7 | derive-release-selftest.sh release-notes + cutover cases (AC-8) |

## Verification commands

```bash
# in the worktree root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/derive-release-selftest.sh   # the new coverage, directly
```

## Risks / rollback notes

- **GITHUB_TOKEN recursion guard (D-7):** a release PR authored with the default token gets no CI runs — the frozen-file exemption and release-pr-gates would never execute. Mitigated by App-token minting; the workflow fails loud when secrets are missing. Setup is one-time and documented.
- **Actions YAML is not machine-validated in this repo** (no actionlint): the two new workflows are exercised for real only on the first push-to-main after merge. Mitigation: keep workflows thin (all logic in the selftest-covered script); the first live run is the acceptance probe, and a red release-pr run does not block feature CI.
- **Force-push clobber (D-4):** human commits on `release/next` are superseded by design; loud comment + PR-history recovery. Documented convention: edit late.
- **Rollback:** revert the PR — ci.yml regains the old bump step, scripts/workflows are additive files. In-flight release PR can simply be closed; no state outside git.

## Out-of-scope

- Changing tag format or release cadence (issue Out-of-scope).
- Retroactively rewriting released CHANGELOG sections.
- Deleting `scripts/check-plugin-version-bumps.sh` (it is reused on the release PR).
- Dev-pipeline stage-6 unplanned-path gate knock-on (#109).
- Performing the actual first release / cutover run (happens on the first push-to-main after merge).

Unverified references: none.
