# lean review verdict — #379

verdict=approve
run_id: review-379-2
session_id: d9c2c3e8-b569-4ac5-bc80-58ea0065f479
rounds: 2
pr: #383
reviewed_head: 5150eeee661664e02e429191a99e61063105e2e0
reviewed_patch_id: f320e928ce9fe376d6ae1dd9a961c0e799de4a91
inherited_patch_id: 4d19b07f4f5aabb7d92a2541b9ea79db8d6e4a07
inherited_from_verdict: 2ef26930cb23b50d3dcc0015d3a79b7ee01bb750
model: unknown

# review-lean round 2 — PR #383 (issue #379)

Range reviewed: `2ef2693..HEAD` (delta since round 1's verdict), plus a re-read of round 1's
findings and a full independent re-verification (shellcheck, jq, all 63 `*-selftest.sh`
suites, lockstep, frozen-files) rather than trusting the inherited coverage alone.

## Verdict: approve

Round 1's sole blocker — AC-9's `lanes[]` seam-scrub call site had zero selftest coverage —
is closed by this round's only commit. No other change is in the delta.

## Findings

No blockers.

### Round-1 blocker: closed

- **[Test coverage / AC-9]** `5150eee` adds case `(i12b)` to `lean-gate-selftest.sh`, mirroring
  `(i12)`/`(i13)`: it populates `commands.acme.lanes` with a `{"command": "... SCRUBBED ...
  || echo LEAKED"}` entry and asserts the gate prints line-anchored `SCRUBBED` with no
  `LEAKED`. Verified: this is the exact call site cmd_3 reads via
  `(.commands[$s].lanes // []) | .[] | (.command // .)` (lean-gate.sh:936) and executes through
  the same seam-scrubbed `env ${SEAM_SCRUB_ENV[@]} bash -c "$cmd"` wrapper (lean-gate.sh:934)
  as the fixed-key and extraLanes children. Ran the suite myself:
  `(i12b) AC-9: a lanes[] lane child runs with SECOND_SHIFT_CONFIG stripped` — PASS, alongside
  all other 100+ cases, 0 FAIL markers. AC-9 now has selftest coverage for all three named
  lane-child kinds (fixed keys, `lanes[]`, extraLanes), closing the gap verbatim as round 1's
  blocker asked.
- The commit carries `Changelog: none` (test-only, no consumer-visible behavior change) — no
  changelog-trailer gate issue.
- The commit touches exactly one file (`lean-gate-selftest.sh`); `lean-gate.sh` itself is
  unchanged in this delta, so no new mutation-sweep run is owed — round 1's survivor claim
  (3 rows, byte-identical to `tools/mutation-baseline.tsv`, all above `cmd_3`) is unaffected by
  a test-only round 2.

### Round-1 warnings: not re-litigated

Round 1 raised four non-blocking warnings (AC-5(b)/(c) coverage gap, pre-existing untested
`typecheck` key, partial `SEAM_SCRUB` token assertion, mutation-survivor claim) and verified
each was behaviorally correct despite the coverage gaps. None of them are touched by this
delta, so they carry forward unchanged — still warnings, still not blocking.

### Out-of-scope check

No violations. The delta is a single, minimal test addition; no production code, no new
config keys, no scope creep beyond the named AC-9 gap.

## AC-1..AC-10 scoring (full spec, this round)

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | unchanged since round 1 (`(i2)`/`(i3)`) |
| AC-2 | satisfied | unchanged since round 1 (`(i4)`) |
| AC-3 | satisfied | unchanged since round 1 (`(i5)`/`(i6)`) |
| AC-4 | satisfied | unchanged since round 1 (`(i14)`/`(i15)`) |
| AC-5 | satisfied | unchanged since round 1 (clause (a) pinned; (b)/(c) verified by hand) |
| AC-6 | satisfied | unchanged since round 1 (`(i7)`); new `(i12b)` case slots between `(i12)` and `(i13)` without disturbing the asserted ordering |
| AC-7 | satisfied | unchanged since round 1 (`(i8)`/`(i9)`/`(i10)`) |
| AC-8 | satisfied | unchanged since round 1 (`(i11)`) |
| AC-9 | **satisfied** | fixed-key (`i12`), `lanes[]` (`i12b`, new this round), extraLanes (`i13`) — all three lane-child kinds now pinned |
| AC-10 | satisfied | unchanged since round 1 (`(i-AC10)`) |

## Verification run myself this round

- `lean-gate-selftest.sh`: green, including new case `(i12b)`.
- Repo-wide: `shellcheck -e SC1091,SC2015,SC2181` on every `*.sh` (0 findings), `jq empty` on
  every `*.json` (clean), all 63 `*-selftest.sh` suites via `bash {}` (matching CI's
  invocation, not direct exec — sidesteps a pre-existing, PR-unrelated missing +x bit on
  `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` that both this worktree and
  `origin/main` already carry), `-P 4`, **without** `SKIP_STRESS`, `env -u
  CLAUDE_CODE_SESSION_ID` — 0 nonzero exits across all 63.
- `scripts/check-lockstep-pairs.sh`: PASS, 16/16 pairs including `seam-scrub-lean`.
- `scripts/check-frozen-files.sh origin/main`: clean.
- Confirmed the delta touches only `lean-gate-selftest.sh`; `lean-gate.sh` (the guard) is
  byte-identical to round 1's reviewed head, so the mutation-sweep survivor claim from round 1
  stands unchanged.
