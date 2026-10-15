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
#         A finding is { id, key, evidence, proposal }, plus `value` when the proposal is an exact
#         value onboard can draft at `key` (the proposal embeds the same JSON, so a caller that
#         renders prose alone loses nothing).
# Exit:  0 always when it ran (findings are DATA, not a crash) · 3 usage/IO error
#
# Findings are ADVISORY. Both callers render them as warnings and neither blocks on them: the
# config has no key to declare a deliberate opt-out in, so a finding the consumer has weighed
# and declined must not hold a repo red forever. A `notEvaluated` entry is not a finding at all:
# it has no proposal, and callers render it informationally.
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

add_finding() { # $1 id, $2 key, $3 evidence, $4 proposal, $5 (optional) value — the exact JSON
                # the proposal sets at $2, for a caller that drafts it; a finding without one has no key
  FINDINGS+=("$(jq -nc --arg id "$1" --arg key "$2" --arg ev "$3" --arg pr "$4" --argjson v "${5:-null}" \
    '{id:$id, key:$key, evidence:$ev, proposal:$pr} + (if $v == null then {} else {value:$v} end)')")
}
add_noteval() { # $1 id, $2 key, $3 reason
  NOTEVAL+=("$(jq -nc --arg id "$1" --arg key "$2" --arg r "$3" '{id:$id, key:$key, reason:$r}')")
}
json_array() { if [[ $# -eq 0 ]]; then echo '[]'; else printf '%s\n' "$@" | jq -sc '.'; fi; }
join_c() { local out="" x; for x in "$@"; do [[ -z "$out" ]] && out="$x" || out="$out, $x"; done; printf '%s' "$out"; }

# --- the commands entry the lane reads -----------------------------------------------------
# /dev-pipeline:run's rule, mirrored: the sole `commands` key, else the key equal to the main
# checkout's directory name (a linked worktree resolves to its main checkout, as the lane's
# does). Every other entry is a different checkout's table: reported, never reached.
MAIN_NAME="$(basename "$ROOT_ABS")"
_common="$(git rev-parse --git-common-dir 2>/dev/null)" && {
  case "$_common" in /*) : ;; *) _common="$ROOT_ABS/$_common" ;; esac
  _main="$(cd "$_common/.." 2>/dev/null && pwd -P)" && MAIN_NAME="$(basename "$_main")"
}
REPO_ID="$(jq -r --arg s "$MAIN_NAME" '
  (.commands // {} | keys) as $k
  | if ($k | length) == 1 then $k[0] elif ($k | index($s)) then $s else empty end' "$CONFIG" 2>/dev/null)"
for id in $(jq -r '(.commands // {}) | keys[]' "$CONFIG" 2>/dev/null); do
  [[ "$id" == "$REPO_ID" ]] && continue
  if [[ -z "$REPO_ID" ]]; then
    add_noteval "commands.$id" "commands.$id" \
      "commands has more than one entry and none is named after this checkout's directory (\"$MAIN_NAME\") — /dev-pipeline:run reads no configured check here; no command was inspected"
  else
    add_noteval "commands.$id" "commands.$id" \
      "not the entry /dev-pipeline:run reads from this checkout (it reads commands.$REPO_ID) — grill it from the checkout named \"$id\""
  fi
done

# --- glob → ERE (AC-3) --------------------------------------------------------------------
# bash 3.2 has no `globstar`, and `git ls-files` pathspec globbing does not brace-expand, so
# neither shell globbing nor git can match these patterns. Transliterate and grep instead.
#
# A pattern containing "/" is path-shaped: "*" stops at a separator, "**" crosses them.
# A pattern with NO "/" (the applicability probe's shape) is matched with "*" crossing
# separators, so an extension-only pattern counts a file at any depth. Using [^/]* there would
# match only root-level files.
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
# One row: reviewers.webComponentGlobs, the trigger review-lead routes a11y-reviewer and the
# design-fidelity dimension on. It fires on BOTH an absent key whose resolved default matches
# nothing AND a hand-set value that matches nothing: an adopted value can itself be broken, so
# setting the key wrongly must not silence the check.
#
# ...UNLESS nothing in the tree matches the row's APPLICABILITY PROBE. "This repo renders
# nothing" is a terminal fact rather than a config omission, and one the tracked-file list
# already in hand can measure, so it lands in notEvaluated[] with nothing to propose.
#
# The DEFAULT below is the RUNTIME-resolved literal — the fallback review-lead actually
# applies — never the JSON Schema `default`, which nothing injects into a config.
t2_key() { # $1 id, $2 key, $3 jq expr yielding the configured globs (empty when unset),
           # $4 benefit sentence; DEFAULT_GLOBS[], CANDIDATES[] and PROBE_GLOBS[] must be set by
           # the caller
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
      "no tracked file matches this capability's applicability probe ($(join_c "${PROBE_GLOBS[@]}")) — the surface this key scopes does not exist in this repo, so there is no value to propose"
    return 0
  fi
  for cand in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
    cn="$(count_glob_matches "$cand")"
    if [[ "$cn" -gt 0 ]]; then alt="$cand"; altn="$cn"; break; fi
  done
  ev="$key — $src ($(join_c "${globs[@]}")) matches 0 of the repo's tracked files."
  if [[ -n "$alt" ]]; then
    pr="Set $key to this repo's real surface: \"$alt\" matches $altn tracked file(s). $benefit"
  else
    pr="Set $key to this repo's real surface — no candidate from the shipped list matched any tracked file either, so the value has to come from you. $benefit"
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
t2_key "T2.webComponentGlobs" "reviewers.webComponentGlobs" \
  '(.reviewers.webComponentGlobs // []) | .[]' \
  "This glob is the trigger for a11y-reviewer AND the design-fidelity dimension (on a pipeline round a11y-reviewer also needs an opt-in): while it matches nothing, neither is ever routed and every review looks clean because they never ran."

# --- trigger 4: internally inconsistent config (AC-4) --------------------------------------
# design.provider declared with no design.liveRender behind it: the design axis is on with no
# render harness behind it, so a ticket that declares design frames has nothing to render.
DESIGN_PROVIDER="$(jq -r '.design.provider // ""' "$CONFIG")"
DESIGN_LR="$(jq -r 'if ((.design | type) == "object") and (.design.liveRender != null) then "yes" else "" end' "$CONFIG")"
if [[ -n "$DESIGN_PROVIDER" && -z "$DESIGN_LR" ]]; then
  # APPLICABILITY FIRST — the same probe trigger 2 applies, for the same reason: a root with no
  # rendering surface (a backend whose frontend is another checkout) has no render harness to
  # propose. Suppression requires CONFIDENCE, so it is gated on a readable work tree: outside
  # one the probe cannot speak and the finding stands — over-firing is the cheaper error.
  if [[ "$TRACKED_OK" -eq 1 ]] && [[ "$(count_glob_matches "${WEB_SURFACE_PROBE[@]}")" -eq 0 ]]; then
    add_noteval "T4.design-liverender" "design.liveRender" \
      "no tracked file matches the rendering-surface probe ($(join_c "${WEB_SURFACE_PROBE[@]}")) — this root has nothing to render, so the render harness belongs to another checkout and there is no value to propose here; grill it from the root that owns the surface"
  else
    add_finding "T4.design-liverender" "design.liveRender" \
      "design.provider is \"$DESIGN_PROVIDER\" but design.liveRender is absent — the design axis is on with no render harness behind it." \
      "Add design.liveRender { command, smokeCommand, readyProbe? } pointing at the repo's render and smoke scripts. Without it a ticket whose record declares design frames stops the run: after every build /dev-pipeline:run renders each declared route and checks it shows its must-show value, and there is nothing here to render with (docs/live-render.md)."
  fi
fi

# --- trigger 5: a declared command that contradicts repo reality (AC-5) --------------------
# EVERY configured command is inspected: a command that never exits hangs the verify lane,
# so the exposure is the same wherever it sits.
#
# Resolution is deliberately NARROW. The missing-script half can produce a false finding on a
# perfectly valid config, and that is a worse outcome than a missed warning — so only an
# unambiguous invocation is resolved, and `<pm> <name>` without the explicit `run` verb is
# treated as ambiguous (yarn workspaces / pnpm dlx / bun x are not script invocations).
#
# The watcher half carries the SAME principle as the missing-script half, and the two
# qualifications below are what make it hold. `-w` is a watch flag only on runners that define
# it as one: on prettier it is `--write`, so an unqualified `-w` rule turns `prettier -w .`
# into a warning on a perfectly valid config that the consumer can do nothing about. Likewise
# `--run` is the flag spelling of vitest's `run` subcommand and exits exactly as it does. Both
# qualifications only ever REDUCE firing; a missed warning is the cheaper error here.
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
            "Point commands.$REPO_ID.$slot at a script that runs once and exits (e.g. a \`vitest run\` script), or add one. The configured command LOOKS fine; it is the manifest script underneath that hangs, so the run that executes it as a check hangs rather than failing."
        fi
      elif [[ "$explicit_run" -eq 1 ]]; then
        add_finding "T5.missing-script.$REPO_ID.$slot" "commands.$REPO_ID.$slot" \
          "commands.$REPO_ID.$slot is \"$cmd\", but package.json has no scripts.$name." \
          "Add a \"$name\" script to package.json, or point commands.$REPO_ID.$slot at a script that exists. \`$pm run $name\` is an explicit script invocation, so this one cannot be anything else."
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

# --- trigger 6: the fails-without-the-change check is off on a vitest or jest repo (#1063) ---
# /dev-pipeline:run runs that check only through commands.<id>.testRunners, and reads it as
# `.testRunners[]? | objects`: unset or empty, every run reports the check not-applicable. A root
# manifest that depends on exactly one of vitest and jest makes the entry mechanical — config-lint
# fixes the format's flags — so the finding carries the whole entry as its `value`.
#
# `when` is the runner's DEFAULT test-file pattern written as run.sh matches `when`: a bash `case`
# pattern, `*` crossing `/`, no braces — one pattern per suffix. The suffixes are the extensions
# the defaults' `?([mc])[jt]s?(x)` names that exist (the cjsx/mjsx/ctsx/mtsx spellings it also
# admits are not files anyone writes). Runner config files are named, never parsed into globs.
T6_EXTS="js jsx ts tsx mjs cjs mts cts"

t6_lock_version() { # $1 runner → "<version>[, <version>…] (<lockfile>)", or "version unresolved: <why>"
  local r="$1" lock="" v=""
  # detect.sh's precedence (yarn, then pnpm, then npm), so the version is read from the lockfile
  # the package manager the entry calls through also reads.
  if [[ -f yarn.lock ]]; then
    lock=yarn.lock
    # v1: `vitest@^1.6.0, vitest@^1.0.0:` then `  version "1.6.1"`; berry: `"vitest@npm:^3.2.4":`
    # then `  version: 3.2.4`. A spec must START with `<runner>@`, so `@vitest/ui@…` and
    # `jest-cli@…` are not the runner.
    v="$(awk -v r="$1" '
      /^[^ #]/ { want = 0; n = split($0, s, /, */)
                 for (i = 1; i <= n; i++) { x = s[i]; gsub(/"/, "", x); if (index(x, r "@") == 1) want = 1 }
                 next }
      want && /^  version:? / { x = $2; gsub(/"/, "", x); print x; want = 0 }' yarn.lock)"
  elif [[ -f pnpm-lock.yaml ]]; then
    lock=pnpm-lock.yaml
    # The packages keys: `  vitest@2.1.8:` (v9), `  /vitest@1.0.0(…):` (v6), `  /vitest/0.34.6:` (v5).
    v="$(grep -oE "^  ['\"]?/?${r}[@/][0-9][^:('\" ]*" pnpm-lock.yaml | sed -E "s|^  ['\"]?/?${r}[@/]||")"
  elif [[ -f package-lock.json ]]; then
    lock=package-lock.json
    v="$(jq -r --arg r "$r" '(.packages["node_modules/" + $r].version // .dependencies[$r].version // empty)' \
      package-lock.json 2>/dev/null)"
  else
    printf 'version unresolved: no yarn.lock, pnpm-lock.yaml or package-lock.json'; return 0
  fi
  v="$(printf '%s\n' "$v" | awk 'NF' | sort -u | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  if [[ -n "$v" ]]; then printf '%s (%s)' "$v" "$lock"; else printf 'version unresolved: %s names no %s package' "$lock" "$r"; fi
}

t6_script_of() { # $1 configured command → the manifest script it calls, or nothing
  # npm reaches a script only through `run`/`run-script`, or `test`/`t`; `bun test` is bun's own
  # runner, so bun needs `run`; yarn and pnpm run `<pm> <name>` as the script when one exists.
  local -a t=()
  read -ra t <<< "$1"
  local a="${t[1]:-}" b="${t[2]:-}" name=""
  case "${t[0]:-}" in
    npm) case "$a" in run|run-script) name="$b" ;; test|t) name="test" ;; esac ;;
    yarn|pnpm) if [[ "$a" == run ]]; then name="$b"; else name="$a"; fi ;;
    bun) [[ "$a" == run ]] && name="$b" ;;
  esac
  [[ -n "$name" ]] && jq -e --arg s "$name" 'has($s)' <<< "$SCRIPTS" >/dev/null 2>&1 && printf '%s' "$name"
  return 0
}

t6_body_is_runner() { # $1 script body, $2 runner → 0 when the body IS one exiting run of the runner
  case "$1" in *'&&'*|*'|'*|*';'*) return 1 ;; esac
  local -a t=()
  read -ra t <<< "$1"
  local i=0 w
  while [[ "$i" -lt "${#t[@]}" ]] && [[ "${t[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
  case "${t[$i]:-}" in npx|bunx) i=$((i + 1)) ;; esac
  [[ "${t[$i]:-}" == "$2" ]] || return 1
  is_watcher "${t[*]:$i}" && return 1
  # A body that already sets a report flag would carry it twice once the format's flags are
  # appended, so it is called directly instead.
  for w in "${t[@]:$i}"; do
    case "$w" in --reporter*|--outputFile*|--json|--bail*) return 1 ;; esac
  done
  return 0
}

t6_count() { # $@ globs → the tracked files at least one of them matches, as run.sh's runner_for matches `when`
  local f g n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    for g in "$@"; do
      # shellcheck disable=SC2254  # $g IS a glob, matched as run.sh matches `when`
      case "$f" in $g) n=$((n + 1)); break ;; esac
    done
  done <<< "$(printf '%s\n' "$TRACKED" | grep -E '\.[cm]?[jt]sx?$')"
  printf '%s' "$n"
}

if [[ -n "$REPO_ID" ]] && ! jq -e --arg r "$REPO_ID" '[.commands[$r].testRunners[]? | objects] | length > 0' "$CONFIG" >/dev/null 2>&1; then
  T6_ID="T6.testRunners.$REPO_ID"; T6_KEY="commands.$REPO_ID.testRunners"
  T6_RUNNERS=""
  [[ -n "$SCRIPTS" ]] && T6_RUNNERS="$(jq -r '[(.dependencies, .devDependencies) | objects | keys[]
      | select(. == "vitest" or . == "jest")] | unique | join(" ")' "$MANIFEST" 2>/dev/null)"
  if [[ -z "$SCRIPTS" ]]; then
    add_noteval "$T6_ID" "$T6_KEY" \
      "no readable root package.json — there is no vitest or jest dependency to read, so no testRunners entry is proposed"
  elif [[ -z "$T6_RUNNERS" ]]; then
    add_noteval "$T6_ID" "$T6_KEY" \
      "the root package.json depends on neither vitest nor jest (dependencies, devDependencies; workspace packages are not read) — no testRunners entry is proposed"
  elif [[ "$T6_RUNNERS" == *" "* ]]; then
    add_noteval "$T6_ID" "$T6_KEY" \
      "the root package.json depends on both vitest and jest — which one runs a tagged test file cannot be told from the manifest, so no testRunners entry is proposed"
  elif [[ "$TRACKED_OK" -ne 1 ]]; then
    add_noteval "$T6_ID" "$T6_KEY" \
      "not a git work tree — tracked files cannot be counted against the proposed when globs, so no testRunners entry is proposed"
  else
    r="$T6_RUNNERS"
    if [[ "$r" == vitest ]]; then
      t6_fmt=vitest-json; t6_flags="--reporter=json --outputFile={report} --bail=0 {files}"
    else
      t6_fmt=jest-json; t6_flags="--json --outputFile={report} --runTestsByPath --bail=0 {files}"
    fi
    # The command: the configured test command when the script it calls IS the runner, else the
    # runner through the package manager — detect.sh's precedence, npm (npx) without a lockfile.
    t6_test="$(jq -r --arg r "$REPO_ID" '.commands[$r].test // "" | strings' "$CONFIG" 2>/dev/null)"
    t6_script=""; [[ -n "$t6_test" ]] && t6_script="$(t6_script_of "$t6_test")"
    t6_body=""; [[ -n "$t6_script" ]] && t6_body="$(jq -r --arg s "$t6_script" '.[$s]' <<< "$SCRIPTS")"
    if [[ -n "$t6_body" ]] && t6_body_is_runner "$t6_body" "$r"; then
      t6_sep=""
      if [[ "$t6_test" == npm\ * ]] && [[ " $t6_test " != *" -- "* ]]; then t6_sep="-- "; fi
      t6_cmd="$t6_test $t6_sep$t6_flags"
      t6_how="The proposed command extends commands.$REPO_ID.test (\"$t6_test\"), whose scripts.$t6_script = \"$t6_body\" is one run of $r."
    else
      t6_sub=""; [[ "$r" == vitest ]] && t6_sub=" run"
      if [[ -f yarn.lock ]]; then t6_pm=yarn; t6_cmd="yarn $r$t6_sub $t6_flags"
      elif [[ -f pnpm-lock.yaml ]]; then t6_pm=pnpm; t6_cmd="pnpm exec $r$t6_sub $t6_flags"
      else t6_pm=npm; t6_cmd="npx $r$t6_sub $t6_flags"; fi
      if [[ -z "$t6_test" ]]; then t6_why="commands.$REPO_ID.test is not set"
      elif [[ -z "$t6_script" ]]; then t6_why="commands.$REPO_ID.test (\"$t6_test\") calls no root package.json script"
      else t6_why="commands.$REPO_ID.test (\"$t6_test\") calls scripts.$t6_script = \"$t6_body\", which is not one plain run of $r"; fi
      t6_how="The proposed command calls $r through $t6_pm: $t6_why."
    fi
    t6_globs=()
    for t6_pat in "*.test." "*.spec."; do
      for t6_ext in $T6_EXTS; do t6_globs+=("$t6_pat$t6_ext"); done
    done
    if [[ "$r" == jest ]]; then
      for t6_ext in $T6_EXTS; do t6_globs+=("*__tests__/*.$t6_ext"); done
    fi
    t6_n="$(t6_count "${t6_globs[@]}")"
    t6_val="$(printf '%s\n' "${t6_globs[@]}" | jq -R . | jq -sc --arg f "$t6_fmt" --arg c "$t6_cmd" \
      '{when: ., format: $f, command: $c}')"
    # A runner config can move the test files away from the default pattern; it is named, not read.
    t6_cfgs=()
    if [[ "$r" == jest ]]; then
      for t6_f in jest.config.*; do [[ -f "$t6_f" ]] && t6_cfgs+=("$t6_f"); done
      jq -e 'has("jest")' "$MANIFEST" >/dev/null 2>&1 && t6_cfgs+=("the \"jest\" key in package.json")
    else
      for t6_f in vitest.config.* vitest.workspace.*; do [[ -f "$t6_f" ]] && t6_cfgs+=("$t6_f"); done
      for t6_f in vite.config.*; do
        [[ -f "$t6_f" ]] && grep -qE '(^|[^A-Za-z0-9_$.])test[[:space:]]*:' "$t6_f" && t6_cfgs+=("$t6_f (a test: block)")
      done
    fi
    # A second suite — another script running the same runner with its own config — keeps its own
    # test files, which the single proposed entry does not reach.
    t6_suites=()
    while IFS=$'\t' read -r t6_name t6_sbody; do
      [[ -n "$t6_name" && "$t6_name" != "$t6_script" ]] || continue
      t6_toks=()
      read -ra t6_toks <<< "$t6_sbody"
      t6_has_r=0; t6_has_c=0
      for t6_w in ${t6_toks[@]+"${t6_toks[@]}"}; do
        [[ "$t6_w" == "$r" ]] && t6_has_r=1
        case "$t6_w" in --config|--config=*|-c) t6_has_c=1 ;; esac
      done
      [[ "$t6_has_r" -eq 1 && "$t6_has_c" -eq 1 ]] && t6_suites+=("scripts.$t6_name (\"$t6_sbody\")")
    done < <(jq -r 'to_entries[] | select(.value | type == "string") | [.key, .value] | @tsv' <<< "$SCRIPTS" 2>/dev/null)
    t6_ev="$T6_KEY has no entry, so /dev-pipeline:run reports the fails-without-the-change check not-applicable on every run. The root package.json depends on $r, $(t6_lock_version "$r"). $t6_how The when globs ($r's default test-file pattern) match $t6_n tracked file(s)."
    if [[ "${#t6_cfgs[@]}" -gt 0 ]]; then
      t6_ev="$t6_ev Runner config: $(join_c "${t6_cfgs[@]}") — the globs assume $r's default test-file pattern, so check them against it."
    fi
    if [[ "${#t6_suites[@]}" -gt 0 ]]; then
      t6_ev="$t6_ev Not covered by the proposed entry: $(join_c "${t6_suites[@]}") — each runs $r with its own config, so its test files may sit outside the default pattern."
    fi
    t6_benefit="With it, each run applies the build's tagged test files onto the record commit's tree and proves every named test fails there; a test that passes without the change does not test it. The plan then names each tagged test as file::case."
    if [[ "$t6_n" -gt 0 ]]; then
      add_finding "$T6_ID" "$T6_KEY" "$t6_ev" "Add this entry to $T6_KEY: $t6_val. $t6_benefit" "$t6_val"
    else
      add_finding "$T6_ID" "$T6_KEY" "$t6_ev" \
        "Add a $t6_fmt entry to $T6_KEY with the command \"$t6_cmd\" — its when globs have to come from you: $r's default test-file pattern matches no tracked file, and an entry whose globs match no test file leaves every tagged test file red. $t6_benefit"
    fi
  fi
fi

jq -n \
  --argjson findings "$(json_array ${FINDINGS[@]+"${FINDINGS[@]}"})" \
  --argjson notEvaluated "$(json_array ${NOTEVAL[@]+"${NOTEVAL[@]}"})" \
  '{findings: $findings, notEvaluated: $notEvaluated}'
exit 0
