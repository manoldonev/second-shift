#!/usr/bin/env bash
# Selftest for check-review-context-sections.sh + section-catalog.txt.
# Covers the #67 acceptance: the cadenza 5-H2 fixture (only the alias flagged, 7 H1s
# silent), the M1 / empty-body / M4 mutation outcomes at the preflight venue, the
# coverage-cannot-fail-exit invariant, the .known-sections escape hatch, and the
# catalog<->extension-points.md template lockstep.
set -euo pipefail

# Hermetic hygiene (mirrors check-review-context-selftest.sh): a Stage-6 verify run exports
# pipeline seam vars that the tools honor as overrides — unset them so this selftest owns its
# environment. NOTE: SECOND_SHIFT_SECTION_CATALOG is intentionally left UNSET so the script
# resolves the REAL shipped catalog ($SCRIPT_DIR/section-catalog.txt) — the lockstep case
# depends on testing the real catalog against the real docs.
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST \
      SECOND_SHIFT_SECTION_CATALOG BRANCH_PREFIX 2>/dev/null || true

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-review-context-sections.sh"
CATALOG="$HERE/section-catalog.txt"
DOCS="$HERE/../../../docs/extension-points.md"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Hermetic plugin root: a minimal review-lead SKILL.md carrying the panel line the effective-
# registry parser keys on. The catalog stays the REAL one (see note above).
mkdir -p "$TMP/plugin/skills/review-lead"
cat > "$TMP/plugin/skills/review-lead/SKILL.md" <<'MD'
choose from the effective reviewer registry — the plugin-shipped panel (security-reviewer, performance-reviewer, db-reviewer, a11y-reviewer, complexity-reviewer, maintainability-reviewer) plus/minus config deltas.
MD
export SECOND_SHIFT_PLUGIN_ROOT="$TMP/plugin"

# ---- fixture builder: cadenza's five real H2s + seven per-reviewer H1 files ----
build_cadenza() {  # $1 = root ; optional $2 = maturity heading override
    local root="$1" maturity="${2:-## Maturity calibration (MVP stage)}"
    mkdir -p "$root/.claude/second-shift/review-context"
    cat > "$root/.claude/second-shift/review-context.md" <<MD
# Review context — Cadenza AI

## Owned elsewhere — pointers, not values
The severity ladder lives in docs/; this file points, not restates.

## Stack
Next.js app router, BullMQ workers, Postgres + pgvector.

## Repo topology & package architecture
pnpm workspaces: apps/web, apps/api, packages/*.

$maturity
Pre-auth MVP: no ownership parameter or tenant guards exist yet.

## Domain test edge cases (test-coverage severity examples)
Empty-cart checkout, duplicate webhook delivery.
MD
    local r
    for r in a11y-reviewer performance-reviewer maintainability-reviewer \
             complexity-reviewer test-coverage-reviewer pipeline-reviewer db-reviewer; do
        cat > "$root/.claude/second-shift/review-context/$r.md" <<MD
# $r — Cadenza AI
Repo-specific notes for this reviewer.
MD
    done
}

# ---- (1) AC-1: cadenza fixture, DEFAULT venue -> exactly the alias flagged --------------
build_cadenza "$TMP/r1"
RC=0; OUT="$(bash "$CHECK" "$TMP/r1" 2>&1)" || RC=$?
n_alias=$(printf '%s\n' "$OUT" | grep -c 'ALIAS:' || true)
n_offcat=$(printf '%s\n' "$OUT" | grep -c 'OFF-CATALOG:' || true)
n_empty=$(printf '%s\n' "$OUT" | grep -c 'EMPTY-SECTION:' || true)
if [ "$RC" -eq 0 ] && [ "$n_alias" -eq 1 ] && [ "$n_offcat" -eq 0 ] && [ "$n_empty" -eq 0 ] \
   && printf '%s\n' "$OUT" | grep -q 'Maturity calibration (MVP stage)'; then
    ok "AC-1: cadenza fixture (default) -> exactly the alias flagged; 4 other H2s + 7 H1s silent"
else
    bad "AC-1: expected exactly 1 alias finding at default (rc=$RC alias=$n_alias offcat=$n_offcat empty=$n_empty)"
fi

# ---- (2) AC-2: M1 (rename alias -> novel) at --preflight -> NOT red, coverage discloses --
build_cadenza "$TMP/r2" "## Historical notes"
RC=0; OUT="$(bash "$CHECK" --preflight "$TMP/r2" 2>&1)" || RC=$?
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'context-coverage:' \
   && printf '%s\n' "$OUT" | grep -q 'security-reviewer'; then
    ok "AC-2 (M1): rename-to-novel is WARN + coverage-disclosed (security-reviewer degraded), NOT red"
else
    bad "AC-2 (M1): expected exit 0 + coverage line naming security-reviewer (rc=$RC)"
fi

# ---- (3) AC-2: present-but-empty catalog section at --preflight -> RED -------------------
mkdir -p "$TMP/r3/.claude/second-shift"
cat > "$TMP/r3/.claude/second-shift/review-context.md" <<'MD'
# Review context — Repo

## Stack

## Maturity stage
Pre-auth MVP.
MD
RC=0; OUT="$(bash "$CHECK" --preflight "$TMP/r3" 2>&1)" || RC=$?
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'EMPTY-SECTION:.*Stack'; then
    ok "AC-2 (empty-body): a present-but-empty catalog section is RED at --preflight"
else
    bad "AC-2 (empty-body): expected non-zero exit + EMPTY-SECTION for Stack (rc=$RC)"
fi

# ---- (4) AC-2: M4 empty file -> NOT red; coverage discloses -----------------------------
mkdir -p "$TMP/r4/.claude/second-shift"
: > "$TMP/r4/.claude/second-shift/review-context.md"
RC=0; OUT="$(bash "$CHECK" --preflight "$TMP/r4" 2>&1)" || RC=$?
RC_REP=0; REP="$(bash "$CHECK" --report "$TMP/r4" 2>&1)" || RC_REP=$?
if [ "$RC" -eq 0 ] && [ "$RC_REP" -eq 0 ] && printf '%s\n' "$REP" | grep -q '0/9 catalog sections present'; then
    ok "AC-2 (M4 empty-file): NOT red; coverage line discloses 0/9 sections present"
else
    bad "AC-2 (M4): expected exit 0 (preflight=$RC report=$RC_REP) + '0/9 ... present' coverage"
fi

# ---- (5) AC-3: coverage cannot contribute to exit (--report always 0) -------------------
r5_ok=1
for d in "$TMP/r1" "$TMP/r3"; do
    bash "$CHECK" --report "$d" >/dev/null 2>&1 || r5_ok=0
done
[ "$r5_ok" -eq 1 ] && ok "AC-3: --report exits 0 even over alias/empty-body fixtures" \
    || bad "AC-3: --report must never contribute to the exit code"

# ---- (6) AC-3: escape hatch (.known-sections AND section: in .known-extensions) ----------
mkdir -p "$TMP/r6/.claude/second-shift"
cat > "$TMP/r6/.claude/second-shift/review-context.md" <<'MD'
# Review context — Repo

## Services stack
Custom, intentional.

## Feature flags
Also intentional.
MD
printf 'Services stack\n' > "$TMP/r6/.claude/second-shift/.known-sections"
printf 'section:Feature flags\n' > "$TMP/r6/.claude/second-shift/.known-extensions"
RC=0; OUT="$(bash "$CHECK" --preflight "$TMP/r6" 2>&1)" || RC=$?
if [ "$RC" -eq 0 ] && ! printf '%s\n' "$OUT" | grep -q 'OFF-CATALOG:'; then
    ok "AC-3: .known-sections + section: in .known-extensions silence off-catalog headings"
else
    bad "AC-3: escape hatch should silence both novel headings (rc=$RC): $(printf '%s' "$OUT" | grep OFF-CATALOG || true)"
fi

# ---- (7) AC-3: catalog <-> extension-points.md template lockstep ------------------------
# Template section names = the `^## ` lines inside the ```markdown fence under
# "## Authoring the review-context surface". Catalog active names = status active rows.
if [ -f "$DOCS" ]; then
    tmpl="$(awk '
        /^## Authoring the review-context surface/ {inSec=1}
        inSec && /^```/ {fence=!fence; next}
        inSec && fence && /^## / {h=$0; sub(/^## /,"",h); print h}
        inSec && !fence && /^## / && !/Authoring the review-context surface/ {exit}
    ' "$DOCS" | sort -u)"
    catalog_active="$(awk -F'|' '
        /^[[:space:]]*#/ {next}
        NF>=3 {
            name=$1; st=$3;
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",name); gsub(/^[[:space:]]+|[[:space:]]+$/,"",st);
            if (st=="active") print name;
        }' "$CATALOG" | sort -u)"
    if [ "$tmpl" = "$catalog_active" ] && [ -n "$tmpl" ]; then
        ok "AC-3: catalog active names == extension-points.md template H2s (lockstep)"
    else
        bad "AC-3: lockstep drift between catalog and docs template"
        echo "    --- template ---"; printf '%s\n' "$tmpl" | sed 's/^/      /'
        echo "    --- catalog ----"; printf '%s\n' "$catalog_active" | sed 's/^/      /'
    fi
    # every alias target must be an active catalog name
    bad_alias=0
    while IFS='|' read -r _ _ st; do
        st="$(printf '%s' "$st" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$st" in deprecated-alias-of:*)
            tgt="${st#deprecated-alias-of:}"
            printf '%s\n' "$catalog_active" | grep -Fxq "$tgt" || { bad_alias=1; echo "    alias -> unknown target: $tgt"; }
        esac
    done < "$CATALOG"
    [ "$bad_alias" -eq 0 ] && ok "AC-3: every deprecated-alias-of target is an active catalog section" \
        || bad "AC-3: an alias points at a non-active target"
else
    bad "AC-3: docs/extension-points.md not found at $DOCS (lockstep cannot run)"
fi

# ---- (8) --verbose surfaces novel headings + coverage in the default (mid-run) venue ----
# Default mode suppresses OFF-CATALOG/coverage; --verbose must reveal both.
RC=0; OUT="$(bash "$CHECK" --verbose "$TMP/r1" 2>&1)" || RC=$?
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'OFF-CATALOG:' \
   && printf '%s\n' "$OUT" | grep -q 'context-coverage:'; then
    ok "--verbose surfaces novel headings + coverage in the default venue (suppressed without it)"
else
    bad "--verbose should reveal OFF-CATALOG + coverage in default mode (rc=$RC)"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "check-review-context-sections-selftest: ALL PASS"
else
    echo "check-review-context-sections-selftest: $FAILS FAILURE(S)"; exit 1
fi
