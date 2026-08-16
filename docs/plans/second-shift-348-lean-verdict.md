# lean review verdict — #348

verdict=needs-work
run_id: review-348-1
session_id: 40cb3ddb-9f8e-4dbe-8df1-a51fc9a0b288
rounds: 1
pr: #568
reviewed_head: 7047b833f65e747be703875c1ead8dfec51a7d85
reviewed_patch_id: d558b5da579f293ff16d22427b603b714ba19675
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 over the full branch diff (`33e6187..HEAD`, 261 files, −17,148 net). `delta` printed
the full range — nothing to inherit.

The deletion itself is careful work: the survive/delete criterion is applied mechanically, every
deviation from the spec's relocation floor is enumerated with a reason, all nine path-carrying
registers re-key cleanly, and the mutation sweep re-anchors rather than re-baselines. The blockers
are not in the deletion. They are in the four places the sweep did not reach.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `.github/workflows/nightly-guards.yml:118` | The nightly `prose-budget` job runs `bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — a path this PR deletes. The file is **untouched by the branch** (`git log 33e6187..HEAD -- .github/workflows/nightly-guards.yml` is empty). That job reds from the first night after merge. It is not an oversight of the re-pointing pass: the line was added by **#561 (`519228a`)**, which landed on `main` *after* the branch's re-pointing commit `61a85b7`, and the rebase brought in a consumer nobody re-swept. The PR body's rebase note walks #561's two baseline TSVs and never mentions its new CI job. Neither AC-1's orphan glob (`*-selftest.sh`, `tools/*.tsv`, `scripts/*.tsv`, the two baselines) nor the spec's sweep list (which names `ci.yml` only) covers `.github/workflows/*.yml` — the hole is in the checklist, not just the execution. Fix: re-point to `plugins/dev-pipeline/tools/prose-budget.sh`, and widen the orphan check to `.github/workflows/`. |
| 2 | **Blocker** | branch commits / **AC-4** | Two halves of AC-4 are unmet. (a) **No `feat!` verb and no `BREAKING CHANGE:` footer** anywhere on the branch — the six subjects are `docs(dev-pipeline)`, `refactor(dev-pipeline)` ×2, `docs(dev-pipeline)`, `test(tools)` ×2. `scripts/derive-release.sh:145` derives major only from `!`/`BREAKING CHANGE:` and minor from `feat:`, so as it stands this merges as a **patch** release — for a change that removes `/dev-pipeline:run` and moves every shipped tool path. (b) **Every trailer is `Changelog: none.`** There is no `Migration:` line on the branch, so the pin literal has no trailer home (the PR body promises it "lands in the `Migration:` trailer" — the trailer does not exist yet), the relocated `config-lint.sh` path the consumer CI template hardcodes is unannounced, and the release notes for the largest breaking change in the repo's history would be empty. CI cannot catch either: `check-changelog-trailer.sh` accepts `Changelog: none`, and `check-frozen-files.sh` is green (correctly — no `version`/`CHANGELOG.md` edit). |
| 3 | **Blocker** | `docs/pipeline-manifesto.md:53-55` / **AC-6** | The P1/P2 posture note is byte-identical to base and still reads "**Until the stage-machinery deletion lands**, the staged path remains in-tree solely as rollback and ablation control (the pin is the last stage-carrying release, recorded on the deletion PR when it merges)". This diff is that deletion, so the sentence is false on merge and its pin parenthetical points at a PR that will be closed. The spec's own register-and-doc sweep names this file *and this note specifically* — "`docs/pipeline-manifesto.md` (trust-boundary record list **+ the P1/P2 pin posture note**)". Only the P3 record list (`:99-104`) was updated. |
| 4 | **Blocker** | `docs/config-schema.md:3`, `:21` / **AC-6** | Two dead links in a file AC-6 names. `:3` links `config-lint.sh` at `../plugins/dev-pipeline/skills/run/tools/config-lint.sh` (now `plugins/dev-pipeline/tools/config-lint.sh`) and the fixtures likewise. `:21` ends `See [stages/6-verify.md](../plugins/dev-pipeline/skills/run/stages/6-verify.md#deterministic-verify-runner-verifyctl)` — into a directory this PR deletes. `:21` is a line **this diff edited** (it removed `verifyctl.sh` from the sentence's subject list and left the link to `verifyctl`'s stage doc in place). |
| 5 | **Blocker** | `README.md:57` / **AC-6** | The front-page README links the JIRA tracker README at `plugins/dev-pipeline/skills/run/tools/tracker/jira/README.md`; the directory moved to `plugins/dev-pipeline/tools/tracker/`. README.md is edited by this PR in three other hunks and is named explicitly in AC-6. |
| 6 | Warning | `plugins/dev-pipeline/cost-tracking-setup.md:40`, `:48` | Relocated `similarity index 100%` — zero content edit — and its own install instructions name `plugins/dev-pipeline/skills/run/otel-collector-config.yaml` (twice) plus the `.../<version>/skills/run/...` cache shape. This is operator-facing setup prose that `lean-gate.sh:2332,2336` cites by section in live diagnostics, and it is the doc that installs the file the same commit moved. The `find`-based `SRC=` recipe still works by accident; the two prose paths do not. |
| 7 | Warning | `plugins/dev-pipeline/cost-tracking-fixtures/README.md:9,11,13,40` | Also `R100`. Four copy-pasteable commands, all dead: the `OTEL_METRICS_FILE` export, the `cp` of the state fixture, `bash plugins/dev-pipeline/skills/run/pipeline-cost-block.sh test-cost`, and `bash plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh`. Separately: the spec's **Deletion set** lists `cost-tracking-fixtures/` as deleted, but the diff **relocates** it. That is a defensible re-verification (it is not statectl-state-only), but it is an undeclared deviation in a spec whose deviation table is the review's stated business. |
| 8 | Warning | `plugins/dev-pipeline/tools/tracker/README.md:33`, `:35` | The tracker adapter contract — linked from `build-lean/SKILL.md`, `review-lean/SKILL.md` and `lean-gate.sh` — documents both bot writes as `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/gh-bot.sh"`. Plugin-root-relative, so it is wrong for an installed consumer too, not just this checkout. Should read `${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh`. |
| 9 | Warning | `plugins/dev-pipeline/state-schema.md` | `R100`, so its sibling links moved with it and none resolve: `[statectl.sh](./statectl.sh)`, `[verifyctl.sh](./verifyctl.sh)`, `[tools/plan-scope-paths.sh](./tools/plan-scope-paths.sh)`, plus prose references to `plan-lint`, `ledger-corroborate` and `gen-statectl-validators`. The spec says this file relocates with "no content edit **beyond path fixes**"; it received none. It is a historical-format doc for the corpus `pipeline-retro`/`perf-retro` still read, so nothing breaks — but every link in a shipped plugin doc is dead, and a reader cannot tell "historical record" from "stale". One banner naming it as the pre-#348 format would settle it. |
| 10 | Warning | PR body / **AC-1** | AC-1 and the body both assert the orphan grep returns "**empty**, with the two stated exemptions". Run as specified over `*-selftest.sh` + `tools/*.tsv` + `scripts/*.tsv` + the baselines, it returns **7 hits in 5 files** beyond those two: `pipeline-doctor-selftest.sh:687,693`, `pre-commit-typecheck-selftest.sh:73,74`, `is-inert-diff-selftest.sh:74`, `check-bounded-exploration-selftest.sh:389`, `workflows-mjs-selftest.sh:13`. I checked each: all benign — two are `.claude/`-prefixed *consumer-side* literals exercising path-matching generically, one fabricates a `1.0.0` cache layout for a version-ordering case where the directory name is arbitrary, two are comments about #348 itself. So the *substance* of AC-1 holds. What does not hold is the claim, and an over-stated mechanical result is how the next deletion's real orphan gets waved through. Either widen the exemption list or restate the check as "no orphaned reference", which is what was actually verified. |
| 11 | Nit | `plugins/dev-pipeline/workflows/design-sync-selftest.mjs:31`, `null-reviewer-selftest.mjs:28` | `// Run: node .claude/skills/run/workflows/<file>` — stale copy-paste lines. `design-sync-selftest.mjs:49`, eighteen lines below, was edited by this diff to explain that the path moved, so the file contradicts itself. |

## Acceptance criteria

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** — sweep green, shellcheck/jq clean, orphan grep | **satisfied** (claim over-stated — finding 10) | CI `lint-and-selftests` pass 4m6s, `selftests (macos, bash 3.2)` pass 4m26s. No orphaned reference found in the registers; the grep is not literally empty. |
| **AC-2** — no register row names a deleted guard; sweep clean on the PR lane | **satisfied** | Verified independently: every path token in all nine registers (`mutation-{baseline,exclusions,catalog,pair-map,slow-suites}`, `selftest-cache-inputs`, `lockstep-manifest`, `fail-open-sites`, `install-topology-known-red`) resolves in the surviving tree, zero misses. `mutation-sweep-pr` green: **49 verdicts** computed across the 6 relocated fast guards, 28 deferred to nightly by the PR-lane cap — not a zero-verdict green. `check-lockstep-pairs.sh`: 22 pairs, 0 failed, 35 DROPPED rows carrying reasoning. |
| **AC-3** — keep list, demotion register, D-3 override in the body | **satisfied** | All three present with per-row justification for 5 KEEP and 12 DROP. Pin literal deferred to merge, which AC-3's own wording licenses ("recorded in the PR body and on the issue **at merge**"). |
| **AC-4** — frozen-files green; `Changelog:` + `Migration:` naming the pin and the moved `config-lint.sh` | **unsatisfied** | Finding 2. `check-frozen-files.sh` half holds (only `description` fields moved; `version` 5.2.2 and `CHANGELOG.md` untouched). The verb half and the trailer half do not. |
| **AC-5** — `capability-parity-check.sh` green, coverage clause **vacuous** | **satisfied** | Ran it at head: `note: .../skills/run/stages does not exist — the coverage clause is vacuous (expected once #348 has landed)` then `OK — 37 capability row(s)`. Exactly the success condition the LIFETIME note declares. |
| **AC-6** — every doc naming deleted machinery updated in the same diff | **unsatisfied** | Findings 3, 4, 5 — three of the files AC-6 names by name (`docs/pipeline-manifesto.md`, `docs/config-schema.md`, `README.md`). Findings 6–9 are the same class outside AC-6's enumerated list. `CLAUDE.md`, `docs/testing.md`, `docs/{onboarding,namespaces,extension-points,team-rollout,extending,live-render}.md` and both descriptions do check out. |
| **AC-7** — `visualCapture` retirement follows the dead-key pattern end to end | **satisfied** | `config-lint.sh:242` rejects with the `design.liveRender` + migration-doc pointer; the property is gone from the schema; `docs/migrations/v1-to-v2.md:71,81,87` carries the entry; `configVersion` unchanged and `check-configversion-migration-doc.sh` green in the sweep — the `gates.costTracking` v2.1.6 shape, as claimed. `docs/live-render.md:14` records the contrast. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no design.provider is configured for this
repo, and the diff has no UI surface`. Verified rather than taken: `jq '.design'` on the effective
config (`/Users/mdonev/github/second-shift/.claude/second-shift.config.json`, the path
`lean-gate.sh` itself resolved) returns `null`, and no changed path matches
`stageParams.webComponentGlobs` — the diff is `.sh`/`.mjs`/`.md`/`.tsv`/`.json`/`.yml` only. The
disarm is justified on a repo that configures no design provider.

## Panel

Six reviewers selected, six returned — no dark reviewer, no coverage gap. `db-reviewer`,
`pipeline-reviewer` and `unit-test-mutation-reviewer` were not triggered (no DB, no queue surface,
no co-located specs); `a11y-reviewer` and the design-fidelity dimension were not routed — no changed
path matched `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`). Security,
performance and complexity returned clean. Maintainability and test-coverage independently found
findings 4 and 11. Scope-completeness returned FAIL and independently found findings 2 and 3 — its
gate is hard, and both survived verification at head, so it stands on its merits rather than on the
gate.

Findings 1, 6, 7, 8, 9 and 10 are the round's own. Finding 1 is the one the panel structurally could
not reach: `nightly-guards.yml` is unchanged by the branch, so it never entered a diff-scoped
reviewer's window.

## What is not a finding

- **The D-3 `statectl` override.** Re-verified: no live invoker outside `skills/run/`, and
  `pipeline-retro`'s `era: "stage"` arm reads the historical corpus as raw JSON through `cat`/`jq`
  rather than through `statectl`. Deleting it is grounded, and it is flagged in both the spec and
  the body as the ledger overriding the issue's reversible default. That is the honest shape.
- **`tools/capability-parity.tsv` left un-re-keyed.** Its own header and
  `capability-parity-check.sh:29` state that its paths are historical citations and are not
  existence-checked. Re-keying would destroy the audit trail this deletion exists to leave. The
  spec overriding ledger D-15 here is correct, and it says so.
- **The deferred pin literal.** Writing a version today would be stale by merge and would
  contaminate the ablation's staged arm. Deferring the *literal* is right; what is missing is the
  `Migration:` trailer that is supposed to hold it (finding 2).
- **The demotion of `unit-test-plan-reviewer` to pool.** Recorded as a decision in both the spec and
  the body, with its lockstep row and `check-model-tiers.sh` entry removed alongside the file rather
  than left dangling. Correctly handled.
- **`e2e-replay-selftest.sh` deleted rather than relocated.** It replays a *staged* run through
  `statectl` (`init → 1..9 → mark-completed`); with no run to replay there is no suite. The
  production code it reached is covered directly, which I spot-checked: `claim-issue.sh` by
  `claim-selftest.sh`, the `.mjs` bodies by `runtime-shim-selftest.mjs`.

## Verdict

`needs-work` — five blockers. Findings 3, 4 and 5 are single-line doc edits. Finding 1 is a
one-line CI path plus widening the orphan check to `.github/workflows/`. Finding 2 is a commit-verb
re-word and a real trailer; it is the one that cannot be deferred to merge, because the release
derivation reads the branch's commits and nothing else.

`pr-gates` is red for the expected reason — `lean-evidence` reporting no committed verdict record,
which this round is producing. All other CI is green.
