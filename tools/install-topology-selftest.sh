#!/usr/bin/env bash
# install-topology-selftest.sh — the class guard for #419.
#
# WHAT CLASS. A shipped suite can pass in this checkout and fail everywhere it is actually
# installed, because it silently borrows something from the tree it was authored in. Nothing
# else in CI runs a shipped suite from the shape a consumer installs, so the whole class was
# invisible: plan-lint-selftest.sh borrowed the repo's git toplevel for its fixtures (its 5a
# assertions were skipped wholesale from the cache, one failing and two passing vacuously) and
# design-sync-selftest.mjs assumed sibling plugins stay adjacent under `plugins/`. Both were
# green here the entire time.
#
# THE TOPOLOGY REPRODUCED (#419 D-3). A version-keyed install cache:
#   <root>/<plugin>/<version>/...        each plugin at its OWN declared version
# outside any git repository, with cwd set to a separate `git init`'d consumer directory that
# holds none of this repo's tree. That is a strict superset of the two known defects: the
# absent git repo above the harness, AND siblings separated by a version segment. A detached
# copy of `plugins/` keeps siblings adjacent and structurally cannot catch the second.
# Plugins really are versioned independently (dev-pipeline 4.0.0 beside design-toolkit 2.2.1),
# so staging each at its own manifest version is what exercises a sibling ladder's last rung
# instead of assuming it.
#
# WIRING (D-5). A plain `*-selftest.sh`; CI's existing `find . -name '*-selftest.sh'` discovers
# it, so there is no job to add and nothing to register. It stages `plugins/` only and lives
# under `tools/`, which is not inside `plugins/` — it cannot stage itself, so no recursion
# guard is needed.
#
# VERDICT (D-6). Reds only on a suite that is NOT listed in install-topology-known-red.tsv.
# A listed suite that passes is a warning, never a red — the "shrink the list" direction,
# the same contract tools/mutation-baseline.tsv carries for survivors.
#
# NOT `set -e`: this harness runs other people's suites and SCORES their exit codes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
KNOWN_RED="$HERE/install-topology-known-red.tsv"
SELF="$HERE/install-topology-selftest.sh"

# Per-suite wall-clock bound (D-8). A hang is a live failure mode here, not a hypothetical:
# statectl-selftest.sh has an `until ! pgrep -f` waiter that deadlocks against a second
# matching copy, and this guard runs a second copy by construction. Unbounded, that hangs CI
# instead of reding it. The default is ~2x the worst contended run measured while building
# this guard (244s against a ~94s uncontended norm), so contention slows the guard rather
# than failing it, while a true deadlock still terminates.
#
# `timeout(1)` is deliberately not used: it is absent from stock macOS, one of this repo's
# two CI lanes. The `set -m` + reap-the-process-group idiom below is lifted from
# tools/mutation-sweep.sh's bounded killer, which documents why killing the pid alone is not
# enough (a spinning grandchild survives it).
SUITE_TIMEOUT="${INSTALL_TOPOLOGY_TIMEOUT:-600}"
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
  kill "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
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

RAN=0; PASSED=0; KNOWN=0; SKIPPED=0; RED=0; STALE=0
red()   { echo "  RED:   $1"; RED=$((RED + 1)); }
ok()    { echo "  pass:  $1"; PASSED=$((PASSED + 1)); }
known() { echo "  known: $1"; KNOWN=$((KNOWN + 1)); }
skip()  { echo "  SKIP:  $1"; SKIPPED=$((SKIPPED + 1)); }
warn()  { echo "  warn:  $1"; }

# ---- known-red list ----------------------------------------------------------------
# Keyed on the REPO-relative path (`plugins/<name>/<rel>`), never the staged one: a staged
# path carries the version segment, so every row would rot at the next release.
KR_PATH=(); KR_CAUSE=(); KR_SEEN=()
if [[ -f "$KNOWN_RED" ]]; then
  while IFS=$'\t' read -r c1 c2 || [[ -n "${c1:-}" ]]; do
    case "${c1:-}" in ''|'#'*) continue ;; esac
    KR_PATH[${#KR_PATH[@]}]="$c1"
    KR_CAUSE[${#KR_CAUSE[@]}]="${c2:-}"
    KR_SEEN[${#KR_SEEN[@]}]=0
  done < "$KNOWN_RED"
else
  echo "[install-topology] FATAL: known-red list not found at $KNOWN_RED" >&2
  exit 1
fi

known_red_index() { # $1 = repo-relative path → echoes index, or empty
  local i=0
  while [[ $i -lt ${#KR_PATH[@]} ]]; do
    [[ "${KR_PATH[$i]}" == "$1" ]] && { echo "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

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
# SKIP_STRESS=1 (set in run_bounded): D-8's mandate is to bound runtime, the class under test
# is path resolution rather than stress behavior, and the in-repo ubuntu lane is where the
# stress legs are exercised. `.mjs` suites need node, which is not a hard prerequisite of this
# repo the way bash and jq are — an absent node is a NAMED, COUNTED skip, never silent green.
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
  repo_rel="plugins/$plugin/$rest"                # stable across releases; the known-red key
  kr="$(known_red_index "$repo_rel" || true)"

  if [[ "$staged" == *.mjs && "$HAVE_NODE" -eq 0 ]]; then
    skip "$repo_rel — node not on PATH, cannot run a .mjs suite"
    continue
  fi

  RAN=$((RAN + 1))
  if [[ -f "$RESULTS/$idx.rc" ]]; then
    rc="$(cat "$RESULTS/$idx.rc")"
  else
    # A worker that produced no verdict is infra, not a suite result. Never silently green.
    rc=125
  fi

  if [[ "$rc" -eq 0 ]]; then
    if [[ -n "$kr" ]]; then
      KR_SEEN[kr]=1
      warn "$repo_rel is listed known-red but PASSED — drop its row (listed: ${KR_CAUSE[$kr]})"
    fi
    ok "$repo_rel"
    continue
  fi

  if [[ "$rc" -eq 124 ]]; then
    detail="timed out after ${SUITE_TIMEOUT}s (bound, not a hang)"
  elif [[ "$rc" -eq 125 ]]; then
    detail="no verdict written — the worker died before scoring this suite (infra, not a result)"
  else
    detail="rc=$rc — $(grep -iE 'FAIL|error|No such|not found' "$RESULTS/$idx.log" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')"
  fi

  if [[ -n "$kr" ]]; then
    KR_SEEN[kr]=1
    known "$repo_rel — $detail (known: ${KR_CAUSE[$kr]})"
  else
    red "$repo_rel — $detail"
  fi
done < "$BASE/worklist"

# A row whose suite never ran is stale, not a failure — same direction as a killed mutant
# still sitting in the mutation baseline: it says "shrink the list", loudly, without reding.
i=0
while [[ $i -lt ${#KR_PATH[@]} ]]; do
  [[ "${KR_SEEN[$i]}" -eq 0 ]] && { warn "known-red row ${KR_PATH[$i]} matched no staged suite — stale row"; STALE=$((STALE + 1)); }
  i=$((i + 1))
done

echo "[install-topology] summary: $RAN ran, $PASSED passed, $KNOWN known-red, $SKIPPED skipped, $STALE stale row(s), $RED red"
exit "$RED"
