# lean review verdict — #812

verdict=approve
run_id: review-812-2
session_id: b5d0b81a-c877-4512-81d8-310b8dfc86a1
rounds: 2
pr: #814
reviewed_head: a72948664fbd0e7ef68c413d6835ddb7f2f25277
reviewed_patch_id: aefe45275c579f9274c84651717e136c3bb07743
inherited_patch_id: 73456842bc0d21ddfd857e5e76418d49596c0d93
inherited_from_verdict: 5cbe02e51a440a37478b7cf4469c2dc602142dd2
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

Round 2 over the delta range `5cbe02e5..HEAD` — `G delta` printed the range since the tree round 1 covered (patch `73456842bc0d`), and the rest is inherited by reference to that record. Four files, +26/-2: the `D-19` ledger row, selftest case `(a6)`, two `tools/lane-bench.sh` fixes, two `tools/mutation-baseline.tsv` rows. Panel: `review-toolkit:scope-completeness-reviewer`, `review-toolkit:unit-test-mutation-reviewer`, plus the in-session lead pass. No reviewer went dark. a11y and design fidelity were not routed: no changed path is a web component, and the spec's `## Design` section is disarmed (`Design: none`).

I read round 1's findings before reading the delta, so a fixed blocker is distinguishable from a re-introduced one.

**Both round-1 blockers are discharged, and both were verified rather than taken on the commit's word.**

`B1` — the two baseline-absent survivors now carry `tools/mutation-baseline.tsv` rows, and `mutation-sweep-pr` is GREEN at this head: `applied=14 killed=12 survived=2`, with `survivor_ids` naming exactly `tools/lane-bench.sh::default::a98c5b90cbb9` and `::bfb857ec55a8` — the same two ids, so the sites did not re-anchor under the code edit. Both rows' rationales are truthful against the code: `tools/mutation-sweep.sh:1468`'s `run_killer` unconditionally sets `TMPDIR="$KILLER_TMPDIR"` before every killer suite, and `tools/lane-bench-selftest.sh:123` exports `GH="$BIN/gh"` once with no later unset. An independent `--emit-site-keys` enumeration confirms those are the file's *only* two `default`-operator sites, so the baseline is neither under- nor over-populated.

`B2` — `D-19` is now in the committed ledger at `docs/plans/second-shift-812-lean.md:81`, so `tools/lane-bench.sh:37`'s `(#812 D-19)` resolves. The row matches D-17/D-18's six-column shape, its provenance `codebase-derived` is inside the closed enum, and `ledger-lint.sh` reads 19 rows OK. The row's text is a one-to-one match for the comment's two premises and its conclusion, not a generic pointer. The citation sweep over the whole branch diff — six distinct `(#812 D-n)` ids — now resolves clean, with no dangling id.

Round 1's `W1` and `S2` were also fixed, unprompted. `W1`'s fix is probe-verified: reverting `|| [ -n "$d_id" ]` in an isolated worktree fails case `(a6)` with exactly `catch=2/2` — the flattering denominator the commit predicted — so the new case kills its own mutant rather than asserting a row count. All four `tools/mutation-catalog.tsv` anchors on this file still match exactly once each at head, and the sweep killed all four.

Verified at the reviewed head: `tools/lane-bench-selftest.sh` 23 passed / 0 failed, and 23/0 again under `bash 3.2` with nested `bash` shimmed to 3.2, so the new constructs are portable to the lane that scores them. `shellcheck -e SC1091,SC2015,SC2181` clean on both scripts; `tools/prose-blockers.sh check` green.

One new finding, from the fix to round 1's `S2`. Two carried forward from round 1, unchanged by this delta.

## Findings

| # | severity | file:line | finding |
| --- | --- | --- | --- |
| W1 | warning | `tools/lane-bench.sh:245` | The `grep -E`→`awk` rewrite fixes the metacharacter exposure but leaves detector 1 disagreeing with the two other readers of the same `TEST` line format, which are still the anchored greps at `:229` and `:236`. Probed both directions on one fixture: `  TEST t-b FAIL` (leading whitespace) is matched by the new awk and NOT by either grep, so `defects_at_head` can count a defect whose test is outside `tests_passed`/`tests_total`'s denominator; `TEST t-a PASS\r` (CRLF) is matched by grep and NOT by the awk — `$3` becomes `FAIL\r` — so the tool would fire the D-6 detector-pair refusal on a test that reported cleanly. Plain trailing whitespace is identical under both, so the corpus is unaffected. Not a blocker: `docs/lane-bench.md:77` declares the channel as a bare `TEST <id> PASS\|FAIL` line, both inputs are outside that contract, no fixture constructs either, and every correctness lane is green. Worth closing by giving all three parsers one matcher. |
| W2 | warning | `tools/lane-bench.sh:101` | Carried forward from round 1, untouched by this delta. The `$2 == "unscorable"` integrity check remains unkillable by the suite: `CLASSES` is hardcoded with no flag and no case builds a table missing the row, so flipping `==` to `!=` lets the first data row set `found` and the guard still exits 0. It defends against documentation drift, not against `score`. A `--classes` seam or a fixture table would make it real. |
| S1 | suggestion | `tools/lane-bench.sh:90-96,156` | Carried forward. The input-validation guards — the `--issue` numeric form, the five existence/readability checks, `SEEDED -gt 0` — still have no case driving them; only the `run.sh`-presence guard at `:94` is exercised. They degrade error-message quality rather than correctness, and the sweep's `k=2` budget would not reach them. |
| S2 | suggestion | PR body | The body's figures predate this delta: it says "22 cases" and "four of the twenty-two", where the suite now reports 23; the `~3.4s` timing D-18 obliges it to record is stale by one case (still far under the 9s threshold, so D-18's no-timings-row conclusion holds); and the Verification section was measured at `ec8560d3`, so it never mentions the sweep red or the two baseline rows that answer it — the round-1 blocker a reader would most want recorded. No AC binds the PR body, and I confirmed the underlying facts independently, so this is record-keeping. |

Merge-boundary state, recorded not blocking: `pr-gates` is red on `lean chain reconciliation` ONLY — structural before a verdict record exists on the branch. `frozen files` and `changelog trailer` both pass. The three correctness lanes are green at this head: `lint-and-selftests`, `selftests (macos, bash 3.2)`, and `mutation-sweep-pr`.

Not scored as a finding: `--issue` is a departure from the CLI shape the issue body declared, ratified by `D-19` rather than by an issue-body amendment. That is the legitimate route here — the committed spec is the definition of done, its `### In` names the tool and its suite without restating a flag list, and no AC binds the CLI signature. The addition is consistent everywhere it surfaces.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Re-scored at this head, not inherited. `docs/lane-bench.md` carries every named element: the arm definition with control/skeleton/candidate ref (`:28`), the two tiers (`:168`), the seven corpus roles (`:55-61`), the gold with its per-defect detector pair (`:72-88`), the nineteen results-row columns in the order AC-8 names (`:128-140`), the terminal-class table over the full slug vocabulary as data by link (`:147`, the narrowing D-5 ratified), the comparability rule for `rounds`/`wall_min` (`:188-196`), the cost bound (`:177-185` — sequential cells on the subscription rate limit, `--max-rounds 2`, three repeats at full), the pre-registration rule with its noise band and minimum detectable effect as fields only (`:211`), the series definition with re-baseline and append-only (`:198`), and the anonymization rule naming the private repos only as "the private eval substrate" (`:20-27`). The vocabulary claim is falsifiable rather than prose: case (j2) derives the slug set out of the shipped `orchestrate-lean.sh` and compares both directions, with (j1) as its anti-vacuity arm — 41 slugs derived on my run, table and scheduler agreeing. The delta touches neither file. |
| AC-8 | satisfied | Every named column is written by `write_row` and read back per column by case (a1); the four scenarios AC-8 names each have a dedicated case — every column (a1), `n/a` (c1, asserting `review_catch=n/a` with an empty `defects_named`), an unapplicable overlay (g1), an ambiguous PR (f1). This delta strengthens the AC rather than merely preserving it: `review_catch` is specified as "`defects_named` over defects **seeded**", and the read-loop fix is what makes the denominator actually equal the seeded count on a hand-authored TSV — probe-verified, `2/3` where the unfixed loop scored `2/2`. Detector 1 still refuses a defect whose test id the overlay never reports; case (i4) exercises it under the new awk matcher. Suite run at this head: 23 passed, 0 failed, and 23/0 under bash 3.2. |
| AC-11 | satisfied | `git diff origin/main...HEAD` grepped for consumer, org and private-repo identifiers across all eight files and all seven commit messages: zero hits. Read the delta's added prose — the D-19 row, the selftest comments, the two baseline-row notes, the code comments — end to end; nothing names a consumer repo, org or GitHub App, and the substrate and bench repo are referred to only as "the private eval substrate". The authoritative denylist is operator-side and outside the repo, so that grep remains the operator's to run before merge; the added surface here is small enough that the substantive claim was checked by reading. |
| AC-12 | satisfied | The branch diff touches eight files, none under `plugins/**`, none named `CHANGELOG.md` or `marketplace.json`, and no plugin `version` field appears in it. Independently confirmed by CI — `pr-gates` step 3, the frozen-files guard, passed at this head. All commits carry a `Changelog:` trailer; the trailer guard passed too. |
