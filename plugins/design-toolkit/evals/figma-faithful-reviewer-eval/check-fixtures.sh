#!/usr/bin/env bash
# check-fixtures.sh — the model-free guard on the figma-faithful-reviewer eval's expected files.
#
# WHAT IT CHECKS. Every `fixtures/*.expected.json` parses. An expected file that carries a
# `disproving` key — the library-conformance fixtures — must give a non-empty list of
# `{"path", "line"}` citations, and each one must name a file inside the fictional `acme-ui`
# stand-in (`fixtures/app/packages/acme-ui/`) and a line that exists in it. Paths are relative to
# the eval directory, which is the `--repo-root` that run.sh gives the reviewer.
#
# WHAT IT DOES NOT CHECK. The content of the cited line. The fixture author owns that; this guard
# only stops a citation from pointing at nothing after the stand-in is edited.
#
# ZERO FILES IS A FAILURE. A guard that reads nothing reports green, so an empty fixture set is
# rc=2, distinct from a violation's rc=1.
#
# No install, no network, no model.
#
# Usage: check-fixtures.sh [eval-dir]
#   eval-dir defaults to the directory holding this script. The argument exists so the paired
#   selftest can check a broken copy.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "[check-fixtures] could not resolve this script's own directory." >&2
  exit 2
fi
ROOT="${1:-$SCRIPT_DIR}"
STAND_IN="fixtures/app/packages/acme-ui/"

if [[ ! -d "$ROOT/fixtures" ]]; then
  echo "[check-fixtures] no fixtures directory under '$ROOT'" >&2
  exit 2
fi

files=()
for f in "$ROOT"/fixtures/*.expected.json; do
  [[ -f "$f" ]] && files+=("$f")
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[check-fixtures] read 0 expected files under $ROOT/fixtures." >&2
  echo "  The fixtures moved, or this root is wrong. Refusing to report a pass on an empty set." >&2
  exit 2
fi

violations=0
citations=0

report() {
  echo "  $1" >&2
  violations=$((violations + 1))
}

for f in "${files[@]}"; do
  rel="${f#"$ROOT"/}"
  if ! jq empty "$f" >/dev/null 2>&1; then
    report "$rel: does not parse as JSON"
    continue
  fi

  # One line per citation: OK<TAB>path<TAB>line, or a shape error. A file with no `disproving`
  # key prints nothing.
  while IFS=$'\t' read -r kind path line; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      NOTARRAY) report "$rel: disproving is not an array"; continue ;;
      EMPTY) report "$rel: disproving is empty — a conformance fixture names at least one line"; continue ;;
      BADENTRY) report "$rel: disproving entry $path is not {\"path\": string, \"line\": positive integer}"; continue ;;
    esac
    citations=$((citations + 1))
    case "$path" in
      "$STAND_IN"*) ;;
      *) report "$rel: $path:$line is outside the acme-ui stand-in ($STAND_IN)"; continue ;;
    esac
    case "/$path/" in
      */../*|*/./*) report "$rel: $path:$line uses a . or .. segment"; continue ;;
    esac
    if [[ ! -f "$ROOT/$path" ]]; then
      report "$rel: $path:$line — no such file"
      continue
    fi
    # awk counts a last line that has no trailing newline; wc -l does not.
    count=$(awk 'END { print NR }' "$ROOT/$path")
    if (( line > count )); then
      report "$rel: $path:$line — the file has $count lines"
    fi
  done < <(jq -r '
    if has("disproving") | not then empty
    else .disproving
      | if type != "array" then "NOTARRAY"
        elif length == 0 then "EMPTY"
        else .[]
          | if type == "object"
                and (.path | type) == "string"
                and (.line | type) == "number"
                and .line == (.line | floor)
                and .line >= 1
            then "OK\t\(.path)\t\(.line)"
            else "BADENTRY\t\(tojson)\t"
            end
        end
    end' "$f")
done

if [[ $violations -gt 0 ]]; then
  echo "[check-fixtures] $violations problem(s) in the expected files under $ROOT/fixtures." >&2
  exit 1
fi

echo "[check-fixtures] ✓ ${#files[@]} expected file(s) parse; $citations disproving citation(s) resolve in the acme-ui stand-in."
