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
status="${out%%|*}"
[[ "$status" == "disabled" ]] \
  && ok "(disabled) enabled:false → disabled even with wrapper + env" \
  || bad "(disabled) status=$status"

# ABSENT config → disabled
out="$(run_case absent ABSENT "GH_BOT=$W1" -- )"
status="${out%%|*}"
[[ "$status" == "disabled" ]] \
  && ok "(disabled) absent config → disabled" \
  || bad "(disabled) absent status=$status"

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
status="${out%%|*}"
[[ "$status" == "unset-var" ]] \
  && ok "(unset-var) enabled, no env, no wrapperPath, default missing → unset-var" \
  || bad "(unset-var) status=$status"

# --- wrapperPath set but absent → missing-file -------------------------------
out="$(run_case missing \
  '{"tracker":{"bot":{"enabled":true,"wrapperPath":"/no/such/wrapper-92.sh"}}}' \
  -- )"
status="${out%%|*}"
[[ "$status" == "missing-file" ]] \
  && ok "(missing-file) configured path absent → missing-file" \
  || bad "(missing-file) status=$status"

# --- present but non-executable → not-executable -----------------------------
Wn="$TMP/not-exec.sh"; printf '#!/bin/sh\necho x\n' > "$Wn"; chmod a-x "$Wn" || true
out="$(run_case notexec \
  "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$Wn\"}}}" \
  -- )"
status="${out%%|*}"
[[ "$status" == "not-executable" ]] \
  && ok "(not-executable) present but non-executable" \
  || bad "(not-executable) status=$status"

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

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
