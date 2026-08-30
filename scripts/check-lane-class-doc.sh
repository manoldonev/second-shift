#!/usr/bin/env bash
# check-lane-class-doc.sh — docs/config-schema.md's reserved-exit-3 claim is DERIVED from
# lean-gate.sh's dispatch, never asserted beside it (#674).
#
# WHY THIS EXISTS. `docs/config-schema.md` states the cross-repo contract for a verify lane's
# reserved exit code `3`: which lanes it is read on, and what milestone 3 does with it. #642
# demoted `lint`, `test` and `extraLanes` to advisory, leaving `typecheck` as the classifier's
# only caller — and the doc went on claiming four lane families. It survived PR #660's three
# review rounds and its full panel, because the file the sentence lives in was never in the diff.
# Nothing coupled the prose to the shell, so nothing could red.
#
# THIS IS NOT A PROSE-PRESENCE GUARD. It does not check that a word is still in a markdown file.
# It reads the CALLER SET out of `lean-gate.sh` and requires the doc's rows to name exactly that
# set — so it fails for a reason no reader of the doc's own diff could see, which is the property
# the prose-presence class structurally lacks (docs/testing.md, tier map).
#
#
# ## What is derived, and from where
#
#   reserved set   the lane keys whose milestone-3 failure routes through `lane_failure_class`.
#                  Derived from GATE by walking every call site of that function.
#   fixed keys     milestone 3's `for key in …` loop. Derived from GATE, one site expected.
#   doc rows       the marker-delimited list in DOC. Each row names one or more lane families
#                  and carries `**reserved**` or `**not reserved**`.
#
# The checks:
#   1. doc reserved-set == code reserved-set, reported in BOTH directions.
#   2. every fixed key has a doc row (a fourth fixed key added silently reds).
#   3. the derivation itself is intact — see fail-closed below.
#
#
# ## FAIL-CLOSED ON AN UNMODELLED DISPATCH
#
# A completeness guard that recognises two shapes out of three reads as complete while being
# blind to the third. So the modelled shape is stated narrowly and everything else REDS rather
# than being dropped from the derived set:
#
#   modelled     a `case` whose subject is `"$key"`, with the arm label and the
#                `lane_failure_class` call on the SAME line — `typecheck) fail_milestone …`.
#   reds         a call site under any other `case` subject (e.g. a future dispatch on an
#                extraLane's name); a call site that is not an arm label at all; a glob arm
#                (`*)`, `t*)`) whose members cannot be named; zero call sites anywhere.
#
# A red here is not "the doc is wrong" — it is "the doc's claim is no longer derivable, and this
# script must be taught the new shape before it can speak for the doc again". The message says so.
#
#
# ## Declared limit (#674 D-4)
#
# Only the FIXED keys are derivable. `extraLanes[]` and setup `lanes[]` are config-driven
# families with no enumerable list inside the gate, so their doc rows are checked for a verdict
# and for not contradicting the reserved set — never against a code-side list, because there is
# none to read. A doc row naming a lane family that does not exist would pass. That is a stated
# hole, not an oversight: the alternative constrains rows the code cannot adjudicate.
#
# Usage: check-lane-class-doc.sh [repo-root]
# Exit code = number of failed checks (repo selftest convention); 99 = environment error.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Asserted before use for the reason scripts/check-lockstep-pairs.sh states: a `cd && pwd` that
# does not run leaves an empty string, `$HERE/..` resolves to `/`, and a walk that finds nothing
# exits 0 — a green over a tree the script never read.
[[ -n "$HERE" ]] || { echo "[lane-class] FATAL: cannot resolve this script's own directory" >&2; exit 99; }
ROOT="${1:-$(cd "$HERE/.." && pwd)}"
[[ -n "$ROOT" && -d "$ROOT" ]] || { echo "[lane-class] FATAL: root is not a directory: '$ROOT'" >&2; exit 99; }

GATE_REL="plugins/dev-pipeline/skills/build-lean/lean-gate.sh"
DOC_REL="docs/config-schema.md"
GATE="$ROOT/$GATE_REL"
DOC="$ROOT/$DOC_REL"

FAILS=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

echo "[lane-class] $ROOT"

# Both subjects must exist. A missing one is a red, never a skip: the two files are the whole
# contract, and "the doc is not there" is not evidence that it agrees with anything.
[[ -f "$GATE" ]] || { bad "the dispatch is missing: $GATE_REL — nothing to derive the reserved set from"; echo "[lane-class] $FAILS failed check(s)"; exit "$FAILS"; }
[[ -f "$DOC" ]]  || { bad "the contract doc is missing: $DOC_REL — nothing to hold the dispatch to"; echo "[lane-class] $FAILS failed check(s)"; exit "$FAILS"; }

# ---- code side ------------------------------------------------------------------------
#
# Emits, one per line:
#   lane<TAB><key>        a derived reserved lane key
#   sites<TAB><n>         how many call sites were seen
#   !subject<TAB>n<TAB>s  call site under a `case` subject that is not $key
#   !shape<TAB>n<TAB>s    call site that is not an arm label on its own line
#   !glob<TAB>n<TAB>s     arm label containing a glob metacharacter
CODE="$(awk '
  function emit_bad(kind, text) { printf("%s\t%d\t%s\n", kind, NR, text) }
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*case[[:space:]]/ {
    subject = "?"
    if (match($0, /case[[:space:]]+"\$[A-Za-z_][A-Za-z0-9_]*"[[:space:]]+in/)) {
      t = substr($0, RSTART, RLENGTH)
      sub(/^case[[:space:]]+"\$/, "", t)
      sub(/"[[:space:]]+in$/, "", t)
      subject = t
    }
  }
  /^[[:space:]]*esac([[:space:]]|$)/ { subject = "" }
  # The loop milestone 3 walks its fixed keys with. One site expected; the count is checked below.
  /^[[:space:]]*for[[:space:]]+key[[:space:]]+in[[:space:]]/ {
    line = $0
    sub(/^[[:space:]]*for[[:space:]]+key[[:space:]]+in[[:space:]]+/, "", line)
    sub(/;.*$/, "", line)
    sub(/[[:space:]]+do[[:space:]]*$/, "", line)
    n = split(line, kk, /[[:space:]]+/)
    for (i = 1; i <= n; i++) if (kk[i] != "") printf("fixed\t%s\n", kk[i])
    fixedsites++
  }
  index($0, "lane_failure_class") == 0 { next }
  index($0, "lane_failure_class()") > 0 { next }     # the definition, not a call
  {
    sites++
    # An empty subject means the call is in no `case` at all — reported as a shape miss, which is
    # what it is. A NON-EMPTY subject that is not $key is the other thing: a real dispatch this
    # script does not model. Two messages, because they need two different repairs.
    if (subject == "") { emit_bad("!shape", $0); next }
    if (subject != "key") { emit_bad("!subject", $0); next }
    if (match($0, /^[[:space:]]*[^)[:space:]]+\)[[:space:]]/)) {
      arms = substr($0, RSTART, RLENGTH)
      sub(/^[[:space:]]*/, "", arms)
      sub(/\)[[:space:]]*$/, "", arms)
      n = split(arms, a, "|")
      for (i = 1; i <= n; i++) {
        if (a[i] ~ /[*?\[]/) emit_bad("!glob", a[i])
        else printf("lane\t%s\n", a[i])
      }
    } else {
      emit_bad("!shape", $0)
    }
  }
  END { printf("sites\t%d\n", sites + 0); printf("fixedsites\t%d\n", fixedsites + 0) }
' "$GATE")"

SITES="$(awk -F'\t' '$1=="sites"{print $2}' <<<"$CODE")"
FIXEDSITES="$(awk -F'\t' '$1=="fixedsites"{print $2}' <<<"$CODE")"
CODE_RESERVED="$(awk -F'\t' '$1=="lane"{print $2}' <<<"$CODE" | LC_ALL=C sort -u)"
FIXED_KEYS="$(awk -F'\t' '$1=="fixed"{print $2}' <<<"$CODE" | LC_ALL=C sort -u)"
UNMODELLED="$(awk -F'\t' '$1 ~ /^!/{print}' <<<"$CODE")"

if [[ -n "$UNMODELLED" ]]; then
  while IFS=$'\t' read -r kind lineno text; do
    case "$kind" in
      '!subject') bad "$GATE_REL:$lineno — lane_failure_class is called under a \`case\` subject that is not \$key. The reserved set is no longer derivable; teach this script the new shape: $text" ;;
      '!shape')   bad "$GATE_REL:$lineno — lane_failure_class is called somewhere that is not a \`case \"\$key\"\` arm label on its own line. The reserved set is no longer derivable; teach this script the new shape: $text" ;;
      '!glob')    bad "$GATE_REL:$lineno — the arm routing to lane_failure_class is a glob ('$text'); its members cannot be named, so the reserved set is not enumerable" ;;
    esac
  done <<<"$UNMODELLED"
fi

if [[ "${SITES:-0}" -eq 0 ]]; then
  bad "$GATE_REL — lane_failure_class has no call sites. Either the classifier is dead code or it was renamed; either way the reservation this doc states is no longer wired."
fi
if [[ "${FIXEDSITES:-0}" -ne 1 ]]; then
  bad "$GATE_REL — expected exactly one \`for key in …\` fixed-key loop, found ${FIXEDSITES:-0}. The fixed-key list is not derivable."
fi

# ---- doc side -------------------------------------------------------------------------
BEGIN_N="$(grep -c -- 'LANE-CLASS-BEGIN' "$DOC")"
END_N="$(grep -c -- 'LANE-CLASS-END' "$DOC")"
if [[ "$BEGIN_N" -ne 1 || "$END_N" -ne 1 ]]; then
  bad "$DOC_REL — expected exactly one LANE-CLASS-BEGIN and one LANE-CLASS-END marker, found $BEGIN_N and $END_N. The claim has no delimited region to read."
  echo "[lane-class] $FAILS failed check(s)"
  exit "$FAILS"
fi

REGION="$(awk '/LANE-CLASS-BEGIN/{inr=1; next} /LANE-CLASS-END/{inr=0} inr' "$DOC")"

# Rows: a list item whose lane names are the backticked tokens before the first em dash, and
# whose verdict is the bolded `reserved` / `not reserved` after it.
DOCROWS="$(awk '
  /^[[:space:]]*-[[:space:]]/ {
    row = $0
    verdict = "?"
    if (index(row, "**not reserved**") > 0)  verdict = "no"
    else if (index(row, "**reserved**") > 0) verdict = "yes"
    head = row
    sub(/ — .*$/, "", head)
    lanes = ""
    while (match(head, /`[^`]+`/)) {
      tok = substr(head, RSTART + 1, RLENGTH - 2)
      sub(/\[\]$/, "", tok)
      lanes = lanes (lanes == "" ? "" : " ") tok
      head = substr(head, RSTART + RLENGTH)
    }
    printf("%s\t%s\t%s\n", verdict, lanes, row)
  }
' <<<"$REGION")"

if [[ -z "$DOCROWS" ]]; then
  bad "$DOC_REL — the LANE-CLASS region has no lane rows. An empty region asserts nothing and would agree with any dispatch."
fi

while IFS=$'\t' read -r verdict lanes row; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "?" ]]; then
    bad "$DOC_REL — a lane row carries neither **reserved** nor **not reserved**: $row"
  fi
  if [[ -z "${lanes:-}" ]]; then
    bad "$DOC_REL — a lane row names no backticked lane: $row"
  fi
done <<<"$DOCROWS"

DOC_RESERVED="$(awk -F'\t' '$1=="yes"{n=split($2,t," "); for(i=1;i<=n;i++) print t[i]}' <<<"$DOCROWS" | LC_ALL=C sort -u)"
DOC_ALL="$(awk -F'\t' '$1=="yes"||$1=="no"{n=split($2,t," "); for(i=1;i<=n;i++) print t[i]}' <<<"$DOCROWS" | LC_ALL=C sort)"
DOC_ALL_UNIQ="$(LC_ALL=C sort -u <<<"$DOC_ALL")"

# A lane claimed by two rows has no single answer, and the looser row would decide it silently.
DUPES="$(LC_ALL=C comm -23 <(printf '%s\n' "$DOC_ALL") <(printf '%s\n' "$DOC_ALL_UNIQ"))"
if [[ -n "${DUPES//[[:space:]]/}" ]]; then
  bad "$DOC_REL — lane(s) named by more than one row, so their verdict is ambiguous: $(tr '\n' ' ' <<<"$DUPES")"
fi

# ---- the comparisons ------------------------------------------------------------------
MISSING_IN_DOC="$(LC_ALL=C comm -23 <(printf '%s\n' "$CODE_RESERVED") <(printf '%s\n' "$DOC_RESERVED"))"
MISSING_IN_CODE="$(LC_ALL=C comm -13 <(printf '%s\n' "$CODE_RESERVED") <(printf '%s\n' "$DOC_RESERVED"))"

if [[ -n "${MISSING_IN_DOC//[[:space:]]/}" ]]; then
  bad "$DOC_REL — the dispatch routes these lane(s) through lane_failure_class and the doc does not mark them **reserved**: $(tr '\n' ' ' <<<"$MISSING_IN_DOC")"
fi
if [[ -n "${MISSING_IN_CODE//[[:space:]]/}" ]]; then
  bad "$DOC_REL — the doc marks these lane(s) **reserved** and the dispatch does not route them through lane_failure_class: $(tr '\n' ' ' <<<"$MISSING_IN_CODE")"
fi

UNDOCUMENTED="$(LC_ALL=C comm -23 <(printf '%s\n' "$FIXED_KEYS") <(printf '%s\n' "$DOC_ALL_UNIQ"))"
if [[ -n "${UNDOCUMENTED//[[:space:]]/}" ]]; then
  bad "$DOC_REL — milestone 3's fixed-key loop runs these lane(s) and the doc's region has no row for them: $(tr '\n' ' ' <<<"$UNDOCUMENTED")"
fi

if [[ "$FAILS" -eq 0 ]]; then
  ok "reserved set derived from $GATE_REL ($SITES call site(s)): $(tr '\n' ' ' <<<"$CODE_RESERVED")— and $DOC_REL agrees"
  ok "every fixed key ($(tr '\n' ' ' <<<"$FIXED_KEYS")) has a row in $DOC_REL"
fi

echo "[lane-class] $FAILS failed check(s)"
exit "$FAILS"
