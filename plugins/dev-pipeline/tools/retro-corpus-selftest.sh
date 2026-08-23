#!/usr/bin/env bash
# retro-corpus-selftest.sh — behavioral suite for tools/retro-corpus.sh (#347).
#
# Every case executes the REAL script against a generated corpus and asserts on what it
# emits. Fixtures are hand-written in the REAL shapes the two producing tools emit
# (stage-schema JSON; lean-gate.sh-shaped progress/verdict records) rather
# than driving those tools end-to-end — the same choice makes for
# the same reason: the point here is the READER's era-detection and aggregation, and the two
# WRITERS have their own coverage — lean-gate-selftest.sh for the surviving writer, and
# a since-deleted suite for the staged one, removed in #348 along with that writer. The
# staged-era fixtures stay: the READER must still aggregate that historical corpus.
#
# A throwaway git-init'd tree stands in for the repo root (retro-corpus.sh resolves
# --git-common-dir unconditionally, even with --state-dir overriding where the corpus itself
# lives) — no commits needed, since corpus mode never checks git-committed status, only file
# existence and content.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$SCRIPT_DIR/retro-corpus.sh"
[ -f "$TOOL" ] || { echo "retro-corpus-selftest: missing $TOOL" >&2; exit 1; }
command -v jq >/dev/null || { echo "retro-corpus-selftest: jq is required" >&2; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1" >&2; }

WORK="$(mktemp -d -t retro-corpus-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

TREE="$WORK/tree"
mkdir -p "$TREE/docs/plans" "$TREE/.claude"
git -C "$TREE" init -q
git -C "$TREE" config user.email t@example.invalid
git -C "$TREE" config user.name t
# tracker.branchPrefix + the "second-shift" repo slug drive both the derived lean prefix
# (open-prs mode) and the verdict-record path formula — must match the fixture PR/comment
# data below, the same way lean-gate-selftest.sh's own synthetic config does.
jq -n '{
  tracker: {branchPrefix: "claude/second-shift-"},
  topology: {repos: {"second-shift": {path: ".", baseBranch: "main"}}},
  paths: {plansDir: "docs/plans", pipelineStateDir: ".claude/pipeline-state"}
}' > "$TREE/.claude/second-shift.config.json"

run_corpus() { ( cd "$TREE" && bash "$TOOL" corpus --state-dir "$1" --json "${@:2}" ); }
run_open_prs() { ( cd "$TREE" && bash "$TOOL" open-prs "$@" ); }

# mkstage <dir> <issue> <startedAt>  — a minimal but real stage-shaped state file.
mkstage() {
  local dir="$1" issue="$2" sa="$3"
  jq -n --arg tk "$issue" --arg sa "$sa" \
    '{ticketKey: $tk, runId: ("selftest-" + $tk), status: "completed", startedAt: $sa, stages: {"1": {status: "completed"}}}' \
    > "$dir/$issue.json"
}

# mksnapshot <dir> <stem> <ticketKey> <startedAt>  — a stage-shaped state file living
# under an OPERATOR-RENAMED basename. The suffixes the #289 cases pass are deliberately not
# ones any production code enumerates: the dedup under test is structural
# (`stem == ticketKey`), and a fixture that only ever used `-failed-` would pass just as well
# against a filename-literal implementation — which is the shape of the bug itself.
mksnapshot() {
  local dir="$1" stem="$2" tk="$3" sa="$4"
  jq -n --arg tk "$tk" --arg sa "$sa" \
    '{ticketKey: $tk, runId: ("selftest-snap-" + $tk), status: "aborted", startedAt: $sa, stages: {"1": {status: "completed"}}}' \
    > "$dir/$stem.json"
}

# mkprogress <dir> <issue> <firstTs> [model-line]  — the exact header shape
# lean-gate.sh's ensure_progress_file()/append_line write, with an optional trailing
# `model:` line (omitted entirely reproduces a pre-#347 record).
mkprogress() {
  local dir="$1" issue="$2" ts="$3" modelline="${4:-}"
  {
    echo "# lean run — issue $issue"
    echo ""
    echo "run_id: run$issue"
    echo "session_id: sess$issue"
    echo "issue: $issue"
    echo "branch_prefix: claude/second-shift-"
    echo "spec: docs/plans/second-shift-$issue-lean.md"
    echo "verdict_record: docs/plans/second-shift-$issue-lean-verdict.md"
    [ -n "$modelline" ] && echo "model: $modelline"
    echo ""
    echo "$ts | milestone-1 | satisfied"
  } > "$dir/$issue-lean-progress.md"
}

# ═══════════════════════════════════════════════════════════════════════════════════
# AC-1: artifact-schema-only corpus (no stage .json files) — must not error. Extended
# (round-1 review B2) past corpus enumeration to the REPORT path: perf-retro's Step 1
# guard decides whether to route by counting this corpus's era:"stage"
# rows, so that count is asserted here too, and the tool the guard exists to route
# around is proven to still hard-exit on the identical fixture — never a blank report.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/ac1"; mkdir -p "$D"
mkprogress "$D" 501 "2026-08-01T10:00:00Z" "claude-sonnet-5"
if OUT="$(run_corpus "$D")"; then
  N="$(jq 'length' <<<"$OUT")"
  ERA="$(jq -r '.[0].era' <<<"$OUT")"
  STAGE_ROWS="$(jq '[.[] | select(.era == "stage")] | length' <<<"$OUT")"
  if [ "$N" = "1" ] && [ "$ERA" = "artifact" ] && [ "$STAGE_ROWS" = "0" ]; then
    pass "(AC-1) artifact-only corpus: exit 0, one artifact-era row, zero stage-schema rows — the signal the report path reads"
  else
    fail "(AC-1) unexpected output — got $OUT (stage-era rows: $STAGE_ROWS)"
  fi
else
  fail "(AC-1) corpus mode exited non-zero on an artifact-only state dir"
fi

# AC-2: mixed-era corpus — both eras present, both labeled, single array.
D="$WORK/ac2"; mkdir -p "$D"
mkstage "$D" 100 "2026-08-01T09:00:00Z"
mkprogress "$D" 200 "2026-08-02T10:00:00Z" "claude-opus-5"
OUT="$(run_corpus "$D")"
ERAS="$(jq -r '[.[].era] | sort | join(",")' <<<"$OUT")"
if [ "$ERAS" = "artifact,stage" ]; then
  pass "(AC-2) mixed-era corpus aggregates both eras into one labeled array"
else
  fail "(AC-2) expected both eras present — got eras=$ERAS, output=$OUT"
fi

# AC-3: corpus-membership — a lean-schema run's ticket key appears in the sweep's input set.
D="$WORK/ac3"; mkdir -p "$D"
mkprogress "$D" 345 "2026-08-01T10:00:00Z" "claude-sonnet-5"
OUT="$(run_corpus "$D")"
MEMBER="$(jq -r '[.[].ticketKey] | index("345") != null' <<<"$OUT")"
if [ "$MEMBER" = "true" ]; then
  pass "(AC-3) lean-schema run's ticketKey (345) appears in the corpus sweep's input set"
else
  fail "(AC-3) ticketKey 345 missing from corpus output — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# AC-4: model identity rides the existing record. Present -> passed through; absent (a
# record predating #347) -> "unknown", never an error.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/ac4"; mkdir -p "$D"
mkprogress "$D" 601 "2026-08-01T10:00:00Z" "claude-opus-5"
mkprogress "$D" 602 "2026-08-01T11:00:00Z"   # no model line — pre-#347 shape
OUT="$(run_corpus "$D")"
M601="$(jq -r '.[] | select(.ticketKey == "601") | .model' <<<"$OUT")"
M602="$(jq -r '.[] | select(.ticketKey == "602") | .model' <<<"$OUT")"
if [ "$M601" = "claude-opus-5" ] && [ "$M602" = "unknown" ]; then
  pass "(AC-4) model field: present value passed through; absent (pre-#347) record reads 'unknown'"
else
  fail "(AC-4) model=601:$M601 602:$M602 — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# AC-5: open-prs — flags a lean PR verdict-less when its issue's comments carry no reference to
# the expected verdict-record path; does not flag one that does; ignores a non-lean PR entirely.
#
# WHAT "NON-LEAN" MEANS HERE CHANGED (#413). Both lanes cut `<branchPrefix><key>` branches, so
# 703 below sits on the SAME namespace as the two lean PRs and is distinguished only by carrying
# no lean spec in its own file list. Under the retired namespace filter it was excluded for
# free; now excluding it is the discriminator's job, and a regression there reports every staged
# PR as abandoned lean work.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/ac5"; mkdir -p "$D/comments"
PRLIST="$D/prs.json"
jq -n '[
  {number: 701, headRefName: "claude/second-shift-701", url: "https://example.invalid/pr/701",
   files: [{path: "docs/plans/second-shift-701-lean.md"}, {path: "src/a.ts"}]},
  {number: 702, headRefName: "claude/second-shift-702", url: "https://example.invalid/pr/702",
   files: [{path: "docs/plans/second-shift-702-lean.md"}]},
  {number: 703, headRefName: "claude/second-shift-703", url: "https://example.invalid/pr/703",
   files: [{path: "docs/plans/acme-703.md"}, {path: "src/b.ts"}]}
]' > "$PRLIST"
# 701: no comments at all -> verdict-less.
echo '[]' > "$D/comments/701.json"
# 702: a closing comment referencing the expected verdict path -> not verdict-less.
jq -n '[{body: "Closing. Verdict: docs/plans/second-shift-702-lean-verdict.md"}]' > "$D/comments/702.json"

OUT="$(run_open_prs --pr-list-file "$PRLIST" --comments-dir "$D/comments" --json)"
N="$(jq 'length' <<<"$OUT")"
VL701="$(jq -r '.[] | select(.issue == 701) | .verdictLess' <<<"$OUT")"
VL702="$(jq -r '.[] | select(.issue == 702) | .verdictLess' <<<"$OUT")"
HAS703="$(jq -r '[.[].issue] | index(703) != null' <<<"$OUT")"
if [ "$N" = "2" ] && [ "$VL701" = "true" ] && [ "$VL702" = "false" ] && [ "$HAS703" = "false" ]; then
  pass "(AC-5) open-prs: flags the verdict-less lean PR, clears the referenced one, ignores the staged PR"
else
  fail "(AC-5) n=$N vl701=$VL701 vl702=$VL702 has703=$HAS703 — got $OUT"
fi

# The discriminator is KEY-MATCHED, not "any lean-shaped file": a staged PR that merely edits an
# older ticket's lean spec is not abandoned lean work. And a lean-SHAPED fixture path casts no
# vote, for the same reason it does not at the merge boundary — this repo's trees carry
# deliberately lean-shaped fixtures.
PRLIST2="$D/prs2.json"
jq -n '[
  {number: 704, headRefName: "claude/second-shift-704", url: "https://example.invalid/pr/704",
   files: [{path: "docs/plans/second-shift-701-lean.md"}]},
  {number: 705, headRefName: "claude/second-shift-705", url: "https://example.invalid/pr/705",
   files: [{path: "scripts/fixtures/second-shift-705-lean.md"}]}
]' > "$PRLIST2"
OUT2="$(run_open_prs --pr-list-file "$PRLIST2" --comments-dir "$D/comments" --json)"
if [ "$(jq 'length' <<<"$OUT2")" = "0" ]; then
  pass "(AC-5b) open-prs: another ticket's spec and a fixture-path spec both cast no vote"
else
  fail "(AC-5b) expected no rows, got $OUT2"
fi

# A row with no `files` key at all cannot be classified. Erroring is the point: silently
# skipping it would report "no open lean work" for a list the discriminator never actually read.
jq -n '[{number: 706, headRefName: "claude/second-shift-706", url: "https://example.invalid/pr/706"}]' \
  > "$D/prs-nofiles.json"
OUT3="$(run_open_prs --pr-list-file "$D/prs-nofiles.json" --json 2>&1)"; RC3=$?
if [ "$RC3" -eq 2 ] && grep -q "carry no 'files'" <<<"$OUT3"; then
  pass "(AC-5c) open-prs: a PR list without the files field is an environment error, not an empty result"
else
  fail "(AC-5c) rc=$RC3 — got $OUT3"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# #413 AC-5: this mode resolves its namespace through the SHARED resolver, not a local copy.
# Behavioral, not a grep for an absent function: with tracker.branchPrefix UNSET, the only way
# to reach a namespace at all is branch-prefix.sh's dominant-prefix detection over the repo's
# remote refs. A re-introduced local copy would have to re-implement detection to pass this —
# and a local copy that simply restored the old `claude/acme-` default fails it outright.
# ═══════════════════════════════════════════════════════════════════════════════════
D5="$WORK/ac5-shared"; mkdir -p "$D5/comments"
CFG_NOPREFIX="$WORK/config-noprefix.json"
jq 'del(.tracker.branchPrefix)' "$TREE/.claude/second-shift.config.json" > "$CFG_NOPREFIX"
# The refs the detection votes on. `for-each-ref` reads these directly — no remote, no fetch.
git -C "$TREE" commit -q --allow-empty -m "ac5-shared fixture" 2>/dev/null
for b in team/second-shift-801 team/second-shift-802 release/1.2.0; do
  git -C "$TREE" update-ref "refs/remotes/origin/$b" HEAD
done
jq -n '[
  {number: 801, headRefName: "team/second-shift-801", url: "https://example.invalid/pr/801",
   files: [{path: "docs/plans/second-shift-801-lean.md"}]}
]' > "$D5/prs.json"
echo '[]' > "$D5/comments/801.json"
OUT5="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOPREFIX" bash "$TOOL" open-prs \
         --pr-list-file "$D5/prs.json" --comments-dir "$D5/comments" --json 2>&1 )"; RC5=$?
if [ "$RC5" -eq 0 ] && [ "$(jq -r '.[0].issue' <<<"$OUT5" 2>/dev/null)" = "801" ]; then
  pass "(AC-5d) open-prs resolves an UNSET branchPrefix through the shared detector, not a local default"
else
  fail "(AC-5d) rc=$RC5 — got $OUT5"
fi

# ...and it inherits the shared refusal, rather than falling back to anything. Same call, refs
# cleared: a local copy carrying the retired `claude/acme-` default would quietly return zero
# rows here instead of erroring, which reads as "no open lean work".
for b in team/second-shift-801 team/second-shift-802 release/1.2.0; do
  git -C "$TREE" update-ref -d "refs/remotes/origin/$b"
done
OUT5B="$( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG_NOPREFIX" bash "$TOOL" open-prs \
          --pr-list-file "$D5/prs.json" --comments-dir "$D5/comments" --json 2>&1 )"; RC5B=$?
if [ "$RC5B" -eq 2 ] && grep -q 'refusing to guess' <<<"$OUT5B"; then
  pass "(AC-5e) open-prs inherits the shared refusal on an unresolvable namespace"
else
  fail "(AC-5e) rc=$RC5B — got $OUT5B"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# help: -h/--help prints the usage doc block via `sed -n`, not a live gh/network call.
# The assertion has to be BOUNDED, not a substring probe — a since-deleted suite's
# (lc38) case found this the hard way: `sed -n '2,40p' "$0"` mutated to `sed -z '2,40p' "$0"`
# reads differently per platform. BSD sed (macOS) rejects `-z` — rc=1, nothing printed, mutant
# dies locally. GNU sed (CI's ubuntu lane) accepts `-z`, which also drops `-n`'s no-autoprint,
# so the arm dumps the ENTIRE script and still exits 0 — and the dump trivially contains
# "Usage:" too, so a contains-only check passes and the mutant survives. Require the usage
# block AND require the output to stop at the excerpt: `set -uo pipefail` is the first
# EXECUTABLE line past the range, so its presence means the whole file leaked.
#
# THE BOUND IS NOT A LITERAL (#565, AC-17b). It tracks the printed window, which tracks the
# header block. #565 added 16 documentation lines for `timing` mode, so the window moved from
# `2,40p` to `2,56p` and this bound moved from 39 to 55 in the same commit. Reading 40/39 as
# fixed numbers makes them look mutually exclusive; the invariant they encode is "the excerpt
# stops inside the header", which the `set -uo pipefail` leak check below states directly and
# which is NOT weakened by the count moving. The `timing` requirement is the other half: a
# window that no longer reaches the usage block would still satisfy the leak check.
# ═══════════════════════════════════════════════════════════════════════════════════
HELP_OUT="$(run_open_prs --help)"
HELP_RC=$?
HELP_LINES="$(printf '%s\n' "$HELP_OUT" | wc -l | tr -d ' ')"
if [ "$HELP_RC" -eq 0 ] \
   && grep -qF 'Usage:' <<<"$HELP_OUT" \
   && grep -qF 'retro-corpus.sh timing' <<<"$HELP_OUT" \
   && ! grep -qF 'set -uo pipefail' <<<"$HELP_OUT" \
   && [ "$HELP_LINES" -le 55 ]; then
  pass "(help/AC-17) '--help' prints the usage doc block including 'timing', and stops there"
else
  fail "(help/AC-17) rc=$HELP_RC, $HELP_LINES line(s) — got: $HELP_OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# verdict-detect: record_verdict() actually reads 'verdict=approve' out of the committed
# record, not just its presence — a corpus row's hasApprovedVerdict must track it. The
# verdict record path is REPO_ROOT-relative (REPO_ROOT == $TREE for every case here), so
# it is written into $TREE/docs/plans, not the --state-dir fixture.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/verdict-detect"; mkdir -p "$D"
mkprogress "$D" 801 "2026-08-01T10:00:00Z" "claude-sonnet-5"
printf 'verdict=approve\nrun_id: r1\nsession_id: s1\n' > "$TREE/docs/plans/second-shift-801-lean-verdict.md"
mkprogress "$D" 802 "2026-08-01T11:00:00Z" "claude-sonnet-5"
printf 'verdict=needs-work\nrun_id: r2\nsession_id: s2\n' > "$TREE/docs/plans/second-shift-802-lean-verdict.md"
OUT="$(run_corpus "$D")"
HV801="$(jq -r '.[] | select(.ticketKey == "801") | .hasApprovedVerdict' <<<"$OUT")"
HV802="$(jq -r '.[] | select(.ticketKey == "802") | .hasApprovedVerdict' <<<"$OUT")"
if [ "$HV801" = "true" ] && [ "$HV802" = "false" ]; then
  pass "(verdict-detect) hasApprovedVerdict is true only for a record reading verdict=approve"
else
  fail "(verdict-detect) hv801=$HV801 hv802=$HV802 — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# verdict-detect-worktree (W2, round-1 review): the case above never distinguishes
# REPO_ROOT from MAIN_ROOT because $TREE stands in for both. Run corpus mode from a REAL
# worktree of $TREE instead — the verdict record lives in $TREE/docs/plans (the main
# checkout), never copied into the worktree, so hasApprovedVerdict is only correct when
# the reader resolves it via MAIN_ROOT (--git-common-dir anchored, same as state_dir()),
# not the caller's own --show-toplevel.
# ═══════════════════════════════════════════════════════════════════════════════════
WT="$WORK/verdict-detect-wt"
git -C "$TREE" worktree add -q -b wt-verdict-detect "$WT" >/dev/null 2>&1
D="$WORK/verdict-detect-wt-state"; mkdir -p "$D"
mkprogress "$D" 901 "2026-08-01T12:00:00Z" "claude-sonnet-5"
printf 'verdict=approve\nrun_id: r3\nsession_id: s3\n' > "$TREE/docs/plans/second-shift-901-lean-verdict.md"
OUT="$(cd "$WT" && bash "$TOOL" corpus --state-dir "$D" --json)"
HV901="$(jq -r '.[] | select(.ticketKey == "901") | .hasApprovedVerdict' <<<"$OUT")"
if [ "$HV901" = "true" ]; then
  pass "(verdict-detect-worktree) hasApprovedVerdict resolves from the main checkout, not the worktree the tool runs in"
else
  fail "(verdict-detect-worktree) expected true from a worktree caller, got hv901=$HV901 — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# #289 AC-1/AC-2/AC-4/AC-5: structural per-ticket dedup over era: "stage" rows.
#
# The live corpus this fixture models: a ticket's live `{key}.json` co-existing with
# operator-renamed snapshots of earlier runs of the SAME ticket, which keep their `stages`
# key and are in neither quarantine family — so before this they aggregated as
# their own runs and the ticket counted several times.
#
# 310  live + two snapshots under two different suffixes  -> one row, the live one (AC-1)
# 320  two snapshots, NO live file                        -> both rows survive (AC-2)
# 340  live stage file + a lean progress record           -> both rows survive (AC-4)
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/dedup"; mkdir -p "$D"
mkstage    "$D" 310 "2026-08-05T12:00:00Z"
mksnapshot "$D" "310-failed-2026-08-01T100429Z"       310 "2026-08-01T10:04:29Z"
mksnapshot "$D" "310-spec-blocked-2026-08-02T090000Z" 310 "2026-08-02T09:00:00Z"
mksnapshot "$D" "320-aborted-2026-08-03T080000Z"      320 "2026-08-03T08:00:00Z"
mksnapshot "$D" "320-escalated-2026-08-04T080000Z"    320 "2026-08-04T08:00:00Z"
mkstage    "$D" 340 "2026-08-05T13:00:00Z"
mkprogress "$D" 340 "2026-08-05T14:00:00Z" "claude-opus-5"

ERRF="$WORK/dedup.err"
OUT="$( cd "$TREE" && bash "$TOOL" corpus --state-dir "$D" --json 2>"$ERRF" )"; RCD=$?
ERR="$(cat "$ERRF")"
N310="$(jq '[.[] | select(.era == "stage" and .ticketKey == "310")] | length' <<<"$OUT")"
S310="$(jq -r '[.[] | select(.era == "stage" and .ticketKey == "310") | .stem] | join(",")' <<<"$OUT")"
N320="$(jq '[.[] | select(.era == "stage" and .ticketKey == "320")] | length' <<<"$OUT")"
S320="$(jq -r '[.[] | select(.era == "stage" and .ticketKey == "320") | .stem] | sort | join(",")' <<<"$OUT")"
E340="$(jq -r '[.[] | select(.ticketKey == "340") | .era] | sort | join(",")' <<<"$OUT")"

if [ "$RCD" -eq 0 ] && [ "$N310" = "1" ] && [ "$S310" = "310" ]; then
  pass "(289 AC-1) a live {key}.json supersedes every operator-renamed snapshot of that ticket, whatever suffix it carries"
else
  fail "(289 AC-1) rc=$RCD n310=$N310 stems=$S310 — got $OUT"
fi

if [ "$N320" = "2" ] \
   && [ "$S320" = "320-aborted-2026-08-03T080000Z,320-escalated-2026-08-04T080000Z" ]; then
  pass "(289 AC-2) with no live file, every snapshot survives as a distinct run — an orphan snapshot is that run's only record"
else
  fail "(289 AC-2) n320=$N320 stems=$S320 — got $OUT"
fi

if [ "$E340" = "artifact,stage" ]; then
  pass "(289 AC-4) a lean record is never keyed by the dedup — it survives alongside a stage-era live file of the same ticket"
else
  fail "(289 AC-4) expected both eras for ticket 340, got eras=$E340 — got $OUT"
fi

# AC-5, the disclosure side: 6 stage-schema files in, 2 superseded, said on STDERR — stdout
# stays the bare array both consumers read with `.[] | …`.
if grep -q '6 stage-schema file(s), 2 superseded' <<<"$ERR" \
   && printf '%s' "$OUT" | jq -e 'type == "array"' >/dev/null 2>&1; then
  pass "(289 AC-5) the suppression is disclosed on stderr with both counts, and stdout stays a bare array"
else
  fail "(289 AC-5) stderr=$ERR — stdout=$OUT"
fi

# Same corpus through the default (TSV) mode: dedup is not a --json-only path, and the note
# still goes to stderr rather than into the tab-separated rows a caller may parse.
ERRF2="$WORK/dedup-tsv.err"
TSV="$( cd "$TREE" && bash "$TOOL" corpus --state-dir "$D" 2>"$ERRF2" )"
TSV310="$(printf '%s\n' "$TSV" | awk -F'\t' '$1 == "stage" && $2 == "310"' | wc -l | tr -d ' ')"
if [ "$TSV310" = "1" ] && ! grep -q 'superseded' <<<"$TSV" \
   && grep -q 'superseded' "$ERRF2"; then
  pass "(289 AC-5) TSV mode dedups identically and keeps the note off stdout"
else
  fail "(289 AC-5/tsv) tsv310=$TSV310 — stdout=$TSV stderr=$(cat "$ERRF2")"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# #289 AC-3: the dedup runs BEFORE the --window slice. Sorted by startedAt the pre-dedup
# order is 410, 410-snapshot, 420 — so deduping after a `--window 2` slice would spend a
# slot on the snapshot and drop ticket 420 from a two-run window entirely.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/dedup-window"; mkdir -p "$D"
mkstage    "$D" 410 "2026-08-05T12:00:00Z"
mksnapshot "$D" "410-failed-2026-08-05T110000Z" 410 "2026-08-05T11:00:00Z"
mkstage    "$D" 420 "2026-08-05T10:00:00Z"
OUT="$(run_corpus "$D" --window 2 2>/dev/null)"
KEYS="$(jq -r '[.[].ticketKey] | sort | join(",")' <<<"$OUT")"
if [ "$KEYS" = "410,420" ]; then
  pass "(289 AC-3) dedup precedes the --window slice — a superseded snapshot never consumes a window slot"
else
  fail "(289 AC-3) expected 410,420 in a 2-run window, got keys=$KEYS — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# #289 AC-5, the silence side: a corpus with nothing superseded emits NOTHING on stderr.
# pipeline-retro's no-argument path calls corpus mode on every invocation, so an
# unconditional note would be banner noise on every run, carrying no information.
# ═══════════════════════════════════════════════════════════════════════════════════
D="$WORK/dedup-quiet"; mkdir -p "$D"
mkstage    "$D" 510 "2026-08-05T12:00:00Z"
mksnapshot "$D" "520-failed-2026-08-05T110000Z" 520 "2026-08-05T11:00:00Z"
mkprogress "$D" 530 "2026-08-05T10:00:00Z" "claude-sonnet-5"
ERRF3="$WORK/dedup-quiet.err"
OUT="$( cd "$TREE" && bash "$TOOL" corpus --state-dir "$D" --json 2>"$ERRF3" )"
NQ="$(jq 'length' <<<"$OUT")"
if [ "$NQ" = "3" ] && [ ! -s "$ERRF3" ]; then
  pass "(289 AC-5) a corpus with nothing superseded keeps all three rows and says nothing on stderr"
else
  fail "(289 AC-5/quiet) n=$NQ stderr=$(cat "$ERRF3") — got $OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# #565 — `timing` mode. Every case below drives the REAL subcommand against generated
# progress records, the same posture the corpus cases take.
#
# WHY THE FIXTURES LOOK LIKE THIS. The record has two incompatible grammar generations inside
# the artifact era, and the ONLY span primitive both write is `| milestone-N | satisfied`. A
# fixture set drawn from one generation would let a parser keyed on `started`/`concluded`
# (~9 of 51 real records) or on `verdict=approve` (~11, old grammar only) pass while silently
# profiling a fraction of the corpus — which is the defect this mode exists to avoid, not a
# hypothetical. So each generation gets its own record, and the flag cases are built to be
# DISCRIMINATING: the re-run fixture's spans differ under a concluded-based rule, the rounds
# fixture's max differs from its first, last and count, and the truncated fixture carries a
# later row that a "last row" wall-clock fallback would happily use.
# ═══════════════════════════════════════════════════════════════════════════════════

run_timing() { ( cd "$TREE" && bash "$TOOL" timing --state-dir "$1" --json "${@:2}" ); }

# mktiming <dir> <issue> [model] — header in lean-gate.sh's exact shape, body rows on STDIN.
# An empty model argument reproduces a record written before the `model:` key existed.
mktiming() {
  local dir="$1" issue="$2" modelline="${3:-}"
  {
    echo "# lean run — issue $issue"
    echo ""
    echo "run_id: run$issue"
    echo "session_id: sess$issue"
    echo "issue: $issue"
    echo "branch_prefix: claude/second-shift-"
    echo "spec: docs/plans/second-shift-$issue-lean.md"
    echo "verdict_record: docs/plans/second-shift-$issue-lean-verdict.md"
    [ -n "$modelline" ] && echo "model: $modelline"
    echo ""
    cat
  } > "$dir/$issue-lean-progress.md"
}

# tf <json> <ticketKey> <jq-path> — one field of one run's row.
tf() { jq -r --arg k "$2" ".[] | select(.ticketKey == \$k) | $3" <<<"$1"; }

T="$WORK/timing"; mkdir -p "$T"

# 901 — new grammar, complete, terminated. The reference run.
mktiming "$T" 901 "opus" <<'EOF'
2026-08-10T10:00:00Z | entry | ledger=/x/s901.jsonl | lines=10 | telemetry=on | session=sess901
2026-08-10T10:05:00Z | milestone-1 | started |
2026-08-10T10:05:30Z | milestone-1 | satisfied
2026-08-10T10:05:30Z | milestone-1 | concluded | rc=0
2026-08-10T10:20:00Z | milestone-2 | started |
2026-08-10T10:20:20Z | milestone-2 | satisfied
2026-08-10T10:20:20Z | milestone-2 | concluded | rc=0
2026-08-10T10:50:00Z | milestone-3 | started |
2026-08-10T10:51:00Z | milestone-3 | satisfied
2026-08-10T10:51:00Z | milestone-3 | concluded | rc=0
2026-08-10T11:30:00Z | milestone-4 | verdict=approve | round=1
2026-08-10T11:30:10Z | milestone-4 | satisfied
2026-08-10T11:30:10Z | milestone-4 | concluded | rc=0
2026-08-10T12:00:00Z | milestone-5 | satisfied
EOF

OUT="$(run_timing "$T")"
W="$(tf "$OUT" 901 .wallClockMin)"
SP="$(tf "$OUT" 901 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
FID="$(tf "$OUT" 901 '.fidelity | join(",")')"
RD="$(tf "$OUT" 901 .rounds)"
# 10:00:00 -> 11:30:10 is 90m10s; spans are floored independently and sum to 88, which is
# exactly why AC-7c forbids asserting sum(spans) == wallClockMin anywhere.
if [ "$W" = "90" ] && [ "$SP" = "1=5,2=14,3=30,4=39" ] && [ "$FID" = "" ] && [ "$RD" = "1" ]; then
  pass "(565 AC-2/AC-4/AC-10) terminated new-grammar run: wall-clock 90, spans 5/14/30/39, rounds 1, no fidelity flag"
else
  fail "(565 AC-2/AC-4) wall=$W spans=$SP rounds=$RD fidelity=$FID"
fi

# AC-2b: the record carries `milestone-5 | satisfied` 30 minutes past the run's end. A spans
# map that reaches milestone 5 measures close-out bookkeeping as run time — on real record 283
# that row lands 605 minutes after a 41-minute wall-clock.
if [ "$(tf "$OUT" 901 '.spans | has("5")')" = "false" ]; then
  pass "(565 AC-2b) spans stop at milestone 4 even when the record carries milestone-5 | satisfied"
else
  fail "(565 AC-2b) spans reached milestone 5 — got $(tf "$OUT" 901 .spans)"
fi

# AC-7: every `concluded` here lands ON its `satisfied` stamp, never after, so the churn
# diagnostic is a measured ZERO — distinct from the null AC-7b requires on a record that has no
# `concluded` row at all. A rule that conflated the two would report both as 0.
if [ "$(tf "$OUT" 901 .reverifyMin)" = "0" ]; then
  pass "(565 AC-7) reverifyMin is a measured 0 when no concluded row follows a satisfied row"
else
  fail "(565 AC-7) expected 0, got $(tf "$OUT" 901 .reverifyMin)"
fi

# ── 902: re-verified after satisfaction. THE discriminating case for AC-8: milestone 3 is
# satisfied at 09:40 and re-concluded at 10:02, so a concluded-based span would read 62 minutes
# where the satisfied-based one reads 20.
mktiming "$T" 902 "opus" <<'EOF'
2026-08-11T09:00:00Z | entry | ledger=/x/s902.jsonl | lines=4 | telemetry=on | session=sess902
2026-08-11T09:00:30Z | milestone-1 | started |
2026-08-11T09:10:00Z | milestone-1 | satisfied
2026-08-11T09:10:00Z | milestone-1 | concluded | rc=0
2026-08-11T09:20:00Z | milestone-2 | satisfied
2026-08-11T09:40:00Z | milestone-3 | satisfied
2026-08-11T09:50:00Z | milestone-3 | started |
2026-08-11T10:02:00Z | milestone-3 | concluded | rc=0
2026-08-11T10:30:00Z | milestone-4 | satisfied
EOF
OUT="$(run_timing "$T")"
SP="$(tf "$OUT" 902 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
RV="$(tf "$OUT" 902 .reverifyMin)"
FID="$(tf "$OUT" 902 '.fidelity | join(",")')"
if [ "$SP" = "1=10,2=10,3=20,4=50" ] && [ "$RV" = "22" ] && [ "$FID" = "re-run" ]; then
  pass "(565 AC-8) re-verification flags re-run and moves no span; the churn lands in reverifyMin (22)"
else
  fail "(565 AC-8) spans=$SP reverify=$RV fidelity=$FID"
fi

# ── 903: old grammar, no `model:` key. AC-9's point is that AC-2 and AC-4 still produce values
# here — both key off `satisfied`, which every generation writes — while AC-7 yields null.
mktiming "$T" 903 "" <<'EOF'
2026-08-12T08:00:00Z | milestone-1 | attempt | no committed spec at docs/plans/second-shift-903-lean.md
2026-08-12T08:10:00Z | milestone-1 | satisfied
2026-08-12T08:25:00Z | milestone-2 | satisfied
2026-08-12T08:40:00Z | milestone-3 | satisfied
2026-08-12T09:00:00Z | milestone-4 | verdict=approve | round=2
2026-08-12T09:05:00Z | milestone-4 | satisfied
2026-08-12T09:30:00Z | milestone-5 | satisfied
EOF
OUT="$(run_timing "$T")"
W="$(tf "$OUT" 903 .wallClockMin)"
SP="$(tf "$OUT" 903 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
RV="$(tf "$OUT" 903 .reverifyMin)"
MD="$(tf "$OUT" 903 .model)"
FID="$(tf "$OUT" 903 '.fidelity | sort | join(",")')"
if [ "$W" = "65" ] && [ "$SP" = "1=10,2=15,3=15,4=25" ] && [ "$RV" = "null" ] \
   && [ "$MD" = "unknown" ] && [ "$FID" = "old-grammar,unknown-model" ]; then
  pass "(565 AC-9/AC-7b/AC-15) old-grammar record still yields wall-clock 65 and spans; reverifyMin null, model unknown"
else
  fail "(565 AC-9) wall=$W spans=$SP reverify=$RV model=$MD fidelity=$FID"
fi

# ── 904: truncated — the shape 27 of 51 real records take, where the build session's record
# ends where that session ends. New-grammar on purpose, so the case isolates truncation from
# the grammar generation. The 09:00 `| session |` row is 60 minutes past the last milestone
# and is the bait for AC-6: any "last row" fallback reports a 130-minute run that never ended.
mktiming "$T" 904 "sonnet" <<'EOF'
2026-08-13T06:50:00Z | entry | ledger=/x/s904.jsonl | lines=6 | telemetry=on | session=sess904
2026-08-13T06:59:00Z | milestone-1 | started |
2026-08-13T07:00:00Z | milestone-1 | satisfied
2026-08-13T07:00:00Z | milestone-1 | concluded | rc=0
2026-08-13T07:29:00Z | milestone-2 | started |
2026-08-13T07:30:00Z | milestone-2 | satisfied
2026-08-13T07:30:00Z | milestone-2 | concluded | rc=0
2026-08-13T07:55:00Z | milestone-3 | started |
2026-08-13T08:00:00Z | milestone-3 | satisfied
2026-08-13T08:00:00Z | milestone-3 | concluded | rc=0
2026-08-13T09:00:00Z | session | 11111111-2222-3333-4444-555555555555
EOF
OUT="$(run_timing "$T")"
W="$(tf "$OUT" 904 .wallClockMin)"
SP="$(tf "$OUT" 904 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
RV="$(tf "$OUT" 904 .reverifyMin)"
FID="$(tf "$OUT" 904 '.fidelity | join(",")')"
if [ "$W" = "null" ] && [ "$RV" = "null" ] && [ "$SP" = "1=10,2=30,3=30" ] && [ "$FID" = "truncated-record" ]; then
  pass "(565 AC-5/AC-6) truncated record: null wall-clock despite a later row and despite concluded rows, spans still emitted"
else
  fail "(565 AC-5/AC-6) wall=$W spans=$SP reverify=$RV fidelity=$FID"
fi

# ── 905: milestone-4 rows exist, none satisfied. "Never got there" and "got there and failed"
# have to stay distinguishable, so this must NOT read truncated-record.
mktiming "$T" 905 "sonnet" <<'EOF'
2026-08-14T07:00:00Z | entry | ledger=/x/s905.jsonl | lines=5 | telemetry=on | session=sess905
2026-08-14T07:05:00Z | milestone-1 | started |
2026-08-14T07:05:10Z | milestone-1 | satisfied
2026-08-14T07:05:10Z | milestone-1 | concluded | rc=0
2026-08-14T07:20:00Z | milestone-4 | started |
2026-08-14T07:20:05Z | milestone-4 | attempt | no committed verdict record
2026-08-14T07:20:05Z | milestone-4 | concluded | rc=1
EOF
OUT="$(run_timing "$T")"
FID="$(tf "$OUT" 905 '.fidelity | join(",")')"
if [ "$FID" = "unterminated" ] && [ "$(tf "$OUT" 905 .wallClockMin)" = "null" ]; then
  pass "(565 AC-5) a record with unsatisfied milestone-4 rows reads 'unterminated', not 'truncated-record'"
else
  fail "(565 AC-5/unterminated) fidelity=$FID wall=$(tf "$OUT" 905 .wallClockMin)"
fi

# ── 906/907: the over-24h trigger is the MEASURED interval to milestone-4 | satisfied, not the
# span of the whole record. 907 is real record 283's shape: a 41-minute run whose milestone-5
# row lands the next morning, which a record-width trigger would flag.
mktiming "$T" 906 "sonnet" <<'EOF'
2026-08-15T06:00:00Z | entry | ledger=/x/s906.jsonl | lines=3 | telemetry=on | session=sess906
2026-08-15T06:10:00Z | milestone-1 | satisfied
2026-08-15T06:40:00Z | milestone-2 | satisfied
2026-08-15T07:00:00Z | milestone-3 | satisfied
2026-08-16T09:00:00Z | milestone-4 | satisfied
EOF
mktiming "$T" 907 "sonnet" <<'EOF'
2026-08-17T22:26:51Z | milestone-1 | satisfied
2026-08-17T22:47:29Z | milestone-2 | satisfied
2026-08-17T22:52:30Z | milestone-3 | satisfied
2026-08-17T23:08:02Z | milestone-4 | satisfied
2026-08-18T09:13:29Z | milestone-5 | satisfied
EOF
OUT="$(run_timing "$T")"
F906="$(tf "$OUT" 906 '.fidelity | index("over-24h") != null')"
F907="$(tf "$OUT" 907 '.fidelity | index("over-24h") != null')"
W907="$(tf "$OUT" 907 .wallClockMin)"
if [ "$F906" = "true" ] && [ "$F907" = "false" ] && [ "$W907" = "41" ]; then
  pass "(565 AC-14) over-24h keys off the measured interval: a 27-hour run flags, a 41-minute run with a next-day milestone-5 does not"
else
  fail "(565 AC-14) 906 over-24h=$F906, 907 over-24h=$F907 wall=$W907"
fi

# ── 908: no parseable timestamped row at all. Emitted with null spans, never dropped silently.
mktiming "$T" 908 "sonnet" <<'EOF'
(this record's rows were lost)
EOF
OUT="$(run_timing "$T")"
if [ "$(tf "$OUT" 908 .stem)" = "908-lean-progress" ] \
   && [ "$(tf "$OUT" 908 .startedAt)" = "null" ] \
   && [ "$(tf "$OUT" 908 '.spans | length')" = "0" ] \
   && [ "$(tf "$OUT" 908 '.fidelity | index("no-chronology") != null')" = "true" ]; then
  pass "(565 AC-1/AC-5) a record with no timestamped row is emitted with null spans and no-chronology, never dropped"
else
  fail "(565 no-chronology) got $(jq -c --arg k 908 '.[] | select(.ticketKey == $k)' <<<"$OUT")"
fi

# ── 909: rounds is max(round=N) matched ANYWHERE on the line. This fixture defeats four wrong
# rules at once: first-token (1), last-token (1), attempt-count (3) and verdict-row-count (3).
# The winning token sits at column 0 with no timestamp, the shape real records 107 and 115 carry.
mktiming "$T" 909 "sonnet" <<'EOF'
2026-08-19T05:00:00Z | milestone-1 | satisfied
2026-08-19T05:05:00Z | milestone-4 | verdict=needs-work | round=1
2026-08-19T05:10:00Z | milestone-4 | attempt | no committed verdict record
milestone-4 | verdict=approve | round=2
2026-08-19T05:15:00Z | milestone-4 | attempt | still no committed verdict record
2026-08-19T05:20:00Z | milestone-4 | attempt | still no committed verdict record
2026-08-19T05:25:00Z | milestone-4 | verdict=needs-work | round=1
2026-08-19T05:30:00Z | milestone-4 | satisfied
EOF
OUT="$(run_timing "$T")"
if [ "$(tf "$OUT" 909 .rounds)" = "2" ]; then
  pass "(565 AC-10/AC-11) rounds is max(round=N) from an un-timestamped row — not the first, last, attempt count or verdict-row count"
else
  fail "(565 AC-10/AC-11) expected rounds=2, got $(tf "$OUT" 909 .rounds)"
fi
if [ "$(tf "$OUT" 904 .rounds)" = "null" ]; then
  pass "(565 AC-10) a record carrying no round= token reads null, not 0"
else
  fail "(565 AC-10/null) expected null, got $(tf "$OUT" 904 .rounds)"
fi

# ── 910/911: the orchestration discriminator is a spawn transcript beside the records, and it
# is one-directional. Its ABSENCE never implies `manual`: run_id has no orchestrator-only shape,
# so there is no positive discriminator for a hand-run lane (OR-1), and an inferred `manual`
# arm would publish a split that is really "transcript present vs. anything else".
mktiming "$T" 910 "sonnet" <<'EOF'
2026-08-19T06:00:00Z | milestone-1 | satisfied
EOF
mktiming "$T" 911 "sonnet" <<'EOF'
2026-08-19T06:30:00Z | milestone-1 | satisfied
EOF
: > "$T/910-lean-spawn-1-build.log"
OUT="$(run_timing "$T")"
MANUAL="$(jq -r '[.[] | select(.orchestrated == "manual")] | length' <<<"$OUT")"
if [ "$(tf "$OUT" 910 .orchestrated)" = "orchestrated" ] \
   && [ "$(tf "$OUT" 911 .orchestrated)" = "indeterminate" ] && [ "$MANUAL" = "0" ]; then
  pass "(565 AC-12/AC-13) a matching *-lean-spawn-*.log reads 'orchestrated'; its absence reads 'indeterminate' and never 'manual'"
else
  fail "(565 AC-12/AC-13) 910=$(tf "$OUT" 910 .orchestrated) 911=$(tf "$OUT" 911 .orchestrated) manual-rows=$MANUAL"
fi

# ── 912: `satisfied` is idempotent in production (lean-gate.sh's append_satisfied returns
# early, D-41), so a second one cannot occur — which is exactly why this fixture is worth
# writing. It pins that NO rule anywhere selects a "last" occurrence: under a last-occurrence
# rule the two spans below swap to 1=50,2=10.
mktiming "$T" 912 "sonnet" <<'EOF'
2026-08-20T04:00:00Z | entry | ledger=/x/s912.jsonl | lines=2 | telemetry=on | session=sess912
2026-08-20T04:10:00Z | milestone-1 | satisfied
2026-08-20T04:50:00Z | milestone-1 | satisfied
2026-08-20T05:00:00Z | milestone-2 | satisfied
2026-08-20T05:30:00Z | milestone-4 | satisfied
EOF
OUT="$(run_timing "$T")"
SP="$(tf "$OUT" 912 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
if [ "$SP" = "1=10,2=50,4=30" ]; then
  pass "(565 AC-3) satisfied(N) is the record's single row: a duplicate does not become a 'latest' occurrence"
else
  fail "(565 AC-3) expected 1=10,2=50,4=30, got $SP"
fi
# AC-2's chain skips a never-satisfied milestone rather than breaking: 912 never satisfies
# milestone 3, and milestone 4 measures from milestone 2 — 05:00 to 05:30 — not from the
# record's first row, and milestone 3 is ABSENT rather than zero.
if [ "$(tf "$OUT" 912 '.spans | has("3")')" = "false" ]; then
  pass "(565 AC-2) a never-satisfied milestone is absent from spans, and the next span measures from the last one that was"
else
  fail "(565 AC-2/skip) milestone 3 present in spans — got $SP"
fi

# ── 914: AC-2 applied to an OUT-OF-ORDER record, which the real corpus contains. This is
# `109-lean-progress.md`'s shape to the second: milestone 1 is satisfied at 12:52:14, AFTER
# milestone 2 at 11:55:09, so span(2) measures backwards and is genuinely negative. The value is
# emitted as measured — clamping it to 0 would read as a fast milestone instead of as the
# out-of-order record it is, and the fidelity enum is closed, so there is no flag to route it to.
#
# The stamps are chosen so the negative span is NOT a whole number of minutes: -57m05s floors to
# -58 and TRUNCATES to -57. bash's `/` truncates toward zero, so an implementation that reaches
# for it directly — or one that drops the negative arm of the floor — reports -57 here and is
# correct on every non-negative span in the suite.
mktiming "$T" 914 "sonnet" <<'EOF'
2026-08-21T11:30:16Z | milestone-1 | attempt | no committed spec at docs/plans/second-shift-914-lean.md
2026-08-21T11:55:09Z | milestone-2 | satisfied
2026-08-21T12:09:21Z | milestone-3 | satisfied
2026-08-21T12:52:08Z | milestone-4 | satisfied
2026-08-21T12:52:14Z | milestone-1 | satisfied
EOF
OUT="$(run_timing "$T")"
SP="$(tf "$OUT" 914 '.spans | to_entries | map("\(.key)=\(.value)") | join(",")')"
W="$(tf "$OUT" 914 .wallClockMin)"
if [ "$SP" = "1=81,2=-58,3=14,4=42" ] && [ "$W" = "81" ]; then
  pass "(565 AC-2c) an out-of-order record yields a negative span, FLOORED not truncated, and is never clamped"
else
  fail "(565 AC-2c) expected spans 1=81,2=-58,3=14,4=42 and wall 81 — got spans=$SP wall=$W"
fi

# ── AC-1: window and sort semantics mirror corpus — newest-first on startedAt, THEN the slice.
OUT="$(run_timing "$T" --window 2)"
KEYS="$(jq -r '[.[].ticketKey] | join(",")' <<<"$OUT")"
# 914 (2026-08-21) then 912 (2026-08-20) are the two newest startedAt values in $T. An
# unsorted slice would return the two the glob happened to reach first.
if [ "$KEYS" = "914,912" ]; then
  pass "(565 AC-1) rows sort newest-first on startedAt before the --window slice, matching corpus"
else
  fail "(565 AC-1/window) expected 912,911 — got $KEYS"
fi
( cd "$TREE" && bash "$TOOL" timing --state-dir "$WORK/no-such-dir" >/dev/null 2>&1 )
if [ $? -eq 2 ]; then
  pass "(565 AC-1) a missing state dir exits 2, the same environment-error code corpus uses"
else
  fail "(565 AC-1/rc) expected rc=2 on a missing state dir"
fi

# ── AC-1: selection is the SAME structural `verdict_record:` test corpus uses. A .md file in
# the state dir without that header key is not a run record, whatever it is named — a filename
# literal would either sweep this in or, on a future naming convention, silently miss real ones.
printf '# notes\n\n2026-08-20T04:00:00Z | milestone-1 | satisfied\n' > "$T/913-lean-progress.md"
OUT="$(run_timing "$T")"
if [ "$(jq -r '[.[] | select(.stem == "913-lean-progress")] | length' <<<"$OUT")" = "0" ]; then
  pass "(565 AC-1) selection is structural: a .md file carrying no verdict_record: key is not a run record"
else
  fail "(565 AC-1/selection) 913 was enumerated without a verdict_record: header key"
fi
rm -f "$T/913-lean-progress.md"

# ── AC-16: corpus's stdout contract is untouched by the new mode. Both shapes are asserted on
# the SAME directory timing reads, so a change that leaked a timing field into corpus rows — or
# a column into its TSV — fails here rather than in a consumer.
CORPUS_TSV="$( cd "$TREE" && bash "$TOOL" corpus --state-dir "$T" 2>/dev/null )"
COLS="$(printf '%s\n' "$CORPUS_TSV" | head -n1 | awk -F'\t' '{print NF}')"
EXTRA="$( cd "$TREE" && bash "$TOOL" corpus --state-dir "$T" --json 2>/dev/null \
  | jq -r '[.[] | keys[]] | unique | map(select(. as $k | ["stem","ticketKey","era","startedAt","model","hasApprovedVerdict"] | index($k) | not)) | join(",")' )"
if [ "$COLS" = "4" ] && [ -z "$EXTRA" ]; then
  pass "(565 AC-16) corpus keeps its 4-column TSV and its exact JSON key set — no timing field leaks in"
else
  fail "(565 AC-16) corpus TSV columns=$COLS, unexpected JSON keys='$EXTRA'"
fi

# ── AC-15: `model` is passed through verbatim, never mapped. A mapping table would put a vendor
# model string in the implementation, which AC-15 forbids outright.
if [ "$(tf "$OUT" 901 .model)" = "opus" ] \
   && [ "$(tf "$OUT" 901 '.fidelity | index("unknown-model")')" = "null" ]; then
  pass "(565 AC-15) a present model rides through unmapped and raises no unknown-model flag"
else
  fail "(565 AC-15) model=$(tf "$OUT" 901 .model) fidelity=$(tf "$OUT" 901 '.fidelity | join(","))')"
fi

# ── The default (no --json) rendering: no header row, and one `-` spelling for every empty
# thing. corpus renders a missing startedAt as "unknown"; timing does not change that, and does
# not adopt it either — two renderings, each stated where it applies.
TSV="$( cd "$TREE" && bash "$TOOL" timing --state-dir "$T" 2>/dev/null )"
ROW904="$(printf '%s\n' "$TSV" | awk -F'\t' '$1 == "904"')"
TSV_HEAD="$(printf '%s\n' "$TSV" | head -n1)"
if [ "$ROW904" = "$(printf '904\t-\t1=10,2=30,3=30\t-\t-\tindeterminate\tsonnet\ttruncated-record')" ] \
   && ! grep -qF 'ticketKey' <<<"$TSV_HEAD"; then
  pass "(565 data contract) TSV renders nulls and empties as '-', in column order, with no header row"
else
  fail "(565 data contract) row904='$ROW904'"
fi

# ── AC-24: no bash-4 construct. The stock-3.2 macOS lane fails OPEN on `declare -A` — the
# associative array simply never populates — so this is a source check, not a runtime one.
if ! grep -qE 'declare -A|\$\{[A-Za-z_]+\^\^\}|\bmapfile\b|readarray' "$TOOL"; then
  pass "(565 AC-24) the tool carries no declare -A, no case-modification expansion and no mapfile/readarray"
else
  fail "(565 AC-24) a bash-4-only construct is present in $TOOL"
fi

echo ""
echo "retro-corpus-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
