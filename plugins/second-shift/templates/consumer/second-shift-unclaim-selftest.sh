#!/usr/bin/env bash
# second-shift-unclaim-selftest.sh — hermetic selftest for the run-state label release.
#
# Contract pinned here: both role labels resolve live from a readable config and fall
# through to their shipped defaults otherwise; a tracker that takes no writes and a tracker
# that is not github are STATED no-ops with zero API calls; a label the item never carried
# is a no-op with zero WRITES; a label lost to a race is still success; a real API failure
# is a real failure rather than a quiet green; and a failure on one label never skips the
# other.
#
# Nothing touches the network: gh is stubbed on PATH, records its argv, and returns a
# status the case controls — per label, so the two removals can be driven independently.
#
# There is deliberately NO grep over either workflow YAML. The YAML is not the unit; the
# syntax floor for both files is scripts/check-workflows-selftest.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-unclaim.sh"
FAILS=0
check() { if [ "$2" -eq 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- the gh stub -----------------------------------------------------------
# Distinguishes the labels READ from a label DELETE by the -X DELETE argument.
# Knobs: STUB_LABELS_JSON (read body), STUB_READ_RC, STUB_DELETE_RC, STUB_DELETE_ERR, and
# STUB_FAIL_ON — when set, only a DELETE whose path contains it takes the failure status.
STUB_DIR="$TMP/bin"; mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
is_delete=0
for a in "$@"; do [ "$a" = "DELETE" ] && is_delete=1; done
if [ "$is_delete" -eq 1 ]; then
  path=""
  for a in "$@"; do path="$a"; done
  if [ -n "${STUB_FAIL_ON:-}" ]; then
    case "$path" in
      *"$STUB_FAIL_ON"*) : ;;
      *) exit 0 ;;
    esac
  fi
  printf '%s\n' "${STUB_DELETE_ERR:-}" >&2
  exit "${STUB_DELETE_RC:-0}"
fi
if [ "${STUB_READ_RC:-0}" -ne 0 ]; then
  echo "HTTP 403: Resource not accessible by integration" >&2
  exit "${STUB_READ_RC:-0}"
fi
printf '%s' "${STUB_LABELS_JSON:-[]}"
EOF
chmod +x "$STUB_DIR/gh"

CARRIES_BOTH_DEFAULT='[{"name":"bug"},{"name":"in-progress"},{"name":"ready-for-dev"}]'
CARRIES_BOTH_CUSTOM='[{"name":"claimed-custom"},{"name":"queue-custom"}]'
CARRIES_QUEUE_ONLY='[{"name":"bug"},{"name":"ready-for-dev"}]'
CARRIES_SPACED='[{"name":"in progress"}]'
CARRIES_NEITHER='[{"name":"bug"},{"name":"enhancement"}]'

# run <config-path> <labels-json> <issue-arg...> -> sets RC, OUT, CALLS, NCALLS
run() {
  local cfg="$1" labels="$2"; shift 2
  GH_CALLS="$TMP/calls"; : > "$GH_CALLS"
  OUT="$(PATH="$STUB_DIR:$PATH" GH_CALLS="$GH_CALLS" \
         STUB_LABELS_JSON="$labels" \
         STUB_READ_RC="${STUB_READ_RC:-0}" \
         STUB_DELETE_RC="${STUB_DELETE_RC:-0}" \
         STUB_DELETE_ERR="${STUB_DELETE_ERR:-}" \
         STUB_FAIL_ON="${STUB_FAIL_ON:-}" \
         SECOND_SHIFT_CONFIG="$cfg" SECOND_SHIFT_REPO_ROOT="$TMP" \
         bash "$TOOL" "$@" 2>&1)"
  RC=$?
  CALLS="$(cat "$GH_CALLS")"
  NCALLS="$(grep -c . "$GH_CALLS")"
}
deletes() { echo "$CALLS" | grep -c 'DELETE'; }

mkcfg() { printf '%s' "$2" > "$TMP/$1.json"; echo "$TMP/$1.json"; }

CFG_CUSTOM="$(mkcfg custom '{"tracker":{"type":"github","labels":{"claimed":"claimed-custom","queue":"queue-custom"}}}')"
CFG_BARE="$(mkcfg bare '{"tracker":{"type":"github"}}')"
CFG_NOWRITES="$(mkcfg nowrites '{"tracker":{"type":"github","writes":false}}')"
CFG_JIRA="$(mkcfg jira '{"tracker":{"type":"jira"}}')"
CFG_SPACED="$(mkcfg spaced '{"tracker":{"type":"github","labels":{"claimed":"in progress"}}}')"
CFG_BROKEN="$(mkcfg broken '{"tracker": {"type": ')"
CFG_ABSENT="$TMP/definitely-not-here.json"

echo "second-shift-unclaim selftest:"

# (1) both roles configured and both present -> both removed, under the configured names.
run "$CFG_CUSTOM" "$CARRIES_BOTH_CUSTOM" 42
check "C1 configured labels: exit 0"                   "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C1 configured labels: read targets issue 42"    "$(echo "$CALLS" | grep -q 'repos/{owner}/{repo}/issues/42/labels$' && echo 0 || echo 1)"
check "C1 configured labels: DELETEs the configured claimed name" "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/claimed-custom' && echo 0 || echo 1)"
check "C1 configured labels: DELETEs the configured queue name"   "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/queue-custom' && echo 0 || echo 1)"

# (2) NO config file at all — the marketplace repo's own state in CI, since it gitignores
#     its config. Both defaults are operative. The DELETE assertions subsume "did not
#     abort": a script treating an absent config as fatal never reaches either call.
run "$CFG_ABSENT" "$CARRIES_BOTH_DEFAULT" 7
check "C2 absent config: DELETEs both shipped defaults" \
      "$(echo "$CALLS" | grep -q 'labels/in-progress' && echo "$CALLS" | grep -q 'labels/ready-for-dev' && echo 0 || echo 1)"

# (3) config present, labels.* absent -> jq yields the string "null".
#     Kills the null-string half of the resolver's guard (C2 cannot: no file is read).
run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" 7
check "C3 config without labels.*: DELETEs both defaults" \
      "$(echo "$CALLS" | grep -q 'labels/in-progress' && echo "$CALLS" | grep -q 'labels/ready-for-dev' && echo 0 || echo 1)"

# (4) unparseable config -> jq exits non-zero and yields an EMPTY value.
#     Kills the empty-value half of the same guard, which C3 cannot reach. An unreadable
#     config must degrade to the defaults, never abort — and reaching the DELETEs proves it.
run "$CFG_BROKEN" "$CARRIES_BOTH_DEFAULT" 7
check "C4 unparseable config: DELETEs both defaults" \
      "$(echo "$CALLS" | grep -q 'labels/in-progress' && echo "$CALLS" | grep -q 'labels/ready-for-dev' && echo 0 || echo 1)"

# (5) tracker.writes false -> stated no-op, ZERO api calls.
run "$CFG_NOWRITES" "$CARRIES_BOTH_DEFAULT" 42
check "C5 writes:false: exit 0"                        "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
# The count and the message die together under every mutant either catches, so they are
# one assertion: the silence is only meaningful if the log says why it was silent.
check "C5 writes:false: zero api calls, arm named" \
      "$([ "$NCALLS" -eq 0 ] && echo "$OUT" | grep -q 'tracker.writes is false' && echo 0 || echo 1)"

# (6) non-github tracker, writes NOT declared -> isolates the type arm from the writes arm.
run "$CFG_JIRA" "$CARRIES_BOTH_DEFAULT" 42
check "C6 jira tracker: exit 0"                        "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C6 jira tracker: zero api calls, arm named" \
      "$([ "$NCALLS" -eq 0 ] && echo "$OUT" | grep -q "tracker.type is 'jira'" && echo 0 || echo 1)"

# (7) the item carried neither label -> the COMMON case. One read, no write.
run "$CFG_BARE" "$CARRIES_NEITHER" 42
check "C7 neither label: exit 0"                       "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C7 neither label: exactly one api call, and not a DELETE" \
      "$([ "$NCALLS" -eq 1 ] && [ "$(deletes)" -eq 0 ] && echo 0 || echo 1)"

# (8) ONLY the queue label present — a crashed claim swap that then closed. Exactly one
#     DELETE, and it is the queue one: proves the two roles are released independently
#     rather than as a pair.
run "$CFG_BARE" "$CARRIES_QUEUE_ONLY" 42
check "C8 queue label only: exactly one DELETE"        "$([ "$(deletes)" -eq 1 ] && echo 0 || echo 1)"
check "C8 queue label only: it is the queue label"     "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/ready-for-dev' && echo 0 || echo 1)"

# (9) a multi-word label is percent-encoded — it is a PATH segment.
run "$CFG_SPACED" "$CARRIES_SPACED" 42
check "C9 spaced label: DELETE path encoded, raw space never sent" \
      "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/in%20progress' \
         && ! echo "$CALLS" | grep -q 'labels/in progress' && echo 0 || echo 1)"

# (10) the read and the delete are not atomic: a concurrent removal is success, not failure.
STUB_DELETE_RC=1 STUB_DELETE_ERR="gh: Not Found (HTTP 404)" run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" 42
check "C10 delete races to 404: exit 0"                "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C10 delete races to 404: says already gone"     "$(echo "$OUT" | grep -q 'already gone' && echo 0 || echo 1)"
unset STUB_DELETE_RC STUB_DELETE_ERR

# (11) any other delete failure is a real failure — a broken token must surface.
STUB_DELETE_RC=1 STUB_DELETE_ERR="gh: Resource not accessible by integration (HTTP 403)" run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" 42
check "C11 delete 403: exit 1"                         "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
unset STUB_DELETE_RC STUB_DELETE_ERR

# (12) a failure on the FIRST label must not skip the second. Only the claimed DELETE is
#      failed; the queue DELETE must still have been issued, and the run must still be red.
STUB_DELETE_RC=1 STUB_DELETE_ERR="gh: HTTP 403" STUB_FAIL_ON="in-progress" \
  run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" 42
check "C12 first label fails: second still attempted, exit 1" \
      "$([ "$RC" -eq 1 ] && echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/ready-for-dev' && echo 0 || echo 1)"
unset STUB_DELETE_RC STUB_DELETE_ERR STUB_FAIL_ON

# (13) an unreadable issue must NOT be reported as "not claimed". Only the exit code is
#      asserted: with an empty read body no mutant can reach a DELETE, so a companion
#      "no DELETE issued" line here would be un-failable.
STUB_READ_RC=1 run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" 42
check "C13 read failure: exit 1"                       "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
unset STUB_READ_RC

# (14)/(15) usage. The numeric half of the guard is also what keeps the argument out of an
# API path, so C15 asserts the exit code and the silence together — removing that half of
# the guard is the one mutant, and two lines for it would be one line of theatre.
run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT"
check "C14 no issue number: exit 2"                    "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
run "$CFG_BARE" "$CARRIES_BOTH_DEFAULT" '42; rm -rf /'
check "C15 non-numeric issue number: exit 2, zero api calls" \
      "$([ "$RC" -eq 2 ] && [ "$NCALLS" -eq 0 ] && echo 0 || echo 1)"

# (16) a missing prerequisite is a loud failure, never a silent skip: guessing the tracker
#      vocabulary could write to a tracker that declares it takes no writes. PATH holds the
#      gh stub and nothing else, so jq is genuinely absent — which is also why the
#      interpreter is invoked by absolute path here (PATH would not resolve `bash` either).
#      One assertion, deliberately: a script with the preflight deleted also exits non-zero
#      (it dies later, on the missing tool), so an exit-code line on its own would stay
#      green through the very mutant this case exists to catch. Naming the tool is what
#      only the live guard can produce.
BASH_BIN="$(command -v bash)"
: > "$TMP/calls"
OUT="$(PATH="$STUB_DIR" GH_CALLS="$TMP/calls" SECOND_SHIFT_CONFIG="$CFG_BARE" \
       SECOND_SHIFT_REPO_ROOT="$TMP" "$BASH_BIN" "$TOOL" 42 2>&1)"; RC=$?
check "C16 jq absent: exit 1 naming the missing tool" \
      "$([ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'jq is not on PATH' && echo 0 || echo 1)"

# (17) BOTH env seams unset — the production path, and the ONLY case that exercises the
#      two default expansions or the rev-parse fallback at all. Every case above pins the
#      config path directly, so a mutant on either of those lines survives all of them
#      while the real workflow, which sets neither, resolves nothing. A throwaway git repo,
#      no network: the label must come from a config found by deriving the root from git.
GITREPO="$TMP/derived"
git init -q "$GITREPO" 2>/dev/null
mkdir -p "$GITREPO/.claude"
printf '%s' '{"tracker":{"type":"github","labels":{"claimed":"derived-label"}}}' \
  > "$GITREPO/.claude/second-shift.config.json"
: > "$TMP/calls"
( cd "$GITREPO" && PATH="$STUB_DIR:$PATH" GH_CALLS="$TMP/calls" \
    STUB_LABELS_JSON='[{"name":"derived-label"}]' \
    env -u SECOND_SHIFT_CONFIG -u SECOND_SHIFT_REPO_ROOT bash "$TOOL" 42 ) >/dev/null 2>&1
check "C17 both seams unset: config resolved via the derived repo root" \
      "$(grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/derived-label' "$TMP/calls" && echo 0 || echo 1)"

echo "second-shift-unclaim selftest: $FAILS failure(s)"
exit "$FAILS"
