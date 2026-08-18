# lean review verdict — #574

verdict=approve
run_id: review-574-2
session_id: 0b3ca40f-40e1-42e0-8292-a6cdfd179d6c
rounds: 2
pr: #584
reviewed_head: 001e58193f8be28f0f9aadb5219b79c375b3a7de
reviewed_patch_id: 20f6985d6aea12f54f51d1d73648de5c734a8e60
inherited_patch_id: e311e9ed3caf4816c60f6d3ce76f0d3cef91a036
inherited_from_verdict: 90b7d6a122e658b0765665441caa819b4a9357f4
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #584 (issue #574), range 90b7d6a..001e581 (delta round, inheriting patch e311e9ed3caf)

Verdict: **approve** — all round-1 findings closed, no new findings. All seven ACs score
satisfied.

Panel: 4/4 spawned, none dark (security, performance, maintainability, scope-completeness —
reduced round-2 lineup per prior-round rules: r1's panel was 6/6 all-approve, the r1 blocker
was the round's own finding, and the delta touches no complexity/test-coverage surface) —
all approve. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`).

## Round-1 findings — disposition

| # | r1 severity | Disposition |
| --- | --- | --- |
| B1 (Changelog trailer omits the breaking retirement) | Blocker | **CLOSED.** Fix commit 001e581 carries `Changelog: BREAKING — …` naming both retired keys, the by-name config-lint rejection, and a `Migration:` line. Proven by running `derive-release.sh`'s own `extract_trailers` awk over the commit body: the full block, `Migration:` included, renders as one release-notes bullet (indented continuations are in-block; no blank line splits it). The major bump itself comes from 8e3c6a5's `feat!` subject; the notes now carry the breaking prose r1 found missing. |
| W1 (doctor's live `testFile` read) | Warning | **CLOSED.** `.testFile` removed from the CMD_TOOLS jq projection (pipeline-doctor.sh:113); `pipeline-doctor-selftest.sh` 42/42 green at head; tree-wide sweep shows no surviving live read of either retired key (remaining hits are history comments in config-diff-guard.sh / check-config-shadowing.sh). |
| W2 (stale model-table census comments) | Warning | **CLOSED.** Doctor 5g and stall-probe.mjs now state the two-map census (REVIEWER_MODEL in code-review.mjs, INTAKE_MODEL in intake-review.mjs) — verified against check-model-tiers.sh's own table registry; stall-probe's known-gap paragraph is preserved, now census-accurate. |
| S1 (`check-model-tiers.sh::cmp-eq::2` stale-candidate row) | Suggestion | OPEN, advisory, unchanged — keep-until-nightly posture stands; no nightly has run since r1. |
| P1 (native-primitive-audit stale v1 rows) | Pre-existing | Carried — point-in-time record, not a #574 regression. |

## New findings this round

None at threshold. One informational nit (scope-completeness, conf 95): the round-2
dispatch named the r1 verdict commit as the diff base — correct for a delta round's READ
range, and the reviewer independently re-derived the true merge-base (a30c29b) and
re-verified scope there: all 9 extracted scope items satisfied, the one deferral explicit in
the issue body. No code defect. Security's one suppressed note (conf 30) records that the
delta narrows, not widens, the pre-existing config-read pattern.

## Obligations check (delta-incurred)

- **Mutation ordinals: zero re-keys.** All six generic operators' matched-line sequences
  over `pipeline-doctor.sh` are byte-identical base→head (cmp-z 13/13, default 13/13,
  detector 13/13, cmp-eq 2/2, logic 27/27, fail-open 0/0) — the jq-projection edit and the
  5g comment rewrite match no operator site. No `mutation-catalog.tsv` row anchors either
  changed file; `stall-probe.mjs` is outside the shell sweep. The untouched baseline is
  correct.
- shellcheck clean on pipeline-doctor.sh; stall-probe.mjs delta is comments-only (its
  top-level-return shape is the workflow-runtime contract, identical at base).

## Per-AC scoring (all against the committed spec `docs/plans/second-shift-574-lean.md`, first commit, never amended)

- **AC-1 — satisfied** (inherited; delta does not touch the deleted-engine surface).
- **AC-2 — satisfied** (inherited; cost-block strip untouched this round).
- **AC-3 — satisfied**, now fully: r1's residue (W1, the last advisory reader of
  `testFile`) is closed in this delta; schema/config-lint/migration-doc/config-grill
  unchanged and green.
- **AC-4 — satisfied** (inherited; parity rows untouched).
- **AC-5 — satisfied** (inherited; tier-guard shrink untouched; W2's census comments now
  agree with the shrunken guard).
- **AC-6 — satisfied** (inherited; docs re-pointing untouched).
- **AC-7 — satisfied** (inherited; registers untouched this round, and the delta was proven
  to incur no new register obligations — see obligations check).

## CI on the reviewed head (001e581)

`lint-and-selftests` success — closing r1's carried "check its conclusion" item;
`mutation-sweep-pr` success; `selftests (macos, bash 3.2)` success; `pr-gates` failure
confined to the `lean chain reconciliation` arm reading the standing r1 needs-work record —
the expected pre-approve state this record supersedes; `release-pr-gates` skipped. The
cancelled runs on 67d516c/90b7d6a are the #576 verdict-push/next-push cancellation design,
not flakes.

## Design fidelity

not-applicable — unchanged from r1: the spec declares no `## Design` section ("No
user-facing UI surface"), and the repo config declares no design provider, so the disarm is
justified.
