# Plan — #222: enumerate in-progress merge/rebase in the non-base-branch posture

## Context

`plugins/dev-pipeline/skills/run/SKILL.md` **[VERIFIED]** carries a **Non-base-branch posture** paragraph (line 364) that enumerates three checkout states: pin established + clean tree → proceed silently; **dirty working tree** → WARN and proceed; **pin not establishable** → fail closed. It never names an in-progress merge or rebase.

An operator-invoked run met a checkout with `MERGE_HEAD` present and four conflicted paths. The executing agent read that as an unenumerated, scarier state rather than as "dirty working tree", invented a blocking gate the contract forecloses, and stopped **before the claim** to ask the operator. The contract already said proceed, so the stop was a deviation — but the prose gives an agent nothing to classify the state against, so the misreading stays available to the next run.

The machinery was correct throughout: the base branch is resolved from config (`topology.repos.<host>.baseBranch`), and the pin/cut both use `origin/<baseBranch>`. Only the prose is thin.

## Assumptions

1. **The `SKILL.md` paragraph is the surface where the failure occurred.** It sits in the pre-Stage-1 "Dynamic Context" block; `stages/1-intake.md` Step 1.P runs *after* the claim. The observed stop was pre-claim, so the paragraph — not Step 1.P — is what the agent classified against.
2. **Merge/index state is genuinely per-worktree.** The issue verified this on a synthetic repo:
   `worktree add` during a conflicted merge returned rc=0; the new worktree was clean with `MERGE_HEAD`
   absent; the original merge stayed byte-intact. Adopted as established, not re-verified.
3. **The fix is prose-only.** No detection predicate changes, no new state field, no behavior change to any script.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does the fix also touch `stages/1-intake.md` Step 1.P, which enumerates the same three predicates? | No — out of scope. The observed failure was pre-claim and Step 1.P runs post-claim; Step 1.P already anchors its dirty predicate to a concrete command (`git status --porcelain` non-empty) so it does not invite the same misread; and AC-4 forecloses the lockstep row that would be this repo's sanctioned way to couple two copies. | codebase-derived |
| D-2 | AC-1 says an in-progress merge/rebase belongs to the WARN class "conflicted or not", but is `git status --porcelain` non-empty actually a superset of merge/rebase-in-progress? | No. Measured on a synthetic repo: conflicted merge → `UU` (non-empty); conflicted rebase → `UU` (non-empty); `rebase -i` paused at `break` with a clean tree → `rebase-merge` present but porcelain **empty**. The prose will therefore place merge/rebase-in-progress in the **proceed** class — WARN when the tree is dirty, silent when it is not — and state that it is never a stop. That is AC-1's intent (no blocking gate) and is true under the existing mechanism. | codebase-derived |

## Affected files

- `plugins/dev-pipeline/skills/run/SKILL.md` **[VERIFIED]** — the Non-base-branch posture paragraph at line 364. Single-line edit.

## Reuse inventory

none — no new helpers introduced. This change adds prose to one markdown paragraph; it introduces no code, no script, and no shared abstraction.

## Implementation steps

1. **Step 1** — In `plugins/dev-pipeline/skills/run/SKILL.md`, replace the Non-base-branch posture paragraph (line 364) with a revision that:
   - appends the per-worktree clause to the pin sentence — merge/index state is per-worktree, so
     `worktree add` neither reads nor disturbs it (AC-2);
   - widens the **dirty working tree** predicate so it names an in-progress merge or rebase, conflicts
     and all, directly inside the WARN-and-proceed clause — AC-1 as written;
   - closes with one sentence that fixes the classification end-to-end: such a state is never a stop,
     riding the dirty-tree predicate when it leaves changes behind and the clean predicate when it does
     not. This resolves the paused-clean-rebase edge (D-2) without weakening the AC-1 clause above;
   - keeps every base-branch reference generic (`origin/<baseBranch>` / "the configured base"), introducing no `main`/`master`/`alpha` literal (AC-3).
2. **Step 2** — Commit with a `Changelog:` trailer. `CLAUDE.md` requires one on every `plugins/**` PR
   and `scripts/check-changelog-trailer.sh` enforces it in CI; the change is consumer-visible prose, so
   it takes a real entry rather than `Changelog: none`. Verb is `docs:` (patch bump).
3. **Step 3** — Run the repo verification triad (shellcheck / jq / selftests) to confirm the markdown edit broke nothing that reads this file.

## Test strategy

**No test is added** — AC-4 is explicit, and it matches this repo's tier map: prose in a markdown file gets nothing. A grep for the new literals would be exactly the prose-presence guard `CLAUDE.md` forbids ("Grepping a literal out of a markdown file asserts only that prose contains words"). No lockstep row either: `scripts/lockstep-manifest.tsv` **[VERIFIED]** has no row pairing `SKILL.md`'s posture paragraph with Step 1.P today, and AC-4 forecloses adding one.

Verify-after (this is a docs change, not a behavior change): the existing selftest suite must stay green, proving the edit did not disturb any script that parses `SKILL.md`.

Unit test surface: **skip** — documentation-only, and this repo configures no `unitTestScope`, so there is no mutation surface.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | In-progress merge/rebase explicitly in the WARN-and-proceed class | Step 1 | — no test (non-functional) |
| AC-2 | Paragraph states merge/index state is per-worktree, so `worktree add` is unaffected | Step 1 | — no test (non-functional) |
| AC-3 | Added prose keeps the base branch generic, no hardcoded literal | Step 1 | — no test (non-functional) |
| AC-4 | No selftest and no lockstep row added | Step 1, Step 3 | — no test (non-functional) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Risk: the new prose over-claims.** Saying "conflicted or not → WARN" verbatim would assert a classification the mechanism does not produce for a paused-clean rebase (D-2). Mitigated by the proceed-class wording, which is true in all three measured cases.
- **Risk: divergence from Step 1.P.** Deliberate and reasoned (D-1); no CI guard couples them today and AC-4 forbids adding one. If the two copies later need coupling, that is a separate ticket with a lockstep row.
- **Rollback:** revert the single commit. No state, schema, or behavior touched.

## Out-of-scope

- `stages/1-intake.md` Step 1.P and its predicate bullets (D-1).
- Any change to the detection predicate itself (e.g. adding a `MERGE_HEAD` / `rebase-merge` check to the `guardOutcome` computation).
- Any selftest, lockstep row, or CI guard (AC-4).
- The version bump and `CHANGELOG.md` — derived at release time, frozen in feature PRs.

Unverified references: none.
