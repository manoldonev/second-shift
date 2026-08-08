# lean review verdict — #423

verdict=approve
run_id: review-423-2
session_id: caf0a5c0-7f40-4a34-be26-313705d5b079
rounds: 2
pr: #428
reviewed_head: c7fe6510f68934c59f75fd697a409b52c7ca5e21
reviewed_patch_id: 1d8a9e4f5150e9444030d87ab4ddc7f9c65b8716
inherited_patch_id: fd2c5c480c8b0dfaaae1043fcabbb0f9897106ed
inherited_from_verdict: a6536c858b8696172b83fd3dfe826d2fe02b0ecd
fidelity: not-applicable
model: unknown

# Review round 2 — PR #428 (issue #423)

**Re-stamped after a rebase onto `origin/main`, still round 2.** The branch was rebased to
resolve a conflict in `scripts/lockstep-manifest.tsv` after #425 and #429 landed. This costs
no round, and the proof is not an assertion: of the fifteen files the branch touches,
**fourteen are byte-identical** to the tree this round reviewed (`git show <old>:<f>` vs
`git show <new>:<f>`, hashed). The fifteenth is the manifest, and its conflict was a pure
both-append at EOF — #429 added a comment-only DROPPED block, this branch added a comment
block plus three rows. The resolved file deletes **nothing** from `origin/main`, and the
nineteen lines it adds are byte-identical to the nineteen the reviewed commit added. So no
finding, no AC score and no probe in this record is stale; only the patch hash moved, which
is exactly what the re-stamp exists to correct.

Range read: `23609ec..HEAD` — the delta since the tree round 1 covered (patch `fd2c5c48`),
inheriting the rest by reference to that record. I also re-read both workflow files and the
production script in full, since round 2's new assertions are claims about behavior that
lives outside the delta.

Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — all seven returned live, none dark, all `approve`
with zero findings. Every finding below is mine.

**Verdict: approve.** Round 1's blocker is genuinely closed — I reproduced both surviving
mutants and confirmed each now reds — and both warnings are fixed. One warning remains, and
it is a comment, not a mechanism.

## What round 1 raised, and where it stands

**B1 (blocker) — FIXED, verified by re-running the exact two survivors.** On a sandbox copy
of the tool, never in the reviewed tree:

| mutant | round 1 | round 2 |
| --- | --- | --- |
| `release_one "needs-spec-work"` | **SURVIVED** | 2 red (C18 count + C18 vocabulary) |
| the whole `for b in epic needs-intake-review needs-spec-work needs-plan-review` loop | **SURVIVED** | 2 red (same pair) |

The fix is the right one: a fixture, not more assertions. `CARRIES_BLOCKERS` carries the
whole shipped blockers vocabulary — which I checked against
`schema/second-shift.config.schema.json:68`, where the documented default is exactly
`["epic","needs-intake-review","needs-spec-work","needs-plan-review"]` — plus a
consumer-configured blockers name, and `CFG_BLOCKERS` configures `.tracker.labels.blockers`
and nothing else so the expected DELETE count stays two.

**The three new assertions are separated, and none is decorative.** Each has a mutant the
other two stay green through, as the PR claims:

| mutant | C18 assertions red |
| --- | --- |
| extra `release_one "bug"` (carried, non-blocker) | count only |
| queue release retargeted at `epic` | vocabulary only |
| queue name resolved from `.tracker.labels.blockers[0]` | config-key only |

I pushed the third one further, because "kills something its siblings don't" is a weaker bar
than the repo's pruning rule deserves. Mutating the resolver to
`QUEUE_LABEL="$(cfg '.tracker.labels.queue' "$(cfg '.tracker.labels.blockers[0]' 'ready-for-dev')")"`
— a blockers-keyed *fallback*, which only fires on a fixture that sets `blockers` and omits
`queue` — reds **exactly one assertion in the whole 28-assertion suite**, the config-key
line. So the third assertion is not a sibling of the other two; it is the only thing in the
suite that can see `.tracker.labels.blockers` being *resolved*, which is the literal
requirement AC-1 states.

**W1 — FIXED.** Three `verbatim` rows, markers on both sides. Probed in a sandbox against a
manifest holding only these three rows: widening `permissions` on the template side reds
`unclaim-workflow-permissions` and nothing else; adding `reopened` reds
`unclaim-workflow-trigger` alone; dropping `GH_REPO` reds `unclaim-workflow-env` alone;
deleting a `LOCKSTEP-BEGIN` fails with `no LOCKSTEP-BEGIN/END block` rather than silently
going unchecked. Restored to 3 checked / 0 failed after each. This is the sanctioned
alternative to the grep D-10 retracted, not a reinstatement of it: it cannot pass by finding
a word.

**W2 — FIXED**, on both sides. The step is now `release the run-state labels` in both files,
the template's header comments are corrected to the plural, and the job-level `name:` was
already correct.

**S1 — declined, and the reasoning is right.** `gh api --paginate` on an array endpoint emits
one JSON array per page, concatenated, and `jq -e` takes its exit status from the last value
— so the naive flag would make a label present on page 1 read as absent, converting a
theoretical miss into a real one. `--paginate --slurp` plus a flatten is the correct form.
Recording it as a spec non-goal with that mechanism is the right disposition for a suggestion.

## Warning (not blocking)

**W3 — `scripts/lockstep-manifest.tsv`: the `unclaim-workflow-env` comment claims a reach the
row does not have.** The block comment says the row guards the case where
"`${{ }}` reaching a `run:` body on one side only is exactly the divergence a reader would
not see." It does not. The `run:` line sits **outside** the markers, and necessarily so — the
two files invoke different script paths, so `run:` can never be part of a `verbatim` block.

Probed: splicing `${{ github.event.issue.number }}` directly into the template's `run:` body
while leaving the `env:` block byte-identical leaves the gate at **3 pair(s) checked, 0
failed**, and the YAML still parses. What the row actually guards — env-block drift, i.e. the
token source and which values are made available — is real and worth having; AC-14's own text
is precise about it ("the step's `env:` block"). It is the manifest comment that overreaches.

Not a blocker: no AC is unmet, the guard does what AC-14 requires, and the injection
discipline itself is intact in both files today. But this repo's whole objection to the
prose-presence class is that something reads as coverage while not being it, and a guard's
own comment claiming a property the guard lacks is that failure mode in miniature. Worth one
sentence of correction whenever this file is next touched.

## Note on the spec amendment

Round 2 amended the spec: AC-14 is new, and a pagination non-goal was added. Both are
sanctioned — `run-lean/SKILL.md` step 4 permits amending the `AC-n` set before milestone 5,
which has not run — and neither is the pattern the "spec amended to match the diff" rule
guards against. AC-14 *adds* an obligation and the diff meets it; the non-goal declines a
round-1 **suggestion**, which was never an AC, so no acceptance criterion was weakened. Round
2 is therefore scored against a spec round 1 never saw, which is stated here rather than left
to be inferred.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Production script unchanged in the delta; round-1 coverage inherited. The negative clause is now genuinely guarded — see B1 above. |
| AC-2 | satisfied | Three no-op arms, C5/C6/C7; suite green. Inherited from round 1, unchanged in the delta. |
| AC-3 | satisfied | `jq -rn --arg s … '$s\|@uri'` at `second-shift-unclaim.sh:123`; C9 pins encoded-and-never-raw. Inherited. |
| AC-4 | satisfied | 404 tolerance C10; other failures exit 1 C11; worst-wins C12; read failure C13; usage exits 2 C14/C15. Inherited. |
| AC-5 | satisfied | Re-read in full this round. `issues: [closed]`, `permissions: {contents: read, issues: write}`, `GH_TOKEN: ${{ github.token }}`, `actions/checkout@v5`, template script run in place, issue number env-borne — no `${{ }}` in the `run:` body. |
| AC-6 | satisfied | Re-read in full. Same trigger/permissions/token/env discipline, `actions/checkout@v4`, calls `.claude/tools/second-shift-unclaim.sh`. |
| AC-7 | satisfied | `onboard/SKILL.md:259-263` copies both verbatim under Step 7 item 3; `:314-315` lists the pair in Step 8; `:161-163` states the write boundary and the read-and-write requirement, and skips the unclaim half under a non-github tracker. One question at Step 3 item 9 — no second prompt. |
| **AC-8** | **satisfied** | Was the round-1 blocker. Hermetic, `gh` stubbed on PATH, argv **and** exit-code assertions, zero YAML greps. AC-1's blockers arm is now covered by C18, and each of its three assertions is independently killable — one of them uniquely across the whole suite. 28/28 green. |
| AC-9 | satisfied | Inherited from round 1: `run-lean/SKILL.md` step 9 names where the drop now happens and the file is inside its 60-line cap; schema description rewritten with no `configVersion` change; both `SECOND-SHIFT.md` copies plus `docs/onboarding.md` and `docs/team-rollout.md` updated. |
| AC-10 | satisfied | Re-verified this round: `.claude/prose-budget.baseline.tsv` is not in the branch diff at all (0 lines). `prose-budget.sh --report` gives **19 FAIL at base `a2b158f` and 19 on this branch**. The lean spec grew 29 lines in the delta but `docs/plans/` is not budgeted (0 rows in the baseline), so no row moved. |
| AC-11 | satisfied | `second-shift-unclaim.sh:73-79` names the reliance and the symptom. I checked the premise rather than the prose: this repo's own config carries `tracker.labels: null`, and `gh label list` shows its real labels are `in-progress` and `ready-for-dev` — exactly the shipped defaults. The canary is correct under both the config-absent and config-present paths. |
| AC-12 | satisfied | The PR's OR-1 section states the trigger is unverified, why it cannot be verified pre-merge, the post-merge verification step (#423 itself is the first natural test), and the `pull_request: [closed]` reversal. |
| AC-13 | satisfied | `check-workflows-selftest.sh` walks `plugins/second-shift/templates/consumer/*.yml`; **7 ok, 0 failed**, both consumer templates among them. |
| AC-14 | satisfied | Three `verbatim` rows and markers on both sides; `check-lockstep-pairs.sh` reports **20 pairs checked, 0 failed**. Each row probed to red on its own drift and on nothing else, and a deleted marker fails loudly. `name:`, the checkout pin and the script path are outside the markers and free to differ, as specified. See W3 for a comment on the row, not on the row's behavior. |

Design fidelity: **not-applicable** — the spec has no `## Design` section and arms no `RS-n`
render states.

## Verification I ran, from this checkout

Everything below was re-run **after** the rebase, against the new base `ec7b6a4`, not
inherited from the pre-rebase run.

- Full selftest sweep, `-P 4`, **without** `SKIP_STRESS` and with `CLAUDE_CODE_SESSION_ID`
  and `RUN_ID` unset: `rc=0`. One `✗` appears in the log and is not a failure — it is inside
  an `install-topology-selftest.sh` line the suite itself labels `known:`
  (`docs/extension-points.md` is not shipped inside any plugin), it arrived with the new base
  rather than with this branch, and the sweep still exits 0.
- `shellcheck -e SC1091,SC2015,SC2181` over the changed shell — clean.
- `second-shift-unclaim-selftest.sh` — **28/28**.
- `check-lockstep-pairs.sh` — 20 pairs, 0 failed, now including the rows #429 added to the
  same manifest. `check-lockstep-pairs-selftest.sh` — 7 passed, 0 failed.
- `check-workflows-selftest.sh` — 7 ok, 0 failed.
- Diff-scoped mutation sweep against `ec7b6a4` with **`MUTATION_SWEEP_CACHE=0`**, so nothing
  replayed from the build session or from the pre-rebase run:
  `applied=8 killed=8 survived=0`, `0 served from cache`. It prints its own ADVISORY banner —
  a local userland is not CI's. `tools/mutation-baseline.tsv` carries no row for this guard
  and needs none; the guard file is byte-identical across the rebase, so no ordinal moved.
- Hand-built mutants beyond the sweep's operator set, all on sandbox copies: 2 reproducing
  round 1's survivors (both now killed), 3 separating the new C18 assertions, 1 proving the
  third is uniquely killable suite-wide, 4 on the lockstep rows, 1 on the `run:` body (W3).
  Every mutation was confirmed to have actually changed the file before the suite re-ran, so
  a no-op edit could not read as "survived".

**CI — the branch's first real check run.** Round 1 could cite no CI at all (Actions outage,
zero check-runs on every commit). Run `31162453861` executed here: `lint-and-selftests`
**success**, `selftests (macos, bash 3.2)` **success** — the bash-3.2 lane a local sweep on
Homebrew bash 5 can never stand in for — `release-pr-gates` skipped. `pr-gates` **fails at
exactly one step**, `lean chain reconciliation`, with `Set up job`, checkout and the three
other guards all green; that is the expected pre-verdict red, since it wants the
`verdict=approve` record this round is about to write.

## Strengths

- The B1 fix is diagnosed at the right layer. The reflex is to add assertions; the actual
  gap was that no fixture could make the violating mutant do anything, so the fix is one
  fixture and the production script is untouched. Saying plainly that "28 mutants, 28 killed"
  was true of every assertion that existed — and was still not coverage of the requirement —
  is the honest reading.
- Each new assertion was given a mutant its siblings survive, rather than three lines that
  die together. That is the discipline this repo prunes for, applied pre-emptively.
- W1 was answered with the *stronger* of the two options round 1 offered. A DROPPED note
  would have closed the finding; lockstep rows actually catch the drift, and the reasoning
  for why that is not a D-10 violation — copy-agreement and absolute correctness are
  different properties, and only the first is byte-anchorable — is correct and worth reusing.
- S1 is declined with the mechanism that makes the naive fix wrong, not with a judgment about
  likelihood. A one-flag suggestion that would have silently broken the membership check is
  exactly the kind that gets taken without checking the flag's output shape.
