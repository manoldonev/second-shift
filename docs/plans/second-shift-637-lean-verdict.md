# lean review verdict — #637

verdict=approve
run_id: review-637-2
session_id: 17ff7c40-7401-4879-b39b-f709b9aea8f4
rounds: 2
pr: #677
reviewed_head: fd46ebd97be2af1e2da038d233e597c24c28b4e2
reviewed_patch_id: d804f59f6099abad05ada9df43b03f434cf8cc4c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #677 (issue #637)

Range read: `8d5d089..fd46ebd` (FULL branch diff — `G delta` declined to inherit round 1's
record because the branch's patch identity is *unchanged* since that round, so there is no
delta to narrow to; the whole diff was re-read).

Round 1 returned `needs-work` on a single blocker that lived entirely outside the ACs: the
`guard-budget` step of `pr-gates` was red. That is now fixed and the code content is
byte-identical to what round 1 read — so this round re-derived every AC independently rather
than inheriting, and re-ran the panel over the full range.

## Verdict: approve

## Findings

None. Six specialist reviewers over the full range returned zero findings; none went dark. No
cross-cutting finding survived my own read of the diff.

### Round-1 blocker — verified fixed

| # | R1 severity | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Blocker | **Fixed** | `pr-gates` → `guard budget guard` now reads `[guard-budget] ✓ guard/test shell mass: base 51720, HEAD 51761 (delta +41), covered by a 'Guard-mass:' trailer.` (run 32783298573, head `fd46ebd`). The remedy was the sanctioned one: a single **empty** commit carrying `Guard-mass: +41 test fixtures for the widened agent-contract census …`, no history rewrite — so round 1's `reviewed_patch_id` was never invalidated by the fix. The trailer is grep-anywhere over `MERGE_BASE..HEAD`, which is why it did not need to land on the commit that grew the mass. |

The `pr-gates` job is still red at handoff, and that is the expected pre-handoff state, not a
second blocker: the only remaining ✗ steps are `lean-evidence` / `lean-chain`, both reporting
the same fact — `verdict record … reads 'verdict=needs-work', not 'verdict=approve'`. That is
round 1's record, which THIS record supersedes. `lint-and-selftests` (4m38s),
`selftests (macos, bash 3.2)` (5m23s) and `mutation-sweep-pr` (11s) are all green on this head.

## Per-AC scoring

Every AC re-measured at `fd46ebd`, from a checkout of the PR head — not inherited from round 1.

| AC | Score | Evidence, re-measured at `fd46ebd` |
| --- | --- | --- |
| AC-1 — `corpus_files()` matches agent contracts as well as `SKILL.md`; fixtures still excluded by path | **satisfied** | `bash tools/prose-blockers.sh corpus` → **51** files: **26** `SKILL.md` + **25** agent contracts + **0** fixtures. Every one of the 25 matches the canonical shape `^plugins/[^/]+/agents/[^/]+\.md$` — the broader `-path '*/agents/*.md'` predicate has zero stragglers on this tree, checked by set-differencing the two patterns. The 12 fixture `agents/` directories under `plugins/review-toolkit/scripts/fixtures/**` are all excluded by the unchanged `grep -v '/fixtures/'`. |
| AC-2 — every censused construct carries a row; `check` reports zero undispositioned; existing rows unchanged except a genuine re-key | **satisfied** | `bash tools/prose-blockers.sh check` → exit **0**, `14 construct(s) over 51 file(s); record: 36 row(s)`, `✓ zero undispositioned constructs`. **Independently re-derived** (not inherited from round 1): ran the *pre-widening* tool (`git show 8d5d089:tools/prose-blockers.sh`, with `PROSE_BLOCKERS_ROOT` pinned to the reviewed worktree so it censused the same tree rather than `/`) and diffed the census id sets — exactly **1 added** (`pb-820b5ac8`), **0 removed**, **0 re-keyed**. |
| AC-3 — the disposition is reached on its merits under #610's rules | **satisfied** | `pb-820b5ac8` is `deleted`/`pointer-kept`. Read the site myself: `figma-faithful-spec-reviewer.md:98` is a `**[Warning]**` bullet whose parenthetical grades one gap `Blocker` (*"A missing Element Inventory is a Blocker — see Scene inventory completeness."*) — a severity **label** inside the reviewer's own rubric, not an instruction to decline. The row's load-bearing claim ("nothing checks an agent-emitted severity — this agent dispatches schema-free, its gate engine retired in #574") is **confirmed at source**, not taken on trust: the agent's own `LOCKSTEP-BEGIN artifact-reviewer-baseline-deltas` block states *"This agent is dispatched **schema-free** on the text contract (its former gate dispatcher, the figma.mjs engine, was retired in #574)"*, and its only referencing skill (`figma-faithful-spec/SKILL.md`) names it twice with no schema and no severity-consuming branch. So `promoted` would be wrong (no enforcing mechanism exists) and `gate-backed` would be wrong (no gate restates it) — `deleted` is the only defensible cell. Enum/consistency check: `pointer-kept` is a *surviving* action, which `check` requires the construct still to be in the tree for; it is, and `check` exits 0. |
| AC-4 — no promotion filed without checking the generator | **satisfied (vacuous, correctly declared)** | The one new row is `deleted`, not `promoted`, so nothing is filed for this AC to police. Verified there is no `promoted` row anywhere on the branch's diff. The malformed-record rule (a non-`deleted` row naming no enforcer is rejected) remains the mechanism that would catch a violation. |
| AC-5 — the answer/decline distinction is recorded in the header | **satisfied** | Both sites carry it and neither is a bare restatement of the other. `tools/prose-blockers.sh`'s `## Corpus` section states the reasoning in full ("its only outcome states are 'answer' and 'decline to answer'… blocking only where it tells the sub-agent to decline rather than answer… not every instruction that happens to contain a stop word while describing what the agent DOES once it proceeds"), and explicitly notes the *predicate is unchanged* — only the triage lens narrows. `docs/prose-blocker-triage.tsv`'s `AGENT CONTRACT FILES` block cross-references it rather than duplicating it, so no `LOCKSTEP` anchor is owed under CLAUDE.md's rule. |
| AC-6 — the selftest covers the widened corpus, both directions | **satisfied** | `bash tools/prose-blockers-selftest.sh` → **60 passed, 0 failed**. **Probed, not assumed**, and probed fresh this round in an isolated detached worktree at `fd46ebd` (removed afterwards; the reviewed worktree was never mutated): (M1) `corpus_files()` reverted to `-name 'SKILL.md'` only → **56 passed, 4 failed**; (M2) the fixture exclusion narrowed to `grep -v '/fixtures/.*SKILL\.md'`, so only fixture *agents* leak in → **56 passed, 4 failed**. M2 is the discriminating mutant: it proves the new exclude-direction assertion is load-bearing rather than shadowed by the pre-existing `SKILL.md` fixture assertion. Both mutants reverted; `git status --porcelain` clean after. |

## Design fidelity

`not-applicable`, and the arming signal is absent on **both** halves independently: the spec
`docs/plans/second-shift-637-lean.md` carries no `## Design` section and no `| RS-n |` rows, and
the repo's own `.claude/second-shift.config.json` declares no `design.provider`. Nothing to
staleness-check, hash-verify, or compare per RS row.

## What else was checked, and passed

- **The "exactly one new construct" claim, adversarially and independently.** Technique: a
  deliberately **broader** line-based grep of the *entire* stop-tier vocabulary read straight out
  of the tool's own `stops()` function (`refus(e|es|ed|ing|al|als)`, `ABORT`, `hard[- ]stop`,
  `is a blocker|are blockers|itself a blocker|counts as a blocker|is a hard blocker`,
  `is a reject|reject-and-stop|strict reject|reject at intake`, `hand(s|ing|ed)? (it )?back`,
  `not negotiable|not optional|not skippable`) over all 25 agent contracts, with **no**
  fence, blockquote, frontmatter or clause-position filtering — a strict superset of what the
  census can see. It returns **exactly one hit**, the same line. The predicate is not
  under-detecting sub-agent declines on agent prose; at the `stop` tier there genuinely are none
  besides this one. The issue's own "11 of 25" figure was a looser vocabulary reaching into the
  `bold`/`all` tiers, which the spec puts out of scope.
- **Predicate breadth.** `-path '*/agents/*.md'` is broader than the `plugins/*/agents/*.md`
  the comments describe — it would also match a nested `plugins/x/skills/y/agents/z.md` or a
  `README.md` sitting in an agents directory. On this tree the two sets are identical (0
  stragglers), and a wider census is the fail-safe direction for a tool whose only failure mode
  is an undispositioned row. Not a finding; recorded so a future reader does not re-derive it.
- **Selftest-cache hazard.** A widened corpus is a `tools/selftest-cache-inputs.tsv` trap:
  a suite with a row there is skipped when its *declared* inputs are unchanged, so widening what
  the tool READS without widening the declared inputs would silently skip the gate.
  `prose-blockers-selftest.sh` has **no** row, so it always runs. Clean.
- **CI actually runs it.** The suite *is* on `tools/selftest-suite-timings.tsv` (15s, above the
  file's `threshold-seconds 9`), so a bare `run-selftests.sh` defers it — including the
  no-`--full` sweep the PR body cites. Both CI selftest jobs pass `--full`, so the suite really
  executed on this head in `lint-and-selftests` and in `selftests (macos, bash 3.2)`, and the
  build additionally ran it standalone. No coverage gap; the PR body's sweep line is just
  weaker evidence than it reads.
- **Mutation-sweep obligations.** `tools/prose-blockers.sh` and its selftest have **no** row in
  `mutation-catalog.tsv`, `mutation-baseline.tsv` or `mutation-exclusions.tsv`, so this guard
  edit carries no re-anchoring or re-baselining obligation. `mutation-sweep-pr` is green (11s).
- **Frozen-file discipline.** No plugin `version`, no `CHANGELOG.md`, no
  `marketplace.json` `metadata.version` touched. `Changelog:` trailer present and substantive on
  the feat commit; `Guard-mass:` trailer present. Commit verb is `feat:` — the honest verb for a
  new capability in this repo, not a downgraded `chore:`.
- **Blast radius.** The only non-selftest consumers of `prose-blockers.sh` are
  `docs/prose-blocker-triage.tsv` (the record) and a *comment* in `.github/workflows/ci.yml`
  explaining why #610 D-9 left the tool unwired. No CI step invokes it, so the widened census
  cannot red an unrelated lane — consistent with "Wiring `check` into CI" being out of scope.

## Reviewer panel

Six specialists over the full range; **none went dark**, all returned `approve` with zero
findings.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

Suppressed (below the confidence bar, surfaced for visibility): two from Security (conf. 30 / 25
— `sed "s|^$ROOT/||"` interpolation, pre-existing and not attacker-reachable; and the widened
`find` reading repo-tracked prose with no credential path), and one from Scope Completeness
(conf. 55 — it could not itself confirm the `#574` schema-free-dispatch claim underpinning the
`deleted` disposition). **That last one I resolved by hand rather than leaving suppressed** — see
AC-3 above; the claim is stated verbatim in the agent's own LOCKSTEP block and holds.

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`) on a bash/markdown/TSV
diff. Not a coverage gap. `db-reviewer`, `pipeline-reviewer` and `unit-test-mutation-reviewer`
have no trigger surface here. `scripts/check-review-context.sh` → clean (no `review-context/`
dir), so no reviewer extension file went silently unread.

## Strengths

- **The census claim is measured, and the measurement survives an independent re-run.** Running
  the pre-widening tool against the post-widening tree and diffing id sets is the right shape of
  evidence for a content-keyed census, and it reproduced exactly (1 added / 0 removed / 0
  re-keyed) in a session that did not write it. The build explicitly refused to inherit the
  issue's own rough "11 of 25" grep estimate and said so in AC-2 rather than quietly matching it.
- **The new selftest arms assert in both directions at both layers** — a real agent contract is
  censused and a fixture one is not, at the corpus listing *and* at the stop-tier construct
  pickup. That is precisely what makes mutant M2 killable, and M2 is the mutant a
  one-direction suite would have let through.
- **The disposition is argued from the enum outward, not backfilled.** `deleted`/`pointer-kept`
  is the only cell the three rules leave open once you establish nothing consumes the severity,
  and the row states that in one line as the record's own contract requires.
- **The header prose earns AC-5 honestly** by stating that the *predicate is unchanged* and only
  the *triage lens* narrows — the exact distinction a later reader would otherwise re-derive
  wrongly — and the two sites are deliberately non-identical, so no lockstep anchor is owed.
