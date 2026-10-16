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
STD_HEAD='"configVersion": 3, "tracker": {"type":"github"}'

echo "config-grill selftest:"

# --- AC-2/AC-3: trigger 2, webComponentGlobs -----------------------------------------------
# An absent key resolves to the repo-wide default (#1076 AC-7), so it fires only where the repo's
# components carry an extension the default does not list: here an Angular tree of .html + .ts.
# The RESOLVED DEFAULT must be quoted (never the schema default, which nothing injects), and a
# detected alternative must be offered with its own count.
R="$(mkrepo t2-web-default src/app/app.component.html src/app/app.component.ts README.md)"
cfg "$R/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R" "$R/c.json"
expect_finding "t2 webComponentGlobs: absent key, default matches nothing" \
  T2.webComponentGlobs "unset; resolved default" "(**/*.{tsx,jsx,vue,svelte,css,scss,less})" \
  "matches 0 of the repo's tracked files" "src/app/**/*.{html,ts}" "matches 2 tracked file(s)"
check "t2 exits 0 with findings present (rc=$RC)" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"

# #1076 AC-7: the default is repo-wide. The motivating case B: a repo whose FE lives under src/
# and that never set the key. The old apps/web default matched nothing there and un-routed a11y
# and the whole design-fidelity dimension; the absent key now covers it. One repo PER extension,
# each component nested where no shipped candidate reaches it, so dropping any one extension from
# the default fails exactly its own case.
for ext in tsx jsx vue svelte css scss less; do
  RDF="$(mkrepo "t2-default-$ext" "packages/ui/src/widget.$ext" README.md)"
  cfg "$RDF/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
  run_grill "$RDF" "$RDF/c.json"
  expect_no_finding "t2 webComponentGlobs: absent key, the default covers a nested .$ext" T2.webComponentGlobs
done
RDF="$(mkrepo t2-default-src src/App.tsx src/Button.tsx README.md)"
cfg "$RDF/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$RDF" "$RDF/c.json"
expect_no_finding "t2 webComponentGlobs: absent key, a src/ React tree is covered" T2.webComponentGlobs

# A hand-set value that matches nothing is the SAME defect (case C's lesson: an adopted value
# can itself be broken), so setting the key wrongly must not silence the check.
cfg "$R/set.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": ["packages/ui/**/*.vue"]} }
EOF
run_grill "$R" "$R/set.json"
expect_finding "t2 webComponentGlobs: hand-set value matching nothing still fires" \
  T2.webComponentGlobs "configured value" "packages/ui/**/*.vue"
# The key lives under reviewers now. A leftover stageParams copy — even one that matches — is
# not what review-lead reads, so it must not silence the check; the matching reviewers copy must.
cfg "$R/leftover.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "stageParams": {"webComponentGlobs": ["src/app/**/*.html"]} }
EOF
run_grill "$R" "$R/leftover.json"
expect_finding "t2 webComponentGlobs: a leftover stageParams value is not read" \
  T2.webComponentGlobs "reviewers.webComponentGlobs — unset; resolved default"
cfg "$R/moved.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": ["src/app/**/*.html"]} }
EOF
run_grill "$R" "$R/moved.json"
expect_no_finding "t2 webComponentGlobs: reviewers.webComponentGlobs matching → silent" T2.webComponentGlobs

# An explicit [] is a declaration, not an omission (#1076 follow-up D-22): the repo says it has
# no web-component surface, review-lead routes neither reviewer on an unarmed diff, and the grill
# has nothing to propose. It lands in notEvaluated[] whether or not the tree holds a UI file —
# the UI-present shape is the one that used to read as "unset" and silently take the default.
RE="$(mkrepo t2-empty-ui src/App.tsx README.md)"
cfg "$RE/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": []} }
EOF
run_grill "$RE" "$RE/c.json"
expect_no_finding "t2 webComponentGlobs: explicit [] is a declared no-surface, not a finding" T2.webComponentGlobs
expect_noteval "t2 webComponentGlobs: explicit [] with a UI file lands in notEvaluated" T2.webComponentGlobs "set to []"
RE2="$(mkrepo t2-empty-noui README.md)"
cfg "$RE2/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": []} }
EOF
run_grill "$RE2" "$RE2/c.json"
expect_noteval "t2 webComponentGlobs: explicit [] with no UI file lands in notEvaluated as declared" T2.webComponentGlobs "set to []"

# The negative half. Without it the check could be a constant-true and still pass everything
# above.
R2="$(mkrepo t2-web-match apps/web/App.tsx apps/web/src/app/Page.tsx)"
cfg "$R2/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R2" "$R2/c.json"
expect_no_finding "t2 webComponentGlobs: default matches → silent" T2.webComponentGlobs

# No candidate matches either → the finding STILL fires and says so, rather than going quiet
# because the tool could not think of a value. The tree has to carry a real component somewhere
# no candidate reaches, with an extension the default does not list: this is the arm the
# applicability probe sits next to, so a probe that over-reached would silence exactly this case.
R3B="$(mkrepo t2-web-nocand pkg/ui/Widget.astro docs/guide.md)"
cfg "$R3B/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R3B" "$R3B/c.json"
expect_finding "t2 webComponentGlobs: no candidate detected → fires and says so" \
  T2.webComponentGlobs "no candidate from the shipped list matched"
# A multi-valued key renders EVERY glob, comma-joined — not just the last one. A consumer acts
# on the glob list in the evidence line, so a join that silently drops all but one turns the
# diagnostic into a wrong instruction. With the triggerGlobs row deleted, webComponentGlobs is
# the only multi-valued row left, so this is the one place join_c meets more than one element.
cfg "$R3B/multi.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": ["apps/web/**/*.css", "apps/legacy/**/*.vue"]} }
EOF
run_grill "$R3B" "$R3B/multi.json"
expect_finding "t2 webComponentGlobs: every configured glob is rendered, comma-joined" \
  T2.webComponentGlobs "(apps/web/**/*.css, apps/legacy/**/*.vue)"

# --- the applicability probe: a repo that renders nothing ----------------------------------
# A shell/CLI/library consumer has no rendering surface at all, so the absent glob is a
# measured fact, not an omission. It must land in notEvaluated[] — no proposal — rather than a
# finding that asks for a value the repo cannot have.
R3="$(mkrepo t2-renders-nothing docs/guide.md scripts/build.sh)"
cfg "$R3/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R3" "$R3/c.json"
expect_noteval "probe: webComponentGlobs not evaluated on a repo that renders nothing" \
  T2.webComponentGlobs "applicability probe"
expect_no_finding "probe: webComponentGlobs emits no finding there" T2.webComponentGlobs
check "probe: exits 0 (rc=$RC)" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"

# The probe list is an allowlist, and an allowlist reviewed as prose reads as a single rule — a
# member nothing exercises can be dropped in a later edit with every case still green. One repo
# PER member, so removing any one extension fails exactly its own case. Each file sits at the
# root, where neither the configured value nor any shipped candidate reaches it: the finding
# that fires is therefore the probe holding the check open, not a candidate rescuing it. The key
# is SET because the repo-wide default already covers most members, and a glob that matches is
# applicable by demonstration — it never consults the probe.
for ext in tsx jsx vue svelte astro html css scss sass less; do
  RPB="$(mkrepo "probe-$ext" "widget.$ext")"
  cfg "$RPB/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "reviewers": {"webComponentGlobs": ["packages/ui/**/*.vue"]} }
EOF
  run_grill "$RPB" "$RPB/c.json"
  expect_finding "probe member .$ext holds the web checks open" \
    T2.webComponentGlobs "matches 0 of the repo's tracked files"
done
# ...and the two deliberate EXCLUSIONS, which are why the probe is extension-shaped rather than
# "any source file": counting .ts/.js would keep it open for every TypeScript repo, i.e. for the
# exact shape it exists to convert. Dropping them from the exclusion set fails here.
for ext in ts js; do
  RPX="$(mkrepo "probe-not-$ext" "app.$ext")"
  cfg "$RPX/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
  run_grill "$RPX" "$RPX/c.json"
  expect_noteval "probe non-member .$ext does not hold the web checks open" \
    T2.webComponentGlobs "applicability probe"
  expect_no_finding "probe non-member .$ext emits no finding" T2.webComponentGlobs
done

# --- AC-4: the deleted ids are GONE from every envelope array -------------------------------
# Deleted outright, not merely silenced: each id's subject key has left the config. This fixture
# deliberately KEEPS the retired keys — it replays the exact shape that made every id fire
# before (a hand-set triggerGlobs and a formatGlob matching nothing, plus a unitTestScope with a
# null testFile), so a re-introduction lands here rather than nowhere. The grill runs on drafts
# pre-lint, so the schema retirement does not blank the probe. Checked across both arrays:
# re-appearing as a notEvaluated entry is the same regression wearing a different severity.
cfg "$R/deleted.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":"src/**","testFile":null}},
  "stageParams": {"visualCapture": {"triggerGlobs": ["apps/web/**/*.css"]}, "formatGlob": "*.{rs,toml}"} }
EOF
run_grill "$R" "$R/deleted.json"
for gone in T2.visualCaptureTriggerGlobs T4.testfile-plumbing.app T2.formatGlob; do
  if [[ -z "$(jq -r --arg i "$gone" \
       '(.findings + .notEvaluated)[] | select(.id==$i) | .id' <<< "$OUT")" ]]; then
    check "deleted id emits nothing anywhere in the envelope: $gone" 0
  else
    check "deleted id came back: $gone" 1
  fi
done

# --- AC-2: the DROPPED rows are dropped, not silently implemented --------------------------
# planFilePattern names a file the run CREATES and paths.* name dirs a fresh repo lacks, so a
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

# --- AC-4: trigger 4, design.liverender -----------------------------------------------------
R6="$(mkrepo t4 apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"

cfg "$R6/design-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "design": {"provider": "figma"} }
EOF
run_grill "$R6" "$R6/design-bare.json"
expect_finding "t4 design.provider set + liveRender absent" T4.design-liverender "figma" "smokeCommand"
cfg "$R6/design-armed.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "design": {"provider": "figma", "liveRender": {"command": "yarn render:verify --route {route} --out {out}"}} }
EOF
run_grill "$R6" "$R6/design-armed.json"
expect_no_finding "t4 design armed with liveRender → silent" T4.design-liverender

# A backend root whose config carries `design.provider` while the render harness lives in the
# frontend checkout. Byte-identical config to the R6 case above that DOES fire, so the tracked
# file set is the only difference between them.
R6B="$(mkrepo t4-be src/main.ts src/orders/orders.service.ts package.json)"
cfg "$R6B/design-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "design": {"provider": "figma"} }
EOF
run_grill "$R6B" "$R6B/design-bare.json"
expect_no_finding "t4 design.provider on a root that renders nothing → no FAIL" T4.design-liverender
expect_noteval "t4 design.provider on a root that renders nothing → not evaluated" \
  T4.design-liverender "rendering-surface probe"

# Suppression requires CONFIDENCE: outside a readable work tree the probe cannot speak, and a
# silent retirement of the design axis on a repo that DOES own the harness is the worse error.
# Over-firing is the cheaper one, so the finding stands.
R6N="$TMP/t4-nongit"; mkdir -p "$R6N/src"; : > "$R6N/src/main.ts"
cfg "$R6N/design-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "design": {"provider": "figma"} }
EOF
run_grill "$R6N" "$R6N/design-bare.json"
expect_finding "t4 design.provider outside a work tree → finding stands" T4.design-liverender "figma"

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
    "wrapped": "npx vitest",
    "fmt": "prettier -w .",
    "vrun": "vitest --run",
    "tscw": "tsc -w" } }
EOF
cfg "$R7/c.json" <<EOF
{ $STD_HEAD,
  "commands": {"app":{
    "test": "yarn test:run",
    "lint": "npm run lint",
    "typecheck": null,
    "format": "yarn vitepreview",
    "lanes": [{"name":"setup","commands":["yarn watchy","yarn mon","yarn fmt","yarn vrun","yarn tscw","yarn test"]}],
    "extraLanes": [{"name":"extra","commands":["pnpm dev","bun serve","npm run wrapped"],"failureClass":"TYPE_ERROR"}]}} }
EOF
run_grill "$R7" "$R7/c.json"
# Case C's oracle rode the testFile slot until #574 retired the key: `yarn test` LOOKS
# fine and scripts.test = "vitest" underneath is what hangs, so the probe now rides a
# lanes command — same manifest-body resolution, different slot.
expect_finding "t5 watcher: bare vitest behind a fine-looking yarn alias (lanes slot)" \
  T5.watcher.app.lanes.0.5 'scripts.test = "vitest"' "never exits"
expect_no_finding "t5 non-watcher: vitest run" T5.watcher.app.test
expect_no_finding "t5 non-watcher: eslint ." T5.watcher.app.lint
expect_no_finding "t5 non-watcher: vite build" T5.watcher.app.format
expect_finding "t5 watcher: jest --watch (lanes slot)"        T5.watcher.app.lanes.0.0 "jest --watch"
expect_finding "t5 watcher: nodemon (lanes slot)"             T5.watcher.app.lanes.0.1 "nodemon"
expect_finding "t5 watcher: next dev (extraLanes slot)"       T5.watcher.app.extraLanes.0.0 "next dev"
expect_finding "t5 watcher: webpack serve (extraLanes slot)"  T5.watcher.app.extraLanes.0.1 "webpack serve"
expect_finding "t5 watcher: npx-wrapped vitest"               T5.watcher.app.extraLanes.0.2 "npx vitest"

# The two shapes the AC-5 narrowings exclude. Each is a script a mainstream repo really ships,
# and each was a finding on a valid config before the qualification: prettier's `-w` is
# `--write`, and vitest's `--run` is the flag spelling of the exiting `run` subcommand. A false
# finding is worse than a missed warning here: the consumer can do nothing about it.
expect_no_finding "t5 non-watcher: prettier -w (-w is --write, not watch)" T5.watcher.app.lanes.0.2
expect_no_finding "t5 non-watcher: vitest --run (flag spelling of the run subcommand)" T5.watcher.app.lanes.0.3
# ...and the rule the first of those narrows must still FIRE where -w really is watch, or the
# narrowing would have deleted the rule rather than qualified it.
expect_finding "t5 watcher: -w on a runner that defines it as watch (tsc)" \
  T5.watcher.app.lanes.0.4 "tsc -w"

# The `-w` allowlist, one case PER MEMBER rather than one for the bullet. An allowlist reviewed
# as prose reads as a single rule, so a member that fails the very predicate it instantiates
# ships unexecuted — which is exactly how `jest` got in: its `-w` is `--maxWorkers`, and
# `watch`/`watchAll` carry no alias, so `jest -w 4` was a finding on an ordinary script.
# Every membership below was decided against that runner's own CLI, not the flag's spelling.
R7b="$(mkrepo t5-wmatrix apps/web/App.tsx a.ts)"
cat > "$R7b/package.json" <<'EOF'
{ "name": "t5c", "scripts": {
    "w0":  "vitest bench -w",
    "w1":  "vite build -w",
    "w2":  "tsc -w",
    "w3":  "webpack -w",
    "w4":  "rollup -c -w",
    "w5":  "ava -w",
    "w6":  "mocha -w",
    "w7":  "sass -w src:dist",
    "w8":  "jest -w 4",
    "w9":  "tsup -w",
    "w10": "esbuild app.ts --bundle -w",
    "w11": "parcel build -w",
    "w12": "karma start -w",
    "w13": "nodemon -w src server.js" } }
EOF
cfg "$R7b/c.json" <<EOF
{ $STD_HEAD,
  "commands": {"app":{
    "lanes": [{"name":"wmatrix","commands":[
      "yarn w0","yarn w1","yarn w2","yarn w3","yarn w4","yarn w5","yarn w6","yarn w7",
      "yarn w8","yarn w9","yarn w10","yarn w11","yarn w12","yarn w13"]}]}} }
EOF
run_grill "$R7b" "$R7b/c.json"
# Members: each defines -w as watch, so each must FIRE. vitest/vite reach this arm only past an
# exiting subcommand — without one the earlier vitest/vite arm answers first.
expect_finding "t5 -w member vitest (vitest bench -w)" T5.watcher.app.lanes.0.0  "vitest bench -w"
expect_finding "t5 -w member vite (vite build -w)"     T5.watcher.app.lanes.0.1  "vite build -w"
expect_finding "t5 -w member tsc"                      T5.watcher.app.lanes.0.2  "tsc -w"
expect_finding "t5 -w member webpack"                  T5.watcher.app.lanes.0.3  "webpack -w"
expect_finding "t5 -w member rollup"                   T5.watcher.app.lanes.0.4  "rollup -c -w"
expect_finding "t5 -w member ava"                      T5.watcher.app.lanes.0.5  "ava -w"
expect_finding "t5 -w member mocha"                    T5.watcher.app.lanes.0.6  "mocha -w"
expect_finding "t5 -w member sass"                     T5.watcher.app.lanes.0.7  "sass -w src:dist"
# Non-members: each fails the predicate, so firing on any of them is a finding on a valid config.
# `jest` is the one that was harmful — the other four read no `-w` at all, so they were inert.
expect_no_finding "t5 -w non-member jest (-w is --maxWorkers, not watch)" T5.watcher.app.lanes.0.8
expect_no_finding "t5 -w non-member tsup (--watch only, no -w)"           T5.watcher.app.lanes.0.9
expect_no_finding "t5 -w non-member esbuild (--watch only, no -w)"        T5.watcher.app.lanes.0.10
expect_no_finding "t5 -w non-member parcel (watch is a subcommand)"       T5.watcher.app.lanes.0.11
expect_no_finding "t5 -w non-member karma (--auto-watch only)"            T5.watcher.app.lanes.0.12
# ...and `nodemon` still fires with a bare `-w`, via the token rule that owns it — which is why
# dropping it from the allowlist as unreachable changed no answer.
expect_finding "t5 nodemon -w still fires through the token rule" \
  T5.watcher.app.lanes.0.13 "nodemon -w src server.js"

# The missing-script half fires ONLY on the unambiguous `<pm> run <name>` form. `<pm> <name>`
# without the run verb may be a built-in subcommand (yarn workspaces, pnpm dlx), and a false
# finding on a valid config is a worse outcome than a missed warning.
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
# rather than pass silently — and the notice must NOT ride in findings[]: it has no proposal.
R9="$(mkrepo t5-nomanifest apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cfg "$R9/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "pytest", "lint": "ruff check ."}} }
EOF
run_grill "$R9" "$R9/c.json"
expect_noteval "t5 no root package.json → non-evaluation" T5.app "no readable root package.json"
if [[ "$(jq -r '[.findings[] | select(.id | startswith("T5."))] | length' <<< "$OUT")" == "0" ]]; then
  check "t5 non-evaluation emits no finding" 0
else
  check "t5 non-evaluation leaked into findings[]" 1
fi

# --- AC-1: which commands entry is evaluated ------------------------------------------------
# /dev-pipeline:run reads the sole `commands` key, else the key named after the checkout's
# directory. The grill inspects exactly that entry; every other one is REPORTED, never reached.
RP="$(mkrepo scoping-be apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
cat > "$RP/package.json" <<'EOF'
{ "name": "scoping-be", "scripts": {} }
EOF
cfg "$RP/c.json" <<'EOF'
{ "configVersion": 3, "tracker": {"type":"github"},
  "commands": {"scoping-be":{"lint":"npm run lint"},
               "scoping-fe":{"lint":"npm run lint"}} }
EOF
run_grill "$RP" "$RP/c.json"
expect_finding "scoping: the entry named after the checkout IS checked" T5.missing-script.scoping-be.lint "no scripts.lint"
expect_no_finding "scoping: another checkout's entry is NOT checked" T5.missing-script.scoping-fe.lint
expect_noteval "scoping: another checkout's entry is reported as not-evaluated" commands.scoping-fe "reads commands.scoping-be"

# A sole key is read whatever it is called — the directory name only breaks a tie.
cfg "$RP/sole.json" <<'EOF'
{ "configVersion": 3, "tracker": {"type":"github"}, "commands": {"api":{"lint":"npm run lint"}} }
EOF
run_grill "$RP" "$RP/sole.json"
expect_finding "scoping: a sole commands key is checked whatever its name" T5.missing-script.api.lint "no scripts.lint"

# Two keys, neither named after the checkout: the lane reads no entry, so none is inspected and
# each is reported rather than one being picked.
cfg "$RP/none.json" <<'EOF'
{ "configVersion": 3, "tracker": {"type":"github"},
  "commands": {"be":{"lint":"npm run lint"}, "fe":{"lint":"npm run lint"}} }
EOF
run_grill "$RP" "$RP/none.json"
expect_no_finding "scoping: no entry named after the checkout → be not checked" T5.missing-script.be.lint
expect_no_finding "scoping: no entry named after the checkout → fe not checked" T5.missing-script.fe.lint
expect_noteval "scoping: each entry is reported when none is named after the checkout" commands.be "none is named after this checkout's directory"

# A linked worktree resolves to its MAIN checkout's name, as the lane does: the worktree's own
# directory name is not a commands key anyone writes.
git -C "$RP" add package.json >/dev/null 2>&1
git -C "$RP" commit -qm base >/dev/null 2>&1
git -C "$RP" worktree add -q "$TMP/scoping-wt-elsewhere" >/dev/null 2>&1
cp "$RP/c.json" "$TMP/scoping-wt-elsewhere/c.json"
run_grill "$TMP/scoping-wt-elsewhere" "$TMP/scoping-wt-elsewhere/c.json"
expect_finding "scoping: a linked worktree reads its main checkout's entry" T5.missing-script.scoping-be.lint "no scripts.lint"

# --- #1063: trigger 6, testRunners on a vitest or jest repo ----------------------------------
# The proposed entry is only worth drafting if the lint the config must pass accepts it, so each
# `value` goes through dev-pipeline's config-lint.sh inside a real config, never a stub. The lockfile
# shapes are the three package managers' own: yarn berry and v1 entry headers, pnpm's packages
# keys, npm's `packages["node_modules/<name>"]` (v2/v3) and `dependencies` (v1).
# config-lint sits in the sibling plugin: plugins/dev-pipeline/ in the repo, and
# <cache>/dev-pipeline/<version>/ in an install, one directory deeper.
LINT="$HERE/../../../../dev-pipeline/tools/config-lint.sh"
if [[ ! -f "$LINT" ]]; then
  for LINT in "$HERE"/../../../../../dev-pipeline/*/tools/config-lint.sh; do :; done
fi
_val() { jq -c --arg i "$1" '.findings[] | select(.id==$i) | .value // empty' <<< "$OUT"; }
expect_value() { # $1 label, $2 id, $3 format, $4 command, $5.. globs the `when` must hold
  local label="$1" id="$2" fmt="$3" cmd="$4" v g; shift 4
  v="$(_val "$id")"
  if [[ -z "$v" ]]; then check "$label (finding '$id' carries no value; got: $(_ids))" 1; return; fi
  if [[ "$(jq -r '.format' <<< "$v")" != "$fmt" || "$(jq -r '.command' <<< "$v")" != "$cmd" ]]; then
    check "$label (value is $v)" 1; return
  fi
  for g in "$@"; do
    jq -e --arg g "$g" '.when | index([$g])' <<< "$v" >/dev/null || { check "$label (when lacks '$g': $v)" 1; return; }
  done
  # The proposal embeds the same JSON, so doctor's prose rendering shows the exact entry.
  if ! jq -e --arg v "$v" '.findings[] | select(.id=="'"$id"'") | .proposal | contains($v)' <<< "$OUT" >/dev/null; then
    check "$label (the proposal does not embed the value)" 1; return
  fi
  jq -n --argjson v "$v" '{configVersion: 3, tracker: {type: "github"}, commands: {app: {testRunners: [$v]}}}' > "$TMP/lint-value.json"
  if bash "$LINT" "$TMP/lint-value.json" >/dev/null 2>"$TMP/lint-value.err"; then check "$label" 0
  else check "$label (config-lint refuses the value: $(head -3 "$TMP/lint-value.err" | tr '\n' ' '))" 1; fi
}

# AC-1: vitest behind yarn berry, the configured form. scripts.test IS one run of vitest, so the
# entry extends `yarn test`. `@vitest/ui` sits in the lockfile with another version: a parse that
# reads it as vitest names the wrong version.
RV="$(mkrepo t6-vitest-berry src/a.test.ts src/b.spec.tsx src/c.ts README.md)"
cat > "$RV/package.json" <<'EOF'
{ "name": "v", "scripts": { "test": "vitest run", "test:e2e": "vitest run -c vitest.e2e.config.ts",
    "test:int": "vitest --config=vitest.int.ts run", "lint": "eslint ." },
  "devDependencies": { "vitest": "^3.2.4", "@vitest/ui": "^9.9.9" } }
EOF
cat > "$RV/yarn.lock" <<'EOF'
__metadata:
  version: 8

"@vitest/ui@npm:^9.9.9":
  version: 9.9.9
  resolution: "@vitest/ui@npm:9.9.9"

"vitest@npm:^3.0.0, vitest@npm:^3.2.4":
  version: 3.2.4
  resolution: "vitest@npm:3.2.4"
EOF
cfg "$RV/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn test"}} }
EOF
run_grill "$RV" "$RV/c.json"
expect_finding "t6 vitest: the evidence names vitest and its yarn berry version" \
  T6.testRunners.app "commands.app.testRunners has no entry" "depends on vitest, 3.2.4 (yarn.lock)" \
  "match 2 tracked file(s)"
if grep -qF "9.9.9" <<< "$(_hit T6.testRunners.app)"; then check "t6 vitest: @vitest/ui's version is not read as vitest's" 1
else check "t6 vitest: @vitest/ui's version is not read as vitest's" 0; fi
expect_value "t6 vitest: the value is a vitest-json entry config-lint accepts, extending commands.app.test" \
  T6.testRunners.app vitest-json "yarn test --reporter=json --outputFile={report} --bail=0 {files}" \
  "*.test.ts" "*.spec.tsx" "*.test.mjs" "*.spec.cts"
# Default patterns only: jest's __tests__ directory is not vitest's default.
if jq -e '.when | index(["*__tests__/*.ts"])' <<< "$(_val T6.testRunners.app)" >/dev/null; then
  check "t6 vitest: when holds no jest-only __tests__ pattern" 1
else check "t6 vitest: when holds no jest-only __tests__ pattern" 0; fi
# AC-5: the two other scripts run vitest with their own config; scripts.test is the entry itself.
expect_finding "t6 vitest: second suites are named as not covered" T6.testRunners.app \
  "Not covered by the proposed entry: scripts.test:e2e (\"vitest run -c vitest.e2e.config.ts\"), scripts.test:int (\"vitest --config=vitest.int.ts run\")"
if grep -qF 'scripts.test ("vitest run")' <<< "$(_hit T6.testRunners.app)"; then
  check "t6 vitest: the entry's own script is not a second suite" 1
else check "t6 vitest: the entry's own script is not a second suite" 0; fi
# Existing findings carry no value: the field is the drafting contract of this finding alone.
if [[ -z "$(jq -r '.findings[] | select(.id != "T6.testRunners.app") | select(has("value")) | .id' <<< "$OUT")" ]]; then
  check "t6: no other finding carries a value" 0
else check "t6: no other finding carries a value" 1; fi

# AC-3: the drafted value itself silences the finding — what onboard's re-run sees once it drafts
# it — while an empty array leaves the check off, as run.sh reads it, so the finding stands.
jq --argjson v "$(_val T6.testRunners.app)" '.commands.app.testRunners = [$v]' "$RV/c.json" > "$RV/drafted.json"
run_grill "$RV" "$RV/drafted.json"
expect_no_finding "t6 testRunners set to the drafted value → no finding" T6.testRunners.app
if [[ -z "$(jq -r '.notEvaluated[] | select(.id == "T6.testRunners.app") | .id' <<< "$OUT")" ]]; then
  check "t6 testRunners set → no notEvaluated line either" 0
else check "t6 testRunners set → no notEvaluated line either" 1; fi
cfg "$RV/handset.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn test",
  "testRunners": [{"when": ["*-selftest.sh"], "command": "bash {file}"}]}} }
EOF
run_grill "$RV" "$RV/handset.json"
expect_no_finding "t6 any non-empty testRunners → no finding" T6.testRunners.app
cfg "$RV/empty.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn test", "testRunners": []}} }
EOF
run_grill "$RV" "$RV/empty.json"
expect_finding "t6 an empty testRunners array is off → the finding fires" T6.testRunners.app "has no entry"

# AC-1, the direct form under yarn v1: scripts.test is the bare `vitest` watcher, so the entry
# calls `yarn vitest run` itself. A v1 lockfile quotes its version.
RV1="$(mkrepo t6-vitest-v1 src/a.test.ts)"
cat > "$RV1/package.json" <<'EOF'
{ "name": "v1", "scripts": { "test": "vitest", "unit": "NODE_ENV=test npx vitest run",
    "ci": "tsc && vitest run", "rep": "vitest run --reporter=verbose" },
  "dependencies": { "vitest": "^1.6.0" } }
EOF
cat > "$RV1/yarn.lock" <<'EOF'
# THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.
# yarn lockfile v1


"@vitest/expect@1.6.0":
  version "1.6.0"

vitest@^1.6.0:
  version "1.6.1"
EOF
cfg "$RV1/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn test"}} }
EOF
run_grill "$RV1" "$RV1/c.json"
expect_finding "t6 vitest v1: the evidence names the yarn v1 version" T6.testRunners.app \
  "depends on vitest, 1.6.1 (yarn.lock)" 'scripts.test = "vitest", which is not one plain run of vitest'
expect_value "t6 vitest v1: a watcher script gives the direct form" T6.testRunners.app vitest-json \
  "yarn vitest run --reporter=json --outputFile={report} --bail=0 {files}" "*.test.ts"
# A leading VAR=value and an npx wrapper are stripped: the script body is still one vitest run.
cfg "$RV1/unit.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn unit"}} }
EOF
run_grill "$RV1" "$RV1/unit.json"
expect_value "t6 vitest: VAR=value and npx are stripped → the configured form" T6.testRunners.app vitest-json \
  "yarn unit --reporter=json --outputFile={report} --bail=0 {files}"
# A chained body, and a body that already sets a reporter, are not one plain run → the direct form.
for t6s in ci rep; do
  cfg "$RV1/$t6s.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn $t6s"}} }
EOF
  run_grill "$RV1" "$RV1/$t6s.json"
  expect_value "t6 vitest: scripts.$t6s is not one plain run → the direct form" T6.testRunners.app vitest-json \
    "yarn vitest run --reporter=json --outputFile={report} --bail=0 {files}"
done

# AC-1 under pnpm (a v9 lockfile), with no configured test command: the direct form through
# `pnpm exec`. A vitest.config.ts and a vite.config.ts with a test: block raise the caveat.
RVP="$(mkrepo t6-vitest-pnpm src/x.test.mts)"
cat > "$RVP/package.json" <<'EOF'
{ "name": "vp", "scripts": {}, "devDependencies": { "vitest": "^2.1.0" } }
EOF
cat > "$RVP/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'

importers:

  .:
    devDependencies:
      vitest:
        specifier: ^2.1.0
        version: 2.1.8(@types/node@22.0.0)

packages:

  '@vitest/pretty-format@2.1.8':
    resolution: {integrity: sha512-x}

  vitest@2.1.8:
    resolution: {integrity: sha512-y}
EOF
: > "$RVP/vitest.config.ts"
printf 'export default defineConfig({\n  test: { environment: "jsdom" },\n})\n' > "$RVP/vite.config.ts"
cfg "$RVP/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$RVP" "$RVP/c.json"
expect_finding "t6 vitest pnpm: version, caveat and the unset test command" T6.testRunners.app \
  "depends on vitest, 2.1.8 (pnpm-lock.yaml)" "commands.app.test is not set" \
  "Runner config: vitest.config.ts, vite.config.ts (a test: block)" "match 1 tracked file(s)"
expect_value "t6 vitest pnpm: the direct form calls pnpm exec" T6.testRunners.app vitest-json \
  "pnpm exec vitest run --reporter=json --outputFile={report} --bail=0 {files}" "*.test.mts"
# A vite.config with no test: block configures no tests, so it raises no caveat.
printf 'export default defineConfig({ plugins: [] })\n' > "$RVP/vite.config.ts"
rm -f "$RVP/vitest.config.ts"
run_grill "$RVP" "$RVP/c.json"
if grep -qF "Runner config" <<< "$(_hit T6.testRunners.app)"; then
  check "t6 vitest: a vite.config with no test: block raises no caveat" 1
else check "t6 vitest: a vite.config with no test: block raises no caveat" 0; fi

# D-6: the default pattern matches no tracked file → the finding fires with NO value, and says the
# globs must come from the operator. No lockfile → npx, and the version is unresolved.
RVZ="$(mkrepo t6-vitest-zero test/foo_test.ts src/a.ts)"
cat > "$RVZ/package.json" <<'EOF'
{ "name": "vz", "scripts": { "test": "vitest run" }, "devDependencies": { "vitest": "^3.0.0" } }
EOF
cfg "$RVZ/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "npm test"}} }
EOF
run_grill "$RVZ" "$RVZ/c.json"
expect_finding "t6 zero matches: fires, the globs come from the operator" T6.testRunners.app \
  "version unresolved: no yarn.lock" "match 0 tracked file(s)" "its when globs have to come from you" \
  "npm test -- --reporter=json --outputFile={report} --bail=0 {files}"
if [[ -z "$(_val T6.testRunners.app)" ]]; then check "t6 zero matches: the finding carries no value" 0
else check "t6 zero matches: the finding carries no value" 1; fi

# AC-2: jest behind npm with a v3 package-lock.json. `npm test` runs scripts.test, which IS jest,
# so the entry extends it with `--`. jest-cli sits beside it with another version. The "jest" key
# in package.json raises the caveat, and scripts.test:it runs jest with -c (AC-5).
RJ="$(mkrepo t6-jest src/__tests__/a.ts src/b.spec.js src/c.test.jsx lib/d.js)"
cat > "$RJ/package.json" <<'EOF'
{ "name": "j", "scripts": { "test": "jest --ci", "test:it": "jest -c jest.it.config.js", "build": "tsc" },
  "devDependencies": { "jest": "^29.7.0" }, "jest": { "testEnvironment": "node" } }
EOF
cat > "$RJ/package-lock.json" <<'EOF'
{ "name": "j", "lockfileVersion": 3, "requires": true,
  "packages": { "": { "devDependencies": { "jest": "^29.7.0" } },
    "node_modules/jest": { "version": "29.7.0" },
    "node_modules/jest-cli": { "version": "29.6.0" } } }
EOF
cfg "$RJ/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "npm test"}} }
EOF
run_grill "$RJ" "$RJ/c.json"
expect_finding "t6 jest: the evidence names jest, its package-lock version, the caveat and the count" \
  T6.testRunners.app "depends on jest, 29.7.0 (package-lock.json)" \
  "Runner config: the \"jest\" key in package.json" "match 3 tracked file(s)"
expect_value "t6 jest: the value is a jest-json entry config-lint accepts, with -- for npm" \
  T6.testRunners.app jest-json "npm test -- --json --outputFile={report} --runTestsByPath --bail=0 {files}" \
  "*.test.ts" "*.spec.js" "*__tests__/*.ts" "*__tests__/*.cjs"
expect_finding "t6 jest: a -c suite is named as not covered" T6.testRunners.app \
  "Not covered by the proposed entry: scripts.test:it (\"jest -c jest.it.config.js\")"

# AC-2 with a v1 package-lock.json, a jest.config.js, and a --watchAll script → the direct form.
RJ1="$(mkrepo t6-jest-v1 src/a.test.js)"
cat > "$RJ1/package.json" <<'EOF'
{ "name": "j1", "scripts": { "test": "jest --watchAll" }, "devDependencies": { "jest": "^27.0.0" } }
EOF
cat > "$RJ1/package-lock.json" <<'EOF'
{ "name": "j1", "lockfileVersion": 1, "dependencies": { "jest": { "version": "27.5.1" } } }
EOF
: > "$RJ1/jest.config.js"
cfg "$RJ1/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "npm run test"}} }
EOF
run_grill "$RJ1" "$RJ1/c.json"
expect_finding "t6 jest v1 lock: version and the jest.config.js caveat" T6.testRunners.app \
  "depends on jest, 27.5.1 (package-lock.json)" "Runner config: jest.config.js"
expect_value "t6 jest: a watcher script gives the direct form through npx" T6.testRunners.app jest-json \
  "npx jest --json --outputFile={report} --runTestsByPath --bail=0 {files}" "*.test.js"

# AC-4: neither runner, both runners, no manifest, and a tree outside git — no finding, and a
# notEvaluated line naming what the grill saw.
RN="$(mkrepo t6-neither src/a.test.ts)"
cat > "$RN/package.json" <<'EOF'
{ "name": "n", "scripts": { "test": "mocha" }, "devDependencies": { "mocha": "^10.0.0", "jest-cli": "^29.0.0" } }
EOF
cfg "$RN/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test": "yarn test"}} }
EOF
run_grill "$RN" "$RN/c.json"
expect_no_finding "t6 neither runner → no finding" T6.testRunners.app
expect_noteval "t6 neither runner → not evaluated, naming it" T6.testRunners.app "depends on neither vitest nor jest"
cat > "$RN/package.json" <<'EOF'
{ "name": "n", "scripts": {}, "dependencies": { "jest": "^29.0.0" }, "devDependencies": { "vitest": "^3.0.0" } }
EOF
run_grill "$RN" "$RN/c.json"
expect_no_finding "t6 both runners → no finding" T6.testRunners.app
expect_noteval "t6 both runners → not evaluated, naming both" T6.testRunners.app "depends on both vitest and jest"
rm -f "$RN/package.json"
run_grill "$RN" "$RN/c.json"
expect_no_finding "t6 no root package.json → no finding" T6.testRunners.app
expect_noteval "t6 no root package.json → not evaluated" T6.testRunners.app "no readable root package.json"
RNG="$TMP/t6-nongit"; mkdir -p "$RNG/src"; : > "$RNG/src/a.test.ts"
cp "$RVZ/package.json" "$RNG/package.json"
cfg "$RNG/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$RNG" "$RNG/c.json"
expect_no_finding "t6 outside a git work tree → no finding" T6.testRunners.app
expect_noteval "t6 outside a git work tree → not evaluated" T6.testRunners.app "not a git work tree"
# D-14: no commands entry the lane reads → no T6 line at all; the entries are reported already.
cfg "$RV/none.json" <<'EOF'
{ "configVersion": 3, "tracker": {"type":"github"}, "commands": {"be":{}, "fe":{}} }
EOF
run_grill "$RV" "$RV/none.json"
if [[ -z "$(jq -r '(.findings + .notEvaluated)[] | select(.id | startswith("T6.")) | .id' <<< "$OUT")" ]]; then
  check "t6 no commands entry the lane reads → no T6 line" 0
else check "t6 no commands entry the lane reads → no T6 line" 1; fi

# --- findings are advisory: nothing in the config suppresses one -----------------------------
# The opt-out key left the config, so a leftover `grillWaivers` entry is inert — it must neither
# error nor silence the finding it names — and no proposal may point a consumer at it.
cat > "$R/package.json" <<'EOF'
{ "name": "t2-web-default", "scripts": {} }
EOF
cfg "$R/waived.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"lint":"npm run lint"}},
  "grillWaivers": {
    "T2.webComponentGlobs": "no web-component surface in this repo",
    "T5.missing-script.app.lint": "no lint script yet; tracked in the backlog" } }
EOF
run_grill "$R" "$R/waived.json"
check "leftover grillWaivers: grill still exits 0 (rc=$RC)" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"
expect_finding "leftover grillWaivers: T2.webComponentGlobs is not suppressed" T2.webComponentGlobs "matches 0"
expect_finding "leftover grillWaivers: T5.missing-script.app.lint is not suppressed" T5.missing-script.app.lint "no scripts.lint"
if [[ -z "$(jq -r '.findings[] | select((.proposal + .evidence) | test("grillWaivers|waive")) | .id' <<< "$OUT")" ]]; then
  check "no proposal offers a waiver" 0
else
  check "a proposal still offers a waiver" 1
fi

# --- AC-1: exit codes ----------------------------------------------------------------------
run_grill "$R" "$R/nope.json"
check "exit 3 on a missing config path (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
printf 'not json' > "$R/bad.json"
run_grill "$R" "$R/bad.json"
check "exit 3 on a non-JSON config (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
RC=0; bash "$GRILL" >/dev/null 2>&1 || RC=$?
check "exit 3 with no arguments (rc=$RC)" "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
RC=0; OUT="$(bash "$GRILL" "$R2" "$R2/c.json" 2>/dev/null)" || RC=$?
if [[ "$RC" -eq 0 ]] && jq -e '(.findings | type == "array") and (.notEvaluated | type == "array")
                               and (keys | sort) == ["findings","notEvaluated"]' <<< "$OUT" >/dev/null; then
  check "envelope: two arrays, exit 0, on a clean repo" 0
else
  check "envelope: two arrays, exit 0, on a clean repo (rc=$RC)" 1
fi
# The envelope carries no `unadopted` key: that severity has no producer.
if jq -e 'has("unadopted") | not' <<< "$OUT" >/dev/null; then
  check "envelope: no unadopted key" 0
else
  check "envelope: unadopted key still present" 1
fi

# --- AC-1: no emitted string names a mechanism the default lane does not execute ------------
# The oracle for the whole envelope, and a lint over shell SOURCE rather than a prose-presence
# guard: it enumerates the strings that can reach findings[]/notEvaluated[] and
# denies a fixed token list in them. Per-check assertions cannot do this job — they can only
# pin the strings someone remembered to pin, and the defect class here is a remediation nobody
# re-read after the lane it named stopped running.
#
# ENUMERATION starts at the emitting call sites — add_finding, add_noteval, plus
# t2_key, which forwards its benefit sentence into a proposal — captures each full statement
# including backslash continuations, then closes over the variable assignments and function
# bodies those statements reference, repeating until nothing new is pulled in. The closure is
# what reaches $ev / $pr / $mut_desc, whose literals live away from the call site; a call-site
# scan without it would read green on half the emitted prose.
#
# COMMENTS ARE NEVER CAPTURED, deliberately. They legitimately describe the other lane's runtime
# semantics, and a whole-file grep would ban explaining the very thing the emitted text must not
# promise. The comment-immunity control below is what holds that line.
#
# DENY-LIST, and the whole of it — there are no per-finding exemptions, because after the
# rewords no correct string needs one:
#   [Ss]tage[ -][0-9] , stages/[0-9] , milestone , receipt   retired-lane phrasing
#   visualCapture / visual capture / screenshot   the dropped capture capability
#   grillWaivers                                  the retired opt-out key
DENY_RE='[Ss]tage[ -][0-9]|stages/[0-9]|[Mm]ilestone|receipt|[Vv]isual[ -][Cc]apture|visualCapture|screenshot|grillWaivers'
SINK_RE='(^|[^A-Za-z0-9_])(add_finding|add_noteval)[[:space:]]'

emitted_corpus() { # $1 = a config-grill.sh source path → every string that can reach the envelope
  local src="$1" corpus prev pulled n round=0
  corpus="$(awk '
    /(^|[^A-Za-z0-9_])(add_finding|add_noteval|t2_key)[[:space:]]/ { cap = 1 }
    cap { print; if ($0 !~ /\\[[:space:]]*$/) { cap = 0 } }
  ' "$src")"
  prev=""
  while [[ "$corpus" != "$prev" && "$round" -lt 8 ]]; do
    prev="$corpus"
    round=$((round + 1))
    pulled=""
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      pulled="$pulled
$(grep -E "(^|[[:space:]])(local[[:space:]]+)?$n=" "$src" 2>/dev/null)
$(awk -v f="$n" 'index($0, f "() {") == 1 { inf = 1 } inf { print } inf && /^\}/ { inf = 0 }' "$src")"
    done <<< "$(grep -oE '[$]\{?[A-Za-z_][A-Za-z0-9_]*|[$]\([a-z_][a-z0-9_]*' <<< "$corpus" \
                | sed 's/^[$][{(]*//' | sort -u)"
    corpus="$(printf '%s\n%s\n' "$corpus" "$pulled" \
              | grep -vE '^[[:space:]]*(#|$)' | sort -u)"
  done
  printf '%s\n' "$corpus"
}

CORPUS="$(emitted_corpus "$GRILL")"

# Control 1 — CLOSURE. Every emitting call site in the source is in the corpus. An enumerator
# that quietly captured half the file would otherwise report "no banned tokens" just as
# convincingly. Compared as DISTINCT statement texts, since the corpus is deduplicated and two
# T5 non-evaluation calls are byte-identical — a text lint's unit is the text, not the line.
declared="$(grep -vE '^[[:space:]]*#' "$GRILL" | grep -E "$SINK_RE" | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$declared") <(grep -E "$SINK_RE" <<< "$CORPUS" | sort -u))"
n_declared="$(grep -c . <<< "$declared")"
if [[ "$n_declared" -gt 0 && -z "$missing" ]]; then
  check "oracle closure: all $n_declared distinct emitting call sites captured" 0
else
  check "oracle closure: $n_declared call sites declared, uncaptured: $(grep -c . <<< "$missing")" 1
  awk '{print "      " $0}' <<< "$missing" | head -3
fi

# Control 2 — SENTINELS, one per capture arm. The first is a literal sitting at a call site; the
# second lives on an `ev=` assignment inside t2_key and is reachable ONLY through the variable
# closure, so losing that arm fails here rather than passing quietly.
for sentinel in "so this one cannot be anything else" "matches 0 of the repo"; do
  if grep -qF -- "$sentinel" <<< "$CORPUS"; then
    check "oracle sentinel present: '$sentinel'" 0
  else
    check "oracle sentinel MISSING (corpus is not what it claims): '$sentinel'" 1
  fi
done

# The assertion itself.
deny_hits="$(grep -nE "$DENY_RE" <<< "$CORPUS")"
if [[ -z "$deny_hits" ]]; then
  check "AC-1: no emitted string names a mechanism the default lane does not execute" 0
else
  check "AC-1: an emitted string names a non-default-lane mechanism" 1
  awk '{print "      " $0}' <<< "$deny_hits" | head -5
fi

# Control 3 — MUTANTS. One at a direct call-site literal, one at an indirect (`ev=`) literal, so
# neither arm can rot into decoration. Both must be CAUGHT.
mutate() { # $1 label, $2 sed script, $3 expect: catch|clean
  local m="$TMP/mutant.sh" hits
  sed "$2" "$GRILL" > "$m"
  if ! cmp -s "$GRILL" "$m"; then
    hits="$(grep -cE "$DENY_RE" <<< "$(emitted_corpus "$m")")"
    if [[ "$3" == "catch" ]]; then
      check "oracle $1" "$([[ "$hits" -gt 0 ]] && echo 0 || echo 1)"
    else
      check "oracle $1" "$([[ "$hits" -eq 0 ]] && echo 0 || echo 1)"
    fi
  else
    check "oracle $1 (mutation was a no-op — the anchor moved)" 1
  fi
}
mutate "mutant: a banned token at a direct call-site literal is caught" \
  's|so this one cannot be anything else|so this one cannot be anything else in Stage 5|' catch
mutate "mutant: a banned token at an indirect (ev=) literal is caught" \
  's|matches 0 of the repo|matches 0 of the stages/6 repo|' catch

# Control 4 — COMMENT IMMUNITY, which is what makes this a call-site scan rather than a
# whole-file grep: comments may describe retired mechanisms, emitted strings may not.
mutate "mutant: a banned token injected into a COMMENT is NOT caught" \
  's|^# Read-only, no network, bash-3.2 safe.|# Read-only, no network. Stage 5 visualCapture screenshot.|' clean

if [[ "$FAILS" -gt 0 ]]; then echo "config-grill selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-grill selftest: all green"
