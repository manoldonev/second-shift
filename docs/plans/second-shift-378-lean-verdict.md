# lean review verdict — #378

verdict=needs-work
run_id: review-378-1
session_id: a5c58cb8-6612-43ff-8e6b-bad002355bbb
rounds: 1
pr: #382
reviewed_head: fa71e2779900ba1efbbecf65b3fd1a3a4c3818b8
reviewed_patch_id: 939314f173255b2419e84f426b8e924504c1307e
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

Round 1 — full branch range (`3308d7a..HEAD`, 8 files). Nothing to inherit; this round read everything.

Reviewed through `review-lead`: 7 specialists dispatched via `code-review.mjs`, none dark. Scope
Completeness returned PASS. Every claim below that names a before/after was reproduced by running
the code, not by reading it.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Both conditional enumerations name the dimension (`SKILL.md:131` never-suppressed sentence, `:166` Routing table). Trigger is config-sourced with the shipped default (`:173`), matching is model judgment (`:175`), three-way provider map incl. the no-provider default (`:179-185`), never depth-suppressed. |
| AC-2 | satisfied | Ran the three sub-registry extractions against the branch SKILL.md: all three yield the identical 12 names, so DRIFT is clean. Bold Routing entries are bare, panel parenthetical is qualified and the parse strips it. `check-reviewer-references.sh` exits 0 in the worktree — the commit hook does not deny. |
| AC-3 | satisfied | Real panel + absent design root → exit 0 with a notice naming BOTH entries (executed). Suite is 11/11. All four mutants the PR body claims were reproduced and each was killed by exactly the claimed case. See blocker B2 — a fifth mutant survives; that is a testing-doctrine gap, not an AC-3 letter failure, and the AC is scored on its letter. |
| AC-4 | satisfied | Executed, not inferred: `reviewers.remove` of BOTH names → exit 0, no REMOVE-UNKNOWN; `review-context/{design,figma}-faithful-reviewer.md` → `check-review-context: clean`; typo'd `figma-faithful-reviewr.md` control → `UNKNOWN-REVIEWER-FILE`, exit 1. Fails closed as claimed. |
| AC-5 | **unsatisfied** | Blocker B1. The toolkit-absent disposition is specified only for a DECLARED provider, so on the no-provider default path the dimension goes silently unrun — which is what this AC's "never silent" forbids. |
| AC-6 | satisfied | `run-lean/SKILL.md` absent from `git diff origin/main...HEAD --name-only`. |
| AC-7 | satisfied | No paths under `stages/`; `code-review.mjs` and `check-model-tiers.sh` unchanged and verified to already carry both `design-toolkit:*-reviewer` model entries and `resolve_sibling_plugin_root`. No new reviewer agents — the new agent-shaped files are all selftest fixtures. |
| AC-8 | satisfied | Local sweep from the branch worktree, no `SKIP_STRESS`, `CLAUDE_CODE_SESSION_ID` unset: shellcheck 0, `jq empty` 0, all `*-selftest.sh` 0, all three `*-selftest.mjs` 0. CI agrees — `lint-and-selftests` and `selftests (macos, bash 3.2)` both pass. `pr-gates` fails only on the absent verdict record, which this round produces. |

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `review-lead/SKILL.md:189`, `:306` | Toolkit-absent degrade is unreachable on the no-provider default path — AC-5's "never silent" fails there. |
| B2 | blocker | `check-reviewer-references.sh:127-128` | `figma-faithful-reviewer`'s exemption entry is unguarded; the mutant dropping it SURVIVES the whole suite and false-denies every design-toolkit-less consumer's commits. |
| W1 | warning | `check-reviewer-references.sh:116-119` | The installed-cache resolution branch is dead code in every selftest — the same branch whose absence historically denied every consumer commit. |
| W2 | warning | `check-reviewer-references.sh:282-290` | The SHADOW drift tripwire silently regressed for the two newly-registered names (reproduced: `ORPHAN`/exit 1 on main → exit 0/silent on the branch). |
| W3 | warning | `review-lead/SKILL.md:64-65` | The relocated config read drops `SECOND_SHIFT_CONFIG` and repo-root anchoring, so a declared provider can silently route the WRONG reviewer. |
| S1 | suggestion | `review-lead/SKILL.md:165` | `a11y-reviewer`'s standalone trigger narrows by default; correct as a relocation, but undeclared in the spec. |
| S2 | suggestion | `check-reviewer-references.sh:33` | Failure-class summary still says "EITHER root" after the three-root rewrite. |
| S3 | suggestion | `check-reviewer-references-selftest.sh:2` | Header still calls it "the two-root reviewer-registry gate". |
| S4 | note | `check-config-shadowing.sh:20` | Its `stages/8-code-review.md` row dies at the wipe and cannot reach the new reader in another plugin. Not this PR's red — hand-off for the wipe. |

### B1 — the toolkit-absent disposition never fires for the commonest consumer

Both clauses gate on a declared provider:

- `SKILL.md:189` — "**If config declares `design.provider`** but the design-toolkit agent type is not available to dispatch..."
- `SKILL.md:306` — "**Config declares `design.provider`**, a changed path *did* match, but the design-toolkit agent type is not available..."

But the provider map's third row selects `design-faithful-reviewer` when the key is **absent** — and `design.provider` is optional while `design-toolkit` is optional, so "no provider declared, design-toolkit not installed, diff touches web components" is the ordinary shape of a consumer running review-toolkit alone. That case falls through both Step 4c bullets: it is not an unmatched surface (a path *did* match), and config does not declare a provider. The dimension is selected, found undispatchable, and vanishes with no note.

That is precisely what Step 4c's own preamble says must not happen — "a whole dimension is silently absent while the round looks green" — and what AC-5 forbids in the words "never silent".

The two halves of the same degrade also disagree: the lint's exemption is correctly **unconditional** (it fires whenever the sibling root resolves empty, whatever the provider), while the skill's is conditional. Fix: re-condition both clauses on *the design-fidelity dimension was selected* (by any provider-map row, including the no-provider default), not on the provider key being present.

### B2 — the exemption's declared set is half-unguarded (mutant verified surviving)

`DESIGN_TOOLKIT_PANEL` declares two names. Deleting `figma-faithful-reviewer` from it and running the paired suite:

```
[check-reviewer-references-selftest] 11 passed, 0 failed
```

All green. With that same mutant, the real shipped panel against an absent design-toolkit:

```
notice: design-toolkit is not installed — ... its panel entries (design-faithful-reviewer) are exempt from DANGLING.
DANGLING: review-lead registry references 'figma-faithful-reviewer' but no agent file exists in ...
exit 1
```

Exit 1 from a script wired as a PreToolUse deny on `git commit` — so every consumer running review-toolkit without design-toolkit is commit-blocked. That is verbatim the regression the PR body gives as the reason the exemption exists at all ("Without that, every consumer running review-toolkit without design-toolkit would have had its commits denied by this PR"), and it is the change's headline safety property.

Root cause: all three design-* cases drive the `plugin-design` fixture panel, which names only `design-faithful-reviewer`; the one case that uses the REAL panel (`shipped-SKILL lockstep`) runs with design-toolkit PRESENT. The cell (real panel × toolkit absent) is never exercised.

The PR's own mutation table is honest — all four rows reproduce, each killed by exactly the claimed case — it is simply silent on this fifth mutant. `unit-test-mutation-reviewer` reached the same finding independently (major, 85); `test-coverage-reviewer` saw it at 55 and suppressed it as "coverage is indirect via the real-root lockstep test, which is verified sufficient" — that reasoning is what the execution above falsifies.

Fix, one case in a file the diff already edits:

```bash
run_cli "$REAL_PLUGIN" "$EMPTY_CONSUMER" "" "$NO_DESIGN"
# assert: exit 0, no `DANGLING:`, and a notice naming BOTH declared names
```

It doubles as the lockstep between the declared set and the shipped panel — the coupling nothing currently checks.

**Scoring note / override.** This is a blocker without being an AC failure. AC-3's letter asks for a case for each of present-toolkit and absent-toolkit, and both exist; the behavior ships correct today (verified). The bar it fails is the repo's own, in CLAUDE.md: a new gate contract must be killable by its paired suite, and "a gate nothing composes against is a gate the next `#204` walks straight through." Blast radius (every consumer commit), a one-line fix, and two independent finders put it over the line. Stated explicitly so the next build round can push back with evidence rather than guess at the reasoning.

### W1 — the cache-layout branch is dead code in every selftest

`resolve_design_toolkit_root`'s versioned-sibling glob (`:116-119`) is never reached: `design-present`/`design-absent` both set `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT`, which short-circuits at the override branch, and `shipped-SKILL lockstep` always resolves via the first repo-layout candidate because this marketplace repo ships `plugins/design-toolkit` on disk.

The sibling `check-model-tiers-selftest.sh:311-326` has exactly the case for the function this one says it "mirrors verbatim", and its comment records why it exists: *"0.1.0 shipped resolving only the marketplace-repo sibling path and UNLOCATABLE-denied every consumer commit."* The copy ships without the case that incident bought.

Consequence is not merely a missed detection: if the glob resolves a stale versioned sibling that has `agents/` but lacks one of the two files, `DESIGN_AGENTS` is non-empty, the exemption is skipped, and the result is a DANGLING denial. A `tail -1` → `head -1` mutant (oldest cached version instead of newest) or dropping the `[ -d "$cand/agents" ]` filter survives today. Port the fabricated-cache-tree case.

### W2 — the SHADOW tripwire regressed for exactly the two names this PR registers

One fixture, `<consumer>/.claude/agents/design-faithful-reviewer.md`, run against both trees:

- **main**: `ORPHAN: consumer reviewer 'design-faithful-reviewer' ... is registered nowhere`, exit 1
- **this branch**: exit 0, no output

The name now satisfies DANGLING through the consumer-root clause, escapes SHADOW (which still compares only against `$PLUGIN_AGENTS`), and escapes ORPHAN (it is now in `$effective`). A repo-local file carrying a plugin-shipped reviewer name is accepted with no error and no notice — `docs/namespaces.md` rule 5's tripwire is gone for precisely the two names the panel gained. Bounded, because dispatch uses the qualified `design-toolkit:` agent type, so the bare consumer file is unlikely to be the one spawned; the loss is the drift signal, plus a dead file accepted in silence.

Fix: extend the SHADOW loop to test `$DESIGN_AGENTS` — better, membership in `$DESIGN_TOOLKIT_PANEL`, so it still holds when design-toolkit is absent — plus a selftest case. (`security-reviewer`, 82; before/after confirmed by execution here.)

### W3 — the relocated config read drops the resolved path

Stage 8 (`stages/8-code-review.md:65`) reads `"$SECOND_SHIFT_CONFIG"`. The relocated copy (`SKILL.md:64-65`) hardcodes a cwd-relative `.claude/second-shift.config.json`, dropping both the env override and the repo-root anchoring that this same file documents at `:50` for the `reviewers` read two paragraphs above. The spec declares "exactly one deliberate source change"; this is an undeclared second one.

Observed live during this review: run from the branch worktree, that path does not exist (the file is gitignored in this repo), so both keys read empty.

For a consumer with `design.provider: "figma"` reviewed from any cwd that is not the repo root, the key reads empty and the *key absent* row spawns `design-faithful-reviewer` — the wrong reviewer, with no Step 4c note, because absence is a legitimate supported state. Step 4c's "including the resolved globs" diagnostic then prints the default globs, actively mis-diagnosing a config that was never read. Mirror Stage 8: resolve the path once, then read from it.

### S1 — the a11y trigger narrows, outside any AC

`a11y-reviewer` went from "the repo's web UI file globs, e.g. `**/*.tsx` / `**/*.jsx`" (any depth) to `$WEB_COMPONENT_GLOBS`, default `apps/web/**/*.{tsx,jsx}`. Stage 8 already used that key and default, so this makes standalone `/review-lead` agree with Stage 8 and is a faithful relocation — but a consumer with FE at `src/**/*.tsx` and no `webComponentGlobs` key loses a11y routing it had under standalone `/review-lead`. No AC mentions the a11y row and the Surfaces table does not call it out. Worth one explicit line in the spec.

## Dismissed

`security-reviewer`'s three suppressed items (45/55/50) hold up as suppressions: the config values gate reviewer selection and are never interpolated into a command, and `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT` matches the override shape the script already uses for two other roots. `performance-reviewer` and `complexity-reviewer` returned clean, correctly — there is no hot path and no new abstraction here.

## Strengths

- `design-present` asserts exit 0 **and** the absence of the exemption notice. Exit 0 alone cannot tell sibling-root resolution from the degrade, and the case says so in a comment. `design-absent`'s `DANGLING:`-with-colon grep is the same care — a bare `DANGLING` would match the notice's own "exempt from DANGLING" wording and red spuriously.
- The exemption set is declared rather than derived, with the reason recorded in the header: when the root resolves empty there is nothing on disk to derive from, and that is exactly the case the exemption serves.
- Making the lint's three-root resolution part of *this* PR rather than a follow-up is the right call — growing the panel without it would have DANGLING-denied every onboarded consumer's commits.
- The declared "one deliberate source change" framing made W3 findable at all: the deviation is visible only because the intended fidelity was written down.

## Verdict

**needs-work** — 2 blockers (B1, B2), 3 warnings. Nothing here is architectural; every fix is local
and the routing design itself is sound. Scope Completeness PASS, AC-8 green both locally and in CI.
