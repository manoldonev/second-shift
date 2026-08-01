#!/usr/bin/env bash
# check-pipeline-chain.sh — T2 rung 1: reconcile a pipeline-authored PR against its stage trail.
#
# Fails a PR whose head branch is pipeline-authored unless the stage-marker chain VISIBLE AT
# PR-OPEN TIME exists, belongs to one run family, and is key-consistent with the branch and the
# committed plan file.
#
# HONEST ALTITUDE: every record read here — the tracker comments, the PR body, the committed
# plan — is written by the agent being checked. This is tamper-EVIDENCE, not proof. Forging one
# record is easy; forging all of them consistently is what this makes detectable. Harness
# attestation is rung 2. See docs/pipeline-manifesto.md.
#
# CONSUMER UNPORTABILITY: this check is second-shift-only by construction. It reconciles against
# tracker COMMENTS, and a read-only tracker (config `tracker.writes: false`, e.g. the jira
# adapter) posts none by contract — under such a consumer every applicable PR would fail on a
# trail that can never exist. Do not ship it to the consumer CI template.
#
# Inputs (all via the environment — never spliced into a `run:` line; a PR body is
# attacker-controllable, and ci.yml already documents this convention for BASE_REF):
#   PIPELINE_BRANCH_PREFIX  required  e.g. "claude/second-shift-"
#   PIPELINE_PLAN_PATTERN   required  e.g. "docs/plans/acme-{issueKey}.md"
#   PR_HEAD_REF             required  the PR's head branch name
#   PR_BODY                 required-ish  the PR body (empty is legal; it just fails to resolve)
#   PR_CREATED_AT           required  ISO-8601; the PR-open observation point
#   GH_REPO                 required for the live path  "<owner>/<repo>"
#   GH_TOKEN                required for the live path
#   PIPELINE_COMMENT_AUTHOR optional  exact bot login the stage trail must come from; absent
#                                     degrades to "any Bot author" (see the trust filter below)
#
# Seams (zero-network selftest, following preflight-selftest.sh's PATH-mock precedent):
#   ${GH:-gh}               the CLI used for the comment fetch
#   --comments-file <path>  read the comment trail from a JSON fixture instead of fetching
#
# The env constants exist because the runtime config (.claude/second-shift.config.json) is
# gitignored and absent in CI. Nothing reconciles them against it: a stale prefix matches zero
# branches and this check degrades to a silent no-op. That is why an unresolvable constant is
# fatal rather than exempt, and why the resolved prefix is echoed on every not-applicable
# verdict. The residual risk is recorded in the manifesto's T0 note.
#
# Exit 0 = pass or not-applicable; 1 = chain violation; 2 = usage/environment error.
# (Same convention as check-frozen-files.sh.)
set -uo pipefail

GH_CLI="${GH:-gh}"
COMMENTS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "[pipeline-chain] unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail()  { echo "[pipeline-chain] ✗ $1" >&2; exit 1; }
envfail() { echo "[pipeline-chain] $1" >&2; exit 2; }

# LOCKSTEP-BEGIN pipeline-chain-required-markers
# The markers required at PR-open time. A deliberate NARROWING of the stage-comment enum in
# plugins/dev-pipeline/skills/run/state-schema.md: `plan-review` and `verify` are conditional
# (verify emits on the failure path only), and `pr` is out of reach — it is posted AFTER the PR
# is created and no event re-triggers this check.
#
# `code-review` is unconditional here. Its receipt is completion-gated whenever a primary review
# round ran; the zero-marker escape hatches are be-fe-pair-only and unreachable under this repo's
# `standalone` topology. A conditional leg would be self-satisfying and would contribute zero
# tamper-evidence against exactly the dark-reviewer class this program targets.
REQUIRED_MARKERS='claimed|intake|plan|doc-update|code-review'
# LOCKSTEP-END pipeline-chain-required-markers

# ---- (1) env constants: fail closed, never "exempt" -------------------------------------
# An unresolvable prefix must never degrade into "non-pipeline, not applicable" — a vacuous
# green is the worst outcome this check can produce.
[[ -n "${PIPELINE_BRANCH_PREFIX:-}" ]] \
  || envfail "PIPELINE_BRANCH_PREFIX is unset or empty — refusing to run (an unresolvable prefix would silently exempt every PR). Set it on the pr-gates job."
[[ -n "${PIPELINE_PLAN_PATTERN:-}" ]] \
  || envfail "PIPELINE_PLAN_PATTERN is unset or empty — refusing to run. Set it on the pr-gates job."
[[ -n "${PR_HEAD_REF:-}" ]] \
  || envfail "PR_HEAD_REF is unset or empty — nothing to classify."
[[ -n "${PR_CREATED_AT:-}" ]] \
  || envfail "PR_CREATED_AT is unset or empty — the PR-open observation point is unresolvable."

# ---- (2) applicability: prefix ----------------------------------------------------------
if [[ "$PR_HEAD_REF" != "$PIPELINE_BRANCH_PREFIX"* ]]; then
  # Echo the resolved prefix: a stale constant is otherwise invisible (it just never matches).
  echo "[pipeline-chain] non-pipeline change — chain check not applicable."
  echo "[pipeline-chain]   head branch: $PR_HEAD_REF"
  echo "[pipeline-chain]   configured prefix: $PIPELINE_BRANCH_PREFIX"
  exit 0
fi

# ---- (3) applicability: the suffix must parse as an issue key ---------------------------
SUFFIX="${PR_HEAD_REF#"$PIPELINE_BRANCH_PREFIX"}"
if [[ ! "$SUFFIX" =~ ^([0-9]+)$ ]]; then
  # A hand-made branch that happens to share the namespace. Exempt WITH NOTICE, not failed —
  # the branch carries no issue key, so there is no trail to reconcile against.
  echo "[pipeline-chain] prefix-matched branch with a non-key suffix ('$SUFFIX') — exempt with notice."
  echo "[pipeline-chain]   head branch: $PR_HEAD_REF"
  exit 0
fi
KEY_BRANCH="${BASH_REMATCH[1]}"

echo "[pipeline-chain] applicable: branch=$PR_HEAD_REF key=$KEY_BRANCH"

# ---- (4) resolve the source issue from the PR body --------------------------------------
# `Closes #N` wins over `Part of #N` when both appear: a program PR routinely carries both
# (`Closes #273` for the worked ticket, `Part of #268` for the epic), so a bare first-match
# would resolve to the epic and mismatch the branch suffix on every one of them.
BODY="${PR_BODY:-}"
KEY_BODY="$(printf '%s' "$BODY" | grep -oiE 'closes[[:space:]]+#[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)"
if [[ -z "$KEY_BODY" ]]; then
  KEY_BODY="$(printf '%s' "$BODY" | grep -oiE 'part[[:space:]]+of[[:space:]]+#[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)"
fi
if [[ -z "$KEY_BODY" ]]; then
  # NOT an exemption: a pipeline-authored branch with no traceable source issue is precisely
  # the class this check exists to catch.
  fail "PR body carries no resolvable issue reference ('Closes #N' or 'Part of #N'), but the head branch '$PR_HEAD_REF' is pipeline-authored. Add the reference."
fi

# ---- (5) three-way key consistency ------------------------------------------------------
# (a) PR-body reference vs head-branch suffix.
if [[ "$KEY_BODY" != "$KEY_BRANCH" ]]; then
  fail "key mismatch: PR body references #$KEY_BODY but the head branch resolves to #$KEY_BRANCH."
fi

# The plan file is committed on the branch at Stage 3, and pr-gates runs actions/checkout@v5
# (fetch-depth: 0) on the PR ref — so the branch's plan file is present in the CI checkout.
plan_path_for() { # plan_path_for <key> -> the pattern-derived path
  printf '%s' "$PIPELINE_PLAN_PATTERN" \
    | sed -e "s|{issueKey}|$1|g" -e "s|{[a-zA-Z][a-zA-Z0-9]*}||g"
}
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the committed plan file."

# (b) branch key -> plan file must exist.
PLAN_BRANCH="$(plan_path_for "$KEY_BRANCH")"
[[ -f "$REPO_ROOT/$PLAN_BRANCH" ]] \
  || fail "no committed plan at '$PLAN_BRANCH' (derived from the head-branch key #$KEY_BRANCH). Stage 3 commits the plan onto the branch."

# (c) body key -> plan file must exist AND be the same file.
PLAN_BODY="$(plan_path_for "$KEY_BODY")"
[[ -f "$REPO_ROOT/$PLAN_BODY" ]] \
  || fail "no committed plan at '$PLAN_BODY' (derived from the PR-body key #$KEY_BODY)."
[[ "$PLAN_BODY" == "$PLAN_BRANCH" ]] \
  || fail "plan-path mismatch: PR body derives '$PLAN_BODY' but the head branch derives '$PLAN_BRANCH'."

echo "[pipeline-chain] key-consistent: body=#$KEY_BODY branch=#$KEY_BRANCH plan=$PLAN_BRANCH"

# ---- (6) fetch the comment trail --------------------------------------------------------
if [[ -n "$COMMENTS_FILE" ]]; then
  [[ -f "$COMMENTS_FILE" ]] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
  COMMENTS="$(cat "$COMMENTS_FILE")"
else
  [[ -n "${GH_REPO:-}" ]] || envfail "GH_REPO is unset — cannot fetch the comment trail."
  COMMENTS="$("$GH_CLI" api "repos/$GH_REPO/issues/$KEY_BRANCH/comments" --paginate 2>&1)" || {
    # A failed fetch is an ENVIRONMENT error, never a silent pass. Fail-open here would waive
    # the whole check on any rate limit or transient 5xx.
    echo "[pipeline-chain] comment fetch failed for issue #$KEY_BRANCH:" >&2
    printf '%s\n' "$COMMENTS" >&2
    exit 2
  }
fi
printf '%s' "$COMMENTS" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || envfail "comment trail is not a JSON array — cannot reconcile."

# ---- (7) trust-filter, window to PR-open, then select the active run family -------------
# TRUST FILTER (load-bearing on a PUBLIC repo). Issue comments are writable by any GitHub
# account, so the raw trail is NOT the agent-written record the rest of this check reasons
# about — an outsider could post a `claimed` marker and hijack family selection, red-lining a
# valid PR on a gate that has no waiver by design.
#
# The filter is `.user.type == "Bot"`, optionally narrowed to an exact login via
# PIPELINE_COMMENT_AUTHOR. Measured, not assumed: the pipeline bot posts with
# `author_association: CONTRIBUTOR`, so the intuitive OWNER/MEMBER/COLLABORATOR allowlist
# would filter out the pipeline itself and break the check on every run.
#
# PIPELINE_COMMENT_AUTHOR absent is NOT fail-closed, unlike the two constants above: it only
# NARROWS an already-safe filter, so its absence degrades to Bot-only rather than to a
# vacuous pass. The two required constants are different — absence there would exempt every
# PR, which is why they are fatal.
TRUSTED="$(printf '%s' "$COMMENTS" | jq --arg author "${PIPELINE_COMMENT_AUTHOR:-}" '
  [ .[] | select((.user.type // "") == "Bot")
        | select($author == "" or (.user.login // "") == $author) ]')"

# D-5 fixes the observation point at "the chain as of PR open". Windowing is what makes that
# real AND makes the gate idempotent: pr-gates is an unrestricted `pull_request` job, so it
# re-executes on every synchronize and manual re-run. Selecting the newest `claimed` outright
# would let a LATER re-claim of the same issue retroactively red-line an already-green PR, with
# no remedy available under the no-waiver rule. A PR's created_at is immutable, so the window is
# stable across re-runs.
IN_WINDOW="$(printf '%s' "$TRUSTED" \
  | jq --arg at "$PR_CREATED_AT" '[ .[] | select((.created_at // "") != "" and .created_at <= $at) ]')"

# Each comment's run_id is captured ONCE, here, and compared by EXACT STRING equality below —
# never re-matched as a regex. A run_id is agent-written, and a family value of `.*` spliced
# into a regex would make every comment match, silently turning this whole check vacuous: the
# single-family property is precisely the tamper-evidence this rung contributes, so it must not
# be defeatable by one token in a comment the agent writes. The charset filter is the second
# layer — a malformed run_id can never be SELECTED as the family, so it cannot be exploited
# even if the comparison were ever loosened again.
WITH_RUN="$(printf '%s' "$IN_WINDOW" | jq '
  [ .[] | . + { run: ((.body // "")
      | capture("<!--[[:space:]]*run_id:[[:space:]]*(?<r>[^[:space:]]+)[[:space:]]*-->").r? // "")}
        | select(.run == "" or (.run | test("^[A-Za-z0-9._-]+$"))) ]')"

FAMILY="$(printf '%s' "$WITH_RUN" | jq -r '
  [ .[] | select(.body // "" | test("<!--[[:space:]]*stage:[[:space:]]*claimed[[:space:]]*-->"))
        | select(.run != "") ]
  | sort_by(.created_at) | last | .run // ""')"

if [[ -z "$FAMILY" || "$FAMILY" == "null" ]]; then
  fail "no 'claimed' marker with a run_id found in the trail of #$KEY_BRANCH at or before PR-open ($PR_CREATED_AT). The chain does not start."
fi

# Public-repo hygiene: RUN_ID is {timestamp}-{hex} — no host component. Actions logs on a
# public repo are world-readable, so only the trailing random segment is ever printed — enough
# to tell families apart.
FAMILY_SHORT="${FAMILY##*-}"
echo "[pipeline-chain] active run family (truncated): …$FAMILY_SHORT  (${PR_CREATED_AT} window)"

# ---- (8) every required marker must be present IN THAT FAMILY ---------------------------
violations=0
OLD_IFS="$IFS"; IFS='|'
# shellcheck disable=SC2206  # word-splitting on IFS='|' is the intended parse
MARKERS=($REQUIRED_MARKERS)
IFS="$OLD_IFS"

for m in "${MARKERS[@]}"; do
  # `.run == $f` — exact equality, never test($f). See the WITH_RUN note above.
  in_family="$(printf '%s' "$WITH_RUN" | jq -r --arg m "$m" --arg f "$FAMILY" '
    [ .[] | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $m + "[[:space:]]*-->"))
          | select(.run == $f) ] | length')"
  if [[ "$in_family" -gt 0 ]]; then
    echo "[pipeline-chain]   ✓ $m"
    continue
  fi
  any="$(printf '%s' "$WITH_RUN" | jq -r --arg m "$m" '
    [ .[] | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $m + "[[:space:]]*-->")) ] | length')"
  if [[ "$any" -gt 0 ]]; then
    echo "[pipeline-chain]   ✗ $m — found $any marker(s), none in the active family (…$FAMILY_SHORT). A stage from an earlier run does not evidence this one." >&2
  else
    echo "[pipeline-chain]   ✗ $m — absent from the trail at or before PR-open. That stage left no record." >&2
  fi
  violations=$((violations + 1))
done

if [[ "$violations" -gt 0 ]]; then
  echo "[pipeline-chain] ✗ $violations required marker(s) missing from the chain of #$KEY_BRANCH." >&2
  echo "[pipeline-chain]   The remedy is completing the missing stage or re-running the pipeline — there is no waiver." >&2
  exit 1
fi

echo "[pipeline-chain] chain complete and key-consistent for #$KEY_BRANCH (family …$FAMILY_SHORT)."
