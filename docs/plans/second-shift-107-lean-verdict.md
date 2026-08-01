# Issue #107 — lean review verdict

milestone-4 | verdict=approve | round=1

- verdict=approve
- round=1
- run_id: run107-0f62506
- base..head: origin/main..87af341a3ccb55b9772e9f715c079fe83f6e5af

## Summary

Both AC-1 (detect.sh broadened be/fe sibling scan) and AC-2 (config-lint.sh flags
lintAutofixes+non-forwarding npm-run) are implemented exactly as specified, with new
fixtures/selftest cases that pass (detect-selftest.sh and config-lint-selftest.sh both
green). Traced the control flow by hand: has_suffix/COUNTERPART_SUFFIXES logic is
bash-3.2-safe, correctly classifies BE vs FE basenames, skips self-match, dedupes via jq
index(), and leaves the pre-existing same-base-name loop untouched (verified case 3
shop-api/shop-ui still passes). config-lint's npm_no_fix_forward guard matches the AC's
literal "ends with --" definition and the emitted message names repo, command, and both
remediation options verbatim per AC-2. Shellcheck clean on all 4 changed .sh files; both
changed JSON fixtures are valid JSON. No frozen release files (plugin.json/marketplace.json/
CHANGELOG.md) touched. Commit carries a Changelog: trailer and uses the honest `fix:` verb
(bug-fix, matches CLAUDE.md's bump table). PR-scoped mutation sweep shows every surviving
mutant on both changed files maps 1:1 to a pre-existing baseline or catalog row — no new
un-baselined survivors from this diff, i.e. the new code paths are actually killed by the
new tests, not just superficially covered.

## Findings

- **note** (confidence 35) — `plugins/dev-pipeline/skills/run/tools/config-lint.sh:26`:
  `npm_no_fix_forward` can false-positive on a lint command that already has a `--`
  separator earlier but not at the very end (e.g. `"npm run lint -- --max-warnings=0"`).
  This matches AC-2's literal wording exactly ("does not already end with a `--` separator
  (trimmed)"), so it is spec-compliant, not a defect against the committed AC. No action
  required for this AC; a follow-up AC could loosen the check if it bites a real consumer
  config.
