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

# The negative form. A retired top-level key is rejected by NAME, and the generic
# "unknown top-level keys" must stay silent on it — an assertion expect_violation cannot
# make, since both messages come out of the same failing run and grep would find either.
expect_no_violation() { # $1 = fixture, $2 = substring that must NOT appear
  local out
  out=$("$LINT" "$FIX/$1" 2>&1) || true
  if grep -qF "$2" <<< "$out"; then
    check "$1 does NOT also say '$2' (got: $(head -3 <<< "$out" | tr '\n' ' '))" 1
  else
    check "$1 does NOT also say '$2'" 0
  fi
}

expect_violation invalid-bad-tracker.json           "tracker.type must be github|jira"
expect_violation invalid-pair-missing-fe.json       "be-fe-pair requires repos.be and repos.fe"
expect_violation invalid-monorepo-two-id.json       "commands.<id>.lanes / extraLanes"
expect_violation invalid-unknown-repo-and-tier.json "commands keyed by unknown repo ids: ghost"
expect_violation invalid-unknown-repo-and-tier.json "reviewers.modelOverrides.security-reviewer: must name a dispatch model (haiku, sonnet, opus, fable) or a tier in the effective tierMap"
# --- #351. The schema half of modelOverrides degraded to a bare string (the legal set is a
# cross-field union it cannot express), so config-lint is now the ONLY thing rejecting a
# mistyped override. These two cases are what keeps that from being a silent widening:
# a tier-shaped typo must still fail, and tierMap values keep the real closed enum.
expect_violation invalid-override-unknown-tier.json  "reviewers.modelOverrides.security-reviewer: must name a dispatch model"
expect_violation invalid-bad-tiermap-value.json      "reviewers.tierMap.code: must be haiku|sonnet|opus|fable"
expect_violation invalid-tracker-unknown-key.json   "tracker: unknown keys"
expect_violation invalid-bot-app-unknown-key.json   "tracker.bot.app: unknown keys"
expect_violation invalid-bad-design-provider.json   "design.provider must be figma|claude-design"
expect_violation invalid-bad-liverender.json        "design.liveRender: unknown keys"
expect_violation invalid-bad-liverender.json        "design.liveRender.command: required"
expect_violation invalid-bad-liverender.json        "design.liveRender.cwd: not a topology.repos id"
# #711 `design.liveRender.tolerancePx`, both rejected shapes. A NUMBER is not enough: the value is
# a pixel count the gate compares against, so a fractional one is as unusable as a negative one and
# the two arms of the predicate are separately reachable. The absent and zero cases ride the
# valid-* glob above (valid-liverender-no-tolerance.json, valid-liverender-tolerance.json) — the
# key is optional, and 0 is the "exact match or red" boundary a consumer legitimately asks for.
expect_violation invalid-tolerancepx-negative.json  "design.liveRender.tolerancePx: must be a non-negative integer"
expect_violation invalid-tolerancepx-fraction.json  "design.liveRender.tolerancePx: must be a non-negative integer"
# ...and it is a KNOWN key, not one the unknown-keys arm happens to catch. Without this the same
# violation text would be produced by a lint that never learned the key at all.
expect_no_violation invalid-tolerancepx-negative.json "design.liveRender: unknown keys"
# #348 retired stageParams.visualCapture. This fixture no longer carries a BAD viewport — a
# perfectly well-formed one is enough now, because the key itself is the violation. Renaming the
# file would break its git history for no gain; the assertion says what it actually proves.
expect_violation invalid-bad-viewport.json          "stageParams.visualCapture was removed in #348"
expect_violation invalid-bad-extralane.json         "extraLanes[0].failureClass: must be a closed failure-taxonomy value"
# #569 retired stageWorkflows / implementDelegates / planGates. Same treatment as
# invalid-bad-viewport.json above: both fixtures now carry a perfectly WELL-FORMED entry,
# because the key itself is the violation — a per-item shape check no longer exists to fail.
# The rejection must NAME the key (a bare "unknown top-level keys" would not say what
# happened to it), which is why the retired keys stay in config-lint's top-level allowlist.
expect_violation invalid-bad-stageworkflow.json     "stageWorkflows was removed in #569"
expect_violation invalid-bad-plangate.json          "planGates was removed in #569"
# ...and the generic rejection must NOT also fire, or the specific message is drowned by a
# second one contradicting it. This is the whole point of the allowlist mechanic.
expect_no_violation invalid-bad-stageworkflow.json  "unknown top-level keys"
expect_no_violation invalid-bad-plangate.json       "unknown top-level keys"
# #574 retired commands.<repo>.unitTestScope / .testFile with the mutation-gate engine —
# the nested-key sibling of the #569 mechanic above: WELL-FORMED values, because the keys
# themselves are the violation; the rejection must NAME each key; and the generic
# unknown-keys message must NOT also fire (the keys stay in the commands allowlist).
expect_violation invalid-removed-mutation-keys.json "commands.host.unitTestScope was removed in #574"
expect_violation invalid-removed-mutation-keys.json "commands.host.testFile was removed in #574"
expect_no_violation invalid-removed-mutation-keys.json "commands.host: unknown keys"
# #107: lintAutofixes:true + a plain `npm run` lint command silently no-ops the autofix the
# flag declares — npm swallows a trailing `--fix` without a `--` separator. valid-lintautofix-npm-withfix.json
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

# --- #15: the config-lint type-check gaps (F83 mutant matrix). One packed fixture, one
# assertion per surviving-mutant class it must now KILL. Plus the removed-key notes.
# #569 retired three of the classes along with their keys — stageWorkflows[].stage,
# implementDelegates[].surface and planGates[].surface have no per-item shape check left to
# gap. The fixture keeps implementDelegates, repurposed as the removal probe below.
expect_violation invalid-type-gaps.json             "stageParams.planFilePattern: must be string"
expect_violation invalid-type-gaps.json             "stageParams.inertPattern: must be string"
expect_violation invalid-type-gaps.json             "reviewers.remove: must be array"
expect_violation invalid-type-gaps.json             "commands.host.extraLanes[0].when: must be array"
expect_violation invalid-type-gaps.json             "paths.plansDir: must be string"
# The third retired key (#569); its two siblings have dedicated fixtures above.
expect_violation invalid-type-gaps.json             "implementDelegates was removed in #569"
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
# whole chain), and the verify lane then silently skipped it — a false green. `null`
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
# to its artifact; the marker test below is byte-shared with the review-toolkit copy under the
# `monorepo-probe` LOCKSTEP markers. The differing `ROOT=` assignment sits ABOVE them on purpose,
# so only the shared test is inside the block — a widened or renamed marker on one side alone is
# exactly the drift that would let one suite skip where the other still fails.
ROOT="$HERE/../../.."
# LOCKSTEP-BEGIN monorepo-probe
if [[ -f "$ROOT/.claude-plugin/marketplace.json" && -d "$ROOT/plugins" ]]; then
  IN_MONOREPO=1
else
  IN_MONOREPO=0
fi
# LOCKSTEP-END monorepo-probe
SCHEMA="$ROOT/schema/second-shift.config.schema.json"
# Re-pointed at tierMap (#351): modelOverrides.additionalProperties no longer carries an
# enum to mirror, and tierMap VALUES are raw dispatch models — expressible, so the schema
# still declares them and this drives both sides of that copy.
SCHEMA_Q='.properties.reviewers.properties.tierMap.additionalProperties.enum'
if [[ ! -f "$SCHEMA" ]]; then
  if [[ "$IN_MONOREPO" -eq 1 ]]; then
    check "tierMap enum mirror: schema readable at $SCHEMA" 1
  else
    SKIP_REASON="SKIP: schema/second-shift.config.schema.json is a repo-only artifact, unreachable from an install — the tierMap enum lockstep did not run"
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
      reviewers: { tierMap: { code: $t } }
    }' > "$TIER_TMP/tier.json"
    if "$LINT" "$TIER_TMP/tier.json" > /dev/null 2>&1; then
      check "schema dispatch model '$tier' accepted as a tierMap value" 0
    else
      check "schema dispatch model '$tier' accepted as a tierMap value" 1
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
    { "$LINT" "$FIX/invalid-bad-tiermap-value.json" 2>&1 || true; } \
      | sed -n 's/.*reviewers\.tierMap\.code: must be //p' \
      | head -1 | tr -d '[:space:]'
  )"
  if [[ -n "$ACTUAL_ENUM" && "$ACTUAL_ENUM" == "$EXPECTED_ENUM" ]]; then
    check "tierMap enum mirror: config-lint reports exactly the schema's '$EXPECTED_ENUM'" 0
  else
    check "tierMap enum mirror: schema says '$EXPECTED_ENUM' but config-lint reports '$ACTUAL_ENUM'" 1
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
  mkdir -p "$FAB/.claude-plugin" "$FAB/plugins/dev-pipeline"
  printf '{}\n' > "$FAB/.claude-plugin/marketplace.json"
  cp -R "$HERE" "$FAB/plugins/dev-pipeline/tools"
  fab_rc=0
  fab_out="$(SECOND_SHIFT_SELFTEST_FABRICATED_TREE=1 \
    bash "$FAB/plugins/dev-pipeline/tools/$(basename "${BASH_SOURCE[0]}")" 2>&1)" || fab_rc=$?
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
