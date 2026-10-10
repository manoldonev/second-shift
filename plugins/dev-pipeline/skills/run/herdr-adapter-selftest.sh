#!/usr/bin/env bash
# herdr-adapter-selftest.sh — drives herdr-adapter.sh (the bundled RUN_WATCH_CMD, #939, and the build/review launcher,
# #945) against a fake `herdr`, a fake `gh`, a fake editor and a git fixture: the watch call's herdr calls and what they
# carry, the log pane's sidebar states, the transcript pane's rendering, and the launcher's calls, derivations and editor
# waiter. Model-free and herdr-free; what only a real herdr shows is the operator's post-merge trial.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AD="$SCRIPT_DIR/herdr-adapter.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/herdr-adapter-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
for _v in $(compgen -e HERDR_) $(compgen -e GIT_) RUN_WATCH_EDITOR RUN_WORKTREE_ROOT SECOND_SHIFT_CONFIG SS_LOG SS_ISSUE SS_ADAPTER SS_WT SS_PR SS_EDITOR_WAIT_SECS; do unset "$_v"; done

# ---- fakes: herdr answers the JSON shapes of herdr 0.9.3 and logs every call, one argv element per line. Ids carry the
# call number, so a test can tell which call returned the id a later call names. It records any herdr pane, tab or
# workspace id it inherits to `env`: a call that runs in a herdr pane's context can act on it without naming it. `down`
# answers every call as a stopped server does; `fail-on` fails any call carrying one of its lines as an argv element;
# `silent` times out wait-output ----
mkdir -p "$T/bin"
cat > "$T/bin/herdr" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_HERDR"; n=$(( $(cat "$S/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/n"
printf '%s\n' "$@" > "$S/call-$n.txt"; echo "$*" >> "$S/calls"
for v in HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID; do [ -z "${!v:-}" ] || echo "$v=${!v}" >> "$S/env"; done
[ -f "$S/down" ] && { echo "{\"id\":\"cli:$1:$2\",\"error\":{\"code\":\"server_not_running\",\"message\":\"no herdr server is running at /tmp/herdr.sock; run \`herdr\` to start or attach it\"}}" >&2; exit 1; }
if [ -f "$S/fail-on" ]; then for a in "$@"; do grep -qxF -- "$a" "$S/fail-on" && { echo "{\"id\":\"cli\",\"error\":{\"code\":\"failed\",\"message\":\"fake failure on $a\"}}" >&2; exit 1; }; done; fi
case "$1 ${2:-}" in
  "workspace list")   if [ -f "$S/workspaces.json" ]; then cat "$S/workspaces.json"; else echo '{"id":"1","result":{"type":"workspace_list","workspaces":[]}}'; fi ;;
  "workspace create") echo "{\"id\":\"1\",\"result\":{\"type\":\"workspace_created\",\"workspace\":{\"workspace_id\":\"w$n\",\"label\":\"x\"},\"tab\":{\"tab_id\":\"w$n:1\"},\"root_pane\":{\"pane_id\":\"w$n-1\"}}}" ;;
  "tab create")       echo "{\"id\":\"1\",\"result\":{\"type\":\"tab_created\",\"tab\":{\"tab_id\":\"t$n\"},\"root_pane\":{\"pane_id\":\"p$n\"}}}" ;;
  "pane split")       echo "{\"id\":\"1\",\"result\":{\"type\":\"pane_info\",\"pane\":{\"pane_id\":\"p$n\"}}}" ;;
  "pane wait-output") if [ -f "$S/silent" ]; then echo '{"id":"cli:pane:wait-output","error":{"code":"timeout","message":"timed out waiting for output match"}}' >&2; exit 1; fi
                      echo '{"id":"1","result":{"type":"output_matched"}}' ;;
  "pane run"|"pane report-agent") echo '{"id":"1","result":{"type":"ok"}}' ;;
  *) echo "fake herdr: unhandled $*" >&2; exit 1 ;;
esac
EOF
# gh answers `pr view <n> --json <field>` from $FAKE_GH/<field>.json, and fails as gh does when there is none
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"; f=""
while [ $# -gt 0 ]; do [ "$1" = --json ] && f="${2:-}"; shift; done
[ -n "$f" ] && [ -f "$FAKE_GH/$f.json" ] || { echo 'GraphQL: Could not resolve to a PullRequest with the number of 7.' >&2; exit 1; }
cat "$FAKE_GH/$f.json"
EOF
# the editors append, so two opens are two lines; `editor-fails` makes them exit 1
for e in code cursor; do
  cat > "$T/bin/$e" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "\$FAKE_HERDR/editor-$e.txt"
[ ! -f "\$FAKE_HERDR/editor-fails" ]
EOF
done
chmod +x "$T/bin/"*
mkdir -p "$T/noperl"   # what build needs, and no perl
for x in bash git jq dirname basename mkdir cat grep rm date sleep; do ln -s "$(command -v "$x")" "$T/noperl/$x"; done; ln -s "$T/bin/code" "$T/noperl/code"
export PATH="$T/bin:$PATH" HERDR_BIN="$T/bin/herdr"

case_dir() { # case_dir <name> — a fresh fake-herdr state, a run log at a path no shell may parse, a worktree
  c="$T/$1"; mkdir -p "$c/herdr" "$c/it's \$HOME dir" "$c/wt"; export FAKE_HERDR="$c/herdr"
  LOG="$c/it's \$HOME dir/42-lean-run-1.log"; echo "start" > "$LOG"
}
call_of() { grep -lx -- "$1" "$FAKE_HERDR"/call-*.txt 2>/dev/null | while read -r f; do [ "$(sed -n 2p "$f")" = "$2" ] && echo "$f"; done | head -n 1; } # call_of <verb> <sub>
has_arg_pair() { awk -v a="$2" -v b="$3" 'p == a && $0 == b { f = 1 } { p = $0 } END { exit !f }' "$1"; } # has_arg_pair <call file> <flag> <value>
bounded_run() { # bounded_run <secs> <outfile> <cmd...> — the panes follow forever by design; a hang is a FAIL, never a stuck suite
  local s="$1" o="$2" p t=0; shift 2
  "$@" > "$o" 2>&1 & p=$!
  while kill -0 "$p" 2>/dev/null && [ "$t" -lt $((s*5)) ]; do sleep 0.2; t=$((t+1)); done
  if kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
  wait "$p"
}

echo "[herdr-adapter-selftest] the watch call"

# (o1) AC-7 AC-8 AC-15 AC-21: no workspace yet — create it unfocused, then a tab for this launch, two panes, fixed text
case_dir o1; HERDR_PANE_ID=operator-pane HERDR_TAB_ID=operator-tab HERDR_WORKSPACE_ID=operator-ws bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(o1) the watch call exits 0" || bad "(o1) rc=$rc: $(tr '\n' '|' < "$c/out")"
[ "$(cut -d' ' -f1-2 "$FAKE_HERDR/calls" | tr '\n' ',')" = "workspace list,workspace create,tab create,pane run,pane split,pane run," ] \
  && ok "(o1) list, create, tab, watch pane, split, transcript pane — in that order" || bad "(o1) calls: $(tr '\n' '|' < "$FAKE_HERDR/calls")"
wc="$(call_of workspace create)"
[ -n "$wc" ] && has_arg_pair "$wc" --label 'acme#42' && grep -qx -- --no-focus "$wc" && has_arg_pair "$wc" --cwd "$c/wt" \
  && ok "(o1) [AC-7] the workspace is created as acme#42 with --no-focus, on the worktree" || bad "(o1) [AC-7] workspace create: $(tr '\n' ' ' < "${wc:-/dev/null}")"
tc="$(call_of tab create)"
[ -n "$tc" ] && has_arg_pair "$tc" --workspace w2 && has_arg_pair "$tc" --env "SS_LOG=$LOG" && has_arg_pair "$tc" --env SS_ISSUE=42 \
  && has_arg_pair "$tc" --env "SS_ADAPTER=$AD" && grep -qx -- --no-focus "$tc" \
  && ok "(o1) [AC-7 AC-8] a tab in the created workspace, its inputs as --env, the log path one argv element" || bad "(o1) tab create: $(tr '\n' ' ' < "${tc:-/dev/null}")"
runs="$(grep -l '^run$' "$FAKE_HERDR"/call-*.txt)"
# shellcheck disable=SC2016  # the fixed text, literally
[ "$(for f in $runs; do sed -n 3,4p "$f" | tr '\n' ' '; echo; done | sort | tr '\n' '|')" = 'p3 bash "$SS_ADAPTER" watch |p5 bash "$SS_ADAPTER" transcript |' ] \
  && ok "(o1) [AC-8 AC-15] each pane runs fixed text that interpolates nothing, on the ids the calls returned" || bad "(o1) pane run: $(for f in $runs; do tr '\n' ' ' < "$f"; echo '|'; done)"
[ "$(grep -lF "it's" "$FAKE_HERDR"/call-*.txt | wc -l | tr -d ' ')" -eq 2 ] && ok "(o1) the log path appears only in the two --env lists (tab create, pane split)" || bad "(o1) the log path is in: $(grep -lF "it's" "$FAKE_HERDR"/call-*.txt | tr '\n' ' ')"
sc="$(call_of pane split)"
[ -n "$sc" ] && [ "$(sed -n 3p "$sc")" = p3 ] && has_arg_pair "$sc" --direction down && has_arg_pair "$sc" --ratio 0.35 \
  && has_arg_pair "$sc" --env "SS_LOG=$LOG" && has_arg_pair "$sc" --env SS_ISSUE=42 && has_arg_pair "$sc" --env "SS_ADAPTER=$AD" && grep -qx -- --no-focus "$sc" \
  && ok "(o1) [AC-15 D-24] the transcript pane is split below the root with the larger share, inputs via --env" || bad "(o1) pane split: $(tr '\n' ' ' < "${sc:-/dev/null}")"
! grep -q 'operator-' "$FAKE_HERDR"/call-*.txt && [ ! -f "$FAKE_HERDR/env" ] \
  && ok "(o1) [AC-21] launched from a herdr pane, no call names that pane, tab or workspace, nor inherits their ids" || bad "(o1) [AC-21] $(grep -l 'operator-' "$FAKE_HERDR"/call-*.txt) $(cat "$FAKE_HERDR/env" 2>/dev/null)"
[ ! -f "$FAKE_HERDR/editor-code.txt" ] && [ ! -f "$FAKE_HERDR/editor-cursor.txt" ] && ok "(o1) [AC-10] RUN_WATCH_EDITOR unset: no editor" || bad "(o1) [AC-10] an editor opened"

# (o2) AC-7 D-16: re-entry reuses the workspace matched by its label alone, and still opens a new tab
case_dir o2
printf '%s' '{"result":{"type":"workspace_list","workspaces":[{"workspace_id":"w-other","label":"acme#420"},{"workspace_id":"w-old","label":"acme#42"},{"workspace_id":"w-4","label":"acme#4"}]}}' > "$FAKE_HERDR/workspaces.json"
bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^workspace create' "$FAKE_HERDR/calls" && has_arg_pair "$(call_of tab create)" --workspace w-old \
  && ok "(o2) [AC-7] an existing acme#42 is reused (not acme#420 or acme#4), with a new tab" || bad "(o2) rc=$rc calls: $(tr '\n' '|' < "$FAKE_HERDR/calls")"

# (o3) AC-10: the editor, once per call, on the worktree
for e in code cursor; do
  case_dir "o3-$e"; RUN_WATCH_EDITOR="$e" bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(tr '\n' ' ' < "$FAKE_HERDR/editor-$e.txt" 2>/dev/null)" = "-n $c/wt " ] && ok "(o3) [AC-10] RUN_WATCH_EDITOR=$e runs '$e -n <worktree>'" || bad "(o3) $e: rc=$rc args $(cat "$FAKE_HERDR/editor-$e.txt" 2>/dev/null)"
done
case_dir o3-vim; RUN_WATCH_EDITOR=vim bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$FAKE_HERDR/editor-code.txt" ] && grep -q "not code or cursor" "$c/out" && ok "(o3) any other editor value opens nothing and says so" || bad "(o3) vim: rc=$rc $(cat "$c/out")"

# (o4) AC-6's other side: herdr down, or answering garbage, is a non-zero exit run.sh logs as one failure line
case_dir o4; touch "$FAKE_HERDR/down"; bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'workspace list failed' "$c/out" && [ "$(wc -l < "$FAKE_HERDR/calls" | tr -d ' ')" -eq 1 ] && ok "(o4) a server that is down fails the call at the first request" || bad "(o4) rc=$rc $(cat "$c/out")"
case_dir o5; echo 'not json' > "$FAKE_HERDR/workspaces.json"; bash "$AD" 42 acme "$LOG" "$c/wt" > "$c/out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && ! grep -q '^tab create' "$FAKE_HERDR/calls" && ok "(o5) a list that is not JSON fails the call before any tab is opened" || bad "(o5) rc=$rc calls: $(tr '\n' '|' < "$FAKE_HERDR/calls")"
case_dir o6; bash "$AD" 42 acme > "$c/out" 2>&1; rc=$?; [ "$rc" -eq 2 ] && ok "(o6) a short argv is a usage error" || bad "(o6) rc=$rc"

echo "[herdr-adapter-selftest] the log pane"
reports() { grep '^pane report-agent' "$FAKE_HERDR/calls" 2>/dev/null; }
# (w1) AC-9: a round reports working; the BARE terminal line reports idle on approved, once; the exit line ends the pane
case_dir w1
cat > "$LOG" <<'EOF'
2026-10-07T00:00:00Z [run] run x: issue 42
2026-10-07T00:00:01Z [run] round 1 of 3 (cost so far $0.00)
2026-10-07T00:00:02Z [run] the review session ended error (rc=1) — re-spawning REVIEW (1 of 1). No round spent, no BUILD spawn.
2026-10-07T00:00:03Z [run] terminal: approved — PR #7 approved
terminal: approved
2026-10-07T00:00:04Z [run] ci: green (read once for the report)
2026-10-07T00:00:05Z [run] detached run exited rc=0
EOF
HERDR_PANE_ID=p-root SS_LOG="$LOG" SS_ISSUE=42 bounded_run 20 "$c/out" bash "$AD" watch; rc=$?
[ "$rc" -eq 0 ] && ok "(w1) the log pane exits after the exit line" || bad "(w1) rc=$rc"
diff <(cat "$LOG") <(head -n 7 "$c/out") >/dev/null && ok "(w1) every log line is shown, from the first" || bad "(w1) output: $(tr '\n' '|' < "$c/out")"
[ "$(reports | tr '\n' '|')" = "pane report-agent p-root --source custom:second-shift --agent ss-42 --state working --message round 1 of 3|pane report-agent p-root --source custom:second-shift --agent ss-42 --state idle --message approved|" ] \
  && ok "(w1) [AC-9 D-32] working on the round line only (not the retry line), idle once on the bare approved line, no --seq" || bad "(w1) reports: $(reports | tr '\n' '|')"
# (w2) any other slug is blocked with the slug
case_dir w2; printf '%s\n' '2026-10-07T00:00:01Z [run] round 1 of 3' '2026-10-07T00:00:02Z [run] terminal: build-no-pr — no open PR' 'terminal: build-no-pr' '2026-10-07T00:00:03Z [run] detached run exited rc=1' > "$LOG"
HERDR_PANE_ID=p-root SS_LOG="$LOG" SS_ISSUE=42 bounded_run 20 "$c/out" bash "$AD" watch
[ "$(reports | grep -c 'state blocked --message build-no-pr$')" -eq 1 ] && [ "$(reports | grep -c 'state blocked')" -eq 1 ] && ok "(w2) [AC-9] blocked with the slug, once" || bad "(w2) reports: $(reports | tr '\n' '|')"
# (w3) a run that exits with no terminal line (killed, or died) is blocked with its exit code
case_dir w3; printf '%s\n' '2026-10-07T00:00:01Z [run] round 2 of 3' '2026-10-07T00:00:02Z [run] terminated; claim left in place' '2026-10-07T00:00:03Z [run] detached run exited rc=143' > "$LOG"
HERDR_PANE_ID=p-root SS_LOG="$LOG" SS_ISSUE=42 bounded_run 20 "$c/out" bash "$AD" watch
[[ "$(reports | tail -n 1)" == *'state blocked --message exited rc=143 with no terminal line' ]] && ok "(w3) [AC-9] no terminal line: blocked with the exit code" || bad "(w3) reports: $(reports | tr '\n' '|')"
# (w4) live: the pane follows lines written after it started, a line written in two halves included
case_dir w4; printf '%s\n' '2026-10-07T00:00:01Z [run] run x' > "$LOG"
( sleep 1; printf '%s\n' '2026-10-07T00:00:02Z [run] round 1 of 1' >> "$LOG"; printf 'terminal: approv' >> "$LOG"; sleep 1; printf 'ed\n2026-10-07T00:00:03Z [run] detached run exited rc=0\n' >> "$LOG" ) &
HERDR_PANE_ID=p-root SS_LOG="$LOG" SS_ISSUE=42 bounded_run 20 "$c/out" bash "$AD" watch; rc=$?; wait
[ "$rc" -eq 0 ] && grep -q '^pane report-agent .*state working' "$FAKE_HERDR/calls" && grep -q '^pane report-agent .*state idle --message approved$' "$FAKE_HERDR/calls" && ok "(w4) a live log is followed, a split line read whole, to its exit" || bad "(w4) rc=$rc reports: $(reports | tr '\n' '|')"
case_dir w5; SS_LOG="$LOG" SS_ISSUE=42 bounded_run 5 "$c/out" bash "$AD" watch; rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && grep -q 'HERDR_PANE_ID' "$c/out" && [ ! -f "$FAKE_HERDR/calls" ] && ok "(w5) outside a herdr pane the watcher refuses, reporting on nobody else's pane" || bad "(w5) rc=$rc $(cat "$c/out")"

echo "[herdr-adapter-selftest] the transcript pane"
# (t1) AC-16..AC-19: one line per rendered event, prefixed by role and attempt; a late transcript waited for; a missing one named
case_dir t1; export HOME="$c/home"; mkdir -p "$HOME/.claude-alt/projects/-x-wt"
u1=11111111-1111-4111-8111-111111111111; u2=22222222-2222-4222-8222-222222222222; u3=33333333-3333-4333-8333-333333333333
long="$(printf 'x%.0s' $(seq 1 200))"
{
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"SECRET-THOUGHT"},{"type":"text","text":"\nFirst line of text\nsecond line"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/w/src/a.ts"}},{"type":"tool_use","id":"b","name":"Bash","input":{"command":"echo '"$long"'"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c","name":"Grep","input":{"pattern":"foo.*bar"}},{"type":"tool_use","id":"d","name":"Agent","input":{"prompt":"go"}}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"SUCCESS-BODY"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b","is_error":true,"content":[{"type":"text","text":"boom happened\nmore"}]}]}}'
  # #964 D-5 D-6: the two denial shapes seen in lane transcripts, a non-zero exit, and an Edit failure
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"f","is_error":true,"content":"Permission for this tool use was denied. It requires approval\nmore"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"g","is_error":true,"content":"Permission to use Bash with command rm /tmp/x has been denied."}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"h","is_error":true,"content":"Exit code 2\n\njq: error: Could not open file x.json"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"i","is_error":true,"content":"<tool_use_error>String to replace not found in file.\nString: foo</tool_use_error>"}]}}'
  echo '{"type":"user","message":{"content":"USER-STRING-PROMPT"}}'
  echo '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"SIDECHAIN-TEXT"}]}}'
  echo '{oops not json'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e","name":"Read","input":{}}]}}'
  echo '{"type":"system","subtype":"init"}'
} > "$HOME/.claude-alt/projects/-x-wt/$u1.jsonl"
printf '%s\n' "2026-10-07T00:00:01Z [run] session: build 1.1 $u1 ~/.claude*/projects/*/$u1.jsonl" "2026-10-07T00:00:02Z [run] session: review 1.1 $u2 ~/.claude*/projects/*/$u2.jsonl" > "$LOG"
sum_before="$(cat "$HOME/.claude-alt/projects/-x-wt/$u1.jsonl" "$LOG" | cksum)"
( sleep 2; echo '{"type":"assistant","message":{"content":[{"type":"text","text":"review says hi"}]}}' > "$HOME/.claude-alt/projects/-x-wt/$u2.jsonl"; sleep 1.5
  printf '%s\n' "2026-10-07T00:00:03Z [run] session: review 1.1-retry1 $u3 ~/.claude*/projects/*/$u3.jsonl" "2026-10-07T00:00:04Z [run] detached run exited rc=5" >> "$LOG" ) &
SS_LOG="$LOG" SS_ISSUE=42 bounded_run 30 "$c/out" bash "$AD" transcript; rc=$?; wait
[ "$rc" -eq 0 ] && ok "(t1) [AC-19] the transcript pane exits after the run's exit line" || bad "(t1) rc=$rc $(tail -n 3 "$c/out" | tr '\n' '|')"
body="$(grep '^\[build 1\.1\]' "$c/out")"
expect_body="[build 1.1] First line of text
[build 1.1] Read /w/src/a.ts
[build 1.1] Bash echo $(printf 'x%.0s' $(seq 1 115))
[build 1.1] Grep foo.*bar
[build 1.1] Agent
[build 1.1] failed boom happened
[build 1.1] ERROR Permission for this tool use was denied. It requires approval
[build 1.1] ERROR Permission to use Bash with command rm /tmp/x has been denied.
[build 1.1] exit 2 jq: error: Could not open file x.json
[build 1.1] failed <tool_use_error>String to replace not found in file.
[build 1.1] [unparsed]
[build 1.1] [unparsed]"
[ "$body" = "$expect_body" ] && ok "(t1) [AC-16 AC-18] text (first line), tool calls with key argument cut at 120, bare Agent, error results, [unparsed] for bad JSON and a missing key" \
  || bad "(t1) build lines:"$'\n'"$body"
[ "$(grep -c ' ERROR ' <<<"$body")" -eq 2 ] && grep -qx '\[build 1.1\] exit 2 jq: error: Could not open file x.json' <<<"$body" && grep -qx '\[build 1.1\] failed <tool_use_error>String to replace not found in file.' <<<"$body" \
  && ok "(t1) #964 D-5 D-6: ERROR tags the two denials only; a non-zero exit shows 'exit <code>' and another tool error 'failed'" || bad "(t1) #964 error tags:"$'\n'"$(grep -E 'ERROR|exit|failed' <<<"$body")"
! grep -qE 'SECRET-THOUGHT|SUCCESS-BODY|USER-STRING-PROMPT|SIDECHAIN-TEXT|init' "$c/out" && ok "(t1) [AC-16] thinking, successful results, user prompts, sidechains and other entry types are not rendered" || bad "(t1) leaked: $(grep -E 'SECRET|SUCCESS|USER-STRING|SIDECHAIN|init' "$c/out")"
grep -qx '\[review 1.1\] waiting for its transcript (~/.claude\*/projects/\*/'"$u2"'.jsonl)' "$c/out" && grep -qx '\[review 1.1\] review says hi' "$c/out" \
  && ok "(t1) [AC-18] a transcript not on disk yet is waited for, said once, then rendered" || bad "(t1) review lines: $(grep 'review 1.1' "$c/out" | tr '\n' '|')"
[ "$(grep -c '^──── ' "$c/out")" -eq 3 ] && grep -q "^──── review 1.1 · session $u2 ────$" "$c/out" && ok "(t1) [AC-17] each new session line switches the pane with a separator naming it" || bad "(t1) separators: $(grep '^────' "$c/out" | tr '\n' '|')"
[ "$(grep -cx 'no transcript for review 1.1-retry1' "$c/out")" -eq 1 ] && ok "(t1) [AC-19] a session with no transcript when the run exits is named once" || bad "(t1) $(tail -n 4 "$c/out" | tr '\n' '|')"
[ "$sum_before" = "$(head -n 2 "$LOG" | cat "$HOME/.claude-alt/projects/-x-wt/$u1.jsonl" - | cksum)" ] && [ ! -f "$FAKE_HERDR/calls" ] \
  && ok "(t1) [AC-19] the pane wrote nothing to the transcript, the log or herdr" || bad "(t1) something was written (herdr calls: $(cat "$FAKE_HERDR/calls" 2>/dev/null))"

echo "[herdr-adapter-selftest] build: the interactive launcher (#945)"
# a git fixture: a main checkout with a subdirectory, a linked worktree, and a symlink to it under another name (D-23).
# Case directories for build and review start with b, r or e: the verb guard below is per-mode.
mkrepo() { # mkrepo <dir> — a main checkout with one commit; no global hooks or identity needed
  mkdir -p "$1/sub/dir" && git -C "$1" init -q && git -C "$1" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m init
}
G="$T/src/acme"; mkrepo "$G" && git -C "$G" worktree add -q "$T/src/acme-linked" -b linked && ln -s "$G" "$T/acme-link" && mkdir -p "$T/nogit" \
  || bad "the git fixture could not be built"
MAINP="$(cd "$G" && pwd -P)"; WTROOT="$(dirname "$MAINP")/acme-worktrees"
# shellcheck disable=SC2016  # the fixed texts, literally
BUILD_TEXT='env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:build $SS_ISSUE" --add-dir "$SS_WT"'
# shellcheck disable=SC2016
REVIEW_TEXT='env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:review $SS_PR"'
bcase() { case_dir "$1"; mkdir -p "$c/gh" "$c/tmp"; export FAKE_GH="$c/gh"; } # bcase <name> — case_dir plus a gh state and a case-local TMPDIR
in_dir() { local d="$1"; shift; ( cd "$d" && bash "$AD" "$@" ) > "$c/out" 2>&1; } # in_dir <dir> <adapter args...>
num() { local b; b="$(basename "$1" .txt)"; echo "${b#call-}"; }
argval() { awk -v a="$2" 'p == a { print; exit } { p = $0 }' "$1"; } # argval <call file> <flag>
calls_with() { grep -lx -- "$3" "$FAKE_HERDR"/call-*.txt 2>/dev/null | while read -r f; do [ "$(sed -n 1,2p "$f" | tr '\n' ' ')" = "$1 $2 " ] && echo "$f"; done; } # calls_with <verb> <sub> <argv element>
poll() { local s="$1" i=0; shift; until "$@"; do [ "$i" -lt $((s*5)) ] || return 1; sleep 0.2; i=$((i+1)); done; } # poll <secs> <cmd...>
chain() { # chain <workspace label> <an --env element of the tab> <tab label> <text> — prints what breaks the chain, nothing when it holds:
  # a tab in the workspace the label names (the id a workspace create for that label returned, or the listed one), on the
  # main checkout, unfocused; a wait for that tab's own pane; then the fixed text, alone, typed into that pane
  local tc ws p wo run
  tc="$(calls_with tab create "$2" | head -n 1)"; [ -n "$tc" ] || { echo "no tab create carries $2"; return; }
  ws="$(argval "$tc" --workspace)"
  if [[ "$ws" =~ ^w([0-9]+)$ ]]; then has_arg_pair "$FAKE_HERDR/call-${BASH_REMATCH[1]}.txt" --label "$1" || { echo "the tab is in $ws, which was not created as $1"; return; }
  else jq -e --arg l "$1" --arg w "$ws" '[.result.workspaces[] | select(.label == $l and .workspace_id == $w)] | length == 1' "$FAKE_HERDR/workspaces.json" >/dev/null 2>&1 || { echo "the tab is in $ws, not $1"; return; }; fi
  has_arg_pair "$tc" --label "$3" && has_arg_pair "$tc" --cwd "$MAINP" && grep -qx -- --no-focus "$tc" || { echo "tab create: $(tr '\n' ' ' < "$tc")"; return; }
  p="p$(num "$tc")"; wo="$(calls_with pane wait-output "$p" | head -n 1)"; run="$(calls_with pane run "$p" | head -n 1)"
  [ -n "$wo" ] && has_arg_pair "$wo" --timeout 10000 || { echo "no 10 s wait-output on $p"; return; }
  [ -n "$run" ] && [ "$(num "$wo")" -lt "$(num "$run")" ] || { echo "no pane run on $p after its wait"; return; }
  [ "$(wc -l < "$run" | tr -d ' ')" -eq 4 ] && [ "$(sed -n 4p "$run")" = "$4" ] || { echo "pane run: $(tr '\n' ' ' < "$run")"; }
}

# (b1) AC-0 AC-1 AC-2 AC-3 AC-10: three tickets from the main checkout, launched from inside a herdr pane
bcase b1; HERDR_PANE_ID=operator-pane HERDR_TAB_ID=operator-tab HERDR_WORKSPACE_ID=operator-ws TMPDIR="$c/tmp" in_dir "$G" build 101 102 103; rc=$?
[ "$rc" -eq 0 ] && ok "(b1) [AC-0] 'build 101 102 103' (four arguments) is the launcher, not the watch call, and exits 0" || bad "(b1) rc=$rc: $(tr '\n' '|' < "$c/out")"
[ "$(cut -d' ' -f1-2 "$FAKE_HERDR/calls" | tr '\n' ',')" = "$(for _ in 1 2 3; do printf 'workspace list,workspace create,tab create,pane wait-output,pane run,'; done)" ] \
  && ok "(b1) [AC-1 AC-13] per ticket: list, create, tab, wait for the shell, run" || bad "(b1) calls: $(tr '\n' '|' < "$FAKE_HERDR/calls")"
f0=$FAIL
for n in 101 102 103; do
  wc="$(calls_with workspace create "acme#$n")"
  [ -n "$wc" ] && has_arg_pair "$wc" --cwd "$MAINP" && grep -qx -- --no-focus "$wc" || bad "(b1) [AC-1] workspace create for $n: $(tr '\n' ' ' < "${wc:-/dev/null}")"
  why="$(chain "acme#$n" "SS_ISSUE=$n" build "$BUILD_TEXT")"; [ -z "$why" ] || bad "(b1) [AC-2] ticket $n: $why"
  tc="$(calls_with tab create "SS_ISSUE=$n")"
  has_arg_pair "$tc" --env "SS_WT=$WTROOT/$n" && has_arg_pair "$tc" --env "SS_ADAPTER=$AD" && ! grep -q RUN_WORKTREE_ROOT "$tc" \
    || bad "(b1) [AC-2 AC-3] ticket $n's --env: $(tr '\n' ' ' < "$tc")"
done
[ "$FAIL" -eq "$f0" ] && ok "(b1) [AC-1 AC-2 AC-3] each ticket: acme#<n> created unfocused on the main checkout, a build tab in it with SS_WT/SS_ISSUE/SS_ADAPTER, the fixed text on its own pane"
! grep -q 'operator-' "$FAKE_HERDR"/call-*.txt && [ ! -f "$FAKE_HERDR/env" ] \
  && ok "(b1) [AC-10] no call names the launching pane, tab or workspace, nor inherits their ids" || bad "(b1) [AC-10] $(grep -l 'operator-' "$FAKE_HERDR"/call-*.txt) $(cat "$FAKE_HERDR/env" 2>/dev/null)"
[ ! -f "$FAKE_HERDR/editor-code.txt" ] && [ -z "$(ls -A "$c/tmp")" ] && ok "(b1) [AC-4] RUN_WATCH_EDITOR unset: no waiter, no editor" || bad "(b1) [AC-4] $(ls -A "$c/tmp")"

# (b2) AC-0 AC-3 D-23: a subdirectory, a linked worktree and a symlinked path under another name all derive acme and its worktree root
for from in "$G/sub/dir" "$T/src/acme-linked" "$T/acme-link/sub"; do
  bcase "b2-$(basename "$from")"; in_dir "$from" build 7; rc=$?
  wc="$(calls_with workspace create 'acme#7')"; tc="$(calls_with tab create SS_ISSUE=7)"
  [ "$rc" -eq 0 ] && [ -n "$wc" ] && has_arg_pair "$wc" --cwd "$MAINP" && has_arg_pair "$tc" --env "SS_WT=$WTROOT/7" \
    && ok "(b2) [AC-0 AC-3] from ${from#"$T"/}: acme#7 on the main checkout, SS_WT=<parent>/acme-worktrees/7" || bad "(b2) from $from rc=$rc: $(tr '\n' '|' < "$FAKE_HERDR/calls" 2>/dev/null) $(cat "$c/out")"
done
bcase b2-root; RUN_WORKTREE_ROOT="$c/wts root" in_dir "$G" build 7; rc=$?; tc="$(calls_with tab create SS_ISSUE=7)"
[ "$rc" -eq 0 ] && has_arg_pair "$tc" --env "SS_WT=$c/wts root/7" && has_arg_pair "$tc" --env "RUN_WORKTREE_ROOT=$c/wts root" \
  && ok "(b2) [AC-2 AC-3] RUN_WORKTREE_ROOT set: SS_WT under it, and it is forwarded to the pane" || bad "(b2) RUN_WORKTREE_ROOT: rc=$rc $(tr '\n' ' ' < "${tc:-/dev/null}")"

# (b3) AC-5: one ticket failing does not stop the others, and is named
bcase b3; echo 'acme#102' > "$FAKE_HERDR/fail-on"; in_dir "$G" build 101 102 103; rc=$?
[ "$rc" -eq 1 ] && [ -n "$(calls_with tab create SS_ISSUE=101)" ] && [ -n "$(calls_with tab create SS_ISSUE=103)" ] && [ -z "$(calls_with tab create SS_ISSUE=102)" ] \
  && [ "$(grep -c 'acme#102: workspace create failed' "$c/out")" -eq 1 ] && [ -z "$(chain 'acme#103' SS_ISSUE=103 build "$BUILD_TEXT")" ] \
  && ok "(b3) [AC-5] 102 fails at workspace create: one line names it, 101 and 103 still open, exit 1" || bad "(b3) rc=$rc $(cat "$c/out")"
bcase b3-run; echo p3 > "$FAKE_HERDR/fail-on"; in_dir "$G" build 101 102; rc=$?   # p3: 101's pane (call 3 is its tab create)
[ "$rc" -eq 1 ] && grep -q 'acme#101: pane run failed' "$c/out" && [ -z "$(chain 'acme#102' SS_ISSUE=102 build "$BUILD_TEXT")" ] \
  && ok "(b3) [AC-5] a failure at the last call (pane run) is per ticket too" || bad "(b3-run) rc=$rc $(cat "$c/out")"
bcase b3-ok; in_dir "$G" build 101; rc=$?; [ "$rc" -eq 0 ] && ok "(b3) [AC-5] all opened: exit 0" || bad "(b3-ok) rc=$rc"

# (b4) the server is down: one line per ticket, exit 1, nothing past the first call of each
bcase b4; touch "$FAKE_HERDR/down"; RUN_WATCH_EDITOR=code TMPDIR="$c/tmp" in_dir "$G" build 101 102 103; rc=$?
[ "$rc" -eq 1 ] && [ "$(grep -c 'workspace list failed.*server_not_running' "$c/out")" -eq 3 ] && [ "$(wc -l < "$c/out" | tr -d ' ')" -eq 3 ] \
  && [ "$(sort -u "$FAKE_HERDR/calls")" = "workspace list" ] && [ -z "$(ls -A "$c/tmp")" ] \
  && ok "(b4) a stopped server: one line per ticket naming it, exit 1, no server start, no editor waiter" || bad "(b4) rc=$rc $(cat "$c/out") $(ls -A "$c/tmp")"

# (b5) AC-6: a bad ticket anywhere is a usage error before any herdr call; a ticket named twice opens once
f0=$FAIL
i=0; for args in "101 abc" "0" "01" "-3" "PROJ-1" ""; do
  i=$((i+1)); bcase "b5-$i"; # shellcheck disable=SC2086  # the argument list, split on purpose
  in_dir "$G" build $args; rc=$?
  [ "$rc" -eq 2 ] && [ ! -f "$FAKE_HERDR/calls" ] && grep -q '^usage:' "$c/out" || bad "(b5) build '$args': rc=$rc calls: $(cat "$FAKE_HERDR/calls" 2>/dev/null)"
done
[ "$FAIL" -eq "$f0" ] && ok "(b5) [AC-6] '101 abc', 0, 01, -3, a jira key under github, no ticket: exit 2 with usage, no herdr call"
bcase b5-dup; in_dir "$G" build 5 5 6 5; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c '^tab create' "$FAKE_HERDR/calls")" -eq 2 ] && [ "$(grep -c '^workspace create' "$FAKE_HERDR/calls")" -eq 2 ] \
  && ok "(b5) [AC-6 D-25] '5 5 6 5' opens 5 and 6 once each" || bad "(b5-dup) rc=$rc $(tr '\n' '|' < "$FAKE_HERDR/calls")"

# (b6) AC-13: a shell that draws nothing in time is typed into anyway, and said once
bcase b6; touch "$FAKE_HERDR/silent"; in_dir "$G" build 101; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c 'did not see the shell' "$c/out")" -eq 1 ] && [ -z "$(chain 'acme#101' SS_ISSUE=101 build "$BUILD_TEXT")" ] \
  && ok "(b6) [AC-13] no shell output within the wait: one line, then the fixed text anyway" || bad "(b6) rc=$rc $(cat "$c/out")"

# (b7) AC-0: outside a git checkout, build and review are usage errors
for sub in "build 5" "review 7"; do
  bcase "b7-${sub%% *}"; # shellcheck disable=SC2086
  ( cd "$T/nogit" && GIT_CEILING_DIRECTORIES="$T" bash "$AD" $sub ) > "$c/out" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -f "$FAKE_HERDR/calls" ] && [ ! -f "$FAKE_GH/calls" ] && grep -q 'not inside a git checkout' "$c/out" \
    && ok "(b7) [AC-0] '$sub' outside a git checkout: exit 2, nothing called" || bad "(b7) '$sub' rc=$rc $(cat "$c/out")"
done

# (b8) D-31: under jira, a key is the ticket; the config is the main checkout's, read from a linked worktree
J="$T/src/jacme"; mkrepo "$J" && git -C "$J" worktree add -q "$T/src/jacme-linked" -b linked && mkdir -p "$J/.claude" \
  && echo '{"configVersion":3,"tracker":{"type":"jira"}}' > "$J/.claude/second-shift.config.json" || bad "the jira fixture could not be built"
JMAIN="$(cd "$J" && pwd -P)"
bcase b8; in_dir "$T/src/jacme-linked" build PROJ-12; rc=$?; tc="$(calls_with tab create SS_ISSUE=PROJ-12)"
[ "$rc" -eq 0 ] && [ -n "$(calls_with workspace create 'jacme#PROJ-12')" ] && has_arg_pair "$tc" --env "SS_WT=$(dirname "$JMAIN")/jacme-worktrees/PROJ-12" \
  && ok "(b8) [AC-0 D-31] jira from a linked worktree: jacme#PROJ-12, its worktree under jacme-worktrees" || bad "(b8) rc=$rc $(cat "$c/out")"
bcase b8-num; in_dir "$T/src/jacme-linked" build 12; rc=$?
[ "$rc" -eq 2 ] && [ ! -f "$FAKE_HERDR/calls" ] && ok "(b8) [AC-6] under jira a bare number is not a ticket" || bad "(b8-num) rc=$rc"
echo '{"tracker":{"type":"jira","keyPattern":"ABC-[0-9]+"}}' > "$T/kp.json"
bcase b8-kp; SECOND_SHIFT_CONFIG="$T/kp.json" in_dir "$G" build PROJ-12; rc1=$?; SECOND_SHIFT_CONFIG="$T/kp.json" in_dir "$G" build ABC-3; rc2=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 0 ] && [ -n "$(calls_with workspace create 'acme#ABC-3')" ] && ok "(b8) SECOND_SHIFT_CONFIG wins, and its tracker.keyPattern bounds the keys as run.sh does" || bad "(b8-kp) rc=$rc1/$rc2"
echo 'not json' > "$T/nj.json"
bcase b8-nj; SECOND_SHIFT_CONFIG="$T/nj.json" in_dir "$G" build 5; rc=$?
[ "$rc" -eq 2 ] && grep -q 'is present but not JSON' "$c/out" && [ ! -f "$FAKE_HERDR/calls" ] && ok "(b8) a config that is not JSON is refused before any call" || bad "(b8-nj) rc=$rc $(cat "$c/out")"
echo '{"tracker":{"type":"jria"}}' > "$T/typo.json"
bcase b8-typo; SECOND_SHIFT_CONFIG="$T/typo.json" in_dir "$G" build 5; rc=$?
[ "$rc" -eq 2 ] && [ ! -f "$FAKE_HERDR/calls" ] && ok "(b8) a tracker.type typo is refused before any call" || bad "(b8-typo) rc=$rc"

echo "[herdr-adapter-selftest] build: the editor waiter"
# the waiter is detached: every case polls a file, never waits on a pid (bash 3.2 on CI). Each case has its own TMPDIR,
# given with the trailing slash darwin's has, and its own worktree root, so no waiter outlives its case's bound.
# (e1) AC-4 D-32 D-33: launched twice before the worktree exists, the editor opens it once, after it appears
bcase e1; export RUN_WORKTREE_ROOT="$c/wts"
# shellcheck disable=SC2016  # the inner script expands its own positional arguments
launch_e1() { RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=20 TMPDIR="$c/tmp/" bounded_run 15 "$c/out$1" bash -c 'cd "$1" && bash "$2" build 42 | cat' _ "$G" "$AD"; }
launch_e1 1; rc1=$?; launch_e1 2; rc2=$?
lock="$c/tmp/herdr-adapter-acme-42-editor.lock"
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -d "$lock" ] && [ ! -f "$FAKE_HERDR/editor-code.txt" ] && grep -q 'already waiting' "$c/out2" \
  && ok "(e1) [AC-4] the launcher returns at once (its pipe closes), the waiter holds the lock, the second launch starts no waiter" || bad "(e1) rc=$rc1/$rc2 $(cat "$c/out1" "$c/out2")"
mkdir -p "$c/wts/42"
poll 10 test -f "$FAKE_HERDR/editor-code.txt" && poll 5 test ! -d "$lock"; sleep 1.5
[ "$(tr '\n' ' ' < "$FAKE_HERDR/editor-code.txt" 2>/dev/null)" = "-n $c/wts/42 " ] && [ ! -d "$lock" ] \
  && ok "(e1) [AC-4] the worktree appears: 'code -n <worktree>' exactly once, and the lock is released" || bad "(e1) editor: $(cat "$FAKE_HERDR/editor-code.txt" 2>/dev/null)"
unset RUN_WORKTREE_ROOT
# (e2) AC-4: the worktree never appears — one give-up line in the per-ticket log, no editor
bcase e2; RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=cursor SS_EDITOR_WAIT_SECS=1 TMPDIR="$c/tmp/" in_dir "$G" build 42; rc=$?
glog="$c/tmp/herdr-adapter-acme-42-editor.log"
poll 10 test -f "$glog" && poll 5 test ! -d "$c/tmp/herdr-adapter-acme-42-editor.lock"
[ "$rc" -eq 0 ] && [ "$(wc -l < "$glog" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q "$c/wts/42 never appeared" "$glog" && [ ! -f "$FAKE_HERDR/editor-cursor.txt" ] \
  && ok "(e2) [AC-4] the bound passes: one line to herdr-adapter-acme-42-editor.log, no editor, the lock released" || bad "(e2) rc=$rc log: $(cat "$glog" 2>/dev/null)"
# (e3) a lock whose waiter is dead does not block a new one
bcase e3; mkdir -p "$c/wts/42" "$c/tmp/herdr-adapter-acme-42-editor.lock"; bash -c 'exit 0' & dead=$!; wait "$dead"
echo "$dead" > "$c/tmp/herdr-adapter-acme-42-editor.lock/pid"
RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=5 TMPDIR="$c/tmp" in_dir "$G" build 42; rc=$?
poll 10 test -f "$FAKE_HERDR/editor-code.txt"
[ "$rc" -eq 0 ] && [ "$(tr '\n' ' ' < "$FAKE_HERDR/editor-code.txt" 2>/dev/null)" = "-n $c/wts/42 " ] && ok "(e3) a stale lock (its waiter gone) is taken over" || bad "(e3) rc=$rc $(cat "$c/out")"
# (e4) any other editor value opens nothing and says so
bcase e4; RUN_WATCH_EDITOR=vim TMPDIR="$c/tmp" in_dir "$G" build 42; rc=$?
[ "$rc" -eq 0 ] && grep -q 'not code or cursor' "$c/out" && [ -z "$(ls -A "$c/tmp")" ] && ok "(e4) RUN_WATCH_EDITOR=vim: no waiter, said once" || bad "(e4) rc=$rc $(cat "$c/out")"

# (e5) a ticket that fails to open starts no waiter; the others each start one
bcase e5; echo 'acme#102' > "$FAKE_HERDR/fail-on"
RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=5 TMPDIR="$c/tmp" in_dir "$G" build 101 102 103; rc=$?
locks="$(for l in "$c/tmp"/*.lock; do [ -d "$l" ] && printf '%s ' "$(basename "$l")"; done)"
mkdir -p "$c/wts/101" "$c/wts/103"; poll 10 test ! -d "$c/tmp/herdr-adapter-acme-101-editor.lock" && poll 10 test ! -d "$c/tmp/herdr-adapter-acme-103-editor.lock"
[ "$rc" -eq 1 ] && [ "$locks" = "herdr-adapter-acme-101-editor.lock herdr-adapter-acme-103-editor.lock " ] \
  && ok "(e5) 102 fails to open: waiters for 101 and 103 only" || bad "(e5) rc=$rc locks: $locks"
# (e6) a wait bound that is not a whole number of seconds is said, and 300 is used
bcase e6; mkdir -p "$c/wts/42"; RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=5m TMPDIR="$c/tmp" in_dir "$G" build 42; rc=$?
poll 10 test -f "$FAKE_HERDR/editor-code.txt"
[ "$rc" -eq 0 ] && grep -q "SS_EDITOR_WAIT_SECS='5m' is not a whole number of seconds; waiting 300" "$c/out" && [ -f "$FAKE_HERDR/editor-code.txt" ] \
  && ok "(e6) SS_EDITOR_WAIT_SECS=5m: said once, the waiter still opens the worktree" || bad "(e6) rc=$rc $(cat "$c/out")"
# (e7) an editor that fails is one line in the per-ticket log, and the lock is released
bcase e7; mkdir -p "$c/wts/42"; touch "$FAKE_HERDR/editor-fails"
RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=5 TMPDIR="$c/tmp" in_dir "$G" build 42; rc=$?
glog="$c/tmp/herdr-adapter-acme-42-editor.log"
poll 10 test -f "$glog" && poll 5 test ! -d "$c/tmp/herdr-adapter-acme-42-editor.lock"
[ "$rc" -eq 0 ] && [ "$(wc -l < "$glog" 2>/dev/null | tr -d ' ')" = 1 ] && grep -qF "code -n $c/wts/42 failed" "$glog" && [ ! -d "$c/tmp/herdr-adapter-acme-42-editor.lock" ] \
  && ok "(e7) the editor fails: one line to the per-ticket log, the lock released" || bad "(e7) rc=$rc log: $(cat "$glog" 2>/dev/null)"
# (e8) no perl to detach with: no waiter, no lock left behind, said once; the build tab still opens
bcase e8; RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code TMPDIR="$c/tmp" PATH="$T/noperl" in_dir "$G" build 42; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c 'no perl to detach the editor waiter' "$c/out")" -eq 1 ] && [ -z "$(ls -A "$c/tmp")" ] && [ -z "$(chain 'acme#42' SS_ISSUE=42 build "$BUILD_TEXT")" ] \
  && ok "(e8) no perl: the tab opens, no waiter, no lock, said once" || bad "(e8) rc=$rc $(cat "$c/out") $(ls -A "$c/tmp")"
# (e9) a lock with no pid yet is being taken by another launch: left alone, no second waiter
bcase e9; mkdir -p "$c/wts/42" "$c/tmp/herdr-adapter-acme-42-editor.lock"
RUN_WORKTREE_ROOT="$c/wts" RUN_WATCH_EDITOR=code SS_EDITOR_WAIT_SECS=5 TMPDIR="$c/tmp" in_dir "$G" build 42; rc=$?
poll 3 test -f "$FAKE_HERDR/editor-code.txt"
[ "$rc" -eq 0 ] && grep -q 'already waiting' "$c/out" && [ ! -f "$FAKE_HERDR/editor-code.txt" ] && [ -d "$c/tmp/herdr-adapter-acme-42-editor.lock" ] \
  && ok "(e9) a lock with no pid yet is not taken over" || bad "(e9) rc=$rc $(cat "$c/out")"

echo "[herdr-adapter-selftest] review"
# (r1) AC-7: github — the PR's one closing reference names the workspace; a review tab with SS_PR, the fixed text
bcase r1; echo '{"closingIssuesReferences":[{"id":"I_1","number":42,"url":"u"}]}' > "$FAKE_GH/closingIssuesReferences.json"
HERDR_PANE_ID=operator-pane HERDR_TAB_ID=operator-tab HERDR_WORKSPACE_ID=operator-ws in_dir "$G/sub" review 7; rc=$?; why="$(chain 'acme#42' SS_PR=7 review "$REVIEW_TEXT")"
[ "$rc" -eq 0 ] && [ -z "$why" ] && [ "$(cat "$FAKE_GH/calls")" = "pr view 7 --json closingIssuesReferences" ] && ! grep -q 'operator-' "$FAKE_HERDR"/call-*.txt && [ ! -f "$FAKE_HERDR/env" ] \
  && [ "$(sed -n '/^--env$/{n;p;}' "$(calls_with tab create SS_PR=7)")" = SS_PR=7 ] \
  && ok "(r1) [AC-7 AC-10] closes #42: acme#42 created, a review tab on the main checkout, SS_PR its only --env, the fixed text" || bad "(r1) rc=$rc $why $(cat "$c/out")"
# (r2) AC-7: the ticket's workspace exists (its build's) — reused, a new review tab
bcase r2; echo '{"closingIssuesReferences":[{"number":42}]}' > "$FAKE_GH/closingIssuesReferences.json"
printf '%s' '{"result":{"type":"workspace_list","workspaces":[{"workspace_id":"w-other","label":"acme#420"},{"workspace_id":"w-old","label":"acme#42"}]}}' > "$FAKE_HERDR/workspaces.json"
in_dir "$G" review 7; rc=$?; why="$(chain 'acme#42' SS_PR=7 review "$REVIEW_TEXT")"
[ "$rc" -eq 0 ] && [ -z "$why" ] && ! grep -q '^workspace create' "$FAKE_HERDR/calls" && has_arg_pair "$(calls_with tab create SS_PR=7)" --workspace w-old \
  && ok "(r2) [AC-7] the existing acme#42 gets the review tab" || bad "(r2) rc=$rc $why"
# (r3) AC-8: no closing reference, two, or gh failing — exit 1, the message names what was found, no herdr call
i=0; for refs in '[]' '[{"number":3},{"number":4}]' ''; do
  i=$((i+1)); bcase "r3-$i"; [ -z "$refs" ] || echo "{\"closingIssuesReferences\":$refs}" > "$FAKE_GH/closingIssuesReferences.json"
  in_dir "$G" review 7; rc=$?
  case "$refs" in '[]') want='closes no ticket' ;; '') want='gh pr view 7 failed' ;; *) want='closes 2 tickets (3 4)' ;; esac
  [ "$rc" -eq 1 ] && grep -qF "$want" "$c/out" && [ ! -f "$FAKE_HERDR/calls" ] && ok "(r3) [AC-8] closing refs '${refs:-gh fails}': exit 1, '$want', no herdr call" || bad "(r3) '$refs' rc=$rc $(cat "$c/out")"
done
# (r4) a review argument that is not one positive PR number is a usage error before gh or herdr
f0=$FAIL
i=0; for args in "abc" "" "7 8" "0"; do
  i=$((i+1)); bcase "r4-$i"; # shellcheck disable=SC2086
  in_dir "$G" review $args; rc=$?
  [ "$rc" -eq 2 ] && [ ! -f "$FAKE_HERDR/calls" ] && [ ! -f "$FAKE_GH/calls" ] || bad "(r4) review '$args': rc=$rc"
done
[ "$FAIL" -eq "$f0" ] && ok "(r4) review 'abc', none, '7 8', 0: exit 2, nothing called"
# (r5) AC-7 D-30 D-31: jira — `Closes [<KEY>]` under the Jira Items heading only, any heading depth, case-insensitive
bcase r5; jq -n --arg b $'built-by: x\n\nCloses [PROJ-99] in prose\n\n### Jira Items\n- closes [PROJ-12]\n\n## Other\nCloses [PROJ-77]' '{body: $b}' > "$FAKE_GH/body.json"
in_dir "$T/src/jacme-linked" review 7; rc=$?; MAINP_SAVE="$MAINP"; MAINP="$JMAIN"; why="$(chain 'jacme#PROJ-12' SS_PR=7 review "$REVIEW_TEXT")"; MAINP="$MAINP_SAVE"
[ "$rc" -eq 0 ] && [ -z "$why" ] && [ "$(cat "$FAKE_GH/calls")" = "pr view 7 --json body" ] \
  && ok "(r5) [AC-7 D-31] jira: the one key under ### Jira Items names jacme#PROJ-12 (prose and other sections ignored)" || bad "(r5) rc=$rc $why $(cat "$c/out")"
i=0; for b in $'### Jira Items\n(nothing)\n### Notes\nCloses [PROJ-1]' $'#### jira items\nCloses [PROJ-1]\nCloses [PROJ-2]'; do
  i=$((i+1)); bcase "r5-bad-$i"; jq -n --arg b "$b" '{body: $b}' > "$FAKE_GH/body.json"; in_dir "$T/src/jacme-linked" review 7; rc=$?
  [ "$rc" -eq 1 ] && [ ! -f "$FAKE_HERDR/calls" ] && grep -qE 'closes (no ticket|2 tickets \(PROJ-1 PROJ-2\))' "$c/out" \
    && ok "(r5) [AC-8] jira: $(grep -oE 'closes (no ticket|2 tickets)' "$c/out"), exit 1, no herdr call" || bad "(r5-bad) rc=$rc $(cat "$c/out")"
done

# (r6) jira: a closed key tracker.keyPattern does not admit opens nothing
bcase r6; jq -n --arg b $'### Jira Items\nCloses [PROJ-12]' '{body: $b}' > "$FAKE_GH/body.json"
SECOND_SHIFT_CONFIG="$T/kp.json" in_dir "$G" review 7; rc=$?
[ "$rc" -eq 1 ] && grep -qF "closes 'PROJ-12', which is not a jira ticket" "$c/out" && [ ! -f "$FAKE_HERDR/calls" ] \
  && ok "(r6) jira: a closed key outside tracker.keyPattern: exit 1, named, no herdr call" || bad "(r6) rc=$rc $(cat "$c/out")"

echo "[herdr-adapter-selftest] what the adapter never calls"
# grep reads the call logs itself: an unreadable log is rc 2, never a vacuous "no forbidden call"
# AC-13 (#939): across every case, none of the verbs that would let the adapter own a worktree, the server or a session
forbidden='^(worktree (create|remove)|server|pane (send-text|send-keys)|agent (start|prompt)|integration|workspace close)( |$)'
grep -qE "$forbidden" "$T"/*/herdr/calls; n1=$?
if [ "$n1" -eq 1 ]; then ok "(n1) [AC-13] no worktree, server, send-text/keys, agent, integration or workspace close call in any case"
else bad "(n1) [AC-13] rc=$n1 — a forbidden herdr verb was called, or a call log could not be read: $(grep -hE "$forbidden" "$T"/*/herdr/calls 2>&1 | head -n 3 | tr '\n' '|')"; fi
# AC-9 (#945): build and review mode go further — an allow-list (report-agent is legal only in watch mode), and every
# pane run carries one of the two fixed texts and nothing else
allowed='^(workspace (list|create)|tab create|pane (wait-output|run))( |$)'
grep -vqE "$allowed" "$T"/[bre]*/herdr/calls; n2=$?
if [ "$n2" -eq 1 ]; then ok "(n2) [AC-9] build and review call only workspace list/create, tab create, pane wait-output and pane run"
else bad "(n2) [AC-9] rc=$n2 — a verb off the allow-list, or an unreadable call log: $(grep -hvE "$allowed" "$T"/[bre]*/herdr/calls 2>&1 | head -n 3 | tr '\n' '|')"; fi
odd=""; for f in "$T"/[bre]*/herdr/call-*.txt; do
  [ "$(sed -n 1,2p "$f" | tr '\n' ' ')" = "pane run " ] || continue
  { [ "$(wc -l < "$f" | tr -d ' ')" -eq 4 ] && { [ "$(sed -n 4p "$f")" = "$BUILD_TEXT" ] || [ "$(sed -n 4p "$f")" = "$REVIEW_TEXT" ]; }; } || odd="$odd $f"
done
[ -z "$odd" ] && ok "(n2) [AC-2 AC-7 AC-9] every pane run in build and review mode is one of the two fixed texts, interpolating nothing" || bad "(n2) pane runs off the fixed texts:$odd"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
