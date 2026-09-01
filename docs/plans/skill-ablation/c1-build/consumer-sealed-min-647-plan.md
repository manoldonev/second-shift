I stopped before writing code because verification turned up something that changes the plan materially. Here it is, then the plan of record.

## The blocking finding

**The ticket's primary fix is not implementable in this repository, and is already implemented upstream.**

Two independent facts:

1. **The target file is not here.** The ticket's remedy #1 modifies `lean-gate.sh entry`. Its canonical path is `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` (per `tools/capability-parity-check-selftest.sh:69`). This checkout has **zero tracked files under `plugins/`** — 100 tracked files total, none of them the kit. `CLAUDE.md` describes a `plugins/**` tree, `check-frozen-files.sh` and `check-changelog-trailer.sh` gate on `plugins/**`, and none of it exists. The base commit says so outright: *"consumer repository at pinned base, kit not present."* There is also no git remote and one branch, so the "until it is merged" endpoint is not reachable from this checkout either.

2. **The fix already shipped.** `seed_lane_worktree_settings()` exists in the installed kit at `~/.claude/plugins/cache/second-shift/dev-pipeline/`, in **12.2.0, 12.2.1 and 12.2.3** (absent in 11.0.0 and earlier). Its header comment is ticket #647's text nearly verbatim, it cites *"#647 round 1, B1"* (so it went through review), and it resolves the ticket's Open Region exactly as predicted — a tracked `settings.json` is skipped for free by the never-clobber rule, so nothing has to ask git what is tracked. `lean-gate-selftest.sh` carries a matching block, `# --- (ws) #647: the lane worktree INHERITS the checkout's Claude settings ---`, whose cases map one-to-one onto the oracles: ws1 = AC-1, ws2 = AC-2 (regular file, independent write), ws3 = AC-3 (re-entry does not clobber), ws4 = AC-1's no-file-no-error half.

So AC-1, AC-2 and AC-3 are satisfied upstream. Re-implementing them here would mean editing an immutable versioned artifact in a dependency cache — overwritten on next install, never reaching a PR.

**What is left, and one thing the ticket missed.** AC-4 and AC-6 are genuinely actionable here. And I found a gap the ACs do not cover: the upstream fix **refuses to seed unless the destination path is git-ignored** (otherwise the untracked file leaves the worktree permanently unclean and the reaper never collects it). This repo's `.gitignore` ignores `.claude/audit/`, `pipeline-state/`, `worktrees/`, `lean-renders/`, `.envrc` and `second-shift.config.json` — but **not `.claude/settings.local.json`**. On the operator's machine a global ignore rule covers it, which is why run 1 worked. On any other clone the seed will warn and skip, and the bug returns. Adding that one line is the highest-value change available in this repo and it is in none of the ACs.

## Plan of record

Scoped to what this checkout can actually produce. In order:

| # | Artifact | Location | Contents | Producer |
|---|---|---|---|---|
| 1 | Branch | `claude/second-shift-647` off `7d3aab3` | — | me |
| 2 | Ignore rule | `.gitignore` | `.claude/settings.local.json`, with a comment tying it to #647: the upstream seed is conditional on this path being ignored, so without it consumers silently get no inheritance | me |
| 3 | Interim allowlist (AC-4) | `.claude/settings.json` (tracked, exists) | Add a `permissions.allow` block with the three allows — gate script, `gh`, `git fetch` — merged into the existing `hooks` + `extraKnownMarketplaces` keys, not replacing them. Comment naming #647 so removal is traceable | me |
| 4 | Verification | — | `shellcheck`, `jq empty` over changed JSON, then AC-5's `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` | me |
| 5 | Commit | — | `feat:` per CLAUDE.md's honest-verb rule, with `Changelog:` + `Migration:` trailer (AC-6) | me |
| 6 | PR | — | Body flagging the Open Region resolution and the AC-1/2/3 upstream status | me — **blocked, no remote** |

Two caveats on that table. `.claude/settings.json` carries no `permissions` key today, so artifact 3 is an addition, not an edit — and JSON has no comments, so "a comment naming this ticket" has to go in a sibling string key (the pattern `docs/onboarding.md` uses for pin blocks); I will confirm the harness ignores unknown keys before relying on it. And **I could not run AC-5 in this session** — the sweep was denied by this session's permission mode, which is the ticket's own failure mode reproducing itself. I will need that command approved, or AC-5 verified in CI.

## What I need from you

One decision, because the two readings produce materially different work:

- **(A) This is the consumer repo and the scope is the consumer-side slice.** I do artifacts 1–5 above, treat AC-1/2/3 as shipped upstream (verified against the cache, cited in the PR), and confirm this repo's pin actually resolves to ≥12.2.0. **This is my recommendation** — it is the whole of what this checkout can deliver, and the `.gitignore` line is what makes the upstream fix function for anyone who is not the original operator.
- **(B) The intent was to fix `lean-gate.sh` itself.** Then I need the toolkit source checkout — the one with a real `plugins/` tree and a remote. This one cannot host that change. Note that even there, the work looks like verifying 12.2.0's implementation rather than writing it.

Tell me A or B and I will start. I have not written anything yet.
