I stopped before writing code because the repository does not contain the ticket's primary target. Here is what I found, then the plan.

## Blocking finding: the kit is not in this checkout

`plugins/**` and `.claude-plugin/**` are absent — not gitignored, simply not there. The base commit says so itself: `c274751 consumer repository at pinned base, kit not present`.

- `ls plugins` → *No such file or directory*; `git ls-files` returns no `plugins/` path.
- `CLAUDE.md:11-13,122,141,178-181` all reference `plugins/**` files that do not exist here.
- `tools/selftest-suite-timings.tsv` and `tools/selftest-cache-inputs.tsv` both carry rows naming `plugins/...` suites.

Consequences, per acceptance criterion:

| AC | Status here |
| --- | --- |
| AC-1/2/3 | **No target.** `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` and its `-selftest.sh` are absent. |
| AC-4 | Producible — `.claude/settings.json` is tracked and present. |
| AC-5 | **Already red at base**, for an unrelated reason. |
| AC-6 | Producible. |

On AC-5: `tools/run-selftests.sh:410-427` validates `selftest-cache-inputs.tsv` on *every* sweep — that block is gated by neither `--full` nor `--cache-dir` — and line 420 makes a row naming an undiscovered suite a hard `die` (rc=2). The table's four rows name `plugins/dev-pipeline/tools/cost-block-selftest.sh`, which discovery cannot find. So AC-5's exact command exits 2 before running a single suite. *Caveat: I could not execute it — Bash approval was denied in this non-interactive session — so this is read off the source, not observed.*

**Second finding that needs reconciling first.** The local plugin cache has `dev-pipeline` 12.2.0/12.2.1/12.2.3 carrying a `seed_lane_worktree_settings` function commented `# ---- settings inheritance (#647)`, with `lean-gate-selftest.sh` cases `ws1`–`ws10` and a marker reading `#647 round 1, B1`. Version 11.0.0 (matching this repo's `CHANGELOG.md` head, v11.0.0) does not have it. So **this ticket appears to have already landed upstream after this base commit** — including a review round. Writing a competing implementation against a stale base is probably not the work you want.

---

## Plan of record

### Step 0 — resolve the blocker (needs your answer)

One question, and it changes everything downstream: **is the missing `plugins/` tree the thing to fix (restore the kit at this base), or is this checkout intentionally kit-free?**

I will not guess, because the two readings produce disjoint deliverables and the ticket itself says the interim "fixes nothing for anyone who installs the toolkit" and is "NOT a substitute." Delivering only the interim and calling it done would misreport the outcome.

Everything below is Path A. Path B is at the end.

### Path A — kit restored at this base

**1. Lane worktree and claim** — produced by `lean-gate.sh entry`, not by hand: branch `claude/second-shift-647`, worktree at `../second-shift-worktrees/647`, plus the bot-authored `lean-claimed` comment on issue #647 (`check-lean-chain.sh` requirement 3 — a comment posted by the operator is invisible to it).

**2. `docs/plans/second-shift-647-lean.md`** — the committed lean spec, written by me. Format follows `second-shift-641-lean.md`: issue URL, pre-flight receipt reference, base SHA, `## Design` (design: none — shell tooling with no rendered surface, which disarms the render lane at the *spec* level per `check-lean-chain.sh` item 8), `## Intent`, `## Scope`, a Decision Ledger, and `AC-1`…`AC-6` restated numbered (requirement 1 needs ≥1 numbered AC-n). The Decision Ledger resolves the ticket's Open Region.

**3. The fix — `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`.** A `seed_lane_worktree_settings` function, called from `cmd_entry` *after* `cmd_entry_sweep` (a worktree the sweep just removed is not one to seed). Source is `$MAIN_ROOT/.claude/`; the main checkout is skipped as a destination so an operator who checked the lane branch out there doesn't copy a file onto itself. Four load-bearing properties:

- **Copy, never symlink** — a symlink into the main checkout would let a lane session's write reach the operator's real settings file.
- **Never clobber** — an existing destination is left alone. This does two jobs: a re-entry reusing a worktree can't overwrite edits made inside it (AC-3), and a *tracked* `settings.json` is already present and skipped for free — so nothing has to ask git what is tracked. That is the reversible default the Open Region names.
- **Ignored, or not written at all** — asked of the destination *path* via `git check-ignore` before any bytes exist. Not optional: an unignored untracked file makes the worktree read unclean, which makes `entry`'s own sweep decline to reap it forever and makes the scheduler read a finished build as still in flight. A convenience that disables the reaper is not a convenience.
- **Advisory** — nothing here may reach `entry`'s exit status. `entry` exists to establish the attestation; an uncopyable settings file is a lost convenience, not evidence.

Detail worth pinning: destination presence tests `-e` **or** `-L`, so a dangling symlink counts as present rather than being written *through*.

**4. `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`** — new cases, written by me. AC-1 (copied when the origin has one; a fixture with no such file yields no file, no error, and *no* `settings:` line at all — absence of output is the assertion, since a consumer with no local settings must not be told they're missing something). AC-2 (regular file, not a symlink; a write to the copy leaves the origin byte-identical). AC-3 (re-entry reusing a worktree does not clobber). Plus a case pinning the check-ignore guard, so removing it reds.

**5. Scenario coverage — deliberately none, stated in the spec.** CLAUDE.md says a new gate contract extends `scenario-liveness-selftest.sh` for every verdict path it touches. This touches none: the seed is advisory and structurally cannot change `entry`'s exit status. The spec records that reasoning rather than leaving the omission to be noticed in review.

**6. `.claude/settings.json`** (AC-4, the interim) — a `permissions.allow` block with the three allows the dogfood lane needs: the gate script, `gh`, and `git fetch`. **One thing to settle:** CI runs `jq empty` over every `.json`, so there is no `//` line-comment available; the ticket-naming comment has to be a JSON-legal carrier (a `"//"` key) *and* Claude Code's settings reader has to tolerate that unknown key without warning. If it doesn't, the traceability note moves to `.claude/SECOND-SHIFT.md` and the spec says why. I'll verify before writing, not after.

**7. Commits** — `feat(dev-pipeline):`, honest verb. CLAUDE.md is explicit that `chore:` here silently downgrades a minor release to a patch, because in this repo the AI tooling *is* the product. Body carries AC-6:

```
Changelog: the lane worktree now inherits the operator's .claude/settings.local.json
  (and any untracked .claude/settings.json) from the checkout it was cut from, so a build
  session no longer starts with no allowlist and fall through to the permission classifier.
  Migration: none required. To receive the file it must be git-ignored in your repo (a global
  ignore counts); if it is not, entry says so and skips rather than leaving the worktree
  permanently unclean.
```

Not touched, because CI rejects it: `CHANGELOG.md`, `plugins/*/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — all derived at release time by `scripts/derive-release.sh` and frozen by `scripts/check-frozen-files.sh`.

**8. Verification before push** — the CLAUDE.md recipe verbatim: shellcheck sweep, `jq empty` sweep, and `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` (AC-5). While iterating I'd run `lean-gate-selftest.sh` alone — it's a 141s suite and the full sweep is ~3 minutes.

**9. PR** `claude/second-shift-647` → `main`. Body flags the Open Region resolution explicitly, as the ticket asks.

**10. `docs/plans/second-shift-647-lean-verdict.md`** — **produced by a separate review session, not by me.** `check-lean-chain.sh` requirement 4 (P10) fails the merge if the verdict's run identity matches the build run's: the session that wrote the code must not write its own review. Carries `verdict=approve`, `run_id`, `session_id`, `rounds`, `pr`, `reviewed_head`, `reviewed_patch_id`, `fidelity: not-applicable`.

**11. Merge-boundary gates** — `check-lean-chain.sh`, `check-changelog-trailer.sh`, `check-frozen-files.sh`, `mutation-sweep-pr`, both CI selftest jobs. One to watch: **`check-guard-budget.sh`**. Its classifier counts `*-selftest.sh` and `*/skills/*/lean-gate.sh` as guard/test shell — this PR adds to both, so it will register a guard-mass increase and need a `Guard-mass: +<n> <reason>` trailer. I'd measure the delta and write the trailer rather than discover it as a red lane.

**12. Follow-up issue** — delete the interim `.claude/settings.json` allows now that AC-1 ships. That removal being traceable is the entire reason AC-4 asks for the ticket reference.

### Path B — if the checkout is intentionally kit-free

Only AC-4 and AC-6 are producible: the tracked `.claude/settings.json` with three allows and the ticket comment, on a branch with the `Changelog:`/`Migration:` trailer. AC-1/2/3 have no target file; AC-5 is red at base for a reason this ticket does not own and I would not "fix" it by deleting live rows from `selftest-cache-inputs.tsv` — those rows are a real declaration, and removing them to get green is exactly the silently-skipped-gate failure that table's design refuses. I would deliver the interim, and report the rest as blocked rather than as done.

---

**Tell me which path**, and — if Path A — whether you want a fresh implementation or a reconciliation against the `#647` work already present in the 12.2.x cache. I'll start as soon as that's settled.
