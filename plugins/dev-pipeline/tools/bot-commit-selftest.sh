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
  && pass "1a bot identity on commit ($AUTHOR)" \
  || fail "1a bot identity — got '$AUTHOR', want '$WANT'"

# The trailer must land on the bot-ENABLED exec too, not only on the bot-disabled one every
# case-10 fixture uses. Nothing else asserts it there: cases 1-9 exercise that exec's `-c`
# PLACEMENT (a flag misplaced after `commit` errors the commit and reds them), but the whole
# trailer wiring could be deleted from it and the rest of the suite would stay green. Measured.
# Non-vacuous by construction — r1 has no prior commit and the invocation above is unguarded.
grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" \
  <<< "$(git -C "$TMP/r1" log -1 --format='%B')" \
  && pass "1b trailer added on the bot-ENABLED exec path" \
  || fail "1b no co-authorship trailer on the bot-identity commit"

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
# The third exec path. Same gap as 1b: its trailer wiring is otherwise asserted by nothing, and
# this is the fallback where the author is the OPERATOR — so here the trailer is load-bearing,
# not merely redundant. 4a already read this commit, so the read cannot be answered by a neighbor.
grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" \
  <<< "$(git -C "$TMP/r4" log -1 --format='%B')" \
  && pass "4c trailer added on the unresolvable-id fallback exec path" \
  || fail "4c no co-authorship trailer on the id-fallback commit"

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
#
# EVERY case below reads `git log -1` from ONE shared fixture, and that is vacuous by default:
# with the invocation `|| true`-guarded, the PREVIOUS case's commit answers for a commit that was
# never made. Measured — no-op'ing the wrapper on just the -F and --amend routes left three of
# these cases passing, and only the anti-vacuity control noticed. The bar is per-case: a case must
# fail when ITS OWN invocation makes no commit. So each records the head it expects to move and
# scores that too, and the body read degrades to a failing case rather than killing the harness on
# an empty fixture. On the --amend routes the case also stages content first: `--amend --no-edit`
# over an unchanged commit is object-identical (same tree, parent, message, and a same-second
# committer stamp → the same SHA), so there a bare head compare discriminates nothing.
head_at() { git -C "$1" rev-parse HEAD 2>/dev/null || echo '<none>'; }
body_at() { git -C "$1" log -1 --format='%B' 2>/dev/null || echo '<no commit>'; }
ca_count() { grep -ci "co-authored-by" <<< "$1" || true; }

mkrepo "$TMP/r10" '{"tracker":{"bot":{"enabled":false,"app":{"appName":"test-pipeline"}}}}'
H10A="$(head_at "$TMP/r10")"
bash "$BOT_COMMIT" -C "$TMP/r10" -q -m "test: no caller trailer" >/dev/null 2>&1 || true
BODY10="$(body_at "$TMP/r10")"
{ [[ "$(head_at "$TMP/r10")" != "$H10A" ]] \
  && grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" <<< "$BODY10"; } \
  && pass "10a absent caller trailer → generic Claude trailer added" \
  || fail "10a no co-authorship trailer on the commit: $BODY10"

# Caller wins: a session knows its own model, this wrapper cannot.
H10B="$(head_at "$TMP/r10")"
echo t10b > "$TMP/r10/b.txt"; git -C "$TMP/r10" add b.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q \
  -m "test: caller trailer" \
  -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" >/dev/null 2>&1 || true
BODY10B="$(body_at "$TMP/r10")"
COUNT10B="$(ca_count "$BODY10B")"
{ [[ "$(head_at "$TMP/r10")" != "$H10B" ]] && [[ "$COUNT10B" == "1" ]] \
  && grep -qi "Claude Opus 5" <<< "$BODY10B"; } \
  && pass "10b caller-supplied trailer preserved, not duplicated" \
  || fail "10b expected exactly 1 trailer naming the caller's model, got $COUNT10B: $BODY10B"

# ---- Cases 10c-10f: the routes an ARGUMENT SCAN cannot read ----------------------
# 10a/10b both carry the trailer state in -m arguments — the one route a scan of "$*" can see.
# -F, --amend and editor mode are where such a scan under-detects, and where a generic trailer
# lands beside the caller's precise one. The invariant is route-INDEPENDENT and is what these
# cases pin: exactly one Co-Authored-By on the resulting commit, naming the caller's model
# whenever the caller supplied one.
printf 'test: -F route\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$TMP/msg10c.txt"
H10C="$(head_at "$TMP/r10")"
echo t10c > "$TMP/r10/c.txt"; git -C "$TMP/r10" add c.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q -F "$TMP/msg10c.txt" >/dev/null 2>&1 || true
BODY10C="$(body_at "$TMP/r10")"
N10C="$(ca_count "$BODY10C")"
{ [[ "$(head_at "$TMP/r10")" != "$H10C" ]] && [[ "$N10C" == "1" ]] \
  && grep -qi "Claude Opus 5" <<< "$BODY10C"; } \
  && pass "10c -F body's trailer preserved, not duplicated" \
  || fail "10c expected 1 trailer naming the caller's model, got $N10C: $BODY10C"

# --amend reuses the STORED message, unreadable from the argument list. Not hypothetical: this
# script's header documents `--amend --reset-author` through this helper as the repair path for a
# commit already mis-attributed to the operator. Staging first is what makes the head compare
# discriminate, and it is also closer to that repair path, where there is something to fix.
H10D="$(head_at "$TMP/r10")"
echo t10d > "$TMP/r10/d.txt"; git -C "$TMP/r10" add d.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q --amend --no-edit >/dev/null 2>&1 || true
BODY10D="$(body_at "$TMP/r10")"
N10D="$(ca_count "$BODY10D")"
{ [[ "$(head_at "$TMP/r10")" != "$H10D" ]] && [[ "$N10D" == "1" ]] \
  && grep -qi "Claude Opus 5" <<< "$BODY10D"; } \
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
H10E="$(head_at "$TMP/r10")"
echo t10e2 > "$TMP/r10/e2.txt"; git -C "$TMP/r10" add e2.txt
GIT_EDITOR="$TMP/bin/editor10e" bash "$BOT_COMMIT" -C "$TMP/r10" -q --amend >/dev/null 2>&1 || true
BODY10E="$(body_at "$TMP/r10")"
N10E="$(ca_count "$BODY10E")"
{ [[ "$(head_at "$TMP/r10")" != "$H10E" ]] && [[ "$N10E" == "1" ]] \
  && grep -qi "Claude Opus 5" <<< "$BODY10E"; } \
  && pass "10e --amend through the editor buffer does not duplicate" \
  || fail "10e expected 1 trailer via the editor route, got $N10E: $BODY10E"

# Dedup must not have degraded into "never add on the routes the scan cannot read" — a -F body
# with NO trailer still earns the generic one. Absent this case, 10c-10e would pass equally well
# if the trailer were dropped outright on every such route.
printf 'test: -F route, no trailer\n' > "$TMP/msg10f.txt"
H10F="$(head_at "$TMP/r10")"
echo t10f > "$TMP/r10/f2.txt"; git -C "$TMP/r10" add f2.txt
bash "$BOT_COMMIT" -C "$TMP/r10" -q -F "$TMP/msg10f.txt" >/dev/null 2>&1 || true
BODY10F="$(body_at "$TMP/r10")"
{ [[ "$(head_at "$TMP/r10")" != "$H10F" ]] \
  && grep -qi "^Co-Authored-By: Claude <noreply@anthropic.com>$" <<< "$BODY10F"; } \
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

# ---- Case 11: the app keys only in the main checkout's gitignored .local.json (#1059) --
# A repo that commits its config keeps tracker.bot.app out of it, in the per-engineer local file.
# Once the config is tracked, the worktree's own copy wins candidate 2, and a session's scratch copy
# wins candidate 1 — and neither has a local file beside it. So the app keys must come from the MAIN
# checkout's local file whichever candidate wins (D-4 D-5). Case 5's shape, with the config
# committed and the app block moved out of it.
NOAPP_CFG='{"tracker":{"bot":{"enabled":true}}}'
LOCAL_APP='{"tracker":{"bot":{"app":{"appName":"local-app"}}}}'
WANT11="local-app[bot] <424242+local-app[bot]@users.noreply.github.com>"
mkrepo "$TMP/r11" "$NOAPP_CFG"
printf '.claude/second-shift.config.local.json\n' > "$TMP/r11/.gitignore"
printf '%s' "$LOCAL_APP" > "$TMP/r11/.claude/second-shift.config.local.json"
git -C "$TMP/r11" add .gitignore .claude/second-shift.config.json
git -C "$TMP/r11" -c user.name=Seed -c user.email=seed@example.com commit -q -m "seed"
git -C "$TMP/r11" worktree add -q -b wt11 "$TMP/r11-wt" >/dev/null 2>&1

[[ -f "$TMP/r11-wt/.claude/second-shift.config.json" && ! -e "$TMP/r11-wt/.claude/second-shift.config.local.json" ]] \
  && ! jq -e '.tracker.bot | has("app")' "$TMP/r11-wt/.claude/second-shift.config.json" >/dev/null \
  && pass "11a the worktree carries the committed config, with no app block and no local file" \
  || fail "11a fixture does not reproduce a committed config without its app block"

echo wt11 > "$TMP/r11-wt/w.txt"; git -C "$TMP/r11-wt" add w.txt
ERR11="$(bash "$BOT_COMMIT" -C "$TMP/r11-wt" -q -m "test: committed config, local app" 2>&1 >/dev/null || true)"
AUTHOR11="$(git -C "$TMP/r11-wt" log --format='%an <%ae>' -1)"
[[ "$AUTHOR11" == "$WANT11" ]] \
  && pass "11b worktree's committed config + main checkout's local app keys → bot identity" \
  || fail "11b got '$AUTHOR11', want '$WANT11' (stderr: $ERR11)"

# The session route: $SECOND_SHIFT_CONFIG names a copy of the committed config in a scratch dir.
mkdir -p "$TMP/scratch11"
cp "$TMP/r11/.claude/second-shift.config.json" "$TMP/scratch11/second-shift.config.json"
echo wt11c > "$TMP/r11-wt/c.txt"; git -C "$TMP/r11-wt" add c.txt
AUTHOR11C="$(SECOND_SHIFT_CONFIG="$TMP/scratch11/second-shift.config.json" \
  bash "$BOT_COMMIT" -C "$TMP/r11-wt" -q -m "test: scratch copy" >/dev/null 2>&1; \
  git -C "$TMP/r11-wt" log --format='%an <%ae>' -1)"
[[ "$AUTHOR11C" == "$WANT11" ]] \
  && pass "11c \$SECOND_SHIFT_CONFIG at a copy of the committed config → bot identity from the main checkout's local file" \
  || fail "11c got '$AUTHOR11C', want '$WANT11'"

# A local file beside the override copy is NOT the one read: it is always the main checkout's (D-5).
printf '%s' '{"tracker":{"bot":{"app":{"appName":"beside-copy-app"}}}}' > "$TMP/scratch11/second-shift.config.local.json"
echo wt11d > "$TMP/r11-wt/d.txt"; git -C "$TMP/r11-wt" add d.txt
AUTHOR11D="$(SECOND_SHIFT_CONFIG="$TMP/scratch11/second-shift.config.json" \
  bash "$BOT_COMMIT" -C "$TMP/r11-wt" -q -m "test: beside the copy" >/dev/null 2>&1; \
  git -C "$TMP/r11-wt" log --format='%an' -1)"
[[ "$AUTHOR11D" == "local-app[bot]" ]] \
  && pass "11d a local file beside the \$SECOND_SHIFT_CONFIG copy is not read; the main checkout's is" \
  || fail "11d got '$AUTHOR11D', want 'local-app[bot]'"

# A local key overrides the same committed key (D-6).
mkrepo "$TMP/r11e" '{"tracker":{"bot":{"enabled":true,"app":{"appName":"committed-app"}}}}'
printf '%s' "$LOCAL_APP" > "$TMP/r11e/.claude/second-shift.config.local.json"
AUTHOR11E="$(bash "$BOT_COMMIT" -C "$TMP/r11e" -q -m "test: local over committed" >/dev/null 2>&1; \
  git -C "$TMP/r11e" log --format='%an' -1)"
[[ "$AUTHOR11E" == "local-app[bot]" ]] \
  && pass "11e the local appName overrides the committed one" \
  || fail "11e got '$AUTHOR11E', want 'local-app[bot]'"

# tracker.bot.enabled is the committed config's alone: local app keys never switch a disabled bot on.
mkrepo "$TMP/r11f" '{"tracker":{"bot":{"enabled":false}}}'
printf '%s' "$LOCAL_APP" > "$TMP/r11f/.claude/second-shift.config.local.json"
AUTHOR11F="$(bash "$BOT_COMMIT" -C "$TMP/r11f" -q -m "test: local app, bot off" >/dev/null 2>&1; \
  git -C "$TMP/r11f" log --format='%an <%ae>' -1)"
[[ "$AUTHOR11F" == "Repo Default <default@example.com>" ]] \
  && pass "11f local app keys with tracker.bot.enabled false → repo default identity" \
  || fail "11f got '$AUTHOR11F', want the repo default"

# SECOND_SHIFT_REPO_ROOT moves the main checkout, so it moves the local file with it (D-4).
mkrepo "$TMP/r11g"
mkdir -p "$TMP/fakeroot11/.claude"
printf '%s' "$NOAPP_CFG" > "$TMP/fakeroot11/.claude/second-shift.config.json"
printf '%s' "$LOCAL_APP" > "$TMP/fakeroot11/.claude/second-shift.config.local.json"
AUTHOR11G="$(SECOND_SHIFT_REPO_ROOT="$TMP/fakeroot11" \
  bash "$BOT_COMMIT" -C "$TMP/r11g" -q -m "test: repo-root override, local app" >/dev/null 2>&1; \
  git -C "$TMP/r11g" log --format='%an' -1)"
[[ "$AUTHOR11G" == "local-app[bot]" ]] \
  && pass "11g SECOND_SHIFT_REPO_ROOT's local file supplies the app keys" \
  || fail "11g got '$AUTHOR11G', want 'local-app[bot]'"

# Enabled with no appName anywhere: the WARN names both files it looked in.
mkrepo "$TMP/r11h" "$NOAPP_CFG"
ERR11H="$(bash "$BOT_COMMIT" -C "$TMP/r11h" -q -m "test: no appName" 2>&1 >/dev/null || true)"
grep -q "tracker.bot.app.appName is set in neither .*second-shift.config.json nor .*second-shift.config.local.json" <<< "$ERR11H" \
  && pass "11h enabled bot with no appName → WARN names the config and the local file" \
  || fail "11h wrong or missing WARN: $ERR11H"

# ---- Cases 12-18: the name cache (#1068) -------------------------------------------
# The id file alone hid a changed appName: a warm id meant the configured name was never looked up.
# The name file beside it holds "<appName> <id>", and the cached id is trusted only when it matches.
#
# This stub answers PER LOGIN and logs each call's arguments, so a lookup of the wrong name cannot
# pass green (the shared stub above returns one id for every login). The failing login mirrors real
# `gh api users/<login>[bot] --jq .id` on a 404: exit 1 with GitHub's error JSON on STDOUT, not
# nothing. Source of the shape: the observation recorded in #1068 ("Why", and intake fan-out F-1) of
# a renamed App's old login, and GitHub's REST error body for GET /users/{username}
# (https://docs.github.com/rest/users/users#get-a-user — 404 "Resource not found").
cat > "$TMP/bin/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "${GH_SHIM_CALLS:?}"
case "$1 $2" in
  "api users/new-app[bot]") echo "777"; exit 0 ;;
  "api users/gone-app[bot]")
    echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/users/users#get-a-user","status":"404"}'
    exit 1 ;;
esac
exit 1
SHIM
chmod +x "$TMP/bin/gh"

NEW_CFG='{"tracker":{"bot":{"enabled":true,"app":{"appName":"new-app"}}}}'
GONE_CFG='{"tracker":{"bot":{"enabled":true,"app":{"appName":"gone-app"}}}}'
WANT_NEW="new-app[bot] <777+new-app[bot]@users.noreply.github.com>"
DEFAULT_ID="Repo Default <default@example.com>"

id_file() { echo "$1/.git/second-shift-bot-user-id"; }
name_file() { echo "$1/.git/second-shift-bot-user-name"; }
# cache_repo <dir> <config-json> <id-content|-> <name-content|-> — "-" leaves that file absent.
cache_repo() {
  mkrepo "$1" "$2"
  if [[ "$3" != "-" ]]; then printf '%s' "$3" > "$(id_file "$1")"; fi
  if [[ "$4" != "-" ]]; then printf '%s' "$4" > "$(name_file "$1")"; fi
  : > "$GH_SHIM_CALLS"
}
# commit_in <dir> — sets RC and ERR (stderr) for the commit just made.
commit_in() {
  set +e
  ERR="$(bash "$BOT_COMMIT" -C "$1" -q -m "test: $1" 2>&1 >/dev/null)"
  RC=$?
  set -e
}
author_of() { git -C "$1" log --format='%an <%ae>' -1 2>/dev/null || echo '<no commit>'; }
content_of() { if [[ -f "$1" ]]; then cat "$1"; else echo '<absent>'; fi; }
gh_calls() { wc -l < "$GH_SHIM_CALLS" | tr -d ' '; }
no_warn() { ! grep -q "bot-commit] WARN" <<< "$1"; }

# ---- Case 12: matching id file and name cache → cached id, no gh call, no WARN (AC-1) --
cache_repo "$TMP/r12" "$NEW_CFG" "555" "new-app 555"
commit_in "$TMP/r12"
{ [[ "$(author_of "$TMP/r12")" == "new-app[bot] <555+new-app[bot]@users.noreply.github.com>" ]] \
  && [[ "$(gh_calls)" == "0" ]] && no_warn "$ERR"; } \
  && pass "12 matching cache → cached id, no gh call, no WARN (AC-1)" \
  || fail "12 got '$(author_of "$TMP/r12")', gh calls $(gh_calls), stderr: $ERR"

# ---- Case 13: name cache for another name + good lookup → new id, both files rewritten (AC-2) --
cache_repo "$TMP/r13" "$NEW_CFG" "555" "old-app 555"
commit_in "$TMP/r13"
[[ "$(author_of "$TMP/r13")" == "$WANT_NEW" ]] \
  && pass "13a changed appName → looked up, commit carries the new id (AC-2)" \
  || fail "13a got '$(author_of "$TMP/r13")', want '$WANT_NEW'"
grep -qx 'api users/new-app\[bot\] --jq .id' "$GH_SHIM_CALLS" \
  && pass "13b the lookup asked for the configured login (AC-2)" \
  || fail "13b gh calls: $(cat "$GH_SHIM_CALLS")"
{ [[ "$(content_of "$(id_file "$TMP/r13")")" == "777" ]] \
  && [[ "$(content_of "$(name_file "$TMP/r13")")" == "new-app 777" ]]; } \
  && pass "13c id file holds the bare new id, name cache holds '<appName> <id>' (AC-2)" \
  || fail "13c id file '$(content_of "$(id_file "$TMP/r13")")', name cache '$(content_of "$(name_file "$TMP/r13")")'"
no_warn "$ERR" \
  && pass "13d successful re-lookup is silent (AC-2)" \
  || fail "13d unexpected WARN: $ERR"
# Round trip through the real writer: the pair 13c wrote must be read back as a match.
echo more > "$TMP/r13/g.txt"; git -C "$TMP/r13" add g.txt
commit_in "$TMP/r13"
{ [[ "$(author_of "$TMP/r13")" == "$WANT_NEW" ]] && [[ "$(gh_calls)" == "1" ]] && no_warn "$ERR"; } \
  && pass "13e the pair the wrapper wrote is trusted on the next commit (AC-1 AC-2)" \
  || fail "13e got '$(author_of "$TMP/r13")', gh calls $(gh_calls) (want 1), stderr: $ERR"

# ---- Case 14: mismatch + failed lookup (404 JSON on stdout) → WARN, default, no write (AC-3) --
cache_repo "$TMP/r14" "$GONE_CFG" "555" "old-app 555"
commit_in "$TMP/r14"
{ [[ "$RC" == "0" ]] && [[ "$(author_of "$TMP/r14")" == "$DEFAULT_ID" ]]; } \
  && pass "14a failed lookup → repo default identity, exit 0 (AC-3)" \
  || fail "14a rc=$RC, got '$(author_of "$TMP/r14")'"
grep -q "could not resolve bot user id.*'gone-app'" <<< "$ERR" \
  && pass "14b WARN names the configured appName (AC-3)" \
  || fail "14b wrong or missing WARN: $ERR"
{ [[ "$(content_of "$(id_file "$TMP/r14")")" == "555" ]] \
  && [[ "$(content_of "$(name_file "$TMP/r14")")" == "old-app 555" ]]; } \
  && pass "14c both cache files unchanged (AC-3)" \
  || fail "14c id file '$(content_of "$(id_file "$TMP/r14")")', name cache '$(content_of "$(name_file "$TMP/r14")")'"
# Cold cache: the pre-#1068 code cached the 404 JSON as the id and committed with a junk email.
cache_repo "$TMP/r14d" "$GONE_CFG" - -
commit_in "$TMP/r14d"
{ [[ "$(author_of "$TMP/r14d")" == "$DEFAULT_ID" ]] \
  && [[ ! -e "$(id_file "$TMP/r14d")" && ! -e "$(name_file "$TMP/r14d")" ]] \
  && grep -q "could not resolve bot user id" <<< "$ERR"; } \
  && pass "14d cold cache + 404 JSON → WARN, repo default, nothing cached (AC-3)" \
  || fail "14d got '$(author_of "$TMP/r14d")', id file '$(content_of "$(id_file "$TMP/r14d")")', stderr: $ERR"

# ---- Case 15: id file, no name cache → a lookup decides (AC-4) -----------------------
cache_repo "$TMP/r15" "$NEW_CFG" "555" -
commit_in "$TMP/r15"
{ [[ "$(author_of "$TMP/r15")" == "$WANT_NEW" ]] && [[ "$(gh_calls)" == "1" ]] \
  && [[ "$(content_of "$(name_file "$TMP/r15")")" == "new-app 777" ]] && no_warn "$ERR"; } \
  && pass "15a id file without a name cache → looked up, behaves as AC-2 (AC-4)" \
  || fail "15a got '$(author_of "$TMP/r15")', gh calls $(gh_calls), name cache '$(content_of "$(name_file "$TMP/r15")")', stderr: $ERR"
cache_repo "$TMP/r15b" "$GONE_CFG" "555" -
commit_in "$TMP/r15b"
{ [[ "$(author_of "$TMP/r15b")" == "$DEFAULT_ID" ]] && [[ "$(gh_calls)" == "1" ]] \
  && [[ "$(content_of "$(id_file "$TMP/r15b")")" == "555" && ! -e "$(name_file "$TMP/r15b")" ]] \
  && grep -q "could not resolve bot user id" <<< "$ERR"; } \
  && pass "15b id file without a name cache + failed lookup → behaves as AC-3 (AC-4)" \
  || fail "15b got '$(author_of "$TMP/r15b")', gh calls $(gh_calls), id file '$(content_of "$(id_file "$TMP/r15b")")', stderr: $ERR"

# ---- Case 16: an id file that is not a valid id is never used (AC-5) -------------------
# The name cache is paired with the same junk, so only the id check can reject it.
for _junk in "not-a-number" '{"message":"Not Found","status":"404"}' $'555\r'; do
  cache_repo "$TMP/r16" "$NEW_CFG" "$_junk" "new-app $_junk"
  commit_in "$TMP/r16"
  _shown="$(printf '%q' "$_junk")"
  { [[ "$(author_of "$TMP/r16")" == "$WANT_NEW" ]] && [[ "$(gh_calls)" == "1" ]]; } \
    && pass "16 id file $_shown → not used, looked up (AC-5)" \
    || fail "16 id file $_shown → got '$(author_of "$TMP/r16")', gh calls $(gh_calls)"
  rm -rf "$TMP/r16"
done

# ---- Case 17: ids that differ, or an empty id file → a lookup (AC-7) --------------------
cache_repo "$TMP/r17" "$NEW_CFG" "555" "new-app 556"
commit_in "$TMP/r17"
{ [[ "$(author_of "$TMP/r17")" == "$WANT_NEW" ]] && [[ "$(gh_calls)" == "1" ]]; } \
  && pass "17a name cache's id differs from the id file's → looked up (AC-7)" \
  || fail "17a got '$(author_of "$TMP/r17")', gh calls $(gh_calls)"
cache_repo "$TMP/r17b" "$NEW_CFG" "" "new-app "
commit_in "$TMP/r17b"
{ [[ "$(author_of "$TMP/r17b")" == "$WANT_NEW" ]] && [[ "$(gh_calls)" == "1" ]]; } \
  && pass "17b empty id file → looked up (AC-7)" \
  || fail "17b got '$(author_of "$TMP/r17b")', gh calls $(gh_calls)"

# ---- Case 18: a cache file that cannot be written → WARN, the commit still happens (AC-8) --
for _which in id name; do
  cache_repo "$TMP/r18-$_which" "$NEW_CFG" - -
  _blocked="$(${_which}_file "$TMP/r18-$_which")"
  mkdir -p "$_blocked"
  commit_in "$TMP/r18-$_which"
  { [[ "$RC" == "0" ]] && [[ "$(author_of "$TMP/r18-$_which")" == "$WANT_NEW" ]]; } \
    && pass "18 directory at the $_which cache path → committed with the resolved id, exit 0 (AC-8)" \
    || fail "18 $_which: rc=$RC, got '$(author_of "$TMP/r18-$_which")', stderr: $ERR"
  grep -qF "WARN: cannot write the bot cache file $_blocked" <<< "$ERR" \
    && pass "18 directory at the $_which cache path → WARN names the file (AC-8)" \
    || fail "18 $_which: no WARN naming $_blocked: $ERR"
done

echo ""
echo "[bot-commit-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
