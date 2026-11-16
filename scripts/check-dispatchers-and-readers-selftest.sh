#!/usr/bin/env bash
# Selftest for check-dispatchers-and-readers.sh: a clean fixture passes, each planted orphan reds and
# names itself, a test or lint naming a surface does not keep it alive, exceptions are honored and
# go stale, an empty scan is rc 2, and the real tree passes.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/check-dispatchers-and-readers.sh"
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

SCHEMA='{"properties":{
  "run":{"properties":{"maxRounds":{"type":"integer"}}},
  "commands":{"additionalProperties":{"properties":{"lanes":{"type":"array","items":{"properties":{"cwd":{"type":"string"}}}}}}}
}}'

tree() { # tree <case> -> a clean fixture root: one dispatched agent, every key read
  local r="$TMP/$1"
  mkdir -p "$r/plugins/p/agents" "$r/plugins/p/skills/s" "$r/plugins/p/workflows" "$r/plugins/p/tools" "$r/schema"
  printf -- '---\nname: rev\n---\n' > "$r/plugins/p/agents/rev.md"
  printf 'Dispatch p:rev on the diff.\n' > "$r/plugins/p/skills/s/SKILL.md"
  printf '%s\n' "$SCHEMA" > "$r/schema/second-shift.config.schema.json"
  printf 'const n = config?.run?.maxRounds\n' > "$r/plugins/p/workflows/w.mjs"
  printf 'jq ".commands.app.lanes[] | .cwd"\n' > "$r/plugins/p/tools/lanes.sh"
  printf '%s' "$r"
}
expect() { # expect <rc> <label> <root> [text-the-output-must-hold]
  local out rc; out="$(CHECK_AGENT_EXCEPTIONS="${AX-}" CHECK_KEY_EXCEPTIONS="${KX-}" bash "$CHECK" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq "$1" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -qF -- "$4"; }; then ok "$2"; else bad "$2 (rc=$rc: $out)"; fi
}

echo "[check-dispatchers-and-readers-selftest]"
expect 0 "a clean fixture passes" "$(tree clean)"

r="$(tree orphan)"; printf -- '---\nname: lonely\n---\n' > "$r/plugins/p/agents/lonely.md"
expect 1 "an agent nothing dispatches reds" "$r" "AGENT plugins/p/agents/lonely.md"

r="$(tree testonly)"; printf -- '---\nname: lonely\n---\n' > "$r/plugins/p/agents/lonely.md"
printf 'run lonely\n' > "$r/plugins/p/skills/s/s-selftest.sh"
expect 1 "a selftest naming an agent is not a dispatcher" "$r" "AGENT plugins/p/agents/lonely.md"

r="$(tree longer)"; printf -- '---\nname: re\n---\n' > "$r/plugins/p/agents/re.md"
printf 'Dispatch p:re-two too.\n' >> "$r/plugins/p/skills/s/SKILL.md"
expect 1 "a longer name does not stand in for a shorter agent" "$r" "AGENT plugins/p/agents/re.md"

r="$(tree samename)"; printf -- '---\nname: s\n---\n' > "$r/plugins/p/agents/s.md"
expect 1 "an agent named like a skill reds" "$r" "SAME-NAME plugins/p/agents/s.md"
AX='s|reached through the skill' expect 0 "an exception with a reason clears it" "$r"
AX='s|' expect 1 "an exception with no reason reds" "$r" "gives no reason"

r="$(tree staleagent)"
AX='rev|human-invoked' expect 1 "an exception for a dispatched agent is stale" "$r" "STALE agent exception 'rev'"
AX='ghost|retired' expect 1 "an exception for a missing agent is stale" "$r" "STALE agent exception 'ghost': no such agent"

r="$(tree unread)"; rm "$r/plugins/p/workflows/w.mjs"
expect 1 "a key nothing reads reds" "$r" "KEY run.maxRounds"

r="$(tree lintonly)"; rm "$r/plugins/p/workflows/w.mjs"
mkdir -p "$r/plugins/dev-pipeline/tools"; printf 'jq .run.maxRounds\n' > "$r/plugins/dev-pipeline/tools/config-lint.sh"
expect 1 "config-lint naming a key is not a reader" "$r" "KEY run.maxRounds"

r="$(tree noancestor)"; printf 'jq ".commands.app.lanes"\n' > "$r/plugins/p/tools/lanes.sh"
printf 'x=.cwd\n' > "$r/plugins/p/tools/other.sh"
expect 1 "an item key read without its ancestor reds" "$r" "KEY commands.*.lanes[].cwd"
KX='commands.*.lanes[].cwd|undecided' expect 0 "a key exception clears it" "$r"

r="$(tree stalekey)"
KX='run.maxRounds|undecided' expect 1 "an exception for a read key is stale" "$r" "STALE key exception 'run.maxRounds'"

mkdir -p "$TMP/empty/plugins" "$TMP/empty/schema"; printf '{}\n' > "$TMP/empty/schema/second-shift.config.schema.json"
expect 2 "an empty scan is rc 2" "$TMP/empty"

out="$(bash "$CHECK" "$(cd "$SCRIPT_DIR/.." && pwd)" 2>&1)" && ok "the real tree passes" || bad "the real tree passes ($out)"
exit "$fail"
