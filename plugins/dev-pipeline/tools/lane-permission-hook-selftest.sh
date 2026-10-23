#!/usr/bin/env bash
# shellcheck disable=SC2016  # the commands fed to the hook carry a literal $( ) and backticks
# lane-permission-hook-selftest.sh — behavioral coverage for tools/lane-permission-hook.sh (#1048 AC-7 AC-8).
#
# The hook is fed PermissionRequest input in the shape the hooks reference documents
# (code.claude.com/docs/en/hooks, "PermissionRequest input": session_id, cwd, hook_event_name, tool_name, tool_input) and
# its decision is read back from the hookSpecificOutput.decision object that page names (behavior; message for a deny).
# The worktree, the main checkout and the scratch dir are real directories with real symlinks, so `..` and link
# resolution run against a filesystem, not a string. That run.sh wires this script into the BUILD spawn only is
# run-claim-selftest's (AC-6).
#
# Operator-safe: no gh, no network, no Claude CLI. Runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane-permission-hook.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/lane-permission-hook-selftest.XXXXXX")" || { echo "lane-permission-hook-selftest: FAIL — no temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
WT="$T/wt"; MAIN="$T/main"; SCR="$T/scratch"
mkdir -p "$WT/.claude/agents" "$WT/sub" "$MAIN/.claude" "$SCR"
ln -s "$MAIN" "$WT/link"                                  # a worktree path that is the main checkout
ln -s "$MAIN/.claude/NOTES.md" "$WT/.claude/escape.md"    # a .claude/ file that is the main checkout's
ln -s settings.json "$WT/.claude/alias.md"                # a .claude/ file that is the settings file
ln -s "$WT/.claude/agents" "$WT/sub/agents-link"          # a worktree path that is a .claude/ subdirectory
P="$(cd "$T" && pwd -P)"   # the physical temp root: on macOS $TMPDIR sits under the /var -> /private/var link

hook() { # hook <tool> <tool_input-json>: the decision object, or nothing
  jq -cn --arg t "$1" --argjson i "$2" --arg cwd "$WT" '{session_id:"s",transcript_path:"/x.jsonl",cwd:$cwd,permission_mode:"acceptEdits",hook_event_name:"PermissionRequest",tool_name:$t,tool_input:$i}' \
    | bash "$HOOK" "$WT" "$SCR"
}
bash_in() { jq -cn --arg c "$1" '{command:$c,description:"d"}'; }
file_in() { jq -cn --arg p "$1" '{file_path:$p,content:"x",old_string:"a",new_string:"b"}'; }
WITHHELD='withheld from lane sessions'; SINGLE='Run each shell command on its own'; LOOKUP='use the Grep tool'; NOTGRANTED="is not on this session's allowlist"
expect_deny() { # expect_deny <label> <reason-phrase> <tool> <tool_input-json> [<must-also-name>]
  local out beh msg; out="$(hook "$3" "$4")"
  beh="$(jq -r '.hookSpecificOutput.decision.behavior // "none"' <<<"$out" 2>/dev/null)"; msg="$(jq -r '.hookSpecificOutput.decision.message // ""' <<<"$out" 2>/dev/null)"
  if [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out" 2>/dev/null)" = PermissionRequest ] && [ "$beh" = deny ] && [[ "$msg" == *"$2"* ]] && [[ "$msg" == *"${5:-}"* ]]; then ok "$1"
  else bad "$1: want deny with '$2'${5:+ naming $5}, got $beh: $msg"; fi
}
expect_allow() { # expect_allow <label> <tool> <tool_input-json>
  local beh; beh="$(hook "$2" "$3" | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null)"
  [ "$beh" = allow ] && ok "$1" || bad "$1: want allow, got ${beh:-nothing}"
}

echo "== (h1) AC-7: withheld — a path that resolves outside the worktree and the scratch dir =="
expect_deny "(h1a) a file tool on the main checkout" "$WITHHELD" Read "$(file_in "$MAIN/.claude/second-shift.config.json")" "$MAIN/.claude/second-shift.config.json"
expect_deny "(h1b) Grep's path on the main checkout" "$WITHHELD" Grep '{"pattern":"x","path":"'"$MAIN"'"}' "$MAIN"
expect_deny "(h1c) a Bash absolute path, ahead of the lookup reason" "$WITHHELD" Bash "$(bash_in "ls -la $MAIN/.claude/")" "$MAIN/.claude/"
expect_deny "(h1d) a \`..\` escape from the worktree" "$WITHHELD" Edit "$(file_in "$WT/sub/../../main/x.txt")" "$P/main/x.txt"
expect_deny "(h1e) a worktree symlink into the main checkout" "$WITHHELD" Bash "$(bash_in "wc -l $WT/link/x.txt")" "$P/main/x.txt"
expect_deny "(h1f) a path after a redirect or an option's =, ahead of the compound reason" "$WITHHELD" Bash "$(bash_in "gh pr edit 7 --body-file=$MAIN/b.md 2>&1 | tail")" "$MAIN/b.md"
expect_deny "(h1g) a path inside \$( ), ahead of the compound reason" "$WITHHELD" Bash "$(bash_in "gh issue view \$(cat '$MAIN/n')")" "$MAIN/n"

echo "== (h2) AC-7: run each command on its own =="
expect_deny "(h2a) \$( ) with a || fallback, /dev/null no path (the build's first command in #1023 and #1040)" "$SINGLE" Bash "$(bash_in 'gh issue view 1040 --repo $(echo) 2>/dev/null || gh issue view 1040')"
expect_deny "(h2b) backticks" "$SINGLE" Bash "$(bash_in 'gh issue view `echo 1`')"
expect_deny "(h2c) a granted command piped into grep, ahead of the lookup reason" "$SINGLE" Bash "$(bash_in "bash $WT/x-selftest.sh 2>&1 | grep -v PASS")"
expect_deny "(h2d) ;" "$SINGLE" Bash "$(bash_in "bash $WT/x.sh ; echo rc")"
expect_deny "(h2e) &&" "$SINGLE" Bash "$(bash_in "true && echo ok")"
expect_deny "(h2f) ||" "$SINGLE" Bash "$(bash_in "false || echo ok")"
expect_deny "(h2g) cd into the worktree" "$SINGLE" Bash "$(bash_in "cd $WT/sub")"
expect_deny "(h2h) a scratch-dir path is no withheld path" "$SINGLE" Bash "$(bash_in "cat $SCR/log | head")"

echo "== (h3) AC-7: the read helpers point at the Grep, Glob and Read tools =="
for c in grep find ls wc head cat tail; do expect_deny "(h3) $c" "$LOOKUP" Bash "$(bash_in "$c -n $WT/sub")" "$c is not granted"; done
expect_deny "(h3q) a | inside quotes is no pipe" "$LOOKUP" Bash "$(bash_in "grep -E 'a|b;c' $WT/sub")"

echo "== (h4) AC-7: anything else is not granted =="
expect_deny "(h4a) an ungranted command" "$NOTGRANTED" Bash "$(bash_in 'claude plugin list --json')" 'claude plugin list --json'
expect_deny "(h4b) an ungranted tool" "$NOTGRANTED" WebFetch '{"url":"https://example.com","prompt":"p"}' WebFetch
expect_deny "(h4c) an edit in the worktree outside .claude/ is never allowed" "$NOTGRANTED" Edit "$(file_in "$WT/.git/config")"

echo "== (h5) AC-8: a file directly in <wt>/.claude/ =="
expect_allow "(h5a) Edit <wt>/.claude/SECOND-SHIFT.md" Edit "$(file_in "$WT/.claude/SECOND-SHIFT.md")"
expect_allow "(h5b) Write <wt>/.claude/SECOND-SHIFT.md" Write "$(file_in "$WT/.claude/SECOND-SHIFT.md")"
expect_allow "(h5c) a \`..\` that stays in <wt>/.claude/" Write "$(file_in "$WT/sub/../.claude/NEW.md")"
expect_deny "(h5d) settings.json" "lane sessions never edit it" Edit "$(file_in "$WT/.claude/settings.json")" ".claude/settings.json"
expect_deny "(h5e) settings.local.json" "lane sessions never edit it" Write "$(file_in "$WT/.claude/settings.local.json")" ".claude/settings.local.json"
expect_deny "(h5f) SETTINGS.JSON, which a case-insensitive disk opens as settings.json" "lane sessions never edit it" Write "$(file_in "$WT/.claude/SETTINGS.JSON")" "SETTINGS.JSON"
expect_deny "(h5g) a file in .claude/agents/" "sessions load" Write "$(file_in "$WT/.claude/agents/x.md")" ".claude/agents/"
expect_deny "(h5h) a symlink in .claude/ to settings.json" "lane sessions never edit it" Edit "$(file_in "$WT/.claude/alias.md")" "settings.json"
expect_deny "(h5i) a \`..\` out of .claude/ into the main checkout" "$WITHHELD" Write "$(file_in "$WT/.claude/../../main/.claude/NOTES.md")" "$P/main/.claude/NOTES.md"
expect_deny "(h5j) a symlink in .claude/ into the main checkout" "$WITHHELD" Edit "$(file_in "$WT/.claude/escape.md")" "$P/main/.claude/NOTES.md"
expect_deny "(h5k) a tool other than Edit and Write is not allowed there" "$NOTGRANTED" NotebookEdit '{"notebook_path":"x","file_path":"'"$WT/.claude/n.ipynb"'"}'

echo "== (h7) #1080: the lane files run.sh names (the record and the plan) under a plansDir in .claude/ =="
mkdir -p "$WT/.claude/plans"
LANE_REC="$WT/.claude/plans/wt-42-decisions.md"; LANE_PLAN="$WT/.claude/plans/wt-42-plan.md"
hook_lane() { # hook_lane <tool> <tool_input-json>: the decision behavior, the hook given the two lane files
  jq -cn --arg t "$1" --argjson i "$2" --arg cwd "$WT" '{cwd:$cwd,hook_event_name:"PermissionRequest",tool_name:$t,tool_input:$i}' \
    | bash "$HOOK" "$WT" "$SCR" "$LANE_REC" "$LANE_PLAN" | jq -r '.hookSpecificOutput.decision | .behavior + " " + (.message // "")'
}
[ "$(hook_lane Write "$(file_in "$LANE_PLAN")")" = 'allow ' ] && ok "(h7a) Write the named plan in .claude/plans/" || bad "(h7a) plan write: $(hook_lane Write "$(file_in "$LANE_PLAN")")"
[ "$(hook_lane Edit "$(file_in "$LANE_REC")")" = 'allow ' ] && ok "(h7b) Edit the named record in .claude/plans/" || bad "(h7b) record edit: $(hook_lane Edit "$(file_in "$LANE_REC")")"
[ "$(hook_lane Write "$(file_in "$WT/sub/../.claude/plans/wt-42-plan.md")")" = 'allow ' ] && ok "(h7c) a \`..\` that resolves to the named plan" || bad "(h7c) dotted plan path not allowed"
[[ "$(hook_lane Write "$(file_in "$WT/.claude/plans/other.md")")" == 'deny '*'sessions load'* ]] && ok "(h7d) another file in .claude/plans/ is still denied" || bad "(h7d) an unnamed plans file was not denied"
[[ "$(hook_lane NotebookEdit '{"file_path":"'"$LANE_PLAN"'"}')" == 'deny '* ]] && ok "(h7e) a tool other than Edit and Write on a lane file is still denied" || bad "(h7e) NotebookEdit on the plan was not denied"
expect_deny "(h7f) without the lane files named, the plan in .claude/plans/ is denied as before" "sessions load" Write "$(file_in "$LANE_PLAN")" ".claude/plans/"
[ "$(jq -cn --arg cwd "$WT" --arg p "$LANE_PLAN" '{cwd:$cwd,tool_name:"Write",tool_input:{file_path:$p}}' | bash "$HOOK" "$WT" "" "$LANE_PLAN" | jq -r '.hookSpecificOutput.decision.behavior')" = allow ] \
  && ok "(h7g) an empty scratch dir argument still reads the lane files after it" || bad "(h7g) empty scratch arg broke the lane files"

echo "== (h8) chmod +x on files in the worktree =="
expect_allow "(h8a) a relative path, against the input's cwd" Bash "$(bash_in "chmod +x sub/new-selftest.sh")"
expect_allow "(h8b) absolute paths, more than one" Bash "$(bash_in "chmod +x $WT/sub/a.sh $WT/b.sh")"
expect_allow "(h8c) a \`..\` that stays in the worktree" Bash "$(bash_in "chmod +x sub/../c.sh")"
expect_allow "(h8d) a file directly in .claude/" Bash "$(bash_in "chmod +x .claude/x.sh")"
expect_deny "(h8e) an absolute path outside the worktree" "$WITHHELD" Bash "$(bash_in "chmod +x $MAIN/x.sh")" "$MAIN/x.sh"
expect_deny "(h8f) a relative \`..\` out of the worktree" "$WITHHELD" Bash "$(bash_in "chmod +x sub/a.sh ../main/x.sh")" "$P/main/x.sh"
expect_deny "(h8g) a relative path through a symlink out of the worktree" "$WITHHELD" Bash "$(bash_in "chmod +x link/x.sh")" "$P/main/x.sh"
expect_deny "(h8h) an absolute path through a symlink out of the worktree" "$WITHHELD" Bash "$(bash_in "chmod +x $WT/link/x.sh")" "$P/main/x.sh"
expect_deny "(h8i) a file in a .claude/ subdirectory" "$NOTGRANTED" Bash "$(bash_in "chmod +x .claude/agents/x.sh")"
expect_deny "(h8j) a .claude/ subdirectory named in another case" "$NOTGRANTED" Bash "$(bash_in "chmod +x $WT/.CLAUDE/hooks/x.sh")"
expect_deny "(h8k) a symlink into a .claude/ subdirectory" "$NOTGRANTED" Bash "$(bash_in "chmod +x sub/agents-link/x.sh")"
expect_deny "(h8l) the scratch dir" "$NOTGRANTED" Bash "$(bash_in "chmod +x $SCR/x.sh")"
for c in 'chmod +x' 'chmod 755 sub/a.sh' 'chmod u+x sub/a.sh' 'chmod -R +x sub' 'chmod +x -R sub' 'chmod +x -- sub/a.sh' "chmod +x 'sub/a.sh'" \
  'chmod +x l*nk/x.sh' 'chmod +x {link,sub}/x.sh' 'chmod +x ~/x.sh' 'chmod +x $HOME/x.sh' 'chmod +x li\nk/x.sh' 'chmod +x sub/a.sh > sub/out' 'chmod +x sub/a.sh & sleep 1' \
  'X=1 chmod +x sub/a.sh' 'sudo chmod +x sub/a.sh'; do
  expect_deny "(h8m) another form: $c" "$NOTGRANTED" Bash "$(bash_in "$c")"
done
expect_deny "(h8n) chained with git add, the compound reason" "$SINGLE" Bash "$(bash_in "chmod +x sub/a.sh && git add sub/a.sh")"

echo "== (h6) no worktree or unreadable input: the hook says nothing, the flow proceeds unchanged =="
[ -z "$(printf '{}' | bash "$HOOK")" ] && [ -z "$(printf 'not json' | bash "$HOOK" "$WT")" ] && ok "(h6) silent" || bad "(h6) the hook decided without a worktree or on unreadable input"

echo
echo "lane-permission-hook-selftest: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
