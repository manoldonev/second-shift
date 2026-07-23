# Plan — #186: verifyctl resolves the command table from the verified repo, not `$host`

## Context / problem framing

On a `topology.type: be-fe-pair` run whose single target is the **non-host** repo, a **bare** `verifyctl run` (no `--repo`) resolves the command table from the `path:"."` host while running against the flat-mirror worktree of the target repo. Result: correct base, wrong commands — a false `TYPE_ERROR`, an unrequested mutating `format`, and lost verify accounting (which corrupts the eval signal).

Intake established (see the issue's intake comment) that the issue's diagnosis is partly **stale**: `--repo <id>` (its suggested-fix option 2) already shipped in #45 (`146b5ca`), and `load_config` already keys the command table on `$REPO_ID` under `--repo`. Stage 6's be-fe-pair loop already passes `--repo` and is correct. The residual defect is the **bare-caller** path — concretely `stages/8-code-review.md:154` (review-fix re-verify) and the Stage-6 quality-pass safety-net (`stages/6-verify.md:131`), neither of which passes `--repo`.

The fix is the issue's own first-listed, cheapest option (1): derive the command-table host from `.targetRepos` when it names exactly one repo and no `--repo` was given. This fixes every bare caller at the verifyctl layer at once.

## Assumptions

- `.targetRepos` is persisted by Stage 1 target routing (`state-schema.md`) and is a JSON array of topology repo ids; absent/empty on `standalone`/`monorepo` runs.
- `load_config` runs inside `cmd_run`, so `key` and the `sget` helper are visible via bash dynamic scoping (same inheritance `REPO_ID` already relies on) — confirmed at `verifyctl.sh:249-273`.
- Only the **command table** needs the target repo's id; base/worktree/sidecar/budget selection stay flat (they key off `REPO_ID`, which stays empty on the bare path). This matches the issue's "base resolves correctly; only the commands are wrong".

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Suggested-fix option (2) "add `--repo`" | Dropped — already shipped in #45 (`146b5ca`, 2026-07-12); re-implementing is a no-op | codebase-derived |
| D-2 | Which fix to implement | Option (1): in `load_config`, when no `--repo` and `.targetRepos` has exactly one entry, key the command table on that entry, else fall back to `path:"."` host | codebase-derived |
| D-3 | Scope boundary | Command-table `host` resolution only; base/worktree/sidecar/budget stay flat (avoid re-introducing the inverse of #141) | codebase-derived |
| D-4 | Regression safety | Absent/empty/>1-entry `.targetRepos` ⇒ `$host` fallback, byte-for-byte the prior `standalone`/`monorepo` behavior; add selftest coverage for the new derive path (currently only `--repo` is tested) | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/verifyctl.sh` — `load_config` host-resolution `else` branch. Existing.
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` — add derive-path cases `[NEW]`. Existing file.

No consumer repo files (verifyctl ships in the plugin checkout, de-vendored). No stage-file edits needed — the verifyctl-layer fix covers every bare caller.

## Reuse inventory

- `sget "$key" '<jq>'` (`verifyctl.sh:216`) — the existing state-read helper; reused to read `.targetRepos`. No new helper.
- The `has($h)` topology-membership check already used for the `--repo` id (`verifyctl.sh:150`) — mirrored for the derived id.
- Selftest fixtures: `$CONFIG_FIXTURE`, `reset_all`, the `SECOND_SHIFT_CONFIG=<cfg>` inline-config pattern (as v12/v13/v16 use), and the yarn shim's `ran-<script>` markers — all reused.
- New helpers introduced: none — no new functions in either file.

## Implementation steps

1. In `verifyctl.sh` `load_config`, replace the `else` (no-`REPO_ID`) host resolution: first read `derived=$(sget "$key" '.targetRepos // [] | if length == 1 then .[0] else "" end')`; when non-empty, set `host="$derived"` and assert it is a `topology.repos` entry (mirroring the `--repo` `has($h)` check, dying `EXIT_CODE=2` otherwise); when empty, keep the existing `path:"."` resolution unchanged.
2. Add selftest cases to `verifyctl-selftest.sh` `[NEW]`:
   - a be-fe-pair inline config (`be` = `path:"."`, `fe` = `path:"apps/fe"`, distinct `test` commands `yarn test-be` / `yarn test-fe`, `lint`/`typecheck`/`format` null);
   - **derive**: `.targetRepos=["fe"]`, no `--repo` ⇒ `ran-test-fe` present, `ran-test-be` absent;
   - **fallback (>1 entry)**: `.targetRepos=["be","fe"]` ⇒ `ran-test-be` present, `ran-test-fe` absent;
   - **fallback (absent)**: no `.targetRepos` ⇒ `ran-test-be` present.

## Test strategy

Verify-after (a bug fix to a shell script; the repo's test surface is shell selftests, `unitTestScope: null` ⇒ no mutation-gate surface). The behavior is pinned by the new `verifyctl-selftest.sh` cases above (derive + both fallbacks), run via the repo's configured `test` command (the `*-selftest.sh` sweep) plus `shellcheck`. No unit-test-framework surface is touched.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | bare run, single-entry `.targetRepos` ⇒ target's command table | 1 | new selftest "derive" case (`ran-test-fe`, not `-be`) |
| AC-2 | standalone/monorepo (no/empty `.targetRepos`) unchanged | 1 | new "fallback (absent)" case + existing v1–v24 (mono, no targetRepos) |
| AC-3 | `--repo <id>` + base/worktree resolution unchanged | 1 (scope boundary) | existing v21–v24 (`--repo`); base/worktree untouched by the edit |

## Verification commands

```bash
# from the repo root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
bash plugins/dev-pipeline/skills/run/verifyctl-selftest.sh          # the new cases + all prior
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Risk:** reading state inside `load_config` (previously config-only). Mitigation: `sget` is already the file's state-read helper and `key` is in scope; on any single-entry-absent case the code falls to the unchanged `path:"."` branch.
- **Risk:** a be-fe-pair `.targetRepos` naming a repo missing from `topology.repos`. Mitigation: the mirrored `has($h)` check dies `EXIT_CODE=2` with a clear message (same posture as the `--repo` validation).
- **Rollback:** revert the single `load_config` hunk; the selftest cases are additive and can stay (they pass against the reverted code only for the fallback cases — so revert both together).

## Out-of-scope

- Dual-target (`[BE]+[FE]`) bare-invocation command resolution — a `.targetRepos` with >1 entry still falls back to `$host`; dual-target verify is handled by Stage 6's `--repo` loop, and dual-target middle-stage handling is a separate tracked follow-up (`stages/2-worktree.md:117`).
- Editing the bare call sites (`8-code-review.md:154`, `6-verify.md:131`) — the verifyctl-layer fix makes them correct without per-site edits.
- Any change to base/worktree/sidecar/budget resolution.
