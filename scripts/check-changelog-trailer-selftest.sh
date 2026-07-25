#!/usr/bin/env bash
# check-changelog-trailer-selftest.sh — fixture-driven proof of the PR trailer gate,
# including the SIGPIPE regression that produced a false "no trailer" on a real PR.
#
# THE REGRESSION THIS PINS: the gate greps `git log <range> --format=%B` for '^Changelog:'.
# With `grep -q`, grep exits at the FIRST match; when the log stream is long enough to need
# more producer writes, git log takes SIGPIPE (141) and `set -o pipefail` turns the
# pipeline — and therefore a SUCCESSFUL match — into failure. Trip conditions: a trailer in
# a RECENT commit (git log emits newest first, so the match lands early) plus enough older
# commit-body volume behind it. Case 1 constructs exactly that shape and fails against the
# grep -q version; the shipped gate uses grep -c (consumes the whole stream) instead.
#
# Runs under the repo's *-selftest.sh CI loop. Bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-changelog-trailer.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t changelog-trailer-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # mkrepo <dir> — base repo with a main branch and one plugins file
  git -C "$1" init -q -b main
  git -C "$1" -c user.name=t -c user.email=t@t config commit.gpgsign false
  mkdir -p "$1/plugins/p"
  echo base > "$1/plugins/p/f.txt"
  git -C "$1" add . && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "base"
}

longbody() { # a ~2KB commit body so a multi-commit log spans several producer writes
  i=0
  while [ $i -lt 25 ]; do
    echo "padding line $i: the quick brown fox jumps over the lazy dog, at considerable length"
    i=$((i + 1))
  done
}

# ---- Case 1: trailer in the NEWEST commit + 14 older long-body commits => must PASS.
# This is the SIGPIPE shape: the match is early in the stream, most volume comes after.
R="$TMP/r1"; mkdir -p "$R"; mkrepo "$R"
git -C "$R" checkout -qb feature
i=1
while [ $i -le 14 ]; do
  echo "$i" >> "$R/plugins/p/f.txt"
  git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "feat: step $i" -m "$(longbody)"
  i=$((i + 1))
done
echo "top" >> "$R/plugins/p/f.txt"
git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "feat: top" -m "$(longbody)

Changelog: consumer-visible thing.
  Migration: none."
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "1 early trailer + long log passes (the SIGPIPE regression shape)" || bad "1 expected rc=0, got $rc"

# ---- Case 2: plugins change, NO trailer anywhere => must FAIL (exit 1).
R="$TMP/r2"; mkdir -p "$R"; mkrepo "$R"
git -C "$R" checkout -qb feature
echo x >> "$R/plugins/p/f.txt"
git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "feat: no trailer" -m "$(longbody)"
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 1 ] && ok "2 plugins change without trailer fails (rc=1)" || bad "2 expected rc=1, got $rc"

# ---- Case 3: no plugins/** change => trailer not required, must PASS.
R="$TMP/r3"; mkdir -p "$R"; mkrepo "$R"
git -C "$R" checkout -qb feature
echo docs > "$R/readme.md"
git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "docs: no plugins"
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "3 non-plugins change needs no trailer" || bad "3 expected rc=0, got $rc"

# ---- Case 4: 'Changelog: none' opt-out => must PASS.
R="$TMP/r4"; mkdir -p "$R"; mkrepo "$R"
git -C "$R" checkout -qb feature
echo y >> "$R/plugins/p/f.txt"
git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "chore: internal" -m "Changelog: none"
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "4 explicit opt-out passes" || bad "4 expected rc=0, got $rc"

# ---- Drift guard: the gate must not regress to grep -q on the log pipeline.
if grep -qE 'git log .*--format=%B \| grep -qE' "$GATE"; then
  bad "5 gate uses grep -q on the git log pipeline again — the SIGPIPE false-negative returns"
else
  ok "5 gate consumes the whole log stream (no grep -q early-exit on the producer)"
fi

echo "check-changelog-trailer-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
