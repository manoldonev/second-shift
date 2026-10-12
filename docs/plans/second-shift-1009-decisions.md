# #1009 — a PR's edits to its own review policy are surfaced in the scheduler's review input

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the policy-edit surface lands | A new section in `review_input` (`plugins/dev-pipeline/skills/run/run.sh`) after the CI-config one, built from `--name-status` split on tabs, listing A/M/D/R rows and both sides of a rename (name-only hides a rename out of the directory); `(none)` when empty. `review_prompt` gets a trace instruction for it and the `## Scheduler input (...)` parenthetical names it; `plugins/dev-pipeline/skills/review/SKILL.md` step 4 mirrors it in prose. Weighed: widening the `:577` grep (a policy file then reads as a CI edit and inherits no trace instruction); reusing `expectations_changed` (keeps only M rows with removed lines, and the threat is additive: #937 was an A) | user-answered | intent |
| D-2 | What the review does with a listed policy edit it cannot trace | Trace each listed file to an acceptance criterion of the ticket or a row of the decision record; an untraced one is a `[blocker]` requiring the citation, wording mirrored from the expectations rule. The edit itself is never blocked, only merging without naming who decided it. Weighed: `[note]` only | user-answered | intent |
| D-3 | Which head-side paths the section lists | `.claude/second-shift.config.json`, `.claude/second-shift/**`, and `.claude/agents/<name>.md` for each bare name under `reviewers.add[]` in the config the scheduler read (a qualified name is a plugin pack, not an in-repo file). Weighed: the ticket's two paths only | user-answered | intent |
| D-4 | Scope item 2 (base-copy loading in review-toolkit) and the standalone `/review-lead` gap | Both parked under OR-1, deferred to one follow-up ticket; owner: the operator; to be filed before item 2 is scheduled. Reasons: ten self-loading agent prompts plus reviewer-baseline and three review-lead sites change; a reviewer-prompt change needs a replay before shipping; a first-adoption PR has no base copy (`git show` exits 128); the seats hold the base as a branch name, which resolves to the base tip, not the merge-base; standalone review-lead builds no scheduler input, so a hand PR gets no flag from item 1 | deferred | open |
| D-5 | Whether the exported config path survives into the spawned review session | Yes, and the scrub applies to lane commands alone. run: `grep -n 'export SECOND_SHIFT_CONFIG' plugins/dev-pipeline/skills/run/run.sh` → `193:[ -n "$CONFIG" ] && export SECOND_SHIFT_CONFIG="$CONFIG"`; run: `sed -n 1094,1116p plugins/dev-pipeline/skills/run/run.sh \| grep -c SCRUB_ENV` → 0. So in the lane the checks, lanes and `reviewers.*` come from the main checkout's config; the standalone path reads the head's, and scope-completeness-reviewer reads a cwd-relative config with no override on both paths | codebase-derived | fact |
| D-6 | Whether the CI-config section already lists a policy path | No. run: `printf '%s\n' .claude/second-shift.config.json .claude/second-shift/review-context.md .claude/second-shift/review-context/security-reviewer.md .claude/agents/orders-reviewer.md \| grep -E '<the run.sh:577 pattern, verbatim>'` → (no match) | codebase-derived | fact |
| D-7 | Who loads the policy files from the head | run: `grep -rl 'review-context' plugins/review-toolkit/agents \| wc -l` → 10 (of 20 agents), plus `reviewer-baseline/SKILL.md:10` and `review-lead/lead-pass-checklist.md:238`; standalone review-lead derives its worktree with `git rev-parse --show-toplevel` (`review-lead/SKILL.md:42`) | codebase-derived | fact |
| D-8 | Shape of the `run-selftest.sh` case | An I10-style case: a fake build step edits the policy paths and force-adds them, `rsec` reads the new section, and the review prompt is grepped for the trace line. The force-add is load-bearing: the fixture gitignores `.claude/` and `push()` stages with `git add -A`, so an unforced edit produces no diff and the case would pass without the change. run: `sed -n 164p plugins/dev-pipeline/skills/run/run-selftest.sh` → `printf '%s\n' ".claude/" > "$d/main/.gitignore"` | codebase-derived | fact |
| D-9 | Whether consumers commit the config file | Yes; only the per-engineer `.local.json` is gitignored, and this dogfood repo is the exception. run: `grep -n 'committed' plugins/second-shift/skills/onboard/SKILL.md \| head -1` → `115: ... the team's tracker.branchPrefix, committed`; run: `git ls-files .claude/second-shift.config.json` → (empty, here) | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Base-copy loading of the policy files in review-toolkit, and a policy-edit flag on the standalone `/review-lead` path | reversible-default-and-flag |

The default is "not in this PR", stated in the PR body. Reversing it is a follow-up ticket that adds prose to the reviewer prompts and review-lead; nothing this PR writes forecloses it, and the flag it adds stays useful either way.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The new section in `$STATE/review-input-<attempt>.md`, its rows and its `(none)` empty state | decided (D-1) |
| S-2 | The review prompt's trace instruction and the `## Scheduler input (...)` heading parenthetical | decided (D-1) |
| S-3 | The verdict text the human reads for an untraced policy edit | decided (D-2) |
| S-4 | The manual `/dev-pipeline:review` skill's step 4 prose | decided (D-1) |
| S-5 | Which files the section names, including a renamed, deleted or added one | decided (D-3) |
| S-6 | The reviewer agents' head-copy self-load, in the lane and standalone | out-of-scope — parked under OR-1 (D-4) for the follow-up |
| S-7 | A hand-authored PR reviewed by standalone `/review-lead` | out-of-scope — standalone builds no scheduler input; parked under OR-1 (D-4) |
| S-8 | A `.yml` or `package.json` under `.claude/second-shift/` listed in both the CI-config and the new section | out-of-scope — a double listing costs a glance and both sections are advisory |
| S-9 | The `run-selftest.sh` case's pass/fail lines | decided (D-8) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design frames

Design: none — `design.provider` is unset and this change renders nothing.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: policy-read-provenance opus 6/6 · matcher-edge-cases fable 4/6 · flag-reader-and-noise opus 5/6 · base-copy-feasibility fable 6/6 · premortem fable 4/6
Tally: rows added 1 · snapshot claims overturned 1 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | policy-read-provenance | `SECOND_SHIFT_CONFIG` reaches both spawned sessions pointing at the main checkout's config; the scrub is `lane()`'s alone, and main's `.claude` dir is handed over with `--add-dir` (probe with a fake claude) | already-had | D-5 |
| F-2 | policy-read-provenance | In the lane and standalone, the policy files resolve at the PR head; nothing reads them from base | already-had | D-7 |
| F-3 | policy-read-provenance | The config read differs per actor: review-lead honors the env override, doc-updater and the baseline one-liner fall back cwd-relative, scope-completeness-reviewer reads cwd-relative with no override | overturned (snapshot: "a head edit to the config file bites standalone review-lead only") | D-5 amended |
| F-4 | policy-read-provenance | `check-review-context.sh` defaults its root to the main checkout from a linked worktree, so in the lane the lint checks main's files while reviewers load the head's | not material | outside the ticket; reported to the operator as adjacent |
| F-5 | policy-read-provenance | The `:577` section lists none of the policy paths | already-had | D-6 |
| F-6 | policy-read-provenance | In this repo the config is gitignored and only `review-context.md` is head-editable; whether consumers commit the config was open | new | became D-9 |
| F-7 | matcher-edge-cases | A rename out of `.claude/second-shift/` is invisible to `--name-only`; only `--name-status` field 2 carries the old path | new | folded into D-1 (name-status, both rename sides) |
| F-8 | matcher-edge-cases | Only a `.yml` or `package.json` under the directory is caught today, by suffix, so a sibling section lists those twice | not material | S-8 |
| F-9 | matcher-edge-cases | The selftest fixture gitignores `.claude/` and the fake build stages with `git add -A`, so the case needs `git add -f` | new | folded into D-8 |
| F-10 | matcher-edge-cases | The `:571` awk splits on whitespace and drops a renamed test with a space in its old path; `expectations_changed` uses a tab split | not material | outside the ticket; D-1 builds on the tab split |
| F-11 | flag-reader-and-noise | The review prompt instructs the reviewer on one section only; widening the grep alone lists files nobody is told to trace | already-had | D-1 |
| F-12 | flag-reader-and-noise | The CI-config pattern matches none of the five policy paths | already-had | D-6 |
| F-13 | flag-reader-and-noise | `expectations_changed` cannot be reused: it keeps only M rows with removed lines, and #937 was an A | new | folded into D-1 |
| F-14 | flag-reader-and-noise | Policy edits are rare (2 of 558 commits since July); #949's edit was traceable to its record's D-13 and scored honored; #937 was a hand PR that `review_input` never saw | new | informs D-2 and D-4 |
| F-15 | flag-reader-and-noise | Severity of an untraced entry is the open call; a `[blocker]` until cited enforces the build prompt's existing new-row rule | already-had | D-2 |
| F-16 | base-copy-feasibility | The seats hold the base as a branch name inside the range string; `git show <name>:` resolves to the base tip, not the merge-base the diff is cut at | new | folded into D-4's reasons |
| F-17 | base-copy-feasibility | A first-adoption PR has no base copy; `git show` exits 128 | already-had | D-4 |
| F-18 | base-copy-feasibility | Stacked, shallow and fork checkouts resolve a base read differently; a fork-style checkout with no `origin` fails the resolver chain | new | folded into D-4's reasons |
| F-19 | base-copy-feasibility | The ticket's unverified item resolves: the exported path reaches the spawned session | already-had | D-5 |
| F-20 | base-copy-feasibility | Touch count for item 2: ten agent prompts, reviewer-baseline, three review-lead sites, three working-tree scripts; no selftest guards the self-load prose | new | folded into D-4's reasons |
| F-21 | base-copy-feasibility | Deferring item 2 leaves a hand PR reviewed by standalone `/review-lead` with no flag, and this repo's own context declares hand PRs normal | new | the standalone gap, added to D-4's options |
| F-22 | premortem | A widened match with no prompt line lands as an untraced filename; the I10-style grep passes without any instruction | already-had | D-1 |
| F-23 | premortem | The review session's cwd is the head worktree, so relative policy reads and repo-local `reviewers.add[]` agents resolve at the head in the lane too | new | D-3's third path |
| F-24 | premortem | The trace is satisfiable by the build itself through a `user-delegated` row, which the review scores departed | new | folded into D-2: the citation lands in the record the human reads |
| F-25 | premortem | Same trap as F-9: the fixture's gitignore plus `git add -A` yields an empty diff | new | D-8, with F-9 |

### Snapshot

    # #1009 snapshot — the register as explore-first intake would have gone in with
    
    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Where the surface lands in the review input | Sibling section after the CI-config one, listing head-side edits to `.claude/second-shift.config.json` and `.claude/second-shift/**`, `(none)` when empty; the review prompt's `## Scheduler input (...)` parenthetical and the manual review's step 4 prose mirror it. Weighed: widen the `:577` grep (a policy file then reads as a CI edit and inherits no trace instruction) |
    | D-2 | What the review does with an untraced policy edit | Trace each listed file to the ticket or a record row, as the expectations section does (`run.sh:629`); an untraced one is a `[blocker]` requiring the citation. Weighed: `[note]` only — flag, never block |
    | D-3 | Which paths count as review policy | The ticket's two: the config file and `.claude/second-shift/**`. Weighed: also `.claude/agents/**` (a repo-local reviewer from `reviewers.add[]` edited by the PR it reviews) |
    | D-4 | Scope item 2, base-copy loading in review-toolkit | Deferred to a follow-up ticket with the reason: ten self-loading agents plus reviewer-baseline, review-lead's maturity section and its config read; a prompt change needs a replay before shipping; a PR that creates the file (the #937 case) has no base copy, so a fallback rule is itself a policy decision |
    | D-5 | The exported config path survives into the spawned review session | Yes: exported at `run.sh:193`; `spawn()` runs `env` with `WATCH_UNSET` only, and `SCRUB_ENV` applies to `lane()` alone. In the lane the scheduler's checks, lanes and `reviewers.*` come from the main checkout's config; a head edit to the config file bites standalone review-lead only |
    | D-6 | The scheduler's config section misses the policy paths | `run.sh:577` pattern against the four candidate paths → no match |
    | D-7 | Self-loading reviewers | 10 of 20 review-toolkit agents, reviewer-baseline and the lead-pass checklist load `review-context` from the repo under review, the head |
    | D-8 | Selftest shape | I10 cases: a fake build (`build-skip-test`, `build-polyglot`) edits files, `rsec` reads the section; a new case edits the two policy paths and asserts both are listed and the section reaches the review prompt |
    
    Surfaces: the review-input section and its `(none)` empty state; the review prompt's heading parenthetical and trace instruction; the manual review skill's step 4 prose; the verdict text the human reads; the reviewer agents' head-copy self-load (D-4); the run-selftest case.
    Checks: the configured test lane runs the full selftest sweep, which discovers `run-selftest.sh` by glob — empty form.
    Open regions: scope item 2 (D-4).
    Dup-scan: 0 candidates (corpus 0).
    Design: none — provider unset; this change renders nothing.
