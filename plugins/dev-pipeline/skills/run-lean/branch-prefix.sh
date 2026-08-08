#!/usr/bin/env bash
# branch-prefix.sh — the ONE resolver for the work-branch namespace (#413).
#
# WHY THIS EXISTS. `<branchPrefix><key>` is the branch formula both lanes use, and both used to
# resolve `branchPrefix` themselves with a `cfg '.tracker.branchPrefix' 'claude/acme-'` fallback.
# That fallback is a defect, not a convenience: a consumer who never set the key got the
# PLACEHOLDER org slug written into real branch names, and nothing in the run could tell the
# operator that a namespace had been guessed. Detection was specified for the staged lane
# (stages/2-worktree.md, tools/tracker/jira/README.md) and never implemented anywhere.
#
# THE RESOLUTION ORDER, and why the last rung is a failure rather than a default:
#   1. the configured `tracker.branchPrefix`, when set — always wins, no scan;
#   2. otherwise the DOMINANT prefix among existing remote branches;
#   3. otherwise FAIL, naming every candidate considered and its vote count.
# An autonomous lane that guesses a namespace writes the wrong branch and nobody notices until
# the PR is open, so rung 3 refuses instead. There is no rung that returns a placeholder.
#
# WHAT COUNTS AS A VOTE. A remote branch votes only when its own name parses as
# `<prefix><key>` for THIS repo's tracker — a numeric key under github, `tracker.keyPattern`
# (case-insensitively, since jira branch keys are lowercased) under jira — and only when the
# name has exactly one path segment after the identifier. `release/1.2.0`,
# `dependabot/npm_and_yarn/x-1.2.3` and `fix/some-branch` therefore cast no vote at all, rather
# than voting for a namespace no ticket ever lands in.
#
# DOMINANCE IS STRICT PLURALITY. The winner is the unique prefix with the strictly highest vote
# count. Zero candidates is a failure; so is a tie at the top — "dominant" that cannot name one
# answer is not an answer, and picking either side of a tie is the silent guess this file
# exists to remove. Both take the same failure path, which prints the whole tally.
#
# Usage (executed):
#   branch-prefix.sh [--configured <prefix>] [--tracker github|jira]
#                    [--key-pattern <ere>] [--repo <dir>]
# Usage (sourced): defines resolve_branch_prefix() and nothing else.
#   resolve_branch_prefix <configured> <tracker-type> <key-pattern> [<repo-dir>]
#
# Exit / return: 0 = resolved (printed on stdout); 2 = unresolvable (diagnostic on stderr).
#
# macOS ships /bin/bash 3.2; this file stays 3.2-compatible (no associative arrays).

# The trailing digit run of a github branch's key segment, and the jira key match. Kept as one
# helper so the two trackers' parses sit side by side rather than in separate branches of a
# caller.
_bp_candidate() { # _bp_candidate <ref> <tracker> <key-pattern>   -> prints the prefix, or fails
  local ref="$1" tracker="$2" key_re="$3" ident rest key
  case "$ref" in */*) : ;; *) return 1 ;; esac
  ident="${ref%%/*}/"
  rest="${ref#*/}"
  # More than one segment after the identifier is a tool namespace (dependabot, renovate),
  # never a work branch.
  case "$rest" in */*) return 1 ;; esac
  if [ "$tracker" = "jira" ]; then
    printf '%s' "$rest" | grep -qiE "^($key_re)$" || return 1
    printf '%s\n' "$ident"
    return 0
  fi
  # github: `<slug->?<digits>`. The optional slug group must end in `-`, so a branch whose
  # name merely CONTAINS digits (`fix/v2-cleanup`) does not parse.
  printf '%s' "$rest" | grep -qE '^([A-Za-z0-9._-]+-)?[0-9]+$' || return 1
  # `##*[!0-9]` strips the longest prefix ending in a non-digit, leaving the trailing digit
  # run — and leaves an all-digits `rest` untouched, which is the bare `<ident>/<n>` shape.
  key="${rest##*[!0-9]}"
  printf '%s\n' "$ident${rest%"$key"}"
}

resolve_branch_prefix() { # resolve_branch_prefix <configured> <tracker> <key-pattern> [<repo>]
  local configured="${1:-}" tracker="${2:-github}" key_pattern="${3:-}" repo="${4:-.}"
  local key_re votes="" ref cand tally top_n winners n_win

  if [ -n "$configured" ]; then
    printf '%s\n' "$configured"
    return 0
  fi

  case "$tracker" in
    jira) key_re="${key_pattern:-[A-Za-z]+-[0-9]+}" ;;
    *)    key_re='[0-9]+' ;;
  esac

  # `for-each-ref … refname:strip=3` rather than `git branch -r`: it drops exactly
  # `refs/remotes/<remote>/`, whatever the remote is called, where stripping "the first
  # segment" of `git branch -r` output assumes the remote is named `origin`. Same data, same
  # `--sort=-committerdate` ordering, exact peeling.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    cand="$(_bp_candidate "$ref" "$tracker" "$key_re")" || continue
    votes="$votes$cand
"
  done < <(git -C "$repo" for-each-ref --sort=-committerdate \
             --format='%(refname:strip=3)' refs/remotes 2>/dev/null)

  tally="$(printf '%s' "$votes" | grep -v '^$' | sort | uniq -c | sort -rn -k1,1)"

  if [ -z "$tally" ]; then
    echo "[branch-prefix] tracker.branchPrefix is unset and no remote branch parses as '<prefix><key>' for tracker '$tracker' — refusing to guess a namespace. Set tracker.branchPrefix in .claude/second-shift.config.json." >&2
    return 2
  fi

  top_n="$(printf '%s\n' "$tally" | head -n1 | awk '{print $1}')"
  winners="$(printf '%s\n' "$tally" | awk -v n="$top_n" '$1 == n { print $2 }')"
  n_win="$(printf '%s\n' "$winners" | grep -c .)" || n_win=0

  if [ "$n_win" -ne 1 ]; then
    echo "[branch-prefix] tracker.branchPrefix is unset and no single prefix dominates the remote branches — refusing to guess. Candidates considered (count prefix):" >&2
    printf '%s\n' "$tally" | sed 's/^/[branch-prefix]   /' >&2
    echo "[branch-prefix] Set tracker.branchPrefix in .claude/second-shift.config.json." >&2
    return 2
  fi

  printf '%s\n' "$winners"
}

# Sourced ⇒ definitions only. Executed ⇒ the CLI the selftest and any operator drives.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  _cfgd=""; _tracker="github"; _keypat=""; _repo="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --configured)  _cfgd="${2:-}"; shift 2 ;;
      --tracker)     _tracker="${2:-}"; shift 2 ;;
      --key-pattern) _keypat="${2:-}"; shift 2 ;;
      --repo)        _repo="${2:-}"; shift 2 ;;
      -h|--help)     sed -n '2,35p' "$0"; exit 0 ;;
      *) echo "branch-prefix.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
  resolve_branch_prefix "$_cfgd" "$_tracker" "$_keypat" "$_repo"
  exit $?
fi
