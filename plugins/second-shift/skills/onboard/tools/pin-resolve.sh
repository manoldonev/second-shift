#!/usr/bin/env bash
# pin-resolve.sh — resolve the marketplace pin for /second-shift:onboard.
# Ref = latest GitHub Release tag; fallback = highest vX.Y.Z tag (warn on stderr:
# the repo predates its first Release). Then read each plugin's plugin.json
# `version` AT THAT REF via the GitHub contents API — the lockfile must record
# what the pinned catalog will install, not what any local cache happens to hold.
#
# Usage: pin-resolve.sh <owner/repo> <plugin> [<plugin>...]
# Out:   {"ref":..., "refSource":"release"|"tag-fallback", "plugins":{name:version}}
# Exit:  0 ok · 1 resolution failure · 3 usage
set -uo pipefail
REPO="${1:-}"; shift || true
[[ -z "$REPO" || $# -eq 0 ]] && { echo "usage: pin-resolve.sh <owner/repo> <plugin>..." >&2; exit 3; }

REF=""; REFSRC=""
if REF="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null)" && [[ -n "$REF" ]]; then
  REFSRC=release
else
  # Highest semver among vX.Y.Z tags. sort -t. -k... keeps bash-3.2/BSD-sort compat.
  REF="$(gh api "repos/$REPO/tags?per_page=100" --jq '.[].name' 2>/dev/null \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ -n "$REF" ]] && REF="v$REF" && REFSRC=tag-fallback \
    && echo "pin-resolve: warning — no GitHub Release yet; pinned to highest tag $REF" >&2
fi
[[ -z "$REF" ]] && { echo "pin-resolve: no releases and no semver tags on $REPO — cannot pin" >&2; exit 1; }

PLUGINS_JSON="{}"
for p in "$@"; do
  v="$(gh api "repos/$REPO/contents/plugins/$p/.claude-plugin/plugin.json?ref=$REF" --jq .content 2>/dev/null \
      | base64 --decode 2>/dev/null | jq -r '.version // empty')"
  [[ -z "$v" ]] && { echo "pin-resolve: cannot read plugins/$p version at $REF" >&2; exit 1; }
  PLUGINS_JSON="$(jq -c --arg p "$p" --arg v "$v" '. + {($p): $v}' <<< "$PLUGINS_JSON")"
done

jq -n --arg ref "$REF" --arg src "$REFSRC" --argjson plugins "$PLUGINS_JSON" \
  '{ref:$ref, refSource:$src, plugins:$plugins}'
