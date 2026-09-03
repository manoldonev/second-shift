# lean review verdict — #747

verdict=needs-work
run_id: review-747-1
session_id: 867e5877-1617-4799-99fc-85ff50667c5a
rounds: 1
pr: #787
reviewed_head: 6273009988f80975b763c47844aecefaedf0b1e5
reviewed_patch_id: f35634ffe7ac56a98c62d9674153f0057ce32913
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 1 over the full branch diff (`684d5fd6..HEAD`, 7 files, +1077/−23, docs-only) — `bash G delta 747`
printed the FULL range: root round, nothing to inherit.

Panel: `review-toolkit:scope-completeness-reviewer` (returned `approve`, no findings). Docs-only diff with
no security surface, no `review-context/security-reviewer.md`, and no path matching
`stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`), so the security dimension was covered by
the lead pass and neither `a11y-reviewer` nor the design-fidelity dimension was routed. Nothing went dark.

Design: the spec declares no `## Design` section — unarmed, `fidelity: not-applicable`, step 5b skipped.

## Findings

| # | severity | where | finding |
| --- | --- | --- | --- |
| B1 | **blocker** | `docs/skill-ablation.md:422` | The apparatus paragraph states *"All three captures exited `0` with empty stderr and classified `COMPLETE`"*. That is false of C2-b, and it is refuted by a file in the same commit: `docs/plans/skill-ablation/c2-review/codereview-657-review.md:28` records C2-b's stderr as `` `Background tasks still running after 600s; terminating. Set CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.` `` — non-empty, and the only capture of the three that hit a termination ceiling. The direction of the error matters: C2-b is also the sample with the smallest finding set (19 against 31 and 34) and the one whose own transcript opens *"subagent result delivery was broken in this environment"* (result 1 of 5; result 2 says the failure later resolved itself). A reader deciding whether C2-b's 19 is a complete set is told by the report of record that its apparatus was clean. The PR body repeats the claim verbatim. §B's scoring precondition — exit 0 and `classify-capture.sh` `COMPLETE` — did hold for all three, so no score moves; what fails is the report's own accuracy against its own committed evidence, in a document series whose entire value is that its claims are checkable. Fix: correct the sentence (and the PR body) to state C2-b's actual stderr and what it does and does not imply. |
| W1 | warning | `docs/skill-ablation.md:394` | *"**84 findings** (31 / 19 / 34). **Nine** correspond to a finding some lane round made — enumerated so the complement is checkable"*. The nine rows are checkable; the **complement is not**, because the dedup that produces 31/19/34 from the raw sinks is recorded nowhere. C2-c is the one place the arithmetic is visible — 32 report-tool findings + 13 on stdout = 45 raw, 11 unlisted merges → 34. C2-a and C2-b carry 14 and 12 JSON findings with the remainder in prose across 2 and 5 `result` bodies, and no reader can reconstruct 31 or 19 without redoing D-13's dedup judgment. Not blocking: §2 itself says the frozen table reads the false-blocker count only on a 5/5 run, which neither arm reached, so nothing downstream consumes the number. Worth either recording the merge pairs or softening "checkable" to what the enumeration actually delivers. |
| W2 | warning | `docs/plans/second-shift-747-lean.md:77` (D-14) | AC-6 says the escapes are recorded separately *"as the predecessor did for the bare arm"*. The predecessor verified its two against `main` before filing; D-14 reads that clause as not requiring verification and records 75 as *raised*. The reading is defensible on AC-6's operative verbs — "recorded separately" and "not folded into recall" are both met — and the weakening is disclosed in §2 and in the PR body rather than hidden, which is why this is not a blocker. But the ledger row licensing it was added in the **results** commit (`62730099`), not the pinned one (`3acdd6db`), i.e. after the count was known, and it resolves in the direction that reduces this slice's work. Recorded so the next reader sees the move rather than inheriting it. |
| N1 | nit | `docs/skill-ablation.md:400` | The escape table cites *"#654 r1 W3"*. `ground-truth-654-r1-verdict.md` numbers its findings 1–4 and labels the third *"3 — Warning: a duplicate row, and an anchor reaching past its own site"* — it never uses `W3`, unlike `ground-truth-657-r1-verdict.md`, which literally carries `W2`. The substance matches; only the label is invented. On a table whose stated purpose is checkability, that costs the reader a lookup. |
| N2 | nit | `docs/skill-ablation.md:557` | A 141-char line inserted mid-paragraph into an otherwise ~100-col-wrapped file (`before any of them runs. Arms 1 and 2a have since run against it; 2b has not. Read it alongside this table: …`). Re-wrap. |

## Verified, not taken on trust

- **AC-1 heads.** All three `(base, head)` pairs in the transcripts' apparatus tables match
  `docs/skill-ablation-addendum.md` §B's pinning table exactly (`dfd68a4`/`cfba102`, `b657907`/`f8f7c14`,
  `bf231bd`/`642a6b1`). I re-fetched each commit and re-derived the ranges.
- **The range argument, independently.** §2 claims C2-a's report describes the pinned range byte-exactly.
  `dfd68a4..cfba102` is **4 commits over 6 files** — `.github/workflows/ci.yml`, `docs/pipeline-manifesto.md`,
  `docs/plans/second-shift-636-lean.md`, `scripts/check-gate-buckets{,-selftest}.sh`, `scripts/gate-buckets.tsv`
  — i.e. "ci.yml, 2 docs, 3 scripts", exactly what the session wrote; `cfba102~1..cfba102` is 2 files, and the
  session cites three files outside it. Confirmed. On C2-b and C2-c I confirmed the weaker claim the same way:
  both branches are exactly 2 commits, and each first commit adds **only** its lean spec, so `HEAD~1..HEAD` and
  the pinned range differ by nothing but that file's initial version.
- **C2-a scored HIT.** `codereview-654-review.md:62-63` names the class `(^|[;&|(){}])` as omitting shell
  keywords, cites `lean-gate.sh:420` `else envfail` by line, and states the denominator consequence. The oracle
  (`ground-truth-654-r1-verdict.md:34`) is the same mechanism, same consequence, same site. HIT holds under the
  frozen rule.
- **C2-c B2 scored MISS.** I grepped the whole C2-c transcript for `identity-stamp` / `fixture-per-reason`:
  every occurrence is a demotion-candidate or firing-count concern, never "this reason has no behavioral case".
  All three near-miss quotes in §2 appear **verbatim** in the transcript. MISS holds.
- **`#660 r2 W1`** — the one escape-table row citing a record not committed under `c2-review/` — is real:
  `7e2781d2:docs/plans/second-shift-642-lean-verdict.md:98` reads *"W1 — milestone 3 concludes `"green gate"`
  unconditionally, over a run that just reported a red."* Exact.
- **The "last governs" report-sink reading is registered, not invented.** `docs/skill-ablation-addendum.md:363-367`
  (frozen, landed in #786) already states that two `ReportFindings` calls carry near-identical sets and the last
  one governs, so committing only call 2 of 2 is the registered form and not an AC-4 verbatim gap.
- **AC-7.** Zero `plugins/` paths in the branch diff; zero commits touching
  `plugins/dev-pipeline/skills/review-lean/SKILL.md`.
- **The spec was pinned before the results.** `3acdd6db` adds the whole spec (81 lines, D-1…D-12); `62730099`
  adds only **D-13 and D-14** and touches no `AC-n`. No acceptance criterion was amended after the fact.
- **Every relative link** added or changed in `docs/skill-ablation.md`, `c2-review/README.md` and the spec
  resolves from its own file's directory.

## CI at the reviewed head

`lint-and-selftests` **pass** (4m6s), `selftests (macos, bash 3.2)` **pass** (6m32s), `mutation-sweep-pr`
**pass** — all three correctness lanes green at `6273009`. `pr-gates` is **red on one step only**, *lean chain
reconciliation*; reproduced locally, the sole failure is `✗ no committed verdict record (a file named
*-747-lean-verdict.md)`. That is the structural pre-approve state of every lean PR, not a defect, and it is
recorded rather than scored.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Each transcript's apparatus table carries the pinned base and head; all three pairs match §B's pinning table byte-for-byte, re-fetched and re-derived here. The range is corroborated beyond the self-reported pre-run assertion: C2-a's own report describes the pinned 4-commit/6-file range byte-exactly and cites three files outside `HEAD~1..HEAD`; on C2-b/C2-c both branches are 2 commits whose first commit adds only the lean spec. |
| AC-2 | satisfied | All three "The realised invocation" blocks are byte-identical to §B's registered command — same `env -u` set, `--model opus`, `/code-review max <branch>`, `--setting-sources ''`, `--allowedTools "Read,Grep,Glob,Bash"`, `--output-format stream-json --verbose` — with only `<branch>` substituted (`pr-654`/`pr-657`/`pr-660`). Model tier and effort identical across the three. Recorded with each transcript as required. |
| AC-3 | satisfied | `scoring.tsv` scores the same five ground-truth blockers at the same three heads under the frozen rule; I re-checked the two scores that carry the result (C2-a HIT, C2-c B2 MISS) against the oracle records and both hold on same-mechanism-and-same-consequence. The one miss's three near-misses are quoted verbatim — all four quoted strings grep clean against `codereview-660-review.md` — and adjudicated in §2 so a reader can repudiate the call. |
| AC-4 | satisfied | `codereview-654-review.md`, `codereview-657-review.md`, `codereview-660-review.md` — one per session, a name family distinct from `bare-<pr>-review.md`, each carrying the realised invocation, the apparatus, and the session output verbatim (report-tool payload where filed plus every `result` body). `c2-review/README.md` gains the describing line. |
| AC-5 | satisfied | `scoring.tsv` appends `codereview_result` / `codereview_adjudication` with `bare_result` / `adjudication` untouched in place (8 columns, 5 data rows, all populated). §2 gains the arm-2a section with the recall table, the miss adjudication and the apparatus; §4's `dev-pipeline/review-lean` row now reads `C2 + #747 arm 2a … the comparison #644 named, now measured` and no longer calls it unmeasured. |
| AC-6 | satisfied | The escapes are recorded in their own `#### Recorded separately, not folded into recall` subsection and excluded from the recall table, which scores only the five ground-truth blockers. Nine matches enumerated in a table; I spot-verified the two that could not be checked from `c2-review/` alone (`#654 r1 W3` — substance right, label invented, see N1; `#660 r2 W1` — exact). The weaker evidentiary standing versus the predecessor is disclosed rather than concealed (W2). |
| AC-7 | satisfied | `git diff --name-only 684d5fd6..HEAD` contains zero `plugins/` paths, and no commit on the branch touches `plugins/dev-pipeline/skills/review-lean/SKILL.md`. |

`needs-work` on B1 alone — every AC is satisfied; the blocker is an obligation the diff incurred, not an
unmet criterion. B1's remedy is a one-sentence correction in `docs/skill-ablation.md` plus the same in the PR
body; that touches no line any AC is scored on, so round 2's reading should be correspondingly narrow.
