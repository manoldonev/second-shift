#!/usr/bin/env bash
# mutation-sweep-selftest.sh — companion suite for tools/mutation-sweep.sh.
#
# Deliberately IN-GLOB (unlike the harness it tests): CLAUDE.md's coverage rule exempts
# excluded from the *glob*, not from *coverage*. Being in-glob also runs
# this on the macOS lane's stock bash 3.2, which is what actually enforces the harness's
# bash-3.2-clean claim.
#
# WHY PER-TOOL FIXTURE CASES RATHER THAN A SCENARIO (CLAUDE.md's scenario-first rule):
# the invariants here are repo-level TEST-INFRASTRUCTURE contracts — the sweep's exit
# semantics, its two mutant tiers, and the resolution rules over its TSV family.
# scenario-liveness-selftest.sh composes dev-pipeline VERDICT PATHS (stage gates reaching
# a terminal write); the mutation sweep touches none of them and is never invoked from a
# pipeline stage, so no scenario there covers this and extending it would bolt an
# unrelated harness onto the pipeline composition suite. The rule's real target — a
# component checked only against itself — is answered by cases (j)/(k), which bind the
# harness to the LIVE TREE rather than to its own fixtures.
#
# ENVIRONMENT PINNING IS LOAD-BEARING (D-8). This suite runs on BOTH CI lanes, where
# GITHUB_ACTIONS=1 is always set, RUNNER_OS is Linux on ubuntu and macOS on
# selftests-bash32, and SKIP_STRESS is unset on ubuntu and 1 on macOS. Inheriting that,
# the harness would enter enforcing mode and red the environment check on both lanes,
# failing the exit-0 cases for a reason unrelated to any mutant. Every invocation below
# therefore pins the environment explicitly via adv()/enf() and NEVER inherits the lane's.
#
# Exit code = number of failed cases (the repo-wide selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$HERE/mutation-sweep.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
FAILS=0

[[ -f "$SWEEP" ]] || { echo "[mutation-sweep-selftest] FATAL: $SWEEP missing"; exit 99; }

ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; FAILS=$((FAILS + 1)); }

TMPROOT="$(mktemp -d -t mutation-sweep-selftest.XXXXXX)" || exit 99
trap 'rm -rf "$TMPROOT"' EXIT

# THE VERDICT CACHE IS OFF BY DEFAULT HERE, and that is load-bearing rather than tidy. The
# cache is per-MACHINE and lives outside any checkout, so an inheriting run would (a) write
# the operator's real cache from fixture verdicts and (b) — much worse — READ it. Fixture
# guards are byte-identical across cases by construction (`make_fixture` emits one guard
# text), so a case that ran earlier under a different killer would serve its verdict to a
# later case and the later case would assert nothing. Cases that exercise the cache turn it
# on explicitly, in a directory under TMPROOT, via cch().
adv() { env -u GITHUB_ACTIONS -u RUNNER_OS -u SKIP_STRESS MUTATION_SWEEP_CACHE=0 "$@"; }
# Enforcing: the canonical environment, stated explicitly rather than inherited.
enf() { env GITHUB_ACTIONS=1 RUNNER_OS=Linux SKIP_STRESS=1 MUTATION_SWEEP_CACHE=0 "$@"; }
# Enforcing WITH the merge-time deferral bypass. NON-EXPORTING, like every other seam this
# suite drives: exported, the knob would reach the nested real sweeps the deferral cases run
# and silently re-answer the very assertions they exist to make.
nodefer() { env GITHUB_ACTIONS=1 RUNNER_OS=Linux SKIP_STRESS=1 MUTATION_SWEEP_CACHE=0 \
              MUTATION_SWEEP_NO_DEFER=1 "$@"; }
# Advisory WITH the cache live, in a named directory. $1 = cache dir, rest = command.
cch() {
  local d="$1"; shift
  env -u GITHUB_ACTIONS -u RUNNER_OS -u SKIP_STRESS \
    MUTATION_SWEEP_CACHE=1 MUTATION_SWEEP_CACHE_DIR="$d" "$@"
}
# The two counters every cache and early-exit case reads out of the run's own timing line.
computed() { printf '%s' "$1" | sed -n 's/.*— \([0-9][0-9]*\) verdict(s) computed.*/\1/p' | tail -1; }
served()   { printf '%s' "$1" | sed -n 's/.*computed by running a paired suite, \([0-9][0-9]*\) served.*/\1/p' | tail -1; }

# ---------------------------------------------------------------- fixture repo
# A git-initialized temp repo is required, not optional: the harness sandboxes with
# `git worktree add --detach HEAD`, so the fixture needs a real commit.
# $1 = dir, $2 = strong|weak killer.
make_fixture() {
  local dir="$1" killer="$2"
  mkdir -p "$dir/tools"
  cat > "$dir/guard.sh" <<'EOF'
#!/usr/bin/env bash
# fixture guard: rejects the literal string "bad".
if [[ "${1:-}" == "bad" ]]; then
  echo "violation"
  exit 1
fi
echo ok
exit 0
EOF
  # 755 like the real tree (107 of 110 tracked guards). The mode is load-bearing fixture
  # state: mutation application that replaces the guard's inode drops the exec bit, and
  # with core.fileMode=true that mode change alone defeats every `git diff --quiet`
  # byte-identity gate. At 644 there is no bit to lose, so (e) and (p) would pass here
  # while dark on every real guard.
  chmod 755 "$dir/guard.sh"
  if [[ "$killer" == "strong" ]]; then
    # Exercises the violation path, so a fail-open mutant (exit 1 -> exit 0) is caught.
    cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f=0
out="$(bash "$HERE/guard.sh" bad)"; rc=$?
[[ $rc -eq 1 ]] || f=$((f+1))
[[ "$out" == "violation" ]] || f=$((f+1))
out="$(bash "$HERE/guard.sh" good)"; rc=$?
[[ $rc -eq 0 ]] || f=$((f+1))
exit $f
EOF
  else
    # Only ever exercises the happy path — the boilerplate class this sweep exists to find.
    cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
  fi
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}

new_fixture() {
  local d="$TMPROOT/fx$RANDOM$RANDOM"
  make_fixture "$d" "$1"
  printf '%s' "$d"
}

# Fleet fixture for the PR-lane cap: $2 trivial guards, each with its own fast same-stem
# killer, all landing in a SECOND commit so `--base HEAD~1` puts every one of them in the
# PR diff. The guards deliberately contain no operator site (no `exit 1`), so a swept
# guard applies zero mutants and a many-guard PR-mode run stays cheap. A separate builder
# rather than a make_fixture parameter: the single-guard cases keep their exact shape.
make_fleet_fixture() {
  local dir="$1" n="$2" i=1
  mkdir -p "$dir/tools"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
  while [[ $i -le $n ]]; do
    printf '#!/usr/bin/env bash\necho ok\nexit 0\n' > "$dir/guard$i.sh"
    chmod 755 "$dir/guard$i.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/guard$i-selftest.sh"
    i=$((i + 1))
  done
  ( cd "$dir" \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm guards ) >/dev/null 2>&1
}

# Weak fleet for the shard/merge cases: $2 guards, each carrying exactly one fail-open
# site behind a happy-path-only killer, so every guard contributes exactly one SURVIVOR —
# which is what makes a merged seed baseline's completeness assertable per guard.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_weak_fleet() {
  local dir="$1" n="$2" i=1
  mkdir -p "$dir/tools"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  while [[ $i -le $n ]]; do
    printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "bad" ]]; then\n  exit 1\nfi\necho ok\n' > "$dir/guard$i.sh"
    chmod 755 "$dir/guard$i.sh"
    { printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
      printf 'out="$(bash "$H/guard%s.sh" good)"\n[[ "$out" == ok ]] || exit 1\nexit 0\n' "$i"
    } > "$dir/guard$i-selftest.sh"
    i=$((i + 1))
  done
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}


# ------------------------------------------------- observation fixtures (pool cases)
# What the pool DID, recorded by the killers themselves. A fixture that only compares two
# reports cannot tell a working pool from one that silently degraded to a single worker, so
# these suites write down how many siblings were live while they ran and which sandbox they
# ran in — and the pool cases assert those BEFORE they assert any equivalence.
obs_reset() {
  rm -rf "$1" 2>/dev/null
  mkdir -p "$1"
}
obs_max() { # highest concurrent-killer count observed, 0 if nothing ran
  local m; m="$(sort -n "$1/observed" 2>/dev/null | tail -1 | tr -d ' ')"
  printf '%s' "${m:-0}"
}
obs_sandboxes() { sort -u "$1/sandboxes" 2>/dev/null | grep -c ''; }
obs_count() { # lines in a named marker file, 0 when it was never created
  [[ -f "$1/$2" ]] || { printf '0'; return 0; }
  grep -c '' "$1/$2"
}

# $2 guards, each with a WEAK same-stem killer (happy path only), so every guard yields
# exactly one SURVIVING fail-open mutant and the survivor set is fully determined.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_obs_fleet() {
  local dir="$1" n="$2" obs="$3" i=1
  mkdir -p "$dir/tools" "$obs"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  while [[ $i -le $n ]]; do
    printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "bad" ]]; then\n  exit 1\nfi\necho ok\n' > "$dir/guard$i.sh"
    chmod 755 "$dir/guard$i.sh"
    { printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
      printf 'OBS=%s\n' "$obs"
      printf 'mkdir -p "$OBS"\n: > "$OBS/live.$$"\nsleep 1\n'
      printf 'ls "$OBS" | grep -c "^live\\." >> "$OBS/observed"\n'
      printf 'rm -f "$OBS/live.$$"\n'
      printf 'echo "$H" >> "$OBS/sandboxes"\n'
      printf 'out="$(bash "$H/guard%s.sh" good)"\n[[ "$out" == ok ]] || exit 1\nexit 0\n' "$i"
    } > "$dir/guard$i-selftest.sh"
    i=$((i + 1))
  done
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}

# One guard, one fail-open site, and a killer shaped to exercise ONE early-exit question.
#   first — the FAIL: lands on the first case, then the suite would run for seconds more
#   last  — the FAIL: lands after every other case, so early exit only cuts the tail
#   noisy — the suite prints the pattern while PASSING, which is the shape that would make
#           early exit fabricate a kill if eligibility were assumed rather than derived
# Every variant appends to marker files under $3, so "did the killer run to completion?" is
# a count rather than a stopwatch reading.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_early_fixture() {
  local dir="$1" mode="$2" obs="$3"
  mkdir -p "$dir/tools" "$obs"
  printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "bad" ]]; then\n  exit 1\nfi\necho ok\n' > "$dir/guard.sh"
  chmod 755 "$dir/guard.sh"
  {
    printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
    printf 'OBS=%s\nmkdir -p "$OBS"\n' "$obs"
    case "$mode" in
      first)
        printf 'rc=0; bash "$H/guard.sh" bad >/dev/null 2>&1 || rc=$?\n'
        printf '[[ $rc -eq 1 ]] || echo "  FAIL: guard no longer rejects bad" >&2\n'
        printf 'sleep 2\n'
        printf 'echo x >> "$OBS/completed"\n'
        printf '[[ $rc -eq 1 ]] || exit 1\nexit 0\n' ;;
      last)
        printf 'rc=0; bash "$H/guard.sh" bad >/dev/null 2>&1 || rc=$?\n'
        printf 'out="$(bash "$H/guard.sh" good)"\n[[ "$out" == ok ]] || exit 1\n'
        printf 'sleep 1\n'
        printf 'echo x >> "$OBS/reached"\n'
        printf '[[ $rc -eq 1 ]] || echo "  FAIL: guard no longer rejects bad" >&2\n'
        printf 'sleep 2\n'
        printf 'echo x >> "$OBS/completed"\n'
        printf '[[ $rc -eq 1 ]] || exit 1\nexit 0\n' ;;
      *)
        printf 'echo "  FAIL: (fixture prose, not a verdict)"\n'
        printf 'sleep 3\n'
        printf 'out="$(bash "$H/guard.sh" good)"\n[[ "$out" == ok ]] || exit 1\nexit 0\n' ;;
    esac
  } > "$dir/guard-selftest.sh"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}

# A guard carrying the repo's EOF-tolerant read idiom VERBATIM, so `cmp-z` at ordinal 1
# produces the mutant that spins at 100% CPU. Shared by (z), which asserts the sweep does
# not hang on it, and (ah), which asserts the reap path still reclaims its disk.
make_spin_fixture() {
  local dir="$1"
  mkdir -p "$dir/tools"
  cat > "$dir/guard.sh" <<'EOF'
#!/usr/bin/env bash
# Carries the repo's EOF-tolerant read idiom verbatim — the real mutation site.
while IFS= read -r line || [[ -n "$line" ]]; do
  :
done
echo ok
exit 0
EOF
  chmod 755 "$dir/guard.sh"
  cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" </dev/null)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
  printf '# fixture operators\ncmp-z\t-z |-n \ts/-z /__MUT__/g; s/-n /-z /g; s/__MUT__/-n /g\n' \
    > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm spin ) >/dev/null 2>&1
}
# One guard, one fail-open site, and a killer that is deterministically flaky AGAINST THE
# MUTANT. It always passes on the UNMUTATED guard, so the precheck is honest; on the mutated
# guard it scores the FIRST observation green and every later one red.
#
# That reproduces the pool's fabricated survivor with no race in it. The race itself is
# un-isolated and so cannot be driven directly; what IS drivable is the MECHANISM the fix
# rests on — the sweep observes a mutant twice, once through the pool and once through the
# serial oracle, and the two observations are allowed to disagree. A killer whose two answers
# differ by construction puts the harness in exactly that state on every run, on every
# machine. $2 is an absolute observation dir OUTSIDE the fixture, because every sandbox is a
# fresh `git worktree add` and a marker written inside one would not survive to the next.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURE's code, not ours
make_flaky_fixture() {
  local dir="$1" obs="$2"
  mkdir -p "$dir/tools" "$obs"
  printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "bad" ]]; then\n  exit 1\nfi\necho ok\n' > "$dir/guard.sh"
  chmod 755 "$dir/guard.sh"
  { printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
    printf 'OBS=%s\nmkdir -p "$OBS"\n' "$obs"
    printf 'rc=0; bash "$H/guard.sh" bad >/dev/null 2>&1 || rc=$?\n'
    printf '[[ $rc -ne 0 ]] && exit 0\n'
    printf 'echo x >> "$OBS/mutrun"\n'
    printf 'n="$(grep -c "" "$OBS/mutrun")"\n'
    printf '[[ "$n" -le 1 ]] && exit 0\n'
    printf 'exit 1\n'
  } > "$dir/guard-selftest.sh"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm flaky ) >/dev/null 2>&1
}

# Two guards on ONE operator, differing only in how many sites they carry: `over.sh` has
# five and `under.sh` has two, against the default K_BUDGET of 2. That is the whole
# experiment — the pair differs in nothing else, so a difference in the report's
# sites_beyond_budget column can only be the budget. Both killers exercise every reject
# site, so every mutant the budget DOES allow is killed and the run's exit contract stays
# out of the way of the column assertion.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURE's code, not ours
make_budget_fixture() {
  local dir="$1" g args
  mkdir -p "$dir/tools"
  { printf '#!/usr/bin/env bash\n# fixture guard: five reject sites -> five `fail-open` ordinals.\n'
    printf 'case "${1:-}" in\n'
    printf '  a) exit 1 ;;\n  b) exit 1 ;;\n  c) exit 1 ;;\n  d) exit 1 ;;\n  e) exit 1 ;;\n'
    printf 'esac\necho ok\nexit 0\n'
  } > "$dir/over.sh"
  { printf '#!/usr/bin/env bash\n# fixture guard: two reject sites, exactly the budget.\n'
    printf 'case "${1:-}" in\n'
    printf '  a) exit 1 ;;\n  b) exit 1 ;;\n'
    printf 'esac\necho ok\nexit 0\n'
  } > "$dir/under.sh"
  chmod 755 "$dir/over.sh" "$dir/under.sh"
  for g in over under; do
    case "$g" in over) args="a b c d e" ;; *) args="a b" ;; esac
    { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nf=0\n'
      printf 'for a in %s; do\n' "$args"
      printf '  bash "$HERE/%s.sh" "$a" >/dev/null 2>&1 && f=$((f+1))\ndone\n' "$g"
      printf 'out="$(bash "$HERE/%s.sh" good)"\n' "$g"
      printf '[[ "$out" == "ok" ]] || f=$((f+1))\nexit $f\n'
    } > "$dir/$g-selftest.sh"
  done
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm budget ) >/dev/null 2>&1
}

# Two guards that collide through the SANDBOX rather than through each other, carrying the
# REAL `default` operator row verbatim — because the collision is a property of that
# alphabet: every guard it mutates receives the SAME placeholder token, so the token is a
# shared namespace on disk. `a-dirtier.sh` mutates into `mkdir -p __MUTANT_DEFAULT__` and is
# correctly KILLED, leaving the directory behind untracked; `b-victim.sh` mutates into
# `mktemp __MUTANT_DEFAULT__/f.XXXXXX`, which fails — and is therefore killed — only while
# that directory does NOT exist. Swept in that order in one sandbox, the second verdict is
# a fact about the first mutant's litter rather than about the guard.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_debris_fixture() {
  local dir="$1"
  mkdir -p "$dir/tools" "$dir/victim-tmp"
  # Exactly one site each. The prose restriction this fixture used to carry — that neither
  # guard may name the mutated shape in a comment, because such a comment took ordinal 1 and
  # survived unkillably — is retired: comments no longer enumerate (see case (am)). The
  # one-site-each shape is kept because the case is about sandbox litter ordering, not sites.
  { printf '#!/usr/bin/env bash\n# fixture guard: names a directory by expansion fallback, then creates it.\n'
    printf 'cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1\n'
    printf 'D="${DIRT_DIR:-dirt-scratch}"\nmkdir -p "$D"\necho "$D"\n'
  } > "$dir/a-dirtier.sh"
  { printf '#!/usr/bin/env bash\n# fixture guard: scratch file under a directory that must ALREADY exist.\n'
    printf 'cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1\n'
    printf 'f="$(mktemp "${VICTIM_TMP:-victim-tmp}/f.XXXXXX")" || exit 1\nrm -f "$f"\necho ok\n'
  } > "$dir/b-victim.sh"
  chmod 755 "$dir/a-dirtier.sh" "$dir/b-victim.sh"
  { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
    printf 'out="$(bash "$HERE/a-dirtier.sh")" || exit 1\n'
    printf '[[ "$out" == "dirt-scratch" ]] || exit 1\nexit 0\n'
  } > "$dir/a-dirtier-selftest.sh"
  { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
    printf 'out="$(bash "$HERE/b-victim.sh")" || exit 1\n'
    printf '[[ "$out" == "ok" ]] || exit 1\nexit 0\n'
  } > "$dir/b-victim-selftest.sh"
  # git cannot track an empty directory, and the victim's unmutated path needs a real one.
  : > "$dir/victim-tmp/.keep"
  # The production `default` row, byte-for-byte. A paraphrase here would let the fixture
  # keep passing while the shipped alphabet drifted into a different shared token.
  { printf '# fixture operators\n'
    printf '%s\t%s\t%s\n' 'default' '\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\}' \
      's/(\$\{[A-Za-z_][A-Za-z0-9_]*:-)[^}]*\}/\1__MUTANT_DEFAULT__}/'
  } > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm debris ) >/dev/null 2>&1
}

# Three guards that differ ONLY in how comments and code interleave for one operator, which
# is what makes the comparison a measurement rather than an anecdote.
#   cg.sh  comment first, then TWO code sites — one the killer exercises, one it does not.
#   co.sh  a single matched line, and it is a comment.
#   cn.sh  no matched line at all.
# The cg.sh shape is the discriminator. Its expected survivor is the SECOND enumerated site,
# and each wrong implementation makes that phrase name a different LINE: enumerating comments
# makes the comment the first enumerated site, so the k=2 window holds the comment and the
# first code line and the second code line is never applied; excluding comments with a
# `continue` INSIDE the mutation loop leaves the enumerated list three long, so the second
# enumerated site is the first code line while the actual survivor is the second. Only
# filtering the matched-line list before anything is counted makes "second enumerated site"
# and "the surviving code line" the same site. An assertion on mutants_applied alone cannot
# tell those apart, which is why the id is what is asserted. The killed site carries the other
# half: a comment flip is unkillable by construction, so the first site being KILLED is what
# proves the first site is the code line.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_comment_fixture() {
  local dir="$1" g
  mkdir -p "$dir/tools"
  { printf '#!/usr/bin/env bash\n'
    printf '# fixture guard: THIS PROSE LINE is the first line the operator matches - it says exit 1.\n'
    printf 'case "${1:-}" in\n'
    printf '  bad)  echo violation; exit 1 ;;\n'
    printf '  dark) exit 1 ;;\n'
    printf 'esac\necho ok\nexit 0\n'
  } > "$dir/cg.sh"
  { printf '#!/usr/bin/env bash\n'
    printf '# fixture guard: the only mention of exit 1 in this file is this prose line.\n'
    printf 'echo ok\n'
  } > "$dir/co.sh"
  { printf '#!/usr/bin/env bash\n'
    printf '# fixture guard: nothing here matches the operator at all.\n'
    printf 'echo ok\n'
  } > "$dir/cn.sh"
  chmod 755 "$dir/cg.sh" "$dir/co.sh" "$dir/cn.sh"
  # cg's killer exercises `bad` and the happy path, never `dark` — so the first code site is
  # killed and the second survives, in one run, with no second guard needed.
  { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nf=0\n'
    printf 'out="$(bash "$HERE/cg.sh" bad)"; rc=$?\n'
    printf '[[ $rc -eq 1 ]] || f=$((f+1))\n'
    printf '[[ "$out" == "violation" ]] || f=$((f+1))\n'
    printf 'out="$(bash "$HERE/cg.sh" good)"; rc=$?\n'
    printf '[[ $rc -eq 0 ]] || f=$((f+1))\n'
    printf '[[ "$out" == "ok" ]] || f=$((f+1))\nexit $f\n'
  } > "$dir/cg-selftest.sh"
  for g in co cn; do
    { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
      printf 'out="$(bash "$HERE/%s.sh")" || exit 1\n' "$g"
      printf '[[ "$out" == "ok" ]] || exit 1\nexit 0\n'
    } > "$dir/$g-selftest.sh"
  done
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm comments ) >/dev/null 2>&1
}

# guard,killed,survived,survivor_ids for one row of a --report TSV.
report_row() { awk -F'\t' -v g="$2" '$1==g {print $5"/"$6"/"$7; exit}' "$1"; }

# The sites_beyond_budget cell for one row. Read through the same positional discipline as
# report_row: appending the column must leave $5/$6/$7 exactly where they were.
report_beyond() { awk -F'\t' -v g="$2" '$1==g {print $8; exit}' "$1"; }

# The sites_comment_only cell, and mutants_applied. Same discipline: each new column lands
# on the END of the row, so $4 and $5/$6/$7 never move.
report_comment_only() { awk -F'\t' -v g="$2" '$1==g {print $9; exit}' "$1"; }
report_applied()      { awk -F'\t' -v g="$2" '$1==g {print $4; exit}' "$1"; }

baseline_with() { # $1=dir, rest = survivor ids
  local d="$1"; shift
  { echo "# environment: ubuntu-latest SKIP_STRESS=1"
    echo "# k=2"
    echo "# keying: content-v1"
    for s in "$@"; do printf '%s\tseeded\n' "$s"; done
  } > "$d/tools/mutation-baseline.tsv"
}

# A fixture site's survivor id, DERIVED by asking production for it. Generic ids are keyed by
# the matched line's content, so a positional literal (`guard.sh::fail-open::1`) is no longer
# an id at all. The two ways to get one here are to compute the sha in this file — which
# re-implements the key function inside its own test suite, the mirror-harness shape CLAUDE.md
# forbids, since a copy cannot fail on a production edit — or to ask the harness. This asks:
# `--emit-site-keys` enumerates and prints `<guard><TAB><operator><TAB><ordinal><TAB><key>`
# while SCORING NOTHING, so what comes back is a derivation and not a verdict captured from a
# run and fed back as its own expectation.
sid_for() { # $1=fixture dir, $2=guard relpath, $3=operator id, $4=1-based ordinal
  ( cd "$1" && adv bash "$SWEEP" --emit-site-keys 2>/dev/null ) \
    | awk -F'\t' -v g="$2" -v o="$3" -v n="$4" '$1==g && $2==o && $3==n {print g"::"o"::"$4; exit}'
}

# Commit a fixture edit so the sandboxed sweep (which checks out HEAD) can see it.
fx_commit() {
  ( cd "$1" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm "${2:-edit}" ) >/dev/null 2>&1
}

# The survivor_ids cell of a report row, as a sorted, newline-separated set.
survivor_set() { # $1=report tsv, $2=guard
  awk -F'\t' -v g="$2" '$1==g {print $7; exit}' "$1" | tr ',' '\n' | grep -v '^$' | sort
}

# ============================================================= fixture cases

echo "(a) green direction — strong killer catches the mutant"
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'killed=1 survived=0' <<<"$OUT"; then
  ok "mutant killed, exit 0"
else
  bad "(a) expected killed=1 survived=0 and rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(b) red direction — weak killer, empty baseline, survivor is red"
FX="$(new_fixture weak)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'baseline-absent survivor' <<<"$OUT"; then
  ok "baseline-absent survivor is red"
else
  bad "(b) expected rc=1 + baseline-absent survivor; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(c) baseline suppression — the same survivor listed is report-only"
FX="$(new_fixture weak)"
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]]; then
  ok "listed survivor does not red the build"
else
  bad "(c) expected rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(d) shrink warns — killed-but-listed, and a listed guard that no longer resolves"
FX="$(new_fixture strong)"
# The second id's guard does not exist, which is the point of the row — nothing can derive a
# key for a file that is not there, so it carries a syntactically valid literal instead.
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)" 'gone/removed.sh::fail-open::000000000000'
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && grep -q 'now KILLED' <<<"$OUT" \
  && grep -q 'no longer resolves' <<<"$OUT"; then
  ok "both shrink conditions warn, neither reds"
else
  bad "(d) expected rc=0 + both warns; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(e) catalog anchor drift — a sed that leaves the file byte-identical is red"
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'drifted\tguard.sh\ts/__NEVER_PRESENT__/x/\tanchor that cannot match\n' >> "$FX/tools/mutation-catalog.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'catalog anchor drift' <<<"$OUT"; then
  ok "anchor drift is LOUD"
else
  bad "(e) expected rc=1 + catalog anchor drift; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(f) validity-failure asymmetry — catalog invalid is red, generic invalid is skipped"
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'invalid\tguard.sh\ts/^echo ok$/if/\tyields bash -n invalid output\n' >> "$FX/tools/mutation-catalog.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'catalog mutant is bash -n invalid' <<<"$OUT"; then
  ok "catalog invalid mutant is red"
else
  bad "(f1) expected rc=1 + catalog invalid; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'breaker\t^echo ok$\ts/echo ok/if/\n' >> "$FX/tools/mutation-operators.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'skip (bash -n invalid, harness artifact)' <<<"$OUT"; then
  ok "generic invalid mutant is skipped-and-logged, never red"
else
  bad "(f2) expected rc=0 + skipped harness artifact; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(g) unrunnable pair — a killer red on the UNMUTATED sandbox is infra red"
FX="$(new_fixture strong)"
baseline_with "$FX"
# Replace the killer outright — appending `exit 7` after its own `exit $f` would be
# unreachable and the case would silently pass for the wrong reason.
printf '#!/usr/bin/env bash\nexit 7\n' > "$FX/guard-selftest.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm break ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && grep -q 'unrunnable pair' <<<"$OUT" \
  && grep -q 'mutants_applied\|swept' <<<"$OUT" \
  && grep -q 'it produced no output' <<<"$OUT"; then
  ok "unrunnable pair is red and its mutants are not scored"
else
  bad "(g) expected rc=1 + unrunnable pair; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(g2) unrunnable pair — the suite's exit status and its own output reach the operator"
# Before this the red carried a reason string and nothing else, so a suite reaped by the OOM
# killer (rc=137 on a 2-core runner) and one with a genuinely failing case (rc=1) produced the
# identical line — the one distinction that decides whether the next move is a code fix or a
# capacity one. $KILLER_LOG is truncated by the next killer and deleted with $WORKDIR on exit,
# so the snapshot has to happen at failure time or there is nothing left to print. This killer
# TALKS before it fails, the way a real suite does; the needle is that the talking survives.
FX="$(new_fixture strong)"
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "diagnostic-needle: the fixture suite explaining itself"
exit 7
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm talk ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && grep -q 'unrunnable pair' <<<"$OUT" \
  && grep -q '(exit 7)' <<<"$OUT" \
  && grep -q 'diagnostic-needle' <<<"$OUT"; then
  ok "the red names the exit status and carries the suite's own output"
else
  bad "(g2) expected rc=1 + '(exit 7)' + the suite's output; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(g3) an unrunnable guard's baseline rows are undecidable, never 'now KILLED'"
# Reads (g2)'s run: that guard carries a baseline row and scored NOTHING, so the row is absent
# from TOTAL_SURVIVORS for the one reason that proves nothing — nothing ran. SWEEP_GUARDS is
# the ASSIGNED partition, fixed before the precheck, so the guard still counts as "swept" and
# the shrink warn used to read that absence as a kill. Obeying it drops a live survivor and
# reds the NEXT healthy run with exactly that row as a baseline-absent survivor.
if ! grep -q 'now KILLED' <<<"$OUT"; then
  ok "no 'now KILLED' warn for a guard whose pair never ran"
else
  bad "(g3) the unrunnable guard's baseline row was reported killed"; printf '%s\n' "$OUT" | grep 'now KILLED'
fi
# The silence above has to be accounted for, or it reads as "the rows are fine".
if grep -q 'undecidable this run' <<<"$OUT"; then
  ok "the red says the rows are undecidable, so the silence is accounted for"
else
  bad "(g3) the red did not account for the suppressed rows"; printf '%s\n' "$OUT" | tail -6
fi

echo "(g4) unrunnable pair — the FAILING CASES are named even when they scroll off the tail"
# #663. (g2) proves the snapshot survives; it does NOT prove the snapshot is USEFUL, because its
# needle is the last thing the fixture prints. A real suite reports each failure where it happens
# and keeps going, so on lean-gate-selftest.sh — 550+ cases — the two FAIL lines sat hundreds of
# lines above the end, and the blind `tail -40` showed forty PASSes and the summary on every
# nightly from 2026-08-20 on. The guard is the SEPARATION: this killer names its failing case
# FIRST and then buries it under more than PRE_LOG_LINES of passing chatter, so a tail-only
# diagnostic cannot show it and a matches-first one must.
#
# PLACED AFTER (g3), not between (g2) and it: (g3) asserts against (g2)'s $OUT, and a run
# inserted above it would silently re-point that assertion at a different fixture.
FX="$(new_fixture strong)"
baseline_with "$FX"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo "  FAIL: (needle-case) the case that actually failed"\n'
  # shellcheck disable=SC2016 # the $-expressions are the FIXTURE's code, not ours
  printf 'i=0; while [ $i -lt 60 ]; do echo "  PASS: filler $i"; i=$((i + 1)); done\n'
  printf 'echo "[fixture-selftest] 1 FAILURE(S)"\n'
  printf 'exit 1\n'
} > "$FX/guard-selftest.sh"
fx_commit "$FX" bury
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
# The tail arm is asserted alongside the match arm, so a change that swapped one blind window
# for another — matches only — fails here rather than passing as an improvement.
if [[ $RC -eq 1 ]] \
  && grep -q 'unrunnable pair' <<<"$OUT" \
  && grep -q 'needle-case' <<<"$OUT" \
  && grep -q 'PASS: filler 59' <<<"$OUT"; then
  ok "the red names the failing case though 60 passing lines buried it, and still carries the tail"
else
  bad "(g4) expected rc=1 + the buried FAIL case + the tail; got rc=$RC"; printf '%s\n' "$OUT" | tail -8
fi
# ...and a suite that DID name its case must not also be reported as naming none.
if grep -q 'no line matches' <<<"$OUT"; then
  bad "(g4b) a suite that named its failing case was reported as naming none"
else
  ok "the no-match note is withheld from a suite that named its case"
fi

echo "(g4c) a killer that fails without naming a case says so, rather than printing a bare tail"
# The other side of (g4b). Without this the operator cannot tell "the suite has no trigger
# lines" from "the diagnostic did not look", and the reaped-by-OOM class is exactly the one
# that produces no FAIL line at all.
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '#!/usr/bin/env bash\necho "quiet failure, no trigger line"\nexit 3\n' > "$FX/guard-selftest.sh"
fx_commit "$FX" quiet
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'no line matches' <<<"$OUT" && grep -q 'quiet failure' <<<"$OUT"; then
  ok "the red says no case was named, and still carries the suite's own output"
else
  bad "(g4c) expected rc=1 + the no-match note + the tail; got rc=$RC"; printf '%s\n' "$OUT" | tail -8
fi

echo "(h) baseline-missing — enforcing non-seed is red; seed mode is green with artifacts"
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'baseline-missing' <<<"$OUT"; then
  ok "absent baseline in an enforcing run is the named infra red"
else
  bad "(h1) expected rc=1 + baseline-missing; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
FX="$(new_fixture weak)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed \
        --baseline-out "$FX/seeded-baseline.tsv" --slow-out "$FX/seeded-slow.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && [[ -s "$FX/seeded-baseline.tsv" ]] \
  && grep -q '^# environment: ubuntu-latest SKIP_STRESS=1$' "$FX/seeded-baseline.tsv" \
  && grep -q '^# k=2$' "$FX/seeded-baseline.tsv" \
  && grep -q '^# keying: content-v1$' "$FX/seeded-baseline.tsv" \
  && grep -q "^$(sid_for "$FX" guard.sh fail-open 1)	" "$FX/seeded-baseline.tsv" \
  && [[ -s "$FX/seeded-slow.tsv" ]]; then
  ok "seed mode exits green and writes a headed, populated baseline + slow list"
else
  bad "(h2) seed mode did not produce the expected artifacts; rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(i) baseline-environment-mismatch — named red, never a survivor diff"
for probe in "RUNNER_OS=macOS SKIP_STRESS=1" "RUNNER_OS=Linux SKIP_STRESS=" "RUNNER_OS=Linux SKIP_STRESS=1 MUTATION_SWEEP_K=3"; do
  FX="$(new_fixture weak)"
  baseline_with "$FX"
  # shellcheck disable=SC2086 # probe is a deliberate space-separated VAR=VAL list
  OUT="$( cd "$FX" && env GITHUB_ACTIONS=1 $probe bash "$SWEEP" --mode full 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] \
    && grep -q 'baseline-environment-mismatch' <<<"$OUT" \
    && ! grep -q 'baseline-absent survivor' <<<"$OUT"; then
    ok "mismatch [$probe] reds as itself, survivors not compared"
  else
    bad "(i) [$probe] expected the named mismatch and NO survivor diff; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
  fi
done

echo "(l) PR mode — empty diff exits 0; slow / multi-suite guards defer visibly"
FX="$(new_fixture strong)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'nothing to sweep' <<<"$OUT"; then
  ok "zero touched guards exits 0 before any baseline resolution"
else
  bad "(l1) expected rc=0 + nothing to sweep; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
# The empty-diff exit must precede baseline resolution — prove it by removing the
# baseline entirely and keeping the enforcing environment. This is what keeps a
# doc-only PR (and the PR that first lands this harness) off the baseline-missing red.
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'baseline-missing' <<<"$OUT"; then
  ok "empty PR diff never reaches the baseline-missing check"
else
  bad "(l2) empty PR diff reded on a missing baseline; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
# Slow killer -> the guard defers wholesale rather than being swept against a reduced
# criterion (which would grade mutants more weakly than the baseline that produced them).
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '# fixture slow list\n./guard-selftest.sh\t42\t2026-07-29\n' > "$FX/tools/selftest-suite-timings.tsv"
# The commit must TOUCH THE GUARD, or the PR-mode diff selects nothing and the case
# passes vacuously on the empty-diff exit instead of exercising deferral.
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm slow ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'deferred-to-nightly' <<<"$OUT"; then
  ok "slow-suite guard defers with a visible report row"
else
  bad "(l3) expected a deferred-to-nightly row; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(l3b) #582 AC-1/AC-2 — an ALL-deferred PR run warns unmissably and annotates the check surface"
# This is the SAME fixture as (l3): one in-scope guard, and it defers. That makes it
# "every in-scope guard deferred" by construction (1/1), the exact scenario #582 fixes: a
# green PR run that graded nothing. RC stays 0 (this is not a red-build fix) but the run
# must say so loudly, distinct from the per-guard "defer ... -> merge-time sweep" info line already
# asserted above.
if [[ $RC -eq 0 ]] \
  && grep -q 'WARN: PR mode graded NOTHING: all 1 in-scope guard(s) deferred to the merge-time sweep, 0 swept' <<<"$OUT" \
  && grep -q 'reasons: slow suite: 1' <<<"$OUT" \
  && grep -q '^::warning::mutation-sweep: PR mode graded NOTHING' <<<"$OUT"; then
  ok "all-deferred run warns the count+reason and emits a check-surface annotation"
else
  bad "(l3b) expected the AC-1 WARN line and the AC-2 ::warning:: annotation; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(l4) slow-list drift is warned AT MEASUREMENT — the diagnosis outlives the timeout it diagnoses"
# A suite that grows past the threshold while absent from the list keeps its guard in the PR
# lane, where the cost lands on every mutant that makes the guard spin. That is how
# lean-gate-selftest.sh reached 143s against a 5s bar and took three PR runs with it, each
# reading only as "timed out after 15 minutes" — because a warn emitted in the report is not
# reached by a job that dies before the report. Hence the placement: the warn fires from the
# precheck, where the measurement is taken, not from finish().
FX="$(new_fixture strong)"
baseline_with "$FX"
# The precheck times the suite; make it measurably slow. 1.2s against a threshold of 1s
# clears the integer-second floor whichever side of a tick the two samples land on.
#
# AND COMMIT IT. The sweep sandboxes the fixture's HEAD, not its working tree, so an
# uncommitted `sleep` never reaches the suite that gets timed. Left uncommitted this case
# still passed — on the ~1s of incidental setup overhead — and a kill probe that made the
# warn unconditional then FAILED it, because that run happened to measure 0s. The sleep is
# what makes the measurement the case's own rather than the machine's.
printf 'sleep 1.2\n' | cat - "$FX/guard-selftest.sh" > "$FX/guard-selftest.sh.tmp"
mv "$FX/guard-selftest.sh.tmp" "$FX/guard-selftest.sh"
( cd "$FX" && git add -A \
  && git -c user.email=f@e.invalid -c user.name=f commit -qm 'slow the fixture suite' ) >/dev/null 2>&1
printf '# fixture slow list — deliberately EMPTY of the suite below\n' > "$FX/tools/selftest-suite-timings.tsv"
OUT="$( cd "$FX" && enf env MUTATION_SWEEP_SLOW_THRESHOLD_S=1 bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'slow-list drift: \./guard-selftest\.sh measured' <<<"$OUT"; then
  ok "an unlisted suite past the threshold warns, naming itself, without reding the run"
else
  bad "(l4) expected a slow-list drift warn naming ./guard-selftest.sh and rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
# PLACEMENT, WHICH IS THE WHOLE POINT — and the half a deletion probe cannot certify. Deleting
# the warn fails the assertion above, so that assertion is live for the warn's EXISTENCE; it
# passes unchanged on a warn RELOCATED into finish(), which is the one placement the fix
# exists to rule out. Ordering closes it: the precheck's own `pool:` line is the next thing
# the run prints, and finish() is 15s and a whole report later.
#
# The direction of the risk is safe. Warn is stderr and `pool:` is stdout, merged by 2>&1 —
# buffering can only DELAY the stdout line, never move it ahead of a write that has not
# happened yet. Here-string and not a pipe: this suite is `set -uo pipefail`, where piping a
# producer into an early-exiting `grep -q` scores a MATCH as a miss — grep leaves, the producer
# takes SIGPIPE, and pipefail reports the signal. (Spelled out rather than shown: the pipe form
# is enumerated as a fail-open site by scripts/check-fail-open-shapes.sh, which reads text and
# cannot tell a warning about the shape from a use of it.)
WLN="$(awk '/slow-list drift/{print NR; exit}' <<<"$OUT")"
PLN="$(awk '/\[mutation-sweep\] pool: [0-9]+ worker/{print NR; exit}' <<<"$OUT")"
if [[ -n "$WLN" && -n "$PLN" && "$WLN" -lt "$PLN" ]]; then
  ok "the warn precedes the pool, so a job killed by its own ceiling has already said why"
else
  bad "(l4) drift warn did not precede the pool line (warn=$WLN pool=$PLN)"; printf '%s\n' "$OUT" | tail -4
fi
# The summary prescribes a remedy, so it has to know which class it is summarizing. This run
# has exactly one warn and it is not a baseline row; an aggregate that says "shrink the
# baseline" here is pointing at a file that needs nothing.
if grep -q 'warning(s)' <<<"$OUT" && ! grep -q 'warning(s).*shrink the baseline' <<<"$OUT"; then
  ok "a non-baseline warn is summarized without prescribing the baseline"
else
  bad "(l4) the warning summary prescribed the baseline for a slow-list drift warn"; grep 'warning(s)' <<<"$OUT" | tail -2
fi
# CONTROL: the same fixture, the same sleep, the same threshold — only the row is added. A
# case that skipped this would pass on a warn keyed to duration alone, which would then fire
# on every listed suite forever and train the reader to ignore it.
printf '# fixture slow list\n./guard-selftest.sh\t2\t2026-08-14\n' > "$FX/tools/selftest-suite-timings.tsv"
OUT="$( cd "$FX" && enf env MUTATION_SWEEP_SLOW_THRESHOLD_S=1 bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'slow-list drift' <<<"$OUT"; then
  ok "the same suite, once listed, warns no more"
else
  bad "(l4) a LISTED suite still warned about drift; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(m) exclusions preempt pairing — a guard in BOTH files is a lint error, via the harness"
# Driven THROUGH mutation-sweep.sh, not re-checked in this file. Case (k) lints the
# committed TSVs directly, which is a data lint; asserting the harness's own red branch
# by re-implementing its condition here would be the mirror shape CLAUDE.md warns about —
# it could not fail on a harness edit. The real tree has no such guard, so without this
# fixture the branch has zero end-to-end coverage.
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '# fixture exclusions\nguard.sh\tdeliberately excluded\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\nguard.sh\t./guard-selftest.sh\tconflicting row\n' > "$FX/tools/mutation-pair-map.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'excluded AND carries pair-map rows' <<<"$OUT"; then
  ok "conflicting exclusion + pair-map rows is red"
else
  bad "(m) expected rc=1 + the conflict red; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(n) argument contract — bad invocations die loudly rather than sweeping something wrong"
FX="$(new_fixture strong)"
for args in "--mode bogus" "--mode pr" "--frobnicate" ""; do
  # shellcheck disable=SC2086 # args is a deliberate space-separated argv fragment
  OUT="$( cd "$FX" && adv bash "$SWEEP" $args 2>&1 )"; RC=$?
  if [[ $RC -eq 2 ]] && grep -q 'FATAL' <<<"$OUT"; then
    ok "rejects [${args:-<no args>}]"
  else
    bad "(n) [${args:-<no args>}] expected rc=2 + FATAL; got rc=$RC"
  fi
done

echo "(o) --report writes the TSV to the named path instead of stdout"
FX="$(new_fixture strong)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$FX/report.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && [[ -s "$FX/report.tsv" ]] \
  && head -1 "$FX/report.tsv" | grep -q '^guard	status	paired_selftest' \
  && grep -q '^guard\.sh	swept' "$FX/report.tsv" \
  && ! grep -q '^guard	status' <<<"$OUT"; then
  ok "report lands at the path and is kept off stdout"
else
  bad "(o) --report did not write the expected TSV; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(p) mode preservation — an -x-gated weak killer must not score false kills"
# Invariant: applying a mutant preserves the guard's file mode. Several real killers
# precondition-gate on `-x` before exercising anything (is-inert-diff-selftest.sh,
# audit-selftest.sh); if mutation application replaced the guard's inode, the lost exec
# bit would fail that gate for EVERY mutant and the sweep would report this deliberately
# weak (happy-path-only) suite as 100% killing — the exact inversion the harness exists
# to prevent. Correct behavior: the fail-open mutant SURVIVES. No liveness scenario
# covers this for the same reason as the header: the sweep composes no pipeline verdict
# path. Case (e) pins the catalog tier's byte-identity gate at real-tree mode; this one
# pins the generic tier's application site.
FX="$(new_fixture weak)"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -x "$HERE/guard.sh" ]; then
  echo "[self-test] FATAL: guard not executable" >&2
  exit 1
fi
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm xgate ) >/dev/null 2>&1
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && grep -q 'killed=0 survived=1' <<<"$OUT" \
  && grep -q 'baseline-absent survivor' <<<"$OUT"; then
  ok "survivor exposed — exec bit held through mutation application"
else
  bad "(p) expected killed=0 survived=1 + rc=1; a kill here means the mutant write stripped the exec bit; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(q) PR mode — a multi-killer union defers wholesale, never sweeps a partial union"
# Invariant: the PR lane sweeps a guard only when its kill set is a SINGLE fast suite. A
# two-killer union must defer wholesale: sweeping a reduced kill set would grade mutants
# under a weaker criterion than the one that produced the baseline (manufacturing false
# reds on a merge-blocking lane), and sweeping the full union blows the lane's time
# bound, since a surviving mutant runs every killer. Every other case gives kill_set_for
# exactly one killer, so without this one a mutant DELETING the union defer survives the
# whole suite. The LOOSENING direction (`-ne 1` -> `-ne 99`) is NOT killed here — every
# guard then defers, which this case still accepts — it is killed by (r)'s positive
# swept=6 assertion. The two cases cover that line jointly, in opposite directions:
# weakening (r) silently reopens the loosening direction. Deferral must also be VISIBLE:
# the report row carries deferred-to-nightly with the full '+'-joined union. No liveness
# scenario covers this for the header's reason: the sweep composes no pipeline verdict path.
FX="$(new_fixture strong)"
baseline_with "$FX"
# Second killer via the pair map — same-stem pairing plus one map row is the union shape.
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/second-killer-selftest.sh"
printf 'guard.sh\t./second-killer-selftest.sh\tsecond killer forms a two-suite union\n' >> "$FX/tools/mutation-pair-map.tsv"
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm union ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && grep -q 'multi-suite union (2 killers)' <<<"$OUT" \
  && grep -q 'guard\.sh	deferred-to-nightly	\./guard-selftest\.sh+\./second-killer-selftest\.sh' <<<"$OUT" \
  && ! grep -q 'guard\.sh	swept' <<<"$OUT"; then
  ok "two-killer guard defers with the full union visible in its report row"
else
  bad "(q) expected a wholesale defer with the '+'-joined union row and no sweep; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(r) PR mode — the fast-guard cap sweeps six, defers the seventh visibly"
# Invariant: the PR lane sweeps at most six fast guards per push — the bound that keeps
# the merge-blocking CI step inside its timeout — and the overflow guard defers with a
# visible report row rather than being dropped. Seven single-killer guards cross a cap of
# six; no other case sweeps more than one guard in PR mode, so without this one a mutant
# raising or removing the cap survives. The 6/1 split and the reason string deliberately
# pin the cap's value: a deliberate cap change must update this case in the same PR.
FX="$TMPROOT/fleet$RANDOM$RANDOM"
make_fleet_fixture "$FX" 7
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
SWEPT_N="$(printf '%s\n' "$OUT" | grep -c '	swept	')"
DEFER_N="$(printf '%s\n' "$OUT" | grep -c '	deferred-to-nightly	')"
if [[ $RC -eq 0 && "$SWEPT_N" -eq 6 && "$DEFER_N" -eq 1 ]] \
  && grep -q 'PR-lane cap (6 fast guards already swept)' <<<"$OUT"; then
  ok "cap swept 6 guards, deferred 1 with the cap named as the reason"
else
  bad "(r) expected swept=6 deferred=1 + the cap reason; got rc=$RC swept=$SWEPT_N deferred=$DEFER_N"; printf '%s\n' "$OUT" | tail -6
fi
# #582 AC-3 control — a PARTIAL defer (six swept, one deferred) must leave reporting
# unchanged: no all-deferred WARN, no check-surface annotation. Without this control a
# mutant that loosens the AC-1/AC-2 gate from "PR_SWEPT empty" to "any defer occurred"
# would fire on every capped push and (l3b) alone would not catch it.
if ! grep -q 'PR mode graded NOTHING' <<<"$OUT" && ! grep -q '^::warning::mutation-sweep:' <<<"$OUT"; then
  ok "a partial defer (6 swept, 1 deferred) triggers no all-deferred warn or annotation"
else
  bad "(r) a partial defer wrongly fired the all-deferred warn/annotation"; printf '%s\n' "$OUT" | tail -6
fi

echo "(r2) the merge-time bypass grades what the PR lane defers — all THREE reasons, not one"
# Invariant: MUTATION_SWEEP_NO_DEFER=1 disables the deferral decision WHOLESALE. All three
# reasons exist to protect the PR lane's TIME BOUND, which the merge-time lane does not have,
# so each must grade under the knob. Covering only one would leave a per-arm regression
# invisible: a bypass wired into the slow-suite arm alone still reads green on a slow-suite
# fixture while the cap and the union silently keep deferring, and the merge-time lane would
# then skip exactly the guards it exists to grade — the topology this ticket replaced.
#
# Each sub-case is the SAME FIXTURE as its knob-off twin above — (l3) slow suite, (q)
# multi-suite union, (r) fast-guard cap — so the pair isolates the knob as what moved the
# verdict rather than the fixture. Status is read out of the report's own column rather than
# grepped, so a row that changed shape cannot pass on a substring.
status_of() { printf '%s\n' "$2" | awk -F'\t' -v g="$1" '$1==g {print $2}' | tail -1; }
count_status() { printf '%s\n' "$2" | awk -F'\t' -v s="$1" '$2==s {c++} END {print c+0}'; }

# 1/3 — a slow paired suite. The PR lane defers it wholesale ((l3)); merge time grades it.
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '# fixture slow list\n./guard-selftest.sh\t42\t2026-07-29\n' > "$FX/tools/selftest-suite-timings.tsv"
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm slow ) >/dev/null 2>&1
OUT="$( cd "$FX" && nodefer bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 && "$(status_of guard.sh "$OUT")" == "swept" ]] \
  && [[ "$(count_status deferred-to-nightly "$OUT")" -eq 0 ]]; then
  ok "the bypass grades a slow-suite guard the PR lane defers"
else
  bad "(r2a) expected guard.sh swept and zero defer rows; got rc=$RC status='$(status_of guard.sh "$OUT")'"
  printf '%s\n' "$OUT" | tail -5
fi

# 2/3 — a multi-suite killer union. Grading under the FULL union is the same criterion that
# produced the baseline, which is why disabling this arm manufactures no false reds.
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/second-killer-selftest.sh"
printf 'guard.sh\t./second-killer-selftest.sh\tsecond killer forms a two-suite union\n' >> "$FX/tools/mutation-pair-map.tsv"
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm union ) >/dev/null 2>&1
OUT="$( cd "$FX" && nodefer bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 && "$(status_of guard.sh "$OUT")" == "swept" ]] \
  && [[ "$(count_status deferred-to-nightly "$OUT")" -eq 0 ]]; then
  ok "the bypass grades a two-killer union the PR lane defers"
else
  bad "(r2b) expected guard.sh swept and zero defer rows; got rc=$RC status='$(status_of guard.sh "$OUT")'"
  printf '%s\n' "$OUT" | tail -5
fi

# 3/3 — the fast-guard cap. Seven guards cross a cap of six; the seventh is deferred at PR
# time ((r)) and graded here. The 7/0 split pins the cap as bypassed rather than merely
# raised — a knob that only widened it would still defer at some N.
FX="$TMPROOT/nodefer-fleet$RANDOM$RANDOM"
make_fleet_fixture "$FX" 7
baseline_with "$FX"
OUT="$( cd "$FX" && nodefer bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
SWEPT_N="$(count_status swept "$OUT")"
DEFER_N="$(count_status deferred-to-nightly "$OUT")"
if [[ $RC -eq 0 && "$SWEPT_N" -eq 7 && "$DEFER_N" -eq 0 ]]; then
  ok "the bypass grades all seven guards, past the six-guard PR cap"
else
  bad "(r2c) expected swept=7 deferred=0; got rc=$RC swept=$SWEPT_N deferred=$DEFER_N"
  printf '%s\n' "$OUT" | tail -6
fi

# CONTROL — the knob is OFF by default. Without this, a mutant that inverted the test (making
# the bypass unconditional) would pass every assertion above while silently disarming the PR
# lane's time bound, and (l3)/(q)/(r) would be the only thing standing between that and a
# merge-blocking job that runs the whole universe. Same fleet fixture, no knob.
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 && "$(count_status swept "$OUT")" -eq 6 && "$(count_status deferred-to-nightly "$OUT")" -eq 1 ]]; then
  ok "with the knob unset the same fixture still defers — the bypass is opt-in"
else
  bad "(r2d) expected the default run to defer 1 of 7; got rc=$RC swept=$(count_status swept "$OUT") deferred=$(count_status deferred-to-nightly "$OUT")"
  printf '%s\n' "$OUT" | tail -6
fi

echo "(s) leading-hyphen operator matches — the committed cmp rows enumerate real sites"
# The committed comparison operators' match strings BEGIN WITH A HYPHEN, so site
# enumeration must terminate option parsing before the pattern. Without that, grep reads
# the match as OPTIONS: one row becomes the pattern 'q|-ne' (matching every line
# containing 'q', all discarded as no-op flips), the other errors and enumerates zero
# sites — silently, in both directions. This case drives the REAL committed rows through
# the real harness against a guard holding exactly one genuine site per operator, plus a
# decoy comment that matches only under the mis-parse. Correct behavior: two mutants,
# both killed, zero no-op skips. The mis-parse instead yields one mutant and a no-op
# skip on the decoy line (or an enumeration red), failing both assertions.
FX="$(new_fixture strong)"
grep '^cmp-' "$REPO_ROOT/tools/mutation-operators.tsv" > "$FX/tools/mutation-operators.tsv"
if [[ "$(grep -c . "$FX/tools/mutation-operators.tsv")" -eq 2 ]]; then
  ok "committed operators file still carries both cmp-* rows"
else
  bad "(s) expected exactly two cmp-* rows in the committed operators file"
fi
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
# quick decoy: this comment line matches only a mis-parsed comparison pattern.
if [ "$#" -eq 0 ]; then
  echo "missing argument"
  exit 3
fi
if [ -z "$1" ]; then
  echo "empty argument"
  exit 3
fi
echo ok
EOF
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f=0
bash "$HERE/guard.sh" >/dev/null 2>&1; [[ $? -eq 3 ]] || f=$((f+1))
bash "$HERE/guard.sh" "" >/dev/null 2>&1; [[ $? -eq 3 ]] || f=$((f+1))
out="$(bash "$HERE/guard.sh" good)"; [[ "$out" == "ok" ]] || f=$((f+1))
exit $f
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm cmp ) >/dev/null 2>&1
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && grep -q 'applied=2 killed=2 survived=0' <<<"$OUT" \
  && ! grep -q 'skip (no-op flip)' <<<"$OUT"; then
  ok "cmp-eq and cmp-z each enumerated their one real site and mutated it"
else
  bad "(s) expected applied=2 killed=2 survived=0 and no no-op skips; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(t) a match grep cannot compile is a named red, never a silent zero-site pass"
# The other half of the enumeration contract: when grep exits >= 2 the match never ran
# as a pattern, and treating that as 'no sites' reports every guard clean against a
# mutation class that was never applied. The red must name the operator.
FX="$(new_fixture strong)"
printf '# fixture operators\nbadre\t(\ts/x/y/\n' > "$FX/tools/mutation-operators.tsv"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'operator match does not enumerate.*badre' <<<"$OUT"; then
  ok "non-compilable match reds loudly and names the operator"
else
  bad "(t) expected rc=1 + the named enumeration red; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(u) shard argument contract — malformed specs die loudly; 1/1 is exactly unsharded"
FX="$(new_fixture strong)"
for args in \
  "--mode full --shard 0/3" "--mode full --shard 4/3" "--mode full --shard x/3" \
  "--mode full --shard 3" "--mode full --shard 2/" "--mode full --shard 08/10" \
  "--mode pr --base HEAD --shard 1/2" "--mode merge" "--mode full --shards-dir ." \
  "--mode pr --base HEAD --seed" "--mode merge --shards-dir /nonexistent-dir-xyz"; do
  # shellcheck disable=SC2086 # args is a deliberate space-separated argv fragment
  OUT="$( cd "$FX" && adv bash "$SWEEP" $args 2>&1 )"; RC=$?
  if [[ $RC -eq 2 ]] && grep -q 'FATAL' <<<"$OUT"; then
    ok "rejects [$args]"
  else
    bad "(u) [$args] expected rc=2 + FATAL; got rc=$RC"
  fi
done
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full --shard 1/1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'killed=1 survived=0' <<<"$OUT"; then
  ok "--shard 1/1 sweeps the whole (one-guard) universe like an unsharded run"
else
  bad "(u) --shard 1/1 expected killed=1 survived=0 rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(v) shard partition — disjoint, complete, deterministic; excluded rows on shard 1 only"
# Invariant: --shard i/N partitions the non-excluded universe — every guard lands in
# EXACTLY one shard, no shard is empty at 7 guards / 3 shards, and the same spec always
# yields the same set. A partition that returns everything to every shard (duplicated
# work AND duplicated merge rows) or nothing to some shard (silently unswept guards)
# must fail here. The excluded guard's zero-count row is universe bookkeeping and must
# come from shard 1 exactly once, or the merged report carries duplicates.
FX="$TMPROOT/shardfleet$RANDOM$RANDOM"
make_fleet_fixture "$FX" 7
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/excluded-guard.sh"
chmod 755 "$FX/excluded-guard.sh"
printf 'excluded-guard.sh\tfixture exclusion\n' >> "$FX/tools/mutation-exclusions.tsv"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm excl ) >/dev/null 2>&1
SHARD_OK=1
for i in 1 2 3; do
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full --shard "$i/3" --report "$FX/rep$i.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 && -s "$FX/rep$i.tsv" ]] || { SHARD_OK=0; bad "(v) shard $i/3 run failed rc=$RC"; }
done
if [[ $SHARD_OK -eq 1 ]]; then
  TOTAL="$(awk -F'\t' '$2=="swept"{print $1}' "$FX"/rep[123].tsv | grep -c .)"
  UNIQ="$(awk -F'\t' '$2=="swept"{print $1}' "$FX"/rep[123].tsv | sort -u | grep -c .)"
  MIN=7; MAX=0
  for i in 1 2 3; do
    n="$(awk -F'\t' '$2=="swept"' "$FX/rep$i.tsv" | grep -c .)"
    [[ "$n" -lt "$MIN" ]] && MIN=$n
    [[ "$n" -gt "$MAX" ]] && MAX=$n
  done
  if [[ "$TOTAL" -eq 7 && "$UNIQ" -eq 7 && "$MIN" -ge 1 && "$MAX" -le 6 ]]; then
    ok "3 shards cover all 7 guards exactly once (min=$MIN max=$MAX per shard)"
  else
    bad "(v) partition broken: total=$TOTAL uniq=$UNIQ min=$MIN max=$MAX (want 7/7, every shard nonempty and partial)"
  fi
  ( cd "$FX" && adv bash "$SWEEP" --mode full --shard 2/3 --report "$FX/rep2again.tsv" ) >/dev/null 2>&1
  if cmp -s <(awk -F'\t' '$2=="swept"{print $1}' "$FX/rep2.tsv") \
            <(awk -F'\t' '$2=="swept"{print $1}' "$FX/rep2again.tsv"); then
    ok "the same shard spec re-selects the same guard set"
  else
    bad "(v) shard 2/3 selected a different set on a second run — partition is unstable"
  fi
  E1="$(grep -c "^excluded-guard\.sh	excluded" "$FX/rep1.tsv")"
  E23="$(grep -c "^excluded-guard\.sh	excluded" "$FX/rep2.tsv" "$FX/rep3.tsv" | awk -F: '{s+=$2} END{print s}')"
  if [[ "$E1" -eq 1 && "$E23" -eq 0 ]]; then
    ok "excluded zero-count row emits from shard 1 only"
  else
    bad "(v) excluded row emission: shard1=$E1 shards2+3=$E23 (want 1 and 0)"
  fi
fi

echo "(w) sharded seed + merge — one header block, all survivors, whole-universe coverage"
# Invariant chain: (1) each seed shard publishes report+baseline+slow for ITS guards;
# (2) merge concatenates into ONE report with ONE header line and one row per guard,
# ONE baseline carrying exactly one '# environment:' / '# k=' block with every shard's
# survivors, and ONE slow list deduplicated per suite at the max measurement; (3) a
# missing shard report is the named 'merge incomplete' red carrying the dead shard's
# guard names — the datapoint the monolithic job's destroyed logs never produced; a
# duplicated one is the named 'merge overlap' red.
FX="$TMPROOT/mergefx$RANDOM$RANDOM"
make_weak_fleet "$FX" 4
mkdir -p "$FX/shards/s1" "$FX/shards/s2"
MERGE_OK=1
for i in 1 2; do
  OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard "$i/2" \
          --report "$FX/shards/s$i/mutation-report.tsv" \
          --baseline-out "$FX/shards/s$i/mutation-baseline.tsv" \
          --slow-out "$FX/shards/s$i/mutation-slow-suites.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 && -s "$FX/shards/s$i/mutation-baseline.tsv" ]] \
    || { MERGE_OK=0; bad "(w) seed shard $i/2 failed rc=$RC"; printf '%s\n' "$OUT" | tail -4; }
done
if [[ $MERGE_OK -eq 1 ]]; then
  # Crafted slow files exercise the per-suite dedup: real sub-second fixture suites never
  # cross the slow threshold, so the seeded lists are empty. These are merge INPUTS —
  # the merge itself still runs in production code.
  printf '# fixture slow header\nshared-selftest.sh\t7\t2026-07-30\nonly1-selftest.sh\t6\t2026-07-30\n' \
    > "$FX/shards/s1/mutation-slow-suites.tsv"
  printf '# fixture slow header\nshared-selftest.sh\t9\t2026-07-30\nonly2-selftest.sh\t8\t2026-07-30\n' \
    > "$FX/shards/s2/mutation-slow-suites.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards" \
          --report "$FX/merged-report.tsv" --baseline-out "$FX/merged-baseline.tsv" \
          --slow-out "$FX/merged-slow.tsv" 2>&1 )"; RC=$?
  ROWS_OK=1
  for g in 1 2 3 4; do
    [[ "$(grep -c "^guard$g\.sh	swept" "$FX/merged-report.tsv")" -eq 1 ]] || ROWS_OK=0
    grep -q "^$(sid_for "$FX" "guard$g.sh" fail-open 1)	" "$FX/merged-baseline.tsv" || ROWS_OK=0
  done
  if [[ $RC -eq 0 && $ROWS_OK -eq 1 ]] \
    && [[ "$(grep -c '^guard	status	paired_selftest' "$FX/merged-report.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^# environment:' "$FX/merged-baseline.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^# k=' "$FX/merged-baseline.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^# keying: content-v1$' "$FX/merged-baseline.tsv")" -eq 1 ]]; then
    ok "merged report has one header + one row per guard; baseline has one header block + all survivors"
  else
    bad "(w) merge output malformed; rc=$RC rows_ok=$ROWS_OK"; printf '%s\n' "$OUT" | tail -6
  fi
  if [[ "$(grep -c '^# fixture slow header' "$FX/merged-slow.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^shared-selftest\.sh	' "$FX/merged-slow.tsv")" -eq 1 ]] \
    && grep -q '^shared-selftest\.sh	9	' "$FX/merged-slow.tsv" \
    && grep -q '^only1-selftest\.sh	6	' "$FX/merged-slow.tsv" \
    && grep -q '^only2-selftest\.sh	8	' "$FX/merged-slow.tsv"; then
    ok "merged slow list dedups the shared suite at its max measurement"
  else
    bad "(w) merged slow list wrong"; cat "$FX/merged-slow.tsv"
  fi
  cp -R "$FX/shards" "$FX/shards-missing"
  rm -f "$FX/shards-missing/s2/mutation-report.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-missing" \
          --report "$FX/m2.tsv" --baseline-out "$FX/b2.tsv" --slow-out "$FX/sl2.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && grep -q 'merge incomplete: no shard reported guard guard2\.sh' <<<"$OUT"; then
    ok "a dead shard's guards are NAMED by the merge red"
  else
    bad "(w) expected rc=1 + 'merge incomplete' naming guard2.sh; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
  cp -R "$FX/shards" "$FX/shards-dup"
  cp "$FX/shards-dup/s1/mutation-report.tsv" "$FX/shards-dup/s2/mutation-report.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-dup" \
          --report "$FX/m3.tsv" --baseline-out "$FX/b3.tsv" --slow-out "$FX/sl3.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && grep -q 'merge overlap' <<<"$OUT"; then
    ok "duplicated shard rows are the named partition-broken red"
  else
    bad "(w) expected rc=1 + 'merge overlap'; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
fi
# An EMPTY seed shard (N exceeds the guard count) must still publish its headed artifacts,
# or the merge reds every such run on a missing shard baseline.
FX="$(new_fixture weak)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard 2/2 \
        --report "$FX/r.tsv" --baseline-out "$FX/b.tsv" --slow-out "$FX/s.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 && -s "$FX/b.tsv" && -s "$FX/r.tsv" ]] \
  && grep -q '^# environment: ' "$FX/b.tsv" \
  && [[ "$(grep -vc '^#' "$FX/b.tsv")" -eq 0 ]]; then
  ok "an empty seed shard still writes a headed, survivor-free baseline"
else
  bad "(w) empty seed shard did not publish artifacts; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(w2) --report is a STREAMING sink, and mutation-complete is written only by finish()"
# Why this is not covered by (w): every case above reads the report AFTER the run, where a
# streamed sink and a mktemp buffer copied in finish() are indistinguishable. The property
# that matters to a shard that never reaches finish() is what is on the artifact path
# WHILE it is still working — pre-fix, nothing at all, so the CI upload step (which reds on
# an empty directory) had nothing to publish for exactly the run worth diagnosing.
#
# Observed by a fixture KILLER rather than by racing the sweep from here: the killer runs
# mid-sweep by construction, so the case is deterministic instead of timing-dependent. The
# marker is read at the same instant and must be ABSENT — it is what merge uses to tell a
# shard killed here from one that finished, so a marker written up front would be a lie.
FX="$TMPROOT/streamfx$RANDOM$RANDOM"
make_weak_fleet "$FX" 2
baseline_with "$FX" "$(sid_for "$FX" guard1.sh fail-open 1)" "$(sid_for "$FX" guard2.sh fail-open 1)"
mkdir -p "$FX/out"
OBS="$FX/observed"
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURE's code, not ours
{ printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
  printf '{ if [[ -f %s/out/mutation-report.tsv ]]; then\n' "$FX"
  printf '    grep -q "^guard	status	paired_selftest" %s/out/mutation-report.tsv && echo report-headed || echo report-headless\n' "$FX"
  printf '  else echo report-absent; fi\n'
  printf '  [[ -f %s/out/mutation-complete ]] && echo marker-present || echo marker-absent\n' "$FX"
  printf '} >> %s\n' "$OBS"
  printf 'out="$(bash "$H/guard1.sh" good)"\n[[ "$out" == ok ]] || exit 1\nexit 0\n'
} > "$FX/guard1-selftest.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm obs ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$FX/out/mutation-report.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && [[ -s "$OBS" ]] \
  && grep -q '^report-headed$' "$OBS" \
  && ! grep -q '^report-absent$\|^report-headless$' "$OBS"; then
  ok "the report is headed on the --report path while killers are still running"
else
  bad "(w2) mid-run report observation wrong; rc=$RC obs=[$(sort -u "$OBS" 2>/dev/null | tr '\n' ' ')]"
  printf '%s\n' "$OUT" | tail -4
fi
if grep -q '^marker-absent$' "$OBS" && ! grep -q '^marker-present$' "$OBS"; then
  ok "mutation-complete does not exist mid-sweep"
else
  bad "(w2) mutation-complete was present mid-sweep — it cannot distinguish a killed shard"
fi
if [[ -f "$FX/out/mutation-complete" ]] \
  && grep -q '^mode=full shard=1/1 rc=0 wall_s=[0-9][0-9]*$' "$FX/out/mutation-complete"; then
  ok "a run that reaches finish() leaves a mutation-complete marker naming its mode/shard/rc"
else
  bad "(w2) marker missing or malformed: [$(cat "$FX/out/mutation-complete" 2>/dev/null)]"
fi
# Without --report there is no output dir to mark, and the report goes to stdout. A marker
# written into some default location instead would be a file nothing publishes and merge
# would never see — worse than none.
FX2="$(new_fixture weak)"
baseline_with "$FX2" "$(sid_for "$FX2" guard.sh fail-open 1)"
OUT="$( cd "$FX2" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
STRAY="$(find "$FX2" -name mutation-complete 2>/dev/null | grep -c . )"
if [[ $RC -eq 0 ]] && grep -q '^guard	status	paired_selftest' <<<"$OUT" && [[ "$STRAY" -eq 0 ]]; then
  ok "without --report the report still goes to stdout and no marker is written"
else
  bad "(w2) no-report run wrong; rc=$RC stray_markers=$STRAY"; printf '%s\n' "$OUT" | tail -4
fi

echo "(w3) merge separates a truncated shard from a complete one"
# A streamed report is present even when its shard died part-way, so 'a report exists' no
# longer means 'this shard finished'. Merge must say which is which — and its seed-arity
# check must not read a truncated shard (killed before finish(), hence before it wrote its
# baseline) as a seed/enforcing MODE mismatch, which is the wrong diagnosis and buries the
# real one.
FX="$TMPROOT/truncfx$RANDOM$RANDOM"
make_weak_fleet "$FX" 4
mkdir -p "$FX/shards/s1" "$FX/shards/s2"
TRUNC_OK=1
for i in 1 2; do
  OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard "$i/2" \
          --report "$FX/shards/s$i/mutation-report.tsv" \
          --baseline-out "$FX/shards/s$i/mutation-baseline.tsv" \
          --slow-out "$FX/shards/s$i/mutation-slow-suites.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 && -f "$FX/shards/s$i/mutation-complete" ]] \
    || { TRUNC_OK=0; bad "(w3) seed shard $i/2 failed or left no marker; rc=$RC"; printf '%s\n' "$OUT" | tail -4; }
done
if [[ $TRUNC_OK -eq 1 ]]; then
  # s2 as a shard killed mid-sweep really looks: a partial report, no marker, no baseline.
  cp -R "$FX/shards" "$FX/shards-trunc"
  rm -f "$FX/shards-trunc/s2/mutation-complete" "$FX/shards-trunc/s2/mutation-baseline.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-trunc" \
          --report "$FX/t.tsv" --baseline-out "$FX/tb.tsv" --slow-out "$FX/ts.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && grep -q 'merge truncated:.*\bs2\b' <<<"$OUT"; then
    ok "a report without a completion marker is the named 'merge truncated' red"
  else
    bad "(w3) expected rc=1 + 'merge truncated' naming s2; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
  if ! grep -q 'mixed seed and enforcing shards' <<<"$OUT"; then
    ok "the seed-arity check counts completed shards, so a truncation is not misread as a mode mismatch"
  else
    bad "(w3) truncated shard was diagnosed as a seed/enforcing mode mismatch"; printf '%s\n' "$OUT" | tail -5
  fi
  # Control: with BOTH shards complete, a genuinely missing baseline must still red as the
  # mode mismatch. Without this the arity check could be dead rather than re-keyed.
  cp -R "$FX/shards" "$FX/shards-mixed"
  rm -f "$FX/shards-mixed/s2/mutation-baseline.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-mixed" \
          --report "$FX/x.tsv" --baseline-out "$FX/xb.tsv" --slow-out "$FX/xs.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && grep -q '2 completed shard report(s) but 1 baseline(s) — mixed seed and enforcing shards' <<<"$OUT"; then
    ok "two completed shards with one baseline is still the mode-mismatch red"
  else
    bad "(w3) expected the mixed seed/enforcing red on complete shards; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
fi

echo "(x) sharded enforcing run — another shard's baseline rows are out of scope, not 'now KILLED'"
# The shrink warn is only decidable for guards THIS shard swept: under sharding, every
# shard seeing every other shard's rows as 'now KILLED' would tell the operator to drop
# ~ (N-1)/N of a healthy baseline. Unsharded behavior (warn on every row) is asserted by
# case (d) and re-pinned here on the same fixture.
FX="$TMPROOT/scopefx$RANDOM$RANDOM"
make_fleet_fixture "$FX" 2
# make_fleet_fixture's guards contain no `exit 1` at all, so there is no site to derive a key
# from — and none is needed: what this case exercises is a baselined row whose GUARD resolves,
# which is decided by the first segment. The literal is content-key-SHAPED so the committed
# baseline's own lint keeps applying to the same vocabulary.
G2SID='guard2.sh::fail-open::000000000000'
baseline_with "$FX" "$G2SID"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q "now KILLED: $G2SID" <<<"$OUT"; then
  ok "unsharded full run still warns on the stale row"
else
  bad "(x) unsharded run should warn 'now KILLED'; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --shard 1/2 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'now KILLED' <<<"$OUT"; then
  ok "shard 1/2 (which does not sweep guard2.sh) stays silent about its row"
else
  bad "(x) shard 1/2 warned about another shard's row (or reded); rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(y) killer stdin isolation — a killer cannot consume the harness's stdin"
# Invariant: run_killer gives each killer its own /dev/null stdin. 30 of the 48 swept
# guards contain a read loop; a mutant that breaks one's input redirection leaves it
# reading whatever stdin the harness inherited rather than its own.
# Asserted by consumption rather than by hanging: this case would otherwise have to BLOCK
# to fail. A killer that eats the sentinel here is one that would misread on a real guard.
# NOT the cause of the dead nightly shards, though it was first blamed for them — those
# survived this fix unchanged and belong to (z) below.
FX="$(new_fixture strong)"
baseline_with "$FX"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Isolated stdin makes this EOF at once; leaked stdin makes it eat the caller's sentinel.
IFS= read -r _ 2>/dev/null || true
out="$(bash "$HERE/guard.sh" bad)"; rc=$?
[[ $rc -eq 1 && "$out" == "violation" ]] || exit 1
exit 0
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm stdin ) >/dev/null 2>&1
LEFTOVER="$( printf 'SENTINEL\n' | { ( cd "$FX" && enf bash "$SWEEP" --mode full ) >/dev/null 2>&1; IFS= read -r l || true; printf '%s' "$l"; } )"
if [[ "$LEFTOVER" == "SENTINEL" ]]; then
  ok "harness stdin survived the killer runs"
else
  bad "(y) a killer consumed the harness's stdin (leftover='$LEFTOVER'); a guard's read loop would block here instead"
fi

echo "(z) killer time bound — a mutant that makes its guard SPIN cannot hang the sweep"
# The failure this pins killed three shards of every 10-shard nightly, deterministically,
# and destroyed their logs each time. `cmp-z` inverts the EOF-tolerance clause of the
# repo's standard read idiom — `while IFS= read -r line || [[ -n "$line" ]]` becomes
# `|| [[ -z "$line" ]]` — and at EOF that clause is permanently TRUE, so the guard spins
# forever at 100% CPU. Its killer never returns, and `run_killer` had no time bound, so
# the shard emitted no further line until the job timed out with the log unfinalized.
# Three live guards carry that idiom; the k budget decides which are armed, which is why
# shard 8 (scaffold-review-context.sh, ordinal 5 > k=2) survived while shards 4 and 9
# (ordinal 1) did not. This fixture reproduces the armed shape at ordinal 1.
#
# Unlike (y), this case CAN assert by hanging, because it brings its own outer watchdog:
# the harness runs under a wall-clock bound here, and blowing it is the failure. That is
# the only honest way to pin "does not hang" — asserting by proxy is what let this pass
# unnoticed while three shards died.
FX="$TMPROOT/fxspin$RANDOM$RANDOM"
make_spin_fixture "$FX"
SPIN_LOG="$FX/sweep.log"
( cd "$FX" && adv env MUTATION_SWEEP_KILLER_TIMEOUT_S=5 bash "$SWEEP" --mode full ) \
  >"$SPIN_LOG" 2>&1 </dev/null &
SPIN_PID=$!
# Outer bound: 5s killer timeout + sandbox/precheck slack. Generous enough that a healthy
# harness never trips it, tight enough that a hung one fails fast instead of stalling CI.
SPIN_DEADLINE=$(( $(date +%s) + 90 ))
SPIN_HUNG=0
while kill -0 "$SPIN_PID" 2>/dev/null; do
  if [[ "$(date +%s)" -ge "$SPIN_DEADLINE" ]]; then SPIN_HUNG=1; break; fi
  sleep 0.2
done
if [[ $SPIN_HUNG -eq 1 ]]; then
  kill -9 "$SPIN_PID" 2>/dev/null
  pkill -9 -f "$FX/guard.sh" 2>/dev/null
  wait "$SPIN_PID" 2>/dev/null
  bad "(z) the sweep HUNG on a spinning mutant — run_killer has no time bound"
else
  wait "$SPIN_PID" 2>/dev/null; SPIN_RC=$?
  SPIN_OUT="$(cat "$SPIN_LOG")"
  if [[ $SPIN_RC -ne 0 ]]; then
    bad "(z) sweep completed but exited $SPIN_RC"; printf '%s\n' "$SPIN_OUT" | tail -5
  elif ! grep -q 'killer timeout' <<<"$SPIN_OUT"; then
    bad "(z) the timed-out killer was not named in the log — a silent kill hides a spin"
    printf '%s\n' "$SPIN_OUT" | tail -5
  elif ! grep -qE 'swept guard\.sh — applied=1 killed=1 survived=0' <<<"$SPIN_OUT"; then
    bad "(z) spun mutant not scored as killed-by-timeout"; printf '%s\n' "$SPIN_OUT" | tail -5
  else
    ok "spinning mutant is bounded, scored as killed, and NAMED in the log"
  fi
fi

echo "(aa) killer bound SCALES per suite — a fast suite is not held to the slow ceiling"
# The bound in (z) is flat only because that fixture pins the ceiling low. A flat bound
# bounds one killer but NOT a shard: a guard whose mutants all spin costs k x the bound,
# and the first bounded seed run still lost a 60-min shard to that accumulation on a
# ~15-min cost model. So the contract is `4 x the suite's measured unmutated time`,
# floored and capped — and this case pins that the FLOOR is what a ~0s fixture suite gets,
# not the ceiling. Asserted through the logged bound, which is the operator-visible number.
# Floor is overridden to 3s so the case proves scaling in seconds rather than in a minute.
# The fixture guard is one trivial subprocess spawn, normally measured at 0s (secs=0 -> the
# 3s floor applies), but a loaded CI runner can round that measurement up to 1s, which scales
# to 1 x KILLER_TIMEOUT_FACTOR(4) = 4s instead. Both readings prove the real contract — a fast
# suite gets a small scaled/floored bound, never the flat 300s ceiling — so the assertion below
# accepts a range instead of pinning the exact reading that only holds on an idle runner.
FX="$TMPROOT/fxscale$RANDOM$RANDOM"
mkdir -p "$FX/tools"
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r line || [[ -n "$line" ]]; do
  :
done
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" </dev/null)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
printf '# fixture operators\ncmp-z\t-z |-n \ts/-z /__MUT__/g; s/-n /-z /g; s/__MUT__/-n /g\n' \
  > "$FX/tools/mutation-operators.tsv"
printf '# fixture exclusions\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\n'   > "$FX/tools/mutation-pair-map.tsv"
printf '# fixture catalog\n'    > "$FX/tools/mutation-catalog.tsv"
( cd "$FX" && git init -q . && git add -A \
  && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm scale ) >/dev/null 2>&1

SCALE_LOG="$FX/sweep.log"
( cd "$FX" && adv env MUTATION_SWEEP_KILLER_TIMEOUT_S=300 MUTATION_SWEEP_KILLER_MIN_S=3 \
    bash "$SWEEP" --mode full ) >"$SCALE_LOG" 2>&1 </dev/null &
SCALE_PID=$!
SCALE_DEADLINE=$(( $(date +%s) + 90 ))
SCALE_HUNG=0
while kill -0 "$SCALE_PID" 2>/dev/null; do
  if [[ "$(date +%s)" -ge "$SCALE_DEADLINE" ]]; then SCALE_HUNG=1; break; fi
  sleep 0.2
done
if [[ $SCALE_HUNG -eq 1 ]]; then
  kill -9 "$SCALE_PID" 2>/dev/null; pkill -9 -f "$FX/guard.sh" 2>/dev/null
  wait "$SCALE_PID" 2>/dev/null
  bad "(aa) sweep did not finish — a ~0s suite was held to the 300s ceiling, not the floor"
else
  wait "$SCALE_PID" 2>/dev/null
  SCALE_OUT="$(cat "$SCALE_LOG")"
  SCALE_BOUND="$(printf '%s' "$SCALE_OUT" | grep -oE 'killer timeout \([0-9]+s exceeded' | head -1 | grep -oE '[0-9]+')"
  if [[ -n "$SCALE_BOUND" && "$SCALE_BOUND" -ge 3 && "$SCALE_BOUND" -le 20 ]]; then
    ok "fast suite bounded near the floor (${SCALE_BOUND}s), not the 300s ceiling"
  else
    bad "(aa) expected a small scaled/floored bound (3-20s); got:"
    printf '%s\n' "$SCALE_OUT" | grep 'killer timeout' | head -2
  fi
fi

echo "(ab) killer PROCESS bound — a mutant that makes its guard FORK cannot kill the host"
# The sibling of (z), and NOT covered by it: a wall clock decides when to stop WAITING, it
# does nothing about what the guard does to the machine while we wait. A recursively
# forking guard exhausts the runner long before any deadline is reached, which is how the
# nightly lost shard 1 twice — once as "the runner has received a shutdown signal", once
# as "the hosted runner lost communication with the server", both with the log blob
# unfinalized and no artifact. (z) would pass the entire time: the harness never hung.
#
# The fixture mirrors doctor.sh's real shape rather than inventing one, because that shape
# is what made the bug invisible: a nested self-invocation (`bash "$0"`, no args) that
# terminates ONLY because the nested run does not re-enter the branch that makes it.
# Flipping the `-eq` that gates the branch is a single ordinary cmp-eq mutant, and every
# ancestor stays live while its child runs, so the group grows one level at a time.
#
# The fixture's own depth cap is the TEST's safety net, not the harness's: if the bound
# under test ever regresses this case must fail, not fork-bomb a shared runner. It sits
# far above the process bound pinned here, so it can never be what stops the growth.
FX="$TMPROOT/fxfork$RANDOM$RANDOM"
mkdir -p "$FX/tools"
# THE FIXTURE CARRIES NO PROSE. Operator sites are enumerated by grepping the guard's
# TEXT, comments included, so a comment mentioning the operator's match string becomes a
# mutation site — and flipping a comment is a guaranteed survivor, which reds the run on a
# mutant that cannot mean anything. An earlier draft of this case explained itself inside
# the heredoc and enumerated two bogus cmp-eq sites for its trouble. Everything the
# fixture would have said is said here instead:
#
#   - the flag is `--wrap`, not `--nest`, because the match string `-ne` is a SUBSTRING of
#     `--nest`, which would enumerate a second, meaningless site;
#   - the depth cap holds the tree up for a beat rather than merely capping it. Sixty
#     levels of a do-nothing guard unwind well inside the harness's ~1s population sample,
#     so a burst that never overlaps a sample would prove nothing. The shape being modelled
#     (doctor.sh runs git and jq at every level) persists for minutes; sleeping at the
#     floor restores that property without making the fixture slow.
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
D="${FIXTURE_DEPTH:-0}"
if [[ "$D" -ge 60 ]]; then sleep 3; echo ok; exit 0; fi
WRAP=0
[[ "${1:-}" == "--wrap" ]] && WRAP=1
if [[ "$WRAP" -eq 1 ]]; then echo "wrapped:$(FIXTURE_DEPTH=$((D + 1)) bash "$0")"; exit 0; fi
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" </dev/null)"
[[ "$out" == "ok" ]] || exit 1
wrapped="$(bash "$HERE/guard.sh" --wrap </dev/null)"
[[ "$wrapped" == "wrapped:ok" ]] || exit 1
exit 0
EOF
printf '# fixture operators\ncmp-eq\t-eq|-ne\ts/-eq/__MUT__/g; s/-ne/-eq/g; s/__MUT__/-ne/g\n' \
  > "$FX/tools/mutation-operators.tsv"
printf '# fixture exclusions\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\n'   > "$FX/tools/mutation-pair-map.tsv"
printf '# fixture catalog\n'    > "$FX/tools/mutation-catalog.tsv"
( cd "$FX" && git init -q . && git add -A \
  && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm fork ) >/dev/null 2>&1

# A LOW process bound so the case trips in about a second on a handful of processes
# instead of on a real bomb, and a short time bound so a regression fails fast rather
# than forking for the default ceiling. The time bound is deliberately reachable: if the
# process bound never fires, the time bound eventually does, and the log then says
# `killer timeout` where this case demands `killer process bound` — so a dead population
# check fails LOUDLY instead of being absorbed by its sibling.
FORK_LOG="$FX/sweep.log"
( cd "$FX" && adv env MUTATION_SWEEP_KILLER_MAX_PROCS=12 MUTATION_SWEEP_KILLER_TIMEOUT_S=20 \
    bash "$SWEEP" --mode full ) >"$FORK_LOG" 2>&1 </dev/null &
FORK_PID=$!
FORK_DEADLINE=$(( $(date +%s) + 90 ))
FORK_HUNG=0
while kill -0 "$FORK_PID" 2>/dev/null; do
  if [[ "$(date +%s)" -ge "$FORK_DEADLINE" ]]; then FORK_HUNG=1; break; fi
  sleep 0.2
done
if [[ $FORK_HUNG -eq 1 ]]; then
  kill -9 "$FORK_PID" 2>/dev/null
  pkill -9 -f "$FX/guard.sh" 2>/dev/null
  wait "$FORK_PID" 2>/dev/null
  bad "(ab) the sweep HUNG on a forking mutant — run_killer has no process bound"
else
  wait "$FORK_PID" 2>/dev/null; FORK_RC=$?
  FORK_OUT="$(cat "$FORK_LOG")"
  # Orphan check, the reason reap_group freezes the group before killing it: a single
  # SIGKILL sweep races a tree that is still forking, and whatever it misses keeps
  # forking for the rest of the shard — on a guard the harness has already moved past.
  FORK_ORPHANS="$(pgrep -f "$FX/guard.sh" 2>/dev/null | wc -l | tr -d ' ')"
  pkill -9 -f "$FX/guard.sh" 2>/dev/null
  if [[ $FORK_RC -ne 0 ]]; then
    bad "(ab) sweep completed but exited $FORK_RC"; printf '%s\n' "$FORK_OUT" | tail -5
  elif ! grep -q 'killer process bound' <<<"$FORK_OUT"; then
    bad "(ab) the forking killer was not named in the log — a silent kill hides a fork bomb"
    printf '%s\n' "$FORK_OUT" | tail -5
  elif ! grep -qE 'swept guard\.sh — applied=1 killed=1 survived=0' <<<"$FORK_OUT"; then
    bad "(ab) forking mutant not scored as killed-by-process-bound"; printf '%s\n' "$FORK_OUT" | tail -5
  elif [[ "${FORK_ORPHANS:-0}" -ne 0 ]]; then
    bad "(ab) $FORK_ORPHANS guard process(es) outlived the reap — the group kill lost the fork race"
  else
    ok "forking mutant is bounded, reaped whole, scored as killed, and NAMED in the log"
  fi
fi

# ======================================================== live-tree lint cases
# (j) and (k) run against the REAL tree, not a fixture. They are pure resolution/parse
# lints — no mutation, no sandbox, no suite execution — so they are cheap enough for both
# per-push lanes, and they are what stops this harness from converging on green while the
# tree drifts underneath it.

echo "(ac) pool equivalence — a parallel run IS the serial run, and it really was parallel"
# The equivalence half of this case is worthless on its own: two serial runs also produce
# identical reports. So the fixture's killers record what the pool was doing while they ran
# — how many siblings were live, and which sandbox each ran in — and the case asserts the
# parallel run actually overlapped BEFORE it asserts the reports match. Without that, a pool
# that silently degraded to one worker would read as a passing equivalence proof.
#
# The four survivors are BASELINED, and that is load-bearing rather than tidy: an unbaselined
# survivor is re-derived by the serial oracle on a sandbox of its own, which is a second
# sandbox and four more killer runs — real behavior, but not the pool's, and it would drown
# the concurrency observations this case exists to read. Baselining isolates the measurement
# to the pool. (aj) owns the oracle.
OBS_AC="$TMPROOT/obs-ac"
FX="$TMPROOT/fxac$RANDOM$RANDOM"
make_obs_fleet "$FX" 4 "$OBS_AC"
baseline_with "$FX" "$(sid_for "$FX" guard1.sh fail-open 1)" "$(sid_for "$FX" guard2.sh fail-open 1)" \
                    "$(sid_for "$FX" guard3.sh fail-open 1)" "$(sid_for "$FX" guard4.sh fail-open 1)"
obs_reset "$OBS_AC"
OUT="$( cd "$FX" && adv env MUTATION_SWEEP_JOBS=1 bash "$SWEEP" --mode full --report "$TMPROOT/ac-1.tsv" 2>&1 )"; RC=$?
MAX1="$(obs_max "$OBS_AC")"; SB1="$(obs_sandboxes "$OBS_AC")"
obs_reset "$OBS_AC"
OUT4="$( cd "$FX" && adv env MUTATION_SWEEP_JOBS=4 bash "$SWEEP" --mode full --report "$TMPROOT/ac-4.tsv" 2>&1 )"; RC4=$?
MAX4="$(obs_max "$OBS_AC")"; SB4="$(obs_sandboxes "$OBS_AC")"
if [[ "$MAX1" -eq 1 && "$SB1" -eq 1 ]]; then
  ok "MUTATION_SWEEP_JOBS=1 never overlaps: max 1 killer live, 1 sandbox"
else
  bad "(ac) serial run observed max=$MAX1 sandboxes=$SB1 (want 1 and 1)"
fi
if [[ "$MAX4" -gt 1 && "$SB4" -gt 1 ]]; then
  ok "MUTATION_SWEEP_JOBS=4 overlapped: $MAX4 killers live at once across $SB4 sandboxes"
else
  bad "(ac) parallel run observed max=$MAX4 sandboxes=$SB4 (want >1 and >1) — the pool never overlapped, so the equivalence assertion below would prove nothing"
fi
if [[ $RC -eq $RC4 ]] && diff -q "$TMPROOT/ac-1.tsv" "$TMPROOT/ac-4.tsv" >/dev/null 2>&1; then
  ok "identical report and exit status from the serial and the parallel run"
else
  bad "(ac) serial rc=$RC parallel rc=$RC4, reports differ"
  diff "$TMPROOT/ac-1.tsv" "$TMPROOT/ac-4.tsv" 2>&1 | head -8
fi

echo "(ad) verdict cache — a re-run over an unchanged tree executes no paired suite at all"
FX="$(new_fixture weak)"
CD="$TMPROOT/cache-ad"
OUT="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full --report "$TMPROOT/ad-cold.tsv" 2>&1 )"
C1="$(computed "$OUT")"; S1="$(served "$OUT")"
OUT2="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full --report "$TMPROOT/ad-warm.tsv" 2>&1 )"
C2="$(computed "$OUT2")"; S2="$(served "$OUT2")"
if [[ "${C1:-0}" -gt 0 && "${S1:-9}" -eq 0 ]]; then
  ok "cold run computed $C1 verdict(s) and served none"
else
  bad "(ad) cold run computed=${C1:-?} served=${S1:-?} (want >0 and 0)"; printf '%s\n' "$OUT" | tail -3
fi
# ZERO is the whole assertion, and it covers the PRECHECK as well as the mutants — a
# precheck is a paired-suite execution too, so a warm run that still ran one would not have
# executed none. The cold run's 3 is 1 precheck + 1 mutant + 1 serial re-verify (this fixture
# carries no baseline, so its survivor is one that would red); the warm run's 1 served is the
# mutant, the precheck is skipped outright rather than cached, and the oracle declines because
# a cache hit was never scored by the pool.
if [[ "${C2:-9}" -eq 0 && "${S2:-0}" -gt 0 ]]; then
  ok "warm run computed 0 and served $S2 — zero paired-suite executions, precheck included"
else
  bad "(ad) warm run computed=${C2:-?} served=${S2:-?} (want 0 and >0)"; printf '%s\n' "$OUT2" | tail -3
fi
if diff -q "$TMPROOT/ad-cold.tsv" "$TMPROOT/ad-warm.tsv" >/dev/null 2>&1; then
  ok "the cached run reports the identical survivor set"
else
  bad "(ad) warm report differs from cold"; diff "$TMPROOT/ad-cold.tsv" "$TMPROOT/ad-warm.tsv" 2>&1 | head -8
fi

echo "(ae) the key includes the SUITE's bytes — an added test case turns a cached SURVIVED into KILLED"
# THE failure a guard-only key would produce, driven directly. guard.sh is byte-identical
# across both runs; only the killer grows a case. A cache keyed on the guard alone hits, and
# serves a SURVIVED verdict for a mutant the tree now kills — green, stale, and undetectable
# from the report.
FX="$(new_fixture weak)"
CD="$TMPROOT/cache-ae"
OUT="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
GSHA_BEFORE="$(shasum -a 256 "$FX/guard.sh" 2>/dev/null | cut -d' ' -f1)"
if grep -q 'killed=0 survived=1' <<<"$OUT"; then
  ok "cold: the happy-path-only killer lets the fail-open mutant survive"
else
  bad "(ae) expected killed=0 survived=1 on the weak killer"; printf '%s\n' "$OUT" | tail -3
fi
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
# The ADDED case: exercises the violation path the weak version never touched.
rc=0; bash "$HERE/guard.sh" bad >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 ]] || exit 1
exit 0
EOF
( cd "$FX" && git add -A \
  && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm "add the missing case" ) >/dev/null 2>&1
GSHA_AFTER="$(shasum -a 256 "$FX/guard.sh" 2>/dev/null | cut -d' ' -f1)"
OUT2="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
if [[ "$GSHA_BEFORE" == "$GSHA_AFTER" ]]; then
  ok "guard.sh is byte-identical across the two runs — only the suite changed"
else
  bad "(ae) the fixture changed guard.sh, so this case no longer isolates the suite key"
fi
if grep -q 'killed=1 survived=0' <<<"$OUT2"; then
  ok "the added case kills the mutant — no stale SURVIVED was served"
else
  bad "(ae) expected killed=1 survived=0 after the case was added; a guard-only cache key serves the stale SURVIVED here"
  printf '%s\n' "$OUT2" | tail -3
fi

echo "(af) cache fail-safe — corruption and an environment change are MISSES, never passes"
FX="$(new_fixture weak)"
CD="$TMPROOT/cache-af"
OUT="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
find "$CD" -type f 2>/dev/null | while IFS= read -r f; do printf 'not a record at all\n' > "$f"; done
OUT2="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
C2="$(computed "$OUT2")"
if [[ "${C2:-0}" -gt 0 ]] && grep -q 'killed=0 survived=1' <<<"$OUT2"; then
  ok "a malformed entry falls back to a real run and reproduces the verdict"
else
  bad "(af) corrupt-cache run computed=${C2:-?} — a malformed entry must never be served"
  printf '%s\n' "$OUT2" | tail -3
fi
# A VALID first line with a second line after it is still corrupt: the shape check is on the
# whole file, not on the line the reader happens to look at.
find "$CD" -type f 2>/dev/null | while IFS= read -r f; do printf 'appended junk\n' >> "$f"; done
OUT3="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
C3="$(computed "$OUT3")"
if [[ "${C3:-0}" -gt 0 ]]; then
  ok "a well-formed first line with trailing junk is a miss too"
else
  bad "(af) a two-line entry was served as a hit (computed=${C3:-?})"
fi
OUT4="$( cd "$FX" && cch "$CD" env MUTATION_SWEEP_KILLER_MAX_PROCS=97 bash "$SWEEP" --mode full 2>&1 )"
C4="$(computed "$OUT4")"
if [[ "${C4:-0}" -gt 0 ]]; then
  ok "an environment change re-keys every entry — the cache survives no environment change"
else
  bad "(af) an environment change hit the cache (computed=${C4:-?})"
fi
# The KILL CRITERION is part of the environment by the same argument the killer bounds are:
# a run that scores under a different one is not answering the same question. Two separate
# assertions, because each kills its own field of CACHE_ENV_TAG — dropping FAIL_PATTERN from
# the key reds only the first, dropping EARLY_EXIT reds only the second. The pattern below is
# one no green fixture suite emits, so this exercises the key and not D-3's unrunnable pair.
OUT4B="$( cd "$FX" && cch "$CD" env MUTATION_SWEEP_FAIL_PATTERN='NEVER-EMITTED-BY-A-GREEN-SUITE:' bash "$SWEEP" --mode full 2>&1 )"
C4B="$(computed "$OUT4B")"
if [[ "${C4B:-0}" -gt 0 ]]; then
  ok "a custom fail pattern re-keys every entry — a verdict scored under one kill criterion is never served to another"
else
  bad "(af) a MUTATION_SWEEP_FAIL_PATTERN change hit the cache (computed=${C4B:-?}); the kill criterion is outside the key"
fi
OUT4C="$( cd "$FX" && cch "$CD" env MUTATION_SWEEP_EARLY_EXIT=0 bash "$SWEEP" --mode full 2>&1 )"
C4C="$(computed "$OUT4C")"
if [[ "${C4C:-0}" -gt 0 ]]; then
  ok "disabling early exit re-keys every entry"
else
  bad "(af) a MUTATION_SWEEP_EARLY_EXIT change hit the cache (computed=${C4C:-?}); the trigger is outside the key"
fi
if [[ -z "$( cd "$FX" && git status --porcelain 2>/dev/null )" ]]; then
  ok "the cache lives outside the checkout — the fixture repo has nothing to commit"
else
  bad "(af) the run left files in the checkout:"; ( cd "$FX" && git status --porcelain ) | head -5
fi
# D-7: THIS HARNESS's own bytes are in the key. A hand-maintained schema constant would have
# to be bumped by whoever next edits the kill criterion, the early-exit trigger or a killer
# bound — and a discipline like that fails silently, leaving entries that outlive the meaning
# they were recorded under. A trailing comment cannot change behavior, which is the point:
# invalidation is conservative and automatic rather than judged.
SWEEP_VARIANT="$TMPROOT/sweep-variant.sh"
{ cat "$SWEEP"; printf '\n# an edit to this harness, which must re-key every entry\n'; } > "$SWEEP_VARIANT"
OUT5="$( cd "$FX" && cch "$CD" bash "$SWEEP_VARIANT" --mode full 2>&1 )"
C5="$(computed "$OUT5")"
if [[ "${C5:-0}" -gt 0 ]]; then
  ok "editing the harness re-keys every entry — no verdict outlives a change to how it was scored"
else
  bad "(af) a modified harness HIT the cache (computed=${C5:-?}); the key does not include its own bytes"
fi
# D-6: one subtree per repo, because two checkouts can hold byte-identical guards and suites
# while differing in a file one of those suites merely SOURCES — which is exactly the residual
# the narrow key carries.
if [[ -d "$CD/$(basename "$FX")" ]]; then
  ok "entries live under <cache dir>/<repo basename>/ — two checkouts cannot share a key"
else
  bad "(af) no per-repo subdirectory under $CD; two checkouts would share entries"
  find "$CD" -maxdepth 1 -mindepth 1 2>/dev/null | head -3
fi

echo "(ag) early exit — a killed mutant stops at the first FAIL:, and scores what a full run scores"
OBS_AG="$TMPROOT/obs-ag"
FX="$TMPROOT/fxagf$RANDOM$RANDOM"
make_early_fixture "$FX" first "$OBS_AG"
obs_reset "$OBS_AG"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"
EARLY_DONE="$(obs_count "$OBS_AG" completed)"
obs_reset "$OBS_AG"
OUT2="$( cd "$FX" && adv env MUTATION_SWEEP_EARLY_EXIT=0 bash "$SWEEP" --mode full 2>&1 )"
FULL_DONE="$(obs_count "$OBS_AG" completed)"
if grep -q 'killed=1 survived=0' <<<"$OUT" && grep -q 'killed=1 survived=0' <<<"$OUT2"; then
  ok "first-case kill scores killed=1 with early exit on AND off"
else
  bad "(ag/first) verdicts differ between the early-exit and the full run"
  printf '%s\n' "$OUT" | tail -3; printf '%s\n' "$OUT2" | tail -3
fi
if [[ "$EARLY_DONE" -eq 1 && "$FULL_DONE" -eq 2 ]]; then
  ok "the early-exit run did NOT run the killer to completion ($EARLY_DONE vs $FULL_DONE completions)"
else
  bad "(ag/first) completions: early=$EARLY_DONE full=$FULL_DONE (want 1 and 2 — the precheck completes either way)"
fi
if grep -q 'early exit (first' <<<"$OUT"; then
  ok "the early exit is NAMED in the log, not a silent kill"
else
  bad "(ag/first) no 'early exit' line — an unlogged early kill is indistinguishable from a real one"
fi

FX="$TMPROOT/fxagl$RANDOM$RANDOM"
make_early_fixture "$FX" last "$OBS_AG"
obs_reset "$OBS_AG"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"
L_REACH="$(obs_count "$OBS_AG" reached)"; L_DONE="$(obs_count "$OBS_AG" completed)"
obs_reset "$OBS_AG"
OUT2="$( cd "$FX" && adv env MUTATION_SWEEP_EARLY_EXIT=0 bash "$SWEEP" --mode full 2>&1 )"
LF_DONE="$(obs_count "$OBS_AG" completed)"
if grep -q 'killed=1 survived=0' <<<"$OUT" && grep -q 'killed=1 survived=0' <<<"$OUT2"; then
  ok "last-case kill scores killed=1 with early exit on AND off"
else
  bad "(ag/last) verdicts differ between the early-exit and the full run"
  printf '%s\n' "$OUT" | tail -3; printf '%s\n' "$OUT2" | tail -3
fi
if [[ "$L_REACH" -eq 2 && "$L_DONE" -eq 1 && "$LF_DONE" -eq 2 ]]; then
  ok "a kill announced at the LAST case still cuts the tail (reached=$L_REACH, completed=$L_DONE vs $LF_DONE)"
else
  bad "(ag/last) reached=$L_REACH completed=$L_DONE full-completed=$LF_DONE (want 2, 1, 2)"
fi

# The invariant the whole trigger rests on, asserted per run rather than measured once. A
# suite that PASSES while printing the trigger would have every mutant of its guard scored
# KILLED on prose, so it is an unrunnable pair — the same class as a suite that cannot run at
# all, and for the same reason: neither can be allowed to report its guard as fully killed.
FX="$TMPROOT/fxagn$RANDOM$RANDOM"
make_early_fixture "$FX" noisy "$OBS_AG"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -ne 0 ]] && grep -q "unrunnable pair.*while PASSING" <<<"$OUT"; then
  ok "a green suite that prints the trigger is a named unrunnable pair, and reds"
else
  bad "(ag/noisy) rc=$RC — a green suite printing the trigger must red as an unrunnable pair"
  printf '%s\n' "$OUT" | tail -3
fi
if grep -qE 'guard\.sh	swept	\./guard-selftest\.sh	0	0	0' <<<"$OUT"; then
  ok "its mutants are NOT scored — no verdict is derived from prose"
else
  bad "(ag/noisy) the guard's mutants were scored anyway; early exit read fixture prose as a verdict"
  printf '%s\n' "$OUT" | tail -3
fi

echo "(ah) sandbox disk is reclaimed on every exit path, the killer's own reaps included"
# Runs the (z) spin shape — the path where the killer is SIGKILLed rather than reaped
# politely — under a TMPDIR this case owns, so "nothing left behind" is an assertion about
# an empty directory rather than about a grep of `df`.
FX="$TMPROOT/fxah$RANDOM$RANDOM"
make_spin_fixture "$FX"
SCRATCH="$TMPROOT/scratch-ah"
mkdir -p "$SCRATCH"
( cd "$FX" && adv env TMPDIR="$SCRATCH" MUTATION_SWEEP_KILLER_TIMEOUT_S=5 \
    bash "$SWEEP" --mode full ) >/dev/null 2>&1 </dev/null
LEFT="$(find "$SCRATCH" -mindepth 1 2>/dev/null | grep -c '')"
WT="$( cd "$FX" && git worktree list 2>/dev/null | grep -c '' )"
if [[ "$LEFT" -eq 0 ]]; then
  ok "no sandbox, workdir or killer scratch survived the run"
else
  bad "(ah) $LEFT path(s) left under TMPDIR after the run:"; find "$SCRATCH" -mindepth 1 | head -5
fi
if [[ "$WT" -eq 1 ]]; then
  ok "the fixture repo is back to one worktree"
else
  bad "(ah) $WT worktrees registered after the run (want 1)"; ( cd "$FX" && git worktree list ) | head -5
fi

echo "(ai) the cache is INERT in the enforcing lane — neither read nor written"
# A user-answered decision (D-2), and the only thing keeping the deliberately narrow key
# honest: a third file the suite merely SOURCES can flip a verdict with the guard and its
# suites byte-identical, so a stale entry must never be able to reach the authoritative lane.
FX="$(new_fixture weak)"
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)"
CD="$TMPROOT/cache-ai"
rm -rf "$CD"
OUT="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"
N_ADV="$(find "$CD" -type f 2>/dev/null | grep -c '')"
OUT2="$( cd "$FX" && env GITHUB_ACTIONS=1 RUNNER_OS=Linux SKIP_STRESS=1 \
          MUTATION_SWEEP_CACHE=1 MUTATION_SWEEP_CACHE_DIR="$CD" bash "$SWEEP" --mode full 2>&1 )"
C2="$(computed "$OUT2")"
N_ENF="$(find "$CD" -type f 2>/dev/null | grep -c '')"
if [[ "${N_ADV:-0}" -gt 0 ]]; then
  ok "the advisory run populated the cache ($N_ADV entr(y|ies))"
else
  bad "(ai) the advisory run wrote nothing, so the enforcing assertions below prove nothing"
fi
if grep -q 'cache disabled in the enforcing lane' <<<"$OUT2"; then
  ok "the enforcing run says the cache is off"
else
  bad "(ai) the enforcing run did not disarm the cache"
fi
if [[ "${C2:-0}" -gt 0 ]]; then
  ok "the enforcing run recomputed every verdict — it read nothing"
else
  bad "(ai) the enforcing run served ${C2:-?} computed verdicts, so it READ the advisory cache"
fi
if [[ "$N_ENF" -eq "$N_ADV" ]]; then
  ok "the enforcing run wrote nothing — entry count unchanged at $N_ENF"
else
  bad "(ai) entry count moved $N_ADV -> $N_ENF, so the enforcing run WROTE to the cache"
fi

echo "(aj) pool disagreement — a survivor the serial oracle kills is a named harness red, never a coverage gap"
# The nightly reded twice in one run on mutants the guards' own selftests demonstrably kill, and
# a baseline row would have permanently blinded the sweep to a real regression at both sites. So
# a survivor that would red the lane is re-derived serially, outside the pool, before it is
# allowed to red anything.
OBS_AJ="$TMPROOT/obs-aj"
FX="$TMPROOT/fxaj$RANDOM$RANDOM"
make_flaky_fixture "$FX" "$OBS_AJ"
baseline_with "$FX"
obs_reset "$OBS_AJ"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$TMPROOT/aj.tsv" 2>&1 )"; RC=$?
RUNS="$(obs_count "$OBS_AJ" mutrun)"
if [[ $RC -eq 1 ]] \
  && grep -q 'pool disagreement' <<<"$OUT" \
  && ! grep -q 'baseline-absent survivor' <<<"$OUT"; then
  ok "the flip reds as 'pool disagreement' and NOT as a coverage gap"
else
  bad "(aj1) expected rc=1 + pool disagreement + no baseline-absent survivor; got rc=$RC"
  printf '%s\n' "$OUT" | tail -6
fi
# Two observations of the mutant and no more: one by the pool, one by the oracle. Fewer means
# the re-verify never ran; more means it ran per killer, or twice, and "exactly one re-run" is
# what makes a single disagreement proof rather than a vote.
if [[ "${RUNS:-0}" -eq 2 ]]; then
  ok "the mutant was scored exactly twice — pool once, serial oracle once"
else
  bad "(aj2) the mutated guard's killer ran ${RUNS:-?} time(s), want exactly 2"
fi
if [[ "$(report_row "$TMPROOT/aj.tsv" guard.sh)" == "1/0/" ]]; then
  ok "the report carries the CORRECTED verdict: killed=1 survived=0, no survivor id"
else
  bad "(aj3) report row is '$(report_row "$TMPROOT/aj.tsv" guard.sh)', want '1/0/'"
fi

# The other direction, and the one that matters more: a genuine survivor must be untouched by
# the oracle. If the re-verify could overturn this, the gate would be suppressing findings.
FX="$(new_fixture weak)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$TMPROOT/aj-agree.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && grep -q 'baseline-absent survivor' <<<"$OUT" \
  && grep -q 'serial re-run agrees' <<<"$OUT" \
  && ! grep -q 'pool disagreement' <<<"$OUT" \
  && [[ "$(report_row "$TMPROOT/aj-agree.tsv" guard.sh)" == "0/1/$(sid_for "$FX" guard.sh fail-open 1)" ]]; then
  ok "a real survivor survives the oracle and still reds as baseline-absent"
else
  bad "(aj4) expected the survivor to stand; rc=$RC row='$(report_row "$TMPROOT/aj-agree.tsv" guard.sh)'"
  printf '%s\n' "$OUT" | tail -6
fi

# Free on a green run. A baselined survivor never reds, so it is never re-verified: 2 is the
# whole run's paired-suite budget (1 precheck + 1 mutant), the same number this fixture cost
# before the oracle existed.
FX="$(new_fixture weak)"
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
C="$(computed "$OUT")"
if [[ $RC -eq 0 ]] && [[ "${C:-0}" -eq 2 ]] \
  && ! grep -q 're-verifying survivor serially' <<<"$OUT"; then
  ok "a run with nothing that would red pays zero extra paired-suite executions"
else
  bad "(aj5) expected rc=0 and exactly 2 computed verdicts with no re-verify; got rc=$RC computed=${C:-?}"
  printf '%s\n' "$OUT" | tail -4
fi

# Seed is the one lane that would write a fabricated survivor into the committed baseline
# permanently and silently, and it exits via its own artifact block BEFORE the exit contract is
# reached — so the ordering assertion is the whole point: the corrected verdict has to be in
# hand before the file is written, not after.
OBS_AJ2="$TMPROOT/obs-aj-seed"
FX="$TMPROOT/fxajs$RANDOM$RANDOM"
make_flaky_fixture "$FX" "$OBS_AJ2"
obs_reset "$OBS_AJ2"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed \
        --baseline-out "$FX/seeded.tsv" --slow-out "$FX/slow.tsv" 2>&1 )"; RC=$?
SEEDED="$(grep -v '^#' "$FX/seeded.tsv" 2>/dev/null | grep -c '')"
if [[ $RC -eq 0 ]] \
  && grep -q 'pool disagreement' <<<"$OUT" \
  && [[ "${SEEDED:-1}" -eq 0 ]]; then
  ok "seed re-verifies before it writes: the fabricated survivor never reaches the baseline"
else
  bad "(aj6) seed wrote ${SEEDED:-?} survivor row(s); rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

# Cache coherence. The corrected verdict must overwrite the pool's own entry, or the next
# advisory run replays the lie from cache and the oracle never gets a chance to speak.
OBS_AJ3="$TMPROOT/obs-aj-cache"
FX="$TMPROOT/fxajc$RANDOM$RANDOM"
make_flaky_fixture "$FX" "$OBS_AJ3"
baseline_with "$FX"
CD="$TMPROOT/cache-aj"
rm -rf "$CD"
obs_reset "$OBS_AJ3"
OUT="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full 2>&1 )"; RC=$?
OUT2="$( cd "$FX" && cch "$CD" bash "$SWEEP" --mode full --report "$TMPROOT/aj-warm.tsv" 2>&1 )"; RC2=$?
if [[ $RC -eq 1 ]] && grep -q 'pool disagreement' <<<"$OUT" \
  && [[ $RC2 -eq 0 ]] \
  && [[ "$(report_row "$TMPROOT/aj-warm.tsv" guard.sh)" == "1/0/" ]] \
  && [[ "$(served "$OUT2")" -gt 0 ]]; then
  ok "the flipped verdict overwrote its cache record — the warm run is served KILLED"
else
  bad "(aj7) warm run rc=$RC2 row='$(report_row "$TMPROOT/aj-warm.tsv" guard.sh)' served='$(served "$OUT2")'"
  printf '%s\n' "$OUT2" | tail -6
fi

echo "(ak) budget darkness is REPORTED — a site past k is named, not silently absent"
# The defect this closes is not that k=2 leaves sites dark; it is that the report could not
# SAY so. A guard with no applicable site for an operator and a guard whose sites all sit
# past the budget emitted the identical empty cell, which is how a live spinning-idiom site
# stayed unswept across two nightlies without one line of evidence.
FX="$TMPROOT/fxak$RANDOM$RANDOM"
make_budget_fixture "$FX"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$TMPROOT/ak.tsv" 2>&1 )"; RC=$?
BEY_OVER="$(report_beyond "$TMPROOT/ak.tsv" over.sh)"
BEY_UNDER="$(report_beyond "$TMPROOT/ak.tsv" under.sh)"
if [[ "$BEY_OVER" == "fail-open:3" ]]; then
  ok "five sites at k=2 report the three the budget declined, named by operator"
else
  bad "(ak1) expected over.sh sites_beyond_budget='fail-open:3'; got '$BEY_OVER' (rc=$RC)"
  printf '%s\n' "$OUT" | tail -6
fi
# The counterpart is what makes the cell readable: empty must mean "nothing beyond budget"
# and not "this harness never fills the column in".
if [[ -z "$BEY_UNDER" ]]; then
  ok "a guard whose sites all fit the budget reports an empty cell"
else
  bad "(ak2) expected under.sh sites_beyond_budget empty; got '$BEY_UNDER'"
fi
# The column is DATA. Both guards are fully killed within budget, so if reporting darkness
# could red a lane this run is where it would show.
if [[ $RC -eq 0 ]] && [[ "$(report_row "$TMPROOT/ak.tsv" over.sh)" == "2/0/" ]]; then
  ok "report-only: the darkness is reported and the run is still green"
else
  bad "(ak3) expected rc=0 and over.sh 2/0/; got rc=$RC row='$(report_row "$TMPROOT/ak.tsv" over.sh)'"
  printf '%s\n' "$OUT" | tail -6
fi
# Appended LAST, checked as a header rather than inferred from the cells: report_row() reads
# $5/$6/$7 positionally and --mode merge compares shard headers byte-wise, so a column
# inserted anywhere else breaks both silently.
HDR="$(head -1 "$TMPROOT/ak.tsv")"
AK_TAB="$(printf '\t')"
AK_TAIL="${AK_TAB}survivor_ids${AK_TAB}sites_beyond_budget${AK_TAB}sites_comment_only"
if [[ "$HDR" == *"$AK_TAIL" ]]; then
  ok "the columns are appended last, in order, after survivor_ids"
else
  bad "(ak4) header does not end in survivor_ids<TAB>sites_beyond_budget<TAB>sites_comment_only: '$HDR'"
fi

echo "(al) a mutant's LITTER is not the next mutant's input — the sandbox is scrubbed between them"
# The nightly reded on this for weeks and read as flaky because the pairing re-rolls with the
# guard list: restore() reverts the one mutated TRACKED path and nothing removed the untracked
# files a killer left in the sandbox, so an earlier mutant's `mkdir` decided a later mutant's
# verdict. Deterministic per tree, which is why --jobs 1 reproduces it exactly: one worker, one
# sandbox, guards swept in ls-files order, a-dirtier before b-victim.
FX="$TMPROOT/fxal$RANDOM$RANDOM"
make_debris_fixture "$FX"
baseline_with "$FX"
OUT="$( cd "$FX" && enf env MUTATION_SWEEP_JOBS=1 bash "$SWEEP" --mode full \
        --report "$TMPROOT/al.tsv" 2>&1 )"; RC=$?
if [[ "$(report_row "$TMPROOT/al.tsv" b-victim.sh)" == "1/0/" ]]; then
  ok "the victim's mutant is KILLED on its own merits, not spared by the dirtier's leftovers"
else
  bad "(al1) b-victim.sh row is '$(report_row "$TMPROOT/al.tsv" b-victim.sh)', want '1/0/'"
  printf '%s\n' "$OUT" | tail -8
fi
# Not vacuous: the dirtier has to have been applied and scored for its litter to exist at all.
# A '0/0/' here would mean the operator matched nothing and (al1) proved only that.
if [[ "$(report_row "$TMPROOT/al.tsv" a-dirtier.sh)" == "1/0/" ]]; then
  ok "the dirtier's own mutant was applied and killed, so its mkdir really ran"
else
  bad "(al2) a-dirtier.sh row is '$(report_row "$TMPROOT/al.tsv" a-dirtier.sh)', want '1/0/'"
fi
# The oracle is the backstop, not the fix. Reaching it at all means the pool fabricated the
# survivor and the lane reds — green here has to mean the pool never got it wrong.
if [[ $RC -eq 0 ]] && ! grep -q 'pool disagreement' <<<"$OUT"; then
  ok "the run is green with no serial re-verify — the pool scored it right the first time"
else
  bad "(al3) expected rc=0 and no pool disagreement; got rc=$RC"
  printf '%s\n' "$OUT" | tail -8
fi

echo "(am) a COMMENT is not a site — it contributes no mutant AND consumes no ordinal"
# 41 of the 142 ordinal-keyed baseline rows on the tree that carried this change existed only
# to record that a comment cannot be killed, and because they took ordinals 1 and 2 they held
# 28 real code sites out of the k=2 window. This case is the falsifiable half of that claim.
FX="$TMPROOT/fxam$RANDOM$RANDOM"
make_comment_fixture "$FX"
# The expected survivor is the SECOND site the operator enumerates on cg.sh, asked for by
# ordinal — which is what --emit-site-keys resolves ordinals for. Under content keying the
# ordinal is a locator into the enumerated list, so "site 2" still names the second CODE line
# only if the comment was filtered out of that list.
CG2="$(sid_for "$FX" cg.sh fail-open 2)"
baseline_with "$FX" "$CG2"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$TMPROOT/am.tsv" 2>&1 )"; RC=$?
# THE assertion, and it still separates the correct filter from both wrong ones — by which
# LINE the survivor is, now that the id names content rather than a number. Enumerating the
# comment puts it in the k=2 window ahead of the second code line, so the surviving key is the
# comment's and the second code site is never applied at all; skipping it inside the loop
# leaves the enumerated list three long, so `sid_for … 2` resolves to the FIRST code line
# while the survivor is the second. Only the filtered list makes the two agree. The killed
# mutant carries the other half: nothing behavioural can kill a comment flip, so a killed
# first site cannot be the comment.
if [[ "$(report_row "$TMPROOT/am.tsv" cg.sh)" == "1/1/$CG2" ]]; then
  ok "the first enumerated site is the code line (killed) and the second code site survives"
else
  bad "(am1) cg.sh row is '$(report_row "$TMPROOT/am.tsv" cg.sh)', want '1/1/$CG2'"
  printf '%s\n' "$OUT" | tail -6
fi
# Two code sites, budget 2: the comment is not merely unmutated, it is not competing for the
# budget either. Enumerating it would push the second code site past k and fill this cell.
if [[ "$(report_applied "$TMPROOT/am.tsv" cg.sh)" == "2" ]] \
  && [[ -z "$(report_beyond "$TMPROOT/am.tsv" cg.sh)" ]]; then
  ok "both code sites fit the budget the comment used to displace them from"
else
  bad "(am2) cg.sh applied='$(report_applied "$TMPROOT/am.tsv" cg.sh)' beyond='$(report_beyond "$TMPROOT/am.tsv" cg.sh)'; want 2 and empty"
fi
# AC-7's conflation, closed the same way sites_beyond_budget closed its own: an operator whose
# every matched line was a comment and an operator with no matched line contribute the same
# nothing, and the report has to say which.
CO="$(report_comment_only "$TMPROOT/am.tsv" co.sh)"
CN="$(report_comment_only "$TMPROOT/am.tsv" cn.sh)"
if [[ "$CO" == "fail-open:1" && -z "$CN" ]]; then
  ok "an all-comment operator is named; a genuinely inapplicable one stays empty"
else
  bad "(am3) sites_comment_only: co.sh='$CO' (want 'fail-open:1'), cn.sh='$CN' (want empty)"
  printf '%s\n' "$OUT" | tail -6
fi
# Report-only, never red — the posture both tally columns share. The one baselined survivor is
# the only thing standing between this run and rc=0.
if [[ $RC -eq 0 ]]; then
  ok "report-only: the exclusion is reported and the run is still green"
else
  bad "(am4) expected rc=0; got rc=$RC"
  printf '%s\n' "$OUT" | tail -6
fi

# ---------------------------------------------------------------- content keying
# A guard whose matched lines are chosen to exercise the key function's whole contract:
#   alpha/beta  two lines that NORMALIZE IDENTICALLY but are not byte-identical (they differ
#               only in indentation) — the shape that collides if the occurrence index ranges
#               over the byte-identical class while the hash ranges over the normalized one.
#   gamma       a line unique to itself, so moving its block cannot change anybody's index.
# The killer only ever walks the happy path, so all three sites survive and the REPORT names
# every id — which is what makes these cases assert on the sweep's own output rather than on
# --emit-site-keys alone.
make_keying_fixture() {
  local dir="$1"
  mkdir -p "$dir/tools"
  cat > "$dir/guard.sh" <<'EOF'
#!/usr/bin/env bash
alpha() {
  [[ "${1:-}" == "bad" ]] && exit 1
}
beta() {
    [[ "${1:-}" == "bad" ]] && exit 1
}
gamma() {
  [[ "${1:-}" == "ugly" ]] && exit 1
}
alpha "${1:-}"
beta "${1:-}"
gamma "${1:-}"
echo ok
exit 0
EOF
  chmod 755 "$dir/guard.sh"
  cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}

# k is raised for these three cases so every site is swept and therefore NAMED in the report.
# At k=2 an inserted site would push a real one out of the window, and the resulting change in
# the survivor set would be the BUDGET moving rather than an identity moving — which is the
# distinction these cases exist to make.
keying_run() { # $1=fixture, $2=report path -> report written, stdout is the run log
  ( cd "$1" && adv env MUTATION_SWEEP_K=9 bash "$SWEEP" --mode full --report "$2" 2>&1 )
}

echo "(an) inserting a killable site ABOVE an existing one re-keys nothing"
# The defect this replaces the whole keying model for. With positional ids every row below the
# insertion point moved, so an edit that changed nothing about a mutant still obliged its PR to
# re-baseline — the coupling that froze the gate and left #543 unresolvable at PR time.
# DIFFERENTIAL by construction: the ids from the pre-edit run are the expectation, so nothing
# here re-implements the key function.
FX="$TMPROOT/fxan$RANDOM$RANDOM"
make_keying_fixture "$FX"
OUT="$(keying_run "$FX" "$TMPROOT/an-before.tsv")"
BEFORE="$(survivor_set "$TMPROOT/an-before.tsv" guard.sh)"
# The same guard with ONE new matched line above every existing one, normalizing to something
# no other site does. Rewritten whole rather than sed -i'd: the in-place flag and the `a\`
# append form are both BSD/GNU dialect splits, and this suite runs on the macOS lane.
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${GUARD_PREFLIGHT:-}" == "no" ]] && exit 1
alpha() {
  [[ "${1:-}" == "bad" ]] && exit 1
}
beta() {
    [[ "${1:-}" == "bad" ]] && exit 1
}
gamma() {
  [[ "${1:-}" == "ugly" ]] && exit 1
}
alpha "${1:-}"
beta "${1:-}"
gamma "${1:-}"
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
fx_commit "$FX" insert-above
OUT2="$(keying_run "$FX" "$TMPROOT/an-after.tsv")"
AFTER="$(survivor_set "$TMPROOT/an-after.tsv" guard.sh)"
KEPT="$(comm -12 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | grep -c .)"
NBEFORE="$(printf '%s\n' "$BEFORE" | grep -c .)"
NAFTER="$(printf '%s\n' "$AFTER" | grep -c .)"
if [[ "$NBEFORE" -eq 3 && "$NAFTER" -eq 4 && "$KEPT" -eq 3 ]]; then
  ok "all 3 pre-existing ids survive an insertion above them; only the new site is new"
else
  bad "(an) before=$NBEFORE after=$NAFTER unchanged=$KEPT (want 3/4/3)"
  printf 'before:\n%s\nafter:\n%s\n' "$BEFORE" "$AFTER"; printf '%s\n' "$OUT2" | tail -4
fi

echo "(ao) MOVING a block, indentation changed, re-keys nothing"
# Whitespace normalization is what buys this, and it is not decoration: relocating a block into
# or out of a function body changes its indentation without changing what it does. `git
# patch-id`, the repo's other content hash, cannot deliver it — it hashes the hunk's CONTEXT
# lines, so a block re-keys when a NEIGHBOUR moves.
FX="$TMPROOT/fxao$RANDOM$RANDOM"
make_keying_fixture "$FX"
OUT="$(keying_run "$FX" "$TMPROOT/ao-before.tsv")"
BEFORE="$(survivor_set "$TMPROOT/ao-before.tsv" guard.sh)"
# gamma's block moves to the top of the file AND is re-indented from 2 spaces to 6. Its own
# line is unique to it, so nothing's occurrence index moves either: the edit is purely
# positional, which is exactly what must cost nothing.
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
gamma() {
      [[ "${1:-}" == "ugly" ]] && exit 1
}
alpha() {
  [[ "${1:-}" == "bad" ]] && exit 1
}
beta() {
    [[ "${1:-}" == "bad" ]] && exit 1
}
alpha "${1:-}"
beta "${1:-}"
gamma "${1:-}"
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
fx_commit "$FX" move-and-reindent
# The re-indented line, byte for byte — the assertion below reads it back off disk so the case
# fails loudly if the heredoc above ever stops producing the move it claims to.
# shellcheck disable=SC2016 # this is the FIXTURE's code, not ours
GAMMA_MOVED='      [[ "${1:-}" == "ugly" ]] && exit 1'

OUT2="$(keying_run "$FX" "$TMPROOT/ao-after.tsv")"
AFTER="$(survivor_set "$TMPROOT/ao-after.tsv" guard.sh)"
if [[ -n "$BEFORE" && "$BEFORE" == "$AFTER" ]] \
  && [[ "$(sed -n '2p' "$FX/guard.sh")" == "gamma() {" ]] \
  && [[ "$(sed -n '3p' "$FX/guard.sh")" == "$GAMMA_MOVED" ]]; then
  ok "the moved, re-indented block keeps its id, and so does every other site"
else
  bad "(ao) survivor set moved across a pure block move"
  printf 'before:\n%s\nafter:\n%s\n' "$BEFORE" "$AFTER"; sed -n '1,12p' "$FX/guard.sh"
fi

echo "(ap) two normalization-identical sites get DISTINCT ids; removing the first re-keys only the second"
# D-6's measured hazard, in miniature: hash the normalized line but index over the BYTE-identical
# class and alpha and beta both take index 1 over the same string — one key for two sites. 24
# such groups exist on the real tree, so getting this wrong reds `main` outright.
FX="$TMPROOT/fxap$RANDOM$RANDOM"
make_keying_fixture "$FX"
OUT="$(keying_run "$FX" "$TMPROOT/ap-before.tsv")"
BEFORE="$(survivor_set "$TMPROOT/ap-before.tsv" guard.sh)"
NDISTINCT="$(printf '%s\n' "$BEFORE" | sort -u | grep -c .)"
A1="$(sid_for "$FX" guard.sh fail-open 1)"; A2="$(sid_for "$FX" guard.sh fail-open 2)"
A3="$(sid_for "$FX" guard.sh fail-open 3)"
# alpha's whole function is deleted, taking the FIRST of the two identical lines with it.
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
beta() {
    [[ "${1:-}" == "bad" ]] && exit 1
}
gamma() {
  [[ "${1:-}" == "ugly" ]] && exit 1
}
beta "${1:-}"
gamma "${1:-}"
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
fx_commit "$FX" drop-first-identical
OUT2="$(keying_run "$FX" "$TMPROOT/ap-after.tsv")"
AFTER="$(survivor_set "$TMPROOT/ap-after.tsv" guard.sh)"
WANT="$(printf '%s\n%s\n' "$A1" "$A3" | sort)"
if [[ "$NDISTINCT" -eq 3 && "$A1" != "$A2" && "$AFTER" == "$WANT" ]]; then
  ok "the identical pair is distinguished, and deleting the first hands its key to the second"
else
  bad "(ap) distinct=$NDISTINCT a1='$A1' a2='$A2'"
  printf 'after:\n%s\nwant:\n%s\n' "$AFTER" "$WANT"; printf '%s\n' "$OUT2" | tail -4
fi

echo "(aq) two enumerated sites sharing a key is a named red — over ALL sites, not just the emitted ones"
# A real 12-hex collision is a ~2^24 birthday search, so the comparison WIDTH is the seam (it
# narrows the check only; the emitted key is always 12 hex). At one hex there are 16 buckets and
# the fixture enumerates 20 sites, so a collision is guaranteed by pigeonhole rather than by
# luck. k stays at 2, so 18 of those 20 sites are never emitted as sids — if the check ranged
# over emitted ids only, it would have nothing to find.
#
# THE CASE HAD TO BE MADE TO DISCRIMINATE, and the first version did not. With the sites labelled
# `bad01..bad20` the FIRST TWO keys happened to share their leading hex, so a check restricted to
# the emitted pair still found a collision and the restriction probe changed nothing. The labels
# are `c01..c20` for that reason, and the assertion below is not "a collision was reported" alone
# but "the reported group names a line the budget never reached" — which is the property AC-6
# actually states, and which fails loudly if the grouping ever degenerates onto the emitted pair.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURE's code, not ours
make_collide_fixture() {
  local dir="$1" i=1
  mkdir -p "$dir/tools"
  { printf '#!/usr/bin/env bash\ncase "${1:-}" in\n'
    while [[ $i -le 20 ]]; do printf '  c%02d) echo v%02d; exit 1 ;;\n' "$i" "$i"; i=$((i + 1)); done
    printf 'esac\necho ok\nexit 0\n'
  } > "$dir/g.sh"
  chmod 755 "$dir/g.sh"
  { printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
    printf 'out="$(bash "$HERE/g.sh" good)"\n[[ "$out" == "ok" ]] || exit 1\nexit 0\n'
  } > "$dir/g-selftest.sh"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n'   > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n'    > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" && git init -q . && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}
FX="$TMPROOT/fxaq$RANDOM$RANDOM"
make_collide_fixture "$FX"
baseline_with "$FX" "$(sid_for "$FX" g.sh fail-open 1)" "$(sid_for "$FX" g.sh fail-open 2)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'site-key collision' <<<"$OUT"; then
  ok "20 distinct sites do not collide at the shipped 12-hex width (the negative control)"
else
  bad "(aq1) unmutated width should be clean; rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
OUT="$( cd "$FX" && enf env MUTATION_SWEEP_SITE_KEY_CMP_HEX=1 bash "$SWEEP" --mode full 2>&1 )"; RC=$?
# g.sh is a shebang, a `case` line, then the 20 arms — so site n is line n+2 and the k=2 window
# is lines 3 and 4. A named line above 4 is a site the sweep never emitted an id for.
BEYOND_NAMED="$(sed -n 's/.*colliding lines: //p' <<<"$OUT" | tr ' ' '\n' | awk '$1 + 0 > 4' | grep -c .)"
if [[ $RC -eq 1 ]] && grep -q 'site-key collision: two enumerated sites of fail-open on g.sh' <<<"$OUT" \
  && [[ "${BEYOND_NAMED:-0}" -ge 1 ]]; then
  ok "a collision reaching past the k=2 window reds, and the red names a beyond-budget line"
else
  bad "(aq2) expected rc=1 + a collision naming a line past the budget; got rc=$RC beyond=${BEYOND_NAMED:-0}"
  printf '%s\n' "$OUT" | tail -5
fi

echo "(ar) no sha binary — the run reds by name, and only where a key is actually computed"
# Fail-closed, and LAZY. The hash used to matter only to the cache, which could disable itself;
# it now decides IDENTITY, so a run that cannot compute one must red rather than invent it. Fired
# at the first key and not at resolution time, or a doc-only PR — which enumerates nothing —
# would red on a host with neither binary.
NOSHA="$TMPROOT/nosha-bin"
mkdir -p "$NOSHA"
OLDIFS="$IFS"; IFS=:
for pdir in $PATH; do
  [[ -d "$pdir" ]] && ln -s "$pdir"/* "$NOSHA"/ 2>/dev/null
done
IFS="$OLDIFS"
rm -f "$NOSHA/shasum" "$NOSHA/sha256sum" "$NOSHA/gsha256sum" "$NOSHA/sha256"
FX="$(new_fixture weak)"
baseline_with "$FX" "$(sid_for "$FX" guard.sh fail-open 1)"
# Control FIRST: the symlink farm is a fixture, and a farm too thin to run the sweep at all
# would make the red below prove nothing.
OUT="$( cd "$FX" && adv env PATH="$NOSHA:$(dirname "$(command -v sha256sum || command -v shasum)")" \
        bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'no-sha-binary' <<<"$OUT"; then
  ok "the pruned PATH plus one sha binary runs a clean sweep (the control)"
else
  bad "(ar1) control run failed; rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi
OUT="$( cd "$FX" && adv env PATH="$NOSHA" bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q 'no-sha-binary' <<<"$OUT"; then
  ok "a sweep that must key a site reds by name with neither binary present"
else
  bad "(ar2) expected rc=1 + no-sha-binary; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi
# The green half of the same contract: PR mode with nothing in the diff computes no key.
OUT="$( cd "$FX" && adv env PATH="$NOSHA" bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && grep -q 'nothing to sweep' <<<"$OUT" && ! grep -q 'no-sha-binary' <<<"$OUT"; then
  ok "a nothing-to-sweep PR run stays green with no sha binary at all"
else
  bad "(ar3) expected a green nothing-to-sweep run; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi
# ...and so does merge, which recombines artifacts and enumerates nothing.
FXM="$TMPROOT/fxarm$RANDOM$RANDOM"
make_fleet_fixture "$FXM" 2
mkdir -p "$FXM/shards/s1"
OUT="$( cd "$FXM" && enf bash "$SWEEP" --mode full --seed --shard 1/1 \
        --report "$FXM/shards/s1/mutation-report.tsv" \
        --baseline-out "$FXM/shards/s1/mutation-baseline.tsv" \
        --slow-out "$FXM/shards/s1/mutation-slow-suites.tsv" 2>&1 )"; SRC=$?
OUT="$( cd "$FXM" && adv env PATH="$NOSHA" bash "$SWEEP" --mode merge --shards-dir "$FXM/shards" \
        --report "$FXM/m.tsv" --baseline-out "$FXM/mb.tsv" --slow-out "$FXM/ms.tsv" 2>&1 )"; RC=$?
if [[ $SRC -eq 0 && $RC -eq 0 ]] && ! grep -q 'no-sha-binary' <<<"$OUT"; then
  ok "merge mode stays green with no sha binary — it computes no keys"
else
  bad "(ar4) merge should stay green; seed_rc=$SRC merge_rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(as) a baseline written under different keying is a named red, in EVERY mode"
# Read content keys against an ordinal-keyed baseline and the run reports every row as
# now-KILLED and every survivor as baseline-absent — a doubled false signal with no clue in it.
# NOT gated on ENFORCING, unlike the environment check: a local advisory run is where the
# damage lands, because nothing re-reads it in CI.
FX="$(new_fixture weak)"
SID="$(sid_for "$FX" guard.sh fail-open 1)"
{ echo "# environment: ubuntu-latest SKIP_STRESS=1"
  echo "# k=2"
  printf '%s\tseeded\n' "$SID"
} > "$FX/tools/mutation-baseline.tsv"
AS_OK=1
for lane in adv enf; do
  OUT="$( cd "$FX" && $lane bash "$SWEEP" --mode full 2>&1 )"; RC=$?
  [[ $RC -eq 1 ]] || { AS_OK=0; bad "(as1) $lane: expected rc=1, got $RC"; }
  grep -q 'baseline-keying-mismatch' <<<"$OUT" || { AS_OK=0; bad "(as1) $lane: no named keying red"; }
  grep -q 'now KILLED' <<<"$OUT" && { AS_OK=0; bad "(as1) $lane: reported a now-KILLED row anyway"; }
  grep -q 'baseline-absent survivor' <<<"$OUT" && { AS_OK=0; bad "(as1) $lane: reported baseline-absent anyway"; }
done
[[ $AS_OK -eq 1 ]] && ok "an unkeyed baseline reds by name in both lanes, and compares no survivor"
# A header carrying the WRONG keying is the same red — the check is equality, not presence.
sed 's/^# k=2$/# k=2\n# keying: ordinal-v0/' "$FX/tools/mutation-baseline.tsv" > "$FX/tools/bl.tmp" \
  && mv "$FX/tools/bl.tmp" "$FX/tools/mutation-baseline.tsv"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && grep -q "declares '# keying: ordinal-v0'" <<<"$OUT"; then
  ok "a stale keying VALUE reds and names what the file declares"
else
  bad "(as2) expected rc=1 naming the declared keying; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
# And a shard set that disagrees fails the merge header check rather than merging into a file
# whose rows name two different identity functions.
FX="$TMPROOT/fxas$RANDOM$RANDOM"
make_fleet_fixture "$FX" 2
MOK=1
for i in 1 2; do
  mkdir -p "$FX/shards/s$i"
  OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard "$i/2" \
          --report "$FX/shards/s$i/mutation-report.tsv" \
          --baseline-out "$FX/shards/s$i/mutation-baseline.tsv" \
          --slow-out "$FX/shards/s$i/mutation-slow-suites.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 ]] || { MOK=0; bad "(as3) seed shard $i failed rc=$RC"; }
done
if [[ $MOK -eq 1 ]]; then
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards" \
          --report "$FX/m.tsv" --baseline-out "$FX/mb.tsv" --slow-out "$FX/ms.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 ]] || { MOK=0; bad "(as3) the agreeing merge should be green, got rc=$RC"; }
  sed 's/^# keying: content-v1$/# keying: content-v2/' "$FX/shards/s2/mutation-baseline.tsv" \
    > "$FX/shards/s2/bl.tmp" && mv "$FX/shards/s2/bl.tmp" "$FX/shards/s2/mutation-baseline.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards" \
          --report "$FX/m2.tsv" --baseline-out "$FX/mb2.tsv" --slow-out "$FX/ms2.tsv" 2>&1 )"; RC=$?
  if [[ $MOK -eq 1 && $RC -eq 1 ]] && grep -q 'baseline header mismatch across shards' <<<"$OUT"; then
    ok "shards disagreeing on keying fail the merge header check"
  else
    bad "(as3) expected rc=1 + a header mismatch; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
fi

echo "(at) --verdict-log — a TAB row per scored mutant, both tiers, '-' for a survivor, a cache hit logs its real killer, an unwritable path is a hard red"
FX="$(new_fixture strong)"
printf 'echo-flip\tguard.sh\ts/echo ok/echo mutated/\tan uncovered good-path echo, never checked by the strong killer\n' \
  >> "$FX/tools/mutation-catalog.tsv"
fx_commit "$FX" "add a survivable catalog row"
GSID="$(sid_for "$FX" guard.sh fail-open 1)"
CSID="catalog::echo-flip"
baseline_with "$FX" "$CSID"
OUT_NOFLAG="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC_NOFLAG=$?
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --verdict-log "$FX/vlog.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 && $RC_NOFLAG -eq $RC ]]; then
  ok "the flag is inert on the run's exit code — identical rc with and without it"
else
  bad "(at1) expected identical rc=0 with and without --verdict-log; got $RC_NOFLAG / $RC"
  printf '%s\n' "$OUT_NOFLAG" | tail -6
  printf '%s\n' "$OUT" | tail -6
fi
HDR="$(head -1 "$FX/vlog.tsv" 2>/dev/null)"
GROW="$(awk -F'\t' -v s="$GSID" '$1==s' "$FX/vlog.tsv" 2>/dev/null)"
CROW="$(awk -F'\t' -v s="$CSID" '$1==s' "$FX/vlog.tsv" 2>/dev/null)"
if [[ "$HDR" == $'mutant_id\tverdict\tkiller_suite' ]] \
  && [[ "$GROW" == "$GSID"$'\t'"killed"$'\t'"./guard-selftest.sh" ]] \
  && [[ "$CROW" == "$CSID"$'\t'"survived"$'\t'"-" ]]; then
  ok "both tiers appear, with the generic id's real killer and '-' for the catalog survivor"
else
  bad "(at2) unexpected verdict-log content — header='$HDR' generic-row='$GROW' catalog-row='$CROW'"
  printf '%s\n' "$OUT" | tail -6
fi

# A cache hit must log the killer suite out of the memoized record, not a blank.
CD="$TMPROOT/cache-at"
FXC="$(new_fixture strong)"
GSIDC="$(sid_for "$FXC" guard.sh fail-open 1)"
( cd "$FXC" && cch "$CD" bash "$SWEEP" --mode full --verdict-log "$TMPROOT/at-cold.tsv" ) >/dev/null 2>&1
OUT2="$( cd "$FXC" && cch "$CD" bash "$SWEEP" --mode full --verdict-log "$TMPROOT/at-warm.tsv" 2>&1 )"
C2="$(computed "$OUT2")"
WARMROW="$(awk -F'\t' -v s="$GSIDC" '$1==s' "$TMPROOT/at-warm.tsv" 2>/dev/null)"
if [[ "${C2:-9}" -eq 0 ]] && [[ "$WARMROW" == "$GSIDC"$'\t'"killed"$'\t'"./guard-selftest.sh" ]]; then
  ok "a cache-served kill still logs its real killer suite"
else
  bad "(at3) warm run computed=${C2:-?}, expected 0; warm row='$WARMROW'"; printf '%s\n' "$OUT2" | tail -6
fi

# An unwritable log path is a hard red, never a silent skip.
FXU="$(new_fixture strong)"
OUT="$( cd "$FXU" && adv bash "$SWEEP" --mode full --verdict-log "/no/such/dir/vlog.tsv" 2>&1 )"; RC=$?
if [[ $RC -ne 0 ]] && grep -q 'cannot write the verdict log' <<<"$OUT"; then
  ok "an unwritable --verdict-log path reds by name"
else
  bad "(at4) expected a named red for an unwritable path; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(j) universe rule — every in-universe guard in the REAL tree is accounted"
UNIV="$( cd "$REPO_ROOT" && git ls-files '*.sh' \
        | grep -v -- '-selftest\.sh$' | grep -v '/evals/' | grep -v '^tests/hooks-smoke/' | sort )"
UNACCOUNTED=""
EXCL_LIST="$(grep -v '^#' "$REPO_ROOT/tools/mutation-exclusions.tsv" | grep -v '^$' | cut -f1)"
MAP_LIST="$(grep -v '^#' "$REPO_ROOT/tools/mutation-pair-map.tsv" | grep -v '^$' | cut -f1)"
while IFS= read -r g; do
  [[ -n "$g" ]] || continue
  case $'\n'"$EXCL_LIST"$'\n' in *$'\n'"$g"$'\n'*) continue ;; esac
  same="$(dirname "$g")/$(basename "$g" .sh)-selftest.sh"
  [[ -f "$REPO_ROOT/$same" ]] && continue
  case $'\n'"$MAP_LIST"$'\n' in *$'\n'"$g"$'\n'*) continue ;; esac
  UNACCOUNTED="${UNACCOUNTED:+$UNACCOUNTED }$g"
done <<< "$UNIV"
if [[ -z "$UNACCOUNTED" ]]; then
  ok "all $(printf '%s\n' "$UNIV" | grep -c .) in-universe guards resolve"
else
  bad "(j) unaccounted guard(s) — add a same-stem suite, a pair-map row, or an exclusions row: $UNACCOUNTED"
fi
# The harness must reach the same verdict through its own accounting path.
OUT="$( cd "$REPO_ROOT" && adv bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! grep -q 'unaccounted guard' <<<"$OUT"; then
  ok "the harness's own accounting agrees"
else
  bad "(j) harness accounting disagrees with the direct lint; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

# PER-GUARD CATALOG CAP (#752). The wholesale sweep shards round-robin, so it balances guard
# COUNT and not cost and a guard's mutants are atomic to one residue class: lean-gate.sh at 56
# rows against a 212s killer killed its shard at the 45-minute step bound twice, taking six
# unrelated guards with it. 36 is a MEASUREMENT — the largest count for that guard observed to
# finish inside the bound — and a count is a proxy for rows x killer-suite seconds. Full
# derivation and the retirement criterion: docs/testing.md.
MAX_ROWS_PER_GUARD=36

# Prints `<guard> <count>`, one line per guard over the cap in $1, sorted; silent when none is.
# Split out from case (k) so case (l) can drive it against a fixture: a lint that only ever
# reads the live tree cannot be shown to still fail, and would go quietly dead the day its
# parsing broke — the failure the real tree is least able to reveal.
catalog_cap_breaches() {
  awk -F'\t' -v cap="$MAX_ROWS_PER_GUARD" '
    /^#/    { next }
    NF < 2  { next }
            { n[$2]++ }
    END     { for (g in n) if (n[g] > cap) printf "%s %d\n", g, n[g] }
  ' "$1" | LC_ALL=C sort
}

echo "(k) TSV family lint — shape and resolution of every committed mutation-*.tsv"
lint_fail() { bad "(k) $*"; }
# Exclusions: path must be in-universe, must NOT also carry pair-map rows, reason non-empty.
while IFS=$'\t' read -r p reason; do
  case "$p" in ''|'#'*) continue ;; esac
  [[ -n "$reason" ]] || lint_fail "exclusions row has no reason: $p"
  case $'\n'"$MAP_LIST"$'\n' in
    *$'\n'"$p"$'\n'*) lint_fail "excluded guard also carries pair-map rows (exclusion preempts pairing): $p" ;;
  esac
  [[ -f "$REPO_ROOT/$p" ]] || lint_fail "exclusions row path does not exist: $p"
done < "$REPO_ROOT/tools/mutation-exclusions.tsv"
# Pair map: both sides must resolve on disk, note non-empty.
while IFS=$'\t' read -r g s note; do
  case "$g" in ''|'#'*) continue ;; esac
  [[ -f "$REPO_ROOT/$g" ]] || lint_fail "pair-map guard does not exist: $g"
  [[ -f "$REPO_ROOT/$s" ]] || lint_fail "pair-map selftest does not exist: $s"
  [[ -n "$note" ]] || lint_fail "pair-map row has no note: $g -> $s"
done < "$REPO_ROOT/tools/mutation-pair-map.tsv"
# Operators: unique non-empty ids, non-empty match/flip, and every match must COMPILE as
# an ERE when passed after grep's option terminator — a match grep cannot compile
# enumerates zero sites, and the PR lane's diff scoping means the PR that commits such a
# row may never itself sweep a guard, so this per-push lint is the row's first executable
# check.
SEEN_OPS=""
while IFS=$'\t' read -r id m f; do
  case "$id" in ''|'#'*) continue ;; esac
  [[ -n "$m" && -n "$f" ]] || lint_fail "operator '$id' has an empty match or flip"
  case " $SEEN_OPS " in *" $id "*) lint_fail "duplicate operator id: $id" ;; esac
  SEEN_OPS="$SEEN_OPS $id"
  printf '' | grep -qE -- "$m" 2>/dev/null
  [[ $? -le 1 ]] || lint_fail "operator '$id' match is not a grep -E-compilable pattern: $m"
done < "$REPO_ROOT/tools/mutation-operators.tsv"
[[ -n "$SEEN_OPS" ]] || lint_fail "no operators defined"
# Catalog: unique ids, guard in-universe and not excluded, sed non-empty, PATTERN-addressed
# (D-3 — a bare line address is not permitted; the emit-deadline site moved between two
# runs of this very ticket, and only the pattern-addressed entries survived it).
if [[ -f "$REPO_ROOT/tools/mutation-catalog.tsv" ]]; then
  SEEN_CAT=""
  while IFS=$'\t' read -r id g sd note; do
    case "$id" in ''|'#'*) continue ;; esac
    case " $SEEN_CAT " in *" $id "*) lint_fail "duplicate catalog id: $id" ;; esac
    SEEN_CAT="$SEEN_CAT $id"
    [[ -n "$sd" ]] || lint_fail "catalog row '$id' has an empty sed"
    [[ -n "$note" ]] || lint_fail "catalog row '$id' has no note"
    [[ -f "$REPO_ROOT/$g" ]] || lint_fail "catalog guard does not exist: $g (row $id)"
    case $'\n'"$EXCL_LIST"$'\n' in
      *$'\n'"$g"$'\n'*) lint_fail "catalog row '$id' targets an EXCLUDED guard: $g" ;;
    esac
    case "$sd" in
      [0-9]*) lint_fail "catalog row '$id' uses a bare line address — D-3 requires a pattern address" ;;
    esac
  done < "$REPO_ROOT/tools/mutation-catalog.tsv"
fi
# The cap itself. Reported per guard rather than as one aggregate: the count is the actionable
# half — "retire n rows" — and an aggregate would name the file rather than the guard to fix.
while read -r cap_g cap_n; do
  [[ -n "$cap_g" ]] || continue
  lint_fail "guard carries $cap_n catalog rows, over the per-guard cap of $MAX_ROWS_PER_GUARD: $cap_g"
done <<< "$(catalog_cap_breaches "$REPO_ROOT/tools/mutation-catalog.tsv")"
# Slow suites: selftest resolves, seconds numeric, measured_at ISO-8601.
if [[ -f "$REPO_ROOT/tools/selftest-suite-timings.tsv" ]]; then
  while IFS=$'\t' read -r s secs when; do
    case "$s" in ''|'#'*) continue ;; esac
    [[ -f "$REPO_ROOT/$s" ]] || lint_fail "slow-suites selftest does not exist: $s"
    case "$secs" in ''|*[!0-9]*) lint_fail "slow-suites seconds is not an integer: $s -> '$secs'" ;; esac
    case "$when" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
      *) lint_fail "slow-suites measured_at is not ISO-8601: $s -> '$when'" ;;
    esac
  done < "$REPO_ROOT/tools/selftest-suite-timings.tsv"
fi
# No suite in the REAL corpus may redirect to a literal path outside its own mktemp tree.
# That is the concurrency hazard the pool made reachable: two mutants of one guard run the
# same suite AT THE SAME TIME, and a fixed path turns their interleaved write-then-read into
# a mutation verdict about the wrong mutant. Three suites carried exactly this shape and were
# fixed to write under their own $TMP; this lint is what stops a fourth arriving, because the
# symptom would otherwise be flake in somebody's nightly rather than a failure here.
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  hits="$(grep -cE '(>|>>)[[:space:]]*"?/(var/)?tmp/' "$REPO_ROOT/$f" 2>/dev/null)"
  [[ "${hits:-0}" -eq 0 ]] \
    || lint_fail "selftest redirects to a literal /tmp path, which races a concurrent sibling under the mutant pool: $f"
done <<< "$(cd "$REPO_ROOT" && git ls-files '*-selftest.sh')"
# Baseline: header present, survivor ids well-formed.
if [[ -f "$REPO_ROOT/tools/mutation-baseline.tsv" ]]; then
  grep -q '^# environment: ' "$REPO_ROOT/tools/mutation-baseline.tsv" || lint_fail "baseline has no '# environment:' header"
  grep -q '^# k=' "$REPO_ROOT/tools/mutation-baseline.tsv" || lint_fail "baseline has no '# k=' header"
  # The keying header is what the sweep compares its own identity function against, so a
  # committed baseline missing it is a file every run would red on.
  grep -q '^# keying: content-v1$' "$REPO_ROOT/tools/mutation-baseline.tsv" \
    || lint_fail "baseline has no '# keying: content-v1' header"
  while IFS=$'\t' read -r sid _; do
    case "$sid" in ''|'#'*) continue ;; esac
    case "$sid" in
      catalog::*) : ;;
      # Generic ids carry a 12-hex CONTENT key in the third segment. A surviving ordinal
      # (`::1`) is what an un-migrated row looks like, and it would silently compare against
      # nothing for the life of the file.
      *::*::*)
        k="${sid##*::}"
        case "$k" in
          [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
          *) lint_fail "baseline survivor id is not content-keyed (want 12 hex): $sid" ;;
        esac
        ;;
      *) lint_fail "malformed baseline survivor id: $sid" ;;
    esac
  done < "$REPO_ROOT/tools/mutation-baseline.tsv"
fi
[[ $FAILS -eq 0 ]] && ok "TSV family is well-formed and resolves"

echo
echo "(l) per-guard catalog cap — case (k)'s cap arm, driven against a fixture catalog"
# Case (k) reads the live tree, which is the right binding for "is the committed catalog legal"
# and the wrong one for "does this arm still fail" — the live tree is legal by construction the
# moment it is fixed, so a broken extractor and a compliant catalog are indistinguishable there.
# These two fixtures separate them, and they are the same function case (k) calls, not a copy.
CAPFX="$TMPROOT/cap"
mkdir -p "$CAPFX"
{
  printf '# fixture catalog\n'
  cap_i=1
  while [[ $cap_i -le $MAX_ROWS_PER_GUARD ]]; do
    printf 'row-%s\ttools/at-cap.sh\ts/a/b/\tnote\n' "$cap_i"
    cap_i=$((cap_i + 1))
  done
} > "$CAPFX/at-cap.tsv"
# One over, plus a second guard well under it: the breach must name the offender alone.
cp "$CAPFX/at-cap.tsv" "$CAPFX/over-cap.tsv"
{
  printf 'row-over\ttools/at-cap.sh\ts/a/b/\tnote\n'
  printf 'other-1\ttools/small.sh\ts/a/b/\tnote\n'
  printf 'other-2\ttools/small.sh\ts/a/b/\tnote\n'
} >> "$CAPFX/over-cap.tsv"

CAP_AT="$(catalog_cap_breaches "$CAPFX/at-cap.tsv")"
if [[ -z "$CAP_AT" ]]; then
  ok "a guard at exactly $MAX_ROWS_PER_GUARD rows draws no breach"
else
  bad "(l1) expected silence at exactly $MAX_ROWS_PER_GUARD rows; got '$CAP_AT'"
fi

CAP_OVER="$(catalog_cap_breaches "$CAPFX/over-cap.tsv")"
if [[ "$CAP_OVER" == "tools/at-cap.sh $((MAX_ROWS_PER_GUARD + 1))" ]]; then
  ok "one row over names the offending guard and its count, and only that guard"
else
  bad "(l2) expected 'tools/at-cap.sh $((MAX_ROWS_PER_GUARD + 1))'; got '$CAP_OVER'"
fi

echo
if [[ $FAILS -eq 0 ]]; then
  echo "[mutation-sweep-selftest] all cases passed"
else
  echo "[mutation-sweep-selftest] $FAILS case(s) failed"
fi
exit "$FAILS"
