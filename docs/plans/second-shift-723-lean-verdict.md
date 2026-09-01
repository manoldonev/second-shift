# lean review verdict — #723

verdict=approve
run_id: review-723-3
session_id: 64f43bc8-8395-463b-b3e9-b61b5efa4ca9
rounds: 3
pr: #754
reviewed_head: 8a116ea6ec15a01ab5c71426a93844532bedcca1
reviewed_patch_id: 1c4b0f55beb1036260e468f7f8d95b531d1bd4d2
inherited_patch_id: 79013973c1ff0f7470b806670af70ce8426c90d6
inherited_from_verdict: 716a337377e6d9fceba1969fc5a9d04fc814d3e4
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

## What this round read

The delta the gate derived is `716a3373..HEAD`: a base merge of `origin/main` (`141ec546`,
bringing #755's AC-scorecard layer) and a one-line whitespace restore (`8a116ea6`). **The
branch's own contribution did not move.** Its added-line set and its deleted-line set against
its base are byte-identical to the patch round 2 approved — measured, not assumed, by sorting
both three-dot diffs and diffing the `+`/`-` line sets (empty both ways).

The merge boundary agrees independently: `pr-gates` at this head prints
`freshness — the recorded patch identity 79013973c1ff and this head's 1c4b0f55beb1 differ,
which a base advance alone is enough to cause, and every one of the branch's own +/- lines is
unchanged since reviewed_head 535a427fc592 — no reviewed line was altered, so the verdict
stands (#597 AC-1)`.

## Why a round happened anyway

`pr-gates` is red at this head on exactly one violation, and it is not about the code:

```
✗ verdict record 'docs/plans/second-shift-723-lean-verdict.md' — AC scorecard:
  no "## AC scorecard" section — an approve must score every AC-n the spec declares,
  and this record scores none
```

Round 2 was written at 21:56 under the pre-#755 contract, which had no scorecard section.
#755 merged at 22:13. The base merge at 22:16 pulled main's new **reader** into the branch,
and that reader refuses a record written before the key existed — it carries no transitional
arm. Reproduced locally at this head:
`lean-evidence.sh scorecard --spec … --verdict approve < <record>` emits the same line.

So the round is spent on a record-format migration, not on a defect. This round's record is
written in the current schema; the code verdict is unchanged.

## Findings

No new code findings. Round 2's seven open items were each re-verified as unchanged at this
head and are carried forward; none is a blocker.

| # | Severity | Dimension | File | Finding |
| --- | --- | --- | --- | --- |
| 1 | major (carried, r2 #1) | Test coverage / mutation | `lean-gate-selftest.sh:8924` | Dropping the `next` from `cost_block_with_usd_key`'s `---` arm re-emits the break AFTER the key, and no case catches it: `(co7b)` asserts only the first three lines, which the mutant reproduces byte-for-byte. Re-verified unchanged — a targeted grep over `git diff 535a427f HEAD` for `co7b` and for the function's own lines returns zero hits, so the gap is exactly as round 2 described it, no wider. |
| 2 | major (carried, r2 #2) | Correctness (latent) | `lean-gate.sh:5918-5924` | `cost_block_with_usd_key` is fail-silent: it inserts only when a bare `---` follows the marker, and that `---` is a third shared literal with no `check-lockstep-pairs.sh` anchor. A marker-bearing block without one returns verbatim — no key, no warning. Unreachable today; `render_block` emits both together. Unchanged. |
| 3 | minor (carried, r2 #3) | Comment accuracy | `lean-gate-selftest.sh` `(co9)` | The comment claims a shape `(co1)`-`(co8b)` never catch; `(co7b)`, inside that range, does catch it. Unchanged. |
| 4 | minor (carried, r2 #4) | Comment accuracy | `lean-gate-selftest.sh` `(co7b)` | The comment claims the key is "never followed by `---` again"; the assertion reads three lines and cannot see line 4. Unchanged. |
| 5 | minor (carried, r2 #5) | Correctness (docs) | `cost-tracking-setup.md:203` | The `src` legend glosses `unreported` as "a pre-#723 PR with no cost block, or a documented skip". Re-run this round: five `unreported` rows now (#750, #755, #749, #741, #738), and the three round 2 opened each HAD a rendered block with no `Cost (USD)` column. The gloss still does not name that case. |
| 6 | minor (carried, r2 #6) | Cross-file coupling (docs) | `cost-tracking-setup.md:161-164` | The recipe decides "lean" by `headRefName`; `retro-corpus.sh:435-441` still carries a committed comment asserting the opposite discriminator for its own lean selection. Harmless today. Unchanged. |
| 7 | nit (carried, r2 #7) | Cosmetic | `cost-tracking-setup.md:186` | The mean drops a trailing zero. Reproduced verbatim this round on a moved window: `mean: $37.1`, not `$37.10`. |
| 8 | suggestion (carried, r2 #8) | Maintainability | `lean-gate.sh:5880` | `grep -oE '\$[0-9]+\.[0-9]{2}'` piped to `head -1` is correct only while `fmt()` is the sole `$` emitter and `render_block` renders one data row. Unchanged. |
| 9 | advisory | Lane, not this PR | `lean-evidence.sh` (#755) | #755 shipped a verdict-record schema requirement with no transitional arm, so every in-flight lean PR whose record predates it is retro-redded and must spend a full review round on a format migration. This PR is the first instance. Routed to the operator, not to this build. |
| 10 | nit | Commit hygiene | `8a116ea6` | The subject carries no conventional-commit type and no `Changelog:` trailer of its own. Neither check is harmed — the trailer is extracted grep-anywhere from `d9ab8785`, the bump derives from the highest verb on the branch, and the squash subject is the PR title `feat(dev-pipeline): …`. |

## Merge integrity — the resolution claim was verified, not taken

`141ec546`'s message claims the `lean-gate-selftest.sh` conflict was "purely additive on both
sides with no shared symbols; both blocks are kept, ours first." Checked:

- **Nothing lost from main.** `git diff 8200f1c3 HEAD` over the two shell files deletes exactly
  five lines, all five of them this branch's own intended edits, verbatim. No #755 material.
- **Nothing lost from the branch.** `git diff 716a3373 HEAD` over the same files deletes exactly
  six lines, all six of them #755's own replacements. No `(co…)` and no `cost_usd` line.
- **Nothing duplicated.** Zero duplicate function names in either file. The set of case-ID
  labels appearing more than once is byte-identical at `8200f1c3`, at `535a427f` and at HEAD —
  the merge added none. The nine `(co…)` and ten `(vs…)` cases each occur exactly once.
- **No shell-scope collision.** The two blocks now share one process. Their variable-name sets
  intersect in nothing (`comm -12` empty); the co block uses `co_rc`/`co_out` where the vs block
  uses bare `rc`/`out`. Every `cd` in both runs inside a `( … )` subshell; no file-scope `trap`.
- **The blank line is cosmetic.** `8a116ea6:9073` sits between a `fi` closing a completed `if`
  and a `#` section header — outside every heredoc, awk program and brace continuation. The
  nearest heredoc closed six lines earlier.
- **`origin/main` is fully contained.** `git diff origin/main...HEAD` is the same five paths and
  the same 483 insertions as before the merge.
- All **62** `tools/mutation-catalog.tsv` rows targeting `lean-gate.sh`, `lean-evidence.sh` or
  `lean-gate-selftest.sh` — the branch's own and the six #755 added — re-anchor at this head with
  `sed -E`: 62 apply, 62 yield `bash -n`-valid output, 0 stale.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean-gate.sh:6027` `echo "- cost_usd: $LEAN_COST_USD"`, between the `- Verdict record:` bullet and the `[ -n "$LEAN_COST_BLOCK" ]` paste, unconditional — so present on a full skip. Cases `(co10)`/`(co11)`. |
| AC-2 | satisfied | `lean-gate.sh:5991` composes head + `cost_block_with_usd_key` + tail; reached only from the `elif` at `:6110` whose `if` arm at `:6108` handles `$LEAN_COST_SKIP`, so a full skip patches nothing. Re-measured end-to-end this round: the real function over PR #754's own published block, composed into the real body, through `POST /markdown mode gfm` — `<hr>` then `<p dir="auto">cost_usd: 19.88</p>`. Control on the same renderer with round 1's placement yields `<h2>cost_usd: 19.88</h2>` and no `<hr>`, so the probe is sensitive. Finding 2 is a latent condition on that presence, not a present failure. |
| AC-3 | satisfied | `resolve_cost_usd` `lean-gate.sh:5875-5889`: `tr -d '$'` gives a bare decimal at `:5882`; D-7's two reasons at `:5884` and `:5887`. Executed at this head against the live block: `RESOLVED=[19.88]`. Cases `(co7)`/`(co8)`/`(co8b)`, and through the production call site by `(co12)`/`(co13)`. |
| AC-4 | satisfied | `cost_block_with_usd_key` at `:5918` pipes `$LEAN_COST_BLOCK` through awk with no write-back; `closeout_comment` pastes the raw shared block. `(co7)` asserts the shared block stays pristine; `(co10)` asserts exactly one occurrence in the comment. |
| AC-5 | satisfied | The insert lands inside the marker-to-terminator span the strip discards (`:5976-5991`). `(co9)` drives the real `closeout_patch_pr_body` twice and asserts exactly one `^cost_usd:` holding the second figure, with the marker count beside it. |
| AC-6 | satisfied | The doc is byte-identical to the round-2 reviewed head, and the recipe was extracted and run verbatim AGAIN this round on a window that has since moved: rc 0, 10 rows, every one `claude/second-shift-`, correct `cost_usd`/`legacy`/`unreported` classification, `mean: $37.1 over 5 of the last 10 merged lean PRs; 5 unpriced`. Nothing imputed, no unpriced row scored as zero. Findings 5-7 are accuracy notes on surrounding prose and formatting, not on what the AC enumerates. |
| AC-7 | satisfied | Re-verified at the merged head: `git diff --name-status origin/main...HEAD` is exactly five paths — the spec and the verdict record added, `cost-tracking-setup.md`, `lean-gate-selftest.sh` and `lean-gate.sh` modified. None of the four files the AC forbids appears; no new script; no jira-adapter code. The base merge did not widen the set. |
| AC-8 | satisfied | All nine enumerated cases present exactly once each at this head. CI at head `8a116ea6`, run `33445647231`: `lint-and-selftests` pass 4m56s and `selftests (macos, bash 3.2)` pass 7m10s — both run the repo's own sweep command, so the oracle is verified by citation rather than re-run. The AC's enumeration is met; finding 1 is a gap outside it. |
| AC-9 | satisfied | `d9ab8785` is `feat(dev-pipeline):` with a full `Changelog:` trailer, and the PR title carries the same verb, so the squash subject bumps minor. At this head `check-frozen-files.sh origin/main` prints `clean` and `check-changelog-trailer.sh origin/main` prints `OK`. Finding 10 is the hygiene nit on the whitespace commit, which harms neither check. |

**Design fidelity: not-applicable.** The spec's `## Design` reads `Design: none — this is a shell-string
change plus a documentation recipe, no web surface, and this repo configures no design.provider`.
Re-verified at this head: the branch's delta is two shell files and two markdown files with no web
surface, and `jq '.design'` on the repo config is `null`. The disarm is justified.

## Verification performed

- **The branch's contribution is provably unchanged**, by added/deleted line-set comparison, and
  independently by the merge boundary's own freshness arm printing "the verdict stands".
- **The rendering blocker was re-measured, not inherited**: real function, real block, real body,
  GitHub's own renderer, with the broken control beside the fixed case.
- **AC-6's recipe was re-run**, not cited — the merge window has moved since round 2 (#750 and
  #755 merged into it), and the recipe still classifies every row correctly on the new data.
  Worth noting for D-5's standing measurement: coverage fell from 7-of-10 priced to 5-of-10,
  because both PRs that merged since publish no cost block at all.
- `shellcheck -e SC1091,SC2015,SC2181` clean on both changed shell files at this head (local
  0.11.0; CI's pinned 0.9.0 is covered by the cited `lint-and-selftests` pass).
- `check-lockstep-pairs.sh`: 29 anchors, 0 failed.
- `mutation-sweep-pr` passed in **13s having graded nothing** — fourth consecutive round, and it
  says so itself: "PR mode graded NOTHING: all 1 in-scope guard(s) deferred to the merge-time
  sweep, 0 swept (reasons: slow suite: 1)". Its green carries zero mutation information on this
  PR. The hand probes recorded in rounds 1-2 and the 62-row catalog re-anchoring above are the
  only mutation evidence here.
- `pr-gates` fail at this head is the scorecard-schema violation quoted above and nothing else.
  No correctness lane is red.
- **Operational note for the merge, not a finding:** `origin/main` has since advanced past the
  merged base by two commits, one of which touches these same two files. The PR reports
  `MERGEABLE`, so no second base merge is needed and none should be taken — a merge that edits a
  branch line would cost another review round for no gain, while a plain base advance leaves this
  record standing.
- Panel: `review-toolkit:scope-completeness-reviewer` (independent AC re-score, 0 scope gaps, plus
  the merge-interaction audit) and `review-toolkit:unit-test-mutation-reviewer` (shell-scope
  collision audit and the carried-gap re-verification). Neither went dark. Neither modified
  anything in the reviewed checkout.
