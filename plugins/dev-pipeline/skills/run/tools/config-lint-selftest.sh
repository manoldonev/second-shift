#!/usr/bin/env bash
# config-lint-selftest.sh — fixture-driven selftest for config-lint.sh
# Valid fixtures must pass; invalid fixtures must fail AND mention the expected violation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/config-lint.sh"
FIX="$HERE/config-lint-fixtures"
FAILS=0

# One mktemp root for the whole suite. Two cases below need scratch space, and a second
# per-case `trap ... EXIT` would silently REPLACE the first — leaving the earlier dir behind.
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Set only when the modelOverrides lockstep cannot run because its repo-only artifact is
# absent AND this tree is not the monorepo. Consumed at the tail: the suite exits 77 — the
# named, counted skip tools/install-topology-selftest.sh hoists — and it does so ONLY if no
# other assertion failed. A real failure always outranks a skip.
SKIP_REASON=""

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
expect_violation invalid-monorepo-two-id.json       "commands.<id>.lanes / extraLanes"
expect_violation invalid-unknown-repo-and-tier.json "commands keyed by unknown repo ids: ghost"
expect_violation invalid-unknown-repo-and-tier.json "reviewers.modelOverrides.security-reviewer: must be haiku|sonnet|opus|fable"
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
# #107: lintAutofixes:true + a plain `npm run` lint command silently no-ops verifyctl's
# `--fix` suffix (npm swallows it without a `--` separator). valid-lintautofix-npm-withfix.json
# (picked up by the valid-*.json loop above) proves the trailing-`--` escape hatch is accepted.
expect_violation invalid-lintautofix-npm-nofix.json "commands.app.lintAutofixes is true but lint (\"npm run lint\") is a plain \`npm run\` invocation"
expect_violation invalid-configversion-3.json       "configVersion 3 is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)"
expect_violation invalid-configversion-0.json       "configVersion 0 predates this plugin (current: 2) — see docs/migrations/v1-to-v2.md for the upgrade path"
# AC-2: the PRIOR version is the case a real consumer hits at the bump; it must be
# rejected WITH the migration-doc pointer, not a bare "invalid".
expect_violation invalid-configversion-1.json       "configVersion 1 predates this plugin (current: 2) — see docs/migrations/v1-to-v2.md for the upgrade path"
expect_violation invalid-v1-gates-figma.json        'gates.figma was removed in v2 — use design: {"provider": ...} (docs/migrations/v1-to-v2.md)'

# --- stageParams.inertPattern: the two rejection classes need two fixtures, because a
# single key cannot hold both an empty and an uncompilable value. Empty is caught by the
# jq pass; uncompilable is only knowable by asking grep, so it is a separate bash-side
# probe after it. Rejecting at config time is the point: is-inert-diff.sh's fail-closed
# is a safety net that fires mid-run, not a diagnosis.
expect_violation invalid-empty-inertpattern.json    "stageParams.inertPattern: must be non-empty"
expect_violation invalid-bad-inertpattern.json      "stageParams.inertPattern: not a valid extended regular expression"

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
expect_violation invalid-type-gaps.json             "stageParams.webComponentGlobs: must be array"
expect_violation invalid-webcomponentglobs-entry.json "stageParams.webComponentGlobs: every entry must be a string"
# grillWaivers: config-grill's declared opt-outs. valid-grillwaivers.json (picked up by the
# valid-*.json loop above) proves the top-level allowlist accepts the key at all — without that
# entry the whole surface reds as an unknown top-level key, which is the failure mode a
# consumer would hit first. An empty reason is a waiver with no accountability, and a
# non-object is not a waiver map.
expect_violation invalid-grillwaivers.json          "grillWaivers.T2.formatGlob: must be a non-empty reason string"
expect_violation invalid-grillwaivers-type.json     "grillWaivers: must be an object keyed by config-grill check id"

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

# --- #113: commands.<repo>.build was dead (never executed by any verify lane) and is
# now formally retired; ship a build tier via extraLanes instead (see the migration doc).
expect_violation invalid-removed-commands-build.json "commands.<repo>.build was removed"

# --- the modelOverrides tier enum is mirrored in schema/second-shift.config.schema.json
# (config-lint.sh's header declares the two must stay in lockstep). Nothing enforced that
# mirror mechanically, so a one-sided edit was silent — and the enum is exactly the kind of
# thing that gets widened on one side only. Drive BOTH artifacts instead of grepping either:
#   forward  — every tier the SCHEMA declares must be ACCEPTED by config-lint;
#   backward — config-lint's rejection message must name exactly the schema's enum, in order.
# A tier added to config-lint alone fails backward; one added to the schema alone fails forward.
#
# The schema is a REPO artifact and ships inside no plugin, so from a marketplace install it
# is structurally absent and its absence says nothing about drift. Distinguish the two by
# probing the tree INTRINSICALLY — never by an environment variable a harness could export,
# which would drain the signal for the consumer who runs this suite straight from their own
# install, the exact case the skip exists for. The `ROOT=` up-count is this suite's own walk
# to its artifact; the marker test below is byte-shared with the review-toolkit copy
# (scripts/lockstep-manifest.tsv, pair `monorepo-probe`).
ROOT="$HERE/../../../../.."
# LOCKSTEP-BEGIN monorepo-probe
if [[ -f "$ROOT/.claude-plugin/marketplace.json" && -d "$ROOT/plugins" ]]; then
  IN_MONOREPO=1
else
  IN_MONOREPO=0
fi
# LOCKSTEP-END monorepo-probe
SCHEMA="$ROOT/schema/second-shift.config.schema.json"
SCHEMA_Q='.properties.reviewers.properties.modelOverrides.additionalProperties.enum'
if [[ ! -f "$SCHEMA" ]]; then
  if [[ "$IN_MONOREPO" -eq 1 ]]; then
    check "modelOverrides enum mirror: schema readable at $SCHEMA" 1
  else
    SKIP_REASON="SKIP: schema/second-shift.config.schema.json is a repo-only artifact, unreachable from an install — the modelOverrides enum lockstep did not run"
  fi
else
  TIER_TMP="$TMPROOT/tier"
  mkdir -p "$TIER_TMP"
  while IFS= read -r tier; do
    [[ -n "$tier" ]] || continue
    jq -n --arg t "$tier" '{
      configVersion: 2,
      tracker: { type: "github" },
      topology: { type: "standalone", repos: { app: { path: ".", baseBranch: "main" } } },
      commands: { app: {} },
      reviewers: { modelOverrides: { "plan-reviewer": $t } }
    }' > "$TIER_TMP/tier.json"
    if "$LINT" "$TIER_TMP/tier.json" > /dev/null 2>&1; then
      check "schema tier '$tier' accepted by config-lint" 0
    else
      check "schema tier '$tier' accepted by config-lint" 1
    fi
  done < <(jq -r "${SCHEMA_Q}[]" "$SCHEMA")

  # Backward: config-lint's rejection message must enumerate the schema's enum EXACTLY.
  # Compared with `=`, not a grep — the substring form is the same false-green this repo
  # already hit once (the assertion above used to pin a strict PREFIX of the real message,
  # and so pinned nothing). A prefix match here is worse than useless: dropping a tier from the
  # schema alone leaves the schema's shorter list a substring of config-lint's longer one,
  # and the whole mirror check goes silently green in the exact direction it exists to catch.
  EXPECTED_ENUM="$(jq -r "$SCHEMA_Q | join(\"|\")" "$SCHEMA")"
  # `|| true`: the fixture is INVALID by construction, so $LINT exits 1 — and under the
  # file's `set -e` a failing command substitution aborts the whole suite silently (it did,
  # swallowing this check and every line after it until the demo exposed it).
  ACTUAL_ENUM="$(
    { "$LINT" "$FIX/invalid-unknown-repo-and-tier.json" 2>&1 || true; } \
      | sed -n 's/.*reviewers\.modelOverrides\.security-reviewer: must be //p' \
      | head -1 | tr -d '[:space:]'
  )"
  if [[ -n "$ACTUAL_ENUM" && "$ACTUAL_ENUM" == "$EXPECTED_ENUM" ]]; then
    check "modelOverrides enum mirror: config-lint reports exactly the schema's '$EXPECTED_ENUM'" 0
  else
    check "modelOverrides enum mirror: schema says '$EXPECTED_ENUM' but config-lint reports '$ACTUAL_ENUM'" 1
  fi
fi

# missing file → usage error (3), not a lint failure
if "$LINT" "$FIX/does-not-exist.json" > /dev/null 2>&1; then rc=0; else rc=$?; fi
check "missing file exits 3" "$([[ "$rc" -eq 3 ]] && echo 0 || echo 1)"

# --- the skip path must be UNREACHABLE in the monorepo ------------------------------------
# Deleting the schema from the working tree cannot prove that: the deletion would also have to
# survive into whatever tree the probe reads. So FABRICATE one — a root carrying the monorepo
# markers and NOT the artifact, with a copy of this directory at exactly the depth the probe
# walks. The copy must hard-FAIL: an rc that is neither 0 nor 77, and no SKIP line at all.
# The inline guard below stops the inner run re-entering this case. It gates a FIXTURE, never
# the skip discriminator, which stays intrinsic.
if [[ -z "${SECOND_SHIFT_SELFTEST_FABRICATED_TREE:-}" ]]; then
  FAB="$TMPROOT/fab"
  mkdir -p "$FAB/.claude-plugin" "$FAB/plugins/dev-pipeline/skills/run"
  printf '{}\n' > "$FAB/.claude-plugin/marketplace.json"
  cp -R "$HERE" "$FAB/plugins/dev-pipeline/skills/run/tools"
  fab_rc=0
  fab_out="$(SECOND_SHIFT_SELFTEST_FABRICATED_TREE=1 \
    bash "$FAB/plugins/dev-pipeline/skills/run/tools/$(basename "${BASH_SOURCE[0]}")" 2>&1)" || fab_rc=$?
  if [[ "$fab_rc" -ne 0 && "$fab_rc" -ne 77 ]] && ! grep -q '^SKIP: ' <<< "$fab_out"; then
    check "monorepo markers + absent schema still hard-FAILs, never skips (rc=$fab_rc)" 0
  else
    check "monorepo markers + absent schema must hard-FAIL, not skip (rc=$fab_rc, skip line: $(grep -c '^SKIP: ' <<< "$fab_out"))" 1
  fi
fi

if [[ "$FAILS" -gt 0 ]]; then echo "config-lint selftest: $FAILS FAILURE(S)"; exit 1; fi
if [[ -n "$SKIP_REASON" ]]; then
  echo "$SKIP_REASON"
  echo "config-lint selftest: all green apart from the skipped lockstep"
  exit 77
fi
echo "config-lint selftest: all green"
