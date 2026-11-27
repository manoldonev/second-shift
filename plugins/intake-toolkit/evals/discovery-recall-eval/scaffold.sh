#!/usr/bin/env bash
# Fills the eval workspace, the current directory, with TICKET.md and a snapshot of this repo at
# the commit the fixture ticket was filed against. The runner starts it with no arguments and only
# PATH from the outer shell, so the repo is found from this file's own path.
#
# The snapshot drops .claude/ and plugins/intake-toolkit/: the runner loads the plugin under test,
# and an old copy of the rules on disk would be read by both arms. Dropping plugins/intake-toolkit/
# also keeps this case's answer key out of the workspace.
#
# SNAPSHOT_REPO and SNAPSHOT_REF replace the repo and the commit. Only the selftest sets them.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SNAPSHOT_REPO:-$CASE_DIR}"
REF="${SNAPSHOT_REF:-3f3e9af5}"

die() { echo "scaffold: $1" >&2; exit 1; }

TOP="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repo: $REPO"
git -C "$TOP" cat-file -e "$REF^{commit}" 2>/dev/null \
  || die "$TOP does not hold commit $REF; a shallow clone needs its full history fetched"

git -C "$TOP" archive --format=tar "$REF" -- ':(top)' ':(top,exclude).claude' ':(top,exclude)plugins/intake-toolkit' \
  | tar -xf -
cp "$CASE_DIR/fixture/TICKET.md" ./TICKET.md
