# lean review verdict — #372

verdict=needs-work
run_id: review-372-1
session_id: 28a2d373-8e8f-4778-88fe-23fc1f83b021
rounds: 1
pr: #373
reviewed_head: 118d63ed7213e5e769058f9f4a76580ee7d011da
reviewed_patch_id: 61237d544a125a394331ce314fca66a8b8d8ad2d
model: unknown

## Review summary

Round 1 on PR #373 (issue #372), reviewing `2ff7700` — three commits on top of `01950af`. The
change re-keys the lean verdict record's DECLARED freshness arm from a commit SHA to
`git patch-id --stable` over `merge-base(base, head)..head`, excluding the record path, across
**three** readers (the issue named two; `lean-reconcile.sh` check (4) was found and re-keyed on
evidence, as AC-9). Six reviewers ran (security, performance, complexity, maintainability,
test-coverage, scope-completeness); none went dark. Five returned approve; scope-completeness
returned request-changes.

**Verdict: needs-work.** Nine of the committed spec's ten ACs are satisfied; **AC-6 is not** —
the mutation evidence recorded in the PR body is wrong for one of the three guards, and I
reproduced the sweep to confirm it. Three further blockers are outside the AC set: the suite is
**red on CI** (`lean-gate-selftest.sh` `(v6)`, on both lanes, at `2ff7700` — before this record
existed), a `--help` regression this diff introduces in `lean-gate.sh`, and an issue-declared
`pause-and-ask` region resolved without an operator record.

**Correction to this record's own first draft.** The initial version of this section reported a
green local sweep. That was a **false green**: `(v6)` passes only on a machine that exports
`CLAUDE_CODE_SESSION_ID`, which every Claude Code session does and CI does not. See B0 — the
mechanism is now understood and reproduced in both directions. The verification list below is
corrected accordingly; nothing else in this record changed. This is a re-stamp of round 1, not a
new round: the verdict was `needs-work` before and after, and editing this record cannot move
`reviewed_patch_id` (the record path is excluded on both sides — that is AC-4).

The engineering itself is right, and worth saying plainly: patch identity is the correct
detector for the property being claimed, the exclusion is pinned **behaviorally** on both
readers rather than by a copy of the formula, every new block asserts its own premise so a
fixture that quietly grew the key cannot migrate a block and leave the fallback uncovered, and
the rebase cases assert the SHA arm *would* have redded on that exact state. None of the three
blockers touches the mechanism.

## Verification run for this round

All from a clean checkout of `2ff7700` at `second-shift-worktrees/second-shift-372`:

- Full `*-selftest.sh` sweep, **without** `SKIP_STRESS`: exit 0 **on this machine, and that
  result is not trustworthy** — `env -u CLAUDE_CODE_SESSION_ID bash …/lean-gate-selftest.sh`
  reproduces CI's `1 FAILURE(S)`. See B0.
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: exit 0. `jq empty` over every
  `*.json`: exit 0.
- `check-lockstep-pairs.sh`: 13 pairs, 0 failed.
- `scenario-liveness-selftest.sh`: 59 passed, 0 failed (including the new `(lean-patch-id)` leg).
- `mutation-sweep.sh --mode pr --base origin/main` (local, macOS, advisory): see B2.
- CI wiring checked against `.github/workflows/ci.yml`: `pr-gates` sets
  `PR_BASE_REF: ${{ github.base_ref }}` and checks out at `fetch-depth: 0`, which is what makes
  `origin/<base>` and the merge-base resolvable for the new arm. The same job already resolves
  `origin/$BASE_REF` in `check-frozen-files.sh`, so this is confirmed rather than assumed.

## Blockers

### B0 — the branch is red on CI: `(v6)` is green only when the operator's session id leaks in

`plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh` (v5)/(v6)

Both selftest lanes fail on `2ff7700` — *before* this verdict record existed, so it is the
build's red, not the review's:

```
FAIL: (v6) expected rc=2 from the writer on an unresolvable base, got 1:
  [lean-gate] ✗ verdict: the build progress file records no session id, so authorship
  separation is unverifiable. Refusing.
[lean-gate-selftest] 1 FAILURE(S)
```

Identical on `lint-and-selftests` (ubuntu) and `selftests (macos, bash 3.2)`. Reproduced in both
directions on one machine, which is what identifies the cause rather than the symptom:

```
$ bash …/lean-gate-selftest.sh                              → all green
$ env -u CLAUDE_CODE_SESSION_ID bash …/lean-gate-selftest.sh → 1 FAILURE(S)   ← CI's exact failure
```

The chain:

1. `(v5)` calls `reset_progress`, which is `rm -f "$PROG"` — the progress file is **gone**.
2. `gate_cfg` (`lean-gate-selftest.sh:787`) then runs the gate. It unsets `RUN_ID` and **not**
   `CLAUDE_CODE_SESSION_ID`.
3. `ensure_progress_file()` (`lean-gate.sh:361`) recreates the header with
   `session_id: ${CLAUDE_CODE_SESSION_ID:-unset}` — so the *operator's ambient session id* is
   stamped into the fixture.
4. `(v6)` runs the `verdict` writer, whose **first** authorship refusal
   (`lean-gate.sh:781`) fires when that key is empty **or the literal `unset`**.

On any Claude Code session the env var is exported, step 3 writes a real id, the refusal is
skipped, and the writer reaches the patch-id arm `(v6)` is actually testing → rc=2, green.
In CI it is absent, step 3 writes `unset`, and the writer refuses two checks earlier → rc=1.

Two things follow, and the second is the one that matters:

- `(v6)` is **not testing what it names**. It asserts the write-side vacuity guard (D-5/AC-8),
  but it only ever reaches that guard by accident of the operator's environment.
- Because the *unmutated* `lean-gate-selftest.sh` fails in CI, `mutation-sweep.sh` scores that
  guard as an **unrunnable pair** and scores none of its mutants there. So the AC-6 row for
  `lean-gate.sh` is reproducible only under the same leak. (The `check-lean-chain.sh` row in
  **B2** is unaffected — that suite is green in CI, and `(v6)` is the only failure across the
  whole sweep.)

This is the exact class this file already warns about one env var over: `lean-gate-selftest.sh:75`
documents `unset RUN_ID` because "this helper backs nearly every case in the file … leaks
through". `CLAUDE_CODE_SESSION_ID` is the one the helpers do not unset.

Fix: `seed_build_progress` before `(v6)` so the case reaches its own arm deliberately, **and**
add `unset CLAUDE_CODE_SESSION_ID` to `gate_cfg`/`gate` alongside the existing `unset RUN_ID`,
so no future case can be green for this reason. The second half is the load-bearing one — the
first alone fixes one case and leaves the leak.

### B1 — `lean-gate.sh --help` now drops its entire Seams section

`plugins/dev-pipeline/skills/run-lean/lean-gate.sh:117`

The diff grows the header comment by 8 lines (`@@ -38,13 +38,21 @@`) and leaves the help range
at `sed -n '2,75p'`. The header now ends at line 86 (`set -uo pipefail` is line 87), so `--help`
prints lines 2–75 and silently drops **lines 76–86** — the whole `Seams` block (`${GH:-gh}`,
`LEAN_PROGRESS_FILE`, `SECOND_SHIFT_CONFIG`, `--pr-file`, `--comments-file`, `LEAN_RUN_MODEL`)
plus the bash-3.2 note. Measured, not inferred:

```
$ bash plugins/dev-pipeline/skills/run-lean/lean-gate.sh --help | tail -3
#       4 = fix budget exhausted for that milestone (hard stop; D-19)
#
                                    ← help ends here; Seams is gone

$ git show origin/main:…/lean-gate.sh > /tmp/base.sh && bash /tmp/base.sh --help | tail -3
#   LEAN_RUN_MODEL           #347: the `model:` key stamped into the progress/verdict record
#                            at creation time (retro-corpus.sh's corpus-aggregation key).
```

This is the exact failure class the diff **fixes on its sibling in the same commit** —
`check-lean-chain.sh:113` correctly moves `2,87p` → `2,102p`. The sibling's guard, and the
reason it exists, is written down at `check-lean-chain-selftest.sh` case `(T)`: *"`sed -n
'2,Np'` is a hand-maintained line number: growing the header silently truncates the help text,
and this repo has been burned by exactly that."*

There is a pre-existing component: at `origin/main` the range already fell 3 lines short
(76–78, from #347's `LEAN_RUN_MODEL` block). This diff widens the loss from a 3-line tail to an
11-line documented section, so it is a regression this change introduces, not an inherited one.

`lean-gate.sh` has **no** `--help` case in its selftest — that is why the green sweep says
nothing here. Fix: `2,86p`, plus a `(T)`-shaped two-sided case in `lean-gate-selftest.sh`
(present: `bash 3.2 compatible`; absent: `^set -uo pipefail`), so the next header edit reds
instead of truncating. The two-sided form is load-bearing on this repo's two lanes: on BSD the
`cmp-z` mutant of that line makes `sed` die and only the presence assertion kills; on GNU it
auto-dumps the file and only the absence assertion does.

### B2 — AC-6's recorded evidence is wrong for `check-lean-chain.sh`

PR body, "AC-6: mutation baseline" table.

The PR body reports `check-lean-chain.sh` as **12 applied / 5 killed / 7 survived**, lists seven
survivor ids including `scripts/check-lean-chain.sh::cmp-z::2`, and concludes *"identical to the
7 committed rows"*. Reproduced independently
(`bash tools/mutation-sweep.sh --mode pr --base origin/main`, this tree, `2ff7700`):

| Guard | applied | killed | survived | survivor ids | PR body |
| --- | ---: | ---: | ---: | --- | --- |
| `lean-gate.sh` | 10 | 6 | 4 | `cmp-eq::1`, `cmp-z::1`, `default::1`, `default::2` | ✅ matches |
| `lean-reconcile.sh` | 11 | 5 | 6 | `fail-open::2`, `cmp-eq::1`, `cmp-z::1`, `detector::1`, `default::1`, `default::2` | ✅ matches |
| `check-lean-chain.sh` | 12 | **6** | **6** | `cmp-eq::1`, `cmp-eq::2`, `cmp-z::1`, `detector::2`, `default::1`, `default::2` | ❌ claims 5 / 7 + `cmp-z::2` |

And `tools/mutation-baseline.tsv` holds **6** rows for that guard, not 7:

```
$ grep -c '^scripts/check-lean-chain\.sh::' tools/mutation-baseline.tsv
6
```

So three separate statements in that row are false: the kill/survive counts, the `cmp-z::2`
survivor, and the number of committed baseline rows it claims to match. `cmp-z::2` on this guard
is the `-h|--help) sed -n '2,102p'` line, and case `(T)` kills it on **both** lanes by
construction (BSD: `sed -z` dies, the presence assertion fires; GNU: `-z` auto-dumps the file,
the absence assertion fires) — so this is not a macOS-vs-CI artifact.

The **conclusion** the row supports is correct and I confirm it: no ordinal moved on any of the
three guards, and no re-baselining is required. But AC-6's deliverable is *"the site-level
evidence recorded in the PR body either way"*, and as recorded it asserts a state — a
baseline-absent survivor — that under `mutation-sweep.sh`'s own exit contract would **red** the
lane. Scoring it satisfied would be substituting the nearby true conclusion for the criterion's
actual bar. Fix: correct the row to 12 / 6 / 6 with the six ids above.

### B3 — OR-2 was dispositioned `pause-and-ask` and resolved without an operator record

Issue #372, Open regions table; spec `docs/plans/second-shift-372-lean.md` D-6.

The issue marks OR-2 — *whether the base for the merge-base is the configured `baseBranch` or
the PR's declared base when they disagree* — as **`pause-and-ask`**, and unlike OR-1 it carries
no reversible default. It is resolved in the build session as D-6 (each reader uses the base it
already has) and presented under an "OR-2, resolved" heading in the PR body. Evidence that no
operator resolution exists:

- `gh issue view 372 --comments` returns exactly one comment, the bot's `lean-claimed` claim.
- No `docs/plans/second-shift-372-lean-intent-gap.md` on the branch, so the P9 ratification
  channel — the mechanism that exists for precisely this — was not used either.

Independently surfaced by `scope-completeness-reviewer` at confidence 92 and corroborated above.
The resolution itself is sound, the divergence is documented in both readers' headers, and the
two rejected alternatives are named — none of that is in question. What is missing is the
authority: a `pause-and-ask` region is not the build session's to close, and this one has a real
operator-visible consequence (a PR retargeted away from the configured base reds at the merge
boundary, fail-closed).

**This blocker has no code remedy** and should not get one. Clear it either by an operator
comment on #372 resolving OR-2, or by writing and ratifying an intent-gap record.

## Warnings

### W1 — the PR body's kill-power table cites six case ids that are wrong or do not exist

PR body, "Evidence" table, `check-lean-chain.sh` rows.

Those six mutants are attributed to `(S2)`, `(S3)`, `(S3a)`, `(S4)`, `(S5)`, `(S6)`. Enumerating
the suite's actual ids:

```
$ grep -oE '"\((S[0-9a-z]*|U[0-9a-z]*|R[0-9a-z]*)\)' scripts/check-lean-chain-selftest.sh | sort -u
(R1) (R2) (R3) (R4) (R5) (S0) (S0b) (S1) (S2) (S3) (S4) (U0) (U1) (U2) (U3) (U3a) (U4) (U5) (U6)
```

`(S3a)`, `(S5)` and `(S6)` do not exist anywhere in the file. `(S2)`/`(S3)`/`(S4)` do exist but
belong to the **pre-existing evidence-6 block** (an unratified intent-gap record blocks the
merge), which has nothing to do with the patch-id arm. The cases that actually kill those
mutants are `(U2)` (record exclusion), `(U3)` (precedence), `(U6)` (collapsed empty-patch-id
guard), `(U5)` (`PR_BASE_REF`), `(U4)` (mismatch comparison); the non-vacuity assertion the body
calls `(S3a)` is `(U3a)`. The `lean-gate.sh` column is correct throughout — `(v1)`–`(v6)` and
`(v3a)` all exist.

The coverage is real; only the citations are wrong, most plausibly a block rename after the
table was drafted. It stays a warning rather than a blocker because no AC's deliverable rests on
it — but it is worth fixing in the same pass as B2, because this repo bans prose-presence guards
on purpose, so **no lane can ever red on a rotted citation**. The merge record keeps whatever is
written here.

### W2 — AC-8's third reader gets a note, not a refusal, and the arm is undriven

`plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh:238`

AC-8 reads *"an unresolvable or empty patch-id on any read side is a **refusal**, not an
unmeasured pass. Covered on each reader."* On `lean-gate.sh` and `check-lean-chain.sh` it is a
refusal, driven by `(v5)`, `(v6)`, `(U5)`, `(U6)`. On `lean-reconcile.sh` an empty recompute
emits `say "  note: cannot compute…"` and the tool continues at rc=0, and no `(M)` case drives
that branch — `(M0)` only asserts the fixture's own id is non-empty.

I score AC-8 **satisfied** rather than failed, and the reasoning is worth recording so a later
round does not re-litigate it: what the AC exists to prevent is an *unmeasured pass*, and a note
is not a pass, so no reader can print a ✓ over an empty hash. The guard is also fail-**closed**
if deleted — with it gone, an empty `CUR_PATCH_ID` falls through to the equality comparison and
mismatches a non-empty declared id, producing a false `bad` rather than a false `ok`. And the
D-5 hazard it names ("two empty strings compare equal") is structurally unreachable on this
reader, since the branch is only entered when `REVIEWED_PATCH_ID` is non-empty.

So this is a letter-vs-behavior gap, not a hole. Worth either driving the branch with an `(M)`
case (a config naming a base with no remote-tracking ref, the shape `(v5)` already uses) or
narrowing AC-8's wording on this reader to "never an unmeasured pass" — the spec's own D-5 says
"both read sides", written before AC-9 added the third, which is where the tension comes from.

## Suggestions

- `lean-reconcile.sh:230` resolves its base with a `to_entries[] | select(.value.path==".")`
  query while `lean-gate.sh:169` uses `$HOST_Q as $h | .topology.repos[$h].baseBranch`. The two
  are equivalent on every well-formed config, and each already existed in its own file — no
  change needed. Noting it only because the three readers now share a formula whose base is the
  one input they resolve differently, and D-6 makes that a deliberate property worth keeping
  visible.
- `git patch-id` ignores pure mode changes and pure renames (no hunks), so a `chmod +x` landing
  after an approve would not move the id. Not a hole: the **inferred** arm catches it in all
  three readers, since the file shows up in `git diff --name-only`. Recorded so the pair's
  division of labor is explicit.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — milestone 4 passes after a clean rebase, fails on a post-record commit | satisfied | `(v3)` passes over a **real** rebase onto a base that moved with content; `(v3a)` asserts the SHA arm would have redded on that exact state; `(v4)` reds a post-approve commit shaped so the inferred arm is green and only this arm can fire |
| AC-2 — same at the merge boundary, incl. a conflict resolution refused / clean replay passed | satisfied | `(U3)`/`(U3a)` clean replay + non-vacuity; `(U4)` a resolution that changed a line is refused, with the record in the same commit so inference stays green |
| AC-3 — pre-key records still gate on the SHA path, and the pass line names the arm | satisfied | `(u1)`–`(u4)` on the fallback, `(u5)` asserts the block's own premise; mirrored by `(R5)` and `(L4)`. Pass lines differ: `declaring reviewed_head` vs `patch-id` (D-8), so the case cannot pass vacuously on the new arm |
| AC-4 — the exclusion holds, both readers | satisfied | `(v2)` and `(U2)` drive it **behaviorally** — the record's own bytes are edited and committed and the gate must still pass — rather than by re-deriving the formula |
| AC-5 — doc scope | satisfied | `run-lean/SKILL.md:44` and `review-lean/SKILL.md:57-60` rewritten; `check-lean-chain.sh:36-47` states covers / does-not-cover. The `interviewing-baseline` re-point is evidence-backed and I re-verified it: `grep -ciE 'rebase\|reviewed_head\|verdict'` over that SKILL.md returns **0**, so the issue's AC-5 named a file that cannot carry the prose. `run-lean/SKILL.md` is still exactly 60 lines — `(f)`'s cap holds |
| AC-6 — survivor ordinals checked against the baseline, site-level evidence in the PR body | **unsatisfied** | See **B2**. The conclusion (no ordinal moved) is correct and reproduced; the recorded evidence is not |
| AC-7 — `Changelog:` trailer | satisfied | `621b205` carries a substantive trailer with `Migration: none`; `2cc81f5` and `2ff7700` carry `Changelog: none`. Verb is `feat:`, which is the honest one here |
| AC-8 — an empty/unresolvable patch-id is a refusal on every read side | satisfied, on a **red** oracle | `(v5)`, `(U5)`, `(U6)` are green in CI and cover both read sides, which is what AC-8 asks for. `(v6)` — the **write** side — is red in CI and only reaches its arm under B0's leak, so it is currently evidence of nothing. The third reader is a note rather than a refusal and the arm is undriven — see **W2**. Scored satisfied because the read sides carry the AC; the write-side case still has to go green (**B0**) |
| AC-9 — the third reader is re-keyed | satisfied | `(M1)` coherent record, `(M2)` a real rebase reconciles with `merge-base --is-ancestor` asserting the ancestry arm **would** have failed, `(M3)` an incoherent id still fails |
| AC-10 — `scenario-liveness-selftest.sh` gains a composing leg | satisfied | leg 7 `(lean-patch-id)`: writes through the **real** `verdict` subcommand, composes across a real rebase, asserts `lean_sha_would_red` is non-empty, and re-reds on a later commit. Suite 59/59 |

**9 of 10 satisfied; AC-6 unsatisfied.**

## Round-2 checklist

0. Green the suite: `seed_build_progress` before `(v6)`, **and** `unset CLAUDE_CODE_SESSION_ID`
   in `gate_cfg`/`gate` next to the existing `unset RUN_ID` (B0). Verify with
   `env -u CLAUDE_CODE_SESSION_ID`, not a bare local run — a bare run is what missed this.
1. `lean-gate.sh` help range `2,75p` → `2,86p`, plus a two-sided `--help` case in
   `lean-gate-selftest.sh` (B1).
2. Correct the AC-6 row to `12 / 6 / 6` with the six survivor ids, and the "7 committed rows"
   claim to 6 (B2).
3. Re-point the six `check-lean-chain.sh` kill-power rows at `(U1)`–`(U6)` / `(U3a)` (W1).
4. An operator comment on #372 resolving OR-2, or a ratified intent-gap record (B3) — **not** a
   code change, and not the build session's to decide.

Optional: drive `lean-reconcile.sh`'s empty-patch-id note with an `(M)` case, or narrow AC-8's
wording on that reader (W2).

Per `review-lean` step 7, a build session addresses these and a **new** review context produces
round 2 — this one is not resumed. Note that fixing items 1–3 changes the branch's patch, so
round 2's record supersedes this one by construction.
