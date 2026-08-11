# Spec — #493: dogfood gate's milestone-3 lane vs the documented verification contract

## Background

Pre-flight ledger: `.claude/pipeline-state/493-ledger.md`. Every decision below restates a
resolved ledger row; nothing here is new judgment.

The gitignored dogfood config (`.claude/second-shift.config.json`) already carries the fixed
lane out of band (D-8):

```
SKIP_STRESS=1 bash tools/run-selftests.sh --jobs 10 --exclude tools/install-topology-selftest.sh
```

That resolves D-1 through D-5: no `install-topology-selftest.sh` at PR time, the checked-in
runner instead of a hand-rolled `find | xargs`, `SKIP_STRESS=1` kept, `--jobs 10` concurrency,
cold (no `--cache-dir`). This ticket's own milestone 3 exercises that lane and is the evidence
for all five (D-10).

What remains is the PR itself: a written referent (D-6) plus two stale prose corrections (D-7).
Docs-only — no code seam, no test surface (D-10).

## Scope

- AC-1: `CLAUDE.md`'s Verification section records that this repo's own dogfood lean-gate
  milestone-3 `test` lane invokes the same `tools/run-selftests.sh` runner described there —
  not a hand-rolled pipeline — so the gitignored config and the documented contract are no
  longer silently comparable-but-uncompared (D-6).
- AC-2: `.github/workflows/ci.yml`'s comment near line 99 stops asserting
  `install-topology-selftest.sh` "runs in its own job below" — no such job exists in `ci.yml`;
  it runs nightly in `nightly-guards.yml` (D-7).
- AC-3: `docs/testing.md`'s paragraph near line 44 stops asserting `--exclude` "exists for one
  caller ... which runs in its own job on both lanes" — it now has four callers
  (`ci.yml:119`, `ci.yml:394`, `nightly-guards.yml:100`, `nightly-guards.yml:116`) and the
  suite runs nightly, not in a same-lane job (D-7).

## Out of scope

- No `commands.second-shift.*` config edit — already applied out of band, ahead of this run
  (D-8; verified present before milestone 1).
- No new script, check, or `config-lint` rule comparing the dogfood config against CLAUDE.md
  (D-6 rejects both a repo-carried checker, which can't run against a gitignored file it can't
  see, and a generic content rule, which is a false-positive-prone heuristic for one machine's
  config).
- No onboarding/template change (D-9 — closed, not deferred: `detect.sh` never emits this
  string for a shell repo).
- OR-1 (whether any *other* dogfood config lane has drifted) stays open at its stated default:
  not audited, not changed.

## Verification

Docs-only; no code seam or guard is owed (D-10). Evidence is this run's own milestone-3 log
under the lane already in place (D-8), plus milestone 2 (shellcheck / jq) and review reading
the three prose edits directly.
