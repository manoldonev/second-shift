# #745 — the three ablation arms get their substrate, challenger and attribution rubric fixed before any of them runs

`docs/skill-ablation-pre-registration.md` fixed a metric, sample, scoring rule and threshold table
for three comparisons before any result existed. Each of #671's three arms changes an input to one
of those comparisons — #746 changes C1's **substrate**, #747 changes C2's **challenger**, and #748
needs an **attribution method the frozen protocol does not contain at all** — and none of those
changes is registered anywhere. A substrate, challenger or rubric fixed after results exist is a
post-hoc rubric, which is the failure mode `docs/skill-ablation-pre-registration.md`:16 names as the
reason a pre-registration exists.

So the registration lands first, in its own ticket, as a new file: `docs/skill-ablation-addendum.md`.
The frozen pre-registration is **not edited** — it carries one commit and `docs/skill-ablation.md`:6-11
makes that unedited history the thing #644's AC-1 was scored on. Nothing enforces that mechanically;
it is honored by placement. Registration only — no arm runs here, and no cut is executed. Part of #671.

## Decision Ledger

No pre-flight `.claude/pipeline-state/745-ledger.md` exists, so nothing is carried forward. The
`ticket-sourced` rows below cite the **body** of https://github.com/manoldonev/second-shift/issues/745
— specifically its "Settled at intake — do not re-litigate" block, which restates #671's
operator-answered guardrails because that parent receipt is gitignored and machine-local. They are
not comments; the label is used because the citation is independently verifiable without a local
pre-flight artifact, which is the property the enum's `ticket-sourced` entry exists for, and this
row says so plainly so a reviewer can repudiate the label rather than take it on trust.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Whether this ticket runs any arm | No. Registration only. The three successors (#746, #747, #748) measure; every deletion is a further successor of #671, per the `docs/skill-ablation.md` §5 precedent separating a verdict from its execution. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |
| D-2 | Where the new rules live | A new file, `docs/skill-ablation-addendum.md`. The frozen pre-registration is never edited; its single-commit history is what #644's AC-1 was scored on (`docs/skill-ablation.md`:6-11). No script enforces this — honored by placement. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |
| D-3 | Arm-1 substrate | Gate and skills absent from the working tree; the installed plugin cache present on disk and readable. The faithful consumer simulation, and the strongest honest version of the bare arm. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |
| D-4 | Attribution unit | The finest: the 10 numbered checklist steps, the 6 non-negotiable rule bullets and the preamble. Explicitly not the two `##` headings, which localise no finer than a 73-line block. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |
| D-5 | Attribution subject | The 127-line `review-lean` at `8d5d0897`. Lines added since are recorded unmeasured, never silently cut or kept. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |
| D-6 | How the arm-1 checkout is constructed | A throwaway `git clone` at the pinned base with `plugins/` and `.claude-plugin/` removed as unstaged deletions. Deleting in a live checkout was rejected as destructive and as visible to `git status` in a tree the lane may be using; a synthetic layout omitting `plugins/` was rejected because #636 and #647 are second-shift tickets and need the repository's own code to be implementable at all. | codebase-derived |
| D-7 | Whether an intact `plugins/` tree or a `.claude-plugin` manifest leaks skill DISCOVERY | No. Measured 2026-09-01: the frozen bare-arm recipe, run in this repository with every `SKILL.md` and agent contract present and `.claude-plugin/marketplace.json` present, answered `SECONDSHIFT:no`. `--setting-sources ''` suppresses plugin enablement. So §1's leak was a file-READING leak: removing the files is required, and sufficient — no extra disarming step is registered. | codebase-derived |
| D-8 | Which arm-1 base commits are pinned, and how they are derived | `dfd68a47…` (#636/PR 654) and `b657907f…` (#647/PR 657), derived as the parent of each branch's first commit. `gh pr view --json baseRefOid` is rejected: for PR 657 it returns `02439277`, the base ref's tip at merge time, so two implementers using it build different checkouts — which defeats the ticket's own reproducibility bar. | codebase-derived |
| D-9 | How arm 1's outcome is read, given that #671 and #745 word it in opposite directions | The frozen rule breaks the tie, because it is the one neither ticket may amend: `docs/skill-ablation-pre-registration.md`:44 defines `cut-to-delta` as cutting to the part that differs from bare, so an item bare COVERS is cut-eligible and one it MISSES is kept — #671's phrasing. #745's AC-2 clause is recorded as the substrate's bias argument (a maximal substrate makes a miss conclusive), not as an outcome rule. Fixed before any result, since choosing after would be the post-hoc rubric this ticket exists to prevent. | codebase-derived |
| D-10 | Whether every covered arm-1 item records where the coverage came from | Yes — a new per-item `cache` / `tree` / `unaided` provenance field. The substrate deliberately leaves the cache reachable, so without it "bare covered M1" and "bare read the SKILL out of the cache" are the same row, and telling those apart is the entire question arm 1 was filed to answer. | codebase-derived |
| D-11 | Whether arm 1 gets a sensitivity arm, and when it is registered | Yes, and NOW — A1-min, triggered when any of M1–M3 is covered with `cache` or `tree` provenance. §1's sensitivity run had to be disclosed as post-hoc (`docs/skill-ablation.md`:56-58); registering the trigger before it can be observed is what stops that recurring. | codebase-derived |
| D-12 | `/code-review` effort level | `max`. `ultra` is nominally stronger but unavailable to this arm: it is a cloud, user-triggered, separately billed multi-agent review that a session cannot launch and that takes a GitHub PR target rather than a pinned local range. Registering it would register a recipe that cannot be run. | codebase-derived |
| D-13 | `/code-review` tool allowlist | `Read,Grep,Glob,Bash`, wider than the frozen bare arm's optional `Read,Grep,Glob`, because the built-in resolves its own range and needs `git`. Bias recorded: a wider allowlist can only help the challenger, whose failure mode is a false `keep`. | codebase-derived |
| D-14 | How the `/code-review` arm is pinned to the reviewed head | A throwaway clone with the default branch hard-reset to the pinned base and the branch created at the pinned head, plus a pre-run assertion on both. Measured 2026-09-01: with no `main` present the built-in silently reviewed `HEAD~1` and reported a plausible result, so an unpinned base yields a silently wrong range. A post-run assertion on the range the report names is registered alongside. | codebase-derived |
| D-15 | How `/code-review` output maps onto the frozen blocker metric | Every finding it reports is in the challenger's finding set — no severity filter, no scorer judgment. Measured 2026-09-01: it emits a ranked findings list with no blocker/non-blocker split, so the frozen `BLOCKERS` section does not exist to read. Both effects registered: it maximizes recall (safe direction) and maximizes false blockers (which the frozen table consults at 5/5). Fixing it now stops a severity filter being chosen after the fact. | codebase-derived |
| D-16 | Whether the 17 units are asserted or derived | Derived, with line ranges at the pinned commit: 10 checklist steps (`5b.`/`5c.` do not match a naive `^[0-9]\+\.` grep, which is why a raw grep finds 8), 6 rule bullets, 1 preamble. The ticket's "roughly 17" is exactly 17. Ablating U-P retains the YAML frontmatter, which is the file's identity rather than instruction prose. | codebase-derived |
| D-17 | Whether units the metric cannot reach may be cut | Never. Most of `review-lean`'s units claim lane artifacts, not findings; a naive reading would ablate them cleanly, score them inert, and license cutting the skill's whole mechanical half. They are recorded `not-reached — no basis`, the way §4 records an unmeasured skill, and routed to a successor owed a different metric. | codebase-derived |
| D-18 | Whether the reach classification is tested or merely asserted | Tested. All 17 units are ablated, not just the 3 in-reach ones, so the classification is a falsifiable prediction; a `not-reached` unit that does change the outcome is recorded as a surprise and promoted. Replicates are asymmetric — n=3 for the control and in-reach units, n=1 as a falsification probe for the rest, escalating on a loss. | codebase-derived |
| D-19 | What happens if the attribution control cannot reproduce the finding | The study is void for the construction, and #748 does not proceed to the ablations. A two-step fallback is fixed now: re-run the control with `review-lead` available, adding it as a coarse 18th unit if that reproduces the finding; otherwise exit `no basis`, which is a real result and is reported rather than retried until it passes. | codebase-derived |
| D-20 | Whether the frozen "absence of evidence yields `cut-to-delta`" rule descends to units | No. It governs a comparison's verdict, and C2 already reached its verdict under it. Reading it at unit level would cut 14 of 17 units on nothing — the guessing this arm exists to replace. | codebase-derived |
| D-21 | How AC-5's "no results" squares with AC-2 and AC-3 mandating measured facts | The distinction registered in the file's own text: an **apparatus** fact (what the harness does) is not an **arm outcome** (what an arm found). AC-3 explicitly requires recording a measured availability fact, so a blanket no-measurement reading of AC-5 would make the two unsatisfiable together. Every measurement in the addendum is apparatus, was taken before any arm ran, and prints its command. | codebase-derived |
| D-22 | Whether a mechanical oracle is built for AC-5 | No. The ticket states there is none and that none is built here: a report about machinery growth should not grow machinery to land. The addendum says so in its own text so a reviewer eyeballs deliberately rather than assuming a gate did it. https://github.com/manoldonev/second-shift/issues/745 | ticket-sourced |

## Design

Design: none — a documentation-only registration with no web surface, and this repo configures no
`design.provider`.

## Acceptance criteria

- AC-1: `docs/skill-ablation-addendum.md` exists, and `git log --oneline --
  docs/skill-ablation-pre-registration.md` still returns exactly one commit. The addendum's own
  opening states that it extends, and does not amend, the frozen protocol.
- AC-2: The addendum registers arm 1's substrate concretely enough that two implementers build the
  identical checkout — the registered substrate (gate and skills absent from the working tree,
  installed plugin cache present and readable) with its recorded rationale; exactly which paths are
  absent and by what means, with the rejected alternatives named; the concrete cache path; the
  pinned base commit of each C1 sample with its derivation and the reason `baseRefOid` is not it;
  and a settled answer to whether a stray `.claude-plugin` manifest or an otherwise-intact
  `plugins/` tree still lets a session discover local skill definitions.
- AC-3: The addendum registers the `/code-review` arm's challenger invocation — the exact command,
  the model tier (`--model opus`), and the effort level — each with its reason, including why the
  nominally-stronger `ultra` is not it. It records the measured fact that the built-in survives the
  frozen bare-arm recipe (`AVAILABLE:yes` / `SECONDSHIFT:no`), so the arm needs no new harness and
  loads no second-shift plugin.
- AC-4: The addendum registers the attribution rubric: leave-one-out ablation over `review-lean`'s
  SKILL, re-run against the C2-a sample (#654 @ `cfba102`), scoring whether the missed ground-truth
  blocker disappears. The unit is the finest — the 10 numbered checklist steps, the 6 non-negotiable
  rule bullets and the preamble, enumerated with line ranges at the pinned commit, not the two `##`
  headings. It fixes, before any run: what counts as "this unit produced the finding", the exit
  threshold for "produced nothing either arm did differently", how an indeterminate run is recorded,
  and the subject pin (the 127-line file at `8d5d0897`, not the current head).
- AC-5: The addendum contains no results and this PR contains no arm output. There is no mechanical
  oracle and none is built; the addendum states this in its own text so a reviewer eyeballs for
  stray figures and verdicts deliberately. Measured **apparatus** facts — what the harness does,
  taken before any arm ran, each printing its command — are not arm output, and AC-3 mandates one of
  them.
- AC-6: `docs/skill-ablation.md` §4 gains a pointer to the addendum, so a reader arriving at the P6
  bases table finds the extended protocol.

## Out of scope

- **Running any arm.** This ticket registers; #746, #747 and #748 measure.
- **Executing any cut.** Every deletion is a further successor of #671.
- **P10 independence** — a lane property, not prose.
- **Editing `docs/skill-ablation-pre-registration.md`** — frozen, per AC-1.
