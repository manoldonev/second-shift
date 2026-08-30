#!/usr/bin/env bash
# install-topology-selftest.sh — the class guard for #419.
#
# WHAT CLASS. A shipped suite can pass in this checkout and fail everywhere it is actually
# installed, because it silently borrows something from the tree it was authored in. Nothing
# else in CI runs a shipped suite from the shape a consumer installs, so the whole class was
# invisible: one suite borrowed the repo's git toplevel for its fixtures (its 5a
# assertions were skipped wholesale from the cache, one failing and two passing vacuously) and
# design-sync-selftest.mjs assumed sibling plugins stay adjacent under `plugins/`. Both were
# green here the entire time.
#
# THE TOPOLOGY REPRODUCED. A version-keyed install cache:
#   <root>/<plugin>/<version>/...        each plugin at its OWN declared version
# outside any git repository, with cwd set to a separate `git init`'d consumer directory that
# holds none of this repo's tree. That is a strict superset of the two known defects: the
# absent git repo above the harness, AND siblings separated by a version segment. A detached
# copy of `plugins/` keeps siblings adjacent and structurally cannot catch the second.
# Plugins really are versioned independently (dev-pipeline 4.0.0 beside design-toolkit 2.2.1),
# so staging each at its own manifest version is what exercises a sibling ladder's last rung
# instead of assuming it.
#
# WIRING. A plain `*-selftest.sh`; CI's existing `find . -name '*-selftest.sh'` discovers it,
# so there is no job to add and nothing to register. It stages `plugins/` only and lives under
# `tools/`, which is not inside `plugins/` — it cannot stage itself, so no recursion guard is
# needed.
#
# VERDICT. A staged suite that fails REDS, full stop (#641: the known-red allowlist that used to
# carve out an exception here emptied to 0 rows and outlived its purpose — deleted, along with
# this read path. A suite listed nowhere is already the "everything must pass" posture once the
# allowlist plumbing is gone).
#
# SUITE-DECLARED SKIPS. A suite may exit 77 to say "I need something that ships inside no
# plugin, so from here its absence measures nothing" — scored as a named, counted SKIP rather
# than a pass or a red, on the suite's OWN reason hoisted from its log. It must earn it: the
# skip is decided suite-side by an intrinsic probe (never a variable this guard exports, which
# would leave the defect alive for a consumer running the suite directly), it comes after every
# assertion the absent artifact does not touch, and an rc 77 with no `SKIP: ` line is a red.
#
# NOT `set -e`: this harness runs other people's suites and SCORES their exit codes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# Per-suite wall-clock bound. This guard runs a SECOND copy of every shipped suite, often
# while the outer sweep is running the first, so cross-copy contention is structural rather
# than incidental: the slowest suite was measured at 244s against a ~94s uncontended norm
# that way. Unbounded, a suite that hangs takes the CI job's timeout with it — a red build
# with no attributable cause — instead of one named timeout line. The default is ~2x the
# worst contended run measured, so contention slows the guard rather than failing it.
#
# That default was 600s and is now 1200s, because "the worst contended run measured" moved.
# Under a stress-inclusive outer sweep at -P 4 the contending load is the whole sweep, not one
# second copy, and that suite crossed 600s in there — reported, correctly, as a
# named timeout, on a tree with nothing wrong with it. A bound that ambient machine load can
# cross stops being a hang detector and becomes a flaky test: every crossing gets
# re-litigated by hand, which is the exact cost the named-timeout line exists to remove.
# The rule is unchanged; only the observation it is applied to is.
#
# (An earlier reading of this had the bound guarding a specific `until ! pgrep -f` waiter in
# that suite. No such waiter exists in this tree — `grep -rn pgrep` finds only
# mutation-sweep-selftest.sh's orphan COUNT. The bound stands on the contention measurement
# above; it is not defending against that mechanism.)
#
# `timeout(1)` is deliberately not used: it is absent from stock macOS, one of this repo's
# two CI lanes. The `set -m` + reap-the-process-group idiom below is lifted from
# tools/mutation-sweep.sh's bounded killer, which documents why killing the pid alone is not
# enough (a spinning grandchild survives it).
SUITE_TIMEOUT="${INSTALL_TOPOLOGY_TIMEOUT:-1200}"
set -m

# ---- bounded runner -----------------------------------------------------------------
# `set -m` above put this shell's background jobs in their own process groups, so the whole
# tree is reapable — SIGSTOP first, because a single SIGKILL races anything still forking.
reap_group() {
  local pgid="$1" i=0 n
  while [[ $i -lt 50 ]]; do
    kill -STOP -"$pgid" 2>/dev/null
    kill -9 -"$pgid" 2>/dev/null || kill -9 "$pgid" 2>/dev/null
    wait "$pgid" 2>/dev/null
    n="$(ps -A -o pgid= 2>/dev/null | tr -d ' ' | grep -c "^$pgid\$")"
    [[ "${n:-0}" -eq 0 ]] && return 0
    i=$((i + 1))
    sleep 0.1
  done
  return 1
}

# A one-shot watchdog job plus a BLOCKING `wait`, rather than a `kill -0` poll loop: a
# finished-but-unreaped child is a zombie, and `kill -0` succeeds on a zombie, so a poll loop
# can only exit once bash happens to reap — which is the very thing `wait` is for. Polling
# would turn that timing into a spurious timeout on a suite that had already passed.
run_bounded() { # $1 = cwd, $2 = logfile, $3 = expiry marker; rest = command → rc, or 124
  local cwd="$1" log="$2" expired="$3"; shift 3
  local pid killer rc
  rm -f "$expired"
  ( cd "$cwd" && SKIP_STRESS=1 "$@" ) > "$log" 2>&1 &
  pid=$!
  ( sleep "$SUITE_TIMEOUT"
    kill -0 "$pid" 2>/dev/null && { : > "$expired"; reap_group "$pid"; }
  ) >/dev/null 2>&1 &
  killer=$!
  wait "$pid"; rc=$?
  # The killer must be reaped as a GROUP, not as a pid: `kill "$killer"` ends the
  # subshell and leaves its `sleep "$SUITE_TIMEOUT"` running to full term, one per
  # suite. That is not theoretical — GitHub's runner printed exactly one
  # "Terminate orphan process: pid (…) (sleep)" line per staged suite at job end.
  reap_group "$killer" >/dev/null 2>&1
  [[ -f "$expired" ]] && return 124
  return "$rc"
}

# ---- worker mode --------------------------------------------------------------------
# One suite, one fresh invocation — which is exactly what gives each concurrent watchdog its
# own job-control shell. Writes <idx>.rc and <idx>.log; the parent scores from those, so a
# worker that dies without writing an .rc is visible as infra rather than as a green suite.
if [[ "${1:-}" == "--run-one" ]]; then
  W_IDX="$2"; W_LIST="$3"; W_CWD="$4"; W_OUT="$5"
  W_STAGED="$(awk -F'\t' -v i="$W_IDX" '$1 == i { print $2 }' "$W_LIST")"
  [[ -z "$W_STAGED" ]] && exit 0
  if [[ "$W_STAGED" == *.mjs ]]; then
    run_bounded "$W_CWD" "$W_OUT/$W_IDX.log" "$W_OUT/$W_IDX.expired" node "$W_STAGED"
  else
    run_bounded "$W_CWD" "$W_OUT/$W_IDX.log" "$W_OUT/$W_IDX.expired" bash "$W_STAGED"
  fi
  echo "$?" > "$W_OUT/$W_IDX.rc"
  exit 0
fi

RAN=0; PASSED=0; SKIPPED=0; RED=0
red()   { echo "  RED:   $1"; RED=$((RED + 1)); }
ok()    { echo "  pass:  $1"; PASSED=$((PASSED + 1)); }
skip()  { echo "  SKIP:  $1"; SKIPPED=$((SKIPPED + 1)); }

# ---- stage the install cache --------------------------------------------------------
BASE="$(mktemp -d -t install-topology.XXXXXX)"
trap 'rm -rf "$BASE"' EXIT
CACHE="$BASE/cache"
CONSUMER="$BASE/consumer"
mkdir -p "$CACHE" "$CONSUMER"

# The consumer's cwd. A real git repo (that is what a consumer checkout is) holding none of
# this repo's tree — the second half of the reproduction, and where the symptom #419 was
# filed against actually appears.
git init -q "$CONSUMER"
git -C "$CONSUMER" config user.email selftest@example.invalid
git -C "$CONSUMER" config user.name selftest
printf 'consumer fixture\n' > "$CONSUMER/README.md"

if CACHE_TOP="$(git -C "$CACHE" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "[install-topology] FATAL: the staged cache resolves a git toplevel ($CACHE_TOP)." >&2
  echo "                   TMPDIR sits inside a repository, so the absent-git-repo half of" >&2
  echo "                   the topology cannot be reproduced and every result would lie." >&2
  exit 1
fi

for plugin_dir in "$REPO"/plugins/*/; do
  name="$(basename "$plugin_dir")"
  manifest="$plugin_dir.claude-plugin/plugin.json"
  version="$(jq -r '.version // empty' "$manifest" 2>/dev/null)"
  if [[ -z "$version" ]]; then
    echo "[install-topology] FATAL: no version in $manifest — cannot stage $name." >&2
    exit 1
  fi
  mkdir -p "$CACHE/$name/$version"
  cp -R "$plugin_dir." "$CACHE/$name/$version/"
done

echo "[install-topology] staged $(find "$CACHE" -maxdepth 2 -mindepth 2 -type d | grep -c '') plugin(s) at $CACHE (no git repo above it), cwd = a git-init'd consumer dir"

# ---- run every staged suite ----------------------------------------------------------
# SKIP_STRESS=1 (set in run_bounded): the class under test is path resolution, not stress
# behavior, and the in-repo ubuntu lane is the one that exercises the stress legs — so paying
# for them a second time here buys nothing. `.mjs` suites need node, which is not a hard
# prerequisite of this repo the way bash and jq are — an absent node is a NAMED, COUNTED skip,
# never silent green.
HAVE_NODE=0
command -v node >/dev/null 2>&1 && HAVE_NODE=1

# Suites run CONCURRENTLY, for the same reason CLAUDE.md's documented sweep does: they are
# independent (each allocates its own mktemp state dir), and re-running the whole shipped set
# serially costs ~9 minutes — which this guard would then add to every local sweep and both CI
# lanes, becoming their long pole. Each worker is a fresh `--run-one` invocation of this file
# so it gets its OWN job-control shell, which is what makes the per-suite bound able to reap a
# whole process group; sharing one shell across concurrent watchdogs could not.
JOBS="${INSTALL_TOPOLOGY_JOBS:-4}"
RESULTS="$BASE/results"
mkdir -p "$RESULTS"

n=0
while IFS= read -r staged; do
  n=$((n + 1))
  printf '%s\t%s\n' "$(printf '%04d' "$n")" "$staged"
done < <(find "$CACHE" \( -name '*-selftest.sh' -o -name '*-selftest.mjs' \) -type f | sort) > "$BASE/worklist"

if [[ "$HAVE_NODE" -eq 0 ]]; then
  grep -v '\.mjs$' "$BASE/worklist" > "$BASE/worklist.run" || true
else
  cp "$BASE/worklist" "$BASE/worklist.run"
fi

# shellcheck disable=SC2016  # the placeholders are for the inner sh -c, deliberately unexpanded
cut -f1 "$BASE/worklist.run" | xargs -P "$JOBS" -n1 -I{} \
  sh -c 'bash "$0" --run-one "$1" "$2" "$3" "$4"' \
  "$SELF" "{}" "$BASE/worklist.run" "$CONSUMER" "$RESULTS" >/dev/null 2>&1

while IFS= read -r line; do
  idx="${line%%	*}"; staged="${line#*	}"
  rel="${staged#"$CACHE"/}"                       # <plugin>/<version>/<path-under-plugin>
  plugin="${rel%%/*}"; rest="${rel#*/}"; rest="${rest#*/}"
  repo_rel="plugins/$plugin/$rest"                # stable across releases

  if [[ "$staged" == *.mjs && "$HAVE_NODE" -eq 0 ]]; then
    skip "$repo_rel — node not on PATH, cannot run a .mjs suite"
    continue
  fi

  if [[ -f "$RESULTS/$idx.rc" ]]; then
    rc="$(cat "$RESULTS/$idx.rc")"
  else
    # A worker that produced no verdict is infra, not a suite result. Never silently green.
    rc=125
  fi

  # A SUITE-DECLARED skip: rc 77 means the suite reached something structurally absent from an
  # install (a repo-only artifact that ships inside no plugin) and stood its other assertions
  # down for it — never a suite that merely failed. The reason is the suite's own, hoisted out
  # of the captured log HERE because that log is deleted with $BASE on exit; a SKIP line that
  # does not carry the reason loses it entirely. An rc of 77 whose log carries no `SKIP: ` line
  # falls through and is scored as a failure below: a skip that discloses nothing is exactly the
  # silent green this whole list exists to prevent.
  if [[ "$rc" -eq 77 ]]; then
    reason="$(grep -m1 '^[[:space:]]*SKIP: ' "$RESULTS/$idx.log" 2>/dev/null | sed -e 's/^[[:space:]]*SKIP:[[:space:]]*//')"
    if [[ -n "$reason" ]]; then
      skip "$repo_rel — $reason"
      continue
    fi
  fi

  RAN=$((RAN + 1))

  if [[ "$rc" -eq 0 ]]; then
    ok "$repo_rel"
    continue
  fi

  if [[ "$rc" -eq 124 ]]; then
    detail="timed out after ${SUITE_TIMEOUT}s (bound, not a hang)"
  elif [[ "$rc" -eq 125 ]]; then
    detail="no verdict written — the worker died before scoring this suite (infra, not a result)"
  else
    # A suite's OWN failure line first, and only then the loose substring sweep (#664).
    # The loose sweep alone picked the first line merely CONTAINING "fail" anywhere, which
    # for pipeline-doctor-selftest.sh is a PASSING line — `ok: (d3) completed + failed at
    # 24h` — 37 lines above the real `FAIL:` one. Seven nightly reds named a green case,
    # and every reader who trusted the summary went to the wrong assertion. A marker at
    # the START of the line is the suites' own convention (`FAIL:`, `FATAL:`, `RED:`), so
    # it cannot collide with case prose the way a bare substring does. The loose sweep is
    # kept as the fallback: a suite that dies on `No such file` prints no marker at all,
    # and a red with a vague detail still beats a red with none.
    #
    # Sentinel-delimited because this path is DEAD on every green run — it executes only
    # once a staged suite has already failed, which is why a broken detail line survived
    # seven nightly reds. install-topology-detail-selftest.sh lifts these lines and runs
    # them against fixture logs so the path is exercised on a green tree too.
    # >>> red-detail
    detail="$(grep -m1 -E '^[[:space:]]*(FAIL|FATAL|RED|ERROR)[:[:space:]]' "$RESULTS/$idx.log" 2>/dev/null | sed 's/^[[:space:]]*//')"
    [[ -n "$detail" ]] || detail="$(grep -m1 -iE 'FAIL|error|No such|not found' "$RESULTS/$idx.log" 2>/dev/null | sed 's/^[[:space:]]*//')"
    detail="rc=$rc — $detail"
    # <<< red-detail
  fi

  red "$repo_rel — $detail"
done < "$BASE/worklist"

echo "[install-topology] summary: $RAN ran, $PASSED passed, $SKIPPED skipped, $RED red"
exit "$RED"
