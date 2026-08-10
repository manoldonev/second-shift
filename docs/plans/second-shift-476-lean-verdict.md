# lean review verdict — #476

verdict=approve
run_id: review-476-1
session_id: 3903c806-40a4-4c5a-9ce1-99d30e42aeac
rounds: 1
pr: #480
reviewed_head: a435008d4588604c5c13f9a75a99d8bac02cf1eb
reviewed_patch_id: 204b708a28370e25f684e02f29224f9565c66d33
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 — `review-476-1`. Verdict: **approve**. No blockers. Nine warnings/suggestions, all
non-blocking; the two that matter most are an execution-verified surviving mutant and one
register note that under-describes what lean actually drops.

## Re-stamp (same round — no new round spent)

This record was first written against head `ce20820` / `reviewed_patch_id 46ff7c1f`. `origin/main`
then moved to `c8c1ad0` (#475, #479, #481), and `#475` had appended its own step to the same
`ci.yml` job region this branch appends to — an add/add conflict that left the PR `DIRTY` and
stopped CI dispatching at all (W-9). The conflict was resolved by keeping both steps, `#475`'s
eval-harness step in the position it landed and the capability-parity step immediately after it;
no other file conflicted.

The patch identity moved (`46ff7c1f` → `204b708a`), so this record is re-stamped at the merged
head. It is re-stamped rather than re-reviewed because the measured contribution is unchanged.
Diffing the merge-base-anchored contribution diffs — `git diff 3849ef5..ce20820` against
`git diff c8c1ad0..HEAD -- . ':(exclude)<this record>'` — yields **zero differing `+`/`-` lines**.
The entire delta is three lines: the blob `index` line, the `@@` offset (`-138` → `-144`), and the
two leading context lines, which are now `#475`'s step instead of `check-lockstep-pairs`. The
eight added `ci.yml` lines are byte-identical, and the other four files are untouched by the
merge. `git patch-id --stable` hashes context, not only offsets, which is why the id moved on a
change that altered nothing under review — the measurement is the authority here, not the id.

Re-verified on the merged tree: `capability-parity-check.sh` green (36 rows), its selftest 17/17,
and both new CI steps present exactly once in `lint-and-selftests`, in order, after
`contract lockstep pairs`. The rest of the gate table below was executed at `ce20820` and covers
byte-identical content; CI now dispatches on this branch for the first time and is the live check
on the merged tree.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-2 | **satisfied** | 36 rows, every one carrying a disposition from the closed enum; `bash tools/capability-parity-check.sh` is green against the real tree, and the coverage clause makes every existing `stages/*.md` file answerable to a row before `#348` can delete it. Selftest case (e) drives the red directly. The AC's colon-clause words the mechanism backwards (W-4) — the guard reds on an uncovered file's *presence*, not on its removal — but the mechanism it names ships, so this scores on the letter with the wording carried as a warning. |
| AC-5 | **satisfied** | Mechanically cross-checked: 36 rows = 4 seeded + 32 proposed; the four seeded rows carry exactly their settled dispositions (`unit-test mutation gate` → `ported`, `visual capture` → `dropped`, `doc update` → `dropped`, `design-fidelity and a11y reviewer routing` → `already-covered`); the 32 proposed split 17 `already-covered` / 13 `dropped` / 2 `choreography`, matching the PR body's three lists name-for-name. All ten stage docs plus a cross-stage section are covered. I re-walked all 2060 lines of `stages/1-intake.md` … `10-cleanup.md` for the ratification obligation the guard cannot discharge — every capability I found maps to a row, with the one under-described note at W-2. |
| AC-6 | **satisfied** | The guard runs as an explicit `ci.yml` step in the `lint-and-selftests` job, immediately after `bash scripts/check-lockstep-pairs.sh` — the named precedent. `tools/capability-parity-check-selftest.sh` is 17/17 and proves all three named red paths: (c)/(l) off-enum disposition, (e) uncovered `stages/*.md`, (f)/(g)/(h)/(h2)/(h3) malformed rows, plus (i) duplicate. |

Design fidelity: **not-applicable**. The spec disarms with `Design: none — <reason>`, and the
repo's config carries no `design` key at all, so the disarm is justified rather than a
missing armament.

## Verification run in this review

CI has **never dispatched on this branch** (W-9), so nothing was inherited — every gate below
was executed here, from the reviewed head, cold.

| Gate | Result |
| --- | --- |
| `tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`, no `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID` | **70 scored, 70 run, 0 failed** |
| `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` | clean |
| `bash tools/capability-parity-check.sh` | green — 36 rows |
| `bash tools/capability-parity-check-selftest.sh` | 17/17 |
| `tools/mutation-sweep.sh --mode pr --base origin/main` | 7 applied, **7 killed, 0 survived** — no baseline row owed |
| `find . -name '*.json' \| xargs -n1 jq empty` | clean |
| `scripts/check-frozen-files.sh origin/main` | clean (advisory notice on the `ci.yml` edit; not enforcement) |
| `scripts/check-changelog-trailer.sh origin/main` | not required — no `plugins/**` change; the commit carries a trailer anyway |

Not reachable locally: `actionlint` over the edited workflow, and the ubuntu leg. The two new
scripts carry no BSD/GNU dual-form idiom (`grep -nE 'sed -i|sed -z|readlink -f|stat -f|stat -c|date -r|grep -P|mapfile|realpath'` is empty), and `mktemp -d -t` matches the form 29 other suites
already use, so the portability surface is the repo's existing one. `declare -A` is the file's
first use in the repo, but `mapfile` — the same bash-4 floor — is already used by
`scripts/check-lockstep-pairs.sh` in the very job this step joins, so the floor is not moved.

## Findings

### Warnings

**W-1 — the path-whitespace trim is an untested assertion; the mutant is execution-verified to
survive.** `tools/capability-parity-check.sh:109-110` trims leading/trailing whitespace off each
comma-split path token before it becomes the `COVERED_PATH` key. Replacing both lines with `:`
(a `:` substitution, not a deletion — `bash -n` confirmed the parse is intact) leaves the paired
suite at **17/17 and the real register green**. I ran that probe; this is not an LLM prediction.

The trim is load-bearing for the real register — every multi-path row is written in the file's own
`", path"` style, so without it a stage doc cited only in a non-first position keys as
`" plugins/…"` and reads as uncovered. It survives today only because each of the ten stage docs
happens to also be cited *first* in some row. The only multi-path fixture
(`capability-parity-check-selftest.sh:58`) puts its whitespace on `workflows/beta.mjs`, which is
not a `.md` under `STAGES_DIR` and is therefore never looked up. The effect is one-directional —
a spurious RED on a legitimately-covered doc, never a masked uncovered one — so this is not a
false-green risk, but under the repo's own test-the-tests rule it is a surviving mutant in a
brand-new guard. Fix: order the beta row's paths so the coverage-critical token is the one
carrying the leading space.

**W-2 — the review-exhaustion handoff has no recorded home, and row 71's note does not say so.**
`code-review fan-out panel and bounded round loop` is dispositioned `already-covered`, and the
fan-out and the round-trip genuinely are. What is not covered is what the *bound* produces:
`stages/8-code-review.md` ships a 3-round cap whose terminal path applies the `needs-deep-review`
label, writes `codeReviewExhausted`, and renders an **Outstanding Review Blockers** section into
the PR body — plus the two sibling short-circuits that reuse it (`scope-blocker-no-code-remedy`
and `review-void-zero-coverage`). Those are consumer-visible produced artifacts: a label and a PR
section that tell a human the diff shipped with blockers nobody cleared.

Under lean none of it exists — `grep -rn "needs-deep-review\|codeReviewExhausted\|Outstanding Review Blockers"` over `skills/run-lean/` and `skills/review-lean/` is empty, and neither SKILL
declares a round cap. Row 73 covers the *void* case and correctly calls lean stricter there, but
nothing addresses the exhaustion case. By the register's own definitions that is a `dropped`
capability — "a real capability deliberately given no lean home; the note says where a consumer
that wants it goes instead" — and it is currently riding inside an `already-covered` row whose
note is silent on it. This is exactly the ratification obligation the PR body asks reviewers to
discharge, so it wants an answer now rather than at `#348`.

Not scored as an AC-5 miss: the capability *has* a row and a disposition, so "one row per
capability" holds. The remedy is a sentence in row 71's note, or splitting the exhaustion handoff
into its own `dropped` row.

**W-3 — the `.mjs` citations are rooted differently from every other path in the register.**
Stage docs and tools are cited repo-root-relative
(`plugins/dev-pipeline/skills/run/tools/claim-issue.sh`, `plugins/dev-pipeline/skills/run/verifyctl.sh`).
The seven workflow citations are `workflows/<name>.mjs` — plugin-relative, the form the stage docs
use in a `scriptPath:` argument. There is no `workflows/` directory at the repo root; the files
live at `plugins/dev-pipeline/skills/run/workflows/`. Two rootings coexist in one machine-readable
cell with nothing declaring which is which.

This matters because of what D-17 was written for: the path cell exists "so a tools-file deletion
is covered via its owning behavior", and `#348`'s parity story is keyed on **deleted paths**. A
deletion check that greps this register for a deleted `.mjs` path matches nothing. Affects rows
`intake orchestration and decomposition`, `design FE-spec produce`,
`design-faithful implement and live-render verify`, `pre-implementation plan review gate`,
`additive plan gates (planGates)`, `unit-test mutation gate`,
`code-review fan-out panel and bounded round loop`, `dark-reviewer and voided-round handling`.
One substitution fixes all of them.

**W-4 — three of the four places that describe the coverage clause invert its causality.** The
guard header says "delete a stage doc no row names, and this reds"; AC-2's colon-clause says
"removing a `stages/*.md` file that no row names reds `tools/capability-parity-check.sh`"; the
commit's `Changelog:` trailer says "a stage doc that no register row names cannot be deleted".
Deleting an uncovered stage doc is what makes the clause stop firing — the guard reds on an
uncovered doc's **presence**, and the real property is a *precondition*: coverage must exist
before any deletion can land, so at deletion time every removed doc was already dispositioned.
AC-6 and the selftest's case (e) both word it correctly, which is why nothing is functionally
wrong. The trailer version is the one worth fixing first: it ships as a release bullet.

**W-5 — the protocol docs the stage docs delegate to are not cited in their rows.** `doc update`
cites only `stages/7-doc-update.md`, but that doc says "Full protocol … lives in
[`doc-update.md`](../doc-update.md). On invocation, read that file and follow it; do not re-derive
the protocol from this section" — the implementation is `skills/run/doc-update.md`. Same class:
`post-run eval and retro corpus record` vs `eval-criteria.md`; `cost block` vs
`cost-tracking-setup.md`; `stage-progression state machine` vs `state-schema.md`,
`tools/stage-envelopes.sh` and `tools/stage-times.sh`. D-17 says path cells enumerate every
implementing artifact; these are the artifacts, and they are the ones `#348` will delete.

**W-6 — row permanence is asserted in the header and enforced nowhere.** The register's central
invariant is "ROWS ARE PERMANENT RECORD. A row is never removed when its staged paths die — the
whole point is that the disposition outlives the implementation." No red condition covers it.
`#348` can delete `stages/7-doc-update.md` and the `doc update` row in the same commit and the
guard stays green: the coverage clause simply has one fewer file, and the zero-rows floor is 35
rows away. That is the precise failure the ticket exists to prevent — "nothing anywhere records
that the deletion was a decision". Not an AC miss (the spec enumerates four red conditions and
all four ship, and a history-comparing guard is a different shape), but the strongest invariant
in the file is currently documentation.

**W-9 — the PR is `DIRTY` and CI has never run on it.** `.github/workflows/ci.yml` conflicts with
`#475`, which added its own step in the same region of the same job. GitHub does not dispatch
`pull_request` workflows for a PR whose merge commit cannot be computed, so
`gh api …/commits/ce20820/check-runs` is empty, `actions/runs?branch=claude/second-shift-476`
returns nothing at all, and `pr-gates` / `ci` / `mutation-sweep-pr` have produced zero evidence —
sibling branches `473` and `477` both got runs in the same window. This is not scored as a
blocker: it is not a red build, the whole gate set was executed here instead, and the resolution
is a pure relocation of the eight added `ci.yml` lines. Merge or rebase `origin/main`, confirm the
merge-base-anchored contribution diff is unchanged, and **re-stamp this same round** rather than
spending a new one.

### Suggestions

**S-7 — the advertised second positional is unexercised and mis-resolves.** `Usage:
capability-parity-check.sh [register.tsv] [stages-dir]`, but the coverage loop computes
`rel="${f#"$ROOT"/}"` where `$ROOT` is derived from the *checker's own* location, not from the
passed dir. A stages-dir outside `$ROOT` leaves `rel` absolute, matches no citation, and reds
every file in it. The selftest never passes it — it relocates `$ROOT` by copying the checker into
the sandbox instead, which is the cleaner idiom. Either drop the argument from the usage line or
give it a case.

**S-8 — the `n_stage_files == 0` diagnostic branch is unexercised.** Cases (j)/(k) probe the
post-`#348` lifetime by moving or removing the whole directory, so they land on the sibling
"directory does not exist" branch. The zero-`.md`-files branch is a bare `echo` with no
`VIOLATIONS` or exit-code effect, so killing it is low-value; noted for completeness.

## Strengths

- **The `:`-substitution discipline in the guard's own parser.** The comment above the hand-split
  explains that `IFS=$'\t' read` collapses consecutive tabs, so an empty middle cell shifts every
  later cell left and the empty disposition arrives wearing the note's text. The PR body records
  that the probe *found* that defect rather than confirming an assumption — which is the probe
  working as intended, and worth saying out loud.
- **The tab-count parse instead of `read -a`**, with case (h) written specifically to kill a
  `read -a` rewrite: a trailing tab leaves an empty note cell a field-splitting read never sees.
  The test names the rewrite it is defending against.
- **Cases (k)/(l)/(m) are lifetime tests, not violation tests** — they pin that the coverage
  clause going vacuous after `#348` must not take the enum lint with it, and that a row citing
  dead paths stays valid. Case (j) is asserted specifically in the post-`#348` state, with a
  comment explaining that against live stage docs it would pass with the zero-rows check deleted.
  That is a suite reasoning about its own vacuity.
- **The register's reasoning holds where I spot-checked it.** `is-inert-diff.sh` really does
  survive via `pre-commit-typecheck.sh` and `config-grill.sh`; `retro-corpus.sh` really does detect
  the lean shape structurally on a `verdict_record:` header key; `lean-gate.sh:2348-2354` really is
  the mutation executor and really does skip with a notice rather than a silent pass;
  `lean-gate.sh:2534` really does refuse a receipt whose `rendered_from` drifted, at milestone 4 as
  claimed. Four for four — the notes are load-bearing prose, not decoration.
- **`choreography` as a first-class enum value** rather than a synonym for `dropped` is the right
  call and the header argues it correctly: the parent's rule requires a by-nature death to be a
  *recorded* decision, which is unexpressible if it collapses into the general drop.

## Panel

7 reviewers selected, 7 returned, none dark. `a11y-reviewer` and the design-fidelity dimension
were **not routed**: no changed path matched `stageParams.webComponentGlobs`, which resolves to
the shipped default `apps/web/**/*.{tsx,jsx}` (the repo's config declares no override).

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 0 |
| Security | Pass | 0 (2 suppressed, conf 35–40) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 |
| Test Coverage | Pass | 0 |
| Unit Test Mutation | Fail | 2 (1 major conf 85 → W-1, verified by execution; 1 minor conf 80 → S-8) |

W-2 through W-6 and S-7 are the orchestrator's own, from the stage-doc walk and the guard read;
no reviewer raised them.
