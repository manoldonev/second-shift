#!/usr/bin/env bash
# check-gate-buckets.sh — every refusal site in the lean lane declares its yield bucket, and an
# unclassified one reds (#636, item 2 of the #605 epic).
#
# WHY THIS EXISTS: docs/pipeline-manifesto.md defines the buckets in prose — a `gates-llm` gate
# never yields to a present operator, a `gates-process` gate may — and #613 shipped the yield
# mechanism. What did not exist was any statement of WHICH gate is which. `OVERRIDE_GATES`
# carries two values chosen by the slice that introduced them; nothing said the other refusals
# were ever considered, and nothing reds when a new one joins the lane unclassified. This is that
# statement, made countable.
#
# THE PREDICATE IS NOT TOTAL, so there are three buckets and not two. Walking the lane's refusal
# sites against the manifesto's binary reading leaves a residue that fits neither arm: a red test
# lane is not a fabrication defense and is not premised on an absent human — it is an objective
# build signal. Forcing those into `gates-process` would make a red suite operator-waivable, which
# is the opposite of what this register is for.
#
#   gates-llm      fabrication / self-approval defense                    never yields
#   gates-signal   the fact is objective (a lane is red, a hash moved)    never yields
#   gates-process  premise is "no human is available to answer this"      may yield when attended
#
# PLUS A FOURTH VALUE THAT IS NOT A BUCKET. `not-a-gate` is what the closed enum needs so that
# the shape enumerator's over-enumeration has a home: the `envfail` usage and environment refusals
# (`PR_HEAD_SHA is unset`, `mktemp failed`, `unknown argument`) and `orchestrate-lean.sh`'s
# exit-0 `terminal` success calls are all provably enumerated by the shape and are none of the
# three. A `not-a-gate` row must say which of the three it is instead, and that is checked.
#
# THE DENOMINATOR IS THIS SCRIPT'S OWN OUTPUT — scripts/check-fail-open-shapes.sh's posture,
# copied deliberately. A completeness claim against a COUNT is unfalsifiable; `--list` prints the
# enumeration, that output IS the denominator by definition, and scripts/gate-buckets.tsv must
# cover it exactly. Neither half can rot quietly: an unclassified site reds, an anchor that
# matches nothing reds as drift, and a row that outlived its site reds too. A fourth red is AC-1's
# "exactly one disposition" read literally — a site claimed by two rows that DISAGREE about its
# bucket has no answer, and without this the looser anchor would decide it silently.
#
# THE CORPUS IS FIVE FILES, declared in CORPUS below. `lean-evidence.sh` is in it because that is
# where the merge-boundary checks actually RUN — check-lean-chain.sh delegates the
# verdict/identity/freshness/ratification arms to it — so a register that classified the chain
# script's own two refusal primitives and delegated the rest would be the vacuous coverage this
# guard exists to prevent.
#
# EVERY REFUSAL PRIMITIVE PER FILE IS NAMED, never assumed to be one. A file that refuses through
# five helpers and is scanned for one is 80% unguarded while reading as covered.
#
# SELF-EXCLUSIONS, stated because an unstated one is a hole in the "output IS the denominator"
# claim (scripts/check-fail-open-shapes.sh:69 is the precedent):
#   * comment lines (`^\s*#`) — a mention is not a call site.
#   * helper DEFINITION lines, excluded by the file's WHOLE declared primitive set rather than by
#     the primitive being enumerated. `orchestrate-lean.sh`'s `envfail() { terminal "$1" 2 "$2"; }`
#     is one line that defines one primitive and calls another; excluding only `envfail`'s own
#     name would leave that line enumerated as a `terminal` site, which is a definition, not a gate.
#   * ARGUMENT positions. The primitive must sit where a COMMAND may start, and that is the
#     whole class, not a hand-picked sample of it: line start, after a separator or grouping
#     character (`;` `&` `|` `(` `)` `{` `}`), or after one of the bash reserved words that is
#     itself followed by a command (`!` `if` `then` `elif` `else` `while` `until` `do` `time`
#     `coproc`), in any run. `CMDPOS` below IS that class. What it excludes is a primitive's NAME
#     appearing as an argument to something else — `launch_note terminal "..."`, a literal inside
#     terminal()'s own body. The earlier draft of this exclusion listed the separators only, which
#     read as "non-command positions" while silently dropping `else envfail "..."` and every
#     one-line `if ...; then fail_milestone ...` — a live shape in the corpus, and the shape a new
#     gate is most likely to be written in. An exclusion whose LABEL is wider than its code is
#     indistinguishable from a forgotten surface, which is what AC-8 exists to prevent.
#
# THE RESIDUAL A SHAPE ENUMERATOR CANNOT CLOSE, stated for the same reason. It has TWO shapes,
# and naming only the first would leave the second looking forgotten:
#   * a NEWLY NAMED refusal helper in a corpus file is not enumerated until it is added to CORPUS.
#   * a refusal made through NO helper at all — an inline `echo "..." >&2; return 2`. Two live
#     instances, both in operator-override.sh (the malformed-override-block and malformed-register-
#     row refusals): they are refusals with the primitive-keyed shape of ordinary code, so nothing
#     keyed to a primitive can see them. AC-3 fixed this file's primitive list at `envfail`, so
#     they are outside this slice's denominator by construction rather than by oversight.
# What the register does catch is the other direction — rename or delete an enumerated primitive
# and every row keyed to it covers zero sites, which reds as drift. There is no honest shape test
# for "is this a refusal", so both residuals are judgment, recorded rather than pretended away.
#
# OUT OF SCOPE, named as a residual rather than left to look forgotten: the ~19 scripts/ + tools/
# CI guards, and the .mjs Workflow gates. Both are their own slices.
#
# Usage:
#   check-gate-buckets.sh [--list] [repo-root]     (default root: the repo above scripts/)
#   --list   print the denominator (key <TAB> line <TAB> text) and exit 0. Checks nothing.
#
# Exit code = number of violations (doctor convention); 0 = clean; 2 = environment refusal.
set -uo pipefail

LIST_ONLY=0
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    # Range-free, as the precedent is: print the header up to its last line, so an edit to the
    # prose above cannot start leaking `set -uo pipefail` into --help.
    -h|--help) sed -n '2,/^# Exit code = number of violations/p' "$0"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$HERE/.." && pwd)}"

TSV_REL="scripts/gate-buckets.tsv"
TSV="$ROOT/$TSV_REL"
OVERRIDE_REL="plugins/dev-pipeline/tools/operator-override.sh"

envfail() { echo "[gate-buckets] $1" >&2; exit 2; }

# The corpus: `<repo-relative path>:<space-separated refusal primitives>`, one per line.
CORPUS='plugins/dev-pipeline/skills/build-lean/lean-gate.sh:fail_milestone block_milestone fail_obligation ticket_refuse envfail
plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:note_violation envfail
plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh:terminal envfail
plugins/dev-pipeline/tools/operator-override.sh:envfail
scripts/check-lean-chain.sh:note_violation fail envfail'

TAB="$(printf '\t')"

# enumerate — the recipe. Prints `key<TAB>lineno<TAB>text`, one live refusal site per line, where
# key is the `path::name` enforcer key docs/prose-blocker-triage.tsv already established.
# CMDPOS — where a command may start, as one named constant so the recipe and the header's
# self-exclusion 3 cannot describe different things. A separator or grouping character, OR a run
# of the bash reserved words that are themselves followed by a command. The reserved-word run is
# what puts `else envfail "..."` and `if ...; then fail_milestone ...` in the denominator; without
# it a new gate written that way joins the lane unclassified and this guard stays green, which is
# the regression #636 was filed against.
CMDPOS='(^|[;&|(){}])[[:space:]]*((!|if|then|elif|else|while|until|do|time|coproc)[[:space:]]+)*'

enumerate() {
  local f prims defs p
  while IFS=: read -r f prims; do
    [[ -n "$f" ]] || continue
    defs="^[[:space:]]*($(printf '%s' "$prims" | tr ' ' '|'))\\(\\)"
    for p in $prims; do
      grep -nE "${CMDPOS}${p}[[:space:]]" "$ROOT/$f" \
        | grep -vE '^[0-9]+:[[:space:]]*#' \
        | grep -vE "^[0-9]+:${defs#^}" \
        | sed -E "s#^([0-9]+):#$f::$p$TAB\\1$TAB#"
    done
  done <<<"$CORPUS" | LC_ALL=C sort -t"$TAB" -k1,1 -k2,2n
}

# The corpus check runs HERE, in the main shell, and NOT inside enumerate(). `envfail` exits, and
# an exit inside the `$(enumerate)` below would kill only the subshell — leaving SITES holding a
# partial denominator and the run continuing against it, which is failing open in the very act of
# checking. lean-gate.sh:3443 spells out the same trap for the same reason.
while IFS=: read -r _cf _cp; do
  [[ -n "$_cf" ]] || continue
  [[ -f "$ROOT/$_cf" ]] || envfail "corpus file is missing: $_cf — the denominator cannot be computed, so nothing here is a disposition disagreement. Fix CORPUS or restore the file."
done <<<"$CORPUS"

SITES="$(enumerate)"

if [[ $LIST_ONLY -eq 1 ]]; then
  [[ -n "$SITES" ]] && printf '%s\n' "$SITES"
  exit 0
fi

violations=0
fail() { echo "[gate-buckets] ✗ $1" >&2; violations=$((violations + 1)); }

# The yield vocabulary is READ, never copied. `OVERRIDE_GATES` already carries a lockstep twin in
# lean-evidence.sh; a third copy here would owe a marker and would be one more thing to drift.
[[ -f "$ROOT/$OVERRIDE_REL" ]] || envfail "cannot read the yield vocabulary: $OVERRIDE_REL is missing"
YIELD_VOCAB="$(sed -nE "s/^OVERRIDE_(GATES|SCOPES)='([^']*)'.*/\\2/p" "$ROOT/$OVERRIDE_REL" | tr '\n' ' ')"
[[ -n "${YIELD_VOCAB// /}" ]] || envfail "$OVERRIDE_REL declares no OVERRIDE_GATES/OVERRIDE_SCOPES values — AC-5's safety arm would pass vacuously against an empty vocabulary"
# Only OVERRIDE_GATES values bind AC-5's "must be gates-process" direction; the scopes are the
# other half of AC-6's accepted forms.
GATE_VOCAB="$(sed -nE "s/^OVERRIDE_GATES='([^']*)'.*/\\1/p" "$ROOT/$OVERRIDE_REL" | tr '\n' ' ')"

in_set() { # in_set <value> <space-separated set>
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

corpus_prims() { # corpus_prims <repo-relative path> — the primitives CORPUS declares for it
  local f prims
  while IFS=: read -r f prims; do
    [[ "$f" == "$1" ]] && { printf '%s' "$prims"; return 0; }
  done <<<"$CORPUS"
  return 0
}

if [[ ! -f "$TSV" ]]; then
  fail "the register is missing: $TSV_REL — the denominator has nothing to be checked against"
else
  COVERED_ROWS="$(mktemp "${TMPDIR:-/tmp}/gate-buckets-rows.XXXXXX")" \
    || envfail "cannot create a temp file to collect the register's rows"
  SITES_F="$(mktemp "${TMPDIR:-/tmp}/gate-buckets-sites.XXXXXX")" \
    || envfail "cannot create a temp file to hold the denominator"
  PASS_OUT="$(mktemp "${TMPDIR:-/tmp}/gate-buckets-pass.XXXXXX")" \
    || envfail "cannot create a temp file for the rows-against-sites pass"
  trap 'rm -f "$COVERED_ROWS" "$SITES_F" "$PASS_OUT"' EXIT

  while IFS="$TAB" read -r rkey rbucket ranchor ryield rwhy; do
    case "${rkey:-}" in ''|'#'*) continue ;; esac
    if [[ -z "${rbucket:-}" || -z "${ranchor:-}" || -z "${ryield:-}" || -z "${rwhy:-}" ]]; then
      fail "malformed row (need 5 tab-separated fields: key bucket anchor yield why): ${rkey}"
      continue
    fi
    rfile="${rkey%%::*}"
    rprim="${rkey##*::}"
    if [[ "$rfile" == "$rkey" || -z "$rprim" ]]; then
      fail "$rkey: the key is not a 'path::primitive' enforcer key"
      continue
    fi
    # The key must name a pair CORPUS actually declares. A row keyed to a primitive the
    # enumerator never scans for could never be checked against anything. Pure bash on purpose:
    # this runs once per register row, and a subprocess per row is what the batching below exists
    # to remove.
    if ! in_set "$rprim" "$(corpus_prims "$rfile")"; then
      fail "$rkey: no such corpus pair — the enumerator does not scan '$rfile' for '$rprim', so this row disposes of nothing"
      continue
    fi
    case "$rbucket" in
      gates-llm|gates-signal|gates-process|not-a-gate) : ;;
      *) fail "$rkey: unknown bucket '$rbucket' (gates-llm | gates-signal | gates-process | not-a-gate)"; continue ;;
    esac

    # ---- AC-5, the register-internal safety arm, both directions ----------------
    if [[ "$rbucket" != "gates-process" && "$ryield" != "-" ]]; then
      fail "$rkey: a '$rbucket' row carries the yield cell '$ryield'. Only gates-process may yield; the empty form is '-'."
    fi
    if [[ "$rbucket" != "gates-process" ]] && in_set "$ryield" "$GATE_VOCAB"; then
      fail "$rkey: the yield cell names the OVERRIDE_GATES value '$ryield' but the row is '$rbucket'. A row that yields IS gates-process — this is the wiring that would make an objective signal operator-waivable."
    fi
    # ---- AC-6, the form of a gates-process yield cell ---------------------------
    if [[ "$rbucket" == "gates-process" ]]; then
      if ! in_set "$ryield" "$YIELD_VOCAB" && [[ ! "$ryield" =~ ^unwired\ —\ .+ ]]; then
        fail "$rkey: a gates-process row's yield cell must name an OVERRIDE_GATES/OVERRIDE_SCOPES value ($YIELD_VOCAB) or read 'unwired — <reason>'; got '$ryield'"
      fi
    fi
    # ---- AC-1, a not-a-gate row says what it is instead -------------------------
    if [[ "$rbucket" == "not-a-gate" && ! "$rwhy" =~ ^(environment\ refusal|usage\ error|success\ path) ]]; then
      fail "$rkey: a not-a-gate row's 'why' must open with what the site IS instead — 'environment refusal', 'usage error' or 'success path'; got: ${rwhy:0:60}"
    fi

    printf '%s\t%s\t%s\n' "$rkey" "$ranchor" "$rbucket" >> "$COVERED_ROWS"
  done < "$TSV"

  # ---- rows x sites, in ONE pass ------------------------------------------------
  # WHY BATCHED. This used to be a subprocess per row (its anchor's hit count) plus a subprocess
  # per site (which rows claim it) — ~460 spawns against this tree, and 3.4s of the guard's 3.5s.
  # The comparison itself is 156 x 305 index() calls, which is nothing; the process table was the
  # whole cost. It matters beyond tidiness: at 3.5s the paired selftest crossed the mutation
  # sweep's 5s slow bar, which is what decides whether the PR lane grades this guard at all.
  #
  # Through ENVIRON and files, never `awk -v`: -v interprets backslash escapes, and anchors quote
  # shell full of them — `\$` would silently become `$` and a row would match nothing while
  # reading as a typo.
  #
  # Emits three tagged streams so one pass answers every question the two loops used to:
  #   HITS  <count> <key> <bucket> <anchor>      one per register row (count may be 0)
  #   UNCL  <key> <line> <text>                  a site no row claims
  #   AMBIG <key> <line> <buckets> <text>        a site claimed by rows that DISAGREE
  printf '%s\n' "$SITES" > "$SITES_F"
  # FILENAME, not the `FNR == NR` idiom: when the rows file is EMPTY awk never enters that block
  # for it, so the sites file's first record satisfies FNR == NR and is silently loaded as a
  # register row. A register whose rows are all comments would then dispose of its own denominator
  # with a blank row — a green-looking pass built from nothing. (g21) is the case.
  CB_ROWS="$COVERED_ROWS" awk -F"$TAB" '
    FILENAME == ENVIRON["CB_ROWS"] { nrow++; rk[nrow] = $1; ra[nrow] = $2; rb[nrow] = $3; next }
    $1 == "" { next }
    {
      buckets = ""; nb = 0
      for (i = 1; i <= nrow; i++) {
        if (rk[i] != $1 || index($3, ra[i]) == 0) continue
        hits[i]++
        # Distinct-bucket set, kept as a padded string so the membership test is a substring
        # one. Counted as it is built rather than re-split afterwards: a separator count is one
        # off-by-one away from reading "two disagreeing rows" as agreement, which is the exact
        # thing this arm exists to catch.
        if (index(buckets, " " rb[i] " ") == 0) { buckets = buckets " " rb[i] " "; nb++ }
      }
      if (nb == 0) { print "UNCL" FS $1 FS $2 FS $3; next }
      if (nb > 1) { gsub(/  +/, " ", buckets); sub(/^ /, "", buckets); sub(/ $/, "", buckets)
                    print "AMBIG" FS $1 FS $2 FS buckets FS $3 }
    }
    END { for (i = 1; i <= nrow; i++) print "HITS" FS (hits[i] + 0) FS rk[i] FS rb[i] FS ra[i] }
  ' "$COVERED_ROWS" "$SITES_F" > "$PASS_OUT"

  # A row with no hits is one of two different things, and only here is it worth a `grep` — on a
  # clean tree this loop runs zero times, which is the other half of why the pass above is
  # batched.
  while IFS="$TAB" read -r tag c rkey rbucket ranchor; do
    [[ "$tag" == "HITS" && "$c" -eq 0 ]] || continue
    rfile="${rkey%%::*}"
    if ! grep -qF -- "$ranchor" "$ROOT/$rfile"; then
      fail "$rkey: ANCHOR DRIFT — '$ranchor' no longer appears in $rfile. Re-anchor the row (or drop it if the site is gone); an anchor that matches nothing disposes of nothing."
    else
      fail "$rkey: the row disposes of '$ranchor' as '$rbucket', but the enumeration finds no such site — the row outlived what it classified. Drop it, or re-anchor it."
    fi
  done < "$PASS_OUT"

  # Every enumerated site must be claimed by some row, and by rows that AGREE. AC-1 says EXACTLY
  # one disposition per site, so two anchors that both cover a site while disagreeing about its
  # bucket is not a redundancy — it is a site with no answer, and the looser of the two would
  # otherwise decide it silently.
  while IFS="$TAB" read -r tag skey sline sx sy; do
    case "$tag" in
      UNCL)
        fail "${skey%%::*}:$sline UNCLASSIFIED refusal site (${skey##*::}) — every gate in the lane declares its bucket. Add a row to $TSV_REL:
      $(printf '%s' "$sx" | sed -e 's/^[[:space:]]*//')" ;;
      AMBIG)
        fail "${skey%%::*}:$sline is claimed by rows disposing of it as BOTH: $sx. A site carries exactly one bucket; tighten whichever anchor is reaching past its own site:
      $(printf '%s' "$sy" | sed -e 's/^[[:space:]]*//')" ;;
    esac
  done < "$PASS_OUT"

  # AC-4: the covered-site count per row, always printed. A row whose anchor swallows more than
  # one site is legitimate — it is how the mechanical `envfail` classes stay one row instead of
  # 132 — but it is also how a FUTURE refusal gets dispositioned by an anchor nobody re-read. The
  # count is what makes that visible rather than silent.
  if grep -q '^HITS' "$PASS_OUT"; then
    echo "[gate-buckets] coverage (sites per row):"
    grep '^HITS' "$PASS_OUT" | LC_ALL=C sort -t"$TAB" -k3,3 \
      | while IFS="$TAB" read -r _tag c k b a; do printf '  %4s  %-12s  %s  «%s»\n' "$c" "$b" "$k" "$a"; done
  fi
fi

if [[ $violations -eq 0 ]]; then
  n="$(printf '%s' "$SITES" | grep -c .)"
  r="$(grep -cv '^[[:space:]]*\(#\|$\)' "$TSV")"
  echo "[gate-buckets] ✓ $n enumerated refusal site(s) across $(printf '%s' "$CORPUS" | grep -c .) file(s), all bucketed by $r register row(s)."
fi
exit "$violations"
