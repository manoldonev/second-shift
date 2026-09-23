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

expect_violation invalid-bad-run-caps.json          "run: unknown keys"
expect_violation invalid-bad-run-caps.json          "run.maxRounds: must be an integer >= 1"
expect_violation invalid-bad-run-caps.json          "run.checksRedMax: must be an integer >= 1"
expect_violation invalid-bad-run-caps.json          "run.costCeilingUsd: must be a number > 0"
expect_violation invalid-bad-run-caps.json          "run.buildTimeoutSeconds: must be an integer >= 60"
expect_violation invalid-bad-run-caps.json          "run.reviewTimeoutSeconds: must be an integer >= 60"
expect_violation invalid-bad-smokecommand.json      "design.liveRender.smokeCommand: must be string"
expect_violation invalid-bad-tracker.json           "tracker.type must be github|jira"
# commands is keyed by an id the scheduler resolves (the sole key, else this checkout's directory
# name) and is no longer cross-checked against anything: a second key is legal. The fixture still
# fails, on its modelOverrides typo, so the no-violation assertion reads a real failing run.
expect_no_violation invalid-unknown-repo-and-tier.json "commands keyed by unknown repo ids"
expect_violation invalid-unknown-repo-and-tier.json "reviewers.modelOverrides.security-reviewer: must name a dispatch model (haiku, sonnet, opus, fable) or a tier in the effective tierMap"
# The schema half of modelOverrides is a bare string (the legal set is a cross-field union it
# cannot express), so config-lint is the ONLY thing rejecting a mistyped override: a tier-shaped
# typo must still fail, and tierMap values keep the real closed enum.
expect_violation invalid-override-unknown-tier.json  "reviewers.modelOverrides.security-reviewer: must name a dispatch model"
expect_violation invalid-bad-tiermap-value.json      "reviewers.tierMap.code: must be haiku|sonnet|opus|fable"

# reviewers.default — the per-repo opt-in into the trimmed review panel. Typed here the way
# remove[] is; the NAME check is check-reviewer-references.sh's. The valid fixture is what fails
# when `default` is missing from the reviewers key allowlist.
expect_violation invalid-reviewers-default-type.json  "reviewers.default: must be array"
expect_violation invalid-reviewers-default-entry.json "reviewers.default: every entry must be a string"
expect_no_violation valid-reviewers-default.json      "reviewers: unknown keys"
expect_violation invalid-tracker-unknown-key.json   "tracker: unknown keys"
expect_violation invalid-bot-app-unknown-key.json   "tracker.bot.app: unknown keys"
expect_violation invalid-bad-design-provider.json   "design.provider must be figma|claude-design"
expect_violation invalid-bad-liverender.json        "design.liveRender: unknown keys"
expect_violation invalid-bad-liverender.json        "design.liveRender.command: required"
expect_violation invalid-bad-extralane.json         "extraLanes[0].failureClass: must be a closed failure-taxonomy value"

# --- configVersion. The PRIOR version is the case a real consumer hits at the bump; it must be
# rejected WITH the migration-doc pointer, never a bare "invalid".
expect_violation invalid-configversion-2.json       "configVersion 2 predates this plugin (current: 3) — see docs/migrations/v2-to-v3.md for the upgrade path"
expect_violation invalid-configversion-1.json       "configVersion 1 predates this plugin (current: 3) — see docs/migrations/v2-to-v3.md"
expect_violation invalid-configversion-1.json       "apply docs/migrations/v1-to-v2.md first"
expect_violation invalid-configversion-0.json       "configVersion 0 predates this plugin (current: 3)"
expect_violation invalid-configversion-4.json       "configVersion 4 is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)"
# The v3 shape needs no topology: a v2 config that only bumped the number must not be told
# topology is REQUIRED — it is told the block is gone.
expect_no_violation valid-standalone-minimal.json   "topology"

# --- Retired keys. Each is rejected by NAME with the migration pointer, never by the generic
# unknown-keys arm, which would name the key without saying what happened to it or what to write
# instead. Each fixture carries WELL-FORMED values, because the key itself is the violation.
expect_violation invalid-removed-topology.json      "topology was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.type was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.repos.be.path was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.repos.be.baseBranch was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.repos.be.worktreesDir was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.repos.be.ticketTag was removed in configVersion 3"
expect_violation invalid-removed-topology.json      "topology.repos.fe.baseBranch was removed in configVersion 3"
expect_no_violation invalid-removed-topology.json   "unknown top-level keys"
expect_violation invalid-removed-gates.json         "gates was removed in configVersion 3"
expect_violation invalid-removed-gates.json         "gates.mutation was removed in configVersion 3"
expect_violation invalid-removed-gates.json         "gates.costTracking was removed in v2.1.6"
expect_no_violation invalid-removed-gates.json      "gates: unknown keys"
expect_violation invalid-v1-gates-figma.json        'gates.figma was removed in v2 — use design: {"provider": ...} (docs/migrations/v1-to-v2.md)'
expect_violation invalid-removed-grillwaivers.json  "grillWaivers was removed in configVersion 3"
expect_no_violation invalid-removed-grillwaivers.json "unknown top-level keys"
expect_violation invalid-removed-stageparams.json   "stageParams was removed in configVersion 3"
expect_violation invalid-removed-stageparams.json   "stageParams.planFilePattern was removed in configVersion 3"
expect_violation invalid-removed-stageparams.json   "stageParams.requiredLabels was removed in configVersion 3"
expect_violation invalid-removed-stageparams.json   "tracker.labels.blockers"
expect_violation invalid-removed-stageparams.json   "stageParams.webComponentGlobs moved to reviewers.webComponentGlobs in configVersion 3"
expect_violation invalid-removed-stageparams.json   "stageParams.formatGlob was removed in configVersion 3"
expect_violation invalid-removed-stageparams.json   "stageParams.inertPattern was removed in configVersion 3"
expect_no_violation invalid-removed-stageparams.json "unknown top-level keys"
expect_no_violation invalid-removed-stageparams.json "stageParams: unknown keys"
expect_violation invalid-bad-viewport.json          "stageParams.visualCapture was removed —"
expect_violation invalid-removed-liverender-keys.json "design.liveRender.tolerancePx was removed in configVersion 3"
expect_violation invalid-removed-liverender-keys.json "design.liveRender.cwd was removed in configVersion 3"
expect_no_violation invalid-removed-liverender-keys.json "design.liveRender: unknown keys"
# Every retirement above points at the one doc that says what to write instead.
expect_violation invalid-removed-liverender-keys.json "(docs/migrations/v2-to-v3.md)"

# --- reviewers.webComponentGlobs: the new home of the web-component surface. The valid fixture
# (valid-schema-key-standalone.json, in the valid-*.json loop) fails when the key is missing from
# the reviewers allowlist; these pin the type checks it carried under stageParams.
expect_no_violation valid-schema-key-standalone.json "reviewers: unknown keys"
expect_violation invalid-webcomponentglobs-entry.json "reviewers.webComponentGlobs: every entry must be a string"

# EP-6/7/8 retired earlier. Same mechanic: the key is the violation, the rejection names it, and
# the generic rejection must NOT also fire.
expect_violation invalid-bad-stageworkflow.json     "stageWorkflows was removed —"
expect_violation invalid-bad-plangate.json          "planGates was removed —"
expect_no_violation invalid-bad-stageworkflow.json  "unknown top-level keys"
expect_no_violation invalid-bad-plangate.json       "unknown top-level keys"
# commands.<id>.unitTestScope / .testFile — the nested-key sibling of the same mechanic.
expect_violation invalid-removed-mutation-keys.json "commands.host.unitTestScope was removed —"
expect_violation invalid-removed-mutation-keys.json "commands.host.testFile was removed —"
expect_no_violation invalid-removed-mutation-keys.json "commands.host: unknown keys"
# lintAutofixes:true + a plain `npm run` lint command silently no-ops the autofix the flag
# declares — npm swallows a trailing `--fix` without a `--` separator.
# valid-lintautofix-npm-withfix.json proves the trailing-`--` escape hatch is accepted.
expect_violation invalid-lintautofix-npm-nofix.json "commands.app.lintAutofixes is true but lint (\"npm run lint\") is a plain \`npm run\` invocation"

# --- the config-lint type-check gaps. One packed fixture, one assertion per mutant class it
# must KILL.
expect_violation invalid-type-gaps.json             "reviewers.remove: must be array"
expect_violation invalid-type-gaps.json             "commands.host.extraLanes[0].when: must be array"
expect_violation invalid-type-gaps.json             "paths.plansDir: must be string"
expect_violation invalid-type-gaps.json             "implementDelegates was removed —"
expect_violation invalid-type-gaps.json             "commands.host.lanes[0].cwd: must be string"
expect_violation invalid-type-gaps.json             "commands.host.lanes[0].commands: must be array"
expect_violation invalid-type-gaps.json             "commands.host.lanes[1].commands: at least one required"
expect_violation invalid-type-gaps.json             "tracker.bot.enabled: must be boolean"
expect_violation invalid-type-gaps.json             "reviewers.webComponentGlobs: must be array"

# --- a non-object lanes[]/extraLanes[] entry must be a CLEAN violation. Without the entry-shape
# guard a string/number/array lane lint-clean-passed (jq's right-to-left `+` and `.name?`-on-a-
# string yielding `empty` collapsed the whole chain), and the scheduler would then skip it — a
# false green. The trailing well-formed lane proves the guard is per-entry.
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[0]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[1]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[2]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.lanes[3]: must be an object"
expect_violation invalid-bad-lane-shape.json        "commands.host.extraLanes[0]: must be an object"

# --- a setup lane with no command is refused by the scheduler's preflight; lint must refuse it too.
expect_violation invalid-lane-no-commands.json      "commands.host.lanes[0].commands: required"
expect_violation invalid-lane-no-commands.json      "commands.host.lanes[1].commands: at least one required"

# --- dead command keys removed earlier keep their migration note.
expect_violation invalid-removed-commands-tiers.json "integrationTest/apiTest were removed in v2.1.6"
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
      configVersion: 3,
      tracker: { type: "github" },
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
