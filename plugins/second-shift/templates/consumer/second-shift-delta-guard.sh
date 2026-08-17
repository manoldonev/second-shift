#!/usr/bin/env bash
# second-shift-delta-guard.sh — delta-aware consumer CI, committed into a consumer repo by
# /second-shift:onboard (#542). Classifies the PR's head commit and answers ONE question:
#
#   may this repo's heavy CI jobs be skipped for this push?
#
# WHAT IT IS FOR. `review-lean` requires the verdict record to be committed, pushed to the PR's
# head branch, and to be the LAST commit on it. In a consumer whose CI runs on `pull_request`,
# that push fires a second full run — lint, typecheck, build, the whole unit suite — whose only
# content is a markdown file the pipeline wrote itself. Measured on a real consumer: a complete
# re-run of a ~570-test lane for a docs-only commit, on every lean PR.
#
# WHY NOT `paths-ignore`. It is the natural reach and it is a no-op here: for `pull_request`
# events GitHub evaluates path filters against the WHOLE PR diff (base…head), not the
# incremental push. Every lean PR contains source changes, so every lean PR matches the filter
# regardless of what the last commit touched. `paths-ignore` only helps `push`-triggered
# workflows. Stated here because it will otherwise be proposed again and quietly fail.
#
# WHY NOT `[skip ci]`. It creates NO run for the head SHA. A repo with required status checks
# then blocks on a check that stays 'Expected' forever, so it cannot be the default. A job
# skipped by a job-level `if:` is the opposite: the run exists, the check run exists, and
# GitHub counts a skipped job as passing for required status checks. That is the mechanism this
# guard drives.
#
# ------------------------------------------------------------------ THE TRUST CONDITION
# A short-circuit that only asked "is this commit docs-only?" would be a fail-open shape: it
# would report a green lane for the head SHA on the strength of a parent run that may have been
# CANCELLED — which is precisely the failure #542 reports, since a `cancel-in-progress: true`
# keyed bare on the ref lets the verdict push kill the code commit's in-flight run.
#
# So the guard skips ONLY when a COMPLETED, SUCCESSFUL run of the CALLING workflow, for the
# SAME event, exists on the PARENT SHA. Every other answer — cancelled, failed, still running,
# absent, a different workflow, an unreadable diff, an API error, no PR context — resolves to
# `skip=false` and a full run. There is no "assume it was fine" branch, and none may be added:
# the whole value of this guard is that the green it licenses was already earned by the tree it
# is claiming green for.
#
# ------------------------------------------------------------------ REJECTED: the off-branch verdict
# The other way to make this cost vanish is to stop putting the verdict record on the branch —
# `git notes`, a `refs/second-shift/verdicts/<key>` ref, or a check-run annotation. REJECTED
# (#542 AC-3), and this is the header a future maintainer reaching for it should read first:
#
#   * It demotes the verdict from a committed, diffable artifact to a tracker-side record. The
#     record stops appearing in the PR's file list, so it stops being reviewable in place.
#   * The patch-binding invariant — `reviewed_patch_id` recomputed from the branch's own diff,
#     which is what makes "approved" mean "approved THIS tree" — is load-bearing in three
#     places: build milestone 4 (lean-gate.sh), the merge boundary (lean-evidence.sh), and
#     lean-reconcile.sh. All three recompute it against the branch. Moving the record off the
#     branch breaks the "last commit on it" property all three depend on.
#
# The cost being solved here is minutes of runner time. That is not worth trading a committed
# artifact for.
#
# ------------------------------------------------------------------ CONTRACT
# Inputs (environment — second-shift-delta-guard.yml supplies all of them; nothing is
# interpolated into a `run:` line, because a PR body is attacker-controllable):
#   PR_HEAD_SHA        the PR's HEAD COMMIT. Never `HEAD`: on a pull_request event
#                      actions/checkout resolves refs/pull/N/merge, so `HEAD` is
#                      merge(base, head) and its parent is the BASE — every base-side commit
#                      would read as the delta. Empty ⇒ not a PR ⇒ skip=false.
#   GUARD_RUN_ID       ${{ github.run_id }} of the CALLING workflow. Used to resolve which
#                      workflow's green counts as evidence. A reusable workflow shares the
#                      caller's run id, so this resolves the caller — which is the workflow
#                      whose heavy jobs are being skipped, and therefore the only one whose
#                      prior green is relevant.
#   GUARD_EVENT_NAME   ${{ github.event_name }} of the calling run. The parent's run must
#                      match it: the same workflow can run a different job set under `push`
#                      than under `pull_request` (`if: github.event_name == …`), so a green
#                      from the other event is not evidence about this one.
#   GH_TOKEN, GH_REPO  for the Actions API read (needs `actions: read`).
#
# Output: `skip=true` or `skip=false` written to $GITHUB_OUTPUT (and echoed), plus a one-line
# reason on stdout. ALWAYS EXITS 0 — a guard that reds would red the very lane it exists to
# shorten, and its "I don't know" is already expressed as skip=false.
#
# macOS ships /bin/bash 3.2; this script stays 3.2-compatible. No `set -e`: the classification
# has many not-applicable paths and each one must reach the single emit at the bottom.
set -uo pipefail

# The verdict record's filename suffix. Pinned here AND in
# plugins/dev-pipeline/skills/build-lean/lean-evidence.sh, which cannot see this file: this one
# is committed into a CONSUMER repo, that one is fetched at the consumer's pinned marketplace
# ref. A one-sided rename would leave this guard classifying every verdict commit as an ordinary
# one — which costs only runner minutes and reports nothing, so nothing would ever notice.
# Hence the marker: the comment must stay OUTSIDE it, since `verbatim` compares the whole block.
# LOCKSTEP-BEGIN lean-verdict-suffix
LEAN_VERDICT_SUFFIX='-lean-verdict.md'
# LOCKSTEP-END lean-verdict-suffix

SKIP=false
REASON=""

emit() {
  echo "[second-shift-delta-guard] skip=$SKIP — $REASON"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "skip=$SKIP"
      echo "reason=$REASON"
    } >> "$GITHUB_OUTPUT"
  fi
  # A no-skip decision reached because something could not be READ (as opposed to a genuine
  # "this is a normal commit") is surfaced as an annotation. It is not a failure — the lane
  # still runs in full — but it means the guard is inert, and an inert guard that nobody can
  # see is one that stays inert.
  if [ "$SKIP" = false ] && [ -n "${GUARD_UNKNOWN:-}" ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::warning title=second-shift delta guard::$REASON"
  fi
  exit 0
}

decide_no() { REASON="$1"; SKIP=false; emit; }
decide_unknown() { REASON="$1"; SKIP=false; GUARD_UNKNOWN=1; emit; }

# ------------------------------------------------------------------ (1) applicability
[ -n "${PR_HEAD_SHA:-}" ] \
  || decide_no "no PR head SHA in the environment (not a pull_request run) — not applicable"

command -v git >/dev/null 2>&1 || decide_unknown "git is not on the runner — cannot read the delta"

PARENT="$(git rev-parse --verify --quiet "${PR_HEAD_SHA}^" 2>/dev/null)"
[ -n "$PARENT" ] \
  || decide_unknown "cannot resolve the parent of $PR_HEAD_SHA — a root commit, or a checkout too shallow to see it (fetch-depth: 2 is the minimum)"

# ------------------------------------------------------------------ (2) is the delta the verdict record?
# `git diff` is run into a VARIABLE with its own status checked, never `| grep -q`: a failed
# diff piped into a matcher is indistinguishable from a clean non-match, and "the delta is
# unreadable" must never resolve the same way as "the delta is a normal commit".
FILES="$(git diff --name-only "$PARENT" "$PR_HEAD_SHA" 2>/dev/null)" \
  || decide_unknown "git diff $PARENT..$PR_HEAD_SHA failed — an unreadable delta is not a docs-only one"

# EXACTLY ONE PATH, and it must be a verdict record (#542 AC-1). Not "every path is a verdict
# record": a commit carrying two of them is not a shape this lane produces, and falling through
# to a full run is the safe direction for anything unrecognised.
FILE_COUNT="$(grep -c '[^[:space:]]' <<<"$FILES")"
[ "$FILE_COUNT" -eq 1 ] \
  || decide_no "the head commit changes $FILE_COUNT path(s), not exactly one — a mixed or empty delta runs in full"

# The ONE path, read as a line. Never a newline-stripped join of the whole list: that turns a
# two-file delta into one string whose tail is the last path, so `src/app.ts` +
# `docs/x-lean-verdict.md` would match the suffix and skip a delta containing source. The count
# check above already excludes that today — this is the second lock, on the reasoning that the
# count check is the line a future "surely two verdict records are still docs-only" edit relaxes.
CHANGED="$(head -n1 <<<"$FILES")"
case "$CHANGED" in
  *"$LEAN_VERDICT_SUFFIX") : ;;
  *) decide_no "the head commit's one path is '$CHANGED', not a lean verdict record (*$LEAN_VERDICT_SUFFIX) — runs in full" ;;
esac

# ------------------------------------------------------------------ (3) the trust condition (AC-2)
command -v gh >/dev/null 2>&1 \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but gh is not on the runner — the parent's run cannot be verified, so the lane runs in full"
command -v jq >/dev/null 2>&1 \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but jq is not on the runner — the parent's run cannot be verified, so the lane runs in full"
[ -n "${GH_REPO:-}" ] \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but GH_REPO is unset — the parent's run cannot be verified, so the lane runs in full"
[ -n "${GUARD_RUN_ID:-}" ] \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but GUARD_RUN_ID is unset — without the calling workflow's identity, ANY green run on the parent would license the skip. Runs in full"
[ -n "${GUARD_EVENT_NAME:-}" ] \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but GUARD_EVENT_NAME is unset — a green from a different event is not evidence about this one. Runs in full"

# Which workflow's green counts. Resolved from the CALLING run rather than taken as an input:
# a name or a filename passed in could be pointed at a cheap always-green workflow, which is
# the same fail-open with extra steps.
WORKFLOW_ID="$(gh api "repos/$GH_REPO/actions/runs/$GUARD_RUN_ID" --jq '.workflow_id' 2>/dev/null)"
case "$WORKFLOW_ID" in
  ''|*[!0-9]*) decide_unknown "'$CHANGED' is a verdict-record commit, but the calling run ($GUARD_RUN_ID) did not resolve to a workflow id — the parent's run cannot be verified. Runs in full" ;;
esac

RUNS_JSON="$(gh api "repos/$GH_REPO/actions/runs?head_sha=$PARENT&per_page=100" 2>/dev/null)" \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but the Actions API read for parent $PARENT failed (does this workflow grant 'actions: read'?) — runs in full"

# The parent's runs of THIS workflow, for THIS event, as `<status>/<conclusion>` lines. The
# conclusions are reported in the fall-through message: "cancelled" is the #542 hazard and an
# operator needs to see it named rather than inferred from a full re-run.
PARENT_STATES="$(printf '%s' "$RUNS_JSON" | jq -r \
  --argjson wid "$WORKFLOW_ID" --arg ev "$GUARD_EVENT_NAME" '
    (.workflow_runs // [])
    | map(select(.workflow_id == $wid) | select((.event // "") == $ev))
    | map(((.status // "?") + "/" + (.conclusion // "none")))
    | .[]' 2>/dev/null)" \
  || decide_unknown "'$CHANGED' is a verdict-record commit, but the Actions API response for parent $PARENT was unreadable — runs in full"

if grep -qxF 'completed/success' <<<"$PARENT_STATES"; then
  REASON="'$CHANGED' is a lean verdict-record commit and parent $PARENT already has a completed, successful run of this workflow ($GUARD_EVENT_NAME) — heavy jobs skipped"
  SKIP=true
  emit
fi

SEEN="$(printf '%s' "$PARENT_STATES" | tr '\n' ' ')"
[ -n "${SEEN// /}" ] || SEEN="none"
decide_no "'$CHANGED' is a lean verdict-record commit, but parent $PARENT has no completed successful run of this workflow for '$GUARD_EVENT_NAME' (saw: $SEEN) — the code commit's run was cancelled, failed, or never happened, so the lane runs in full"
