# Lean review verdict — second-shift#109

- run_id: 2026-08-01T113009Z-lean109
- issue: 109
- round: 3
- verdict=approve

## Summary

Hardens `statectl.sh`'s `deviations[]` ledger validation per #109's four ACs. AC-1:
Stage-5 checkpoint `deviations[].kind` is now enum-validated at write time
(`validate_stage5_payload`), sharing the closed enum with the existing Stage-7 check
via a new `validate_deviations_kinds` helper (byte-identical to the prior inline
loop) so the two vocabularies cannot drift. AC-2a/AC-2b: `build-checkpoint-7` gains
optional `--affected-files`/`--out-of-scope-files` flags; when the payload carries
the `affectedFiles` key, `validate_stage7_payload` refuses a `changedFiles` entry
absent from both the plan's Affected-files section and `deviations[]` (AC-2a), or
present in the Out-of-scope section without disclosure (AC-2b, distinct sharper
message, checked first for a path matching both conditions). Opt-in on key
presence, not array emptiness, so every pre-#109 caller — including the be-fe-pair
`perRepo` path — is untouched. New `tools/plan-scope-paths.sh` extracts
backtick-quoted path tokens from a named plan section (reusing `plan-lint.sh`
Check 5a's regex verbatim), wired into `stages/7-doc-update.md`'s flat checkpoint
path so real runs are actually gated. AC-3/AC-4: full test coverage
(`statectl-selftest.sh` 269/269, `plan-scope-paths-selftest.sh` 9/9, both including
targeted pass/fail cases per AC) and `state-schema.md` documentation, both
confirmed by round 3.

Two real defects surfaced and were fixed across the three review rounds, both
caught by `lean-review` itself:

- **Round 1 (needs-work):** the worktree branch had forked from `main` before
  commits #320/#321/#322 landed upstream and was never rebased, so the diff would
  have silently reverted three unrelated fixes on merge. Fixed by rebasing onto
  `origin/main` (now based on `d341104`/#323) — confirmed clean, no unrelated files
  in the diff.
- **Round 2 (needs-work):** `plan-scope-paths.sh`'s section-body terminator reused
  `plan-lint.sh`'s heading-EXISTENCE regex (which matches any line starting with
  `**`) as a body-slice terminator, so a bold-lead prose line inside a section body
  (a pattern this repo's own plans already use, e.g. `**D-1.**`/`**Changed:**`)
  silently truncated the extracted path list — undermining AC-2a/AC-2b for exactly
  the writing style already present in this codebase. Fixed by narrowing the
  terminator to a real markdown heading or a STANDALONE bold-line header (the
  whole trimmed line is exactly `**...**`); regression-guard fixture
  (`bold-lead-prose-plan.md`) plus its counterpart proving genuine headers still
  terminate (`standalone-bold-header-plan.md`) both added and passing.

Round 3 confirmed both fixes hold, verified `validate_deviations_kinds`'s
extraction is behavior-preserving, confirmed no frozen release files
(`plugin.json`/`marketplace.json`/`CHANGELOG.md`) are touched, and found zero
remaining findings.

## Findings

None.
