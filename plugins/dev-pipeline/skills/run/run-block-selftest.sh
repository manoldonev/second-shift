#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-block-selftest.sh — run.sh scenario slice: the run block in the PR body. The build writes one pipeline fold after
# the template, with the record link, the baseline and an empty marker pair; run.sh fills the marker region in place,
# rewrites the fold's summary to the outcome, and wraps only its own block when no fold encloses it.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-block-selftest] the run block in the PR body"

# the PR body is $FAKE_GH/live-body.md, served both to pr_conventions (pr view) and to the run block's read (api)
cat > "$T/bin/gh-live" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "api repos/o/r/pulls/7") cat "\$FAKE_GH/live-body.md" ;;
  "pr view") case "\$*" in *body*) jq -n --rawfile b "\$FAKE_GH/live-body.md" --argjson d "\$([ -f "\$FAKE_GH/draft" ] && echo true || echo false)" '{body:\$b, title:"fix: a change", isDraft:\$d}' ;; *) exec "$T/bin/gh" "\$@" ;; esac ;;
  *) exec "$T/bin/gh" "\$@" ;;
esac
EOF
chmod +x "$T/bin/gh-live"
LINK='Decision record: [docs/plans/main-42-decisions.md](https://github.com/o/r/blob/second-shift/42/docs/plans/main-42-decisions.md)'
BASE='Record baseline: 0123456789abcdef0123456789abcdef01234567'
folded_body() { # folded_body <region lines>: the template, then the build's one fold holding the marker pair
  printf '%s\n' 'built-by: second-shift run x' '' '## Summary' '' 'The consumer template section.' '' 'Closes #42' '' \
    '<details><summary>second-shift</summary>' '' '## Review focus' '' 'The build suggests:' '- a file worth a look' '' \
    '<details><summary>a nested fold the build closed</summary>' '' 'inner' '' '</details>' '' "$LINK" "$BASE" '' \
    '<!-- pipeline-cost-block -->'
  [ -z "$1" ] || printf '%s\n' "$1"
  printf '%s\n' '<!-- /pipeline-cost-block -->' '' '</details>'
}
outside() { awk '$0 == "<!-- pipeline-cost-block -->" { s = 1 } !s && !/^<details><summary>second-shift/ { print } $0 == "<!-- /pipeline-cost-block -->" { s = 0 }' "$1"; }
SUMMARY_RE='second-shift: approved after 1 round[(]s[)] · verdict approve · CI none · [$][0-9.]+'

# (b1) the build's fold holds a filled region from an earlier run: the region is replaced where it stands
fixture b1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; folded_body $'## second-shift run\n\nold block line' > "$FAKE_GH/live-body.md"
RUN_GH="$T/bin/gh-live" run_case "$d"; expect approved "(b1) a body with the build's fold"
B="$FAKE_GH/pr-body.md"
[ "$(grep -cx '<!-- pipeline-cost-block -->' "$B")" = 1 ] && [ "$(grep -cx '<!-- /pipeline-cost-block -->' "$B")" = 1 ] && ! grep -q 'old block line' "$B" \
  && grep -q '^Outcome: approved after 1 round' "$B" && grep -q '| approved |' "$B" \
  && ok "(b1) one marker region, its old content replaced by this run's report" || bad "(b1) body: $(tr '\n' '|' < "$B" | cut -c1-400)"
[ "$(grep -c '^<details' "$B")" = 2 ] && [ "$(grep -cx '</details>' "$B")" = 2 ] && ! grep -q 'Run details' "$B" \
  && ok "(b1) one pipeline fold: the build's nested fold stays, and the block adds no fold of its own" || bad "(b1) folds: $(grep -n 'details' "$B" | tr '\n' '|')"
[ "$(outside "$B")" = "$(outside "$FAKE_GH/live-body.md")" ] && grep -qxF "$LINK" "$B" && grep -qxF "$BASE" "$B" \
  && ok "(b1) every line the build wrote outside the region, the link and the baseline included, is unchanged and in place" || bad "(b1) outside the region: $(diff <(outside "$FAKE_GH/live-body.md") <(outside "$B") | tr '\n' '|')"
grep -qxE "<details><summary>$SUMMARY_RE</summary>" "$B" && [ "$(grep -n '^<details><summary>second-shift' "$B" | cut -d: -f1)" = 9 ] \
  && ok "(b1) the fold's summary, at the build's line, is rewritten to the outcome" || bad "(b1) summary: $(grep -n '<summary>' "$B" | tr '\n' '|')"
pc="$(find "$(SD)" -maxdepth 1 -name 'pr-conventions-*.txt' 2>/dev/null | head -n 1)"
[ -n "$pc" ] && [ ! -s "$pc" ] && ok "(b1) pr_conventions finds the record link inside the fold: no convention unmet" || bad "(b1) pr conventions: ${pc:-no file} $(cat "$pc" 2>/dev/null)"

# (b2) the status post fails: the summary carries the flag, the full note sits inside
fixture b2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; folded_body '' > "$FAKE_GH/live-body.md"
# the REST API's 422 body as gh reports it, the shape run-verdict-selftest.sh's cs5 posts
echo 'gh: Validation Failed (HTTP 422)' > "$FAKE_GH/status-fail"
RUN_GH="$T/bin/gh-live" run_case "$d"; expect approved "(b2) a status post that fails"
B="$FAKE_GH/pr-body.md"
grep -qxE "<details><summary>$SUMMARY_RE · status NOT posted</summary>" "$B" && grep -q '^status: NOT posted (second-shift/review=success on ' "$B" \
  && ok "(b2) the summary ends with the status NOT posted flag, and the note is in the region" || bad "(b2) summary: $(grep '<summary>' "$B" | tr '\n' '|')"

# (b3) a body from before the change: the region stands expanded among the template's lines, with no fold around it
fixture b3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
printf '%s\n' 'built-by: second-shift run x' '' '## Summary' '' 'The consumer template section.' '' "$LINK" "$BASE" '' 'Closes #42' '' \
  '<!-- pipeline-cost-block -->' '## second-shift run' '' 'Outcome: old.' '' '<details><summary>Run details</summary>' '' '| old | table |' '' '</details>' \
  '<!-- /pipeline-cost-block -->' '' '## Testing' '' 'A template section after the block.' > "$FAKE_GH/live-body.md"
RUN_GH="$T/bin/gh-live" run_case "$d"; expect approved "(b3) a body with no fold around the region"
B="$FAKE_GH/pr-body.md"
[ "$(outside "$B")" = "$(outside "$FAKE_GH/live-body.md")" ] \
  && ok "(b3) every line outside the region is unchanged and in place" || bad "(b3) outside the region: $(diff <(outside "$FAKE_GH/live-body.md") <(outside "$B") | tr '\n' '|')"
r="$(awk '$0 == "<!-- pipeline-cost-block -->" { s = 1 } s { print } $0 == "<!-- /pipeline-cost-block -->" { s = 0 }' "$B")"
[ "$(sed -n 2p <<<"$r")" != "${r%%$'\n'*}" ] && grep -qxE "<details><summary>$SUMMARY_RE</summary>" <<<"$(sed -n 2p <<<"$r")" \
  && [ "$(tail -n 2 <<<"$r" | head -n 1)" = '</details>' ] && [ "$(grep -c '^<details' <<<"$r")" = 1 ] && ! grep -q 'Run details\|Outcome: old' <<<"$r" \
  && ok "(b3) the region wraps only its own block in one fold under the outcome summary" || bad "(b3) region: $(tr '\n' '|' <<<"$r" | cut -c1-400)"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
