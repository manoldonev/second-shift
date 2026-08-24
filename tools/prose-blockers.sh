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
#   promoted     it is worth enforcing, so a gate now does — or a filed issue owns doing it
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
# A blocking construct must NAME A STOP. That is the whole default (`--tier stop`):
#
#   refus{e,es,ed,ing,al}   abort (commanded, forbidden, or shouted)   hard-stop
#   is/are a blocker        is a reject / reject-and-stop              hand back
#   not negotiable / not optional / not skippable
#
# A bare prohibition is deliberately NOT enough. "Do not pad with `no issues found`" is
# guidance: nothing stops if you read past it, and pruning that class would strip working
# instruction under a triage that was never about it. `abort` is narrowed the same way — a run
# that WAS aborted is a state, not a stop, so `aborted runs are in scope` is not a blocker while
# `-> ABORT with:` is.
#
# The wider tiers exist so the narrow default is a stated choice rather than a hidden one:
#
#   --tier stop   (default)  names a stop
#   --tier bold              + prohibitions inside a bold span (this repo marks a rule that way)
#   --tier all               + every clause-initial `never` / `do not` / `don't`
#
# The clause-initial restriction on the prohibition tiers is what separates a control from a
# description. "Never copy plugin content" is a rule; "the lint never looks at the tree" is a
# statement about the world. A clause-initial marker must also bind an ACTION — "renders names,
# never the local cache values" is an elliptical noun-phrase contrast — a determiner or a
# preposition after the marker — and nothing stops if you read past it either.
#
# There is deliberately NO exclusion list. A hand-maintained roster of "lines that look like
# blockers but are not" is the centrally-registered prose census the intake rejected: it conflicts
# on every PR that appends to it, and it goes blind to whatever it never named. The cost — a
# block that carries a stop word inside a larger instruction — is accepted, and such a block
# triages on its merits like any other.
#
# Fenced code and blockquotes are not prose the reader is told to obey: a command that refuses IS
# the gate, and a blockquote is quoted payload (a message the skill emits, a tracker-delta
# callout). Both are skipped, as is YAML frontmatter.
#
# ## Corpus
#
# Skills' SKILL.md files under plugins/, and agent contract files under plugins/*/agents
# (#637 folded the latter in — they used to be a named out-of-census residual, routed to the
# classification register, which cannot hold prose). Fixture copies are excluded BY PATH
# (their prose is test data — pruning it would edit a fixture's expected content).
#
# An agent contract has no run to stop and no milestone ladder: a SKILL.md's "stop" is a
# checklist step a session refuses to pass, but a sub-agent has no checklist to halt partway
# through — its only outcome states are "answer" and "decline to answer". So a stop marker in
# an agent contract is read the same way structurally (the predicate is unchanged — it still
# just matches text), but triaged against that narrower outcome: the construct is blocking
# only where it tells the sub-agent to decline rather than answer (refuse to review, hand
# back with no verdict, abort the dispatch) — not every instruction that happens to contain a
# stop word while describing what the agent DOES once it proceeds.
#
#
# Usage:
#   bash tools/prose-blockers.sh corpus                    # the in-census files, one per line
#   bash tools/prose-blockers.sh census [--tier T] [--full] # TSV: id, sites, excerpt
#   bash tools/prose-blockers.sh check [record]             # census vs the triage record
#
# check exits 3 on any of three disagreements, naming every row involved:
#   UNDISPOSITIONED  a construct in the tree with no row in the record
#   UNPRUNED         a `prose-deleted` row whose construct is still in the tree
#   STALE            a surviving-action row (pointer-kept, lockstep-pinned, guard-added, filed)
#                    whose construct is no longer in the tree
#   UNRESOLVED       an enforcer path the tree does not carry. It does NOT verify that the named
#                    gate enforces that rule — that is a reading, and this command claims no
#                    judgment it does not have.
# It exits 4 on a malformed record. Nothing wires it into CI in this slice: the living coverage
# guard belongs to the classification register, which will key on gates rather than on prose.

set -uo pipefail

SELF_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=${PROSE_BLOCKERS_ROOT:-$(cd -- "$SELF_DIR/.." && pwd)}
DEFAULT_RECORD="docs/prose-blocker-triage.tsv"
TIER=${PROSE_BLOCKERS_TIER:-stop}
FULL=${PROSE_BLOCKERS_FULL:-}

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
#
# Agent contract files (plugins/*/agents/*.md) carry the same construct class as SKILL.md
# prose — a sub-agent reads its contract as instruction the same way a skill session reads
# its SKILL.md — so they are censused alongside it (#637). Fixture copies are excluded by
# path exactly as for SKILL.md: any file under a `/fixtures/` directory is test data, not a
# real contract.
corpus_files() {
  find "$ROOT/plugins" -type f \( -name 'SKILL.md' -o -path '*/agents/*.md' \) 2>/dev/null |
    grep -v '/fixtures/' |
    sed "s|^$ROOT/||" |
    LC_ALL=C sort
}

# Emit one record per matching block: path \t line \t anchor \t normalized-text.
# Anchor is the enclosing LOCKSTEP anchor, or "-" when the block is not inside one.
scan_file() {
  awk -v path="$1" -v tier="$TIER" '
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
    # elliptical noun-phrase contrast ("pinned ref, never the local cache values"): nothing stops.
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
    # A run that WAS aborted is a state, not a stop demanded of the reader. `abort` counts only
    # where the prose commands or forbids one — or shouts it, which is how the skills write the
    # imperative ("-> ABORT with: ...").
    function commands_abort(lc) {
      return (lc ~ /(never|not|must|do not|don'"'"'t|will|then|→|->) abort/)
    }
    function stops(lc, raw) {
      if (lc ~ /refus(e|es|ed|ing|al|als)/) return 1
      if (commands_abort(lc) || raw ~ /ABORT/) return 1
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
      if (stops(lc, text)) return 1
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
    /^[[:space:]]*>/ { flush(); next }
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
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) [ $# -ge 2 ] || die "--tier needs a value"; TIER=$2; shift 2 ;;
      --full) FULL=1; shift ;;
      *) die "census: unknown option: $1" ;;
    esac
  done
  case "$TIER" in stop|bold|all) ;; *) die "--tier must be stop, bold or all (got '$TIER')" ;; esac
  local tmp
  tmp=$(mktemp) || die "mktemp failed"
  # Cleanup is explicit, at the bottom of this function, and deliberately NOT an EXIT trap — bash
  # 3.2, the stock macOS shell, does not run a trap set inside a pipeline element of a command
  # substitution, which is exactly how the tier counts below call this:
  # `$(census --tier bold | awk …)`. A trap would clean up under bash 5 and leak one temp per
  # such call under 3.2, which is invisible to output and to rc.
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
    if [ -n "$FULL" ]; then
      printf '%s\t%s\t%s\n' "$id" "$sites" "$text"
    else
      printf '%s\t%s\t%s\n' "$id" "$sites" "$(printf '%s' "$text" | cut -c1-160)"
    fi
  done | LC_ALL=C sort
  # The pipeline's status has to survive the cleanup below: `check` reads
  # `(census) >"$tmp_census" || exit $?`, so a masked failure there would leave it comparing the
  # record against a TRUNCATED census and printing an all-clear over it.
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

check() {
  local record=${1:-$DEFAULT_RECORD}
  [ -f "$ROOT/$record" ] || die "no triage record at $record"

  local tmp_census tmp_rows
  tmp_census=$(mktemp) || die "mktemp failed"
  tmp_rows=$(mktemp) || die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_census' '$tmp_rows'" EXIT
  # `census` writes TIER and FULL as globals and does its own teardown; the subshell keeps both
  # off this shell, whose EXIT trap above owns the two temps opened here.
  (census) >"$tmp_census" || exit $?

  local bad
  bad=$(awk -F'\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 6 { printf "line %d: %d field(s), want 6\n", FNR, NF; next }
    $2 !~ /^(gate-backed|promoted|deleted)$/ { printf "line %d: unknown disposition \"%s\"\n", FNR, $2 }
    $3 !~ /^(prose-deleted|pointer-kept|lockstep-pinned|guard-added|filed)$/ { printf "line %d: unknown action \"%s\"\n", FNR, $3 }
    $2 != "deleted" && $5 == "-" { printf "line %d: %s row names no enforcer\n", FNR, $2 }
  ' "$ROOT/$record")
  if [ -n "$bad" ]; then
    printf '[prose-blockers] MALFORMED record %s:\n%s\n' "$record" "$bad" >&2
    exit 4
  fi

  # AC-3, mechanically: a named gate must EXIST. The check cannot verify that the gate enforces
  # that particular rule — that is a reading — but a row pointing at a path the tree does not
  # carry is a claim nothing backs, and it is the shape a rename leaves behind.
  local unresolved
  unresolved=$(awk -F'\t' '!/^#/ && NF == 6 && $5 != "-" && $5 !~ /^#[0-9]+$/ {
      p = $5; sub(/::.*$/, "", p); print $1 "\t" p
    }' "$ROOT/$record" | while IFS=$'\t' read -r id path; do
      [ -e "$ROOT/$path" ] || printf '  %s  %s\n' "$id" "$path"
    done)

  awk -F'\t' '!/^#/ && NF == 6 { print $1 "\t" $3 }' "$ROOT/$record" >"$tmp_rows"

  # FILENAME, not NR == FNR: either side can legitimately be empty — a tree with no constructs
  # left, a record with no rows yet — and awk skips an empty file entirely, which makes the
  # NR == FNR idiom read the SECOND file as if it were the first and report nothing at all.
  local rc=0 undispositioned unpruned stale
  undispositioned=$(awk -F'\t' -v R="$tmp_rows" 'FILENAME == R { seen[$1] = 1; next } !($1 in seen) { print "  " $1 "  " $2 }' "$tmp_rows" "$tmp_census")
  unpruned=$(awk -F'\t' -v C="$tmp_census" 'FILENAME == C { live[$1] = $2; next } $2 == "prose-deleted" && ($1 in live) { print "  " $1 "  " live[$1] }' "$tmp_census" "$tmp_rows")
  stale=$(awk -F'\t' -v C="$tmp_census" 'FILENAME == C { live[$1] = 1; next } $2 != "prose-deleted" && !($1 in live) { print "  " $1 "  (" $2 ")" }' "$tmp_census" "$tmp_rows")

  printf '[prose-blockers] census: %s construct(s) over %s file(s); record: %s row(s).\n' \
    "$(awk 'END {print NR}' "$tmp_census")" \
    "$(corpus_files | awk 'END {print NR}')" \
    "$(awk 'END {print NR}' "$tmp_rows")"

  # The stop tier is narrow by design, so what it declines to call blocking is reported
  # here rather than left to a reader who would have to run two more commands to find out. The
  # tiers nest - every stop construct is a bold one and every bold one is an all one - so the
  # difference against all is exactly what the default excludes.
  local n_stop n_bold n_all
  n_stop=$(awk 'END {print NR}' "$tmp_census")
  n_bold=$(census --tier bold | awk 'END {print NR}')
  n_all=$(census --tier all | awk 'END {print NR}')
  printf '[prose-blockers] tiers: stop=%s (default), bold=%s, all=%s - the default excludes %s wider construct(s).\n' \
    "$n_stop" "$n_bold" "$n_all" "$((n_all - n_stop))"

  if [ -n "$undispositioned" ]; then
    printf '[prose-blockers] UNDISPOSITIONED — in the tree, absent from %s:\n%s\n' "$record" "$undispositioned" >&2
    rc=3
  fi
  if [ -n "$unpruned" ]; then
    printf '[prose-blockers] UNPRUNED — recorded prose-deleted, still in the tree:\n%s\n' "$unpruned" >&2
    rc=3
  fi
  if [ -n "$unresolved" ]; then
    printf '[prose-blockers] UNRESOLVED — the row names a gate the tree does not carry:\n%s\n' "$unresolved" >&2
    rc=3
  fi
  if [ -n "$stale" ]; then
    printf '[prose-blockers] STALE — the row expects a surviving construct, the tree has none:\n%s\n' "$stale" >&2
    rc=3
  fi
  [ "$rc" -eq 0 ] && printf '[prose-blockers] ✓ zero undispositioned constructs.\n'
  return "$rc"
}

case "${1:-census}" in
  corpus) corpus_files ;;
  census) shift; census "$@" ;;
  check) shift; check "$@" ;;
  *) die "usage: prose-blockers.sh {corpus | census [--tier stop|bold|all] [--full] | check [record]}" ;;
esac
