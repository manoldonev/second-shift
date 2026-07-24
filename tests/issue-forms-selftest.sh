#!/usr/bin/env bash
# issue-forms-selftest.sh — structural validation of the .github/ISSUE_TEMPLATE
# feedback issue forms (#34). Dependency-free (awk + optional ruby YAML parse):
# GitHub's issue-form SCHEMA is not locally validatable without network, so this
# proves well-formedness + the load-bearing structure (per-field evidence
# enforcement, the doctor --report bundle field), not full schema conformance.
#
# WHAT CHANGED IN #214
#   The old version grepped each form for `required:[[:space:]]*true` and for
#   `--report` ANYWHERE in the file. Both tolerated the realistic regressions:
#   every form carries several `required: true`, so flipping the load-bearing one
#   left the check green; and `--report` survives deletion of the doctor-report
#   FIELD via the intro markdown prose that also mentions it. The nine
#   `^name:`/`^description:`/`^body:` greps were dropped outright — the YAML parse
#   plus GitHub's own loader cover them, and no realistic single-form edit removes
#   a top-level key while leaving parseable YAML.
#
#   The replacement is per-FIELD anchored and per-FORM aware: it extracts each
#   named field's own `required:` value and compares it against an expected table.
#   That table encodes a real design decision — review-false-positive.yml's
#   doctor-report is `required: false` deliberately ("Optional but helpful"), so
#   its evidence contract rests on finding / code-under-dispute / why-fp instead.
#   A blanket "doctor-report must be required" rule would be wrong for that form.
#
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

# Extract ONE field's `required:` value: scan from `id: <field>` to the start of the
# next list item (`- type:`), and report the `required:` found inside that window.
# Anchoring to the field is the whole point — a file-wide grep cannot tell which
# field it matched. Prints "true" | "false" | "" (field absent, or carries no key).
field_required() { # $1 = path, $2 = field id
  awk -v want="$2" '
    /^[[:space:]]*-[[:space:]]*type:/ { inblock = 0 }
    $0 ~ "^[[:space:]]*id:[[:space:]]*" want "[[:space:]]*$" { inblock = 1; next }
    inblock && /^[[:space:]]*required:/ {
      v = $0
      sub(/^[[:space:]]*required:[[:space:]]*/, "", v)
      gsub(/[[:space:]]/, "", v)
      print v
      exit
    }
  ' "$1"
}

# Assert one field's required-ness. BOTH directions are load-bearing: a field that
# must be required going false silently drops evidence enforcement, and a field that
# is deliberately optional going true breaks the reporter's flow.
expect_required() { # $1 = form, $2 = field, $3 = expected true|false
  local got
  got="$(field_required "$TPL/$1.yml" "$2")"
  if [[ -z "$got" ]]; then
    bad "$1: field '$2' not found (or carries no required:) — the evidence contract moved"
  elif [[ "$got" == "$3" ]]; then
    ok "$1: $2 required=$3"
  else
    bad "$1: $2 required=$got, expected $3"
  fi
}

echo "issue-forms selftest:"

# Chooser config.
if [[ -f "$TPL/config.yml" ]]; then
  ok "config.yml present"
  yaml_parses "$TPL/config.yml"
else
  bad "config.yml missing"
fi

FORMS=(pipeline-aborted config-lint-disagreement review-false-positive)
for f in "${FORMS[@]}"; do
  path="$TPL/$f.yml"
  if [[ ! -f "$path" ]]; then bad "$f.yml missing"; continue; fi
  yaml_parses "$path"
done

# Per-form evidence contract. Keeping this table explicit (rather than deriving a rule)
# is deliberate: the asymmetry below IS the contract, and a derived rule would have to
# encode the exception anyway.
expect_required pipeline-aborted          what-happened      true
expect_required pipeline-aborted          state-excerpt      true
expect_required pipeline-aborted          doctor-report      true
expect_required pipeline-aborted          run-ref            false

expect_required config-lint-disagreement  lint-message       true
expect_required config-lint-disagreement  expected           true
expect_required config-lint-disagreement  doctor-report      true

# review-false-positive deliberately makes doctor-report OPTIONAL ("Optional but
# helpful") — the reporter is disputing a finding, not reporting broken tooling.
expect_required review-false-positive     finding            true
expect_required review-false-positive     code-under-dispute true
expect_required review-false-positive     why-fp             true
expect_required review-false-positive     doctor-report      false

# Every form must still OFFER the doctor --report bundle as its own field, whether or
# not it is required. Anchored to the field id, so deleting the field fails even though
# the intro markdown still mentions `--report`.
for f in "${FORMS[@]}"; do
  if [[ -n "$(field_required "$TPL/$f.yml" doctor-report)" ]]; then
    ok "$f: carries a doctor-report field"
  else
    bad "$f: doctor-report field is gone (intro prose mentioning --report does not count)"
  fi
done

if [[ "$FAILS" -gt 0 ]]; then echo "issue-forms selftest: $FAILS FAILURE(S)"; exit "$FAILS"; fi
echo "issue-forms selftest: all green"
