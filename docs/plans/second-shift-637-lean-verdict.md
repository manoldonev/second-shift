# lean review verdict — #637

verdict=needs-work
run_id: review-637-1
session_id: 5310b387-c4b7-4b21-9200-3e4d8ca8712a
rounds: 1
pr: #677
reviewed_head: 5e5d3432fb1752c95b6ffd41a1c2f7e51343384c
reviewed_patch_id: d804f59f6099abad05ada9df43b03f434cf8cc4c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #677 (issue #637)

Range read: `8d5d089..5e5d343` (full branch diff — root round, nothing to inherit).

Widening `corpus_files()` to census `plugins/*/agents/*.md` alongside `SKILL.md`. Every
acceptance criterion is satisfied and independently re-measured. One blocker sits outside the
ACs: an enforced repo CI gate is red on this head for a reason the verdict record will not fix.

## Verdict: needs-work

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | branch commit trailers | `pr-gates` is red on the **guard-budget** gate, not on the (expected) absent verdict record. `scripts/check-guard-budget.sh` measures guard/test shell mass grown by **+41** lines with no `Guard-mass:` trailer anywhere in `8d5d089..HEAD`. Reproduced locally from the reviewed head at a clean tree: `[guard-budget] ✗ guard/test shell mass grew by 41 lines with no reason recorded: base 51720 (8d5d089), HEAD 51761.` The branch carries a `Changelog:` trailer but no `Guard-mass:` one. |

**Why this is a blocker rather than a note.** It is not the pre-handoff `pr-gates` red every lean
PR carries (`check-lean-chain.sh` refusing an absent verdict record). It is a second, independent
failing step in the same job, and pushing the verdict record does not clear it — the PR stays
unmergeable. It must be fixed *before* the record lands, because the record is patch-bound and a
later trailer-carrying commit or amend re-stamps it.

**The patch.** The gate greps `git log "$MERGE_BASE..HEAD" --format=%B` for `^Guard-mass:`, so the
trailer survives the squash from any commit on the branch — an amend is not required. Add:

```
Guard-mass: +41 the AC-6 selftest coverage the ticket mandates (agent() fixture helper,
  a censused fixture agent contract, an excluded fixture copy, four assertions) plus the
  corpus_files() predicate widening and its comment.
```

+41 is the gate's **own** measured delta and is the number of record; the raw `--numstat` figure
(+63/-7 over the two `*.sh` files) is not, since the classifier excludes comment and blank lines.
Deleting mass elsewhere to get back under budget is the other sanctioned remedy, but not the right
one here: the added mass *is* AC-6, which the ticket requires.

## Per-AC scoring

| AC | Score | Evidence, re-measured at `5e5d343` |
| --- | --- | --- |
| AC-1 — `corpus_files()` matches agent contracts as well as `SKILL.md`, fixtures still excluded by path | **satisfied** | `bash tools/prose-blockers.sh corpus` → **51** files = 26 `SKILL.md` + 25 agent contracts + **0** fixtures. Every one of the 25 matches the canonical `plugins/<plugin>/agents/<name>.md` shape (checked against `^plugins/[^/]+/agents/[^/]+\.md$` — no stragglers from the broader `-path '*/agents/*.md'` predicate). The 18 fixture `.md` files under `*/fixtures/*/agents/` are all excluded. |
| AC-2 — every censused construct carries a row; `check` reports zero undispositioned; existing rows unchanged except a genuine re-key | **satisfied** | `bash tools/prose-blockers.sh check` → exit 0, `14 construct(s) over 51 file(s); record: 36 row(s)`, `✓ zero undispositioned constructs`. Ran the **pre-widening** tool (`git show 8d5d089:tools/prose-blockers.sh`) against this same tree and diffed the id sets: exactly one id **added** (`pb-820b5ac8`), **zero** removed, zero re-keyed. The 35 base rows are byte-identical (`diff` over `^pb-` lines shows only the appended row). |
| AC-3 — disposition reached on its merits under #610's rules | **satisfied** | `pb-820b5ac8` is `deleted`/`pointer-kept`. Read the site: `figma-faithful-spec-reviewer.md:98` is a `**[Warning]**` bullet whose parenthetical grades one gap `Blocker` — a severity **label**, not a decline instruction, so `deleted` (never a control) is right and `gate-backed` would be wrong. The "dispatches schema-free since #574" claim is corroborated by the same file at `:119` and by the sibling agents; #574 is indeed "Four shipped Workflow engines lost their only dispatcher in #348". `pointer-kept` is right too — the censused block is the whole Warning bullet, and deleting it would remove a live rule. `deleted`/`pointer-kept` is an established pair (3 prior rows), not a novel one. |
| AC-4 — no promotion filed without checking the generator | **satisfied** | Correctly declared N/A by construction: the record's only new row is `deleted`, and no row on this branch is `promoted`. Nothing to police. |
| AC-5 — the answer/decline distinction is recorded in the header | **satisfied** | Both headers carry it: `tools/prose-blockers.sh`'s `## Corpus` section ("its only outcome states are 'answer' and 'decline to answer'… blocking only where it tells the sub-agent to decline") and `docs/prose-blocker-triage.tsv`'s `AGENT CONTRACT FILES` block, which cross-references it rather than restating it. The two are deliberately non-identical prose, so no `LOCKSTEP` anchor is owed. |
| AC-6 — the selftest covers the widened corpus, both directions | **satisfied** | `bash tools/prose-blockers-selftest.sh` → **60 passed, 0 failed**. The four new assertions cover both the corpus listing and the stop-tier pickup, in both the include and exclude direction. **Probed, not assumed** — two mutants in a throwaway worktree, each reverted after: (M1) `corpus_files()` reverted to `-name 'SKILL.md'` only → **4 failures**; (M2) the fixture exclusion narrowed to `grep -v '/fixtures/.*SKILL\.md'` so fixture *agent* copies leak in while fixture SKILLs still do not → **4 failures**. Both new arms are load-bearing. |

## Design fidelity

`not-applicable`. The spec carries no `## Design` section, and the repo's own
`.claude/second-shift.config.json` declares no `design.provider` — the arming signal is the
conjunction of the two, so neither half is present.

## What else was checked, and passed

- **The "exactly one construct" claim, adversarially.** Ran a deliberately **broader** line-based
  grep of the entire stop-tier vocabulary (`refus*`, `ABORT`, `hard-stop`, `is a blocker`,
  `is a reject`, `hand back`, `not negotiable|optional|skippable`) over all 25 agent contracts,
  with no fence/blockquote/frontmatter exclusion — a strict superset of what the census sees. It
  returns **exactly one hit**, the same line. The predicate is not under-detecting sub-agent
  declines on agent prose; there genuinely are none at the `stop` tier. The issue's "rough pass
  hits 11 of 25" was a looser vocabulary reaching into the `bold`/`all` tiers, which the ticket
  puts out of scope.
- **The stale-claim sweep.** No "out-of-census residual" language survives anywhere in `docs/`,
  `tools/`, `scripts/` or `plugins/` — both sites the ticket names were updated, and there is no
  third.
- **Cache-skip safety.** `tools/prose-blockers-selftest.sh` has **no** row in
  `tools/selftest-cache-inputs.tsv`, so it always runs. Had it carried one, the widening would
  have silently under-declared its inputs (the suite's last assertion reads the real tree).
- `shellcheck -e SC1091,SC2015,SC2181` on both changed scripts → clean (0.11.0 local).
- bash-3.2 safety: no `declare -A`, no GNU-only flags; the `selftests (macos, bash 3.2)` CI job
  passes on this head.
- `lint-and-selftests` (4m04s) and `mutation-sweep-pr` (14s) both pass on this head — not re-run
  here, per the standing rule against re-running verbatim what CI already ran.

## Reviewer panel

Six specialists over the full range; none went dark.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`) on a bash/markdown diff. Not a
coverage gap. `db-reviewer` and `pipeline-reviewer` have no trigger surface here.

The sole blocker is a `[Cross-cutting]` finding — no specialist reviewer reads CI gate state, so it
lands here or nowhere.

## Strengths

- The "exactly one construct" result is *measured*, not asserted: the build ran the census before
  and after and said which id appeared, and explicitly refused to inherit the issue's own rough
  grep estimate. That estimate would have been wrong by 10x, and the spec says so in AC-2 rather
  than quietly matching the number.
- The new selftest arms assert in **both** directions (a real agent contract is censused, a
  fixture one is not) at **both** layers (corpus listing, stop-tier pickup). That is what made
  mutant M2 — a fixture exclusion that still works for `SKILL.md` — killable.
- The header prose earns AC-5 honestly: it states that the *predicate is unchanged* and only the
  *triage lens* narrows, which is the distinction a later reader would otherwise re-derive wrongly.
