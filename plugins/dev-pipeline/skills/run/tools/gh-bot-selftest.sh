#!/usr/bin/env bash
# Self-test for tools/gh-bot.sh — the single bot-wrapper resolver (#92).
#
# Per-tool behavioral suite (cost-block-selftest run_identity_case pattern): each
# case sandboxes $HOME and the consumer repo root so ladder rungs cannot leak
# into the operator's real config.
#
# No scenario-liveness-selftest.sh scenario: like doctor block 8, this path
# reaches no terminal write (status/path/passthrough only). Stated per the
# scenario-first rule in CLAUDE.md.
#
# bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/gh-bot.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

[[ -x "$HELPER" ]] || { echo "gh-bot-selftest: $HELPER missing or not executable" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_case <label> <config-json-or-ABSENT> <env-assignments…> -- <gh-bot args>
# Prints "status|path|rc" on stdout for the --status / --path probes.
run_case() {
  local _label="$1" cfg_json="$2"; shift 2
  : "${_label}" # case id for callers; unused in body
  local home="$TMP/h-$$-$RANDOM" root="$TMP/r-$$-$RANDOM"
  mkdir -p "$home" "$root/.claude" "$home/.config/$(basename "$root")"
  local cfg_path="$root/.claude/second-shift.config.json"
  if [[ "$cfg_json" == "ABSENT" ]]; then
    :
  else
    printf '%s\n' "$cfg_json" > "$cfg_path"
  fi

  # Remaining args until -- are env assignments KEY=VAL
  local -a env_assign=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_assign+=("$1"); shift
  done
  [[ "${1:-}" == "--" ]] && shift

  local status path rc_path
  status="$(
    env -i \
      PATH="$PATH" HOME="$home" \
      SECOND_SHIFT_REPO_ROOT="$root" \
      SECOND_SHIFT_CONFIG="$cfg_path" \
      ${env_assign[@]+"${env_assign[@]}"} \
      bash "$HELPER" --status 2>/dev/null
  )"
  path="$(
    env -i \
      PATH="$PATH" HOME="$home" \
      SECOND_SHIFT_REPO_ROOT="$root" \
      SECOND_SHIFT_CONFIG="$cfg_path" \
      ${env_assign[@]+"${env_assign[@]}"} \
      bash "$HELPER" --path 2>/dev/null
  )" && rc_path=0 || rc_path=$?
  # path may be empty on failure; normalize
  printf '%s|%s|%s\n' "$status" "${path:-}" "$rc_path"
}

echo "=== gh-bot.sh ladder + token set (#92) ==="

# --- each rung wins in order -------------------------------------------------
# Rung 1 (env) wins over wrapperPath and default.
W1="$TMP/wrapper-env.sh"; printf '#!/bin/sh\necho env-wrapper\n' > "$W1"; chmod +x "$W1"
W2="$TMP/wrapper-cfg.sh"; printf '#!/bin/sh\necho cfg-wrapper\n' > "$W2"; chmod +x "$W2"
out="$(run_case env-wins \
  "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$W2\"}}}" \
  "GH_BOT=$W1" -- )"
status="${out%%|*}"; rest="${out#*|}"; path="${rest%%|*}"; rc="${rest##*|}"
[[ "$status" == "ok" && "$path" == "$W1" && "$rc" == "0" ]] \
  && ok "(rung1) env var wins over wrapperPath" \
  || bad "(rung1) got status=$status path=$path rc=$rc"

# Rung 2 (wrapperPath) wins over default when env unset.
out="$(run_case wrap-wins \
  "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$W2\"}}}" \
  -- )"
status="${out%%|*}"; rest="${out#*|}"; path="${rest%%|*}"; rc="${rest##*|}"
[[ "$status" == "ok" && "$path" == "$W2" && "$rc" == "0" ]] \
  && ok "(rung2) wrapperPath wins when env unset" \
  || bad "(rung2) got status=$status path=$path rc=$rc"

# Rung 3 (default under $HOME/.config/<basename>/gh-as-bot.sh).
# Build via a dedicated sandbox so we know the default path.
home3="$TMP/h3"; root3="$TMP/r3"; mkdir -p "$home3" "$root3/.claude"
printf '%s\n' '{"tracker":{"bot":{"enabled":true}}}' > "$root3/.claude/second-shift.config.json"
def3="$home3/.config/$(basename "$root3")/gh-as-bot.sh"
mkdir -p "$(dirname "$def3")"
printf '#!/bin/sh\necho default\n' > "$def3"; chmod +x "$def3"
st3="$(env -i PATH="$PATH" HOME="$home3" SECOND_SHIFT_REPO_ROOT="$root3" \
  SECOND_SHIFT_CONFIG="$root3/.claude/second-shift.config.json" \
  bash "$HELPER" --status)"
p3="$(env -i PATH="$PATH" HOME="$home3" SECOND_SHIFT_REPO_ROOT="$root3" \
  SECOND_SHIFT_CONFIG="$root3/.claude/second-shift.config.json" \
  bash "$HELPER" --path)"
[[ "$st3" == "ok" && "$p3" == "$def3" ]] \
  && ok "(rung3) default path under \$HOME/.config/<basename>/" \
  || bad "(rung3) status=$st3 path=$p3 expected=$def3"

# --- ~ expansion -------------------------------------------------------------
home_t="$TMP/ht"; root_t="$TMP/rt"; mkdir -p "$home_t" "$root_t/.claude"
printf '#!/bin/sh\necho tilde\n' > "$home_t/wrapper.sh"; chmod +x "$home_t/wrapper.sh"
printf '%s\n' '{"tracker":{"bot":{"enabled":true,"wrapperPath":"~/wrapper.sh"}}}' \
  > "$root_t/.claude/second-shift.config.json"
stt="$(env -i PATH="$PATH" HOME="$home_t" SECOND_SHIFT_REPO_ROOT="$root_t" \
  SECOND_SHIFT_CONFIG="$root_t/.claude/second-shift.config.json" bash "$HELPER" --status)"
pt="$(env -i PATH="$PATH" HOME="$home_t" SECOND_SHIFT_REPO_ROOT="$root_t" \
  SECOND_SHIFT_CONFIG="$root_t/.claude/second-shift.config.json" bash "$HELPER" --path)"
[[ "$stt" == "ok" && "$pt" == "$home_t/wrapper.sh" ]] \
  && ok "(tilde) wrapperPath ~ expands against \$HOME" \
  || bad "(tilde) status=$stt path=$pt"

# --- envVar: "MY_BOT" honored; set GH_BOT ignored -----------------------------
Wmy="$TMP/my-bot.sh"; printf '#!/bin/sh\necho my\n' > "$Wmy"; chmod +x "$Wmy"
Wgh="$TMP/gh-bot-ignore.sh"; printf '#!/bin/sh\necho gh\n' > "$Wgh"; chmod +x "$Wgh"
home_m="$TMP/hm"; root_m="$TMP/rm"; mkdir -p "$home_m" "$root_m/.claude"
printf '%s\n' '{"tracker":{"bot":{"enabled":true,"envVar":"MY_BOT"}}}' \
  > "$root_m/.claude/second-shift.config.json"
stm="$(env -i PATH="$PATH" HOME="$home_m" SECOND_SHIFT_REPO_ROOT="$root_m" \
  SECOND_SHIFT_CONFIG="$root_m/.claude/second-shift.config.json" \
  MY_BOT="$Wmy" GH_BOT="$Wgh" bash "$HELPER" --status)"
pm="$(env -i PATH="$PATH" HOME="$home_m" SECOND_SHIFT_REPO_ROOT="$root_m" \
  SECOND_SHIFT_CONFIG="$root_m/.claude/second-shift.config.json" \
  MY_BOT="$Wmy" GH_BOT="$Wgh" bash "$HELPER" --path)"
[[ "$stm" == "ok" && "$pm" == "$Wmy" ]] \
  && ok "(envVar) MY_BOT honored; GH_BOT ignored" \
  || bad "(envVar) status=$stm path=$pm"

# --- enabled:false → disabled regardless of present wrapper ------------------
out="$(run_case disabled \
  "{\"tracker\":{\"bot\":{\"enabled\":false,\"wrapperPath\":\"$W2\"}}}" \
  "GH_BOT=$W1" -- )"
status="${out%%|*}"; rest="${out#*|}"; rc="${rest##*|}"
[[ "$status" == "disabled" && "$rc" != "0" ]] \
  && ok "(disabled) enabled:false → disabled even with wrapper + env" \
  || bad "(disabled) status=$status rc=$rc"

# ABSENT config → disabled
out="$(run_case absent ABSENT "GH_BOT=$W1" -- )"
status="${out%%|*}"; rest="${out#*|}"; rc="${rest##*|}"
[[ "$status" == "disabled" && "$rc" != "0" ]] \
  && ok "(disabled) absent config → disabled" \
  || bad "(disabled) absent status=$status rc=$rc"

# --- unset var + resolvable wrapper → ok (exact repro) -----------------------
out="$(run_case unset-ok \
  "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$W2\"}}}" \
  -- )"
status="${out%%|*}"; rest="${out#*|}"; path="${rest%%|*}"; rc="${rest##*|}"
[[ "$status" == "ok" && "$path" == "$W2" && "$rc" == "0" ]] \
  && ok "(repro) unset env + resolvable wrapperPath → ok" \
  || bad "(repro) status=$status path=$path rc=$rc"

# --- unset var + nothing resolvable → unset-var ------------------------------
out="$(run_case unset-var \
  '{"tracker":{"bot":{"enabled":true}}}' \
  -- )"
status="${out%%|*}"; rest="${out#*|}"; rc="${rest##*|}"
[[ "$status" == "unset-var" && "$rc" != "0" ]] \
  && ok "(unset-var) enabled, no env, no wrapperPath, default missing → unset-var" \
  || bad "(unset-var) status=$status rc=$rc"

# --- wrapperPath set but absent → missing-file -------------------------------
out="$(run_case missing \
  '{"tracker":{"bot":{"enabled":true,"wrapperPath":"/no/such/wrapper-92.sh"}}}' \
  -- )"
status="${out%%|*}"; rest="${out#*|}"; rc="${rest##*|}"
[[ "$status" == "missing-file" && "$rc" != "0" ]] \
  && ok "(missing-file) configured path absent → missing-file" \
  || bad "(missing-file) status=$status rc=$rc"

# --- present but non-executable → not-executable -----------------------------
Wn="$TMP/not-exec.sh"; printf '#!/bin/sh\necho x\n' > "$Wn"; chmod a-x "$Wn" || true
out="$(run_case notexec \
  "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$Wn\"}}}" \
  -- )"
status="${out%%|*}"; rest="${out#*|}"; rc="${rest##*|}"
[[ "$status" == "not-executable" && "$rc" != "0" ]] \
  && ok "(not-executable) present but non-executable" \
  || bad "(not-executable) status=$status rc=$rc"

# --- passthrough forwards argv -----------------------------------------------
Wm="$TMP/mock-pass.sh"
cat > "$Wm" <<'EOF'
#!/bin/sh
printf 'ARGV:%s\n' "$*"
EOF
chmod +x "$Wm"
home_p="$TMP/hp"; root_p="$TMP/rp"; mkdir -p "$home_p" "$root_p/.claude"
printf '%s\n' "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$Wm\"}}}" \
  > "$root_p/.claude/second-shift.config.json"
pass_out="$(env -i PATH="$PATH" HOME="$home_p" SECOND_SHIFT_REPO_ROOT="$root_p" \
  SECOND_SHIFT_CONFIG="$root_p/.claude/second-shift.config.json" \
  bash "$HELPER" api -X POST foo --jq .bar 2>/dev/null)"
[[ "$pass_out" == "ARGV:api -X POST foo --jq .bar" ]] \
  && ok "(passthrough) argv forwarded verbatim to wrapper" \
  || bad "(passthrough) got: [$pass_out]"

# --- --status always exits 0 -------------------------------------------------
rc_s=0
env -i PATH="$PATH" HOME="$TMP" SECOND_SHIFT_REPO_ROOT="$TMP" \
  bash "$HELPER" --status >/dev/null 2>&1 || rc_s=$?
[[ "$rc_s" == "0" ]] \
  && ok "(--status) always exits 0" \
  || bad "(--status) exited $rc_s"

# --- real git-derived root: no SECOND_SHIFT_REPO_ROOT/SECOND_SHIFT_CONFIG ----
# Every case above overrides both env vars, so the actual `git rev-parse
# --git-common-dir` ladder (the worktree-safe derivation lifted from
# claim-issue.sh) never runs under test — this is the branch real invocations
# always take, since nobody exports SECOND_SHIFT_REPO_ROOT in practice.

# (a) main checkout: git-common-dir reports a RELATIVE ".git" — the
# absolute-ize branch that handles that case.
home_g="$TMP/hg"; repo_g="$TMP/realrepo-$$"; mkdir -p "$home_g" "$repo_g"
git init -q "$repo_g"
git -C "$repo_g" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$repo_g/.claude"
printf '%s\n' '{"tracker":{"bot":{"enabled":true}}}' > "$repo_g/.claude/second-shift.config.json"
def_g="$home_g/.config/$(basename "$repo_g")/gh-as-bot.sh"
mkdir -p "$(dirname "$def_g")"
printf '#!/bin/sh\necho realrepo\n' > "$def_g"; chmod +x "$def_g"
st_g="$(cd "$repo_g" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --status)"
p_g="$(cd "$repo_g" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --path)"
[[ "$st_g" == "ok" && "$p_g" == "$def_g" ]] \
  && ok "(real-root) main checkout: git-common-dir derives root with no override" \
  || bad "(real-root) main checkout: status=$st_g path=$p_g expected=$def_g"

# Same real derivation from a SUBDIRECTORY (git rev-parse --git-common-dir
# resolves identically regardless of cwd within the repo).
mkdir -p "$repo_g/sub/dir"
st_gs="$(cd "$repo_g/sub/dir" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --status)"
p_gs="$(cd "$repo_g/sub/dir" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --path)"
[[ "$st_gs" == "ok" && "$p_gs" == "$def_g" ]] \
  && ok "(real-root) subdirectory: git-common-dir derives the same root" \
  || bad "(real-root) subdirectory: status=$st_gs path=$p_gs expected=$def_g"

# (b) linked worktree: git-common-dir reports an ABSOLUTE path — the branch
# that skips the absolute-ize step. `--git-common-dir` from a linked worktree
# points at the MAIN repo's .git (shared object database, by git's own
# design — confirmed empirically), so root — and the default path's basename
# — resolves to the MAIN repo, not the worktree's own directory. This is the
# intended "worktree-safe root ... the main checkout" behavior the header
# comment describes, not a bug: a lean worktree must resolve the SAME config
# and bot wrapper as its main checkout.
wt_g="$TMP/realwt-$$"
git -C "$repo_g" worktree add -q -b "gh-bot-selftest-wt-$$" "$wt_g" >/dev/null 2>&1
st_wg="$(cd "$wt_g" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --status)"
p_wg="$(cd "$wt_g" && env -i PATH="$PATH" HOME="$home_g" bash "$HELPER" --path)"
[[ "$st_wg" == "ok" && "$p_wg" == "$def_g" ]] \
  && ok "(real-root) linked worktree: absolute git-common-dir resolves to the MAIN repo's basename" \
  || bad "(real-root) linked worktree: status=$st_wg path=$p_wg expected=$def_g"
git -C "$repo_g" worktree remove "$wt_g" --force >/dev/null 2>&1 || true

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
