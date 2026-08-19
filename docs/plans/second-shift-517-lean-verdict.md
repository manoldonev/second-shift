# lean review verdict — #517

verdict=approve
run_id: review-517-2
session_id: 47e3974b-1a3e-46ca-a005-b544283ed34c
rounds: 2
pr: #592
reviewed_head: 81055f3d5ef57a6f00b5c29382109e79ad2f977b
reviewed_patch_id: 47b82deba2974e786bed47bb2c206fc788aaa369
inherited_patch_id: 422191818c1bcff2c3206e9c85a9e74601f7b8c7
inherited_from_verdict: 9687d443ed4c2227045299c275c967fc03c53037
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict: approve — round 2

Round 2, inheriting the coverage of patch `422191818c1b` (round 1's record). Range read:
`9687d44..81055f3` — one commit, four files. I also re-ran round 1's per-AC checks by execution
rather than inheriting them, because they cost seconds and a round that read everything is the
stronger record.

Both round-1 blockers are closed, and each was verified independently rather than taken from the
PR body. The panel returned 6/6 usable this round with zero findings — round 1's
`maintainability-reviewer` coverage gap (W-2) is closed by its return.

---

## Round-1 blockers — both closed

### B-1 (closed) — the shellcheck 0.9.0 red

`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh:545`

`rc_receipt`'s unused `${1:-Both call sites}` parameter is dropped. `grep -n rc_receipt` shows
exactly two occurrences — the definition at :545 and one argument-less call at :560 — so the
parameter was genuinely dead and removing it changes no fixture. Its sibling `rc_plan` keeps its
parameter and is called with one at five sites, which is why only one of the pair ever fired.

Verified against **shellcheck 0.9.0 itself**, in both directions, on the same bytes:

| bytes | 0.9.0 result |
| --- | --- |
| `9687d44` (pre-fix) | **rc=1** — `SC2120 rc_receipt references arguments, but none are ever passed`, `SC2119` |
| `81055f3` (post-fix), all 5 shell files in the branch diff | **rc=0**, zero output |

And CI settles it at the reviewed head: run
[32194556880](https://github.com/manoldonev/second-shift/actions/runs/32194556880) on `headSha
81055f3` has **`lint-and-selftests` success** and **`selftests (macos, bash 3.2)` success**. Round
1's second-order consequence is therefore also resolved: the ubuntu lane that died at the
shellcheck step now runs to completion, so this head has CI selftest evidence from both jobs
rather than only macos.

### B-2 (closed) — the reconciliation disclosure survives every design state

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3063-3064`

Both `design_state` arms now append (`note="$note, …"`) instead of assigning. Enumerating every
writer of `note` inside `cmd_1` confirms the fix is complete and that no third writer exists:

```
:3001  local … note=""                                    # init
:3042  0) note="$note, ${rec_out#…}" ;;                    # #517 reconciliation — appends
:3063  note="$note, design lane disarmed for this ticket"  # appends (was: assigned)
:3064  armed)  note="$note, design lane ARMED" ;;          # appends (was: assigned)
:3078  pass_milestone 1 "$SPEC_REL ($n AC-n reference(s))$note"
```

`note` reaches stdout through exactly one `pass_milestone` call, which also disposes of the one
thing worth checking about the new guard: `(a15)`'s two `grep -q` assertions run over the whole of
`$out` rather than over a single captured line, but since both strings can only ever appear on that
one pass line, the case cannot be satisfied by an implementation that emits them separately.

**Negative control — the part that makes the new case worth anything.** In an isolated worktree
detached at `81055f3`, I reverted only the two `$note, ` prefixes and re-ran the suite:

| `(a15)` arm | fix reverted | fix present (CI, at this head) |
| --- | --- | --- |
| ARMED | **FAIL** — `expected rc=0 carrying BOTH the counts and the arming note` | pass |
| DISARMED | **FAIL** — `expected rc=0 carrying BOTH the counts and the disarm note` | pass |

So `(a15)` fails on precisely the defect it names, in both design states — which `(a11)`, running
only through the `design`-less fixture config, structurally could not. That was round 1's W-1 and
it is closed by construction, not by assertion.

---

## Warnings (not blocking)

- **W-1 — AC-11's final sentence asserts a re-key that did not happen.** It reads "Editing
  `lean-gate.sh` and `ledger-lint.sh` re-keys their generic mutation survivor ordinals, so
  `tools/mutation-baseline.tsv` is re-baselined in the same diff." No baseline row moved, and that
  is correct (see AC-11's basis below) — but the sentence states the re-key as fact, so a reader
  diffing the AC against the changed-file set concludes a promised artifact is missing. The
  scope-completeness reviewer raised exactly that inference in both rounds. The obligation is
  discharged vacuously; only the wording is wrong. Not worth a round: rewording it conditionally
  ("re-baselined in the same diff **where an ordinal moves**") is a fine follow-on, and a reviewer
  who checks the ordinals reaches the right answer either way.

- **W-2 — `pr-gates` is red at this head, and it is the expected pre-handoff state.** It fails on
  `verdict record … reads 'verdict=needs-work', not 'verdict=approve'` — it is reading round 1's
  record, which this record replaces. Distinct from round 1's B-1: the two lanes that could carry a
  real red, `lint-and-selftests` and `selftests (macos, bash 3.2)`, are both green here.

- **W-3 — the full mutation sweep dispatched on this head was still running when this record was
  written.** Run [32194568837](https://github.com/manoldonev/second-shift/actions/runs/32194568837)
  at `81055f3`, 9 of 10 shards green, 0 failures, shard 7 in flight. It is corroboration, not the
  basis: the mechanical argument under AC-11 stands on its own, and `mutation-sweep-pr` already
  passed at this head.

---

## Per-AC scoring

Every AC re-scored against the whole spec. Where the delta did not touch the code, I still re-ran
the check rather than inheriting round 1's answer.

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `--reconcile <receipt> <plan>` binds on provenance via `INTENT_PROVENANCE`, not the `Kind` cell. Re-confirmed live: the 4-column (pre-`Kind`) receipt form binds — the run's own `.claude/pipeline-state/517-ledger.md` reconciles as `8 bound, 8 carried, 0 departure(s)`, rc=0, driving the branch copy directly. |
| AC-2 | satisfied | Re-ran: dropping a bound row → rc=1, `VIOLATION: D-1 (user-answered) is in the pre-flight receipt … but not in …'s Decision Ledger`, and the counts line correctly reports `1 bound, 0 carried`. |
| AC-3 | satisfied | Re-ran all three arms. `100/min` vs `100/MIN` → rc=1 naming both sides (case-sensitive, per OR-1). `\|    100/min    \|` → rc=0, `1 carried` (whitespace-normalized). Differing text → rc=1. |
| AC-4 | satisfied | Re-ran: `DEPARTURE — throttling moved to the edge proxy` → rc=0, counted as `1 departure(s)` and **not** as a carry. Bare `DEPARTURE —` → rc=1 with the reason-required message. |
| AC-5 | satisfied | Re-ran: a spec whose `## Decision Ledger` is the prose `No material decisions — all choices codebase-derived.` against a receipt with a bound row → rc=1, landing on the per-row missing arm. |
| AC-6 | satisfied | Inherited from round 1, which verified it in the strongest available form (extracted `origin/main`'s `ledger-lint.sh`, diffed rc+stdout+stderr for plain and `--receipt` modes on the pair `--reconcile` refuses — byte-identical). The delta does not touch `ledger-lint.sh` at all, so nothing in the range can have changed it. |
| AC-7 | satisfied | Re-read the block at `:3016-3048`: it sits above the `LEAN_GATE_OBSERVE` guard, so `all`'s pre-pass sees the same answer a direct call does. rc mapping unchanged — 0 → `note`, 1 → `fail_milestone 1` (spends an attempt), anything else → `envfail` (spends none). Absent receipt inert. |
| **AC-8** | **satisfied** (was unsatisfied) | See **B-2**. Both arms append; `note` has exactly one emitter; and the reverted-fix negative control proves the new guard fails on the defect in both the armed and disarmed states. The AC's round-2 amendment **strengthens** it — it adds the "must survive `unarmed`, `disarmed` **and** `armed`" invariant that round 1 found violated — so this is not a spec bent to match the diff. |
| AC-9 | satisfied | `build-lean/SKILL.md` step 4 states the carry-forward obligation naming the provenance pair, the `D-n`/Resolution match and the `DEPARTURE — <reason>` escape; 47 lines against the 60-line cap. Untouched by the delta. |
| AC-10 | satisfied | `--help` documents the mode and the hand-maintained `sed -n '2,98p'` range still stops immediately before `set -euo pipefail`. Untouched by the delta. |
| AC-11 | satisfied | All four tiers present and non-vacuous. `(a15)` is the round's addition and is proven non-vacuous by the negative control above — the standard round 1 asked for. The amendment naming it strengthens the AC rather than relaxing it. **On the baseline clause:** no re-baseline is owed, established mechanically rather than inferred. Replaying all six operator regexes from `tools/mutation-operators.tsv` over `origin/main`'s copy and this head's, and comparing the matched-line sequence inside the swept window (`K_BUDGET=2`): every one of the seven committed baseline rows for these two guards — `lean-gate.sh::{cmp-eq::1, default::1, default::2}` and `ledger-lint.sh::{cmp-eq::1, cmp-eq::2, cmp-z::1, cmp-z::2}` — has a **byte-identical** line at its ordinal. The operators whose `k≤2` window did move (`lean-gate.sh` `cmp-z`; `ledger-lint.sh` `fail-open`/`logic`/`detector`) carry **no** committed row, so they re-key nothing. Independently, the delta re-keys nothing at all: all six operators are byte-identical between `9687d44` and `81055f3` (`cmp-eq` 40, `cmp-z` 148, `logic` 283, `detector` 16, `default` 59, `fail-open` 0) — the edit changes two lines in place and adds only comments, which are not sites. And the green enforcing sweep at `a651fbb` transfers to this head exactly: `a651fbb..9687d44` touches neither guard, so `ledger-lint.sh` is byte-identical and `lean-gate.sh` is operator-identical between the swept tree and this one. No `tools/mutation-catalog.tsv` row anchors a line this delta touched (catalog rows key on `sed` content programs, not ordinals). |

**Design fidelity:** `not-applicable`. The committed spec carries no `## Design` section (its
sections are Problem / What this ships / Acceptance criteria / Flagged defaults / Scope boundary /
Decision Ledger), and the repo's config declares no `design.provider`, so `design_state` returns
`unarmed`. Nothing to score. Round 1 noted the irony that this same condition is what hid B-2;
`(a15)` now reaches the two branches this repo's own configuration cannot.

---

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (1 suppressed, conf 30 — a display-layer scanner match on unchanged prose) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 — **returned this round**, closing round 1's W-2 coverage gap |
| Test Coverage | Pass | 0 |
| Scope Completeness | Pass | 0 (all five scope items in-diff; 3 recorded notes, all addressed above) |

6/6 usable, no dark reviewers. `a11y-reviewer` and the design-fidelity dimension were not routed:
no changed path matched `stageParams.webComponentGlobs` (unset, so the shipped default
`apps/web/**/*.{tsx,jsx}`). Not a coverage gap — the trigger did not fire on a shell/markdown diff.

The scope-completeness reviewer's three recorded notes are all resolved in this record: the
intent-provenance narrowing is receipt row **D-1** (`user-answered`) and was settled in round 1;
the `tools/mutation-baseline.tsv` observation is W-1 / AC-11 above; and its note that the dispatch
named a branch commit as base is correct and harmless — it re-classified against `main...81055f3`
itself, so the round-1 feature commits were never read as missing.
