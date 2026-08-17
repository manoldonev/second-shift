#!/usr/bin/env bash
# resolve-sibling.sh — the sibling-plugin file resolver (#419), extracted so a second caller
# at a DIFFERENT depth (lean-gate.sh, #562) reuses the ladder instead of re-deriving it.
#
# WHY EXTRACTED: the function body below depends only on two caller-supplied globals,
# SCRIPT_DIR and PLUGINS_DIR — the hop count from a caller's own file to its plugin root is
# what legitimately differs by depth (pipeline-doctor.sh sits one level under its plugin root,
# lean-gate.sh sits two), and that arithmetic stays the CALLER's, computed the same way
# pipeline-doctor.sh already does below. What must not differ is the ladder itself: monorepo
# path, then this plugin's own version in the cache, then the newest sibling version carrying
# the file. A caller sources this file, computes its own SCRIPT_DIR/PLUGIN_DIR/PLUGINS_DIR at
# its own depth, then calls resolve_sibling — see pipeline-doctor.sh's own three lines above
# its `. .../resolve-sibling.sh` for the pattern, and lean-gate.sh's resolve_ledger_lint() for
# a caller one level deeper.
#
#   monorepo checkout:            <PLUGINS_DIR>/<sib>/<rel>
#   version-keyed install cache:  <cacheroot>/<sib>/<ver>/<rel>   (cacheroot = dirname of PLUGINS_DIR)
#
# Tries the monorepo path, then this plugin's own version in the cache, then the newest sibling
# version that has the file. Prints the first hit; returns non-zero if none exists.
# >>> resolve-sibling
resolve_sibling() { # $1 = sibling plugin name, $2 = path under that plugin
  local sib="$1" rel="$2" cand v cacheroot myver
  cand="$PLUGINS_DIR/$sib/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  cacheroot="$(cd "$PLUGINS_DIR/.." 2>/dev/null && pwd)" || return 1
  myver="$(basename "$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)")"
  cand="$cacheroot/$sib/$myver/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  # Highest version FIRST — this loop takes the first hit, so the sort must descend. Per-key
  # `r` modifiers, not a global `-r`: BSD sort ignores the global flag once per-key modifiers
  # are present, which would walk the versions ASCENDING and return the oldest sibling. The
  # plain `sort -r` this replaces was lexical, and ranked 9.0.0 above 10.0.0.
  # shellcheck disable=SC2012  # version dirs are alphanumeric (X.Y.Z); ls is safe and 3.2-portable here
  for v in $(ls -1 "$cacheroot/$sib" 2>/dev/null | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
    cand="$cacheroot/$sib/$v/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}
# <<< resolve-sibling
