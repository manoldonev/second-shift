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
# (A THIRD severity, `unadopted` — waivable, carrying a proposal, but a DEFAULT rather than a
# DEFECT, so doctor rendered it as a note that never touched the exit code while onboard
# blocked on it — existed for trigger 1's `T1.mutation-sweep` row. #877 retired that row's only
# reason to exist along with it, and it was the channel's only producer, so the severity and
# its `unadopted` output key went with it rather than sit empty forever.)
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
# that reproduces the bash `[[ "$f" == $a ]]` match the verify lane applies to
# this key, byte-for-byte (the key outlived its executor — D-17). Using [^/]* there would
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
#   planFilePattern   — names a file the run is about to CREATE; zero matches is universal.
#   paths.*           — directories a fresh repo legitimately lacks.
#   visualCapture.*   — dropped outright, not merely unmeasurable: no lane on the default path
#                       takes a screenshot, so a glob scoping one cannot be a gap. `extraLanes`
#                       is the consumer home for a capture lane. No key under `visualCapture`
#                       is evaluated here.
#
# Each active row fires on BOTH an absent key whose resolved default matches nothing AND a
# hand-set value that matches nothing: an adopted value can itself be broken, so setting a key
# wrongly must not silence the check.
#
# ...UNLESS the row carries an APPLICABILITY PROBE and nothing in the tree matches it. "Zero
# matches is a finding" holds for formatGlob — every repo has files to format — and breaks for
# the web-conditional row, where "this repo renders nothing" is a terminal fact rather than
# a config omission, and one the tracked-file list already in hand can measure. A shell, CLI or
# library consumer would otherwise be told to hand-author a glob for files that do not exist,
# and would answer with a waiver restating a fact the tool could see for itself.
#
# It lands in notEvaluated[], never findings[]: a repo with no rendering surface has no
# disposition to force and nothing to propose, and notEvaluated carries no proposal and cannot
# be waived — forcing one here would re-impose the very waiver-prose tax this removes.
#
# The DEFAULTS below are the RUNTIME-resolved literals — the jq fallback the consuming stage
# actually applies — never the JSON Schema `default`, which nothing injects into a config.
# Their coupling to the source sites is recorded as declined in docs/testing.md: the
# webComponentGlobs literal alone is restated at seven sites across two plugins, and one
# canonical against seven scattered restatements is not a group any relation can express.
t2_key() { # $1 id, $2 key, $3 jq expr yielding the configured globs (empty when unset),
           # $4 benefit sentence; DEFAULT_GLOBS[], CANDIDATES[] and PROBE_GLOBS[] must be set by
           # the caller — PROBE_GLOBS EVERY time, empty for a universal row, or the previous
           # call's probe leaks into this one and suppresses a row that has no probe at all
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
  # The probe is consulted only here, once the configured-or-default globs have already scored
  # zero — a key that matches is applicable by demonstration and never reaches this.
  if [[ "${#PROBE_GLOBS[@]}" -gt 0 ]] && [[ "$(count_glob_matches "${PROBE_GLOBS[@]}")" -eq 0 ]]; then
    add_noteval "$id" "$key" \
      "no tracked file matches this capability's applicability probe ($(join_c "${PROBE_GLOBS[@]}")) — the surface this key scopes does not exist in this repo, so there is no value to propose and nothing to waive"
    return 0
  fi
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

# Component and stylesheet extensions only. Bare `.ts`/`.js` are excluded ON PURPOSE: including
# them makes the probe never fire for any TypeScript repo, which defeats it. `.html` is what
# catches the Angular shape (`.ts` + template), matching the src/app/**/*.{html,ts} candidate.
# Slash-free by construction, so glob_to_ere's `*`-crosses-separators branch applies and a
# component at any depth counts. A stray tracked `.html` means the probe declines to convert and
# present behavior stands — over-firing is the safe error, so it only suppresses when confident.
WEB_SURFACE_PROBE=("*.{tsx,jsx,vue,svelte,astro,html,css,scss,sass,less}")

DEFAULT_GLOBS=("apps/web/**/*.{tsx,jsx}")
CANDIDATES=("src/app/**/*.{html,ts}" "src/**/*.vue" "app/**/*.tsx" "src/**/*.{tsx,jsx}")
PROBE_GLOBS=("${WEB_SURFACE_PROBE[@]}")
t2_key "T2.webComponentGlobs" "stageParams.webComponentGlobs" \
  '(.stageParams.webComponentGlobs // []) | .[]' \
  "This glob is the trigger for a11y-reviewer AND the design-fidelity dimension (on a pipeline round a11y-reviewer also needs an opt-in): while it matches nothing, neither is ever routed and every review looks clean because they never ran."

DEFAULT_GLOBS=("*.{ts,tsx,js,json,md}")
CANDIDATES=("*.{ts,tsx,js,jsx,json,md}" "*.{py,md,json}" "*.{sh,md,json,yml}" "*.{go,md,json}" "*.{rs,md,toml}")
PROBE_GLOBS=()  # universal row: every repo has files to format. Reset, not omitted — see t2_key.
t2_key "T2.formatGlob" "stageParams.formatGlob" \
  '.stageParams.formatGlob // ""' \
  "This glob scopes the default prettier format lane: while it matches nothing, no changed file is ever format-checked."

# --- trigger 4: internally inconsistent config (AC-4) --------------------------------------
# design.provider declared with no design.liveRender behind it: the design axis is on with no
# render harness behind it, so a ticket that arms it has nothing to render.
#
# (#877 retired this trigger's other occupant — gates.mutation graded against a repo-carried
# tools/mutation-sweep.sh — because no second-shift gate has executed that sweep since #580, so
# grading a repo's declared intent against a file nothing runs turned a doctor-green repo FAIL
# for a capability no consumer used. gates.mutation stays legal in the schema; config-lint still
# accepts it. Nothing in this file reads it any more.)
DESIGN_PROVIDER="$(jq -r '.design.provider // ""' "$CONFIG")"
DESIGN_LR="$(jq -r 'if ((.design | type) == "object") and (.design.liveRender != null) then "yes" else "" end' "$CONFIG")"
if [[ -n "$DESIGN_PROVIDER" && -z "$DESIGN_LR" ]]; then
  # APPLICABILITY FIRST — the same predicate T2's rendering-surface rows already apply, and for
  # the same reason: a root with no rendering surface has no render harness to propose and no
  # disposition to force. On a be-fe-pair the config declares the WHOLE topology, so the backend
  # repo's own config legitimately carries `design.provider` while the harness lives in the
  # sibling. Ungated, this fired a FAIL at every backend root on that shape, and the only escape
  # was a grillWaivers entry excusing a non-problem — "declare, because there is nothing to
  # adopt", which is precisely what the T2 probe exists to stop.
  #
  # #788 taught the BUILD lane this ownership rule via `design.liveRender.cwd`; that key cannot
  # settle it here, because this check fires only when `liveRender` — and so `cwd` with it — is
  # ABSENT. Tracked rendering surface is the signal that survives the key's absence, needs no
  # hardcoded "fe" topology key, and stays correct on a single-repo frontend app.
  #
  # Suppression requires CONFIDENCE, so it is gated on a readable work tree: outside one the
  # probe cannot speak and the finding stands. Retiring the design axis on a repo that does own
  # the harness would be the silent failure #788 refused, and over-firing is the cheaper error.
  if [[ "$TRACKED_OK" -eq 1 ]] && [[ "$(count_glob_matches "${WEB_SURFACE_PROBE[@]}")" -eq 0 ]]; then
    add_noteval "T4.design-liverender" "design.liveRender" \
      "no tracked file matches the rendering-surface probe ($(join_c "${WEB_SURFACE_PROBE[@]}")) — this root has nothing to render, so the render harness belongs to a sibling repo of the topology and there is no value to propose and nothing to waive here; grill it from the root that owns the surface"
  else
    add_finding "T4.design-liverender" "design.liveRender" \
      "design.provider is \"$DESIGN_PROVIDER\" but design.liveRender is absent — the design axis is on with no render harness behind it." \
      "Add design.liveRender { command, cwd?, readyProbe? } pointing at the repo's render script. Without it a ticket cannot arm its design lane at all: the green gate renders every declared route and hashes the results into a committed receipt, and there is nothing here to render (docs/live-render.md). $(waiver_hint "T4.design-liverender")"
  fi
fi

# --- trigger 5: a declared command that contradicts repo reality (AC-5) --------------------
# EVERY configured command is inspected: a command that never exits hangs the verify lane,
# so the exposure is the same wherever it sits.
#
# Resolution is deliberately NARROW. The missing-script half can produce a false FAIL on a
# perfectly valid config, and that is a worse outcome than a missed warning — so only an
# unambiguous invocation is resolved, and `<pm> <name>` without the explicit `run` verb is
# treated as ambiguous (yarn workspaces / pnpm dlx / bun x are not script invocations).
#
# The watcher half carries the SAME principle as the missing-script half, and the two
# qualifications below are what make it hold. `-w` is a watch flag only on runners that define
# it as one: on prettier it is `--write`, so an unqualified `-w` rule turns `prettier -w .`
# into a doctor FAIL on a perfectly valid config — and the only escape from that FAIL is a
# grillWaivers entry excusing a non-problem, which is not "adopt or declare", it is "declare,
# because there is nothing to adopt". Likewise `--run` is the flag spelling of vitest's `run`
# subcommand and exits exactly as it does. Both qualifications only ever REDUCE firing;
# under-firing is OR-1's subject, and a missed warning is the cheaper error here.
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
        *)
          for w in ${t[@]+"${t[@]}"}; do
            [[ "$w" == "--run" ]] && return 1
          done
          return 0 ;;
      esac
      ;;
  esac
  for w in ${t[@]+"${t[@]}"}; do
    case "$w" in
      --watch|--watchAll|--watch=true|nodemon) return 0 ;;
      -w)
        # Membership is the predicate "this runner defines -w as watch", decided per runner
        # against that runner's own CLI rather than inferred from the flag's spelling.
        # Excluded on that evidence: `jest` (-w is --maxWorkers; watch/watchAll carry no alias
        # at all), and `tsup`, `esbuild`, `parcel`, `karma` (no -w of any meaning). `nodemon`
        # is absent because the token arm above already returns for any body containing it,
        # which would leave a row here unreachable.
        case "$first" in
          vitest|vite|tsc|webpack|rollup|ava|mocha|sass) return 0 ;;
        esac
        ;;
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
      | ( ["test","lint","typecheck","format"]
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

# (Trigger 1, "a capability nobody ever mentioned", used to carry two rows: `T1.extension-points`
# — retired in #569 with the three config keys it proposed adopting — and `T1.mutation-sweep`,
# retired in #877 for the same reason config-grill.sh:252's trigger-4 row was: nothing has graded
# gates.mutation-declared intent against a repo-carried tools/mutation-sweep.sh's presence since
# #580 retired the gate that ran it, so an "adopt or declare" note about a file nothing executes
# was busywork. Trigger 1 had no other occupant, so it is gone, and with it the `unadopted[]`
# severity: it existed to hold exactly this note, and this file now emits no other unadopted
# entry to reintroduce it for.)

jq -n \
  --argjson findings "$(json_array ${FINDINGS[@]+"${FINDINGS[@]}"})" \
  --argjson notEvaluated "$(json_array ${NOTEVAL[@]+"${NOTEVAL[@]}"})" \
  '{findings: $findings, notEvaluated: $notEvaluated}'
exit 0
