# #866 — Record-form defects and stale-verdict merges must not cost, or skip, a review round

Two record-form causes cost review rounds that change no production code: a render receipt that
went stale after milestone 3, and an intent-gap record waiting on a ratification that happens
outside the tree. This change stops the first at the build's handoff and removes the wait from the
second by making delegated ratification the documented path. The stale-verdict half (b) needs no
code: the shipped freshness arm already refuses it wherever consumers install the boundary check.

## Acceptance criteria

- **AC-1** — A direct `bash G mark <issue>` on an armed spec refuses when the committed render
  receipt's `rendered_from` differs from the branch's current render patch identity. It exits
  non-zero, posts nothing, and prints milestone 4's existing stale-receipt refusal. It refuses
  whether or not a bot is configured. An unarmed spec, a receipt that matches, and the
  close-out path (`cmd_5`/`cmd_close_out` call `cmd_mark` as a function) are unaffected.
- **AC-2** — The stale-receipt refusal text is defined once and read by both milestone 4 and the
  `mark` guard. No refusal string is added or reworded, and the (ac1) milestone-4 site count is
  unchanged.
- **AC-3** — A gate selftest scenario covers AC-1. A direct `mark` on an armed spec with a stale
  receipt refuses with that text. The same fixture with a fresh receipt passes the guard.
- **AC-4** — The intent-gap schema in `interviewing-baseline` documents ratification by standing
  delegation. The build writes `ratified: yes` before the handoff, and `ratified_by:` cites a GitHub
  blob permalink to the delegation line in the consumer's committed CLAUDE.md (or an equivalent
  committed doc). An operator's comment URL remains a valid citation. The "committing the flip
  costs a round" advice now tells the build to ratify before the handoff, so no flip lands after
  review.
- **AC-5** — The build skill's P9 rule and its tracker-writes rule say the same thing: under a
  standing delegation, the build ratifies its own intent-gap record before the handoff, and that
  costs no tracker write.
- **AC-6** — The review skill says an intent-gap record's ratification state is not a review
  finding. The merge boundary settles it. Step 5d's hand-back is unchanged.
- **AC-7** — The hand-back record that `bash G verdict --hand-back ratification` writes names the
  delegation permalink as a valid `ratified_by:` citation alongside an operator comment.
- **AC-8** — The consumer template `SECOND-SHIFT.md` tells the consumer how to commit the
  delegation line and how a build cites it.
- **AC-9** — A boundary selftest scenario shows that an intent-gap record reading `ratified: yes`
  with a blob permalink in `ratified_by:` raises no ratification violation.
- **AC-10** — The diff adds no file beyond this lane's own records, no record key, no capability
  token, no register row, and no new or reworded refusal string. The merge boundary's
  `ratified_by:` https check and its violation text are unchanged.

## Replay row map

Row ids from the operator's consumer scoreboard (2026-09-19 seed, filled 2026-09-20). Ids only.

| Row | Class | Disposition |
| --- | --- | --- |
| B-11 | stale render receipt | removed — AC-1: `mark` refuses the stale receipt before the handoff, so the build re-renders and the reviewer never sees it |
| B-14 | stale render receipt (docs-only ratification commit after milestone 3) | removed — AC-1 for the stale receipt, and AC-4/AC-5: the ratification is written before the handoff |
| B-25 | stale render receipt | removed — AC-1 |
| B-29 | stale render receipt | removed — AC-1 |
| B-30 | stale render receipt | removed — AC-1 |
| B-33 | `ratified: no` | removed — AC-4/AC-5/AC-6: the build ratifies by delegation before the handoff, and the reviewer does not block on ratification |
| R-02 | verdict-only round (deferral's follow-up ticket missing) | out of scope — D-6 |
| R-27 | verdict-only round (deferral's follow-up ticket missing) | out of scope — D-6 |
| B-12, B-17, B-18, B-20, B-21, B-23, B-35 | false evidence in the spec | out of scope — D-2 |
| the 23 rows behind (b) | stale-verdict merge | out of scope for code — D-1 |

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What this ticket does about (b), stale-verdict merges | Out of scope for code. The shipped freshness arm (boundary-evidence.sh arm 3, `reviewed_patch_id`) already refuses a head that moved after its verdict. No consumer runs it, because second-shift-ci.yml is emitted only on request. The remedy is the operator installing that workflow as a required check at consumers. The (b) rows are replayed as out of scope for that reason. | user-answered |
| D-2 | Which record-form rows are in scope for (a) | The plan Step-5 set only: B-11, B-14, B-25, B-29, B-30 (stale render receipt), B-33 (`ratified: no`), R-02, R-27 (verdict-only rounds). The seven false-evidence rows (B-12, B-17, B-18, B-20, B-21, B-23, B-35) are out of scope: a spec claiming evidence that does not exist is a real defect in the definition of done. | user-answered |
| D-3 | Where a stale render receipt is stopped | On an armed spec, the build's last gate call before handoff refuses when the receipt's `rendered_from` differs from the current `render_patch_id`, reusing milestone 4's existing "Re-run milestone 3…" refusal string (no new string). The build re-renders, so the reviewer never sees a stale receipt. BUILD picks the exact call site. This also covers B-14, a docs-only ratification commit after milestone 3. | user-answered |
| D-4 | Who ratifies a departure, and how the record says so | The build ratifies by standing delegation: it writes the intent-gap record with `ratified: yes` before handoff, and `ratified_by:` cites the standing delegation, not a comment posted as the operator. No human-only signature step is added. Nothing flips after review, so ratification never costs a round, and the reviewer does not block on a pending ratification. The CLAUDE.md "human's signature" clause is read as satisfied by the standing delegation. | user-answered |
| D-5 | Where the standing delegation lives, so `ratified_by:` can cite it | A GitHub blob permalink to a line in the consumer's committed CLAUDE.md (or an equivalent committed doc) stating the delegation. No new key and no new file in this repo, and it works under jira because source control is GitHub for every adapter. The onboarding and build docs say how to add and cite it. The merge boundary's existing https-URL check on `ratified_by:` is unchanged. | user-answered |
| D-6 | R-02 and R-27 (a deferral's follow-up ticket missing) | Out of scope, with the reason recorded in the replay map: a deferral without its ticket is a spec-authority gap, and filing the ticket is a tracker write the delegation does not cover (impossible under `writes: false`). They stay candidates for the intake-trace ticket. | user-answered |
| D-7 | Review 5d hand-back (two ratified artifacts disagree) | Unchanged. It is a genuine ruling that can change code, so the round it costs is legitimate, and no scoreboard row blames it. Its `ratified: no` record is ratified by delegation like any other. | user-answered |
| D-8 | How the acceptance replay is shown | The spec carries a row map keyed by scoreboard row id (ids only), mapping each in-scope row to the mechanism that removes its round and every other named row to "out of scope" with the D-1, D-2 or D-6 reason. Each new mechanism gets a gate selftest scenario (stale receipt refused at handoff; delegated ratification written before handoff and accepted at the boundary). The operator re-reads the rows at the next scoreboard read. | user-answered |
| D-9 | Constraints on the diff | As the ticket body states: no new file beyond the lane's own records, no new record key or capability token, no new register row, no new or reworded refusal string (the (ac1)/(ac1b)/(ac1d) pinned counts may move), net diff stated at merge authorization. | codebase-derived |
| D-10 | The `writes: false` tracker edit from the comment datum | Not scope for this ticket. The operator filed it separately under the admission rule, per https://github.com/manoldonev/second-shift/issues/866#issuecomment-5764331968 | ticket-sourced |
| D-11 | Duplicate scan | dup-scan rc=0: nothing queued or in progress to collide with. | codebase-derived |
| D-12 | The exact call site D-3 left to BUILD | The direct `mark` subcommand, guarded at dispatch next to the ticket-liveness re-check. `mark` is the last gate call before the handoff (checklist step 7). The guard sits before `cmd_mark`, so it runs when no bot is configured, where `cmd_mark` returns early. The close-out path calls `cmd_mark` as a function and never reaches it, so a merged or approved branch is never stranded by it. | codebase-derived |
| D-13 | What the `mark` guard does when the render patch identity cannot be computed | It does not refuse. Milestone 4 still refuses that case at review with its own text, and a new refusal string for it would break D-9. The guard refuses only on a computed mismatch. | codebase-derived |
| D-14 | The boundary's ratification violation text, which still says "Cite the operator's comment" | Unchanged, per D-9 (no reworded refusal string) and D-5 (the boundary check is unchanged). The schema docs carry the delegated citation. | codebase-derived |
