# lean review verdict — #604

verdict=approve
run_id: review-604-1
session_id: 7a7cdae2-f34e-47c2-ae31-b525c96df807
rounds: 1
pr: #606
reviewed_head: 414521fd2e9624f99d558665a186b1e692d7093c
reviewed_patch_id: f0dd7254d10175bcf0d6a78c4074e45cc25bfa9e
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #606 (issue #604)

**Verdict: approve.** No blockers. Three warnings, none of which blocks the merge.
Panel 6/6, none dark. Range reviewed: `3b55bc7..414521f` (full branch diff — round 1).

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | `check-lockstep-pairs.sh` takes no manifest argument; it walks, groups by anchor and compares every member. Ran CI's own invocation (no argument) from the reviewed checkout: `21 anchor(s) checked, 0 failed`. `scripts/lockstep-manifest.tsv` is gone, and `ci.yml:143` runs the script bare. |
| AC-2 | **satisfied** | Size-1 failure verified live on a constructed tree, and it names both: `FAIL: orphan-demo: only ONE site (sub/thing.sh)`. All six orphans have zero live markers (`stage8-secondary-review`'s sole mention is `docs/plans/acme-260.md:220`, doubly out of scope — excluded path AND mid-sentence, so it fails the grammar). Each in-code site left a `SINGLE-SITED:` note stating why and what would justify re-adding. |
| AC-3 | **satisfied** | `seam-scrub` reports live as `subset-of: superset preflight.sh ⊇ lean-gate.sh`. Suite cases (g) narrowing, (h) absent token reds, (i) direction reversal reds, (j) member disagreement, (j2) two supersets, (k) unknown token — all pass. |
| AC-4 | **satisfied** | `EXCLUDED_PREFIXES='docs/plans/'` is a named constant carrying its reason as prose. Armed by the new catalog row `lockstep-discovery-scope`, which I confirmed is **killed** by case (l), with (l2) as the over-reach negative. |
| AC-5 | **satisfied** | `docs/testing.md:466` *Couplings considered and declined*, organised into "Unanchorable" and "Retired — the subject itself is gone" rather than dumped, with the behavioral guard named in almost every entry. |
| AC-6 | **satisfied** | Enumerated **every** live `LOCKSTEP-BEGIN` site and checked each for adjacent rationale. All carry it — most immediately above the marker, several (`lean-pr-marker`, `contribution-compare`, `audit-row-fields`, `checked-call`) immediately below it inside the block. See warning W2 for the one clause that did not survive. |
| AC-7 | **satisfied** | Zero live references to `lockstep-manifest` outside `docs/plans/**`; the historical plan docs are untouched, as required. |
| AC-8 | **satisfied** | 24 cases, 0 failed, covering every shape the AC names. Registers re-anchored — see "Verification I ran" below: I did not take the PR's word for the baseline removals. |
| AC-9 | **satisfied** | `CLAUDE.md:177` tier-map row now reads "a `LOCKSTEP-BEGIN <anchor>` marker on **each** copy — they are discovered and grouped, never registered" / "the files themselves"; `docs/testing.md` carries the discovery-model section and both known trades. |

**9 of 9 satisfied.** The spec was committed once (`7861d73`) and never amended — no
after-the-fact fitting of the ACs to the diff.

## Verification I ran (not inherited from the PR body)

**The PR-lane mutation sweep DEFERRED this guard.** `mutation-sweep-pr` is green, but its log
reads `scripts/check-lockstep-pairs.sh deferred-to-nightly … 0 0 0` — the 6-fast-guard cap. So
the green sweep job proves nothing about the guard this PR rewrites, while the PR **removes five
baseline rows**. CLAUDE.md warns precisely here: deleting a row that records a site as unkillable
reds the next sweep on the survivor it exists to accept.

So I ran the sweep myself, scoped to that one guard via an isolated probe worktree and a scratch
commit (there is no `--only` flag, and the cap is hardcoded):

```
scripts/check-lockstep-pairs.sh  swept  applied=11 killed=11 survived=0
```

Zero survivors, so all five removals are safe. All three catalog rows were applied and **KILLED**:
`lockstep-discovery-scope`, `lockstep-grammar-anchor`, and `lockstep-normalize` — the last being
one of the removed baseline rows, which the PR claimed is now killed rather than unkillable. It is.

**Directional control on the live corpus.** A green checker proves nothing until the wrong tree
reds. I injected real drift into the `audit-row-fields` block and the checker failed correctly,
naming the anchor and both files.

## Warnings (none blocking)

**W1 — a stray untracked file can MASK the size-1 failure locally.** This is the round's own
finding; no reviewer raised it. The walk is `find`-based by D-4 (deliberate — fixture trees are
not git repos), and it prunes only `.git` and `node_modules`. It therefore reads untracked
working-tree files. Reproduced in both directions on a constructed tree:

```
A: single-sited anchor            -> FAIL: orphan-demo: only ONE site (sub/thing.sh)
B: same tree + sub/thing.sh.bak   -> PASS: orphan-demo (verbatim): sub/thing.sh sub/thing.sh.bak agree
```

An editor backup, or a `.orig`/`.rej` left by a conflict resolution, turns a genuine orphan into a
green PASS — masking the exact property this PR adds. **CI is unaffected**: `actions/checkout`
yields a clean tree, so the merge boundary's authority is intact. It bites the local run the
CLAUDE.md recipe recommends before pushing. Not a blocker, and cheap to close later: prune
`*.bak`/`*.orig`/`*.rej`, or prefer `git ls-files` when the root is a git repo and fall back to
`find` for the fixture trees D-4 cares about.

**W2 — one clause of #601's `contribution-compare` rationale was dropped, not relocated.** The
deleted manifest row explained why those two copies must be held identical rather than shared:
"Neither file can import the other: lean-gate.sh runs from a lane worktree and lean-evidence.sh is
fetched standalone at a pinned ref by a consumer's CI." That sentence is at no site now. AC-6 is
still satisfied — the anchor carries ~20 lines of substantive rationale directly below its marker
in both files — and the contract itself is fully enforced (the group discovers and compares
clean). This is a documentation loss from the base-merge resolution, which the spec's Sequencing
section pre-authorised as "keep the delete, no row needed"; it discussed the row, not its prose.
One comment line closes it.

**W3 — the suite sits on the slow-list boundary.** My scoped sweep emitted
`WARN: slow-list drift: check-lockstep-pairs-selftest.sh measured 5s (>= 5s) but
tools/mutation-slow-suites.tsv does not record it`. Independently timed twice at ~4.1s wall, so it
straddles the bar. Membership drift is a precheck warn and never a red, and adding the row would
*defer* this guard out of the PR lane — the wrong trade for a guard this PR just rewrote. Leaving
it absent is defensible; recorded so the nightly warn is not read as a regression.

**Nit.** The PR body's verification table says `20 anchors`; the head measures **21**, because the
base merge brought in #601's `contribution-compare` pair. The table is honest for the tree it was
measured on, just pre-merge.

## Findings dismissed

**`scope-completeness-reviewer`'s AC-6 blocker (confidence 95) is factually wrong and I dismissed
it.** It asserted that "neither lean-gate.sh:830 nor lean-evidence.sh:515 has any LOCKSTEP prose
above or inside the block". Both have roughly twenty lines of it inside the block, beginning
directly below the marker: "THE BRANCH'S OWN CONTRIBUTION, AS LINES (#597, D-2/D-3/D-4)…", then
"WHY A HASH CANNOT ANSWER THIS", then "THE COMPARISON THAT CAN". The reviewer checked only above
the marker — its own suppressed note shows it knew the below-the-marker pattern existed elsewhere.
Its narrower point survives as W2, at warning severity.

**Its `major` on the baseline rows is closed by evidence, not dismissed.** It said outright that it
could not confirm kill status within budget and asked for a scoped sweep before merge. That sweep
is above: `applied=11 killed=11 survived=0`.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (3 suppressed, all <50 confidence) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 0 |
| Scope Completeness | Fail (1 blocker dismissed, 1 major closed by evidence) | 2 |

a11y and design-fidelity were not routed: no changed path matches
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`) — this is a shell/docs repo.
Not a coverage gap.

## Strengths

- **The ticket's own thesis, demonstrated live by its own merge.** #601 shipped
  `contribution-compare` as two markers *plus* a manifest row. The base merge deleted the row, and
  the pair is now discovered and compared automatically with no registration. The conflict this PR
  exists to abolish was the last thing it had to resolve.
- **The size-1 property is the real deliverable and it found six live orphans**, three of them
  cited in plan documents as proof that copies "still matched byte-for-byte" while nothing was
  comparing them. That is a false coverage signal removed, not just a file deleted.
- **The two mutation defects were fixed rather than baselined.** The `cd … && pwd` fail-open was
  the serious one — it made CI's own no-argument invocation report a green contract check over a
  tree it never read, and zero anchors is zero failures. The live-corpus case now invokes the
  checker the way CI does and asserts a non-zero anchor count, which is what separates "everything
  agrees" from "nothing was read".
- **The exclusion is data with a reason, not a glob**, and it is armed by a catalog row because no
  generic operator reaches a bare assignment — the one hole in the walk has the one signal that
  can see it widen.
