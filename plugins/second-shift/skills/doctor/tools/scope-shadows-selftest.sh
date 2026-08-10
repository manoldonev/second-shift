#!/usr/bin/env bash
# scope-shadows-selftest.sh — hermetic selftest for scope-shadows.sh (no claude binary, no
# network). Every plugin list is written inline under mktemp and injected through the same
# DOCTOR_PLUGIN_LIST_FILE override doctor uses.
#
# Two things are asserted on every case, not one: the ROWS and the EXIT STATUS. The status is
# the whole reason this helper exists as a separate tool — local-dev-refresh Step 4 reads it as
# its precondition and never parses a row — so a case that checked only the text would pass just
# as happily on a helper that always exited 0 and left Step 4 declining on everything.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SS="$HERE/scope-shadows.sh"; FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"; OTHER="$TMP/other"

# run <list-file> <expected-rc> <expected-rows-or-empty> <label> [extra args...]
run() {
  local list="$1" want_rc="$2" want_rows="$3" label="$4"; shift 4
  local out rc=0
  out="$(DOCTOR_PLUGIN_LIST_FILE="$list" bash "$SS" --root "$ROOT" "$@" 2>/dev/null)" || rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == "$want_rows" ]]; then check "$label" 0
  else check "$label (rc=$rc want $want_rc)" 1; printf '      got: %q\n      want:%q\n' "$out" "$want_rows"; fi
}

cat > "$TMP/shadowed.json" <<EOF
[
  { "id": "dev-pipeline@second-shift", "version": "2.0.1", "scope": "project", "projectPath": "$ROOT", "lastUpdated": "2020-01-01" },
  { "id": "dev-pipeline@second-shift", "version": "2.1.0", "scope": "user",    "lastUpdated": "2026-01-01" }
]
EOF
cat > "$TMP/user-only.json" <<EOF
[ { "id": "dev-pipeline@second-shift", "version": "2.1.0", "scope": "user" } ]
EOF
cat > "$TMP/project-only.json" <<EOF
[ { "id": "dev-pipeline@second-shift", "version": "2.0.1", "scope": "project", "projectPath": "$ROOT" } ]
EOF
cat > "$TMP/local-project.json" <<EOF
[
  { "id": "dev-pipeline@second-shift", "version": "2.0.1", "scope": "project", "projectPath": "$ROOT" },
  { "id": "dev-pipeline@second-shift", "version": "2.1.0", "scope": "local",   "projectPath": "$ROOT" }
]
EOF
cat > "$TMP/local-user.json" <<EOF
[
  { "id": "dev-pipeline@second-shift", "version": "2.1.0", "scope": "user" },
  { "id": "dev-pipeline@second-shift", "version": "9.9.9", "scope": "local", "projectPath": "$ROOT" }
]
EOF
cat > "$TMP/other-root.json" <<EOF
[
  { "id": "dev-pipeline@second-shift", "version": "2.0.1", "scope": "project", "projectPath": "$OTHER" },
  { "id": "dev-pipeline@second-shift", "version": "2.1.0", "scope": "user" }
]
EOF
cat > "$TMP/many.json" <<EOF
[
  { "id": "review-toolkit@second-shift", "version": "2.0.2", "scope": "user" },
  { "id": "dev-pipeline@second-shift",   "version": "2.0.1", "scope": "project", "projectPath": "$ROOT" },
  { "id": "dev-pipeline@second-shift",   "version": "2.1.0", "scope": "user" },
  { "id": "audit-toolkit@othermarket",   "version": "9.0.0", "scope": "user" }
]
EOF
printf '[]\n'      > "$TMP/empty.json"
printf 'not json\n' > "$TMP/garbage.json"

echo "scope-shadows selftest:"

# The core split. A project record is redundant only when a USER record already serves the
# plugin; with no user record it IS the thing serving it, and the ticket's Out of scope keeps
# that install correct.
run "$TMP/shadowed.json"     0 "$(printf 'shadowed\tdev-pipeline\t2.0.1\t2.1.0')"     "user+project -> shadowed row, rc=0"
run "$TMP/user-only.json"    1 "$(printf 'user-served\tdev-pipeline\t-\t2.1.0')"      "user only -> user-served row, rc=1"
run "$TMP/project-only.json" 1 ""                                                     "project only -> no row, rc=1"

# A `local`-scope record is the sanctioned per-developer override lever (docs/team-rollout.md),
# so it is never redundancy: it neither shadows a project record nor stands in for a user one.
# doctor.sh's own resolver ADMITS local records alongside user ones, which is exactly why this
# needs pinning — the obvious implementation reuses that select and reports local-over-project.
run "$TMP/local-project.json" 1 ""                                               "local does not shadow a project record"
run "$TMP/local-user.json"    1 "$(printf 'user-served\tdev-pipeline\t-\t2.1.0')" "local is not counted as the serving record"

# projectPath scoping: a project record belonging to ANOTHER checkout is not this repo's
# redundancy — nothing here can uninstall it, and local-dev-refresh already refuses to touch it.
run "$TMP/other-root.json" 1 "$(printf 'user-served\tdev-pipeline\t-\t2.1.0')" "project record at another root is not shadowed here"

# Ordering is by plugin id and foreign marketplaces are ignored — callers render these rows in
# sequence and must not have to sort, and this tool is filtered to one marketplace by contract.
run "$TMP/many.json" 0 "$(printf 'shadowed\tdev-pipeline\t2.0.1\t2.1.0\nuser-served\treview-toolkit\t-\t2.0.2')" \
  "multiple plugins -> id-ordered rows, foreign marketplace ignored"

# The positional filter is what makes the per-plugin Step 4 precondition possible: asking about
# one straggler must not return 0 because some OTHER plugin is shadowed.
run "$TMP/many.json" 1 "$(printf 'user-served\treview-toolkit\t-\t2.0.2')" "name filter: unshadowed plugin -> rc=1" review-toolkit
run "$TMP/many.json" 0 "$(printf 'shadowed\tdev-pipeline\t2.0.1\t2.1.0')"  "name filter: shadowed plugin -> rc=0"  dev-pipeline

# Degenerate inputs. Empty is a legitimate answer (nothing installed); unparseable is not, and
# must be rc=2 rather than the rc=1 "nothing shadowed" a caller would act on.
run "$TMP/empty.json"   1 "" "empty plugin list -> no rows, rc=1"
run "$TMP/garbage.json" 2 "" "unparseable plugin list -> rc=2"

# --marketplace retargets the id suffix; nothing else in the classification changes.
run "$TMP/many.json" 1 "$(printf 'user-served\taudit-toolkit\t-\t9.0.0')" "--marketplace retargets the suffix" --marketplace othermarket

# DOCTOR_REPO_ROOT is the no-flag path — the one doctor's children actually take, since doctor
# exports its injections rather than passing flags down.
envout="$(DOCTOR_PLUGIN_LIST_FILE="$TMP/shadowed.json" DOCTOR_REPO_ROOT="$ROOT" bash "$SS" 2>/dev/null)"; envrc=$?
[[ "$envrc" -eq 0 && "$envout" == "$(printf 'shadowed\tdev-pipeline\t2.0.1\t2.1.0')" ]] \
  && check "DOCTOR_REPO_ROOT resolves the root with no --root flag" 0 \
  || { check "DOCTOR_REPO_ROOT resolves the root with no --root flag (rc=$envrc)" 1; printf '      got: %q\n' "$envout"; }
# ...and the same list against a DIFFERENT root must NOT be shadowed, or the case above would
# pass on a helper that ignored the root entirely.
envout2="$(DOCTOR_PLUGIN_LIST_FILE="$TMP/shadowed.json" DOCTOR_REPO_ROOT="$OTHER" bash "$SS" 2>/dev/null)"; envrc2=$?
[[ "$envrc2" -eq 1 && "$envout2" == "$(printf 'user-served\tdev-pipeline\t-\t2.1.0')" ]] \
  && check "DOCTOR_REPO_ROOT is actually read (other root -> not shadowed)" 0 \
  || { check "DOCTOR_REPO_ROOT is actually read (other root -> not shadowed) (rc=$envrc2)" 1; printf '      got: %q\n' "$envout2"; }

# Usage errors are rc=2, distinct from both verdicts. A flag typo that fell through to "nothing
# shadowed" would silently re-enable the Step 4 realignment this helper exists to block.
for bad_args in "--root" "--marketplace" "--nope"; do
  # shellcheck disable=SC2086 # deliberate word-splitting: each entry is one flag
  DOCTOR_PLUGIN_LIST_FILE="$TMP/shadowed.json" bash "$SS" $bad_args >/dev/null 2>&1; brc=$?
  [[ "$brc" -eq 2 ]] && check "usage error '$bad_args' -> rc=2" 0 || check "usage error '$bad_args' -> rc=2 (got $brc)" 1
done

if [[ "$FAILS" -gt 0 ]]; then echo "scope-shadows selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "scope-shadows selftest: all green"
