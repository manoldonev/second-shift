# second-shift #777 — arm 2a captures stdout, but the built-in reports to a tool sink

`docs/skill-ablation-addendum.md` §B registers the arm-2a challenger as a bare `claude -p …`
whose finding set is read off **stdout**. On a real tree the built-in `/code-review` may instead
route its findings to a structured report tool, and the capture discards them.

It does this **non-deterministically**. Measured 2026-09-02, all three registered C2 samples run
under the registered form verbatim — same command, model tier, effort and allowlist:

| sample           | rc  | stdout  | capture mode | findings recoverable            |
| ---------------- | --- | ------- | ------------ | ------------------------------- |
| C2-a (`cfba102`) | 0   | 3188 B  | report tool  | **0 of 15**                     |
| C2-b (`f8f7c14`) | 0   | 2897 B  | report tool  | **0 of 12**                     |
| C2-c (`642a6b1`) | 0   | 17326 B | stdout       | 15 of 15, as a valid JSON array |

Uniform loss would fail loudly. This does not: a reader scoring the corpus as captured grades
C2-c on 15 findings and C2-a/C2-b on the handful of scraps those sessions volunteered _in
addition to_ the filed set, and records the difference as a property of the challenger.

The registration did not catch it because the validating measurement — §B's "Measured 2026-09-01,
the exact form above was also run end-to-end" paragraph — ran against a
throwaway two-commit repository, whose small diff yields a prose answer. The path two of the
three real samples take was never exercised.

## Consequence for the frozen metric

- AC-3 of #747 grades the challenger against the five frozen ground-truth blockers. For two of
  three samples the primary finding set is unreadable.
- D-39 registers that **all** findings count, with no severity filter. A stdout-only capture on
  those two samples yields a self-selected fraction — the one shape that decision rules out.

> **Line citations.** The `docs/skill-ablation-addendum.md` line numbers carried in the Decision
> Ledger below (`:257-261`, `:264-269`, `:271-295`) are the pre-flight ledger's own text and are
> anchored to this branch's base, `d8ea88aa`. This PR's own edits move them, so everything outside
> that table cites §B by subsection heading instead.

## Scope

Registration and re-validation only (D-2). #747 remains the slice that runs the three arms,
scores AC-3 and commits the transcripts; it unblocks when this merges. The consuming slice
cannot make this edit itself: `docs/plans/second-shift-747-lean.md` puts editing
`docs/skill-ablation-addendum.md` out of scope, and D-37 records that nothing about the
invocation is that slice's to choose.

## Acceptance criteria

- AC-1: §B "The invocation, exact" registers `--output-format stream-json --verbose` on the
  `claude -p` invocation. The command, the model tier (`--model opus`), the effort (`max`), the
  allowlist (`Read,Grep,Glob,Bash`) and the `env -u` set are otherwise unchanged, and §B says so
  — this changes what is _recorded_, not what is _run_, so the bias arguments registered at
  §B's model-tier, effort and allowlist subsections hold verbatim (D-1).
- AC-2: §B's registered mapping states what composes the arm's finding set under the amended
  capture: the **union** of the report tool's input and the findings in the final assistant
  text, deduplicated on **same mechanism and same consequence** — the frozen hit rule's own
  predicate, so no new scorer judgment enters. It reads as a refinement of the existing "every
  finding the built-in reports is in the challenger's finding set", not a replacement of it: no
  severity filter, no demotion (D-3).
- AC-3: §B's two-commit end-to-end validation claim — "Measured 2026-09-01, the exact form above
  was also run end-to-end" — is
  **replaced** by the re-validation of AC-4, not supplemented by it. §B states why the old claim
  was insufficient: the two-commit diff never exercised the report-tool path (D-7).
- AC-4: §B records the re-validation as executed evidence: the assertion command run verbatim,
  and its measured output, against the **`c2-a-654` pinned clone** — a real tree that
  demonstrably triggers the report tool — asserting whether the report tool's input is present
  in the **parent** stream. `/code-review` delegates to subagents, so that it reaches the parent
  at all is empirical, not assumed. If the assertion fails, §B instead registers the
  payload-plus-stdout capture and records the subagent finding as the reason (D-4, OR-1).
- AC-5: §B records the measured capture-mode variance above as the defect this amendment
  answers, and the disposition of the three outputs already captured: **discarded for scoring**,
  retained as this ticket's defect measurement only. #747 re-runs all three under the amended
  capture, so one capture mode spans the corpus and the samples are comparable by construction
  (D-5, D-6).
- AC-6: The branch is green — `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e
SC1091,SC2015,SC2181` and `SKIP_STRESS=1 bash tools/run-selftests.sh --exclude
tools/install-topology-selftest.sh`. No new checked-in script is added: the re-validation
  command is recorded as literal text in §B, so no script arrives without a selftest to exercise
  it.

## Out of scope

- **The three committed challenger transcripts** under `docs/plans/skill-ablation/c2-review/`,
  `scoring.tsv`'s arm columns, and §2 / §4 of `docs/skill-ablation.md`. #747 runs the arms and
  commits them; those are its AC-5 (D-2, S-5, S-6).
- **The unevaluable post-run assertion** — §B's "Post-run assertion, from the same measurement"
  paragraph, which requires that the report state the range it reviewed. None of the three reports names the
  range it reviewed, so "the report states the range it reviewed" cannot be evaluated in either
  direction — a real gap, and _not_ one the amended capture closes. The issue narrows explicitly
  to capture ("Proposed change — **capture only**"), D-2 confirms it, and no ledger row disposes
  of the assertion, so re-registering it is not this ticket's decision to make. AC-4's measured
  output records what the report did or did not name, which is what leaves #747 able to raise it
  on evidence rather than on assertion. Flagged in the PR body.
- **Re-running C2-b and C2-c under the amended capture.** D-4 gates on one pinned clone, chosen
  because it demonstrably triggers the report tool; #747 re-runs all three (D-5).

## Decision Ledger

| ID  | Decision                                             | Resolution                                                                                                                                                                                                                                                                                                                                                                                                                                           | Provenance       |
| --- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| D-1 | How the arm captures the challenger's finding set    | Add `--output-format stream-json --verbose` to the invocation at `docs/skill-ablation-addendum.md`:257-261. Command, model tier, effort and allowlist unchanged, so the bias arguments at :271-295 hold verbatim; this changes what is recorded, not what is run.                                                                                                                                                                                    | user-answered    |
| D-2 | What #777 covers                                     | Registration and re-validation only. #747 remains the slice that runs the three arms, scores AC-3 and commits the transcripts; it unblocks when #777 merges. Keeps the arm runs with the ticket whose ACs grade them.                                                                                                                                                                                                                                | user-answered    |
| D-3 | What composes the arm's finding set                  | The union of the report tool's input and the findings in the final assistant text, deduplicated on same-mechanism-and-consequence — the frozen hit rule's own predicate, so no new scorer judgment enters. Honors D-39's "no severity filter, no scorer judgment about which ones were really blockers".                                                                                                                                             | user-answered    |
| D-4 | The re-validation gate, and the fallback if it fails | Re-validate against the `c2-a-654` pinned clone — a real tree that demonstrably triggers the report tool — asserting the tool's input is present in the parent stream. `/code-review` delegates to angle subagents, so that it reaches the parent at all is empirical. On failure, register the payload-plus-stdout capture instead and record the subagent finding as the reason. The assertion command and its measured output are recorded in §B. | user-answered    |
| D-5 | Disposition of the three outputs already captured    | Discarded for scoring; retained as this ticket's defect measurement only. #747 re-runs all three under the amended capture, so one capture mode spans the corpus and the samples are comparable by construction.                                                                                                                                                                                                                                     | user-answered    |
| D-6 | The capture mode varies across samples               | Measured 2026-09-02 under the registered form verbatim: 2 of 3 samples routed to the report tool (C2-a, C2-b), 1 of 3 printed a parseable 15-element JSON array to stdout (C2-c). D-1's stream captures both modes, so no further mechanism is registered. Evidence table in the issue body.                                                                                                                                                         | codebase-derived |
| D-7 | The §B:264-269 validation claim                      | Rewritten. The recorded two-commit end-to-end run never exercised the report-tool path that two of three real samples take, so it is replaced by D-4's pinned-clone measurement rather than supplemented by it.                                                                                                                                                                                                                                      | codebase-derived |

## Open Regions

| ID   | Region                                                                                               | Disposition                 |
| ---- | ---------------------------------------------------------------------------------------------------- | --------------------------- |
| OR-1 | Whether the report tool's input reaches the parent stream when `/code-review` delegates to subagents | reversible-default-and-flag |

OR-1 takes `--output-format stream-json --verbose` as the stated default and surfaces the result
of AC-4's assertion. Reversing it is cheap: the fallback is already registered in D-4 — capture
the payload and stdout together — and no sample has been scored at the point the assertion runs,
so a reversal costs a re-run and no committed result.
