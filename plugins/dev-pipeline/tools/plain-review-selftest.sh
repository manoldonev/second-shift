#!/usr/bin/env bash
# plain-review-selftest.sh — behavioral selftest for tools/plain-review.sh, the plain session the review skills run.
# run.sh composes the same parts; its scenario cases are skills/run/run-joined-selftest.sh.
#
# INVARIANTS GUARDED: `run` gives the session a tree of the head with no .git and no plans dir, a prompt with the diff
# less the plans dir and the ticket less every line naming the record, Read/Grep/Glob only, and a deny on the
# reviewed checkout and every --deny-read path; with no ticket the prompt says so; a final message carrying a verdict
# is the draft; no verdict, or a session past --timeout, is exit 1 with the reason in <out>/why; a flag with no value
# is usage, never a hang; `enabled` reads RUN_JOINED_REVIEW, then run.joinedReview, defaults to true, and refuses any
# other value; the session is always denied the Atlassian write tools and each transcript dir, and its tree holds none
# of the PR's Claude config; with no --out, `run` uses `out-dir <head>`, cleared of an earlier run's files.
#
# Operator-safe: no network, no real claude. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/plain-review.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/plain-review-selftest.XXXXXX")"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

R="$T/repo"; mkdir -p "$R/src" "$R/docs/plans"
git -C "$R" init -q -b main && git -C "$R" config user.email t@example.com && git -C "$R" config user.name t
echo 'one' > "$R/src/a.txt"; git -C "$R" add -A && git -C "$R" commit -qm base
git -C "$R" checkout -qb feature
echo 'two' >> "$R/src/a.txt"; echo '| D-1 | secret-record-row |' > "$R/docs/plans/repo-7-decisions.md"
mkdir -p "$R/.claude"; echo '{"hooks":{}}' > "$R/.claude/settings.json"; echo '{"mcpServers":{}}' > "$R/.mcp.json"; echo 'local' > "$R/CLAUDE.local.md"
git -C "$R" add -A && git -C "$R" commit -qm change
mkdir -p "$T/home/.claude/projects" "$T/home/.claude-work/projects" "$T/home/.claude-bare" "$T/cfg/projects"
HEAD_SHA="$(git -C "$R" rev-parse HEAD)"
printf '%s\n' '# Add two' '' 'Append two to a.txt.' 'Record: docs/plans/repo-7-decisions.md' > "$T/ticket.md"

cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DIR/args"; pwd -P > "$FAKE_DIR/cwd"; cat > "$FAKE_DIR/prompt"
ls -A > "$FAKE_DIR/tree"; [ -e docs/plans ] && echo plans >> "$FAKE_DIR/tree"
case "$FAKE_MODE" in
  verdict) printf '{"subtype":"success","result":"Done.\\n```\\nverdict: needs-work\\n## Findings\\n- [blocker] B1 src/a.txt:2 — bad\\n```","total_cost_usd":0.25}\n' ;;
  none) printf '{"subtype":"success","result":"I could not decide."}\n' ;;
  slow) sleep 30 ;;
esac
EOF
chmod +x "$T/claude"
export PLAIN_CLAUDE="$T/claude" FAKE_DIR="$T"; unset RUN_JOINED_REVIEW

HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" FAKE_MODE=verdict bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o1" --plans-dir docs/plans \
  --ticket "$T/ticket.md" --record repo-7-decisions.md --deny-read "$T/lane-scratch" --model opus >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && [ "$(head -1 "$T/o1/verdict.md")" = "verdict: needs-work" ] && grep -qF -- '- [blocker] B1 src/a.txt:2 — bad' "$T/o1/verdict.md" \
  && ! grep -q '```' "$T/o1/verdict.md" && ok "(p1) the verdict in the final message is the draft, fences dropped" || bad "(p1) rc=$RC $(cat "$T/o1/verdict.md" "$T/o1/why" 2>/dev/null)"
[ "$(cat "$T/cwd")" = "$T/o1/tree" ] && grep -qx 'src' "$T/tree" && ! grep -qx '.git' "$T/tree" && ! grep -qx 'plans' "$T/tree" \
  && ok "(p2) the session runs in a tree of the head with no .git and no plans dir" || bad "(p2) cwd=$(cat "$T/cwd") tree=$(tr '\n' ' ' < "$T/tree")"
grep -qx '+two' "$T/prompt" && ! grep -q 'secret-record-row\|repo-7-decisions' "$T/prompt" && grep -qx 'Append two to a.txt.' "$T/prompt" \
  && grep -qF "saved to \`$T/o1/scratch/verdict.md\`" "$T/prompt" && ! grep -q '^<!--' "$T/prompt" \
  && ok "(p3) the prompt holds the diff less the plans dir and the ticket less the record line, below the header" || bad "(p3) $(head -c 600 "$T/prompt")"
DIS="$(awk 'p { print; exit } $0 == "--disallowedTools" { p = 1 }' "$T/args")"
ALW="$(awk 'p { print; exit } $0 == "--allowedTools" { p = 1 }' "$T/args")"
[ "$ALW" = "Read,Grep,Glob" ] && case ",$DIS," in *",Bash,"*",Read(/$R/**),Read(/$T/lane-scratch/**),"*) true ;; *) false ;; esac \
  && grep -qx -- '--strict-mcp-config' "$T/args" && grep -qx opus "$T/args" \
  && ok "(p4) Read/Grep/Glob only, no MCP, and reads of the checkout and each --deny-read path denied" || bad "(p4) allow=$ALW deny=$DIS"
NW="$(printf '%s' "$DIS" | tr ',' '\n' | grep -c '^mcp__\(atlassian\|plugin_atlassian_atlassian\|claude_ai_Atlassian_Rovo\)__\(add\|create\|edit\|transition\|update\)')"
case ",$DIS," in *",mcp__atlassian__createJiraIssue,"*",mcp__claude_ai_Atlassian_Rovo__addTeamworkGraphContext,"*) [ "$NW" -eq 42 ] ;; *) false ;; esac \
  && ok "(p18) the 14 Atlassian write tools are denied under all 3 namespaces, under github too" || bad "(p18) $NW write tools denied"
case ",$DIS," in *",Read(/$T/home/.claude/projects/**),"*) true ;; *) false ;; esac \
  && case ",$DIS," in *",Read(/$T/home/.claude-work/projects/**),"*) true ;; *) false ;; esac \
  && case ",$DIS," in *",Read(/$T/cfg/projects/**),"*) true ;; *) false ;; esac \
  && case "$DIS" in *"$T/home/.claude-bare"*) false ;; *) true ;; esac \
  && ok "(p19) reads of each existing transcript dir are denied: ~/.claude, ~/.claude-*, \$CLAUDE_CONFIG_DIR" || bad "(p19) deny=$DIS"
! grep -qx '.claude' "$T/tree" && ! grep -qx '.mcp.json' "$T/tree" && ! grep -qx 'CLAUDE.local.md' "$T/tree" \
  && ok "(p20) the tree holds none of the PR's .claude/, .mcp.json or CLAUDE.local.md" || bad "(p20) tree=$(tr '\n' ' ' < "$T/tree")"

grep -q '^Also flag a requirement the ticket states' "$T/prompt" && [ "$(cat "$T/o1/ticket")" = true ] \
  && ok "(p5) with a ticket the ticket-requirement paragraph stays, and <out>/ticket is true" || bad "(p5) ticket=$(cat "$T/o1/ticket" 2>/dev/null)"

FAKE_MODE=verdict bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o2" --plans-dir docs/plans >/dev/null 2>&1
grep -qx 'No ticket is available for this change.' "$T/prompt" && ! grep -q 'Also flag a requirement the ticket states' "$T/prompt" \
  && [ "$(cat "$T/o2/ticket")" = false ] && grep -qx -- '--strict-mcp-config' "$T/args" \
  && ok "(p6) with no ticket the prompt says so, drops the ticket-requirement paragraph, and <out>/ticket is false" || bad "(p6) $(sed -n '/<ticket>/,/Ignore style/p' "$T/prompt")"

FAKE_MODE=verdict bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o5" --plans-dir docs/plans --jira-key ABC-12 >/dev/null 2>&1
ALW="$(awk 'p { print; exit } $0 == "--allowedTools" { p = 1 }' "$T/args")"
grep -q 'Fetch ticket ABC-12 with the getJiraIssue tool' "$T/prompt" && grep -q '^Also flag a requirement the ticket states' "$T/prompt" \
  && ! grep -qx -- '--strict-mcp-config' "$T/args" && [ "$(cat "$T/o5/ticket")" = true ] \
  && [ "$ALW" = "Read,Grep,Glob,mcp__atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__claude_ai_Atlassian_Rovo__getJiraIssue" ] \
  && ok "(p7) --jira-key: MCP loads, getJiraIssue is the one tool added, and the prompt names the key" || bad "(p7) allow=$ALW"
bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o6" --ticket "$T/ticket.md" --jira-key ABC-12 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(p8) --ticket and --jira-key together is usage: exit 2" || bad "(p8) rc=$RC"

FAKE_MODE=none bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o3" --plans-dir docs/plans >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && [ "$(cat "$T/o3/why")" = "the blind review returned no verdict" ] && [ ! -s "$T/o3/verdict.md" ] \
  && ok "(p9) a final message with no verdict is exit 1, and why says so" || bad "(p9) rc=$RC why=$(cat "$T/o3/why" 2>/dev/null)"

FAKE_MODE=slow bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o4" --plans-dir docs/plans --timeout 2 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && [ "$(cat "$T/o4/why")" = "the blind review ran past 2s" ] && [ -s "$T/o4/end" ] \
  && ok "(p10) a session past --timeout is stopped: exit 1, and why says so" || bad "(p10) rc=$RC why=$(cat "$T/o4/why" 2>/dev/null)"
W1="$(cat "$T/o1/wall" 2>/dev/null)"; W4="$(cat "$T/o4/wall" 2>/dev/null)"
case "$W1" in ''|*[!0-9]*) W1=-1 ;; esac; case "$W4" in ''|*[!0-9]*) W4=-1 ;; esac
[ "$W1" -ge 0 ] && [ "$W4" -ge 2 ] && [ ! -e "$T/o6/wall" ] \
  && ok "(p17) <out>/wall holds the session's whole seconds once it ends, and is absent when no session ran" || bad "(p17) o1=$W1 o4=$W4 o6=$(cat "$T/o6/wall" 2>/dev/null)"

mkdir -p "$T/tmp"; D="$(TMPDIR="$T/tmp" bash "$TOOL" out-dir "$HEAD_SHA")"
mkdir -p "$D/scratch"; echo stale > "$D/why"; echo 'verdict: approve' > "$D/verdict.md"; echo stale > "$D/scratch/old"
TMPDIR="$T/tmp" FAKE_MODE=none bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --plans-dir docs/plans >/dev/null 2>&1; RC=$?
[ "$D" = "$T/tmp/plain-review-$HEAD_SHA" ] && [ "$RC" -eq 1 ] && [ "$(cat "$D/why")" = "the blind review returned no verdict" ] \
  && [ ! -s "$D/verdict.md" ] && [ ! -e "$D/scratch/old" ] \
  && ok "(p21) with no --out, run uses out-dir <head>, after clearing what an earlier run left there" || bad "(p21) D=$D rc=$RC why=$(cat "$D/why" 2>/dev/null)"
bash "$TOOL" out-dir 'not-a-sha' >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(p22) out-dir refuses anything but a hex sha: exit 2" || bad "(p22) rc=$RC"

echo '{"run":{"joinedReview":false}}' > "$T/off.json"; echo '{"run":{"joinedReview":"yes"}}' > "$T/bad.json"; echo '{}' > "$T/none.json"
[ "$(bash "$TOOL" enabled "$T/none.json")" = true ] && [ "$(bash "$TOOL" enabled "$T/off.json")" = false ] \
  && [ "$(bash "$TOOL" enabled "$T/missing.json")" = true ] && ok "(p11) enabled: unset or no config is true, false is false" || bad "(p11)"
bash "$TOOL" enabled "$T/bad.json" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(p12) enabled refuses a value that is not a boolean: exit 2" || bad "(p12) rc=$RC"
bash "$TOOL" run --worktree "$R" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(p13) run without its required flags is usage: exit 2" || bad "(p13) rc=$RC"

echo '{"run":{"joinedReview":true}}' > "$T/on.json"
[ "$(RUN_JOINED_REVIEW=false bash "$TOOL" enabled "$T/on.json")" = false ] && [ "$(RUN_JOINED_REVIEW=true bash "$TOOL" enabled "$T/off.json")" = true ] \
  && [ "$(RUN_JOINED_REVIEW='' bash "$TOOL" enabled "$T/off.json")" = false ] \
  && ok "(p14) RUN_JOINED_REVIEW beats the config both ways; empty falls through to the config" || bad "(p14)"
RUN_JOINED_REVIEW=yes bash "$TOOL" enabled "$T/on.json" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(p15) a RUN_JOINED_REVIEW that is not a boolean: exit 2" || bad "(p15) rc=$RC"

bash "$TOOL" run --worktree "$R" --base main --head "$HEAD_SHA" --out "$T/o7" --deny-read >/dev/null 2>&1 & PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$PID" 2>/dev/null; then kill -KILL "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; bad "(p16) a trailing flag with no value still runs after 10 s"
else wait "$PID"; RC=$?; [ "$RC" -eq 2 ] && ok "(p16) a trailing flag with no value is usage: exit 2, not a hang" || bad "(p16) rc=$RC"; fi

echo "plain-review-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
