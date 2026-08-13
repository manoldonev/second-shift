#!/usr/bin/env bash
# dup-scan.sh — deterministic duplicate scan for an intake subject against the
# tracker's open queue.
#
# WHY THIS EXISTS: two tickets describing one defect both cleared intake, both
# carried the queue label, and both became eligible to run. Neither the router
# nor any intake skill looked at what was already queued. The duplication was
# caught by hand, after one of the two runs had finished nothing.
#
# WHAT IT IS, AND IS NOT. This is a PROPOSER. It ranks open tickets by mechanical
# overlap with the subject and hands the list to a reader; it never judges, and it
# never writes to the tracker. The two tickets that motivated it were genuinely
# written by different routes and only a reader can say whether they are the same
# work — so an auto-close would have been wrong even when the scan is right. The
# scorer proposes; the agent and the operator judge.
#
# THE CORPUS IS QUEUED **OR** CLAIMED, and the claimed half is the load-bearing
# one. `claim` swaps the queue label for the claimed label, so a ticket that is
# already being built carries no queue label at all — a queue-only corpus is blind
# to the most expensive duplicate class there is, which is exactly the shape of the
# collision this tool exists to prevent. The claimed half pays a second way: a
# candidate that is NOT a duplicate but touches the same file is an in-flight
# collision warning, which tells the reader to sequence rather than to close.
#
# SCORING (deliberately mechanical, so the answer is reproducible and diffable):
#
#   score = TITLE_WEIGHT * |title tokens shared| + |body symbols shared|
#
# Title tokens are lowercased, stopworded, ≥3 chars, crudely de-pluralized. Body
# symbols are four closed classes a tracker body actually repeats — file paths with
# a known extension, long flags, exit/return codes, and cross-references to other
# items. Neither half is agent judgment over raw prose, and neither is the tracker's
# own relevance search: both are unguardable, and a scan whose verdict cannot be
# pinned by a fixture is a scan nobody can tell has broken.
#
# Titles outweigh bodies because in a single-product tracker the bodies converge —
# every ticket here names the same handful of scripts — while two titles sharing
# three content words is rare. The weight, the threshold, and the stopword list are
# all one constant each, every one of them overridable, and the `--explain` mode
# prints the full ranked corpus so a retune is a measurement rather than a guess.
#
# Exit: 0 no candidates at or above the threshold (or the tracker has no queue at
#       all), 10 candidates found and listed on stdout, 2 usage/IO/tracker error.
#
# `10` and not `1`, and the distinction is the point: a failed `gh` must never be
# readable as a clean scan. A caller that tests `if scan; then proceed` gets the
# right answer on all three arms only because "found something" and "could not
# look" are different non-zero values.
set -euo pipefail

# ---------------------------------------------------------------- tunables
# Calibrated against the pair that motivated this tool, scored inside the queue those
# two tickets were actually filed into:
#
#   subject   candidate                      score
#   #500      #502  (the true duplicate)        16
#   #500      #514  (related, distinct)          8   <- the nearest non-duplicate
#   #500      everything else queued          <= 3
#   #502      #500                              16   <- symmetric
#
# 12 sits in the 8-16 gap. That corpus is frozen as `dup-scan-fixtures/corpus-live.json`
# and the selftest asserts BOTH halves of the separation, so this is a measurement with a
# guard on it rather than a comment: change the constant without re-reading the
# measurement and the suite reds. `--explain` prints the full ranked corpus, which is how
# you take the measurement again on a queue that has moved.
THRESHOLD=12
TITLE_WEIGHT=3
CORPUS_LIMIT=100

# Standard English function words, plus the two nouns every tracker item contains
# ("issue", "ticket") — in a tracker corpus those carry exactly as much signal as
# "the". Tokens shorter than 3 characters are dropped before this list is consulted,
# so it holds none of them.
STOPWORDS='the and for but not its that this with when what which who whom why how
does did done can cannot could should would will shall must may might have has had
been being are was were them they their there here into onto than then those these
such some any all each every both more most other own same too very just also even
still yet already ever never always only because after before while during about
above below over under again further once from out off down only own said says say
it is issue ticket item work'

# ---------------------------------------------------------------- argument parse
SUBJECT_ISSUE=""
SUBJECT_TITLE=""
BODY_FILE=""
EXPLAIN=0

usage() {
  echo "dup-scan: usage: dup-scan.sh (--issue <n> | --title <text> [--body-file <path>])" >&2
  echo "                            [--threshold <n>] [--title-weight <n>] [--limit <n>] [--explain]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      [ $# -ge 2 ] || { echo "dup-scan: --issue needs a value" >&2; exit 2; }
      SUBJECT_ISSUE="$2"; shift 2 ;;
    --title)
      [ $# -ge 2 ] || { echo "dup-scan: --title needs a value" >&2; exit 2; }
      SUBJECT_TITLE="$2"; shift 2 ;;
    --body-file)
      [ $# -ge 2 ] || { echo "dup-scan: --body-file needs a value" >&2; exit 2; }
      BODY_FILE="$2"; shift 2 ;;
    --threshold)
      [ $# -ge 2 ] || { echo "dup-scan: --threshold needs a value" >&2; exit 2; }
      THRESHOLD="$2"; shift 2 ;;
    --title-weight)
      [ $# -ge 2 ] || { echo "dup-scan: --title-weight needs a value" >&2; exit 2; }
      TITLE_WEIGHT="$2"; shift 2 ;;
    --limit)
      [ $# -ge 2 ] || { echo "dup-scan: --limit needs a value" >&2; exit 2; }
      CORPUS_LIMIT="$2"; shift 2 ;;
    --explain) EXPLAIN=1; shift ;;
    -h|--help) sed -n '2,57p' "$0"; exit 0 ;;
    -*) echo "dup-scan: unknown option: $1" >&2; usage; exit 2 ;;
    *)  echo "dup-scan: unexpected argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -n "$SUBJECT_ISSUE" ] && [ -n "$SUBJECT_TITLE" ]; then
  echo "dup-scan: --issue and --title are mutually exclusive — the subject is either a filed item or a draft, not both" >&2
  exit 2
fi
if [ -z "$SUBJECT_ISSUE" ] && [ -z "$SUBJECT_TITLE" ]; then
  usage; exit 2
fi
if [ -n "$SUBJECT_ISSUE" ] && [ -n "$BODY_FILE" ]; then
  echo "dup-scan: --body-file is meaningless with --issue — the body is fetched from the tracker" >&2
  exit 2
fi

for pair in "THRESHOLD:$THRESHOLD" "TITLE_WEIGHT:$TITLE_WEIGHT" "CORPUS_LIMIT:$CORPUS_LIMIT"; do
  case "${pair#*:}" in
    ''|*[!0-9]*) echo "dup-scan: ${pair%%:*} must be a non-negative integer, got '${pair#*:}'" >&2; exit 2 ;;
  esac
done
case "$SUBJECT_ISSUE" in
  '') : ;;
  *[!0-9]*) echo "dup-scan: --issue takes a number, got '$SUBJECT_ISSUE'" >&2; exit 2 ;;
esac
if [ -n "$BODY_FILE" ] && [ ! -f "$BODY_FILE" ]; then
  echo "dup-scan: body file not found: $BODY_FILE" >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "dup-scan: jq is required" >&2; exit 2; }

# ---------------------------------------------------------------- config
# Same anchor lean-gate.sh uses: the config lives in the MAIN checkout, so a lane
# worktree resolves it through --git-common-dir rather than its own root.
if [ -n "${SECOND_SHIFT_CONFIG:-}" ]; then
  CONFIG="$SECOND_SHIFT_CONFIG"
else
  _common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$_common" ]; then
    case "$_common" in
      /*) : ;;
      *)  _common="$(pwd)/$_common" ;;
    esac
    CONFIG="$(cd "$_common/.." 2>/dev/null && pwd)/.claude/second-shift.config.json"
  else
    CONFIG=".claude/second-shift.config.json"
  fi
fi

# ABSENT and UNPARSEABLE are two different facts, and only one is legal. Absent means
# "this consumer configured nothing" and every default below is the documented answer.
# Present-and-broken means the operator's intent is unknown — and the defaults are not
# neutral here: `.tracker.type` defaults to github, the arm that actually scans. A typo
# must not silently select an adapter.
if [ -f "$CONFIG" ] && ! jq empty "$CONFIG" >/dev/null 2>&1; then
  echo "dup-scan: config $CONFIG exists but is not parseable JSON — refusing to fall back to defaults (jq empty '$CONFIG' names the parse error)" >&2
  exit 2
fi

cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"

# D-6: the jira adapter has no queue and no labels, so there is no corpus to define.
# Say so out loud rather than inventing a substitute one — an intake exit that reads a
# silent 0 cannot tell "nothing matched" from "nothing was looked at".
if [ "$TRACKER_TYPE" != "github" ]; then
  echo "dup-scan: not applicable — tracker.type is '$TRACKER_TYPE', which has no queue label and no claimed label, so there is no corpus of eligible tickets to scan against. No scan was performed."
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "dup-scan: gh is required under tracker.type github" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The internal record separator for the scored table — see the printf below it.
US="$(printf '\037')"

# ---------------------------------------------------------------- text mechanics
tokens() { # tokens <text> → one normalized title token per line, sorted, unique
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '\n' \
    | awk -v sw="$(printf '%s' "$STOPWORDS" | tr '\n' ' ')" '
        BEGIN { n = split(sw, a, /[ \t\n]+/); for (i = 1; i <= n; i++) stop[a[i]] = 1 }
        length($0) >= 3 {
          t = $0
          # crude de-pluralization so "claim"/"claims" and "label"/"labels" agree.
          # Applied to BOTH sides identically, so an over-strip ("class"→"clas") costs
          # nothing as long as it is consistent — hence the -ss guard is the only
          # exception worth carrying.
          if (length(t) >= 4 && substr(t, length(t)) == "s" && substr(t, length(t) - 1, 2) != "ss") {
            t = substr(t, 1, length(t) - 1)
          }
          if (!(t in stop)) print t
        }' \
    | sort -u
}

symbols() { # symbols <text> → one normalized body symbol per line, sorted, unique
  {
    # 1. file paths / names carrying a known extension
    printf '%s' "$1" | grep -oE '[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sh|mjs|js|ts|tsv|json|md|ya?ml|py)' || true
    # 2. long flags
    printf '%s' "$1" | grep -oE '\-\-[A-Za-z0-9][A-Za-z0-9-]+' || true
    # 3. exit / return codes — `exit 2`, `rc=2`, `rc 2`, `exit code 2` all mean one thing
    printf '%s' "$1" | grep -oiE '\b(exit([[:space:]]+code)?|rc)[[:space:]]*=?[[:space:]]*[0-9]+' \
      | sed -E 's/^[^0-9]*/rc:/' || true
    # 4. cross-references to other tracker items
    printf '%s' "$1" | grep -oE '#[0-9]+' | sed -E 's/^#/ref:/' || true
  } | tr '[:upper:]' '[:lower:]' | sort -u
}

# ---------------------------------------------------------------- the subject
if [ -n "$SUBJECT_ISSUE" ]; then
  if ! gh issue view "$SUBJECT_ISSUE" --json number,title,body > "$TMP/subject.json" 2>"$TMP/gh.err"; then
    echo "dup-scan: could not read the subject item #$SUBJECT_ISSUE from the tracker — this is NOT a clean scan" >&2
    sed 's/^/dup-scan:   /' "$TMP/gh.err" >&2
    exit 2
  fi
  SUBJECT_TITLE="$(jq -r '.title // ""' "$TMP/subject.json")"
  jq -r '.body // ""' "$TMP/subject.json" > "$TMP/subject.body"
else
  if [ -n "$BODY_FILE" ]; then
    cat "$BODY_FILE" > "$TMP/subject.body"
  else
    : > "$TMP/subject.body"
  fi
fi

tokens  "$SUBJECT_TITLE"             > "$TMP/subject.tok"
symbols "$(cat "$TMP/subject.body")" > "$TMP/subject.sym"

# ---------------------------------------------------------------- the corpus
# Two queries, not one: `gh issue list --label A --label B` is an AND, and the corpus
# this needs is the UNION. Merged and de-duplicated by number, so a ticket carrying
# both labels is scored once.
fetch() { # fetch <label> <outfile>
  if ! gh issue list --state open --label "$1" --limit "$CORPUS_LIMIT" \
        --json number,title,body,url,labels > "$2" 2>"$TMP/gh.err"; then
    echo "dup-scan: tracker query failed for label '$1' — this is NOT a clean scan" >&2
    sed 's/^/dup-scan:   /' "$TMP/gh.err" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' "$2" >/dev/null 2>&1; then
    echo "dup-scan: tracker query for label '$1' did not return a JSON array — this is NOT a clean scan" >&2
    return 1
  fi
}

fetch "$QUEUE_LABEL"   "$TMP/queue.json"  || exit 2
fetch "$CLAIMED_LABEL" "$TMP/claimed.json" || exit 2

QUEUE_N="$(jq 'length' "$TMP/queue.json")"
CLAIMED_N="$(jq 'length' "$TMP/claimed.json")"

# No silent caps: a corpus clipped by --limit is a scan with a blind spot, and a blind
# spot nobody is told about reads as coverage.
for pair in "$QUEUE_LABEL:$QUEUE_N" "$CLAIMED_LABEL:$CLAIMED_N"; do
  if [ "${pair##*:}" -ge "$CORPUS_LIMIT" ]; then
    echo "dup-scan: WARNING: the '${pair%:*}' query returned ${pair##*:} items, which is the --limit — the corpus may be truncated and the scan incomplete. Raise --limit." >&2
  fi
done

if [ -n "$SUBJECT_ISSUE" ]; then
  jq -s --argjson self "$SUBJECT_ISSUE" \
    'add | unique_by(.number) | map(select(.number != $self))' \
    "$TMP/queue.json" "$TMP/claimed.json" > "$TMP/corpus.json"
else
  jq -s 'add | unique_by(.number)' "$TMP/queue.json" "$TMP/claimed.json" > "$TMP/corpus.json"
fi

CORPUS_N="$(jq 'length' "$TMP/corpus.json")"

# ---------------------------------------------------------------- score
: > "$TMP/scored"

# Metadata in ONE pass. Four `jq` invocations per corpus item was this scan's dominant
# cost, and a hundred-ticket queue pays it four hundred times. The body still needs a
# per-item extraction because it is multi-line and cannot ride a line-oriented table;
# titles are newline-flattened for the same reason (the tracker forbids them anyway).
jq -r --arg us "$US" \
  '.[] | [ (.number | tostring), (.title // "" | gsub("[\r\n]"; " ")), (.url // "") ] | join($us)' \
  "$TMP/corpus.json" > "$TMP/meta"

i=0
while IFS="$US" read -r num ctitle curl_; do
  jq -r --argjson i "$i" '.[$i].body // ""' "$TMP/corpus.json" > "$TMP/c.body"

  tokens  "$ctitle"            > "$TMP/c.tok"
  symbols "$(cat "$TMP/c.body")" > "$TMP/c.sym"

  shared_tok="$(comm -12 "$TMP/subject.tok" "$TMP/c.tok" | tr '\n' ' ' | sed 's/ *$//')"
  shared_sym="$(comm -12 "$TMP/subject.sym" "$TMP/c.sym" | tr '\n' ' ' | sed 's/ *$//')"
  n_tok="$(comm -12 "$TMP/subject.tok" "$TMP/c.tok" | grep -c . || true)"
  n_sym="$(comm -12 "$TMP/subject.sym" "$TMP/c.sym" | grep -c . || true)"
  score=$(( TITLE_WEIGHT * n_tok + n_sym ))

  # score, number, title, url, shared tokens, shared symbols. The separator is US
  # (\037), NOT a tab: tab is an IFS *whitespace* character, so `read` collapses runs
  # of it and an empty column simply vanishes — which shifts every later field one
  # place left and prints body symbols under the title-token label. A non-whitespace
  # separator preserves empty fields positionally. The score is zero-padded so a plain
  # lexical `sort -r` orders it numerically.
  printf '%06d%s%s%s%s%s%s%s%s%s%s\n' \
    "$score" "$US" "$num" "$US" "$ctitle" "$US" "$curl_" "$US" "$shared_tok" "$US" "$shared_sym" \
    >> "$TMP/scored"
  i=$(( i + 1 ))
done < "$TMP/meta"

# Descending score, ascending number within a tie — deterministic, so two runs over an
# unchanged corpus produce a byte-identical report.
sort -t "$US" -k1,1r -k2,2n "$TMP/scored" > "$TMP/ranked"

emit_row() { # emit_row <score> <num> <title> <url> <toks> <syms>
  printf '  score %-4s #%-6s %s\n' "$1" "$2" "$3"
  if [ -n "$5" ]; then
    printf '                     shared title tokens: %s\n' "$5"
  fi
  if [ -n "$6" ]; then
    printf '                     shared body symbols: %s\n' "$6"
  fi
  if [ -n "$4" ]; then
    printf '                     %s\n' "$4"
  fi
  printf '\n'
}

# Spell out the arithmetic. The scanned count is the UNION less the subject, so it does
# not equal the sum of the two queries, and a summary line that printed all three bare
# numbers would read as an off-by-one in the tool rather than as the de-duplication and
# self-exclusion it actually is.
CORPUS_NOTE="corpus: $CORPUS_N scanned — the union of $QUEUE_N carrying '$QUEUE_LABEL' and $CLAIMED_N carrying '$CLAIMED_LABEL'"
if [ -n "$SUBJECT_ISSUE" ]; then
  CORPUS_NOTE="$CORPUS_NOTE, less the subject"
fi

if [ "$EXPLAIN" -eq 1 ]; then
  echo "dup-scan: --explain — every corpus item, ranked (threshold $THRESHOLD, title weight $TITLE_WEIGHT)"
  echo "dup-scan: $CORPUS_NOTE"
  echo
  while IFS="$US" read -r s n t u tk sy; do
    [ -n "$s" ] || continue
    emit_row "$(( 10#$s ))" "$n" "$t" "$u" "$tk" "$sy"
  done < "$TMP/ranked"
fi

HITS=0
: > "$TMP/hits"
while IFS="$US" read -r s n t u tk sy; do
  [ -n "$s" ] || continue
  if [ "$(( 10#$s ))" -ge "$THRESHOLD" ]; then
    HITS=$(( HITS + 1 ))
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$(( 10#$s ))" "$US" "$n" "$US" "$t" "$US" "$u" "$US" "$tk" "$US" "$sy" >> "$TMP/hits"
  fi
done < "$TMP/ranked"

if [ "$HITS" -eq 0 ]; then
  echo "dup-scan: no candidates at or above threshold $THRESHOLD ($CORPUS_NOTE)"
  exit 0
fi

echo "dup-scan: $HITS candidate(s) at or above threshold $THRESHOLD ($CORPUS_NOTE)"
echo
while IFS="$US" read -r s n t u tk sy; do
  [ -n "$s" ] || continue
  emit_row "$s" "$n" "$t" "$u" "$tk" "$sy"
done < "$TMP/hits"

cat <<'JUDGE'
dup-scan: these are PROPOSALS, not a verdict. Read each candidate and decide:
  - the same work            → do not queue this one; fold it into the candidate, and say so.
  - overlapping but distinct → queue it, and sequence it against the candidate if they
                               touch the same files (a CLAIMED candidate is already in flight).
  - unrelated                → queue it.
Record one Decision Ledger row per candidate judged. Never close a ticket on this output.
JUDGE
exit 10
