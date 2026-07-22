#!/usr/bin/env bash
# derive-release-selftest.sh — proves scripts/derive-release.sh + the two PR-time gates (#119).
#
# Builds a throwaway git repo fixture (two plugins, a v1.0.0 tag, a curated commit series)
# and asserts: changed-plugin derivation from paths (AC-2), bump levels from conventional
# commit types incl. BREAKING (AC-2/AC-4), CHANGELOG rendering shape (AC-3), grep-anywhere
# trailer extraction incl. mid-body blocks and 'Changelog: none' (AC-4), release-commit
# exclusion, the cutover max rule + in-progress-section absorption without double-counting
# (AC-8), apply-mode idempotency, version-field shape for consumers (AC-7), the What-breaks
# assembly incl. "Nothing breaks." (AC-8), and both PR gates in pass and fail directions
# (AC-1, AC-5). bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
#
# shellcheck disable=SC2016  # single-quoted needles carry literal markdown backticks
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DERIVE="$HERE/derive-release.sh"
FROZEN="$HERE/check-frozen-files.sh"
TRAILER="$HERE/check-changelog-trailer.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_contains() { # assert_contains <label> <needle> <file>
  if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1 — missing: $2"; fi
}
assert_not_contains() {
  if grep -qF -- "$2" "$3"; then bad "$1 — unexpectedly present: $2"; else ok "$1"; fi
}

WORK="$(mktemp -d -t derive-release-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO"
cd "$REPO" || exit 2
git init -q
git config user.name selftest
git config user.email selftest@example.invalid
git config commit.gpgsign false

mkplugin() { # mkplugin <name> <version>
  mkdir -p "plugins/$1/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$1" "$2" > "plugins/$1/.claude-plugin/plugin.json"
}

# --- baseline at v1.0.0 ---
mkplugin alpha 1.2.0
mkplugin beta 2.0.1
mkdir -p .claude-plugin docs
printf '{\n  "name": "fixture",\n  "metadata": { "version": "1.0.0" }\n}\n' > .claude-plugin/marketplace.json
printf '{ "source": { "ref": "v1.0.0" } }\n' > docs/onboarding.md
cat > CHANGELOG.md <<'EOF'
# Changelog

Fixture preamble line.

## v1.0.0

### `alpha` 1.1.0 → 1.2.0

- **old released entry** (#1)
EOF
git add -A
git commit -qm "release: v1.0.0"
git tag v1.0.0

# --- commit series since the tag ---

# C1: fix on alpha, mid-body trailer with indented continuation, NOT the final paragraph (AC-4).
echo a >> "plugins/alpha/f.txt"
git add -A
git commit -qm "fix(alpha): guard the flux capacitor (#10)" -m "Changelog: flux capacitor no longer explodes.
  Migration: rerun setup once.

docs(pipeline): plan for #10 — trailing squash noise paragraph"

# C2: feat touching BOTH plugins in one commit (AC-2 path derivation, no scope parsing).
echo b >> "plugins/alpha/g.txt"
echo b >> "plugins/beta/g.txt"
git add -A
git commit -qm "feat: shared surface across alpha and beta (#11)" -m "Changelog: none"

# C3: breaking on beta via BREAKING CHANGE body (AC-4 major + note).
echo c >> "plugins/beta/h.txt"
git add -A
git commit -qm "feat(beta): rework config lanes (#12)" -m "BREAKING CHANGE: lanes[] entries must be objects now.

Changelog: lanes[] string shorthand removed.
  Migration: rewrite [\"npm ci\"] as [{\"name\":\"install\",\"commands\":[\"npm ci\"]}]."

# C4: no trailer at all on alpha (AC-4 bare bullet + flagged).
echo d >> "plugins/alpha/i.txt"
git add -A
git commit -qm "chore(alpha): tidy internals (#13)"

# C4b: the PUNCTUATED no-op form. Every fixture above writes the bare "none", which is why
# an exact `$0 != "none"` comparison passed this selftest for months while shipping literal
# "  none." bullets into the real CHANGELOG.md (12 commits' worth). "none." is the form
# contributors actually type.
echo d2 >> "plugins/alpha/i2.txt"
git add -A
git commit -qm "chore(alpha): punctuated no-op trailer (#14)" -m "Changelog: none."

# C4c: a real entry that merely STARTS with the no-op word must still render — the drop is
# whole-block, not a prefix match.
echo d3 >> "plugins/beta/i3.txt"
git add -A
git commit -qm "fix(beta): narrow no-op lookalike (#19)" -m "Changelog: none of the exported helpers changed shape."

# C5: a release: commit that must be EXCLUDED from derivation.
echo e >> "plugins/alpha/j.txt"
git add -A
git commit -qm "release: v9.9.9 — decoy that must not be counted"

# C6: root-only change — no plugin, no bullet.
echo f >> docs/onboarding.md.bak
git add -A
git commit -qm "docs: root-only change (#14)"

# Cutover state: alpha already hand-bumped AHEAD (1.4.0 > tag 1.2.0), plus an
# unreleased in-progress section referencing #10 (its bullet must not double-count).
python3 - <<'PYEOF' 2>/dev/null || sed -i.bak 's/"version": "1.2.0"/"version": "1.4.0"/' plugins/alpha/.claude-plugin/plugin.json
import json
p = "plugins/alpha/.claude-plugin/plugin.json"
d = json.load(open(p))
d["version"] = "1.4.0"
json.dump(d, open(p, "w"), indent=2)
PYEOF
rm -f plugins/alpha/.claude-plugin/plugin.json.bak
cat > CHANGELOG.md <<'EOF'
# Changelog

Fixture preamble line.

## v1.1.0 (in progress)

### `alpha` 1.2.0 → 1.4.0

- **hand-written rich entry for the flux fix (#10).** Kept prose with migration detail
  that must survive absorption verbatim.

## v1.0.0

### `alpha` 1.1.0 → 1.2.0

- **old released entry** (#1)
EOF
git add -A
git commit -qm "chore(alpha): cutover fixture state (#15)" -m "Changelog: none"

echo "== manifest derivation =="
MANIFEST="$WORK/manifest.json"
bash "$DERIVE" manifest > "$MANIFEST" || bad "manifest mode exited nonzero"

check_jq() { # check_jq <label> <jq-expr expected to be true>
  if [[ "$(jq -r "$1" "$MANIFEST")" == "true" ]]; then ok "$2"; else bad "$2 — jq: $1 => $(jq -r "$1" "$MANIFEST")"; fi
}
check_jq '.previousTag == "v1.0.0"' "previous tag"
check_jq '.previousVersion == "1.0.0"' "previous marketplace version"
check_jq '.plugins | keys == ["alpha","beta"]' "changed plugins from paths (AC-2)"
check_jq '.plugins.beta.level == "major"' "BREAKING CHANGE body -> major (AC-4)"
check_jq '.plugins.beta.new == "3.0.0"' "beta 2.0.1 major -> 3.0.0 (AC-2)"
check_jq '.plugins.alpha.new == "1.4.0"' "alpha max rule: hand-bumped 1.4.0 beats derived 1.3.0 (AC-8 cutover)"
check_jq '.releaseVersion == "2.0.0"' "release version = previous + max level (major) (AC-2)"
check_jq '[.prs[].subject] | any(startswith("release:")) | not' "release: commits excluded"
check_jq '[.prs[] | select(.prNumber == 10) | .changelog[0]] | .[0] | startswith("flux capacitor")' "mid-body trailer extracted grep-anywhere (AC-4)"
check_jq '[.prs[] | select(.prNumber == 13) | .noTrailer] | .[0] == true' "no-trailer commit flagged (AC-4)"
check_jq '[.prs[] | select(.prNumber == 11) | .noTrailer] | .[0] == false' "Changelog: none counts as trailer-present (AC-5 semantics)"

echo "== apply mode =="
PR_BODY="$WORK/pr-body.md"
bash "$DERIVE" apply > "$PR_BODY" || bad "apply mode exited nonzero"

V_ALPHA="$(jq -r .version plugins/alpha/.claude-plugin/plugin.json)"
V_BETA="$(jq -r .version plugins/beta/.claude-plugin/plugin.json)"
V_MARKET="$(jq -r .metadata.version .claude-plugin/marketplace.json)"
[[ "$V_ALPHA" == "1.4.0" ]] && ok "alpha version written (max rule)" || bad "alpha version: $V_ALPHA"
[[ "$V_BETA" == "3.0.0" ]] && ok "beta version written (AC-7 same field shape)" || bad "beta version: $V_BETA"
[[ "$V_MARKET" == "2.0.0" ]] && ok "marketplace lockstep version written" || bad "marketplace: $V_MARKET"
assert_contains "pinned-ref example updated" '"ref": "v2.0.0"' docs/onboarding.md

assert_contains "generated release heading (AC-3)" '## v2.0.0' CHANGELOG.md
assert_not_contains "in-progress heading absorbed" '(in progress)' CHANGELOG.md
assert_contains "per-plugin heading with old -> new (AC-3)" '### `beta` 2.0.1 → 3.0.0' CHANGELOG.md
assert_contains "hand-written prose preserved verbatim (AC-8 cutover)" 'hand-written rich entry for the flux fix' CHANGELOG.md
assert_contains "trailer prose rendered as migration note (AC-3)" 'Migration: rewrite ["npm ci"]' CHANGELOG.md
assert_contains "no-trailer commit still gets a bullet (AC-4)" 'tidy internals' CHANGELOG.md
assert_contains "punctuated no-op commit still gets its bullet" 'punctuated no-op trailer' CHANGELOG.md
assert_contains "no-op lookalike still renders in full" 'none of the exported helpers changed shape' CHANGELOG.md
# Exact-line, not substring: the lookalike bullet above legitimately BEGINS with "  none",
# so a grep -F "  none" would false-fail on it. Only a line that is nothing but the no-op
# word is the defect.
if grep -qxE '[[:space:]]*[Nn]one\.?[[:space:]]*' CHANGELOG.md; then
  bad "no-op trailer rendered as a literal bullet line ($(grep -nxE '[[:space:]]*[Nn]one\.?[[:space:]]*' CHANGELOG.md | head -1))"
else
  ok "no-op trailers ('none' and 'none.') render no literal bullet line"
fi
assert_contains "released section untouched" '- **old released entry** (#1)' CHANGELOG.md
COUNT_FLUX="$(grep -c 'flux' CHANGELOG.md || true)"
[[ "$COUNT_FLUX" == "1" ]] && ok "covered PR #10 not double-counted" || bad "PR #10 rendered $COUNT_FLUX times"
assert_contains "PR body: bump table" '| `beta` | 2.0.1 | **3.0.0** | major |' "$PR_BODY"
assert_contains "PR body: subject-only flag section" 'Subject-only entries' "$PR_BODY"
assert_contains "PR body: human checklist" 'Section catalog' "$PR_BODY"

echo "== apply idempotency =="
CHG1="$WORK/changelog-run1"
cp CHANGELOG.md "$CHG1"
bash "$DERIVE" apply > /dev/null || bad "second apply exited nonzero"
if diff -q "$CHG1" CHANGELOG.md > /dev/null; then ok "second apply is byte-identical (idempotent)"; else bad "second apply changed CHANGELOG"; diff "$CHG1" CHANGELOG.md | head -20; fi

echo "== release-notes mode =="
NOTES="$WORK/notes.md"
bash "$DERIVE" release-notes > "$NOTES" || bad "release-notes exited nonzero"
assert_contains "What-breaks carries BREAKING prose (AC-8)" 'lanes[] entries must be objects' "$NOTES"
assert_contains "What-breaks carries Migration trailer prose" 'Migration: rewrite' "$NOTES"
assert_contains "upgrade recipe present (AC-8)" 'claude plugin marketplace update second-shift' "$NOTES"

echo "== release-notes: Nothing breaks. =="
# A tag right here makes the remaining range empty -> the explicit no-breaks line.
git add -A >/dev/null 2>&1 || true
git commit -qam "release: v2.0.0" >/dev/null 2>&1 || true
git tag v2.0.0
echo x >> "plugins/alpha/k.txt"
git add -A
git commit -qm "fix(alpha): quiet fix (#16)" -m "Changelog: none"
bash "$DERIVE" release-notes > "$NOTES" || bad "release-notes (clean range) exited nonzero"
assert_contains "explicit Nothing breaks. (AC-8)" 'Nothing breaks.' "$NOTES"

echo "== PR gates =="
# Branch simulating a feature PR that (wrongly) bumps a version + touches CHANGELOG.
git checkout -qb bad-pr v2.0.0
python3 - <<'PYEOF' 2>/dev/null || sed -i.bak 's/"version": "1.4.0"/"version": "1.5.0"/' plugins/alpha/.claude-plugin/plugin.json
import json
p = "plugins/alpha/.claude-plugin/plugin.json"
d = json.load(open(p))
d["version"] = "1.5.0"
json.dump(d, open(p, "w"), indent=2)
PYEOF
rm -f plugins/alpha/.claude-plugin/plugin.json.bak
echo "manual entry" >> CHANGELOG.md
git add -A
git commit -qm "feat(alpha): sneaky manual bump (#17)"
if bash "$FROZEN" v2.0.0 > /dev/null 2>&1; then bad "frozen-files gate passed a version bump + CHANGELOG edit (AC-1)"; else ok "frozen-files gate rejects version bump + CHANGELOG edit (AC-1)"; fi
if bash "$TRAILER" v2.0.0 > /dev/null 2>&1; then bad "trailer gate passed a plugins/** PR with no trailer (AC-5)"; else ok "trailer gate rejects missing trailer (AC-5)"; fi

# Clean feature PR: plugins change, no frozen files, trailer present.
git checkout -q v2.0.0
git checkout -qb good-pr
echo y >> "plugins/beta/l.txt"
git add -A
git commit -qm "fix(beta): honest fix (#18)" -m "Changelog: none"
if bash "$FROZEN" v2.0.0 > /dev/null 2>&1; then ok "frozen-files gate passes a clean PR (AC-1)"; else bad "frozen-files gate rejected a clean PR"; fi
if bash "$TRAILER" v2.0.0 > /dev/null 2>&1; then ok "trailer gate passes with Changelog: none (AC-5)"; else bad "trailer gate rejected Changelog: none"; fi

# Non-plugins PR: trailer not required.
git checkout -q v2.0.0
git checkout -qb docs-pr
echo z >> docs/onboarding.md
git add -A
git commit -qm "docs: no plugin surface (#19)"
if bash "$TRAILER" v2.0.0 > /dev/null 2>&1; then ok "trailer gate skips non-plugins PR (AC-5)"; else bad "trailer gate demanded a trailer on a non-plugins PR"; fi

echo "== configVersion migration-doc gate =="
CFGGATE="$HERE/check-configversion-migration-doc.sh"
git checkout -q v2.0.0
git checkout -qb cfgver
mkdir -p schema docs/migrations
printf '{ "properties": { "configVersion": { "const": 1 } } }\n' > schema/second-shift.config.schema.json
git add -A
git commit -qm "chore: schema fixture (#20)" -m "Changelog: none"
git tag v3.0.0
if bash "$CFGGATE" v3.0.0 > /dev/null 2>&1; then ok "configVersion unchanged -> pass"; else bad "configVersion unchanged should pass"; fi

printf '{ "properties": { "configVersion": { "const": 2 } } }\n' > schema/second-shift.config.schema.json
git add -A
git commit -qm "feat!: schema v2 (#21)" -m "Changelog: none"
if bash "$CFGGATE" v3.0.0 > /dev/null 2>&1; then bad "configVersion 1->2 without migration doc should FAIL"; else ok "configVersion bump without migration doc -> fail"; fi

printf 'migration notes\n' > docs/migrations/v1-to-v2.md
git add -A
git commit -qm "docs: migration doc (#22)" -m "Changelog: none"
if bash "$CFGGATE" v3.0.0 > /dev/null 2>&1; then ok "configVersion bump WITH migration doc -> pass"; else bad "configVersion bump with doc present should pass"; fi

echo
echo "derive-release-selftest: $PASS ok, $FAIL failed"
exit "$FAIL"
