# Plan — #110: anchor `bot-commit.sh` config resolution at the git common dir (fail-loud)

## Context / problem framing

`bot-commit.sh` exists to stop pipeline commits landing under the operator's git identity. It
resolves the consumer config **worktree-relative**:

- `plugins/dev-pipeline/skills/run/tools/bot-commit.sh:30` — `CFG="${SECOND_SHIFT_CONFIG:-$DIR/.claude/second-shift.config.json}"`
- `plugins/dev-pipeline/skills/run/tools/bot-commit.sh:33` — fallback root via `git -C "$DIR" rev-parse --show-toplevel`

Inside a git worktree, `--show-toplevel` is the **worktree**, not the main checkout. The consumer
config is gitignored in this repo, so it is never checked out into a worktree — both candidate
paths miss, `tracker.bot.enabled` reads `false` at `:37`, and the helper takes its
"bot disabled → repo default" branch at `:46`, committing as the operator. Silently: no WARN, rc=0.

Measured on this machine before planning (throwaway main-checkout + worktree pair, gitignored config):

| Probe | Result |
| --- | --- |
| config present in worktree | NO |
| `rev-parse --show-toplevel` from the worktree | the worktree — the wrong anchor |
| `--git-common-dir` → `dirname` | the main checkout — the correct anchor |

Four independent pipeline retros (#88, #89, #100, #99) recorded this failure in production runs.

**The correct anchor is already the house idiom in three sibling helpers** — this change makes
`bot-commit.sh` the fourth, rather than inventing anything:

- `plugins/dev-pipeline/skills/run/statectl.sh:120-127` — `state_dir()`
- `plugins/dev-pipeline/skills/run/verifyctl.sh:99-116` — `main_root()`
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh:22-44` — `_repo_root()` / config path

## Assumptions

- The consumer config being gitignored is a **supported** consumer choice, not a misconfiguration
  to fix — so the helper must work with it, not warn it away. (This repo does exactly that.)
- A bot-less consumer is legitimate and must keep committing successfully. `second-shift` is a
  marketplace product with external consumers; a fatal exit would break all of them.
- `git rev-parse --git-common-dir` is available on every supported git version — already relied on
  by the three helpers above and by `bot-commit.sh:53` itself.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Drop the "bot configured but config not found" WARN trigger; keep only "fallback taken AND repo resolvable" | codebase-derived | `BOT_ENABLED`/`APP_NAME` derive solely from `$CFG` (`bot-commit.sh:37-42`), so once no path yields a file, "bot intended" and "no bot here" are indistinguishable. The dropped clause has no implementable trigger. |
| D-2 | Loud means stderr WARN, never a non-zero exit | codebase-derived | AC-2 requires the fallback to still work; `bot-commit-selftest.sh:71-77` asserts a no-config repo commits successfully; four artifacts document absent-config as a legitimate disabled state. |
| D-3 | "Resolvable repo" is defined as `git rev-parse --git-common-dir` succeeding from `$DIR` | codebase-derived | Same predicate the anchor itself uses, so definition and mechanism cannot drift. Makes AC-2 testable. |
| D-4 | Two distinct WARN strings, one per fallback cause | codebase-derived | Lets the dangerous cause (no config found anywhere) be grepped apart from the benign one (config found, bot deliberately off). Follows the `[bot-commit] WARN:` prefix at `:67`. |
| D-5 | Correct the stale contract prose in four sibling artifacts; change no behavior outside `bot-commit.sh` | codebase-derived | They state the fallback is silent and three name `bot-commit.sh` as reference. `pipeline-cost-block.sh` is already correctly anchored, so only its comment is wrong. |
| D-6 | Take the optional `pipeline-doctor.sh` check (issue item 4) into scope | user-delegated | A scope-boundary call, not a codebase-derived one (Stage-4 warning 2): the issue offers item 4 as optional and the autonomous run took it. ~5 lines on the existing `warn()` helper, converting a luck-dependent post-hoc discovery into a pre-run signal — the exact complaint in all four retros. Ships with no automated test; see the traceability table. |
| D-7 | `SECOND_SHIFT_REPO_ROOT` moves the CONFIG root only — the bot-id cache stays on the real `--git-common-dir` | codebase-derived | Stage-4 warning 4 flagged the desync. Deliberate, not parity-for-its-own-sake with `verifyctl.sh:99-116`: the cache must sit in a real git dir to be writable and worktree-shared, while the override exists so selftests can redirect config resolution at a fixture. Documented in the helper header. |
| D-8 | Keep `dirname "$COMMON_DIR"` despite non-standard git-dir layouts | codebase-derived | Stage-4 warning 5. The house idiom in three siblings; consistency beats a bespoke scheme. It degrades safely — a wrong root only makes candidate 3 miss, falling through to the pre-existing repo-default path plus the new WARN, never a wrong identity. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/bot-commit.sh` — the fix
- `plugins/dev-pipeline/skills/run/tools/bot-commit-selftest.sh` — coverage
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — pre-run WARN
- `plugins/dev-pipeline/skills/run/SKILL.md` — "Bot Identity" prose (`:321`)
- `plugins/dev-pipeline/skills/run/state-schema.md` — `skipped-no-bot-wrapper` note (`:296`)
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — same claim (`:15`)
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — write-identity comment only (`:115-121`)

## Reuse inventory

- `main_root()` idiom — `plugins/dev-pipeline/skills/run/verifyctl.sh:99-116`. Mirrored verbatim
  (including the `SECOND_SHIFT_REPO_ROOT` override) rather than re-invented.
- `COMMON_DIR` computation — `plugins/dev-pipeline/skills/run/tools/bot-commit.sh:53`. Hoisted above
  the config read and reused for both the config path and the existing bot-id cache path; not duplicated.
- `[bot-commit] WARN:` stderr convention — `plugins/dev-pipeline/skills/run/tools/bot-commit.sh:67`.
- `warn()` helper — `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh:71`.
- `mkrepo()` + `gh` PATH shim + PASS/FAIL counters — `plugins/dev-pipeline/skills/run/tools/bot-commit-selftest.sh:37-46`.

No new helpers introduced.

## Implementation steps

1. **Hoist the anchor.** In `bot-commit.sh`, move the `COMMON_DIR` computation currently at `:53`
   above the config-resolution block at `:30`. Guard it so a non-repo `$DIR` yields an empty
   `COMMON_DIR` instead of aborting under `set -e`. Derive `MAIN_ROOT="$(dirname "$COMMON_DIR")"`
   when non-empty, honoring `$SECOND_SHIFT_REPO_ROOT` first (verifyctl parity).
2. **Three-candidate config resolution**, first hit wins: `$SECOND_SHIFT_CONFIG` (when it names an
   existing file) → `$DIR/.claude/second-shift.config.json` → `$MAIN_ROOT/.claude/second-shift.config.json`.
   Leave `CFG` empty when none resolve. Replaces `:30-34`.
3. **Reuse the hoisted `COMMON_DIR`** for the bot-id cache at `:53` instead of recomputing it.
4. **Loud fallback.** In the `BOT_ENABLED != true` branch at `:44-47`, when `COMMON_DIR` is non-empty
   emit one of two stderr WARNs before `exec git commit` — no config resolved, vs. config resolved
   but bot disabled. Stay rc=0 in both. Silent when `$DIR` is not a resolvable repo.
5. **Header note** documenting the new resolution order and the `--amend --reset-author` repair
   recipe for already-mis-attributed commits (`--amend` alone preserves the original author).
6. **Selftest — amend case 3** to assert the no-config fallback now emits the WARN, alongside its
   existing repo-default-identity assertion.
7. **Selftest — new cases**: (5) main checkout with a gitignored config + a `git worktree add` child,
   `-C <worktree>`, no env → bot identity and no WARN; (6) explicit `"enabled": false` config →
   repo default plus the bot-disabled WARN; (7) `-C` a non-repo directory → our WARN is absent.
8. **Doctor check** in `pipeline-doctor.sh` near the existing `CFG` at `:58`: `git check-ignore -q "$CFG"`
   → `warn()` that the config will be absent in worktrees; `ok()` otherwise.
9. **Doc corrections** at the four sites listed above.

## Test strategy

Verify-after (infra/shell change; no runtime framework in this repo). `bot-commit-selftest.sh` is the
executable specification and is discovered by the repo-wide selftest glob, so the new cases join CI
without registration.

Case 5 is the AC-1 regression test and is **new scaffolding, not a new assertion** — cases 1-4 all use
single `git init` repos (`bot-commit-selftest.sh:37-46`); nothing in the file calls `git worktree add`
today. It must build a real main-checkout + worktree pair with a `.gitignore`d config to reproduce the
bug, and it fails against the current `bot-commit.sh`.

Case 3 is an **expectation change**, not an addition: it currently passes only because the fallback is
silent.

Unit-test mutation gate: not applicable — `commands.second-shift.unitTestScope` is `null`, so this repo
has no mutation surface.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Worktree + untracked config, no env → `<appName>[bot]` identity | 1, 2, 3 | selftest case 5 (AC-1) |
| AC-2 | Bot genuinely disabled → repo default still works, and says so on stderr when `-C` is resolvable | 4 | selftest cases 3, 6, 7 (AC-2) |
| AC-3 | Selftests cover both cases, green in the standard sweep | 6, 7 | full `*-selftest.sh` sweep |
| D-7 | `SECOND_SHIFT_REPO_ROOT` moves the config root but not the id cache | 1 | selftest case 9a/9b/9c (added at Stage-8 review) |
| — | `$SECOND_SHIFT_CONFIG` (candidate 1) outranks the `-C` dir config | 2 | selftest case 8 (added at Stage-8 review) |
| — | Doctor pre-run WARN on a gitignored config (D-6, issue item 4) | 8 | — no test — `pipeline-doctor.sh` has no paired selftest in this repo (pre-existing); the check is a `warn()` line on an environment probe, verified by running the doctor. Building a doctor harness is out of scope for a bug fix. |

## Verification commands

```bash
bash plugins/dev-pipeline/skills/run/tools/bot-commit-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# Repo CI gates that also gate this PR (Stage-4 warning 3):
bash scripts/check-frozen-files.sh        # no version/CHANGELOG edits in a feature PR
bash scripts/check-changelog-trailer.sh   # every plugins/** PR carries a Changelog: trailer
```

Per CLAUDE.md this PR touches `plugins/**`, so its commits carry a **`Changelog:`** trailer, and it
must NOT edit `plugin.json` `version`, `CHANGELOG.md`, or `marketplace.json` `metadata.version` —
those are derived at release time and `check-frozen-files.sh` rejects a feature PR that writes them.

## Risks / rollback notes

- **New WARN noise on bot-less consumers.** Every commit in a repo without a bot config now prints a
  stderr line. This is AC-2's explicit intent, and it is stderr-only and non-fatal, so no caller
  breaks. Mitigated by making the deliberate-disable message distinct from the dangerous one.
- **`set -e` interaction.** The hoisted `COMMON_DIR` runs in a command substitution that can fail for a
  non-repo `$DIR`; without a guard the script would abort where it previously fell through. Step 1
  guards it explicitly and case 7 covers it.
- **`SECOND_SHIFT_CONFIG` pointing at a missing file** currently falls through via the `:32` re-check.
  The new order preserves that (the env candidate is only taken when the file exists).
- Rollback is a single-file revert of `bot-commit.sh`; the doc and selftest changes are inert without it.

## Out-of-scope

- Changing `pipeline-cost-block.sh` behavior — already correctly anchored; comment only.
- Making the fallback fatal (D-2).
- Un-gitignoring the consumer config, or any change to how the config is distributed to worktrees.
- Issue item 5 (confirm-and-close of #88/#89): verified complete at HEAD during intake —
  `statectl.sh:120-127` and `verifyctl.sh:99-116` both carry the anchor. Zero code work; the PR body
  notes that #88/#89 can be closed on merge.

Unverified references: none — every path, line, and function above was read in the pinned checkout.
