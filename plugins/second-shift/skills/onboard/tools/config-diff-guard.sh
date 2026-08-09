#!/usr/bin/env bash
# config-diff-guard.sh — refuse to let a RE-onboard silently destroy an existing config value.
#
# /second-shift:onboard Step 0 promises diff mode against the existing config, and Step 3's key
# contract used to override it unconditionally: `testFile` and `unitTestScope` were emitted
# ALWAYS as explicit null. Those are exactly the keys a human sets when adopting the mutation
# gate, so a re-onboard reverted the adoption — and `unitTestScope: null` is a legal "no mutation
# surface", so Stage 5 printed `gate OFF`, `config-lint` passed, and the gate stayed off for
# months. Step 3 now carries those two keys forward; this guard is the mechanical backstop, so a
# prose intent cannot be overridden by prose a second time.
#
# There is no discriminator for "human-authored" — detection emits nothing for the two keys the
# evidence names, and for keys it DOES produce, an existing value is indistinguishable from a
# prior run's detected one (the emitted config is pure JSON with all provenance stripped). So the
# provenance framing is dropped: EVERY existing non-null value is protected. A value the draft
# reproduces identically yields no delta, so the extra generality costs nothing.
#
# Onboard-only by construction. /second-shift:doctor never rewrites a config, so it has no draft
# to compare and nothing to destroy; it keeps calling config-grill.sh alone.
#
# Usage: config-diff-guard.sh <existing-config.json> <draft-config.json> [--ack <path>]...
# Output: ONE JSON document on stdout — { deltas: [...], acknowledged: [...], unmatchedAcks: [...] }
# Exit:  0 always when it ran (deltas are DATA, not a crash) · 3 usage/IO error
#
# Takes no repo root and reads no tree: pure document comparison. Read-only, no network,
# bash-3.2 safe.
#
# A dotted `path` is ambiguous for a config key containing a literal `.`. Stated, not escaped:
# repo ids come from a package.json short name or a directory basename, both dot-free in
# practice, and any escaping scheme would have to be typed back correctly into `--ack` by the
# caller to buy anything.
#
# `grillWaivers` is deliberately NOT the ack channel. A waiver is permanent config state; this is
# a one-time event. Waiving a path would silence the guard for it on every future re-onboard, so
# the SECOND accidental destruction of the same key would go through silently.
set -uo pipefail

usage() {
  echo "usage: config-diff-guard.sh <existing-config.json> <draft-config.json> [--ack <path>]..." >&2
  exit 3
}

EXISTING=""
DRAFT=""
ACKS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ack)
      shift
      [[ $# -gt 0 ]] || { echo "config-diff-guard: --ack needs a config path" >&2; usage; }
      ACKS+=("$1"); shift ;;
    --) shift ;;
    -*) echo "config-diff-guard: unknown option: $1" >&2; usage ;;
    *)
      if [[ -z "$EXISTING" ]]; then EXISTING="$1"
      elif [[ -z "$DRAFT" ]]; then DRAFT="$1"
      else echo "config-diff-guard: unexpected extra argument: $1" >&2; usage
      fi
      shift ;;
  esac
done
[[ -n "$EXISTING" && -n "$DRAFT" ]] || usage

# An unreadable EXISTING config is an error, never a silent skip: diff mode is impossible against
# a document Step 0 could not load, and skipping would disable the guard exactly when the config
# is already damaged.
for f in "$EXISTING" "$DRAFT"; do
  [[ -f "$f" ]] || { echo "config-diff-guard: no such file: $f" >&2; exit 3; }
  jq empty "$f" 2>/dev/null || { echo "config-diff-guard: not valid JSON: $f" >&2; exit 3; }
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 \
    || { echo "config-diff-guard: not a JSON object: $f" >&2; exit 3; }
done

if [[ "${#ACKS[@]}" -eq 0 ]]; then
  ACKS_JSON='[]'
else
  ACKS_JSON="$(printf '%s\n' "${ACKS[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"
fi

# The walk (see docs/plans/second-shift-450-lean.md AC-2): descend objects, treat an ARRAY as a
# leaf compared whole. commands.<id>.lanes, extraLanes and reviewers.add are arrays of objects, so
# index-level paths would report a cascade of shifted elements on a single insertion — noise that
# trains the reader to acknowledge blindly.
#
# An existing `null` leaf is skipped: there is nothing there to destroy.
#
# `$schema` is the only excluded key. Step 4 rewrites it to the pinned ref on every run, so a
# pin-upgrade re-onboard would otherwise fire a delta every single time.
#
# A draft value of `null` is `removed`, not `changed`: the key survives and the value does not,
# which IS the motivating evidence. Draft-only paths are never reported — an addition destroys
# nothing — which is why the walk is over the existing document.
jq -n \
  --slurpfile existing "$EXISTING" \
  --slurpfile draft "$DRAFT" \
  --argjson acks "$ACKS_JSON" '
  def leafpaths($p):
    if type == "object"
    then [ to_entries[] | .key as $k | (.value | leafpaths($p + [$k])) ] | add // []
    else [$p] end;
  def dget($doc; $p): (try ($doc | getpath($p)) catch null);

  ($existing[0]) as $E | ($draft[0]) as $D
  | [ ($E | leafpaths([]))[]
      | select(. != ["$schema"])
      | . as $p
      | ($E | getpath($p)) as $ev
      | select($ev != null)
      | (dget($D; $p)) as $dv
      | (if ($p | length) == 0 then "absent"
         else (dget($D; $p[0:-1])) as $par
              | if ($par | type) == "object" and ($par | has($p[-1]))
                then "present" else "absent" end
         end) as $pres
      | if $dv == null then
          { path: ($p | join(".")), kind: "removed", existing: $ev, draft: null,
            state: (if $pres == "absent" then "absent" else "null" end) }
        elif $dv != $ev then
          { path: ($p | join(".")), kind: "changed", existing: $ev, draft: $dv, state: "differs" }
        else empty end ]
  | map(. + {
      evidence: (
        if .kind == "removed" then
          "\(.path) is \(.existing | tojson) in the committed config, and the draft "
          + (if .state == "absent" then "omits the key entirely." else "sets it to null." end)
          + " Nothing downstream will notice: a capability that is off simply never runs and the run still reports green."
        else
          "\(.path) is \(.existing | tojson) in the committed config, and the draft would change it to \(.draft | tojson)."
        end),
      proposal: (
        "Restore \(.path) in the draft, or — if this "
        + (if .kind == "removed" then "removal" else "change" end)
        + " is what the human intends — confirm it and re-run with --ack \(.path). "
        + "The acknowledgment is per-run and writes nothing, so the same value is protected again on the next re-onboard.")
    } | del(.state))
  | . as $d
  | ([$d[] | .path]) as $paths
  | { deltas:        [ $d[] | . as $x | select(($acks | index($x.path)) == null) ],
      acknowledged:  [ $d[] | .path | . as $p | select(($acks | index($p)) != null) ],
      unmatchedAcks: [ $acks[] | . as $a | select(($paths | index($a)) == null) ] }
'
exit 0
