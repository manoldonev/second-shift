#!/usr/bin/env bash
# lane-env-selftest.sh — proves lane-env.sh, the LANE_/LEAN_ environment compatibility reader.
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures => a per-tool
# behavioral selftest. The invariant is a PURE function of the process environment with no
# composed verdict path and no terminal write, so no scenario in scenario-liveness-selftest.sh
# covers it — the scenarios that DO compose against the gate exercise the knobs under their
# CURRENT spelling, which is the one reading this file cannot get wrong.
#
# WHAT WOULD BREAK SILENTLY. Every failure here is a FALSE GREEN, never an error: a retired
# export that stops resolving turns attendance off, observe off, or a cache store nobody hands
# down, and the run proceeds looking healthy. So the suite asserts the VALUE reaches the reader,
# not merely that a notice was printed — and the two end-to-end cases (j) and (k) run REAL
# shipped scripts rather than re-declaring the helper, one per wiring shape: (j) a script that
# SOURCES the lib, (k) the portable payload that carries the LOCKSTEP twin INLINE. A lockstep
# pass proves the two texts agree; only (k) proves the inlined one is actually CALLED.
#
# Case (l) is the coverage derivation: it reads the env-knob set out of the shipped scripts and
# requires each to be promoted, so a knob added later without its fallback reds HERE rather than
# in a consumer's lane six months on. It fails closed — an empty discovered set is a FAIL, not a
# vacuous pass. Case (m) pins the one assumption the promote-in-place design rests on.
#
# ZERO NETWORK, zero fixtures beyond a mktemp scratch file.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
# SC2016 is disabled file-wide: `probe` takes its snippet as a SINGLE-QUOTED string on purpose —
# the body is evaluated in a child shell, where `$V` must still be a variable reference and not
# this shell's (empty) expansion. Every hit shellcheck reports here is that idiom working.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lane-env.sh"
ROOT="$(cd "$HERE/../../../.." && pwd)"

PASSES=0
FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$LIB" ]; then
  echo "FATAL: $LIB does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-env-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "[lane-env-selftest]"

# `probe` runs one snippet in a FRESH bash with the lib sourced, capturing stdout and stderr
# separately — the stdout/stderr split is half of what this suite exists to assert, so the two
# streams are never merged.
probe() { # probe <env-assignments-as-one-string> <snippet>
  ( eval "export $1" 2>/dev/null; bash -c '. "$0"; '"$2" "$LIB" ) >"$WORK/out" 2>"$WORK/err"
}

# ---- (a) the lib defines both entry points ---------------------------------------------------
# POSITIVE CONTROL: without it every "should not warn" case below would pass on a shell that
# never defined the function at all.
probe 'X=1' 'type -t lane_env; type -t lane_env_promote'
if [ "$(tr '\n' ' ' < "$WORK/out")" = "function function " ]; then
  pass "(a) sourcing lane-env.sh defines lane_env and lane_env_promote"
else fail "(a) the lib did not define both entry points: $(cat "$WORK/out")"; fi

# ---- (b) the current spelling wins, silently -------------------------------------------------
probe 'LANE_T=new LEAN_T=old' 'lane_env V LANE_T fallback; printf "%s" "$V"'
if [ "$(cat "$WORK/out")" = "new" ] && [ ! -s "$WORK/err" ]; then
  pass "(b) LANE_ wins over a set LEAN_, and says nothing"
else fail "(b) got out='$(cat "$WORK/out")' err='$(cat "$WORK/err")'"; fi

# ---- (c) the retired spelling resolves, and the notice is on STDERR ---------------------------
# The stream matters more than the wording: these scripts' stdout is PARSED by their callers, so
# a notice printed there is a reader broken by a deprecation warning.
probe 'LEAN_T=old' 'lane_env V LANE_T fallback; printf "%s" "$V"'
if [ "$(cat "$WORK/out")" = "old" ] && grep -q 'LEAN_T' "$WORK/err" && ! grep -q 'LEAN_T' "$WORK/out"; then
  pass "(c) the retired LEAN_ spelling resolves and notices on stderr, never stdout"
else fail "(c) got out='$(cat "$WORK/out")' err='$(cat "$WORK/err")'"; fi

# ---- (d) once per process per distinct token --------------------------------------------------
# The busiest tokens are read at dozens of sites; a per-read notice would flood a gate log.
probe 'LEAN_T=old' 'lane_env A LANE_T; lane_env B LANE_T; lane_env C LANE_T; printf "%s%s%s" "$A" "$B" "$C"'
n="$(grep -c 'LEAN_T' "$WORK/err")"
if [ "$(cat "$WORK/out")" = "oldoldold" ] && [ "$n" -eq 1 ]; then
  pass "(d) three reads of one retired token notice exactly once"
else fail "(d) expected one notice over three reads, got $n; out='$(cat "$WORK/out")'"; fi

# ---- (e) ...but PER TOKEN, not per process ----------------------------------------------------
probe 'LEAN_T=1 LEAN_U=2' 'lane_env A LANE_T; lane_env B LANE_U'
if [ "$(grep -c 'LEAN_T' "$WORK/err")" -eq 1 ] && [ "$(grep -c 'LEAN_U' "$WORK/err")" -eq 1 ]; then
  pass "(e) two distinct retired tokens each get their own notice"
else fail "(e) per-token accounting collapsed: $(cat "$WORK/err")"; fi

# ---- (f) neither set: the caller's default, silently ------------------------------------------
probe 'X=1' 'lane_env V LANE_ABSENT thedefault; printf "%s" "$V"'
if [ "$(cat "$WORK/out")" = "thedefault" ] && [ ! -s "$WORK/err" ]; then
  pass "(f) with neither spelling set the caller's default stands, with no notice"
else fail "(f) got out='$(cat "$WORK/out")' err='$(cat "$WORK/err")'"; fi

# ---- (g) a set-but-EMPTY current spelling is an ANSWER, not an absence -------------------------
# The scrub path depends on this: milestone 3 disables the selftest cache by exporting
# LANE_SELFTEST_CACHE_DIR= into the lane child. If empty read as "unset", the child would fall
# back to a stale LEAN_ export and re-enable the store the gate just turned off.
probe 'LANE_T= LEAN_T=old' 'lane_env V LANE_T fallback; printf "[%s]" "$V"'
if [ "$(cat "$WORK/out")" = "[]" ] && [ ! -s "$WORK/err" ]; then
  pass "(g) an empty LANE_ is honored as an empty answer and does not fall back"
else fail "(g) an empty current spelling fell through: out='$(cat "$WORK/out")' err='$(cat "$WORK/err")'"; fi

# ---- (h) an explicit retired name, for the tokens that did not rename mechanically -------------
# #833 AC-15: the bench family's LEAN_BENCH_LANE_BIN / LEAN_BENCH_SS_ROOT do not become
# LANE_BENCH_LANE_BIN / LANE_BENCH_SS_ROOT, so their retired names cannot be derived.
probe 'LEAN_BENCH_SS_ROOT=/somewhere' 'lane_env V LANE_BENCH_ROOT "" LEAN_BENCH_SS_ROOT; printf "%s" "$V"'
if [ "$(cat "$WORK/out")" = "/somewhere" ] && grep -q 'LEAN_BENCH_SS_ROOT' "$WORK/err"; then
  pass "(h) a non-derivable retired name resolves when passed explicitly"
else fail "(h) got out='$(cat "$WORK/out")' err='$(cat "$WORK/err")'"; fi

# ---- (i) promote resolves IN PLACE and never clobbers a set current spelling -------------------
probe 'LEAN_P=fromold LANE_Q=fromnew LEAN_Q=shadowed' 'lane_env_promote LANE_P LANE_Q LANE_R; printf "%s|%s|[%s]" "$LANE_P" "$LANE_Q" "$LANE_R"'
if [ "$(cat "$WORK/out")" = "fromold|fromnew|[]" ]; then
  pass "(i) lane_env_promote fills from the retired name, leaves a set current name alone, and defines the absent one empty"
else fail "(i) got '$(cat "$WORK/out")'"; fi

# ---- (j) END TO END in a shipped script that SOURCES the lib ----------------------------------
# `operator-override.sh state` answers `marked-headless` ONLY when the attend-mode knob resolved,
# and `no-session-identity` when it did not — two different words for two different reads, so this
# proves the retired export reached the reader rather than merely that a notice was printed.
#
# The witness is a script that SHIPS in this plugin, deliberately: install-topology-selftest.sh
# re-runs every shipped suite from a staged install cache where the repo's own tools/ does not
# exist, and a case that reached for one would red there while proving nothing about the install.
OVR="$HERE/../../tools/operator-override.sh"
if [ ! -f "$OVR" ]; then
  fail "(j) $OVR is missing — the sourcing wiring has no witness"
else
  with="$(cd "$WORK" && env -u CLAUDE_CODE_SESSION_ID LEAN_ATTEND_MODE=headless bash "$OVR" state 2>&1)"
  without="$(cd "$WORK" && env -u CLAUDE_CODE_SESSION_ID -u LEAN_ATTEND_MODE -u LANE_ATTEND_MODE bash "$OVR" state 2>&1)"
  if grep -q 'marked-headless' <<<"$with" \
     && grep -q 'LEAN_ATTEND_MODE is the retired spelling' <<<"$with" \
     && ! grep -q 'marked-headless' <<<"$without"; then
    pass "(j) a sourcing script honors the retired spelling end to end"
  else fail "(j) operator-override.sh did not read LEAN_ATTEND_MODE — with='$with' without='$without'"; fi
fi

# ---- (k) END TO END in the PORTABLE payload, which carries the twin INLINE ---------------------
# boundary-evidence.sh cannot source anything — a consumer's CI fetches it as ONE file at a
# pinned ref — so its copy is the LOCKSTEP twin. check-lockstep-pairs.sh proves the two texts
# agree; only this case proves the inlined copy is on the execution path.
EV="$HERE/boundary-evidence.sh"
if [ ! -f "$EV" ]; then
  fail "(k) $EV is missing — the inline-twin wiring has no witness"
else
  # The payload refuses outside a git repo before it reads any knob, so the case needs a tree.
  # A bare `git init` is enough: the refusal under test fires on the ENV value, ahead of every
  # artifact read, and an empty repo keeps the case zero-fixture.
  mkdir -p "$WORK/evtree" && ( cd "$WORK/evtree" && git init -q . ) >/dev/null 2>&1
  out="$(cd "$WORK/evtree" && PIPELINE_BRANCH_PREFIX='claude/x-' LEAN_BOT_ENABLED=bogus bash "$EV" classify 2>&1)"
  if grep -qF "unknown bot-enabled value 'bogus'" <<<"$out"; then
    pass "(k) the portable payload's inline twin is on the execution path"
  else fail "(k) boundary-evidence.sh did not read LEAN_BOT_ENABLED: $out"; fi
fi

# ---- (l) COVERAGE DERIVATION: every env knob read is a knob promoted --------------------------
# Read the fact out of the code on BOTH sides. A `${LANE_X:-…}` read that the script does not
# assign itself IS an environment knob; every one of them must be promoted, or the retired
# spelling of that knob silently stops resolving. Fails closed: an empty discovered set is a
# FAIL, because a derivation that found nothing proves nothing.
#
# TWO TOPOLOGIES. In the repo the file set is `git ls-files`. From a STAGED INSTALL CACHE — where
# install-topology-selftest.sh re-runs every shipped suite and there is no git repo at all — it is
# a walk of the installed plugin root. The derivation is the same either way; only the census
# differs, and the fail-closed floor below is what stops the no-git case from passing vacuously.
if SCAN_ROOT="$(cd "$ROOT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$SCAN_ROOT" ]; then
  scan_list() { ( cd "$SCAN_ROOT" && git ls-files '*.sh' ); }
else
  SCAN_ROOT="$(cd "$HERE/../.." && pwd)"
  scan_list() { ( cd "$SCAN_ROOT" && find . -name '*.sh' -type f | sed 's|^\./||' ); }
fi

missing=""
knobs=0
ALL_KNOBS=" "
while IFS= read -r f; do
  case "$f" in *-selftest.sh|*/lane-env.sh|lane-env.sh) continue ;; esac
  [ -f "$SCAN_ROOT/$f" ] || continue
  # CODE ONLY on the read side: a `#`-leading line is documentation, and this repo's own compat
  # header quotes the `${LANE_X:-<default>}` shape it describes. On the promote side, fold line
  # continuations first — a promote list long enough to wrap would otherwise read as half a list,
  # which fails in the SAFE direction but for a reason no reader of the diff could see.
  f_code="$(sed 's/^[[:space:]]*#.*$//' "$SCAN_ROOT/$f" 2>/dev/null)"
  reads="$(grep -oE '\$\{LANE_[A-Z0-9_]+:-' <<<"$f_code" | sed 's/^\${//; s/:-$//' | sort -u)"
  [ -n "$reads" ] || continue
  promoted="$(awk '{ while (sub(/\\$/, "")) { if ((getline nxt) <= 0) break; $0 = $0 nxt } print }' "$SCAN_ROOT/$f" 2>/dev/null \
                | grep -oE 'lane_env(_promote)?[ ][A-Z_0-9 ]*' | grep -oE 'LANE_[A-Z0-9_]+' | sort -u)"
  for t in $reads; do
    # A file that ASSIGNS the knob itself is not reading an environment knob there, so it is not
    # this census's business. The test is narrow on PURPOSE: comment-stripped, and only where a
    # shell assignment can actually stand — line start, after a `;`/`&`/`|`, or after
    # export/local/readonly/declare. Accepting a bare `(` or any whitespace matched the knob's own
    # name quoted inside a MESSAGE string — `(LANE_ATTEND_MODE=headless)`, `(LANE_SELFTEST_CACHE=0)`
    # — and dropped four knobs from the census that (l) and (n) BOTH walk. One of them was
    # LANE_ATTEND_MODE, whose half-cleared scrub (n) exists to catch and could not see.
    grep -qE "(^[[:space:]]*|[;&|][[:space:]]*|[[:space:]](export|local|readonly|declare)[[:space:]]+)$t=" \
      <<<"$f_code" && continue
    knobs=$((knobs + 1))
    case " $ALL_KNOBS " in *" $t "*) : ;; *) ALL_KNOBS="$ALL_KNOBS$t " ;; esac
    printf '%s\n' "$promoted" | grep -qx "$t" || missing="$missing$(basename "$f"):$t "
  done
done < <(scan_list)
if [ "$knobs" -eq 0 ]; then
  fail "(l) the derivation found NO environment knobs at all under $SCAN_ROOT — it is measuring nothing"
elif [ -n "$missing" ]; then
  fail "(l) $knobs knob(s) discovered, and these are read without a retired-spelling fallback: $missing"
else
  pass "(l) all $knobs discovered LANE_ environment knob(s) are promoted"
fi

# ---- (m) nothing distinguishes set-from-unset, which is what makes (g)/(i) safe ----------------
# lane_env_promote DEFINES an absent knob as the empty string. That is behavior-preserving only
# while every reader uses `:-`, under which empty and unset are one answer. A reader that tested
# set-vs-unset on a LANE_ knob would start seeing "set" for one nobody exported.
#
# A here-string rather than a pipeline into a quiet grep: a dead producer scores as "no match",
# which here would read as "the repo is clean" — the fail-open shape
# scripts/check-fail-open-shapes.sh exists to refuse, and a false clean is this case's own failure
# mode. (The shape is named in words on purpose; spelling it literally would make this comment
# match that guard's census.)
plus=""
while IFS= read -r cand; do
  [ -f "$SCAN_ROOT/$cand" ] || continue
  cand_code="$(sed 's/^[[:space:]]*#.*$//' "$SCAN_ROOT/$cand" 2>/dev/null)"
  grep -qE '\$\{LANE_[A-Z0-9_]+:?\+' <<<"$cand_code" && plus="$plus$cand "
done < <(scan_list)
if [ -z "$plus" ]; then
  pass "(m) no reader distinguishes a set-but-empty LANE_ knob from an unset one"
else fail "(m) promote-in-place is unsafe — these files test set-vs-unset on a LANE_ knob: $plus"; fi

# ---- (n) a file that CLEARS a knob must clear BOTH spellings ----------------------------------
# The mirror image of (l). A suite or a lane that scrubs `LANE_X` — at suite scope, or per case
# with `env -u` — is reaching for the documented ABSENT-value behavior. After the fallback shipped,
# the ambient export in the wild is the RETIRED one, so clearing half a pair is not hermeticity, it
# is hermeticity's shape: the value walks straight through and the default under test is silently
# falsified. Measured on this ticket — milestone-gate-selftest.sh's suite-scope
# `unset LANE_RUN_MODEL` let the scheduler's `LEAN_RUN_MODEL` reach `(m1b)` and `(p5)` again.
#
# PER FILE, not per line: clearing the retired twin ONCE at suite scope covers every case below it,
# and that is the better shape — it states the file's hermeticity where a reader looks for it
# instead of repeating a pair at thirty call sites.
#
# WHOLE TOKENS, both halves. Every knob here is a PREFIX of another one — `LANE_GATE` of
# `LANE_GATE_ANY_TREE`, `LANE_SELFTEST_CACHE` of `LANE_SELFTEST_CACHE_DIR` — so a substring test
# scores the LONGER scrub as defending the SHORTER token and calls a half-cleared pair clean.
# That is the fail-open shape this case exists to refuse, arriving in the case itself: with the
# substring form, milestone-gate-selftest.sh's `unset LEAN_SELFTEST_CACHE_DIR` satisfied the
# requirement for the bare `LEAN_SELFTEST_CACHE`, which was NOT cleared, and four of that suite's
# cases were falsified by an ambient export of it. The same relation applies to the counting half:
# a file scrubbing only `LANE_SELFTEST_CACHE_DIR` used to be counted as defending
# `LANE_SELFTEST_CACHE`, inflating `defenses` with a pair nobody wrote.
scrub_token_set() {   # $1 = comment-stripped code, $2 = LANE_ | LEAN_ -> " TOK TOK "
  # `(`/`)`/`;`/`|`/`&` become their own words first, so `$( unset X` yields `unset` and a
  # trailing `LANE_X;` yields `LANE_X` — and a `;` still TERMINATES an `unset` operand list,
  # which is what keeps `unset LANE_A; foo LANE_B` from claiming LANE_B.
  awk -v pfx="$2" '
    { gsub(/[();|&]/, " & ")
      for (i = 1; i <= NF; i++) {
        if ($i == "unset") {
          for (j = i + 1; j <= NF && $j ~ /^[A-Za-z_][A-Za-z0-9_]*$/; j++)
            if (index($j, pfx) == 1) print $j
          i = j - 1
        } else if ($i == "-u" && i < NF && $(i + 1) ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          if (index($(i + 1), pfx) == 1) print $(i + 1)
          i++
        }
      }
    }' <<<"$1" | sort -u | tr '\n' ' '
}
leaky=""
defenses=0
while IFS= read -r sf; do
  [ -f "$SCAN_ROOT/$sf" ] || continue
  sf_code="$(sed 's/^[[:space:]]*#.*$//' "$SCAN_ROOT/$sf" 2>/dev/null)"
  sf_scrubs=" $(scrub_token_set "$sf_code" LANE_)"
  [ "$sf_scrubs" != " " ] || continue
  # The retired side is collected SEPARATELY: a suite-scope `unset LEAN_GATE …` names no LANE_
  # token at all, so the census above cannot see it, and checking against that census alone would
  # refuse the very shape this case asks for.
  sf_retired=" $(scrub_token_set "$sf_code" LEAN_)"
  for t in $ALL_KNOBS; do
    case "$sf_scrubs" in
      *" $t "*) : ;;
      *) continue ;;
    esac
    defenses=$((defenses + 1))
    retired="LEAN_${t#LANE_}"
    case "$sf_retired" in
      *" $retired "*) : ;;
      *) leaky="$leaky$(basename "$sf"):$t " ;;
    esac
  done
done < <(scan_list)
if [ "$defenses" -eq 0 ]; then
  fail "(n) no LANE_ knob is scrubbed anywhere under $SCAN_ROOT — the pairing rule is measuring nothing"
elif [ -n "$leaky" ]; then
  fail "(n) $defenses (file, knob) scrub pair(s) found, and these clear only the current spelling, so the retired one still resolves: $leaky"
else
  pass "(n) all $defenses (file, knob) scrub pair(s) clear the retired spelling too"
fi

echo "[lane-env-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
