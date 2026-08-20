#!/usr/bin/env bash
# check-lockstep-pairs.sh — mechanically enforce contract blocks that are duplicated
# across files and can only drift silently.
#
# Some contracts exist in two or three places by necessity: an agent whose independence
# contract forbids reading pipeline docs keeps an inline copy of a rule; three Workflow
# scripts each declare the same schema because the runtime gives them no import. The
# prose at those sites says "keep verbatim" / "must match byte-for-byte" — and without
# this script, nothing checks it.
#
# This replaces the prose-presence guard class (grep a token out of a markdown file),
# which could only tell you a word was still present, never that two copies still agree.
#
# Lives in repo-level scripts/ rather than in a plugin because the blocks span plugins.
#
# Usage:
#   bash scripts/check-lockstep-pairs.sh [repo-root]
# Default root: the parent of this script's directory.
#
#
# ## Pairs are DISCOVERED, never declared twice (#604)
#
# There is no manifest. The markers in the files are the whole declaration: this script
# walks the tree, groups every marker site by its anchor, and compares all members of
# each group. A central register would restate what the markers already say, conflict on
# every PR that appends to it, and — as it did for six anchors — read as coverage for
# blocks it never named.
#
# **A group of size 1 is a FAILURE.** An anchor with one site is a block that believes it
# is held to a copy and is not. That is the same property as "a missing marker is a
# FAILURE, not a skip", approached from the other side, and it is what the manifest was
# structurally unable to check.
#
#
# ## Marker grammar
#
# A marker is recognised ONLY when it occupies its whole line, modulo leading
# indentation, one host comment opener and an optional markdown closer:
#
#     <indent> [# | // | <!--] LOCKSTEP-BEGIN <anchor> [<relation>] [-->]
#     <indent> [# | // | <!--] LOCKSTEP-END   <anchor>              [-->]
#
# <anchor> is [A-Za-z0-9_-]+. The marker lines themselves are never part of the block.
#
# The whole-line rule is load-bearing, not tidiness. A marker NAME appears in ordinary
# prose and in ordinary code — a doc sentence citing an anchor, a selftest passing the
# token to sed — and a substring search would enrol those as sites, adding phantom
# members that red a correct tree. The rejected alternative was "a BEGIN counts only if
# its file also has a matching END": it excludes the phantoms, but it also silently drops
# a real block whose END was deleted, which is the drift this script exists to catch.
#
# A line that starts with the token but does not satisfy the grammar is MALFORMED and
# fails. Failing closed is deliberate: the alternative is a site that silently vanishes.
#
# Careful when writing ABOUT markers. A whole-line marker inside a heredoc — a selftest
# fixture, a doc example — is a real site to this walk, and will fail as a group of one.
# Build such a line at runtime from a variable, the way the selftest does.
#
#
# ## Relations
#
# The optional third token on a BEGIN marker states the relation and, where it has one,
# its direction. It lives at the site because that is where the person editing the block
# reads it.
#
#   (omitted)   verbatim — the default, and what all but one group uses. Every member of
#               the group must match after collapsing whitespace runs to one space and
#               trimming (the text-contract-selftest.sh idiom — indentation and line
#               wrapping are not the contract; the tokens are).
#   verbatim    the same, stated explicitly.
#   superset    this member is the canonical wide side of a subset-of group.
#   subset      this member is a deliberate NARROWING of the group's superset. Its first
#               single-quoted '...|...' literal is split on `|`, and every token must
#               appear in the superset's. For e.g. a human-attributed subset of a wider
#               enum, where verbatim would be wrong.
#
# A group whose members disagree — some verbatim, some not — FAILS. A subset-of group
# needs exactly one superset. An unrecognised relation token FAILS rather than falling
# back to verbatim, because a typo that degraded to the default would be a check nobody
# could see had stopped discriminating.
#
# Exit code = number of failed anchors (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$HERE/.." && pwd)}"

[[ -d "$ROOT" ]] || { echo "[lockstep] FATAL: root not found: $ROOT" >&2; exit 99; }

# --- Discovery scope -------------------------------------------------------------------
#
# EXCLUDED_PREFIXES — repo-root-relative path prefixes the walk does not read, one per
# line. Stated here as data with its reason rather than buried in a find(1) glob, because
# an exclusion is a hole in a guard and has to be legible as one.
#
#   docs/plans/   Plan documents QUOTE locksteped blocks verbatim as evidence for a
#                 decision. They are a historical record of what a block said on the day
#                 it was reasoned about, not a carrier of the contract, and they are never
#                 edited afterwards. Five of them quote a live block today. Including them
#                 would enrol each as a group member and red a correct tree the moment the
#                 real block legitimately changed — the plan doc is SUPPOSED to drift.
EXCLUDED_PREFIXES='docs/plans/'

FAILS=0
ANCHORS=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

TMPD=$(mktemp -d -t lockstep.XXXXXX) || { echo "[lockstep] FATAL: mktemp failed" >&2; exit 99; }
trap 'rm -rf "$TMPD"' EXIT INT TERM
SITES="$TMPD/sites"
: > "$SITES"

excluded() {
  local rel="$1" p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    case "$rel" in "$p"*) return 0 ;; esac
  done <<< "$EXCLUDED_PREFIXES"
  return 1
}

# scan_file <abs-path> <rel-path> — emit one record per marker event.
#   SITE      <anchor> <relation> <rel-path> <begin-line> <end-line>
#   MALFORMED <rel-path> <line-no> <the line>
#   UNCLOSED  <rel-path> <line-no> <anchor>
#   ORPHANEND <rel-path> <line-no> <anchor>
#   MISMATCH  <rel-path> <line-no> <open-anchor> <closing-anchor>
scan_file() {
  awk -v rel="$2" '
    function emit_malformed(n, raw) { printf "MALFORMED\t%s\t%d\t%s\n", rel, n, raw }
    BEGIN { open = ""; openrole = ""; openline = 0 }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/^(#+|\/\/|<!--)[[:space:]]*/, "", line)
      if (line !~ /^LOCKSTEP-(BEGIN|END)[[:space:]]/) next
      sub(/[[:space:]]*-->[[:space:]]*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      n = split(line, f, /[[:space:]]+/)
      if (f[2] !~ /^[A-Za-z0-9_-]+$/) { emit_malformed(FNR, $0); next }
      if (f[1] == "LOCKSTEP-BEGIN") {
        if (n < 2 || n > 3) { emit_malformed(FNR, $0); next }
        if (open != "") { printf "UNCLOSED\t%s\t%d\t%s\n", rel, openline, open }
        open = f[2]; openrole = (n == 3 ? f[3] : "verbatim"); openline = FNR
      } else {
        if (n != 2) { emit_malformed(FNR, $0); next }
        if (open == "") { printf "ORPHANEND\t%s\t%d\t%s\n", rel, FNR, f[2]; next }
        if (f[2] != open) {
          printf "MISMATCH\t%s\t%d\t%s\t%s\n", rel, FNR, open, f[2]
          open = ""; next
        }
        printf "SITE\t%s\t%s\t%s\t%d\t%d\n", open, openrole, rel, openline, FNR
        open = ""
      }
    }
    END { if (open != "") printf "UNCLOSED\t%s\t%d\t%s\n", rel, openline, open }
  ' "$1"
}

# --- Walk -------------------------------------------------------------------------------
# -I skips binaries. .git and node_modules are pruned for cost, not policy: neither can
# hold a repo contract, and both are absent from a fresh clone's scan surface anyway.
while IFS= read -r abs; do
  rel="${abs#"$ROOT"/}"
  excluded "$rel" && continue
  scan_file "$abs" "$rel" >> "$SITES"
done < <(
  find "$ROOT" -type f \
       ! -path '*/.git/*' ! -path '*/node_modules/*' -print0 2>/dev/null \
    | xargs -0 grep -lI 'LOCKSTEP-BEGIN' 2>/dev/null \
    | sort
)

# --- Structural failures ----------------------------------------------------------------
# Reported before any grouping: a file whose markers do not pair up has no well-defined
# sites to group, so a group verdict computed over it would be an answer about a tree the
# author does not have.
while IFS=$'\t' read -r kind a b c d; do
  case "$kind" in
    MALFORMED) bad "$a:$b: line starts with a LOCKSTEP marker but does not match the grammar: $c" ;;
    UNCLOSED)  bad "$a:$b: LOCKSTEP-BEGIN '$c' is never closed" ;;
    ORPHANEND) bad "$a:$b: LOCKSTEP-END '$c' has no matching BEGIN" ;;
    MISMATCH)  bad "$a:$b: LOCKSTEP-END '$d' closes an open '$c'" ;;
  esac
done < <(grep -v '^SITE	' "$SITES" || true)

# --- Group and compare -------------------------------------------------------------------

# extract <rel> <begin> <end> — the lines strictly between the markers.
extract() {
  local b=$(( $2 + 1 )) e=$(( $3 - 1 ))
  [[ "$b" -le "$e" ]] || return 1
  sed -n "${b},${e}p" "$ROOT/$1"
}

# normalize — collapse whitespace runs to a single space and trim, so indentation and
# line wrapping are not part of the contract.
normalize() { tr '\n' ' ' | tr -s ' \t' ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

# first_enum — the first single-quoted literal containing a `|`, with quotes stripped.
first_enum() { grep -o "'[^']*|[^']*'" | head -n1 | tr -d "'"; }

check_group() {
  local anchor="$1" group="$2"
  local count roles supersets subsets others
  ANCHORS=$((ANCHORS + 1))
  count=$(wc -l < "$group" | tr -d ' ')

  if [[ "$count" -eq 1 ]]; then
    local only
    only=$(cut -f3 < "$group")
    bad "$anchor: only ONE site ($only) — a lockstep marker with no counterpart is a block that reads as held to a copy and is not. Give it a second site, or remove its markers."
    return
  fi

  roles=$(cut -f2 < "$group" | sort -u)
  supersets=$(awk -F'\t' '$2 == "superset"' "$group" | wc -l | tr -d ' ')
  subsets=$(awk -F'\t' '$2 == "subset"'   "$group" | wc -l | tr -d ' ')
  others=$(awk -F'\t' '$2 != "superset" && $2 != "subset" && $2 != "verbatim"' "$group" | cut -f2,3 | sort -u)

  if [[ -n "$others" ]]; then
    bad "$anchor: unrecognised relation(s) — expected verbatim | superset | subset:"$'\n'"$(printf '%s\n' "$others" | sed 's/^/        /')"
    return
  fi

  if [[ "$supersets" -eq 0 && "$subsets" -eq 0 ]]; then
    check_verbatim "$anchor" "$group"
    return
  fi

  # A subset-of group. Every member must have taken a side.
  if [[ "$roles" == *verbatim* ]]; then
    bad "$anchor: members DISAGREE about the relation — $(awk -F'\t' '$2=="verbatim"{printf "%s(verbatim) ",$3}' "$group")vs $(awk -F'\t' '$2!="verbatim"{printf "%s(%s) ",$3,$2}' "$group")"
    return
  fi
  if [[ "$supersets" -ne 1 ]]; then
    bad "$anchor: a subset-of group needs exactly ONE superset, found $supersets ($(awk -F'\t' '$2=="superset"{printf "%s ",$3}' "$group"))"
    return
  fi
  check_subset "$anchor" "$group"
}

check_verbatim() {
  local anchor="$1" group="$2" canon="" canon_rel="" rel b e body norm canon_norm
  local drifted=0
  while IFS=$'\t' read -r _a _r rel b e; do
    if ! body=$(extract "$rel" "$b" "$e"); then
      bad "$anchor: block in $rel is EMPTY (markers are adjacent)"
      return
    fi
    [[ -n "$body" ]] || { bad "$anchor: block in $rel is empty"; return; }
    norm=$(printf '%s' "$body" | normalize)
    if [[ -z "$canon_rel" ]]; then
      canon="$body"; canon_norm="$norm"; canon_rel="$rel"; continue
    fi
    if [[ "$norm" != "$canon_norm" ]]; then
      bad "$anchor (verbatim): $canon_rel and $rel have DRIFTED"
      diff <(printf '%s\n' "$canon") <(printf '%s\n' "$body") | sed 's/^/      /' >&2
      drifted=1
    fi
  done < "$group"
  [[ "$drifted" -eq 0 ]] && ok "$anchor (verbatim): $(cut -f3 < "$group" | tr '\n' ' ' | sed 's/ $//') agree"
}

check_subset() {
  local anchor="$1" group="$2" super_rel super_enum rel b e body enum missing tok OLDIFS
  local violated=0
  super_rel=$(awk -F'\t' '$2=="superset"{print $3}' "$group")
  local sb se
  sb=$(awk -F'\t' '$2=="superset"{print $4}' "$group")
  se=$(awk -F'\t' '$2=="superset"{print $5}' "$group")
  body=$(extract "$super_rel" "$sb" "$se") || { bad "$anchor: superset block in $super_rel is empty"; return; }
  super_enum=$(printf '%s' "$body" | first_enum)
  [[ -n "$super_enum" ]] || { bad "$anchor (subset-of): no single-quoted '...|...' literal in the superset $super_rel"; return; }

  while IFS=$'\t' read -r _a role rel b e; do
    [[ "$role" == "subset" ]] || continue
    body=$(extract "$rel" "$b" "$e") || { bad "$anchor: subset block in $rel is empty"; violated=1; continue; }
    enum=$(printf '%s' "$body" | first_enum)
    [[ -n "$enum" ]] || { bad "$anchor (subset-of): no single-quoted '...|...' literal in $rel"; violated=1; continue; }
    missing=""
    # bash 3.2: no readarray/associative arrays — split on | with IFS.
    OLDIFS="$IFS"; IFS='|'
    for tok in $enum; do
      case "|$super_enum|" in *"|$tok|"*) ;; *) missing="$missing $tok" ;; esac
    done
    IFS="$OLDIFS"
    if [[ -n "$missing" ]]; then
      bad "$anchor (subset-of): $rel has token(s) absent from the superset $super_rel:$missing"
      violated=1
    fi
  done < "$group"
  [[ "$violated" -eq 0 ]] && ok "$anchor (subset-of): superset $super_rel ⊇ $(awk -F'\t' '$2=="subset"{printf "%s ",$3}' "$group" | sed 's/ $//')"
}

GROUP="$TMPD/group"
CUR=""
: > "$GROUP"
while IFS= read -r rec; do
  a=$(printf '%s' "$rec" | cut -f2)
  if [[ "$a" != "$CUR" ]]; then
    [[ -n "$CUR" ]] && check_group "$CUR" "$GROUP"
    CUR="$a"; : > "$GROUP"
  fi
  printf '%s\n' "${rec#SITE	}" >> "$GROUP"
done < <(grep '^SITE	' "$SITES" | sort -t"$(printf '\t')" -k2,2 -k4,4 || true)
[[ -n "$CUR" ]] && check_group "$CUR" "$GROUP"

echo "[lockstep] $ANCHORS anchor(s) checked, $FAILS failed"
exit $FAILS
