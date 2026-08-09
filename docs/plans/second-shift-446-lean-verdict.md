# lean review verdict — #446

verdict=approve
run_id: review-446-1
session_id: 7fcb7c07-157a-4236-9195-ed7caee46b9a
rounds: 1
pr: #456
reviewed_head: e7c97a9f5da40c0d9dec301b75f3526e4a974d6b
reviewed_patch_id: cd82097647a8628b4e2d3330bf2c8b5f37d234cf
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review round 1 — PR #456 (issue #446)

Full-branch range (`c19f19e..HEAD`, chain root — nothing to inherit): 4 files, +447/−8.
Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.
a11y and design-fidelity were not routed: no changed path is a web component
(`stageParams.webComponentGlobs` is unset in this repo's config, so the shipped default
`apps/web/**/*.{tsx,jsx}` applies and matches nothing here).

**Verdict: approve.** No blockers. The fix is the right shape for the reported failure —
`mark` keeps writing the ambient session id (so a second build session still stamps its
own identity, the case D-4 exists for) and refuses when that session is not one the
harness recorded, which turns an uncorrectable mis-stamp into a recoverable refusal. The
issue's first suggested direction is rejected in the spec and in the code comment with a
concrete regression, not a preference.

### Verification performed in this review

- `lean-gate-selftest.sh` at this head, with `CLAUDE_CODE_SESSION_ID`/`RUN_ID` unset:
  **67 ran / 67 passed**, including all 11 new `(ms)` cases.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean.
- The `tools/mutation-catalog.tsv` row was applied **verbatim** from the file
  (`s#if ! session_in_build_set "\$msid"; then#if false; then#`) and is **KILLED** by
  five cases — (ms1), (ms2), (ms6), (ms8), (ms9).
- Three additional hand-probes against the new production lines; results in W1 and S1.
- CI on `e7c97a9`: `lint-and-selftests` green, `selftests (macos, bash 3.2)` green,
  `mutation-sweep-pr` green. `pr-gates` is red for the single expected pre-review reason —
  `no committed verdict record` — and no other arm. The PR marker is present and carries
  `session_id: da7d7b09-…`, matching the progress header, so the identity arm is clean.

### Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `build_session_set()` emits `record_key session_id` (header) then the `\| session \| <id>` rows, filtered through `awk '$0 != "" && $0 != "unset" && !seen[$0]++'`. |
| AC-2 | satisfied | `record_build_session` is called in `cmd_entry` **outside** the `if entry_row_present` branch; (ms3) drives a third session through the idempotent `entry` and marks with one attestation row on file. |
| AC-3 | satisfied | The call sits before the `TRACKER_TYPE = jira` early return, so both adapters reach it; (ms7) exercises the jira half. The github half is untested — see W1, which does not change this score. |
| AC-4 | satisfied | `record_build_session` has exactly two call sites (`cmd_entry:900`, `cmd_claim:928`). (ms6) pairs a review session's `bash G 4` with a subsequent refused `mark`; (ms11) pins the row count at 2 after every refused *and* successful `mark`. |
| AC-5 | satisfied | (ms1) rc=1 with an empty bot spool; (ms2) pins the ordering by consequence — a nonexistent `--pr-file` would `envfail` rc=2, and rc=1 proves the identity refusal ran first. |
| AC-6 | satisfied | (ms1) asserts all three D-8 fields: the ambient id, a recorded id, and the literal `CLAUDE_CODE_SESSION_ID=<id> bash G mark 8`. |
| AC-7 | satisfied | (ms8) no progress file; (ms9) header frozen at `unset` with an unset ambient session — both refuse with `recorded no build session`. The vacuity guard is genuinely load-bearing: dropping `$0 != "unset"` from the awk filter flips (ms9)'s message branch. |
| AC-8 | satisfied | (ms4) the second build session's marker carries `sess-mark-2` and not the header's `sess-mark-1`. |
| AC-9 | satisfied | The row is `<iso> \| session \| <id>` with no `session_id:` key. (ms5) uses two fixtures, and the header-less one is the discriminating case. Confirmed independently: `lean-gate.sh:373` `record_key` and `lean-reconcile.sh:174` `extract_key` are byte-identical extractions, so one assertion covers both readers. |
| AC-10 | satisfied | (ms10) a header-only progress file with no session rows marks successfully. |
| AC-11 | satisfied | Eleven `(ms)` cases spanning AC-2…AC-10, each setting `CLAUDE_CODE_SESSION_ID` explicitly via the opt-in `BUILD_SID`/`bgate` seam rather than a suite-wide export. Catalog row present and verified killed above. |
| AC-12 | satisfied | The pinned line-shape block gains `<iso> \| session \| <id>` plus the note on why it omits the `session_id:` key. `run-lean/SKILL.md` is untouched at 43 lines, inside the 60-line cap. |

12/12 satisfied. Nothing undeterminable.

### Warnings (non-blocking)

**W1 — AC-3's github half is untested; the mutant survives.** `lean-gate.sh:928`.
Confirmed by probe, not predicted: moving `record_build_session` inside the
`if [ "$TRACKER_TYPE" = "jira" ]` branch leaves the whole suite green (67/67). Both
`claim` call sites in the selftest are jira. The production code is correct and AC-3 is
met by reading it, which is why this is not a blocker — and the exposure is small, since
`claim` is gated by `require_entry_attested` and `entry` records unconditionally, so the
uncovered path only matters for a second session that runs `claim` without `entry`. Worth
one more case, or a catalog row, in a follow-up.

**W2 — `require_entry_attested`'s remedy text can steer a review session into
whitelisting itself.** `lean-gate.sh:2545`. `delta` is a review-role subcommand and is in
the `require_entry_attested` list; its refusal says *"Run `bash G entry $ISSUE`
(idempotent) and retry"* before it says the record may simply be out of reach. Before this
PR that advice was harmless. After it, a review session that follows the first line is
added to the build-session set and can then `mark` — reproducing exactly the mis-stamp
this PR removes. Not a blocker: `review-lean/SKILL.md` step 4 already forbids it
("re-run from the build worktree… if it is genuinely absent, hand it back"), the message's
fourth line says the same thing, and the wording predates this diff. But this PR is what
gives it teeth, so the message deserves a role-aware first line. Follow-up issue, not a
fix here.

**W3 — scope gate: issue #446's third suggested direction is neither implemented nor
deferred on the issue.** `scope-completeness-reviewer` returned `request-changes` at
confidence 85 over *"Consider widening the idempotence guard to `(run_id, session_id)`"*.
Downgraded to a warning rather than enforced as a hard gate, for two independent reasons:
the pre-flight ledger's **D-10 is `user-answered` and drops it** with a reason the diff
does not contradict (`arm_identity` compares every marker, so a corrective second marker
buys a duplicate comment and no recovery), and the issue itself prefaces the section with
"Not prescriptive — the shape is the point" and "Consider", which is not an acceptance
criterion. The reviewer's own calibration note agrees. Recommendation, for the tracker
rather than the branch: record the drop on #446 so the next reader does not re-derive it.

### Suggestions

**S1 — `session_in_build_set`'s literal-`unset` guard is an equivalent mutant.**
`lean-gate.sh:765`. Replacing `[ "$want" != "unset" ] || return 1` with `:` leaves the
suite green (67/67, verified). `build_session_set` already drops `unset` on the way in, so
the set can never contain it to match against. Harmless defense-in-depth; flagged only
because the repo's standing rule is that a line no case can fail is a line worth knowing
about. The *other* half of the AC-7 vacuity guard — the awk filter — is genuinely killed.

**S2 — the spec omits `## Design` entirely.** Not a gate violation: milestone 1 only
demands the section when `design.provider` is configured, and this repo configures none,
so fidelity is correctly `not-applicable`. Noted because the two most recent sibling specs
(`second-shift-443-lean.md`, `second-shift-447-lean.md`) both carry the explicit
`Design: none — <reason>` disarm, and matching them costs one line.

### Strengths

- **(ms2) pins ordering by consequence rather than by reading the source.** Pointing
  `--pr-file` at a nonexistent file and asserting rc=1 instead of rc=2 proves the identity
  refusal precedes the PR lookup, without asserting anything about line order.
- **(ms5) was rewritten after the first probe round showed it could not fail.** A
  header-bearing fixture wins the `session_id:` first-match race by position no matter how
  the row is spelled; the header-less fixture is the one where a row spelled
  `session_id: <id>` actually fabricates a build identity. The PR body reports that
  correction rather than quietly banking the assertion.
- **`BUILD_SID`/`bgate` is an opt-in seam, not a suite-wide export.** The comment names the
  earlier round that a global session id cost, and the four cases that need an identity
  take it one call at a time — the surrounding "the sweep runs with it unset" pin survives
  intact.
- **The fixtures drive the real `entry` rather than echoing progress rows.** A hand-written
  `| session | <id>` line would keep passing after the writer changed shape; three sessions
  through one run also produce the D-7 state (one attestation row, three usable
  identities) as a by-product rather than as a contrivance.
- **The rejected direction is documented where it will be re-proposed.** D-2 lives in the
  ledger, the spec, the commit body *and* the `WHY A SET RATHER THAN A LOOKUP` comment
  above the code — so the next reader who thinks "just read the header" finds the
  regression before writing it.
