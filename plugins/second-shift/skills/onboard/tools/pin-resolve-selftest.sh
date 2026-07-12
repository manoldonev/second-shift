#!/usr/bin/env bash
# pin-resolve-selftest.sh — hermetic: stubs `gh` with a PATH shim.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/pin-resolve.sh"
FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
expect() { local got; got="$(jq -r "$2" <<< "$1")"; if [[ "$got" == "$3" ]]; then check "$4" 0; else check "$4 (want '$3' got '$got')" 1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

write_gh() { # $1 = mode: release | tags-only | no-tags
cat > "$TMP/bin/gh" <<SHIM
#!/usr/bin/env bash
mode="$1"
case "\$*" in
  *releases/latest*)
    if [[ "\$mode" == release ]]; then echo "v9.9.0"; exit 0; else echo "Not Found" >&2; exit 1; fi ;;
  *"/tags"*)
    if [[ "\$mode" == no-tags ]]; then echo ""; exit 0; fi
    printf 'v2.0.1\nv2.0.0\nv1.9.0\n' ;;
  *contents/plugins/*plugin.json*)
    # base64 body, NEWLINE-WRAPPED like the real contents API (fold), version keyed on plugin name
    if [[ "\$*" == *dev-pipeline* ]]; then v=2.1.0; else v=2.0.0; fi
    printf '{ "version": "%s" }' "\$v" | base64 | fold -w 20 ;;
  *) echo "unexpected gh call: \$*" >&2; exit 64 ;;
esac
SHIM
chmod +x "$TMP/bin/gh"
}

echo "pin-resolve selftest:"
export PATH="$TMP/bin:$PATH"

write_gh release
OUT="$("$TOOL" acme/second-shift dev-pipeline review-toolkit)"
expect "$OUT" '.ref' v9.9.0 "release path picks releases/latest"
expect "$OUT" '.refSource' release "refSource=release"
expect "$OUT" '.plugins."dev-pipeline"' 2.1.0 "plugin version at ref"
expect "$OUT" '.plugins."review-toolkit"' 2.0.0 "second plugin version"

write_gh tags-only
OUT2="$("$TOOL" acme/second-shift dev-pipeline 2>/dev/null)"
expect "$OUT2" '.ref' v2.0.1 "tag fallback picks highest semver"
expect "$OUT2" '.refSource' tag-fallback "refSource=tag-fallback"

write_gh no-tags
if "$TOOL" acme/second-shift dev-pipeline >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "no tags at all exits 1" "$([[ "$rc" -eq 1 ]] && echo 0 || echo 1)"

if "$TOOL" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "usage error exits 3" "$([[ "$rc" -eq 3 ]] && echo 0 || echo 1)"

if [[ "$FAILS" -gt 0 ]]; then echo "pin-resolve selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "pin-resolve selftest: all green"
