#!/usr/bin/env bash
# scenario-liveness-selftest.sh — composed-path liveness for the lean lane's declared verdicts.
#
# NOT per-tool fixture accretion. Every other selftest in this tree verifies one
# component's own contract; this one asserts that a COMPOSED path still reaches its
# terminal state. The bug class it guards is contracts contradicting each other ACROSS
# components while every per-tool selftest stays green — how the (since-retired)
# stacked-PR path died in #204 with a fully green suite.
#
# Scenarios:
#
#   lean legs     the build-lean progress-file line chain and gate exit codes across the
#                 three verdict paths: the fix budget of 3, the 4th-red hard stop, the
#                 abort record, counters surviving re-entry, and the session-executed claim
#   lean-closeout a close-out that discharged only ONE of milestone 5's two obligations,
#                 continued once by the scheduler through to the terminal write (#531). The
#                 acceptance evidence for #525: the falsifiable form of "a run completes".
#   lean-reentry  the LEAN lane's scheduler, composed: preflight's re-entry admission
#                 (claimed label + a bot-authored claim marker) driven through the real
#                 orchestrate-lean.sh and the real lean-gate.sh in a real worktree, to the
#                 close-out's milestone-5 record — the terminal write the scheduler's own
#                 close-out check reads back
#   lane routing  exactly one merge-boundary gate claims any given PR (#413) — a property of
#                 the PAIR of chain gates, invisible to either gate's own suite
#
# Scope boundary: scenarios exercise the MECHANICAL chain. Agent-prose gates (the
# scope reviewer, review-lead synthesis) appear only as their mechanical shadows —
# the state writes their outcomes produce. A model-free harness cannot execute
# prose; it CAN assert that the prose's declared state protocol composes.
#
# ---------------------------------------------------------------------------
# Reach boundary — what is deliberately NOT scenarioed, and why.
#
# Stated so the next reach audit is a DIFF of this list rather than a re-derivation.
#
# (A) Out of reach BY CONTRACT — nothing to add until the contract itself changes:
#   - Design mode. The mode is contractually interactive/MCP-backed and headless
#     fail-closes by design. (The engine-enum drift guard died with the design-sync
#     engine and its selftest, #574; milestone 3's render lane is the design gate.)
#   - A REAL `claude -p` session re-entering a run the lean lane stopped itself.
#     The (lean-reentry) leg below composes the scheduler with the real gate over
#     a SCRIPTED session binary, which is its stated ceiling — CI is model-free by
#     design, and orchestrate-lean-selftest.sh:11-16 records the same boundary for
#     itself. Reversing it means an operator-run end to end, which is not a CI
#     artifact, so this is a contract boundary rather than debt.
#
#   - The #141 lane-tree assertion's REFUSE path. Exit 9 stops the run before any
#     downstream component observes it, so there is no composed verdict path for a
#     scenario to reach a terminal write along — a scenario for it would be a
#     per-tool case in scenario clothing (lean-gate-selftest.sh's (lt*) block owns
#     it). Its PASS direction is composed here for free and not by accident: the
#     (lean-reentry) and (lean-closeout) legs below define `g()` as a subshell that
#     cds into a REAL worktree on `claude/acme-<key>`, so a wrong predicate in that
#     guard reds them.
#
# (B) Uncovered, TRACKED — reachable today; absence here is debt, not a decision:
#   - Production Workflow .mjs dispatch ladders. Those belong on the runtime shim
#     (workflows/runtime-shim-selftest.mjs), not here.
#
# #348 NOTE — what this suite USED to carry. The staged-lane scenarios (no-split,
# sub-issues carve-out, failure-path, exhausted-review, voided-review, be-fe-pair,
# the verify circuit breaker, waived-run, the jira zero-evidence guard, the
# predecessor ordering backstop, the tracker-reconcile resume, and ledger
# corroboration) each composed stage progression to a terminal write.
# They were deleted with the lane, not lost: `tools/capability-parity.tsv` carries
# the per-capability disposition for every behavior they asserted on, and the tools
# that SURVIVED the deletion (predecessor-gate.sh, claim-issue.sh) kept their own
# per-tool suites.
# ---------------------------------------------------------------------------
#
# Exit code = number of failed checks (repo selftest convention).

# `-uo pipefail` (no `-e`): these scenarios assert on non-zero exit codes as first-class
# outcomes (a refused milestone, a hard stop), so a global `-e` would abort the harness on
# its own passing cases.
set -uo pipefail
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST BRANCH_PREFIX

# #141: the lane-tree assertion, DISARMED for the legs whose fixture is a bare `git init` tree and
# re-armed for the three that are not. Most legs here compose the gate against a plain repo on its
# default branch, over several issue keys — one tree cannot be on four lane branches — so an export
# is what keeps them driving the composed path this file exists to drive. The (lean-reentry),
# (lean-infrakill) and (lean-closeout) legs are the exception: each cuts a REAL `git worktree` on
# `claude/acme-<key>` and unsets this again inside its own `g()`, which is where the guard's PASS
# direction is composed rather than merely tolerated (#141 D-5).
export LEAN_GATE_ANY_TREE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t scenario-liveness.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM
cd "$TMP" || exit 99

# ─────────────────────────────────────────────────────────────────────────────
# LEAN LEGS (build-lean) — the composed progress-file line chain and gate exit codes
# across the three verdict paths.
#
# These are the assertion site for the failure economics the issue pins in PROSE but
# no AC-n carries: the fix budget of 3, the 4th-red hard stop, the abort record, and
# counters surviving re-entry. A per-tool fixture proves one gate in isolation; only a
# composed leg proves the CHAIN a real run walks.
#
# The all-green leg is also AC-15's assertion site: the claim is executed by the session
# following SKILL.md rather than by a gate, so this is where the second bot-wrapper write
# is checked (the label swap itself is claim-issue.sh's contract, proven by claim-selftest.sh).
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "── lean legs (build-lean)"

# $HERE, not BASH_SOURCE: this suite cd's to $TMP above, so BASH_SOURCE is relative by the
# time we get here and would resolve against the temp dir. $HERE was captured absolutely
# before that cd for exactly this reason.
#
# Absence is a FAILURE, not a skip. build-lean ships in this repo, so a missing gate means the
# legs below never ran — and a skipped leg reporting PASS is the vacuous green this whole
# suite exists to prevent. (It bit these very legs once: a bad path resolved to a skip and
# the suite reported 32/32 having asserted nothing about lean.)
LEAN_GATE="$HERE/lean-gate.sh"
if [[ ! -x "$LEAN_GATE" ]]; then
  fail "(lean) lean-gate.sh not found or not executable at $LEAN_GATE — the lean legs did not run"
else
  LEAN_TREE="$TMP/lean-tree"
  mkdir -p "$LEAN_TREE/docs/plans" "$LEAN_TREE/.claude/audit"
  git -C "$LEAN_TREE" init -q
  LEAN_CFG="$TMP/lean-config.json"
  cat > "$LEAN_CFG" <<'LEANCFG'
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
LEANCFG
  LEAN_PROG="$TMP/lean-progress.md"
  # No Open Regions section, so milestone 1's pause-and-ask check (#374) no-ops before it would
  # ever need a live `gh issue view` or comment-trail fetch — these legs are zero-network by
  # construction, same reasoning as lean-gate-selftest.sh's own default. --issue-file is FIRST,
  # so a leg's own --issue-file in "$@" is a later occurrence and overrides it.
  LEAN_ISSUE_NOREGIONS="$TMP/lean-issue-noregions.json"
  printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$LEAN_ISSUE_NOREGIONS"
  # #416: the build-role precondition reads an entry attestation these legs must now COMPOSE,
  # not seed — which means a live per-session ledger and a session id the legs control. Pinning
  # it here (rather than inheriting the ambient one) is what makes the legs behave identically
  # in a Claude Code session, where CLAUDE_CODE_SESSION_ID is exported, and in CI, where it is
  # not: the fixture's session identity is always the fixture's.
  #
  # unset RUN_ID GH_BOT: the same ambient-leak pinning lean-gate-selftest.sh applies to its own
  # helper. Load-bearing since #359 — milestone 5 calls cmd_mark, whose no-op test keys on the
  # resolved run id, so an operator's exported RUN_ID makes these legs stamp an identity the
  # fixtures do not carry, and an ambient GH_BOT would send that write to a LIVE bot.
  # CLAUDE_CODE_SESSION_ID is PINNED rather than unset — the stronger form of the same fix, and
  # the one #416 requires, since the attestation the legs compose reads THIS session's ledger.
  LEAN_SID="sess-lean-build"
  printf '{"tool":"Bash"}\n' > "$LEAN_TREE/.claude/audit/$LEAN_SID.jsonl"
  lean_gate() { ( unset RUN_ID GH_BOT; cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
                  CLAUDE_CODE_SESSION_ID="$LEAN_SID" \
                  bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 ); }
  lean_count() { if [[ -f "$LEAN_PROG" ]]; then local n; n=$(grep -cF "$1" "$LEAN_PROG" 2>/dev/null) || n=0; echo "$n"; else echo 0; fi; }
  # #496: the same call through the observe seam. A separate helper rather than an assignment
  # prefixed to `lean_gate` — a `VAR=x func` prefix on a shell FUNCTION does not reliably scope to
  # the call, and a seam that leaked into the legs below would silence their recording assertions.
  lean_gate_observe() { ( unset RUN_ID GH_BOT; cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" \
                  LEAN_PROGRESS_FILE="$LEAN_PROG" CLAUDE_CODE_SESSION_ID="$LEAN_SID" LEAN_GATE_OBSERVE=1 \
                  bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 ); }

  LEAN_SPEC="$LEAN_TREE/docs/plans/acme-77-lean.md"
  LEAN_VERDICT="$LEAN_TREE/docs/plans/acme-77-lean-verdict.md"

  # The verdict record is REVIEW-authored throughout these legs. build-lean's session
  # cannot produce it, so a leg composing a build-authored record would compose a state no
  # real run can reach — and the chain would prove nothing about the run it claims to model.
  # The build identities are seeded explicitly rather than left to the gate's stamping, so
  # the authorship comparison has two known sides in every leg.
  lean_seed_progress() { # lean_seed_progress <build-run-id> <build-session-id>
    rm -f "$LEAN_PROG"
    { echo "# lean run — issue 77"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$LEAN_PROG"
    # The build run-id CACHE, which is what a real run leaves behind and what every later
    # fresh-shell call resolves its identity from. Seeded explicitly rather than left to
    # resolve as `unset`: milestone 5 stamps the PR marker with this value (#359), so a leg
    # composing an unset identity would compose a marker no real run writes. It is seeded
    # BEFORE the entry call below so that call resolves the same identity the header carries.
    mkdir -p "$LEAN_TREE/.claude/pipeline-state"
    printf '%s' "$1" > "$LEAN_TREE/.claude/pipeline-state/77-run-id"
    # The entry attestation comes from the REAL `entry` subcommand, never a seeded line: a
    # hand-written row would keep every leg green after the writer and the reader drifted apart,
    # which is the shape of failure #416 itself was.
    lean_gate entry 77 >/dev/null 2>&1
  }
  # The same seed WITHOUT the attestation — the state a run that skipped step 1 is in, and the
  # only thing the refusal leg below varies. The run-id cache is seeded here too, precisely so
  # the missing attestation row is the only difference between the two states.
  lean_seed_unattested() { # lean_seed_unattested <build-run-id> <build-session-id>
    rm -f "$LEAN_PROG"
    { echo "# lean run — issue 77"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$LEAN_PROG"
    mkdir -p "$LEAN_TREE/.claude/pipeline-state"
    printf '%s' "$1" > "$LEAN_TREE/.claude/pipeline-state/77-run-id"
  }
  # Milestone 4 binds the record to a tree: it must be COMMITTED and nothing but the record
  # itself may have changed since. So the legs commit, and each verdict write advances a round
  # counter — an identical re-write stages nothing, which would leave the record holding an
  # earlier round's commit while the tree moved on and red the leg on freshness instead of on
  # what it composes.
  git -C "$LEAN_TREE" config user.email lean@example.invalid
  git -C "$LEAN_TREE" config user.name lean-scenario
  printf '.claude/\n' > "$LEAN_TREE/.gitignore"
  lean_commit() { git -C "$LEAN_TREE" add -A >/dev/null 2>&1
                  git -C "$LEAN_TREE" commit -q --allow-empty -m "${1:-lean fixture}" >/dev/null 2>&1; }
  lean_commit "lean fixture tree"
  # The patch-id freshness arm measures the branch's diff from merge-base(origin/<base>, HEAD),
  # so the fixture carries the remote-tracking ref a real checkout would have. Leg 7 composes
  # that arm; every other leg writes records without the key and takes the SHA fallback.
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main HEAD
  # `reviewed_head` is resolved BEFORE the commit, which is the shape a real round has: the
  # reviewer reads the current head, names it, and commits the record on top of it. Resolving it
  # after would name the record's own commit and leave the declared arm asserting nothing.
  LEAN_ROUND=0
  lean_write_verdict() { # lean_write_verdict <verdict> <run-id> <session-id> [reviewed-head]
    LEAN_ROUND=$((LEAN_ROUND + 1))
    printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: %s\nreviewed_head: %s\n' \
      "$1" "$2" "$3" "$LEAN_ROUND" "${4:-$(git -C "$LEAN_TREE" rev-parse HEAD)}" > "$LEAN_VERDICT"
    lean_commit "review verdict $1 (round $LEAN_ROUND)"
  }

  # ---- leg 1: all-green -> exit artifacts ----------------------------------
  lean_seed_progress r-lean-1 sess-lean-build
  printf '# spec\n\n- AC-1: a thing\n' > "$LEAN_SPEC"
  # The spec is committed on its OWN, before the review reads it. `lean_commit` stages
  # everything, so folding it into the verdict commit would put a code change inside the record's
  # commit — a shape review-lean step 6 forbids and both freshness arms refuse. What is left is
  # the state a real branch is in the moment the review session has pushed: the record's commit
  # is the head, and the head it names is the commit right below it.
  lean_commit "build session pushes the spec"
  lean_write_verdict approve r-lean-review-1 sess-lean-review
  cat > "$TMP/lean-pr.json" <<'LEANPR'
[{ "number": 5, "url": "https://example.invalid/pr/5", "isDraft": false,
   "body": "Closes #77\n\nSpec: docs/plans/acme-77-lean.md" }]
LEANPR
  # THREE comments now (#359). The third is the PR build-identity marker milestone 5 stamps —
  # present here carrying THIS run's id, so cmd_mark no-ops and the leg stays a pure
  # composition of the terminal write. (lean-mark) below composes the write itself.
  cat > "$TMP/lean-comments.json" <<'LEANC'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-lean-1 -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-77-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: r-lean-1 -->\n<!-- session_id: sess-lean-build -->\n<!-- stage: lean-pr-marker -->" }]
LEANC
  lean_gate 1 77 >/dev/null 2>&1; g1=$?
  lean_gate 2 77 >/dev/null 2>&1; g2=$?
  lean_gate 3 77 >/dev/null 2>&1; g3=$?
  lean_gate 4 77 >/dev/null 2>&1; g4=$?
  lean_gate 5 77 --pr-file "$TMP/lean-pr.json" --comments-file "$TMP/lean-comments.json" >/dev/null 2>&1; g5=$?
  [[ "$g1$g2$g3$g4$g5" == "00000" ]] \
    && pass "(lean-green) milestones 1-5 all exit 0 on a complete run" \
    || fail "(lean-green) exit codes were $g1$g2$g3$g4$g5, expected 00000"

  lean_sat=0
  for m in 1 2 3 4 5; do
    [[ "$(lean_count "| milestone-$m | satisfied")" -eq 1 ]] && lean_sat=$((lean_sat + 1))
  done
  [[ "$lean_sat" -eq 5 ]] \
    && pass "(lean-green) the progress-file chain carries exactly one satisfied line per milestone" \
    || fail "(lean-green) expected 5 single satisfied lines, got $lean_sat"

  # #392, green-with-notice verdict path. This fixture configures no verify lane at all, so the
  # chain above only reaches milestone 3's green gate through the `allowUnverified` opt-out —
  # a green run that verified nothing, legitimate solely because it was DECLARED. The
  # declaration has to survive into the artifact a reconcile reads; without this assertion the
  # opt-out path is traversed by the composed run and pinned by nothing.
  [[ "$(lean_count "| milestone-3 | skipped | no verifying lane configured")" -eq 1 ]] \
    && pass "(lean-zv-skip) the declared zero-lane opt-out composes into a recorded progress line" \
    || fail "(lean-zv-skip) the composed green run left no opt-out record in $LEAN_PROG"

  # AC-15's second write. What is pinned is not "a comment exists" but that it is
  # BOT-authored and carries the run id — an operator-posted comment is invisible to the
  # merge-boundary gate's trust filter, so it would not be evidence at all.
  claim_ok=$(jq -r '[ .[] | select(.user.type == "Bot")
                          | select((.body // "") | test("stage:[[:space:]]*lean-claimed"))
                          | select((.body // "") | test("run_id:[[:space:]]*[A-Za-z0-9._-]+")) ] | length' \
             "$TMP/lean-comments.json")
  [[ "$claim_ok" -ge 1 ]] \
    && pass "(lean-claim) the claim trail carries a bot-authored lean-claimed marker with a run id (AC-15)" \
    || fail "(lean-claim) no bot-authored lean-claimed comment with a run id"

  # The marker must be lean-DISTINCT: a bare `stage: claimed` would pollute the pipeline
  # chain gate's run-family selection if this issue later runs through full `run`.
  polluting=$(jq -r '[ .[] | select((.body // "") | test("stage:[[:space:]]*claimed[[:space:]]*-->")) ] | length' \
              "$TMP/lean-comments.json")
  [[ "$polluting" -eq 0 ]] \
    && pass "(lean-claim) the marker is lean-distinct — no bare 'stage: claimed' to pollute pipeline family selection" \
    || fail "(lean-claim) a bare 'stage: claimed' marker would pollute pipeline family selection"

  # ---- leg 1b: the PR build-identity marker, composed through the terminal write --------
  # #359. The merge boundary compares the review verdict against bot markers on the PR; without
  # a WRITER that comparison refuses every honest run, and the writer only ever fires from a
  # composed milestone-5 (or from checklist step 7, the same code path). Leg 1 above deliberately
  # pre-seeds the marker so it composes the no-op branch — this leg composes the WRITE.
  #
  # The bot wrapper is stubbed, not mocked away: what is asserted is the BYTES posted, because
  # the boundary reads `run_id`/`session_id` out of that body and a marker missing either is
  # indistinguishable to it from no marker at all.
  LEAN_BOT_SPOOL="$TMP/lean-bot-spool.txt"
  cat > "$TMP/lean-bot-stub.sh" <<'LEANBOT'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in body=@*) cat "${a#body=@}" >> "$LEAN_BOT_SPOOL" ;; esac
done
echo "https://example.invalid/pr/5#issuecomment-1"
LEANBOT
  chmod +x "$TMP/lean-bot-stub.sh"
  # Same trail as leg 1 minus the marker: everything else about the run is already green, so a
  # refusal here can only be the marker's.
  jq 'map(select((.body // "") | test("lean-pr-marker") | not))' "$TMP/lean-comments.json" \
    > "$TMP/lean-comments-nomarker.json"
  # NO re-seed: cmd_5 asserts milestones 1-4 each left a `satisfied` record, and
  # lean_seed_progress wipes exactly those. This leg runs on the state leg 1 just composed,
  # which is also the only state a real run reaches milestone 5 in.
  : > "$LEAN_BOT_SPOOL"
  # unset RUN_ID, then let the identity resolve from the CACHE lean_seed_progress wrote — which
  # is what a real run does, since only entry/claim establish it and every later call reads it
  # back. Passing one explicitly here would test a shape no run has, and inheriting an ambient
  # one makes the leg stamp an identity the fixture never carries.
  lm5=$( ( unset RUN_ID; cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
           CLAUDE_CODE_SESSION_ID=sess-lean-build GH_BOT="$TMP/lean-bot-stub.sh" \
           LEAN_BOT_SPOOL="$LEAN_BOT_SPOOL" \
           bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" 5 77 \
           --pr-file "$TMP/lean-pr.json" --comments-file "$TMP/lean-comments-nomarker.json" \
           >/dev/null 2>&1; echo $? ) )
  if [[ "$lm5" -eq 0 ]] \
     && grep -q 'stage: lean-pr-marker' "$LEAN_BOT_SPOOL" 2>/dev/null \
     && grep -q 'run_id: r-lean-1' "$LEAN_BOT_SPOOL" 2>/dev/null \
     && grep -q 'session_id: sess-lean-build' "$LEAN_BOT_SPOOL" 2>/dev/null; then
    pass "(lean-mark) a composed milestone 5 stamps the PR with the build run's identity — both keys, bot-authored"
  else
    fail "(lean-mark) rc=$lm5, spool=$(cat "$LEAN_BOT_SPOOL" 2>/dev/null)"
  fi

  # ...and the run that already stamped does not stamp again. The mandated pre-close `all`
  # sweep re-enters milestone 5, so a writer that posted unconditionally would leave one marker
  # per sweep on every PR the lane ever opens.
  : > "$LEAN_BOT_SPOOL"
  lm5b=$( ( unset RUN_ID; cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
            CLAUDE_CODE_SESSION_ID=sess-lean-build GH_BOT="$TMP/lean-bot-stub.sh" \
            LEAN_BOT_SPOOL="$LEAN_BOT_SPOOL" \
            bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" 5 77 \
            --pr-file "$TMP/lean-pr.json" --comments-file "$TMP/lean-comments.json" \
            >/dev/null 2>&1; echo $? ) )
  [[ "$lm5b" -eq 0 && ! -s "$LEAN_BOT_SPOOL" ]] \
    && pass "(lean-mark) a re-entered milestone 5 finds its own marker and posts nothing" \
    || fail "(lean-mark) re-entry rc=$lm5b, spool=$(cat "$LEAN_BOT_SPOOL" 2>/dev/null)"

  # ---- leg 2: budget exhaustion -> abort record ----------------------------
  lean_seed_progress r-lean-1 sess-lean-build
  mv "$LEAN_VERDICT" "$TMP/held-lean-verdict.md"
  lean_rcs=""
  for _ in 1 2 3 4; do lean_gate 4 77 >/dev/null 2>&1; lean_rcs="$lean_rcs$?"; done
  [[ "$lean_rcs" == "5554" ]] \
    && pass "(lean-budget) 3 fix attempts then a 4th-red hard stop (rc=4) — the prose-only fix budget, asserted" \
    || fail "(lean-budget) exit sequence was $lean_rcs, expected 5554"
  [[ "$(lean_count 'budget-exhausted')" -ge 1 ]] \
    && pass "(lean-budget) the abort record lands in the progress file" \
    || fail "(lean-budget) no budget-exhausted record written"
  [[ "$(lean_count '| milestone-4 | satisfied')" -eq 0 ]] \
    && pass "(lean-budget) an exhausted milestone records no satisfied line — an abort is not a pass" \
    || fail "(lean-budget) an exhausted milestone was also recorded satisfied"

  # ---- leg 3: needs-work -> fix-loop re-entry ------------------------------
  # Round 2 arrives from a NEW review context, so it carries a new review identity — that is
  # what "a new review context produces the next verdict" means in artifact terms.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict needs-work r-lean-review-1 sess-lean-review
  lean_gate 4 77 >/dev/null 2>&1; nw1=$?
  lean_write_verdict approve r-lean-review-2 sess-lean-review-2
  lean_gate 4 77 >/dev/null 2>&1; nw2=$?
  [[ "$nw1" -eq 1 && "$nw2" -eq 0 ]] \
    && pass "(lean-fixloop) a needs-work verdict blocks (rc=1) and re-entry after the fix passes (rc=0)" \
    || fail "(lean-fixloop) expected rc 1 then 0, got $nw1 then $nw2"
  [[ "$(lean_count '| milestone-4 | attempt |')" -eq 1 ]] \
    && pass "(lean-fixloop) the failed round is still counted after re-entry (counters survive resume)" \
    || fail "(lean-fixloop) the surviving attempt counter was lost across re-entry"

  # ---- leg 3d: the milestone-4 taxonomy, composed (#496) --------------------
  # CLAUDE.md: a new gate contract extends the liveness scenario for every verdict path it
  # touches. The per-tool suite proves each class against its own fixture; what only a composed
  # leg can show is that the classes stay DISTINCT along one run's progress-file chain, and that
  # they survive `all` — the whole-progression entry point a resume re-enters through, and the
  # one caller that reaches milestone 4 through a pre-pass rather than directly.
  #
  # Three conditions, three actions, on ONE tree that differs only in the verdict record: a
  # record that does not approve (a BUILD fix), a record that is not there at all (a review
  # round), and a record the build run authored (a refusal no retry can clear). Before #496 all
  # three arrived as `1` and the scheduler spent a round on each.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict needs-work r-lean-review-tx1 sess-lean-review-tx1
  lean_gate 4 77 >/dev/null 2>&1; tx_nw=$?
  lean_gate all 77 >/dev/null 2>&1; tx_nw_all=$?

  lean_seed_progress r-lean-1 sess-lean-build
  mv "$LEAN_VERDICT" "$TMP/held-lean-verdict-tx.md"
  lean_gate 4 77 >/dev/null 2>&1; tx_absent=$?
  lean_gate all 77 >/dev/null 2>&1; tx_absent_all=$?
  mv "$TMP/held-lean-verdict-tx.md" "$LEAN_VERDICT"

  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-1 sess-lean-review-tx2
  lean_gate 4 77 >/dev/null 2>&1; tx_p10=$?
  lean_gate all 77 >/dev/null 2>&1; tx_p10_all=$?

  [[ "$tx_nw" -eq 1 && "$tx_absent" -eq 5 && "$tx_p10" -eq 6 ]] \
    && pass "(lean-taxonomy) one tree, three verdict records, three distinct classes — needs-work 1, no usable record 5, build-authored 6" \
    || fail "(lean-taxonomy) expected rc 1/5/6, got $tx_nw/$tx_absent/$tx_p10"
  [[ "$tx_nw_all" -eq 1 && "$tx_absent_all" -eq 5 && "$tx_p10_all" -eq 6 ]] \
    && pass "(lean-taxonomy) ...and 'all' propagates each class rather than laundering it into its pre-pass's own 1" \
    || fail "(lean-taxonomy) 'all' collapsed the classes: got $tx_nw_all/$tx_absent_all/$tx_p10_all, expected 1/5/6"

  # THE OBSERVE SEAM, composed. The scheduler reads this gate through it on every round, so what
  # matters on a real progress file is that the read classifies identically and appends nothing —
  # a seam that recorded would spend the BUILD role's fix budget on the SCHEDULER's reads, three
  # of them per run, which is the premise-breaking write #496 removes.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict needs-work r-lean-review-tx3 sess-lean-review-tx3
  tx_lines_before=$(lean_count '| milestone-4 |')
  lean_gate_observe 4 77 >/dev/null 2>&1; tx_obs=$?
  tx_lines_after=$(lean_count '| milestone-4 |')
  lean_gate 4 77 >/dev/null 2>&1; tx_rec=$?
  [[ "$tx_obs" -eq 1 && "$tx_rec" -eq 1 && "$tx_lines_after" -eq "$tx_lines_before" \
     && "$(lean_count '| milestone-4 |')" -gt "$tx_lines_after" ]] \
    && pass "(lean-taxonomy) an observed read classifies the same and writes no milestone-4 line, while the recording path on the same file still does" \
    || fail "(lean-taxonomy) observe=$tx_obs record=$tx_rec lines $tx_lines_before -> $tx_lines_after -> $(lean_count '| milestone-4 |')"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-tx4 sess-lean-review-tx4

  # ---- leg 4: P10 — the same chain reds on a build-authored verdict ---------
  # The composed counterpart to lean-gate-selftest's (n) cases. Everything else in leg 1 is
  # left exactly as it was; ONLY the verdict's authorship changes, so a green here would mean
  # the milestone-4 link in the chain is not carrying the check at all.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-1 sess-lean-review
  lean_gate 4 77 >/dev/null 2>&1; auth1=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; auth2=$?
  [[ "$auth1" -eq 6 && "$auth2" -eq 6 ]] \
    && pass "(lean-authorship) the chain reds with the INTEGRITY class when the verdict carries the build run's id or names its session" \
    || fail "(lean-authorship) expected rc 6 and 6, got $auth1 then $auth2"

  # ---- leg 5: the chain reds on a STALE verdict, and a new round clears it --
  # The composed counterpart to lean-gate-selftest's (t) cases, and the one failure this
  # separation created rather than removed: with review in its own session, "verdict, then
  # more commits" is the ordinary shape of the needs-work loop, so an approve for an earlier
  # head reaching a green chain is the default outcome unless something binds the two.
  # Everything else in leg 1 is left as it was; ONLY a later commit is added.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-3 sess-lean-review-3
  lean_gate 4 77 >/dev/null 2>&1; fresh1=$?
  printf '# spec\n\n- AC-1: a thing\n- AC-2: added after the review\n' > "$LEAN_SPEC"
  lean_commit "code lands after the verdict"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; fresh2=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-4 sess-lean-review-4
  lean_gate 4 77 >/dev/null 2>&1; fresh3=$?
  [[ "$fresh1" -eq 0 && "$fresh2" -eq 5 && "$fresh3" -eq 0 ]] \
    && pass "(lean-freshness) a verdict covering the head passes, one predating a later commit reds as 5, a new round clears it" \
    || fail "(lean-freshness) expected rc 0/5/0, got $fresh1 then $fresh2 then $fresh3"

  # ---- leg 6: the chain reds on a verdict that DECLARES an earlier head -----
  # Leg 5 composes the INFERRED freshness arm — git decides which commit carries the record.
  # This leg composes the DECLARED one, and it is constructed so leg 5's arm is GREEN over it:
  # the record is committed LAST, so its commit IS the head and nothing but the record differs
  # from it. Only the head the record NAMES is stale. That is not a contrived shape — it is what
  # a review round produces whenever a fix lands while the review is still running, and it is
  # the residual the inferred arm cannot see. Everything else is left as leg 1 had it.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_stale_head="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  printf '# spec\n\n- AC-1: a thing\n- AC-3: landed while the review was running\n' > "$LEAN_SPEC"
  lean_commit "code lands between the review and the record"
  lean_write_verdict approve r-lean-review-5 sess-lean-review-5 "$lean_stale_head"
  lean_gate 4 77 >/dev/null 2>&1; decl1=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-6 sess-lean-review-6
  lean_gate 4 77 >/dev/null 2>&1; decl2=$?
  [[ "$decl1" -eq 5 && "$decl2" -eq 0 ]] \
    && pass "(lean-declared) a record whose own commit IS the head still reds when it names an earlier reviewed_head, and a re-declared round clears it" \
    || fail "(lean-declared) expected rc 5 then 0, got $decl1 then $decl2"

  # ...and the migration arm: a record with no reviewed_head at all is refused, not grandfathered.
  lean_seed_progress r-lean-1 sess-lean-build
  printf 'verdict=approve\nrun_id: r-lean-review-7\nsession_id: sess-lean-review-7\nrounds: 7\n' > "$LEAN_VERDICT"
  lean_commit "a key-less record, as written before reviewed_head existed"
  lean_gate 4 77 >/dev/null 2>&1; decl3=$?
  [[ "$decl3" -eq 5 ]] \
    && pass "(lean-declared) a verdict record predating the reviewed_head key is refused, not grandfathered" \
    || fail "(lean-declared) expected rc=5 on a key-less record, got $decl3"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-8 sess-lean-review-8

  # ---- leg 7: the PATCH-ID declared arm, composed across a real rebase ------
  # Legs 5 and 6 compose the two freshness arms over records that carry no `reviewed_patch_id`,
  # so both take the SHA fallback. This leg composes the arm records written by the current
  # writer actually take — and it composes it across the operation that arm exists for.
  #
  # The record comes from the REAL `verdict` subcommand rather than a printf: the id it stamps is
  # the thing milestone 4 recomputes, so a leg that hand-wrote one would compose a record no
  # review session produces. The write is refused unless the review identity is distinct from the
  # build's on both axes, which is why the two are seeded explicitly here as everywhere else.
  lean_seed_progress r-lean-1 sess-lean-build
  rm -f "$LEAN_TREE/.claude/pipeline-state/77-review-run-id"
  ( cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
    CLAUDE_CODE_SESSION_ID=sess-lean-review-9 RUN_ID=r-lean-review-9 \
    bash "$LEAN_GATE" verdict 77 --pr 5 --verdict approve >/dev/null 2>&1 ); pid_write=$?
  lean_commit "review session commits its patch-id-keyed record"
  lean_gate 4 77 >/dev/null 2>&1; pid1=$?

  # A REAL rebase onto a base that moved with content. A same-tree base would leave the pre- and
  # post-rebase trees identical, so the SHA arm would pass too and the leg would compose nothing.
  lean_branch="$(git -C "$LEAN_TREE" symbolic-ref --short HEAD 2>/dev/null)"
  lean_pre_rebase="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  git -C "$LEAN_TREE" branch -f lean-base refs/remotes/origin/main >/dev/null 2>&1
  git -C "$LEAN_TREE" checkout -q lean-base 2>/dev/null
  printf 'the base moved while the review was in flight\n' > "$LEAN_TREE/base-moved.txt"
  git -C "$LEAN_TREE" add base-moved.txt >/dev/null 2>&1
  git -C "$LEAN_TREE" commit -q -m 'base advances' >/dev/null 2>&1
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main lean-base
  git -C "$LEAN_TREE" checkout -q "$lean_branch" 2>/dev/null
  git -C "$LEAN_TREE" rebase -q lean-base >/dev/null 2>&1; lean_rebased=$?
  # The SHA arm would red here: the pre-rebase commit is still an object in this repo, but its
  # tree now differs from the head by the base's commit. If that diff is empty the leg is vacuous.
  lean_sha_would_red="$(git -C "$LEAN_TREE" diff --name-only "$lean_pre_rebase" HEAD 2>/dev/null)"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; pid2=$?

  # ...and the arm is still a gate: a commit after the approve moves the patch and reds it.
  lean_seed_progress r-lean-1 sess-lean-build
  printf '# spec\n\n- AC-1: a thing\n- AC-4: landed after the approve\n' > "$LEAN_SPEC"
  lean_commit "code lands after the approve"
  lean_gate 4 77 >/dev/null 2>&1; pid3=$?

  [[ "$pid_write" -eq 0 && "$lean_rebased" -eq 0 && -n "$lean_sha_would_red" \
     && "$pid1" -eq 0 && "$pid2" -eq 0 && "$pid3" -eq 5 ]] \
    && pass "(lean-patch-id) a review-written record passes, survives a rebase the SHA arm would have redded, and still reds once a commit changes the branch" \
    || fail "(lean-patch-id) write=$pid_write rebase=$lean_rebased sha-arm-diff='$lean_sha_would_red' rcs=$pid1/$pid2/$pid3, expected 0/0/nonempty/0/0/5"

  # ---- leg 7b: #597 — a BASE ADVANCE does not void a verdict, composed ------
  # CLAUDE.md: a new gate contract extends the liveness scenario for every verdict path it
  # touches. Leg 7 composes the arm across a REBASE; this leg composes it across the operation
  # the rebase case does not reach — merging the base IN. The two differ in exactly the way that
  # matters: a rebase leaves the merge-base where it was, while a merge ADVANCES it, and
  # `branch_patch_id` hashes a diff measured from it. On #583 that moved the identity from
  # 1decd12550cd to 86daf57fb18e over a union resolution that introduced no branch line, spawned a
  # review against an unmoved head, and forced a hand re-stamp.
  #
  # What only a composed leg can show is that BOTH freshness arms clear it together. The per-tool
  # suite drives each arm; here the inferred arm's file list and the declared arm's hash both move,
  # and milestone 4 must still be green through `all` — the entry point a resume re-enters through.
  lean_seed_progress r-lean-1 sess-lean-build
  rm -f "$LEAN_TREE/.claude/pipeline-state/77-review-run-id"
  ba_branch="$(git -C "$LEAN_TREE" symbolic-ref --short HEAD 2>/dev/null)"
  git -C "$LEAN_TREE" branch -f ba-base refs/remotes/origin/main >/dev/null 2>&1
  git -C "$LEAN_TREE" checkout -q ba-base 2>/dev/null
  printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nc8\nc9\nc10\n' > "$LEAN_TREE/shared.txt"
  git -C "$LEAN_TREE" add shared.txt >/dev/null 2>&1
  git -C "$LEAN_TREE" commit -q -m 'base seeds the shared file' >/dev/null 2>&1
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main ba-base
  git -C "$LEAN_TREE" checkout -q "$ba_branch" 2>/dev/null
  git -C "$LEAN_TREE" merge -q --no-edit ba-base >/dev/null 2>&1
  printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nc8\nc9\nc10\nBRANCH-OWN-LINE\n' > "$LEAN_TREE/shared.txt"
  lean_commit "the branch appends its own line to the shared file"
  ( cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
    CLAUDE_CODE_SESSION_ID=sess-lean-review-11 RUN_ID=r-lean-review-11 \
    bash "$LEAN_GATE" verdict 77 --pr 5 --verdict approve >/dev/null 2>&1 ); ba_write=$?
  lean_commit "review commits its record at the pre-merge head"
  ba_vcommit="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  ba_pid_before="$(grep -oE 'reviewed_patch_id:[[:space:]]*[A-Za-z0-9._-]+' "$LEAN_VERDICT" \
                   | head -n1 | sed -E 's/^reviewed_patch_id:[[:space:]]*//')"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; ba1=$?

  # The unrelated base advance, INSIDE the branch hunk's context and in a file the branch also
  # touches — the shape that moves both arms. A base commit in some other file moves neither.
  git -C "$LEAN_TREE" checkout -q ba-base 2>/dev/null
  printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nBASE-EDIT\nc9\nc10\n' > "$LEAN_TREE/shared.txt"
  git -C "$LEAN_TREE" add shared.txt >/dev/null 2>&1
  git -C "$LEAN_TREE" commit -q -m 'an unrelated PR lands on the base' >/dev/null 2>&1
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main ba-base
  git -C "$LEAN_TREE" checkout -q "$ba_branch" 2>/dev/null
  git -C "$LEAN_TREE" merge -q --no-edit ba-base >/dev/null 2>&1; ba_merged=$?

  # NON-VACUITY, on BOTH arms, against plain git. If either is unmoved this leg composes nothing.
  ba_mb="$(git -C "$LEAN_TREE" merge-base refs/remotes/origin/main HEAD 2>/dev/null)"
  ba_pid_now="$(git -C "$LEAN_TREE" diff "$ba_mb" HEAD -- . ':(exclude)docs/plans/acme-77-lean-verdict.md' 2>/dev/null \
                | git -C "$LEAN_TREE" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  ba_inferred="$(git -C "$LEAN_TREE" diff --name-only "$ba_vcommit" HEAD 2>/dev/null \
                 | grep -vxF 'docs/plans/acme-77-lean-verdict.md')"

  # Through `all`, not through a direct milestone-4 call: the whole-progression entry point is
  # where a resume re-enters, and a green arm that `all` never reaches is not a cleared run.
  lean_seed_progress r-lean-1 sess-lean-build
  ba_all_out="$(lean_gate all 77 2>&1)"
  # `all` walks the WHOLE progression, so its own exit code answers for milestone 5 too — which
  # this fixture has no PR for. What this leg owns is that milestone 4 is reached and SATISFIED on
  # that walk, recorded in the run's own progress file rather than inferred from a rolled-up rc.
  ba_all_m4=$(lean_count '| milestone-4 | satisfied')
  ba_all_m4_red="$(printf '%s\n' "$ba_all_out" | grep '✗ milestone-4' || true)"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; ba2=$?

  # ...and the arms are STILL gates. Without this the leg reads as "milestone 4 was disabled".
  printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nBASE-EDIT\nc9\nc10\nBRANCH-OWN-LINE-EDITED\n' > "$LEAN_TREE/shared.txt"
  lean_commit "a real fix lands on a reviewed line after the base merge"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; ba3=$?

  [[ "$ba_write" -eq 0 && "$ba_merged" -eq 0 && "$ba1" -eq 0 \
     && -n "$ba_pid_before" && -n "$ba_pid_now" && "$ba_pid_before" != "$ba_pid_now" \
     && -n "$ba_inferred" && "$ba_all_m4" -ge 1 && -z "$ba_all_m4_red" \
     && "$ba2" -eq 0 && "$ba3" -eq 5 ]] \
    && pass "(lean-base-advance) a verdict survives a base merge that moved BOTH freshness arms' inputs and altered no reviewed line — green through 'all' — and still reds once a reviewed line moves" \
    || fail "(lean-base-advance) write=$ba_write merged=$ba_merged pid '$ba_pid_before'->'$ba_pid_now' inferred='$ba_inferred' rcs=$ba1/$ba2/$ba3 all-m4-satisfied=$ba_all_m4 all-m4-red='$ba_all_m4_red', expected 0/0/moved/nonempty/0/0/5/>=1/empty
$ba_all_out"

  # Restore the tree the remaining legs were written against: no shared.txt, no ba-base, and the
  # base ref back where leg 7 left it. The legs below diff against origin/main.
  rm -f "$LEAN_TREE/shared.txt"; lean_commit "remove the (lean-base-advance) fixture file"
  git -C "$LEAN_TREE" branch -D ba-base >/dev/null 2>&1

  # Restore the SHA-fallback shape the remaining legs were written against.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-10 sess-lean-review-10

  # ---- non-vacuity ---------------------------------------------------------
  # An all-green leg that stays green over a broken tree proves nothing.
  lean_seed_progress r-lean-1 sess-lean-build
  mv "$LEAN_SPEC" "$TMP/held-lean-spec.md"
  lean_gate 1 77 >/dev/null 2>&1; lean_nv=$?
  [[ "$lean_nv" -ne 0 ]] \
    && pass "(lean-nv) non-vacuity: the same leg reds when the spec is absent" \
    || fail "(lean-nv) milestone-1 passed with no spec — the lean legs are vacuous"

  # ---- leg 3c: absence is not a failed fix, composed (#494) -----------------
  # CLAUDE.md: a new gate contract extends the liveness scenario for every verdict path it
  # touches. The per-tool suite proves the two line kinds against a hand-seeded progress file;
  # what only a composed leg can show is the interaction with `all` — the whole-progression
  # entry point a resume re-enters through, and the one caller that reaches milestone 1 with
  # PRECHECK set. A pre-pass that recorded an absence would charge a run for a milestone it
  # never evaluated, which is the same class of defect #494 fixes.
  #
  # The tree is the one (lean-nv) just left: green in every respect EXCEPT the moved-away spec,
  # so the absence is the only thing these calls can be reacting to.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate all 77 >/dev/null 2>&1; ab_all=$?
  ab_pre_absent=$(lean_count '| milestone-1 | absent |')
  ab_pre_attempt=$(lean_count '| milestone-1 | attempt |')
  # Now the real calls: three of them, the shape a build session following SKILL.md step 3 and
  # resuming twice produces.
  ab_rcs=""
  for _ in 1 2 3; do lean_gate 1 77 >/dev/null 2>&1; ab_rcs="$ab_rcs$?"; done
  [[ "$ab_all" -ne 0 && "$ab_pre_absent" -eq 0 && "$ab_pre_attempt" -eq 0 \
     && "$ab_rcs" == "111" \
     && "$(lean_count '| milestone-1 | absent |')" -eq 3 \
     && "$(lean_count '| milestone-1 | attempt |')" -eq 0 ]] \
    && pass "(lean-absent) an unwritten spec reds 'all' and every milestone-1 call, records 'absent', and the pre-pass records neither kind" \
    || fail "(lean-absent) all=$ab_all pre-pass absent/attempt=$ab_pre_absent/$ab_pre_attempt rcs=$ab_rcs absent=$(lean_count '| milestone-1 | absent |') attempts=$(lean_count '| milestone-1 | attempt |'), expected nonzero/0/0/111/3/0"

  # ...and the terminal write the fix budget still owes, on the SAME progress file: the three
  # absent calls above bought milestone 1 nothing, so a CONTENT failure gets its full 3 attempts
  # and the 4th hard-stops. Under the pre-#494 conflation this sequence reads 4444 and the abort
  # record lands three calls early.
  printf '# spec\n\nNothing numbered here.\n' > "$LEAN_SPEC"
  ab_content=""
  for _ in 1 2 3 4; do lean_gate 1 77 >/dev/null 2>&1; ab_content="$ab_content$?"; done
  [[ "$ab_content" == "1114" && "$(lean_count 'budget-exhausted')" -ge 1 \
     && "$(lean_count '| milestone-1 | satisfied')" -eq 0 ]] \
    && pass "(lean-absent) after three absent calls a CONTENT failure still reaches its 4th-red abort record with the full budget" \
    || fail "(lean-absent) content sequence was $ab_content, budget-exhausted=$(lean_count 'budget-exhausted'), satisfied=$(lean_count '| milestone-1 | satisfied'), expected 1114/>=1/0"

  mv "$TMP/held-lean-spec.md" "$LEAN_SPEC"
  lean_seed_progress r-lean-1 sess-lean-build

  # ---- leg 3e: the pre-flight receipt, composed (#517) ----------------------
  # CLAUDE.md again: a new gate contract extends this scenario for every verdict path it
  # touches. The per-tool suites prove the reconciliation against fixtures and the gate's
  # classification of its exit codes. What only a composed leg can show is that the refusal
  # is reachable through `all` — the whole-progression entry point a resume re-enters
  # through, and the one caller that reaches milestone 1 with PRECHECK set. A check placed
  # below the observe guard (where the gh-calling pause-and-ask check sits) would let `all`
  # report milestone 1 clean on a spec the very next direct call refuses, which is the
  # shape a scheduler reads as progress.
  #
  # The receipt is written at the DEFAULT path rather than through --ledger-file, so the leg
  # composes the real $MAIN_ROOT/$STATE_DIR/<issue>-ledger.md resolution too. It is removed
  # again at the end: it would otherwise change milestone 1 for every leg below.
  LEAN_RECEIPT="$LEAN_TREE/.claude/pipeline-state/77-ledger.md"
  mkdir -p "$LEAN_TREE/.claude/pipeline-state"
  printf '%s\n' '# receipt' '## Decision Ledger' \
    '| ID | Decision | Resolution | Provenance | Kind |' \
    '| --- | --- | --- | --- | --- |' \
    '| D-1 | Fix scope | Both call sites | user-answered | intent |' \
    '| D-2 | Cache TTL | 5 minutes | codebase-derived | fact |' \
    > "$LEAN_RECEIPT"
  cp "$LEAN_SPEC" "$TMP/held-lean-spec-517.md"

  # The spec leg 1 committed carries no Decision Ledger at all — the state the founding
  # incident shipped in, and the state every spec in this suite is otherwise in. That is why
  # the refusal here names the missing SECTION rather than the individual row: the per-row
  # naming is lean-gate-selftest.sh's (a9), and what this leg owns is the composed path.
  lean_seed_progress r-lean-1 sess-lean-build
  rcp_all_out="$(lean_gate all 77 2>&1)"; rcp_all=$?
  rcp_pre_attempt=$(lean_count '| milestone-1 | attempt |')
  rcp_direct_out="$(lean_gate 1 77 2>&1)"; rcp_direct=$?

  # ...and the same tree once the row is carried forward. Nothing else about the spec or the
  # tree changes between the two calls, so the reconciliation is the only thing they can be
  # reacting to.
  {
    printf '\n## Decision Ledger\n'
    printf '| ID | Decision | Resolution | Provenance |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| D-1 | Fix scope | Both call sites | user-answered |\n'
  } >> "$LEAN_SPEC"
  lean_seed_progress r-lean-1 sess-lean-build
  rcp_fixed_out="$(lean_gate 1 77 2>&1)"; rcp_fixed=$?

  # NON-VACUITY, and the inertness contract: put the dropped-row spec back, take the RECEIPT
  # away, and the same call passes. Without this the leg cannot tell "the reconciliation
  # refused" from "this spec was refused for some other reason all along".
  cp "$TMP/held-lean-spec-517.md" "$LEAN_SPEC"
  rm -f "$LEAN_RECEIPT"
  lean_seed_progress r-lean-1 sess-lean-build
  rcp_inert_out="$(lean_gate 1 77 2>&1)"; rcp_inert=$?

  [[ "$rcp_all" -ne 0 && "$rcp_direct" -eq 1 && "$rcp_fixed" -eq 0 && "$rcp_inert" -eq 0 \
     && "$rcp_pre_attempt" -eq 0 ]] \
    && grep -q 'does not reconcile with the pre-flight ledger' <<< "$rcp_all_out" \
    && grep -q 'carries 1 row(s) the plan must carry forward' <<< "$rcp_direct_out" \
    && grep -q '1 bound, 0 carried, 0 departure(s)' <<< "$rcp_direct_out" \
    && grep -q '1 bound, 1 carried, 0 departure(s)' <<< "$rcp_fixed_out" \
    && ! grep -q 'bound,' <<< "$rcp_inert_out" \
    && pass "(lean-receipt) a dropped pre-flight receipt row reds both 'all' and milestone 1, passes once carried forward, and is inert with no receipt" \
    || fail "(lean-receipt) all=$rcp_all direct=$rcp_direct fixed=$rcp_fixed inert=$rcp_inert pre-pass-attempts=$rcp_pre_attempt, expected nonzero/1/0/0/0. all-out=$rcp_all_out direct-out=$rcp_direct_out fixed-out=$rcp_fixed_out inert-out=$rcp_inert_out"

  lean_seed_progress r-lean-1 sess-lean-build

  # ---- leg 3d: an interrupted evaluation, composed (#497) -------------------
  # Same CLAUDE.md obligation: the interrupted budget's rc=4 is a new verdict path. The per-tool
  # suite proves the pair and the bound against one milestone in isolation, including the real
  # SIGKILL. What only a composed leg can show is the SEAM the scheduler reads it through — an
  # exhausted interrupted budget must reach `LEAN_GATE_OBSERVE=1` as a 4 while recording nothing,
  # or orchestrate-lean's verdict read would either miss the hard stop or write build-role rows
  # into the record on every round.
  #
  # The tree here is fully green — leg 1 walked milestones 1-5 on it and the spec is back — so
  # the unclosed rows are the only thing these calls can be reacting to. They are seeded by
  # DUPLICATING what the real writer just produced, not by hand-spelling a shape that would keep
  # passing after the writer moved.
  lean_gate 1 77 >/dev/null 2>&1; in_seed=$?
  in_started="$(grep -F '| milestone-1 | started |' "$LEAN_PROG" 2>/dev/null | head -n1)"
  in_concluded="$(grep -F '| milestone-1 | concluded |' "$LEAN_PROG" 2>/dev/null | head -n1)"
  for _ in 1 2 3 4 5; do printf '%s\n' "$in_started" >> "$LEAN_PROG"; done
  in_rows_before="$(lean_count '| milestone-1 |')"
  lean_gate_observe 1 77 >/dev/null 2>&1; in_obs=$?
  in_rows_obs="$(lean_count '| milestone-1 |')"
  lean_gate 1 77 >/dev/null 2>&1; in_rec=$?
  # THE DISCRIMINATOR: the bound is on UNCLOSED rows, not on how many evaluations have ever run.
  # Closing them — the state an uninterrupted run is always in — restores the milestone. Without
  # this the leg passes for a gate that simply stops working after six calls.
  for _ in 1 2 3 4 5; do printf '%s\n' "$in_concluded" >> "$LEAN_PROG"; done
  lean_gate 1 77 >/dev/null 2>&1; in_cleared=$?
  [[ -n "$in_started" && -n "$in_concluded" && "$in_seed" -eq 0 \
     && "$in_obs" -eq 4 && "$in_rows_obs" -eq "$in_rows_before" \
     && "$in_rec" -eq 4 && "$(lean_count '| milestone-1 | interrupted-exhausted | 5 unconcluded')" -eq 1 \
     && "$in_cleared" -eq 0 ]] \
    && pass "(lean-interrupted) five unconcluded rows reach the scheduler's observe seam as 4 with nothing recorded, hard-stop the recording call with an exhaustion record, and clear the moment they are concluded" \
    || fail "(lean-interrupted) seed=$in_seed observe=$in_obs rows $in_rows_before->$in_rows_obs recorded=$in_rec exhaustion=$(lean_count '| milestone-1 | interrupted-exhausted | 5 unconcluded') cleared=$in_cleared, expected 0/4/unmoved/4/1/0"
  lean_seed_progress r-lean-1 sess-lean-build

  # ---- leg 3b: the entry precondition, composed (#416) ----------------------
  # CLAUDE.md: a new gate contract extends the liveness scenario for every verdict path it
  # touches. This is that leg. The per-tool suite proves the refusal in isolation against one
  # milestone; what only a composed leg can show is that a run which skipped step 1 is stopped
  # at the call a REAL run makes — `all`, the whole-progression entry point a resume re-enters
  # through — and stopped there WITHOUT charging a fix attempt, before any milestone body runs.
  #
  # The tree here is fully green: leg 1 above just walked milestones 1-5 to completion on it.
  # So the ONLY thing that reds this is the missing row, which is what makes the pairing below
  # evidence rather than coincidence.
  lean_seed_unattested r-lean-1 sess-lean-build
  lean_gate all 77 >/dev/null 2>&1; ea_all=$?
  lean_gate 4 77 >/dev/null 2>&1; ea_m4=$?
  ea_attempts=$(grep -cF '| milestone-' "$LEAN_PROG" 2>/dev/null) || ea_attempts=0
  # ...and the same tree, one `entry` call later, walks the whole progression again.
  lean_seed_progress r-lean-1 sess-lean-build
  ea_healed_out="$(lean_gate 1 77)"; ea_healed=$?
  [[ "$ea_all" -eq 2 && "$ea_m4" -eq 2 && "$ea_attempts" -eq 0 && "$ea_healed" -eq 0 ]] \
    && pass "(lean-entry) an unattested run is refused at 'all' and at a milestone with exit 2, records nothing, and self-heals after one idempotent entry call" \
    || fail "(lean-entry) all=$ea_all m4=$ea_m4 milestone-lines=$ea_attempts healed=$ea_healed, expected 2/2/0/0: $ea_healed_out"

  # ---- leg 3c: the entry precondition's cutoff, composed (#444) -------------
  # Same CLAUDE.md obligation as leg 3b, for the verdict path #444 adds: the precondition now
  # DE-BLOCKS a branch that started before it existed. The per-tool suite proves the comparator
  # against fixtures; what only a composed leg can show is that de-blocking restores the RUN —
  # control reaches a milestone body and its terminal record gets written — rather than merely
  # suppressing a refusal and stalling somewhere quieter.
  #
  # The branch is aged in place rather than in a tree of its own: origin/main is moved to the
  # current head and one commit is authored before the cutoff, so merge-base's first commit is
  # that one. Both refs are restored afterwards — the added commit is empty, so a hard reset
  # leaves the tree byte-identical for the legs below, which is load-bearing since leg 4 onward
  # keeps composing milestone 4's patch-id freshness against this same history.
  lean_seed_unattested r-lean-1 sess-lean-build
  ec_head="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  ec_origin="$(git -C "$LEAN_TREE" rev-parse refs/remotes/origin/main)"
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main "$ec_head"
  GIT_AUTHOR_DATE='2026-08-07T13:22:50Z' lean_commit "work authored before the precondition existed"
  ec_out="$(lean_gate 1 77)"; ec_rc=$?
  ec_rows="$(lean_count '| entry | ledger=')"
  ec_satisfied="$(lean_count '| milestone-1 | satisfied')"
  git -C "$LEAN_TREE" reset --hard -q "$ec_head"
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main "$ec_origin"
  # ...and the DISCRIMINATOR: the identical unattested state on the un-aged branch is still
  # refused. Without it the leg passes for a precondition that stopped guarding anything at all.
  lean_gate 1 77 >/dev/null 2>&1; ec_paired=$?
  [[ "$ec_rc" -eq 0 && "$ec_rows" -eq 0 && "$ec_satisfied" -ge 1 && "$ec_paired" -eq 2 ]] \
    && pass "(lean-entry-since) a branch older than the entry precondition walks a milestone to its record while attesting nothing, and the same run on a newer branch is still refused" \
    || fail "(lean-entry-since) rc=$ec_rc entry-rows=$ec_rows milestone-1-records=$ec_satisfied paired=$ec_paired, expected 0/0/≥1/2: $ec_out"

  # ---- leg 4: the jira adapter, composed end to end ------------------------
  # The three adapter branch sites are proven in ISOLATION by lean-gate-selftest.sh's (n*)
  # cases. What only a composed leg can show is that they CHAIN: that the progress file
  # cmd_claim creates while making zero tracker writes is the same file milestones 1-5 later
  # satisfy, and that the milestones documented as adapter-INSENSITIVE really are — under an
  # alphanumeric ticket key, where every derived path (docs/plans/acme-ACME-7-lean.md) has a
  # different shape than the numeric case the other legs walk. Those are prose claims at
  # three surfaces with no oracle behind them until here.
  LEAN_CFG_J="$TMP/lean-config-jira.json"
  cat > "$LEAN_CFG_J" <<'LEANCFGJ'
{
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "abc/", "keyPattern": "[A-Z]+-[0-9]+" },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
LEANCFGJ
  LEAN_PROG_J="$TMP/lean-progress-jira.md"
  LEAN_JKEY="ACME-7"
  # env -u GH_BOT is load-bearing, not hygiene: the github arm dies on `${GH_BOT:?}`, so a leg
  # that completes without it in the environment is evidence the jira arm never reached there.
  # CLAUDE_CODE_SESSION_ID is the BUILD identity — `claim` stamps it into the progress file, and
  # milestone 4 compares it against the review session id in the committed record.
  lean_gate_j() { ( cd "$LEAN_TREE" && env -u GH_BOT SECOND_SHIFT_CONFIG="$LEAN_CFG_J" \
                    LEAN_PROGRESS_FILE="$LEAN_PROG_J" RUN_ID="r-lean-j" \
                    CLAUDE_CODE_SESSION_ID="sess-lean-jira-build" bash "$LEAN_GATE" "$@" 2>&1 ); }
  lean_count_j() { if [[ -f "$LEAN_PROG_J" ]]; then local n; n=$(grep -cF "$1" "$LEAN_PROG_J" 2>/dev/null) || n=0; echo "$n"; else echo 0; fi; }

  rm -f "$LEAN_PROG_J" "$LEAN_TREE/.claude/pipeline-state/$LEAN_JKEY-run-id"
  printf '{"tool":"Bash"}\n' > "$LEAN_TREE/.claude/audit/sess-lean-jira-build.jsonl"
  printf '# spec\n\n- AC-1: a thing\n' > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean.md"
  # The spec commits FIRST and on its own. `lean_commit` stages everything, so one combined
  # commit would put a code change inside the verdict's commit — a shape review-lean step 6
  # forbids, and one both freshness arms refuse.
  lean_commit "jira leg: build session pushes the spec"
  # P10 applies to the jira arm unchanged — the adapter moves the tracker WRITE, never the
  # authorship separation. So the record is REVIEW-authored (a session id distinct from the
  # build one `claim` stamps into the progress file below) and COMMITTED, or milestone 4
  # refuses it on authorship/freshness before the adapter is ever reached. `reviewed_head` is
  # the head as of the review, resolved before the record's own commit.
  printf 'verdict=approve\nrun_id: r-lean-jreview\nsession_id: sess-lean-jira-review\nrounds: 1\nreviewed_head: %s\n' \
    "$(git -C "$LEAN_TREE" rev-parse HEAD)" \
    > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean-verdict.md"
  lean_commit "jira leg: review verdict"
  cat > "$TMP/lean-pr-jira.json" <<LEANPRJ
[{ "number": 6, "url": "https://example.invalid/pr/6", "isDraft": false,
   "body": "Summary.\n\nSpec: docs/plans/acme-$LEAN_JKEY-lean.md\nVerdict: docs/plans/acme-$LEAN_JKEY-lean-verdict.md\n\n### Jira Items\n\nCloses [$LEAN_JKEY]\n" }]
LEANPRJ
  # EMPTY, not merely comment-less: under tracker.writes: false there is no trail to read, and
  # the same empty trail is a hard failure on the github legs above. That contrast IS the leg.
  echo '[]' > "$TMP/lean-comments-none.json"

  # `entry` FIRST, as SKILL.md step 1 orders it and as the precondition now requires — the
  # jira arm's claim is a build-role subcommand like any other.
  lean_gate_j entry "$LEAN_JKEY" >/dev/null 2>&1; je=$?
  lean_gate_j claim "$LEAN_JKEY" >/dev/null 2>&1; jc=$?
  lean_gate_j 1 "$LEAN_JKEY" >/dev/null 2>&1; j1=$?
  lean_gate_j 2 "$LEAN_JKEY" >/dev/null 2>&1; j2=$?
  lean_gate_j 3 "$LEAN_JKEY" >/dev/null 2>&1; j3=$?
  lean_gate_j 4 "$LEAN_JKEY" >/dev/null 2>&1; j4=$?
  lean_gate_j 5 "$LEAN_JKEY" --pr-file "$TMP/lean-pr-jira.json" \
              --comments-file "$TMP/lean-comments-none.json" >/dev/null 2>&1; j5=$?
  [[ "$je$jc$j1$j2$j3$j4$j5" == "0000000" ]] \
    && pass "(lean-jira) entry + claim + milestones 1-5 all exit 0 under tracker.type: jira, with no GH_BOT and an empty comment trail" \
    || fail "(lean-jira) exit codes were $je$jc$j1$j2$j3$j4$j5, expected 0000000"

  lean_sat_j=0
  for m in 1 2 3 4 5; do
    [[ "$(lean_count_j "| milestone-$m | satisfied")" -eq 1 ]] && lean_sat_j=$((lean_sat_j + 1))
  done
  [[ "$lean_sat_j" -eq 5 ]] \
    && pass "(lean-jira) the chain lands in the SAME progress file cmd_claim created — one satisfied line per milestone" \
    || fail "(lean-jira) expected 5 single satisfied lines in the claim-created file, got $lean_sat_j"

  # The claim writes nothing to the tracker, so the run-id anchor in this file is the only
  # thing left tying the run together. If it is absent the jira arm has no record at all.
  [[ "$(lean_count_j '| claim | tracker=jira |')" -eq 1 && "$(lean_count_j 'run_id: r-lean-j')" -ge 1 ]] \
    && pass "(lean-jira) the write-free claim still records the claim line and the run-id anchor" \
    || fail "(lean-jira) the jira claim left no claim line or no run-id anchor"

  # ---- non-vacuity for the jira leg ---------------------------------------
  # Under jira the verdict-record reference moved from the closing comment INTO the PR body.
  # Strip it and the leg must red — otherwise this leg would pass on a PR carrying no link to
  # the artifact the whole gate exists to surface.
  cat > "$TMP/lean-pr-jira-nv.json" <<LEANPRJNV
[{ "number": 6, "url": "https://example.invalid/pr/6", "isDraft": false,
   "body": "Summary.\n\nSpec: docs/plans/acme-$LEAN_JKEY-lean.md\n\n### Jira Items\n\nCloses [$LEAN_JKEY]\n" }]
LEANPRJNV
  lean_gate_j 5 "$LEAN_JKEY" --pr-file "$TMP/lean-pr-jira-nv.json" \
              --comments-file "$TMP/lean-comments-none.json" >/dev/null 2>&1; jnv=$?
  [[ "$jnv" -ne 0 ]] \
    && pass "(lean-jira-nv) non-vacuity: the same leg reds when the PR body drops the verdict-record path" \
    || fail "(lean-jira-nv) milestone-5 passed under jira with no verdict reference anywhere — the leg is vacuous"

  # P10 is NOT adapter-scoped, and this is where that is asserted rather than assumed. The
  # adapter moves the tracker WRITE; it must not become a second way to author your own
  # verdict. Re-write the record carrying the BUILD session id and milestone 4 must refuse on
  # the jira arm exactly as it does on github.
  printf 'verdict=approve\nrun_id: r-lean-j\nsession_id: sess-lean-jira-build\nrounds: 2\n' \
    > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean-verdict.md"
  lean_commit "jira leg: build-authored verdict (must be refused)"
  lean_gate_j 4 "$LEAN_JKEY" >/dev/null 2>&1; jp10=$?
  [[ "$jp10" -ne 0 ]] \
    && pass "(lean-jira-p10) a build-authored verdict is refused on the jira arm too — the adapter is no authorship loophole" \
    || fail "(lean-jira-p10) milestone-4 accepted a verdict carrying the build session id under jira"

  # ---- extraLanes composition (#379) — the skip and red verdict paths, end to end --------
  # NOT a duplicate of lean-gate-selftest.sh's per-tool AC coverage (that suite drives
  # milestone 3 alone against dozens of shapes): this is the composed-verdict-path
  # obligation the repo's own testing rule names — a fresh, isolated tree because legs 1-7
  # and the jira sub-section above leave $LEAN_TREE mid-rebase/branch-switched, unrelated to
  # this composition.
  EL_TREE="$TMP/lean-el-tree"
  mkdir -p "$EL_TREE/docs/plans" "$EL_TREE/.claude/audit"
  git -C "$EL_TREE" init -q
  git -C "$EL_TREE" config user.email lean-el@example.invalid
  git -C "$EL_TREE" config user.name lean-el-scenario
  printf '.claude/\n' > "$EL_TREE/.gitignore"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture base" >/dev/null 2>&1
  git -C "$EL_TREE" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$EL_TREE/src"
  printf 'x\n' > "$EL_TREE/src/App.tsx"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture change" >/dev/null 2>&1

  EL_ISSUE="$TMP/lean-el-issue.json"
  printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$EL_ISSUE"
  el_cfg() { # el_cfg <label> <extraLanes-json>
    local out="$TMP/lean-el-cfg-$1.json"
    jq --argjson el "$2" '.commands.acme.extraLanes = $el' "$LEAN_CFG" > "$out" 2>/dev/null
    printf '%s' "$out"
  }
  EL_SID="sess-lean-el-build"
  printf '{"tool":"Bash"}\n' > "$EL_TREE/.claude/audit/$EL_SID.jsonl"
  el_gate() { # el_gate <config-file> <progress-file> <args...>
    local cfg="$1" prog="$2"; shift 2
    ( unset RUN_ID GH_BOT; cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
      CLAUDE_CODE_SESSION_ID="$EL_SID" bash "$LEAN_GATE" --issue-file "$EL_ISSUE" "$@" 2>&1 )
  }
  # Each extraLanes case gets its own progress file, so each composes its own `entry` first.
  el_attest() { el_gate "$1" "$2" entry 777 >/dev/null 2>&1; }

  # skip: a non-matching `when` composes into a fully green run, exactly like (lean-green)
  # above — extraLanes must not silently block a run it has nothing to say about.
  EL_SPEC="$EL_TREE/docs/plans/acme-777-lean.md"
  EL_VERDICT="$EL_TREE/docs/plans/acme-777-lean-verdict.md"
  printf '# spec\n\n- AC-1: a thing\n' > "$EL_SPEC"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el: spec" >/dev/null 2>&1
  printf 'verdict=approve\nrun_id: r-el-review\nsession_id: sess-el-review\nrounds: 1\nreviewed_head: %s\n' \
    "$(git -C "$EL_TREE" rev-parse HEAD)" > "$EL_VERDICT"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el: verdict" >/dev/null 2>&1
  cat > "$TMP/lean-el-pr.json" <<LEANELPR
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false,
   "body": "Closes #777\n\nSpec: docs/plans/acme-777-lean.md" }]
LEANELPR
  # The build run-id cache, and the PR marker milestone 5 stamps with it (#359) — same
  # reasoning as the leg-1 tree above.
  mkdir -p "$EL_TREE/.claude/pipeline-state"
  printf 'r-el-1' > "$EL_TREE/.claude/pipeline-state/777-run-id"
  cat > "$TMP/lean-el-comments.json" <<LEANELC
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-el-1 -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-777-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: r-el-1 -->\n<!-- stage: lean-pr-marker -->" }]
LEANELC
  EL_CFG_SKIP="$(el_cfg skip '[{"name":"scoped","when":["docs/nomatch/**/*.md"],"commands":["echo should-not-run"],"failureClass":"TEST_FAILURE"}]')"
  EL_PROG_SKIP="$TMP/lean-el-prog-skip.md"
  el_attest "$EL_CFG_SKIP" "$EL_PROG_SKIP"
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 1 777 >/dev/null 2>&1; els1=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 2 777 >/dev/null 2>&1; els2=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 3 777 >/dev/null 2>&1; els3=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 4 777 >/dev/null 2>&1; els4=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 5 777 --pr-file "$TMP/lean-el-pr.json" \
          --comments-file "$TMP/lean-el-comments.json" >/dev/null 2>&1; els5=$?
  [[ "$els1$els2$els3$els4$els5" == "00000" ]] \
    && pass "(lean-el-skip) a non-matching extraLanes 'when' composes into a fully green run (milestones 1-5)" \
    || fail "(lean-el-skip) exit codes were $els1$els2$els3$els4$els5, expected 00000"
  el_skip_n=$(grep -cF "milestone-3 | skipped | extra lane 'scoped'" "$EL_PROG_SKIP" 2>/dev/null) || el_skip_n=0
  [[ "$el_skip_n" -ge 1 ]] \
    && pass "(lean-el-skip) the skip composes with a recorded progress-file line, not a silent pass" \
    || fail "(lean-el-skip) no skip line recorded in the composed run"

  # red: a failing extraLane composes the same way a fixed-key failure already does — 'all'
  # stops at milestone 3 and never reaches 4/5, the composition obligation the fixed-key
  # legs above never exercise for extraLanes specifically. A fresh progress file: the point
  # is what THIS run records, not what the skip leg above already left behind.
  EL_CFG_RED="$(el_cfg red '[{"name":"boom","commands":["exit 3"],"failureClass":"TEST_FAILURE"}]')"
  EL_PROG_RED="$TMP/lean-el-prog-red.md"
  el_attest "$EL_CFG_RED" "$EL_PROG_RED"
  out="$(el_gate "$EL_CFG_RED" "$EL_PROG_RED" all 777)"; elr=$?
  if [[ "$elr" -ne 0 ]] && grep -q 'stopped at milestone-3' <<<"$out"; then
    pass "(lean-el-red) a failing extraLane composes into 'all' stopping at milestone-3"
  else fail "(lean-el-red) expected 'all' to stop at milestone-3, got rc=$elr: $out"; fi
  el_red_n=$(grep -cF '| milestone-4 | satisfied' "$EL_PROG_RED" 2>/dev/null) || el_red_n=0
  [[ "$el_red_n" -eq 0 ]] \
    && pass "(lean-el-red) milestone-4 is never recorded satisfied when extraLanes reds milestone-3 first" \
    || fail "(lean-el-red) milestone-4 was recorded satisfied despite milestone-3 failing"

  # ---- zero configured verify lanes (#392) — the RED verdict path, composed -------------
  # (lean-el-red) above proves a milestone-3 red composes when a lane RAN and failed. This
  # guard reds when no lane was ever configured, which is the opposite trigger and reachable
  # by a different predicate. It needs its own leg because every lean fixture in this suite
  # carries `allowUnverified: true` to reach a green chain at all — strip the opt-out and
  # nothing else, and the guard's red branch is the only thing that moved. Reuses the EL
  # substrate: same isolated tree, same spec/verdict commits, no extraLanes anywhere.
  ZV_CFG="$TMP/lean-zv-cfg.json"
  jq 'del(.commands.acme.allowUnverified)' "$LEAN_CFG" > "$ZV_CFG"
  ZV_PROG="$TMP/lean-zv-prog.md"
  el_attest "$ZV_CFG" "$ZV_PROG"
  out="$(el_gate "$ZV_CFG" "$ZV_PROG" all 777)"; zvr=$?
  if [[ "$zvr" -ne 0 ]] && grep -q 'stopped at milestone-3' <<<"$out" \
     && grep -q 'no verifying lane configured' <<<"$out"; then
    pass "(lean-zv-red) an undeclared zero-verify-lane config composes into 'all' stopping at milestone-3"
  else fail "(lean-zv-red) expected 'all' to stop at milestone-3 naming the zero-lane reason, got rc=$zvr: $out"; fi
  zv_red_n=$(grep -cF '| milestone-4 | satisfied' "$ZV_PROG" 2>/dev/null) || zv_red_n=0
  [[ "$zv_red_n" -eq 0 ]] \
    && pass "(lean-zv-red) milestone-4 is never recorded satisfied when the zero-lane guard reds milestone-3" \
    || fail "(lean-zv-red) milestone-4 was recorded satisfied despite the zero-lane guard failing"
  # ---- design legs (#394) — the armed lane composed across all three verdict paths -------
  # Per-tool fixtures prove each armed assertion against a fixture. What only a composed leg
  # proves is that the armed lane rides the SAME chain everything else does: the same fix
  # budget, the same hard stop, the same milestone-4 handoff, the same milestone-5 terminal
  # write. An armed run that quietly grew its own failure economics would be invisible to
  # lean-gate-selftest.sh, which drives each milestone alone.
  #
  # Its OWN tree and config: every leg above ran unarmed, and arming is config-keyed, so the
  # shared LEAN_CFG cannot carry a provider without changing what those legs compose.
  LEAN_DTREE="$TMP/lean-dtree"
  mkdir -p "$LEAN_DTREE/docs/plans" "$LEAN_DTREE/.claude"
  git -C "$LEAN_DTREE" init -q
  git -C "$LEAN_DTREE" config user.email lean@example.invalid
  git -C "$LEAN_DTREE" config user.name lean-scenario
  printf '.claude/\n' > "$LEAN_DTREE/.gitignore"
  LEAN_DSTUB="$TMP/lean-render-stub.sh"
  LEAN_DMODE="$TMP/lean-render-mode"
  cat > "$LEAN_DSTUB" <<LEANSTUB
#!/usr/bin/env bash
MODEF="$LEAN_DMODE"
LEANSTUB
  cat >> "$LEAN_DSTUB" <<'LEANSTUB'
route=""; state=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --route) route="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    --out)   out="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
mode=ok; [ -f "$MODEF" ] && mode="$(cat "$MODEF")"
case "$mode" in
  fail) echo "render harness unavailable" >&2; exit 5 ;;
  *)    printf 'PNG-%s-%s\n' "$route" "$state" > "$out" ;;
esac
exit 0
LEANSTUB
  LEAN_DCFG="$TMP/lean-config-design.json"
  cat > "$LEAN_DCFG" <<LEANDCFG
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } },
  "design": { "provider": "figma",
              "liveRender": { "command": "bash $LEAN_DSTUB --route {route} --state {state} --out {out}" } }
}
LEANDCFG
  LEAN_DPROG="$TMP/lean-progress-design.md"
  LEAN_DSPEC="$LEAN_DTREE/docs/plans/acme-88-lean.md"
  LEAN_DSID="sess-lean-d-build"
  mkdir -p "$LEAN_DTREE/.claude/audit"
  printf '{"tool":"Bash"}\n' > "$LEAN_DTREE/.claude/audit/$LEAN_DSID.jsonl"
  lean_dgate() { ( unset RUN_ID GH_BOT; cd "$LEAN_DTREE" && SECOND_SHIFT_CONFIG="$LEAN_DCFG" LEAN_PROGRESS_FILE="$LEAN_DPROG" \
                   CLAUDE_CODE_SESSION_ID="$LEAN_DSID" \
                   bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 ); }
  lean_dcommit() { git -C "$LEAN_DTREE" add -A >/dev/null 2>&1
                   git -C "$LEAN_DTREE" commit -q --allow-empty -m "${1:-lean design fixture}" >/dev/null 2>&1; }
  lean_dseed() { rm -f "$LEAN_DPROG"
                 { echo "# lean run — issue 88"; echo ""; echo "run_id: r-lean-d"; echo "session_id: sess-lean-d-build"; } > "$LEAN_DPROG"
                 lean_dgate entry 88 >/dev/null 2>&1; }
  lean_dverdict() { # lean_dverdict <session> <run-id> [args...]
    local sid="$1" rid="$2"; shift 2
    rm -f "$LEAN_DTREE/.claude/pipeline-state/88-review-run-id"
    ( unset RUN_ID; cd "$LEAN_DTREE" && SECOND_SHIFT_CONFIG="$LEAN_DCFG" LEAN_PROGRESS_FILE="$LEAN_DPROG" \
      CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$LEAN_GATE" verdict 88 "$@" 2>&1 )
  }
  {
    printf '# spec\n\n- AC-1: a thing\n\n## Design\n\nHandoff: https://design.example.invalid/f/a\n\n'
    printf '| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n'
    printf '| RS-1 | prospects | default | AC-1 |\n| RS-2 | prospects | filters expanded | AC-1 |\n'
  } > "$LEAN_DSPEC"
  lean_dcommit "base"
  git -C "$LEAN_DTREE" update-ref refs/remotes/origin/main HEAD
  printf 'the work\n' > "$LEAN_DTREE/subject.txt"
  lean_dcommit "the build session pushes the armed spec"

  # ---- design leg 1: a blocking render red walks the SAME budget to the hard stop --------
  # D-2's whole point: there is no degraded state, so an unreachable render harness spends the
  # milestone's attempts and hard-stops exactly as a failing test suite does. If the armed lane
  # had its own economics this sequence would not be 1/1/1/4.
  lean_dseed
  printf 'fail\n' > "$LEAN_DMODE"
  lean_drcs=""
  for _ in 1 2 3 4; do lean_dgate 3 88 >/dev/null 2>&1; lean_drcs="$lean_drcs$?"; done
  [[ "$lean_drcs" == "1114" ]] \
    && pass "(lean-design-budget) a blocking render failure spends the shared 3-attempt budget and hard-stops (rc=4)" \
    || fail "(lean-design-budget) exit sequence was $lean_drcs, expected 1114"
  lean_darmed=$(grep -cF '| milestone-3 | armed |' "$LEAN_DPROG" 2>/dev/null) || lean_darmed=0
  lean_dattempts=$(grep -cF '| milestone-3 | attempt |' "$LEAN_DPROG" 2>/dev/null) || lean_dattempts=0
  [[ "$lean_darmed" -eq 1 && "$lean_dattempts" -eq 4 ]] \
    && pass "(lean-design-budget) the armed record is written once and counts for nothing — 4 attempts, 1 lock" \
    || fail "(lean-design-budget) armed=$lean_darmed attempts=$lean_dattempts, expected 1 and 4"

  # ---- design leg 2: the receipt commits, then milestone 4 refuses an unscored verdict ----
  printf 'ok\n' > "$LEAN_DMODE"
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1; ld_render=$?
  lean_dcommit "the render receipt"
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1; ld_green=$?
  [[ "$ld_render" -eq 1 && "$ld_green" -eq 0 ]] \
    && pass "(lean-design-render) the receipt reds until committed, then the same evaluation passes" \
    || fail "(lean-design-render) expected rc 1 then 0, got $ld_render then $ld_green"

  # A review round that scored no fidelity: the handoff must round-trip, not certify.
  lean_dseed
  lean_dverdict sess-lean-d-review r-lean-d-review --pr 8 --verdict approve >/dev/null 2>&1
  lean_dcommit "a verdict that scored no fidelity"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_nofid=$?

  # ...and a stale receipt under an otherwise-fresh verdict — D-10's backstop, composed.
  lean_dseed
  lean_dverdict sess-lean-d-review2 r-lean-d-review2 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "a verdict scoring fidelity pass"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_pass=$?
  printf 'a fix lands after the render\n' > "$LEAN_DTREE/subject.txt"
  lean_dcommit "a fix, leaving the receipt behind"
  lean_dseed
  lean_dverdict sess-lean-d-review3 r-lean-d-review3 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "an honest record on top of a stale receipt"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_stale=$?
  [[ "$ld_nofid" -eq 5 && "$ld_pass" -eq 0 && "$ld_stale" -eq 1 ]] \
    && pass "(lean-design-verdict) milestone 4 refuses an unscored verdict (5 — get a review round), passes a scored one, and refuses a stale receipt (1 — re-render, a BUILD action)" \
    || fail "(lean-design-verdict) expected rc 5/0/1, got $ld_nofid/$ld_pass/$ld_stale"

  # ---- design leg 3: post-approve, `all` reaches the milestone-5 terminal write ----------
  # The livelock this ordering exists to prevent: the mandated pre-close sweep re-evaluates
  # milestone 3 AFTER the approve, and a re-render there would rewrite the receipt inside
  # reviewed_patch_id and void the verdict the run just earned. So the sweep must pass on the
  # binding alone — with the PNGs deleted, which is also every fresh-worktree resume.
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1
  lean_dcommit "the re-rendered receipt for the fixed head"
  lean_dseed
  lean_dverdict sess-lean-d-review4 r-lean-d-review4 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "the round-2 record on the fresh receipt"
  rm -rf "$LEAN_DTREE/.claude/lean-renders/88"
  cat > "$TMP/lean-design-pr.json" <<'LEANDPR'
[{ "number": 8, "url": "https://example.invalid/pr/8", "isDraft": false,
   "body": "Closes #88\n\nSpec: docs/plans/acme-88-lean.md" }]
LEANDPR
  # The build run-id cache, and the PR marker milestone 5 stamps with it (#359).
  mkdir -p "$LEAN_DTREE/.claude/pipeline-state"
  printf 'r-lean-d' > "$LEAN_DTREE/.claude/pipeline-state/88-run-id"
  cat > "$TMP/lean-design-comments.json" <<'LEANDC'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-lean-d -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-88-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: r-lean-d -->\n<!-- stage: lean-pr-marker -->" }]
LEANDC
  lean_dseed
  lean_dgate 1 88 >/dev/null 2>&1; ldf1=$?
  lean_dgate 2 88 >/dev/null 2>&1; ldf2=$?
  lean_dgate 3 88 >/dev/null 2>&1; ldf3=$?
  lean_dgate 4 88 >/dev/null 2>&1; ldf4=$?
  lean_dgate 5 88 --pr-file "$TMP/lean-design-pr.json" \
             --comments-file "$TMP/lean-design-comments.json" >/dev/null 2>&1; ldf5=$?
  [[ "$ldf1$ldf2$ldf3$ldf4$ldf5" == "00000" ]] \
    && pass "(lean-design-terminal) post-approve, milestones 1-5 all exit 0 with every rendered PNG deleted" \
    || fail "(lean-design-terminal) exit codes were $ldf1$ldf2$ldf3$ldf4$ldf5, expected 00000"
  [[ ! -d "$LEAN_DTREE/.claude/lean-renders/88" ]] \
    && pass "(lean-design-terminal) and nothing re-rendered — the receipt's binding alone carried the sweep" \
    || fail "(lean-design-terminal) the post-approve sweep re-rendered, which would void the verdict it just earned"

  # ---- non-vacuity for the design legs ---------------------------------------------------
  # The whole block would stay green if arming never took. Disarm the spec on a run that
  # already armed and the same chain must red — at milestone 1, before any of it.
  {
    printf '# spec\n\n- AC-1: a thing\n\n## Design\n\nDesign: none — reconsidered mid-run.\n'
  } > "$LEAN_DSPEC"
  lean_dgate 1 88 >/dev/null 2>&1; ld_nv=$?
  [[ "$ld_nv" -ne 0 ]] \
    && pass "(lean-design-nv) non-vacuity: the same chain reds when the armed spec is disarmed mid-run" \
    || fail "(lean-design-nv) a mid-run disarm passed milestone 1 — the design legs are vacuous"

  # ---- leg 8: the SCHEDULER's re-entry admission, composed to a terminal write (#514) -----
  # Same CLAUDE.md obligation as legs 3b/3c/3d: a new gate contract extends the liveness
  # scenario for every verdict path it touches. #510 gave orchestrate-lean.sh's preflight a
  # SECOND accepting state — the claimed label AND this lane's bot-authored `lean-claimed`
  # marker — and it is covered only by orchestrate-lean-selftest.sh, which drives a FAKE gate
  # and a fake session binary. That is the component checked against itself; no scenario ever
  # composed an admitted re-entry through to a terminal state.
  #
  # THIS IS THE FIRST LEG IN THIS FILE TO INVOKE THE SCHEDULER AT ALL, which is why it composes
  # the whole lane rather than the admission alone: real orchestrate-lean.sh -> real
  # lean-gate.sh -> a real `git worktree` on the work branch -> the close-out's
  # `| milestone-5 | satisfied` row. That row is the very token the scheduler's own close-out
  # check reads back, so preflight is genuinely ON the path to a terminal state — which is what
  # makes the non-vacuity arm below mechanical rather than a claim.
  #
  # ITS CEILING, stated rather than papered over: the session binary is a SCRIPT. This proves
  # the scheduler composes with the gate; it cannot prove a real `claude -p` build session
  # re-enters. CI is model-free by design, and orchestrate-lean-selftest.sh:11-16 states the
  # same ceiling for itself. That fidelity is provable only by an operator-run end to end.
  #
  # A re-entry admission is recorded in NO artifact — #510 kept the predicate read-only so the
  # scheduler's "writes nothing" premise stays true — so the leg keys on the scheduler's own
  # `ok intake: re-entry` line and the marker's run id alongside rc and the milestone-5 row.
  RE_ORCH="$HERE/../run-lean/orchestrate-lean.sh"
  if [[ ! -f "$RE_ORCH" ]]; then
    # Absence is a FAILURE, the same posture the lean legs above take: run-lean SHIPS in this
    # plugin, so a missing scheduler means this leg never ran — and a skipped leg reporting PASS
    # is the vacuous green this suite exists to prevent.
    fail "(lean-reentry) orchestrate-lean.sh not found at $RE_ORCH — the scheduler leg did not run"
  else
    RE_KEY=55
    RE_BRANCH="claude/acme-$RE_KEY"
    RE_RUN="r-lean-reentry"
    RE_PR_NUM=21
    RE_DIR="$TMP/lean-reentry"
    RE_WT="$TMP/lean-reentry-wt"
    RE_LEDGER_DIR="$LEAN_TREE/.claude/audit"
    mkdir -p "$RE_DIR"
    re_count() { # re_count <file> <fixed-string>
      if [[ -f "$1" ]]; then local n; n=$(grep -cF "$2" "$1" 2>/dev/null) || n=0; echo "$n"; else echo 0; fi; }

    # ITS OWN config, progress file and issue key (never legs 1-7's), because those legs thread
    # shared mutable state in order — leg 1b explicitly runs on the state leg 1 left. An own key
    # also keeps the `<key>-run-id` cache and the marker fixtures clear of them. $LEAN_TREE is
    # reused as MAIN_ROOT deliberately: the scheduler resolves the lane worktree from
    # `git worktree list --porcelain` and MAIN_ROOT from `--git-common-dir`, so a stub directory
    # would leave the one piece of git parsing in that script unexercised.
    RE_CFG="$RE_DIR/config.json"
    cat > "$RE_CFG" <<'RECFG'
{
  "tracker": { "type": "github", "branchPrefix": "claude/acme-",
               "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
RECFG

    # The tracker fixtures. NO queue label — that is the state `claim` leaves behind and the
    # exact reason preflight had to grow a second accepting state.
    RE_LABELS="$RE_DIR/labels"
    printf 'in-progress\n' > "$RE_LABELS"
    # Milestone 1's pause-and-ask check reads the issue body live; no Open Regions section, so
    # it no-ops without a second tracker read.
    RE_BODY="$RE_DIR/issue-body"
    printf '# issue\n\nNo Open Regions section here.\n' > "$RE_BODY"
    # The staleness ticket arm's read: `issue view <n> --json state --jq '.state'`, whose answer is
    # a bare state string. Without an arm for it the stub's catch-all exits 1 and the gate fails
    # CLOSED on an unreadable tracker — correct behavior against a fixture with nothing to say.
    RE_STATE="$RE_DIR/issue-state"
    printf 'OPEN\n' > "$RE_STATE"
    RE_PR="$RE_DIR/pr.json"
    cat > "$RE_PR" <<REPR
[{ "number": $RE_PR_NUM, "url": "https://example.invalid/pr/$RE_PR_NUM", "isDraft": false,
   "body": "Closes #$RE_KEY\n\nSpec: docs/plans/acme-$RE_KEY-lean.md" }]
REPR
    # The entry sweep's own shape (`--state all`), served with a state field so a run that ever
    # reached it could not read this lane's own open PR as closed and destroy its worktree.
    RE_PR_ALL="$RE_DIR/pr-all.json"
    printf '[{ "number": %s, "state": "OPEN" }]\n' "$RE_PR_NUM" > "$RE_PR_ALL"
    RE_PR_NUMS="$RE_DIR/pr-numbers"
    printf '%s\n' "$RE_PR_NUM" > "$RE_PR_NUMS"

    # THE RE-ENTRY EVIDENCE, plus the two comments milestone 5 needs: a closing comment naming
    # the verdict record, and the PR build-identity marker carrying THIS run's id so cmd_mark
    # takes its no-op branch (leg 1b owns the marker's bytes; asserting them here would only
    # duplicate it, and the no-op branch needs no GH_BOT stub).
    RE_COMMENTS="$RE_DIR/comments.json"
    cat > "$RE_COMMENTS" <<REC
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- dev-pipeline -->\n<!-- run_id: $RE_RUN -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-$RE_KEY-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: $RE_RUN -->\n<!-- session_id: sess-lean-re-build -->\n<!-- stage: lean-pr-marker -->" }]
REC
    # The non-vacuity trail: byte-identical except that the claim marker is authored by a USER.
    # Issue comments are writable by any account on a public repo, so this is the state a hand-
    # reset ticket presents, and the whole trail then has nothing bot-authored to admit.
    RE_COMMENTS_NV="$RE_DIR/comments-nv.json"
    jq '(.[] | select((.body // "") | test("stage: lean-claimed")) | .user.type) = "User"' \
      "$RE_COMMENTS" > "$RE_COMMENTS_NV"

    # ONE fake tracker CLI, injected via GH= and serving BOTH scripts — orchestrate-lean.sh and
    # lean-gate.sh resolve their client identically (`${GH:-gh}`), so one seam covers the pair.
    # The gate's --pr-file / --comments-file / --issue-file seams the legs above use are NOT
    # available here: the scheduler passes none of them to the gate subprocesses it spawns.
    # Written fresh rather than shared with orchestrate-lean-selftest.sh's — a fake gh is not
    # production logic, so a second copy is not a mirror harness, and coupling the two would let
    # one suite's fixture edit red the other.
    RE_GH="$RE_DIR/gh"
    cat > "$RE_GH" <<'REGH'
#!/usr/bin/env bash
echo "$*" >> "$RE_GH_LOG"
case "$1" in
  issue)
    case "$*" in
      *"--json labels"*) cat "$RE_LABELS" ;;
      *"--json body"*)   cat "$RE_BODY" ;;
      *"--json state"*)  cat "$RE_STATE" ;;
      *) exit 1 ;;
    esac ;;
  pr)
    case "$*" in
      *"--state all"*) cat "$RE_PR_ALL" ;;
      *"--jq"*)        cat "$RE_PR_NUMS" ;;
      *)               cat "$RE_PR" ;;
    esac ;;
  api)
    case "$*" in *comments*) cat "$RE_COMMENTS_LIVE" ;; *) exit 1 ;; esac ;;
  *) exit 1 ;;
esac
REGH
    chmod +x "$RE_GH"

    # The session fake. It dispatches on the PROMPT in ARGV plus a spawn counter — the close-out
    # is a SECOND build-lean spawn — and it advances the run ONLY by calling the REAL gate.
    # Hand-written progress rows are the mirror-harness failure CLAUDE.md forbids: a copy cannot
    # fail on a production edit, so the leg would stay green after the gate's writer and the
    # scheduler's reader drifted apart, which is precisely the drift a composed leg exists for.
    RE_SESSION="$RE_DIR/session"
    cat > "$RE_SESSION" <<'RESESS'
#!/usr/bin/env bash
n=$(( $(cat "$RE_DIR/spawns" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$RE_DIR/spawns"
echo "spawn $n: $*" >> "$RE_DIR/session.log"
g() { ( unset LEAN_GATE_ANY_TREE; cd "$RE_WT" && bash "$RE_GATE" "$@" ) >> "$RE_DIR/session.log" 2>&1; }
case "$*" in
  *review-lean*)
    # A DISTINCT identity on BOTH axes, or milestone 4 refuses the record on authorship (P10)
    # before freshness is ever reached. The record comes from the REAL `verdict` subcommand: the
    # patch id it stamps is the thing milestone 4 recomputes, so a hand-written one would compose
    # a record no review session produces.
    export CLAUDE_CODE_SESSION_ID=sess-lean-re-review RUN_ID=r-lean-re-review
    g verdict "$RE_KEY" --pr "$RE_PR_NUM" --verdict approve || exit 1
    git -C "$RE_WT" add -A >/dev/null 2>&1
    git -C "$RE_WT" commit -q -m "review session commits its verdict record" >/dev/null 2>&1 || exit 1
    # #531: the PUSH, which every commit in these legs now carries. review-lean step 6 pushes the
    # record — the merge boundary reads it off the PR — and the scheduler's in-flight check reads
    # exactly that. A fixture that committed without pushing would be modelling the DEFECT.
    git -C "$RE_WT" push -q origin "HEAD:refs/heads/$RE_BRANCH" >/dev/null 2>&1 || exit 1
    ;;
  *build-lean*)
    if [ "$n" -eq 1 ]; then
      # SKILL.md step 2 is SKIPPED, which is the whole shape of a re-entry: the marker is posted
      # and the labels are swapped already. The run's ESTABLISHED id is exported rather than
      # minted, so `entry` seeds the cache with the id the marker on the ticket carries.
      export CLAUDE_CODE_SESSION_ID=sess-lean-re-build RUN_ID="$RE_RUN"
      printf '{"tool":"Bash"}\n' > "$RE_LEDGER_DIR/sess-lean-re-build.jsonl"
      g entry "$RE_KEY" || exit 1
      printf '# spec\n\n- AC-1: the composed re-entry\n' > "$RE_WT/docs/plans/acme-$RE_KEY-lean.md"
      git -C "$RE_WT" add -A >/dev/null 2>&1
      git -C "$RE_WT" commit -q -m "build session pushes the spec" >/dev/null 2>&1 || exit 1
      git -C "$RE_WT" push -q origin "HEAD:refs/heads/$RE_BRANCH" >/dev/null 2>&1 || exit 1
      g 1 "$RE_KEY" || exit 1
      g 2 "$RE_KEY" || exit 1
      g 3 "$RE_KEY" || exit 1
    else
      # The CLOSE-OUT is a fresh session, so a fresh id — which its own `entry` admits to the
      # build set (#446), and without which milestone 5's `mark` would refuse to stamp it.
      export CLAUDE_CODE_SESSION_ID=sess-lean-re-close RUN_ID="$RE_RUN"
      printf '{"tool":"Bash"}\n' > "$RE_LEDGER_DIR/sess-lean-re-close.jsonl"
      g entry "$RE_KEY" || exit 1
      g all "$RE_KEY" || exit 1
      g 5 "$RE_KEY" || exit 1
    fi
    ;;
  *) exit 1 ;;
esac
exit 0
RESESS
    chmod +x "$RE_SESSION"

    RE_PROG="$RE_DIR/progress.md"
    RE_PROG_NV="$RE_DIR/progress-nv.md"
    RE_GH_LOG="$RE_DIR/gh.log"
    # D-8: the leg must START with no `| milestone-5 | satisfied` row. append_satisfied is
    # idempotent and the progress file is keyed by issue, so the scheduler's close-out check —
    # which demands a NEW row — cannot move its token over a record that already carries one.
    rm -f "$RE_PROG" "$RE_PROG_NV" "$RE_GH_LOG" "$RE_DIR/spawns" "$RE_DIR/session.log" \
          "$LEAN_TREE/.claude/pipeline-state/$RE_KEY-run-id" \
          "$LEAN_TREE/.claude/pipeline-state/$RE_KEY-review-run-id"
    # A REAL remote, which none of the legs above needed: they hand-set `refs/remotes/origin/main`
    # with `update-ref`, but the staleness base arm FETCHES, and a fetch it cannot complete is
    # exit 1 by design rather than a clean answer. Pushed at the branch point, so the arm's answer
    # here is "the base has not moved" — the FIRING path is owned by orchestrate-lean-selftest.sh's
    # (v13)/(v14), which drive the same real gate against a base that did move.
    RE_ORIGIN="$RE_DIR/origin.git"
    rm -rf "$RE_ORIGIN"
    git init -q --bare "$RE_ORIGIN" >/dev/null 2>&1
    git -C "$LEAN_TREE" remote remove origin >/dev/null 2>&1
    git -C "$LEAN_TREE" remote add origin "$RE_ORIGIN" >/dev/null 2>&1
    git -C "$LEAN_TREE" push -q origin HEAD:refs/heads/main >/dev/null 2>&1
    git -C "$LEAN_TREE" worktree add -q -b "$RE_BRANCH" "$RE_WT" HEAD >/dev/null 2>&1; re_wt=$?

    # CLAUDE_CODE_SESSION_ID is UNSET on the scheduler, which is the real shape: it never sets or
    # passes one, and each spawn's identity is the harness's own stamp — here, the fake's export.
    # GH_BOT is unset too, and that is load-bearing rather than hygiene: an ambient one would
    # send cmd_mark's write to a LIVE bot if its no-op branch ever stopped being taken.
    re_run() { # re_run <progress-file> <comments-file>
      ( cd "$LEAN_TREE" && env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u GH_BOT \
          GH="$RE_GH" LEAN_SPAWN_BIN="$RE_SESSION" \
          SECOND_SHIFT_CONFIG="$RE_CFG" LEAN_PROGRESS_FILE="$1" RE_COMMENTS_LIVE="$2" \
          RE_DIR="$RE_DIR" RE_WT="$RE_WT" RE_GATE="$LEAN_GATE" RE_KEY="$RE_KEY" \
          RE_RUN="$RE_RUN" RE_PR_NUM="$RE_PR_NUM" RE_LEDGER_DIR="$RE_LEDGER_DIR" \
          RE_BRANCH="$RE_BRANCH" \
          RE_LABELS="$RE_LABELS" RE_BODY="$RE_BODY" RE_STATE="$RE_STATE" \
          RE_PR="$RE_PR" RE_PR_ALL="$RE_PR_ALL" \
          RE_PR_NUMS="$RE_PR_NUMS" RE_GH_LOG="$RE_GH_LOG" \
          bash "$RE_ORCH" "$RE_KEY" --build-model sonnet 2>&1 )
    }

    re_out="$(re_run "$RE_PROG" "$RE_COMMENTS")"; re_rc=$?
    re_m5="$(re_count "$RE_PROG" '| milestone-5 | satisfied')"
    [[ "$re_wt" -eq 0 && "$re_rc" -eq 0 && "$re_m5" -eq 1 ]] \
      && grep -q 'done — #' <<<"$re_out" \
      && pass "(lean-reentry) the real scheduler admits a claimed+markered ticket and drives the lane through the real gate to its terminal write — one NEW milestone-5 satisfaction, exit 0, done" \
      || fail "(lean-reentry) worktree=$re_wt rc=$re_rc milestone-5-rows=$re_m5, expected 0/0/1: $re_out"

    # OR-2. The admission leaves no artifact, so the scheduler's own line IS the evidence — and
    # it must NAME the re-entry rather than fold it into the queue-label wording, carrying the id
    # off the marker it read. Without this the case above would also pass for a scheduler that
    # accepted every claimed ticket unconditionally.
    grep 'ok intake: re-entry' <<<"$re_out" | grep -q "run '$RE_RUN'" \
      && pass "(lean-reentry) the admission is named as re-entry and carries the run id off the marker — the only evidence the read-only arm produces" \
      || fail "(lean-reentry) the accept was not named as re-entry with run '$RE_RUN': $re_out"

    # ...and the record was written by the REAL gate, not by the session fake. Three shapes only
    # the gate emits: `entry`'s attestation row, one satisfied line per milestone (append_satisfied
    # is idempotent, so the close-out's `all` + `5` still leave exactly one), and the BUILD SESSION
    # SET spanning both spawns.
    #
    # The set is header ∪ rows (#446), and the asymmetry is the assertion rather than a quirk of
    # it: the FIRST build session is the one ensure_progress_file stamps into the header, so it
    # gets no row, while the close-out — a fresh session on a file that already exists — is
    # admitted by its own `entry` as a `| session |` row. Without that row milestone 5's `mark`
    # would refuse to stamp the close-out at all, so a leg asserting only the header would pass
    # over the exact case a re-entered run is.
    re_sat=0
    for m in 1 2 3 4 5; do
      [[ "$(re_count "$RE_PROG" "| milestone-$m | satisfied")" -eq 1 ]] && re_sat=$((re_sat + 1))
    done
    [[ "$re_sat" -eq 5 \
       && "$(re_count "$RE_PROG" '| entry | ledger=')" -ge 1 \
       && "$(re_count "$RE_PROG" 'session_id: sess-lean-re-build')" -eq 1 \
       && "$(re_count "$RE_PROG" '| session | sess-lean-re-close')" -eq 1 ]] \
      && pass "(lean-reentry) the composed chain's record is the GATE's: an entry attestation, one satisfied line per milestone, and a build-session set spanning the header's first session and the close-out spawn's own row" \
      || fail "(lean-reentry) satisfied=$re_sat entry-rows=$(re_count "$RE_PROG" '| entry | ledger=') header-session=$(re_count "$RE_PROG" 'session_id: sess-lean-re-build') close-session-row=$(re_count "$RE_PROG" '| session | sess-lean-re-close'), expected 5/>=1/1/1"

    # ---- non-vacuity for the scheduler leg -------------------------------------------------
    # The leg above would stay green if preflight admitted every claimed ticket. Vary the
    # FIXTURE — not production, the same discipline (lean-nv) and (lcs2) already take — so the
    # trail carries nothing bot-authored, and the identical run must reject at exit 2, spawn
    # nothing, and leave ZERO milestone-5 satisfactions in its own record.
    rm -f "$RE_DIR/spawns"
    re_nv_out="$(re_run "$RE_PROG_NV" "$RE_COMMENTS_NV")"; re_nv_rc=$?
    re_nv_spawns="$(cat "$RE_DIR/spawns" 2>/dev/null || echo 0)"
    [[ "$re_nv_rc" -eq 2 && "$re_nv_spawns" -eq 0 \
       && "$(re_count "$RE_PROG_NV" '| milestone-5 | satisfied')" -eq 0 ]] \
      && grep -q "no bot-authored 'lean-claimed' marker" <<<"$re_nv_out" \
      && pass "(lean-reentry-nv) non-vacuity: the same composition on a trail with no bot-authored marker rejects at exit 2, spawns nothing, and reaches no terminal write" \
      || fail "(lean-reentry-nv) rc=$re_nv_rc spawns=$re_nv_spawns milestone-5-rows=$(re_count "$RE_PROG_NV" '| milestone-5 | satisfied'), expected 2/0/0: $re_nv_out"

    git -C "$LEAN_TREE" worktree remove --force "$RE_WT" >/dev/null 2>&1

    # ---- leg 9: an INFRASTRUCTURE KILL composed through to a terminal write (#527) --------
    # Same CLAUDE.md obligation as leg 8, on the verdict path #527 adds: a BUILD session whose
    # milestone-3 evaluation is killed satisfies no milestone and fails none, so its progress
    # token is byte-identical to an idle spawn's — and the scheduler stopped there with both
    # continuations unspent, on runs whose implementation was complete the whole time.
    #
    # WHY IT HAS TO BE COMPOSED. Both halves are covered against themselves already:
    # lean-gate-selftest.sh (ir*) drives the residue read against hand-placed pid records, and
    # orchestrate-lean-selftest.sh (oi*) drives the routing against a FAKE gate whose infra
    # answers a case scripts. Neither can fail if the gate's writer and the scheduler's reader
    # disagree about what residue a killed evaluation leaves — which is the whole contract.
    # Here the kill is real (`kill -9` on the gate's process group, (if5)'s mechanic), the
    # residue is whatever the real gate left, and the run must reach `| milestone-5 | satisfied`.
    IK_KEY=56
    IK_BRANCH="claude/acme-$IK_KEY"
    IK_RUN="r-lean-infrakill"
    IK_PR_NUM=22
    IK_DIR="$TMP/lean-infrakill"
    IK_WT="$TMP/lean-infrakill-wt"
    mkdir -p "$IK_DIR"

    # Two configs, and the split is what makes the kill reachable: the lane the FIRST spawn runs
    # must block long enough to be killed mid-sweep, while every other gate call in the run — the
    # scheduler's, and the later spawns' — takes the ordinary zero-lane one. The session fake
    # selects per call; nothing about the scheduler's own environment changes.
    IK_CFG="$IK_DIR/config.json"
    cp "$RE_CFG" "$IK_CFG"
    IK_CFG_BLOCK="$IK_DIR/config-block.json"
    jq '.commands.acme.test = "sleep 20"' "$IK_CFG" > "$IK_CFG_BLOCK"

    IK_LABELS="$IK_DIR/labels";     printf 'in-progress\n' > "$IK_LABELS"
    IK_BODY="$IK_DIR/issue-body";   printf '# issue\n\nNo Open Regions section here.\n' > "$IK_BODY"
    IK_STATE="$IK_DIR/issue-state"; printf 'OPEN\n' > "$IK_STATE"
    IK_PR="$IK_DIR/pr.json"
    cat > "$IK_PR" <<IKPR
[{ "number": $IK_PR_NUM, "url": "https://example.invalid/pr/$IK_PR_NUM", "isDraft": false,
   "body": "Closes #$IK_KEY\n\nSpec: docs/plans/acme-$IK_KEY-lean.md" }]
IKPR
    IK_PR_ALL="$IK_DIR/pr-all.json"
    printf '[{ "number": %s, "state": "OPEN" }]\n' "$IK_PR_NUM" > "$IK_PR_ALL"
    # EMPTY at the start, and that is the fixture's whole job: `resolve_pr` reads this file on
    # every iteration, so a lane with no PR yet is expressed by its contents rather than by a
    # spawn counter the scheduler would have to be told about. The second BUILD spawn writes it.
    IK_PR_NUMS="$IK_DIR/pr-numbers"; : > "$IK_PR_NUMS"

    IK_COMMENTS="$IK_DIR/comments.json"
    cat > "$IK_COMMENTS" <<IKC
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- dev-pipeline -->\n<!-- run_id: $IK_RUN -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-$IK_KEY-lean-verdict.md" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: $IK_RUN -->\n<!-- session_id: sess-lean-ik-build -->\n<!-- stage: lean-pr-marker -->" }]
IKC

    # The session fake. Spawn 1 KILLS its own milestone-3 evaluation and exits 0 having produced
    # no PR — `claude -p`'s exact shape, since a turn that ends takes its detached children with
    # it. Spawn 2 is the continuation and completes the build. Nothing writes a progress row by
    # hand: every row in the record below came out of the real gate.
    IK_SESSION="$IK_DIR/session"
    cat > "$IK_SESSION" <<'IKSESS'
#!/usr/bin/env bash
n=$(( $(cat "$IK_DIR/spawns" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$IK_DIR/spawns"
echo "spawn $n: $*" >> "$IK_DIR/session.log"
g() { ( unset LEAN_GATE_ANY_TREE; cd "$IK_WT" && SECOND_SHIFT_CONFIG="$IK_CFG" bash "$IK_GATE" "$@" ) >> "$IK_DIR/session.log" 2>&1; }
case "$*" in
  *review-lean*)
    export CLAUDE_CODE_SESSION_ID=sess-lean-ik-review RUN_ID=r-lean-ik-review
    g verdict "$IK_KEY" --pr "$IK_PR_NUM" --verdict approve || exit 1
    git -C "$IK_WT" add -A >/dev/null 2>&1
    git -C "$IK_WT" commit -q -m "review session commits its verdict record" >/dev/null 2>&1 || exit 1
    git -C "$IK_WT" push -q origin "HEAD:refs/heads/$IK_BRANCH" >/dev/null 2>&1 || exit 1
    ;;
  *build-lean*)
    export CLAUDE_CODE_SESSION_ID=sess-lean-ik-build RUN_ID="$IK_RUN"
    printf '{"tool":"Bash"}\n' > "$IK_LEDGER_DIR/sess-lean-ik-build.jsonl"
    if [ "$n" -eq 1 ] && [ "${IK_MODE:-kill}" = "idle" ]; then
      # THE NON-VACUITY SPAWN. `entry` and nothing else: its rows are deliberately outside
      # progress_token's set, and it starts no milestone-3 evaluation, so BOTH predicates are
      # unmoved across this spawn and the scheduler must stop.
      g entry "$IK_KEY" || exit 1
    elif [ "$n" -eq 1 ]; then
      g entry "$IK_KEY" || exit 1
      printf '# spec\n\n- AC-1: the composed infrastructure kill\n' > "$IK_WT/docs/plans/acme-$IK_KEY-lean.md"
      git -C "$IK_WT" add -A >/dev/null 2>&1
      git -C "$IK_WT" commit -q -m "build session pushes the spec" >/dev/null 2>&1 || exit 1
      # PUSHED BEFORE THE KILL, which is what makes the continuation reachable: the second spawn
      # yields a PR, and the scheduler's in-flight check reads a head this one already published.
      git -C "$IK_WT" push -q origin "HEAD:refs/heads/$IK_BRANCH" >/dev/null 2>&1 || exit 1
      # NO milestone 1 or 2 HERE, and that omission is the case. A satisfied milestone moves the
      # continuation predicate, and this spawn must move NOTHING that predicate can see — or the
      # run continues down the pre-#527 "advanced but left no open PR" path and the infra route
      # is never taken. Writing and committing the spec is not a gate call, so the record stays
      # untouched until the kill leaves its residue. Spawn 2 satisfies 1 and 2.
      # THE KILL. Its own process group (`set -m`) so the negative pid reaches the detached
      # runner too — killing the waiter alone would leave the sweep running and the residue this
      # leg is about would never form. The lane self-terminates on a short bound, so a kill that
      # somehow misses cannot wedge the suite.
      set -m
      ( unset LEAN_GATE_ANY_TREE; cd "$IK_WT" && SECOND_SHIFT_CONFIG="$IK_CFG_BLOCK" bash "$IK_GATE" 3 "$IK_KEY" \
          >> "$IK_DIR/session.log" 2>&1 ) &
      kpg=$!
      set +m
      waited=0
      while ! grep -qF "| milestone-3 | started |" "$LEAN_PROGRESS_FILE" 2>/dev/null \
            && [ "$waited" -lt 200 ]; do sleep 0.1; waited=$((waited + 1)); done
      kill -9 -"$kpg" 2>/dev/null
      wait "$kpg" 2>/dev/null
      reaped=0
      while kill -0 -"$kpg" 2>/dev/null && [ "$reaped" -lt 50 ]; do sleep 0.1; reaped=$((reaped + 1)); done
    elif [ "$n" -eq 2 ]; then
      g entry "$IK_KEY" || exit 1
      g 1 "$IK_KEY" || exit 1
      g 2 "$IK_KEY" || exit 1
      g 3 "$IK_KEY" || exit 1
      printf '%s\n' "$IK_PR_NUM" > "$IK_PR_NUMS"
    else
      export CLAUDE_CODE_SESSION_ID=sess-lean-ik-close
      printf '{"tool":"Bash"}\n' > "$IK_LEDGER_DIR/sess-lean-ik-close.jsonl"
      g entry "$IK_KEY" || exit 1
      g all "$IK_KEY" || exit 1
      g 5 "$IK_KEY" || exit 1
    fi
    ;;
  *) exit 1 ;;
esac
exit 0
IKSESS
    chmod +x "$IK_SESSION"

    IK_PROG="$IK_DIR/progress.md"
    IK_PROG_NV="$IK_DIR/progress-nv.md"
    IK_GH_LOG="$IK_DIR/gh.log"
    ik_run() { # ik_run <progress-file> <kill|idle>
      rm -f "$IK_DIR/spawns" "$IK_DIR/session.log" "$IK_GH_LOG" "$IK_PR_NUMS" \
            "$LEAN_TREE/.claude/pipeline-state/$IK_KEY-run-id" \
            "$LEAN_TREE/.claude/pipeline-state/$IK_KEY-review-run-id"
      : > "$IK_PR_NUMS"
      git -C "$LEAN_TREE" worktree remove --force "$IK_WT" >/dev/null 2>&1
      git -C "$LEAN_TREE" branch -D "$IK_BRANCH" >/dev/null 2>&1
      # #531: and the PUBLISHED head with it. The branch is recreated at the base every run, so a
      # surviving origin ref from the previous run would make this one's worktree read as BEHIND
      # origin — clean, but for the wrong reason, which is a fixture asserting nothing.
      git -C "$RE_ORIGIN" update-ref -d "refs/heads/$IK_BRANCH" >/dev/null 2>&1
      git -C "$LEAN_TREE" update-ref -d "refs/remotes/origin/$IK_BRANCH" >/dev/null 2>&1
      git -C "$LEAN_TREE" worktree add -q -b "$IK_BRANCH" "$IK_WT" HEAD >/dev/null 2>&1
      ( cd "$LEAN_TREE" && env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u GH_BOT \
          GH="$RE_GH" LEAN_SPAWN_BIN="$IK_SESSION" \
          SECOND_SHIFT_CONFIG="$IK_CFG" LEAN_PROGRESS_FILE="$1" RE_COMMENTS_LIVE="$IK_COMMENTS" \
          IK_MODE="$2" \
          IK_DIR="$IK_DIR" IK_WT="$IK_WT" IK_GATE="$LEAN_GATE" IK_KEY="$IK_KEY" \
          IK_CFG="$IK_CFG" IK_CFG_BLOCK="$IK_CFG_BLOCK" IK_RUN="$IK_RUN" IK_BRANCH="$IK_BRANCH" \
          IK_PR_NUM="$IK_PR_NUM" IK_PR_NUMS="$IK_PR_NUMS" IK_LEDGER_DIR="$RE_LEDGER_DIR" \
          RE_LABELS="$IK_LABELS" RE_BODY="$IK_BODY" RE_STATE="$IK_STATE" \
          RE_PR="$IK_PR" RE_PR_ALL="$IK_PR_ALL" RE_PR_NUMS="$IK_PR_NUMS" RE_GH_LOG="$IK_GH_LOG" \
          bash "$RE_ORCH" "$IK_KEY" --build-model sonnet 2>&1 )
    }

    ik_out="$(ik_run "$IK_PROG" kill)"; ik_rc=$?
    ik_m5="$(re_count "$IK_PROG" '| milestone-5 | satisfied')"
    ik_unclosed="$(re_count "$IK_PROG" '| milestone-3 | started |')"
    ik_closed="$(re_count "$IK_PROG" '| milestone-3 | concluded |')"
    [[ "$ik_rc" -eq 0 && "$ik_m5" -eq 1 ]] \
      && grep -q 'killed by infrastructure' <<<"$ik_out" \
      && grep -q 'done — #' <<<"$ik_out" \
      && pass "(lean-infrakill) a BUILD session whose milestone-3 evaluation is KILLED continues in a fresh session and the real lane still reaches its terminal write" \
      || fail "(lean-infrakill) rc=$ik_rc milestone-5-rows=$ik_m5, expected 0/1: $ik_out"

    # The residue was REAL, not asserted: the kill left a started row the run never closed, which
    # is exactly the shape the gate's read derives an infrastructure death from. A leg that
    # continued for any other reason would show a matched pair here.
    [[ "$ik_unclosed" -gt "$ik_closed" ]] \
      && pass "(lean-infrakill) the killed evaluation left a genuinely unclosed milestone-3 row — the residue the continuation was routed on" \
      || fail "(lean-infrakill) started=$ik_unclosed concluded=$ik_closed — nothing was actually killed, so the leg proves nothing"

    # ---- non-vacuity ----------------------------------------------------------------------
    # The leg above would stay green if the scheduler continued on every PR-less spawn. Vary the
    # FIXTURE — a first spawn that does nothing but `entry`, whose rows are deliberately outside
    # the progress token AND leave no milestone-3 residue — and the identical composition must
    # stop at exit 1 with nothing to review.
    ik_nv_out="$(ik_run "$IK_PROG_NV" idle)"; ik_nv_rc=$?
    ik_nv_spawns="$(cat "$IK_DIR/spawns" 2>/dev/null || echo 0)"
    [[ "$ik_nv_rc" -eq 1 && "$ik_nv_spawns" -eq 1 \
       && "$(re_count "$IK_PROG_NV" '| milestone-5 | satisfied')" -eq 0 ]] \
      && grep -q 'nothing to review' <<<"$ik_nv_out" \
      && pass "(lean-infrakill-nv) non-vacuity: the same composition with a genuinely idle first spawn stops at exit 1 after ONE spawn and reaches no terminal write" \
      || fail "(lean-infrakill-nv) rc=$ik_nv_rc spawns=$ik_nv_spawns milestone-5-rows=$(re_count "$IK_PROG_NV" '| milestone-5 | satisfied'), expected 1/1/0: $ik_nv_out"

    git -C "$LEAN_TREE" worktree remove --force "$IK_WT" >/dev/null 2>&1

    # ---- leg 10: a PARTIALLY FINISHED CLOSE-OUT, continued to a terminal write (#531) -------
    # THE EPIC'S ACCEPTANCE EVIDENCE. #525's whole premise is that nothing fails when the lane
    # stops completing runs, which is how eight tickets coexisted with a green sweep. This leg is
    # the falsifiable form of "a run completes" for the close-out half: BUILD -> REVIEW -> a
    # close-out that discharges ONE of milestone 5's two obligations -> the continuation -> the
    # terminal `| milestone-5 | satisfied` row.
    #
    # WHY IT HAS TO BE COMPOSED, in the same terms as legs 8 and 9. Both halves are covered against
    # themselves: lean-gate-selftest.sh drives the obligation rows against fixtures, and
    # orchestrate-lean-selftest.sh (w1)/(w2) drive the continuation against a FAKE gate whose
    # tokens a case scripts. Neither can fail if the gate's WRITER and the scheduler's READER
    # disagree about which rows a partially finished close-out leaves — and D-10 is precisely a
    # decision about that: an obligation row spelled with the aggregate's verb would move the
    # scheduler's satisfied token and print `done` over a run with no closing comment on it. Only a
    # composed leg can red on that.
    #
    # THE PARTIAL STATE IS REAL, not simulated: the first close-out runs against a comment trail
    # with no verdict reference, so the real cmd_5 reds on the `verdict-reference` obligation while
    # `exit-artifacts` holds. The fixture then posts the missing comment — which is exactly what a
    # human rescuing this run by hand would do — and the second close-out completes.
    CO_KEY=58
    CO_BRANCH="claude/acme-$CO_KEY"
    CO_RUN="r-lean-closeout"
    CO_PR_NUM=23
    CO_DIR="$TMP/lean-closeout"
    CO_WT="$TMP/lean-closeout-wt"
    mkdir -p "$CO_DIR"

    CO_CFG="$CO_DIR/config.json"; cp "$RE_CFG" "$CO_CFG"
    CO_LABELS="$CO_DIR/labels";     printf 'in-progress\n' > "$CO_LABELS"
    CO_BODY="$CO_DIR/issue-body";   printf '# issue\n\nNo Open Regions section here.\n' > "$CO_BODY"
    CO_STATE="$CO_DIR/issue-state"; printf 'OPEN\n' > "$CO_STATE"
    CO_PR="$CO_DIR/pr.json"
    cat > "$CO_PR" <<COPR
[{ "number": $CO_PR_NUM, "url": "https://example.invalid/pr/$CO_PR_NUM", "isDraft": false,
   "body": "Closes #$CO_KEY\n\nSpec: docs/plans/acme-$CO_KEY-lean.md" }]
COPR
    CO_PR_ALL="$CO_DIR/pr-all.json"
    printf '[{ "number": %s, "state": "OPEN" }]\n' "$CO_PR_NUM" > "$CO_PR_ALL"
    CO_PR_NUMS="$CO_DIR/pr-numbers"; printf '%s\n' "$CO_PR_NUM" > "$CO_PR_NUMS"

    # The claim marker and the PR identity marker, but NO closing comment. That absence is the
    # case: `exit-artifacts` will hold and `verdict-reference` will not.
    CO_COMMENTS_PARTIAL="$CO_DIR/comments-partial.json"
    cat > "$CO_COMMENTS_PARTIAL" <<COC
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- dev-pipeline -->\n<!-- run_id: $CO_RUN -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "<!-- run_id: $CO_RUN -->\n<!-- session_id: sess-lean-co-build -->\n<!-- stage: lean-pr-marker -->" }]
COC
    # ...and the same trail WITH it, which the session fake swaps in between the two close-outs.
    CO_COMMENTS_FULL="$CO_DIR/comments-full.json"
    jq --arg v "docs/plans/acme-$CO_KEY-lean-verdict.md" \
       '. + [{ user: { type: "Bot" }, created_at: "2026-01-03T00:00:00Z",
               body: ("Done. Verdict record: " + $v) }]' \
       "$CO_COMMENTS_PARTIAL" > "$CO_COMMENTS_FULL"

    # ONE live trail file the fake gh reads, so "the operator posted the missing comment" is a
    # copy rather than a second gh stub.
    CO_COMMENTS_LIVE="$CO_DIR/comments-live.json"

    CO_SESSION="$CO_DIR/session"
    cat > "$CO_SESSION" <<'COSESS'
#!/usr/bin/env bash
n=$(( $(cat "$CO_DIR/spawns" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CO_DIR/spawns"
echo "spawn $n: $*" >> "$CO_DIR/session.log"
g() { ( unset LEAN_GATE_ANY_TREE; cd "$CO_WT" && bash "$CO_GATE" "$@" ) >> "$CO_DIR/session.log" 2>&1; }
case "$*" in
  *review-lean*)
    export CLAUDE_CODE_SESSION_ID=sess-lean-co-review RUN_ID=r-lean-co-review
    g verdict "$CO_KEY" --pr "$CO_PR_NUM" --verdict approve || exit 1
    git -C "$CO_WT" add -A >/dev/null 2>&1
    git -C "$CO_WT" commit -q -m "review session commits its verdict record" >/dev/null 2>&1 || exit 1
    git -C "$CO_WT" push -q origin "HEAD:refs/heads/$CO_BRANCH" >/dev/null 2>&1 || exit 1
    ;;
  *build-lean*)
    if [ "$n" -eq 1 ]; then
      export CLAUDE_CODE_SESSION_ID=sess-lean-co-build RUN_ID="$CO_RUN"
      printf '{"tool":"Bash"}\n' > "$CO_LEDGER_DIR/sess-lean-co-build.jsonl"
      g entry "$CO_KEY" || exit 1
      printf '# spec\n\n- AC-1: the composed close-out continuation\n' > "$CO_WT/docs/plans/acme-$CO_KEY-lean.md"
      git -C "$CO_WT" add -A >/dev/null 2>&1
      git -C "$CO_WT" commit -q -m "build session pushes the spec" >/dev/null 2>&1 || exit 1
      git -C "$CO_WT" push -q origin "HEAD:refs/heads/$CO_BRANCH" >/dev/null 2>&1 || exit 1
      g 1 "$CO_KEY" || exit 1
      g 2 "$CO_KEY" || exit 1
      g 3 "$CO_KEY" || exit 1
    else
      # EVERY close-out is a fresh session, so a fresh id — its own `entry` admits it to the build
      # set (#446), without which milestone 5's `mark` would refuse to stamp it. `bash G 5` is
      # allowed to RED here: on the first close-out that red IS the case, and its exit is not
      # checked, exactly as a real close-out's checklist step 9 leaves the failure to the record.
      export CLAUDE_CODE_SESSION_ID="sess-lean-co-close-$n" RUN_ID="$CO_RUN"
      printf '{"tool":"Bash"}\n' > "$CO_LEDGER_DIR/sess-lean-co-close-$n.jsonl"
      g entry "$CO_KEY" || exit 1
      # `all` first, exactly as the checklist mandates before step 9 — and it is what makes
      # milestone 4 satisfied here, without which cmd_5 stops at its progress-file precondition
      # and never reaches an obligation at all. Its exit is deliberately unchecked: on the first
      # close-out its milestone-5 red IS the case.
      g all "$CO_KEY"
      g 5 "$CO_KEY"
      # THE RESCUE, and it is the fixture varying rather than production: the missing closing
      # comment is posted after the first close-out has already recorded it unmet. In CO_MODE=stuck
      # it never appears, which is the paired non-vacuity arm.
      # Keyed on "the first close-out has now happened", NOT on the spawn ordinal: `n` counts
      # every spawn, so a literal would silently name the REVIEW spawn and the rescue would never
      # fire — the shape this leg is meant to catch in production.
      if [ "${CO_MODE:-fixed}" = "fixed" ] && [ ! -f "$CO_DIR/rescued" ]; then
        : > "$CO_DIR/rescued"
        cp "$CO_COMMENTS_FULL" "$CO_COMMENTS_LIVE"
      fi
    fi
    ;;
  *) exit 1 ;;
esac
exit 0
COSESS
    chmod +x "$CO_SESSION"

    CO_PROG="$CO_DIR/progress.md"
    CO_PROG_NV="$CO_DIR/progress-nv.md"
    CO_GH_LOG="$CO_DIR/gh.log"
    co_run() { # co_run <progress-file> <fixed|stuck>
      rm -f "$CO_DIR/spawns" "$CO_DIR/session.log" "$CO_GH_LOG" "$CO_DIR/rescued" \
            "$LEAN_TREE/.claude/pipeline-state/$CO_KEY-run-id" \
            "$LEAN_TREE/.claude/pipeline-state/$CO_KEY-review-run-id"
      cp "$CO_COMMENTS_PARTIAL" "$CO_COMMENTS_LIVE"
      git -C "$LEAN_TREE" worktree remove --force "$CO_WT" >/dev/null 2>&1
      git -C "$LEAN_TREE" branch -D "$CO_BRANCH" >/dev/null 2>&1
      git -C "$RE_ORIGIN" update-ref -d "refs/heads/$CO_BRANCH" >/dev/null 2>&1
      git -C "$LEAN_TREE" update-ref -d "refs/remotes/origin/$CO_BRANCH" >/dev/null 2>&1
      git -C "$LEAN_TREE" worktree add -q -b "$CO_BRANCH" "$CO_WT" HEAD >/dev/null 2>&1
      ( cd "$LEAN_TREE" && env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u GH_BOT \
          GH="$RE_GH" LEAN_SPAWN_BIN="$CO_SESSION" \
          SECOND_SHIFT_CONFIG="$CO_CFG" LEAN_PROGRESS_FILE="$1" RE_COMMENTS_LIVE="$CO_COMMENTS_LIVE" \
          CO_MODE="$2" \
          CO_DIR="$CO_DIR" CO_WT="$CO_WT" CO_GATE="$LEAN_GATE" CO_KEY="$CO_KEY" \
          CO_RUN="$CO_RUN" CO_PR_NUM="$CO_PR_NUM" CO_LEDGER_DIR="$RE_LEDGER_DIR" \
          CO_BRANCH="$CO_BRANCH" CO_COMMENTS_FULL="$CO_COMMENTS_FULL" \
          CO_COMMENTS_LIVE="$CO_COMMENTS_LIVE" \
          RE_LABELS="$CO_LABELS" RE_BODY="$CO_BODY" RE_STATE="$CO_STATE" \
          RE_PR="$CO_PR" RE_PR_ALL="$CO_PR_ALL" RE_PR_NUMS="$CO_PR_NUMS" RE_GH_LOG="$CO_GH_LOG" \
          bash "$RE_ORCH" "$CO_KEY" --build-model sonnet 2>&1 )
    }

    rm -f "$CO_PROG" "$CO_PROG_NV"
    co_out="$(co_run "$CO_PROG" fixed)"; co_rc=$?
    co_spawns="$(cat "$CO_DIR/spawns" 2>/dev/null || echo 0)"
    co_m5="$(re_count "$CO_PROG" '| milestone-5 | satisfied')"
    [[ "$co_rc" -eq 0 && "$co_spawns" -eq 4 && "$co_m5" -eq 1 ]] \
      && grep -q 'continuing in a fresh session (1 of 1)' <<<"$co_out" \
      && grep -q 'done — #' <<<"$co_out" \
      && pass "(lean-closeout) a close-out that discharged only one of milestone 5's obligations is continued once, and the real lane still reaches its terminal write" \
      || fail "(lean-closeout) rc=$co_rc spawns=$co_spawns milestone-5-rows=$co_m5, expected 0/4/1: $co_out"

    # THE PARTIAL STATE WAS REAL, and it is the gate's own record that says so — the composition's
    # whole point. `exit-artifacts` met while `verdict-reference` was still unmet, and the aggregate
    # withheld until both held. A gate that spelled either row with the aggregate's verb would have
    # moved the scheduler's token on the FIRST close-out and printed `done` above.
    [[ "$(re_count "$CO_PROG" '| milestone-5 | obligation | exit-artifacts | met')" -eq 1 \
       && "$(re_count "$CO_PROG" '| milestone-5 | obligation | verdict-reference | unmet')" -eq 1 \
       && "$(re_count "$CO_PROG" '| milestone-5 | obligation | verdict-reference | met')" -eq 1 ]] \
      && pass "(lean-closeout) the record carries one row per obligation with its own state — the partial close-out is legible in the artifact, not only in the log" \
      || fail "(lean-closeout) obligation rows were not written as expected: $(grep 'obligation' "$CO_PROG" 2>/dev/null)"

    # ...and the scheduler's continuation was routed on the GENERAL progress token (D-9), which
    # moved because the failed close-out appended a milestone-5 attempt row. Without that row the
    # run would have taken the advanced-nothing stop instead, and this leg would be measuring the
    # wrong path.
    [[ "$(re_count "$CO_PROG" '| milestone-5 | attempt |')" -ge 1 ]] \
      && pass "(lean-closeout) the continuation was routed on a real advancement — the failed close-out's own attempt row" \
      || fail "(lean-closeout) no milestone-5 attempt row, so the continuation cannot have been routed on advancement: $(cat "$CO_PROG" 2>/dev/null)"

    # ---- non-vacuity ----------------------------------------------------------------------
    # The leg above would stay green against a scheduler that continued forever, or against a gate
    # that satisfied milestone 5 regardless. Vary the FIXTURE — the closing comment is never posted
    # — and the identical composition must spend its one continuation, stop under its own slug, and
    # reach NO terminal write.
    co_nv_out="$(co_run "$CO_PROG_NV" stuck)"; co_nv_rc=$?
    co_nv_spawns="$(cat "$CO_DIR/spawns" 2>/dev/null || echo 0)"
    [[ "$co_nv_rc" -eq 1 && "$co_nv_spawns" -eq 4 \
       && "$(re_count "$CO_PROG_NV" '| milestone-5 | satisfied')" -eq 0 ]] \
      && grep -q 'terminal: closeout-continuations-spent' <<<"$co_nv_out" \
      && grep -q 'obligation verdict-reference: unmet' <<<"$co_nv_out" \
      && pass "(lean-closeout-nv) non-vacuity: an obligation that never becomes met spends the one continuation, stops under its own slug, and names the outstanding obligation from the gate's own report" \
      || fail "(lean-closeout-nv) rc=$co_nv_rc spawns=$co_nv_spawns milestone-5-rows=$(re_count "$CO_PROG_NV" '| milestone-5 | satisfied'), expected 1/4/0: $co_nv_out"

    git -C "$LEAN_TREE" worktree remove --force "$CO_WT" >/dev/null 2>&1
  fi

  # ============ #566: milestone 3 is INLINE, and its residue is what the scheduler reads ====
  # WHAT THIS REPLACED. A #539 scenario stood here and asserted the opposite property: that
  # milestone 3's DETACHED runner outlived its launcher's whole process group being killed, and
  # that a second call JOINED it rather than starting a second sweep. #566 deleted that stratum —
  # the runner, the marker, the rejoin, the lane registry — because the evaluation is now bounded
  # to fit inside the turn instead of engineered to survive leaving it.
  #
  # WHAT NO FIXTURE CASE CAN FAIL ON, and why this is still a scenario. lean-gate-selftest.sh's
  # (x3d) asserts the gate does not ANNOUNCE a detached evaluation, and (if5)/(if5b) assert a
  # killed one leaves `started` with no `concluded`. Neither composes the piece the scheduler
  # actually acts on: that the residue a killed milestone 3 leaves is what `progress --infra`
  # reports, in the token space orchestrate-lean.sh compares across a spawn. Three components,
  # one property, and the seam between them is where #527's original defect lived.
  #
  # THE KILL IS (if5)'s IDIOM VERBATIM: `set -m` so the backgrounded gate leads its own group,
  # wait for the milestone-3 `started` row so the evaluation demonstrably began, then `kill -9`
  # the negative pid.
  TE_KEY=57
  TE_DIR="$TMP/lean-inline-m3"
  TE_TREE="$TE_DIR/tree"
  TE_SID="sess-lean-inline-m3"
  mkdir -p "$TE_TREE/docs/plans" "$TE_TREE/.claude/audit"
  git -C "$TE_TREE" init -q
  git -C "$TE_TREE" config user.email te@example.invalid
  git -C "$TE_TREE" config user.name lean-inline
  printf '.claude/\n' > "$TE_TREE/.gitignore"
  printf '# spec\n\n- AC-1: the thing\n' > "$TE_TREE/docs/plans/acme-$TE_KEY-lean.md"
  git -C "$TE_TREE" add -A >/dev/null 2>&1
  git -C "$TE_TREE" commit -q -m base >/dev/null 2>&1
  git -C "$TE_TREE" update-ref refs/remotes/origin/main HEAD
  printf '{"tool":"Bash"}\n' > "$TE_TREE/.claude/audit/$TE_SID.jsonl"
  TE_PROG="$TE_DIR/progress.md"

  te_gate() { # te_gate <config> <args...> — stderr MERGED, for reading the gate's report
    local cfg="$1"; shift
    ( cd "$TE_TREE" && env -u RUN_ID -u GH_BOT CLAUDE_CODE_SESSION_ID="$TE_SID" \
        SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$TE_PROG" \
        bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 )
  }
  # THE TOKEN VARIANT, stderr DROPPED. `progress --infra` prints an opaque token on stdout and its
  # diagnostic on stderr precisely so a caller can compare the token as an exact string; merging
  # them makes every comparison a two-line one that can never match. Same split as
  # lean-gate-selftest.sh's gate_ir / gate_ir_e, and for the same reason.
  te_token() { # te_token <config> <args...>
    local cfg="$1"; shift
    ( cd "$TE_TREE" && env -u RUN_ID -u GH_BOT CLAUDE_CODE_SESSION_ID="$TE_SID" \
        SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$TE_PROG" \
        bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>/dev/null )
  }

  # ---- the happy path: an inline evaluation concludes, and the read says "no death" ---------
  TE_CFG_OK="$TE_DIR/config-ok.json"
  jq '.commands.acme.test = "true"' "$LEAN_CFG" > "$TE_CFG_OK"
  rm -f "$TE_PROG"
  te_gate "$TE_CFG_OK" entry "$TE_KEY" >/dev/null 2>&1
  te_ok_out="$(te_gate "$TE_CFG_OK" 3 "$TE_KEY")"; te_ok_rc=$?
  te_ok_tok="$(te_token "$TE_CFG_OK" progress "$TE_KEY" --infra)"
  # The started/concluded PAIR is the half a join used to break deliberately (#511 D-9: "a join
  # writes nothing"). With no join arm left, every evaluation that begins must also close.
  if [[ "$te_ok_rc" -eq 0 && "$te_ok_tok" == "m3infra-v3:0" ]] \
     && ! grep -q 'spawned detached' <<<"$te_ok_out" \
     && [[ "$(re_count "$TE_PROG" '| milestone-3 | started |')" -eq 1 \
        && "$(re_count "$TE_PROG" '| milestone-3 | concluded |')" -eq 1 ]]; then
    pass "(lean-inline-m3) #566 AC-1/AC-9: milestone 3 runs inline, closes its started/concluded pair, and the scheduler reads m3infra-v3:0"
  else
    fail "(lean-inline-m3) rc=$te_ok_rc token='$te_ok_tok' started=$(re_count "$TE_PROG" '| milestone-3 | started |') concluded=$(re_count "$TE_PROG" '| milestone-3 | concluded |'): $te_ok_out"
  fi

  # ---- non-vacuity: kill it mid-lane, and the SAME read must move -------------------------
  # Without this leg the one above would stay green against a gate that answered `:0`
  # unconditionally — which is exactly the shape #527 was filed about, a killed session
  # indistinguishable from an idle one.
  TE_CFG_BLOCK="$TE_DIR/config-block.json"
  jq '.commands.acme.test = "sleep 20"' "$LEAN_CFG" > "$TE_CFG_BLOCK"
  rm -f "$TE_PROG"
  te_gate "$TE_CFG_BLOCK" entry "$TE_KEY" >/dev/null 2>&1
  set -m
  ( cd "$TE_TREE" && env -u RUN_ID -u GH_BOT CLAUDE_CODE_SESSION_ID="$TE_SID" \
      SECOND_SHIFT_CONFIG="$TE_CFG_BLOCK" LEAN_PROGRESS_FILE="$TE_PROG" \
      bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" 3 "$TE_KEY" ) >/dev/null 2>&1 &
  te_kpg=$!
  set +m
  te_waited=0
  while ! grep -qF "| milestone-3 | started |" "$TE_PROG" 2>/dev/null && [ "$te_waited" -lt 300 ]; do
    sleep 0.1; te_waited=$((te_waited + 1))
  done
  kill -9 -"$te_kpg" 2>/dev/null
  wait "$te_kpg" 2>/dev/null
  te_waited=0
  while kill -0 -"$te_kpg" 2>/dev/null && [ "$te_waited" -lt 50 ]; do sleep 0.1; te_waited=$((te_waited + 1)); done
  # NOTHING SURVIVES THE GROUP KILL — the property AC-1 bought by deleting the escape. If a
  # detached runner ever comes back, `sleep 20` is still running here and this check fails.
  if kill -0 -"$te_kpg" 2>/dev/null; then
    fail "(lean-inline-m3-nv) a lane child outlived the gate's process group — milestone 3 detached"
  else
    te_nv_tok="$(te_token "$TE_CFG_BLOCK" progress "$TE_KEY" --infra)"
    if [[ "$te_nv_tok" == "m3infra-v3:1" \
       && "$(re_count "$TE_PROG" '| milestone-3 | started |')" -eq 1 \
       && "$(re_count "$TE_PROG" '| milestone-3 | concluded |')" -eq 0 ]]; then
      pass "(lean-inline-m3-nv) non-vacuity: a killed inline evaluation leaves started-with-no-concluded, and the same read moves to m3infra-v3:1"
    else
      fail "(lean-inline-m3-nv) expected m3infra-v3:1 with 1 started / 0 concluded, got token='$te_nv_tok' started=$(re_count "$TE_PROG" '| milestone-3 | started |') concluded=$(re_count "$TE_PROG" '| milestone-3 | concluded |')"
    fi
  fi

fi

# ══════════════════════════════════════════════════════════════════════════════
# LANE ROUTING (#413) — exactly one merge-boundary gate claims any given PR
# ══════════════════════════════════════════════════════════════════════════════
# WHY THIS IS A SCENARIO AND NOT TWO FIXTURE CASES. Both lanes now cut branches under
# `<tracker.branchPrefix><key>`, so the branch name no longer separates them; what does is that
# BOTH gates ask lean-evidence.sh's classify() which lane owns a PR. That is a property of the
# PAIR. Each gate's own suite drives it in isolation and cannot see the two failure modes that
# matter — a PR claimed by BOTH (double-gated, and the lean one then reds on a stage trail its
# lane never emits) and a PR claimed by NEITHER (the vacuous green the whole boundary exists to
# prevent). Composing them over ONE tree and ONE branch shape is the only way to assert
# "exactly one".
echo
echo "── lane routing (both merge-boundary gates over one PR)"

LR_ROOT="$HERE/../../../.."
LR_LEAN="$LR_ROOT/scripts/check-lean-chain.sh"
LR_PIPE="$LR_ROOT/scripts/check-pipeline-chain.sh"
LR_EV="$HERE/lean-evidence.sh"
# BOTH chain gates live in the marketplace repo's `scripts/`, and both are second-shift-only by
# construction — their own headers say not to ship them to a consumer. So when this suite runs
# from a STAGED INSTALL CACHE (tools/install-topology-selftest.sh re-runs every shipped suite
# there), they are correctly absent and these legs have nothing to compose. Skipping is right
# there and WRONG here, so the two cases are told apart by the marketplace manifest, which only
# the repo root carries: absent gates inside the repo stay a hard failure.
if [[ ! -f "$LR_LEAN" || ! -f "$LR_PIPE" || ! -f "$LR_EV" ]] \
   && [[ ! -f "$LR_ROOT/.claude-plugin/marketplace.json" ]]; then
  echo "  skip: lane routing — the chain gates are marketplace-repo-only and this tree is an installed plugin cache"
elif [[ ! -f "$LR_LEAN" || ! -f "$LR_PIPE" || ! -f "$LR_EV" ]]; then
  # In the repo, absence is a FAILURE, not a skip — the same posture the lean legs above take.
  fail "(lr) a chain gate or the classifier is missing — lane routing did not run (lean=$LR_LEAN pipe=$LR_PIPE ev=$LR_EV)"
else
  LR_TREE="$TMP/lr-tree"
  mkdir -p "$LR_TREE/docs/plans"
  git -C "$LR_TREE" init -q .
  git -C "$LR_TREE" config user.email lr@example.invalid
  git -C "$LR_TREE" config user.name lr-scenario
  git -C "$LR_TREE" config commit.gpgsign false
  echo "staged plan" > "$LR_TREE/docs/plans/acme-77.md"
  printf '# lean spec\n\n- AC-1: does a thing\n' > "$LR_TREE/docs/plans/acme-77-lean.md"
  git -C "$LR_TREE" add -A >/dev/null 2>&1
  git -C "$LR_TREE" commit -qm "fixture: both lanes' artifacts for #77" >/dev/null 2>&1

  LR_PREFIX="claude/acme-"
  LR_OPEN="2026-07-30T12:00:00Z"
  LR_BODY="Closes #77"
  LR_SHA="$(git -C "$LR_TREE" rev-parse HEAD)"

  # Both gates get an EMPTY comment trail on purpose: whichever one claims the PR reds on it,
  # so "claimed" cannot be confused with "passed everything".
  LR_EMPTY="$TMP/lr-empty.json"
  echo '[]' > "$LR_EMPTY"

  # Applicability is read off each gate's own decline line, never inferred from rc — a gate
  # that ran and failed and a gate that declined need distinguishing, and only one prints a
  # decline.
  lr_lean() { # lr_lean <diff-file> -> applicable|declined
    local out
    out="$( cd "$LR_TREE" && PIPELINE_BRANCH_PREFIX="$LR_PREFIX" \
      PR_HEAD_REF="${LR_PREFIX}77" PR_HEAD_SHA="$LR_SHA" \
      PR_BASE_REF=main PR_BODY="$LR_BODY" PR_CREATED_AT="$LR_OPEN" \
      LEAN_EVIDENCE="$LR_EV" bash "$LR_LEAN" --comments-file "$LR_EMPTY" \
      --diff-files-file "$1" 2>&1 )"
    # Since #443 the lean gate's decline is its class-(b) line — the only thing it writes on a
    # green run — so the token is `lean-chain: not-applicable`, not the retired prose sentence.
    if grep -q 'lean-chain: not-applicable' <<<"$out"; then echo declined; else echo applicable; fi
  }
  lr_pipe() { # lr_pipe <diff-file> -> applicable|declined
    local out
    out="$( cd "$LR_TREE" && PIPELINE_BRANCH_PREFIX="$LR_PREFIX" \
      PIPELINE_PLAN_PATTERN="docs/plans/acme-{issueKey}.md" \
      PR_HEAD_REF="${LR_PREFIX}77" PR_HEAD_SHA="$LR_SHA" \
      PR_BASE_REF=main PR_BODY="$LR_BODY" PR_CREATED_AT="$LR_OPEN" \
      LEAN_EVIDENCE="$LR_EV" bash "$LR_PIPE" --comments-file "$LR_EMPTY" \
      --diff-files-file "$1" 2>&1 )"
    if grep -q 'chain check not applicable' <<<"$out"; then echo declined; else echo applicable; fi
  }
  # The same composition, output verbatim, for the cutoff leg below — which reads WHICH lines the
  # boundary wrote rather than only whether it claimed the PR.
  lr_lean_out() { # lr_lean_out <diff-file> <pr-created-at>
    ( cd "$LR_TREE" && PIPELINE_BRANCH_PREFIX="$LR_PREFIX" \
      PR_HEAD_REF="${LR_PREFIX}77" PR_HEAD_SHA="$LR_SHA" \
      PR_BASE_REF=main PR_BODY="$LR_BODY" PR_CREATED_AT="$2" \
      LEAN_EVIDENCE="$LR_EV" bash "$LR_LEAN" --comments-file "${3:-$LR_EMPTY}" \
      --diff-files-file "$1" 2>&1 )
  }

  # #445. The claim trail this boundary already holds is also the carrier of the producer's
  # CAPABILITY STAMP, which decides whether a capability-bound arm evaluates at all. Two trails,
  # identical but for the stamp, so the legs below state which producer generation built the PR
  # instead of inheriting an empty trail's answer. Both are claimed before the cutoff instants
  # the legs use, so the boundary's own PR-open window is satisfied either way.
  LR_CLAIM_STAMPED="$TMP/lr-claim-stamped.json"
  cat > "$LR_CLAIM_STAMPED" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "created_at": "2026-08-08T00:00:00Z",
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-lr-build -->\n<!-- session_id: sess-lr-build -->\n<!-- capabilities: pr-marker -->\n<!-- stage: lean-claimed -->" }]
EOF
  LR_CLAIM_PRETOKEN="$TMP/lr-claim-pretoken.json"
  cat > "$LR_CLAIM_PRETOKEN" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "created_at": "2026-08-08T00:00:00Z",
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-lr-build -->\n<!-- session_id: sess-lr-build -->\n<!-- stage: lean-claimed -->" }]
EOF

  # (lr1) A LEAN PR: the same namespace a staged one uses, distinguished only by its spec.
  LR_DIFF_LEAN="$TMP/lr-diff-lean.txt"
  printf 'src/thing.ts\ndocs/plans/acme-77-lean.md\n' > "$LR_DIFF_LEAN"
  lr_a="$(lr_lean "$LR_DIFF_LEAN")"; lr_b="$(lr_pipe "$LR_DIFF_LEAN")"
  [[ "$lr_a" == "applicable" && "$lr_b" == "declined" ]] \
    && pass "(lr1) a lean PR on the shared namespace routes to the LEAN gate only" \
    || fail "(lr1) lean PR routing — lean=$lr_a pipeline=$lr_b"

  # (lr2) A STAGED PR on the SAME branch shape. The only thing that moved is the diff, which is
  # the entire claim: the discriminator is the artifact, not the name.
  LR_DIFF_STAGED="$TMP/lr-diff-staged.txt"
  printf 'src/thing.ts\ndocs/plans/acme-77.md\n' > "$LR_DIFF_STAGED"
  lr_a="$(lr_lean "$LR_DIFF_STAGED")"; lr_b="$(lr_pipe "$LR_DIFF_STAGED")"
  [[ "$lr_a" == "declined" && "$lr_b" == "applicable" ]] \
    && pass "(lr2) a staged PR on the SAME branch shape routes to the PIPELINE gate only" \
    || fail "(lr2) staged PR routing — lean=$lr_a pipeline=$lr_b"

  # (lr3) The cross-key case, where a suffix-only artifact test would lose BOTH gates: a staged
  # PR that merely edits some other ticket's lean spec must stay with the pipeline gate.
  LR_DIFF_OTHER="$TMP/lr-diff-other.txt"
  printf 'src/thing.ts\ndocs/plans/acme-99-lean.md\n' > "$LR_DIFF_OTHER"
  lr_a="$(lr_lean "$LR_DIFF_OTHER")"; lr_b="$(lr_pipe "$LR_DIFF_OTHER")"
  [[ "$lr_a" == "declined" && "$lr_b" == "applicable" ]] \
    && pass "(lr3) a PR carrying ANOTHER ticket's lean spec is not orphaned — the pipeline gate keeps it" \
    || fail "(lr3) cross-key routing — lean=$lr_a pipeline=$lr_b"

  # (lr4) #444: the PAYLOAD's arm cutoff, composed through the delegating boundary. The other
  # new verdict path this ticket adds — its sibling, the entry precondition's de-block, composes
  # in the (lean-entry-since) leg above. Only a composed run shows the exemption SURVIVING
  # delegation: check-lean-chain.sh shells out to the payload and folds back a violation COUNT,
  # so a class-(b) decline that the boundary miscounted as a violation, or a cutoff the delegated
  # environment never reached, is invisible to the payload's own suite.
  #
  # PAIRED ACROSS THE CUTOFF on one unchanged tree, which is what makes it a comparator test
  # rather than a "does it ever print this" test: only the instant moves between the two calls.
  #
  # BOTH CALLS RUN ON THE STAMPED CLAIM TRAIL (#445). A capability-bound arm on an unstamped
  # trail declines for a SECOND reason, so an empty trail would leave the after-side's "not
  # postdated" satisfied by a different decline and the leg would prove nothing about the cutoff.
  # The after-side asserts the arm cleared BOTH exemptions — no `postdated`, no `inert` — which is
  # the strongest statement available on this tree: it carries no verdict record, so the arm
  # short-circuits before its refusal (that refusal is (Y1)'s subject, in the boundary's own
  # suite).
  lr4_before="$(lr_lean_out "$LR_DIFF_LEAN" '2026-08-08T17:05:13Z' "$LR_CLAIM_STAMPED")"
  lr4_after="$(lr_lean_out "$LR_DIFF_LEAN" '2026-08-08T17:05:14Z' "$LR_CLAIM_STAMPED")"
  grep -q 'identity: postdated' <<<"$lr4_before" \
    && ! grep -qE 'identity: (postdated|inert)' <<<"$lr4_after" \
    && pass "(lr4) the payload's arm cutoff survives delegation: the boundary exempts a PR opened one second before it and stops exempting one second after" \
    || fail "(lr4) delegated cutoff — before=[$lr4_before] after=[$lr4_after]"

  # (lr5) #445: the CAPABILITY binding, composed the same way and over the same instant. Only the
  # claim trail moves between the two calls — one stamped, one from the generation that predates
  # the stamp — so the boundary's answer can only have come from the stamp. PAIRED, because
  # either side alone is satisfied by an arm that always declines or one that never does.
  lr5_pre="$(lr_lean_out "$LR_DIFF_LEAN" '2026-08-08T17:05:14Z' "$LR_CLAIM_PRETOKEN")"
  grep -q 'identity: inert' <<<"$lr5_pre" \
    && ! grep -q 'identity: inert' <<<"$lr4_after" \
    && pass "(lr5) the payload's capability binding survives delegation: a pre-token producer's PR declines where a stamped one does not" \
    || fail "(lr5) delegated capability binding — pretoken=[$lr5_pre] stamped=[$lr4_after]"
fi

echo
echo "[scenario-liveness] summary: $PASS passed, $FAIL failed"
exit $FAIL
