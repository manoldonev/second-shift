# lean review verdict — #289

verdict=approve
run_id: review-289-1
session_id: a7663375-1709-457d-a9f4-7724da5b9fc8
rounds: 1
pr: #485
reviewed_head: 8aa024cd0e9994caf6c5bc0150675518e698c90b
reviewed_patch_id: cbff672ac81f78bc998d26c9b92b6f27c93d6985
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1. Range reviewed: the whole branch diff (`c4742ad..8aa024c`) — `lean-gate.sh delta 289`
reported FULL, nothing verifiable to inherit. 5 files, +285/-2.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness
(review-lead fan-out via `code-review.mjs`). Six selected, six returned, none dark. All six
returned `approve` with zero findings; the single suppressed item was a security-reviewer
information-disclosure check on the new stderr note, cleared at confidence 30 (the note emits
only jq-computed integers — no filenames, ticket keys or paths).

Change size Medium (51–300 lines, 4–10 files). `a11y` + design-fidelity not routed: no changed
path matched `stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`);
`db-reviewer`, `pipeline-reviewer` and `unit-test-mutation-reviewer` had no trigger surface
(shell tool + selftest + prose + a TSV manifest, no DB, no queue, no co-located unit specs).

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Observation (non-blocking) | `plugins/dev-pipeline/skills/run/tools/retro-corpus.sh:195` | The `.era == "stage"` clause in the `$live` **collection** has no killing case in the suite — a mutant dropping it survives all 20 cases. It is equivalent on today's corpus, not a hidden defect: the artifact loop only admits state-dir `.md` files carrying a `verdict_record:` header, every such basename carries a suffix (`{issue}-lean-progress`), so no artifact row can ever satisfy `stem == ticketKey` and enter `$live`. The clause is defensive redundancy against a naming convention change, and the code comment says exactly that. The *other* direction — an artifact row being deleted by the dedup — is the one AC-4 names, and its guard (`$r.era == "stage"` in the suppress arm) is killed by the `(289 AC-4)` case. Recorded so a future rename of the progress-record shape is known to land here. |

No blockers. Nothing was softened to keep the run moving; the mutation probes below were run by
this review, not adopted from the PR body.

## Verification run by this review

- `retro-corpus-selftest.sh` under `env -u CLAUDE_CODE_SESSION_ID`: **20 passed, 0 failed**
  (13 pre-existing + 7 new `#289` cases).
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean.
- `scripts/check-lockstep-pairs.sh`: 28 pair(s) checked, 0 failed — the new entry is a
  DROPPED comment block and correctly registers no checked pair.
- Real-corpus behavior, `.claude/pipeline-state` (195 `.json`, 16 quarantined, 63 stage-schema):
  the branch emits 59 stage rows against `main`'s 63, and discloses
  `63 stage-schema file(s), 4 superseded` on stderr — matching the four snapshots the PR body
  names across three suffixes.
- Cross-tool parity, the coupling the manifest entry records: `stage-envelopes.sh --json`
  independently reports `stateFiles: 63` with the same `dedupRule` string. The two corpora now
  agree file-for-file, which is the disagreement `perf-retro` Step 1 used to carry as prose.
- **AC-5 byte-identity measured, not reasoned**: `diff` of `main`'s `retro-corpus.sh` against the
  branch's over a purpose-built no-superseded state dir (two live stage files + one lean progress
  record) — identical in both default TSV mode and `--json`, with an empty stderr.

### Mutation probes (applied diff printed and `bash -n` checked before each scoring)

| Mutant | Result |
| --- | --- |
| `$live` collection neutered to `[] as $live` (dedup dead) | KILLED — `(289 AC-1)`, `(289 AC-3)`, `(289 AC-5)`, `(289 AC-5/tsv)` |
| stderr note made unconditional (`-gt 0` → `-ge 0`) | KILLED — `(289 AC-5/quiet)` |
| `--window` slice hoisted above the dedup block | KILLED — `(289 AC-3)` |
| `$r.era == "stage"` dropped from the suppress arm (cross-era delete) | KILLED — `(289 AC-4)` |
| `($live \| index($r.ticketKey)) != null` → `true` (drop every snapshot) | KILLED — `(289 AC-2)`, `(289 AC-5)`, `(289 AC-5/quiet)` |
| `.era == "stage"` dropped from the `$live` collection | SURVIVED — equivalent, see finding 1 |

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — structural per-ticket dedup, `stem == ticketKey` is live | **satisfied** | `(289 AC-1)` pins one surviving row with stem `310` against two snapshots under `-failed-` and `-spec-blocked-`, neither of which appears anywhere in production code. Dedup-dead mutant killed. Real corpus 63 → 59. |
| AC-2 — no live file, every snapshot survives | **satisfied** | `(289 AC-2)` keeps both `320-aborted-…` and `320-escalated-…` and asserts their stems, so a lookup that collapsed them would fail. The `index(…) → true` mutant is killed here. |
| AC-3 — dedup precedes the `--window` slice | **satisfied** | `(289 AC-3)`'s fixture is ordered so a post-slice dedup drops ticket 420 from a `--window 2`; the hoist mutant produces exactly that and is killed. |
| AC-4 — `era: "artifact"` rows never keyed | **satisfied** | `(289 AC-4)` asserts both eras survive for ticket 340; the suppress-arm era-guard mutant is killed. The collection-side guard is unkillable-but-equivalent (finding 1). |
| AC-5 — stdout byte-identical, disclosure on stderr, conditional | **satisfied** | Measured directly against `main`'s script (above) in both output modes rather than inferred; `(289 AC-5)`, `(289 AC-5/tsv)` and `(289 AC-5/quiet)` pin the stderr counts, the note's absence from stdout, and the silent case. |
| AC-6 — behavioral cases for AC-1…AC-5, each probed | **satisfied** | Seven new cases in the existing per-tool suite (the tier map's row for one script's behavior against fixtures). The obligation is one dedup-arm and one stderr-arm mutant caught; both were re-executed by this review, plus three more. The fixture's suffixes are deliberately ones no production code enumerates, which is what makes the cases fail against a filename-literal implementation. |
| AC-7 — `perf-retro/SKILL.md` Step 1 + `lockstep-manifest.tsv` | **satisfied** | Step 1 now states the shared rule ("**both now dedup `era: "stage"` rows per ticket by the same rule**") and the "**Scope line: when #289 lands…**" sentence is gone; the residual-disagreement sentence correctly re-points at a real disagreement rather than an expected offset. The manifest carries a DROPPED entry naming both implementations, why no byte-anchorable pair exists across awk/TSV and jq/JSON, and the behavioral guard on each side (`stage-envelopes-selftest.sh` env5 / `retro-corpus-selftest.sh` 289 AC-1/2/3). |

Open regions land on their recorded defaults and the PR body discloses both: OR-1 as the DROPPED
manifest form, OR-2 as the non-zero-only stderr note. No spec amendment after the fact — the
committed spec predates the implementation commit.

## CI

`lint-and-selftests` pass, `mutation-sweep-pr` pass, `release-pr-gates` skipped.
`pr-gates` fails on exactly one line — `[lean-evidence] ✗ no committed verdict record` — which is
the by-design pre-handoff state this record resolves; `frozen-files` and the lean-chain
classification within that same job are clean. `selftests (macos, bash 3.2)` was still running at
review time; the diff introduces no bash-4 construct (no associative arrays, no `declare -A`,
no arrays at all — one `jq` pipeline and one `[ … -gt … ]`), so that lane carries no
construct-specific risk here, but it is an unfinished check rather than an observed green.

## Design fidelity

`not-applicable` — the spec's `## Design` section reads `Design: none — shell, selftest and
prose; no rendered surface, no route`, which the diff bears out: no web-component path, no
render receipt, no handoff link.
