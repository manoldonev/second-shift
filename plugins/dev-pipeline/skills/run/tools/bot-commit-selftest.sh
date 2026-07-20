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

# ---- Case 3: bot disabled / no config → repo default identity + WARN (AC-2) ------
mkrepo "$TMP/r3"
ERR3="$(bash "$BOT_COMMIT" -C "$TMP/r3" -q -m "test: default" 2>&1 >/dev/null || true)"
AUTHOR3="$(git -C "$TMP/r3" log --format='%an <%ae>' -1)"
[[ "$AUTHOR3" == "Repo Default <default@example.com>" ]] \
  && pass "3a no config → repo default identity" \
  || fail "3a got '$AUTHOR3', want repo default"
grep -q "no second-shift config found" <<< "$ERR3" \
  && pass "3b no-config fallback is loud (AC-2)" \
  || fail "3b silent no-config fallback — want a stderr WARN"

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

# ---- Case 5: gitignored config + worktree, no env → bot identity (AC-1) ----------
# THE regression test for #110. Unlike cases 1-4 (single `git init` repos) this builds a real
# main-checkout + worktree pair with the config GITIGNORED, reproducing the production setup:
# the config never lands in the worktree, so resolution must reach the main checkout via
# --git-common-dir. Against the pre-#110 --show-toplevel anchor this case fails.
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

mkrepo "$TMP/r5" "$BOT_CFG"
printf '.claude/second-shift.config.json\n' > "$TMP/r5/.gitignore"
git -C "$TMP/r5" add .gitignore
git -C "$TMP/r5" -c user.name=Seed -c user.email=seed@example.com commit -q -m "seed"
git -C "$TMP/r5" worktree add -q -b wt5 "$TMP/r5-wt" >/dev/null 2>&1

[[ ! -f "$TMP/r5-wt/.claude/second-shift.config.json" ]] \
  && pass "5a config is absent from the worktree (reproduces the bug's precondition)" \
  || fail "5a config unexpectedly present in worktree — case does not reproduce #110"

echo wt > "$TMP/r5-wt/w.txt"; git -C "$TMP/r5-wt" add w.txt
ERR5="$(bash "$BOT_COMMIT" -C "$TMP/r5-wt" -q -m "test: worktree" 2>&1 >/dev/null || true)"
AUTHOR5="$(git -C "$TMP/r5-wt" log --format='%an <%ae>' -1)"
[[ "$AUTHOR5" == "$WANT" ]] \
  && pass "5b worktree + gitignored config, no env → bot identity (AC-1)" \
  || fail "5b got '$AUTHOR5', want '$WANT'"
grep -q "bot-commit] WARN" <<< "$ERR5" \
  && fail "5c unexpected WARN on the success path: $ERR5" \
  || pass "5c success path is silent (no WARN)"

# ---- Case 6: explicit enabled:false → repo default + the bot-disabled WARN (AC-2) -
mkrepo "$TMP/r6" '{"tracker":{"bot":{"enabled":false,"app":{"appName":"test-pipeline"}}}}'
ERR6="$(bash "$BOT_COMMIT" -C "$TMP/r6" -q -m "test: disabled" 2>&1 >/dev/null || true)"
AUTHOR6="$(git -C "$TMP/r6" log --format='%an <%ae>' -1)"
[[ "$AUTHOR6" == "Repo Default <default@example.com>" ]] \
  && pass "6a bot disabled → repo default identity (AC-2)" \
  || fail "6a got '$AUTHOR6', want repo default"
grep -q "bot disabled in" <<< "$ERR6" \
  && pass "6b deliberate-disable WARN is distinct from the no-config WARN (AC-2)" \
  || fail "6b wrong or missing WARN: $ERR6"

# ---- Case 7: -C a non-repo dir → our WARN is absent (no consumer to be wrong about) -
mkdir -p "$TMP/notarepo"
ERR7="$(bash "$BOT_COMMIT" -C "$TMP/notarepo" -q -m "test: nonrepo" 2>&1 >/dev/null || true)"
grep -q "bot-commit] WARN" <<< "$ERR7" \
  && fail "7 WARN emitted for a non-repo dir: $ERR7" \
  || pass "7 non-repo dir → no bot-commit WARN (AC-2)"

echo ""
echo "[bot-commit-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
