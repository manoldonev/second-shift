#!/usr/bin/env bash
# scope-shadows.sh — which @second-shift plugins are served by a USER-scope install record,
# and which project-scope records at a given repo root are therefore redundant.
#
# Three consumers share this one answer, because until it existed each of them decided the
# question for itself and they disagreed: doctor.sh resolved a user-scope record as satisfying
# the lockfile and then prescribed a project-scope install anyway, onboard printed the same
# install line for a plugin user scope already served, and local-dev-refresh's Step 4
# uninstall+reinstall PRESERVED the redundant record at a fresh version. The project record it
# minted then rots, because only the CURRENT repo is ever realigned — so nobody chooses the
# version it drifts to.
#
# The EXIT STATUS is the point. Step 4's precondition is a machine-checkable signal it cannot
# walk past, not a sentence in a skill file that is trusted to be followed. A `--shadowed-records`
# flag on doctor could not have carried it: doctor hard-exits when the repo has no valid
# lockfile, and local-dev-refresh is machine-wide and runs in lockfile-less repos — exactly the
# ones with nothing else to protect them. This helper reads no lockfile.
#
# A `local`-scope record is never reported. Per docs/team-rollout.md it is the sanctioned
# per-developer override lever (a user-scope `false` cannot beat a project-level enable; local
# scope can), so a local record shadowing a project one is the documented mechanism working, not
# redundancy.
#
# Env injection (selftest): DOCTOR_PLUGIN_LIST_FILE, DOCTOR_REPO_ROOT — deliberately doctor's
# own names, so a child of doctor.sh inherits its injections and the paired suite stays hermetic
# (no claude binary, no network) exactly as doctor-selftest.sh is.
set -uo pipefail

MKT="second-shift"
ROOT_ARG=""
usage() {
  echo "usage: scope-shadows.sh [--root <dir>] [--marketplace <name>] [<plugin> ...]"
  echo "  Emits one TAB-separated row per classified plugin, ordered by plugin id:"
  echo "    shadowed<TAB><plugin><TAB><project-version><TAB><user-version>"
  echo "    user-served<TAB><plugin><TAB>-<TAB><user-version>"
  echo "  exit 0 = at least one shadowed record; 1 = none; 2 = usage/data error."
  echo "  With no <plugin> names, every @<marketplace> record is classified."
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_ARG="${2:-}"; [[ -n "$ROOT_ARG" ]] || { echo "[scope-shadows] --root needs a value" >&2; exit 2; }; shift 2 ;;
    --marketplace) MKT="${2:-}"; [[ -n "$MKT" ]] || { echo "[scope-shadows] --marketplace needs a value" >&2; exit 2; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "[scope-shadows] unknown argument: $1 (try --help)" >&2; exit 2 ;;
    *) break ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[scope-shadows] jq missing" >&2; exit 2; }
ROOT="${ROOT_ARG:-${DOCTOR_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

if [[ -n "${DOCTOR_PLUGIN_LIST_FILE:-}" ]]; then PLUGLIST="$(cat "$DOCTOR_PLUGIN_LIST_FILE")"
else PLUGLIST="$(claude plugin list --json 2>/dev/null)" || PLUGLIST="[]"; fi

# An empty WANT means "every plugin". Built with `jq -Rn '[inputs]'` rather than a shell loop so
# a name carrying whitespace survives; the `$# -gt 0` guard is what keeps a zero-arg call from
# becoming the one-empty-string list `printf` would otherwise produce.
if [[ $# -gt 0 ]]; then WANT="$(printf '%s\n' "$@" | jq -Rn '[inputs]')"; else WANT="[]"; fi

# group_by(.id) both dedupes the per-plugin work and fixes the output order (jq sorts the groups),
# so callers get a stable listing without a downstream sort. Within a scope the newest record by
# `lastUpdated` wins — the tie-break only matters for a malformed list carrying two records of the
# same scope for one id, which the resolver below must still answer deterministically.
rows="$(jq -r --arg mkt "$MKT" --arg root "$ROOT" --argjson want "$WANT" '
  [ .[] | select(.id | endswith("@" + $mkt)) ]
  | group_by(.id)
  | map(
      (.[0].id | rtrimstr("@" + $mkt)) as $p
      | select(($want | length) == 0 or ($p | IN($want[])))
      | ((map(select(.scope == "user"))    | sort_by(.lastUpdated // "") | last) // null) as $u
      | ((map(select(.scope == "project" and ((.projectPath // "") == $root)))
                                           | sort_by(.lastUpdated // "") | last) // null) as $j
      | if   $u == null then empty
        elif $j != null then "shadowed\t\($p)\t\($j.version)\t\($u.version)"
        else                 "user-served\t\($p)\t-\t\($u.version)"
        end
    )
  | .[]' <<< "$PLUGLIST" 2>/dev/null)" || { echo "[scope-shadows] could not read the plugin list" >&2; exit 2; }

[[ -n "$rows" ]] && printf '%s\n' "$rows"
# `cut -f1` (TAB is its default delimiter) rather than a pattern carrying a literal tab, which
# is the kind of byte an editor silently converts.
cut -f1 <<< "$rows" | grep -qx shadowed && exit 0
exit 1
