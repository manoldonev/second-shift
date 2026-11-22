#!/usr/bin/env bash
# Selftest for scaffold.sh. It builds its own git repo, because a shipped suite also runs from an
# install cache with no git repository above it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/scaffold.sh"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/.claude" "$REPO/plugins/intake-toolkit/skills" "$REPO/plugins/dev-pipeline/skills/run"
echo '{}' > "$REPO/.claude/settings.json"
echo old-rules > "$REPO/plugins/intake-toolkit/skills/SKILL.md"
echo scheduler > "$REPO/plugins/dev-pipeline/skills/run/run.sh"
g() { git -C "$REPO" -c user.email=selftest@local -c user.name=selftest "$@"; }
g init -q
g add -A
g commit -q -m snapshot
REF="$(g rev-parse HEAD)"

# (1) the shared snapshot and ticket, with the interview record beside them
WS="$TMP/ws1"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$REPO" SNAPSHOT_REF="$REF" bash "$TOOL") >"$TMP/out1" 2>"$TMP/err1" || RC=$?
[ "$RC" -eq 0 ] && ok "exits 0 on a repo that holds the commit" || bad "exit $RC on a repo that holds the commit: $(cat "$TMP/err1")"
cmp -s "$WS/INTERVIEW.md" "$HERE/fixture/INTERVIEW.md" && ok "INTERVIEW.md is the fixture record" || bad "INTERVIEW.md is missing or differs from the fixture"
cmp -s "$WS/TICKET.md" "$HERE/../decision-questions-eval/fixture/TICKET.md" \
  && ok "TICKET.md is the shared fixture ticket" || bad "TICKET.md is missing or differs from the shared fixture"
[ -f "$WS/plugins/dev-pipeline/skills/run/run.sh" ] && ok "the commit's tree is in the workspace" || bad "the commit's tree is not in the workspace"
[ ! -e "$WS/.claude" ] && ok "the workspace has no .claude/" || bad "the workspace holds .claude/"
[ ! -e "$WS/plugins/intake-toolkit" ] && ok "the workspace has no plugins/intake-toolkit/" || bad "the workspace holds plugins/intake-toolkit/"

# (2) a failed snapshot leaves no record behind, so the run fails as a scaffold error
WS="$TMP/ws2"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$REPO" SNAPSHOT_REF=0123456789abcdef0123456789abcdef01234567 bash "$TOOL") \
  >/dev/null 2>"$TMP/err2" || RC=$?
if [ "$RC" -ne 0 ] && [ -z "$(ls -A "$WS")" ]; then
  ok "a missing commit exits non-zero and writes nothing"
else
  bad "a missing commit: exit $RC, workspace '$(ls -A "$WS")'"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "scaffold-selftest: ALL PASS"; else
  echo "scaffold-selftest: $FAILS FAILURE(S)"; exit 1; fi
