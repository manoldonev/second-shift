#!/usr/bin/env bash
# lane-registry.sh — the lean lane liveness registry, and the job ceiling derived from it.
#
# WHY THIS EXISTS (#526). Every lean lane sized its verification sweep to the WHOLE machine:
# tools/run-selftests.sh defaults to 4 workers and this repo's own config asks for 10, and
# nothing anywhere counted lanes. Five concurrent lanes on ten cores measured load 16.9-26.8
# and one lane at 1h46m wall for 4m07s of its own CPU. This file makes the lane count knowable
# so the gate can hand each lane a CEILING on its share.
#
# A CEILING, NOT A SEMAPHORE, and that is the whole design. The suites are independent by
# construction and safe to interleave — they were starving each other, not racing. A
# wait-your-turn lock would put a waiter on the milestone-3 path and convert a slow lane into
# a hung one. Nothing here blocks; the worst case is a lane that reads a stale count and asks
# for more workers than its share, which is exactly today's behavior.
#
# EVERY DEGRADATION IS TOWARD TODAY. An unreadable registry, an unresolvable pid, a `ps` that
# does not answer — each yields the SINGLE-LANE answer (the largest ceiling) and says so. This
# never returns a confident zero, and it never returns a ceiling of 0: a silent drop to serial
# is the fail-open shape #525's T6 exists to remove, not something to introduce here.
#
# THE LIVENESS KEY IS pid PLUS THAT PID'S START TIME. Pids recycle, so a bare pid cannot tell a
# live lane from a dead lane whose number was reissued. The start time is read back from `ps`
# and compared as an OPAQUE STRING — never parsed, never reformatted. That is deliberate: the
# BSD and GNU `lstart` renderings differ, and a dual-form parse is this repo's documented way
# of failing dirty under the other OS. Comparing what one machine's `ps` printed against what
# the same machine's `ps` prints later needs no format at all.
#
# WHICH PID IS "THE LANE". Not this script's, and not its parent's — an agent harness spawns a
# fresh shell per tool call, so both are gone seconds after `entry` and the lane would reap
# itself. The owning process is the nearest ancestor that is NOT a shell: the agent session in
# the two-terminal flow, the spawned session in the scheduler flow. `LEAN_LANE_PID` overrides
# when a caller knows better (a scheduler registering itself). When the walk finds no non-shell
# ancestor it falls back to the immediate parent, which under-counts rather than over-counts.
#
# SCOPE IS THIS REPO'S LANES, NOT THE MACHINE'S. The registry lives beside the other lean run
# state, in the main checkout's pipeline-state dir, which every worktree already shares. Lanes
# in a DIFFERENT repo on the same machine are invisible here and their contention is not
# modelled. Stated as a limit rather than papered over: the measured incident was five lanes of
# one repo, and a machine-global path would need its own lifecycle and its own cleanup story.
#
# USAGE
#   lane-registry.sh register   --registry <file> --issue <key> [--pid <n>] [--from <n>]
#   lane-registry.sh deregister --registry <file> [--issue <key>] [--pid <n>] [--from <n>]
#   lane-registry.sh ceiling    --registry <file>
#   lane-registry.sh lane-pid   [--pid <n>] [--from <n>]
#   lane-registry.sh list       --registry <file>
#
#   --registry  the TSV. Defaults to $LEAN_LANE_REGISTRY. Rows are
#               `pid<TAB>start<TAB>issue<TAB>registered`.
#   --pid       register/deregister/report THIS pid instead of the resolved one.
#   --from      start the ancestor walk here instead of at this script's own pid.
#
# `ceiling` prints one TAB-separated line: `<ceiling> <lanes> <cores> <basis>`, where basis is
# one of live | absent | unreadable | empty | stale. The caller renders the announcement; this
# script does not know what a "milestone" is.
#
# EXIT: 0 on success. 2 for a usage error. `ceiling` is 0 even when it degrades — a degraded
# answer is an answer, and a non-zero there would red a verification lane over a bookkeeping
# file.
#
# TEST SEAM: LEAN_LANE_PS_DIR. When set, process facts are read from
# `<dir>/<pid>.{ppid,lstart,comm}` instead of from `ps`, so a suite can stage an ancestry and a
# recycled pid deterministically without spawning anything. A missing file means "no such
# process". Never set in CI or by an operator; the real `ps` path is exercised by the same
# suite against the live process tree.
#
# bash 3.2: no associative arrays, no mapfile, no ${var,,}. Stock macOS bash is one of this
# repo's two CI lanes, and `declare -A` fails OPEN there.
set -uo pipefail

TAB="$(printf '\t')"

die() { echo "[lane-registry] $1" >&2; exit 2; }
warn() { echo "[lane-registry] $1" >&2; }

# The shell set the ancestor walk steps over. Newline-delimited and matched with `grep -qxF`
# rather than a case glob: exact whole-line membership, no accidental prefix match on a
# command named `bashful`.
SHELL_NAMES='sh
bash
zsh
dash
ksh
ksh93
mksh
pdksh
csh
tcsh
fish
login'

MAX_HOPS=8

# ---------------------------------------------------------------------- process facts
# _ps_field <pid> <ppid|lstart|comm> -> the field on stdout, or rc 1 when the process is gone.
# Whitespace is squeezed and trimmed so a value compares stably across calls; `lstart` is
# padded differently by different ps implementations and even by the same one across widths.
_ps_field() {
  local pid="$1" field="$2" out f
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  if [ -n "${LEAN_LANE_PS_DIR:-}" ]; then
    f="$LEAN_LANE_PS_DIR/$pid.$field"
    [ -f "$f" ] || return 1
    out="$(cat "$f" 2>/dev/null)" || return 1
  else
    out="$(ps -o "$field=" -p "$pid" 2>/dev/null)" || return 1
  fi
  out="$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ')"
  out="${out# }"; out="${out% }"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# _is_shell <comm> — basename, leading '-' stripped (a login shell reports as `-zsh`).
_is_shell() {
  local c="${1##*/}"
  c="${c#-}"
  printf '%s' "$SHELL_NAMES" | grep -qxF -- "$c"
}

# resolve_lane_pid <walk-start-pid> — the owning process of this lane. Always prints something.
resolve_lane_pid() {
  local start="$1" cur next comm hops=0
  if [ -n "${LEAN_LANE_PID:-}" ]; then
    case "$LEAN_LANE_PID" in
      ''|*[!0-9]*) warn "LEAN_LANE_PID='$LEAN_LANE_PID' is not a pid — resolving from the process tree instead." ;;
      *) printf '%s' "$LEAN_LANE_PID"; return 0 ;;
    esac
  fi
  cur="$start"
  # The fallback is the IMMEDIATE parent, which is short-lived under an agent harness. That is
  # the point: an entry keyed on it goes stale within the run and the lane stops being counted,
  # which raises every other lane's ceiling back toward today's value. Under-counting is the
  # safe direction; over-counting is the bug this file exists to fix.
  local fallback
  fallback="$(_ps_field "$cur" ppid)" || fallback="$cur"
  while [ "$hops" -lt "$MAX_HOPS" ]; do
    next="$(_ps_field "$cur" ppid)" || break
    # pid 1 is every process's ancestor, so it can never identify a lane; and a ppid that does
    # not move is a cycle this loop must not ride (an orphan reparented to itself under a
    # container init has been observed elsewhere).
    case "$next" in ''|0|1) break ;; esac
    [ "$next" != "$cur" ] || break
    comm="$(_ps_field "$next" comm)" || break
    if ! _is_shell "$comm"; then printf '%s' "$next"; return 0; fi
    cur="$next"
    hops=$((hops + 1))
  done
  printf '%s' "$fallback"
}

# ---------------------------------------------------------------------- the registry file
REG=""

# live_rows — prints the rows whose pid is still alive AND still carries the recorded start
# time. Rows are dropped, never repaired: a pid whose start time moved is a DIFFERENT process
# that happens to hold a recycled number, and crediting it would be the exact confusion the
# start-time half of the key exists to prevent.
live_rows() {
  local pid start issue reg cur
  while IFS="$TAB" read -r pid start issue reg; do
    [ -n "$pid" ] || continue
    cur="$(_ps_field "$pid" lstart)" || continue
    [ "$cur" = "$start" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$pid" "$start" "$issue" "$reg"
  done < "$REG"
}

# total_rows — non-empty rows, live or not. `grep -c` prints its zero AND exits 1, so the count
# is captured first and the rc branch only replaces it — an `|| echo 0` here would emit TWO
# lines on an empty file and every arithmetic test downstream would error on the pair.
total_rows() {
  local n
  n="$(grep -c '[^[:space:]]' "$REG" 2>/dev/null)" || n=0
  printf '%s' "${n:-0}"
}

# reap — rewrite the registry with only its live rows. Best effort: a registry that cannot be
# rewritten is not an error, it is one more sweep's worth of stale rows, and every reader
# tolerates those already.
reap() {
  local tmp
  [ -w "$REG" ] || return 0
  tmp="$REG.reap.$$"
  live_rows > "$tmp" 2>/dev/null && mv -f "$tmp" "$REG" || rm -f "$tmp"
  return 0
}

# ---------------------------------------------------------------------- cores
# BOTH halves of tools/mutation-sweep.sh's precedent, deliberately, including the fallback:
# `getconf` is POSIX and answers on both CI lanes, whereas an `nproc`-or-`sysctl` dual form is
# the class this repo documents as failing dirty rather than loudly under the other OS.
cores() {
  local c
  c="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || c=""
  case "${c:-}" in ''|*[!0-9]*) c=2 ;; esac
  [ "$c" -ge 1 ] || c=1
  printf '%s' "$c"
}

# ---------------------------------------------------------------------- subcommands
cmd_register() {
  local pid="$1" issue="$2" start dir
  start="$(_ps_field "$pid" lstart)" || {
    # No start time means no liveness key, and a row that cannot be aged out is worse than no
    # row: it would inflate every future lane count forever. Not registering costs this lane
    # its vote and nothing else.
    warn "cannot read the start time of pid $pid — this lane is not registered and will not be counted."
    return 0
  }
  dir="$(dirname "$REG")"
  mkdir -p "$dir" 2>/dev/null || { warn "cannot create '$dir' — this lane is not registered."; return 0; }
  [ -f "$REG" ] || : > "$REG" 2>/dev/null || { warn "cannot create '$REG' — this lane is not registered."; return 0; }
  # Re-registering is idempotent by rewrite, not by append: `entry` is idempotent and a resumed
  # run calls it again, which would otherwise let one lane hold N votes.
  cmd_deregister "$pid" ""
  printf '%s\t%s\t%s\t%s\n' "$pid" "$start" "$issue" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REG" \
    || warn "cannot append to '$REG' — this lane is not registered."
  return 0
}

cmd_deregister() {
  local pid="$1" issue="$2" tmp
  [ -f "$REG" ] || return 0
  [ -w "$REG" ] || { warn "'$REG' is not writable — this lane's row is left behind and will be reaped when its process exits."; return 0; }
  tmp="$REG.dereg.$$"
  # Drops the named pid's row and every dead row in the same pass, so teardown is also the
  # reaping opportunity a lane that never reads `ceiling` would otherwise skip.
  local r_pid r_start r_issue r_reg cur
  : > "$tmp" || return 0
  while IFS="$TAB" read -r r_pid r_start r_issue r_reg; do
    [ -n "$r_pid" ] || continue
    # This lane's own row: dropped. `--issue` NARROWS that match, it does not widen it — a row
    # belonging to another pid is never dropped for carrying the same issue key, which is what
    # a resumed run under a new session would otherwise do to the run it resumed.
    if [ "$r_pid" = "$pid" ]; then
      if [ -z "$issue" ] || [ "$r_issue" = "$issue" ]; then continue; fi
    fi
    cur="$(_ps_field "$r_pid" lstart)" || continue
    [ "$cur" = "$r_start" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$r_pid" "$r_start" "$r_issue" "$r_reg" >> "$tmp"
  done < "$REG"
  mv -f "$tmp" "$REG" || rm -f "$tmp"
  return 0
}

cmd_ceiling() {
  local basis live=0 total=0 lanes c ceil
  if [ ! -e "$REG" ]; then
    basis="absent"
  elif [ ! -r "$REG" ]; then
    basis="unreadable"
  else
    total="$(total_rows)"
    live="$(live_rows | grep -c '[^[:space:]]')" || live=0
    if [ "$total" -eq 0 ]; then basis="empty"
    elif [ "$live" -eq 0 ]; then basis="stale"
    else basis="live"; fi
    reap
  fi
  lanes="$live"
  # The floor is what makes "degrades to the single-lane answer" true for all four non-live
  # bases at once, and it is also what keeps the division below defined.
  [ "$lanes" -ge 1 ] || lanes=1
  c="$(cores)"
  ceil=$((c / lanes))
  [ "$ceil" -ge 1 ] || ceil=1
  printf '%s\t%s\t%s\t%s\n' "$ceil" "$lanes" "$c" "$basis"
}

cmd_list() {
  [ -r "$REG" ] || return 0
  live_rows
}

# ---------------------------------------------------------------------- argv
[ $# -ge 1 ] || die "usage: lane-registry.sh <register|deregister|ceiling|lane-pid|list> [options]"
SUB="$1"; shift

OPT_PID=""; OPT_FROM=""; OPT_ISSUE=""
REG="${LEAN_LANE_REGISTRY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --registry) [ $# -ge 2 ] || die "--registry requires a path"; REG="$2"; shift 2 ;;
    --issue)    [ $# -ge 2 ] || die "--issue requires a key"; OPT_ISSUE="$2"; shift 2 ;;
    --pid)      [ $# -ge 2 ] || die "--pid requires a pid"; OPT_PID="$2"; shift 2 ;;
    --from)     [ $# -ge 2 ] || die "--from requires a pid"; OPT_FROM="$2"; shift 2 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

case "${OPT_PID:-0}" in *[!0-9]*) die "--pid must be a positive integer, got: $OPT_PID" ;; esac
case "${OPT_FROM:-0}" in *[!0-9]*) die "--from must be a positive integer, got: $OPT_FROM" ;; esac

WALK_FROM="${OPT_FROM:-$$}"
# Resolved only where it is used. `ceiling` and `list` answer from the file alone, and walking
# the process tree to produce a value they discard costs two `ps` calls on the milestone-3 path.
LANE_PID=""
case "$SUB" in
  register|deregister|lane-pid) LANE_PID="${OPT_PID:-$(resolve_lane_pid "$WALK_FROM")}" ;;
esac

case "$SUB" in
  lane-pid)
    printf '%s\n' "$LANE_PID"
    ;;
  register)
    [ -n "$REG" ] || die "register requires --registry (or \$LEAN_LANE_REGISTRY)"
    [ -n "$OPT_ISSUE" ] || die "register requires --issue"
    cmd_register "$LANE_PID" "$OPT_ISSUE"
    ;;
  deregister)
    [ -n "$REG" ] || die "deregister requires --registry (or \$LEAN_LANE_REGISTRY)"
    cmd_deregister "$LANE_PID" "$OPT_ISSUE"
    ;;
  ceiling)
    [ -n "$REG" ] || die "ceiling requires --registry (or \$LEAN_LANE_REGISTRY)"
    cmd_ceiling
    ;;
  list)
    [ -n "$REG" ] || die "list requires --registry (or \$LEAN_LANE_REGISTRY)"
    cmd_list
    ;;
  *) die "unknown subcommand: $SUB" ;;
esac
