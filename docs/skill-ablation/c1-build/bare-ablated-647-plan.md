I've read enough to write a grounded plan. Three things I found that change the shape of it:

**`entry` does not cut the worktree.** `cmd_entry` (`lean-gate.sh:2663`) only attests the ledger and sweeps stale worktrees. The worktree is cut by the *build session* at `build-lean/SKILL.md` step 3, one step after `G entry`. So AC-1's phrase "after `entry` cuts a lane worktree" describes something no code does. What `entry` *does* have is both roots — `REPO_ROOT` (current worktree) and `MAIN_ROOT` (main checkout, `lean-gate.sh:498-510`) — and selftest case `(d5)` already proves `entry` is expected to run from *inside* a linked worktree. That's the seam.

**`.claude/settings.json` is already tracked** (`git ls-files .claude/` confirms it) and carries `hooks` + `extraKnownMarketplaces`, no `permissions`. AC-4 is an edit to an existing file, not a new file.

**The working tree has ~75 pending deletions** (every `SKILL.md` and agent `.md`), and `lean-gate-selftest.sh:23` binds `SKILL="$HERE/SKILL.md"`. AC-5 may not be green before I write a line.

---

# Plan of record

## 0. Baseline (before any edit)

Run `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` and record the verdict. If the deleted `SKILL.md` files red the suite, AC-5 is unattainable from this tree and I stop and report rather than "fixing" the ablation by resurrecting files. **Producer:** me. **Artifact:** none committed — a stated baseline in the PR body.

Also confirm empirically where the payload session's project dir actually is, since `spawn()` (`orchestrate-lean.sh:691-722`) runs `claude -p` with **no `cd`** — it inherits the orchestrator's cwd. This decides whether the fix is live or inert (see §7).

## 1. Branch

`claude/second-shift-647` cut from `main`. **Producer:** me.

## 2. Spec — `docs/plans/second-shift-647-lean.md`

Matches the convention `lean-gate.sh:890` resolves (`docs/plans/second-shift-<issue>-lean.md`, siblings at `second-shift-641-lean.md`). Contains: the numbered `AC-1`…`AC-6` verbatim from the ticket; a Decision Ledger with the two decisions below (it will be lint-checked by `ledger-lint.sh` if I include the section — `lean-gate.sh:3378`); and the restatement of AC-1 in terms the code can satisfy.

Two decisions the spec records:

- **D-1 — `entry` seeds, it does not cut.** One rule, two shapes: when `REPO_ROOT != MAIN_ROOT`, seed `$REPO_ROOT`; when `entry` runs from the main checkout, seed each lane worktree `lean_worktrees()` already enumerates. The second half is what breaks the circularity — a session that is *already* denied everything cannot seed its own worktree in time to help itself.
- **D-2 — the ticket's open region.** Skip `.claude/settings.json` when tracked (the worktree already has it); copy only what the worktree lacks. Reversible default, flagged in the PR.

## 3. Code — `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`

A new `settings_seed_worktree()` helper placed beside `audit_toolkit_opted_out()` (`:1852`), which already establishes the `$root/.claude/settings{,.local}.json` idiom. It must:

- take a worktree path; no-op silently when it equals `$MAIN_ROOT`;
- for each of `settings.local.json` and `settings.json`: skip if the source is absent (**AC-1 null case**), skip if the destination already exists (**AC-3**), skip `settings.json` when it is tracked (D-2);
- copy with `cp` — never `ln -s` (**AC-2**, and the ticket's stated reason: a symlink lets a lane session's write reach the operator's real file);
- be **advisory** — a failed copy warns and never reaches `cmd_entry`'s exit status, matching how `cmd_entry_sweep`'s result is deliberately discarded (`:2735-2738`).

Call site: inside `cmd_entry`, **after** `cmd_entry_sweep` — seeding a worktree the sweep is about to remove is wasted work.

## 4. Interim allowlist — `.claude/settings.json` (AC-4)

Add a `permissions.allow` block with the three the dogfood lane needs — the gate script, `gh`, `git fetch` — plus a comment key naming **#647** so its removal after AC-1 ships is traceable. JSON has no comments, so the marker is a sibling key (e.g. `"//": "…#647…"`), consistent with the file staying `jq empty`-clean under CLAUDE.md's verification recipe.

## 5. Tests — `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`

New `(ws*)` case block, modelled on the existing `(d5)` harness (`:583-600`), which already cuts a linked worktree on the fixture tree and drives real `entry` in it with a real audit-hook-written ledger:

| case | asserts | AC |
| --- | --- | --- |
| `ws1` | origin has `settings.local.json` → worktree carries it after `entry` | AC-1 |
| `ws2` | origin has none → worktree has none, `entry` still exits 0 | AC-1 |
| `ws3` | `[ ! -L ]` on the copy, and a write to the worktree copy leaves the origin bytes unchanged | AC-2 |
| `ws4` | pre-existing worktree file survives a second `entry` byte-for-byte | AC-3 |
| `ws5` | tracked `settings.json` is not re-copied (D-2) | — |

Per CLAUDE.md's tier map these are per-tool behavioral cases, not prose greps and not a mirror harness. **No `scenario-liveness-selftest.sh` extension**: this adds no verdict path — `entry`'s exit status is unchanged by construction. I'll state that reasoning in the PR rather than let its absence read as an oversight.

## 6. Docs

`docs/testing.md` — only if I decline a coupling that a reader would expect; CLAUDE.md requires declined couplings be recorded under *Couplings considered and declined* rather than left silent. No `LOCKSTEP-BEGIN` anchor: there is only one copy of this contract.

## 7. The efficacy caveat — stated in the PR, not silently absorbed

Claude Code resolves project settings at session launch, from the project dir. `spawn()` passes no `cd`. So seeding a worktree helps the **next** session launched with that worktree as its project dir, not the one running `entry`. §0's check settles whether the observed #641 failure was a session whose project dir *was* the worktree (the ticket's premise) — if it was not, the copy is correct but does not by itself explain the two-run divergence, and I will say so plainly rather than claim a fix I did not verify. This does not block: AC-1–AC-3 are file-placement oracles and are satisfiable either way.

## 8. Verification (AC-5)

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```
Plus the new suite standalone. If the diff-scoped `mutation-sweep-pr` job surfaces a survivor, it is data — only one absent from `tools/mutation-baseline.tsv` reds.

## 9. Commit (AC-6)

`feat(dev-pipeline): …` — a new capability, and CLAUDE.md is explicit that `chore:` here would silently downgrade a minor release. Trailer with the required `Migration:` line, since consumers gain behavior they did not have. **No** version bump, **no** `CHANGELOG.md` edit — both are release-time derived and CI rejects a feature PR that touches them.

## 10. PR

Body carries: the AC→evidence table, D-2's open region flagged for the reviewer, §7's caveat, and the note that AC-4's tracked allowlist is interim and removable once AC-1 ships.

---

Two things I'd flag before starting: the §0 baseline could invalidate AC-5 outright, and AC-1's "entry cuts a lane worktree" is factually wrong about the code — I've resolved it as "entry seeds," which I believe is the ticket's intent, but it is a reinterpretation rather than a literal reading. Stopping here as instructed.
