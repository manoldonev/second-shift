# lean review verdict — #812

verdict=needs-work
run_id: review-812-1
session_id: 093302a3-3162-4c7d-9f85-2c22794de137
rounds: 1
pr: #814
reviewed_head: ec8560d3af5463160028e56030f693ad3c11a4b3
reviewed_patch_id: 73456842bc0d21ddfd857e5e76418d49596c0d93
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

Round 1 over the full branch range `3912f458..ec8560d3` (`G delta` printed FULL — nothing verifiable to inherit). Panel: `review-toolkit:scope-completeness-reviewer`, `review-toolkit:unit-test-mutation-reviewer`, plus the in-session lead pass (performance, maintainability, complexity, test coverage, and security — its conditional did not fire: no auth/tenancy/session/upload surface, and the repo carries no `review-context/security-reviewer.md`). No reviewer went dark. a11y and design-fidelity were not routed: no changed path is a web component, and the spec's `## Design` section is disarmed (`Design: none`).

The work itself is strong. The terminal-class map is derived from the shipped scheduler in both directions with its own anti-vacuity arm; the empty-is-not-zero rule is carried by four separate cases; the fixture substrate is a real git repo with two committed verdict-record versions, so D-2's "any version counts" claim is measured rather than asserted. I ran `tools/lane-bench-selftest.sh` at the reviewed head: 22 passed, 0 failed.

Two blockers, both about the record rather than the design.

## Findings

| # | severity | file:line | finding |
| --- | --- | --- | --- |
| B1 | blocker | `tools/lane-bench.sh:158,186` | `mutation-sweep-pr` is RED at this head: `baseline-absent survivor: tools/lane-bench.sh::default::a98c5b90cbb9` and `::bfb857ec55a8`, applied=14 killed=12 survived=2. Those are the `${TMPDIR:-/tmp}` and `${GH:-gh}` seams, and the branch adds no `tools/mutation-baseline.tsv` rows. `docs/testing.md:1725` states the remedy verbatim — copy each named id in as `<survivor_id><TAB><note>` and commit it "in the PR that wrote the site" — and #779/PR782 is the exact precedent, a new `tools/*.sh` guard whose own feature commit carried its `${TMPDIR:-/tmp}` row. D-12 predicted these survivors ("baseline-absent survivors on first push") and then discharged nothing. A red correctness lane is a blocker under this skill's own rule. |
| B2 | blocker | `tools/lane-bench.sh:37` | The comment justifying the added `--issue` flag cites `(#812 D-19)`. `grep -c 'D-19' docs/plans/second-shift-812-lean.md` returns 0; the committed ledger's last row is D-18. The PR body repeats the claim ("It is an explicit input (D-19)"). `--issue` is an addition to the CLI contract the issue body declared, so its ratification is exactly what the citation is for — and it resolves to nothing. No gate reads a code-to-ledger citation, so this lands here or nowhere. Fix: add the D-19 row, or re-point the citation at `docs/lane-bench.md`'s paragraph, which does carry the reasoning. |
| W1 | warning | `tools/lane-bench.sh:147` | The seeded-defect read loop drops a final row that carries no trailing newline: `read` populates the vars and returns non-zero, so the body never runs. Probe-verified — a two-defect TSV whose last line lacks `\n` yields `SEEDED=1`. That silently changes `review_catch`'s denominator and skips the D-6 detector-pair refusal for the dropped defect, on an operator-hand-authored file. Not a blocker: 218 of the repo's 219 `while IFS= read` loops share this shape, so it is a repo-consistent pattern, not a new gap. `|| [ -n "$d_id" ]` closes it. |
| W2 | warning | `tools/lane-bench.sh:101` | The `$2 == "unscorable"` integrity check is unkillable by the suite as written. `CLASSES` is hardcoded to `$HERE/lane-bench-classes.tsv` with no flag, and no case builds a table missing the row — mutate the comparison to `!=` and the first data row (`approved<TAB>approved<TAB>-`) sets `found` and the guard still exits 0. It only defends against documentation drift, not against `score` itself, so it is a warning; a `--classes` seam or a fixture table would make it real. |
| S1 | suggestion | `tools/lane-bench.sh:90-96,156` | The input-validation guards — `--issue` numeric form, the five existence/readability checks, and `SEEDED -gt 0` — have no case driving them. Only the `run.sh`-presence guard (:94) is exercised, by (i3). They degrade error-message quality rather than correctness, and the sweep's `k=2` budget would never reach them, so this is cheap-to-add rather than owed. |
| S2 | suggestion | `tools/lane-bench.sh:240` | `${t}` (a defect's `test_id`) is interpolated unescaped into a `grep -E` pattern. Corpus ids like `t-sep` are inert, but an id carrying `.` or `+` would match more than its own TEST line and mis-score `defects_at_head`. |

Not scored as a finding: `scope-completeness-reviewer` flagged (confidence 92) that issue #812's Scope>In says `score` "runs the substrate's configured `test` command" while the tool deliberately does not. The committed spec's D-1 ratifies exactly that narrowing and states the reason (a single exit code cannot say WHICH hidden test a defect broke, which the detector pair requires); the committed spec is this round's definition of done, and AC-8 — the criterion that grades the behavior — asks only for hidden tests passed/total. The issue body's prose is stale, not the code.

Merge-boundary state, recorded not blocking: `pr-gates` is red on `lean chain reconciliation` only, which is structural before a verdict record exists. `frozen files` and `changelog trailer` both passed; all four commits carry `Changelog: none` and nothing under `plugins/**` is touched.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `docs/lane-bench.md` carries every named element: arm definition with control/skeleton/candidate-ref, the smoke and full tiers, the seven corpus roles, the gold with its per-defect detector pair, the nineteen results columns, the comparability rule for `rounds`/`wall_min`, the cost bound (sequential cells on the subscription rate limit, `--max-rounds 2`, three repeats at full), the pre-registration rule naming its noise band and minimum detectable effect with no values, the series definition with re-baseline and append-only, and the anonymization rule naming the private repos only as "the private eval substrate". The terminal-class table is present as data by link rather than as prose — the narrowing D-5 ratified — and `tools/lane-bench-selftest.sh` case (j2) holds the "full slug vocabulary" claim to account against the shipped scheduler in both directions, with (j1) as its anti-vacuity arm. Verified at the reviewed head: 41 slugs derived, table and scheduler agree. |
| AC-8 | satisfied | Every named column is written by `write_row` (`tools/lane-bench.sh:167-179`, columns 13-19) and read back per column by case (a1); `defects_at_head` is detector 1 (:238-244), `defects_named` detector 2 across every committed record version (:247-265), `review_catch` the fraction with `n/a` when no record exists (:249,265). The selftest covers all four required shapes: every column (a1-a5), `n/a` (c1), an unapplicable overlay (g1), an ambiguous PR (f1). Ran it at this head — 22 passed, 0 failed. |
| AC-11 | satisfied | Read all six changed files end to end plus the PR body, the issue body and all four commit messages: no consumer repo, org or GitHub App is named anywhere, and the substrate and bench repo are referred to only as "the private eval substrate". A targeted grep for known consumer and private-repo identifiers over the changed set returns nothing. The authoritative denylist is operator-side and outside the repo, so that grep remains the operator's to run; the artifacts here are small enough that the substantive claim was checked by reading. |
| AC-12 | satisfied | The branch diff touches six files, none under `plugins/**` and none named `CHANGELOG.md`; no plugin `version` field appears in it. Independently confirmed by CI — `pr-gates` step 3, the frozen-files guard, passed at this head. |
