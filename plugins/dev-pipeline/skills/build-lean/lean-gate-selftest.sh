#!/usr/bin/env bash
# lean-gate-selftest.sh — behavioral suite for the build-lean milestone gates.
#
# Every case drives the REAL lean-gate.sh against a throwaway git tree and a synthetic config,
# through the script's documented seams (LEAN_PROGRESS_FILE, SECOND_SHIFT_CONFIG, --pr-file,
# --comments-file). Zero network.
#
# The cases that matter most are the ones a plausible-looking implementation gets wrong:
#   (b*) the D-41 append rules — a passing gate must append at most ONE `satisfied` line ever,
#        or diagnostic re-runs silently inflate the fix-budget counter.
#   (c*) the D-19 hard stop — 3 attempts, the 4th red exits 4.
#   (e*) AC-9's MUTUAL non-prefix-match. A one-directional reading passes with a derived
#        prefix of `lean/`, which would make every pipeline PR applicable to the lean gate.
#   (g)  G-2 — `satisfied` is a RECORD, not a CACHE. `all` must re-evaluate a milestone that
#        already has a satisfied line, or a green gate from before a fix round certifies code
#        that never passed it.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/lean-gate.sh"
SKILL="$HERE/SKILL.md"

FAILS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

# HERMETICITY. `LEAN_RUN_MODEL` is a documented seam of the gate, so a lean run that stamps
# its model honestly has it EXPORTED — and (m1b)/(p5) below assert the absent-value default
# `unknown`, which that export silently falsifies. The suite inherited the ambient value for
# this one variable, so those two cases red on exactly the machines the lane runs on and pass
# everywhere else: an environment artifact that surfaces at milestone 3 reading like a code
# defect in whatever diff happens to be in flight. Unset it once here so every case starts
# from the documented absent state; (m1c) sets it explicitly for the other direction.
unset LEAN_RUN_MODEL

# `RUN_ID` is the same class, and it hid behind a per-helper defense that did not cover every
# call site. `gate()` unsets it, and so does every `entry` call but one: (d5)'s linked-worktree
# call inherits the ambient value, and `entry` is a SEEDING subcommand — it writes whatever it
# resolves into `<issue>-run-id`. Two hundred lines later (k6)'s milestone 5 resolves that cache,
# finds an id the comment fixture's marker does not carry, and posts a marker instead of
# skipping — with `gate()` having unset `GH_BOT`, which reds the case.
#
# The variable is exported by every real run: build-lean's checklist step 2 says to export it. So
# the failure lands on an operator's own machine, inside milestone 3, on a case unrelated to
# whatever is in flight — and passes standalone, which is the worst shape a false red can have.
# Unset it once here rather than at each call site; every case that needs a value sets one.
unset RUN_ID

# #141: DISARM THE LANE-TREE ASSERTION SUITE-WIDE, and unset it again inside the cases that test
# it. This suite drives the guarded subcommands (`1`..`5`, `all`, `delta`, `verdict`) against bare
# `git init` fixture trees, over many issue keys and three branch prefixes — one tree cannot be on
# nine lane branches at once, and checking a branch out per case would rewrite hundreds of call
# sites to test nothing this file is about. EXPORTED rather than pinned per call for the same
# reason `unset RUN_ID` above is: the seam has to reach every invocation, including the dozen that
# bypass `gate()`. The (wt*) block below unsets it in its own subshells, which is what keeps the
# guard covered here rather than merely tolerated.
export LEAN_GATE_ANY_TREE=1

# Ownership stamp for tools/reap-lean-fixtures.sh (#528): this process's pid, plus its start
# time. A suite killed by a signal leaves WORK behind with no trap to run; the stamp is what
# lets the reaper tell a dead run's leftovers from a live one's without guessing from age alone.
#
# THE EXPRESSION IS NOT SPELLED OUT HERE. It lives in tools/fixture-stamp.sh, which the reaper
# sources too: a producer and a consumer that each spell the sanitization their own way agree
# only by accident of how `ps` pads its lstart column, and on a `ps` that does not pad, the
# reaper reads a live suite's fixture as unowned and deletes it.
#
# OPTIONAL by design — a shipped plugin install carries no tools/ directory, so a suite that
# cannot find the library builds an UNSTAMPED name and the reaper governs it by the long legacy
# floor alone. That is the safe direction: no stamp at all beats a stamp the reader would read
# back as somebody else's.
STAMP_LIB="$HERE/../../../../tools/fixture-stamp.sh"
OWN_SEG=""
if [ -r "$STAMP_LIB" ]; then
  # shellcheck source=../../../../tools/fixture-stamp.sh
  . "$STAMP_LIB"
  OWN_SEG="$(fixture_stamp_own 2>/dev/null)" || OWN_SEG=""
fi
# TRAP INSTALLED BEFORE WORK EXISTS (#528). The old order (mktemp, then trap) left a window —
# five lines, here — where a signal orphaned WORK with nothing registered to remove it. This
# closes it airtight rather than merely dominant; cleanup() already guards on WORK being set,
# so installing the trap before WORK is assigned is safe.
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT
if [ -n "$OWN_SEG" ]; then
  WORK="$(mktemp -d -t "leangate.$OWN_SEG.XXXXXX")"
else
  WORK="$(mktemp -d -t "leangate.XXXXXX")"
fi

# ---------------------------------------------------------------- the tracker stub (#611)
# `entry`/`claim` now READ the ticket at the run boundary, so every case in this file that
# attests would otherwise open a socket — against a repo the fixture does not have. The stub is
# EXPORTED suite-wide, on `LEAN_GATE_ANY_TREE`'s precedent: the seam has to reach the dozen call
# sites that bypass `gate()` (attest_at, pgate, tdgate, jw_gate), and a per-call pin would leave
# whichever one was added next silently live. Cases that want a different answer override `GH`
# for their own invocation, exactly as the pre-existing `gh-dead.sh` cases already do.
#
# It answers the four reads this script makes and fails everything else loudly, so a new read
# added upstream surfaces here as a named stub miss rather than as a network call nobody notices.
GH_STUB="$WORK/gh-ticket-stub.sh"
cat > "$GH_STUB" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [ -n "${STUB_GH_FAIL:-}" ]; then printf '%s\n' "$STUB_GH_FAIL" >&2; exit 1; fi
case "${1:-}/${2:-}" in
  issue/view)
    case "$*" in
      *--json\ body*)   printf '%s\n' "${STUB_GH_BODY:-}" ;;
      *--json\ labels*) printf '%s\n' "${STUB_GH_LABELS//,/$'\n'}" ;;
      *)                printf '%s\n' "${STUB_GH_STATE:-OPEN}" ;;
    esac ;;
  api/*) printf '%s\n' "${STUB_GH_COMMENTS:-[]}" ;;
  pr/list) printf '[]\n' ;;
  *) echo "gh-ticket-stub: unstubbed call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH_STUB"
export GH="$GH_STUB"

# ---------------------------------------------------------------- fixture repo + config
TREE="$WORK/tree"
mkdir -p "$TREE/docs/plans" "$TREE/.claude/audit"
git -C "$TREE" init -q
git -C "$TREE" config user.email t@example.invalid
git -C "$TREE" config user.name t
# Milestone 4's freshness arm reads the verdict record's COMMIT, so the fixture carries real
# commits rather than loose files — a commit-less tree would make every freshness assertion
# vacuous and red the cases that are about something else. `.claude/` is ignored exactly as the
# real repo ignores it, so a cache file appearing or being removed between cases cannot read as
# "code changed after the verdict". `add -A` is safe here and nowhere else: throwaway repo.
printf '.claude/\n' > "$TREE/.gitignore"
commit_tree() { # commit_tree [message]
  git -C "$TREE" add -A >/dev/null 2>&1
  git -C "$TREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
commit_tree "fixture tree"
# The `verdict` writer resolves the record's reviewed_patch_id from merge-base(origin/<baseBranch>,
# HEAD), so the fixture needs a real remote-tracking ref. A throwaway repo has no remote;
# update-ref creates exactly what a fetch would leave behind, without one. The writer refuses when
# this is unresolvable — see (v6) — so its absence would red the suite loudly rather than quietly
# skipping the arm. Milestone 4 stopped reading it at #720.
git -C "$TREE" update-ref refs/remotes/origin/main HEAD

CFG="$WORK/config.json"
cat > "$CFG" <<'EOF'
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
EOF

PROG="$WORK/progress.md"
SPEC="$TREE/docs/plans/acme-7-lean.md"
VERDICT="$TREE/docs/plans/acme-7-lean-verdict.md"

# #663: THE SUBSTRING NETS BELOW ARE CAST OVER THE GATE'S WORDS, NEVER OVER ITS PATHS.
# The gate opens every run with `[lean-gate] config: <path>`, and that path is wherever
# `mktemp -d -t` put this suite's scratch. On Linux `-t` resolves against $TMPDIR, and the
# nightly mutation sweep runs every killer with TMPDIR pointed at a directory of its own
# named `mutation-sweep-work.XXXXXX` — so on that lane, and on no other, (i-580a)'s
# `grep -i mutation` matched the directory the suite was standing in. Both #580 cases failed
# for that reason on every nightly from 2026-08-20, the pair read as unrunnable, and
# lean-gate.sh — the most catalog-covered guard in the tree — was scored by nothing at all
# until #663. The macOS lane never saw it: `mktemp -d -t` there resolves against
# _CS_DARWIN_USER_TEMP_DIR and ignores TMPDIR outright.
#
# Tokens are dropped WHOLE, keyed on the fixture root by `index()` rather than by a regex —
# the root is a path, and escaping one into a pattern is the second half of this same bug.
# What survives is every word the gate itself chose, which is what the #580 cases are about;
# a resurrected D-18 line names `tools/mutation-sweep.sh` relatively (see (i-580c)'s literal)
# and is untouched, and (i-580b)'s tripwire marker is an oracle no scrub can reach.
FIXTURE_ROOT="$(dirname "$WORK")"
scrub_fixture_paths() { # scrub_fixture_paths <text>
  awk -v r="$FIXTURE_ROOT" '{
    n = split($0, w, " "); s = ""
    for (i = 1; i <= n; i++) if (index(w[i], r) == 0) s = s (s == "" ? "" : " ") w[i]
    print s
  }' <<<"$1"
}

# The default issue body every case gets unless it overrides `--issue-file` itself: no Open
# Regions section at all, so milestone 1's pause-and-ask check (AC-10) no-ops before it would
# ever need a live `gh issue view` or a comment trail. Without this EVERY existing milestone-1
# case in this file would attempt a real network call the moment cmd_1 grew that check — the
# file's own masthead promises "Zero network".
ISSUE_NOREGIONS="$WORK/issue-noregions.json"
printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$ISSUE_NOREGIONS"

gate() { # gate <args...>  — always from inside the fixture tree
  # unset RUN_ID: this helper backs nearly every case in the file, including (m1)'s
  # "no RUN_ID, no cache" baseline. Without this, a RUN_ID exported in the CALLING shell
  # (SKILL.md step 2 tells operators/agents to export it for a real run) leaks through —
  # bash subshells inherit the parent's exported environment by default — and (m1)/(m3)
  # spuriously fail asserting the real run's id where the fixture expects `unset` or its
  # own cached value. SECOND_SHIFT_CONFIG/LEAN_PROGRESS_FILE are already pinned per-call
  # for the same reason; RUN_ID was the one seam left open to ambient leakage.
  #
  # unset CLAUDE_CODE_SESSION_ID, for the same reason and a sharper consequence. When the
  # gate recreates a deleted progress file, ensure_progress_file() stamps
  # `session_id: ${CLAUDE_CODE_SESSION_ID:-unset}` — so the OPERATOR's ambient session id
  # lands in the fixture. Every Claude Code session exports it and CI does not, which makes
  # any case reading that key green locally and red in CI. It cost a full review round: (v6)
  # reached the arm it names only because the leaked id skipped an earlier authorship
  # refusal. Pinning it here means the fixture's session identity is always the fixture's.
  # --issue-file defaults to the no-regions fixture and is FIRST, so a caller's own
  # --issue-file (in "$@") is a later occurrence and wins — the parser overwrites left to
  # right, never appends.
  # GH_BOT joins the unset list for #359: milestone 5 now calls cmd_mark, whose no-op test keys
  # on the resolved run id. If a fixture's marker ever stops matching, an ambient GH_BOT would
  # send this suite to a LIVE bot wrapper — a selftest posting a real PR comment. Unset, the
  # same drift surfaces as a loud `GH_BOT must point at the bot wrapper` test failure instead.
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
    # shellcheck disable=SC2030,SC2031  # subshell-local is the point: the identity must reach
    # this one gate invocation and no other, exactly like the unset it re-opens.
    [ -n "$BUILD_SID" ] && export CLAUDE_CODE_SESSION_ID="$BUILD_SID"
    # #613's twin of the line above, and opt-in for the same reason: attendance binds to BOTH
    # identities, so an attended case needs the run id past the unset as well. Empty everywhere
    # else, which is what keeps every other case's `headless` reading a real assertion.
    # shellcheck disable=SC2030,SC2031
    [ -n "$BUILD_RID" ] && export RUN_ID="$BUILD_RID"
    cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
# $BUILD_SID: the OPT-IN seam past the unset above, and empty for every case that does not ask.
# #446 makes cmd_mark refuse any session outside the recorded build-session set, and milestone 5
# calls cmd_mark — so the handful of cases that reach it must run as an identity attest_at()
# actually recorded, while every other case keeps the genuinely-unset pin the comment above
# argues for. Set per call via `bgate`, never globally: a suite-wide session id would restore
# exactly the ambient leak that cost (v6) a review round.
BUILD_SID=""
BUILD_RID=""
bgate() { BUILD_SID="$ENTRY_SID" gate "$@"; }
# Capture-then-default, NOT `grep -cF ... || echo 0`: on zero matches `grep -c` prints "0" AND
# exits 1, so the `||` fires too and the helper emits "0\n0" — which every `-eq 0` comparison
# through it then rejects as a non-integer, failing the case for a reason unrelated to the gate.
# Non-zero counts were unaffected, which is why the shape survived: it only breaks the assertions
# that a counter did NOT move. pcount() (the (ea*) block) and the gate's own count_matches()
# already use the form below.
count_in_progress() {
  local n
  [ -f "$PROG" ] || { echo 0; return 0; }
  n="$(grep -cF "$1" "$PROG" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

# #416: every build-role subcommand refuses with exit 2 until the run has an entry attestation
# row, so a progress file seeded from scratch needs one before ANY other case can run. It is
# produced by driving the REAL `entry` rather than by echoing the row — a hand-written line
# would keep passing after the writer changed shape, and this suite's own D-41 cases show what
# that costs. The ledger is created here, per tree, because `entry` resolves it relative to the
# git common dir of the cwd, so one file cannot serve five fixture trees.
ENTRY_SID="sess-lean-fixture"
attest_at() { # attest_at <tree> <config> <progress-file> <issue>
  mkdir -p "$1/.claude/audit"
  printf '{"tool":"Bash"}\n' > "$1/.claude/audit/$ENTRY_SID.jsonl"
  # RUN_ID is UNSET here, deliberately. `entry` creates the progress file when it is absent,
  # header included, and SKILL.md orders it BEFORE the export — so this is the ordering every
  # honest run is in, and a case whose header must carry a particular id gets it from the
  # gate's own heal on the first call that establishes one. Passing the id in here instead
  # would hide that production behavior behind a fixture knob: the header would be right in
  # the suite and `unset` in the field.
  ( unset RUN_ID; cd "$1" && CLAUDE_CODE_SESSION_ID="$ENTRY_SID" SECOND_SHIFT_CONFIG="$2" \
    LEAN_PROGRESS_FILE="$3" bash "$GATE" entry "$4" >/dev/null 2>&1 )
}
# The unattested form, for the (p*) cases that are ABOUT the missing row. Every other case
# wants the attested one — that is the state a run following SKILL.md step 1 is in.
reset_progress_unattested() { rm -f "$PROG"; }
reset_progress() { reset_progress_unattested; attest_at "$TREE" "$CFG" "$PROG" 7; }
# Milestone 5 asserts milestones 1-4 left satisfied records, so the (k) cases need a
# progress file in the state a real run would have reached by then.
seed_progress_1_to_4() {
  reset_progress_unattested
  { echo "# lean run — issue 7"; echo "run_id: r-1"; } > "$PROG"
  local m
  for m in 1 2 3 4; do echo "2026-01-01T00:00:00Z | milestone-$m | satisfied" >> "$PROG"; done
  attest_at "$TREE" "$CFG" "$PROG" 7
}

echo "[lean-gate-selftest]"

# ---- (a) milestone 1: existence at the pinned path + >= 1 AC-n, and nothing else ---------
reset_progress
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no committed spec' <<<"$out"; then
  pass "(a1) milestone-1 fails when the lean spec is absent"
else fail "(a1) expected rc=1, got $rc: $out"; fi

printf '# spec\n\nNothing numbered here.\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no numbered AC-n' <<<"$out"; then
  pass "(a2) milestone-1 fails when the spec carries no AC-n"
else fail "(a2) expected rc=1 on an AC-less spec, got $rc: $out"; fi

printf '# spec\n\n- AC-1: a thing\n- AC-2: another\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(a3) milestone-1 passes on a spec with AC-n at the pinned path"
else fail "(a3) expected rc=0, got $rc: $out"; fi

# ---- (b) D-41 append rules ---------------------------------------------------------------
# A passing evaluation appends at most ONE satisfied line, no matter how many times it runs.
gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1
n="$(count_in_progress '| milestone-1 | satisfied')"
if [ "$n" -eq 1 ]; then pass "(b1) repeated passing evaluations append exactly one satisfied line (idempotent)"
else fail "(b1) expected 1 satisfied line, got $n"; fi

# Of (a1)/(a2), only (a2) — the CONTENT failure — is an attempt; (a1)'s absence is its own line
# kind since #494. Passes must never add either.
n="$(count_in_progress '| milestone-1 | attempt |')"
if [ "$n" -eq 1 ]; then pass "(b2) only FAILED evaluations append attempt lines (passes do not inflate the counter)"
else fail "(b2) expected 1 attempt line, got $n"; fi

# ---- (a4)-(a7) #562: a committed Decision Ledger's provenance lints, via ledger-lint.sh ------
# The check is CONDITIONAL on the section existing at all — whether a spec carries one is #517's
# row-presence question, distinct from this one's provenance-validity question. Each case resets
# the progress file itself; (a1)-(b2) above are done reading it by this point.
reset_progress
printf '# spec\n\n- AC-1: a thing\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | Fix shape | Do the thing | issue-specified |\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'fails ledger-lint' <<<"$out" && grep -q "provenance 'issue-specified' not in" <<<"$out"; then
  pass "(a4) #562 AC-1: an invented provenance value in the committed Decision Ledger refuses milestone 1"
else fail "(a4) expected rc=1 naming the invented provenance, got $rc: $out"; fi

reset_progress
printf '# spec\n\n- AC-1: a thing\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | Fix shape | Do the thing | codebase-derived |\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(a5) #562 AC-2: a Decision Ledger with only enum-legal provenance passes milestone 1"
else fail "(a5) expected rc=0 on a clean ledger, got $rc: $out"; fi

reset_progress
printf '# spec\n\n- AC-1: a thing\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(a6) #562 AC-3: a spec with no Decision Ledger section at all is unaffected (row-presence is #517's question, not this one's)"
else fail "(a6) expected rc=0 with no Decision Ledger section, got $rc: $out"; fi

# The explicit empty form is itself a clean ledger-lint pass (no rows, no provenance to invent).
reset_progress
printf '# spec\n\n- AC-1: a thing\n\n## Decision Ledger\n\nNo material decisions — all choices codebase-derived.\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(a7) a Decision Ledger stating the explicit empty form passes milestone 1"
else fail "(a7) expected rc=0 on the explicit empty form, got $rc: $out"; fi

# (a8) round-1 review Blocker 3: the section detector at :2962 is a second copy of
# ledger-lint.sh's own check-1 detector, and the `\*\*` (bold-heading) alternative was
# exercised by no case — a mutant narrowing the detector to the `#{1,6}` branch alone would
# have survived every suite while silently skipping provenance validation on this form.
# intake-interviewer/SKILL.md:226 documents `**Decision Ledger**` as what the interview emits.
reset_progress
printf '# spec\n\n- AC-1: a thing\n\n**Decision Ledger**\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | Fix shape | Do the thing | issue-specified |\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'fails ledger-lint' <<<"$out" && grep -q "provenance 'issue-specified' not in" <<<"$out"; then
  pass "(a8) the bold-heading Decision Ledger form is detected too — an invented provenance under it refuses milestone 1"
else fail "(a8) expected rc=1 naming the invented provenance under the bold heading, got $rc: $out"; fi

# ---- (a9)-(a14) #517: the committed spec reconciles against the pre-flight receipt --------
# The receipt is reached through --ledger-file, the seam #533 opened for exactly this reason:
# the DEFAULT path is $STATE_DIR/<issue>-ledger.md under the git common dir, a directory shared
# by every worktree on the machine, and a suite writing there would collide with whatever lane
# is live. Every case below therefore states its own receipt.
#
# The receipt binds TWO rows and carries a third it does not, so "the check bound something"
# and "the check bound everything" are distinguishable in the pass line.
RC_RECEIPT="$WORK/517-receipt.md"
printf '%s\n' '# receipt' '## Decision Ledger' \
  '| ID | Decision | Resolution | Provenance | Kind |' \
  '| --- | --- | --- | --- | --- |' \
  '| D-1 | Rate limit | 100/min, per tenant | user-answered | intent |' \
  '| D-2 | Cache TTL | 5 minutes | codebase-derived | fact |' \
  '| D-3 | Fix scope | Both call sites | user-delegated | intent |' \
  > "$RC_RECEIPT"
rc_spec() { # rc_spec <resolution-for-D-3>
  printf '%s\n' '# spec' '' '- AC-1: a thing' '' '## Decision Ledger' \
    '| ID | Decision | Resolution | Provenance |' \
    '| --- | --- | --- | --- |' \
    '| D-1 | Rate limit | 100/min, per tenant | user-answered |' \
    "| D-3 | Fix scope | ${1:-Both call sites} | user-delegated |" > "$SPEC"
}

# (a9) a bound row the spec drops. rc=1 AND an attempt line: editing the committed spec is a fix
# the build role can make, so this spends fix budget exactly as #562's provenance lint does.
reset_progress
rc_spec; grep -v 'D-3' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC"
out="$(gate --ledger-file "$RC_RECEIPT" 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not reconcile with the pre-flight ledger' <<<"$out" \
   && grep -q 'D-3 (user-delegated)' <<<"$out" \
   && [ "$(count_in_progress '| milestone-1 | attempt |')" -eq 1 ]; then
  pass "(a9) #517 AC-2/AC-7: a dropped receipt row refuses milestone 1 and spends a fix attempt"
else fail "(a9) expected rc=1 naming D-3 plus one attempt line, got $rc / $(count_in_progress '| milestone-1 | attempt |'): $out"; fi

# (a10) the row is there and resolves the other way, with no marker.
reset_progress
rc_spec 'Only the import path'
out="$(gate --ledger-file "$RC_RECEIPT" 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no departure marker' <<<"$out"; then
  pass "(a10) #517 AC-3: a bound row re-decided without a DEPARTURE marker refuses milestone 1"
else fail "(a10) expected rc=1 on an unflagged reversal, got $rc: $out"; fi

# (a11) the declared departure passes — and AC-8, the pass line disclosing what was reconciled.
# The COUNTS are asserted, not just the presence of a note: a note reading "0 bound" would sit
# in the same place and say nothing, which is the shape a silently-inert check hides behind.
reset_progress
rc_spec 'DEPARTURE — narrowed to the import path; the export path is dead code'
out="$(gate --ledger-file "$RC_RECEIPT" 1 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '2 bound, 1 carried, 1 departure(s)' <<<"$out"; then
  pass "(a11) #517 AC-4/AC-8: a reasoned DEPARTURE passes, and the pass line discloses the counts"
else fail "(a11) expected rc=0 with the reconciliation counts on the pass line, got $rc: $out"; fi

# (a12) ABSENT receipt is inert (AC-7). Most tickets never went through pre-flight, so the
# common case must not acquire a note at all — a pass line that grew one for every run would
# make the disclosure in (a11) meaningless. The spec here is the (a9) shape that DOES refuse
# when a receipt is present, so this case cannot be satisfied by a spec that would pass anyway.
reset_progress
rc_spec; grep -v 'D-3' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'bound,' <<<"$out"; then
  pass "(a12) #517 AC-7: with no pre-flight receipt the check is inert and adds no note"
else fail "(a12) expected a silent rc=0 with no receipt, got $rc: $out"; fi

# (a13) an UNREADABLE receipt is an ENVIRONMENT refusal, not a fix attempt (AC-7). This is the
# arm that decides whether the mechanism can fail open: every read inside the reconciliation is
# a `grep ... || true`, so an unreadable receipt binds nothing and would otherwise report a
# clean reconciliation. rc=2 and, just as load-bearing, the attempt counter must not move — no
# edit the build role can make fixes a file it cannot read, and three such blips would
# hard-stop the run at rc=4 with a rescue path nobody can act on.
#
# TWO calls, because the ordinary one is not attributable. #533's check_pause_and_ask reports
# the same fact for the same file, so deleting the reconciliation entirely leaves the first
# assertion passing — measured, not assumed. The OBSERVE call is the discriminator: that check
# sits under the observe guard and is skipped there, so under LEAN_GATE_OBSERVE=1 the only
# reader left that can refuse an unreadable receipt is this one.
reset_progress
rc_spec
RC_UNREADABLE="$WORK/517-receipt-unreadable.md"
cp "$RC_RECEIPT" "$RC_UNREADABLE"; chmod 000 "$RC_UNREADABLE"
if [ -r "$RC_UNREADABLE" ]; then
  fail "(a13) precondition: chmod 000 left the receipt readable (running as root?) — the fail-open arm is unverified"
else
  out="$(gate --ledger-file "$RC_UNREADABLE" 1 7)"; rc=$?
  obs_out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
              bash "$GATE" --issue-file "$ISSUE_NOREGIONS" --ledger-file "$RC_UNREADABLE" 1 7 2>&1 )"; obs_rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'could not read pre-flight ledger' <<<"$out" \
     && [ "$obs_rc" -eq 2 ] && grep -q 'while reconciling it against' <<<"$obs_out" \
     && [ "$(count_in_progress '| milestone-1 | attempt |')" -eq 0 ]; then
    pass "(a13) #517 AC-7: an unreadable receipt is an envfail (rc=2) in the observe pass too, and spends no fix budget"
  else fail "(a13) expected rc=2 both ways with no attempt line, got $rc / observe $obs_rc / $(count_in_progress '| milestone-1 | attempt |'): $out || $obs_out"; fi
fi
chmod 644 "$RC_UNREADABLE"

# (a14) the reconciliation runs in the OBSERVE pass, above the guard that gates the gh-calling
# pause-and-ask check (AC-7). `cmd_all`'s cheap pre-pass reaches milestone 1 through that seam,
# so a check placed below the guard would let `all` report a milestone-1 pass on a spec the very
# next direct call refuses. The counterpart half is asserted too: observing records nothing.
reset_progress
rc_spec; grep -v 'D-3' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" --ledger-file "$RC_RECEIPT" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not reconcile' <<<"$out" \
   && [ "$(count_in_progress '| milestone-1 |')" -eq 0 ]; then
  pass "(a14) #517 AC-7: the reconciliation is evaluated in the observe pass and records nothing there"
else fail "(a14) expected rc=1 with an empty progress record under LEAN_GATE_OBSERVE, got $rc / $(count_in_progress '| milestone-1 |'): $out"; fi

reset_progress
printf '# spec\n\n- AC-1: a thing\n- AC-2: another\n' > "$SPEC"

# ---- (c) D-19 fix budget: 3 attempts, the 4th red hard-stops -----------------------------
# #496: the three reds are the milestone-4 CLASS (5 — a malformed record is a review-round
# problem, not a build fix), and the 4th is still 4. Both halves matter: a budget that stopped
# reporting 4 would lose the hard stop, and a 4th call that reported 5 would tell the scheduler to
# keep re-spawning REVIEW past the bound. Exhaustion outranks the class.
#
# #642 RE-POINTED THIS at a record that is PRESENT and keyless. It used to drive milestone 4's
# ABSENCE — which was legal while absence charged the fix budget, and is not now that it routes to
# the `absent` verb (AC-3). The class under test is unchanged (5) and so is the property; only the
# refusal driving it is one the budget still counts. The record is removed again afterwards so the
# (j) block still opens on a tree with no committed verdict.
reset_progress
printf 'verdict=approve\n' > "$VERDICT"; commit_tree "a keyless verdict record, for the budget cases"
rcs=""
for _ in 1 2 3 4; do gate 4 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "5554" ]; then pass "(c1) fix budget: attempts 1-3 return the milestone-4 class, the 4th returns 4 (hard stop)"
else fail "(c1) expected rc sequence 5554, got $rcs"; fi
if [ "$(count_in_progress 'budget-exhausted')" -ge 1 ]; then
  pass "(c2) budget exhaustion is recorded in the progress file"
else fail "(c2) no budget-exhausted line recorded"; fi

# #642 AC-3: the ABSENT counterpart of (c1), on the site (c1) used to drive. Four calls against a
# record that does not exist must charge NOTHING and must not hard-stop — the remedy is the
# handoff the checklist orders next, not a fix. The class is still 5, which is what keeps the
# scheduler routing to the review half.
rm -f "$VERDICT"; commit_tree "the keyless record is withdrawn"
reset_progress
rcs=""
for _ in 1 2 3 4; do gate 4 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "5555" ] \
   && [ "$(count_in_progress '| milestone-4 | absent |')" -eq 4 ] \
   && [ "$(count_in_progress '| milestone-4 | attempt |')" -eq 0 ]; then
  pass "(c2b) #642: an absent verdict record records 'absent', keeps the milestone-4 class, and charges no fix attempt"
else fail "(c2b) expected rc 5555 / 4 absent / 0 attempts, got $rcs / $(count_in_progress '| milestone-4 | absent |') / $(count_in_progress '| milestone-4 | attempt |')"; fi

# ---- (c3-c6) #494: an ABSENT artifact is not a failed fix --------------------------------
# (c1) above is the deliberate control: it drives MILESTONE 4's identical `[ -f ]` absence,
# which #494 D-7 scopes OUT. Its rc sequence carrying a 4th-red 4 rather than three `absent` lines
# is the evidence that the change below landed at milestone 1's call site alone and did not
# generalize — #496 re-keyed the first three digits to milestone 4's class, not to absence.
#
# (c3) asserts BOTH halves on purpose. "attempt_count() did not rise" passes vacuously if the
# absence path records nothing at all, so the absent lines must be counted too.
reset_progress
held_spec_494="$WORK/held-spec-494.md"
mv "$SPEC" "$held_spec_494"
rcs=""
for _ in 1 2 3; do gate 1 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "111" ] \
   && [ "$(count_in_progress '| milestone-1 | absent |')" -eq 3 ] \
   && [ "$(count_in_progress '| milestone-1 | attempt |')" -eq 0 ]; then
  pass "(c3) an absent spec records 'absent' lines, returns 1, and leaves the fix budget untouched"
else fail "(c3) expected rc 111 / 3 absent / 0 attempts, got $rcs / $(count_in_progress '| milestone-1 | absent |') / $(count_in_progress '| milestone-1 | attempt |')"; fi

# Same progress file, deliberately: the three absent calls above must have bought milestone 1's
# fix budget nothing, so a CONTENT failure still gets the full 3 attempts and hard-stops on the
# 4th. Under the pre-#494 conflation this sequence would read 444 4.
printf '# spec\n\nNothing numbered here.\n' > "$SPEC"
rcs=""
for _ in 1 2 3 4; do gate 1 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "1114" ] && [ "$(count_in_progress '| milestone-1 | attempt |')" -eq 4 ]; then
  pass "(c4) after 3 absent calls a CONTENT failure still gets attempts 1-3, and the 4th returns 4"
else fail "(c4) expected rc sequence 1114 and 4 attempt lines, got $rcs / $(count_in_progress '| milestone-1 | attempt |')"; fi

# The absent kind is bounded too (D-2) — free absence would leave nothing stopping a session
# that loops on SKILL.md step 3 forever. 10 calls, the 11th hard-stops on rc=4.
reset_progress
rm -f "$SPEC"
rcs=""
for _ in 1 2 3 4 5 6 7 8 9 10 11; do gate 1 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "11111111114" ] && [ "$(count_in_progress '| milestone-1 | absent-exhausted |')" -eq 1 ]; then
  pass "(c5) the absent budget is 10; the 11th call returns 4 and records absent-exhausted"
else fail "(c5) expected rc sequence 11111111114 and 1 absent-exhausted line, got $rcs / $(count_in_progress '| milestone-1 | absent-exhausted |')"; fi

# D-5's naming trap, pinned: `absent-budget-exhausted` would carry the substring (c2) counts, so
# exhausting the absent budget would silently read as exhausting the FIX budget.
if [ "$(count_in_progress 'budget-exhausted')" -eq 0 ]; then
  pass "(c6) absent-exhausted does not inflate the budget-exhausted count (c2) reads"
else fail "(c6) absent exhaustion recorded a budget-exhausted line: $(cat "$PROG")"; fi

# The number the exhaustion line reports is the count of ABSENT CALLS, not of progress lines
# that mention absence. Only the record can catch this: past the cap the verdict is already 4
# either way, so a counter that also swept up the `absent-exhausted` lines it wrote itself
# would red nothing while reporting 13 for a 12th call. That is the same "the record cannot be
# read as a count of what happened" defect this ticket exists to fix, one level down.
gate 1 7 >/dev/null 2>&1
if [ "$(count_in_progress '| milestone-1 | absent-exhausted | 12 calls')" -eq 1 ]; then
  pass "(c7) the exhaustion record counts absent CALLS, not the absence lines it wrote itself"
else fail "(c7) expected an 'absent-exhausted | 12 calls' line, got: $(grep 'absent-exhausted' "$PROG" | tr '\n' ' ')"; fi

mv "$held_spec_494" "$SPEC"

# ---- (d) AC-14 entry gate ----------------------------------------------------------------
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u CLAUDE_CODE_SESSION_ID -u RUN_ID bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'CLAUDE_CODE_SESSION_ID is unset' <<<"$out"; then
  pass "(d1) entry refuses when the session id is unresolvable"
else fail "(d1) expected rc=1 on an unset session id, got $rc: $out"; fi

: > "$TREE/.claude/audit/sess-empty.jsonl"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u RUN_ID CLAUDE_CODE_SESSION_ID=sess-empty bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'missing or empty' <<<"$out"; then
  pass "(d2) entry refuses on an EMPTY ledger — directory existence is not the test"
else fail "(d2) expected rc=1 on an empty ledger, got $rc: $out"; fi

out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u RUN_ID CLAUDE_CODE_SESSION_ID=sess-absent bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(d3) entry refuses when no ledger file exists for the session"
else fail "(d3) expected rc=1 on an absent ledger, got $rc: $out"; fi

# env -u RUN_ID on every `entry` call above and below is load-bearing, not hygiene: `entry` is
# one of the two build-role subcommands that SEED the run-id cache, so an ambient RUN_ID (the
# operator exports one for a real run) writes that id into the fixture tree — and milestone 5's
# marker check then resolves an identity no fixture carries. It cost a milestone-3 red on #359.
printf '{"tool":"Bash"}\n{"tool":"Read"}\n' > "$TREE/.claude/audit/sess-live.jsonl"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u RUN_ID CLAUDE_CODE_SESSION_ID=sess-live bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(d4) entry passes on a live, non-empty ledger"
else fail "(d4) expected rc=0 on a live ledger, got $rc: $out"; fi

# (d5) THE FALSE REFUSAL. Every case above hands the gate a hand-written ledger, so all of
# them agree with `cmd_entry` about the path by construction and none can catch the reader
# and the WRITER disagreeing. They did: the audit hook wrote beside the worktree while this
# gate reads `--git-common-dir/..`, so a lean run — which works in a linked worktree by
# contract — was refused at the door for a ledger it had just written correctly.
#
# So this case drives the REAL hook rather than synthesizing its output. It is deliberately
# a cross-plugin reach: a copy of the writer's path logic here could not fail on a writer
# edit, which is the whole defect. The writer's own suite covers the same agreement from
# its side (audit-selftest.sh Tests 10-14); this one covers it from the reader's, so a
# regression in either half reds a suite that owns that half.
#
# Reaching the sibling takes a LADDER, not a fixed hop count, because two on-disk layouts
# ship this pair: the marketplace repo, where plugins sit adjacent under `plugins/`, and a
# version-keyed install cache (`<root>/<plugin>/<version>/...`), where a version segment
# separates them. A fixed `../../../` resolves only in the first, so from every install this
# case took its not-found branch and red the suite — the exact class
# tools/install-topology-selftest.sh stages for. Same ladder as
# check-model-tiers.sh's resolve_sibling_plugin_root(). NOT a lockstep pair with the copy in
# lean-reconcile-selftest.sh: each suite resolves its own sibling independently and drift
# between them breaks nothing — the shared thing is a technique, not a contract.
HOOK_REPO="$HERE/../../../audit-toolkit/hooks/audit-tool-calls.sh"
HOOK="$HOOK_REPO"
if [ ! -x "$HOOK" ]; then
  # Cache layout: the HIGHEST staged version that actually carries the hook. Glob order is
  # lexical, so a bare `tail -1` ranked 9.0.0 above 10.0.0. The version is two dirs up from
  # the hook, so it is keyed out explicitly rather than sorted on the whole path.
  HOOK="$(for c in "$HERE"/../../../../audit-toolkit/*/hooks/audit-tool-calls.sh; do
    [ -x "$c" ] || continue
    printf '%s\t%s\n' "$(basename "$(dirname "$(dirname "$c")")")" "$c"
  done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-)"
fi
if [ ! -x "$HOOK" ]; then
  fail "(d5) audit hook not found — searched $HOOK_REPO and $HERE/../../../../audit-toolkit/<version>/hooks/audit-tool-calls.sh; the writer half of the ledger contract is unreachable"
else
  WT_ENTRY="$WORK/wt-entry"
  git -C "$TREE" worktree add -q -b wt-entry "$WT_ENTRY" >/dev/null 2>&1
  if [ ! -d "$WT_ENTRY" ]; then
    fail "(d5) could not create a linked worktree on the fixture repo"
  else
    printf '%s' "{\"session_id\":\"sess-wt\",\"cwd\":\"$WT_ENTRY\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WT_ENTRY/x\"}}" \
      | CLAUDE_PROJECT_DIR="$WT_ENTRY" "$HOOK"
    # `env -u RUN_ID`, like every sibling entry case above, and for a consequence that reaches
    # far past this case: `entry` is one of the three subcommands that PERSIST the run-id cache,
    # so an ambient RUN_ID seeds $TREE's cache with the operator's own id. (k6) then resolves it
    # in cmd_mark's no-op test, matches no fixture marker, and falls through to the LIVE $GH_BOT
    # write path — which is green in CI (no ambient RUN_ID) and red for any operator who followed
    # SKILL.md step 2 and kept theirs exported. CLAUDE_CODE_SESSION_ID stays set on purpose: this
    # case is about the worktree ledger the hook wrote under sess-wt.
    out="$( cd "$WT_ENTRY" && env -u RUN_ID SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
            CLAUDE_CODE_SESSION_ID=sess-wt bash "$GATE" entry 7 2>&1 )"; rc=$?
    if [ "$rc" -eq 0 ]; then
      pass "(d5) entry passes in a linked worktree whose ledger the REAL hook wrote"
    else
      fail "(d5) the false refusal is back — entry rejected a worktree run with a live hook (rc=$rc): $out"
    fi
  fi
fi

# ---- (e) AC-1/AC-2/AC-4 (#413): the branch formula is the staged lane's, verbatim ---------
# The gate echoes the resolved prefix into the progress-file header, which is where we read it.
# There is no `lean/` re-rooting left to assert in two directions: one namespace, one prefix.
reset_progress
# Use milestone 1 (not `entry`) to materialize the header: entry refuses without a live
# ledger for THIS session, so it would leave no progress file to read the prefix from.
gate 1 7 >/dev/null 2>&1 || true
resolved="$(grep '^branch_prefix:' "$PROG" 2>/dev/null | awk '{print $2}')"
if [ "$resolved" = "claude/acme-" ]; then
  pass "(e1) the resolved prefix IS tracker.branchPrefix — no lean/ namespace is derived"
else fail "(e1) expected claude/acme-, got '$resolved'"; fi

# AC-1 is a byte-equality claim against the staged lane's `${BRANCH_PREFIX}${ISSUE_NUMBER}`
# (stages/2-worktree.md), so assert the composed NAME, not just the prefix it starts with.
if [ "$resolved""7" = "claude/acme-7" ]; then
  pass "(e2) the branch name is <branchPrefix><key>, byte-identical to the staged formula"
else fail "(e2) branch name mismatch: '$resolved""7'"; fi

# AC-2: under jira the KEY is lowercased in the branch name while the PREFIX is used as
# configured. Read the COMPOSED name off the progress header, which is the record every
# downstream reader (pipeline-retro's PR lookup) resolves the branch from — rebuilding it as
# `<branch_prefix><issue>` is right under github and wrong here, which is why the key exists.
CFG_JIRA="$WORK/config-jira-branch.json"
jq '.tracker.type = "jira" | .tracker.writes = false | .tracker.branchPrefix = "jdoe/"
    | .tracker.keyPattern = "[A-Z]+-[0-9]+"' "$CFG" > "$CFG_JIRA"
PROG_JIRA="$WORK/p2.md"; rm -f "$PROG_JIRA"
# `entry` is what materializes the header, and it is also this run's attestation — the same
# ordering reset_progress() puts every other case in.
attest_at "$TREE" "$CFG_JIRA" "$PROG_JIRA" GH-540
jira_branch="$(grep '^branch:' "$PROG_JIRA" 2>/dev/null | awk '{print $2}')"
if [ "$jira_branch" = "jdoe/gh-540" ]; then
  pass "(e3) under jira the branch key is lowercased: jdoe/ + GH-540 -> jdoe/gh-540"
else fail "(e3) expected jdoe/gh-540, got '$jira_branch'"; fi

# ...and the github key is NOT mangled by that transform — an unconditional lowercase would be
# invisible on digits, so the negative half of AC-2 needs a key that could change.
if [ "$(grep '^branch:' "$PROG" 2>/dev/null | awk '{print $2}')" = "claude/acme-7" ]; then
  pass "(e3b) under github the composed name is <prefix><key>, untransformed"
else fail "(e3b) github branch name mismatch: $(grep '^branch:' "$PROG" 2>/dev/null)"; fi

# AC-4: an unset tracker.branchPrefix must FAIL rather than fall back to the `claude/acme-`
# placeholder — that fallback is defect 2 in the ticket, and a guessed namespace stays invisible
# until the PR is open. The fixture tree carries no remote branches, so detection finds nothing
# and takes the refusal path.
CFG_NOPREFIX="$WORK/config-noprefix.json"
jq 'del(.tracker.branchPrefix)' "$CFG" > "$CFG_NOPREFIX"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOPREFIX" LEAN_PROGRESS_FILE="$WORK/p3.md" \
        bash "$GATE" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'refusing to guess' <<<"$out" \
   && ! grep -qF 'claude/acme-' <<<"$out"; then
  pass "(e4) an unresolvable prefix is a loud refusal, never the claude/acme- placeholder"
else fail "(e4) expected rc=2 with no placeholder fallback, got $rc: $out"; fi

# ---- (f) AC-1 / D-33: the SKILL.md line cap ----------------------------------------------
if [ -f "$SKILL" ]; then
  lines="$(wc -l < "$SKILL" | tr -d ' ')"
  if [ "$lines" -le 60 ]; then pass "(f) SKILL.md is $lines lines (<= 60, frontmatter included)"
  else fail "(f) SKILL.md is $lines lines — the cap is 60 including frontmatter"; fi
else fail "(f) SKILL.md not found at $SKILL"; fi

# ---- (g) G-2: `satisfied` is a record, not a cache ---------------------------------------
# Satisfy milestone 1, then REMOVE the spec. `all` must re-evaluate and fail at milestone 1 —
# if it short-circuited on the stored satisfied line it would report green over a broken tree.
reset_progress
gate 1 7 >/dev/null 2>&1
mv "$SPEC" "$WORK/held-spec.md"
out="$(gate all 7)"; rc=$?
if [ "$rc" -ne 0 ] && grep -q 'milestone-1' <<<"$out"; then
  pass "(g) an already-satisfied milestone is still re-evaluated by 'all' (no caching)"
else fail "(g) 'all' short-circuited on a stored satisfied line — rc=$rc: $out"; fi
mv "$WORK/held-spec.md" "$SPEC"

# ---- (h) D-44: consumer posture — absent policy scripts are a SKIP NOTICE, not a pass -----
reset_progress
out="$(gate 2 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qi 'SKIPPED' <<<"$out"; then
  pass "(h) milestone-2 prints a skip notice when the policy scripts are absent (consumer repo)"
else fail "(h) expected a skip notice, got rc=$rc: $out"; fi

# ---- (i) milestone 3 on a zero-lane, opted-out tree ---------------------------------------
# The shared $CFG configures zero fixed keys and no extraLanes, so it depends on its own
# "commands.acme.allowUnverified": true (added for #392, below) to reach milestone 3's green
# gate at all — the cases in this block are about the dead `build` key and the absent
# extraLanes token, neither of which is about the zero-lane guard itself.
#
# #580 DELETED the case that used to open this block: "(i) D-18: mutation sweep absent is a
# printed skip". Milestone 3 no longer invokes tools/mutation-sweep.sh under any condition, so
# there is no skip notice to assert — and an assertion kept here would be asserting a deleted
# behaviour. The green run below is still what the rest of the block reads.
reset_progress
out="$(gate 3 7)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(i) milestone-3 is green on a zero-lane, allowUnverified-opted-out tree"
else fail "(i) expected a green milestone-3, got rc=$rc: $out"; fi

# #580 AC-1, the negative half: neither D-18 line reaches stdout, on a tree that carries NO
# tools/mutation-sweep.sh. A positive-carrying tree is covered by (i-580b) further down — the
# absent branch and the present branch were the two arms of the deleted `if`, so proving only
# one of them would leave the other free to come back.
m580a="$(scrub_fixture_paths "$out")"
if ! grep -qi 'mutation' <<<"$m580a"; then
  pass "(i-580a) AC-1: no mutation-sweep line is emitted when the tree carries no sweep"
else fail "(i-580a) expected no mutation line at all, got: $(grep -i mutation <<<"$m580a")"; fi

# #392 AC-1 (second half): the same green run also carries the allowUnverified notice, since
# the shared fixture has zero fixed keys and no extraLanes.
if grep -q 'allowUnverified opt-out is set' <<<"$out"; then
  pass "(i-392) the allowUnverified opt-out notice is printed on this zero-lane, opted-out run"
else fail "(i-392) expected the allowUnverified opt-out notice, got: $out"; fi

# ...and the same run's AUDIT RECORD, asserted on $PROG rather than $out. The notice on stdout
# evaporates with the shell; the progress line is what says, at reconcile time, that a lean run
# reported green having verified nothing. A grep of $out cannot fail when the sibling
# `append_line` is deleted, so the printed half is no oracle for the recorded half.
if grep -qF 'milestone-3 | skipped | no verifying lane configured — allowUnverified opt-out' "$PROG"; then
  pass "(i-392b) the opt-out is RECORDED in the progress file, not merely printed"
else fail "(i-392b) no opt-out record in $PROG: $(cat "$PROG" 2>/dev/null)"; fi

# AC-10: `build` is gone from the fixed-key loop — the shared $CFG never declares it (same
# as before this change), so the ONLY thing that moved is whether the dead key still prints.
if ! grep -q 'build is null' <<<"$out"; then
  pass "(i-AC10) the dead 'build' key no longer appears in milestone-3 output"
else fail "(i-AC10) 'build is null' still printed — the dead key was not removed"; fi

# AC-5: no extraLanes key in $CFG — the same run must carry no 'extra lane' token, and the
# rest of this suite's shared-$TREE milestone-3 cases (this one included) stay green
# unmodified, proving the change is additive.
if ! grep -q 'extra lane' <<<"$out"; then
  pass "(i-AC5) no extraLanes key -> no 'extra lane' token in milestone-3 output"
else fail "(i-AC5) an 'extra lane' token appeared with no extraLanes configured"; fi

# ---- (i-580b) #580 AC-1: a tree that CARRIES a sweep does not get one run ------------------
# The arm that matters. (i-580a) proves the absent branch stays quiet; this proves the PRESENT
# branch — the one the deleted `if [ -f "$sweep" ]` actually took in this repo — is gone too.
# Asserting only the quiet side would leave `[ -f ... ] && run it` free to come back and still
# pass every case above.
#
# The planted sweep is a TRIPWIRE, not a stub: it writes a marker and exits 0, so a gate that
# still invoked it would go GREEN and the only evidence would be the marker. That is deliberate
# — an exit-1 tripwire would be caught by the rc assertion alone, which is a weaker claim (it
# proves the sweep did not FAIL, not that it did not RUN).
M580_TREE="$WORK/m580-tree"
mkdir -p "$M580_TREE/docs/plans" "$M580_TREE/tools"
git -C "$M580_TREE" init -q
git -C "$M580_TREE" config user.email t@example.invalid
git -C "$M580_TREE" config user.name t
printf '.claude/\n' > "$M580_TREE/.gitignore"
printf '# spec\n\n- AC-1: the thing\n' > "$M580_TREE/docs/plans/acme-7-lean.md"
M580_MARK="$WORK/m580-sweep-ran"
cat > "$M580_TREE/tools/mutation-sweep.sh" <<M580EOF
#!/usr/bin/env bash
printf 'invoked %s\n' "\$*" >> "$M580_MARK"
exit 0
M580EOF
chmod +x "$M580_TREE/tools/mutation-sweep.sh"
git -C "$M580_TREE" add -A >/dev/null 2>&1
git -C "$M580_TREE" commit -q -m base >/dev/null 2>&1
git -C "$M580_TREE" update-ref refs/remotes/origin/main HEAD
M580_PROG="$WORK/m580-prog.md"
attest_at "$M580_TREE" "$CFG" "$M580_PROG" 7
out="$( cd "$M580_TREE" && ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
  SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$M580_PROG" \
  bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 ) )"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$M580_MARK" ] && ! grep -qi 'mutation' <<<"$(scrub_fixture_paths "$out")"; then
  pass "(i-580b) AC-1: milestone 3 never invokes a repo-carried tools/mutation-sweep.sh"
else fail "(i-580b) expected a green milestone-3 with the sweep untouched, got rc=$rc marker=$([ -e "$M580_MARK" ] && cat "$M580_MARK" || echo absent): $out"; fi

# ---- (i-580d) #663: the negative net does not match the FIXTURE'S OWN PATH ----------------
# The regression that cost lean-gate.sh its whole mutation coverage, pinned deterministically
# instead of being left to the one lane that produces the condition. The gate is handed a
# config whose PATH carries the word the two cases above grep for; before the scrub, both of
# them failed on exactly this and the suite exited 2 with the sweep unable to say why.
#
# The config is byte-identical to $CFG and every path in it is relative, so the ONLY thing this
# case varies is where the file sits — which is the whole claim.
M663_DIR="$WORK/mutation-sweep-work.probe/tmp.0"
mkdir -p "$M663_DIR"
cp "$CFG" "$M663_DIR/config.json"
reset_progress
out="$( cd "$TREE" && ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
  SECOND_SHIFT_CONFIG="$M663_DIR/config.json" LEAN_PROGRESS_FILE="$PROG" \
  bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 ) )"; rc=$?
m663="$(scrub_fixture_paths "$out")"
# The rc arm is asserted alongside: a scrub that emptied the output entirely would satisfy the
# grep and prove nothing, and a gate that stopped running would do the same.
if [ "$rc" -eq 0 ] && ! grep -qi 'mutation' <<<"$m663" && grep -q 'allowUnverified opt-out is set' <<<"$m663"; then
  pass "(i-580d) AC-1 survives a fixture path that itself contains the word — the net is over the gate's words, not its scratch dir"
else fail "(i-580d) rc=$rc, scrubbed output: $m663"; fi

# ...and the progress record carries no D-18 skip row either. The stdout half above cannot fail
# when only the sibling `append_line` comes back, which is the same asymmetry (i-392b) exists
# for: a reconcile-time reader sees the FILE, not the shell.
if ! grep -qF 'mutation-sweep.sh absent' "$M580_PROG" && ! grep -qF 'mutation-sweep.sh absent' "$PROG"; then
  pass "(i-580c) AC-1: no mutation-sweep row is written to the progress record"
else fail "(i-580c) a mutation-sweep row reached a progress record: $(grep -hF 'mutation-sweep.sh absent' "$M580_PROG" "$PROG" 2>/dev/null)"; fi

# ---- (iz) #392: milestone 3 must not report green having verified nothing -----------------
# Dedicated configs derived from $CFG, isolating the zero-lane guard from the opt-out the
# shared fixture now carries (added above so the rest of this file's milestone-3 cases, which
# are not about this guard, keep reaching the green gate).
CFG_NOOPT="$WORK/config-nooptout.json"
jq 'del(.commands.acme.allowUnverified)' "$CFG" > "$CFG_NOOPT"

# AC-1: zero verifying lanes configured, no opt-out -> milestone 3 reds naming the resolved
# host slug, the config path, and allowUnverified.
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOOPT" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "no verifying lane configured for 'acme'" <<<"$out" \
   && grep -qF "$CFG_NOOPT" <<<"$out" && grep -q 'allowUnverified' <<<"$out"; then
  pass "(iz1) AC-1: zero verifying lanes + no opt-out reds milestone 3, naming slug/config/allowUnverified"
else fail "(iz1) expected rc=1 naming acme/$CFG_NOOPT/allowUnverified, got $rc: $out"; fi

# ...and the red must be CHARGED to milestone 3. `fail_milestone`'s first argument picks the
# attempt/fix-budget counter the run spends and the milestone the operator is sent to fix;
# nothing asserted above varies with it — reason text, config path and the allowUnverified
# token are byte-identical under `fail_milestone 2`. The attempt record is where the number
# becomes observable.
if grep -qF '| milestone-3 | attempt | no verifying lane configured' "$PROG"; then
  pass "(iz1b) the red is charged to milestone 3's attempt counter, not a neighbor's"
else fail "(iz1b) no milestone-3 attempt record in $PROG: $(cat "$PROG" 2>/dev/null)"; fi

# AC-1: a config carrying NO commands table at all reds the same way, and names the same three
# things — the config path included, since "which file did you read?" is the whole question an
# operator has here. (Before #413 this case removed the config file entirely; a run with no
# config now refuses earlier, on the unresolvable branch namespace — asserted as (iz2b).)
CFG_NOCMDS="$WORK/config-nocommands.json"
jq 'del(.commands)' "$CFG" > "$CFG_NOCMDS"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOCMDS" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "no verifying lane configured for 'acme'" <<<"$out" \
   && grep -qF "$CFG_NOCMDS" <<<"$out" && grep -q 'allowUnverified' <<<"$out"; then
  pass "(iz2) AC-1: a config with no commands table also reds, naming slug/config/allowUnverified"
else fail "(iz2) expected rc=1 naming acme/$CFG_NOCMDS/allowUnverified, got $rc: $out"; fi

# ...and with NO config file at all the run stops before any milestone is evaluated. That is the
# #413 posture and it is deliberately EARLIER than the zero-lane red above: with no committed
# config there is no branch namespace, and the retired `claude/acme-` fallback made that
# invisible by writing a placeholder org slug into real branch names.
CFG_ABSENT="$WORK/no-such-config.json"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_ABSENT" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'refusing to guess' <<<"$out" \
   && ! grep -qF 'claude/acme-' <<<"$out"; then
  pass "(iz2b) no config file at all refuses on the unresolvable namespace, with no placeholder"
else fail "(iz2b) expected rc=2 refusing to guess, got $rc: $out"; fi

# AC-2: exactly one fixed key set to a real command -> guard inert, existing behavior
# unchanged (no mention of allowUnverified anywhere in the output).
CFG_ONEKEY="$WORK/config-onekey.json"
jq 'del(.commands.acme.allowUnverified) | .commands.acme.lint = "true"' "$CFG" > "$CFG_ONEKEY"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_ONEKEY" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'allowUnverified' <<<"$out"; then
  pass "(iz3) AC-2: one fixed key configured -> guard stays inert, no allowUnverified mention"
else fail "(iz3) expected rc=0 with no allowUnverified mention, got $rc: $out"; fi

# AC-3: the only verifying surface is a when-scoped extraLane, evaluated against a diff that
# matches nothing -> still green. Configured-but-skipped is not unverified, and no opt-out is
# needed. $TREE's HEAD has not moved past the fixture commit at this point in the suite, so
# origin/main..HEAD is empty and no `when` glob can match.
CFG_WHENONLY="$WORK/config-whenonly.json"
jq 'del(.commands.acme.allowUnverified)
    | .commands.acme.extraLanes = [{"name":"scoped","when":["docs/nope/**"],"commands":["true"],"failureClass":"TEST_FAILURE"}]' \
  "$CFG" > "$CFG_WHENONLY"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_WHENONLY" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'scoped' — skipped" <<<"$out" \
   && ! grep -q 'allowUnverified' <<<"$out"; then
  pass "(iz4) AC-3: a when-scoped extraLane skipped on this diff is still 'configured' -> green"
else fail "(iz4) expected rc=0, when-skip notice, no allowUnverified mention; got $rc: $out"; fi

# ---- (i2) extraLanes (#379) ---------------------------------------------------------------
# A dedicated fixture tree, config, and issue file per case group — NOT the shared $TREE/$CFG
# above. Two reasons: (1) several cases here need a REAL, non-empty diff from origin/main
# (AC-3's own testing note: the shared $TREE pins origin/main to HEAD by construction, making
# its diff empty — a broken `when` implementation would pass both the match and the skip case
# against it), and (2) isolation keeps every later milestone-4/5 case in this file — which
# reads $TREE's patch identity — untouched by a commit this section adds for its own purposes.
EL_CFG_N=0
el_cfg() { # el_cfg <extraLanes-json> — writes a config.json with that extraLanes array spliced
           # into the shared $CFG's commands.acme, returns its path.
  EL_CFG_N=$((EL_CFG_N + 1))
  local out="$WORK/el-cfg-$EL_CFG_N.json"
  jq --argjson el "$1" '.commands.acme.extraLanes = $el' "$CFG" > "$out" 2>/dev/null
  printf '%s' "$out"
}
EL_ISSUE="$WORK/el-issue.json"
printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$EL_ISSUE"
el_count_in() { # el_count_in <token> <progress-file> — the safe count idiom (never `grep -c
                # ... || echo 0`: on zero matches grep prints "0" AND exits 1, doubling up).
  local n
  n="$(grep -cF "$1" "$2" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

EL_TREE="$WORK/el-tree"
mkdir -p "$EL_TREE"
git -C "$EL_TREE" init -q
git -C "$EL_TREE" config user.email t@example.invalid
git -C "$EL_TREE" config user.name t
printf '.claude/\n' > "$EL_TREE/.gitignore"
printf 'seed\n' > "$EL_TREE/README.md"
git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture base" >/dev/null 2>&1
git -C "$EL_TREE" update-ref refs/remotes/origin/main HEAD
# Advance past origin/main with a REAL, non-empty diff that matches nothing a `docs/**/*.md`
# `when` would select — AC-3's negative case, proven against non-empty rather than inert.
mkdir -p "$EL_TREE/src" "$EL_TREE/nomatch"
printf 'x\n' > "$EL_TREE/src/App.tsx"
printf 'y\n' > "$EL_TREE/nomatch/file.txt"
git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture change" >/dev/null 2>&1

gate_el() { # gate_el <config-file> <progress-file> <args...>
  local cfg="$1" prog="$2"; shift 2
  # Each (i*) case gets its own progress file, so each needs its own entry attestation before
  # the build-role precondition will let milestone 3 run at all. Idempotent, and none of these
  # cases is ABOUT the row — that is (p*)'s job.
  attest_at "$EL_TREE" "$cfg" "$prog" 7
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
    bash "$GATE" --issue-file "$EL_ISSUE" "$@" 2>&1 )
}

# AC-1: no `when` = always run; a passing lane's command is printed and milestone-3 passes.
cfg="$(el_cfg '[{"name":"ok-lane","commands":["echo hi"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-ok.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'ok-lane' » echo hi" <<<"$out"; then
  pass "(i2) AC-1: an extraLane with no 'when' always runs"
else fail "(i2) expected rc=0 and the lane's command printed, got rc=$rc: $out"; fi

# AC-1, as #642 left it: a failing lane REPORTS, naming BOTH the lane and the failing command,
# and milestone 3 continues. `mutation-sweep-pr` and `lint-and-selftests` re-run what extraLanes
# carry at the merge boundary, so refusing here bought when, not whether.
cfg="$(el_cfg '[{"name":"boom","commands":["exit 7"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-boom.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'boom' failed (rc=7): exit 7" <<<"$out" \
   && grep -q 'ADVISORY' <<<"$out"; then
  pass "(i3) #642 AC-4: a failing extraLane reports and does not refuse, naming the lane and the command"
else fail "(i3) expected rc=0 with an advisory naming lane+command, got rc=$rc: $out"; fi
# The DURABLE half, and the one that matters to a reviewer and to the retro corpus: the red left a
# record, on a verb no counter in the gate greps. Without this, "advisory" would be indistinguishable
# from "silently swallowed".
if [ "$(el_count_in "| milestone-3 | advisory | extra lane 'boom' failed (rc=7)" "$prog")" -eq 1 ] \
   && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ] \
   && [ "$(el_count_in '| milestone-3 | satisfied' "$prog")" -eq 1 ]; then
  pass "(i3b) #642 AC-4: the advisory red is RECORDED, charges no fix attempt, and the milestone still concludes satisfied"
else fail "(i3b) expected 1 advisory / 0 attempts / 1 satisfied, got $(el_count_in '| milestone-3 | advisory |' "$prog") / $(el_count_in '| milestone-3 | attempt |' "$prog") / $(el_count_in '| milestone-3 | satisfied' "$prog"): $(cat "$prog" 2>/dev/null)"; fi

# AC-2: commands[] run sequentially and stop at the FIRST non-zero — "echo three" must never
# run, and the failure names the second command, not the third.
cfg="$(el_cfg '[{"name":"multi","commands":["echo one","exit 5","echo three"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-multi.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "» echo one" <<<"$out" \
   && ! grep -qF "» echo three" <<<"$out" \
   && grep -qF "failed (rc=5): exit 5" <<<"$out"; then
  pass "(i4) AC-2: a multi-command lane stops at the first non-zero command (#642: it reports rather than refuses, and the lane still stops)"
else fail "(i4) expected sequential run stopping at 'exit 5', got rc=$rc: $out"; fi

# AC-3: a non-matching `when`, against the REAL non-empty diff above (src/App.tsx,
# nomatch/file.txt — neither is under docs/), skips with the pinned progress-file line.
cfg="$(el_cfg '[{"name":"scoped","when":["docs/**/*.md"],"commands":["echo should-not-run"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-scoped.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'scoped' — skipped" <<<"$out" \
   && ! grep -q 'should-not-run' <<<"$out"; then
  pass "(i5) AC-3: a non-matching 'when' against a non-empty diff prints a skip"
else fail "(i5) expected a printed skip and no command run, got rc=$rc: $out"; fi
if [ "$(el_count_in "milestone-3 | skipped | extra lane 'scoped' — no changed path matches when[]" "$prog")" -ge 1 ]; then
  pass "(i6) AC-3: the pinned skip progress-file line is written"
else fail "(i6) expected the pinned skip line in $prog, got: $(cat "$prog" 2>/dev/null)"; fi

# AC-6: ordering is fixed keys -> extraLanes (declaration order) -> milestone-3's verdict,
# fail-fast.
#
# RE-STATED for #580, not weakened. The third term used to be the mutation sweep's skip notice;
# that lane is deleted, so the ordering anchors on milestone 3's own terminal pass line instead.
# Three ordered observables either way — and the new final term is strictly harder to satisfy
# accidentally than the old one, because an extraLane that migrated AFTER the verdict could not
# be reported at all, whereas one that migrated after a skip notice still was.
cfg="$(el_cfg '[{"name":"ord-lane","commands":["echo mid"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-ord.md"
out="$(gate_el "$cfg" "$prog" 3 7)"
lint_at="$(printf '%s\n' "$out" | grep -n 'lint is null' | head -1 | cut -d: -f1)"
lane_at="$(printf '%s\n' "$out" | grep -n "extra lane 'ord-lane'" | head -1 | cut -d: -f1)"
done_at="$(printf '%s\n' "$out" | grep -n 'milestone-3: green gate' | head -1 | cut -d: -f1)"
if [ -n "${lint_at:-}" ] && [ -n "${lane_at:-}" ] && [ -n "${done_at:-}" ] \
   && [ "$lint_at" -lt "$lane_at" ] && [ "$lane_at" -lt "$done_at" ]; then
  pass "(i7) AC-6: observable ordering is fixed keys -> extraLanes -> milestone-3 verdict"
else fail "(i7) expected lint < extraLane < verdict ordering, got lint=$lint_at lane=$lane_at verdict=$done_at"; fi

# AC-7: malformed entries red milestone 3 naming the entry INDEX — three shapes.
cfg="$(el_cfg '["oops"]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad1.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "extraLanes[0]: must be an object" <<<"$out"; then
  pass "(i8) AC-7: a non-object extraLanes entry reds milestone 3 naming the index"
else fail "(i8) expected the non-object shape error, got rc=$rc: $out"; fi

cfg="$(el_cfg '[{"commands":["echo hi"],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad2.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "extraLanes[0]: missing 'name'" <<<"$out"; then
  pass "(i9) AC-7: an entry missing 'name' reds milestone 3 naming the index"
else fail "(i9) expected the missing-name error, got rc=$rc: $out"; fi

cfg="$(el_cfg '[{"name":"x","commands":[],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad3.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "extraLanes[0] ('x'): 'commands' must be a non-empty array" <<<"$out"; then
  pass "(i10) AC-7: an entry with empty 'commands' reds milestone 3 naming the index"
else fail "(i10) expected the empty-commands error, got rc=$rc: $out"; fi

# AC-8: an unresolvable origin/<baseBranch> reds milestone 3 FAIL-CLOSED when a when-scoped
# lane exists, rather than reading the unresolvable base as an empty (and thus matchless) diff.
EL_TREE_NB="$WORK/el-tree-noorigin"
mkdir -p "$EL_TREE_NB"
git -C "$EL_TREE_NB" init -q
git -C "$EL_TREE_NB" config user.email t@example.invalid
git -C "$EL_TREE_NB" config user.name t
printf '.claude/\n' > "$EL_TREE_NB/.gitignore"
printf 'seed\n' > "$EL_TREE_NB/README.md"
git -C "$EL_TREE_NB" add -A >/dev/null 2>&1 && git -C "$EL_TREE_NB" commit -q -m base >/dev/null 2>&1
# Deliberately NO `update-ref refs/remotes/origin/main` — the base is unresolvable.
cfg="$(el_cfg '[{"name":"scoped","when":["src/**/*.tsx"],"commands":["echo hi"],"failureClass":"TEST_FAILURE"}]')"
attest_at "$EL_TREE_NB" "$cfg" "$WORK/el-prog-nb.md" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE_NB" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$WORK/el-prog-nb.md" \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "cannot resolve origin/main to evaluate 'when'" <<<"$out"; then
  pass "(i11) AC-8: an unresolvable base reds milestone 3 fail-closed (not a silent skip)"
else fail "(i11) expected a fail-closed refusal, got rc=$rc: $out"; fi

# AC-9: milestone-3 lane children run with the pipeline's seam vars stripped — proven on a
# FIXED key, a lanes[] entry, and an extraLane, the three independent call sites this diff
# touches. Assertions are LINE-ANCHORED (^SCRUBBED$ / ^LEAKED$): the lane command's own text
# is echoed as an announcement ("» ... || echo LEAKED") before it runs, so an unanchored grep
# for LEAKED would false-positive on the announcement line itself even when the executed
# result is clean.
cfg="$WORK/el-cfg-scrub-fixed.json"
jq '.commands.acme.lint = "[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED || echo LEAKED"' "$CFG" > "$cfg" 2>/dev/null
out="$(gate_el "$cfg" "$WORK/el-prog-scrub-fixed.md" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'SCRUBBED' <<<"$out" && ! grep -qx 'LEAKED' <<<"$out"; then
  pass "(i12) AC-9: the fixed-key lane child runs with SECOND_SHIFT_CONFIG stripped"
else fail "(i12) expected SCRUBBED with no LEAKED, got rc=$rc: $out"; fi

# lanes[] entries are {name, cwd?, commands[]} objects — the shape config-lint.sh enforces
# (its lanes[] arm: `name` required, unknown keys rejected) and the one the gate itself reads.
# This fixture previously wrote `{command: "..."}`, a shape no lint-clean config can hold, and
# so pinned the reader bug rather than the contract: `.command // .` fed the whole lane object
# to `bash -c`, which is a syntax error on every real config that declares a lane.
cfg="$WORK/el-cfg-scrub-lanes.json"
jq '.commands.acme.lanes = [{"name": "scrub", "commands": ["[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED || echo LEAKED"]}]' "$CFG" > "$cfg" 2>/dev/null
out="$(gate_el "$cfg" "$WORK/el-prog-scrub-lanes.md" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'SCRUBBED' <<<"$out" && ! grep -qx 'LEAKED' <<<"$out"; then
  pass "(i12b) AC-9: a lanes[] lane child runs with SECOND_SHIFT_CONFIG stripped"
else fail "(i12b) expected SCRUBBED with no LEAKED, got rc=$rc: $out"; fi

# A lane carrying no commands is lint-CLEAN (config-lint requires non-empty only when the key is
# present), so nothing upstream stops it — and a zero-iteration inner loop would skip it in
# silence on the way to a green milestone 3. It must fail loudly instead.
cfg="$WORK/el-cfg-lane-nocmds.json"
jq '.commands.acme.lanes = [{"name": "empty"}]' "$CFG" > "$cfg" 2>/dev/null
out="$(gate_el "$cfg" "$WORK/el-prog-lane-nocmds.md" 3 7)"; rc=$?
if [ "$rc" -ne 0 ] && grep -q "non-empty array" <<<"$out"; then
  pass "(i12c) a commands-less lanes[] entry reds milestone 3 instead of being silently skipped"
else fail "(i12c) expected a loud failure, got rc=$rc: $out"; fi

# shellcheck disable=SC2016  # deliberate: the ${SECOND_SHIFT_CONFIG:-} must reach the child
# bash -c unexpanded, to be evaluated THERE (inside the scrubbed env), not by this shell.
cfg="$(el_cfg '[{"name":"scrub-check","commands":["[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED || echo LEAKED"],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-scrub-extra.md" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'SCRUBBED' <<<"$out" && ! grep -qx 'LEAKED' <<<"$out"; then
  pass "(i13) AC-9: an extraLanes child runs with SECOND_SHIFT_CONFIG stripped"
else fail "(i13) expected SCRUBBED with no LEAKED, got rc=$rc: $out"; fi

# AC-4: the bash-pattern dialect — `src/**/*.tsx` does NOT match a top-level `src/App.tsx`
# (no `when` in this diff DOES match, so the lane is expected to SKIP).
EL_TREE_TOP="$WORK/el-tree-top"
mkdir -p "$EL_TREE_TOP/src"
git -C "$EL_TREE_TOP" init -q
git -C "$EL_TREE_TOP" config user.email t@example.invalid
git -C "$EL_TREE_TOP" config user.name t
printf '.claude/\n' > "$EL_TREE_TOP/.gitignore"
printf 'seed\n' > "$EL_TREE_TOP/README.md"
git -C "$EL_TREE_TOP" add -A >/dev/null 2>&1 && git -C "$EL_TREE_TOP" commit -q -m base >/dev/null 2>&1
git -C "$EL_TREE_TOP" update-ref refs/remotes/origin/main HEAD
printf 'x\n' > "$EL_TREE_TOP/src/App.tsx"
git -C "$EL_TREE_TOP" add -A >/dev/null 2>&1 && git -C "$EL_TREE_TOP" commit -q -m "top-level tsx" >/dev/null 2>&1
cfg="$(el_cfg '[{"name":"tsx-lane","when":["src/**/*.tsx"],"commands":["echo should-not-run"],"failureClass":"TEST_FAILURE"}]')"
attest_at "$EL_TREE_TOP" "$cfg" "$WORK/el-prog-top.md" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE_TOP" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$WORK/el-prog-top.md" \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'tsx-lane' — skipped" <<<"$out" \
   && ! grep -q 'should-not-run' <<<"$out"; then
  pass "(i14) AC-4: 'src/**/*.tsx' does NOT match a top-level 'src/App.tsx'"
else fail "(i14) expected a skip against a top-level-only tsx change, got rc=$rc: $out"; fi

# AC-4 / AC-1: the same dialect DOES match a nested 'src/a/App.tsx' — the lane runs.
EL_TREE_NEST="$WORK/el-tree-nest"
mkdir -p "$EL_TREE_NEST/src/a"
git -C "$EL_TREE_NEST" init -q
git -C "$EL_TREE_NEST" config user.email t@example.invalid
git -C "$EL_TREE_NEST" config user.name t
printf '.claude/\n' > "$EL_TREE_NEST/.gitignore"
printf 'seed\n' > "$EL_TREE_NEST/README.md"
git -C "$EL_TREE_NEST" add -A >/dev/null 2>&1 && git -C "$EL_TREE_NEST" commit -q -m base >/dev/null 2>&1
git -C "$EL_TREE_NEST" update-ref refs/remotes/origin/main HEAD
printf 'y\n' > "$EL_TREE_NEST/src/a/App.tsx"
git -C "$EL_TREE_NEST" add -A >/dev/null 2>&1 && git -C "$EL_TREE_NEST" commit -q -m "nested tsx" >/dev/null 2>&1
cfg="$(el_cfg '[{"name":"tsx-lane","when":["src/**/*.tsx"],"commands":["echo did-run"],"failureClass":"TEST_FAILURE"}]')"
attest_at "$EL_TREE_NEST" "$cfg" "$WORK/el-prog-nest.md" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE_NEST" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$WORK/el-prog-nest.md" \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "extra lane 'tsx-lane' » echo did-run" <<<"$out"; then
  pass "(i15) AC-4: 'src/**/*.tsx' DOES match a nested 'src/a/App.tsx'"
else fail "(i15) expected the lane to run against a nested tsx change, got rc=$rc: $out"; fi

# ---- (ic) #527: A VERIFY LANE'S RESERVED INFRASTRUCTURE CODE ------------------------------
# Exit 3 from a verify lane means "I failed for reasons that are not this branch". Milestone 3
# must red with 7 — nothing was evaluated — and charge NO fix attempt, or a run whose sweep was
# killed arrives at its first REAL milestone-3 fix with the budget already spent.
#
# Driven through the EL fixture because it is the one with a real non-empty diff and its own
# progress file per case; the ASSERTIONS are on the gate's exit code and on the progress record,
# never on the lane's own output.
#
# #642 MOVED EVERY CASE HERE FROM `test` TO `typecheck`. `lint`, `test` and extraLanes no longer
# refuse at all, so the reserved code cannot mean anything on them — an advisory lane's exit code
# is recorded, not classified. `typecheck` is the one verify key still blocking, so it is where the
# contract still has a reader, and (ic4) below pins the OTHER half of that split: a demoted lane
# exiting the reserved 3 is advisory like any other red.
ic_cfg() { # ic_cfg <jq-filter> — the shared config with that filter applied
  EL_CFG_N=$((EL_CFG_N + 1))
  local out="$WORK/ic-cfg-$EL_CFG_N.json"
  jq "$1" "$CFG" > "$out" 2>/dev/null
  printf '%s' "$out"
}

# AC-2/AC-3, the FIXED KEYS — which is the path a repo-carried sweep takes, since
# `commands[repo].test` is its only call site.
cfg="$(ic_cfg '.commands.acme.typecheck = "exit 3"')"
prog="$WORK/ic-prog-fixed.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 7 ] && grep -q 'INFRASTRUCTURE' <<<"$out" \
   && grep -qF 'typecheck failed (rc=3)' <<<"$out"; then
  pass "(ic1) AC-2: a fixed key exiting the reserved 3 reds milestone 3 with 7, named as infrastructure"
else fail "(ic1) expected rc=7 naming infrastructure, got rc=$rc: $out"; fi
if [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ]; then
  pass "(ic2) AC-3: the infra red appends NO attempt row — no fix budget was charged"
else fail "(ic2) an infra red charged a fix attempt: $(cat "$prog" 2>/dev/null)"; fi

# THE CONTROL, and (ic1)/(ic2) are vacuous without it: an ordinary red must still be rc=1 and
# must still charge. Same lane, same call, one digit different.
cfg="$(ic_cfg '.commands.acme.typecheck = "exit 1"')"
prog="$WORK/ic-prog-ordinary.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 1 ] \
   && ! grep -q 'INFRASTRUCTURE' <<<"$out"; then
  pass "(ic3) control: a lane failing with any other code is still rc=1 and still charges one attempt"
else fail "(ic3) expected rc=1 with one attempt row, got rc=$rc / $(el_count_in '| milestone-3 | attempt |' "$prog") attempt(s): $out"; fi

# #642: THE OTHER HALF OF THE SPLIT. D-1's uniformity claim — the reserved code means the same
# thing on the fixed keys and on the additive lanes — held while both refused. extraLanes are
# advisory now, so the reserved code has no reader there: an exit 3 records like any other lane
# red and the milestone concludes. Asserting the new truth is what stops the old case from being
# re-added on the strength of a comment nobody re-read.
cfg="$(ic_cfg '.commands.acme.extraLanes = [{"name":"flaky","commands":["exit 3"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/ic-prog-extra.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'INFRASTRUCTURE' <<<"$out" \
   && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ] \
   && [ "$(el_count_in "| milestone-3 | advisory | extra lane 'flaky' failed (rc=3)" "$prog")" -eq 1 ]; then
  pass "(ic4) #642: an extraLane exiting the reserved 3 is ADVISORY — the lane no longer refuses, so nothing is classified"
else fail "(ic4) expected rc=0 with an advisory row and no infra classification, got rc=$rc: $out"; fi

# AC-3, the claim that actually matters at run time: repeated infra reds never exhaust the fix
# budget. Four calls is one past FIX_BUDGET — the count at which an ordinary red hard-stops with
# rc=4 — so a class that leaked into the counter would show up here as a 4 rather than a 7.
cfg="$(ic_cfg '.commands.acme.typecheck = "exit 3"')"
prog="$WORK/ic-prog-repeat.md"
gate_el "$cfg" "$prog" 3 7 >/dev/null 2>&1
gate_el "$cfg" "$prog" 3 7 >/dev/null 2>&1
gate_el "$cfg" "$prog" 3 7 >/dev/null 2>&1
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ] \
   && [ "$(el_count_in 'budget-exhausted' "$prog")" -eq 0 ]; then
  pass "(ic5) AC-3: four consecutive infra reds still return 7 — the fix budget is never touched"
else fail "(ic5) expected a fourth rc=7 with no attempt and no exhaustion, got rc=$rc: $(cat "$prog" 2>/dev/null)"; fi

# AC-3 THROUGH THE OBSERVE SEAM, on the one state where the two rules collide. Budget exhaustion
# normally outranks the class; an infra red inverts that, because it spends nothing and never can,
# so answering 4 would report "out of attempts" about a call that takes none. The fix budget is
# genuinely spent here — three real reds through the real writer — and the infra answer must still
# be 7, with the ordinary class right beside it still answering 4.
#
# NAMED CONFIGS, not `ic_cfg`: that helper runs in a command substitution, so its counter
# increments in a subshell and every call writes the SAME path. Harmless where one config is used
# before the next is built — every case above — and wrong here, where two must be live at once.
IC8_ORD="$WORK/ic8-ordinary.json"; jq '.commands.acme.typecheck = "exit 1"' "$CFG" > "$IC8_ORD"
IC8_INF="$WORK/ic8-infra.json";    jq '.commands.acme.typecheck = "exit 3"' "$CFG" > "$IC8_INF"
prog="$WORK/ic-prog-spent.md"
gate_el "$IC8_ORD" "$prog" 3 7 >/dev/null 2>&1
gate_el "$IC8_ORD" "$prog" 3 7 >/dev/null 2>&1
gate_el "$IC8_ORD" "$prog" 3 7 >/dev/null 2>&1
ic_before="$(el_count_in '| milestone-3 |' "$prog")"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$IC8_INF" \
        LEAN_PROGRESS_FILE="$prog" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
out2="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$IC8_ORD" \
         LEAN_PROGRESS_FILE="$prog" LEAN_GATE_OBSERVE=1 \
         bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc2=$?
if [ "$rc" -eq 7 ] && [ "$rc2" -eq 4 ] \
   && [ "$(el_count_in '| milestone-3 |' "$prog")" -eq "$ic_before" ]; then
  pass "(ic8) AC-3: observe reports an infra red as 7 even on a spent budget, while an ordinary red there still predicts 4 — and records neither"
else fail "(ic8) expected infra=7 / ordinary=4 with an unmoved record, got $rc / $rc2 and $ic_before -> $(el_count_in '| milestone-3 |' "$prog"): $out$out2"; fi

# AC-1 ↔ AC-2 COMPOSED, and this is the case that makes the reserved code a contract rather than
# two files agreeing by coincidence. The writer (tools/run-selftests.sh) and the reader (this
# gate) share a NUMBER, not an anchorable block, so a LOCKSTEP group cannot hold them — see
# docs/testing.md, *Couplings considered and declined*. What holds them is this: the real runner, over
# a fixture tree whose every suite dies without a verdict, wired into `commands.acme.test` exactly
# as a consumer would wire it. A one-sided change of the number reds here.
#
# WHERE IT DOES NOT RUN, and why that is two different answers. This suite SHIPS inside the
# plugin, and install-topology-selftest.sh re-runs it from a staged cache with no git repo above
# it — a topology in which the repo's `tools/` genuinely does not exist. That is the boundary, not
# a defect, so it is a stated SKIP. Anywhere a git toplevel DOES resolve, a missing runner means
# the file moved and the coupling lost its only composed guard: that reds.
IC_RUNNER="$HERE/../../../../tools/run-selftests.sh"
if [ -f "$IC_RUNNER" ]; then
  IC_SWEEP="$WORK/ic-sweep-tree"
  mkdir -p "$IC_SWEEP"
  printf '#!/usr/bin/env bash\nexit 125\n' > "$IC_SWEEP/one-selftest.sh"
  printf '#!/usr/bin/env bash\nexit 125\n' > "$IC_SWEEP/two-selftest.sh"
  cfg="$(ic_cfg "$(printf '.commands.acme.typecheck = "bash %s --root %s --jobs 2"' "$IC_RUNNER" "$IC_SWEEP")")"
  prog="$WORK/ic-prog-composed.md"
  out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
  if [ "$rc" -eq 7 ] && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ]; then
    pass "(ic6) AC-1↔AC-2: the REAL sweep's all-infra exit reaches this gate as 7 and charges nothing"
  else fail "(ic6) the composed writer→reader path did not classify as infra, got rc=$rc: $out"; fi

  # The other polarity through the same wiring: one genuinely red suite and the run is a red
  # branch again — rc=1, one attempt charged. Without it (ic6) would pass against a runner that
  # returned 3 unconditionally.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$IC_SWEEP/two-selftest.sh"
  prog="$WORK/ic-prog-composed-mixed.md"
  out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
  if [ "$rc" -eq 1 ] && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 1 ]; then
    pass "(ic7) AC-1↔AC-2: one genuinely red suite in the same sweep is a branch failure again"
  else fail "(ic7) the composed path misclassified a mixed sweep, got rc=$rc: $out"; fi
elif ! git -C "$HERE" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "  SKIPPED: (ic6/ic7) staged install cache — tools/run-selftests.sh is repo-only, so the composed writer→reader case runs in the repo sweep and not here"
else
  fail "(ic6/ic7) tools/run-selftests.sh is not beside this gate in a git checkout — the reserved code's only composed guard did not run"
fi

# ---- (ad) #642 AC-4: the merge-boundary duplicates report, they do not refuse ---------------
# `lint` and `test` are re-run verbatim by `lint-and-selftests` at the merge boundary, so what
# refusing here bought was WHEN a failure is caught, not whether — at the price of a fix round
# inside the build session. They report now. `typecheck` is NOT demoted, and (ad3) is what keeps
# that from being a comment: the demotion's premise is measured CI duplication, and typecheck has
# none measured.
for ad_key in lint test; do
  cfg="$(ic_cfg ".commands.acme.$ad_key = \"exit 1\"")"
  prog="$WORK/ad-prog-$ad_key.md"
  out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -qF "$ad_key failed (rc=1)" <<<"$out" && grep -q 'ADVISORY' <<<"$out"; then
    pass "(ad1-$ad_key) #642 AC-4: a red '$ad_key' lane reports and milestone 3 still concludes zero"
  else fail "(ad1-$ad_key) expected rc=0 with an advisory, got rc=$rc: $out"; fi
  if [ "$(el_count_in "| milestone-3 | advisory | $ad_key failed (rc=1)" "$prog")" -eq 1 ] \
     && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 0 ] \
     && [ "$(el_count_in '| milestone-3 | satisfied' "$prog")" -eq 1 ]; then
    pass "(ad2-$ad_key) #642 AC-4: the red is RECORDED on the advisory verb, charges no fix attempt, and the milestone concludes satisfied"
  else fail "(ad2-$ad_key) expected 1 advisory / 0 attempts / 1 satisfied for $ad_key, got: $(cat "$prog" 2>/dev/null)"; fi
done

# THE CONTROL, and (ad1)/(ad2) are half-vacuous without it: `typecheck` still refuses, still
# charges, and still returns 1. One key different, same call.
cfg="$(ic_cfg '.commands.acme.typecheck = "exit 1"')"
prog="$WORK/ad-prog-typecheck.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'typecheck failed (rc=1)' <<<"$out" \
   && [ "$(el_count_in '| milestone-3 | attempt |' "$prog")" -eq 1 ] \
   && [ "$(el_count_in '| milestone-3 | advisory |' "$prog")" -eq 0 ]; then
  pass "(ad3) #642 AC-4: 'typecheck' is NOT demoted — it still refuses with 1 and still charges one attempt"
else fail "(ad3) expected rc=1 with one attempt and no advisory row, got rc=$rc: $out"; fi

# A DEMOTED LANE STILL RUNS. "Advisory" must not decay into "skipped": the lane's output is the
# operator's only live signal, and the record above is worth nothing if nothing was executed.
cfg="$(ic_cfg '.commands.acme.test = "echo ad-lane-really-ran; exit 1"')"
prog="$WORK/ad-prog-ran.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'ad-lane-really-ran' <<<"$out"; then
  pass "(ad4) #642 AC-4: a demoted lane is still EXECUTED — it reports its red, it is not skipped"
else fail "(ad4) the demoted lane did not run, rc=$rc: $out"; fi

# ...and the milestone still refuses on the m3 points #642 did NOT demote. `no-verify-lane` is the
# sharpest of them: demoting it would make milestone 3 green having verified nothing, which is the
# one failure the whole file exists to prevent.
# `allowUnverified` is cleared too — the shared fixture config sets it (it is what makes the (i)
# block's zero-lane tree green), and leaving it on would take the opt-out arm instead of the refusal.
cfg="$(ic_cfg '.commands.acme.lint = null | .commands.acme.typecheck = null | .commands.acme.test = null | .commands.acme.extraLanes = [] | del(.commands.acme.allowUnverified)')"
prog="$WORK/ad-prog-zero.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no verifying lane configured' <<<"$out"; then
  pass "(ad5) #642: m3/no-verify-lane still REFUSES — the demotion is scoped to the three named points, not to milestone 3"
else fail "(ad5) expected rc=1 on a zero-lane tree, got rc=$rc: $out"; fi

# ---- (ad6-ad8) #668: the terminal line states what reported red beside it ------------------
# The advisory row above is durable and the warn lines are live, but the ONE line an operator or
# the scheduler reads was `green gate` either way. Observed on PR 660: a real selftest failure rode
# an advisory lane under an rc=0 gate whose last line was an unqualified green.
cfg="$(ic_cfg '.commands.acme.test = "exit 1"')"
prog="$WORK/ad-prog-count1.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qFx '[lean-gate] ✓ milestone-3: green gate (1 advisory)' <<<"$out"; then
  pass "(ad6) #668 AC-1: one advisory lane — the terminal line carries the count"
else fail "(ad6) expected rc=0 and a counted terminal line, got rc=$rc: $out"; fi

# TWO, so (ad6) cannot pass against a hardcoded "(1 advisory)" suffix. `typecheck` stays null
# between them: it is the undemoted key, and a red there would refuse before the second count.
cfg="$(ic_cfg '.commands.acme.lint = "exit 1" | .commands.acme.test = "exit 1"')"
prog="$WORK/ad-prog-count2.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qFx '[lean-gate] ✓ milestone-3: green gate (2 advisory)' <<<"$out" \
   && [ "$(el_count_in '| milestone-3 | advisory |' "$prog")" -eq 2 ]; then
  pass "(ad7) #668 AC-1: the count tracks the advisory rows actually written, not a fixed suffix"
else fail "(ad7) expected rc=0, a '(2 advisory)' terminal line and 2 advisory rows, got rc=$rc: $out"; fi

# THE CONTROL, and AC-2's whole content: a clean run's terminal line must be BYTE-IDENTICAL to
# what every existing consumer already reads. `-x` is load-bearing — a substring match would pass
# against `green gate (0 advisory)`, which is exactly the leak this case exists to catch.
cfg="$(ic_cfg '.commands.acme.test = "true"')"
prog="$WORK/ad-prog-count0.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qFx '[lean-gate] ✓ milestone-3: green gate' <<<"$out" \
   && [ "$(el_count_in '| milestone-3 | advisory |' "$prog")" -eq 0 ]; then
  pass "(ad8) #668 AC-2: zero advisories leaves the terminal line unchanged, byte for byte"
else fail "(ad8) expected the unqualified terminal line on a clean run, got rc=$rc: $out"; fi

# ---- (ib) #527 AC-4 / #566: the INTERRUPTED budget — one value, scoped per milestone -------
# Without this the fix is self-defeating. Once an infra kill stops charging a fix attempt the
# scheduler re-spawns, and each dead spawn leaves another unclosed `started` row that nothing
# decrements — so the run would loop here forever, on a milestone nothing judged.
#
# #527 D-7 gave milestone 3 a LARGER VALUE (8 against 5) because it alone ran DETACHED, and so
# was the only evaluation long enough for a turn boundary to kill. #566 deleted the detached
# runner and that asymmetry with it: (ib1) and (ib2) now answer the SAME COUNT the SAME way on
# milestone 1 and on milestone 3.
#
# What #566 did NOT retire is the SCOPING — the value is shared, the ledger is not, and unclosed
# rows still belong to the milestone that wrote them. (ib3) is what pins that half, because
# (ib1) and (ib2) each seed the milestone they then ask about and so cannot see a gate that
# counted unclosed rows repo-wide.
IB_TREE="$WORK/ib-tree"
mkdir -p "$IB_TREE/docs/plans"
git -C "$IB_TREE" init -q
git -C "$IB_TREE" config user.email t@example.invalid
git -C "$IB_TREE" config user.name t
printf '.claude/\n' > "$IB_TREE/.gitignore"
printf '# spec\n\nAC-1: something.\n' > "$IB_TREE/docs/plans/acme-7-lean.md"
git -C "$IB_TREE" add -A >/dev/null 2>&1 && git -C "$IB_TREE" commit -q -m "ib base" >/dev/null 2>&1
git -C "$IB_TREE" update-ref refs/remotes/origin/main HEAD

ib_seed() { # ib_seed <progress-file> <milestone> <n-unclosed>
  attest_at "$IB_TREE" "$CFG" "$1" 7
  local i
  for (( i=0; i<$3; i++ )); do
    echo "2026-01-01T00:00:00Z | milestone-$2 | started |" >> "$1"
  done
}
gate_ib() { # gate_ib <progress-file> <args...>
  local prog="$1"; shift
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$IB_TREE" && SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$prog" bash "$GATE" --issue-file "$EL_ISSUE" "$@" 2>&1 )
}

prog="$WORK/ib-prog-m1.md"; rm -f "$prog"; ib_seed "$prog" 1 5
out="$(gate_ib "$prog" 1 7)"; rc=$?
if [ "$rc" -eq 4 ] && grep -q 'interrupted-exhausted' "$prog" \
   && grep -q 'interrupted 5/5' <<<"$out"; then
  pass "(ib1) AC-4: milestone 1 exhausts at the 5-interruption bound, and reports it as 5/5"
else fail "(ib1) expected rc=4 at 5 unclosed on milestone 1, got rc=$rc: $out"; fi

# #566 RETIRED MILESTONE 3'S SEPARATE BOUND. This case asserted the inverse — that the SAME
# count which exhausts milestone 1 leaves milestone 3 running, on a separate bound of its own
# set to 8. #527 D-7 gave it that larger bound because milestone 3 ran DETACHED and was the only
# milestone long enough to be killed by a turn boundary, so re-spawns piled up unclosed rows
# faster than anywhere else. The evaluation is inline and turn-bounded now, so milestone 3 is
# exactly as exposed as the other four and takes the same 5 — which is what this asserts.
prog="$WORK/ib-prog-m3.md"; rm -f "$prog"; ib_seed "$prog" 3 5
out="$(gate_ib "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 4 ] && grep -q 'interrupted-exhausted' "$prog" \
   && grep -q 'interrupted 5/5' <<<"$out"; then
  pass "(ib2) #566: milestone 3 shares the generic 5-interruption bound — its own 8 retired with the detached runner"
else fail "(ib2) expected rc=4 at 5 unclosed on milestone 3's generic 5-bound, got rc=$rc: $out"; fi

# ...and the count is SCOPED to one milestone, which is the half of #527 AC-4 that #566 left
# standing. Retiring the separate value did not merge the ledgers: a run that infrastructure cut
# off five times at milestone 3 must still be able to re-enter milestone 1, or the bound stops
# being a per-milestone brake and becomes a per-run one. Seeded at milestone 3's own exhausting
# count and asked at milestone 1, so a gate that counted unclosed rows repo-wide would satisfy
# (ib1) and (ib2) and fail only here.
prog="$WORK/ib-prog-cross.md"; rm -f "$prog"; ib_seed "$prog" 3 5
out="$(gate_ib "$prog" 1 7)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'interrupted-exhausted' "$prog" \
   && ! grep -q 'never concluded' <<<"$out"; then
  pass "(ib3) #566: the bound is per-milestone in SCOPE — milestone 3's 5 unclosed rows neither exhaust milestone 1 nor are announced to it"
else fail "(ib3) expected rc=0, no exhaustion row and no interruption notice at milestone 1 with 5 unclosed milestone-3 rows, got rc=$rc: $out"; fi

# #718 DELETED THE (ir) BLOCK — `progress --infra`, the infra-death read. Six cases ((ir1)-(ir4),
# (ir9), (ir10)) stood here over their own fixture tree, pinning a token space whose only consumer
# was orchestrate-lean.sh's continuation loop. The RESIDUE they derived from is still pinned:
# (if5)/(if5b) below, and scenario-liveness-selftest.sh's (lean-inline-m3)/(lean-inline-m3-nv)
# over a real group-killed milestone 3.

# ---- (j) AC-6: milestone 4 blocks on anything but a committed verdict=approve -------------
# The fixture verdict is REVIEW-authored throughout: `r-review-1` / `sess-review-1` are the
# separate review session's identities. A build-authored one is case (n).
# Each call models a fresh review ROUND, so the round counter advances and the bytes differ.
# That is not cosmetic: milestone 4 reads the record's COMMIT, and an identical re-write stages
# nothing, so the record would keep the commit of an earlier round while the tree moved on —
# the case would then red on freshness rather than on what it is about.
#
# `reviewed_head` is resolved BEFORE the commit, which is the honest shape: the reviewer reads
# the current head, names it, and then commits the record on top of it. Resolving it after the
# commit would name the record's own commit and make every declared-freshness case vacuous.
# The patch identity a record must carry, computed by the PRODUCTION function through library
# mode — never by a copy of its formula here. A copy could not fail on a production edit, which
# is the mirror-harness shape docs/testing.md forbids; and #642 made this key mandatory at
# milestone 4, so every fixture record needs one that the gate itself will agree with.
# shellcheck disable=SC1090  # $GATE is the script under test; following it is the point.
fixture_patch_id() { # fixture_patch_id [head-ish]
  # Copied out BEFORE the `.`: sourcing consumes the sourcing scope's positional parameters.
  local fp_head="${1:-HEAD}"
  ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 \
    && REPO_ROOT="$TREE" BASE_BRANCH=main VERDICT_REL="docs/plans/acme-7-lean-verdict.md" \
       branch_patch_id "$fp_head" )
}

VROUND=0
write_review_verdict() { # write_review_verdict [verdict] [reviewed-head]
  VROUND=$((VROUND + 1))
  local head="${2:-$(git -C "$TREE" rev-parse HEAD)}"
  printf 'verdict=%s\nrun_id: r-review-1\nsession_id: sess-review-1\nrounds: %s\nreviewed_head: %s\nreviewed_patch_id: %s\n' \
    "${1:-approve}" "$VROUND" "$head" "$(fixture_patch_id "$head")" > "$VERDICT"
  commit_tree "review verdict ${1:-approve} (round $VROUND)"
}

reset_progress
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'no committed verdict record' <<<"$out"; then
  pass "(j1) milestone-4 fails with no committed verdict record"
else fail "(j1) expected rc=5, got $rc: $out"; fi

write_review_verdict needs-work
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'reads verdict=needs-work, not verdict=approve' <<<"$out"; then
  pass "(j2) milestone-4 fails on verdict=needs-work"
else fail "(j2) expected rc=1 on needs-work, got $rc: $out"; fi

# #720 deleted (j3)/(j3b) with the arms they pinned: the run_id and session_id key refusals were
# duplicates of lean-evidence.sh's arm_verdict, which every consumer's merge boundary runs.
# lean-evidence-selftest.sh pins that record class there.
reset_progress
write_review_verdict
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(j4) milestone-4 passes on a committed verdict=approve with distinct review identities"
else fail "(j4) expected rc=0, got $rc: $out"; fi

# ---- (u) #642: the pre-patch-id MIGRATION arm replaces the SHA-keyed fallback ---------------
# This block used to drive `m4/head-missing` and `m4/head-tree-diff`, the two arms milestone 4
# fell through to for a record carrying no `reviewed_patch_id`. #642 deleted both. They were not
# merely never-fired: cmd_verdict, the only writer, emits that key unconditionally and envfails
# rather than omit it, and lean-evidence.sh — which `pr-gates` runs on every consumer's PR —
# refuses a record without it outright. Whatever those arms answered, the boundary refused the PR.
#
# What is left is the pair of key requirements, and they are strictly tighter than the fallback
# they replace: absence of either is refused here now, in the same class the record's other
# missing keys carry.
reset_progress
printf 'verdict=approve\nrun_id: r-review-1\nsession_id: sess-review-1\n' > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'no reviewed_head key' <<<"$out"; then
  pass "(u1) milestone-4 fails an approve record carrying no reviewed_head key"
else fail "(u1) expected rc=5 on a head-less approve, got $rc: $out"; fi

# #720 deleted (u2) and its non-vacuity companion (u3): the reviewed_patch_id-absent refusal that
# #642 put here is the same one lean-evidence.sh's arm_freshness makes at the merge boundary
# ("declares no reviewed_patch_id"), pinned there by lean-evidence-selftest.sh (r). (u1) above
# stays because `reviewed_head`'s absence has NO counterpart downstream. What still pins that the
# real writer stamps the key is (x1), which reads it out of a writer-produced record.

# The two deleted arms are ABSENT, not merely unreached. A behavioral case cannot red on an arm
# that no longer exists, so the deletion itself is pinned here — the same completeness discipline
# (ac1) applies to the class mapping.
if ! grep -q 'is not a commit in this branch' "$GATE" \
   && ! grep -q 'differ between that commit and the current head' "$GATE"; then
  pass "(u4) #642: m4/head-missing and m4/head-tree-diff are gone from the gate, not just unreached"
else fail "(u4) the SHA-keyed fallback arms are still present in $GATE"; fi

# ---- (k) AC-7: milestone 5 exit artifacts, via the fixture seams --------------------------
cat > "$WORK/pr-draft.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": true,
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
EOF
cat > "$WORK/pr-ready.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false,
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
EOF
cat > "$WORK/pr-nospec.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false, "body": "Closes #7" }]
EOF
# Two bot PR markers, not one, and both are load-bearing (#359). cmd_5 calls cmd_mark last,
# and cmd_mark's no-op test keys on THIS run's id — so a fixture missing the id that resolves
# would send the case down the live `$GH_BOT` write path and abort the suite. The (k) block
# runs before (m2) seeds the run-id cache, so it resolves `unset`; the (q)/(r) `all` cases run
# after it and resolve `selftest-run-306`. Covering both keeps every M5 case a no-op, which is
# what these cases are actually about — the marker's own behavior is (pm1)-(pm5)'s subject.
cat > "$WORK/comments-closing.json" <<'EOF'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-7-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: unset -->\n<!-- stage: lean-pr-marker -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: selftest-run-306 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
echo '[]' > "$WORK/comments-none.json"

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-draft.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'still a draft' <<<"$out"; then
  pass "(k1) milestone-5 fails a draft PR (D-27 requires a ready PR)"
else fail "(k1) expected rc=1 on a draft PR, got $rc: $out"; fi

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-nospec.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not link the committed spec' <<<"$out"; then
  pass "(k2) milestone-5 fails a PR body that does not link the committed spec"
else fail "(k2) expected rc=1 on a spec-less body, got $rc: $out"; fi

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'references the verdict record' <<<"$out"; then
  pass "(k3) milestone-5 fails when no closing comment references the verdict record"
else fail "(k3) expected rc=1 on a missing closing comment, got $rc: $out"; fi
# #642 AC-3: the largest announcement class in milestone 5 (8 of the corpus's firings, every one
# adjudicated `unchanged`) records the ABSENT verb — the closing comment is the step the checklist
# orders NEXT, so refusing for its absence must not charge a fix attempt. Both halves asserted:
# a bare "attempt_count did not rise" passes vacuously if the path records nothing at all.
if [ "$(count_in_progress '| milestone-5 | absent |')" -ge 1 ] \
   && [ "$(count_in_progress '| milestone-5 | attempt |')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | unmet')" -eq 1 ]; then
  pass "(k3b) #642 AC-3: the missing closing comment records 'absent' and its obligation row, and charges no fix attempt"
else fail "(k3b) expected an absent row, 0 attempts and the unmet obligation, got $(count_in_progress '| milestone-5 | absent |') / $(count_in_progress '| milestone-5 | attempt |') / $(count_in_progress '| milestone-5 | obligation | verdict-reference | unmet'): $(cat "$PROG")"; fi

reset_progress
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'not current' <<<"$out"; then
  pass "(k4) milestone-5 fails when milestones 1-4 left no satisfied record"
else fail "(k4) expected rc=1 on a non-current progress file, got $rc: $out"; fi

# ...and that failure must be STABLE on re-run. This is the self-defeating-check class: a bare
# "does the progress file exist" assertion heals itself, because reporting the failure appends
# an attempt line and appending creates the file. Asserting the 1-4 records instead is stable —
# an M5 attempt line never satisfies M1-4.
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'not current' <<<"$out"; then
  pass "(k5) that failure is stable on re-run (the check does not heal itself)"
else fail "(k5) the progress-file check healed itself between runs — rc=$rc: $out"; fi
# #642 AC-3: ...and both of those calls recorded ABSENT, not an attempt. `m5/progress-current`
# fires because an EARLIER milestone has not happened yet, which is the announcement shape.
if [ "$(count_in_progress '| milestone-5 | absent |')" -eq 2 ] \
   && [ "$(count_in_progress '| milestone-5 | attempt |')" -eq 0 ]; then
  pass "(k5b) #642 AC-3: m5/progress-current records 'absent' on both calls and charges no fix attempt"
else fail "(k5b) expected 2 absent / 0 attempts, got $(count_in_progress '| milestone-5 | absent |') / $(count_in_progress '| milestone-5 | attempt |'): $(cat "$PROG")"; fi

# Realistic state: milestones 1-4 have run and left their records. `bgate`, not `gate`: this is
# the only (k) case that gets past every assertion to cmd_mark, which since #446 refuses a
# session outside the recorded build set. The failing cases above stop earlier and stay on the
# session-less helper.
seed_progress_1_to_4
out="$(bgate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(k6) milestone-5 passes with a ready PR, spec link, closing comment, and a progress file"
else fail "(k6) expected rc=0, got $rc: $out"; fi

# ---- (k7)-(k10) #642 AC-8: a MERGED PR satisfies the same obligation an open one does --------
# Requiring `open` made close-out permanently unreachable once an operator merged first —
# milestones 3 and 4 pass, 5 retries three times against a condition that cannot become true
# again, and the run's cost-log row is never written. The obligation is that the PR reached its
# terminal state carrying its exit artifacts, and merged is more terminal than open.
cat > "$WORK/pr-merged.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false, "state": "MERGED",
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
EOF
cat > "$WORK/pr-closed.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false, "state": "CLOSED",
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
EOF
# Milestone 5's own view of the same merged PR — it additionally asserts the body's Closes trailer and spec link.
cat > "$WORK/gh-merged-m5.sh" <<'STUB'
#!/bin/sh
# `--state open` answers an EMPTY array, which is what real gh returns once the PR is merged —
# so a revert of #670's resolver change fails here instead of quietly passing.
case "$*" in
  *"issue view"*) echo OPEN ;;
  *"pr list"*)
    case "$*" in
      *"--state open"*) echo '[]' ;;
      *) cat <<'JSON'
[{ "number": 91, "url": "https://example.invalid/pr/91", "isDraft": false, "state": "MERGED",
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
JSON
      ;;
    esac ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$WORK/gh-merged-m5.sh"
cat > "$WORK/pr-open-and-merged.json" <<'EOF'
[{ "number": 8, "url": "https://example.invalid/pr/8", "isDraft": false, "state": "MERGED",
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" },
 { "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false, "state": "OPEN",
   "body": "Closes #7\n\nSpec: docs/plans/acme-7-lean.md" }]
EOF
seed_progress_1_to_4
out="$(bgate 5 7 --pr-file "$WORK/pr-merged.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(k7) #642 AC-8: resolve_open_pr accepts a MERGED PR through the --pr-file seam"
else fail "(k7) expected rc=0 on a merged PR, got $rc: $out"; fi

# ---- (k7b) #670 AC-1: the same claim (k7) USED to make, over the path a consumer takes -------
# (k7) was titled "close-out stays reachable after a merge" and could not observe it: --pr-file
# short-circuits both resolvers, so cmd_5 passed while cmd_mark's own `--state open` list — which
# cmd_5 calls unconditionally — would have answered `[]` and blocked the milestone. This case
# takes the live path end to end and is the one that fails on a revert.
seed_progress_1_to_4
out="$( GH="$WORK/gh-merged-m5.sh" bgate 5 7 --comments-file "$WORK/comments-closing.json" )"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(k7b) #670 AC-1: milestone-5 passes on a MERGED PR over the LIVE gh path — close-out is actually reachable after a merge"
else fail "(k7b) expected rc=0 on the live merged path, got $rc: $out"; fi

# A CLOSED-unmerged PR is the shape of abandoned work. Certifying it would be a false public
# statement about the run, so it satisfies nothing — and the refusal is the ABSENT verb (AC-3).
seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-closed.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no open or merged PR found' <<<"$out"; then
  pass "(k8) #642 AC-8: a CLOSED-unmerged PR satisfies nothing — merged is accepted, abandoned is not"
else fail "(k8) expected rc=1 naming no open or merged PR, got $rc: $out"; fi
if [ "$(count_in_progress '| milestone-5 | absent |')" -ge 1 ] \
   && [ "$(count_in_progress '| milestone-5 | attempt |')" -eq 0 ]; then
  pass "(k9) #642 AC-3: the no-PR refusal records 'absent' and charges no fix attempt"
else fail "(k9) expected an absent row and no attempt, got $(count_in_progress '| milestone-5 | absent |') / $(count_in_progress '| milestone-5 | attempt |'): $(cat "$PROG")"; fi

# OPEN WINS when both exist: a re-cut PR on the same branch is the live one, and its body is what
# close-out patches. The merged row is FIRST in the fixture, so a reader that simply took `.[0]`
# would pick the wrong one.
seed_progress_1_to_4
out="$(bgate 5 7 --pr-file "$WORK/pr-open-and-merged.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'example.invalid/pr/9' <<<"$out" && ! grep -qF 'example.invalid/pr/8' <<<"$out"; then
  pass "(k10) #642 AC-8: with both an open and a merged PR on the branch, the OPEN one is resolved"
else fail "(k10) expected the open PR (#9) to win, got $rc: $out"; fi

# ---- (k11) #642 AC-3, round 1 B2: m5/identity-stamp, the sixth reason, driven ---------------
# The other five announcement reasons each had a behavioral case; this one had only the static
# site count, which greps call sites textually and can never observe what the routing DOES —
# that a failed identity stamp records `absent` and charges zero attempts.
#
# THE SEAM IS `gate`, NOT `bgate`. cmd_mark's #446 guard refuses any session outside the recorded
# build set, and `gate` runs with CLAUDE_CODE_SESSION_ID unset — which is why every other case
# that reaches cmd_mark uses `bgate`. Here reaching it and being refused IS the fixture.
#
# The comment fixture carries the closing comment and NO run marker, deliberately: cmd_mark's
# idempotent no-op sits BEFORE the session guard, so a trail carrying this run's marker would
# return 0 and the case would assert nothing. Every earlier milestone-5 obligation must pass, or
# the refusal under test is never reached — (k11a) asserts the reason text for exactly that.
cat > "$WORK/comments-closing-nomarker.json" <<'EOF'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-7-lean-verdict.md" }]
EOF
seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing-nomarker.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'could not stamp the build identity' <<<"$out"; then
  pass "(k11a) milestone-5 refuses when the build identity could not be stamped on the PR"
else fail "(k11a) expected rc=1 naming the identity stamp, got $rc: $out"; fi
# BOTH halves, for (c3)'s reason: "attempt_count did not rise" passes vacuously on a path that
# recorded nothing at all. The verdict-reference obligation must read `met` — that is what proves
# the run got PAST the closing-comment check and the refusal under test is m5/identity-stamp.
if [ "$(count_in_progress '| milestone-5 | absent |')" -ge 1 ] \
   && [ "$(count_in_progress '| milestone-5 | attempt |')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | met')" -eq 1 ]; then
  pass "(k11) #642 AC-3: a failed identity stamp records 'absent' past both met obligations, and charges no fix attempt"
else fail "(k11) expected an absent row, 0 attempts and a met verdict-reference, got $(count_in_progress '| milestone-5 | absent |') / $(count_in_progress '| milestone-5 | attempt |') / $(count_in_progress '| milestone-5 | obligation | verdict-reference | met'): $(cat "$PROG")"; fi

# ---- (ob) #531 D-10: milestone 5 reports its two obligations SEPARATELY -------------------
# THE DEFECT. `orchestrate-lean.sh` could only say "the closing comment, the exit artifacts and
# the worktree teardown are all unaccounted for", because a milestone-5 red left one `attempt`
# line and nothing else — so every recovery started with a human reading the record. What is
# asserted here is the record's shape; the scheduler's use of it is its own suite's.
#
# THE VERB IS THE WHOLE CONTRACT (D-10). progress_token narrows to a milestone by the FIXED
# SUBSTRING `| milestone-n | satisfied`, so an obligation row spelled with that verb would move
# the scheduler's close-out token the instant the FIRST obligation held — printing `done` over a
# run with no closing comment on it, which is the false `done` the taxonomy exists to remove.
# (ob3) is that assertion, driven on the REAL rows rather than on the verb's spelling.
seed_progress_1_to_4
ob_tok_before="$(gate progress 7 --satisfied 5)"
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | exit-artifacts | met')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | unmet')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | satisfied')" -eq 0 ]; then
  pass "(ob1) a PARTIALLY finished close-out records each obligation's own state and withholds the aggregate"
else fail "(ob1) rc=$rc, rows: $(grep -c 'obligation' "$PROG" 2>/dev/null): $(grep 'milestone-5' "$PROG" 2>/dev/null)"; fi

# THE POINT OF THE DISTINCT VERB, measured rather than asserted about the spelling: the
# scheduler's close-out token must be UNMOVED across a close-out that met one obligation. A row
# carrying `| milestone-5 | satisfied` in any form would move it here.
ob_tok_after="$(gate progress 7 --satisfied 5)"
if [ "$ob_tok_before" = "$ob_tok_after" ] && [ -n "$ob_tok_after" ]; then
  pass "(ob3) an obligation row does NOT move the scheduler's milestone-5 token — the verb is distinct from the aggregate's"
else fail "(ob3) the obligation row moved the close-out token: '$ob_tok_before' -> '$ob_tok_after'"; fi

# The report the scheduler ECHOES. Each obligation with its own state, the aggregate's own state
# alongside its parts — "both met, no aggregate" is a real state — and teardown read SEPARATELY,
# never folded into the milestone (D-11).
out="$(gate progress 7 --obligations)"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qF 'milestone-5 obligation exit-artifacts: met' <<<"$out" \
   && grep -qF 'milestone-5 obligation verdict-reference: unmet' <<<"$out" \
   && grep -qF 'milestone-5 aggregate: not satisfied' <<<"$out" \
   && grep -qF 'teardown: not recorded' <<<"$out"; then
  pass "(ob4) 'progress --obligations' reports each obligation, the aggregate, and teardown as four separate answers"
else fail "(ob4) the obligations report was wrong, rc=$rc: $out"; fi

# ...and once the missing comment exists the SAME milestone passes, recording the transition
# rather than rewriting it. `bgate`, because this is the case that reaches cmd_mark.
out="$(bgate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | unmet')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | met')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | satisfied')" -eq 1 ]; then
  pass "(ob2) the fixed close-out passes, and the record keeps BOTH states — an append-only history, not a rewrite"
else fail "(ob2) rc=$rc: $(grep 'milestone-5' "$PROG" 2>/dev/null)"; fi

# `met` WINS over `unmet` when both are on file. There is no reverse transition, so reporting the
# failure would make an append-only record say the run got worse.
out="$(gate progress 7 --obligations)"
if grep -qF 'milestone-5 obligation verdict-reference: met' <<<"$out" \
   && grep -qF 'milestone-5 aggregate: satisfied' <<<"$out"; then
  pass "(ob5) with both states on file the report reads 'met' — the pair is a history, and only one direction of it exists"
else fail "(ob5) the report did not resolve the met/unmet pair: $out"; fi

# IDEMPOTENT PER (obligation, state). `all` re-runs cmd_5 on every sweep, and a record that grew
# a row per sweep would be unreadable long before it was wrong.
out="$(bgate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"
if [ "$(count_in_progress '| milestone-5 | obligation | exit-artifacts | met')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | verdict-reference | met')" -eq 1 ]; then
  pass "(ob6) re-running milestone 5 restates nothing — one row per (obligation, state)"
else fail "(ob6) obligation rows accumulated across re-runs: $(grep -c 'obligation' "$PROG")"; fi

# The flag is a REPORT, not a token space, so it cannot be combined with one — a caller that asked
# for both would get two different KINDS of answer on one stream. Driven against `--satisfied`
# since #718; the `--infra` half of this refusal went with the flag.
out="$(gate progress 7 --obligations --satisfied 5)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'cannot be combined' <<<"$out"; then
  pass "(ob7) --obligations refuses to combine with --satisfied"
else fail "(ob7) expected rc=2, got $rc: $out"; fi
out="$(gate 5 7 --obligations)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "only meaningful on 'progress'" <<<"$out"; then
  pass "(ob8) --obligations on a subcommand that ignores it is a usage error, not a silent no-op"
else fail "(ob8) expected rc=2, got $rc: $out"; fi

# ---- (l) usage errors --------------------------------------------------------------------
out="$(gate 9 7)"; rc=$?
if [ "$rc" -eq 2 ]; then pass "(l1) an unknown subcommand is a usage error"
else fail "(l1) expected rc=2 for subcommand 9, got $rc"; fi
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" bash "$GATE" 1 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ]; then pass "(l2) a missing issue argument is a usage error"
else fail "(l2) expected rc=2 with no issue, got $rc"; fi

# ---- (m) RUN_ID survives a fresh subprocess with no RUN_ID in its own env ------------------
# Observed live on #306: `RUN_ID` was exported for the `claim` call only. Every later
# `bash G <n> <issue>` runs as its own one-shot subprocess (only cwd persists across tool
# calls, not shell state), so the export was gone by milestone 1 and the progress-file header
# stamped `run_id: unset` — a mismatch against the claim comment / verdict record that
# lean-reconcile.sh exists to catch. The fix caches the id to `<issue>-run-id` on the first
# call that sees it in its own env, and resolves later calls from that cache.
RUN_ID_CACHE="$TREE/.claude/pipeline-state/7-run-id"
rm -f "$RUN_ID_CACHE"
reset_progress
gate 3 7 >/dev/null 2>&1  # RUN_ID unset here too — establishes the "no cache yet" baseline
out="$(cat "$PROG" 2>/dev/null)"
if grep -q '^run_id: unset$' <<<"$out"; then
  pass "(m1) with no RUN_ID and no cache, the header stamps run_id: unset (unchanged default)"
else fail "(m1) expected 'run_id: unset' in the header, got: $out"; fi
if grep -q '^model: unknown$' <<<"$out"; then
  pass "(m1b) ensure_progress_file() stamps model: unknown when LEAN_RUN_MODEL is unset (#347)"
else fail "(m1b) expected 'model: unknown' in the header, got: $out"; fi

# The other direction of the same seam, which nothing covered: (m1b) alone reads as "the model
# key works" while only ever proving the DEFAULT. A stamp that ignored the variable entirely —
# a hardcoded `unknown` — passes (m1b) and every other case in this file, and would silently
# make the retro corpus's model-aggregation key a constant.
#
# WHICH CALL carries the variable is load-bearing, and it moved. The header is stamped ONCE, at
# record CREATION — `ensure_progress_file` will not rewrite a file that exists — and creation is
# now `entry`, which `reset_progress` drives. By the time any milestone call runs, the header is
# already written, so setting the variable on `gate 3` asserted nothing: the case read the
# `model: unknown` that `entry` had already stamped without it. Set it on the CREATING call, in
# a subshell so nothing leaks to the cases below. That is also the ordering an honest run is in
# — the stamp is a property of the run, not of whichever milestone happens to execute first —
# and the case keeps its full strength: a hardcoded `unknown` still fails here.
reset_progress_unattested
( export LEAN_RUN_MODEL=selftest-model-357; attest_at "$TREE" "$CFG" "$PROG" 7 )
out="$(cat "$PROG" 2>/dev/null)"
if grep -q '^model: selftest-model-357$' <<<"$out"; then
  pass "(m1c) ensure_progress_file() stamps the LEAN_RUN_MODEL value when one IS set (#347)"
else fail "(m1c) expected 'model: selftest-model-357' in the header, got: $out"; fi

reset_progress
rm -f "$RUN_ID_CACHE"
# Through `entry`, a BUILD-ROLE subcommand — only `entry` and `claim` may ESTABLISH the build
# identity, for the reason (m4) pins. `entry` is the cheaper of the two to drive here (a
# session id and a non-empty ledger, both already fixtured above; `claim` needs the bot
# wrapper), and it is also the first call of a real run, which is what (m3) then continues.
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-live RUN_ID="selftest-run-306" bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$RUN_ID_CACHE" 2>/dev/null)" = "selftest-run-306" ]; then
  pass "(m2) a build-role call made WITH RUN_ID in its env caches it to <issue>-run-id"
else fail "(m2) expected the cache file to hold 'selftest-run-306', rc=$rc, cache=$(cat "$RUN_ID_CACHE" 2>/dev/null)"; fi

reset_progress
# No RUN_ID in THIS call's env — simulates the fresh-subprocess loss. The cache from (m2)
# must be what the header resolves against, not "unset".
gate 3 7 >/dev/null 2>&1
out="$(cat "$PROG" 2>/dev/null)"
if grep -q '^run_id: selftest-run-306$' <<<"$out"; then
  pass "(m3) a later call with NO RUN_ID in its env still resolves the cached id, not unset"
else fail "(m3) expected 'run_id: selftest-run-306' from the cache, got: $out"; fi

# An EVALUATION may READ the build identity, never ESTABLISH one. With no cache on disk yet —
# a run that never exported RUN_ID, a state dir cleaned after a retro — a REVIEW session doing
# the natural thing (`bash G 4 <issue>` to check the record it just wrote, which review-lean
# forbids nowhere) would otherwise CREATE the cache holding its own id. Milestone 4 compares
# the record against that very file, so it would then refuse a valid, review-authored record
# on every subsequent call, burning a fix attempt each time until the budget hard-stops.
# Seed-once alone does not cover this: there is nothing to lose the race to.
reset_progress
rm -f "$RUN_ID_CACHE"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        RUN_ID="r-review-poison" bash "$GATE" 4 7 2>&1 )"
if [ ! -e "$RUN_ID_CACHE" ]; then
  pass "(m4) a milestone EVALUATION with RUN_ID set does not create the build run-id cache"
else fail "(m4) an evaluation seeded the build cache with '$(cat "$RUN_ID_CACHE" 2>/dev/null)'"; fi

rm -f "$RUN_ID_CACHE"
reset_progress

# ---- (n) P10 authorship: the build session may not author its own verdict ------------------
# Three build identities are compared, and each arm has its own way of being the one that
# matters. (n1) is the ordinary case. (n2) uses the session id, which is harness-assigned
# rather than agent-chosen and so is the hardest of the three to fake. (n3) is the arm a
# plausible implementation omits: a review session that provisioned NO identity used to
# resolve the build's cached one, and the record it wrote then differed from nothing.
REVIEW_CACHE="$TREE/.claude/pipeline-state/7-review-run-id"
seed_build_progress() { # seed_build_progress <run-id> <session-id>
  reset_progress_unattested
  { echo "# lean run — issue 7"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$PROG"
  attest_at "$TREE" "$CFG" "$PROG" 7
}

seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-build-1\nsession_id: sess-review-1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q "BUILD run's identity" <<<"$out"; then
  pass "(n1) milestone-4 refuses a verdict carrying the build run's run_id"
else fail "(n1) expected rc=6 on a build-authored verdict, got $rc: $out"; fi

seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-review-1\nsession_id: sess-build-1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q 'names the BUILD session' <<<"$out"; then
  pass "(n2) milestone-4 refuses a verdict whose session_id is the build session's"
else fail "(n2) expected rc=6 on a build-session verdict, got $rc: $out"; fi

# The cache arm. The progress header records no usable build run id, so ONLY the cache file
# can supply it — which is exactly the state a review session that re-exported nothing is in.
seed_build_progress unset sess-build-1
mkdir -p "$(dirname "$RUN_ID_CACHE")"; printf 'r-cached-1' > "$RUN_ID_CACHE"
printf 'verdict=approve\nrun_id: r-cached-1\nsession_id: sess-review-1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q "BUILD run's identity" <<<"$out"; then
  pass "(n3) milestone-4 refuses an identity that resolves from the build run-id CACHE file"
else fail "(n3) expected rc=6 on a cache-resolved identity, got $rc: $out"; fi
rm -f "$RUN_ID_CACHE"

# ---- (q) a REVIEW session checking the record it wrote must not red it ---------------------
# Milestone 4 compared the verdict's run_id against $RESOLVED_RUN_ID — "whoever is running this
# command" — which is a BUILD identity only when a build session is the caller. review-lean
# SKILL.md step 1 requires the review session to export its own RUN_ID, and nothing forbids it
# from running `bash G 4 <issue>` to check the record it just wrote; that call resolved the
# review id, matched the record by construction, and refused it. Under overwrite-caching the
# same call ALSO replaced the build cache with the review id, so every later clean-env call
# stayed red. All three halves are asserted — the pass, the intact cache, and the re-check.
seed_build_progress r-build-1 sess-build-1
mkdir -p "$(dirname "$RUN_ID_CACHE")"; printf 'r-build-1' > "$RUN_ID_CACHE"
write_review_verdict
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        RUN_ID=r-review-1 bash "$GATE" 4 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(q1) milestone-4 passes when the REVIEW session runs it with its own RUN_ID exported"
else fail "(q1) expected rc=0 from a review-run milestone-4, got $rc: $out"; fi

if [ "$(cat "$RUN_ID_CACHE" 2>/dev/null)" = "r-build-1" ]; then
  pass "(q2) that call left the BUILD run-id cache intact (seed-once, not overwrite)"
else fail "(q2) build cache clobbered to '$(cat "$RUN_ID_CACHE" 2>/dev/null)', want r-build-1"; fi

seed_build_progress r-build-1 sess-build-1
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(q3) a later clean-env milestone-4 on the SAME record still passes"
else fail "(q3) expected rc=0 from the clean-env re-check, got $rc: $out"; fi
rm -f "$RUN_ID_CACHE"

# ---- (o) AC-3: milestone-4 EVALUATION never writes the verdict record ----------------------
# The build session's only relationship to that file is reading one somebody else wrote. A
# gate that could rewrite it — even to "normalize" it — makes every check in (n) decorative.
# mtime is backdated first so that a rewrite producing identical bytes still shows up.
# `-f` is the one stat flag whose two dialects both SUCCEED at printing something. On BSD it is
# the format string; on GNU it is --file-system, so a BSD-first probe there dumps a whole
# filesystem block to stdout and *then* exits non-zero — the `||` appends the real mtime after
# it, and the captured value carries the runner's free-block count. Two calls milliseconds apart
# disagree whenever that count moves, so the comparison below was reading free disk space, not
# mtime: red at random on GNU, green every time on BSD. Probe GNU first (BSD `stat -c` fails with
# an empty stdout, so that direction cannot leak), then require digits, so neither dialect's
# error output can reach the comparison. Empty is a FAILURE below, never a vacuous match.
mtime_of() { # mtime_of <file> -> epoch seconds, or "" when neither dialect resolves
  local m
  m="$(stat -c '%Y' "$1" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m="$(stat -f '%m' "$1" 2>/dev/null)" ;; esac
  case "$m" in ''|*[!0-9]*) m="" ;; esac
  printf '%s' "$m"
}
seed_build_progress r-build-1 sess-build-1
printf '# spec\n\n- AC-1: a thing\n' > "$SPEC"
# Committed on its OWN, before the record is written. `commit_tree` stages everything, so
# folding this into the verdict commit would put a code change inside it — a shape review-lean
# step 6 forbids ("commit nothing else in this session") and which both freshness arms refuse.
commit_tree "spec settles before the review"
write_review_verdict
touch -t 202601010000 "$VERDICT"
o_sum_before="$(cksum < "$VERDICT")"; o_mt_before="$(mtime_of "$VERDICT")"
out="$(bgate all 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
o_sum_after="$(cksum < "$VERDICT")"; o_mt_after="$(mtime_of "$VERDICT")"
if [ "$rc" -eq 0 ] && [ -n "$o_mt_before" ] && [ "$o_sum_before" = "$o_sum_after" ] && [ "$o_mt_before" = "$o_mt_after" ]; then
  pass "(o) a full 'all' sweep leaves the verdict record byte- and mtime-identical"
else fail "(o) sweep rc=$rc; cksum $o_sum_before -> $o_sum_after; mtime '$o_mt_before' -> '$o_mt_after': $out"; fi

# ---- (co1) #642 AC-3, round 1 B1: the CLOSE-OUT path re-verbed --------------------------------
# AC-3 was half-applied. `cmd_5`'s milestone-5 reds were re-verbed; `cmd_close_out`'s were not, so
# two reasons the ablation corpus adjudicates `unchanged` — m5/progress-current and
# m5/exit-artifacts:no-open-pr — still reached `append_attempt` on the close-out path and charged
# the fix budget. The static (ac1c) guard above is what catches the class; this is the reachable
# arm driven end to end, because a count of call sites cannot observe which counter moved.
#
# THIS RUNS RIGHT AFTER (o) ON PURPOSE. close-out evaluates milestones 1-4 itself and stops at the
# first red, so the no-PR arm is only reachable from a tree where all four pass — which is exactly
# what (o) just proved of this one. `seed_build_progress` gives it a clean attested record;
# close-out re-runs 1-4 and appends their satisfied rows itself.
#
# The other arm, `cmd_close_out`'s progress-current red, has NO behavioral fixture and can have
# none: it sits behind the 1-4 loop that appends the very satisfied rows it tests for, so no
# input reaches it. (ac1c) is that arm's only possible guard, which is the argument for a static
# case here rather than the usual preference for a driven one.
printf '[]\n' > "$WORK/pr-none.json"
seed_build_progress r-build-1 sess-build-1
out="$(gate close-out 7 --pr-file "$WORK/pr-none.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no open or merged PR found' <<<"$out"; then
  pass "(co1a) close-out refuses when the lane branch has no open or merged PR"
else fail "(co1a) expected rc=1 naming the missing PR, got $rc: $out"; fi
# The assertion the blocker is about. `absent` >= 1 AND `attempt` == 0 together — either alone
# passes vacuously, the first on a path that also charged, the second on a path that recorded
# nothing. The obligation row is the third: close-out mirrors cmd_5's `block_obligation
# exit-artifacts`, so the record names WHICH half is outstanding rather than leaving one
# indistinguishable line (#531 D-10).
if [ "$(count_in_progress '| milestone-5 | absent |')" -ge 1 ] \
   && [ "$(count_in_progress '| milestone-5 | attempt |')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-5 | obligation | exit-artifacts | unmet')" -eq 1 ]; then
  pass "(co1) #642 AC-3: the close-out no-PR refusal records 'absent' and its obligation row, and charges no fix attempt"
else fail "(co1) expected an absent row, 0 attempts and the unmet obligation, got $(count_in_progress '| milestone-5 | absent |') / $(count_in_progress '| milestone-5 | attempt |') / $(count_in_progress '| milestone-5 | obligation | exit-artifacts | unmet'): $(cat "$PROG")"; fi

# ---- (x) #374 AC-1/2/3: cmd_all's cheap pre-pass -------------------------------------------
# The pre-pass evaluates milestones 1 and 4 BEFORE milestone 3's green gate (~15 minutes in
# production). The fixture's own milestone-3 body is free (test/lint/typecheck are null), so
# the seam AC-1 asks for is a marker file: `commands.acme.test` is repointed to `touch` one,
# and the marker's ABSENCE after a dirty pre-pass is proof milestone 3's body never ran — proof
# by effect, not by timing.
MARKER="$WORK/m3-marker"
CFG_M3="$WORK/config-m3.json"
jq --arg m "$MARKER" '.commands.acme.test = ("touch " + ($m | @sh))' "$CFG" > "$CFG_M3"
gate_m3() {
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID
    # shellcheck disable=SC2030,SC2031  # subshell-local is the point: the identity must reach
    # this one gate invocation and no other, exactly like the unset it re-opens.
    [ -n "$BUILD_SID" ] && export CLAUDE_CODE_SESSION_ID="$BUILD_SID"
    cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_M3" LEAN_PROGRESS_FILE="$PROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
bgate_m3() { BUILD_SID="$ENTRY_SID" gate_m3 "$@"; }

reset_progress
rm -f "$MARKER"
write_review_verdict needs-work
out="$(gate_m3 all 7)"; rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$MARKER" ] && grep -q 'reads verdict=needs-work' <<<"$out"; then
  pass "(x1) AC-1: 'all' reports the milestone-4 refusal without running milestone-3's body"
else fail "(x1) expected rc!=0, no marker, needs-work message — rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi

# AC-3: BOTH cheap assertions broken (spec AC-less AND verdict needs-work) are reported
# together in ONE pre-pass, not just the first a naive sequential loop would reach.
cp "$SPEC" "$WORK/held-spec-x.md"
printf '# spec\n\nno AC token here\n' > "$SPEC"
out="$(gate_m3 all 7)"; rc=$?
if [ "$rc" -ne 0 ] \
   && grep -q 'no numbered AC-n' <<<"$out" \
   && grep -q 'reads verdict=needs-work' <<<"$out"; then
  pass "(x2) AC-3: the pre-pass reports BOTH cheap failures from one 'all' run"
else fail "(x2) expected both milestone-1 and milestone-4 pre-pass failures, got rc=$rc: $out"; fi
cp "$WORK/held-spec-x.md" "$SPEC"

# AC-2: a clean pre-pass (spec ok, verdict approve+fresh) still runs milestone 3 for real — the
# marker now appears, proving the pre-pass is not a way to skip the green gate.
reset_progress
rm -f "$MARKER"
write_review_verdict
out="$(bgate_m3 all 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ -e "$MARKER" ]; then
  pass "(x3) AC-2: a clean pre-pass still runs milestone-3's real body (green gate not skipped)"
else fail "(x3) expected rc=0 and the marker present, got rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi
# #566 AC-1: `all`'s 3-leg runs INLINE, in this process. Until #566 it went through a
# launch-or-join wrapper that spawned a detached runner and blocked on its marker; the whole
# stratum is gone, and this is the case that would fail if any of it came back.
#
# ASSERTED AS AN ABSENCE, which is the only shape available and is why it is paired with (x3)
# directly above: (x3) proves milestone 3's real body RAN (the marker exists), so this case
# cannot pass vacuously by the leg being skipped. Absence alone would be satisfied by a
# milestone 3 that did nothing at all.
if ! grep -q 'spawned detached' <<<"$out" && ! grep -q 'runner state:' <<<"$out"; then
  pass "(x3d) #566 AC-1: 'all' reaches milestone 3 as a single inline call — nothing is detached"
else fail "(x3d) 'all' announced a detached milestone-3 evaluation: $out"; fi
rm -f "$MARKER"
reset_progress

# ---- (y) #374 AC-8/9/10: milestone 1 refuses an unresolved pause-and-ask Open Region -------
cat > "$WORK/issue-or1-paa.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | Ordering guarantee | pause-and-ask |\n| OR-2 | Retention window | reversible-default-and-flag |\n"}
EOF
cat > "$WORK/issue-or-flag-only.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-2 | Retention window | reversible-default-and-flag |\n"}
EOF
cat > "$WORK/comments-or1-resolved.json" <<'EOF'
[{ "user": { "type": "User", "login": "operator" }, "body": "Go with append-only for OR-1, ship it." }]
EOF
cat > "$WORK/comments-or1-bot.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" }, "body": "auto-note mentioning OR-1, but not from an operator" }]
EOF
cat > "$WORK/comments-or10-boundary.json" <<'EOF'
[{ "user": { "type": "User", "login": "operator" }, "body": "OR-10 is fine as scoped, no change needed" }]
EOF

# (y1) AC-10: no Open Regions section at all — additive, milestone 1 unaffected.
out="$(gate 1 7 --issue-file "$ISSUE_NOREGIONS" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(y1) AC-10: an issue with no Open Regions section passes milestone 1 unchanged"
else fail "(y1) expected rc=0 with no Open Regions section, got $rc: $out"; fi

# (y2) AC-8: a pause-and-ask region with no resolution artifact refuses, naming the region.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out" && grep -q 'pause-and-ask' <<<"$out"; then
  pass "(y2) AC-8: an unresolved pause-and-ask region refuses milestone 1, naming the region"
else fail "(y2) expected rc=1 naming OR-1, got $rc: $out"; fi

# (y3) AC-8: a non-bot comment naming the region IS a resolution artifact.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-or1-resolved.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(y3) AC-8: a non-bot operator comment naming the region clears the refusal"
else fail "(y3) expected rc=0 with an operator comment naming OR-1, got $rc: $out"; fi

# ...and a BOT comment mentioning the same id does NOT count — only an operator write does.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-or1-bot.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y3b) a BOT-authored comment naming the region does not resolve it"
else fail "(y3b) expected rc=1 despite a bot comment mentioning OR-1, got $rc: $out"; fi

# ...and a comment naming a DIFFERENT, merely similar id (OR-10) must not resolve OR-1 — the
# word-boundary the id match is built on.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-or10-boundary.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y3c) a comment naming OR-10 does not resolve OR-1 (word-boundary match, not substring)"
else fail "(y3c) expected rc=1 — OR-10 must not satisfy OR-1, got $rc: $out"; fi

# (y4) AC-8: a ratified intent-gap record naming the region IS a resolution artifact, even
# with an empty comment trail.
reset_progress
GAP="$TREE/docs/plans/acme-7-lean-intent-gap.md"
printf 'region: OR-1\nratified: yes\nratified_by: https://example.invalid/issues/7#issuecomment-1\n' > "$GAP"
commit_tree "ratified intent-gap for OR-1"
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(y4) AC-8: a ratified intent-gap record naming the region clears the refusal"
else fail "(y4) expected rc=0 with a ratified intent-gap record for OR-1, got $rc: $out"; fi
rm -f "$GAP"; commit_tree "remove intent-gap fixture"

# (y5) AC-9: reversible-default-and-flag alone never refuses.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-flag-only.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(y5) AC-9: a reversible-default-and-flag region does not refuse milestone 1"
else fail "(y5) expected rc=0 with only a reversible-default-and-flag region, got $rc: $out"; fi

# (y6) AC-15: the disposition is the last NON-EMPTY cell, not $(NF-1). GFM does not require a
# trailing pipe; under $(NF-1) this table's disposition cell is the Region text, so the row is
# silently skipped and the gate fails OPEN — the unsafe direction, on markup a renderer
# accepts. The header/separator rows drop the trailing pipe here too, as a real one would.
cat > "$WORK/issue-or1-nopipe.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n| ID | Region | Disposition\n| --- | --- | ---\n| OR-1 | Ordering guarantee | pause-and-ask\n"}
EOF
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-nopipe.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y6) AC-15: a pause-and-ask row in a trailing-pipe-less table still refuses (no fail-open)"
else fail "(y6) expected rc=1 naming OR-1 on a trailing-pipe-less table, got $rc: $out"; fi

# (y7) AC-16: two unresolved regions are named in ONE refusal — the AC-3 ergonomic applied to
# this check. Asserting the refusal COUNT is the load-bearing half: reporting them as two
# successive lines would satisfy a both-ids-present grep while still costing two round-trips.
cat > "$WORK/issue-or-two-paa.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | Ordering guarantee | pause-and-ask |\n| OR-3 | Backfill window | pause-and-ask |\n"}
EOF
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-two-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
n="$(printf '%s\n' "$out" | grep -c 'dispositioned pause-and-ask with no resolution artifact')"
if [ "$rc" -eq 1 ] && [ "$n" -eq 1 ] && grep -q 'regions OR-1, OR-3' <<<"$out"; then
  pass "(y7) AC-16: two unresolved regions are reported together, in a single refusal"
else fail "(y7) expected rc=1 with 1 refusal naming both OR-1 and OR-3, got rc=$rc refusals=$n: $out"; fi

# (y8) AC-18: the `ratified: yes` conjunct on the intent-gap resolution arm. (y4) covers a
# ratified record and (y2) covers the file being absent — but `ratified: no` is indistinguishable
# from absence to both, so dropping the conjunct would let an UNRATIFIED record clear a
# pause-and-ask region with the whole suite green. That is the inverse of the merge boundary's
# own `ratified: no` refusal (P9).
reset_progress
GAP="$TREE/docs/plans/acme-7-lean-intent-gap.md"
printf 'region: OR-1\nratified: no\n' > "$GAP"
commit_tree "unratified intent-gap for OR-1"
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y8) AC-18: an intent-gap record reading 'ratified: no' does not clear the region"
else fail "(y8) expected rc=1 — an unratified intent-gap record must not resolve OR-1, got $rc: $out"; fi
rm -f "$GAP"; commit_tree "remove unratified intent-gap fixture"
reset_progress

# (y9)-(y11) #532: "could not read the issue" is not "the issue declares no region", and it is
# not a failed FIX either. Both gh arms already printed a reason, so both already refused —
# what they could not do was refuse for the right REASON: an unreadable tracker spent one of
# milestone 1's three attempts, and three blips hard-stopped the run at rc=4.
#
# Each case asserts BOTH halves. The rc alone is not enough — rc=1 and rc=2 are both refusals,
# and only the attempt COUNT separates "the operator has work to do" from "the environment is
# broken". Read straight off the progress file, which is what the budget is computed from.
attempts_1() { grep -cF '| milestone-1 | attempt |' "$PROG" 2>/dev/null || true; }

reset_progress
before="$(attempts_1)"
printf '{"body": not json at all' > "$WORK/issue-malformed.json"
out="$(gate 1 7 --issue-file "$WORK/issue-malformed.json" --comments-file "$WORK/comments-none.json")"; rc=$?
after="$(attempts_1)"
if [ "$rc" -eq 2 ] && grep -q 'could not parse' <<<"$out" && [ "$before" = "$after" ]; then
  pass "(y9) an UNPARSEABLE issue file is an environment refusal (rc=2), not a clear and not a fix attempt"
else fail "(y9) expected rc=2 naming 'could not parse' with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi

# The gh arm. `gate` injects --issue-file, so this one goes through gate_cfg with a GH_CLI that
# cannot succeed — the real network-blip shape.
reset_progress
before="$(attempts_1)"
printf '#!/bin/sh\necho "gh: connection refused" >&2\nexit 1\n' > "$WORK/gh-dead.sh"
chmod +x "$WORK/gh-dead.sh"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        GH="$WORK/gh-dead.sh" bash "$GATE" 1 7 2>&1 )"; rc=$?
after="$(attempts_1)"
if [ "$rc" -eq 2 ] && grep -q 'could not read issue' <<<"$out" && [ "$before" = "$after" ]; then
  pass "(y10) a dead \`gh issue view\` is an environment refusal (rc=2) that spends no fix budget"
else fail "(y10) expected rc=2 naming 'could not read issue' with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi

# The direction that keeps (y9)/(y10) honest: a REAL unresolved region must still cost an
# attempt. Without it, turning every milestone-1 refusal into rc=2 would pass both cases above
# while silently putting the whole fix budget out of reach.
reset_progress
before="$(attempts_1)"
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
after="$(attempts_1)"
if [ "$rc" -eq 1 ] && [ "$after" -eq $((before + 1)) ]; then
  pass "(y11) a genuine unresolved region still costs one fix attempt — the two refusals stay distinct"
else fail "(y11) expected rc=1 with attempts $before -> $((before + 1)), got rc=$rc attempts=$after: $out"; fi
reset_progress

# ---- #533: milestone 1 also reads the pre-flight ledger's Open Regions table -----------------
# Intake's plan-interview writes pause-and-ask regions THERE, not into the issue body, so a run
# whose spec came out of pre-flight had a region declared somewhere this guard, before #533,
# never looked.
LEDGER_OR1="$WORK/ledger-or1.md"
printf '## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | Ordering guarantee | pause-and-ask |\n' > "$LEDGER_OR1"
LEDGER_FLAG_ONLY="$WORK/ledger-flag-only.md"
printf '## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-2 | Retention window | reversible-default-and-flag |\n' > "$LEDGER_FLAG_ONLY"

# (y12) AC-1: a region declared ONLY in the ledger (the issue body carries no Open Regions
# section at all — gate()'s default $ISSUE_NOREGIONS) refuses, naming it. Proves the existing
# parser is genuinely reused against the new source, not merely declared reusable.
reset_progress
out="$(gate 1 7 --comments-file "$WORK/comments-none.json" --ledger-file "$LEDGER_OR1")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y12) AC-1: a pause-and-ask region declared only in the pre-flight ledger refuses milestone 1"
else fail "(y12) expected rc=1 naming OR-1 from a ledger-only region, got $rc: $out"; fi

# (y13) AC-1's union half: the SAME id in both the ledger and the issue body is reported ONCE,
# not twice — the two sources are deduplicated before resolution is checked.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json" --ledger-file "$LEDGER_OR1")"; rc=$?
n="$(printf '%s\n' "$out" | grep -c 'region OR-1')"
if [ "$rc" -eq 1 ] && [ "$n" -eq 1 ]; then
  pass "(y13) AC-1: the same region declared in both the ledger and the issue body is reported once"
else fail "(y13) expected rc=1 with OR-1 named once, got rc=$rc n=$n: $out"; fi

# (y14) AC-1: reversible-default-and-flag in the LEDGER never refuses, same as the existing (y5)
# rule for the issue body — the disposition enum applies uniformly across sources.
reset_progress
out="$(gate 1 7 --comments-file "$WORK/comments-none.json" --ledger-file "$LEDGER_FLAG_ONLY")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(y14) AC-1: a reversible-default-and-flag region in the ledger does not refuse milestone 1"
else fail "(y14) expected rc=0 with only a reversible-default-and-flag ledger region, got $rc: $out"; fi

# (y15) AC-2: an explicit --ledger-file pointed at a path that does not exist is an environment
# refusal, symmetric with --issue-file ((y9)) — a typo'd fixture path is not "no ledger".
reset_progress
before="$(attempts_1)"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json" --ledger-file "$WORK/does-not-exist-ledger.md")"; rc=$?
after="$(attempts_1)"
if [ "$rc" -eq 2 ] && grep -q 'does not exist' <<<"$out" && [ "$before" = "$after" ]; then
  pass "(y15) AC-2: an explicit --ledger-file naming a missing path is an environment refusal, no fix attempt spent"
else fail "(y15) expected rc=2 naming the missing --ledger-file with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi

# (y16) AC-4: the resolved DEFAULT ledger path (no --ledger-file) being absent is legitimate
# absence, not an error — most tickets never go through pre-flight.
reset_progress
rm -f "$TREE/.claude/pipeline-state/7-ledger.md"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(y16) AC-4: no ledger at the resolved default path is absence, not an error — milestone 1 unaffected"
else fail "(y16) expected rc=0 with no ledger at the default path, got $rc: $out"; fi

# (y17) AC-1/AC-4: the other half of (y16) — a ledger actually present at the resolved DEFAULT
# path ($STATE_DIR/<issue>-ledger.md under $MAIN_ROOT, not the --ledger-file seam) is read and
# refuses, proving the default-path branch is not merely inert.
reset_progress
mkdir -p "$TREE/.claude/pipeline-state"
cp "$LEDGER_OR1" "$TREE/.claude/pipeline-state/7-ledger.md"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json")"; rc=$?
rm -f "$TREE/.claude/pipeline-state/7-ledger.md"
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y17) AC-1/AC-4: a ledger present at the resolved default path is read and refuses"
else fail "(y17) expected rc=1 naming OR-1 from the default-path ledger, got $rc: $out"; fi

# (y18) AC-4: an unreadable ledger (exists, unreadable — chmod 000) is an environment refusal
# distinguishable from absence, and spends no fix-budget attempt — mirrors the two gh arms'
# (y9)/(y10) contract.
#
# Since #517 the RECONCILIATION reaches this file first — it runs in the observe pass, above the
# guard this check sits under — so the message below is now raised there. Deliberately left
# keyed on the fact rather than on the raiser: what AC-4 buys is that an unreadable ledger is
# never a silent CLEAR and never a fix attempt, and both halves hold whichever reader reports it.
reset_progress
before="$(attempts_1)"
mkdir -p "$TREE/.claude/pipeline-state"
: > "$TREE/.claude/pipeline-state/7-ledger.md"
chmod 000 "$TREE/.claude/pipeline-state/7-ledger.md"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json")"; rc=$?
after="$(attempts_1)"
chmod 644 "$TREE/.claude/pipeline-state/7-ledger.md"
rm -f "$TREE/.claude/pipeline-state/7-ledger.md"
if [ "$rc" -eq 2 ] && grep -q 'could not read pre-flight ledger' <<<"$out" && [ "$before" = "$after" ]; then
  pass "(y18) AC-4: an unreadable ledger at the default path is an environment refusal (rc=2), not a clear and not a fix attempt"
else fail "(y18) expected rc=2 naming 'could not read pre-flight ledger' with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi
reset_progress

# ---- (ys) #700: the section is read in the shapes the corpus ACTUALLY uses, and a section it
# cannot read REFUSES ------------------------------------------------------------------------
# WHY HERE AND NOT A SCENARIO: every case below drives one function pair (open_regions_section /
# open_region_rows) through the --issue-file and --ledger-file seams and asserts a single
# milestone-1 verdict. The COMPOSED path — an unenumerable section reaching a terminal refusal
# rather than a milestone-1 pass — is a different assertion and is covered where it belongs, by
# the `unenumerable open regions` scenario in scenario-liveness-selftest.sh. Neither subsumes the
# other: these pin WHICH shapes parse, that one pins that the verdict actually terminates.
#
# The pre-#700 parser split on the pipe character, so it recognized a region only as a table row.
# Measured across the tracker: 7 of the 11 issue bodies that declare regions with ids use bullets,
# and no issue body has used the table form since #381 — so the shape the gate could read was the
# shape nobody was writing, and milestone 1's refusal returned CLEAR having enumerated nothing.

# The #694 shape, which is what filed this: id and disposition on one bullet line.
cat > "$WORK/issue-or-bullet-paa.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- **OR-1** (`pause-and-ask`) — the plan artifact's contract\n- **OR-2** (`reversible-default-and-flag`) — the enum's members\n"}
EOF
# The #639 shape: the token sits on a CONTINUATION line of the bullet, not on its first line.
cat > "$WORK/issue-or-bullet-cont-paa.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- OR-1: which run identity the record binds to, given the scheduler scrubs RUN_ID and\n  the build run's id is minted in the child. `pause-and-ask` if no binding is derivable.\n"}
EOF
# The #640 OR-1/OR-2 shape: continuation-line token, but reversible — must still CLEAR.
cat > "$WORK/issue-or-bullet-cont-flag.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- OR-1: whether the non-verdict is a wait or a hand-back (stop;\n  the operator re-launches). `reversible-default-and-flag`, default hand-back.\n"}
EOF
# The #636 / #622 shape: a DECORATED heading. Pre-#700 this matched no section at all.
cat > "$WORK/issue-or-decorated-heading.json" <<'EOF'
{"body": "# issue\n\n## Open regions (BUILD flags, does not pause)\n\n- OR-1: the falsifier's construction. `pause-and-ask`, and it is blocking.\n"}
EOF
# A heading-per-region section: pre-#700 the sub-heading ENDED the section, leaving zero non-blank
# content lines, so it read as an empty section rather than an unparseable one.
cat > "$WORK/issue-or-heading-per-region.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n### OR-1 — Ordering\n\nDisposition: pause-and-ask\n"}
EOF
# The #441 / #427 / #426 / #363 shape: prose bullets carrying no OR-n at all.
cat > "$WORK/issue-or-idless-prose.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- Completeness of the AC-5 watcher taxonomy. The list is stated so the criteria are writable.\n- Trigger-5 behavior on stacks the detection does not cover, where every lane is null.\n"}
EOF
# The #640 OR-3 shape: an id whose disposition is stated only in prose, with no token anywhere.
cat > "$WORK/issue-or-nodisp.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- OR-3: whether an attended operator may override and approve anyway. Default **no** — this is a\n  gates-signal condition under the sibling register slice's predicate.\n"}
EOF
# Both defects at once, to pin that ONE run reports both.
cat > "$WORK/issue-or-two-defects.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\n- OR-3: whether an attended operator may override. Default **no**, flagged.\n- OR-4: the retention window. Default 30 days, flagged.\n"}
EOF
# A hand-written short empty form — NOT ledger-lint's canonical sentence.
cat > "$WORK/issue-or-empty-form-short.json" <<'EOF'
{"body": "# issue\n\n## Open regions\n\nNo open regions.\n"}
EOF
# A heading with nothing under it: asserts nothing, so it is not the unenumerable case.
cat > "$WORK/issue-or-bare-heading.json" <<'EOF'
{"body": "# issue\n\n## Open Regions\n\n## Acceptance Criteria\n\n- AC-1 something\n"}
EOF

# (y19) AC-3: the #694 bullet — the shape this ticket was filed on. Pre-#700 the id came from the
# second pipe-delimited field of a line with no pipes, so it was empty and the region vanished.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-bullet-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out" && ! grep -q 'OR-2' <<<"$out"; then
  pass "(y19) AC-3: a bullet-form pause-and-ask region refuses milestone 1, and its reversible sibling does not"
else fail "(y19) expected rc=1 naming OR-1 only, got $rc: $out"; fi

# (y20) AC-3: the disposition token on a CONTINUATION line. A first-line-only read finds the id
# and misses the token — and on #639, an OPEN ticket, that token is a live pause-and-ask.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-bullet-cont-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y20) AC-3: a pause-and-ask token on a bullet's continuation line is found and refuses"
else fail "(y20) expected rc=1 naming OR-1 from a continuation line, got $rc: $out"; fi

# (y21) AC-3/AC-7: the same folding must not manufacture a refusal. A continuation-line
# reversible-default-and-flag is a fully enumerated region and clears — the (y5) rule, reached
# through the bullet arm.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-bullet-cont-flag.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(y21) AC-3/AC-7: a continuation-line reversible-default-and-flag region is enumerated and clears"
else fail "(y21) expected rc=0 for a continuation-line reversible region, got $rc: $out"; fi

# (y22) AC-1: the DECORATED heading, and the sharpest case in this block. Pre-#700 the heading
# regex was anchored at end-of-line, so `## Open regions (BUILD flags, does not pause)` matched no
# section — nothing was misparsed, so no refusal could fire and the gate cleared in silence.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-decorated-heading.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y22) AC-1: a heading carrying trailing text is still the Open Regions section, and its region refuses"
else fail "(y22) expected rc=1 naming OR-1 under a decorated heading, got $rc: $out"; fi

# (y23) AC-2/AC-5: heading-per-region. The fix is in the SECTION extractor, not the row parse —
# terminating on any heading left zero non-blank content, which read as an empty section. It now
# stays inside, is visible, and reds as unenumerable rather than clearing.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-heading-per-region.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'could not enumerate the open regions' <<<"$out" && grep -q 'no recognized shape' <<<"$out"; then
  pass "(y23) AC-2/AC-5: a heading-per-region section is visible to the parse and refuses as unenumerable"
else fail "(y23) expected rc=2 naming an unenumerable section, got $rc: $out"; fi

# (y24) AC-5: idless prose bullets. The section asserts it has open regions and the parser cannot
# name one — the same "could not read" the two gh arms report, not "declares none".
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-idless-prose.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "issue #7's body declares an \"## Open regions\" section in no recognized shape" <<<"$out"; then
  pass "(y24) AC-5: a section of idless prose bullets is an environment refusal, not a clear"
else fail "(y24) expected rc=2 naming the issue body's unenumerable section, got $rc: $out"; fi

# (y25) AC-6: an id parsed with no recognizable disposition token. Reading it as "not
# pause-and-ask" is exactly the fail-open this ticket closes.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-nodisp.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'declares region OR-3 with no recognizable disposition' <<<"$out"; then
  pass "(y25) AC-6: a region with no recognizable disposition refuses, naming the region"
else fail "(y25) expected rc=2 naming OR-3 as dispositionless, got $rc: $out"; fi

# (y26) AC-9: every region in ONE message, not the first — the same ergonomic the unresolved-region
# refusal already owes and states. An operator clearing two must not pay two runs.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-two-defects.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'OR-3' <<<"$out" && grep -q 'OR-4' <<<"$out" \
   && [ "$(grep -c 'could not enumerate the open regions' <<<"$out")" -eq 1 ]; then
  pass "(y26) AC-9: two dispositionless regions are named in one refusal, not one per run"
else fail "(y26) expected one refusal naming both OR-3 and OR-4, got $rc: $out"; fi

# (y27) AC-7: the empty form is recognized by PREFIX, not against ledger-lint's canonical
# sentence. The issue body has no lint to teach an operator that sentence, so a hand-written
# "No open regions." must clear rather than refuse.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-empty-form-short.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(y27) AC-7: a short hand-written empty form clears — the recognizer is a prefix, not the canonical sentence"
else fail "(y27) expected rc=0 for a hand-written empty form, got $rc: $out"; fi

# (y28) AC-7: a heading with no non-blank content under it asserts nothing, so it is absence and
# not an unenumerable section. This is the boundary (y23) sits on the other side of.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or-bare-heading.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(y28) AC-7: an Open Regions heading with nothing under it declares nothing and clears"
else fail "(y28) expected rc=0 for a contentless section, got $rc: $out"; fi

# (y29) AC-8: the LEDGER source gets the same treatment, through the one shared parser. A fix
# that only covered the issue body would leave the other declared half open.
reset_progress
LEDGER_BULLET_PAA="$WORK/ledger-bullet-paa.md"
printf '## Open Regions\n\n- OR-1: the ordering guarantee. pause-and-ask, nobody owns it yet.\n' > "$LEDGER_BULLET_PAA"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json" --ledger-file "$LEDGER_BULLET_PAA")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(y29) AC-8: a bullet-form pause-and-ask region in the pre-flight ledger refuses too"
else fail "(y29) expected rc=1 naming OR-1 from the ledger, got $rc: $out"; fi

# (y30) AC-8: and the unenumerable arm reaches the ledger, naming THAT source rather than the
# issue body — an operator must be told which of the two to go and fix.
reset_progress
LEDGER_IDLESS="$WORK/ledger-idless.md"
printf '## Open Regions\n\n- Whether the ladder copies get manifest rows. Default: add it.\n' > "$LEDGER_IDLESS"
out="$(gate 1 7 --comments-file "$WORK/comments-none.json" --ledger-file "$LEDGER_IDLESS")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "the pre-flight ledger $LEDGER_IDLESS declares an" <<<"$out"; then
  pass "(y30) AC-8/AC-9: an unenumerable LEDGER section refuses, naming the ledger path as the source"
else fail "(y30) expected rc=2 naming the ledger path, got $rc: $out"; fi

# (y31) AC-10: the refusal costs no fix attempt. It is the environment-refusal arm, so a run whose
# ticket carries an unreadable section must not burn milestone 1's budget on something no edit the
# build role can make would fix — neither the issue body nor the gitignored receipt is its to edit.
reset_progress
before="$(count_in_progress '| milestone-1 | attempt |')"
out="$(gate 1 7 --issue-file "$WORK/issue-or-idless-prose.json" --comments-file "$WORK/comments-none.json")"; rc=$?
after="$(count_in_progress '| milestone-1 | attempt |')"
if [ "$rc" -eq 2 ] && [ "$after" -eq "$before" ]; then
  pass "(y31) AC-10: an unenumerable section is an environment refusal and spends no fix attempt"
else fail "(y31) expected rc=2 with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi

# (y32) AC-4/AC-12: the non-regression pin with teeth. The pre-#700 table path and its refusal
# SENTENCE are unchanged — that sentence is the one the file marks byte-for-byte fixed for
# headless runs, and the new refusal is an additional message rather than an edit to it.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1 dispositioned pause-and-ask with no resolution artifact' <<<"$out" \
   && ! grep -q 'could not enumerate the open regions' <<<"$out"; then
  pass "(y32) AC-4/AC-12: the table path still refuses with its original sentence, untouched by the new arm"
else fail "(y32) expected the original unresolved-region sentence and no enumeration refusal, got $rc: $out"; fi

# (y33) AC-5: the SIZE case, and the reason it is here. open_regions_defects reads its section
# with herestrings, not `printf | grep -q`: this file runs under `set -o pipefail`, `grep -q`
# exits on its first match, and on a section large enough to fill the pipe buffer the writer takes
# SIGPIPE — so the pipeline reports 141 ON A MATCH and the content test reads as "no content".
# Every other case in this block is a handful of lines and passes either way; this one is the
# only thing standing between that idiom and a fail-open reachable on real issue bodies.
reset_progress
{ printf '# issue\n\n## Open regions\n\n'
  awk 'BEGIN { for (i = 0; i < 3000; i++) print "- a prose bullet, number " i ", carrying no OR-n id at all and padded well past one pipe buffer" }'
} > "$WORK/or-big.txt"
jq -Rs '{body: .}' < "$WORK/or-big.txt" > "$WORK/issue-or-big.json"
out="$(gate 1 7 --issue-file "$WORK/issue-or-big.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no recognized shape' <<<"$out"; then
  pass "(y33) AC-5: a LARGE unenumerable section still refuses — the content test does not lose its match to SIGPIPE"
else fail "(y33) expected rc=2 on a >1-pipe-buffer unenumerable section, got $rc: $out"; fi

reset_progress

reset_progress

# ---- (yo) #613 AC-4: the operator-override route through the same refusal --------------------
# THE THIRD RESOLUTION ARTIFACT. (y3) covers the tracker comment and (y4) the ratified intent-gap
# record; these cover an override recorded by a present operator. The pairing that matters is
# (yo3)/(yo4): the token changes what the refusal SAYS and never what it decides.
OVT="$HERE/../../tools/operator-override.sh"
OV_REC="$TREE/docs/plans/acme-7-lean-override.md"
OV_SID="ov-attend-session"
OV_RID="ov-attend-run"
ov_attend() {
  ( cd "$TREE" && env RUN_ID="$OV_RID" CLAUDE_CODE_SESSION_ID="$OV_SID" SECOND_SHIFT_CONFIG="$CFG" \
      bash "$OVT" attend ) >/dev/null 2>&1
}
ov_write() { # ov_write <region>
  ( cd "$TREE" && env RUN_ID="$OV_RID" CLAUDE_CODE_SESSION_ID="$OV_SID" SECOND_SHIFT_CONFIG="$CFG" \
      bash "$OVT" record --gate spec-open-region --scope open-region-resolution --issue 7 \
      --region "$1" --decision 'append-only, per the operator' --answer 'Append-only. Ship it.' \
      --repo-root "$TREE" ) >/dev/null 2>&1
}
ov_clear() { rm -f "$OV_REC" "$TREE/.claude/pipeline-state/attend-$OV_SID.token"; commit_tree "drop override fixture" >/dev/null 2>&1; }

if [ ! -f "$OVT" ]; then
  fail "(yo0) the override mechanism at $OVT is absent — every case below would pass vacuously"
else
  pass "(yo0) the override mechanism resolves at the path lean-gate.sh defaults to"

  # (yo1) the YIELD. An override naming OR-1 clears the region with an empty comment trail and no
  # intent-gap record at all.
  reset_progress
  ov_attend
  ov_write OR-1
  commit_tree "override record for OR-1"
  out="$(BUILD_RID="$OV_RID" BUILD_SID="$OV_SID" gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "(yo1) AC-4: a recorded operator override naming the region clears the refusal, where today only a tracker comment does"
  else fail "(yo1) expected rc=0 with an override for OR-1, got $rc: $out"; fi

  # (yo2) authority is SCOPED to the region it names. Without this, an override for any region
  # would clear every region, and (yo1) alone could not tell the difference.
  reset_progress
  ov_clear
  ov_attend
  ov_write OR-3
  commit_tree "override record for OR-3"
  out="$(BUILD_RID="$OV_RID" BUILD_SID="$OV_SID" gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
    pass "(yo2) AC-4: an override recorded for another region does NOT clear this one"
  else fail "(yo2) expected rc=1 still naming OR-1, got $rc: $out"; fi
  ov_clear

  # (yo3) HEADLESS — the gate's normal case, since every scheduler payload is one. The refusal
  # sentence is asserted whole, and the affordance asserted ABSENT: AC-4 binds this arm unchanged.
  reset_progress
  out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  if [ "$rc" -eq 1 ] \
     && grep -qF 'record, before continuing. (attempt ' <<<"$out" \
     && ! grep -q 'record --gate spec-open-region' <<<"$out"; then
    pass "(yo3) AC-4: headless, the refusal is unchanged — its sentence runs straight into the attempt suffix, with no affordance spliced in"
  else fail "(yo3) expected the unchanged headless refusal with no affordance, got rc=$rc: $out"; fi

  # (yo4) ATTENDED, NO RECORD — the same rc, the same region, plus the exact command. This is the
  # epic's claim reduced to a diff between two refusals: the token bought the affordance and
  # nothing else.
  reset_progress
  ov_attend
  out="$(BUILD_RID="$OV_RID" BUILD_SID="$OV_SID" gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out" \
     && grep -q 'record --gate spec-open-region --scope open-region-resolution --issue 7 --region OR-1' <<<"$out"; then
    pass "(yo4) AC-4: attended with no record still REFUSES, and prints the exact record-writing command"
  else fail "(yo4) expected rc=1 with the affordance printed, got rc=$rc: $out"; fi

  # (yo4b) TWO unresolved regions, TWO commands. The affordance's own sentence promises "one
  # command per region", and authority is scoped per region — one command clears only the id it
  # names, so printing the first and leaving the operator to infer the rest is how a two-region
  # refusal gets half-resolved and re-runs into the same wall. Both ids asserted, because a
  # reader that emitted the LAST one instead of the first would look just as right on (yo4).
  reset_progress
  cat > "$WORK/issue-or2-paa.json" <<'PAA2'
{"body": "# issue\n\n## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | Ordering guarantee | pause-and-ask |\n| OR-3 | Backfill window | pause-and-ask |\n"}
PAA2
  out="$(BUILD_RID="$OV_RID" BUILD_SID="$OV_SID" gate 1 7 --issue-file "$WORK/issue-or2-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  if [ "$rc" -eq 1 ] \
     && grep -q -- '--region OR-1 ' <<<"$out" \
     && grep -q -- '--region OR-3 ' <<<"$out"; then
    pass "(yo4b) AC-4: two unresolved regions print two commands — one per region, as the sentence says"
  else fail "(yo4b) expected a command for BOTH OR-1 and OR-3, got rc=$rc: $out"; fi

  # (yo5) a malformed record is an ENVIRONMENT refusal that spends no fix budget — the same
  # posture (y10) pins for an unreadable tracker. Collapsing it into "no override" would let a
  # record the merge boundary is about to reject wave the region through here first.
  reset_progress
  before="$(attempts_1)"
  printf '## Override 1\ngate: spec-open-region\nscope: open-region-resolution\nissue: 7\nregion: none\nrun_id: r\nsession_id: s\nexpiry: run\ndecision: d\n\n### Operator answer\n\n> a\n' > "$OV_REC"
  commit_tree "malformed override record"
  out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
  after="$(attempts_1)"
  if [ "$rc" -eq 2 ] && grep -q 'could not be read as a clean answer' <<<"$out" && [ "$before" = "$after" ]; then
    pass "(yo5) a malformed override record is an environment refusal (rc=2) that spends no fix attempt"
  else fail "(yo5) expected rc=2 naming the unreadable record with attempts unchanged ($before), got rc=$rc attempts=$after: $out"; fi
  ov_clear
fi
reset_progress

# ---- (p) the REVIEW role: lean-gate.sh verdict ---------------------------------------------
# Every arm here is a refusal that fails CLOSED. The subcommand is the only write path to the
# verdict record, and it lives in this script solely so the pinned name table has one
# derivation — not because the build role may reach it.
verdict_cmd() { # verdict_cmd <session-id> <run-id|""> [args...]
  local sid="$1" rid="$2"
  shift 2
  if [ -n "$rid" ]; then
    ( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
      CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$GATE" verdict 7 "$@" 2>&1 )
  else
    ( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
      CLAUDE_CODE_SESSION_ID="$sid" bash "$GATE" verdict 7 "$@" 2>&1 )
  fi
}

seed_build_progress r-build-1 sess-build-1
rm -f "$VERDICT" "$REVIEW_CACHE" "$RUN_ID_CACHE"

out="$(verdict_cmd sess-build-1 r-review-9 --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'this IS the build session' <<<"$out"; then
  pass "(p1) verdict refuses when the invoking session is the build session"
else fail "(p1) expected rc=1 from the build session, got $rc: $out"; fi
[ -f "$VERDICT" ] && fail "(p1b) a refused verdict call still wrote the record" \
  || pass "(p1b) a refused verdict call writes nothing"

out="$(verdict_cmd sess-review-9 '' --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no review identity provisioned' <<<"$out"; then
  pass "(p2) verdict refuses with no review identity rather than inheriting the build's"
else fail "(p2) expected rc=1 with no RUN_ID, got $rc: $out"; fi

out="$(verdict_cmd sess-review-9 r-build-1 --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "IS the build run's" <<<"$out"; then
  pass "(p3) verdict refuses a review identity equal to the build run's"
else fail "(p3) expected rc=1 on a colliding identity, got $rc: $out"; fi

seed_build_progress r-build-1 unset
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no session id' <<<"$out"; then
  pass "(p4) verdict refuses when the build run recorded no session id (unverifiable is not fine)"
else fail "(p4) expected rc=1 on an unverifiable build session, got $rc: $out"; fi

seed_build_progress r-build-1 sess-build-1
printf 'No blockers. AC-1 satisfied.\n' > "$WORK/verdict-summary.md"
# The head the writer must name is the one it is invoked ON. Resolved here, before the call, so
# the assertion compares against a value this suite derived independently of the writer.
p5_head="$(git -C "$TREE" rev-parse HEAD)"
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve --rounds 2 --summary-file "$WORK/verdict-summary.md")"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'verdict=approve' "$VERDICT" 2>/dev/null \
   && grep -qF 'run_id: r-review-9' "$VERDICT" && grep -qF 'session_id: sess-review-9' "$VERDICT" \
   && grep -qF 'rounds: 2' "$VERDICT" && grep -qF 'No blockers.' "$VERDICT" \
   && grep -qF "reviewed_head: $p5_head" "$VERDICT" && grep -qF 'model: unknown' "$VERDICT"; then
  pass "(p5) verdict writes the record with all three reconciliation keys, a git-resolved reviewed_head, the model key (#347), and the summary body"
else fail "(p5) expected a well-formed record, rc=$rc: $out
$(cat "$VERDICT" 2>/dev/null)"; fi

# The two caches are separate FILES, not two names for one. If the review role touched the
# build cache, a later build call would resolve the review's id and the separation would
# unravel from the other end.
if [ "$(cat "$REVIEW_CACHE" 2>/dev/null)" = "r-review-9" ] && [ ! -e "$RUN_ID_CACHE" ]; then
  pass "(p6) the review identity caches under its own role key and the build cache is untouched"
else fail "(p6) review-cache='$(cat "$REVIEW_CACHE" 2>/dev/null)' build-cache-exists=$([ -e "$RUN_ID_CACHE" ] && echo y || echo n)"; fi

# ...and the record the REVIEW role just wrote is exactly what the BUILD role's milestone 4
# accepts. Asserting the two halves compose is the point; each half passing alone is not.
# The commit is the review session's own next step (review-lean step 6) and milestone 4 now
# requires it: an uncommitted record is invisible to everything downstream.
commit_tree "review session commits its record"
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(p7) milestone-4 accepts the record written by the review role"
else fail "(p7) expected rc=0 from milestone-4 on a review-written record, got $rc: $out"; fi

# ---- (r) the verdict role validates its value-args -----------------------------------------
# --pr lands verbatim in a COMMITTED evidence artifact, so it is validated like the other two
# value-args rather than merely checked for emptiness. Nothing escalates today (every reader
# takes the FIRST match of each key, so an injected `run_id:` loses to the authentic one), but
# that is a property of the current readers, not of this argument.
seed_build_progress r-build-1 sess-build-1
rm -f "$VERDICT" "$REVIEW_CACHE"

out="$(verdict_cmd sess-review-9 r-review-9 --pr not-a-number --verdict approve)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'pr must be a positive integer' <<<"$out"; then
  pass "(r1) verdict rejects a non-numeric --pr instead of echoing it into the record"
else fail "(r1) expected rc=2 on a non-numeric --pr, got $rc: $out"; fi
[ -f "$VERDICT" ] && fail "(r1b) a rejected --pr still wrote the record" \
  || pass "(r1b) a rejected --pr writes nothing"

out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve --rounds 0)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'rounds must be a positive integer' <<<"$out"; then
  pass "(r2) verdict rejects --rounds 0, which its own message always called positive"
else fail "(r2) expected rc=2 on --rounds 0, got $rc: $out"; fi

out="$(verdict_cmd sess-review-9 r-review-9 --pr '#12' --verdict approve)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'pr: #12' "$VERDICT" 2>/dev/null; then
  pass "(r3) a '#'-prefixed --pr is tolerated and normalized to a single '#'"
else fail "(r3) expected rc=0 and 'pr: #12', got $rc: $out
$(cat "$VERDICT" 2>/dev/null)"; fi

# `0` matches neither '' nor *[!0-9]*, so it is the alternative a mutant drops first — and it
# is dropped per-argument, so --rounds 0 passing at (r2) says nothing about --pr.
rm -f "$VERDICT"
out="$(verdict_cmd sess-review-9 r-review-9 --pr 0 --verdict approve)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'pr must be a positive integer' <<<"$out"; then
  pass "(r4) verdict rejects --pr 0, the same way it rejects --rounds 0"
else fail "(r4) expected rc=2 on --pr 0, got $rc: $out"; fi

rm -f "$REVIEW_CACHE"

# ---- (s) the verdict VALUE is read first-match, never counted across the file ---------------
# `--summary-file` puts the reviewer's own prose below the keys, and review prose discusses
# verdicts — the committed record for #237 carries the token twice for exactly that reason. A
# count-anywhere reader passes a record whose authoritative first line says needs-work: a
# fail-OPEN on the single predicate the whole lean chain rests on. Driven through the REAL
# writer, so the case also pins that a summary body cannot forge the value.
seed_build_progress r-build-1 sess-build-1
rm -f "$VERDICT" "$REVIEW_CACHE"
printf 'Round 1 returned verdict=approve; this round found a blocker and does not.\n' \
  > "$WORK/summary-quoting-approve.md"
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict needs-work \
       --summary-file "$WORK/summary-quoting-approve.md")"; rc=$?
if [ "$rc" -ne 0 ]; then fail "(s0) the fixture verdict write failed: $out"; else
  commit_tree "needs-work record whose body quotes the token"
  out="$(gate 4 7)"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'reads verdict=needs-work' <<<"$out"; then
    pass "(s) a needs-work record whose summary quotes verdict=approve is still refused"
  else fail "(s) expected rc=1 on a needs-work record quoting the token, got $rc: $out"; fi
fi
rm -f "$REVIEW_CACHE"

# ---- (t) THE RECORD MUST BE ON THE BRANCH ---------------------------------------------------
# Not freshness — #720 moved that question to the merge boundary, where lean-evidence.sh's
# arm_freshness is the one reader of it. What is left here is the precondition every downstream
# reader has: a record nobody committed is invisible to `pr-gates`, to the merge boundary and to
# a human opening the PR, so a lane that certified it would hand off a run carrying no evidence
# at all. That defect only the LANE can see, which is why these arms stay local.
seed_build_progress r-build-1 sess-build-1
write_review_verdict
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(t1) milestone-4 passes when the verdict's commit IS the head"
else fail "(t1) expected rc=0 on a fresh verdict, got $rc: $out"; fi

# #720 deleted (t2): the inferred freshness arm it pinned is gone from milestone 4, and
# lean-evidence.sh's arm_freshness asks the same question at the merge boundary. (t3), its
# remedy half, went with it — a remedy for a refusal that no longer exists asserts nothing.
# (t1) stays: it is the ordinary green, and the (t4)/(t5) uncommitted cases below still need it.
printf '# spec\n\n- AC-1: a thing\n- AC-2: added after the review\n' > "$SPEC"
commit_tree "code lands after the verdict"
seed_build_progress r-build-1 sess-build-1
write_review_verdict

# An UNCOMMITTED record is not evidence: nothing downstream can see it, and nothing dates it
# against the code. A bare `[ -f ]` existence check accepted it. TWO readings of "uncommitted"
# have to fail, and only one of them is what a `git log -- <path>` lookup notices.
#
# (t4) is tracked-but-DIRTY, the one that lookup misses: the path has a commit, so it resolves,
# while the bytes being read are not the bytes on the branch. This is the shape an operator
# actually produces — hand-editing an already-committed record — and it reads as green unless
# the working tree is compared too.
seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-review-9\nsession_id: sess-review-9\nrounds: 99\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'has uncommitted changes' <<<"$out"; then
  pass "(t4) milestone-4 refuses a committed record that was then edited locally"
else fail "(t4) expected rc=5 on a dirty record, got $rc: $out"; fi
git -C "$TREE" checkout -- "$VERDICT" >/dev/null 2>&1

# (t5) never committed at all. Driven on a DIFFERENT issue key, because `git log -- <path>`
# answers "has this path ever been committed" — deleting #7's record would leave the deletion
# commit behind and still resolve. #8's record has no history, which is the state a real first
# review round is in before it commits.
seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-review-9\nsession_id: sess-review-9\nrounds: 1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$TREE/docs/plans/acme-8-lean-verdict.md"
out="$(gate 4 8)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'was never committed' <<<"$out"; then
  pass "(t5) milestone-4 refuses a verdict record that was never committed at all"
else fail "(t5) expected rc=5 on an untracked record, got $rc: $out"; fi
rm -f "$TREE/docs/plans/acme-8-lean-verdict.md"

# ---- (n) the tracker adapter: github default + the jira arm --------------------------------
# The lane shipped github-only while being the DEFAULT lane, so a `tracker.type: jira` /
# `tracker.writes: false` consumer had three unreachable checklist items — the queue-label
# confirm, the two claim writes, and a milestone 5 gated on `Closes #<n>` plus a closing
# tracker comment that adapter posts none of. These cases pin the three branch sites.
CFG_JIRA="$WORK/config-jira.json"
cat > "$CFG_JIRA" <<'EOF'
{
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "abc/", "keyPattern": "[A-Z]+-[0-9]+" },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null } }
}
EOF
# jq, not sed: a textual substitution exits 0 whether or not it fired, so a reformatted
# fixture would silently produce a config IDENTICAL to $CFG — and (n8) would then compare the
# default against itself and pass forever while asserting nothing. The injection is asserted
# below for the same reason; a fixture builder that can no-op is the mirror-harness bug class.
CFG_GITHUB="$WORK/config-github.json"
jq '.tracker.type = "github"' "$CFG" > "$CFG_GITHUB"
CFG_BOGUS="$WORK/config-bogus.json"
jq '.tracker.type = "gitlab"' "$CFG" > "$CFG_BOGUS"
if [ "$(jq -r '.tracker.type' "$CFG_GITHUB" 2>/dev/null)" = "github" ] \
   && [ "$(jq -r '.tracker.type' "$CFG_BOGUS" 2>/dev/null)" = "gitlab" ] \
   && [ "$(jq -r '.tracker.type // "absent"' "$CFG" 2>/dev/null)" = "absent" ]; then
  pass "(n0) the adapter fixtures were actually built (github/gitlab injected, base still absent)"
else fail "(n0) fixture build did not apply — the (n7)/(n8) comparison would be vacuous"; fi

JKEY="ACME-7"
PROG_J="$WORK/progress-jira.md"
JSPEC_REL="docs/plans/acme-$JKEY-lean.md"
JVERDICT_REL="docs/plans/acme-$JKEY-lean-verdict.md"

gate_cfg() { # gate_cfg <config> <progress-file> <args...>
  # unset RUN_ID CLAUDE_CODE_SESSION_ID: same ambient-leak pinning as gate(); see its comment.
  local cfg="$1" prog="$2"; shift 2
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" bash "$GATE" "$@" 2>&1 )
}
seed_progress_1_to_4_at() {
  rm -f "$1"
  { echo "# lean run — issue $JKEY"; echo "run_id: r-j"; } > "$1"
  local m
  for m in 1 2 3 4; do echo "2026-01-01T00:00:00Z | milestone-$m | satisfied" >> "$1"; done
  attest_at "$TREE" "$CFG_JIRA" "$1" "$JKEY"
}

# An unrecognized tracker.type must be LOUD. Falling through to github would run the
# write-happy arm against whatever tracker the typo meant — the exact failure this closes.
out="$(gate_cfg "$CFG_BOGUS" "$WORK/p-bogus.md" 1 7)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "unknown tracker.type" <<<"$out"; then
  pass "(n1) an unrecognized tracker.type is an environment error, not a silent github fall-through"
else fail "(n1) expected rc=2 on tracker.type 'gitlab', got $rc: $out"; fi

# ---- jira PR-body fixtures (milestone 5) ----
cat > "$WORK/pr-jira-ok.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n### Jira Items\n\nCloses [$JKEY]\n" }]
EOF
cat > "$WORK/pr-jira-nokey.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n" }]
EOF
cat > "$WORK/pr-jira-noverdict.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\n\n### Jira Items\n\nCloses [$JKEY]\n" }]
EOF
# The SECTION is the contract, not the token: a key mentioned elsewhere with an empty Jira
# Items section is what a half-filled template actually looks like.
cat > "$WORK/pr-jira-unsectioned.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Closes [$JKEY] eventually.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n### Jira Items\n\n_none yet_\n\n### Notes\n\nCloses [$JKEY]\n" }]
EOF

# AC-1's headline: a ready PR + sectioned key + verdict path passes against an EMPTY comment
# trail. Under github that same trail is a hard failure — which is the whole point.
seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-ok.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(n2) jira milestone-5 passes on a ready PR carrying 'Closes [$JKEY]' + the verdict path, against an EMPTY comment trail"
else fail "(n2) expected rc=0 under jira, got $rc: $out"; fi

seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-nokey.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "no 'Closes [$JKEY]'" <<<"$out"; then
  pass "(n3) jira milestone-5 fails a body with no sectioned ticket reference"
else fail "(n3) expected rc=1 on a key-less body, got $rc: $out"; fi

seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-noverdict.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not reference the verdict record' <<<"$out"; then
  pass "(n4) jira milestone-5 fails a body that does not reference the verdict record"
else fail "(n4) expected rc=1 on a verdict-less body, got $rc: $out"; fi

seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-unsectioned.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "no 'Closes [$JKEY]'" <<<"$out"; then
  pass "(n5) jira milestone-5 fails when the key appears only OUTSIDE the Jira Items section"
else fail "(n5) expected rc=1 on an unsectioned key, got $rc: $out"; fi

# The draft rejection (D-27) holds for BOTH adapters — jira's draft-PR rationale belongs to
# the `run` lane's manual promotion step, which lean has no counterpart for.
cat > "$WORK/pr-jira-draft.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": true,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n### Jira Items\n\nCloses [$JKEY]\n" }]
EOF
seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-draft.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'still a draft' <<<"$out"; then
  pass "(n6) jira milestone-5 still rejects a draft PR (D-27 holds for both adapters)"
else fail "(n6) expected rc=1 on a jira draft PR, got $rc: $out"; fi

# AC-3: the github default is ASSERTED, not assumed. Same jira-shaped body, under a config
# with tracker.type ABSENT and under one that spells it out — both must take the github arm,
# which this body cannot satisfy.
seed_progress_1_to_4_at "$WORK/p-default.md"
out="$(gate_cfg "$CFG" "$WORK/p-default.md" 5 "$JKEY" --pr-file "$WORK/pr-jira-ok.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "no 'Closes #$JKEY'" <<<"$out"; then
  pass "(n7) with tracker.type ABSENT the github arm runs — a jira-shaped body is rejected"
else fail "(n7) expected the github Closes-# failure with tracker.type absent, got $rc: $out"; fi

seed_progress_1_to_4_at "$WORK/p-explicit.md"
out2="$(gate_cfg "$CFG_GITHUB" "$WORK/p-explicit.md" 5 "$JKEY" --pr-file "$WORK/pr-jira-ok.json" --comments-file "$WORK/comments-none.json")"; rc2=$?
if [ "$rc2" -eq "$rc" ] && grep -qF "no 'Closes #$JKEY'" <<<"$out2"; then
  pass "(n8) an explicit tracker.type: github behaves identically to the absent default"
else fail "(n8) explicit github diverged from the default — rc=$rc2: $out2"; fi

# ---- jira claim: zero tracker calls, and no GH_BOT required --------------------------------
# The proof has two halves, because either alone is weak. `env -u GH_BOT` closes the
# `${GH_BOT:?}` path (the github arm dies there, so surviving it is evidence). The PATH spy
# closes everything else: any `gh` the arm reached for lands in the log and exits 1.
mkdir -p "$WORK/bin"
SPY_LOG="$WORK/tracker-calls.log"
cat > "$WORK/bin/gh" <<EOF
#!/bin/sh
echo "gh \$*" >> "$SPY_LOG"
exit 1
EOF
chmod +x "$WORK/bin/gh"
rm -f "$SPY_LOG" "$PROG_J" "$TREE/.claude/pipeline-state/$JKEY-run-id"
attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"

out="$( cd "$TREE" && env -u GH_BOT PATH="$WORK/bin:$PATH" SECOND_SHIFT_CONFIG="$CFG_JIRA" \
        LEAN_PROGRESS_FILE="$PROG_J" RUN_ID="jira-run-1" bash "$GATE" claim "$JKEY" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$SPY_LOG" ]; then
  pass "(n9) jira claim exits 0 with NO GH_BOT in the environment and makes zero tracker calls"
else fail "(n9) expected rc=0 and an empty spy log, got rc=$rc, log='$(cat "$SPY_LOG" 2>/dev/null)': $out"; fi

# The record is the point: no write happens, but lean-reconcile.sh's run-id anchor must
# still land or the run stops being reconcilable. The header this asserts against was created
# `unset` by `entry` above — SKILL.md's own ordering — so this also pins the heal: without it
# the anchor freezes at `unset` and reconcile arm (1) reds every honest run.
if grep -q '^run_id: jira-run-1$' "$PROG_J" 2>/dev/null && grep -qF '| claim | tracker=jira |' "$PROG_J" 2>/dev/null; then
  pass "(n10) jira claim still records the run id and a claim line in the progress file"
else fail "(n10) progress file missing the jira claim record: $(cat "$PROG_J" 2>/dev/null)"; fi

# ---- the entry note ------------------------------------------------------------------------
printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/sess-jira.jsonl"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_JIRA" LEAN_PROGRESS_FILE="$PROG_J" \
        env -u RUN_ID CLAUDE_CODE_SESSION_ID=sess-jira bash "$GATE" entry "$JKEY" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'no queue label to confirm' <<<"$out"; then
  pass "(n11) entry prints the jira adapter note — step 1's label reject has no jira meaning"
else fail "(n11) expected the jira entry note, got rc=$rc: $out"; fi

out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u RUN_ID CLAUDE_CODE_SESSION_ID=sess-jira bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'no queue label to confirm' <<<"$out"; then
  pass "(n12) the github arm prints no adapter note"
else fail "(n12) the adapter note leaked into the github arm: $out"; fi

rm -f "$TREE/.claude/pipeline-state/$JKEY-run-id"

# ---- the section boundary: both regexes must mean the same thing by "heading" -------------
# An asymmetric pair is a false-ACCEPT, and false accepts are the direction that matters in a
# gate. The two cases pin the two halves against each other: a space-less `###Jira Items` must
# not OPEN (it is literal text, not an ATX heading), and — the same rule read the other way —
# a space-less `###Notes` must not CLOSE, because content under it still renders inside the
# section a real heading opened. Only one of these can be got wrong at a time; together they
# make the symmetry non-optional.
cat > "$WORK/pr-jira-openless.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n###Jira Items\n\nCloses [$JKEY]\n" }]
EOF
seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-openless.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF "no 'Closes [$JKEY]'" <<<"$out"; then
  pass "(n13) a space-less '###Jira Items' does not open a section — it is not an ATX heading"
else fail "(n13) expected rc=1 on a space-less opening heading, got $rc: $out"; fi

cat > "$WORK/pr-jira-closeless.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n### Jira Items\n\n###Notes\n\nCloses [$JKEY]\n" }]
EOF
seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-closeless.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(n14) a space-less '###Notes' does not close the section — the boundary rule is symmetric"
else fail "(n14) expected rc=0 (the key still renders inside the section), got $rc: $out"; fi

# The heading match folds case, like the `-i` on the ticket-reference grep. `### JIRA Items`
# is the likelier consumer template — the repo's own jira prose caps the acronym throughout —
# and a case-sensitive match would make it a false-REJECT that burns milestone 5 to rc=4.
cat > "$WORK/pr-jira-caps.json" <<EOF
[{ "number": 11, "url": "https://example.invalid/pr/11", "isDraft": false,
   "body": "Summary line.\n\nSpec: $JSPEC_REL\nVerdict: $JVERDICT_REL\n\n### JIRA Items\n\nCloses [$JKEY]\n" }]
EOF
seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-caps.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(n15) '### JIRA Items' is accepted — the heading match folds case, like the Closes grep"
else fail "(n15) expected rc=0 on an all-caps heading, got $rc: $out"; fi

# (n16) AC-17/#533 AC-3: milestone 1 — the one milestone the jira arm reaches outside milestone
# 5, and the only case in this file that drives it. `check_pause_and_ask` skips the ISSUE-BODY
# read under jira (no `gh issue` to read there), but #533 made the pre-flight-ledger read
# UNCONDITIONAL — so jira is no longer a blanket short-circuit, and the four cases below prove
# the reachability is genuine rather than an accident of an unrelated fixture never hitting it.
mkdir -p "$TREE/docs/plans"
printf '# lean spec — %s\n\n- **AC-1**: the jira arm reaches milestone 1.\n' "$JKEY" > "$TREE/$JSPEC_REL"
commit_tree "jira spec fixture"
JLEDGER_OR1="$WORK/ledger-jira-or1.md"
printf '## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | Ordering guarantee | pause-and-ask |\n' > "$JLEDGER_OR1"

# (n16a) no ledger at all (the resolved default path, under jira's own $STATE_DIR, is absent) —
# clear, same as any ticket that never went through pre-flight. --issue-file is passed anyway
# (an unresolved region, were the body read) to prove this rc=0 is the ledger's own absence
# talking, not the issue-body skip alone.
rm -f "$PROG_J"; attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 1 "$JKEY" --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(n16a) jira milestone 1: no ledger present is clear, regardless of what the (unread) issue body declares"
else fail "(n16a) expected rc=0 under tracker.type: jira with no ledger, got $rc: $out"; fi

# (n16b) #533 AC-3 non-vacuity: an unresolved pause-and-ask region IN THE LEDGER refuses
# milestone 1 under jira — the guard is genuinely reachable there, not merely not-crashing.
rm -f "$PROG_J"; attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 1 "$JKEY" --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json" --ledger-file "$JLEDGER_OR1")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(n16b) #533 AC-3: an unresolved ledger region refuses jira milestone 1 — the guard is reachable, not skipped"
else fail "(n16b) expected rc=1 naming OR-1 under tracker.type: jira, got $rc: $out"; fi

# (n16c) the comment trail is NOT consulted under jira, even when one is supplied and would
# resolve the region under github — comments-or1-resolved.json (defined above, (y3)) carries a
# non-bot comment naming OR-1. Its presence changing nothing here is what proves jira's
# `comments="[]"` default, not merely that this fixture happens to carry no resolving comment.
rm -f "$PROG_J"; attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 1 "$JKEY" --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-or1-resolved.json" --ledger-file "$JLEDGER_OR1")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'region OR-1' <<<"$out"; then
  pass "(n16c) a comment naming OR-1 does not resolve it under jira — no comment trail this check reads"
else fail "(n16c) expected rc=1 (comment trail ignored) under tracker.type: jira, got $rc: $out"; fi

# (n16d) the tracker-agnostic resolution artifact still works: a ratified intent-gap record
# clears the same ledger region under jira, with no comment trail available at all.
JGAP="$TREE/docs/plans/acme-$JKEY-lean-intent-gap.md"
printf 'region: OR-1\nratified: yes\nratified_by: https://example.invalid/browse/%s#comment-1\n' "$JKEY" > "$JGAP"
commit_tree "ratified intent-gap for jira OR-1"
rm -f "$PROG_J"; attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 1 "$JKEY" --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json" --ledger-file "$JLEDGER_OR1")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(n16d) a ratified intent-gap record clears a ledger region under jira, with no comment trail"
else fail "(n16d) expected rc=0 with a ratified intent-gap record under tracker.type: jira, got $rc: $out"; fi
rm -f "$JGAP"; commit_tree "remove jira intent-gap fixture"

rm -f "$TREE/$JSPEC_REL"; commit_tree "remove jira spec fixture"

rm -f "$TREE/.claude/pipeline-state/$JKEY-run-id"

# ---- (v) the verdict WRITER still refuses an unresolvable base ------------------------------
# #720 deleted milestone 4's two freshness arms, and with them (v0)-(v4), (v5), (vb-baseline),
# (vb0)-(vb4a) — every case whose subject was a comparison this gate no longer makes. The question
# they drove is asked once now, by lean-evidence.sh's arm_freshness at the merge boundary, and
# lean-evidence-selftest.sh's (r)/(s2)/(s4) pin it there including the #597 fail-open route.
#
# (v6) is NOT one of those. Its subject is `cmd_verdict`, the WRITER, which still resolves the
# branch's patch identity and still `envfail`s rather than omit the key — and after #720 that
# refusal is the ONLY thing standing between a key-less record and a merge boundary that rejects
# one outright, so it is the arm with the most to lose from going unpinned, not the least.
#
# D-5 vacuity, WRITE side. A record written with the key silently OMITTED reads downstream as
# "written before the key existed", which lean-evidence.sh refuses on every consumer's PR — so a
# missing base here would produce an unmergeable record at review time, invisibly.
#
# seed_build_progress is load-bearing, not tidy-up: the cases above ran after reset_progress, so
# the gate RE-created the progress file and stamped `session_id: unset` into it. cmd_verdict's
# FIRST authorship refusal fires on exactly that, two checks before the patch-id arm this case
# names — so without the seed (v6) passes for the wrong reason where an ambient session id happens
# to leak in, and fails outright where it does not. Seeding a real build identity makes the writer
# reach its own arm on every machine.
reset_progress
CFG_NOBASE="$WORK/config-nobase.json"
jq '.topology.repos.acme.baseBranch = "no-such-base"' "$CFG" > "$CFG_NOBASE"
[ "$(jq -r '.topology.repos.acme.baseBranch' "$CFG_NOBASE" 2>/dev/null)" = "no-such-base" ] \
  || fail "(v6-fixture) the no-base config was not built — (v6) would run against the real base"
seed_build_progress r-build-1 sess-build-1
rm -f "$REVIEW_CACHE"
out="$( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOBASE" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-review-9 RUN_ID=r-review-9 \
        bash "$GATE" verdict 7 --pr 12 --verdict approve 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'cannot compute the branch' <<<"$out"; then
  pass "(v6) the verdict writer refuses an unresolvable base rather than omitting the key downstream cannot do without"
else fail "(v6) expected rc=2 from the writer on an unresolvable base, got $rc: $out"; fi


# ---- (w) --help prints the header, and only the header ------------------------------------
# `sed -n '2,Np'` is a hand-maintained line number: growing the header silently truncates the
# help text. check-lean-chain-selftest.sh case (T) has guarded its sibling for exactly this;
# this file had no such case, which is why a green sweep said nothing when the header here grew
# by 8 lines and the range stayed at 2,75p — dropping the whole Seams block from --help.
#
# Two assertions, because either direction is a real failure AND because the repo's two lanes
# kill the `cmp-z` mutant of this line by opposite halves: on BSD sed `-z` dies and only the
# presence assertion fires; on GNU sed `-z` dumps the whole file and only the absence one does.
out="$(bash "$GATE" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q 'bash 3.2 compatible' <<<"$out" \
   && ! grep -q '^set -uo pipefail' <<<"$out"; then
  pass "(w) --help prints through the last header line and stops before the code"
else fail "(w) --help did not print exactly the header, rc=$rc: $out"; fi

# ---- (x) the INHERITANCE CHAIN: a fix round reads the delta, not the whole diff (#375) ------
# ITS OWN FIXTURE TREE, and that is an assertion rather than tidiness. Every block above commits
# verdict records into $TREE, and inherit_candidate walks that path's ENTIRE history — so an
# "a round-1 record inherits nothing" case run in $TREE would silently inherit whatever an
# earlier block last wrote, and pass for a reason unrelated to the property it names.
#
# The records are produced by the REAL writer throughout. Where a case needs a corrupt record
# (there is no honest way to write one), it corrupts a production-written record's ONE key and
# leaves every other key production-derived.
XTREE="$WORK/xtree"
mkdir -p "$XTREE/docs/plans" "$XTREE/.claude"
git -C "$XTREE" init -q
git -C "$XTREE" config user.email t@example.invalid
git -C "$XTREE" config user.name t
printf '.claude/\n' > "$XTREE/.gitignore"
XSPEC="$XTREE/docs/plans/acme-9-lean.md"
XVERDICT="$XTREE/docs/plans/acme-9-lean-verdict.md"
XVERDICT_REL="docs/plans/acme-9-lean-verdict.md"
XPROG="$WORK/xprogress.md"

xcommit() {
  git -C "$XTREE" add -A >/dev/null 2>&1
  git -C "$XTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
xgate() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$XTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$XPROG" bash "$GATE" "$@" 2>&1 ); }
xverdict() { # xverdict <session-id> <run-id> [args...]
  local sid="$1" rid="$2"; shift 2
  rm -f "$XTREE/.claude/pipeline-state/9-review-run-id"
  ( unset RUN_ID; cd "$XTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$XPROG" \
    CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$GATE" verdict 9 "$@" 2>&1 )
}
xseed_build() { rm -f "$XPROG"; { echo "# lean run — issue 9"; echo ""; echo "run_id: r-build-x"; echo "session_id: sess-build-x"; } > "$XPROG"
                attest_at "$XTREE" "$CFG" "$XPROG" 9; }
xkey() { grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$XVERDICT" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"; }

xcommit "base"
git -C "$XTREE" update-ref refs/remotes/origin/main HEAD
printf '# spec\n\n- AC-1: the thing\n' > "$XSPEC"
printf 'reviewed in round 1, never touched again\n' > "$XTREE/untouched.txt"
printf 'reviewed in round 1, and the fix will touch it\n' > "$XTREE/refixed.txt"
xcommit "the branch's work"

attest_at "$XTREE" "$CFG" "$XPROG" 9
# (x0) nothing committed to review yet: the FULL range, said so out loud. The degrade message is
# the same one a BROKEN chain produces, which is why (x6) asserts the diagnostic beside it.
out="$(xgate delta 9)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'FULL range' <<<"$out" \
   && grep -q 'untouched.txt' <<<"$out" && grep -q 'refixed.txt' <<<"$out"; then
  pass "(x0) with no prior record, delta prints the whole branch diff"
else fail "(x0) expected a full-range delta, rc=$rc: $out"; fi

# (x1) ROUND 1 is a chain ROOT, and declares that in as many words: the key is WRITTEN with a
# `none` sentinel, not omitted. AC-4's write side — additive at every READER, where a root is
# read as inheriting nothing exactly as a pre-#375 record is, while the WRITER is deliberately
# no longer byte-identical to the pre-#375 shape. A key emitted only sometimes is a key whose
# first occurrence in the file can be the reviewer's own prose; (z1)/(z2) drive that, and the
# always-emitted form is what lets the authentic value win.
#
# `needs-work` deliberately: OR-2 resolved that COVERAGE and VERDICT are separate properties, and
# the issue's whole motivating case is a needs-work round-1 whose coverage round 2 inherits. Were
# that reversed, this record would be uninheritable and every case below would degrade to full.
xseed_build
out="$(xverdict sess-review-x1 r-review-x1 --pr 90 --verdict needs-work --rounds 1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(xkey inherited_patch_id)" = "none" ] \
   && [ "$(xkey inherited_from_verdict)" = "none" ] && [ -n "$(xkey reviewed_patch_id)" ] \
   && grep -q 'chain ROOT' <<<"$out"; then
  pass "(x1) a round-1 record carries reviewed_patch_id and writes both inheritance keys as 'none', and says it is a chain root"
else fail "(x1) expected a root record, rc=$rc: $out
$(cat "$XVERDICT" 2>/dev/null)"; fi
X_R1_PID="$(xkey reviewed_patch_id)"
xcommit "round 1's record"
X_R1_COMMIT="$(git -C "$XTREE" rev-parse HEAD)"

# (x2) AC-2, and the headline claim: the fix touches code round 1 already read, so it is IN the
# delta — while the file the fix did not touch is NOT, which is the half that makes the range a
# narrowing rather than a rename of "the whole diff".
printf 'reviewed in round 1, and the fix touched it\n' > "$XTREE/refixed.txt"
xcommit "the fix the round-1 blockers asked for"
out="$(xgate delta 9)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'inheriting the coverage of patch' <<<"$out" \
   && grep -q 'refixed.txt' <<<"$out" \
   && ! grep -q 'untouched.txt' <<<"$out"; then
  pass "(x2) the delta range is anchored at the inherited patch: the re-touched file is in it, the untouched one is not"
else fail "(x2) expected a narrowed delta naming refixed.txt only, rc=$rc: $out"; fi

# (x3) AC-1, positive: round 2's inheritance is DERIVED — no flag was passed — and it names round
# 1's reviewed patch. Milestone 4 then accepts the record with the chain arm satisfied.
xseed_build
out="$(xverdict sess-review-x2 r-review-x2 --pr 90 --verdict approve --rounds 2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(xkey inherited_patch_id)" = "$X_R1_PID" ] \
   && [ "$(xkey inherited_from_verdict)" = "$X_R1_COMMIT" ]; then
  pass "(x3) round 2 derives inherited_patch_id from round 1's record, with no flag and no argument"
else fail "(x3) expected the derived inheritance keys, rc=$rc: $out
$(cat "$XVERDICT" 2>/dev/null)"; fi
xcommit "round 2's record"
out="$(xgate 4 9)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(x3b) milestone-4 accepts an inheriting round whose link resolves"
else fail "(x3b) expected rc=0 on a resolvable chain, got $rc: $out"; fi

# (x3c) AC-6: inheritance opens no path around P10. Run against the record (x3b) just accepted,
# so the chain resolves perfectly and the authorship arm is the only thing that can red — a case
# built on an already-broken chain would pass on the wrong refusal.
sed -e "s/^run_id: .*/run_id: r-build-x/" "$XVERDICT" > "$XVERDICT.tmp" && mv "$XVERDICT.tmp" "$XVERDICT"
xcommit "the record claims the build run's identity"
out="$(xgate 4 9)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q "BUILD run's identity" <<<"$out"; then
  pass "(x3c) a round-n record carrying the build run's identity is refused exactly as before, chain or no chain"
else fail "(x3c) expected the P10 refusal on an inheriting round, got $rc: $out"; fi

# (x4) SELF-INHERITANCE, the failure the "differs from this round's patch" clause exists for.
# review-lean re-runs a round on its cached identity, and at that moment the newest committed
# record IS this round's own. Without the clause the re-run would inherit itself, which every
# reader then refuses as a loop — a correct round made permanently unmergeable by being checked.
xseed_build
out="$(xverdict sess-review-x2 r-review-x2 --pr 90 --verdict approve --rounds 2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(xkey inherited_patch_id)" = "$X_R1_PID" ]; then
  pass "(x4) re-running a round is idempotent — it inherits round 1 again, never itself"
else fail "(x4) expected the same inherited link on a re-run, rc=$rc: $(xkey inherited_patch_id)"; fi
xcommit "round 2's record, re-run"

# (x5) REBASE INVARIANCE, the reason the chain is matched by content and not by SHA. A rebase
# rewrites every commit SHA on the branch — including the ones carrying the earlier records — and
# changes not one reviewed line. A SHA-linked chain would resolve to nothing here.
#
# Non-vacuity is asserted, not argued: the base advances by a commit carrying real content, and
# the pre-rebase head must actually be gone from the branch.
x_pre_rebase_head="$(git -C "$XTREE" rev-parse HEAD)"
x_branch="$(git -C "$XTREE" symbolic-ref --short HEAD 2>/dev/null)"
git -C "$XTREE" branch -f x-base refs/remotes/origin/main >/dev/null 2>&1
git -C "$XTREE" checkout -q x-base 2>/dev/null
printf 'the base moved while the rounds were in flight\n' > "$XTREE/base-moved.txt"
git -C "$XTREE" add base-moved.txt >/dev/null 2>&1
git -C "$XTREE" commit -q -m 'base advances' >/dev/null 2>&1
git -C "$XTREE" update-ref refs/remotes/origin/main x-base
git -C "$XTREE" checkout -q "$x_branch" 2>/dev/null
x_rebased=0
git -C "$XTREE" rebase -q x-base >/dev/null 2>&1 && x_rebased=1 || git -C "$XTREE" rebase --abort >/dev/null 2>&1
if [ "$x_rebased" -eq 1 ] && [ "$(git -C "$XTREE" rev-parse HEAD)" != "$x_pre_rebase_head" ] \
   && ! git -C "$XTREE" merge-base --is-ancestor "$X_R1_COMMIT" HEAD 2>/dev/null; then
  pass "(x5a) the fixture really was rebased, and round 1's original record commit is no longer on the branch"
else fail "(x5a) the rebase did not take (ok=$x_rebased) — (x5) would assert nothing"; fi
out="$(xgate 4 9)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(x5) the inheritance chain survives a rebase — it is keyed on patch identity, not on the commit SHAs the rebase replaced"
else fail "(x5) expected rc=0 after a clean rebase, got $rc: $out"; fi

# (x6) AC-5: a declared link matching no committed record is REFUSED, never quietly downgraded to
# "treat it as a root record" — that downgrade would turn an unverifiable claim into a satisfied
# one, which is the whole failure mode the chain exists to prevent.
#
# Shaped so the chain arm is the ONLY one that can red: the record's own bytes are excluded from
# the patch identity and tolerated by the inferred-freshness arm, so corrupting one of its keys
# and committing leaves every other milestone-4 check green.
sed -e "s/^inherited_patch_id:.*/inherited_patch_id: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef/" "$XVERDICT" > "$XVERDICT.tmp" \
  && mv "$XVERDICT.tmp" "$XVERDICT"
xcommit "the record's declared link is corrupted"
out="$(xgate 4 9)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'matches no earlier verdict record committed on this branch' <<<"$out" \
   && grep -q 'round 2 declares' <<<"$out"; then
  pass "(x6) milestone-4 refuses an unresolvable inheritance link, naming the round that declared it"
else fail "(x6) expected rc=5 naming round 2, got $rc: $out"; fi

# (x7) AC-3: the round NAMED is the round that BROKE the chain, not the round that declared the
# link being walked. Round 3's own link resolves fine; it is round 2's that dangles, and a
# message naming round 3 would send the operator to the wrong record.
#
# Round 3's record is written by the real writer (so reviewed_patch_id stays production-derived)
# and then has its link appended by hand — the writer, correctly, degrades to a root record here
# BECAUSE the chain below it is broken, which is (x8)'s assertion.
printf 'a third round of fixes\n' > "$XTREE/refixed.txt"
xcommit "the round-2 blockers get fixed too"
X_R2_PID="$(git -C "$XTREE" show "HEAD~1:$XVERDICT_REL" 2>/dev/null | grep -oE 'reviewed_patch_id:[[:space:]]*[A-Za-z0-9._-]+' | head -n1 | sed -E 's/^reviewed_patch_id:[[:space:]]*//')"
xseed_build
out="$(xverdict sess-review-x3 r-review-x3 --pr 90 --verdict approve --rounds 3)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(xkey inherited_patch_id)" = "none" ] \
   && grep -q 'inherits nothing' <<<"$out"; then
  pass "(x8) the writer degrades to a ROOT record when the chain beneath it is broken, and says so"
else fail "(x8) expected a loud degrade to root, rc=$rc: $out
$(cat "$XVERDICT" 2>/dev/null)"; fi
# The hand-declared link REPLACES the sentinel in the header. Appending it to the end of the
# file — which is what this line did while the key was read first-match-anywhere — now declares
# nothing at all, because the readers are header-anchored. That is the guard working: a value
# below the body is exactly what a reviewer's prose is.
sed -e "s/^inherited_patch_id:.*/inherited_patch_id: $X_R2_PID/" "$XVERDICT" > "$XVERDICT.tmp" \
  && mv "$XVERDICT.tmp" "$XVERDICT"
xcommit "round 3 declares the link by hand"
out="$(xgate 4 9)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'round 2 declares' <<<"$out" \
   && ! grep -q 'round 3 declares' <<<"$out"; then
  pass "(x7) the refusal names round 2 — the round whose link dangles — not round 3, which declared a link that resolves"
else fail "(x7) expected the break to be attributed to round 2, got $rc: $out"; fi

# ---- (y) the search window never includes the record being read (#375) ----------------------
# ITS OWN TREE: this needs a clean three-round chain, and the (x) block ends with two records
# deliberately corrupted.
#
# The only shape that distinguishes a window bounded below the record from an unbounded one is
# SELF-INHERITANCE — a record whose inherited_patch_id is its own reviewed_patch_id — over a
# branch reverted to a tree an earlier round reviewed. Unbounded, the walk resolves that round to
# ITSELF, counts the record under test as a link in its own chain, and still PASSES: one link
# longer, every link after it shifted, exit code unchanged. The count in milestone 4's pass line
# is what makes that visible from outside; without it the two behaviors are indistinguishable and
# the window is a comment rather than a guard.
#
# The writer never produces such a record (inherit_candidate requires a DIFFERING patch), so the
# link is set by hand — on a record whose every other key the production writer derived.
YTREE="$WORK/ytree"
mkdir -p "$YTREE/docs/plans" "$YTREE/.claude"
git -C "$YTREE" init -q
git -C "$YTREE" config user.email t@example.invalid
git -C "$YTREE" config user.name t
printf '.claude/\n' > "$YTREE/.gitignore"
YVERDICT="$YTREE/docs/plans/acme-11-lean-verdict.md"
YPROG="$WORK/yprogress.md"
ycommit() {
  git -C "$YTREE" add -A >/dev/null 2>&1
  git -C "$YTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
ygate() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$YTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$YPROG" bash "$GATE" "$@" 2>&1 ); }
yverdict() { # yverdict <session-id> <run-id> [args...]
  local sid="$1" rid="$2"; shift 2
  rm -f "$YPROG"; { echo "# lean run — issue 11"; echo ""; echo "run_id: r-build-y"; echo "session_id: sess-build-y"; } > "$YPROG"
  attest_at "$YTREE" "$CFG" "$YPROG" 11
  rm -f "$YTREE/.claude/pipeline-state/11-review-run-id"
  ( unset RUN_ID; cd "$YTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$YPROG" \
    CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$GATE" verdict 11 "$@" 2>&1 )
}
ykey() { grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$YVERDICT" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"; }

ycommit "base"
git -C "$YTREE" update-ref refs/remotes/origin/main HEAD
printf '# spec\n\n- AC-1: the thing\n' > "$YTREE/docs/plans/acme-11-lean.md"
printf 'round 1 reviewed this\n' > "$YTREE/subject.txt"
ycommit "the branch's work"
out="$(yverdict sess-review-y1 r-review-y1 --pr 91 --verdict needs-work --rounds 1)"; rc=$?
[ "$rc" -eq 0 ] || fail "(y0) the round-1 writer refused, so (y) has no chain to walk: $out"
Y_PID_A="$(ykey reviewed_patch_id)"
ycommit "round 1's record"

printf 'the fix round 1 asked for\n' > "$YTREE/subject.txt"
ycommit "the fix"
out="$(yverdict sess-review-y2 r-review-y2 --pr 91 --verdict approve --rounds 2)"; rc=$?
[ "$rc" -eq 0 ] || fail "(y0) the round-2 writer refused: $out"
ycommit "round 2's record"

# The revert: round 3's tree IS round 1's, so its reviewed patch is an identity an ancestor
# record also carries. That is the precondition — without an ancestor to resolve to, the walk has
# nothing but the record itself and both behaviors refuse identically.
printf 'round 1 reviewed this\n' > "$YTREE/subject.txt"
ycommit "the round-2 fix is reverted"
out="$(yverdict sess-review-y3 r-review-y3 --pr 91 --verdict approve --rounds 3)"; rc=$?
[ "$rc" -eq 0 ] || fail "(y0) the round-3 writer refused: $out"
Y_PID_REV="$(ykey reviewed_patch_id)"
if [ "$Y_PID_REV" = "$Y_PID_A" ]; then
  pass "(y1) the revert restored round 1's patch identity — the self-inheritance case has an ancestor to resolve to"
else fail "(y1) the reverted tree hashes to $Y_PID_REV, not round 1's $Y_PID_A — (y2) would assert nothing"; fi
sed -e "s/^inherited_patch_id:.*/inherited_patch_id: $Y_PID_REV/" "$YVERDICT" > "$YVERDICT.tmp" && mv "$YVERDICT.tmp" "$YVERDICT"
ycommit "round 3 declares its own reviewed patch as the one it inherited"
out="$(ygate 4 11)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'inheriting 1 verified earlier round' <<<"$out"; then
  pass "(y2) a self-inheriting record resolves to the ANCESTOR carrying that patch, counted once — the window never includes the record being read"
else fail "(y2) expected rc=0 with exactly 1 inherited link, got $rc: $out"; fi

# ---- (z) the record's own BODY cannot supply the inheritance key it is read on (#375) -------
# The key is the schema's first CONDITIONALLY-emitted one, and the mitigation the rest of the
# schema rests on — "the authentic value is written above the body, so it wins first-match" —
# has no winner when the writer emitted nothing. The first match is then whatever the reviewer's
# findings contain, and a review of a PR about inheritance quotes these keys as a matter of
# course. Reached in production before it was reached here: a round-1 `approve` written by the
# real writer with no hand-editing took the merge boundary red on a value from line 71 of its
# own body.
#
# Both halves of the fix are driven: the writer's `none` sentinel (asserted in (x1)) and the
# header-anchored read (here). The body values below are placed by `--summary-file`, which is
# the production path a reviewer's findings actually arrive through — not by appending to the
# record afterwards, which no role does.
#
# ITS OWN TREE, for the reason the (x) block states: inherit_candidate walks the whole history
# of the record path, and (x)/(y) end with records deliberately corrupted.
ZTREE="$WORK/ztree"
mkdir -p "$ZTREE/docs/plans" "$ZTREE/.claude"
git -C "$ZTREE" init -q
git -C "$ZTREE" config user.email t@example.invalid
git -C "$ZTREE" config user.name t
printf '.claude/\n' > "$ZTREE/.gitignore"
ZVERDICT="$ZTREE/docs/plans/acme-12-lean-verdict.md"
ZVERDICT_REL="docs/plans/acme-12-lean-verdict.md"
ZPROG="$WORK/zprogress.md"
zcommit() {
  git -C "$ZTREE" add -A >/dev/null 2>&1
  git -C "$ZTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
zgate() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$ZTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$ZPROG" bash "$GATE" "$@" 2>&1 ); }
zverdict() { # zverdict <session-id> <run-id> [args...]
  local sid="$1" rid="$2"; shift 2
  rm -f "$ZPROG"; { echo "# lean run — issue 12"; echo ""; echo "run_id: r-build-z"; echo "session_id: sess-build-z"; } > "$ZPROG"
  attest_at "$ZTREE" "$CFG" "$ZPROG" 12
  rm -f "$ZTREE/.claude/pipeline-state/12-review-run-id"
  ( unset RUN_ID; cd "$ZTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$ZPROG" \
    CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$GATE" verdict 12 "$@" 2>&1 )
}
zkey() { grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$ZVERDICT" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"; }

zcommit "base"
git -C "$ZTREE" update-ref refs/remotes/origin/main HEAD
printf '# spec\n\n- AC-1: the thing\n' > "$ZTREE/docs/plans/acme-12-lean.md"
printf 'round 1 reviewed this\n' > "$ZTREE/subject.txt"
zcommit "the branch's work"

# (z1) THE PRODUCTION SHAPE, and the one that was reached: a chain ROOT whose findings quote an
# inheritance key resolving to nothing. Read first-match, the record declares a dangling link and
# every reader refuses it — with a remedy ("get a round that reads the full diff") that is
# unreachable, since a fresh round writing the same finding reproduces the same refusal.
ZBODY="$WORK/zbody-1.md"
{
  echo "## B1 — the reader takes the first match"
  echo ""
  echo '```'
  echo "inherited_patch_id: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  echo "inherited_from_verdict: 1111111111111111111111111111111111111111"
  echo '```'
} > "$ZBODY"
out="$(zverdict sess-review-z1 r-review-z1 --pr 92 --verdict approve --rounds 1 --summary-file "$ZBODY")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(zkey inherited_patch_id)" = "none" ]; then
  pass "(z1a) the writer records a root as 'none' even when the body it was handed quotes the key"
else fail "(z1a) expected the sentinel in the header, rc=$rc: $out
$(cat "$ZVERDICT" 2>/dev/null)"; fi
Z_PID1="$(zkey reviewed_patch_id)"
zcommit "round 1's record, whose findings quote the key"
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'covering the whole branch diff on its own' <<<"$out" \
   && ! grep -q 'matches no earlier verdict record' <<<"$out"; then
  pass "(z1b) milestone 4 reads that record as the ROOT it is — the value in its findings is not a claim"
else fail "(z1b) expected a root read, got rc=$rc: $out"; fi

# (z2) THE DANGEROUS HALF. (z1) fails LOUDLY, which is survivable; this one fails SILENTLY. The
# quoted value here RESOLVES — it is round 1's real reviewed patch — so a first-match reader
# credits this round with coverage no round performed, which is the exact inverse of the property
# the chain exists to prove. rc is 0 in both readings, so only the coverage phrase separates them.
#
# The round is a root for a cause established independently of this fix: the branch is reverted to
# round 1's tree, so the sole candidate fails the "differs from this round's patch" clause that
# (x4) pins. Nothing here depends on the round being a root for the reason under test.
printf 'the fix\n' > "$ZTREE/subject.txt"
zcommit "a fix lands"
printf 'round 1 reviewed this\n' > "$ZTREE/subject.txt"
zcommit "and is reverted, restoring round 1's tree"
ZBODY2="$WORK/zbody-2.md"
{
  echo "## the finding, quoting round 1's own record"
  echo ""
  echo '```'
  echo "inherited_patch_id: $Z_PID1"
  echo '```'
} > "$ZBODY2"
out="$(zverdict sess-review-z2 r-review-z2 --pr 92 --verdict approve --rounds 2 --summary-file "$ZBODY2")"; rc=$?
zcommit "round 2's record, quoting a link that would resolve"
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'covering the whole branch diff on its own' <<<"$out" \
   && ! grep -q 'inheriting 1 verified earlier round' <<<"$out"; then
  pass "(z2) a quoted value that WOULD resolve credits no coverage — the silent half, where both readings exit 0"
else fail "(z2) expected the root coverage phrase and no inherited credit, got rc=$rc: $out"; fi

# (z3) THE SAME DOOR ONE LEVEL DOWN. A chain walk reads PRIOR records the same way, and those may
# predate the sentinel entirely — every branch in flight when this ships carries one. Round 1's
# record is reshaped to exactly that: header keys stripped, the value left in the body where a
# pre-#375 reviewer's findings would have put it. A first-match walk follows it off the branch.
git -C "$ZTREE" checkout -q -- "$ZVERDICT_REL" 2>/dev/null
git -C "$ZTREE" show "$(git -C "$ZTREE" log --format=%H -- "$ZVERDICT_REL" | tail -n1):$ZVERDICT_REL" \
  | grep -v '^inherited_' > "$ZVERDICT.tmp"
{
  cat "$ZVERDICT.tmp"
  echo ""
  echo "a pre-sentinel round's findings: inherited_patch_id: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
} > "$ZVERDICT"
rm -f "$ZVERDICT.tmp"
if ! grep -q '^inherited_patch_id:' "$ZVERDICT" && grep -q 'inherited_patch_id: deadbeef' "$ZVERDICT"; then
  pass "(z3a) the fixture really is a pre-sentinel record — no header key, and the value only in the body"
else fail "(z3a) the legacy-shape rewrite did not take, so (z3b) would assert nothing: $(cat "$ZVERDICT")"; fi
zcommit "round 1's record, rewritten in the pre-sentinel shape"
printf 'the fix round 1 asked for\n' > "$ZTREE/subject.txt"
zcommit "the fix"
out="$(zverdict sess-review-z3 r-review-z3 --pr 92 --verdict approve --rounds 2)"; rc=$?
Z_PID2="$(zkey reviewed_patch_id)"
if [ "$rc" -eq 0 ]; then
  pass "(z3b) the writer's own chain walk terminates at a pre-sentinel root instead of following its body"
else fail "(z3b) the writer refused over a value in a prior record's body: $out"; fi

# (z4) ORDER: "is this record on the branch at all" is asked BEFORE "does its chain resolve". The
# walk's window is anchored at the commit carrying the record, so an UNCOMMITTED round-2 record
# anchors on round 1's commit, the window trims round 1 away, and the legitimate link the record
# declares matches nothing left. Fail-closed either way — but one message says "commit it" and the
# other sends the reviewer to redo a round over a record whose only defect is an unrun git commit.
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'uncommitted changes' <<<"$out" \
   && ! grep -q 'matches no earlier verdict record' <<<"$out"; then
  pass "(z4) an uncommitted round-2 record is refused for being uncommitted, not for a chain its own state broke"
else fail "(z4) expected the uncommitted refusal without a chain diagnostic, got rc=$rc: $out"; fi
zcommit "round 2's record"
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'inheriting 1 verified earlier round' <<<"$out"; then
  pass "(z4b) committed, the same record passes with its one link — so (z4) turned on the commit and nothing else"
else fail "(z4b) expected a 1-link pass once committed, got rc=$rc: $out"; fi

# (z5) A ROUND MAY NOT LINK TO ITS OWN EARLIER VERSION. review-lean permits re-running a round on
# its cached identity; if the branch moved in between, that round's own committed record differs
# from the current tree on CONTENT and so passes the "differs" clause while being the same review.
# The link it produces resolves for two readers — milestone 4 and the merge boundary each count a
# round that never happened — and lean-reconcile.sh refuses it, so three readers disagree about a
# record the production writer emitted. Fixed at the writer: the candidate is skipped and the
# search continues to the last INDEPENDENT round, which is round 1 here.
printf 'the branch moves between two runs of round 2\n' > "$ZTREE/subject.txt"
zcommit "the branch moves"
out="$(zverdict sess-review-z3 r-review-z3 --pr 92 --verdict approve --rounds 2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(zkey inherited_patch_id)" = "$Z_PID1" ] \
   && [ "$(zkey inherited_patch_id)" != "$Z_PID2" ]; then
  pass "(z5) a re-run round inherits the last INDEPENDENT round, never the earlier version of itself"
else fail "(z5) expected the link to be round 1's $Z_PID1, got $(zkey inherited_patch_id) (its own prior version is $Z_PID2), rc=$rc: $out"; fi
zcommit "round 2's record, re-run after the branch moved"
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'inheriting 1 verified earlier round' <<<"$out"; then
  pass "(z5b) and the chain it writes is one link, not the two a self-link would have counted"
else fail "(z5b) expected a 1-link chain after the re-run, got rc=$rc: $out"; fi

# ---- (d) the DESIGN RENDER LANE (#394) ------------------------------------------------------
# Three failure classes from a design-driven consumer run, each with its own arm here:
#   (2) a PASSING render that captured the default collapsed state and verified nothing
#       → the RS table + {state} + the identical-hash collision detector, (dr1)/(dr3)/(dr6);
#   (1) a NON-BLOCKING degrade that shipped five visual defects
#       → blocking on the fix budget, (dr4)/(dr5) — there is no degraded state to assert;
#   (3) a design-BLIND reviewer that passed while disclaiming it could verify nothing
#       → the `fidelity:` verdict key, (fd*).
#
# ITS OWN FIXTURE TREE, for the reason the (x)/(z) blocks state and one more: this block's cases
# commit render manifests and rewrite .gitignore, and every earlier block's tree is asserted
# against by cases that would silently change meaning if either happened in it.
#
# The render harness is a STUB — deliberately, and it is the level the ACs are written at. The
# real-renderer end-to-end proof is #348's own merge precondition; what is gated HERE is the
# gate's own contract with any harness, so the stub's job is to be arg-asserting (it refuses an
# unsubstituted placeholder rather than quietly rendering) and byte-deterministic.
DTREE="$WORK/dtree"
mkdir -p "$DTREE/docs/plans" "$DTREE/.claude"
git -C "$DTREE" init -q
git -C "$DTREE" config user.email t@example.invalid
git -C "$DTREE" config user.name t
printf '.claude/\n' > "$DTREE/.gitignore"
DSPEC="$DTREE/docs/plans/acme-55-lean.md"
DVERDICT="$DTREE/docs/plans/acme-55-lean-verdict.md"
DMANIFEST="$DTREE/docs/plans/acme-55-lean-renders.md"
DPROG="$WORK/dprogress.md"
DCFG="$WORK/dconfig.json"
DSTUB="$WORK/render-stub.sh"
DCALLS="$WORK/stub-calls.log"
DMODE="$WORK/stub-mode"
# The rects sibling (#711). The PAYLOAD is a file the cases rewrite — the same bytes for every
# state, which is what makes the plan's `RS` column the thing that decides which nodes a state is
# measured on rather than the stub. Its MODE is separate from the render mode: "the harness
# screenshotted and wrote no rects" and "the harness failed" are different states, and the ticket
# puts them on different budgets.
DRECTS="$WORK/stub-rects.json"
DRMODE="$WORK/stub-rects-mode"

# The arg-asserting stub. It exits NONZERO on an unsubstituted `{route}`/`{state}`/`{out}`, so a
# gate that forwarded the template verbatim reds instead of producing a plausible screenshot —
# the assertion AC-3 names, made by the harness rather than by a grep over the gate's stdout.
# Its bytes are a function of route+state, which is what makes two declared states distinguish
# themselves; `blind` mode is the same harness ignoring {state}, i.e. failure class (2).
cat > "$DSTUB" <<EOSTUB
#!/usr/bin/env bash
CALLS="$DCALLS"
MODEF="$DMODE"
RECTSF="$DRECTS"
RMODEF="$DRMODE"
EOSTUB
cat >> "$DSTUB" <<'EOSTUB'
route=""; state=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --route) route="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    --out)   out="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s|%s|%s\n' "$route" "$state" "$out" >> "$CALLS"
mode=ok; [ -f "$MODEF" ] && mode="$(cat "$MODEF")"
case "$route" in ''|*'{route}'*) echo "stub: {route} not substituted ('$route')" >&2; exit 90 ;; esac
case "$out"   in ''|*'{out}'*)   echo "stub: {out} not substituted ('$out')" >&2;     exit 91 ;; esac
case "$mode" in
  fail)  echo "stub: simulated harness failure" >&2; exit 7 ;;
  empty) : > "$out" ;;
  blind) printf 'PNG-%s\n' "$route" > "$out" ;;
  *)
    case "$state" in ''|*'{state}'*) echo "stub: {state} not substituted ('$state')" >&2; exit 92 ;; esac
    printf 'PNG-%s-%s\n' "$route" "$state" > "$out" ;;
esac
rmode=emit; [ -f "$RMODEF" ] && rmode="$(cat "$RMODEF")"
rm -f "$out.rects.json"
case "$rmode" in
  none) : ;;
  bad)  printf 'this is not json\n' > "$out.rects.json" ;;
  *)    if [ -f "$RECTSF" ]; then cat "$RECTSF" > "$out.rects.json"; else printf '{}\n' > "$out.rects.json"; fi ;;
esac
exit 0
EOSTUB

dcfg() { # dcfg <liveRender-command-or-empty> [cwd] [tolerancePx]
  local cmd="${1:-}" cwd="${2:-}" tol="${3:-}" lr=""
  if [ -n "$cmd" ]; then
    lr=", \"liveRender\": { \"command\": \"$cmd\"$([ -n "$cwd" ] && printf ', "cwd": "%s"' "$cwd")$([ -n "$tol" ] && printf ', "tolerancePx": %s' "$tol") }"
  fi
  cat > "$DCFG" <<EOCFG
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } },
  "design": { "provider": "figma"$lr }
}
EOCFG
}
DPLAN="$DTREE/docs/plans/acme-55-lean-plan.md"
DFENCE='```'  # single-quoted: three backticks in double quotes are command substitution
DSYNCCFG="$WORK/dsync-config.json"
DSYNCPROG="$WORK/dsync-progress.md"

DSTUB_CMD="bash $DSTUB --route {route} --state {state} --out {out}"

# The design config dplan_sync() reads: armed, but with NO liveRender command, so the gate stops
# at the harness check the instant the plan pass is satisfied. Syncing must never render into
# fixture state the cases below assert on.
cat > "$DSYNCCFG" <<EOSYNC
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } },
  "design": { "provider": "figma" }
}
EOSYNC

# The armed ticket's translation plan (#694/#711), conforming: a `why this component` table and a
# dimension table declaring `node`/`RS`/`px` beside `dimensions`, every cell filled, and the
# `planned_from:` line the gate stamps.
#
# The component table carries a `node` column of its own AND NO `dimensions` COLUMN, which is the
# shape the measured-node arm has to get right: those three columns are required of the table that
# declares `dimensions`, not of the document, so a `node` column over there is not the answer.
#
# RS-1, because it is the one state EVERY armed spec in this block declares — (dr6b) narrows the
# matrix to the default state alone, and a default row keyed to RS-2 would red it on the
# undeclared-state arm, for a reason that case is not about. A non-default state is measured by
# (dpx12), where that is the subject.
DPLAN_DROW='| Filter panel | RS-1 | 320×604 | fixed 320px wide, hug height | none |'
dplan_write() {
  {
    echo "# translation plan — acme #55"
    echo ""
    echo "planned_from: pending"
    echo ""
    echo "## Resolved components"
    echo ""
    echo "| node | repo component | why this component |"
    echo "| --- | --- | --- |"
    echo "| Filter panel | @acme/ui Drawer | the frame draws a right-edge sheet over a scrim |"
    echo ""
    echo "## Dimensions"
    echo ""
    echo "| node | RS | px | dimensions | overflow |"
    echo "| --- | --- | --- | --- | --- |"
    echo "$DPLAN_DROW"
  } > "$DPLAN"
}

# The rects payload the stub emits for EVERY state, matching the plan above exactly. Rewritten in
# place by the measurement cases; restored by this function, so a case that moves it says so.
DRECTS_OK='{ "Filter panel": { "width": 320, "height": 604 } }'
drects_write() { # drects_write [json]
  printf '%s\n' "${1:-$DRECTS_OK}" > "$DRECTS"
  printf 'emit\n' > "$DRMODE"
}
drects_write

# Bring `planned_from` current using PRODUCTION — the gate stamps it, this never computes a patch
# id itself. A selftest that derived the id would be the mirror harness docs/testing.md forbids,
# and it would agree with a broken gate forever.
#
# It runs against the REAL progress file and restores it afterwards, rather than against a
# throwaway one: milestone 3 is only reachable through the entry attestation `dreset` writes, so a
# fresh progress file would refuse before the plan pass and stamp nothing — silently, leaving every
# armed case below red on an artifact the fixture believed it had synced. Save-and-restore keeps
# the attempt/absent counters the cases assert on byte-identical.
#
# It reads a design config with NO liveRender, so the gate stops at the harness check immediately
# after the plan pass instead of rendering into fixture state other cases depend on.
#
# The stamp lands in its OWN commit. That is safe by construction: the plan is excluded from
# plan_patch_id, so re-stamping never restales the stamp it just wrote, and it is excluded from
# nothing else — a re-stamp moves render_patch_id, which is correct, because the plan only goes
# stale when the code the receipt screenshotted moved too.
dplan_sync() { # dplan_sync [config]
  local cfg="${1:-$DSYNCCFG}"
  [ -f "$DPLAN" ] || return 0
  git -C "$DTREE" rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1 || return 0
  cp "$DPROG" "$DSYNCPROG" 2>/dev/null || return 0
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
    && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$DPROG" \
       bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 55 ) >/dev/null 2>&1
  mv "$DSYNCPROG" "$DPROG" 2>/dev/null
  if ! git -C "$DTREE" diff --quiet HEAD -- docs/plans/acme-55-lean-plan.md 2>/dev/null \
     || [ -z "$(git -C "$DTREE" log -1 --format=%H -- docs/plans/acme-55-lean-plan.md 2>/dev/null)" ]; then
    git -C "$DTREE" add docs/plans/acme-55-lean-plan.md >/dev/null 2>&1
    git -C "$DTREE" commit -q -m "stamp the translation plan" >/dev/null 2>&1
  fi
  dplanrev_sync "$cfg"
}

# The plan-REVIEW record (#710), and the same discipline the plan stamp above is written under:
# PRODUCTION's own writer stamps `reviewed_plan_from`, and this fixture never computes a patch id.
# A fixture that derived the binding would be the mirror harness docs/testing.md forbids, and it
# would agree with a broken gate forever.
#
# It is a no-op for a family with no plan reviewer: the writer refuses (exit 2), nothing lands in
# the tree, and the commit arm below sees nothing to commit — which is exactly the state the
# (dpr7) case needs, and it needs no special-casing here to get it.
#
# Committing the record cannot restale the plan (the record is excluded from plan_patch_id), which
# is half of what (dpr2) asserts against production; the fixture RELIES on that rather than
# re-deriving it, so a gate that lost the exclusion turns every armed case below red.
DPLANREV="$DTREE/docs/plans/acme-55-lean-plan-review.md"
DFINDINGS="$WORK/dplan-findings.md"
{
  printf '## Findings\n\n'
  printf 'B1: the 16px sibling gap between the header block and the results grid is translated as 8px.\n'
} > "$DFINDINGS"
dplanrev_sync() { # dplanrev_sync [config] [verdict]
  local cfg="${1:-$DSYNCCFG}" v="${2:-pass}"
  [ -f "$DPLAN" ] || return 0
  git -C "$DTREE" rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1 || return 0
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
    && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$DPROG" \
       bash "$GATE" plan-review 55 --verdict "$v" --summary-file "$DFINDINGS" --model stub-model ) >/dev/null 2>&1
  if ! git -C "$DTREE" diff --quiet HEAD -- docs/plans/acme-55-lean-plan-review.md 2>/dev/null \
     || [ -z "$(git -C "$DTREE" log -1 --format=%H -- docs/plans/acme-55-lean-plan-review.md 2>/dev/null)" ]; then
    git -C "$DTREE" add docs/plans/acme-55-lean-plan-review.md >/dev/null 2>&1
    git -C "$DTREE" commit -q -m "record the plan review" >/dev/null 2>&1
  fi
}

dcommit() {
  git -C "$DTREE" add -A >/dev/null 2>&1
  git -C "$DTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
  # Every armed milestone-3 case below reaches the render pass only through the plan gate, so the
  # plan has to be committed and current whenever the tree moves. A no-op unless the plan exists
  # AND its binding actually went stale.
  dplan_sync
}
dgate() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$DCFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ); }
# The UNARMED reader: the same tree and the same spec, read through a config with no design axis.
# That pairing is the AND→OR mutant's executioner — under OR the section alone would arm.
dgate_nodesign() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ); }
# The panel an armed round must carry (#708): the fixture config declares `design.provider: figma`
# and dspec_armed hands off to a figma host, so the figma fidelity reviewer is the mandatory one.
# Written out rather than derived — a fixture that recomputed design_family() would assert
# whatever that function returned, including nothing.
DPANEL="review-toolkit:security-reviewer,design-toolkit:figma-faithful-reviewer"
dverdict() { # dverdict <session-id> <run-id> [args...]
  local sid="$1" rid="$2"; shift 2
  # DEFAULTED, not required at every call site. $DSPEC is armed for nearly every case below, and
  # the writer refuses an armed round with no `--panel`; supplying it here keeps each of those
  # cases asserting its own subject — the fidelity-evidence grammar, the enum, the identity arms
  # — instead of restating the panel contract. A case that IS about the panel passes its own,
  # and wins: the gate's parser takes the last occurrence of a flag.
  case " $* " in *" --panel "*) : ;; *) set -- "$@" --panel "$DPANEL" ;; esac
  ( unset RUN_ID; cd "$DTREE" && SECOND_SHIFT_CONFIG="$DCFG" LEAN_PROGRESS_FILE="$DPROG" \
    CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$GATE" verdict 55 "$@" 2>&1 )
}
dreset() { rm -f "$DPROG"; { echo "# lean run — issue 55"; echo ""; echo "run_id: r-build-d"; echo "session_id: sess-build-d"; } > "$DPROG"
           attest_at "$DTREE" "$DCFG" "$DPROG" 55; }
# CAPTURE FIRST, default on the assignment — the trap lean-gate.sh's own count_matches()
# documents: on zero matches `grep -c` PRINTS "0" *and* exits 1, so a trailing `|| echo 0`
# emits a second "0" and every arithmetic test on the result then trips "integer expression
# expected" and reads as false. A counter that silently returns "0\n0" fails the exact
# assertions it exists to make (this cost (dl4) a round).
dnum() { # dnum <grep-args...>
  local n
  n="$("$@" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}
dcalls() { if [ -f "$DCALLS" ]; then dnum grep -c . "$DCALLS"; else echo 0; fi; }
dcount() { if [ -f "$DPROG" ]; then dnum grep -cF "$1" "$DPROG"; else echo 0; fi; }
dmode()  { printf '%s' "$1" > "$DMODE"; }

dspec_armed() { # dspec_armed <extra-rows...>
  {
    echo "# spec"
    echo ""
    echo "- AC-1: the thing"
    echo ""
    echo "## Design"
    echo ""
    echo "Handoff: https://www.figma.com/design/AbC123/Prospects"
    echo ""
    echo "| RS-n | route | state (what must be visible) | AC refs |"
    echo "| --- | --- | --- | --- |"
    echo "| RS-1 | prospects | default | AC-1 |"
    echo "| RS-2 | prospects | filters expanded | AC-1 |"
  } > "$DSPEC"
}

# The conforming evidence body an armed `--fidelity pass` write now demands (#693): one scored row
# per state dspec_armed declares. A FILE passed through --summary-file, because that is the
# production path a reviewer uses — an inline here-doc at each of the seven call sites would be
# seven copies of the column contract to keep in step.
DEVIDENCE="$WORK/devidence.md"
devidence() { # devidence [extra-rows...]
  local r
  {
    echo "## Design fidelity evidence"
    echo ""
    echo "| RS-n | frame node | property | design | rendered | verdict |"
    echo "| --- | --- | --- | --- | --- | --- |"
    echo "| RS-1 | Prospects / default | control height | 32px | 32px | match |"
    echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |"
    for r in "$@"; do echo "$r"; done
  } > "$DEVIDENCE"
}
devidence

# The gate's OWN key reader, run over a record this suite produced — never a grep spelled here.
# `record_key` is an unanchored whole-file scan, so what it does with a body that contains
# `key: value`-shaped text is a production property, and a hand-rolled mirror of it could not
# fail on a production edit.
dreckey() { # dreckey <key> <file>
  # `k`/`f` are copied out of $1/$2 BEFORE the source, for the reason mdrows() states below:
  # library mode's placeholder args are consumed by the gate's own parser, which leaves this
  # scope with no positional parameters at all.
  local k="$1" f="$2"
  # shellcheck disable=SC1090  # $GATE is the script under test, sourced in its own library mode.
  ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 && record_key "$k" "$f" )
}

# The `panel:` value, through the GATE's own reader rather than a grep spelled here. `record_key`
# and `header_key` both stop at the first character outside [A-Za-z0-9._-], so either would
# truncate a qualified comma-separated list to its leading token and (fp0) would assert nothing
# about the property it exists for. A grep in the fixture would prove only that the bytes are on
# disk, which is not the claim — the claim is that a READER gets the whole value back.
dpanelkey() { # dpanelkey <file>
  local f="$1"
  # shellcheck disable=SC1090  # $GATE is the script under test, sourced in its own library mode.
  ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 && panel_key < "$f" )
}

dmode ok
dcfg "$DSTUB_CMD"
dcommit "base"
git -C "$DTREE" update-ref refs/remotes/origin/main HEAD
printf 'the work\n' > "$DTREE/subject.txt"

# #709: `Design: none` on a provider repo needs a gate-visible design-disarm override behind
# it (D-1) — a build session may not opt a ticket out of the render lane on its own. Defined
# HERE, before any disarm fixture below, so every "Design: none" case in this whole design
# block can back its disarm rather than reading the new refusal by accident.
DOVT="$HERE/../../tools/operator-override.sh"
DOV_REC="$DTREE/docs/plans/acme-55-lean-override.md"
dov_attend() { ( cd "$DTREE" && env RUN_ID=dov-run CLAUDE_CODE_SESSION_ID=dov-sess SECOND_SHIFT_CONFIG="$DCFG" \
    bash "$DOVT" attend ) >/dev/null 2>&1; }
dov_write() { # dov_write <decision> <answer>
  ( cd "$DTREE" && env RUN_ID=dov-run CLAUDE_CODE_SESSION_ID=dov-sess SECOND_SHIFT_CONFIG="$DCFG" \
      bash "$DOVT" record --gate design-disarm --scope design-disarm --issue 55 \
      --decision "$1" --answer "$2" --repo-root "$DTREE" ) >/dev/null 2>&1; }
dov_clear() { rm -f "$DOV_REC" "$DTREE/.claude/pipeline-state/attend-dov-sess.token"; }
# One override, reused by every disarm fixture below that is not itself testing the override
# mechanism (that is (dzo)'s job) — recorded once and left in place, since the mechanism scopes
# by issue+gate and every case here is issue 55's design-disarm.
if [ -f "$DOVT" ]; then
  dov_attend
  dov_write 'the ticket ships no UI' 'Confirmed — backend-only, disarm it where the fixture needs to.'
else
  fail "(dzoh) the override mechanism at $DOVT is absent — every disarm fixture below would read the new refusal instead of its own subject"
fi

# ---- (dz) AC-1: the milestone-1 arming forms --------------------------------------------
# (dz1) provider configured, no section at all.
dreset
printf '# spec\n\n- AC-1: the thing\n' > "$DSPEC"
dcommit "a spec with no Design section"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'must carry a "## Design" section' <<<"$out"; then
  pass "(dz1) a configured design.provider with no '## Design' section reds milestone 1"
else fail "(dz1) expected the missing-section refusal, rc=$rc: $out"; fi

# (dz3) THE AND→OR EXECUTIONER, run before the armed cases so the spec it reads is the armed one.
# Same tree, same spec, config with no design axis: milestone 1 must pass and say nothing about
# arming. Under an OR reading of D-8 this case reds, because the section alone would arm a repo
# that owns no render harness.
dreset
dspec_armed
dcommit "the armed spec"
out="$(dgate_nodesign 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'ARMED' <<<"$out"; then
  pass "(dz3) a '## Design' section in a repo with no design.provider arms NOTHING (the AND half of D-8)"
else fail "(dz3) expected an unarmed pass, rc=$rc: $out"; fi

# (dz4) and the same spec under the design config IS armed.
dreset
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'design lane ARMED' <<<"$out"; then
  pass "(dz4) the same spec under a configured provider arms the lane"
else fail "(dz4) expected an armed pass, rc=$rc: $out"; fi

# (dz2) the explicit-empty form.
dreset
printf '# spec\n\n- AC-1: the thing\n\n## Design\n\nDesign: none — no FE surface in this ticket.\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'disarmed' <<<"$out"; then
  pass "(dz2) 'Design: none — <reason>' is a conscious per-ticket disarm, not a defect"
else fail "(dz2) expected a disarmed pass, rc=$rc: $out"; fi

# (dz5) a disarm with no reason is not the form. An undocumented disarm is indistinguishable
# from an omission at review time, which is what the review-side blocker has to judge.
dreset
printf '# spec\n\n- AC-1: the thing\n\n## Design\n\nDesign: none\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'states no reason' <<<"$out"; then
  pass "(dz5) a bare 'Design: none' is refused — the disarm is a decision and must carry one"
else fail "(dz5) expected the no-reason refusal, rc=$rc: $out"; fi

# ---- (dzo) #709: `Design: none` on a provider repo needs a gate-visible design-disarm override
# D-1 forbids a build session opting a ticket out of the render lane on its own. The three arms
# mirror (yo)'s spec-open-region cases: no record refuses naming the exact command, a valid
# record yields, and a malformed one reds distinctly worded from "no override" (dov_attend/
# dov_write/dov_clear/DOVT/DOV_REC are defined once, above (dz1), so every disarm fixture in
# this whole design section can use them — this block is the one that exercises the mechanism
# itself, not merely relies on it).
if [ ! -f "$DOVT" ]; then
  fail "(dzo0) the override mechanism at $DOVT is absent — every case below would pass vacuously"
else
  pass "(dzo0) the override mechanism resolves at the path lean-gate.sh defaults to"

  # (dzo1) NO RECORD: milestone 1 reds naming the exact remedy command, on the same disarmed
  # spec (dz2) accepts once an override backs it.
  dreset
  dov_clear
  printf '# spec\n\n- AC-1: the thing\n\n## Design\n\nDesign: none — no FE surface in this ticket.\n' > "$DSPEC"
  dcommit "a disarmed spec, no override"
  out="$(dgate 1 55)"; rc=$?
  if [ "$rc" -eq 1 ] \
     && grep -q 'no design-disarm operator override backs it' <<<"$out" \
     && grep -q -- 'record --gate design-disarm --scope design-disarm --issue 55' <<<"$out"; then
    pass "(dzo1) #709 AC-1: a disarmed provider spec with no override reds milestone 1 naming the exact remedy"
  else fail "(dzo1) expected rc=1 naming the override command, got rc=$rc: $out"; fi

  # (dzo2) AC-2: a VALID record backs the SAME spec, and the ticket yields — 'disarmed', not the
  # refusal (dzo1) hit on identical spec bytes.
  dreset
  dov_attend
  dov_write 'the ticket ships no UI' 'Confirmed — backend-only, disarm it.'
  out="$(dgate 1 55)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -q 'disarmed' <<<"$out"; then
    pass "(dzo2) #709 AC-2: a design-disarm override backing the same spec yields — disarmed"
  else fail "(dzo2) expected rc=0 disarmed, got rc=$rc: $out"; fi

  # (dzo3) AC-3: a MALFORMED record is UNKNOWN, not "no override" — collapsing the two would let
  # a record the merge boundary is about to reject wave the disarm through here first.
  # `design_state()`'s vocabulary is `unarmed`/`disarmed`/`armed`/`error:<msg>` (its own header
  # comment), not check_pause_and_ask's separate rc=2/no-charge one — a malformed override is an
  # `error:` outcome like every other design_state() defect (a missing section, a bad host), so
  # it charges a fix attempt like they do, rather than a bespoke unbudgeted class this one arm
  # would need alone.
  dreset
  dov_clear
  before="$(dcount '| milestone-1 | attempt |')"
  # No '### Operator answer' quote at all — well-formed for design-disarm otherwise (it is NOT
  # region-scoped, so 'region: none' here is correct rather than the defect), but a decision
  # nobody stated is not an override.
  printf '## Override 1\ngate: design-disarm\nscope: design-disarm\nissue: 55\nregion: none\nrun_id: r\nsession_id: s\nexpiry: run\ndecision: d\n' > "$DOV_REC"
  out="$(dgate 1 55)"; rc=$?
  after="$(dcount '| milestone-1 | attempt |')"
  if [ "$rc" -eq 1 ] && grep -q 'could not be read as a clean answer' <<<"$out" \
     && grep -q 'not the same fact as' <<<"$out" && [ "$after" -eq $((before + 1)) ]; then
    pass "(dzo3) #709 AC-3: a malformed design-disarm record reds as UNKNOWN, worded distinctly from 'no override'"
  else fail "(dzo3) expected rc=1 naming the unreadable record with one more attempt than before ($before), got rc=$rc attempts=$after: $out"; fi
  dov_clear

  # (dzo4) AC-2: the committed VERDICT stamps the override's own ref. Same spec as (dzo2); the
  # writer's --fidelity defaults to not-applicable, and on a disarmed provider ticket it is
  # stamped with the ref design_state() validated — '55#1', the record's own block ordinal.
  dreset
  dov_attend
  dov_write 'the ticket ships no UI' 'Confirmed — backend-only, disarm it.'
  rm -f "$DVERDICT"
  out="$(dverdict sess-review-d run-review-d --pr 900 --verdict approve)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^fidelity: not-applicable (override: 55#1)$' "$DVERDICT" 2>/dev/null; then
    pass "(dzo4) #709 AC-2: the written verdict stamps 'fidelity: not-applicable (override: 55#1)'"
  else fail "(dzo4) expected the verdict to carry the override ref, rc=$rc: $out; verdict: $(cat "$DVERDICT" 2>/dev/null)"; fi
  dov_clear

  # (dzo5) the writer's own fail-closed side: the SAME disarmed spec with no override backing it
  # refuses --fidelity not-applicable at the WRITER, rather than let a bare value paper over the
  # opt-out #705 forbids — the round never gets a verdict to hand to milestone 4.
  dreset
  dov_clear
  rm -f "$DVERDICT"
  out="$(dverdict sess-review-d2 run-review-d2 --pr 901 --verdict approve)"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'no design-disarm operator override backs it' <<<"$out" && [ ! -f "$DVERDICT" ]; then
    pass "(dzo5) #709: the writer refuses a bare not-applicable on a disarmed spec with no override, and writes no record"
  else fail "(dzo5) expected the writer to refuse with no record written, rc=$rc: $out"; fi
  # RESTORE the default backing override this block cleared — every disarm fixture from here to
  # the end of this design section (dz6 onward) assumes one is already recorded, the same way the
  # pre-(dzo) header above established it before (dz1).
  dov_attend
  dov_write 'the ticket ships no UI' 'Confirmed — backend-only, disarm it where the fixture needs to.'
fi
dreset

# (dz6) render states declared, no handoff link: the review session would have nothing to score
# the screenshots against.
dreset
printf '# spec\n\n- AC-1: x\n\n## Design\n\n| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n| RS-1 | p | default | AC-1 |\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no provider handoff link' <<<"$out"; then
  pass "(dz6) an armed section with no handoff link is refused at authoring time"
else fail "(dz6) expected the missing-link refusal, rc=$rc: $out"; fi

# (dz7) a section that is neither armed nor disarmed — the shape that produced failure class (2).
dreset
printf '# spec\n\n- AC-1: x\n\n## Design\n\nHandoff: https://design.example.invalid/f/a\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no render state' <<<"$out"; then
  pass "(dz7) a section naming neither a render state nor a disarm is refused"
else fail "(dz7) expected the no-render-state refusal, rc=$rc: $out"; fi

# (dz8) #708 D-13: an armed section whose handoff link names no host this lane can classify. The
# fidelity reviewer an armed round must dispatch is derived from that host — here and at the merge
# boundary alike — so an unclassifiable one leaves the mandatory reviewer unnameable. Refused at
# authoring time, where the remedy is a spec edit, rather than at the boundary where it costs a
# round. The section is otherwise WELL-FORMED, so nothing but the host can be what reds it.
dreset
{
  printf '# spec\n\n- AC-1: x\n\n## Design\n\nHandoff: https://design.example.invalid/f/a\n\n'
  printf '| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n| RS-1 | p | default | AC-1 |\n'
} > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'recognises as a provider surface' <<<"$out"; then
  pass "(dz8) an armed section whose handoff host names no provider surface is refused at milestone 1"
else fail "(dz8) expected the unrecognised-host refusal, rc=$rc: $out"; fi

# (dz9) #708 D-14: the host and config `design.provider` name DIFFERENT families. This gate is the
# only reader that sees both — the merge boundary reads the committed spec and never the config —
# so it is the only place the disagreement can be reported at all. Left standing it is a run that
# renders one provider's states while the boundary demands the other provider's reviewer: green on
# each side of the seam, and wrong. The config here declares figma; the handoff says claude-design.
dreset
{
  printf '# spec\n\n- AC-1: x\n\n## Design\n\nHandoff: https://claude.ai/design/AbC123\n\n'
  printf '| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n| RS-1 | p | default | AC-1 |\n'
} > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'hands off to a claude-design surface' <<<"$out" \
   && grep -q 'design.provider is "figma"' <<<"$out"; then
  pass "(dz9) a handoff host disagreeing with config design.provider is refused at milestone 1, naming both"
else fail "(dz9) expected the host/provider mismatch refusal, rc=$rc: $out"; fi

# (dz10) ...and the SAME claude-design handoff under a claude-design provider ARMS. Without this
# the pair above would pass on a gate that simply refused every claude.ai handoff, and the family
# derivation would never be shown to have two answers.
DCFG_CD="$WORK/dconfig-claude-design.json"
sed -e 's#"provider": "figma"#"provider": "claude-design"#' "$DCFG" > "$DCFG_CD"
grep -q '"claude-design"' "$DCFG_CD" \
  || fail "(dz10-fixture) the claude-design config was not built — (dz10) would assert nothing"
dreset
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
        && SECOND_SHIFT_CONFIG="$DCFG_CD" LEAN_PROGRESS_FILE="$DPROG" \
           bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 55 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'design lane ARMED' <<<"$out"; then
  pass "(dz10) the same claude.ai/design handoff ARMS under a claude-design provider — the derivation has two answers"
else fail "(dz10) expected an armed pass under claude-design, rc=$rc: $out"; fi
dspec_armed
dreset

# (a15) #517 AC-8, on the two branches this suite's OTHER config cannot reach. The (a9)-(a14)
# block above runs through $CFG, which declares no `design` key, so design_state() returns
# `unarmed` there, the `case` below the reconciliation matches no arm, and every one of those
# cases scores only the branch where nothing else writes `note`. (a11) therefore cannot fail on
# an assignment in the armed or disarmed arm — which is exactly the defect it was written to
# guard against, and exactly the defect that shipped.
#
# So drive the SAME reconciliation through the design config instead. Both facts must appear on
# one pass line: an implementation that assigns rather than appends keeps whichever it wrote
# last and drops the other, so asserting only one of the two would still pass the clobber.
# The receipt is fixed and the ONLY thing varying between the two calls is the `## Design`
# section, which is what makes the design state the attributable cause.
D_RECEIPT="$WORK/55-receipt.md"
printf '%s\n' '# receipt' '## Decision Ledger' \
  '| ID | Decision | Resolution | Provenance | Kind |' \
  '| --- | --- | --- | --- | --- |' \
  '| D-1 | Rate limit | 100/min, per tenant | user-answered | intent |' \
  '| D-2 | Cache TTL | 5 minutes | codebase-derived | fact |' \
  > "$D_RECEIPT"

# ARMED: the reconciliation counts survive alongside the arming note.
dreset
dspec_armed
printf '%s\n' '' '## Decision Ledger' \
  '| ID | Decision | Resolution | Provenance |' \
  '| --- | --- | --- | --- |' \
  '| D-1 | Rate limit | 100/min, per tenant | user-answered |' >> "$DSPEC"
out="$(dgate --ledger-file "$D_RECEIPT" 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '1 bound, 1 carried, 0 departure(s)' <<<"$out" \
   && grep -q 'design lane ARMED' <<<"$out"; then
  pass "(a15) #517 AC-8: an ARMED design lane does not clobber the reconciliation disclosure"
else fail "(a15) expected rc=0 carrying BOTH the counts and the arming note, got $rc: $out"; fi

# DISARMED: same tree, same receipt, same bound row — only the section changes.
dreset
{ printf '%s\n' '# spec' '' '- AC-1: the thing' '' '## Design' '' \
    'Design: none — no FE surface in this ticket.' '' '## Decision Ledger' \
    '| ID | Decision | Resolution | Provenance |' \
    '| --- | --- | --- | --- |' \
    '| D-1 | Rate limit | 100/min, per tenant | user-answered |'; } > "$DSPEC"
out="$(dgate --ledger-file "$D_RECEIPT" 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '1 bound, 1 carried, 0 departure(s)' <<<"$out" \
   && grep -q 'design lane disarmed for this ticket' <<<"$out"; then
  pass "(a15) #517 AC-8: a DISARMED design lane does not clobber it either"
else fail "(a15) expected rc=0 carrying BOTH the counts and the disarm note, got $rc: $out"; fi

# ---- (dp) #694 AC-1: the TRANSLATION PLAN gate ---------------------------------------------
# The plan was prose a build session emitted and implemented against — nothing read it, so both
# checks written to grade it (per-node sizing, component suitability) reached nothing. These cases
# pin the artifact contract that makes them reachable: it exists, both tables are fully populated,
# it is committed, and it is dated against this branch's patch.
#
# THEY ALL RUN THE FULL RENDER CONFIG. A case that reds under a config with no harness could not
# tell "the plan stopped it" from "there was nothing to render", so every red below is one the
# render pass would otherwise have walked straight past.
dcommit_raw() { # a tree move that does NOT re-stamp the plan — staleness is the subject here
  git -C "$DTREE" add -A >/dev/null 2>&1
  git -C "$DTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
# The plan cases reach the render pass twice on their way through, so they leave a manifest and
# PNGs behind. A later `git add -A` would COMMIT that manifest, and the (dr) happy path then writes
# a byte-identical one, finds HEAD already carrying it, and reads as green — a case asserting the
# commit refusal would pass while asserting nothing. Clear it before every tree move.
dclear_render() { rm -f "$DMANIFEST" "$DCALLS"; rm -rf "$DTREE/.claude/lean-renders"; }

# (dp0) THE AND EXECUTIONER, first. The same tree with no plan at all, read through the config
# with no design axis: milestone 3 must not mention a translation plan. Under a section-only
# reading of arming, every consumer that ever wrote `## Design` would owe this artifact.
dreset
dspec_armed
rm -f "$DPLAN"
dcommit_raw "the armed spec, no plan"
dcfg "$DSTUB_CMD"
out="$(dgate_nodesign 3 55)"; rc=$?
if ! grep -q 'translation plan' <<<"$out"; then
  pass "(dp0) a repo with no design.provider owes no translation plan (the AND half of D-8)"
else fail "(dp0) the unarmed reader demanded a translation plan, rc=$rc: $out"; fi

# (dp1) ARMED and absent. The red names the path and the two columns, and it is charged to the
# ABSENT budget — #642's criterion: a red naming something the run was going to do anyway is not
# a failed fix. Without that split an armed run spends two of its three attempts getting to a
# first render.
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'docs/plans/acme-55-lean-plan.md' <<<"$out" \
   && grep -qF 'why this component' <<<"$out" && grep -qF 'dimensions' <<<"$out" \
   && grep -q 'not a fix attempt' <<<"$out" && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ]; then
  pass "(dp1) an armed spec with no translation plan reds milestone 3, names the artifact, and spends no fix attempt"
else fail "(dp1) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dp2) present, but the resolved-component table never declares `why this component`. This is
# the name-match resolution the ticket was filed on: a component resolved on a layer name, with
# nobody ever asked why it is the right one.
dreset
dplan_write
sed 's/| why this component |/| note |/' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a plan with no why-this-component column"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'resolved-component list is absent' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ]; then
  pass "(dp2) a plan with no 'why this component' column reds, and a written-but-wrong plan IS a fix attempt"
else fail "(dp2) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dp12)-(dp14) #711: the MEASURED-NODE columns, one case per column. They are required OF THE
# TABLE THAT DECLARES `dimensions`, never of the document, and (dp12) is where that distinction
# has teeth: dplan_write's resolved-component table already carries a `node` column, so a
# document-wide existence check reads it as the answer and the dimension table keeps its silence.
dreset
dplan_write
sed 's/^| node | RS | px | dimensions | overflow |$/| component | RS | px | dimensions | overflow |/' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a dimension table with no node column, and a component table that has one"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no "node" column' <<<"$out"; then
  pass "(dp12) a dimension table with no 'node' column reds — a 'node' column on the component table is not the answer"
else fail "(dp12) expected the missing-node-column refusal, rc=$rc: $out"; fi

dreset
dplan_write
sed 's/^| node | RS | px | dimensions | overflow |$/| node | state | px | dimensions | overflow |/' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a dimension table with no RS column"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no "rs" column' <<<"$out"; then
  pass "(dp13) a dimension table with no 'RS' column reds — a size measured in no named state is measured against no file"
else fail "(dp13) expected the missing-RS-column refusal, rc=$rc: $out"; fi

dreset
dplan_write
sed 's/^| node | RS | px | dimensions | overflow |$/| node | RS | size | dimensions | overflow |/' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a dimension table with no px column"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no "px" column' <<<"$out"; then
  pass "(dp14) a dimension table with no 'px' column reds — the prose 'dimensions' cell is not machine-readable and is not meant to be"
else fail "(dp14) expected the missing-px-column refusal, rc=$rc: $out"; fi

# (dp3) the EMPTY CELL, which is the spec reviewer's device and the whole point of the column
# anchor: a dimension row that exists but records nothing is the silence being caught.
dreset
dplan_write
sed "s@^$DPLAN_DROW\$@| Filter panel | RS-1 | 320×604 |  | none |@" "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a plan with an empty dimensions cell"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'dimensions row 1 leaves column 4 empty' <<<"$out"; then
  pass "(dp3) an empty cell in the dimension table reds, named by row and column"
else fail "(dp3) expected the empty-cell refusal, rc=$rc: $out"; fi

# (dp4) the SHORT ROW. GFM renders a missing trailing cell as blank, so deleting the cell would
# otherwise be the one-character escape from (dp3).
dreset
dplan_write
sed "s@^$DPLAN_DROW\$@| Filter panel | RS-1 | 320×604 | fixed 320px wide, hug height |@" "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a plan with a short dimensions row"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'a short row is a missing cell' <<<"$out"; then
  pass "(dp4) a row declaring fewer cells than its header reds — deleting the cell is not an escape"
else fail "(dp4) expected the short-row refusal, rc=$rc: $out"; fi

# (dp10) THE TABLE THAT CARRIES NO DATA ROW — the ticket's own headline failure restated: "a plan
# that records no control dimensions at all". It is caught by neither neighbour, which is why it
# needs its own case: the missing-column arm sees the column declared, and the empty-cell arm has
# no cell to look at. A header and a delimiter over nothing is a column declared and never filled.
dreset
dplan_write
sed "\@^$DPLAN_DROW\$@d" "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a plan whose dimension table carries no data row"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'the table declaring a "dimensions" column carries no data row' <<<"$out"; then
  pass "(dp10) a dimension table with a header and no data row reds — a declared column with nothing under it is the silence the artifact exists to make visible"
else fail "(dp10) expected the no-data-row refusal, rc=$rc: $out"; fi

# (dp11) NO DELIMITER ROW UNDER THE HEADER. Without it GFM renders the run as paragraph text, not
# a table, so a plan that lost the line reads as populated in the source and as prose to anything
# that renders it — and the gate would otherwise mistake the first data row for the delimiter.
#
# TWO data rows on purpose. With one, neutering this arm falls through to (dp10)'s arm — `rowno`
# never reaches 3, so `endtable()` reports the no-data-row shape instead and the case still reds
# on a gate that has stopped checking delimiters. Two rows is the shape a real plan has, and it is
# where the arm is fail-open rather than merely mis-worded.
dreset
dplan_write
echo "| Results grid | RS-1 | -×412 | fill width, 12px row gap | scroll-y |" >> "$DPLAN"
awk '/^\| --- \| --- \| --- \| --- \| --- \|$/ { next } { print }' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a plan whose dimension table lost its delimiter row"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'the table declaring a "dimensions" column has no delimiter row under its header' <<<"$out"; then
  pass "(dp11) a dimension table with no delimiter row under its header reds — the first data row is not a delimiter"
else fail "(dp11) expected the missing-delimiter refusal, rc=$rc: $out"; fi

# (dp9) A FENCED EXAMPLE IS NOT A TABLE. The step-7 prose invites a plan to quote the required
# shape, and a plan whose own example's placeholder cells were reported as violations would be
# refused for doing what it was told — the one red an author cannot act on.
dreset
dplan_write
{ printf '\n%smarkdown\n' "$DFENCE"
  printf '| node | dimensions | overflow |\n| --- | --- | --- |\n|  |  |  |\n'
  printf '%s\n' "$DFENCE"; } >> "$DPLAN"
dcommit_raw "a conforming plan that quotes the shape in a fence"
out="$(dgate 3 55)"; rc=$?
if ! grep -q 'leaves column' <<<"$out" && ! grep -q 'is absent' <<<"$out"; then
  pass "(dp9) a fenced example's placeholder cells draw no violation — quoting the shape is not declaring a table"
else fail "(dp9) the fenced example was parsed as a real table, rc=$rc: $out"; fi

# (dp5) conforming tables, no `planned_from:` line. The gate refuses rather than inserting one:
# it stamps a field the author declared, it never invents structure inside an authored artifact.
dreset
dplan_write
grep -v '^planned_from:' "$DPLAN" > "$DPLAN.tmp" && mv "$DPLAN.tmp" "$DPLAN"
dcommit_raw "a conforming plan with no planned_from header"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "no 'planned_from:' header" <<<"$out" \
   && grep -qF 'planned_from: pending' <<<"$out"; then
  pass "(dp5) a plan with no 'planned_from:' line reds, naming the exact line to add"
else fail "(dp5) expected the missing-header refusal with the remedy line, rc=$rc: $out"; fi

# (dp6) THE STAMP CYCLE, and the case that proves the plan gate is what the render pass waits on.
# Red one: the gate stamps and demands a commit, and NO render has happened. Red two: committed
# and current, so the same evaluation walks past the plan into the render pass.
dreset
dplan_write
dcommit_raw "the conforming plan"
rm -f "$DCALLS"
out="$(dgate 3 55)"; rc=$?
dp_stamped="$(grep -oE '^planned_from: .+' "$DPLAN" | head -n1)"
if [ "$rc" -eq 1 ] && grep -q 're-stamped to' <<<"$out" && [ "$dp_stamped" != "planned_from: pending" ] \
   && [ "$(dcalls)" -eq 0 ]; then
  pass "(dp6) an unstamped plan is stamped by the gate and reds before the harness is called once"
else fail "(dp6) rc=$rc stamped='$dp_stamped' renders=$(dcalls): $out"; fi

dcommit_raw "commit the stamp"
# #710: reaching the render pass now needs the plan-review record too, so the fixture supplies it
# through PRODUCTION's writer. Without this the case would still see 'translation plan current'
# and red on the render count — which is (dpr1)'s subject, not this one's.
dplanrev_sync
dreset
out="$(dgate 3 55)"; rc=$?
if grep -q 'translation plan current' <<<"$out" && [ "$(dcalls)" -eq 2 ]; then
  pass "(dp6) …and once committed the same evaluation passes the plan and reaches the render pass"
else fail "(dp6) expected the plan to pass and both states to render, rc=$rc renders=$(dcalls): $out"; fi

# (dp7) STALENESS (decision g). The plan was written against code that has since moved, so the
# binding no longer says what it claims. It re-stamps and reds; committing that clears it.
dclear_render
dreset
printf 'a later fix\n' >> "$DTREE/subject.txt"
dcommit_raw "code moves under the plan"
out="$(dgate 3 55)"; rc=$?
dp_restamped="$(grep -oE '^planned_from: .+' "$DPLAN" | head -n1)"
if [ "$rc" -eq 1 ] && grep -q 'RE-READ THE PLAN' <<<"$out" && [ "$dp_restamped" != "$dp_stamped" ]; then
  pass "(dp7) a plan bound to code that has since moved reds and is re-stamped"
else fail "(dp7) rc=$rc before='$dp_stamped' after='$dp_restamped': $out"; fi

dcommit_raw "commit the re-stamp"
dplanrev_sync
dreset
out="$(dgate 3 55)"; rc=$?
if grep -q 'translation plan current' <<<"$out"; then
  pass "(dp7) …and committing the re-stamp clears it, so the binding converges rather than looping"
else fail "(dp7) the re-stamped plan did not settle, rc=$rc: $out"; fi

# ---- (dpr) #710: the plan is asserted for shape and GRADED by somebody -------------------
# The plan pass above proves two tables have no empty cells. Nothing proved anyone read what was
# in them — `figma-faithful-plan-reviewer` scored 99.17% against the very defects #692 shipped and
# was dispatched by no autonomous lane. The gate cannot run an agent, so these cases assert the
# committed OUTPUT, exactly as the verdict record's own cases do.
#
# THEY ALL RUN THE FULL RENDER CONFIG, on (dp)'s rule: a case that redded under a config with no
# harness could not tell "the plan review stopped it" from "there was nothing to render".
#
# ENTERING STATE: the plan is committed and current, and (dp7) left a current record beside it.

# (dpr1) AC-1. ABSENT. The red names the dispatch and the writer, it walks the ABSENT budget, and
# — the half that is the ticket's whole point — the render stub is never called once. A plan
# nobody graded costs no screenshots.
dclear_render
git -C "$DTREE" rm -q -f docs/plans/acme-55-lean-plan-review.md >/dev/null 2>&1
dcommit_raw "remove the plan-review record"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'docs/plans/acme-55-lean-plan-review.md' <<<"$out" \
   && grep -qF 'design-toolkit:figma-faithful-plan-reviewer' <<<"$out" \
   && grep -qF 'plan-review 55' <<<"$out" \
   && grep -q 'not a fix attempt' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ] && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpr1) an armed run with no plan-review record reds before any render command, names the dispatch, and spends no fix attempt"
else fail "(dpr1) rc=$rc attempts=$(dcount '| milestone-3 | attempt |') renders=$(dcalls): $out"; fi

# (dpr2) AC-2, first half: COMMITTING THE RECORD DOES NOT STALE IT. The record binds to the plan
# patch id, and that id is computed over the branch diff — so without the exclusion the very
# commit that lands the record would move the id it just recorded, and the binding could never be
# satisfied by any sequence of commits. Asserted through the writer, which is the only thing that
# stamps the value.
dplanrev_sync
dclear_render
dreset
out="$(dgate 3 55)"; rc=$?
if grep -q 'translation plan reviewed by figma-faithful-plan-reviewer' <<<"$out" \
   && grep -q 'verdict pass' <<<"$out" && [ "$(dcalls)" -eq 2 ]; then
  pass "(dpr2) committing the plan-review record never stales it — the same evaluation passes it and reaches the render pass"
else fail "(dpr2) the committed record did not release the render pass, rc=$rc renders=$(dcalls): $out"; fi

# (dpr2) second half: STALENESS. The code moved under the plan, so the plan was re-stamped and
# re-read; the review of the OLD plan is no longer a review of this one. Two commits, because the
# plan's own re-stamp red has to be cleared first — this arm is about the record, not the plan.
printf 'a fix landed after the plan review\n' >> "$DTREE/subject.txt"
dclear_render
dcommit_raw "code moves under the reviewed plan"
dgate 3 55 >/dev/null 2>&1          # the plan re-stamps here
dcommit_raw "commit the re-stamp"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'was written against a different tree' <<<"$out" \
   && grep -q 'translation plan current' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ] && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpr2) a record whose reviewed_plan_from no longer matches the branch's plan binding reds as stale, on the absent budget, before any render"
else fail "(dpr2-stale) rc=$rc attempts=$(dcount '| milestone-3 | attempt |') renders=$(dcalls): $out"; fi

# (dpr3) AC-3. `verdict: block` reds and QUOTES THE FIRST FINDING. Quoting is the arm that makes
# the refusal actionable — "the plan review blocks" would send its reader to open a file to learn
# what for, and the whole economics here is that the fix is one table row. The findings body opens
# with a `## Findings` heading, so this also pins that a section label is not a finding.
dplanrev_sync "$DSYNCCFG" block
dclear_render
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'BLOCKED the translation plan' <<<"$out" \
   && grep -qF 'B1: the 16px sibling gap' <<<"$out" \
   && ! grep -qF '## Findings' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ] && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpr3) 'verdict: block' reds milestone 3 before any render, quoting the first finding and not the section heading above it"
else fail "(dpr3) rc=$rc attempts=$(dcount '| milestone-3 | attempt |') renders=$(dcalls): $out"; fi

# (dpr4) AC-3, the other side: `fix-and-go` PROCEEDS. It is a real value in the enum and not a
# synonym for `block` — a reviewer that found something worth writing down and nothing worth
# stopping for ships the list into the PR, where review-lean reads the committed record.
dplanrev_sync "$DSYNCCFG" fix-and-go
dclear_render
dreset
out="$(dgate 3 55)"; rc=$?
if grep -q 'verdict fix-and-go' <<<"$out" && [ "$(dcalls)" -eq 2 ]; then
  pass "(dpr4) 'fix-and-go' passes the plan-review gate and reaches the render pass"
else fail "(dpr4) expected fix-and-go to proceed, rc=$rc renders=$(dcalls): $out"; fi

# (dpr5) MALFORMED, and a `fail_milestone` rather than a block: the record was written and what
# was written is wrong, which is #642's criterion for a fix attempt. Only a hand edit can reach
# this — the writer stamps every key the reader reads — so the refusal is also the one that says
# "stop hand-editing this file".
dclear_render
sed 's/^verdict: fix-and-go$/verdict: probably-fine/' "$DPLANREV" > "$DPLANREV.tmp" && mv "$DPLANREV.tmp" "$DPLANREV"
dcommit_raw "a hand-edited record with a verdict outside the enum"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'is malformed' <<<"$out" \
   && grep -q "outside the enum" <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ] && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpr5) a verdict outside the enum reds as MALFORMED and IS a fix attempt — a written-but-wrong record is a failed fix"
else fail "(dpr5) rc=$rc attempts=$(dcount '| milestone-3 | attempt |') renders=$(dcalls): $out"; fi

# (dpr6) the REVIEWER ARM of the same refusal, and it needs its own case: (dpr5) neuters the
# verdict enum, so a gate that had stopped checking `reviewer:` entirely would still red there.
# The value is host-derived (D-28) — a record naming some other agent is a record of a review the
# spec's handoff never asked for.
dplanrev_sync
dclear_render
sed 's/^reviewer: figma-faithful-plan-reviewer$/reviewer: maintainability-reviewer/' "$DPLANREV" > "$DPLANREV.tmp" && mv "$DPLANREV.tmp" "$DPLANREV"
dcommit_raw "a record naming a reviewer the handoff host does not make mandatory"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'is malformed' <<<"$out" \
   && grep -q "reviewer 'maintainability-reviewer' is not the one" <<<"$out" && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpr6) a record naming a reviewer the handoff host does not make mandatory reds as malformed"
else fail "(dpr6) rc=$rc renders=$(dcalls): $out"; fi

# (dpr7) THE DECLINED MANDATE (D-27 / OR-1). `design-faithful-plan-reviewer` does not exist, so an
# armed claude-design run has no dispatch to make and the gate must say so rather than demand an
# artifact nobody can produce. This is the case that keeps the family arm from being a formality:
# without it, a gate that mandated the record for EVERY armed family would be indistinguishable
# from this one, because every other case here hands off to a figma host.
#
# The record committed above is left in the tree deliberately — a family with no plan reviewer is
# not asked about it at all, so its presence must not change the answer either way.
DCDCFG="$WORK/dconfig-claude-design.json"
sed 's/"provider": "figma"/"provider": "claude-design"/' "$DCFG" > "$DCDCFG"
DCDSYNCCFG="$WORK/dsync-config-claude-design.json"
sed 's/"provider": "figma"/"provider": "claude-design"/' "$DSYNCCFG" > "$DCDSYNCCFG"
dgate_cd() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$DCDCFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ); }
sed 's#https://www.figma.com/design/AbC123/Prospects#https://claude.ai/design/AbC123/Prospects#' "$DSPEC" > "$DSPEC.tmp" && mv "$DSPEC.tmp" "$DSPEC"
dclear_render
dcommit_raw "the same armed ticket, handed off to a claude-design surface"
dplan_sync "$DCDSYNCCFG"
dclear_render
dreset
out="$(dgate_cd 3 55)"; rc=$?
if grep -q "'claude-design' design family ships no plan-stage reviewer" <<<"$out" \
   && ! grep -q 'is malformed' <<<"$out" && ! grep -q 'BLOCKED the translation plan' <<<"$out" \
   && [ "$(dcalls)" -eq 2 ]; then
  pass "(dpr7) an armed family with no plan-stage reviewer is declared unreviewed and proceeds — the mandate is family-scoped, not universal"
else fail "(dpr7) rc=$rc renders=$(dcalls): $out"; fi

# (dpr8) AC-4, the WRITER. Two refusals and one stamp. The enum refusal is what keeps a typo from
# becoming a fourth verdict value nothing downstream understands, and `--summary-file` is required
# here where `verdict`'s is optional for the reason (dpr3) demonstrates: a `block` the gate has to
# quote needs a body to quote from.
dwriter() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$DSYNCCFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" plan-review 55 "$@" 2>&1 ); }
sed 's#https://claude.ai/design/AbC123/Prospects#https://www.figma.com/design/AbC123/Prospects#' "$DSPEC" > "$DSPEC.tmp" && mv "$DSPEC.tmp" "$DSPEC"
dclear_render
dcommit_raw "hand the ticket back to the figma surface"
dplan_sync
out="$(dwriter --verdict probably-fine --summary-file "$DFINDINGS" --model stub-model)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'takes pass|fix-and-go|block' <<<"$out"; then
  pass "(dpr8) the writer refuses a verdict outside the enum, as a usage error and not a milestone red"
else fail "(dpr8) expected the enum refusal at exit 2, rc=$rc: $out"; fi

out="$(dwriter --verdict pass --model stub-model)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'summary-file is required' <<<"$out"; then
  pass "(dpr8) …and refuses a verdict with no findings body — a record that names no fix is the silence this artifact exists to end"
else fail "(dpr8) expected the required-summary refusal at exit 2, rc=$rc: $out"; fi

# …and the STAMP is production's, read back through production's own reader. The fixture asserts
# only that the two AGREE: it never computes a patch id, which is what would make it a mirror.
dwriter --verdict pass --summary-file "$DFINDINGS" --model stub-model >/dev/null 2>&1
dpr_stamped="$(grep -oE '^reviewed_plan_from: .+' "$DPLANREV" | head -n1 | sed 's/^reviewed_plan_from: //')"
git -C "$DTREE" add docs/plans/acme-55-lean-plan-review.md >/dev/null 2>&1
git -C "$DTREE" commit -q -m "record the plan review" >/dev/null 2>&1
dclear_render
dreset
out="$(dgate 3 55)"; rc=$?
if [ -n "$dpr_stamped" ] && [ "$dpr_stamped" != "pending" ] \
   && grep -qF "reviewed_plan_from ${dpr_stamped:0:12}" <<<"$out" && [ "$(dcalls)" -eq 2 ]; then
  pass "(dpr8) …and the value it stamps is the one the gate reads back as current — writer and reader share one derivation"
else fail "(dpr8) stamped='$dpr_stamped' rc=$rc renders=$(dcalls): $out"; fi

dclear_render

# (dp8) THE STATE LOCK moved with the ordering (D-5). The plan pass now runs first, so it is the
# pass that must write `| milestone-3 | armed |` — otherwise a plan that failed could be disarmed
# away on the next attempt, which is exactly what the lock exists to refuse.
dclear_render
dreset
rm -f "$DPLAN"
dcommit_raw "the plan is removed again"
dgate 3 55 >/dev/null 2>&1
dp_armed="$(dcount '| milestone-3 | armed |')"
{ printf '%s\n' '# spec' '' '- AC-1: the thing' '' '## Design' '' 'Design: none — reconsidered.'; } > "$DSPEC"
dcommit_raw "a mid-run disarm after the plan red"
out="$(dgate 3 55)"; rc=$?
if [ "$dp_armed" -eq 1 ] && [ "$rc" -eq 1 ] && grep -q 'already armed it' <<<"$out"; then
  pass "(dp8) a plan red still arms the lane, so the disarm state-lock refuses the escape it exists for"
else fail "(dp8) armed=$dp_armed rc=$rc: $out"; fi

# Leave the fixture where the (dr) cases expect it: armed spec, conforming committed plan, and no
# render evidence — committed OR in the tree, per dclear_render's header.
dspec_armed
dplan_write
dclear_render
dcommit_raw "restore the armed spec and its plan, clearing the render evidence"
dplan_sync
dclear_render

# ---- (dr) AC-3: the render pass ----------------------------------------------------------
# (dr7) the template must carry {out} — there is otherwise nowhere for a screenshot to land.
dreset
dspec_armed
dcommit "the armed spec, restored"
dcfg "bash $DSTUB --route {route} --state {state}"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no {out} placeholder' <<<"$out"; then
  pass "(dr7) a liveRender.command with no {out} reds milestone 3"
else fail "(dr7) expected the missing-{out} refusal, rc=$rc: $out"; fi

# (dr6) {state} is required only because a NON-DEFAULT state is declared. Without it the harness
# would screenshot the default view for every row — failure class (2), passing every other check.
dreset
dcfg "bash $DSTUB --route {route} --out {out}"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no {state} placeholder' <<<"$out"; then
  pass "(dr6) a non-default RS row with no {state} in the command reds milestone 3"
else fail "(dr6) expected the missing-{state} refusal, rc=$rc: $out"; fi

# ...and the same command is ACCEPTED when every declared state is the default one, so (dr6)
# turns on the declared state and not merely on the placeholder's absence.
dreset
{
  echo "# spec"; echo ""; echo "- AC-1: x"; echo ""; echo "## Design"; echo ""
  echo "Handoff: https://www.figma.com/design/AbC123/Prospects"; echo ""
  echo "| RS-n | route | state | AC refs |"; echo "| --- | --- | --- | --- |"
  echo "| RS-1 | prospects | default | AC-1 |"
} > "$DSPEC"
dcommit "a single default-state spec"
out="$(dgate 3 55)"; rc=$?
# The POSITIVE half: the run reached the render itself. Asserting only the refusal's absence
# would also pass if the gate had redded one line earlier for some unrelated reason, which is
# how a "the check did not fire" case quietly stops asserting anything.
if ! grep -q 'no {state} placeholder' <<<"$out" \
   && grep -q 'milestone-3: render RS-1' <<<"$out"; then
  pass "(dr6b) a default-only render table needs no {state} — the refusal is keyed on the declared state, and the run reaches the render"
else fail "(dr6b) expected the template check to pass through to the render, rc=$rc: $out"; fi

# (dr11) a repeated RS id. The id is the screenshot's filename, so the second render overwrites
# the first and the manifest ends up with two rows backed by one file — evidence that fails the
# reviewer's hash check for a reason the spec author never sees.
dreset
{
  echo "# spec"; echo ""; echo "- AC-1: x"; echo ""; echo "## Design"; echo ""
  echo "Handoff: https://www.figma.com/design/AbC123/Prospects"; echo ""
  echo "| RS-n | route | state | AC refs |"; echo "| --- | --- | --- | --- |"
  echo "| RS-1 | prospects | default | AC-1 |"
  echo "| RS-1 | prospects | filters expanded | AC-1 |"
} > "$DSPEC"
dcommit "a spec repeating an RS id"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "twice" <<<"$out"; then
  pass "(dr11) a repeated RS id reds — one id, one screenshot file, no silently overwritten evidence"
else fail "(dr11) expected the duplicate-id refusal, rc=$rc: $out"; fi

# (dr10) cwd naming a repo this run does not host. The lean lane works one worktree; the honest
# answer is to name the limitation, not to render the wrong tree.
dreset
dspec_armed
dcommit "the armed spec, restored"
dcfg "$DSTUB_CMD" "fe"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'run the lean lane from the repo that owns the render harness' <<<"$out"; then
  pass "(dr10) design.liveRender.cwd naming a non-host topology repo reds with the limitation named"
else fail "(dr10) expected the cwd limitation refusal, rc=$rc: $out"; fi

# (dr8) the check-ignore RED. PNG bytes must never enter history, and the refusal prints the
# exact line to add rather than leaving the operator to derive it.
dreset
dcfg "$DSTUB_CMD"
printf 'docs/nothing\n' > "$DTREE/.gitignore"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'not git-ignored' <<<"$out" \
   && grep -qF '.claude/lean-renders/' <<<"$out"; then
  pass "(dr8) an un-ignored render output path reds, naming the exact .gitignore line to add"
else fail "(dr8) expected the check-ignore refusal with the remedy line, rc=$rc: $out"; fi

# (dr9) and the GREEN half, restored: the same assertion passes once the path is ignored, so
# (dr8) turns on the ignore rule and not on something incidental to that tree.
printf '.claude/\n' > "$DTREE/.gitignore"
dcommit "restore the ignore rule"
dreset
out="$(dgate 3 55)"; rc=$?
if ! grep -q 'not git-ignored' <<<"$out"; then
  pass "(dr9) the same path passes the ignore assertion once .gitignore covers it"
else fail "(dr9) the check-ignore refusal survived the ignore rule: $out"; fi

# (dr5) a harness that exits nonzero. BLOCKING: there is no degraded state to assert, which is
# the whole of failure class (1) — the run stops here.
dreset
dmode fail
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'render RS-1' <<<"$out" && grep -q 'failed (rc=7)' <<<"$out" \
   && [ ! -f "$DMANIFEST" ]; then
  pass "(dr5) a nonzero render exit reds milestone 3 and writes no manifest"
else fail "(dr5) expected the render failure refusal and no manifest, rc=$rc: $out"; fi

# (dr4) a harness that exits 0 and writes nothing. The exit code alone would have called this a
# pass — the second half of failure class (1).
dreset
dmode empty
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'wrote no PNG bytes' <<<"$out" && [ ! -f "$DMANIFEST" ]; then
  pass "(dr4) a zero-byte screenshot reds even though the harness exited 0"
else fail "(dr4) expected the zero-byte refusal, rc=$rc: $out"; fi

# (dr3) THE {state}-BLIND HARNESS — failure class (2) exactly. Two declared states, one view
# rendered twice: every other assertion here passes, and only the hash collision separates it
# from an honest two-state render.
dreset
dmode blind
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'hash identically' <<<"$out" && [ ! -f "$DMANIFEST" ]; then
  pass "(dr3) two declared states rendering byte-identically red — the {state}-blind-harness detector"
else fail "(dr3) expected the identical-hash refusal, rc=$rc: $out"; fi

# (dr1) THE HAPPY PATH. Two rows, two distinct PNGs, two manifest rows — and the manifest reds
# until it is committed, because the receipt sits inside reviewed_patch_id and a verdict must
# bind to evidence that is actually on the branch.
dreset
dmode ok
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
D_ROWS="$(grep -cE '^\| RS-[0-9]+ +\|' "$DMANIFEST" 2>/dev/null)" || D_ROWS=0
if [ "$rc" -eq 1 ] && grep -q 'commit it and re-run' <<<"$out" \
   && [ "$D_ROWS" -eq 2 ] && [ "$(dcalls)" -eq 2 ] \
   && [ -s "$DTREE/.claude/lean-renders/55/RS-1.png" ] && [ -s "$DTREE/.claude/lean-renders/55/RS-2.png" ]; then
  pass "(dr1) two declared states render into two non-empty PNGs and two manifest rows, red until committed"
else fail "(dr1) expected 2 rows / 2 calls / 2 PNGs and the commit refusal, rc=$rc rows=$D_ROWS calls=$(dcalls): $out"; fi

# (dr2) the arg-asserting half made explicit: the stub was handed each declared route AND state,
# so a gate that forwarded the template or dropped {state} could not have reached (dr1).
if grep -qF 'prospects|default|' "$DCALLS" && grep -qF 'prospects|filters expanded|' "$DCALLS"; then
  pass "(dr2a) the harness received each declared {route}/{state} pair, substituted"
else fail "(dr2a) the stub's call log does not carry both substituted pairs: $(cat "$DCALLS")"; fi

# (dr2) the recorded hash IS the file's hash — recomputed here rather than trusted, because a
# manifest that hashed something else would still look like a receipt.
D_SHA="$(shasum -a 256 "$DTREE/.claude/lean-renders/55/RS-2.png" 2>/dev/null | cut -d' ' -f1)"
if [ -n "$D_SHA" ] && grep -qF "$D_SHA" "$DMANIFEST"; then
  pass "(dr2b) a recomputed sha256 of a rendered PNG matches its manifest cell"
else fail "(dr2b) the manifest does not carry RS-2's real hash ($D_SHA): $(cat "$DMANIFEST")"; fi

# (dr2c) THE REPLACEMENT-LAYER TRAP, on the same call-log oracle. An ampersand is ordinary in
# both halves of a row — a query string in a route, punctuation in a human state — and since
# bash 5.2 a bare one in a `${t//p/r}` REPLACEMENT expands to the placeholder just matched, so
# the harness is driven to the wrong view. Nothing else here can see it: the render exits 0, the
# PNG is non-empty, the two rows still hash differently (two different WRONG views), and the
# manifest records the DECLARED row, so the receipt reads as honest while the pixels are of
# something else. Only the arguments the harness actually received tell the two apart, which is
# why this rides (dr2a)'s oracle rather than a new one.
# NOTE the platform split: macOS system bash is 3.2, which predates patsub_replacement, so this
# case is vacuous there and does its killing on the ubuntu lane.
dreset
dmode ok
rm -f "$DCALLS" "$DMANIFEST"
{
  echo "# spec"; echo ""; echo "- AC-1: the thing"; echo ""; echo "## Design"; echo ""
  echo "Handoff: https://www.figma.com/design/AbC123/Prospects"; echo ""
  echo "| RS-n | route | state (what must be visible) | AC refs |"; echo "| --- | --- | --- | --- |"
  echo "| RS-1 | prospects | default | AC-1 |"
  echo "| RS-2 | prospects?tab=new&sort=asc | filters & sort expanded | AC-1 |"
} > "$DSPEC"
dcommit "an armed spec whose row carries ampersands"
out="$(dgate 3 55)"
if grep -qF 'prospects?tab=new&sort=asc|filters & sort expanded|' "$DCALLS"; then
  pass "(dr2c) an ampersand in a declared route and state reaches the harness verbatim"
else fail "(dr2c) the ampersand row was corrupted between template and harness: $out $(cat "$DCALLS")"; fi
# Teardown, and it is part of the case: this fixture is the only one here carrying an ampersand,
# so leaving it in place would let the same defect red (di1)/(di2)/(dl4) as collateral and the
# kill would no longer be attributable to one case. Restore the canonical two-row spec and
# re-render it, which is exactly the state (dr1) left for the idempotence block.
dspec_armed
dcommit "the canonical armed spec, restored"
dreset
rm -f "$DCALLS" "$DMANIFEST"
dgate 3 55 >/dev/null 2>&1

# ---- (di) AC-4: idempotence ---------------------------------------------------------------
# (di1) committed, the same evaluation passes WITHOUT re-rendering. Without this every `all`
# sweep would re-shoot every state, and each re-shoot rewrites the receipt inside the reviewed
# patch.
dcommit "the render receipt"
dreset
D_CALLS_BEFORE="$(dcalls)"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(dcalls)" -eq "$D_CALLS_BEFORE" ] \
   && grep -q 'not re-rendering' <<<"$out"; then
  pass "(di1) a pre-verdict re-run passes on the committed receipt and renders nothing again"
else fail "(di1) expected an idempotent pass, rc=$rc calls=$(dcalls) (was $D_CALLS_BEFORE): $out"; fi

# (di1b) ...and the bytes are load-bearing BEFORE a verdict exists: delete one PNG and the same
# evaluation re-renders, because the screenshots are what a review round is about to read.
rm -f "$DTREE/.claude/lean-renders/55/RS-2.png"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$(dcalls)" -gt "$D_CALLS_BEFORE" ]; then
  pass "(di1b) a missing PNG pre-verdict re-renders — the receipt alone is not the evidence yet"
else fail "(di1b) expected a re-render after deleting a PNG, calls=$(dcalls) (was $D_CALLS_BEFORE): $out"; fi
dcommit "the re-rendered receipt"

# (di2) POST-APPROVE the bytes stop mattering and the binding alone passes. Two things ride on
# this: the mandated pre-close `bash G all` sweep must not re-render (a rewritten receipt is
# inside reviewed_patch_id and would void the approve it just earned — a livelock no fix clears),
# and a resume in a fresh worktree has no PNGs at all.
dreset
printf 'verdict=approve\nrun_id: r-review-d\n' > "$DVERDICT"
rm -rf "$DTREE/.claude/lean-renders/55"
D_CALLS_BEFORE="$(dcalls)"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(dcalls)" -eq "$D_CALLS_BEFORE" ] \
   && grep -q 'this round is approved' <<<"$out"; then
  pass "(di2) post-approve, the render binding alone passes with every PNG deleted — no livelock, resume-safe"
else fail "(di2) expected a post-approve pass with no re-render, rc=$rc calls=$(dcalls): $out"; fi
rm -f "$DVERDICT"

# ---- (dl) AC-2: the disarm STATE LOCK ------------------------------------------------------
# (dl1) the armed record is written by a PASSING armed evaluation, not only by a failing one —
# the lock must exist on the path where nothing went wrong.
if [ "$(dcount "| milestone-3 | armed |")" -ge 1 ]; then
  pass "(dl1) a passing armed milestone-3 evaluation records '| milestone-3 | armed |'"
else fail "(dl1) no armed record after a passing armed run: $(cat "$DPROG")"; fi

# (dl4) and it is NOT an attempt line: arming a lane must never spend fix budget, or three
# diagnostic re-runs would hard-stop a run that failed nothing.
if [ "$(dcount "| milestone-3 | attempt |")" -eq 0 ]; then
  pass "(dl4) arming leaves the fix-budget counter untouched — the record is a lock, not a counter"
else fail "(dl4) armed evaluations appended attempt lines: $(cat "$DPROG")"; fi

# (dl2)/(dl3) mid-run disarm, refused at BOTH milestones — retiring the render evidence a review
# round would be scored against, and the run may re-enter at either milestone. What these two
# pin is exactly the WITHIN-WORKTREE lock: the progress file is machine-local, so (dl5) below is
# what keeps the pair honest about which population it covers.
printf '# spec\n\n- AC-1: x\n\n## Design\n\nDesign: none — changed my mind mid-run.\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'already armed it' <<<"$out"; then
  pass "(dl2) disarming after the lane armed reds milestone 1"
else fail "(dl2) expected the mid-run-disarm refusal at milestone 1, rc=$rc: $out"; fi
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'already armed it' <<<"$out"; then
  pass "(dl3) ...and reds milestone 3, which a resume can re-enter without re-running milestone 1"
else fail "(dl3) expected the mid-run-disarm refusal at milestone 3, rc=$rc: $out"; fi

# ...and the same disarm on a run that never armed is simply a disarm. (dl2)/(dl3) therefore turn
# on the recorded lock, not on the spec's wording.
dreset
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(dl5) the identical disarm passes on a run with no armed record — the lock is what refuses"
else fail "(dl5) expected a clean disarm with no armed record, rc=$rc: $out"; fi

# ---- (fd) AC-5: the fidelity verdict key ---------------------------------------------------
dspec_armed
dcommit "the armed spec, restored for the verdict cases"
dreset
dmode ok
out="$(dgate 3 55)"; rc=$?
dcommit "the render receipt at this head"
dreset
out="$(dgate 3 55)"; rc=$?
[ "$rc" -eq 0 ] || fail "(fd0) the armed fixture is not green at milestone 3, so the (fd) cases would assert nothing: $out"

# (fd1) the enum is validated at the writer, where the fix is one flag away.
out="$(dverdict sess-review-d r-review-d --pr 55 --verdict approve --fidelity maybe)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "must be 'pass', 'fail' or 'not-applicable'" <<<"$out"; then
  pass "(fd1) --fidelity enum-validates"
else fail "(fd1) expected an enum refusal, rc=$rc: $out"; fi

# (fd4) fail x approve is a contradiction: a design failure is a blocker and any blocker is
# needs-work. Refused at the writer rather than only at milestone 4, where it costs the round.
out="$(dverdict sess-review-d r-review-d --pr 55 --verdict approve --fidelity fail)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cannot accompany' <<<"$out"; then
  pass "(fd4) --fidelity fail with --verdict approve is refused"
else fail "(fd4) expected the fail-x-approve refusal, rc=$rc: $out"; fi

# (fd2) the key is emitted UNCONDITIONALLY, defaulting to not-applicable — the property that
# keeps a header-anchored read meaningful, and the fail-closed default on an armed run.
out="$(dverdict sess-review-d r-review-d --pr 55 --verdict approve)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^fidelity: not-applicable$' "$DVERDICT"; then
  pass "(fd2) a verdict written without --fidelity still carries the key, defaulted"
else fail "(fd2) expected an unconditional fidelity key, rc=$rc: $(cat "$DVERDICT" 2>/dev/null)"; fi

# (fd5) ...and that default is REFUSED on an armed run: a round that never scored the design is
# not an approval of it. This is failure class (3) caught at the gate.
dcommit "a verdict that scored no fidelity"
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'not fidelity=pass' <<<"$out"; then
  pass "(fd5) an armed run refuses a verdict whose fidelity is not 'pass'"
else fail "(fd5) expected the armed fidelity refusal, rc=$rc: $out"; fi

# (fd3) HEADER-ANCHORED, not first-match. The record below scores not-applicable in its header
# and quotes `fidelity: pass` in the findings a real reviewer would write about this feature —
# through --summary-file, the production path. A first-match reader certifies it.
DBODY="$WORK/dbody.md"
{
  echo "## finding"
  echo ""
  echo '```'
  echo "fidelity: pass"
  echo '```'
} > "$DBODY"
dreset
out="$(dverdict sess-review-d2 r-review-d2 --pr 55 --verdict approve --summary-file "$DBODY")"; rc=$?
dcommit "a record whose body quotes the key"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'not fidelity=pass' <<<"$out"; then
  pass "(fd3) a 'fidelity: pass' in the record's BODY is not a score — the read is anchored to the header"
else fail "(fd3) expected the armed refusal despite the body value, rc=$rc: $out"; fi

# (fd5b) and the same record scored `pass` in its header passes, so (fd5)/(fd3) turn on the
# header value and nothing else.
dreset
out="$(dverdict sess-review-d3 r-review-d3 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
dcommit "a record scoring fidelity pass"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fd5b) an armed run passes milestone 4 on a header-scored 'fidelity: pass'"
else fail "(fd5b) expected an armed milestone-4 pass, rc=$rc: $out"; fi

# ---- (ac-d) #496 AC-1: the two milestone-4 arms no other case in this file reaches -----------
# Anchored on (fd5b)'s state, which is green in every respect — so each case below turns on the
# ONE fact it introduces. Without them, two of the twenty sites in the class table would be
# classified by inspection alone, which is the half-covered taxonomy the ticket's intake found.

# The receipt is MISSING while the record scores `pass`. Class 1, not 5: the remedy the message
# gives is "re-run milestone 3 and commit the receipt", which is a BUILD action — re-spawning
# REVIEW over it would produce another record scoring the same absent receipt.
mv "$DMANIFEST" "$WORK/held-dmanifest.md"
dreset
out="$(dgate 4 55)"; rc=$?
mv "$WORK/held-dmanifest.md" "$DMANIFEST"
if [ "$rc" -eq 1 ] && grep -q 'no render receipt at' <<<"$out"; then
  pass "(ac-d1) an armed approve with no render receipt is class 1 — its remedy is a BUILD action, not another review round"
else fail "(ac-d1) expected rc=1 on a missing receipt, got $rc: $out"; fi

# ...and the ENVIRONMENT arm beside it: the receipt is there and the record scores pass, but this
# branch's render patch identity cannot be computed at all, so there is nothing to compare against.
# Class 2 — no verdict is at fault and no session can fix it; the operator fetches the base.
DCFG_NOBASE="$WORK/dconfig-nobase.json"
jq '.topology.repos.acme.baseBranch = "no-such-base"' "$DCFG" > "$DCFG_NOBASE"
[ "$(jq -r '.topology.repos.acme.baseBranch' "$DCFG_NOBASE" 2>/dev/null)" = "no-such-base" ] \
  || fail "(ac-d2-fixture) the no-base design config was not built — (ac-d2) would run against the real base"
dreset
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
        && SECOND_SHIFT_CONFIG="$DCFG_NOBASE" LEAN_PROGRESS_FILE="$DPROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 4 55 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'render patch identity' <<<"$out"; then
  pass "(ac-d2) an uncomputable render patch identity is class 2 — an environment error, never a review round"
else fail "(ac-d2) expected rc=2 on an unresolvable base, got $rc: $out"; fi

# The control: with the receipt restored and the real base, the same call is green again — so
# neither case above turned on the fixture drifting out from under (fd5b).
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(ac-d3) restored, the same evaluation passes — (ac-d1)/(ac-d2) each turned on their one fact"
else fail "(ac-d3) the restored fixture is not green, so the two cases above proved nothing: rc=$rc: $out"; fi

# (dm1) D-10's BACKSTOP. Everything else here is fresh — the verdict is the last commit, so both
# freshness arms are green — and only the receipt is stale, which is precisely a reviewer who
# scored round-1 screenshots against round-2 code and then committed an honest record.
printf 'a fix lands after the render\n' > "$DTREE/subject.txt"
dcommit "a fix, leaving the receipt behind"
dreset
out="$(dverdict sess-review-d4 r-review-d4 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
dcommit "an honest record on the new head, scored against the OLD screenshots"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'renders from' <<<"$out" \
   && ! grep -q 'file(s) changed after it' <<<"$out"; then
  pass "(dm1) a stale render receipt reds milestone 4 on a tree whose verdict freshness is green"
else fail "(dm1) expected the stale-receipt refusal alone, rc=$rc: $out"; fi

# (fd6) the UNARMED transition allowance: a record with no fidelity key at all — every record
# written before this key existed — still passes. Read through the no-design config, which is
# every consumer with no design axis.
dreset
out="$(dgate 3 55)"; rc=$?
dcommit "the re-rendered receipt for the new head"
dreset
out="$(dverdict sess-review-d5 r-review-d5 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
grep -v '^fidelity:' "$DVERDICT" > "$DVERDICT.tmp" && mv "$DVERDICT.tmp" "$DVERDICT"
dcommit "a record with the key stripped, as a pre-#394 reviewer would have written it"
dreset
out="$(dgate_nodesign 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fd6) an unarmed run tolerates a record carrying no fidelity key at all"
else fail "(fd6) expected the unarmed transition allowance, rc=$rc: $out"; fi

# (fd7) ...but a value that IS present on an unarmed run must be not-applicable, so a `pass`
# cannot be parked on an unarmed record and inherited by a later armed one.
dreset
out="$(dverdict sess-review-d6 r-review-d6 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
dcommit "a record claiming a fidelity its spec could not have armed"
dreset
out="$(dgate_nodesign 4 55)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'arms no design render lane' <<<"$out"; then
  pass "(fd7) an unarmed run refuses a fidelity value other than not-applicable"
else fail "(fd7) expected the unarmed non-applicable refusal, rc=$rc: $out"; fi

# ---- (fe) #693: an armed `fidelity: pass` must carry a conforming evidence table -------------
# The gap these close is that milestone 4's armed arm asked three MECHANICAL questions and one
# unfalsifiable one — the header reads `pass` — so the whole lane was satisfied by a receipt of
# the wrong screen, correctly hashed. Every case here is a WRITER case: the refusal is at
# cmd_verdict, where the fix is one edit, not at milestone 4 where it costs the round. No
# scenario in scenario-liveness-selftest.sh reaches the malformed-table taxonomy — the scenario
# composes ONE refusal (no table at all) against the terminal write, which is the fact that needs
# composing; the shapes below are a per-tool matter.
dspec_armed
dcommit "the armed spec, restored for the evidence cases"
dreset
dmode ok
dgate 3 55 >/dev/null 2>&1
dcommit "the render receipt at this head"
dreset
out="$(dgate 3 55)"; rc=$?
[ "$rc" -eq 0 ] || fail "(fe0) the armed fixture is not green at milestone 3, so the (fe) cases would assert nothing: $out"

# (fe1) AC-1: the omitted --summary-file. This is the shape the pre-#693 lane accepted, and the
# one a reviewer reaches for first.
out="$(dverdict sess-review-e1 r-review-e1 --pr 55 --verdict approve --fidelity pass)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no "## Design fidelity evidence" section' <<<"$out"; then
  pass "(fe1) an armed 'pass' with no summary at all is refused, naming the missing section"
else fail "(fe1) expected the missing-section refusal, rc=$rc: $out"; fi

# (fe1b) ...and a summary that IS supplied but carries only prose lands on the same refusal, so
# (fe1) turns on the section's absence rather than on the flag's.
printf 'I looked at the screens and they matched the design.\n' > "$WORK/fe-prose.md"
out="$(dverdict sess-review-e1b r-review-e1b --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-prose.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no "## Design fidelity evidence" section' <<<"$out"; then
  pass "(fe1b) a prose summary with no evidence section is refused identically — the flag is not what is checked"
else fail "(fe1b) expected the missing-section refusal on a prose summary, rc=$rc: $out"; fi

# (fe1c) ...and the refusal WROTE NOTHING. The check sits above the run-id cache whose comment
# reads "every refusal above has passed, so this is a real review round"; placed below it, a
# refused round would cache a review identity for a record that does not exist.
rm -f "$DTREE/.claude/pipeline-state/55-review-run-id"
dverdict sess-review-e1c r-review-e1c --pr 55 --verdict approve --fidelity pass >/dev/null 2>&1
if [ ! -e "$DTREE/.claude/pipeline-state/55-review-run-id" ]; then
  pass "(fe1c) a refused evidence write caches no review identity — the refusal precedes the cache"
else fail "(fe1c) the refused round cached a review identity: $(cat "$DTREE/.claude/pipeline-state/55-review-run-id" 2>/dev/null)"; fi

# (fe2) AC-6/AC-18: the accepting case, and it carries a CITED deviation — a deviation that names
# a criterion the spec declares does not force `fail`, which is the whole reason the enum is not
# simply "match".
devidence '| RS-2 | Prospects / filters expanded | unit selector | number field | text input | deviation (AC-1) |'
out="$(dverdict sess-review-e2 r-review-e2 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^fidelity: pass$' "$DVERDICT" \
   && grep -qF '| RS-2 | Prospects / filters expanded | unit selector | number field | text input | deviation (AC-1) |' "$DVERDICT"; then
  pass "(fe2) a conforming table — several rows for one state, and a cited deviation — is accepted at fidelity=pass"
else fail "(fe2) expected the conforming write to land, rc=$rc: $out / $(cat "$DVERDICT" 2>/dev/null)"; fi
devidence

# (fe3) AC-2, the OMISSION direction.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | frame node | property | design | rendered | verdict |"
  echo "| --- | --- | --- | --- | --- | --- |"
  echo "| RS-1 | Prospects / default | control height | 32px | 32px | match |"; } > "$WORK/fe-missing.md"
out="$(dverdict sess-review-e3 r-review-e3 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-missing.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no row for RS-2' <<<"$out"; then
  pass "(fe3) a table omitting a declared render state is refused, naming the missing row"
else fail "(fe3) expected the missing-row refusal, rc=$rc: $out"; fi

# (fe4) AC-2, the OTHER direction — a row the spec does not declare. Same stale-artifact argument
# that makes the spec the enumeration source: a row carried over from a round before the spec
# dropped RS-3 must not pass silently.
devidence '| RS-3 | Prospects / archived | control height | 32px | 32px | match |'
out="$(dverdict sess-review-e4 r-review-e4 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'scores RS-3, which the spec does not declare' <<<"$out"; then
  pass "(fe4) a row for an undeclared render state is refused, naming it"
else fail "(fe4) expected the undeclared-row refusal, rc=$rc: $out"; fi
devidence

# (fe5) AC-3: the header is enforced BY NAME, not by cell count. This table has six cells in every
# row and one wrong column name.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | node | property | design | rendered | verdict |"
  echo "| --- | --- | --- | --- | --- | --- |"
  echo "| RS-1 | Prospects / default | control height | 32px | 32px | match |"
  echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |"; } > "$WORK/fe-hdr.md"
out="$(dverdict sess-review-e5 r-review-e5 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-hdr.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'header row must name exactly 6 columns' <<<"$out" \
   && grep -q 'RS-n | node | property' <<<"$out"; then
  pass "(fe5) a misnamed column is refused, reporting the expected six and what was found"
else fail "(fe5) expected the header refusal, rc=$rc: $out"; fi

# (fe5d) ...and the count is EXACTLY six, never "at least six". A superset puts AC-3 ("any empty
# cell is refused") and AC-4 ("all six non-empty is accepted") in direct conflict on a 7-column
# table whose 7th cell is empty, and it leaves the empty-column refusal with a column name it
# cannot report. The per-row cell-count arm reds this table too, with a DIFFERENT message — so the
# assertion is on the header message specifically, or a relaxed header contract survives here.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | frame node | property | design | rendered | verdict | notes |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
  echo "| RS-1 | Prospects / default | control height | 32px | 32px | match | fine |"
  echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match | fine |"; } > "$WORK/fe-super.md"
out="$(dverdict sess-review-e5d r-review-e5d --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-super.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'header row must name exactly 6 columns' <<<"$out"; then
  pass "(fe5d) a seven-column superset is refused BY THE HEADER CONTRACT — exactly six, not at least six"
else fail "(fe5d) expected the header refusal on a column superset, rc=$rc: $out"; fi

# (fe5b) ...and a table with no `| --- |` separator has no locatable header at all. The data-row
# anchor cannot find the header row, so the separator is what locates it — this is the case that
# says so.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | frame node | property | design | rendered | verdict |"
  echo "| RS-1 | Prospects / default | control height | 32px | 32px | match |"
  echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |"; } > "$WORK/fe-nosep.md"
out="$(dverdict sess-review-e5b r-review-e5b --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-nosep.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'separator row' <<<"$out"; then
  pass "(fe5b) a table with no separator row is refused — the header is located by the separator, nothing else"
else fail "(fe5b) expected the separator refusal, rc=$rc: $out"; fi

# (fe5c) ...and the heading is matched at ANY depth and case-folded, mirroring design_section().
# Without this a reviewer who nested the section reads AC-1's "no section" message and cannot tell
# it from a section they never wrote.
{ echo "### DESIGN FIDELITY EVIDENCE"; echo ""
  echo "| rs-n | Frame Node | PROPERTY | Design | Rendered | Verdict |"
  echo "| --- | --- | --- | --- | --- | --- |"
  echo "| RS-1 | Prospects / default | control height | 32px | 32px | match |"
  echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |"; } > "$WORK/fe-depth.md"
out="$(dverdict sess-review-e5c r-review-e5c --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-depth.md")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fe5c) a nested, case-folded heading and header are accepted — the match is depth- and case-tolerant"
else fail "(fe5c) expected the nested heading to be accepted, rc=$rc: $out"; fi

# (fe6) AC-4: an empty cell, named by COLUMN. Cell-count-only checking could not report a name.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | frame node | property | design | rendered | verdict |"
  echo "| --- | --- | --- | --- | --- | --- |"
  echo "| RS-1 | Prospects / default | control height |  | 32px | match |"
  echo "| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |"; } > "$WORK/fe-empty.md"
out="$(dverdict sess-review-e6 r-review-e6 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-empty.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'column "design" is empty' <<<"$out"; then
  pass "(fe6) an empty cell is refused, naming the row and the column"
else fail "(fe6) expected the empty-cell refusal, rc=$rc: $out"; fi

# (fe7) AC-5: heading, header and separator, and nothing else. Without this a reviewer satisfies
# the section check vacuously.
{ echo "## Design fidelity evidence"; echo ""
  echo "| RS-n | frame node | property | design | rendered | verdict |"
  echo "| --- | --- | --- | --- | --- | --- |"; } > "$WORK/fe-norows.md"
out="$(dverdict sess-review-e7 r-review-e7 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-norows.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'carries no data row' <<<"$out"; then
  pass "(fe7) a zero-data-row section is refused against an armed spec"
else fail "(fe7) expected the empty-table refusal, rc=$rc: $out"; fi

# (fe8) AC-16: `deviation` plus a free-text reason is what the lane accepted before, and it is
# what returned `pass` twice against a wrong screen. A reason nothing can check is not a citation.
devidence
sed -e 's#| RS-1 | Prospects / default | control height | 32px | 32px | match |#| RS-1 | Prospects / default | control height | 32px | 70px | deviation — it looked fine to me |#' "$DEVIDENCE" > "$WORK/fe-bare.md"
grep -qF 'it looked fine to me' "$WORK/fe-bare.md" \
  || fail "(fe8-fixture) the bare-deviation body was not built — (fe8) would assert nothing"
out="$(dverdict sess-review-e8 r-review-e8 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-bare.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'without naming the AC-n or D-n' <<<"$out"; then
  pass "(fe8) an uncited deviation is refused — a free-text reason is not a citation"
else fail "(fe8) expected the uncited-deviation refusal, rc=$rc: $out"; fi

# (fe8b) ...and the enum token is a PREFIX anchored on a non-word boundary, so a cell that merely
# BEGINS with the token does not read as it — ledger-lint.sh reads the Surface Inventory
# disposition with the same anchor, for the same reason. Both directions of the anchor are
# exercised: `matches roughly` must not read as `match` (the trailing boundary), and `mismatch …`
# must not either (the leading one). A closed enum without both is a substring test.
devidence
sed -e 's#| RS-1 | Prospects / default | control height | 32px | 32px | match |#| RS-1 | Prospects / default | control height | 32px | 32px | matches roughly |#' "$DEVIDENCE" > "$WORK/fe-loose1.md"
sed -e 's#| RS-1 | Prospects / default | control height | 32px | 32px | match |#| RS-1 | Prospects / default | control height | 32px | 700px | mismatch — 700px vs 320px |#' "$DEVIDENCE" > "$WORK/fe-loose2.md"
{ grep -qF 'matches roughly' "$WORK/fe-loose1.md" && grep -qF 'mismatch' "$WORK/fe-loose2.md"; } \
  || fail "(fe8b-fixture) the loose-enum bodies were not built — (fe8b) would assert nothing"
out="$(dverdict sess-review-e8b r-review-e8b --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-loose1.md")"; rc=$?
out2="$(dverdict sess-review-e8c r-review-e8c --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-loose2.md")"; rc2=$?
if [ "$rc" -eq 1 ] && grep -q 'is neither "match" nor' <<<"$out" \
   && [ "$rc2" -eq 1 ] && grep -q 'is neither "match" nor' <<<"$out2"; then
  pass "(fe8b) 'matches roughly' and 'mismatch …' are both refused — the enum token is boundary-anchored, not a substring"
else fail "(fe8b) expected both loose-enum refusals, rc=$rc/$rc2: $out / $out2"; fi

# (fe9) AC-17: the DANGLING citation. This is the failure that prompted the ticket — an extra
# affordance classified as a decided deviation when no decision existed anywhere in the criteria.
devidence
sed -e 's#| RS-2 | Prospects / filters expanded | panel width | 320px | 320px | match |#| RS-2 | Prospects / filters expanded | panel width | 320px | 700px | deviation (AC-9) |#' "$DEVIDENCE" > "$WORK/fe-dangling.md"
grep -qF 'deviation (AC-9)' "$WORK/fe-dangling.md" \
  || fail "(fe9-fixture) the dangling-citation body was not built — (fe9) would assert nothing"
out="$(dverdict sess-review-e9 r-review-e9 --pr 55 --verdict approve --fidelity pass --summary-file "$WORK/fe-dangling.md")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cites AC-9, which the spec does not declare' <<<"$out"; then
  pass "(fe9) a citation the spec never declares is refused as dangling, naming the reference"
else fail "(fe9) expected the dangling-citation refusal, rc=$rc: $out"; fi

# (fe10) AC-7: the other two enum values need no table, on the same armed spec. Without this the
# check could be keyed on the armed spec alone and every finding round would be blocked from
# recording what it found.
out="$(dverdict sess-review-e10 r-review-e10 --pr 55 --verdict approve --fidelity not-applicable)"; rc=$?
out2="$(dverdict sess-review-e10b r-review-e10b --pr 55 --verdict needs-work --fidelity fail)"; rc2=$?
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  pass "(fe10) 'not-applicable' and 'fail' write with no evidence table — the obligation is 'pass'-only"
else fail "(fe10) expected both non-pass values to write, rc=$rc rc2=$rc2: $out / $out2"; fi

# (fe11) AC-7's OTHER half: an UNARMED consumer. Same tree, same spec, read through a config with
# no design axis — the pairing that keeps the AND honest. Milestone 4 refuses this record in its
# own words; the writer must not, or every consumer with no design axis breaks.
out="$( unset RUN_ID; cd "$DTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$DPROG" \
        CLAUDE_CODE_SESSION_ID=sess-review-e11 RUN_ID=r-review-e11 \
        bash "$GATE" verdict 55 --pr 55 --verdict approve --fidelity pass 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fe11) with no design.provider configured the writer demands nothing — the obligation is provider-gated"
else fail "(fe11) an unarmed consumer was refused at the writer, rc=$rc: $out"; fi

# (fe12) AC-8: a DISARMED spec scoring `pass`. design_state has four outcomes, not two, and
# treating a disarm as merely not-armed would let a ticket that declared no render state bank one.
printf '# spec\n\n- AC-1: x\n\n## Design\n\nDesign: none — no FE surface in this ticket.\n' > "$DSPEC"
out="$(dverdict sess-review-e12 r-review-e12 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'disarms the design lane' <<<"$out"; then
  pass "(fe12) a disarmed spec cannot bank a fidelity pass"
else fail "(fe12) expected the disarmed refusal, rc=$rc: $out"; fi

# (fe13) ...and an `error:` state — here a spec declaring render states with no handoff link. A
# section too broken to enumerate is exactly the tamper surface: under a not-armed reading it
# would sail through.
printf '# spec\n\n- AC-1: x\n\n## Design\n\n| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n| RS-1 | p | default | AC-1 |\n' > "$DSPEC"
out="$(dverdict sess-review-e13 r-review-e13 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'design arming cannot be resolved' <<<"$out"; then
  pass "(fe13) a malformed '## Design' section is refused at the writer, not read as not-armed"
else fail "(fe13) expected the unresolvable-arming refusal, rc=$rc: $out"; fi

# (fe14) ...and an ABSENT spec, which design_state reads as `unarmed` — the same answer it gives a
# consumer with no design axis. The provider being configured is what tells the two apart, and
# without that split an armed ticket reviewed from the wrong checkout banks a pass on a file
# nobody read.
mv "$DSPEC" "$WORK/fe-held-spec.md"
out="$(dverdict sess-review-e14 r-review-e14 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
mv "$WORK/fe-held-spec.md" "$DSPEC"
if [ "$rc" -eq 1 ] && grep -q 'no spec at' <<<"$out"; then
  pass "(fe14) an absent spec under a configured provider is refused — not read as an unarmed consumer"
else fail "(fe14) expected the absent-spec refusal, rc=$rc: $out"; fi

# (fe15) AC-9: NO MILESTONE-4 BACKSTOP, and this is what that buys. A verdict record carries no
# timestamp and no schema version, so a legacy evidence-free `pass` is byte-indistinguishable from
# one whose section was stripped — a backstop that cannot tell them apart adds no assurance and
# strands every record written before this shipped. The record below is exactly that legacy shape.
dspec_armed
dcommit "the armed spec, restored"
dreset
dgate 3 55 >/dev/null 2>&1
dcommit "the render receipt at this head"
dreset
devidence
out="$(dverdict sess-review-e15 r-review-e15 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
[ "$rc" -eq 0 ] || fail "(fe15-fixture) the conforming write did not land, so (fe15) would strip nothing: $out"
awk '/^#+[[:space:]]+[Dd]esign fidelity evidence/ { exit } { print }' "$DVERDICT" > "$DVERDICT.tmp" && mv "$DVERDICT.tmp" "$DVERDICT"
grep -q 'Design fidelity evidence' "$DVERDICT" \
  && fail "(fe15-fixture) the evidence section was not stripped — (fe15) would assert nothing"
dcommit "a pre-#693 record: fidelity pass, no evidence section"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fe15) milestone 4's armed arm is unchanged — an already-committed evidence-free 'pass' still passes"
else fail "(fe15) a legacy record was retroactively failed by the evidence rule, rc=$rc: $out"; fi

# (fe16) AC-14: record_key is an UNANCHORED whole-file scan, and milestone 4 reads `rounds` and
# `reviewed_patch_id` through it. The evidence table is reviewer-authored text inside that scan
# range, so a table cell shaped like a key must not win the first-match race against the header.
# Read through the gate's own record_key, never a grep spelled here.
devidence
sed -e 's#| RS-1 | Prospects / default | control height | 32px | 32px | match |#| RS-1 | Card / rounds: 9 | reviewed_patch_id: cafebabe | 32px | 32px | match |#' "$DEVIDENCE" > "$WORK/fe-keys.md"
grep -qF 'reviewed_patch_id: cafebabe' "$WORK/fe-keys.md" \
  || fail "(fe16-fixture) the key-shaped body was not built — (fe16) would assert nothing"
out="$(dverdict sess-review-e16 r-review-e16 --pr 55 --verdict approve --rounds 3 --fidelity pass --summary-file "$WORK/fe-keys.md")"; rc=$?
fe_rounds="$(dreckey rounds "$DVERDICT")"
fe_pid="$(dreckey reviewed_patch_id "$DVERDICT")"
if [ "$rc" -eq 0 ] && [ "$fe_rounds" = "3" ] && [ -n "$fe_pid" ] && [ "$fe_pid" != "cafebabe" ]; then
  pass "(fe16) a table cell shaped like a record key does not displace the header's value for rounds or reviewed_patch_id"
else fail "(fe16) record_key read rounds='$fe_rounds' reviewed_patch_id='$fe_pid' (rc=$rc): $out"; fi

# ...and the same record still walks milestone 4, so (fe16) is about the READER and not about a
# write the gate happened to refuse.
dcommit "a record whose evidence table contains key-shaped text"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fe16b) ...and milestone 4 passes on it — the key-shaped cells changed nothing downstream"
else fail "(fe16b) milestone 4 refused a record whose table carries key-shaped text, rc=$rc: $out"; fi
devidence

# ---- (fp) the panel attestation: the mandatory fidelity reviewer (#708) ---------------------
# On an armed ticket the provider's fidelity reviewer is not routed by judgment, and `panel:` is
# what makes its absence detectable: it lists the reviewers the round actually got a result back
# from, so "never selected" and "went dark" are the same shape here and both are refused. These
# cases drive the WRITER and milestone 4; the merge boundary's identical arm is
# check-lean-chain-selftest.sh's (X7)-(X11), over the same lockstep derivation.
#
# (fp0) runs first and is the vacuity guard: everything below asserts nothing if the fixture's
# armed round could not be written at all.
dspec_armed
dcommit "the armed spec for the panel cases"
dreset
dgate 3 55 >/dev/null 2>&1
dcommit "the render receipt for the panel cases"
dreset
devidence
out="$(dverdict sess-review-p0 r-review-p0 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
fp_panel="$(dpanelkey "$DVERDICT")"
if [ "$rc" -eq 0 ] && [ "$fp_panel" = "$DPANEL" ]; then
  pass "(fp0) an armed round naming the mandatory reviewer writes, and the record carries the panel back WHOLE — qualified names and commas survive the reader"
else fail "(fp0) rc=$rc panel='$fp_panel' expected '$DPANEL': $out"; fi
# COMMITTED here, because every refusal below writes nothing and so commits nothing: without this
# (fp5) would red on an uncommitted record instead of on its panel, and would assert nothing about
# the arm it exists for.
dcommit "the green armed record for the panel cases"

# (fp1) NO PANEL AT ALL. `--panel` is bypassed here rather than defaulted, which is the one thing
# every other case in this suite relies on dverdict not doing.
fp_before="$(cat "$DVERDICT" 2>/dev/null)"
out="$( unset RUN_ID; cd "$DTREE" && SECOND_SHIFT_CONFIG="$DCFG" LEAN_PROGRESS_FILE="$DPROG" \
        CLAUDE_CODE_SESSION_ID=sess-review-p1 RUN_ID=r-review-p1 \
        bash "$GATE" verdict 55 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE" 2>&1 )"; rc=$?
fp_after="$(cat "$DVERDICT" 2>/dev/null)"
if [ "$rc" -eq 1 ] && grep -q -- '--panel <a,b,c> is required' <<<"$out" \
   && [ "$fp_before" = "$fp_after" ]; then
  pass "(fp1) an armed round with no --panel is refused at the writer, and the committed record is untouched"
else fail "(fp1) expected the missing-panel refusal with no write, rc=$rc: $out"; fi

# (fp2) THE RESERVED SEAT IS EMPTY: a full panel of other reviewers with the mandatory one absent.
# That is what a dark fidelity reviewer looks like in the returned set, and what routing that
# never selected it looks like — indistinguishable here, and refused either way.
out="$(dverdict sess-review-p2 r-review-p2 --pr 55 --verdict approve --fidelity pass \
        --panel "review-toolkit:security-reviewer,review-toolkit:maintainability-reviewer" \
        --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'design-toolkit:figma-faithful-reviewer' <<<"$out"; then
  pass "(fp2) an armed round whose panel omits the mandatory reviewer is refused, and the refusal names the reviewer"
else fail "(fp2) expected the panel-omission refusal, rc=$rc: $out"; fi

# (fp3) SUBSTRING IS NOT MEMBERSHIP. No shipped reviewer name contains another's today, which is
# exactly why this needs pinning: the day one does is the day a `case` without comma anchors, or a
# bare grep, silently stops discriminating.
out="$(dverdict sess-review-p3 r-review-p3 --pr 55 --verdict approve --fidelity pass \
        --panel "acme:pre-design-toolkit:figma-faithful-reviewer-v2" \
        --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not name design-toolkit:figma-faithful-reviewer' <<<"$out"; then
  pass "(fp3) a panel entry that merely CONTAINS the reviewer's name is not that reviewer — the match is a whole comma-separated token"
else fail "(fp3) a substring panel entry was credited as a dispatch, rc=$rc: $out"; fi

# (fp4) NOT GATED ON --fidelity. A needs-work record is evidence too, and the next round inherits
# its coverage by reference; a round that never dispatched the mandatory reviewer has no coverage
# of that dimension to hand on, whatever verdict it reached. Without this the arm could be keyed
# on `pass` and every finding round would carry an unchecked panel into the chain.
out="$(dverdict sess-review-p4 r-review-p4 --pr 55 --verdict needs-work --fidelity fail \
        --panel "review-toolkit:security-reviewer")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'design-toolkit:figma-faithful-reviewer' <<<"$out"; then
  pass "(fp4) the panel obligation is not gated on --fidelity — a needs-work round owes it too"
else fail "(fp4) a needs-work round skipped the panel obligation, rc=$rc: $out"; fi

# (fp5) MILESTONE 4, over a record this writer would never have produced: one committed before the
# key existed, or hand-edited afterwards, which is the case a READER has to own. Only the `panel:`
# line changes, and the verdict record is excluded from both patch bindings, so a red here is the
# panel arm and can be nothing else. rc=5 — the remedy is another review round, not a build fix.
dreset
out="$(dgate 4 55)"; ld_m4_ok=$?
[ "$ld_m4_ok" -eq 0 ] || fail "(fp5-fixture) milestone 4 was not green before the edit, so (fp5) would assert nothing: $out"
awk '/^panel:/ { print "panel: review-toolkit:security-reviewer"; next } { print }' "$DVERDICT" > "$DVERDICT.tmp" \
  && mv "$DVERDICT.tmp" "$DVERDICT"
grep -q 'design-toolkit:figma-faithful-reviewer' "$DVERDICT" \
  && fail "(fp5-fixture) the panel line was not rewritten — (fp5) would assert nothing"
dcommit "a record whose panel lost the mandatory reviewer"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'does not name design-toolkit:figma-faithful-reviewer' <<<"$out"; then
  pass "(fp5) milestone 4 refuses a committed record whose panel lacks the mandatory reviewer (5 — get a review round)"
else fail "(fp5) expected rc=5 with the panel violation, got rc=$rc: $out"; fi

# (fp6) ...and an armed record with NO panel key at all. #708 D-15 grandfathers nothing: without
# the key, nothing in the branch says which reviewers ran, which is the whole condition the key
# was added to make visible. The writer's unarmed `panel: none` sentinel lands here too.
awk '/^panel:/ { next } { print }' "$DVERDICT" > "$DVERDICT.tmp" && mv "$DVERDICT.tmp" "$DVERDICT"
grep -q '^panel:' "$DVERDICT" && fail "(fp6-fixture) the panel key was not removed — (fp6) would assert nothing"
dcommit "a record predating the panel key"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 5 ] && grep -q 'panel=<none>' <<<"$out"; then
  pass "(fp6) an armed record carrying no panel key is refused too — nothing is grandfathered"
else fail "(fp6) expected rc=5 naming the absent panel, got rc=$rc: $out"; fi

# (fp7) THE UNARMED CONSUMER is untouched. Same tree, same spec, read through a config with no
# design axis — the pairing that keeps the obligation provider-gated. Every consumer without a
# design lane would otherwise be unable to write a verdict at all.
out="$( unset RUN_ID; cd "$DTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$DPROG" \
        CLAUDE_CODE_SESSION_ID=sess-review-p7 RUN_ID=r-review-p7 \
        bash "$GATE" verdict 55 --pr 55 --verdict approve 2>&1 )"; rc=$?
fp7_panel="$(dpanelkey "$DVERDICT")"
if [ "$rc" -eq 0 ] && [ "$fp7_panel" = "none" ]; then
  pass "(fp7) with no design.provider configured the writer demands no panel, and records the 'none' sentinel rather than an absence"
else fail "(fp7) unarmed write rc=$rc panel='$fp7_panel' (expected 0 / none): $out"; fi

# Restore a green armed record for anything downstream that reads this tree.
dspec_armed
dcommit "the armed spec, restored after the panel cases"
dreset
dgate 3 55 >/dev/null 2>&1
dcommit "the render receipt, restored"
dreset
dverdict sess-review-p9 r-review-p9 --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE" >/dev/null 2>&1
dcommit "a green armed record, restored"

# ---- (dpx) #711: the RENDERED MEASUREMENT ---------------------------------------------------
# The gap this closes, in the ticket's own words: milestone 3 renders and hashes, review-lean 5b
# writes an evidence table the writer checks for SHAPE, and no gate read a NUMBER — so a screen
# rendered at 2.2x the design's width passed every mechanical check (#692). The plan already
# recorded the design side (#710); this block is the rendered side arriving.
#
# LAST IN THE DESIGN BLOCK, and self-establishing. Every case here rewrites the plan, the payload
# and the spec's own state matrix, so running it earlier would hand (dl)/(fd)/(fe)/(fp) a fixture
# whose measured nodes they never asserted anything about.
#
# THE STUB IS THE HARNESS, exactly as it is for the screenshots: it writes whatever payload the
# case put in $DRECTS, and the gate's job is arithmetic over what a harness hands it. A fixture
# that computed the medians itself would be the mirror harness docs/testing.md forbids, and would
# agree with a broken gate forever.
dpx_setup() { # dpx_setup <rects-json> <dimension-row>...
  local rects="$1"; shift
  dmode ok
  dcfg "$DSTUB_CMD" "" "${DPX_TOL:-}"
  dspec_armed
  rm -f "$DVERDICT"
  {
    echo "# translation plan — acme #55"
    echo ""
    echo "planned_from: pending"
    echo ""
    echo "| node | repo component | why this component |"
    echo "| --- | --- | --- |"
    echo "| Filter panel | @acme/ui Drawer | the frame draws a right-edge sheet over a scrim |"
    echo ""
    echo "| node | RS | px | dimensions | overflow |"
    echo "| --- | --- | --- | --- | --- |"
    printf '%s\n' "$@"
  } > "$DPLAN"
  drects_write "$rects"
  dcommit "a plan and a measurement payload"
  dreset
  rm -f "$DCALLS" "$DMANIFEST"
  rm -rf "$DTREE/.claude/lean-renders/55"
}
DPX_TOL=""

# Findings are JOINED into one refusal line (D-5), so `grep -c` would answer 1 for any number of
# them — which is the difference between "k is named once" and "k is named at all", and between
# three nodes reported and one. Count OCCURRENCES.
dpx_hits() { # dpx_hits <needle> <<< output
  local n
  n="$(grep -o "$1" | grep -c .)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

# (dpx1) AC-1 VERBATIM. One stated axis, so the median absorbs everything and the arm degenerates
# to plain absolute comparison — which is the whole reason AC-1 and AC-2 survive the scale-adaptive
# rewrite unchanged. The refusal has to name all four of RS-n, the node, the design and the render:
# "a size is wrong" sends the reader back to the file the gate just read.
dpx_setup '{ "Control": { "height": 107 } }' '| Control | RS-1 | -×32 | fixed 32px tall | none |'
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'RS-1' <<<"$out" && grep -q 'Control' <<<"$out" \
   && grep -q 'design 32' <<<"$out" && grep -q 'rendered 107' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ] && [ ! -f "$DMANIFEST" ]; then
  pass "(dpx1) a 32px control rendered at 107px reds milestone 3, naming the state, the node and both numbers, and spends a fix attempt"
else fail "(dpx1) rc=$rc attempts=$(dcount '| milestone-3 | attempt |') manifest=$([ -f "$DMANIFEST" ] && echo yes || echo no): $out"; fi

# (dpx2) AC-2, both halves. 33 against a design 32 is inside the default tolerance and passes
# through to the receipt; the SAME tree under tolerancePx: 0 reds. Two runs of one fixture, because
# the claim is about the key and not about the numbers.
dpx_setup '{ "Control": { "height": 33 } }' '| Control | RS-1 | -×32 | fixed 32px tall | none |'
out="$(dgate 3 55)"; rc=$?
# The claim is that the COMPARISON passed, so it is asserted as "the render pass ran to its end
# and raised no measurement finding" rather than on an exit code — whether the receipt then needs
# committing is the receipt bookkeeping's business and moves with what the previous case left in
# the tree.
if grep -q 'rendered 2 state(s)' <<<"$out" && [ -f "$DMANIFEST" ] \
   && [ "$(dpx_hits 'out of proportion' <<<"$out")" -eq 0 ] \
   && [ "$(dpx_hits '(scale)' <<<"$out")" -eq 0 ]; then
  pass "(dpx2) a 1px difference passes at the default tolerance and the render pass reaches its receipt"
else fail "(dpx2) expected a clean measurement, rc=$rc: $out"; fi

DPX_TOL=0
dpx_setup '{ "Control": { "height": 33 } }' '| Control | RS-1 | -×32 | fixed 32px tall | none |'
out="$(dgate 3 55)"; rc=$?
DPX_TOL=""
if [ "$rc" -eq 1 ] && grep -q 'tolerancePx=0' <<<"$out" && grep -q 'rendered 33' <<<"$out" \
   && [ ! -f "$DMANIFEST" ]; then
  pass "(dpx2) …and the same 1px difference reds at tolerancePx: 0 — the key is read, not decorative"
else fail "(dpx2) expected the zero-tolerance refusal, rc=$rc: $out"; fi

# (dpx3) AC-7 — THE #692 DEFECT CLASS, and the arm's fail-open flank. Both nodes render at a common
# factor, so median normalization ABSORBS it and every `shape` test passes: an implementation that
# lost the `scale` check still reds on genuine per-node defects and looks alive while being blind to
# this exact defect. Two assertions, and the second is the one that matters: k is named ONCE, not
# once per node, because "everything is 2.2x" is one fact and repeating it per node buries it.
dpx_setup '{ "Header": { "height": 70 }, "Body": { "height": 110 } }' \
  '| Header | RS-1 | -×32 | fixed 32px tall | none |' \
  '| Body | RS-1 | -×50 | fixed 50px tall | none |'
out="$(dgate 3 55)"; rc=$?
dpx_scale="$(dpx_hits '(scale)' <<<"$out")"
dpx_shape="$(dpx_hits 'out of proportion' <<<"$out")"
if [ "$rc" -eq 1 ] && [ "$dpx_scale" -eq 1 ] && [ "$dpx_shape" -eq 0 ] \
   && grep -q 'k=2.194' <<<"$out"; then
  pass "(dpx3) a whole state rendered at a common factor reds as 'scale' naming k ONCE, with no per-node shape red the median absorbed"
else fail "(dpx3) rc=$rc scale=$dpx_scale shape=$dpx_shape: $out"; fi

# (dpx4) AC-8 — ALL THREE, IN ONE MESSAGE. Four stated axes at ratios 0.9/0.9/1.1/1.1 put the
# median at 1.0, which no node matches: every node is out of proportion and NOTHING is explained by
# a common factor, so this is the exact complement of (dpx3). One attempt is charged, which is the
# accumulate-and-join claim made as a number — first-only would spend one of three attempts per
# node revealed and hard-stop at attempt 4 having shown the operator three of four.
dpx_setup '{ "Header": { "width": 90, "height": 180 }, "Body": { "width": 110 }, "Footer": { "height": 110 } }' \
  '| Header | RS-1 | 100×200 | fixed | none |' \
  '| Body | RS-1 | 100×- | fill height | none |' \
  '| Footer | RS-1 | -×100 | fill width | none |'
out="$(dgate 3 55)"; rc=$?
dpx_shape="$(dpx_hits 'out of proportion' <<<"$out")"
if [ "$rc" -eq 1 ] && grep -q 'Header' <<<"$out" && grep -q 'Body' <<<"$out" && grep -q 'Footer' <<<"$out" \
   && [ "$dpx_shape" -eq 4 ] && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ]; then
  pass "(dpx4) three mismatching nodes are named together in one refusal, on one fix attempt"
else fail "(dpx4) rc=$rc shape=$dpx_shape attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx5) AC-3, first half: the sibling never arrives. ABSENT budget — the harness owns that file and
# no edit in this worktree reaches it, which is #642's criterion applied verbatim. The screenshot
# itself is fine, so nothing else in the render pass can see this.
dpx_setup "$DRECTS_OK" '| Filter panel | RS-2 | 320×604 | fixed | none |'
printf 'none\n' > "$DRMODE"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no rects sibling' <<<"$out" && grep -q 'not a fix attempt' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ] && [ ! -f "$DMANIFEST" ]; then
  pass "(dpx5) a state whose harness wrote no rects sibling reds on the absent budget — a green exit code and a real PNG do not make it a pass"
else fail "(dpx5) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx6) AC-3, second half: the file is there and does not carry a node the plan measures. FIX
# budget, deliberately — on the absent budget a session would earn unlimited free retries by naming
# nodes the harness never emits.
dpx_setup '{ "Filter panel": { "width": 320 } }' '| Ghost | RS-1 | -×32 | fixed | none |'
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'does not carry' <<<"$out" && grep -q 'Ghost' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ]; then
  pass "(dpx6) a plan node the rects file does not carry reds on the FIX budget — omitting the key is not how a node opts out of measurement"
else fail "(dpx6) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx7) malformed rects JSON. The harness's output contract, so the absent budget again.
dpx_setup "$DRECTS_OK" '| Filter panel | RS-2 | 320×604 | fixed | none |'
printf 'bad\n' > "$DRMODE"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'not a JSON object' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 0 ]; then
  pass "(dpx7) an unparseable rects sibling reds on the absent budget, naming the file rather than the branch"
else fail "(dpx7) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx8) the entry resolved the node and measured half of it. Distinct from (dpx6) on purpose: a
# node absent from the file and a node present with one axis are different facts about the harness,
# and collapsing them would leave the second reading as "no such node".
dpx_setup '{ "Control": { "height": 32 } }' '| Control | RS-1 | 320×32 | fixed | none |'
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'states a width for node' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ]; then
  pass "(dpx8) an axis the plan states and the rects entry omits reds — a resolved node measured on one axis is not a pass on the other"
else fail "(dpx8) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx9) THE PROSE ESCAPE HATCH, closed. `px` is machine-read and a cell that does not parse reds
# rather than being skipped — skipping is what would let one unparseable cell silently opt a node
# out of the only numeric check on this lane. `dimensions` next to it stays prose, which is the
# whole reason the numbers got their own column.
dpx_setup '{ "Control": { "height": 32 } }' '| Control | RS-1 | about 32px tall | fixed | none |'
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'is not <w>' <<<"$out" \
   && [ "$(dcount '| milestone-3 | attempt |')" -eq 1 ]; then
  pass "(dpx9) a px cell that does not parse reds — an unreadable number is not a waiver"
else fail "(dpx9) rc=$rc attempts=$(dcount '| milestone-3 | attempt |'): $out"; fi

# (dpx10) a plan row measured in a state the spec does not declare. It is compared against nothing
# at all, which is the same silence a missing node is, and it is refused BEFORE the harness runs —
# rendering every state to then report a plan defect buys the operator nothing.
dpx_setup "$DRECTS_OK" '| Filter panel | RS-9 | 320×604 | fixed | none |'
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'RS-9' <<<"$out" && grep -q 'does not declare' <<<"$out" \
   && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpx10) a plan row measured in an undeclared render state reds before the harness is called once"
else fail "(dpx10) rc=$rc renders=$(dcalls): $out"; fi

# (dpx11) tolerancePx that is not a non-negative integer. config-lint owns this rule too, but the
# config is gitignored and never travels to CI, so the gate cannot assume anyone ran it — and an
# unvalidated value reads as 0 in awk, turning a config typo into a wall of shape reds about the
# branch.
DPX_TOL=-1
dpx_setup "$DRECTS_OK" '| Filter panel | RS-2 | 320×604 | fixed | none |'
out="$(dgate 3 55)"; rc=$?
DPX_TOL=""
if [ "$rc" -eq 1 ] && grep -q 'tolerancePx' <<<"$out" && grep -q 'not a fix attempt' <<<"$out" \
   && [ "$(dcalls)" -eq 0 ]; then
  pass "(dpx11) a tolerancePx that is not a non-negative integer reds before anything is compared against it"
else fail "(dpx11) rc=$rc renders=$(dcalls): $out"; fi

# (dpx12) AC-4 and the receipt shape, on one conforming render. The sibling joins the hashed set as
# its own `RS-n.rects` row — asserted by RECOMPUTING the hash here, because a receipt that hashed
# something else would still look like a receipt — and editing it afterwards then stales the
# receipt exactly as editing a PNG does, which is D-9's "no new gate code" claim made as a test.
dpx_setup "$DRECTS_OK" '| Filter panel | RS-2 | 320×604 | fixed | none |'
out="$(dgate 3 55)"; rc=$?
dpx_rrows="$(grep -cE '^\| RS-[0-9]+\.rects +\|' "$DMANIFEST" 2>/dev/null)" || dpx_rrows=0
dpx_rsha="$(shasum -a 256 "$DTREE/.claude/lean-renders/55/RS-2.png.rects.json" 2>/dev/null | cut -d' ' -f1)"
if grep -q 'rendered 2 state(s)' <<<"$out" && [ "$dpx_rrows" -eq 2 ] \
   && [ -n "$dpx_rsha" ] && grep -qF "$dpx_rsha" "$DMANIFEST"; then
  pass "(dpx12) a conforming measurement renders green and puts a hashed 'RS-n.rects' row beside every screenshot row"
else fail "(dpx12) rc=$rc rects-rows=$dpx_rrows sha=$dpx_rsha: $out $(cat "$DMANIFEST" 2>/dev/null)"; fi

dcommit "the render receipt with its rects rows"
dreset
DPX_CALLS_BEFORE="$(dcalls)"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(dcalls)" -eq "$DPX_CALLS_BEFORE" ]; then
  pass "(dpx12) …and the committed receipt is idempotent — the rects rows do not force a re-render on every sweep"
else fail "(dpx12) expected an idempotent pass, rc=$rc calls=$(dcalls) (was $DPX_CALLS_BEFORE): $out"; fi

printf '{ "Filter panel": { "width": 640, "height": 604 } }\n' > "$DTREE/.claude/lean-renders/55/RS-2.png.rects.json"
dreset
out="$(dgate 3 55)"; rc=$?
if [ "$(dcalls)" -gt "$DPX_CALLS_BEFORE" ]; then
  pass "(dpx12) …and editing the rects file after the receipt is written stales it and re-renders — the measurements are evidence, hashed like the pixels"
else fail "(dpx12) an edited rects file did not stale the receipt, calls=$(dcalls) (was $DPX_CALLS_BEFORE): $out"; fi
DPX_TOL=""

# ---- (ea) the entry attestation: recorded, and enforced (#416) -------------------------------
# The gap this closes is not "entry fails open" — it always failed closed. It is that NOTHING
# CHECKED IT RAN: `cmd_entry` wrote nothing durable and no later reader looked, so a run that
# skipped step 1 reached five green milestones and a merged PR. Two such runs exist. These cases
# pin both halves: the row, and the refusal that reads it.
PTREE="$WORK/ptree"
mkdir -p "$PTREE/docs/plans" "$PTREE/.claude/audit"
git -C "$PTREE" init -q
git -C "$PTREE" config user.email t@example.invalid
git -C "$PTREE" config user.name t
printf '.claude/\n' > "$PTREE/.gitignore"
printf '# spec\n\n- AC-1: a thing\n' > "$PTREE/docs/plans/acme-8-lean.md"
git -C "$PTREE" add -A >/dev/null 2>&1
git -C "$PTREE" commit -q -m "p fixture" >/dev/null 2>&1
git -C "$PTREE" update-ref refs/remotes/origin/main HEAD
PPROG="$WORK/pprogress.md"
PSID="sess-p-build"
printf '{"tool":"Bash"}\n{"tool":"Read"}\n' > "$PTREE/.claude/audit/$PSID.jsonl"
pgate() { # pgate <args...> — a build session's own environment: session id set, ledger live
  # HERMETICITY (#432). cmd_entry now reads the telemetry env vars out of its OWN inherited
  # environment and stamps the resolved state onto the attestation row. The operator running this
  # suite is very likely IN an exporting session, so inheriting either variable would make (ea1)
  # and the (tel*) cases below assert whatever that machine happens to export — green here, red
  # on a colleague's laptop. Unset both; the cases that need a state set them explicitly.
  ( unset RUN_ID CLAUDE_CODE_ENABLE_TELEMETRY OTEL_EXPORTER_OTLP_ENDPOINT
    cd "$PTREE" && CLAUDE_CODE_SESSION_ID="$PSID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$PPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
pgate_tel() { # pgate_tel <VAR=value…> -- <args…> — same, with an explicit telemetry environment
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  ( unset RUN_ID CLAUDE_CODE_ENABLE_TELEMETRY OTEL_EXPORTER_OTLP_ENDPOINT
    cd "$PTREE" && env "${envs[@]}" CLAUDE_CODE_SESSION_ID="$PSID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$PPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
# Capture-then-default, never `grep -c … || echo 0`: on zero matches grep PRINTS "0" *and*
# exits 1, so the fallback appends a second "0" and every `-eq` against it throws. This suite's
# older count_in_progress has the same shape and gets away with it only because its callers
# never compare against zero — (ea3) does.
pcount() {
  local n
  [ -f "$PPROG" ] || { echo 0; return 0; }
  n="$(grep -cF "$1" "$PPROG" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

rm -f "$PPROG"
out="$(pgate entry 8)"; rc=$?
# All three fields, not merely the marker: the path and the count are what make the row an
# ATTESTATION rather than a bit, and a writer that dropped them would still satisfy every
# presence-only reader downstream.
if [ "$rc" -eq 0 ] && [ "$(pcount '| entry | ledger=')" -eq 1 ] \
   && grep -qF "/.claude/audit/$PSID.jsonl | lines=2 | telemetry=off | session=$PSID" "$PPROG"; then
  pass "(ea1) entry records one row carrying the resolved ledger path, its line count, the telemetry state and the session id"
else fail "(ea1) expected one full entry row, rc=$rc: $(cat "$PPROG" 2>/dev/null)"; fi

out="$(pgate entry 8)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(pcount '| entry | ledger=')" -eq 1 ]; then
  pass "(ea2) a second entry call is idempotent — the row is not duplicated"
else fail "(ea2) expected still exactly one row, rc=$rc, count=$(pcount '| entry | ledger=')"; fi

# ---- (tel) the entry-side telemetry probe (#432) --------------------------------------------
# A session launched without CLAUDE_CODE_ENABLE_TELEMETRY exports nothing, and the run discovers
# it at step 7 — after all the work is done, when the datapoints can never be recovered. The gate
# is a bash child of the `claude` process, so its own inherited environment IS the export
# decision the run never had. Two properties are load-bearing and pull in opposite directions:
# the state must be REPORTED and stamped, and it must NEVER be a refusal (D-1/D-3 — nothing
# downstream consumes cost, and the feature is opt-in, so refusing would promote it to a hard
# precondition for every consumer that has no collector).
#
# A port nothing is listening on. Resolved rather than hard-coded: a fixed port that happened to
# be occupied on the operator's machine would turn (tel2) into a silent false green.
DEAD_PORT=""
for _p in 45317 45318 45319 45320 45321; do
  (exec 3<>"/dev/tcp/127.0.0.1/$_p") 2>/dev/null || { DEAD_PORT="$_p"; break; }
done

rm -f "$PPROG"
out="$(pgate_tel -u CLAUDE_CODE_ENABLE_TELEMETRY -- entry 8)"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qF 'CLAUDE_CODE_ENABLE_TELEMETRY is not set' <<<"$out" \
   && grep -qF 'cannot be recovered after the run' <<<"$out" \
   && grep -qF '| telemetry=off |' "$PPROG"; then
  pass "(tel1) a non-exporting session warns, names the unrecoverable consequence, and stamps telemetry=off — WITHOUT refusing"
else fail "(tel1) expected rc=0 + the off warning + the stamped row, rc=$rc: $out"; fi

if [ -n "$DEAD_PORT" ]; then
  rm -f "$PPROG"
  out="$(pgate_tel CLAUDE_CODE_ENABLE_TELEMETRY=1 "OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:$DEAD_PORT" -- entry 8)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -qF '| telemetry=nocoll |' "$PPROG" \
     && grep -qF 'nothing is accepting' <<<"$out"; then
    pass "(tel2) exporting enabled but no collector listening resolves to nocoll, still rc=0"
  else fail "(tel2) expected nocoll, rc=$rc: $out / $(cat "$PPROG" 2>/dev/null)"; fi
else
  fail "(tel2) could not find a closed loopback port to probe — the case could not run"
fi

# (tel3) OR-1: the reachability half is SKIPPED on anything that is not a plain-http loopback
# endpoint, and the state falls back to the env var alone. A probe that fired against a working
# REMOTE collector would warn on a healthy setup, and a warning that cries wolf gets ignored —
# which costs more than the missing signal. The endpoint below is deliberately unreachable, so a
# probe that ran anyway would resolve nocoll and red this case.
rm -f "$PPROG"
out="$(pgate_tel CLAUDE_CODE_ENABLE_TELEMETRY=1 "OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.example.invalid:4317" -- entry 8)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF '| telemetry=on |' "$PPROG"; then
  pass "(tel3) a non-loopback/non-http endpoint skips the reachability probe and reports on"
else fail "(tel3) expected telemetry=on for the skipped probe, rc=$rc: $(cat "$PPROG" 2>/dev/null)"; fi

# (tel4) …and a path-bearing loopback URL is a gateway, not the documented local collector, so it
# skips too. Same port as (tel2), where the bare host:port form resolved nocoll — so this pins the
# PARSER, not the reachability of the port.
if [ -n "$DEAD_PORT" ]; then
  rm -f "$PPROG"
  out="$(pgate_tel CLAUDE_CODE_ENABLE_TELEMETRY=1 "OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:$DEAD_PORT/v1/metrics" -- entry 8)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -qF '| telemetry=on |' "$PPROG"; then
    pass "(tel4) a path-bearing loopback URL skips the probe — the same port that resolved nocoll bare"
  else fail "(tel4) expected telemetry=on for the path-bearing URL, rc=$rc: $(cat "$PPROG" 2>/dev/null)"; fi
else
  fail "(tel4) could not find a closed loopback port — the case could not run"
fi

# (tel5) the CONNECTED direction. Without it, an implementation whose probe always failed would
# warn `nocoll` on every healthy machine — the false alarm OR-1 says costs the most — and every
# case above would still pass. Needs a real loopback listener, so it is guarded on `nc`; when
# `nc` is absent the case is reported NOT RUN rather than silently dropped.
TEL_LISTEN_PORT=""
for _p in 45322 45323 45324 45325; do
  (exec 3<>"/dev/tcp/127.0.0.1/$_p") 2>/dev/null || { TEL_LISTEN_PORT="$_p"; break; }
done
if command -v nc >/dev/null 2>&1 && [ -n "$TEL_LISTEN_PORT" ]; then
  nc -l 127.0.0.1 "$TEL_LISTEN_PORT" >/dev/null 2>&1 &
  NC_PID=$!
  _up=0
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$TEL_LISTEN_PORT") 2>/dev/null; then _up=1; break; fi
    sleep 0.2
  done
  if [ "$_up" -eq 1 ]; then
    # The connect above consumed the single accept, so re-listen for the gate's own probe.
    kill "$NC_PID" 2>/dev/null; wait "$NC_PID" 2>/dev/null
    nc -k -l 127.0.0.1 "$TEL_LISTEN_PORT" >/dev/null 2>&1 &
    NC_PID=$!
    sleep 0.5
    rm -f "$PPROG"
    out="$(pgate_tel CLAUDE_CODE_ENABLE_TELEMETRY=1 "OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:$TEL_LISTEN_PORT" -- entry 8)"; rc=$?
    if [ "$rc" -eq 0 ] && grep -qF '| telemetry=on |' "$PPROG"; then
      pass "(tel5) a loopback endpoint that ACCEPTS resolves to on — the probe is not a constant failure"
    else fail "(tel5) expected telemetry=on against a live listener, rc=$rc: $(cat "$PPROG" 2>/dev/null)"; fi
  else
    echo "  NOTE: (tel5) not run — could not bring up a loopback listener on $TEL_LISTEN_PORT"
  fi
  kill "$NC_PID" 2>/dev/null; wait "$NC_PID" 2>/dev/null
else
  echo "  NOTE: (tel5) not run — no \`nc\` on PATH, so no loopback listener is available"
fi

# (tel6) BACKWARD COMPATIBILITY. The row grew a field, and a run already in flight when the new
# gate lands has the OLD one. `entry_row_present` / `require_entry_attested` read PRESENCE, so a
# legacy row must still satisfy them — otherwise every mid-flight run reds at its next milestone
# on a format change it had no way to anticipate.
rm -f "$PPROG"
{ echo "# lean run — issue 8"; echo ""; echo "run_id: r-p"; echo "session_id: $PSID"
  echo "2026-01-01T00:00:00Z | entry | ledger=$PTREE/.claude/audit/$PSID.jsonl | lines=2 | session=$PSID"
} > "$PPROG"
out="$(pgate 1 8)"; rc=$?
if [ "$rc" -ne 2 ]; then
  pass "(tel6) a legacy entry row without the telemetry field still attests — no mid-flight run reds on the format change"
else fail "(tel6) legacy row rejected by the entry precondition: $out"; fi

# The refusal, on a progress file that has everything EXCEPT the row. Seeding a full header is
# the point: "the file is missing" and "the run never attested" must not be the same test, or a
# gate that merely required a progress file would pass this.
pseed_unattested() {
  rm -f "$PPROG"
  { echo "# lean run — issue 8"; echo ""; echo "run_id: r-p"; echo "session_id: $PSID"; } > "$PPROG"
}
pseed_unattested
out="$(pgate 1 8)"; rc=$?
# The `absent` half is #494's: the refusal fires before cmd_1 runs, so it must charge NEITHER
# counter — a new line kind that leaked through the entry refusal would still be a record of a
# milestone that was never evaluated.
if [ "$rc" -eq 2 ] && grep -qF 'bash G entry 8' <<<"$out" \
   && [ "$(pcount '| milestone-1 | attempt |')" -eq 0 ] \
   && [ "$(pcount '| milestone-1 | absent |')" -eq 0 ]; then
  pass "(ea3) a build-role milestone with no entry row exits 2, names the remedy, and charges neither counter"
else fail "(ea3) expected rc=2 + remedy + zero attempts/absences, rc=$rc, attempts=$(pcount '| milestone-1 | attempt |'), absent=$(pcount '| milestone-1 | absent |'): $out"; fi

# D-13's backstop, and the issue's own exit-evidence wording: a run REACHING MILESTONE 4 with no
# entry trace reds. It reds at the precondition rather than inside cmd_4 — which is the point of
# D-4, since the constraint the issue states as governing is that the failure be reachable BEFORE
# a verdict record exists — but the observable the issue asks for is the same one.
# `reviewed_patch_id` is stamped for the reason every fixture record now stamps one (#642): the key
# is required at milestone 4, and this case is about the ENTRY precondition, not about the record.
# Derived through the production function in library mode — never a copy of its formula.
#
# The CONTENT COMMIT below is what makes that computable. `origin/main` in this fixture sits at the
# tree's only commit, so a branch carrying nothing but the verdict record — which the measurement
# excludes — has an EMPTY diff, and `git patch-id` prints nothing for one. The record would then be
# written key-less and the case would red on the key rather than on the precondition it names.
printf 'p fixture content, so the branch diff is non-empty\n' > "$PTREE/content.txt"
git -C "$PTREE" add -A >/dev/null 2>&1
git -C "$PTREE" commit -q -m "p fixture content" >/dev/null 2>&1
# shellcheck disable=SC1090  # $GATE is the script under test; following it is the point.
p_pid="$( cd "$PTREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 \
          && REPO_ROOT="$PTREE" BASE_BRANCH=main VERDICT_REL="docs/plans/acme-8-lean-verdict.md" \
             branch_patch_id HEAD )"
printf 'verdict=approve\nrun_id: r-p-review\nsession_id: sess-p-review\nrounds: 1\nreviewed_head: %s\nreviewed_patch_id: %s\n' \
  "$(git -C "$PTREE" rev-parse HEAD)" "$p_pid" > "$PTREE/docs/plans/acme-8-lean-verdict.md"
git -C "$PTREE" add -A >/dev/null 2>&1
git -C "$PTREE" commit -q -m "p review verdict" >/dev/null 2>&1
pseed_unattested
out="$(pgate 4 8)"; rc4_unattested=$?
pgate entry 8 >/dev/null 2>&1
out2="$(pgate 4 8)"; rc4_attested=$?
if [ "$rc4_unattested" -eq 2 ] && [ "$rc4_attested" -eq 0 ]; then
  pass "(ea4) milestone 4 reds on an unattested run and passes once the row exists — the paired backstop"
else fail "(ea4) expected 2 then 0, got $rc4_unattested then $rc4_attested: $out / $out2"; fi

# `all` is the whole-progression entry point, so a precondition it did not share would leave the
# one call a resume actually makes unguarded.
pseed_unattested
out="$(pgate all 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'no entry attestation' <<<"$out"; then
  pass "(ea5) 'all' refuses an unattested run before its cheap pre-pass runs"
else fail "(ea5) expected rc=2 from all, got $rc: $out"; fi

# #590's `close-out` shares the precondition for a sharper reason than its siblings: it WRITES.
# A close-out on a run with no attestation would post a public closing comment about a run nothing
# can reconcile, which is worse than a milestone certified against one.
pseed_unattested
out="$(pgate close-out 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'no entry attestation' <<<"$out"; then
  pass "(ea5a) 'close-out' refuses an unattested run before it writes anything"
else fail "(ea5a) expected rc=2 from close-out, got $rc: $out"; fi

# `delta` is invoked by the REVIEW session — D-4 gates it anyway and accepts the consequence: a
# reviewer of an unattested build is told to stop, with a remedy only the build side can apply.
pseed_unattested
out="$(pgate delta 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'bash G entry 8' <<<"$out"; then
  pass "(ea6) delta refuses an unattested run — a reviewer must not certify a run with no ledger"
else fail "(ea6) expected rc=2 from delta, got $rc: $out"; fi

# ...but `verdict` is NOT gated (D-5). Its own ledger precondition is a follow-up gated on #417,
# and gating it here would refuse every honest review whose session works in the build worktree.
# Asserted POSITIVELY, not by the absence of a string: `exit 2` is envfail's code generally, so
# rc alone cannot separate "gated" from "reached cmd_verdict and stopped there", and absence
# alone passes for any other refusal whose wording differs. What discriminates is the message
# PREFIX — the precondition writes `✗ <sub>:` and cmd_verdict's own diagnostics write a bare
# `verdict:` — so requiring one and forbidding the other pins that control got past the gate.
pseed_unattested
out="$( cd "$PTREE" && CLAUDE_CODE_SESSION_ID=sess-p-review SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$PPROG" RUN_ID=r-p-review-2 bash "$GATE" verdict 8 --pr 3 --verdict approve 2>&1 )"; rc=$?
if grep -qF '[lean-gate] verdict:' <<<"$out" \
   && ! grep -qF 'no entry attestation' <<<"$out"; then
  pass "(ea7) verdict is exempt from the build-role precondition (D-5) — it reaches its own evaluation"
else fail "(ea7) verdict was gated by the entry precondition, rc=$rc: $out"; fi

# AC-2 / D-9: enrichment only. The VERDICT is the ledger predicate's in both halves (rc=1
# either way); what changes is whether the operator is told the one thing that turns a
# five-minute hunt into a one-line fix.
PNOLEDGER="$WORK/pnoledger"
mkdir -p "$PNOLEDGER/docs/plans" "$PNOLEDGER/.claude"
git -C "$PNOLEDGER" init -q
git -C "$PNOLEDGER" config user.email t@example.invalid
git -C "$PNOLEDGER" config user.name t
git -C "$PNOLEDGER" commit -q --allow-empty -m base >/dev/null 2>&1
pn_entry() { ( unset RUN_ID; cd "$PNOLEDGER" && CLAUDE_CODE_SESSION_ID=sess-absent \
               SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$WORK/pnprogress.md" \
               bash "$GATE" entry 8 2>&1 ); }
rm -f "$PNOLEDGER/.claude/settings.json" "$PNOLEDGER/.claude/settings.local.json"
out="$(pn_entry)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'is missing or empty' <<<"$out" \
   && ! grep -q 'audit-toolkit is disabled' <<<"$out"; then
  pass "(ea8) with no settings to read, the missing-ledger refusal keeps its generic wording"
else fail "(ea8) expected the generic refusal, rc=$rc: $out"; fi

printf '{"enabledPlugins": {"audit-toolkit@second-shift": false}}\n' > "$PNOLEDGER/.claude/settings.local.json"
out="$(pn_entry)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'audit-toolkit is disabled' <<<"$out"; then
  pass "(ea9) the same refusal names audit-toolkit when the settings say it is off — same verdict, better diagnosis"
else fail "(ea9) expected the plugin-off wording, rc=$rc: $out"; fi

# The enrichment must never become an authority: a settings file saying `false` cannot refuse a
# run whose ledger IS live. This is the direction a "check the plugin instead" implementation
# gets wrong, and it would red every honest run in a repo with a stale local settings file.
printf '{"enabledPlugins": {"audit-toolkit@second-shift": false}}\n' > "$PTREE/.claude/settings.local.json"
rm -f "$PPROG"
out="$(pgate entry 8)"; rc=$?
rm -f "$PTREE/.claude/settings.local.json"
if [ "$rc" -eq 0 ] && [ "$(pcount '| entry | ledger=')" -eq 1 ]; then
  pass "(ea10) a live ledger passes even with audit-toolkit marked disabled — the predicate decides, not the settings"
else fail "(ea10) the settings read became a second authority, rc=$rc: $out"; fi

# ---- the header the attestation created (#416) ----------------------------------------------
# `entry` creates the progress file, and SKILL.md orders it BEFORE the RUN_ID export — so on
# every honest run the header is born `run_id: unset`. #322 closed that freeze by keeping
# `entry` from creating the file at all, a remedy this precondition cannot keep. The heal is
# what replaces it, and it is load-bearing: lean-reconcile.sh arm (1) compares the claim
# comment's run_id against this header, so an unhealed `unset` reds a clean run at the merge
# boundary. Neither direction is a fixture nicety.
PSTATE="$PTREE/.claude/pipeline-state"
rm -f "$PPROG" "$PSTATE/8-run-id"
pgate entry 8 >/dev/null 2>&1
if grep -q '^run_id: unset$' "$PPROG" 2>/dev/null; then frozen_at_entry=1; else frozen_at_entry=0; fi
# A milestone call does NOT establish an identity (it resolves without persisting), so an
# ad-hoc RUN_ID on one must not reach the header: the header has to carry the id `claim` wrote
# and reconcile compares against, not whatever shell ran a gate in between.
( cd "$PTREE" && CLAUDE_CODE_SESSION_ID="$PSID" SECOND_SHIFT_CONFIG="$CFG" \
  LEAN_PROGRESS_FILE="$PPROG" RUN_ID=p-drive-by bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 8 >/dev/null 2>&1 )
if [ "$frozen_at_entry" -eq 1 ] && grep -q '^run_id: unset$' "$PPROG" 2>/dev/null; then
  pass "(ea11) an ad-hoc RUN_ID on a milestone call cannot stamp the header — only an established identity may"
else fail "(ea11) frozen_at_entry=$frozen_at_entry, header now: $(grep '^run_id:' "$PPROG" 2>/dev/null)"; fi

# ...and the establishing call heals it. `entry` is idempotent, so re-running it with the id
# exported is exactly the recovery an operator who read step 2 second would make.
out="$( cd "$PTREE" && CLAUDE_CODE_SESSION_ID="$PSID" SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$PPROG" RUN_ID=p-build-1 bash "$GATE" entry 8 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^run_id: p-build-1$' "$PPROG" 2>/dev/null \
   && [ "$(pcount '| entry | ledger=')" -eq 1 ]; then
  pass "(ea12) the first call to establish a run identity heals the frozen header, without duplicating the row"
else fail "(ea12) header did not heal, rc=$rc: $(grep '^run_id:' "$PPROG" 2>/dev/null) / rows=$(pcount '| entry | ledger=')"; fi

# ---- (eb) #444: the entry precondition declares when IT took effect --------------------------
# The precondition above is itself an arm that landed while branches were in flight, and
# enforcing it against them refuses a run for not satisfying a contract that did not exist when
# it started. So it carries a `since:` and de-blocks anything older.
#
# ONE FIXTURE, RE-DATED PER CASE. The tree is rebuilt for each case because the observable IS
# the first commit's author date past merge-base, so it cannot be varied any other way.
EBTREE="$WORK/ebtree"
EBPROG="$WORK/ebprogress.md"
eb_build() { # eb_build <author-date> — a branch whose one commit past origin/main is so dated
  rm -rf "$EBTREE" "$EBPROG"
  mkdir -p "$EBTREE/docs/plans"
  git -C "$EBTREE" init -q
  git -C "$EBTREE" config user.email t@example.invalid
  git -C "$EBTREE" config user.name t
  printf '.claude/\n' > "$EBTREE/.gitignore"
  git -C "$EBTREE" add -A >/dev/null 2>&1
  git -C "$EBTREE" commit -q -m "eb base" >/dev/null 2>&1
  git -C "$EBTREE" update-ref refs/remotes/origin/main HEAD
  printf '# spec\n\n- AC-1: a thing\n' > "$EBTREE/docs/plans/acme-8-lean.md"
  git -C "$EBTREE" add -A >/dev/null 2>&1
  # COMMITTER stamped NOW, author stamped by the case. That split is the point: the comparator
  # must read the author date, because a rebase rewrites the committer one and would make an old
  # branch postdate its own cutoff the morning it was rebased — the exact stranding this removes.
  GIT_AUTHOR_DATE="$1" git -C "$EBTREE" commit -q -m "eb work" >/dev/null 2>&1
}
ebgate() { # ebgate <args...> — an UNATTESTED run: no entry row is ever written in this block
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID
    cd "$EBTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$EBPROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
# Capture-then-default, for the reason pcount above spells out: on zero matches `grep -c` PRINTS
# "0" *and* exits 1, so a `|| echo 0` fallback emits a second "0" and the `-eq` against it throws.
# Every case here compares against zero, so this block is exactly where that bites.
ebrows() {
  local n
  [ -f "$EBPROG" ] || { echo 0; return 0; }
  n="$(grep -cF '| entry | ledger=' "$EBPROG" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

# AC-6, one second before. rc=0 rather than merely "not 2": milestone 1 actually RUNS and
# passes, which is what proves the precondition let control through rather than swapping one
# refusal for another.
eb_build '2026-08-07T13:22:50Z'
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qF 'before the entry precondition took effect (2026-08-07T13:22:51Z)' <<<"$out" \
   && ! grep -qF 'no entry attestation' <<<"$out" \
   && [ "$(ebrows)" -eq 0 ]; then
  pass "(eb1) AC-6: a branch started before the precondition's since: is de-blocked, announced, and NOT attested"
else fail "(eb1) expected a de-blocked run with no entry row, rc=$rc rows=$(ebrows): $out"; fi

# AC-7/AC-5, the same second. At-or-after enforces, and the refusal is the unchanged one —
# including its SECOND cause, the host-local/gitignored paragraph, which a rewrite of this
# function is likeliest to drop.
eb_build '2026-08-07T13:22:51Z'
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'no entry attestation' <<<"$out" \
   && grep -qF 'host-local and gitignored' <<<"$out"; then
  pass "(eb2) AC-7: a branch started AT the since: is refused, with the existing wording and second cause"
else fail "(eb2) expected the unchanged refusal at the boundary second, rc=$rc: $out"; fi

# AC-8, the behavioral half, and the direction that FAILS OPEN if the offset is ignored: local
# 09:00 sorts before the cutoff's 13:22:51 as a string, but it is 14:00 UTC — at or after — so a
# comparator that compared the raw author date would silently exempt a branch it must enforce.
eb_build '2026-08-07T09:00:00-05:00'
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'no entry attestation' <<<"$out"; then
  pass "(eb3) AC-8: a -05:00 author date at 14:00 UTC enforces, though its local clock reads before the cutoff"
else fail "(eb3) a non-UTC offset was compared unnormalized (fail-open direction), rc=$rc: $out"; fi

# ...and the mirror, which fails CLOSED if the offset is ignored: local 18:00 sorts after the
# cutoff, but it is 12:30 UTC — before — so the branch must be de-blocked. Both directions are
# driven because one alone is satisfied by a comparator that is merely wrong in the other.
eb_build '2026-08-07T18:00:00+05:30'
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'this branch started at 2026-08-07T12:30:00Z' <<<"$out"; then
  pass "(eb4) AC-8: a +05:30 author date at 12:30 UTC de-blocks, though its local clock reads after the cutoff"
else fail "(eb4) a non-UTC offset was compared unnormalized (fail-closed direction), rc=$rc: $out"; fi

# OR-2. An EMPTY range is not the unresolvable case: the branch was cut just now with nothing
# committed, which is definitively at or after any cutoff, so it ENFORCES. Every (ea*) case above
# rides on this — their fixture's origin/main IS its head — so pinning it explicitly is what
# keeps a future "empty means unknown, be lenient" rewrite from silently waiving all of them.
eb_build '2026-08-07T13:22:50Z'
git -C "$EBTREE" update-ref refs/remotes/origin/main HEAD
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'no entry attestation' <<<"$out"; then
  pass "(eb5) OR-2: an empty commit range enforces — a branch cut now postdates nothing"
else fail "(eb5) an empty range took the de-block path, rc=$rc: $out"; fi

# D-5. An unresolvable merge-base is its OWN environment error, not a fifth cause on the refusal:
# "you skipped entry" and "your checkout is broken" have different remedies, and this gate runs
# where origin/$BASE_BRANCH is present by construction. Asserted in BOTH directions — the new
# message present AND the attestation refusal absent — since rc=2 alone cannot tell them apart.
eb_build '2026-08-07T13:22:50Z'
git -C "$EBTREE" update-ref -d refs/remotes/origin/main
out="$(ebgate 1 8)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'cannot resolve merge-base(origin/main, HEAD)' <<<"$out" \
   && ! grep -qF 'no entry attestation' <<<"$out"; then
  pass "(eb6) D-5: an unresolvable merge-base fails closed with its own diagnosis, not the attestation refusal"
else fail "(eb6) expected the merge-base envfail, rc=$rc: $out"; fi

# AC-8, the structural half (D-7). git does the offset arithmetic — `--date=format-local` under
# TZ=UTC — precisely so no `date` invocation is on this path: `date -d` (GNU) and `date -r` (BSD)
# fail DIRTY under the other userland, so a comparator reaching for either is green on the lane
# that has it and wrong on the lane that does not, and this suite runs on both. Deliberately not
# gated on detecting a 3.2 interpreter: such a case would never fire on the ubuntu lane and would
# read as coverage while proving nothing.
if ! grep -nE '(^|[^[:alnum:]_-])date[[:space:]]+-[dr]([[:space:]]|$)' "$GATE" >/dev/null; then
  pass "(eb7) AC-8: the cutoff comparison invokes neither 'date -d' nor 'date -r'"
else fail "(eb7) a GNU/BSD-split date form reached lean-gate.sh: $(grep -nE '(^|[^[:alnum:]_-])date[[:space:]]+-[dr]([[:space:]]|$)' "$GATE")"; fi

# ---- (pm) AC-4: the PR build-identity marker (#359) -----------------------------------------
# The WRITER half of the boundary's identity arm. lean-evidence.sh compares the verdict record
# against every marker this posts; without a writer that arm refuses every honest PR, and with
# a writer that posts unconditionally the trail fills with duplicates on every resumed run.
#
# Issue 8, not 7, so the build run-id cache these calls seed (`mark` is a build-role
# subcommand) cannot reach the (m) block's cache assertions on issue 7.
BOT_SPOOL="$WORK/bot-spool.txt"
cat > "$WORK/bot-stub.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for the gh bot wrapper: spool whatever body was posted, then emit a comment URL.
for a in "$@"; do
  case "$a" in body=@*) cat "${a#body=@}" >> "$BOT_SPOOL" ;; esac
done
echo "https://example.invalid/pr/9#issuecomment-1"
EOF
chmod +x "$WORK/bot-stub.sh"

MPROG="$WORK/progress-mark.md"
mark_gate() { # mark_gate <config> <run-id> <session-id> <args...>
  local cfg="$1" rid="$2" sid="$3"; shift 3
  ( cd "$TREE" && RUN_ID="$rid" CLAUDE_CODE_SESSION_ID="$sid" SECOND_SHIFT_CONFIG="$cfg" \
      LEAN_PROGRESS_FILE="$MPROG" GH_BOT="$WORK/bot-stub.sh" BOT_SPOOL="$BOT_SPOOL" \
      bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}

# #446: `mark` refuses any session outside the RECORDED build-session set, so these cases need
# the sessions they run as to be in it. Driven through the REAL `entry` rather than echoed rows —
# a hand-written line keeps passing after the writer changes shape, which is the failure mode
# this suite's own D-41 cases document. Three sessions, one run: the first creates the file (its
# id lands in the header), the next two arrive after the per-RUN attestation row already exists,
# which is exactly the D-7 case the per-SESSION presence test is for.
mark_attest() { # mark_attest <session-id>
  mkdir -p "$TREE/.claude/audit"
  printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/$1.jsonl"
  ( unset RUN_ID; cd "$TREE" && CLAUDE_CODE_SESSION_ID="$1" SECOND_SHIFT_CONFIG="$CFG" \
      LEAN_PROGRESS_FILE="$MPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" entry 8 >/dev/null 2>&1 )
}
mcount() { # mcount <fixed-string>
  local n
  [ -f "$MPROG" ] || { echo 0; return 0; }
  n="$(grep -cF "$1" "$MPROG" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}
rm -f "$MPROG"
mark_attest sess-mark-1
mark_attest sess-mark-2
mark_attest sess-mark-3
# #457's (pm6b) drives mark under jira+bot as its own session; it needs to be in the set too.
mark_attest sess-mark-jb

cat > "$WORK/pr-mark.json" <<'EOF'
[{ "number": 9, "url": "https://example.invalid/pr/9" }]
EOF
echo '[]' > "$WORK/pr-mark-none.json"

: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-1 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-1' "$BOT_SPOOL" 2>/dev/null \
   && grep -q 'session_id: sess-mark-1' "$BOT_SPOOL" 2>/dev/null \
   && grep -q 'stage: lean-pr-marker' "$BOT_SPOOL" 2>/dev/null; then
  pass "(pm1) mark posts a bot marker carrying BOTH identities and the lean-pr-marker stage token"
else fail "(pm1) expected a posted marker with both ids, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# IDEMPOTENT. A resumed run re-reaches milestone 5, and cmd_5 calls this last on every pass —
# a writer that posted unconditionally would leave one marker per invocation.
cat > "$WORK/comments-mark-same.json" <<'EOF'
[{ "user": { "type": "Bot" }, "body": "<!-- run_id: mark-run-1 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-1 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-mark-same.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'already carries this run' <<<"$out"; then
  pass "(pm2) mark is a no-op when this run's marker is already on the PR"
else fail "(pm2) expected a silent no-op, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ...but idempotent BY IDENTITY, never by presence. This is the D-4 case: a SECOND build
# session on the same PR must leave its own marker, or the boundary compares the verdict
# against only the first session's id and that second session can review its own work.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-2 sess-mark-2 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-mark-same.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-2' "$BOT_SPOOL" 2>/dev/null; then
  pass "(pm3) a DIFFERENT build session still posts its own marker (D-4)"
else fail "(pm3) expected a second marker for a second session, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# The no-op test is right-delimited, so a longer id sharing this one's prefix is a different
# run. Undelimited, `mark-run-1` would match `mark-run-10`'s marker and the longer-named
# session would go unmarked — invisible at the boundary, which is the hole (pm3) closes.
cat > "$WORK/comments-mark-prefix.json" <<'EOF'
[{ "user": { "type": "Bot" }, "body": "<!-- run_id: mark-run-10 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-1 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-mark-prefix.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-1' "$BOT_SPOOL" 2>/dev/null; then
  pass "(pm4) a marker whose run id merely PREFIX-matches does not suppress the write"
else fail "(pm4) expected a post despite the prefix-matching marker, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# An operator-authored marker is not evidence the harness ran — the reader filters on
# `.user.type == "Bot"`, so a writer that let one suppress the post would strand the PR with a
# marker the boundary cannot see.
cat > "$WORK/comments-mark-human.json" <<'EOF'
[{ "user": { "type": "User" }, "body": "<!-- run_id: mark-run-1 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-1 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-mark-human.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-1' "$BOT_SPOOL" 2>/dev/null; then
  pass "(pm5) an operator-authored marker does not suppress the bot's own"
else fail "(pm5) expected a post despite the human marker, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# A consumer with no bot has no authenticated writer at all, so there is nothing to post. The
# degrade is PRINTED — a silent skip would read as "the marker was posted" in the run log.
# $CFG_JIRA declares no bot block, which is what every jira config looked like while config-lint
# forbade one; that absence, not the tracker, is what this asserts (#440).
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG_JIRA" mark-run-j sess-mark-j mark ACME-8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'reduced strength' <<<"$out"; then
  pass "(pm6) with no bot configured, mark writes nothing and says so (reduced strength, printed)"
else fail "(pm6) expected a printed no-bot degrade with no write, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ...and the SAME jira consumer with a bot enabled posts the marker exactly as a github one does
# (#440). The PR is a code-host surface every adapter has, so `tracker.type` was never the right
# key for this write; re-keying the branch back onto the tracker fails here.
CFG_JIRA_BOT="$WORK/config-jira-bot.json"
jq '.tracker.bot = { "enabled": true, "app": { "appName": "acme-pipeline-bot" } }' \
  "$CFG_JIRA" > "$CFG_JIRA_BOT"
jq -e '.tracker.bot.enabled == true and .tracker.type == "jira"' "$CFG_JIRA_BOT" >/dev/null \
  || fail "(pm6b) fixture builder produced no bot block — the case below would assert nothing"
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG_JIRA_BOT" mark-run-jb sess-mark-jb mark ACME-8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-jb' "$BOT_SPOOL" 2>/dev/null \
   && ! grep -q 'reduced strength' <<<"$out"; then
  pass "(pm6b) a jira consumer WITH a bot posts the PR marker, like any other"
else fail "(pm6b) expected a posted marker under jira+bot, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# No PR ⇒ no surface to stamp. Refuse rather than no-op: a run that never opened its PR has
# not reached the step this is called from, and a silent success would hide that.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-3 sess-mark-3 mark 8 --pr-file "$WORK/pr-mark-none.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'no open or merged PR found' <<<"$out"; then
  pass "(pm7) mark refuses when the branch has no PR at all"
else fail "(pm7) expected rc=1 with no write, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ---- (pm7b)-(pm7c) #670 AC-1: mark resolves a MERGED PR, and posts nothing to it -------------
# THE LIVE PATH, DELIBERATELY: no --pr-file anywhere below. That seam is what hid this defect —
# both mark and resolve_open_pr honor it, so a fixture passing it never reaches the `gh pr list`
# call where mark's own `--state open` lived, and #642's (k7) certified post-merge reachability
# while crossing none of the code that denied it. A case here that passes --pr-file does not
# satisfy AC-1.
# The ticket-liveness arm mark runs before it writes needs an `issue view` answer too.
cat > "$WORK/gh-merged.sh" <<'STUB'
#!/bin/sh
# `--state open` answers an EMPTY array, which is what real gh returns once the PR is merged —
# so a revert of #670's resolver change fails here instead of quietly passing.
case "$*" in
  *"issue view"*) echo OPEN ;;
  *"pr list"*)
    case "$*" in
      *"--state open"*) echo '[]' ;;
      *) cat <<'JSON'
[{"number":91,"url":"https://example.invalid/pr/91","isDraft":false,"state":"MERGED","body":"Closes #8"}]
JSON
      ;;
    esac ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$WORK/gh-merged.sh"

# RUN AS AN ALREADY-ATTESTED SESSION, and that is load-bearing for (pm7c) rather than tidiness.
# `mark`'s build-session guard sits TWO refusals in front of the merged branch, so a session id
# outside the recorded set makes the no-write assertion below unfalsifiable — it passed even with
# the merged early-return deleted, refusing on the identity instead. Reusing `sess-mark-1` rather
# than attesting a fifth id keeps (ms11)'s `| session |` row count at 3, which is its own guard.
: > "$BOT_SPOOL"
out="$( GH="$WORK/gh-merged.sh" mark_gate "$CFG" mark-run-670 sess-mark-1 mark 8 --comments-file "$WORK/comments-none.json" )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'already MERGED' <<<"$out"; then
  pass "(pm7b) #670 AC-1: mark RESOLVES a merged PR over the live gh path instead of refusing it"
else fail "(pm7b) expected rc=0 naming the merged PR, rc=$rc: $out"; fi

# The other half of D-3, and the half a bare widening would get wrong: resolving it must not
# also POST to it. The marker's only reader is the pull_request-event merge boundary, which has
# already run by the time the PR is merged.
if [ ! -s "$BOT_SPOOL" ]; then
  pass "(pm7c) #670 D-3: nothing is posted to a merged PR — the marker's only reader has already run"
else fail "(pm7c) expected NO write to a merged PR, spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ---- (tl) #650 AC-2: the mid-run ticket-liveness re-check ------------------------------------
# The scheduler asks "is this ticket still open" before every BUILD spawn and cannot ask again
# while one is running — there is no channel into a live `claude -p`, which its own header states
# as "bounds the damage at one session, not at zero". This is the other side of that boundary: the
# session asks for itself, at the step-7 handoff, before a review round is spent on work whose
# ticket closed underneath it.
#
# `mark` and not a milestone, because `require_ticket_live`'s header fixes "one read per run
# boundary, never per milestone" and `1`..`5` are recorded network-free. `mark` already opens a
# socket and already writes.

# THE REFUSAL. Nothing is spooled — the point of catching it here rather than after is that no
# half-made handoff exists to clean up.
: > "$BOT_SPOOL"
out="$(STUB_GH_STATE=CLOSED mark_gate "$CFG" mark-run-tl1 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 7 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'THE TICKET CLOSED UNDER THIS RUN' <<<"$out"; then
  pass "(tl1) mark refuses with the staleness code when the ticket closed under the run, and writes nothing"
else fail "(tl1) expected rc=7 + no write + the named refusal, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ANTI-VACUITY for (tl1), and it is the case that makes the pair a measurement: the SAME
# invocation with the SAME fixtures under an OPEN ticket must post. Without it a `mark` broken for
# any other reason would satisfy (tl1)'s "rc!=0, nothing spooled" shape.
: > "$BOT_SPOOL"
out="$(STUB_GH_STATE=OPEN mark_gate "$CFG" mark-run-tl2 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'run_id: mark-run-tl2' "$BOT_SPOOL" 2>/dev/null; then
  pass "(tl2) the same call under an OPEN ticket posts as before — the refusal is the STATE's doing, not a broken path"
else fail "(tl2) expected the ordinary post under OPEN, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# FAIL CLOSED, on the arm's own precedent: an unreadable tracker is not an open ticket. Its own
# code, because the remedy differs — 7 says re-open or abandon, 2 says fix the environment.
: > "$BOT_SPOOL"
out="$(STUB_GH_FAIL='gh: upstream is on fire' mark_gate "$CFG" mark-run-tl3 sess-mark-1 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'liveness could not be read' <<<"$out"; then
  pass "(tl3) an unreadable tracker refuses with the environment code and posts nothing — fail closed"
else fail "(tl3) expected rc=2 + no write on an unreadable tracker, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# THE LANDING PATH IS EXEMPT (`D-9`), and this is the case that keeps it exempt. `cmd_5` and
# `cmd_close_out` call `cmd_mark` as a FUNCTION, so they never reach the dispatch guard — #515's
# `D-4` reasoning honored rather than re-decided: a ticket that closes mid-review must still be
# able to land its approved, reviewed work, and a refusal there would strand it.
#
# SCORED ON THE REFUSAL'S ABSENCE, not on a green close-out: this fixture is not staged for a
# complete milestone 5, and asserting one would make the case about something else. The property
# is precisely "the mid-run guard did not fire here", and it is falsifiable — widen the dispatch
# arm to `mark|5|close-out` and this reds while (tl1) still passes.
out="$(STUB_GH_STATE=CLOSED mark_gate "$CFG" mark-run-tl4 sess-mark-1 5 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -ne 7 ] && ! grep -q 'THE TICKET CLOSED UNDER THIS RUN' <<<"$out"; then
  pass "(tl4) milestone 5's own re-call of mark is NOT gated by the mid-run check — the landing path stays open"
else fail "(tl4) the mid-run refusal fired on the landing path, rc=$rc: $out"; fi

# ---- (ms) #446: mark's session_id must come from a RECORDED build session --------------------
# The marker's session_id is the STRONGEST identity the merge boundary compares (run_id is
# agent-chosen; the session id is harness-assigned) and it was read from the ambient environment.
# The documented recovery for a stranded marker is run from the REVIEW session — the only place
# the omission becomes visible — so following it stamped the review session as the build session
# and lean-evidence.sh reported an honest, independent review as a P10 self-review. Neither a
# re-run (idempotent on run_id alone) nor a corrective second marker (the boundary compares
# EVERY marker) clears that, so the only fix is refusing to write it in the first place.

# AC-5/AC-6. The refusal itself, and all three things D-8 requires it to say: the conflicting
# ambient id, every id the harness recorded, and the exact re-invocation.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-r sess-review-r mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] \
   && grep -qF "sess-review-r" <<<"$out" \
   && grep -qF "sess-mark-1" <<<"$out" \
   && grep -qF "CLAUDE_CODE_SESSION_ID=<id> bash G mark 8" <<<"$out"; then
  pass "(ms1) mark refuses a session outside the recorded build set, naming the conflict, the recorded id(s) and the re-invocation"
else fail "(ms1) expected rc=1 + the three D-8 fields + no write, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# AC-5's ORDERING, RE-CUT for #590 and pinned by consequence rather than by reading the source.
# #446 put the identity refusal ahead of the PR lookup so a review session doing the documented
# recovery paid no network call — a COST argument, and the case pinned it with a --pr-file naming
# a file that does not exist (an envfail, rc=2, the moment the lookup runs). #590 moved the
# refusal BEHIND the already-marked no-op, because the close-out is a gate command with no session
# identity at all and must pass when checklist step 7 already stamped the PR. So the lookup is
# reached now, and rc=2 is the honest consequence.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-r sess-review-r mark 8 --pr-file "$WORK/absent-pr.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$BOT_SPOOL" ]; then
  pass "(ms2) the PR lookup is reached before the refusal now — and an unreadable --pr-file still writes nothing"
else fail "(ms2) expected rc=2 and no write once the lookup precedes the refusal, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ...and WHAT THE REORDER MUST NOT COST, which is the whole of #446: a foreign session on a PR
# that does NOT already carry this run's marker is still refused, and still writes nothing. The
# refusal guards a WRITE, so moving it behind a path that writes nothing changes what it protects
# by exactly zero — (ms1) above is that assertion, and this is its no-write half stated again
# against a REAL pr fixture so the two cannot both be satisfied by an envfail.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-r sess-review-r mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'not a recorded BUILD session' <<<"$out"; then
  pass "(ms2a) a foreign session on a PR carrying no marker for this run is still refused, and still writes nothing"
else fail "(ms2a) the reorder cost the refusal, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# ...and #590 AC-6's OWN half, which nothing above states: a session OUTSIDE the build set passes
# when the PR already carries this run's marker. That is the path the scheduler's close-out takes
# — it runs with CLAUDE_CODE_SESSION_ID scrubbed — and under the pre-#590 order it was a refusal,
# so no lane could ever have closed out through the gate. Nothing is posted: the no-op is the pass.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-1 sess-review-r mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-mark-same.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'already carries this run' <<<"$out"; then
  pass "(ms2b) a session outside the build set PASSES when the PR already carries this run's marker — the no-op the close-out relies on, and it posts nothing"
else fail "(ms2b) expected a silent rc=0 no-op for an unrecorded session on an already-marked PR, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# AC-2/D-7. sess-mark-2 and sess-mark-3 registered through `entry` calls that appended NO second
# attestation row — that row is per-RUN and short-circuits. A recorder sharing the row's presence
# test would have recorded nothing for them, and (pm3)/(pm7) would then be refusals rather than
# the behaviors they assert. Both halves together: one row, three usable identities.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-d7 sess-mark-3 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(mcount '| entry | ledger=')" -eq 1 ] && grep -q 'session_id: sess-mark-3' "$BOT_SPOOL" 2>/dev/null; then
  pass "(ms3) a session recorded AFTER the per-run entry row already existed still marks (D-7)"
else fail "(ms3) expected rc=0 with one entry row, rc=$rc, rows=$(mcount '| entry | ledger='): $out"; fi

# AC-8. The marker keeps carrying the AMBIENT id, not the header's — a second build session must
# stamp its OWN identity or it is invisible at the boundary and could review its own work. This
# is the half a "resolve session_id from the header" fix would have broken, which is why D-2
# rejects that direction outright.
: > "$BOT_SPOOL"
out="$(mark_gate "$CFG" mark-run-d4 sess-mark-2 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'session_id: sess-mark-2' "$BOT_SPOOL" 2>/dev/null \
   && ! grep -q 'session_id: sess-mark-1' "$BOT_SPOOL" 2>/dev/null; then
  pass "(ms4) a second build session's marker carries its OWN session id, not the header's (D-4/AC-8)"
else fail "(ms4) expected the ambient id on the marker, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# AC-9/D-13. The appended row must stay OUT of the `session_id:` first-match race — the same
# extraction lean-reconcile.sh:304 and cmd_verdict:2001 both perform, and both call whatever it
# returns THE build session. Two fixtures, because a header-bearing file alone cannot see the
# regression: there the header wins the race by position no matter how the row is spelled. The
# discriminating shape is a progress file with NO session_id header — what seed_progress_1_to_4
# and every hand-seeded resume produce — where a row spelled `session_id: <id>` has no competitor
# and silently FABRICATES a build identity out of the last session to run `entry`.
MPROG_NOHDR="$WORK/progress-nohdr.md"
printf '# lean run — issue 8\n\nrun_id: r-nohdr\n' > "$MPROG_NOHDR"
mkdir -p "$TREE/.claude/audit"
printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/sess-nohdr.jsonl"
( unset RUN_ID; cd "$TREE" && CLAUDE_CODE_SESSION_ID=sess-nohdr SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$MPROG_NOHDR" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" entry 8 >/dev/null 2>&1 )
first_of() { # first_of <file> — record_key's own extraction, performed independently
  grep -oE 'session_id:[[:space:]]*[A-Za-z0-9._-]+' "$1" 2>/dev/null | head -n1 | sed -E 's/^session_id:[[:space:]]*//'
}
mfirst_session="$(first_of "$MPROG")"
mfirst_nohdr="$(first_of "$MPROG_NOHDR")"
if [ "$mfirst_session" = "sess-mark-1" ] && [ -z "$mfirst_nohdr" ] \
   && grep -qF '| session | sess-nohdr' "$MPROG_NOHDR"; then
  pass "(ms5) a session row records the id without claiming the session_id: key — no header, no fabricated build identity"
else fail "(ms5) session rows entered the session_id: race — with-header '$mfirst_session', header-less '$mfirst_nohdr'"; fi

# AC-4/D-3/D-5. A REVIEW session may READ an identity, never establish one. `bash G 4` is the
# call review-lean makes against the build's progress file; if it recorded a session, that
# session could then whitelist itself and mark — the silent-inheritance failure the role-keyed
# run-id split already exists to prevent. Paired: the milestone call first, then the mark.
: > "$BOT_SPOOL"
mark_gate "$CFG" mark-run-rev sess-review-m4 4 8 >/dev/null 2>&1
out="$(mark_gate "$CFG" mark-run-rev sess-review-m4 mark 8 --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'not a recorded BUILD session' <<<"$out"; then
  pass "(ms6) a review session running milestone 4 records no session, so it still cannot mark (D-3/D-5)"
else fail "(ms6) a milestone call whitelisted the session that made it, rc=$rc: $out"; fi

# AC-3. `claim` is the other half of the arm that may establish an identity, and it records under
# BOTH adapters — driven here on jira, the only adapter whose claim path is drivable without a
# live bot. The entry call uses a DIFFERENT session, so the file already carries a header and an
# attestation row: if claim recorded nothing, sess-claim-1 would be refused below.
CPROG="$WORK/progress-claim.md"
rm -f "$CPROG"
mkdir -p "$TREE/.claude/audit"
printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/sess-claim-entry.jsonl"
printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/sess-claim-1.jsonl"
( unset RUN_ID; cd "$TREE" && CLAUDE_CODE_SESSION_ID=sess-claim-entry SECOND_SHIFT_CONFIG="$CFG_JIRA" \
    LEAN_PROGRESS_FILE="$CPROG" bash "$GATE" entry "$JKEY" >/dev/null 2>&1 )
( unset RUN_ID; cd "$TREE" && CLAUDE_CODE_SESSION_ID=sess-claim-1 SECOND_SHIFT_CONFIG="$CFG_JIRA" \
    LEAN_PROGRESS_FILE="$CPROG" bash "$GATE" claim "$JKEY" >/dev/null 2>&1 )
: > "$BOT_SPOOL"
out="$( cd "$TREE" && RUN_ID=mark-run-c CLAUDE_CODE_SESSION_ID=sess-claim-1 SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$CPROG" GH_BOT="$WORK/bot-stub.sh" BOT_SPOOL="$BOT_SPOOL" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" mark 8 \
        --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'session_id: sess-claim-1' "$BOT_SPOOL" 2>/dev/null; then
  pass "(ms7) claim records the ambient session into the set, under a tracker that writes nothing (AC-3)"
else fail "(ms7) claim did not record its session, rc=$rc: $out / progress=$(cat "$CPROG" 2>/dev/null)"; fi

# AC-7/D-9, half one: no progress file at all. Fail CLOSED with a remedy — a `mark` that fell
# through here would write `session_id: unset` onto the marker, and "unverifiable" must never
# resolve to "fine".
: > "$BOT_SPOOL"
out="$( cd "$TREE" && RUN_ID=mark-run-x CLAUDE_CODE_SESSION_ID=sess-mark-1 SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$WORK/progress-absent.md" GH_BOT="$WORK/bot-stub.sh" BOT_SPOOL="$BOT_SPOOL" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" mark 8 \
        --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'recorded no build session' <<<"$out"; then
  pass "(ms8) with no build session recorded anywhere, mark refuses rather than stamping 'unset' (D-9)"
else fail "(ms8) expected the fail-closed refusal, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# AC-7/D-9, half two: THE VACUITY. A header frozen at `unset` and an unset ambient session are
# both unverifiable, and a naive `[ "$ambient" = "$recorded" ]` passes them — two unknowns
# agreeing. The set drops 'unset' on the way in and the ambient side is checked for emptiness, so
# neither can satisfy the other.
printf '# lean run — issue 8\n\nrun_id: r-vac\nsession_id: unset\n' > "$WORK/progress-vacuous.md"
: > "$BOT_SPOOL"
out="$( unset CLAUDE_CODE_SESSION_ID; cd "$TREE" && RUN_ID=mark-run-v SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$WORK/progress-vacuous.md" GH_BOT="$WORK/bot-stub.sh" BOT_SPOOL="$BOT_SPOOL" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" mark 8 \
        --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$BOT_SPOOL" ] && grep -q 'recorded no build session' <<<"$out"; then
  pass "(ms9) an unset ambient session does not compare EQUAL to an 'unset' recorded one (D-9)"
else fail "(ms9) the vacuous comparison passed, rc=$rc: $out / spool=$(cat "$BOT_SPOOL" 2>/dev/null)"; fi

# AC-10. Backward compatibility for a run already in flight when this lands: its progress file
# has a header and no session rows, and the header IS the build identity by cmd_verdict's own
# compare — so it marks. Without the header in the set every such run would strand at `mark`,
# with the recovery this issue is about as the only way out.
printf '# lean run — issue 8\n\nrun_id: r-inflight\nsession_id: sess-inflight\n' > "$WORK/progress-inflight.md"
: > "$BOT_SPOOL"
out="$( cd "$TREE" && RUN_ID=mark-run-i CLAUDE_CODE_SESSION_ID=sess-inflight SECOND_SHIFT_CONFIG="$CFG" \
        LEAN_PROGRESS_FILE="$WORK/progress-inflight.md" GH_BOT="$WORK/bot-stub.sh" BOT_SPOOL="$BOT_SPOOL" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" mark 8 \
        --pr-file "$WORK/pr-mark.json" --comments-file "$WORK/comments-none.json" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'session_id: sess-inflight' "$BOT_SPOOL" 2>/dev/null; then
  pass "(ms10) a header-only progress file (no session rows) still marks — no in-flight run strands (AC-10)"
else fail "(ms10) an in-flight run stranded at mark, rc=$rc: $out"; fi

# AC-4. `mark` is a PURE READER. A guard that recorded before checking would whitelist itself and
# be vacuous, so the refused calls above must have left the file untouched — asserted against the
# fixture's own byte count rather than by re-reading the ids it prints.
if [ "$(mcount '| session | ')" -eq 3 ] \
   && ! grep -qF 'sess-review-r' "$MPROG" 2>/dev/null \
   && ! grep -qF 'sess-review-m4' "$MPROG" 2>/dev/null; then
  pass "(ms11) mark records nothing — neither the refused sessions nor the successful ones were added (AC-4)"
else fail "(ms11) mark wrote to the progress file: rows=$(mcount '| session | '), file=$(cat "$MPROG" 2>/dev/null)"; fi

# ---- (fp) #439: what this gate writes must survive the consumer's format check --------------
# $PLANS_DIR sits inside the format gate of at least one consumer, and this gate writes two
# markdown artifacts there and requires both committed. The manifest is padded at the write site
# (the re-derive byte-compare forbids formatting it afterwards); the verdict record is handed to
# a locally resolved prettier, guarded, because its body is arbitrary authored markdown.
#
# The padder is exercised in LIBRARY MODE against byte-exact goldens rather than only through
# the render path, for a reason the render path itself states: every column of the manifest is
# wider than the 3-dash minimum, so that branch is unreachable there. The goldens below were
# each produced by prettier 3.7.4 and pasted; (fp5) re-derives them from a live prettier when
# one is installed, and SKIPS — never fails — when none is.

# md_table_prettier through the real production body: no copy of the padder exists in this file.
# shellcheck disable=SC1090  # $GATE is the script under test; following it is the point.
mdtab() { ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 \
            && md_table_prettier ); }

# FP_IN/FP_WANT are reassigned in place through (fp1)-(fp4), so a live oracle reading them at the
# end would re-derive only whichever pair happened to be last — the narrowest one, not the 64-char
# digest shape the receipt actually depends on. Each pair is kept as it is declared, and (fp5)
# walks all of them.
FP_GOLDENS="$WORK/fp-goldens"; mkdir -p "$FP_GOLDENS"
fp_keep() { printf '%s\n' "$FP_IN" > "$FP_GOLDENS/$1.in"; printf '%s\n' "$FP_WANT" > "$FP_GOLDENS/$1.want"; }

# (fp1) WIDTH FROM A BODY VALUE, in every column. A padder that sized columns from the header
# alone produces a table prettier immediately re-pads.
FP_IN="| RS | route | state |
| RS-1 | /a | default |
| RS-10 | /longer | on |"
FP_WANT="| RS    | route   | state   |
| ----- | ------- | ------- |
| RS-1  | /a      | default |
| RS-10 | /longer | on      |"
fp_keep fp1
FP_GOT="$(printf '%s\n' "$FP_IN" | mdtab)"
if [ "$FP_GOT" = "$FP_WANT" ]; then
  pass "(fp1) column widths come from the widest body cell"
else fail "(fp1) padded table differs from prettier's form:
$FP_GOT"; fi

# (fp2) WIDTH FROM THE HEADER, the other direction — `sha256` is wider than its only value. A
# padder that ignored the header row when measuring gets this one wrong and (fp1) right.
FP_IN="| sha256 | route |
| ab | /a |"
FP_WANT="| sha256 | route |
| ------ | ----- |
| ab     | /a    |"
fp_keep fp2
FP_GOT="$(printf '%s\n' "$FP_IN" | mdtab)"
if [ "$FP_GOT" = "$FP_WANT" ]; then
  pass "(fp2) a header cell wider than every value sets the column width"
else fail "(fp2) padded table differs from prettier's form:
$FP_GOT"; fi

# (fp3) THE SHIPPED SHAPE, single row: the five real columns with a real 64-char digest, which
# is the cell that guarantees the unpadded form differs from the formatted one.
FP_IN="| RS | route | state | png | sha256 |
| RS-1 | /a | default | .claude/lean-renders/55/RS-1.png | deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef |"
FP_WANT="| RS   | route | state   | png                              | sha256                                                           |
| ---- | ----- | ------- | -------------------------------- | ---------------------------------------------------------------- |
| RS-1 | /a    | default | .claude/lean-renders/55/RS-1.png | deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef |"
fp_keep fp3
FP_GOT="$(printf '%s\n' "$FP_IN" | mdtab)"
if [ "$FP_GOT" = "$FP_WANT" ]; then
  pass "(fp3) a single-row manifest table matches prettier byte for byte"
else fail "(fp3) padded table differs from prettier's form:
$FP_GOT"; fi

# (fp4) THE 3-DASH MINIMUM. Prettier never emits a delimiter cell narrower than `---`, so a
# column whose widest content is one character still pads to three. Unreachable through the
# render path — hence library mode.
FP_IN="| a | bb |
| c | d |"
FP_WANT="| a   | bb  |
| --- | --- |
| c   | d   |"
fp_keep fp4
FP_GOT="$(printf '%s\n' "$FP_IN" | mdtab)"
if [ "$FP_GOT" = "$FP_WANT" ]; then
  pass "(fp4) columns narrower than three characters pad to the 3-dash minimum"
else fail "(fp4) padded table differs from prettier's form:
$FP_GOT"; fi

# (fp5) THE LIVE ORACLE, opportunistic. The goldens above are a claim about another program's
# output; this re-derives every one of them from that program when it is installed locally. CI
# installs nothing for it — a prettier table-format change is caught by whoever runs this suite on
# a machine that has one, never by a red build that fetched a formatter to find out.
#
# THE DELIMITER ROW IS SPLICED IN FIRST, and that is the whole subtlety. md_table_prettier's input
# contract is that the row is NOT supplied — its dash count is a function of the widths the padder
# computes — but markdown needs it for a table to exist at all. Handing prettier the padder's raw
# input makes it read a paragraph, rewrite nothing, and the comparison passes only by never
# running. An unpadded `| --- | ... |` is a real table prettier must re-pad, so the goldens below
# become what it has to produce.
FP_PRETTIER=""
for fp_c in "$(cd "$HERE" && git rev-parse --show-toplevel 2>/dev/null)/node_modules/.bin/prettier" "$(command -v prettier 2>/dev/null)"; do
  if [ -n "$fp_c" ] && [ -x "$fp_c" ]; then FP_PRETTIER="$fp_c"; break; fi
done
if [ -z "$FP_PRETTIER" ]; then
  echo "  SKIPPED: (fp5) no local prettier resolves — the live table-form oracle is opportunistic by design"
else
  FP_BAD=""
  for fp_g in "$FP_GOLDENS"/*.in; do
    fp_id="$(basename "$fp_g" .in)"
    awk 'NR==1 { print; n = gsub(/\|/, "|") - 1; d = "|"; while (n-- > 0) d = d " --- |"; print d; next } { print }' \
      "$fp_g" > "$WORK/fp-live.md"
    "$FP_PRETTIER" --write "$WORK/fp-live.md" >/dev/null 2>&1
    cmp -s "$WORK/fp-live.md" "$FP_GOLDENS/$fp_id.want" \
      || FP_BAD="$FP_BAD [$fp_id: $(diff "$FP_GOLDENS/$fp_id.want" "$WORK/fp-live.md" | head -4 | tr '\n' ' ')]"
  done
  if [ -z "$FP_BAD" ]; then
    pass "(fp5) every golden above is what this machine's prettier actually writes"
  else fail "(fp5) $FP_PRETTIER disagrees with the golden form:$FP_BAD"; fi
fi

# (fp6) INTEGRATION: the receipt the render path writes is already in that form, so the file
# the milestone tells the run to commit is the file a `--check` accepts. Asserted on the
# delimiter row, whose dash counts are a pure function of the widths the write site computed —
# the id column is 10 wide because the widest id is `RS-n.rects` (#711), not `RS-n`.
dspec_armed
printf 'x\n' > "$DTREE/fp-move-the-patch-id.txt"
dcommit "the armed spec and a tree change, so the receipt must actually be re-derived"
dreset
dmode ok
rm -f "$DCALLS" "$DMANIFEST"
FP_OUT3="$(dgate 3 55)"; rc=$?
FP_DELIM="$(grep -m1 -E '^\| -+ \|' "$DMANIFEST" 2>/dev/null)"
FP_HDR="$(grep -m1 -F '| RS ' "$DMANIFEST" 2>/dev/null)"
if [ "$rc" -eq 1 ] && [ -n "$FP_DELIM" ] && [ ${#FP_DELIM} -eq ${#FP_HDR} ] \
   && grep -qE '^\| -{10} \| -+ \| -+ \| -+ \| -{64} \|$' <<<"$FP_DELIM"; then
  pass "(fp6) the rendered receipt carries a padded delimiter row sized to its own columns"
else fail "(fp6) the receipt is not in prettier's table form, rc=$rc, delim=[$FP_DELIM] hdr=[$FP_HDR]"; fi

# (fp7) ...and the reader is unchanged by it. render_manifest_rows trims each cell, so a PADDED
# manifest and an UNPADDED one written before this change parse to the same rows — which is what
# lets a receipt already committed on an in-flight branch keep being read.
mdrows() { # mdrows <manifest-file>
  # `m` is copied out of $1 BEFORE the source: library mode's placeholder args are consumed by
  # the gate's own parser, which leaves this scope with no positional parameters at all.
  local m="$1"
  # shellcheck disable=SC1090,SC2034  # $GATE is the script under test, and the two assignments
  # are read by the sourced production function rather than by anything in this file.
  ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1 \
    && REPO_ROOT="$(dirname "$m")" && RENDER_MANIFEST_REL="$(basename "$m")" && render_manifest_rows )
}
sed -e 's/  */ /g' "$DMANIFEST" > "$WORK/fp-legacy-renders.md"
if [ "$(mdrows "$DMANIFEST")" = "$(mdrows "$WORK/fp-legacy-renders.md")" ] \
   && [ -n "$(mdrows "$DMANIFEST")" ]; then
  pass "(fp7) padded and legacy unpadded manifests parse to identical rows"
else fail "(fp7) the reader disagrees between the two forms: padded=[$(mdrows "$DMANIFEST")] legacy=[$(mdrows "$WORK/fp-legacy-renders.md")]"; fi
dcommit "the padded render receipt"

# ---- the verdict record's format step -------------------------------------------------------
# A fake prettier at the rung lean_resolve_prettier actually probes, so these cases exercise the
# resolver too. `mode` decides what it does to the file, which is how one fixture covers both
# the benign path and the header-destroying one without needing prettier installed.
FP_NM="$DTREE/node_modules/.bin"
fp_formatter() { # fp_formatter <benign|join>
  mkdir -p "$FP_NM"
  cat > "$FP_NM/prettier" <<EOFMT
#!/usr/bin/env bash
mode=$1
EOFMT
  cat >> "$FP_NM/prettier" <<'EOFMT'
f=""
for a in "$@"; do case "$a" in --*) : ;; *) f="$a" ;; esac; done
[ -n "$f" ] || exit 1
if [ "$mode" = "join" ]; then
  # proseWrap: "always" joins the header block into one line — measured, and the reason the
  # verify-and-revert guard exists: every `^key:`-anchored reader then finds nothing.
  awk 'BEGIN{h=0} /^[A-Za-z_][A-Za-z0-9_]*[:=]/ && h==0 {h=1} h==1 && /^[[:space:]]*$/ {h=2; print ""; next} h==1 {printf "%s ", $0; next} {print}' "$f" > "$f.j" && mv "$f.j" "$f"
else
  printf 'FORMATTED-BODY-MARKER\n' >> "$f"
fi
exit 0
EOFMT
  chmod +x "$FP_NM/prettier"
}
fp_unformatter() { rm -rf "$DTREE/node_modules"; }

# (fp8) THE BENIGN PATH: a resolvable formatter runs, and its output is kept. Without this the
# revert cases below would pass on a gate that never formatted anything at all.
fp_formatter benign
out="$(dverdict sess-review-fp r-review-fp --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^FORMATTED-BODY-MARKER$' "$DVERDICT" \
   && grep -q '^run_id: r-review-fp$' "$DVERDICT" \
   && grep -q 'formatted with' <<<"$out"; then
  pass "(fp8) the verdict record is handed to the resolved formatter and its output kept"
else fail "(fp8) expected a formatted record, rc=$rc: $out / $(cat "$DVERDICT" 2>/dev/null)"; fi

# (fp9) THE HEADER-DESTROYING PATH: the same call, a formatter that flattens the header block.
# The record must come back UNFORMATTED with every key readable — a joined header silently
# degrades the round to a chain root and drops `fidelity:`, which no reader can detect after
# the fact. One warn line, and the call still succeeds: formatting is never the gate.
fp_formatter join
out="$(dverdict sess-review-fp r-review-fp --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^run_id: r-review-fp$' "$DVERDICT" \
   && grep -q '^fidelity: pass$' "$DVERDICT" \
   && grep -q 'changed header key' <<<"$out"; then
  pass "(fp9) a formatter that flattens the header is reverted, warned about, and not fatal"
else fail "(fp9) expected a reverted record and a warning, rc=$rc: $out / $(cat "$DVERDICT" 2>/dev/null)"; fi

# (fp10) NO FORMATTER: skipped, warned once, still rc=0. An absent prettier is a consumer fact,
# not a run defect — and the gate must not reach the network to invent one, so the warning is
# the only thing that fires.
fp_unformatter
out="$(dverdict sess-review-fp r-review-fp --pr 55 --verdict approve --fidelity pass --summary-file "$DEVIDENCE")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^run_id: r-review-fp$' "$DVERDICT" \
   && ! grep -q '^FORMATTED-BODY-MARKER$' "$DVERDICT" \
   && grep -q 'no prettier under' <<<"$out"; then
  pass "(fp10) an unresolvable formatter skips the step with one warning, never a failure"
else fail "(fp10) expected an unformatted record and a skip warning, rc=$rc: $out / $(cat "$DVERDICT" 2>/dev/null)"; fi

# (fp11) The same refusal (fp6) captured, read for what it TELLS the run. The gate formats only
# what it authors, so the spec and any intent-gap record are the author's — and this message is
# the only place a run learns that before CI does. It also states the re-derive cost, because a
# padded rewrite moves reviewed_patch_id and voids a verdict already standing on the branch.
if grep -q 'intent-gap record are NOT' <<<"$FP_OUT3" \
   && grep -q 'voids it' <<<"$FP_OUT3"; then
  pass "(fp11) the milestone-3 commit refusal names the formatting obligation and the re-derive cost"
else fail "(fp11) the milestone-3 refusal does not carry both notices: $FP_OUT3"; fi

# (fp12) AC-7's OTHER half. Milestone 4 refuses an uncommitted record on two separate branches —
# never-committed and committed-but-dirty — and each carries its own copy of the obligation. They
# are a different code path from (fp11)'s milestone-3 message, so the edit that added the notice
# could have landed on one and missed these; a guard that pins only the first would not notice.
# A complete-enough record: the reconciliation and head keys are checked BEFORE the commit
# branches, so a stub record reds on those instead and never reaches the messages under test.
fp_record() { { echo 'verdict=approve'; echo 'run_id: r-review-fp12'; echo 'session_id: sess-review-fp12';
                echo "reviewed_head: $(git -C "$DTREE" rev-parse HEAD)"; } > "$1"; }
# The never-committed branch needs a record path with NO history, and issue 55's has been
# committed several times over by now — so branch A runs against an unused issue number, whose
# record `git log` has never seen. require_entry_attested() reads the progress file for an entry
# row, not for an issue, so the same fixture progress file serves both calls.
dreset
fp_record "$DTREE/docs/plans/acme-56-lean-verdict.md"
FP_OUT4A="$(dgate 4 56)"
fp_record "$DVERDICT"
dcommit "the verdict record, committed"
printf 'a local edit\n' >> "$DVERDICT"
dreset
FP_OUT4B="$(dgate 4 55)"
if grep -q 'format those before committing' <<<"$FP_OUT4A" \
   && grep -q 'formats only what it authors' <<<"$FP_OUT4B"; then
  pass "(fp12) both milestone-4 commit refusals name the formatting obligation"
else fail "(fp12) a milestone-4 refusal is missing the notice:
A=$FP_OUT4A
B=$FP_OUT4B"; fi

# ---- (wt) WORKTREE TEARDOWN: the `teardown` subcommand and the entry sweep (#442) -------------
# The lane never destroyed a worktree. Both mechanisms funnel through one removal, so the cases
# below are split accordingly: the PRECONDITIONS (which either path can decline on) are pinned
# once through `teardown`, and the sweep's own cases are about QUALIFICATION — which worktrees it
# will even consider, and what a failed tracker lookup must not be mistaken for.
#
# Paths are compared literally by the implementation (`$wt = $MAIN_ROOT`, `$wt = $REPO_ROOT`), and
# `git worktree list` reports physically-resolved paths — on macOS `$TMPDIR` is a symlink, so a
# fixture built on the unresolved path would make every one of those comparisons false and the
# guards would read as absent. Resolve once, here.
WREAL="$(cd "$WORK" && pwd -P)"
WTREE="$WREAL/wtree"
mkdir -p "$WTREE/.claude/audit"
git -C "$WTREE" init -q
git -C "$WTREE" config user.email t@example.invalid
git -C "$WTREE" config user.name t
# The default branch name is a git CONFIG, not a constant — `main` here and `master` on an older
# box. Every worktree below is cut from `main` by name and (wt19) checks it back out, so pin it
# rather than inherit whatever the runner's git decided.
git -C "$WTREE" symbolic-ref HEAD refs/heads/main
printf '.claude/\n' > "$WTREE/.gitignore"
git -C "$WTREE" add -A >/dev/null 2>&1
git -C "$WTREE" commit -q -m "wt fixture" >/dev/null 2>&1
git -C "$WTREE" update-ref refs/remotes/origin/main HEAD
WSID="sess-wt-build"
printf '{"tool":"Bash"}\n' > "$WTREE/.claude/audit/$WSID.jsonl"
WPROG="$WREAL/wt-progress.md"
WPR="$WREAL/pr-fixtures"
mkdir -p "$WPR"

# Stands in for `gh pr list --head <branch> --state all --json number,state`. A MISSING fixture
# exits non-zero: a failed lookup and an empty array are different answers (D-12), and a stub
# that returned `[]` for both could not tell the two cases apart.
cat > "$WREAL/gh-wt-stub.sh" <<'EOF'
#!/usr/bin/env bash
# #611: `entry` reads the ticket at the run boundary now, and these cases drive `entry` for its
# SWEEP. Answer that read the way the suite-wide stub does — an open ticket — so the sweep's own
# assertions are what these cases turn on, rather than a boundary refusal upstream of them.
case "${1:-}/${2:-}" in
  issue/view)
    case "$*" in
      *--json\ labels*) printf '\n' ;;
      *)                printf 'OPEN\n' ;;
    esac
    exit 0 ;;
esac
head=""
while [ $# -gt 0 ]; do
  case "$1" in --head) head="${2:-}"; shift 2 ;; *) shift ;; esac
done
f="$PR_FIXTURE_DIR/$(printf '%s' "$head" | tr '/' '_').json"
[ -f "$f" ] || { echo "gh: could not resolve $head" >&2; exit 1; }
cat "$f"
EOF
chmod +x "$WREAL/gh-wt-stub.sh"
pr_fixture() { printf '%s' "$2" > "$WPR/$(printf '%s' "$1" | tr '/' '_').json"; }

wgate() { # wgate <cwd> <args...>
  local cwd="$1"; shift
  ( unset RUN_ID GH_BOT; cd "$cwd" && CLAUDE_CODE_SESSION_ID="$WSID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$WPROG" GH="$WREAL/gh-wt-stub.sh" PR_FIXTURE_DIR="$WPR" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
wt_registered() { git -C "$WTREE" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $1"; }
wt_make() { # wt_make <issue> — a clean lane worktree whose branch is fully pushed
  local br="claude/acme-$1" p="$WREAL/wt-$1"
  git -C "$WTREE" worktree add -q --no-track -b "$br" "$p" main 2>/dev/null
  git -C "$WTREE" update-ref "refs/remotes/origin/$br" "$(git -C "$WTREE" rev-parse "$br")"
  printf '%s' "$p"
}
# #530: a SECOND worktree on a branch `wt_make` already checked out. `--force` is required —
# without it git refuses a branch already checked out elsewhere — and it is what the fixture is
# for: the sanctioned "review session cut its own checkout of the same PR head" shape.
wt_make_second() { # wt_make_second <issue> <suffix> — a second worktree on wt_make's branch
  local br="claude/acme-$1" p="$WREAL/wt-$1-$2"
  git -C "$WTREE" worktree add -q --force "$p" "$br" 2>/dev/null
  printf '%s' "$p"
}

# --- the preconditions, through `teardown` ---------------------------------------------------
rm -f "$WPROG"
p="$(wt_make 20)"
out="$(wgate "$WTREE" teardown 20)"; rc=$?
# AC-4 in the same breath as AC-1/2: the branch must SURVIVE its worktree. The PR points at it
# and the verdict record is committed on it, so a "helpful" `git branch -D` here would delete
# the evidence the merge boundary reads.
if [ "$rc" -eq 0 ] && ! wt_registered "$p" && [ ! -d "$p" ] \
   && git -C "$WTREE" rev-parse --verify -q claude/acme-20 >/dev/null; then
  pass "(wt1) teardown removes a clean, fully-pushed lane worktree and leaves its branch intact"
else fail "(wt1) rc=$rc, still registered=$(wt_registered "$p" && echo yes || echo no): $out"; fi

# ...and it did that with NO entry attestation in the progress file. Deliberate: teardown asserts
# nothing and records nothing, so gating it behind `entry` would block cleanup for no evidentiary
# gain. A future edit that adds it to require_entry_attested's set reds here with rc=2.
if [ ! -f "$WPROG" ] || ! grep -q 'entry' "$WPROG" 2>/dev/null; then
  pass "(wt2) teardown is not a build-role gated call — it needs no entry attestation and writes no record"
else fail "(wt2) teardown touched the progress file: $(cat "$WPROG" 2>/dev/null)"; fi

out="$(wgate "$WTREE" teardown 20)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'nothing to remove' <<<"$out"; then
  pass "(wt3) a second teardown is a no-op, not an error"
else fail "(wt3) expected an idempotent no-op, rc=$rc: $out"; fi

p="$(wt_make 21)"
printf 'work in progress\n' > "$p/scratch.txt"
out="$(wgate "$WTREE" teardown 21)"; rc=$?
if [ "$rc" -eq 0 ] && wt_registered "$p" && grep -qF 'is not clean' <<<"$out" \
   && grep -qF 'scratch.txt' <<<"$out" \
   && grep -qF 'worktree remove' <<<"$out"; then
  pass "(wt4) an unclean worktree is kept, its blocking file named, and the manual command printed — rc=0"
else fail "(wt4) expected a kept-and-explained refusal at rc=0, rc=$rc: $out"; fi
rm -f "$p/scratch.txt"

# The data-loss direction. `git worktree remove` would take these commits with it.
p="$(wt_make 22)"
git -C "$p" commit -q --allow-empty -m "unpushed work" >/dev/null 2>&1
out="$(wgate "$WTREE" teardown 22)"; rc=$?
if [ "$rc" -eq 0 ] && wt_registered "$p" && grep -qF 'not on origin/claude/acme-22' <<<"$out"; then
  pass "(wt5) a worktree carrying unpushed commits is kept"
else fail "(wt5) expected a refusal on unpushed work, rc=$rc: $out"; fi

# The case the issue's own proposed precondition (`HEAD = origin/<branch>`) gets WRONG. Once the
# review session pushes its verdict record the build worktree is legitimately BEHIND origin —
# strict equality would refuse exactly the removal this whole ticket asks for.
p="$(wt_make 23)"
git -C "$p" commit -q --allow-empty -m "the review session's verdict record" >/dev/null 2>&1
git -C "$WTREE" update-ref refs/remotes/origin/claude/acme-23 "$(git -C "$p" rev-parse HEAD)"
git -C "$p" reset -q --hard HEAD~1
out="$(wgate "$WTREE" teardown 23)"; rc=$?
if [ "$rc" -eq 0 ] && ! wt_registered "$p"; then
  pass "(wt6) a worktree merely BEHIND origin is removed — behind is safe, ahead is not"
else fail "(wt6) a behind-origin worktree was refused, rc=$rc: $out"; fi

# AC-6: git's OWN refusal, which the preconditions above cannot produce. A locked worktree is
# clean and fully pushed and `git worktree remove` still declines — the same keep-and-explain
# path has to carry that through, rather than the removal failing silently.
p="$(wt_make 24)"
git -C "$WTREE" worktree lock "$p" >/dev/null 2>&1
out="$(wgate "$WTREE" teardown 24)"; rc=$?
git -C "$WTREE" worktree unlock "$p" >/dev/null 2>&1
if [ "$rc" -eq 0 ] && wt_registered "$p" && grep -qF 'git refused to remove it' <<<"$out"; then
  pass "(wt7) a removal git itself refuses is reported through the same keep path, still rc=0"
else fail "(wt7) expected git's refusal surfaced at rc=0, rc=$rc: $out"; fi
git -C "$WTREE" worktree remove --force "$p" >/dev/null 2>&1

# AC-5: teardown is OUTSIDE the 1..5 progression. `all` is mandated BEFORE checklist step 9, so a
# milestone that removed the worktree would delete it mid-run, before the closing comment.
p="$(wt_make 25)"
wgate "$WTREE" entry 25 >/dev/null 2>&1
out="$(wgate "$WTREE" all 25)"; rc=$?
if wt_registered "$p"; then
  pass "(wt8) 'all' removes nothing — teardown is not part of the milestone progression"
else fail "(wt8) 'all' destroyed a worktree, rc=$rc: $out"; fi

# --- (wt20)-(wt22) #530: a SECOND worktree on the same branch is a SANCTIONED state, not a -------
# violated expectation — review-lean cuts its own checkout of the PR head, and the build worktree
# is not guaranteed to still be there. `lean_worktree_for_branch`'s first-match return orphaned
# whichever one it did not see; these pin that both are now accounted for.
# Issue numbers 120-122, not 26-28: the entry-sweep qualification block below already owns
# 26-29 for its own fixtures, and `wt_make`'s `-b` add fails silently (2>/dev/null) on a branch
# that already exists — reusing those numbers here left that block's worktrees never created,
# which is what actually broke (wt9)-(wt11) there rather than anything this pins.
p1="$(wt_make 120)"
p2="$(wt_make_second 120 b)"
out="$(wgate "$WTREE" teardown 120)"; rc=$?
if [ "$rc" -eq 0 ] && ! wt_registered "$p1" && ! wt_registered "$p2" \
   && git -C "$WTREE" rev-parse --verify -q claude/acme-120 >/dev/null; then
  pass "(wt20) #530: two clean, fully-pushed worktrees on one branch are both removed, the branch kept"
else fail "(wt20) rc=$rc, p1 reg=$(wt_registered "$p1" && echo yes || echo no) p2 reg=$(wt_registered "$p2" && echo yes || echo no): $out"; fi

# The mixed case: one tree is collected, the other still holds work. Both preconditions apply
# PER TREE — a dirty sibling must not block the clean one's removal, and a removed sibling must
# not hide the one that still needs a human.
p1="$(wt_make 121)"
p2="$(wt_make_second 121 b)"
printf 'uncollected\n' > "$p2/scratch.txt"
out="$(wgate "$WTREE" teardown 121)"; rc=$?
if [ "$rc" -eq 0 ] && ! wt_registered "$p1" && wt_registered "$p2" \
   && grep -qF 'is not clean' <<<"$out" && grep -qF 'scratch.txt' <<<"$out"; then
  pass "(wt21) #530: one clean and one dirty tree on the same branch — the clean one is removed, the dirty one kept"
else fail "(wt21) rc=$rc, p1 reg=$(wt_registered "$p1" && echo yes || echo no) p2 reg=$(wt_registered "$p2" && echo yes || echo no): $out"; fi
rm -f "$p2/scratch.txt"
git -C "$WTREE" worktree remove --force "$p2" >/dev/null 2>&1

# D-7: the CALLER's own worktree is one of the registered trees on its branch when teardown runs
# from inside it (the ordinary checklist-step-9 shape) — and it must be removed like any other,
# never silently skipped for being the cwd.
p1="$(wt_make 122)"
p2="$(wt_make_second 122 b)"
out="$(wgate "$p1" teardown 122)"; rc=$?
if [ "$rc" -eq 0 ] && ! wt_registered "$p1" && ! wt_registered "$p2"; then
  pass "(wt22) #530 D-7: teardown run from inside its own worktree removes it too, not just its sibling"
else fail "(wt22) rc=$rc, p1(own) reg=$(wt_registered "$p1" && echo yes || echo no) p2 reg=$(wt_registered "$p2" && echo yes || echo no): $out"; fi

# --- (if) #531 D-3: the shared IN-FLIGHT predicate, exposed read-only ---------------------------
# ONE PREDICATE, TWO CALLERS. The (wt4)-(wt6) cases above pin it through `teardown`; these pin the
# same conditions through the subcommand the SCHEDULER calls, which is the point of the extraction
# — two copies of "is this tree collected" would be two answers the moment one grew a case, and a
# scheduler-side copy that drifted LENIENT costs a review round spent on code nobody will merge.
#
# THREE ANSWERS, NOT TWO. "Could not look" is neither "clean" nor "dirty", and a caller that could
# not tell them apart would either stop every run whose fetch flaked or review a stale head.
rm -f "$WPROG"
p="$(wt_make 40)"
out="$(wgate "$WTREE" inflight 40)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'inflight: clean' <<<"$out"; then
  pass "(if1) a clean, fully-pushed lane worktree reports nothing in flight"
else fail "(if1) expected rc=0 on a collected worktree, rc=$rc: $out"; fi

# ...and it did that WITHOUT an entry attestation and WITHOUT bringing a record into existence.
# Both matter: the states this read is most needed in are the ones where a spawn died early, and
# a read that created the file whose absence is itself an answer would be a writer.
if [ ! -f "$WPROG" ]; then
  pass "(if2) the inflight read is read-only — no entry attestation required, and no progress file created"
else fail "(if2) inflight wrote a record: $(cat "$WPROG" 2>/dev/null)"; fi

printf 'work in progress\n' > "$p/scratch.txt"
out="$(wgate "$WTREE" inflight 40)"; rc=$?
if [ "$rc" -eq 8 ] && grep -qF 'is not clean' <<<"$out" && grep -qF 'scratch.txt' <<<"$out"; then
  pass "(if3) a dirty tree is exit 8, naming the file that blocks it"
else fail "(if3) expected rc=8 on a dirty tree, rc=$rc: $out"; fi
rm -f "$p/scratch.txt"

git -C "$p" commit -q --allow-empty -m "committed, never pushed" >/dev/null 2>&1
out="$(wgate "$WTREE" inflight 40)"; rc=$?
if [ "$rc" -eq 8 ] && grep -qF 'not on origin/claude/acme-40' <<<"$out"; then
  pass "(if4) an unpushed commit is exit 8 too — the shape a BUILD session that exited 0 without pushing leaves"
else fail "(if4) expected rc=8 on unpushed work, rc=$rc: $out"; fi

# The asymmetry (wt6) pins at the other caller: BEHIND origin is safe, AHEAD is not. Once the
# review session pushes its verdict record the build worktree is legitimately behind, and a
# predicate that stopped there would fire on every honest run.
git -C "$WTREE" update-ref refs/remotes/origin/claude/acme-40 "$(git -C "$p" rev-parse HEAD)"
git -C "$p" reset -q --hard HEAD~1
out="$(wgate "$WTREE" inflight 40)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(if5) a worktree merely BEHIND origin holds nothing in flight — the same asymmetry teardown applies"
else fail "(if5) a behind-origin worktree was reported in flight, rc=$rc: $out"; fi

# FAIL CLOSED, and DISTINGUISHABLY. An unresolvable remote-tracking ref is not a clean answer and
# not a dirty one; collapsing it into either is the error-reads-as-success shape the whole
# taxonomy exists to remove.
p41="$(wt_make 41)"
git -C "$WTREE" update-ref -d refs/remotes/origin/claude/acme-41 >/dev/null 2>&1
out="$(wgate "$WTREE" inflight 41)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'could not be evaluated' <<<"$out" \
   && grep -qF 'unresolvable' <<<"$out"; then
  pass "(if6) an unresolvable origin ref is exit 1 — a read that did not complete, never a clean answer"
else fail "(if6) expected rc=1 on an unresolvable remote, rc=$rc: $out"; fi
git -C "$WTREE" worktree remove --force "$p41" >/dev/null 2>&1

# NO WORKTREE IS 0, and it has to be: the scheduler calls this after the close-out, whose last act
# is teardown. A tree that does not exist holds no uncollected work, and `git worktree remove`
# refuses a dirty one, so the directory cannot have taken work with it.
out="$(wgate "$WTREE" inflight 42)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'no registered worktree' <<<"$out"; then
  pass "(if7) a branch with no worktree reports nothing in flight, naming why"
else fail "(if7) expected rc=0 with nothing to read, rc=$rc: $out"; fi
git -C "$WTREE" worktree remove --force "$p" >/dev/null 2>&1

# --- (if8)-(if10) #530 D-3: the SAME predicate, read across every worktree on the branch --------
# ONE PREDICATE, MULTIPLE TREES NOW. (wt20)-(wt22) above pin the same fixture shape through
# `teardown`; these pin it through the scheduler's read. The strongest answer wins: 8 outranks 1,
# 1 outranks 0 — a tree demonstrably holding work is more actionable than one nothing could read,
# and a read that did not complete is not the clean answer either.
p1="$(wt_make 46)"
p2="$(wt_make_second 46 b)"
printf 'uncollected\n' > "$p2/scratch.txt"
out="$(wgate "$WTREE" inflight 46)"; rc=$?
if [ "$rc" -eq 8 ] && grep -qF 'STILL HOLDS WORK' <<<"$out" && grep -qF "$p2" <<<"$out"; then
  pass "(if8) #530 D-3: a dirty tree outranks a clean sibling on the same branch — 8 over 0"
else fail "(if8) rc=$rc: $out"; fi
rm -f "$p2/scratch.txt"
git -C "$WTREE" worktree remove --force "$p2" >/dev/null 2>&1
git -C "$WTREE" worktree remove --force "$p1" >/dev/null 2>&1

# The unresolvable-status case is per-TREE (a missing directory), unlike an unresolvable remote
# ref — which is per-BRANCH and so cannot differ between two worktrees on the same one. Deleting
# the tree out from under its registration (never pruned) reproduces "the status could not be
# read" without touching the branch both trees share.
p1="$(wt_make 47)"
p2="$(wt_make_second 47 b)"
rm -rf "$p2"
out="$(wgate "$WTREE" inflight 47)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'could not be evaluated' <<<"$out"; then
  pass "(if9) #530 D-3: a tree whose status cannot be read outranks a clean sibling — 1 over 0"
else fail "(if9) rc=$rc: $out"; fi
git -C "$WTREE" worktree remove --force "$p1" >/dev/null 2>&1
git -C "$WTREE" worktree prune >/dev/null 2>&1

p1="$(wt_make 48)"
p2="$(wt_make_second 48 b)"
printf 'uncollected\n' > "$p1/scratch.txt"
rm -rf "$p2"
out="$(wgate "$WTREE" inflight 48)"; rc=$?
if [ "$rc" -eq 8 ] && grep -qF 'STILL HOLDS WORK' <<<"$out" && grep -qF "$p1" <<<"$out"; then
  pass "(if10) #530 D-3: a dirty tree outranks an unreadable sibling — 8 over 1"
else fail "(if10) rc=$rc: $out"; fi
rm -f "$p1/scratch.txt"
git -C "$WTREE" worktree remove --force "$p1" >/dev/null 2>&1
git -C "$WTREE" worktree prune >/dev/null 2>&1

# --- (td) #531 D-11: teardown REPORTS its outcome, and is never certified ------------------------
# Checklist step 9 runs `bash G 5` and THEN teardown, so the outcome does not exist when milestone
# 5 is decided and cannot be one of its obligations. It gets a row of its own instead, in its own
# `| teardown |` namespace — which is what keeps a hygiene outcome out of every reader that
# anchors on `| milestone-<n> |`.
TDPROG="$WREAL/td-progress.md"
tdgate() { ( unset RUN_ID GH_BOT; cd "$WTREE" && CLAUDE_CODE_SESSION_ID="$WSID" \
             SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$TDPROG" \
             GH="$WREAL/gh-wt-stub.sh" PR_FIXTURE_DIR="$WPR" \
             bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ) }
td_count() { local n; [ -f "$TDPROG" ] || { echo 0; return 0; }
             n="$(grep -cF "$1" "$TDPROG" 2>/dev/null)" || n=0; echo "${n:-0}"; }

rm -f "$TDPROG"
p="$(wt_make 43)"
tdgate entry 43 >/dev/null 2>&1
td_sat_before="$(td_count '| satisfied')"
out="$(tdgate teardown 43)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(td_count '| teardown | removed |')" -eq 1 ]; then
  pass "(td1) a successful teardown records 'removed' in its own namespace"
else fail "(td1) rc=$rc, rows: $(grep 'teardown' "$TDPROG" 2>/dev/null)"; fi

# It is a DIAGNOSTIC, so it must be invisible to both scheduler token spaces. A teardown row that
# moved either one would make hygiene an input to a completion decision.
td_sat_after="$(td_count '| satisfied')"
# The second clause is the anti-vacuity control the deleted token used to supply: the teardown
# DID write its row, so an unchanged satisfied count is evidence the row landed outside the
# milestone namespace rather than evidence that nothing was written at all.
if [ "$td_sat_before" = "$td_sat_after" ] && [ "$(td_count '| teardown |')" -gt 0 ]; then
  pass "(td2) the teardown row moves neither the close-out's satisfied read nor anything anchored on a milestone"
else fail "(td2) the teardown row moved a milestone-anchored count: '$td_sat_before' -> '$td_sat_after'"; fi

out="$(tdgate teardown 43)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(td_count '| teardown | absent |')" -eq 1 ]; then
  pass "(td3) a teardown with nothing to remove records 'absent' — a second outcome, not a repeat of the first"
else fail "(td3) rc=$rc, rows: $(grep 'teardown' "$TDPROG" 2>/dev/null)"; fi

p="$(wt_make 44)"
printf 'uncollected\n' > "$p/scratch.txt"
out="$(tdgate teardown 44)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(td_count '| teardown | kept |')" -eq 1 ] \
   && grep -qF 'is not clean' "$TDPROG"; then
  pass "(td4) a KEPT worktree records 'kept' carrying the reason the operator was just shown — still rc=0"
else fail "(td4) rc=$rc, rows: $(grep 'teardown' "$TDPROG" 2>/dev/null)"; fi

# ...and the report reads the LAST outcome, because a run that fixed a kept worktree carries both.
rm -f "$p/scratch.txt"
tdgate teardown 44 >/dev/null 2>&1
out="$(tdgate progress 44 --obligations)"
if grep -qE '^teardown: (removed|kept) ' <<<"$out"; then
  pass "(td5) the obligations report reads teardown's standing outcome, as its own line"
else fail "(td5) teardown was not reported separately: $out"; fi

# ONE ROW PER OUTCOME KIND, not one per call: the record is re-runnable and a bounded one is the
# readable one.
tdgate teardown 44 >/dev/null 2>&1
if [ "$(td_count '| teardown | ')" -le 4 ]; then
  pass "(td6) re-running teardown restates nothing — one row per outcome kind"
else fail "(td6) teardown rows accumulated: $(grep -c 'teardown' "$TDPROG")"; fi
rm -f "$TDPROG"

# #530 D-4: a SINGLE call that both removes one tree and keeps another records BOTH rows, `kept`
# last — so the one row `progress --obligations` surfaces (the most recent) is the state that
# still needs a human, not the one that already left.
p1="$(wt_make 45)"
p2="$(wt_make_second 45 b)"
printf 'uncollected\n' > "$p2/scratch.txt"
tdgate entry 45 >/dev/null 2>&1
out="$(tdgate teardown 45)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(td_count '| teardown | removed |')" -eq 1 ] \
   && [ "$(td_count '| teardown | kept |')" -eq 1 ] \
   && ! wt_registered "$p1" && wt_registered "$p2"; then
  pass "(td7) #530: a call that removes one tree and keeps another records both outcomes in one pass"
else fail "(td7) rc=$rc, rows: $(grep 'teardown' "$TDPROG" 2>/dev/null)"; fi

obl="$(tdgate progress 45 --obligations)"
if grep -qE '^teardown: kept ' <<<"$obl"; then
  pass "(td8) #530 D-4: 'kept' is the standing outcome when one call reaches both — the row an operator sees is the one still needing them"
else fail "(td8) expected 'kept' as the standing teardown row: $obl"; fi
rm -f "$p2/scratch.txt"
git -C "$WTREE" worktree remove --force "$p2" >/dev/null 2>&1
rm -f "$TDPROG"

# --- the entry sweep: qualification ------------------------------------------------------------
# One `entry` call decides every registered worktree at once, so the fixtures are set up together
# and the assertions read the same run's output. Issue 25's worktree above is the caller's own
# once we re-enter from inside it; the rest are the four qualification answers.
p26="$(wt_make 26)"; pr_fixture claude/acme-26 '[{"number":26,"state":"MERGED"}]'
p27="$(wt_make 27)"; pr_fixture claude/acme-27 '[{"number":27,"state":"OPEN"}]'
p28="$(wt_make 28)"; pr_fixture claude/acme-28 '[]'
p29="$(wt_make 29)"   # no fixture at all ⇒ the stub exits non-zero ⇒ a FAILED lookup
git -C "$WTREE" worktree add -q --no-track -b fix/not-a-lane-branch "$WREAL/wt-foreign" main 2>/dev/null
pr_fixture claude/acme-25 '[{"number":25,"state":"CLOSED"}]'

rm -f "$WPROG"
# Run it FROM INSIDE wt-25, which is what makes that worktree the caller's own for (wt15).
# The argument is 25 and not an unrelated number: since #611 an `entry` whose ticket disagrees
# with the lane branch its cwd is on is a refusal, so a mismatched pair here would never reach the
# sweep at all — every assertion below would red on a guard none of them are about.
out="$(wgate "$WREAL/wt-25" entry 25)"; rc=$?

if [ "$rc" -eq 0 ] && ! wt_registered "$p26" && grep -qF 'has no open PR' <<<"$out"; then
  pass "(wt9) the sweep removes a worktree whose PR is merged — PR state, never git branch --merged"
else fail "(wt9) merged-PR worktree survived the sweep, rc=$rc: $out"; fi

if wt_registered "$p27" && grep -qF 'still has an open PR' <<<"$out"; then
  pass "(wt10) a branch with an OPEN PR is kept, and said so"
else fail "(wt10) the sweep touched a live run's worktree: $out"; fi

if wt_registered "$p28" && grep -qF 'has no PR at all' <<<"$out"; then
  pass "(wt11) a branch with no PR at all is kept and reported (OR-1's reversible default)"
else fail "(wt11) the sweep guessed at a PR-less worktree: $out"; fi

# D-12, the one that must never be got wrong: a FAILED lookup is not a "no PR" answer. An
# implementation reading the stub's output without checking its exit status sees an empty
# string, parses it as no PRs, and — under a different default — could remove the worktree.
if wt_registered "$p29" && grep -qF 'could not list PRs for claude/acme-29' <<<"$out"; then
  pass "(wt12) a failed gh lookup removes nothing and names the branch it could not resolve"
else fail "(wt12) a gh outage was read as an answer: $out"; fi

# ...and none of that changed `entry`'s verdict. The audit-ledger predicate is the sole decider of
# whether a run may start; a tracker outage must not become a second reason it cannot.
if [ "$rc" -eq 0 ] && grep -q '| entry | ledger=' "$WPROG" 2>/dev/null; then
  pass "(wt13) the sweep cannot change entry's exit status or suppress its attestation"
else fail "(wt13) entry's own contract was affected by the sweep, rc=$rc: $out"; fi

# D-10, the blast radius. A branch that does not parse as `<prefix><key>` for this tracker is
# skipped with NO tracker lookup — the stub would have exited non-zero and printed a diagnostic
# naming it, so the absence of that line is the assertion.
if wt_registered "$WREAL/wt-foreign" \
   && ! grep -qF 'fix/not-a-lane-branch' <<<"$out"; then
  pass "(wt14) a non-lane branch is skipped without a PR lookup"
else fail "(wt14) the sweep considered a foreign branch: $out"; fi

# The caller's own worktree, whose PR fixture says CLOSED — it qualifies on every other test and
# is skipped anyway. The sweep is for runs that are OVER; the one you are standing in is not.
if wt_registered "$WREAL/wt-25"; then
  pass "(wt15) the sweep never removes the worktree it is running from, even when that PR is closed"
else fail "(wt15) the sweep deleted its own caller's checkout: $out"; fi

if wt_registered "$WTREE"; then
  pass "(wt16) the main checkout is never a sweep candidate"
else fail "(wt16) the sweep removed the main checkout: $out"; fi

# The preconditions are the SHARED half: a qualified worktree still has to be safe to remove.
p31="$(wt_make 31)"; pr_fixture claude/acme-31 '[{"number":31,"state":"MERGED"}]'
printf 'unsaved\n' > "$p31/scratch.txt"
out="$(wgate "$WTREE" entry 31)"; rc=$?
rm -f "$p31/scratch.txt"
if [ "$rc" -eq 0 ] && wt_registered "$p31" && grep -qF 'is not clean' <<<"$out"; then
  pass "(wt17) a qualified-but-unclean worktree is kept by the sweep too — one precondition set, two callers"
else fail "(wt17) the sweep bypassed the shared preconditions, rc=$rc: $out"; fi

# AC-10: `entry` sweeps and nothing else does. `claim` is the adjacent call and the one a reader
# would reach for. Probed under jira, where claim makes no tracker write at all and so needs no
# bot wrapper — and PAIRED with an `entry` on the SAME config and the SAME worktree, because
# "claim removed nothing" is satisfied by any config under which nothing was removable. The pair
# is what makes it a probe of claim rather than of the fixture.
CFG_JIRA_WT="$WREAL/config-jira-wt.json"
jq '.tracker.type = "jira" | .tracker.writes = false | .tracker.branchPrefix = "claude/"' \
  "$CFG" > "$CFG_JIRA_WT"
jwt() { # jwt <sub> <key>
  ( unset RUN_ID GH_BOT; cd "$WTREE" && CLAUDE_CODE_SESSION_ID="$WSID" SECOND_SHIFT_CONFIG="$CFG_JIRA_WT" \
    LEAN_PROGRESS_FILE="$WREAL/wt-jira-progress.md" GH="$WREAL/gh-wt-stub.sh" PR_FIXTURE_DIR="$WPR" \
    RUN_ID=wt-jira bash "$GATE" "$1" "$2" 2>&1 )
}
# `claim` is a build-role call and exits 2 without an entry attestation, so the attestation has
# to come FIRST — which is also why the candidate worktree is created after it rather than before.
rm -f "$WREAL/wt-jira-progress.md"
jwt entry ACME-32 >/dev/null 2>&1
pr_fixture claude/acme-32 '[{"number":32,"state":"MERGED"}]'
p32="$(wt_make 32)"
out="$(jwt claim ACME-32)"
if wt_registered "$p32"; then claim_kept=1; else claim_kept=0; fi
out2="$(jwt entry ACME-32)"
if [ "$claim_kept" -eq 1 ] && ! wt_registered "$p32"; then
  pass "(wt18) claim does not sweep, and the same config's entry does — the sweep is entry's alone"
else fail "(wt18) claim_kept=$claim_kept, still registered after entry=$(wt_registered "$p32" && echo yes || echo no): $out / $out2"; fi

# The main-checkout guard inside the removal itself, which the sweep's own skip hides. An
# operator who checked the lean branch out in the main checkout and ran teardown must be told,
# not have git's "is a main working tree" error surface as an unexplained failure.
git -C "$WTREE" checkout -q -b claude/acme-33
git -C "$WTREE" update-ref refs/remotes/origin/claude/acme-33 "$(git -C "$WTREE" rev-parse HEAD)"
out="$(wgate "$WTREE" teardown 33)"; rc=$?
git -C "$WTREE" checkout -q main
if [ "$rc" -eq 0 ] && wt_registered "$WTREE" && grep -qF 'it is the main checkout' <<<"$out"; then
  pass "(wt19) teardown refuses the main checkout by name, even when the lean branch is checked out there"
else fail "(wt19) expected a named refusal on the main checkout, rc=$rc: $out"; fi


# --- (ws) #647: the lane worktree INHERITS the checkout's Claude settings ------------------------
# A worktree receives tracked files only, and the operator's allowlist is gitignored — the fixture
# repo's `.gitignore` carries `.claude/` for exactly that reason, so these worktrees start with no
# settings the same way a real one does. A session launched in such a worktree has no allowlist at
# all and every tool call falls through to the harness's classifier; the observed shape is a session
# denied `git fetch`, `gh api` and its own first gate call, which still exits 0.
#
# One `entry` per fixture rather than one shared run, because the whole point is what a SECOND
# entry does differently from the first (ws3), and a single run cannot show that.
#
# `ws_wt` and not `wt_make` directly: `wt_make` swallows `git worktree add`'s stderr, so a fixture
# number already used by an earlier section produces NO worktree and every assertion below then
# reads a path that does not exist — which is indistinguishable from a seed that declined to run.
# Caught the first time this section was written, on `wt_make 40`. The registration is checked
# rather than assumed, so a future collision fails HERE instead of passing vacuously downstream.
ws_wt() { # ws_wt <issue> -> path, or a named failure
  local p; p="$(wt_make "$1")"
  wt_registered "$p" || fail "(ws-setup) fixture worktree claude/acme-$1 was not created — is that number already used by an earlier section?"
  printf '%s' "$p"
}
printf '{"permissions":{"allow":["Bash(git fetch:*)"]}}\n' > "$WTREE/.claude/settings.local.json"

p60="$(ws_wt 60)"; pr_fixture claude/acme-60 '[{"number":60,"state":"OPEN"}]'
# The premise, asserted rather than assumed: `git worktree add` did NOT bring the file along. If a
# future git ever did, every case below would pass while testing nothing.
if [ -e "$p60/.claude/settings.local.json" ]; then ws_pre=1; else ws_pre=0; fi
rm -f "$WPROG"
out="$(wgate "$WTREE" entry 60)"; rc=$?

if [ "$ws_pre" -eq 0 ] && [ "$rc" -eq 0 ] && [ -f "$p60/.claude/settings.local.json" ] \
   && cmp -s "$WTREE/.claude/settings.local.json" "$p60/.claude/settings.local.json"; then
  pass "(ws1) entry seeds the lane worktree with the checkout's .claude/settings.local.json, content-identical"
else fail "(ws1) pre=$ws_pre rc=$rc — the worktree did not inherit the allowlist: $out"; fi

# AC-2, both halves at once. A symlink would satisfy "the file is there" and satisfy `cmp` too, and
# would hand a lane session write access to the operator's real settings — so the inode's
# INDEPENDENCE is the assertion, not the file's presence. The `-f` conjunct keeps this from passing
# on a path that does not exist at all, which `! -L` alone is true for.
printf 'MUTATED-BY-THE-LANE\n' >> "$p60/.claude/settings.local.json" 2>/dev/null
if [ -f "$p60/.claude/settings.local.json" ] && [ ! -L "$p60/.claude/settings.local.json" ] \
   && grep -qF 'MUTATED-BY-THE-LANE' "$p60/.claude/settings.local.json" \
   && ! grep -qF 'MUTATED-BY-THE-LANE' "$WTREE/.claude/settings.local.json"; then
  pass "(ws2) the copy is a regular file, and a write inside the worktree cannot reach the origin checkout's file"
else fail "(ws2) the worktree's settings file is not independent of the checkout's: $(ls -l "$p60/.claude/settings.local.json" 2>&1)"; fi

# AC-3. The mutation above is the marker: a re-entry that reused the worktree and re-copied would
# erase it, and the operator's in-worktree edit with it.
out="$(wgate "$WTREE" entry 60)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'MUTATED-BY-THE-LANE' "$p60/.claude/settings.local.json" 2>/dev/null \
   && grep -qF 'is already present' <<<"$out"; then
  pass "(ws3) a re-entry reusing the worktree leaves an existing settings file alone, and says so"
else fail "(ws3) re-entry clobbered the worktree's own settings file, rc=$rc: $out"; fi

# AC-1's other half. A consumer who keeps no local settings has nothing to inherit, and must not be
# told they are missing something — the absence of any `settings:` line is the assertion, so a
# future diagnostic added on this path fails here rather than becoming noise on every clean run.
mv "$WTREE/.claude/settings.local.json" "$WREAL/ws-stash.json"
p61="$(ws_wt 61)"; pr_fixture claude/acme-61 '[{"number":61,"state":"OPEN"}]'
out="$(wgate "$WTREE" entry 61)"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$p61/.claude/settings.local.json" ] && ! grep -qF 'settings:' <<<"$out"; then
  pass "(ws4) a checkout with no settings of its own yields a worktree with none, silently and without error"
else fail "(ws4) rc=$rc, worktree file present=$([ -e "$p61/.claude/settings.local.json" ] && echo yes || echo no): $out"; fi
mv "$WREAL/ws-stash.json" "$WTREE/.claude/settings.local.json"

# D-4: an UNTRACKED `.claude/settings.json` is inherited too. In this fixture `.claude/` is ignored
# wholesale, so `settings.json` is exactly as invisible to the worktree as the local one — which is
# the case the ticket names, and the one a tracked settings.json never reaches.
printf '{"env":{"WS":"1"}}\n' > "$WTREE/.claude/settings.json"
p62="$(ws_wt 62)"; pr_fixture claude/acme-62 '[{"number":62,"state":"OPEN"}]'
out="$(wgate "$WTREE" entry 62)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$p62/.claude/settings.local.json" ] && [ -f "$p62/.claude/settings.json" ]; then
  pass "(ws5) both settings files are inherited — the local one and an untracked settings.json"
else fail "(ws5) rc=$rc — one of the two files did not land: $(ls "$p62/.claude" 2>&1)"; fi

# The Open Region's reversible default, from the direction that can actually be got wrong. A
# TRACKED settings.json is already in the worktree, and the rule that leaves it alone is
# "the destination exists", which asks git nothing. Simulated here by putting the file there first.
# The local file IS expected to land alongside it — without that conjunct this case would pass on a
# seed that did nothing at all.
p63="$(ws_wt 63)"; pr_fixture claude/acme-63 '[{"number":63,"state":"OPEN"}]'
mkdir -p "$p63/.claude"
printf '{"env":{"WS":"tracked"}}\n' > "$p63/.claude/settings.json"
out="$(wgate "$WTREE" entry 63)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF '"tracked"' "$p63/.claude/settings.json" \
   && [ -f "$p63/.claude/settings.local.json" ]; then
  pass "(ws6) a settings.json the worktree already carries — as a tracked one is — is passed over while its sibling still lands"
else fail "(ws6) the copy overwrote a file the worktree already had, rc=$rc: $out"; fi

# The dangling-symlink arm. `[ -e ]` alone is FALSE for a symlink whose target does not exist, so an
# implementation testing only `-e` would `cp` straight THROUGH it and write into whatever path the
# operator pointed it at — outside the worktree entirely. The settings.json conjunct is again the
# liveness half: the seed must have RUN on this worktree for the refusal to mean anything.
#
# #663: THE HARM ARM IS PLATFORM-BLIND, AND THE CANONICAL LANE IS THE BLIND SIDE. `[ ! -e <target> ]`
# asks whether the write happened, and on Linux it never does — GNU `cp` refuses to write through a
# dangling symlink on its own ("not writing through dangling symlink"), so the `-L` conjunct has no
# observable consequence there and the catalog's `lean-gate-settings-clobber-dangling` mutant
# SURVIVED the first ubuntu sweep to score this guard in ten days (run 33316017803, shard 6, serially
# re-verified). BSD `cp` follows the link and writes, which is why the same mutant dies locally —
# a guard that only fires on the developer's laptop.
#
# The arm added below is the gate's OWN WORDS, which are the thing the deleted conjunct actually
# controls: with `-L`, the destination is reported present and skipped; without it, the seed
# proceeds and reports either a copy or a failed copy. That is true on both platforms and does not
# rest on which `cp` is installed — so the case now kills the mutant where it is scored.
p64="$(ws_wt 64)"; pr_fixture claude/acme-64 '[{"number":64,"state":"OPEN"}]'
mkdir -p "$p64/.claude"
ln -s "$WREAL/ws-nonexistent-target.json" "$p64/.claude/settings.local.json"
out="$(wgate "$WTREE" entry 64)"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$WREAL/ws-nonexistent-target.json" ] \
   && grep -qF "settings: $p64/.claude/settings.local.json is already present" <<<"$out" \
   && [ -L "$p64/.claude/settings.local.json" ] && [ -f "$p64/.claude/settings.json" ]; then
  pass "(ws7) a destination that is a dangling symlink counts as present — the seed reports it skipped and writes nothing through it"
else fail "(ws7) the seed did not treat the dangling symlink as present, rc=$rc: $(ls -l "$p64/.claude" 2>&1) :: $(grep -F 'settings:' <<<"$out")"; fi

# AC-2 from the SOURCE side: `cp` dereferences, so what lands is a regular file even when the
# operator's own settings file is a symlink into a dotfiles repo. `cp -P` or `ln -s` would fail here.
mv "$WTREE/.claude/settings.local.json" "$WREAL/ws-real-settings.json"
ln -s "$WREAL/ws-real-settings.json" "$WTREE/.claude/settings.local.json"
p65="$(ws_wt 65)"; pr_fixture claude/acme-65 '[{"number":65,"state":"OPEN"}]'
out="$(wgate "$WTREE" entry 65)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$p65/.claude/settings.local.json" ] && [ ! -L "$p65/.claude/settings.local.json" ]; then
  pass "(ws8) a symlinked source is dereferenced — the worktree gets a regular file, never a link back out"
else fail "(ws8) rc=$rc: $(ls -l "$p65/.claude" 2>&1)"; fi

# The suite's own hygiene: every later section runs `entry` from this same checkout, and a settings
# file left here would print a `settings:` line into output those cases grep.
rm -f "$WTREE/.claude/settings.local.json" "$WTREE/.claude/settings.json" "$WREAL/ws-real-settings.json"

# ---- (ws9)/(ws10) #647 round 1, B1: the premise the eight cases above SHARE -------------------
# Every (ws) case runs in a fixture whose `.gitignore` carries `.claude/`, which encodes the
# operator's PERSONAL GLOBAL ignore rule as a repo rule. No consumer repo has that line, and this
# repo did not either until this change added one path of it — so all eight are green on a premise
# production does not satisfy, and not one of them can fail when the seed writes an UNIGNORED
# untracked file into a tree whose cleanliness `worktree_inflight` reads as "still carries work".
# Sharing a premise with the feature is exactly how a suite converges on green while the defect
# it is meant to cover stays live, so this needs a SECOND fixture repo rather than another case
# in the first one.
WNIG="$WREAL/wtree-noignore"
mkdir -p "$WNIG/.claude/audit"
git -C "$WNIG" init -q
git -C "$WNIG" config user.email t@example.invalid
git -C "$WNIG" config user.name t
git -C "$WNIG" symbolic-ref HEAD refs/heads/main
# HERMETICITY, and it is the whole case. `git check-ignore` consults the operator's GLOBAL ignore
# file as well as the repo's, and the machine this lane runs on carries
# `**/.claude/settings.local.json` there — which is exactly why the production repo looked ignored
# while carrying no rule of its own, and why round 1's defect needed an isolated probe to see. Left
# unpinned, this fixture inherits that rule, the seed copies, and both cases below measure the
# operator's home directory rather than the gate: green here, and a DIFFERENT path taken on a CI
# runner that has no such file. `/dev/null` is an empty excludes file, so only `$WNIG/.gitignore`
# counts.
git -C "$WNIG" config core.excludesFile /dev/null
# Ignore rules EXIST here — just not one covering the seed's destination. A repo with no
# `.gitignore` at all would leave "does this handle a rule-less repo" as a confound on the result.
printf 'node_modules/\n' > "$WNIG/.gitignore"
git -C "$WNIG" add -A >/dev/null 2>&1
git -C "$WNIG" commit -q -m "no-ignore fixture" >/dev/null 2>&1
git -C "$WNIG" update-ref refs/remotes/origin/main HEAD
printf '{"tool":"Bash"}\n' > "$WNIG/.claude/audit/$WSID.jsonl"
printf '{"permissions":{"allow":["Bash(git fetch:*)"]}}\n' > "$WNIG/.claude/settings.local.json"
nig_registered() { git -C "$WNIG" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $1"; }
p66="$WREAL/wt-66"
git -C "$WNIG" worktree add -q --no-track -b claude/acme-66 "$p66" main 2>/dev/null
git -C "$WNIG" update-ref refs/remotes/origin/claude/acme-66 "$(git -C "$WNIG" rev-parse claude/acme-66)"
# Registration checked, not assumed — same reason `ws_wt` checks it: an absent worktree makes both
# cases below pass vacuously, and "nothing was copied" is what (ws9) asserts.
nig_registered "$p66" || fail "(ws-setup) no-ignore fixture worktree claude/acme-66 was not created"

pr_fixture claude/acme-66 '[{"number":66,"state":"OPEN"}]'
rm -f "$WPROG"
out="$(wgate "$WNIG" entry 66)"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$p66/.claude/settings.local.json" ] \
   && grep -qF 'is not git-ignored' <<<"$out" && grep -qF 'Add this line to .gitignore' <<<"$out"; then
  pass "(ws9) where no ignore rule covers the destination, the seed declines by name and writes nothing"
else fail "(ws9) rc=$rc — the seed wrote an unignored file into the lane worktree, or declined silently: $out"; fi

# THE PROBE FROM ROUND 1, AS A CASE — seed, then sweep, and the worktree must still reap. If the
# seed had written an unignored file, `git status --porcelain` is non-empty, `worktree_inflight`
# answers 8 ("its tree is not clean"), and `worktree_destroy` KEEPS the worktree instead — the
# stray-worktree accumulation #530 and this very sweep exist to prevent, self-inflicted by the
# gate one call earlier and never recoverable, because every later entry re-reads the same file.
# Removing the check-ignore guard from `seed_lane_worktree_settings` reds this line.
pr_fixture claude/acme-66 '[{"number":66,"state":"CLOSED"}]'
rm -f "$WPROG"
out="$(wgate "$WNIG" entry 66)"; rc=$?
if [ "$rc" -eq 0 ] && ! nig_registered "$p66"; then
  pass "(ws10) the next entry's sweep still reaps a worktree the seed considered — the seed left the tree clean"
else fail "(ws10) rc=$rc — the worktree is still registered: the seed dirtied the tree the sweep reads: $out"; fi

# ---- (pc) #445: the producer stamps the generation its readers gate on ----------------------
# THE WRITER HALF of the capability contract. A merge-boundary arm bound to a capability reads
# this stamp off the run's own claim comment; a producer that stopped writing it would send every
# such arm inert — a weakened boundary that reads exactly as green as a strong one, which is why
# the writer needs its own kill criterion rather than only the reader's.
CFG_BOT="$WORK/config-bot.json"
sed -e 's/"tracker": { "branchPrefix"/"tracker": { "bot": { "enabled": true, "envVar": "GH_BOT" }, "branchPrefix"/' \
  "$CFG" > "$CFG_BOT"
CLAIM_SPOOL="$WORK/claim-spool.txt"
cat > "$WORK/claim-bot-stub.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for the gh bot wrapper across BOTH of claim's writes: the label swap (whose response
# body claim-issue.sh inspects for the claimed label) and the marker comment.
for a in "$@"; do
  case "$a" in body=@*) cat "${a#body=@}" >> "$CLAIM_SPOOL" ;; esac
done
case "$*" in
  *labels*) cat >/dev/null; printf '["in-progress"]\n' ;;
  *)        echo "https://example.invalid/issues/8#issuecomment-1" ;;
esac
EOF
chmod +x "$WORK/claim-bot-stub.sh"

CPCPROG="$WORK/progress-pc.md"
rm -f "$CPCPROG"; : > "$CLAIM_SPOOL"
mkdir -p "$TREE/.claude/audit"
printf '{"tool":"Bash"}\n' > "$TREE/.claude/audit/sess-pc-1.jsonl"
( unset RUN_ID; cd "$TREE" && CLAUDE_CODE_SESSION_ID=sess-pc-1 SECOND_SHIFT_CONFIG="$CFG_BOT" \
    LEAN_PROGRESS_FILE="$CPCPROG" bash "$GATE" entry 8 >/dev/null 2>&1 )
out="$( cd "$TREE" && RUN_ID=pc-run-1 CLAUDE_CODE_SESSION_ID=sess-pc-1 SECOND_SHIFT_CONFIG="$CFG_BOT" \
        LEAN_PROGRESS_FILE="$CPCPROG" GH_BOT="$WORK/claim-bot-stub.sh" CLAIM_SPOOL="$CLAIM_SPOOL" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" claim 8 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'stage: lean-claimed' "$CLAIM_SPOOL" 2>/dev/null \
   && grep -q 'capabilities: pr-marker' "$CLAIM_SPOOL" 2>/dev/null; then
  pass "(pc1) claim stamps this producer's capabilities onto the comment its readers gate on"
else fail "(pc1) expected a stamped claim comment, rc=$rc: $out / spool=$(cat "$CLAIM_SPOOL" 2>/dev/null)"; fi

# The verdict record carries the same stamp, with NO reader today (D-7). Shipped now so a later
# review-side arm finds it already present in older records instead of going permanently inert
# over their silence — which only holds if the writer is guarded from the day it lands.
out="$(yverdict sess-review-pc r-review-pc --pr 91 --verdict approve --rounds 1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^capabilities: pr-marker$' "$YVERDICT" 2>/dev/null; then
  pass "(pc2) the verdict record carries the producer's capability stamp (D-7)"
else fail "(pc2) expected a stamped verdict record, rc=$rc: $out / record=$(cat "$YVERDICT" 2>/dev/null)"; fi

# THE CLOSED VOCABULARY, driven rather than grepped. A producer stamping a token no reader binds
# to arms nothing and disarms everything bound to the token it replaced — silently, since the
# stamp is still present and still well-formed. So it is an environment error at the writer, and
# nothing is posted. A COPY of the real file with one literal changed: the guard runs on
# production bytes, and a hand-written model of it could not fail when those bytes change.
#
# The copy lives in a SANDBOX carrying the real siblings it sources, so what runs is the whole
# production file rather than a fragment that dies on a missing dependency and returns the same
# rc=2 for an unrelated reason. Driven through `verdict`, whose write path needs no helper
# outside that directory.
BADDIR="$WORK/gate-badcap"
mkdir -p "$BADDIR"
cp "$(dirname "$GATE")"/*.sh "$BADDIR"/
sed -e "s/^LEAN_PRODUCER_CAPABILITIES='pr-marker'\$/LEAN_PRODUCER_CAPABILITIES='not-a-capability'/" \
  "$GATE" > "$BADDIR/lean-gate.sh"
if ! grep -q "^LEAN_PRODUCER_CAPABILITIES='not-a-capability'\$" "$BADDIR/lean-gate.sh"; then
  fail "(pc3) the mutation did not apply — the case would assert nothing"
else
  rm -f "$YPROG"; { echo "# lean run — issue 11"; echo ""; echo "run_id: r-build-y"; echo "session_id: sess-build-y"; } > "$YPROG"
  attest_at "$YTREE" "$CFG" "$YPROG" 11
  rm -f "$YTREE/.claude/pipeline-state/11-review-run-id"
  cp "$YVERDICT" "$WORK/held-pc-verdict.md" 2>/dev/null
  out="$( unset RUN_ID; cd "$YTREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$YPROG" \
          CLAUDE_CODE_SESSION_ID=sess-review-pc3 RUN_ID=r-review-pc3 \
          bash "$BADDIR/lean-gate.sh" verdict 11 --pr 91 --verdict approve --rounds 1 2>&1 )"; rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'not in the closed capability vocabulary' <<<"$out" \
     && ! grep -q 'not-a-capability' "$YVERDICT" 2>/dev/null; then
    pass "(pc3) a producer token outside the closed vocabulary refuses instead of stamping it"
  else fail "(pc3) expected an environment error on an out-of-vocabulary token, rc=$rc: $out"; fi
  cp "$WORK/held-pc-verdict.md" "$YVERDICT" 2>/dev/null
fi

# ---- (pg) the CLOSE-OUT's SATISFIED READ, `progress --satisfied` ------------------------------
# #492 put the CONTINUATION PREDICATE here and #718 deleted it: (pg1)-(pg4) pinned the bare token's
# row set, and there is no longer a bare token or a caller for one. What survives is the narrow
# question the close-out asks, and every case below is about that.
PGPROG="$WORK/pg-progress.md"
pgprog() { # pgprog <args...>
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
    cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PGPROG" \
    bash "$GATE" progress 77 "$@" 2>&1 )
}

# The baseline every case below moves away from: one satisfied row and one attempt row, plus one
# of every other row shape this file writes — including a reason string that says both verbs in
# prose, which a looser pattern would count.
cat > "$PGPROG" <<'EOF'
# lean run — issue 77

run_id: r-pg
session_id: sess-pg

2026-01-01T00:00:00Z | entry | ledger=/x | lines=3 | telemetry=on | session=sess-pg
2026-01-01T00:00:01Z | session | sess-pg
2026-01-01T00:00:02Z | milestone-1 | satisfied
2026-01-01T00:00:03Z | milestone-2 | attempt | a reason that says satisfied and attempt | in prose
2026-01-01T00:00:04Z | milestone-2 | budget-exhausted | 3 attempts
2026-01-01T00:00:05Z | milestone-2 | skipped | consumer repo
2026-01-01T00:00:06Z | milestone-3 | armed | 2 rows
milestone-4 | verdict=approve | round=1
EOF

# D-8's narrowing. The close-out asks a different question from the build phase, and `attempt` is
# deliberately NOT part of it: a close-out that redded milestone 5 advanced the record but did not
# finish step 9, and crediting it would be the false `done` #492 exists to remove.
M5_BEFORE="$(pgprog --satisfied 5)"
printf '%s\n' '2026-01-01T00:04:00Z | milestone-5 | attempt | closing comment missing' >> "$PGPROG"
if [ "$M5_BEFORE" = "m5sat-v1:0" ] && [ "$(pgprog --satisfied 5)" = "$M5_BEFORE" ]; then
  pass "(pg5) --satisfied 5 ignores milestone 5's ATTEMPT rows, so a redded close-out is not credited"
else fail "(pg5) an attempt row moved the milestone-5-scoped token: $M5_BEFORE -> $(pgprog --satisfied 5)"; fi

printf '%s\n' '2026-01-01T00:05:00Z | milestone-5 | satisfied' >> "$PGPROG"
if [ "$(pgprog --satisfied 5)" != "$M5_BEFORE" ]; then
  pass "(pg6) --satisfied 5 moves on milestone 5's satisfied row — the close-out's credit signal"
else fail "(pg6) the milestone-5 satisfied row did not move its scoped token"; fi

# ...and it is SCOPED. A satisfied row on another milestone must not credit a close-out. The
# second half is the anti-vacuity control, and it is what the deleted broad token used to supply:
# without it the case would stay green against a reader that answered a constant.
M5_NOW="$(pgprog --satisfied 5)"
M4_BEFORE="$(pgprog --satisfied 4)"
printf '%s\n' '2026-01-01T00:06:00Z | milestone-4 | satisfied' >> "$PGPROG"
if [ "$(pgprog --satisfied 5)" = "$M5_NOW" ] && [ "$(pgprog --satisfied 4)" != "$M4_BEFORE" ]; then
  pass "(pg7) another milestone's satisfaction moves ITS OWN scoped token but not the milestone-5-scoped one"
else fail "(pg7) --satisfied 5 was not scoped to milestone 5: $M5_NOW -> $(pgprog --satisfied 5)"; fi

# Read-only, and specifically NOT a creator. Every other subcommand funnels through
# ensure_progress_file; this one must not, because the absence of the record is itself the answer
# the scheduler needs about a spawn that died before `entry`.
PG_ABSENT="$WORK/pg-absent.md"
rm -f "$PG_ABSENT"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PG_ABSENT" \
        bash "$GATE" progress 78 --satisfied 5 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "m5sat-v1:0" ] && [ ! -f "$PG_ABSENT" ]; then
  pass "(pg8) with no progress record at all the token is well-defined and the file is NOT created"
else fail "(pg8) expected m5sat-v1:0 with no file created, rc=$rc out='$out' exists=$([ -f "$PG_ABSENT" ] && echo yes || echo no)"; fi

# D-2: NOT in require_entry_attested's set — and for a sharper reason than teardown's. This reads
# the very file an attestation would live in, so gating it on that attestation would make the
# predicate unavailable in exactly the state the scheduler most needs an answer about. Without
# the control below, (pg8) would also pass against a gate that never enforced anything.
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PG_ABSENT" \
        bash "$GATE" 1 78 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no entry attestation' <<<"$out"; then
  pass "(pg9) the positive control: a build-role call on that same unattested run DOES refuse"
else fail "(pg9) the control did not refuse, so (pg8)'s ungated read proves nothing: rc=$rc: $out"; fi

# The token must never be mistaken for an ordinal — it is compared for equality and nothing else.
if grep -q '^m5sat-v1:' <<<"$M5_NOW"; then
  pass "(pg10) the token carries a generation prefix, so a caller reaching for a numeric compare has to notice it is not a number"
else fail "(pg10) the token has no generation prefix: '$M5_NOW'"; fi

out="$(pgprog --satisfied nope)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'takes a milestone number' <<<"$out"; then
  pass "(pg11) a non-numeric --satisfied is a usage refusal"
else fail "(pg11) expected rc=2 on a non-numeric --satisfied, got rc=$rc: $out"; fi

out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PGPROG" \
        bash "$GATE" delta 77 --satisfied 5 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "only meaningful on 'progress'" <<<"$out"; then
  pass "(pg12) --satisfied on a subcommand that ignores it is a refusal, not a silently dropped flag"
else fail "(pg12) --satisfied was accepted on 'delta', rc=$rc: $out"; fi

# #718 AC-7. The bare form was the continuation predicate, and deleting the predicate while leaving
# the subcommand answering SOMETHING would hand a stale caller a token nothing computes anymore —
# the silently-wrong direction. It refuses instead, and the refusal names what went away.
out="$(pgprog)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'unknown progress form' <<<"$out"; then
  pass "(pg13) bare 'progress <issue>' is a usage refusal naming the deleted predicate, not a default token"
else fail "(pg13) expected rc=2 with an 'unknown progress form' refusal, got rc=$rc: $out"; fi

# ---- (ac) #496: the milestone-4 failure taxonomy, the observe seam, and the config guard -----
# The per-arm behavior is asserted where each arm's fixture already lives — (j1)/(j2)/(u1)/(t*)/
# (x*)/(n*)/(fd*)/(ac-d*) above, each now keyed to its class. What is left, and what only a
# whole-function assertion can carry, is COMPLETENESS: a fifteenth site added without a class
# silently defaults to 1, which is exactly the collapse this ticket removes, and no behavioral
# case can red on an arm that does not exist yet.
#
# 20 -> 18 at #642: `m4/head-missing` and `m4/head-tree-diff` were deleted (both class 5) and the
# `reviewed_patch_id`-absent refusal that replaced them added one back (also class 5). The verdict
# ABSENCE site left this count entirely — it is `block_milestone` now, on the absent verb.
#
# 18 -> 20 at #708: the panel attestation added two, both on the armed path. The unnameable-family
# refusal is class 1 (the remedy is a spec edit in the build lane, and milestone 1 refuses it there
# too); the panel-omission refusal is class 5 (only another review round can produce a record that
# names the reviewer — no build action fixes it).
#
# 20 -> 14 at #720: SIX sites deleted, five class 5 (run_id, session_id and reviewed_patch_id key
# absence; the inferred and declared patch-stale arms) and one class 2 (patch identity
# uncomputable). Each re-asked a question lean-evidence.sh's arm_verdict/arm_freshness answers at
# the merge boundary on every consumer's PR, so a record this milestone waved through on those
# grounds could not reach a merge anyway. The class TWO count falls to one, which is the shape to
# watch: the sole remaining environment-class site is the armed render-identity one, so a future
# fail-open added on the unarmed path would show up here as a signature change and not just a total.
m4_calls="$(grep -c 'fail_milestone 4 "' "$GATE")"
m4_sig="$(grep 'fail_milestone 4 "' "$GATE" | sed -n 's/.*" \([0-9]\).*$/\1/p' | sort | tr -d '\n')"
if [ "$m4_calls" -eq 14 ] && [ "$m4_sig" = "11112555555566" ]; then
  pass "(ac1) all 14 milestone-4 failure sites carry an explicit class, in the documented 4x1 / 1x2 / 7x5 / 2x6 split"
else fail "(ac1) milestone-4 site mapping drifted: $m4_calls call(s), class signature '$m4_sig' (expected 14 / 11112555555566)"; fi

# THE ABSENT-VERB SITES, held to the same completeness bar (#642 AC-3). Every reason the ablation
# report adjudicates `unchanged` must reach block_milestone/block_obligation; a new one added as a
# fail_milestone silently re-charges the fix budget, and only a whole-file count can say so.
# TEN SITES over SIX points: `m5/identity-stamp` and `m5/verdict-reference:closing-comment` each
# have two arms (the jira and github close-outs; the fetch failure and the missing comment), and
# round 1 added the two `cmd_close_out` arms — m5/progress-current and m5/exit-artifacts:no-open-pr
# — that `cmd_5` had already re-verbed and close-out had not (8 -> 10).
# The literal-prefix `"[a-z]` is what excludes block_obligation's own `block_milestone 5 "$2"`.
#
# THIS COUNT IS THE INCLUSION DIRECTION AND NOTHING MORE. It was green across both of round 1's
# blocker sites, because a `fail_milestone` carrying one of the six predicates leaves it untouched.
# (ac1c) below is the half that can see that; neither case replaces the other.
m_block="$(grep -cE 'block_milestone [145] "[a-z]|block_obligation [a-z-]+ "' "$GATE")"
if [ "$m_block" -eq 10 ]; then
  pass "(ac1b) #642 AC-3: all 10 announcement-class refusal sites route to the absent verb, over the 6 points the ablation report adjudicates 'unchanged'"
else fail "(ac1b) absent-verb site count drifted: $m_block (expected 10) — $(grep -nE 'block_milestone [145] "[a-z]|block_obligation [a-z-]+ "' "$GATE")"; fi

# ---- (ac1c)/(ac1d) #642 AC-3, round 1: THE EXCLUSION DIRECTION -----------------------------
# (ac1b) above counts absent-verb sites and asserts a total. That is the INCLUSION direction, and
# it is blind by construction to the defect it was written for: two `fail_milestone 5` sites in
# `cmd_close_out` carried m5/progress-current and m5/exit-artifacts:no-open-pr reasons, which
# leaves the count at 8 and passes. A violation spelled in the OTHER verb is invisible to a
# guard that only counts the right one — so this case asserts the complement: no CHARGING-verb
# site's reason may classify into an announcement-class point.
#
# MEMBERSHIP IS DERIVED, never hand-listed. AC-3's wording is "every reason docs/gate-ablation.md
# adjudicates `unchanged`", so the set is read from the PRODUCTION adjudication table, and each
# reason is classified by the PRODUCTION predicate table under gate-ablation.awk's own rule
# (first match wins within a milestone). A seventh point adjudicated `unchanged` by a future
# corpus joins this guard with no edit here — and re-verbing one that leaves the set is likewise
# a one-file change. The `<issue>:<point>` override key form is stripped to its point.
#
# `$VAR`-ONLY REASONS ARE RESOLVED, to every literal `VAR="…"` assignment in the gate. The
# blocker's second site is `fail_milestone 5 "$LEAN_PR_ERROR"` — a guard reading source literals
# alone would have caught exactly half of it and reported a green on the other half.
#
# WHY A PREFIX SUFFICES. All six announcement predicates are `^`-anchored, so a reason's leading
# literal decides the question; truncating at the first unescaped `"` cannot hide a match that a
# fuller expansion would find. (ac1d) pins what the technique CANNOT reach.
#
# It also reaches a site NO fixture can drive: `cmd_close_out`'s progress-current red is
# unreachable from close-out's own flow (the 1..4 loop it sits behind appends the very satisfied
# rows it tests for), so the static classification is that arm's only possible guard. (kc1) below
# drives the reachable one behaviorally.
AC_ADJ="$HERE/../../../../tools/gate-ablation-adjudication.tsv"
AC_CLS="$HERE/../../../../tools/gate-ablation-classes.tsv"
if [ -r "$AC_ADJ" ] && [ -r "$AC_CLS" ]; then
  ac_scan="$(awk -F'\t' -v ADJ="$AC_ADJ" -v CLS="$AC_CLS" '
    FILENAME == ADJ {
      if ($0 !~ /^#/ && NF > 1 && $2 == "unchanged") { gp = $1; sub(/^[0-9]+:/, "", gp); ann[gp] = 1 }
      next
    }
    FILENAME == CLS {
      if ($0 !~ /^#/ && NF >= 5) { nc++; cms[nc] = $2; cpat[nc] = $4; cgp[nc] = $1 }
      next
    }
    # every literal VAR="…" assignment in the gate, for the $VAR-only reasons below
    {
      s = $0
      while (match(s, /[A-Z_][A-Z0-9_]*="/)) {
        nm = substr(s, RSTART, RLENGTH - 2); rest = substr(s, RSTART + RLENGTH); q = index(rest, "\"")
        if (q > 1) asg[nm] = asg[nm] SUBSEP substr(rest, 1, q - 1)
        s = substr(s, RSTART + RLENGTH)
      }
    }
    /fail_milestone [0-9]+ "|fail_obligation [a-z-]+ "/ { sl[++ns] = $0; sn[ns] = FNR }
    function classify(ms, reason,   i) {
      for (i = 1; i <= nc; i++) if (cms[i] == ms && reason ~ cpat[i]) return cgp[i]
      return ""
    }
    END {
      if (nc == 0) { print "INFRA\tthe predicate table parsed to zero rows"; exit }
      for (g in ann) nann++
      if (nann == 0) { print "INFRA\tthe adjudication table declared no `unchanged` point"; exit }
      printf "SET\t%s\n", nann
      for (i = 1; i <= ns; i++) {
        s = sl[i]
        if (match(s, /fail_milestone [0-9]+ "/)) { ms = substr(s, RSTART, RLENGTH); gsub(/[^0-9]/, "", ms) }
        else if (match(s, /fail_obligation [a-z-]+ "/)) ms = "5"
        else continue
        rest = substr(s, RSTART + RLENGTH); q = index(rest, "\"")
        arg = (q > 0) ? substr(rest, 1, q - 1) : rest
        # fail_obligation and block_obligation pass their CALLER s reason through; the caller is
        # the site, and it is matched on its own line.
        if (arg == "$1" || arg == "$2") continue
        k = 0
        if (arg ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) {
          nm = arg; gsub(/[${}]/, "", nm)
          if (nm in asg) k = split(asg[nm], cand, SUBSEP)
          if (k == 0) { printf "OPAQUE\t%s\t%s\t%s\n", sn[i], ms, arg; continue }
        } else if (arg ~ /^\$/ || arg == "") {
          printf "OPAQUE\t%s\t%s\t%s\n", sn[i], ms, arg; continue
        } else { k = 1; cand[1] = arg }
        for (j = 1; j <= k; j++) {
          if (cand[j] == "" || (i SUBSEP cand[j]) in seen) continue
          seen[i SUBSEP cand[j]] = 1
          gp = classify(ms, cand[j])
          if (gp != "" && (gp in ann)) printf "VIOLATION\t%s\t%s\t%s\t%s\n", sn[i], ms, gp, cand[j]
        }
      }
    }
  ' "$AC_ADJ" "$AC_CLS" "$GATE")"
  ac_infra="$(printf '%s\n' "$ac_scan" | grep -c '^INFRA')" || ac_infra=0
  ac_set="$(printf '%s\n' "$ac_scan" | awk -F'\t' '$1 == "SET" { print $2 }')"
  ac_viol="$(printf '%s\n' "$ac_scan" | grep '^VIOLATION')" || ac_viol=""
  ac_opaque="$(printf '%s\n' "$ac_scan" | grep '^OPAQUE')" || ac_opaque=""
  ac_nopaque="$(printf '%s\n' "$ac_scan" | grep -c '^OPAQUE')" || ac_nopaque=0

  # The set size is asserted so a table that stopped parsing cannot make the exclusion vacuous —
  # zero announcement points would let every charging site through, silently.
  if [ "$ac_infra" -eq 0 ] && [ "$ac_set" = "6" ] && [ -z "$ac_viol" ]; then
    pass "(ac1c) #642 AC-3: no charging-verb reason classifies into any of the 6 announcement-class points, over the production adjudication + predicate tables"
  else fail "(ac1c) exclusion direction breached (announcement points: ${ac_set:-none}, infra=$ac_infra) — a fail_milestone/fail_obligation site carries a reason the corpus adjudicates 'unchanged', so it charges the fix budget: $ac_viol"; fi

  # WHAT THE TECHNIQUE CANNOT REACH, pinned so a new blind spot has to be looked at rather than
  # inherited. A reason that is a function call, a parameter expansion, or a leading `$VAR` cannot
  # be prefix-classified — the six predicates are all `^`-anchored, and nothing here states the
  # anchor's text. All ten sit at milestones 1, 3 and 4; the assertion that NONE sits at milestone
  # 5 is the load-bearing half, because milestone 5 carries three of the six announcement points
  # and is where both round-1 blockers lived.
  ac_op5="$(printf '%s\n' "$ac_opaque" | awk -F'\t' '$3 == "5"' | wc -l | tr -d ' ')"
  if [ "$ac_nopaque" -eq 10 ] && [ "$ac_op5" -eq 0 ]; then
    pass "(ac1d) #642 AC-3: the 10 reasons (ac1c) cannot classify are pinned, and none is at milestone 5"
  else fail "(ac1d) the unclassifiable-reason set moved: $ac_nopaque (expected 10), $ac_op5 at milestone 5 (expected 0) — each needs a look before it is inherited: $ac_opaque"; fi
elif ! git -C "$HERE" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "  SKIPPED: (ac1c/ac1d) staged install cache — the ablation tables are repo-only, so the exclusion direction is asserted in the repo sweep and not here"
else
  fail "(ac1c/ac1d) the ablation adjudication/predicate tables are not beside this gate in a git checkout — AC-3's exclusion direction lost its only guard"
fi

# `all` PROPAGATES the class rather than laundering it into its own 1. Both halves of the pre-pass
# are driven: an integrity refusal, which must never read as needs-work one layer up, and an absent
# record. The m3 config is reused so a green pre-pass would be visible as the marker file — these
# cases must stop BEFORE milestone 3 either way.
rm -f "$MARKER"
seed_build_progress r-build-ac sess-build-ac
printf 'verdict=approve\nrun_id: r-build-ac\nsession_id: sess-review-ac\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree "a build-authored verdict"
out="$(gate_m3 all 7)"; rc=$?
if [ "$rc" -eq 6 ] && [ ! -e "$MARKER" ] && grep -q "BUILD run's identity" <<<"$out"; then
  pass "(ac2) 'all' propagates a milestone-4 integrity refusal as 6 — it is not laundered into the pre-pass's generic 1"
else fail "(ac2) expected rc=6 from 'all' with no marker, got rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi

reset_progress
rm -f "$MARKER"
mv "$VERDICT" "$WORK/held-verdict-ac.md"
out="$(gate_m3 all 7)"; rc=$?
mv "$WORK/held-verdict-ac.md" "$VERDICT"
if [ "$rc" -eq 5 ] && [ ! -e "$MARKER" ]; then
  pass "(ac3) 'all' propagates an absent verdict record as 5 — the scheduler learns the review half failed, not that a fix did"
else fail "(ac3) expected rc=5 from 'all', got rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi

# THE OBSERVE SEAM. Records nothing, and still classifies: an evaluation that answered a different
# question under observation would make the scheduler's read worthless.
reset_progress
write_review_verdict needs-work
obs_before="$(count_in_progress '| milestone-4 |')"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 4 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(count_in_progress '| milestone-4 |')" -eq "$obs_before" ] \
   && grep -q 'reads verdict=needs-work' <<<"$out"; then
  pass "(ac4) the observe seam classifies exactly as the recording path and appends no milestone-4 line"
else fail "(ac4) expected rc=1 with an unmoved counter, got rc=$rc lines $obs_before -> $(count_in_progress '| milestone-4 |'): $out"; fi

# The control for (ac4): the SAME evaluation through the recording path DOES append. Without it,
# (ac4) would pass against a gate whose milestone 4 had stopped recording altogether.
gate 4 7 >/dev/null 2>&1
if [ "$(count_in_progress '| milestone-4 | attempt |')" -eq 1 ]; then
  pass "(ac5) ...and the recording path still appends its attempt line, so (ac4) measured the seam, not a dead writer"
else fail "(ac5) the recording path appended no attempt line — (ac4) proves nothing: $(cat "$PROG")"; fi

# BUDGET EXHAUSTION SURVIVES OBSERVATION. `PRECHECK` returned a flat 1 before the budget compare,
# so a scheduler reading through it could not tell "spent" from "failed once" — and the whole
# point of the seam is that the scheduler reads through it. The budget is spent by the RECORDING
# path (observe must not be able to spend one), then read.
# #642: driven by a PRESENT, keyless record — milestone 4's absence no longer charges the budget
# (AC-3), so it can no longer exhaust one. The record is restored afterwards.
reset_progress
mv "$VERDICT" "$WORK/held-verdict-ac2.md"
printf 'verdict=approve\n' > "$VERDICT"; commit_tree "a keyless record, to spend the budget"
for _ in 1 2 3 4; do gate 4 7 >/dev/null 2>&1; done
obs_lines="$(count_in_progress '| milestone-4 |')"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 4 7 2>&1 )"; rc=$?
mv "$WORK/held-verdict-ac2.md" "$VERDICT"
if [ "$rc" -eq 4 ] && [ "$(count_in_progress '| milestone-4 |')" -eq "$obs_lines" ]; then
  pass "(ac6) an exhausted budget is reported through the observe seam as 4, with no line written"
else fail "(ac6) expected rc=4 with an unmoved counter, got rc=$rc lines $obs_lines -> $(count_in_progress '| milestone-4 |'): $out"; fi

# THE CONFIG GUARD. Absent is legal and resolves the documented defaults; present-but-unparseable
# is a refusal, because the defaults are not neutral — `.tracker.type` falls back to `github`,
# whose intake arm attests more than jira's, so a corrupt file would pick a policy in silence.
CFG_CORRUPT="$WORK/config-corrupt.json"
printf '{ "tracker": { "type": "jira", }\n' > "$CFG_CORRUPT"
jq empty "$CFG_CORRUPT" >/dev/null 2>&1 \
  && fail "(ac7-fixture) the corrupt config parses, so (ac7) would assert nothing"
reset_progress
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_CORRUPT" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'not parseable JSON' <<<"$out"; then
  pass "(ac7) a config that exists but does not parse is a refusal, not a silent fall-through to the defaults"
else fail "(ac7) expected rc=2 naming the parse failure, got rc=$rc: $out"; fi

# ...and the other half, which is what keeps the guard from being a fail-closed-on-everything
# regression: NO config at all is the ordinary un-onboarded consumer, and every default applies.
# The remote ref is the fixture that absence needs and presence did not: with no config there is
# no `tracker.branchPrefix`, so the namespace is inferred from remote branches, and a fixture repo
# with none refuses for that unrelated reason. One work-shaped remote branch supplies the vote —
# which is the state the resolver was built for, not a way around it.
git -C "$TREE" update-ref refs/remotes/origin/claude/acme-7 HEAD
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$WORK/no-such-config.json" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(ac8) an ABSENT config still resolves the shipped defaults — the guard fails closed on corruption only"
else fail "(ac8) an absent config was refused, got rc=$rc: $out"; fi

# ---- (if) #497: THE IN-FLIGHT PAIR — a begun-and-never-concluded evaluation leaves a trace -----
# The defect these cases guard is an ABSENCE: every other row this gate writes is appended after
# an evaluation RETURNS, so a process killed mid-run left a record byte-identical to one where the
# milestone was never invoked. (if5) is the only case in this file that produces the real trigger
# — a live gate process, SIGKILLed mid-body — and it is what the rest are calibrated against.
MARK497="$WORK/m497-marker"
CFG_497="$WORK/config-497.json"
jq --arg m "$MARK497" '.commands.acme.test = ("touch " + ($m | @sh))' "$CFG" > "$CFG_497"
gate_497() {
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
    # shellcheck disable=SC2030,SC2031  # subshell-local is the point, exactly as in gate().
    cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_497" LEAN_PROGRESS_FILE="$PROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}

reset_progress
rm -f "$MARK497"
out="$(gate_497 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && [ -e "$MARK497" ] \
   && [ "$(count_in_progress '| milestone-3 | started |')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-3 | concluded | rc=0')" -eq 1 ]; then
  pass "(if1) a completed evaluation writes started BEFORE the body and concluded with its rc"
else fail "(if1) expected rc=0 + marker + one started/one concluded rc=0, got rc=$rc marker=$([ -e "$MARK497" ] && echo present || echo absent) started=$(count_in_progress '| milestone-3 | started |') concluded=$(count_in_progress '| milestone-3 | concluded | rc=0'): $out"; fi

# The payload is the BODY's exit code, not a constant. A `concluded` line that always said rc=0
# would close every row and still lie about what happened.
reset_progress
cp "$SPEC" "$WORK/held-spec-if.md"
printf '# spec\n\nno AC token here\n' > "$SPEC"
gate 1 7 >/dev/null 2>&1; rc=$?
cp "$WORK/held-spec-if.md" "$SPEC"
if [ "$rc" -eq 1 ] && [ "$(count_in_progress '| milestone-1 | concluded | rc=1')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-1 | concluded | rc=0')" -eq 0 ]; then
  pass "(if2) the concluded payload carries the body's real rc, not a constant"
else fail "(if2) expected one 'concluded | rc=1' and no rc=0, got rc=$rc: $(grep 'concluded' "$PROG" | tr '\n' ' ')"; fi

# THE SOUNDNESS CASE, and the reason the conclusion is its own verb rather than the `satisfied`
# line closing the `started` one. append_satisfied is idempotent by construction, and CLAUDE.md
# mandates a `bash G all` before build-lean's close-out step — so under the issue's own sketch
# every honest run would end its record with a phantom unclosed row. Three passing evaluations of
# one milestone: three started, three concluded, still exactly one satisfied.
reset_progress
gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1
if [ "$(count_in_progress '| milestone-1 | started |')" -eq 3 ] \
   && [ "$(count_in_progress '| milestone-1 | concluded |')" -eq 3 ] \
   && [ "$(count_in_progress '| milestone-1 | satisfied')" -eq 1 ]; then
  pass "(if3) concluded is NOT idempotent: re-evaluating a satisfied milestone still closes its row"
else fail "(if3) expected 3/3/1, got started=$(count_in_progress '| milestone-1 | started |') concluded=$(count_in_progress '| milestone-1 | concluded |') satisfied=$(count_in_progress '| milestone-1 | satisfied')"; fi

# ...and with every row closed, a resuming session is told nothing. The negative control for
# (if6): a notice on an honest run would be noise the operator learns to ignore.
out="$(gate 1 7)"
if ! grep -q 'never concluded' <<<"$out"; then
  pass "(if4) an honest run announces nothing — no unconcluded row exists to report"
else fail "(if4) an honest re-run reported an interruption: $out"; fi

# THE TRIGGER, for real. A configured lane that blocks, then SIGKILL on the gate's PROCESS GROUP
# — not its PID: `kill -9` on the gate alone leaves the lane child running, and this repo has
# already had an orphaned fixture from a killed sweep red an unrelated suite indefinitely. `set -m`
# is what puts the background job in its own group so the negative PID below addresses all of it.
# The lane self-terminates on a short bound rather than sleeping unbounded, so a kill that somehow
# misses cannot leave this suite waiting on a process forever.
CFG_KILL="$WORK/config-497-kill.json"
jq '.commands.acme.test = "sleep 20"' "$CFG" > "$CFG_KILL"
reset_progress
m3_before="$(count_in_progress '| milestone-3 |')"
set -m
( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
  # shellcheck disable=SC2030,SC2031  # subshell-local is the point, exactly as in gate().
  cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_KILL" LEAN_PROGRESS_FILE="$PROG" \
  bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 >/dev/null 2>&1 ) &
kill_pgid=$!
set +m
waited=0
while [ "$(count_in_progress '| milestone-3 | started |')" -eq 0 ] && [ "$waited" -lt 150 ]; do
  sleep 0.1; waited=$((waited + 1))
done
kill -9 -"$kill_pgid" 2>/dev/null
wait "$kill_pgid" 2>/dev/null
reaped=0
while kill -0 -"$kill_pgid" 2>/dev/null && [ "$reaped" -lt 50 ]; do sleep 0.1; reaped=$((reaped + 1)); done
if [ "$m3_before" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-3 | started |')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-3 | concluded |')" -eq 0 ]; then
  pass "(if5) a SIGKILLed evaluation leaves started with NO concluded — distinguishable from one that never ran"
else fail "(if5) expected 0 rows before / 1 started / 0 concluded, got $m3_before / $(count_in_progress '| milestone-3 | started |') / $(count_in_progress '| milestone-3 | concluded |')"; fi
# #566 SIMPLIFIED THIS BACK TO A STATEMENT ABOUT THE GATE'S OWN GROUP. Between #539 and #566 it
# could not be one: milestone 3 spawned a runner that the escape path deliberately put in its own
# SESSION, so the group kill above legitimately left it alive and the case had to reap the
# recorded runner explicitly before it could claim anything. There is no runner and no record
# now — milestone 3's evaluation is a child of this process group like every other milestone's —
# so the group kill is once again the whole story, and the reap loop it needed is deleted rather
# than left iterating over a glob that can no longer match.
#
# THIS IS THE CASE THAT PAYS FOR AC-1's DELETION. If milestone 3 ever detaches again, the sweep it
# spawned survives this kill and the wait below times out.
reaped=0
while kill -0 -"$kill_pgid" 2>/dev/null && [ "$reaped" -lt 50 ]; do sleep 0.1; reaped=$((reaped + 1)); done
if ! kill -0 -"$kill_pgid" 2>/dev/null; then
  pass "(if5b) #566 AC-1: killing the gate's own process group leaves no lane child running"
else fail "(if5b) process group $kill_pgid still has a live member after the group kill — did milestone 3 detach?"; fi

# The milestone the run never reached carries NEITHER row. Without this (if5) would pass against a
# gate that wrote `started` for every milestone on every call — the two states this ticket exists
# to separate would still be one state, just spelled differently.
if [ "$(count_in_progress '| milestone-2 | started |')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-2 | concluded |')" -eq 0 ]; then
  pass "(if5c) a milestone that was never invoked carries neither row"
else fail "(if5c) an uninvoked milestone-2 has rows: $(grep 'milestone-2' "$PROG" | tr '\n' ' ')"; fi

# ANNOUNCE, NEVER REFUSE (D-4). The interrupted milestone is precisely the one the resuming
# session must be able to re-run, so the next call reports the unconcluded row AND runs the body.
rm -f "$MARK497"
out="$(gate_497 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && [ -e "$MARK497" ] \
   && grep -q '1 earlier evaluation(s) began and never concluded (interrupted 1/5)' <<<"$out"; then
  pass "(if6) the next evaluation announces the unconcluded row and still runs the body"
else fail "(if6) expected rc=0 + marker + the interrupted notice, got rc=$rc marker=$([ -e "$MARK497" ] && echo present || echo absent): $out"; fi

# THE BUDGET (D-2/D-7). Seeded from the REAL writer's line — duplicating what append_started
# produced above, rather than hand-spelling a shape that would keep passing after the writer moved.
# FIVE unconcluded rows, and the sixth call refuses: no body, no new started row, rc=4.
#
# Five, not eight, since #566: milestone 3 no longer carries a larger interrupted budget of its
# own, because the detached runner that justified one is gone and the inline evaluation is exactly
# as exposed to a turn boundary as every other milestone's. Seeding the bound EXACTLY is what
# makes this case discriminate — at eight it would red under a 5-, 6- or 7-bound alike, and assert
# nothing (ib2) does not already assert.
reset_progress
rm -f "$MARK497"
gate_497 3 7 >/dev/null 2>&1
started_line="$(grep -F '| milestone-3 | started |' "$PROG" | head -n1)"
[ -n "$started_line" ] && [ "$(count_in_progress '| milestone-3 | concluded |')" -eq 1 ] \
  || fail "(if7-fixture) no closed pair to seed from — the budget cases below would assert nothing"
for _ in 1 2 3 4 5; do printf '%s\n' "$started_line" >> "$PROG"; done
rm -f "$MARK497"
out="$(gate_497 3 7)"; rc=$?
if [ "$rc" -eq 4 ] && [ ! -e "$MARK497" ] \
   && [ "$(count_in_progress '| milestone-3 | interrupted-exhausted | 5 unconcluded')" -eq 1 ] \
   && [ "$(count_in_progress '| milestone-3 | started |')" -eq 6 ]; then
  pass "(if7) the 6th evaluation past 5 unconcluded rows returns 4, records the exhaustion and never runs the body"
else fail "(if7) expected rc=4 / no marker / one 'interrupted-exhausted | 5 unconcluded' / 6 started, got rc=$rc marker=$([ -e "$MARK497" ] && echo present || echo absent) exh=$(count_in_progress '| milestone-3 | interrupted-exhausted |') started=$(count_in_progress '| milestone-3 | started |'): $out"; fi

# The number it reports is the unconcluded count it REFUSED ON, not a count of the lines it wrote
# itself — the (c7) defect one level down. At or past the cap the verdict is already 4 either way,
# so only the record can catch a counter that swept up its own exhaustion lines.
gate_497 3 7 >/dev/null 2>&1
if [ "$(count_in_progress '| milestone-3 | interrupted-exhausted | 5 unconcluded')" -eq 2 ]; then
  pass "(if7b) the exhaustion record counts unconcluded ROWS, not the exhaustion lines it wrote itself"
else fail "(if7b) expected two 'interrupted-exhausted | 5 unconcluded' lines, got: $(grep 'interrupted-exhausted' "$PROG" | tr '\n' ' ')"; fi

# D-8: the new verbs are invisible to every existing counter. `interrupted-exhausted` must not
# carry the `budget-exhausted` substring (c2) reads, nor the `absent-exhausted` one (c5) reads,
# and neither half of the pair may look like an `attempt` or an `absent` line.
if [ "$(count_in_progress 'budget-exhausted')" -eq 0 ] \
   && [ "$(count_in_progress 'absent-exhausted')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-3 | attempt |')" -eq 0 ] \
   && [ "$(count_in_progress '| milestone-3 | absent |')" -eq 0 ]; then
  pass "(if8) started/concluded/interrupted-exhausted inflate no existing counter"
else fail "(if8) a new verb leaked into an existing counter: $(cat "$PROG")"; fi

# D-3: and NOT into the `satisfied` row set either. The reader that space fed was the scheduler's
# continuation predicate, deleted in #718; the row-set property outlived it, because the close-out's
# `--satisfied` read and the obligations report both anchor on `| milestone-<n> |` too.
# READ FROM THE FILE, not through a token: the token that used to answer this is the deleted one.
reset_progress
gate 1 7 >/dev/null 2>&1
sat_before="$(count_in_progress '| satisfied')"
gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1; gate 1 7 >/dev/null 2>&1
sat_after="$(count_in_progress '| satisfied')"
if [ "$sat_before" = "$sat_after" ] \
   && [ "$(count_in_progress '| milestone-1 | started |')" -eq 4 ]; then
  pass "(if9) a churn of started/concluded rows adds no satisfied row"
else fail "(if9) the satisfied count moved '$sat_before' -> '$sat_after' over $(count_in_progress '| milestone-1 | started |') started rows"; fi

# THE OBSERVE SEAM. #496 promoted it to a SCHEDULER read — orchestrate-lean.sh runs
# `LEAN_GATE_OBSERVE=1 bash G 4 <issue>` at top level, which the dispatch routes through
# run_milestone — so the pair must be suppressed there or every round of every lean run has the
# scheduler writing build-role rows. The `all` pre-pass bypasses run_milestone by construction;
# this call does not, which is why it is the one asserted.
reset_progress
obs_before="$(count_in_progress '| milestone-1 |')"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_in_progress '| milestone-1 |')" -eq "$obs_before" ]; then
  pass "(if10) a top-level observed evaluation writes neither half of the pair"
else fail "(if10) expected rc=0 with an unmoved counter, got rc=$rc lines $obs_before -> $(count_in_progress '| milestone-1 |'): $out"; fi

# ...and it PREDICTS the budget rather than reporting a pass it cannot deliver — the (ac6) shape,
# one budget over. Seeded exactly as (if7) is, from the writer's own line.
gate 1 7 >/dev/null 2>&1
started_line="$(grep -F '| milestone-1 | started |' "$PROG" | head -n1)"
for _ in 1 2 3 4 5; do printf '%s\n' "$started_line" >> "$PROG"; done
obs_before="$(count_in_progress '| milestone-1 |')"
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_GATE_OBSERVE=1 \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 4 ] && [ "$(count_in_progress '| milestone-1 |')" -eq "$obs_before" ]; then
  pass "(if11) a spent interrupted budget is reported through the observe seam as 4, with no line written"
else fail "(if11) expected rc=4 with an unmoved counter, got rc=$rc lines $obs_before -> $(count_in_progress '| milestone-1 |'): $out"; fi

# The usage error still writes nothing. `*)` in the dispatch case routes every unknown subcommand
# through run_milestone, so a wrapper that recorded before validating would stamp
# `| milestone-9 | started |` on its way to exit 2 — and, on a fresh run, create the progress file
# the entry precondition exists to find absent.
reset_progress
before_all="$(count_in_progress '| milestone-')"
out="$(gate 9 7)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(count_in_progress '| milestone-')" -eq "$before_all" ]; then
  pass "(if12) an unknown subcommand still exits 2 having written no milestone row"
else fail "(if12) expected rc=2 with an unmoved record, got rc=$rc lines $before_all -> $(count_in_progress '| milestone-'): $out"; fi

# ---- (st) #515: the staleness predicate, against a REAL remote and a REAL fetch ---------------
# Its own fixture, not the shared $TREE: this block pushes commits to an origin and moves a work
# branch, and doing that in the tree every case above shares is how a later case starts failing
# for a reason its own body cannot show. It is also the only block in this file with a real
# `git remote` — the base arm's whole subject is a range against origin/<base>, and $TREE's
# `update-ref refs/remotes/origin/main` stand-in cannot be fetched into.
#
# THE FETCH IS WHAT MAKES (st2) NON-VACUOUS. Base commits are pushed to the bare origin and the
# work tree NEVER fetches them by hand — so a build of the arm that dropped its own `git fetch`
# would read a remote-tracking ref frozen at the branch point, answer "nothing moved", and fail
# this case. That is the exact stale-ref reading D-5 exists to refuse.
STW="$WORK/staleness"
SORIGIN="$STW/origin.git"
STREE="$STW/tree"
SPUSH="$STW/push"          # a second clone, used to land "someone else's" commits on the base
mkdir -p "$STW"
git init -q --bare "$SORIGIN" >/dev/null 2>&1
git -C "$SORIGIN" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
st_git() { git -C "$1" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "${@:2}"; }

git init -q "$STREE" >/dev/null 2>&1
git -C "$STREE" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
printf 'base\n' > "$STREE/shared.txt"
printf 'base\n' > "$STREE/untouched.txt"
st_git "$STREE" add -A >/dev/null 2>&1
st_git "$STREE" commit -q -m "base" >/dev/null 2>&1
git -C "$STREE" remote add origin "$SORIGIN" >/dev/null 2>&1
git -C "$STREE" push -q origin main >/dev/null 2>&1

# The work branch: it edits `shared.txt` and a file of its own. Created as a REF, with no
# worktree — the subcommand resolves `refs/heads/<branch>` rather than HEAD precisely so it can
# answer before the lane's worktree exists.
st_git "$STREE" checkout -q -b claude/acme-7 >/dev/null 2>&1
printf 'branch edit\n' >> "$STREE/shared.txt"
printf 'branch only\n' > "$STREE/branch-only.txt"
st_git "$STREE" add -A >/dev/null 2>&1
st_git "$STREE" commit -q -m "branch work" >/dev/null 2>&1
st_git "$STREE" checkout -q main >/dev/null 2>&1

# "Someone else" landing on the base, through a clone that pushes — so $STREE learns about it
# only by fetching.
git clone -q "$SORIGIN" "$SPUSH" >/dev/null 2>&1
push_base() { # push_base <file> <message>
  printf '%s\n' "$2" >> "$SPUSH/$1"
  st_git "$SPUSH" add -A >/dev/null 2>&1
  st_git "$SPUSH" commit -q -m "$2" >/dev/null 2>&1
  st_git "$SPUSH" push -q origin main >/dev/null 2>&1
}

ST_CFG="$STW/config.json"
cat > "$ST_CFG" <<'EOF'
{
  "tracker": { "type": "github", "branchPrefix": "claude/acme-" },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" }
}
EOF
ST_CFG_JIRA="$STW/config-jira.json"
cat > "$ST_CFG_JIRA" <<'EOF'
{
  "tracker": { "type": "jira", "branchPrefix": "claude/", "keyPattern": "ACME-[0-9]+" },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" }
}
EOF

# The tracker stub answers ONE question and records that it was asked. `ST_STATE` picks the
# answer; `ST_GH_FAIL` makes the read itself fail, which is a different fact from `CLOSED` and
# must not collapse into it.
mkdir -p "$STW/bin"
cat > "$STW/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$ST_GH_LOG"
[ -n "${ST_GH_FAIL:-}" ] && exit 1
printf '%s\n' "${ST_STATE:-OPEN}"
SH
chmod +x "$STW/bin/gh"
ST_GH_LOG="$STW/gh.log"
: > "$ST_GH_LOG"

# NO LEAN_PROGRESS_FILE override, deliberately: (st15) asserts the subcommand creates no progress
# file at the path the gate resolves on its own, which an override would move out from under it.
# NO entry attestation is ever recorded in this block either — (st15) also asserts that this
# subcommand is reachable without one, and every case above it silently depends on that being true.
stgate() { # stgate <config> <args...>
  local cfg="$1"; shift
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
    cd "$STREE" && PATH="$STW/bin:$PATH" GH="$STW/bin/gh" ST_GH_LOG="$ST_GH_LOG" \
      ST_STATE="${ST_STATE:-OPEN}" ST_GH_FAIL="${ST_GH_FAIL:-}" \
      SECOND_SHIFT_CONFIG="$cfg" bash "$GATE" staleness "$@" 2>&1 )
}

out="$(stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'ticket arm clean' <<<"$out" \
   && grep -q 'has not moved since the branch point' <<<"$out"; then
  pass "(st1) an open ticket on an unmoved base is clean, with both arms reporting"
else fail "(st1) expected rc=0 with both arms clean, got rc=$rc: $out"; fi

push_base untouched.txt "an unrelated change on the base"
out="$(stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'into no file this branch touches' <<<"$out"; then
  pass "(st2) a base that MOVED but into no shared file is clean — bare advancement is not the trigger"
else fail "(st2) expected rc=0 on a non-overlapping advance, got rc=$rc: $out"; fi

# The discriminator for (st2): the same moved base, now touching the one file the branch also
# edits. Without this pair, (st2) would pass just as well against an arm that never fires at all.
push_base shared.txt "a change to the file the branch is editing"
out="$(stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 7 ] && grep -q 'BASE ARM FIRED' <<<"$out" && grep -q 'shared.txt' <<<"$out"; then
  pass "(st3) a base that moved INTO a file this branch touches exits 7 and names the overlapping path"
else fail "(st3) expected rc=7 naming shared.txt, got rc=$rc: $out"; fi

if ! grep -q 'untouched.txt' <<<"$out" && ! grep -q 'branch-only.txt' <<<"$out"; then
  pass "(st4) the report is the INTERSECTION — neither the base-only nor the branch-only file is listed"
else fail "(st4) a non-overlapping file was reported as overlap: $out"; fi

if grep -q 'no exclusion list' <<<"$out"; then
  pass "(st5) the exit names its known false-positive class (OR-1), so an operator recognizes one in a single read"
else fail "(st5) the overlap report did not name the false-positive class: $out"; fi

out="$(stgate "$ST_CFG" 7 --arm ticket)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'BASE ARM FIRED' <<<"$out" && grep -q 'ticket arm clean' <<<"$out"; then
  pass "(st6) --arm ticket skips the base arm — scored against a base that is currently FIRING, so the skip is a measurement"
else fail "(st6) --arm ticket did not skip a firing base arm, rc=$rc: $out"; fi

# The assignment stays INSIDE the substitution. `ST_STATE=CLOSED out="$(…)"` would be two
# assignments rather than a command prefix, so the value would persist for every case below —
# which is how (st13) first failed as a closed ticket it never asked for.
out="$(ST_STATE=CLOSED stgate "$ST_CFG" 7 --arm base)"; rc=$?
if [ "$rc" -eq 7 ] && ! grep -q 'TICKET ARM FIRED' <<<"$out" && grep -q 'BASE ARM FIRED' <<<"$out"; then
  pass "(st7) --arm base skips the ticket arm — scored against a ticket that is CLOSED, so this skip is a measurement too"
else fail "(st7) --arm base did not skip a closed ticket, rc=$rc: $out"; fi

out="$(ST_STATE=CLOSED stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 7 ] && grep -q 'TICKET ARM FIRED' <<<"$out" && grep -q 'CLOSED' <<<"$out"; then
  pass "(st8) a closed ticket exits 7 on the ticket arm"
else fail "(st8) expected rc=7 from the ticket arm, got rc=$rc: $out"; fi

# D-7 in the one direction that matters: `.state` is CLOSED for `not_planned` too, and the
# motivating ticket closed exactly that way. Reading `.stateReason` would have missed it — so the
# stub is asserted to have been asked for `state` and nothing else.
if grep -q -- '--json state' "$ST_GH_LOG" && ! grep -q -- 'stateReason' "$ST_GH_LOG"; then
  pass "(st9) the ticket arm reads .state alone — any CLOSED counts, so a not_planned close is not missed"
else fail "(st9) the ticket arm did not read .state, or narrowed on stateReason: $(cat "$ST_GH_LOG")"; fi

out="$(ST_GH_FAIL=1 stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "could not read #7's state" <<<"$out" \
   && ! grep -q 'ARM FIRED' <<<"$out"; then
  pass "(st10) an unreadable tracker is exit 1 naming the read, never 0 and never 7 (D-5 fails closed)"
else fail "(st10) expected rc=1 from a failed tracker read, got rc=$rc: $out"; fi

out="$(ST_STATE=WEIRD stgate "$ST_CFG" 7)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'unrecognized state' <<<"$out"; then
  pass "(st11) an unrecognized tracker answer is exit 1, not a guess in either direction"
else fail "(st11) expected rc=1 on an unrecognized state, got rc=$rc: $out"; fi

# jira, D-8. Scored while the base is still FIRING, so a blanket "jira ⇒ clean" build fails here:
# the ticket arm states a skip and the BASE arm still runs. The branch under jira is
# `claude/acme-7` (prefix `claude/`, key lowercased), which is the same ref this block created.
out="$(ST_STATE=CLOSED stgate "$ST_CFG_JIRA" ACME-7)"; rc=$?
if [ "$rc" -eq 7 ] && grep -q 'ticket arm skipped' <<<"$out" && grep -q 'BASE ARM FIRED' <<<"$out"; then
  pass "(st12) under jira the ticket arm states a skip and the base arm still runs — the skip is not a pass"
else fail "(st12) expected a stated jira skip with a live base arm, got rc=$rc: $out"; fi

# D-9. A branch key with no ref: the base arm has no range and says so, the ticket arm still runs,
# and the result is 0 — NOT the exit 1 a read failure gets.
out="$(stgate "$ST_CFG" 4242)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'does not exist yet' <<<"$out" \
   && grep -q 'ticket arm clean' <<<"$out" && grep -q 'Nothing failed' <<<"$out"; then
  pass "(st13) no branch ref yet is a stated base-arm SKIP at rc=0, with the ticket arm still evaluated"
else fail "(st13) expected a rc=0 skip on a branch-less key, got rc=$rc: $out"; fi

# The fetch's own failure mode, driven by pointing origin at nothing. Scored on a key whose branch
# EXISTS, so the arm genuinely reaches the fetch rather than short-circuiting at (st13)'s skip.
git -C "$STREE" remote set-url origin "$STW/no-such-remote.git" >/dev/null 2>&1
out="$(stgate "$ST_CFG" 7 --arm base)"; rc=$?
git -C "$STREE" remote set-url origin "$SORIGIN" >/dev/null 2>&1
if [ "$rc" -eq 1 ] && grep -q 'could not fetch origin/main' <<<"$out" \
   && ! grep -q 'ARM FIRED' <<<"$out" && ! grep -q 'base arm clean' <<<"$out"; then
  pass "(st14) an unfetchable base is exit 1 naming the fetch — a stale ref must not answer 'nothing moved'"
else fail "(st14) expected rc=1 from a failed fetch, got rc=$rc: $out"; fi

# ZERO WRITES, and this block never recorded an entry attestation — so this one assertion carries
# both facts: the subcommand ran (repeatedly, above) outside require_entry_attested's set, and it
# brought no progress file into existence at the path the gate resolves for itself.
if [ ! -e "$STREE/.claude/pipeline-state/7-lean-progress.md" ] \
   && [ ! -e "$STREE/.claude/pipeline-state/4242-lean-progress.md" ]; then
  pass "(st15) staleness needs no entry attestation and creates no progress file — it records nothing"
else fail "(st15) staleness wrote a progress file: $(ls "$STREE/.claude/pipeline-state" 2>/dev/null)"; fi

out="$(stgate "$ST_CFG" 7 --arm sideways)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'ticket|base|both' <<<"$out"; then
  pass "(st16) an unknown --arm is a usage refusal, not a value that quietly selects neither arm"
else fail "(st16) expected rc=2 on an unknown --arm, got rc=$rc: $out"; fi

# The THIRD fail-closed arm, and the only one with no natural driver: a branch that shares no
# history with the base, so the fetch succeeds and the merge-base does not exist. Reached with an
# orphan root rather than a broken remote, which is what keeps it distinct from (st14) — the ref
# resolves, the fetch works, and there is still no range. LAST in the block because it moves the
# fixture's HEAD around.
st_git "$STREE" checkout -q --orphan claude/acme-99 >/dev/null 2>&1
st_git "$STREE" rm -rq --cached . >/dev/null 2>&1
printf 'unrelated history\n' > "$STREE/orphan.txt"
st_git "$STREE" add orphan.txt >/dev/null 2>&1
st_git "$STREE" commit -q -m "an unrelated root" >/dev/null 2>&1
st_git "$STREE" checkout -qf main >/dev/null 2>&1
rm -f "$STREE/orphan.txt"
out="$(stgate "$ST_CFG" 99 --arm base)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cannot resolve merge-base' <<<"$out" \
   && ! grep -q 'does not exist yet' <<<"$out" && ! grep -q 'base arm clean' <<<"$out"; then
  pass "(st17) a branch with no shared history is exit 1 naming the merge-base — not the D-9 skip and not a clean answer"
else fail "(st17) expected rc=1 from an unresolvable merge-base, got rc=$rc: $out"; fi

# ---- (sc) #563: the selftest pass-cache store reaches the lane children -------------------
# The SAME seam (jc1) asserts, carrying the second value the gate hands down, and asserted the
# same way and for the same reason: an extraLane runs through the one `env ${SEAM_SCRUB_ENV[@]…}`
# idiom every milestone-3 child is spawned through, so a child that sees the store proves the
# fixed `test` key — the one that actually runs run-selftests.sh — sees it too.
#
# What CANNOT be asserted here is that a suite is then skipped: that is the runner's contract and
# tools/run-selftests-selftest.sh's #563 cases own it, driven through this very variable. The
# coupling between the two sides is a variable NAME, which docs/testing.md records as declined
# under LEAN_SELFTEST_CACHE_DIR, and which this case pins behaviorally, from the writer's side,
# so a rename here leaves a child reporting `unset`.
sc_xdg="$WORK/sc-xdg"
# The single quotes are the assertion: $LEAN_SELFTEST_CACHE_DIR must expand in the CHILD the gate
# spawns. Expanding it here would compare this suite's environment against itself.
# shellcheck disable=SC2016
cfg="$(el_cfg '[{"name":"store-probe","commands":["echo child-store=${LEAN_SELFTEST_CACHE_DIR:-unset}"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-store.md"
attest_at "$EL_TREE" "$cfg" "$prog" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID LEAN_SELFTEST_CACHE_DIR LEAN_SELFTEST_CACHE
        cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
        XDG_CACHE_HOME="$sc_xdg" \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
sc_child="$(printf '%s\n' "$out" | sed -n 's/^child-store=//p' | head -1)"
if [ "$rc" -eq 0 ] && [ "$sc_child" = "$sc_xdg/second-shift/lean-selftest" ] \
   && grep -qF "selftest pass cache store $sc_xdg/second-shift/lean-selftest" <<<"$out" \
   && grep -qF 'ADVERTISED, not enforced' <<<"$out"; then
  pass "(sc1) milestone 3 announces the default store and the lane child is spawned with it"
else fail "(sc1) expected the announced default store to reach the child, got rc=$rc child='$sc_child': $out"; fi

# The operator override, asserted on the ANNOUNCEMENT and deliberately not on the child. The
# child value cannot discriminate here and saying so is the point: an operator-set variable is
# inherited by every descendant anyway, so a child reporting it proves nothing about the gate —
# a measured fact, not a supposition (the first revision of this case asserted the child and
# passed with the export line replaced by `:`). (sc1) is where the export itself is pinned,
# against a DEFAULT store the environment does not carry; this case pins the resolution.
prog="$WORK/el-prog-store-override.md"
attest_at "$EL_TREE" "$cfg" "$prog" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID LEAN_SELFTEST_CACHE
        cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
        XDG_CACHE_HOME="$sc_xdg" LEAN_SELFTEST_CACHE_DIR="$WORK/sc-operator-store" \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "selftest pass cache store $WORK/sc-operator-store" <<<"$out" \
   && ! grep -qF "$sc_xdg/second-shift/lean-selftest" <<<"$out"; then
  pass "(sc2) an operator-set store overrides the default the gate would otherwise announce"
else fail "(sc2) expected the operator store to be the announced one, got rc=$rc: $out"; fi

# The off switch, run in the ONLY environment where it can fail: one that already carries a
# store. Ambient inheritance is what a bare "do not export" walks straight past — the gate would
# announce a cold sweep while the runner below it cached — so the case that matters sets the
# variable and demands the child see nothing. A gate that merely stopped PRINTING, or that
# declined to export while leaving the operator's value inherited, both red here.
prog="$WORK/el-prog-store-off.md"
attest_at "$EL_TREE" "$cfg" "$prog" 7
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID
        cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
        XDG_CACHE_HOME="$sc_xdg" LEAN_SELFTEST_CACHE_DIR="$WORK/sc-ambient-store" \
        LEAN_SELFTEST_CACHE=0 \
        bash "$GATE" --issue-file "$EL_ISSUE" 3 7 2>&1 )"; rc=$?
sc_child="$(printf '%s\n' "$out" | sed -n 's/^child-store=//p' | head -1)"
if [ "$rc" -eq 0 ] && [ "$sc_child" = "unset" ] \
   && grep -qF 'selftest pass cache DISABLED (LEAN_SELFTEST_CACHE=0)' <<<"$out"; then
  pass "(sc3) the off switch scrubs an AMBIENT store out of the lane child, not just the export"
else fail "(sc3) an ambient store survived the off switch, got rc=$rc child='$sc_child': $out"; fi

# ---- (lt) #141: THE LANE-TREE ASSERTION ------------------------------------------------------
# Every case here `unset LEAN_GATE_ANY_TREE` in its own subshell, undoing the suite-wide export at
# the top of this file. That export is what lets the other ~200 guarded calls run against fixture
# trees at all; these are the cases the guard is actually covered by, so leaving it set here would
# make the whole block vacuous.
#
# ITS OWN MAIN CHECKOUT, not $TREE. The refusal's remedy arm reads `git worktree list` from the
# resolved MAIN_ROOT, so the fixture needs a real registered worktree — which means a repo this
# block owns, since adding one to $TREE would put a second branch into 200 unrelated cases' view.
LT_MAIN="$WORK/wt-main"
LT_LANE="$WORK/wt-lane"
LT_PROG="$WORK/wt-progress.md"
mkdir -p "$LT_MAIN/docs/plans" "$LT_MAIN/.claude/audit"
git -C "$LT_MAIN" init -q
git -C "$LT_MAIN" config user.email t@example.invalid
git -C "$LT_MAIN" config user.name t
printf '.claude/\n' > "$LT_MAIN/.gitignore"
git -C "$LT_MAIN" add -A >/dev/null 2>&1
git -C "$LT_MAIN" commit -q -m "wt fixture" >/dev/null 2>&1
git -C "$LT_MAIN" update-ref refs/remotes/origin/main HEAD
# The lane worktree for issue 31, on the branch $CFG's prefix derives. Issue 32 deliberately gets
# none, which is the fallback arm's fixture.
git -C "$LT_MAIN" worktree add -q -b claude/acme-31 "$LT_LANE" >/dev/null 2>&1
LT_OFF="$(git -C "$LT_MAIN" rev-parse --abbrev-ref HEAD)"

# <tree> <issue> <args...> — run the gate with the assertion ARMED, merging both streams.
# GH is pinned to the dead stub for the same reason the rest of this file is zero-network: the two
# unguarded subcommands reached here (`entry`, `inflight`) look a PR state up, and an unseamed one
# would send a selftest to the live API. A refused lookup removes nothing and is reported, which
# is exactly the state these cases want — none of them is about the sweep.
ltgate() { local t="$1" i="$2"; shift 2
  # #611: the TICKET stub, not `gh-dead.sh`. (lt2) drives `entry` to prove it is not wrong-tree
  # guarded, and under a dead CLI that call now refuses at the run boundary instead — leaving the
  # case asserting "not rc=9" about an invocation that never reached the guard at all. Both stubs
  # are network-free; only this one lets the arm mean what the case says it means.
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT LEAN_GATE_ANY_TREE
    cd "$t" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$LT_PROG" GH="$GH_STUB" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" "$i" 2>&1 )
}

# (lt1) EVERY guarded subcommand refuses from a tree that is not on the lane branch. Enumerated
# rather than sampled: the dispatch arm is a `case` list, and a list is exactly the thing a
# one-member probe cannot tell from a complete one.
rm -f "$LT_PROG"
lt1_bad=""
for sub in 1 2 3 4 5 all delta verdict close-out; do
  out="$(ltgate "$LT_MAIN" 31 "$sub")"; rc=$?
  [ "$rc" -eq 9 ] || lt1_bad="$lt1_bad $sub(rc=$rc)"
  grep -q 'WRONG TREE' <<<"$out" || lt1_bad="$lt1_bad $sub(no-message)"
done
if [ -z "$lt1_bad" ]; then
  pass "(lt1) all nine guarded subcommands refuse with exit 9 from a tree on '$LT_OFF' instead of the lane branch"
else fail "(lt1) not refused:$lt1_bad"; fi

# (lt1a) ...and the refusal EVALUATED NOTHING. The progress file is the only thing a milestone
# call writes, and a guard that refused after recording would be worse than none: the run's record
# would carry a milestone row derived from the wrong tree.
if [ ! -f "$LT_PROG" ]; then
  pass "(lt1a) a refused call writes no progress record at all — nothing was evaluated"
else fail "(lt1a) the refusal left a progress file: $(cat "$LT_PROG")"; fi

# (lt2) The unguarded set is genuinely unguarded. These are the roles whose tree IS the main
# checkout — SKILL.md steps 1-2 run before the worktree exists, and the scheduler reads the run's
# state from the clone it owns. A guard that caught them would make the lane unstartable.
lt2_bad=""
for sub in entry progress teardown inflight staleness; do
  out="$(ltgate "$LT_MAIN" 31 "$sub")"; rc=$?
  [ "$rc" -eq 9 ] && lt2_bad="$lt2_bad $sub(rc=9)"
  grep -q 'WRONG TREE' <<<"$out" && lt2_bad="$lt2_bad $sub(message)"
done
if [ -z "$lt2_bad" ]; then
  pass "(lt2) entry/progress/teardown/inflight/staleness are NOT guarded — they run from the main checkout by role"
else fail "(lt2) wrongly refused:$lt2_bad"; fi
rm -f "$LT_PROG"

# (lt3) THE PASS DIRECTION, and it must reach real evaluation rather than merely not exiting 9.
# Attested first, so milestone 1 gets past the entry precondition and returns its own answer:
# `absent` for a spec that is not written yet, which is a milestone verdict only the guarded body
# can produce.
# The audit ledger has to land in the MAIN checkout, not the lane worktree: `entry` resolves it
# from the git COMMON dir, which a linked worktree shares with $LT_MAIN. attest_at seeds it beside
# the tree it is handed, so the linked-worktree case needs the main copy planted by hand.
mkdir -p "$LT_MAIN/.claude/audit"
printf '{"tool":"Bash"}\n' > "$LT_MAIN/.claude/audit/$ENTRY_SID.jsonl"
# #611: NOT under `gh-dead.sh` any more. `entry` reads the ticket at the run boundary, so a dead
# CLI here refuses the attestation this case needs to exist — and (lt3) would then report a
# missing-attestation rc=2 as "milestone 1 did not pass through", which is a red naming the wrong
# guard. The suite-wide stub keeps it network-free.
attest_at "$LT_LANE" "$CFG" "$LT_PROG" 31
out="$(ltgate "$LT_LANE" 31 1)"; rc=$?
if [ "$rc" -eq 1 ] && ! grep -q 'WRONG TREE' <<<"$out" && grep -q 'no committed spec' <<<"$out"; then
  pass "(lt3) on the lane branch the guard passes THROUGH to the milestone body — milestone 1 returns its own absent-spec answer"
else fail "(lt3) expected milestone 1's own answer, rc=$rc: $out"; fi

# (lt4) A DETACHED HEAD refuses. `rev-parse --abbrev-ref HEAD` reads back the literal `HEAD`, so
# the equality fails — and it must, because a detached tree's identity is asserted by nothing on
# disk. This is the shape a review session lands in when it cuts its checkout with `--detach`.
git -C "$LT_LANE" checkout -q --detach
out="$(ltgate "$LT_LANE" 31 1)"; rc=$?
if [ "$rc" -eq 9 ] && grep -q "is on 'HEAD'" <<<"$out"; then
  pass "(lt4) a DETACHED head refuses — it reads back as 'HEAD' and matches no lane branch"
else fail "(lt4) expected the detached refusal, rc=$rc: $out"; fi
git -C "$LT_LANE" checkout -q claude/acme-31

# (lt5) The refusal names all three things an operator needs: the branch found, the branch
# expected, and where to go. A refusal that says only "wrong tree" costs the round it saved.
out="$(ltgate "$LT_MAIN" 31 1)"
if grep -q "is on '$LT_OFF'" <<<"$out" && grep -q "claude/acme-31" <<<"$out" \
   && grep -qF "$LT_LANE" <<<"$out"; then
  pass "(lt5) the refusal names the branch found, the lane branch expected, and the registered lane worktree's path"
else fail "(lt5) refusal is missing one of the three: $out"; fi

# (lt5a) ...and with NO worktree registered on the lane branch it prints the command that cuts
# one, rather than naming nothing. Issue 32 has no worktree; issue 31 does.
out="$(ltgate "$LT_MAIN" 32 1)"
if grep -qF "worktree add" <<<"$out" && grep -qF "$LT_MAIN" <<<"$out" \
   && grep -q "claude/acme-32" <<<"$out" && ! grep -qF "$LT_LANE" <<<"$out"; then
  pass "(lt5b) with no worktree on the lane branch the refusal falls back to the 'git worktree add' command"
else fail "(lt5b) expected the worktree-add fallback for an unregistered lane branch: $out"; fi

# (lt6) THE GUARD FIRES FIRST (D-7). Same call, but the run has no entry attestation either. Both
# refusals are real, and the one reported must be the tree — the entry refusal's own text ends
# "Re-run from the build worktree", which sends the operator to fix the second-order symptom.
rm -f "$LT_PROG"
out="$(ltgate "$LT_MAIN" 31 1)"; rc=$?
if [ "$rc" -eq 9 ] && grep -q 'WRONG TREE' <<<"$out" && ! grep -q 'no entry attestation' <<<"$out"; then
  pass "(lt6) a wrong-tree call with no attestation reports the TREE, not the missing entry row"
else fail "(lt6) the entry precondition preempted the tree guard, rc=$rc: $out"; fi

# (lt7) The opt-out disarms, and ANNOUNCES that it did. A guard nobody can see disarmed is a guard
# nobody can audit — the announcement is the seam's whole safety property.
out="$( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
        cd "$LT_MAIN" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$LT_PROG" \
        GH="$WORK/gh-dead.sh" LEAN_GATE_ANY_TREE=1 bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 31 2>&1 )"; rc=$?
if [ "$rc" -ne 9 ] && grep -q 'LEAN_GATE_ANY_TREE=1' <<<"$out" \
   && grep -q "is on '$LT_OFF'" <<<"$out" && grep -q "claude/acme-31" <<<"$out"; then
  pass "(lt7) LEAN_GATE_ANY_TREE=1 disarms the assertion and announces it, naming both the branch found and the one expected"
else fail "(lt7) expected an announced disarm, rc=$rc: $out"; fi

# (lt7a) The announcement is a DIAGNOSTIC and rides stderr, like every other one this file emits.
# Same reasoning as (rc5a): the machine-read answer is stdout, and a note there is a parse hazard.
lt7_stdout="$( unset RUN_ID CLAUDE_CODE_SESSION_ID GH_BOT
               cd "$LT_MAIN" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$LT_PROG" \
               GH="$WORK/gh-dead.sh" LEAN_GATE_ANY_TREE=1 bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 1 31 2>/dev/null )"
if ! grep -q 'LEAN_GATE_ANY_TREE' <<<"$lt7_stdout"; then
  pass "(lt7a) the disarm announcement goes to stderr and never to stdout"
else fail "(lt7a) the disarm note polluted stdout: $lt7_stdout"; fi


# ---- (tk) #611: the ticket-resolution contract on the run boundary ------------------------
# WHY A BLOCK OF ITS OWN rather than cases folded into (l). The (l) usage cases assert exit 2 —
# "you spelled the invocation wrong" — and every case here asserts exit 10, which is a different
# claim: the invocation parsed and its ticket is not one this run may act on. A suite that mixed
# them would let a regression collapsing 10 into 2 pass half the file.
#
# TWO TREES, because the contract's two halves need opposite cwds: TK_MAIN is a shared checkout
# that is on no lane at all (so nothing is inferable from it), TK_LANE is a worktree ON
# `claude/acme-77` (the re-entry shape). LEAN_GATE_ANY_TREE is unset in both — the suite-wide
# disarm would make the cwd arms vacuous, which is the failure mode the (wt*) block already
# taught this file to guard against.
TK_MAIN="$WORK/tk-main"
mkdir -p "$TK_MAIN/.claude/audit"
git -C "$TK_MAIN" init -q
git -C "$TK_MAIN" config user.email t@example.invalid
git -C "$TK_MAIN" config user.name t
printf '.claude/\n' > "$TK_MAIN/.gitignore"
git -C "$TK_MAIN" add -A >/dev/null 2>&1
git -C "$TK_MAIN" commit -q -m "tk fixture" >/dev/null 2>&1
git -C "$TK_MAIN" branch -M main >/dev/null 2>&1
git -C "$TK_MAIN" update-ref refs/remotes/origin/main HEAD
TK_LANE="$WORK/tk-lane"
git -C "$TK_MAIN" worktree add -q -b claude/acme-77 "$TK_LANE" HEAD 2>/dev/null
mkdir -p "$TK_LANE/.claude/audit"
TK_SID="sess-tk-fixture"
printf '{"tool":"Bash"}\n' > "$TK_MAIN/.claude/audit/$TK_SID.jsonl"
TK_PROG="$WORK/tk-prog.md"

# The two drivers. Neither passes --issue-file: these cases are about the run boundary, which
# reads the tracker through $GH and never through that seam, and a fixture flag the production
# path does not consult would read as coverage it is not.
tkgate() { # tkgate <args…> — from the shared checkout, on no lane
  ( unset RUN_ID GH_BOT LEAN_GATE_ANY_TREE
    cd "$TK_MAIN" && CLAUDE_CODE_SESSION_ID="$TK_SID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$TK_PROG" bash "$GATE" "$@" 2>&1 )
}
tklane() { # tklane <args…> — from the lane worktree, on claude/acme-77
  ( unset RUN_ID GH_BOT LEAN_GATE_ANY_TREE
    cd "$TK_LANE" && CLAUDE_CODE_SESSION_ID="$TK_SID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$TK_PROG" bash "$GATE" "$@" 2>&1 )
}

# --- failure case 1: ABSENT ---------------------------------------------------------------
rm -f "$TK_PROG"
out="$(tkgate entry)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'was given no ticket' <<<"$out" \
   && grep -q 'not a work branch' <<<"$out"; then
  pass "(tk1) AC-2: \`entry\` with no ticket from a non-lane cwd refuses with rc=10, naming what was missing"
else fail "(tk1) expected rc=10 refusing to self-select, got $rc: $out"; fi

# The row a refused call must NOT have written. `entry`'s whole job is to create this file, so
# "it refused" and "it refused before writing" are genuinely different outcomes here.
if [ ! -f "$TK_PROG" ]; then
  pass "(tk1a) AC-5: the absent-ticket refusal writes no progress file at all"
else fail "(tk1a) the refusal created $TK_PROG: $(cat "$TK_PROG")"; fi

out="$(tklane claim)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q "whose key is '77'" <<<"$out" \
   && grep -q 'claim 77 --ticket-source lane-branch' <<<"$out"; then
  pass "(tk2) AC-2: from a lane cwd the refusal names the derived key and the exact re-invocation — and still refuses"
else fail "(tk2) expected rc=10 naming key 77 and the re-invocation, got $rc: $out"; fi

# --- failure case 2: KEY SHAPE ------------------------------------------------------------
out="$(tkgate entry abc)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'not a github issue number' <<<"$out"; then
  pass "(tk3) AC-5: a non-numeric github key refuses with its own named reason"
else fail "(tk3) expected rc=10 on 'abc', got $rc: $out"; fi

out="$(tkgate entry 0)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'positive integer' <<<"$out"; then
  pass "(tk3a) AC-1: zero is not a positive integer and is refused at the shape arm"
else fail "(tk3a) expected rc=10 on '0', got $rc: $out"; fi

out="$(tkgate entry 007)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'leading zeros' <<<"$out"; then
  pass "(tk3b) AC-1: a zero-padded key is refused — it would derive a lane branch no other reader reconstructs"
else fail "(tk3b) expected rc=10 on '007', got $rc: $out"; fi

# The shape arm must beat the tracker arm: a key the adapter cannot spell has no ticket to be,
# and a stub that would have answered OPEN proves the ordering rather than the outcome.
out="$( STUB_GH_STATE=OPEN tkgate entry abc )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'No tracker read was attempted' <<<"$out"; then
  pass "(tk3c) AC-2: the shape refusal performs no tracker read, even when the tracker would have said OPEN"
else fail "(tk3c) expected the no-read message, got $rc: $out"; fi

# --- failure case 3: NONEXISTENT / CLOSED -------------------------------------------------
out="$( STUB_GH_FAIL='GraphQL: Could not resolve to an issue or pull request with the number of 4242. (repository.issue)' \
        tkgate entry 4242 )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'names no issue in this repository' <<<"$out"; then
  pass "(tk4) AC-5: an argument naming no issue refuses with its own named reason, distinct from an outage"
else fail "(tk4) expected the nonexistent reason, got $rc: $out"; fi

out="$( STUB_GH_STATE=CLOSED tkgate entry 4242 )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'nothing on it evidences that this run ever claimed it' <<<"$out"; then
  pass "(tk5) AC-1: a CLOSED ticket with no re-entry evidence refuses"
else fail "(tk5) expected the closed-no-evidence reason, got $rc: $out"; fi

# The waiver, and its two halves. The marker must be BOT-authored AND carry THIS run's id — the
# same pair check-lean-chain.sh applies at the merge boundary — and the label must be present.
TK_MARKER="$WORK/tk-marker.json"
cat > "$TK_MARKER" <<'JSON'
[{"user":{"type":"Bot"},"body":"<!-- run_id: tk-run-1 -->\n<!-- stage: lean-claimed -->\n"}]
JSON
TK_HUMAN="$WORK/tk-human.json"
cat > "$TK_HUMAN" <<'JSON'
[{"user":{"type":"User"},"body":"<!-- run_id: tk-run-1 -->\n<!-- stage: lean-claimed -->\n"}]
JSON

tkre() { # tkre <comments-fixture> <args…> — a re-entry: this run's id established
  local f="$1"; shift
  ( unset GH_BOT LEAN_GATE_ANY_TREE
    cd "$TK_MAIN" && RUN_ID=tk-run-1 CLAUDE_CODE_SESSION_ID="$TK_SID" SECOND_SHIFT_CONFIG="$CFG" \
    LEAN_PROGRESS_FILE="$TK_PROG" STUB_GH_STATE=CLOSED STUB_GH_LABELS=in-progress \
    STUB_GH_COMMENTS="$(cat "$f")" bash "$GATE" "$@" 2>&1 )
}

rm -f "$TK_PROG"
out="$(tkre "$TK_MARKER" entry 4242)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'Admitted as a RE-ENTRY' <<<"$out"; then
  pass "(tk5a) AC-1: a CLOSED ticket carrying the claimed label AND this run's bot marker admits \`entry\`, so close-out and teardown still run"
else fail "(tk5a) expected rc=0 admitting the re-entry, got $rc: $out"; fi

out="$(tkre "$TK_MARKER" claim 4242)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'a claim WRITE against a closed ticket is not' <<<"$out"; then
  pass "(tk5b) AC-1: the same evidence routes \`claim\` to a refusal — the waiver is for close-out, never for a fresh claim"
else fail "(tk5b) expected rc=10 refusing the claim write, got $rc: $out"; fi

out="$(tkre "$TK_HUMAN" entry 4242)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'marker=0' <<<"$out"; then
  pass "(tk5c) an operator-posted claim marker is not evidence the harness ran — the waiver needs a BOT author"
else fail "(tk5c) expected rc=10 on a human-authored marker, got $rc: $out"; fi

# --- failure case 4: TRACKER UNREADABLE ---------------------------------------------------
out="$( STUB_GH_FAIL='error connecting to api.github.com' tkgate entry 4242 )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'could not be read' <<<"$out" && grep -q 'fails CLOSED' <<<"$out"; then
  pass "(tk6) AC-5: an unreadable tracker refuses with its own named reason and says it fails closed"
else fail "(tk6) expected the outage reason, got $rc: $out"; fi

out="$( STUB_GH_STATE=WEIRD tkgate entry 4242 )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'unrecognized state' <<<"$out"; then
  pass "(tk6a) an unrecognized state is refused rather than guessed — the same fail-closed side"
else fail "(tk6a) expected the unrecognized-state refusal, got $rc: $out"; fi

# --- failure case 5: CWD DISAGREEMENT -----------------------------------------------------
for sub in entry claim mark teardown; do
  out="$(tklane "$sub" 78)"; rc=$?
  if [ "$rc" -eq 10 ] && grep -q "whose key is '77'" <<<"$out"; then
    pass "(tk7-$sub) AC-4: \`$sub\` refuses when the argument and the lane branch disagree"
  else fail "(tk7-$sub) expected rc=10 on a disagreement, got $rc: $out"; fi
done

# The other half of AC-4, and the one a plausible implementation gets wrong: the milestone calls
# keep the #141 code they already had. A second integer here would make two guards answer one
# question with two remedies.
out="$(tklane 1 78)"; rc=$?
if [ "$rc" -eq 9 ]; then
  pass "(tk7a) AC-4: a milestone call from the same disagreeing tree still exits 9, not 10 — the wrong-tree refusal is not duplicated"
else fail "(tk7a) expected rc=9 from the milestone call, got $rc: $out"; fi

# A cwd that is not a work branch of this namespace constrains nothing — otherwise every call
# from a shared checkout would need a lane to run at all.
out="$( STUB_GH_STATE=OPEN tkgate mark 78 )"; rc=$?
if [ "$rc" -ne 10 ]; then
  pass "(tk7b) AC-4: a non-lane cwd constrains nothing — \`mark\` is not refused for standing in the shared checkout"
else fail "(tk7b) a non-lane cwd wrongly triggered the disagreement arm: $out"; fi

# --- legal path 1: ARGUMENT ONLY ----------------------------------------------------------
rm -f "$TK_PROG"
out="$( STUB_GH_STATE=OPEN tkgate entry 4242 )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF '| ticket | resolved=4242 | source=argument' "$TK_PROG"; then
  pass "(tk8) AC-3: an open, named ticket resolves and records \`source=argument\` in the progress file"
else fail "(tk8) expected rc=0 and an argument-sourced ticket row, got $rc: $out / $(cat "$TK_PROG" 2>/dev/null)"; fi

# --- legal path 2: INFERENCE WITH A DECLARED SOURCE ---------------------------------------
rm -f "$TK_PROG"
out="$( STUB_GH_STATE=OPEN tklane entry 77 --ticket-source lane-branch )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF '| ticket | resolved=77 | source=lane-branch' "$TK_PROG"; then
  pass "(tk9) AC-3: an inferred ticket declared from a lane cwd resolves, and BOTH the key and its source are recorded"
else fail "(tk9) expected rc=0 and a lane-branch-sourced row, got $rc: $out / $(cat "$TK_PROG" 2>/dev/null)"; fi

out="$( STUB_GH_STATE=OPEN tkgate entry 4242 --ticket-source lane-branch )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'is not a work branch' <<<"$out"; then
  pass "(tk10) AC-3: a declared inference from a cwd that is no lane refuses — there is nowhere it could have come from"
else fail "(tk10) expected rc=10 on an inference claim from the shared checkout, got $rc: $out"; fi

# The registry source is ACCEPTED and still CHECKED against the branch (D-5): the branch name
# wins, so a row that disagreed with the tree is the disagreement refusal, never a fallback.
rm -f "$TK_PROG"
out="$( STUB_GH_STATE=OPEN tklane entry 77 --ticket-source lane-registry )"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'source=lane-registry' "$TK_PROG"; then
  pass "(tk10a) D-5: \`lane-registry\` is a recordable source, and it is still checked against the branch name"
else fail "(tk10a) expected rc=0 recording the registry source, got $rc: $out"; fi

out="$( STUB_GH_STATE=OPEN tklane entry 78 --ticket-source lane-registry )"; rc=$?
if [ "$rc" -eq 10 ] && grep -q "whose key is '77'" <<<"$out"; then
  pass "(tk10b) D-5: a registry-sourced key that disagrees with the branch refuses — the branch wins, and the disagreement is not silently absorbed"
else fail "(tk10b) expected rc=10 on a registry/branch disagreement, got $rc: $out"; fi

# --- the flag's own usage errors, which are exit 2 and not 10 -----------------------------
out="$(tkgate entry 4242 --ticket-source bogus)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'argument|lane-branch|lane-registry' <<<"$out"; then
  pass "(tk11) AC-3: a source token outside the enum is a usage error, not a refusal"
else fail "(tk11) expected rc=2 on an unknown source, got $rc: $out"; fi

out="$(tkgate teardown 4242 --ticket-source lane-branch)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "only meaningful on 'entry' or 'claim'" <<<"$out"; then
  pass "(tk11a) AC-3: --ticket-source on a subcommand that records nothing is a usage error, not a silent no-op"
else fail "(tk11a) expected rc=2 on a non-boundary subcommand, got $rc: $out"; fi

# --- the half that did NOT move -----------------------------------------------------------
# (l2) above asserts this for subcommand 1 against the shared TREE; this asserts it here too,
# because the deferral that made `entry` refuse with 10 is spelled as a case on $SUB, and a
# regression widening that case is invisible from either side alone.
out="$(tkgate 3)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'usage: lean-gate.sh' <<<"$out"; then
  pass "(tk12) the milestone calls keep their exit-2 usage error on an absent argument"
else fail "(tk12) expected rc=2 from a milestone call with no issue, got $rc: $out"; fi

# --- no stray identity from a refused boundary call ---------------------------------------
# `entry` seeds `<issue>-run-id`, and seed-once never clobbers — so a cache written for a number
# the gate then refused would hand this run's identity to whatever real run later took it.
rm -rf "$TK_MAIN/.claude/pipeline-state"
( unset GH_BOT LEAN_GATE_ANY_TREE
  cd "$TK_MAIN" && RUN_ID=tk-stray CLAUDE_CODE_SESSION_ID="$TK_SID" SECOND_SHIFT_CONFIG="$CFG" \
  LEAN_PROGRESS_FILE="$TK_PROG" STUB_GH_STATE=CLOSED bash "$GATE" entry 4242 >/dev/null 2>&1 )
if [ ! -e "$TK_MAIN/.claude/pipeline-state/4242-run-id" ]; then
  pass "(tk13) a refused boundary call leaves no run-id cache behind for the ticket it refused"
else fail "(tk13) the refusal seeded $(cat "$TK_MAIN/.claude/pipeline-state/4242-run-id")"; fi

# --- the jira arm: adapter-aware shape, and a liveness read it does not have ---------------
TK_CFG_JIRA="$WORK/tk-config-jira.json"
sed -e 's/"branchPrefix": "claude\/acme-"/"branchPrefix": "claude\/acme-", "type": "jira", "keyPattern": "[A-Z]+-[0-9]+"/' "$CFG" > "$TK_CFG_JIRA"
tkj() { ( unset RUN_ID GH_BOT LEAN_GATE_ANY_TREE
          cd "$TK_MAIN" && CLAUDE_CODE_SESSION_ID="$TK_SID" SECOND_SHIFT_CONFIG="$TK_CFG_JIRA" \
          LEAN_PROGRESS_FILE="$TK_PROG" bash "$GATE" "$@" 2>&1 ); }
out="$(tkj entry 4242)"; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'not a valid jira key' <<<"$out"; then
  pass "(tk14) AC-1: validation is adapter-aware — a bare number is not a key under jira"
else fail "(tk14) expected rc=10 on a numeric key under jira, got $rc: $out"; fi

rm -f "$TK_PROG"
out="$(tkj entry ACME-9)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'ticket liveness arm skipped' <<<"$out"; then
  pass "(tk14a) AC-1: under jira the shape arm runs and the liveness arm says it has no read here, rather than inventing one"
else fail "(tk14a) expected rc=0 with an announced skip, got $rc: $out"; fi

# ---- (co) #590: the close-out command's own logic ------------------------------------------------
# The composed happy path lives in scenario-liveness-selftest.sh's (lean-closeout) leg, which runs
# the REAL command through the REAL scheduler to a terminal write. What that leg CANNOT reach is
# the branch below it: it runs on a host with no collector, so its cost block is always a
# documented skip and the PR-description replacement is never attempted. These cases own that
# branch — and the replacement is the highest-risk text in the command, because a strip that ran
# to end-of-file would silently delete a human's own paragraph out of a PR description.
CO_WORK="$WORK/closeout"; mkdir -p "$CO_WORK"
CO_SPOOL="$CO_WORK/patched-body"
CO_STUB="$CO_WORK/writer.sh"
cat > "$CO_STUB" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in body=@*) cat "${a#body=@}" > "$CO_SPOOL" ;; esac
done
echo 9
EOF
chmod +x "$CO_STUB"

# shellcheck disable=SC2016  # a literal dollar amount in a rendered table, not an expansion.
CO_BLOCK="$(printf '%s\n' '<!-- pipeline-cost-block -->' '---' '' '## Pipeline Cost' '' '| Scope | Cost |' '|---|---|' '| Run total | $1.00 |' '' 'Cache-hit rate: 90% · Sessions: 2')"

# LIBRARY MODE, so the replacement is driven as the function it is rather than through a live PR.
# Prints the note the command records as its obligation detail; the patched body lands in $CO_SPOOL.
# shellcheck disable=SC1090,SC2034  # $GATE is the script under test, and the two globals below
# are exactly the inputs its production body reads.
co_patch() { # co_patch <current-body>
  # CAPTURED BEFORE THE SOURCE, and that is not style. `.` inside a function lends that function's
  # positional parameters to the sourced file, and the gate's own option loop SHIFTS them away — so
  # a `$1` read AFTER the source is unbound, which under this suite's `set -u` kills the subshell
  # and returns an empty note. Every one of these six cases failed that way before it ever reached
  # an assertion about the production code.
  local co_arg="$1"
  rm -f "$CO_SPOOL"
  # EXPORTED, not prefixed, and for TWO reasons that are easy to conflate. The stub is a separate
  # process and sees only the environment, so `CO_SPOOL`/`GH_BOT` have to be exported at all. And a
  # prefix assignment on `.` would not have survived the source anyway — that persistence is POSIX-
  # mode behavior, not this bash's. Either way the failure is silent and reads as "the function
  # returned nothing".
  ( cd "$TREE" && export CO_SPOOL GH_BOT="$CO_STUB"
    LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1
    LEAN_COST_BLOCK="$CO_BLOCK"
    closeout_patch_pr_body 9 "$co_arg" >/dev/null 2>&1
    printf '%s' "$LEAN_PATCH_NOTE" )
}

# (co1) A BLOCK IN THE MIDDLE. Everything above it survives, the block is replaced, and — the case
# this exists for — everything BELOW its terminator line survives too.
co_body="$(printf '%s\n' 'Summary of the change.' '' 'Closes #9' '' "$CO_BLOCK" '' '## Notes from a human' '' 'Please do not delete me.')"
co_note="$(co_patch "$co_body")"
if [ "$co_note" = "replaced in place" ] \
   && grep -qF 'Please do not delete me.' "$CO_SPOOL" \
   && grep -qF 'Closes #9' "$CO_SPOOL" \
   && [ "$(grep -cF '<!-- pipeline-cost-block -->' "$CO_SPOOL")" -eq 1 ]; then
  pass "(co1) a cost block with human text below it is replaced in place — the text below survives, and exactly one block remains"
else fail "(co1) note='$co_note', body=$(cat "$CO_SPOOL" 2>/dev/null)"; fi

# (co2) NO BLOCK YET. The step-7 paste is the ordinary case, but a body that never got one must
# gain it rather than be rewritten.
co_body="$(printf '%s\n' 'Summary of the change.' '' 'Closes #9')"
co_note="$(co_patch "$co_body")"
if [ "$co_note" = "appended — the description carried no earlier block" ] \
   && grep -qF 'Closes #9' "$CO_SPOOL" \
   && [ "$(grep -cF '<!-- pipeline-cost-block -->' "$CO_SPOOL")" -eq 1 ]; then
  pass "(co2) a description with no earlier block gains one, and keeps everything it had"
else fail "(co2) note='$co_note', body=$(cat "$CO_SPOOL" 2>/dev/null)"; fi

# (co3) A MARKER WITH NO TERMINATOR. The strip cannot tell where such a block ends, so it runs to
# end-of-file — and the command must SAY so rather than truncate quietly. The note is the record's
# half of that; a mutant that dropped the distinction would leave (co1) green and this red.
co_body="$(printf '%s\n' 'Summary.' '' '<!-- pipeline-cost-block -->' 'a block whose last line moved' '' 'text below')"
co_note="$(co_patch "$co_body")"
if [ "$co_note" = "replaced, but the previous block had no terminator line — anything below it was not preserved" ] \
   && grep -qF 'Summary.' "$CO_SPOOL" \
   && ! grep -qF 'text below' "$CO_SPOOL"; then
  pass "(co3) a marker with no terminator line is reported as a truncating replacement, not performed as a silent one"
else fail "(co3) note='$co_note', body=$(cat "$CO_SPOOL" 2>/dev/null)"; fi

# (co4) CRLF. A body round-tripped through the GitHub API carries CRLF, so `$0 == marker` matches
# nothing without the CR strip — the marker would read as ABSENT on every real PR while every
# fixture in this file passed. The failure is a second block appended below the first, forever.
co_body="$(printf '%s\r\n' 'Summary.' '' '<!-- pipeline-cost-block -->' '---' '' 'Cache-hit rate: 10% · Sessions: 1' '' 'text below')"
co_note="$(co_patch "$co_body")"
if [ "$co_note" = "replaced in place" ] \
   && [ "$(grep -cF '<!-- pipeline-cost-block -->' "$CO_SPOOL")" -eq 1 ] \
   && grep -qF 'text below' "$CO_SPOOL"; then
  pass "(co4) a CRLF description is matched and replaced once — the marker does not read as absent on a body the API round-tripped"
else fail "(co4) note='$co_note', body=$(cat "$CO_SPOOL" 2>/dev/null)"; fi

# (co5) THE CORPUS ROW IS READ BACK, keyed on (ticketKey, runId). #546 writes it inside
# pipeline-cost-block.sh; without this read-back the obligation would assert "a command was run",
# which is the whole class of claim this ticket exists to delete.
CO_LOG="$CO_WORK/cost-log.jsonl"
{ printf '{"ticketKey":"8","runId":"r-other","totalUsd":1}\n'
  printf '{"ticketKey":"8","runId":"r-co","totalUsd":2}\n'; } > "$CO_LOG"
# shellcheck disable=SC1090,SC2034  # ditto — the two globals ARE the function's inputs.
co_row() { # co_row <run-id>
  local co_arg="$1"   # before the source, for the reason co_patch states above
  # COST_LOG_FILE IS SET AFTER THE SOURCE, not as a prefix on it. A prefix assignment on `.`
  # persists only in POSIX mode; under the bash this suite runs in, it lasts exactly as long as the
  # source and is gone by the time the function below reads it — which reads as "the row is not in
  # the log". The two prefixes that remain are needed only DURING the source, which is why they
  # are still prefixes.
  ( cd "$TREE" && LEAN_GATE_LIB=1 SECOND_SHIFT_CONFIG="$CFG" . "$GATE" >/dev/null 2>&1
    COST_LOG_FILE="$CO_LOG"; ISSUE=8; RESOLVED_RUN_ID="$co_arg"
    closeout_cost_log_row && echo found || echo missing )
}
co_hit="$(co_row r-co)"; co_miss="$(co_row r-absent)"
if [ "$co_hit" = "found" ] && [ "$co_miss" = "missing" ]; then
  pass "(co5) the cost-log read-back finds this run's row and refuses another run's — the corpus write is asserted, not assumed"
else fail "(co5) hit='$co_hit' miss='$co_miss' over $(cat "$CO_LOG")"; fi

# (co6) A LOG THAT DOES NOT PARSE is not a found row. `jq -s` errors with EMPTY output there, and
# an unguarded numeric test on an empty string is a syntax error that would read as success under
# the wrong idiom — the fail-open shape this repo enumerates.
printf 'not json at all\n' > "$CO_LOG"
if [ "$(co_row r-co)" = "missing" ]; then
  pass "(co6) an unparseable cost log reads as 'no row', never as one — the count is captured before it is tested"
else fail "(co6) an unparseable cost log was read as a found row"; fi

echo "[lean-gate-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
