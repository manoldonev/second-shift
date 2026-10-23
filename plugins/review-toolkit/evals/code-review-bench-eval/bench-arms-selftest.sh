#!/usr/bin/env bash
# bench-arms-selftest.sh — every arm under arms/ loads through bench.py's own parse_arm and formats with
# the placeholders review_once passes it. A stray brace in an arm otherwise crashes the bench after its
# calibration and checkouts are paid for. No session is spawned: model-free, like the rest of CI.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/bench-arms-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# load <arms-dir> -> one line per arm: OK|ERR <tab> name <tab> spawn <tab> allow <tab> whether {out} reached the prompt
load() {
  python3 -I - "$HERE" "$1" <<'PY'
import importlib.util, sys
from pathlib import Path
here, arms = Path(sys.argv[1]), Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("bench", here / "bench.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
ph = dict(checkout="/co", base="b0", head="h0", scratch="/s", out="/s/findings.md")
rules = (here / "rules.md").read_text().format(**ph)
for p in sorted(arms.glob("*.md")):
    arm = bench.parse_arm(p)
    try:
        prompt = arm["prompt"].format(rules=rules, **ph)
    except (KeyError, IndexError, ValueError) as e:
        print(f"ERR\t{arm['name']}\t{type(e).__name__}: {e}")
        continue
    print(f"OK\t{arm['name']}\t{arm.get('spawn')}\t{arm.get('allow', '')}\t{int(ph['out'] in prompt)}")
PY
}

echo "== code-review-bench arms =="
out="$(load "$HERE/arms")"; rc=$?
n_files="$(find "$HERE/arms" -name '*.md' -type f | wc -l | tr -d ' ')"
[ "$rc" -eq 0 ] && [ "$(awk -F'\t' '$1 == "OK"' <<<"$out" | wc -l | tr -d ' ')" = "$n_files" ] \
  && ok "all $n_files arms load and format through bench.py" || bad "rc=$rc: $(tr '\n\t' '| ' <<<"$out")"
lane="$(awk -F'\t' '$2 == "lane-review"' <<<"$out")"
[ "$(cut -f1,3 <<<"$lane")" = "$(printf 'OK\tclaude')" ] && [ "$(cut -f5 <<<"$lane")" = 1 ] \
  && ok "lane-review is a claude arm whose prompt names the output file" || bad "lane-review: [$(tr '\t' ' ' <<<"$lane")]"
[ "$(cut -f4 <<<"$lane")" = 'Read,Grep,Glob,Write,Bash(git *)' ] \
  && ok "lane-review runs on the review session's read grants plus Write, with no gh" || bad "lane-review allow: [$(cut -f4 <<<"$lane")]"

printf 'spawn: claude\n---\n{rules}\n\nA JSON example: {"a": 1}\n' > "$T/braced.md"
out="$(load "$T")"
[ "$(cut -f1,2 <<<"$out")" = "$(printf 'ERR\tbraced')" ] && ok "an arm with a literal brace is reported, not loaded" || bad "braced arm: [$(tr '\t' ' ' <<<"$out")]"

echo "bench-arms-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
