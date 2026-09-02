# lean review verdict — #780

verdict=needs-work
run_id: review-780-2
session_id: f95f2377-a8be-4ca4-aa01-cedd0fe8c533
rounds: 2
pr: #784
reviewed_head: a87170383629a3857a87b9754e0a71db137632d9
reviewed_patch_id: 8b616dcf346d6c61109cf244bc7e8096fa2ca1e4
inherited_patch_id: 01bc205fd23b4da03d20c348b89491ce4b0e069e
inherited_from_verdict: 16329d57dc5365d9805cd6d56403adc94e743ce1
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 2, inheriting round 1's coverage of patch `01bc205fd23b` and reading the delta
`16329d57..HEAD` — one commit, `a8717038`, touching `CLAUDE.md` and `docs/testing.md` only. Round
1's two blockers are both addressed and I close both by measurement: the `Changelog:` trailer is
now the bare `none.` form on all four branch commits and renders nothing, and the false universal
("every scratch allocation in this repo uses the explicit-template form") is gone from both homes.
Round 1's two warnings and its one suggestion are closed too.

**But the narrowing replaced a false universal with a false specific, in the same two files.**
Both passages now say "33 shell files still call `mktemp -d -t` / `mktemp -t`". At this head that
number reproduces from exactly one command — `git grep -l 'mktemp -d -t' -- '*.sh'` — and that set
**includes the two suites the same sentence exempts**, whose only matches are the `#780` comments
this PR added. It also excludes the four files that call the `mktemp -t` spelling the claim names.
The real count of callers is **34**; and since the sentence's own parenthetical states that a bare
`mktemp -d` resolves the same way, the set of shell files a private `TMPDIR` does **not** isolate
is **68**. `CLAUDE.md` additionally dropped the bare-`mktemp -d` clause that `main` carried, so on
that form it is now less informative than before this PR. AC-7 stays unsatisfied.

Panel: `review-toolkit:scope-completeness-reviewer` (approve, no findings; one suppressed note at
confidence 70). No reviewer went dark, and no re-dispatch was needed. Routing selected one
subagent: the delta is two Markdown files outside `.claude/`, so the trivial-inert row applies —
`security-reviewer` not selected (no security surface in a pure-prose delta and no
`.claude/second-shift/review-context/security-reviewer.md` in the repo; the security dimension is
the lead pass's this round), and a11y plus design-fidelity not routed (no changed path matched
`stageParams.webComponentGlobs`, which the config does not declare, so the shipped default
`apps/web/**/*.{tsx,jsx}` applied; the spec declares no `## Design` section, so the run is
unarmed and `fidelity` is `not-applicable`).

## Strengths

- **The narrowing is the right shape and the right two edits.** Round 1's ask was "say that the
  two fixture families *joined* the explicit-template set, and that the rest of the tree has not",
  and that is precisely what both passages now do. The dangerous direction is gone: no reader can
  now come away believing a private `TMPDIR` isolates their lane. The operative advice in both
  files is correct and actionable regardless of the count defect below.
- **Round 1's blocker 2 is closed at the mechanism, not just at the wording.** The code commit was
  amended (`c3ea669e` to `91b33556`) to a bare `Changelog: none.` with the justification moved
  into unindented body prose above it. Verified by running `derive-release.sh`'s real
  `extract_trailers` and `render_bullet` awk programs over the branch's actual squash body
  (`git log --reverse --format=%B origin/main..HEAD`): output is empty, so nothing reaches
  `CHANGELOG.md`. The amend was message-only — `git diff c3ea669e 91b33556` is empty — so round
  1's reviewed content, and therefore this round's inheritance, is intact.
- **The scrub-glob caveat and the stale criteria count are both properly closed.** The new
  paragraph after the `find` command names the families the alternation misses and tells the
  reader to widen it before reading an empty result as "nothing to scrub" — round 1's warning. And
  `docs/testing.md:1834` now reads "fixes the criteria and the arm definitions (C-1 was retired in
  #780)" — round 1's suggestion, closed with the exact wording it proposed.
- **The PR body's net-diff line now reproduces from the command it cites.** "-398 lines (389
  insertions, 787 deletions)" is exactly `git diff origin/main...HEAD --shortstat` at this head,
  and "-679 excluding the spec and verdict-record commits" is exactly the same command with
  `':!docs/plans/'`. Round 1's second warning, closed.

## Critical (must fix before merge)

- **[Maintainability] `CLAUDE.md:78` and `docs/testing.md:194` (confidence: 92) — the replacement
  count is wrong, and its own set contradicts the sentence it appears in.**

  Both files now say: "33 shell files still call `mktemp -d -t` / `mktemp -t`". Measured at
  `a8717038`, three separate things are wrong with that:

  1. **It counts the two files it exempts.** `git grep -l 'mktemp -d -t' -- '*.sh'` returns
     exactly 33 — the quoted figure, and the only command at this head that produces it. Three of
     those 33 match on comment lines, not call sites, and two of the three are
     `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` (lines 70 and 161) and
     `plugins/dev-pipeline/skills/run-lean/orchestrate-lean-selftest.sh` (line 50) — the two
     suites the same sentence names as having *joined* the explicit-template set, matching only
     because **this PR added those `#780` comments**. The third is
     `tools/capability-parity-check.sh:120`. So the sentence reads "the rest of the tree has not:
     33 files", where 33 counts the two files that did.
  2. **It excludes four callers of the spelling it names.** The claim says "`mktemp -d -t` /
     `mktemp -t`", but the 33 is a count of the first spelling alone. Four files call only the
     second: `plugins/dev-pipeline/tools/operator-override.sh:336`,
     `plugins/dev-pipeline/tools/pipeline-doctor.sh:427`,
     `plugins/dev-pipeline/tools/preflight.sh:97`, `scripts/check-lean-chain.sh:534`. Counting
     non-comment matches of either spelling gives **34**.
  3. **Its own parenthetical doubles the true set, and `CLAUDE.md` lost that parenthetical
     entirely.** `docs/testing.md:195` states that a bare `mktemp -d` *is* `-t tmp` "so it
     resolves the same way" — which I confirmed empirically on this machine: under
     `TMPDIR=/tmp/mkt-probe/`, `mktemp -d` returned
     `/var/folders/.../T/tmp.bNiUvFUxwU` while the explicit template returned
     `/tmp/mkt-probe//exp.QLlU5n`. **34 further shell files** call bare `mktemp -d` (zero overlap
     with the `-t` set), so the set a private `TMPDIR` does not isolate is **68**, not 33.
     `CLAUDE.md`'s paragraph omits the parenthetical that `main` carried ("a bare `mktemp -d`
     *is* `-t tmp`, so there is no second behavior to fall back on"), so on the bare form
     `CLAUDE.md` is now **less** informative than before this PR while carrying a number that
     reads as the complete count.

  **The failure this causes.** A contributor whose killed suite is one of the 34 bare-`mktemp -d`
  callers — `cost-block-selftest.sh`, `doctor-selftest.sh`, `gh-bot-selftest.sh`,
  `claim-selftest.sh` and 30 others — reads `CLAUDE.md`, sees a 33-file set headed by
  `mutation-sweep.sh` and `install-topology-selftest.sh`, finds their suite in neither, and
  concludes their leftovers landed in their private `TMPDIR`. They did not: they are in
  `_CS_DARWIN_USER_TEMP_DIR` under the name `tmp.XXXXXXXX`, which no glob in `docs/testing.md`
  matches and which neither file now mentions. `docs/testing.md`'s new scrub caveat compounds it
  by telling the reader to "read the caller list above and add its names" — that list is the `-t`
  set, so following the instruction still misses half the residue.

  This is the same class as round 1's blocker, one level down, and it is a regression against
  `main` for that class of file. The remedy is one sentence in each home: quote the honest figure
  for the whole TMPDIR-ignoring set (68 shell files, or "most of the tree"), name all three forms
  (`mktemp -d -t`, `mktemp -t`, and bare `mktemp -d`), and restore the bare-form clause to
  `CLAUDE.md`. Dropping the number entirely would also close it — the qualitative claim carries
  the advice on its own.

## Warnings (should fix)

_None. Round 1's two warnings are both closed._

## Suggestions (consider)

- **[Maintainability] `docs/testing.md:181` (confidence: 80) — "**Some** scratch allocations use
  the explicit-template form" is a bolded hedge where a count would do.** The paragraph's job is
  to tell a reader which side of the line their suite is on; "some" answers nothing, and the
  section then spends four sentences reconstructing what the bold line could have stated. If the
  blocker above is fixed by quoting the real figures, this line can quote the complement and the
  reconstruction shortens.

## Plan Compliance

Implementation still matches the spec's scope boundary. The delta edits only the two documentation
homes AC-7 names; no `docs/plans/` record was touched (D-8, D-14), no guard, selftest case or
script was added (D-1, D-14), and no code changed at all this round. D-11 (trap before `WORK`) and
D-15 (`pwd -P`) both remain in place at this head, re-verified rather than inherited:
`lean-gate-selftest.sh:69` and `orchestrate-lean-selftest.sh:49` register `trap cleanup EXIT`
before their line-82 and line-59 `WORK` assignments, and `orchestrate-lean-selftest.sh:60` keeps
its `pwd -P` normalization. OR-1's resolution is unchanged and still flagged in the PR body.

The one gap remains inside AC-7, and it is the same passage as in round 1 — the docs follow the
deletion in structure and now in direction, but the specifics they assert are false at their own
head.

## CI at the reviewed head

Recorded, not treated as a finding. Run `33643417575`, `head_sha a8717038` — the reviewed head:

- `lint-and-selftests` — **pass** (4m08s). This is the full sweep; AC-4's "a full sweep exits 0"
  is cited from it rather than re-run, per the CI-citation discriminator (same command, same head).
- `mutation-sweep-pr` — **pass** (14s).
- `selftests (macos, bash 3.2)` — still in flight at the time of writing.
- `pr-gates` — **fail**, at step 6, "lean chain reconciliation". This is the structural
  pre-approve state: the branch's committed verdict record is round 1's `needs-work`, and
  `check-lean-chain.sh` refuses on it. Steps 3 and 4 — the frozen-files guard and the
  `Changelog:` trailer guard — both **pass**, so there is no policy-gate red on this branch and
  nothing in `pr-gates` is a correctness signal about the diff.

## Pre-existing gaps (not blocking this PR)

- `CLAUDE.md:115` and `docs/testing.md:685` still describe a "64-suite tree"; the tree discovers
  77 suites here. Stale before this PR, moved by one more by the deletion. Round 1 raised it and
  it is unchanged — still not this ticket's job.

## Suppressed (below confidence threshold)

- `scope-completeness-reviewer` (70) — AC-4's "a full sweep exits 0" clause was not independently
  re-measured by that reviewer at this head, and it grounded the clause on four directly affected
  suites plus the CI run cited in round 1's record. Its note reports two `orchestrate-lean-selftest.sh`
  failures locally that reproduce identically on `origin/main`. I did not carry this forward: a
  second lane (issue #783) was running a full sweep on this machine throughout this round, local
  suite runs contend across lanes, and `lint-and-selftests` is green at this exact head — which is
  the stronger evidence and the one AC-4 is scored on.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ❌ | 2 | 80-92 |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** No

**Reasoning:** The round-1 blockers are genuinely closed, but the AC-7 narrowing asserts a count
that is false at its own head and whose set includes the two files the same sentence exempts —
in `CLAUDE.md`, the file every session loads. One sentence in each home fixes it.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Re-measured at a8717038, not inherited: the spec's own grep (git grep -lE over the two name patterns, excluding docs/plans/) returns nothing, rc=1. All three files are deleted in the branch diff. |
| AC-2 | satisfied | grep -c 'reap-lean-fixtures' returns 0 for both tools/run-selftests.sh and tools/run-selftests-selftest.sh at this head. The entry block plus its header comment (-18 lines) and the fake-reaper case with its absent-tool control (-40 lines) are gone. |
| AC-3 | satisfied | Both producers allocate with the explicit-template form: lean-gate-selftest.sh:82 and orchestrate-lean-selftest.sh:59. D-11 holds in both — trap cleanup EXIT at lines 69 and 49 respectively, before the WORK assignments. D-15 holds: orchestrate-lean-selftest.sh:60 keeps its pwd -P normalization, and lean-gate-selftest.sh:74 gained the mirror of it. No stamping remains in either. |
| AC-4 | satisfied | grep -c 'fixture-stamp' returns 0 for both tools/selftest-cache-inputs.tsv and tools/mutation-pair-map.tsv. tools/check-sweep-bound-selftest.sh's comment cross-reference is reworded (the reap-lean-fixtures sentence deleted). "A full sweep exits 0" is cited from CI rather than re-run: lint-and-selftests pass 4m08s in run 33643417575 at head_sha a8717038, the reviewed head, running the same tools/run-selftests.sh sweep. |
| AC-5 | satisfied | tools/selftest-suite-timings.tsv gains a 10-line header block, prose only — no new column, no validator. Its factual claim re-verified at this head: tools/selftest-cache-inputs.tsv declares exactly 3 suites (lean-gate-selftest.sh, cost-block-selftest.sh, check-lean-chain-selftest.sh); the first and third carry rows in the timings table at 212s and 67s against its 9s threshold, so both are deferred; cost-block-selftest.sh carries no row and is treated as fast, leaving it the only cacheable suite a milestone-3 lane runs. |
| AC-6 | satisfied | git diff origin/main...HEAD --shortstat gives 389 insertions and 787 deletions, i.e. -398 across the branch, and -679 with ':!docs/plans/'. Negative on both readings, and the PR body now quotes both figures with the commands that produce them. |
| AC-7 | unsatisfied | Structurally complete and now correct in direction: the reaper paragraph is gone, the scrub command and its widening caveat are in, C-1 plus the sampler's fixture half plus the stagger rule are dropped with C-2 to C-4 retained, the record-void is noted at docs/testing.md:1885, CLAUDE.md's parallel paragraph is rewritten, and the stale "four criteria" count is fixed at docs/testing.md:1834. But the replacement asserts in both homes that 33 shell files still call the non-honoring mktemp forms, and that is false at its own head three ways: the 33 reproduces only from git grep -l over the -d -t spelling alone, whose set includes the two suites the same sentence exempts (matching only on comments this PR added) plus one more comment-only file; it omits the four files calling the mktemp -t spelling the claim also names, so the caller count is 34; and the sentence's own parenthetical about bare mktemp -d, which I confirmed empirically, brings the non-isolated set to 68. CLAUDE.md additionally dropped the bare-form clause main carried. See the Critical finding. |
