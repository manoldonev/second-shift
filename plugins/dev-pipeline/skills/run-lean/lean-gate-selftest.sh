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
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null } }
}
EOF

PROG="$WORK/progress.md"
SPEC="$TREE/docs/plans/acme-7-lean.md"
VERDICT="$TREE/docs/plans/acme-7-lean-verdict.md"

gate() { # gate <args...>  — always from inside the fixture tree
  # unset RUN_ID: this helper backs nearly every case in the file, including (m1)'s
  # "no RUN_ID, no cache" baseline. Without this, a RUN_ID exported in the CALLING shell
  # (SKILL.md step 2 tells operators/agents to export it for a real run) leaks through —
  # bash subshells inherit the parent's exported environment by default — and (m1)/(m3)
  # spuriously fail asserting the real run's id where the fixture expects `unset` or its
  # own cached value. SECOND_SHIFT_CONFIG/LEAN_PROGRESS_FILE are already pinned per-call
  # for the same reason; RUN_ID was the one seam left open to ambient leakage.
  ( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" bash "$GATE" "$@" 2>&1 )
}
count_in_progress() { [ -f "$PROG" ] && grep -cF "$1" "$PROG" 2>/dev/null || echo 0; }
reset_progress() { rm -f "$PROG"; }
# Milestone 5 asserts milestones 1-4 left satisfied records, so the (k) cases need a
# progress file in the state a real run would have reached by then.
seed_progress_1_to_4() {
  reset_progress
  { echo "# lean run — issue 7"; echo "run_id: r-1"; } > "$PROG"
  local m
  for m in 1 2 3 4; do echo "2026-01-01T00:00:00Z | milestone-$m | satisfied" >> "$PROG"; done
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
reset_progress
out="$(gate 3 7)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'mutation-sweep.sh absent'; then
  pass "(i) milestone-3 prints a skip notice when tools/mutation-sweep.sh is absent"
else fail "(i) expected a mutation-sweep skip notice, got rc=$rc: $out"; fi

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
  reset_progress
  { echo "# lean run — issue 7"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$PROG"
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
  local cfg="$1" prog="$2"; shift 2
  ( unset RUN_ID; cd "$TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" bash "$GATE" "$@" 2>&1 )
}
seed_progress_1_to_4_at() {
  rm -f "$1"
  { echo "# lean run — issue $JKEY"; echo "run_id: r-j"; } > "$1"
  local m
  for m in 1 2 3 4; do echo "2026-01-01T00:00:00Z | milestone-$m | satisfied" >> "$1"; done
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

out="$( cd "$TREE" && env -u GH_BOT PATH="$WORK/bin:$PATH" SECOND_SHIFT_CONFIG="$CFG_JIRA" \
        LEAN_PROGRESS_FILE="$PROG_J" RUN_ID="jira-run-1" bash "$GATE" claim "$JKEY" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$SPY_LOG" ]; then
  pass "(n9) jira claim exits 0 with NO GH_BOT in the environment and makes zero tracker calls"
else fail "(n9) expected rc=0 and an empty spy log, got rc=$rc, log='$(cat "$SPY_LOG" 2>/dev/null)': $out"; fi

# The record is the point: no write happens, but lean-reconcile.sh's run-id anchor must
# still land or the run stops being reconcilable.
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

echo "[lean-gate-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
