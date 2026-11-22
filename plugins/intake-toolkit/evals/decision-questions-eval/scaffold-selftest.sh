#!/usr/bin/env bash
# Selftest for scaffold.sh. It builds its own git repo, because a shipped suite also runs from an
# install cache with no git repository above it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/scaffold.sh"
FIXTURE="$HERE/fixture/TICKET.md"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/.claude" "$REPO/plugins/intake-toolkit/skills" "$REPO/plugins/dev-pipeline/skills/run" \
  "$REPO/plugins/dev-pipeline/.claude"
echo readme > "$REPO/README.md"
echo '{}' > "$REPO/.claude/settings.json"
echo old-rules > "$REPO/plugins/intake-toolkit/skills/SKILL.md"
echo scheduler > "$REPO/plugins/dev-pipeline/skills/run/run.sh"
echo nested > "$REPO/plugins/dev-pipeline/.claude/keep.md"
g() { git -C "$REPO" -c user.email=selftest@local -c user.name=selftest "$@"; }
g init -q
g add -A
g commit -q -m snapshot
REF="$(g rev-parse HEAD)"
echo later > "$REPO/later.txt"
g add -A
g commit -q -m later

# (1) the snapshot of the named commit, beside TICKET.md
WS="$TMP/ws1"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$REPO" SNAPSHOT_REF="$REF" bash "$TOOL") >"$TMP/out1" 2>"$TMP/err1" || RC=$?
[ "$RC" -eq 0 ] && ok "exits 0 on a repo that holds the commit" || bad "exit $RC on a repo that holds the commit: $(cat "$TMP/err1")"
cmp -s "$WS/TICKET.md" "$FIXTURE" && ok "TICKET.md is the fixture ticket" || bad "TICKET.md is missing or differs from the fixture"
[ -f "$WS/README.md" ] && [ -f "$WS/plugins/dev-pipeline/skills/run/run.sh" ] \
  && ok "the commit's tree is in the workspace" || bad "the commit's tree is not in the workspace"
[ ! -e "$WS/later.txt" ] && ok "a file from a later commit is absent" || bad "later.txt is present: the snapshot is not the named commit"
[ ! -e "$WS/.git" ] && ok "the snapshot has no .git" || bad "the snapshot holds .git"
[ ! -e "$WS/.claude" ] && ok "the snapshot has no top-level .claude/" || bad "the snapshot holds .claude/"
[ ! -e "$WS/plugins/intake-toolkit" ] && ok "the snapshot has no plugins/intake-toolkit/" || bad "the snapshot holds plugins/intake-toolkit/"
[ -f "$WS/plugins/dev-pipeline/.claude/keep.md" ] && ok "a nested .claude/ stays" || bad "a nested .claude/ was dropped"

# (2) a repo that does not hold the commit, as in a shallow clone
WS="$TMP/ws2"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$REPO" SNAPSHOT_REF=0123456789abcdef0123456789abcdef01234567 bash "$TOOL") \
  >/dev/null 2>"$TMP/err2" || RC=$?
if [ "$RC" -ne 0 ] && [ "$(grep -c . "$TMP/err2")" -eq 1 ] && [ -z "$(ls -A "$WS")" ]; then
  ok "a missing commit exits non-zero with one stderr line and writes nothing"
else
  bad "a missing commit: exit $RC, stderr '$(cat "$TMP/err2")', workspace '$(ls -A "$WS")'"
fi

# (3) a directory that is not a git repo
mkdir -p "$TMP/plain"
WS="$TMP/ws3"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$TMP/plain" SNAPSHOT_REF="$REF" bash "$TOOL") >/dev/null 2>"$TMP/err3" || RC=$?
if [ "$RC" -ne 0 ] && [ "$(grep -c . "$TMP/err3")" -eq 1 ] && [ -z "$(ls -A "$WS")" ]; then
  ok "a non-repo exits non-zero with one stderr line and writes nothing"
else
  bad "a non-repo: exit $RC, stderr '$(cat "$TMP/err3")', workspace '$(ls -A "$WS")'"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "scaffold-selftest: ALL PASS"; else
  echo "scaffold-selftest: $FAILS FAILURE(S)"; exit 1; fi
