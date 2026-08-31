# lean review verdict — #723

verdict=needs-work
run_id: review-723-1
session_id: 734f72b2-7bd1-43b3-b833-0980f41d4c8c
rounds: 1
pr: #754
reviewed_head: d9ab878589760c05f599ecbddc2fc40f854ddfe5
reviewed_patch_id: 2b194563801f4c8f2956c75ad535b38de28e43fe
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

## Findings

| # | Severity | Dimension | File | Finding |
| --- | --- | --- | --- | --- |
| 1 | **blocker** | Cross-cutting (rendered surface) | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:5861-5866` | `cost_block_with_usd_key` inserts the key **immediately after the marker line**, directly above the block's `---`. In CommonMark/GFM a paragraph line followed by `---` is a **setext H2 underline**, so the block's thematic break is consumed and the machine key renders as a heading. Measured through GitHub's own renderer (`POST /markdown`, `mode: gfm`) against **PR #754's real cost block**, transformed by the PR's own awk: output is `<h2>cost_usd: 9.90</h2><h2>Pipeline Cost</h2>` with **no `<hr>`**. Control (base `main`, no key) renders `<hr><h2>Pipeline Cost</h2>`. Every closed-out lean PR description gets this permanently. |
| 2 | major | Test coverage / mutation | `lean-gate.sh:5887` | The `resolve_cost_usd` call inside `closeout_cost_block()` — the **only** production call site that populates `$LEAN_COST_USD` before a real close-out — is never exercised. `co_resolve()` and `co_comment()` both set `LEAN_COST_BLOCK`/`LEAN_COST_SKIP` by hand and call `resolve_cost_usd` themselves, bypassing `closeout_cost_block` entirely; `resolve_cost_usd` occurs exactly twice in the suite, both in those helpers. Deleting line 5887 ships `- cost_usd: ` (blank) on every real run — the precise regression #723 exists to prevent — with zero test signal. |
| 3 | major | Test coverage / mutation | `lean-gate.sh:5863` | Dropping the `next` from the marker arm makes awk fall through to `{ print }`, **duplicating the marker line**. Verified directly on the awk: mutant output carries 2 marker lines. No new case catches it — (co7)/(co8)/(co8b) grep for specific lines only, (co10)/(co11) never route through this function, and (co9) survives because `closeout_patch_pr_body`'s strip span swallows the duplicate before the second call's `grep -c '^cost_usd:'`. A `grep -c '^<!-- pipeline-cost-block -->'` equals-1 assertion in (co9) would kill it. |
| 4 | major | Correctness (docs) | `plugins/dev-pipeline/cost-tracking-setup.md` | The recipe's window is `gh pr list --state merged` over **all** PRs, so release PRs and other non-lean PRs — which by construction can never carry the key — sit in the coverage denominator and are scored `unreported`. Run verbatim now: `mean: $41.95 over 4 of the last 10 merged PRs; 6 unpriced`, and `#751` in that set is `release: v12.2.2`. D-5 designates this coverage line as "the standing measurement" for whether the unpriced-run gap earns a follow-up ticket, so it is biased low. Also a spec-internal divergence: D-4 says "the last 10 merged **lean** PRs", AC-6 and the code say "the last 10 merged PRs". Filtering on the configured `tracker.branchPrefix` via `headRefName` would resolve both. |
| 5 | suggestion | Maintainability | `lean-gate.sh:5834` | `grep -oE '\$[0-9]+\.[0-9]{2}' \| head -1` is correct today only because `fmt()` in `pipeline-cost-block.sh` is the sole `$` emitter and `render_block` renders exactly one data row — verified in both files. The comment records the coupling, but nothing fails if a later per-stage breakdown adds a second cost cell: `head -1` would then silently publish a partial figure as an authoritative machine key. |

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `closeout_comment()` emits the bullet unconditionally at `lean-gate.sh:5969`, beside `- PR:` / `- Verdict record:` and before the `[ -n "$LEAN_COST_BLOCK" ]` block paste. `closeout_cost_block`'s two failure returns abort close-out at `:6032` before the comment is reached, so a value always exists by then. Suite cases (co10)/(co11). |
| AC-2 | satisfied (raw), see finding 1 | The line is present exactly when a block is published: `:6050-6052` routes to `closeout_patch_pr_body` only on the non-skip arm, and the two arms are mutually exclusive by the `case` at `:5883-5886`. The AC's literal text is met; the rendered result is finding 1. |
| AC-3 | satisfied | Bare decimal via `tr -d '$'` (co7); both D-7 reasons distinguished and correctly assigned (co8 rendered-no-column, co8b no-block). |
| AC-4 | satisfied | `cost_block_with_usd_key` pipes `$LEAN_COST_BLOCK` through awk without assigning back; `closeout_comment` pastes the raw shared block. (co7) asserts the block stays pristine, (co10) asserts exactly one `cost_usd:` in the comment. |
| AC-5 | satisfied | The insert lands inside the marker→terminator span that `closeout_patch_pr_body`'s strip discards (`:5926-5929`, terminator `Cache-hit rate: ` matched by `index($0,t)==1`). (co9) drives the real production call twice with two figures and asserts exactly one line holding the second. |
| AC-6 | satisfied, see finding 4 | Ran the documented recipe verbatim: exits 0, prints 10 rows with `src` provenance, recovers 4 legacy figures, prints the mean over the priced subset and the unpriced count, imputes nothing. Spot-checked #742/#744/#740/#735 — each body carries exactly one `$N.NN` and it is the cost cell, so the legacy capture is accurate. |
| AC-7 | satisfied | `git diff --name-status main...HEAD` = 4 paths: the spec (added) plus `cost-tracking-setup.md`, `lean-gate.sh`, `lean-gate-selftest.sh`. No `pipeline-cost-block.sh`, `retro-corpus.sh`, `cost-log.jsonl`, `perf-retro`, no new script, no jira code. |
| AC-8 | satisfied, see findings 2-3 | All six enumerated cases exist and pass: (co7) priced + both copies, (co8) rendered-unpriced reason, (co8b) full-skip reason, (co9) re-entry non-duplication, (co10) comment-says-it-once, (co11) full-skip bullet. The AC's enumeration is met; the gaps in findings 2-3 lie outside it. |
| AC-9 | satisfied | Commit is `feat(dev-pipeline): …` with a `Changelog:` trailer carrying prose plus `Migration: none.`. No `plugin.json` `version`, `CHANGELOG.md`, or marketplace `version` in the diff. |

**Design fidelity: not-applicable.** The spec's `## Design` reads `Design: none — this is a shell-string change plus a documentation recipe, no web surface, and this repo configures no design.provider`. Verified: the diff has no web-component surface, and `jq '.design'` on the repo config returns `null`. The disarm is justified.

## Verification performed

- **CI cited, not re-run** (run `33439242209`, `headSha` `d9ab878589760c05f599ecbddc2fc40f854ddfe5` = the reviewed head): `lint-and-selftests` **pass** (4m12s) and `selftests (macos, bash 3.2)` **pass** (10m13s). Both run the repo's own sweep command, so AC-8's oracle is verified by citation.
- `lean-gate-selftest.sh` run locally at the same head as a cross-check: **594 pass, 0 fail, "all green"**.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean locally (0.11.0); the CI-pinned 0.9.0 is covered by the cited `lint-and-selftests` pass.
- `pr-gates` **fail** is the expected pre-approval state and is NOT a finding: its sole red is `no committed verdict record (a file named *-723-lean-verdict.md)`, which this round produces. No correctness lane is red.
- `mutation-catalog.tsv`: all 55 `lean-gate.sh` rows still anchor at HEAD (0 stale, same as at base), so the guard-edit re-anchoring obligation is met.
- `mutation-sweep-pr` passed in 14s having **graded nothing** — its log states it plainly: "PR mode graded NOTHING: all 1 in-scope guard(s) deferred to the merge-time sweep, 0 swept (reasons: slow suite: 1)". Its green is structurally vacuous here, so findings 2-3 are the only mutation signal on this PR.
- **How findings 2-3 are evidenced, precisely.** Finding 2 rests on static analysis, not on an executed mutant: `closeout_cost_block` has zero call sites in `lean-gate-selftest.sh`, and `resolve_cost_usd` occurs there exactly twice, both inside the `co_resolve`/`co_comment` helpers that set the globals by hand — so no test can observe line 5887. That is corroborated independently by `unit-test-mutation-reviewer` at confidence 88. Finding 3 rests on running the mutated awk directly: the `next`-dropped form emits the marker line twice. A confirming full-suite probe of both was started in an isolated worktree and **abandoned unfinished** under git-lock contention from two other lean-gate suites running concurrently on this machine; **no executed `SURVIVED` verdict is claimed**, and neither finding needs one.
