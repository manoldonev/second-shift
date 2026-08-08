#!/usr/bin/env bash
# detect.sh — provenance-first consumer-repo detection for /second-shift:onboard.
# Emits ONE JSON document on stdout; every field carries its evidence ("source").
# Never asks, never guesses: an undetectable value is null/"" with source
# "undetected" — the onboard skill decides whether that means ask or abort.
# Read-only: no writes, no repo mutation. bash-3.2-safe.
#
# Usage: detect.sh [repo-root]     Exit: 0 ok · 3 usage/not-a-git-repo
# Selftest env hooks: DETECT_SKIP_GH, DETECT_SKIP_MCP, DETECT_SKIP_LSREMOTE
set -uo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT" 2>/dev/null || { echo "detect: no such dir: $ROOT" >&2; exit 3; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "detect: not a git repo: $ROOT" >&2; exit 3; }
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT" || exit 3

# --- git provenance --------------------------------------------------------
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
ORIGIN_HOST=""
case "$ORIGIN_URL" in
  git@*)  ORIGIN_HOST="${ORIGIN_URL#git@}"; ORIGIN_HOST="${ORIGIN_HOST%%:*}" ;;
  ssh://*|http://*|https://*) ORIGIN_HOST="${ORIGIN_URL#*://}"; ORIGIN_HOST="${ORIGIN_HOST%%/*}"; ORIGIN_HOST="${ORIGIN_HOST#*@}"; ORIGIN_HOST="${ORIGIN_HOST%%:*}" ;;
esac

BASE_BRANCH=""; BASE_SRC="undetected"
if sym="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
  BASE_BRANCH="${sym#origin/}"; BASE_SRC="origin/HEAD symbolic-ref"
elif [[ -z "${DETECT_SKIP_LSREMOTE:-}" ]]; then
  lsr="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p' | head -1)"
  if [[ -n "$lsr" ]]; then BASE_BRANCH="$lsr"; BASE_SRC="git ls-remote --symref origin HEAD"; fi
fi

# --- tracker ---------------------------------------------------------------
GH_AUTH=no
if [[ -z "${DETECT_SKIP_GH:-}" ]] && gh auth status >/dev/null 2>&1; then GH_AUTH=yes; fi
JIRA_EVIDENCE="[]"
if [[ -z "${DETECT_SKIP_MCP:-}" ]] && command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -qiE 'atlassian|jira'; then JIRA_EVIDENCE='["mcp:atlassian"]'; fi
fi
TRACKER="ambiguous"; TRACKER_SRC="origin host ${ORIGIN_HOST:-none}"
if [[ "$ORIGIN_HOST" == "github.com" && "$JIRA_EVIDENCE" == "[]" ]]; then
  TRACKER="github"; TRACKER_SRC="origin host github.com"
  [[ "$GH_AUTH" == yes ]] && TRACKER_SRC="$TRACKER_SRC + gh auth ok"
elif [[ "$ORIGIN_HOST" != "github.com" && "$JIRA_EVIDENCE" != "[]" ]]; then
  TRACKER="jira"; TRACKER_SRC="non-github origin (${ORIGIN_HOST:-none}) + Atlassian MCP configured"
fi

# --- package manager + commands ---------------------------------------------
PM=""; PM_SRC="undetected"; RUN=""
if   [[ -f yarn.lock         ]]; then PM=yarn; PM_SRC=yarn.lock;         RUN="yarn "
elif [[ -f pnpm-lock.yaml    ]]; then PM=pnpm; PM_SRC=pnpm-lock.yaml;    RUN="pnpm "
elif [[ -f package-lock.json ]]; then PM=npm;  PM_SRC=package-lock.json; RUN="npm run "
elif [[ -f package.json      ]]; then PM=npm;  PM_SRC="package.json (no lockfile)"; RUN="npm run "
fi

script_cmd() { # $1 = script name → prints command or nothing
  [[ -f package.json ]] || return 0
  local v; v="$(jq -r --arg s "$1" '.scripts[$s] // empty' package.json 2>/dev/null)"
  [[ -z "$v" || "$v" == *"Error: no test specified"* ]] && return 0
  printf '%s%s' "$RUN" "$1"
}
# Each lane carries its OWN provenance (never a fabricated one — provenance-first).
LINT="$(script_cmd lint)";       LINT_SRC="package.json scripts.lint"
TEST="$(script_cmd test)";       TEST_SRC="package.json scripts.test"
BUILD="$(script_cmd build)";     BUILD_SRC="package.json scripts.build"
FORMAT="$(script_cmd format)";   FORMAT_SRC="package.json scripts.format"
TYPECHECK="$(script_cmd typecheck)"; TC_SRC="package.json scripts.typecheck"
if [[ -z "$TYPECHECK" ]]; then TYPECHECK="$(script_cmd type-check)"; [[ -n "$TYPECHECK" ]] && TC_SRC="package.json scripts.type-check"; fi
LINT_RAW="$(jq -r '.scripts.lint // ""' package.json 2>/dev/null || true)"
LINT_AUTOFIX=false; [[ "$LINT_RAW" == *"--fix"* ]] && LINT_AUTOFIX=true
# Makefile fallback when no package.json at all
if [[ ! -f package.json && -f Makefile ]]; then
  for t in lint test build typecheck format; do
    if grep -qE "^$t:" Makefile; then
      case "$t" in
        lint) LINT="make lint"; LINT_SRC="Makefile target lint";;
        test) TEST="make test"; TEST_SRC="Makefile target test";;
        build) BUILD="make build"; BUILD_SRC="Makefile target build";;
        typecheck) TYPECHECK="make typecheck"; TC_SRC="Makefile target typecheck";;
        format) FORMAT="make format"; FORMAT_SRC="Makefile target format";;
      esac
    fi
  done
  PM="make"; PM_SRC="Makefile"
fi
cmd_json() { # $1 value, $2 source-label
  if [[ -n "$1" ]]; then jq -n --arg v "$1" --arg s "$2" '{value:$v, source:$s}'
  else jq -n '{value:null, source:"undetected"}'; fi
}

# --- topology ----------------------------------------------------------------
WORKSPACES="[]"
if [[ -f package.json ]]; then
  WORKSPACES="$(jq -c '(.workspaces // []) | if type=="object" then (.packages // []) else . end' package.json 2>/dev/null || echo '[]')"
fi
# Some repos declare `workspaces` purely to host test-scoped packages (an e2e harness,
# fixture packages) — not evidence of a genuine multi-app monorepo layout. A workspaces
# array whose every entry (glob suffix stripped) is a test-ish name shouldn't drive the
# topology decision by itself. The raw array still ships in the output below
# (provenance-first — never hide evidence); WORKSPACES_REAL is what topology
# classification keys on.
WORKSPACES_REAL="$WORKSPACES"
if [[ "$WORKSPACES" != "[]" ]]; then
  real_count="$(jq -r '
    [ .[] | sub("/\\*+$"; "") | (split("/") | last) |
      select(test("^(test|tests|__tests__|e2e|spec|specs|fixtures|testing)$"; "i") | not) ] | length
  ' <<< "$WORKSPACES" 2>/dev/null || echo 1)"
  [[ "$real_count" -eq 0 ]] && WORKSPACES_REAL="[]"
fi

BASENAME="$(basename "$ROOT")"
FE_SUFFIXES=(ui web frontend client app fe)
BE_SUFFIXES=(api be backend server service)
has_suffix() { # $1 name, $2..  suffixes
  local name="$1"; shift
  local suf
  for suf in "$@"; do case "$name" in *-"$suf") return 0 ;; esac; done
  return 1
}
strip_suffix() { # $1 name, $2.. suffixes → base with a matching trailing "-suffix" removed
  local name="$1"; shift
  local suf
  for suf in "$@"; do case "$name" in *-"$suf") printf '%s' "${name%-"$suf"}"; return 0 ;; esac; done
  printf '%s' "$name"
}
SIBLINGS="[]"
add_sibling() { # $1 = candidate dir name relative to ROOT's parent (e.g. "shop-ui")
  [[ -d "$ROOT/../$1/.git" ]] || return 0
  SIBLINGS="$(jq -c --arg c "../$1" 'if index($c) then . else . + [$c] end' <<< "$SIBLINGS")"
}
# Same-base-name convention (shop-api / shop-ui): try BOTH directions from this repo's
# own name, not just BE→FE. A BE-suffixed repo tries every FE-suffixed same-base-name
# candidate (the original direction, kept below). An FE-suffixed repo tries the BARE
# base name (e.g. shop-ui → shop — the common "bare backend, suffixed
# frontend" convention) AND every BE-suffixed same-base-name candidate; the reverse
# direction used to be unreachable, so a bare-base-name BE sibling of an FE repo was
# invisible even though it sits right next door.
BASE_NO_BE="$(strip_suffix "$BASENAME" "${BE_SUFFIXES[@]}")"
if [[ "$BASE_NO_BE" != "$BASENAME" ]]; then
  for suffix in "${FE_SUFFIXES[@]}"; do add_sibling "${BASE_NO_BE}-${suffix}"; done
fi
BASE_NO_FE="$(strip_suffix "$BASENAME" "${FE_SUFFIXES[@]}")"
if [[ "$BASE_NO_FE" != "$BASENAME" ]]; then
  add_sibling "$BASE_NO_FE"
  for suffix in "${BE_SUFFIXES[@]}"; do add_sibling "${BASE_NO_FE}-${suffix}"; done
fi
# Name-unrelated pairs (fastapi-be / vue-fe): no shared base name, so scan every
# adjacent git-repo directory for the counterpart suffix once THIS repo's own basename
# carries a recognized BE- or FE-side suffix. Still detection, not a guess: a match
# only adds a candidate for onboard's existing pair-confirm elicitation to ask about.
COUNTERPART_SUFFIXES=()
if has_suffix "$BASENAME" "${BE_SUFFIXES[@]}"; then
  COUNTERPART_SUFFIXES=("${FE_SUFFIXES[@]}")
elif has_suffix "$BASENAME" "${FE_SUFFIXES[@]}"; then
  COUNTERPART_SUFFIXES=("${BE_SUFFIXES[@]}")
fi
if [[ "${#COUNTERPART_SUFFIXES[@]}" -gt 0 && -d "$ROOT/.." ]]; then
  for d in "$ROOT"/../*/; do
    [[ -d "$d/.git" ]] || continue
    dname="$(basename "$d")"
    [[ "$dname" == "$BASENAME" ]] && continue
    has_suffix "$dname" "${COUNTERPART_SUFFIXES[@]}" && add_sibling "$dname"
  done
fi
# Sibling checkouts are the stronger signal (two actual physically-adjacent repos, not
# just a manifest field) and are checked FIRST — an `elif` here would let a (possibly
# wrong, see WORKSPACES_REAL above) monorepo classification silently swallow a real
# pair candidate that also exists on disk, never surfacing it for onboard's confirm step.
TOPOLOGY=standalone; TOPO_SRC="no workspaces manifest; no sibling candidates"
if [[ "$SIBLINGS" != "[]" ]]; then
  TOPOLOGY="be-fe-pair-candidate"; TOPO_SRC="sibling checkout(s) detected — needs confirmation"
elif [[ "$WORKSPACES_REAL" != "[]" ]]; then
  TOPOLOGY=monorepo; TOPO_SRC="package.json workspaces"
elif [[ "$WORKSPACES" != "[]" ]]; then
  TOPOLOGY=standalone; TOPO_SRC="package.json workspaces are test-only (e2e/fixtures) — not treated as monorepo evidence"
fi

# --- emit ---------------------------------------------------------------------
jq -n \
  --arg root "$ROOT" --arg ourl "$ORIGIN_URL" --arg ohost "$ORIGIN_HOST" \
  --arg bb "$BASE_BRANCH" --arg bbsrc "$BASE_SRC" \
  --arg tr "$TRACKER" --arg trsrc "$TRACKER_SRC" --argjson jira "$JIRA_EVIDENCE" \
  --arg pm "$PM" --arg pmsrc "$PM_SRC" \
  --arg topo "$TOPOLOGY" --arg toposrc "$TOPO_SRC" --argjson ws "$WORKSPACES" --argjson sib "$SIBLINGS" \
  --argjson lint  "$(cmd_json "$LINT"  "$LINT_SRC")" \
  --argjson tc    "$(cmd_json "$TYPECHECK" "$TC_SRC")" \
  --argjson test  "$(cmd_json "$TEST"  "$TEST_SRC")" \
  --argjson build "$(cmd_json "$BUILD" "$BUILD_SRC")" \
  --argjson fmt   "$(cmd_json "$FORMAT" "$FORMAT_SRC")" \
  --argjson la "$LINT_AUTOFIX" \
  '{ repoRoot: $root,
     git: { originUrl: $ourl, originHost: $ohost, baseBranch: { value: $bb, source: $bbsrc } },
     tracker: { value: $tr, source: $trsrc, jiraEvidence: $jira },
     packageManager: { value: (if $pm=="" then null else $pm end), source: $pmsrc },
     topology: { value: $topo, source: $toposrc, workspaces: $ws, siblingCandidates: $sib },
     commands: { lint: $lint, lintAutofixes: $la, typecheck: $tc, test: $test, build: $build, format: $fmt } }'
