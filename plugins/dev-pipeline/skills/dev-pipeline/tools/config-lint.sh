#!/usr/bin/env bash
# config-lint.sh — validate a consumer repo's .claude/second-shift.config.json
#
# Structural validator in bash+jq (no node/ajv dependency, same toolchain as the
# pipeline's shell tools). Mirrors schema/second-shift.config.schema.json; the
# schema file is the documentation contract, this script is the enforcement the
# plugins actually run. Keep the two in lockstep.
#
# Usage: config-lint.sh <config-file>
# Exit:  0 valid · 1 violations (listed on stderr) · 3 usage/IO error
set -euo pipefail

CONFIG="${1:?usage: config-lint.sh <config-file>}"
[[ -f "$CONFIG" ]] || { echo "config-lint: no such file: $CONFIG" >&2; exit 3; }

jq empty "$CONFIG" 2>/dev/null || { echo "config-lint: not valid JSON: $CONFIG" >&2; exit 1; }

ERRORS=$(jq -r '
  def err(cond; msg): if cond then [msg] else [] end;

  # ---- top level ----------------------------------------------------------
  err(.configVersion != 1; "configVersion must be 1")
  + err((.tracker | type) != "object"; "tracker: required object")
  + err((.topology | type) != "object"; "topology: required object")
  + err((.commands | type) != "object"; "commands: required object")
  + err(
      (keys - ["configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams"]) != [];
      "unknown top-level keys: " + ((keys - ["configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams"]) | join(", "))
    )

  # ---- tracker -------------------------------------------------------------
  + err((.tracker.type? // "") | IN("github","jira") | not; "tracker.type must be github|jira")
  + err((.tracker.bot? != null) and (.tracker.type? == "jira"); "tracker.bot is github-only")
  + err((.tracker | type == "object") and ((.tracker | keys) - ["type","writes","bot","keyPattern","branchPrefix"]) != []; "tracker: unknown keys")
  + err((.tracker.writes? != null) and ((.tracker.writes | type) != "boolean"); "tracker.writes: must be boolean")
  + err((.tracker.branchPrefix? != null) and ((.tracker.branchPrefix | type) != "string"); "tracker.branchPrefix: must be string")
  + err((.tracker.keyPattern? != null) and ((.tracker.keyPattern | type) != "string"); "tracker.keyPattern: must be string")
  + ((.tracker.bot // {}) |
      err((type == "object") and ((keys) - ["enabled","envVar","wrapperPath","app"]) != []; "tracker.bot: unknown keys")
      + ((.app // {}) | err((type == "object") and ((keys) - ["clientId","appName","privateKeyFilename","installationId"]) != []; "tracker.bot.app: unknown keys"))
    )

  # ---- topology ------------------------------------------------------------
  + err((.topology.type? // "") | IN("standalone","be-fe-pair","monorepo") | not; "topology.type must be standalone|be-fe-pair|monorepo")
  + err(((.topology.repos? // {}) | length) < 1; "topology.repos: at least one repo required")
  + ((.topology.repos // {}) | to_entries | map(
      err((.value.path? // "") == ""; "topology.repos." + .key + ".path: required")
      + err((.value.baseBranch? // "") == ""; "topology.repos." + .key + ".baseBranch: required")
      + err(((.value | keys) - ["path","baseBranch","worktreesDir","ticketTag"]) != []; "topology.repos." + .key + ": unknown keys")
    ) | add // [])
  + err(
      (.topology.type? == "be-fe-pair") and ((((.topology.repos? // {}) | keys) | contains(["be","fe"])) | not);
      "topology.type be-fe-pair requires repos.be and repos.fe"
    )

  # ---- commands ------------------------------------------------------------
  + err(
      ((.commands // {}) | keys) - ((.topology.repos // {}) | keys) != [];
      "commands keyed by unknown repo ids: " + ((((.commands // {}) | keys) - ((.topology.repos // {}) | keys)) | join(", "))
    )
  + ((.commands // {}) | to_entries | map(
      (.key as $repo | .value |
        err(((keys) - ["lint","lintAutofixes","typecheck","test","testFile","unitTestScope","integrationTest","apiTest","build","format","lanes","extraLanes"]) != []; "commands." + $repo + ": unknown keys")
        + ([to_entries[] | select(.key | IN("lint","typecheck","test","testFile","unitTestScope","integrationTest","apiTest","build","format")) |
            err((.value | type) | IN("string","null") | not; "commands." + $repo + "." + .key + ": must be string or null")
          ] | add // [])
        + ((.lanes // []) | to_entries | map(
            err((.value.name? // "") == ""; "commands." + $repo + ".lanes[" + (.key|tostring) + "].name: required")
          ) | add // [])
        + ((.extraLanes // []) | to_entries | map(
            (.key as $i | .value |
              err(((keys) - ["name","when","commands","failureClass"]) != []; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].name: required")
              + err(((.commands // []) | length) < 1; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].commands: at least one required")
              + err((.failureClass? // "") | IN("FORMAT","LINT_AUTOFIX","TYPE_ERROR","TEST_FAILURE","PLAN_CMD_FAILURE","INFRA") | not; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].failureClass: must be a closed failure-taxonomy value (FORMAT|LINT_AUTOFIX|TYPE_ERROR|TEST_FAILURE|PLAN_CMD_FAILURE|INFRA)")
            )
          ) | add // [])
      )
    ) | add // [])

  # ---- reviewers -----------------------------------------------------------
  + err((.reviewers? != null) and ((.reviewers | type) != "object"); "reviewers: must be object")
  + ((.reviewers // {}) |
      err(((keys) - ["add","remove","modelOverrides"]) != []; "reviewers: unknown keys")
      + ((.add // []) | to_entries | map(
          err((.value.name? // "") == ""; "reviewers.add[" + (.key|tostring) + "].name: required")
        ) | add // [])
      + ((.modelOverrides // {}) | to_entries | map(
          err(.value | IN("haiku","sonnet","opus") | not; "reviewers.modelOverrides." + .key + ": must be haiku|sonnet|opus")
        ) | add // [])
    )

  # ---- paths / gates / design ------------------------------------------------
  + ((.paths // {}) | err(((keys) - ["plansDir","pipelineStateDir"]) != []; "paths: unknown keys"))
  + ((.gates // {}) |
      err(((keys) - ["mutation","costTracking"]) != []; "gates: unknown keys")
      + (to_entries | map(err((.value | type) != "boolean"; "gates." + .key + ": must be boolean")) | add // [])
    )
  + (if (.design != null) then (.design |
      err((type) != "object"; "design: must be object")
      + err(((keys) - ["provider"]) != []; "design: unknown keys")
      + err((.provider? // "") | IN("figma","claude-design") | not; "design.provider must be figma|claude-design")
    ) else [] end)
  + (if (.stageParams != null) then (.stageParams |
      err((type) != "object"; "stageParams: must be object")
      + err(((keys) - ["planFilePattern","requiredLabels","visualCapture","formatGlob"]) != []; "stageParams: unknown keys")
      + err((.planFilePattern? != null) and ((.planFilePattern | type) != "string"); "stageParams.planFilePattern: must be string")
      + err((.formatGlob? != null) and ((.formatGlob | type) != "string"); "stageParams.formatGlob: must be string")
      + err((.requiredLabels? != null) and ((.requiredLabels | type) != "array"); "stageParams.requiredLabels: must be array")
      + ((.visualCapture // {}) |
          err((type) != "object"; "stageParams.visualCapture: must be object")
          + err(((keys) - ["baseUrl","devServerCommand","smokeRoutes","viewports","triggerGlobs"]) != []; "stageParams.visualCapture: unknown keys")
          + ((.viewports // []) | map(select(. as $v | ["mobile","tablet","laptop","desktop"] | index($v) | not)) |
              if length > 0 then ["stageParams.visualCapture.viewports must be a subset of mobile|tablet|laptop|desktop"] else [] end)
        )
    ) else [] end)

  | .[]
' "$CONFIG")

if [[ -n "$ERRORS" ]]; then
  echo "config-lint: $CONFIG:" >&2
  while IFS= read -r line; do echo "  ✗ $line" >&2; done <<< "$ERRORS"
  exit 1
fi

echo "config-lint: OK ($CONFIG)"
