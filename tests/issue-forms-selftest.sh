#!/usr/bin/env bash
# issue-forms-selftest.sh — structural validation of the .github/ISSUE_TEMPLATE
# feedback issue forms (#34). Dependency-free (grep + optional ruby YAML parse):
# GitHub's issue-form SCHEMA is not locally validatable without network, so this
# proves well-formedness + the load-bearing structure (required evidence fields,
# the --report bundle field), not full schema conformance.
# Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TPL="$ROOT/.github/ISSUE_TEMPLATE"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

yaml_parses() { # $1 = path — parse via ruby when present, else skip (not a failure)
  if command -v ruby >/dev/null 2>&1; then
    if ruby -ryaml -e "YAML.load_file(ARGV[0])" "$1" 2>/dev/null; then ok "$(basename "$1"): YAML parses"
    else bad "$(basename "$1"): YAML parse error"; fi
  else
    ok "$(basename "$1"): YAML parse skipped (ruby absent)"
  fi
}

FORMS=(pipeline-aborted config-lint-disagreement review-false-positive)

echo "issue-forms selftest:"

# Chooser config (warning #1 from plan review — give config.yml coverage too).
if [[ -f "$TPL/config.yml" ]]; then ok "config.yml present"; yaml_parses "$TPL/config.yml"
else bad "config.yml missing"; fi

for f in "${FORMS[@]}"; do
  path="$TPL/$f.yml"
  if [[ ! -f "$path" ]]; then bad "$f.yml missing"; continue; fi
  yaml_parses "$path"
  # required top-level issue-form keys
  for key in name description body; do
    grep -qE "^${key}:" "$path" && ok "$f: has $key:" || bad "$f: missing top-level $key:"
  done
  # issue forms must ENFORCE evidence — at least one required field
  grep -qE "required:[[:space:]]*true" "$path" \
    && ok "$f: marks a field required" \
    || bad "$f: no 'required: true' field (a Markdown template can't enforce; this must be a form)"
  # the shared --report evidence field
  grep -qiE "doctor --report|--report" "$path" \
    && ok "$f: references the doctor --report bundle" \
    || bad "$f: missing the --report evidence field"
done

if [[ "$FAILS" -gt 0 ]]; then echo "issue-forms selftest: $FAILS FAILURE(S)"; exit "$FAILS"; fi
echo "issue-forms selftest: all green"
