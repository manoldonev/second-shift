#!/usr/bin/env bash
#
# Gate 1 smoke: fake-gh shim + new fixture loader.
# No Claude CLI invocation. Pure local validation, cost $0.
#
# Passes if:
#   - fake-gh returns expected responses / logs every mutation
#   - the harness's new fixture loader discovers all 10 fixture directories
#
# Fails fast on the first mismatch.

set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SMOKE_DIR="$(cd "$(dirname "$0")" && pwd)"
# The shared agent-eval-kit lives in the review-toolkit plugin (sibling under plugins/).
KIT="$(cd "$SMOKE_DIR/../../../../review-toolkit/evals/agent-eval-kit" && pwd)"
FIXTURES="$REPO/docs/eval-fixtures/intake-orchestrator"

echo "=== Gate 1: shim + loader ==="

# --- Part A: fake-gh shim ---
echo
echo "[A] fake-gh shim: exercise every command variant"

TMPDIR="$(mktemp -d -t gate1-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# Seed a minimal issue-view.json for the shim to return on `issue view`
cat > "$TMPDIR/issue-view.json" <<EOF
{"body": "stub body", "comments": [], "labels": [], "number": 1, "state": "OPEN", "title": "stub"}
EOF

export GH_MOCK_DIR="$TMPDIR"
export GH_MOCK_LOGS="$TMPDIR/writes.log"
: > "$GH_MOCK_LOGS"

# 1. gh auth status -> exit 0, no log write
"$KIT/fake-gh" auth status > /dev/null
if [ -s "$GH_MOCK_LOGS" ]; then
  echo "FAIL: gh auth status wrote to writes.log"; exit 1
fi

# 2. gh issue view 1 -> returns issue-view.json body
OUT="$("$KIT/fake-gh" issue view 1 --json body,comments,labels)"
if ! echo "$OUT" | grep -q '"body"'; then
  echo "FAIL: gh issue view did not echo issue-view.json"; echo "$OUT"; exit 1
fi

# 3. gh issue create -> logs
"$KIT/fake-gh" issue create --title t --body b --label ready-for-dev > /dev/null
if ! grep -q "issue create" "$GH_MOCK_LOGS"; then
  echo "FAIL: gh issue create was not logged"; exit 1
fi

# 4. gh issue edit -> logs
"$KIT/fake-gh" issue edit 1 --add-label epic --remove-assignee @me > /dev/null
if ! grep -q "issue edit" "$GH_MOCK_LOGS"; then
  echo "FAIL: gh issue edit was not logged"; exit 1
fi

# 5. gh issue comment -> logs
"$KIT/fake-gh" issue comment 1 --body "hello" > /dev/null
if ! grep -q "issue comment" "$GH_MOCK_LOGS"; then
  echo "FAIL: gh issue comment was not logged"; exit 1
fi

# 6. gh api repos/foo/bar -> returns empty object when no file
OUT="$("$KIT/fake-gh" api repos/foo/bar)"
if [ "$OUT" != "{}" ]; then
  echo "FAIL: gh api returned non-{} when no canned file present: $OUT"; exit 1
fi

echo "    OK — shim handles auth/view/create/edit/comment/api"
echo "    writes.log contents:"
sed 's/^/      /' "$GH_MOCK_LOGS"

# --- Part B: fixture loader ---
echo
echo "[B] fixture loader: discover all 10 intake fixtures"

python3 - "$FIXTURES" "$KIT" <<'PY'
import sys
from pathlib import Path
kit_dir = Path(sys.argv[2])
sys.path.insert(0, str(kit_dir))
# Import run_eval as a module
import importlib.util
runner = kit_dir / "run-eval.py"
spec = importlib.util.spec_from_file_location("run_eval", runner)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

fixtures_dir = Path(sys.argv[1])
repo_root = fixtures_dir.parents[1]
fixtures = m.load_fixtures(fixtures_dir, repo_root)

expected = {
    "01-clean-bug-fix", "02-clean-chore-config", "03-small-feature-atomic",
    "04-mid-feature-parallel", "05-large-feature-stacked",
    "06-subagent-false-positive", "07-threshold-breach-subissues",
    "08-threshold-breach-blockers", "09-resume-guard-stacked",
    "10-rewrite-mislabeled-bug",
}
got = {f["name"] for f in fixtures}
assert got == expected, f"Missing: {expected - got}; Extra: {got - expected}"

# Each fixture must have: content, expected, mocks (3 canned_* keys), mock_env_dir
required_mock_keys = {"canned_spec_review", "canned_codebase_explorer", "canned_dependency_analyzer"}
for f in fixtures:
    assert f["content"], f"{f['name']}: empty content"
    assert f["expected"], f"{f['name']}: empty expected"
    assert f["mock_env_dir"] and f["mock_env_dir"].is_dir(), f"{f['name']}: missing mock-env/"
    assert required_mock_keys.issubset(f["mocks"].keys()), (
        f"{f['name']}: mocks missing keys. Got {sorted(f['mocks'].keys())}"
    )
    # mock-env/issue-view.json must exist
    iv = f["mock_env_dir"] / "issue-view.json"
    assert iv.is_file(), f"{f['name']}: missing mock-env/issue-view.json"

print(f"    OK — all {len(fixtures)} fixtures loaded with mocks + mock-env")
PY

echo
echo "=== Gate 1 PASS ==="
