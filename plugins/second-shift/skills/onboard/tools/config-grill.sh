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
# Output: ONE JSON document on stdout — { findings: [...], notEvaluated: [...], unadopted: [...] }
# Exit:  0 always when it ran (findings are DATA, not a crash) · 3 usage/IO error
#
# A `notEvaluated` entry is never a finding: it has no proposal, cannot be waived, and must
# not block onboard's accept predicate. Callers render it informationally.
#
# An `unadopted` entry is the THIRD severity, and it exists because trigger 1 fits neither of
# the other two. A finding is a DEFECT — doctor renders it as a FAIL, which is only coherent
# because a repo can reach exit 0 by fixing it. An unadopted optional key is a DEFAULT, not a
# defect: routing it through findings[] would make every long-onboarded consumer non-zero
# forever for a capability most will never want. A notEvaluated entry is the other extreme —
# no proposal, not waivable — so it can never force a disposition. So: same object as a
# finding (id, key, evidence, proposal), waivable by the same mechanism, but doctor renders it
# as a NOTE that never touches the exit code while onboard renders it as a blocking line on
# the accept-or-edit screen. Adopt or declare, at the one moment a human is already reading
# the config.
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
UNADOPTED=()
WAIVERS="$(jq -c 'if (.grillWaivers | type) == "object" then .grillWaivers else {} end' "$CONFIG")"

add_finding() { # $1 id, $2 key, $3 evidence, $4 proposal
  jq -e --arg k "$1" 'has($k)' <<< "$WAIVERS" >/dev/null 2>&1 && return 0
  FINDINGS+=("$(jq -nc --arg id "$1" --arg key "$2" --arg ev "$3" --arg pr "$4" \
    '{id:$id, key:$key, evidence:$ev, proposal:$pr}')")
}
add_unadopted() { # $1 id, $2 key, $3 evidence, $4 proposal
  # Suppression lives HERE, not in either caller, so onboard and doctor suppress identically —
  # a waiver that silenced only one of them would let a repo look clean on the screen it was
  # typed into and stay noisy forever on the other.
  jq -e --arg k "$1" 'has($k)' <<< "$WAIVERS" >/dev/null 2>&1 && return 0
  UNADOPTED+=("$(jq -nc --arg id "$1" --arg key "$2" --arg ev "$3" --arg pr "$4" \
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
# It lands in notEvaluated[], not the unadopted[] severity: that one is for an optional key at
# its default that a human should DISPOSE of, so it is waivable and carries a proposal. A repo
# with no rendering surface has no disposition to force and nothing to propose — and onboard
# blocks on unadopted[], which would re-impose the very waiver-prose tax this removes.
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
  "This glob is the whole trigger for a11y-reviewer AND the design-fidelity dimension: while it matches nothing, neither is ever routed and every review looks clean because they never ran."

DEFAULT_GLOBS=("*.{ts,tsx,js,json,md}")
CANDIDATES=("*.{ts,tsx,js,jsx,json,md}" "*.{py,md,json}" "*.{sh,md,json,yml}" "*.{go,md,json}" "*.{rs,md,toml}")
PROBE_GLOBS=()  # universal row: every repo has files to format. Reset, not omitted — see t2_key.
t2_key "T2.formatGlob" "stageParams.formatGlob" \
  '.stageParams.formatGlob // ""' \
  "This glob scopes the default prettier format lane: while it matches nothing, no changed file is ever format-checked."

# --- trigger 4: internally inconsistent config (AC-4) --------------------------------------
# The mutation seam has ONE owner: a repo-carried `tools/mutation-sweep.sh`, which the consumer
# also RUNS — #580 deleted the green-gate lane that used to execute it, because that lane made
# the identical invocation the consumer's own PR CI already makes. The technique inside it — a
# Stryker wrapper, a per-spec harness, a shell-guard sweep — is the consumer's, and so is the
# wiring. So the detectable inconsistency is unchanged in shape: a config that DECLARES mutation
# intent while the repo carries nothing to run. What changed is only what we can promise about
# the file once it exists — nothing here executes it.
#
# gates.mutation follows RUNTIME semantics, not the schema default: only the literal `false`
# takes the off-switch branch, so ABSENT IS NOT FALSE and absent still reads as intent. The
# finding text states the state actually found.
#
# The id is kept BYTE-FOR-BYTE across this semantic change on purpose. `grillWaivers` keys on
# finding id, so minting a new one would silently void every consumer's existing waiver and
# flip a doctor-green repo to FAIL on upgrade. What the waiver means — "accepted: no mutation
# coverage here" — is continuous, which is what makes keeping the id honest rather than merely
# convenient.
#
# Scoped to the evaluated root, like every other per-repo check: a pair sibling is reported by
# the topology loop above and never reached.
MUT_STATE="$(jq -r 'if ((.gates | type) == "object") and (.gates | has("mutation"))
                    then (.gates.mutation | tostring) else "absent" end' "$CONFIG")"
SWEEP_REL="tools/mutation-sweep.sh"
HAS_SWEEP=0
[[ -f "$ROOT_ABS/$SWEEP_REL" ]] && HAS_SWEEP=1
if [[ -n "$REPO_ID" ]]; then
  # (#574 retired commands.<repo>.unitTestScope, which used to be this check's second
  # arm; the declared-intent signal is gates.mutation alone now.)
  if [[ "$HAS_SWEEP" -ne 1 ]]; then
    mut_desc=""
    if [[ "$MUT_STATE" != "false" ]]; then
      mut_desc="gates.mutation is true"
      [[ "$MUT_STATE" == "absent" ]] && mut_desc="gates.mutation is absent — and absent is NOT false: only the literal \`false\` is the off-switch, so mutation reads ON"
    fi
    if [[ -n "$mut_desc" ]]; then
      add_finding "T4.mutation-plumbing.$REPO_ID" "gates.mutation" \
        "$mut_desc — but this repo carries no $SWEEP_REL, so nothing is ever mutated. The config declares coverage the repo cannot execute." \
        "Add an executable $SWEEP_REL at the repo root and wire it on your own merge boundary — \`bash $SWEEP_REL --mode pr --base origin/<baseBranch>\` from the root is the usual invocation. Since #580 no second-shift gate runs it for you, so a sweep with no CI job of its own still mutates nothing (docs/onboarding.md). Or declare the opt-out where a reader can see it: set \"gates\": { \"mutation\": false }. $(waiver_hint "T4.mutation-plumbing.$REPO_ID")"
    fi
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
    "Add design.liveRender { command, cwd?, readyProbe? } pointing at the repo's render script. Without it a ticket cannot arm its design lane at all: the green gate renders every declared route and hashes the results into a committed receipt, and there is nothing here to render (docs/live-render.md). $(waiver_hint "T4.design-liverender")"
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

# --- trigger 1: a capability nobody ever mentioned (AC-2) -----------------------------------
# Scope is the seams onboard's question batch cannot settle. Four of the five it DOES ask about
# (design + liveRender, reviewer deltas, the review-context scaffold, the CI workflows) are
# handled by naming the benefit on those existing questions — a check here would re-nag a human
# about something they declined ten lines earlier in the same run.
#
# This trigger used to carry a SECOND row, `T1.extension-points`, which fired whenever all of
# stageWorkflows / implementDelegates / planGates were absent and proposed adopting one. #569
# retired those three keys, so the row's two exits became "adopt a seam config-lint now rejects"
# and "type a waiver" — and because onboard BLOCKS its accept-or-edit screen on an unwaived
# unadopted entry, that is a deadlock, not a nag. It is deleted rather than reworded: the
# disposition it forced ("have you considered the additive-gate seams") no longer has a subject.
#
# The mutation row below outlives it exactly as its own comment predicted it would. What is
# missing there is a FILE in the repo, not a config answer: a human can answer "yes, mutation"
# and still carry no sweep, and only the tree can say which. And it keys on
# `commands.<repo>.test` — durable config — rather than on keys the config-schema assessment
# might retire, which is what has just happened to its sibling.

# The mutation seam's DURABLE surfacing. The findings[] row above is keyed on config that may
# retire; this one is keyed on `commands.<repo>.test`, which will not, and it is deliberately
# INDEPENDENT of that row rather than suppressed by it. Coupling them would mean waiving the
# finding makes a new note appear — "fix one, another arrives" reads as a broken tool, and the
# two force genuinely different dispositions: one is "your config lies", this is "you have a
# suite and nothing checks whether it would catch anything".
#
# It rides in unadopted[], never findings[]: absence of a sweep is a legal, common state — since
# #580 nothing anywhere even looks for the file — so a doctor FAIL would take every already-green
# consumer non-zero for a capability many will never adopt. The severity philosophy outlived the
# printed skip it used to mirror: this is an adoption note, not a defect.
if [[ -n "$REPO_ID" && "$HAS_SWEEP" -ne 1 ]]; then
  TEST_CMD="$(jq -r --arg r "$REPO_ID" '.commands[$r].test // ""' "$CONFIG")"
  if [[ -n "$TEST_CMD" ]]; then
    add_unadopted "T1.mutation-sweep.$REPO_ID" "commands.$REPO_ID.test" \
      "commands.$REPO_ID.test is configured (\"$TEST_CMD\") but this repo carries no $SWEEP_REL — there is a suite, and nothing that checks whether it would catch a regression. Absence is legal and is the default, and since #580 no second-shift gate looks for the file, so nothing else will ever raise it." \
      "Adopt the seam or declare that you don't want it. Add an executable $SWEEP_REL at the repo root and give it a job on your own merge boundary — \`bash $SWEEP_REL --mode pr --base origin/<baseBranch>\` from the root is the usual invocation. What it mutates and how is yours — a Stryker wrapper, a per-spec harness, a shell-guard sweep. Wiring it is yours too: #580 retired the green-gate lane that used to run it, because that lane duplicated the PR check (docs/onboarding.md). $(waiver_hint "T1.mutation-sweep.$REPO_ID")"
  fi
fi

jq -n \
  --argjson findings "$(json_array ${FINDINGS[@]+"${FINDINGS[@]}"})" \
  --argjson notEvaluated "$(json_array ${NOTEVAL[@]+"${NOTEVAL[@]}"})" \
  --argjson unadopted "$(json_array ${UNADOPTED[@]+"${UNADOPTED[@]}"})" \
  '{findings: $findings, notEvaluated: $notEvaluated, unadopted: $unadopted}'
exit 0
