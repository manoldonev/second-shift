# lean review verdict — #442

verdict=approve
run_id: review-442-1
session_id: 4f7cccc0-f054-496b-a3d0-cd1888ebfaf4
rounds: 1
pr: #467
reviewed_head: bce75409cde2540fa8cd23ddd896d47dbb9e50d7
reviewed_patch_id: 3770090cc3e5dcabfe43366e595acf150da40834
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1. Full branch range (`6a6922c..HEAD`) — nothing verifiable to inherit.

**The patch is approved. PR #467 as an envelope cannot be merged**, for a reason that is
not in the diff and that no code change fixes — see "Merge-blocking, not a code finding"
below. The two claims are separable because the boundary keys the record on
`reviewed_patch_id`, not on the PR number: this record survives onto a fresh PR cut from
the same branch with the same commits.

## Verdict

`approve` — every AC-1..AC-12 is satisfied, and no reviewer found a defect in the change.

## Merge-blocking, not a code finding

`pr-gates` is red with **two** violations, only one of which this record clears:

- `no committed verdict record` — the expected pre-handoff shape. This commit clears it.
- `no bot-authored 'lean-claimed' comment on #442 at or before PR-open (2026-08-09T22:31:54Z)` —
  **not** clearable on this PR. The issue carries zero comments, and its label timeline shows
  the claim's label swap at 10:54:22Z was reverted at 21:41:13Z (`in-progress` →
  `ready-for-dev`); the run then re-committed at 21:50–21:52Z and opened the PR at 22:31:54Z
  without re-running `claim`. The progress file's last line is `milestone-3 | attempt | test
  failed (rc=127)` at 13:10:04Z, so nothing after that was recorded through the gate.

A PR's `created_at` is immutable and the marker window is anchored to it by design, so a
comment posted now can never fall inside it. The same absence also makes check 4 (P10
authorship) uncheckable — the bot claim comment is the only build-side identity CI can see.
The remedy is a build-session action, not a code fix: re-run `bash G claim 442` (the label is
back at `ready-for-dev`, so it will run clean), then close #467 and open a fresh PR from this
same branch. This record carries over unchanged as long as the branch's own diff does not move.

The three lanes that assess the code are all green: `lint-and-selftests` (3m45s),
`selftests (macos, bash 3.2)` (4m54s), `mutation-sweep-pr` (3m20s).

## Independent verification performed this round

- **Both changed suites re-run locally**, `env -u CLAUDE_CODE_SESSION_ID`: `lean-gate-selftest.sh`
  all green (263 PASS, including all 19 `(wt*)` cases), `branch-prefix-selftest.sh` all green.
- **The mutation-catalog row's kill claim, checked rather than taken on faith.** Applied
  `lean-gate-teardown-pushed-direction` verbatim from `tools/mutation-catalog.tsv`
  (`refs/remotes/origin/$br..HEAD` → `HEAD..refs/remotes/origin/$br`), confirmed the mutant still
  parses (`bash -n`), and ran the paired suite: killed by `(wt5)` *and* `(wt6)` independently,
  exactly as the commit body claims. `--mode pr` returning rc=0 is not by itself evidence a
  catalog row is live, which is why this was probed directly.
- **The one production configuration no case covers**, raised at confidence 70 by the panel:
  checklist step 9 runs `bash G teardown <issue>` from *inside* the worktree being destroyed.
  Probed on a scratch repo — `git worktree remove` from a cwd inside the target returns 0, the
  entry is unregistered and the directory is gone. `worktree_destroy` runs the removal as
  `git -C "$MAIN_ROOT" worktree remove`, so the caller's cwd is not an input, and `cmd_teardown`
  is the last thing the process does. **Correct, but untested** — see Suggestions.
- `shellcheck -e SC1091,SC2015,SC2181` clean over all four changed shell files.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `teardown` in the subcommand enum and both usage strings; dispatched at `lean-gate.sh:2995`; header block at lines 98–104 sits inside `sed -n '2,139p'`, and case `(w)` pins that range on both ends. |
| AC-2 | satisfied | `lean_worktree_for_branch` matches `--porcelain` output on `$LEAN_BRANCH`, never a path. `(wt1)` removes; `(wt3)` re-runs to a reported no-op at rc=0. |
| AC-3 | satisfied | `(wt4)` unclean → kept, file named, manual command printed, rc=0. `(wt5)` unpushed → kept. `(wt6)` merely behind origin → **removed**. `(wt17)` the same preconditions decline a sweep candidate. |
| AC-4 | satisfied | `(wt1)` asserts the branch still resolves after removal; no `git branch -d`/`-D` anywhere in the diff. |
| AC-5 | satisfied | `cmd_all` contains no teardown call and `cmd_teardown`/`worktree_destroy` have exactly one caller each outside the sweep; `(wt8)` asserts `all` removes nothing. |
| AC-6 | satisfied | `(wt7)` uses a *locked* worktree — clean and fully pushed, and git still declines — so git's own message reaches the shared keep path at rc=0. The one refusal the preconditions cannot manufacture. |
| AC-7 | satisfied | `(wt9)` MERGED under github, `(wt18)` MERGED under jira. The predicate is `n_open -gt 0`, so closed-unmerged takes the identical path. No `git branch --merged` anywhere. |
| AC-8 | satisfied | All five keeps, each with a printed reason: `(wt10)` open PR, `(wt11)` no PR at all, `(wt16)` main checkout, `(wt15)` caller's own worktree (with a CLOSED PR, so it qualified on every other test), `(wt14)` non-lane branch, asserted by the *absence* of a lookup diagnostic naming it. |
| AC-9 | satisfied | `(wt12)` branches on exit status before reading output and names the branch. `(wt13)` pins entry's status and its attestation row. Structurally: `cmd_entry_sweep` has no non-zero return, and `cmd_entry` calls it last then `return 0`. |
| AC-10 | satisfied | `(wt18)` is the right shape — it pairs "claim removed nothing" with "the same config's `entry` did", so it probes `claim` rather than the fixture. `cmd_entry_sweep` has exactly one call site. |
| AC-11 | satisfied | Step 9 names `bash G teardown <issue>`; step 1 states `entry` also sweeps. `run-lean/SKILL.md` is 43 lines against the 60-line cap. |
| AC-12 | satisfied | Step 3 no longer presents the build worktree as durable; step 4's exit-2 remedy names any checkout of the build host's clone. Exercised this round — `bash G delta 442` resolved the entry attestation from the build worktree. |

Out of scope held: PR-less worktrees are kept and say so out loud (`(wt11)`), rather than
aged out.

## Findings

No blockers in the diff.

### Warnings

- **[Performance] `lean-gate.sh:1099` (confidence 82) — the sweep is N+1 on `gh`.**
  One `gh pr list --head "$br"` per candidate, where one `gh pr list --state all --json
  number,state,headRefName` and a local match would answer for all of them. This runs at the top
  of every `entry`, i.e. at the start of every run. Not hypothetical at this scale: the
  maintainer's own checkout currently registers ~13 branch-carrying lane worktrees, so that is
  ~13 sequential round-trips plus ~13 `git fetch` calls added to run-start until the backlog is
  swept. Self-limiting (the sweep removes its own workload) and correctness is unaffected.
- **[Performance] `lean-gate.sh:1039` (confidence 80) — no bound on the sweep's network calls.**
  Neither `git fetch` nor `gh pr list` is timeout-wrapped, and `cmd_entry` made **no** network
  calls at all before this change — run-start is newly network-dependent. AC-9 guarantees the
  sweep cannot change `entry`'s exit *status*; it says nothing about it not returning. There is
  no timeout idiom elsewhere in the file to mirror, so this is a new-surface note rather than an
  inconsistency.

### Suggestions

- **[Test coverage] The real step-9 configuration is unexercised.** Every `teardown` case invokes
  the gate with cwd at `$WTREE` (the main checkout); none from inside the worktree being removed,
  which is what the lane actually does. I probed it and it works, so this guards a behavior that
  is currently correct — which is exactly when it is cheap to pin and later valuable. One case
  running `wgate "$p" teardown <n>` would close it.
- **[Test coverage] Closed-unmerged removal is asserted only through the merged path.** AC-7 names
  both; `(wt9)`/`(wt18)` cover MERGED. The implementation cannot distinguish them (`n_open -gt 0`
  is the whole predicate), so this is a completeness nit, not a gap in behavior.
- **[Maintainability] `lean-gate.sh:2995` (confidence 85)** — `teardown) cmd_teardown ;;` is one
  character past the dispatch block's column alignment. Cosmetic.

### Suppressed (below threshold, recorded for visibility)

- `branch-prefix.sh:56,66` (40) — config `keyPattern` interpolated as an ERE into `grep -qiE`;
  trusted local config, and only relocated by this diff.
- `lean-gate.sh` `worktree_destroy` (35) — branch name as a fetch refspec; leading-dash injection
  precluded by git ref-name rules and by the `bp_is_work_branch` shape gate upstream.
- `lean-gate.sh` `worktree_keep` (30) — raw git output echoed to stderr on the decline path.
- `lean-gate.sh:1031` (55) — the "status could not be read" branch has no direct case; fails safe.
- `docs/plans/second-shift-442-lean.md:5` (65) — the ledger it cites is host-local and gitignored,
  so the supersession cannot be checked from the diff. The in-code rationale at `lean-gate.sh`
  1036–1045 stands on its own, which is why this is not a scope gap.

## Strengths

- **The pushed-ness precondition is the ticket's most consequential decision, and it goes against
  the issue.** `origin/<branch>..HEAD` rather than `HEAD = origin/<branch>` — strict equality
  would refuse exactly the case this exists for, because the review session's verdict record
  leaves the build worktree legitimately behind. It is reasoned out in the comment, pinned by
  `(wt6)`, *and* carried as a mutation-catalog row so a later edit reversing it gets caught. Three
  independent defenses on the one line where being wrong destroys work.
- **`bp_is_work_branch` is built on the real parse, not a prefix string test.** The obvious
  `case "$ref" in "$prefix"*)` would have accepted `claude/second-shift-notes` and every
  `dependabot/...` path under a matching identifier — and since this predicate *is* the sweep's
  blast radius, the shortcut would have been a deletion bug. `bp_key_re` keeps one definition
  answering both the forward and inverse questions, and `(h1)`–`(h5)` pin exactly the cases the
  shortcut gets wrong.
- **A failed `gh` lookup is treated as an absence of information, not as "no PR".** Branching on
  exit status before touching output, with a stub whose *missing* fixture exits non-zero so the
  two cases are actually distinguishable — the fixture design is what makes `(wt12)` real rather
  than decorative.
- **The suite reaches for cases the implementation cannot fake.** `(wt7)` locks a worktree to
  produce a git-side refusal the preconditions can't manufacture; `(wt18)` pairs the negative with
  a positive on the same config so it probes `claim` rather than the fixture; `(wt14)` asserts on
  the *absence* of a diagnostic. The `pwd -P` note is the kind of thing that silently turns three
  guards into no-ops on macOS, caught before it did.
