#!/usr/bin/env bash
# reap-lean-fixtures.sh — removes leangate.*/orchestrate-lean-selftest.* fixture directories a
# signal-killed suite left behind (#528).
#
# WHY THIS EXISTS. lean-gate-selftest.sh and orchestrate-lean-selftest.sh each allocate a
# templated `mktemp -d -t <name>.XXXXXX` work dir and clean it up with a `trap ... EXIT`. On macOS
# that `-t` path resolves against _CS_DARWIN_USER_TEMP_DIR, NOT against TMPDIR — this script's
# `${TMPDIR:-/tmp}` default reaches it only because launchd exports TMPDIR already set to that same
# directory (see CLAUDE.md's killed-sweep note for the derivation, and --dir to aim it elsewhere).
# The template is not the problem either way. A trap is: a suite killed by a SIGNAL (a `timeout`,
# a reaped background job, several concurrent sweeps starving each other) never reaches it, and
# the directory survives. Measured live: 107 `leangate.*` and 73 `orchestrate-lean-selftest.*`
# orphans on one machine.
#
# AGE ALONE IS UNSAFE. CLAUDE.md records install-topology at 319-584s and the full sweep at
# 5:22-13:12 — a LIVE fixture is routinely tens of minutes old, so reaping on age alone would
# delete exactly what this script exists to protect. Both suites now stamp OWNERSHIP into the
# template instead:
#
#   leangate.<pid>.<stamp>.XXXXXX
#   orchestrate-lean-selftest.<pid>.<stamp>.XXXXXX
#
# <pid> is the suite's own process id. <stamp> is that pid's process start time, read back from
# `ps -o lstart=` and sanitized to [A-Za-z0-9_] — treated as an OPAQUE STRING throughout, never
# parsed or reformatted, because BSD and GNU render `lstart` differently and a dual-form parse
# is this repo's documented way of failing dirty under the other OS.
#
# PRODUCER AND CONSUMER SHARE ONE EXPRESSION — tools/fixture-stamp.sh, sourced by this script
# and by both fixture-producing suites. They used to carry the sanitization twice in two shapes
# that agreed only on a `ps` padding lstart with a trailing blank; under one that does not, the
# stamp read back never matched the stamp written and this script deleted LIVE fixtures. See
# that file's header for the measurement.
#
# A directory is reap-eligible only when BOTH hold:
#   1. OWNERSHIP says it is not live: the pid is gone, or a DIFFERENT process now holds a
#      recycled pid (its current `lstart` no longer matches the embedded stamp). "Could not
#      tell" is a THIRD answer, not a synonym for the second: a pid that is alive but whose
#      start time cannot be read leaves the directory in place. Every failure to establish
#      ownership must resolve toward keeping, because the cost of keeping is disk and the cost
#      of deleting is a live suite's working tree.
#   2. AGE clears a floor — a small one (MIN_AGE_OWNED) when ownership already answered the
#      safety question, a large one (MIN_AGE_LEGACY, clearing the documented worst-case suite
#      duration by a wide margin) for a name this script does not recognize at all: an
#      unstamped legacy orphan (predating this fix) or anything with no parseable pid segment.
#      Age is the floor beneath ownership, never a substitute for it.
#
# CROSS-LANE SAFETY. Two sweeps entering at once can both select the same candidate. The
# ownership check happens immediately before the delete (a narrow window), and `rm -rf` is
# treated as best-effort: a directory that vanishes mid-walk (removed by the other sweep) is
# reported as skipped, never as a fatal error propagated to the caller.
#
# USAGE
#   reap-lean-fixtures.sh [--dir <tmp-root>] [--min-age-owned-secs <n>]
#                         [--min-age-legacy-secs <n>] [--dry-run]
#
# Prints one line per directory removed, kept, or skipped, then a summary line. Exit 0 unless a
# usage error (exit 2) — a reap failure never gates the caller; see run-selftests.sh's call site.
set -uo pipefail

die() { echo "[reap-lean-fixtures] $1" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
# Not optional here, unlike the producer side: without the shared expression this script cannot
# read a stamp at all, and a reaper that silently fell back to age alone is the unsafe shape.
# shellcheck source=tools/fixture-stamp.sh
[ -r "$HERE/fixture-stamp.sh" ] || die "the sibling fixture-stamp.sh is absent — ownership cannot be established, refusing to reap on age alone."
. "$HERE/fixture-stamp.sh"

DIR="${TMPDIR:-/tmp}"
MIN_AGE_OWNED=600      # 10 min: ownership already proved it is not the live owner; this is a
                        # small buffer against a narrow ps-read race, well under any realistic
                        # suite duration.
MIN_AGE_LEGACY=86400   # 24h: no ownership signal at all, so the floor must clear CLAUDE.md's
                        # documented worst case (5:22-13:12) by a wide margin.
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)                  DIR="${2:-}"; [ -n "$DIR" ] || die "--dir requires a path"; shift 2 ;;
    --min-age-owned-secs)   MIN_AGE_OWNED="${2:-}"; shift 2 ;;
    --min-age-legacy-secs)  MIN_AGE_LEGACY="${2:-}"; shift 2 ;;
    --dry-run)               DRY_RUN=1; shift ;;
    -h|--help)               sed -n '2,55p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$MIN_AGE_OWNED" in ''|*[!0-9]*) die "--min-age-owned-secs must be a whole number, got: $MIN_AGE_OWNED" ;; esac
case "$MIN_AGE_LEGACY" in ''|*[!0-9]*) die "--min-age-legacy-secs must be a whole number, got: $MIN_AGE_LEGACY" ;; esac
[ -d "$DIR" ] || die "--dir is not a directory: $DIR"

# ---- portable mtime — lifted verbatim from pipeline-cost-block.sh's file_mtime -------------
# BSD `stat -f %m` and GNU `stat -c %Y`, and neither fails cleanly under the other (on GNU, `-f`
# is --file-system and reads %m as another operand rather than erroring). Validating the digits,
# not the exit status, is what makes the pair portable.
file_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) m=$(stat -f %m "$1" 2>/dev/null) ;; esac
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$m"
}

# ---- ownership ---------------------------------------------------------------------------
# Seam for the selftest: REAP_LEAN_PS_STUB, a directory of "<pid>.lstart" files. When set,
# liveness and the start-time readback come from staged files instead of the real process
# table, so every case is deterministic — no real pid needs to be alive or dead on the machine
# running the suite. An ABSENT stub file models a gone pid; a PRESENT but empty one models the
# third answer — a process that is alive while its start time cannot be read.
#
# THREE ANSWERS, not two. `not-owned` is a positive finding (the pid is gone, or a recycled pid
# now belongs to a different process); `unknown` is the absence of a finding, and it keeps.
_own_state() { # _own_state <pid> <embedded stamp> -> prints owned | not-owned | unknown
  local pid="$1" want="$2" raw current
  if [ -n "${REAP_LEAN_PS_STUB:-}" ]; then
    [ -f "$REAP_LEAN_PS_STUB/$pid.lstart" ] || { printf 'not-owned'; return 0; }
    raw="$(cat "$REAP_LEAN_PS_STUB/$pid.lstart" 2>/dev/null)"
    [ -n "$raw" ] || { printf 'unknown'; return 0; }
    current="$(fixture_stamp_sanitize "$raw")"
  else
    kill -0 "$pid" 2>/dev/null || { printf 'not-owned'; return 0; }
    # Alive, but `ps` said nothing usable. Not a finding — see the header.
    current="$(fixture_stamp_for_pid "$pid")" || { printf 'unknown'; return 0; }
  fi
  if [ "$current" = "$want" ]; then printf 'owned'; else printf 'not-owned'; fi
}

REMOVED=0
KEPT=0
SKIPPED=0
now="$(date -u +%s)"

for pattern in 'leangate.*' 'orchestrate-lean-selftest.*'; do
  for cand in "$DIR"/$pattern; do
    [ -d "$cand" ] || continue
    name="$(basename "$cand")"

    mtime="$(file_mtime "$cand")" || {
      echo "[reap-lean-fixtures] skip (unreadable mtime): $name"
      SKIPPED=$((SKIPPED + 1))
      continue
    }
    age=$((now - mtime))
    [ "$age" -ge 0 ] || age=0   # clock-skew guard — never treat a future mtime as ancient

    # <prefix>.<pid>.<stamp>.<random> — AT LEAST 4 dot-fields. BSD `mktemp -d -t` treats the
    # whole argument as a prefix and appends its own suffix, so a real stamped name has 5;
    # only fields 2 and 3 are read, so both shapes parse identically. Anything shorter (legacy
    # pre-stamp names, or content this script does not recognize) is NEVER treated as owned;
    # it falls to the long age-only floor below instead.
    field_count="$(printf '%s' "$name" | awk -F. '{print NF}')"
    pid=""
    stamp=""
    if [ "$field_count" -ge 4 ]; then
      pid="$(printf '%s' "$name" | cut -d. -f2)"
      stamp="$(printf '%s' "$name" | cut -d. -f3)"
      case "$pid" in ''|*[!0-9]*) pid="" ;; esac
    fi

    if [ -n "$pid" ]; then
      state="$(_own_state "$pid" "$stamp")"
      if [ "$state" = "owned" ]; then
        echo "[reap-lean-fixtures] keep (live owner pid $pid): $name"
        KEPT=$((KEPT + 1))
        continue
      fi
      if [ "$state" = "unknown" ]; then
        echo "[reap-lean-fixtures] keep (ownership unknown for live pid $pid): $name"
        KEPT=$((KEPT + 1))
        continue
      fi
      if [ "$age" -lt "$MIN_AGE_OWNED" ]; then
        echo "[reap-lean-fixtures] keep (not past the ${MIN_AGE_OWNED}s owned floor, age=${age}s): $name"
        KEPT=$((KEPT + 1))
        continue
      fi
    else
      if [ "$age" -lt "$MIN_AGE_LEGACY" ]; then
        echo "[reap-lean-fixtures] keep (unstamped name, not past the ${MIN_AGE_LEGACY}s legacy floor, age=${age}s): $name"
        KEPT=$((KEPT + 1))
        continue
      fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[reap-lean-fixtures] would remove: $name (age=${age}s)"
      REMOVED=$((REMOVED + 1))
      continue
    fi
    if rm -rf -- "$cand" 2>/dev/null; then
      echo "[reap-lean-fixtures] removed: $name (age=${age}s)"
      REMOVED=$((REMOVED + 1))
    else
      echo "[reap-lean-fixtures] skip (rm failed — likely removed by a concurrent reaper): $name"
      SKIPPED=$((SKIPPED + 1))
    fi
  done
done

echo "[reap-lean-fixtures] $REMOVED removed, $KEPT kept, $SKIPPED skipped, under $DIR"
exit 0
