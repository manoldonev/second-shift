# second-shift #583 — survivor ids keyed by CONTENT, not position

Issue: [#583](https://github.com/manoldonev/second-shift/issues/583) — part of #567.
Predecessor: #579 (comment lines stop enumerating as mutation sites), merged as PR #589.

Design: none — this is harness plumbing (`tools/mutation-sweep.sh` and its registers); no
`design.provider` is configured for this repo and the change renders no route.

## Problem

A generic survivor id is `<guard relpath>::<operator id>::<ordinal>`, and the ordinal indexes the
operator's full matched-line list **in file order**. Identity is therefore positional: inserting a
killable line above an existing site renumbers every site below it, so an unrelated edit re-keys
baseline rows. That is why `CLAUDE.md`'s "Test-the-tests" block obliges every guard-editing PR to
re-baseline in the same diff, why #543 could not be resolved (its guard moved to the nightly lane,
so the re-key evidence is not obtainable at PR time), and why blind re-baselining is common enough
to need a standing rule against it.

## Approach

Keep the three-segment wire format `<guard>::<operator>::<key>` — every existing parser
(`${sid%%::*}` in the sweep, the `*::*::*` well-formedness arm in the companion suite) keeps
working — and replace the third segment with a **content key**.

`<key>` is the first 12 hex of a sha256 over:

1. the matched line, **whitespace-normalized**: tabs folded to spaces, internal runs collapsed to
   a single space, leading and trailing whitespace stripped; and
2. the **occurrence index of that line among the operator's matched lines in the same guard that
   normalize to the SAME string** — folded into the hashed input, not appended as a fourth
   segment.

The index counts over the **normalization-identical** class, the same equivalence class the hash
input ranges over. Indexing over the byte-identical class instead would give two lines differing
only in indentation the same index over the same hashed string, hence the same key: 119
normalization-identical duplicate groups against 95 byte-identical ones on the current tree, so 24
groups would collide and AC-6 would red on `main`.

No context window: `git patch-id` is the repo's trusted hashing idiom but hashes a hunk's *context
lines*, which is exactly the sensitivity this change exists to remove.

The index ranges over ALL matched lines, including sites past `K_BUDGET` and sites skipped as
no-op or `bash -n`-invalid — `tools/mutation-operators.tsv` promises that raising `K` re-keys
nothing, and indexing over applied mutants only would break that promise.

## Acceptance criteria

- **AC-1:** WHEN a new killable code site is inserted ABOVE an existing baselined site in a guard
  THEN ZERO baseline rows re-key.
- **AC-2:** WHEN a guard's function block is MOVED without editing its lines — including a move
  that changes its indentation — THEN ZERO baseline rows re-key.
- **AC-3:** WHEN two matched lines of one operator in one guard normalize to the SAME string THEN
  they receive DISTINCT ids, and removing the first re-keys the second and nothing else.
- **AC-4:** WHEN the baseline is migrated THEN it is produced by `--emit-site-keys`, the PR body
  carries the complete old-id → new-id mapping, and the row count before and after is EQUAL — the
  row SET preserved rather than re-derived.
- **AC-5:** WHEN the migration lands THEN the `catalog::<cid>` rows are UNTOUCHED: same ids, same
  notes, byte-identical as a set.
- **AC-6:** WHEN two enumerated sites in one guard+operator resolve to the same 12-hex key THEN
  the sweep REDS by name. The check ranges over ALL enumerated matched lines, including
  beyond-budget and skipped sites — not only emitted sids.
- **AC-7:** WHEN neither `shasum` nor `sha256sum` resolves AND a key must be computed THEN the
  sweep REDS by name. `--mode merge` and a nothing-to-sweep PR run, which compute no keys, stay
  green.
- **AC-8:** WHEN a baseline lacking `# keying: content-v1` is read — in ANY mode, enforcing or
  advisory — THEN it reds as a named keying mismatch, not as a mass of absent-survivor and
  now-killed signals. A shard set whose members disagree on the keying header fails the merge
  header check rather than merging.
- **AC-9:** WHEN the contract surfaces are read THEN the now-false re-key coupling is GONE, not
  stale, at EVERY site that states it: `CLAUDE.md`'s "Test-the-tests" block (whose sentence is
  COMPOUND — the catalog-anchor half stays true and is kept), `tools/mutation-operators.tsv`,
  `docs/testing.md`, `tools/mutation-catalog.tsv`, and `tools/mutation-baseline.tsv`'s footer.
  The enumerated set is a floor, not a ceiling.
- **AC-10:** WHEN `tools/mutation-sweep-selftest.sh` runs THEN cases pin AC-1, AC-2 and AC-3 by
  DIFFERENTIAL assertion — capture the id set from a fixture run, apply the edit, re-run, assert
  the untouched sites' ids are unchanged. The expected key is never computed inside the selftest
  (that would be a mirror harness); the hard-coded positional sids and the `baseline_with` helper
  convert by deriving their fixture's id with `--emit-site-keys`.

## Implementation notes

**`--emit-site-keys`** ships as a MODE of `tools/mutation-sweep.sh`, never as a new `tools/*.sh`
(which would oblige a paired selftest and enter the guard universe). It enumerates and prints
`<guard>\t<operator>\t<ordinal>\t<key>` without scoring anything. It serves two needs: it derives
the migration mapping reproducibly, and it lets a fixture obtain a baseline id with no scoring
run — which is what makes AC-10's ban on capture-and-feed-back implementable.

**The migration is a mechanical transform, not a re-seed.** The key is a pure function of the
guard's bytes plus the operator table, so the mapping is 1:1 and derivable by re-running site
enumeration alone. A `--seed` run would recompute verdicts (dropping rows that have since become
killed, adding flaky ones) and would flatten the hand-written rationale carried by the curated
rows.

**Row order.** The migrated file is written sorted by row, which is what a later seed/merge
already emits — keeping the current order would make the next nightly a pure-churn diff. AC-4's
mapping is the verification path, not the diff.

**Positional prose in preserved notes** is rewritten where it becomes false under content keying,
keeping the rationale. Notes are not deleted and no false sentence is left standing.

**Fail-closed on no SHA binary is LAZY** — fired at the first key computation, not at `SHA_KIND`
resolution, so `--mode merge` and the "PR mode: nothing to sweep" early exit stay green on a host
with neither binary.

**Skip diagnostics** (`skip (bash -n invalid…)`, `skip (no-op flip)`) print the content key too,
so the log carries one id vocabulary.

## Non-goals

- Comment exclusion (predecessor slice, landed in #579).
- `--mode pr`: it STAYS (D-2 — the audit was run and refuted the deletion case).
- The moat: nightly sweep of record, merge boundary, never-self-merge.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
```

Plus a dispatched `mutation-sweep.yml --ref claude/second-shift-583` run: a content-keying change
whose whole point is that ids stay stable must be proven against the real guard corpus, not only
against fixtures.
