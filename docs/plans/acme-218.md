# Plan — mutation sweep: test-the-tests harness, pair map, PR-scoped + nightly lanes (#218)

## Context

The repo has 49 selftests and 50 shell guards, and nothing measures whether the selftests actually
catch regressions. The epic's audit predicted a concrete corpus of surviving mutants but never
executed it. This lands the standing measurement: a bash mutation-sweep harness that mutates guards,
runs their paired selftests, and reports which mutants survive — turning "are these tests worth
anything" from a one-off audit into a repeatable number.

Spec rev 4 is the binding text. It deliberately de-scoped the pair-map policing lints to #248 after
four intake stops in which each rev's fix mechanism became the next rev's blocker; the measurement
core has been stable since rev 2. The non-bash corpus entries are deferred to #240.

Intake resolved four gaps (D-1..D-4 below) and recorded two implementation choices; the seed run's
2–3h CI round-trip is the schedule's long pole, not a risk to the design.

## Assumptions

1. The universe rule is an exact cover at `f3a9068`: 50 tracked `*.sh` guards (excluding
   `*-selftest.sh`, `*/evals/*`, `tests/hooks-smoke/`), 3 excluded, **47 swept**; 34 resolve
   same-stem (directory-scoped) and the other 13 are each covered by an enumerated pair-map row.
   Verified at intake.
2. Selftests resolve their guard by path relative to their own location (48 of 49 use
   `dirname $0` / `BASH_SOURCE`), so running a killer from inside a mutated sandbox keeps pairing
   intact. Six suites need real git state, which is why the sandbox is `git worktree add --detach`
   and not `cp -R`. The one exception is `scripts/check-workflows-selftest.sh`, which resolves via
   `cd "$(git rev-parse --show-toplevel)"` — inside a detached worktree that resolves to the
   **sandbox** root, so pairing holds there too and no special case is needed.
3. `tools/mutation-sweep-selftest.sh` is picked up by the existing discovery glob in **both** CI
   lanes, including `selftests-bash32` on macOS. That lane checks out **without** `fetch-depth: 0`
   and runs stock **bash 3.2**, so the companion selftest — and every harness path it exercises —
   must be bash-3.2-clean (no associative arrays, no `mapfile`, no `${var^^}`) and must not require
   full history or tags.
4. Kill verdicts are only comparable inside the canonical environment. Local macOS sweeps are
   advisory: the repo documents a platform-divergent guard (`exitplan-ledger-gate.sh`'s tier-3
   `find -newermB` scan is dead code under GNU find).
5. The seed baseline can only be produced on CI. Seeding rides a temporary `push:` trigger on
   `.github/workflows/mutation-sweep.yml` [NEW], because a workflow existing only on a PR branch is
   not `workflow_dispatch`-able.
6. The harness reads `GITHUB_ACTIONS`, `RUNNER_OS` and `SKIP_STRESS` from the ambient environment.
   Anything that invokes the harness must therefore control that environment explicitly rather than
   inherit it — see D-8.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Who supplies `SKIP_STRESS=1` for the PR-scoped sweep — the job, the step, or the harness? | The **step**, via `env: SKIP_STRESS: '1'`. `lint-and-selftests` is ubuntu but sets no `SKIP_STRESS` (`.github/workflows/ci.yml:9-10`; the only occurrence is `:138`, on the macOS job), so a literal implementation reds the merge-blocking lane on every PR with `baseline-environment-mismatch`. Job-level would change the existing selftest step, which the spec explicitly wants exercising the stress legs. The harness must never export it itself — that makes the mismatch check vacuous. | `codebase-derived` |
| D-2 | What is the baseline's `ubuntu-latest` runner field actually compared against? | `RUNNER_OS=Linux`. No Actions variable exposes the `runs-on` label; `ImageOS` is deliberately unstable across image rollouts and would red the lane on GitHub's schedule rather than this repo's changes. The `# environment: ubuntu-latest SKIP_STRESS=1` header text stays as specified and is documentary; the executable assertion is `RUNNER_OS=Linux` plus `SKIP_STRESS=1` plus the `# k=` budget. | `codebase-derived` |
| D-3 | How are catalog mutants addressed, given anchor drift is a red build? | **Pattern addresses only**; a bare line address is not permitted, and a multi-line block uses a start/end pattern range (`/start/,/end/d`). Not hypothetical: the `check-emit-deadline` corpus site was verified at `:132/:133` during run 3 and sits at `:200` in this base, moved by #249 — the pin's own HEAD. It survived only because the corpus quoted the expression; the five line-range entries would not have. The obligation is symmetric to the generic tier's: a PR that edits a guard re-anchors that guard's catalog rows in the same diff, exactly as it re-baselines its ordinals. | `codebase-derived` |
| D-4 | Is a generic "site" a matched line or a matched occurrence? | A matched **line**, at most one mutation per line per operator. Survivor ordinals are a committed, byte-compared contract, so leaving this open means two faithful implementations produce different baselines. Two-way swaps route through a placeholder token so the sed program is not self-cancelling. | `codebase-derived` |
| D-5 | Cap the PR lane's work when a diff touches many fast guards? | Yes — cap at **6** touched fast guards; the remainder reports `deferred-to-nightly` through the mechanism the spec already defines, and the step carries `timeout-minutes: 15`. AC-2 honestly bounds only a 0–2-guard diff. Measured over the last 40 merges the maximum universe-guard touch count is 3 and 12 merges touch none, so 6 is 2x the observed ceiling and its worst case stays inside the timeout. Additive to AC-2, not a weakening. | `codebase-derived` |
| D-6 | Pin the unspecified report/TSV formatting? | Yes, by choice rather than by spec defect: deferred rows carry zero counts and an empty `survivor_ids`; `measured_at` is an ISO-8601 date; `seconds` comes from the seed run's unmutated precheck of that suite. Any consistent choice works and the companion selftest pins it by construction. | `codebase-derived` |
| D-7 | Seed the baseline locally to avoid the CI round-trip? | No. Local macOS seeding would ship BSD kill verdicts into a GNU enforcement lane across a divergence this repo documents (assumption 4). The 2–3h round-trip is accepted, as rev 3 already settled. | `ticket-sourced` — https://github.com/manoldonev/second-shift/issues/218#issuecomment-5109998579 |
| D-8 | How does the in-glob companion selftest avoid tripping the harness's own environment assertion? | **Every fixture invocation pins the environment explicitly; none inherits the lane's.** The companion suite is in-glob by design, so it runs on both CI lanes — where `GITHUB_ACTIONS=1` is always set, `RUNNER_OS` is `Linux` on ubuntu and **`macOS`** on `selftests-bash32`, and `SKIP_STRESS` is unset on ubuntu and `1` on macOS. Inheriting that, the harness would enter enforcing mode and red the environment check on **both** lanes, failing the exit-0 cases for a reason unrelated to any mutant. So: advisory-mode cases run under `env -u GITHUB_ACTIONS`, enforcing-mode cases under `env GITHUB_ACTIONS=1 RUNNER_OS=Linux SKIP_STRESS=1`, and each fixture baseline carries the header matching its case. Case `(i)` then asserts the mismatch red deliberately instead of suffering it. This is the same env-hygiene discipline the existing suites use for `SECOND_SHIFT_CONFIG`. | `codebase-derived` |

## Affected files/modules

**Create — `tools/` (new top-level directory; the repo has none today, verified):**

- `tools/mutation-sweep.sh` [NEW] — the harness. Named outside the `*-selftest.sh` discovery glob so CI never runs it against itself.
- `tools/mutation-sweep-selftest.sh` [NEW] — companion, deliberately in-glob.
- `tools/mutation-pair-map.tsv` [NEW] — `guard`, `selftest`, `note`; one row per (guard, selftest) pair.
- `tools/mutation-exclusions.tsv` [NEW] — `path`, `reason`.
- `tools/mutation-operators.tsv` [NEW] — `id`, `match`, `flip`.
- `tools/mutation-catalog.tsv` [NEW] — `id`, `guard`, `sed`, `note`.
- `tools/mutation-baseline.tsv` [NEW] — seeded from the canonical CI run, committed here.
- `tools/mutation-slow-suites.tsv` [NEW] — `selftest`, `seconds`, `measured_at`; measured by the seed run.
- `.github/workflows/mutation-sweep.yml` [NEW] — nightly `schedule` + `workflow_dispatch`; the repo's first cron workflow.

**Modify:**

- `.github/workflows/ci.yml` — one PR-scoped step in the existing `lint-and-selftests` job.
- `CLAUDE.md` — the tier map gains the sweep row (Stage 7).
- `docs/testing.md` — the full tier map (Stage 7).

## Reuse inventory

- `scripts/check-lockstep-pairs.sh:74` — `while IFS=$'\t' read -r ...` is the repo's TSV-contract read idiom; the harness reuses it verbatim for all six TSVs rather than inventing a parser.
- `scripts/lockstep-manifest.tsv:1-12` — the commented TSV header style (columns documented in-file); the six new TSVs follow it.
- `scripts/check-lockstep-pairs-selftest.sh:72,86,106` — the LOUD anchor-drift convention (`mutation did not apply — the sed anchor has moved`). The catalog tier's red is this exact convention, cited by the spec as precedent.
- `.github/workflows/ci.yml:91-96` — the `BASE_REF`-via-`env` pattern (never spliced into the `run:` body, because ref names permit `$`, backticks and `;`). The new PR-scoped step copies it.
- `.github/workflows/ci.yml:39-46` — the selftest exit-code convention (`exit "$fails"` at `:46`); the companion selftest follows it.
- No new shared helpers are introduced — the harness is the deliverable, not a utility other scripts consume.

## Implementation steps

1. **`tools/mutation-sweep.sh` skeleton + universe/accounting.** Arg parsing (`--mode full|pr`,
   `--base <ref>`, `--seed`, `--report <path>`), repo-root resolution, TSV loaders. Universe =
   `git ls-files '*.sh'` minus `*-selftest.sh`, `*/evals/*`, `tests/hooks-smoke/`. Per guard resolve
   status: an exclusions row preempts pairing entirely (an excluded guard also carrying map rows is
   a lint error); otherwise the kill set is the **union** of the directory-scoped same-stem suite
   (`<guard dir>/<stem>-selftest.sh`) and every map row. A guard with neither is **unaccounted** —
   red.
2. **Sandbox + restore.** `git worktree add --detach` into a temp dir at `HEAD`; `git checkout --
   <file>` between mutants; trap-based teardown.
3. **Unrunnable-pair precheck.** Before any mutant of a guard, run each killer once against the
   **unmutated** sandbox; a killer that does not exit 0 is an unrunnable pair (red), so a broken or
   environment-starved suite can never score its guard's mutants as killed. Time each run here —
   this is also the `seconds` source for the slow list (D-6).
4. **Generic operator tier.** For each operator row in file order: enumerate matched **lines**
   (D-4) with `grep -nE "$match"`; take the first `K=2`; apply `$flip` to that line only
   (`sed -E "<n>{...}"`); `bash -n` validate — an invalid generic mutant is a harness artifact,
   skipped and logged, never red. Survivor id `<guard relpath>::<operator>::<ordinal>`, where the
   ordinal indexes the operator's **full** matched-line list so raising K later re-keys nothing.
   An operator with no applicable site contributes no mutants (data, never red).
5. **Catalog tier.** For each `tools/mutation-catalog.tsv` row whose `guard` is in play: apply the
   pattern-addressed sed (D-3). Byte-identical output **or** `bash -n`-invalid output is anchor
   drift — red. Survivor id `catalog::<id>`.
6. **Kill loop.** Run the guard's killers cheapest-first (slow-list `seconds` ascending, unknown =
   fast) and stop at the first nonzero exit. Kill = **any** paired selftest exits nonzero;
   crash-kills count as kills. A surviving mutant has run every killer.
7. **Report writer.** TSV: `guard`, `status`, `paired_selftest`, `mutants_applied`, `killed`,
   `survived`, `survivor_ids`. `status` ∈ `swept` \| `deferred-to-nightly` \| `excluded`; identical
   column set in both modes; `paired_selftest` is `+`-joined; `excluded` and `deferred-to-nightly`
   rows carry zero counts and empty `survivor_ids` (D-6).
8. **Exit contract + baseline compare.** Enforcing = `GITHUB_ACTIONS` set; local runs are advisory
   and say so. Verify the baseline header against `RUNNER_OS=Linux`, `SKIP_STRESS=1` and the
   current `k` (D-2) **before** comparing survivors; a mismatch is `baseline-environment-mismatch`,
   never a survivor diff. Red on: baseline-absent survivor, `baseline-missing` in an enforcing
   non-seed run, catalog anchor drift, `bash -n`-invalid catalog mutant, unaccounted guard,
   unrunnable pair, environment mismatch, sandbox failure. Warn (never red) on: a killed mutant
   still listed in the baseline, and a baseline row whose guard relpath no longer resolves.
9. **PR mode.** Restrict the universe to guards touched by `origin/$BASE_REF...HEAD` (three-dot,
   base from the PR event). Zero touched guards → exit 0 with an empty report **before any baseline
   resolution** — the ordering is load-bearing, not incidental: it is what stops a doc-only or
   workflow-only PR from reding on `baseline-missing`, and it is what lets this PR's own
   merge-blocking lane stay green while the seed run is still in flight (this diff touches no
   in-universe guard except the self-excluded sweep). Defer any guard
   whose kill set is not a **single fast suite** (slow-list membership or a multi-suite union both
   defer), plus the D-5 count cap; deferred guards are reported, never run.
10. **Seed mode.** Scoped to `mutation-sweep.yml` only. Enter iff the baseline is absent **and** the
    event is not `schedule`, **or** `seed=true` is dispatched (the explicit re-baseline override,
    which never enforces). Publish the report, a ready-to-commit baseline and the measured slow-suites
    file as artifacts; exit green.
11. **Author the four hand-curated TSVs.** Exclusions (4 rows: `_effective-registry.sh`,
    `install-gh-bot.sh`, `.claude/tools/second-shift-doctor.sh`, `tools/mutation-sweep.sh` itself);
    pair map (the enumerated rows, `note` justifying each); operators (the 6 seed ids with concrete
    `match`/`flip`); catalog (one row per in-scope bash-guard corpus prediction, pattern-addressed).
    Two of the exclusions restate exceptions CLAUDE.md's "Genuine exceptions" register already
    carries, so each such `reason` cell **cites that register as its origin** rather than asserting
    an independent rationale, and the Stage-7 doc update points the register at the TSV. One
    register stays authoritative; the other defers to it.
12. **`tools/mutation-sweep-selftest.sh`.** See Test strategy — including the D-8 env pinning, which
    is what keeps this suite green on the macOS lane.
13. **CI wiring.** The `ci.yml` PR-scoped step (`if: github.event_name == 'pull_request'`,
    `env: BASE_REF` + `SKIP_STRESS: '1'`, `timeout-minutes: 15`) and `mutation-sweep.yml`
    (`schedule` + `workflow_dispatch` with a `seed` input, `fetch-depth: 0`, `SKIP_STRESS=1`,
    artifact upload `if: always()`).
14. **Seed round-trip.** Push the branch with a temporary `push: branches: [<this branch>]` trigger
    on `mutation-sweep.yml` → baseline absent, event is not `schedule` → seed mode → download the
    baseline and slow-suites artifacts → commit both → delete the temporary trigger → file the
    survivor findings comment on #218.

## Test strategy

Verify-after (infrastructure, no product behavior change). The harness is proved by its companion
selftest; the guards it sweeps already have their own suites.

`tools/mutation-sweep-selftest.sh` [NEW], exit code = fail count, bash-3.2-clean (assumption 3).

**Why per-tool fixture cases rather than a scenario** (CLAUDE.md's scenario-first rule): the invariant
guarded here is a *repo-level test-infrastructure* contract — the sweep's exit semantics, its two
mutant tiers, and the resolution rules over its TSV family. `scenario-liveness-selftest.sh` composes
**dev-pipeline verdict paths** (stage gates reaching a terminal write); the mutation sweep touches
none of them and is never invoked from a pipeline stage, so no scenario there covers it and extending
it would mean bolting an unrelated harness onto the pipeline composition suite. The rule's real
target — a component tested only against itself — is answered by cases `(j)`/`(k)`, which bind the
harness to the **live tree** rather than to its own fixtures.

**Environment control (D-8):** every case pins `GITHUB_ACTIONS` / `RUNNER_OS` / `SKIP_STRESS`
explicitly and never inherits the lane's; fixture baselines carry headers matching their case.

**Two kinds of case, deliberately:**

- `(j)` and `(k)` run against the **real tree**. They are pure resolution/parse lints — no mutation,
  no sandbox, no suite execution — so they are cheap enough for both per-push lanes and they are what
  stops the harness from converging on green while the tree drifts underneath it.
- `(a)`–`(i)` and `(l)` run against a tiny **fixture** guard + selftest pair in a temp dir, because
  they must actually mutate and actually run a killer.

Cases:

- **(a) green direction** — fixture guard, fixture killer that catches the mutant → the sweep
  reports the mutant killed and exits 0.
- **(b) red direction** — fixture killer that does **not** catch it, with an empty baseline → a
  baseline-absent survivor exits nonzero.
- **(c) baseline suppression** — the same survivor listed in the baseline → report-only, exit 0.
- **(d) shrink warn** — a baseline row whose mutant is now killed, and a baseline row whose guard
  no longer resolves → warn, exit 0.
- **(e) catalog anchor drift** — a catalog sed that leaves the file byte-identical → red.
- **(f) invalid catalog mutant** — a catalog sed yielding `bash -n`-invalid output → red;
  a **generic** mutant doing the same → skipped-and-logged, exit 0 (the tier asymmetry).
- **(g) unrunnable pair** — a killer that fails on the unmutated sandbox → red, and the guard's
  mutants are not scored as killed.
- **(h) `baseline-missing`** — enforcing (`GITHUB_ACTIONS=1`) non-seed run with no baseline → red;
  the same run in seed mode → green with artifacts written.
- **(i) `baseline-environment-mismatch`** — header disagreeing with `RUNNER_OS` / `SKIP_STRESS` /
  `k` → that named red, and **not** a survivor diff.
- **(j) universe rule** — every in-universe guard in the real tree resolves to a same-stem suite,
  a pair-map row, or an exclusions row; an unaccounted guard is red. This is the lint that keeps
  the TSV family honest as the tree changes.
- **(k) TSV family lint** — pair-map rows resolve on both sides; an excluded guard carrying map
  rows is an error; operators have non-empty `id`/`match`/`flip` with unique ids; catalog rows
  reference in-universe guards; slow-suites rows are `selftest` + numeric `seconds` + ISO-8601
  `measured_at`; baseline survivor ids are well-formed.
- **(l) PR mode** — zero touched guards → exit 0, empty report; a slow-list or multi-suite guard →
  a visible `deferred-to-nightly` row with zero counts, never swept.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Full-sweep report covers the whole universe; every exclusion reasoned; seed survivors committed as the baseline with its environment header and filed as a findings comment | 1, 7, 10, 11, 14 | `(j)` universe rule, `(k)` TSV family lint — plus the seed run itself, `— no test (infra-only)` for the committed-artifact and findings-comment legs |
| AC-2 | PR mode is `pull_request`-only, diff-scoped, defers non-single-fast-suite guards visibly, stays under 3 min on a 0–2-guard diff, and is red only on a baseline-absent survivor or the named infra failures | 8, 9, 13 | `(l)` PR mode, `(b)` red direction, `(c)` baseline suppression, `(h)` `baseline-missing`, `(i)` environment mismatch |
| AC-3 | Nightly workflow publishes the TSV report as an artifact and is red only on the same list; baseline-listed survivors report-only; killed-but-listed is a shrink warn | 8, 10, 13 | `(c)` baseline suppression, `(d)` shrink warn, `(g)` unrunnable pair, `(e)`/`(f)` catalog reds |
| AC-4 | Every in-scope bash-guard corpus prediction is a catalog row, confirmed or refuted by the seed run; non-bash and multi-file entries stay deferred to #240; struck entries stay struck | 5, 11, 14 | `(e)` anchor drift, `(f)` invalid catalog mutant, `(k)` catalog rows reference in-universe guards — the confirm/refute leg is the seed run, `— no test (infra-only)` |

## Verification commands

```bash
# Repo-standard gates (CLAUDE.md).
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}

# The new companion suite on its own, and under the macOS lane's exact shape:
# stock bash 3.2 WITH the lane's environment, which is what D-8 exists to survive.
bash tools/mutation-sweep-selftest.sh
env GITHUB_ACTIONS=1 RUNNER_OS=macOS SKIP_STRESS=1 /bin/bash tools/mutation-sweep-selftest.sh
# ...and the ubuntu lane's shape (GITHUB_ACTIONS set, SKIP_STRESS unset).
env -u SKIP_STRESS GITHUB_ACTIONS=1 RUNNER_OS=Linux bash tools/mutation-sweep-selftest.sh

# Advisory local sweep of a couple of fast guards — proves the harness end to end
# without the 2-3h full run. Local runs are advisory by contract and say so.
bash tools/mutation-sweep.sh --mode pr --base origin/main --report /tmp/sweep-report.tsv

# Workflow syntax (CI runs actionlint over both files).
docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 -color
```

## Risks / rollback notes

- **The seed run is a 2–3h CI round-trip.** Accepted by the spec and by D-7. It is the schedule's
  long pole, and the PR is not complete until the baseline it produces is committed. Mitigation:
  everything except steps 14 lands first, so the wait is a single trailing step.
- **A wrong survivor baseline is self-correcting but noisy.** If the seed run's survivor set is
  wrong, the first enforcing PR reds on a baseline-absent survivor. Rollback is a one-line TSV edit,
  or `workflow_dispatch` with `seed=true` to re-baseline wholesale.
- **The PR-scoped step is merge-blocking from the moment it lands.** D-1 and D-2 exist precisely
  because the two naive readings each red the lane on every PR for reasons unrelated to any mutant.
  If the lane proves noisy in practice, the step can be reverted independently of the harness.
- **bash 3.2 on the macOS lane** is the tightest implementation constraint (assumption 3); a bash-4
  idiom will fail there and not on ubuntu. Verified by running the companion suite under
  `/bin/bash` locally. The same lane is also where an un-pinned environment would red the suite
  (D-8) — the two lane hazards are independent and both are covered by the Verification commands.
- **Two registers of "script with no paired suite"** now exist: CLAUDE.md's "Genuine exceptions"
  prose register and `tools/mutation-exclusions.tsv`. They can drift. Mitigated by making the TSV's
  `reason` cells cite the register as origin (step 11) and by pointing the register at the TSV in the
  Stage-7 doc update; not eliminated. Mechanically reconciling the two is a candidate for #248.
- **`tools/` collides in shorthand** with the long-established `plugins/dev-pipeline/skills/run/tools/`,
  so "the tools dir" becomes ambiguous in conversation and in future prose. The name is spec-mandated
  (rev 2 fixed it deliberately, to separate repo-level test infrastructure from `scripts/`' merge-blocking
  gates), so this is accepted rather than resolved; references in docs use the full path.
- **Catalog anchor drift is red on a merge-blocking lane.** D-3's pattern-only rule is the
  mitigation; the residual risk is a guard edit that changes the pattern itself, which by design
  obliges the same PR to re-anchor the row.
- Rollback for the whole change is a revert: nothing outside `tools/` and the two workflow files
  is touched, and no existing guard's behavior changes.

## Out-of-scope

- The opt-in early-abort env for the four slow selftests (the ~70% nightly cost cut). Nightly is
  accepted un-optimized; a follow-up may claim it.
- The `.mjs` / `.md` / `.yml` / multi-file corpus entries — deferred to **#240**, along with the
  struck `diff-range` entry (a future-refactor prediction with nothing to sed).
- Mechanical pair-map policing: the `evidence` line-anchor lint, the bidirectional
  executor-completeness scan, and `mutation-pair-ignore.tsv` — deferred to **#248**, to be designed
  against a harness that exists. Until then a dead map row is a curation bug fixed by ordinary PR,
  and the seed findings comment is the observability.
- The assertion-kill vs crash-kill diagnostic — deferred to **#248**; crash-kills count as kills here.
- Parallelising the sweep. Worst-case nightly is accepted serial.
- Unverified references: none.
