# lean review verdict — #647

verdict=approve
run_id: review-647-2
session_id: c3693a9b-7acf-418c-a99d-835747869ed9
rounds: 2
pr: #657
reviewed_head: 497740737845501720e7c52f848015eac183edf4
reviewed_patch_id: 1909ee28ea7c98d48291bcc1300c631da24775c3
inherited_patch_id: 0be43fad810014af9b70610de21654dd8b507ab0
inherited_from_verdict: 5ba15b044a021b5c8dbd900f27c9d454d15bc200
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 2 inherits patch `0be43fad8100` and reads the delta `5ba15b0..HEAD` (3 commits, 7 files,
+127/-7). Both round-1 blockers are discharged, and each was verified by **execution**, not by
reading the diff.

**B1 is fixed and the fix is live.** `seed_lane_worktree_settings` now asks `git check-ignore` about
the destination path before any bytes exist there, and skips with the `.gitignore` line to add. The
mechanism is the right one: `worktree_inflight()` (`lean-gate.sh:2119`) reads
`git status --porcelain`, whose default `-unormal` reports untracked-but-not-ignored files and
nothing else, so `check-ignore` on the destination is exactly the predicate that keeps the sweep's
input clean. I re-ran round 1's probe as the build re-ran it, and then went further: applying the
new catalog row's sed in an isolated worktree reds **exactly `(ws9)` and `(ws10)` and nothing
else**, with the eight original cases green under the mutant, while the unmutated tree is
`0 FAILURE(S)`. That is the row's whole claim, independently reproduced.

The fixture change is the part that matters most and it is correct. `(ws9)`/`(ws10)` run in a
**second** repo whose `.gitignore` carries only `node_modules/` and whose `core.excludesFile` is
pinned to `/dev/null`. That pin is load-bearing exactly as its comment says: I confirmed this repo's
new `.gitignore:33` resolves `.claude/settings.local.json` as ignored **with the operator's global
ignore file neutralised**, which is what makes the dogfood lane take the copy path on a CI runner
and not merely on this machine.

**B2 is fixed, and the enumeration survives falsification.** The tracked `Bash(gh:*)` is gone. I did
not take the derivation on trust: the stated basis is "the lane scripts and skills, cross-checked
against what lane sessions have really run", and the second half carries it. Counting `gh` verbs
across 477 session audit ledgers, the nine kept entries are precisely the high-traffic reads plus
the one PR-opening write — `gh issue view` (704), `gh pr view` (441), `gh run view` (306),
`gh pr checks` (143), `gh pr list` (101), `gh run list` (79), `gh issue list` (49), `gh pr create`
(35), `gh pr diff` (9) — and every excluded verb is either a categorical write (`gh pr merge` 4,
`gh pr close` 3, `gh issue close` 5, `gh issue edit` 28, `gh pr edit` 25, `gh pr comment` 26,
`gh issue comment` 19) or `gh api` (263 across forms), excluded on the prefix argument. Three of the
kept verbs appear nowhere in the lane scripts, so a scripts-only derivation would have missed them;
the ledger half is doing real work. `gh pr checkout` is named in `review-lean`'s own checklist but
has **zero** ledger invocations, so omitting it is empirically right rather than an oversight.

The `gh api` prefix argument is sound as stated: an allow pattern matches a command prefix, and no
`gh api` prefix excludes a trailing `-X DELETE`.

Three warnings, no blockers. All seven ACs are satisfied against the committed spec.

**On the spec amendment.** AC-4's bar moved this round from "the three allows" to the enumeration,
and a spec amended to match the diff is normally itself a blocker. It is not one here, on two
independent grounds: the amendment **tightens** the bar rather than lowering it to fit what shipped
(a wildcard was permitted before and is now forbidden at any width), and `D-8` carries
`user-answered` provenance for a categorical operator ruling issued at re-entry launch, before the
fix was written. The rule that guards against post-hoc spec fitting is not engaged by a bar that got
harder for a reason that pre-dates the code.

## Strengths

- **The fixture is a second repo, not a ninth case in the first one.** Round 1's defect existed
  *because* eight cases shared the feature's premise; adding a case to that fixture would have
  reproduced the blindness. Splitting the fixture is the only move that makes the suite able to
  fail, and the `core.excludesFile=/dev/null` pin closes the remaining leak — without it both new
  cases would have measured the operator's home directory and taken a different path on CI.
- **`(ws10)` is round 1's probe promoted to a case.** A blocker found by an out-of-band probe
  normally leaves no durable guard behind; this one now reds automatically, and the sweep-then-seed
  ordering means it pins the real interaction (entry *N* seeds, entry *N+1* declines to reap) rather
  than a restatement of `(ws9)`.
- **The catalog row earns its keep against the generic tier explicitly.** The guard line carries no
  `-eq`/`-ne`, no `-z`/`-n`, no `&&`/`||`, no `grep` literal, no `${VAR:-}` and no `exit 1` — so no
  generic operator enumerates the site and it would otherwise be an unmutated line. That is the
  correct justification for a catalog row, and it is stated rather than assumed.
- **The guard is index-aware by construction, which covers a case nobody claimed.** `git
  check-ignore` consults the index by default, so a destination that is *tracked but deleted on
  disk* answers "not ignored" and is skipped — copying there would have produced a ` M` entry and
  dirtied the tree just as surely as an untracked file. The never-clobber test cannot see that
  shape; this one does.

## Warnings

### W1 — "made inside the `lean-gate.sh` call the first allow already covers" is false for the writes it is invoked to excuse

`docs/plans/second-shift-647-lean.md:77` (`D-8`), and the same sentence in the PR body's B2 section.

The exclusion of `gh pr comment` / `gh issue comment` / `gh issue edit` is the operator's categorical
ruling and is not in question. The *reason given for it being costless* is checkable, and it does not
check out. `lean-gate.sh` contains exactly one `gh` token in its entire 5000+ lines — `gh pr checkout`
inside a warning **message string** at line 5430 — and no reference to `gh-bot.sh`, `gh pr comment`
or `gh issue comment` at all. It does invoke `claim-issue.sh` (line 2872), which wraps the bot, so
the *claim and label* writes genuinely are covered by the first allow. The findings comment is not:
`review-lean` checklist step 8 posts it directly, and all 26 `gh pr comment` invocations in the audit
ledger are issued straight from a lane worktree, none inside a gate call.

The consequence is scoped and small — this is an interim, this-repo-only file, and the operator's own
`settings.local.json` (which AC-1 now copies) covers the gap on this machine. But it means round 1's
W1 residual **grew** this round rather than shrank: the PR's "ordering residual" section still says
AC-4's tracked block "covers the remaining first-round case here", and on a narrower block that is
now less true than it was in round 1. Fix the sentence, not the allowlist.

### W2 — the tracker's AC-4 still states the bar the shipped block deliberately departs from

`https://github.com/manoldonev/second-shift/issues/647` (issue body, AC-4).

The issue body reads "lands with the three allows and a comment naming this ticket". The shipped
block carries eleven entries, and the amendment lives in the committed spec and in `D-8` — but not in
the tracker, and there is no dated comment recording it (the three comments on #647 predate the
ruling). The precedent this repo set on #641 is that an operator amendment to an AC's bar lands in
the issue **body** plus a dated comment, carried as a D-row; two of those three legs exist here.

This does not change my scoring — the committed lean spec is the definition of done for this lane,
and it carries the amendment. It is a durability gap: a future scope check reading only the tracker
sees a mismatch, which is exactly what happened to the scope-completeness reviewer this round
(confidence 85). The remedy is a tracker edit, which is human-authority work, so it is recorded here
rather than resolved.

### W3 — the remedy's consumer story is now conditional, and the ticket's remedy-selection rationale was not revisited

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh:2050`.

Issue #647 chose this remedy over the alternative partly because it "also works for consumers, whose
ignore rules and allowlists this repo cannot see". After round 2 a consumer inherits **nothing** until
they add `.claude/settings.local.json` to their own `.gitignore` — which is the precise state the
ticket described as the one to solve for. The trade is forced and correctly taken: the alternative is
writing an unignored file, which is the defect, and `D-9` rejects the in-flight carve-out for good
reason. It is also disclosed where a consumer will actually see it — the refusal prints the exact line
to add, and commit `bbef4d9`'s `Migration:` line states it.

What is missing is the loop back to the ticket's own comparison: the sentence that justified picking
this remedy is now half-true, and nothing in the spec or PR says so. Noting it so the narrowed
consumer story is a decision on the record rather than a residue of the fix.

## Round-1 findings, dispositions

| r1 finding | Disposition |
| --- | --- |
| B1 — unignored write dirties the tree `worktree_inflight()` reads | **Fixed.** Guard at `lean-gate.sh:2050`, `.gitignore:33`, `(ws9)`/`(ws10)` in a premise-free second fixture. Mutant probe reproduces the kill set exactly. |
| B2 — tracked project-scope `Bash(gh:*)` | **Fixed.** Replaced by nine enumerated verbs; derivation independently confirmed against 477 session ledgers. |
| W1 — AC-4's efficacy is an unverified proxy; observed invocations are compound | **Not addressed, and now sharper** — carried forward as this round's W1. |
| W2 — the `wt == MAIN_ROOT` guard is redundant with never-clobber | **Not addressed; none was required.** Round 1 asked for no change. Still accurate, still harmless. |

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `(ws1)` content-identical copy against an asserted pre-condition; `(ws4)` the silent no-op asserted on the *absence* of a `settings:` line. Re-read this round (the file is in the delta); unchanged and still green |
| AC-2 | satisfied | `(ws2)` regular file plus write-independence from the origin; `(ws8)` symlinked source dereferenced. Both green in my own cold run of the suite |
| AC-3 | satisfied | `(ws3)` re-entry preserves an in-worktree mutation; `(ws6)`/`(ws7)` extend it to the tracked-file and dangling-symlink shapes. The new guard sits *after* this test, so it does not re-open the tracked-ness question |
| AC-4 | satisfied | eleven allows, no wildcard, `_comment` names #647; `jq empty` green in CI. Scored against the **amended** spec bar, whose amendment is operator-sourced and strictly tightening — see the summary. Grant width: resolved. Justification accuracy: W1. Tracker drift: W2 |
| AC-5 | satisfied | CI at this exact head `4977407`: `lint-and-selftests` pass (4m29s) and `selftests (macos, bash 3.2)` pass (6m37s) — the AC's own command on two runners, and CI is this AC's oracle. Corroborated locally: `lean-gate-selftest.sh` cold, `0 FAILURE(S)` |
| AC-6 | satisfied | `bbef4d9` carries `Changelog:` with `Migration: none — a consumer wanting the copy adds .claude/settings.local.json to their .gitignore`; the two test/docs commits carry `Changelog: none` |
| AC-7 | satisfied | `(ws9)` the seed declines by name and writes nothing; `(ws10)` the next entry's sweep still reaps. The fixture requirement the AC itself imposes is met — `.gitignore` carries only `node_modules/`, and `core.excludesFile` is pinned. Verified live: the catalog mutant reds these two and only these two |

## Reviewer panel

Six reviewers, none dark: security, performance, maintainability, complexity, test-coverage,
scope-completeness. The first five returned **zero** findings above threshold; security suppressed
three below it (highest 62), all of which I read and agree are non-findings — notably the
`2>/dev/null` on `check-ignore`, which fails **closed** (a git error skips the copy).
Scope-completeness returned three minor/nit findings; two are carried above as W2 and W3, the third
(AC-1's ordering residual) is disclosed in the PR, the spec and the code comment, and needs no
finding.

`a11y` and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (absent, resolving to `apps/web/**/*.{tsx,jsx}`). Fidelity is
`not-applicable` — the spec arms no `## Design` section and the repo declares no `design.provider`.

As in round 1, the panel is not where this round's substance came from. W1 and W3 came from
hand-derivation against the audit ledger and the call graph; AC-7's verification came from applying
the catalog mutant in an isolated worktree, which was necessary because **CI could not check it**:
`lean-gate-selftest.sh` is a 141s slow suite, so `mutation-sweep-pr` deferred every in-scope guard to
nightly and graded nothing at this head. The row's claim had no oracle but the build's own assertion
until this round reproduced it.

**Verdict: approve** — 0 blockers, 3 warnings.
