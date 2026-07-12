#!/usr/bin/env bash
# detect-selftest.sh — hermetic selftest for detect.sh (no network, no gh, no claude).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$HERE/detect.sh"
FIX="$HERE/detect-fixtures"
FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
expect() { # $1 label, $2 json, $3 jq expr, $4 expected
  local got; got="$(jq -r "$3" <<< "$2")"
  if [[ "$got" == "$4" ]]; then check "$1" 0; else check "$1 (want '$4' got '$got')" 1; fi
}
mkrepo() { # $1 dir, $2 origin-url, $3 default-branch
  if ! git -C "$1" init -q -b "$3" 2>/dev/null; then
    git -C "$1" init -q && git -C "$1" checkout -q -b "$3"
  fi
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$1" remote add origin "$2"
  git -C "$1" update-ref "refs/remotes/origin/$3" HEAD
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$3"
}
export DETECT_SKIP_GH=1 DETECT_SKIP_MCP=1 DETECT_SKIP_LSREMOTE=1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "detect selftest:"
# Case 1: yarn standalone, github origin, main
R="$TMP/widget-api"; mkdir -p "$R"; mkrepo "$R" "git@github.com:acme/widget-api.git" main
cp "$FIX/package-yarn.json" "$R/package.json"; touch "$R/yarn.lock"
OUT="$("$DETECT" "$R")"
expect "tracker github"        "$OUT" '.tracker.value' github
expect "baseBranch main"       "$OUT" '.git.baseBranch.value' main
expect "baseBranch provenance" "$OUT" '.git.baseBranch.source' "origin/HEAD symbolic-ref"
expect "pm yarn"               "$OUT" '.packageManager.value' yarn
expect "lint cmd"              "$OUT" '.commands.lint.value' "yarn lint"
expect "typecheck null"        "$OUT" '.commands.typecheck.value' null
expect "lintAutofixes true"    "$OUT" '.commands.lintAutofixes' true
expect "topology standalone"   "$OUT" '.topology.value' standalone

# Case 2: monorepo (workspaces), npm, non-github origin ⇒ ambiguous tracker
R2="$TMP/platform"; mkdir -p "$R2"; mkrepo "$R2" "git@git.acme-corp.example:platform/platform.git" develop
cp "$FIX/package-monorepo.json" "$R2/package.json"; touch "$R2/package-lock.json"
OUT2="$("$DETECT" "$R2")"
expect "topology monorepo"   "$OUT2" '.topology.value' monorepo
expect "workspaces listed"   "$OUT2" '.topology.workspaces | length' 2
expect "tracker ambiguous"   "$OUT2" '.tracker.value' ambiguous
expect "baseBranch develop"  "$OUT2" '.git.baseBranch.value' develop
expect "pm npm"              "$OUT2" '.packageManager.value' npm
expect "npm run prefix"      "$OUT2" '.commands.test.value' "npm run test"

# Case 3: sibling be-fe candidate
R3="$TMP/shop-api"; mkdir -p "$R3" "$TMP/shop-ui/.git"; mkrepo "$R3" "git@github.com:acme/shop-api.git" main
OUT3="$("$DETECT" "$R3")"
expect "sibling candidate" "$OUT3" '.topology.siblingCandidates[0]' "../shop-ui"

# Case 4: not a git repo ⇒ exit 3
if "$DETECT" "$TMP" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "non-repo exits 3" "$([[ "$rc" -eq 3 ]] && echo 0 || echo 1)"

# Case 5: no origin/HEAD and DETECT_SKIP_LSREMOTE ⇒ baseBranch empty + undetected (NOT a guess)
R5="$TMP/headless"; mkdir -p "$R5"
if ! git -C "$R5" init -q -b main 2>/dev/null; then git -C "$R5" init -q && git -C "$R5" checkout -q -b main; fi
git -C "$R5" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$R5" remote add origin "git@github.com:acme/headless.git"
OUT5="$("$DETECT" "$R5")"
expect "undetected baseBranch is empty" "$OUT5" '.git.baseBranch.value' ""
expect "undetected provenance"          "$OUT5" '.git.baseBranch.source' undetected

if [[ "$FAILS" -gt 0 ]]; then echo "detect selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "detect selftest: all green"
