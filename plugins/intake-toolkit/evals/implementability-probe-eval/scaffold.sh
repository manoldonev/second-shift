#!/usr/bin/env bash
# Fills the eval workspace, the current directory, with a snapshot of this repo at a pinned commit
# and three fixture files under docs/plans/: the ticket, its decision record, and interview notes
# that the session is not handed. The runner starts it with no arguments and only PATH from the
# outer shell, so the repo is found from this file's own path.
#
# The snapshot drops every path that would hand a session the answer key or the probe's rules:
# .claude/, docs/plans/ (records that name the key files), this plugin's evals/, the probe's agent
# file, and skills/intake/, which restates the rules the graders score.
#
# The fixture files are copied one by one, by name. The answer keys stay behind.
#
# SNAPSHOT_REPO and SNAPSHOT_REF replace the repo and the commit. Only the selftest sets them.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SNAPSHOT_REPO:-$CASE_DIR}"
REF="${SNAPSHOT_REF:-b2b4f6e9}"
SLUG="ledger-lint-json"

die() { echo "scaffold: $1" >&2; exit 1; }

TOP="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repo: $REPO"
git -C "$TOP" cat-file -e "$REF^{commit}" 2>/dev/null \
  || die "$TOP does not hold commit $REF; a shallow clone needs its full history fetched"

git -C "$TOP" archive --format=tar "$REF" -- ':(top)' \
    ':(top,exclude).claude' \
    ':(top,exclude)docs/plans' \
    ':(top,exclude)plugins/intake-toolkit/evals' \
    ':(top,exclude)plugins/intake-toolkit/skills/intake' \
    ':(top,exclude)plugins/intake-toolkit/agents/implementability-probe.md' \
  | tar -xf -

mkdir -p docs/plans
cp "$CASE_DIR/fixtures/underspecified-spec.md" "docs/plans/$SLUG-ticket.md"
cp "$CASE_DIR/fixtures/planted-record.md" "docs/plans/$SLUG-decisions.md"
cp "$CASE_DIR/fixtures/interview-notes.md" "docs/plans/$SLUG-interview-notes.md"
