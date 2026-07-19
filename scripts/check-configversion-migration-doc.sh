#!/usr/bin/env bash
# check-configversion-migration-doc.sh — a schema-breaking change ships its upgrade doc (#119).
#
# docs/migrations/README.md's contract: a breaking config-schema change is a major release +
# a `configVersion` bump + `docs/migrations/vN-to-vN+1.md`. The migration filename is
# configVersion-indexed, so the gate keys on configVersion — NOT on the derived major bump.
# (A plugin-level breaking change that does not touch the schema carries its guidance in the
# `BREAKING CHANGE:` trailer instead; there is no vN-to-vN+1 doc to name for it.)
#
# Runs on the release PR only (ci.yml release-pr-gates).
#
# Usage: check-configversion-migration-doc.sh [base-ref]
#   base-ref defaults to the latest tag reachable from HEAD.
# Exit 0 = no schema change, or the doc exists; 1 = doc missing; 2 = usage/environment error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

SCHEMA="schema/second-shift.config.schema.json"
BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  BASE="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
if [[ -z "$BASE" ]]; then
  echo "[configversion] no prior release tag — nothing to compare. PASS."
  exit 0
fi

OLD="$(git show "$BASE:$SCHEMA" 2>/dev/null | jq -r '.properties.configVersion.const // empty' 2>/dev/null || true)"
NEW="$(jq -r '.properties.configVersion.const // empty' "$SCHEMA" 2>/dev/null || true)"

if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "[configversion] cannot read configVersion at $BASE or HEAD — treating as no change. PASS." >&2
  exit 0
fi

if [[ "$OLD" == "$NEW" ]]; then
  echo "[configversion] unchanged ($NEW) — no migration doc required. PASS."
  exit 0
fi

DOC="docs/migrations/v${OLD}-to-v${NEW}.md"
if [[ -f "$DOC" ]]; then
  echo "[configversion] ✓ $OLD → $NEW with $DOC present."
  exit 0
fi

echo "[configversion] ✗ configVersion $OLD → $NEW without $DOC" >&2
echo "[configversion]   The migration contract (docs/migrations/README.md) requires an upgrade doc for a schema-breaking change." >&2
exit 1
