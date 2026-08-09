#!/usr/bin/env bash
# config-grill-selftest.sh — behavioral selftest for config-grill.sh.
#
# Hermetic: every case builds a throwaway git work tree under mktemp (git ls-files reads the
# INDEX, so `git add` with no commit is enough) plus a config file, and asserts on the JSON
# envelope. No network, no plugin cache, no `claude` binary.
#
# What each case guards is stated at the case, not here. The through-line: a finding must fire
# on a real gap and must NOT fire on a repo where the key is fine — a checker that only ever
# fires is as useless as one that never does.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRILL="$HERE/config-grill.sh"
FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT=""; RC=0

mkrepo() { # $1 label, $2.. tracked file paths → prints the root
  local root="$TMP/$1"; shift
  mkdir -p "$root"
  git -c init.defaultBranch=main init -q "$root" >/dev/null 2>&1
  git -C "$root" config user.email selftest@example.invalid
  git -C "$root" config user.name selftest
  local f
  for f in "$@"; do
    mkdir -p "$root/$(dirname "$f")"
    : > "$root/$f"
    git -C "$root" add -- "$f" >/dev/null 2>&1
  done
  printf '%s' "$root"
}

run_grill() { # $1 root, $2 config path
  RC=0
  OUT="$(bash "$GRILL" "$1" "$2" 2>/dev/null)" || RC=$?
}

_hit() { jq -r --arg i "$1" '.findings[] | select(.id==$i) | .evidence + " ⟂ " + .proposal' <<< "$OUT"; }
_ids() { jq -r '.findings[].id' <<< "$OUT" | tr '\n' ' '; }
_nids() { jq -r '.notEvaluated[].id' <<< "$OUT" | tr '\n' ' '; }

expect_finding() { # $1 label, $2 id, $3.. substrings that must appear in evidence+proposal
  local label="$1" id="$2"; shift 2
  local got s; got="$(_hit "$id")"
  if [[ -z "$got" ]]; then check "$label (no finding '$id'; got: $(_ids))" 1; return; fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<< "$got"; then check "$label (finding '$id' missing '$s')" 1; echo "      $got"; return; fi
  done
  check "$label" 0
}
expect_no_finding() { # $1 label, $2 id
  if [[ -z "$(_hit "$2")" ]]; then check "$1" 0; else check "$1 (unexpected finding '$2')" 1; echo "      $(_hit "$2")"; fi
}
expect_noteval() { # $1 label, $2 id, $3 (optional) substring in reason
  local got; got="$(jq -r --arg i "$2" '.notEvaluated[] | select(.id==$i) | .reason' <<< "$OUT")"
  if [[ -z "$got" ]]; then check "$1 (no notEvaluated '$2'; got: $(_nids))" 1; return; fi
  if [[ -n "${3:-}" ]] && ! grep -qF -- "$3" <<< "$got"; then check "$1 (reason missing '$3')" 1; echo "      $got"; return; fi
  check "$1" 0
}

cfg() { # $1 path ← stdin
  cat > "$1"
}
STD_HEAD='"configVersion": 2, "tracker": {"type":"github"},
  "topology": {"type":"standalone","repos":{"app":{"path":".","baseBranch":"main"}}}'

echo "config-grill selftest:"

# --- AC-2/AC-3: trigger 2, webComponentGlobs -----------------------------------------------
# The motivating case B: the key is never asked about, falls back to the shipped
# apps/web literal, and un-routes a11y + the whole design-fidelity dimension in a repo whose
# FE lives under src/. The RESOLVED DEFAULT must be quoted (never the schema default, which
# nothing injects), and a detected alternative must be offered with its own count.
R="$(mkrepo t2-web-default src/App.tsx src/Button.tsx README.md)"
cfg "$R/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}} }
EOF
run_grill "$R" "$R/c.json"
expect_finding "t2 webComponentGlobs: absent key, default matches nothing" \
  T2.webComponentGlobs "unset; resolved default" "apps/web/**/*.{tsx,jsx}" \
  "matches 0 of the repo's tracked files" "src/**/*.{tsx,jsx}" "matches 2 tracked file(s)"
check "t2 exits 0 with findings present (rc=$RC)" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"

# A hand-set value that matches nothing is the SAME defect (case C's lesson: an adopted value
# can itself be broken), so setting the key wrongly must not silence the check.
cfg "$R/set.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "stageParams": {"webComponentGlobs": ["packages/ui/**/*.vue"]} }
EOF
run_grill "$R" "$R/set.json"
expect_finding "t2 webComponentGlobs: hand-set value matching nothing still fires" \
  T2.webComponentGlobs "configured value" "packages/ui/**/*.vue"

# The negative half. Without it the check could be a constant-true and still pass everything
# above.
R2="$(mkrepo t2-web-match apps/web/App.tsx apps/web/src/app/Page.tsx)"
cfg "$R2/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R2" "$R2/c.json"
expect_no_finding "t2 webComponentGlobs: default matches → silent" T2.webComponentGlobs
expect_no_finding "t2 triggerGlobs: default matches → silent" T2.visualCaptureTriggerGlobs

# No candidate matches either → the finding STILL fires and says so, rather than going quiet
# because the tool could not think of a value.
R3="$(mkrepo t2-no-alt docs/guide.md)"
cfg "$R3/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R3" "$R3/c.json"
expect_finding "t2 webComponentGlobs: no candidate detected → fires and says so" \
  T2.webComponentGlobs "no candidate from the shipped list matched"
# The multi-glob key renders EVERY resolved default, comma-joined — not just the last one.
# This is the one place the four shipped triggerGlobs literals are pinned end to end, which is
# what the DROPPED lockstep entry for these restatements says is exercised here. A consumer
# acts on the glob list in the evidence line; a join that silently drops three of four turns
# the diagnostic into a wrong instruction.
expect_finding "t2 triggerGlobs: the whole resolved default set is rendered, comma-joined" \
  T2.visualCaptureTriggerGlobs \
  "(apps/web/src/app/**/*.{tsx,jsx}, apps/web/src/app/**/*.css, apps/web/src/components/**/*.{tsx,jsx}, apps/web/tailwind.config.{ts,js})"

# --- AC-2/AC-3: trigger 2, formatGlob ------------------------------------------------------
# formatGlob's shape has no "/", and verifyctl matches it with bash `[[ f == $a ]]`, where *
# CROSSES separators. Transliterating * to [^/]* would match only root-level files and fire a
# false zero-match on every repo with sources in a subdirectory — this pair pins that rule.
R4="$(mkrepo t2-format-go main.go pkg/server.go)"
cfg "$R4/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R4" "$R4/c.json"
expect_finding "t2 formatGlob: default matches nothing on a go tree" \
  T2.formatGlob "*.{ts,tsx,js,json,md}" "*.{go,md,json}"
R5="$(mkrepo t2-format-nested src/deep/a.ts)"
cfg "$R5/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R5" "$R5/c.json"
expect_no_finding "t2 formatGlob: slash-free glob crosses separators (src/deep/a.ts)" T2.formatGlob

# --- AC-2: trigger 2, visualCapture.triggerGlobs -------------------------------------------
cfg "$R5/vc.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "stageParams": {"visualCapture": {"triggerGlobs": ["apps/web/**/*.css"]}} }
EOF
run_grill "$R5" "$R5/vc.json"
expect_finding "t2 triggerGlobs: hand-set value matching nothing fires" \
  T2.visualCaptureTriggerGlobs "configured value" "apps/web/**/*.css"

# --- AC-2: the DROPPED rows are dropped, not silently implemented --------------------------
# planFilePattern names a file Stage 3 CREATES and paths.* name dirs a fresh repo lacks, so a
# "zero matches" rule on them would fire universally. Nothing may emit a finding for them.
cfg "$R3/dropped.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "paths": {"plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state"},
  "stageParams": {"planFilePattern": "{plansDir}/plan-{issueKey}.md",
                  "inertPattern": "(\\\\.md\$)"} }
EOF
run_grill "$R3" "$R3/dropped.json"
for dropped in T2.planFilePattern T2.plansDir T2.pipelineStateDir T2.inertPattern; do
  expect_no_finding "t2 dropped row stays dropped: $dropped" "$dropped"
done

# --- AC-4: trigger 4 -----------------------------------------------------------------------
R6="$(mkrepo t4 apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cfg "$R6/scope-no-runner.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":"src/**","testFile":null}} }
EOF
run_grill "$R6" "$R6/scope-no-runner.json"
expect_finding "t4 unitTestScope set + testFile null" \
  T4.testfile-plumbing.app "commands.app.unitTestScope is set" "testFile is null"

# gates.mutation follows RUNTIME semantics: `.gates.mutation // empty` means only the literal
# false is the off-switch, so ABSENT IS NOT FALSE. The finding must say which state it found —
# a check keyed to `== true` alone would miss the far commoner absent case entirely.
cfg "$R6/mut-absent.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}} }
EOF
run_grill "$R6" "$R6/mut-absent.json"
expect_finding "t4 gates.mutation absent (absent is not false) + no scope" \
  T4.mutation-plumbing.app "absent" "NOT false"
cfg "$R6/mut-true.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null}}, "gates": {"mutation": true} }
EOF
run_grill "$R6" "$R6/mut-true.json"
expect_finding "t4 gates.mutation true + no scope" T4.mutation-plumbing.app "gates.mutation is true"
cfg "$R6/mut-false.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null}}, "gates": {"mutation": false} }
EOF
run_grill "$R6" "$R6/mut-false.json"
expect_no_finding "t4 gates.mutation false is the declared off-switch → silent" T4.mutation-plumbing.app
cfg "$R6/mut-ok.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":"src/**","testFile":"yarn vitest run {file}"}} }
EOF
run_grill "$R6" "$R6/mut-ok.json"
expect_no_finding "t4 fully plumbed → no mutation finding" T4.mutation-plumbing.app
expect_no_finding "t4 fully plumbed → no testFile finding" T4.testfile-plumbing.app

cfg "$R6/design-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "design": {"provider": "figma"} }
EOF
run_grill "$R6" "$R6/design-bare.json"
expect_finding "t4 design.provider set + liveRender absent" T4.design-liverender "figma"
cfg "$R6/design-armed.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "design": {"provider": "figma", "liveRender": {"command": "yarn render:verify --route {route} --out {out}"}} }
EOF
run_grill "$R6" "$R6/design-armed.json"
expect_no_finding "t4 design armed with liveRender → silent" T4.design-liverender

# --- AC-5: trigger 5 -----------------------------------------------------------------------
# Case C: `yarn test {file}` LOOKS fine; scripts.test = "vitest" underneath is what hangs. The
# watcher test therefore runs on the manifest script BODY, never the configured string.
R7="$(mkrepo t5-watch apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cat > "$R7/package.json" <<'EOF'
{ "name": "t5", "scripts": {
    "test": "vitest",
    "test:run": "vitest run",
    "watchy": "jest --watch",
    "dev": "next dev",
    "serve": "webpack serve",
    "mon": "nodemon server.js",
    "vitepreview": "vite build",
    "lint": "eslint .",
    "wrapped": "npx vitest" } }
EOF
cfg "$R7/c.json" <<EOF
{ $STD_HEAD,
  "commands": {"app":{
    "testFile": "yarn test {file}",
    "test": "yarn test:run",
    "lint": "npm run lint",
    "typecheck": null,
    "format": "yarn vitepreview",
    "lanes": [{"name":"setup","commands":["yarn watchy","yarn mon"]}],
    "extraLanes": [{"name":"extra","commands":["pnpm dev","bun serve","npm run wrapped"],"failureClass":"TYPE_ERROR"}]}} }
EOF
run_grill "$R7" "$R7/c.json"
expect_finding "t5 watcher: bare vitest under a fine-looking testFile" \
  T5.watcher.app.testFile 'scripts.test = "vitest"' "never exits"
expect_no_finding "t5 non-watcher: vitest run" T5.watcher.app.test
expect_no_finding "t5 non-watcher: eslint ." T5.watcher.app.lint
expect_no_finding "t5 non-watcher: vite build" T5.watcher.app.format
expect_finding "t5 watcher: jest --watch (lanes slot)"        T5.watcher.app.lanes.0.0 "jest --watch"
expect_finding "t5 watcher: nodemon (lanes slot)"             T5.watcher.app.lanes.0.1 "nodemon"
expect_finding "t5 watcher: next dev (extraLanes slot)"       T5.watcher.app.extraLanes.0.0 "next dev"
expect_finding "t5 watcher: webpack serve (extraLanes slot)"  T5.watcher.app.extraLanes.0.1 "webpack serve"
expect_finding "t5 watcher: npx-wrapped vitest"               T5.watcher.app.extraLanes.0.2 "npx vitest"

# The missing-script half fires ONLY on the unambiguous `<pm> run <name>` form. `<pm> <name>`
# without the run verb may be a built-in subcommand (yarn workspaces, pnpm dlx), and a false
# FAIL on a valid config is a worse outcome than a missed warning.
R8="$(mkrepo t5-resolve apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cat > "$R8/package.json" <<'EOF'
{ "name": "t5b", "scripts": { "test": "vitest run" } }
EOF
cfg "$R8/c.json" <<EOF
{ $STD_HEAD,
  "commands": {"app":{
    "lint": "npm run lint",
    "test": "yarn workspaces foreach -A run test",
    "typecheck": "npx tsc --noEmit",
    "format": "yarn prettier --write ."}} }
EOF
run_grill "$R8" "$R8/c.json"
expect_finding "t5 missing script: explicit \`npm run lint\` with no scripts.lint" \
  T5.missing-script.app.lint "no scripts.lint"
expect_noteval "t5 ambiguous \`yarn workspaces …\` → not evaluated" T5.app.test "ambiguous"
expect_no_finding "t5 ambiguous form is never flagged" T5.missing-script.app.test
expect_noteval "t5 non-pm \`npx tsc\` → not evaluated" T5.app.typecheck "not an unambiguous"
expect_noteval "t5 \`yarn prettier\` (no run verb, not a script) → not evaluated" T5.app.format "ambiguous"

# No manifest at all (python/go/rust/bun consumers): trigger 5 must state non-evaluation
# rather than pass silently — and the notice must NOT ride in findings[], which would deadlock
# onboard's accept predicate (a notEvaluated entry has no proposal and cannot be waived).
R9="$(mkrepo t5-nomanifest apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cfg "$R9/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "pytest", "lint": "ruff check ."}} }
EOF
run_grill "$R9" "$R9/c.json"
expect_noteval "t5 no root package.json → non-evaluation" T5.app "no readable root package.json"
if [[ "$(jq -r '[.findings[] | select(.id | startswith("T5."))] | length' <<< "$OUT")" == "0" ]]; then
  check "t5 non-evaluation emits no finding (accept predicate stays reachable)" 0
else
  check "t5 non-evaluation leaked into findings[]" 1
fi

# --- AC-1: multi-repo scoping --------------------------------------------------------------
# The evaluated repo is the one whose topology path resolves to the root we were handed; a
# sibling checkout is REPORTED, never reached — both callers are cwd-scoped and reading a
# sibling means touching directories outside that root.
RP="$(mkrepo scoping-be apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
mkdir -p "$TMP/scoping-fe"
cfg "$RP/c.json" <<'EOF'
{ "configVersion": 2, "tracker": {"type":"github"},
  "topology": {"type":"be-fe-pair","repos":{
    "be": {"path":".","baseBranch":"main"},
    "fe": {"path":"../scoping-fe","baseBranch":"main"}}},
  "commands": {"be":{"unitTestScope":"src/**","testFile":null},
               "fe":{"unitTestScope":"src/**","testFile":null}} }
EOF
run_grill "$RP" "$RP/c.json"
expect_finding "scoping: the evaluated repo IS checked" T4.testfile-plumbing.be "commands.be"
expect_no_finding "scoping: the sibling repo is NOT checked" T4.testfile-plumbing.fe
expect_noteval "scoping: the sibling is reported as not-evaluated" topology.fe "sibling checkout"

# --- AC-6: waiver suppression --------------------------------------------------------------
# Keyed by CHECK ID with the repo id where the check is per-repo. A waived finding is
# suppressed by the checker itself, so both callers suppress identically.
cfg "$R/waived.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}},
  "grillWaivers": {
    "T2.webComponentGlobs": "no web-component surface in this repo",
    "T4.mutation-plumbing.app": "no unit-test surface yet; tracked in the backlog" } }
EOF
run_grill "$R" "$R/waived.json"
expect_no_finding "waiver: T2.webComponentGlobs suppressed" T2.webComponentGlobs
expect_no_finding "waiver: T4.mutation-plumbing.app suppressed (repo-scoped id)" T4.mutation-plumbing.app
expect_finding "waiver: an UNwaived finding still fires" T2.visualCaptureTriggerGlobs "triggerGlobs"

# A waiver keyed WITHOUT the repo id must not silence a per-repo check — that is the whole
# reason the id carries the repo (a bare id would silence every repo at once).
cfg "$R/waived-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}},
  "grillWaivers": { "T4.mutation-plumbing": "bare id, wrong shape" } }
EOF
run_grill "$R" "$R/waived-bare.json"
expect_finding "waiver: a repo-less id does NOT silence a per-repo check" T4.mutation-plumbing.app

# --- AC-1: exit codes ----------------------------------------------------------------------
run_grill "$R" "$R/nope.json"
check "exit 3 on a missing config path (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
printf 'not json' > "$R/bad.json"
run_grill "$R" "$R/bad.json"
check "exit 3 on a non-JSON config (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
RC=0; bash "$GRILL" >/dev/null 2>&1 || RC=$?
check "exit 3 with no arguments (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
RC=0; OUT="$(bash "$GRILL" "$R2" "$R2/c.json" 2>/dev/null)" || RC=$?
if [[ "$RC" -eq 0 ]] && jq -e '(.findings | type == "array") and (.notEvaluated | type == "array")' <<< "$OUT" >/dev/null; then
  check "envelope: two arrays, exit 0, on a clean repo" 0
else
  check "envelope: two arrays, exit 0, on a clean repo (rc=$RC)" 1
fi

if [[ "$FAILS" -gt 0 ]]; then echo "config-grill selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-grill selftest: all green"
