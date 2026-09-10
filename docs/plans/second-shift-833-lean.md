# second-shift #833 — The guards and `LEAN_` identifiers drop the lean name

`CLAUDE.md` calls it "the milestone gate"; the file is `lean-gate.sh`. #731 renamed the prose and
left the identifiers, so the docs name things that do not exist under that name. This closes the
gap, and because it breaks a consumer contract it is the major the deprecated skill aliases have
been waiting for.

The renames and the token sweep are ONE deliverable. 54 of `tools/mutation-catalog.tsv`'s 154 lines
are anchored to these scripts; those rows re-anchor on a path move alone, so renaming the
identifiers inside the same guards in the same commit costs zero additional catalog rows. Splitting
pays the 54-row re-anchor twice for no benefit.

## Goal

Every renamed subject carries its new name, every caller and every path-keyed register follows it,
no tracked file outside `docs/plans/` and `CHANGELOG.md` carries a `LEAN_` token except at the
documented compatibility sites, and a stale `LEAN_*` export still resolves with a one-time stderr
notice rather than being silently dropped.

## The renames, fixed (D-3)

| Now | Becomes |
| --- | --- |
| `plugins/dev-pipeline/skills/build/lean-gate.sh` | `milestone-gate.sh` |
| `plugins/dev-pipeline/skills/build/lean-evidence.sh` | `boundary-evidence.sh` |
| `plugins/dev-pipeline/skills/build/lean-reconcile.sh` | `reconcile.sh` |
| `plugins/dev-pipeline/skills/run/orchestrate-lean.sh` | `orchestrate.sh` |
| `scripts/check-lean-chain.sh` | `scripts/check-lane-chain.sh` |
| `.claude/lean-overrides.tsv` | `.claude/lane-overrides.tsv` |

Each `-selftest.sh` follows its subject.

## Scope

### In

- The six subjects above and their five selftests, plus every caller.
- Every `LEAN_*` identifier in a tracked file outside the frozen sets, renamed `LANE_*`, with a
  read-time fallback at every ENVIRONMENT-read site.
- The path-keyed registers, re-anchored.
- `plugins/dev-pipeline/skills/build/lane-env.sh` — one implementation of the AC-2/AC-3 fallback,
  sourced by the nine scripts that read a knob and carried inline (LOCKSTEP `lane-env-fallback`) by
  the portable `boundary-evidence.sh` — with `lane-env-selftest.sh` beside it and two
  `tools/mutation-catalog.tsv` rows grading that suite.
- `SECOND_SHIFT_LEAN_EVIDENCE`, the consumer template's own seam, renamed
  `SECOND_SHIFT_BOUNDARY_EVIDENCE` with its own inline fallback: it carries the literal `LEAN_`
  that AC-5's fixed-string grep would otherwise find.
- The three deprecated alias skill directories, deleted.
- Prose and schema `description` strings naming a renamed script by path.

### Out

- Plugin `version` fields and `CHANGELOG.md` — derived at release time (CLAUDE.md).
- `docs/plans/**` — historical records, never rewritten.
- The `01-lean-spec-*` eval fixtures and every artifact family (see AC-9).
- Renaming `lean` out of `lane-bench`'s own arm/cell vocabulary beyond the two tokens AC-15 names.

## Acceptance Criteria

- **AC-1** — Each of the six subjects and its selftest carries its new name and every caller is
  updated. Scope is the **basename of these six subjects and their selftests**, not a ban on the
  substring across `plugins/`.
- **AC-2** — `LEAN_*` identifiers become `LANE_*`, and the old spelling **keeps working** at every
  site a script reads one from the ENVIRONMENT: read `LANE_*` first, fall back to `LEAN_*`. A hard
  cut is rejected — a stale export would be silently ignored and the symptom is a false green, not
  an error (D-1). Identifiers that are only ever local shell variables are renamed outright; there
  is nothing for a fallback to catch.
- **AC-3** — The fallback warns **once per process per distinct token, on stderr, never on stdout**
  (D-6). These scripts' stdout is parsed by callers.
- **AC-4** — `.claude/lane-overrides.tsv` is read new-name-first with a fallback to
  `.claude/lean-overrides.tsv` (D-4). Measured at this head: `operator-override.sh` is the ONLY
  side that reads the register — `boundary-evidence.sh` carries the same constant inside the
  `override-record-reader` LOCKSTEP block for its message text and consults no file — so the
  fallback lands there, outside the block, and the block stays byte-identical on both sides.
- **AC-5** — Outside the compatibility sites AC-2 and AC-4 introduce, and outside `docs/plans/` and
  `CHANGELOG.md`, no tracked file carries a `LEAN_` token. Verified with a **fixed-string** grep
  (`git grep -F 'LEAN_'`). `git grep -E '\bLEAN_'` returns zero despite the real matches — `\b` is
  not honored on this path, so that idiom reports success having changed nothing.
- **AC-6** — Every path-keyed register that anchors on a renamed script is re-anchored:
  `tools/mutation-catalog.tsv`, `scripts/gate-buckets.tsv`, `tools/capability-parity.tsv`,
  `tools/selftest-cache-inputs.tsv`, `tools/mutation-baseline.tsv`,
  `tools/selftest-suite-timings.tsv`, `tools/mutation-pair-map.tsv`, `scripts/fail-open-sites.tsv`.
  A stale `selftest-suite-timings.tsv` row does not red the sweep — it silently stops bounding the
  suite it names.
- **AC-7** — `tools/mutation-catalog.tsv` **row ids** naming a renamed script are renamed with it,
  and every cross-reference in `mutation-baseline.tsv`, `mutation-pair-map.tsv` and
  `mutation-exclusions.tsv` is re-keyed in the same commit. A mis-keyed baseline row turns a known
  survivor into a red build.
- **AC-8** — The three deprecated alias skill directories are deleted:
  `plugins/dev-pipeline/skills/build-lean/`, `review-lean/`, `run-lean/` (D-7, D-11).
- **AC-9** — **Untouched**: every on-the-wire marker VALUE and the LOCKSTEP ids that equal one
  (D-2). `LEAN_PR_MARKER_TAG='lean-pr-marker'` and its `LOCKSTEP-BEGIN lean-pr-marker` block are the
  same string ten lines apart; a one-sided rename silently empties the marker set, which is
  indistinguishable from the harness never having run. The variable NAME still moves to
  `LANE_PR_MARKER_TAG`; only the value and the anchor are frozen. Also untouched: the artifact
  families (`-lean.md`, `-lean-verdict.md`, `-lean-renders.md`, `-lean-intent-gap.md`,
  `-lean-override.md`, `{issue}-lean-progress.md`, `{issue}-lean-launches.tsv`, `lean-lanes.tsv`,
  the `-lean-spawn-` log stem) **and the four `# lean …` title lines the gate writes INSIDE those
  records** (`# lean run — issue <n>`, `# lean translation-plan review`, `# lean render manifest`,
  `# lean review verdict`), each of which names its own frozen family from inside it; historical
  records under `docs/plans/`; `CHANGELOG.md`; and the `01-lean-spec-*` eval fixtures.

  Five more members of this class surfaced during implementation and are frozen for the same
  reason — a name a reader outside this diff resolves by:
  - **the `lean chain reconciliation` CI job name** (`.github/workflows/ci.yml`, and the
    `` `lean chain` `` check the docs tell an operator to look for). A required status check is
    keyed BY NAME in branch protection, here and in every consumer that gates on it, so renaming
    it is a settings migration and not a code change — and it would red this PR's own merge.
  - **`plugins/intake-toolkit/skills/plan-interview/tools/dup-scan-fixtures/corpus-live.json`** —
    a frozen calibration corpus of real issue text; `dup-scan.sh` says so in its own header.
  - **`docs/skill-ablation*.md`** — measurements of a text pinned at a named commit. Their PATH
    references move with the rename; their quoted `review-lean` / `build-lean` SUBJECTS do not,
    because rewriting them would falsify what was measured.
  - **the retired `lean/` branch namespace** (#413), which `boundary-evidence.sh` still classifies
    and its suite still covers. It names history, and history did not change.
  - **audit-toolkit's adjectival "lean"** (`the lean audit`, `lean version has none`) — the word
    there means *lightweight*, not *this pipeline*, and rewriting it would make the sentence false.
    Likewise `pre-lean`, which names an era.
- **AC-10** — `plugins/second-shift/templates/consumer/second-shift-ci-check.sh` names the new
  `boundary-evidence.sh` path, and its selftest's asserted string moves with it. This is a
  **consumer migration** (D-5): `onboard` copies that script into every onboarded repo, and an
  existing copy fetches the old path at the consumer's pinned ref.
- **AC-11** — The `Changelog:` trailer carries real migration steps, not `none` — the
  `second-shift-ci-check.sh` re-copy and the alias removal — plus a `BREAKING CHANGE:` footer, on a
  `feat!` subject (D-7, D-10).
- **AC-12** — Prose naming a renamed script by path carries the new path: `CLAUDE.md`,
  `docs/testing.md`, `docs/config-schema.md`, `docs/releasing.md`, `docs/lane-bench.md`,
  `docs/pipeline-manifesto.md`, and the `description` strings in
  `schema/second-shift.config.schema.json` (which still parses: `jq empty`). Measured at this head,
  `docs/releasing.md` names NO renamed script by path — the AC is satisfied there by having nothing
  to change, which is recorded rather than left to look like an omission.
- **AC-13** — The word-bounded sibling-plugin `lean` lines (86 at this head, across
  `plugins/audit-toolkit`, `plugins/design-toolkit`, `plugins/intake-toolkit`,
  `plugins/review-toolkit` and `plugins/second-shift`) name the current spellings; prose using
  "lean" as a concept noun reads as "the lane". What deliberately survives is the frozen class
  AC-9 enumerates plus fixture strings and era names inside suites (`capability-parity.tsv`'s
  staged-vs-lean comparison columns, the selftests' progress-record fixtures) — none of it a name
  a reader resolves to a file.
- **AC-14** — The full sweep is green:
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`.
  **And** `bash tools/install-topology-selftest.sh` passes directly — this is a layout change to
  ten shipped scripts and that guard's push trigger is too narrow to catch the class.
- **AC-15** — `LANE_BENCH_LANE_BIN` and `LANE_BENCH_SS_ROOT` do not ship. The lane-bench family
  already uses "lane" for its own concept, so mechanical substitution yields a doubled noun. They
  ship as `LANE_BENCH_BIN` and `LANE_BENCH_ROOT`, each with a fallback to its own retired spelling.

## Design

Design: none — this change renames files, identifiers and prose. It renders no UI, adds no screen
and no component, and the repo configures no `design.provider`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Whether the retired `LEAN_` environment spelling keeps working | Accept both. Read `LANE_*` first and fall back to `LEAN_*`, the pattern `lean-evidence.sh` already uses for the retired `LEAN_BRANCH_PREFIX`. A hard cut was rejected because a stale operator or CI export would be silently ignored and the symptom is a false green, attend off and observe off, rather than an error | user-answered |
| D-2 | Whether the LOCKSTEP ids that equal an on-the-wire marker value are renamed | Frozen. The wire value wins and LOCKSTEP ids leave this ticket's scope. `LEAN_PR_MARKER_TAG='lean-pr-marker'` and its `LOCKSTEP-BEGIN lean-pr-marker` block are the same string ten lines apart, and the file documents that a one-sided rename silently empties the marker set, which is indistinguishable from the harness never having run | user-answered |
| D-3 | The concrete new name for each renamed script | Pinned as a table in the ticket body rather than left to BUILD, because a wrong pick repays every catalog anchor plus the timings and cache-inputs registers. `milestone-gate.sh`, `boundary-evidence.sh`, `reconcile.sh`, `orchestrate.sh`, `check-lane-chain.sh`, `lane-overrides.tsv`, each selftest following its subject | user-answered |
| D-4 | Whether the renamed overrides register keeps reading its old name | Yes, new-name-first with a fallback. `/second-shift:onboard` writes this file into consumer repos and the reader's absent-register path is a pass rather than an error, so a hard rename would make existing operator overrides silently stop applying | user-delegated |
| D-5 | The consumer CI check resolves `plugins/dev-pipeline/skills/build/lean-evidence.sh` by literal path at the consumer's pinned ref, and `onboard` copies that script into every onboarded repo | Update the shipped template and accept the migration. A forwarding stub at the old path was offered and declined. Consumers must re-copy `second-shift-ci-check.sh`; until they do, bumping their pin to a release carrying this rename breaks their CI | user-answered |
| D-6 | The shape of the deprecation warning the `LEAN_` fallback emits | Once per process per distinct token, on stderr, never on stdout. Per-read warnings would flood a gate log because the busiest tokens are referenced at dozens of sites, and these scripts' stdout is parsed by callers, so anything written there risks breaking a reader | user-answered |
| D-7 | Bump level, given the consumer migration in D-5 | `feat!` with a BREAKING CHANGE footer, cutting a major. The three deprecated skill aliases are deleted in this same ticket, honoring their own stated retirement in the next major rather than deferring it to an unscheduled one. Consumers get a single migration event covering the CI-check re-copy and the alias removal | user-answered |
| D-8 | The scope figures the ticket body asserts | Re-measured at `3113cb95`. `LEAN_` is 1281 occurrences across 136 files and 121 distinct tokens, drifted up from the body's 1279 and 135. Catalog anchoring is unchanged at 54 of 154 rows. The sibling-plugin class is unchanged at 95 word-bounded lines | codebase-derived |
| D-9 | AC-5's list of path-keyed registers names one with nothing in it | `tools/mutation-exclusions.tsv` carries zero lean lines and re-anchors nothing. Measured live: gate-buckets 179, capability-parity 40, selftest-cache-inputs 31, gate-ablation-adjudication 14, mutation-baseline 13, selftest-suite-timings 7, mutation-pair-map 2, fail-open-sites 2 | codebase-derived |
| D-10 | What the `Changelog:` trailer must carry | Real migration steps, not `none`. D-5 makes this consumer-visible and D-7 makes it breaking, so the trailer names the re-copy of `second-shift-ci-check.sh` and the alias removal. Per CLAUDE.md the verb is load-bearing and versions are derived at release time, so the trailer is the only channel | codebase-derived |
| D-11 | Whether deleting the three alias directories is safe at this head | It is. Zero live invocations remain outside frozen records and the alias directories themselves, since #834 cleared the last three, and `orchestrate-lean.sh` already spawns `dev-pipeline:build` and `dev-pipeline:review` by the new names | codebase-derived |
| D-12 | How a lane in flight across the merge is handled | Parked under OR-1. The fallbacks of D-1 and D-4 carry most of it and the progress filename itself is frozen as an artifact family, but rows already written into a record under the old script names are not covered | deferred |

### Departures and measured corrections

None of the twelve rows is departed from. Two of the ledger's `codebase-derived` FIGURES were
re-measured at this head and are stated here as measured, per "re-measure inherited ACs":

- **D-9's `gate-ablation-adjudication` 14 and `capability-parity` 40 do not survive the
  measurement.** Both counts are of the string `lean`, not of a renamed script. All 14
  `gate-ablation-adjudication.tsv` hits are `<issue>-lean-progress.md` record citations — a FROZEN
  artifact family (AC-9) — so that register re-anchors NOTHING and is dropped from AC-6. Of
  `capability-parity.tsv`'s 38 `lean` lines, 17 name a renamed script; the rest are the same frozen
  families. AC-6's obligation is unchanged in kind: re-anchor what actually anchors.
- **D-8's 121 distinct tokens measures 120 here**, and the sibling-plugin class measures 86
  word-bounded lines rather than 95, under this spec's own regex. Neither figure is load-bearing:
  AC-5 and AC-13 are verified by a grep returning empty, not by matching a count.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A lane in flight across the merge resumes against renamed scripts while its progress record was written under the old ones. The failure would be a silent under-count in the cost fence rather than an error, and draining every lane before merge is the alternative BUILD may take if it prefers | reversible-default-and-flag |

**OR-1 resolved by taking the default.** This build takes the fallback path: the `LEAN_*` and
`.claude/lean-overrides.tsv` fallbacks of D-1/D-4 carry an in-flight lane's environment, and the
progress-record family — filename AND its `# lean run` title line — is frozen by AC-9, so a record
written under the old names still reads. What is not covered is a record whose rows QUOTE an old
script path; those rows are prose in a log and no reader parses them. Reversing this costs a re-run
of one lane, not a re-release, which is what makes the default legitimate. Named in the PR body.

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
- `bash tools/install-topology-selftest.sh`
- `git grep -F 'LEAN_' -- ':!docs/plans' ':!CHANGELOG.md'` — every surviving hit is a documented
  compatibility site.
- `bash plugins/dev-pipeline/skills/build/lane-env-selftest.sh` — AC-2 and AC-3 directly, including
  two end-to-end cases (one sourcing script, one inline-twin script) and a coverage derivation that
  reds if a knob is ever read without its fallback.
