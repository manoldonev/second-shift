#!/usr/bin/env bash
#
# Self-test for the reviewer diff-range semantics (#130).
#
# THE BUG: the reviewer-dispatching Workflow scripts rendered a TWO-dot range
# (`<base>..<head>`) into every reviewer prompt. When the caller passed a branch
# name whose tip had advanced past the review branch's merge-base, two-dot renders
# the base branch's newer commits as DELETIONS in the branch under review — and
# reviewers duly report the branch as reverting work it never touched. Observed on
# PR #125: two confidently-argued BLOCKER findings, both false.
#
# THE FIX: render THREE-dot (`<base>...<head>`), which is merge-base semantics by
# definition (git diffs from merge-base(base,head) to head). Workflow scripts have
# no Bash or filesystem access, so they cannot compute a merge-base themselves —
# three-dot delegates that resolution to git at reviewer-run time.
#
# This test has two halves:
#   (A/B) BEHAVIORAL — a real throwaway git fixture proving three-dot excludes
#         base-only commits and that an explicit merge-base SHA is unaffected.
#         Case A also asserts the fixture STILL REPRODUCES under two-dot: a fixture
#         that cannot fail the old way would silently stop testing anything.
#   (C-G) DRIFT GUARDS — token assertions over the production scripts. These are
#         grep-shaped because Workflow scripts run inside the Workflow runtime
#         (injected globals, top-level `return`), so they can be neither executed
#         nor `node --check`ed here — the same technique null-reviewer-selftest.mjs
#         and intake-readroot-selftest.sh use.
#
# All guard greps are FIXED-STRING (`grep -F`): the tokens are punctuation-dense
# (`$`, `{`, `}`, `.`) and a regex-mode `.` would match any character.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")"                    # skills/run
WORKFLOWS="$RUN_DIR/workflows"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

echo "diff-range-selftest: reviewer diff-range semantics (#130)"

# ---------------------------------------------------------------------------
# Behavioral half — a real git fixture with an AHEAD base branch.
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "  SKIP: git not invokable — behavioral cases (A/B) skipped"
else
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX"' EXIT

  (
    cd "$FIX" || exit 1
    git init -q .
    git config user.email "selftest@example.invalid"
    git config user.name "selftest"
    git config commit.gpgsign false

    echo root > root.txt
    git add root.txt && git commit -qm "root"

    # The review branch: one commit touching feature.txt.
    git checkout -qb review
    echo feature > feature.txt
    git add feature.txt && git commit -qm "branch work"

    # The base branch MOVES AHEAD after the branch point — the condition that
    # triggers the bug. It touches a file the review branch never saw.
    git checkout -q master 2>/dev/null || git checkout -q main
    echo unrelated > unrelated.txt
    git add unrelated.txt && git commit -qm "base advanced after branch point"
  ) || { bad "could not build the git fixture"; }

  BASE_BRANCH="$(git -C "$FIX" rev-parse --abbrev-ref HEAD)"

  # --- Case A (AC-1): three-dot excludes base-only commits -------------------
  THREE="$(git -C "$FIX" diff --name-only "${BASE_BRANCH}...review")"
  TWO="$(git -C "$FIX" diff --name-only "${BASE_BRANCH}..review")"

  if [[ "$THREE" == "feature.txt" ]]; then
    ok "A three-dot range yields ONLY the review branch's own file (feature.txt)"
  else
    bad "A three-dot range yielded '$THREE' (expected exactly 'feature.txt')"
  fi

  # The fixture must still reproduce the ORIGINAL bug under two-dot. If this ever
  # stops holding, the fixture has drifted and Case A above proves nothing.
  if grep -qx 'unrelated.txt' <<<"$TWO"; then
    ok "A two-dot range still leaks the base-only file (fixture reproduces the bug)"
  else
    bad "A two-dot range did NOT leak unrelated.txt — fixture no longer reproduces #130, so the three-dot assertion is vacuous"
  fi

  # --- Case B (AC-2): an explicit merge-base SHA is unaffected ---------------
  MB="$(git -C "$FIX" merge-base "$BASE_BRANCH" review)"
  MB_THREE="$(git -C "$FIX" diff --name-only "${MB}...review")"
  MB_TWO="$(git -C "$FIX" diff --name-only "${MB}..review")"

  if [[ "$MB_THREE" == "$MB_TWO" ]]; then
    ok "B explicit merge-base SHA: three-dot == two-dot (no regression for correct callers)"
  else
    bad "B explicit merge-base SHA diverged: three-dot='$MB_THREE' vs two-dot='$MB_TWO'"
  fi
fi

# ---------------------------------------------------------------------------
# Drift-guard half — the production scripts must carry three-dot and NO two-dot.
#
# Scoped to exactly these four files. The eval probes (stall-probe.mjs,
# tool-discipline-probe.mjs) intentionally KEEP two-dot: their base defaults are
# `<sha>^` against `<sha>`, where merge-base(X^,X) == X^ makes the two forms
# identical, and they are held byte-stable for cross-run comparability. A
# repo-wide assertion would therefore be wrong.
# ---------------------------------------------------------------------------
# NO surrounding backticks in these tokens. The range appears in two syntactic
# shapes: a const assignment (`const range = `${base}...${head}``) and an inline
# log interpolation (` (${base}...${head})`). An earlier version of this guard
# required backticks and so matched only the const form — a two-dot log line
# survived the check, which is precisely the partial-fix case this test exists to
# catch. Match the interpolation itself, not its delimiters.
#
# Note `${base}..${head}` is NOT a substring of `${base}...${head}`: after `${base}`
# the two-dot token needs `..${head}`, but the three-dot form supplies `...${head}`,
# so the third dot blocks the match. The absence assertion is therefore sound.
# shellcheck disable=SC2016  # single quotes are REQUIRED: these are literal JS
# source tokens to grep for, not shell expansions. Expanding them would search for
# the empty string and make every guard below vacuously pass.
THREE_DOT='${base}...${head}'
# shellcheck disable=SC2016  # literal token, see above
TWO_DOT='${base}..${head}'
# shellcheck disable=SC2016  # literal token, see above (used by Case G)
HEAD_TOKEN='${head}'

for f in code-review.mjs design-sync.mjs unit-tests.mjs mutation-gate.mjs; do
  path="$WORKFLOWS/$f"
  if [[ ! -f "$path" ]]; then
    bad "C-F $f is missing at $path"
    continue
  fi
  # Presence: mutation-gate.mjs renders the range only in a log line, so match the
  # three-dot interpolation rather than a `const range =` assignment.
  if grep -qF "$THREE_DOT" "$path"; then
    ok "C-F $f renders a three-dot range"
  else
    bad "C-F $f lost the three-dot range — #130 regression"
  fi
  # Absence: the zero-occurrence form is what catches a PARTIAL fix. unit-tests.mjs
  # carries two range sites (a log line and the const); a presence-only check would
  # happily pass with one of them still two-dot.
  if grep -qF "$TWO_DOT" "$path"; then
    bad "C-F $f still contains a two-dot ${TWO_DOT} range — #130 regression (check every site, not just the first)"
  else
    ok "C-F $f contains no two-dot base..head range"
  fi
done

# --- Case G (AC-5): plan-review.mjs is confirmed range-free ------------------
# AC-5 names plan-review.mjs as an audit target. It constructs no diff range at
# all, so it needs no fix — but that "confirmed unaffected" verdict is re-checked
# mechanically here rather than trusted to a plan's prose.
PLAN_REVIEW="$WORKFLOWS/plan-review.mjs"
if [[ ! -f "$PLAN_REVIEW" ]]; then
  bad "G plan-review.mjs is missing at $PLAN_REVIEW"
elif grep -qF "$HEAD_TOKEN" "$PLAN_REVIEW"; then
  bad "G plan-review.mjs now interpolates a head ref — it gained a diff range and must be audited for #130"
else
  ok "G plan-review.mjs still constructs no diff range (confirmed unaffected)"
fi

# --- Case H: the null-reviewer drift guard pins the three-dot token ----------
NULL_SELFTEST="$WORKFLOWS/null-reviewer-selftest.mjs"
if [[ -f "$NULL_SELFTEST" ]] && grep -qF "$THREE_DOT" "$NULL_SELFTEST"; then
  ok "H null-reviewer-selftest.mjs pins the three-dot token in its drift guard"
else
  bad "H null-reviewer-selftest.mjs no longer pins the three-dot token (${THREE_DOT})"
fi

echo "diff-range-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
