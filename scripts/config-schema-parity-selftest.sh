#!/usr/bin/env bash
# config-schema-parity-selftest.sh — config-lint.sh must reject every shape the config schema rejects.
#
# Walks schema/second-shift.config.schema.json and derives one invalid config per rule: an unknown key
# under each `additionalProperties: false` object, a wrong-typed value for each typed node (array items
# and map values included), a value outside each enum or const, a value under each bound, and each
# required key left out. Every invalid config sits in an otherwise minimal valid config, and that base
# is linted too, so a rejection is the mutant's own. A keyword the walker does not handle fails the
# suite rather than going unchecked.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/plugins/dev-pipeline/tools/config-lint.sh"
SCHEMA="$ROOT/schema/second-shift.config.schema.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

# Where config-lint deliberately accepts what the schema rejects. Each entry is a label glob and its
# reason; an entry that no accepted case matches is stale and fails the suite.
EXCEPTIONS=(
  'tracker.bot.app.* = *|the app keys are checked by name only, any value type, as the per-engineer file checks them'
  '* = null|an explicit null on an optional key is read as the key being absent'
)

# Values config-lint needs beyond the schema's own minimum, at the config path the walker builds
# (a map key is "app", an array index 0).
OVERRIDES='{
  "commands.app.testRunners.0.command": "t {file}",
  "design.liveRender.command": "r {route} {out}"
}'

echo "config-schema parity selftest:"

jq -c --argjson over "$OVERRIDES" '
  def key($p): $p | map(tostring) | join(".");
  def name($p): if $p == [] then "<config>" else key($p) end;
  def ok_type($v; $t):
    if $t == "integer" then ($v | type) == "number" and $v == ($v | floor)
    else ($v | type) == $t end;
  def types($s): $s.type | if type == "array" then . elif . == null then [] else [.] end;
  def minimal($s; $p):
    if $over | has(key($p)) then $over[key($p)]
    elif $s | has("const") then $s.const
    elif $s | has("enum") then $s.enum[0]
    else (types($s)[0]) as $t
      | if $t == "object" then
          (reduce ($s.required // [])[] as $r ({}; .[$r] = minimal($s.properties[$r]; $p + [$r])))
          | if ($s.minProperties // 0) >= 1 and ($s.additionalProperties | type) == "object"
            then .app = minimal($s.additionalProperties; $p + ["app"]) else . end
        elif $t == "array" then (if ($s.minItems // 0) >= 1 then [minimal($s.items; $p + [0])] else [] end)
        elif $t == "string" then "x"
        elif $t == "integer" then ($s.minimum // 1)
        elif $t == "number" then (if $s | has("minimum") then $s.minimum elif $s | has("exclusiveMinimum") then $s.exclusiveMinimum + 1 else 1 end)
        elif $t == "boolean" then true
        else null end
    end;
  def materialize($chain): reduce $chain[] as $c (.;
      if getpath($c.p) == null then setpath($c.p; minimal($c.s; $c.p)) else . end);
  def known: ["type","properties","additionalProperties","required","items","enum","const","minItems",
              "minProperties","minLength","minimum","exclusiveMinimum","pattern","format","description",
              "default","title","$schema","$id"];
  def reject($p; $what; $config): {kind: "reject", "label": (name($p) + $what), config: $config};
  def walk($s; $p; $anc; $root):
    ($anc + [{p: $p, s: $s}]) as $chain
    | ($root | materialize($anc)) as $up
    | ($root | materialize($chain)) as $here
    | (($s | keys) - known) as $unknown
    | (if $unknown != [] then {kind: "unhandled", "label": (name($p) + ": " + ($unknown | join(",")))} else empty end),
      (if types($s) | index(["object"]) then {kind: "control", "label": name($p), config: $here} else empty end),
      (if ($s | has("type")) or ($s | has("enum")) or ($s | has("const")) then
         (7, 1.5, "s", true, [1], {"k": 1}, null) as $v
         | select(types($s) | any(. as $t | ok_type($v; $t)) | not)
         | select((($s | has("enum")) and ($s.enum | index([$v]) != null)) | not)
         | select((($s | has("const")) and $s.const == $v) | not)
         | reject($p; " = " + ($v | tojson); $up | setpath($p; $v))
       else empty end),
      (if $s | has("enum") then reject($p; " = \"not-in-enum\""; $up | setpath($p; "not-in-enum")) else empty end),
      (if ($s | has("const")) and ($s.const | type) == "number" then reject($p; " = " + ($s.const + 1 | tojson); $up | setpath($p; $s.const + 1)) else empty end),
      (if $s | has("minItems") then reject($p; " = [] (minItems)"; $up | setpath($p; [])) else empty end),
      (if $s | has("minProperties") then reject($p; " = {} (minProperties)"; $up | setpath($p; {})) else empty end),
      (if $s | has("minLength") then reject($p; " = \"\" (minLength)"; $up | setpath($p; "")) else empty end),
      (if $s | has("minimum") then reject($p; " = " + ($s.minimum - 1 | tojson) + " (minimum)"; $up | setpath($p; $s.minimum - 1)) else empty end),
      (if $s | has("exclusiveMinimum") then reject($p; " = " + ($s.exclusiveMinimum | tojson) + " (exclusiveMinimum)"; $up | setpath($p; $s.exclusiveMinimum)) else empty end),
      (if $s.additionalProperties == false then reject($p; " + unknown key"; $here | setpath($p + ["not-a-key"]; 1)) else empty end),
      (($s.required // [])[] as $r | reject($p; " without " + $r; $here | delpaths([$p + [$r]]))),
      (($s.properties // {}) | to_entries[] | walk(.value; $p + [.key]; $chain; $root)),
      (if ($s.additionalProperties | type) == "object" then walk($s.additionalProperties; $p + ["app"]; $chain; $root) else empty end),
      (if $s | has("items") then walk($s.items; $p + [0]; $chain; $root) else empty end);
  . as $schema | walk($schema; []; []; minimal($schema; []))
' "$SCHEMA" > "$TMP/cases.jsonl" || { bad "the schema walk failed"; exit 1; }

[ -s "$TMP/cases.jsonl" ] || { bad "the schema walk produced no cases"; exit 1; }

declare -a HITS
for i in "${!EXCEPTIONS[@]}"; do HITS[i]=0; done
n=0; controls=0; rejects=0; rejected=0; excepted=0
while IFS= read -r line; do
  n=$((n + 1))
  kind="$(jq -r .kind <<<"$line")"; lbl="$(jq -r .label <<<"$line")"
  if [ "$kind" = unhandled ]; then bad "the walker does not handle schema keyword(s) at $lbl"; continue; fi
  jq .config <<<"$line" > "$TMP/c$n.json"
  out="$("$LINT" "$TMP/c$n.json" 2>&1)"; rc=$?
  if [ "$kind" = control ]; then
    controls=$((controls + 1))
    [ "$rc" -eq 0 ] || bad "minimal valid config at $lbl lints rc=$rc: $(grep '✗' <<<"$out" | head -2 | tr '\n' ' ')"
    continue
  fi
  rejects=$((rejects + 1))
  if [ "$rc" -eq 1 ]; then rejected=$((rejected + 1)); continue; fi
  matched=""
  for i in "${!EXCEPTIONS[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$lbl" == ${EXCEPTIONS[i]%%|*} ]]; then matched=1; HITS[i]=$((HITS[i] + 1)); break; fi
  done
  if [ -n "$matched" ] && [ "$rc" -eq 0 ]; then excepted=$((excepted + 1)); continue; fi
  bad "schema rejects $lbl, config-lint exits $rc$( [ "$rc" -gt 1 ] && printf ': %s' "$(head -1 <<<"$out")")"
done < "$TMP/cases.jsonl"

for i in "${!EXCEPTIONS[@]}"; do
  if [ "${HITS[i]}" -gt 0 ]; then ok "exception '${EXCEPTIONS[i]%%|*}' (${EXCEPTIONS[i]#*|}): ${HITS[i]} case(s)"
  else bad "exception '${EXCEPTIONS[i]%%|*}' matches no accepted case — delete it"; fi
done
ok "$controls minimal valid configs lint clean"
echo "  $rejected of $rejects schema-invalid configs rejected by config-lint, $excepted excepted"

if [ "$FAILS" -gt 0 ]; then echo "config-schema parity selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-schema parity selftest: all green"
