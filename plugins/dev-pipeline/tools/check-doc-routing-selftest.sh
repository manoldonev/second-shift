#!/usr/bin/env bash
# Selftest for check-doc-routing.sh: a valid routing map (literal + dir + glob entries)
# passes; a renamed/moved doc and a deleted doc each fail closed naming the entry; no
# doc-routing.md is a clean no-op.
set -euo pipefail
# Hermetic hygiene: honor the same unset convention as check-extensions-selftest.sh (#34) so
# a caller's leaked pipeline seam vars cannot clobber this selftest's own fixtures.
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_DOC_ROUTING BRANCH_PREFIX
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-doc-routing.sh"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# (1) no doc-routing.md at all -> clean no-op (this repo's own tree has none today)
mkdir -p "$TMP/empty"
bash "$CHECK" "$TMP/empty" >/dev/null 2>&1 && ok "no doc-routing.md -> clean" || bad "missing doc-routing.md should pass but failed"

# (2) a valid map: a repo-root-relative file, a repo-root-relative dir, and a glob entry
#     resolved relative to doc-routing.md's own directory -> clean
mkdir -p "$TMP/valid/.claude/second-shift/subdir" "$TMP/valid/docs"
: > "$TMP/valid/docs/real.md"
: > "$TMP/valid/.claude/second-shift/subdir/a.md"
cat > "$TMP/valid/.claude/second-shift/doc-routing.md" << 'ROUTING'
| Change category | Doc(s) to check |
| --- | --- |
| Foo changes | `docs/real.md` |
| Bar changes | `docs/` |

- `subdir/*.md` — stale-risk hotspot
ROUTING
bash "$CHECK" "$TMP/valid" >/dev/null 2>&1 && ok "literal file + dir + glob entries -> clean" \
  || bad "valid routing map should pass but failed"

# (3) a table entry pointing at a renamed/moved doc -> fail closed, naming the entry
mkdir -p "$TMP/moved/.claude/second-shift" "$TMP/moved/docs"
: > "$TMP/moved/docs/renamed-target.md"
cat > "$TMP/moved/.claude/second-shift/doc-routing.md" << 'ROUTING'
| Change category | Doc(s) to check |
| --- | --- |
| Foo changes | `docs/old-name.md` |
ROUTING
if bash "$CHECK" "$TMP/moved" > "$TMP/docroute-moved.out" 2>&1; then
  bad "renamed-doc entry should FAIL but passed"
else
  grep -q "DANGLING-DOC-ROUTE:.*docs/old-name.md" "$TMP/docroute-moved.out" \
    && ok "renamed doc -> DANGLING-DOC-ROUTE fail closed, naming the entry" \
    || bad "renamed doc failed but without the expected message"
fi

# (4) a list entry pointing at a deleted doc -> fail closed
mkdir -p "$TMP/deleted/.claude/second-shift"
cat > "$TMP/deleted/.claude/second-shift/doc-routing.md" << 'ROUTING'
## Docs that restate code constants

- `.project/reference/domain-constants.md` — thresholds mirrored by tests
ROUTING
if bash "$CHECK" "$TMP/deleted" > "$TMP/docroute-deleted.out" 2>&1; then
  bad "deleted-doc entry should FAIL but passed"
else
  grep -q "DANGLING-DOC-ROUTE:.*domain-constants.md" "$TMP/docroute-deleted.out" \
    && ok "deleted doc -> DANGLING-DOC-ROUTE fail closed" \
    || bad "deleted doc failed but without the expected message"
fi

# (5) prose/blockquote backtick mentions outside table/list rows are never scanned
mkdir -p "$TMP/prose/.claude/second-shift"
cat > "$TMP/prose/.claude/second-shift/doc-routing.md" << 'ROUTING'
> Read by `review-toolkit:doc-updater`.
> `.project/` is the authoritative knowledge tree.
ROUTING
bash "$CHECK" "$TMP/prose" >/dev/null 2>&1 && ok "prose/blockquote backtick mentions -> not scanned, clean" \
  || bad "prose-only file should pass but failed"

# (6) a table HEADER row containing a backtick-quoted path that does not exist -> not
# scanned (AC-3's header exclusion), only the body row below it is checked
mkdir -p "$TMP/header/.claude/second-shift/docs"
: > "$TMP/header/.claude/second-shift/docs/real.md"
cat > "$TMP/header/.claude/second-shift/doc-routing.md" << 'ROUTING'
| Change category (see `docs/does-not-exist.md`) | Doc(s) to check |
| --- | --- |
| Foo changes | `docs/real.md` |
ROUTING
bash "$CHECK" "$TMP/header" >/dev/null 2>&1 && ok "header-row backtick span -> not scanned, clean" \
  || bad "header row should be excluded from scanning but its dangling span failed the check"

# (7) exit code equals the number of distinct dangling entries (AC-5), not a fixed 1
mkdir -p "$TMP/count/.claude/second-shift"
cat > "$TMP/count/.claude/second-shift/doc-routing.md" << 'ROUTING'
| Change category | Doc(s) to check |
| --- | --- |
| Foo changes | `docs/missing-a.md` |
| Bar changes | `docs/missing-b.md` |
ROUTING
rc=0
bash "$CHECK" "$TMP/count" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] && ok "exit code equals the dangling-entry count (2)" \
  || bad "exit code should be 2 (one per dangling entry) but was $rc"

if [[ "$FAILS" -gt 0 ]]; then echo "check-doc-routing selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-doc-routing selftest: all green"
