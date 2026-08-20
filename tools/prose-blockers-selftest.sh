#!/usr/bin/env bash
# prose-blockers-selftest.sh — behavioral suite for tools/prose-blockers.sh.
#
# Every case drives the real script over a fixture tree via PROSE_BLOCKERS_ROOT. Nothing here
# re-declares the predicate: a copy of it could not fail on a production edit, which is the
# mirror-harness shape this repo forbids.
#
# LOCKSTEP marker lines are built at RUNTIME from a variable, never written literally into a
# heredoc — a whole-line marker in a fixture is a real site to scripts/check-lockstep-pairs.sh
# and would fail as a group of one.

set -uo pipefail

SELF_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
TOOL="$SELF_DIR/prose-blockers.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want '$3', got '$2'"; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- fixture tree
skill() { # skill <plugin> <name>; body on stdin
  local d="$WORK/plugins/$1/skills/$2"
  mkdir -p "$d"
  cat >"$d/SKILL.md"
}

mkdir -p "$WORK/plugins/rev/scripts/fixtures/plugin/skills/copied"
cat >"$WORK/plugins/rev/scripts/fixtures/plugin/skills/copied/SKILL.md" <<'EOF'
The gate refuses without a live ledger.
EOF

skill core alpha <<'EOF'
---
name: alpha
description: refuses everything in the frontmatter, which is metadata and not a rule
---

# alpha

The gate refuses without a live audit ledger.

**Do not pad the report with "no issues found."**

The lint never looks at the tree, and a capability that is off simply never runs.

Never copy plugin content into the consumer repo.

Renders the pinned ref, never the local cache values.

```
bash guard.sh --strict   # refuses an empty body
```

> "alpha requires the Workflow tool. It cannot run as a subagent — hand back."
EOF

skill core beta <<'EOF'
# beta

Independent retrospective for a completed (or aborted) run. An abort is a real cost.

`git.baseBranch` empty → ABORT with the stderr reason.

1. First step, whose continuation line
   mentions that the gate refuses a stale patch id.
5b. A separately numbered step that hands back on an all-dark panel.
EOF

skill other gamma <<'EOF'
# gamma

The gate refuses without a live audit ledger.
EOF

: >"$WORK/guard.sh"   # a real path for the record's enforcer column to resolve to

run() { PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" "$@" 2>&1; }
ids() { PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census "$@" 2>/dev/null | cut -f1; }
row() { PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null | grep -F "$1"; }

echo "== corpus =="
CORPUS=$(run corpus)
is "corpus: three real skills discovered" "$(printf '%s\n' "$CORPUS" | wc -l | tr -d ' ')" "3"
case "$CORPUS" in
  *fixtures*) bad "corpus: fixture copies excluded by path" "fixture SKILL.md is in the corpus" ;;
  *) ok "corpus: fixture copies excluded by path" ;;
esac

echo "== predicate: the stop tier =="
STOP=$(PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census --full 2>/dev/null)
grep -q 'refuses without a live audit ledger' <<<"$STOP" \
  && ok "a named refusal is a construct" || bad "a named refusal is a construct" "absent"
grep -q 'no issues found' <<<"$STOP" \
  && bad "a bare bolded prohibition is NOT a stop" "censused at the stop tier" \
  || ok "a bare bolded prohibition is NOT a stop"
grep -q 'never looks at the tree' <<<"$STOP" \
  && bad "a descriptive never is not a construct" "censused" \
  || ok "a descriptive never is not a construct"
grep -q 'ABORT with the stderr reason' <<<"$STOP" \
  && ok "a commanded ABORT is a stop" || bad "a commanded ABORT is a stop" "absent"
grep -q 'completed (or aborted) run' <<<"$STOP" \
  && bad "an aborted RUN is a state, not a stop" "censused" \
  || ok "an aborted RUN is a state, not a stop"
grep -q 'It cannot run as a subagent' <<<"$STOP" \
  && bad "a blockquote is quoted payload" "censused" || ok "a blockquote is quoted payload"
grep -q 'refuses an empty body' <<<"$STOP" \
  && bad "fenced code is not prose" "censused" || ok "fenced code is not prose"
grep -q 'metadata and not a rule' <<<"$STOP" \
  && bad "frontmatter is not prose" "censused" || ok "frontmatter is not prose"

echo "== predicate: the wider tiers =="
N_STOP=$(ids | wc -l | tr -d ' ')
N_BOLD=$(ids --tier bold | wc -l | tr -d ' ')
N_ALL=$(ids --tier all | wc -l | tr -d ' ')
[ "$N_BOLD" -gt "$N_STOP" ] && ok "bold widens the stop tier" \
  || bad "bold widens the stop tier" "stop=$N_STOP bold=$N_BOLD"
[ "$N_ALL" -gt "$N_BOLD" ] && ok "all widens the bold tier" \
  || bad "all widens the bold tier" "bold=$N_BOLD all=$N_ALL"
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census --tier bold 2>/dev/null | grep -q 'no issues found' \
  && ok "the bolded prohibition appears at --tier bold" \
  || bad "the bolded prohibition appears at --tier bold" "absent"
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census --tier all --full 2>/dev/null | grep -q 'Never copy plugin content' \
  && ok "a clause-initial never appears at --tier all" \
  || bad "a clause-initial never appears at --tier all" "absent"
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census --tier all --full 2>/dev/null | grep -q 'never the local cache values' \
  && bad "an elliptical contrast binds no action" "censused even at --tier all" \
  || ok "an elliptical contrast binds no action"
run census --tier bogus >/dev/null 2>&1; is "an unknown tier is a usage error" "$?" "2"

echo "== the census unit =="
is "a bullet's continuation lines are one construct" \
  "$(row 'core/skills/beta/SKILL.md' | grep -c 'First step')" "1"
row 'beta/SKILL.md' | grep -q 'separately numbered step' \
  && ok "a 5b-style marker starts a new construct" \
  || bad "a 5b-style marker starts a new construct" "merged into the previous block"

DUP_ID=$(PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null \
  | awk -F'\t' '$2 ~ /alpha/ && $2 ~ /gamma/ {print $1}')
[ -n "$DUP_ID" ] && ok "one contract in two skills is one construct with two sites" \
  || bad "one contract in two skills is one construct with two sites" "no row carries both"

echo "== ids are content-derived =="
BEFORE=$(ids)
printf '\n\nA trailing paragraph that names no stop.\n' >>"$WORK/plugins/core/skills/beta/SKILL.md"
is "an unrelated edit re-keys nothing" "$(ids)" "$BEFORE"

echo "== lockstep grouping =="
# Two sites whose text DIFFERS, held together by an anchor: one construct, two sites.
BEGIN_MARK="<!-- LOCKSTEP-BEGIN $(printf 'fixture-anchor') -->"
END_MARK="<!-- LOCKSTEP-END $(printf 'fixture-anchor') -->"
printf '\n%s\nOn rc 2 the scan could not run: hard-stop in alpha.\n%s\n' "$BEGIN_MARK" "$END_MARK" \
  >>"$WORK/plugins/core/skills/alpha/SKILL.md"
printf '\n%s\nOn rc 2 the scan could not run: hard-stop in gamma.\n%s\n' "$BEGIN_MARK" "$END_MARK" \
  >>"$WORK/plugins/other/skills/gamma/SKILL.md"
ANCHORED=$(PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null \
  | awk -F'\t' '$3 ~ /hard-stop/ {print $1 "\t" $2}')
is "differing sites under one anchor are ONE construct" \
  "$(printf '%s\n' "$ANCHORED" | grep -c .)" "1"
printf '%s' "$ANCHORED" | grep -q 'alpha' && printf '%s' "$ANCHORED" | grep -q 'gamma' \
  && ok "the anchored construct carries both sites" \
  || bad "the anchored construct carries both sites" "$ANCHORED"

echo "== check =="
REC="$WORK/docs/rec.tsv"
mkdir -p "$WORK/docs"
: >"$REC"

run check docs/rec.tsv >/dev/null 2>&1; is "an empty record is all-undispositioned" "$?" "3"

# Every live construct gets a row -> clean.
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null \
  | awk -F'\t' '{print $1 "\tgate-backed\tpointer-kept\t" $2 "\tguard.sh::x\tcovered"}' >"$REC"
OUT=$(run check docs/rec.tsv); is "a complete record is clean" "$?" "0"
grep -q 'zero undispositioned' <<<"$OUT" && ok "clean run says so" || bad "clean run says so" "$OUT"

# A prose-deleted row whose construct is still there is UNPRUNED.
LIVE=$(ids | head -1)
sed "s|^$LIVE\tgate-backed\tpointer-kept|$LIVE\tgate-backed\tprose-deleted|" "$REC" >"$REC.x" && mv "$REC.x" "$REC"
OUT=$(run check docs/rec.tsv); is "a prose-deleted row still in the tree reds" "$?" "3"
grep -q 'UNPRUNED' <<<"$OUT" && ok "and names it UNPRUNED" || bad "and names it UNPRUNED" "$OUT"

# A surviving-action row whose construct is gone is STALE.
printf 'pb-deadbeef\tpromoted\tfiled\tsome/file.md:1\t#999\tnot in the tree\n' >>"$REC"
OUT=$(run check docs/rec.tsv); is "a filed row with no construct reds" "$?" "3"
grep -q 'STALE' <<<"$OUT" && ok "and names it STALE" || bad "and names it STALE" "$OUT"

# Malformed rows are exit 4, ahead of any comparison.
printf 'pb-1\tgate-backed\tpointer-kept\n' >"$REC"
run check docs/rec.tsv >/dev/null 2>&1; is "a short row is a malformed record" "$?" "4"
printf 'pb-1\tinvented\tpointer-kept\ta:1\tg::x\tn\n' >"$REC"
run check docs/rec.tsv >/dev/null 2>&1; is "an unknown disposition is malformed" "$?" "4"
printf 'pb-1\tgate-backed\tinvented\ta:1\tg::x\tn\n' >"$REC"
run check docs/rec.tsv >/dev/null 2>&1; is "an unknown action is malformed" "$?" "4"
printf 'pb-1\tgate-backed\tpointer-kept\ta:1\t-\tn\n' >"$REC"
OUT=$(run check docs/rec.tsv 2>&1); is "a gate-backed row naming no enforcer is malformed" "$?" "4"
grep -q 'names no enforcer' <<<"$OUT" && ok "and says which" || bad "and says which" "$OUT"
# An enforcer path the tree does not carry is UNRESOLVED.
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null \
  | awk -F'\t' '{print $1 "\tgate-backed\tpointer-kept\t" $2 "\tno/such/guard.sh::x\tcovered"}' >"$REC"
OUT=$(run check docs/rec.tsv); is "an enforcer the tree lacks reds" "$?" "3"
grep -q 'UNRESOLVED' <<<"$OUT" && ok "and names it UNRESOLVED" || bad "and names it UNRESOLVED" "$OUT"
PROSE_BLOCKERS_ROOT="$WORK" bash "$TOOL" census 2>/dev/null \
  | awk -F'\t' '{print $1 "\tpromoted\tfiled\t" $2 "\t#4242\tdeferred"}' >"$REC"
run check docs/rec.tsv >/dev/null 2>&1; is "an issue ref is not a path to resolve" "$?" "0"

printf '# only a comment\n\npb-2\tdeleted\tprose-deleted\ta:1\t-\twas never a control\n' >"$REC"
run check docs/rec.tsv >/dev/null 2>&1; is "comments and blanks are skipped, deleted needs no enforcer" "$?" "3"

run check docs/nope.tsv >/dev/null 2>&1; is "an absent record is a usage error" "$?" "2"

echo "== the shipped record =="
PROSE_BLOCKERS_ROOT="$SELF_DIR/.." bash "$TOOL" check >/dev/null 2>&1
is "this repo's own tree is fully dispositioned" "$?" "0"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
