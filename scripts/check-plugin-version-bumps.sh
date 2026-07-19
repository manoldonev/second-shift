#!/usr/bin/env bash
# check-plugin-version-bumps.sh — enforce the version-bump discipline.
#
# WHY (Phase 2 caution): `claude plugin update` is keyed on the manifest `version`
# field — a plugin whose content changed but whose plugin.json version did NOT is
# invisible to consumers ("already at the latest version"). So: any plugin whose
# CONTENT differs from the most recent release tag MUST carry a bumped
# .claude-plugin/plugin.json version.
#
# Compares each plugins/<name>/ tree against the latest reachable tag. No prior tag
# (the very first release) → nothing to compare, pass. Runs in marketplace CI
# (model-free). Exit 0 = all good; 1 = a plugin changed without a version bump.
#
# CALL SITE (#119): runs ONLY on the release PR (ci.yml release-pr-gates, branch
# release/next) — feature PRs no longer bump versions (scripts/check-frozen-files.sh
# enforces the inverse there); the bumps this script verifies are the ones
# scripts/derive-release.sh derived onto the release PR.
#
# Usage: check-plugin-version-bumps.sh [base-ref]
#   base-ref defaults to the latest tag reachable from HEAD (excluding HEAD's own
#   tag, so the check is meaningful on the release commit itself).
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  # Latest tag strictly before HEAD; empty if none exists yet.
  BASE="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
  [[ -z "$BASE" ]] && BASE="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi

if [[ -z "$BASE" ]]; then
  echo "[version-bump] no prior release tag — first release, nothing to compare. PASS."
  exit 0
fi

echo "[version-bump] comparing plugin content against $BASE"
fails=0
for manifest in plugins/*/.claude-plugin/plugin.json; do
  plugdir="$(dirname "$(dirname "$manifest")")"
  name="$(basename "$plugdir")"
  # Content changed vs the base tag? (--quiet: exit 1 if differences exist.)
  if git diff --quiet "$BASE" -- "$plugdir" 2>/dev/null; then
    continue   # no content change → no bump required
  fi
  new_ver="$(jq -r '.version // ""' "$manifest")"
  old_ver="$(git show "$BASE:$manifest" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || true)"
  if [[ -z "$old_ver" ]]; then
    echo "[version-bump] $name: new plugin since $BASE (version $new_ver) — OK"
    continue
  fi
  if [[ "$new_ver" == "$old_ver" ]]; then
    echo "[version-bump] ✗ $name: content changed since $BASE but version is still $new_ver — bump .claude-plugin/plugin.json" >&2
    fails=$((fails + 1))
  else
    echo "[version-bump] ✓ $name: $old_ver → $new_ver"
  fi
done

if [[ "$fails" -gt 0 ]]; then
  echo "[version-bump] $fails plugin(s) changed without a version bump" >&2
  exit 1
fi
echo "[version-bump] all changed plugins carry a version bump. PASS."
