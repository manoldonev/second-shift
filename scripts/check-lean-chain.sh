#!/usr/bin/env bash
# check-lean-chain.sh — merge-boundary evidence gate for /dev-pipeline:run-lean PRs.
#
# A SIBLING of check-pipeline-chain.sh, deliberately not a mode of it (D-45): editing that
# script would re-key its four mutation-baseline survivor rows for zero benefit, and the two
# gates check different evidence sets over disjoint branch namespaces.
#
# WHY THIS EXISTS. run-lean spends as few tokens as possible IN the run, which means almost
# every in-run record is written by the agent being checked. That is fine — as long as the
# binding evidence contract lives somewhere the agent cannot reach. This is that somewhere:
# a model-free check at the merge boundary, costing zero run tokens (D-47). It fails an
# applicable PR unless all of this evidence exists:
#   1. a committed lean spec carrying >= 1 numbered AC-n (the definition of done),
#   2. a committed verdict record reading `verdict=approve` (so a hand-typed local progress
#      line cannot reach a merge — only a committed, diffable artifact can),
#   3. a bot-authored `lean-claimed` comment on the linked issue, windowed at PR-open,
#   4. AUTHORSHIP (P10): the verdict record's run identity is NOT the build run's, and the
#      record names its own review session. The build run's identity AT THIS BOUNDARY is the
#      one carried in that bot claim comment — the only build-side record CI can see, because
#      the progress file is gitignored and never reaches a checkout. A verdict carrying the
#      same id means the session that wrote the code also wrote its own review, which is the
#      structural bias the separation exists to remove. A missing reconciliation key is
#      refused for the same reason a missing verdict is: nothing is checkable, and an
#      uncheckable claim must not read as a satisfied one.
#   5. FRESHNESS: the verdict covers the head being merged. The record is a static file, so
#      "an approve record exists" and "this code was approved" are different claims — a
#      review session commits its record and the branch then moves on, which is the ordinary
#      shape of the needs-work loop. Nothing but the record itself may have changed between
#      the commit carrying it and the PR head. TWO ARMS, because neither subsumes the other:
#      the INFERRED one derives its anchor from git (which commit carries the file — the
#      record's prose cannot argue with that), and the DECLARED one reads what the reviewer
#      wrote. Inference binds the record to where it was COMMITTED; the declaration binds it to
#      what was REVIEWED. They come apart whenever code lands between the review and the
#      record's commit — the reviewer then commits an honest record on top of a head it never
#      read, and inference alone calls that fresh.
#
#      The declaration is keyed on `reviewed_patch_id`: the patch identity of the branch's own
#      diff against its base, excluding the record. WHAT IT COVERS — any commit landing after
#      the review, and any conflict resolution that altered a line during a rebase, both of
#      which move the id. WHAT IT DOES NOT — a rebase that replays the branch unchanged (the id
#      is invariant, and that is the point: SHA keying refused it, and in this fresh checkout
#      the pre-rebase object does not exist at all, so the refusal was unavoidable rather than
#      merely wrong), and a base change that reds the suite with no textual conflict. That last
#      one is CI's job: the reviewed content did not move, so the verdict stands, and the merged
#      result failing is a different claim. Conflating the two is what made SHA keying
#      over-strict. Records predating the key still gate on the `reviewed_head` SHA path.
#   6. RATIFICATION (P9): if the run wrote an intent-gap record — a decision implementation
#      surfaced that the receipt did not cover — that record reads `ratified: yes` and cites
#      the operator comment that ratified it. Absence of a record is the ordinary case and is
#      printed, not silently skipped.
#
# HONEST ALTITUDE: like its sibling, this is tamper-EVIDENCE, not proof. The agent writes
# artifacts 1 and 2. Forging one is easy; forging all three consistently, across a committed
# diff and a bot-authenticated tracker comment, is what this makes detectable. Harness
# attestation is lean-reconcile.sh's job (and #292's later).
#
# NON-VACUOUS BY CONSTRUCTION. Applicability triggers on branch-prefix match OR on a
# lean-marked spec appearing in the PR diff. That second arm is the point: a stale or wrong
# LEAN_BRANCH_PREFIX matches zero branches, and a prefix-only gate would then silently exempt
# every lean PR — the self-neutralization mode the manifesto's T0 note records for the
# pipeline constant. The artifact arm still fires with a zero-matching prefix, and the
# selftest carries that exact case.
#
# The artifact arm is ANDed with "the branch is not pipeline-prefixed", so a pipeline PR that
# merely carries lean-shaped files — the delivering PR for this very feature does — is never
# double-classified. Selftest-fixture paths are excluded from the artifact scan for the same
# reason: fixtures are lean-shaped on purpose.
#
# CONSUMER UNPORTABILITY: second-shift-only, same as its sibling. It reconciles against
# tracker COMMENTS, which a read-only tracker (`tracker.writes: false`) posts none of. lean's
# integrity contract is dogfood-scoped for now; consumer-side enforcement is a named
# promotion prerequisite. Do not ship this to the consumer CI template.
#
# Inputs (ALL via the environment — never spliced into a `run:` line; a PR body is
# attacker-controllable, and ci.yml documents this convention):
#   LEAN_BRANCH_PREFIX      required  e.g. "lean/second-shift-"
#   PIPELINE_BRANCH_PREFIX  required  e.g. "claude/second-shift-" (the exclusion arm)
#   PR_HEAD_REF             required  the PR's head branch name
#   PR_BODY                 required-ish  the PR body (empty is legal; it just fails to resolve)
#   PR_CREATED_AT           required  ISO-8601; the PR-open observation point
#   PR_HEAD_SHA             required  the PR head commit the freshness check measures against.
#                                     NOT `HEAD`: on a pull_request event actions/checkout
#                                     resolves refs/pull/N/merge, so HEAD is merge(base, head)
#                                     and every base-side commit since the branch point would
#                                     read as "changed after the verdict".
#   PR_BASE_REF             required for the live diff, and for evidence 5's patch-id arm  the
#                                     PR's base branch. This is the base the patch identity is
#                                     measured from, and it is deliberately NOT reconciled
#                                     against the runtime config's baseBranch — CI cannot see
#                                     that file. The two agree whenever the PR targets the
#                                     configured base, which is the lane's contract; a PR
#                                     retargeted elsewhere reds here, which is fail-closed.
#   GH_REPO                 required for the live path  "<owner>/<repo>"
#   GH_TOKEN                required for the live path
#   LEAN_COMMENT_AUTHOR     optional  exact bot login; absent degrades to "any Bot author"
#
# Seams (zero-network selftest, the check-pipeline-chain.sh precedent):
#   ${GH:-gh}                  the CLI used for the comment fetch
#   --comments-file <path>     read the comment trail from a JSON fixture
#   --diff-files-file <path>   read the PR's changed-file list from a newline-delimited fixture
#
# Exit 0 = pass or not-applicable; 1 = evidence violation; 2 = usage/environment error.
set -uo pipefail

GH_CLI="${GH:-gh}"
COMMENTS_FILE=""
DIFF_FILES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --comments-file)   COMMENTS_FILE="${2:-}"; shift 2 ;;
    --diff-files-file) DIFF_FILES_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,102p' "$0"; exit 0 ;;
    *) echo "[lean-chain] unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail()    { echo "[lean-chain] ✗ $1" >&2; exit 1; }
envfail() { echo "[lean-chain] $1" >&2; exit 2; }

# LOCKSTEP-BEGIN lean-chain-artifact-patterns
# The lean-marked name shapes, suffix-anchored. `*-lean.md` must never match the verdict
# record (`*-lean-verdict.md`) — that is why both are anchored at the END of the filename
# rather than matched as substrings. lean-gate.sh derives the same two names from config;
# here they are patterns, because CI has no access to the gitignored runtime config.
LEAN_SPEC_SUFFIX='-lean.md'
LEAN_VERDICT_SUFFIX='-lean-verdict.md'
LEAN_INTENT_GAP_SUFFIX='-lean-intent-gap.md'
# LOCKSTEP-END lean-chain-artifact-patterns

# Fixture paths are lean-shaped ON PURPOSE (the selftests below need lean-looking files), so
# they must never make a PR applicable. Anything under a fixtures dir is out of the scan.
is_fixture_path() {
  case "$1" in
    */fixtures/*|*-fixtures/*|fixtures/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- (1) env constants: fail closed, never "exempt" -------------------------------------
# An unresolvable prefix must never degrade into "not applicable". Same posture as the
# sibling gate, for the same reason: a vacuous green is the worst outcome available here.
[[ -n "${LEAN_BRANCH_PREFIX:-}" ]] \
  || envfail "LEAN_BRANCH_PREFIX is unset or empty — refusing to run (an unresolvable prefix would weaken applicability to the artifact arm alone). Set it on the pr-gates job."
[[ -n "${PIPELINE_BRANCH_PREFIX:-}" ]] \
  || envfail "PIPELINE_BRANCH_PREFIX is unset or empty — refusing to run (the artifact arm needs it to avoid double-classifying pipeline PRs). It is set at job level on pr-gates."
[[ -n "${PR_HEAD_REF:-}" ]] \
  || envfail "PR_HEAD_REF is unset or empty — nothing to classify."
[[ -n "${PR_CREATED_AT:-}" ]] \
  || envfail "PR_CREATED_AT is unset or empty — the PR-open observation point is unresolvable."
[[ -n "${PR_HEAD_SHA:-}" ]] \
  || envfail "PR_HEAD_SHA is unset or empty — the freshness check has nothing to measure the verdict against, and 'a verdict exists' is not 'this head was approved'. Set it on the pr-gates job."

# The two prefixes must be mutually non-prefix-matching, or the two gates double-classify.
# lean-gate.sh asserts this at derivation time; assert it again here, because CI's copies are
# independent constants that nothing reconciles against the runtime config (the T0 residual).
if [[ "$LEAN_BRANCH_PREFIX" == "$PIPELINE_BRANCH_PREFIX"* || "$PIPELINE_BRANCH_PREFIX" == "$LEAN_BRANCH_PREFIX"* ]]; then
  envfail "LEAN_BRANCH_PREFIX ('$LEAN_BRANCH_PREFIX') and PIPELINE_BRANCH_PREFIX ('$PIPELINE_BRANCH_PREFIX') must be mutually non-prefix-matching; one is a prefix of the other, so both gates would classify the same PRs."
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the committed artifacts."

# ---- (2) resolve the PR's changed files (for the artifact arm) ---------------------------
changed_files() {
  if [[ -n "$DIFF_FILES_FILE" ]]; then
    [[ -f "$DIFF_FILES_FILE" ]] || envfail "--diff-files-file '$DIFF_FILES_FILE' does not exist."
    cat "$DIFF_FILES_FILE"
    return 0
  fi
  [[ -n "${PR_BASE_REF:-}" ]] || return 0   # no base ref ⇒ no artifact arm, prefix arm still applies
  local mb
  mb="$(git merge-base "origin/$PR_BASE_REF" HEAD 2>/dev/null)" || return 0
  git diff --name-only "$mb"..HEAD 2>/dev/null || true
}

LEAN_SPEC_IN_DIFF=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_fixture_path "$f" && continue
  case "$f" in
    *"$LEAN_VERDICT_SUFFIX") continue ;;                 # the verdict record is not the spec
    *"$LEAN_SPEC_SUFFIX") LEAN_SPEC_IN_DIFF="$f"; break ;;
  esac
done < <(changed_files)

# ---- (3) applicability (AC-13) ----------------------------------------------------------
APPLICABLE=0
TRIGGER=""
if [[ "$PR_HEAD_REF" == "$LEAN_BRANCH_PREFIX"* ]]; then
  APPLICABLE=1; TRIGGER="branch-prefix"
elif [[ -n "$LEAN_SPEC_IN_DIFF" && "$PR_HEAD_REF" != "$PIPELINE_BRANCH_PREFIX"* ]]; then
  APPLICABLE=1; TRIGGER="lean-artifact ($LEAN_SPEC_IN_DIFF)"
fi

if [[ "$APPLICABLE" -eq 0 ]]; then
  # Echo the resolved prefixes: a stale constant is otherwise invisible (it just never matches).
  echo "[lean-chain] non-lean change — lean chain check not applicable."
  echo "[lean-chain]   head branch: $PR_HEAD_REF"
  echo "[lean-chain]   configured lean prefix: $LEAN_BRANCH_PREFIX"
  if [[ -n "$LEAN_SPEC_IN_DIFF" ]]; then
    echo "[lean-chain]   note: a lean-marked spec IS present ($LEAN_SPEC_IN_DIFF) but the head branch is pipeline-authored — classified to the pipeline chain gate, not this one."
  fi
  exit 0
fi

echo "[lean-chain] applicable via $TRIGGER: branch=$PR_HEAD_REF"

# ---- (4) resolve the source issue from the PR body --------------------------------------
# `Closes #N` wins over `Part of #N`: a program PR routinely carries both, and a bare
# first-match would resolve to the epic.
BODY="${PR_BODY:-}"
KEY="$(printf '%s' "$BODY" | grep -oiE 'closes[[:space:]]+#[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)"
if [[ -z "$KEY" ]]; then
  KEY="$(printf '%s' "$BODY" | grep -oiE 'part[[:space:]]+of[[:space:]]+#[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)"
fi
[[ -n "$KEY" ]] \
  || fail "PR body carries no resolvable issue reference ('Closes #N' or 'Part of #N'), but this PR is classified lean via $TRIGGER. Add the reference."

# On the prefix arm the branch suffix is itself the key — assert the two agree.
if [[ "$TRIGGER" == "branch-prefix" ]]; then
  SUFFIX="${PR_HEAD_REF#"$LEAN_BRANCH_PREFIX"}"
  if [[ "$SUFFIX" =~ ^([0-9]+)$ ]]; then
    [[ "${BASH_REMATCH[1]}" == "$KEY" ]] \
      || fail "key mismatch: PR body references #$KEY but the head branch resolves to #${BASH_REMATCH[1]}."
  else
    echo "[lean-chain] prefix-matched branch with a non-key suffix ('$SUFFIX') — using the body key #$KEY."
  fi
fi

echo "[lean-chain] source issue: #$KEY"

violations=0
note_violation() { echo "[lean-chain]   ✗ $1" >&2; violations=$((violations + 1)); }

# ---- (5) evidence 1: a committed lean spec carrying >= 1 AC-n ----------------------------
SPEC=""
if [[ -n "$LEAN_SPEC_IN_DIFF" && -f "$REPO_ROOT/$LEAN_SPEC_IN_DIFF" ]]; then
  SPEC="$LEAN_SPEC_IN_DIFF"
else
  # Prefix-arm PRs need not have the spec in THIS diff (a resumed run may have committed it
  # earlier), so fall back to locating it in the tree by the pinned suffix + issue key.
  while IFS= read -r f; do
    is_fixture_path "$f" && continue
    case "$f" in *"$LEAN_VERDICT_SUFFIX") continue ;; esac
    case "$(basename "$f")" in *"-$KEY$LEAN_SPEC_SUFFIX") SPEC="${f#"$REPO_ROOT/"}"; break ;; esac
  done < <(find "$REPO_ROOT" -name "*$LEAN_SPEC_SUFFIX" -type f 2>/dev/null)
fi

if [[ -z "$SPEC" ]]; then
  note_violation "no committed lean spec (a file named *$LEAN_SPEC_SUFFIX for #$KEY). The spec IS the definition of done; without it nothing constrains the change."
else
  ac_count="$(grep -cE '(^|[^A-Za-z])AC-[0-9]+' "$REPO_ROOT/$SPEC" 2>/dev/null)" || ac_count=0
  if [[ "${ac_count:-0}" -lt 1 ]]; then
    note_violation "committed spec '$SPEC' carries no numbered AC-n criterion."
  else
    echo "[lean-chain]   ✓ spec: $SPEC ($ac_count AC-n reference(s))"
  fi
fi

# ---- (6) evidence 2: a committed verdict record reading verdict=approve ------------------
VERDICT=""
while IFS= read -r f; do
  is_fixture_path "${f#"$REPO_ROOT/"}" && continue
  case "$(basename "$f")" in *"-$KEY$LEAN_VERDICT_SUFFIX") VERDICT="${f#"$REPO_ROOT/"}"; break ;; esac
done < <(find "$REPO_ROOT" -name "*$LEAN_VERDICT_SUFFIX" -type f 2>/dev/null)

VERDICT_RUN_ID=""
VERDICT_SESSION_ID=""
VERDICT_REVIEWED_HEAD=""
VERDICT_REVIEWED_PATCH_ID=""
if [[ -z "$VERDICT" ]]; then
  note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX). The independent review's verdict must be a committed, diffable artifact — a local progress-file line is not evidence."
else
  # FIRST-MATCH, never a count over the whole file. `lean-gate.sh verdict --summary-file`
  # appends the reviewer's own prose below these keys, and review prose discusses verdicts:
  # the committed record for #237 carries `verdict=approve` on line 3 and again on line 9
  # inside a sentence about the previous round. A count-anywhere reader passes a record whose
  # authoritative first line says `needs-work`. Line-anchoring was rejected instead of this
  # because the earliest records write the key as a bullet or table cell, and an anchor would
  # reclassify already-merged evidence as unreadable. lean-gate.sh's record_verdict() is the
  # same read on the same file.
  verdict_value="$(grep -oE 'verdict=[A-Za-z-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/^verdict=//')"
  if [[ "$verdict_value" != "approve" ]]; then
    note_violation "verdict record '$VERDICT' reads 'verdict=${verdict_value:-<none>}', not 'verdict=approve'."
  else
    echo "[lean-chain]   ✓ verdict record: $VERDICT (verdict=approve)"
  fi
  # `session_id:` does not contain the substring `run_id:`, so the two extractions cannot
  # capture each other; head -n1 keeps the first occurrence of each, matching the shape
  # lean-gate.sh and lean-reconcile.sh read the same record with.
  VERDICT_RUN_ID="$(grep -oE 'run_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/run_id:[[:space:]]*//')"
  VERDICT_SESSION_ID="$(grep -oE 'session_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/session_id:[[:space:]]*//')"
  # Same first-match shape, same charset. No other key in the record contains the substring
  # `reviewed_head:`, so this extraction cannot capture one of theirs or be captured by it —
  # `reviewed_patch_id:` in particular is a different string, not an extension of this one.
  VERDICT_REVIEWED_HEAD="$(grep -oE 'reviewed_head:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/reviewed_head:[[:space:]]*//')"
  VERDICT_REVIEWED_PATCH_ID="$(grep -oE 'reviewed_patch_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/reviewed_patch_id:[[:space:]]*//')"
fi

# ---- (7) evidence 3: a bot-authored lean-claimed comment, windowed at PR-open ------------
if [[ -n "$COMMENTS_FILE" ]]; then
  [[ -f "$COMMENTS_FILE" ]] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
  COMMENTS="$(cat "$COMMENTS_FILE")"
else
  [[ -n "${GH_REPO:-}" ]] || envfail "GH_REPO is unset — cannot fetch the comment trail."
  COMMENTS="$("$GH_CLI" api "repos/$GH_REPO/issues/$KEY/comments" --paginate 2>&1)" || {
    # A failed fetch is an ENVIRONMENT error, never a silent pass: fail-open here would waive
    # the whole gate on any rate limit or transient 5xx.
    echo "[lean-chain] comment fetch failed for issue #$KEY:" >&2
    printf '%s\n' "$COMMENTS" >&2
    exit 2
  }
fi
printf '%s' "$COMMENTS" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || envfail "comment trail is not a JSON array — cannot reconcile."

# TRUST FILTER (load-bearing on a PUBLIC repo). Issue comments are writable by any account, so
# the raw trail is not the agent-written record this reasons about — an outsider could post a
# lean-claimed marker. `.user.type == "Bot"` is the filter, optionally narrowed by an exact
# login. Measured on the sibling gate: the pipeline bot posts with author_association
# CONTRIBUTOR, so an OWNER/MEMBER allowlist would filter out the bot itself.
#
# Windowing to PR-open makes the gate idempotent: pr-gates re-runs on every synchronize, and a
# LATER re-claim of the same issue must not retroactively red-line an already-green PR. A PR's
# created_at is immutable, so the window is stable across re-runs.
# shellcheck disable=SC2016  # $author/$at are jq variables, bound with --arg; shell must not expand them.
CLAIM_FILTER='
  [ .[]
    | select((.user.type // "") == "Bot")
    | select($author == "" or (.user.login // "") == $author)
    | select((.created_at // "") != "" and .created_at <= $at)
    | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*lean-claimed[[:space:]]*-->"))
  ]'

CLAIMED="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  "$CLAIM_FILTER | length")"

# The build run's identity as CI can see it. Same filter as the count above — reading the id
# off a comment that did not pass the trust/window filter would let an outsider's marker (or a
# later re-claim) define what "the build run" means for this PR.
CLAIM_RUN_ID="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  "$CLAIM_FILTER | map((.body // \"\") | capture(\"run_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)\").r? // \"\") | map(select(. != \"\")) | first // \"\"")"

# The build SESSION as CI can see it, when the claim carries one. `session_id:` does not
# contain the substring `run_id:`, so the capture above cannot have consumed it.
CLAIM_SESSION_ID="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  "$CLAIM_FILTER | map((.body // \"\") | capture(\"session_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)\").r? // \"\") | map(select(. != \"\" and . != \"unset\")) | first // \"\"")"

if [[ "${CLAIMED:-0}" -lt 1 ]]; then
  any="$(printf '%s' "$COMMENTS" | jq -r '[ .[] | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*lean-claimed[[:space:]]*-->")) ] | length')"
  if [[ "${any:-0}" -gt 0 ]]; then
    note_violation "found $any 'lean-claimed' marker(s) on #$KEY, but none that are bot-authored AND at or before PR-open ($PR_CREATED_AT). An operator-posted claim is not evidence the harness ran."
  else
    note_violation "no bot-authored 'lean-claimed' comment on #$KEY at or before PR-open ($PR_CREATED_AT). The run left no claim record."
  fi
else
  echo "[lean-chain]   ✓ claim: bot-authored lean-claimed comment on #$KEY within the PR-open window"
fi

# ---- (8) evidence 4: the verdict was authored OUTSIDE the build session (P10) ------------
# Skipped only when there is no verdict record at all — that is already a violation, and
# reporting "authorship unverifiable" on top of "no verdict" is noise, not information.
if [[ -n "$VERDICT" ]]; then
  if [[ -z "$VERDICT_RUN_ID" ]]; then
    note_violation "verdict record '$VERDICT' carries no run_id reconciliation key, so its authorship cannot be separated from the build run's."
  elif [[ -z "$VERDICT_SESSION_ID" ]]; then
    note_violation "verdict record '$VERDICT' carries no session_id reconciliation key — the review session that produced it cannot be located, so nothing outside the record itself attests the review ran."
  elif [[ -z "$CLAIM_RUN_ID" ]]; then
    note_violation "the bot-authored lean-claimed comment on #$KEY carries no run_id, so the build run's identity is unknown and the verdict's independence is uncheckable."
  elif [[ "$VERDICT_RUN_ID" == "$CLAIM_RUN_ID" ]]; then
    note_violation "verdict record '$VERDICT' carries the BUILD run's identity ('$VERDICT_RUN_ID') — the session that wrote the code also wrote its own review verdict. The verdict must come from a separate review session carrying its own identity."
  elif [[ -n "$CLAIM_SESSION_ID" && "$VERDICT_SESSION_ID" == "$CLAIM_SESSION_ID" ]]; then
    # The STRONGER of the two comparisons, and the reason cmd_claim carries a session id at
    # all: run_id is agent-CHOSEN, so a build session determined to review itself need only
    # pick a second string, whereas the session id is harness-assigned.
    note_violation "verdict record '$VERDICT' names the BUILD session ('$VERDICT_SESSION_ID') as its author — a distinct run_id does not make it an independent review (P10)."
  else
    echo "[lean-chain]   ✓ authorship: verdict run_id ($VERDICT_RUN_ID) is distinct from the build claim's ($CLAIM_RUN_ID), and the record names its review session"
    # TRANSITIONAL, and deliberately not a violation. Claim comments posted before the claim
    # writer carried a session id have none, and there is no remedy available: the comment
    # must fall inside the immutable PR-open window, so it cannot be re-posted for an open PR.
    # Refusing here would strand those PRs with no action that clears the gate. The run_id arm
    # above still applies to them, and lean-reconcile.sh makes the session comparison
    # out-of-band against the progress file, which is not window-bound.
    [[ -n "$CLAIM_SESSION_ID" ]] \
      || echo "[lean-chain]   note: the claim comment carries no session_id (claimed before the writer emitted one) — only the run-id half of the authorship comparison was available."
  fi
fi

# ---- (9) evidence 5: the verdict covers the head being merged ----------------------------
# Skipped when there is no verdict record — already a violation, and "unverifiable freshness"
# on top of "no verdict" is noise. The tolerance is exactly one path, the record itself,
# because the review session commits nothing else (review-lean step 6).
#
# #374 AC-4/5/6: VACUITY. "Fresh" is a claim about an approve — a needs-work record is not
# stale or fresh, because there is nothing for either arm to be measured against: the record
# does not certify this code either way, regardless of what changed after it. Evaluating both
# arms anyway restates evidence 2's "not approve" finding twice more, in slightly different
# words, which is exactly the "one fact printed as three violations" defect this fix removes —
# observed live on a #372 round-2 build. So a non-approve value short-circuits here to ONE
# refusal naming it, before either arm's git/patch-id computation runs at all. An approve
# record is unaffected: both arms below evaluate exactly as they did before this change (AC-5).
if [[ -n "$VERDICT" && "$verdict_value" != "approve" ]]; then
  note_violation "verdict record '$VERDICT' reads 'verdict=${verdict_value:-<none>}', not 'verdict=approve' — freshness is undefined for a non-approve record, so the changed-files and patch-id/reviewed-head arms are not evaluated."
elif [[ -n "$VERDICT" ]]; then
  git -C "$REPO_ROOT" cat-file -e "$PR_HEAD_SHA^{commit}" 2>/dev/null \
    || envfail "PR_HEAD_SHA '$PR_HEAD_SHA' is not a commit in this checkout — the freshness check cannot run, and a check that cannot run must not report a pass."
  VERDICT_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT" 2>/dev/null)"
  if [[ -z "$VERDICT_COMMIT" ]]; then
    note_violation "verdict record '$VERDICT' is present in the tree but carries no commit — it was never committed to the branch, so nothing dates it against the code."
  else
    STALE="$(git -C "$REPO_ROOT" diff --name-only "$VERDICT_COMMIT" "$PR_HEAD_SHA" 2>/dev/null | grep -vxF "$VERDICT" || true)"
    if [[ -n "$STALE" ]]; then
      n_stale="$(printf '%s\n' "$STALE" | wc -l | tr -d ' ')"
      note_violation "verdict record '$VERDICT' approves $(git -C "$REPO_ROOT" rev-parse --short "$VERDICT_COMMIT"), but $n_stale file(s) changed between that commit and the PR head (e.g. $(printf '%s' "$STALE" | head -n1)). An approve for an earlier head is not an approve for this one — run another review round."
    else
      echo "[lean-chain]   ✓ freshness (inferred): nothing but the verdict record itself changed between its commit and the PR head"
    fi
  fi

  # The DECLARED arm. Refused when absent for the same reason a missing verdict is: nothing is
  # checkable. Records written before this key existed are refused too — unlike the claim
  # comment's missing session_id above, a remedy IS available here (re-run the review round),
  # so a transitional pass would be a waiver rather than a kindness.
  #
  # `reviewed_patch_id` takes precedence over the `reviewed_head` SHA when present; the SHA path
  # below is what records predating that key gate on. The precedence is one-way and never
  # AND-ed: running both would re-impose the rebase refusal the patch-id exists to remove, since
  # this checkout holds no pre-rebase object to resolve the SHA against.
  if [[ -z "$VERDICT_REVIEWED_HEAD" ]]; then
    note_violation "verdict record '$VERDICT' carries no reviewed_head key, so nothing states which commit the review actually read. Re-run the review round on a dev-pipeline that writes it: '/dev-pipeline:review-lean <pr>'."
  elif [[ -n "$VERDICT_REVIEWED_PATCH_ID" ]]; then
    # Both failures below are ENVIRONMENT errors, not violations, and for the (Q1)/(Q2) reason:
    # `git patch-id` prints NOTHING for an empty diff, so two failed computations compare EQUAL
    # and an unguarded reader prints its ✓ having hashed nothing. A check that cannot run must
    # not report a pass — and must not report a violation either, since the evidence is not what
    # is missing.
    #
    # ONE guard over the whole computation, not one per step. An unresolvable merge-base and an
    # empty measured range both surface as an empty id, and splitting them produced an arm no
    # case could kill: whichever fired second was unreachable, because reaching it required the
    # first to have succeeded. An unkillable guard reads as coverage while asserting nothing.
    # PR_BASE_REF stays separate because its remedy is different — a job-level env fix, not a
    # checkout-depth one — and (U5) kills it on its own.
    [[ -n "${PR_BASE_REF:-}" ]] \
      || envfail "verdict record '$VERDICT' declares a reviewed_patch_id, but PR_BASE_REF is unset or empty — the branch's patch identity cannot be recomputed without a base to measure from. Set it on the pr-gates job."
    CUR_PATCH_ID="$(git -C "$REPO_ROOT" diff "$(git -C "$REPO_ROOT" merge-base "origin/$PR_BASE_REF" "$PR_HEAD_SHA" 2>/dev/null)" \
      "$PR_HEAD_SHA" -- . ":(exclude)$VERDICT" 2>/dev/null \
      | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
    if [[ -z "$CUR_PATCH_ID" ]]; then
      envfail "cannot compute this branch's patch identity against origin/$PR_BASE_REF — the merge-base is unresolvable (a full-history checkout of the base is required: fetch-depth: 0), or the branch's diff excluding '$VERDICT' is empty. Either way there is nothing to compare the verdict's reviewed_patch_id against."
    elif [[ "$CUR_PATCH_ID" != "$VERDICT_REVIEWED_PATCH_ID" ]]; then
      note_violation "verdict record '$VERDICT' reviewed patch ${VERDICT_REVIEWED_PATCH_ID:0:12}, but this branch's diff against origin/$PR_BASE_REF now hashes to ${CUR_PATCH_ID:0:12}. Content changed after the review — a commit landed, or a rebase resolved a conflict by altering a line — so the review read a different tree than the one being merged. Run another review round."
    else
      echo "[lean-chain]   ✓ freshness (declared, patch-id ${CUR_PATCH_ID:0:12}): the branch's diff against origin/$PR_BASE_REF is the one the review read"
    fi
  elif ! git -C "$REPO_ROOT" cat-file -e "$VERDICT_REVIEWED_HEAD^{commit}" 2>/dev/null; then
    note_violation "verdict record '$VERDICT' names reviewed_head $VERDICT_REVIEWED_HEAD, for which this checkout holds no commit — the branch was rebased or force-pushed after the review, so the reviewed code is not what is being merged. Re-run the review round."
  else
    DECLARED_STALE="$(git -C "$REPO_ROOT" diff --name-only "$VERDICT_REVIEWED_HEAD" "$PR_HEAD_SHA" 2>/dev/null | grep -vxF "$VERDICT" || true)"
    if [[ -n "$DECLARED_STALE" ]]; then
      n_declared="$(printf '%s\n' "$DECLARED_STALE" | wc -l | tr -d ' ')"
      note_violation "verdict record '$VERDICT' states it reviewed $(git -C "$REPO_ROOT" rev-parse --short "$VERDICT_REVIEWED_HEAD" 2>/dev/null), but $n_declared file(s) differ between that commit and the PR head (e.g. $(printf '%s' "$DECLARED_STALE" | head -n1)). The review read a different tree than the one being merged — run another review round."
    else
      echo "[lean-chain]   ✓ freshness (declared): the record names $(git -C "$REPO_ROOT" rev-parse --short "$VERDICT_REVIEWED_HEAD" 2>/dev/null) as the head it reviewed, and only the record itself differs from the PR head"
    fi
  fi
fi

# ---- (10) evidence 6: no unratified intent-gap record (P9) -------------------------------
# A decision that surfaces during BUILD and is not in the receipt is not a failure — it is
# ordinary operation, and the intent-gap record is the channel it routes back through instead
# of becoming a silent choice. What must not happen is the merge landing while that decision
# is still the build run's own call. The record is a committed artifact for the same reason
# the verdict is: a local note nobody can diff is not evidence.
#
# The gate checks RATIFICATION and nothing else. It deliberately does not re-validate the
# record's disposition against the receipt's enum — that enum is single-sited in
# ledger-lint.sh, and a second copy here would be the duplicate machinery the lockstep
# manifest calls worse than none.
#
# ABSENCE IS LEGAL, and PRINTED. Most runs surface no gap, so "no record" is the common case
# rather than a missing artifact — but it is announced, so a reader of the log can tell
# "nothing surfaced" from "the arm never ran".
INTENT_GAP=""
while IFS= read -r f; do
  is_fixture_path "${f#"$REPO_ROOT/"}" && continue
  case "$(basename "$f")" in *"-$KEY$LEAN_INTENT_GAP_SUFFIX") INTENT_GAP="${f#"$REPO_ROOT/"}"; break ;; esac
done < <(find "$REPO_ROOT" -name "*$LEAN_INTENT_GAP_SUFFIX" -type f 2>/dev/null)

if [[ -z "$INTENT_GAP" ]]; then
  echo "[lean-chain]   · no intent-gap record for #$KEY — nothing surfaced during BUILD that the receipt did not already cover."
else
  # FIRST-MATCH, same discipline as the verdict read above: the record's prose discusses
  # ratification, and a count-anywhere reader would certify a record whose header says `no`.
  # `ratified_by:` cannot be captured here — the character after `ratified` is `_`, not `:`.
  GAP_RATIFIED="$(grep -oE 'ratified:[[:space:]]*[A-Za-z]+' "$REPO_ROOT/$INTENT_GAP" 2>/dev/null | head -n1 | sed -E 's/ratified:[[:space:]]*//')"
  GAP_BY="$(grep -oE 'ratified_by:[[:space:]]*https://[^[:space:]]+' "$REPO_ROOT/$INTENT_GAP" 2>/dev/null | head -n1 | sed -E 's/ratified_by:[[:space:]]*//')"
  if [[ "$GAP_RATIFIED" != "yes" ]]; then
    note_violation "intent-gap record '$INTENT_GAP' reads 'ratified: ${GAP_RATIFIED:-<none>}' — a decision the receipt never covered is still the build run's own call, and P9 routes it back to the human before it merges. Ratify it on #$KEY and record the comment URL as 'ratified_by:'."
  elif [[ -z "$GAP_BY" ]]; then
    note_violation "intent-gap record '$INTENT_GAP' claims 'ratified: yes' but cites no 'ratified_by:' URL — a ratification the run wrote about itself is a self-ratification. Cite the operator's comment."
  else
    echo "[lean-chain]   ✓ intent gap: $INTENT_GAP ratified ($GAP_BY)"
  fi
fi

# ---- (11) verdict -----------------------------------------------------------------------
if [[ "$violations" -gt 0 ]]; then
  echo "[lean-chain] ✗ $violations evidence artifact(s) missing for lean PR on #$KEY." >&2
  echo "[lean-chain]   The remedy is producing the missing artifact — there is no waiver." >&2
  exit 1
fi

echo "[lean-chain] lean evidence complete for #$KEY (spec + approve-verdict covering the head + claim)."
