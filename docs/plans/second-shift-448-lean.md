# A deterministic suite re-runs on inputs that did not change — #448

## Problem

Every CI run re-executes every discovered suite, including deterministic ones whose inputs are
byte-identical to the last run that already passed them. There is nothing to cache in the
conventional sense — no dependency install, no build, no compile step — so the form that applies is
**result caching**: not re-running a deterministic suite whose *declared* inputs have not changed.

`#447` (PR #453) already landed the parallel sweep and moved the install-topology class guard to a
nightly workflow. The PR critical path measured **5:48** afterwards, and `statectl-selftest.sh`
alone is **149s** of the 171s ubuntu sweep. That one suite is the floor this change removes.

## Binding input

`.claude/pipeline-state/448-ledger.md` is the pre-flight receipt and **overrides the issue body**
where the two disagree. Three consequences that shape everything below:

- **AC-8 is retired** (D-4). The install-topology guard is nightly-only after #447, so per-plugin
  keying has no PR lane to save on, and AC-7 mandates the nightly bypass the cache regardless.
- **AC-9 is retired** (D-7). Prose-only PRs are 1 of the last 100 commits here, because every lean
  PR commits its `docs/plans/*-lean.md` beside the diff.
- Their IDs are **not reused** (D-15). The landing set is AC-1..AC-7, AC-10, AC-11, plus AC-12 for
  the doc staleness the rename in D-8 creates.

## Design

### The declaration table — `tools/selftest-cache-inputs.tsv`

TSV, one row per **(suite, input)** pair, so adding an input is a one-line diff:

```
suite-relpath<TAB>input-relpath
```

An input may name a file or a directory; a directory contributes every regular file beneath it.

**The table is validated on every sweep, whether or not the cache is in play.** A row is only ever
*used* under `--cache-dir`, but a malformed declaration is a broken gate declaration, and letting
it sit unread until CI is exactly the silent-widening posture the existing stale-`--exclude` check
already refuses.

Validation (all hard errors, `rc=2`, each naming the offending row — same posture as
`stale exclusion`):

- the suite named by a row must be discovered under `--root`;
- every declared input must exist;
- **self-inclusion**: a suite's input set must contain the suite's own path;
- **subject-inclusion**: when `<dir>/<stem>.sh` exists next to `<dir>/<stem>-selftest.sh`, it must
  be declared. Where no such sibling exists the subject cannot be mechanized — the runner instead
  requires **at least one input besides the suite itself**, so a row that declares nothing but its
  own bytes is rejected rather than reading as a complete declaration.

### The key

`sha256` over a manifest built from (D-13): an epoch constant, `RUNNER_OS` (falling back to
`uname -s`), the bash major version, `SKIP_STRESS`, the suite path, and the `git hash-object` blob
id of every declared input in sorted order. The two CI lanes therefore never share a key.

`SKIP_STRESS` is on the axis beyond D-13's list, for the reason `tools/mutation-sweep.sh` already
carries it: a suite that skipped its stress legs passed a strictly weaker question than one that
ran them. Today the two lanes also differ by OS so nothing could collide — but that is a
coincidence of the current matrix, not a property, and the fix is one field.

`SELFTEST_CACHE_EPOCH` is the one-character invalidation OR-1 asks for: runner-image drift can in
principle move a verdict with every declared input byte-identical, and bumping the epoch makes the
next run a full cold sweep — the fail-closed state.

### The store

A directory of marker files, one empty-ish record per passing key (D-6). Presence means pass. The
four concurrent workers never touch it — the parent computes keys before dispatch and writes
markers after the replay — so there is no read-modify-write race and no torn file. A failing or
verdict-less suite simply has no marker written, which is AC-5 falling out of the shape rather than
being separately enforced.

`SELFTEST_CACHE_MAX` (default 5000) clears the store when it overflows, mirroring
`tools/mutation-sweep.sh`'s `cache_prune`.

### The two flags, and why they are two

- `--cache-dir <dir>` — participate. **Absent, there is no cache at all** (D-11), so the mandated
  local recipe in `CLAUDE.md` stays the honest pre-commit gate it is today.
- `--cache-write` — additionally *record* passes. Default off. This is the seam that makes AC-6 an
  executable assertion in the runner rather than a property only GitHub can demonstrate; the
  workflow still additionally conditions `actions/cache/save` on `push`, so the containment is
  belt-and-braces.

This inverts `tools/mutation-sweep.sh`'s cache, which is local-only and disables itself in the
enforcing lane. The difference is which side owns the authority: there CI is the authority and must
run cold; here CI *is* the thing being sped up, and the authority is the nightly wholesale leg.

### Which suites get rows

Per D-9, the three measured at ≥30s in `tools/mutation-slow-suites.tsv`:

| suite | declared inputs |
| --- | --- |
| `statectl-selftest.sh` | itself, `statectl.sh`, `scenario-lib.sh`, `state-schema.md`, `SKILL.md`, `stages/`, `statectl-selftest-fixtures/`, `workflows/mutation-gate.mjs`, `tools/gen-statectl-validators.sh`, `tools/stage-times.sh`, `tools/stage-times-fixtures/` |
| `cost-block-selftest.sh` | itself, `pipeline-cost-block.sh`, `cost-tracking-fixtures/` |
| `scenario-liveness-selftest.sh` | **no row — OR-2 resolves to drop** |

**Eight of statectl's eleven inputs are absent from the issue's own four-entry table**, and every
one of them can move that suite's verdict on its own: it re-runs `gen-statectl-validators.sh` and
diffs the output against `statectl.sh`, drift-checks documented values across `stages/*.md` and
`SKILL.md`, parses sentinel blocks out of `mutation-gate.mjs`, and drives `stage-times.sh` over its
fixtures. This is precisely the under-declaration the self-inclusion rule cannot catch, which is
why every set here was derived from the suite rather than copied from the ticket.

**It also costs hit rate, and the honest number is lower than the pre-flight ledger's.** That
measurement — 13 of the last 100 non-merge commits touch statectl's declared inputs — was taken
against the four-entry set. Adding `stages/` and `SKILL.md` pulls in a subtree that far more
commits touch, so the row will miss more often than projected. It is kept anyway: even at a
reduced hit rate it is the largest single saving available (149s), and the alternative — the
narrower set — is a silently skipped gate. `cost-block-selftest.sh`'s set is tight and unaffected.

**OR-2 resolves to its stated default.** `scenario-liveness-selftest.sh` composes ten scripts by
name plus their transitive closure (`lean-gate.sh` alone sources `branch-prefix.sh` and invokes
`claim-issue.sh`); the closure is not enumerable stably from the suite, so the row is dropped
rather than under-declared. Cost: 31s of the target. Restoring it later is one TSV line.

### Workflow wiring

- `ci.yml`, both selftest lanes: `actions/cache/restore` before the sweep, `--cache-dir` on it,
  `--cache-write` only when `GITHUB_EVENT_NAME == push`, and `actions/cache/save` gated on `push`.
- `.github/workflows/install-topology.yml` is **renamed** to `nightly-guards.yml` (D-8) and gains a
  cache-bypassing wholesale sweep on both lanes — same exclusion, same `SKIP_STRESS` asymmetry as
  `ci.yml`, so the nightly asks the identical question the PR lane asks.

No required status check changes: no job is path-filtered (D-5, retired with AC-9).

## Acceptance criteria

- **AC-1** A suite with no row in `tools/selftest-cache-inputs.tsv` is always run — cache
  participation is opt-in and fail-closed.
- **AC-2** A row omitting the suite itself, or the script under test, is rejected with a named
  error.
- **AC-3** Breaking a script listed as a declared input of a cached suite makes that suite miss the
  cache and go red on the next run.
- **AC-4** Breaking a script listed in no row still goes red — the always-run suites are
  unaffected.
- **AC-5** Only PASS is recorded; a failed or verdict-less suite writes no marker.
- **AC-6** A run without `--cache-write` never records a pass, so a PR cannot mark its own untested
  content as passing; the workflow passes it only on push-to-`main`.
- **AC-7** The nightly workflow runs the full sweep with the cache bypassed, and reds on any suite
  the cache would have skipped but that fails wholesale. Bypass is the runner's default: with no
  `--cache-dir`, a suite holding a valid marker still runs.
- **AC-10** Every cache skip prints the suite, the key, and the inputs that produced the key.
- **AC-11** `docs/testing.md` documents the cache contract and its four containment properties.
- **AC-12** The rename in D-8 leaves no stale `install-topology.yml` reference behind — `CLAUDE.md`,
  `docs/testing.md` and the `ci.yml` comment point at the renamed workflow.

AC-1 through AC-7 and AC-10 are executable assertions in `tools/run-selftests-selftest.sh`, driving
the real runner against fixture trees — not a manual ritual.

*(AC-8 and AC-9 are retired by the pre-flight ledger; the gaps stay.)*

## Obligations

This work edits a guard (`tools/run-selftests.sh`), so the ordinary mutation obligations apply:
re-baseline the re-keyed generic survivor ordinals in `tools/mutation-baseline.tsv` in the same
diff, and re-anchor any `tools/mutation-catalog.tsv` row addressing them.
