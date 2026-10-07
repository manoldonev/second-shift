#!/usr/bin/env bash
# herdr-adapter-selftest.sh — drives herdr-adapter.sh (the bundled RUN_WATCH_CMD, #939) against a fake `herdr` and a
# fake editor: the watch call's herdr calls and what they carry, the log pane's sidebar states, and the transcript pane's
# rendering. Model-free and herdr-free; what only a real herdr shows is the operator's post-merge trial.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AD="$SCRIPT_DIR/herdr-adapter.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/herdr-adapter-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
for _v in $(compgen -e HERDR_) RUN_WATCH_EDITOR SS_LOG SS_ISSUE SS_ADAPTER; do unset "$_v"; done

# ---- fakes: herdr answers the JSON shapes of herdr 0.9.3 and logs every call, one argv element per line ----
mkdir -p "$T/bin"
cat > "$T/bin/herdr" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_HERDR"; n=$(( $(cat "$S/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/n"
printf '%s\n' "$@" > "$S/call-$n.txt"; echo "$*" >> "$S/calls"
[ -f "$S/down" ] && { echo 'error: server_not_running' >&2; exit 1; }
case "$1 ${2:-}" in
  "workspace list")   if [ -f "$S/workspaces.json" ]; then cat "$S/workspaces.json"; else echo '{"id":"1","result":{"type":"workspace_list","workspaces":[]}}'; fi ;;
  "workspace create") echo '{"id":"1","result":{"type":"workspace_created","workspace":{"workspace_id":"w9","label":"x"},"tab":{"tab_id":"w9:1"},"root_pane":{"pane_id":"w9-1"}}}' ;;
  "tab create")       echo '{"id":"1","result":{"type":"tab_created","tab":{"tab_id":"t5"},"root_pane":{"pane_id":"p-root"}}}' ;;
  "pane split")       echo '{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"p-below"}}}' ;;
  "pane run"|"pane report-agent") echo '{"id":"1","result":{"type":"ok"}}' ;;
  *) echo "fake herdr: unhandled $*" >&2; exit 1 ;;
esac
EOF
# shellcheck disable=SC2016  # the fake's own text: it expands when the fake runs
for e in code cursor; do printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$FAKE_HERDR/editor-%s.txt"\n' "$e" > "$T/bin/$e"; done
chmod +x "$T/bin/"*
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
[ -n "$tc" ] && has_arg_pair "$tc" --workspace w9 && has_arg_pair "$tc" --env "SS_LOG=$LOG" && has_arg_pair "$tc" --env SS_ISSUE=42 \
  && has_arg_pair "$tc" --env "SS_ADAPTER=$AD" && grep -qx -- --no-focus "$tc" \
  && ok "(o1) [AC-7 AC-8] a tab in the created workspace, its inputs as --env, the log path one argv element" || bad "(o1) tab create: $(tr '\n' ' ' < "${tc:-/dev/null}")"
runs="$(grep -l '^run$' "$FAKE_HERDR"/call-*.txt)"
# shellcheck disable=SC2016  # the fixed text, literally
[ "$(for f in $runs; do sed -n 3,4p "$f" | tr '\n' ' '; echo; done | sort | tr '\n' '|')" = 'p-below bash "$SS_ADAPTER" transcript |p-root bash "$SS_ADAPTER" watch |' ] \
  && ok "(o1) [AC-8 AC-15] each pane runs fixed text that interpolates nothing, on the ids the calls returned" || bad "(o1) pane run: $(for f in $runs; do tr '\n' ' ' < "$f"; echo '|'; done)"
[ "$(grep -lF "it's" "$FAKE_HERDR"/call-*.txt | wc -l | tr -d ' ')" -eq 2 ] && ok "(o1) the log path appears only in the two --env lists (tab create, pane split)" || bad "(o1) the log path is in: $(grep -lF "it's" "$FAKE_HERDR"/call-*.txt | tr '\n' ' ')"
sc="$(call_of pane split)"
[ -n "$sc" ] && [ "$(sed -n 3p "$sc")" = p-root ] && has_arg_pair "$sc" --direction down && has_arg_pair "$sc" --ratio 0.35 \
  && has_arg_pair "$sc" --env "SS_LOG=$LOG" && has_arg_pair "$sc" --env SS_ISSUE=42 && has_arg_pair "$sc" --env "SS_ADAPTER=$AD" && grep -qx -- --no-focus "$sc" \
  && ok "(o1) [AC-15 D-24] the transcript pane is split below the root with the larger share, inputs via --env" || bad "(o1) pane split: $(tr '\n' ' ' < "${sc:-/dev/null}")"
! grep -q 'operator-' "$FAKE_HERDR"/call-*.txt && ok "(o1) [AC-21] launched from a herdr pane, no call names that pane, tab or workspace" || bad "(o1) [AC-21] $(grep -l 'operator-' "$FAKE_HERDR"/call-*.txt)"
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
reports | tail -n 1 | grep -q 'state blocked --message exited rc=143 with no terminal line$' && ok "(w3) [AC-9] no terminal line: blocked with the exit code" || bad "(w3) reports: $(reports | tr '\n' '|')"
# (w4) live: the pane follows lines written after it started, a line written in two halves included
case_dir w4; printf '%s\n' '2026-10-07T00:00:01Z [run] run x' > "$LOG"
( sleep 1; printf '%s\n' '2026-10-07T00:00:02Z [run] round 1 of 1' >> "$LOG"; printf 'terminal: approv' >> "$LOG"; sleep 1; printf 'ed\n2026-10-07T00:00:03Z [run] detached run exited rc=0\n' >> "$LOG" ) &
HERDR_PANE_ID=p-root SS_LOG="$LOG" SS_ISSUE=42 bounded_run 20 "$c/out" bash "$AD" watch; rc=$?; wait
[ "$rc" -eq 0 ] && reports | grep -q 'state working' && reports | grep -q 'state idle --message approved$' && ok "(w4) a live log is followed, a split line read whole, to its exit" || bad "(w4) rc=$rc reports: $(reports | tr '\n' '|')"
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
[build 1.1] ERROR boom happened
[build 1.1] [unparsed]
[build 1.1] [unparsed]"
[ "$body" = "$expect_body" ] && ok "(t1) [AC-16 AC-18] text (first line), tool calls with key argument cut at 120, bare Agent, an error result, [unparsed] for bad JSON and a missing key" \
  || bad "(t1) build lines:"$'\n'"$body"
! grep -qE 'SECRET-THOUGHT|SUCCESS-BODY|USER-STRING-PROMPT|SIDECHAIN-TEXT|init' "$c/out" && ok "(t1) [AC-16] thinking, successful results, user prompts, sidechains and other entry types are not rendered" || bad "(t1) leaked: $(grep -E 'SECRET|SUCCESS|USER-STRING|SIDECHAIN|init' "$c/out")"
grep -qx '\[review 1.1\] waiting for its transcript (~/.claude\*/projects/\*/'"$u2"'.jsonl)' "$c/out" && grep -qx '\[review 1.1\] review says hi' "$c/out" \
  && ok "(t1) [AC-18] a transcript not on disk yet is waited for, said once, then rendered" || bad "(t1) review lines: $(grep 'review 1.1' "$c/out" | tr '\n' '|')"
[ "$(grep -c '^──── ' "$c/out")" -eq 3 ] && grep -q "^──── review 1.1 · session $u2 ────$" "$c/out" && ok "(t1) [AC-17] each new session line switches the pane with a separator naming it" || bad "(t1) separators: $(grep '^────' "$c/out" | tr '\n' '|')"
[ "$(grep -cx 'no transcript for review 1.1-retry1' "$c/out")" -eq 1 ] && ok "(t1) [AC-19] a session with no transcript when the run exits is named once" || bad "(t1) $(tail -n 4 "$c/out" | tr '\n' '|')"
[ "$sum_before" = "$(head -n 2 "$LOG" | cat "$HOME/.claude-alt/projects/-x-wt/$u1.jsonl" - | cksum)" ] && [ ! -f "$FAKE_HERDR/calls" ] \
  && ok "(t1) [AC-19] the pane wrote nothing to the transcript, the log or herdr" || bad "(t1) something was written (herdr calls: $(cat "$FAKE_HERDR/calls" 2>/dev/null))"

echo "[herdr-adapter-selftest] what the adapter never calls"
# AC-13: across every case above, none of the verbs that would let a watcher own a worktree, the server or a session
if cat "$T"/*/herdr/calls 2>/dev/null | grep -qE '^(worktree (create|remove)|server|pane (send-text|send-keys)|agent (start|prompt)|integration|workspace close)( |$)'; then
  bad "(n1) [AC-13] a forbidden herdr verb was called: $(cat "$T"/*/herdr/calls | grep -E '^(worktree|server|pane send|agent|integration|workspace close)' | head -n 3 | tr '\n' '|')"
else ok "(n1) [AC-13] no worktree, server, send-text/keys, agent, integration or workspace close call in any case"; fi

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
