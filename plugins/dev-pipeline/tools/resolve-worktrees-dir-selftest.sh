#!/usr/bin/env bash
# resolve-worktrees-dir-selftest.sh — behavioral selftest for tools/resolve-worktrees-dir.sh.
#
# Fixture configs are written to a per-run mktemp dir (parallel-safe under -P 4, per
# CLAUDE.md's verification recipe). Exit code = number of failed checks (repo selftest
# convention).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/resolve-worktrees-dir.sh"

[[ -x "$TOOL" ]] || { echo "[resolve-worktrees-dir-selftest] FATAL: $TOOL not executable"; exit 99; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "== resolve-worktrees-dir.sh =="

# ---------------------------------------------------------------------------
# key present — returned verbatim (AC-1)
# ---------------------------------------------------------------------------
CFG_SET="$TMP/set.json"
cat > "$CFG_SET" <<'JSON'
{
  "topology": {
    "repos": {
      "acme": { "path": ".", "baseBranch": "main", "worktreesDir": "../custom-worktrees" }
    }
  }
}
JSON

got="$(bash "$TOOL" "$CFG_SET" 2>/dev/null)"; rc=$?
[[ "$rc" == "0" && "$got" == "../custom-worktrees" ]] \
  && pass "(rwd1) worktreesDir configured → returned verbatim, exit 0 (AC-1)" \
  || fail "(rwd1) configured key → got '$got' rc=$rc (want '../custom-worktrees', 0)"

# ---------------------------------------------------------------------------
# key absent — the documented default (AC-1)
# ---------------------------------------------------------------------------
CFG_ABSENT="$TMP/absent.json"
cat > "$CFG_ABSENT" <<'JSON'
{
  "topology": {
    "repos": {
      "acme": { "path": ".", "baseBranch": "main" }
    }
  }
}
JSON

got="$(bash "$TOOL" "$CFG_ABSENT" 2>/dev/null)"; rc=$?
[[ "$rc" == "0" && "$got" == "../acme-worktrees" ]] \
  && pass "(rwd2) worktreesDir absent → documented default '../<repo>-worktrees', exit 0 (AC-1)" \
  || fail "(rwd2) absent key → got '$got' rc=$rc (want '../acme-worktrees', 0)"

# ---------------------------------------------------------------------------
# empty-string key — same as absent, not taken literally (AC-1)
# ---------------------------------------------------------------------------
CFG_EMPTY="$TMP/empty.json"
cat > "$CFG_EMPTY" <<'JSON'
{
  "topology": {
    "repos": {
      "acme": { "path": ".", "baseBranch": "main", "worktreesDir": "" }
    }
  }
}
JSON

got="$(bash "$TOOL" "$CFG_EMPTY" 2>/dev/null)"; rc=$?
[[ "$rc" == "0" && "$got" == "../acme-worktrees" ]] \
  && pass "(rwd3) worktreesDir explicitly empty string → same default, not composed literally (AC-1)" \
  || fail "(rwd3) empty-string key → got '$got' rc=$rc (want '../acme-worktrees', 0)"

# ---------------------------------------------------------------------------
# unresolvable host — no topology.repos entry with path "." — fails closed (AC-4)
# ---------------------------------------------------------------------------
CFG_NOHOST="$TMP/nohost.json"
cat > "$CFG_NOHOST" <<'JSON'
{
  "topology": {
    "repos": {
      "backend": { "path": "services/backend", "baseBranch": "main" }
    }
  }
}
JSON

out="$(bash "$TOOL" "$CFG_NOHOST" 2>&1 >/dev/null)"; got="$(bash "$TOOL" "$CFG_NOHOST" 2>/dev/null)"; rc=$?
[[ "$rc" != "0" && -z "$got" && "$out" == *"no topology.repos entry with path"* ]] \
  && pass "(rwd4) no host repo entry → non-zero exit, empty stdout, named stderr reason — never a silent empty result (AC-1, AC-4)" \
  || fail "(rwd4) no host entry → rc=$rc got='$got' stderr='$out' (want non-zero, empty, reason)"

# ---------------------------------------------------------------------------
# explicit repo id absent from config — fails closed the same way (AC-1, be-fe-pair /
# preflight.sh caller shape — they pass an explicit id, not host auto-detect)
# ---------------------------------------------------------------------------
out="$(bash "$TOOL" "$CFG_NOHOST" frontend 2>&1 >/dev/null)"; got="$(bash "$TOOL" "$CFG_NOHOST" frontend 2>/dev/null)"; rc=$?
[[ "$rc" != "0" && -z "$got" && "$out" == *'no topology.repos."frontend" entry'* ]] \
  && pass "(rwd5) explicit repo id not in config → non-zero exit, empty stdout, named reason (AC-1, AC-4)" \
  || fail "(rwd5) unknown explicit repo id → rc=$rc got='$got' stderr='$out'"

# ---------------------------------------------------------------------------
# explicit repo id present — used directly, no host auto-detect needed (be-fe-pair /
# preflight.sh caller shape)
# ---------------------------------------------------------------------------
CFG_PAIR="$TMP/pair.json"
cat > "$CFG_PAIR" <<'JSON'
{
  "topology": {
    "repos": {
      "backend": { "path": "services/backend", "baseBranch": "alpha", "worktreesDir": "../be-worktrees" },
      "frontend": { "path": "services/frontend", "baseBranch": "main" }
    }
  }
}
JSON

got="$(bash "$TOOL" "$CFG_PAIR" backend 2>/dev/null)"; rc=$?
[[ "$rc" == "0" && "$got" == "../be-worktrees" ]] \
  && pass "(rwd6) explicit repo id, key configured → returned verbatim (AC-1)" \
  || fail "(rwd6) explicit repo id configured → got '$got' rc=$rc (want '../be-worktrees', 0)"

got="$(bash "$TOOL" "$CFG_PAIR" frontend 2>/dev/null)"; rc=$?
[[ "$rc" == "0" && "$got" == "../frontend-worktrees" ]] \
  && pass "(rwd7) explicit repo id, key absent → default keyed off THAT repo id, not the host (AC-1)" \
  || fail "(rwd7) explicit repo id default → got '$got' rc=$rc (want '../frontend-worktrees', 0)"

# ---------------------------------------------------------------------------
# missing config file / missing args — usage-level fail closed
# ---------------------------------------------------------------------------
rc=$(bash "$TOOL" "$TMP/does-not-exist.json" >/dev/null 2>&1; echo $?)
[[ "$rc" != "0" ]] && pass "(rwd8) config file not found → non-zero exit" \
  || fail "(rwd8) missing config file → rc=$rc (want non-zero)"

rc=$(bash "$TOOL" >/dev/null 2>&1; echo $?)
[[ "$rc" != "0" ]] && pass "(rwd9) no arguments → non-zero exit (usage)" \
  || fail "(rwd9) no args → rc=$rc (want non-zero)"

echo
echo "resolve-worktrees-dir-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
