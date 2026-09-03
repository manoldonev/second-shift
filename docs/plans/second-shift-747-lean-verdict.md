# lean review verdict — #747

verdict=approve
run_id: review-747-2
session_id: 788b66eb-0fbb-44d3-a7d2-5192f2e6bcc3
rounds: 2
pr: #787
reviewed_head: 06b3ae9d33f85f28c104ef96b97f4e04faa7d200
reviewed_patch_id: b72ee421bc4b2a664c161ec0ce2571bd9caabdfb
inherited_patch_id: f35634ffe7ac56a98c62d9674153f0057ce32913
inherited_from_verdict: 0a7fbc4ddd50537fd29a9831706818ce6bff0727
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 2 over `bash G delta 747`'s range — `0a7fbc4d..HEAD`, one file, `docs/skill-ablation.md`,
+34/−11, docs-only — inheriting the coverage of patch `f35634ffe7ac` (round 1). Prior findings read
first, per the delta banner.

Panel: `review-toolkit:scope-completeness-reviewer` (returned `approve`, no findings; one
confidence-55 suppression about AC-6's 75 escapes being *raised* rather than verified — the same
point round 1 recorded as W2, and the delta discloses it). Nothing went dark. Docs-only prose diff
with no executable surface, no `.claude/second-shift/review-context/security-reviewer.md` in the
repo and no path matching `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), so
`security-reviewer` was not selected and the security dimension sat with the lead pass; `a11y` and
the design-fidelity dimension were not routed.

Design: the spec declares no `## Design` section — unarmed, `fidelity: not-applicable`, step 5b
skipped.

## Round-1 findings: disposition

| prior | disposition |
| --- | --- |
| **B1** (blocker) — "All three captures exited `0` with empty stderr" is false of C2-b | **Fixed.** The apparatus paragraph now reads *"All three captures exited `0` and classified `COMPLETE`"* and a new bolded paragraph states *"Stderr was empty on two of the three; C2-b's was not"*, quoting the ceiling message and linking the transcript. Re-verified against the artifacts: `codereview-654-review.md:28` `empty`, `codereview-660-review.md:28` `empty`, `codereview-657-review.md:28` the 600s termination string byte-for-byte. The same correction landed in the PR body, which carried the claim too. Grepped `docs/` branch-wide for a residual: the only other "empty stderr" is `skill-ablation-addendum.md:349`, which describes §B's own 2026-09-02 re-validation capture, a different run — not a half-applied fix. |
| **W1** (warning) — "enumerated so the complement is checkable" oversells the nine rows | **Addressed by disclosure.** The text now says the complement is *not* checkable and gives the only reconstructible arithmetic. Every number re-derived here: C2-c's report-tool section carries **32** `failure_scenario` objects and its two `result` bodies **13** → 45 raw, −11 merges → 34. C2-a **14** and C2-b **12** JSON findings, across **2** and **5** `result` events (matching each apparatus table's `result events` row). |
| **W2** (warning) — D-14 reads AC-6 as not requiring verification | **Addressed by disclosure.** §2 now records that D-14 was written in the results commit rather than the pinned one. Confirmed: `3acdd6db` adds the whole spec (81 lines, D-1…D-12); `git log -S"D-14"` returns only `62730099`, the results commit. |
| **N1** (nit) — the invented label `#654 r1 W3` | **Fixed** → `#654 r1 finding 3 (Warning)`. `ground-truth-654-r1-verdict.md:31` reads `\| 3 \| Warning \|` and `:57` `### 3 — Warning: …`; the new label matches the record. |
| **N2** (nit) — a 141-char line | **Fixed.** Re-wrapped; no added line in the delta exceeds 102 chars, and the file's remaining >110-char lines are pre-existing table rows outside the delta. |

## Findings

| # | severity | where | finding |
| --- | --- | --- | --- |
| N1 | nit | `docs/skill-ablation.md:428` | The quotation `*"subagent result delivery was broken in this environment (only the conventions angle could report back)"*` closes a parenthesis the source does not close. `codereview-657-review.md:43` reads `… (only the conventions angle could report back — its Write tool was denied and it correctly refused to route around that)`. The elision changes no meaning and the paragraph's claim does not rest on it, but this file marks elision with `…` elsewhere (the `build-lean/SKILL.md:32` block quote at §2), and on a document whose discipline is verbatim quoting an unmarked truncation reads as a complete quote. |

## Verified, not taken on trust

- **The three `result`-body quotes are verbatim and correctly positioned.** `codereview-657-review.md`
  headings put `result` 1 at :41, 2 at :129, 5 at :191; the quoted strings sit at :43, :131 and :197
  respectively. *"the delivery failure resolved itself — their results arrived as task
  notifications"* and *"The review is complete and the ranking stands"* are exact; the `result` 1
  quote is exact up to the elision at N1.
- **"C2-b is the only capture of the three that reached one [a ceiling]"** — true: the other two
  apparatus tables record `stderr | empty`.
- **"It moves no score"** — all three apparatus tables record exit `0` and a `COMPLETE`
  classification, which is §B's whole scoring precondition. Nothing about the score changes.
- **"The ceiling fired after the session had declared itself done."** This rests on harness
  semantics (the background-task wait runs after the final turn), not on a timestamp in the capture,
  and the text hedges accordingly (*"nothing here measures how much"*). The wall clock is consistent:
  C2-b ran 10:34:37→11:14:38, and a 600s ceiling terminating at 11:14:38 puts the session's last
  `result` at ~11:04.
- **The heading count is right.** `#### Apparatus, and three things the registration did not
  anticipate` now enumerates stderr, the inverted capture mode, and multi-`result` events. The two
  other bolded paragraphs in that block are not counted, consistently with the pre-change "two
  things": §B's unevaluable post-run assertion is explicitly *"as #777 predicted"*, and the
  file-reading leak is D-2's registered measurement.
- **C2-a's 31 corroborates independently.** 14 JSON findings in `result` 1 plus 18 numbered items in
  `result` 2 = 32 raw, of which item 18 is self-described as *"Refinement to my duplicated-paragraph
  finding"* — one merge → 31. The doc's claim that the total needs the merge judgment redone to
  reproduce is literally accurate; redoing it lands on the reported figure.
- **No spec amendment.** `docs/plans/second-shift-747-lean.md` is untouched in the delta; the only
  files changed since round 1's reviewed head are `docs/skill-ablation.md` and round 1's own verdict
  record.
- **No doc guard depends on the edited strings.** No `*.sh`/`*.mjs`/`*.yml`/`*.tsv` outside `docs/`
  references `skill-ablation`; the repo has no markdown format or line-length gate.
- **AC-2 re-derived at this head.** The fenced invocation block extracted from all three transcripts
  is byte-identical modulo the `pr-<n>` / clone-dir token, and identical to the command §B registers.
- **AC-5 re-derived at this head.** `scoring.tsv` is 8 columns × 5 data rows with every cell
  populated; `bare_result` / `adjudication` in place; `codereview_result` / `codereview_adjudication`
  appended.

## CI at the reviewed head

`lint-and-selftests` **pass** (4m46s) and `mutation-sweep-pr` **pass** at `06b3ae9d`;
`selftests (macos, bash 3.2)` was still running when this record was written — a docs-only delta
touching no script, so no correctness lane has a surface to move. `pr-gates` fails on **one step**,
*lean chain reconciliation*; reproduced locally with the workflow's own env, the sole cause is
`✗ verdict record … reads 'verdict=needs-work', not 'verdict=approve'` — round 1's record, which
this one supersedes. The frozen-files and `Changelog:` trailer steps are green; all four commits
carry `Changelog: none`, and the diff touches no `plugins/**` path.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Unchanged in the delta and re-checked at this head: each transcript's apparatus table carries the pinned base/head, and all three pairs match `skill-ablation-addendum.md`'s pinning table (`dfd68a47`/`cfba1022`, `b657907f`/`f8f7c142`, `bf231bdc`/`642a6b13`). |
| AC-2 | satisfied | The fenced invocation block in all three transcripts is byte-identical after normalizing `pr-<n>` and the clone directory, and matches §B's registered command — same `env -u` set, `--model opus`, `/code-review max`, `--setting-sources ''`, `--allowedTools "Read,Grep,Glob,Bash"`, `--output-format stream-json --verbose`. Model tier and effort identical across the three; recorded with each transcript. |
| AC-3 | satisfied | `scoring.tsv` untouched this round; the two scores that carry the result were re-checked in round 1 against the oracle records and hold. The one miss's three near-misses are quoted verbatim and adjudicated in §2, unchanged. |
| AC-4 | satisfied | The three `codereview-<pr>-review.md` files and `c2-review/README.md` are untouched in the delta; one file per session, name family distinct from `bare-<pr>-review.md`, each carrying the realised invocation, apparatus, and session output verbatim. |
| AC-5 | satisfied | `scoring.tsv` re-verified at this head (8 columns, 5 rows, all populated, bare columns in place). §2 carries the arm-2a section with the recall table, the miss adjudication and the apparatus — now with the corrected stderr fact. §4's `dev-pipeline/review-lean` row reads `C2 + #747 arm 2a … the comparison #644 named, now measured`, and the §1 summary row at :31 agrees; neither calls the comparison unmeasured. |
| AC-6 | satisfied | The escapes remain in their own `#### Recorded separately, not folded into recall` subsection and are excluded from the recall table, which scores only the five ground-truth blockers. Nine matches enumerated; the delta strengthens the record by retracting the "complement is checkable" claim, correcting the one invented citation label (N1 of round 1), and disclosing that D-14 — the row reading AC-6 as not requiring live verification — was written after the count was known. Verification of the 75 remains out of this AC by D-14's own terms, and is now disclosed rather than implied. |
| AC-7 | satisfied | `git diff --name-only 684d5fd6..HEAD` contains zero `plugins/` paths; no commit on the branch touches `plugins/dev-pipeline/skills/review-lean/SKILL.md`. |

`approve` — no blockers. Round 1's B1 is fixed and the correction is itself verified against the
artifact that refuted the original claim; W1, W2, N1 and N2 are all addressed, three of them by
disclosure that makes the record weaker-but-honest rather than stronger-but-unsupported. The one
finding this round is a nit about an unmarked elision inside a quotation.
