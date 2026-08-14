#!/usr/bin/env bash
# reap-lean-fixtures.sh — removes leangate.*/orchestrate-lean-selftest.* fixture directories a
# signal-killed suite left behind (#528).
#
# WHY THIS EXISTS. lean-gate-selftest.sh and orchestrate-lean-selftest.sh each allocate a
# templated `mktemp -d -t <name>.XXXXXX` work dir under TMPDIR (or /tmp) and clean it up with a
# `trap ... EXIT`. BSD `mktemp -t` DOES honor TMPDIR (unlike its no-template form — see
# CLAUDE.md's killed-sweep note), so the template is not the problem. A trap is: a suite killed
# by a SIGNAL (a `timeout`, a reaped background job, several concurrent sweeps starving each
# other) never reaches it, and the directory survives. Measured live: 107 `leangate.*` and 73
# `orchestrate-lean-selftest.*` orphans on one machine.
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
# A directory is reap-eligible only when BOTH hold:
#   1. OWNERSHIP says it is not live: the pid is gone, or a DIFFERENT process now holds a
#      recycled pid (its current `lstart` no longer matches the embedded stamp).
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
    -h|--help)               sed -n '2,45p' "$0"; exit 0 ;;
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
# running the suite. Absent (the real-run path), a dead or unreadable pid is simply "not owned".
_pid_lstart() { # $1 pid -> prints the sanitized stamp, or fails if dead/unreadable
  local pid="$1" raw
  if [ -n "${REAP_LEAN_PS_STUB:-}" ]; then
    [ -f "$REAP_LEAN_PS_STUB/$pid.lstart" ] || return 1
    raw="$(cat "$REAP_LEAN_PS_STUB/$pid.lstart" 2>/dev/null)"
  else
    kill -0 "$pid" 2>/dev/null || return 1
    raw="$(ps -o lstart= -p "$pid" 2>/dev/null)"
  fi
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | tr -cs 'A-Za-z0-9' '_'
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

    # <prefix>.<pid>.<stamp>.<random> — 4 dot-fields. Anything else (legacy pre-stamp names,
    # or content this script does not recognize) is NEVER treated as owned; it falls to the
    # long age-only floor below instead.
    field_count="$(printf '%s' "$name" | awk -F. '{print NF}')"
    pid=""
    stamp=""
    if [ "$field_count" -ge 4 ]; then
      pid="$(printf '%s' "$name" | cut -d. -f2)"
      stamp="$(printf '%s' "$name" | cut -d. -f3)"
      case "$pid" in ''|*[!0-9]*) pid="" ;; esac
    fi

    if [ -n "$pid" ]; then
      owned=0
      current="$(_pid_lstart "$pid")" && [ "$current" = "$stamp" ] && owned=1
      if [ "$owned" -eq 1 ]; then
        echo "[reap-lean-fixtures] keep (live owner pid $pid): $name"
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
