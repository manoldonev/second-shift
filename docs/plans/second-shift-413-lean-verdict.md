# lean review verdict — #413

verdict=approve
run_id: review-413-2
session_id: 6402c4e1-cecd-4426-8d56-a8fb1ef71ecc
rounds: 2
pr: #415
reviewed_head: 51f08a7f2e062d6a39d36a55f2c9540705ecfaa7
reviewed_patch_id: d1082fe6abd36dedb7683795d071e24af555a4b5
inherited_patch_id: cacb3b4ec531a1f62a5ebcd6b20ee92195157af8
inherited_from_verdict: d56d9ca73ed1b3d7a1e5e282b2d4d28bf8535dca
fidelity: not-applicable
model: unknown

# Review round 2 — PR #415 (#413), verdict: approve

Range read: `d56d9ca..HEAD` (the delta since round 1's reviewed tree `cacb3b4ec531`), inheriting
that round's coverage. Round 1's findings were read first. The reviewer panel was additionally run
over the **whole** branch (`c3f8300...HEAD`) rather than the delta, so nothing is inherited by
assertion where a fresh reading was cheap. Design: `not-applicable` — `design` is `null` in this
repo's runtime config, so the spec's `Design: none` disarm is justified; step 5b skipped.

**B-1 is closed, and closed at the right side.** The blocker is fixed by refusing at the gate that
*declines*, which is the only placement that keeps exactly-one in the cell where the diff carries
both keys' specs. Driven from this checkout against both real gates, with round 1's own repro
inputs:

```
branch=claude/second-shift-413  body="Part of #400"  diff=<PR #415's own file list>
  check-lean-chain.sh      rc=1  ✗ key mismatch: the PR body resolves to #400 but the head branch
                                 'claude/second-shift-413' resolves to #413, and the diff commits
                                 #413's lean spec (docs/plans/second-shift-413-lean.md). …
  check-pipeline-chain.sh  rc=0  lean-authored PR — not applicable
```

Round 1 had both at `rc=0`. And the case that pins it is not decorative: with step 4b present but
never refusing (`if false`), `(D3)` is the **only** red in the 71-case suite. `(m)` behaves the same
way against the `default::2` mutant it was written for — the only red in 20.

No blockers. Three warnings and three suggestions, none of which the shipped behavior turns on.

## Warnings

### W-1. AC-17's headline invariant is falsified by the sibling's *other* exemption arm

AC-17 leads with **"No PR is exempted by both chain gates."** Step 4b models exactly one of
`check-pipeline-chain.sh`'s three exemption arms — step 3b (the diff commits the branch key's lean
spec). It models neither the step-2 arm (branch does not match the prefix) nor the step-3 arm
(prefix-matched branch with a **non-key suffix**). Driven, same checkout:

```
branch=claude/second-shift-413-v2   body="Closes #400"   diff=<PR #415's own file list>
  check-lean-chain.sh      rc=0  non-lean change — not applicable
                                 (4b reads the trailing digit run "2"; no *-2-lean.md in the diff)
  check-pipeline-chain.sh  rc=0  prefix-matched branch with a non-key suffix ('413-v2') — exempt
```

Both exempt, with a **fresh** `docs/plans/second-shift-413-lean.md` in the diff and nobody reading
its evidence. That is B-1's consequence class, reached through a different door.

**Why it is a warning and not a blocker.** Unlike B-1, this is not lane-reachable: the lane writes
`<branchPrefix><key>`, and under github the key is digits, so the suffix always parses and this arm
is never taken. Getting here needs a hand-made branch name *plus* a body whose first issue reference
differs from the spec it commits. B-1 needed only the second. The behavior on every branch name the
lane can produce is fail-closed, and I verified that by driving the table rather than reasoning about
it (cells 1–8 below).

**What actually needs doing is a restatement, not a code change** — the same remedy this round
already applied to AC-11, applied to its replacement. Three shipped sites now carry the over-claim,
and each will be read as settled by whoever touches this boundary next:

- `docs/plans/second-shift-413-lean.md` AC-17 — "No PR is exempted by both chain gates."
- `scripts/check-lean-chain.sh:96-106` — "no PR is EXEMPT from both … On a key disagreement both
  gates may fire; neither may be silent."
- `docs/pipeline-manifesto.md` — "The invariant that actually holds is **no PR is exempt from
  both**."

The invariant that survives the table is narrower: *a PR whose branch resolves to a key under the
pipeline gate's own derivation, and whose diff commits that key's lean spec, is never exempt from
both.* Where the branch resolves to no key at all, the pipeline gate exempts unconditionally and
nothing downstream of it claims the PR.

This is the round-1 diagnosis recurring one level down — a property proven for the cell it was
designed for, generalized in the prose to a universal that was never driven. The manifesto paragraph
added this round is right about the lesson and then commits the error it describes, in its last
sentence.

### W-2. The restated AC-11's own example has no case in either suite

The spec's round-2 restatement cites a concrete cell as the counterexample that made AC-11 an
over-claim: branch `<prefix>500` + body `Closes #392` + `…-392-lean.md` in the diff → applicable to
both. I drove it and it holds — `check-lean-chain.sh` applies via the body key and reds on the
missing spec/verdict; `check-pipeline-chain.sh` applies and reds on the key mismatch. But no case in
either suite drives it. `(D3)`/`(D3b)`/`(l8)` all drive the mirror cell (branch-key spec in the
diff). The claim the spec now rests on is therefore prose again, and a future edit that narrowed
either gate's matching in that cell would break it with no test going red. Raised by
`unit-test-mutation-reviewer` at confidence 84; confirmed by driving it.

### W-3. Two different cases in `check-pipeline-chain-selftest.sh` are both labeled `(l8)`

`:195` (`AC-17: a branch-key/body-key disagreement still exempts here`) and `:213` (`a missing
--diff-files-file is exit 2`). The new case was inserted above `(l7)` and took a label already in
use below it. Harmless to kill-ability — each `ok`/`bad` is independent — but this repo cites case
labels from mutation-catalog rows, baseline notes and verdict records, and `(l8)` now resolves to
two different assertions. `(l9)` on the second.

## Suggestions

- **`require_branch_name` guards three call sites; one is driven.** `lean-gate.sh:719` (`entry`),
  `:755` (`claim`), `:2093` (milestone 5). `(e4)` drives only `entry` under an unresolvable prefix.
  Dropping the guard from `claim` or `5` would likely still fail downstream, but through a different
  message and possibly a different exit code, and no assertion is pinned to the intended
  `envfail`.
- **`retro-corpus.sh:197`'s new `|| exit 2` is untested, and its regression is a silent green.**
  With it dropped, `prefix` is empty, `issue="${head#""}"` leaves the whole branch name, and the
  `case … *[!0-9]*) continue` filter skips every PR — so `open-prs` reports zero verdict-less PRs
  instead of failing. That is the vacuous-green shape this diff's own headers call the worst outcome
  available, in the one tool where nothing would catch it.
- **`is_fixture_path()` is duplicated verbatim across the two gates and is not lockstep-pinned.**
  Only the `-lean.md` literal has a row (`lean-spec-suffix`). If the two copies ever disagree about
  what a fixture is, `check-lean-chain.sh` exits at step 3 — *upstream* of 4b — while the sibling
  still exempts, and the pair is both-exempt again. Identical today, so nothing is live; but 4b
  guards one decline point and the gate has three. Surfaced by `security-reviewer` at confidence 55
  (below its own threshold); it belongs here because it is the same structural gap as W-1.

## The truth table, driven

Eight cells run against both real gates from this checkout (`PIPELINE_BRANCH_PREFIX` as `ci.yml`
sets it, `LEAN_BRANCH_PREFIX` absent):

| # | branch | body key | lean spec(s) in diff | lean-chain | pipeline-chain |
| --- | --- | --- | --- | --- | --- |
| 1 | `…-413` | 413 | 413 | rc=1 applicable (evidence) | rc=0 exempt |
| 2 | `…-413` | 400 | 413 | **rc=1 key-mismatch refusal** | rc=0 exempt |
| 3 | `…-413` | 400 | 400 | rc=1 applicable | rc=1 applicable |
| 4 | `…-413` | 400 | 392 | rc=0 declines | rc=1 applicable |
| 5 | `patch-1` | 400 | 392 | rc=0 declines | rc=0 not applicable |
| 6 | `…-hotfix` | 400 | 392 | rc=0 declines | rc=0 exempt (non-key suffix) |
| 7 | `…-413-v2` | 400 | **413** | rc=0 declines | rc=0 exempt (non-key suffix) |
| 8 | `…-413` | — | 413 | rc=1 no resolvable reference | rc=0 exempt |

Cell 2 is the round-1 blocker, now closed. Cell 3 is the restated AC-11 (W-2: undriven by any
suite). Cells 5 and 6 are benign — a PR editing someone else's spec is correctly nobody's. Cell 7 is
W-1.

## Per-AC scoring (spec: `docs/plans/second-shift-413-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean_branch_prefix` returns nothing outside `docs/plans/` prose. Inherited from round 1; re-grepped. |
| AC-2 | satisfied | Inherited (round 1 drove key `ACME-7` → `abc/acme-7`, spec `acme-ACME-7-lean.md`); untouched by the delta. |
| AC-3 | satisfied (as narrowed by ledger D-1) | `branch-prefix-selftest.sh` 20/0 including the new `(m)`; detection resolved `jdoe/` from a 3-vs-1 tally driven off real refs with no network. Staged lane out of scope per D-1. |
| AC-4 | satisfied | `(c)` zero candidates rc=2 naming what it scanned, `(d)` tie rc=2 naming both, `(e3)` jira-shaped suffixes cast no vote under github. |
| AC-5 | satisfied (as narrowed by ledger D-1) | One implementation; callers remain `lean-gate.sh` and `retro-corpus.sh:197`. |
| AC-6 | satisfied | Cell 1: `applicable via lean-artifact (docs/plans/second-shift-413-lean.md): branch=claude/second-shift-413`, `source issue: #413`, no `LEAN_BRANCH_PREFIX` in the environment or in `ci.yml`. |
| AC-7 | satisfied | Cell 1 (exempt) and cell 4 (a prefix-matched PR carrying another key's spec stays fully gated and reds). |
| AC-8 | satisfied | `check-lockstep-pairs.sh`: 18 pairs, 0 failed, `lean-spec-suffix` among them. |
| AC-9 | satisfied | Re-driven **with 4b live**, since 4b now reads the head ref: `PR_HEAD_REF=lean/second-shift-413` → `applicable via lean-artifact`. The legacy prefix is unaffected by the new arm. |
| AC-10 | satisfied | Cell 4. |
| AC-11 | satisfied, as restated this round | The restatement is honest about the counterexample and promotes the property that holds. Cell 3 confirms the cited example. See W-2 for the missing case. |
| AC-12 | satisfied | `(D2)` and `(l4)` green in the sweep; cell 4's sibling arm reds on the missing plan. |
| AC-13 | satisfied | `run-lean/SKILL.md` 42 lines (cap 60); the manifesto section is rewritten to two constants and now carries the residual. |
| AC-14 | satisfied | `(D3)`/`(D3b)`/`(l8)`/`(k2)`/`(k2b)`/`(m)` added; `(D3)` and `(m)` **probed** as the sole red against the defect each was written for. `(l8)`'s label collides — W-3. |
| AC-15 | satisfied | Re-run independently from this checkout, **without** `SKIP_STRESS` and under `env -u CLAUDE_CODE_SESSION_ID`: `shellcheck` rc=0, `jq empty` rc=0, full `*-selftest.sh` sweep **rc=0** (274/0 on the largest suite), `check-lockstep-pairs.sh` 18/0. `check-lean-chain.sh`'s `cmp-eq` site list is byte-for-byte the same order at `d56d9ca` and at head, so the two baselined ordinals still name the lines their notes claim; `branch-prefix.sh`'s `default::2` moved onto the scan root and is killed by `(m)` rather than baselined. |
| AC-16 | **satisfied** (was undeterminable at round 1) | Settled by the CI run on `d56d9ca`: `lint-and-selftests` **succeeded** in 8m54s and the `mutation sweep (PR-scoped)` step ran **17s** (17:35:06→17:35:23) against its `timeout-minutes: 15` bound. `selftests (macos, bash 3.2)` also passed. The deferral rows do what the AC claims. |
| AC-17 | satisfied as implemented and driven | The refusal fires in the split-key + branch-key-spec cell (2), does not fire in the split-key + other-key-spec cell (4, and `(D3b)`), the sibling still exempts (`(l8)`), and both suites drive it. Its **headline** over-claims — W-1 — scored the same way round 1 scored AC-11's: the mechanism the AC specifies is delivered; the summary sentence needs the same restatement AC-11 just received. |
| AC-18 | satisfied | Driven from a real worktree with no `--config`, no `SECOND_SHIFT_CONFIG` and no `--repo-root`: `claude/second-shift-`. At round 1 the same invocation answered `lean/`. `(k2)` makes the two roots disagree on purpose so the case can only pass for the right reason, and `(k2b)` proves the worktree carries no config of its own. |

## Reviewer panel

Run over the full branch (`c3f8300...HEAD`), not the delta.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope completeness | Pass | 0 | — |
| Security | Pass | 0 (2 suppressed) | 40–55 |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Unit-test mutation | Request-changes | 5 | 80–92 |
| Test coverage | **Dark (no output)** | — | — |

`scope-completeness-reviewer` passed this round; round 1's two blockers against the staged lane's
prose (overridden then by ledger D-1) did not recur. `unit-test-mutation-reviewer`'s five findings
are W-2, W-3 and the first two suggestions, plus a nit confirming 4b's own coverage — all of them
checked against the code rather than relayed. `test-coverage-reviewer` went dark for the second
consecutive round on this PR (turn-budget, no text on either attempt) — its domain is covered here
by the two mutant probes, the truth table and the independent sweep, but that is the sixth death of
this shape and it is a standing coverage gap, not a pass. `a11y-reviewer` and the design-fidelity
dimension were not routed: no changed path matches `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`) on a shell-and-docs diff.

## Strengths

- The blocker was fixed at the side that **declines**, and the PR argues why rather than asserting
  it. That reasoning generalizes past this boundary: the decline is the unsafe act, so the
  precondition belongs where the decline is written — and it is the only placement that survives the
  both-specs-in-the-diff cell.
- `(D3b)` is the case that keeps the fix honest. A 4b that fired on any key disagreement would red
  every staged PR editing an old lean spec; pinning the *non*-firing half is what stops the guard
  widening later, and it is the half most PRs would have omitted.
- AC-11 was restated rather than quietly kept, with the counterexample written out. That is the
  right instinct and it is what makes W-1 worth raising at all — the standard this PR set for itself
  is the one its replacement AC does not yet meet.
- `(k2)` is built so it cannot pass by coincidence: the worktree's remote listing favors a
  *different* identifier than the config, so the two candidate roots give different answers, and
  `(k2b)` separately proves the worktree has no config to find. Most fixtures for this class of bug
  pass whether or not the fix is present.
- AC-16 is settled with per-step CI timings rather than an overall job conclusion, and the coverage
  cost of the deferral is stated in the AC instead of buried.
