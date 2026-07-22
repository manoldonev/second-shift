#!/usr/bin/env bash
# score-review-selftest.sh — proves the harness scorer scores, and that the planted
# mutants in harness-plan-alpha.md are still planted.
#
# Three halves:
#   (A) SCORER CASES — canned findings JSON through score-review.sh: full detection,
#       partial detection, false positives, bare-array input, malformed input. A scorer
#       nobody has seen fail is a scorer nobody knows works.
#   (B) ANCHOR DRIFT GUARDS — each planted falsehood in harness-plan-alpha.md must STILL
#       be false in the live tree, else the mutant silently stops measuring anything
#       (the fixture-must-still-reproduce discipline from diff-range-selftest.sh):
#       a repo change that legitimately invalidates an anchor must update the fixture.
#   (C) MANIFEST SANITY — ids unique, kinds legal, regexes compile, >0 detect rows.
#
# Entirely model-free (CI-safe). Bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")" # skills/run
SCORER="$SCRIPT_DIR/score-review.sh"
FIXDIR="$SCRIPT_DIR/review-harness-fixtures"
MANIFEST="$FIXDIR/review-harness-manifest.tsv"
PLAN="$FIXDIR/harness-plan-alpha.md"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t score-review-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ---------- (A) scorer cases ----------

# A1: findings that hit every mutant and no trap → detected=8/8 fp=0.
cat > "$TMP/full.json" <<'EOF'
{ "findings": [
  { "severity": "blocker", "file": "statectl.sh", "description": "mark-failed validates --reason against a closed enum; the free-text assumption is false" },
  { "severity": "blocker", "file": "tools/bot-commit.sh", "description": "bot-commit.sh already resolves the config from the main checkout (candidate 3); the SECOND_SHIFT_CONFIG export step is unnecessary" },
  { "severity": "major", "file": "tools/claim-issue.sh", "description": "the claim swap adds in-progress first and confirms before removing ready-for-dev — the plan states the reverse order" },
  { "severity": "blocker", "file": "workflows/stall-probe.mjs", "description": "FINDINGS_SCHEMA is copied verbatim by stall-probe and tool-discipline-probe; renaming it in code-review.mjs alone breaks the lockstep" },
  { "severity": "major", "file": "workflows/code-review.mjs", "description": "dispatchSchemaAgent does not exist in code-review.mjs (that file has dispatchReviewer)" },
  { "severity": "major", "file": "workflows/unit-tests.mjs", "description": "withCeiling does not exist in unit-tests.mjs; it lives in plan-review.mjs and code-review.mjs" },
  { "severity": "blocker", "file": "docs", "description": "step 6 bumps plugin.json version — versions are release-derived and check-frozen-files rejects a feature PR touching them" },
  { "severity": "warning", "file": "skills/run", "description": "state-times.md does not exist; the real file is stage-times.sh" }
] }
EOF
out="$(bash "$SCORER" "$TMP/full.json" "$MANIFEST")"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -q "harness-score: detected=8/8 fp=0"; then
  ok "A1 full-detection findings score 8/8 fp=0"
else
  bad "A1 expected detected=8/8 fp=0 rc=0; got rc=$rc, $(printf '%s\n' "$out" | tail -1)"
fi

# A2: partial detection + false positives → detected=2/8, fp>=2.
cat > "$TMP/partial.json" <<'EOF'
{ "findings": [
  { "severity": "blocker", "file": "statectl.sh", "message": "mark-failed reasons are enum-validated, contradicting the assumption" },
  { "severity": "warning", "file": "workflows/unit-tests.mjs", "claim": "withCeiling is absent from unit-tests.mjs" },
  { "severity": "major", "file": "tools/tracker/jira/README.md", "description": "tracker/jira/README.md appears to be missing from the tree" },
  { "severity": "blocker", "file": "plan", "description": "CEILING_MS must be raised now; leaving the ceiling unchanged is unacceptable" }
] }
EOF
out="$(bash "$SCORER" "$TMP/partial.json" "$MANIFEST")"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -q "harness-score: detected=2/8 fp=2"; then
  ok "A2 partial findings score 2/8 with fp=2"
else
  bad "A2 expected detected=2/8 fp=2; got: $(printf '%s\n' "$out" | tail -1)"
fi

# A3: bare-array input is accepted.
echo '[{"severity":"note","file":"x","description":"state-times.md is not present in the repo"}]' > "$TMP/bare.json"
out="$(bash "$SCORER" "$TMP/bare.json" "$MANIFEST")"
printf '%s\n' "$out" | grep -q "harness-score: detected=1/8 fp=0" \
  && ok "A3 bare-array findings input accepted" \
  || bad "A3 bare-array scoring wrong: $(printf '%s\n' "$out" | tail -1)"

# A4: empty findings → 0/8, fp=0 (a review that says nothing detects nothing).
echo '{"findings":[]}' > "$TMP/empty.json"
out="$(bash "$SCORER" "$TMP/empty.json" "$MANIFEST")"
printf '%s\n' "$out" | grep -q "harness-score: detected=0/8 fp=0 findings=0" \
  && ok "A4 empty findings score 0/8" \
  || bad "A4 empty findings scoring wrong: $(printf '%s\n' "$out" | tail -1)"

# A5: malformed JSON → rc=2, no score line.
echo 'not json' > "$TMP/badjson.json"
out="$(bash "$SCORER" "$TMP/badjson.json" "$MANIFEST" 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && ok "A5 malformed JSON is rc=2" || bad "A5 expected rc=2, got $rc"

# A6: a manifest with zero detect rows is refused — a vacuous score must never read green.
printf 'P9\tprecision\tx\tfoo\tbar\tnote\n' > "$TMP/empty-manifest.tsv"
out="$(bash "$SCORER" "$TMP/full.json" "$TMP/empty-manifest.tsv" 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && ok "A6 zero-detect-row manifest is refused (rc=2)" || bad "A6 expected rc=2, got $rc"

# ---------- (B) anchor drift guards ----------

[[ -f "$PLAN" ]] && ok "B0 fixture plan present" || bad "B0 fixture plan missing at $PLAN"

grep -qE '(^|[[:space:]])(const|let|var)[[:space:]]+dispatchSchemaAgent' "$RUN_DIR/workflows/code-review.mjs" \
  && bad "B1 code-review.mjs now defines dispatchSchemaAgent — mutant M5 is no longer false; update the fixture" \
  || ok "B1 M5 anchor holds (no dispatchSchemaAgent in code-review.mjs)"

grep -q "withCeiling" "$RUN_DIR/workflows/unit-tests.mjs" \
  && bad "B2 unit-tests.mjs now has withCeiling — mutant M6 is no longer false; update the fixture" \
  || ok "B2 M6 anchor holds (no withCeiling in unit-tests.mjs)"

[[ -e "$SCRIPT_DIR/state-migrate.sh" ]] \
  && bad "B3 tools/state-migrate.sh now exists — the fixture's premise drifted; update the fixture" \
  || ok "B3 M-premise anchor holds (state-migrate.sh absent)"

[[ -e "$RUN_DIR/state-times.md" ]] \
  && bad "B4 state-times.md now exists — mutant M8 is no longer false; update the fixture" \
  || ok "B4 M8 anchor holds (state-times.md absent)"

grep -q "main checkout" "$SCRIPT_DIR/bot-commit.sh" \
  && ok "B5 M2 anchor holds (bot-commit.sh documents main-checkout resolution)" \
  || bad "B5 bot-commit.sh no longer documents main-checkout config resolution — re-verify mutant M2"

grep -qE "Confirm the add applied BEFORE removing" "$SCRIPT_DIR/claim-issue.sh" \
  && ok "B6 M3 anchor holds (claim-issue.sh adds-then-removes with confirm)" \
  || bad "B6 claim-issue.sh ordering doc changed — re-verify mutant M3"

grep -q "Copied verbatim from code-review.mjs" "$RUN_DIR/workflows/stall-probe.mjs" \
  && ok "B7 M4 anchor holds (stall-probe declares the verbatim FINDINGS_SCHEMA copy)" \
  || bad "B7 stall-probe.mjs no longer declares the verbatim copy — re-verify mutant M4"

[[ -e "$RUN_DIR/tools/tracker/jira/README.md" ]] \
  && ok "B8 P1 anchor holds (tracker/jira/README.md exists)" \
  || bad "B8 tracker/jira/README.md vanished — precision trap P1 now mis-scores"

# ---------- (C) manifest sanity ----------

ids="$(grep -v '^#' "$MANIFEST" | cut -f1 | grep -c .)"
uniq_ids="$(grep -v '^#' "$MANIFEST" | cut -f1 | sort -u | grep -c .)"
[[ "$ids" -eq "$uniq_ids" && "$ids" -gt 0 ]] \
  && ok "C1 manifest ids unique ($ids rows)" \
  || bad "C1 duplicate or zero manifest ids ($ids rows, $uniq_ids unique)"

badkind="$(grep -v '^#' "$MANIFEST" | cut -f2 | grep -Ev '^(detect|precision)$' | grep -c . || true)"
[[ "${badkind:-0}" -eq 0 ]] && ok "C2 manifest kinds legal" || bad "C2 illegal kind in manifest"

regex_fail=0
while IFS=$'\t' read -r id _kind _cls regexA regexB _note; do
  case "$id" in ''|\#*) continue ;; esac
  echo probe | grep -Ei -- "$regexA" >/dev/null 2>&1; [[ $? -eq 2 ]] && { regex_fail=$((regex_fail+1)); echo "  bad regexA on $id" >&2; }
  echo probe | grep -Ei -- "$regexB" >/dev/null 2>&1; [[ $? -eq 2 ]] && { regex_fail=$((regex_fail+1)); echo "  bad regexB on $id" >&2; }
done < "$MANIFEST"
[[ "$regex_fail" -eq 0 ]] && ok "C3 all manifest regexes compile" || bad "C3 $regex_fail manifest regexes invalid"

echo "score-review-selftest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
