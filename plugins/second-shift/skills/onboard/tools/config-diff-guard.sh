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
    # No `--` end-of-options arm: implementing GNU semantics here would buy nothing (both
    # positionals are temp-file paths chosen by the caller, never `-`-leading) and an arm that
    # merely consumes the token advertises a terminator that does not terminate. `--` is an
    # unknown option, and says so. (The `--` further down is jq's terminator, not this one's — an
    # `--ack` VALUE may well be `-`-leading, because the caller does not choose it.)
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
#
# The shape check is SLURPED — `jq -e 'type == "object"' file` reports the status of jq's LAST
# output, so a file holding a JSON *stream* (`[1,2]` then `{...}`) passes it outright, and the
# `--slurpfile … | .[0]` read below would then walk only document one while the rest of the file
# went unprotected. That is a damaged config getting the silent skip this guard exists to refuse.
# `jq -se 'length == 1 and …'` reads the whole file before deciding, so a doubled write or a
# botched conflict resolution is an error rather than a partial comparison.
for f in "$EXISTING" "$DRAFT"; do
  [[ -f "$f" ]] || { echo "config-diff-guard: no such file: $f" >&2; exit 3; }
  jq empty "$f" 2>/dev/null || { echo "config-diff-guard: not valid JSON: $f" >&2; exit 3; }
  jq -se 'length == 1 and (.[0] | type == "object")' "$f" >/dev/null 2>&1 \
    || { echo "config-diff-guard: not a single JSON object: $f" >&2; exit 3; }
done

# `--args` carries the array across verbatim. Joining on newlines and re-splitting would lose the
# boundaries AC-3 calls exact: one `--ack` carrying an embedded newline would become two acks, and
# `--ack ""` would vanish without ever reaching unmatchedAcks[]. The empty-array branch is for
# bash 3.2, where `"${ACKS[@]}"` on an empty array trips `set -u`.
#
# The `--` is load-bearing: `--args` fixes value BOUNDARIES, not value INTERPRETATION. Without it
# jq parses a `-`-leading ack as one of its OWN options — `jq --args "-n"` yields `[]` — so that
# ack is neither suppressed nor reported in unmatchedAcks[]; it disappears, which is the same
# silent-drop class the newline round-trip had. Only the terminator makes every remaining word
# positional. The status is checked for the reason the comparison below captures its output: a jq
# that died leaves ACKS_JSON empty, an empty `--argjson` then kills the MAIN filter, and the one
# guard-authored line the operator sees would name the wrong subsystem.
if [[ "${#ACKS[@]}" -eq 0 ]]; then
  ACKS_JSON='[]'
else
  ACKS_JSON="$(jq -nc '$ARGS.positional' --args -- "${ACKS[@]}")" \
    || { echo "config-diff-guard: could not marshal --ack values" >&2; exit 3; }
fi

# The walk (see docs/plans/second-shift-450-lean.md AC-2): descend objects, treat an ARRAY as a
# leaf compared whole. commands.<id>.lanes, extraLanes and reviewers.add are arrays of objects, so
# index-level paths would report a cascade of shifted elements on a single insertion — noise that
# trains the reader to acknowledge blindly.
#
# An existing `null` leaf is skipped: there is nothing there to destroy. Its limit, stated where a
# reader looks for it rather than left to be discovered: the guard reports subtrees only through
# their leaves, so a subtree whose leaves are ALL null — a `commands.<id>` with every lane unset —
# is deletable wholesale with zero deltas. Every leaf under it is individually nothing.
#
# `$schema` is the only excluded key. Step 4 rewrites it to the pinned ref on every run, so a
# pin-upgrade re-onboard would otherwise fire a delta every single time.
#
# A draft value of `null` is `removed`, not `changed`: the key survives and the value does not,
# which IS the motivating evidence. Draft-only paths are never reported — an addition destroys
# nothing — which is why the walk is over the existing document.
#
# The result is captured rather than streamed: a filter that died would otherwise print nothing,
# and nothing reads as "no deltas" to a caller that only sees stdout and an exit status. Validation
# above makes this near-unreachable — but "the comparison did not run" must never be spelled the
# same way as "the comparison found nothing", which is the same fail-open family the slurped shape
# check closes.
OUT="$(jq -n \
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
')" || { echo "config-diff-guard: comparison failed" >&2; exit 3; }
printf '%s\n' "$OUT"
exit 0
