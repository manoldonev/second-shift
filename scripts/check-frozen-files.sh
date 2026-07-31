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
# The script has TWO tiers, and the distinction is load-bearing:
#
#   HARD rows (CHANGELOG.md, plugin.json `version`) — exit 1. CI is the enforcer; a
#   feature PR has no legitimate reason to write them.
#
#   ADVISORY rows (.github/workflows/**) — print and continue, never exit 1. The
#   intended enforcer is a server-side push ruleset, NOT this script: this script runs
#   as a step inside the very workflow it would freeze, so on a same-repo PR an agent
#   could neuter the step while keeping the required check green. A hard row here would
#   also red-line every sanctioned workflow change with no escape, since `pr-gates` is
#   required with no bypass actors. See docs/pipeline-manifesto.md's T0 note — which
#   also records that push rulesets are unavailable on this (public, user-owned) repo,
#   so the workflow freeze is currently procedural and this row is the only signal.
#
# Usage: check-frozen-files.sh <base-ref>   (e.g. origin/main)
# Exit 0 = clean, possibly with advisory notices; 1 = a frozen file is modified;
#          2 = usage/environment error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:?usage: check-frozen-files.sh <base-ref>}"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "[frozen-files] cannot resolve merge-base of $BASE and HEAD" >&2; exit 2; }

fails=0
advisories=0

# ADVISORY row — deliberately does NOT touch `fails`. See the tier note in the header.
workflow_edits="$(git diff --name-only "$MERGE_BASE"..HEAD -- '.github/workflows' 2>/dev/null)"
if [[ -n "$workflow_edits" ]]; then
  echo "[frozen-files] ⚠ advisory: this PR edits .github/workflows/** —"
  while IFS= read -r f; do echo "[frozen-files]     $f"; done <<< "$workflow_edits"
  echo "[frozen-files]   A workflow edit on a same-repo PR can neuter the very checks that judge it."
  echo "[frozen-files]   This row is fast feedback, not enforcement (docs/pipeline-manifesto.md, T0 note)."
  advisories=$((advisories + 1))
fi

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
if [[ "$advisories" -gt 0 ]]; then
  # Distinct from the bare "clean" line: a run that warned must not read as one that did not.
  echo "[frozen-files] clean — no release-owned files modified; $advisories advisory notice(s) above."
else
  echo "[frozen-files] clean — no release-owned files modified."
fi
