# lean review verdict — #779

verdict=needs-work
run_id: review-779-1
session_id: 14d10f41-3a3f-4641-aa97-97b7fbc9e718
rounds: 1
pr: #782
reviewed_head: 1975b89fa40386ae678d9b1a1b68d14632045bd2
reviewed_patch_id: ceae5fcd5769001a32b7c68e35658e7b7e08fc17
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

Round 1, root round — full branch diff `d8ea88aa..1975b89f` (3 files, +317). Reviewed from the
lane worktree with the branch checked out. Panel 2/2, none dark. Fidelity `not-applicable`: the
spec declares no `## Design` section and the repo configures no `design.provider`.

**Verdict: needs-work — 2 blockers.**

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `tools/classify-capture.sh` takes one capture path and scans every line, keying on `.type == "result"` at `:53-54`. Exercised end-to-end by all 11 selftest cases and by hand on a 2.2 MB / 831-line synthetic capture (rc 0, 6s wall). |
| AC-2 | satisfied | Three verdicts at distinct exit codes, each printing a naming line: rc 0 `COMPLETE` at `:73`, rc 1 `FAILED` naming subtype and is_error at `:77`, rc 2 `TRUNCATED` naming the absent terminal event at `:60`. Suite cases (a)-(e) assert code and message together; the empty file takes the rc-2 arm because the read loop never iterates. |
| AC-3 | satisfied | Missing arg `:40`, absent-or-unreadable file `:42`, unparseable line `:52` all reach `die` at exit 3, kept disjoint from rc 2. Cases (f)(g)(h) confirm the codes. Hand-probed: a capture ending in a partial JSON object exits 3, which is what this AC specifies — see W1 for why that shape deserves a follow-up rather than a blocker. |
| AC-4 | satisfied | `tail -n 1` over the collected result lines at `:68` makes the last event govern; the count note at `:64-66` fires only above one. Case (i) proves a later failure overrides an earlier success and asserts the count string; case (j) proves the reverse direction, so the rule is not "any failure wins". |
| AC-5 | unsatisfied | Every case this AC enumerates exists, but its closing requirement — "Each case asserts both the exit code and that the printed line names the verdict" — is unmet in 5 of the 11 cases, which assert the exit code alone: (f) `:95`, (g) `:105`, (h) `:113`, (j) `:137`, (k) `:147`. MEASURED LIVE for the rc-3 family: with `die` rewritten to emit a constant wrong string, and again to emit nothing at all, the suite stays at 11/11 rc 0 (probe M1, M2 at the reviewed head). For (j) and (k) the message is asserted by sibling cases (a) and (b)/(c), so those two are redundant rather than live. Remedy is a `grep -qF` per case. |
| AC-6 | satisfied | Cited from CI at this exact head, not re-run: `lint-and-selftests` pass 3m48s and `selftests (macos, bash 3.2)` pass 5m23s, both on head `1975b89f` in run 33626782058. Glob discovery confirmed in that job's log — `pass 1s tools/classify-capture-selftest.sh` — with no registration anywhere. `shellcheck -e SC1091,SC2015,SC2181` on both new files is clean locally as well. This AC names `run-selftests.sh` and `shellcheck` only; the separate `mutation-sweep-pr` red is B1 below and is not an AC-6 obligation. |

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| B1 | Blocker | `tools/classify-capture.sh:44` | `mutation-sweep-pr` is RED at the reviewed head: `applied=8 killed=7 survived=1`, and the survivor `tools/classify-capture.sh::default::8f08ececad0b` is reported as a baseline-absent survivor, exit 1 (run 33626782058, job 100236291015, head `1975b89f`). The site is the `TMPDIR` fallback in the `mktemp -d` template; the `default` operator replaces the fallback with a token, and with TMPDIR set the branch is never taken, so no case can observe it. CI's own serial re-run outside the pool already confirmed it really survives, and probe M6 reproduces it locally. This is a correctness lane on content the diff just wrote, and the remedy is judgment, not mechanical: the repo's established treatment for an unkillable environment-fallback default is a justified row in `tools/mutation-baseline.tsv`, which already carries 20-plus rows of exactly this class naming the seam that makes the default unreachable. The branch adds a new guard with such a site and adds no row. |
| B2 | Blocker | `tools/classify-capture-selftest.sh:95` | AC-5 unsatisfied — see the scorecard row. Five cases assert only the exit code, and for the three rc-3 cases that is the whole assertion, because rc 3 alone cannot distinguish a missing argument from an unreadable file from an unparseable line. Measured: neutering `die` to a constant wrong message (M1) or to no message at all (M2) leaves the suite fully green, so the diagnostic that is the only carrier of which read failed is currently unguarded. |
| W1 | Warning | `tools/classify-capture.sh:52` | The literal signature of the failure this tool exists for lands in the unreadable bucket rather than the truncated one. A session killed mid-write leaves a final partial JSON object; probed at the reviewed head, such a capture exits 3 with "line 2 is not valid JSON" rather than exiting 2 as truncated. AC-3 specifies exactly this, so the diff is right and this is not a blocker — and the corruption the ticket exists to prevent is still prevented, because rc 3 is not a negative result either. But the remedy AC-2 was split three ways to communicate is now wrong for the commonest truncation shape: an operator is told to investigate an unreadable file when the answer is re-run. Worth a selftest case pinning whichever classification the ticket wants, and a header note, or a follow-up on the consumer side in the ticket that reads this. |
| W2 | Warning | `tools/classify-capture.sh:69` | A result event carrying no `subtype` key at all is unguarded. Case (k) covers the analogous gap for `is_error` and fails closed to rc 1; nothing covers the subtype half. Confirmed live: flipping the fallback to `success` leaves the suite at 11/11 rc 0 (probe M3). Reported by `unit-test-mutation-reviewer` at confidence 82 and verified by execution. Not an AC-5 enumerated case, hence a warning. |
| W3 | Warning | `tools/classify-capture.sh:64` | No case asserts the multi-result note is ABSENT on a single-result capture, so relaxing the threshold from above-one to above-zero prints a spurious "1 result events found, the last one governs" note on every ordinary capture and survives the suite (probe M4). Reported by `unit-test-mutation-reviewer` at confidence 80 and verified by execution. |
| W4 | Warning | `tools/classify-capture.sh:40` | The argument check is only ever exercised with 0 or 1 arguments, so relaxing it from exactly-one to at-least-one — silently ignoring a second argument instead of refusing it — survives the suite (probe M5). Reported by `unit-test-mutation-reviewer` at confidence 82 and verified by execution. The generic sweep's `cmp-eq` operator does kill the exactly-one check, but only by flipping to not-equal; the relaxation direction is unreached. |
| S1 | Suggestion | `tools/classify-capture.sh:53` | A capture line that is a bare JSON scalar passes the validity check and then leaks a raw `jq: error (at <stdin>:1): Cannot index number with string "type"` to stderr before being treated as a non-result line. Probed: the tool still returns the right verdict, but a consumer capturing stderr gets jq noise attributed to nothing. Suppressing stderr on the type read, as the validity check already does, closes it. |
| S2 | Suggestion | `tools/classify-capture.sh:52` | A line containing literal `null` is reported as "not valid JSON" when it is valid JSON — `jq -e` exits 1 on a null or false result, which the validity check reads as a parse failure. Harmless for real stream-json, but the message is wrong about its own input. `jq -e 'type'` or a bare `jq .` with an explicit rc check says what is meant. |

## Strengths

- The rc-3 family is a genuinely good call and the header says why: truncation is a claim about
  what the capture contains, not about whether the tool could open it, so folding an unreadable
  input into "truncated" would recreate the exact ambiguity the tool removes. The empty-file case
  landing on rc 2 rather than rc 3 (case (e)) is the sharp edge of that distinction, and it is
  reasoned rather than incidental.
- Case (j) is the case most authors skip. Proving a later success governs over an earlier failure
  is what separates an implemented last-one-governs rule from an accidental any-failure-wins one,
  and case (i) alone would have passed under both.
- OR-1 is honestly parked: the reversibility claim is checkable (one read, one tool, no committed
  results depending on it) rather than asserted, and D-8 records the default it took.

## Panel

- `review-toolkit:scope-completeness-reviewer` — approve, 0 findings. Noted in its suppressed set
  that rc 3 and the last-one-governs rule are additive beyond the issue body; both are declared in
  the committed spec as AC-3 and AC-4, so nothing is out of scope.
- `review-toolkit:unit-test-mutation-reviewer` — approve-with-nits, 3 minor findings, confidence
  80-82. All three predicted mutants were applied and scored at the reviewed head; all three
  survive, so all three are carried as W2, W3, W4 rather than as predictions.
- Lead pass covered performance, maintainability, complexity, test coverage and security.
  `security-reviewer` was not selected — no auth, tenancy, session, upload or external-input query
  surface in the diff and no `review-context/security-reviewer.md` in the repo — so the lead pass
  owns the security dimension this round; a read-only local file classifier with no network and no
  privileged write carries no new surface. Performance was measured rather than reasoned: two jq
  spawns per line is 1662 processes on the motivating artifact's size, and that measures at 6s
  wall, which is not a finding. `a11y-reviewer` and the design-fidelity dimension were not routed
  — no changed path matches `stageParams.webComponentGlobs`, which resolves to the shipped default
  `apps/web/**` since this repo declares none.

## Merge-boundary state, recorded not scored

`pr-gates` fails at step 6, lean chain reconciliation, because no verdict record existed at the
time it ran. That is the expected pre-approve state of that lane and is not a finding. Every other
step of that job is green, including the frozen-files guard and the changelog-trailer guard.

## Probe method

All mutants were applied in a throwaway worktree detached at `1975b89f`, inside the repo, one at a
time with a restore between, and scored by whether the paired suite's exit code moved off zero.
Baseline was confirmed green first. The reviewed lane worktree was never modified and is clean.
