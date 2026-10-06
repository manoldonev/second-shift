#!/usr/bin/env bash
# check-frontmatter.sh — every plugin skill and agent carries frontmatter Claude Code reads whole.
#
# WHY THIS EXISTS. An unquoted `description:` value that contains ` #` or `: ` is not the string it
# looks like: ` #` starts a YAML comment, and `: ` opens a mapping that a lenient parser cuts at. The
# skill listing then shows a description truncated mid-sentence, and description routing reads
# the stub. Eight descriptions shipped that way before this guard.
#
# WHAT COUNTS AS A VIOLATION.
#   (1) a plain (unquoted, non-block) `description:` value containing ` #` or `: `;
#   (2) a `name:` that differs from the skill's directory or the agent's file name.
# Scanned: plugins/*/skills/*/SKILL.md and plugins/*/agents/*.md — test fixtures sit deeper and
# are not scanned.
#
# ZERO FILES IS A FAILURE (rc 2): a scan of nothing is a moved root, not a clean tree.
#
# Usage: check-frontmatter.sh [root]   (root defaults to the repo root; the selftest passes a fixture tree)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

n=0; bad=0
for f in "$ROOT"/plugins/*/skills/*/SKILL.md "$ROOT"/plugins/*/agents/*.md; do
  [ -f "$f" ] || continue
  n=$((n+1)); rel="${f#"$ROOT"/}"
  case "$f" in */SKILL.md) want="$(basename "$(dirname "$f")")" ;; *) want="$(basename "$f" .md)" ;; esac
  fm="$(awk 'NR == 1 && /^---[ \t]*$/ { i = 1; next } i && /^---[ \t]*$/ { exit } i' "$f")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:blank:]]*//p' | head -n 1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:blank:]]*//p' | head -n 1)"
  [ "$name" = "$want" ] || { echo "$rel: name '$name' does not match '$want'"; bad=1; }
  case "$desc" in
    \"*|\'*|\|*|\>*) : ;;
    *" #"*|*": "*) echo "$rel: unquoted description contains ' #' or ': ' — YAML cuts it there; quote it"; bad=1 ;;
  esac
done
[ "$n" -gt 0 ] || { echo "check-frontmatter: no skill or agent files under $ROOT/plugins — wrong root?"; exit 2; }
[ "$bad" -eq 0 ] && echo "check-frontmatter: $n files ok"
exit "$bad"
