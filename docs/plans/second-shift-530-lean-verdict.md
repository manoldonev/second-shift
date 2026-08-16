# lean review verdict — #530

verdict=approve
run_id: review-530-1
session_id: a0c93f6a-9a29-490d-94b0-44487f80d653
rounds: 1
pr: #559
reviewed_head: 9df933c90176b6780db5a9fc54703d9629c00831
reviewed_patch_id: 3f2449ef6a96c073f0d91e7237969a06ab345089
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict: approve

Round 1, full branch range `3e39430..9df933c` (the gate's `delta` printed the whole branch diff —
nothing verifiable to inherit). Three files, +239/-23: the spec receipt, `lean-gate.sh`, and
`lean-gate-selftest.sh`.

The change is what the ledger asked for. `lean_worktree_for_branch` is gone — not shadowed by a
plural sibling but replaced, with no remaining consumer of the singular form anywhere in the tree
(the only surviving mentions are three prose references and one historical verdict record). Both
callers iterate. The `entry` sweep was already plural over `lean_worktrees` and correctly needed no
change.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | not-applicable | Retired to #531 at that ticket's intake; the id is not reused. #531 landed at `f9c8777`. |
| AC-2 | satisfied | `lean_worktrees_for_branch` prints one path per line (`lean-gate.sh:1554`). `cmd_teardown` iterates every registered tree (`:1808-1824`), partitioning `$REPO_ROOT` last and never skipping it. `cmd_inflight` evaluates every tree and ranks explicitly, 8 over 1 over 0 (`:1866-1881`). Probed: reverting the helper to its first-match return reds seven cases; skipping the caller's own tree reds two; inverting either ranking rung reds its own case. |
| AC-3 | satisfied | Rows are appended after the loop, one per outcome kind, `kept` second (`:1830-1831`). Case (td7) counts exactly one of each from a single call that reached both; (td8) reads the standing row back through `progress --obligations`. Probed: swapping the two emission lines reds (td8). |
| AC-4 | satisfied | `return 0` is unconditional on every non-`absent` path; (wt20), (wt21), (wt22) and (td7) each assert rc 0 across removals, keeps, and a mixed call. |
| AC-5 | satisfied | The loop calls the unchanged `worktree_destroy` per tree, so every precondition applies independently. (wt21) pins the clean-plus-dirty pair through teardown, (if8) through the scheduler's read. The pushed-ness direction is separately confirmed live — see the catalog probe below. |

## Verification I ran, and what it showed

Baseline: `lean-gate-selftest.sh` at the head, cold, in an isolated detached worktree — 424 pass,
0 fail.

Seven mutants, each applied with an exact-count anchor assertion and a `bash -n` validity check, then
scored by case id:

| Mutant | Result | Killed by |
| --- | --- | --- |
| helper reverted to the pre-#530 first-match return | killed | (wt20) (wt21) (wt22) (if8) (if9) (td7) (td8) |
| caller's own tree skipped entirely | killed | (wt22) (wt19) |
| caller's own tree ordered FIRST instead of last | **survived** | — see the suggestion below |
| `kept` row emitted first, `removed` last | killed | (td8) |
| an unreadable tree allowed to overwrite an in-flight one | killed | (if10) |
| an unreadable tree never allowed to beat a clean one | killed | (if9) (if6) |
| catalog row `lean-gate-teardown-pushed-direction`, applied verbatim | killed | (wt5) (wt6) (if4) (if5) |

The last row matters because CI's `mutation-sweep-pr` is a **zero-verdict green** here — the log
reads `deferred-to-nightly: slow suite (147s)`, `mutants_applied 0`. The PR body says so plainly
rather than presenting it as coverage, which is right; the probes above are what stands in for it
this round.

D-11's two mutation obligations are discharged, by arithmetic rather than assertion. For the two
operator classes carrying baseline rows on this guard, the matched-site counts are identical across
the diff (`default` 57 to 57, `cmp-eq` 39 to 39) and the first three matched lines are byte-identical
at the same line numbers, so ordinals 1 and 2 — the whole swept window at K=2 — cannot have re-keyed.
`cmp-z` and `logic` gain sites (140 to 144, 271 to 276), all after the swept window, and neither
carries a baseline row for this guard. The catalog anchor matches exactly one line, byte-unchanged.

CI on this head: `lint-and-selftests` success with `lean-gate-selftest.sh` in its own `pass` group
and not a cache hit, `selftests (macos, bash 3.2)` success, `mutation-sweep-pr` success as described.
`pr-gates` is red on exactly one arm — no committed verdict record for #530 — which is this
round's own output and the expected pre-review state.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness. Six
selected, six returned, none dark. No a11y or design-fidelity dimension was routed — no changed path
belongs to a web-component surface, and this repo declares no `stageParams.webComponentGlobs`.

## Findings

No blockers.

### Warning — a resolved `kept` outcome can no longer be reported as resolved

`append_teardown` is idempotent per outcome kind, and `obligations_report` reads the LAST teardown
row. The comment at `append_teardown` states the intended transition explicitly: "a later call
reaching a DIFFERENT outcome still appends, which is the transition an operator actually wants to
see (kept, fixed, then removed)."

A mixed call now writes both kinds at once. So after a call that removed one tree and kept another,
the operator resolves the kept tree and re-runs `teardown` — and neither row appends, because both
kinds already exist. The standing outcome stays `kept` forever, and `progress --obligations` reports
a human is needed on a lane where nothing is left. Before this change the mixed call could not
happen, so the kept-then-removed transition always worked.

Not a blocker, and not scored against AC-3, which is about a single call and which the diff meets:
the row is diagnostic only. `orchestrate-lean.sh` echoes `closeout_report` on its failure paths and
gates on nothing in it, and the namespace note is explicit that nothing reading `| milestone-<n> |`
can see this row. Worth a follow-up rather than a round.

### Suggestion — D-7's ordering half is guarded for existence, not for placement

(wt22) reds when the caller's own tree is skipped, which is the half that matters most. It does not
red when that tree is merely moved to the FRONT of the removal order: that mutant ran the full suite
green, 424 of 424, and the fixture does exercise the hazard the comment names — `wgate` runs the
gate with cwd inside the worktree it removes.

Read the right way round, that is mildly reassuring about the code and unflattering about the guard:
the "remaining removals running from a deleted cwd" failure did not materialize, so the ordering is
defensive depth rather than a load-bearing invariant. But the decision is written down as D-7 and
carries a stated rationale, and nothing in the suite would notice a later edit undoing it. If the
ordering is worth the ledger row, it is worth an assertion on emission order, not just on membership.

### Suggestion — the tie-break is documented but unexercised

The ranking implements first-found-wins on a tie, and the comment calls that deliberate. None of
(if8)-(if10) constructs one: each pairs two distinct outcomes. Two trees both at 8, asserting that
the first-registered one owns the reported path and reason, would close it. Low harm either way —
both trees need a human — but the same "documented claim, no guard" shape as the one above.

### Nit — one word in the PR body

The body describes the catalog row's matched bytes as "unchanged and unmoved". The bytes are
unchanged and the row needs no re-anchoring, which is the substantive claim and is correct; the line
itself did move, 1622 to 1628, displaced by the helper's new comment block. Immaterial for a
sed-anchored row, and worth only a word if the body is ever edited.

## Strengths

- The mutation reporting is honest in the direction that costs something. A zero-verdict
  `mutation-sweep-pr` green is the easiest place in this repo to claim coverage that was never run,
  and the body names the deferral and the reason instead.
- D-11 told the build to "confirm rather than assume" on the baseline ordinals and the catalog
  anchor. It confirmed, and the confirmation reproduces.
- Replacing the singular helper rather than adding a plural sibling is the right call and was carried
  through — there is no first-match form left for a future caller to reach for.
- The ranking is written as explicit rungs with a stated reason (a later renumbering of the codes
  cannot silently invert it) rather than as a numeric comparison on the exit codes. Two of the seven
  probes land on that logic and both die.
