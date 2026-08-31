# lean review verdict — #665

verdict=needs-work
run_id: review-665-1
session_id: c3251c09-14e8-4881-abb6-5a08a7c7e128
rounds: 1
pr: #740
reviewed_head: f68e1d81ee5dc209db1242e48248c7b5b5fe8431
reviewed_patch_id: 3f2800c7b3889bffb8343741c98e33be744c06c9
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full branch range (`630b1f89..f68e1d81`, 11 files) — nothing to inherit.

All 8 ACs are satisfied. One blocker sits outside the AC set: the diff reds a
correctness lane, and that red suppressed most of CI's evidence about it.

## Blocker

**B1 — `lint-and-selftests` is RED on `actionlint`, and the red skipped the Linux
selftest sweep plus six register guards.** Job 99516969061 fails at step 7; steps 8-16
(`run all selftests`, `contract lockstep blocks`, `reserved exit-3 lane set`,
`eval-harness model identity`, `capability parity register`, `gate bucket register`,
`namespace direction check`) are all `skipped`, so none of them has a verdict on this
head. Four SC2016 violations, every one on a line this PR wrote — markdown backticks
inside single-quoted shell strings, which shellcheck (running inside actionlint over
`run:` blocks) reads as unexpanded command substitution:

| Site | Offending text |
| --- | --- |
| `.github/workflows/file-issue-on-red.yml:82` | ``printf 'Commit: `%s`\n' "$SHORT"`` |
| `.github/workflows/mutation-merge.yml:124` | ``LEAD='...absent from `tools/mutation-baseline.tsv`...'`` |
| `.github/workflows/mutation-merge.yml:127` | ``LEAD='...the exit contract in `docs/testing.md`.'`` |
| `.github/workflows/mutation-sweep.yml:260` | ``echo 'No `RED:` line was captured — ...'`` |

Not pre-existing and not flake: `main` at this branch's base (`630b1f89`) is CI-green,
as are the two merges after it, and all four sites are in files this PR adds or edits.
There is no `.github/actionlint.yaml`, so SC2016 is not suppressible without adding one.

This is not a merge-boundary policy refusal — actionlint is neither `guard-budget`, the
`Changelog:` trailer, nor frozen files. It is `lint-and-selftests`, which the review
contract names as a correctness lane, and its redness is what makes six of this repo's
own register guards unanswered on this head.

Why it escaped the build: `scripts/check-workflows-selftest.sh` does discover both new
workflows and passes on them (11 ok, 0 failed — 9 on `main`), but it is a YAML floor. It
does not run shellcheck over `run:` bodies, which is the check that actually fails.

Fix shape: double-quote the four strings, or drop the backticks. All four are prose
formatting, so no behavior moves — meaning if that is the whole fix, it changes no line
this round reviewed except those four.

## Warnings

**W1 — two residual "nightly" wordings in `docs/testing.md` now describe a monthly lane.**
`:1539` ("flake in somebody's nightly") and `:1546` ("If a nightly shard starts naming
timeouts..."). AC-5 binds the "Where it runs" section, which is fully rewritten, and
neither line routes to a *deleted* lane — the wholesale lane still exists, at a new
cadence. Stale wording, not an unmet AC.

**W2 — a job-level timeout on `mutation-merge` files nothing.** `file-red` gates on
`needs.sweep.result == 'failure'`; a blown 75-minute *job* bound yields `cancelled`, which
that condition does not match, so the run is silent. The 60-minute *step* bound makes this
the unlikely path (and the header reasons about exactly that step-vs-job split), but the
fallback body claims to cover "a runner death", which is the case most likely to produce a
non-`failure` result. `contains(needs.*.result, 'failure')` is not the fix either;
`!= 'success'` would be.

**W3 — the dedup/classify shell has no automated coverage.** `file-issue-on-red.yml`'s
exists/not-exists and labeled/unlabeled branches, and `mutation-merge.yml`'s survivor-vs-infra
classification, are only exercised by a live red against the GitHub API. D-1's reasoning
(no new `*.sh`, so no paired-selftest obligation) is correct as stated, but B1 is the
concrete cost of untested shell living in YAML.

## Not findings

- **The `deferred-to-nightly` report enum is retained.** Disclosed as D-7 and documented
  at `docs/testing.md:1623`; three selftest greps and the doc consume it.
- **Concurrency is queue-never-cancel, the reverse of the issue's literal "coalescing".**
  D-6, provenance `user-answered` — committed operator authority, and the technical
  argument (a cancelled merge's guards have no later lane) is correct.
- **`run-selftests.sh`'s five "nightly leg" references.** Verified against the workflow
  set: `nightly-guards.yml` is the only cron lane invoking `run-selftests.sh`, and this PR
  does not touch it. Accurate as written.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `mutation-merge.yml` is `on: push: branches:[main]`, `--mode pr --base "$BEFORE"`, `MUTATION_SWEEP_NO_DEFER: '1'`. Depth is full: the six `$MODE` branches in `mutation-sweep.sh` (798/809/1027/1087/1153/2212) govern guard selection, the empty-scope exit, deferral, and shard accounting only — `K_BUDGET` and the catalog tier are mode-independent. Knob present in BOTH `SEAM_SCRUB` copies; `check-lockstep-pairs.sh` green, 30 anchors / 0 failed, `subset-of` relation intact. Exit contract untouched. |
| AC-2 | satisfied | Both lanes call `file-issue-on-red.yml`. The survivor grep matches at source: `red()` (`mutation-sweep.sh:358`) prefixes `[mutation-sweep] RED: `, and `:2199` emits `baseline-absent survivor: $sid`. stderr is captured (`2>&1 \| tee`) on both lanes. Commit travels as `github.sha`; dedup is a `startswith` over the open-issue LISTING, not the eventually-consistent search index. Green files nothing (`if: failure()` / `needs.*.result`). Qualified by W2. |
| AC-3 | satisfied | `cron: '17 3 1 * *'`; `workflow_dispatch` + `seed` input + the seed-mode resolution at `:109-122` and `:143` unchanged; 10-shard matrix and merge job unchanged. |
| AC-4 | satisfied (as scoped by the spec's restatement + D-7) | `ci.yml`'s only `MUTATION_SWEEP_NO_DEFER` occurrence is the prohibition comment. `emit_row "$g" "deferred-to-nightly"` is byte-unchanged. Deferral decisions proved unchanged twice: control sub-case `(r2d)`, and my M1 mutant below, which `(r2d)` kills. |
| AC-5 | satisfied | "Where it runs" is a three-lane table with per-lane deferral and on-red columns. CLAUDE.md unchanged and still accurate — its two `nightly` references are `nightly-guards.yml`/install-topology, out of scope per #666. W1 covers two residual wordings. |
| AC-6 | satisfied | Four sub-cases, all green — locally (`[mutation-sweep-selftest] all cases passed`) and in CI on the macOS bash-3.2 lane (`pass 198s`, run COLD: no row in `selftest-cache-inputs.tsv`). Non-vacuity proved by mutants, below. |
| AC-7 | satisfied | `Changelog:` trailer on `0d834aba`, with `Migration: none.` |
| AC-8 | satisfied | `writing-tests/SKILL.md` now reads "Those **three** are the only places it runs" and names `mutation-merge.yml`. |

## Independent verification

- **Catalog anchoring.** All 37 `mutation-catalog.tsv` rows addressing `lean-gate.sh` /
  `preflight.sh` re-applied at head with `sed -E -e`, the sweep's own form
  (`mutation-sweep.sh:1897`): **ok=37, drift=0, invalid_sed=0, bash_n_invalid=0**. Worth
  re-deriving rather than inheriting: `mutation-sweep-pr` passing in 13s does NOT cover
  these, because `lean-gate.sh` pairs to a slow suite and defers before any sed is applied.
- **Mutant M1 — unconditional bypass** (`if [[ "$NO_DEFER" != "1" ]]` → `if false`),
  isolated detached worktree at the reviewed head. Killed, 5 cases: `(l3)`, `(l3b)`, `(q)`,
  `(r)`, `(r2d)`.
- **Mutant M2 — bypass wired into the slow-suite arm alone** (outer guard → `true`, the
  `NO_DEFER` test moved into the slow-suite arm's condition). Killed by exactly `(r2b)` and
  `(r2c)`, and **not** by `(r2a)`. This is the finding that ratifies D-17's widening: the
  ledger's original single-slow-suite shape would have been blind to M2, which is precisely
  the "merge-time lane silently skips the guards it exists to grade" regression.
- **`pr-gates`** fails on its final step only ("lean chain reconciliation"); steps 3-5
  (frozen files, changelog trailer, pipeline chain) pass. That is the expected pre-verdict
  state, not a finding.

## Panel

`review-lead` fan-out, 6 of 6 returned, none dark: security, performance, maintainability,
complexity, test-coverage, scope-completeness. Zero blockers from the panel. Its two
substantive notes (AC-4's prose departure, D-6's concurrency shape) independently reached
the same reading recorded above; W1 and W3 originate there. `a11y` and the design-fidelity
dimension were not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → default `apps/web/**/*.{tsx,jsx}`). B1 was hand-derived — reviewers read the diff,
not the check surface.

**Fidelity: not-applicable.** The spec has no `## Design` section and the repo configures
no `design.provider`.
