#!/usr/bin/env bash
# second-shift-ci-check-selftest.sh — hermetic selftest for the consumer CI evidence gate.
# Contract: exit = number of FAILED checks; ref lockstep drift and a real config-lint
# violation are FAILs; "couldn't verify" (fetch/tool failure) is a non-fatal WARN. The
# config-lint fetch is stubbed via SECOND_SHIFT_CONFIG_LINT so no case touches the network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-ci-check.sh"
YML="$HERE/second-shift-ci.yml"
FAILS=0
check() { if [ "$2" -eq 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# stub config-lint: SECOND_SHIFT_CONFIG_LINT points here; its exit code is controlled
# by the STUB_RC env var so one stub covers both the pass and violation cases.
STUB="$TMP/config-lint-stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_RC:-0}"
EOF
chmod +x "$STUB"

# Build a consumer repo fixture. $1 = settings ref, $2 = lockfile ref, $3 = lockfile repo.
make_repo() {
  local dir="$1" set_ref="$2" lock_ref="$3" lock_repo="$4"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/settings.json" <<EOF
{ "extraKnownMarketplaces": { "second-shift": { "source": { "source": "github", "repo": "$lock_repo", "ref": "$set_ref" } } } }
EOF
  cat > "$dir/.claude/second-shift.lock.json" <<EOF
{ "lockfileVersion": 1, "marketplace": { "name": "second-shift", "repo": "$lock_repo", "ref": "$lock_ref" }, "plugins": { "dev-pipeline": "2.2.4" }, "generatedBy": "second-shift:onboard@1.5.0" }
EOF
  cat > "$dir/.claude/second-shift.config.json" <<'EOF'
{ "configVersion": 2, "tracker": { "type": "github" }, "topology": { "type": "standalone", "repos": { "r": { "path": ".", "baseBranch": "main" } } }, "commands": { "r": {} } }
EOF
}

echo "second-shift-ci-check selftest:"

# (1) matched refs + stub lint exits 0 → all OK, exit 0
make_repo "$TMP/ok" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/ok" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "matched refs + lint ok: exit 0"                 "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "matched refs: reports ref lockstep OK"          "$(grep -q "settings ref == lockfile ref" <<<"$out" && echo 0 || echo 1)"
check "matched refs: reports config-lint passed"       "$(grep -q "config-lint passed" <<<"$out" && echo 0 || echo 1)"

# (2 · AC-3) drifted refs → FAIL, "disagree", exit >=1
make_repo "$TMP/drift" "v9.8.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/drift" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "drifted refs: exit >=1 (AC-3)"                  "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "drifted refs: FAIL names the disagreement (AC-3)" "$(grep -q "disagree" <<<"$out" && grep -q "FAIL" <<<"$out" && echo 0 || echo 1)"

# (3 · AC-2) config-lint violation → FAIL, exit >=1
make_repo "$TMP/lintfail" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/lintfail" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=1 bash "$TOOL")"; rc=$?
check "config-lint violation: exit >=1 (AC-2)"         "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "config-lint violation: FAIL names it (AC-2)"    "$(grep -q "config-lint reported violations" <<<"$out" && echo 0 || echo 1)"

# (4) canary form (ref: main) matched → exit 0
make_repo "$TMP/canary" "main" "main" "manoldonev/second-shift"
out="$(cd "$TMP/canary" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "canary ref main matched: exit 0"                "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# (5) couldn't-verify is a WARN, not a FAIL: matched refs, no config-lint seam, empty
#     lockfile repo forces the fetch to be skipped with a WARN (no network) → exit 0.
make_repo "$TMP/warn" "v9.9.0" "v9.9.0" ""
out="$(cd "$TMP/warn" && unset SECOND_SHIFT_CONFIG_LINT; bash "$TOOL")"; rc=$?
check "fetch un-verifiable: exit stays 0 (WARN not FAIL)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "fetch un-verifiable: emits a WARN line"         "$(grep -q "WARN" <<<"$out" && grep -q "could not verify" <<<"$out" && echo 0 || echo 1)"

# (6) missing lockfile → FAIL, exit >=1
mkdir -p "$TMP/nolock/.claude"
out="$(cd "$TMP/nolock" && bash "$TOOL")"; rc=$?
check "no lockfile: exit >=1"                          "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"

# (6b) missing settings.json → FAIL
make_repo "$TMP/noset" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
rm -f "$TMP/noset/.claude/settings.json"
out="$(cd "$TMP/noset" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "no settings.json: exit >=1"                     "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"

# (6c) missing config.json → FAIL
make_repo "$TMP/nocfg" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
rm -f "$TMP/nocfg/.claude/second-shift.config.json"
out="$(cd "$TMP/nocfg" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "no config.json: exit >=1"                       "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"

# (6d) empty settings marketplace ref → FAIL ("no marketplace ref pin")
make_repo "$TMP/norefpin" "" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/norefpin" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "empty settings ref: exit >=1"                   "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "empty settings ref: names the missing pin"     "$(grep -q "no marketplace ref pin" <<<"$out" && echo 0 || echo 1)"

# (7) the emitted workflow YAML wires the check correctly
check "yml: triggers on pull_request"                  "$(grep -q "pull_request" "$YML" && echo 0 || echo 1)"
check "yml: runs the check script"                     "$(grep -q "second-shift-ci-check.sh" "$YML" && echo 0 || echo 1)"
check "yml: passes github.token as GH_TOKEN"           "$(grep -q "GH_TOKEN" "$YML" && grep -q "github.token" "$YML" && echo 0 || echo 1)"
check "yml: job name matches the documented required-status-check context" "$(grep -q "name: second-shift evidence" "$YML" && echo 0 || echo 1)"

# AC-4 (#444). The evidence payload's `since:`-bearing arms compare against PR_CREATED_AT, and
# they treat it as OPTIONAL on purpose — an absent value declines rather than reds — so a
# template that stopped supplying it silently loses those arms instead of failing. That is
# exactly the drift this file exists to catch, and the template has NO live signal (no consumer
# CI runs in this repo), so the wiring is pinned structurally here.
# Anchored against the step's ENV BLOCK rather than the file, on the permissions block's
# precedent below: a commented-out line elsewhere in the YAML must not satisfy it.
STEPENV="$(awk '/^        env:/{f=1;next} f&&/^        [^ ]/{f=0} f' "$YML")"
# shellcheck disable=SC2016  # the ${{ }} is GitHub Actions template syntax; the shell must not expand it.
check "yml: env supplies PR_CREATED_AT from the PR's open instant (AC-4)" \
  "$(grep -qF 'PR_CREATED_AT: ${{ github.event.pull_request.created_at }}' <<<"$STEPENV" && echo 0 || echo 1)"

# (8) gh fetch paths (stubbed gh on PATH; SECOND_SHIFT_CONFIG_LINT unset so the fetch runs).
# 404 = the pinned ref / linter path does not exist = DRIFT = FAIL, never a warn-green.
mkdir -p "$TMP/bin404"
printf '#!/usr/bin/env bash\necho "gh: Not Found (HTTP 404)" >&2\nexit 1\n' > "$TMP/bin404/gh"
chmod +x "$TMP/bin404/gh"
make_repo "$TMP/gh404" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/gh404" && env -u SECOND_SHIFT_CONFIG_LINT PATH="$TMP/bin404:$PATH" bash "$TOOL")"; rc=$?
check "gh 404: exit >=1 (nonexistent pinned ref IS drift)"  "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "gh 404: classified FAIL naming HTTP 404"             "$(grep -q "FAIL" <<<"$out" && grep -q "HTTP 404" <<<"$out" && echo 0 || echo 1)"

# network/auth error stays a non-fatal WARN (an infra blip must not red-X a clean PR).
mkdir -p "$TMP/binnet"
printf '#!/usr/bin/env bash\necho "gh: error connecting to api.github.com" >&2\nexit 1\n' > "$TMP/binnet/gh"
chmod +x "$TMP/binnet/gh"
make_repo "$TMP/ghnet" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/ghnet" && env -u SECOND_SHIFT_CONFIG_LINT PATH="$TMP/binnet:$PATH" bash "$TOOL")"; rc=$?
check "gh network error: exit 0 (non-fatal WARN)"           "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "gh network error: says could not verify"             "$(grep -q "could not verify" <<<"$out" && echo 0 || echo 1)"

# fetch success: the base64 pipeline decodes and executes the fetched linter.
mkdir -p "$TMP/binok"
printf '#!/usr/bin/env bash\nprintf %%s "IyEvdXNyL2Jpbi9lbnYgYmFzaApleGl0IDAK"\n' > "$TMP/binok/gh"
chmod +x "$TMP/binok/gh"
make_repo "$TMP/ghok" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/ghok" && env -u SECOND_SHIFT_CONFIG_LINT PATH="$TMP/binok:$PATH" bash "$TOOL")"; rc=$?
check "gh fetch success: exit 0 and config-lint passed"     "$([ "$rc" -eq 0 ] && grep -q "config-lint passed" <<<"$out" && echo 0 || echo 1)"

# (9 · #359) the lean-evidence arm. The payload is stubbed through SECOND_SHIFT_LEAN_EVIDENCE
# so no case touches the network; what is under test here is the WIRING — that the arm runs on
# a PR, that the payload's exit code lands in the right FAIL/WARN bucket, and that a moved
# payload path is drift. The payload's own semantics are lean-evidence-selftest.sh's subject.
EVSTUB="$TMP/lean-evidence-stub.sh"
cat > "$EVSTUB" <<'EOF'
#!/usr/bin/env bash
echo "[lean-evidence] stub speaking"
exit "${EV_STUB_RC:-0}"
EOF
chmod +x "$EVSTUB"

# The PR context the template supplies. Any non-empty PR_HEAD_REF makes the arm applicable;
# whether the PR is LEAN is the payload's call, not this file's.
ev_run() { # ev_run <dir> <stub-rc>
  ( cd "$1" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 \
      SECOND_SHIFT_LEAN_EVIDENCE="$EVSTUB" EV_STUB_RC="$2" \
      PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA=deadbeef PR_BASE_REF=main PR_NUMBER=9 \
      PR_BODY="Closes #42" GH_REPO="acme/acme" bash "$TOOL" )
}

make_repo "$TMP/ev" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(ev_run "$TMP/ev" 0)"; rc=$?
check "lean evidence complete: exit 0 (AC-2)"          "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "lean evidence complete: reports OK (AC-2)"      "$(grep -q "OK    lean evidence" <<<"$out" && echo 0 || echo 1)"
check "lean evidence: the payload actually ran"        "$(grep -q "stub speaking" <<<"$out" && echo 0 || echo 1)"

out="$(ev_run "$TMP/ev" 1)"; rc=$?
check "lean evidence violation: exit >=1 (AC-2)"       "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "lean evidence violation: FAIL names it (AC-2)"  "$(grep -q "missing merge-boundary evidence" <<<"$out" && echo 0 || echo 1)"

# exit 2 is the payload saying it could not run — a missing input this template owns. FAIL, not
# the transient "could not verify" WARN: failing it open would waive the arm on a workflow that
# quietly stopped passing PR_BASE_REF, and the gate would read green forever after.
out="$(ev_run "$TMP/ev" 2)"; rc=$?
check "lean evidence unrunnable: exit >=1, not a warn-green (AC-2)" "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "lean evidence unrunnable: FAIL says it could not run"        "$(grep -q "could not run" <<<"$out" && echo 0 || echo 1)"

# No PR context at all (a workflow_dispatch run): not applicable, and never a failure.
out="$(cd "$TMP/ev" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 SECOND_SHIFT_LEAN_EVIDENCE="$EVSTUB" bash "$TOOL")"; rc=$?
check "no PR context: exit 0"                          "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "no PR context: reported not applicable"         "$(grep -q "no PR context" <<<"$out" && echo 0 || echo 1)"
check "no PR context: the payload did not run"         "$(grep -q "stub speaking" <<<"$out" && echo 1 || echo 0)"

# A MOVED PAYLOAD PATH is drift (AC-2). The 404 stub answers every fetch, so the config-lint arm
# fails too — this asserts the lean arm's own 404 line, which is the one that would otherwise
# be missing entirely if the path were never fetched.
make_repo "$TMP/ev404" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/ev404" && env -u SECOND_SHIFT_CONFIG_LINT -u SECOND_SHIFT_LEAN_EVIDENCE \
        PATH="$TMP/bin404:$PATH" PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA=deadbeef PR_BASE_REF=main \
        PR_NUMBER=9 PR_BODY="Closes #42" GH_REPO="acme/acme" bash "$TOOL")"; rc=$?
check "lean payload 404: exit >=1 (a moved path IS drift) (AC-2)" "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "lean payload 404: FAIL names the payload path and the 404 (AC-2)" \
  "$(grep -q "lean-evidence: plugins/dev-pipeline/skills/run-lean/lean-evidence.sh does not exist" <<<"$out" \
     && grep -q "HTTP 404" <<<"$out" && echo 0 || echo 1)"

# ...and a network/auth failure fetching the payload stays a non-fatal WARN, same as (a)'s.
out="$(cd "$TMP/ev404" && env -u SECOND_SHIFT_CONFIG_LINT -u SECOND_SHIFT_LEAN_EVIDENCE \
        PATH="$TMP/binnet:$PATH" PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA=deadbeef PR_BASE_REF=main \
        PR_NUMBER=9 PR_BODY="Closes #42" GH_REPO="acme/acme" bash "$TOOL")"; rc=$?
check "lean payload network error: exit 0 (non-fatal WARN)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "lean payload network error: says could not verify"   "$(grep -q "lean-evidence: could not verify" <<<"$out" && echo 0 || echo 1)"

# (10 · #359) the emitted workflow supplies what the payload needs. Each of these is an input
# whose absence makes the payload exit 2 — which the arm above scores FAIL — so a template that
# dropped one would red every adopting repo's lean PRs.
check "yml: checkout is full-history (fetch-depth: 0)"  "$(grep -q "fetch-depth: 0" "$YML" && echo 0 || echo 1)"
for v in GH_REPO PR_NUMBER PR_HEAD_REF PR_HEAD_SHA PR_BASE_REF PR_BODY; do
  check "yml: step env carries $v"                      "$(grep -q "$v:" "$YML" && echo 0 || echo 1)"
done
# The TOKEN SCOPES are an input in exactly that sense, and the one a reader cannot see is
# missing: a `permissions:` key replaces the defaults wholesale, so a scope omitted here is
# `none` and the identity arm's `gh api repos/O/R/issues/N/comments` read is denied — payload
# exit 2, scored FAIL, on every lean PR. Asserted against the BLOCK, not the whole file, so a
# `contents: read` appearing in a comment cannot satisfy it. Mirrors this repo's own pr-gates
# job, which carries the same three for the same read.
PERMS="$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f' "$YML")"
for p in "contents: read" "issues: read" "pull-requests: read"; do
  check "yml: permissions block grants $p (AC-2)"       "$(grep -q "^  $p\$" <<<"$PERMS" && echo 0 || echo 1)"
done
# The blast-radius rule the block's comment states, as an assertion rather than prose: a fetched
# script runs under this token, so a write scope here is a standing escalation.
check "yml: permissions block grants no write scope (AC-2)" "$(grep -q ": write" <<<"$PERMS" && echo 1 || echo 0)"

if [ "$FAILS" -gt 0 ]; then echo "second-shift-ci-check selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "second-shift-ci-check selftest: all green"
