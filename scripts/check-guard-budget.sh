#!/usr/bin/env bash
# check-guard-budget.sh — PR-time guard: guard/test shell mass must not grow without a stated
# reason (#641, Phase 0 of the 2026-08-22 backlog recalibration).
#
# docs/pipeline-manifesto.md's P2/P3 gate every growth principle mechanically; P4/P5 ("as much
# as it takes, and none more" / "every word earns its place") do not, by the document's own
# admission. This is P4/P5's mechanical counterpart.
#
# DERIVED, NOT STORED (#641 supersedes PR #645's committed-ceiling design). No tools/*.tsv.
# This script measures guard/test mass twice — once at the PR's merge-base, once at HEAD — and
# compares the two numbers it just took. A stored ceiling needs an update path; the update path
# needs either an unsupervised write to main or an operator ritual, and both were the source of
# every finding PR #645 collected. Deriving both sides deletes the need for either.
#
# THE CLASSIFICATION (PR #645's predicate, kept behaviorally identical). A .sh file counts as
# guard/test when its basename matches `*-selftest.sh`, `check-*.sh` or `*-lint.sh`, or it is a
# lean-gate.sh (`*/skills/*/lean-gate.sh`), or one of the named standing-guard entry points:
# run-selftests.sh, mutation-sweep.sh, gate-ablation.sh — is_guard_path() below, called by BOTH
# classify_worktree() (files on disk) and classify_ref() (a git ref's tree, never checked out),
# so there is one arm list, not two hand-kept ones a fixture could exercise on only one side.
#
# THE ESCAPE HATCH IS A COMMIT TRAILER, NOT A FILE EDIT: a PR whose guard mass increases reds
# unless a commit on the branch carries a `Guard-mass:` trailer, the same extracted grep-anywhere
# mechanism scripts/check-changelog-trailer.sh already establishes (so it survives the squash).
# This script does not parse or validate the stated delta/reason, same as that one does not
# validate changelog prose.
#
# Usage: check-guard-budget.sh <base-ref>   (e.g. origin/main)
# Exit 0 = mass unchanged/decreased, or increased with a Guard-mass: trailer;
#      1 = increased with no trailer;
#      2 = usage/environment error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:?usage: check-guard-budget.sh <base-ref>}"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "[guard-budget] cannot resolve merge-base of $BASE and HEAD" >&2; exit 2; }

is_guard_path() { # is_guard_path <repo-relative-.sh-path> — rc=0 iff it counts as guard/test mass
  case "$1" in */skills/*/lean-gate.sh) return 0 ;; esac
  case "${1##*/}" in
    *-selftest.sh|check-*.sh|*-lint.sh|run-selftests.sh|mutation-sweep.sh|gate-ablation.sh) return 0 ;;
  esac
  return 1
}

classify_worktree() { # classify_worktree <root> — every guard/test .sh path under root, one per line
  find "$1" -type f -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null \
    | while IFS= read -r p; do is_guard_path "$p" && printf '%s\n' "$p"; done
}

classify_ref() { # classify_ref <ref> — same predicate, evaluated over `git ls-tree`, no checkout
  git ls-tree -r --name-only "$1" -- . 2>/dev/null | while IFS= read -r p; do
    case "$p" in */node_modules/*) continue ;; esac
    is_guard_path "$p" && printf '%s\n' "$p"
  done
}

measure_worktree() { # measure_worktree <root> — total line count across classify_worktree()'s files
  classify_worktree "$1" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l | tr -d ' '
}

measure_ref() { # measure_ref <ref> — total line count across classify_ref()'s files, read from git
  local ref="$1" total=0 p n
  while IFS= read -r p; do
    n="$(git show "$ref:$p" 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + n))
  done < <(classify_ref "$ref")
  printf '%s' "$total"
}

BASE_MASS="$(measure_ref "$MERGE_BASE")"
HEAD_MASS="$(measure_worktree .)"
DELTA=$((HEAD_MASS - BASE_MASS))

if [ "$DELTA" -le 0 ]; then
  echo "[guard-budget] ✓ guard/test shell mass: base $BASE_MASS, HEAD $HEAD_MASS (delta $DELTA)."
  exit 0
fi

# grep -c, NOT -q: -q exits at the first match, git log takes SIGPIPE, and pipefail turns that
# into a false negative — the shape check-changelog-trailer.sh's header already guards against.
if git log "$MERGE_BASE..HEAD" --format=%B | grep -cE '^Guard-mass:' >/dev/null; then
  echo "[guard-budget] ✓ guard/test shell mass: base $BASE_MASS, HEAD $HEAD_MASS (delta +$DELTA), covered by a 'Guard-mass:' trailer."
  exit 0
fi

echo "[guard-budget] ✗ guard/test shell mass grew by $DELTA lines with no reason recorded: base $BASE_MASS ($MERGE_BASE), HEAD $HEAD_MASS." >&2
echo "[guard-budget]   Delete guard mass elsewhere, or amend the commit that added it (git commit --amend) with:" >&2
echo "[guard-budget]     Guard-mass: +$DELTA <reason>" >&2
exit 1
