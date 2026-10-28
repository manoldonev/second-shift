#!/usr/bin/env bash
# blind-prove-selftest.sh — the blind-prove arm on a local case, with a fake claude and a fake probe function:
# the stage order, each stage's handover byte for byte, the per-stage blindness voids read from transcripts by
# the bench's own scan, a failed stage, the cost cap, the probe limit, plain's scoring path, the bound probe
# on the real checkouts, and `run`'s refusals before any model call. Nothing calls a model or the network.
# shellcheck disable=SC2016  # the fixtures, probe commands and python are text, written literally
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
TD="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TD%/}/blind-prove-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
field() { python3 -c '
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v[int(k)] if isinstance(v, list) else (v or {}).get(k)
print(json.dumps(v) if isinstance(v, (dict, list)) else v)' "$@" 2>/dev/null; }

U="$T/acme/tool"; mkdir -p "$U/src"
printf 'sum() { echo $(( $1 - $2 )); }\n' > "$U/src/sum.sh"
g -C "$U" init -q && g -C "$U" add -A && g -C "$U" commit -qm "initial import"
g -C "$U" config uploadpack.allowAnySHA1InWant true
BASE="$(git -C "$U" rev-parse HEAD)"
g -C "$U" checkout -qb fix
mkdir -p "$U/docs/plans"
printf 'sum() { echo $(( $1 + $2 )); }\n' > "$U/src/sum.sh"
printf '# Plan\n\n## 1. Sum\n\n- [ ] 1.1 Make sum add (src/sum.sh) [AC-1]\n' > "$U/docs/plans/tool-41-plan.md"
g -C "$U" add -A && g -C "$U" commit -qm "the fix"
R="$T/root"; mkdir -p "$R/overlays/acme__tool" "$R/arms" "$R/cases/abc123"
cp "$HERE/arms/hunt.md" "$HERE/arms/prove.md" "$HERE/arms/intent.md" "$R/arms/"
printf '# Review context\n\nShell functions print their result on stdout.\n' > "$R/overlays/acme__tool/review-context.md"
printf '{"configVersion": 3, "tracker": {"type": "github"}, "commands": {}}\n' > "$R/overlays/acme__tool/config.json"
C="$R/cases/abc123"
printf '{"upstream": "file://%s", "instance": "acme__tool-42", "license": "MIT", "base": "%s", "base_branch": "main", "overlay": "acme__tool", "issue": 41, "pr": 42, "commit": "fix: sum adds its arguments", "truth": {"class": "P1", "description": "Sum still subtracts in one branch.", "locations": [{"file": "src/sum.sh", "start": 1, "end": 1, "side": "head"}]}}\n' "$U" "$BASE" > "$C/case.json"
printf '# Sum subtracts\n\n`sum 2 3` prints -1.\n\n## Acceptance criteria\n\n- AC-1: `sum 2 3` prints 5.\n' > "$C/ticket.md"
printf '# Decision record — #41 Sum subtracts\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | How sum combines | It adds its {two} arguments. | user-answered | intent |\n' > "$C/record.md"
git -C "$U" diff "$BASE" fix > "$C/patch.diff"

mkdir -p "$T/fakebin"
# The envelope is `claude -p --output-format json`'s, as render-selftest.sh's fake writes it; a transcript line
# is the assistant tool_use record that bench.py's blindness_violations reads.
cat > "$T/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
sid="" name="" model=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id) sid="$2"; shift 2 ;;
    -n) name="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
  esac
done
stage="${name#bench-}"; stage="${stage%%-*}"
if [ -p /dev/stdin ]; then echo "fake claude: the prompt is a pipe" >&2; exit 1; fi
cat > "$FAKE_DIR/$stage.prompt"
echo "$stage $model $sid" >> "$FAKE_DIR/order"
[ ! -f "$FAKE_DIR/$stage.hang" ] || exec sleep 60
if [ -f "$FAKE_DIR/$stage.reads" ]; then
  mkdir -p "$HOME/.claude/projects/p"
  while IFS= read -r p; do
    python3 -c 'import json, sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": sys.argv[1]}}]}}))' "$p"
  done < "$FAKE_DIR/$stage.reads" >> "$HOME/.claude/projects/p/$sid.jsonl"
fi
if [ "$stage" = intent ] && [ -f "$FAKE_DIR/intent.verdict" ]; then
  cp "$FAKE_DIR/intent.verdict" "$(sed -n 's/^Output: write your verdict to `\(.*\)` in this form and nothing else:$/\1/p' "$FAKE_DIR/intent.prompt")"
fi
if [ -f "$FAKE_DIR/$stage.envelope" ]; then cat "$FAKE_DIR/$stage.envelope"; exit 0; fi
python3 -c '
import json, os, sys
model, cost, out = sys.argv[1:4]
text = open(out).read() if os.path.exists(out) else ""
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": text, "total_cost_usd": float(cost),
                  "num_turns": 2, "modelUsage": {model: {"inputTokens": 10}}}))' "$model" "$(cat "$FAKE_DIR/$stage.cost" 2>/dev/null || echo 0.5)" "$FAKE_DIR/$stage.out"
EOF
chmod +x "$T/fakebin/claude"

scenario() { mkdir -p "$T/s/$1"; echo "$T/s/$1"; }
drive() { # drive <scenario dir> [cap] [stage timeout] [real]: one case-run, its record in <dir>/rec.json
  FAKE_DIR="$1" HOME="$T/home" PATH="$T/fakebin:$PATH" python3 -c '
import asyncio, json, pathlib, sys
sys.path.insert(0, sys.argv[1]); import planted
root, s, clones = map(pathlib.Path, sys.argv[2:5])
cap, timeout, real = float(sys.argv[5]), int(sys.argv[6]), sys.argv[7]
canned = json.loads((s / "probe-results.json").read_text()) if (s / "probe-results.json").exists() else {}
def fake(cmd, d, t):
    files = {str(p.relative_to(d)): p.read_text() for p in sorted(d.rglob("*")) if p.is_file()}
    with open(s / "order", "a") as f:
        f.write("probe " + json.dumps({"cmd": cmd, "files": files, "timeout": t}) + "\n")
    return canned.get(cmd, {"verdict": "SAME", "reason": "", "before": {"rc": 0, "out": "", "err": ""}, "after": {"rc": 0, "out": "", "err": ""}})
models = {"hunt": "claude-alpha-x", "prove": "claude-beta-x", "intent": "claude-alpha-x"}
rec = asyncio.run(planted.blind_prove_one(planted.load_case(root / "cases" / "abc123"), 1, s / "work", clones, root, models,
                                          timeout, cap, asyncio.Semaphore(1), planted.load_bench(), None if real else fake))
(s / "rec.json").write_text(json.dumps(rec, indent=1, default=str))' "$HERE" "$R" "$1" "$T/clones" "${2:-3}" "${3:-30}" "${4:-}" > "$1/drive.log" 2>&1
}
order() { cut -d' ' -f1 "$1/order" 2>/dev/null | tr '\n' ' '; }
contains() { python3 -c 'import sys; sys.exit(0 if open(sys.argv[1]).read() in open(sys.argv[2]).read() else 1)' "$@"; }
VERDICT='verdict: needs-work
## Findings
- [blocker] B1 src/sum.sh:1 — sum 2 3 prints 5 where the caller in src/cli.sh expects -1.'

echo "== a full case-run =="
S="$(scenario full)"
cat > "$S/hunt.out" <<'EOF'
The change makes sum add. A caller reads {checkout} literally,
and src/cli.sh:3 → expects the old sign.

```candidates
[{"id": "C1", "site": "src/sum.sh:1", "input": "sum 2 3"}, {"id": "C2", "site": "src/sum.sh:1", "input": "a long run"}, {"oops": 1}]
```
EOF
cat > "$S/prove.out" <<'EOF'
Two commands, and one for a candidate that is not on the list. {hunt}

```probes
[{"candidate": "C1", "cmd": ". src/sum.sh; sum $(cat \"$PROBE_DIR/in.txt\")", "files": {"in.txt": "2 3"}}, {"candidate": "C2", "cmd": "long"}, {"candidate": "C9", "cmd": "true"}]
```
EOF
printf '%s\n' "$VERDICT" > "$S/intent.verdict"
python3 -c '
import json, sys
long = "x" * 2500
print(json.dumps({
    ". src/sum.sh; sum $(cat \"$PROBE_DIR/in.txt\")": {"verdict": "DIFFERS", "reason": "the stdout differ", "before": {"rc": 0, "out": "-1\n", "err": ""}, "after": {"rc": 0, "out": "5\n", "err": ""}},
    "long": {"verdict": "SAME", "reason": "", "before": {"rc": 0, "out": long, "err": ""}, "after": {"rc": 0, "out": long, "err": ""}}}))' > "$S/probe-results.json"
drive "$S"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$S/rec.json" status)" = ok ] && ok "the case-run exits 0 with status ok" || bad "full: rc=$rc $(tail -n 5 "$S/drive.log") $(head -c 400 "$S/rec.json" 2>/dev/null)"
[ "$(order "$S")" = "hunt prove probe probe probe intent " ] && ok "hunt, prove, three probes and intent run in that order" || bad "order: $(order "$S")"
[ "$(cut -d' ' -f1,2 "$S/order" | grep -v '^probe' | tr '\n' '|')" = "hunt claude-alpha-x|prove claude-beta-x|intent claude-alpha-x|" ] \
  && ok "each stage runs on its own model" || bad "models: $(tr '\n' '|' < "$S/order")"
contains "$S/hunt.out" "$S/prove.prompt" && ok "hunt's output reaches prove's prompt byte for byte" || bad "hunt's text is not verbatim in prove's prompt"
contains "$S/hunt.out" "$S/intent.prompt" && contains "$S/prove.out" "$S/intent.prompt" \
  && ok "hunt's and prove's outputs reach intent's prompt byte for byte" || bad "a handover is not verbatim in intent's prompt"
[ "$(python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print(r["stages"]["hunt"]["text"] == open(sys.argv[2]).read() and r["stages"]["prove"]["text"] == open(sys.argv[3]).read())' "$S/rec.json" "$S/hunt.out" "$S/prove.out")" = True ] \
  && ok "the record keeps hunt's and prove's whole text" || bad "stage texts in the record"
for p in hunt prove; do
  grep -qF "$R" "$S/$p.prompt" || grep -qF 'Sum subtracts' "$S/$p.prompt" || grep -qF 'How sum combines' "$S/$p.prompt" || grep -qF 'tool-41-plan' "$S/$p.prompt" \
    && bad "$p's prompt names the corpus, the ticket, the record or the plan" || ok "$p's prompt carries no ticket, record, plan or corpus path"
done
grep -qF '# Sum subtracts' "$S/intent.prompt" && grep -qF 'It adds its {two} arguments.' "$S/intent.prompt" \
  && ok "intent's prompt carries the ticket and the record" || bad "intent prompt: $(head -c 300 "$S/intent.prompt")"
hits="$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import planted
for p in sys.argv[2:]:
    print(*planted.markers_in(open(p).read()))' "$HERE" "$S/hunt.prompt" "$S/prove.prompt" "$S/intent.prompt" | tr -d '\n')"
[ -z "$hits" ] && ok "no stage prompt carries a marker" || bad "markers: $hits"

echo "== the record =="
[ "$(python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))
st = r["stages"]
ids = {s["session"] for s in st.values()}
print(sorted(st), len(ids), [st[s]["resolved_model"] for s in ("hunt", "prove", "intent")], [st[s]["violations"] for s in st], r["cost_usd"])' "$S/rec.json")" \
  = "['hunt', 'intent', 'prove'] 3 ['claude-alpha-x', 'claude-beta-x', 'claude-alpha-x'] [[], [], []] 1.5" ] \
  && ok "the record holds three session ids, three resolved models, three clean blindness results and one cost, 0.5 x 3" || bad "record: $(python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print({k: {kk: v.get(kk) for kk in ("session", "resolved_model", "violations", "cost_usd")} for k, v in r["stages"].items()}, r.get("cost_usd"))' "$S/rec.json" 2>&1)"
[ "$(field "$S/rec.json" stages hunt handover)" = '{"block": "ok", "items": 2, "invalid": 1}' ] && [ "$(field "$S/rec.json" stages prove handover)" = '{"block": "ok", "items": 3, "invalid": 0}' ] \
  && ok "the record counts each handover's items, and an item with no id is invalid" || bad "handover: $(field "$S/rec.json" stages hunt handover) $(field "$S/rec.json" stages prove handover)"
[ "$(field "$S/rec.json" probes 0 verdict)" = DIFFERS ] && [ "$(field "$S/rec.json" probes 0 after out)" = 5 ] && [ "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["probes"][1]["before"]["out"]))' "$S/rec.json")" = 2500 ] \
  && ok "the record keeps every probe result whole" || bad "probes: $(field "$S/rec.json" probes | head -c 300)"
grep -q '^probe {"cmd": ". src/sum.sh; sum $(cat \\"$PROBE_DIR/in.txt\\")", "files": {"in.txt": "2 3"}, "timeout": 120}$' "$S/order" \
  && ok "each probe runs with its files in its dir and 120 s per side" || bad "probe call: $(grep '^probe' "$S/order" | head -n 1)"
[ "$(field "$S/rec.json" wall_s)" -ge 0 ] 2>/dev/null && ok "the record sums one wall time" || bad "wall: $(field "$S/rec.json" wall_s)"

echo "== what intent reads of the probes =="
grep -qxF '### C1 at src/sum.sh:1' "$S/intent.prompt" && grep -qxF 'verdict: DIFFERS (the stdout differ)' "$S/intent.prompt" && grep -qxF 'before: exit code 0' "$S/intent.prompt" \
  && ok "a candidate's block names its site, its verdict and each side's exit code" || bad "C1 block: $(grep -A 6 '### C1' "$S/intent.prompt")"
grep -qxF 'before stdout, normalized: the first 2,000 of 2,500 characters, capped at 2,000' "$S/intent.prompt" \
  && [ "$(python3 -c 'import sys; print(open(sys.argv[1]).read().count("x" * 2000 + "\n~~~~"))' "$S/intent.prompt")" = 2 ] \
  && ok "a long stdout reaches intent cut at 2,000 characters, and the block states the cap" || bad "cap: $(grep -n 'characters' "$S/intent.prompt" | head -n 3)"
grep -qxF '### C9 at no site in the candidate list' "$S/intent.prompt" && ok "a command for a candidate hunt never named is shown on its own" || bad "C9 block missing"

echo "== intent's verdict goes through plain's scoring =="
out="$(python3 -c '
import asyncio, json, pathlib, sys
sys.path.insert(0, sys.argv[1]); import planted
r = json.load(open(sys.argv[2]))
c = planted.collect("plain", open(sys.argv[3]).read(), None, None)
print(all(r[k] == c[k] for k in ("status", "verdict", "findings", "rows", "problems", "text")))
case = planted.load_case(pathlib.Path(sys.argv[4]))
async def judge(golden, cand):
    return True
asyncio.run(planted.score_records({case["id"]: case}, [r], judge))
print(r["score"]["right"], r["score"]["how"])
arms = planted.tally({case["id"]: case}, [r, {**r, "arm": "plain"}, {**r, "arm": "lane"}])
print(sorted(arms), planted.gate(arms)["runs"], planted.gate(planted.tally({case["id"]: case}, [r])))
print(planted.model_segment("blind-prove", [r], None, r["models"]))' "$HERE" "$S/rec.json" "$S/intent.verdict" "$C" 2>&1)"
[ "$(sed -n 1p <<<"$out")" = True ] && ok "the record's verdict fields are collect(\"plain\", …) of intent's verdict file" || bad "collect: $out"
[ "$(sed -n 2p <<<"$out")" = "1 blocker" ] && ok "score_review scores intent's [blocker] as right" || bad "score: $out"
[ "$(sed -n 3p <<<"$out")" = "['blind-prove', 'lane', 'plain'] {'plain': 1, 'lane': 1} None" ] \
  && ok "tally keeps the arm apart, and gate() reads plain and lane only" || bad "gate: $(sed -n 3p <<<"$out")"
[ "$(sed -n 4p <<<"$out")" = "model=hunt claude-alpha-x, prove claude-beta-x, intent claude-alpha-x" ] && ok "the changelog row names each stage's model" || bad "model segment: $(sed -n 4p <<<"$out")"

echo "== the checkouts and the bound probe =="
W="$S/work"
[ ! -e "$W/probe/after/docs/plans/tool-41-plan.md" ] && [ -f "$W/checkout/docs/plans/tool-41-plan.md" ] && [ -z "$(git -C "$W/probe/after" status --porcelain)" ] \
  && ok "hunt and prove read the neutral after checkout with no plan file; intent reads plain's, with it" || bad "checkouts: $(ls "$W")"
[ "$(git -C "$W/checkout" log --format=%s | tr '\n' '|')" = "fix: sum adds its arguments|chore: add the review configuration|initial import|" ] \
  && ok "intent's checkout is plain's build" || bad "plain build: $(git -C "$W/checkout" log --format=%s | tr '\n' '|')"
"$W/state/bin/probe" --cmd '. src/sum.sh; sum 2 3; pwd; touch made.txt; ls "$PROBE_DIR"' --files '{"in.txt": "hi"}' > "$T/bound.json" 2> "$T/bound.err"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/bound.json" verdict)" = DIFFERS ] && [ "$(field "$T/bound.json" before out)" = "$(printf -- '-1\n<ROOT>\nin.txt')" ] && [ "$(field "$T/bound.json" after out)" = "$(printf '5\n<ROOT>\nin.txt')" ] \
  && ok "prove's probe runs on the case-run's real checkouts, with its files, and prints normalized output" || bad "bound: rc=$rc $(head -c 500 "$T/bound.json") $(tail -n 3 "$T/bound.err")"
grep -qF abc123 "$T/bound.json" || grep -qF "$R" "$T/bound.json" || grep -qF "$W" "$T/bound.json" \
  && bad "the bound probe's output names the case, the corpus or the work dir" || ok "the bound probe's output names no case id and no harness path"
! grep -qF abc123 "$W/state/bin/probe" && [ -n "$(find "$W/prove-scratch" -name in.txt)" ] \
  && ok "the wrapper carries no case id, and the files land under prove's scratch" || bad "wrapper: $(cat "$W/state/bin/probe")"
[ -z "$(git -C "$W/probe/after" status --porcelain)$(git -C "$W/probe/before" status --porcelain)" ] \
  && ok "both checkouts are back on their commit after a command that writes a file" || bad "dirt: $(git -C "$W/probe/after" status --porcelain | tr '\n' '|')"
"$W/state/bin/probe" --cmd 'true' --files '{"../out.txt": "x"}' > "$T/bound2.json" 2>&1
[ "$(field "$T/bound2.json" verdict)" = UNPROVEN ] && grep -q 'not a relative path inside the probe dir' "$T/bound2.json" \
  && ok "a file name that leaves the probe dir is UNPROVEN" || bad "bad files: $(cat "$T/bound2.json")"

echo "== the real probe =="
S="$(scenario real)"
printf '```candidates\n[{"id": "C1", "site": "src/sum.sh:1", "input": "sum 2 3"}]\n```\n' > "$S/hunt.out"
printf '```probes\n[{"candidate": "C1", "cmd": ". src/sum.sh; sum 2 3; touch left.txt"}, {"candidate": "C1", "cmd": "ls left.txt"}]\n```\n' > "$S/prove.out"
printf '%s\n' "$VERDICT" > "$S/intent.verdict"
drive "$S" 3 30 real
[ "$(field "$S/rec.json" probes 0 verdict)" = DIFFERS ] && [ "$(field "$S/rec.json" probes 0 before out)" = -1 ] && [ "$(field "$S/rec.json" probes 0 after out)" = 5 ] \
  && ok "without a fake, the probes run in the before and after checkouts built once" || bad "real probe: $(field "$S/rec.json" probes 0) $(tail -n 3 "$S/drive.log")"
[ "$(field "$S/rec.json" probes 1 before rc)" != 0 ] && [ "$(field "$S/rec.json" probes 1 after rc)" != 0 ] \
  && ok "a file one command writes is gone before the next" || bad "reset: $(field "$S/rec.json" probes 1)"

echo "== blindness per stage =="
blind() { # blind <name> <stage> <path read> <expected status>; the scenario dir is left in $S
  S="$(scenario "$1")"
  printf '```candidates\n[]\n```\n' > "$S/hunt.out"; printf '```probes\n[]\n```\n' > "$S/prove.out"; printf '%s\n' "$VERDICT" > "$S/intent.verdict"
  printf '%s\n' "${3//@W@/$S/work}" > "$S/$2.reads"
  drive "$S"
  if [ "$(field "$S/rec.json" status)" = "$4" ]; then ok "$1: a $2 session that reads ${3##*/} ends $4"; else bad "$1: status $(field "$S/rec.json" status), want $4; $(tail -n 3 "$S/drive.log")"; fi
}
blind hunt-case hunt "$C/case.json" "hunt: voided-blindness"
[ "$(order "$S")" = "hunt " ] && [ -n "$(field "$S/rec.json" stages hunt violations 0)" ] && ok "a voided hunt spawns no later stage and records the read" || bad "hunt-case: $(order "$S") $(field "$S/rec.json" stages hunt violations)"
blind hunt-ticket hunt "$C/ticket.md" "hunt: voided-blindness"
blind hunt-plan hunt "@W@/checkout/docs/plans/tool-41-plan.md" "hunt: voided-blindness"
blind prove-record prove "$C/record.md" "prove: voided-blindness"
[ "$(order "$S")" = "hunt prove " ] && ok "a voided prove runs no probe and no intent" || bad "prove-record: $(order "$S")"
blind prove-state prove "@W@/state/probe-binding.json" "prove: voided-blindness"
blind intent-plan intent "@W@/checkout/docs/plans/tool-41-plan.md" ok
blind intent-case intent "$C/case.json" "intent: voided-blindness"

echo "== a stage that fails =="
S="$(scenario prove-hang)"
printf '```candidates\n[]\n```\n' > "$S/hunt.out"; touch "$S/prove.hang"
drive "$S" 3 2
[ "$(field "$S/rec.json" status)" = "prove: timeout" ] && [ "$(order "$S")" = "hunt prove " ] && [ "$(field "$S/rec.json" stages prove cost_usd)" = None ] \
  && ok "a prove session past its timeout stops the case-run as 'prove: timeout', and intent never spawns" || bad "prove-hang: $(field "$S/rec.json" status) $(order "$S")"
out="$(python3 -c '
import json, pathlib, sys
sys.path.insert(0, sys.argv[1]); import planted
r = json.load(open(sys.argv[2])); case = planted.load_case(pathlib.Path(sys.argv[3]))
print(planted.tally({case["id"]: case}, [r])["blind-prove"]["1"]["classes"]["P1"]["unscorable"])' "$HERE" "$S/rec.json" "$C" 2>&1)"
[ "$out" = 1 ] && ok "tally counts a stopped case-run unscorable" || bad "tally: $out"
S="$(scenario hunt-turns)"
# the shape tools/classify-capture-selftest.sh records for a session cut at --max-turns
printf '{"type":"result","subtype":"error_max_turns","is_error":false,"total_cost_usd":0.2}\n' > "$S/hunt.envelope"
drive "$S"
[ "$(field "$S/rec.json" status)" = "hunt: error_max_turns" ] && [ "$(order "$S")" = "hunt " ] && [ "$(field "$S/rec.json" cost_usd)" = 0.2 ] \
  && ok "a hunt cut at its turn limit stops the case-run as 'hunt: error_max_turns', with its cost kept" || bad "hunt-turns: $(field "$S/rec.json" status) $(order "$S")"
S="$(scenario empty)"
printf 'Nothing here looks breakable.\n' > "$S/hunt.out"; printf '```probes\nnot json\n```\n' > "$S/prove.out"; printf '%s\n' "$VERDICT" > "$S/intent.verdict"
drive "$S"
[ "$(field "$S/rec.json" status)" = ok ] && [ "$(order "$S")" = "hunt prove intent " ] && [ "$(field "$S/rec.json" stages hunt handover block)" = missing ] && [ "$(field "$S/rec.json" stages prove handover block)" = unparsable ] \
  && grep -qxF 'No command ran.' "$S/intent.prompt" && ok "a missing or unparsable block is zero items, recorded, and intent still runs" || bad "empty: $(field "$S/rec.json" status) $(order "$S") $(field "$S/rec.json" stages hunt handover)"

echo "== the cost cap and the probe limit =="
S="$(scenario cap)"
printf '```candidates\n[]\n```\n' > "$S/hunt.out"; printf '```probes\n[{"candidate": "C1", "cmd": "true"}]\n```\n' > "$S/prove.out"; echo 0.8 > "$S/prove.cost"
drive "$S" 1
[ "$(field "$S/rec.json" status)" = 'prove: over the cost cap ($1.30 of $1.00)' ] && [ "$(order "$S")" = "hunt prove " ] && [ "$(field "$S/rec.json" cost_usd)" = 1.3 ] \
  && ok "a summed cost past --max-cost after prove stops the case-run before any probe, naming the stage" || bad "cap: $(field "$S/rec.json" status) $(order "$S")"
S="$(scenario many)"
printf '```candidates\n[]\n```\n' > "$S/hunt.out"; printf '%s\n' "$VERDICT" > "$S/intent.verdict"
python3 -c 'import json; print("```probes\n" + json.dumps([{"candidate": "C1", "cmd": f"echo {n}"} for n in range(10)]) + "\n```")' > "$S/prove.out"
drive "$S"
[ "$(grep -c '^probe ' "$S/order")" = 8 ] && [ "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["dropped"]))' "$S/rec.json")" = 2 ] \
  && grep -qxF '2 more command(s) did not run: at most 8 run per review.' "$S/intent.prompt" \
  && ok "at most 8 probes run, and the rest are recorded as dropped and told to intent" || bad "many: $(grep -c '^probe ' "$S/order") $(field "$S/rec.json" dropped)"

echo "== run's refusals =="
mkdir -p "$T/cli"
cli() { FAKE_DIR="$T/cli" PATH="$T/fakebin:$PATH" HUNT_MODEL="${HM-claude-alpha-x}" PROVE_MODEL="${PM-claude-beta-x}" INTENT_MODEL="${IM-claude-alpha-x}" JUDGE_MODEL=claude-gamma-x \
  python3 "$HERE/planted.py" --root "$R" run "$@" 2>&1; }
out="$(cli --arm blind-prove --arm plain)"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "[planted] --arm blind-prove runs alone; drop --arm plain and --arm lane" ] && ok "blind-prove beside another arm is refused" || bad "beside plain: rc=$rc $out"
out="$(PM=claude-alpha-y cli --arm blind-prove)"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "[planted] prove model claude-alpha-y is in hunt's family alpha; prove runs on the other family" ] && ok "a prove model in hunt's family is refused" || bad "same family: rc=$rc $out"
out="$(IM='' cli --arm blind-prove)"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "[planted] INTENT_MODEL is empty" ] && ok "an empty stage model is refused" || bad "empty model: rc=$rc $out"
out="$(cli --pilot --arm blind-prove)"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "[planted] --pilot reviews with the plain arm only; drop --arm blind-prove" ] && ok "--pilot refuses blind-prove" || bad "pilot: rc=$rc $out"
out="$(cli --arm blind-prove --max-cost 0)"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "[planted] --max-cost must be a positive number of USD" ] && ok "a --max-cost of 0 is refused" || bad "max-cost: rc=$rc $out"
[ ! -e "$T/cli/order" ] && ok "no refusal spawns a session" || bad "a session spawned: $(cat "$T/cli/order")"
python3 "$HERE/planted.py" --root "$R" render --case abc123 --arm blind-prove --dest "$T/r" > /dev/null 2>&1; rc=$?
out="$(python3 -c '
import pathlib, sys
sys.path.insert(0, sys.argv[1]); import planted
try:
    planted.build(planted.load_case(pathlib.Path(sys.argv[2])), "blind-prove", pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]), pathlib.Path(sys.argv[5]))
except planted.BuildError as e:
    print(e)' "$HERE" "$C" "$T/b" "$T/clones" "$R" 2>&1)"
[ "$rc" -eq 2 ] && [ "$out" = "unknown arm blind-prove" ] && ok "render and build() take plain and lane only" || bad "render rc=$rc build: $out"

echo "blind-prove-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
