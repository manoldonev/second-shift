#!/usr/bin/env bash
# claims-lint.sh — verified calibration claims: expiry + declarative probes (#68).
#
# Severity-downgrading calibration claims (the maturity prose security-reviewer
# honors for [Pre-existing] downgrades) are standing severity waivers. This tool
# makes them expire: it scans the consumer repo's .claude/second-shift/**/*.md for
# fenced ```second-shift-claims blocks, FAILs on any claim past its mandatory
# reverify-by date, and evaluates optional declarative probes that accelerate
# staleness discovery. Runs at the per-run pipeline pre-flight (fail-closed),
# inside onboarding preflight.sh, and feeds the doctor's quiet summary line.
#
# Entry grammar (strict, fail-closed — anything else is a parse FAIL):
#   - id: <slug>                          # [a-z0-9][a-z0-9-]*, unique across the repo
#     claim: <text>                       # required, free text (optionally "quoted")
#     reverify-by: YYYY-MM-DD             # required; date-form ONLY (a version/ref
#                                         #   form has no defined "current" to compare)
#     verified-against: <ref>             # optional; recorded so re-blessing is a
#                                         #   reviewable diff — NEVER drives expiry
#     probe: <dsl>                        # optional accelerator (see below)
#
# Probe DSL (declarative — never eval of consumer shell; args are only ever used as
# literal find/grep arguments and [[ == ]] patterns):
#   path-exists:<glob>                    # fails (WARN) when nothing matches
#   path-absent:<glob>                    # fails (WARN) when something matches
#   pattern-absent:<ere> in <target>      # fails (WARN) when grep -E matches; <ere>
#                                         #   may be double-quoted, <target> a dir/glob
#
# Applicability assertion: for path-absent / pattern-absent the deepest non-wildcard
# parent of the glob/target must exist — a moved/renamed tree reports probe-broken
# (WARN), never a silent pass. path-exists asserts existence itself.
#
# Severity by failure class (the expiry × probe matrix is deliberate):
#   expired reverify-by      -> FAIL, regardless of probe outcome (the expiry is the
#                               load-bearing guard; a passing probe never suppresses it)
#   parse error / bad grammar-> FAIL (fail-closed; a typo'd waiver must be loud)
#   failing probe            -> WARN with remediation (the claim may still be honestly
#                               severity-downgrading — see the issue's flagship case)
#   vanished probe target    -> probe-broken WARN
#   passing probe            -> reported only as not-yet-contradicted; a pass only
#                               withholds the probe WARN. It never mints evidence.
#
# Usage:  claims-lint.sh [consumer-repo-root]     (default: cwd)
# Env:    SECOND_SHIFT_CLAIMS_TODAY  — YYYY-MM-DD "today" override (selftest seam)
# Exit:   number of FAILed checks (0 = clean). No .claude/second-shift dir or no
#         claims fences = silent exit 0 (missing extension = generic behavior).
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible (no globstar,
# no mapfile). Date comparison is lexicographic on YYYY-MM-DD (no BSD/GNU date).

set -uo pipefail

ROOT="${1:-.}"
SS="$ROOT/.claude/second-shift"
TODAY="${SECOND_SHIFT_CLAIMS_TODAY:-$(date -u +%Y-%m-%d)}"

[[ -d "$SS" ]] || exit 0

FAILS=0
WARNS=0
TOTAL=0
EXPIRED=0
PROBED_OK=0
PROBELESS_SLUGS=""
SEEN_IDS=" "

say()  { echo "[claims-lint] $1"; }
warn() { say "WARN  $1"; WARNS=$((WARNS+1)); }
bad()  { say "FAIL  $1"; FAILS=$((FAILS+1)); }

REMEDIATION="re-verify the claim against the code and edit the prose; extending reverify-by without a prose change is an audit smell"

# Deepest non-wildcard parent of a glob: segments before the first one carrying
# a wildcard char. A wildcard-free path anchors at its own dirname.
anchor_of() { # $1 = glob (repo-relative) -> echoes anchor dir ("" = repo root)
  local glob="$1" anchor="" seg rest="$1"
  case "$glob" in
    *'*'* | *'?'* | *'['*)
      while [[ "$rest" == */* ]]; do
        seg="${rest%%/*}"; rest="${rest#*/}"
        case "$seg" in
          *'*'* | *'?'* | *'['*) break ;;
          *) anchor="${anchor:+$anchor/}$seg" ;;
        esac
      done
      echo "$anchor"
      ;;
    *) dirname "$glob" ;;
  esac
}

# Does anything under $ROOT match the glob? [[ == ]] fnmatch semantics — `*` (and
# `**`) match across `/`, the same matcher extension-manifest globs already use.
glob_matches() { # $1 = glob (repo-relative) -> rc 0 if >=1 path matches
  local glob="$1" anchor p rel
  case "$glob" in
    *'*'* | *'?'* | *'['*)
      anchor="$(anchor_of "$glob")"
      [[ -e "$ROOT/${anchor:-.}" ]] || return 1
      while IFS= read -r p; do
        rel="${p#"$ROOT"/}"
        # shellcheck disable=SC2053  # unquoted RHS is the point: fnmatch semantics
        [[ "$rel" == $glob ]] && return 0
      done < <(find "$ROOT/${anchor:-.}" \( -type f -o -type d \) 2>/dev/null)
      return 1
      ;;
    *) [[ -e "$ROOT/$glob" ]] ;;
  esac
}

# grep -E over a pattern-absent target (dir or glob). rc 0 = pattern found.
pattern_found() { # $1 = ere, $2 = target (repo-relative dir or glob)
  local ere="$1" target="$2" anchor p rel hit=1
  if [[ -d "$ROOT/$target" ]]; then
    grep -rIlE -- "$ere" "$ROOT/$target" >/dev/null 2>&1
    return $?
  fi
  anchor="$(anchor_of "$target")"
  while IFS= read -r p; do
    rel="${p#"$ROOT"/}"
    # shellcheck disable=SC2053
    if [[ "$rel" == $target ]] && grep -qIE -- "$ere" "$p" 2>/dev/null; then hit=0; fi
  done < <(find "$ROOT/${anchor:-.}" -type f 2>/dev/null)
  return "$hit"
}

# Validate a path/glob argument: reject shell metacharacters and whitespace so a
# probe arg can never smuggle a command (defense in depth — nothing here evals).
valid_glob_arg() { # $1 = candidate
  case "$1" in
    '' | *[';&|$`\\ '\''"']* ) return 1 ;;
    *) return 0 ;;
  esac
}

# ---- per-entry validation + evaluation --------------------------------------
# Entry fields arrive in globals E_ID / E_CLAIM / E_REVERIFY / E_PROBE (E_VERIFIED
# is parsed for grammar but deliberately never echoed — no "verified" wording in
# output is part of the acceptance contract).
flush_entry() { # $1 = file, $2 = line of the `- id:` opener
  local file="$1" line="$2" verb arg ere target anchor probe_state=""
  TOTAL=$((TOTAL+1))

  if [[ ! "$E_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    bad "claims-parse-error $file:$line: invalid or missing id '${E_ID}' (want [a-z0-9][a-z0-9-]*)"
    return
  fi
  case "$SEEN_IDS" in
    *" $E_ID "*) bad "duplicate claim id '$E_ID' ($file:$line) — ids are repo-unique" ; return ;;
  esac
  SEEN_IDS="$SEEN_IDS$E_ID "

  [[ -n "$E_CLAIM" ]] || bad "claims-parse-error $file:$line: claim '$E_ID' has no claim: text"

  # reverify-by: mandatory, date-form only, lexicographic compare vs today.
  if [[ -z "$E_REVERIFY" ]]; then
    bad "claim '$E_ID' ($file:$line) has no reverify-by — the expiry is mandatory for every severity-downgrading claim"
  elif [[ ! "$E_REVERIFY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    bad "claim '$E_ID' ($file:$line): reverify-by '$E_REVERIFY' is not date-form (YYYY-MM-DD) — version/ref forms have no defined current to compare against; record the ref in verified-against instead"
  elif [[ "$E_REVERIFY" < "$TODAY" ]]; then
    EXPIRED=$((EXPIRED+1))
    bad "expired claim '$E_ID' (reverify-by $E_REVERIFY < today $TODAY) in $file — $REMEDIATION"
    # deliberate fall-through: a probe still evaluates below, but its outcome
    # cannot suppress the FAIL above (the expiry × probe matrix).
  fi

  # probe: optional accelerator.
  if [[ -z "$E_PROBE" ]]; then
    PROBELESS_SLUGS="${PROBELESS_SLUGS:+$PROBELESS_SLUGS }$E_ID"
    return
  fi
  case "$E_PROBE" in
    path-exists:*|path-absent:*)
      verb="${E_PROBE%%:*}"; arg="${E_PROBE#*:}"
      if ! valid_glob_arg "$arg"; then
        bad "claims-parse-error $file:$line: probe glob '$arg' carries whitespace/shell metacharacters — the DSL takes literal globs only"
        return
      fi
      if [[ "$verb" == "path-exists" ]]; then
        if glob_matches "$arg"; then probe_state="holds"; else
          warn "probe failing for claim '$E_ID' (path-exists:$arg matched nothing) in $file — $REMEDIATION"
          probe_state="failing"
        fi
      else
        anchor="$(anchor_of "$arg")"
        if [[ ! -e "$ROOT/${anchor:-.}" ]]; then
          warn "probe-broken for claim '$E_ID': probe target vanished ('${anchor:-.}' missing, probe path-absent:$arg) in $file — fix or remove the probe"
          probe_state="broken"
        elif glob_matches "$arg"; then
          warn "probe failing for claim '$E_ID' (path-absent:$arg found a match) in $file — $REMEDIATION"
          probe_state="failing"
        else
          probe_state="holds"
        fi
      fi
      ;;
    pattern-absent:*)
      rest="${E_PROBE#pattern-absent:}"
      case "$rest" in
        \"*\"\ in\ *) ere="${rest#\"}"; ere="${ere%%\" in *}"; target="${rest##*\" in }" ;;
        *\ in\ *)     ere="${rest%% in *}"; target="${rest##* in }" ;;
        *) bad "claims-parse-error $file:$line: pattern-absent needs '<ere> in <target>' — got '$rest'"; return ;;
      esac
      if [[ -z "$ere" ]] || ! valid_glob_arg "$target"; then
        bad "claims-parse-error $file:$line: pattern-absent has an empty regex or an invalid target '$target'"
        return
      fi
      # The target is the search root, not the asserted object — a wildcard-free
      # target must itself exist (else the probe silently passes on a vanished tree).
      case "$target" in
        *'*'* | *'?'* | *'['*) anchor="$(anchor_of "$target")" ;;
        *) anchor="$target" ;;
      esac
      if [[ ! -e "$ROOT/${anchor:-.}" ]]; then
        warn "probe-broken for claim '$E_ID': probe target vanished ('${anchor:-.}' missing, probe pattern-absent in $target) in $file — fix or remove the probe"
        probe_state="broken"
      elif pattern_found "$ere" "$target"; then
        warn "probe failing for claim '$E_ID' (pattern-absent found '$ere' in $target) in $file — $REMEDIATION"
        probe_state="failing"
      else
        probe_state="holds"
      fi
      ;;
    "pattern-absent "*|"path-exists "*|"path-absent "*)
      bad "claims-parse-error $file:$line: probe '$E_PROBE' uses the space form — the pinned grammar is colon-form: path-exists:<glob> | path-absent:<glob> | pattern-absent:<ere> in <target>"
      return
      ;;
    *)
      bad "claims-parse-error $file:$line: unknown probe verb in '$E_PROBE' — the DSL is path-exists:<glob> | path-absent:<glob> | pattern-absent:<ere> in <target>; arbitrary command strings are rejected"
      return
      ;;
  esac
  [[ "$probe_state" == "holds" ]] && PROBED_OK=$((PROBED_OK+1))
}

# ---- scan: extract fences, parse entries ------------------------------------
E_ID=""; E_CLAIM=""; E_REVERIFY=""; E_VERIFIED=""; E_PROBE=""
in_entry=0; entry_file=""; entry_line=0

reset_entry() { E_ID=""; E_CLAIM=""; E_REVERIFY=""; E_VERIFIED=""; E_PROBE=""; in_entry=0; }

while IFS= read -r mdfile; do
  # fence extractor: emit "<lineno>:<line>" for lines inside second-shift-claims fences
  while IFS= read -r numbered; do
    lineno="${numbered%%:*}"
    raw="${numbered#*:}"
    # strip trailing " # comment" (whitespace-preceded) and trailing whitespace
    line="$(printf '%s' "$raw" | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//')"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    stripped="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//')"
    case "$stripped" in
      "- id:"*)
        if [[ "$in_entry" -eq 1 ]]; then flush_entry "$entry_file" "$entry_line"; fi
        reset_entry; in_entry=1; entry_file="$mdfile"; entry_line="$lineno"
        E_ID="$(printf '%s' "${stripped#- id:}" | sed -e 's/^[[:space:]]*//')"
        ;;
      "claim:"*)
        v="$(printf '%s' "${stripped#claim:}" | sed -e 's/^[[:space:]]*//' -e 's/^"//' -e 's/"$//')"
        [[ "$in_entry" -eq 1 ]] && E_CLAIM="$v" || bad "claims-parse-error $mdfile:$lineno: claim: outside an entry (expected '- id:' first)"
        ;;
      "reverify-by:"*)
        v="$(printf '%s' "${stripped#reverify-by:}" | sed -e 's/^[[:space:]]*//')"
        [[ "$in_entry" -eq 1 ]] && E_REVERIFY="$v" || bad "claims-parse-error $mdfile:$lineno: reverify-by: outside an entry"
        ;;
      "verified-against:"*)
        v="$(printf '%s' "${stripped#verified-against:}" | sed -e 's/^[[:space:]]*//')"
        [[ "$in_entry" -eq 1 ]] && E_VERIFIED="$v" || bad "claims-parse-error $mdfile:$lineno: verified-against: outside an entry"
        ;;
      "probe:"*)
        v="$(printf '%s' "${stripped#probe:}" | sed -e 's/^[[:space:]]*//')"
        [[ "$in_entry" -eq 1 ]] && E_PROBE="$v" || bad "claims-parse-error $mdfile:$lineno: probe: outside an entry"
        ;;
      *)
        bad "claims-parse-error $mdfile:$lineno: unrecognized line '$stripped' — the grammar is id/claim/reverify-by/verified-against/probe"
        ;;
    esac
  done < <(awk '/^```second-shift-claims[[:space:]]*$/{inb=1; next} inb && /^```[[:space:]]*$/{inb=0; next} inb{printf "%d:%s\n", NR, $0}' "$mdfile")
  if [[ "$in_entry" -eq 1 ]]; then flush_entry "$entry_file" "$entry_line"; reset_entry; fi
done < <(find "$SS" -type f -name '*.md' 2>/dev/null | sort)

# E_VERIFIED is intentionally unread beyond parsing: the recorded ref is for the
# re-blessing diff in the prose, never for output or expiry. Reference it once so
# set -u tooling and reviewers see the intent.
: "${E_VERIFIED:-}"

[[ "$TOTAL" -eq 0 ]] && exit 0

# The ONE quiet summary line (probe-less claims are never per-claim nagged).
summary="$TOTAL claim(s) — $EXPIRED expired, $WARNS probe warning(s), $PROBED_OK probe(s) not-yet-contradicted"
if [[ -n "$PROBELESS_SLUGS" ]]; then
  summary="$summary; probe-less (expiry-only): $PROBELESS_SLUGS"
fi
say "summary: $summary"
exit "$FAILS"
