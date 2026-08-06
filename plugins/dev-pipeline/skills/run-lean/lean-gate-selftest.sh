#!/usr/bin/env bash
# lean-gate-selftest.sh — behavioral suite for the run-lean milestone gates.
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

WORK="$(mktemp -d -t leangate.XXXXXX)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

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
# The patch-id freshness arm measures the branch's diff from merge-base(origin/<baseBranch>,
# HEAD), so the fixture needs a real remote-tracking ref. A throwaway repo has no remote;
# update-ref creates exactly what a fetch would leave behind, without one. Both the `verdict`
# writer and milestone 4 refuse when this is unresolvable — see (v6)/(v5) — so its absence
# would red the suite loudly rather than quietly skipping the arm.
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
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}
count_in_progress() { [ -f "$PROG" ] && grep -cF "$1" "$PROG" 2>/dev/null || echo 0; }

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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed spec'; then
  pass "(a1) milestone-1 fails when the lean spec is absent"
else fail "(a1) expected rc=1, got $rc: $out"; fi

printf '# spec\n\nNothing numbered here.\n' > "$SPEC"
out="$(gate 1 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no numbered AC-n'; then
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

# The two failures from (a1)/(a2) are the only attempts; passes must never add one.
n="$(count_in_progress '| milestone-1 | attempt |')"
if [ "$n" -eq 2 ]; then pass "(b2) only FAILED evaluations append attempt lines (passes do not inflate the counter)"
else fail "(b2) expected 2 attempt lines, got $n"; fi

# ---- (c) D-19 fix budget: 3 attempts, the 4th red hard-stops -----------------------------
reset_progress
rcs=""
for _ in 1 2 3 4; do gate 4 7 >/dev/null 2>&1; rcs="$rcs$?"; done
if [ "$rcs" = "1114" ]; then pass "(c1) fix budget: attempts 1-3 return 1, the 4th returns 4 (hard stop)"
else fail "(c1) expected rc sequence 1114, got $rcs"; fi
if [ "$(count_in_progress 'budget-exhausted')" -ge 1 ]; then
  pass "(c2) budget exhaustion is recorded in the progress file"
else fail "(c2) no budget-exhausted line recorded"; fi

# ---- (d) AC-14 entry gate ----------------------------------------------------------------
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        env -u CLAUDE_CODE_SESSION_ID bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'CLAUDE_CODE_SESSION_ID is unset'; then
  pass "(d1) entry refuses when the session id is unresolvable"
else fail "(d1) expected rc=1 on an unset session id, got $rc: $out"; fi

: > "$TREE/.claude/audit/sess-empty.jsonl"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-empty bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'missing or empty'; then
  pass "(d2) entry refuses on an EMPTY ledger — directory existence is not the test"
else fail "(d2) expected rc=1 on an empty ledger, got $rc: $out"; fi

out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-absent bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(d3) entry refuses when no ledger file exists for the session"
else fail "(d3) expected rc=1 on an absent ledger, got $rc: $out"; fi

printf '{"tool":"Bash"}\n{"tool":"Read"}\n' > "$TREE/.claude/audit/sess-live.jsonl"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-live bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(d4) entry passes on a live, non-empty ledger"
else fail "(d4) expected rc=0 on a live ledger, got $rc: $out"; fi

# ---- (e) AC-9: the derived prefix, asserted in BOTH directions ---------------------------
# The gate echoes the derived prefix into the progress-file header, which is where we read it.
reset_progress
# Use milestone 1 (not `entry`) to materialize the header: entry refuses without a live
# ledger for THIS session, so it would leave no progress file to read the prefix from.
gate 1 7 >/dev/null 2>&1 || true
derived="$(grep '^branch_prefix:' "$PROG" 2>/dev/null | awk '{print $2}')"
pipeline_prefix="claude/acme-"
if [ "$derived" = "lean/acme-" ]; then pass "(e1) prefix derives from tracker.branchPrefix ($pipeline_prefix -> $derived)"
else fail "(e1) expected lean/acme-, got '$derived'"; fi

case "$derived" in
  "$pipeline_prefix"*) fail "(e2) derived prefix '$derived' prefix-matches the pipeline prefix" ;;
  *) pass "(e2) derived prefix does not prefix-match the pipeline prefix" ;;
esac
# The reverse direction is the one a one-directional reading misses: `lean/` would pass (e2)
# while making EVERY pipeline branch match the lean gate.
case "$pipeline_prefix" in
  "$derived"*) fail "(e3) pipeline prefix '$pipeline_prefix' prefix-matches the derived prefix '$derived' — every pipeline PR would be double-classified" ;;
  *) pass "(e3) pipeline prefix does not prefix-match the derived prefix (the reverse direction)" ;;
esac

# A configured prefix already under lean/ collapses the two — the derivation must refuse.
CFG_BAD="$WORK/config-collide.json"
sed 's|"claude/acme-"|"lean/acme-"|' "$CFG" > "$CFG_BAD"
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_BAD" LEAN_PROGRESS_FILE="$WORK/p2.md" bash "$GATE" 1 7 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'collides'; then
  pass "(e4) a colliding configured prefix is a loud environment error, not a silent collision"
else fail "(e4) expected rc=2 on a colliding prefix, got $rc: $out"; fi

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
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'milestone-1'; then
  pass "(g) an already-satisfied milestone is still re-evaluated by 'all' (no caching)"
else fail "(g) 'all' short-circuited on a stored satisfied line — rc=$rc: $out"; fi
mv "$WORK/held-spec.md" "$SPEC"

# ---- (h) D-44: consumer posture — absent policy scripts are a SKIP NOTICE, not a pass -----
reset_progress
out="$(gate 2 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'SKIPPED'; then
  pass "(h) milestone-2 prints a skip notice when the policy scripts are absent (consumer repo)"
else fail "(h) expected a skip notice, got rc=$rc: $out"; fi

# ---- (i) D-18: mutation sweep absent is a printed skip ------------------------------------
# The shared $CFG configures zero fixed keys and no extraLanes, so it now depends on its own
# "commands.acme.allowUnverified": true (added for #392, below) to reach milestone 3's green
# gate at all — the cases in this block are about the mutation-sweep notice, the dead `build`
# key, and the absent extraLanes token, none of which are about the zero-lane guard itself.
reset_progress
out="$(gate 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'mutation-sweep.sh absent'; then
  pass "(i) milestone-3 prints a skip notice when tools/mutation-sweep.sh is absent"
else fail "(i) expected a mutation-sweep skip notice, got rc=$rc: $out"; fi

# #392 AC-1 (second half): the same green run also carries the allowUnverified notice, since
# the shared fixture has zero fixed keys and no extraLanes.
if printf '%s' "$out" | grep -q 'allowUnverified opt-out is set'; then
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
if ! printf '%s' "$out" | grep -q 'build is null'; then
  pass "(i-AC10) the dead 'build' key no longer appears in milestone-3 output"
else fail "(i-AC10) 'build is null' still printed — the dead key was not removed"; fi

# AC-5: no extraLanes key in $CFG — the same run must carry no 'extra lane' token, and the
# rest of this suite's shared-$TREE milestone-3 cases (this one included) stay green
# unmodified, proving the change is additive.
if ! printf '%s' "$out" | grep -q 'extra lane'; then
  pass "(i-AC5) no extraLanes key -> no 'extra lane' token in milestone-3 output"
else fail "(i-AC5) an 'extra lane' token appeared with no extraLanes configured"; fi

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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "no verifying lane configured for 'acme'" \
   && printf '%s' "$out" | grep -qF "$CFG_NOOPT" && printf '%s' "$out" | grep -q 'allowUnverified'; then
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

# AC-1: no config file at ALL (REPO_SLUG resolves the default 'acme') reds the same way, and
# names the same three things — the absent path included, since "which file did you read?" is
# the whole question an operator has when there is no config.
CFG_ABSENT="$WORK/no-such-config.json"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_ABSENT" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "no verifying lane configured for 'acme'" \
   && printf '%s' "$out" | grep -qF "$CFG_ABSENT" && printf '%s' "$out" | grep -q 'allowUnverified'; then
  pass "(iz2) AC-1: no config file at all also reds, naming slug/config/allowUnverified"
else fail "(iz2) expected rc=1 naming acme/$CFG_ABSENT/allowUnverified, got $rc: $out"; fi

# AC-2: exactly one fixed key set to a real command -> guard inert, existing behavior
# unchanged (no mention of allowUnverified anywhere in the output).
CFG_ONEKEY="$WORK/config-onekey.json"
jq 'del(.commands.acme.allowUnverified) | .commands.acme.lint = "true"' "$CFG" > "$CFG_ONEKEY"
reset_progress
out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_ONEKEY" LEAN_PROGRESS_FILE="$PROG" \
        bash "$GATE" --issue-file "$ISSUE_NOREGIONS" 3 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'allowUnverified'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "extra lane 'scoped' — skipped" \
   && ! printf '%s' "$out" | grep -q 'allowUnverified'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "extra lane 'ok-lane' » echo hi"; then
  pass "(i2) AC-1: an extraLane with no 'when' always runs"
else fail "(i2) expected rc=0 and the lane's command printed, got rc=$rc: $out"; fi

# AC-1: a failing lane reds milestone 3, naming BOTH the lane and the failing command.
cfg="$(el_cfg '[{"name":"boom","commands":["exit 7"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-boom.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "extra lane 'boom' failed (rc=7): exit 7"; then
  pass "(i3) AC-1: a failing extraLane reds milestone 3, naming the lane and the command"
else fail "(i3) expected rc=1 naming lane+command, got rc=$rc: $out"; fi

# AC-2: commands[] run sequentially and stop at the FIRST non-zero — "echo three" must never
# run, and the failure names the second command, not the third.
cfg="$(el_cfg '[{"name":"multi","commands":["echo one","exit 5","echo three"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-multi.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "» echo one" \
   && ! printf '%s' "$out" | grep -qF "» echo three" \
   && printf '%s' "$out" | grep -qF "failed (rc=5): exit 5"; then
  pass "(i4) AC-2: a multi-command lane stops at the first non-zero command"
else fail "(i4) expected sequential run stopping at 'exit 5', got rc=$rc: $out"; fi

# AC-3: a non-matching `when`, against the REAL non-empty diff above (src/App.tsx,
# nomatch/file.txt — neither is under docs/), skips with the pinned progress-file line.
cfg="$(el_cfg '[{"name":"scoped","when":["docs/**/*.md"],"commands":["echo should-not-run"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-scoped.md"
out="$(gate_el "$cfg" "$prog" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "extra lane 'scoped' — skipped" \
   && ! printf '%s' "$out" | grep -q 'should-not-run'; then
  pass "(i5) AC-3: a non-matching 'when' against a non-empty diff prints a skip"
else fail "(i5) expected a printed skip and no command run, got rc=$rc: $out"; fi
if [ "$(el_count_in "milestone-3 | skipped | extra lane 'scoped' — no changed path matches when[]" "$prog")" -ge 1 ]; then
  pass "(i6) AC-3: the pinned skip progress-file line is written"
else fail "(i6) expected the pinned skip line in $prog, got: $(cat "$prog" 2>/dev/null)"; fi

# AC-6: ordering is fixed keys -> extraLanes (declaration order) -> mutation sweep, fail-fast.
cfg="$(el_cfg '[{"name":"ord-lane","commands":["echo mid"],"failureClass":"TEST_FAILURE"}]')"
prog="$WORK/el-prog-ord.md"
out="$(gate_el "$cfg" "$prog" 3 7)"
lint_at="$(printf '%s\n' "$out" | grep -n 'lint is null' | head -1 | cut -d: -f1)"
lane_at="$(printf '%s\n' "$out" | grep -n "extra lane 'ord-lane'" | head -1 | cut -d: -f1)"
sweep_at="$(printf '%s\n' "$out" | grep -n 'mutation-sweep.sh absent' | head -1 | cut -d: -f1)"
if [ -n "${lint_at:-}" ] && [ -n "${lane_at:-}" ] && [ -n "${sweep_at:-}" ] \
   && [ "$lint_at" -lt "$lane_at" ] && [ "$lane_at" -lt "$sweep_at" ]; then
  pass "(i7) AC-6: observable ordering is fixed keys -> extraLanes -> mutation sweep"
else fail "(i7) expected lint < extraLane < sweep ordering, got lint=$lint_at lane=$lane_at sweep=$sweep_at"; fi

# AC-7: malformed entries red milestone 3 naming the entry INDEX — three shapes.
cfg="$(el_cfg '["oops"]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad1.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "extraLanes[0]: must be an object"; then
  pass "(i8) AC-7: a non-object extraLanes entry reds milestone 3 naming the index"
else fail "(i8) expected the non-object shape error, got rc=$rc: $out"; fi

cfg="$(el_cfg '[{"commands":["echo hi"],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad2.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "extraLanes[0]: missing 'name'"; then
  pass "(i9) AC-7: an entry missing 'name' reds milestone 3 naming the index"
else fail "(i9) expected the missing-name error, got rc=$rc: $out"; fi

cfg="$(el_cfg '[{"name":"x","commands":[],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-bad3.md" 3 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "extraLanes[0] ('x'): 'commands' must be a non-empty array"; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "cannot resolve origin/main to evaluate 'when'"; then
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
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'SCRUBBED' && ! printf '%s\n' "$out" | grep -qx 'LEAKED'; then
  pass "(i12) AC-9: the fixed-key lane child runs with SECOND_SHIFT_CONFIG stripped"
else fail "(i12) expected SCRUBBED with no LEAKED, got rc=$rc: $out"; fi

# lanes[] entries are {name, cwd?, commands[]} objects — the shape config-lint.sh enforces
# (its lanes[] arm: `name` required, unknown keys rejected) and the one verifyctl.sh reads.
# This fixture previously wrote `{command: "..."}`, a shape no lint-clean config can hold, and
# so pinned the reader bug rather than the contract: `.command // .` fed the whole lane object
# to `bash -c`, which is a syntax error on every real config that declares a lane.
cfg="$WORK/el-cfg-scrub-lanes.json"
jq '.commands.acme.lanes = [{"name": "scrub", "commands": ["[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED || echo LEAKED"]}]' "$CFG" > "$cfg" 2>/dev/null
out="$(gate_el "$cfg" "$WORK/el-prog-scrub-lanes.md" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'SCRUBBED' && ! printf '%s\n' "$out" | grep -qx 'LEAKED'; then
  pass "(i12b) AC-9: a lanes[] lane child runs with SECOND_SHIFT_CONFIG stripped"
else fail "(i12b) expected SCRUBBED with no LEAKED, got rc=$rc: $out"; fi

# A lane carrying no commands is lint-CLEAN (config-lint requires non-empty only when the key is
# present), so nothing upstream stops it — and a zero-iteration inner loop would skip it in
# silence on the way to a green milestone 3. It must fail loudly instead.
cfg="$WORK/el-cfg-lane-nocmds.json"
jq '.commands.acme.lanes = [{"name": "empty"}]' "$CFG" > "$cfg" 2>/dev/null
out="$(gate_el "$cfg" "$WORK/el-prog-lane-nocmds.md" 3 7)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "non-empty array"; then
  pass "(i12c) a commands-less lanes[] entry reds milestone 3 instead of being silently skipped"
else fail "(i12c) expected a loud failure, got rc=$rc: $out"; fi

# shellcheck disable=SC2016  # deliberate: the ${SECOND_SHIFT_CONFIG:-} must reach the child
# bash -c unexpanded, to be evaluated THERE (inside the scrubbed env), not by this shell.
cfg="$(el_cfg '[{"name":"scrub-check","commands":["[ -z \"${SECOND_SHIFT_CONFIG:-}\" ] && echo SCRUBBED || echo LEAKED"],"failureClass":"TEST_FAILURE"}]')"
out="$(gate_el "$cfg" "$WORK/el-prog-scrub-extra.md" 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'SCRUBBED' && ! printf '%s\n' "$out" | grep -qx 'LEAKED'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "extra lane 'tsx-lane' — skipped" \
   && ! printf '%s' "$out" | grep -q 'should-not-run'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "extra lane 'tsx-lane' » echo did-run"; then
  pass "(i15) AC-4: 'src/**/*.tsx' DOES match a nested 'src/a/App.tsx'"
else fail "(i15) expected the lane to run against a nested tsx change, got rc=$rc: $out"; fi

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
VROUND=0
write_review_verdict() { # write_review_verdict [verdict] [reviewed-head]
  VROUND=$((VROUND + 1))
  local head="${2:-$(git -C "$TREE" rev-parse HEAD)}"
  printf 'verdict=%s\nrun_id: r-review-1\nsession_id: sess-review-1\nrounds: %s\nreviewed_head: %s\n' \
    "${1:-approve}" "$VROUND" "$head" > "$VERDICT"
  commit_tree "review verdict ${1:-approve} (round $VROUND)"
}

reset_progress
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(j1) milestone-4 fails with no committed verdict record"
else fail "(j1) expected rc=1, got $rc: $out"; fi

write_review_verdict needs-work
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'reads verdict=needs-work, not verdict=approve'; then
  pass "(j2) milestone-4 fails on verdict=needs-work"
else fail "(j2) expected rc=1 on needs-work, got $rc: $out"; fi

# An approve record with no reconciliation key is unverifiable at the merge boundary.
printf 'verdict=approve\n' > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no run_id reconciliation key'; then
  pass "(j3) milestone-4 fails an approve record carrying no run_id reconciliation key"
else fail "(j3) expected rc=1 on a key-less approve, got $rc: $out"; fi

# ...and the session key is required for the same reason: without it the review session's
# ledger cannot be located, so nothing outside the record attests the review happened.
# reset_progress first — j1..j3 have already spent the 3-attempt budget, and a 4th red would
# hard-stop at rc=4 and prove nothing about the check under test.
reset_progress
printf 'verdict=approve\nrun_id: r-review-1\n' > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no session_id reconciliation key'; then
  pass "(j3b) milestone-4 fails an approve record carrying no session_id reconciliation key"
else fail "(j3b) expected rc=1 on a session-key-less approve, got $rc: $out"; fi

reset_progress
write_review_verdict
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(j4) milestone-4 passes on a committed verdict=approve with distinct review identities"
else fail "(j4) expected rc=0, got $rc: $out"; fi

# ---- (u) DECLARED freshness, SHA-keyed: the pre-patch-id fallback --------------------------
# `write_review_verdict` deliberately emits NO `reviewed_patch_id`, so every case in this block
# exercises the fallback path records written before that key still gate on — the (v) block
# covers the patch-id-keyed one. The distinction is asserted at (u5) rather than assumed: if the
# writer ever grew the key, these cases would silently migrate to the other arm and this block
# would assert nothing about the path it is named for.
#
# The MIGRATION arm. Every verdict record written before this key existed lands here, and it is
# refused rather than grandfathered: a remedy is always available (re-run the review round),
# so a transitional pass would be a waiver. Note this is a record that is otherwise complete —
# both reconciliation keys present, committed, and its commit IS the head — so the ONLY thing
# that can red it is the missing key.
reset_progress
printf 'verdict=approve\nrun_id: r-review-1\nsession_id: sess-review-1\n' > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no reviewed_head key'; then
  pass "(u1) milestone-4 fails an approve record carrying no reviewed_head key (the pre-key migration case)"
else fail "(u1) expected rc=1 on a head-less approve, got $rc: $out"; fi

# The gap the INFERRED arm cannot see, and the reason this key exists. The record is committed
# LAST — so `git log -1 -- <record>` finds the head, nothing but the record differs from it, and
# the inferred arm is green — but the head it NAMES is one commit older, which is exactly what
# happens when a fix lands between the review and the record's commit.
reset_progress
stale_head="$(git -C "$TREE" rev-parse HEAD)"
printf '# spec\n\n- AC-1: a thing\n- AC-2: landed while the review was running\n' > "$SPEC"
commit_tree "code lands between the review and the record"
write_review_verdict approve "$stale_head"
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'states it reviewed'; then
  pass "(u2) milestone-4 refuses a record naming an earlier head even though its own commit IS the head (inferred arm green, declared arm reds)"
else fail "(u2) expected rc=1 on a declared-stale record, got $rc: $out"; fi

# ...and a head that is not a commit here at all — the rebase/force-push-after-approval shape.
reset_progress
write_review_verdict approve 0000000000000000000000000000000000000000
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not a commit in this branch'; then
  pass "(u3) milestone-4 refuses a reviewed_head absent from the branch's history"
else fail "(u3) expected rc=1 on an unknown reviewed_head, got $rc: $out"; fi

reset_progress
write_review_verdict approve
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declaring reviewed_head'; then
  pass "(u4) milestone-4 passes a record naming the head it was written on top of"
else fail "(u4) expected rc=0 on a matching reviewed_head, got $rc: $out"; fi

# The block's own premise, asserted rather than assumed. The pass line above names the SHA arm;
# the patch-id arm prints `patch-id` instead — (v1). Without this, a writer that grew the key
# would move (u1)-(u4) onto the other arm and leave the fallback with no coverage at all, green
# the whole time.
if ! grep -q 'reviewed_patch_id' "$VERDICT" 2>/dev/null \
   && ! printf '%s' "$out" | grep -q 'patch-id'; then
  pass "(u5) the (u) records carry no reviewed_patch_id, so this block does gate on the SHA fallback"
else fail "(u5) the (u) block is no longer exercising the SHA fallback: $(cat "$VERDICT" 2>/dev/null)"; fi

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
cat > "$WORK/comments-closing.json" <<'EOF'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-7-lean-verdict.md" }]
EOF
echo '[]' > "$WORK/comments-none.json"

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-draft.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'still a draft'; then
  pass "(k1) milestone-5 fails a draft PR (D-27 requires a ready PR)"
else fail "(k1) expected rc=1 on a draft PR, got $rc: $out"; fi

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-nospec.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'does not link the committed spec'; then
  pass "(k2) milestone-5 fails a PR body that does not link the committed spec"
else fail "(k2) expected rc=1 on a spec-less body, got $rc: $out"; fi

seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'references the verdict record'; then
  pass "(k3) milestone-5 fails when no closing comment references the verdict record"
else fail "(k3) expected rc=1 on a missing closing comment, got $rc: $out"; fi

reset_progress
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not current'; then
  pass "(k4) milestone-5 fails when milestones 1-4 left no satisfied record"
else fail "(k4) expected rc=1 on a non-current progress file, got $rc: $out"; fi

# ...and that failure must be STABLE on re-run. This is the self-defeating-check class: a bare
# "does the progress file exist" assertion heals itself, because reporting the failure appends
# an attempt line and appending creates the file. Asserting the 1-4 records instead is stable —
# an M5 attempt line never satisfies M1-4.
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not current'; then
  pass "(k5) that failure is stable on re-run (the check does not heal itself)"
else fail "(k5) the progress-file check healed itself between runs — rc=$rc: $out"; fi

# Realistic state: milestones 1-4 have run and left their records.
seed_progress_1_to_4
out="$(gate 5 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(k6) milestone-5 passes with a ready PR, spec link, closing comment, and a progress file"
else fail "(k6) expected rc=0, got $rc: $out"; fi

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
if printf '%s' "$out" | grep -q '^run_id: unset$'; then
  pass "(m1) with no RUN_ID and no cache, the header stamps run_id: unset (unchanged default)"
else fail "(m1) expected 'run_id: unset' in the header, got: $out"; fi
if printf '%s' "$out" | grep -q '^model: unknown$'; then
  pass "(m1b) ensure_progress_file() stamps model: unknown when LEAN_RUN_MODEL is unset (#347)"
else fail "(m1b) expected 'model: unknown' in the header, got: $out"; fi

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
if printf '%s' "$out" | grep -q '^run_id: selftest-run-306$'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(n1) milestone-4 refuses a verdict carrying the build run's run_id"
else fail "(n1) expected rc=1 on a build-authored verdict, got $rc: $out"; fi

seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-review-1\nsession_id: sess-build-1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'names the BUILD session'; then
  pass "(n2) milestone-4 refuses a verdict whose session_id is the build session's"
else fail "(n2) expected rc=1 on a build-session verdict, got $rc: $out"; fi

# The cache arm. The progress header records no usable build run id, so ONLY the cache file
# can supply it — which is exactly the state a review session that re-exported nothing is in.
seed_build_progress unset sess-build-1
mkdir -p "$(dirname "$RUN_ID_CACHE")"; printf 'r-cached-1' > "$RUN_ID_CACHE"
printf 'verdict=approve\nrun_id: r-cached-1\nsession_id: sess-review-1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$VERDICT"; commit_tree
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(n3) milestone-4 refuses an identity that resolves from the build run-id CACHE file"
else fail "(n3) expected rc=1 on a cache-resolved identity, got $rc: $out"; fi
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
out="$(gate all 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
o_sum_after="$(cksum < "$VERDICT")"; o_mt_after="$(mtime_of "$VERDICT")"
if [ "$rc" -eq 0 ] && [ -n "$o_mt_before" ] && [ "$o_sum_before" = "$o_sum_after" ] && [ "$o_mt_before" = "$o_mt_after" ]; then
  pass "(o) a full 'all' sweep leaves the verdict record byte- and mtime-identical"
else fail "(o) sweep rc=$rc; cksum $o_sum_before -> $o_sum_after; mtime '$o_mt_before' -> '$o_mt_after': $out"; fi

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
  ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_M3" LEAN_PROGRESS_FILE="$PROG" \
    bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 )
}

reset_progress
rm -f "$MARKER"
write_review_verdict needs-work
out="$(gate_m3 all 7)"; rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$MARKER" ] && printf '%s' "$out" | grep -q 'reads verdict=needs-work'; then
  pass "(x1) AC-1: 'all' reports the milestone-4 refusal without running milestone-3's body"
else fail "(x1) expected rc!=0, no marker, needs-work message — rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi

# AC-3: BOTH cheap assertions broken (spec AC-less AND verdict needs-work) are reported
# together in ONE pre-pass, not just the first a naive sequential loop would reach.
cp "$SPEC" "$WORK/held-spec-x.md"
printf '# spec\n\nno AC token here\n' > "$SPEC"
out="$(gate_m3 all 7)"; rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q 'no numbered AC-n' \
   && printf '%s' "$out" | grep -q 'reads verdict=needs-work'; then
  pass "(x2) AC-3: the pre-pass reports BOTH cheap failures from one 'all' run"
else fail "(x2) expected both milestone-1 and milestone-4 pre-pass failures, got rc=$rc: $out"; fi
cp "$WORK/held-spec-x.md" "$SPEC"

# AC-2: a clean pre-pass (spec ok, verdict approve+fresh) still runs milestone 3 for real — the
# marker now appears, proving the pre-pass is not a way to skip the green gate.
reset_progress
rm -f "$MARKER"
write_review_verdict
out="$(gate_m3 all 7 --pr-file "$WORK/pr-ready.json" --comments-file "$WORK/comments-closing.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ -e "$MARKER" ]; then
  pass "(x3) AC-2: a clean pre-pass still runs milestone-3's real body (green gate not skipped)"
else fail "(x3) expected rc=0 and the marker present, got rc=$rc marker=$([ -e "$MARKER" ] && echo present || echo absent): $out"; fi
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'region OR-1' && printf '%s' "$out" | grep -q 'pause-and-ask'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'region OR-1'; then
  pass "(y3b) a BOT-authored comment naming the region does not resolve it"
else fail "(y3b) expected rc=1 despite a bot comment mentioning OR-1, got $rc: $out"; fi

# ...and a comment naming a DIFFERENT, merely similar id (OR-10) must not resolve OR-1 — the
# word-boundary the id match is built on.
reset_progress
out="$(gate 1 7 --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-or10-boundary.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'region OR-1'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'region OR-1'; then
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
if [ "$rc" -eq 1 ] && [ "$n" -eq 1 ] && printf '%s' "$out" | grep -q 'regions OR-1, OR-3'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'region OR-1'; then
  pass "(y8) AC-18: an intent-gap record reading 'ratified: no' does not clear the region"
else fail "(y8) expected rc=1 — an unratified intent-gap record must not resolve OR-1, got $rc: $out"; fi
rm -f "$GAP"; commit_tree "remove unratified intent-gap fixture"
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'this IS the build session'; then
  pass "(p1) verdict refuses when the invoking session is the build session"
else fail "(p1) expected rc=1 from the build session, got $rc: $out"; fi
[ -f "$VERDICT" ] && fail "(p1b) a refused verdict call still wrote the record" \
  || pass "(p1b) a refused verdict call writes nothing"

out="$(verdict_cmd sess-review-9 '' --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no review identity provisioned'; then
  pass "(p2) verdict refuses with no review identity rather than inheriting the build's"
else fail "(p2) expected rc=1 with no RUN_ID, got $rc: $out"; fi

out="$(verdict_cmd sess-review-9 r-build-1 --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "IS the build run's"; then
  pass "(p3) verdict refuses a review identity equal to the build run's"
else fail "(p3) expected rc=1 on a colliding identity, got $rc: $out"; fi

seed_build_progress r-build-1 unset
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no session id'; then
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
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'pr must be a positive integer'; then
  pass "(r1) verdict rejects a non-numeric --pr instead of echoing it into the record"
else fail "(r1) expected rc=2 on a non-numeric --pr, got $rc: $out"; fi
[ -f "$VERDICT" ] && fail "(r1b) a rejected --pr still wrote the record" \
  || pass "(r1b) a rejected --pr writes nothing"

out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve --rounds 0)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'rounds must be a positive integer'; then
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
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'pr must be a positive integer'; then
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
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'reads verdict=needs-work'; then
    pass "(s) a needs-work record whose summary quotes verdict=approve is still refused"
  else fail "(s) expected rc=1 on a needs-work record quoting the token, got $rc: $out"; fi
fi
rm -f "$REVIEW_CACHE"

# ---- (t) FRESHNESS: the verdict must cover the tree it is read against ----------------------
# Four of the five milestones re-derive their answer from the current tree on every sweep,
# which is what makes `satisfied` a record rather than a cache. Milestone 4 cannot — its
# evaluation is reading a file — so the file is bound to a tree instead. Without this the
# needs-work loop's ordinary shape ("verdict, then more commits") certifies code no reviewer
# saw, and the PR that introduced the separation demonstrated it on itself.
seed_build_progress r-build-1 sess-build-1
write_review_verdict
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(t1) milestone-4 passes when the verdict's commit IS the head"
else fail "(t1) expected rc=0 on a fresh verdict, got $rc: $out"; fi

# ONLY a later commit is added — everything the other arms check is left exactly as it was, so
# a green here would mean the freshness link is not carrying the check at all.
printf '# spec\n\n- AC-1: a thing\n- AC-2: added after the review\n' > "$SPEC"
commit_tree "code lands after the verdict"
seed_build_progress r-build-1 sess-build-1
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'a verdict does not cover code it never saw'; then
  pass "(t2) milestone-4 refuses a verdict that predates a later code commit"
else fail "(t2) expected rc=1 on a stale verdict, got $rc: $out"; fi

# ...and a new review round clears it, so (t2) is a check with a remedy rather than a wall.
seed_build_progress r-build-1 sess-build-1
write_review_verdict
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(t3) a new review round over the current head clears it"
else fail "(t3) expected rc=0 after a fresh round, got $rc: $out"; fi

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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'has uncommitted changes'; then
  pass "(t4) milestone-4 refuses a committed record that was then edited locally"
else fail "(t4) expected rc=1 on a dirty record, got $rc: $out"; fi
git -C "$TREE" checkout -- "$VERDICT" >/dev/null 2>&1

# (t5) never committed at all. Driven on a DIFFERENT issue key, because `git log -- <path>`
# answers "has this path ever been committed" — deleting #7's record would leave the deletion
# commit behind and still resolve. #8's record has no history, which is the state a real first
# review round is in before it commits.
seed_build_progress r-build-1 sess-build-1
printf 'verdict=approve\nrun_id: r-review-9\nsession_id: sess-review-9\nrounds: 1\nreviewed_head: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" > "$TREE/docs/plans/acme-8-lean-verdict.md"
out="$(gate 4 8)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'was never committed'; then
  pass "(t5) milestone-4 refuses a verdict record that was never committed at all"
else fail "(t5) expected rc=1 on an untracked record, got $rc: $out"; fi
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
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "unknown tracker.type"; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no 'Closes [$JKEY]'"; then
  pass "(n3) jira milestone-5 fails a body with no sectioned ticket reference"
else fail "(n3) expected rc=1 on a key-less body, got $rc: $out"; fi

seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-noverdict.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'does not reference the verdict record'; then
  pass "(n4) jira milestone-5 fails a body that does not reference the verdict record"
else fail "(n4) expected rc=1 on a verdict-less body, got $rc: $out"; fi

seed_progress_1_to_4_at "$PROG_J"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 5 "$JKEY" --pr-file "$WORK/pr-jira-unsectioned.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no 'Closes [$JKEY]'"; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'still a draft'; then
  pass "(n6) jira milestone-5 still rejects a draft PR (D-27 holds for both adapters)"
else fail "(n6) expected rc=1 on a jira draft PR, got $rc: $out"; fi

# AC-3: the github default is ASSERTED, not assumed. Same jira-shaped body, under a config
# with tracker.type ABSENT and under one that spells it out — both must take the github arm,
# which this body cannot satisfy.
seed_progress_1_to_4_at "$WORK/p-default.md"
out="$(gate_cfg "$CFG" "$WORK/p-default.md" 5 "$JKEY" --pr-file "$WORK/pr-jira-ok.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no 'Closes #$JKEY'"; then
  pass "(n7) with tracker.type ABSENT the github arm runs — a jira-shaped body is rejected"
else fail "(n7) expected the github Closes-# failure with tracker.type absent, got $rc: $out"; fi

seed_progress_1_to_4_at "$WORK/p-explicit.md"
out2="$(gate_cfg "$CFG_GITHUB" "$WORK/p-explicit.md" 5 "$JKEY" --pr-file "$WORK/pr-jira-ok.json" --comments-file "$WORK/comments-none.json")"; rc2=$?
if [ "$rc2" -eq "$rc" ] && printf '%s' "$out2" | grep -qF "no 'Closes #$JKEY'"; then
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
        CLAUDE_CODE_SESSION_ID=sess-jira bash "$GATE" entry "$JKEY" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no queue label to confirm'; then
  pass "(n11) entry prints the jira adapter note — step 1's label reject has no jira meaning"
else fail "(n11) expected the jira entry note, got rc=$rc: $out"; fi

out="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-jira bash "$GATE" entry 7 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'no queue label to confirm'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no 'Closes [$JKEY]'"; then
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

# (n16) AC-17: milestone 1 — the one milestone the jira arm reaches outside milestone 5, and the
# only case in this file that drives it. `check_pause_and_ask` opens with a jira short-circuit
# that is load-bearing, not defensive: the function's tracker read is `gh issue view <JIRA-KEY>`,
# which cannot succeed, and its failure branch PRINTS a reason — a printed reason IS the refusal.
# So deleting the short-circuit refuses milestone 1 for the entire jira lane. The issue fixture
# below carries an unresolved pause-and-ask region precisely so rc=0 proves the check was
# SKIPPED rather than merely having found nothing to fire on.
mkdir -p "$TREE/docs/plans"
printf '# lean spec — %s\n\n- **AC-1**: the jira arm reaches milestone 1.\n' "$JKEY" > "$TREE/$JSPEC_REL"
commit_tree "jira spec fixture"
rm -f "$PROG_J"; attest_at "$TREE" "$CFG_JIRA" "$PROG_J" "$JKEY"
out="$(gate_cfg "$CFG_JIRA" "$PROG_J" 1 "$JKEY" --issue-file "$WORK/issue-or1-paa.json" --comments-file "$WORK/comments-none.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(n16) AC-17: jira milestone 1 skips the pause-and-ask check — an unresolved region does not refuse"
else fail "(n16) expected rc=0 under tracker.type: jira despite an unresolved OR-1, got $rc: $out"; fi
rm -f "$TREE/$JSPEC_REL"; commit_tree "remove jira spec fixture"

rm -f "$TREE/.claude/pipeline-state/$JKEY-run-id"

# ---- (v) DECLARED freshness, PATCH-ID keyed: a rebase must not void a verdict ---------------
# LAST in the file on purpose: (v3) rewrites the fixture branch's history with a real rebase, and
# every case above reasons about commits it made itself.
#
# The record is produced by the REAL `verdict` writer rather than a printf, so the id these cases
# compare against is derived by the production code under test. A hand-written expectation could
# only pin whatever formula the suite author copied.
seed_build_progress r-build-1 sess-build-1
rm -f "$VERDICT" "$REVIEW_CACHE" "$RUN_ID_CACHE"
printf 'reviewer prose, round 1\n' > "$WORK/v-summary.md"
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve --summary-file "$WORK/v-summary.md")"; rc=$?
[ "$rc" -eq 0 ] || fail "(v0) the verdict writer refused, so the (v) block has no record to gate: $out"
commit_tree "review session commits its patch-id-keyed record"

out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qE 'reviewed_patch_id: [0-9a-f]{6}' "$VERDICT" 2>/dev/null \
   && printf '%s' "$out" | grep -q 'patch-id'; then
  pass "(v1) the review role stamps reviewed_patch_id and milestone-4's pass line names the patch-id arm it gated on"
else fail "(v1) expected a patch-id-keyed record and pass line, rc=$rc: $out
$(cat "$VERDICT" 2>/dev/null)"; fi

# AC-4: the EXCLUSION. The writer resolves the id at a head that does not yet carry the record;
# every reader recomputes it at a head that does. Excluding the record path on both sides is what
# makes those two agree — drop it on either and the arm reds on every correct record.
#
# Driven behaviorally, so it cannot be satisfied by a copy of the formula: the record's own bytes
# change and are committed, and milestone 4 must still pass. If the path were in the measured
# range, this edit alone would move the id.
reset_progress
printf 'reviewer prose, amended after the fact\n' >> "$VERDICT"
commit_tree "the record's own bytes change"
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'patch-id'; then
  pass "(v2) editing the verdict record itself does not move the patch identity — the exclusion holds on both sides"
else fail "(v2) expected rc=0 after editing the record, got $rc: $out"; fi

# THE headline case. A rebase rewrites every commit SHA on the branch and changes not one
# reviewed line, and the SHA keying refused it — in a fresh checkout the pre-rebase object does
# not exist at all, so the refusal was unavoidable rather than merely wrong.
#
# The rebase is REAL. Simulating one would prove nothing about the property being claimed, which
# is a property of git's replay. The base advances by a commit carrying actual content, because a
# same-tree base would leave the pre- and post-rebase trees identical and the old SHA arm would
# pass too — a vacuous case dressed as a regression guard. Non-vacuity is asserted, not argued.
reset_progress
v_branch="$(git -C "$TREE" symbolic-ref --short HEAD 2>/dev/null)"
v_orphaned_head="$(git -C "$TREE" rev-parse HEAD)"
git -C "$TREE" branch -f v-base refs/remotes/origin/main >/dev/null 2>&1
git -C "$TREE" checkout -q v-base 2>/dev/null
printf 'the base moved while the review was in flight\n' > "$TREE/base-moved.txt"
git -C "$TREE" add base-moved.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'base advances' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main v-base
git -C "$TREE" checkout -q "$v_branch" 2>/dev/null
if git -C "$TREE" rebase -q v-base >/dev/null 2>&1; then
  v_rebase_ok=1
else
  v_rebase_ok=0
  git -C "$TREE" rebase --abort >/dev/null 2>&1
fi
# Non-vacuity: under SHA keying this exact state reds. The pre-rebase commit is still an object
# here (a local rebase does not gc it), so the `cat-file -e` arm would not fire — but its TREE
# now differs from the head by the commit the base advanced with, so the `git diff <reviewed_head>
# HEAD` arm would. If that diff is empty the case is measuring nothing.
v_sha_arm_would_red="$(git -C "$TREE" diff --name-only "$v_orphaned_head" HEAD 2>/dev/null)"
if [ "$v_rebase_ok" -eq 1 ] && [ "$(git -C "$TREE" rev-parse HEAD)" != "$v_orphaned_head" ] \
   && [ -n "$v_sha_arm_would_red" ]; then
  pass "(v3a) the fixture really was rebased onto a moved base, and the SHA arm would red on it"
else fail "(v3a) the rebase did not take (ok=$v_rebase_ok, sha-arm-diff='$v_sha_arm_would_red') — (v3) would assert nothing"; fi

out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'patch-id'; then
  pass "(v3) milestone-4 passes after a rebase that replays the branch unchanged, though the declared head is no longer this branch's"
else fail "(v3) expected rc=0 after a clean rebase, got $rc: $out"; fi

# D-5 vacuity, READ side. `git patch-id` prints NOTHING for an empty diff, so two failed
# computations compare EQUAL — an unguarded reader prints its ✓ having hashed nothing. This
# config names a base branch with no remote-tracking ref, so the merge-base is unresolvable.
reset_progress
CFG_NOBASE="$WORK/config-nobase.json"
jq '.topology.repos.acme.baseBranch = "no-such-base"' "$CFG" > "$CFG_NOBASE"
[ "$(jq -r '.topology.repos.acme.baseBranch' "$CFG_NOBASE" 2>/dev/null)" = "no-such-base" ] \
  || fail "(v5-fixture) the no-base config was not built — (v5)/(v6) would run against the real base"
out="$(gate_cfg "$CFG_NOBASE" "$PROG" 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'cannot compute this branch'; then
  pass "(v5) an unresolvable base is a milestone-4 refusal, not a pass over two empty patch ids"
else fail "(v5) expected rc=1 on an unresolvable base, got $rc: $out"; fi

# D-5 vacuity, WRITE side, and the sharper half. A record written with the key silently OMITTED
# reads downstream as "written before the key existed" and falls through to the SHA path — so a
# missing base here would quietly re-introduce the rebase refusal, at review time, invisibly.
#
# seed_build_progress is load-bearing, not tidy-up: (v5) above ran after reset_progress, so the
# gate RE-created the progress file and stamped `session_id: unset` into it. cmd_verdict's FIRST
# authorship refusal fires on exactly that, two checks before the patch-id arm this case names —
# so without the seed (v6) passes for the wrong reason where an ambient session id happens to
# leak in, and fails outright where it does not. Seeding a real build identity makes the writer
# reach its own arm on every machine.
seed_build_progress r-build-1 sess-build-1
rm -f "$REVIEW_CACHE"
out="$( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOBASE" LEAN_PROGRESS_FILE="$PROG" \
        CLAUDE_CODE_SESSION_ID=sess-review-9 RUN_ID=r-review-9 \
        bash "$GATE" verdict 7 --pr 12 --verdict approve 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'cannot compute the branch'; then
  pass "(v6) the verdict writer refuses an unresolvable base rather than omitting the key and degrading to the SHA path"
else fail "(v6) expected rc=2 from the writer on an unresolvable base, got $rc: $out"; fi

# ...and the arm is still a GATE. A commit changing the branch after the review moves the patch
# identity. Without this, (v3) reads as "the arm was disabled" rather than "the arm was re-keyed".
#
# Built in the shape where the patch-id arm is the ONLY one that can red: the record is written
# at head A and lands in the SAME commit as the code change, so `git log -1 -- <record>` finds
# the head, nothing differs from it, and the INFERRED arm is green. A code commit made after the
# record's own commit would red on inference first and prove nothing about this arm.
seed_build_progress r-build-1 sess-build-1
rm -f "$REVIEW_CACHE"
out="$(verdict_cmd sess-review-9 r-review-9 --pr 12 --verdict approve)"; rc=$?
[ "$rc" -eq 0 ] || fail "(v4-fixture) the writer refused, so (v4) has no stale record to gate: $out"
printf '# spec\n\n- AC-1: a thing\n- AC-2: landed while the review was running\n' > "$SPEC"
commit_tree "code and the record land together"
out="$(gate 4 7)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'reviewed patch'; then
  pass "(v4) milestone-4 refuses once a commit changes the branch's patch after the review, with the inferred arm green"
else fail "(v4) expected rc=1 on a moved patch identity, got $rc: $out"; fi

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
   && printf '%s' "$out" | grep -q 'bash 3.2 compatible' \
   && ! printf '%s' "$out" | grep -q '^set -uo pipefail'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FULL range' \
   && printf '%s' "$out" | grep -q 'untouched.txt' && printf '%s' "$out" | grep -q 'refixed.txt'; then
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
   && printf '%s' "$out" | grep -q 'chain ROOT'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheriting the coverage of patch' \
   && printf '%s' "$out" | grep -q 'refixed.txt' \
   && ! printf '%s' "$out" | grep -q 'untouched.txt'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'matches no earlier verdict record committed on this branch' \
   && printf '%s' "$out" | grep -q 'round 2 declares'; then
  pass "(x6) milestone-4 refuses an unresolvable inheritance link, naming the round that declared it"
else fail "(x6) expected rc=1 naming round 2, got $rc: $out"; fi

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
   && printf '%s' "$out" | grep -q 'inherits nothing'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'round 2 declares' \
   && ! printf '%s' "$out" | grep -q 'round 3 declares'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheriting 1 verified earlier round'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'covering the whole branch diff on its own' \
   && ! printf '%s' "$out" | grep -q 'matches no earlier verdict record'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'covering the whole branch diff on its own' \
   && ! printf '%s' "$out" | grep -q 'inheriting 1 verified earlier round'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'uncommitted changes' \
   && ! printf '%s' "$out" | grep -q 'matches no earlier verdict record'; then
  pass "(z4) an uncommitted round-2 record is refused for being uncommitted, not for a chain its own state broke"
else fail "(z4) expected the uncommitted refusal without a chain diagnostic, got rc=$rc: $out"; fi
zcommit "round 2's record"
out="$(zgate 4 12)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheriting 1 verified earlier round'; then
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
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheriting 1 verified earlier round'; then
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

# The arg-asserting stub. It exits NONZERO on an unsubstituted `{route}`/`{state}`/`{out}`, so a
# gate that forwarded the template verbatim reds instead of producing a plausible screenshot —
# the assertion AC-3 names, made by the harness rather than by a grep over the gate's stdout.
# Its bytes are a function of route+state, which is what makes two declared states distinguish
# themselves; `blind` mode is the same harness ignoring {state}, i.e. failure class (2).
cat > "$DSTUB" <<EOSTUB
#!/usr/bin/env bash
CALLS="$DCALLS"
MODEF="$DMODE"
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
exit 0
EOSTUB

dcfg() { # dcfg <liveRender-command-or-empty> [cwd]
  local cmd="${1:-}" cwd="${2:-}" lr=""
  if [ -n "$cmd" ]; then
    lr=", \"liveRender\": { \"command\": \"$cmd\"$([ -n "$cwd" ] && printf ', "cwd": "%s"' "$cwd") }"
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
DSTUB_CMD="bash $DSTUB --route {route} --state {state} --out {out}"

dcommit() {
  git -C "$DTREE" add -A >/dev/null 2>&1
  git -C "$DTREE" commit -q --allow-empty -m "${1:-fixture}" >/dev/null 2>&1
}
dgate() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$DCFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ); }
# The UNARMED reader: the same tree and the same spec, read through a config with no design axis.
# That pairing is the AND→OR mutant's executioner — under OR the section alone would arm.
dgate_nodesign() { ( unset RUN_ID CLAUDE_CODE_SESSION_ID; cd "$DTREE" \
  && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$DPROG" bash "$GATE" --issue-file "$ISSUE_NOREGIONS" "$@" 2>&1 ); }
dverdict() { # dverdict <session-id> <run-id> [args...]
  local sid="$1" rid="$2"; shift 2
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
    echo "Handoff: https://design.example.invalid/file/abc"
    echo ""
    echo "| RS-n | route | state (what must be visible) | AC refs |"
    echo "| --- | --- | --- | --- |"
    echo "| RS-1 | prospects | default | AC-1 |"
    echo "| RS-2 | prospects | filters expanded | AC-1 |"
  } > "$DSPEC"
}

dmode ok
dcfg "$DSTUB_CMD"
dcommit "base"
git -C "$DTREE" update-ref refs/remotes/origin/main HEAD
printf 'the work\n' > "$DTREE/subject.txt"

# ---- (dz) AC-1: the milestone-1 arming forms --------------------------------------------
# (dz1) provider configured, no section at all.
dreset
printf '# spec\n\n- AC-1: the thing\n' > "$DSPEC"
dcommit "a spec with no Design section"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'must carry a "## Design" section'; then
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
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'ARMED'; then
  pass "(dz3) a '## Design' section in a repo with no design.provider arms NOTHING (the AND half of D-8)"
else fail "(dz3) expected an unarmed pass, rc=$rc: $out"; fi

# (dz4) and the same spec under the design config IS armed.
dreset
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'design lane ARMED'; then
  pass "(dz4) the same spec under a configured provider arms the lane"
else fail "(dz4) expected an armed pass, rc=$rc: $out"; fi

# (dz2) the explicit-empty form.
dreset
printf '# spec\n\n- AC-1: the thing\n\n## Design\n\nDesign: none — no FE surface in this ticket.\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'disarmed'; then
  pass "(dz2) 'Design: none — <reason>' is a conscious per-ticket disarm, not a defect"
else fail "(dz2) expected a disarmed pass, rc=$rc: $out"; fi

# (dz5) a disarm with no reason is not the form. An undocumented disarm is indistinguishable
# from an omission at review time, which is what the review-side blocker has to judge.
dreset
printf '# spec\n\n- AC-1: the thing\n\n## Design\n\nDesign: none\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'states no reason'; then
  pass "(dz5) a bare 'Design: none' is refused — the disarm is a decision and must carry one"
else fail "(dz5) expected the no-reason refusal, rc=$rc: $out"; fi

# (dz6) render states declared, no handoff link: the review session would have nothing to score
# the screenshots against.
dreset
printf '# spec\n\n- AC-1: x\n\n## Design\n\n| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n| RS-1 | p | default | AC-1 |\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no provider handoff link'; then
  pass "(dz6) an armed section with no handoff link is refused at authoring time"
else fail "(dz6) expected the missing-link refusal, rc=$rc: $out"; fi

# (dz7) a section that is neither armed nor disarmed — the shape that produced failure class (2).
dreset
printf '# spec\n\n- AC-1: x\n\n## Design\n\nHandoff: https://design.example.invalid/f/a\n' > "$DSPEC"
out="$(dgate 1 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'declares no render state'; then
  pass "(dz7) a section naming neither a render state nor a disarm is refused"
else fail "(dz7) expected the no-render-state refusal, rc=$rc: $out"; fi

# ---- (dr) AC-3: the render pass ----------------------------------------------------------
# (dr7) the template must carry {out} — there is otherwise nowhere for a screenshot to land.
dreset
dspec_armed
dcommit "the armed spec, restored"
dcfg "bash $DSTUB --route {route} --state {state}"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no {out} placeholder'; then
  pass "(dr7) a liveRender.command with no {out} reds milestone 3"
else fail "(dr7) expected the missing-{out} refusal, rc=$rc: $out"; fi

# (dr6) {state} is required only because a NON-DEFAULT state is declared. Without it the harness
# would screenshot the default view for every row — failure class (2), passing every other check.
dreset
dcfg "bash $DSTUB --route {route} --out {out}"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no {state} placeholder'; then
  pass "(dr6) a non-default RS row with no {state} in the command reds milestone 3"
else fail "(dr6) expected the missing-{state} refusal, rc=$rc: $out"; fi

# ...and the same command is ACCEPTED when every declared state is the default one, so (dr6)
# turns on the declared state and not merely on the placeholder's absence.
dreset
{
  echo "# spec"; echo ""; echo "- AC-1: x"; echo ""; echo "## Design"; echo ""
  echo "Handoff: https://design.example.invalid/f/a"; echo ""
  echo "| RS-n | route | state | AC refs |"; echo "| --- | --- | --- | --- |"
  echo "| RS-1 | prospects | default | AC-1 |"
} > "$DSPEC"
dcommit "a single default-state spec"
out="$(dgate 3 55)"; rc=$?
# The POSITIVE half: the run reached the render itself. Asserting only the refusal's absence
# would also pass if the gate had redded one line earlier for some unrelated reason, which is
# how a "the check did not fire" case quietly stops asserting anything.
if ! printf '%s' "$out" | grep -q 'no {state} placeholder' \
   && printf '%s' "$out" | grep -q 'milestone-3: render RS-1'; then
  pass "(dr6b) a default-only render table needs no {state} — the refusal is keyed on the declared state, and the run reaches the render"
else fail "(dr6b) expected the template check to pass through to the render, rc=$rc: $out"; fi

# (dr11) a repeated RS id. The id is the screenshot's filename, so the second render overwrites
# the first and the manifest ends up with two rows backed by one file — evidence that fails the
# reviewer's hash check for a reason the spec author never sees.
dreset
{
  echo "# spec"; echo ""; echo "- AC-1: x"; echo ""; echo "## Design"; echo ""
  echo "Handoff: https://design.example.invalid/f/a"; echo ""
  echo "| RS-n | route | state | AC refs |"; echo "| --- | --- | --- | --- |"
  echo "| RS-1 | prospects | default | AC-1 |"
  echo "| RS-1 | prospects | filters expanded | AC-1 |"
} > "$DSPEC"
dcommit "a spec repeating an RS id"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "twice"; then
  pass "(dr11) a repeated RS id reds — one id, one screenshot file, no silently overwritten evidence"
else fail "(dr11) expected the duplicate-id refusal, rc=$rc: $out"; fi

# (dr10) cwd naming a repo this run does not host. The lean lane works one worktree; the honest
# answer is to name the limitation, not to render the wrong tree.
dreset
dspec_armed
dcommit "the armed spec, restored"
dcfg "$DSTUB_CMD" "fe"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'run the lean lane from the repo that owns the render harness'; then
  pass "(dr10) design.liveRender.cwd naming a non-host topology repo reds with the limitation named"
else fail "(dr10) expected the cwd limitation refusal, rc=$rc: $out"; fi

# (dr8) the check-ignore RED. PNG bytes must never enter history, and the refusal prints the
# exact line to add rather than leaving the operator to derive it.
dreset
dcfg "$DSTUB_CMD"
printf 'docs/nothing\n' > "$DTREE/.gitignore"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not git-ignored' \
   && printf '%s' "$out" | grep -qF '.claude/lean-renders/'; then
  pass "(dr8) an un-ignored render output path reds, naming the exact .gitignore line to add"
else fail "(dr8) expected the check-ignore refusal with the remedy line, rc=$rc: $out"; fi

# (dr9) and the GREEN half, restored: the same assertion passes once the path is ignored, so
# (dr8) turns on the ignore rule and not on something incidental to that tree.
printf '.claude/\n' > "$DTREE/.gitignore"
dcommit "restore the ignore rule"
dreset
out="$(dgate 3 55)"; rc=$?
if ! printf '%s' "$out" | grep -q 'not git-ignored'; then
  pass "(dr9) the same path passes the ignore assertion once .gitignore covers it"
else fail "(dr9) the check-ignore refusal survived the ignore rule: $out"; fi

# (dr5) a harness that exits nonzero. BLOCKING: there is no degraded state to assert, which is
# the whole of failure class (1) — the run stops here.
dreset
dmode fail
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'render RS-1' && printf '%s' "$out" | grep -q 'failed (rc=7)' \
   && [ ! -f "$DMANIFEST" ]; then
  pass "(dr5) a nonzero render exit reds milestone 3 and writes no manifest"
else fail "(dr5) expected the render failure refusal and no manifest, rc=$rc: $out"; fi

# (dr4) a harness that exits 0 and writes nothing. The exit code alone would have called this a
# pass — the second half of failure class (1).
dreset
dmode empty
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'wrote no PNG bytes' && [ ! -f "$DMANIFEST" ]; then
  pass "(dr4) a zero-byte screenshot reds even though the harness exited 0"
else fail "(dr4) expected the zero-byte refusal, rc=$rc: $out"; fi

# (dr3) THE {state}-BLIND HARNESS — failure class (2) exactly. Two declared states, one view
# rendered twice: every other assertion here passes, and only the hash collision separates it
# from an honest two-state render.
dreset
dmode blind
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'hash identically' && [ ! -f "$DMANIFEST" ]; then
  pass "(dr3) two declared states rendering byte-identically red — the {state}-blind-harness detector"
else fail "(dr3) expected the identical-hash refusal, rc=$rc: $out"; fi

# (dr1) THE HAPPY PATH. Two rows, two distinct PNGs, two manifest rows — and the manifest reds
# until it is committed, because the receipt sits inside reviewed_patch_id and a verdict must
# bind to evidence that is actually on the branch.
dreset
dmode ok
rm -f "$DCALLS" "$DMANIFEST"
out="$(dgate 3 55)"; rc=$?
D_ROWS="$(grep -cE '^\| RS-[0-9]+ \|' "$DMANIFEST" 2>/dev/null)" || D_ROWS=0
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'commit it and re-run' \
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
  echo "Handoff: https://design.example.invalid/file/abc"; echo ""
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
   && printf '%s' "$out" | grep -q 'not re-rendering'; then
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
   && printf '%s' "$out" | grep -q 'this round is approved'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'already armed it'; then
  pass "(dl2) disarming after the lane armed reds milestone 1"
else fail "(dl2) expected the mid-run-disarm refusal at milestone 1, rc=$rc: $out"; fi
out="$(dgate 3 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'already armed it'; then
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
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "must be 'pass', 'fail' or 'not-applicable'"; then
  pass "(fd1) --fidelity enum-validates"
else fail "(fd1) expected an enum refusal, rc=$rc: $out"; fi

# (fd4) fail x approve is a contradiction: a design failure is a blocker and any blocker is
# needs-work. Refused at the writer rather than only at milestone 4, where it costs the round.
out="$(dverdict sess-review-d r-review-d --pr 55 --verdict approve --fidelity fail)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'cannot accompany'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not fidelity=pass'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not fidelity=pass'; then
  pass "(fd3) a 'fidelity: pass' in the record's BODY is not a score — the read is anchored to the header"
else fail "(fd3) expected the armed refusal despite the body value, rc=$rc: $out"; fi

# (fd5b) and the same record scored `pass` in its header passes, so (fd5)/(fd3) turn on the
# header value and nothing else.
dreset
out="$(dverdict sess-review-d3 r-review-d3 --pr 55 --verdict approve --fidelity pass)"; rc=$?
dcommit "a record scoring fidelity pass"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(fd5b) an armed run passes milestone 4 on a header-scored 'fidelity: pass'"
else fail "(fd5b) expected an armed milestone-4 pass, rc=$rc: $out"; fi

# (dm1) D-10's BACKSTOP. Everything else here is fresh — the verdict is the last commit, so both
# freshness arms are green — and only the receipt is stale, which is precisely a reviewer who
# scored round-1 screenshots against round-2 code and then committed an honest record.
printf 'a fix lands after the render\n' > "$DTREE/subject.txt"
dcommit "a fix, leaving the receipt behind"
dreset
out="$(dverdict sess-review-d4 r-review-d4 --pr 55 --verdict approve --fidelity pass)"; rc=$?
dcommit "an honest record on the new head, scored against the OLD screenshots"
dreset
out="$(dgate 4 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'renders from' \
   && ! printf '%s' "$out" | grep -q 'file(s) changed after it'; then
  pass "(dm1) a stale render receipt reds milestone 4 on a tree whose verdict freshness is green"
else fail "(dm1) expected the stale-receipt refusal alone, rc=$rc: $out"; fi

# (fd6) the UNARMED transition allowance: a record with no fidelity key at all — every record
# written before this key existed — still passes. Read through the no-design config, which is
# every consumer with no design axis.
dreset
out="$(dgate 3 55)"; rc=$?
dcommit "the re-rendered receipt for the new head"
dreset
out="$(dverdict sess-review-d5 r-review-d5 --pr 55 --verdict approve --fidelity pass)"; rc=$?
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
out="$(dverdict sess-review-d6 r-review-d6 --pr 55 --verdict approve --fidelity pass)"; rc=$?
dcommit "a record claiming a fidelity its spec could not have armed"
dreset
out="$(dgate_nodesign 4 55)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'arms no design render lane'; then
  pass "(fd7) an unarmed run refuses a fidelity value other than not-applicable"
else fail "(fd7) expected the unarmed non-applicable refusal, rc=$rc: $out"; fi

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
  ( unset RUN_ID; cd "$PTREE" && CLAUDE_CODE_SESSION_ID="$PSID" SECOND_SHIFT_CONFIG="$CFG" \
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
   && grep -qF "/.claude/audit/$PSID.jsonl | lines=2 | session=$PSID" "$PPROG"; then
  pass "(ea1) entry records one row carrying the resolved ledger path, its line count and the session id"
else fail "(ea1) expected one full entry row, rc=$rc: $(cat "$PPROG" 2>/dev/null)"; fi

out="$(pgate entry 8)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(pcount '| entry | ledger=')" -eq 1 ]; then
  pass "(ea2) a second entry call is idempotent — the row is not duplicated"
else fail "(ea2) expected still exactly one row, rc=$rc, count=$(pcount '| entry | ledger=')"; fi

# The refusal, on a progress file that has everything EXCEPT the row. Seeding a full header is
# the point: "the file is missing" and "the run never attested" must not be the same test, or a
# gate that merely required a progress file would pass this.
pseed_unattested() {
  rm -f "$PPROG"
  { echo "# lean run — issue 8"; echo ""; echo "run_id: r-p"; echo "session_id: $PSID"; } > "$PPROG"
}
pseed_unattested
out="$(pgate 1 8)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'bash G entry 8' \
   && [ "$(pcount '| milestone-1 | attempt |')" -eq 0 ]; then
  pass "(ea3) a build-role milestone with no entry row exits 2, names the remedy, and charges no attempt"
else fail "(ea3) expected rc=2 + remedy + zero attempts, rc=$rc, attempts=$(pcount '| milestone-1 | attempt |'): $out"; fi

# D-13's backstop, and the issue's own exit-evidence wording: a run REACHING MILESTONE 4 with no
# entry trace reds. It reds at the precondition rather than inside cmd_4 — which is the point of
# D-4, since the constraint the issue states as governing is that the failure be reachable BEFORE
# a verdict record exists — but the observable the issue asks for is the same one.
printf 'verdict=approve\nrun_id: r-p-review\nsession_id: sess-p-review\nrounds: 1\nreviewed_head: %s\n' \
  "$(git -C "$PTREE" rev-parse HEAD)" > "$PTREE/docs/plans/acme-8-lean-verdict.md"
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
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'no entry attestation'; then
  pass "(ea5) 'all' refuses an unattested run before its cheap pre-pass runs"
else fail "(ea5) expected rc=2 from all, got $rc: $out"; fi

# `delta` is invoked by the REVIEW session — D-4 gates it anyway and accepts the consequence: a
# reviewer of an unattested build is told to stop, with a remedy only the build side can apply.
pseed_unattested
out="$(pgate delta 8)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'bash G entry 8'; then
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
if printf '%s' "$out" | grep -qF '[lean-gate] verdict:' \
   && ! printf '%s' "$out" | grep -qF 'no entry attestation'; then
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
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'is missing or empty' \
   && ! printf '%s' "$out" | grep -q 'audit-toolkit is disabled'; then
  pass "(ea8) with no settings to read, the missing-ledger refusal keeps its generic wording"
else fail "(ea8) expected the generic refusal, rc=$rc: $out"; fi

printf '{"enabledPlugins": {"audit-toolkit@second-shift": false}}\n' > "$PNOLEDGER/.claude/settings.local.json"
out="$(pn_entry)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'audit-toolkit is disabled'; then
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

echo "[lean-gate-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
