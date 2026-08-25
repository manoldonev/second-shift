# #658 — a review re-runs the sweep CI already ran verbatim at the reviewed head

Operator-directed, 2026-08-24, from the #647 arm-b campaign run: the review session for PR 657
re-executed the full selftest sweep to verify an oracle AC, killed mid-sweep by the operator,
when CI had already run the identical recipe green on two stronger lanes (ubuntu,
macos bash 3.2) at the same head.

## Problem, restated in one line

"Verify an AC by execution, not by trusting prose" is a good rule that over-generalizes: it
also fires when the execution already happened, in CI, on the exact commit and exact command —
so the review session pays minutes to answer a question its own PR's checks already answered,
with less coverage than the citation it replaces.

## What this slice is

One sentence of review-side guidance, landed where a review session loads it, stating a
two-part discriminator (same command AND same head ⇒ cite; either differs ⇒ execute) plus the
mechanics of citing (job, head SHA, conclusion via `gh pr checks` / `gh run view`). No gate, no
script — this is a judgment aid for the reviewing session, the same register as
`docs/pipeline-manifesto.md`.

## Acceptance Criteria

- **AC-1** — the guidance lands in `plugins/dev-pipeline/skills/review-lean/SKILL.md` (the
  surface a review session loads first), stating the cite-vs-execute discriminator inline, with
  the full rationale and worked examples in a new `docs/testing.md` subsection it links to (the
  overflow surface). Both committed.
- **AC-2** (oracle) — no new gate, no new script; `git diff --stat main...HEAD -- '*.sh' '*.mjs'`
  is empty, so the guard-budget guard's delta is zero with no `Guard-mass:` trailer needed.
- **AC-3** (critic) — a `Changelog:` trailer on the branch, stating the guidance in consumer
  terms (a review session may now cite a matching CI run instead of re-executing an oracle AC).

## Do not touch

`plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`,
`.claude-plugin/marketplace.json` `metadata.version` — release artifacts, derived at release
time.

## Decision Ledger

No pre-flight ledger exists for #658, so this table is the run's own; every row is grounded in
the ticket text or in the codebase, never assumed.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which file is "the surface a review session loads"? | `plugins/dev-pipeline/skills/review-lean/SKILL.md` — it is the checklist a `/dev-pipeline:review-lean` session reads first, and step 5 is already where the session scores each `AC-n`, oracle ACs included. Phrase is the issue body's own, at https://github.com/manoldonev/second-shift/issues/658. | ticket-sourced |
| D-2 | The issue flags a 60-line skill cap to mind. Does review-lean/SKILL.md carry that cap? | No — it is 127 lines pre-edit with no cap asserted by any selftest (checked: no suite references `review-lean/SKILL.md` by name for a line-count bound; the 60-line cap that exists is `run-lean/SKILL.md`'s, per `run-lean-skill-60-line-cap` precedent). The caution is honored in spirit — one sentence inline — with the fuller rationale pushed to `docs/testing.md`, the overflow surface the issue itself names. | codebase-derived |
| D-3 | Where in `docs/testing.md` does the overflow land? | A new `### Citing a CI run instead of re-running it (review side)` subsection under `## How the sweep runs`, immediately after `### The pass cache` — the build-side cache and this review-side citation answer the same shape of question ("does this need to run again") from opposite ends of the pipeline. | codebase-derived |
| D-4 | How does a reviewer concretely "cite" a run? | `gh pr checks <pr>` or `gh run view <run-id> --json headSha,conclusion,jobs`, naming the job (`lint-and-selftests` on ubuntu, `selftests-bash32` on macos bash 3.2 — both read from `.github/workflows/ci.yml`), the head SHA, and the conclusion. Verified runnable against this repo's own `gh run view --json headSha,conclusion,jobs` before writing it into the doc. | codebase-derived |
| D-5 | Does this slice need a new selftest? | No. AC-2 says "no new gate, no new script," and `CLAUDE.md`'s test-placement tier map states plainly: "prose in a markdown file → **nothing**." Both files touched are prose/skill guidance, not executable surfaces. | codebase-derived |
