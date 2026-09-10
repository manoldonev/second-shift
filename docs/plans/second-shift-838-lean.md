# second-shift #838 — The pipeline's default review panel is scope-completeness only

The private eval substrate's Series 1 deep dive measured 25 review fan-outs across 21 control
cells. `security-reviewer`, `a11y-reviewer` and `unit-test-mutation-reviewer` were selected on 12,
20 and 24 of them respectively, produced 35 findings between them, and moved **zero** hidden tests
and **zero** seeded-defect detectors. `scope-completeness-reviewer` is the only panel member that
ever blocked, and the only one whose gate is structural.

This ticket makes that measurement the routing default — on the pipeline path only. The three
reviewers keep their agents, their triggers, and every other invocation path; what changes is that
on a `/dev-pipeline:review` round their surface triggers no longer *select* them. An operator opts
one back in per ticket (a Decision Ledger row in the committed spec) or per repo (a new
`reviewers.default[]` config key).

The saving is honestly small — ≈0.43 M input-side tokens and ≈7.7 k output tokens per review
round, ≈3% of a cell's input side, and no wall at all, since the three run in parallel with the
scope reviewer, which is the longest dispatch. The reason to ship it is not the tokens: it is that
a panel member whose findings never move a measured outcome is a gate that reads as coverage
without being coverage.

## Goal

On the pipeline path, `review-toolkit:review-lead` selects `scope-completeness-reviewer` (and the
unchanged design-fidelity / domain dimensions) by default, dispatches `security-reviewer`,
`a11y-reviewer` and `unit-test-mutation-reviewer` **only** when an operator opted them in through
one of two carriers, and says in the Review Summary which panel it ran. Every other invocation
path is byte-identical in behavior. A misspelt opt-in name is reported, never silently dropped.

## Scope

### In

- `plugins/review-toolkit/skills/review-lead/SKILL.md` — the pipeline-default panel: what the
  caller declares, which triggers it suppresses, the two opt-in carriers, the unrecognized-name
  rule, and the Review Summary line.
- `plugins/dev-pipeline/skills/review/SKILL.md` — step 5 declares the pipeline default panel when
  it invokes `review-toolkit:review-lead`.
- `schema/second-shift.config.schema.json` — the `reviewers.default[]` key.
- `plugins/dev-pipeline/tools/config-lint.sh` — `default` accepted under `reviewers`, typed the
  way `remove` is; plus its selftest.
- `plugins/review-toolkit/scripts/check-reviewer-references.sh` — a `DEFAULT-UNKNOWN` failure
  class, mirroring `REMOVE-UNKNOWN`; plus its selftest and a fixture.
- `docs/extending.md` — a worked example for `reviewers.default`, and the §1 subtraction claim
  kept true.
- `plugins/second-shift/skills/onboard/SKILL.md` — the sub-key enumeration in the reviewers
  question.
- `tools/mutation-catalog.tsv` — rows for the two new guard arms.

### Out

- `plugins/review-toolkit/workflows/code-review.mjs`. Selection is decided in-session before the
  fan-out and arrives as `args.reviewers`; the dispatcher does not route and needs no change.
- The standalone `/review-toolkit:review-lead` path and `dev-pipeline:pr-revision` (D-3). Their
  routing is unchanged, which is the whole reason the trim is caller-declared rather than sniffed.
- `db-reviewer`, `pipeline-reviewer`, and repo-local `reviewers.add` reviewers (D-4). The bench has
  no DB or queue layer and says nothing about them.
- The design-fidelity dimension (D-5). An armed spec still mandates it and `lean-gate.sh`'s
  `design_family` / `panel_has` still refuse a `--panel` without it.
- `scope-completeness-reviewer` grading a stale issue body over a ratified `user-answered` receipt
  row. Named in #838 as a separate finding; it is not fixed by a trim and is filed on its own.
- The three plugins' `version` fields, `CHANGELOG.md`, and `.claude-plugin/marketplace.json`
  `metadata.version` — derived at release, frozen in a feature PR.
- This repo's own `.claude/second-shift.config.json`. It is gitignored, and this ticket ships the
  key rather than adopting it.

## Acceptance Criteria

- AC-1 — `plugins/review-toolkit/skills/review-lead/SKILL.md` defines the **pipeline default
  panel** as a policy the *caller declares*, not a mode review-lead infers. When it is declared,
  the Conditionally-spawn rows for `security-reviewer`, `a11y-reviewer` and
  `unit-test-mutation-reviewer` do not fire on their surface triggers; every other row of that
  table is explicitly unchanged. When it is **not** declared, routing is exactly today's.
- AC-2 — The same file names two opt-in carriers, either of which selects: (a) a
  `## Decision Ledger` row in the committed spec whose Decision cell is `review panel`, whose
  Resolution cell is a comma-separated list of the short names `security`, `a11y`,
  `unit-test-mutation`, and whose Provenance is `user-answered` or `user-delegated`; (b) config
  `reviewers.default[]`, naming plugin-shipped reviewers by their full bare names. A ledger row
  whose provenance is not one of the two intent values selects nothing.
- AC-3 — The same file states the unrecognized-name rule: a name in either carrier that is not a
  reviewer the effective registry knows selects nothing **and** is named in the Review Summary. It
  is never a blocker and never silent.
- AC-4 — The same file states the record shape when the trimmed default runs (D-6): the Review
  Summary carries one line naming the panel that ran and the opt-ins taken; an unselected
  reviewer's Verdicts row is omitted, not `Dark (no output)`; `security-reviewer` not dispatched
  leaves its Verdicts row reading `Lead pass — ✅/❌`; and `panel:` still lists what was obtained.
- AC-5 — `plugins/dev-pipeline/skills/review/SKILL.md` step 5 declares the pipeline default panel
  when it invokes `review-toolkit:review-lead`, and names where the two carriers are read from.
- AC-6 — `schema/second-shift.config.schema.json` declares `reviewers.default` as an array of
  strings with a description, `reviewers.additionalProperties` stays `false`, and the file parses
  (`jq empty`).
- AC-7 — `plugins/dev-pipeline/tools/config-lint.sh` accepts `reviewers.default`, rejects a
  non-array `reviewers.default` with `reviewers.default: must be array`, and rejects a non-string
  entry with `reviewers.default: every entry must be a string`. A config carrying a valid
  `reviewers.default` no longer trips `reviewers: unknown keys`.
- AC-8 — `plugins/dev-pipeline/tools/config-lint-selftest.sh` gains scenario cases that fail
  without the AC-7 code: a valid `reviewers.default` passing, a non-array rejecting, and a
  non-string entry rejecting.
- AC-9 — `plugins/review-toolkit/scripts/check-reviewer-references.sh` emits
  `DEFAULT-UNKNOWN: reviewers.default names '<n>' but it is not a plugin-shipped reviewer …` for a
  `reviewers.default` entry absent from the plugin registry, exits non-zero on it, and is silent
  on a `default` that names only registry members. The effective-registry computation itself is
  unchanged — `default` neither adds nor removes a reviewer from it.
- AC-10 — `plugins/review-toolkit/scripts/check-reviewer-references-selftest.sh` gains a scenario
  case, backed by a fixture, that fails without the AC-9 code.
- AC-11 — `docs/extending.md` documents `reviewers.default` as an additive key: it can add a
  reviewer to the pipeline default panel and can never subtract one, so §1's "the two places that
  can subtract" claim stays true as written.
- AC-12 — `plugins/second-shift/skills/onboard/SKILL.md`'s reviewers question enumerates `.default`
  alongside `.add`, `.remove`, `.modelOverrides` and `.tierMap`.
- AC-13 — `tools/mutation-catalog.tsv` carries one row per new guard arm (the config-lint
  `default` typing, the `DEFAULT-UNKNOWN` check), each predicting a kill by the AC-8 / AC-10
  cases, and the file's existing rows are unchanged.
- AC-14 — Oracle. `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
  is clean; every `*.json` parses under `jq empty`; and
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  exits 0.

## Design

Design: none — this ticket edits two SKILL.md files, a JSON schema, two shell guards and their
selftests. It renders no UI, and no `design.provider` is configured for this repo.

## Decision Ledger

Rows D-1 … D-9 are carried forward from the pre-flight receipt
(`.claude/pipeline-state/838-ledger.md`) under the same ids and Resolution text. D-10 … D-14 are
build-time decisions.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What "opt-in" replaces for `security-reviewer`, `a11y-reviewer` and `unit-test-mutation-reviewer` | Their surface triggers are DROPPED on the pipeline path: only an explicit opt-in dispatches them. Security stays owned by the lead pass when not dispatched (its existing fallback). Grounded in the private eval substrate's §7: the triggers selected them on 12, 20 and 24 of 25 fan-outs and no finding moved a hidden test or seeded-defect detector. | user-answered |
| D-2 | The opt-in carrier | Two carriers, either selects. Per ticket: a receipt row `\| D-n \| review panel \| security, a11y \| user-answered \| intent \|` that build copies into the committed spec's Decision Ledger, which the review session reads (milestone 1 already lints that section). Per repo: a new `reviewers.default[]` array beside `reviewers.remove[]` in `.claude/second-shift.config.json`, validated by `config-lint.sh` the way `remove[]` is (array of strings naming plugin-shipped reviewers). No tracker label, no jira mirror. | user-answered |
| D-3 | Which entry mode takes the trimmed default | Pipeline only. The `dev-pipeline:review` session states the panel policy when it invokes `review-toolkit:review-lead` in-session (review SKILL step 5 already names review-lead as the implementation); standalone `/review-lead` dispatch mode and `pr-revision` keep today's surface triggers. | user-answered |
| D-4 | `db-reviewer`, `pipeline-reviewer` and repo-local `reviewers.add` domain reviewers | Unchanged: they keep their surface triggers on every path. The bench has no DB or queue layer and says nothing about them. | user-answered |
| D-5 | The design-fidelity dimension | Unchanged. On an armed lean spec the fidelity reviewer is mandatory and the verdict gate refuses a `--panel` without it (`lean-gate.sh` `design_family` / `panel_has`, mirrored in `scripts/check-lean-chain.sh`); on unarmed diffs the existing web-component routing and toolkit-absent degrade stand. | codebase-derived |
| D-6 | Record shape when an opt-in reviewer is not dispatched | Reuse the existing shapes: an unselected reviewer's Verdicts row is omitted (as today for `a11y-reviewer` on a non-UI diff); `security-reviewer` not dispatched → `Lead pass — ✅/❌` (review-lead "Security defers when it is spawned"); the Review Summary carries one line naming the trimmed default and any opt-ins taken, mirroring the existing "no subagent met a trigger this round" line for an empty selection. `panel:` lists what was obtained, as today. | codebase-derived |
| D-7 | Where the opt-in ledger row's grammar is fixed | The Decision cell reads `review panel`; the Resolution cell is a comma-separated list of plugin-shipped reviewer short names (`security`, `a11y`, `unit-test-mutation`); the row must be `intent`-kind (`user-answered` / `user-delegated`), so a `codebase-derived` opt-in is not one. Parked under OR-1: build takes this default and flags it. | deferred |
| D-8 | Duplicate scan | `dup-scan.sh --issue 838` rc 0 — no candidate at or above threshold (corpus of 1). Nothing recorded. | codebase-derived |
| D-9 | Build model sizing | `opus`. Basis: the deliverable is prose in two SKILL.md files plus a new validated config key in `config-lint.sh` — a guard edit that re-anchors `tools/mutation-catalog.tsv` rows and extends the config-lint selftest fixtures — and one deferred grammar (OR-1) the build must take a default on. A guard surface plus an open call is the `opus` shape. | user-delegated |
| D-10 | OR-1 resolution — the opt-in row's grammar, and the spelling asymmetry it creates | Build takes D-7's default verbatim, including its two-value provenance test (`user-answered` / `user-delegated`, the ledger's `intent` kind) — which excludes `ticket-sourced`, the one other operator-originated value in the closed enum; widening to it would be a change to the ledger contract, not to this routing rule, and D-7 is what build was told to take. Build also FLAGS what the default costs: the per-ticket carrier uses short names (`security`) while the per-repo carrier uses full bare names (`security-reviewer`), because `reviewers.default[]` sits beside `reviewers.remove[]` and must be validatable against the plugin registry by the same string compare. Two carriers with two spellings is the one wart in this design. It is reversible per OR-1 — one parser, one doc line — and the unrecognized-name rule (AC-3) makes a cross-spelling mistake visible in the Review Summary rather than silent. | user-delegated |
| D-11 | Whether `reviewers.default[]` may SUBTRACT — e.g. name only `db-reviewer` and thereby drop `scope-completeness-reviewer` | No. It is purely additive: it names reviewers dispatched unconditionally on the pipeline path, on top of the trimmed default. Two reasons. `docs/extending.md` §1 fences subtraction to `reviewers.remove` and `gates`, and a second subtracting key would falsify a claim the doc makes in its first paragraph; and `scope-completeness-reviewer` is the one member the bench measured as load-bearing, so a repo that wants it gone should have to say `reviewers.remove`, where the lint already names it. | codebase-derived |
| D-12 | Where the DEFAULT-UNKNOWN name check lives | `check-reviewer-references.sh`, not `config-lint.sh`. `config-lint.sh` never reads `review-lead`'s SKILL.md, so it cannot know the panel — which is exactly why `remove[]`'s name check lives in the reference checker and its type check lives in the lint. `default[]` gets the same split, so the two keys fail the same way for the same reason. | codebase-derived |
| D-13 | Whether `default[]` joins the effective-registry computation in `_effective-registry.sh` | No. The effective registry is the set of reviewers this repo *has*; `default[]` says which of them the pipeline path *dispatches unconditionally*. Folding it in would make a `default` entry look like an `add`, and `add` carries a consumer-root agent-file obligation `default` must not inherit. The `comm -23` line that `tools/mutation-catalog.tsv` row `reviewer-references-removes` anchors is therefore untouched. | codebase-derived |
| D-14 | Whether the trimmed default needs a shipped runtime guard asserting the fan-out actually shrank | No. Selection is model judgment inside a skill — the same class as every other row of the Conditionally-spawn table, none of which carries a runtime guard — and a guard over it would be a prose-presence assertion, which `writing-tests` forbids. What IS guarded is the machine-readable half: the config key's typing (AC-8) and its name validation (AC-10). The behavioral half is evidenced by the verdict record's `panel:` line on every subsequent run. | codebase-derived |

## Open Regions

| ID | Region | Disposition | Outcome |
| --- | --- | --- | --- |
| OR-1 | The exact grammar of the per-ticket opt-in row (Decision cell wording, bare vs qualified reviewer names, how a misspelt name is reported) | reversible-default-and-flag | Taken, and flagged in D-10. Decision cell `review panel`; short names in the row; an unrecognized name is reported in the Review Summary (AC-3) and selects nothing. |

## Notes

The bench's headline is a null result, and the ticket is careful to say so: the trim buys ≈3% of a
cell's input side and no wall. What it actually buys is a panel whose membership is defensible —
each remaining dimension either blocked something the bench measured, or is mandated by a gate.
