#!/usr/bin/env bash
# preflight.sh — read-only onboarding finish line for the dev-pipeline (#30).
#
# Proves a freshly onboarded consumer repo is pipeline-ready WITHOUT the anxiety
# of a mutating first run: echoes the resolved targets (tracker/repos/branches/
# worktree-path strings), runs the config gates (config-lint, check-extensions),
# runs the config-aware environment doctor (pipeline-doctor.sh — the #17 layer,
# invoked, not duplicated), performs ONE tracker READ (no claim), executes every
# non-null command lane once in the current checkout, and writes a preflight
# report. /second-shift:onboard invokes this as its final step.
#
# Write boundary (the feature's contract, asserted by preflight-selftest.sh):
#   FORBIDDEN  — tracker mutations (claim/labels/comments), git mutations
#                (branch/worktree/commit), remote writes. Nothing here uses
#                $GH_BOT; the only gh calls are reads.
#   PERMITTED  — the local report file, transient lane artifacts (dependency
#                installs, test output), doctor's own `mkdir -p .claude/worktrees`
#                probe and mktemp scratch.
#   Source-mutating lanes never run: a `format` lane configured as a string is
#   the repo's own formatter run verbatim (rewrites the tree) — SKIP-with-note;
#   `lint` when `lintAutofixes: true` mutates files — SKIP-with-note. A generic
#   check-mode transformation is not derivable for arbitrary commands, so
#   skip-with-note is the only universally safe posture.
#
# Usage:
#   preflight.sh [<ticket-key>]
#   (outside plugin execution, resolve the root first:
#    claude plugin list --json | jq -r '.[] | select(.id == "dev-pipeline@second-shift") | .installPath')
#
# Without a ticket key (the onboard finish-line case) the github tracker read is
# the queue head (`gh issue list` — a READ); with a key it is that issue. Under
# tracker.type: jira the tracker read is SKIPped with a note — the jira fetch is
# session-side MCP (mcp__atlassian__getJiraIssue), unreachable from a shell tool.
#
# Env seams (mirroring the sibling tools):
#   SECOND_SHIFT_REPO_ROOT   — consumer repo root override (else git-common-dir, else cwd)
#   SECOND_SHIFT_CONFIG      — config path override
#   PREFLIGHT_DOCTOR_CMD     — environment-doctor command override (selftest mock seam;
#                              default: the sibling pipeline-doctor.sh)
#
# Report: <repo-root>/.claude/pipeline-state/preflight-report.md (overwritten per run).
# Exit code: number of FAILed checks (0 = ready) — the pipeline-doctor convention.
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEY="${1:-}"

# --- Resolve consumer repo root + config (pipeline-doctor.sh idiom) --------------
if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$SECOND_SHIFT_REPO_ROOT"
elif _common="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  REPO_ROOT="$(dirname "$(cd "$_common" && pwd)")"
else
  REPO_ROOT="$(pwd)"
fi
CFG="${SECOND_SHIFT_CONFIG:-$REPO_ROOT/.claude/second-shift.config.json}"

REPORT_DIR="$REPO_ROOT/.claude/pipeline-state"
REPORT="$REPORT_DIR/preflight-report.md"
mkdir -p "$REPORT_DIR"

FAILS=0
# Every line goes to stdout AND the report (built in a scratch buffer, moved into
# place at the end so a crashed run never leaves a half-written report behind).
BUF="$(mktemp -t preflight-report.XXXXXX)"
trap 'rm -f "$BUF"' EXIT

say()  { echo "$1"; echo "$1" >> "$BUF"; }
ok()   { say "[preflight] OK    $1"; }
warn() { say "[preflight] WARN  $1"; }
skipn(){ say "[preflight] SKIP  $1"; }
bad()  { say "[preflight] FAIL  $1"; FAILS=$((FAILS+1)); }
hdr()  { { echo ""; echo "## $1"; echo ""; } >> "$BUF"; echo "[preflight] --- $1 ---"; }

{
  echo "# dev-pipeline preflight report"
  echo ""
  echo "- date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- repo root: $REPO_ROOT"
  echo "- config: $CFG"
  echo "- ticket: ${KEY:-"(none — issue-independent run)"}"
  echo "- contract: READ-ONLY — no tracker mutation, no branch/worktree/commit, no push, no comment."
} >> "$BUF"

# --- Section 1: config gates ------------------------------------------------------
hdr "Config gates"
if [[ ! -f "$CFG" ]]; then
  bad "no consumer config at $CFG — run /second-shift:onboard first"
else
  if out=$(bash "$SCRIPT_DIR/config-lint.sh" "$CFG" 2>&1); then
    ok "config-lint: $(tail -1 <<< "$out")"
  else
    bad "config-lint rejected $CFG:"
    while IFS= read -r l; do say "[preflight]        $l"; done < <(tail -10 <<< "$out")
  fi
  if out=$(bash "$SCRIPT_DIR/check-extensions.sh" "$REPO_ROOT" 2>&1); then
    ok "check-extensions: extension files + EP-6/EP-7 references resolve"
  else
    bad "check-extensions rejected the repo:"
    while IFS= read -r l; do say "[preflight]        $l"; done < <(tail -10 <<< "$out")
  fi
  # review-context SECTION lint (review-toolkit) — the in-file counterpart to
  # check-extensions. review-toolkit is a SEPARATE plugin, so resolve its install path:
  # env override (hermetic selftests) -> installed plugin path -> skip-note. A missing
  # review-toolkit is NOT a preflight failure (the section lint is a review-toolkit
  # capability; dev-pipeline can preflight without it). check-review-context-sections.sh
  # --preflight fails closed on alias drift + present-but-empty catalog sections; the
  # coverage --report line is informational and can never contribute to the exit code.
  RT_ROOT="${SECOND_SHIFT_REVIEW_TOOLKIT_ROOT:-}"
  if [[ -z "$RT_ROOT" ]] && command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # Same jq shape as doctor.sh's resolver (kept identical so the two cannot drift — the
    # cross-plugin boundary means they can't share a sourced helper the way the review-toolkit
    # scripts share _effective-registry.sh: each must FIND review-toolkit before sourcing it).
    RT_ROOT=$(claude plugin list --json 2>/dev/null | jq -r '[.[] | select(.id=="review-toolkit@second-shift")] | (sort_by(.lastUpdated // "") | last | .installPath) // empty' 2>/dev/null || true)
  fi
  SECTION_LINT="$RT_ROOT/scripts/check-review-context-sections.sh"
  if [[ -n "$RT_ROOT" && -x "$SECTION_LINT" ]]; then
    if out=$(bash "$SECTION_LINT" --preflight "$REPO_ROOT" 2>&1); then
      ok "check-review-context-sections: no alias drift or empty catalog sections"
      # Surface the lint's OFF-CATALOG WARNs even on success — a reviewer-degrading rename
      # to a NOVEL heading is (by the reconciled #67 contract) WARN-not-red, so this line
      # plus the coverage line below IS its entire disclosure. Swallowing it here would
      # reduce the reconciliation to a coverage-count footnote.
      while IFS= read -r l; do [[ -n "$l" ]] && say "[preflight]        $l"; done < <(grep 'OFF-CATALOG' <<< "$out" | head -10)
    else
      bad "check-review-context-sections rejected the repo (alias drift, empty catalog section, or lint error):"
      hits=$(grep -E 'ALIAS:|EMPTY-SECTION:' <<< "$out" | head -10)
      [[ -z "$hits" ]] && hits=$(tail -5 <<< "$out")   # exit-2 infra error: show the real message
      while IFS= read -r l; do say "[preflight]        $l"; done <<< "$hits"
    fi
    cov=$(bash "$SECTION_LINT" --report "$REPO_ROOT" 2>/dev/null | grep -m1 'context-coverage:' || true)
    [[ -n "$cov" ]] && say "[preflight]        $cov"
  else
    warn "check-review-context-sections: review-toolkit not resolved — section lint skipped (set SECOND_SHIFT_REVIEW_TOOLKIT_ROOT or install review-toolkit@second-shift)"
  fi
fi
# claims-lint runs REGARDLESS of config presence — calibration claims live in
# extension files, which can exist without a config. Silent exit 0 = no claims.
if out=$(bash "$SCRIPT_DIR/claims-lint.sh" "$REPO_ROOT" 2>&1); then
  if [[ -n "$out" ]]; then
    ok "claims-lint: $(tail -1 <<< "$out" | sed 's/^\[claims-lint\] //')"
    while IFS= read -r l; do case "$l" in *"WARN"*) say "[preflight]        $l" ;; esac; done <<< "$out"
  else
    ok "claims-lint: no calibration claims declared"
  fi
else
  bad "claims-lint rejected the repo (expired or malformed severity-downgrading claims):"
  while IFS= read -r l; do say "[preflight]        $l"; done < <(tail -10 <<< "$out")
fi

# --- Section 2: Target Confirmation echo (read-only) ------------------------------
# The resolved config the first real run will operate on — tracker, repos, branch
# and worktree-path STRINGS (computed, never created: no statectl init, no git
# worktree add). Defaults mirror the run skill's resolution sites.
hdr "Target Confirmation (resolved targets)"
TRACKER_TYPE=github; TRACKER_WRITES=true; BRANCH_PREFIX="claude/acme-"; KEY_PATTERN=""
TOPO=standalone; QUEUE_LABEL="ready-for-dev"; CLAIMED_LABEL="in-progress"
PLAN_DIR="docs/plans"; PLAN_PAT="{plansDir}/acme-{issueKey}{slice}.md"; STATE_DIR=".claude/pipeline-state"
if [[ -f "$CFG" ]] && command -v jq >/dev/null 2>&1; then
  TRACKER_TYPE=$(jq -r '.tracker.type // "github"' "$CFG" 2>/dev/null || echo github)
  TRACKER_WRITES=$(jq -r 'if .tracker.writes != null then .tracker.writes else (.tracker.type // "github") == "github" end' "$CFG" 2>/dev/null || echo true)
  BRANCH_PREFIX=$(jq -r '.tracker.branchPrefix // "claude/acme-"' "$CFG" 2>/dev/null || echo "claude/acme-")
  KEY_PATTERN=$(jq -r '.tracker.keyPattern // empty' "$CFG" 2>/dev/null)
  TOPO=$(jq -r '.topology.type // "standalone"' "$CFG" 2>/dev/null || echo standalone)
  QUEUE_LABEL=$(jq -r '.tracker.labels.queue // "ready-for-dev"' "$CFG" 2>/dev/null || echo "ready-for-dev")
  CLAIMED_LABEL=$(jq -r '.tracker.labels.claimed // "in-progress"' "$CFG" 2>/dev/null || echo "in-progress")
  PLAN_DIR=$(jq -r '.paths.plansDir // "docs/plans"' "$CFG" 2>/dev/null || echo "docs/plans")
  PLAN_PAT=$(jq -r '.stageParams.planFilePattern // "{plansDir}/acme-{issueKey}{slice}.md"' "$CFG" 2>/dev/null || echo "{plansDir}/acme-{issueKey}{slice}.md")
  STATE_DIR=$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$CFG" 2>/dev/null || echo ".claude/pipeline-state")
fi
EXAMPLE_KEY="${KEY:-EXAMPLE-KEY}"
BRANCH="${BRANCH_PREFIX}${EXAMPLE_KEY}"
PLAN_REL="$(printf '%s' "$PLAN_PAT" | sed -e "s|{plansDir}|$PLAN_DIR|" -e "s|{issueKey}|$EXAMPLE_KEY|" -e "s|{slice}||")"
ok "tracker: type=$TRACKER_TYPE writes=$TRACKER_WRITES queue='$QUEUE_LABEL' claimed='$CLAIMED_LABEL'${KEY_PATTERN:+ keyPattern=$KEY_PATTERN}"
ok "branch namespace: prefix='$BRANCH_PREFIX' -> work branch '$BRANCH'"
ok "plan file: '$PLAN_REL' | pipeline state dir: '$STATE_DIR'"
ok "topology: type=$TOPO"
if [[ -f "$CFG" ]] && command -v jq >/dev/null 2>&1; then
  while IFS=$'\t' read -r rid rpath rbase rwt; do
    [[ -z "$rid" ]] && continue
    [[ "$rwt" == "null" || -z "$rwt" ]] && rwt=".claude/worktrees"
    ok "repo '$rid': path='$rpath' baseBranch='$rbase' -> worktree path (string-only) '$rwt/${BRANCH##*/}'"
  done < <(jq -r '(.topology.repos // {}) | to_entries[] | [.key, .value.path, (.value.baseBranch // "main"), (.value.worktreesDir // "null")] | @tsv' "$CFG" 2>/dev/null)
fi

# --- Section 3: environment doctor (#17 config-aware layer — invoked, not copied) --
hdr "Environment (pipeline-doctor.sh)"
if [[ -n "${PREFLIGHT_DOCTOR_CMD:-}" ]]; then
  doctor_out=$(cd "$REPO_ROOT" && eval "$PREFLIGHT_DOCTOR_CMD" 2>&1); doctor_rc=$?
else
  doctor_out=$(cd "$REPO_ROOT" && bash "$SCRIPT_DIR/pipeline-doctor.sh" 2>&1); doctor_rc=$?
fi
{ echo '```'; echo "$doctor_out"; echo '```'; } >> "$BUF"
if [[ $doctor_rc -eq 0 ]]; then
  ok "pipeline-doctor: 0 failed check(s)"
else
  bad "pipeline-doctor: $doctor_rc failed check(s) — see the Environment section of the report"
  FAILS=$((FAILS + doctor_rc - 1))   # fold doctor's per-check count into the exit code (bad() already added 1)
fi

# --- Section 4: one tracker READ (no claim) ---------------------------------------
hdr "Tracker read (no claim)"
if [[ "$TRACKER_TYPE" == "github" ]]; then
  if [[ -n "$KEY" ]]; then
    if out=$(cd "$REPO_ROOT" && gh api "repos/{owner}/{repo}/issues/$KEY" --jq '"#\(.number) [\(.state)] \(.title)"' 2>&1); then
      ok "issue read: $out"
    else
      bad "could not read issue '$KEY' via gh api (check gh auth / the key): $(tail -1 <<< "$out")"
    fi
  else
    if out=$(cd "$REPO_ROOT" && gh issue list --label "$QUEUE_LABEL" --json number,title --limit 1 --jq '.[0] | "#\(.number) \(.title)"' 2>&1); then
      if [[ -n "$out" && "$out" != "null" ]]; then
        ok "queue head ('$QUEUE_LABEL'): $out"
      else
        ok "queue read succeeded — queue is empty (normal for a fresh consumer)"
      fi
    else
      bad "queue read failed (gh issue list --label '$QUEUE_LABEL'): $(tail -1 <<< "$out")"
    fi
  fi
else
  skipn "tracker read: tracker.type=$TRACKER_TYPE — the jira fetch is session-side MCP (mcp__atlassian__getJiraIssue), not reachable from a shell tool; verify it from the Claude session"
fi

# --- Section 5: command lanes, once each, in the current checkout ------------------
# Order mirrors verifyctl: setup lanes[] first, then the trio (+build), then extraLanes.
hdr "Command lanes (one pass, current checkout)"
run_lane() { # $1 = lane label, $2 = command string
  local label="$1" cmd="$2" out rc
  # Lanes run in the environment a normal shell would see — preflight's own env
  # seams must not leak in (a consumer lane may itself be second-shift tooling;
  # a leaked SECOND_SHIFT_REPO_ROOT re-roots it and fails it spuriously).
  out=$(cd "$REPO_ROOT" && env -u SECOND_SHIFT_REPO_ROOT -u SECOND_SHIFT_CONFIG -u PREFLIGHT_DOCTOR_CMD bash -c "$cmd" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "lane '$label': green ($cmd)"
  else
    bad "lane '$label' failed (rc=$rc): $cmd"
    { echo '```'; tail -15 <<< "$out"; echo '```'; } >> "$BUF"
  fi
}
if [[ -f "$CFG" ]] && command -v jq >/dev/null 2>&1; then
  HOST_ID=$(jq -r '(.topology.repos // {}) | to_entries[] | select(.value.path==".") | .key' "$CFG" 2>/dev/null | head -n1)
  if [[ -z "$HOST_ID" ]]; then
    warn "no host repo (path \".\") in topology.repos — lane pass skipped"
  else
    LINT_AUTOFIX=$(jq -r --arg h "$HOST_ID" '.commands[$h].lintAutofixes // false' "$CFG" 2>/dev/null || echo false)
    FORMAT_KIND=$(jq -r --arg h "$HOST_ID" '.commands[$h] | if has("format") then (if .format == null then "null" else "string" end) else "absent" end' "$CFG" 2>/dev/null || echo absent)
    # setup lanes (write node_modules/build artifacts — inside the permitted boundary)
    i=0
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      i=$((i+1)); run_lane "setup[$i]" "$cmd"
    # `select(type == "object")` (#100): a non-object lanes[] entry otherwise aborts
    # the whole jq stream, and the 2>/dev/null hides it — so ONE malformed entry
    # silently drops EVERY lane, including well-formed ones, while preflight still
    # reports it executed the lanes. config-lint is the gate that rejects such a
    # config, but bad() only counts the failure and preflight continues into this
    # section on the same run, so the read itself must be safe.
    done < <(jq -r --arg h "$HOST_ID" '(.commands[$h].lanes // []) | .[] | select(type == "object") | (.commands // [])[]' "$CFG" 2>/dev/null)
    # the trio + build
    for lane in lint typecheck test build; do
      cmd=$(jq -r --arg h "$HOST_ID" --arg l "$lane" '.commands[$h][$l] // empty' "$CFG" 2>/dev/null)
      if [[ -z "$cmd" || "$cmd" == "null" ]]; then
        skipn "lane '$lane': null/absent — lane not configured"
        continue
      fi
      if [[ "$lane" == "lint" && "$LINT_AUTOFIX" == "true" ]]; then
        skipn "lane 'lint': lintAutofixes=true — the configured lint mutates files; read-only preflight never runs it (first real run exercises it)"
        continue
      fi
      run_lane "$lane" "$cmd"
    done
    # format lane — never run at preflight (see the write boundary header)
    case "$FORMAT_KIND" in
      string) skipn "lane 'format': configured string is the repo's own formatter run verbatim — mutates the tree; read-only preflight never runs it" ;;
      null)   skipn "lane 'format': null — lane disabled by config" ;;
      absent) skipn "lane 'format': absent — the default scoped prettier check needs a diff; nothing to format-check at preflight" ;;
    esac
    # extraLanes (when-gate not evaluable — there is no diff at preflight)
    i=0
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      i=$((i+1)); run_lane "extraLanes[$i] (when-gate not evaluated — no diff at preflight)" "$cmd"
    done < <(jq -r --arg h "$HOST_ID" '(.commands[$h].extraLanes // []) | .[] | (.commands // [])[]' "$CFG" 2>/dev/null)
  fi
else
  warn "no config / no jq — lane pass skipped"
fi

# --- Verdict -----------------------------------------------------------------------
hdr "Verdict"
say "[preflight] deliberately NOT done: no issue claim, no label swap, no branch, no worktree, no commit, no push, no tracker comment."
if ! (cd "$REPO_ROOT" && git check-ignore -q "$STATE_DIR/preflight-report.md" 2>/dev/null); then
  warn "'$STATE_DIR/' is not gitignored in this repo — add it to .gitignore (local-only run artifacts, never version-controlled)"
fi
say "[preflight] summary: $FAILS failed check(s)$( [[ $FAILS -eq 0 ]] && echo ' — pipeline-ready' )"
say "[preflight] report: $REPORT"

mv "$BUF" "$REPORT"
trap - EXIT
exit "$FAILS"
