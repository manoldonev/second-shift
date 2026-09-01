# lean review verdict — #724

verdict=needs-work
run_id: review-724-1
session_id: f9fb0860-7f11-48ea-b284-83fd50141203
rounds: 1
pr: #761
reviewed_head: 707d9a7b6b6a0990f484a00df04e182960050767
reviewed_patch_id: 5c7dc64c81ff361be9d7cb72e6743067988b802c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — PR #761 (issue #724)

Range read: `153188f5..HEAD` — the whole branch diff (root round, nothing to inherit).
Reviewed head: `707d9a7b6b6a0990f484a00df04e182960050767`. Docs-only: `CLAUDE.md`,
`docs/consumer-eval.md` (new), `docs/plans/second-shift-724-lean.md`, `docs/releasing.md`.

Panel: `review-toolkit:scope-completeness-reviewer` (returned `block`). The four collapsed
dimensions plus security were the lead pass's — this diff is trivial-inert prose outside
`.claude/`, so maintainability and scope are the two with a real surface. a11y and
design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs` (unset,
default `apps/web/**/*.{tsx,jsx}`), and the spec carries no `## Design` section, so the run is
unarmed. security-reviewer not selected: no security surface in a prose diff and no
`.claude/second-shift/review-context/security-reviewer.md` in the repo; the lead pass owned the
dimension.

CI at this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass. `pr-gates` fails on exactly one line — `no committed verdict record`
— which is the pre-approve state, not a finding.

## Findings

| # | Severity | Anchor | Finding |
| --- | --- | --- | --- |
| 1 | **blocker** | `docs/consumer-eval.md:99-112` | The prescribed `launchToMerged` start rule discards only a `preflight-rejected` group. A launch group that **spawned and then stranded without writing any `terminal` row** survives the filter, and the rule takes it. That case is live on the ledger this PR cites as its own demonstration: `724-lean-launches.tsv` carries group `20260831T223407Z-28860` (launch 22:34:07Z, one `spawn`, **no terminal**) and then a fresh group `20260901T062648Z-11087` (launch 06:26:48Z) that produced PR #761. The awk returns `2026-08-31T22:34:07Z`. The issue's Behavior §4 defines the start as "the first `launch` row of **the run that produced the merged PR**" — which is `06:26:48Z`. The two readings differ by **~8 hours** on this one ledger, most of it an operator gap. The document names the rejected-preflight exclusion explicitly and is silent on this one, in a section whose thesis is "Each has one exact source. Nothing here is estimated." The remedy is to state which reading governs — discard a group with no terminal row the way a rejected preflight is discarded, or keep it and say the figure includes re-launch gaps — not to leave it to the reader. |
| 2 | **blocker** | `docs/consumer-eval.md` (whole-PR) | **AC-10 / issue Scope-In bullet 4 is unsatisfied.** The issue requires "one fixture ticket run end to end in the consumer repo, its measured output carried in the body of the PR". No consumer-repo replay ran; all four metrics read `unavailable`. The stated cause is real and I re-verified all three rows of it in the consumer's own files — marketplace `ref: "main"`, all six plugins `"latest"`, `configVersion: 1`. But that precondition is listed in the issue under **Dependencies**, not **Deferred**, and nothing in the issue body defers this deliverable or links a follow-up. The build declared the AC unmeetable unilaterally; the scope gate is structurally hard on exactly this shape. Resolutions: run the replay, or have the operator amend the issue with explicit deferral language plus a linked follow-up issue. Finding 1 is the argument for why this matters concretely — the instrument's one real defect is in the metric a replay would have computed first. |
| 3 | major | `docs/plans/second-shift-724-lean.md:167` (D-9) | D-9 reads "Yes, one fixture ticket end to end, measured output in the implementing PR body", provenance `user-answered`, and carries **no DEPARTURE marker** — while D-16, the smaller departure, got one in its own commit (`5e815b27`, "in the reconcile-recognized form"). What shipped departs from D-9. `ledger-lint`'s reconcile binds intent and provenance only, so no gate sees the mismatch; it lands here or nowhere. Whatever finding 2 resolves to, D-9's row has to say it. |
| 4 | nit | `docs/consumer-eval.md:94,96` | `<stateDir>` is the config key `paths.pipelineStateDir` and `<key>` in `<plansDir>/<key>-lean-verdict.md` resolves to `<repo-slug>-<issue>` (`lean-gate.sh:523-524,839`). Legible as placeholders; naming them exactly would cost nothing. |

## Findings dismissed

The panel raised two majors asking for **operator ratification** of the AC-15/AC-6 and AC-3
departures on the ground that the issue body was not amended. I do not carry either as a blocker:

- **AC-15 / AC-6 (continuation cap).** Verified: `orchestrate-lean.sh:332` makes
  `--max-continuations` a hard `envfail`, and every launch row in the live ledgers writes three
  parameters (`build= review= rounds=`), not four. An eval launch obeying AC-15 literally would
  not start. That is a measured-inert divergence, D-16 is marked DEPARTURE in the
  reconcile-recognized form, and the issue body correctly was **not** back-edited. Scored
  `divergent-inert`, not escalated.
- **AC-3 (rounds source).** Verified by running the instrument: `retro-corpus.sh timing` returns
  `rounds: null` on all six most recent runs while `wallClockMin` beside it is populated
  (505, 113, 122, 44, 39) — its `rounds` greps a `round=` token (`retro-corpus.sh:378-383`) the
  current record grammar no longer writes. The verdict record's `rounds:` header key is live and
  committed. That substitution is a correction, not a scope change, and D-13 records it as one.
  AC-3 is scored `unsatisfied` for finding 1 alone, not for this.

## What I verified rather than took on assertion

- Every code citation in the doc and ledger: `orchestrate-lean.sh:332`, `:357`,
  `lean-gate.sh:489`, `:529`, `release-pr.yml` force-push and body PATCH (at lines 95 and 110 —
  D-10 cites 94, one line off, cosmetic).
- The doc's awk, run against the real `724-lean-launches.tsv`: it does return `22:34:07Z` and it
  does discard the `preflight-rejected-resumable` group. That is finding 1 — the demonstration
  validated the exclusion it names and not the property the metric needs.
- `retro-corpus.sh timing --json` on this repo's corpus, for the AC-3 amendment's figures.
- The consumer repo's lockfile, plugin pins and `configVersion`, for the AC-10 bootstrap block.
- Commit order: the spec including all four Amendments landed at `a662bed7`, **before** the
  implementation at `8c525803`. No AC was amended after the fact to match the diff, and the
  issue's own ACs are untouched.
- AC-2 anonymization across all four files and the issue body: clean.

## Strengths

The amendment discipline is the good part of this PR. Three of the four departures are argued
from a measured fact about the tree, each with a runnable citation, and the issue body was left
alone rather than back-edited to match — which is the honest form and is what let me re-verify
each one in minutes. The `launchToMerged` awk is a real, tested command rather than a prose
gesture, and the non-merge rule ("the refusal class *is* the measurement") is the right call for
an eval that exists to catch a bad release.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | all five stated: corpus obligation `:19-48`, pinned-base recipe `:50-85`, four metrics `:87-118`, non-merge rule `:120-128`, recording obligation `:130-144` |
| AC-2 | satisfied | grepped all four changed files and the issue body for consumer/org/stack identifiers — no hit; the only `manoldonev/` occurrences are this repo's own, one pre-existing in `releasing.md:74` |
| AC-3 | unsatisfied | finding 1 — the launch-timestamp source is under-specified for a surviving-but-stranded launch group, and the two readings differ by ~8h on this PR's own ledger. The `rounds` substitution and the `mergedAt`/`usd` sources are sound (see Findings dismissed) |
| AC-4 | satisfied | `:55-62` alternate config via `SECOND_SHIFT_CONFIG` naming the eval base; `:57-59` exactly one differing field; `:64-65` default branch neither modified nor rewound |
| AC-5 | satisfied | `:33` specs live in the consumer repo; `:25-31` the five roles; `:21-23` `F-1`..`F-5` bind in that order |
| AC-6 | divergent-inert | doc table `:150-151` and column contract `:157-169` carry the 10 columns of the spec's Data Contracts, `continuationCap` dropped. measured: `orchestrate-lean.sh:332` hard-refuses `--max-continuations`, and every live launch row writes three parameters, so the column could only ever be empty. follow-up: none owed — the flag was removed in #718 and does not return; D-16 carries the DEPARTURE |
| AC-7 | satisfied | `:120-128` null metric set plus named refusal class, `outcome: did-not-merge:<refusal-class>`, never re-run and never dropped |
| AC-8 | satisfied | `:132-133` comment on the release PR before it merges, rows land on `main` separately; `:142-144` verdict is operator judgment, no automatic threshold |
| AC-9 | satisfied | `docs/releasing.md:47-54` states all three obligations inside the existing numbered flow, and the maintainer-surface block is renumbered consistently |
| AC-10 | unsatisfied | finding 2 — no consumer-repo replay ran; all four metrics `unavailable`. The precondition is genuinely unmet (re-verified) but sits under the issue's **Dependencies**, not **Deferred**, with no linked follow-up, so the deliverable is neither delivered nor deferred by any authority this round can read |
| AC-11 | satisfied | `git diff --stat 153188f5..HEAD` is four Markdown files; nothing under `tools/` or `scripts/`, no `*-selftest.sh` |
| AC-12 | satisfied | `:150-153` header row present with no data rows plus the explicit "No release has been evaluated yet — the table has no rows." |
| AC-13 | satisfied | `:135-140` names both erasure mechanisms and says the placement must not be "simplified" back into the body; verified against `release-pr.yml:95` and `:110` |
| AC-14 | satisfied | `:45-48` sequential, one lane at a time, with the contention reason and the #525 citation |
| AC-15 | divergent-inert | `:70-78` mandates build model, review model and round cap explicitly, all three recorded. measured: `--max-continuations` is an `envfail` at `orchestrate-lean.sh:332`, so a launch obeying the AC as written would not start. follow-up: none owed — #718 removed the budget the flag bounded; D-16 carries the DEPARTURE |
| AC-16 | satisfied | `:38-43` fresh issues each release, with the reason — per-issue lane state is keyed on the issue number and `timing` would silently report release-to-release elapsed time |
| AC-17 | satisfied | `CLAUDE.md:174`, one pointer line beside the existing per-doc pointers |

## Verdict

**needs-work** — two blockers. Finding 1 is a doc edit: name the rule for a launch group that
survives the preflight filter but writes no terminal row. Finding 2 is not the build session's to
resolve alone — it needs either the replay or an operator amendment to the issue body deferring
the bootstrap with a linked follow-up.
