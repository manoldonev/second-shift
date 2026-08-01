# Lean verdict — #299

verdict=approve
run_id: lean299-1785579452
rounds: 2

## Summary

All 9 acceptance criteria verified against the final diff (`cb67129..6478cb0`, 7 files: the
new CI step, four bad fixtures, `tests/issue-forms-selftest.sh`, and the lean spec) by
direct execution, not just reading: installed `check-jsonschema==0.37.4` in a sandbox and
confirmed both `vendor.github-issue-forms`/`vendor.github-issue-config` builtin schema ids
are exposed (AC-1); validated all three real forms + `config.yml` pass their respective
schemas (AC-2); ran the exact CI shell logic and confirmed it passes on real forms and
fails only when a bad fixture is accepted (AC-3); confirmed all four checked-in fixtures
are genuinely rejected by the pinned schema, matching each fixture's own claimed error
(AC-4); exercised the new id-uniqueness and render+required selftest checks by injecting
synthetic regressions and observing them correctly fire (AC-5, AC-6); confirmed `FORMS` is
glob-derived with the explicit `KNOWN_FORMS`/`expect_required` table retained (AC-7);
confirmed the YAML-parser hard-fail block mirrors `scripts/check-workflows-selftest.sh`'s
pattern, verified by hiding both parsers and observing exit 1 instead of a silent pass
(AC-8); confirmed no `tools/mutation-exclusions.tsv`/`tools/mutation-catalog.tsv` row and
no new `scripts/check-*.sh` were added (AC-9). shellcheck, `jq empty`, and actionlint are
clean on the changed files; no frozen release artifact touched; commits carry `Changelog:
none` trailers.

Round 1 flagged one note (confidence 30): the new CI step implicitly relies on `pipx`'s
shim directory being on `PATH` for GitHub Actions' non-login `run:` shell. Fixed in the
last commit by appending to `$GITHUB_PATH` and exporting `PATH` explicitly; round 2
re-verified the fixed script runs correctly end to end.

## Findings

None (round 1's PATH note was fixed before round 2; round 2's one note was a
review-environment artifact — `origin/main` advanced past this branch's merge-base
mid-review from an unrelated concurrent merge — not a defect in this PR's commits).
