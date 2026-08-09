#!/usr/bin/env bash
# config-grill.sh — GRILL a consumer's second-shift config for detectable gaps.
#
# `config-lint.sh` is a STRUCTURAL validator: absence is legal for every optional key, so it
# is incapable of noticing that a capability is silently off. Nothing downstream notices
# either — a capability that is off simply never runs, and the run still reports green. This
# checker is the other half: wherever a gap or misconfiguration is *detectable from repo plus
# config with no human input*, it says so, says exactly what to set, and says what the
# consumer gets for setting it.
#
# Run by BOTH front doors: /second-shift:onboard (on the drafted config, before the
# accept-or-edit screen) and /second-shift:doctor (on the committed config).
#
# Usage: config-grill.sh <repo-root> [<config-path>]
#        config-path defaults to <repo-root>/.claude/second-shift.config.json
# Output: ONE JSON document on stdout — { findings: [...], notEvaluated: [...] }
# Exit:  0 always when it ran (findings are DATA, not a crash) · 3 usage/IO error
#
# A `notEvaluated` entry is never a finding: it has no proposal, cannot be waived, and must
# not block onboard's accept predicate. Callers render it informationally.
#
# Waivers live in the config's top-level `grillWaivers` object, keyed by check id (with the
# repo id where the check is per-repo) and valued by a human-authored reason. A waived
# finding is suppressed HERE, so both callers suppress identically. `check-config-shadowing.sh`
# carries no row for `grillWaivers`: its CHECKS array is rooted at the dev-pipeline skill dir
# and this key's only reader is this script, inside the second-shift plugin. Stated exception,
# not an oversight.
#
# Read-only, no network, bash-3.2 safe.
set -uo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "usage: config-grill.sh <repo-root> [<config-path>]" >&2; exit 3; }
[[ -d "$ROOT" ]] || { echo "config-grill: no such directory: $ROOT" >&2; exit 3; }
ROOT_ABS="$(cd "$ROOT" && pwd -P)" || { echo "config-grill: cannot enter: $ROOT" >&2; exit 3; }
CONFIG="${2:-$ROOT_ABS/.claude/second-shift.config.json}"
[[ -f "$CONFIG" ]] || { echo "config-grill: no such file: $CONFIG" >&2; exit 3; }
jq empty "$CONFIG" 2>/dev/null || { echo "config-grill: not valid JSON: $CONFIG" >&2; exit 3; }
cd "$ROOT_ABS" || exit 3

FINDINGS=()
NOTEVAL=()
WAIVERS="$(jq -c 'if (.grillWaivers | type) == "object" then .grillWaivers else {} end' "$CONFIG")"

add_finding() { # $1 id, $2 key, $3 evidence, $4 proposal
  jq -e --arg k "$1" 'has($k)' <<< "$WAIVERS" >/dev/null 2>&1 && return 0
  FINDINGS+=("$(jq -nc --arg id "$1" --arg key "$2" --arg ev "$3" --arg pr "$4" \
    '{id:$id, key:$key, evidence:$ev, proposal:$pr}')")
}
add_noteval() { # $1 id, $2 key, $3 reason
  NOTEVAL+=("$(jq -nc --arg id "$1" --arg key "$2" --arg r "$3" '{id:$id, key:$key, reason:$r}')")
}
json_array() { if [[ $# -eq 0 ]]; then echo '[]'; else printf '%s\n' "$@" | jq -sc '.'; fi; }
join_c() { local out="" x; for x in "$@"; do [[ -z "$out" ]] && out="$x" || out="$out, $x"; done; printf '%s' "$out"; }

waiver_hint() { # $1 = check id
  printf 'If this is deliberate, declare it rather than leaving it silent: add "grillWaivers": { "%s": "<your reason>" } to the config.' "$1"
}

# --- repo scoping (AC-1) -----------------------------------------------------------------
# Both callers are cwd-scoped. Reading a sibling checkout means touching directories outside
# the root we were handed, so a sibling is reported, never reached.
REPO_ID=""
for id in $(jq -r '(.topology.repos // {}) | keys[]' "$CONFIG" 2>/dev/null); do
  p="$(jq -r --arg i "$id" '.topology.repos[$i].path // ""' "$CONFIG")"
  cand=""
  [[ -n "$p" ]] && cand="$(cd "$ROOT_ABS/$p" 2>/dev/null && pwd -P)"
  if [[ -n "$cand" && "$cand" == "$ROOT_ABS" ]]; then
    REPO_ID="$id"
  else
    add_noteval "topology.$id" "topology.repos.$id" \
      "path \"$p\" does not resolve to the evaluated root ($ROOT_ABS) — a sibling checkout is outside this run's reach; grill it from its own root"
  fi
done

# --- glob → ERE (AC-3) --------------------------------------------------------------------
# bash 3.2 has no `globstar`, and `git ls-files` pathspec globbing does not brace-expand, so
# neither shell globbing nor git can match these patterns. Transliterate and grep instead.
#
# A pattern containing "/" is path-shaped: "*" stops at a separator, "**" crosses them.
# A pattern with NO "/" (the formatGlob shape) is matched with "*" crossing separators —
# that reproduces verifyctl.sh's `[[ "$f" == $a ]]` byte-for-byte. Using [^/]* there would
# match only root-level files and would fire a zero-match finding on every repo whose sources
# sit in a subdirectory.
glob_to_ere() { # $1 = glob → prints an anchored ERE
  local g="$1" out="" i=0 len=${#1} c n depth=0 has_slash=0
  case "$g" in */*) has_slash=1 ;; esac
  while [[ "$i" -lt "$len" ]]; do
    c="${g:$i:1}"
    case "$c" in
      '*')
        n="${g:$((i+1)):1}"
        if [[ "$n" == '*' ]]; then
          if [[ "${g:$((i+2)):1}" == '/' ]]; then out="$out([^/]*/)*"; i=$((i+3))
          else out="$out.*"; i=$((i+2)); fi
        else
          if [[ "$has_slash" -eq 1 ]]; then out="${out}[^/]*"; else out="$out.*"; fi
          i=$((i+1))
        fi
        ;;
      '?') if [[ "$has_slash" -eq 1 ]]; then out="${out}[^/]"; else out="$out."; fi; i=$((i+1)) ;;
      '{') out="$out("; depth=$((depth+1)); i=$((i+1)) ;;
      '}') if [[ "$depth" -gt 0 ]]; then out="$out)"; depth=$((depth-1)); else out="$out\\}"; fi; i=$((i+1)) ;;
      ',') if [[ "$depth" -gt 0 ]]; then out="$out|"; else out="$out,"; fi; i=$((i+1)) ;;
      '.'|'+'|'('|')'|'|'|'^'|'$'|'['|']'|\\) out="$out\\$c"; i=$((i+1)) ;;
      *) out="$out$c"; i=$((i+1)) ;;
    esac
  done
  printf '^%s$' "$out"
}

TRACKED=""
TRACKED_OK=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED="$(git ls-files 2>/dev/null)"
  TRACKED_OK=1
fi

count_glob_matches() { # $1.. globs → prints the number of tracked files matching any of them
  local joined="" g re n
  for g in "$@"; do
    re="$(glob_to_ere "$g")"
    if [[ -z "$joined" ]]; then joined="$re"; else joined="$joined|$re"; fi
  done
  if [[ -z "$joined" ]]; then printf '0'; return 0; fi
  n="$(printf '%s\n' "$TRACKED" | grep -cE "$joined" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# --- trigger 2: a silent-fallback default that cannot match the repo (AC-2/AC-3) ----------
# Per-key table. The blanket rule "zero matches is a finding" does not survive contact with
# the key list, so the rows that cannot mean anything are dropped EXPLICITLY:
#   inertPattern      — its predicate belongs to is-inert-diff.sh, which ships in dev-pipeline
#                       and is frequently NOT installed at onboard time; preflight.sh already
#                       runs the real classifier at its Step 8, where the plugin resolves.
#                       Re-implementing the predicate here would be an early warning that can
#                       disagree with the late gate, which is worse than no warning.
#   planFilePattern   — names a file Stage 3 is about to CREATE; zero matches is universal.
#   paths.*           — directories a fresh repo legitimately lacks.
#   visualCapture non-glob keys — not tree-shaped at all.
#
# Each active row fires on BOTH an absent key whose resolved default matches nothing AND a
# hand-set value that matches nothing: an adopted value can itself be broken, so setting a key
# wrongly must not silence the check.
#
# The DEFAULTS below are the RUNTIME-resolved literals — the jq fallback the consuming stage
# actually applies — never the JSON Schema `default`, which nothing injects into a config.
# Their coupling to the source sites is recorded as a DROPPED entry in
# scripts/lockstep-manifest.tsv: the webComponentGlobs literal alone is restated at seven
# sites across two plugins, which file-to-file anchored pairs cannot express.
t2_key() { # $1 id, $2 key, $3 jq expr yielding the configured globs (empty when unset),
           # $4 benefit sentence; DEFAULT_GLOBS[] and CANDIDATES[] must be set by the caller
  local id="$1" key="$2" expr="$3" benefit="$4"
  if [[ "$TRACKED_OK" -ne 1 ]]; then
    add_noteval "$id" "$key" "not a git work tree — tracked files cannot be enumerated"
    return 0
  fi
  local cur src n cand cn line ev pr alt="" altn=0
  cur="$(jq -r "$expr" "$CONFIG" 2>/dev/null)"
  local -a globs=()
  if [[ -n "$cur" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && globs+=("$line"); done <<< "$cur"
    src="configured value"
  fi
  if [[ "${#globs[@]}" -eq 0 ]]; then
    globs=("${DEFAULT_GLOBS[@]}")
    src="unset; resolved default"
  fi
  n="$(count_glob_matches "${globs[@]}")"
  [[ "$n" -gt 0 ]] && return 0
  for cand in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
    cn="$(count_glob_matches "$cand")"
    if [[ "$cn" -gt 0 ]]; then alt="$cand"; altn="$cn"; break; fi
  done
  ev="$key — $src ($(join_c "${globs[@]}")) matches 0 of the repo's tracked files."
  if [[ -n "$alt" ]]; then
    pr="Set $key to this repo's real surface: \"$alt\" matches $altn tracked file(s). $benefit $(waiver_hint "$id")"
  else
    pr="Set $key to this repo's real surface — no candidate from the shipped list matched any tracked file either, so the value has to come from you. $benefit $(waiver_hint "$id")"
  fi
  add_finding "$id" "$key" "$ev" "$pr"
}

DEFAULT_GLOBS=("apps/web/**/*.{tsx,jsx}")
CANDIDATES=("src/app/**/*.{html,ts}" "src/**/*.vue" "app/**/*.tsx" "src/**/*.{tsx,jsx}")
t2_key "T2.webComponentGlobs" "stageParams.webComponentGlobs" \
  '(.stageParams.webComponentGlobs // []) | .[]' \
  "This glob is the whole trigger for a11y-reviewer AND the design-fidelity dimension: while it matches nothing, neither is ever routed and every review looks clean because they never ran."

DEFAULT_GLOBS=("*.{ts,tsx,js,json,md}")
CANDIDATES=("*.{ts,tsx,js,jsx,json,md}" "*.{py,md,json}" "*.{sh,md,json,yml}" "*.{go,md,json}" "*.{rs,md,toml}")
t2_key "T2.formatGlob" "stageParams.formatGlob" \
  '.stageParams.formatGlob // ""' \
  "This glob scopes the default prettier format lane: while it matches nothing, no changed file is ever format-checked."

DEFAULT_GLOBS=("apps/web/src/app/**/*.{tsx,jsx}" "apps/web/src/app/**/*.css" "apps/web/src/components/**/*.{tsx,jsx}" "apps/web/tailwind.config.{ts,js}")
CANDIDATES=("src/**/*.{tsx,jsx}" "src/**/*.vue" "app/**/*.tsx")
t2_key "T2.visualCaptureTriggerGlobs" "stageParams.visualCapture.triggerGlobs" \
  '(.stageParams.visualCapture.triggerGlobs // []) | .[]' \
  "These globs gate Stage-6 visual capture: while they match nothing, no screenshot is ever taken and a render regression ships unseen."

# --- trigger 4: internally inconsistent config (AC-4) --------------------------------------
# gates.mutation follows RUNTIME semantics, not the schema default: stages/5-implement.md
# resolves `.gates.mutation // empty` and only the literal `false` takes the off-switch
# branch, so ABSENT IS NOT FALSE. The finding text therefore states the state actually found.
MUT_STATE="$(jq -r 'if ((.gates | type) == "object") and (.gates | has("mutation"))
                    then (.gates.mutation | tostring) else "absent" end' "$CONFIG")"
if [[ -n "$REPO_ID" ]]; then
  UTS="$(jq -r --arg r "$REPO_ID" '.commands[$r].unitTestScope // ""' "$CONFIG")"
  TFL="$(jq -r --arg r "$REPO_ID" '.commands[$r].testFile // ""' "$CONFIG")"
  if [[ -n "$UTS" && -z "$TFL" ]]; then
    add_finding "T4.testfile-plumbing.$REPO_ID" "commands.$REPO_ID.testFile" \
      "commands.$REPO_ID.unitTestScope is set (\"$UTS\") but commands.$REPO_ID.testFile is null — the mutation gate has a surface to mutate and no per-spec runner to run." \
      "Set commands.$REPO_ID.testFile to the repo's per-spec runner (e.g. \"yarn vitest run {file}\"). Stage 5 fail-closes on this pair, so the gate you configured a scope for cannot run until it is set. $(waiver_hint "T4.testfile-plumbing.$REPO_ID")"
  fi
  if [[ "$MUT_STATE" != "false" && -z "$UTS" ]]; then
    mut_desc="gates.mutation is true"
    [[ "$MUT_STATE" == "absent" ]] && mut_desc="gates.mutation is absent — and absent is NOT false: only the literal \`false\` is the off-switch, so the gate is ON"
    add_finding "T4.mutation-plumbing.$REPO_ID" "commands.$REPO_ID.unitTestScope" \
      "$mut_desc, but commands.$REPO_ID.unitTestScope is null, which is a legal \"no mutation surface\" — Stage 5 prints \`gate OFF\` and proceeds." \
      "Set commands.$REPO_ID.unitTestScope to the repo's unit-test surface (e.g. \"src/**\") to get the Stage-5 mutation gate you believe you have, or set \"gates\": { \"mutation\": false } to declare the opt-out where a reader can see it. $(waiver_hint "T4.mutation-plumbing.$REPO_ID")"
  fi
else
  add_noteval "T4.commands" "commands" \
    "no topology.repos entry resolves to the evaluated root, so there is no command table to check"
fi
DESIGN_PROVIDER="$(jq -r '.design.provider // ""' "$CONFIG")"
DESIGN_LR="$(jq -r 'if ((.design | type) == "object") and (.design.liveRender != null) then "yes" else "" end' "$CONFIG")"
if [[ -n "$DESIGN_PROVIDER" && -z "$DESIGN_LR" ]]; then
  add_finding "T4.design-liverender" "design.liveRender" \
    "design.provider is \"$DESIGN_PROVIDER\" but design.liveRender is absent — the design axis is on with no render harness behind it." \
    "Add design.liveRender { command, cwd?, readyProbe? } pointing at the repo's render script. Without it the Stage-5 gate degrades to render-verify-unavailable and a lean ticket cannot arm its design lane at all (docs/live-render.md). $(waiver_hint "T4.design-liverender")"
fi

# --- trigger 5: a declared command that contradicts repo reality (AC-5) --------------------
# EVERY configured command is inspected, not just testFile: a command that never exits hangs
# Stage 6 exactly as it hangs a mutation run, so the exposure is the same wherever it sits.
#
# Resolution is deliberately NARROW. The missing-script half can produce a false FAIL on a
# perfectly valid config, and that is a worse outcome than a missed warning — so only an
# unambiguous invocation is resolved, and `<pm> <name>` without the explicit `run` verb is
# treated as ambiguous (yarn workspaces / pnpm dlx / bun x are not script invocations).
is_watcher() { # $1 = manifest script BODY → 0 when it never exits
  # A leading npx/bunx wrapper is not a category of its own — strip it so `npx vitest` is
  # judged as the `vitest` it is.
  local body="$1"
  body="${body#npx }"; body="${body#bunx }"
  local -a t=()
  read -ra t <<< "$body"
  local first="${t[0]:-}" second="${t[1]:-}" w
  case "$first" in
    vitest|vite)
      case "$second" in
        run|build|preview|optimize|bench|list) ;;
        *) return 0 ;;
      esac
      ;;
  esac
  for w in ${t[@]+"${t[@]}"}; do
    case "$w" in
      --watch|--watchAll|--watch=true|-w|nodemon) return 0 ;;
    esac
  done
  case "$1" in
    *"next dev"*|*"webpack serve"*) return 0 ;;
  esac
  return 1
}

if [[ -n "$REPO_ID" ]]; then
  MANIFEST="$ROOT_ABS/package.json"
  SCRIPTS=""
  if [[ -f "$MANIFEST" ]]; then
    SCRIPTS="$(jq -c '.scripts // {}' "$MANIFEST" 2>/dev/null)"
  fi
  if [[ -z "$SCRIPTS" ]]; then
    add_noteval "T5.$REPO_ID" "commands.$REPO_ID" \
      "no readable root package.json — there are no manifest script bodies to inspect, so no configured command was checked for a missing script or a watcher"
  else
    while IFS=$'\t' read -r slot cmd; do
      [[ -n "$slot" && -n "$cmd" ]] || continue
      toks=()
      read -ra toks <<< "$cmd"
      pm="${toks[0]:-}"
      case "$pm" in
        npm|yarn|pnpm|bun) ;;
        *) add_noteval "T5.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
             "\"$cmd\" is not an unambiguous package-manager script invocation — not resolved to a manifest script, and never flagged"
           continue ;;
      esac
      explicit_run=0; idx=1
      if [[ "${toks[1]:-}" == "run" ]]; then explicit_run=1; idx=2; fi
      name="${toks[$idx]:-}"
      if [[ -z "$name" ]]; then
        add_noteval "T5.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
          "\"$cmd\" names no script — not resolved"
        continue
      fi
      if jq -e --arg s "$name" 'has($s)' <<< "$SCRIPTS" >/dev/null 2>&1; then
        body="$(jq -r --arg s "$name" '.[$s]' <<< "$SCRIPTS")"
        if is_watcher "$body"; then
          add_finding "T5.watcher.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
            "commands.$REPO_ID.$slot is \"$cmd\", which resolves to package.json scripts.$name = \"$body\" — a watch-mode command that never exits." \
            "Point commands.$REPO_ID.$slot at a script that runs once and exits (e.g. a \`vitest run\` script), or add one. The configured command LOOKS fine; it is the manifest script underneath that hangs, so the lane that uses it blocks forever rather than failing. $(waiver_hint "T5.watcher.$REPO_ID.$slot")"
        fi
      elif [[ "$explicit_run" -eq 1 ]]; then
        add_finding "T5.missing-script.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
          "commands.$REPO_ID.$slot is \"$cmd\", but package.json has no scripts.$name." \
          "Add a \"$name\" script to package.json, or point commands.$REPO_ID.$slot at a script that exists. \`$pm run $name\` is an explicit script invocation, so this one cannot be anything else. $(waiver_hint "T5.missing-script.$REPO_ID.$slot")"
      else
        add_noteval "T5.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
          "\"$cmd\" has no explicit \`run\` verb and \"$name\" is not a manifest script — ambiguous (\`$pm $name\` may be a built-in subcommand), so it is reported rather than flagged"
      fi
    done < <(jq -r --arg r "$REPO_ID" '
      (.commands[$r] // {}) as $c
      | ( ["testFile","test","lint","typecheck","format"]
          | map(select(($c[.] // null) != null) | [., $c[.]]) )
      + ( ($c.lanes // []) | to_entries
          | map(.key as $i | ((.value.commands // []) | to_entries
              | map(["lanes.\($i).\(.key)", .value]))) | add // [] )
      + ( ($c.extraLanes // []) | to_entries
          | map(.key as $i | ((.value.commands // []) | to_entries
              | map(["extraLanes.\($i).\(.key)", .value]))) | add // [] )
      | .[] | @tsv' "$CONFIG" 2>/dev/null)
  fi
fi

jq -n \
  --argjson findings "$(json_array ${FINDINGS[@]+"${FINDINGS[@]}"})" \
  --argjson notEvaluated "$(json_array ${NOTEVAL[@]+"${NOTEVAL[@]}"})" \
  '{findings: $findings, notEvaluated: $notEvaluated}'
exit 0
