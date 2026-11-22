#!/usr/bin/env bash
# eval-selftest.sh — run.sh and eval.py against a three-file fixture repo, with a stand-in for the review
# session (PLAIN_CLAUDE) and for the judge (JUDGE_CLAUDE). The real plain-review.sh runs, so its deny rules
# and its out-dir check are exercised. No session is spawned: model-free, like the rest of CI.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
done_() { echo "eval-selftest: $PASS passed, $FAIL failed"; exit "$FAIL"; }

TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$TOP" ] || [ ! -f "$TOP/plugins/review-toolkit/evals/agent-eval-kit/run-eval.py" ]; then
  echo "  skip: the eval kit is not beside this plugin (an installed copy); the eval runs from a checkout"
  done_
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/pass1-eval-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/tmp" "$T/state" "$T/results"

echo "== the checked-in fixture =="
HEAD_SHA="$(jq -r .head "$HERE/fixtures/tuning/fixture.json")"
if git -C "$TOP" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
  out="$(bash "$HERE/run.sh" --check-fixture --cache-dir "$T/check-cache" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "both plants apply at the pinned head, and the planted tree no longer names the removed field" || bad "check-fixture rc=$rc: $out"
else
  echo "  skip: this checkout does not hold the fixture's commit (a shallow clone)"
fi

case "$(cd "$T" && pwd -P)" in
  /private/tmp/*) echo "  skip: the temp dir is under a path the runner denies, so no session could read its tree"; done_ ;;
esac

echo "== a fixture repo =="
R="$T/repo"; F="$T/fixtures/tiny"
mkdir -p "$R" "$F"
g() { git -C "$R" -c user.name=selftest -c user.email=selftest@example.invalid "$@"; }
g init -q
echo 'echo zero' > "$R/zero.sh"; g add zero.sh; g commit -qm base
BASE="$(g rev-parse HEAD)"
echo 'echo one' > "$R/one.sh"; echo 'echo marker-two' > "$R/two.sh"; echo 'bash two.sh' > "$R/two-test.sh"; echo 'bash one.sh' > "$R/one-test.sh"
echo 'usage' > "$R/README.md"
g add .; g commit -qm head
HEAD="$(g rev-parse HEAD)"
g rm -q two.sh two-test.sh; g diff --cached HEAD > "$F/plant-a.patch"; g reset -q --hard HEAD
g rm -q two-test.sh; g diff --cached HEAD > "$F/plant-b.patch"; g reset -q --hard HEAD
printf '%s\n' '# Two commands' '' 'C1: a first command.' 'C2: a second command.' 'C3: the README says how.' > "$F/ticket.md"
jq -n '{criteria: [{n: 1, id: "C1", text: "a first command", impl: "one.sh:1", test: "one-test.sh:1"},
                   {n: 2, id: "C2", text: "a second command", impl: "two.sh:1", test: "two-test.sh:1"},
                   {n: 3, id: "C3", text: "the README says how", impl: "README.md:1", test: null}]}' > "$F/key.json"
jq -n --arg repo "$R" --arg base "$BASE" --arg head "$HEAD" '
  {label: "tiny", repo: $repo, base: $base, head: $head, plans_dir: "docs/plans", ticket: "ticket.md", key: "key.json", planted_criterion: 2,
   variants: {"plant-a": {patch: "plant-a.patch", kind: "unimplemented", leak_tokens: ["marker-two"]},
              "plant-b": {patch: "plant-b.patch", kind: "untested"}, twin: {}}}' > "$F/fixture.json"

RM=alpha JM=beta
# run_eval <log> <args...>: the runner in a home, temp dir and cache of its own, siblings under $T
run_eval() {
  local log="$1"; shift
  HOME="$T/home" TMPDIR="$T/tmp" XDG_CACHE_HOME="$T/home/.cache" REVIEWER_MODEL="$RM" JUDGE_MODEL="$JM" \
    PLAIN_CLAUDE="$HERE/selftest-data/fake-claude.sh" JUDGE_CLAUDE="$HERE/selftest-data/fake-judge.py" FAKE_STATE="$T/state" \
    bash "$HERE/run.sh" --fixtures-dir "$T/fixtures" --fixture tiny --results-dir "$T/results" --no-record --allow-dirty "$@" > "$log" 2>&1
}
row() { grep -F "arm=$2 " "$1" | grep -F 'fixture=tiny' | head -n 1; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

echo "== measures =="
run_eval "$T/all.log" --arm pass-1 --arm plain --runs 2; rc=$?
P="$(row "$T/all.log" pass-1)"; L="$(row "$T/all.log" plain)"
[ "$rc" -eq 0 ] && has "$P" 'detect-A=2/2 (3,3) | detect-B=2/2 (3,3) |' && has "$P" '| tag=4/4 | voided=0 |' \
  && ok "a review that names the planted criterion is a detection on both plants, with every judge vote and its tag" || bad "rc=$rc pass-1 row: $P $(tail -n 5 "$T/all.log")"
has "$P" 'clean-twin=2/2 | approve-twin=0/2 (false 0, per-rule 2, other 0) | false-claims=0.0 (unkeyed 0.0, per-rule 0.3)' \
  && ok "a no-test claim on a criterion the key marks untested is per-rule: the twin stays clean and the run is not an approve" || bad "pass-1 row: $P"
has "$L" 'detect-A=0/2 (0,0) | clean-twin=0/2 | approve-twin=0/2 (false 2, per-rule 0, other 0) | false-claims=0.5' \
  && ok "a review with no findings detects nothing, and a not-implemented claim on the twin is a false claim" || bad "plain row: $L"
if has "$L" 'detect-B' || has "$L" 'tag='; then bad "plain row carries a plant-b or tag measure: $L"; else ok "the plain arm has no plant-b cell and no tag without a detection"; fi
has "$P" "model=claude-$RM-0 | judge=claude-$JM-0 | runs=2 |" && ok "the row names the ids the sessions resolved" || bad "pass-1 row: $P"
RES="$(find "$T/results" -name 'results-*.json' | head -n 1)"
[ -n "$RES" ] && [ "$(jq '[.arms["pass-1"].runs[] | select(.variant == "plant-a") | .planted.votes | length] | add' "$RES")" = 6 ] \
  && [ "$(jq -r '[.arms.plain.runs[] | select(.variant == "twin") | .claims[0].class] | unique | join(",")' "$RES")" = false ] \
  && ok "the results file holds each run's judge votes and each claim's class" || bad "results: $RES"
[ -z "$(find "$T/home/.cache/review-runs/runs" -mindepth 1 -maxdepth 1 2>/dev/null)" ] \
  && ok "no run dir is left for a later session to read" || bad "left: $(ls "$T/home/.cache/review-runs/runs")"
[ "$(wc -l < "$T/state/cwds" | tr -d ' ')" = 10 ] && ! grep -qE 'plant|twin|pass-1|plain|tiny|eval/' "$T/state/cwds" \
  && ok "a session's working directory names no fixture, arm, variant or eval" || bad "working directories: $(sed "s#$T##" "$T/state/cwds" | tr '\n' ' ')"

echo "== void runs =="
: > "$T/state/fail-once-pass-1-twin"
run_eval "$T/void.log" --arm pass-1 --variant twin --runs 2; rc=$?
P="$(row "$T/void.log" pass-1)"
[ "$rc" -eq 0 ] && has "$P" 'runs=2 | clean-twin=2/2' && has "$P" '| voided=1 |' \
  && ok "a run with no draft is void and is rerun once" || bad "rc=$rc row: $P $(grep -F '[eval]' "$T/void.log")"

FAKE_READ=/etc/hosts run_eval "$T/leak.log" --arm plain --variant twin --runs 1
L="$(row "$T/leak.log" plain)"
has "$L" 'runs=0 | voided=2 |' && grep -qF 'read outside its tree: Read file_path=/etc/hosts' "$T/leak.log" \
  && ok "a read that returned a file outside the tree voids the run and its rerun, and the cell has no measure" || bad "row: $L"

FAKE_READ=/etc/hosts FAKE_READ_ERROR=1 run_eval "$T/refused.log" --arm plain --variant twin --runs 1
L="$(row "$T/refused.log" plain)"
has "$L" 'runs=1 | clean-twin=0/1' && has "$L" '| voided=0 |' && ok "a refused read outside the tree does not void the run" || bad "row: $L"

echo "== refusals =="
out="$(JUDGE_MODEL='' REVIEWER_MODEL="$RM" bash "$HERE/run.sh" --arm plain 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "$out" 'JUDGE_MODEL is required' && ok "a billed run with no judge model is refused" || bad "rc=$rc $out"
run_eval "$T/same.log" --arm plain --variant twin --runs 1 --judge-model "$RM"; rc=$?
[ "$rc" -ne 0 ] && grep -qF 'set JUDGE_MODEL to another tier' "$T/same.log" && ok "a judge on the reviewer's tier is refused before a row is written" || bad "rc=$rc $(tail -n 3 "$T/same.log")"
run_eval "$T/denied.log" --arm plain --runs 1 --cache-dir "$T/tmp/cache"; rc=$?
[ "$rc" -ne 0 ] && grep -qF 'is inside the denied path' "$T/denied.log" && ok "a cache under a denied path is refused at the start" || bad "rc=$rc $(tail -n 3 "$T/denied.log")"

done_
