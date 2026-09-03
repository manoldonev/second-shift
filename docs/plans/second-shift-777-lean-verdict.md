# lean review verdict — #777

verdict=approve
run_id: review-777-1
session_id: 83de3758-0634-4b9e-9e30-bc2bd194efde
rounds: 1
pr: #786
reviewed_head: 5ac0541c2a1ceff759a4873f2796c98fcc588964
reviewed_patch_id: d3cce4120bc70cffd5706d28ed60bc950ff2a3a1
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full branch range `0978ee14..5ac0541c` (nothing verifiable to inherit). Docs-only diff:
253 insertions across `docs/plans/second-shift-777-lean.md` (new spec) and
`docs/skill-ablation-addendum.md` (§B amendment). All seven declared ACs are satisfied. Three
warnings, none blocking: an internal contradiction between the file's own "What this file must
never contain" rule and §B's new measured-output content, one artifact described at two different
sizes, and a claim in the spec's Out-of-scope rationale (repeated in the PR body) that §B's
recorded measurement does not actually back.

The amendment is unusually well-evidenced for a registration edit: the flag pair is byte-verified
against the pre-amendment invocation, the assertion it turns on was executed rather than argued,
and the run's limitation ("this sample also volunteered the findings on stdout, so it is not a pure
report-tool-only sample") is disclosed by the author rather than found by the reviewer.

Reviewers: `review-toolkit:scope-completeness-reviewer` (approve, 0 findings) — the only subagent a
Trivial-inert docs diff selects. Security conditional did not fire (no security surface in the
diff, no `review-context/security-reviewer.md` in the repo); the security dimension was covered by
the lead pass. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`). No reviewer went dark.

## Strengths

- **The flag-pair non-change is verified, not asserted.** `§B:264-270`'s "byte-identical to the
  form this arm was first registered with" holds under a literal diff of the `env -u` set and every
  flag between `0978ee14` and `5ac0541c` — only the two capture flags and a line continuation
  differ. That is the whole load-bearing claim of AC-1 and it survives mechanical checking.
- **The re-validation records what it does NOT establish.** `§B:373-380` volunteers that the run
  also printed the findings to stdout, so it is not a pure report-tool-only sample and is not
  evidence that the amended capture was the only recovery path. The narrower claim it does support
  is then stated explicitly. This is the discipline whose absence caused the defect being fixed.
- **AC-7's rule was applied to itself before being registered.** `§B:353-355` records that the two
  captures taken before the recorded one both classified `TRUNCATED` and were discarded rather than
  scored, and `tools/classify-capture.sh`'s exit codes as described (`0/1/2/3`) match the shipped
  script line-for-line.

## Critical (must fix before merge)

None.

## Warnings (should fix)

- **[Cross-cutting] `docs/skill-ablation-addendum.md`:34-44 vs :281-301, :365-366 (confidence: 85)
  — §B now carries measured arm output from the pinned samples, and the rule that forbids it was
  left unamended.** "What this file must never contain" states, without exemption, that "Every
  number below is a *pin* … or a *threshold fixed before its arm runs*. None is an outcome", and
  that the few permitted measured facts "[were] taken before any arm ran". The new variance table
  records, per pinned C2 sample, how many findings the challenger produced (`0 of 15`, `0 of 12`,
  `15 of 15`), and the re-validation records a `15-element findings array` from a run at the pinned
  C2-a head. Those are counts of what an arm found, obtained by running the arm on the frozen
  samples — the first content in the file that is neither a pin nor a pre-run threshold. AC-5
  *mandates* the variance table, so the diff is doing what the ticket asked; what is missing is the
  corresponding amendment to the governing section. The file states it has "no mechanical oracle"
  for this rule and relies on a reviewer eyeballing for stray figures — that reviewer now has a
  rule that its own document contradicts, and no recorded exemption to resolve it against. The
  mitigation is present in §B (the three outputs are "discarded for scoring" and #747 re-runs all
  three) but lives nowhere near the rule it qualifies.
- **[Maintainability] `docs/skill-ablation-addendum.md`:312 vs :354 (confidence: 92) — the same
  capture is given two different sizes.** :312 describes the reaped capture as "a 2.3 MB, 831-line
  file"; :354 calls it "2.2 MB/831 lines". Same line count, same run, same paragraph subject. The
  already-merged `tools/classify-capture.sh`:8 independently records "a 2.3 MB, 831-line capture",
  so :354 is the outlier against two other statements of the same figure. In a document whose
  stated purpose is that apparatus claims be measured and re-runnable, one artifact with two sizes
  is the defect class the file exists to prevent.
- **[Maintainability] `docs/plans/second-shift-777-lean.md`:88-96 and the PR body (confidence: 85)
  — the Out-of-scope rationale claims an evidence record §B does not contain.** The spec defers the
  post-run assertion partly on the grounds that "AC-4's measured output records what the report did
  or did not name, which is what leaves #747 able to raise it on evidence rather than on
  assertion"; the PR body repeats it. §B:349-380 records exit status, stderr, wall time, byte and
  line counts, the completeness classification, the parent/subagent `tool_use` split, the
  `ReportFindings` payload shape, and the stdout residue — and says nothing about whether the report
  named the range it reviewed. The deferral itself is legitimate (D-2 narrows to capture, no ledger
  row disposes of the assertion) and the evidence #747 actually needs is already recorded elsewhere
  ("None of the three reports names the range it reviewed", :87-90), so this does not unsatisfy an
  AC. But as written the diff does not keep the promise the spec and the PR body make about it, and
  the capture it would have come from lives at `/private/tmp` and does not survive the merge. One
  sentence in §B closes it.

## Suggestions (consider)

- **[Complexity] `docs/skill-ablation-addendum.md`:364-367 (confidence: 80)** — the parent/subagent
  `tool_use` split table is a measured fact with no command printed beside it. The file's own
  standard for a permitted measured fact is that it be "labelled and re-runnable from the command
  printed beside it", and §B honors that everywhere else: the pre-run assertion is a literal `test`
  block, and the capture invocation is quoted verbatim. A reader cannot re-derive "476 subagent / 2
  parent" from the stream without inventing the `parent_tool_use_id` split themselves. AC-4's
  "assertion command run verbatim" is satisfied by the `claude -p` invocation on the better reading
  ("against the `c2-a-654` pinned clone" attaches to a command you run on a tree), so this is a
  standard-of-evidence gap, not an AC failure.
- **[Maintainability] `docs/skill-ablation-addendum.md`:336-337 (confidence: 60, suppressed below)**
  — see Suppressed.

## Plan Compliance

Implementation matches the spec. Every AC-1..AC-7 is delivered; nothing outside `Registration and
re-validation only` was touched — the diff is exactly the spec plus §B, and the three declared
out-of-scope surfaces (the committed challenger transcripts under
`docs/plans/skill-ablation/c2-review/`, `scoring.tsv`, and §2/§4 of `docs/skill-ablation.md`) are
untouched. No version, `CHANGELOG.md`, or `marketplace.json` edit (frozen-file rule respected). All
four commits carry a `Changelog:` trailer; `160e6b91`'s `Changelog: none.` takes the trailing-period
form, which `derive-release.sh` drops correctly because no indented continuation follows it.

## Pre-existing gaps (not blocking this PR)

- `docs/plans/second-shift-777-lean.md`:100-112 — D-7's "The §B:264-269 validation claim" is an
  imprecise anchor: at the branch base `d8ea88aa`, :264-267 is the *"No new harness is needed"*
  probe paragraph and the two-commit validation claim runs :269-272. The spec's own "Line citations"
  note discloses that these numbers are the pre-flight ledger's inherited text, and AC-3 cites the
  claim by quoted text instead, so the ambiguity never reaches the definition of done. Inherited,
  not introduced.

## Suppressed (below confidence threshold)

- `docs/skill-ablation-addendum.md`:336-337 — Confidence: 60 — the re-validation clone had
  `plugins/` deleted (374 working-tree deletions), which arm 2a's registered construction (:415-419)
  does not specify and :272-275 explicitly measures as unnecessary. So the validating run again used
  a substrate unlike the registered arm's — rhyming with the fixture-fidelity defect being fixed —
  but plugin absence has no plausible causal path to whether `ReportFindings` reaches the parent
  stream, and the divergence is disclosed in the text rather than hidden.
- `docs/skill-ablation-addendum.md`:441-448 — Confidence: 65 — "The output shape" subsection's
  claims still derive from the 2026-09-01 two-commit run whose fidelity this PR impeaches, and were
  not restated from the higher-fidelity measurement now in hand. The appended "Reports spans both
  sinks" block amends the mapping those claims feed, which is the part that matters.
- `docs/skill-ablation-addendum.md`:327 — Confidence: 55 (scope-completeness-reviewer) — the
  post-run assertion remains unevaluable and is untouched by the diff; the issue scopes its change
  to "capture only" and its scoring consequence is discharged by the :299-301 disposition.

## Verdicts

| Reviewer           | Verdict          | Findings | Confidence Range |
| ------------------ | ---------------- | -------- | ---------------- |
| Scope Completeness | Pass             | 0        | —                |
| Security           | Lead pass — ✅   | 0        | —                |
| Performance        | Lead pass — ✅   | 0        | —                |
| Complexity         | Lead pass — ✅   | 1        | 80               |
| Maintainability    | Lead pass — ✅   | 2        | 85-92            |
| Test Coverage      | Lead pass — ✅   | 0        | —                |

**Ready to merge?** With fixes (advisory — no blockers)

**Reasoning:** All seven ACs are satisfied and the load-bearing claim (the flag pair changes what is
recorded, not what is run) is mechanically verified against the pre-amendment text. The three
warnings are documentation-integrity defects in an evidence-grade registration — a rule the diff
contradicts without amending, one artifact given two sizes, and a promise the PR body makes that the
recorded measurement does not keep — none of which corrupts the frozen metric or blocks the
consuming slice.

## AC scorecard

| AC-n | score | evidence |
| ---- | ----- | -------- |
| AC-1 | satisfied | `docs/skill-ablation-addendum.md`:257-263 adds `--output-format stream-json --verbose`; :264-270 states the capture-flags-only claim. Verified literally: diffing the `env -u` set and every flag between `0978ee14` and `5ac0541c` shows only the two added flags and one line continuation — command, `--model opus`, effort `max` (in the piped prompt), and `--allowedTools "Read,Grep,Glob,Bash"` unchanged. |
| AC-2 | satisfied | :457-473 "Reports spans both sinks": the finding set is the union of the report tool's input and the final assistant text, deduplicated on same-mechanism-and-consequence (the frozen hit rule's own predicate, so no new scorer judgment). :471-473 states it is a refinement of the preceding sentence, not a replacement; no severity filter and no demotion are introduced. |
| AC-3 | satisfied | The `**Measured 2026-09-01, the exact form above was also run end-to-end**` paragraph is DELETED by the diff (a `-` hunk, not relocated — `grep` at HEAD finds no surviving copy). :325-333 replaces it with "Validation of the recipe — superseded, and by what", which states the insufficiency: a two-commit diff yields a prose answer, so the report-tool path two of three real samples take was never exercised, and says explicitly it *replaces* rather than supplements. |
| AC-4 | satisfied | :335-347 records the run against the `c2-a-654` pinned clone with both pins asserted (`main` at `dfd68a47`, head at `cfba1022` — matching the frozen table at :409-413) and the invocation verbatim. :357-371 records the measured output: 2 parent-level `tool_use` events, both `ReportFindings`, against 476 subagent events; each carries a 15-element `findings` array with `file`/`line`/`summary`/`failure_scenario` intact. The assertion HELD, so D-4/OR-1's payload-plus-stdout fallback is correctly not registered. |
| AC-5 | satisfied | :277-301: the variance table records all three pinned samples measured under the pre-amendment form (C2-a `0 of 15`, C2-b `0 of 12`, C2-c `15 of 15` recoverable from stdout) as the defect this amendment answers, with the non-determinism argument. :299-301 registers the disposition — "discarded for scoring", retained as the defect measurement only, with #747 re-running all three under the amended capture. See the cross-cutting warning above on the tension with :34-44. |
| AC-6 | satisfied | Verified by citing CI, not re-run: run 33674825615 at head `5ac0541c` (identical to the reviewed head). `lint-and-selftests` — success; its shellcheck step (`.github/workflows/ci.yml`:31) is byte-identical to the AC's shellcheck command, `find` over every `*.sh` piped into `xargs -0 shellcheck -e SC1091,SC2015,SC2181`. `selftests (macos, bash 3.2)` — success. Both selftest lanes run `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh --cache-dir ...`, a strict superset of the AC's command (74 suites vs 61). `mutation-sweep-pr` — success. No new checked-in script: the diff adds two `.md` files and nothing else. The only red step, `pr-gates`, fails solely on `lean-evidence`'s "no committed verdict record" arm — the merge-boundary artifact this record IS, which cannot be green before it is written. |
| AC-7 | satisfied | :303-323 registers the rule: classify every capture with `tools/classify-capture.sh` before reading a finding out of it; only exit-`0` is scored; `TRUNCATED` or a completed failure is discarded and re-run, never recorded as a null result. The documented exit codes (`0` complete-success, `1` completed-but-failed, `2` truncated, `3` unreadable input) match the shipped `tools/classify-capture.sh`:32-35 and its four exit sites exactly. AC-4's own measurement records its verdict — `COMPLETE`, `subtype=success`, `is_error=false`, 4 `result` events with the last governing (:351-355) — and records the two captures discarded as `TRUNCATED` before it, so the rule is registered having been applied to itself. |
