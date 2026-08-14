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

# Case 3b: name-unrelated be/fe sibling pair (#107) — the same-base-name loop above
# cannot find this (fastapi-be shares no base name with vue-fe), so this proves the
# broadened suffix-counterpart scan independently. Nested under its own PAIR107 dir so its
# adjacency scan doesn't pick up the OTHER cases' fixtures sharing $TMP (e.g. Case 3's
# shop-ui, which also carries an FE suffix). Case 3's convention match is left untouched
# above to prove the addition doesn't regress it.
PAIR107="$TMP/pair107"; mkdir -p "$PAIR107"
R3B="$PAIR107/fastapi-be"; mkdir -p "$R3B"; mkrepo "$R3B" "git@github.com:acme/fastapi-be.git" main
mkdir -p "$PAIR107/vue-fe/.git"
OUT3B="$("$DETECT" "$R3B")"
expect "name-unrelated sibling candidate" "$OUT3B" '.topology.siblingCandidates[0]' "../vue-fe"
expect "name-unrelated topology candidate" "$OUT3B" '.topology.value' "be-fe-pair-candidate"

# Case 3c: repo basename carries no recognized BE/FE suffix ⇒ the broadened scan never
# runs, even with a suffix-shaped sibling next door (isolated for the same reason as 3b).
PLAIN="$TMP/plain107"; mkdir -p "$PLAIN"
R3C="$PLAIN/plainrepo"; mkdir -p "$R3C"; mkrepo "$R3C" "git@github.com:acme/plainrepo.git" main
mkdir -p "$PLAIN/vue-fe/.git"
OUT3C="$("$DETECT" "$R3C")"
expect "no suffix ⇒ no sibling candidates" "$OUT3C" '.topology.siblingCandidates | length' "0"

# Case 3d (upstream fix, defect 1): a workspaces array whose only entry is test-scoped
# (an e2e harness, not app code) must NOT classify the repo as monorepo — but the raw
# array is still reported (provenance-first: evidence isn't hidden, just not decisive).
R3D="$TMP/storefront"; mkdir -p "$R3D"; mkrepo "$R3D" "git@github.com:acme/storefront.git" main
cp "$FIX/package-workspaces-testonly.json" "$R3D/package.json"
OUT3D="$("$DETECT" "$R3D")"
expect "test-only workspaces ⇒ not monorepo" "$OUT3D" '.topology.value' standalone
expect "test-only workspaces still reported"  "$OUT3D" '.topology.workspaces[0]' e2e

# Case 3e (upstream fix, defect 3): the FE side carries a recognized suffix
# (storefront-ui) and its BE counterpart is a BARE base name (storefront, no suffix at
# all) — the common "bare backend, suffixed frontend" convention. The same-base-name
# loop used to only ever construct FE-suffixed candidates, so this direction (BE
# sibling reachable FROM the FE repo) was unreachable regardless of which repo
# detect.sh ran from. Isolated in its own dir for the same adjacency reason as 3b/3c.
BAREBE="$TMP/barebe"; mkdir -p "$BAREBE"
R3E="$BAREBE/storefront-ui"; mkdir -p "$R3E"; mkrepo "$R3E" "git@github.com:acme/storefront-ui.git" main
mkdir -p "$BAREBE/storefront/.git"
OUT3E="$("$DETECT" "$R3E")"
expect "bare-base-name BE sibling found" "$OUT3E" '.topology.siblingCandidates[0]' "../storefront"
expect "bare-base-name BE topology candidate" "$OUT3E" '.topology.value' "be-fe-pair-candidate"

# Case 3f (upstream fix, defect 2): a repo with a REAL (non-test-only) workspaces
# manifest that ALSO has a genuine sibling checkout next door must still surface the
# pair candidate — an `elif` used to let the workspaces-driven monorepo branch swallow
# the sibling signal entirely, even though `siblingCandidates` was already computed.
MONOPAIR="$TMP/monopair"; mkdir -p "$MONOPAIR"
R3F="$MONOPAIR/platform-ui"; mkdir -p "$R3F"; mkrepo "$R3F" "git@github.com:acme/platform-ui.git" main
cp "$FIX/package-monorepo.json" "$R3F/package.json"
mkdir -p "$MONOPAIR/platform/.git"
OUT3F="$("$DETECT" "$R3F")"
expect "sibling not swallowed by a real monorepo branch" "$OUT3F" '.topology.value' "be-fe-pair-candidate"
expect "sibling candidate present alongside real workspaces" "$OUT3F" '.topology.siblingCandidates[0]' "../platform"
expect "workspaces evidence still reported despite pair candidate" "$OUT3F" '.topology.workspaces | length' 2

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

# Case 6 (#532): `claude mcp list` FAILING is not evidence of "no Atlassian MCP". A github
# origin plus an empty evidence array elects `github`, so a blip in a non-interactive shell
# used to MISDETECT the tracker and there was no third answer to give. Both directions matter,
# hence two sub-cases over the SAME repo — only the stub's exit status differs.
R6="$TMP/mcpblip"; mkdir -p "$R6"; mkrepo "$R6" "git@github.com:acme/mcpblip.git" main
STUBS="$TMP/stubs"; mkdir -p "$STUBS"

printf '#!/bin/sh\necho "error: could not connect" >&2\nexit 9\n' > "$STUBS/claude"
chmod +x "$STUBS/claude"
OUT6="$(PATH="$STUBS:$PATH" DETECT_SKIP_MCP='' "$DETECT" "$R6")"
expect "unreadable MCP does not elect github"   "$OUT6" '.tracker.value' ambiguous
expect "unreadable MCP claims no jira evidence" "$OUT6" '.tracker.jiraEvidence | length' 0
SRC6="$(jq -r '.tracker.source' <<< "$OUT6")"
if grep -q 'exited 9' <<< "$SRC6"; then
  check "unreadable MCP puts the producer's exit status in the provenance" 0
else
  check "unreadable MCP provenance (want 'exited 9', got '$SRC6')" 1
fi

# The negative half: a stub that SUCCEEDS with no Atlassian server is a genuine negative and
# must still elect github. Without it the case above would also pass on a detect.sh that had
# simply stopped classifying anything.
printf '#!/bin/sh\necho "server: filesystem (connected)"\n' > "$STUBS/claude"
chmod +x "$STUBS/claude"
OUT6B="$(PATH="$STUBS:$PATH" DETECT_SKIP_MCP='' "$DETECT" "$R6")"
expect "a readable MCP list with no jira still elects github" "$OUT6B" '.tracker.value' github

# The POSITIVE arm, and the reason it is not optional: rc 0 and rc 1 are the only outcomes the
# two sub-cases above tell apart, and BOTH of them leave the evidence array empty. A
# checked_match whose matcher never matched would satisfy them exactly as written — so without
# this case the suite cannot see that mutant. Only a list that DOES carry Atlassian turns the
# probe into evidence.
printf '#!/bin/sh\necho "server: atlassian (connected)"\n' > "$STUBS/claude"
chmod +x "$STUBS/claude"
OUT6C="$(PATH="$STUBS:$PATH" DETECT_SKIP_MCP='' "$DETECT" "$R6")"
expect "a matching MCP list IS jira evidence" "$OUT6C" '.tracker.jiraEvidence | length' 1

# And on a non-github origin that same evidence is what elects jira — the match reaching a
# terminal answer, not merely a populated array.
R6D="$TMP/mcpjira"; mkdir -p "$R6D"; mkrepo "$R6D" "git@git.acme-corp.example:acme/mcpjira.git" main
OUT6D="$(PATH="$STUBS:$PATH" DETECT_SKIP_MCP='' "$DETECT" "$R6D")"
expect "non-github origin + Atlassian MCP elects jira" "$OUT6D" '.tracker.value' jira

if [[ "$FAILS" -gt 0 ]]; then echo "detect selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "detect selftest: all green"
