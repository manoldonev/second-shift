# C2-b — the built-in `/code-review` on PR #657

The arm-2a challenger session for sample **C2-b**, run 2026-09-03 against the pinned clone. Registered at [`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §B; scored against the frozen C2 rule at [`docs/skill-ablation-pre-registration.md`](../../../skill-ablation-pre-registration.md):146-161. Everything below the rule is this session's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2-b-657
printf '%s' '/code-review max pr-657' | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT \
  -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob,Bash" \
    --output-format stream-json --verbose
```

Byte-identical to the registered form. `RUN_ID`, `LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` were additionally absent from the launching environment, so no lane variable leaked into the challenger; the registered `env -u` list itself is unchanged.

## Apparatus

| fact | value |
| --- | --- |
| pinned base (`main`) | `b657907f52011c06afad34fc026fbbaeca8ae88a` |
| pinned head (`pr-657`) | `f8f7c142919507a58acbc268596c1127b4fa1ae0` |
| pre-run assertion | both `git rev-parse` tests passed; clone tree clean |
| `plugins/` in the working tree | present (spec D-1) |
| exit code | `0` |
| stderr | `Background tasks still running after 600s; terminating. Set CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.` |
| wall clock | 2026-09-03T10:34:37Z → 2026-09-03T11:14:38Z |
| capture | 5,207,181 bytes, 2,429 lines, sha256 `4cc0ff4b34f88d38…` |
| `tools/classify-capture.sh` | exit 0 — [classify-capture] COMPLETE — /private/tmp/c2-b-657.stream.json ran to completion successfully (subtype=success, is_error=false). |
| parent `tool_use` | `Bash` 2, `Grep` 1, `Read` 3 |
| subagent `tool_use` | `Bash` 436, `Grep` 15, `Read` 28, `SendMessage` 9, `ToolSearch` 7, `Write` 6 |
| `result` events | 5 |
| tool calls touching `review-lean` | 1 |

Only an exit-0 capture is scored (§B *A capture must be proven complete before it is scored*); this one classified `COMPLETE`, so its findings were read out of it.

---

## Assistant text — `result` event 1 of 5

All 10 finder angles ran; subagent result delivery was broken in this environment (only the conventions angle could report back — its Write tool was denied and it correctly refused to route around that), so I performed the remaining angles, verification, and the sweep directly. I also ran the full `lean-gate-selftest.sh` (green, all 8 new `(ws)` cases pass), every applicable repo guard (`check-fail-open-shapes`, `check-gate-buckets`, `check-lockstep-pairs`, `check-guard-budget main`, `check-frozen-files main`, `check-changelog-trailer main`, `check-config-shadowing`, `stack-generality-lint`, `capability-parity-check` — all clean), and empirically reproduced the top finding.

```json
[
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2035,
    "summary": "The seed writes .claude/settings{,.local}.json into the lane worktree without first asserting the path is git-ignored there, so on any repo/machine lacking that ignore rule the copy makes the worktree permanently 'in flight' — bricking teardown, the entry sweep, and the orchestrator's post-BUILD gate — and puts the operator's local settings (env secrets, apiKeyHelper, MCP creds) inside a tree the build session commits from.",
    "failure_scenario": "Reproduced: a repo whose .gitignore does not cover .claude/settings.local.json (this repo's .gitignore does NOT — it is ignored only by the operator's personal /Users/manoldonev/.config/git/ignore) plus an existing $MAIN_ROOT/.claude/settings.local.json. After `entry`, `git -C \"$wt\" status --porcelain` returns `?? .claude/` where it returned empty. worktree_inflight (lean-gate.sh:2097) then returns 8 'its tree is not clean' -> worktree_destroy (2131) refuses removal, so the #442 entry sweep and step-9 close-out teardown keep every lane worktree forever; cmd_inflight (2297) returns 8 so orchestrate-lean.sh's #531 AC-5 BUILD exit contract HARD STOPS the run with 'the lane worktree still holds work nothing else has a copy of'. Verified directly: `git worktree remove` -> \"fatal: ... contains modified or untracked files\". Secondary harm: a build session doing `git add -A` stages the operator's settings into a public PR. Invisible to the new suite because the fixture's .gitignore is `.claude/` (lean-gate-selftest.sh:5098) and invisible on this machine because of a global ignore no consumer has — yet the Changelog trailer says 'Migration: none — consumers gain the behavior with no action'. The repo already has the right mechanism one function away: lean-gate.sh:3952 refuses to write render output unless `git -C \"$REPO_ROOT\" check-ignore -q` passes."
  },
  {
    "file": "/private/tmp/c2-b-657/.claude/settings.json",
    "line": 5,
    "summary": "The interim allow \"Bash(bash plugins/dev-pipeline/skills/build-lean/lean-gate.sh:*)\" is a repo-RELATIVE path, but the lane resolves the gate from the installed plugin root, so the rule can never match the command the session actually runs — leaving AC-4's stated purpose unmet.",
    "failure_scenario": "Claude Code matches Bash rules against the literal command prefix. .claude/second-shift.lock.json and this same file's `extraKnownMarketplaces` install dev-pipeline from the github marketplace `manoldonev/second-shift@main`, so build-lean/SKILL.md's `bash G entry <issue>` resolves G to an absolute path under the plugin cache (the repo's own convention for plugin scripts is `bash \"${CLAUDE_PLUGIN_ROOT}/skills/...\"` — see plugins/second-shift/skills/onboard/SKILL.md:38), and orchestrate-lean.sh:243 defaults LEAN_GATE to `$SCRIPT_DIR/../build-lean/lean-gate.sh`, also absolute. `bash /Users/.../plugins/dev-pipeline/skills/build-lean/lean-gate.sh entry 647` does not start with `bash plugins/dev-pipeline/...`, so the allow never fires and the first-round gate call this block exists to cover still falls through to the classifier — the exact 2026-08-22 failure the ticket is about."
  },
  {
    "file": "/private/tmp/c2-b-657/.claude/settings.json",
    "line": 6,
    "summary": "\"Bash(gh:*)\" lands an unbounded, un-prompted grant for the entire GitHub CLI in a TRACKED project settings file, so it applies to every agent session in this repo rather than only the lean lane's read calls.",
    "failure_scenario": "`gh:*` matches `gh api -X DELETE /repos/manoldonev/second-shift`, `gh pr merge`, `gh release delete`, `gh secret set`, `gh repo delete`, `gh workflow run`. Because the file is tracked, every contributor and every agent session that trusts the project inherits it — not just the dogfood lean lane. The stated need is the sweep's `gh pr list` and the ticket reads; a narrowed pair such as `Bash(gh pr list:*)` / `Bash(gh issue view:*)` / `Bash(gh api:*)` would cover it. The plan's own 'What is deliberately NOT here' rejects `bypassPermissions` as 'a standing grant on every spawn' while this block grants a standing repo-wide one by a different route."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2813,
    "summary": "The seed is hung off `entry`, which is the run's FIRST call and precedes worktree creation, so on a fresh run the worktree that gets cut is never seeded — the fix is placed one layer above where the defect lives.",
    "failure_scenario": "SKILL.md step 1 is `bash G entry <issue>`; step 3 cuts the worktree. At step 1 `lean_worktrees_for_branch \"$LEAN_BRANCH\"` matches nothing, so `seed_lane_worktree_settings` returns at line 2015 having done nothing, and the worktree created at step 3 carries no settings until some LATER `entry` — a re-entry or the next round. The plan's 'The residual, named rather than left to be found' concedes exactly this and papers over it with the tracked-allow block that finding #2 shows is likely inert. The mechanism belongs where the worktree is created, or at the spawn: orchestrate-lean.sh:717 already builds the `claude -p` command line (`--permission-mode \"$PERM_MODE\"`) and is the one place that knows both the worktree path and the launch, so a `--settings`/cwd argument there would cover round 1 and every round after with no filesystem copy at all."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
    "line": 5585,
    "summary": "`ws_wt` calls `fail` from inside a command substitution, so its `FAILS=$((FAILS + 1))` is lost in the subshell and the setup guard cannot red the suite it was written to red.",
    "failure_scenario": "`p60=\"$(ws_wt 60)\"` (line 5590) runs ws_wt in a subshell. `fail()` (line 27) is `echo ... >&2; FAILS=$((FAILS + 1))` — the increment mutates the subshell's copy and is discarded on exit, while the suite ends with `exit \"$FAILS\"`. So the fixture-collision guard the comment introduces as 'a future collision fails HERE instead of passing vacuously downstream' prints its message but contributes zero to the exit code. It is the only `fail` in this 6982-line suite invoked from inside `$( )`. Worse, `printf '%s' \"$p\"` still emits the path after the failure, so the caller proceeds against a directory that does not exist."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
    "line": 5590,
    "summary": "No (ws) case pins the seed's BRANCH SCOPE, so widening it from `lean_worktrees_for_branch \"$LEAN_BRANCH\"` to the sibling `lean_worktrees` one line above would spray the operator's settings into every registered worktree in the repo with all eight cases and both new catalog mutants still green.",
    "failure_scenario": "During the (ws) block, ~25 worktrees from the (wt) section plus claude/acme-60..65 are registered on branches other than the one being entered. Every ws assertion reads only `$p60`..`$p65` for the issue currently being entered, and ws4's negative (`[ ! -e \"$p61/...\" ]`) is evaluated during `entry 61` — before the later entries that a widened seed would use to write into p61 and into every (wt) fixture. A one-token edit at lean-gate.sh:2014 (`lean_worktrees_for_branch \"$LEAN_BRANCH\"` -> `lean_worktrees`, which is right there at 1955 and is what cmd_entry_sweep calls) therefore survives the whole suite, while in production it would copy an operator's allowlist into unrelated checkouts — including the review-lane and non-lane worktrees the sweep's D-10 blast-radius rule deliberately excludes."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
    "line": 5568,
    "summary": "The eight new per-tool fixture cases do not state why no scenario in scenario-liveness-selftest.sh covers them, which the repo CLAUDE.md requires of every new fixture case — and the tier map routes this change's shape to a scenario.",
    "failure_scenario": "CLAUDE.md:140-142: '**Scenario-first.** A new per-tool fixture case must name the invariant it guards and why no scenario in `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` covers it. The since-retired stacked-PR path died with all 42 selftests green because every one of them checked a component against itself.' The (ws) block's 15-line header covers the gitignore premise, the one-entry-per-fixture choice, and why ws_wt wraps wt_make, but never mentions a scenario; scenario-liveness-selftest.sh is untouched by the diff. CLAUDE.md:178's tier map routes 'a composed verdict path reaching a terminal write' to a scenario, and `cp \"$src\" \"$dst\"` at lean-gate.sh:2035 is a terminal write reached from a composed path. Sibling suites carry the required sentence verbatim (branch-prefix-selftest.sh:6, checked-call-selftest.sh:13, pipeline-doctor-selftest.sh:575, gh-bot-selftest.sh:8, audit-selftest.sh:138). Note finding #1 is precisely the class of defect a component-against-itself fixture cannot see."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2021,
    "summary": "The seed copies `.claude/settings.json` without the files that settings file references, so a worktree can inherit a hook configuration pointing at a script that is not there.",
    "failure_scenario": "This repo's .claude/settings.json declares a SessionStart hook `bash \"$CLAUDE_PROJECT_DIR/.claude/tools/second-shift-doctor.sh\"`. Here the hook script is tracked so a worktree has it, but the seed's whole premise is the UNTRACKED case (D-4: 'The second is copied only when the worktree lacks it, which is exactly the untracked case the issue names'). In a consumer repo where .claude/settings.json is untracked, its `.claude/tools/*`, `.claude/agents/*` and `.claude/commands/*` are untracked too and are not copied — so the seeded worktree gets a settings file whose every hook/command path resolves to nothing, and each session there fires a failing SessionStart hook. `.claude/second-shift.config.json` (gitignored, and named in CLAUDE.md as load-bearing for the lane) is likewise not seeded; it happens to be safe only because CONFIG resolves off $MAIN_ROOT at line 518."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2014,
    "summary": "`entry` now forks `git worktree list --porcelain` twice back to back over the same unchanged repo state.",
    "failure_scenario": "cmd_entry_sweep's loop is fed by `$(lean_worktrees)` (line 2727), and the very next statement, seed_lane_worktree_settings, calls lean_worktrees_for_branch, which re-runs `$(lean_worktrees)` at line 1977 — a second `git worktree list --porcelain` fork plus a second awk plus a second full re-parse, on the run's first and most-repeated call, for a list the sweep just read and cannot have changed except by removals the sweep itself performed. Hoisting one read into a variable the sweep returns (or having the sweep publish its surviving set, which it already computes) removes the fork and also removes the need for the 'AFTER the sweep on purpose' ordering comment."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2030,
    "summary": "The 'already present' branch is the normal steady state in this repo, not an exception, so it prints an unactionable line on every `entry` for every lane worktree, forever.",
    "failure_scenario": "`.claude/settings.json` is TRACKED here (it is the file this very PR edits), so every lane worktree always has it and `[ -e \"$dst\" ]` is always true — meaning every `entry`, on every re-entry and every round, emits `settings: <abs worktree path>/.claude/settings.json is already present — left as it is.` once per registered lane worktree. Once settings.local.json is seeded on the first pass, that is two such lines per worktree per call, none of which name anything the operator can act on. The design note for the absent-source case is explicit that a no-op 'must not be told they are missing something'; the same reasoning applies to the skip-if-present no-op, which should be silent (or logged only when it actually declines to overwrite differing content)."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh",
    "line": 5583,
    "summary": "`ws_wt` is a one-section wrapper compensating for a hazard that lives in `wt_make` itself, which has ~25 other call sites carrying the identical hazard unguarded.",
    "failure_scenario": "The comment states the problem exactly: `wt_make` (line 5142) ends its `git worktree add ... 2>/dev/null` (line 5144) swallowing stderr, so a reused fixture number yields NO worktree while `wt_make` still prints the path — 'every assertion below then reads a path that does not exist, which is indistinguishable from a seed that declined to run. Caught the first time this section was written, on `wt_make 40`.' There are 26 `wt_make` call sites in this file; 25 of them remain exposed to the failure this diff just paid to diagnose, and the new suite now hard-codes the numbers 60-65 as one more collision surface. Folding the `wt_registered` check into `wt_make` (returning non-zero and letting the caller's own assertion red) fixes every site and deletes the wrapper."
  },
  {
    "file": "/private/tmp/c2-b-657/plugins/dev-pipeline/skills/build-lean/lean-gate.sh",
    "line": 2020,
    "summary": "The `[ \"$wt\" = \"$MAIN_ROOT\" ] && continue` guard is unreachable-by-consequence: the never-clobber rule five lines down already produces the same outcome, and no case covers it.",
    "failure_scenario": "Its comment justifies it as preventing 'the file copied onto itself'. But when `$wt` equals `$MAIN_ROOT`, `dst` is byte-identical to `src`, so `[ -e \"$dst\" ]` at line 2029 is true and the copy is skipped anyway — deleting line 2020 changes only whether one extra 'already present' line is printed. Nothing in the (ws) block distinguishes the two, and neither new mutation-catalog row reaches it, so it is untested code justified by a hazard the adjacent rule already owns. The design note directly above already claims 'one rule doing two jobs' for the never-clobber test; this is a third job it silently does as well, and the guard should either be dropped or re-justified on the message it suppresses."
  }
]
```

Notes for the caller:
- **Everything the PR set out to prove, it proves.** The new `(ws1)`–`(ws8)` cases all pass in a full green suite run, both new `tools/mutation-catalog.tsv` rows apply cleanly under `sed -E`, leave the guard non-identical, and produce `bash -n`-valid mutants killed by exactly the cases their notes name. The `sed -n '2,308p'` help range is correct (line 308 is the last header line, 309 is `set -uo pipefail`), and case `(w)` guards it. Commit trailers, verbs, and every repo guard pass.
- **Finding #1 is the one to act on before merge** — it is reproduced, not inferred, and it is silent in both the suite and on the author's machine for two different accidental reasons. The one-line remedy already exists in this same file at line 3952.
- The 11 background finder agents are still listed as running; their results never reached this session, so nothing below depends on them except the CLAUDE.md `Scenario-first` finding, whose rule text I verified independently at `/private/tmp/c2-b-657/CLAUDE.md:140`.

---

## Assistant text — `result` event 2 of 5

All 10 finder angles have now reported back (the delivery failure resolved itself — their results arrived as task notifications). They independently confirm the review I already gave you and add material worth acting on. Delta only:

## Independent confirmation of the top finding
Three separate angles reproduced the `.gitignore` defect end-to-end, one on a fixture repo with `core.excludesFile=/dev/null`: `entry` seeds the file → `?? .claude/` → `inflight` returns 8 → `teardown` keeps the worktree → `orchestrate-lean.sh` hard-stops at `build-inflight`. That finding is not in doubt.

## New, and I verified the two that matter most

**The stale copy shadows the live file for the gate's own reader.** `audit_toolkit_opted_out` (`lean-gate.sh:1860`) loops `for root in "$REPO_ROOT" "$MAIN_ROOT"` — worktree first. Combined with never-clobber, an operator who re-enables audit-toolkit in the main checkout gets a lane worktree whose seeded copy still says `false`, and a re-entry from inside it prints the wrong refusal. Same shape for the more likely loop: the operator widens the allowlist after a round-1 denial, re-runs, and `entry` prints "already present — left as it is" while the new grant never arrives. The fix reports success on stdout while doing nothing.

**`spawn()` never changes directory** — confirmed at `orchestrate-lean.sh:717`. Every `cd` in that file (583, 745, 767, 784, 793, 815, 820, 838) wraps a *direct gate call*, never a spawn. So under orchestration no spawned session ever has the lane worktree as its cwd, which is the only shape the copy repairs. That doesn't disprove the ticket — the 2026-08-22 incident may have been a hand-run `claude` in the worktree — but the plan's diagnosis is stated as if it covers the orchestrated lane, and it doesn't. Related: `claude` accepts `--settings <file>`, and line 717 already threads `--permission-mode`; the plan's "deliberately NOT here" section never names or rejects that option, which has no ordering lag and no filesystem mutation.

**Reproduced by two angles:** `mkdir -p` on a *prunable* worktree (directory deleted, registration still listed) resurrects the directory — after which both `git worktree prune && git worktree add` and `git worktree remove` fail, and the operator's settings sit orphaned outside any checkout. One-line `[ -d "$wt/.git" ] || continue`.

**Also new:** the dangling-symlink guard is leaf-only, so a symlinked `$wt/.claude` still lets `cp` write outside the worktree; the loop skips `$MAIN_ROOT` but not `$REPO_ROOT`, unlike `cmd_entry_sweep` three lines away, so it mutates the caller's own tree on continuation rounds; `MAIN_ROOT` resolves to the *parent* of a bare repo and to `<super>/.git/modules` for submodules; and the `$MAIN_ROOT` guard compares bash's logical `pwd` against git's resolved path, so it's dead under symlink skew (this checkout is literally at `/private/tmp`).

**Simplification set** (none load-bearing): `[ -n "$paths" ]` at :2015 is unreachable-false; the `mkdir || warn` arm duplicates `cp`'s own failure path and no test reaches it; ws5 and ws6 add no coverage over ws1/ws3 — the catalog's own new row concedes ws3 and ws6 are interchangeable; the ws4 `mv`/`mv-back` stash disappears if ws4 moves above line 5588; and `sed -n '2,308p'` hand-bumps a number three sibling guards in this repo already handle range-free.

## Process note
Five of the agents had their `Write` tool denied and each correctly refused to route around it via Bash, relaying findings inline instead. That's the right call and I'm not overriding it — but it's why delivery was noisy. If you want the per-angle JSON on disk for a future run, `Write` to `/tmp` needs approving up front.

Nothing here changes the merge recommendation: the `check-ignore` guard at `lean-gate.sh:3952` is still the one-line remedy for the blocker, and the seed's placement in `entry` is still the structural issue underneath.

---

## Assistant text — `result` event 3 of 5

The final angle (line-by-line) reported. Two items are new and one I checked and am downgrading.

**Correction to what that agent claimed.** It reported that `(ws2)` passes vacuously over a seed that copied nothing, because `printf ... >>` at `lean-gate-selftest.sh:5606` creates the file that the `-f` conjunct then checks. The mechanism is real but the headline scenario isn't: the fixture writes `.gitignore` as `.claude/` wholesale *before* its only `git add -A` (`:5098-5099`), so nothing under `.claude/` is tracked and a fresh worktree has no `.claude` directory at all. Against a no-op seed, `>>` fails on the missing parent, `-f` is false, and ws2 reds correctly. The gap that does survive is narrower: if `mkdir` succeeds and `cp` fails — the `warn` branch — `>>` creates the file and ws2 passes on nothing. No test reaches that branch anyway, so it's a latent weakness in the conjunct, not the vacuous pass as described.

**New and worth having — the missing test.** The concrete shape for a `(ws9)` that would have caught the blocker: give one fixture a `.gitignore` matching the *real* repo's (ignoring only `.claude/audit/`, `pipeline-state/`, `worktrees/`, `lean-renders/`, `second-shift.config.json` — not `.claude/` wholesale), then run `teardown` or `inflight` against that worktree after the seed. It reds immediately on `keeping ... its tree is not clean`. Every current (ws) case stops at the copy and never drives the cleanliness predicates downstream of it, which is the structural reason all eight are green over a defect that bricks the lane.

**A sharper argument on `Bash(gh:*)`** than the generic "it matches `gh repo delete`" — verified: the lane's integrity model depends on a bot-identity trust filter. `lean-reconcile.sh:279` selects comments on `(.user.type // "") == "Bot"`, and `lean-evidence.sh:46` states a writer "cannot post a marker that survives the `.user.type == \"Bot\"` trust filter." A standing grant on `gh issue comment` / `gh pr comment` lets a model post as the human, producing exactly the state the gate's own header warns about — an operator-posted claim comment that is invisible to the merge-boundary check, failing a legitimately-claimed PR. That's a repo-specific reason to narrow the grant to the read verbs actually used, independent of the destructive-command argument.

Also: both new `mutation-catalog.tsv` rows re-verified clean by this angle (valid `sed -E`, one unique matching line each, `bash -n` valid) — that now has three independent confirmations.

Nothing changes the ranking. `check-ignore` before the write is still the pre-merge blocker; the `(ws9)` shape above is the test that should land with it.

---

## Assistant text — `result` event 4 of 5

Final angle (shell pitfalls) is in — that's all 10. Three new items, plus a set of cleared concerns worth recording.

**New: a broken symlink at the *source* is silent.** `[ -f "$src" ]` at `lean-gate.sh:2026` follows symlinks, so an operator whose `.claude/settings.local.json` points into a dotfiles repo that isn't checked out gets nothing — no copy, no message — indistinguishable from "this consumer keeps no local settings." That's the exact near-silent shape #647 exists to remove, reintroduced on a new path. Note the asymmetry it creates: a dangling symlink at the *destination* is handled loudly and has its own case (ws7) and catalog row, while a dangling symlink at the *source* is folded into the documented no-op. ws8 covers only the live symlinked source. `[ -e "$src" ] || [ -L "$src" ]` would let the absent case stay silent while a broken link warns.

**The directory-symlink hole is now reproduced, not just reasoned.** With `$wt/.claude` symlinked outside the worktree, the seed prints `settings: copied .claude/settings.local.json into .../wt9` while the file lands at the link target. The success message names a path that does not contain the file — so the operator's evidence says the remedy worked. Reachable in exactly the deployment the ticket targets: where `.claude/` is ignored wholesale a fresh worktree has no `.claude` at all, which is when someone reaches for the symlink workaround.

**The `$MAIN_ROOT` guard's comment is wrong about what protects it.** This refines the earlier path-skew finding rather than repeating it: both BSD and GNU `cp` refuse a same-file copy (rc=1, source not truncated), so the guard was never what prevented self-copy — `[ -e "$dst" ]` at :2029 is, incidentally. The comment at :2018-2019 claims otherwise. That matters because the mutation catalog already treats the never-clobber condition as mutable: reorder or relax it and the real protection disappears while the comment still says it's covered.

Minor: `cp ... 2>/dev/null` discards the diagnostic, so EACCES, ENOSPC, EROFS and a vanished worktree all produce one identical causeless warn — against three named siblings in the same file that interpolate their captured error (`cmd_entry_sweep:2707`, `worktree_destroy:2137`, `worktree_inflight:2098`).

**Cleared, and worth knowing:** `shellcheck -e SC1091,SC2015,SC2181` is clean on both changed files *and* their `main` versions (zero new warnings); both pass `bash -n` under bash 3.2.57 with all eight `(ws)` cases green; and the `done <<EOF\n$paths\nEOF` heredoc was tested against a worktree name containing command substitution and backticks — it does not re-scan its expansion, nothing executed, and paths with spaces, brackets and globs are handled correctly. The injection surface a heredoc-fed loop over externally-derived paths would normally raise is genuinely not there.

One sharpening of the known `ws_wt` subshell bug: when a fixture collision makes `p61` a nonexistent path, **all three** of ws4's conjuncts go trivially true — `rc -eq 0`, the `! -e` negative, and `! grep 'settings:'` — because the seed returns at :2014 having printed nothing. So ws4 doesn't just red for the wrong reason; it goes green having tested nothing, and the only signal is a `FAIL:` line that never reaches the exit code.

That closes the review. The ranking is unchanged from what I gave you: `check-ignore` before the write is the pre-merge blocker, the `(ws9)` shape is the test that should land with it, and everything else is post-merge cleanup.

---

## Assistant text — `result` event 5 of 5

That's the same Angle D agent re-notifying — same task ID, same findings, all of which I relayed in my last message. Nothing new to add.

One small detail in the repeat worth a line, since it touches the secrets concern: `cp` preserves mode 0600, so the seeded copy doesn't widen file permissions on the operator's settings. It's still inside a tree the build session commits from, which is the actual exposure — but the copy itself isn't loosening access.

The review is complete and the ranking stands.
