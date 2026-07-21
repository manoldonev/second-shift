# #160 scoping — L2 instruction-prose debloat

Scoping pass only: classification, targets, and ranked candidates with evidence. No prose is
cut by this document. Word counts are measured (baseline TSV / `wc -w`); classifications and
per-candidate savings are analyst judgment over full-file reads (±15%), labeled as such.

## Verdict up front

1. **The 158k-token headline is the wrong optimization target.** Those tokens are never
   co-resident. The binding constraint is the **run-session surface**: ~44.3k words
   (~59k tokens) that accumulate in one autonomous `/dev-pipeline:run` context
   (SKILL.md + the 10 stage files + doc-update.md + eval-criteria.md + the two mandated
   Skill loads: intake-orchestrator and review-lead). Reviewer subagents each load only
   baseline + their own file (~5–7k tokens). Budgets are set per surface below.
2. **The bloat hypothesis is mostly false for the hot path.** Measured classification of
   ~91k words (37 files, 77% of the layer): **~79% contract, ~9% redundancy, ~12%
   ceremony**. The instruction layer is contract-dense; the realistic safe reduction is
   **~8.2k words cut or deduped in-context plus ~1.0k words of inline bash extracted into
   selftested scripts — ≈9.2k words (~12k tokens, ~8%) off the layer** — plus ~3k words
   removed from the run surface without deleting anything (operator docs that never
   belonged on it; the text survives as linked reference, so it does not reduce the layer
   total). A 30%-style target would force cutting contract and is explicitly not proposed.
3. **The retro record is unambiguous about what to cut first.** Across all 23 retros, no
   deviation class ever stopped recurring after a prose strengthening; every class that
   stopped, stopped after a statectl/helper gate landed (#144, #153, #158). The
   highest-value cuts are the emphasis-essays around rules that are already mechanically
   enforced — the prose is narrating a gate that exists.

## Method / Decision Ledger

Interactive DE pass per the pre-flight ledger (`.claude/pipeline-state/160-ledger.md`),
reproduced:

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Execution vehicle | Interactive DE session, not an autonomous run | user-answered |
| D-2 | Reduction-target unit | Per-load-surface budgets; repo total is a secondary metric | user-answered |
| D-3 | Classification scope | Run surface in full + every file ≥1500 words (37 files, ~77% of layer weight); tail bulk-passed | user-answered |
| D-4 | Evidence standard | 3-tier (retro-deviation cross-ref / mechanical near-dup scan / labeled analyst judgment); disposition per candidate: cut / relocate / mechanize | user-answered |
| D-5 | Deliverable | This report in docs/plans/; follow-on issues drafted here, filed only after approval | user-answered |
| D-6 | Gate posture | prose-budget.sh stays a flat growth-guard; reductions re-snapshot the baseline | codebase-derived |

Evidence inputs: all 23 `.claude/pipeline-state/*-retro.md` (tier a); an 8-word-shingle
cross-file similarity scan over all 71 baseline files (tier b); full-file section-level
classification of the 37 in-scope files by parallel analysts with a shared rubric,
adjudicated here (tier c). "Relocate (lazy)" below means: move off a load surface without
deleting text.

## Load-surface model

| Surface | What co-resides | Words | ~Tokens |
| --- | --- | --- | --- |
| **Run session** (accumulates over one autonomous run) | run/SKILL.md 7.8k + stages 1–10 23.9k + doc-update.md 2.3k + eval-criteria.md 0.9k + intake-orchestrator 4.7k (S1 Skill load) + review-lead 4.8k (S8 Skill load) | **44.3k** | **~59k** |
| — plus avoidable reads | state-schema.md is reference (per-section reads are correct); cost-tracking-setup.md + 3 tracker READMEs (~3.0k words) are linked operator docs, **not** step-time instruction | +0–3k | |
| **Reviewer dispatch** (per subagent) | reviewer-baseline 2.2k + one agent file 1.5–3.3k + extension file | 3.7–5.5k | 5–7.3k |
| **Interactive intake** | intake router + interviewing-baseline + one routed skill | ≤6.3k | ≤8.4k |
| **Design skills/agents** | each loads standalone (figma-faithful 3.1k the largest) | ≤3.1k | ≤4.2k |
| Whole layer (secondary metric) | 71 files | 118.4k | ~158k |

A one-run context pressure datapoint: mandated Skill loads were silently skipped in 3 runs
(retro-130 lineage) — the run surface is heavy enough that executors under pressure shed
mandated loads. Shrinking this surface is not cosmetic.

## Evidence

### Tier a — prose that failed to enforce (retro-deviation map)

Condensed from the full extraction (12 deviation classes across 23 retros):

| Deviation class | Runs | Prose that failed | Ended by |
| --- | --- | --- | --- |
| Self-eval substitution / generous scoring | 10 | eval-criteria.md (LOCKED label); SKILL.md Post-Run Eval | `mark-completed` key/value gate (#153) — judgment half still open |
| Out-of-plan files committed | 9 | eval-criteria criterion 4; stages/7 | still recurring; #109/#159 gates in flight |
| Operator-identity commits | 7 | SKILL.md bot contract + helper header | config-resolution fix (#144) |
| Late `started` writes / collapsed stage windows | 5 | stages/1-intake.md:93 (maximally emphatic), stages/7:13 | **nothing — the canonical prose-ceiling case**; hard gate rejected (#147) as false-tripping |
| Mandated comments dropped | 4 | stages/3:84, 7:90, 8:186, SKILL.md | comment-receipt gate (#140 lineage) |
| Enum/provenance drift incl. fabrication | 4 | state-schema enum; 3-write-plan item 8 | drift only where validation was absent |
| Mandated skill loads skipped | 3 | stages/1 1.B, stages/8 | `skillsLoaded[]` completion evidence (#158) |

Four retros explicitly declare prose exhausted (#68, #99, #110, #145). Implication for
scoping: **emphasis-inflation around already-mechanized rules is the safest cut class**
(the gate, not the essay, is what enforces), and the one repeatedly-bent rule with *no*
gate (stage-entry write ordering) should be cut **only paired with** a retro-side
mechanical check, not cut bare.

### Tier b — mechanical near-dup scan

Top cross-file duplication clusters (8-word shingles, all 71 files):

| Cluster | Signal | Canonical-home call |
| --- | --- | --- |
| `run/doc-update.md` ↔ `review-toolkit/agents/doc-updater.md` | 385 shared shingles — near-clone pair (~20% of each file) | Deliberate fork (pipeline stage vs manual agent) but unmarked; needs a declared-divergence note or shared core |
| review-toolkit agent mesh (10 agents pairwise 76–172) | ~650w cross-agent boilerplate | reviewer-baseline (already auto-loaded via `skills:`) |
| design-faithful + figma-* family (100–176 per pair) | ~2.4k words family-duplicated | split: skills point at figma-faithful; enforcement text canonical in figma-faithful-reviewer |
| state-schema.md ↔ scope-completeness-reviewer (116) | AC-ID fallback block | **intentional byte-for-byte mirror — protect with a copies-match lint, do NOT dedup** |
| stage-file cross-shares (1↔2, 3↔5, 3↔4: 94–122) | stage-entry reminders + receipt-refusal restatements | SKILL.md global convention |

Unique mechanically-duplicated content across the layer: ~4k words. Caveat: skills and
agents load into separate contexts, so dedup only reduces tokens when the canonical home is
loadable from the consuming context; otherwise the win is drift-prevention.

### Tier c — classification (37 files, measured words / judged split)

| File | Words | Contract | Redund. | Ceremony |
| --- | --- | --- | --- | --- |
| run/SKILL.md | 7799 | ~5200 | ~1150 | ~1450 |
| run/state-schema.md | 7883 | ~6450 | ~450 | ~1000 |
| stages/1-intake.md | 4161 | ~3100 | ~350 | ~750 |
| stages/2-worktree.md | 1998 | ~1600 | ~90 | ~310 |
| stages/3-write-plan.md | 1886 | ~1650 | ~110 | ~140 |
| stages/4-plan-review.md | 1165 | ~950 | ~150 | ~100 |
| stages/5-implement.md | 3287 | ~2650 | ~200 | ~450 |
| stages/6-verify.md | 3947 | ~2430 | ~250 | ~1200 |
| stages/7-doc-update.md | 982 | ~845 | ~85 | ~95 |
| stages/8-code-review.md | 3475 | ~2700 | ~210 | ~535 |
| stages/9-open-pr.md | 2666 | ~2200 | ~460 | ~175 |
| stages/10-cleanup.md | 295 | ~285 | 0 | ~25 |
| run/doc-update.md | 2348 | ~1685 | ~100 | ~565 |
| run/hooks.md | 1054 | ~420 | ~570 | ~160 |
| run/eval-criteria.md | 895 | ~675 | ~20 | ~205 |
| run/cost-tracking-setup.md | 1685 | operator reference — relocate (lazy), not cut | | |
| tracker READMEs (3) | 1285 | ~820 | ~410 | ~90 |
| review-lead/SKILL.md | 4751 | ~3700 | ~500 | ~550 |
| reviewer-baseline/SKILL.md | 2172 | ~1750 | ~200 | ~250 |
| plan-reviewer.md | 3307 | ~2750 | ~60 | ~490 |
| security-reviewer.md | 2579 | ~2050 | ~360 | ~190 |
| doc-updater.md | 1945 | ~1350 | ~80 | ~520 |
| scope-completeness-reviewer.md | 1697 | ~1430 | ~165 | ~110 |
| test-coverage-reviewer.md | 1569 | ~1290 | ~155 | ~125 |
| pipeline-reviewer.md | 1525 | ~1310 | ~140 | ~80 |
| intake-orchestrator/SKILL.md | 4665 | ~3800 | ~280 | ~620 |
| intake-interviewer/SKILL.md | 2883 | ~2560 | ~140 | ~160 |
| pr-revision/SKILL.md | 2250 | ~1930 | ~210 | ~110 |
| pipeline-retro/SKILL.md | 1769 | ~1640 | 0 | ~160 |
| figma-faithful/SKILL.md | 3112 | ~2200 | ~570 | ~330 |
| figma-faithful-spec/SKILL.md | 2154 | ~1600 | ~400 | ~150 |
| figma-faithful-reviewer.md | 1890 | ~1830 | ~50 | ~30 |
| figma-faithful-spec-reviewer.md | 1657 | ~1300 | ~300 | ~60 |
| figma-faithful-plan-reviewer.md | 1655 | ~1330 | ~290 | ~40 |
| onboard/SKILL.md | 2741 | ~2530 | ~90 | ~130 |

Bulk pass on the 34-file tail (~27k words, avg ~800 words/file): predominantly small
single-purpose skills and agents (audit-toolkit, second-shift doctor/local-dev-refresh,
remaining reviewers, design-faithful family). Spot signals from the scan: the
design-faithful trio carries the family duplication counted above; the small reviewer
agents share the same ~150–190w boilerplate blocks as the classified ones (covered by the
same reviewer-baseline centralization). No per-file evidence beyond that — per D-3, the
tail is not a wave-1 target.

Model citizens worth naming (calibration anchors, leave alone): `stages/10-cleanup.md`,
`stages/4-plan-review.md`, `pipeline-retro/SKILL.md`, `figma-faithful-reviewer.md`,
`intake-interviewer/SKILL.md`.

## Targets

Per D-6 these are **planning targets tracked by re-snapshot** — the gate stays a flat
growth-guard and is never coupled to them.

| Surface | Now | Target (full program, all three issues) | Δ |
| --- | --- | --- | --- |
| Run session | 44.3k words (~59k tok) | ≤ 38.6k words (~51k tok) | **−13%** |
| Run session incl. de-surfaced operator docs | 47.3k reachable | 38.6k | −18% vs worst case |
| Reviewer dispatch (per agent) | 3.7–5.5k words | −10–15% per agent file | |
| Whole layer (secondary) | 118.4k words (~158k tok) | ≤ 109k words (~145k tok) | −8% |
| narrative `#NNN` in operational prose | 39 across 16 files | 0 (keep the rule, drop the number) | |

The run-session figure is the **program** target: the prose-wave issue alone reaches
~40.3k; the mechanization issue (preflight extraction, stage-entry family) and the
cross-plugin issue (intake-orchestrator, review-lead) carry the rest.

## Ranked reduction candidates

Ordered by (words saved × safety). Disposition: cut / relocate / mechanize.
Risk = behavioral-regression risk if executed as specified.

| # | Candidate | Disposition | ~Words | Tier | Risk |
| --- | --- | --- | --- | --- | --- |
| 1 | De-surface `cost-tracking-setup.md` + 3 tracker READMEs from the run surface (already only linked; make stage-9/stage-1 carry the 2–3 behavioral deltas they need inline, everything else stays as linked reference) | relocate (lazy) | ~3000 off-surface, ~250 cut | c | near-zero |
| 2 | `6-verify.md` five "Why X is inert" essays → comments in `is-inert-diff.sh` (the declared single source of truth; selftests already guard) keeping the 3-line rule (default-to-SUITE, never widen mid-run) | relocate | ~900 | c | low |
| 3 | Mark-stage-started essay family (stages 1, 2, 3, 7, 9 + 5/6 preambles) → one-line rule + SKILL.md convention pointer, **paired with** a pipeline-retro/stage-times WARN on `startedAt≈completedAt` with a large pre-stage gap | cut + mechanize | ~550 | **a (D6)** | low *only* with the paired check; medium bare |
| 4 | run/SKILL.md pre-flight environment gate (~90 lines inline bash) → `tools/preflight-gate.sh` + selftest | mechanize | ~600 | c | low |
| 5 | state-schema.md convention consolidation: `--force` scope (6 statements → 1 + per-site tags), "deliberately-not-a-closed-enum" (4→1), "additive/no-migration" (6→1) — the `--force`-never-bypasses-mark-completed clause survives verbatim, and **each per-site tag must restate the operative clause inline** (state-schema.md is read per-section; a bare pointer is invisible at the read site) | cut | ~400 | c | low-medium |
| 6 | run/SKILL.md dedups: design-driven ¶ → state-schema pointer (~230); RUN_ID / reclaim / failed-state-clearing single-homing (~250); comment-hygiene cluster to one normative statement + one code comment each (~350, keep every rule — they are observed-failure-backed) | cut | ~830 | b+c | medium (hygiene cluster), low (rest) |
| 7 | Receipt/"completion refuses without X" restatements (≥6 sites across stages 1/3/8/9) → "(completion-gated)" tags; the statectl refusal is the enforcement | cut | ~250 | a+c | low |
| 8 | review-toolkit cross-agent boilerplate → reviewer-baseline (extension blockquote ×4, baseline-pointer ×3, Process-skeleton ×3, Output stubs); resolve trust-model canonical home to review-lead | relocate | ~650 (~500 net) | b+c | low |
| 9 | plan-reviewer + doc-updater worked-example blocks → one illustrative instance each (or ship as sample `doc-routing.md` plugin asset) | cut/relocate | ~800 | c | medium-low (explicitly non-normative) |
| 10 | stages/8 skill-load emphasis block → 5 lines (the #158 `skillsLoaded[]` gate is the enforcement now) + drop the non-authoritative "reminder" list | cut | ~290 | a (D5) | low |
| 11 | stages/9 cost-block mechanism prose → pointer at cost-tracking-setup.md (mutual dup today). Stage 9's mark-started essay is **owned by candidate 3**, not here — it must not be trimmed bare ahead of candidate 3's paired check | cut | ~250 | c | near-zero |
| 12 | run/doc-update.md example block → keep the 7.B map only; drop "Why this matters" + `docUpdaterFindings` restate | cut | ~455 | c | low |
| 13 | Archaeology sweep: 39 narrative `#NNN` + version citations (onboard v2.1.x, key-rename story in eval-criteria, design-history HTML comments) — keep the rule each annotates, drop the number/story | cut | ~450 | c | near-zero |
| 14 | intake-orchestrator internal dedup: jira-delta 5→1 blockquote + 3-word site tags; Step 0.5 rationale essays; audit preamble; threshold worked examples | cut | ~570 | c | low |
| 15 | figma family: capability block + steps 1–2 single-homing (kills the declared "keep in sync" liability), branded-rules canonical in figma-faithful-reviewer, origin-story + anecdote (told 4×) deletion; design spec/plan reviewers adopt `skills: reviewer-baseline` (verify cross-plugin install; trinary enum survives verbatim) | cut/relocate | ~1150 in-context (+~1250 drift-prevention) | b+c | medium (cross-plugin dependency), low (rest) |
| 16 | hooks.md embedded `pre-commit-typecheck.sh` copy → link the shipped script; **retarget `pre-commit-typecheck-selftest.sh` lockstep assertion first** | relocate + mechanize | ~400 | c | medium (selftest change is a prerequisite) |
| 17 | Emphasis-inflation singles: mktemp rule 4→2 (SKILL.md), verifyctl-ownership 5→1 (5/6), INFRA-never-charged 4→1, EP-7 guarantee 3→1, schema-sole-output 5→1 (baseline), independence rule 5→2 (scope-completeness), additive-refrain 6→1 (test-coverage) | cut | ~600 | c | low |

Sum of candidates, split by what each actually reduces: **~8.2k words cut/deduped
in-context** + **~1.0k moved into selftested scripts** (candidates 4, 16) = **≈9.2k off
the whole layer** (118.4k → ~109k), plus **~3.0k de-surfaced** (candidate 1 — run-surface
relief only; the text survives as linked reference). Run surface: ~5.7k of the in-context
cuts land on run-surface files → 44.3k → ~38.6k. The targets above are set to exactly
these sums — no margin is claimed; reaching further (e.g. 108k) would require revisiting
the deliberate non-candidates, which is not proposed.

**Deliberate non-candidates** (flagged so nobody "finishes the job" later): security/plan
reviewer calibration example sets (they change verdicts), the trivial-inert carve-out, dark
reviewer accounting, both halves of the scope-independence contract, the AC-ID byte-for-byte
mirror (mechanize with a copies-match lint instead), `stages/10-cleanup.md`,
`pipeline-retro/SKILL.md`, eval-criteria's JSON example (validator-generating) and criterion
letter (scorer-binding).

## Incidental defects found (fix regardless of debloat)

1. `stages/2-worktree.md:205` — verbatim duplicated sentence ("This is the contract —
   `worktree-set` rejects an absolute path…" twice back-to-back).
2. `onboard/SKILL.md` — Step 3 numbers the CI-evidence offer as item 9, but Step 7 and
   Step 8 both gate on "item 8" (the review-context scaffold). Off-by-one; an executor
   following Step 7 literally gates the CI files on the wrong answer.
3. `hooks.md:131` — both stage references predate the current numbering: the full verify
   suite runs at the **Stage 6** (verify) boundary via verifyctl (not "Stage 7"), and the
   commit-per-chunk workflow the fast hook protects is **Stage 5** (implement) (not
   "Stage 6"). Confirm both against the stage files when fixing.

## Follow-on issues (filed, consolidated by logical grouping)

**#165 — dev-pipeline: run-surface prose debloat — dedup, ceremony cuts, and audit defect fixes**
Candidates 1, 2, 5, 6, 7, 10, 11, 12, 13, 17 (dev-pipeline part) plus all three incidental
defects (they are prose corrections found by the same audit; the onboard off-by-one rides
along). Pure prose: no rule is deleted, only restatements, essays narrating existing
mechanical gates, examples beyond the first, and archaeology. Re-snapshot
`prose-budget.sh --update-baseline` in the same PR; selftests + shellcheck green.
Acceptance: run surface ≤ 40.5k words after this issue alone (≤ 38.6k is the program
target once the other two land); every cut names the surviving canonical statement.
Commit verbs `refactor`/`fix`; PR needs a `Changelog:` trailer (consumer-visible: slimmer
instruction layer).

**#166 — dev-pipeline: mechanize prose-enforced rules the retros show failing**
Candidates 3 (retro-side stage-entry timing WARN — the #145 "answer is a mechanism" item,
deliberately not a hard gate per #147), 4 (preflight-gate.sh extraction), 16 (hooks.md
embedded-copy removal with selftest retarget), plus the AC-ID copies-match lint from the
non-candidates list. Each mechanization lands with its selftest **before** the
corresponding prose shrinks (ordering enforced within the PR). Owns every stage-entry
mark-started trim, including stage 9's (see candidate 11 cross-ref). Commit verb `feat`
(new checks are capability); `Changelog:` trailer required.

**#167 — review-toolkit, design-toolkit, intake-toolkit: centralize cross-plugin boilerplate and family dedup**
Candidates 8, 9, 14, 15, 17 (review-toolkit part). Decide the trust-model canonical home
(recommendation: review-lead); delete review-lead's Step-6/Plan-Spec-Awareness verbatim
dup; reviewer-baseline adoption for the two design reviewers is gated on confirming
review-toolkit is a guaranteed co-install (onboard's default bundle satisfies it today).
Commit verb `refactor`; `Changelog:` trailer required (likely `none` per plugin unless
prompt-visible behavior changes).

Sequencing: #166 before or with #165 (candidate 3's cut requires its paired check;
#165 must not trim any mark-started prose bare). #167 independent. Each PR re-snapshots
the baseline it changes.

## Guardrails (restated from #160)

- `prose-budget.sh` remains a flat growth-guard. No downward ratchet, no target coupling.
- The baseline TSV is re-snapshotted by each reduction PR — reductions move the floor,
  they never gate on it.
- No cut lands without naming the surviving canonical statement (or the mechanical check
  that replaces the prose).
