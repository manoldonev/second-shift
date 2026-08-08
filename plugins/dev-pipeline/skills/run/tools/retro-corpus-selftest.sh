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
    echo "branch_prefix: lean/second-shift-"
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
if [ "$RC3" -eq 2 ] && printf '%s' "$OUT3" | grep -q "carry no 'files'"; then
  pass "(AC-5c) open-prs: a PR list without the files field is an environment error, not an empty result"
else
  fail "(AC-5c) rc=$RC3 — got $OUT3"
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
   && printf '%s' "$HELP_OUT" | grep -qF 'Usage:' \
   && ! printf '%s' "$HELP_OUT" | grep -qF 'set -uo pipefail' \
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

echo ""
echo "retro-corpus-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
