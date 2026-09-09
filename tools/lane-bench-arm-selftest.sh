#!/usr/bin/env bash
# lane-bench-arm-selftest.sh — behavioral cover for tools/lane-bench-arm.sh.
#
# Zero network, zero model calls. Every case drives the real wrapper with a `claude` fake first on
# PATH; the fake writes its argv one argument per line, so an EMPTY argument is a visible empty
# line and `--setting-sources ''` is asserted as the empty string it has to be rather than as a
# flag that happens to be present.
#
# THE SCENARIO EACH CASE GUARDS is that the wrapper is invisible to the scheduler in exactly the
# ways `orchestrate-lean.sh` depends on: the id it parses out of stdout by field position, the
# exit status it reads, and the two control-plane calls it makes on the same handle. None of that
# is covered by plugins/dev-pipeline/skills/build/scenario-liveness-selftest.sh, which
# composes the milestone gate's own verdict paths — this script is not on one and is never invoked by
# the gate.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/lane-bench-arm.sh"
# The explicit-template form, which IS honored by a private TMPDIR (docs/testing.md).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-bench-arm-selftest.XXXXXX")"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

PASSES=0; FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $*"; }
fail() { FAILS=$((FAILS + 1));  echo "  FAIL: $*"; }

# ---- the claude fake ---------------------------------------------------------------------------
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
: > "$ARGV_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV_LOG"; done
printf 'backgrounded · %s · %s\n' "${FAKE_ID:-sess0001}" "${FAKE_NAME:-lean-42-build-r1}"
printf 'fake stderr line\n' >&2
exit "${FAKE_RC:-0}"
SH
chmod +x "$BIN/claude"
PATH="$BIN:$PATH"; export PATH
ARGV_LOG="$WORK/argv.log"; export ARGV_LOG

# ---- the arm worktrees the manifests name --------------------------------------------------------
# Real directories, because the wrapper's fourth refusal is about existence and a fixture of names
# alone could not tell the passing cases from the refusing one.
SIX=""; for p in second-shift dev-pipeline review-toolkit intake-toolkit audit-toolkit design-toolkit; do
  mkdir -p "$WORK/arm/plugins/$p"; SIX="$SIX $WORK/arm/plugins/$p"
done
M6="$WORK/manifest-6"; : > "$M6"
for d in $SIX; do printf '%s\n' "$d" >> "$M6"; done
M2="$WORK/manifest-2"
printf '%s\n%s\n' "$WORK/arm/plugins/dev-pipeline" "$WORK/arm/plugins/audit-toolkit" > "$M2"

# The scheduler's own dispatch argv, verbatim from orchestrate-lean.sh's spawn call site. It is
# reproduced whole rather than sampled because the claim under test is "reaches the binary
# verbatim", and a case passing three of six flags could not fail for the reason it names.
SETTINGS="$WORK/spawn-1-settings.json"; echo '{"env":{}}' > "$SETTINGS"
PROMPT='/dev-pipeline:build 42'
dispatch() { # dispatch <manifest>
  LEAN_ARM_MANIFEST="$1" bash "$TOOL" --bg \
    --permission-mode auto --model opus \
    --name lean-42-build-r1 \
    --disallowedTools AskUserQuestion \
    --settings "$SETTINGS" \
    "$PROMPT" 2>"$WORK/err"
}

# ================================================================= (a) the six-directory manifest
out="$(dispatch "$M6")"; rc=$?
EXP="$WORK/expect-6"
{ printf -- '--bg\n--permission-mode\nauto\n--model\nopus\n--name\nlean-42-build-r1\n'
  printf -- '--disallowedTools\nAskUserQuestion\n--settings\n%s\n%s\n' "$SETTINGS" "$PROMPT"
  printf -- '--setting-sources\n\n'
  for d in $SIX; do printf -- '--plugin-dir\n%s\n' "$d"; done
} > "$EXP"
if [ "$rc" -eq 0 ] && diff -q "$EXP" "$ARGV_LOG" >/dev/null; then
  pass "(a1) a six-directory manifest reaches the binary as the scheduler's argv verbatim, then --setting-sources '' and six --plugin-dir pairs, and nothing else"
else fail "(a1) rc=$rc argv diff: $(diff "$EXP" "$ARGV_LOG" | tr '\n' ' ')"; fi

# The empty string is the assertion, not the flag's presence: `--setting-sources` followed by
# anything non-empty would keep the arm's OWN settings sources loaded and silently un-ablate it.
n="$(grep -n -- '^--setting-sources$' "$ARGV_LOG" | cut -d: -f1)"
if [ -n "$n" ] && [ -z "$(sed -n "$((n + 1))p" "$ARGV_LOG")" ]; then
  pass "(a2) --setting-sources carries the EMPTY string, not a name"
else fail "(a2) --setting-sources at line ${n:-none} is followed by '$(sed -n "$((${n:-0} + 1))p" "$ARGV_LOG")'"; fi

# ================================================================= (b) the two-directory manifest
out="$(dispatch "$M2")"; rc=$?
EXP2="$WORK/expect-2"
{ printf -- '--bg\n--permission-mode\nauto\n--model\nopus\n--name\nlean-42-build-r1\n'
  printf -- '--disallowedTools\nAskUserQuestion\n--settings\n%s\n%s\n' "$SETTINGS" "$PROMPT"
  printf -- '--setting-sources\n\n'
  printf -- '--plugin-dir\n%s\n--plugin-dir\n%s\n' "$WORK/arm/plugins/dev-pipeline" "$WORK/arm/plugins/audit-toolkit"
} > "$EXP2"
if [ "$rc" -eq 0 ] && diff -q "$EXP2" "$ARGV_LOG" >/dev/null; then
  pass "(b1) the skeleton's two-directory manifest yields exactly two --plugin-dir pairs — the count follows the manifest, not a constant"
else fail "(b1) rc=$rc argv diff: $(diff "$EXP2" "$ARGV_LOG" | tr '\n' ' ')"; fi

# ================================================================= (c) transparency
# The scheduler reads the id as the THIRD whitespace-delimited field of the `backgrounded` line
# (#805 D-14, and the defect #816 fixed). A wrapper that prefixed one word of its own would move
# the id by a field and every spawn would die `spawn-unreadable` ninety seconds later.
if [ "$out" = "backgrounded · sess0001 · lean-42-build-r1" ]; then
  pass "(c1) the child's stdout line reaches the caller byte-for-byte, unprefixed"
else fail "(c1) stdout was '$out'"; fi
if [ "$(printf '%s\n' "$out" | awk '/backgrounded/ { print $3; exit }')" = "sess0001" ]; then
  pass "(c2) the scheduler's own field-3 id parse still reads the id off that line"
else fail "(c2) field 3 is '$(printf '%s\n' "$out" | awk '/backgrounded/ { print $3; exit }')'"; fi
if grep -q 'fake stderr line' "$WORK/err"; then
  pass "(c3) the child's stderr is relayed"
else fail "(c3) stderr was not relayed: $(cat "$WORK/err")"; fi

FAKE_RC=9 dispatch "$M2" >/dev/null; rc=$?
if [ "$rc" -eq 9 ]; then
  pass "(c4) the child's exit status is the wrapper's — a dispatch that failed is not reported as one that worked"
else fail "(c4) child exited 9, wrapper exited $rc"; fi

# ================================================================= (d) the other two control-plane calls
# `orchestrate-lean.sh` polls with `agents --json --all` and stops with `stop <id>` through this
# same handle. An appended --plugin-dir there is at best ignored and at worst makes the listing
# unparseable, which the poll counts against the PAYLOAD rather than against the wrapper.
LEAN_ARM_MANIFEST="$M6" bash "$TOOL" agents --json --all >/dev/null 2>&1
if [ "$(printf 'agents\n--json\n--all\n')" = "$(cat "$ARGV_LOG")" ]; then
  pass "(d1) 'agents --json --all' reaches the binary unmodified"
else fail "(d1) argv was: $(tr '\n' ' ' < "$ARGV_LOG")"; fi

LEAN_ARM_MANIFEST="$M6" bash "$TOOL" stop sess0001 >/dev/null 2>&1
if [ "$(printf 'stop\nsess0001\n')" = "$(cat "$ARGV_LOG")" ]; then
  pass "(d2) 'stop <id>' reaches the binary unmodified"
else fail "(d2) argv was: $(tr '\n' ' ' < "$ARGV_LOG")"; fi

# `-p` and `--print` are dispatches too: the bench is not the only caller shape, and a wrapper
# that recognised only `--bg` would silently un-ablate any print-mode arm.
LEAN_ARM_MANIFEST="$M2" bash "$TOOL" -p "say hi" >/dev/null 2>&1
if grep -q -- '^--plugin-dir$' "$ARGV_LOG"; then
  pass "(d3) a '-p' argv is a dispatch and gets the flags"
else fail "(d3) -p was treated as a control-plane call: $(tr '\n' ' ' < "$ARGV_LOG")"; fi
LEAN_ARM_MANIFEST="$M2" bash "$TOOL" --print "say hi" >/dev/null 2>&1
if grep -q -- '^--plugin-dir$' "$ARGV_LOG"; then
  pass "(d4) a '--print' argv is a dispatch and gets the flags"
else fail "(d4) --print was treated as a control-plane call: $(tr '\n' ' ' < "$ARGV_LOG")"; fi

# `--bare` is the caller's to pass and the wrapper's neither to add nor to refuse: it kills
# subscription auth, so a wrapper that added one would make every cell API-billed.
LEAN_ARM_MANIFEST="$M2" bash "$TOOL" --bg --bare "say hi" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(grep -c -- '^--bare$' "$ARGV_LOG")" = "1" ]; then
  pass "(d5) a caller's --bare passes through once and is not refused; the wrapper adds none"
else fail "(d5) rc=$rc --bare count=$(grep -c -- '^--bare$' "$ARGV_LOG")"; fi

# ================================================================= (e) the four refusals
# Every one asserts that NOTHING was exec'd, not merely that the exit code was 2: a wrapper that
# printed a complaint and dispatched anyway would spawn an un-ablated session under a bench cell's
# name, and the row it produced would be indistinguishable from a real one.
refuses() { # refuses <label> <expected-fragment> -- <env assignment...>
  : > "$ARGV_LOG"
  local label="$1" frag="$2"; shift 3
  local err rc
  err="$(env "$@" bash "$TOOL" --bg "prompt" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && grep -qF "$frag" <<<"$err" && [ ! -s "$ARGV_LOG" ]; then
    pass "$label"
  else fail "$label — rc=$rc argv=$(wc -c < "$ARGV_LOG" | tr -d ' ') bytes err=$err"; fi
}

refuses "(e1) an unset LEAN_ARM_MANIFEST refuses on stderr and execs nothing" \
        "LEAN_ARM_MANIFEST is unset" -- -u LEAN_ARM_MANIFEST
refuses "(e2) a manifest naming no readable file refuses" \
        "names no readable file" -- "LEAN_ARM_MANIFEST=$WORK/no-such-manifest"

UNREADABLE="$WORK/manifest-unreadable"; cp "$M2" "$UNREADABLE"; chmod 000 "$UNREADABLE"
if [ -r "$UNREADABLE" ]; then
  fail "(e3) fixture is still readable — the case cannot fail for the reason it names (running as root?)"
else
  refuses "(e3) a manifest that exists but cannot be read refuses, rather than being read as empty" \
          "names no readable file" -- "LEAN_ARM_MANIFEST=$UNREADABLE"
fi

EMPTY="$WORK/manifest-empty"; printf '\n\n' > "$EMPTY"
refuses "(e4) a manifest of blank lines only is empty and refuses — not a zero-plugin dispatch" \
        "is empty" -- "LEAN_ARM_MANIFEST=$EMPTY"

GHOST="$WORK/manifest-ghost"
printf '%s\n%s\n' "$WORK/arm/plugins/dev-pipeline" "$WORK/arm/plugins/not-here" > "$GHOST"
refuses "(e5) an entry naming a directory that does not exist refuses BEFORE any flag is appended" \
        "names a directory that does not exist" -- "LEAN_ARM_MANIFEST=$GHOST"

# The refusal is about the bench's configuration, so it binds the control-plane calls too: a
# `stop` that succeeded against a broken manifest would let a cell discover the breakage only at
# the moment it spawned, after the issue was filed and the receipt written.
: > "$ARGV_LOG"
err="$(env -u LEAN_ARM_MANIFEST bash "$TOOL" agents --json --all 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$ARGV_LOG" ]; then
  pass "(e6) a control-plane call refuses on a broken manifest too — the refusal is about the bench, not about this argv"
else fail "(e6) rc=$rc err=$err"; fi

echo
echo "lane-bench-arm-selftest: $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1
