# lean review verdict — #667

verdict=needs-work
run_id: review-667-1
session_id: cd0b9583-58a0-49d4-9ae7-0018f536c57e
rounds: 1
pr: #733
reviewed_head: 707a1ca544ea851ca743020aefb97944a9a563e9
reviewed_patch_id: bfba7da3a59ac0fa6d103460fbbcc617372df5d4
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — #667 / PR #733

Range read: `1d714d4..707a1ca` (root round, full branch diff — 6 files, +626/-50).
Panel: 6 selected, 6 returned, 0 dark (security, performance, maintainability, complexity,
test-coverage, scope-completeness). All six returned zero findings; the blocker below was
hand-derived from the diff.

**Verdict: needs-work — 1 blocker, 3 warnings. 13 of 14 ACs satisfied.**

## Blockers

**B1 — the Rules section still states the OLD Step 4b-void trigger, and on a dark
`scope-completeness-reviewer` it contradicts what AC-10 requires.**
`plugins/review-toolkit/skills/review-lead/SKILL.md:519`

The branch rewrote `### Step 4b-void` (`:377`–`:392`) so that an all-dark **selected set** is no
longer a void when the lead pass completed, and added an explicit paragraph settling the scope
gate: *"The scope gate is a hard No, not a void … a dark return all make 'Ready to merge?' **No**.
It is a real verdict on a round that really happened, so it is never converted into a void"*
(`:388`).

The terminal Rules list was not updated with it. Line 519 still reads:

> **Always give a clear verdict** — "Ready to merge?" must be answered Yes, No, or With fixes.
> **One exception:** a round voided under Step 4b-void (every selected reviewer dark) answers it
> not at all …

The parenthetical is now wrong in both directions: "every selected reviewer dark" is no longer
*sufficient* for a void (`:381` says a completed lead pass makes it a partial-coverage round), and
it is no longer *necessary* (`:386`'s armed-spec case has nothing to do with darkness). `:519` is
untouched by this branch — `git blame` puts it on `33cc62e` — so this is old text the diff made
false, not a typo it introduced.

**Failure scenario.** Routing on a lean round selects only `scope-completeness-reviewer` — the
ordinary shape now that the core four are collapsed, and exactly this PR's own shape — and it goes
dark. Step 4b-void `:388` says: not a void, `Dark (no output)` row, **"Ready to merge?" = No**.
Rules `:519` says: every selected reviewer is dark, therefore voided, therefore **answer it not at
all**. The two are normative statements about the same decision and give opposite outputs. Taking
`:519`, the session emits the "review did not run" report, `review-lean` 5c hands the round back
without writing a record, and the run stalls on infrastructure that reviewed the range perfectly
well — while the hard No that AC-10 mandates is never recorded.

`:495`'s reference to the void is fine (it names no trigger). `:519` is the only wrong restatement
in the file.

**AC-10 is unsatisfied on this**: the AC requires that a dark `scope-completeness-reviewer` keep
Step 4's force and yield "Ready to merge? No". As shipped, the skill states both that and its
negation.

## Warnings

**W1 — `Step 4c`'s intro still counts two cases against a three-bullet list.** `SKILL.md:398`
reads *"**Two** not-selected cases still must not be invisible"* immediately above three bullets
(unmatched web-component surface; security conditional did not fire; design-toolkit not
installed). The closing line of the same section *was* updated — `:404` reads "All three are a
note, never a blocker". No behavior is ambiguous (the bullets are the instruction), so this is a
warning rather than a blocker, but it is the same missed-restatement class as B1 and should be
fixed in the same pass.

**W2 — under `pr-revision`, the four collapsed dimensions are now reviewed by the session that
authored the fix.** `plugins/dev-pipeline/skills/pr-revision/SKILL.md:266` runs review-lead in
dispatch mode from the same session that made the revision commits, so the lead pass (Process step
6) is performed there by the author. Previously those four dimensions had four independent Sonnet
readers. The spec's justification — the Sub-Agent Trust Model already obliges *the reviewing
session* to re-derive them — holds in the lean lane, where `review-lean` is a separate session by
construction, but not on that path. Not raised as a blocker: pr-revision's review is explicitly
advisory and non-blocking by its own contract (`:295`), and the measured blocker yield of the four
is zero. Worth a sentence somewhere, or an explicit acceptance.

**W3 — two sibling sites still state review-lead's void trigger in its old shape.**
`plugins/dev-pipeline/skills/review-lean/SKILL.md:91` ("**every** reviewer it selected went dark")
and, by reference, `lean-gate.sh:5024`. Both are out of scope by the spec's own exclusion list
("Any lane-contract change … hand-back semantics") and neither misbehaves — `review-lean` 5c keys
off review-lead *actually emitting* the void report rather than deciding independently, and the
armed-spec half of both is still correct. Recording it so the follow-up is a choice rather than an
oversight.

## AC scoring

| AC | Score | Evidence |
| -- | ----- | -------- |
| AC-1 — the four no longer selected at any size | satisfied | `SKILL.md` carries no selection site for the four: the "Always spawn (core reviewers)" section is replaced by `### Lead-pass dimensions (never spawned)` (`:164`–`:175`); the depth table's Reviewers column is split into "Lead-pass depth" / "Subagents selected" on all four rows (`:131`–`:135`); the Trivial-inert carve-out no longer says "always get full core review" (`:139`); Step 4b's dark example is re-cast to `db-reviewer + unit-test-mutation-reviewer` (`:374`). Grepped all five names across the file — the only remaining hits are the registry parenthetical, the lead-pass list, the extension-surface list, and dedup prose. |
| AC-2 — the Depth table's surviving role stated | satisfied | `:123`–`:128`, "What this table routes, now that the core four are collapsed": depth calibration + whether the security conditional is worth evaluating; conditional reviewers stay exempt, restated at `:143`. |
| AC-3 — lead-pass checklist reference file | satisfied | `lead-pass-checklist.md`, 338 lines, ships in the skill dir. Carries the generalized Pre-Emit Gate (`:65`), the two-condition Critical trigger (`:52`), a `Do NOT flag` block per dimension (all five verified against the agent files' `What NOT to Flag` — no item dropped), new-vs-pre-existing (`:41`), and confidence ≥ 80 with sub-threshold kept visible in `## Suppressed` (`:29`). Structure is one diff read then per-dimension sections with out-of-diff reads only against a named risk (`:11`–`:21`). Referenced from `SKILL.md:167` and from the Lead pass section at `:228`. |
| AC-4 — security spawns conditionally | satisfied | Conditional table row at `:181` with both arms (diff surface OR `review-context/security-reviewer.md`), matching stated as model judgment; `security-reviewer` added to the never-depth-suppressed list at `:143`; the not-fired case is a Step 4c note at `:401`; the lead pass owns the dimension otherwise and defers when spawned (`:243`–`:246`, checklist `:280`). |
| AC-5 — the lead pass loads the consumer extension surface | satisfied | `:230`–`:238` enumerates the shared core plus all four per-reviewer files, and the security one conditioned on the conditional not firing; empty/TODO-bodied counts as absent (`:240`), matching the `reviewer-baseline` rule and restated in the checklist at `:87`. |
| AC-6 — catalog + extension-points reconciled, reader tokens unchanged | satisfied | `section-catalog.txt` is +10/−0 and every added line is a `#` comment — the active rows and section NAMES are byte-identical, so the catalog↔docs-template lockstep case is untouched. Semantic stated once in the catalog header and mirrored at `docs/extension-points.md:47`–`:53`; all ten `Read by:` tokens unchanged. |
| AC-7 — registry intact | satisfied | All five names remain in the panel parenthetical (`SKILL.md:33`), hence in the effective registry, and in `REVIEWER_MODEL` (`code-review.mjs:36`–`:41`). `check-reviewer-references.sh` exits 0 against the edited file. |
| AC-8 — the three sub-registries stay consistent | satisfied | Verified at the lint's own anchors, not just by its exit code: the `routing` sub-registry parses `**name-reviewer**` between `## Reviewer Routing` and the next `## ` — the four are still bold there, in the lead-pass list; the `verdict` sub-registry's awk anchor `/Verdict       \| Findings/` still matches (header row not reflowed), and the first-column labels Performance/Complexity/Maintainability/Test Coverage are unchanged while the Verdict cells read `Lead pass — ✅/❌`. The Verdict-rules exception is present at `:488`. Lint green. |
| AC-9 — empty-selection short-circuit | satisfied | `code-review.mjs:174`–`:175` throws on a non-array or empty `reviewers`; `SKILL.md:271`–`:282` ("Empty selection: no fan-out at all") instructs skipping the Workflow, and Process steps 7–8 carry the same instruction inline. Correctly classified as neither dark nor a `[Coverage gap]` (`:281`, `:390`). |
| AC-10 — Step 4b-void re-worded for a non-empty lead pass | **unsatisfied** | The Step 4b-void section itself is correct (`:377`–`:392`, including the scope-gate paragraph the AC names). But the Rules section at `:519` still defines the void as "every selected reviewer dark", which on a dark `scope-completeness-reviewer` withholds the verdict the AC requires to be "No". See B1. |
| AC-11 — `code-review.mjs` untouched | satisfied | Absent from `git diff --stat 1d714d4..HEAD`. |
| AC-12 — `review-panel-yield.md` brought in step | satisfied | +20/−0. The note "What the routing edit actually did with P-4 through P-7" sits under the Decisions table, states the collapse-not-domain-gated-dispatch fact, cites the wider 248-version corpus, and records that every panelist stays spawnable. Zero deletions, so the measured columns are provably unrevised. |
| AC-13 — `Changelog:` trailer | satisfied | On `707a1ca`: names the four no longer spawned, the security conditional, that every reviewer stays registered and spawnable, that consumers' `review-context/<reviewer>.md` files are now read by the lead pass and need no edit, and `Migration: none.` `changelog trailer guard` green in `pr-gates` (step 4). |
| AC-14 — validation surface green | satisfied | Cited, not re-run, per the CI-oracle rule — command and head both match. Run `33389195554` at head `707a1ca5`: `lint-and-selftests` **pass** (4m41s, job `99478635223`), `selftests (macos, bash 3.2)` **pass** (7m12s, job `99478635317`), `mutation-sweep-pr` **pass** (job `99478635188`). Run locally in the reviewed checkout: `check-reviewer-references.sh` rc 0, `check-review-context.sh` rc 0, `check-review-context-sections.sh` rc 0, `tools/prose-blockers.sh check` rc 0 (25 constructs / 47 rows / zero undispositioned). Noted: the two `review-context` lints are **vacuously** green here — this repo ships no `review-context/` surface, so they report "clean (no review-context surface)" rather than exercising the reader path. That is a property of the repo, not a gap in the change. |

## Design fidelity

`not-applicable`. The spec's `## Design` section reads `Design: none — this slice edits skill
prose, a reference file, a section catalog and a repo doc`. The disarm is justified: `jq '.design'`
on `.claude/second-shift.config.json` returns null, so this repo configures no design provider, and
no changed path is a web component. There are no `| RS-n |` rows to score.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on **one** step — step 6, "lean chain reconciliation (lean PRs carry their
evidence set)". Read from the job's step list, not from `gh pr checks`: steps 3, 4 and 5 (frozen
files, changelog trailer, pipeline chain) all succeeded. This is the expected pre-verdict state —
the record this round writes is the missing evidence — and it is a policy lane, not a correctness
one.

## Strengths

- The registry-intact decision is carried through concretely rather than asserted: the four stay
  bold inside `## Reviewer Routing` so the lint's `routing` sub-registry still finds them, the
  Verdicts header spacing is left alone so its awk anchor still matches, and `REVIEWER_MODEL` keeps
  all four keys. Consumer migration really is zero on the lint surface, and it is zero for a
  checkable reason.
- `AC-5` is the non-obvious risk in a collapse like this and the change names it directly: the
  collapsed reviewers used to *self*-load their `review-context/<name>.md`, so the lead pass has to
  load them explicitly or consumer calibration is silently dropped while every lint stays green.
  The load list at `:230`–`:238` and the empty-section-counts-as-absent rule are the fix.
- `AC-12` is a good instinct — landing a collapse when the measurement register says `demote`
  ("dispatched only on a diff matching its domain") would have left that table asserting a routing
  rule the tree no longer has. The note reconciles it without touching a measured column, and 20
  additions with 0 deletions proves that rather than claiming it.
- The checklist's fold is faithful where it would have been easy to be lossy: every one of the five
  `What NOT to Flag` blocks survives item-for-item, and the file says plainly that the agent files
  remain the long form.
