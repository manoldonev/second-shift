# Plan — #188: cost block silently skipped / never bare `null`

## Context / problem framing

`pipeline-cost-block.sh` (the in-band Stage 9 sub-step) records its outcome to
`costBlockApplied` in the run's state file. Two production exit paths bail **without**
calling `record()`, unlike every sibling `skipped-*` path, so the field is left bare `null`
and the miss is invisible:

- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh:74` — `no state file … nothing to do` → `exit 0`.
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh:368` — `no PRs in state — skipping` → `exit 0`.

The reported trigger (a control-repo-driven, **FE-only** run where cwd at Stage 9 is a foreign
FE checkout, so `resolve_state()` anchors to the FE repo and finds no state) is **not
reproducible in-tree**: the `be-fe-pair` PR loop (`stages/9-open-pr.md:72`) uses `git -C "$WT"`
for every op and never `cd`s, so at the cost-block call site cwd is still the control repo,
where `resolve_state()` resolves correctly. The bug as a *silent* failure is real regardless
of topology; the fix is defensive hardening + a control-repo anchor, not a repro of an
out-of-tree flow.

`prs` also has a value-shape drift: `statectl pr-add` writes `{ url, branch, repo }` for the
`--repo` (be-fe-pair) form but `{ url }` for the branch-keyed (single-repo) form. Any reader
expecting `.branch`/`.repo` breaks on the single-repo shape.

**Governing design:** a pre-flight `/plan-interview` produced a **user-delegated** Decision
Ledger (`.claude/pipeline-state/188-ledger.md`), hydrated verbatim below. It governs — where
it differs from the provisional intake-comment decisions (notably the no-state path now
**exits non-zero** rather than staying `exit 0`), the ledger wins.

## Assumptions

- `resolve_state()` already honors `STATECTL_STATE_DIR` and `SECOND_SHIFT_REPO_ROOT`
  (`pipeline-cost-block.sh:56`, `:25`), so the cross-repo remedy is an **export at the Stage 9
  call site**, not a resolver rewrite.
- The `no state file` path (`:74`) is **inherently unrecordable** — `record()` writes into
  `$STATE_FILE`, which by definition does not exist there — so it fails loud via a non-zero
  exit instead (ledger D-2).
- No `unitTestScope` is configured for this repo → no mutation surface; verification is by the
  shell selftests, `shellcheck`, and `jq empty` (per `CLAUDE.md`).

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | State-anchor mechanism for the Stage-9 cost-block invocation on cross-repo runs | Stage 9 exports SECOND_SHIFT_REPO_ROOT=<control-repo main root> (the MAIN_ROOT the stage already computes) on the documented pipeline-cost-block.sh invocation, unconditionally for ALL topologies (no-op for standalone/monorepo). No speculative in-script control-root discovery: the script cannot derive the control repo from an FE cwd (git resolves to the FE checkout; plugin-cache location is meaningless), same reasoning as the #110 bot-commit fix. Side effect is intended: config/bot-identity resolution also anchors to the control repo, matching the pair loop, which already uses the control GH_BOT for FE-repo PR writes | user-delegated |
| D-2 | Fail-loud semantics for the two silent non-recording exits | The no-PRs path (state exists) records skipped-no-prs then exits 0, joining the existing skipped-* catalog. The no-state path cannot record (no file to write into), so it logs loudly and exits 2 — a new documented non-zero meaning state-unresolvable; the always-exits-0 contract in the script header, cost-tracking-setup.md, and 9-open-pr.md is amended to: exit 0 = ran or recorded skip, non-zero = unresolvable state, surface in run summary but never block Stage 9 completion. Script-side exit code chosen over a prompt-layer costBlockApplied null-check because it is the stronger gate | user-delegated |
| D-3 | Canonical .prs record shape across run shapes | Normalize the VALUE shape, not the keys: every entry becomes {url, branch, repo} — pr-add always stamps branch and repo (from --repo when given, else derived from the config host-repo alias). Keys stay run-shape-specific (branch-keyed for single-repo/stacked slices, repo-keyed for be-fe-pair) because stacked slices collide on a repo key and pair runs collide on a branch key. state-schema.md documents the union; Stage 9 doc clarified that the be-fe-pair per-repo loop (pr-add --repo) applies whenever topology.type is be-fe-pair, even when targetRepos has a single entry — the observed FE-only drift came from taking the single-repo path | user-delegated |
| D-4 | Migration of historical state files carrying url-only prs entries | No backfill. Both consumers (pipeline-cost-block.sh PR iteration, pipeline-retro PR_URL read) iterate values key-agnostically and read only .url, so legacy entries stay readable; readers remain tolerant of the old value shape | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — record `skipped-no-prs` on the no-PRs exit (`:368`); no-state exit (`:74`) logs loud + `exit 2`; header contract comment (`:6`) amended to "exit 0 = ran or recorded skip; non-zero = unresolvable state".
- `plugins/dev-pipeline/skills/run/statectl.sh` — `cmd_pr_add()` (`:1166`,`:1173`) always stamps `branch` and `repo` (repo from `--repo`, else the config host-repo alias).
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — unconditional `export SECOND_SHIFT_REPO_ROOT=<control root>` before the shared cost-block call (`:285`); clarify the be-fe-pair per-repo loop applies whenever `topology.type == be-fe-pair` (even single `targetRepos`); amend the exits-0 note (`:282`,`:292`).
- `plugins/dev-pipeline/skills/run/state-schema.md` — `.prs` example (`:33`) + field doc (`:282`) document the `{ url, branch, repo }` union and both keyings; add `skipped-no-prs` to the `costBlockApplied` catalog (`:298`).
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — add `skipped-no-prs` bullet (`:109`); amend the always-exits-0 statement; cross-repo state-location caveat.
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` — `[NEW]` no-PRs case (records `skipped-no-prs`) + `[NEW]` no-state case (exit 2).
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — `[NEW]` assertion that branch-keyed `pr-add` writes `.prs[b].branch` and `.prs[b].repo`.

## Reuse inventory

- `record()` (`pipeline-cost-block.sh:79`) — reuse verbatim for the `skipped-no-prs` write.
- `run_identity_case()` / `make_gh_stub()` (`cost-block-selftest.sh`) and the `state-two-runs-B.json` fixture — reuse to drive the new no-PRs / no-state cases.
- `sct` / `pass` / `fail` harness helpers (`statectl-selftest.sh`) — reuse for the new pr-add assertion.
- Config host-alias resolution (`.topology.repos | to_entries[] | select(.value.path==".") | .key`) — the existing idiom used across the stage files; reuse in `pr-add`.
- No new helpers introduced.

## Implementation steps (ordered, bite-sized)

1. `pipeline-cost-block.sh:368` — replace the bare `exit 0` with `record '"skipped-no-prs"'` then `exit 0`; keep the log line.
2. `pipeline-cost-block.sh:74` — on missing state file, log loudly and `exit 2` (state-unresolvable); update the header contract comment (`:6`) to the exit-0/non-zero split.
3. `statectl.sh` `cmd_pr_add()` — branch-keyed mutation writes `{ url, branch, repo }`, resolving `repo` from `--repo` when given else the config host-repo alias (via `${SECOND_SHIFT_CONFIG}`; omit/`null` if unresolvable). The `--repo` form is unchanged.
4. `stages/9-open-pr.md` — before the shared `bash pipeline-cost-block.sh` call, add `export SECOND_SHIFT_REPO_ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")"` with a comment (control root for all in-tree topologies; no-op for standalone). Clarify the be-fe-pair loop applies for any `topology.type == be-fe-pair`. Amend the exits-0 note. **Derivation note (dispositions plan-review W1):** use the `git-common-dir`-parent formula above, NOT `git rev-parse --show-toplevel` — from a single-repo worktree `--show-toplevel` returns the *worktree* top, not the control root; the ledger D-1 phrase "the MAIN_ROOT the stage already computes" means the control root, which the common-dir parent yields correctly in both topologies (be-fe-pair cwd = control main checkout; single-repo cwd = a worktree sharing the control `.git`).
5. `state-schema.md` — update the `.prs` example (`:33`) and field doc (`:282`) to the `{ url, branch, repo }` union + both keyings; add the `skipped-no-prs` bullet to the `costBlockApplied` catalog (`:298`).
6. `cost-tracking-setup.md` — add the `skipped-no-prs` troubleshooting bullet; amend the always-exits-0 statement to the exit-0/non-zero split; add a one-line cross-repo state-location caveat.
7. `cost-block-selftest.sh` — add the no-PRs case (run-B fixture with `.prs = {}`; assert `costBlockApplied == "skipped-no-prs"`) and the no-state case (empty `STATECTL_STATE_DIR`; assert rc `== 2`).
8. `statectl-selftest.sh` — extend the `pr-add` block: assert `.prs[branch].branch == <branch>` **strictly**, and assert the `repo` **key is present** (`has("repo")`) — NOT a specific value (dispositions plan-review W2: the selftest harness runs config-less on CI where the gitignored config is absent, so `config_file()` cannot resolve the host alias and `repo` is `null`; presence, not value, is the invariant).

## Test strategy (verify-after — infra/bugfix, no `unitTestScope` surface)

- New `cost-block-selftest.sh` cases exercise the real script to both exits: the no-PRs exit asserts the recorded reason, the no-state exit asserts rc 2 (fail-loud).
- New `statectl-selftest.sh` assertion pins the normalized branch-keyed value shape.
- The Stage-9 export and catalog additions are shell/prose verified by `shellcheck` + review; no be-fe-pair harness exists in this standalone repo.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | No-PRs run records `skipped-no-prs`; no path leaves bare `null` | 1, 2 | `(AC-1)` no-PRs case + no-state exit-2 case in `cost-block-selftest.sh` |
| AC-2 | Every `.prs[*]` value carries `url`+`branch` (+`repo`); schema documents both keyings | 3, 5 | `(AC-2)` new `pr-add` shape assertion in `statectl-selftest.sh` |
| AC-3 | Stage 9 exports control-repo state location before the cost-block call | 4 | — no test (infra-only) |
| AC-4 | `skipped-no-prs` registered in the `costBlockApplied` catalog + schema | 5, 6 | — no test (infra-only) |

## Verification commands

```bash
bash plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh
env SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/statectl-selftest.sh
find plugins/dev-pipeline/skills/run -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
```

## Risks / rollback notes

- `record '"skipped-no-prs"'` runs only after the sessions/metrics/rollup checks pass, so it never fires on runs that legitimately skip earlier (those already record their own reason). Low risk.
- The no-state `exit 2` changes the script's exit contract. Stage 9 invokes the sub-step without checking rc, so a non-zero exit never blocks completion; the amended contract (exit 0 = ran/recorded skip; non-zero = unresolvable state) is documented in three places (D-2). Existing selftest cases all provide a resolvable state file, so none regress.
- Adding `branch`/`repo` to the branch-keyed `pr-add` value is additive; existing readers use `.url` (D-4). `statectl-selftest`'s `(pa1..pa5)` assertions read `.url`/`length` and stay green.
- Rollback: revert the commit; no state migration (field additions are forward-compatible; gitignored state is ephemeral — D-4).

## Out-of-scope

- The truly out-of-tree "control repo drives a foreign FE checkout via `--add-dir`, cwd = FE at Stage 9" flow: not a defined second-shift topology. Served only if the operator exports `SECOND_SHIFT_REPO_ROOT`/`STATECTL_STATE_DIR` — documented as a caveat, not auto-detected.
- Backfill/migration of historical `prs` entries (D-4).
- Any change to the be-fe-pair repo-keyed `prs` shape (already `{ url, branch, repo }`).

Unverified references: none.
