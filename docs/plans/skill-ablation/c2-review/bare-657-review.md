I reviewed the change against the repository, not just the diff.

## What I verified as sound

- **`--help` range.** `sed -n '2,308p'` is correct: line 308 is the last header comment (`# bash 3.2 compatible…`), 309 is `set -uo pipefail`. (`lean-gate.sh:308`)
- **D-5 (advisory) holds mechanically.** `say`/`warn` are output-only (`lean-gate.sh:383-384`), the helper ends `return 0`, and `cmd_entry` discards its result. Nothing here can reach `entry`'s exit status.
- **Both mutation-catalog rows are well-formed.** `mutation-sweep.sh:1852` applies catalog seds with `sed -E`, so `\|\|`, `\[`, `\$` are literals as intended, and the anchor-drift check (`:1862`) reds a row that stops matching. Under the symlink mutant `ws2` genuinely fails; under the `-L`-drop mutant `ws7` is genuinely the sole killer, as the rows claim.
- **AC-6.** The head commit carries `Changelog:` with a `Migration:` line.

## Warnings

**W1 — AC-4's headline allow is a repo-relative prefix and probably never matches.**
`Bash(bash plugins/dev-pipeline/skills/build-lean/lean-gate.sh:*)` only matches a command literally beginning with that relative path. The gate is resolved from the *installed plugin* directory (`orchestrate-lean.sh:243`, `GATE="${LEAN_GATE:-$SCRIPT_DIR/../build-lean/lean-gate.sh}"`), and a build session types `bash G …` with `G` resolved from the skill's own location — an absolute `~/.claude/plugins/...` path. Bash permission matching is prefix-on-the-literal-string, so the one allow covering "its own first gate call" — the exact denial the ticket is named after — likely does not fire. Worth checking against a real transcript line before shipping the interim block; the `gh` and `git fetch` entries are unaffected.

**W2 — the efficacy claim rests on the operator's launch cwd, not just on round ordering.**
`spawn()` (`orchestrate-lean.sh:716-718`) sets no cwd for the child, so the BUILD session inherits whatever directory the operator ran `orchestrate-lean.sh` from. If that is the main checkout, the session already saw the operator's settings and the seed changes nothing for it — ever, not just in round 1. The plan's "residual" section frames the gap as first-round-only; the cwd dependency is the sharper and more durable statement, and it belongs in the ledger.

**W3 — no removal owner for the interim block.**
`"Delete it once that ordering no longer matters"` has no trigger, no follow-up issue and no guard. Tracked interim grants of this kind persist. One filed ticket referencing the `_comment` would make AC-4's "traceable" claim real.

**W4 — secondary to Blocker 1: seeded settings can carry operator env.**
`gh-bot.sh:145` explicitly tells operators to put `GH_BOT`-style variables in `.claude/settings.local.json`. Copying that file to a worktree path that git reports as untracked-and-not-ignored puts machine-local identifiers one careless `git add` away from a public PR branch. This disappears once Blocker 1 is fixed; it is why I would not fix Blocker 1 by only filtering `worktree_inflight`.

## Nits

- **N1** — In this repo `.claude/settings.json` is tracked, so it is present in every lane worktree by construction, and `lean-gate.sh:2030` prints `settings: … is already present — left as it is.` on *every* `entry` call for a file that can never need copying. Skipping the message when the destination is tracked, or dropping it for the non-local file, would keep `entry`'s output about the run.
- **N2** — `ws4`'s `! grep -qF 'settings:'` is a negative over the whole of `entry`'s output. Any future unrelated line containing the substring `settings:` reds a case that is about a clean-run no-op. Anchoring on `settings: copied`/`settings: cannot` would pin the same property without the blast radius.

---

## BLOCKERS

**1. The seed writes untracked, un-ignored files into the lane worktree, which makes `worktree_inflight` report the worktree as permanently holding work — blocking teardown and hard-stopping every run.**

- **File / mechanism:** `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:2033-2039` creates `$wt/.claude/` and `cp`s `settings.local.json` / `settings.json` into it. `worktree_inflight` (`lean-gate.sh:2097-2103`) reads `git -C "$wt" status --porcelain` with **no exclusion for untracked `.claude/` paths** and returns `8` on any non-empty output.
- **Why it fires:** this repo's `.gitignore` ignores only `.claude/audit/`, `.claude/pipeline-state/`, `.claude/worktrees/`, `.claude/lean-renders/`, `.claude/second-shift.config.json` — no rule matches `.claude/settings.local.json`. `$(git rev-parse --git-common-dir)/info/exclude` does not cover it either. The **only** thing hiding it is the operator's personal `~/.config/git/ignore`, which contains `**/.claude/settings.local.json`. That is a per-machine, per-user rule, and this PR ships the behavior to consumers with "Migration: none — consumers gain the behavior with no action."
- **Consequence:** on any machine or consumer repo without that personal ignore rule, the seeded file lands as `?? .claude/settings.local.json`. `worktree_destroy` then keeps the worktree forever with "its tree is not clean" (`lean-gate.sh:2099-2103`, `2131-2135`), and `orchestrate-lean.sh:925` / `:1048` issue a terminal `build-inflight` HARD STOP: *"the lane worktree still holds work nothing else has a copy of."* Every run of the lane stops, and the message points the operator at work that does not exist. D-4's targeted case — an **untracked** `.claude/settings.json` — is the one guaranteed to trigger it.
- **Why the suite is blind:** the fixture's `.gitignore` is `.claude/` wholesale (`lean-gate-selftest.sh:5098`), which encodes the operator's global-ignore posture as a repo rule. All eight `ws` cases assert file presence/content and none reads `git status` in the seeded worktree, so the entire section is green against the one condition that matters.
- **Precedent this contradicts:** the gate already refuses to write bytes into a path git would report — `lean-gate.sh:3950-3955` reds milestone 3 unless `check-ignore -q "$RENDER_OUT_REL"` passes, and names the `.gitignore` line to add. The seed does the opposite silently.
- **Fix:** mirror that precedent — skip (with a `say`, per D-5) unless `git -C "$wt" check-ignore -q ".claude/$rel"`, or add the paths to the repo's `.gitignore` and assert it. Either way the suite needs a case on a fixture whose `.gitignore` does **not** cover `.claude/`, asserting `git -C "$wt" status --porcelain` is empty after `entry`. Note that `check-ignore` reads the global excludes file, so that new case must pin `GIT_CONFIG_GLOBAL` or it will pass on this machine for the wrong reason.

**2. `.claude/settings.json` commits an unscoped standing `Bash(gh:*)` grant to every session in the repo.**

- **File / mechanism:** `.claude/settings.json:5` adds `"Bash(gh:*)"` to `permissions.allow` in a **tracked** file. Project-scope allows apply to every session any contributor runs in this repo, not only lane sessions — and by D-7's own finding, they are inherited by every lane worktree too.
- **Consequence:** `gh` is a write CLI. The pattern auto-approves `gh pr merge`, `gh pr close`, `gh issue close`, and `gh api -X DELETE …` with no prompt, removing the interactive checkpoint that enforces this repo's per-action merge authorization. The PR's own "What is deliberately NOT here" declines to change `LEAN_SPAWN_PERMISSION_MODE` on the grounds that it would "trade a random failure for a standing grant on every spawn, and that posture decision is not this slice's" — then commits a broader-audience standing grant, tracked, in the same change.
- **Fix:** enumerate what the lane actually calls (`gh issue view`, `gh pr list`, `gh pr create`, `gh pr comment`, and whichever `gh api` reads it needs) rather than `gh:*`; or drop the entry entirely and use the per-launch `--permission-mode` escape the plan already identifies as the correct operator remedy. Also resolve W1 while you are there — the allow that is scoped correctly is the one that likely does not match.
