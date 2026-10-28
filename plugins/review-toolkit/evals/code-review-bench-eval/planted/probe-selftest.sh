#!/usr/bin/env bash
# probe-selftest.sh — `planted.py probe` on local fixture upstreams, with a fake npm and a fake corepack: the
# neutral before and after checkouts, the install each package manager gets, the overlay's setup step, the
# install cache, and each verdict. Nothing calls a model or the network.
# shellcheck disable=SC2016  # the fixtures and probe commands are shell text, written literally
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
TD="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TD%/}/probe-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
field() { python3 -c '
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v[int(k)] if isinstance(v, list) else (v or {}).get(k)
print(json.dumps(v) if isinstance(v, (dict, list)) else v)' "$@" 2>/dev/null; }

R="$T/root"; mkdir -p "$R/cases"
upstream() { # upstream <name> <package.json> [<lockfile name> <lockfile text>]
  local u="$T/acme/$1"; mkdir -p "$u/src"
  printf 'sum() { echo $(( $1 - $2 )); }\n' > "$u/src/sum.sh"
  printf '%s\n' "$2" > "$u/package.json"
  printf 'dist/\n' > "$u/.gitignore"
  [ -z "${3:-}" ] || printf '%s\n' "$4" > "$u/$3"
  g -C "$u" init -q && g -C "$u" add -A && g -C "$u" commit -qm "initial import"
  local base; base="$(git -C "$u" rev-parse HEAD)"
  g -C "$u" checkout -qb fix
  mkdir -p "$u/docs/plans"
  printf 'sum() { echo $(( $1 + $2 )); }\n' > "$u/src/sum.sh"
  printf '# Plan\n\n## 1. Sum\n\n- [ ] 1.1 Make sum add (src/sum.sh) [AC-1]\n' > "$u/docs/plans/$1-41-plan.md"
  g -C "$u" add -A && g -C "$u" commit -qm "the fix"
  mkdir -p "$R/overlays/acme__$1"
  printf '# Review context\n\nShell functions print their result on stdout.\n' > "$R/overlays/acme__$1/review-context.md"
  printf '{"configVersion": 3, "tracker": {"type": "github"}, "commands": {}}\n' > "$R/overlays/acme__$1/config.json"
  echo "$base"
}
mkcase() { # mkcase <id> <upstream name> <base> [<patch file>]
  local d="$R/cases/$1"; mkdir -p "$d"
  printf '{"upstream": "file://%s", "instance": "acme__%s-42", "license": "MIT", "base": "%s", "base_branch": "main", "overlay": "acme__%s", "issue": 41, "pr": 42, "commit": "fix: sum adds its arguments", "truth": {"class": "control"}}\n' "$T/acme/$2" "$2" "$3" "$2" > "$d/case.json"
  printf '# Sum subtracts\n\n`sum 2 3` prints -1.\n\n## Acceptance criteria\n\n- AC-1: `sum 2 3` prints 5.\n' > "$d/ticket.md"
  printf '# Decision record — #41 Sum subtracts\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | How sum combines | It adds. | user-answered | intent |\n' > "$d/record.md"
  if [ -n "${4:-}" ]; then cp "$4" "$d/patch.diff"; else git -C "$T/acme/$2" diff "$3" fix > "$d/patch.diff"; fi
}
CALC="$(upstream calc '{"name": "calc"}' package-lock.json '{"name": "calc", "lockfileVersion": 3}')"
LOOSE="$(upstream loose '{"name": "loose"}')"
WEB="$(upstream web '{"name": "web", "packageManager": "pnpm@9.0.0"}' pnpm-lock.yaml "lockfileVersion: '9.0'")"
YARNY="$(upstream yarny '{"name": "yarny", "packageManager": "yarn@3.2.4"}' yarn.lock '__metadata:')"
printf '{"setup": "pnpm run build"}\n' > "$R/overlays/acme__web/probe.json"
mkcase abc123 calc "$CALC"
mkcase loo111 loose "$LOOSE"
mkcase web222 web "$WEB"
mkcase yar333 yarny "$YARNY"
printf -- '--- a/src/sum.sh\n+++ b/src/sum.sh\n@@ -1 +1 @@\n-sum() { echo nothing; }\n+sum() { echo $(( $1 + $2 )); }\n' > "$T/stale.diff"
mkcase bad444 calc "$CALC" "$T/stale.diff"

mkdir -p "$T/fakebin"
cat > "$T/fakebin/npm" <<'EOF'
#!/usr/bin/env bash
hit=miss; [ -e "$npm_config_cache/seen" ] && hit=hit
mkdir -p "$npm_config_cache" && touch "$npm_config_cache/seen"
echo "npm $(basename "$PWD") $1 $hit" >> "$FAKE_LOG"
[ -z "${FAKE_NPM_FAIL:-}" ] || { echo "npm ERR! fake failure" >&2; exit 1; }
[ "$1" != ci ] || [ -f package-lock.json ] || { echo "npm ci needs a package-lock.json" >&2; exit 1; }
[ "$1" != install ] || [ -f package-lock.json ] || echo '{"lockfileVersion": 3, "generated": true}' > package-lock.json
mkdir -p node_modules/.fake
EOF
cat > "$T/fakebin/corepack" <<'EOF'
#!/usr/bin/env bash
echo "corepack $(basename "$PWD") $* store=$npm_config_store_dir yarn=$YARN_CACHE_FOLDER prompt=$COREPACK_ENABLE_DOWNLOAD_PROMPT" >> "$FAKE_LOG"
if [ "$2" = run ] && [ "$3" = build ]; then mkdir -p dist && echo built > dist/out; else mkdir -p node_modules/.fake; fi
EOF
chmod +x "$T/fakebin/npm" "$T/fakebin/corepack"
export FAKE_LOG="$T/fake.log"
: > "$FAKE_LOG"
N=0
pr() { # pr <out name> <case> <command> [extra flags...]; the checkouts land in $T/<out name>
  local name="$1" c="$2" cmd="$3"; shift 3
  PATH="$T/fakebin:$PATH" python3 "$HERE/planted.py" --root "$R" probe "$c" --cmd "$cmd" --dest "$T/$name" --clones "$T/clones" "$@" > "$T/$name.json" 2> "$T/$name.err"
}
log_since() { tail -n +"$((N+1))" "$FAKE_LOG"; }
mark() { N="$(wc -l < "$FAKE_LOG" | tr -d ' ')"; }
SANDBOX=none; command -v sandbox-exec >/dev/null 2>&1 && SANDBOX=sandbox-exec

echo "== DIFFERS, and the neutral checkouts =="
mark
pr diff abc123 '. src/sum.sh; sum 2 3'; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/diff.json" verdict)" = DIFFERS ] && [ "$(field "$T/diff.json" before out)" = -1 ] && [ "$(field "$T/diff.json" after out)" = 5 ] \
  && ok "the probe exits 0 and finds that before prints -1 and after prints 5" || bad "diff: rc=$rc $(head -c 600 "$T/diff.json") $(tail -n 3 "$T/diff.err")"
[ "$(field "$T/diff.json" reason)" = "the stdout differ" ] && [ "$(field "$T/diff.json" before rc)" = 0 ] && [ "$(field "$T/diff.json" after rc)" = 0 ] \
  && ok "the reason names stdout, and both sides exit 0" || bad "diff reason: $(field "$T/diff.json" reason)"
[ "$(field "$T/diff.json" sandbox)" = "$SANDBOX" ] && ok "the JSON names the sandbox the host has: $SANDBOX" || bad "sandbox: $(field "$T/diff.json" sandbox), host $SANDBOX"
for side in before after; do
  co="$T/diff/$side"
  [ ! -e "$co/docs/plans/calc-41-plan.md" ] && [ ! -e "$co/docs/plans/calc-41-decisions.md" ] && [ -z "$(find "$co" -name ticket.md -not -path '*/.git/*')" ] \
    && ok "$side holds no plan file, record or ticket" || bad "$side tree: $(find "$co" -path '*/.git' -prune -o -type f -print | tr '\n' ' ')"
  subjects="$(git -C "$co" log --format=%s)"
  grep -qxF 'fix: sum adds its arguments' <<<"$subjects" && bad "$side carries the case's commit subject" || ok "no commit subject of $side is the case's commit subject"
  grep -q 41 <<<"$subjects$(git -C "$co" branch --format='%(refname:short)')" && bad "$side names the issue: $subjects" || ok "no subject or branch of $side names the issue number"
  [ "$(git -C "$co" rev-parse --abbrev-ref HEAD)" = "$side" ] && [ -z "$(git -C "$co" remote)" ] && [ ! -e "$co/.git/FETCH_HEAD" ] \
    && ok "$side is on branch $side, with no remote and no FETCH_HEAD" || bad "$side branch: $(git -C "$co" rev-parse --abbrev-ref HEAD) remote [$(git -C "$co" remote)]"
  [ -f "$co/.claude/second-shift/review-context.md" ] && [ -z "$(git -C "$co" status --porcelain)" ] && [ -d "$co/node_modules" ] \
    && ok "$side keeps review-context.md, has its own node_modules, and git lists no new file" || bad "$side status: $(git -C "$co" status --porcelain | tr '\n' '|')"
done
[ "$(git -C "$T/diff/after" show --name-only --format= HEAD)" = src/sum.sh ] && [ "$(git -C "$T/diff/before" rev-list --count HEAD)" = 2 ] \
  && ok "after's change commit holds src/sum.sh alone, and before is the base and the overlay" || bad "after commit: $(git -C "$T/diff/after" show --name-only --format= HEAD | tr '\n' ' ')"
[ "$(log_since | tr '\n' '|')" = "npm before ci miss|npm after ci hit|" ] && [ "$(field "$T/diff.json" lockfile)" = committed ] \
  && ok "each side runs npm ci from the committed lockfile, and after reuses the cache before filled" || bad "npm calls: $(log_since | tr '\n' '|') lockfile=$(field "$T/diff.json" lockfile)"

echo "== DIFFERS on the exit code =="
pr rc abc123 '. src/sum.sh; [ "$(sum 2 3)" = 5 ]'
[ "$(field "$T/rc.json" verdict)" = DIFFERS ] && [ "$(field "$T/rc.json" before rc)" = 1 ] && [ "$(field "$T/rc.json" after rc)" = 0 ] && [ "$(field "$T/rc.json" reason)" = "the exit code differ" ] \
  && ok "an exit code that differs alone is DIFFERS" || bad "rc: $(head -c 600 "$T/rc.json")"

echo "== SAME after normalization, with a probe dir =="
mkdir -p "$T/pd"; printf 'hello\n' > "$T/pd/input"
mark
pr same abc123 'pwd; echo "Time: 0.$RANDOM s"; cat "$PROBE_DIR/input"; . src/sum.sh; sum 3 0; echo "at $PWD" >&2' --dir "$T/pd"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/same.json" verdict)" = SAME ] && [ "$(field "$T/same.json" reason)" = "" ] \
  && ok "outputs that differ only in the checkout root and a timing line are SAME" || bad "same: rc=$rc $(head -c 800 "$T/same.json") $(tail -n 3 "$T/same.err")"
grep -q '/before$' <<<"$(field "$T/same.json" before out)" && grep -q '/after$' <<<"$(field "$T/same.json" after out)" && grep -q '^hello$' <<<"$(field "$T/same.json" after out)" \
  && ok "the JSON keeps the raw outputs, and the command read \$PROBE_DIR" || bad "raw out: $(field "$T/same.json" before out | tr '\n' '|')"
[ "$(find "$T/pd" -mindepth 1)" = "$T/pd/input" ] && [ -z "$(git -C "$T/same/before" status --porcelain)$(git -C "$T/same/after" status --porcelain)" ] \
  && ok "the probe dir and both checkouts gain no file" || bad "probe dir: $(find "$T/pd" -mindepth 1 | tr '\n' ' ')"
[ "$(log_since | tr '\n' '|')" = "npm before ci hit|npm after ci hit|" ] \
  && ok "a second probe on the same upstream and base reuses the cached install" || bad "npm calls: $(log_since | tr '\n' '|')"

echo "== UNPROVEN =="
start="$(date +%s)"
pr slow abc123 'sleep 30' --timeout 1; rc=$?
took=$(( $(date +%s) - start ))
[ "$rc" -eq 0 ] && [ "$(field "$T/slow.json" verdict)" = UNPROVEN ] && grep -q 'ran past its timeout' <<<"$(field "$T/slow.json" reason)" && [ "$took" -lt 25 ] \
  && ok "a side that runs past --timeout is UNPROVEN, and the probe stops it (${took} s)" || bad "timeout: rc=$rc took=$took $(head -c 600 "$T/slow.json")"
FAKE_NPM_FAIL=1 pr fail abc123 'true'; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/fail.json" verdict)" = UNPROVEN ] && grep -q '^the npm install in before exited 1: npm ERR! fake failure' <<<"$(field "$T/fail.json" reason)" && [ "$(field "$T/fail.json" before)" = None ] \
  && ok "a failed install is UNPROVEN, with the install's output in the reason" || bad "failed install: rc=$rc $(head -c 600 "$T/fail.json")"
pr stale bad444 'true'; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/stale.json" verdict)" = UNPROVEN ] && grep -q '^the patch does not apply to the base' <<<"$(field "$T/stale.json" reason)" \
  && ok "a patch that does not apply is UNPROVEN" || bad "stale patch: rc=$rc $(head -c 600 "$T/stale.json")"

echo "== an npm base with no lockfile =="
mark
pr loose1 loo111 'cat package-lock.json'
[ "$(log_since | tr '\n' '|')" = "npm before install miss|npm after ci hit|" ] && [ "$(field "$T/loose1.json" lockfile)" = generated ] && [ "$(field "$T/loose1.json" verdict)" = SAME ] \
  && ok "before installs unpinned, and after installs from the lockfile before generated" || bad "loose: $(log_since | tr '\n' '|') $(head -c 400 "$T/loose1.json")"
[ -z "$(git -C "$T/loose1/before" status --porcelain)$(git -C "$T/loose1/after" status --porcelain)" ] \
  && ok "git lists neither side's generated lockfile" || bad "loose status: $(git -C "$T/loose1/before" status --porcelain | tr '\n' '|')"
mark
pr loose2 loo111 'true'
[ "$(log_since | tr '\n' '|')" = "npm before ci hit|npm after ci hit|" ] && [ "$(field "$T/loose2.json" lockfile)" = generated ] \
  && ok "a later probe on the base pins both sides to the generated lockfile" || bad "loose again: $(log_since | tr '\n' '|')"

echo "== pnpm and yarn through corepack =="
mark
pr web web222 'cat dist/out'
store="$T/clones/acme__web.probe/$WEB/pnpm-store"
expect="corepack before pnpm install --frozen-lockfile store=$store|corepack before pnpm run build store=$store|corepack after pnpm install --frozen-lockfile store=$store|corepack after pnpm run build store=$store|"
calls="$(log_since)"
[ "$(log_since | sed 's/ yarn=.*//' | tr '\n' '|')" = "$expect" ] && ! grep -q '^npm ' <<<"$calls" \
  && ok "a pnpm base installs through corepack with a frozen lockfile, and probe.json's setup runs after each side's install" || bad "pnpm calls: $(tr '\n' '|' <<<"$calls")"
grep -q 'prompt=0$' <<<"$calls" && ok "corepack runs with its download prompt off" || bad "prompt: $(log_since | head -n 1)"
[ "$(field "$T/web.json" verdict)" = SAME ] && [ "$(field "$T/web.json" after out)" = built ] && [ -z "$(git -C "$T/web/after" status --porcelain)" ] \
  && ok "the command sees the setup's output in both sides" || bad "web: $(head -c 600 "$T/web.json") $(tail -n 3 "$T/web.err")"
mark
pr yarn yar333 'true'
[ "$(log_since | sed 's/ store=.*//' | tr '\n' '|')" = "corepack before yarn install --immutable|corepack after yarn install --immutable|" ] \
  && grep -q "yarn=$T/clones/acme__yarny.probe/$YARNY/yarn " <<<"$(log_since | head -n 1)" && [ "$(field "$T/yarn.json" verdict)" = SAME ] \
  && ok "a yarn base installs through corepack with --immutable, and its cache sits beside the bare clones" || bad "yarn calls: $(log_since | tr '\n' '|')"

if [ "$SANDBOX" = sandbox-exec ]; then
  echo "== the sandbox =="
  pr net abc123 'python3 -c "import socket; socket.socket().bind((\"127.0.0.1\", 0))" && echo net-ok'
  [ "$(field "$T/net.json" verdict)" = SAME ] && [ "$(field "$T/net.json" before rc)" != 0 ] && ! grep -q net-ok "$T/net.json" \
    && ok "the command cannot open a socket under sandbox-exec" || bad "net: $(head -c 600 "$T/net.json")"
fi

echo "== usage errors =="
pr none zzz999 'true'; rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$T/none" ] && ok "an unknown case exits non-zero and builds nothing" || bad "unknown case: rc=$rc"
PATH="$T/fakebin:$PATH" python3 "$HERE/planted.py" --root "$R" probe abc123 > /dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a probe with no --cmd exits 2" || bad "no --cmd: rc=$rc"
pr diff abc123 'true'; rc=$?
[ "$rc" -ne 0 ] && grep -q 'already exists' "$T/diff.err" && ok "a --dest that exists exits non-zero" || bad "existing dest: rc=$rc $(cat "$T/diff.err")"

echo "probe-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
