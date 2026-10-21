#!/usr/bin/env bash
# Model-free consistency check over data/: run.sh runs it first, and it costs nothing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/data"
rc=0
fail() { echo "check-data: $*" >&2; rc=1; }

[ -s "$D/UPSTREAM" ] || fail "data/UPSTREAM missing"
grep -Eq '^commit: [0-9a-f]{40}$' "$D/UPSTREAM" || fail "data/UPSTREAM has no 40-hex commit line"

head -1 "$D/prs.tsv" | grep -qx $'id\tproject\toriginal_url\tclone_url\tbase\thead\tset' || fail "prs.tsv header"
tail -n +2 "$D/prs.tsv" | awk -F'\t' -v OFS='\t' '
  NF != 7 { print "row " NR+1 ": " NF " columns"; bad=1 }
  seen[$1]++ { print "duplicate id " $1; bad=1 }
  $5 !~ /^[0-9a-f]{40}$/ || $6 !~ /^[0-9a-f]{40}$/ { print "row " NR+1 ": base/head not 40-hex"; bad=1 }
  $7 != "dev" && $7 != "heldout" { print "row " NR+1 ": set is " $7; bad=1 }
  $4 !~ /^https:\/\/github\.com\/[^ ]+\.git$/ { print "row " NR+1 ": clone_url " $4; bad=1 }
  END { if (bad) exit 1 }' || fail "prs.tsv rows"

n=$(tail -n +2 "$D/prs.tsv" | wc -l | tr -d ' ')
ndev=$(tail -n +2 "$D/prs.tsv" | awk -F'\t' '$7=="dev"' | wc -l | tr -d ' ')
[ "$n" -eq 50 ] || fail "expected 50 PRs, found $n"
[ "$ndev" -eq 10 ] || fail "expected 10 dev PRs, found $ndev"

for f in "$D"/golden/*.json "$D"/calibration/*.json; do jq empty "$f" 2>/dev/null || fail "$f is not JSON"; done

while IFS=$'\t' read -r id _ url _; do
  jq -e --arg u "$url" 'map(select(.url == $u)) | length == 1' "$D"/golden/*.json >/dev/null 2>&1 \
    || { cat "$D"/golden/*.json | jq -se --arg u "$url" '[.[][] | select(.url == $u)] | length == 1' >/dev/null 2>&1; } \
    || fail "$id: original_url not found exactly once in data/golden/"
  jq -e --arg k "$id" 'has($k)' "$D/calibration/"*.json >/dev/null 2>&1 || fail "$id: no calibration entry"
done < <(tail -n +2 "$D/prs.tsv")

if grep -rEl 'claude-[a-z]+-[0-9]' "$D" >/dev/null 2>&1; then fail "a model id pin is in data/ (check-eval-model-identity.sh scans it)"; fi

[ "$rc" -eq 0 ] && echo "check-data: ok ($n PRs, $ndev dev)"
exit "$rc"
