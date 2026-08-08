# lean review verdict — #419

verdict=approve
run_id: review-419-2
session_id: df564885-302b-4881-ae04-27e2f47eb1b2
rounds: 2
pr: #425
reviewed_head: acb4d781a3361aaeaff53c1112b29f1918e6909e
reviewed_patch_id: 6dbec78a8d8befbb952f741afdf2a39ea2fa916e
inherited_patch_id: 07223b3894d88227f047fe90c98403f182b7c02d
inherited_from_verdict: 74ef2c9ea95e2a37a97d5125f8cc842c403d4850
fidelity: not-applicable
model: unknown

Round 2, delta range `74ef2c9..HEAD` (the two fix commits), inheriting patch `07223b3894d8`
from round 1's record. I read the prior findings first, then the delta, then re-ran the
verification the round-1 record left open.

All five round-1 blockers and all five warnings are addressed, and I verified each one rather
than reading the claim. The two that mattered most — B1 (the branch reds both CI lanes) and
B2 (counts seeded from one machine) — are discharged the only way they could be: by
reproducing the second environment here and scoring the guard in it.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | PR body | `INSTALL_TOPOLOGY_TIMEOUT` is described as "(default 600s)"; the tree says 1200s in three places, and the body never mentions the raise at all. |
| N1 | nit | `docs/testing.md` | The page tells the reader not to plan around a single number for the guard, then gives the stress-inclusive sweep's own figure as a bare point value (540s). I measured 758s. |

No blockers. Nothing in the delta reopens anything round 1 found, and nothing in it introduces
a new defect I could produce a failure for.

### W1 — the PR body is the one artifact still saying 600s

The delta raises the per-suite bound from 600s to 1200s. The guard's own comment, `docs/testing.md`
and the spec's AC-4 amendment all say 1200 and all explain why. The PR body's **Per-suite bound**
paragraph still opens `INSTALL_TOPOLOGY_TIMEOUT` (default 600s)` and still justifies it with the
244s contention measurement alone — so a reader of the PR learns neither the current default nor
that it moved in response to round 1's W1.

Same class as round-1 B5, and I am deliberately scoring it lower. B5 was one of five blockers on
a branch that was independently red, so it cost nothing to carry. Here it is the only open item on
a branch that is green, and the fix is a PR-description edit — not a commit — so it does **not**
touch the patch this record is bound to and costs no round. Make the edit; the verdict stands
through it.

### N1 — one number kept its point value

`docs/testing.md` argues, correctly and at length, that a whole-suite re-runner's wall clock is not
reproducible enough to publish as a single figure, and gives the guard's own as a 319/438/584s
range. Two paragraphs later the stress-inclusive sweep is stated as "measured 540s". My run of
that exact form took **758s** (11:08:43 → 11:21:21). That is inside the 1.8x spread the page
itself documents, so this is "did not reproduce the point value", not "the number is wrong" — but
the page's own advice applies to its own figure.

## What I verified, and how

**The second environment reproduces, exactly.** Following `docs/testing.md`'s recipe — `PATH`
rebuilt symlink-for-symlink (1430 entries) with only `bash` repointed at `/bin/bash` 3.2 and
`claude` omitted — the guard scores:

```
[install-topology] summary: 55 ran, 49 passed, 6 known-red, 0 skipped, 0 stale row(s), 0 red
GUARD_SHADOW_RC=0
```

which is the PR's claimed figure to the digit. Both late rows surface with CI's first failure line
verbatim: `cost-block-selftest.sh — rc=1 — FAIL run A produced no valid rollup JSON` and
`preflight-selftest.sh — rc=1 — [self-test] FAIL section lint surfaces at preflight (clean
review-context)`. `plan-lint-selftest.sh` and `design-sync-selftest.mjs` both **pass** in that
environment, and so does `audit-selftest.sh` — OR-2 closes on evidence. The recipe being
reproducible by someone who did not write it is itself part of what AC-7 now asks for.

That run also puts the guard through **bash 3.2** end to end, which is the macOS lane's shell, so
the new `KR_SEEN[kr]=1` subscript and `SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"` are 3.2-clean
by execution rather than by inspection.

**W1's raise holds under the load that broke 600s.** The stress-inclusive `-P 4` sweep — no
`SKIP_STRESS`, the form that timed `statectl-selftest.sh` out at 600s in round 1 — completed with
the guard at `55 ran, 51 passed, 4 known-red, 0 skipped, 0 stale row(s), 0 red`, and the sweep
itself `SWEEP_RC=0`. No timeout line anywhere.

**W2's leak is closed at scale.** `pgrep -f '^sleep 1200'` after both full guard runs: **0**.
Round 1 measured 67 left behind on this machine and 55 on CI's runner.

**W4 is fixed and the fix is load-bearing.** I ran the production guard over a minimal staged
fixture (one fake plugin carrying one `.mjs` suite, with a known-red row for it) under a `PATH`
with `node` removed, against both the branch guard and `74ef2c9`'s:

```
BRANCH   :: summary: 0 ran, 0 passed, 0 known-red, 1 skipped, 0 stale row(s), 0 red
PRE-FIX  :: warn: known-red row … matched no staged suite — stale row
            summary: 0 ran, 0 passed, 0 known-red, 1 skipped, 1 stale row(s), 0 red
```

Same fixture, opposite result — so the fix is not decorative. The `node`-present control arm runs
the suite and warns "listed known-red but PASSED", confirming the fixture is real rather than
inert. This is also what makes AC-6 scorable this round.

**W3 is in the sanctioned form.** The lockstep entry is a `Considered for a row and DROPPED:`
comment block, which is how the other eighteen dropped pairs in that file are written — not an
invented convention. `scripts/check-lockstep-pairs.sh`: 17 pairs, 0 failed. Its recorded
"both sides sort lexicographically, so `10.0.0` sorts under `9.0.0`" claim checks out against
`sort -r` and `.sort().reverse()` on both sides, and it names the residual (no behavioral guard on
the bash side) rather than papering over it.

**The list did not become a place to hide reds.** Both new rows carry a reproduced mechanism, not
`undiagnosed`, and neither suite is excused anywhere except under the install topology — both still
run, and still have to pass, in the ordinary in-repo sweep. The `cd ""` diagnosis is
version-checkable on inspection: `git rev-parse --git-common-dir` fails above an install cache, so
`cd "$HERE" && cd "" && pwd` yields `$HERE` on bash ≤ 5.2 and empty on ≥ 5.3, and `dirname ""` is
`.` — which lands the fixture in the consumer cwd where the script also looks. Green here on 5.3.9,
red on both lanes' older bash. That is the observed split.

## The gap I cannot close, stated plainly

**CI has never run on this head.** The only run on this branch is 31127616715 on `274d9e9` — round
1's head, the red one. Both fix commits (`a22e956`, `acb4d78`) and the round-1 verdict commit
landed during the GitHub Actions incident and got no run at all; `ci.yml` has no `workflow_dispatch`,
so a review session cannot trigger one without a push, and a push would void this record.

I am not treating that as a blocker. The claim under test — "the guard is 0 red where CI runs it" —
is a claim about an environment, and I reproduced that environment locally and measured it, which
is the same class of evidence CI would give and is what AC-7 now requires. Pushing this record is
itself the branch's next `synchronize` event, so CI will run on it before the merge boundary reads
anything. If that run is red, this verdict is wrong and should be discarded rather than argued
with.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Inherited from round 1's independent verification; untouched by the delta. `plan-lint-selftest.sh` passes under the staged topology in both environments I ran (lines 26 of each guard log). |
| AC-2 | satisfied | Inherited; untouched. |
| AC-3 | satisfied | Inherited; untouched. Re-read the ladder against `resolve_sibling()` — rung structure, `PLUGINS_DIR`/`MY_VERSION` derivation and the unresolved-failure message all mirror. `design-sync-selftest.mjs` passes in both environments. |
| AC-4 | satisfied | The bound's contract is unchanged (a hang is one named timeout line); only the default moved, and the AC never named a value. Guard observed running end to end twice, plus the fixture probe. |
| AC-5 | satisfied | All four verdict paths observed live this round: `known:` (4 rows here, 6 in the second environment), `warn:` listed-but-passing (both env-dependent rows on this machine), `warn:` stale-row (fixture probe), and the six-way count line. |
| AC-6 | **satisfied** (was undeterminable) | Directly probed rather than inspected: `node` removed from `PATH`, the `.mjs` suite reports `SKIP:` by name and the summary carries `1 skipped`, rc=0, never folded into `passed`. Round 1 could not score this because `node` was present in every run available to it. |
| AC-7 | **satisfied** (was unsatisfied) | The AC was tightened to require a second environment before any count is published, and then met. I reproduced the corroborating run independently: `49 passed, 6 known-red, 0 red`, rc=0. No row for `plan-lint-selftest.sh` or `design-sync-selftest.mjs`; every row states a cause; no row reads `undiagnosed`. |
| AC-8 | satisfied | #421 is open, updated, and covers all six rows, D-10's `audit-selftest.sh` note (now "no diagnosis owed — it passes"), and D-4's SKIP policy as its Class A. The closing-comment link is milestone 5's and still not observable. |
| AC-9 | satisfied | Unchanged this round and re-checked structurally: the delta touches no in-universe guard (`tools/mutation-sweep.sh` excludes `*-selftest.sh` by name, and the other five changed files are docs/TSV), so no ordinal can re-key and no accounting row is owed. |
| AC-10 | satisfied | Both rows present (`docs/testing.md:24`, `CLAUDE.md:153`), and the `-P 4` pair is re-measured with the guard in the glob. The stale "51 pass, 4 listed" sentence round 1 flagged under B2 is gone. N1 is a nit against one figure on the same page, not this AC. |

## Design fidelity

`not-applicable`. The spec has no `## Design` section and `.claude/second-shift.config.json`
declares no `design` key, so no provider is configured and the disarm is justified rather than
evasive. Unchanged from round 1; re-checked against the config rather than inherited.

## Verification run on the reviewed head (`acb4d78`, tree clean, `origin` identical)

- `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` — **rc=0**
- `jq empty` over all `*.json` — **rc=0**
- all `*-selftest.sh`, `-P 4`, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID` — **rc=0**
  (round 1's same command was rc=1 on the 600s timeout), 12m38s
- `tools/install-topology-selftest.sh` under the CI-equivalent `PATH` (bash 3.2, no `claude`) —
  **rc=0**, `55 ran, 49 passed, 6 known-red, 0 skipped, 0 stale row(s), 0 red`
- `scripts/check-lockstep-pairs.sh` — **rc=0**, 17 pairs, 0 failed
- `scripts/check-changelog-trailer.sh main` — OK; `scripts/check-frozen-files.sh main` — clean
- orphan `sleep` processes after two full guard runs — **0**
- CI on this head — **none exists**; see the gap section above
