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
  # verifyctl autofix loop appends a bare ` --fix` to the configured lint command
  # ($CMD_LINT --fix). Plain `npm run <script>` swallows a trailing flag instead of
  # forwarding it to the underlying tool unless the command already ends in a `--`
  # separator — so `lintAutofixes: true` paired with e.g. "npm run lint" silently no-ops
  # the fix loop with no signal (#107). yarn/pnpm/direct-tool invocations forward
  # unrecognized flags on their own and are not flagged.
  def npm_no_fix_forward: (. // "") as $c | ($c | test("^npm run ")) and (($c | rtrimstr(" ")) | endswith("--") | not);

  # ---- top level ----------------------------------------------------------
  err((.configVersion? | type) != "number"; "configVersion: required number (current: 2)")
  + err(((.configVersion? | type) == "number") and .configVersion > 2;
        "configVersion \(.configVersion) is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)")
  + err(((.configVersion? | type) == "number") and .configVersion < 2;
        "configVersion \(.configVersion) predates this plugin (current: 2) — see docs/migrations/v1-to-v2.md for the upgrade path")
  + err((.tracker | type) != "object"; "tracker: required object")
  + err((.topology | type) != "object"; "topology: required object")
  + err((.commands | type) != "object"; "commands: required object")
  + err(
      (keys - ["$schema","configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams","stageWorkflows","implementDelegates","planGates","grillWaivers"]) != [];
      "unknown top-level keys: " + ((keys - ["$schema","configVersion","tracker","topology","commands","reviewers","paths","gates","design","stageParams","stageWorkflows","implementDelegates","planGates","grillWaivers"]) | join(", "))
    )

  # ---- tracker -------------------------------------------------------------
  + err((.tracker.type? // "") | IN("github","jira") | not; "tracker.type must be github|jira")
  + err((.tracker | type == "object") and ((.tracker | keys) - ["type","writes","bot","keyPattern","branchPrefix","labels"]) != []; "tracker: unknown keys")
  + err((.tracker.writes? != null) and ((.tracker.writes | type) != "boolean"); "tracker.writes: must be boolean")
  + err((.tracker.branchPrefix? != null) and ((.tracker.branchPrefix | type) != "string"); "tracker.branchPrefix: must be string")
  + err((.tracker.keyPattern? != null) and ((.tracker.keyPattern | type) != "string"); "tracker.keyPattern: must be string")
  # `labels` is tracker-gated and `bot` deliberately is NOT (#440). A label vocabulary is queue
  # machinery, and a JIRA repo has no queue — so that one really is github-only. The bot is a
  # CODE-HOST capability that was modelled on the tracker axis by accident: every key the shape
  # rules below allow (enabled / envVar / wrapperPath / app.*) configures write IDENTITY, and
  # none is claim-specific. Source control is GitHub under both adapters, so a JIRA-tracked
  # repo writes to GitHub on every run and needs the identity exactly as much as a github-
  # tracked one. Rejecting it left those consumers permanently operator-attributed and
  # permanently degraded at the identity arm of the merge boundary. Do not re-add this rule;
  # if the parent name is the complaint, the fix is a configVersion migration, not a refusal.
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
  + err(
      (.topology.type? == "monorepo") and
      ((((.topology.repos? // {}) | length) > 1) or
       (((.topology.repos? // {}) | to_entries | map(select(.value.path? == ".")) | length) < 1));
      "topology.type monorepo requires exactly one topology.repos entry with path \".\" — a second independent verify surface is not a second repos entry, ship it via commands.<id>.lanes / extraLanes instead"
    )

  # ---- commands ------------------------------------------------------------
  + err(
      ((.commands // {}) | keys) - ((.topology.repos // {}) | keys) != [];
      "commands keyed by unknown repo ids: " + ((((.commands // {}) | keys) - ((.topology.repos // {}) | keys)) | join(", "))
    )
  + ((.commands // {}) | to_entries | map(
      (.key as $repo | .value |
        err(((keys) - ["lint","lintAutofixes","typecheck","test","testFile","unitTestScope","format","lanes","extraLanes","allowUnverified"]) != []; "commands." + $repo + ": unknown keys (note: integrationTest/apiTest were removed in v2.1.6, commands.<repo>.build was removed (#113: never executed by any verify lane) — ship those tiers via extraLanes / extension points EP-6/EP-7; see docs/migrations)")
        + ([to_entries[] | select(.key | IN("lint","typecheck","test","testFile","unitTestScope","format")) |
            err((.value | type) | IN("string","null") | not; "commands." + $repo + "." + .key + ": must be string or null")
          ] | add // [])
        + err((.lintAutofixes? != null) and ((.lintAutofixes | type) != "boolean"); "commands." + $repo + ".lintAutofixes: must be boolean")
        + err(
            (.lintAutofixes? == true) and ((.lint? // "") | npm_no_fix_forward);
            "commands." + $repo + ".lintAutofixes is true but lint (\"" + (.lint? // "") + "\") is a plain `npm run` invocation — npm swallows the `--fix` suffix verifyctl appends instead of forwarding it to the underlying tool; add a trailing `--` separator (e.g. \"" + ((.lint? // "") | rtrimstr(" ")) + " --\") or invoke the tool directly (e.g. \"npx eslint .\")"
          )
        + err((.allowUnverified? != null) and ((.allowUnverified | type) != "boolean"); "commands." + $repo + ".allowUnverified: must be boolean")
        + ((.lanes // []) | if type != "array" then ["commands." + $repo + ".lanes: must be array"] else (to_entries | map(
            (.key as $li | .value |
              # Entry-shape guard FIRST (#100). Without it a non-object entry is
              # silently accepted: jq evaluates `+` operands right-to-left, and
              # `.name?` on a string/number/array yields `empty`, which collapses
              # the whole chain before `keys` below is ever reached — so the lane
              # lints clean and verifyctl then skips it, reaching a false green.
              # An `and` guard on `keys` alone is NOT sufficient (the sibling
              # field accesses still collapse); the branch must precede them all.
              if (type != "object") then
                ["commands." + $repo + ".lanes[" + ($li|tostring) + "]: must be an object {name, cwd?, commands[]}"]
              else
              err(((keys) - ["name","cwd","commands"]) != []; "commands." + $repo + ".lanes[" + ($li|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".lanes[" + ($li|tostring) + "].name: required")
              + err((.cwd? != null) and ((.cwd | type) != "string"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].cwd: must be string")
              + err((.commands? != null) and ((.commands | type) != "array"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: must be array")
              + err((.commands? != null) and ((.commands | type) == "array") and ((.commands | length) < 1); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: at least one required when present")
              end
            )
          ) | add // []) end)
        + ((.extraLanes // []) | if type != "array" then ["commands." + $repo + ".extraLanes: must be array"] else (to_entries | map(
            (.key as $i | .value |
              # Same entry-shape guard as lanes[] above (#100). extraLanes was not
              # silent — a non-object entry crashed jq with rc=5 via `.commands`
              # below — but a raw crash is not a lint violation; make it clean.
              if (type != "object") then
                ["commands." + $repo + ".extraLanes[" + ($i|tostring) + "]: must be an object {name, when?, commands[], failureClass?}"]
              else
              err(((keys) - ["name","when","commands","failureClass"]) != []; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].name: required")
              + err((.when? != null) and ((.when | type) != "array"); "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].when: must be array")
              + err(((.commands // []) | length) < 1; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].commands: at least one required")
              + err((.failureClass? // "") | IN("FORMAT","LINT_AUTOFIX","TYPE_ERROR","TEST_FAILURE","PLAN_CMD_FAILURE","INFRA") | not; "commands." + $repo + ".extraLanes[" + ($i|tostring) + "].failureClass: must be a closed failure-taxonomy value (FORMAT|LINT_AUTOFIX|TYPE_ERROR|TEST_FAILURE|PLAN_CMD_FAILURE|INFRA)")
              end
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
          err(.value | IN("haiku","sonnet","opus","fable") | not; "reviewers.modelOverrides." + .key + ": must be haiku|sonnet|opus|fable")
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
  # ---- grillWaivers ----------------------------------------------------------
  # Declared opt-outs for config-grill.sh findings (shipped in the second-shift plugin,
  # run by /second-shift:onboard and /second-shift:doctor). Keys are CHECK IDS carrying
  # the repo id where the check is per-repo (e.g. "T4.mutation-plumbing.api") — never a
  # dotted config path, which would silence two distinct checks that share a key, and
  # never a bare check id, which would silence every repo under a multi-repo topology.
  # The value is the human-authored reason; an empty one is a waiver with no accountability.
  + (if (.grillWaivers != null) then (.grillWaivers |
      err((type) != "object"; "grillWaivers: must be an object keyed by config-grill check id")
      + (if (type) == "object" then (to_entries | map(
          err(((.value | type) != "string") or ((.value | length) == 0);
              "grillWaivers." + .key + ": must be a non-empty reason string")
        ) | add // []) else [] end)
    ) else [] end)

  + (if (.stageParams != null) then (.stageParams |
      err((type) != "object"; "stageParams: must be object")
      + err(has("visualCapture"); "stageParams.visualCapture was removed in #348 — Stage 6'"'"'s advisory smoke-capture died with the staged lane and has no lean reader. The blocking design check is design.liveRender (docs/live-render.md, docs/migrations/v1-to-v2.md)")
      + err(((keys) - ["planFilePattern","requiredLabels","visualCapture","webComponentGlobs","formatGlob","inertPattern"]) != []; "stageParams: unknown keys")
      + err((.planFilePattern? != null) and ((.planFilePattern | type) != "string"); "stageParams.planFilePattern: must be string")
      + err((.formatGlob? != null) and ((.formatGlob | type) != "string"); "stageParams.formatGlob: must be string")
      + err((.inertPattern? != null) and ((.inertPattern | type) != "string"); "stageParams.inertPattern: must be string")
      + err((.inertPattern? != null) and ((.inertPattern | type) == "string") and (.inertPattern == ""); "stageParams.inertPattern: must be non-empty (omit the key to use the default inert set)")
      + err((.requiredLabels? != null) and ((.requiredLabels | type) != "array"); "stageParams.requiredLabels: must be array")
      + ((.requiredLabels // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["stageParams.requiredLabels: every entry must be a string"] else [] end) else [] end)
      + err((.webComponentGlobs? != null) and ((.webComponentGlobs | type) != "array"); "stageParams.webComponentGlobs: must be array")
      + ((.webComponentGlobs // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["stageParams.webComponentGlobs: every entry must be a string"] else [] end) else [] end)
    ) else [] end)

  | .[]
' "$CONFIG")

# stageParams.inertPattern must actually COMPILE as an ERE. jq can only check that it
# is a non-empty string; whether `grep -E` accepts it is knowable only by asking grep.
# Doing it here means a typo is a config-time rejection rather than a Stage-6 surprise
# — and while is-inert-diff.sh fails closed to SUITE on an uncompilable pattern, that
# is a safety net, not a diagnosis: it fires once per verify with the run already
# underway. rc 0/1 are both "compiled" (matched / did not match); rc >= 2 is the
# compile failure. Empty input keeps this a pure syntax probe.
INERT_PATTERN_CFG=$(jq -r '.stageParams.inertPattern // empty' "$CONFIG" 2>/dev/null)
if [[ -n "$INERT_PATTERN_CFG" ]]; then
  # rc must be captured from grep itself, not read as $? inside an `if !` branch
  # (there it is the negation's status, always 0). `|| true` keeps `set -e` out of it,
  # since rc 1 — "compiled fine, matched nothing" — is the expected result here.
  grep_rc=0
  printf '' | grep -E "$INERT_PATTERN_CFG" >/dev/null 2>&1 || grep_rc=$?
  if [[ "$grep_rc" -ge 2 ]]; then
    ERRORS="${ERRORS:+$ERRORS$'\n'}stageParams.inertPattern: not a valid extended regular expression (grep -E rejected it)"
  fi
fi

if [[ -n "$ERRORS" ]]; then
  echo "config-lint: $CONFIG:" >&2
  while IFS= read -r line; do echo "  ✗ $line" >&2; done <<< "$ERRORS"
  exit 1
fi

echo "config-lint: OK ($CONFIG)"
