# second-shift #779 — a truncated `stream-json` capture must not read as a completed negative

A BUILD session's detached probe can be reaped at the spawn boundary mid-run. What it leaves
behind — a `stream-json` capture with no `ReportFindings` events — is indistinguishable at face
value from a capture that ran to completion and genuinely found nothing. Measured 2026-09-02 on
#777: a 2.3 MB, 831-line capture, killed roughly 7 minutes into a comparable 20–30 minute run,
carries no `result` event and no findings. Read as a clean negative, that is a false measurement
entering a frozen-adjacent registration document.

This ticket does not touch the reap itself — `SKILL.md`:41 already forbids ending a turn with
uncollected work, and the lane already stops on it (`terminal: build-no-pr`, exit 1). It adds the
one thing missing: a way to tell a truncated capture apart from a completed one before either is
trusted.

## Completeness predicate

Measured 2026-09-02: a clean `claude -p --output-format stream-json` run terminates with a
`{"type":"result","subtype":"success","is_error":false,…}` event; the reaped #777 capture carries
no `type: "result"` event anywhere in the file. A capture is complete iff it carries at least one
such event.

## Acceptance criteria

- **AC-1** — `tools/classify-capture.sh <capture-file>` exists and classifies a `stream-json`
  capture (one JSON object per line) by scanning every line for `type == "result"` events.
- **AC-2** — Three verdicts, distinct exit codes, because truncated and completed-but-failed carry
  different remedies — re-run versus investigate — and collapsing them recreates the ambiguity
  the tool exists to remove (D-4):
  - `0` — at least one `result` event, the governing one (AC-4) has `subtype: "success"` and
    `is_error: false`. Prints a line stating the capture completed successfully.
  - `1` — at least one `result` event, the governing one has `is_error: true` or a `subtype`
    other than `"success"`. Prints a line stating the capture completed but the run failed, and
    names the subtype and `is_error` value.
  - `2` — no `type: "result"` event anywhere, including an empty file. Prints a line stating the
    capture stops without a terminal event — a truncation, not a negative result.
- **AC-3** — A missing argument, a nonexistent or unreadable capture file, or a line that fails to
  parse as JSON is a distinct failure (exit `3`) from all three AC-2 verdicts — a checker that
  cannot read its input must not report a verdict about that input, truncated or otherwise.
- **AC-4** — When a capture carries more than one `result` event — a concatenated run, or a caller
  appending to an existing file — the **last** one governs the AC-2 verdict, and the tool prints a
  line stating the count when it exceeds one (D-8, OR-1's default).
- **AC-5** — `tools/classify-capture-selftest.sh` covers, at minimum: a truncated capture (no
  `result` line, including the empty-file case), a complete success, a complete failure via
  `is_error: true`, a complete failure via a non-`success` subtype, multiple `result` events
  (asserting the last governs and the count is surfaced), a missing file, and a line that is not
  valid JSON. Each case asserts both the exit code and that the printed line names the verdict.
- **AC-6** — `bash tools/run-selftests.sh` and `shellcheck` (per `CLAUDE.md`'s verification
  recipe) stay green on the branch, and `tools/classify-capture-selftest.sh` is picked up by the
  sweep's glob discovery with no registration.

## Out of scope

- Wiring any consumer to call this tool. #777 owns how its arm captures are read and already
  registers that a capture failing this check is discarded rather than scored; #779 merges first
  and #777 cites it (D-5).
- Rewording or re-guarding `SKILL.md`:41's "never end a turn with uncollected work" rule (D-6).
- Any runtime enforcement of the reap itself — there is no channel into a live `claude -p`, and
  descendants are killed rather than orphaned (D-7).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What this ticket delivers | The truncation refusal only. The reap itself is already caught by `terminal: build-no-pr` / exit 1, which costs a session rather than a wrong answer; the failure worth fixing is the one that corrupts results. | user-answered |
| D-2 | Where the check lives | A checked-in tool under `tools/` with its own `*-selftest.sh`, discovered by the sweep's glob so it needs no registration. Reusable by any later consumer of a capture, rather than reimplemented per arm. | user-answered |
| D-3 | The completeness predicate | A capture is complete iff it carries a `type: "result"` event. Measured 2026-09-02: a clean run terminates with `{"type":"result","subtype":"success","is_error":false,…}`; the reaped #777 capture carries no such event. | codebase-derived |
| D-4 | Verdict arity and reporting | Three verdicts with distinct exit codes: `0` complete and successful, `1` complete but `is_error` or a non-success subtype, `2` truncated with no `result` event. Truncated and completed-but-failed carry different remedies — re-run versus investigate — so collapsing them recreates the ambiguity the tool removes. Each verdict prints a line naming which of the three it is; `rc=2` states that the capture stops without a terminal event. | user-answered |
| D-5 | What consumes the check | Nothing in this ticket. #777 already owns how the arm's capture is read, and its §B amendment registers that a capture failing the check is discarded rather than scored. #779 merges first and #777 cites it — sequencing, not scope creep. | user-answered |
| D-6 | The rule this ticket does not touch | `plugins/dev-pipeline/skills/build-lean/SKILL.md`:41 (#535, 2026-08-14) already forbids ending a turn with uncollected work and names this exact case — "a probe you plan to report on 'when it lands' … is abandoned, not deferred". It is not reworded or re-guarded: the repo forbids prose-presence guards, so a reworded rule would add prose nothing may test. | codebase-derived |
| D-7 | Why runtime enforcement of the reap is out of scope | `orchestrate-lean.sh`:169 records there is no channel into a live `claude -p`, and descendants are killed rather than orphaned — in both observed runs every artifact stops at the second the session exited. Neither interruption nor post-hoc process detection has anything to act on. | codebase-derived |
| D-8 | Which `result` event governs when a capture carries more than one | The last one governs, and the count is surfaced when it exceeds one. Parked under OR-1 (owner: this ticket's build, resolved when the tool lands). | deferred |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A capture carrying more than one `result` event — concatenated runs, or a caller appending to an existing file | reversible-default-and-flag |

OR-1 takes the stated default that the **last** `result` event governs the verdict, and surfaces
the count when it exceeds one. Reversing it is cheap: the predicate is a single read in one
checked-in tool with no committed results depending on it at the point it lands, and D-4's three
exit codes do not change shape under either reading.
