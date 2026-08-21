#!/usr/bin/env bash
# dup-scan-selftest.sh — deterministic checks for dup-scan.sh (mirrors the
# ledger-lint-selftest culture: fixtures + a stubbed tracker, pass/fail counters,
# exit code = number of failures).
#
# The tracker is stubbed on PATH rather than mocked inside the tool, so the tool
# under test is the shipped one, unmodified, running its real `gh` invocations.
#
# THE CALIBRATION IS A TEST CASE, not a comment. `corpus-live.json` is the real pair
# of tickets that motivated this tool plus the nearest non-duplicates from the queue
# they were filed into; cases (ds-k)/(ds-l) pin that the shipped threshold separates
# them. Retuning the constant without re-reading that measurement reds here.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$HERE/dup-scan.sh"
FIX="$HERE/dup-scan-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# macOS `mktemp -d` ignores TMPDIR, so an orphaned fixture dir cannot poison a later
# run: the path is unique per invocation either way.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- the tracker stub
STUB="$TMP/bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Stub tracker. Serves DUP_SCAN_STUB_CORPUS; every invocation is recorded so a test
# can assert the tool did NOT call it.
set -euo pipefail
echo "$*" >> "${DUP_SCAN_STUB_LOG:-/dev/null}"
C="${DUP_SCAN_STUB_CORPUS:-}"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  if [ "${DUP_SCAN_STUB_FAIL:-}" = "view" ]; then
    echo "stub: could not resolve to an Issue" >&2; exit 1
  fi
  jq --argjson n "$3" '.[] | select(.number == $n)' "$C"
  exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  if [ "${DUP_SCAN_STUB_FAIL:-}" = "list" ]; then
    echo "stub: HTTP 401: Bad credentials" >&2; exit 1
  fi
  if [ "${DUP_SCAN_STUB_BAD_JSON:-}" = "1" ]; then
    echo '{"message":"Not Found"}'; exit 0
  fi
  lbl=""; lim=100
  while [ $# -gt 0 ]; do
    [ "$1" = "--label" ] && lbl="${2:-}"
    [ "$1" = "--limit" ] && lim="${2:-100}"
    shift
  done
  jq --arg l "$lbl" --argjson k "$lim" \
    '[ .[] | select(any(.labels[]?; .name == $l)) ][:$k]' "$C"
  exit 0
fi
echo "stub: unhandled invocation: $*" >&2
exit 1
STUBEOF
chmod +x "$STUB/gh"

# ---------------------------------------------------------------- config fixtures
printf '%s\n' '{"tracker":{"type":"github"}}'                                    > "$TMP/github.json"
printf '%s\n' '{"tracker":{"type":"jira"}}'                                      > "$TMP/jira.json"
printf '%s\n' '{"tracker":{"type":"github","labels":{"queue":"triaged","claimed":"building"}}}' > "$TMP/custom.json"
printf '%s\n' '{"tracker":{"type":"github",}'                                    > "$TMP/broken.json"

# ---------------------------------------------------------------- runners
# `run` sets the globals OUT and RC and is called as a STATEMENT, never as `$(run …)`:
# a command substitution runs the function in a subshell, where the OUT assignment is
# discarded and every later assertion reads the PREVIOUS case's output. That reads as a
# passing suite for any case whose grep happens to match stale text.
OUT=""
RC=0
run() { # run <corpus> <config> [args...]
  local corpus="$1" config="$2"; shift 2
  set +e
  OUT="$(PATH="$STUB:$PATH" \
         DUP_SCAN_STUB_CORPUS="$corpus" \
         SECOND_SHIFT_CONFIG="$config" \
         bash "$SCAN" "$@" 2>&1)"
  RC=$?
  set -e
}

LIVE="$FIX/corpus-live.json"
SYN="$FIX/corpus-synthetic.json"
GH="$TMP/github.json"

echo "[dup-scan-selftest] usage errors (each must exit 2 — never 0, never 10)"

run "$LIVE" "$GH"
rc=$RC
[ "$rc" -eq 2 ] \
  && pass "(ds-a) no subject → 2" \
  || fail "(ds-a) no subject — got rc=$rc"

run "$LIVE" "$GH" --issue 500 --title "a draft"
rc=$RC
[ "$rc" -eq 2 ] && grep -q "mutually exclusive" <<< "$OUT" \
  && pass "(ds-b) --issue with --title → 2, named" \
  || fail "(ds-b) --issue with --title — rc=$rc out=$OUT"

# The second mutual-exclusion arm, and it fails differently from (ds-b): a body file is not
# a competing subject, it is a body for one the tracker already holds. The file is a real one,
# so the not-found check downstream cannot be what produces the 2.
run "$LIVE" "$GH" --issue 500 --body-file "$FIX/draft-body.md"
rc=$RC
[ "$rc" -eq 2 ] && grep -q "body-file is meaningless with --issue" <<< "$OUT" \
  && pass "(ds-b2) --issue with --body-file → 2, named" \
  || fail "(ds-b2) --issue with --body-file — rc=$rc out=$OUT"

# The message, not just the code — and here that is what makes the case a guard at all.
# The numeric check sits BELOW the tracker-type block (so the jira arm above stays
# reachable), which puts it one step from the subject fetch: delete it and `five` flows
# into `gh issue view five`, the tracker fails on it, and the tool exits 2 anyway. An
# rc-only assertion is green either way and pins nothing. Measured: with the guard
# removed this case still passed until it asserted the text.
run "$LIVE" "$GH" --issue five
rc=$RC
[ "$rc" -eq 2 ] && grep -q -- "--issue takes a number" <<< "$OUT" \
  && pass "(ds-c) non-numeric --issue → 2, named — not the subject-fetch failure" \
  || fail "(ds-c) non-numeric --issue — rc=$rc out=$OUT"

run "$LIVE" "$GH" --title "x" --body-file "$TMP/does-not-exist.md"
rc=$RC
[ "$rc" -eq 2 ] && grep -q "body file not found" <<< "$OUT" \
  && pass "(ds-d) missing --body-file → 2, named" \
  || fail "(ds-d) missing --body-file — rc=$rc out=$OUT"

# The message is asserted, not just the code: it is the only thing that tells the caller
# WHICH tunable it fumbled and what shape the tool wanted instead. A bare rc=2 is the same
# answer this tool gives to six other mistakes.
run "$LIVE" "$GH" --title "x" --threshold twelve
rc=$RC
[ "$rc" -eq 2 ] && grep -q "THRESHOLD must be a non-negative integer" <<< "$OUT" \
  && pass "(ds-e) non-numeric --threshold → 2, names the tunable and the shape" \
  || fail "(ds-e) non-numeric --threshold — rc=$rc out=$OUT"

run "$LIVE" "$GH" --title "x" --wat
rc=$RC
[ "$rc" -eq 2 ] && grep -q "unknown option" <<< "$OUT" \
  && pass "(ds-f) unknown option → 2, named" \
  || fail "(ds-f) unknown option — rc=$rc out=$OUT"

# `--help` serves the header comment by line range, which is a contract between the arm
# and the file it slices: both ends are asserted, because the two ways that slice breaks
# fail in opposite directions. Serving too little (a range that no longer reaches the
# explanation) and serving the whole file (the range silently ignored) are both wrong, and
# an rc-only check sees neither.
run "$LIVE" "$GH" --help
rc=$RC
[ "$rc" -eq 0 ] && grep -q "WHY THIS EXISTS" <<< "$OUT" && ! grep -q "^THRESHOLD=" <<< "$OUT" \
  && pass "(ds-f2) --help → 0, serves the header excerpt and stops before the code" \
  || fail "(ds-f2) --help — rc=$rc out=$OUT"

echo "[dup-scan-selftest] a failed look is never a clean scan"

set +e
OUT="$(PATH="$STUB:$PATH" DUP_SCAN_STUB_CORPUS="$LIVE" SECOND_SHIFT_CONFIG="$GH" \
       DUP_SCAN_STUB_FAIL=list bash "$SCAN" --title "importer drops rows" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] && grep -q "NOT a clean scan" <<< "$OUT" \
  && pass "(ds-g) tracker query failure → 2, named — not 0" \
  || fail "(ds-g) tracker query failure — rc=$rc out=$OUT"

set +e
OUT="$(PATH="$STUB:$PATH" DUP_SCAN_STUB_CORPUS="$LIVE" SECOND_SHIFT_CONFIG="$GH" \
       DUP_SCAN_STUB_FAIL=view bash "$SCAN" --issue 500 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] && grep -q "could not read the subject" <<< "$OUT" \
  && pass "(ds-h) subject fetch failure → 2, named" \
  || fail "(ds-h) subject fetch failure — rc=$rc out=$OUT"

set +e
OUT="$(PATH="$STUB:$PATH" DUP_SCAN_STUB_CORPUS="$LIVE" SECOND_SHIFT_CONFIG="$GH" \
       DUP_SCAN_STUB_BAD_JSON=1 bash "$SCAN" --title "importer drops rows" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] && grep -q "did not return a JSON array" <<< "$OUT" \
  && pass "(ds-i) non-array tracker response → 2, named" \
  || fail "(ds-i) non-array tracker response — rc=$rc out=$OUT"

run "$LIVE" "$TMP/broken.json" --title "importer drops rows"
rc=$RC
[ "$rc" -eq 2 ] && grep -q "not parseable JSON" <<< "$OUT" \
  && pass "(ds-j) unparseable config → 2, refuses the defaults" \
  || fail "(ds-j) unparseable config — rc=$rc out=$OUT"

echo "[dup-scan-selftest] calibration — the motivating pair, against the queue it was filed into"

# The URL is the whole point of the report for a reader — a candidate they cannot open
# is a number they have to go look up. Asserted here rather than in its own case because
# it is part of "surfaced", not a separate behavior.
run "$LIVE" "$GH" --issue 500
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#502' <<< "$OUT" && grep -q 'issues/502' <<< "$OUT" \
  && pass "(ds-k) the real duplicate is surfaced → 10, names #502 and links it" \
  || fail "(ds-k) real duplicate — rc=$rc out=$OUT"

# The other half of a calibration: the nearest NON-duplicate must stay below the bar.
# A threshold that surfaces everything is not a scan, it is a listing.
grep -q '#514' <<< "$OUT" \
  && fail "(ds-l) #514 (the nearest non-duplicate) leaked above the threshold" \
  || pass "(ds-l) the nearest non-duplicate stays below the threshold"

run "$LIVE" "$GH" --issue 502
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#500' <<< "$OUT" \
  && pass "(ds-m) the pair scores the same in both directions → 10, names #500" \
  || fail "(ds-m) reverse direction — rc=$rc out=$OUT"

run "$LIVE" "$GH" --issue 500 --threshold 8
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#514' <<< "$OUT" \
  && pass "(ds-n) --threshold widens the net (OR-1 flag is live)" \
  || fail "(ds-n) --threshold 8 — rc=$rc out=$OUT"

run "$LIVE" "$GH" --issue 500 --threshold 17
rc=$RC
[ "$rc" -eq 0 ] && grep -q "no candidates" <<< "$OUT" \
  && pass "(ds-o) --threshold above the pair's score → 0, no candidates" \
  || fail "(ds-o) --threshold 17 — rc=$rc out=$OUT"

run "$LIVE" "$GH" --issue 500 --title-weight 0
rc=$RC
[ "$rc" -eq 0 ] \
  && pass "(ds-p) --title-weight is live (0 drops the pair below the bar)" \
  || fail "(ds-p) --title-weight 0 — rc=$rc out=$OUT"

echo "[dup-scan-selftest] the corpus is queued OR claimed"

# The load-bearing case. #43 in the synthetic corpus carries ONLY the claimed label —
# a claim consumes the queue label, so a queue-only corpus cannot see it, and a
# duplicate of work already in flight is the most expensive class there is.
run "$SYN" "$GH" --title "Importer drops rows when the batch size exceeds the page limit" \
        --body-file "$FIX/draft-body.md"
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#43' <<< "$OUT" \
  && pass "(ds-q) a CLAIMED-only duplicate is surfaced (queue-only corpus would miss it)" \
  || fail "(ds-q) claimed-only duplicate — rc=$rc out=$OUT"

# #44 carries BOTH labels: the union must de-duplicate it, or it is scored (and
# reported) twice and every count in the summary line is wrong.
run "$SYN" "$GH" --title "Importer drops rows when the batch size exceeds the page limit" \
        --body-file "$FIX/draft-body.md" --threshold 0
rc=$RC
n44=$(grep -c '#44' <<< "$OUT" || true)
[ "$n44" -eq 1 ] \
  && pass "(ds-r) a ticket carrying both labels is scored once" \
  || fail "(ds-r) both-labels dedup — #44 appeared $n44 time(s)"

# The summary line must report the union size, not the sum of the two queries.
grep -q "corpus: 4 scanned" <<< "$OUT" \
  && pass "(ds-s) the corpus count is the union, not the sum of both queries" \
  || fail "(ds-s) corpus count — out=$OUT"

echo "[dup-scan-selftest] both halves of the score carry weight"

# #45 restates the subject entirely in the other grammatical number ("Importers drop a
# row when batches exceed page limits" against "Importer drops rows when the batch size
# exceeds the page limit"), and shares no body symbols at all. Nothing but the
# de-pluralization makes those two titles overlap — remove it and #45 falls to 3.
run "$SYN" "$GH" --title "Importer drops rows when the batch size exceeds the page limit" \
        --body-file "$FIX/draft-body.md"
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#45' <<< "$OUT" \
  && pass "(ds-s2) a title restated in the plural still matches (de-pluralization is live)" \
  || fail "(ds-s2) de-pluralization — rc=$rc out=$OUT"

# The body-symbol half, pinned on its own: with the title contribution zeroed, #43 can
# only clear a threshold of 4 on the four symbols it shares with the draft body
# (`importer.sh`, `--batch-size`, the exit code, and the #42 cross-reference).
run "$SYN" "$GH" --title "Nightly load finishes clean while records go missing" \
        --body-file "$FIX/draft-body.md" --title-weight 0 --threshold 4
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#43' <<< "$OUT" \
  && pass "(ds-s3) body symbols alone can carry a candidate over the bar" \
  || fail "(ds-s3) body-symbol contribution — rc=$rc out=$OUT"

echo "[dup-scan-selftest] the subject is not its own duplicate"

run "$LIVE" "$GH" --issue 500 --threshold 0
rc=$RC
grep -q '#500' <<< "$OUT" \
  && fail "(ds-t) the subject matched itself — self-exclusion is broken" \
  || pass "(ds-t) --issue excludes the subject from its own corpus"

echo "[dup-scan-selftest] adapters and config"

# D-6: jira has no queue label and no claimed label, so there is no corpus. It must
# say so — and it must not have looked, because a silent 0 from an adapter that
# cannot scan is indistinguishable from a clean scan.
#
# THE SUBJECT SHAPE IS THE TEST. This case used to pass `--issue 500`, and a number is
# the one subject shape no jira consumer has — a jira key is never all-digits. It was
# green for months against a tool whose `--issue` numeric guard sat in the argument
# parse, ABOVE the tracker-type check, so every real jira invocation died on a usage 2
# two blocks before this branch could run. The arm was structurally unreachable through
# the only door its consumers use, and the case covering it could not tell. A key here
# reds on that ordering; a number does not.
LOG="$TMP/gh.log"
: > "$LOG"
set +e
OUT="$(PATH="$STUB:$PATH" DUP_SCAN_STUB_CORPUS="$LIVE" SECOND_SHIFT_CONFIG="$TMP/jira.json" \
       DUP_SCAN_STUB_LOG="$LOG" bash "$SCAN" --issue ABC-123 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] && grep -q "not applicable" <<< "$OUT" \
  && pass "(ds-u) a filed jira subject reaches the not-applicable arm → 0, not a usage 2" \
  || fail "(ds-u) jira skip — rc=$rc out=$OUT"

[ ! -s "$LOG" ] \
  && pass "(ds-v) the jira arm makes no tracker call at all" \
  || fail "(ds-v) the jira arm called the tracker: $(cat "$LOG")"

# Custom label vocabulary: the corpus queries must follow config, not the shipped
# literals. Under `triaged`/`building` the synthetic corpus is empty, so a tool that
# ignored config would still find #43 and score it.
run "$SYN" "$TMP/custom.json" --title "Importer drops rows when the batch size exceeds the page limit" \
        --body-file "$FIX/draft-body.md"
rc=$RC
[ "$rc" -eq 0 ] && grep -q "corpus: 0 scanned" <<< "$OUT" \
  && pass "(ds-w) label names come from config, not the shipped literals" \
  || fail "(ds-w) custom labels — rc=$rc out=$OUT"

# Config DISCOVERY, with the environment override deliberately unset — every case above
# hands the tool its config path, so none of them exercises the anchor the tool actually
# ships with. `git rev-parse --git-common-dir` is what lets a lane worktree read the MAIN
# checkout's config, and it is the only path a real intake exit takes. Staged with the
# custom vocabulary so the two outcomes are opposite verdicts, not the same one twice: a
# tool that discovered nothing falls back to `ready-for-dev`/`in-progress` and surfaces
# #43, where a tool that discovered the config scans an empty corpus.
#
# Run from a LANE WORKTREE, not from the checkout root. From the root, a bare relative
# `.claude/second-shift.config.json` resolves to the same file the anchor would find, so
# the case would pass with the anchor deleted — measured: that deletion survived this case
# until it moved here. A worktree has no `.claude/` of its own, so only `--git-common-dir`
# reaches the config, and the two implementations give opposite verdicts.
DISC="$TMP/discover"
mkdir -p "$DISC/.claude"
git init -q "$DISC"
cp "$TMP/custom.json" "$DISC/.claude/second-shift.config.json"
git -C "$DISC" -c user.email=selftest@example.invalid -c user.name=selftest \
    commit -q --allow-empty -m "config only"
git -C "$DISC" worktree add -q --detach "$TMP/discover-wt" >/dev/null 2>&1
set +e
OUT="$(cd "$TMP/discover-wt" && env -u SECOND_SHIFT_CONFIG PATH="$STUB:$PATH" DUP_SCAN_STUB_CORPUS="$SYN" \
       bash "$SCAN" --title "Importer drops rows when the batch size exceeds the page limit" \
       --body-file "$FIX/draft-body.md" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] && grep -q "corpus: 0 scanned" <<< "$OUT" \
  && pass "(ds-x0) a lane worktree discovers the MAIN checkout's config via --git-common-dir" \
  || fail "(ds-x0) config discovery via --git-common-dir — rc=$rc out=$OUT"

# An ABSENT config is a legal state ("this consumer configured nothing") and selects
# the shipped defaults — unlike an unparseable one, which refuses.
run "$SYN" "$TMP/no-such-config.json" --title "Importer drops rows when the batch size exceeds the page limit" \
        --body-file "$FIX/draft-body.md"
rc=$RC
[ "$rc" -eq 10 ] \
  && pass "(ds-x) an absent config selects the shipped defaults" \
  || fail "(ds-x) absent config — rc=$rc out=$OUT"

echo "[dup-scan-selftest] reporting"

run "$LIVE" "$GH" --issue 500 --explain
rc=$RC
[ "$rc" -eq 10 ] && grep -q '#166' <<< "$OUT" \
  && pass "(ds-y) --explain lists sub-threshold items too" \
  || fail "(ds-y) --explain — rc=$rc out=$OUT"

# Determinism: two runs over an unchanged corpus are byte-identical. A ranked report
# that reorders on ties cannot be diffed across intake rounds.
run "$LIVE" "$GH" --issue 500 --explain >/dev/null; first="$OUT"
run "$LIVE" "$GH" --issue 500 --explain >/dev/null; second="$OUT"
[ "$first" = "$second" ] \
  && pass "(ds-z) the ranked report is byte-identical across runs" \
  || fail "(ds-z) report is not deterministic"

# No silent caps: a corpus clipped by --limit must say so.
run "$SYN" "$GH" --title "importer" --limit 1
rc=$RC
grep -q "WARNING" <<< "$OUT" && grep -q "may be truncated" <<< "$OUT" \
  && pass "(ds-aa) a --limit-clipped corpus warns rather than reading as complete" \
  || fail "(ds-aa) --limit truncation warning — rc=$rc out=$OUT"

# The judgment framing is the AC-2 contract: the tool proposes, a reader decides.
run "$LIVE" "$GH" --issue 500
rc=$RC
grep -q "Never close a ticket on this output" <<< "$OUT" \
  && pass "(ds-ab) the report tells the reader to judge, never to auto-close" \
  || fail "(ds-ab) judgment framing absent — out=$OUT"

echo
echo "[dup-scan-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
