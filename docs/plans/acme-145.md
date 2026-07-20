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
- The exit-code contract (`exit $fails`, "exit code = number of FAILED checks") stays. Vacuous coverage becomes a *fail*, so no new exit semantics are invented.
- `.claude/` is an acceptable home for a committed per-repo artifact — established by `second-shift.lock.json` and `settings.json` being tracked there, with `second-shift.config.json` and `pipeline-state/` selectively gitignored.
- `commands.second-shift.unitTestScope` is `null`, so there is no mutation-test surface; the unit-test gate classifies as `skip`.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Scan roots discover both the consumer layout and the plugin-repo layout, additively | codebase-derived | `.claude/skills`/`.claude/agents` absent here; 103 files live under `plugins/*/{skills,agents}`. Additive keeps existing consumers working (AC-4). |
| D-2 | Baseline resolves repo-local first, plugin copy as fallback stub; `--update-baseline` writes repo-local | codebase-derived | The shipped TSV must stay a neutral stub or consumers inherit this repo's paths. `.claude/` already holds committed per-repo artifacts. |
| D-3 | Vacuous coverage is a hard fail with a distinct marker; a reverse pass also reports unresolvable baseline rows | codebase-derived | A 0-match-only check still lets a partial layout move pass. Same mechanism covers both, so this is not scope creep. |
| D-4 | Ship `prose-budget-selftest.sh` | codebase-derived | CLAUDE.md requires every checked-in script pair with one; its absence is why a gate measuring nothing shipped undetected. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — scan-root discovery, baseline resolution, vacuous/stale gate
- `plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv` — stays a neutral stub; header corrected to describe the repo-local destination
- `plugins/dev-pipeline/skills/run/tools/prose-budget-selftest.sh` `[NEW]` — CI-discovered selftest
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — check 7 distinguishes vacuous from growth; drops the stale `.claude/skills/run/tools/` remediation path
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
4. **Vacuous-coverage gate** — after the scan loop, if the tracked-file count is 0, print a distinct `FAIL vacuous coverage:` line naming the roots searched, and increment `fails`.
5. **Stale-row reverse pass** — iterate baseline rows; report each whose path does not resolve on disk. All rows unresolvable ⇒ counts as a fail (a stub baseline against a real inventory); some unresolvable ⇒ warning.
6. **Correct the stub header** to describe the repo-local destination instead of instructing a write into the plugin cache.
7. **Regenerate this repo's baseline** to `.claude/prose-budget.baseline.tsv` via `--update-baseline`, and commit it.
8. **Write `prose-budget-selftest.sh`** covering AC-1..AC-4 (see Test strategy).
9. **Update `pipeline-doctor.sh`** check 7 to branch on the vacuous marker with its own message, and replace the stale `.claude/skills/run/tools/` path with `$SCRIPT_DIR`.

## Test strategy

Verify-after (infra/tooling change; no application behavior). The selftest is the mechanical guard and is the deliverable that keeps the fix from regressing.

`prose-budget-selftest.sh` builds throwaway git repos under `mktemp -d` and drives `prose-budget.sh` against them via the `PROSE_ROOTS` seam and real on-disk fixtures:

- **T1 (AC-2)** repo with no instruction layer ⇒ exit non-zero **and** stdout carries the vacuous marker.
- **T2 (AC-4)** repo with `.claude/skills/x.md` ⇒ that file appears in the table; no regression for the consumer layout.
- **T3 (AC-1)** repo with `plugins/foo/agents/y.md` ⇒ that file appears in the table.
- **T4 (AC-3)** baseline containing a row whose path does not exist ⇒ the stale row is reported.
- **T5** file grown past `PROSE_TOLERANCE_PCT` over its baseline ⇒ `FAIL grew`, exit non-zero (guards the pre-existing ratchet against regression).
- **T6 (AC-5)** `--update-baseline` writes `<repo>/.claude/prose-budget.baseline.tsv`, not the plugin copy.
- **T7** drift check: `prose-budget.sh` still carries the load-bearing tokens (`vacuous coverage`, `prose_roots`) and `pipeline-doctor.sh` still branches on the marker — mirrors `claim-selftest.sh`'s parity tail.

`SKIP_STRESS=1` is honored (no stress tier here; the flag is accepted and ignored) so the CI glob invocation works unchanged.

Unit test surface: **skip** — `unitTestScope` is `null` for this repo; shell tooling with no mutation surface.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Inspects >0 files in this repo | 2 | T3; `prose-budget.sh` run in Verification |
| AC-2 | Empty tracked set ⇒ distinct failure, non-zero exit | 4 | T1 |
| AC-3 | Unresolvable baseline row reported as stale | 5 | T4 |
| AC-4 | `.claude/{skills,agents}` still scanned — no regression | 2 | T2 |
| AC-5 | Pairs with a CI-discovered selftest | 8 | T6 (and CI glob discovery itself) |

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
- Rollback: revert the commit. The repo-local baseline is additive; the stub falls back cleanly.

## Out-of-scope

- Promoting prose-budget from a doctor WARN to a blocking pre-flight check.
- Retro-fitting repo-local baselines into other consumer repos (they regenerate on their own next run).
- Any change to the narrative-`#NNN` detector or the tolerance default.
- Reducing actual instruction-layer prose size — this ticket makes the gate measure; it does not act on what it measures.

Unverified references: none — every path and function above was confirmed by read/grep against `origin/main`.
