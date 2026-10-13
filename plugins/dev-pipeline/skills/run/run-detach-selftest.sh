#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-detach-selftest.sh — run.sh scenario slice: usage refusals, --detach, the watch call, detached
# signals.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-detach-selftest] usage refusals, --detach, the watch call, detached signals"

# ---- rows: cases keyed to the contract inventory (strategy repo, run-sh-contract-inventory-2026-09-22.md).
#      Each case names the row it discriminates; a row whose behavior is reverted turns its case red.

# A2 A8 A10: usage refusals with their own slugs
fixture ra; OUT="$( cd "$d/main" && bash "$RUN" 42 43 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect usage-unexpected-argument "[A2] a second positional argument is refused, never silently taken as the ticket"; [ "$RC" -eq 2 ] && ok "[A2] exit 2" || bad "[A2] exit $RC"
OUT="$( cd "$d/main" && bash "$RUN" 42 --review-model "" 2>&1 )"; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-empty-review-model "[A8] an empty --review-model has its own slug"
OUT="$( cd "$d/main" && bash "$RUN" 42 --record /tmp/x.md 2>&1 )"; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-unknown-option "[A15] --record is not a flag: the receipt lives at its one conventional path"
OUT="$( cd "$d/main" && bash "$RUN" 42 --max-continuations 3 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-max-continuations "[A10] the retired --max-continuations is named, not 'unknown option'"; [ "$RC" -eq 2 ] && ok "[A10] exit 2" || bad "[A10] exit $RC"

# A18: --detach with an uncreatable log dir refuses before detaching
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans","pipelineStateDir":"blocker/state"}}' fixture rb; : > "$d/main/blocker"
run_case "$d" --detach; expect env-detach-log-dir "[A18] --detach cannot create its log dir"; [ "$RC" -eq 2 ] && ok "[A18] exit 2" || bad "[A18] exit $RC"

# A17: --detach with no perl on PATH
mkdir -p "$T/noperl"; for b in /bin/* /usr/bin/*; do case "$(basename "$b")" in perl*) ;; *) ln -sf "$b" "$T/noperl/$(basename "$b")" ;; esac; done
for tool in git jq curl; do p="$(command -v "$tool")"; [ -n "$p" ] && ln -sf "$p" "$T/noperl/$tool"; done
fixture rc1; OUT="$( cd "$d/main" && PATH="$T/noperl:$T/bin" bash "$RUN" 42 --detach 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
if PATH="$T/noperl:$T/bin" command -v perl >/dev/null 2>&1; then ok "[A17] (skipped: perl still resolvable on the stripped PATH)"; else expect env-detach-perl "[A17] --detach without perl is refused"; fi

# A16: --detach runs to its terminal under setsid; the log's last line carries the exit code
fixture rc2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --detach
[ "$RC" -eq 0 ] && grep -q 'detached: pid ' <<<"$OUT" && ok "[A16] --detach prints pid and log, exits 0" || bad "[A16] detach rc=$RC: $(tail -n 2 <<<"$OUT" | tr '\n' '|')"
dlog="$(sed -n 's/.*detached: pid [0-9]* · log \([^ ]*\) .*/\1/p' <<<"$OUT")"
for _ in $(seq 1 120); do grep -q 'detached run exited rc=' "$dlog" 2>/dev/null && break; sleep 0.5; done
grep -q 'detached run exited rc=0$' "$dlog" 2>/dev/null && grep -q '^terminal: approved$' "$dlog" && ok "[A16] the detached run reached approved and the log's last line carries rc=0" || bad "[A16] detached log: $(tail -n 3 "$dlog" 2>/dev/null | tr '\n' '|')"
[ "$(grep -c 'watch:' "$dlog" 2>/dev/null)" -eq 1 ] && grep -q ' \[run\] watch: off (RUN_WATCH_CMD is unset)$' "$dlog" && ok "(#939 AC-3) an unwatched detached run says 'watch: off', once" || bad "(#939 AC-3) watch lines: $(grep 'watch:' "$dlog" | tr '\n' '|')"

# ---- #939: every session is named and findable; one bounded watch call per detached launch; the scrub; a detached run's signals ----
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
arg_after() { awk -v f="$2" 'p == f { print; exit } { p = $0 }' "$1"; }   # arg_after <args file> <flag>
watch_lines() { grep -c ' \[run\] watch: ' <<<"$OUT"; }
# (wa1) a run that looks detached (RUN_DETACHED_LOG is how the detach parent says so) and is watched, launched from a herdr
# pane: two rounds and a review re-spawn make the worktree ready again, and every variable the watch reads is set — the
# lane check below goes red if one of them reaches it
# shellcheck disable=SC2016  # the check line expands in the lane, not here
fixture wa1 '- test -z "${HERDR_PANE_ID:-}${HERDR_SOCKET_PATH:-}${HERDR_ZZ_UNNAMED:-}${RUN_WATCH_CMD:-}${RUN_WATCH_EDITOR:-}${RUN_DETACHED_LOG:-}"'
printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-wrong-sha\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo started > "$d/detached.log"
HERDR_PANE_ID=op-pane HERDR_TAB_ID=op-tab HERDR_WORKSPACE_ID=op-ws HERDR_SOCKET_PATH="$d/herdr.sock" HERDR_ZZ_UNNAMED=leak RUN_WATCH_EDITOR=code \
  RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"
expect approved "(wa1) a watched run: needs-work, a review re-spawn, then approve"
[ "$(grep -c . "$FAKE_GH/watch-calls" 2>/dev/null)" = 1 ] && ok "(wa1) [AC-4] the watch command is called once per launch, though the worktree was made ready twice" || bad "(wa1) [AC-4] watch calls: $(grep -c . "$FAKE_GH/watch-calls" 2>/dev/null)"
[ "$(tr '\n' ' ' < "$FAKE_GH/watch-args" 2>/dev/null)" = "42 main $d/detached.log $d/wt/42 " ] && [ "$(cat "$FAKE_GH/watch-cwd" 2>/dev/null)" = "$(cd "$d/main" && pwd -P)" ] \
  && ok "(wa1) [AC-4] args <issue> <repo> <detach-log> <worktree>, run from the main checkout" || bad "(wa1) [AC-4] args: $(tr '\n' ' ' < "$FAKE_GH/watch-args" 2>/dev/null) cwd: $(cat "$FAKE_GH/watch-cwd" 2>/dev/null)"
read -r wpid wpgid < "$FAKE_GH/watch-pgid" 2>/dev/null
[ -n "${wpid:-}" ] && [ "$wpid" = "${wpgid:-}" ] && ok "(wa1) [AC-4 D-26] the call leads its own process group" || bad "(wa1) [AC-4] pid/pgid: ${wpid:-?}/${wpgid:-?}"
[ "$(tr '\n' ' ' < "$FAKE_GH/watch-env")" = "HERDR_SOCKET_PATH=$d/herdr.sock HERDR_ZZ_UNNAMED=leak " ] \
  && ok "(wa1) [AC-21] the call keeps herdr's server location and drops the launching pane, tab and workspace ids" || bad "(wa1) [AC-21] watch env: $(tr '\n' ' ' < "$FAKE_GH/watch-env")"
grep -qx WATCH-STDOUT "$(SD)/watch.out" && grep -qx WATCH-STDERR "$(SD)/watch.out" && ! grep -q 'WATCH-STD' <<<"$OUT" \
  && ok "(wa1) [AC-4] the call's stdout and stderr go to its file in the state dir, never the run's log" || bad "(wa1) [AC-4] watch.out: $(tr '\n' '|' < "$(SD)/watch.out" 2>/dev/null)"
[ "$(watch_lines)" -eq 1 ] && grep -q " \[run\] watch: $T/bin/watch-fake started the watch (output: " <<<"$OUT" && ok "(wa1) one 'watch:' line" || bad "(wa1) watch lines: $(grep 'watch:' <<<"$OUT" | tr '\n' '|')"
leak="$(grep -hE '^(HERDR_|RUN_WATCH|RUN_DETACHED_LOG)' "$FAKE_GH"/env-*.txt)"
[ "$(cat "$FAKE_GH/calls")" = 5 ] && [ -z "$leak" ] && ok "(wa1) [AC-12] no session got a HERDR_*, RUN_WATCH* or RUN_DETACHED_LOG variable, an unnamed HERDR_ZZ_UNNAMED included" || bad "(wa1) [AC-12] leaked: $(tr '\n' ' ' <<<"$leak")"
names="$(for n in 1 2 3 4 5; do arg_after "$FAKE_GH/args-$n.txt" -n; done | tr '\n' ' ')"
[ "$names" = "42-build-1-1 42-review-1-1 42-build-2-2 42-review-2-2 42-review-2-2-retry1 " ] && ok "(wa1) [AC-1] each session is named <issue>-<role>-<attempt id>, the id sanitized" || bad "(wa1) [AC-1] names: $names"
sids="$(for n in 1 2 3 4 5; do arg_after "$FAKE_GH/args-$n.txt" --session-id; done)"; asid="$(arg_after "$T/rc2/gh/args-1.txt" --session-id)"
[ "$(grep -cxE "$UUID_RE" <<<"$sids")" -eq 5 ] && [ "$(sort -u <<<"$sids" | grep -c .)" -eq 5 ] && grep -qxE "$UUID_RE" <<<"$asid" && ! grep -qxF "$asid" <<<"$sids" \
  && ok "(wa1) [AC-1] each session gets a fresh lowercase v4 --session-id, never reused within or across launches" || bad "(wa1) [AC-1] session ids: $(tr '\n' ' ' <<<"$sids") / (rc2): $asid"
s1="$(sed -n 1p <<<"$sids")"; s5="$(sed -n 5p <<<"$sids")"
grep -qF " [run] session: build 1.1 $s1 ~/.claude*/projects/*/$s1.jsonl" <<<"$OUT" && grep -qF " [run] session: review 2.2-retry1 $s5 ~/.claude*/projects/*/$s5.jsonl" <<<"$OUT" \
  && [ "$(grep -c ' \[run\] session: ' <<<"$OUT")" -eq 5 ] && ok "(wa1) [AC-2] one session line per spawn: role, attempt id, uuid, transcript glob" || bad "(wa1) [AC-2] $(grep 'session:' <<<"$OUT" | tr '\n' '|')"
# (wa2, wa4) AC-5: a foreground run is never watched; a run that ends before its worktree is ready calls nothing
fixture wa2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_WATCH_CMD="$T/bin/watch-fake" run_case "$d"; expect approved "(wa2) a foreground run with RUN_WATCH_CMD set"
[ ! -f "$FAKE_GH/watch-calls" ] && [ "$(watch_lines)" -eq 1 ] && grep -q ' \[run\] watch: skipped for a foreground run' <<<"$OUT" && ok "(wa2) [AC-5] nothing invoked; the log says the watch was skipped" || bad "(wa2) [AC-5] calls: $(cat "$FAKE_GH/watch-calls" 2>/dev/null) lines: $(grep 'watch:' <<<"$OUT")"
fixture wa4; echo CLOSED > "$FAKE_GH/state"; RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"; expect env-ticket-closed "(wa4) a watched run refused in preflight"
[ ! -f "$FAKE_GH/watch-calls" ] && [ "$(watch_lines)" -eq 0 ] && ok "(wa4) [AC-5] a refusal before the worktree: no call" || bad "(wa4) [AC-5] watch was called"
# (wb1-wb3) AC-6: a watch that fails, is missing or hangs changes nothing but its one line
wb() { # wb <case> <cmd> <FAKE_WATCH> <line regex> — the same run as (a); its terminal, exit, run block and comments carry no watch
  fixture "$1"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; local s0; s0=$(date +%s)
  FAKE_WATCH="$3" RUN_WATCH_CMD="$2" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"; WB_EL=$(( $(date +%s) - s0 ))
  expect approved "($1) [AC-6] a watch that is '$3' leaves the outcome alone"
  [ "$RC" -eq 0 ] && [ "$(watch_lines)" -eq 1 ] && grep -qE " \[run\] watch: FAILED — $4" <<<"$OUT" && ok "($1) [AC-6] exit 0 and exactly one 'watch:' failure line" || bad "($1) [AC-6] rc=$RC watch lines: $(grep 'watch:' <<<"$OUT" | tr '\n' '|')"
  ! grep -qiE 'watch|herdr' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" && grep -q '| approved |' "$FAKE_GH/pr-body.md" && ok "($1) [AC-6 AC-14] the run block and the closing comment carry nothing of the watch" || bad "($1) [AC-6] $(grep -iE 'watch|herdr' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" | head -n 2)"
}
wb wb1 "$T/bin/watch-fake" fail "$T/bin/watch-fake exited rc=3 "
wb wb2 /nonexistent/watch ok "'/nonexistent/watch' is not an executable"
wb wb3 "$T/bin/watch-fake" hang "$T/bin/watch-fake ran past its 10s bound and its process group was killed"
[ "$WB_EL" -lt 40 ] && ok "(wb3) [AC-4] the 10 s bound is a bound (${WB_EL}s for the whole run)" || bad "(wb3) [AC-4] the run took ${WB_EL}s"
sleep 0.5; if pgrep -f 'sleep 939[12]' >/dev/null 2>&1; then bad "(wb3) [AC-4] a descendant of the hung call survived its group kill"; pkill -KILL -f 'sleep 939[12]'; else ok "(wb3) [AC-4] the hung call's whole group, a TERM-ignoring grandchild included, is gone"; fi
# (wb4) AC-4: while the call runs, the run's TERM trap reaps its whole group
fixture wb4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && FAKE_WATCH=hang RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" exec bash "$RUN" 42 > "$d/wb4.log" 2>&1 ) & rp=$!
for _ in $(seq 1 60); do [ -f "$FAKE_GH/watch-calls" ] && break; sleep 0.5; done; sleep 1
kill -TERM "$rp"; wait "$rp"; xrc=$?
sleep 0.5; if pgrep -f 'sleep 939[12]' >/dev/null 2>&1; then bad "(wb4) [AC-4] the watch call outlived a TERM to the run (rc=$xrc)"; pkill -KILL -f 'sleep 939[12]'
else [ "$xrc" -eq 143 ] && grep -q 'terminated; claim left in place' "$d/wb4.log" && ok "(wb4) [AC-4] TERM during the watch call exits 143 and reaps the call's whole group" || bad "(wb4) rc=$xrc $(tail -n 2 "$d/wb4.log" | tr '\n' '|')"; fi
# (dk1-dk4) AC-20 D-28: a detached run killed by its printed pid or by its process group stops through its own trap,
# leaves its claim, leaves no process of its group behind, and its log still ends with the exit line
detached_kill() { # detached_kill <case> <signal> pid|group <rc>
  fixture "$1"; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --detach
  local pid log; pid="$(sed -n 's/.*detached: pid \([0-9]*\) .*/\1/p' <<<"$OUT")"; log="$(sed -n 's/.*detached: pid [0-9]* · log \([^ ]*\) .*/\1/p' <<<"$OUT")"
  [ -n "$pid" ] && [ -n "$log" ] || { bad "($1) no pid or log: $OUT"; return; }
  for _ in $(seq 1 120); do grep -q ' \[run\] session: build 1.1 ' "$log" 2>/dev/null && [ -f "$FAKE_GH/calls" ] && break; sleep 0.5; done; sleep 1
  if [ "$3" = group ]; then kill "-$2" -- "-$pid"; else kill "-$2" "$pid"; fi
  for _ in $(seq 1 60); do grep -q 'detached run exited rc=' "$log" && break; sleep 0.5; done
  local last; last="$(tail -n 1 "$log")"
  grep -qE " \[run\] detached run exited rc=$4$" <<<"$last" && grep -q 'claim left in place' "$log" && grep -qx in-progress "$FAKE_GH/labels" \
    && ok "($1) [AC-20] $2 to the $3 stops the run through its trap, the claim kept, the last line 'detached run exited rc=$4'" || bad "($1) [AC-20] $2 to the $3: $(tail -n 3 "$log" | tr '\n' '|')"
  for _ in $(seq 1 20); do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 -- "-$pid" 2>/dev/null; then bad "($1) [AC-20] a process of the run's group survived: $(pgrep -l -g "$pid" | tr '\n' '|')"; kill -KILL -- "-$pid" 2>/dev/null
  else ok "($1) [AC-20] no process of the run, its session or the wrapper survives"; fi
}
detached_kill dk1 TERM pid 143
detached_kill dk2 TERM group 143
detached_kill dk3 INT pid 130
detached_kill dk4 HUP group 129

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
