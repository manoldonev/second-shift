#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-claim-selftest.sh — run.sh scenario slice: labels and claims, the bot path, PR conventions,
# signals, design-provider tickets, session bounds.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-claim-selftest] labels and claims, the bot path, PR conventions, signals, design-provider tickets, session bounds"

# (t) round-five parity: configured label names are WRITTEN, not just read; the no-bot claim path;
#     an unreadable tracker fails closed; every usage slug
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"queue":"todo","claimed":"doing"}},"paths":{"plansDir":"docs/plans"}}' fixture t1
printf 'todo\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(t1) run with configured label names"
grep -qx doing "$FAKE_GH/labels" && ! grep -qx todo "$FAKE_GH/labels" && ok "(t1) the configured queue label was removed and the configured claimed label applied" || bad "(t1) labels after claim: $(tr '\n' ' ' < "$FAKE_GH/labels")"
fixture t2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
# no bot configured, RUN_GH unset: the plain-gh swap must be taken (the fake sits on PATH as `gh`)
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(t2) a consumer with no bot configured can run (plain gh claim swap)"
fixture t3; : > "$FAKE_GH/state"; cat > "$T/bin/gh-dead" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue view" ] && [[ "\$*" == *state* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-dead"; RUN_GH="$T/bin/gh-dead" run_case "$d"; expect env-tracker-unreadable "(t3) an unreadable tracker is a refusal, never read as OPEN"
fixture t4; OUT="$( cd "$d/main" && bash "$RUN" 2>&1 )"; grep -q '^terminal: usage-missing-issue$' <<<"$OUT" && ok "(t4) usage-missing-issue slug" || bad "(t4) missing-issue slug absent"
OUT="$( cd "$d/main" && bash "$RUN" 42 --max-rounds 0 2>&1 )"; grep -q '^terminal: usage-max-rounds$' <<<"$OUT" && ok "(t4) usage-max-rounds slug" || bad "(t4) max-rounds slug absent"
OUT="$( cd "$d/main" && bash "$RUN" 42 --review-model sonnet 2>&1 )"; grep -q '^terminal: usage-review-model-basis$' <<<"$OUT" && ok "(t4) usage-review-model-basis slug" || bad "(t4) review-model-basis slug absent"

# (u) round-six parity: no blind body replace, a broken enabled bot refuses, staleness anchored at
#     the branch point on re-entry, a dead review session, a failed marker post
fixture u1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-nobody" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-nobody"; RUN_GH="$T/bin/gh-nobody" run_case "$d"; expect approved "(u1) run whose PR-body read fails"
[ ! -f "$FAKE_GH/pr-body.md" ] && grep -q 'NOT written' <<<"$OUT" && ok "(u1) an unreadable PR body is never replaced blind" || bad "(u1) body was PATCHed over an unread body"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"wrapperPath":"/nonexistent/gh-as-bot.sh"}},"paths":{"plansDir":"docs/plans"}}' fixture u2
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" env -u RUN_GH -u GH_BOT bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect env-bot "(u2) bot enabled but its wrapper missing is a refusal, never a silent write as the operator"
fixture u3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(u3) first run"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main && echo moved >> work.txt && git add work.txt && git commit -qm "base moves onto the branch's file" && git push -q origin main ) 2>/dev/null
u3_head="$(git -C "$d/origin.git" rev-parse second-shift/42)"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect staleness-expired "(u3) on re-entry the base move since the BRANCH POINT is seen"; [ "$RC" -eq 7 ] && ok "(u3) [B12] staleness-expired exits 7" || bad "(u3) exit $RC"
grep -q 'the rebase onto [0-9a-f]* conflicts in: work.txt' <<<"$OUT" && [ "$(git -C "$d/origin.git" rev-parse second-shift/42)" = "$u3_head" ] && [ -z "$(git -C "$d/wt/42" status --porcelain 2>/dev/null)" ] \
  && ok "(u3) a conflicting rebase is aborted: the stop names the file, origin and the worktree are as they were" || bad "(u3) $(grep -E 'terminal|rebase' <<<"$OUT" | tr '\n' '|')"
# (u3r) a base move into the branch's file that git rebases cleanly goes on: the branch is rebased and pushed, and the
#       record baseline — in the PR body and in the next build's prompt — follows the rewritten record commit
FIXTURE_FILES=work.txt FIXTURE_BODY=$'a\nb\nc\nd\ne' fixture u3r; commit_record
first0="$(git -C "$d/origin.git" log --format=%H --diff-filter=A second-shift/42 -- docs/plans/main-42-decisions.md | tail -n 1)"
printf 'built-by: fake\n\nRecord baseline: %s\n' "${first0:0:12}" > "$FAKE_GH/live-body"
cat > "$T/bin/gh-body" <<EOF
#!/usr/bin/env bash
# the PR body as GitHub serves it: --jq .body reads it raw, a PATCH replaces it and is kept in order
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then cat "\$FAKE_GH/live-body"; exit 0; fi
if [ "\$1 \$2 \$3" = "api -X PATCH" ]; then for a in "\$@"; do case "\$a" in body=@*) cp "\${a#body=@}" "\$FAKE_GH/live-body"; { cat "\${a#body=@}"; echo '<!-- end of patch -->'; } >> "\$FAKE_GH/patches" ;; esac; done; fi
exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-body"; printf 'build-pr\nreview-needs-work-move-base\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
RUN_GH="$T/bin/gh-body" run_case "$d"; expect approved "(u3r) a clean rebase onto a base that moved into the branch's file does not stop the run"
first1="$(git -C "$d/origin.git" log --format=%H --diff-filter=A second-shift/42 -- docs/plans/main-42-decisions.md | tail -n 1)"
git -C "$d/origin.git" merge-base --is-ancestor main second-shift/42 && [ "$(git -C "$d/origin.git" show second-shift/42:work.txt | head -n 1)" = moved ] && [ "$first1" != "$first0" ] \
  && ok "(u3r) the branch on origin is rebased onto the moved base and its record commit is new" || bad "(u3r) origin: first $first0 -> $first1, work.txt line 1 '$(git -C "$d/origin.git" show second-shift/42:work.txt | head -n 1)'"
grep -qx "Record baseline: $first1" "$FAKE_GH/patches" && grep -qx "Record baseline: $first1" "$FAKE_GH/live-body" && grep -q "Commit $first1 is the record baseline" "$FAKE_GH/prompt-3.txt" \
  && ok "(u3r) the PR body's 'Record baseline:' line and the round-2 build prompt name the rebased record commit" || bad "(u3r) baseline: body $(grep 'Record baseline' "$FAKE_GH/live-body"), want $first1"
fixture u4; printf 'build-pr\nreview-crash\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(u4) a review session that died is not a verdict"
fixture u5; cat > "$T/bin/gh-nocomment" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue comment" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-nocomment"; RUN_GH="$T/bin/gh-nocomment" run_case "$d"; expect env-claim-failed "(u5) a claim marker that could not be posted is a refusal"

# (v) round-seven parity: the working-bot path end to end, jira keys lowercased in the branch, the
#     marker's author filter, must-show absent is red, every lane named before the first diff
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT","app":{"appName":"second-shift-bot"}}},"paths":{"plansDir":"docs/plans"}}' fixture v1
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
git -C "$d/main" config user.name t; git -C "$d/main" config user.email t@x   # the build's own commits; the record commit must carry the bot's identity instead
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh" env -u RUN_GH -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(v1) a consumer WITH a bot: claim through claim-issue.sh, marker and body through the wrapper"
grep -qx in-progress "$FAKE_GH/labels" && ! grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(v1) claim-issue.sh swapped the labels through the bot" || bad "(v1) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(v1) marker posted through the bot" || bad "(v1) no marker"
# #985: the bot-commit call the prompt names, and the 'bash <helper>' form the scheduler itself uses, both match a granted prefix
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); bcall=$(grep -o "'[^']*/bot-commit\.sh -C [^']*'" "$FAKE_GH/prompt-1.txt" | tr -d "'" | sed 's/<[^>]*>/msg.txt/')
granted() { # granted <command> [<allowlist>, default $bal]: a 'Bash(x)' rule matches exactly; each * in one matches any run
  # of characters, so 'Bash(x*)' matches by prefix and 'Bash(x * y *)' (#1048 D-3) by its words in order
  local r p s lit; IFS=, read -r -a r <<<"${2-$bal}"
  for p in "${r[@]}"; do
    case "$p" in Bash\(*\)) p="${p#Bash(}"; p="${p%)}" ;; *) continue ;; esac
    case "$p" in *\**) ;; *) [ "$1" = "$p" ] && return 0; continue ;; esac
    lit="${p%%\**}"; [[ "$1" == "$lit"* ]] || continue; s="${1#"$lit"}"; p="${p#*\*}"
    while :; do case "$p" in
      *\**) lit="${p%%\**}"; p="${p#*\*}"; [[ "$s" == *"$lit"* ]] || continue 2; s="${s#*"$lit"}" ;;
      *) [[ "$s" == *"$p" ]] && return 0; continue 2 ;;
    esac; done
  done; return 1; }
[ -n "$bcall" ] && granted "$bcall" && granted "bash $bcall" && ok "(v1) the prompt's bot-commit call and its bash form are both granted" || bad "(v1) bot-commit call '${bcall:-none}' not granted, bare or through bash"
[ "$(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)" = 'second-shift-bot[bot]' ] && ok "(v1) [E3] the record commit carries the bot's identity" || bad "(v1) [E3] record commit author: $(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)"
# every command of a piped or chained check is granted (each is checked on its own), a later one by its own text only,
# never one led by rm; the build may run its worktree's scripts, the review jq and shasum
fixture vg $'- printf x | xargs -0 echo -e a,b\n- true && cat /dev/null\n- true && rm -rf a,b'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(vg) piped and chained checks"
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); ral=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-2.txt" | tail -n 1); wt=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | sed -n 2p)
miss=""; for c in 'printf x' 'xargs -0 echo -e a,b' 'true' 'cat /dev/null' "bash $wt/t.sh"; do granted "$c" || miss="$miss [$c]"; done
for c in 'jq -n 1' 'shasum x'; do granted "$c" "$ral" || miss="$miss [review: $c]"; done
for c in 'xargs rm x' 'cat /etc/passwd' 'cat /dev/null /etc/passwd' 'rm -rf x'; do granted "$c" && miss="$miss [granted: $c]"; done
[ -n "$wt" ] && [ -z "$miss" ] && ok "(vg) each command of a piped or chained check is granted by its own text, rm never; worktree scripts, jq and shasum are" || bad "(vg) allowlist wrong:$miss"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture v2
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
OUT="$( cd "$d/main" && bash "$RUN" GH-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(v2) jira key"
grep -q 'Fetch it with the getJiraIssue MCP tool' "$FAKE_GH/prompt-1.txt" && ! grep -q 'gh issue view GH-42' "$FAKE_GH/prompt-1.txt" \
  && ok "(v2) #1048 D-5 D-19: under jira the build prompt names getJiraIssue as the ticket fetch" || bad "(v2) #1048 jira fetch: $(grep -i 'fetch' "$FAKE_GH/prompt-1.txt" | head -n 2 | tr '\n' '|')"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/jdoe/gh-42 >/dev/null && ok "(v2) the jira key is lowercased in the branch name, as the adapter documents" || bad "(v2) branches: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
fixture v3; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
jq '. + [{body:"<!-- run_id: x -->\n<!-- stage: lean-claimed -->",user:{login:"stranger",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect claimed-elsewhere "(v3) a marker posted by another account is not the lane's claim"
fixture v4; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
jq '. + [{body:"<!-- run_id: x -->\n<!-- stage: lean-claimed -->",user:{login:"some-app[bot]",type:"Bot"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect approved "(v4) a Bot-authored marker re-enters"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {mustShow} = ok\"}}}" fixture v5 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(v5) route smoke: render, non-empty image, must-show satisfied"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture v6 "- true" $'\n## Design frames\n\n| RS | route | state | frame |\n| --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 |\n'
# the launch lint refuses this receipt from disk (#1022), so the smoke's own guard is reached the way a record the lint
# never saw reaches it: committed on the branch already
run_case "$d"; expect env-receipt-invalid "(v6) the same frames row in a receipt on disk is refused at launch"
grep -q 'receipt: ledger-lint: VIOLATION: malformed design frames row' <<<"$OUT" && ok "(v6) the refusal prints the lint's violation" || bad "(v6) violation not printed: $(grep 'receipt: ' <<<"$OUT" | head -n 3)"
commit_record; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(v6) a frames row with no must-show value is red, never silently green (D-4)"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["e2e-runner --all"]}]}}}' fixture v7 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
grep -q 'e2e-runner --all' "$FAKE_GH/prompt-1.txt" && grep -q 'Bash(e2e-runner\*)' "$FAKE_GH/args-1.txt" && ok "(v7) a when-globbed lane is named in the round-1 prompt and allowlist before any diff exists" || bad "(v7) lane missing from the prompt or allowlist"

# (z) #1048: what a build session reaches for is granted, steered or answered with a reason
# (zg) AC-2 D-2 OR-1: an xargs segment of a check also grants the command it runs on its own, by the same cut prefix — the
#      value -n takes skipped, never a bare word, never one run by rm, a shell, env, eval, exec, sudo, nohup, cd or python3.
#      xargs -r and empty input keep every check from running anything
chk=$'- find . -name \'no-such-*.sh\' -type f -print0 | xargs -0 -r shellcheck -e SC1091,SC2015,SC2181\n- printf \'\' | xargs -0 -r -n 1 jq empty\n- printf \'\' | xargs -0 -r sudo ls\n- printf \'\' | xargs -0 -r date'
for x in rm sh bash zsh env eval exec sudo nohup cd python3; do chk="$chk"$'\n'"- printf '' | xargs -0 -r -n 1 $x -c a,b"; done
fixture zg "$chk"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(zg) checks whose xargs segments run a tool"
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); miss=""
for c in 'shellcheck -e SC1091 plugins/x.sh' 'jq empty a.json'; do granted "$c" || miss="$miss [$c]"; done
for c in 'shellcheck plugins/x.sh' 'sudo ls x' 'date'; do granted "$c" && miss="$miss [granted: $c]"; done
for x in rm sh bash zsh env eval exec sudo nohup cd python3; do
  granted "$x -c a" && miss="$miss [granted: $x -c a]"; granted "xargs -0 -r -n 1 $x -c a" && miss="$miss [granted: xargs -0 -r -n 1 $x -c a]"
done
[ -z "$miss" ] && ok "(zg) AC-2: shellcheck -e and jq empty are granted on their own; a bare word, sudo, rm, a shell, env, eval, exec, nohup, cd and python3 are not, through xargs or alone" || bad "(zg) AC-2 allowlist wrong:$miss"
# (zh) AC-1 AC-3 AC-4 AC-5 AC-6 on a plain github run
fixture zh; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(zh) a plain github run"
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); wt=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | sed -n 2p); scr=$(awk 'p { print; p = 0 } $0 == "--add-dir" { p = 1 }' "$FAKE_GH/args-1.txt" | sed -n 2p)
[[ ",$bal," == *,Grep,* && ",$bal," == *,Glob,* ]] && ! granted 'grep -n x a.sh' && ! granted 'ls -la' && ! granted 'wc -l a.sh' && ! granted 'head -n 1 a.sh' \
  && ok "(zh) AC-1: the build has the Grep and Glob tools and no Bash grep, ls, wc or head" || bad "(zh) AC-1 build allowlist: $bal"
granted 'gh pr edit 7 --body-file /x/b.md' && ! granted 'gh pr edit 7 --body x' && ! granted 'gh pr edit 7 --add-label x' \
  && ok "(zh) AC-3: gh pr edit --body-file is granted, gh pr edit otherwise is not" || bad "(zh) AC-3 gh pr edit: $bal"
grep -q "Run the checks listed below and the tests your change touches, never a verification list from the repo's CLAUDE.md or docs" "$FAKE_GH/prompt-1.txt" \
  && ok "(zh) AC-4: the build prompt runs the listed checks and the touched tests, never a CLAUDE.md or docs list" || bad "(zh) AC-4 sentence missing from the build prompt"
fetch=$(grep -o "Fetch it with exactly '[^']*'" "$FAKE_GH/prompt-1.txt" | sed "s/^Fetch it with exactly '//; s/'\$//")
[ "$fetch" = 'gh issue view 42 --json title,body,comments' ] && granted "$fetch" && ok "(zh) AC-5: the prompt's ticket fetch is '$fetch', and the build allowlist grants it" || bad "(zh) AC-5 fetch '${fetch:-none}' missing or not granted"
bset=$(grep -A1 -x -- '--settings' "$FAKE_GH/args-1.txt" | tail -n 1); rset=$(grep -A1 -x -- '--settings' "$FAKE_GH/args-2.txt" | tail -n 1)
hcmd=$(jq -r '.hooks.PermissionRequest[0].hooks[0].command // empty' <<<"$bset" 2>/dev/null)
hook_says() { # hook_says <tool> <file_path-or-command>: what the build's hook command, run as the settings write it, decides
  jq -cn --arg t "$1" --arg v "$2" '{hook_event_name:"PermissionRequest",cwd:"/",tool_name:$t,tool_input:(if $t == "Bash" then {command:$v} else {file_path:$v,content:"x"} end)}' \
    | bash -c "$hcmd" | jq -r '.hookSpecificOutput.decision | .behavior + " " + (.message // "")'
}
[ "$(sed -n "s/^bash '\([^']*\)'.*/\1/p" <<<"$hcmd")" = "$(cd "$(dirname "$RUN")/../../tools" && pwd)/lane-permission-hook.sh" ] \
  && [ "$(hook_says Write "$wt/.claude/NOTES.md")" = 'allow ' ] && [[ "$(hook_says Write "$wt/.claude/settings.json")" == deny* ]] \
  && [[ "$(hook_says Bash "wc -l $scr/log")" == 'deny wc is not granted'* ]] && [[ "$(hook_says Bash "wc -l $d/main/x")" == *'withheld from lane sessions'* ]] \
  && jq -e 'has("hooks") | not' <<<"$rset" >/dev/null 2>&1 \
  && ok "(zh) AC-6: the build's --settings runs the dev-pipeline tools hook on PermissionRequest, given its worktree and scratch dir; the review's has no hooks" \
  || bad "(zh) AC-6 build settings: $bset · review settings: $rset"

# (zi) #1080: a plansDir under .claude/ — the build's hook is given the record and the plan, so the build can write the plan
#      the plan coverage requires and edit the record's rows there; any other file in that dir is still denied
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":".claude/plans"}}' fixture zi
printf '.claude/*\n!.claude/plans/\n' > "$d/main/.gitignore" && git -C "$d/main" commit -qam 'track .claude/plans' && git -C "$d/main" push -q origin main 2>/dev/null
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(zi) #1080: a run whose plansDir is .claude/plans"
bset=$(grep -A1 -x -- '--settings' "$FAKE_GH/args-1.txt" 2>/dev/null | tail -n 1); wt=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" 2>/dev/null | sed -n 2p)
hcmd=$(jq -r '.hooks.PermissionRequest[0].hooks[0].command // empty' <<<"$bset" 2>/dev/null)
[ "$(hook_says Write "$wt/.claude/plans/main-42-plan.md")" = 'allow ' ] && [ "$(hook_says Edit "$wt/.claude/plans/main-42-decisions.md")" = 'allow ' ] \
  && [[ "$(hook_says Write "$wt/.claude/plans/notes.md")" == 'deny '*'sessions load'* ]] \
  && ok "(zi) #1080: the build's hook allows the plan and the record in .claude/plans/, and denies any other file there" \
  || bad "(zi) #1080 hook: $hcmd · plan: $(hook_says Write "$wt/.claude/plans/main-42-plan.md")"

# (w) round-eight parity: PR conventions asserted, a stopped run still leaves its block,
#     claimed-elsewhere exits 2, second run's block is its own
# E22 E23: a lane PR is a draft until a review approves its head — GitHub refuses to merge a draft
fixture w1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w1) [E22 E23] a ready PR from the build"
[ "$(cut -d' ' -f2 "$FAKE_GH/ready-calls" 2>/dev/null | tr '\n' ' ')" = "undo ready " ] && ok "(w1) [E22 E23] turned into a draft after the build, marked ready only on the approve" || bad "(w1) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
[ ! -f "$FAKE_GH/draft" ] && grep -q 'marked ready for review — approved at' "$FAKE_GH/pr-body.md" && ok "(w1) [E23] the approved PR is ready and its run block says so" || bad "(w1) still a draft, or no note in the run block"
fixture w1d; printf 'build-pr-draft\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w1d) [E22] a draft PR is no finding"
[ "$(cut -d' ' -f2 "$FAKE_GH/ready-calls" 2>/dev/null | tr '\n' ' ')" = "ready " ] && ok "(w1d) [E22 E23] a draft is left a draft, then marked ready on the approve" || bad "(w1d) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
fixture w1n; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(w1n) [E23] needs-work, then the rounds are spent"
[ -f "$FAKE_GH/draft" ] && ! grep -q ' ready$' "$FAKE_GH/ready-calls" 2>/dev/null && ok "(w1n) [E23] a run that ends without an approve leaves the PR a draft" || bad "(w1n) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
fixture w1f; printf 'build-pr-draft\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'HTTP 403: Resource not accessible by integration' > "$FAKE_GH/ready-fail"; run_case "$d"; expect approved "(w1f) [E23] a flip that fails is not fatal"
grep -q 'still a draft — marking it ready failed (HTTP 403' "$FAKE_GH/pr-body.md" && ok "(w1f) [E23] the run block names the failed flip and its reason" || bad "(w1f) run block: $(grep 'draft' "$FAKE_GH/pr-body.md" 2>/dev/null | head -2 | tr '\n' '|')"
fixture w1b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_CLOSES=lower run_case "$d"; expect approved "(w1b) a lowercase 'closes #42' is accepted, as the old gate matched it"
fixture w2; printf 'build-pr-nobody\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(w2) a PR body without built-by/Closes is sent back, then spent"
grep -q "Closes #42" "$FAKE_GH/prompt-2.txt" && ok "(w2) the convention finding reaches the next build prompt" || bad "(w2) finding not in the next prompt"
fixture w3; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(w3) stopped after a PR exists"
grep -q '| review-unbound |' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(w3) a stopped run still writes its run block into the PR body" || bad "(w3) no run block on a stopped run"
fixture w4; echo in-progress > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 2 ] && ok "(w4) claimed-elsewhere spawned nothing and exits 2" || bad "(w4) exit $RC"
fixture w6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w6) first run"
first_block="$(SD)/pr-body.md"; printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main ) ; run_case "$d" --resume; expect approved "(w6) second run on the same ticket"
[ "$(grep -c '^| build-' "$(SD)/pr-body.md")" = 1 ] && [ "$(SD)/pr-body.md" != "$first_block" ] && ok "(w6) the second run's block lists only its own sessions" || bad "(w6) block rows: $(grep -c '^| build-' "$(SD)/pr-body.md")"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"queue":"ready.for.dev","claimed":"in-progress"}},"paths":{"plansDir":"docs/plans"}}' fixture w7
printf 'ready-for-dev\nopus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(w7) a queue label with regex metacharacters is matched exactly (ready-for-dev is not ready.for.dev)"

# (x) round-ten parity: TERM exits 143 and kills the session, the ready probe gates only a render,
#     a PR-only fix does not dead-end, jira Closes outside its heading, ci red reported
fixture x1; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && exec bash "$RUN" 42 > "$d/x1.log" 2>&1 ) & rp=$!
until grep -q 'round 1 of' "$d/x1.log" 2>/dev/null; do sleep 0.5; done; sleep 1.5
kill -TERM "$rp"; wait "$rp"; xrc=$?
[ "$xrc" -eq 143 ] && ok "(x1) TERM exits 143" || bad "(x1) TERM exit $xrc"
sleep 1; if pgrep -f "$T/bin/claude" >/dev/null 2>&1 || pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(x1) the session outlived the scheduler"; pkill -f "$T/bin/claude" 2>/dev/null; pkill -f 'sleep 60' 2>/dev/null; else ok "(x1) the session and its children were killed with the scheduler"; fi
grep -q 'claim left in place' "$d/x1.log" && grep -qx in-progress "$FAKE_GH/labels" && ok "(x1) the claim is left in place on TERM" || bad "(x1) claim state wrong after TERM"
scr="$(sed -n 's/^.* \[run\] scratch: \(.*\) (both sessions.*$/\1/p' "$d/x1.log")"; toc="$(tar -tf "$(SD)/scratch.tar" 2>&1)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" \
  && ok "(x1) #964 D-2: on TERM the scratch dir is archived into \$STATE and removed" || bad "(x1) #964 D-2: scratch '${scr:-none}' $([ -e "$scr" ] && echo kept), archive: $(tr '\n' ' ' <<<"$toc")"
fixture x1b; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV or die' -- bash "$RUN" 42 > "$d/x1b.log" 2>&1 ) & rp=$!
until grep -q 'round 1 of' "$d/x1b.log" 2>/dev/null; do sleep 0.5; done; sleep 1.5
kill -INT "$rp"; wait "$rp"; xrc=$?
[ "$xrc" -eq 130 ] && grep -q 'interrupted; claim left in place' "$d/x1b.log" && ok "(x1b) [B18] INT exits 130" || bad "(x1b) INT exit $xrc"
sleep 1; if pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(x1b) [B18] the session outlived the scheduler on INT"; pkill -f 'sleep 60' 2>/dev/null; else ok "(x1b) [B18] the session was reaped on INT"; fi
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","readyProbe":"http://127.0.0.1:9/"}}}' fixture x2 "- true" $'\n## Design\n\nDesign: none — a wording change, nothing renders\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(x2) a readyProbe gates nothing on a ticket declared Design: none"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:9/\"}}}" fixture x3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(x3) a dead readyProbe stops an armed ticket before rendering"
[ "$RC" -eq 2 ] && ok "(x3) infra stop, exit 2, no attempt spent" || bad "(x3) exit $RC"
fixture x4; printf 'build-pr-nobody\nbuild-pr-fixbody\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(x4) a PR-only fix (the body) is accepted without the head moving"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture x5
printf 'build-pr-jira-outside\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
OUT="$( cd "$d/main" && RUN_CHECKS_RED_MAX=2 bash "$RUN" GH-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect checks-red-spent "(x5) jira Closes outside its heading is a finding, as the old gate ruled"
fixture x6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; touch "$FAKE_GH/ci-red"; run_case "$d"; expect approved "(x6) CI is never waited on"
grep -q '| red |' "$FAKE_GH/pr-body.md" && ok "(x6) a red CI is reported in the run block" || bad "(x6) CI red not reported"
fixture x7; printf 'build-pr-keyed-title\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(x7) a PR title carrying the ticket key is sent back"
grep -qF 'PR title must not carry #42' "$FAKE_GH/prompt-2.txt" && ok "(x7) the next build is told the title carries #42" || bad "(x7) prompt-2 lacks the title finding"
fixture x8; printf 'build-pr-keyed-commit\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(x8) a commit message carrying the ticket key is sent back"
grep -qF 'commit messages after the record commit must not carry #42' "$FAKE_GH/prompt-2.txt" && ok "(x8) the next build is told a commit carries #42" || bad "(x8) prompt-2 lacks the commit finding"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture x9
printf 'build-pr-keyed-title\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
OUT="$( cd "$d/main" && RUN_CHECKS_RED_MAX=2 bash "$RUN" GH-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect checks-red-spent "(x9) a jira key in the PR title is sent back, while its Closes line under Jira Items passes"
grep -qF 'PR title must not carry GH-42' "$FAKE_GH/prompt-2.txt" && ! grep -q "must carry 'Closes \[GH-42\]'" "$FAKE_GH/prompt-2.txt" && ok "(x9) only the title is a finding" || bad "(x9) prompt-2 findings: $(grep -o 'must[^.]*' "$FAKE_GH/prompt-2.txt" | head -n 3 | tr '\n' '|')"

# (y) round-eleven parity: a provider repo's ticket declares its design state, the probe wants a 2xx/3xx,
#     a timed-out session is reaped, -h prints the whole table
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture y1
run_case "$d"; expect env-design-undeclared "(y1) on a design-provider repo a record with neither frames nor 'Design: none' is refused (#705's rule)"
[ ! -f "$FAKE_GH/calls" ] && ok "(y1) refused before any build" || bad "(y1) a build ran"
fixture y2; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=2 run_case "$d"; expect build-blocked "(y2) a build past its ceiling is stopped"
sleep 1; if pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(y2) the timed-out session's children outlived it"; pkill -f 'sleep 60' 2>/dev/null; else ok "(y2) the timed-out session and its children were reaped"; fi
grep -qx 'BASH_DEFAULT_TIMEOUT_MS=120000' "$FAKE_GH/env-1.txt" && grep -qx 'BASH_MAX_TIMEOUT_MS=120000' "$FAKE_GH/env-1.txt" && ok "(y2) [F-env] a bound under 420 s floors the BUILD's Bash timeouts at the harness's own 120 s" || bad "(y2) [F-env] BUILD spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
# F-env: the bounds feed bash arithmetic, so a fraction is refused before the claim — it must never abandon the round loop into close-out
for v in 600.5 1.5 .; do
  fixture "fe-$v"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT="$v" run_case "$d"; expect env-config-run "(fe1) RUN_BUILD_TIMEOUT=$v is refused"
  [ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(fe1) $v: exit 2, no session spawned" || bad "(fe1) $v: rc=$RC calls=$(cat "$FAKE_GH/calls" 2>/dev/null)"
done
fixture fe2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=7200.0 RUN_REVIEW_TIMEOUT=0900 run_case "$d"; expect approved "(fe2) a whole-number 7200.0 and a zero-padded 0900 are read as integers"
grep -qx 'BASH_MAX_TIMEOUT_MS=6900000' "$FAKE_GH/env-1.txt" && grep -qx 'CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=600000' "$FAKE_GH/env-2.txt" && ok "(fe2) 7200.0 -> 6900 s; 0900 -> 900 s, its wait floored at the harness's own 600 s" || bad "(fe2) env: $(cat "$FAKE_GH/env-1.txt" "$FAKE_GH/env-2.txt" | tr '\n' ' ')"
fixture fe3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 RUN_BUILD_TIMEOUT=9999999 run_case "$d"; expect approved "(fe3) an inherited background-tasks switch and a huge bound"
! grep -q 'CLAUDE_CODE_DISABLE_BACKGROUND_TASKS' "$FAKE_GH/env-2.txt" && ok "(fe3) REVIEW never inherits the BUILD's background-tasks switch" || bad "(fe3) REVIEW env: $(tr '\n' ' ' < "$FAKE_GH/env-2.txt")"
grep -qx 'BASH_MAX_TIMEOUT_MS=2147483647' "$FAKE_GH/env-1.txt" && ok "(fe3) the BUILD's Bash timeout is capped at the JS timer maximum" || bad "(fe3) BUILD env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
port=$(( 20000 + RANDOM % 20000 )); ( cd "$T" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & hs=$!
until curl -s -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; do sleep 0.2; done
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:$port/missing\"}}}" fixture y3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(y3) an HTTP 404 from the readyProbe is not ready"
grep -q 'last reading: HTTP 404' <<<"$OUT" && ok "(y3) the refusal names the reading" || bad "(y3) reading not named"
kill "$hs" 2>/dev/null; wait "$hs" 2>/dev/null
fixture y4; OUT="$( cd "$d/main" && bash "$RUN" -h 2>&1 )"; grep -q '130 / 143' <<<"$OUT" && ok "(y4) -h prints the whole exit table" || bad "(y4) -h truncated"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
