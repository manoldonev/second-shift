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
PLUGIN="$REPO/plugins/intake-toolkit"
mkdir -p "$REPO/.claude" "$REPO/docs/plans" "$REPO/docs/guide" \
  "$PLUGIN/agents" "$PLUGIN/evals/some-eval/fixtures" "$PLUGIN/skills/intake" \
  "$PLUGIN/skills/plan-interview/tools" "$REPO/plugins/other/evals"
echo readme > "$REPO/README.md"
echo '{}' > "$REPO/.claude/settings.json"
echo old-record > "$REPO/docs/plans/old-decisions.md"
echo guide > "$REPO/docs/guide/keep.md"
echo probe-rules > "$PLUGIN/agents/implementability-probe.md"
echo other-agent > "$PLUGIN/agents/other.md"
echo answer-key > "$PLUGIN/evals/some-eval/fixtures/planted-defects.md"
echo receipt-rules > "$PLUGIN/skills/intake/receipt.md"
echo lint > "$PLUGIN/skills/plan-interview/tools/ledger-lint.sh"
echo other-eval > "$REPO/plugins/other/evals/keep.md"
g() { git -C "$REPO" -c user.email=selftest@local -c user.name=selftest "$@"; }
g init -q
g add -A
g commit -q -m snapshot
REF="$(g rev-parse HEAD)"
echo later > "$REPO/later.txt"
g add -A
g commit -q -m later

# (1) the snapshot of the named commit, with the three fixture files under docs/plans/
WS="$TMP/ws1"; mkdir -p "$WS"
RC=0; (cd "$WS" && SNAPSHOT_REPO="$REPO" SNAPSHOT_REF="$REF" bash "$TOOL") >"$TMP/out1" 2>"$TMP/err1" || RC=$?
[ "$RC" -eq 0 ] && ok "exits 0 on a repo that holds the commit" || bad "exit $RC on a repo that holds the commit: $(cat "$TMP/err1")"
cmp -s "$WS/docs/plans/ledger-lint-json-ticket.md" "$HERE/fixtures/underspecified-spec.md" \
  && ok "the ticket is the fixture spec" || bad "the ticket is missing or differs from the fixture"
cmp -s "$WS/docs/plans/ledger-lint-json-decisions.md" "$HERE/fixtures/planted-record.md" \
  && ok "the record is the planted record" || bad "the record is missing or differs from the fixture"
cmp -s "$WS/docs/plans/ledger-lint-json-interview-notes.md" "$HERE/fixtures/interview-notes.md" \
  && ok "the interview notes are in the workspace" || bad "the interview notes are missing or differ from the fixture"
[ "$(find "$WS/docs/plans" -type f | wc -l | tr -d ' ')" = "3" ] \
  && ok "docs/plans/ holds the three fixture files only" || bad "docs/plans/ holds: $(ls "$WS/docs/plans")"
[ -z "$(find "$WS" -name 'planted-defects.md' -o -name 'seeded-gaps.md')" ] \
  && ok "no answer key is in the workspace" || bad "an answer key is in the workspace"
[ -f "$WS/README.md" ] && [ -f "$WS/plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh" ] \
  && ok "the commit's tree is in the workspace" || bad "the commit's tree is not in the workspace"
[ ! -e "$WS/later.txt" ] && ok "a file from a later commit is absent" || bad "later.txt is present: the snapshot is not the named commit"
[ ! -e "$WS/.git" ] && ok "the snapshot has no .git" || bad "the snapshot holds .git"
[ ! -e "$WS/.claude" ] && ok "the snapshot has no top-level .claude/" || bad "the snapshot holds .claude/"
[ ! -e "$WS/plugins/intake-toolkit/evals" ] && ok "the plugin's evals/ is absent" || bad "the snapshot holds the plugin's evals/"
[ ! -e "$WS/plugins/intake-toolkit/skills/intake" ] && ok "skills/intake/ is absent" || bad "the snapshot holds skills/intake/"
[ ! -e "$WS/plugins/intake-toolkit/agents/implementability-probe.md" ] \
  && ok "the probe's agent file is absent" || bad "the snapshot holds the probe's agent file"
[ -f "$WS/plugins/intake-toolkit/agents/other.md" ] && [ -f "$WS/plugins/other/evals/keep.md" ] \
  && [ -f "$WS/docs/guide/keep.md" ] \
  && ok "another agent, another plugin's evals/ and the other docs stay" || bad "the snapshot dropped a path it must keep"

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
