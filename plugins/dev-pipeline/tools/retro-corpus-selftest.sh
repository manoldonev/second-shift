#!/usr/bin/env bash
# retro-corpus-selftest.sh — behavioral suite for tools/retro-corpus.sh (#347).
#
# Every case executes the REAL script against a generated corpus and asserts on what it
# emits. Fixtures are hand-written in the REAL shapes the two producing tools emit
# (statectl-shaped stage-schema JSON; lean-gate.sh-shaped progress/verdict records) rather
# than driving those tools end-to-end — the same choice stage-envelopes-selftest.sh makes for
# the same reason: the point here is the READER's era-detection and aggregation, and the two
# WRITERS already have their own coverage (statectl-selftest.sh, lean-gate-selftest.sh).
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

# mkstage <dir> <issue> <startedAt>  — a minimal but real statectl-shaped state file.
mkstage() {
  local dir="$1" issue="$2" sa="$3"
  jq -n --arg tk "$issue" --arg sa "$sa" \
    '{ticketKey: $tk, runId: ("selftest-" + $tk), status: "completed", startedAt: $sa, stages: {"1": {status: "completed"}}}' \
    > "$dir/$issue.json"
}

# mksnapshot <dir> <stem> <ticketKey> <startedAt>  — a statectl-shaped state file living
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
# guard decides whether to call stage-envelopes.sh by counting this corpus's era:"stage"
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
    pass "(AC-1) artifact-only corpus: exit 0, one artifact-era row, zero stage-era rows — the signal perf-retro's report path reads to skip stage-envelopes.sh"
  else
    fail "(AC-1) unexpected output — got $OUT (stage-era rows: $STAGE_ROWS)"
  fi
else
  fail "(AC-1) corpus mode exited non-zero on an artifact-only state dir"
fi

STAGE_ENV_TOOL="$SCRIPT_DIR/stage-envelopes.sh"
if [ -f "$STAGE_ENV_TOOL" ] && ! bash "$STAGE_ENV_TOOL" --state-dir "$D" >/dev/null 2>&1; then
  pass "(AC-1) stage-envelopes.sh still hard-exits on the same artifact-only state dir — the report path must route around it via the era count, not by catching its failure"
else
  fail "(AC-1) stage-envelopes.sh did not hard-exit on an artifact-only state dir — the report-path guard's premise no longer holds"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# AC-2: mixed-era corpus — both eras present, both labeled, single array.
# ═══════════════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════════════
# AC-3: corpus-membership — a lean-schema run's ticket key appears in the sweep's input set.
# ═══════════════════════════════════════════════════════════════════════════════════
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
# The assertion has to be BOUNDED, not a substring probe — ledger-corroborate-selftest.sh's
# (lc38) case found this the hard way: `sed -n '2,40p' "$0"` mutated to `sed -z '2,40p' "$0"`
# reads differently per platform. BSD sed (macOS) rejects `-z` — rc=1, nothing printed, mutant
# dies locally. GNU sed (CI's ubuntu lane) accepts `-z`, which also drops `-n`'s no-autoprint,
# so the arm dumps the ENTIRE script and still exits 0 — and the dump trivially contains
# "Usage:" too, so a contains-only check passes and the mutant survives. Require the usage
# block AND require the output to stop at the excerpt: `set -uo pipefail` (line 44) is the
# first line past the `2,40p` range, so its presence means the whole file leaked.
# ═══════════════════════════════════════════════════════════════════════════════════
HELP_OUT="$(run_open_prs --help)"
HELP_RC=$?
HELP_LINES="$(printf '%s\n' "$HELP_OUT" | wc -l | tr -d ' ')"
if [ "$HELP_RC" -eq 0 ] \
   && grep -qF 'Usage:' <<<"$HELP_OUT" \
   && ! grep -qF 'set -uo pipefail' <<<"$HELP_OUT" \
   && [ "$HELP_LINES" -le 39 ]; then
  pass "(help) '--help' prints the usage doc block and stops there — not the whole script"
else
  fail "(help) rc=$HELP_RC, $HELP_LINES line(s) — got: $HELP_OUT"
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
# key and are in neither statectl quarantine family — so before this they aggregated as
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

echo ""
echo "retro-corpus-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
