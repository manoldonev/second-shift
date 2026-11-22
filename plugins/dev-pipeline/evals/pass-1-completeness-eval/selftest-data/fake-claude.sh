#!/usr/bin/env bash
# A stand-in for the review session that plain-review.sh spawns, for eval-selftest.sh. It reads which
# variant its tree is from the files there, answers with the canned draft for that arm and variant, and
# leaves a transcript with one Read call under $HOME, as a real session does.
#   FAKE_STATE/fail-once-<arm>-<variant>  when present, one call renames it and fails with no answer
#   FAKE_STATE/cwds  gets the working directory of every call
#   FAKE_READ        the path its one Read call names (default: one.sh in the tree)
#   FAKE_READ_ERROR  when 1, that Read was refused
set -uo pipefail
DATA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model=""
while [ $# -gt 0 ]; do
  case "$1" in --model) model="${2-}"; shift 2 ;; *) shift ;; esac
done
prompt="$(cat)"
case "$prompt" in *"This is pass 1 of the review"*) arm=pass-1 ;; *) arm=plain ;; esac
if [ ! -f two.sh ]; then variant=plant-a; elif [ ! -f two-test.sh ]; then variant=plant-b; else variant=twin; fi
once="${FAKE_STATE:-/nonexistent}/fail-once-$arm-$variant"
if mv "$once" "$once.$$" 2>/dev/null; then exit 1; fi
[ -z "${FAKE_STATE:-}" ] || pwd >> "$FAKE_STATE/cwds"
sid="fake-$$-$RANDOM"
mkdir -p "$HOME/.claude/projects/fake" || exit 1
jq -cn --arg p "${FAKE_READ:-$PWD/one.sh}" --argjson err "$([ "${FAKE_READ_ERROR:-0}" = 1 ] && echo true || echo false)" '
  {type: "assistant", message: {content: [{type: "tool_use", id: "t1", name: "Read", input: {file_path: $p}}]}},
  {type: "user", message: {content: [{type: "tool_result", tool_use_id: "t1", is_error: $err, content: "x"}]}}' \
  > "$HOME/.claude/projects/fake/$sid.jsonl" || exit 1
jq -n --rawfile draft "$DATA/draft-$arm-$variant.md" --arg sid "$sid" --arg model "$model" '
  {type: "result", subtype: "success", result: $draft, session_id: $sid, total_cost_usd: 0.5, num_turns: 3,
   modelUsage: {("claude-" + $model + "-0"): {inputTokens: 1}}}'
