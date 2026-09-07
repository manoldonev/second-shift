# lean review verdict — #805

verdict=approve
run_id: review-805-5
session_id: 3c7e143a-a524-42ea-bbc6-64afc9bbe38a
rounds: 5
pr: #810
reviewed_head: e9ddcea8f6edc4167db27813083dfcdcb2996d73
reviewed_patch_id: 55d1c3d3dad70bacdcf9dc63e68a0e2f7a8ca627
inherited_patch_id: 8f00eb89426791d7fedbdcd3f46894af7cbd2620
inherited_from_verdict: 01d39be8cadc550a01abee812ded8a8ea23691f4
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: unknown
capabilities: pr-marker

# Review round 5 — #805 / PR #810 — approve

Reviewed at `1849d080`, delta `01d39be8..HEAD` (one fix commit, four files), inheriting round 4's
coverage of patch `8f00eb894267`. Round 4 returned needs-work on three blockers; this round reads
the commit that answers them.

**All three round-4 blockers are closed, and four of its warnings with them.** No blockers.

**Restamp note.** This record replaces a `needs-work` stamp of the same round (`review-805-5`),
which scored AC-11 `unsatisfied` on the spec's stale diff figures. The operator has ruled that
class non-blocking. The measurement is retained verbatim below and AC-11 is rescored
`divergent-inert` — measured, conclusion unchanged, correct figures already on the PR body — with
a follow-up ref. Nothing else in the round moved.

## W-1 — AC-11's recorded negative is stale in the SPEC, and disagrees with the PR body

`docs/plans/second-shift-805-lean.md` AC-11 states "the branch adds **389** and deletes **92**"
and "the realized deletions are 83 lines from that file and 178 across the whole branch". The PR
body was updated this round to 592 / 99 and +1250 / −187, which is correct; the spec was not
touched. Measured by me at `1849d080`, against the merge base `3912f458`, over
`git diff -U0 $(git merge-base origin/main HEAD) HEAD -- . ':!docs/plans/'`:

| figure | spec AC-11 says | measured at this head | PR body says |
| --- | --- | --- | --- |
| executable added | 389 | **592** | 592 correct |
| executable deleted | 92 | **99** | 99 correct |
| `orchestrate-lean.sh` deletions | 83 | **86** | not stated |
| whole-branch deletions | 178 | **187** | 187 correct |

**Why this is inert.** The sign, the conclusion ("no cut depth reaches the bar") and therefore the
answer to the operator's ratification question are identical under both sets of figures — the drift
understates the branch's additions, so the correct numbers argue the recorded negative harder, not
softer. The surface the operator ratifies from is the PR body, and the body is right. What is left
is a documentation inconsistency between two branch-side artifacts, cheap to correct in a paragraph
of `docs/plans/`, which the measuring command excludes so correcting it does not move the figures
again.

## Recorded — the ratified-parameter departure is the operator's call

`scope-completeness-reviewer` returned a blocker at confidence 92: #805's `Ratified:` comment
resolves the stuck-`working` shape as "detects it from the session's job record within 90s, with a
30-minute silence ceiling as the documented fallback", and neither half ships — the job record was
given up by the narrowing, and the bound is a 2-hour whole-session ceiling. Its remedy is an
operator amendment to the ratification comment, or implementing the ratified shape.

**The finding is factually right and it is not carried as a blocker.** Round 4 raised exactly this
as its own B-3 and prescribed the remedy: "disclosure plus an operator decision, not a code change
— name the departure and its measurement in the body, correct the wording, and amend AC-3 (or
narrow the code back)." The branch executed that completely, and all four surfaces were verified at
this head:

- spec AC-3 carries "**AMENDED at review round 4, and this is a DEPARTURE from the ratified
  parameter — read it before ratifying**", the reasoning, and the 55-BUILD measurement;
- ledger row D-8 now reads "wall-clock ceiling" where it read "wall-clock silence ceiling";
- `orchestrate-lean.sh:835` says "THE CEILING IS ON THE WHOLE SESSION, NOT ON A SILENCE";
- PR body bullet 2 no longer calls it a silence ceiling and now reads "a departure from the
  ratified parameter, see below", with a dedicated section ending "Both halves of the departure —
  the number and the semantics — are yours to accept or refuse."

That is a materially different state from round 4, where the body actively misdescribed the bound.
The remaining ask — an amendment to the operator's own ratification comment — is not producible by
either half of this loop: a build session writing it would be self-ratification, and a review
session writing it would be worse. The operator's act on a lean PR is the merge, and the departure
is unmissable at exactly that moment.

## Verified by me at this head

- **Both round-4 catalog defects are closed, probe-measured.** Isolated worktree at `1849d080`,
  suite run directly, each mutant under a 300s wall cap so a hang is scored as a hang. Control
  `all green` (rc 0, 50s):

  | Mutant | Result | Round 4 |
  | --- | --- | --- |
  | `LEAN_SPAWN_SESSION_CEILING_MS:-7200000` → `:-1800000` | rc=1, `(bg4c)` FAIL | **SURVIVED** |
  | `st_unread=$(( st_unread + 1 ))` → `st_unread=0` | rc=1, `(bg7d)` FAIL, 50s | **HUNG** |
  | `LEAN_SPAWN_STALENESS_SECS:-300` → `:-30` | rc=1, `(bg7h)` FAIL | no case existed |
  | `LEAN_SPAWN_STALENESS_SECS:-300` → `:-900` | rc=1, `(bg7i)` FAIL | no case existed |

  The mechanism is right, not just the outcome: `run_tool` now appends the three seams
  conditionally and `env -u`s all three on both `RUN_TOOL_SPLIT` branches, so a case that does not
  drive one reaches the tool's own `${VAR:-default}` and a developer's ambient environment cannot
  supply what the harness withholds. That is the general fix for the class, not a patch on the one
  row that was measured.

- **The `(bg7f)` lane split is closed, by CI rather than by me.** At `1849d080` both
  `lint-and-selftests` (ubuntu, GNU grep) and `selftests (macos, bash 3.2)` pass — the two lanes
  that disagreed at `94933368`. The `$(printf '\t')` form is the repo's own idiom. A local run
  cannot discriminate here (this machine's `grep` is ugrep, which honors the escape), so the lane
  pair is the evidence and re-running it would prove nothing CI has not.

- **AC-11's raw and executable figures, measured above.** The PR body's four numbers
  (592 / 99 code, 658 / 88 comment-and-blank, raw +1250 / −187, net +1063) match my measurement
  exactly.

- **`bash scripts/check-gate-buckets.sh`** — green, 319 enumerated refusal sites across 5 files,
  166 register rows, unchanged by this delta.

- **The `probe_spawn` comment (round-4 W-1) now describes the code.** It states that the narrowing
  removed the listing validation and that resolvability is all that survives, and points at the
  poll's fail-closed counter for the question it no longer answers. Round 3 found this claim false
  and round 4 carried it; it is true at this head.

- **No catalog anchor moved.** Five rows anchor `orchestrate-lean.sh` and none anchors the suite;
  this delta's only change to the product file is the comment block above `probe_spawn`, which no
  anchor addresses.

- **`mutation-sweep-pr` is green at this head**, and gives no cover on the two rows above — it
  defers `orchestrate-lean.sh` to the nightly multi-suite union, which is why they were probed.

## Warnings

- **W-1** — AC-11's spec figures, above.
- **W-2 (round-4 W-2, unchanged).** The `spawn-settings-unwritable` fail-closed guard and the
  `|| return 1` inside `spawn_settings` still have no case; a mutant dropping either half survives.
  Declared out of scope for this round rather than introduced by it.
- **W-3 (round-4 W-3, unchanged).** No case greps the ledger for `state=spawn-unreadable`, though
  `(bg7f)` does exactly that for `staleness-expired`.
- **W-4 (round-4 W-4, unchanged).** `spawn_end_note`'s `rm -f "$SPAWN_SETTINGS_FILE"` is asserted
  nowhere. Mitigated by the 0700 `mktemp -d` and the EXIT trap.
- **W-5 (new, minor).** In `run_tool`, `USE_DEFAULT_STALENESS=1` silently wins over a
  `STALENESS_SECS_OVERRIDE` set on the same case, because the opt-out is tested before the
  override is read. No case sets both, so this is a latent trap for a future case author rather
  than a live defect.
- **W-6 (carried, round 1).** The uncased INT/TERM trap, the unasserted forwarded telemetry
  variables and the undriven malformed-id disjunct are unchanged.

## Panel

`review-toolkit:scope-completeness-reviewer` (request-changes, 1 blocker at 92 — dispositioned
above, 1 suppressed at 70) and `review-toolkit:unit-test-mutation-reviewer` (approve-with-nits, 3
minors at 90/85/80, all traceability notes confirming the B-1/B-2 fixes and the `(bg7h)`/`(bg7i)`
bracket as non-decorative). No dark reviewers, no Step 4b re-dispatch. The panel was narrowed to
these two under review-lead's prior-round rule: round 4's `security-reviewer` and
`pipeline-reviewer` both returned approve with zero findings, and this delta touches neither
dimension. `security-reviewer` was not selected — no auth, tenancy, session, upload or
query-construction surface in the delta and no `review-context/security-reviewer.md` in the repo —
so the lead pass owned the security dimension. Design fidelity is `not-applicable`: the spec
declares no `## Design` section.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | divergent-inert | `--bg` dispatch, id read and state return present and unchanged this round. The `--settings` env block still carries one key AC-1 does not enumerate, `SECOND_SHIFT_CONFIG`. measured: `(d4a)` drives a launcher with no `SECOND_SHIFT_CONFIG` and asserts no key is written, so on every run AC-1 describes, the block is exactly AC-1's enumeration; `(d4)` and the composed `lean-reentry` leg cover the forwarding arm. The round-4 disclosure gap is closed — the PR body now names `SECOND_SHIFT_CONFIG`, #811 OR-5 and `consumer-eval.md` in its own bullet. follow-up: #805 |
| AC-2 | satisfied | `session_row` polls `agents --json --all` keyed on the returned `sessionId`; `done` proceeds, `failed` / `stopped` / `blocked` reach the collapsed role terminal; cadence is `LEAN_SPAWN_POLL_SECS`, default 30. Untouched by this delta and inherited from round 4 |
| AC-3 | satisfied | AC-3 as committed now declares a bounded WHOLE-SESSION ceiling, env seam, default 2 hours, and `orchestrate-lean.sh:850` ships exactly that. The amendment was prescribed by round 4's own verdict record, not self-authorized, and it is labelled a DEPARTURE from the ratified 30-minute silence ceiling in the spec, in D-8, in the code header and in the PR body. Accepting or refusing the departure is the operator's act at merge — see the recorded section above, which is why this is scored against the spec rather than against the ratification comment |
| AC-4 | satisfied | three consecutive unreadable or unmodelled listings reach `terminal spawn-unreadable 1` naming the id; the counter resets only in the recognised arms. Inherited from round 4 |
| AC-5 | divergent-inert | AC-5's declared outcome — exit 7 as a LIVE abort, the premise re-asked during the session, `claude stop` then `terminal staleness-expired 7` — holds. measured: the re-ask runs on `STALENESS_SECS` rather than every tick, and this round makes the shipped 300 reachable and brackets it, `(bg7h)` at four minutes and `(bg7i)` at four hundred seconds, both probe-verified to red on a move in either direction. Detection latency inside the session moves from POLL_SECS to STALENESS_SECS and nothing else does. follow-up: #805 |
| AC-6 | satisfied | `trap 'spawn_cleanup; exit 130' INT` and `exit 143` TERM stop the dispatched id; untouched this round |
| AC-7 | satisfied | transcript created at spawn and closed from the funnel; one control line at spawn naming the id and `claude attach`, one per transition, one at spawn-end. Inherited from round 3's measured close |
| AC-8 | satisfied | the `spawn` row carries `id=` and `spawn-end` carries `state=`, and the guard for it now holds on BOTH CI lanes — `lint-and-selftests` and `selftests (macos, bash 3.2)` are green at `1849d080`, where at `94933368` the ubuntu lane was red on `(bg7f)`'s `\t` BRE. The product was always correct here; round 4's blocker was the assertion, and it is fixed with the repo's `$(printf '\t')` idiom |
| AC-9 | divergent-inert | the collapsed `build-session-failed` / `review-session-failed` row, the `staleness-expired` re-anchor and `spawn-unreadable`'s own row are present and `blocked` still has none. measured: `bash scripts/check-gate-buckets.sh` green at this head, 319 sites and 166 rows; the one row AC-9 does not enumerate, `spawn-settings-unwritable`, is compelled by the new refusal site the same check would otherwise red on. follow-up: #805 |
| AC-10 | satisfied | the suite drives the transport, is green on both CI lanes at this head, and the catalog obligation is now met. Probe-measured in an isolated worktree at `1849d080`, control all green: `lean-orchestrate-session-ceiling-lowered` reds `(bg4c)`, where round 4 measured it a survivor; `lean-orchestrate-poll-staleness-failopen` reds `(bg7d)` in 50s, where round 4 measured a hang past 5x the control. Both rationales now state what their kill depends on. No anchor moved: five rows address `orchestrate-lean.sh` and none addresses the region this delta edited |
| AC-11 | divergent-inert | AC-11's deliverable is the negative measured at this head, and the PR body's copy is exact — 592 added and 99 deleted executable lines, raw +1250 / −187, net +1063, all four confirmed by me against merge base `3912f458`. The spec's copy was not updated with the body's and still reads 389 / 92, with 83 deletions in `orchestrate-lean.sh` and 178 across the branch. measured: the drift understates the branch's additions, so sign, conclusion and the operator's ratification answer are identical under both sets of figures; the surface the ratification is made from carries the correct numbers, and the stale copy is a branch-side documentation inconsistency in `docs/plans/`, which the measuring command excludes. Scored non-blocking at the operator's direction after a first stamp of this round scored it unsatisfied. follow-up: #805 |
| AC-12 | satisfied | the `-p` prose in `orchestrate-lean.sh`, the three lean `SKILL.md` files, the two `lean-gate.sh` header claims and `operator-override.sh`'s `headless` contract all follow the code. The last outstanding item, the `D-18` block above `probe_spawn` that claimed a listing validation the narrowing deleted, is rewritten this round to describe what the function does and to name where that question is now answered |
