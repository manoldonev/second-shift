#!/usr/bin/env bash
# config-diff-guard-selftest.sh — behavioral selftest for config-diff-guard.sh.
#
# Hermetic: the tool takes no repo root and reads no tree, so every fixture is two JSON
# documents under mktemp. No git, no network, no plugin cache.
#
# What each case guards is stated at the case. The through-line: a delta must fire on a value
# the draft would destroy and must NOT fire on a draft that reproduces it — a guard that always
# fires is one the human learns to acknowledge blindly, which is the failure mode the whole
# design is arranged against.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/config-diff-guard.sh"
FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT=""; ERR=""; RC=0

run_guard() { # $1.. → args passed through verbatim
  RC=0
  OUT="$(bash "$GUARD" "$@" 2>"$TMP/stderr")" || RC=$?
  ERR="$(cat "$TMP/stderr")"
}

# A `jq` shim that fails exactly ONE of the guard's jq invocations, selected by an argument only
# that invocation carries (`--slurpfile` → the comparison; `--args` → the ack marshalling). This
# is the only way to reach the guard's did-not-run arms: the validation ahead of them makes a real
# failure near-unreachable, and an unreachable-but-load-bearing arm is exactly the kind that can
# revert to a fail-open with every case still green.
mkdir -p "$TMP/shim"
REAL_JQ="$(command -v jq)"
cat > "$TMP/shim/jq" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "\$SHIM_KILL" ]]; then exit 5; fi
done
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$TMP/shim/jq"

run_guard_shim() { # $1 the jq argument whose invocation dies, $2.. → guard args
  local marker="$1"; shift
  RC=0
  OUT="$(SHIM_KILL="$marker" PATH="$TMP/shim:$PATH" bash "$GUARD" "$@" 2>"$TMP/stderr")" || RC=$?
  ERR="$(cat "$TMP/stderr")"
}

_paths() { jq -r '.deltas[].path' <<< "$OUT" | tr '\n' ' '; }
_delta() { jq -r --arg p "$1" '.deltas[] | select(.path==$p) | "\(.kind) ⟂ \(.existing|tojson) ⟂ \(.draft|tojson) ⟂ \(.evidence) ⟂ \(.proposal)"' <<< "$OUT"; }

expect_delta() { # $1 label, $2 path, $3 kind, $4.. substrings that must appear in the row
  local label="$1" path="$2" kind="$3"; shift 3
  local got s; got="$(_delta "$path")"
  if [[ -z "$got" ]]; then check "$label (no delta '$path'; got: $(_paths))" 1; return; fi
  if [[ "${got%% ⟂ *}" != "$kind" ]]; then check "$label (kind is '${got%% ⟂ *}', expected '$kind')" 1; return; fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<< "$got"; then check "$label (missing '$s')" 1; echo "      $got"; return; fi
  done
  check "$label" 0
}
expect_no_delta() { # $1 label, $2 path
  if [[ -z "$(_delta "$2")" ]]; then check "$1" 0; else check "$1 (unexpected delta '$2')" 1; echo "      $(_delta "$2")"; fi
}
expect_count() { # $1 label, $2 expected number of deltas
  local n; n="$(jq -r '.deltas | length' <<< "$OUT")"
  if [[ "$n" == "$2" ]]; then check "$1" 0; else check "$1 (delta count $n, expected $2: $(_paths))" 1; fi
}
expect_list() { # $1 label, $2 envelope array (acknowledged|unmatchedAcks), $3 expected space-joined
  local got; got="$(jq -r --arg k "$2" '.[$k] | join(" ")' <<< "$OUT")"
  if [[ "$got" == "$3" ]]; then check "$1" 0; else check "$1 ($2 is '$got', expected '$3')" 1; fi
}
expect_len() { # $1 label, $2 envelope array, $3 expected length — for entries join() would blur
  local n; n="$(jq -r --arg k "$2" '.[$k] | length' <<< "$OUT")"
  if [[ "$n" == "$3" ]]; then check "$1" 0; else check "$1 ($2 length $n, expected $3)" 1; fi
}
expect_no_stdout() { # $1 label — a caller reading only stdout must see nothing at all
  if [[ -z "$OUT" ]]; then check "$1" 0; else check "$1 (stdout: $OUT)" 1; fi
}
expect_no_stderr_match() { # $1 label, $2 substring the message must NOT carry
  if grep -qF -- "$2" <<< "$ERR"; then check "$1 (stderr carries '$2': $ERR)" 1; else check "$1" 0; fi
}
expect_rc() { # $1 label, $2 expected rc, $3 (optional) substring the stderr message must carry
  if [[ "$RC" != "$2" ]]; then check "$1 (rc=$RC, expected $2)" 1; return; fi
  # The rc alone does not distinguish the reasons: every IO shape lands on 3, so a missing file
  # that fell through to the JSON check would still score green. The message is the only thing
  # that tells the operator WHICH input is wrong, so it is asserted where it differs.
  if [[ -n "${3:-}" ]] && ! grep -qF -- "$3" <<< "$ERR"; then
    check "$1 (stderr missing '$3': $ERR)" 1; return
  fi
  check "$1" 0
}

echo "config-diff-guard selftest:"

# --- AC-2 classification table + the motivating evidence ------------------------------------
# The audited re-onboard reverted BOTH mutation-gate keys — one to an explicit null, one by
# omission — while every other key round-tripped. Both spellings destroy the value, so both are
# `removed`; distinguishing them in the evidence is what tells the reader which half of the draft
# to look at. `lint` changing is `changed`, `typecheck` round-tripping is silent.
cat > "$TMP/e1.json" <<'EOF'
{ "$schema": "https://example.invalid/v1/schema.json",
  "configVersion": 2,
  "commands": { "web": { "lint": "yarn lint", "typecheck": "yarn tsc",
                         "testFile": "yarn test {file}", "unitTestScope": "src/**",
                         "format": null } } }
EOF
cat > "$TMP/d1.json" <<'EOF'
{ "$schema": "https://example.invalid/v1/schema.json",
  "configVersion": 2,
  "commands": { "web": { "lint": "yarn lint --cache", "typecheck": "yarn tsc",
                         "testFile": null,
                         "format": "yarn prettier" } },
  "gates": { "mutation": false } }
EOF
run_guard "$TMP/e1.json" "$TMP/d1.json"
expect_delta "draft-null is removed, and the evidence says which spelling" \
  commands.web.testFile removed '"yarn test {file}"' "sets it to null" "--ack commands.web.testFile"
expect_delta "draft-absent is removed, and the evidence says which spelling" \
  commands.web.unitTestScope removed '"src/**"' "omits the key entirely"
expect_delta "draft-differs is changed, and both values are quoted" \
  commands.web.lint changed '"yarn lint"' '"yarn lint --cache"' "change is what the human intends"
expect_no_delta "draft-identical is silent" commands.web.typecheck
expect_no_delta "an existing null leaf is never protected, even when the draft fills it in" \
  commands.web.format
expect_no_delta "a draft-only path is never reported — an addition destroys nothing" gates.mutation
expect_count "exactly the three destroyed values" 3
expect_rc "exit 0 with deltas present — deltas are data, not a crash" 0
expect_list "nothing acknowledged without --ack" acknowledged ""

# --- AC-2 walk table: nested objects descend to scalar leaves --------------------------------
# The walk must reach a leaf at any depth, and must report the LEAF path rather than the object
# that contains it: `tracker.bot` as a whole would name a subtree the human did not change.
cat > "$TMP/e2.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/app-",
               "bot": { "enabled": true, "envVar": "GH_BOT",
                        "app": { "appName": "app-bot", "installationId": "1234" } } } }
EOF
cat > "$TMP/d2.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/app-",
               "bot": { "enabled": true, "envVar": "GH_BOT",
                        "app": { "appName": "app-bot", "installationId": "9999" } } } }
EOF
run_guard "$TMP/e2.json" "$TMP/d2.json"
expect_delta "a depth-4 scalar leaf is reached and reported at its own path" \
  tracker.bot.app.installationId changed '"1234"' '"9999"'
expect_count "only the changed leaf, not its enclosing objects" 1

# --- AC-2 walk table: an array is a leaf, compared whole --------------------------------------
# commands.<id>.lanes / extraLanes / reviewers.add are arrays of OBJECTS. Descending would report
# a cascade of shifted element paths on a single insertion, so the array's own path is reported
# ONCE and no index path ever appears.
cat > "$TMP/e3.json" <<'EOF'
{ "configVersion": 2,
  "commands": { "web": { "lanes": [ {"name":"install","commands":["yarn install --immutable"]} ],
                         "extraLanes": [ {"name":"build","commands":["yarn build"]} ] } },
  "reviewers": { "add": ["local-reviewer"] } }
EOF
cat > "$TMP/d3.json" <<'EOF'
{ "configVersion": 2,
  "commands": { "web": { "lanes": [ {"name":"setup","commands":["yarn install --immutable"]},
                                    {"name":"install","commands":["yarn install --immutable"]} ],
                         "extraLanes": [ {"name":"build","commands":["yarn build"]} ] } },
  "reviewers": { "add": ["local-reviewer"] } }
EOF
run_guard "$TMP/e3.json" "$TMP/d3.json"
expect_delta "an array reports its OWN path, once" commands.web.lanes changed
expect_count "one delta for the whole array — no per-index cascade" 1
if jq -e '[.deltas[].path] | map(select(test("\\.[0-9]"))) | length == 0' <<< "$OUT" >/dev/null; then
  check "no index-level path is ever emitted" 0
else check "no index-level path is ever emitted (got: $(_paths))" 1; fi
expect_no_delta "an array that deep-equals is silent" commands.web.extraLanes
expect_no_delta "an array of scalars that deep-equals is silent" reviewers.add

# --- AC-2: \$schema is excluded, and the exclusion is SCOPED ----------------------------------
# Step 4 rewrites $schema to the pinned ref on every run, so a pin-upgrade re-onboard would fire
# a delta every single time. The second half is what proves the exclusion is a key rule and not a
# document-wide mute: a sibling key changing in the same document still fires.
cat > "$TMP/e4.json" <<'EOF'
{ "$schema": "https://example.invalid/v4.1.0/schema.json", "configVersion": 2,
  "tracker": { "type": "github" } }
EOF
cat > "$TMP/d4.json" <<'EOF'
{ "$schema": "https://example.invalid/v4.2.0/schema.json", "configVersion": 2,
  "tracker": { "type": "jira" } }
EOF
run_guard "$TMP/e4.json" "$TMP/d4.json"
SCHEMA_KEY="\$schema"   # the config's literal key name, not a shell expansion
expect_no_delta "a rewritten \$schema never fires" "$SCHEMA_KEY"
expect_delta "a sibling key in the same document still fires" tracker.type changed '"github"' '"jira"'
expect_count "the exclusion is one key, not a document-wide mute" 1

# --- AC-3: the ack channel ---------------------------------------------------------------------
# Acks are exact and per-run. One ack drops exactly one delta; an unacked sibling stays blocking,
# which is what keeps a single confirmation from clearing the whole screen.
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack commands.web.testFile
expect_no_delta "an acked path drops out of deltas[]" commands.web.testFile
expect_delta "an unacked sibling stays blocking" commands.web.unitTestScope removed
expect_list "the suppression is auditable, not invisible" acknowledged "commands.web.testFile"
expect_count "one fewer delta" 2

run_guard "$TMP/e1.json" "$TMP/d1.json" --ack commands.web.testFile --ack commands.web.unitTestScope
expect_count "--ack is repeatable" 1
expect_list "both suppressions are listed" acknowledged "commands.web.testFile commands.web.unitTestScope"

# An ack that matches nothing cannot let a real delta through — that delta is still in deltas[] —
# but it does leave the caller believing it dispositioned something, so the guard says so.
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack commands.app.testFile
expect_list "an ack matching nothing is reported" unmatchedAcks "commands.app.testFile"
expect_list "and acknowledges nothing" acknowledged ""
expect_count "and suppresses nothing" 3

# A wildcard is not a wildcard: ack paths are exact, so a prefix clears nothing.
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack commands.web
expect_count "a prefix is not a wildcard" 3
expect_list "and is reported unmatched" unmatchedAcks "commands.web"

# "Exact" is also about ARGUMENT BOUNDARIES, and a text round-trip loses them silently. Joining
# the acks on newlines and re-splitting turned one flag carrying an embedded newline into two acks
# and dropped `--ack ""` entirely — both invisible, because the envelope reported the shape the
# round-trip produced rather than the one the caller typed.
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack "$(printf 'commands.web.testFile\ncommands.web.unitTestScope')"
expect_len "one --ack is one ack, even carrying a newline" unmatchedAcks 1
expect_count "and it suppresses neither of the two paths it spells" 3
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack ""
expect_len "an empty --ack is reported unmatched, not silently dropped" unmatchedAcks 1

# Boundaries are not the whole of "verbatim": a value can survive intact and still be re-INTERPRETED
# downstream. `--args` alone leaves jq parsing a `-`-leading ack as one of its own options
# (`jq --args "-n"` → `[]`), and the ack then vanished — neither suppressed nor in unmatchedAcks[].
# Only jq's `--` terminator makes every remaining word positional. The `--raw-output0` case is the
# long form of the same class, which additionally leaked a jq warning onto the operator's screen.
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack -n
expect_list "a '-'-leading ack survives jq's own option parser" unmatchedAcks "-n"
expect_count "and suppresses nothing" 3
run_guard "$TMP/e1.json" "$TMP/d1.json" --ack --raw-output0 --ack commands.web.testFile
expect_list "a long-form jq option as an ack value is carried across too" unmatchedAcks "--raw-output0"
expect_count "and a real ack alongside it still suppresses exactly one" 2

# --- a clean re-onboard is silent ---------------------------------------------------------------
# The AC-4 carry-forward exists so THIS is the common case. A guard that fires on an identical
# draft would be ack-spam on every re-onboard forever.
run_guard "$TMP/e1.json" "$TMP/e1.json"
expect_count "an identical draft yields no delta" 0
expect_rc "exit 0 with no deltas" 0

# --- AC-1: usage / IO errors all exit 3 ----------------------------------------------------------
# Both of these assert the usage LINE, not the rc: with the argument-count guard gone, one
# argument falls through to the file check and the tool exits 3 on `no such file: ` with an empty
# path — same code, a message describing a file the caller never named.
run_guard "$TMP/e1.json"
expect_rc "one argument is a usage error" 3 "usage: config-diff-guard.sh"
run_guard
expect_rc "no arguments is a usage error" 3 "usage: config-diff-guard.sh"
run_guard "$TMP/e1.json" "$TMP/d1.json" "$TMP/e1.json"
expect_rc "a third positional is a usage error" 3 "unexpected extra argument:"
run_guard "$TMP/nope.json" "$TMP/d1.json"
expect_rc "a missing EXISTING config is an error, never a silent skip" 3 "no such file: $TMP/nope.json"
run_guard "$TMP/e1.json" "$TMP/nope.json"
expect_rc "a missing draft is an error" 3 "no such file: $TMP/nope.json"
printf 'not json at all' > "$TMP/bad.json"
run_guard "$TMP/bad.json" "$TMP/d1.json"
expect_rc "a non-JSON existing config is an error" 3 "not valid JSON: $TMP/bad.json"
run_guard "$TMP/e1.json" "$TMP/bad.json"
expect_rc "a non-JSON draft is an error" 3 "not valid JSON: $TMP/bad.json"
printf '["a","b"]' > "$TMP/arr.json"
run_guard "$TMP/arr.json" "$TMP/d1.json"
expect_rc "valid JSON that is not an object is an error" 3 "not a single JSON object: $TMP/arr.json"

# A JSON *stream* is the shape a lone-array fixture cannot catch. `jq -e 'type == "object"' file`
# reports the status of jq's LAST output, so `[1,2]` followed by an object passes an is-it-an-object
# gate outright — and `--slurpfile … | .[0]` then binds document one, so every later document goes
# unwalked and unprotected. A config damaged into a stream (a doubled write, a botched conflict
# resolution) is precisely the damaged config that must exit 3 rather than get a partial screen.
printf '[1,2]\n{"a":1}\n' > "$TMP/streamarr.json"
run_guard "$TMP/streamarr.json" "$TMP/d1.json"
expect_rc "an array in front of an object does not sneak past the object check" 3 \
  "not a single JSON object: $TMP/streamarr.json"
printf '{"commands":{"web":{"lint":"a"}}}\n{"stageParams":{"x":1}}\n' > "$TMP/streamobj.json"
run_guard "$TMP/streamobj.json" "$TMP/d1.json"
expect_rc "two objects are an error, not a comparison against the first" 3 \
  "not a single JSON object: $TMP/streamobj.json"
run_guard "$TMP/e1.json" "$TMP/streamobj.json"
expect_rc "a multi-document draft is an error too" 3 "not a single JSON object: $TMP/streamobj.json"
: > "$TMP/empty.json"
run_guard "$TMP/empty.json" "$TMP/d1.json"
expect_rc "an empty file holds no document, so it is an error" 3 \
  "not a single JSON object: $TMP/empty.json"

run_guard "$TMP/e1.json" "$TMP/d1.json" --ack
expect_rc "--ack with no value is a usage error" 3 "--ack needs a config path"
run_guard "$TMP/e1.json" "$TMP/d1.json" --waive commands.web.testFile
expect_rc "an unknown option is a usage error — grillWaivers is not this tool's channel" 3 \
  "unknown option: --waive"
# The case above is also satisfied by a guard that merely SKIPS the flag, because its value then
# lands as a third positional. A bare unknown flag is what separates rejecting from ignoring.
run_guard "$TMP/e1.json" "$TMP/d1.json" --verbose
expect_rc "a bare unknown option is rejected, not silently skipped" 3 "unknown option: --verbose"
# There is no end-of-options arm, and that is the decision rather than an omission: an arm that
# consumed `--` without making the rest positional advertised GNU semantics it did not implement.
run_guard "$TMP/e1.json" "$TMP/d1.json" --
expect_rc "-- is an unknown option, not an unimplemented terminator" 3 "unknown option: --"

# --- AC-1: no fail-open on the comparison itself -------------------------------------------------
# The control comes first, and it is what keeps the two kill cases from being vacuous: a shim that
# failed everything would red these regardless of the guard's arms.
run_guard_shim --an-argument-no-invocation-carries "$TMP/e1.json" "$TMP/d1.json"
expect_rc "the shim is inert when its marker matches nothing" 0
expect_count "and the comparison under it is the real one" 3

# A filter that DIED must not be spelled the way a filter that found nothing is. Streaming the
# comparison instead of capturing it gives the caller rc 0 and an empty stdout — a clean envelope
# for a comparison that never ran, over a config nothing protected.
run_guard_shim --slurpfile "$TMP/e1.json" "$TMP/d1.json"
expect_rc "a comparison that could not run exits 3" 3 "comparison failed"
expect_no_stdout "and prints no envelope at all"

# The ack marshalling is the same family one invocation earlier, and its failure mode is
# misattribution: an unchecked jq leaves ACKS_JSON empty, `--argjson acks ""` kills the MAIN
# filter, and the operator is told the comparison failed when the acks are what did.
run_guard_shim --args "$TMP/e1.json" "$TMP/d1.json" --ack commands.web.testFile
expect_rc "a failed --ack marshal exits 3 naming the acks" 3 "could not marshal --ack values"
expect_no_stderr_match "and does not misattribute itself to the comparison" "comparison failed"
expect_no_stdout "and prints no envelope either"

if [[ "$FAILS" -gt 0 ]]; then echo "config-diff-guard selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-diff-guard selftest: all green"
