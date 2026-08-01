#!/usr/bin/env bash
# issue-forms-selftest.sh — structural validation of the .github/ISSUE_TEMPLATE
# feedback issue forms (#34). CI (.github/workflows/ci.yml, #299) validates the same forms
# against GitHub's real issue-forms/issue-config JSON Schema via check-jsonschema, which
# catches an illegal `type:`, a misplaced key, a bad `render:` language, or a malformed
# `id`. This selftest owns what that schema structurally cannot: `id` uniqueness (the
# schema's `uniqueItems` applies only to dropdown `options`) and `render:` co-occurring
# with `validations.required: true` (the schema has no `not` keyword) — plus the
# load-bearing per-field evidence table below, which is a design decision no schema knows.
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
# WHAT CHANGED IN #299
#   FORMS is now discovered by globbing .github/ISSUE_TEMPLATE/*.yml minus config.yml
#   (previously a hardcoded list), so a new form is covered on arrival with no selftest
#   edit — id uniqueness, render+required, YAML-parses, and doctor-report-field-present all
#   run against it automatically. The per-field expect_required table stays hardcoded to
#   the three known forms; that table is a per-form design decision, not a generalizable
#   rule. The YAML-parser resolution (ruby -> python3+PyYAML) now hard-FAILs when neither is
#   available, mirroring scripts/check-workflows-selftest.sh:29-42 — this was previously the
#   one YAML gate in the tree that reported absent-ruby as a PASS ("YAML parse skipped"),
#   which is a false green.
#
# Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TPL="$ROOT/.github/ISSUE_TEMPLATE"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

# Resolve a YAML parser once. Prefer ruby (ships on macOS and GitHub runners); fall back to
# python3 + PyYAML. Neither ⇒ FAIL loudly rather than skip — a silently-skipped gate is a
# false green.
PARSER=""
if ruby -ryaml -e '' >/dev/null 2>&1; then
  PARSER="ruby"
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  PARSER="python"
else
  echo "issue-forms-selftest: FAIL — no YAML parser available (tried: ruby -ryaml, python3 + PyYAML)." >&2
  echo "  Install one: 'brew install ruby' or 'python3 -m pip install pyyaml'." >&2
  exit 1
fi

yaml_parses() { # $1 = path
  local err
  case "$PARSER" in
    ruby)
      if err="$(ruby -ryaml -e "YAML.load_file(ARGV[0])" "$1" 2>&1)"; then ok "$(basename "$1"): YAML parses"
      else bad "$(basename "$1"): YAML parse error"; fi
      ;;
    python)
      if err="$(python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1" 2>&1)"; then ok "$(basename "$1"): YAML parses"
      else bad "$(basename "$1"): YAML parse error"; fi
      ;;
  esac
}

# Scan one form's body items in order and emit "<id>\t<has_render>\t<required>" per
# top-level `- type:` block (markdown blocks carry no id, so their first field is empty).
# Anchored to block boundaries, same idiom as field_required below, so a value from one
# field is never attributed to its neighbor.
extract_blocks() { # $1 = path
  awk '
    function flush() { if (started) printf "%s\t%s\t%s\n", id, hasrender, required }
    /^[[:space:]]*-[[:space:]]*type:/ { flush(); started = 1; id = ""; hasrender = "0"; required = ""; next }
    started && $0 ~ "^[[:space:]]*id:[[:space:]]*" {
      v = $0; sub(/^[[:space:]]*id:[[:space:]]*/, "", v); gsub(/[[:space:]]/, "", v); id = v
    }
    started && $0 ~ "^[[:space:]]*render:" { hasrender = "1" }
    started && $0 ~ "^[[:space:]]*required:" {
      v = $0; sub(/^[[:space:]]*required:[[:space:]]*/, "", v); gsub(/[[:space:]]/, "", v); required = v
    }
    END { flush() }
  ' "$1"
}

# id uniqueness within one form. The schema's uniqueItems constraint applies only to
# dropdown `options`, not to field ids — a copy-pasted block with the same id validates
# fine against the schema and only breaks at render/submission time.
check_id_uniqueness() { # $1 = form (basename, no .yml)
  local path="$TPL/$1.yml" dup
  dup="$(extract_blocks "$path" | awk -F'\t' '$1 != "" {print $1}' | sort | uniq -d)"
  if [[ -n "$dup" ]]; then
    bad "$1: duplicate field id(s): $(echo "$dup" | tr '\n' ' ')"
  else
    ok "$1: field ids unique"
  fi
}

# render + validations.required: true together is schema-legal (no `not` keyword exists
# for it) but is this ticket's own headline uncatchable example — a `render:` hint on a
# field GitHub also demands non-empty makes no sense (render only applies to freeform
# textarea display), so it stays owned locally.
check_render_not_required() { # $1 = form (basename, no .yml)
  local path="$TPL/$1.yml" offenders
  offenders="$(extract_blocks "$path" | awk -F'\t' '$2=="1" && $3=="true" {print $1}')"
  if [[ -n "$offenders" ]]; then
    bad "$1: field(s) combine render: with required: true: $(echo "$offenders" | tr '\n' ' ')"
  else
    ok "$1: no render+required combination"
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

# Discovered by glob, not named: a new form is covered on arrival with no selftest edit.
FORMS=()
for path in "$TPL"/*.yml; do
  [[ -f "$path" ]] || continue
  base="$(basename "$path" .yml)"
  [[ "$base" == "config" ]] && continue
  FORMS+=("$base")
done

for f in "${FORMS[@]}"; do
  path="$TPL/$f.yml"
  yaml_parses "$path"
  check_id_uniqueness "$f"
  check_render_not_required "$f"
done

# The three forms the per-field evidence table below is written against. Kept explicit
# (not derived from FORMS) because a missing KNOWN form is a real regression the table
# must catch, while FORMS itself already covers "does every form parse / have unique ids".
KNOWN_FORMS=(pipeline-aborted config-lint-disagreement review-false-positive)
for f in "${KNOWN_FORMS[@]}"; do
  [[ -f "$TPL/$f.yml" ]] || bad "$f.yml missing"
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
