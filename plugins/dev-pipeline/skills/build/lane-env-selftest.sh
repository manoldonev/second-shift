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
# lane-bench-arm.sh refuses on an unreadable manifest and NAMES the path it was handed, so the
# retired export is proven to have reached the reader rather than merely to have been noticed.
ARM="$ROOT/tools/lane-bench-arm.sh"
if [ ! -f "$ARM" ]; then
  fail "(j) $ARM is missing — the sourcing wiring has no witness"
else
  out="$(LEAN_ARM_MANIFEST="$WORK/no-such-manifest" bash "$ARM" 2>&1)"
  if grep -qF "$WORK/no-such-manifest" <<<"$out" && grep -qF 'LEAN_ARM_MANIFEST is the retired spelling' <<<"$out"; then
    pass "(j) a sourcing script honors the retired spelling end to end"
  else fail "(j) lane-bench-arm.sh did not read LEAN_ARM_MANIFEST: $out"; fi
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
missing=""
knobs=0
while IFS= read -r f; do
  # CODE ONLY on the read side: a `#`-leading line is documentation, and this repo's own compat
  # header quotes the `${LANE_X:-<default>}` shape it describes. On the promote side, fold line
  # continuations first — a promote list long enough to wrap would otherwise read as half a list,
  # which fails in the SAFE direction but for a reason no reader of the diff could see.
  reads="$(sed 's/^[[:space:]]*#.*$//' "$f" 2>/dev/null \
             | grep -oE '\$\{LANE_[A-Z0-9_]+:-' | sed 's/^\${//; s/:-$//' | sort -u)"
  [ -n "$reads" ] || continue
  promoted="$(awk '{ while (sub(/\\$/, "")) { if ((getline nxt) <= 0) break; $0 = $0 nxt } print }' "$f" 2>/dev/null \
                | grep -oE 'lane_env(_promote)?[ ][A-Z_0-9 ]*' | grep -oE 'LANE_[A-Z0-9_]+' | sort -u)"
  for t in $reads; do
    grep -qE "(^|[[:space:];(])$t=" "$f" && continue
    knobs=$((knobs + 1))
    printf '%s\n' "$promoted" | grep -qx "$t" || missing="$missing$(basename "$f"):$t "
  done
done < <(cd "$ROOT" && git ls-files '*.sh' | grep -v -- '-selftest\.sh$' | grep -v 'lane-env\.sh$' | sed "s|^|$ROOT/|")
if [ "$knobs" -eq 0 ]; then
  fail "(l) the derivation found NO environment knobs at all — it is measuring nothing"
elif [ -n "$missing" ]; then
  fail "(l) $knobs knob(s) discovered, and these are read without a retired-spelling fallback: $missing"
else
  pass "(l) all $knobs discovered LANE_ environment knob(s) are promoted"
fi

# ---- (m) nothing distinguishes set-from-unset, which is what makes (g)/(i) safe ----------------
# lane_env_promote DEFINES an absent knob as the empty string. That is behavior-preserving only
# while every reader uses `:-`, under which empty and unset are one answer. A `${LANE_X+…}` or
# `${LANE_X:+…}` reader would start seeing "set" for a knob nobody exported.
plus="$(cd "$ROOT" && git grep -lE '\$\{LANE_[A-Z0-9_]+:?\+' -- '*.sh' 2>/dev/null)"
if [ -z "$plus" ]; then
  pass "(m) no reader distinguishes a set-but-empty LANE_ knob from an unset one"
else fail "(m) promote-in-place is unsafe — these files test set-vs-unset on a LANE_ knob: $plus"; fi

echo "[lane-env-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
