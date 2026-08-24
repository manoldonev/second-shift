# lean review verdict — #647

verdict=needs-work
run_id: review-647-1
session_id: 9ba1afaa-c36d-4f71-ab8a-d68d405654d4
rounds: 1
pr: #657
reviewed_head: f8f7c142919507a58acbc268596c1127b4fa1ae0
reviewed_patch_id: 0be43fad810014af9b70610de21654dd8b507ab0
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 1 covers the whole branch diff (`b657907..HEAD`, 5 files / +287). The mechanism is
well-chosen and the eight `(ws)` cases are unusually strong — each pins a distinct failure the
others pass through, and the PR's own probe table shows they are live rather than decorative.
Both selftest lanes are green in CI (ubuntu 4m27s, macOS bash-3.2 6m23s), so AC-5 has evidence on
both platforms; `pr-gates` is red only on the absent verdict record this review writes.

Two blockers, both about what the change *deposits* rather than how it is tested.

The first is the one the suite structurally cannot see. `seed_lane_worktree_settings` writes an
**untracked** file into a tree whose cleanliness `lean-gate.sh` itself treats as a load-bearing
predicate, and it does so with no assertion that the destination is git-ignored. Every fixture in
the suite writes `.claude/` into the fixture repo's `.gitignore` (`lean-gate-selftest.sh:137` and
~20 siblings), which models the operator's **personal global** ignore rule as a repo rule. The
production repo does not have that rule: `git check-ignore -v .claude/settings.local.json` resolves
through `/Users/mdonev/.config/git/ignore`, not through this repo's `.gitignore`. So the suite is
green on a premise neither this repo nor any consumer repo satisfies.

The second is a posture the PR argues against in its own "What is deliberately NOT here" section
and then commits: a standing, project-scope, publicly-cloned `Bash(gh:*)` grant.

## Strengths

- **`(ws2)`, `(ws7)` and `(ws8)` are the three cases most implementations would omit**, and each is
  the only killer of a real mutant: inode independence (not mere presence + `cmp`), a *dangling*
  symlink destination that `[ -e ]` alone reads as absent, and a symlinked *source* that `cp -P`
  would have propagated. The probe table's "`(ws1)` stayed green" note under the `ln -s` mutant is
  exactly the right thing to report — it shows the weaker assertion would have survived.
- **`ws_wt()` checks its own fixture registration** rather than assuming it, so a future worktree-
  number collision fails at the setup line instead of passing vacuously on a path that does not
  exist. That is the class of vacuous-green this repo has been bitten by before.
- **`D-7` was probed rather than assumed.** "A remedy that copies a file the harness ignores reads
  exactly as green as a working one" is the correct thing to have been worried about, and checking
  the trust-root question before relying on it is the difference between a fix and a placebo.
- **The ordering residual is named in the PR, the spec and the code comment** instead of being left
  for review to find.

## Blockers

### B1 — the seed writes an unignored untracked file into the tree whose cleanliness `worktree_inflight()` reads

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh:2020-2044` (`seed_lane_worktree_settings`)

`.claude/settings.local.json` is ignored **only** by the operator's global ignore file. This repo's
`.gitignore` does not list it, and a consumer repo receiving the shipped gate has no reason to.
Where no ignore rule covers it, the copy makes the lane worktree permanently unclean, and
`worktree_inflight()` (`lean-gate.sh:2093-2101`) — the single predicate that both `cmd_entry_sweep`
and the scheduler's `#531 D-3` boundary consume — answers `8`, *"its tree is not clean"*, on a file
the gate itself just wrote.

Probed, in an isolated fixture repo with no ignore rule for the path:

```
=== worktree BEFORE seed ===
(nothing above == clean)
=== worktree AFTER seed ===
?? .claude/settings.local.json
=== what worktree_inflight() would answer ===
rc=8  INFLIGHT_REASON='its tree is not clean'  DETAIL: ?? .claude/settings.local.json
=== and with a repo .gitignore covering it (the fixture's premise) ===
(seeded file no longer listed)
```

The last line is the point: the fixture's `.gitignore` is what makes all eight `(ws)` cases blind
to this. Consequences, in order:

1. **The sweep stops reaping.** `worktree_destroy` → `worktree_inflight` → `8` → `worktree_keep`.
   Entry *N* seeds the file; entry *N+1*'s sweep sees a dirty tree and declines to remove the
   worktree, forever. That is precisely the stray-worktree accumulation `#530` and the sweep exist
   to prevent, now self-inflicted by the gate.
2. **The scheduler reads a false in-flight.** The same predicate tells `#531 D-3` that a finished
   build session "still carries work", on a tree whose only content is a settings file.
3. **Secondary:** an untracked machine-local settings file — which may carry an `env` block — sits
   in a worktree an autonomous session commits and pushes from, in a public repo.

This repo already treats this exact class as gate-worthy, in this same file: `lean-gate.sh:3952`
runs `git check-ignore -q "$RENDER_OUT_REL"` **before** writing render bytes and fails milestone 3
naming the exact `.gitignore` line to add — and PNG bytes are strictly less sensitive than an
allowlist. `.gitignore`'s own `.claude/worktrees/` paragraph documents the same failure mode
("an untracked entry here still makes `git status --porcelain` non-empty, which mis-records the
pre-flight attestation … Surfaced by the #1 dogfooding retro").

**Remedy** (must stay advisory — `D-5` is right): before copying, `git -C "$wt" check-ignore -q
".claude/$rel"`; on a miss, skip the copy and `warn` with the `.gitignore` line to add, mirroring
`lean-gate.sh:3953`. Add the corresponding line to this repo's `.gitignore` so the dogfood lane
takes the copy path rather than the warn path. And a `(ws)` case whose fixture repo does **not**
carry `.claude/` in `.gitignore` — without it, the suite still cannot fail on this.

### B2 — a tracked, project-scope `Bash(gh:*)` is the standing grant this PR's own reasoning rejects

`.claude/settings.json:6`

The new `permissions.allow` block is committed, so it applies to every clone of a public repo and
to every contributor session in it — not only to the lane. `Bash(gh:*)` matches far more than the
lane's reads: `gh pr merge`, `gh api -X DELETE`, `gh secret set`. Two specific problems:

- The PR's "What is deliberately not here" argues, correctly, that making `bypassPermissions` the
  lane default "trades a random failure for a standing grant on every spawn, and that posture
  decision is not this slice's." A committed `gh:*` is the same trade at a slightly smaller
  blast radius, made in the same slice. The `_comment` justifies the *ordering* problem being
  solved; it does not justify the *width* of the grant or its move from user scope to project
  scope.
- It removes the confirmation prompt that stands behind the merge-authorization rule this
  repository's lane depends on. This repo also ingests attacker-influenceable text (issue bodies,
  fork PR diffs) into agent context, so the pre-approved surface is not hypothetical.

AC-4 as written names `gh`, so I am not scoring AC-4 unsatisfied — this is a blocker on
independent grounds. **Remedy:** narrow to the subcommands the lane actually needs
(`Bash(gh pr view:*)`, `Bash(gh pr list:*)`, `Bash(gh issue view:*)`, `Bash(gh pr comment:*)`,
`Bash(gh api:*)` if a read form is expressible), keeping the `_comment` and its delete-when
condition. If the operator wants the wide form, it belongs in the ungitignored user-scope file,
not in a tracked one.

## Warnings

### W1 — AC-4's efficacy is a proxy no case verifies, and the observed invocation form is compound

The three allows are asserted to be "the three allows the dogfood lane needs", but nothing checks
that they match the command strings the lane actually issues. The #647 build session's own audit
ledger records:

```
export RUN_ID="lean-647-$(date -u +%Y%m%dT%H%M%SZ)" && echo "RUN_ID=$RUN_ID" && bash plugins/dev-pipeline/skills/build-lean/lean-gate.sh entry 647 2>&1 | tail -40; echo "rc=$?"
export RUN_ID="lean-647-20260823T215541Z" && bash plugins/dev-pipeline/skills/build-lean/lean-gate.sh claim 647 2>&1 | ctx-wire run --agent claude tail -20
```

The gate segment matches the allow; `export`, `tail`, `echo` and the `ctx-wire run` wrapper in the
same compound command do not. So the tracked block may not, on its own, have prevented the
2026-08-22 shape it is written to cover for the first round. Not a blocker — AC-4 is explicitly a
*proxy* and the block is explicitly interim — but the residual section reads as if AC-4 closes the
first-round case, and on this evidence it closes part of it.

### W2 — the `wt == MAIN_ROOT` guard is redundant with never-clobber, and untested

`lean-gate.sh:2026`. If the operator has the lane branch checked out in the main checkout, `dst`
*is* `src`, so `[ -e "$dst" ]` fires first and prints "already present". The guard is therefore
belt-and-braces rather than load-bearing, and `git worktree list`'s recorded path is not guaranteed
byte-equal to `pwd`-resolved `MAIN_ROOT` on a symlinked prefix — where they differ, the guard
silently does nothing and never-clobber carries it anyway. No change required; noting it so a
future reader does not mistake it for the mechanism that makes the self-copy safe.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `(ws1)` content-identical copy with the pre-condition (`ws_pre`) asserted, `(ws4)` the silent no-op with the *absence* of a `settings:` line as the assertion |
| AC-2 | satisfied | `(ws2)` regular file + write-independence from the origin; `(ws8)` symlinked source dereferenced. The `ln -s` mutant reds both and leaves `(ws1)` green |
| AC-3 | satisfied | `(ws3)` re-entry preserves the in-worktree mutation and prints "is already present"; `(ws6)` and `(ws7)` extend it to the tracked-file and dangling-symlink shapes |
| AC-4 | satisfied | the three allows plus a top-level `_comment` naming #647 land in the tracked file; `jq empty` passes in CI. Efficacy is a separate matter — see W1; grant width — see B2 |
| AC-5 | satisfied | CI, this head: `lint-and-selftests` pass (4m27s) and `selftests (macos, bash 3.2)` pass (6m23s), both running the recipe AC-5 names. Not re-run locally — the CI evidence is the same command on two platforms |
| AC-6 | satisfied | implementation commit carries `Changelog:` with a `Migration: none — consumers gain the behavior with no action` line |

Every AC is satisfied; the two blockers are defects the ACs do not reach. That is the expected
shape when the oracles are written from the same mental model as the implementation — B1 is
exactly a case where the fixture and the feature share a premise the production repo does not.

## Reviewer panel

Six reviewers, none dark: security (2 major, conf 82/85), performance, maintainability,
complexity, test-coverage, scope-completeness — the last five returned no findings above
threshold. `a11y` + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`). Design fidelity: `not-applicable` —
the spec arms no `## Design` section and the repo declares no `design.provider`.

B1 and B2 were reached independently by the security reviewer and by hand-derivation from the
`worktree_inflight` call graph; B1's mechanism was confirmed by probe rather than by reading, and
W1 by reading the build session's own audit ledger rather than the PR's account of it.

**Verdict: needs-work** — 2 blockers, 2 warnings.
