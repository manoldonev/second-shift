# lean review verdict — #709

verdict=approve
run_id: review-709-1
session_id: 09d0dafc-5cf0-45a2-9a8f-c2c43c7f5619
rounds: 1
pr: #736
reviewed_head: bf4e69f6e357263076380c37676c87a60fae2e99
reviewed_patch_id: 2062edfa97d300c8edb2630521dd7eaa25ce0ef2
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #736 (#709)

Range read: `1d714d4..bf4e69f` (root round — full branch diff, 14 files, +550/-13).
Reviewers: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.

**Verdict: approve.** No blocker. Three nits and one warning below, none of them an
unmet `AC-n`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `design_state()` rc=1 arm prints the refusal naming `record --gate design-disarm --scope design-disarm --issue <n> --decision … --answer …`. Killed by `(dzo1)`; end-to-end in `scenario-liveness` leg (a). |
| AC-2 | satisfied | rc=0 → `disarmed`; `cmd_verdict` stamps the ref from a direct `--print-ref` call. `(dzo2)`, `(dzo4)` (literal `fidelity: not-applicable (override: 55#1)`), liveness legs (b)/(c) (`89#1`), `(v3)`/`(v4)` ordinal semantics. Independently probed: `header_key fidelity` truncates the suffixed value to `not-applicable` in **both** `lean-gate.sh` and `check-lean-chain.sh`, so every existing `fidelity:` comparison is unaffected — implementation note 3's load-bearing claim holds. |
| AC-3 | satisfied | `*)` arm reds as unknown, worded distinctly from "no override". `(dzo3)` also asserts the attempt counter advanced by exactly 1. |
| AC-4 | satisfied | `fidelity_key` + `arm_override` ref resolution. `(ov6)` resolves→silent, `(ov7)` no record→refused, `(ov8)` wrong-gate block→refused, `(ov9)` non-vacuity. Independently probed `fidelity_key` on four values incl. a record whose *body* carries `fidelity: pass` — the header anchor holds. "Every existing fixture stays green": `lean-evidence-selftest` and `check-lean-chain-selftest` both all-green. |
| AC-5 | satisfied | `check-lockstep-pairs.sh`: 30 anchors, 0 failed. `check-gate-buckets.sh`: 298 enumerated refusal sites, all bucketed by 166 rows — that guard is the completeness oracle, so the single new bucket row is sufficient, not an undercount. Three new catalog rows: patterns verified unique, and all three **probed and killed** (below). |
| AC-6 | satisfied | `feat(dev-pipeline):` subject, `Changelog:` trailer with `Migration: none`. No `version`, `CHANGELOG.md` or `marketplace.json` edit in the diff. |

Design fidelity: **not-applicable**. The spec disarms with `Design: none — … this repo
configures no design.provider`, and that is verified true (`.design` is null in the dogfood
config), so the disarm is justified and the armed-run obligations do not attach.

## The mutation lane's green is VACUOUS here — the rows were probed instead

`mutation-sweep-pr` is SUCCESS at this head, and it graded **nothing on this PR's subject**.
Re-running `--mode pr --base origin/main` locally:

```
lean-evidence.sh     deferred-to-nightly   0 mutants applied
lean-gate.sh         deferred-to-nightly   0 mutants applied
check-lean-chain.sh  deferred-to-nightly   0 mutants applied
operator-override.sh swept                 0 mutants applied
```

All three guards this PR changed are slow-suite-paired, so all three deferred. The three new
catalog rows therefore had **no CI oracle**. Probed directly instead, each in its own isolated
worktree at `bf4e69f`, mutant applied with `sed -E` (the applier the sweep itself uses),
non-vacuity confirmed by diffing the mutated file:

| Catalog row | Killed by | Result |
| --- | --- | --- |
| `lean-gate-design-disarm-override-bypass` | `(dzo1)`, `(dzo3)`, `(dzo5)` | **KILLED** |
| `lean-gate-design-disarm-writer-drops-ref` | `(dzo4)` | **KILLED** |
| `lean-evidence-fidelity-ref-resolution-off` | `(ov7)`, `(ov8)` | **KILLED** |

Control at the same head, same command: `[lean-gate-selftest] all green`. The rows are credited
on this probe, not on the lane's green.

## Warning — `lean-evidence.sh` now states both halves of a contradiction

The new LOCKSTEP comment (`:1002-1003`) ends `— see register_row_violation() below,
operator-override.sh-only since the register is per-tool.` Ten lines down, the pre-existing
comment on `OVERRIDE_REGISTER_REL` (`:1011-1013`) reads `The merge boundary reads it and the
merge boundary has no config`. Two consequences, both verified:

- There is **no** `register_row_violation()` in `lean-evidence.sh` — the cross-reference is
  accurate in `operator-override.sh` and dangling in the vendored copy. Inherent to a
  `verbatim` block, but the wording could have served both readers.
- Nothing on the boundary side reads `.claude/lean-overrides.tsv` at all:
  `check-lean-chain.sh` has zero references, and `lean-evidence.sh` has only the constant
  definition and one error string. So the *pre-existing* sentence is the false one, and this PR
  makes the file assert its negation without retiring it.

Not blocking — no behavior rides on either sentence — but a future reader of the payload
consumers vendor has to reconcile two opposite claims to find out which is true.

## Nits

1. **D-23's "at both gate and boundary" ships gate-only.** Verified well-founded rather than
   dropped: implementing the boundary half would require adding a register reader to
   `lean-evidence.sh`, which has none, so the decision rested on a premise the code does not
   support. D-23's provenance is `codebase-derived`, which may be corrected without a
   `DEPARTURE` row. Functionally closed either way — a `design-disarm` register row cannot
   yield at the gate (refused rc 2) and cannot satisfy the boundary's ref resolution, which
   reads per-issue record blocks only. No fail-open. Worth a ledger correction rather than code.
2. **`design_state()`'s unresolved-`$ISSUE` arm has no case.** Fails closed (`error:` → refusal,
   never `disarmed`), and unreachable through the normal entry path. Advisory only.
3. **An empty `--print-ref` would stamp `fidelity: not-applicable (override: )`.** Requires
   `design_state()` to return `disarmed` and the immediately-following `--print-ref` to return
   nothing, which the register-forbidden rule makes unreachable today. Fails *closed* at the
   boundary if it ever happened, but with a message pointing at the wrong cause.

Dismissed after reading the code: `unit-test-mutation-reviewer`'s claim that the `*)` catch-all
arm is untested — `(dzo3)` reaches it via rc=2 from a malformed record and asserts its exact
wording. Its rc=127 sub-case is untested, which is the same fail-closed class as nit 2.

## Merge-boundary state, recorded not blocking

`pr-gates` is FAILURE at this head, on the `lean chain reconciliation` step — the expected
pre-verdict state (no verdict record was committed yet). Both correctness lanes are green at
`bf4e69f`: `lint-and-selftests` SUCCESS and `selftests (macos, bash 3.2)` SUCCESS.

Local corroboration, run with the session's leaked `LEAN_ATTEND_MODE=headless` cleared — that
leak false-reds every attend-dependent fixture and is not a branch defect (it reproduces at
`1d714d4`): `lean-gate-selftest` all green, `lean-evidence-selftest` all green,
`check-lean-chain-selftest` all green, `scenario-liveness` 85 passed / 0 failed,
`config-lint-selftest` all green.
