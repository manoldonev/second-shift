# lean review verdict — #580

verdict=approve
run_id: review-580-1
session_id: 8448dc73-e0b7-4680-a1ed-7822eada17aa
rounds: 1
pr: #595
reviewed_head: 0d8d09b2cd02287a33947627c98a1f365e09df62
reviewed_patch_id: 7baf51f481d3fe6ed9044ecee6196e1d971d8d3a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #595 (#580): milestone 3 no longer runs the diff-scoped mutation sweep

Range read: `eb3046e..0d8d09b` (root round — `bash G delta 580` printed the FULL branch diff,
16 files). Panel: security / performance / maintainability / complexity / test-coverage /
scope-completeness, all six returned, none dark, **zero findings between them**. Everything
below is the round's own reading and reproduction.

**Verdict: approve.** No blockers. Three warnings, none of which is a code fix.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `tools/capability-parity.tsv:61` | AC-2's surface set is one row short of its own derivation. |
| 2 | warning | PR body, AC-7 | The stated `logic` ordinals `412–413` do not reproduce, and cannot exist. |
| 3 | warning | CI on `0d8d09b` | `lint-and-selftests` and `mutation-sweep-pr` are stuck `in_progress`, not red. |

### 1 — `tools/capability-parity.tsv` row 61 is an un-enumerated D-18 surface (warning)

AC-2 says the surface set was "derived by grepping the tree", and carves out exactly
`docs/plans/*` and `CHANGELOG.md` as frozen records. `grep -rn 'D-18'` over the head tree, with
those two excluded, still returns `tools/capability-parity.tsv:61`, which carries both

- a live-half sentence — "the **D-18** repo-carried `tools/mutation-sweep.sh` seam owns mutation
  under a deterministic/no-model-calls contract" — whose identifier is now dead, and
- a preserved-original sentence — "lean-gate.sh's D-18 block **is the executor** (`bash
  tools/mutation-sweep.sh --mode pr --base origin/<baseBranch>`; rc!=0 reds milestone-3), running
  when the target repo carries the sweep and skipping with a notice when it does not."

Not a blocker, for two reasons I checked rather than assumed. The false sentence sits inside the
row's explicitly-labelled `Original note follows:` half, so the row is self-dating; and the live
half's actual assertion (why the model-billed mutation owner was dropped BY ARCHITECTURE)
survives #580 untouched — the seam is still repo-carried, only no longer gate-run. The file's
header also declares rows a permanent record, and `capability-parity-check.sh` validates shape
and enum only, so nothing goes red.

What makes it worth saying anyway: this is the same staleness class **#574 already repaired in
this exact cell**, prefixing `CORRECTED (#574, executed):` when the note's claim went false. The
precedent cited for leaving `docs/plans/acme-303.md` alone is "untouched since `1e2d7f7`" — the
opposite of this row's history (`d344956`, `7620251`, `2609c0e` all touched the file). A one-line
`CORRECTED (#580)` prefix, or an explicit disposition line in the spec the way `acme-303.md` got
one, closes it. Either is fine; leaving it silent is the only shape that is not.

### 2 — AC-7's `logic` ordinal figure does not reproduce (warning)

The body states the deletion's three sites sit at "`cmp-eq` ordinal 33 and `logic` ordinals
412–413 — far beyond `k=2`". I replayed the enumeration exactly as `tools/mutation-sweep.sh`
performs it (`grep -nE --` per operator from `tools/mutation-operators.tsv`, then the leading-`#`
filter at `mutation-sweep.sh:1593`), base vs head, per operator:

```
fail-open: IDENTICAL (n=0)
cmp-eq:    DIFFERS base=35 head=34 — first divergence at ordinal 33
cmp-z:     IDENTICAL (n=143)
logic:     DIFFERS base=282 head=280 — first divergence at ordinal 234
detector:  IDENTICAL (n=15)
default:   IDENTICAL (n=57)
```

`cmp-eq 33` is right. `logic` is **234–235**, not 412–413 — and 412 is not merely wrong, it is
unreachable: base `lean-gate.sh` has 282 `logic` sites filtered (283 unfiltered), so no ordinal
above 283 exists for that operator. The figure does not come out of the pre-#579 unfiltered model
either (that gives 235–236).

Warning, not a blocker, because the **claim** the figure supports is true and I verified it
independently — see the AC-7 row below. This is a PR-body correction, which costs no commit and
no round. Worth fixing in the body so the record is right.

### 3 — CI on the reviewed head never completed (warning, merge precondition)

`gh api .../commits/0d8d09b/check-runs`:

| check | status | conclusion |
| --- | --- | --- |
| `selftests (macos, bash 3.2)` | completed | **success** |
| `pr-gates` | completed | failure |
| `release-pr-gates` | completed | skipped |
| `lint-and-selftests` | **in_progress** | — |
| `mutation-sweep-pr` | **in_progress** | — |

`pr-gates` is the expected pre-review shape and nothing more: its step list is green through
frozen-files, changelog-trailer and pipeline-chain, and fails **only** at step 6 "lean chain
reconciliation" — the missing verdict record this round is about to write.

The two ubuntu jobs are the problem. Run `32272856280` started `2026-08-19T15:54:48Z` and its
`updated_at` has been frozen at `15:54:54Z` ever since; it is the only run on the branch. That is
a hung dispatch, not a red and not a backlog, and it means the two jobs that would have graded
shellcheck, the suite sweep, and the mutation registers produced no verdict on this head.

I did not wait on it — I reproduced what it would have said, locally, at the reviewed head:

| lane | result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over the whole tree at **0.9.0** (CI's exact binary, not the local 0.11.0) | rc=0 |
| `jq empty` over every `*.json` | rc=0 |
| `tools/run-selftests.sh --exclude tools/install-topology-selftest.sh` | **69 scored, 69 run, 0 served from cache, 0 failed**, rc=0 |
| `lean-gate-selftest.sh` at head | **453 cases, all green**, rc=0 |
| mutation register replay (see AC-7) | no re-key, 19/19 catalog anchors apply |

So the round is not blocked on it. But the run needs a re-dispatch before the merge boundary, or
those two required checks land on a merge with no answer.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — no sweep invoked, neither line emitted, no progress row | **satisfied** | Reproduced the negative control independently. |
| AC-2 — every live D-18 statement updated | **satisfied** | 15/15 surfaces land; finding 1 is a warning against the enumeration, not against the contract. |
| AC-3 — selftest cases that only drove this lane | **satisfied** | `(i)` de-clawed, `(i7)` re-stated, `(dj1)` re-anchored; all three re-checked against the gate source. |
| AC-4 — scenario-liveness | **satisfied** | `grep -n 'mutation' scenario-liveness-selftest.sh` → rc=1, reproduced. |
| AC-5 — breaking verb in the TITLE + `Migration:` | **satisfied** | Title is `feat(dev-pipeline)!:`; commit carries a `BREAKING CHANGE:` footer and a `Changelog:` trailer with `Migration:`. |
| AC-6 — `gates.mutation` survives, with a stated disposition | **satisfied** | Ground 1 verified at the byte level; finding ids proven byte-identical. |
| AC-7 — no mutation register row re-keys | **satisfied** | Replayed both halves myself, each probe validated in both directions. Figure error is finding 2. |

**AC-1.** I rebuilt the negative control from scratch rather than scoring it off the PR body: a
detached `git worktree` at `eb3046e` (unfixed `lean-gate.sh`, real repo layout) with only the
branch's `lean-gate-selftest.sh` swapped in. Result — **exactly 3 FAILURE(S)**, 450 passing, and
all three failures are the new cases:

```
FAIL: (i-580a) expected no mutation line at all, got: [lean-gate] milestone-3:
      tools/mutation-sweep.sh absent — mutation sweep SKIPPED (notice, not a silent pass).
FAIL: (i-580b) expected a green milestone-3 with the sweep untouched,
      got rc=0 marker=invoked --mode pr --base origin/main
FAIL: (i-580c) a mutation-sweep row reached a progress record:
      2026-08-19T21:23:29Z | milestone-3 | skipped | mutation-sweep.sh absent
```

That is the strong form of the claim. `(i-580b)`'s tripwire marker records the **actual
invocation** the old gate made, which also settles the vacuity question the case would otherwise
raise: milestone 3 on that fixture genuinely reaches the point where the sweep ran, so the green
at head is a real negative, not an early exit. Exiting **0** rather than 1 is the right call and
the reason this case is worth more than the rc assertion beside it.

At head: 453 cases, all green. In the gate source, `grep -n 'mutation-sweep\|mutation sweep'` over
`lean-gate.sh` returns comments only — the `if [ -f "$sweep" ]` block, the `sweep` local, and both
emitted lines are gone.

**AC-3.** Checked each re-anchor against what the gate actually emits rather than taking the
body's word:

- `(i7)`'s new third term `milestone-3: green gate` comes from `pass_milestone 3 "green gate"`
  (`lean-gate.sh:4196`), which is `cmd_3`'s **last statement** — so the "an extraLane that migrated
  past the verdict could not be reported at all" argument holds literally, and the re-statement is
  the stronger of the two.
- `(dj1)`'s new anchor `allowUnverified opt-out is set` occurs **exactly once** in the file
  (`lean-gate.sh:4125`), inside milestone 3's body, emitted by `say` and by no waiter path — so it
  still separates "the body ran over there" from "the waiter replayed it", which is the whole case.

Both pass at head and in the negative control, which is the correct signature for a
behavior-preserving re-anchor.

**AC-6.** Ground 1 is the one that had to be checked rather than argued, and it holds:
`grep -c 'gates\.mutation'` over `lean-gate.sh` is **0 at base and 0 at head**, so the key
demonstrably never armed the deleted lane. Finding ids are byte-identical —
`diff <(grep -oE '"T[0-9]+\.[A-Za-z0-9._$-]*"' base) <(… head)` is empty — so no consumer's
`grillWaivers` key is voided, which is the only way this rewrite could have reached a consumer.
`scripts/check-lockstep-pairs.sh`: 22 pairs, 0 failed.

**AC-7.** Two probes, each validated in **both** directions before its zero was allowed to count.

*Site enumeration.* Per-operator matched-line **sequence** compared base vs head for every touched
`.sh` — the sequence, not the line numbers, because ordinals index that sequence. `config-lint.sh`,
`config-grill.sh`, `config-grill-selftest.sh` and `doctor-selftest.sh` are **identical across all
six operators**. `lean-gate.sh` diverges only where the table above says, and critically `default`
is identical — which is what actually protects `lean-gate.sh::default::1` and `::default::2`, the
only baselined rows for a touched guard. `config-lint.sh::fail-open::1` is likewise untouched.
Positive control: deleting the first `cmp-eq` site reports a divergence at ordinal 1 (`1d0`), so a
divergence at 33/234 is a real reading and not a probe that cannot see.

*Catalog anchors.* Applied all **19** rows addressing the touched guards with `sed -E` (the
sweep's own applier, `mutation-sweep.sh:1646` — BRE would have lied here) at head and at base:
`rows=19 drifted=0` both times. Positive control: moving `lean-gate-runid-heal`'s
`^  heal_progress_run_id$` anchor on a copy gives `rows=19 drifted=1`, naming that row. So
`drifted=0` is evidence.

The body's own conclusion is therefore correct; only its `logic` figure is not (finding 2).

## Notes, not findings

- `prose-budget.sh` reds on `plugins/second-shift/skills/onboard/SKILL.md` at head (4747→5153
  words). **Pre-existing**: the identical row already reds on `eb3046e` at 5139, so this diff adds
  14 words to a row that was already over. The other two failures
  (`capability-parity-check{,-selftest}.sh`) are untouched by this diff. The guard is nightly and
  advisory, not on the PR lane. Nothing owed here — recorded so a later reader does not misread it
  as this PR's.
- `(i-580c)` greps both `$M580_PROG` and the shared `$PROG`. On the sweep-carrying fixture the old
  gate would have *invoked* rather than written an "absent" row, so it is `$PROG` that makes the
  case live — which is exactly what the negative control's captured row shows. The case fires; the
  observation is only that its two greps are not symmetric.
- The `Design` section reads `Design: none — no design.provider configured`, and the repo's config
  declares none. Disarm justified; fidelity scored `not-applicable`.
