#!/usr/bin/env bash
# bot-commit-selftest.sh — proves bot-commit.sh on THIS machine (mirrors claim-selftest.sh
# conventions: numbered cases, pass/fail counters, exit code = number of failed cases).
#
# Offline: `gh` is a PATH shim; git repos are throwaway tmp dirs. Covers the three identity
# paths (bot resolved / bot disabled / id-unresolvable fallback) plus the id cache.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_COMMIT="$HERE/bot-commit.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t bot-commit-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- gh shim: counts calls, answers `api users/<login>` with a fixed id ---------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SHIM'
#!/usr/bin/env bash
echo "1" >> "${GH_SHIM_CALLS:?}"
if [[ "$1" == "api" && "$2" == users/* ]]; then
  echo "424242"
  exit 0
fi
exit 1
SHIM
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_SHIM_CALLS="$TMP/gh-calls"
: > "$GH_SHIM_CALLS"

mkrepo() { # mkrepo <dir> [config-json]
  local dir="$1" cfg="${2:-}"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Repo Default"
  git -C "$dir" config user.email "default@example.com"
  [[ -n "$cfg" ]] && printf '%s' "$cfg" > "$dir/.claude/second-shift.config.json"
  echo hello > "$dir/f.txt"
  git -C "$dir" add f.txt
}

BOT_CFG='{"tracker":{"bot":{"enabled":true,"app":{"appName":"test-pipeline"}}}}'

# ---- Case 1: bot enabled → commit carries <app>[bot] identity -------------------
mkrepo "$TMP/r1" "$BOT_CFG"
unset SECOND_SHIFT_CONFIG || true
bash "$BOT_COMMIT" -C "$TMP/r1" -q -m "test: one" >/dev/null 2>&1
AUTHOR="$(git -C "$TMP/r1" log --format='%an <%ae>' -1)"
WANT="test-pipeline[bot] <424242+test-pipeline[bot]@users.noreply.github.com>"
[[ "$AUTHOR" == "$WANT" ]] \
  && pass "1 bot identity on commit ($AUTHOR)" \
  || fail "1 bot identity — got '$AUTHOR', want '$WANT'"

# ---- Case 2: id cache written and reused (gh called exactly once) ---------------
[[ -s "$TMP/r1/.git/second-shift-bot-user-id" ]] \
  && pass "2a bot user id cached in git common dir" \
  || fail "2a cache file missing"
echo more >> "$TMP/r1/f.txt"; git -C "$TMP/r1" add f.txt
bash "$BOT_COMMIT" -C "$TMP/r1" -q -m "test: two" >/dev/null 2>&1
CALLS="$(wc -l < "$GH_SHIM_CALLS" | tr -d ' ')"
[[ "$CALLS" == "1" ]] \
  && pass "2b second commit reuses cache (gh called once total)" \
  || fail "2b gh called $CALLS times, want 1"

# ---- Case 3: bot disabled / no config → repo default identity -------------------
mkrepo "$TMP/r3"
bash "$BOT_COMMIT" -C "$TMP/r3" -q -m "test: default" >/dev/null 2>&1
AUTHOR3="$(git -C "$TMP/r3" log --format='%an <%ae>' -1)"
[[ "$AUTHOR3" == "Repo Default <default@example.com>" ]] \
  && pass "3 no config → repo default identity" \
  || fail "3 got '$AUTHOR3', want repo default"

# ---- Case 4: unresolvable id → warn + repo default (never a fabricated email) ---
mkrepo "$TMP/r4" '{"tracker":{"bot":{"enabled":true,"app":{"appName":"no-such-app"}}}}'
cat > "$TMP/bin/gh" <<'SHIM'
#!/usr/bin/env bash
exit 1
SHIM
chmod +x "$TMP/bin/gh"
ERR="$(bash "$BOT_COMMIT" -C "$TMP/r4" -q -m "test: fallback" 2>&1 >/dev/null || true)"
AUTHOR4="$(git -C "$TMP/r4" log --format='%an <%ae>' -1)"
[[ "$AUTHOR4" == "Repo Default <default@example.com>" ]] \
  && pass "4a unresolvable id → repo default identity" \
  || fail "4a got '$AUTHOR4', want repo default"
grep -q "could not resolve bot user id" <<< "$ERR" \
  && pass "4b fallback is noisy (stderr WARN)" \
  || fail "4b no WARN on stderr — silent fallback"

echo ""
echo "[bot-commit-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
