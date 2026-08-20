#!/usr/bin/env bash
# prose-blockers.sh — census of BLOCKING CONSTRUCTS in skill prose.
#
# A blocking construct is a piece of SKILL.md prose that tells the reader the run stops:
# a prohibition addressed to the executing agent, or a restatement of a refusal some gate
# already performs. The manifesto's P2 says an outcome gate must be impossible to skip and
# P5 says a rule enforced by a gate does not also live as prose — so a prose blocker is
# always one of three things, and this command is what makes the set enumerable:
#
#   gate-backed  a gate already enforces it; the prose only restates the refusal
#   promoted     it is worth enforcing, so a gate now does
#   deleted      it was never a control; a reminder is not a gate
#
# The disposition itself is NOT computed here. It is authored once, in the record this
# command checks against (docs/prose-blocker-triage.tsv). What this command owns is the
# CENSUS: which constructs exist, and where. That split is deliberate — the census must
# regenerate from the tree, so a construct cannot enter the corpus by being registered,
# and cannot leave it by being forgotten.
#
#
# ## The census unit
#
# One construct = one markdown BLOCK carrying at least one blocking marker in normative
# position. A block is a bullet item with its continuation lines, or a paragraph, or a
# table row. Blocks are the unit rather than lines because these rules are written as
# "**Never X.** <two sentences of why>" — the rule and its rationale prune together, and
# counting them as two would double-count one contract.
#
# A construct appearing in more than one skill is ONE contract with several sites. Its
# identity comes from its content, so relocating a rule within a file — or between files —
# re-keys nothing. Two sites collapse into one construct when their normalized text is
# identical, or when both sit inside the same LOCKSTEP anchor: that is the repo's existing
# mechanism for "two copies of one contract", and where both sites survive a triage it is
# what holds them together afterwards.
#
# Ids are content-derived (pb-<8 hex of sha256 over the normalized text, or over the
# anchor name for a lockstep group). Editing a construct's prose therefore re-keys it, and
# that is the intended failure mode: an edited rule is a rule whose disposition should be
# re-read, not one that silently inherits the old row.
#
#
# ## The predicate, and why it is this one
#
# Two marker families, and a construct needs only one of them:
#
#   REFUSAL   refus{e,es,ing,al}, abort, HARD STOP, blocker, reject, hand back
#             — anywhere in the block. These name the stop outright.
#   PROHIBITION  must not / may not / must never / not optional / not negotiable
#             anywhere; plus `never` and `do not` in CLAUSE-INITIAL position.
#
# The clause-initial restriction on `never` is what separates a control from a description.
# "Never copy plugin content" is a rule the reader must obey. "the lint never looks at the
# tree" and "a capability that is off simply never runs" are statements about the world,
# and pruning them would damage prose that was never a blocker. A bare grep for `never`
# cannot tell those apart and lands near 240 lines against this predicate's ~100 — most of
# the difference is that class.
#
# A clause-initial `never` must also be followed by something other than a determiner or a
# preposition. "renders names, never versions" is an elliptical contrast, not a prohibition
# on an action: nothing stops if you read past it. Requiring a verb-ish next word drops
# that class without needing a list of exceptions.
#
# There is deliberately NO exclusion list. A hand-maintained roster of "lines that look
# like blockers but are not" is the centrally-registered prose census the intake rejected:
# it conflicts on every PR that appends to it, and it goes blind to whatever it never named.
# The predicate over-including a handful of elliptical contrasts is the accepted cost.
#
#
# ## Corpus
#
# Skills' SKILL.md files under plugins/. Fixture copies are excluded BY PATH (their prose
# is test data — pruning it would edit a fixture's expected content). Agent contract files
# under plugins/*/agents carry the same construct class and are a named out-of-census
# residual, routed to the classification register rather than silently swept in or dropped.
#
#
# Usage:
#   bash tools/prose-blockers.sh corpus            # the in-census files, one per line
#   bash tools/prose-blockers.sh census            # TSV: id, sites, excerpt
#   bash tools/prose-blockers.sh check [record]    # census vs the triage record
#
# check exits 3 naming every construct in the tree with no row in the record
# (UNDISPOSITIONED), and every row dispositioned `deleted` whose construct is still in the
# tree (UNPRUNED). It exits 4 on a malformed record. Nothing wires it into CI in this
# slice: the living coverage guard belongs to the classification register.

set -uo pipefail

SELF_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=${PROSE_BLOCKERS_ROOT:-$(cd -- "$SELF_DIR/.." && pwd)}
DEFAULT_RECORD="docs/prose-blocker-triage.tsv"

die() {
  printf '[prose-blockers] %s\n' "$*" >&2
  exit 2
}

if command -v shasum >/dev/null 2>&1; then
  hash_stdin() { shasum -a 256 | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  hash_stdin() { sha256sum | awk '{print $1}'; }
else
  die "neither shasum nor sha256sum is on PATH — no construct id can be computed"
fi

# The corpus, resolved from the tree every time. `find` rather than a manifest: a skill
# added tomorrow is censused tomorrow, with nobody having to remember to enrol it.
corpus_files() {
  find "$ROOT/plugins" -type f -name 'SKILL.md' 2>/dev/null |
    grep -v '/fixtures/' |
    sed "s|^$ROOT/||" |
    LC_ALL=C sort
}

# Emit one record per matching block: path \t line \t anchor \t normalized-text.
# Anchor is the enclosing LOCKSTEP anchor, or "-" when the block is not inside one.
scan_file() {
  awk -v path="$1" -v tier="${PROSE_BLOCKERS_TIER:-stop}" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    function normalize(s) {
      s = trim(s)
      sub(/^[-*+][[:space:]]+/, "", s)
      sub(/^[0-9]+[a-z]?[.)][[:space:]]+/, "", s)
      gsub(/[[:space:]]+/, " ", s)
      return trim(s)
    }
    # A clause boundary is the start of the block, sentence or clause punctuation, a bold
    # opener, a list marker, a table pipe — or the pronoun subject of a stated rule
    # ("You never guess"), which is a prohibition wearing a declarative coat.
    function at_boundary(p) {
      p = trim(p)
      if (p == "") return 1
      if (p ~ /(\*|:|;|\.|,|\(|>|\||"|-)$/) return 1
      if (p ~ /—$/) return 1
      if (p ~ /(^|[[:space:]])(you|we|it|they)$/) return 1
      return 0
    }
    # A prohibition binds an ACTION. A determiner or preposition after the marker means an
    # elliptical contrast ("pinned ref, never local cache values"), which stops nothing.
    function binds_action(rest,   w) {
      w = rest
      sub(/^[[:space:]]+/, "", w)
      sub(/[^a-z0-9`*_'"'"'-].*$/, "", w)
      gsub(/[`*_]/, "", w)
      if (w == "") return 0
      return (w !~ /^(a|an|the|to|for|from|in|on|at|by|with|of|as|and|or|but|its|his|her|their|your|our|that|this|these|those|it|they|he|she|we|you|i|more|less|just|only|simply|again|both|either|neither|one|two)$/)
    }
    function clause_initial(lc, marker,   n, parts, i, ok) {
      n = split(lc, parts, marker)
      for (i = 2; i <= n; i++) {
        if (at_boundary(parts[i - 1]) && binds_action(parts[i])) return 1
      }
      return 0
    }
    # A prohibition alone is not a blocker. "Do not pad with `no issues found`" is a style
    # instruction: nothing stops if you read past it. What makes a construct BLOCKING is a
    # stop consequence — stated outright, or carried by the bold emphasis this repo uses to
    # mark a rule as non-negotiable.
    function stops(lc) {
      if (lc ~ /refus(e|es|ed|ing|al|als)/) return 1
      if (lc ~ /abort/) return 1
      if (lc ~ /hard[- ]stop|hard stop/) return 1
      if (lc ~ /(is a blocker|are blockers|itself a blocker|counts as a blocker|is a hard blocker)/) return 1
      if (lc ~ /(is a reject|reject-and-stop|strict reject|reject at intake)/) return 1
      if (lc ~ /hand(s|ing|ed)? (it )?back/) return 1
      if (lc ~ /(not negotiable|not optional|not skippable)/) return 1
      return 0
    }
    function prohibits(lc) {
      if (lc ~ /(must not|may not|must never)/) return 1
      if (clause_initial(lc, "never ")) return 1
      if (clause_initial(lc, "do not ")) return 1
      if (clause_initial(lc, "don'"'"'t ")) return 1
      return 0
    }
    # Bold spans only. `**` pairs delimit them, so every even piece of the split is inside one.
    function bold_prohibits(text,   n, b, i) {
      n = split(text, b, /\*\*/)
      for (i = 2; i <= n; i += 2) {
        if (prohibits(tolower(b[i]))) return 1
      }
      return 0
    }
    function is_construct(text,   lc) {
      lc = tolower(text)
      if (stops(lc)) return 1
      if (tier != "stop" && bold_prohibits(text)) return 1
      if (tier == "all" && prohibits(lc)) return 1
      return 0
    }
    function flush(   norm) {
      if (block == "") return
      norm = normalize(block)
      if (norm != "" && is_construct(norm)) {
        printf "%s\t%d\t%s\t%s\n", path, block_line, (anchor == "" ? "-" : anchor), norm
      }
      block = ""
    }
    BEGIN { infence = 0; front = 0; anchor = ""; block = "" }
    # Frontmatter is metadata, not prose the reader is told to obey.
    NR == 1 && $0 == "---" { front = 1; next }
    front == 1 { if ($0 == "---") front = 0; next }
    # A LOCKSTEP anchor makes several sites one contract; the marker lines are never prose.
    $0 ~ /LOCKSTEP-BEGIN[[:space:]]+[A-Za-z0-9_-]+/ {
      flush()
      a = $0
      sub(/^.*LOCKSTEP-BEGIN[[:space:]]+/, "", a)
      sub(/[^A-Za-z0-9_-].*$/, "", a)
      anchor = a
      next
    }
    $0 ~ /LOCKSTEP-END[[:space:]]+[A-Za-z0-9_-]+/ { flush(); anchor = ""; next }
    # Fenced code is not prose. A command that refuses is the gate, not a restatement of it.
    /^[[:space:]]*```/ { flush(); infence = !infence; next }
    infence { next }
    /^[[:space:]]*$/ { flush(); next }
    /^[[:space:]]*#/ { flush(); next }
    # A new list item or table row ends the previous block, whatever its indent: a nested
    # bullet is its own rule, and merging it into its parent would hide one of the two.
    /^[[:space:]]*([-*+][[:space:]]|[0-9]+[a-z]?[.)][[:space:]])/ || /^[[:space:]]*\|/ {
      flush(); block = $0; block_line = FNR; next
    }
    { if (block == "") { block = $0; block_line = FNR } else { block = block " " $0 } }
    END { flush() }
  ' "$ROOT/$1"
}

# Group the scan into constructs. Sites sharing a lockstep anchor, or an identical
# normalized text, are one construct — so a duplicated rule is counted once and carries
# both of its addresses.
census() {
  local tmp
  tmp=$(mktemp) || die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT
  local f
  while IFS= read -r f; do
    scan_file "$f"
  done < <(corpus_files) >"$tmp"

  # One pass to assign each row its grouping key, then group by it.
  awk -F'\t' '{
    key = ($3 == "-") ? "T\t" $4 : "A\t" $3
    print key "\t" $1 ":" $2 "\t" $4
  }' "$tmp" | LC_ALL=C sort | awk -F'\t' '
    { k = $1 "\t" $2
      if (k != prev) { if (prev != "") emit(); prev = k; sites = $3; text = $4; kind = $1; raw = $2 }
      else { sites = sites "," $3 }
    }
    function emit() { printf "%s\t%s\t%s\t%s\n", kind, raw, sites, text }
    END { if (prev != "") emit() }
  ' | while IFS=$'\t' read -r kind raw sites text; do
    local id
    if [ "$kind" = "A" ]; then
      id="pb-$(printf 'lockstep:%s' "$raw" | hash_stdin | cut -c1-8)"
    else
      id="pb-$(printf '%s' "$raw" | hash_stdin | cut -c1-8)"
    fi
    if [ -n "${PROSE_BLOCKERS_FULL:-}" ]; then
      printf '%s\t%s\t%s\n' "$id" "$sites" "$text"
    else
      printf '%s\t%s\t%s\n' "$id" "$sites" "$(printf '%s' "$text" | cut -c1-160)"
    fi
  done | LC_ALL=C sort
}

check() {
  local record=${1:-$DEFAULT_RECORD}
  [ -f "$ROOT/$record" ] || die "no triage record at $record"

  local tmp_census tmp_ids
  tmp_census=$(mktemp) || die "mktemp failed"
  tmp_ids=$(mktemp) || die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_census' '$tmp_ids'" EXIT
  census >"$tmp_census"

  # Record shape: id, disposition, action, sites, enforcer, note — comments and blanks skipped.
  local bad
  bad=$(awk -F'\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 6 { printf "line %d: %d fields, want 6\n", FNR, NF; next }
    $2 !~ /^(gate-backed|promoted|deleted)$/ { printf "line %d: unknown disposition %s\n", FNR, $2 }
  ' "$ROOT/$record")
  if [ -n "$bad" ]; then
    printf '[prose-blockers] MALFORMED record %s:\n%s\n' "$record" "$bad" >&2
    exit 4
  fi

  awk -F'\t' '!/^#/ && NF == 6 { print $1 "\t" $2 }' "$ROOT/$record" >"$tmp_ids"

  local rc=0 undispositioned unpruned
  undispositioned=$(awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { print "  " $1 "  " $2 "  " $3 }' "$tmp_ids" "$tmp_census")
  unpruned=$(awk -F'\t' 'NR == FNR { live[$1] = $2; next } $2 == "deleted" && ($1 in live) { print "  " $1 "  " live[$1] }' "$tmp_census" "$tmp_ids")

  local n
  n=$(awk 'END {print NR}' "$tmp_census")
  printf '[prose-blockers] census: %s construct(s) over %s file(s).\n' "$n" "$(corpus_files | awk 'END {print NR}')"

  if [ -n "$undispositioned" ]; then
    printf '[prose-blockers] UNDISPOSITIONED — in the tree, absent from %s:\n%s\n' "$record" "$undispositioned" >&2
    rc=3
  fi
  if [ -n "$unpruned" ]; then
    printf '[prose-blockers] UNPRUNED — recorded `deleted`, still in the tree:\n%s\n' "$unpruned" >&2
    rc=3
  fi
  [ "$rc" -eq 0 ] && printf '[prose-blockers] ✓ every censused construct carries a disposition.\n'
  return "$rc"
}

case "${1:-census}" in
  corpus) corpus_files ;;
  census) census ;;
  check) shift; check "$@" ;;
  *) die "usage: prose-blockers.sh {corpus|census|check [record]}" ;;
esac
