#!/usr/bin/env bash
# config-lint-selftest.sh — fixture-driven selftest for config-lint.sh
# Valid fixtures must pass; invalid fixtures must fail AND mention the expected violation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/config-lint.sh"
FIX="$HERE/config-lint-fixtures"
FAILS=0

check() { # $1 = label, $2 = expectation result (0 ok / 1 fail)
  if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS + 1)); fi
}

echo "config-lint selftest:"

for f in "$FIX"/valid-*.json; do
  if "$LINT" "$f" > /dev/null 2>&1; then check "$(basename "$f") passes" 0; else check "$(basename "$f") passes" 1; fi
done

expect_violation() { # $1 = fixture, $2 = expected substring in error output
  local out
  if out=$("$LINT" "$FIX/$1" 2>&1); then
    check "$1 fails" 1
  elif grep -qF "$2" <<< "$out"; then
    check "$1 fails mentioning '$2'" 0
  else
    check "$1 fails mentioning '$2' (got: $(head -3 <<< "$out" | tr '\n' ' '))" 1
  fi
}

expect_violation invalid-bad-tracker.json           "tracker.type must be github|jira"
expect_violation invalid-pair-missing-fe.json       "be-fe-pair requires repos.be and repos.fe"
expect_violation invalid-unknown-repo-and-tier.json "commands keyed by unknown repo ids: ghost"
expect_violation invalid-unknown-repo-and-tier.json "reviewers.modelOverrides.security-reviewer: must be haiku|sonnet|opus"
expect_violation invalid-tracker-unknown-key.json   "tracker: unknown keys"
expect_violation invalid-bot-app-unknown-key.json   "tracker.bot.app: unknown keys"
expect_violation invalid-bad-design-provider.json   "design.provider must be figma|claude-design"
expect_violation invalid-bad-liverender.json        "design.liveRender: unknown keys"
expect_violation invalid-bad-liverender.json        "design.liveRender.command: required"
expect_violation invalid-bad-liverender.json        "design.liveRender.cwd: not a topology.repos id"
expect_violation invalid-bad-viewport.json          "stageParams.visualCapture.viewports must be a subset"
expect_violation invalid-bad-extralane.json         "extraLanes[0].failureClass: must be a closed failure-taxonomy value"
expect_violation invalid-bad-stageworkflow.json     "stageWorkflows[0].stage: must be an integer 1-10"
expect_violation invalid-bad-plangate.json          "planGates[0].agent: required"
expect_violation invalid-configversion-2.json       "configVersion 2 is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)"
expect_violation invalid-configversion-0.json       "configVersion 0 predates this plugin — see docs/migrations/ for the upgrade path"
expect_violation invalid-v1-gates-figma.json        'gates.figma was removed in v2 — use design: {"provider": ...} (docs/migrations/v1-to-v2.md)'

# --- #15: the 12 config-lint type-check gaps (F83 mutant matrix). One packed fixture,
# one assertion per surviving-mutant class it must now KILL. Plus the removed-key notes.
expect_violation invalid-type-gaps.json             "stageWorkflows[0].stage: must be an integer 1-10"
expect_violation invalid-type-gaps.json             "stageParams.visualCapture.smokeRoutes: must be array"
expect_violation invalid-type-gaps.json             "stageParams.visualCapture.baseUrl: must be string"
expect_violation invalid-type-gaps.json             "reviewers.remove: must be array"
expect_violation invalid-type-gaps.json             "commands.host.extraLanes[0].when: must be array"
expect_violation invalid-type-gaps.json             "paths.plansDir: must be string"
expect_violation invalid-type-gaps.json             "implementDelegates[0].surface: must be string"
expect_violation invalid-type-gaps.json             "planGates[0].surface: must be string"
expect_violation invalid-type-gaps.json             "commands.host.lanes[0].cwd: must be string"
expect_violation invalid-type-gaps.json             "commands.host.lanes[0].commands: must be array"
expect_violation invalid-type-gaps.json             "commands.host.lanes[1].commands: at least one required when present"
expect_violation invalid-type-gaps.json             "tracker.bot.enabled: must be boolean"
expect_violation invalid-type-gaps.json             "stageParams.requiredLabels: every entry must be a string"

# --- #100: a non-object lanes[]/extraLanes[] entry must be a CLEAN violation.
# Before the entry-shape guard, a string/number/array lane lint-clean-passed
# (jq's right-to-left `+` and `.name?`-on-a-string yielding `empty` collapsed the
# whole chain), and verifyctl then silently skipped it — a false green. `null`
# and a non-object extraLane crashed jq with rc=5 instead of reporting. Every
# non-object type must now name the required shape. The trailing well-formed
# lane in the fixture proves the guard is per-entry, not a whole-block abort.
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[0]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[1]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[2]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[3]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.extraLanes[0]: must be an object"

# --- #15: the two removed dead keys must be rejected with a migration note.
expect_violation invalid-removed-commands-tiers.json "integrationTest/apiTest were removed in v2.1.6"
expect_violation invalid-removed-gates-costtracking.json "gates.costTracking was removed in v2.1.6"

# missing file → usage error (3), not a lint failure
if "$LINT" "$FIX/does-not-exist.json" > /dev/null 2>&1; then rc=0; else rc=$?; fi
check "missing file exits 3" "$([[ "$rc" -eq 3 ]] && echo 0 || echo 1)"

if [[ "$FAILS" -gt 0 ]]; then echo "config-lint selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-lint selftest: all green"
