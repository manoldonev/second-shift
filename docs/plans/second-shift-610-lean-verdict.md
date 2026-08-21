# lean review verdict — #610

verdict=needs-work
run_id: review-610-5
session_id: 3728c4a8-4b21-4bd6-bbb2-92dbb6b2b2ef
rounds: 5
pr: #625
reviewed_head: dfa2f20f6edd43e22204294e128b07b153fe6e55
reviewed_patch_id: 2fdaa7e1632779034b769fd677264073073f3c7d
inherited_patch_id: 30f0e0d21b377cc4bce56b1357fe60e7dfd43225
inherited_from_verdict: 934e3f2b8f4737023fbbcf1a31841835165e43eb
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 5, inheriting round 4's coverage of patch `30f0e0d21b37`. Delta read: `934e3f2b..HEAD` —
the third `origin/main` merge and the one commit that closes round 4's open warning. I read wider
than the range: the whole branch contribution against the merge-base, because a merge commit puts
main's own files in the delta and reading only the range confuses them for this branch's work.

Verdict: **needs-work** — one blocker, and like rounds 2 and 4 it is not this round's code. Round
4's warning is genuinely and well closed, every technical claim in the PR body reproduces, and the
base drift that cost the last three rounds is finally **not** an issue. What is wrong is the
deliverable's own record: three rows assert a promotion that two now-closed tickets have
explicitly disowned, and the operator filed the exact corrections on #610 before this head was
cut.

## Round 4's warning is closed, and closed in the killable direction

**The rc-propagation half of the round-4 fix now has a guard.** `census` captures its pipeline's
status across its own cleanup and returns it; `check` reads that capture and exits on it. Round 4
measured that mutating either half to a constant left the suite fully green. The new case shims
`sort` — the pipeline's last element, which is what the capture reads — to exit 9, and asserts the
value that propagates.

Probed in an isolated worktree at the reviewed head, every mutant scored under brew bash 5.3.9 and
under a `bash` shim that `exec`s `/bin/bash` 3.2.57:

| Tree | bash 5 | bash 3.2 |
| --- | --- | --- |
| shipped head | 56 / 0 | 56 / 0 |
| `census`'s status return → `return 0` (site-keyed, line 307 only) | **54 / 2** | **54 / 2** |
| `census`'s status return → `return 1` (anti-constant control) | 32 / 23 | 32 / 23 |
| `check` drops its capture-or-exit propagation (line 321) | **54 / 2** | **54 / 2** |
| round 4's explicit `rm` deleted (leak guard) | 55 / 1 | 55 / 1 |
| `check`'s own status return → `return 0` (line 389, distinct site) | 51 / 5 | 51 / 5 |

Rows two and four each fail **exactly the two new assertions and nothing else** — I captured the
failing case names rather than trusting the counts, and both mutants fail
`check exits with the census's own status, not a masked one` and
`check stops instead of comparing against a truncated census`. Row five confirms round 4's own
guard is still the sole killer of its site. The per-site keying matters and the build was right to
insist on it: that return text appears twice in the file, and one unkeyed `sed` moves five
unrelated cases (row six is that other site, mutated deliberately).

**The distinctive exit code is load-bearing in a way the PR body understates.** Under both masked
mutants `check` does not exit 0 — it runs on to its comparison over an empty census and exits
**3**, printing `census: 0 construct(s) over 0 file(s); record: 8 row(s)`. So an assertion of
merely "non-zero" would have passed both mutants. Pinning the value 9 is what makes this case kill
anything, and the fail-open it guards is reproduced verbatim in the mutant's own output.

**The merge resolution is correct and complete.** Round 4 prescribed taking main's side whole in
`tools/run-selftests-selftest.sh` (#566/#621 deleted `LEAN_JOB_CEILING`, and main's copy already
subsumed this branch's scrub). `git diff origin/main HEAD -- tools/run-selftests-selftest.sh`
prints nothing, which is the check round 4 named. `mutation-slow-suites.tsv` is the union of both
sides.

**The PR body's numbers all reproduce.** `check` rc=0 at 13 constructs / 35 rows / 26 files;
prose-budget 4 fails here against 6 on `main`, measured in a detached `origin/main` worktree
rather than asserted — `build-lean/SKILL.md` reads 1707 against a 1624 row here and 1930 against a
1488 row there, so that overrun is inherited and materially reduced; `review-lean` and `onboard`
fail on `main` and pass here.

## The base moved a fourth time, and this time it costs nothing

#630 landed on `main` at `2c281b56` after this head was cut. Unlike rounds 2 and 4 this is **not**
a blocker and no fourth merge is owed:

- The PR is `MERGEABLE`; `git merge-tree --write-tree HEAD origin/main` returns rc=0 with no
  conflicted path. No reviewed `+`/`-` line is touched, so the record written this round is not
  void on arrival.
- It mints no census work — proved, not assumed, by the round-4 method: `plugins/` archived from
  both `9f2b5d00` and `2c281b56` into throwaway roots and censused with `PROSE_BLOCKERS_ROOT`
  yields **38 constructs with byte-identical ids** on each.
- `check` over the actual merged tree (`25393b03`) reads `13 construct(s) over 26 file(s);
  record: 35 row(s)`, `✓ zero undispositioned constructs`, rc=0. AC-6 survives the merge.

`mergeStateStatus: BLOCKED` is the committed `verdict=needs-work` holding the gate, not a new
problem. CI on this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass, `pr-gates` fail — the last being the correct state while the record says
needs-work.

## Blocker

### B-7 — three `promoted` rows name follow-ups that were closed NOT_PLANNED, and the corrections were filed on #610 before this head was cut

`docs/prose-blocker-triage.tsv` rows `pb-21641fc1`, `pb-ce91bffc` (both `#623`) and `pb-3bdd8454`
(`#624`) read `promoted | filed`. Both tickets are now **CLOSED / NOT_PLANNED** — #623 at
2026-08-21T12:48Z, #624 at 13:10Z — each closed on a finding that the rule *cannot become a
control*, not that it was deferred.

This is not an inference from the closures. The operator posted the row corrections **on #610
itself**, with the replacement rows spelled out:

- 12:47:49Z — `pb-21641fc1` / `pb-ce91bffc`: "the rows' `promoted` disposition and their `#623`
  enforcer are both now wrong", with the two tab-separated replacement rows given verbatim, and
  "Please fold this into the conflict resolution you already owe."
- 13:11:33Z — `pb-3bdd8454`: "the row points at a promotion that will not happen", with the
  recommended re-disposition given and one judgment call explicitly left to this lane.

HEAD `dfa2f20f` is dated 12:52:55Z — **after** the first comment — and carries neither correction.

**Why it is a blocker rather than a warning.** AC-4 requires a `promoted` construct to have either
the shipped guard or "the record's `enforcer` cell carries the follow-up issue that **owns** it".
An issue closed not-planned, whose closing comment says the prose stays as prose and the triage
row is stale, owns nothing. So three of 35 rows assert a promotion no gate performs and no open
ticket owns — the promotion is dropped, and the drop lives only on the tracker, not in the
deliverable this issue ships. That is the one thing AC-4 exists to prevent.

**And nothing downstream catches it.** `check`'s enforcer-resolution arm exempts issue-shaped
cells by construction (`prose-blockers.sh:340`, the enforcer test skips a cell matching a bare
`#`-number), so the record reads rc=0 while these three rows are false. D-8 already says `check`
cannot verify that a named enforcer really enforces the rule; this is that gap with a live
instance in it. It lands at review or nowhere.

**The corrections apply verbatim at this head — I checked rather than assumed.** All three ids
still resolve in the census at `dfa2f20f` with unchanged sites
(`intake-orchestrator/SKILL.md:218` and `:235`, `figma-iterate/SKILL.md:57`), so columns 1 and 4
stand and only columns 2, 3, 5 and 6 change. #630, the pending base merge, touches `dup-scan.sh`
and its selftest only — not `intake-orchestrator/SKILL.md` — so the ids survive that merge too.

Both operator comments land on `deleted` / `pointer-kept` / `-`, which is the only legal pairing:
`prose-blockers.sh:326` permits an empty enforcer for `deleted` alone, and `pointer-kept` is a
surviving-action row so neither the UNPRUNED nor the STALE arm fires. **One judgment is genuinely
yours and is not mine to settle**: #624's comment notes that AC-2 documents `deleted` as carrying
"the one-line reason it was **never a control**", while a reader could argue `pb-3bdd8454` is
instead *worth enforcing but unenforceable here*. If that distinction matters to this record, say
so in the note rather than flattening it. Applying the corrections and saying which reading you
took closes this.

`pb-0426581f` (`#622`) is unaffected — #622 is still OPEN.

## Warnings

- **`mutation-sweep-pr` is green on this head and grades nothing**, unchanged since round 3 and
  for the same self-inflicted reason: this PR's own slow-list row defers `prose-blockers.sh`
  wholesale. I did not treat that green as signal. The round-5 build's cold override sweep
  (`applied=8 killed=8 survived=0`, 9 verdicts live, 79s,
  `sites_beyond_budget: cmp-z:4+logic:23+default:1`) is consistent with rounds 3 and 4, and my own
  hand probe above covers the two sites the ordinal cap skips. No action — recorded so the next
  reader does not mistake the lane's green for coverage.
- **Two files arrive unbaselined from the base**, not from this branch: `tools/gate-ablation.sh`
  and `tools/gate-ablation-selftest.sh` report `NEW (add to baseline)`. They are main's, the prune
  does not move them, and AC-7 only obliges rows the prune moves — so nothing is owed here. Named
  so it is not rediscovered as this branch's debt. prose-budget is a nightly guard
  (`nightly-guards.yml`), not a PR gate, so none of this reds the lane.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `census` emits 13 rows over 26 files on this head, tier line `stop=13 (default), bold=59, all=227`. The behavioral selftest is 56 cases, 56/0 under bash 5 **and** bash 3.2, and the two cases added this round are provably non-vacuous — each of the two production sites they cover fails exactly them and nothing else. |
| AC-2 | **unsatisfied** | Mechanically the record is well-formed: 35 rows, exactly one disposition each, 30 `gate-backed` / 4 `promoted` / 1 `deleted`. But B-7 makes three of those dispositions factually wrong — `promoted` asserts a rule that a gate will enforce, and the two tickets that would have enforced them are closed not-planned on the finding that they cannot be. The operator's filed corrections re-disposition all three to `deleted` / `pointer-kept`. |
| AC-3 | satisfied | `check`'s mechanical arm resolves every path-keyed enforcer in the tree (rc=0). The AC's "resolves in the tree" clause has only ever bound path-keyed cells — issue-shaped enforcers are exempt by construction — so the three stale issue refs are scored under AC-4 rather than double-counted here. |
| AC-4 | **unsatisfied** | Same root cause as AC-2, and this is where it bites hardest. No guard shipped (D-1 authorizes that for anything larger than one-guard-small), so each `promoted` row depends entirely on its `enforcer` cell naming the follow-up that owns it. `#623` and `#624` are CLOSED/NOT_PLANNED and their closing comments explicitly disown the promotions. Three of four `promoted` rows therefore satisfy neither limb. `#622` (`pb-0426581f`) is OPEN and does satisfy it. |
| AC-5 | satisfied | Six tab-separated columns on all 35 rows; every disposition and action inside the declared enums, which `check`'s malformed-record arm would exit 4 on otherwise. The corrections B-7 asks for stay inside the same enums and the same key format. |
| AC-6 | satisfied | `check` on this head: `census: 13 construct(s) over 26 file(s); record: 35 row(s)`, `✓ zero undispositioned constructs`, rc=0 — and the same over the merged tree with the pending base. No standing CI guard wired, per D-9 and the AC's own text. Note that AC-6 is satisfied *and* blind to B-7, by the design D-8 declares. |
| AC-7 | satisfied | `prose-budget.sh --check`: 4 fails here, 6 on `origin/main`, both measured. Three fails are pre-existing and untouched (`QUERIES.md`, `figma-faithful-spec-reviewer.md`, `capability-parity-check-selftest.sh`); `build-lean/SKILL.md` fails on both sides and is materially better here. The shell baseline row for `prose-blockers-selftest.sh` is re-recorded at what this PR ships, which is legitimate for a row this PR minted for a file it authors in full. Residual ownership (#553/#554/#566/#541, and the agent-contract corpus routed to phase 2) is named per row. |

Design fidelity: `not-applicable`. The spec disarms it (`Design: none`), the repo's config declares
no `design.provider` and no `stageParams.webComponentGlobs`, and no changed path is a web
component — so the disarm is justified rather than convenient.

## Panel

Six reviewers selected, **six returned** — no dark reviewer, second consecutive round. Five
returned `approve` with zero findings (security, maintainability, complexity, test-coverage,
unit-test-mutation). Security's one suppressed finding (confidence 30, the test's `PATH` shim)
is correctly below threshold — the shim is scoped to the suite's temp jail with no production
reach.

`scope-completeness-reviewer` returned `request-changes` with B-7 at **confidence 93**, reached
independently of my own reading and of anything in the dispatch prompt. Its suppressed note
(confidence 70) — that `check` has no liveness test on `filed` issue refs, so this staleness class
recurs — is correct and correctly out of scope, since AC-6 forbids a new standing guard in this
slice; it belongs to the phase-2 register. The Scope Completeness Gate is hard, so `needs-work`
follows structurally as well as on the merits.

`performance-reviewer` was **not selected**, unchanged from round 4 under the round-2+
lineup-reduction rule: zero findings in four prior rounds and no performance surface in a
30-line test addition. Not a coverage gap by darkness — a deliberate narrowing, named so a later
reader can tell the two apart. `a11y-reviewer` and the design-fidelity dimension were not routed:
no changed path matches `stageParams.webComponentGlobs` (unset, so the default
`apps/web/**/*.{tsx,jsx}`), which is the ordinary shape of a shell-and-prose diff.

## What closing this round needs

One commit on the lane branch applying the three row corrections from the two #610 comments, and a
sentence in the PR body saying which reading you took on the `pb-3bdd8454` note. `check` will
still read 13/35/rc=0 afterwards — the corrections change no id and no site, and `deleted` +
`pointer-kept` keeps both the UNPRUNED and STALE arms quiet. No base merge is owed: the PR is
mergeable against `2c281b56` and that merge mints no census work.
