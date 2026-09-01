# 746 — `build-lean`'s M1–M3 coverage, re-measured where the gate is not tree source

Issue: https://github.com/manoldonev/second-shift/issues/746 — part of #671, arm 1.
Predecessor: #745 (the addendum). Successor: #747.

## What this is

§1 of [`docs/skill-ablation.md`](../skill-ablation.md) scored a bare session as covering M1, M2 and
M3 — and recorded that it covered them *by reading `lean-gate.sh` out of the working tree*, which is
true only in this repository. This slice re-runs the same two samples on the substrate
[`docs/skill-ablation-addendum.md`](../skill-ablation-addendum.md) §A registers — gate and skills
absent from the tree, the installed plugin cache present and readable — and reports which M-items
survive a consumer-shaped checkout.

**This slice localises a cut. It executes none** (parent guardrail; `docs/skill-ablation.md` §5
precedent). No shipped SKILL prose is edited.

## Acceptance criteria

Carried verbatim from the issue body, which is the authority surface (#671 carries no numbered
criteria of its own; these were derived at intake). The issue declares them as `**AC-n** —` bold
paragraphs; they are re-declared here as bullets because that is the form the verdict record's
reader treats as a declaration rather than a citation. Wording is unchanged.

- AC-1: Both registered C1 samples re-run: #636 and #647, each given
  `docs/plans/skill-ablation/c1-build/prompt-template.txt` with its ticket appended, unchanged from
  the registered run.
- AC-2: Each session runs on the substrate registered in `docs/skill-ablation-addendum.md`: gate
  and skills absent from the working tree, installed plugin cache present on disk and readable. The
  realised substrate is verified and recorded per run — which paths were absent, and that the cache
  was reachable — so a reader can tell the arm measured what it claims.
- AC-3: Scored by the frozen C1 rule at `docs/skill-ablation-pre-registration.md`:104-121,
  unchanged: each of M1–M10 `covered` or `absent`, no partial credit, M5 reported but excluded as
  non-discriminating. A plan naming "a PR" without `ready`/`Closes` scores M6 `absent` and the wording
  is quoted.
- AC-4: Both transcripts committed verbatim under `docs/plans/skill-ablation/c1-build/`, one file
  per session, under a name distinct from the existing `bare-<n>-plan.md` and
  `bare-ablated-<n>-plan.md` families. `docs/plans/skill-ablation/c1-build/README.md` gains a line
  describing the new family, matching how it already describes the other two.
- AC-5: `docs/plans/skill-ablation/c1-build/scoring.tsv` carries the new arm's per-item results
  alongside the existing columns, and `docs/skill-ablation.md` is updated in three places: §1, the top
  Verdicts table row 1, and §4's `dev-pipeline/build-lean` row.
- AC-6: The result is stated as an explicit cut list: which M-items fall inside `build-lean`'s
  delta and which do not. If the bare arm misses M1–M3 on this substrate, those items are inside the
  delta and their prose is retained — that is a narrower `cut-to-delta`, not a `keep`, which the frozen
  threshold table makes unavailable for C1 (`docs/skill-ablation-pre-registration.md`:119).
- AC-7: `plugins/dev-pipeline/skills/build-lean/SKILL.md` is not edited. Its line count is
  unchanged at 48.

## Out of scope

- Executing the cut — a named successor of #671.
- The `review-lean` arms (#747, #748).
- P10 independence — a lane property, not prose.
- Editing `docs/skill-ablation-pre-registration.md` — frozen.

## Decision Ledger

No pre-flight `746-ledger.md` exists. The parent's intake receipt (`671-ledger.md`) is machine-local
and gitignored; its operator-answered rows that bind this slice are restated in the issue body's
"Settled at intake" block and are carried below under their **original parent ids** (`D-1`, `D-2`,
`D-18`) so the two ledgers stay diffable. Slice-local decisions start at `D-24`, above the parent's
highest id, so no id means two things.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does this arm execute the cut, or only localise it | Localise only. The arm ends at an explicit cut *list*; the deletion is a named successor of #671. No shipped SKILL prose is edited (AC-7). | user-answered |
| D-2 | What arm 1's consumer-shaped checkout lets the bare session reach | Gate and skills absent from the working tree; the installed plugin cache present on disk and readable by `Read`/`Grep`. The faithful consumer simulation and the strongest honest version of the bare arm. | user-answered |
| D-18 | Build sizing | `opus`. The scoring judgment is the deliverable. | user-delegated |
| D-24 | Which invocation the arm uses | The frozen bare-arm recipe verbatim (`docs/skill-ablation-pre-registration.md`:22-27), `--model opus`, with the bracketed `--allowedTools "Read,Grep,Glob"` **taken**, not omitted. D-2 registers the cache as readable *by the session's tool allowlist*; omitting the flag would starve the arm of the one affordance the substrate exists to grant. | codebase-derived |
| D-25 | How the substrate is realised | Throwaway `git clone` of this repository per sample, detached at the addendum's pinned base commit, with `plugins/` and `.claude-plugin/` deleted from the working tree and left as unstaged deletions, and `.claude/second-shift.config.json` copied in (it is gitignored here, but an onboarded consumer commits one). Registered at `docs/skill-ablation-addendum.md`:74-94 and :141-152; the two alternatives it rejects are not re-proposed. | codebase-derived |
| D-26 | The pinned checkouts | C1-a #636 → `dfd68a47402acb9f77530e3e086dd42760749709`; C1-b #647 → `b657907f52011c06afad34fc026fbbaeca8ae88a` (`docs/skill-ablation-addendum.md`:161-165). `gh pr view --json baseRefOid` is registered as NOT the answer and is not used. | codebase-derived |
| D-27 | Provenance is recorded for every `covered` item | `cache` \| `tree` \| `unaided`, per `docs/skill-ablation-addendum.md`:183-199. This is what makes the arm readable: without it, "bare covered M1" and "bare read the SKILL out of the cache" are the same row. Scored per sample, not per arm. | codebase-derived |
| D-28 | Whether A1-min runs | Conditional and pre-registered (`docs/skill-ablation-addendum.md`:224-247): it runs iff any of M1–M3 scores `covered` with provenance `cache` or `tree` in A1-max. The trigger is evaluated after A1-max is scored and the evaluation is recorded either way, so a reader can see the branch was taken deliberately rather than skipped. | codebase-derived |
| D-29 | The outcome reading | Fixed before any result by `docs/skill-ablation-addendum.md`:201-222, which also breaks the #671-vs-#745 tie in favor of the frozen rule: an item bare **covers** is cut-eligible; an item bare **misses** is **kept**. AC-6's conditional clause is consistent with that and is not re-read. | codebase-derived |
| D-30 | New transcript family name | `consumer-<arm>-<n>-plan.md`, `<arm>` ∈ `max \| min \| sealed \| sealed-min` — distinct from both `bare-<n>-plan.md` and `bare-ablated-<n>-plan.md` (AC-4), and it names the substrate rather than a run ordinal, so a further arm does not have to renumber. The superseded first pass keeps its own name, `consumer-max-confined-<n>-plan.md` (D-33). | codebase-derived |
| D-31 | `scoring.tsv` gains columns, it does not gain rows | The new arms are per-item columns (`consumer_<arm>_<sample>`) plus a `consumer_verdict`, alongside the existing columns rather than replacing them (AC-5). The registered and ablated columns are the record §1 is scored on and stay readable. Each cell carries the provenance too (`covered:tree`, `covered:cache`, `covered:unaided`, `absent`), because D-27 makes provenance part of the score rather than a footnote. | codebase-derived |
| D-32 | The apparatus command in the addendum has a stale jq field | `docs/skill-ablation-addendum.md`:65-67 prints `claude plugin list --json \| jq -r '.[].path'`; the field is `installPath` and `.path` yields `null`. The addendum is a registration and this slice does not edit it — the working form is recorded in the arm's own report next to the resolved path, and the discrepancy is stated rather than silently corrected. | codebase-derived |
| D-33 | **Measured: under the frozen recipe the plugin cache is NOT reachable**, so the first pass did not realise the registered substrate | A session started by `claude -p` is confined to its working directory; `ls ~/.claude/plugins/cache/second-shift` returns *"blocked … may only list files in the allowed working directories for this session"*. AC-2 requires the cache be readable, and `docs/skill-ablation-addendum.md`:51-53 registers it as *inside the session's tool allowlist* — so a confined run fails the acceptance criterion. Resolved by adding `--add-dir /Users/mdonev/.claude/plugins/cache` to the invocation, verified by probe. This is not a departure from the frozen recipe's *substance*: it changes no model, prompt or settings source, and it is the minimum that makes the registered property true. The confined pass is reported as the finding that produced it and is not scored. | codebase-derived |
| D-34 | **Measured: the registered construction does not realise the registered substrate**, because deleting the kit from the working tree leaves it readable from the clone's object store | `git show HEAD:plugins/dev-pipeline/skills/build-lean/SKILL.md` prints the 48-line file in every A1-max and A1-min checkout, and every one of those four sessions used it. Under `docs/skill-ablation-addendum.md`:201-222 that scores their coverage provenance `tree`, which the registered reading already calls **inconclusive**. A1-min is registered as the remedy for `tree` provenance and inherits the same hole, so it cannot lift it either. Both registered arms are run and reported in full; a **disclosed post-hoc** arm, A1-sealed, is added to answer the question they cannot, labelled the way `docs/skill-ablation.md`:56-58 labels §1's own sensitivity run. | codebase-derived |
| D-35 | A1-sealed needs its own minimal twin | A1-sealed keeps `docs/plans/` and the onboarding files, so a `covered` there is open to exactly the objection A1-min exists to close — the repository's own committed lean artifacts. A1-sealed-min applies A1-min's registered removal list to the sealed tree, and the registered A1-min reading is applied to the pair: an item is cut-eligible only if `covered` in **both**. Post-hoc and labelled, for the same reason A1-sealed is. | codebase-derived |
| D-36 | The leak reaches §1's already-scored evidence | The disclosed ablated run for #647 in `docs/skill-ablation.md` §1 recovered `build-lean/SKILL.md` with `git show HEAD:` — the same hole, in the arm §1 added to remove that confound. Reported in §1 with the command that shows it, and **not acted on**: re-scoring §1 is not this ticket's scope, and silently correcting a committed result would be worse than naming it. | codebase-derived |

## Open Regions

None. Every input this arm consumes was fixed by #745 before it ran.
