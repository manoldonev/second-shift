#!/usr/bin/env bash
# check-eval-model-neutrality.sh — no vendor model identity in the RUNNABLE eval surface.
#
# WHY THIS EXISTS. The eval harnesses under `plugins/*/evals/**` ship inside two plugins, so a
# model id checked in there is a vendor id in every consumer's tree (epic #350 asks that
# concrete backend targets stay with the operator). It is also an evidence defect: the runner's
# `changelog.md` records `model=<reviewer_model>` as the key two eval rows are compared on, so a
# default supplied by the repo attributes a score to whatever constant happened to be in the file
# that day, and a floating dispatch alias attributes it to something that no longer means the
# same thing a generation later.
#
# WHAT COUNTS AS A VIOLATION. Two forms, both narrow enough that prose cannot trip them:
#
#   (1) a VERSIONED VENDOR PIN — `claude-<family>-<digits>…`. Unambiguous: no English sentence
#       contains it by accident, so this one needs no position analysis.
#   (2) a FLOATING ALIAS IN A MODEL POSITION — one of `opus`/`sonnet`/`haiku`/`fable` as the value
#       of a `--…model` flag, a JSON `"model":` key, or a `*MODEL=` assignment. The position
#       requirement is what keeps "downgrading from Opus to Sonnet" in a README, or a note string
#       like `sonnet-ab`, from reading as a violation.
#
# WHAT IS EXEMPT, AND WHY. The historical record files — a run's `changelog.md` and the landed
# baseline reports beside it — name the model that PRODUCED a score. Neutralizing them would
# destroy the attribution the pins exist for, so they are excluded by name. The runner's own
# `results-*.json` output is excluded for the same reason (and is gitignored anyway);
# `__pycache__` is pruned because it is compiled bytecode.
#
# ZERO FILES IS A FAILURE. A guard that scans nothing reports green, and this surface is exactly
# the kind that gets relocated — it moved out of a consumer's `pipeline-state/` once already. An
# empty scan set means the root is wrong or the surface moved; either way the answer is not
# "clean".
#
# Usage: check-eval-model-neutrality.sh [root]
#   root defaults to the repo root containing this script. The argument exists so a fixture tree
#   can be scanned — that is how the paired selftest exercises every arm.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ ! -d "$ROOT" ]]; then
  echo "[check-eval-model-neutrality] not a directory: $ROOT" >&2
  exit 2
fi

# The record set, by name: a file with one of these names anywhere in the eval surface is a
# landed record of a run, not runnable machinery.
RECORD_FILES=(
  changelog.md
  FINAL-REPORT.md
  CLOSEOUT-BASELINE.md
  BASELINE.md
  KNOWN_ISSUES.md
  FIXTURE-AUDIT.md
)

# (1) versioned vendor pin.
PIN_RE='claude-[a-z]+-[0-9][a-z0-9.-]*'

# (2) floating alias in a model position. Single-quoted template with an @A@ placeholder so the
#     end-of-line anchors stay literal `$` regardless of how the shell would read them.
ALIASES='opus|sonnet|haiku|fable'
POS_RE_TMPL='(--[a-z-]*model[=[:space:]]+["'\'']?(@A@)(["'\''[:space:]]|$)|"model"[[:space:]]*:[[:space:]]*"(@A@)"|[A-Z_]*MODEL=["'\'']?(@A@)(["'\''[:space:]]|$))'
POS_RE="${POS_RE_TMPL//@A@/$ALIASES}"

# Build the scan set with `find`, not `git ls-files`: the root may be a fixture tree that is not
# a git repo, and an untracked runner output must still be excluded by name.
exclusions=(-name 'results-*.json')
for r in "${RECORD_FILES[@]}"; do
  exclusions+=(-o -name "$r")
done

files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && files+=("$f")
done < <(
  find "$ROOT" \
    -type d -name '__pycache__' -prune -o \
    -path '*/evals/*' -type f ! \( "${exclusions[@]}" \) -print 2>/dev/null |
    LC_ALL=C sort
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[check-eval-model-neutrality] scanned 0 files under $ROOT — nothing matches */evals/*." >&2
  echo "  The eval surface moved, or this root is wrong. Refusing to report a pass on an empty scan set." >&2
  exit 2
fi

violations=0

for f in "${files[@]}"; do
  rel="${f#"$ROOT"/}"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    echo "  $rel:$hit  ← versioned vendor model pin" >&2
    violations=$((violations + 1))
  done < <(grep -inoE "$PIN_RE" "$f" 2>/dev/null)
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    echo "  $rel:$hit  ← floating dispatch alias in a model position" >&2
    violations=$((violations + 1))
  done < <(grep -inoE "$POS_RE" "$f" 2>/dev/null)
done

if [[ $violations -gt 0 ]]; then
  {
    echo
    echo "[check-eval-model-neutrality] $violations vendor model reference(s) in the runnable eval surface under $ROOT."
    echo "  Model identity belongs to the operator, not to this repo. Read it from the environment"
    echo "  (REVIEWER_MODEL / JUDGE_MODEL / MOCK_MODEL) and let the runner refuse a missing or"
    echo "  floating value — see plugins/review-toolkit/evals/agent-eval-kit/README.md."
    echo "  If the file is a landed RECORD of a run rather than machinery, its name belongs in this"
    echo "  guard's RECORD_FILES list, with the reason."
  } >&2
  exit 1
fi

echo "[check-eval-model-neutrality] ✓ ${#files[@]} runnable eval file(s) carry no vendor model identity."
