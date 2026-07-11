#!/usr/bin/env bash
# check-extensions.sh — EP-3 + EP-6/EP-7 lockstep validator. Two fail-closed checks, run at
# pipeline pre-flight alongside config-lint:
#   (1) EP-3 manifest lint — every file under .claude/second-shift/ must match a known name in the
#       plugin-shipped manifest (extension-manifest.txt) or the consumer .known-extensions allowlist;
#       a typo'd name like blocker-mutants.md.md is loud, not silently ignored.
#   (2) EP-6/EP-7 reference resolution — every config stageWorkflows[].workflow and
#       implementDelegates[].agent reference must resolve: a repo-relative path/agent is stat'd here;
#       a "<plugin>:<relpath>" reference is format-checked (its plugin-cache resolution is a runtime
#       pre-flight concern). An unresolvable local reference is a FAIL-CLOSED config error.
# Usage: check-extensions.sh [consumer-repo-root]   (default: cwd). Exit 1 on any failure.
set -euo pipefail
ROOT="${1:-.}"
SS="$ROOT/.claude/second-shift"
MANIFEST="${SECOND_SHIFT_EXTENSION_MANIFEST:-$(cd "$(dirname "$0")" && pwd)/extension-manifest.txt}"
CONFIG="${SECOND_SHIFT_CONFIG:-$ROOT/.claude/second-shift.config.json}"
fails=0

# ---- (2) EP-6/EP-7 reference resolution (config may exist even with no extension files) ----
if [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r wf; do
    [[ -z "$wf" ]] && continue
    if [[ "$wf" == *:* ]]; then continue; fi   # <plugin>:<relpath> — resolved against the plugin cache at runtime
    if [[ ! -f "$ROOT/$wf" ]]; then
      echo "UNRESOLVED-WORKFLOW: stageWorkflows references '$wf' but no such repo-relative file exists — fail closed (EP-6)" >&2
      fails=$((fails+1))
    fi
  done < <(jq -r '(.stageWorkflows // [])[].workflow // empty' "$CONFIG" 2>/dev/null)

  while IFS= read -r ag; do
    [[ -z "$ag" ]] && continue
    if [[ "$ag" == *:* ]]; then continue; fi   # <plugin>:<agent> — companion pack, resolved at runtime
    if [[ ! -f "$ROOT/.claude/agents/$ag.md" ]]; then
      echo "UNRESOLVED-AGENT: implementDelegates references bare agent '$ag' but .claude/agents/$ag.md does not exist — fail closed (EP-7)" >&2
      fails=$((fails+1))
    fi
  done < <(jq -r '(.implementDelegates // [])[].agent // empty' "$CONFIG" 2>/dev/null)
fi

# ---- (1) EP-3 extension-file manifest lint ----
if [[ -d "$SS" ]]; then
  [[ -f "$MANIFEST" ]] || { echo "check-extensions: manifest not found: $MANIFEST" >&2; exit 2; }
  globs=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    globs+=("$line")
  done < "$MANIFEST"
  # Consumer-declared extra known globs (companion-pack / repo-local extensions the stock manifest
  # doesn't ship — e.g. an org QA pack's api-testing/*.md). Auditable in the repo, additive-only.
  ALLOW="$SS/.known-extensions"
  if [[ -f "$ALLOW" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      globs+=("$line")
    done < "$ALLOW"
  fi
  while IFS= read -r f; do
    rel="${f#"$SS"/}"
    [[ "$(basename "$rel")" == .* ]] && continue   # dotfiles are control files, not extension content
    matched=0
    for g in "${globs[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$rel" == $g ]]; then matched=1; break; fi
    done
    if [[ "$matched" -eq 0 ]]; then
      echo "UNKNOWN-EXTENSION: .claude/second-shift/$rel matches no known extension name (typo, or a file this plugin version does not recognize)" >&2
      fails=$((fails+1))
    fi
  done < <(find "$SS" -type f | sort)
fi

if [[ "$fails" -gt 0 ]]; then
  echo "check-extensions: $fails failure(s) — fail closed" >&2
  exit 1
fi
echo "check-extensions: clean"
