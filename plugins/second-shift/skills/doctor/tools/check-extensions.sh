#!/usr/bin/env bash
# check-extensions.sh — EP-3 manifest lint, run by /second-shift:doctor. Every file under
# .claude/second-shift/ must match a known name in the manifest beside this script
# (extension-manifest.txt) or the consumer .known-extensions allowlist, so a typo'd name like
# blocker-mutants.md.md is loud, not silently never consulted. It reads no config.
# Usage: check-extensions.sh [consumer-repo-root]   (default: cwd).
# Exit: 0 clean · 1 unknown file(s), one UNKNOWN-EXTENSION line each on stderr · 2 manifest missing
set -euo pipefail
ROOT="${1:-.}"
SS="$ROOT/.claude/second-shift"
MANIFEST="${SECOND_SHIFT_EXTENSION_MANIFEST:-$(cd "$(dirname "$0")" && pwd)/extension-manifest.txt}"
fails=0

# ---- EP-3 extension-file manifest lint ----
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
