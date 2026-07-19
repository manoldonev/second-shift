#!/usr/bin/env bash
# check-workflows-selftest.sh — every .github/workflows/*.yml must parse as YAML (#119).
#
# WHY THIS EXISTS: a workflow file with a YAML syntax error is rejected by GitHub with
# "Invalid workflow file" and simply does not run — so a broken ci.yml cannot be caught by
# a step inside ci.yml. It has to fail LOCALLY, before the push. This selftest is that gate.
#
# The bug that motivated it: an unquoted step name containing a colon-space —
#   - name: changelog trailer guard (plugins/** PRs carry Changelog:/Changelog: none)
# YAML reads the inner ': ' as a nested mapping and rejects the file. Quoting fixes it, and
# this parse catches the whole class.
#
# Deeper semantic checks (invalid `if:` expressions, unknown contexts, shellcheck over
# `run:` blocks) are actionlint's job and run in CI; this is the syntax floor that must hold
# on the maintainer's machine.
#
# No parser available is a FAILURE, never a skip: a silently-skipped gate is a false green
# (the lesson from the mis-shaped-setup-lane fix). Runs under the repo's *-selftest.sh loop.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

WORKFLOW_DIR=".github/workflows"
if [[ ! -d "$WORKFLOW_DIR" ]]; then
  echo "check-workflows-selftest: no $WORKFLOW_DIR — nothing to check. PASS."
  exit 0
fi

# Resolve a YAML parser once. Prefer ruby (ships on macOS and GitHub runners); fall back to
# python3 + PyYAML. Neither ⇒ fail loudly with the install hint.
PARSER=""
if ruby -ryaml -e '' >/dev/null 2>&1; then
  PARSER="ruby"
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  PARSER="python"
else
  echo "check-workflows-selftest: FAIL — no YAML parser available (tried: ruby -ryaml, python3 + PyYAML)." >&2
  echo "  Install one: 'brew install ruby' or 'python3 -m pip install pyyaml'." >&2
  echo "  This gate fails rather than skips: a workflow YAML error is invisible in CI (GitHub" >&2
  echo "  refuses to run the broken file), so an unchecked workflow is a false green." >&2
  exit 1
fi

parse_yaml() { # parse_yaml <file> -> 0 ok, non-zero + stderr on syntax error
  case "$PARSER" in
    ruby)   ruby -ryaml -e 'YAML.unsafe_load_file(ARGV[0]) rescue YAML.load_file(ARGV[0])' "$1" ;;
    python) python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1" ;;
  esac
}

PASS=0
FAIL=0
for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [[ -f "$wf" ]] || continue
  if err="$(parse_yaml "$wf" 2>&1)"; then
    echo "  ok: $wf"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $wf" >&2
    echo "$err" | head -5 >&2
    FAIL=$((FAIL + 1))
  fi
done

if [[ "$PASS" -eq 0 && "$FAIL" -eq 0 ]]; then
  echo "check-workflows-selftest: no workflow files found. PASS."
  exit 0
fi

echo "check-workflows-selftest ($PARSER): $PASS ok, $FAIL failed"
exit "$FAIL"
