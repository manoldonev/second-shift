# lean review verdict — #347

verdict=needs-work
run_id: review-347-1
session_id: 1b9373b2-7bd3-433e-927d-d1f33176e240
rounds: 1
pr: #369
model: unknown

## Review summary

Round 1 on PR #369 (issue #347). The enumerator itself — `retro-corpus.sh` — is well built:
structural era detection rather than a `-lean-` filename literal, both quarantine families
carried over from the prior enumeration, a real behavioral selftest that executes the script
against generated corpora, and an honest mid-run correction (c0b39b3 found and fixed
`record_key()`'s character class truncating the `verdict_record:` path at its first slash).
Six reviewers ran; none went dark.

**Verdict: needs-work.** All seven of the committed spec's ACs are satisfied by their letter,
but two blockers stand independently of AC scoring: CI is red on a baseline-absent mutation
survivor, and the era-awareness stops at the enumerator — `perf-retro`'s own steps still hard-
error on the all-lean corpus this change exists to make readable.

## Per-AC scoring (against `docs/plans/second-shift-347-lean.md`)

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `retro-corpus-selftest.sh` case (AC-1) green; verified locally, 7/7 pass. See Blocker 2 — the spec's AC-1 is narrower than the issue's. |
| AC-2 | satisfied | mixed-era fixture yields `eras=artifact,stage`. |
| AC-3 | satisfied | ticketKey 345 present in corpus output. |
| AC-4 | satisfied | field present, pass-through and `unknown` default both asserted. See Warning 3 — inert in production. |
| AC-5 | satisfied | `open-prs` flags 701, clears 702, ignores the non-lean 703. |
| AC-6 | satisfied | verified both diffs: `pipeline-retro` Step 1 branches per era, Step 2 routes a Criteria proposal, Step 3 items 1/2/3/5/6 read N/A; `perf-retro` Step 1 sources `retro-corpus.sh corpus --json`, Step 6 template labels both eras. |
| AC-7 | satisfied | `Changelog:` trailer on all three commits. |

## Blockers

**B1 — CI is red: baseline-absent mutation survivor.**
`plugins/dev-pipeline/skills/run/tools/retro-corpus.sh::cmp-z::1`. Per CLAUDE.md, a survivor
absent from `tools/mutation-baseline.tsv` reds the lane; ab714d7 baselined four, CI found five.

Root cause is a platform split, not flake. `cmp-z` ordinal 1 is `retro-corpus.sh:66`,
`sed -n '2,40p' "$0"`; the mutant is `sed -z '2,40p' "$0"`. BSD sed rejects `-z`, so stdout is
empty and the mutant dies — which is what the local macOS advisory sweep saw. GNU sed accepts
`-z`, and with `-n` gone auto-print dumps the whole file, which trivially contains `Usage:` —
so the `(help)` case's `grep -qF 'Usage:'` passes and the mutant survives on CI's ubuntu lane.

The honest remedy is to strengthen the assertion rather than baseline the row: that `(help)`
case was added by c0b39b3 specifically to close a mutation gap, and a presence-only check
cannot. Bounding the window (assert the output does *not* contain a line from below line 40,
or assert a line count) kills it on both platforms and guards the real regression already seen
on #363 — growing a header silently truncates `--help`.

**B2 — era-awareness stops at the enumerator; `perf-retro` still errors on an all-lean corpus.**
`stage-envelopes.sh` hard-exits 2 in two places on a corpus with no stage rows — `:132`
`no run-state files under $STATE_DIR` and `:160` `no readable runs in the window`. It is
unchanged by this PR, and `perf-retro` Steps 3 and 6 still call it unconditionally; the revised
SKILL.md adds no zero-stage-row guard and does not say what those sections emit in that case.

This contradicts the issue's own Scope bullet, "neither era errors on the other", and the
issue's AC-1, "retro tooling produces a complete report from a fixture run containing only
artifact-schema records". The committed spec narrowed that AC to `retro-corpus.sh corpus
--json` exiting 0 — precisely the dimension the diff does cover — so the spec's AC-1 passes
while the issue's does not. The narrowing is the finding, not a technicality.

It is also not hypothetical. The last stage run in the real corpus is dated 2026-07-24; every
run since is artifact-era, and #348 deletes the stage choreography outright. An all-stage-free
corpus is the near-term steady state this change was written for.

Fix: guard the `stage-envelopes.sh` call on the presence of `era: "stage"` rows, state what the
envelope sections read when there are none, and extend the AC-1 selftest to the report path
rather than corpus enumeration alone.

## Warnings

**W1 — the `model:` key is untested at the producer, and its fixture is a mirror.**
`lean-gate.sh` writes `model:` in `ensure_progress_file()` and `cmd_verdict()`, but
`lean-gate-selftest.sh` contains no assertion for it (grepped: the only `model` match is an
unrelated comment on line 223). `retro-corpus-selftest.sh`'s `mkprogress` helper hand-authors
the header shape instead of driving the real writer, and its header comment justifies that by
asserting "the two WRITERS already have their own coverage (statectl-selftest.sh,
lean-gate-selftest.sh)" — which is true for the pre-existing keys and false for `model:`. That
is the shape CLAUDE.md's "No mirror harnesses" rule names: a copy cannot fail on a production
edit. One assertion in `lean-gate-selftest.sh` closes it.

**W2 — `hasApprovedVerdict` is cwd-dependent.**
`retro-corpus.sh:148` resolves the verdict record as `"$REPO_ROOT/$vrel"` while the state dir
resolves from `MAIN_ROOT` (lines 72–78, deliberately worktree-safe). Mixing the two anchors in
one reader makes a corpus field vary with the caller's checkout. Reproduced on the real corpus,
same tool and same state dir: issues 362 and 363 read `hasApprovedVerdict: true` from the main
checkout and `false` from the lean worktree, because their verdict records merged after this
branch was cut. Currently latent — nothing consumes the field yet — but the fix is
`MAIN_ROOT` in place of `REPO_ROOT`.

**W3 — `--window` now mixes eras, silently shrinking `perf-retro`'s stage profile.**
The window is applied after both eras are merged and date-sorted, so artifact rows displace
stage rows in the same budget. Measured on the real corpus at the SKILL's `--window 15`: 5
artifact + 10 stage, against 16 stage rows available. Because artifact rows are always the most
recent, this degrades monotonically — at 15 lean runs the per-stage profile feeding Steps 2–4
is empty. The SKILL.md says only stage rows feed that table but does not account for the two
eras competing for one window.

**W4 — model identity ships inert.**
Nothing in the repo exports `LEAN_RUN_MODEL` — the only references are this PR's own comments
and spec. All five real artifact rows read `model: unknown`, including #347's own build run.
AC-4 passes by its letter, but the ratified directive it implements ("cross-model deltas are
queryable") is unmet in production. `run-lean/SKILL.md` is at its hard 60-line cap, so wiring
it needs a decision rather than a line; worth naming explicitly rather than leaving the key to
read `unknown` forever.

## Dismissed

- *Selftest labels (AC-4)/(AC-5) don't map to the issue's ACs* (scope-completeness, conf 90).
  They map exactly to the committed spec's AC-1..AC-7, which is the definition of done here;
  `check-lean-chain.sh` confirms 7 AC-n references. Not a finding.
- *`gh api --paginate` may emit concatenated page arrays* (my own check). Verified against a
  real issue: `gh` merges into a single array. The pattern is also copied verbatim from
  `lean-gate.sh`'s shipped milestone-5 predicate.

## Suppressed (below confidence threshold)

- `retro-corpus.sh:171` (conf 50) — `verdict_record:` path joined to `$REPO_ROOT` without
  prefix-containment; record is operator-written and only a boolean is observed.
- `lean-gate.sh:295,700` (conf 45) — `${LEAN_RUN_MODEL:-unknown}` interpolated unescaped; a
  newline-bearing value could forge header keys. Operator-controlled, no privilege boundary.
- `retro-corpus.sh:56` (conf 40) — `GH_CLI="${GH:-gh}"` env-selected binary; established
  zero-network seam matching `stage-envelopes.sh` / `lean-gate.sh`.
- `retro-corpus.sh:193` (conf 35) — `gh pr list` stderr echoed into the error message.
- `retro-corpus.sh:~140` (conf 60) — O(n²) jq re-serialization of the growing `rows` array;
  bounded internal tooling, no user-facing path.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 1 blocker, 1 nit (nit dismissed) | 88–90 |
| Security | Pass | 0 (4 suppressed) | — |
| Performance | Pass | 0 (1 suppressed) | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Fail | 1 major | 85 |

Head reviewed: ab714d72a395b6ecd8efb714714365760d465d88.
