# lean review verdict — #419

verdict=needs-work
run_id: review-419-1
session_id: 4fa92bd6-ff8e-4521-91b1-eb5d3db41c80
rounds: 1
pr: #425
reviewed_head: 274d9e9aaab93b290346e8cf2f80a82920c03f7c
reviewed_patch_id: 07223b3894d88227f047fe90c98403f182b7c02d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full-branch range (`bash G delta 419` printed `a2b158f..HEAD` — chain root, nothing to inherit).

The fixes are right and I verified both of them independently. The guard is real and non-vacuous —
I put main's pre-fix suites back under its topology and both go red, with the exact #419 symptom
(`FAIL: (pl-n3) ghost path — rc=0`, rc=1) and the exact sibling ENOENT (rc=2). It also found two
more members of its own class on CI, unprompted, which is the best evidence anyone could ask for
that it belongs in the tree.

What it has not done is land green. The branch reds both selftest lanes, and the known-red list
was seeded from a run whose environment hid the two failures the guard now reports. I reproduced
that directly: the guard is **`0 red` on this machine and `2 red` on both CI lanes, same commit**.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `tools/install-topology-known-red.tsv` | Two suites fail under the guard with no row, on **both** CI lanes. The guard is the only failing suite in either lane, so it is the whole red build. |
| B2 | blocker | AC-7, `docs/testing.md`, PR body | The seeded counts are stated as measured and are false off the authoring machine. AC-7 asserts `cost-block-selftest.sh` passes; CI measures rc=1 twice. |
| B3 | blocker | `preflight-selftest.sh:38` | A class-B fixed hop (`$SCRIPT_DIR/../../../../review-toolkit`) that the guard correctly caught and the seeding run masked via the `claude` CLI being on the author's PATH. Reproduced both directions. |
| B4 | blocker | `cost-block-selftest.sh` | Reds on both CI lanes, passes standing alone here — cause undiagnosed, so no honest row can be written for it yet. |
| B5 | blocker | PR body | Still carries the D-8 `until ! pgrep -f` waiter premise the committed spec retracts. |
| W1 | warning | `install-topology-selftest.sh:55` | The 600s bound converts ambient machine load into a red; a third distinct red set on a third run of the same tree. |
| W2 | warning | `install-topology-selftest.sh:79-94` | The watchdog leaks one `sleep $SUITE_TIMEOUT` per suite — 55 orphans reported by CI's runner. |
| W3 | warning | `design-sync-selftest.mjs:42,52` | A hand-maintained copy of `resolve_sibling()` with only prose keeping the two in step, and no `scripts/lockstep-manifest.tsv` row (or DROPPED entry). |
| W4 | warning | `install-topology-selftest.sh:224` | A listed `.mjs` suite skipped for absent `node` also reports as a stale row — two warnings, one cause, and the "shrink the list" signal points the wrong way. |
| W5 | nit | `install-topology-selftest.sh:37` | `SELF` hardcodes the filename instead of using the already-resolved `${BASH_SOURCE[0]}`. |

### B1 — the branch reds both CI lanes (blocker)

Run 31127616715, head `274d9e9`. Identical on `lint-and-selftests` (ubuntu) and
`selftests (macos, bash 3.2)`:

```
RED:   plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh — rc=1 — FAIL run A produced no valid rollup JSON
RED:   plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh — rc=1 — [self-test] FAIL section lint surfaces at preflight (clean review-context)
[install-topology] summary: 55 ran, 49 passed, 4 known-red, 0 skipped, 0 stale row(s), 2 red
```

`install-topology-selftest.sh` is the only suite that fails the outer sweep in either lane — the
guard is the entire red. Milestone 3's green gate cannot be satisfied as the branch stands.

Run uncontended on this machine at the same commit, it is green:

```
[install-topology] summary: 55 ran, 51 passed, 4 known-red, 0 skipped, 0 stale row(s), 0 red
```

Same tree, same guard, opposite verdict. That gap is the finding, not the two rows.

### B2 — the seeded counts are a measurement that does not hold (blocker)

Three artifacts carry the same number from the same run:

- AC-7's parenthetical: *"`cost-block-selftest.sh` likewise passes here, because AC-4's cwd is a
  real git-init'd directory it can write under."*
- `docs/testing.md`: *"Its first run scored 55 suites: 51 pass, 4 listed."*
- PR body: *"First run of the guard — 55 suites, 51 pass, 4 listed, 0 red"*.

CI scores 49 pass / 2 red, twice. OR-1's default was to seed from *the guard's first clean run*;
the run used was clean only on the machine that produced it, which is precisely the property the
guard exists to make visible. The counts need re-deriving from a run whose environment is not the
authoring one, and AC-7's cost-block sentence has to go or invert.

### B3 — `preflight-selftest.sh` is a true positive the seeding masked (blocker)

`plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh:38`:

```sh
RT_TEST_ROOT="$(cd "$SCRIPT_DIR/../../../../review-toolkit" 2>/dev/null && pwd || true)"
```

A fixed hop count — the same class as the `design-sync-selftest.mjs` defect AC-3 fixes. From a
version-keyed cache it resolves to nothing, so line 114's `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT=""`
sends `preflight.sh:144-147` to its `claude plugin list` rung. That rung hits on a machine with
the `claude` CLI and review-toolkit installed, and misses on CI.

Reproduced, staging this branch's dev-pipeline at `<root>/dev-pipeline/4.0.0/` with cwd a
git-init'd consumer dir:

```
=== preflight-selftest.sh, ALONE, staged, consumer cwd ===
[self-test] ok   ...                                   # green

=== same, with the claude CLI hidden from PATH ===
[self-test] FAIL section lint surfaces at preflight (clean review-context)
[self-test] FAIL context-coverage line surfaces (exit-neutral)
```

The second line is CI's exact failure. Either fix is fine by me — mirror the AC-3 ladder, or list
it with this cause — but not "leave it unlisted and red".

### B4 — `cost-block-selftest.sh` is red on CI and green here; cause unknown (blocker)

Standing alone under the same staged topology it passes **34/34**, and resolves its state dir to
`<consumer>/.claude/pipeline-state` — i.e. inside the guard's *shared* consumer cwd.

That shared cwd is worth a look while diagnosing. `run_bounded` gives every worker the same
`$CONSUMER`, up to `INSTALL_TOPOLOGY_JOBS` (default 4) at a time, and three staged suites resolve
their state dir from cwd's git-common-dir — `cost-block-selftest.sh:40-42`,
`stage-envelopes-selftest.sh`, `gh-bot-selftest.sh`. The guard's own comment (line 191) says the
suites "are independent (each allocates its own mktemp state dir)"; for those three, under one
shared cwd, that is not true. I could **not** reproduce a collision, so I am not asserting it is
the cause — but until something is, a row for this suite reading anything other than
`undiagnosed` would be the invented rationale OR-1's flag forbids.

### B5 — the PR body repeats a premise the spec retracts (blocker, cheap)

PR body: *"`INSTALL_TOPOLOGY_TIMEOUT` (default 600s) exists because `statectl-selftest.sh`'s
`until ! pgrep -f` waiter deadlocks against a second matching copy"*.

The committed spec retracts exactly that ("One D-8 premise did not survive contact with the
tree") and says the guard and `docs/testing.md` state the real reason and *"neither repeats the
waiter claim"*. The script (lines 46-49) and the doc both honor that; the PR body does not, and
it is the artifact a reader meets first. Replace it with the contention measurement the decision
actually stands on.

### W1 — the bound turns ambient load into a red

On this machine, the stress-inclusive `-P 4` sweep over the branch produced:

```
RED:   plugins/dev-pipeline/skills/run/statectl-selftest.sh — timed out after 600s (bound, not a hang)
[install-topology] summary: 55 ran, 50 passed, 4 known-red, 0 skipped, 0 stale row(s), 1 red
```

with `install-topology-selftest.sh` the only failing suite (`selftests rc=1`; `shellcheck rc=0`,
`jq empty rc=0`). This is heavier than CLAUDE.md's documented `env SKIP_STRESS=1` form, so it is
not a claim that the documented command reds — it is the third distinct red set from three runs
of one tree (CI ubuntu, CI macOS, here), and that is what makes the guard's verdict currently
unattributable. AC-4's contract is met (the expiry is a *named* timeout, not a hang), so this is a
warning, not a blocker — but a red that moves with machine load will be re-litigated on every PR.

Related, same caveat: the uncontended run above took **9m44s** (21:02:50 → 21:12:34), not the
319s / 5:19 `docs/testing.md` and `CLAUDE.md` now state. I cannot certify my machine was quiet, so
treat this as "did not reproduce" rather than "the number is wrong" — but it is worth a second
measurement before those numbers are the ones a reader plans around.

### W2 — 55 orphan `sleep` processes per run

`run_bounded` kills `$killer`, which is the subshell, not the `sleep "$SUITE_TIMEOUT"` running
inside it; `wait "$killer"` cannot reap a grandchild. Every completed suite therefore leaves a
`sleep 600` behind. CI's ubuntu runner reported exactly 55 of them at job end — one per staged
suite, none anything else:

```
Terminate orphan process: pid (270125) (sleep)   ... ×55
```

and my own uncontended run left **67** behind on this machine. Harmless to the verdict, and the PR
body's "no orphan left" is narrowly true of the *expiry* path it was measured on. The normal path
is the leak. `reap_group "$killer"` — the function is already written — closes it.

## The guard is not vacuous — I checked

Worth recording since it is the thing that would be hardest to recover later. I staged this
branch's plugins at `<root>/<name>/<version>/`, swapped in `origin/main`'s pre-fix copies of the
two suites, and scored them the way the guard does:

```
=== PRE-FIX plan-lint-selftest.sh, staged, consumer cwd ===
rc=1
  FAIL: (pl-n3) ghost path — rc=0 err=
[plan-lint-selftest] summary: 42 passed, 1 failed

=== PRE-FIX design-sync-selftest.mjs, staged, consumer cwd ===
rc=2
  FAIL: H0 could not read source files: Error: ENOENT ... /cache/dev-pipeline/design-toolkit/skills/design-faithful/lib/contract-types.mjs
[design-sync-selftest] 30 passed, 2 failed
```

Neither carries a known-red row, so both would red the guard. The class guard catches the class it
was built for, and the fixes are what make it green.

### W3 — the two ladders have no lockstep row

`design-sync-selftest.mjs`'s `resolveSibling()` is a hand-maintained copy of
`pipeline-doctor.sh`'s `resolve_sibling()`, and its own comment says "keep the two ladders in
step" — prose, which is exactly the thing CLAUDE.md's tier map routes to
`scripts/lockstep-manifest.tsv`. Not byte-anchorable across bash and JS, so the sanctioned form is
a **DROPPED** row carrying the reasoning, "so the decision is visible rather than forgotten".
Neither was added.

For the record the copies do agree today, including the part most likely to drift: `sort -r` and
`.sort().reverse()` are both lexicographic, not semver, so `10.0.0` sorts under `9.0.0` on both
sides. Mirrored faithfully — which is the point of pinning it.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Verified independently: staged `dev-pipeline@4.0.0` at `<root>/<name>/<version>/` with no git repo above it — `43 passed, 0 failed` from an out-of-repo cwd **and** from an in-repo cwd, and no scratch dir left under `$HERE`. |
| AC-2 | satisfied | In the same run `pl-n3` → rc=1 naming `does not exist`, `pl-n4`/`pl-n5` → 0, and the standing-witness reasoning is written into the fixture comment. |
| AC-3 | satisfied | Verified both halves. With `dev-pipeline 4.0.0` beside `design-toolkit 2.2.1` (rung 3 is the hit): `32 passed, 0 failed`. With the sibling removed: `H0 could not resolve sibling design-toolkit contract-types.mjs — tried:` + every probed path, rc=1. |
| AC-4 | satisfied | Staging, the no-git-above assertion, the separate git-init'd consumer cwd and the per-suite bound are all present and were observed working — including the bound firing as a named timeout rather than a hang (W1). |
| AC-5 | satisfied | Repo-relative key, red-unless-listed, listed-but-passing and stale-row as warnings, and the six-way count line — all present and correct on all three observed runs. |
| AC-6 | undeterminable | `node` was on PATH in every run CI or I made, so the skip path never executed. The code is right on inspection, modulo W4. |
| AC-7 | **unsatisfied** | Two suites fail under AC-4's topology with no row (B1), and the AC's own parenthetical asserts a `cost-block-selftest.sh` pass that CI contradicts twice (B2). |
| AC-8 | satisfied | #421 is open and covers exactly the deferred set — all four rows, D-10's `audit-selftest.sh` note, and D-4's SKIP policy as its Class A. The closing-comment link is milestone 5's and not yet observable. |
| AC-9 | satisfied | `plan-lint.sh` is untouched, so no ordinal can re-key; `tools/mutation-sweep.sh:22-25` does exclude `*-selftest.sh` by name, so the guard needs no accounting row; the five `plan-lint.sh` rows in `tools/mutation-baseline.tsv` match the claimed surviving set. The fixture change moves which *repo* the plans live in, not which `plan-lint.sh` paths the cases exercise, so a zero delta is what I would expect. |
| AC-10 | satisfied | Both rows landed (`docs/testing.md` tier table, `CLAUDE.md` "Where a new test goes"), and the `-P 4` pair was re-measured on this branch. The stale "51 pass, 4 listed" sentence inside that prose is B2's problem, not this AC's text. |

## Design fidelity

`not-applicable`. The spec has no `## Design` section, and `.claude/second-shift.config.json`
declares no `design` key — no provider is configured, so the disarm is justified rather than
evasive.

## Verification run on the reviewed head

- `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` — **rc=0**
- `jq empty` over all `*.json` — **rc=0**
- all `*-selftest.sh`, `-P 4`, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID` — **rc=1**,
  the single failure being `install-topology-selftest.sh` (W1)
- `tools/install-topology-selftest.sh` alone, uncontended — **rc=0**, `55 ran, 51 passed,
  4 known-red, 0 skipped, 0 stale row(s), 0 red`, 9m44s, 67 orphan `sleep` left behind
- CI run 31127616715 on `274d9e9` — `lint-and-selftests` fail, `selftests (macos, bash 3.2)` fail,
  `pr-gates` fail (missing verdict record only, which is this round's output)
