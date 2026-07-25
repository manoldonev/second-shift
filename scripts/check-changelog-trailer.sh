#!/usr/bin/env bash
# check-changelog-trailer.sh — PR-time guard: a plugins/** PR must carry changelog intent (#119).
#
# The release CHANGELOG is derived from 'Changelog:' commit trailers (grep-anywhere in the
# squashed body — this repo's squash prefill is COMMIT_MESSAGES, so branch commit bodies
# survive the merge by default). A PR that touches plugins/** must have at least one commit
# whose body carries a 'Changelog:' line — either prose for the release notes, or the
# explicit opt-out 'Changelog: none'. No trailer at all -> the release entry silently
# degrades to a bare subject line, which is exactly the failure this gate makes loud.
#
# ci.yml runs this on pull_request only, and skips it on the release branch
# (github.head_ref == 'release/next').
#
# Usage: check-changelog-trailer.sh <base-ref>   (e.g. origin/main)
# Exit 0 = trailer present or no plugins/** change; 1 = missing; 2 = usage error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:?usage: check-changelog-trailer.sh <base-ref>}"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "[changelog-trailer] cannot resolve merge-base of $BASE and HEAD" >&2; exit 2; }

if git diff --quiet "$MERGE_BASE"..HEAD -- 'plugins/' 2>/dev/null; then
  echo "[changelog-trailer] no plugins/** change — trailer not required."
  exit 0
fi

# grep -c, NOT grep -q: -q exits at the first match, git log takes SIGPIPE (141) on its
# next write, and pipefail turns that into pipeline failure — so the gate reported "no
# trailer" precisely when a trailer was found EARLY in a LONG log (first observed on a
# 13-commit PR; 1-3-commit PRs fit one write and never tripped it). -c consumes the whole
# stream (producer never SIGPIPEs) and exits 0 iff at least one line matches.
if git log "$MERGE_BASE..HEAD" --format=%B | grep -cE '^Changelog:' >/dev/null; then
  echo "[changelog-trailer] OK — a 'Changelog:' trailer is present."
  exit 0
fi

cat >&2 <<'EOF'
[changelog-trailer] ✗ This PR touches plugins/** but no commit carries a 'Changelog:' trailer.
[changelog-trailer]   Add one to a commit body (it becomes the release-notes entry):
[changelog-trailer]     Changelog: <what changed for consumers>.
[changelog-trailer]       Migration: <what a consumer must do, if anything>.
[changelog-trailer]   Or opt out explicitly when nothing is consumer-visible:
[changelog-trailer]     Changelog: none
[changelog-trailer]   (Amend the last commit: git commit --amend, add the line to the body.)
EOF
exit 1
