# #709 — `Design: none` disarms the render lane on a provider repo with no operator override

Slice 2 of 4 of #705 (sequential; predecessor #708, successor #710). On a repo with
`design.provider` set, a spec can disarm the live render with `Design: none — <reason>` and the
gate accepts any non-empty reason, leaving the justification to `review-lean`'s judgment. A
per-ticket disarm that a build session can write on its own is the opt-out #705 forbids.

## Decision Ledger

Carried from the #705 intake receipt, restated from this issue's own ratified decisions and
resolved guess-points; ids and Resolutions are its own.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the disarm allowed without a gate-visible operator override? | No — not disarmable without one. | user-answered |
| D-4 | Where does the override live, and what does the verdict record? | A new closed-enum value on #613's mechanism — gate `design-disarm`, scope `design-disarm` — recorded in the fixed-path register `.claude/lean-overrides.tsv` LOCKSTEP pair (`override-record-reader`, widened rather than a new register). Verdict header records `fidelity: not-applicable (override: <ref>)`. | user-answered |
| D-10 | Can the merge boundary tell a provider repo from an unarmed one for a disarmed spec? | No — no handoff link, no visible config. Boundary scope: if `fidelity:` cites an override ref, the record must exist and validate; provider-scoped enforcement stays gate-side only. | user-answered |
| D-20 | Override record ref form. | `<issue>#<n>`, `n` the `## Override n` block ordinal in the issue's record file (`operator-override.sh`'s existing block numbering). No schema change. | codebase-derived |
| D-21 | How the writer resolves the ref to stamp on the verdict. | `operator-override.sh check` gains `--print-ref`: on rc=0 prints the ref of the matching block; the verdict writer reads it. | codebase-derived |
| D-22 | Does `check` disambiguate on scope? | No — `check` already filters on gate+issue+region and ignores scope (existing asymmetry, unchanged); scope stays descriptive for every gate. | codebase-derived |
| D-23 | Is `design-disarm` allowed in the persistent register? | No — FORBIDDEN. A register row matches on gate alone, which is exactly the blanket opt-out D-1 forbids. A register row naming it is a validation error at both gate and boundary. | codebase-derived |
| D-24 | Headless posture. | `record` already refuses from a headless session by design (unchanged). The operator records the override ATTENDED, before launching `run-lean`; a headless build on a provider repo with `Design: none` and no record hard-stops at milestone 1 naming the record command. That is the point. | codebase-derived |
| D-25 | Issue resolution on the verdict-writer path. | `design_state()` gains the issue (global `ISSUE`, already resolved by every `cmd_*`); where it may be unset on the writer path, an unknown issue FAILS CLOSED (not disarmed). | codebase-derived |
| D-26 | Fail-open residual. | A review worktree with no config resolves `DESIGN_PROVIDER` empty and the writer refusal vanishes — the existing fail-open of every config-keyed design check (config absent ⇒ unarmed), accepted; the boundary's fidelity-ref arm is the backstop. | codebase-derived |

## Design

Design: none — this slice changes gate/boundary shell and two tool contracts. It ships no web
component and this repo configures no `design.provider`, so there is no render state to declare.

## Acceptance criteria

- AC-1: on a provider repo, a spec carrying `Design: none — <reason>` with no `design-disarm`
  override record reds milestone 1, and the message names the exact `operator-override.sh record`
  invocation.
- AC-2: with a valid record the run is `disarmed`, and the committed verdict header reads
  `fidelity: not-applicable (override: <id>)` where `<id>` is that record's ref
  (`<issue>#<n>`).
- AC-3: a malformed record (rc=2 from `operator-override.sh check`) reds milestone 1 as unknown,
  not as disarmed.
- AC-4: `check-lean-chain.sh` (via `lean-evidence.sh`'s delegated override arm) reds a PR whose
  `fidelity:` cites an override ref that does not resolve to a valid `design-disarm` block for
  this issue in the committed record; every existing armed/unarmed fixture stays green.
- AC-5: `OVERRIDE_GATES`/`OVERRIDE_SCOPES` are byte-equal across the LOCKSTEP pair
  (`operator-override.sh` and `lean-evidence.sh`, anchor `override-record-reader`);
  `check-lockstep-pairs.sh` stays green. `tools/mutation-catalog.tsv` and `scripts/gate-buckets.tsv`
  gain rows for every new refusal site and re-anchored row.
- AC-6: `feat(dev-pipeline):` with a `Changelog:` trailer; no `version` or `CHANGELOG.md` edits.

## Implementation notes (non-binding detail, subordinate to the ACs above)

1. `plugins/dev-pipeline/tools/operator-override.sh` + `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh`,
   LOCKSTEP block `override-record-reader`: widen `OVERRIDE_GATES` with `design-disarm` and
   `OVERRIDE_SCOPES` with `design-disarm`; the gate is region-forbidden (issue-scoped, `region:
   none`), same shape as `intake-unqueued`. `cmd_check` gains `--print-ref`: on a hit, prints
   `<issue>#<n>` where `n` is the matching block's 1-indexed ordinal in file order.
2. `lean-gate.sh` `design_state()`: on a provider repo, `Design: none — <reason>` returns
   `disarmed` only when `operator-override.sh check --gate design-disarm --issue <n> --repo-root
   <root> --print-ref` returns 0 — the printed ref is threaded to the verdict writer; rc=1 → the
   existing milestone-1 error is extended to name the exact
   `bash <operator-override.sh> record --gate design-disarm --scope design-disarm --issue <n> …`
   invocation; rc=2 → unknown, red (a malformed record is not "no override", same posture as the
   existing malformed-region-override handling). The mid-run disarm lock
   (`design_disarm_locked_msg`) is unchanged. An unresolved `$ISSUE` on this path fails closed
   (not disarmed).
3. Verdict writer: `--fidelity not-applicable` on a disarmed-by-override run writes `fidelity:
   not-applicable (override: <record-id>)`. `header_key`'s charset already truncates the value at
   the first disallowed character, so every EXISTING `fidelity:` comparison (`= "pass"`, `!=
   "not-applicable"`) keeps working unchanged against the truncated `not-applicable` prefix — no
   widening needed there. A bare `not-applicable` on a provider repo with a `Design: none` spec
   with no valid override is refused at the writer (the gate knows the provider; the writer runs
   gate-side).
4. `lean-evidence.sh` arm 5 (`arm_override`, delegated in full by `check-lean-chain.sh`): when the
   loaded verdict's `fidelity:` header carries a `(override: <ref>)` suffix — read with a
   dedicated whole-value reader in the `panel_key` shape, since `header_key`'s charset would
   truncate it — the arm additionally resolves `<ref>` against the committed override record and
   requires that block to exist, name gate `design-disarm`, and belong to this issue; absent or
   mismatched → violation. This is IN ADDITION to the existing generic per-block validation, not a
   replacement for it.
5. Docs: `docs/config-schema.md` `design` row and `docs/live-render.md` state the override form;
   `plugins/dev-pipeline/skills/build-lean/SKILL.md` step 5 line ("Decide once: the disarm
   state-locks the moment milestone 3 arms.") gets the override instruction appended.
   `config-lint` is unchanged (nothing here is config-side).
6. Tests: per-tool cases in `operator-override-selftest.sh` for the new enum value (valid /
   malformed / wrong-gate ref); `lean-gate-selftest.sh` cases (no override / valid / malformed) for
   `design_state()`'s disarm-by-override arm; `lean-evidence-selftest.sh` / `check-lean-chain-selftest.sh`
   cases for the fidelity-ref arm (valid ref / absent record / wrong gate in the referenced block);
   `scenario-liveness-selftest.sh` (or the repo's current liveness-leg carrier) gains: provider
   repo + `Design: none` + no record → milestone 1 red naming the record command; with a valid
   record → disarmed, verdict carries the ref. Catalog rows per AC-5.

## Out of scope

The plan-review record (#710 / S-3), and whatever S-4 (#711) covers. `intake-unqueued` and
`spec-open-region` behavior is unchanged; only the closed enum widens.
