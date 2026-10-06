#!/usr/bin/env bash
# Selftest for check-frontmatter.sh: each violation reds and names its file, the quoted and block
# forms of the same text stay green, an empty scan is rc 2, and the real tree passes.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/check-frontmatter.sh"
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

tree() { # tree <case> <name> <description-line> -> a fixture root holding one skill and one clean agent
  local r="$TMP/$1"; mkdir -p "$r/plugins/p/skills/s" "$r/plugins/p/agents"
  printf -- '---\nname: %s\n%s\n---\nbody\n' "$2" "$3" > "$r/plugins/p/skills/s/SKILL.md"
  printf -- '---\nname: a\ndescription: An agent.\n---\n' > "$r/plugins/p/agents/a.md"
  printf '%s' "$r"
}
expect() { # expect <rc> <label> <root> [file-it-must-name]
  local out rc; out="$(bash "$CHECK" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq "$1" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -q "$4"; }; then ok "$2"; else bad "$2 (rc=$rc: $out)"; fi
}

echo "[check-frontmatter-selftest]"
expect 1 "an unquoted ' #' reds"           "$(tree hash s 'description: Retired in #574.')"            skills/s/SKILL.md
expect 1 "an unquoted ': ' reds"           "$(tree colon s 'description: Expects intake: a record.')" skills/s/SKILL.md
expect 1 "a name off its directory reds"  "$(tree name t 'description: Fine.')"                       "name 't'"
expect 0 "the same text single-quoted is green" "$(tree sq s "description: 'Retired in #574; intake: a record.'")"
expect 0 "the same text double-quoted is green" "$(tree dq s 'description: "Retired in #574; intake: a record."')"
expect 0 "a block scalar is green"        "$(tree blk s 'description: >-')"
mkdir -p "$TMP/empty/plugins"; expect 2 "an empty scan is rc 2" "$TMP/empty"
expect 0 "the real tree passes" "$(cd "$SCRIPT_DIR/.." && pwd)"
exit "$fail"
