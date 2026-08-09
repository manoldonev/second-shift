# lean review verdict — #439

verdict=approve
run_id: review-439-2
session_id: 3fd4d3c7-ec02-413c-b2fa-f986bae995b2
rounds: 2
pr: #452
reviewed_head: 5eba44f21b3d9e52db1530399428f48bb4c4a891
reviewed_patch_id: a68062b8f1efa5a920632db4b1b4ca07802f2755
inherited_patch_id: 3ddd85214a65956bfe8ab49600117a587608f82b
inherited_from_verdict: 2bb199453cc6bd8bcf96bfc31cdb36f767d35f9f
fidelity: not-applicable
model: unknown

## Review summary

Round 2, `review-439-2`, inheriting the coverage of patch `3ddd85214a65` (round 1's tree).
Delta read: `2bb1994..HEAD` — one commit, 4 files, +107/−13. Round 1's findings were read
first, and every `AC-n` is scored below against the whole spec, not just the delta.

Round 1's single blocker is fixed, and I did not take the fix on trust: the case it repairs is
skip-guarded, so a green suite proves nothing about it. I supplied the resource instead —
three real prettier binaries — and probed the new assertions with verified mutants.

**`(fp5)` now has the posture AC-8 and D-10 specify, in both directions.** With no formatter on
`PATH` the suite is green and the case reports `SKIPPED`; with prettier **3.7.4** on `PATH` the
suite is green and the case **PASSes**. That is the exact inversion of round 1, where a resolvable
formatter was a guaranteed red.

```
A  no prettier      → SKIPPED: (fp5) no local prettier resolves …      [lean-gate-selftest] all green
B  prettier 3.7.4   → PASS: (fp5) every golden above is what this machine's prettier actually writes
C  prettier 3.9.6   → PASS: (fp5) …                                    [lean-gate-selftest] all green
```

I also re-derived all four goldens outside the suite, across three prettier majors — **3.1.1,
3.7.4 and 3.9.6** — by splicing the delimiter row exactly as `(fp5)` does. All four match
byte-for-byte on all three. So the oracle is not merely fixed for the pinned version: it will not
red spuriously on a developer machine carrying a newer prettier, which was the residual worry
behind round 1's blocker.

**The round-1 secondary ask — cover *the goldens*, not one of them — is really satisfied**, and
the failure message names which pair broke. Mutating `fp3`'s golden (the 64-char digest shape the
receipt actually depends on, and the pair a reader at the end of the file would never have seen)
kills `(fp5)` with `[fp3: …]`; mutating `fp1`'s kills it with `[fp1: …]`.

**Round 1's warning 2 (ambient-prettier hermeticity) is closed, and it was my error.**
`lean_resolve_prettier` probes `$REPO_ROOT/node_modules/.bin` then `$MAIN_ROOT/node_modules/.bin`
and has **no `PATH` rung**, so a host prettier cannot reach the verdict-writing cases at all; only
`(fp5)`'s own resolver reads `PATH`. Measured here, wall-clock: **73 s** with prettier 3.7.4 on
`PATH`, **74 s** with 3.9.6 — no spawn-per-case cost, and nothing like the ">6 minutes" round 1
reported. That figure was an artifact of round 1's own probe shim, which re-scanned `~/.npm/_npx`
on every invocation.

**Round 1's finding 3 is closed with a guard that actually kills.** `(fp12)` drives both
milestone-4 refusal branches — never-committed and committed-but-dirty — and the two greps are
branch-discriminating (`format those before committing` appears only on the first, `formats only
what it authors` only on the second), so neither branch can pass on the other's message.

**Round 1's finding 4 is dispositioned as OR-3** — declared in the spec beside OR-1/OR-2 and
carried in `md_table_prettier`'s header comment. That is the right treatment for a Suggestion the
round-1 record explicitly raised "rather than asking for escaping", and the spec is honest that
OR-3 is *worse* than OR-2 rather than the same size.

The gate's production code is untouched this round: the `lean-gate.sh` delta is **comment-only**
(0 non-comment added lines). Site enumeration confirms it — every mutation operator reports an
identical site count and identical first-three line numbers before and after the delta, so **no
mutation-baseline re-key is owed**, and `mutation-sweep-pr` is green on the branch.

## Probes run

Each mutant was applied to an isolated worktree at the reviewed head, byte-verified by
`git diff --stat`, and `bash -n`-checked before running. Scored on the **named case**, over
merged stdout+stderr.

| Probe | Mutant | Expected | Result |
| --- | --- | --- | --- |
| P0 | none (control, prettier present) | `(fp5)` PASS | PASS, rc=0 |
| P1 | `fp3` golden widened one space | `(fp5)` FAIL | **KILLED**, rc=2, names `[fp3: …]` |
| P2 | `fp1` golden widened one space | `(fp5)` FAIL | **KILLED**, rc=2, names `[fp1: …]` |
| P3 | delimiter splice removed (round-1 shape) | `(fp5)` FAIL | **KILLED**, rc=1, fails on all four |
| P4 | notice dropped from milestone-4 never-committed branch | `(fp12)` FAIL | **KILLED**, rc=1 |
| P5 | notice dropped from milestone-4 dirty branch | `(fp12)` FAIL | **KILLED**, rc=1 |

One methodology note, recorded because it nearly became a false result: P3's first attempt used a
heavily-escaped in-place substitution that matched nothing, and the suite came back green — a
`SURVIVED` that had measured no mutant at all. It was caught only because the harness prints
`git diff --stat` per probe and that probe printed none. **A probe that produces no byte change is
not a survivor.**

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Suggestion | `lean-gate-selftest.sh` (fp12) | The case mutates shared fixture state in ways that oblige it to stay last, and nothing enforces that. |
| 2 | Note | `docs/plans/second-shift-439-lean.md` AC-8 | An orphaned short line left by the in-place edit. Cosmetic. |

### 1 — Suggestion: `(fp12)` is position-dependent on the shared fixture tree

`(fp12)` is currently the last case in the file, and it has to be. It leaves two pieces of state
behind that a later case would inherit:

- `dcommit` runs `git add -A`, so the branch-A fixture it wrote at
  `docs/plans/acme-56-lean-verdict.md` gets **committed** as a side effect of staging branch B's
  record. Issue 56's "record `git log` has never seen" property — which the case's own comment
  names as the reason branch A uses an unused issue number — is consumed by the case itself and
  is not available to the next author who reaches for it.
- `$DVERDICT` is deliberately left dirty (`a local edit` appended, never reverted).

Neither is wrong today. But the case's comment explains *why* it needs a virgin issue number
without recording that it also spends one, so a case appended after it that reuses 56, or that
reads `$DVERDICT`, would silently take a different milestone-4 branch and still report PASS. One
line in the comment, or a `git checkout -- "$DVERDICT"` at the end, would make the coupling
visible. Not worth a round on its own.

### 2 — Note: an orphaned line in the AC-8 paragraph

The in-place edit left `resolver actually probes, which joins the` as a short line mid-paragraph.
Cosmetic only, and it does not affect the AC's meaning.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — manifest emitted in Prettier's exact form | satisfied | `(fp1)`–`(fp4)` green. Re-verified independently outside the suite: all four goldens reproduce byte-for-byte under prettier **3.1.1, 3.7.4 and 3.9.6**. |
| AC-2 — padding computed at the write site | satisfied | Unchanged this round; pure `awk`, no formatter on the manifest path. `(fp6)` green — the re-derive converges on the padded form. |
| AC-3 — no reader changes, legacy manifests parse | satisfied | `render_manifest_rows()` is untouched across the whole branch — its only appearance in the branch diff is a mention inside this round's new comment. `(fp7)` green. |
| AC-4 — verdict record formatted by a local formatter | satisfied | Read directly: `lean_resolve_prettier` carries the worktree rung then the main-checkout rung and returns 1 — no `npx`, no `PATH`. `(fp8)` green. |
| AC-5 — formatting never damages the header | satisfied | `(fp9)` green; the flattening fake formatter is reverted, warned about once, and not fatal. |
| AC-6 — absent formatter is a consumer fact | satisfied | `(fp10)` green, and observed live: suite run A resolved no formatter, skipped with one warning, and the run stayed green. (The issue body's wording is "skip silently"; the spec — binding via D-6 — specifies one warn line, and the deliverable "never fails the call" is met either way.) |
| AC-7 — both commit instructions name the obligation | satisfied | Now guarded on both halves, as the amended AC requires. `(fp11)` pins the milestone-3 message; `(fp12)` pins **each** milestone-4 refusal branch. P4 and P5 confirm each branch kills independently. |
| AC-8 — Prettier-exact claim bound by fixtures, CI takes no node dependency | satisfied | Was round 1's blocker. `(fp5)` now SKIPs with no formatter and PASSes with one (runs A/B/C), splices the delimiter row so prettier is really doing the padding, and walks **every** golden — P1 and P2 kill on non-last pairs and name them. CI still installs no node: `lint-and-selftests` and `selftests (macos, bash 3.2)` are green with the case skipping. |
| AC-9 — two docs brought current | satisfied | `docs/live-render.md` unchanged from round 1's satisfied state. `docs/testing.md` keeps the library-mode seam and adds `### Opportunistic oracles: a SKIP reports nothing`, correctly nested under the library-mode section it refers back to — above what the AC asked for. |
| AC-10 — suite hermetic against an exported `RUN_ID` | satisfied | `unset RUN_ID` still present at the top of the suite (line 49), beside the `LEAN_RUN_MODEL` guard. Round 1 verified both with and without the variable exported; nothing in this delta touches it. |

## CI

On the reviewed head `5eba44f`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass, `release-pr-gates` skipped. `pr-gates` red, and its only `✗` is the
verdict record — round 1's committed `verdict=needs-work`, which `lean-evidence` and `lean-chain`
both refuse by design. That is the expected pre-review state and resolves with this record. No CI
blocker outside the AC set.

`(fp5)`'s failure mode remains invisible to CI by construction — the lane has no node (D-11) — so
it lands on whoever runs the sweep locally. That is the accepted trade AC-8 states, and it is now
a trade rather than a guaranteed red.

## Verdict

`approve` — round 1's blocker is fixed, and fixed in the strong form: the oracle re-derives every
golden, it holds across three prettier majors, and both halves of AC-7 are now guarded by cases
that demonstrably kill. All ten ACs are satisfied. The two items above are a suggestion and a
cosmetic note; neither is worth a round.
