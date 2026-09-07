# lean review verdict — #805

verdict=approve
run_id: review-805-6
session_id: 3c7e143a-a524-42ea-bbc6-64afc9bbe38a
rounds: 6
pr: #810
reviewed_head: a860f4c508c49ef6be49c9964f54e1152539d4b0
reviewed_patch_id: 702a46a8549c93cc7c3ce04b321137e4337e4523
inherited_patch_id: 8f00eb89426791d7fedbdcd3f46894af7cbd2620
inherited_from_verdict: 01d39be8cadc550a01abee812ded8a8ea23691f4
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: unknown
capabilities: pr-marker

# Review round 6 — #805 / PR #810 — approve

## READ THIS FIRST — PART OF THIS PATCH WAS AUTHORED BY THIS ROUND

**`a860f4c5` was written by this review session, not by a build session.** It is 7 added lines
across `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` and
`tools/lane-bench-classes.tsv`, closing an integration red that the base merge with `main` exposed.
This record therefore does **not** carry independent review of those 7 lines — their author graded
them. It is stamped at the operator's explicit direction, and the limitation is stated here rather
than left for a reader to infer, because no gate in this repo can detect it. Everything else below
is independent review of code this session did not write.

Reviewed at `a860f4c5`. Round 5 read `01d39be8..1849d080` (one fix commit, four files), inheriting
round 4's coverage of patch `8f00eb894267`, and approved it. Two commits landed after that stamp and
voided it: the base merge `2d282654`, and the self-authored integration fix `a860f4c5`.

**Stamp history.** Round 5 was stamped `needs-work` on AC-11's stale spec figures, then restamped
`approve` at the operator's direction with AC-11 rescored `divergent-inert`. That record was voided
by the two commits named above. This round re-stamps at the merged head, also at the operator's
direction, with no further review round.

## The base merge, and the integration red it exposed

`main` advanced to `a490c242` (#809, #814) mid-round and the branch went `CONFLICTING`. An
unmergeable PR gets zero CI, which is why no checks ran on the round-5 stamped head.

- **`2d282654`** merges `origin/main` in, not a rebase. The single conflict,
  `tools/mutation-catalog.tsv`, was an append/append collision — this branch adds 2 rows and deletes
  0, `main` adds 4 and deletes 0 — resolved as the pure union and verified one-directional against
  each parent. It altered no reviewed line, and `check-lean-chain.sh` confirmed the round-5 record
  survived it on contribution-state grounds.
- **`a860f4c5`** closes the red that merge exposed. `tools/lane-bench-selftest.sh` `(j2)`, shipped
  by #814, derives the lane's terminal-slug vocabulary by grepping command-position
  `terminal <slug>` sites out of the shipped scheduler, and requires `tools/lane-bench-classes.tsv`
  to name exactly that set in both directions. This branch broke it both ways at once: it adds two
  literal slugs the table never saw (`spawn-unreadable`, `spawn-settings-unwritable`), and it
  collapses `terminal build-session-failed` / `terminal review-session-failed` into
  `terminal "$lower-session-failed"`, which no static reader can see. `main` was green at
  `a490c242` and this branch green at `1849d080`; only the pair reds. The fix adds the two table
  rows as `lane-error`, matching every sibling refusal row, and announces the two composed names
  with the scheduler's own `terminal-vocabulary:` prefix — the mechanism that table's header
  documents for exactly this case, and the one `review-skipped-approved` already uses. Deleting the
  two rows would have been green and wrong: both slugs still reach the launch ledger at runtime, so
  the bench would have been left unable to classify two terminals that genuinely fire.

  **This is the self-authored commit.** Verified, but by its own author: `lane-bench-selftest.sh`
  23 pass / 0 fail, `orchestrate-lean-selftest.sh` all green, shellcheck clean.

## CI at this exact head

`lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS, `mutation-sweep-pr` SUCCESS.
`pr-gates` is red only because the record it reads was the voided round-5 one; this stamp is what
answers it. All three correctness lanes are green on the merged tree, which is the first time any
lane has run on a head carrying both `main`'s advance and this branch.

## W-1 — AC-11's recorded negative is stale in the SPEC, and disagrees with the PR body

`docs/plans/second-shift-805-lean.md` AC-11 states "the branch adds **389** and deletes **92**" and
"the realized deletions are 83 lines from that file and 178 across the whole branch". The PR body
was updated to 592 / 99 and +1250 / −187, which is correct; the spec was not touched. Measured at
`1849d080` against merge base `3912f458`, over
`git diff -U0 $(git merge-base origin/main HEAD) HEAD -- . ':!docs/plans/'`:

| figure | spec AC-11 says | measured | PR body says |
| --- | --- | --- | --- |
| executable added | 389 | **592** | 592 correct |
| executable deleted | 92 | **99** | 99 correct |
| `orchestrate-lean.sh` deletions | 83 | **86** | not stated |
| whole-branch deletions | 178 | **187** | 187 correct |

**Why this is inert.** The sign, the conclusion ("no cut depth reaches the bar") and therefore the
answer to the operator's ratification question are identical under both sets of figures — the drift
understates the branch's additions, so the correct numbers argue the recorded negative harder, not
softer. The surface the operator ratifies from is the PR body, and the body is right. What is left
is a documentation inconsistency between two branch-side artifacts.

## Recorded — the ratified-parameter departure is the operator's call

`scope-completeness-reviewer` returned a blocker at confidence 92: #805's `Ratified:` comment
resolves the stuck-`working` shape as "detects it from the session's job record within 90s, with a
30-minute silence ceiling as the documented fallback", and neither half ships — the job record was
given up by the narrowing, and the bound is a 2-hour whole-session ceiling. Its remedy is an
operator amendment to the ratification comment, or implementing the ratified shape.

**The finding is factually right and it is not carried as a blocker.** Round 4 raised exactly this
as its own B-3 and prescribed the remedy: disclosure plus an operator decision, not a code change.
The branch executed that completely, and all four surfaces were verified: spec AC-3 carries the
`AMENDED … DEPARTURE … read it before ratifying` header and the 55-BUILD measurement; ledger row
D-8 reads "wall-clock ceiling"; `orchestrate-lean.sh:835` says the ceiling is on the whole session,
not on a silence; and the PR body names it a departure with a section ending "Both halves of the
departure — the number and the semantics — are yours to accept or refuse." The remaining ask is not
producible by either half of this loop, and the operator's act on a lean PR is the merge.

## Verified independently — code this session did not write

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

- **The `(bg7f)` lane split is closed, by CI rather than by me.** Both `lint-and-selftests` (ubuntu,
  GNU grep) and `selftests (macos, bash 3.2)` pass — the two lanes that disagreed at `94933368`. A
  local run cannot discriminate here (this machine's `grep` is ugrep, which honors the escape), so
  the lane pair is the evidence.

- **`bash scripts/check-gate-buckets.sh`** — green, 319 enumerated refusal sites across 5 files,
  166 register rows.

- **The `probe_spawn` comment (round-4 W-1) now describes the code.** It states that the narrowing
  removed the listing validation and that resolvability is all that survives, and points at the
  poll's fail-closed counter for the question it no longer answers. Round 3 found this claim false
  and round 4 carried it; it is true at this head.

- **No catalog anchor moved.** Five rows anchor `orchestrate-lean.sh` and none anchors the suite.

## Warnings

- **W-1** — AC-11's spec figures, above.
- **W-2 (round-4 W-2, unchanged).** The `spawn-settings-unwritable` fail-closed guard and the
  `|| return 1` inside `spawn_settings` still have no case; a mutant dropping either half survives.
- **W-3 (round-4 W-3, unchanged).** No case greps the ledger for `state=spawn-unreadable`, though
  `(bg7f)` does exactly that for `staleness-expired`.
- **W-4 (round-4 W-4, unchanged).** `spawn_end_note`'s `rm -f "$SPAWN_SETTINGS_FILE"` is asserted
  nowhere. Mitigated by the 0700 `mktemp -d` and the EXIT trap.
- **W-5.** In `run_tool`, `USE_DEFAULT_STALENESS=1` silently wins over a `STALENESS_SECS_OVERRIDE`
  set on the same case, because the opt-out is tested before the override is read. No case sets
  both — a latent trap for a future case author.
- **W-6.** `a860f4c5`'s announcement prints both composed slug names on any role-session failure,
  so an operator reading that path sees the name that did not fire beside the one that did. It is
  one line of explanatory output on a failure path, and it is the price of the vocabulary being
  statically derivable. Unreviewed independently — see the header.
- **W-7 (carried, round 1).** The uncased INT/TERM trap, the unasserted forwarded telemetry
  variables and the undriven malformed-id disjunct are unchanged.

## Panel

`review-toolkit:scope-completeness-reviewer` (request-changes, 1 blocker at 92 — dispositioned
above, 1 suppressed at 70) and `review-toolkit:unit-test-mutation-reviewer` (approve-with-nits, 3
minors at 90/85/80, all traceability notes confirming the fixes and the `(bg7h)`/`(bg7i)` bracket as
non-decorative). No dark reviewers, no Step 4b re-dispatch. The panel ran against `1849d080` and was
narrowed under review-lead's prior-round rule: round 4's `security-reviewer` and `pipeline-reviewer`
both returned approve with zero findings, and that delta touched neither dimension.
`security-reviewer` was not selected — no auth, tenancy, session, upload or query-construction
surface — so the lead pass owned the security dimension. **No panel ran against `a860f4c5`.** Design
fidelity is `not-applicable`: the spec declares no `## Design` section.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | divergent-inert | `--bg` dispatch, id read and state return present and unchanged. The `--settings` env block still carries one key AC-1 does not enumerate, `SECOND_SHIFT_CONFIG`. measured: `(d4a)` drives a launcher with no `SECOND_SHIFT_CONFIG` and asserts no key is written, so on every run AC-1 describes, the block is exactly AC-1's enumeration; `(d4)` and the composed `lean-reentry` leg cover the forwarding arm. The PR body now names `SECOND_SHIFT_CONFIG`, #811 OR-5 and `consumer-eval.md` in its own bullet. follow-up: #805 |
| AC-2 | satisfied | `session_row` polls `agents --json --all` keyed on the returned `sessionId`; `done` proceeds, `failed` / `stopped` / `blocked` reach the collapsed role terminal; cadence is `LEAN_SPAWN_POLL_SECS`, default 30 |
| AC-3 | satisfied | AC-3 as committed declares a bounded WHOLE-SESSION ceiling, env seam, default 2 hours, and `orchestrate-lean.sh:850` ships exactly that. The amendment was prescribed by round 4's own verdict record, not self-authorized, and the departure from the ratified 30-minute silence ceiling is labelled in the spec, in D-8, in the code header and in the PR body. Accepting or refusing it is the operator's act at merge |
| AC-4 | satisfied | three consecutive unreadable or unmodelled listings reach `terminal spawn-unreadable 1` naming the id; the counter resets only in the recognised arms |
| AC-5 | divergent-inert | AC-5's declared outcome — exit 7 as a LIVE abort, the premise re-asked during the session, `claude stop` then `terminal staleness-expired 7` — holds. measured: the re-ask runs on `STALENESS_SECS` rather than every tick, and the shipped 300 is now reachable and bracketed, `(bg7h)` at four minutes and `(bg7i)` at four hundred seconds, both probe-verified to red on a move in either direction. Detection latency inside the session moves from POLL_SECS to STALENESS_SECS and nothing else does. follow-up: #805 |
| AC-6 | satisfied | `trap 'spawn_cleanup; exit 130' INT` and `exit 143` TERM stop the dispatched id |
| AC-7 | satisfied | transcript created at spawn and closed from the funnel; one control line at spawn naming the id and `claude attach`, one per transition, one at spawn-end |
| AC-8 | satisfied | the `spawn` row carries `id=` and `spawn-end` carries `state=`, and the guard for it holds on BOTH CI lanes — `lint-and-selftests` and `selftests (macos, bash 3.2)` are green at this head, where at `94933368` the ubuntu lane was red on `(bg7f)`'s `\t` BRE. The product was always correct here; round 4's blocker was the assertion, fixed with the repo's `$(printf '\t')` idiom |
| AC-9 | divergent-inert | the collapsed `build-session-failed` / `review-session-failed` row, the `staleness-expired` re-anchor and `spawn-unreadable`'s own row are present and `blocked` still has none. measured: `bash scripts/check-gate-buckets.sh` green, 319 sites and 166 rows; the one row AC-9 does not enumerate, `spawn-settings-unwritable`, is compelled by the new refusal site the same check would otherwise red on. A SECOND register, `tools/lane-bench-classes.tsv`, arrived from main mid-round and needed the same reconciliation — done in `a860f4c5`, self-authored. follow-up: #805 |
| AC-10 | satisfied | the suite drives the transport, is green on both CI lanes, and the catalog obligation is met. Probe-measured in an isolated worktree at `1849d080`, control all green: `lean-orchestrate-session-ceiling-lowered` reds `(bg4c)`, where round 4 measured it a survivor; `lean-orchestrate-poll-staleness-failopen` reds `(bg7d)` in 50s, where round 4 measured a hang past 5x the control. Both rationales now state what their kill depends on. No anchor moved |
| AC-11 | divergent-inert | the PR body's copy is exact — 592 added and 99 deleted executable lines, raw +1250 / −187, net +1063, all four confirmed against merge base `3912f458`. The spec's copy still reads 389 / 92, with 83 deletions in `orchestrate-lean.sh` and 178 across the branch. measured: the drift understates the branch's additions, so sign, conclusion and the operator's ratification answer are identical under both sets; the surface the ratification is made from carries the correct numbers, and the stale copy is a branch-side documentation inconsistency. Scored non-blocking at the operator's direction. follow-up: #805 |
| AC-12 | satisfied | the `-p` prose in `orchestrate-lean.sh`, the three lean `SKILL.md` files, the two `lean-gate.sh` header claims and `operator-override.sh`'s `headless` contract all follow the code. The `D-18` block above `probe_spawn` that claimed a listing validation the narrowing deleted now describes what the function does and names where that question is answered |
