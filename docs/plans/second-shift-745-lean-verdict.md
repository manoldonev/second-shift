# lean review verdict — #745

verdict=approve
run_id: review-745-1
session_id: 3fa65cf5-b2da-46a0-8922-a0f654ed95b4
rounds: 1
pr: #758
reviewed_head: 2dcf54a614f72bae9639def268f677acd15eef76
reviewed_patch_id: bce897fb64be7b354f241d9c25b7d92e6e82b4e5
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — PR #758 (issue #745)

Reviewed head `2dcf54a614f72bae9639def268f677acd15eef76`, full branch range `8200f1c3..HEAD`
(round 1, nothing to inherit). Three files, all Markdown under `docs/`, +690/−0.

**Verdict: approve.** No blockers. Two majors and one minor, all citation-accuracy defects in
the addendum's prose; none moves a registered rule, threshold, pin, outcome or arm construction.

## What I verified rather than took on trust

This is a pre-registration whose entire value is that its pins and derivations are correct, so
they were re-derived from the repository rather than read:

| claim | result |
| --- | --- |
| pre-registration carries exactly one commit (AC-1 oracle) | ✅ `8d5d0897`, one commit; file untouched by this diff |
| `review-lean` SKILL is 127 lines @ `8d5d0897` | ✅ 127 |
| `review-lean` SKILL is 188 lines @ `8200f1c3` | ✅ 188 |
| `build-lean` SKILL is 48 lines | ✅ 48 at both commits |
| only two `##` headings at the pin (24, 98) | ✅ exactly two — the "2-run study" argument holds |
| all 17 unit line ranges @ `8d5d0897` | ✅ every boundary matches; U-P 1–23, U-1 26–28 … R-6 122–127, contiguous with headings excluded |
| C1-a base `dfd68a47…` (PR 654) | ✅ first-commit-parent and merge-base both agree |
| C1-b base `b657907f…` (PR 657) | ✅ agrees |
| `gh pr view 657 --json baseRefOid` returns `02439277` | ✅ exactly — the rejection is correct, and 654/660 agree by luck, which is why one sample would not have shown it |
| C2 heads `cfba1022…`/`f8f7c142…`/`642a6b13…` expand the frozen short SHAs | ✅ all three; each stated base is an ancestor of its head and each head is in its PR branch |
| C2-a is the sample bare missed (the 0.20) | ✅ `c2-review/scoring.tsv` scores C2-a `MISS`, 4 of 5 elsewhere |
| `cfba102:docs/plans/second-shift-636-lean.md` contains no `Design` | ✅ 0 occurrences — U-5b/R-5's `not-reached` call is verified, not assumed |
| 17 lean specs under `docs/plans/` @ `8200f1c3` | ✅ 17 |
| pre-registration cites :16, :28, :34, :44, :47, :104–109, :123–161, :132–133, :147–152 | ✅ all nine land exactly |
| `c1-build/prompt-template.txt`:2–3, `c2-review/prompt-template.txt`:7–10 | ✅ both land |
| replicate arithmetic: 3 + 3×3 + 14×1 = 26, vs 3 + 17×3 = 54 | ✅ both correct |
| 3 in-reach / 14 not-reached / 5 sample-or-harness-conditional | ✅ table and prose agree |
| R-4's quoted text matches the **pinned** revision, not today's | ✅ correct at `8d5d0897`; the current head reads differently, and the addendum quotes the pin |

CI at this exact head (`2dcf54a6`, run 33446948625): `lint-and-selftests` **pass**,
`selftests (macos, bash 3.2)` **pass**, `mutation-sweep-pr` **pass**. Cited, not re-run.
`pr-gates` is red on the single line `no committed verdict record` — the expected pre-approve
state this round exists to clear, not a finding. `check-frozen-files.sh` clean;
`check-changelog-trailer.sh` reports no `plugins/**` change, so no trailer is required (both
commits carry `Changelog: none` anyway).

## Findings

### Major — the addendum's two stale line citations into the very file this commit shifts

`docs/skill-ablation-addendum.md`:409 states `docs/skill-ablation.md` repeats "127" at
**:31, :188, :192, :275, :299**. Those are the line numbers *before* this commit's own 9-line
insert into that same file. At the head being merged they are **:31, :188, :192, :284, :308** —
the first three still land, and the last two do not: `:275` now points at a sentence from this
PR's own inserted paragraph, and `:299` at a blank line.

The mechanism is worth naming because no single review dimension owns it: the commit edits file
X and, in file Y of the same commit, cites file X by line number. The figures were correct when
derived at intake (the issue body carries the same five) and this PR invalidated two of them.

The substantive claim — the doc repeats 127 in five places, which is *why* the subject is pinned
by commit rather than by line count — is true and unaffected. Remedy is two digits, or drop the
line numbers and cite the five sites by section.

### Major — the addendum contradicts the passage it cites, two sentences later, on the pre-registration's commit SHA

`docs/skill-ablation-addendum.md`:9-11 cites `docs/skill-ablation.md`:6-11 and states the
pre-registration "carries exactly one commit, **`8d5d0897`**". The cited passage
(`docs/skill-ablation.md`:10) says of the same file: "It has exactly one commit, **`f174f1f`**".

Both resolve. `f174f1f` is the pre-squash branch commit; `8d5d0897` is the squash-merge on main
(PR #673). **The addendum is the accurate one** — `8d5d0897` is what AC-1's own oracle
(`git log --oneline -- docs/skill-ablation-pre-registration.md`) returns, is reachable on main,
and is the commit the 127-line subject pin resolves against, all verified above. The defect is
that a reader who follows the citation lands on a different SHA for the same fact with no
reconciliation, in a document whose whole discipline is citation accuracy. One clause fixes it
("the squash-merge of the branch commit `f174f1f` that `docs/skill-ablation.md`:10 names").

### Minor — "quoted from the frozen sample" is a paraphrase

`docs/skill-ablation-addendum.md`:429 introduces the C2-a ground-truth blocker as *quoted* "so
the hit rule has a fixed subject". It is not verbatim: the frozen oracle reads "…omits
keyword-preceded calls (`lean-gate.sh:420` `else envfail`)", and the addendum generalizes the
specific site to "a live refusal site" and adds "the denominator the guard claims is its output".
Same mechanism and same consequence, so the frozen hit rule is unaffected and the oracle file is
cited alongside — but dropping the site makes the stated subject looser than the frozen one, and
"quoted" overstates it. Either quote it or call it a restatement.

### Registered-but-unpinned input — worth settling before #746 runs, not before this merges

The "deliberately KEPT" table registers `.claude/second-shift.config.json` as **copied in from
the operator's checkout**, because it is gitignored. That file is machine-local and moves over
time, so it is the one substrate input two implementers cannot reproduce byte-for-byte — and
A1-min deliberately keeps it too, so neither arm pins it.

I score AC-2 **satisfied** rather than blocking on this: every one of AC-2's six enumerated
obligations is met, the item *is* registered with its bias direction rather than omitted, and
there is a real argument the other way — pinning a consumer-simulation config makes the substrate
less faithful to "what a real downstream machine looks like", which is the substrate's stated
rationale. But the addendum rejects `baseRefOid` on precisely the test this row does not meet
("two implementers using it build different checkouts, which defeats the ticket's own
reproducibility bar"), so the standard is the document's own. Settle it in #746 — pin the
fields that matter, commit a redacted copy into the study's evidence tree, or register the
omission — rather than after a result makes the answer interesting.

## Strengths

- **The pins are derived, not asserted, and they survive independent re-derivation.** Every SHA,
  line range and count above was re-computed from the repository and matched. The `baseRefOid`
  rejection is the sharpest example: it is correct for PR 657 and *coincidentally agrees* on 654
  and 660, so a one-sample check would have concluded the opposite.
- **The `not-reached` classification is registered as a falsifiable prediction rather than an
  exemption.** All 17 units are ablated, not just the 3 in-reach ones, and a `not-reached` unit
  that moves the outcome is promoted and reported as a surprise. That is the difference between
  a rubric and a way of not measuring 14 units.
- **The conflict between the two parent tickets is broken before any result, on the one rule
  neither may amend.** #671 and #745's AC-2 point in opposite directions on M1–M3; the addendum
  names the conflict, resolves it on `docs/skill-ablation-pre-registration.md`:44's definition of
  `cut-to-delta` (which I verified reads as claimed), and demotes AC-2's clause to the bias
  argument its sentence actually makes. Choosing after seeing a result is the exact failure this
  file exists to prevent.
- **Two confounds are disclosed rather than discovered later** — that `review-lead` is absent
  from every arm including the control, and that the built-in's base resolution falls back
  silently (measured: it reviewed `HEAD~1` and returned a plausible report). §1 had to disclose
  its sensitivity run as post-hoc; A1-min is registered before its trigger can be observed.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `docs/skill-ablation-addendum.md` exists; `git log --oneline -- docs/skill-ablation-pre-registration.md` returns exactly one commit (`8d5d0897`), and the diff does not touch that file; the addendum's line 3 opens "This file EXTENDS the frozen protocol; it does not amend it." |
| AC-2 | satisfied | All six enumerated obligations settled: substrate + rationale (§A); paths absent (`plugins/`, `.claude-plugin/`) by throwaway clone with both named alternatives rejected; cache path resolved via `claude plugin list --json` rather than guessed; both C1 base commits pinned with the first-commit-parent derivation and the `baseRefOid` rejection — all re-derived and matching; and the discovery question settled by measurement (`SECONDSHIFT:no` with `plugins/` fully intact). The copied-in gitignored config is registered with its bias but not pinned — raised as a finding, routed to #746, does not leave an enumerated obligation unmet. |
| AC-3 | satisfied | §B registers the exact invocation — the frozen `env -u …` recipe with `claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob,Bash"`, prompt on stdin; `--model opus` with its false-`keep` reason; effort `max` with the reason `ultra` is unavailable (cloud, user-triggered, separately billed, PR-targeted). The measured `AVAILABLE:yes` / `SECONDSHIFT:no` is recorded in §A with its command and cross-referenced from §B. |
| AC-4 | satisfied | Leave-one-out over `review-lean`, C2-a (#654 @ `cfba102` — SHA expansion verified against the frozen oracle), scoring whether the ground-truth blocker disappears. All 17 units enumerated with line ranges that match the pinned file boundary-for-boundary; the two-`##`-headings argument verified (exactly two, at 24 and 98). Fixes `carrier` (§C), the `no-effect` set-comparison threshold, `indeterminate` handling with the "fewer than 2 valid runs is `undetermined`, never `no-effect`" rule, and the 127-line pin at `8d5d0897` — 127 verified there, 188 at the branch base. |
| AC-5 | satisfied | Eyeballed all 588 lines, deliberately, as the AC directs — there is no mechanical oracle and the addendum says so in its own text. No outcome from #746/#747/#748 appears. Every measured fact is apparatus (harness availability, the built-in's silent `HEAD~1` fallback, its ranked-list output shape, `baseRefOid`'s value), was taken before any arm ran, and prints its command. The only outcome-shaped figures (4/5, 0.20) restate the already-committed §2 result and are attributed to it. |
| AC-6 | satisfied | `docs/skill-ablation.md` §4 spans lines 266–299; the pointer lands at 272–280, above the P6 bases table, so a reader arriving at the table meets it first. |

## Design fidelity

`not-applicable`. The spec's `## Design` section reads `Design: none — a documentation-only
registration with no web surface, and this repo configures no design.provider`. The disarm is
justified rather than taken on trust: the repo's config carries no `design` key, and the diff is
three Markdown documents with zero web-component surface.

## Panel

`review-toolkit:scope-completeness-reviewer` — returned `approve`, no findings, one suppressed
note at confidence 70 (the 188-vs-176 line figure, where it independently measured 188 at
`8200f1c3` and confirmed the addendum is the accurate one).

Routing selected exactly one subagent: the diff is trivial-inert (three Markdown files, all under
`docs/`, none under `.claude/`), so no db, pipeline, mutation, a11y or design-fidelity trigger
fired. `security-reviewer` was not selected — no auth/tenancy/session/upload/query surface in a
prose diff and no `review-context/security-reviewer.md` in the repo — so the lead pass owned the
security dimension (nothing to flag: no secrets, no credentials, the sample cache path is
anonymized as `/Users/<user>/`). Performance, complexity, maintainability and test-coverage were
the lead pass's by design; the three findings above are its maintainability output. Test coverage:
no executable surface is added, and AC-5 registers that no mechanical oracle is built, with its
reason.
