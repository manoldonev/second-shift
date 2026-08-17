#!/usr/bin/env bash
# second-shift-delta-guard-selftest.sh — hermetic selftest for the consumer CI delta guard.
#
# Contract under test (#542): the guard writes `skip=true` to $GITHUB_OUTPUT for exactly one
# shape — a head commit whose whole delta is one lean verdict record, whose parent already has
# a COMPLETED SUCCESSFUL run of the CALLING workflow for the SAME event — and `skip=false` for
# everything else, including everything it could not read.
#
# The three verdicts AC-5 names are cases (1), (2) and (3). The rest of the file is the
# fail-closed set: every path that reaches a "cannot tell" must land on skip=false, because a
# short-circuit that guesses is the fail-open shape this guard exists to avoid.
#
# Hermetic: real git fixtures (cheap, and the delta computation is the thing under test — a
# stubbed `git diff` would be a mirror harness), a stubbed `gh` on PATH so nothing touches the
# network, and $GITHUB_OUTPUT pointed at a temp file so the emitted value is READ BACK rather
# than inferred from stdout.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-delta-guard.sh"
YML="$HERE/second-shift-delta-guard.yml"
FAILS=0
check() { if [ "$2" -eq 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --------------------------------------------------------------- fixture: a consumer repo
# $1 = dir, $2 = the path the HEAD commit touches. The parent commit is always a source
# change, so `parent..head` is exactly $2.
make_repo() {
  local dir="$1" head_path="$2"
  mkdir -p "$dir" && git -C "$dir" init -q -b main
  mkdir -p "$dir/src"
  echo one > "$dir/src/app.ts"
  git -C "$dir" add -A && git -C "$dir" commit -qm "code"
  mkdir -p "$dir/$(dirname "$head_path")"
  echo "verdict=approve" > "$dir/$head_path"
  git -C "$dir" add -A && git -C "$dir" commit -qm "head"
}

# A gh stub whose two answers are controlled by env vars, so one stub covers every case:
#   STUB_WORKFLOW_ID  what `actions/runs/<id>` reports as .workflow_id ("" = emit nothing)
#   STUB_RUNS         the JSON body for the `actions/runs?head_sha=…` query
#   STUB_RUNS_RC      non-zero to simulate an API failure on that query
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  *"actions/runs?head_sha="*) [ "${STUB_RUNS_RC:-0}" -eq 0 ] || { echo "gh: API error" >&2; exit 1; }
                              printf '%s' "${STUB_RUNS:-}" ;;
  *"actions/runs/"*)          printf '%s' "${STUB_WORKFLOW_ID:-}" ;;
  *)                          exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

runs_json() { # runs_json <workflow_id> <event> <status> <conclusion>
  printf '{"workflow_runs":[{"workflow_id":%s,"event":"%s","status":"%s","conclusion":%s}]}' \
    "$1" "$2" "$3" "$(if [ "$4" = null ]; then echo null; else echo "\"$4\""; fi)"
}

# Run the guard against a fixture. Echoes the value the guard EMITTED (not what it printed).
# $1 = repo dir; remaining args are `VAR=value` overrides for the stub / environment.
guard() {
  local dir="$1"; shift
  local out="$TMP/gh-output.$$"; : > "$out"
  local head; head="$(git -C "$dir" rev-parse HEAD)"
  ( cd "$dir" && env PATH="$TMP/bin:$PATH" GITHUB_OUTPUT="$out" \
      GH_REPO="acme/acme" GH_TOKEN=x PR_HEAD_SHA="$head" \
      GUARD_RUN_ID=777 GUARD_EVENT_NAME=pull_request \
      "$@" bash "$TOOL" ) >"$TMP/stdout" 2>&1
  GUARD_RC=$?
  GUARD_STDOUT="$(cat "$TMP/stdout")"
  GUARD_SKIP="$(sed -n 's/^skip=//p' "$out" | tail -n1)"
  rm -f "$out"
}

echo "second-shift-delta-guard selftest:"

# ---------------------------------------------------------------- (1 · AC-5) docs-only + parent green → SKIP
make_repo "$TMP/skip" "docs/plans/acme-42-lean-verdict.md"
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "docs-only verdict commit + parent green: skip=true (AC-5)"  "$([ "$GUARD_SKIP" = true ] && echo 0 || echo 1)"
check "docs-only verdict commit + parent green: exits 0"           "$([ "$GUARD_RC" -eq 0 ] && echo 0 || echo 1)"
check "skip decision names the parent's completed successful run"  "$(grep -q "completed, successful run" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# ---------------------------------------------------------------- (2 · AC-5) docs-only + parent CANCELLED → full run
# The #542 hazard itself: `cancel-in-progress: true` keyed on the ref let the verdict push kill
# the code commit's run. Skipping here would report a green head SHA whose code was never
# verified by anything — the inversion, laundered into a pass.
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed cancelled)"
check "docs-only verdict commit + parent cancelled: skip=false (AC-5)" "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "parent cancelled: the reason names what it saw"                 "$(grep -q "completed/cancelled" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# ---------------------------------------------------------------- (3 · AC-5) mixed diff → full run
make_repo "$TMP/mixed" "docs/plans/acme-42-lean-verdict.md"
echo two > "$TMP/mixed/src/app.ts"
git -C "$TMP/mixed" add -A && git -C "$TMP/mixed" commit -q --amend --no-edit
guard "$TMP/mixed" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "mixed diff (verdict + source): skip=false (AC-5)"           "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "mixed diff: the reason says it is not exactly one path"     "$(grep -q "not exactly one" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# A mixed delta whose LAST path is the verdict record. This is the ordering that a
# newline-stripped join of the file list would read as one string ending in the suffix — i.e.
# a skip on a delta containing source. Distinct from the case above, whose verdict record sorts
# first: only this ordering can reach that shape.
make_repo "$TMP/mixed_last" "zz-src/app2.ts"
echo "verdict=approve" > "$TMP/mixed_last/aa-lean-verdict.md"
git -C "$TMP/mixed_last" add -A && git -C "$TMP/mixed_last" commit -q --amend --no-edit
guard "$TMP/mixed_last" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "mixed diff with the verdict record LAST: skip=false"        "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# A single-file commit that is NOT a verdict record — the other half of "mixed": one path, but
# the wrong one. Without this, a guard that only counted paths would pass case (3).
make_repo "$TMP/otherdoc" "docs/README.md"
guard "$TMP/otherdoc" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "single non-verdict path: skip=false (AC-5)"                 "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "single non-verdict path: reason names the path it saw"      "$(grep -q "docs/README.md" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# The suffix is anchored at the END of the filename, never a substring. A file merely
# CONTAINING the token must not be read as a verdict record.
make_repo "$TMP/suffixish" "docs/plans/acme-42-lean-verdict.md.bak"
guard "$TMP/suffixish" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "suffix is anchored, not a substring: skip=false"            "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# ---------------------------------------------------------------- the trust condition's other outcomes (AC-2)
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS='{"workflow_runs":[]}'
check "parent has no run at all: skip=false (AC-2)"                "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "no parent run: the reason says 'saw: none'"                 "$(grep -q "saw: none" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request in_progress null)"
check "parent run still in progress: skip=false (AC-2)"            "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed failure)"
check "parent run failed: skip=false (AC-2)"                       "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# A DIFFERENT workflow's green on the parent must not license the skip — otherwise the cheap
# always-green evidence workflow would authorise skipping the expensive one.
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 12345 pull_request completed success)"
check "green run belongs to another workflow: skip=false (AC-2)"   "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# ...and so must a green from a different EVENT: the same workflow can run a different job set
# under `push` than under `pull_request`.
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 push completed success)"
check "green run belongs to another event: skip=false (AC-2)"      "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# ---------------------------------------------------------------- fail-closed on every unknown
guard "$TMP/skip" STUB_WORKFLOW_ID=99 STUB_RUNS_RC=1
check "Actions API read fails: skip=false"                         "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "API failure names the actions:read scope"                   "$(grep -q "actions: read" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

guard "$TMP/skip" STUB_WORKFLOW_ID="" STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "calling run does not resolve to a workflow id: skip=false"  "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

guard "$TMP/skip" GUARD_RUN_ID="" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "GUARD_RUN_ID unset: skip=false (any green would license it)" "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

guard "$TMP/skip" GUARD_EVENT_NAME="" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "GUARD_EVENT_NAME unset: skip=false"                          "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

guard "$TMP/skip" GH_REPO="" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "GH_REPO unset: skip=false"                                   "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"

# No PR context — a workflow_dispatch run. Not applicable, never a skip, and the API is not
# even consulted (nothing to consult it about).
guard "$TMP/skip" PR_HEAD_SHA="" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "no PR head SHA: skip=false"                                  "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "no PR head SHA: reported not applicable"                     "$(grep -q "not applicable" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# A head commit with no parent (a single-commit branch) is unreadable as a delta, not empty.
mkdir -p "$TMP/root" && git -C "$TMP/root" init -q -b main
echo one > "$TMP/root/a.txt"
git -C "$TMP/root" add -A && git -C "$TMP/root" commit -qm root
guard "$TMP/root" STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "head has no parent: skip=false"                              "$([ "$GUARD_SKIP" = false ] && echo 0 || echo 1)"
check "head has no parent: names the shallow-checkout cause"        "$(grep -q "fetch-depth: 2" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"

# gh missing from the runner entirely: the classification still succeeds, the trust condition
# cannot be evaluated, so the lane runs in full.
mkdir -p "$TMP/emptybin"
out="$TMP/gh-output.nogh"; : > "$out"
head="$(git -C "$TMP/skip" rev-parse HEAD)"
( cd "$TMP/skip" && env PATH="$TMP/emptybin:/usr/bin:/bin" GITHUB_OUTPUT="$out" \
    GH_REPO="acme/acme" PR_HEAD_SHA="$head" GUARD_RUN_ID=777 GUARD_EVENT_NAME=pull_request \
    bash "$TOOL" ) > "$TMP/stdout" 2>&1
check "gh absent from the runner: skip=false"                       "$([ "$(sed -n 's/^skip=//p' "$out" | tail -n1)" = false ] && echo 0 || echo 1)"

# ---------------------------------------------------------------- run outside Actions
# $GITHUB_OUTPUT is absent whenever the guard is run by hand — which is how a consumer finds
# out why their lane did NOT skip. The decision must still reach stdout, and the output write
# must be genuinely skipped rather than redirected somewhere: a guarded write whose fallback is
# a filename litters the working tree of whoever ran it, silently and once per invocation.
mkdir -p "$TMP/nooutput" && cp -R "$TMP/skip/." "$TMP/nooutput/"
BEFORE="$(find "$TMP/nooutput" -maxdepth 1 | sort | tr '\n' ' ')"
head="$(git -C "$TMP/nooutput" rev-parse HEAD)"
( cd "$TMP/nooutput" && env -u GITHUB_OUTPUT PATH="$TMP/bin:$PATH" \
    GH_REPO="acme/acme" GH_TOKEN=x PR_HEAD_SHA="$head" GUARD_RUN_ID=777 \
    GUARD_EVENT_NAME=pull_request STUB_WORKFLOW_ID=99 \
    STUB_RUNS="$(runs_json 99 pull_request completed success)" \
    bash "$TOOL" ) > "$TMP/stdout" 2>&1
AFTER="$(find "$TMP/nooutput" -maxdepth 1 | sort | tr '\n' ' ')"
check "no \$GITHUB_OUTPUT: the decision still reaches stdout"        "$(grep -q "skip=true" < "$TMP/stdout" && echo 0 || echo 1)"
check "no \$GITHUB_OUTPUT: writes no file into the working tree"     "$([ "$BEFORE" = "$AFTER" ] && echo 0 || echo 1)"

# ---------------------------------------------------------------- the annotation seam
# An "unknown" no-skip is a DIFFERENT event from a normal commit: the guard is inert and an
# operator needs to see it. A normal commit must NOT produce that annotation, or the signal is
# noise on every PR.
guard "$TMP/skip" GITHUB_ACTIONS=true STUB_WORKFLOW_ID=99 STUB_RUNS_RC=1
check "unreadable case emits a ::warning:: annotation"              "$(grep -q "::warning title=second-shift delta guard::" <<<"$GUARD_STDOUT" && echo 0 || echo 1)"
guard "$TMP/otherdoc" GITHUB_ACTIONS=true STUB_WORKFLOW_ID=99 STUB_RUNS="$(runs_json 99 pull_request completed success)"
check "an ordinary commit emits NO annotation"                      "$(grep -q "::warning" <<<"$GUARD_STDOUT" && echo 1 || echo 0)"

# ---------------------------------------------------------------- the emitted workflow's wiring
# The YAML has no live signal — no consumer CI runs in this repo — so every input the script
# would fail on is pinned structurally here. Each of these, dropped, makes the guard
# permanently inert (skip=false forever) rather than red: exactly the silent self-disable this
# file exists to catch.
check "yml: is a reusable workflow (workflow_call)"                 "$(grep -q "workflow_call" "$YML" && echo 0 || echo 1)"
# shellcheck disable=SC2016  # `${{ … }}` is a GitHub Actions expression, matched as a literal.
check "yml: exposes the skip output from the guard job"             "$(grep -qF 'value: ${{ jobs.guard.outputs.skip }}' "$YML" && echo 0 || echo 1)"
check "yml: runs the committed guard script"                        "$(grep -q "second-shift-delta-guard.sh" "$YML" && echo 0 || echo 1)"
# shellcheck disable=SC2016  # ditto — a literal Actions expression, not a shell expansion.
check "yml: checks out the PR HEAD commit, not the merge ref"       "$(grep -qF 'ref: ${{ github.event.pull_request.head.sha }}' "$YML" && echo 0 || echo 1)"
check "yml: fetch-depth 2 (head + parent, the delta's minimum)"     "$(grep -q "fetch-depth: 2" "$YML" && echo 0 || echo 1)"

# Whole-line, indent included, against the STEP'S ENV BLOCK — a commented-out wiring elsewhere
# in the file must not satisfy it (second-shift-ci-check-selftest.sh's precedent: the substring
# form passed that exact mutation).
STEPENV="$(awk '/^        env:/{f=1;next} f&&/^        [^ ]/{f=0} f' "$YML")"
check "yml: env supplies PR_HEAD_SHA from the PR head commit"       "$(grep -qE '^ {10}PR_HEAD_SHA: \$\{\{ github\.event\.pull_request\.head\.sha \}\}$' <<<"$STEPENV" && echo 0 || echo 1)"
check "yml: env supplies GUARD_RUN_ID from the calling run"         "$(grep -qE '^ {10}GUARD_RUN_ID: \$\{\{ github\.run_id \}\}$' <<<"$STEPENV" && echo 0 || echo 1)"
check "yml: env supplies GUARD_EVENT_NAME from the calling event"   "$(grep -qE '^ {10}GUARD_EVENT_NAME: \$\{\{ github\.event_name \}\}$' <<<"$STEPENV" && echo 0 || echo 1)"
for v in GH_TOKEN GH_REPO; do
  check "yml: step env carries $v"                                  "$(grep -qE "^ {10}$v:" <<<"$STEPENV" && echo 0 || echo 1)"
done

# A `permissions:` key replaces the defaults wholesale, so a scope omitted here is `none`:
# without `actions: read` the trust condition can never be evaluated and the guard is inert on
# every run. Asserted against the BLOCK so a mention in a comment cannot satisfy it.
PERMS="$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f' "$YML")"
for p in "contents: read" "actions: read"; do
  check "yml: permissions block grants $p (AC-2)"                   "$(grep -q "^  $p\$" <<<"$PERMS" && echo 0 || echo 1)"
done
check "yml: permissions block grants no write scope"                "$(grep -q ": write" <<<"$PERMS" && echo 1 || echo 0)"

# The documented wiring must use `!= 'true'`, never `== 'false'`: a guard that produced no
# output at all leaves the string empty, and an empty string has to RUN the lane.
check "yml: documents the fail-safe gate form (!= 'true')"          "$(grep -qF "!= 'true'" "$YML" && echo 0 || echo 1)"

if [ "$FAILS" -gt 0 ]; then echo "second-shift-delta-guard selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "second-shift-delta-guard selftest: all green"
