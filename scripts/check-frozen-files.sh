#!/usr/bin/env bash
# check-frozen-files.sh — the PR-time inverse of the old version-bump discipline (#119).
#
# Under release-time derivation, feature PRs must NOT write the release-owned files:
# CHANGELOG.md and any plugins/*/.claude-plugin/plugin.json `version` field are computed
# by scripts/derive-release.sh on the release PR (branch release/next). A feature PR that
# touches them re-creates the every-PR-conflicts-with-every-PR problem this repo removed.
#
# ci.yml runs this on pull_request only, and skips it on the release branch
# (github.head_ref == 'release/next') — the release PR is the one legitimate writer.
# Non-version plugin.json edits (description, etc.) pass.
#
# Usage: check-frozen-files.sh <base-ref>   (e.g. origin/main)
# Exit 0 = clean; 1 = a frozen file is modified; 2 = usage/environment error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:?usage: check-frozen-files.sh <base-ref>}"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "[frozen-files] cannot resolve merge-base of $BASE and HEAD" >&2; exit 2; }

fails=0

if ! git diff --quiet "$MERGE_BASE"..HEAD -- CHANGELOG.md 2>/dev/null; then
  echo "[frozen-files] ✗ CHANGELOG.md is release-owned — it is generated on the release PR by scripts/derive-release.sh. Put migration prose in a 'Changelog:' commit trailer instead (docs/releasing.md)." >&2
  fails=$((fails + 1))
fi

for manifest in $(git diff --name-only "$MERGE_BASE"..HEAD -- 'plugins/*/.claude-plugin/plugin.json' 2>/dev/null); do
  old_ver="$(git show "$MERGE_BASE:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  new_ver="$(git show "HEAD:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  if [[ -n "$old_ver" && "$old_ver" != "$new_ver" ]]; then
    echo "[frozen-files] ✗ $manifest: version $old_ver → $new_ver — version fields are release-owned (derived on the release PR). Revert the bump; the release workflow computes it." >&2
    fails=$((fails + 1))
  fi
done

if [[ "$fails" -gt 0 ]]; then
  echo "[frozen-files] $fails frozen-file modification(s). See docs/releasing.md." >&2
  exit 1
fi
echo "[frozen-files] clean — no release-owned files modified."
