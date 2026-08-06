# lean review verdict — #408

verdict=approve
run_id: review-408-1
session_id: e464cd15-924f-4377-8923-e6e4bd8ca8f3
rounds: 1
pr: #414
reviewed_head: bd4428428c72a427462a1bcc2870a90570f084a8
reviewed_patch_id: 1cb5ded24549883e73e5e3746b5f82b9d6a59ff8
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Round 1 — approve

Range read: `c3f8300..HEAD` (full branch diff — root round, nothing to inherit). Two files,
61 insertions / 3 deletions: a new lean spec under `docs/plans/`, and a 6-line prose edit to
`plugins/dev-pipeline/skills/run/tools/tracker/README.md`.

Reviewer panel: `security`, `performance`, `maintainability`, `scope-completeness` — all four
returned `approve` with zero findings, none dark. Depth routing put this at Small, not
Trivial-inert: the README lives under `plugins/*/skills/`, which in this repo is the
instruction layer (context-loaded, prose-budget-ratcheted), not a `docs/` doc.
`a11y` + design-fidelity were not routed — no changed path matched
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).

The premise the change rests on was verified against the scripts rather than taken from the
spec. `lean-gate.sh` carries **five** behavioral `[ "$TRACKER_TYPE" = "jira" ]` conditionals —
`cmd_entry` (:724), `cmd_claim` (:743), `check_pause_and_ask` (:842), and two in
`jira_items_section` (:2114, :2132) — so "exactly three" was stale under any counting
convention, not just the one #398 applied. `lean-reconcile.sh` carries **three** (:138 the
`--comments-file` refusal, :247 the check-(1) arm, :467 the closing-line qualifier), so
"exactly one" was stale too. Both counts are gone rather than re-pinned, which is the point.

Grepped every tracked `.md` outside `docs/plans/` for a surviving branch-site count: the two
sentences in this file were the only shipped-prose sites, and both are fixed. Remaining hits
are historical spec/verdict records for #362/#388/#398, which are records of what was true
then and correctly untouched.

### Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** — neither sentence states a numeric count of a script's tracker branch sites | satisfied | `README.md:43` now reads "branches at tracker-sensitive sites"; `:47` reads "branches at its own tracker-sensitive sites". No numeral, no bolded count, in either. The two-hunk diff touches nothing else in the paragraph. |
| **AC-2** — docs still distinguish gate branch sites from the lane-operation table, and still record that both scripts reject an unrecognized `tracker.type` | satisfied | The distinction survives structurally: both sentences still attribute branch sites to the two named *scripts*, "Milestones 1–4 are adapter-insensitive" is byte-unchanged between them, and the table below is headed **Operation** over entry/claim/exit/reconcile. The reject sentence is retained verbatim — "Both reject an unrecognized value rather than falling through to an arm" — and is true: `lean-gate.sh:250-252` and `lean-reconcile.sh:129-131` are the same `case`/`envfail` shape. |
| **AC-3** — prose-only; no gate or selftest edits; existing suites green untouched | satisfied | The diff contains no `.sh`, `.mjs`, `.json` or workflow file — two markdown files only. CI `lint-and-selftests` is **green on `bd44284`** (GitHub Actions run 31114798010), which is the AC's "green untouched" verified rather than asserted. |
| **AC-4** — `Changelog:` trailer present | satisfied | `bd44284`'s body carries the bare no-op form `Changelog: none.` Checked against the actual suppressor rather than the convention: `derive-release.sh:240-243`'s `render_bullet` strips trailing whitespace and a trailing period before testing `tolower(t) != "none"`, so `none.` is suppressed. This is the exact trap the `none — <rationale>` form walked into on #401; the form used here is correct. |

### Design fidelity

`not-applicable`. The spec's `## Design` section is the disarmed form (`Design: none — prose-only
change to a markdown file, no UI surface, and design.provider is unconfigured in this repo`), and
the disarm holds on inspection: `.claude/second-shift.config.json` declares no `design` key at
all, and the diff touches no web-component surface. Nothing to hash-verify, no RS rows, no
handoff frame.

### Findings

No blockers. Four non-blocking notes, none of which the build session needs to act on.

| # | Class | Where | Note |
| --- | --- | --- | --- |
| N1 | pre-existing | `prose-budget.sh` | This file is a prose-budget FAIL (`baseline 770` → `1271` words), but it already fails identically on `main` at `c3f8300` (`1270` words), and the repo-wide totals are unchanged at 19 fails / 21 warnings on both sides. The PR moves it by one word. Not introduced here, and not a gate on this PR either way: `prose-budget.sh` appears in no `.github/workflows/` file, and lean milestone 2 runs `check-frozen-files.sh` + `check-changelog-trailer.sh` only. |
| N2 | CI infra | `selftests (macos, bash 3.2)` | Red, but from a GitHub Actions outage, not this branch: the job died in **Set up job** with `Failed to resolve action download info. Error: Service Unavailable` after two retries, so it never reached checkout. The same job is green on `main`'s run of the same base commit. Pushing this verdict record retriggers CI and re-runs it — no manual action needed. |
| N3 | expected | `pr-gates` | Red pre-review, and only at the **lean chain reconciliation** step; the frozen-files, changelog-trailer and pipeline-chain steps all pass. That step wants the verdict record this round is writing, so its red is the expected pre-verdict state. |
| N4 | suggestion | `README.md:43,47` | The two sentences are now phrased asymmetrically ("branches at tracker-sensitive sites" vs "branches at *its own* tracker-sensitive sites"), and post-fix each carries close to zero information — a tracker-sensitive script branching at tracker-sensitive sites is a tautology. That is the cost the spec knowingly chose: AC-1 mandates dropping the count, and #407 set the precedent for this exact file. Raising it as a blocker would be amending the spec from the review chair, so it stays a note. If the sentences are ever revisited, "branches only where the adapter differs, and nowhere in milestones 1–4" would carry the meaning the number used to. |

### Verdict

`approve`. Every AC is satisfied on the diff rather than on the spec's promises; the premise the
change rests on was independently re-derived from both scripts and holds; the panel found
nothing; and the one CI red that is not structurally expected is a GitHub outage in job setup.
