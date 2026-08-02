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
# applicable PR unless all three artifacts exist:
#   1. a committed lean spec carrying >= 1 numbered AC-n (the definition of done),
#   2. a committed verdict record reading `verdict=approve` (so a hand-typed local progress
#      line cannot reach a merge — only a committed, diffable artifact can),
#   3. a bot-authored `lean-claimed` comment on the linked issue, windowed at PR-open.
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
#   PR_BASE_REF             required for the live diff  the PR's base branch
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
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
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

if [[ -z "$VERDICT" ]]; then
  note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX). The independent review's verdict must be a committed, diffable artifact — a local progress-file line is not evidence."
else
  approve_count="$(grep -cF 'verdict=approve' "$REPO_ROOT/$VERDICT" 2>/dev/null)" || approve_count=0
  if [[ "${approve_count:-0}" -lt 1 ]]; then
    note_violation "verdict record '$VERDICT' does not read 'verdict=approve'."
  else
    echo "[lean-chain]   ✓ verdict record: $VERDICT (verdict=approve)"
  fi
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
CLAIMED="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" '
  [ .[]
    | select((.user.type // "") == "Bot")
    | select($author == "" or (.user.login // "") == $author)
    | select((.created_at // "") != "" and .created_at <= $at)
    | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*lean-claimed[[:space:]]*-->"))
  ] | length')"

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

# ---- (8) verdict ------------------------------------------------------------------------
if [[ "$violations" -gt 0 ]]; then
  echo "[lean-chain] ✗ $violations evidence artifact(s) missing for lean PR on #$KEY." >&2
  echo "[lean-chain]   The remedy is producing the missing artifact — there is no waiver." >&2
  exit 1
fi

echo "[lean-chain] lean evidence complete for #$KEY (spec + approve-verdict + claim)."
