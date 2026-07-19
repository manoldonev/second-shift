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
  err((.configVersion? | type) != "number"; "configVersion: required number (current: 1)")
  + err(((.configVersion? | type) == "number") and .configVersion > 1;
        "configVersion \(.configVersion) is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)")
  + err(((.configVersion? | type) == "number") and .configVersion < 1;
        "configVersion \(.configVersion) predates this plugin — see docs/migrations/ for the upgrade path")
  + err((.tracker | type) != "object"; "tracker: required object")
  + err((.topology | type) != "object"; "topology: required object")
  + err((.commands | type) != "object"; "commands: required object")
  + err(
      (keys - ["$schema","configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams","stageWorkflows","implementDelegates","planGates"]) != [];
      "unknown top-level keys: " + ((keys - ["$schema","configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams","stageWorkflows","implementDelegates","planGates"]) | join(", "))
    )

  # ---- tracker -------------------------------------------------------------
  + err((.tracker.type? // "") | IN("github","jira") | not; "tracker.type must be github|jira")
  + err((.tracker.bot? != null) and (.tracker.type? == "jira"); "tracker.bot is github-only")
  + err((.tracker | type == "object") and ((.tracker | keys) - ["type","writes","bot","keyPattern","branchPrefix","labels"]) != []; "tracker: unknown keys")
  + err((.tracker.writes? != null) and ((.tracker.writes | type) != "boolean"); "tracker.writes: must be boolean")
  + err((.tracker.branchPrefix? != null) and ((.tracker.branchPrefix | type) != "string"); "tracker.branchPrefix: must be string")
  + err((.tracker.keyPattern? != null) and ((.tracker.keyPattern | type) != "string"); "tracker.keyPattern: must be string")
  + err((.tracker.labels? != null) and (.tracker.type? == "jira"); "tracker.labels is github-only (a JIRA repo has no queue/claim/label vocabulary)")
  + ((.tracker.labels // {}) |
      err((type == "object") and ((keys) - ["queue","claimed","blockers"]) != []; "tracker.labels: unknown keys")
      + err((.queue? != null) and ((.queue | type) != "string"); "tracker.labels.queue: must be string")
      + err((.claimed? != null) and ((.claimed | type) != "string"); "tracker.labels.claimed: must be string")
      + err((.blockers? != null) and ((.blockers | type) != "array"); "tracker.labels.blockers: must be array")
    )
  + ((.tracker.bot // {}) |
      err((type == "object") and ((keys) - ["enabled","envVar","wrapperPath","app"]) != []; "tracker.bot: unknown keys")
      + err((.enabled? != null) and ((.enabled | type) != "boolean"); "tracker.bot.enabled: must be boolean")
      + err((.envVar? != null) and ((.envVar | type) != "string"); "tracker.bot.envVar: must be string")
      + err((.wrapperPath? != null) and ((.wrapperPath | type) != "string"); "tracker.bot.wrapperPath: must be string")
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
        err(((keys) - ["lint","lintAutofixes","typecheck","test","testFile","unitTestScope","build","format","lanes","extraLanes","allowUnverified"]) != []; "commands." + $repo + ": unknown keys (note: integrationTest/apiTest were removed in v2.1.6 — ship those tiers via extraLanes / extension points EP-6/EP-7; see docs/migrations)")
        + ([to_entries[] | select(.key | IN("lint","typecheck","test","testFile","unitTestScope","build","format")) |
            err((.value | type) | IN("string","null") | not; "commands." + $repo + "." + .key + ": must be string or null")
          ] | add // [])
        + err((.lintAutofixes? != null) and ((.lintAutofixes | type) != "boolean"); "commands." + $repo + ".lintAutofixes: must be boolean")
        + err((.allowUnverified? != null) and ((.allowUnverified | type) != "boolean"); "commands." + $repo + ".allowUnverified: must be boolean")
        + ((.lanes // []) | if type != "array" then ["commands." + $repo + ".lanes: must be array"] else (to_entries | map(
            (.key as $li | .value |
              err(((keys) - ["name","cwd","commands"]) != []; "commands." + $repo + ".lanes[" + ($li|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".lanes[" + ($li|tostring) + "].name: required")
              + err((.cwd? != null) and ((.cwd | type) != "string"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].cwd: must be string")
              + err((.commands? != null) and ((.commands | type) != "array"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: must be array")
              + err((.commands? != null) and ((.commands | type) == "array") and ((.commands | length) < 1); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: at least one required when present")
            )
          ) | add // []) end)
        + ((.extraLanes // []) | if type != "array" then ["commands." + $repo + ".extraLanes: must be array"] else (to_entries | map(
            (.key as $i | .value |
              err(((keys) - ["name","when","commands","failureClass"]) != []; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].name: required")
              + err((.when? != null) and ((.when | type) != "array"); "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].when: must be array")
              + err(((.commands // []) | length) < 1; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].commands: at least one required")
              + err((.failureClass? // "") | IN("FORMAT","LINT_AUTOFIX","TYPE_ERROR","TEST_FAILURE","PLAN_CMD_FAILURE","INFRA") | not; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].failureClass: must be a closed failure-taxonomy value (FORMAT|LINT_AUTOFIX|TYPE_ERROR|TEST_FAILURE|PLAN_CMD_FAILURE|INFRA)")
            )
          ) | add // []) end)
      )
    ) | add // [])

  # ---- reviewers -----------------------------------------------------------
  + err((.reviewers? != null) and ((.reviewers | type) != "object"); "reviewers: must be object")
  + ((.reviewers // {}) |
      err(((keys) - ["add","remove","modelOverrides"]) != []; "reviewers: unknown keys")
      + err((.add? != null) and ((.add | type) != "array"); "reviewers.add: must be array")
      + err((.remove? != null) and ((.remove | type) != "array"); "reviewers.remove: must be array")
      + ((.remove // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["reviewers.remove: every entry must be a string"] else [] end) else [] end)
      + ((.add // []) | to_entries | map(
          err((.value.name? // "") == ""; "reviewers.add[" + (.key|tostring) + "].name: required")
        ) | add // [])
      + ((.modelOverrides // {}) | to_entries | map(
          err(.value | IN("haiku","sonnet","opus") | not; "reviewers.modelOverrides." + .key + ": must be haiku|sonnet|opus")
        ) | add // [])
    )

  # ---- paths / gates / design ------------------------------------------------
  + ((.paths // {}) |
      err(((keys) - ["plansDir","pipelineStateDir"]) != []; "paths: unknown keys")
      + err((.plansDir? != null) and ((.plansDir | type) != "string"); "paths.plansDir: must be string")
      + err((.pipelineStateDir? != null) and ((.pipelineStateDir | type) != "string"); "paths.pipelineStateDir: must be string")
    )
  + ((.gates // {}) |
      err(has("figma"); "gates.figma was removed in v2 — use design: {\"provider\": ...} (docs/migrations/v1-to-v2.md)")
      + err(has("apiTests"); "gates.apiTests was removed in v2 — ship an API-test tier via extension points EP-6/EP-7 (docs/migrations/v1-to-v2.md)")
      + err(has("costTracking"); "gates.costTracking was removed in v2.1.6 — local OTel cost attribution now runs unconditionally (passive, never blocks); the toggle had no reader (docs/migrations/v1-to-v2.md)")
      + err(((keys) - ["mutation","costTracking","figma","apiTests"]) != [];
            "gates: unknown keys: " + (((keys) - ["mutation","costTracking","figma","apiTests"]) | join(", ")))
      + (to_entries | map(select(.key == "mutation") | err((.value | type) != "boolean"; "gates." + .key + ": must be boolean")) | add // [])
    )
  + (if (.design != null) then ((.topology.repos // {} | keys) as $repoIds | .design |
      err((type) != "object"; "design: must be object")
      + err(((keys) - ["provider","liveRender"]) != []; "design: unknown keys")
      + err((.provider? // "") | IN("figma","claude-design") | not; "design.provider must be figma|claude-design")
      + (if (.liveRender != null) then (.liveRender |
          err((type) != "object"; "design.liveRender: must be object")
          + err(((keys) - ["command","cwd","readyProbe"]) != []; "design.liveRender: unknown keys")
          + err((.command? // "") == ""; "design.liveRender.command: required")
          + err((.command? != null) and ((.command | type) != "string"); "design.liveRender.command: must be string")
          + err((.cwd? != null) and ((.cwd | type) != "string"); "design.liveRender.cwd: must be string")
          + err((.cwd? != null) and ((.cwd | type) == "string") and ($repoIds != []) and ((.cwd as $c | $repoIds | index($c)) == null); "design.liveRender.cwd: not a topology.repos id")
          + err((.readyProbe? != null) and ((.readyProbe | type) != "string"); "design.liveRender.readyProbe: must be string")
        ) else [] end)
    ) else [] end)
  + (if (.stageWorkflows != null) then (.stageWorkflows |
      err((type) != "array"; "stageWorkflows: must be array")
      + (to_entries | map(
          (.key as $i | .value |
            err(((keys) - ["stage","name","workflow"]) != []; "stageWorkflows[" + ($i|tostring) + "]: unknown keys")
            + err(((.stage | type) != "number") or (((.stage // 0) | floor) != (.stage // 0)) or ((.stage // 0) < 1) or ((.stage // 0) > 10); "stageWorkflows[" + ($i|tostring) + "].stage: must be an integer 1-10")
            + err((.name? // "") == ""; "stageWorkflows[" + ($i|tostring) + "].name: required")
            + err((.workflow? // "") == ""; "stageWorkflows[" + ($i|tostring) + "].workflow: required")
          )
        ) | add // [])
      + err(([.[].name] | length) != ([.[].name] | unique | length); "stageWorkflows: names must be unique")
    ) else [] end)
  + (if (.implementDelegates != null) then (.implementDelegates |
      err((type) != "array"; "implementDelegates: must be array")
      + (to_entries | map(
          (.key as $i | .value |
            err(((keys) - ["surface","agent"]) != []; "implementDelegates[" + ($i|tostring) + "]: unknown keys")
            + err((.surface? // "") == ""; "implementDelegates[" + ($i|tostring) + "].surface: required")
            + err((.surface? != null) and ((.surface | type) != "string"); "implementDelegates[" + ($i|tostring) + "].surface: must be string")
            + err((.agent? // "") == ""; "implementDelegates[" + ($i|tostring) + "].agent: required")
          )
        ) | add // [])
    ) else [] end)
  + (if (.planGates != null) then (.planGates |
      err((type) != "array"; "planGates: must be array")
      + (to_entries | map(
          (.key as $i | .value |
            err(((keys) - ["name","surface","agent"]) != []; "planGates[" + ($i|tostring) + "]: unknown keys")
            + err((.name? // "") == ""; "planGates[" + ($i|tostring) + "].name: required")
            + err((.surface? != null) and ((.surface | type) != "string"); "planGates[" + ($i|tostring) + "].surface: must be string")
            + err((.agent? // "") == ""; "planGates[" + ($i|tostring) + "].agent: required")
          )
        ) | add // [])
      + err(([.[].name] | length) != ([.[].name] | unique | length); "planGates: names must be unique")
    ) else [] end)
  + (if (.stageParams != null) then (.stageParams |
      err((type) != "object"; "stageParams: must be object")
      + err(((keys) - ["planFilePattern","requiredLabels","visualCapture","formatGlob"]) != []; "stageParams: unknown keys")
      + err((.planFilePattern? != null) and ((.planFilePattern | type) != "string"); "stageParams.planFilePattern: must be string")
      + err((.formatGlob? != null) and ((.formatGlob | type) != "string"); "stageParams.formatGlob: must be string")
      + err((.requiredLabels? != null) and ((.requiredLabels | type) != "array"); "stageParams.requiredLabels: must be array")
      + ((.requiredLabels // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["stageParams.requiredLabels: every entry must be a string"] else [] end) else [] end)
      + ((.visualCapture // {}) |
          err((type) != "object"; "stageParams.visualCapture: must be object")
          + err(((keys) - ["baseUrl","devServerCommand","smokeRoutes","viewports","triggerGlobs"]) != []; "stageParams.visualCapture: unknown keys")
          + err((.baseUrl? != null) and ((.baseUrl | type) != "string"); "stageParams.visualCapture.baseUrl: must be string")
          + err((.devServerCommand? != null) and ((.devServerCommand | type) != "string"); "stageParams.visualCapture.devServerCommand: must be string")
          + err((.smokeRoutes? != null) and ((.smokeRoutes | type) != "array"); "stageParams.visualCapture.smokeRoutes: must be array")
          + err((.triggerGlobs? != null) and ((.triggerGlobs | type) != "array"); "stageParams.visualCapture.triggerGlobs: must be array")
          + err((.viewports? != null) and ((.viewports | type) != "array"); "stageParams.visualCapture.viewports: must be array")
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
