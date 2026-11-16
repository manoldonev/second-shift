#!/usr/bin/env bash
# check-eval-model-identity.sh — no vendor model identity in the RUNNABLE eval surface.
#
# WHY THIS EXISTS. The eval harnesses under `plugins/*/evals/**` ship inside two plugins, so a
# model id checked in there is a vendor id in every consumer's tree (the rule is that
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
# Usage: check-eval-model-identity.sh [root]
#   root defaults to the repo root containing this script. The argument exists so a fixture tree
#   can be scanned — that is how the paired selftest exercises every arm.

set -uo pipefail

# Resolved in two named steps rather than one nested substitution, so a failure to locate
# either has somewhere to be observed: an unresolvable script dir would otherwise silently
# become an empty prefix and the default root would resolve to `/`, turning a no-argument
# invocation into a whole-filesystem scan.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "[check-eval-model-identity] could not resolve this script's own directory." >&2
  exit 2
fi
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${1:-$DEFAULT_ROOT}"

if [[ ! -d "$ROOT" ]]; then
  echo "[check-eval-model-identity] not a directory: '$ROOT'" >&2
  exit 2
fi

# The record set, by name: a file with one of these names anywhere in the eval surface is a
# landed record of a run, not runnable machinery.
RECORD_FILES=(
  changelog.md
  BASELINE.md
)

# (1) versioned vendor pin.
PIN_RE='claude-[a-z]+-[0-9][a-z0-9.-]*'

# (2) floating alias in a model position. Single-quoted template with an @A@ placeholder so the
#     end-of-line anchors stay literal `$` regardless of how the shell would read them.
ALIASES='opus|sonnet|haiku|fable'
POS_RE_TMPL='(--[a-z-]*model[=[:space:]]+["'\'']?(@A@)(["'\''[:space:]]|$)|"model"[[:space:]]*:[[:space:]]*"(@A@)"|[A-Z_]*MODEL=["'\'']?(@A@)(["'\''[:space:]]|$))'
POS_RE="${POS_RE_TMPL//@A@/$ALIASES}"

# Inside a git work tree the scan set is tracked and untracked-unignored files only, so a
# gitignored in-tree worktree's stale copies are not scanned. A fixture root that is not a git
# repo keeps `find`. Either way an untracked runner output is still excluded by name.
list_candidates() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$ROOT" && git ls-files -z -co --exclude-standard) |
      while IFS= read -r -d '' r; do printf '%s/%s\n' "$ROOT" "$r"; done
  else
    find "$ROOT" -type d -name '__pycache__' -prune -o -path '*/evals/*' -type f -print 2>/dev/null
  fi
}

is_excluded_name() {
  local base="${1##*/}" r
  case "$base" in results-*.json) return 0 ;; esac
  for r in "${RECORD_FILES[@]}"; do
    [[ "$base" == "$r" ]] && return 0
  done
  return 1
}

files=()
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  case "$f" in */__pycache__/*) continue ;; */evals/*) ;; *) continue ;; esac
  is_excluded_name "$f" && continue
  files+=("$f")
done < <(list_candidates | LC_ALL=C sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[check-eval-model-identity] scanned 0 files under $ROOT — nothing matches */evals/*." >&2
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
    echo "[check-eval-model-identity] $violations vendor model reference(s) in the runnable eval surface under $ROOT."
    echo "  Model identity belongs to the operator, not to this repo. Read it from the environment"
    echo "  (REVIEWER_MODEL / JUDGE_MODEL) and let the runner refuse a missing value — see"
    echo "  plugins/review-toolkit/evals/code-review-bench-eval/README.md."
    echo "  If the file is a landed RECORD of a run rather than machinery, its name belongs in this"
    echo "  guard's RECORD_FILES list, with the reason."
  } >&2
  exit 1
fi

echo "[check-eval-model-identity] ✓ ${#files[@]} runnable eval file(s) carry no vendor model identity."
