# lean review verdict — #379

verdict=needs-work
run_id: review-379-1
session_id: 9c84afd0-688c-417b-8b9e-c8184a12d32e
rounds: 1
pr: #383
reviewed_head: 6d0206ee660e0be3fc26b53e23e338a345b30e4e
reviewed_patch_id: 4d19b07f4f5aabb7d92a2541b9ea79db8d6e4a07
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

# review-lean round 1 — PR #383 (issue #379)

Range reviewed: `3308d7a..HEAD` (whole branch — round 1, nothing to inherit).

## Verdict: needs-work

One AC-9 gap is a genuine, spec-literal blocker (see below); everything else checks out,
including a full green repo sweep I ran myself (shellcheck, jq, all 63 `*-selftest.sh`
suites) on top of the reviewer fan-out (7 specialists via `code-review.mjs`).

## Findings

### Blocker

- **[Test coverage / AC-9] `lean-gate.sh` — the `lanes[]` seam-scrub call site has zero
  selftest coverage.** AC-9 names three "lane children" — fixed keys, `lanes[]`, `extraLanes`
  — and requires the seam-var stripping be "pinned by a selftest case" for each. Only 2 of 3
  are: `(i12)` pins the fixed-key child, `(i13)` pins the extraLanes child. Grepped both
  `lean-gate-selftest.sh` and `scenario-liveness-selftest.sh` for any reference to
  `commands.acme.lanes` — there is none; no fixture in either file ever populates a `lanes[]`
  entry, so the `env ${SEAM_SCRUB_ENV[@]+...} bash -c "$cmd"` conversion at that call site
  (lean-gate.sh, `lanes[]` setup loop) is entirely unexercised.
  I verified independently that the code itself is correct — built a fixture with
  `commands.acme.lanes: [{"command": "[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED
  || echo LEAKED"}]` and confirmed the gate prints `SCRUBBED`. So this is not a functional
  bug; it is a missing regression guard on a claim the PR's own Testing section states it
  covers ("one case per AC (AC-1 through AC-10)"), which is not accurate for AC-9's `lanes[]`
  sub-case. Fix: add an `(i)`-style case mirroring `(i12)`/`(i13)` that populates
  `commands.acme.lanes` with a scrub-check command and asserts `SCRUBBED`/no `LEAKED`, the
  same pattern already used for the other two lane-child kinds.

### Warnings (not blocking — behavior verified correct by hand)

- **[Test coverage] AC-5's "progress file gains no new lines beyond today's" clause is
  asserted nowhere.** `(i-AC5)` only checks that no `extra lane` token appears in output; no
  case captures the progress file's line count/content before and after a no-`extraLanes`
  `gate 3` run. I verified the underlying claim directly: ran both the pre-PR (`3308d7a`) and
  post-PR `lean-gate.sh` against an identical fixture (no `extraLanes` key) and diffed the
  resulting progress files — byte-identical modulo timestamp (`milestone-3 | skipped |
  mutation-sweep.sh absent` + `milestone-3 | satisfied`, nothing else, in both). AC-5 is
  satisfied; a dedicated before/after assertion would still be good practice as a future
  regression guard.

- **[Pre-existing, not introduced by this diff] `typecheck` fixed key never exercised with a
  real command.** Every fixture in both selftest files sets `"typecheck": null`. Confirmed via
  `git show 3308d7a:...lean-gate-selftest.sh` that this predates the diff — the `build`
  removal (`for key in lint typecheck test build` → `for key in lint typecheck test`) is the
  only change to that loop, and it does not touch how `typecheck` itself is tested. Not this
  PR's gap to close.

- **[Minor] Only 1 of 13 `SEAM_SCRUB` tokens (`SECOND_SHIFT_CONFIG`) is directly asserted by a
  selftest.** The other 12 rely on `scripts/lockstep-manifest.tsv`'s new `seam-scrub-lean` row
  (verified: I ran `scripts/check-lockstep-pairs.sh` myself — PASS, `lean-gate.sh` ==
  `verifyctl.sh` on the `seam-scrub` LOCKSTEP block) plus CI running that check directly. A
  real, if indirect, backstop exists — low severity.

- **[Confirmed, no action needed] Mutation-sweep survivor claim.** The PR states 3 survivors
  (`lean-gate.sh::cmp-eq::1`, `::default::1`, `::default::2`) are byte-identical to existing
  `tools/mutation-baseline.tsv` rows and pre-date this diff's insertion point. Independently
  confirmed: all three rows exist verbatim in the baseline file, and `origin/main`'s copy of
  `lean-gate.sh` has those sites at lines 107/108/124 — in the file header, well above `cmd_3`
  (~line 877). Claim checks out; no re-baseline owed.

### Out-of-scope check

No violations. No `format` key, no advisory mode, no failure-taxonomy import, no inert lane,
no design/ticket awareness added to the gate, no config-lint invocation from the gate.

### Lockstep-manifest cross-check

`seam-scrub-lean` row (`verbatim`, `lean-gate.sh`'s `seam-scrub` block vs `verifyctl.sh`'s):
confirmed byte-identical by diffing both `SEAM_SCRUB=` lines directly, and
`scripts/check-lockstep-pairs.sh` passes clean (0 failed / 16 pairs, including this new row).

## AC-1..AC-10 scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `(i2)`/`(i3)`: no-`when` lane runs; failing lane reds naming lane+command |
| AC-2 | satisfied | `(i4)`: multi-command lane stops at first non-zero, later commands never run |
| AC-3 | satisfied | `(i5)`/`(i6)`: non-matching `when` against a real non-empty diff — printed skip + pinned progress line |
| AC-4 | satisfied | `(i14)`/`(i15)`: `src/**/*.tsx` dialect proven both negative (top-level) and positive (nested) |
| AC-5 | satisfied | `(i-AC5)` for clause (a); clauses (b)/(c) verified by hand (see Warnings) — behaviorally correct, coverage gap noted as a warning |
| AC-6 | satisfied | `(i7)`: line-number ordering assertion, fixed keys < extraLane < mutation sweep |
| AC-7 | satisfied | `(i8)`/`(i9)`/`(i10)`: non-object, missing-name, empty-commands all red naming the index |
| AC-8 | satisfied | `(i11)`: unresolvable `origin/main` fail-closed refusal, not a silent skip |
| AC-9 | **unsatisfied (partial)** | fixed-key + extraLanes children pinned and correct; `lanes[]` child scrub is behaviorally correct (verified by hand) but has zero selftest coverage — see Blocker |
| AC-10 | satisfied | `(i-AC10)` + confirmed no stale `build`-key references anywhere else in the diff |

## Verification run myself (beyond the reviewer fan-out)

- `lean-gate-selftest.sh`, `scenario-liveness-selftest.sh`: green.
- Repo-wide: `shellcheck` (0 findings), `jq empty` on every `*.json` (clean), all 63
  `*-selftest.sh` suites (`-P 4`, `SKIP_STRESS=1`, `env -u CLAUDE_CODE_SESSION_ID`) — 0 FAIL
  markers, exit 0.
- `scripts/check-lockstep-pairs.sh`: PASS.
- Manual fixture runs (documented above) for AC-5(b) and AC-9 (`lanes[]`).

## Reviewer fan-out (review-toolkit:review-lead, 7 specialists)

Security, performance, maintainability, complexity, test-coverage: all **approve**, no
findings. `unit-test-mutation-reviewer`: **approve-with-nits** (the `typecheck`/`lanes[]`/
partial-SEAM_SCRUB-token findings folded in above). `scope-completeness-reviewer`: flagged the
AC-5/AC-9 gaps addressed above, plus confirmed no other scope item is missing.
