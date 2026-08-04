# lean review verdict — #374

verdict=approve
run_id: review-374-2
session_id: bbcd2e14-87b3-447a-a19a-fabd8ca03ac9
rounds: 2
pr: #376
reviewed_head: 8d08cd080e482adb6d078d0a92541537a66e7673
reviewed_patch_id: 4b03e4e4dd57d299112ee8930486e1764e085eab
model: unknown

# Review round 2 — PR #376 (issue #374)

Round 1's blocker is fixed, both warnings are fixed with cases that were verified to kill their
mutants, and two of the three notes are taken. The amended `AC-n` set (AC-14 … AC-18) was
written before the re-handoff, as the lane requires. All 18 criteria are satisfied and no
blocker survives. Two warnings and four notes are recorded below; none of them blocks.

## Verification run (from this checkout of the PR head, 8d08cd0)

| Check | Result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` | rc=0 |
| `jq empty` over every `*.json` | rc=0 |
| every `*-selftest.sh` suite, `-P 4`, **no `SKIP_STRESS`**, `env -u CLAUDE_CODE_SESSION_ID` | rc=0 over **63** suites |
| the four round-2 mutant kills, re-run one guard at a time | reproduced — each reds exactly one case, and it is the paired one |
| `mutation-sweep.sh --mode pr --base origin/main` (advisory, local) | reproduced — see AC-12 |
| `check-changelog-trailer.sh` / `check-frozen-files.sh` against `origin/main` | rc=0 / rc=0 |
| CI on 8d08cd0 | `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `pr-gates` red on the round-1 `needs-work` record — this record clears it |

**The mutant-kill claims are reproduced, not accepted.** Reverting one guard at a time (`cp`
restore, `python` anchor asserting a single occurrence) and running the whole suite:

| Mutant | Suite failures | The one that failed |
| --- | --- | --- |
| `disp = $(NF-1)` restored | 1 | `(y6)` |
| report only the first unresolved region | 1 | `(y7)` |
| drop the `ratified = yes` conjunct | 1 | `(y8)` |
| delete the jira short-circuit | 1 | `(n16)` |

Baseline and post-restore runs were both green, and the worktree was clean afterwards.

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| W-1 | warning | `lean-gate-selftest.sh` / `scenario-liveness-selftest.sh` | nothing anywhere runs `all` against an unresolved region, so the post-verdict backstop is a live, load-bearing path with no coverage at any tier |
| W-2 | warning | `SKILL.md` (Resume) | on the resume path the new check is deferred from minute 1 to step 9 — `all` prints `✓ milestone-1 (pre-pass)` for an issue `bash G 1` refuses |
| N-1 | note | `lean-gate.sh` (`pause_and_ask_ids`) | the trailing-pipe fix left `id = $2`; a leading-pipe-less GFM row resolves the id to the Region text |
| N-2 | note | `lean-gate.sh` (`check_pause_and_ask`) | with two unresolved regions the intent-gap route can clear at most one, yet the refusal offers it for both |
| N-3 | note | commit `8d08cd0` | a commit adding a new gate contract is typed `fix:`, which derives a patch bump |
| N-4 | note | PR body | the verification table says 49 selftest suites; the repo has 63 |

### W-1 — the composed path the new gate reaches is unpinned at every tier

`cmd_all`'s pre-pass runs `cmd_1` under `PRECHECK=1`, which skips `check_pause_and_ask`; the
real `cmd_1` further down the same sweep does not. So `all` *does* enforce the new contract —
once the pre-pass is clean. Probed on a throwaway fixture with the committed gate from this
head, an unresolved `OR-1`, and a committed `verdict=approve`:

```
[lean-gate] ✓ milestone-1 (pre-pass): docs/plans/acme-7-lean.md (1 AC-n reference(s))
[lean-gate] ✓ milestone-4 (pre-pass): … reads verdict=approve …
[lean-gate] ✗ milestone-1: issue #7 declares region OR-1 dispositioned pause-and-ask … (attempt 1/3)
[lean-gate] all: stopped at milestone-1 (rc=1)
```

That is the backstop on the run's mandated pre-step-9 `all` call, and it is real. No case
exercises it. `(y1)`–`(y8)` and `(n16)` all drive `bash G 1` directly; `(x1)`–`(x3)` drive `all`
with the fixture-wide no-regions issue file. The scenario tier is worse than uncovered: the
diff's only touch of `scenario-liveness-selftest.sh` gives every lean leg that same no-regions
default, so the new contract is inert there by construction, and `(lean-green)`'s `lean_gate 1 77`
composes only its pass arm.

`docs/testing.md`: *"Prefer one composed scenario to N component checks … If a new gate has a
verdict path, extend `scenario-liveness-selftest.sh`."* This gate has a verdict path — refusal →
`fail_milestone` → attempt line → the 4th-red hard stop — and seven per-tool cases against zero
composed ones is the ratio that rule names. The concrete walk-through: a later refactor that
reuses the pre-pass's milestone-1 verdict instead of re-running `cmd_1` (an obvious-looking
optimization, since the pre-pass just evaluated it) silently removes the backstop with the whole
suite green.

Why this is a warning and not a blocker: the contract itself landed in round 1's diff and was
reviewed there without this being raised; the per-tool coverage is genuinely strong and now
mutation-verified; and there is no live defect — both paths that should refuse today do. A
stricter reading of the `docs/testing.md` rule would make it blocker-class, and I am recording
that I did not take it rather than leaving it implied. Cheapest remedy is one case, not a leg:
`all` on the (y2) fixture with an approve record committed, asserting the refusal names `OR-1`.

### W-2 — on the resume path the refusal arrives at step 9, not minute 1

The issue's own framing for this change is *"moving that blocker from a round-1 review finding
to a minute-1 refusal, before any code is written."* That holds for the checklist's step-3
`bash G 1`. It does not hold for the Resume path, which the amended section now sends operators
to first. Same fixture, verdict record absent (i.e. all of BUILD):

```
[lean-gate] ✓ milestone-1 (pre-pass): docs/plans/acme-7-lean.md (1 AC-n reference(s))
[lean-gate] ✗ milestone-4 (pre-pass): no committed verdict record …
[lean-gate] all: pre-pass found an already-unsatisfiable cheap assertion — stopping before milestone-3.
```

The region is never mentioned. A session resuming per the Resume section reads `✓ milestone-1
(pre-pass)` as milestone 1 being clean, implements, and meets the refusal at the mandated
pre-step-9 `all` — after the code is written, which is the outcome the issue set out to
prevent.

The diff is not wrong here: AC-7 mandates keeping the check out of the pre-pass (it is the only
network path milestone 1 has, and the pre-pass's no-network bound is the whole point). The gap
is that the pre-pass's `✓` on milestone 1 is weaker than milestone 1's real verdict and nothing
says so — not the output, not the newly amended Resume caveat, which explains only what happens
to milestones 2 and 3. One clause is enough: the pre-pass's milestone-1 `✓` does not include
the Open-Regions check, so run `bash G 1` directly at resume. `SKILL.md` is at its 60-line cap,
so it has to go in place, the way AC-11's and AC-14's edits did.

### N-1 — the trailing-pipe fix is one-sided

AC-15's rationale is that GFM does not require the trailing pipe. GFM does not require the
*leading* pipe either, and `id = $2` still assumes it. Probed directly against the committed
awk:

| Row | id resolved |
| --- | --- |
| `\| OR-1 \| Ordering \| pause-and-ask \|` | `OR-1` |
| `\| OR-1 \| Ordering \| pause-and-ask` | `OR-1` |
| `OR-1 \| Ordering \| pause-and-ask \|` | `Ordering` |
| `OR-1 \| Ordering \| pause-and-ask` | `Ordering` |

The failure direction is the safe one — the row still matches, so the gate still refuses — which
is why this is a note and not the blocker `$(NF-1)` would have been. But the refusal then names
a token no artifact can clear: the operator's comment naming `OR-1` and an intent-gap record
reading `region: OR-1` both miss, and the run is stuck refusing `region Ordering`. Taking the
id as the first non-empty cell closes it symmetrically with the disposition scan.

### N-2 — the intent-gap route does not scale to the plural refusal AC-16 introduced

`INTENT_GAP_REL` is one path per issue and every reader takes the first `region:` key, so at
most one region can ever be cleared that way. The refusal now names N regions and offers both
routes for all of them: *"neither a non-bot comment naming each nor a ratified intent-gap record
(…) exists"*. For N ≥ 2 only the comment route can actually work. Wording, or a per-region
record; either is out of AC-16's scope, which asks only that both be named in one refusal.

### N-3 — the verb

`8d08cd0` and `da57b2d` are `fix:`, and `da57b2d` adds a gate contract that refuses runs which
previously proceeded. `CLAUDE.md`: *"Use the honest verb … Here the AI tooling IS the product, so
a new capability is `feat:`."* As typed, the branch derives a patch bump for a minor-shaped
change. Not worth a round on its own — recorded so the release derivation is a decision rather
than an accident.

### N-4 — the suite count in the PR body

The verification table reports 49 `*-selftest.sh` suites; `find . -name '*-selftest.sh'` returns
63 tracked files today, and my own sweep ran 63 at rc=0. The claim's *verdict* is right and its
*measurement* is not; 49 is `CLAUDE.md`'s prose figure, which is itself stale. Worth a glance
because a count copied from prose rather than from the run is the shape that makes an evidence
table stop being evidence.

## AC scoring

All 18 satisfied. AC-1…AC-13 were re-verified against this head rather than carried over —
round 2 edits `lean-gate.sh` again, so round 1's scoring does not transfer.

| AC | Kind | Score | Evidence |
| --- | --- | --- | --- |
| AC-1 | oracle | **satisfied** | `(x1)` — marker absent after a `needs-work` `all`; proof by effect. |
| AC-2 | oracle | **satisfied** | `(x3)` — clean pre-pass, marker present, rc=0. |
| AC-3 | oracle | **satisfied** | `(x2)` — both cheap failures reported from one run. |
| AC-4 | oracle | **satisfied** | `(I2)` — exactly 2 `✗` lines, all three arm-specific strings asserted absent. |
| AC-5 | oracle | **satisfied** | `(O1)`/`(R2)`/`(R5)` green; the short-circuit is guarded on `!= approve` and cannot reach them. |
| AC-6 | oracle | **satisfied** | `note_violation()` is the single site that prints `✗` and increments the counter; `(I2)` pins 2 against 2. |
| AC-7 | critic | **satisfied** | Round 1 scored this with a stated override; the round-2 rewording removes the need for one. Verified at this head: `cmd_4` contains no `$GH_CLI`/`gh`/`curl` site, and its subprocess set is `cat git grep head tr wc` plus `sed` via `record_key` — inside the AC's widened enumeration. `cmd_1` under `PRECHECK=1` skips `check_pause_and_ask`, milestone 1's only network path. |
| AC-8 | oracle | **satisfied** | `(y2)`/`(y3)`/`(y3b)`/`(y3c)`/`(y4)`. |
| AC-9 | oracle | **satisfied** | `(y5)`. |
| AC-10 | oracle | **satisfied** | `(y1)`, plus the fixture-wide `--issue-file` default keeping every pre-existing milestone-1 case zero-network. |
| AC-11 | critic | **satisfied** | `wc -l` = 60; the two-tracker-writes rule names the operator's resolving comment as the third, in place. |
| AC-12 | oracle | **satisfied** | Reproduced from this checkout: `lean-gate.sh` 10/7/3 → `cmp-eq::1, default::1, default::2`; `check-lean-chain.sh` 12/6/6 → `cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2, detector::2`. Both match `tools/mutation-baseline.tsv` member-for-member; the AC's closing trap (new coverage shrinking a survivor set) did not fire. No re-baseline owed. |
| AC-13 | critic | **satisfied** | `check-changelog-trailer.sh origin/main` rc=0. |
| AC-14 | doc | **satisfied** | The Resume section now states what `all` reports while the verdict is outstanding, and both halves were checked against the gate rather than read: the outstanding-verdict output stops at milestone 4 without touching 2 or 3, and with an `approve` record committed the pre-pass is clean and the real progression runs — the state the mandated pre-step-9 call is in. Still 60 lines. W-2 is what the paragraph does not say, not an error in what it says. |
| AC-15 | oracle | **satisfied** | `(y6)`; the `$(NF-1)` revert reds `(y6)` alone. |
| AC-16 | oracle | **satisfied** | `(y7)` asserts the refusal count is 1 and that it names both ids; reporting only the first reds `(y7)` alone. |
| AC-17 | oracle | **satisfied** | `(n16)` — the first case in the file to drive milestone 1 on the jira arm, over an issue fixture carrying an *unresolved* region, so rc=0 proves the check was skipped. Deleting the short-circuit reds `(n16)` alone, with the refusal naming `issue #ACME-7`. |
| AC-18 | oracle | **satisfied** | `(y8)` commits `ratified: no` and asserts the refusal still names `OR-1`; dropping the conjunct reds `(y8)` alone. |

## What is good here

- **The mutant-kill evidence is the right shape.** One guard reverted at a time, the whole suite
  run, and the requirement that the paired case be the *only* red — not just that the suite went
  red. That distinction is what separates coverage from collateral damage, and all four held
  when I re-ran them independently.
- **`(y7)` asserts the refusal count, not the presence of both ids.** Two successive refusal
  lines would satisfy a presence grep while still costing the operator two round-trips; the count
  is the assertion that actually binds AC-16.
- **`(n16)`'s fixture carries an unresolved region.** A jira milestone-1 case over a clean issue
  would pass whether or not the short-circuit existed. Making rc=0 mean "the check was skipped"
  rather than "nothing fired" is the difference between a case and a decoration.
- **AC-7 was reworded rather than argued around.** Round 1 scored it satisfied on its binding
  clause with a written override; round 2 moved the AC to the clause that binds and widened the
  enumeration to what the spec already mandated. That is the right direction of repair.

## Verdict

`approve`. No blocker survives; W-1 and W-2 are recorded for the next diff to pick up, and the
notes are yours to take or leave.
