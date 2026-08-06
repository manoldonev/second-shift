#!/usr/bin/env bash
# second-shift-unclaim-selftest.sh — hermetic selftest for the claimed-label release.
#
# Contract pinned here: the label name resolves live from a readable config and falls
# through to the shipped default otherwise; a tracker that takes no writes and a tracker
# that is not github are STATED no-ops with zero API calls; an item that never carried
# the label is a no-op with zero WRITES; a label lost to a race is still success; and a
# real API failure is a real failure rather than a quiet green.
#
# Nothing touches the network: gh is stubbed on PATH, records its argv, and returns a
# status the case controls. Every case asserts on the recorded argv AND the exit code, so
# no two cases are distinguished only by their fixture.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-unclaim.sh"
REPO_YML="$HERE/../../../../.github/workflows/unclaim-on-close.yml"
CONSUMER_YML="$HERE/second-shift-unclaim.yml"
FAILS=0
check() { if [ "$2" -eq 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- the gh stub -----------------------------------------------------------
# Distinguishes the labels READ from the label DELETE by the -X DELETE argument.
# Knobs: STUB_LABELS_JSON (read body), STUB_READ_RC, STUB_DELETE_RC, STUB_DELETE_ERR.
STUB_DIR="$TMP/bin"; mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
for a in "$@"; do
  if [ "$a" = "DELETE" ]; then
    printf '%s\n' "${STUB_DELETE_ERR:-}" >&2
    exit "${STUB_DELETE_RC:-0}"
  fi
done
if [ "${STUB_READ_RC:-0}" -ne 0 ]; then
  echo "HTTP 403: Resource not accessible by integration" >&2
  exit "${STUB_READ_RC:-0}"
fi
printf '%s' "${STUB_LABELS_JSON:-[]}"
EOF
chmod +x "$STUB_DIR/gh"

CARRIES_DEFAULT='[{"name":"bug"},{"name":"in-progress"}]'
CARRIES_CUSTOM='[{"name":"claimed-custom"}]'
CARRIES_SPACED='[{"name":"in progress"}]'
CARRIES_NEITHER='[{"name":"bug"},{"name":"ready-for-dev"}]'

# run <config-path> <labels-json> <issue-arg...> -> sets RC, OUT, CALLS
run() {
  local cfg="$1" labels="$2"; shift 2
  GH_CALLS="$TMP/calls"; : > "$GH_CALLS"
  OUT="$(PATH="$STUB_DIR:$PATH" GH_CALLS="$GH_CALLS" \
         STUB_LABELS_JSON="$labels" \
         STUB_READ_RC="${STUB_READ_RC:-0}" \
         STUB_DELETE_RC="${STUB_DELETE_RC:-0}" \
         STUB_DELETE_ERR="${STUB_DELETE_ERR:-}" \
         SECOND_SHIFT_CONFIG="$cfg" SECOND_SHIFT_REPO_ROOT="$TMP" \
         bash "$TOOL" "$@" 2>&1)"
  RC=$?
  CALLS="$(cat "$GH_CALLS")"
  NCALLS="$(grep -c . "$GH_CALLS")"
}

mkcfg() { printf '%s' "$2" > "$TMP/$1.json"; echo "$TMP/$1.json"; }

CFG_CUSTOM="$(mkcfg custom '{"tracker":{"type":"github","labels":{"claimed":"claimed-custom"}}}')"
CFG_BARE="$(mkcfg bare '{"tracker":{"type":"github"}}')"
CFG_NOWRITES="$(mkcfg nowrites '{"tracker":{"type":"github","writes":false}}')"
CFG_JIRA="$(mkcfg jira '{"tracker":{"type":"jira"}}')"
CFG_SPACED="$(mkcfg spaced '{"tracker":{"type":"github","labels":{"claimed":"in progress"}}}')"
CFG_BROKEN="$(mkcfg broken '{"tracker": {"type": ')"
CFG_ABSENT="$TMP/definitely-not-here.json"

echo "second-shift-unclaim selftest:"

# (1) configured label + the issue carries it -> DELETE that exact label, exit 0.
run "$CFG_CUSTOM" "$CARRIES_CUSTOM" 42
check "C1 configured label: exit 0"                    "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C1 configured label: read targets issue 42"     "$(echo "$CALLS" | grep -q 'repos/{owner}/{repo}/issues/42/labels$' && echo 0 || echo 1)"
check "C1 configured label: DELETE carries the configured name" "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/claimed-custom' && echo 0 || echo 1)"

# (2) NO config file at all — the marketplace repo's own state in CI, since it gitignores
#     its config. The default is operative. The DELETE assertion subsumes "did not abort":
#     a script that treated an absent config as fatal never reaches the call.
run "$CFG_ABSENT" "$CARRIES_DEFAULT" 7
check "C2 absent config: DELETE uses the shipped default" "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/7/labels/in-progress' && echo 0 || echo 1)"

# (3) config present, labels.claimed absent -> jq yields the string "null".
#     Kills the null-string half of the resolver's guard (C2 cannot: no file is read).
run "$CFG_BARE" "$CARRIES_DEFAULT" 7
check "C3 config without labels.claimed: DELETE uses the default" "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/7/labels/in-progress' && echo 0 || echo 1)"

# (4) unparseable config -> jq exits non-zero and yields an EMPTY value.
#     Kills the empty-value half of the same guard, which C3 cannot reach. An unreadable
#     config must degrade to the default, never abort — and reaching the DELETE at all is
#     what proves it did not abort.
run "$CFG_BROKEN" "$CARRIES_DEFAULT" 7
check "C4 unparseable config: DELETE uses the default" "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/7/labels/in-progress' && echo 0 || echo 1)"

# (5) tracker.writes false -> stated no-op, ZERO api calls.
run "$CFG_NOWRITES" "$CARRIES_DEFAULT" 42
check "C5 writes:false: exit 0"                        "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C5 writes:false: zero api calls"                "$([ "$NCALLS" -eq 0 ] && echo 0 || echo 1)"
check "C5 writes:false: names the arm"                 "$(echo "$OUT" | grep -q 'tracker.writes is false' && echo 0 || echo 1)"

# (6) non-github tracker, writes NOT declared -> isolates the type arm from the writes arm.
run "$CFG_JIRA" "$CARRIES_DEFAULT" 42
check "C6 jira tracker: exit 0"                        "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C6 jira tracker: zero api calls"                "$([ "$NCALLS" -eq 0 ] && echo 0 || echo 1)"
check "C6 jira tracker: names the arm"                 "$(echo "$OUT" | grep -q "tracker.type is 'jira'" && echo 0 || echo 1)"

# (7) the issue never carried the label -> the COMMON case. One read, no write.
run "$CFG_BARE" "$CARRIES_NEITHER" 42
check "C7 label absent: exit 0"                        "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C7 label absent: exactly one api call"          "$([ "$NCALLS" -eq 1 ] && echo 0 || echo 1)"
check "C7 label absent: no DELETE issued"              "$(echo "$CALLS" | grep -q 'DELETE' && echo 1 || echo 0)"

# (8) a multi-word label is percent-encoded — it is a PATH segment.
run "$CFG_SPACED" "$CARRIES_SPACED" 42
check "C8 spaced label: DELETE path is encoded"        "$(echo "$CALLS" | grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/in%20progress' && echo 0 || echo 1)"
check "C8 spaced label: raw space never sent"          "$(echo "$CALLS" | grep -q 'labels/in progress' && echo 1 || echo 0)"

# (9) the read and the delete are not atomic: a concurrent removal is success, not failure.
STUB_DELETE_RC=1 STUB_DELETE_ERR="gh: Not Found (HTTP 404)" run "$CFG_BARE" "$CARRIES_DEFAULT" 42
check "C9 delete races to 404: exit 0"                 "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
check "C9 delete races to 404: says already gone"      "$(echo "$OUT" | grep -q 'already gone' && echo 0 || echo 1)"
unset STUB_DELETE_RC STUB_DELETE_ERR

# (10) any other delete failure is a real failure — a broken token must surface.
STUB_DELETE_RC=1 STUB_DELETE_ERR="gh: Resource not accessible by integration (HTTP 403)" run "$CFG_BARE" "$CARRIES_DEFAULT" 42
check "C10 delete 403: exit 1"                         "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
unset STUB_DELETE_RC STUB_DELETE_ERR

# (11) an unreadable issue must NOT be reported as "not claimed". Only the exit code is
#      asserted: with an empty read body no mutant can reach a DELETE, so a companion
#      "no DELETE issued" line here would be un-failable.
STUB_READ_RC=1 run "$CFG_BARE" "$CARRIES_DEFAULT" 42
check "C11 read failure: exit 1"                       "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
unset STUB_READ_RC

# (12)/(13) usage. The numeric half of the guard is also what keeps the argument out of an
# API path, so C13 asserts the exit code and the silence together — removing that half of
# the guard is the one mutant, and two lines for it would be one line of theatre.
run "$CFG_BARE" "$CARRIES_DEFAULT"
check "C12 no issue number: exit 2"                    "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
run "$CFG_BARE" "$CARRIES_DEFAULT" '42; rm -rf /'
check "C13 non-numeric issue number: exit 2, zero api calls" \
      "$([ "$RC" -eq 2 ] && [ "$NCALLS" -eq 0 ] && echo 0 || echo 1)"

# (14) a missing prerequisite is a loud failure, never a silent skip: guessing the tracker
#      vocabulary could write to a tracker that declares it takes no writes. PATH holds the
#      gh stub and nothing else, so jq is genuinely absent — which is also why the
#      interpreter is invoked by absolute path here (PATH would not resolve `bash` either).
BASH_BIN="$(command -v bash)"
: > "$TMP/calls"
OUT="$(PATH="$STUB_DIR" GH_CALLS="$TMP/calls" SECOND_SHIFT_CONFIG="$CFG_BARE" \
       SECOND_SHIFT_REPO_ROOT="$TMP" "$BASH_BIN" "$TOOL" 42 2>&1)"; RC=$?
#      One assertion, deliberately: a script with the preflight deleted also exits non-zero
#      (it dies later, on the missing tool), so an exit-code line on its own here would stay
#      green through the very mutant this case exists to catch. Naming the tool is what only
#      the live guard can produce.
check "C14 jq absent: exit 1 naming the missing tool" \
      "$([ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'jq is not on PATH' && echo 0 || echo 1)"

# (15) BOTH env seams unset — the production path, and the ONLY case that exercises the
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
check "C15 both seams unset: config resolved via the derived repo root" \
      "$(grep -q 'DELETE repos/{owner}/{repo}/issues/42/labels/derived-label' "$TMP/calls" && echo 0 || echo 1)"

# ---- workflow wiring -------------------------------------------------------
# These pin the WIRING of two files that are never executed on the path under test — the
# narrowed grep sanction, same shape as second-shift-ci-check-selftest.sh's yml cases.
# The trigger and the issues:write grant are what make the script reachable at all.
#
# The two pins below are Actions and shell syntax that must appear VERBATIM in the workflow
# files; single quotes are exactly what keeps them unexpanded here, so SC2016 is the
# intended reading, not a bug.
# shellcheck disable=SC2016
ISSUE_ENV_PIN='ISSUE_NUMBER: ${{ github.event.issue.number }}'
# shellcheck disable=SC2016
ISSUE_ARG_PIN='bash '
# shellcheck disable=SC2016
ISSUE_ARG_TAIL=' "$ISSUE_NUMBER"'

for pair in "repo:$REPO_YML:plugins/second-shift/templates/consumer/second-shift-unclaim.sh:secrets.GITHUB_TOKEN" \
            "consumer:$CONSUMER_YML:.claude/tools/second-shift-unclaim.sh:github.token"; do
  who="${pair%%:*}"; rest="${pair#*:}"
  yml="${rest%%:*}"; rest="${rest#*:}"
  script="${rest%%:*}"; token="${rest#*:}"
  # No "file exists" line: grep against a missing path reds every pin below it, so one
  # would kill nothing the rest do not already catch.
  check "yml($who): triggers on issues closed"         "$(grep -qF 'types: [closed]' "$yml" && grep -qF 'issues:' "$yml" && echo 0 || echo 1)"
  check "yml($who): grants issues: write"              "$(grep -qF 'issues: write' "$yml" && echo 0 || echo 1)"
  check "yml($who): grants contents: read"             "$(grep -qF 'contents: read' "$yml" && echo 0 || echo 1)"
  check "yml($who): invokes $script with the env-borne issue number" \
        "$(grep -qF "$ISSUE_ARG_PIN$script$ISSUE_ARG_TAIL" "$yml" && echo 0 || echo 1)"
  check "yml($who): passes the token as GH_TOKEN"      "$(grep -qF "GH_TOKEN: \${{ $token }}" "$yml" && echo 0 || echo 1)"
  check "yml($who): issue number rides in env, not the run body" \
        "$(grep -qF "$ISSUE_ENV_PIN" "$yml" && echo 0 || echo 1)"
done

echo "second-shift-unclaim selftest: $FAILS failure(s)"
exit "$FAILS"
