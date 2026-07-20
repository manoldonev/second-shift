# Plan — #145: prose-budget.sh matches 0 files and reports a vacuous green

## Context / problem framing

`plugins/dev-pipeline/skills/run/tools/prose-budget.sh` is the instruction-layer bloat ratchet, wired into `pipeline-doctor.sh` as check 7. In this repo it inspects **zero** files, reports `0 fail(s), 0 warning(s)`, and exits 0. The gate cannot fail.

The issue attributes this to a stale baseline. That is only half the cause. `prose-budget.sh:37-39`:

```sh
tracked_files() {
  find .claude/skills .claude/agents -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
}
```

The scan roots are **literals**, fixed to the pre-de-vendoring layout. Neither directory exists in this repo — `.claude/` holds only `tools/`, `settings.json`, `second-shift.lock.json`, `SECOND-SHIFT.md` — and `2>/dev/null` swallows `find`'s missing-directory error. The real instruction layer is 103 files: 37 under `plugins/*/agents/`, 66 under `plugins/*/skills/`.

Two consequences the issue does not draw:

1. **The issue's fix #1 is not independently viable.** `--update-baseline` regenerates from `tracked_files()`. With the roots unfixed it writes an *empty* baseline and cements the false green.
2. **The baseline has no correct destination.** `BASELINE` resolves script-relative inside the plugin (`prose-budget.sh:23-24`) and `--update-baseline` writes back to that same shipped file. Writing this repo's real inventory there hands every consumer a baseline of `plugins/dev-pipeline/...` paths that do not exist in their repo — recreating this exact bug downstream. Yet the stub's own header instructs consumers to "Run `prose-budget.sh --update-baseline` in your consumer repo", which for an installed plugin means writing into the read-only plugin cache.

This is a silently-passing gate: the failure mode is indistinguishable from success. The fix must make *measuring nothing* loud, not merely re-point the data.

## Assumptions

- second-shift is both the plugin repo and its own consumer (the dogfooding canary), so `prose-budget.sh` must work under **both** layouts, not be switched from one to the other.
- A **de-vendored marketplace consumer** legitimately has *no local instruction layer at all* — its skills and agents live in the plugin cache, not in the repo. "Nothing to measure" is the correct steady state there, not a defect. This is the distinction the first draft of this plan missed.
- The exit-code contract (`exit $fails`, "exit code = number of FAILED checks") stays. Vacuous coverage becomes a *fail*, so no new exit semantics are invented.
- `.claude/` is an acceptable home for a committed per-repo artifact — established by `second-shift.lock.json` and `settings.json` being tracked there, with `second-shift.config.json` and `pipeline-state/` selectively gitignored.
- `commands.second-shift.unitTestScope` is `null`, so there is no mutation-test surface; the unit-test gate classifies as `skip`.

## The failure the gate must not introduce

A check that fires permanently with no achievable remediation is the mirror image of the bug being fixed: a false red is as useless as a false green, and worse for trust. So "0 files matched" is **not** by itself a failure. The gate distinguishes three states:

| State | Condition | Outcome |
| --- | --- | --- |
| **n/a** | No instruction-layer root exists on disk | Report `n/a`, exit 0 — the de-vendored consumer's correct steady state |
| **vacuous** | A root exists but matched 0 markdown files | `FAIL vacuous coverage` — the #145 signature |
| **measured** | Roots and files present | Normal ratchet |

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Scan roots discover both the consumer layout and the plugin-repo layout, additively | codebase-derived | `.claude/skills`/`.claude/agents` absent here; 103 files live under `plugins/*/{skills,agents}`. Additive keeps existing consumers working (AC-4). |
| D-2 | Baseline resolves repo-local first, plugin copy as fallback stub; `--update-baseline` writes repo-local | codebase-derived | The shipped TSV must stay a neutral stub or consumers inherit this repo's paths. `.claude/` already holds committed per-repo artifacts. |
| D-3 | Vacuous coverage is a hard fail with a distinct marker | codebase-derived | The issue's item 2 states the requirement directly; `exit $fails` already carries fail semantics, so no new contract is invented. |
| D-4 | Ship `prose-budget-selftest.sh` | codebase-derived | CLAUDE.md requires every checked-in script pair with one; its absence is why a gate measuring nothing shipped undetected. |
| D-5 | A repo with **no** instruction-layer root reports `n/a` and exits 0 — only a root that exists but matches nothing fails | codebase-derived | The marketplace consumer model means a de-vendored repo has no local instruction layer by design. Failing there would be unremediable. |
| D-6 | The shipped stub is emptied to header-only; staleness checks apply **only** to a repo-local baseline | codebase-derived | The stub currently carries 18 concrete `.claude/agents/*` rows — not neutral. Left as-is it would trip the staleness rule in every consumer that falls back to it. |
| D-7 | Staleness scope: report unresolvable rows; fail only when a repo-local baseline has rows and **none** resolve while files were tracked | deferred | The partial-staleness *threshold* is a judgment call the pipeline cannot ground. The all-unresolvable case is the #145 signature and is unambiguous; a ratio-based threshold is left to a follow-up. |
| D-8 | `--update-baseline` refuses to write an empty baseline unless `PROSE_ALLOW_EMPTY_BASELINE=1` | codebase-derived | Closes the plan's own diagnosed failure: regenerating against unfixed roots cements the false green. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — scan-root discovery, baseline resolution, n/a-vs-vacuous gate, stale-row pass, `--update-baseline` guard
- `plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv` — emptied to header-only (the 18 pre-de-vendoring rows removed); header rewritten to describe the repo-local destination
- `plugins/dev-pipeline/skills/run/tools/prose-budget-selftest.sh` `[NEW]` — CI-discovered selftest
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — check 7 distinguishes vacuous from growth; drops the stale `.claude/skills/run/tools/` remediation path
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh` — fixture at line 67 cites the pre-de-vendoring baseline path; retarget to `.claude/prose-budget.baseline.tsv`
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` — the inert-`.tsv` rationale at line 62 cites the same stale path; same retarget. The inert rule itself is unaffected — the new path is still a `.tsv` under `.claude/`.
- `.claude/prose-budget.baseline.tsv` `[NEW]` — this repo's real baseline (committed)

## Reuse inventory

- `tracked_files()`, `words_of()`, `chars_of()`, `narrative_nnn()` — existing helpers in `prose-budget.sh`; extended, not replaced.
- `pipeline-doctor.sh`'s `ok()` / `warn()` helpers — reused for the new vacuous branch.
- Selftest harness idiom (`PASS`/`FAIL` counters, `ok()`/`bad()`, `mktemp -d` + `trap`) — mirrored from `claim-selftest.sh`; no new helper introduced.
- New helpers introduced: `prose_roots()` `[NEW]` in `prose-budget.sh` (root discovery; no existing equivalent — confirmed by grep for `roots`/`find .claude` across `tools/`).

## Implementation steps

1. **Reorder resolution** in `prose-budget.sh` so `REPO` is resolved before `BASELINE` (the repo-local path depends on it).
2. **Add `prose_roots()`** — emits each existing dir among `.claude/skills`, `.claude/agents`, `plugins/*/skills`, `plugins/*/agents`; honors a `PROSE_ROOTS` env override (the selftest's seam). Rewrite `tracked_files()` to consume it and return cleanly on an empty root set.
3. **Baseline resolution** — `REPO_BASELINE="$REPO/.claude/prose-budget.baseline.tsv"`, `STUB_BASELINE="$SCRIPT_DIR/prose-budget.baseline.tsv"`; read from the repo-local one when present, else the stub. `--update-baseline` always writes `REPO_BASELINE` (creating `.claude/` if needed) and reports the destination.
4. **Three-state coverage gate** — after the scan loop:
   - no root existed ⇒ print `n/a — no instruction layer found (roots searched: …)`, do **not** increment `fails`, exit 0;
   - a root existed but 0 files matched ⇒ print the distinct `FAIL vacuous coverage:` line naming the roots, increment `fails`.
5. **Stale-row reverse pass, scoped to a repo-local baseline.** Iterate its rows and report each path that does not resolve. If the repo-local baseline has rows, files *were* tracked, and **no** row resolves ⇒ fail (the #145 signature). Some unresolvable ⇒ warning. When the fallback stub is in use, this pass does not run at all — instead print a one-line notice to run `--update-baseline`. Never a fail.
6. **Empty the stub** to header-only and rewrite the header to name the repo-local destination instead of instructing a write into the plugin cache.
7. **Guard `--update-baseline`** — refuse to write when the tracked set is empty (non-zero exit, explanatory message) unless `PROSE_ALLOW_EMPTY_BASELINE=1`.
8. **Regenerate this repo's baseline** to `.claude/prose-budget.baseline.tsv`, and commit it.
9. **Write `prose-budget-selftest.sh`** covering AC-1..AC-6 (see Test strategy).
10. **Update `pipeline-doctor.sh`** check 7 to branch on the vacuous marker with its own message, and replace the stale `.claude/skills/run/tools/` path with `$SCRIPT_DIR`.
11. **Retarget the two stale path references** in `is-inert-diff-selftest.sh:67` and `stages/6-verify.md:62`.

Every commit touching `plugins/**` carries a `Changelog:` trailer (CI-enforced by `scripts/check-changelog-trailer.sh`). No version bump and no `CHANGELOG.md` edit — those are release-derived and rejected in a feature PR by `scripts/check-frozen-files.sh`.

## Test strategy

Verify-after (infra/tooling change; no application behavior). The selftest is the mechanical guard and is the deliverable that keeps the fix from regressing.

`prose-budget-selftest.sh` builds throwaway git repos under `mktemp -d` and drives `prose-budget.sh` against them via the `PROSE_ROOTS` seam and real on-disk fixtures:

- **T1 (AC-2)** repo where a root exists but holds no markdown ⇒ exit non-zero **and** stdout carries the vacuous marker.
- **T2 (AC-4)** repo with `.claude/skills/x.md` ⇒ that file appears in the table; no regression for the consumer layout.
- **T3 (AC-1)** repo with `plugins/foo/agents/y.md` ⇒ that file appears in the table.
- **T4 (AC-3)** repo-local baseline containing a row whose path does not exist ⇒ the stale row is reported.
- **T5** file grown past `PROSE_TOLERANCE_PCT` over its baseline ⇒ `FAIL grew`, exit non-zero (guards the pre-existing ratchet against regression).
- **T6 (AC-5)** `--update-baseline` writes `<repo>/.claude/prose-budget.baseline.tsv`, not the plugin copy.
- **T7 (AC-6, negative)** repo with **no** instruction-layer root at all ⇒ exit **0** and stdout reports `n/a`, with no vacuous marker. This is the de-vendored-consumer case; it must not fail.
- **T8** falling back to the shipped stub ⇒ no staleness fail, and the stub itself has zero rows.
- **T9** `--update-baseline` against an empty tracked set ⇒ refuses, exits non-zero, leaves any existing baseline untouched.
- **T10** drift check: `prose-budget.sh` still carries the load-bearing tokens (`vacuous coverage`, `prose_roots`) and `pipeline-doctor.sh` still branches on the marker — mirrors `claim-selftest.sh`'s parity tail.

`SKIP_STRESS=1` is honored (no stress tier here; the flag is accepted and ignored) so the CI glob invocation works unchanged.

Unit test surface: **skip** — `unitTestScope` is `null` for this repo; shell tooling with no mutation surface.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Inspects >0 files in this repo | 2 | T3; `prose-budget.sh` run in Verification |
| AC-2 | Root exists but matched nothing ⇒ distinct failure, non-zero exit | 4 | T1 |
| AC-3 | Unresolvable baseline row reported as stale | 5 | T4 |
| AC-4 | `.claude/{skills,agents}` still scanned — no regression | 2 | T2 |
| AC-5 | Pairs with a CI-discovered selftest | 9 | T6 (and CI glob discovery itself) |
| AC-6 | A repo with no instruction layer at all does **not** fail | 4 | T7 |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# the gate itself, now non-vacuous:
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh; echo "exit=$?"
```

## Risks / rollback notes

- **The regenerated baseline instantly makes the ratchet real.** Any instruction file already over its (previously unmeasured) size is now measured — but the baseline is a snapshot of *current* sizes, so the first run after regeneration is green by construction. Growth from here is what fails.
- **Unquoted root expansion.** `find $roots` requires word-splitting; guarded with an explicit `shellcheck disable=SC2086` and a non-empty check rather than an array (macOS bash 3.2 compatibility, per the script's existing constraint comment).
- **Doctor stays WARN-only** for prose-budget by design (`FAILS` is not incremented) — this change does not promote it to an environment blocker; it only makes the message honest.
- **False-red risk is the one this plan takes seriously.** The n/a state (D-5) and the stub-scoped staleness rule (D-6) exist specifically so no consumer inherits an unremediable failure. T7 and T8 are the regression guards; if either is weakened, the gate becomes worse than the bug it replaces.
- Rollback: revert the commit. The repo-local baseline is additive; the stub falls back cleanly.

## Out-of-scope

- Promoting prose-budget from a doctor WARN to a blocking pre-flight check.
- Measuring `plugins/*/templates` and `plugins/*/evals` markdown. They sit outside the skills/agents trees and are not context-loaded instruction prose; bringing them in is a scope question for a separate ticket, not a silent widening here.
- Acting on what the gate now reports. It measures 71 files / ~158k tokens; reducing that number is the L2 debloat work this ratchet exists to enable, not part of making the ratchet honest.
- Retro-fitting repo-local baselines into other consumer repos (they regenerate on their own next run).
- Any change to the narrative-`#NNN` detector or the tolerance default.
- Reducing actual instruction-layer prose size — this ticket makes the gate measure; it does not act on what it measures.

Unverified references: none — every path and function above was confirmed by read/grep against `origin/main`.
