#!/usr/bin/env bash
# operator-override-selftest.sh — proves operator-override.sh, the attended-session affordance
# and the per-decision operator override record (#613).
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures ⇒ a per-tool
# behavioral selftest. What it guards is the MECHANISM's own contract — which inputs read as
# headless, what a forged token does and does not buy, and when a yield is refused. The two
# consumers' composed paths are guarded where they live (orchestrate-lean-selftest.sh's intake
# probe, lean-gate-selftest.sh's open-region cases, scenario-liveness-selftest.sh's milestone-1
# chain); no scenario there can reach the resolution ladder's individual rungs, because a
# scenario drives one composed verdict and this file drives eight distinct token states.
#
# ZERO NETWORK. The only tracker read the tool makes is the persistent register's expiry, driven
# here through `GH` pointing at a fake that RECORDS what it was asked.
#
# THE CASE THIS SUITE EXISTS FOR is (g): a token this suite writes BY HAND — never minted by
# `attend` — resolves attended, and the yield still refuses. That is the epic's whole claim
# ("a forged token buys nothing but the pause") reduced to an assertion.
#
# Anti-vacuity: the tool's existence is asserted up front with a distinct exit 2, and the happy
# path is asserted to have WRITTEN a record before any absence-based case is scored — an absence
# assertion over a file that was never created is not a pass.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/operator-override.sh"

PASSES=0
FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$TOOL" ]; then
  echo "FATAL: $TOOL does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi

# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT
WORK="$(mktemp -d -t "operator-override-selftest.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"

REPO="$WORK/repo"
mkdir -p "$REPO/.claude/pipeline-state" "$REPO/docs/plans"
cat > "$REPO/.claude/second-shift.config.json" <<'CFG'
{"configVersion":2,"topology":{"repos":{"acme":{"path":".","baseBranch":"main"}}},"tracker":{"type":"github","branchPrefix":"claude/acme-"}}
CFG
RECORD="$REPO/docs/plans/acme-42-lean-override.md"
REGISTER="$REPO/.claude/lean-overrides.tsv"

# The fake tracker. STATE is read from a file the cases rewrite, so one fake covers the open,
# closed and unreadable arms without three scripts.
GHFAKE="$WORK/gh"
cat > "$GHFAKE" <<'GHF'
#!/usr/bin/env bash
state="$(cat "$GH_STATE_FILE" 2>/dev/null)"
[ "$state" = "ERROR" ] && exit 1
printf '%s\n' "$state"
GHF
chmod +x "$GHFAKE"
export GH_STATE_FILE="$WORK/gh-state"
echo OPEN > "$GH_STATE_FILE"

# One invocation shape. Identity is passed per call rather than exported, because half the cases
# are ABOUT an identity being absent and an exported one would leak into them.
ov() { # ov <run-id-or-empty> <session-id-or-empty> <mode-or-empty> <args...>
  local r="$1" s="$2" m="$3"; shift 3
  env -u RUN_ID -u CLAUDE_CODE_SESSION_ID -u LEAN_ATTEND_MODE \
      ${r:+RUN_ID="$r"} ${s:+CLAUDE_CODE_SESSION_ID="$s"} ${m:+LEAN_ATTEND_MODE="$m"} \
      SECOND_SHIFT_REPO_ROOT="$REPO" GH="$GHFAKE" bash "$TOOL" "$@"
}

echo "== operator-override.sh =="

# ---- (a) AC-1: no token at all ------------------------------------------------------------
out="$(ov r1 s1 '' state 2>&1)"
if [ "$out" = "headless (no-token)" ]; then
  pass "(a) AC-1: an absent token reads as headless"
else fail "(a) expected 'headless (no-token)', got: $out"; fi

# ---- (b) AC-1: a token that exists but carries no identity keys ---------------------------
printf 'this is not a token\n' > "$REPO/.claude/pipeline-state/attend-s1.token"
out="$(ov r1 s1 '' state 2>&1)"
if [ "$out" = "headless (corrupt-token)" ]; then
  pass "(b) AC-1: a corrupt token reads as headless, not as absent and not as attended"
else fail "(b) expected 'headless (corrupt-token)', got: $out"; fi

# ---- (g) AC-1: THE FORGED TOKEN ------------------------------------------------------------
# Written by hand, byte-perfect, never minted. It resolves ATTENDED — the mechanism does not
# claim to detect forgery, and pretending otherwise is the honesty this ticket was written
# against. What it must NOT do is yield.
printf 'session_id: s1\nrun_id: r1\nminted_at: 2026-01-01T00:00:00Z\n' > "$REPO/.claude/pipeline-state/attend-s1.token"
out="$(ov r1 s1 '' state 2>&1)"
ov r1 s1 '' check --gate spec-open-region --issue 42 --region OR-1 --repo-root "$REPO" >/dev/null 2>&1
crc=$?
if [ "$out" = "attended" ] && [ "$crc" -eq 1 ]; then
  pass "(g) AC-1: a FORGED token resolves attended and still yields nothing — the affordance is all it buys"
else fail "(g) forged token: state='$out' (want attended), check rc=$crc (want 1 = refuse)"; fi

# ---- (c) AC-1: session mismatch -------------------------------------------------------------
# The token is named by session id, so this is what a COPIED token looks like: right filename,
# wrong content.
printf 'session_id: someone-else\nrun_id: r1\n' > "$REPO/.claude/pipeline-state/attend-s1.token"
out="$(ov r1 s1 '' state 2>&1)"
if [ "$out" = "headless (session-mismatch)" ]; then
  pass "(c) AC-1: a token whose recorded session is not this one reads as headless"
else fail "(c) expected 'headless (session-mismatch)', got: $out"; fi

# ---- (d) AC-1: run mismatch — STRUCTURAL staleness, no clock involved ----------------------
printf 'session_id: s1\nrun_id: an-older-run\n' > "$REPO/.claude/pipeline-state/attend-s1.token"
out="$(ov r1 s1 '' state 2>&1)"
if [ "$out" = "headless (run-mismatch)" ]; then
  pass "(d) AC-1: a token bound to another run is STALE and reads as headless — no TTL, no date arithmetic"
else fail "(d) expected 'headless (run-mismatch)', got: $out"; fi

# ---- (e) the scheduler's mark outranks a live token ----------------------------------------
printf 'session_id: s1\nrun_id: r1\n' > "$REPO/.claude/pipeline-state/attend-s1.token"
out="$(ov r1 s1 headless state 2>&1)"
if [ "$out" = "headless (marked-headless)" ]; then
  pass "(e) a payload marked headless reads headless even holding a valid token — the second belt"
else fail "(e) expected 'headless (marked-headless)', got: $out"; fi

# ---- (f) attendance is never self-asserted -------------------------------------------------
out="$(ov r1 s1 attended state 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'never self-asserted' <<<"$out"; then
  pass "(f) an env var claiming attendance is an ERROR, not an answer"
else fail "(f) expected rc 2 naming self-assertion, got rc=$rc: $out"; fi

# ---- (p) a spawned payload cannot mint its own attendance ----------------------------------
out="$(ov r1 s1 headless attend 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'marked headless' <<<"$out"; then
  pass "(p) attend REFUSES inside a scheduler-marked payload"
else fail "(p) expected attend to refuse under the headless mark, got rc=$rc: $out"; fi

# ---- (o) attend needs both identities ------------------------------------------------------
out="$(ov r1 '' '' attend 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'CLAUDE_CODE_SESSION_ID' <<<"$out"; then
  pass "(o1) attend refuses with no session identity to bind to"
else fail "(o1) expected a session-identity refusal, got rc=$rc: $out"; fi
out="$(ov '' s2 '' attend 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'export RUN_ID' <<<"$out"; then
  pass "(o2) attend refuses with no run identity, and prints the export"
else fail "(o2) expected a run-identity refusal naming the export, got rc=$rc: $out"; fi

# ---- (h) AC-2: a headless session may not record ------------------------------------------
out="$(ov r1 s1 headless record --gate intake-unqueued --scope intake-attestation --issue 42 --decision d --answer a --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -f "$RECORD" ]; then
  pass "(h) AC-2: a headless run cannot record an override — it has no operator to quote"
else fail "(h) expected a refusal and no file, got rc=$rc (record exists: $([ -f "$RECORD" ] && echo yes || echo no))"; fi

# ---- (i) AC-2: the happy path, and the ANTI-VACUITY anchor for every absence case below ----
ov r1 s1 '' attend >/dev/null 2>&1
out="$(ov r1 s1 '' record --gate spec-open-region --scope open-region-resolution --issue 42 \
        --region OR-1 --decision 'Ordering is best-effort' --answer 'Best effort is fine.' --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$RECORD" ] && grep -q '^> Best effort is fine\.$' "$RECORD"; then
  pass "(i) AC-2: an attended session records the override, quoting the answer verbatim"
else fail "(i) record failed (rc=$rc) or the answer was not quoted: $out"; fi

ov r1 s1 '' check --gate spec-open-region --issue 42 --region OR-1 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass "(i2) AC-2: the recorded override yields for the region it names"
else fail "(i2) the recorded override did not yield"; fi

ov r1 s1 '' check --gate spec-open-region --issue 42 --region OR-9 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 1 ]; then pass "(i3) AC-2: it does NOT yield for a region it does not name"
else fail "(i3) an override for OR-1 cleared OR-9"; fi

ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 1 ]; then pass "(i4) AC-2: it does NOT yield at a different gate — authority is scoped"
else fail "(i4) an open-region override cleared the intake gate"; fi

ov r1 s1 '' check --gate spec-open-region --issue 99 --region OR-1 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 1 ]; then pass "(i5) AC-2: it does NOT yield for another issue"
else fail "(i5) an override for #42 cleared #99"; fi

# ---- (l) AC-5: lint is clean on the record just written -----------------------------------
out="$(ov r1 s1 '' lint --record "$RECORD" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(l) AC-5: lint passes the record the tool itself wrote"
else fail "(l) lint reported $rc violation(s) on a tool-written record: $out"; fi

# ---- (u) AC-2: a refused `record` writes NOTHING -------------------------------------------
# The tool must not create the artifact that blocks the lane. Both arms here are about the write
# that happens BEFORE anyone judges the value: the record's schema is validated against the file
# as parsed, which is the right check, but a parse cannot see where the file landed and cannot
# un-append a block it has already read.
#
# Ordered before (j), which snapshots $RECORD as the known-good copy every later case restores
# from — an arm that left a bad block behind would poison that snapshot, which is itself a second
# reading of the same assertion.
REC_BEFORE="$(cksum < "$RECORD")"

# (u1) --issue is interpolated straight into the record's PATH, so a traversal-shaped value used to
# land a well-formed record outside plansDir and only then refuse. `issue:` is a key the reader
# already rejects, so what fixes this is the staging, not a second check on the argument.
out="$(ov r1 s1 '' record --gate intake-unqueued --scope intake-attestation --issue '../../escaped' \
        --decision d --answer a --repo-root "$REPO" 2>&1)"; rc=$?
STRAY="$(find "$WORK" -name '*escaped*lean-override.md' 2>/dev/null | head -1)"
if [ "$rc" -eq 2 ] && grep -q 'ticket key' <<<"$out" && [ -z "$STRAY" ]; then
  pass "(u1) a traversal-shaped --issue is refused with no record anywhere — the path it named was never written"
else fail "(u1) expected rc 2 and no stray record, got rc=$rc, stray='$STRAY': $out"; fi

# (u2) ...and a typo'd --gate lands in the RIGHT file, which is the costlier half: the block is
# unreadable, so every later `check` for this issue answers UNKNOWN (rc 2) until a human edits
# the record by hand. Asserted on the file's BYTES, because "refused" and "wrote nothing" are
# exactly the two things that used to come apart here.
out="$(ov r1 s1 '' record --gate intake-unqueue --scope intake-attestation --issue 42 \
        --decision d --answer a --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'NOTHING was written' <<<"$out" && [ "$(cksum < "$RECORD")" = "$REC_BEFORE" ]; then
  pass "(u2) a malformed block is refused with the destination record byte-for-byte unchanged"
else fail "(u2) expected rc 2 and an untouched record, got rc=$rc: $out"; fi

# (u3) NON-VACUITY for both arms above: the same shape with every value legal still appends, so
# (u1)/(u2) turn on the refusal and not on `record` having stopped writing at all.
out="$(ov r1 s1 '' record --gate intake-unqueued --scope intake-attestation --issue 42 \
        --decision 'proceed unqueued' --answer 'Go — scoped in the thread.' --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cksum < "$RECORD")" != "$REC_BEFORE" ] && grep -q '^> Go — scoped in the thread\.$' "$RECORD"; then
  pass "(u3) a well-formed block still appends — (u1)/(u2) turn on the refusal, not on a dead writer"
else fail "(u3) expected a clean append, got rc=$rc: $out"; fi

# (u4) THE KEY SHAPE IS THE TRACKER'S. Every case above passes a github issue NUMBER, which is the
# one key shape a jira consumer never has — so the numeric-only reader was pinned green here for
# the mechanism's whole life while being unreachable for those consumers end to end: `record`
# refused the key, and the gate's own printed remedy named the argument its tool would reject.
# Asserted through record AND check, because both routes parse through the same reader and a fix
# to one alone would leave the yield unreachable from the other. Lands at its own path, so the
# shared $RECORD (u1)/(u2)/(j) read stays untouched.
JIRA_RECORD="$REPO/docs/plans/acme-ABC-123-lean-override.md"
# Snapshotted HERE, not reused from (u1)'s: (u3) appended to $RECORD in between.
REC_BEFORE_JIRA="$(cksum < "$RECORD")"
out="$(ov r1 s1 '' record --gate spec-open-region --scope open-region-resolution --issue ABC-123 \
        --region OR-1 --decision 'ship it as scoped' --answer 'Leave it scoped.' --repo-root "$REPO" 2>&1)"; rc=$?
ov r1 s1 '' check --gate spec-open-region --issue ABC-123 --region OR-1 --repo-root "$REPO" >/dev/null 2>&1
crc=$?
if [ "$rc" -eq 0 ] && [ "$crc" -eq 0 ] && [ -f "$JIRA_RECORD" ] && [ "$(cksum < "$RECORD")" = "$REC_BEFORE_JIRA" ]; then
  pass "(u4) a non-numeric tracker key records and then YIELDS — the whole mechanism was unreachable under jira"
else fail "(u4) expected record rc 0 and check rc 0 for a jira-shaped key, got rc=$rc crc=$crc: $out"; fi

# ---- (j) AC-5: a malformed block is UNKNOWN, never a clean negative ------------------------
# The distinction this asserts is the whole rc vocabulary: "there is no override" and "there is
# something here I could not read" must not collapse, or a record the merge boundary is about to
# reject waves the gate through first.
cp "$RECORD" "$WORK/record.good"
printf '\n## Override 2\ngate: spec-open-region\nscope: open-region-resolution\nissue: 42\nregion: none\nrun_id: r1\nsession_id: s1\nexpiry: run\ndecision: d\n\n### Operator answer\n\n> a\n' >> "$RECORD"
out="$(ov r1 s1 '' check --gate spec-open-region --issue 42 --region OR-1 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'region-scoped' <<<"$out"; then
  pass "(j) AC-5: a region-scoped override naming no region is malformed — check answers UNKNOWN, not 'no override'"
else fail "(j) expected rc 2 naming the region requirement, got rc=$rc: $out"; fi

out="$(ov r1 s1 '' lint --record "$RECORD" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(l2) AC-5: lint counts that same block as exactly one violation"
else fail "(l2) expected 1 violation, got $rc: $out"; fi

# ---- (n) AC-2: a per-issue record may not carry a persistent expiry ------------------------
cp "$WORK/record.good" "$RECORD"
printf '\n## Override 2\ngate: intake-unqueued\nscope: intake-attestation\nissue: 42\nregion: none\nrun_id: r1\nsession_id: s1\nexpiry: until-issue:7\ndecision: d\n\n### Operator answer\n\n> a\n' >> "$RECORD"
out="$(ov r1 s1 '' lint --record "$RECORD" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'persistent override belongs in' <<<"$out"; then
  pass "(n) AC-2: persistence in a per-issue record is refused and routed to the register"
else fail "(n) expected the persistence refusal, got rc=$rc: $out"; fi

# ---- (q) a record with no quoted operator answer is not an override -----------------------
cp "$WORK/record.good" "$RECORD"
printf '\n## Override 2\ngate: intake-unqueued\nscope: intake-attestation\nissue: 42\nregion: none\nrun_id: r1\nsession_id: s1\nexpiry: run\ndecision: d\n' >> "$RECORD"
out="$(ov r1 s1 '' lint --record "$RECORD" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'decision nobody stated' <<<"$out"; then
  pass "(q) a block quoting no operator answer is a violation — the quote IS the evidence"
else fail "(q) expected the missing-quote violation, got rc=$rc: $out"; fi
cp "$WORK/record.good" "$RECORD"

# ---- (r) an EMPTY field must not shift the ones after it ----------------------------------
# The regression this pins was live in the first draft: the block reader emitted TAB-separated
# fields, and tab is an IFS-WHITESPACE character, so `IFS=<tab> read` collapsed the run of
# delimiters around an empty value and every later field landed one column left. A record with
# an empty `run_id:` was reported as carrying `expiry: 1` — a real violation, named wrongly, on
# a key the record does not even have. Asserting the REASON, not just the rc, is the whole point:
# the buggy version also returned 1.
cp "$WORK/record.good" "$RECORD"
printf '\n## Override 2\ngate: intake-unqueued\nscope: intake-attestation\nissue: 42\nregion: none\nrun_id:\nsession_id: s1\nexpiry: run\ndecision: d\n\n### Operator answer\n\n> a\n' >> "$RECORD"
out="$(ov r1 s1 '' lint --record "$RECORD" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'run_id is empty' <<<"$out" && ! grep -q 'expiry' <<<"$out"; then
  pass "(r) an empty field is reported as ITSELF — the reader does not shift columns around it"
else fail "(r) expected the run_id violation and nothing about expiry, got rc=$rc: $out"; fi
cp "$WORK/record.good" "$RECORD"

# ---- (k) AC-6: the gate enum is CLOSED -----------------------------------------------------
out="$(ov r1 s1 '' check --gate some-other-gate --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'is not one of' <<<"$out"; then
  pass "(k) AC-6: a gate outside the closed enum is an ERROR — wiring a third gate is a code change here"
else fail "(k) expected rc 2 on an unknown gate, got rc=$rc: $out"; fi

# ---- (m) AC-2: the persistent register -----------------------------------------------------
rm -f "$RECORD"
printf 'intake-unqueued\tintake-attestation\tnone\tuntil-issue:7\tthe upstream queue label is minted by hand until #7 lands\n' > "$REGISTER"
echo OPEN > "$GH_STATE_FILE"
ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass "(m1) AC-2: a live persistent row yields with no per-issue record at all"
else fail "(m1) a live persistent row did not yield"; fi

echo CLOSED > "$GH_STATE_FILE"
out="$(ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'has fired' <<<"$out"; then
  pass "(m2) AC-2: an EXPIRED persistent row reds the run rather than quietly ceasing to apply"
else fail "(m2) expected rc 2 naming the fired expiry, got rc=$rc: $out"; fi

echo ERROR > "$GH_STATE_FILE"
out="$(ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'could not be evaluated' <<<"$out"; then
  pass "(m3) an unevaluable expiry is UNKNOWN — an unreadable tracker is neither a live row nor an expired one"
else fail "(m3) expected rc 2 naming the unevaluable expiry, got rc=$rc: $out"; fi

echo OPEN > "$GH_STATE_FILE"
printf 'intake-unqueued\tintake-attestation\tnone\tuntil-issue:7\t\n' > "$REGISTER"
out="$(ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'justification is empty' <<<"$out"; then
  pass "(m4) AC-2: an UNJUSTIFIED persistent row reds"
else fail "(m4) expected rc 2 on the empty justification, got rc=$rc: $out"; fi

printf 'intake-unqueued\tintake-attestation\tnone\t2026-12-31\twall-clock expiry\n' > "$REGISTER"
out="$(ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'a condition rather than a clock' <<<"$out"; then
  pass "(m5) a date-shaped expiry is refused — the grammar is a condition, deliberately"
else fail "(m5) expected the grammar refusal, got rc=$rc: $out"; fi

# ---- (s) the root resolution the PRODUCTION callers actually take -------------------------
# Every case above pins SECOND_SHIFT_REPO_ROOT, because every case above is about something
# else. Nothing in production sets it: both consumers call this tool from inside a checkout and
# it resolves the SHARED root through `git rev-parse --git-common-dir`. Unasserted, that is where
# the token silently lands somewhere nobody reads it — and a sweep confirmed it, surviving both a
# wrong-default mutant on the override branch and the logic flip on the resolution itself.
#
# DRIVEN FROM A SUBDIRECTORY, which is the load-bearing detail. Run from the repo root, `pwd`
# equals the resolved root, so the resolution's own fallback arm produces the RIGHT answer by
# accident and the logic mutant survives a green case — measured, on the first version of this
# case. A subdirectory is also the honest shape: the gate calls this from a lane worktree, never
# from wherever the root happens to be.
#
# The assertion is the EXACT path, not merely rc 0: every mutant here still exits 0 while writing
# the token somewhere else.
GITREPO="$WORK/gitrepo"
mkdir -p "$GITREPO/.claude" "$GITREPO/sub"
cp "$REPO/.claude/second-shift.config.json" "$GITREPO/.claude/"
git -C "$GITREPO" init -q 2>/dev/null
if [ -d "$GITREPO/.git" ]; then
  ( cd "$GITREPO/sub" && env -u SECOND_SHIFT_REPO_ROOT RUN_ID=gr-run CLAUDE_CODE_SESSION_ID=gr-sess \
      bash "$TOOL" attend ) >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$GITREPO/.claude/pipeline-state/attend-gr-sess.token" ] \
     && [ ! -e "$GITREPO/sub/.claude" ]; then
    pass "(s1) called from a subdirectory with no root override, the token lands at the SHARED root and nowhere else"
  else fail "(s1) attend rc=$rc; token at the shared root: $([ -f "$GITREPO/.claude/pipeline-state/attend-gr-sess.token" ] && echo yes || echo no); stray tree under sub/: $(find "$GITREPO/sub" -mindepth 1 2>/dev/null | head -3)"; fi

  # ...and it reads back as attended from that same resolution, which is what a consumer's gate
  # actually asks. A token written to the right path but read from a different one is the same
  # defect wearing the other hat.
  out="$( cd "$GITREPO/sub" && env -u SECOND_SHIFT_REPO_ROOT RUN_ID=gr-run CLAUDE_CODE_SESSION_ID=gr-sess \
      bash "$TOOL" state 2>&1 )"
  if [ "$out" = "attended" ]; then
    pass "(s2) the reader resolves the same root the writer did"
  else fail "(s2) expected 'attended' from the git-common-dir resolution, got: $out"; fi
else
  fail "(s0) the fixture git repo could not be created — (s1)/(s2) would assert nothing"
fi

# ---- (t) --help prints the header, and only the header ------------------------------------
# `sed -n '2,Np'` is a hand-maintained line number: growing the header silently truncates the
# help text, and this repo has been burned by exactly that. Two assertions, because either
# direction is a real failure — the LAST header line must be present (the range did not fall
# short) and the first line of code must not be (it did not over-reach).
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qF 'macOS ships bash 3.2' <<<"$out" \
   && ! grep -qF 'set -uo pipefail' <<<"$out"; then
  pass "(t) --help prints through the last header line and stops before the code"
else fail "(t) --help did not print exactly the header, rc=$rc: $out"; fi

# ---- (v) #709: design-disarm — the new closed-enum value ----------------------------------
# Same mechanism, a third gate: `check --gate design-disarm` behaves exactly like the other two
# non-region-scoped gates (rc 1 with no record, rc 0 once one is recorded), and `--print-ref`
# returns the block's own 1-indexed FILE-ORDER ordinal `<issue>#<n>` — not a running count of
# design-disarm blocks alone. $RECORD and $REGISTER are cleared first: (m) above left the
# register holding a malformed row, and every row in it is validated before the gate filter
# runs, so an unrelated leftover violation would red these cases for the wrong reason.
rm -f "$RECORD" "$REGISTER"
ov r1 s1 '' check --gate design-disarm --issue 42 --repo-root "$REPO" >/dev/null 2>&1
if [ $? -eq 1 ]; then pass "(v1) #709: design-disarm with no record refuses (rc 1), same as any other gate"
else fail "(v1) expected rc 1 with no override record"; fi

ov r1 s1 '' attend >/dev/null 2>&1
out="$(ov r1 s1 '' record --gate design-disarm --scope design-disarm --issue 42 \
        --decision 'the ticket ships no UI' --answer 'Confirmed — backend-only, disarm it.' --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$RECORD" ] && grep -q '^> Confirmed — backend-only, disarm it\.$' "$RECORD"; then
  pass "(v2) #709: design-disarm records like any other gate, quoting the operator's answer"
else fail "(v2) design-disarm record failed (rc=$rc): $out"; fi

out="$(ov r1 s1 '' check --gate design-disarm --issue 42 --repo-root "$REPO" --print-ref 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "42#1" ]; then
  pass "(v3) #709 D-20/D-21: --print-ref on a hit prints the block's own 1-indexed ordinal"
else fail "(v3) expected rc 0 and '42#1', got rc=$rc: $out"; fi

# A second design-disarm block for the SAME issue: the ref is the block's own file position
# (2), not "the 1st/2nd design-disarm block" — there is only one gate in this file so the two
# readings coincide here, which is exactly why (v3)/(v4) exist as a PAIR: (v4) alone could not
# tell "file position" from "design-disarm-block count" apart.
out="$(ov r1 s1 '' record --gate design-disarm --scope design-disarm --issue 42 \
        --decision 'second decision, same ticket' --answer 'Still disarmed.' --repo-root "$REPO" 2>&1)"; rc=$?
out2="$(ov r1 s1 '' check --gate design-disarm --issue 42 --repo-root "$REPO" --print-ref 2>&1)"
if [ "$rc" -eq 0 ] && [ "$out2" = "42#1" ]; then
  pass "(v4) #709: FIRST match wins — a second design-disarm block does not move the printed ref"
else fail "(v4) expected the ref to stay '42#1' (first match), got rc=$rc, ref='$out2'"; fi

# ---- (v5) #709 D-23: design-disarm is FORBIDDEN in the persistent register -----------------
rm -f "$RECORD"
printf 'design-disarm\tdesign-disarm\tnone\tuntil-issue:7\ta register row would be a blanket opt-out\n' > "$REGISTER"
out="$(ov r1 s1 '' check --gate design-disarm --issue 42 --repo-root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'may not appear in the persistent register' <<<"$out"; then
  pass "(v5) #709 D-23: a design-disarm row in the persistent register is refused as malformed, not honored"
else fail "(v5) expected rc 2 naming the per-issue-only rule, got rc=$rc: $out"; fi

out="$(ov r1 s1 '' lint --register "$REGISTER" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'may not appear in the persistent register' <<<"$out"; then
  pass "(v6) #709 D-23: lint counts that same row as exactly one violation"
else fail "(v6) expected 1 violation naming the per-issue-only rule, got $rc: $out"; fi

# ---- (v7) #709: --print-ref prints NOTHING on a REGISTER hit -------------------------------
# A register row carries no per-block ordinal to cite — exercised on intake-unqueued, since
# design-disarm can never reach the register ((v5) is exactly why).
printf 'intake-unqueued\tintake-attestation\tnone\tuntil-issue:7\tthe upstream queue label is minted by hand until #7 lands\n' > "$REGISTER"
echo OPEN > "$GH_STATE_FILE"
out="$(ov r1 s1 '' check --gate intake-unqueued --issue 42 --repo-root "$REPO" --print-ref 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "(v7) #709: --print-ref prints nothing on a REGISTER hit — a register row carries no block ordinal"
else fail "(v7) expected rc 0 and empty stdout, got rc=$rc: '$out'"; fi
rm -f "$REGISTER" "$RECORD"

# ---- (m6) the register that ships in THIS repo, and the one SUITE-DECLARED SKIP ------------
# The register documents the schema by example, so a malformed one here is inherited by every
# consumer reading it. It is also a consumer-repo artifact that ships inside no plugin, which
# makes this the case install-topology-selftest.sh's exit-77 contract is written for: run from a
# version-keyed install cache there is no repo above the harness, and the file's absence there
# measures nothing about this tool.
#
# The probe is INTRINSIC — the file either resolves or it does not — never a variable the outer
# guard exports, which would leave the same defect alive for anyone running this suite directly.
# And it comes LAST, after every assertion the absent artifact does not touch, so a skip costs
# the other 29 cases nothing.
SHIPPED="$HERE/../../../.claude/lean-overrides.tsv"
if [ -f "$SHIPPED" ]; then
  out="$(ov r1 s1 '' lint --register "$SHIPPED" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then pass "(m6) this repo's own shipped register lints clean"
  else fail "(m6) the shipped register has $rc violation(s): $out"; fi
fi

echo
echo "operator-override.sh: $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1
if [ ! -f "$SHIPPED" ]; then
  echo "SKIP: the repo's .claude/lean-overrides.tsv is a consumer-repo artifact that ships in no plugin, so from an install cache its absence measures nothing — (m6) alone is skipped."
  exit 77
fi
