# #672 — intake-orchestrator and intake-interviewer: a measured basis, or an explicit no-basis record

Successor to #644. Both skills left §3 of `docs/skill-ablation.md` `not adjudicated`. This slice
registers a measurement, runs it, and writes each skill's verdict — or an explicit `no basis` record
with its reason — into §3 and the §4 P6 table. It deletes nothing.

## Acceptance criteria

- **AC-1** `docs/skill-ablation-addendum-3.md` exists, extends (never amends) the pre-registration
  and addenda 1–2, pins the subjects, the substrate, the private role/gold/runner/scorer hashes, the
  construction, the invocation bar, replicates and both thresholds tables, and carries no result. It
  is committed on this branch before any file under `docs/plans/skill-ablation/c4-intake/`.
- **AC-2** The orchestrator metric is coverage-gap recall over 6 planted gaps in 3 epic roles
  (two between-children, two no-owner follow-up, two vacuous-child), each with a deterministic
  detector with zero hits on its own role body; the interviewer proxy is recall of 6 material
  ambiguities over 3 rough-request roles, registered unable to license `keep`.
- **AC-3** All registered runs are executed (3 replicates × 3 roles × 2 arms per skill), and
  `docs/plans/skill-ablation/c4-intake/` records per run: rc, capture bytes, sha256, the
  `tools/classify-capture.sh` verdict, the resolved model id, the invocation count, and per-gap
  hits — numbers and gap ids only, no role text, detector or arm output.
- **AC-4** `docs/skill-ablation.md` replaces both `not adjudicated` verdict-table rows, both §3
  `Not adjudicated` paragraphs, and both §4 P6 rows with the registered verdict or an explicit
  `no basis` record and its reason, and updates the §4 measured-lines headline ratio and the §5
  successor bullet for #672 accordingly.
- **AC-5** A non-empty cut list is filed as a successor issue and cited from §3; an empty one is
  stated as empty. No `SKILL.md` is edited.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Outcome metric for intake-orchestrator | Coverage-gap recall: each epic role carries planted cross-child defects with a gold key; an arm scores a gap when its decomposition avoids it or flags it. Gap classes are the ticket's: a follow-up deferred by every child with no owner (#465), a requirement falling between two children, a vacuous or superseded child. Child-set agreement and post-build vacuous-rate are not the metric. | user-answered |
| D-2 | Sample substrate | The lane bench's private synthetic substrate (#811), extended with epic roles for the orchestrator and blob/idea roles for the interviewer, each with a gold key. The committed record is numbers-only (the #811 summary-comment precedent); no substrate content, consumer name or org lands in this repo. | user-answered |
| D-3 | Basis for intake-interviewer | Proxy: recall of each blob role's gold material ambiguities in the arm's first-turn questions plus its declared-open items. Registered as unable to license `keep` (the pre-registration's comparison-1 consequence); reachable verdicts are `cut-to-delta` and `delete`. | user-answered |
| D-4 | Where the slice stops | Register, run, verdict. A new addendum file registered and committed before any arm runs; arms run; verdicts written into `docs/skill-ablation.md` §3/§4 (both `not adjudicated` rows replaced). No deletion in this slice; any non-empty cut is filed as a successor, as #746/#748 → #800 did. | user-answered |
| D-5 | Sample size, replicates, thresholds (orchestrator) | n=3 epic roles × 2 planted gaps = 6 gaps; 3 replicates per arm; a gap counts for an arm on majority (2 of 3). `keep`: kit catches ≥ 2 more gaps than bare. `delete`: bare catches ≥ kit AND all 6. Otherwise `cut-to-delta`, scoped to the gaps bare missed. Interviewer proxy uses the same n and replicates with the cut/delete-only table. Both arms scored against gold, so the kit arm is admissible. | user-answered |
| D-6 | Burden of proof | Unchanged from #644: burden on the skill; absence of evidence → `cut-to-delta`; "roughly equal, but more thorough" is a loss. Per the ticket body. | codebase-derived |
| D-7 | Kit-arm construction | The kit arm invokes the skill under test directly, and each run records from its stream-json events whether it was invoked. A control that invokes it in fewer than 2 of 3 runs exits `no basis — construction not delivered`. Source: `docs/skill-ablation-addendum-2.md` "Loaded is not invoked" and "The routing-prose rule". | codebase-derived |
| D-8 | Bare-arm construction | As frozen in `docs/skill-ablation-pre-registration.md` "The bare arm" (plugin-free `claude -p --setting-sources ''`, same model tier, same worktree). `CLAUDE.md`-mandated items are non-discriminating. | codebase-derived |
| D-9 | Where the new rules live | A new file `docs/skill-ablation-addendum-3.md`, committed before any run; it extends and never amends the frozen pre-registration or addenda 1–2; it holds pins and thresholds, never results. Per addendum 1's preamble ("New rules go in new files") and addendum 2's ordering check. | codebase-derived |
| D-10 | Exit when an arm cannot be delivered | Each skill exits with a measured basis or an explicit `no basis` record with its reason, in both §3 and the §4 table; never silence. Per the operator amendment of 2026-08-24 in the issue body. | codebase-derived |
| D-11 | Planted-gap content per role | Parked under OR-1. | deferred |
| D-12 | How the lane bench hosts intake arms | `tools/lane-bench.sh run` drives only full scheduler lanes and has no one-shot intake cell (read at `49147157`), so it is not the runner. The arms run as the ablation's one-shot sessions (D-7, D-8). The bench contributes its private substrate repo and its gold discipline: each planted gap or ambiguity gets a deterministic detector, a regex over the arm's output, fixed and hash-pinned in the addendum before any run. `tools/lane-bench*.sh` is not modified. Formerly OR-2, ratified 2026-09-19. | user-delegated |
| D-13 | Build model | `opus`. The builder authors a pre-registration whose thresholds decide a verdict, designs the gold keys under OR-1, and adjudicates the scoring. That is judgment-heavy, with an open region. | user-delegated |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Which concrete gaps each epic role plants, and which ambiguities each blob role carries | reversible-default-and-flag — the default was taken: two roles carry a between-children and a no-owner gap each, one carries two vacuous children; fixed and hash-pinned in addendum 3 before any run, flagged in the PR body |

## Out of scope

Edits to either `SKILL.md` (S-7); changes to `tools/lane-bench*.sh` (S-8).
