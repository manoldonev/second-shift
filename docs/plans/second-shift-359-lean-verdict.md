# lean review verdict — #359

verdict=approve
run_id: review-359-3
session_id: 3634ae3d-0230-4878-8781-a4a83dccd4f3
rounds: 3
pr: #430
reviewed_head: 5bee67272f3a3759b26b7f7ef4aa3a310b9a635c
reviewed_patch_id: 64fa261cca2befad5dd5c2a39d4f057d7dcdecb8
inherited_patch_id: 3818c4fc81ae77ce9c2dcf94e9c0050e914ccf07
inherited_from_verdict: 09f24ae5b5abfd2c9d591cc8883904d52b734c9f
fidelity: not-applicable
model: unknown

## Round 3 — `approve` (re-stamp, same identity `review-359-3`)

This is **not a round 4**. The base moved again after round 3 (#428 landed) and the branch merged
it `--no-ff` at `5bee672` with two hand-resolved conflicts, which moved `reviewed_patch_id`
`6783b0a8d790` → `64fa261cca2b` and red-lined the declared-freshness arm. The round-3 approve is
re-stamped rather than spent, on the measurement below — not on the PR body's argument, which I
re-derived independently.

**The branch's own contribution is byte-identical to the tree round 3 approved.** Merge-base
anchored on both sides:

```
diff <(git diff 3b9c810..fe197e5) <(git diff 6cb40a0..5bee672)
```

is **30 lines: two `index` blob hashes, one `@@` offset, and six context lines** — the context
main's additions moved into place around this branch's hunks. **Zero `+`/`-` lines.** The stat
agrees: `19 files, +2247/−186` at `fe197e5` and at `5bee672`. (Round 3's record quotes
`+2245/−186`; that stat was measured at `d8afaf2`, before its own 118→120-line record commit. The
two-line delta reconciles exactly and is not a content change.)

**Main's side came in whole.** `diff <(git diff 3b9c810..6cb40a0) <(git diff fe197e5..5bee672)`
is 40 lines, all `index`/`@@`/one reconciled blank separator in an append-log file.

`git merge-tree --write-tree fe197e5 6cb40a0` confirms the two conflicts were real
(`SECOND-SHIFT.md`, `lockstep-manifest.tsv`) — so this is not the trivial "Update branch" case,
and each resolution was checked on its own terms below.

Range declared by `delta`: `6cb40a0..HEAD`, **FULL** — all 19 files, nothing inherited by
reference. Round 3's and round 2's committed findings were read first. `inherited_patch_id` in the
header records the chain link to round 2's record (`inherit_candidate` skips round 3's own
committed record on the run-id match, exactly as its comment specifies); it is not a claim that a
range went unread.

### The two conflict resolutions, each checked

| Conflict | Resolution | Verified how |
| --- | --- | --- |
| `scripts/lockstep-manifest.tsv` | add-vs-add at EOF, both blocks kept whole | `check-lockstep-pairs` **22/22** (this branch's 19 + main's 3 `unclaim-workflow-*` rows); the branch's own rows are byte-identical to round 3's, only the `@@` offset moved `-450` → `-469` with the same `,3 +…,75` counts |
| `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` | branch's three-bullet rewrite taken whole; main's unclaim bullet placed **after** it | set-difference against **both** parents: **zero** lines from the branch's version dropped, and exactly **four** from main's — the pre-branch two-check bullet this branch replaces, whose content the replacement restates. The ordering is load-bearing and correct: the third lean bullet opens "If you hand-maintain **that** workflow", and the unclaim bullet now follows it rather than splitting the block, so "that workflow" still binds to the evidence workflow. Main's own "the pair above" back-references still resolve to the evidence pair, as they did on main |

### Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Note (new) | `plugins/dev-pipeline/skills/run-lean/lean-gate.sh:2443` (from #422, via the merge — **not** this branch's contribution) | `require_entry_attested` gates `delta`, which is the **review** lane's step 4. This build run predates #422, so the branch's own gate refuses step 4 outright. The remedy it prints is `bash G entry <issue>` — a *build-role* subcommand whose row `lean-reconcile.sh:477` reads as "the **build** run recorded an entry attestation … the **build session's** audit ledger was live when the run started". A review session running it stamps its own session id and today's timestamp into that claim, i.e. forges the one arm about the build's own provenance. Worse on a host with no build run-id cache — the case the refusal message itself anticipates ("a checkout not sharing the build host's state dir") — where `entry` resolves `RUN_ID_CACHE` with `persist=1` and a review session with its own `RUN_ID` exported would **establish the build identity as the review id**, against that dispatch's own comment ("an EVALUATION must be able to read an identity, never to establish one"). I did not run it; step 4 was run from the installed `G` per the #363 rule, which scopes the branch-copy requirement to `verdict` alone. Not a blocker here: `check-lean-chain.sh` has zero references to the entry row, so the merge boundary does not gate on it, and CI confirms. Route as a successor against the review lane. |
| 2 | Note (new) | PR body, final section | The reproduction command is base-relative: `diff <(git diff 3b9c810..fe197e5) <(git diff origin/main..5bee672)` gave 20 lines when written, but `origin/main` has since advanced to `a7f069a` (#418) and it now yields **461** lines, most of them a spurious reversal of #418. A committed artifact's proof should be merge-base-anchored (`6cb40a0..5bee672`) so it keeps reproducing. Body-only; its fix is not a commit. |
| 3 | Note (carried, r3 #1) | `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh:945` | The `lean_seed_unattested()` run-id cache seed is observed by no case. Unchanged. |
| 4 | Note (carried, r3 #2) | PR body, "One commit beyond the rebase" | `b1855cc`'s `(m1c)` fix was superseded by main's own in #433; the section still reads as if it contributes. Unchanged. |
| 5 | Note (carried, r1/r3 #3) | `scripts/check-lean-chain.sh:369` | Round 1's unkilled defensive guard, declared left-as-recorded. Unchanged. |

No blockers. Nothing in the delta is a re-introduction of a previously-found blocker: rounds 1 and
2 each had exactly one, both fixed in round 2 and both still fixed here (the template's three read
scopes, and `arm_freshness`'s one-fact-one-violation guard — both re-verified below).

### AC scoring — `docs/plans/second-shift-359-lean.md`

Every `AC-n` scored against the whole spec. The implementing files are byte-identical to the tree
round 3 read, so round 3's mapping stands; the marked rows were re-verified independently on this
head rather than inherited.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 payload selftest | **satisfied** | `lean-evidence-selftest.sh` carries every enumerated case: `(g)` missing verdict, `(k)`/`(l)` run_id/session_id collision, `(m)` zero markers under github, `(n)` non-Bot marker, `(w)`/`(x)` intent-gap, `(r)`/`(s)` absent/mismatched `reviewed_patch_id`, `(b)` non-lean not-applicable, `(h)`+`(h2)` one-fact-one-violation. **Re-run on this head: `rc=0`.** |
| AC-2 template selftest | **satisfied** | **Re-verified on this head**: the suite's own `awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f'` extraction against `second-shift-ci.yml` returns exactly `contents: read` / `issues: read` / `pull-requests: read` and **zero** `: write` lines. Suite `rc=0`. |
| AC-3 delegation | **satisfied** | `check-lean-chain.sh` delegates classify (`:363`) plus `verdict` (`:448`), `identity` (`:551`), `freshness` (`:646`, inside the declared-`reviewed_patch_id` precedence branch only) and `intent-gap` (`:733`); no second copy retained. Suite `rc=0`. Live in this head's `pr-gates` log, which interleaves `[lean-evidence]` lines inside the `[lean-chain]` run and passes the identity arm against a real bot marker. |
| AC-4 writer | **satisfied** | `(pm1)`–`(pm7)` present and green; `pr-gates` on this head reports the verdict identity "distinct from all 1 bot marker(s) on this PR". |
| AC-5 config resolution | **satisfied** | `(z1)` config-derived, `(z3)` env-overrides-config, `(z2)` pipeline-namespace exclusion, `(f)` mutual non-prefix refusal — all green. |
| AC-6 jira degrade | **satisfied** | `(aa1)` reduced-strength line printed, `(aa2)` jira fixture with a missing verdict still exits 1. |
| AC-7 mutation baseline | **satisfied** | **Re-read from CI's enforcing lane on this exact head** (`lint-and-selftests`, green): `lean-evidence 11/8/3 · lean-gate 15/12/3 · ci-check 10/5/5 · check-lean-chain 12/7/5` — byte-identical triples and survivor id sets to round 3's. Merging #428 re-keyed no ordinal, so no `tools/mutation-baseline.tsv` row needed re-anchoring. |
| AC-8 doc | **satisfied** | **Re-verified post-merge**: `SECOND-SHIFT.md` still documents the arm, the required-status-check wiring, the fail-closed posture, all three read scopes with the replaces-wholesale rule, and the jira degrade — and reads coherently in its new neighborhood (see the resolution table). `SKILL.md` step 7 names the `mark` call and the file is 43 lines, inside the 60-line cap. `check-lockstep-pairs` **22/22**. |
| AC-9 critic | **satisfied** | All **10** non-merge commits carry a `Changelog:` trailer, checked per-commit. A scan of the full `6cb40a0..HEAD` diff for consumer repo names, org names and company ticket-key shapes returns nothing. |

### Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit `Design: none — this is
shell/CI plumbing with no rendered surface` disarm, and the repo's committed config declares no
`design.provider`, so the disarm is justified rather than convenient. Unchanged from rounds 1–3.

### Verification I ran (from this checkout of the PR head, `5bee672`)

- `shellcheck -e SC1091,SC2015,SC2181` clean on all nine changed shell files.
- Both YAML files parse.
- `check-lockstep-pairs` **22/22**.
- The four directly-affected suites re-run with `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `GH_BOT`
  unset — `lean-evidence-selftest`, `lean-gate-selftest`, `check-lean-chain-selftest`,
  `second-shift-ci-check-selftest`, **4/4 `rc=0`**.
- CI on this exact head: `lint-and-selftests` **pass** (15m03), `selftests (macos, bash 3.2)`
  **pass** (16m08) — the full 66-suite sweep and the bash-3.2 lane, which is stronger evidence
  than a local sweep and is why I did not repeat it.

### The boundary's own verdict on this head

`pr-gates` is **red for exactly one reason**, and it is the reason this re-stamp exists: the
committed record declares `reviewed_patch_id 6783b0a8d790` while the branch now hashes to
`64fa261cca2b`. Every other arm passes in that same run — spec, delegated verdict, the issue-side
claim, the delegated PR-marker identity against a real bot marker, the inheritance chain (2
links), and the ratified intent gap. This record clears the one red.
