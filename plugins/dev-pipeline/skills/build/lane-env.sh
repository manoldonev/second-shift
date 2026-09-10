#!/usr/bin/env bash
# lane-env.sh — the LANE_/LEAN_ environment compatibility reader (#833).
#
# WHY THIS EXISTS: the pipeline's environment knobs were spelled `LEAN_*` until the lane dropped
# the "lean" name. A HARD cut was rejected (D-1): an operator or a consumer CI job still exporting
# the old spelling would have it silently ignored, and the symptom of a dropped knob here is a
# FALSE GREEN — attendance off, observe off, a cache store nobody hands down — never an error.
# So every environment read goes through `lane_env`, which takes `LANE_*` first and falls back to
# the retired `LEAN_*`.
#
# THE NOTICE IS ONCE PER PROCESS PER DISTINCT TOKEN, ON STDERR (D-6). Never stdout: these scripts'
# stdout is PARSED by their callers, and the busiest tokens are read at dozens of sites, so a
# per-read notice would both flood a gate log and risk breaking a reader.
#
# STDERR IS NOT INVISIBLE. A caller that captures `2>&1` and compares the result gets this line
# inside the value it is asserting on — this repo's own suites do that routinely, and it is what
# turned one leaked token into four red cases rather than two. The notice firing is a symptom, so
# the fix belongs where the retired spelling reaches the process (scrub BOTH halves of a pair),
# never in a filter here.
#
# Sourced, not executed — it defines one function and one accumulator and dispatches nothing.
# `boundary-evidence.sh` carries the LOCKSTEP twin of the block below inline instead of sourcing
# this file, because it is the PORTABLE payload a consumer's CI fetches as a single file at a
# pinned ref and has nothing to source from.
#
# bash 3.2 compatible (macOS ships it, and CI has a bash-3.2 lane): `${!name+set}` indirection and
# `printf -v` both predate 4.0. `printf -v` rather than a command substitution is deliberate — a
# `$( … )` read runs in a SUBSHELL, where the once-per-process accumulator would be discarded and
# every read would warn again.

# LOCKSTEP-BEGIN lane-env-fallback
LANE_ENV_WARNED=' '
lane_env() { # lane_env <dest-var> <LANE_NAME> [default] [retired-name]
  local __lane_new="$2" __lane_old="${4:-LEAN_${2#LANE_}}"
  if [ -n "${!__lane_new+set}" ]; then
    printf -v "$1" '%s' "${!__lane_new}"
  elif [ -n "${!__lane_old+set}" ]; then
    case "$LANE_ENV_WARNED" in
      *" $__lane_old "*) : ;;
      *) LANE_ENV_WARNED="$LANE_ENV_WARNED$__lane_old "
         printf '[lane-env] notice: %s is the retired spelling of %s and still resolves. Export %s instead; the retired name is removed at the next major.\n' \
           "$__lane_old" "$__lane_new" "$__lane_new" >&2 ;;
    esac
    printf -v "$1" '%s' "${!__lane_old}"
  else
    printf -v "$1" '%s' "${3-}"
  fi
}

# The common case: a knob whose new spelling is `LANE_` + the retired suffix, resolved IN PLACE so
# every existing `${LANE_X:-<default>}` read site keeps its own default and needs no edit. Setting
# an absent token to the empty string is deliberate and safe: every read site uses `:-`, under
# which empty and unset are the same answer, and no site in this repo distinguishes them (`+` forms
# are absent by construction — the companion selftest asserts it).
lane_env_promote() { # lane_env_promote <LANE_NAME>...
  local __lane_n
  for __lane_n in "$@"; do lane_env "$__lane_n" "$__lane_n"; done
}
# LOCKSTEP-END lane-env-fallback
