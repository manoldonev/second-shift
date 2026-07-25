#!/usr/bin/env bash
# check-lockstep-pairs-selftest.sh — verifies check-lockstep-pairs.sh actually catches drift.
#
# The mutation idiom (per scripts/check-intake-tracker-namespaces-selftest.sh): green on the
# real tree, RED after a sed mutation of one leg. A guard that has never been observed
# failing is indistinguishable from one that cannot fail — which is precisely the
# prose-presence class this script's subject replaces.
#
# Runs against a throwaway COPY of the tree, so mutations never touch the working tree.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECKER="$HERE/check-lockstep-pairs.sh"
MANIFEST="$HERE/lockstep-manifest.tsv"

[[ -x "$CHECKER" ]] || { echo "[lockstep-selftest] FATAL: $CHECKER not executable"; exit 99; }
[[ -f "$MANIFEST" ]] || { echo "[lockstep-selftest] FATAL: $MANIFEST missing"; exit 99; }

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t lockstep-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM

run_checker() { bash "$CHECKER" "$1/scripts/lockstep-manifest.tsv" "$1" >/dev/null 2>&1; echo $?; }

echo "[lockstep-selftest]"

# ---- (a) green on the real tree -------------------------------------------------------
rc=$(bash "$CHECKER" "$MANIFEST" "$ROOT" >/dev/null 2>&1; echo $?)
[[ "$rc" -eq 0 ]] \
  && ok "(a) real tree is green (every manifest pair agrees)" \
  || bad "(a) real tree is RED — rc=$rc; run 'bash scripts/check-lockstep-pairs.sh' for the drift"

# Build the mutation sandbox once: copy only what the manifest legs need.
SANDBOX="$TMP/tree"
mkdir -p "$SANDBOX/scripts"
cp "$MANIFEST" "$SANDBOX/scripts/"
# Only the two path columns are needed here; the relation/anchor columns are read into
# throwaway names so the row still splits on the right field boundaries.
# shellcheck disable=SC2034 # _relation/_aa/_ab are positional placeholders, not dead code
while IFS=$'\t' read -r pair _relation fa _aa fb _ab; do
  case "${pair:-}" in ''|'#'*) continue ;; esac
  [[ -n "${fb:-}" ]] || continue
  for f in "$fa" "$fb"; do
    mkdir -p "$SANDBOX/$(dirname "$f")"
    cp "$ROOT/$f" "$SANDBOX/$f"
  done
done < "$MANIFEST"

rc=$(run_checker "$SANDBOX")
[[ "$rc" -eq 0 ]] \
  && ok "(b) sandbox copy reproduces the green baseline" \
  || bad "(b) sandbox is RED before any mutation — rc=$rc (copy is incomplete)"

# ---- (c) verbatim drift is caught -----------------------------------------------------
# Mutate ONE leg of the FINDINGS_SCHEMA pair: flip a severity enum value.
TARGET="$SANDBOX/plugins/dev-pipeline/skills/run/workflows/stall-probe.mjs"
sed "s/'blocker', 'major', 'minor', 'nit'/'blocker', 'major', 'minor', 'trivial'/" "$TARGET" > "$TARGET.m" && mv "$TARGET.m" "$TARGET"
if grep -q "'trivial'" "$TARGET"; then
  rc=$(run_checker "$SANDBOX")
  [[ "$rc" -ne 0 ]] \
    && ok "(c) verbatim: a one-token drift in stall-probe.mjs FINDINGS_SCHEMA goes RED (rc=$rc)" \
    || bad "(c) verbatim drift NOT caught — the guard cannot fail"
  cp "$ROOT/plugins/dev-pipeline/skills/run/workflows/stall-probe.mjs" "$TARGET"   # restore
else
  bad "(c) mutation did not apply — the sed anchor has moved; fix this selftest"
fi

# ---- (d) subset-of violation is caught ------------------------------------------------
# Add a token to the SUBSET leg that the canonical enum does not carry.
TARGET="$SANDBOX/plugins/dev-pipeline/skills/run/tools/plan-lint.sh"
sed "s/HUMAN_PROVENANCE='user-answered|user-delegated'/HUMAN_PROVENANCE='user-answered|user-delegated|invented-value'/" "$TARGET" > "$TARGET.m" && mv "$TARGET.m" "$TARGET"
if grep -q 'invented-value' "$TARGET"; then
  rc=$(run_checker "$SANDBOX")
  [[ "$rc" -ne 0 ]] \
    && ok "(d) subset-of: a token absent from the canonical enum goes RED (rc=$rc)" \
    || bad "(d) subset-of violation NOT caught"
  cp "$ROOT/plugins/dev-pipeline/skills/run/tools/plan-lint.sh" "$TARGET"   # restore
else
  bad "(d) mutation did not apply — the sed anchor has moved; fix this selftest"
fi

# ---- (e) subset-of does NOT fire on a legitimate narrowing ----------------------------
# The canonical may carry values the subset omits — that is the whole point of the relation.
rc=$(run_checker "$SANDBOX")
[[ "$rc" -eq 0 ]] \
  && ok "(e) subset-of tolerates the legitimate narrowing (restored tree green again)" \
  || bad "(e) restored tree is RED — a restore failed, or subset-of rejects a valid subset"

# ---- (f) a REMOVED marker is a failure, never a silent skip ---------------------------
TARGET="$SANDBOX/plugins/dev-pipeline/skills/run/state-schema.md"
sed 's/<!-- LOCKSTEP-BEGIN ac-id-rule -->//' "$TARGET" > "$TARGET.m" && mv "$TARGET.m" "$TARGET"
if ! grep -q 'LOCKSTEP-BEGIN ac-id-rule' "$TARGET"; then
  rc=$(run_checker "$SANDBOX")
  [[ "$rc" -ne 0 ]] \
    && ok "(f) a deleted marker FAILS the pair (a silently-unchecked pair is the bug class)" \
    || bad "(f) deleted marker was treated as a skip — the guard can be disabled by deletion"
  cp "$ROOT/plugins/dev-pipeline/skills/run/state-schema.md" "$TARGET"   # restore
else
  bad "(f) mutation did not apply — the sed anchor has moved; fix this selftest"
fi

# ---- (g) a manifest row naming a missing file fails ------------------------------------
printf 'ghost\tverbatim\tno/such/file.sh\tx\tno/such/other.sh\tx\n' >> "$SANDBOX/scripts/lockstep-manifest.tsv"
rc=$(run_checker "$SANDBOX")
[[ "$rc" -ne 0 ]] \
  && ok "(g) a manifest row pointing at a missing file FAILS (rc=$rc)" \
  || bad "(g) missing-file row silently ignored"

echo "[lockstep-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
