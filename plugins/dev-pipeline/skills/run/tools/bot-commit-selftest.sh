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
REAL_GIT="$(command -v git)"   # resolved BEFORE the shim dirs go on PATH (case 10g)
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

# ---- Case 8: $SECOND_SHIFT_CONFIG (candidate 1) wins over the -C dir config ------
# Candidate 1 has the highest precedence and is what operators/CI invoke directly, but
# every other positive case leaves it unset. Point it at a DIFFERENT appName than the
# repo's own config so the winner is unambiguous from the resulting identity alone.
mkrepo "$TMP/r8" '{"tracker":{"bot":{"enabled":true,"app":{"appName":"in-repo-app"}}}}'
mkdir -p "$TMP/override"
printf '%s' '{"tracker":{"bot":{"enabled":true,"app":{"appName":"override-app"}}}}' \
  > "$TMP/override/cfg.json"
AUTHOR8="$(SECOND_SHIFT_CONFIG="$TMP/override/cfg.json" \
  bash "$BOT_COMMIT" -C "$TMP/r8" -q -m "test: override" >/dev/null 2>&1; \
  git -C "$TMP/r8" log --format='%an' -1)"
[[ "$AUTHOR8" == "override-app[bot]" ]] \
  && pass "8 \$SECOND_SHIFT_CONFIG (candidate 1) outranks the -C dir config" \
  || fail "8 got '$AUTHOR8', want 'override-app[bot]' — candidate precedence is wrong"

# ---- Case 9: SECOND_SHIFT_REPO_ROOT moves the CONFIG root, NOT the id cache (D-7) --
# The override exists so a selftest can aim config resolution at a fixture; the bot-id
# cache must STAY on the real --git-common-dir (it needs a writable, worktree-shared git
# dir). Asserting both halves is the point — a "parity" implementation that moved the
# cache too would pass an identity-only check.
mkrepo "$TMP/r9"                     # deliberately NO config in the repo itself
mkdir -p "$TMP/fakeroot/.claude"
printf '%s' "$BOT_CFG" > "$TMP/fakeroot/.claude/second-shift.config.json"
rm -f "$TMP/r9/.git/second-shift-bot-user-id"
AUTHOR9="$(SECOND_SHIFT_REPO_ROOT="$TMP/fakeroot" \
  bash "$BOT_COMMIT" -C "$TMP/r9" -q -m "test: repo-root override" >/dev/null 2>&1; \
  git -C "$TMP/r9" log --format='%an' -1)"
[[ "$AUTHOR9" == "test-pipeline[bot]" ]] \
  && pass "9a SECOND_SHIFT_REPO_ROOT redirects config resolution (D-7)" \
  || fail "9a got '$AUTHOR9', want 'test-pipeline[bot]' — override did not move the config root"
[[ -s "$TMP/r9/.git/second-shift-bot-user-id" ]] \
  && pass "9b id cache stayed in the REAL git common dir, not the override (D-7)" \
  || fail "9b cache missing from \$TMP/r9/.git — the override wrongly moved the cache too"
[[ ! -e "$TMP/fakeroot/second-shift-bot-user-id" && ! -e "$TMP/fakeroot/.git" ]] \
  && pass "9c override dir received no cache write (D-7)" \
  || fail "9c cache leaked into the override root"

# ---- Case 10: AI co-authorship trailer -------------------------------------------
# On a bot-DISABLED consumer the author is the operator, so this trailer is the only signal
# that a run wrote the commit. Both directions are asserted because the failure modes are
# opposite and both are silent: no trailer at all (what shipped for a full run across two
# consumer repos), or a caller's precise model name shadowed by a duplicate generic one.
mkrepo "$TMP/r10" '{"tracker":{"bot":{"enabled":false,"app":{"appName":"test-pipeline"}}}}'
bash "$BOT_COMMIT" -C "$TMP/r10" -q -m "test: no caller trailer" >/dev/null 2>&1 || true
BODY10="$(git -C "$TMP/r10" log -1 --format='%B')"
grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" <<< "$BODY10" \
  && pass "10a absent caller trailer → generic Claude trailer added" \
  || fail "10a no co-authorship trailer on the commit: $BODY10"

# Caller wins: a session knows its own model, this wrapper cannot.
echo t10b > "$TMP/r10/b.txt"; git -C "$TMP/r10" add b.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q \
  -m "test: caller trailer" \
  -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" >/dev/null 2>&1 || true
BODY10B="$(git -C "$TMP/r10" log -1 --format='%B')"
COUNT10B="$(grep -ci "co-authored-by" <<< "$BODY10B" || true)"
{ [[ "$COUNT10B" == "1" ]] && grep -qi "Claude Opus 5" <<< "$BODY10B"; } \
  && pass "10b caller-supplied trailer preserved, not duplicated" \
  || fail "10b expected exactly 1 trailer naming the caller's model, got $COUNT10B: $BODY10B"

# ---- Cases 10c-10f: the routes an ARGUMENT SCAN cannot read ----------------------
# 10a/10b both carry the trailer state in -m arguments — the one route a scan of "$*" can see.
# -F, --amend and editor mode are where such a scan under-detects, and where a generic trailer
# lands beside the caller's precise one. The invariant is route-INDEPENDENT and is what these
# cases pin: exactly one Co-Authored-By on the resulting commit, naming the caller's model
# whenever the caller supplied one.
ca_count() { grep -ci "co-authored-by" <<< "$1" || true; }

printf 'test: -F route\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$TMP/msg10c.txt"
echo t10c > "$TMP/r10/c.txt"; git -C "$TMP/r10" add c.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q -F "$TMP/msg10c.txt" >/dev/null 2>&1 || true
BODY10C="$(git -C "$TMP/r10" log -1 --format='%B')"
N10C="$(ca_count "$BODY10C")"
{ [[ "$N10C" == "1" ]] && grep -qi "Claude Opus 5" <<< "$BODY10C"; } \
  && pass "10c -F body's trailer preserved, not duplicated" \
  || fail "10c expected 1 trailer naming the caller's model, got $N10C: $BODY10C"

# --amend reuses the STORED message, unreadable from the argument list. Not hypothetical: this
# script's header documents `--amend --reset-author` through this helper as the repair path for a
# commit already mis-attributed to the operator.
bash "$BOT_COMMIT" -C "$TMP/r10" -q --amend --no-edit >/dev/null 2>&1 || true
BODY10D="$(git -C "$TMP/r10" log -1 --format='%B')"
N10D="$(ca_count "$BODY10D")"
{ [[ "$N10D" == "1" ]] && grep -qi "Claude Opus 5" <<< "$BODY10D"; } \
  && pass "10d --amend --no-edit does not duplicate the stored trailer" \
  || fail "10d expected 1 trailer after amend, got $N10D: $BODY10D"

# Editor mode: the message exists only in the editor buffer while the wrapper runs. Reached here
# through --amend, which is how it is reachable at all — a pipeline session never types into an
# editor. GIT_EDITOR exits without touching the buffer, i.e. the operator saved unchanged.
#
# MEASURED LIMIT, deliberate: git applies --trailer to the buffer BEFORE the editor opens, so a
# trailer typed IN the editor afterwards sits beside the generic one and no setting can dedupe it
# (measured: 2 either way). That is out of reach of this wrapper and unreachable from a
# non-interactive caller, so it is recorded rather than guarded — an editor case written that way
# would pass whether or not the dedup works, which is worse than no case at all.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/editor10e"
chmod +x "$TMP/bin/editor10e"
echo t10e > "$TMP/r10/e.txt"; git -C "$TMP/r10" add e.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q -m "test: editor route" \
  -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" >/dev/null 2>&1 || true
GIT_EDITOR="$TMP/bin/editor10e" bash "$BOT_COMMIT" -C "$TMP/r10" -q --amend >/dev/null 2>&1 || true
BODY10E="$(git -C "$TMP/r10" log -1 --format='%B')"
N10E="$(ca_count "$BODY10E")"
{ [[ "$N10E" == "1" ]] && grep -qi "Claude Opus 5" <<< "$BODY10E"; } \
  && pass "10e --amend through the editor buffer does not duplicate" \
  || fail "10e expected 1 trailer via the editor route, got $N10E: $BODY10E"

# Dedup must not have degraded into "never add on the routes the scan cannot read" — a -F body
# with NO trailer still earns the generic one. Absent this case, 10c-10e would pass equally well
# if the trailer were dropped outright on every such route.
printf 'test: -F route, no trailer\n' > "$TMP/msg10f.txt"
echo t10f > "$TMP/r10/f2.txt"; git -C "$TMP/r10" add f2.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q -F "$TMP/msg10f.txt" >/dev/null 2>&1 || true
BODY10F="$(git -C "$TMP/r10" log -1 --format='%B')"
grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" <<< "$BODY10F" \
  && pass "10f -F body without a trailer still earns the generic one" \
  || fail "10f no trailer added on the -F route: $BODY10F"

# ---- Case 10g: an unreadable `git --version` must not abort the commit ------------
# The trailer is optional; the commit is not. Reading the version through a PIPELINE under
# `set -euo pipefail` propagates a failing git and kills the wrapper before it ever reaches
# `git commit` — `2>/dev/null` hides the message, not the status. Scored on the OUTCOME (a commit
# exists), not on rc alone, so a wrapper that exits 0 without committing still fails.
mkdir -p "$TMP/gitshim"
cat > "$TMP/gitshim/git" <<SHIM
#!/usr/bin/env bash
[[ "\$1" == "--version" ]] && exit 3
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$TMP/gitshim/git"
mkrepo "$TMP/r10g" '{"tracker":{"bot":{"enabled":false,"app":{"appName":"test-pipeline"}}}}'
BEFORE10G="$(git -C "$TMP/r10g" rev-list --count HEAD 2>/dev/null || echo 0)"
set +e
PATH="$TMP/gitshim:$PATH" bash "$BOT_COMMIT" -C "$TMP/r10g" -q -m "test: version unreadable" >/dev/null 2>&1
RC10G=$?
set -e
AFTER10G="$(git -C "$TMP/r10g" rev-list --count HEAD 2>/dev/null || echo 0)"
{ [[ "$RC10G" == "0" ]] && (( AFTER10G > BEFORE10G )); } \
  && pass "10g unreadable git --version → commit still made" \
  || fail "10g wrapper aborted: rc=$RC10G, commits $BEFORE10G → $AFTER10G"

# ---- Case 10h: the >= 2.32 version gate ------------------------------------------
# `--trailer` needs git 2.32; the contract for anything older is "no trailer, but the commit still
# happens". Nothing else reaches that branch, and a gate that silently inverted would hand
# `--trailer` to a git that rejects the option — turning an optional nicety into a failed commit.
# Both halves are asserted: the commit exists AND carries no trailer.
mkdir -p "$TMP/gitshim-old"
cat > "$TMP/gitshim-old/git" <<SHIM
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then echo "git version 2.30.0"; exit 0; fi
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$TMP/gitshim-old/git"
mkrepo "$TMP/r10h" '{"tracker":{"bot":{"enabled":false,"app":{"appName":"test-pipeline"}}}}'
PATH="$TMP/gitshim-old:$PATH" bash "$BOT_COMMIT" -C "$TMP/r10h" -q -m "test: git 2.30" >/dev/null 2>&1 || true
BODY10H="$(git -C "$TMP/r10h" log -1 --format='%B' 2>/dev/null || echo '<no commit>')"
N10H="$(ca_count "$BODY10H")"
{ [[ "$N10H" == "0" ]] && grep -q "test: git 2.30" <<< "$BODY10H"; } \
  && pass "10h git < 2.32 → commit made, no trailer attempted" \
  || fail "10h expected a commit with 0 trailers on git 2.30, got $N10H: $BODY10H"

echo ""
echo "[bot-commit-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
