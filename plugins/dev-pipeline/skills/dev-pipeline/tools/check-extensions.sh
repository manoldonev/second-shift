#!/usr/bin/env bash
# check-extensions.sh — EP-3 lockstep validator. Lints a consumer repo's .claude/second-shift/
# extension files against the plugin-shipped manifest (extension-manifest.txt). An unrecognized
# file (a typo'd name like blocker-mutants.md.md, or a file the plugin version does not know) is a
# FAIL-CLOSED config-lint failure — converting "missing extension = generic behavior" from silent
# degradation into a checked contract. Run at pipeline pre-flight alongside config-lint.
# Usage: check-extensions.sh [consumer-repo-root]   (default: cwd). Exit 1 on any unknown file.
set -euo pipefail
ROOT="${1:-.}"
SS="$ROOT/.claude/second-shift"
MANIFEST="${SECOND_SHIFT_EXTENSION_MANIFEST:-$(cd "$(dirname "$0")" && pwd)/extension-manifest.txt}"

[[ -d "$SS" ]] || { echo "check-extensions: no .claude/second-shift/ — nothing to check"; exit 0; }
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

fails=0
while IFS= read -r f; do
  rel="${f#"$SS"/}"
  # dotfiles (e.g. .known-extensions) are control files, not extension content — skip them
  [[ "$(basename "$rel")" == .* ]] && continue
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

if [[ "$fails" -gt 0 ]]; then
  echo "check-extensions: $fails unknown extension file(s) — fail closed" >&2
  exit 1
fi
echo "check-extensions: clean"
