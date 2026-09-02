# second-shift #783 — mark's own PR-body check, at step 7 instead of at close-out

Checklist step 7 already mandates what a lean PR body must carry — a ready (non-draft) PR,
`Closes #<issue>`, and the committed spec link. Nothing asserted that until `close-out`, which
runs only after a whole review round is spent: two measured occurrences (#693/PR 696,
#564/PR 781) hard-stopped on the same missing spec-link string, each time after an approve, each
time paying `close-out`'s full milestone-3 re-sweep a second time to rescue a one-line body.

The assertion already exists — `cmd_5`'s `exit-artifacts` obligation, `lean-gate.sh`. The gap is
that `cmd_mark`, which is holding the same PR object at the moment checklist step 7 composes the
body, asserts nothing about it.

## Acceptance criteria

- **AC-1** — A single shared predicate, `pr_exit_artifacts_check`, asserts the three obligations
  `cmd_5`'s `exit-artifacts` obligation already covers — non-draft, `Closes #<issue>` (or, under
  `jira`, `Closes [<KEY>]` inside the `Jira Items` section), and the committed spec link — and is
  called by both `cmd_mark` and `cmd_5`. Not a `LOCKSTEP-BEGIN` pair: both call sites live in
  `lean-gate.sh`, where a shared call prevents drift instead of merely detecting it (D-2, D-3).
- **AC-2** — `cmd_mark` calls the predicate and hard-refuses (`return 1`) when any obligation is
  missing, positioned after the MERGED short-circuit and before the existing-marker idempotency
  no-op — so a re-entry whose marker already exists but whose body has since broken re-verifies
  rather than no-opping past it (D-1, D-4).
- **AC-3** — With exactly one obligation missing, the refusal's message text is byte-identical to
  the message `cmd_5` already produced for that obligation before this ticket. With two or three
  missing, one joined message names every failing obligation (D-5).
- **AC-4** — The predicate makes zero additional network calls: `resolve_open_pr`, which
  `cmd_mark` already calls, already fetches `body`/`isDraft`/`url` (D-9). A `cmd_mark` refusal
  writes no progress-file row and charges no fix-budget attempt — `cmd_mark` is not a milestone
  (D-10).
- **AC-5** — The cost block and the PR summary prose stay out of the checked set: the cost block
  self-heals at close-out (`closeout_patch_pr_body` treats an absent block as legal), and
  "summary" is unassertable prose a presence guard would only fake-cover (D-7, D-8).
- **AC-6** — `--pr-file` selftest fixtures that reach `cmd_mark` (`pr-mark.json`) carry `isDraft`
  and a compliant `body`, so existing identity/idempotency cases keep exercising what they always
  exercised instead of being refused earlier by the new check (D-13).
- **AC-7** — `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` gains a leg
  composing `mark` itself refusing a step-7 PR body missing the spec link, and the same session
  posting normally once the body is fixed — the "new gate contract extends the liveness scenario"
  obligation (D-14).
- **AC-8** — `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` gains unit-level
  cases for: a single-obligation refusal matching `cmd_5`'s own wording (draft; spec link), the
  joined multi-obligation message (D-5), and the D-4 placement property — a re-entry whose
  marker already exists still refuses when the body has since broken (D-14).
- **AC-9** — No `tools/mutation-catalog.tsv` row is added for the new assertion (departure from
  D-14's literal ask — see D-18). `tools/mutation-catalog.tsv`'s existing
  `lean-gate-mark-session-guard` row is unchanged and does not need re-anchoring: it anchors
  `if ! session_in_build_set "$msid"; then`, which this ticket does not edit (D-15).
- **AC-10** — `build-lean/SKILL.md` step 7's prose is unchanged: the instruction is what makes a
  session write the obligations in the first place, and no prose is added about the new refusal
  — it incurs a prose-blocker triage row for no new information; the refusal names itself
  (D-16).
- **AC-11** — `bash tools/prose-blockers.sh check` exits 0 on the branch (no new prose blockers
  introduced).
- **AC-12** — The shared predicate reproduces `cmd_5`'s existing
  `grep -c -i -E "closes[[:space:]]+#$ISSUE"` verbatim, inheriting rather than closing the
  backticked `` `Closes #N` `` blind spot (OR-1's default disposition — flagged in the PR body,
  not fixed here).
- **AC-13** — The repo sweep
  (`SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`)
  and `shellcheck -e SC1091,SC2015,SC2181` stay green.

## Out of scope

- Raising `tools/mutation-sweep-selftest.sh`'s `MAX_ROWS_PER_GUARD` cap. `lean-gate.sh` is
  already at the cap (36/36 measured rows); lifting a repo-wide cap to fit one ticket's row is a
  policy change outside this ticket's bounded-exception scope (D-6, D-18).
- Closing OR-1 (the backticked `` `Closes #N` `` blind spot). Parked, per D-17/OR-1.
- Any change to `close-out`'s own re-sweep behavior. This ticket's positive-diff removes the
  *class* of post-approve rescue by catching the omission earlier; it does not change what
  `close-out` re-verifies.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | How hard the new body check bites inside `cmd_mark` | Hard fail — `return 1`. The ticket's stated strand risk is falsified: `lean-evidence.sh` `arm_identity` emits `note_violation "no bot-authored 'lean-pr-marker' comment on this PR…"`, so an absent marker fails closed and names itself rather than being unreadable. A warn would re-create the unenforced-instruction gap the ticket itself names | user-answered |
| D-2 | Which of step 7's four obligations the check covers | All three `cmd_5` asserts: non-draft, `Closes #<issue>`, and the spec link `$SPEC_REL`. Matching that set exactly is what makes one shared expression possible rather than approximate | user-answered |
| D-3 | One expression or two | One shared predicate helper in `lean-gate.sh`, called by both `cmd_mark` and `cmd_5`. It returns 0/1 and sets a message variable; each caller keeps its own reporting verb (`cmd_5`'s `fail_obligation exit-artifacts`, `cmd_mark`'s `warn` + `return 1`). Not a LOCKSTEP pair: every `LOCKSTEP-BEGIN` id in this repo spans two or more FILES, and both sites here are in one file, where a call prevents drift rather than detecting it | user-answered |
| D-4 | Placement within `cmd_mark`'s three early returns | After the merged short-circuit, before the idempotency no-op. Re-entry therefore re-verifies the body instead of no-opping past it. Placing it before the merged return would make close-out newly fallible on the post-merge path #642 deliberately kept reachable, against a marker whose only reader has already run | user-answered |
| D-5 | What the build session reads when more than one obligation is missing | The helper collects all three verdicts and joins them. Byte-identical to today's message when exactly one fails, so `cmd_5`'s existing selftest expectations are untouched and only the two- and three-failure cases are new text. Grounded in the ticket's own complaint that short-circuit diagnosis "wastes a cycle" | user-answered |
| D-6 | How #783 clears #717's ratification bar | Ratify by bounded exception, in #622's shape — the bound stated so it sets no precedent for siblings. A narrowing was searched for first and none exists: the block extracted from `cmd_5` is ~18 lines against a ~24-line helper plus call sites, and `cmd_5`'s check cannot be deleted as redundant because a session can edit the body after step 7. The exception buys removal of a class of post-approve hand-rescue and of a redundant full milestone-3 sweep (≥5:22 even all-green) | user-answered |
| D-7 | Whether the cost block is in the checked set | No. `closeout_patch_pr_body` treats an absent block as the legal `appended` state, so a missing step-7 cost block self-heals at close-out and has never failed a run | codebase-derived |
| D-8 | Whether "summary" is in the checked set | No. It is unassertable prose, and `review-toolkit:plan-reviewer` flags any new prose-presence guard | codebase-derived |
| D-9 | Cost of the check at step 7 | Zero extra network calls. `resolve_open_pr` already fetches `number,url,body,isDraft,state`, so `cmd_mark` holds the body and the draft flag at the moment the marker is posted | codebase-derived |
| D-10 | Whether a failed check charges gate budget | No. `cmd_mark` is not a milestone — it calls neither `append_attempt` nor `append_absent` — so the refusal returns 1 to the shell and writes no progress row | codebase-derived |
| D-11 | Tracker-adapter handling inside the helper | The helper carries `cmd_5`'s existing fork verbatim: under `jira`, `Closes [<KEY>]` within `jira_items_section`; otherwise `Closes #<issue>`. The spec-link arm stays adapter-insensitive, as it is today | codebase-derived |
| D-12 | Accepting that no-bot consumers get no early check | Accepted. `cmd_mark` returns 0 before `resolve_open_pr` when `BOT_ENABLED != true`, and supplying the body there would mean a network call on a lane with no marker to post — inverting the short-circuit's purpose. Those consumers keep `cmd_5`'s assertion at close-out | user-answered |
| D-13 | `--pr-file` fixtures under the new read | Fixtures that reach `cmd_mark` must gain `body` and `isDraft` keys. Several carry only `{"number":N,"state":"…"}` today and would read an empty body. An absent key must not read as a pass — that would be a fail-open hole in the new assertion | codebase-derived |
| D-14 | Test obligations this incurs | A new refusal in `cmd_mark` is a new gate contract, so it owes a `scenario-liveness-selftest.sh` extension plus a `tools/mutation-catalog.tsv` row for the new assertion, per CLAUDE.md and the `writing-tests` skill | codebase-derived |
| D-15 | Whether the existing catalog row re-anchors | No. `lean-gate-mark-session-guard` anchors on `if ! session_in_build_set "$msid"; then`, which this change does not edit | codebase-derived |
| D-16 | Whether step 7's prose changes | No. The trade of shell against prose was considered and declined: the instruction is what makes the session write the obligations in the first place, and deleting it would convert a pre-emptive instruction into a post-hoc refusal. Adding prose about the new refusal was also declined — it incurs a prose-blocker triage row for no new information, and the refusal names itself | user-answered |
| D-17 | Whether the shared assertion also closes the code-span `Closes #N` blind spot | Parked under OR-1 | deferred |
| D-18 | Whether D-14's `tools/mutation-catalog.tsv` row is added literally | DEPARTURE — `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` is already at `tools/mutation-sweep-selftest.sh`'s `MAX_ROWS_PER_GUARD` cap (36/36 rows, measured at build time); a 37th row breaches the per-guard cap lint, and raising a repo-wide cap for one ticket's row is outside D-6's bounded-exception scope. No catalog row is added. Coverage for the new assertion instead comes from `tools/mutation-sweep.sh`'s generic tier — which auto-mutates every shell line, including the new call sites, with no catalog registration required — plus the AC-7 scenario leg and the AC-8 unit cases. The `writing-tests` skill's tier map treats a catalog row as the mechanism for pinning a regression class the generic budget might otherwise leave dark, not a blanket requirement for every new assertion; a composed verdict path reaching a terminal write is the scenario tier's job, which AC-7 discharges | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether the shared `Closes` assertion should reject a backticked `` `Closes #N` ``, which GitHub ignores for auto-close but the current grep matches | reversible-default-and-flag |

OR-1's default is to reproduce `cmd_5`'s `grep -c -i -E "closes[[:space:]]+#$ISSUE"` verbatim,
inheriting the blind spot rather than fixing it inside a ticket whose whole premise is sharing
one expression. Reversing it later is cheap and bounded — after D-3 there is exactly one grep in
one helper, where today there would be two — and the failure it would catch has not been
measured on this lane. Flagged in the PR body; file separately if it is worth closing.

## Design

Design: none — `design.provider` is unconfigured on this consumer (`.claude/second-shift.config.json`'s `design` key is `null`); this ticket touches no UI surface in any case.
