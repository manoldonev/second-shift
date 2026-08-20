#!/usr/bin/env bash
# gate-ablation-selftest.sh — behavioral suite for tools/gate-ablation.sh (#609 AC-5).
#
# HERMETIC BY CONSTRUCTION. Every case builds its own state dir, class table, adjudication table
# and manifest under mktemp and drives the tool through its `--state-dir` / `--classes` /
# `--adjudication` / `--manifest` / `--plans-dir` seams. Nothing here reads the live corpus: that
# corpus moves whenever any lane appends a row, so a case that read it would red on a green tree
# for a reason no reader of the diff could see.
#
# Nearly every assertion greps for a markdown table cell, which carries backticks and pipes. The
# single quotes are what keeps the shell out of them, and there is nothing inside for it to expand
# — hence the file-level SC2016 waiver rather than eight identical per-site ones.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/gate-ablation.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILED=0
pass() { echo "  ok   ($1) $2"; }
fail() { echo "  FAIL ($1) $2"; FAILED=$((FAILED + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1" "$4"; else fail "$1" "$4 — want '$3', got '$2'"; fi; }

mkstate() { # mkstate <dir> ; a state dir with the two fixture records below
  mkdir -p "$1"
  cat > "$1/900-lean-progress.md" <<'REC'
# lean run — issue 900

run_id: fixture-900
issue: 900
branch: fixture/900
verdict_record: docs/plans/fixture-900-lean-verdict.md

2026-01-01T00:00:00Z | entry | ledger=x | lines=1 | telemetry=on | session=deadbeef
2026-01-01T00:00:10Z | milestone-1 | started |
2026-01-01T00:00:12Z | milestone-1 | absent | no committed spec at docs/plans/fixture-900-lean.md
2026-01-01T00:00:12Z | milestone-1 | concluded | rc=1
2026-01-01T00:00:20Z | milestone-1 | started |
2026-01-01T00:00:22Z | milestone-1 | absent | no committed spec at docs/plans/fixture-900-lean.md
2026-01-01T00:00:22Z | milestone-1 | concluded | rc=1
2026-01-01T00:01:00Z | milestone-1 | started |
2026-01-01T00:01:00Z | milestone-1 | satisfied
2026-01-01T00:01:00Z | milestone-1 | concluded | rc=0
2026-01-01T00:02:00Z | milestone-3 | started |
2026-01-01T00:02:30Z | milestone-3 | attempt | test failed (rc=1)
2026-01-01T00:02:30Z | milestone-3 | concluded | rc=1
2026-01-01T00:05:00Z | milestone-3 | started |
2026-01-01T00:05:30Z | milestone-3 | satisfied
2026-01-01T00:05:30Z | milestone-3 | concluded | rc=0
2026-01-01T00:06:00Z | milestone-4 | started |
2026-01-01T00:06:01Z | milestone-4 | attempt | verdict record docs/plans/fixture-900-lean-verdict.md reads verdict=needs-work, not verdict=approve
2026-01-01T00:06:01Z | milestone-4 | concluded | rc=1
REC
  cat > "$1/901-lean-progress.md" <<'REC'
# lean run — issue 901

run_id: fixture-901
issue: 901

2026-02-02T00:00:00Z | entry | ledger=x | lines=1 | telemetry=on | session=deadbeef
2026-02-02T00:00:10Z | milestone-5 | started |
2026-02-02T00:00:11Z | milestone-5 | obligation | exit-artifacts | unmet
2026-02-02T00:00:11Z | milestone-5 | attempt | no open PR found for branch fixture/901
2026-02-02T00:00:11Z | milestone-5 | concluded | rc=1
2026-02-02T00:00:20Z | session | 11111111-2222-3333-4444-555555555555
2026-02-02T00:00:30Z | milestone-5 | started |
2026-02-02T00:00:31Z | milestone-5 | attempt | no open PR found for branch fixture/901
2026-02-02T00:00:31Z | milestone-5 | concluded | rc=1
2026-02-02T00:01:00Z | milestone-2 | started |
2026-02-02T00:01:00Z | milestone-2 | advisory | [frozen-files] clean
2026-02-02T00:01:00Z | milestone-2 | concluded | rc=0
REC
}

mkclasses() {
  {
    echo "# fixture classes"
    printf 'm1/spec-absent\t1\t-\t^no committed spec at \tspec not written\n'
    printf 'm1/never\t1\t-\t^this never matches anything\tnever\n'
    printf 'm3/test\t3\t-\t^test failed \\(rc=\ttest lane red\n'
    printf 'm4/verdict-not-approve\t4\t-\treads verdict=.*, not verdict=approve\tneeds-work\n'
    printf 'm5/exit-artifacts:no-open-pr\t5\texit-artifacts\t^no open PR found for branch \tno open PR\n'
  } > "$1"
}

mkadj() {
  {
    echo "# fixture adjudication"
    printf 'm1/spec-absent\tunchanged\tno\t900-lean-progress.md\tthe checklist writes the spec\n'
    printf 'm1/never\tundetermined\tno\tnever fired\t—\n'
    printf 'm3/test\tchanged\tno\t900-lean-progress.md\ta source edit\n'
    printf 'm4/verdict-not-approve\tchanged\tno\t900-lean-progress.md\ta review round\n'
    printf 'm5/exit-artifacts:no-open-pr\tunchanged\tno\tthe class\tnothing committed speaks to it\n'
    printf '901:m5/exit-artifacts:no-open-pr\tunchanged\tyes\tfixture verdict record\tthe PR existed\n'
  } > "$1"
}

mkverdicts() { # a plans dir whose one verdict record moves the patch id across two rounds
  mkdir -p "$1"
  cat > "$1/fixture-900-lean-verdict.md" <<'V'
# lean review verdict — #900

verdict=approve
rounds: 2
reviewed_patch_id: aaaaaaaaaaaa1111
inherited_patch_id: bbbbbbbbbbbb2222
V
}

run() { bash "$TOOL" "$@" 2>&1; }

echo "== gate-ablation selftest =="

S="$T/state"; C="$T/classes.tsv"; A="$T/adj.tsv"; P="$T/plans"; M="$T/manifest.tsv"
mkstate "$S"; mkclasses "$C"; mkadj "$A"; mkverdicts "$P"

# (a) manifest mode names each record with a hash and honours --exclude.
OUT="$(run manifest --state-dir "$S" --lanes /nonexistent --exclude 901)"
check a "$(printf '%s\n' "$OUT" | grep -c '^900-lean-progress.md')" 1 "manifest lists the in-corpus record"
check a2 "$(printf '%s\n' "$OUT" | grep -c '^901-lean-progress.md')" 0 "--exclude drops the named lane"
check a3 "$(printf '%s\n' "$OUT" | grep -c 'named by --exclude:     901')" 1 "the header records where the exclusion came from"
check a4 "$(printf '%s\n' "$OUT" | awk -F'\t' '/^900/ {print length($2)}')" 64 "the row carries a sha256"

# (b) emit is deterministic over an unchanged corpus — AC-5's byte-for-byte claim.
run manifest --state-dir "$S" --lanes /nonexistent > "$M"
E1="$T/e1"; E2="$T/e2"
bash "$TOOL" emit --state-dir "$S" --manifest "$M" --classes "$C" --adjudication "$A" --plans-dir "$P" > "$E1" 2>&1
rc1=$?
bash "$TOOL" emit --state-dir "$S" --manifest "$M" --classes "$C" --adjudication "$A" --plans-dir "$P" > "$E2" 2>&1
check b "$rc1" 0 "emit succeeds over a manifest-matching corpus"
if cmp -s "$E1" "$E2"; then pass b2 "two emits are byte-identical"; else fail b2 "two emits differ"; fi

# (c) the two labeled columns are both present and independent.
check c "$(grep -c '| `m3/test` | 3 | — | 1 |' "$E1")" 1 "the fired point carries its count"
check c2 "$(grep -c 'content-moved' "$E1")" 1 "the verdict record's round boundary yields one real content diff"
check c3 "$(awk '/^### Decision points/,/^### Firings/' "$E1" | grep -c '| `m1/never` | 1 | — | — |')" 1 "a point that never fired is still enumerated with a zero count"
check c4 "$(awk '/^### Never fired/,/^### Earn/' "$E1" | grep -c '| `m1/never` | 1 | — |')" 1 "and is listed under Never fired"

# (s) the demotion ranking is the table AC-2 says the report ranks by, so its ORDER is a contract.
#     Both fixture points carry 2 zero-decision-change firings, so the primary key ties and the
#     eval-cost tiebreak decides: m1/spec-absent cost 4s, the m5 point 2s, dearest first. A flipped
#     comparator swaps these two rows and changes nothing else, which is why membership alone is
#     not enough to catch it.
RANKED="$(awk '/^### Demotion/,/^### Never fired/' "$E1" | sed -n 's/^| [0-9][0-9]* | `\([^`]*\)` .*/\1/p' | tr '\n' ',')"
check s "$RANKED" "m1/spec-absent,m5/exit-artifacts:no-open-pr," "a tie on the primary key is broken by evaluation cost, dearest first"

# (d) corpus drift is named, never silently absorbed.
echo "2026-01-01T00:09:00Z | milestone-3 | started |" >> "$S/900-lean-progress.md"
OUT="$(run emit --state-dir "$S" --manifest "$M" --classes "$C" --adjudication "$A" --plans-dir "$P")"; rc=$?
check d "$rc" 3 "a record whose content moved exits 3"
check d2 "$(printf '%s\n' "$OUT" | grep -c '900-lean-progress.md: content moved')" 1 "the drifted record is named"

# (e) a record the manifest names but the corpus has lost is drift too, not a short corpus.
mkstate "$T/state2"; S2="$T/state2"
rm -f "$S2/901-lean-progress.md"
OUT="$(run emit --state-dir "$S2" --manifest "$M" --classes "$C" --adjudication "$A" --plans-dir "$P")"; rc=$?
check e "$rc" 3 "a missing record exits 3"
check e2 "$(printf '%s\n' "$OUT" | grep -c '901-lean-progress.md: named by the manifest but missing')" 1 "the missing record is named"

# (f) a live record the manifest does not name is IGNORED — the manifest closes the corpus, so a
#     new run appearing mid-analysis cannot change the tables underneath a reader.
mkstate "$T/state3"; S3="$T/state3"
cp "$S3/900-lean-progress.md" "$S3/999-lean-progress.md"
M2="$T/manifest2.tsv"
run manifest --state-dir "$S3" --lanes /nonexistent --exclude 999 > "$M2"
OUT="$(run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P")"; rc=$?
check f "$rc" 0 "an out-of-manifest record does not red the run"
check f2 "$(printf '%s\n' "$OUT" | grep -c 'scored records (artifact schema) | 2 ')" 1 "and is not scored"

# (g) an unclassified reason is a hard failure naming the record — never an `other` bucket (D-c).
mkstate "$T/state4"; S4="$T/state4"
echo "2026-01-01T00:20:00Z | milestone-3 | attempt | the moon was in the wrong phase" >> "$S4/900-lean-progress.md"
M3="$T/manifest3.tsv"; run manifest --state-dir "$S4" --lanes /nonexistent > "$M3"
OUT="$(run emit --state-dir "$S4" --manifest "$M3" --classes "$C" --adjudication "$A" --plans-dir "$P")"; rc=$?
check g "$rc" 1 "an unmatched reason exits 1"
check g2 "$(printf '%s\n' "$OUT" | grep -c 'matches no row in the reason-class table')" 1 "and says so"
check g3 "$(printf '%s\n' "$OUT" | grep -c '900-lean-progress.md 2026-01-01T00:20:00Z')" 1 "naming the record and the row"

# (h) a gate point with no adjudication row is a hard failure — the table cannot go stale.
A2="$T/adj2.tsv"; grep -v '^m3/test' "$A" > "$A2"
OUT="$(run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A2" --plans-dir "$P")"; rc=$?
check h "$rc" 1 "an unadjudicated gate point exits 1"
check h2 "$(printf '%s\n' "$OUT" | grep -c "gate point 'm3/test' has no row in the adjudication table")" 1 "naming the point"

# (i) a per-run override outranks the per-point row.
A3="$T/adj3.tsv"; cp "$A" "$A3"
printf '900:m3/test\tunchanged\tno\tan override\toverridden\n' >> "$A3"
OUT="$(run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A3" --plans-dir "$P")"
check i "$(printf '%s\n' "$OUT" | grep -c '| `m3/test` | 3 | — | 1 | 1 / — | 1 unmeasured | 1 unchanged |')" 1 "the <issue>:<point> key wins"

# (j) the repeat-firing diagnostic counts a bare re-fire and is broken by a session change.
#     900 re-fires m1/spec-absent with nothing between; 901 re-fires its m5 point across a session
#     row, which is exactly the boundary that must NOT count.
check j "$(grep -c '| `m1/spec-absent` | 1 | 2 |' "$E1")" 1 "a bare re-fire counts as a repeat"
check j2 "$(grep -c '| `m5/exit-artifacts:no-open-pr` | 1 |' "$E1")" 0 "a re-fire across a session change does not"

# (k) the false-red tally counts only rows flagged with a citation, and reports a floor.
check k "$(grep -c '^\*\*Lower bound: 2 firings\.\*\*$' "$E1")" 1 "the floor counts both firings the flagged row covers"
check k2 "$(grep -c 'm5/exit-artifacts:no-open-pr` | 2 | `2026-02-02T00:00:11Z` | `901:m5/exit-artifacts:no-open-pr`' "$E1")" 1 "and names the per-run row that flagged them"
A6="$T/adj6.tsv"; grep -v '^901:' "$A" > "$A6"
OUT="$(run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A6" --plans-dir "$P")"
check k3 "$(printf '%s\n' "$OUT" | grep -c '^\*\*Lower bound: 0 firings\.\*\*$')" 1 "with the flag gone the floor is zero, not an estimate"

# (l) the scrub is a gate: a session id or an absolute path in the output exits 4.
A4="$T/adj4.tsv"; sed 's|a source edit|leaked 11111111-2222-3333-4444-555555555555|' "$A" > "$A4"
run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A4" --plans-dir "$P" >/dev/null 2>&1
check l "$?" 4 "a session-id-shaped token exits 4"
A5="$T/adj5.tsv"; sed 's|a source edit|read from /Users/someone/state|' "$A" > "$A5"
run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A5" --plans-dir "$P" >/dev/null 2>&1
check l2 "$?" 4 "an absolute local path exits 4"
A7="$T/adj7.tsv"; sed 's|a source edit|state_dir=/Users/someone/state|' "$A" > "$A7"
run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A7" --plans-dir "$P" >/dev/null 2>&1
check l3 "$?" 4 "an absolute path glued to a key, with no space in front of it, exits 4 too"
A8="$T/adj8.tsv"; sed 's|a source edit|see docs/plans and m5/exit-artifacts|' "$A" > "$A8"
run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A8" --plans-dir "$P" >/dev/null 2>&1
check l4 "$?" 0 "a relative path is not an absolute one — the widened anchor leaves a docs-slash-plans shape alone"

# (m) check mode diffs the report's embedded block against a regeneration.
R="$T/report.md"
{ echo "# fixture report"; echo ""; echo "<!-- BEGIN GENERATED: gate-ablation -->"; cat "$E1"; echo "<!-- END GENERATED: gate-ablation -->"; } > "$R"
run check --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --report "$R" >/dev/null 2>&1
check m "$?" 0 "an in-sync report checks clean"
sed 's/| 54 |/| 99 |/; s/scored records (artifact schema) | 2 /scored records (artifact schema) | 7 /' "$R" > "$R.bad"
run check --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --report "$R.bad" >/dev/null 2>&1
check m2 "$?" 1 "a hand-edited table reds"
{ echo "# fixture report"; echo "no markers here"; } > "$R.none"
OUT="$(run check --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --report "$R.none")"; rc=$?
check m3 "$rc" 1 "a report with no generated block reds"
check m4 "$(printf '%s\n' "$OUT" | grep -c 'carries no generated block')" 1 "rather than checking an empty block clean"
{ echo "# fixture report"; echo ""; echo "generated on 11111111-2222-3333-4444-555555555555"; echo ""
  echo "<!-- BEGIN GENERATED: gate-ablation -->"; cat "$E1"; echo "<!-- END GENERATED: gate-ablation -->"; } > "$R.leaky"
run check --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --report "$R.leaky" >/dev/null 2>&1
check m5 "$?" 4 "a session id in the report's hand-written half reds, not just one in the generated block"

# (n) --granularity milestone collapses the key; the flag is OR-1's reversible half.
OUT="$(run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --granularity milestone)"
check n "$(printf '%s\n' "$OUT" | grep -c '`milestone-3`')" 0 "the collapsed key needs its own adjudication rows"
run emit --state-dir "$S3" --manifest "$M2" --classes "$C" --adjudication "$A" --plans-dir "$P" --granularity nonsense >/dev/null 2>&1
check n2 "$?" 2 "an unknown granularity is a usage error"

# (o) usage and environment failures are exit 2, not a silently empty report.
run nonsense >/dev/null 2>&1;                                          check o "$?" 2 "an unknown subcommand"
run emit --state-dir /nonexistent >/dev/null 2>&1;                      check o2 "$?" 2 "a missing state dir"
run emit --state-dir "$S" --manifest /nonexistent >/dev/null 2>&1;      check o3 "$?" 2 "a missing manifest"
run emit --state-dir "$S" --manifest "$M" --classes /nonexistent >/dev/null 2>&1; check o4 "$?" 2 "a missing class table"

# (p) the default paths resolve against the repo root, not against an empty string. Nothing else
#     here exercises them — every case above passes explicit paths — so a broken root resolution
#     would leave the tool unusable in the one way it is actually invoked and every case green.
mkdir -p "$T/empty"
run emit --state-dir "$T/empty" >/dev/null 2>&1
check p "$?" 3 "with no --manifest the committed default resolves and its records are missing (3), not unresolvable (2)"

# (q) --lanes is honoured over the state dir's own registry. The two must be able to disagree, or
#     the seam is untested and the default silently wins wherever the fixture has no registry.
mkstate "$T/state5"; S5="$T/state5"
printf '1	some date	900	2026-01-01T00:00:00Z
' > "$S5/lean-lanes.tsv"
printf '2	some date	901	2026-01-01T00:00:00Z
' > "$T/other-lanes.tsv"
OUT="$(run manifest --state-dir "$S5" --lanes "$T/other-lanes.tsv")"
check q "$(printf '%s\n' "$OUT" | grep -c '^900-lean-progress.md')" 1 "the lane the passed registry does NOT name stays in"
check q2 "$(printf '%s\n' "$OUT" | grep -c '^901-lean-progress.md')" 0 "the lane it names is excluded"
check q3 "$(printf '%s\n' "$OUT" | grep -c 'from the lane registry: 901')" 1 "and the header attributes it to the registry"

# (r) with nothing excluded, both header sources read `none` — the manifest must never imply an
#     exclusion it did not make.
OUT="$(run manifest --state-dir "$S5" --lanes /nonexistent)"
check r "$(printf '%s\n' "$OUT" | grep -c 'still in flight when this was cut: none')" 1 "no exclusions renders as none"
check r2 "$(printf '%s\n' "$OUT" | grep -c 'from the lane registry: none')" 1 "an absent registry renders as none"
check r3 "$(printf '%s\n' "$OUT" | grep -c 'named by --exclude:     none')" 1 "an unused --exclude renders as none"

echo
if [ "$FAILED" -eq 0 ]; then echo "gate-ablation-selftest: ALL CASES PASSED"; exit 0; fi
echo "gate-ablation-selftest: $FAILED CASE(S) FAILED"; exit 1
