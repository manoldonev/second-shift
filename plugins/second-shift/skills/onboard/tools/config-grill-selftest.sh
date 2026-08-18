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
_uhit() { jq -r --arg i "$1" '.unadopted[] | select(.id==$i) | .evidence + " ⟂ " + .proposal' <<< "$OUT"; }
_uids() { jq -r '.unadopted[].id' <<< "$OUT" | tr '\n' ' '; }

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
expect_unadopted() { # $1 label, $2 id, $3.. substrings that must appear in evidence+proposal
  local label="$1" id="$2"; shift 2
  local got s; got="$(_uhit "$id")"
  if [[ -z "$got" ]]; then check "$label (no unadopted '$id'; got: $(_uids))" 1; return; fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<< "$got"; then check "$label (unadopted '$id' missing '$s')" 1; echo "      $got"; return; fi
  done
  check "$label" 0
}
expect_no_unadopted() { # $1 label, $2 id
  if [[ -z "$(_uhit "$2")" ]]; then check "$1" 0; else check "$1 (unexpected unadopted '$2')" 1; echo "      $(_uhit "$2")"; fi
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
{ $STD_HEAD, "commands": {"app":{}} }
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

# No candidate matches either → the finding STILL fires and says so, rather than going quiet
# because the tool could not think of a value. The tree has to carry a real component somewhere
# no candidate reaches: this is the arm the applicability probe sits next to, so a probe that
# over-reached would silence exactly this case.
R3B="$(mkrepo t2-web-nocand pkg/ui/Widget.tsx docs/guide.md)"
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
  "stageParams": {"webComponentGlobs": ["apps/web/**/*.css", "apps/legacy/**/*.vue"]} }
EOF
run_grill "$R3B" "$R3B/multi.json"
expect_finding "t2 webComponentGlobs: every configured glob is rendered, comma-joined" \
  T2.webComponentGlobs "(apps/web/**/*.css, apps/legacy/**/*.vue)"

# --- the applicability probe: a repo that renders nothing ----------------------------------
# "Zero matches is a finding" is right for formatGlob and wrong for the web-conditional key:
# a shell/CLI/library consumer has no rendering surface at all, so the absent glob is a
# measured fact, not an omission. It must land in notEvaluated[] — no proposal, not waivable,
# never blocking — rather than demanding a waiver that restates what the tool just measured.
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
# root, where neither the resolved default nor any shipped candidate reaches it: the finding
# that fires is therefore the probe holding the check open, not a candidate rescuing it.
for ext in tsx jsx vue svelte astro html css scss sass less; do
  RPB="$(mkrepo "probe-$ext" "widget.$ext")"
  cfg "$RPB/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
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

# --- AC-2/AC-3: trigger 2, formatGlob ------------------------------------------------------
# formatGlob's shape has no "/", and the bash `[[ f == $a ]]` match it inherited from the
# the verify lane treats * as one that
# CROSSES separators. Transliterating * to [^/]* would match only root-level files and fire a
# false zero-match on every repo with sources in a subdirectory — this pair pins that rule.
R4="$(mkrepo t2-format-go main.go pkg/server.go)"
cfg "$R4/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R4" "$R4/c.json"
expect_finding "t2 formatGlob: default matches nothing on a go tree" \
  T2.formatGlob "*.{ts,tsx,js,json,md}" "*.{go,md,json}"
# The probe-leak guard, and it only works on a tree with NO web surface: formatGlob is universal
# and carries no probe, so it must still FIRE in the same call where the web key converted.
# A probe left set from the preceding t2_key call would take formatGlob with it, and every other
# formatGlob fixture in this file has something the probe matches, so none of them can catch it.
expect_noteval "t2 probe: the go tree converts webComponentGlobs" T2.webComponentGlobs "applicability probe"
if [[ -z "$(jq -r '.notEvaluated[] | select(.id=="T2.formatGlob") | .id' <<< "$OUT")" ]]; then
  check "t2 probe does not leak into formatGlob (no notEvaluated entry for it)" 0
else
  check "t2 probe leaked into formatGlob — it converted a row that carries no probe" 1
fi
R5="$(mkrepo t2-format-nested src/deep/a.ts)"
cfg "$R5/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R5" "$R5/c.json"
expect_no_finding "t2 formatGlob: slash-free glob crosses separators (src/deep/a.ts)" T2.formatGlob

# The third enumerated case for this row: a HAND-SET formatGlob matching nothing. Not a
# formality — formatGlob is the only slash-free row, so the configured-value path and the
# `*` → `.*` branch only ever meet here. That both counts in this finding (0 for the configured
# value, 1 for the alternative) come out of the crossing branch is what makes the pairing
# load-bearing: under `[^/]*` the alternative would score 0 too and the proposal would offer a
# value that matches nothing either.
cfg "$R5/format-set.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}},
  "stageParams": {"formatGlob": "*.{rs,toml}"} }
EOF
run_grill "$R5" "$R5/format-set.json"
expect_finding "t2 formatGlob: hand-set value matching nothing still fires" \
  T2.formatGlob "configured value" "*.{rs,toml}" \
  "matches 0 of the repo's tracked files" "*.{ts,tsx,js,jsx,json,md}" "matches 1 tracked file(s)"

# --- AC-4: the deleted ids are GONE from every envelope array -------------------------------
# Deleted outright, not merely silenced. Visual capture is dropped as a capability (`extraLanes`
# is the consumer home for a capture lane), and the testFile obligation died with its key
# (`testFile`/`unitTestScope` were retired outright in #574). This fixture deliberately KEEPS
# the retired keys — it replays the exact shape that made BOTH ids fire before (a hand-set
# triggerGlobs matching nothing on a tree that renders something, plus a unitTestScope with a
# null testFile), so a re-introduction lands here rather than nowhere. The grill runs on
# drafts pre-lint, so the schema retirement does not blank the probe. Checked across all three arrays: re-appearing as a notEvaluated or unadopted
# entry is the same regression wearing a different severity.
cfg "$R/deleted.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":"src/**","testFile":null}},
  "stageParams": {"visualCapture": {"triggerGlobs": ["apps/web/**/*.css"]}} }
EOF
run_grill "$R" "$R/deleted.json"
for gone in T2.visualCaptureTriggerGlobs T4.testfile-plumbing.app; do
  if [[ -z "$(jq -r --arg i "$gone" \
       '(.findings + .unadopted + .notEvaluated)[] | select(.id==$i) | .id' <<< "$OUT")" ]]; then
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

# --- AC-4: trigger 4, the mutation seam ----------------------------------------------------
# The seam has ONE owner: a repo-carried tools/mutation-sweep.sh that the green gate executes.
# So the detectable inconsistency is a config that DECLARES mutation intent over a repo carrying
# nothing to run it. Since #574 retired commands.<repo>.unitTestScope, gates.mutation is the
# ONLY declared-intent signal — under RUNTIME semantics: `.gates.mutation // empty` means only
# the literal false is the off-switch, so ABSENT IS NOT FALSE. The evidence must say which
# state it found; a check keyed to `== true` alone would miss the far commoner absent case.
R6="$(mkrepo t4 apps/web/App.tsx apps/web/src/app/P.tsx a.ts)"
R6S="$(mkrepo t4-swept apps/web/App.tsx apps/web/src/app/P.tsx a.ts tools/mutation-sweep.sh)"

cfg "$R6/mut-absent.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R6" "$R6/mut-absent.json"
expect_finding "t4 gates.mutation absent (absent is not false) + no sweep" \
  T4.mutation-plumbing.app "absent" "NOT false"
cfg "$R6/mut-true.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "gates": {"mutation": true} }
EOF
run_grill "$R6" "$R6/mut-true.json"
expect_finding "t4 gates.mutation true + no sweep" T4.mutation-plumbing.app "gates.mutation is true"

# The retirement probe (#574): the RETIRED key must contribute nothing — one finding, whose
# evidence is the gates state alone. Before #574 this exact shape produced evidence naming
# unitTestScope; a re-introduced arm lands here rather than nowhere. (The fixture key is
# schema-retired — the grill runs on drafts pre-lint, so what is probed is the grill's own
# read, not the schema.)
cfg "$R6/mut-retired-key.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":"src/**"}}, "gates": {"mutation": true} }
EOF
run_grill "$R6" "$R6/mut-retired-key.json"
expect_finding "t4 the retired unitTestScope key contributes nothing to the evidence" \
  T4.mutation-plumbing.app "gates.mutation is true"
if [[ -z "$(jq -r '.findings[] | select(.id=="T4.mutation-plumbing.app") | .evidence | select(test("unitTestScope"))' <<< "$OUT")" ]]; then
  check "t4 retired-key evidence never names unitTestScope" 0
else
  check "t4 retired-key evidence still names unitTestScope (#574 regression)" 1
fi
if [[ "$(jq -r '[.findings[] | select(.id=="T4.mutation-plumbing.app")] | length' <<< "$OUT")" == "1" ]]; then
  check "t4 retired key → still exactly one finding" 0
else
  check "t4 retired key → duplicate findings" 1
fi

# The declared opt-out stays silent...
cfg "$R6/mut-false.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}}, "gates": {"mutation": false} }
EOF
run_grill "$R6" "$R6/mut-false.json"
expect_no_finding "t4 gates.mutation false is the declared off-switch → silent" \
  T4.mutation-plumbing.app

# ...and so does a repo that actually CARRIES the sweep — the negative half, without which the
# check could be "fires on every config" and still pass everything above. Byte-identical config
# to the absent-gates case that fires, so the sweep file is the only difference between them.
cfg "$R6S/mut-absent.json" <<EOF
{ $STD_HEAD, "commands": {"app":{}} }
EOF
run_grill "$R6S" "$R6S/mut-absent.json"
expect_no_finding "t4 the repo carries the sweep → silent" T4.mutation-plumbing.app

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
    "wrapped": "npx vitest",
    "fmt": "prettier -w .",
    "vrun": "vitest --run",
    "tscw": "tsc -w" } }
EOF
cfg "$R7/c.json" <<EOF
{ $STD_HEAD,
  "commands": {"app":{
    "testFile": "yarn test {file}",
    "test": "yarn test:run",
    "lint": "npm run lint",
    "typecheck": null,
    "format": "yarn vitepreview",
    "lanes": [{"name":"setup","commands":["yarn watchy","yarn mon","yarn fmt","yarn vrun","yarn tscw"]}],
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

# The two shapes the AC-5 narrowings exclude. Each is a script a mainstream repo really ships,
# and each was a doctor FAIL on a valid config before the qualification: prettier's `-w` is
# `--write`, and vitest's `--run` is the flag spelling of the exiting `run` subcommand. A false
# FAIL is worse than a missed warning here, because its only escape is a waiver excusing a
# non-problem — which turns "adopt or declare" into "declare, there is nothing to adopt".
expect_no_finding "t5 non-watcher: prettier -w (-w is --write, not watch)" T5.watcher.app.lanes.0.2
expect_no_finding "t5 non-watcher: vitest --run (flag spelling of the run subcommand)" T5.watcher.app.lanes.0.3
# ...and the rule the first of those narrows must still FIRE where -w really is watch, or the
# narrowing would have deleted the rule rather than qualified it.
expect_finding "t5 watcher: -w on a runner that defines it as watch (tsc)" \
  T5.watcher.app.lanes.0.4 "tsc -w"

# The `-w` allowlist, one case PER MEMBER rather than one for the bullet. An allowlist reviewed
# as prose reads as a single rule, so a member that fails the very predicate it instantiates
# ships unexecuted — which is exactly how `jest` got in: its `-w` is `--maxWorkers`, and
# `watch`/`watchAll` carry no alias, so `jest -w 4` was a doctor FAIL on an ordinary script.
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
# Non-members: each fails the predicate, so firing on any of them is a FAIL on a valid config.
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
  "commands": {"be":{"test":"yarn test"},
               "fe":{"test":"yarn test"}} }
EOF
run_grill "$RP" "$RP/c.json"
expect_finding "scoping: the evaluated repo IS checked" T4.mutation-plumbing.be "NOT false"
expect_no_finding "scoping: the sibling repo is NOT checked" T4.mutation-plumbing.fe
expect_noteval "scoping: the sibling is reported as not-evaluated" topology.fe "sibling checkout"

# --- AC-6: waiver suppression --------------------------------------------------------------
# Keyed by CHECK ID with the repo id where the check is per-repo. A waived finding is
# suppressed by the checker itself, so both callers suppress identically.
# The UNwaived control rides on formatGlob, hand-set to match nothing: it is the row this
# fixture can fire that neither waiver names, and without it "suppressed" and "emits nothing at
# all" are the same observation.
cfg "$R/waived.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}},
  "stageParams": {"formatGlob": "*.{rs,toml}"},
  "grillWaivers": {
    "T2.webComponentGlobs": "no web-component surface in this repo",
    "T4.mutation-plumbing.app": "no unit-test surface yet; tracked in the backlog" } }
EOF
run_grill "$R" "$R/waived.json"
expect_no_finding "waiver: T2.webComponentGlobs suppressed" T2.webComponentGlobs
expect_no_finding "waiver: T4.mutation-plumbing.app suppressed (repo-scoped id)" T4.mutation-plumbing.app
expect_finding "waiver: an UNwaived finding still fires" T2.formatGlob "*.{rs,toml}"

# A waiver keyed WITHOUT the repo id must not silence a per-repo check — that is the whole
# reason the id carries the repo (a bare id would silence every repo at once).
cfg "$R/waived-bare.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}},
  "grillWaivers": { "T4.mutation-plumbing": "bare id, wrong shape" } }
EOF
run_grill "$R" "$R/waived-bare.json"
expect_finding "waiver: a repo-less id does NOT silence a per-repo check" T4.mutation-plumbing.app

# --- #569: trigger 1's extension-points row is RETIRED --------------------------------------
# The block that lived here drove `T1.extension-points` through its whole matrix: fires when all
# three additive-gate seams are absent, silent as soon as any ONE is adopted, `[]` is not
# adoption, waivable by a repo-less id. #569 retired stageWorkflows / implementDelegates /
# planGates, so every one of those cases now asserts behavior over keys config-lint rejects.
#
# The replacement is not "delete and move on" — that would let the row come back unnoticed, and
# the row is worse than useless now: onboard BLOCKS on an unwaived unadopted entry, so a config
# with none of the three keys (which is every config, since they cannot be set any more) would
# be permanently blocked behind a waiver for a capability that does not exist. So the guard is
# inverted: the id must be ABSENT on exactly the config shape that used to produce it.
RT1="$(mkrepo t1-none src/App.tsx a.ts)"
cfg "$RT1/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}} }
EOF
run_grill "$RT1" "$RT1/c.json"
expect_no_unadopted "t1: the retired extension-points row does not fire (#569)" T1.extension-points
expect_no_finding "t1: nor does it leak into findings[]" T1.extension-points
check "t1 exits 0 (rc=$RC)" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"

# A config that still CARRIES the retired keys must not resurrect it either. config-lint rejects
# such a config, but the grill runs on onboard's draft as well as on a committed file, so it has
# to be inert on the shape rather than merely unreachable — and an `EP_ADOPTED`-style predicate
# left behind would read as "adopted" here and hide a re-introduction.
cfg "$RT1/legacy-keys.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null,"testFile":null}},
  "stageWorkflows": [], "implementDelegates": [], "planGates": [] }
EOF
run_grill "$RT1" "$RT1/legacy-keys.json"
expect_no_unadopted "t1: retired keys present-but-empty raises nothing (#569)" T1.extension-points

# --- AC-4: the durable mutation-seam advisory ----------------------------------------------
# Keyed on commands.<repo>.test — durable config — so this surfacing outlives the keys the
# findings[] row is phrased in. It rides in unadopted[]: a missing sweep is a legal and common
# state (the green gate prints a SKIPPED notice and proceeds), so a findings[] entry would take
# every already-green consumer non-zero for a capability many will never adopt.
RMS="$(mkrepo t1-sweep src/App.tsx a.ts)"
cfg "$RMS/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test":"yarn test","unitTestScope":null}},
  "gates": {"mutation": false} }
EOF
run_grill "$RMS" "$RMS/c.json"
expect_unadopted "t1 sweep: test configured + no sweep" T1.mutation-sweep.app \
  "yarn test" "--mode pr --base origin/<baseBranch>" "grillWaivers"
expect_no_finding "t1 sweep never leaks into findings[] (doctor would FAIL on it)" T1.mutation-sweep.app

# One negative per input, so neither half of the predicate can be a constant.
cfg "$RMS/no-test.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"unitTestScope":null}}, "gates": {"mutation": false} }
EOF
run_grill "$RMS" "$RMS/no-test.json"
expect_no_unadopted "t1 sweep: silent with no test lane configured" T1.mutation-sweep.app
RMS2="$(mkrepo t1-sweep-present src/App.tsx tools/mutation-sweep.sh)"
cfg "$RMS2/c.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test":"yarn test","unitTestScope":null}},
  "gates": {"mutation": false} }
EOF
run_grill "$RMS2" "$RMS2/c.json"
expect_no_unadopted "t1 sweep: silent when the repo carries one" T1.mutation-sweep.app

# The two tiers are INDEPENDENT, not one suppressing the other. That is the whole reason they
# carry separate waiver ids: coupling them would mean waiving one makes the other appear —
# "fix it and a new complaint arrives" reads as a broken tool — and they force different
# dispositions ("your config declares coverage it cannot run" vs "you have a suite and nothing
# checks it"). Both directions of the waiver are pinned, since a suppression written into the
# wrong tier only shows up from one side.
cfg "$RMS/both-tiers.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test":"yarn test"}} }
EOF
run_grill "$RMS" "$RMS/both-tiers.json"
expect_finding "t1 sweep: the findings[] row fires alongside the advisory" \
  T4.mutation-plumbing.app "NOT false"
expect_unadopted "t1 sweep: the advisory fires alongside the finding" T1.mutation-sweep.app "yarn test"
cfg "$RMS/waived-finding.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test":"yarn test"}},
  "grillWaivers": { "T4.mutation-plumbing.app": "declared: no mutation coverage here" } }
EOF
run_grill "$RMS" "$RMS/waived-finding.json"
expect_no_finding "t1 sweep: waiving the finding suppresses only the finding" T4.mutation-plumbing.app
expect_unadopted "t1 sweep: ...and leaves the advisory standing" T1.mutation-sweep.app "yarn test"
cfg "$RMS/waived-advisory.json" <<EOF
{ $STD_HEAD, "commands": {"app":{"test":"yarn test"}},
  "grillWaivers": { "T1.mutation-sweep.app": "no sweep wanted here" } }
EOF
run_grill "$RMS" "$RMS/waived-advisory.json"
expect_no_unadopted "t1 sweep: a waiver suppresses the advisory" T1.mutation-sweep.app
expect_finding "t1 sweep: ...and leaves the finding standing" T4.mutation-plumbing.app "NOT false"

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
                               and (.unadopted | type == "array")' <<< "$OUT" >/dev/null; then
  check "envelope: three arrays, exit 0, on a clean repo" 0
else
  check "envelope: three arrays, exit 0, on a clean repo (rc=$RC)" 1
fi

# --- AC-1: no emitted string names a mechanism the default lane does not execute ------------
# The oracle for the whole envelope, and a lint over shell SOURCE rather than a prose-presence
# guard: it enumerates the strings that can reach findings[]/unadopted[]/notEvaluated[] and
# denies a fixed token list in them. Per-check assertions cannot do this job — they can only
# pin the strings someone remembered to pin, and the defect class here is a remediation nobody
# re-read after the lane it named stopped running.
#
# ENUMERATION starts at the emitting call sites — add_finding, add_unadopted, add_noteval, plus
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
#   [Ss]tage[ -][0-9] , stages/[0-9]   staged-lane phrasing; the default lane has milestones
#   visualCapture / visual capture / screenshot   the dropped capture capability
# T2.webComponentGlobs and T2.formatGlob are TRUTHFUL under the default lane — a11y and
# design-fidelity route through the review half's panel, and the format lane is executed by the
# green gate — so they must pass this untouched rather than earn an exemption.
DENY_RE='[Ss]tage[ -][0-9]|stages/[0-9]|[Vv]isual[ -][Cc]apture|visualCapture|screenshot'
SINK_RE='(^|[^A-Za-z0-9_])(add_finding|add_unadopted|add_noteval)[[:space:]]'

emitted_corpus() { # $1 = a config-grill.sh source path → every string that can reach the envelope
  local src="$1" corpus prev pulled n round=0
  corpus="$(awk '
    /(^|[^A-Za-z0-9_])(add_finding|add_unadopted|add_noteval|t2_key)[[:space:]]/ { cap = 1 }
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
# ("Adopt the seam or declare" replaced "Adopt whichever fits" in #569 — the latter lived in
# the retired T1.extension-points proposal. Both are direct call-site literals; the arm under
# test is unchanged.)
for sentinel in "Adopt the seam or declare" "matches 0 of the repo"; do
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
  's|there is a suite, and nothing that checks|there is a Stage 5 suite, and nothing that checks|' catch
mutate "mutant: a banned token at an indirect (ev=) literal is caught" \
  's|matches 0 of the repo|matches 0 of the stages/6 repo|' catch

# Control 4 — COMMENT IMMUNITY, which is what makes this a call-site scan rather than a
# whole-file grep. The pristine source ALREADY carries banned tokens in comments (the dropped-row
# table names the stage that creates a plan file; the visualCapture note says why no lane takes a
# screenshot), so the green verdict above is only meaningful if those are genuinely out of scope.
src_hits="$(grep -cE "$DENY_RE" "$GRILL")"
if [[ "$src_hits" -gt 0 ]]; then
  check "oracle: the source carries $src_hits banned token(s) in comments, and passes anyway" 0
else
  check "oracle: no banned token anywhere in the source — comment immunity is untested" 1
fi
mutate "mutant: a banned token injected into a COMMENT is NOT caught" \
  's|^# Read-only, no network, bash-3.2 safe.|# Read-only, no network. Stage 5 visualCapture screenshot.|' clean

if [[ "$FAILS" -gt 0 ]]; then echo "config-grill selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-grill selftest: all green"
