#!/usr/bin/env bash
# check-dispatchers-and-readers.sh — every shipped agent has a dispatcher and every config key a reader.
#
# The selftest rule keeps scripts covered, but a selftest that drives a dead surface keeps it alive.
# This check asks the other question: does anything that ships call it?
#
#   AGENT    plugins/*/agents/<name>.md whose name appears in no dispatcher file: a skill file, a
#            Workflow script or a hook under plugins/ (run.sh is a skill file). The match is the name
#            as a whole token, so a longer agent name never stands in for a shorter one.
#   SAME-NAME an agent named like a skill. A mention cannot tell the agent from the skill, so the
#            agent needs an exception that says how it is reached.
#   KEY      a schema/second-shift.config.schema.json key named by no reader under plugins/. A key
#            with a named parent must appear as `parent.key` (optional chaining is folded first); a
#            top-level key as `.key`; a key under a map or array as `.key` in a file that also names
#            its nearest named ancestor. Object keys with their own properties are covered by those.
#   STALE    an exception whose agent or key is gone, or that now has a dispatcher or reader.
#
# Not readers or dispatchers: tests, fixtures, evals, examples, READMEs, docs/, the schema, and the
# two config lints (config-lint.sh, check-config-shadowing.sh), which name keys to check them.
#
# Ceiling: this is a grep. A name in a prose aside counts as a dispatch, and a generic item key
# (`name`, `when`) is satisfied by any read of that word in a file that names its ancestor.
#
# Exceptions are `<name>|<reason>` lines; CHECK_AGENT_EXCEPTIONS and CHECK_KEY_EXCEPTIONS replace the
# lists below for a fixture tree.
#
# Usage: check-dispatchers-and-readers.sh [root]   exit 1 on any finding, 2 when nothing was scanned
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SCHEMA="$ROOT/schema/second-shift.config.schema.json"

AGENT_EXCEPTIONS="${CHECK_AGENT_EXCEPTIONS-}"
[ -n "${CHECK_AGENT_EXCEPTIONS+set}" ] || AGENT_EXCEPTIONS='doc-updater|human-invoked after a change; its plugin manifest describes it so and nothing in the repo dispatches it
design-faithful|shares its name with the skill it wraps; whether anything dispatches the agent is undecided
design-faithful-spec|shares its name with the skill it wraps; whether anything dispatches the agent is undecided'

KEY_EXCEPTIONS="${CHECK_KEY_EXCEPTIONS-}"
[ -n "${CHECK_KEY_EXCEPTIONS+set}" ] || KEY_EXCEPTIONS="\$schema|JSON Schema metadata for editors and validators, never read by plugin code
commands.*.extraLanes[].failureClass|found by this check, undecided: required by the schema, which says it no longer changes behavior
reviewers.add[].dimensions|found by this check, undecided: described as a routing hint for review-lead, which does not read it"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

excepted() { printf '%s\n' "$2" | awk -F'|' -v k="$1" '$1 == k { f = 1 } END { exit !f }'; }

list_plugin_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$ROOT" && git ls-files -co --exclude-standard -- plugins)
  else
    (cd "$ROOT" && find plugins -type f ! -path '*/node_modules/*')
  fi | grep -vE '(^|/)README\.md$|-selftest[.-]|\.test\.mjs$|(^|/|-)fixtures/|/evals/|/examples/' | sort
}
list_plugin_files > "$TMP/files"

grep -E '^plugins/[^/]+/(skills|workflows|hooks)/' "$TMP/files" > "$TMP/dispatchers"
grep -vE '^plugins/[^/]+/(agents|\.claude-plugin)/|^plugins/dev-pipeline/tools/(config-lint|check-config-shadowing)\.sh$' \
  "$TMP/files" > "$TMP/readers"
mkdir -p "$TMP/r"
while IFS= read -r rel; do
  mkdir -p "$TMP/r/$(dirname "$rel")"
  tr -d '?' < "$ROOT/$rel" > "$TMP/r/$rel" 2>/dev/null
done < "$TMP/readers"

echo "[check-dispatchers-and-readers]"

dispatched() {
  (cd "$ROOT" && tr '\n' '\0' < "$TMP/dispatchers" | xargs -0 grep -lE "(^|[^A-Za-z0-9_-])$1([^A-Za-z0-9_-]|\$)" -- 2>/dev/null) | head -n 1
}

n_agents=0
for f in "$ROOT"/plugins/*/agents/*.md; do
  [ -f "$f" ] || continue
  n_agents=$((n_agents + 1))
  a="$(basename "$f" .md)"; rel="${f#"$ROOT"/}"
  echo "$a" >> "$TMP/agents"
  site="$(dispatched "$a")"
  if excepted "$a" "$AGENT_EXCEPTIONS"; then
    if [ -z "$(ls -d "$ROOT"/plugins/*/skills/"$a" 2>/dev/null)" ] && [ -n "$site" ]; then
      bad "STALE agent exception '$a': $site now dispatches it"
    fi
    continue
  fi
  if [ -n "$(ls -d "$ROOT"/plugins/*/skills/"$a" 2>/dev/null)" ]; then
    bad "SAME-NAME $rel shares its name with a skill, so no mention shows a dispatch; add an exception saying how it is reached"
  elif [ -z "$site" ]; then
    bad "AGENT $rel is named by no skill, workflow or hook under plugins/"
  fi
done

jq -r '
  def keys_of($s; $p):
    ( ($s.properties // {}) | to_entries[] | .key as $k | .value as $v
      | (if $v.properties == null then ($p + [$k] | join("\t")) else empty end),
        keys_of($v; $p + [$k]) ),
    ( if ($s.additionalProperties | type) == "object" then keys_of($s.additionalProperties; $p + ["*"]) else empty end ),
    ( if ($s.items | type) == "object" then keys_of($s.items; $p + ["[]"]) else empty end );
  keys_of(.; [])' "$SCHEMA" > "$TMP/keys" 2>/dev/null || { echo "  FAIL cannot read $SCHEMA"; exit 2; }

read_in() { (cd "$TMP/r" && grep -rlF -- "$1" . 2>/dev/null); }

n_keys=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n_keys=$((n_keys + 1))
  key="$(printf '%s' "$line" | tr '\t' '.' | sed 's/\.\[\]/[]/g')"
  echo "$key" >> "$TMP/seen-keys"
  leaf="${line##*$'\t'}"
  parent=""; anc=""
  case "$line" in *$'\t'*) parent="${line%$'\t'*}"; parent="${parent##*$'\t'}" ;; esac
  case "$parent" in
    "")     hits="$(read_in ".$leaf")" ;;
    "*"|"[]")
      anc="$(printf '%s' "$line" | tr '\t' '\n' | sed '$d' | grep -vxF '*' | grep -vxF '[]' | tail -n 1)"
      hits=""
      for h in $(read_in ".$leaf"); do grep -qF -- "$anc" "$TMP/r/$h" && { hits="$h"; break; }; done ;;
    *)      hits="$(read_in "$parent.$leaf")" ;;
  esac
  if excepted "$key" "$KEY_EXCEPTIONS"; then
    [ -z "$hits" ] || bad "STALE key exception '$key': $(printf '%s\n' "$hits" | head -n 1 | sed 's|^\./||') now reads it"
    continue
  fi
  [ -n "$hits" ] || bad "KEY $key is in the schema but nothing under plugins/ reads it (beyond the lints, tests and docs)"
done < "$TMP/keys"

while IFS='|' read -r a why; do
  [ -n "$a" ] || continue
  [ -n "$why" ] || bad "agent exception '$a' gives no reason"
  grep -qxF "$a" "$TMP/agents" 2>/dev/null || bad "STALE agent exception '$a': no such agent"
done <<< "$AGENT_EXCEPTIONS"
while IFS='|' read -r k why; do
  [ -n "$k" ] || continue
  [ -n "$why" ] || bad "key exception '$k' gives no reason"
  grep -qxF "$k" "$TMP/seen-keys" 2>/dev/null || bad "STALE key exception '$k': no such schema key"
done <<< "$KEY_EXCEPTIONS"

if [ "$n_agents" -eq 0 ] || [ "$n_keys" -eq 0 ]; then
  echo "  scanned $n_agents agent(s) and $n_keys key(s) under $ROOT — wrong root?"; exit 2
fi
[ "$fails" -eq 0 ] && echo "  ok   $n_agents agents and $n_keys config keys checked"
[ "$fails" -eq 0 ]
