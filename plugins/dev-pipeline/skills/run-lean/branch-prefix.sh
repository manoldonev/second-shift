#!/usr/bin/env bash
# branch-prefix.sh — resolve the work-branch prefix, for every lane that needs one (#413).
#
# WHY THIS EXISTS. Two lanes needed a branch namespace and each answered it differently.
# The lean harness re-rooted the configured prefix under `lean/` — a namespace no other lane
# uses, leaking the harness's internal name onto the one surface every reviewer and every
# `git branch` listing sees. And both lanes resolved an unset `tracker.branchPrefix` to the
# literal placeholder `claude/acme-`, shipping a fake org slug into real branch names.
#
# THE FORMULA IS `<branchPrefix><key>`, nothing more — the same one the staged lane spells at
# stages/2-worktree.md:31, with the key lowercased under `tracker.type: jira`
# (tools/tracker/jira/README.md). Lane identity is NOT carried on the branch name: both chain
# gates at the merge boundary discriminate on the committed lean spec instead, which is an
# artifact a PR either has or does not, rather than a constant that can go stale in CI.
#
# DETECTION, AND WHY IT FAILS LOUDLY. With `tracker.branchPrefix` unset, the prefix is detected
# from the identifier already in use on the remote — the behavior stages/2-worktree.md and the
# jira adapter README have specified since they were written, and which no script implemented.
# Detection here is NON-INTERACTIVE: the lean lane is autonomous and cannot do the staged
# lane's "confirm with the operator" round. That is exactly why an unresolvable prefix is a
# hard error naming the candidates considered, and never a fall-back: an autonomous lane that
# guesses a namespace writes the wrong branch, and nobody notices until the PR is open.
#
# WHAT VOTES (#413 D-2). Only a remote branch of the shape `<ident>/<key>` — one path segment
# then a key — where the key matches the tracker's key shape: numeric under github, the
# configured `tracker.keyPattern` under jira. Namespaces like `release/` and `dependabot/`
# therefore cast no vote, and neither does a multi-segment prefix (`claude/acme-42` is
# `<ident>/<slug>-<key>`, which detection cannot decompose — a repo using that shape must set
# `tracker.branchPrefix`, which is what this repo does).
#
# Usage:
#   branch-prefix.sh [--config <path>] [--repo-root <path>] [--branches-file <path>]
#
# Seams (zero-network, zero-remote selftest — the retro-corpus.sh / lean-gate.sh precedent):
#   SECOND_SHIFT_CONFIG / --config    the runtime config to read
#   --repo-root <path>                the checkout `git branch -r` runs in
#   --branches-file <path>            read the remote-branch listing from a fixture instead
#                                     (same raw shape `git branch -r --sort=-committerdate`
#                                     emits, `  origin/name` per line)
#
# Exit: 0 = prefix printed on stdout; 2 = usage or unresolvable-prefix error.
set -uo pipefail

CONFIG_ARG=""
ROOT_ARG=""
BRANCHES_FILE=""

fail() { echo "[branch-prefix] $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config)        CONFIG_ARG="${2:-}"; shift 2 || fail "--config needs a path." ;;
    --repo-root)     ROOT_ARG="${2:-}"; shift 2 || fail "--repo-root needs a path." ;;
    --branches-file) BRANCHES_FILE="${2:-}"; shift 2 || fail "--branches-file needs a path." ;;
    -h|--help)       sed -n '30,41p' "$0"; exit 0 ;;
    *)               fail "unknown argument '$1' (expected --config|--repo-root|--branches-file)." ;;
  esac
done

CONFIG="${CONFIG_ARG:-${SECOND_SHIFT_CONFIG:-}}"
if [ -z "$CONFIG" ]; then
  _root="${ROOT_ARG:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$_root" ] || fail "no --config given and not in a git repo — cannot locate the runtime config."
  CONFIG="$_root/.claude/second-shift.config.json"
fi

cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

# ---- (1) the configured value wins, and it is the ONLY non-detected answer ----------------
CONFIGURED="$(cfg '.tracker.branchPrefix' '')"
if [ -n "$CONFIGURED" ]; then
  printf '%s\n' "$CONFIGURED"
  exit 0
fi

# ---- (2) detection: the dominant `<ident>/` among key-shaped remote branches ---------------
# The key shape is the tracker's, not a guess. Under jira an ABSENT `tracker.keyPattern` falls
# back to the conventional JIRA shape rather than to "anything": the schema lets keyPattern be
# absent to mean "accept any non-empty key" at statectl's validation site, but "anything" is
# useless as a DETECTION filter — every `release/next` and `dependabot/npm_and_yarn` would vote.
TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github) KEY_RE='[0-9]+' ;;
  jira)   KEY_RE="$(cfg '.tracker.keyPattern' '[A-Za-z]+-[0-9]+')" ;;
  *)      fail "unknown tracker.type '$TRACKER_TYPE' — expected 'github' or 'jira'." ;;
esac

if [ -n "$BRANCHES_FILE" ]; then
  [ -f "$BRANCHES_FILE" ] || fail "--branches-file '$BRANCHES_FILE' does not exist."
  RAW="$(cat "$BRANCHES_FILE")"
else
  ROOT="${ROOT_ARG:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$ROOT" ] || fail "not in a git repo — cannot scan remote branches for a prefix."
  RAW="$(git -C "$ROOT" branch -r --sort=-committerdate 2>/dev/null)" || RAW=""
fi

SCANNED=0
VOTES=""
while IFS= read -r line; do
  # Trim; git indents each ref by two spaces.
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  # `origin/HEAD -> origin/main` is a symbolic ref, not a branch.
  case "$line" in *' -> '*) continue ;; esac
  SCANNED=$((SCANNED + 1))
  # Drop the remote name; what remains is the branch's own name.
  case "$line" in */*) name="${line#*/}" ;; *) continue ;; esac
  # A candidate is EXACTLY `<ident>/<key>`. More segments than that is a prefix shape
  # detection cannot decompose (see the header); fewer is not a namespaced branch at all.
  case "$name" in
    */*/*) continue ;;
    */*)   : ;;
    *)     continue ;;
  esac
  ident="${name%%/*}"
  key="${name#*/}"
  printf '%s' "$key" | grep -qiE "^($KEY_RE)$" || continue
  VOTES="$VOTES$ident/
"
done <<EOF
$RAW
EOF

if [ -z "$VOTES" ]; then
  scanned_names="$(printf '%s' "$RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                    | grep -v ' -> ' | grep -v '^$' | head -n 10 | tr '\n' ' ')"
  fail "cannot resolve a branch prefix: tracker.branchPrefix is unset and no remote branch has the shape <ident>/<key> (key ~ /$KEY_RE/) among $SCANNED scanned. Considered: ${scanned_names:-none}. Set tracker.branchPrefix in the runtime config."
fi

TALLY="$(printf '%s' "$VOTES" | grep -v '^$' | sort | uniq -c | sort -k1,1nr -k2,2)"
TOP_N="$(printf '%s\n' "$TALLY" | head -n1 | awk '{print $1}')"
TOP_AT="$(printf '%s\n' "$TALLY" | awk -v n="$TOP_N" '$1 == n {print $2}')"
N_AT_TOP="$(printf '%s\n' "$TOP_AT" | grep -c .)"

if [ "$N_AT_TOP" -gt 1 ]; then
  fail "cannot resolve a branch prefix: tracker.branchPrefix is unset and $N_AT_TOP identifiers tie at $TOP_N branch(es) each — $(printf '%s' "$TOP_AT" | tr '\n' ' '). Full tally: $(printf '%s' "$TALLY" | tr '\n' ';' | sed 's/;$//'). Set tracker.branchPrefix in the runtime config."
fi

printf '%s\n' "$TOP_AT"
