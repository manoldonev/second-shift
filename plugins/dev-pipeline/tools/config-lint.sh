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

# The shipped tier alphabet (#351). A reviewers.modelOverrides value may name a TIER as
# well as a raw dispatch model, so this lint needs the same alphabet check-model-tiers.sh
# parses — from the same authority, ../model-tiering.md, rather than a second hardcoded
# copy that would drift from it. The parse block below is pinned to that script's copy by the
# `tier-alphabet-parse` LOCKSTEP markers, which scripts/check-lockstep-pairs.sh discovers and
# compares verbatim. Edit one, edit both.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TIER_DOC="${SECOND_SHIFT_TIER_DOC:-$SCRIPT_DIR/../model-tiering.md}"
parse_tier_alphabet() { # parse_tier_alphabet <doc-path>
    [ -f "$1" ] || return 0
# LOCKSTEP-BEGIN tier-alphabet-parse
    awk '
        /^##[[:space:]]+Tier alphabet[[:space:]]*$/ { inseg = 1; next }
        inseg && /^##[[:space:]]/                   { inseg = 0 }
        inseg && /^\|/ {
            n = split($0, c, "|")
            if (n < 4) next
            tier = c[2]; tok = c[3]
            gsub(/^[ \t]+|[ \t]+$/, "", tier)
            gsub(/^[ \t]+|[ \t]+$/, "", tok)
            if (tier ~ /^[a-z][a-z0-9_-]*$/ && tok ~ /^[a-z][a-z0-9_.-]*$/)
                printf "%s\t%s\n", tier, tok
        }
    ' "$1"
# LOCKSTEP-END tier-alphabet-parse
}
# `jq -s .` emits `[]` on empty stdin, so an unreadable or table-less TIER_DOC already yields
# an empty alphabet here rather than an empty STRING — no separate fallback assignment is
# needed, and one that looked like the empty-input guard but could never run was worse than
# none. An empty alphabet then fails a modelOverrides value naming a shipped tier, which is
# the safe direction: a missing authority rejects, it does not wave through.
SHIPPED_TIERS_JSON=$(parse_tier_alphabet "$TIER_DOC" | cut -f1 | jq -R . | jq -s .)

ERRORS=$(jq -r --argjson shippedTiers "$SHIPPED_TIERS_JSON" '
  def err(cond; msg): if cond then [msg] else [] end;
  # `lintAutofixes: true` declares the configured lint command MUTATES files, and
  # the onboard detect.sh script derives it from a `--fix` in that command string.
  # Plain `npm run <script>` swallows a trailing flag instead of forwarding it to the
  # underlying tool unless the command already ends in a `--` separator — so
  # "npm run lint --fix" sets the flag true while npm eats the flag, and the autofix
  # the config now claims silently never happens (#107). yarn/pnpm/direct-tool
  # invocations forward unrecognized flags on their own and are not flagged.
  def npm_no_fix_forward: (. // "") as $c | ($c | test("^npm run ")) and (($c | rtrimstr(" ")) | endswith("--") | not);

  # ---- top level ----------------------------------------------------------
  # A retired key is rejected by NAME, with what to write instead and the migration pointer, and
  # stays in the allowlist beneath so that message fires INSTEAD of a bare "unknown top-level
  # keys", which would name the key without saying what happened to it. The allowlist entry is
  # message routing: the schema no longer publishes these keys.
  ("(docs/migrations/v2-to-v3.md)") as $v3doc
  | err((.configVersion? | type) != "number"; "configVersion: required number (current: 3)")
  + err(((.configVersion? | type) == "number") and .configVersion > 3;
        "configVersion \(.configVersion) is newer than this plugin understands — upgrade the marketplace pin (docs/releasing.md)")
  + err(((.configVersion? | type) == "number") and .configVersion < 3;
        "configVersion \(.configVersion) predates this plugin (current: 3) — see docs/migrations/v2-to-v3.md for the upgrade path" + (if .configVersion < 2 then " (apply docs/migrations/v1-to-v2.md first)" else "" end))
  + err((.tracker | type) != "object"; "tracker: required object")
  + err((.commands | type) != "object"; "commands: required object")
  + err(has("stageWorkflows"); "stageWorkflows was removed — a registered stage workflow had stopped running when the staged lane was deleted. Nothing replaced it: an additive check is commands.<id>.extraLanes, run by /dev-pipeline:run after every build. Delete the key from your config (docs/migrations/v1-to-v2.md; the shape is kept as a design record in docs/extending.md §3.6)")
  + err(has("implementDelegates"); "implementDelegates was removed — a registered delegate had stopped being routed to when the staged lane was deleted. The pipeline is outcome-gated and silent on HOW the diff is produced, so a build session may still dispatch the same agent by choice; what has no home is the config-routed surface-to-agent mechanism. Delete the key from your config (docs/migrations/v1-to-v2.md; the shape is kept as a design record in docs/extending.md §3.7)")
  + err(has("planGates"); "planGates was removed — a registered plan gate had stopped running when the staged lane was deleted. There is no plan gate on the pipeline for one to be additive to; the record is judged by /dev-pipeline:review. Delete the key from your config (docs/migrations/v1-to-v2.md; the shape is kept as a design record in docs/extending.md §3.8)")
  + err(has("topology"); "topology was removed in configVersion 3 — nothing reads it: the base branch is the remote default branch, worktrees go under RUN_WORKTREE_ROOT, and commands is keyed by any id. Delete the block " + $v3doc)
  + err(has("gates"); "gates was removed in configVersion 3 — delete the block " + $v3doc)
  + err(has("stageParams"); "stageParams was removed in configVersion 3 — delete the block; webComponentGlobs moves to reviewers.webComponentGlobs " + $v3doc)
  + err(has("grillWaivers"); "grillWaivers was removed in configVersion 3 — config-grill findings are advisory now (doctor and onboard report them as WARN), so there is nothing to waive. Delete the key " + $v3doc)
  + err(
      (keys - ["$schema","configVersion","tracker","commands","reviewers","paths","design","run","topology","gates","stageParams","grillWaivers","stageWorkflows","implementDelegates","planGates"]) != [];
      "unknown top-level keys: " + ((keys - ["$schema","configVersion","tracker","commands","reviewers","paths","design","run","topology","gates","stageParams","grillWaivers","stageWorkflows","implementDelegates","planGates"]) | join(", "))
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

  # ---- retired: topology -----------------------------------------------------
  + (if (.topology | type) == "object" then (.topology |
      err(has("type"); "topology.type was removed in configVersion 3 — there is no topology to declare: each repo is onboarded on its own " + $v3doc)
      + (if (.repos | type) == "object" then (.repos | to_entries | map(
          .key as $id | (.value | if type == "object" then . else {} end) |
            err(has("path"); "topology.repos." + $id + ".path was removed in configVersion 3 — commands and liveRender run in the ticket worktree of the repo the config lives in " + $v3doc)
          + err(has("baseBranch"); "topology.repos." + $id + ".baseBranch was removed in configVersion 3 — the base branch is the remote default branch (origin/HEAD); change it on the code host " + $v3doc)
          + err(has("worktreesDir"); "topology.repos." + $id + ".worktreesDir was removed in configVersion 3 — export RUN_WORKTREE_ROOT instead (default: <parent>/<repo>-worktrees) " + $v3doc)
          + err(has("ticketTag"); "topology.repos." + $id + ".ticketTag was removed in configVersion 3 — nothing routes on it; say the repo in the ticket title or body " + $v3doc)
        ) | add // []) else [] end)
    ) else [] end)

  # ---- commands ------------------------------------------------------------
  # Keyed by an id, and not cross-checked against anything: /dev-pipeline:run uses the sole key,
  # else the key equal to the directory name of this checkout.
  + ((.commands // {}) | to_entries | map(
      (.key as $repo | .value |
        # unitTestScope/testFile: retired keys rejected by NAME, and kept in the unknown-keys
        # allowlist below so this message, not the generic one, is what a consumer sees.
        err(has("unitTestScope"); "commands." + $repo + ".unitTestScope was removed — the unit-test mutation engine that read it was retired, so the key armed nothing. For mutation coverage, add your own mutation tool as a commands.<id>.extraLanes check. Delete the key from your config (docs/migrations/v1-to-v2.md)")
        + err(has("testFile"); "commands." + $repo + ".testFile was removed — it was the retired unit-test mutation engine\u0027s per-spec runner template, read by nothing else. Delete the key from your config (docs/migrations/v1-to-v2.md)")
        + err(((keys) - ["lint","lintAutofixes","typecheck","test","testFile","unitTestScope","format","lanes","extraLanes","allowUnverified"]) != []; "commands." + $repo + ": unknown keys (note: integrationTest/apiTest were removed in v2.1.6, commands.<repo>.build was removed — ship those tiers via extraLanes; see docs/migrations)")
        + ([to_entries[] | select(.key | IN("lint","typecheck","test","format")) |
            err((.value | type) | IN("string","null") | not; "commands." + $repo + "." + .key + ": must be string or null")
          ] | add // [])
        + err((.lintAutofixes? != null) and ((.lintAutofixes | type) != "boolean"); "commands." + $repo + ".lintAutofixes: must be boolean")
        + err(
            (.lintAutofixes? == true) and ((.lint? // "") | npm_no_fix_forward);
            "commands." + $repo + ".lintAutofixes is true but lint (\"" + (.lint? // "") + "\") is a plain `npm run` invocation — npm swallows a trailing `--fix` instead of forwarding it to the underlying tool, so the autofix this flag declares silently never happens; add a trailing `--` separator (e.g. \"" + ((.lint? // "") | rtrimstr(" ")) + " --\") or invoke the tool directly (e.g. \"npx eslint .\")"
          )
        + err((.allowUnverified? != null) and ((.allowUnverified | type) != "boolean"); "commands." + $repo + ".allowUnverified: must be boolean")
        + ((.lanes // []) | if type != "array" then ["commands." + $repo + ".lanes: must be array"] else (to_entries | map(
            (.key as $li | .value |
              # Entry-shape guard FIRST (#100). Without it a non-object entry is
              # silently accepted: jq evaluates `+` operands right-to-left, and
              # `.name?` on a string/number/array yields `empty`, which collapses
              # the whole chain before `keys` below is ever reached — so the lane
              # lints clean and the verify runner then skips it, reaching a false green.
              # An `and` guard on `keys` alone is NOT sufficient (the sibling
              # field accesses still collapse); the branch must precede them all.
              if (type != "object") then
                ["commands." + $repo + ".lanes[" + ($li|tostring) + "]: must be an object {name, cwd?, commands[]}"]
              else
              err(((keys) - ["name","cwd","commands"]) != []; "commands." + $repo + ".lanes[" + ($li|tostring) + "]: unknown keys")
              + err((.name? // "") == ""; "commands." + $repo + ".lanes[" + ($li|tostring) + "].name: required")
              + err((.cwd? != null) and ((.cwd | type) != "string"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].cwd: must be string")
              + err((.commands? == null); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: required")
              + err((.commands? != null) and ((.commands | type) != "array"); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: must be array")
              + err(((.commands? | type) == "array") and ((.commands | length) < 1); "commands." + $repo + ".lanes[" + ($li|tostring) + "].commands: at least one required")
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
      (["haiku","sonnet","opus","fable"]) as $models
      | ($shippedTiers + ((.tierMap // {}) | if type == "object" then keys else [] end)) as $tiers
      | err(((keys) - ["add","remove","default","modelOverrides","tierMap","webComponentGlobs"]) != []; "reviewers: unknown keys")
      + err((.webComponentGlobs? != null) and ((.webComponentGlobs | type) != "array"); "reviewers.webComponentGlobs: must be array")
      + ((.webComponentGlobs // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["reviewers.webComponentGlobs: every entry must be a string"] else [] end) else [] end)
      + err((.add? != null) and ((.add | type) != "array"); "reviewers.add: must be array")
      + err((.remove? != null) and ((.remove | type) != "array"); "reviewers.remove: must be array")
      + ((.remove // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["reviewers.remove: every entry must be a string"] else [] end) else [] end)
      + err((.default? != null) and ((.default | type) != "array"); "reviewers.default: must be array")
      + ((.default // []) | if type == "array" then (map(select((type) != "string")) | if length > 0 then ["reviewers.default: every entry must be a string"] else [] end) else [] end)
      + ((.add // []) | to_entries | map(
          err((.value.name? // "") == ""; "reviewers.add[" + (.key|tostring) + "].name: required")
        ) | add // [])
      # tierMap VALUES are raw dispatch models — that closed enum is the real one, and the
      # schema still declares it. Validated before modelOverrides because the effective
      # alphabet below is built from its keys.
      + err((.tierMap? != null) and ((.tierMap | type) != "object"); "reviewers.tierMap: must be object")
      + ((.tierMap // {}) | if type == "object" then (to_entries | map(
          err((.value | type) != "string" or (.value | IN("haiku","sonnet","opus","fable") | not); "reviewers.tierMap." + .key + ": must be haiku|sonnet|opus|fable")
        ) | add // []) else [] end)
      # A modelOverrides value is the closed UNION of the dispatch models and the EFFECTIVE
      # tier alphabet — the shipped tiers merged with any this config declares. This is the
      # cross-field constraint JSON Schema cannot express, which is why the schema half
      # degrades to a bare string and the real check lives here.
      + ((.modelOverrides // {}) | to_entries | map(
          err((.value | IN(($models + $tiers)[])) | not; "reviewers.modelOverrides." + .key + ": must name a dispatch model (haiku, sonnet, opus, fable) or a tier in the effective tierMap")
        ) | add // [])
    )

  # ---- paths / run / design ------------------------------------------------
  + ((.paths // {}) |
      err(((keys) - ["plansDir","pipelineStateDir"]) != []; "paths: unknown keys")
      + err((.plansDir? != null) and ((.plansDir | type) != "string"); "paths.plansDir: must be string")
      + err((.pipelineStateDir? != null) and ((.pipelineStateDir | type) != "string"); "paths.pipelineStateDir: must be string")
    )
  + ((.run // {}) |
      err((type) != "object"; "run: must be object")
      + err(((keys) - ["maxRounds","checksRedMax","buildTimeoutSeconds","reviewTimeoutSeconds","costCeilingUsd"]) != []; "run: unknown keys")
      + err((.maxRounds? != null) and (((.maxRounds | type) != "number") or (.maxRounds != (.maxRounds | floor)) or (.maxRounds < 1)); "run.maxRounds: must be an integer >= 1")
      + err((.checksRedMax? != null) and (((.checksRedMax | type) != "number") or (.checksRedMax != (.checksRedMax | floor)) or (.checksRedMax < 1)); "run.checksRedMax: must be an integer >= 1")
      + err((.buildTimeoutSeconds? != null) and (((.buildTimeoutSeconds | type) != "number") or (.buildTimeoutSeconds != (.buildTimeoutSeconds | floor)) or (.buildTimeoutSeconds < 60)); "run.buildTimeoutSeconds: must be an integer >= 60")
      + err((.reviewTimeoutSeconds? != null) and (((.reviewTimeoutSeconds | type) != "number") or (.reviewTimeoutSeconds != (.reviewTimeoutSeconds | floor)) or (.reviewTimeoutSeconds < 60)); "run.reviewTimeoutSeconds: must be an integer >= 60")
      + err((.costCeilingUsd? != null) and (((.costCeilingUsd | type) != "number") or (.costCeilingUsd <= 0)); "run.costCeilingUsd: must be a number > 0")
    )
  + (if (.design != null) then (.design |
      err((type) != "object"; "design: must be object")
      + err(((keys) - ["provider","liveRender"]) != []; "design: unknown keys")
      + err((.provider? // "") | IN("figma","claude-design") | not; "design.provider must be figma|claude-design")
      + (if (.liveRender != null) then (.liveRender |
          err((type) != "object"; "design.liveRender: must be object")
          + err(has("tolerancePx"); "design.liveRender.tolerancePx was removed in configVersion 3 — the pixel-tolerance compare is replaced by the route smoke /dev-pipeline:run runs after every build; set design.liveRender.smokeCommand " + $v3doc)
          + err(has("cwd"); "design.liveRender.cwd was removed in configVersion 3 — the render command runs in the ticket worktree; put any cd into the command itself; if it named another repo, move design into that repo config " + $v3doc)
          + err(((keys) - ["command","readyProbe","smokeCommand","tolerancePx","cwd"]) != []; "design.liveRender: unknown keys")
          + err((.command? // "") == ""; "design.liveRender.command: required")
          + err((.command? != null) and ((.command | type) != "string"); "design.liveRender.command: must be string")
          + err((.smokeCommand? != null) and ((.smokeCommand | type) != "string"); "design.liveRender.smokeCommand: must be string")
          + err((.readyProbe? != null) and ((.readyProbe | type) != "string"); "design.liveRender.readyProbe: must be string")
        ) else [] end)
    ) else [] end)

  # ---- retired: gates, stageParams ---------------------------------------------
  + (if (.gates | type) == "object" then (.gates |
      err(has("mutation"); "gates.mutation was removed in configVersion 3 — nothing read it; for mutation coverage, add your own mutation tool as a commands.<id>.extraLanes check " + $v3doc)
      + err(has("figma"); "gates.figma was removed in v2 — use design: {\"provider\": ...} (docs/migrations/v1-to-v2.md)")
      + err(has("apiTests"); "gates.apiTests was removed in v2 — ship an API-test tier via commands.<id>.extraLanes (docs/migrations/v1-to-v2.md)")
      + err(has("costTracking"); "gates.costTracking was removed in v2.1.6 — the toggle had no reader (docs/migrations/v1-to-v2.md)")
    ) else [] end)
  + (if (.stageParams | type) == "object" then (.stageParams |
      err(has("visualCapture"); "stageParams.visualCapture was removed — the advisory smoke-capture has no reader. The design check is the route smoke, design.liveRender.smokeCommand " + $v3doc)
      + err(has("planFilePattern"); "stageParams.planFilePattern was removed in configVersion 3 — the committed intake record is always <paths.plansDir>/<repo>-<key>-decisions.md " + $v3doc)
      + err(has("requiredLabels"); "stageParams.requiredLabels was removed in configVersion 3 — the label vocabulary is tracker.labels (queue, claimed, and tracker.labels.blockers for the do-not-pick-up set; github only — under jira delete the key, nothing replaces it) " + $v3doc)
      + err(has("webComponentGlobs"); "stageParams.webComponentGlobs moved to reviewers.webComponentGlobs in configVersion 3 — same value, new key " + $v3doc)
      + err(has("formatGlob"); "stageParams.formatGlob was removed in configVersion 3 — nothing read it; the format check is commands.<id>.format " + $v3doc)
      + err(has("inertPattern"); "stageParams.inertPattern was removed in configVersion 3 — every configured check runs on every build, so there is no inert-diff classifier to override " + $v3doc)
    ) else [] end)

  | .[]
' "$CONFIG")

if [[ -n "$ERRORS" ]]; then
  echo "config-lint: $CONFIG:" >&2
  while IFS= read -r line; do echo "  ✗ $line" >&2; done <<< "$ERRORS"
  exit 1
fi

echo "config-lint: OK ($CONFIG)"
