#!/usr/bin/env bash
# operator-override.sh — the attended-session affordance and the per-decision operator override
# record (#613, slice one of #605).
#
# THE MECHANISM IN ONE LINE: affordance plus record. An ambient attended signal unlocks only the
# affordance to PAUSE AND ASK instead of reject; any actual yield additionally requires a
# per-decision recorded operator answer. The signal alone never unlocks anything — a session that
# could assert its own attendance could turn off its own gates, which is the receipt-fabrication
# problem one level up.
#
# TRUST POSTURE, stated rather than implied. Nothing in-session is tamper-proof; the repo's trust
# boundary says so and this file does not pretend otherwise.
#   - The TOKEN is tamper-evident only. Forging it buys a pause, never a yield.
#   - The RECORD is the yield's evidence, at the intent-gap ratification trust level:
#     session-writable, committed, PR-visible, merge-boundary-validated, repudiable at review.
#   - The residual — this file edited to skip its own bookkeeping — is the standing local-gate
#     posture, caught at review as a diff. docs/pipeline-manifesto.md states it.
#
# WHY ONE BINARY AND NOT A SOURCED LIBRARY. Two consumers in two files need the same parser, and
# two copies of a parser is the dual-declaration smell. What keeps this "private to the gate"
# rather than a public seam is the CLOSED gate enum below: wiring a third gate is a code change
# here, not a config knob.
#
# Usage:
#   operator-override.sh attend
#   operator-override.sh state
#   operator-override.sh record --gate <g> --scope <s> --issue <n> [--region <OR-n>]
#                               --decision <text> --answer <text> [--repo-root <dir>]
#   operator-override.sh check  --gate <g> --issue <n> [--region <OR-n>] [--repo-root <dir>]
#   operator-override.sh lint   [--record <path>] [--register <path>]
#
# Exit codes:
#   attend  0 minted; 2 refused (no identity, or marked headless)
#   state   0 always — the ANSWER is on stdout ("attended" / "headless <reason>"); 2 only for a
#           self-asserted LEAN_ATTEND_MODE value, which is an environment error and not a state
#   record  0 written; 2 refused (headless, bad enum, or an unwritable root)
#   check   0 a matching unexpired override exists (YIELD); 1 none (REFUSE);
#           2 something exists but could not be read or is malformed (UNKNOWN — never a negative)
#   lint    the number of violations (doctor convention); 2 for usage/environment
#
# The `check` vocabulary is checked-call.sh's, deliberately: 2 means the caller MAY NOT treat
# this as a negative. Both consumers turn it into a fail-closed refusal with its own message.
#
# Env seams (every one has a shipped default pointing at the real thing):
#   LEAN_ATTEND_MODE        `headless` marks this process tree headless. NO positive value is
#                           honored — see resolve_attendance().
#   RUN_ID                  the run identity the token and record bind to.
#   CLAUDE_CODE_SESSION_ID  the session identity, and what makes staleness structural.
#   SECOND_SHIFT_CONFIG     config path override.
#   SECOND_SHIFT_REPO_ROOT  main-checkout override (the token lives there, shared across worktrees).
#   GH                      the code-host CLI, read-only here (register expiry only).
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible.

set -uo pipefail

GH_CLI="${GH:-gh}"

usage() { sed -n '2,53p' "$0"; }
envfail() { echo "[operator-override] $1" >&2; exit 2; }
say() { echo "[operator-override] $1"; }

# ---------------------------------------------------------------- roots and config
# MAIN_ROOT is the shared checkout — `git rev-parse --git-common-dir` then up one, the idiom
# lean-gate.sh and bot-commit.sh already use. The TOKEN lives there on purpose: a lane worktree
# is cut and destroyed inside one run, and a token that died with it would make every re-entry
# read headless for a reason that has nothing to do with who is watching.
if [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then
  MAIN_ROOT="$SECOND_SHIFT_REPO_ROOT"
elif _common="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" || MAIN_ROOT="$(pwd)"
else
  MAIN_ROOT="$(pwd)"
fi

CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"
cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}
PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
STATE_DIR="$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
REPO_SLUG="$(cfg '(.topology.repos | to_entries[] | select(.value.path==".") | .key)' 'acme')"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---------------------------------------------------------------- attendance
# FIRST RULE THAT FIRES WINS, and the order is the contract.
#
# Rule 1 is the only env-supplied answer, and it is one-directional. `headless` is honored
# because a process that knows it is unattended is telling the truth against its own interest;
# any OTHER value — `attended` above all — is an environment error, because an honored positive
# value IS the self-asserted attendance the epic forbids. A typo lands in the same arm rather
# than silently reading as attended.
#
# Rules 2/3 are why staleness needs no clock. A scheduler-spawned `claude -p` payload gets a
# FRESH session id, so an operator's token can never read attended inside one; and the run id is
# what D-2's per-run scoping is stated against. Both are required — degrading to the weaker
# binding when one is missing would hand back exactly the case the binding exists to catch.
ATTEND_REASON=""
resolve_attendance() { # 0 = attended; 1 = headless, with ATTEND_REASON set
  local tok sid rid tsid trid
  case "${LEAN_ATTEND_MODE:-}" in
    "")        : ;;
    headless)  ATTEND_REASON="marked-headless"; return 1 ;;
    *) envfail "LEAN_ATTEND_MODE='$LEAN_ATTEND_MODE' is not a value this reads. Only 'headless' is honored — attendance is never self-asserted, it is minted by an operator running '$(basename "$0") attend'." ;;
  esac
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || { ATTEND_REASON="no-session-identity"; return 1; }
  rid="${RUN_ID:-}"
  [ -n "$rid" ] || { ATTEND_REASON="no-run-identity"; return 1; }
  tok="$(token_path)"
  [ -f "$tok" ] || { ATTEND_REASON="no-token"; return 1; }
  tsid="$(record_key session_id "$tok")"
  trid="$(record_key run_id "$tok")"
  if [ -z "$tsid" ] || [ -z "$trid" ]; then ATTEND_REASON="corrupt-token"; return 1; fi
  [ "$tsid" = "$sid" ] || { ATTEND_REASON="session-mismatch"; return 1; }
  [ "$trid" = "$rid" ] || { ATTEND_REASON="run-mismatch"; return 1; }
  return 0
}

# Named by SESSION id, not by run: two operator sessions on one machine must not overwrite each
# other's token, and the session id is the component that cannot be inherited.
token_path() { printf '%s\n' "$MAIN_ROOT/$STATE_DIR/attend-${CLAUDE_CODE_SESSION_ID:-none}.token"; }

# The same first-match header read the intent-gap record uses (lean-gate.sh's record_key). Kept
# to that character class so a value that is not an identity-shaped token reads as ABSENT rather
# than as a partial match.
record_key() { # record_key <key> <file>
  [ -f "$2" ] || return 0
  grep -oE "^$1:[[:space:]]*[A-Za-z0-9._:/-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

cmd_attend() {
  local tok
  case "${LEAN_ATTEND_MODE:-}" in
    headless) envfail "this process tree is marked headless (LEAN_ATTEND_MODE=headless) — the scheduler sets it on every payload it spawns. Attendance cannot be minted here; run the lane from your own session." ;;
  esac
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] \
    || envfail "no CLAUDE_CODE_SESSION_ID — there is no session identity to bind to, so a token minted here could not be told apart from any other. Run this from the session that is attending."
  [ -n "${RUN_ID:-}" ] \
    || envfail "no RUN_ID — the token binds to run identity (the per-run scoping the record is stated against). Export the run's id first, the same export build-lean's step 2 already requires: export RUN_ID=<token>"
  tok="$(token_path)"
  mkdir -p "$(dirname "$tok")" 2>/dev/null \
    || envfail "cannot create $(dirname "$tok") to hold the attendance token."
  {
    echo "session_id: $CLAUDE_CODE_SESSION_ID"
    echo "run_id: $RUN_ID"
    echo "minted_at: $(now_iso)"
  } > "$tok" || envfail "cannot write the attendance token at $tok."
  say "✓ attended — token at $tok (run_id=$RUN_ID)."
  say "  This unlocks the PAUSE affordance only. A yield still needs a recorded operator answer:"
  say "  $(basename "$0") record --gate <gate> --scope <scope> --issue <n> --decision '…' --answer '…'"
}

cmd_state() {
  if resolve_attendance; then echo "attended"; else echo "headless ($ATTEND_REASON)"; fi
}

# ---------------------------------------------------------------- the record
record_path() { printf '%s\n' "$1/$PLANS_DIR/$REPO_SLUG-$2-lean-override.md"; }

# THE RECORD READER, held in LOCKSTEP with plugins/dev-pipeline/skills/build-lean/lean-evidence.sh.
#
# WHY A COPY AND NOT A SOURCE. A consumer's CI fetches lean-evidence.sh ALONE, at a pinned ref,
# through second-shift-ci-check.sh — one file, no sibling, no plugin tree. A `source` there would
# resolve to nothing, and the boundary would report a pass on evidence it never read. This is the
# checked-call.sh situation exactly, and it takes the same remedy: a byte-identical copy the
# lockstep guard compares on every run, rather than prose asking two files to agree.
#
# The comments are INSIDE the block on purpose. They are what tell the next reader why an
# unknown enum value is an error rather than a miss, and a copy that kept the code and dropped
# that paragraph would grow back the fail-open one edit at a time.
# LOCKSTEP-BEGIN override-record-reader verbatim
# The CLOSED enums. Widening either is the phase-2 work #613 defers, and an unknown value is an
# ERROR rather than a silent miss: a gate name nobody implements must not read as "no override
# exists", which is the fail-open this whole mechanism is built against.
OVERRIDE_GATES='intake-unqueued spec-open-region'
OVERRIDE_SCOPES='intake-attestation open-region-resolution'

# The gate that is region-scoped. A region is REQUIRED for it and forbidden for the other: an
# open-region override that named no region would clear every region on the ticket at once.
OVERRIDE_REGION_SCOPED_GATE='spec-open-region'

# The register is at a FIXED path, deliberately unlike every other artifact here. The merge
# boundary reads it and the merge boundary has no config — the same reasoning check-lean-chain.sh
# already applies to its own constants.
OVERRIDE_REGISTER_REL='.claude/lean-overrides.tsv'

override_in_enum() { # override_in_enum <value> <space-separated set>
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# Every block, one TAB-separated line, keys read FIRST-MATCH WITHIN THE BLOCK. Per-block and not
# per-file because one run can yield at two different gates, and a single file-wide first-match
# header could only ever name one of them.
#
# `answers` counts non-empty quoted lines under `### Operator answer`: a record whose quote is
# missing is a decision nobody stated, which is the thing this record exists to carry.
#
# THE SEPARATOR IS \037, NOT A TAB, and that is a correctness fix rather than a taste one. Tab is
# an IFS-WHITESPACE character in bash, so `IFS=<tab> read` collapses a run of them into ONE
# delimiter: an empty middle field silently shifts every field after it, and the reader then
# reports a violation about the wrong key. Measured on the first draft — a record with an empty
# `run_id:` was reported as carrying `expiry: 1`.
override_parse_blocks() { # override_parse_blocks <file>
  [ -f "$1" ] || return 0
  awk '
    function flush() {
      if (!inblk) return
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", g, sc, is, rg, ri, si, ex, (dc == "" ? 0 : 1), ans
    }
    function reset() { g=""; sc=""; is=""; rg=""; ri=""; si=""; ex=""; dc=""; ans=0; inans=0 }
    /^##[[:space:]]+Override[[:space:]]/ { flush(); reset(); inblk=1; next }
    !inblk { next }
    /^###[[:space:]]+Operator answer[[:space:]]*$/ { inans=1; next }
    /^###[[:space:]]/ { inans=0 }
    inans && /^>[[:space:]]*[^[:space:]]/ { ans++ }
    inans { next }
    {
      if (match($0, /^[a-z_]+:[[:space:]]*/)) {
        k = substr($0, 1, index($0, ":") - 1)
        v = substr($0, RLENGTH + 1)
        sub(/[[:space:]]+$/, "", v)
        if (k == "gate"       && g  == "") g  = v
        if (k == "scope"      && sc == "") sc = v
        if (k == "issue"      && is == "") is = v
        if (k == "region"     && rg == "") rg = v
        if (k == "run_id"     && ri == "") ri = v
        if (k == "session_id" && si == "") si = v
        if (k == "expiry"     && ex == "") ex = v
        if (k == "decision"   && dc == "") dc = v
      }
    }
    END { flush() }
  ' "$1"
}

# One rule set, two callers: `check` uses it to decide MALFORMED (rc 2), `lint` to count
# violations. A second copy would be two answers to "is this record well-formed", and the merge
# boundary's answer is the one that has to match the gate's.
override_block_violation() { # override_block_violation <tsv-line> — prints a reason, or nothing when clean
  local g sc is rg ri si ex dc ans
  IFS="$(printf '\037')" read -r g sc is rg ri si ex dc ans <<EOF
$1
EOF
  override_in_enum "$g" "$OVERRIDE_GATES"   || { echo "gate '${g:-<none>}' is not one of: $OVERRIDE_GATES"; return; }
  override_in_enum "$sc" "$OVERRIDE_SCOPES" || { echo "scope '${sc:-<none>}' is not one of: $OVERRIDE_SCOPES"; return; }
  case "$is" in ''|*[!0-9]*) echo "issue '${is:-<none>}' is not a ticket number"; return ;; esac
  if [ "$g" = "$OVERRIDE_REGION_SCOPED_GATE" ]; then
    case "$rg" in
      OR-[0-9]*) : ;;
      *) echo "gate '$g' is region-scoped but region reads '${rg:-<none>}' — an override naming no region would clear every open region on the ticket at once"; return ;;
    esac
  elif [ "$rg" != "none" ]; then
    echo "gate '$g' is not region-scoped, so region must read 'none', not '${rg:-<none>}'"; return
  fi
  [ -n "$ri" ] || { echo "run_id is empty — the override binds to run identity"; return; }
  [ -n "$si" ] || { echo "session_id is empty — nothing names the session that recorded it"; return; }
  [ "$ex" = "run" ] || { echo "expiry '${ex:-<none>}' — a per-issue record carries only 'run'; a persistent override belongs in $OVERRIDE_REGISTER_REL with an explicit expiry"; return; }
  [ "$dc" = "1" ] || { echo "decision is empty"; return; }
  [ "${ans:-0}" -ge 1 ] || { echo "no quoted operator answer under '### Operator answer' — a decision nobody stated is not an override"; return; }
}
# LOCKSTEP-END override-record-reader

cmd_record() {
  local gate="" scope="" issue="" region="none" decision="" answer="" root="" path n line why
  while [ $# -gt 0 ]; do
    case "$1" in
      --gate)      gate="${2:-}"; shift 2 ;;
      --scope)     scope="${2:-}"; shift 2 ;;
      --issue)     issue="${2:-}"; shift 2 ;;
      --region)    region="${2:-}"; shift 2 ;;
      --decision)  decision="${2:-}"; shift 2 ;;
      --answer)    answer="${2:-}"; shift 2 ;;
      --repo-root) root="${2:-}"; shift 2 ;;
      *) envfail "record: unknown argument '$1'" ;;
    esac
  done
  # THE ATTENDANCE CHECK IS ON THE WRITE, NOT ON THE READ. A record outlives the session that
  # wrote it — a re-entry, a re-run, CI — so re-demanding a live token at read time would make
  # every correct record stop working the moment its session ended. What the token buys is the
  # right to write one at all.
  resolve_attendance \
    || envfail "refusing to record an override from a headless session ($ATTEND_REASON). This record's whole content is an operator's stated answer; a headless run has no operator to quote. Mint attendance first: $(basename "$0") attend"
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  [ -n "$root" ] || envfail "record: not inside a git checkout and no --repo-root given."
  [ -n "$decision" ] || envfail "record: --decision is required — one line saying what the operator decided."
  [ -n "$answer" ] || envfail "record: --answer is required — the operator's stated answer, quoted verbatim. Paraphrasing it is the fabrication this record exists to prevent."

  path="$(record_path "$root" "$issue")"
  n=$(( $(override_parse_blocks "$path" | wc -l | tr -d ' ') + 1 ))
  mkdir -p "$(dirname "$path")" 2>/dev/null || envfail "cannot create $(dirname "$path")."
  if [ ! -f "$path" ]; then
    printf '# Lean override record — issue %s\n\nRecorded operator overrides for this ticket. Each block is one decision: the gate that would\notherwise have refused, the authority scope it covers, and the operator answer it quotes.\n' "$issue" > "$path" \
      || envfail "cannot write $path."
  fi
  {
    printf '\n## Override %s\n' "$n"
    printf 'gate: %s\n' "$gate"
    printf 'scope: %s\n' "$scope"
    printf 'issue: %s\n' "$issue"
    printf 'region: %s\n' "$region"
    printf 'run_id: %s\n' "$RUN_ID"
    printf 'session_id: %s\n' "$CLAUDE_CODE_SESSION_ID"
    printf 'expiry: run\n'
    printf 'recorded_at: %s\n' "$(now_iso)"
    printf 'decision: %s\n' "$decision"
    printf '\n### Operator answer\n\n'
    printf '%s\n' "$answer" | sed 's/^/> /'
  } >> "$path" || envfail "cannot append to $path."

  # Validated AFTER the write, against the file as parsed — the same reader the gate and the
  # boundary use. Validating the arguments instead would assert that the intent was legal, not
  # that the artifact is, and those came apart once already in this repo's history.
  line="$(override_parse_blocks "$path" | tail -n 1)"
  why="$(override_block_violation "$line")"
  [ -z "$why" ] || envfail "the block just written to $path is malformed: $why. Fix or remove it — a malformed record refuses at the merge boundary too."
  say "✓ recorded override $n at $path"
  case "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
    "$(cfg '.tracker.branchPrefix' 'claude/')"*) : ;;
    *) say "  NOTE: $root is not a lane worktree, so this record is not on the branch the PR will carry. Move it into the lane worktree once it is cut, or the merge boundary has nothing to validate." ;;
  esac
}

# ---------------------------------------------------------------- the persistent register
# THE RARE CLASS ONLY. A single repo-wide append-per-run register is conflict-by-construction —
# every run would touch one file — which is why per-run overrides live in per-issue files and
# only PERSISTENT rows come here. Rare rows conflict rarely.
#
# Hand-edited and reviewed as a diff, the fail-open-sites.tsv posture: there is no `add` verb,
# because a persistent override that nobody argued about in a PR is the thing this is for.
#
# Columns: gate <TAB> scope <TAB> region <TAB> expiry <TAB> justification
# `expiry` grammar is the SINGLE form `until-issue:<N>` — a condition, not a clock. A date would
# import the BSD/GNU `date` arithmetic the token design already declined, and would expire
# silently at midnight instead of when the work it waits on actually lands.
register_rows() { # register_rows <path>
  [ -f "$1" ] || return 0
  awk -F'\t' '/^[[:space:]]*#/ { next } NF == 0 { next } /^[[:space:]]*$/ { next } { print }' "$1"
}

# 0 = live, 1 = expired, 2 = the answer is unknown (an unreadable tracker is not an expired row,
# and it is not a live one either).
register_row_expired() { # register_row_expired <expiry-token>
  local n state
  case "$1" in
    until-issue:[0-9]*) n="${1#until-issue:}" ;;
    *) return 2 ;;
  esac
  state="$("$GH_CLI" issue view "$n" --json state --jq .state 2>/dev/null)" || return 2
  case "$state" in
    OPEN)   return 0 ;;
    CLOSED) return 1 ;;
    *)      return 2 ;;
  esac
}

# `cut`, not an IFS read: this file is genuinely TAB-separated on disk and cannot change its
# separator, and the IFS-whitespace collapse described above would shift an empty middle column
# here too — an empty `region` would make this report on the wrong field. `cut` counts delimiters.
register_field() { # register_field <n> <row>
  printf '%s' "$2" | cut -f"$1"
}

register_row_violation() { # register_row_violation <tsv-row>
  local g sc rg ex ju
  g="$(register_field 1 "$1")"; sc="$(register_field 2 "$1")"; rg="$(register_field 3 "$1")"
  ex="$(register_field 4 "$1")"; ju="$(register_field 5 "$1")"
  override_in_enum "$g" "$OVERRIDE_GATES"   || { echo "gate '${g:-<none>}' is not one of: $OVERRIDE_GATES"; return; }
  override_in_enum "$sc" "$OVERRIDE_SCOPES" || { echo "scope '${sc:-<none>}' is not one of: $OVERRIDE_SCOPES"; return; }
  if [ "$g" = "$OVERRIDE_REGION_SCOPED_GATE" ]; then
    case "$rg" in OR-[0-9]*) : ;; *) echo "gate '$g' is region-scoped but region reads '${rg:-<none>}'"; return ;; esac
  elif [ "$rg" != "none" ]; then
    echo "gate '$g' is not region-scoped, so region must read 'none', not '${rg:-<none>}'"; return
  fi
  case "$ex" in
    until-issue:[0-9]*) : ;;
    *) echo "expiry '${ex:-<none>}' — the grammar is the single form until-issue:<N>, a condition rather than a clock"; return ;;
  esac
  [ -n "$ju" ] || { echo "justification is empty — a persistent override nobody justified reds by design"; return; }
}

# ---------------------------------------------------------------- check: the yield predicate
cmd_check() {
  local gate="" issue="" region="" root="" path line why g sc is rg hit=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --gate)      gate="${2:-}"; shift 2 ;;
      --issue)     issue="${2:-}"; shift 2 ;;
      --region)    region="${2:-}"; shift 2 ;;
      --repo-root) root="${2:-}"; shift 2 ;;
      *) envfail "check: unknown argument '$1'" ;;
    esac
  done
  override_in_enum "$gate" "$OVERRIDE_GATES" || envfail "check: gate '${gate:-<none>}' is not one of: $OVERRIDE_GATES"
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  [ -n "$root" ] || envfail "check: not inside a git checkout and no --repo-root given."

  # ---- the per-issue record. EVERY malformed block refuses, including one that does not match
  # this query: a file the boundary will reject must not read as a clean "no override here", or
  # the run proceeds on evidence that cannot survive the merge.
  path="$(record_path "$root" "$issue")"
  if [ -f "$path" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      why="$(override_block_violation "$line")"
      if [ -n "$why" ]; then
        echo "[operator-override] malformed override block in $path: $why" >&2
        return 2
      fi
      IFS="$(printf '\037')" read -r g sc is rg _ <<EOF
$line
EOF
      [ "$g" = "$gate" ] || continue
      [ "$is" = "$issue" ] || continue
      if [ "$gate" = "$OVERRIDE_REGION_SCOPED_GATE" ]; then [ "$rg" = "$region" ] || continue; fi
      hit=1
    done <<EOF
$(override_parse_blocks "$path")
EOF
  fi
  [ "$hit" -eq 0 ] || return 0

  # ---- the persistent register. Consulted second and rarely populated, so the common path pays
  # nothing for it. An expired or unevaluable row is rc 2 and reds the run HERE, at the first
  # consumer that consults it — which is what "reds the next run" means in practice.
  local reg rrc
  reg="$root/$OVERRIDE_REGISTER_REL"
  if [ -f "$reg" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      why="$(register_row_violation "$line")"
      if [ -n "$why" ]; then
        echo "[operator-override] malformed row in $OVERRIDE_REGISTER_REL: $why" >&2
        return 2
      fi
      g="$(register_field 1 "$line")"; rg="$(register_field 3 "$line")"; ex="$(register_field 4 "$line")"
      [ "$g" = "$gate" ] || continue
      if [ "$gate" = "$OVERRIDE_REGION_SCOPED_GATE" ]; then [ "$rg" = "$region" ] || continue; fi
      register_row_expired "$ex"; rrc=$?
      case "$rrc" in
        0) return 0 ;;
        1) echo "[operator-override] $OVERRIDE_REGISTER_REL carries a persistent '$gate' override whose expiry '$ex' has fired — remove the row or replace it with a live one." >&2; return 2 ;;
        *) echo "[operator-override] $OVERRIDE_REGISTER_REL carries a persistent '$gate' override whose expiry '$ex' could not be evaluated (the tracker read failed). That is not the same answer as 'no override' and is not treated as one." >&2; return 2 ;;
      esac
    done <<EOF
$(register_rows "$reg")
EOF
  fi
  return 1
}

# ---------------------------------------------------------------- lint: the boundary's reader
cmd_lint() {
  local rec="" reg="" line why v=0 rrc
  while [ $# -gt 0 ]; do
    case "$1" in
      --record)   rec="${2:-}"; shift 2 ;;
      --register) reg="${2:-}"; shift 2 ;;
      *) envfail "lint: unknown argument '$1'" ;;
    esac
  done
  [ -n "$rec" ] || [ -n "$reg" ] || envfail "lint: give --record and/or --register."
  if [ -n "$rec" ]; then
    [ -f "$rec" ] || envfail "lint: --record '$rec' does not exist."
    if [ -z "$(override_parse_blocks "$rec")" ]; then
      echo "[operator-override]   ✗ $rec exists but declares no '## Override n' block — an override record with no override in it is not evidence of anything." >&2
      v=$((v + 1))
    fi
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      why="$(override_block_violation "$line")"
      [ -z "$why" ] || { echo "[operator-override]   ✗ $rec: $why" >&2; v=$((v + 1)); }
    done <<EOF
$(override_parse_blocks "$rec")
EOF
  fi
  if [ -n "$reg" ] && [ -f "$reg" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      why="$(register_row_violation "$line")"
      if [ -n "$why" ]; then
        echo "[operator-override]   ✗ $reg: $why" >&2; v=$((v + 1)); continue
      fi
      register_row_expired "$(register_field 4 "$line")"; rrc=$?
      case "$rrc" in
        1) echo "[operator-override]   ✗ $reg: a persistent override's expiry has fired — remove the row: $line" >&2; v=$((v + 1)) ;;
        2) echo "[operator-override]   ✗ $reg: a persistent override's expiry could not be evaluated: $line" >&2; v=$((v + 1)) ;;
      esac
    done <<EOF
$(register_rows "$reg")
EOF
  fi
  return "$v"
}

# ---------------------------------------------------------------- dispatch
SUB="${1:-}"
[ $# -gt 0 ] && shift
case "$SUB" in
  attend) cmd_attend "$@" ;;
  state)  cmd_state "$@" ;;
  record) cmd_record "$@" ;;
  check)  cmd_check "$@" ;;
  lint)   cmd_lint "$@" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
