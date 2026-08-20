#!/usr/bin/env bash
# gate-ablation.sh — paper ablation of the lean lane's gates over the run corpus (#609).
#
# WHAT THIS ANSWERS. The mutation sweep holds every shell guard to one bar: name the regression
# class only you catch. The lane's own blocking gates have never been held to it. This is the
# transplant of that idea onto the gates — disable one on paper and ask whether any historical
# run's merge decision changes. A gate whose removal changes no decision across the corpus is
# ceremony with a measurement behind it.
#
# THE SUBSTRATE. Every lean run leaves `{issue}-lean-progress.md` — append-only, timestamped, and
# gitignored. Its `attempt` / `absent` rows ARE the gate's firings; its `obligation` rows name the
# sub-milestone identity where the gate writes one. Every reviewed run leaves a COMMITTED verdict
# record whose `inherited_patch_id` / `reviewed_patch_id` pair is the only patch-level content-diff
# observation the lane records anywhere.
#
# WHAT IS NOT RECOMPUTABLE, and why the mechanical column has an `unmeasured` value. The lane's
# branches are squash-merged and deleted, so no branch history survives on the base branch, and the
# progress record carries no commit sha at any row. A true per-firing content diff therefore exists
# only where a verdict-record round boundary covers the interval — milestone 4, and only its last
# firing per run. Everything else is `unmeasured`, which is a stated limit on this report's reach
# and never an implied pass. Nothing here is repaired by inference: no fallback to git metadata,
# file mtime or merge time.
#
# THE TWO COLUMNS are deliberately different in kind (#609 D-1):
#   mechanical    computed here, from the corpus, reproducible byte-for-byte against the manifest.
#   adjudicated   read from a committed table, each row citing a record. Judgment, disclosed as
#                 such, and the column the demotion table ranks by.
#
# REPRODUCIBILITY. The records are host-local, so the corpus itself cannot be committed. What is
# committed is a manifest of record ids plus sha256 content hashes: `emit` verifies every row
# against the live corpus and refuses (rc=3) naming any record that drifted or went missing, so a
# regeneration either reproduces the tables byte-for-byte or says which record moved. Live lanes are
# excluded at manifest time — their records are still being appended to — and named in the header.
#
# Usage:
#   gate-ablation.sh manifest [--state-dir <dir>] [--lanes <tsv>] [--exclude <ids>]
#   gate-ablation.sh emit     [--state-dir <dir>] [--manifest <tsv>] [--classes <tsv>]
#                             [--adjudication <tsv>] [--plans-dir <dir>] [--granularity class|milestone]
#   gate-ablation.sh check    [--report <md>] [same options as emit]
#
# Exit: 0 ok; 1 drift (check) or unclassified/unadjudicated firing; 2 usage/environment;
#       3 corpus drift against the manifest; 4 the emitted output carries a session id or an
#       absolute path.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

die() { echo "[gate-ablation] $*" >&2; exit 2; }

SUB="${1:-}"; shift || true
case "$SUB" in
  manifest|emit|check) : ;;
  *) die "usage: gate-ablation.sh <manifest|emit|check> [options]" ;;
esac

STATE_DIR=""
LANES=""
EXCLUDE=""
MANIFEST="$REPO_ROOT/docs/gate-ablation-manifest.tsv"
CLASSES="$SELF_DIR/gate-ablation-classes.tsv"
ADJUDICATION="$SELF_DIR/gate-ablation-adjudication.tsv"
PLANS_DIR="$REPO_ROOT/docs/plans"
REPORT="$REPO_ROOT/docs/gate-ablation.md"
GRANULARITY=class

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)     STATE_DIR="${2:-}"; shift 2 ;;
    --lanes)         LANES="${2:-}"; shift 2 ;;
    --exclude)       EXCLUDE="${2:-}"; shift 2 ;;
    --manifest)      MANIFEST="${2:-}"; shift 2 ;;
    --classes)       CLASSES="${2:-}"; shift 2 ;;
    --adjudication)  ADJUDICATION="${2:-}"; shift 2 ;;
    --plans-dir)     PLANS_DIR="${2:-}"; shift 2 ;;
    --report)        REPORT="${2:-}"; shift 2 ;;
    --granularity)   GRANULARITY="${2:-}"; shift 2 ;;
    *) die "unknown option '$1'" ;;
  esac
done

case "$GRANULARITY" in
  class|milestone) : ;;
  *) die "--granularity takes 'class' or 'milestone', got '$GRANULARITY'" ;;
esac

# The records live in the MAIN checkout — the lane worktree this may be invoked from has no
# state dir of its own, and the gate writes there for exactly that reason.
if [ -z "$STATE_DIR" ]; then
  common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)" || die "not a git repo and no --state-dir given"
  case "$common" in /*) : ;; *) common="$REPO_ROOT/$common" ;; esac
  STATE_DIR="$(cd "$common/.." && pwd)/.claude/pipeline-state"
fi
[ -d "$STATE_DIR" ] || die "no state dir at $STATE_DIR"
[ -n "$LANES" ] || LANES="$STATE_DIR/lean-lanes.tsv"

# sha256, portable: macOS ships shasum, most Linux images ship sha256sum, and a host with neither
# must say so rather than emit a manifest whose hashes are absent.
if command -v shasum >/dev/null 2>&1; then
  hash_of() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  hash_of() { sha256sum "$1" | awk '{print $1}'; }
else
  die "neither shasum nor sha256sum is on PATH — no content hash can be computed"
fi

record_ids() { # every artifact-schema record id in the state dir, numerically ordered
  find "$STATE_DIR" -maxdepth 1 -type f -name '*-lean-progress.md' 2>/dev/null \
    | sed -n 's|^.*/\([0-9][0-9]*\)-lean-progress\.md$|\1|p' | sort -n
}

live_lanes() { # issue ids of lanes still registered as in flight (column 3 of the lane registry)
  [ -f "$LANES" ] || return 0
  awk -F'\t' 'NF>=3 && $3 ~ /^[0-9]+$/ {print $3}' "$LANES" | sort -n -u
}

# ------------------------------------------------------------------ manifest
if [ "$SUB" = manifest ]; then
  # Two exclusion sources, and both are needed. The lane registry is reaped by pid, so a lane whose
  # session died without tearing down loses its row while its record is still being appended to —
  # which is exactly the drift `emit` then refuses on. `--exclude` is the operator's half of that,
  # and the header records which ids came from where so the corpus boundary is auditable rather
  # than asserted.
  reg="$(live_lanes | tr '\n' ' ')"; reg="${reg% }"
  man="$(echo "$EXCLUDE" | tr ',' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  live="$(echo "$reg $man" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  echo "# gate-ablation corpus manifest — record id + sha256 of every scored progress record."
  echo "# Generated by tools/gate-ablation.sh manifest. Records are host-local and gitignored;"
  echo "# this file is what makes the report's mechanical columns reproducible."
  echo "# excluded, still in flight when this was cut: ${live:-none}"
  echo "#   from the lane registry: ${reg:-none}"
  echo "#   named by --exclude:     ${man:-none}"
  for id in $(record_ids); do
    skip=
    for l in $live; do [ "$id" = "$l" ] && skip=1; done
    [ -n "$skip" ] && continue
    printf '%s\t%s\n' "$id-lean-progress.md" "$(hash_of "$STATE_DIR/$id-lean-progress.md")"
  done
  exit 0
fi

# ------------------------------------------------------------------ corpus verification
[ -f "$MANIFEST" ]     || die "no manifest at $MANIFEST — run 'gate-ablation.sh manifest' first"
[ -f "$CLASSES" ]      || die "no reason-class table at $CLASSES"
[ -f "$ADJUDICATION" ] || die "no adjudication table at $ADJUDICATION"

CORPUS_LIST="$(mktemp)"; DRIFT="$(mktemp)"; OUT="$(mktemp)"
trap 'rm -f "$CORPUS_LIST" "$DRIFT" "$OUT"' EXIT

while IFS="$(printf '\t')" read -r rec want; do
  case "$rec" in ''|'#'*) continue ;; esac
  [ -n "$want" ] || { echo "$rec: manifest row carries no hash" >> "$DRIFT"; continue; }
  f="$STATE_DIR/$rec"
  if [ ! -f "$f" ]; then
    echo "$rec: named by the manifest but missing from the corpus" >> "$DRIFT"
    continue
  fi
  got="$(hash_of "$f")"
  if [ "$got" != "$want" ]; then
    echo "$rec: content moved since the manifest was cut (manifest ${want}, corpus ${got})" >> "$DRIFT"
    continue
  fi
  echo "$f" >> "$CORPUS_LIST"
done < "$MANIFEST"

if [ -s "$DRIFT" ]; then
  echo "[gate-ablation] ✗ corpus drift against $MANIFEST:" >&2
  sed 's/^/[gate-ablation]   /' "$DRIFT" >&2
  echo "[gate-ablation]   the tables cannot be reproduced against a corpus that moved. Re-cut the" >&2
  echo "[gate-ablation]   manifest deliberately, or restore the records." >&2
  exit 3
fi
[ -s "$CORPUS_LIST" ] || die "the manifest selected no records"

# The verdict index: the one committed patch-identity observation per run (see the header).
VERDICT_INDEX="$(mktemp)"
trap 'rm -f "$CORPUS_LIST" "$DRIFT" "$OUT" "$VERDICT_INDEX"' EXIT
for f in "$PLANS_DIR"/*-lean-verdict.md; do
  [ -f "$f" ] || continue
  issue="$(basename "$f" | sed -n 's/^.*-\([0-9][0-9]*\)-lean-verdict\.md$/\1/p')"
  [ -n "$issue" ] || continue
  awk -v issue="$issue" '
    /^rounds:/            { r = $2 }
    /^inherited_patch_id:/{ i = $2 }
    /^reviewed_patch_id:/ { p = $2 }
    END { printf "%s\t%s\t%s\t%s\n", issue, (r == "" ? "?" : r), (i == "" ? "?" : i), (p == "" ? "?" : p) }
  ' "$f" >> "$VERDICT_INDEX"
done

# ------------------------------------------------------------------ emit
# An array, not word-splitting: a fixture state dir under mktemp may sit below a path with a
# space in it, and a split there would hand awk two half-paths and score a silently short corpus.
CORPUS_FILES=()
while IFS= read -r line; do CORPUS_FILES+=("$line"); done < "$CORPUS_LIST"

awk -v classes="$CLASSES" -v adj="$ADJUDICATION" -v vindex="$VERDICT_INDEX" \
    -v granularity="$GRANULARITY" \
    -f "$SELF_DIR/gate-ablation.awk" "${CORPUS_FILES[@]}" > "$OUT"
rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$OUT" >&2
  exit "$rc"
fi

# D-f. The scrub is a gate, not a convention: the committed report must carry no session id and no
# absolute local path, and a quoted reason is exactly how one would get in. The path anchor takes
# any non-path character before the slash, not just a space or a bracket: `key=/Users/...` is the
# same leak as ` /Users/...` and used to walk through. A `/` after a word character is a relative
# path (`docs/plans`, `m5/exit-artifacts`) and is left alone.
scrub() { # scrub <file> <what> — exits 4 on the first leak, printing the offending lines
  if grep -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$1" >&2; then
    echo "[gate-ablation] ✗ $2 carries a session-id-shaped token (lines above)" >&2
    exit 4
  fi
  if grep -nE '(^|[^A-Za-z0-9._/-])(/[A-Za-z_.]|~/)' "$1" >&2; then
    echo "[gate-ablation] ✗ $2 carries an absolute local path (lines above)" >&2
    exit 4
  fi
}
scrub "$OUT" "the generated block"

if [ "$SUB" = emit ]; then
  cat "$OUT"
  exit 0
fi

# ------------------------------------------------------------------ check
[ -f "$REPORT" ] || die "no report at $REPORT"
# The generated block was scrubbed above; AC-5 is about the committed file, so the hand-written
# prose around the markers is scrubbed too — that is where a pasted path or session id lands.
scrub "$REPORT" "the committed report"
EMBEDDED="$(mktemp)"
trap 'rm -f "$CORPUS_LIST" "$DRIFT" "$OUT" "$VERDICT_INDEX" "$EMBEDDED"' EXIT
awk '/^<!-- BEGIN GENERATED: gate-ablation -->$/{f=1;next} /^<!-- END GENERATED: gate-ablation -->$/{f=0} f' \
  "$REPORT" > "$EMBEDDED"
if [ ! -s "$EMBEDDED" ]; then
  echo "[gate-ablation] ✗ $REPORT carries no generated block between the gate-ablation markers" >&2
  exit 1
fi
if diff -u "$EMBEDDED" "$OUT" > /dev/null 2>&1; then
  echo "[gate-ablation] ✓ the report's generated block reproduces from the pinned corpus"
  exit 0
fi
echo "[gate-ablation] ✗ the report's generated block does not reproduce (embedded vs regenerated):" >&2
diff -u "$EMBEDDED" "$OUT" >&2
exit 1
