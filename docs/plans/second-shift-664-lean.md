# second-shift #664 — pipeline-doctor-selftest reds from the staged install cache

Issue: [#664](https://github.com/manoldonev/second-shift/issues/664)

## Problem

`nightly-guards.yml`'s `install-topology-selftest.sh` run has been red on both lanes for its
last 7 runs (through 2026-08-24), reporting:

```
RED: plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh — rc=1 —
ok: (d3) completed + failed at 24h → never stale (terminal by contract)
```

The suite is green in-repo at the same heads. That is the exact class the install-topology
guard exists to catch: a shipped suite that borrows its authoring checkout's layout.

## Root cause (reproduced 2026-08-30)

Staging the cache by hand — `plugins/*` copied to `<cache>/<plugin>/<version>/`, run from a
`git init`'d consumer cwd — reproduces `rc=1`. The failing case is **not** `(d3)`:

```
FAIL: (inv/sibling) pipeline-doctor delegates to selftest(s) that do not exist:
  intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh
  review-toolkit/scripts/check-model-tiers-selftest.sh
  review-toolkit/scripts/check-reviewer-references-selftest.sh
  — the invocation outlived its subject
```

The `(d3)` line in the nightly log is an artifact of how install-topology composes its `detail`
string: `grep -iE 'FAIL|error|No such|not found' "$log" | head -1`. The case text
"completed + **fail**ed at 24h" matches `FAIL` case-insensitively, so the *first* matching line
in the log is a passing `ok:` line and the real `FAIL:` line 37 lines below it is never shown.

**The divergence.** `pipeline-doctor-selftest.sh`'s `inv_scan()` sibling arm resolves a
delegated sibling-plugin selftest by joining paths directly:

```bash
sibling) plug="${hit%% *}"; rel="${hit#* }"; hit="$plug/$rel"
         base="$PLUGINS_ROOT/$plug/$rel" ;;
```

`$PLUGINS_ROOT` is `<doctor>/../..`. That join is **rung 1 of the ladder and nothing else** —
the monorepo path `plugins/<sib>/<rel>`, which exists only in this checkout. Under a
version-keyed install cache the sibling lives at `<cacheroot>/<sib>/<ver>/<rel>`, with a
version segment the join does not know about, so every sibling delegation reads as deleted.

The production code the arm is guarding does **not** make that assumption: `pipeline-doctor.sh`
reaches its three sibling delegations through `resolve_sibling` (`resolve-sibling.sh`), whose
whole purpose is the three-rung ladder — monorepo path, then this plugin's own version in the
cache, then the newest sibling version carrying the file. The guard re-derived a rung-1-only
answer instead of asking the ladder, so it disagreed with production the moment the layout
stopped being the monorepo one. The other two arms (`script`, `plugin`) resolve relative to the
doctor's own file and are correct under both layouts; only `sibling` crosses a plugin boundary.

Nothing about time or the 24h staleness contract is involved.

## Acceptance Criteria

- **AC-1** — The root cause is named in this document with the failing case (`(inv/sibling)`)
  and the staged-vs-repo divergence cited: the sibling arm's `$PLUGINS_ROOT/$plug/$rel` join is
  rung 1 of the ladder only, while the production delegation it guards goes through
  `resolve_sibling`.
- **AC-2** — `bash tools/install-topology-selftest.sh` passes locally, with
  `plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh` among its passes and 0 red.
- **AC-3** — The regression class is guarded by a case in `pipeline-doctor-selftest.sh` that
  runs in the ordinary in-repo sweep and **fails under the pre-fix code**: it drives the real
  `inv_scan` sibling arm against a fabricated version-keyed cache, where the pre-fix path join
  structurally cannot resolve. It is paired with a control asserting that a delegation staged
  nowhere is still reported missing under that same layout, so the case cannot pass vacuously.
- **AC-4** — The fix resolves the sibling arm through the **production** ladder
  (`resolve-sibling.sh`'s sentinel-delimited block, executed — not a hand-copied predicate),
  so the guard and the code it guards cannot disagree about layout again.
- **AC-5** — `install-topology-selftest.sh`'s red `detail` line names the suite's own failure
  line rather than the first line that merely contains the substring "fail". A red from this
  guard must point at the failing case. *(Added during build: this is what made the nightly red
  undiagnosable from its own log — the ticket flags the oddity explicitly, and a class guard
  whose red names a passing case sends the next reader to the wrong assertion.)*
- **AC-6** — AC-5's path is guarded by an executing test, not left to the next red to discover.
  It is dead code on every green run — it executes only once a staged suite has already failed,
  which is exactly why a broken composition survived seven nightly runs — so it is
  sentinel-delimited and driven against fixture logs, including the `ok: … failed …` decoy that
  produced the misleading line. The guard does not inherit install-topology's staging cost.
- **AC-7** — `docs/testing.md`'s install-topology section is corrected. Its standing claim that
  the class guard "is the reason no new instance of this needs its own test" is what this
  ticket disproves in part: the guard detected the defect on every one of the seven nightly
  runs, but it runs nightly-only since #620 and its red named a passing case, so neither
  detection-on-the-branch nor diagnosability followed from it.
- **AC-8** — `Changelog:` trailer present per repo convention.

## Non-goals

- No change to `pipeline-doctor.sh` itself. The production resolution was always correct; the
  guard was the thing that disagreed with it.
- No change to the nightly schedule or to install-topology's staging topology.

## Decision Ledger

No pre-flight ledger was produced for this ticket; no `user-answered` / `user-delegated` rows to
carry forward.

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Fix the guard or fix the packaging? | Fix the guard. The shipped layout is correct and production resolves through it; the suite's rung-1-only join was the defect. | codebase-derived |
| D-2 | Where does the class guard live? | A case inside `pipeline-doctor-selftest.sh` that fabricates the cache layout, following the `(rs1)`/`(rs3)` precedent in the same file — so the defect reds at PR time in the ordinary sweep, not only in the nightly install-topology run. | codebase-derived |
