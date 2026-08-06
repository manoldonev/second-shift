# lean review verdict — #413

verdict=needs-work
run_id: review-413-1
session_id: 416253a4-4a2c-4162-b5c0-e8e97382225a
rounds: 1
pr: #415
reviewed_head: a30d4cd355978320eaa85215b772d686005e9a94
reviewed_patch_id: cacb3b4ec531a1f62a5ebcd6b20ee92195157af8
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

# Review round 1 — PR #415 (#413), verdict: needs-work

Range read: `c3f8300..HEAD` (full branch — chain ROOT, nothing to inherit). Design: `not-applicable`
(`design` is `null` in this repo's runtime config, so the spec's `Design: none` disarm is justified;
step 5b skipped).

The change is well built and the mechanism is right: one shared resolver, refusal instead of a
placeholder, and a discriminator moved from a CI constant onto a committed artifact. Every
applicability path the spec enumerates was driven through the real gates from this checkout and
behaved as specified. One blocker stands: a shape the spec does not enumerate makes **both** chain
gates decline the same PR, and a lean PR in that shape reaches the merge boundary with its entire
evidence set unchecked.

## Blocker

### B-1. A lean PR whose body's first issue reference differs from its branch key is claimed by neither chain gate

`check-lean-chain.sh` keys applicability on the issue resolved from the **PR body** (`Closes #N`,
else `Part of #N`, first match — `:358-361`). `check-pipeline-chain.sh` keys its lean exclusion on
the issue resolved from the **branch name** (`KEY_BRANCH`, `:116` → `:154`). When the two disagree,
each gate hands the PR to the other and neither runs.

Reproduced against both scripts as committed, from this checkout, with this PR's own file list:

```
$ PR_HEAD_REF=claude/second-shift-413 PR_BODY="Part of #400" ... bash scripts/check-pipeline-chain.sh --diff-files-file <415 files>
rc=0
[pipeline-chain] lean-authored PR — pipeline chain check not applicable.
[pipeline-chain]   the diff commits this key's lean spec (docs/plans/second-shift-413-lean.md); scripts/check-lean-chain.sh owns it.

$ PR_HEAD_REF=claude/second-shift-413 PR_BODY="Part of #400" ... bash scripts/check-lean-chain.sh --diff-files-file <415 files>
rc=0
[lean-chain] non-lean change — lean chain check not applicable.
[lean-chain]   note: the diff carries lean spec(s) — docs/plans/second-shift-413-lean.md — but none for
                this PR's own issue (#400) ... Classified to the pipeline chain gate, not this one.
```

Both exit 0. No verdict record, no `lean-claimed` comment, no freshness check, no stage trail.

**Reachable from the lane, not only by hand.** `lean-gate.sh` milestone 5 asserts only that
`Closes #$ISSUE` appears **at least once** (`:2133-2136`, `-ge 1`); it does not require it to be the
first or the only one. A lean PR closing two issues whose body lists the other key first
(`Closes #421` before `Closes #420` on branch `…-420`) passes milestone 5 and then deactivates both
gates. A prose `closes #N` earlier in a long body does the same — these bodies are long and
prose-heavy.

**Introduced by this diff.** Before it, `check-lean-chain.sh` applied on *branch-prefix match OR
artifact*, so the prefix arm claimed the PR regardless of how the body resolved, and the evidence
pass then red on the mismatch. Collapsing to the artifact arm alone (issue proposal 3) removed that
cover; the mirror exclusion added to the sibling gate closed the other side too. The failure is also
self-justifying in the logs: each gate prints that the other owns the PR, so a reader of a green
`pr-gates` sees two confident hand-offs and no gap.

No `AC-n` is violated — AC-11 asserts *no PR is applicable to both*, and that direction holds and was
verified. It is the unasserted complement (*every lean PR is applicable to at least one*) that the
diff breaks, at a boundary whose own header calls a vacuous green "the worst outcome available here."

**Minimal remedies (either side, one condition):**
- `check-lean-chain.sh` — when the diff carries non-fixture lean spec(s) but none matches the body
  key, do not fall through to not-applicable if one of them matches the **branch** key; claim the PR
  (or `fail`, as the no-issue-reference arm at `:365` already does).
- or `check-pipeline-chain.sh` — require the body-resolved key to agree with `KEY_BRANCH` before
  exempting.

Either way this needs a selftest case in both suites: the current sets never drive a
branch-key ≠ body-key PR through either gate, which is why the shape survived.

## Warnings

- **W-1. `retro-corpus.sh open-prs` inherits the same blind spot.** Its candidate filter
  (`lean_spec_in_files`, `:180-186`) keys the spec suffix on the issue extracted from the **branch**
  (`:214-216`), while the two gates disagree about which key is authoritative. The consequence here
  is only a wrong operator report, not a bypass — but whatever key rule B-1 settles on should reach
  all three sites, which is exactly what D-12 decided for the previous rule.

- **W-2. Bare `branch-prefix.sh` resolves its config from a different root than both live callers.**
  With no `--config`, it reads `$(git rev-parse --show-toplevel)/.claude/second-shift.config.json`
  (`:62-64`). Both callers pass `--config` resolved from `--git-common-dir`'s **main** root
  (`lean-gate.sh:195-198`, `retro-corpus.sh:78-81`), because the runtime config is gitignored and
  therefore absent from every worktree. Run from the 413 worktree, the bare form silently takes the
  detection path and answers `lean/` — one stray `origin/lean/398` is the only key-shaped vote among
  this repo's remotes, so detection confidently reproduces the namespace this PR deletes:

  ```
  $ bash plugins/dev-pipeline/skills/run-lean/branch-prefix.sh     # from the 413 worktree
  lean/
  $ bash plugins/dev-pipeline/skills/run-lean/branch-prefix.sh --config <main root>/.claude/second-shift.config.json
  claude/second-shift-
  ```

  Neither production path is affected. But the debugging path is, and it answers wrong rather than
  refusing. Anchoring the no-`--config` default on `--git-common-dir` would make the standalone form
  agree with its callers.

- **W-3. Detection declares a winner at one vote.** `N_AT_TOP -gt 1` is the only refusal
  (`:142`); a single key-shaped branch is "dominant" and resolves outright. AC-3 says *dominant*, so
  this satisfies the letter, and W-2's `lean/` is what it looks like in practice. A minimum-vote
  floor, or a required margin over the runner-up, would make the refusal match the intent — and the
  refusal is the whole safety property here (D-4).

- **W-4. Two shipped claims are now stronger than the code.** `check-lean-chain.sh:88-93`
  ("NON-VACUOUS BY CONSTRUCTION … has no counterpart here") and
  `docs/pipeline-manifesto.md:165-168` ("making the artifact the **only** trigger removes the
  constant, and with it the whole residual"). B-1 is a residual of a different shape in the same
  place. Whatever the fix, both paragraphs need to describe what actually holds.

## Suggestions

- `tools/mutation-baseline.tsv:181` — "Every remaining site shifted down one" is true for the two
  ordinals the rows name, but two sites vanished, not one: the header prose line **and** the
  `[[ "$APPLICABLE" -eq 0 ]]` code site at the old `:331`. Sites past that shift by two. No
  operational consequence at `K=2`; the rows themselves check out (verified below).
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md:70-72` — the legacy fallback composes a
  `lean/`-prefixed head ref from an old `branch_prefix:` record, which is a useful compatibility
  path but reads against ledger D-6 ("already-merged `lean/`-prefixed runs drop out of the corpus").
  Different tools, no contradiction in force; worth a word if D-6 is ever cited as settled.
- `gh pr list --json files` is subject to GraphQL file-list truncation on very large PRs, which
  could hide a lean spec from `open-prs`. Advisory surface only, not a gate.

## Scope: the staged lane, and the override

`review-toolkit:scope-completeness-reviewer` returned two blockers, both correct against the
**issue's** literal wording: AC-3 says "both lanes resolve that identifier" and AC-5 says "one
detection implementation, called by both lanes", and `stages/2-worktree.md:27` still spells
`jq -r '.tracker.branchPrefix // "claude/acme-"'`.

**Overridden, deliberately and on the record.** `.claude/pipeline-state/413-ledger.md` D-1 is
`user-answered` and predates implementation: *"run-lean (`lean-gate.sh`) and `retro-corpus.sh` only.
The deprecated staged lane's prose in `stages/2-worktree.md` is left untouched … AC-5 narrows to 'one
implementation among live consumers'."* The pre-flight ledger is binding input that can narrow the
issue's ACs, the spec carries the narrowing verbatim, and the staged lane is deprecated. Both
findings are downgraded to a **note**: the issue body still reads unnarrowed, so file a follow-up (or
amend #413) rather than leaving the shipped scope and the tracked scope divergent. Not a blocker, and
not scored against the ACs.

## Per-AC scoring (spec: `docs/plans/second-shift-413-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean_branch_prefix()` absent from both scripts (grep: only doc/spec prose remains). `lean-gate-selftest.sh` (e1)(e2)(e3); scenario `(lean-branch-name)`. |
| AC-2 | satisfied | `(n0b)` and scenario `(lean-branch-name)`: key `ACME-7` → branch `abc/acme-7`, spec path `docs/plans/acme-ACME-7-lean.md` verbatim. |
| AC-3 | satisfied (as narrowed by ledger D-1) | Detection resolves the dominant identifier; `claude/acme-` reaches no output path — `branch-prefix-selftest` (b2), `lean-gate-selftest` (e4), scenario `(lean-branch-refusal)`. Staged lane out of scope per D-1; see the scope section. |
| AC-4 | satisfied | Driven directly: zero candidates → rc=2 naming what it scanned; two-way tie → rc=2 naming both and the full tally; three-vs-one → `jdoe/`. |
| AC-5 | satisfied (as narrowed by ledger D-1) | One implementation; the only two callers are `lean-gate.sh:275` and `retro-corpus.sh:194`. |
| AC-6 | satisfied | Driven from this checkout with `LEAN_BRANCH_PREFIX` unset and no `PIPELINE_BRANCH_PREFIX`: `applicable via lean-artifact (docs/plans/second-shift-413-lean.md): branch=claude/second-shift-413`. Constant absent from script logic and from `ci.yml`. |
| AC-7 | satisfied | Same inputs: `[pipeline-chain] lean-authored PR — not applicable`. A staged PR with no lean spec still reds on the missing plan (probe below). |
| AC-8 | satisfied | `lean-spec-suffix` row present; `scripts/check-lockstep-pairs.sh` → 18 pairs, 0 failed. |
| AC-9 | satisfied | Driven with `PR_HEAD_REF=lean/second-shift-413`: still `applicable via lean-artifact`. |
| AC-10 | satisfied | Driven: branch key 500 + only `second-shift-392-lean.md` in the diff → `applicable: key=500`, reds on the missing plan. `(l2)`. |
| AC-11 | satisfied | Key-matched applicability on both sides; `open-prs` (AC-5b) rejects the other-key and fixture-only PRs; a lean spec with no resolvable issue reference **fails** (driven: `✗ PR body carries no resolvable issue reference`). See B-1 for the complement this AC does not assert. |
| AC-12 | satisfied | Driven: prefix-matched, no lean spec → pipeline gate applicable and red. `(l4)`. |
| AC-13 | satisfied | `run-lean/SKILL.md` step 3 reads `<branchPrefix><key>`, file is 42 lines (cap 60); `pipeline-retro` recipe reads `branch:` from the record; manifesto section rewritten to two constants. |
| AC-14 | satisfied | New 246-line `branch-prefix-selftest.sh` covers configured passthrough, detection, zero-candidate and tie refusals, and the jira key-pattern arm (plus absent-`keyPattern` fallback, github-vs-jira key shapes, symbolic-ref exclusion). Two new `scenario-liveness` legs. Chain-gate prefix cases replaced, not deleted (`check-lean-chain-selftest.sh:315,331`). |
| AC-15 | satisfied | Re-run independently from this checkout, **without** `SKIP_STRESS` and under `env -u CLAUDE_CODE_SESSION_ID`: `shellcheck` rc=0, `jq empty` rc=0, full `*-selftest.sh` sweep rc=0 (274/0, 75/0, 43/0, 35/0, 32/0, 7/0). Baseline re-keying verified by enumerating the `-eq|-ne` sites at base and head — the dropped `self-neutralization` prose line makes head ordinal 1 = `zero-network` (old ordinal 2) and ordinal 2 = `Armed-ness` (old ordinal 3); both prose, accepted-survivor set unchanged, no kill lost. `branch-prefix.sh` has exactly one `cmp-eq` site and it is the Seams comment, as the new row states. |
| AC-16 | **undeterminable** (not unsatisfied — see below) | `tools/mutation-slow-suites.tsv` gains both rows with honest provenance, and `branch-prefix.sh` stays on the PR lane. But the AC's claim is about the sweep completing inside the step bound, and CI has not yet produced that evidence. |

### AC-16 and the current CI red

`lint-and-selftests` and `pr-gates` both read `fail` at 15m02s, which looks exactly like the
`timeout-minutes: 15` cancellation the AC was written to fix. It is not. Both jobs report
`conclusion: cancelled` with **zero steps**, and the check annotation reads:

> The job was not acquired by Runner of type hosted even after multiple attempts

No hosted ubuntu runner was ever assigned; the 15m02s is the runner-acquisition wait, not the
mutation step. Neither job reached checkout, so nothing in this diff was executed by them.
`selftests (macos, bash 3.2)` — a different runner pool — passed in 11m26s.

So AC-16 is scored `undeterminable` rather than unsatisfied: the run that would settle it never
started. Pushing this verdict record retriggers CI, which re-runs both jobs for free; read
`lint-and-selftests` on that run before treating AC-16 as either met or missed. It does not affect
the verdict either way — B-1 is what stands.

## Reviewer panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope completeness | Fail (overridden — see scope section) | 2 | 92–95 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test coverage | **Dark (no output)** | — | — |

`review-toolkit:test-coverage-reviewer` died after its automatic retry (turn-budget, no text on
either attempt). Its domain was covered in-session instead — the AC-14 row above, the selftest
enumeration, and the independent sweep — and that coverage is what surfaced B-1's missing case.
`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`) on a shell-and-docs diff.

## Strengths

- The mechanism is the right one. Replacing a CI constant with a committed artifact as the
  applicability input is strictly stronger, and the diff carries the argument in the manifesto rather
  than leaving it implied.
- The `--diff-files-file` hoist is a real find, correctly generalized: validating inside a function
  consumed through a process substitution meant `envfail`'s exit killed only the subshell, and once
  that list *became* applicability a mistyped seam path would have read as a clean green. Fixed in
  both gates with a case each.
- The refusal paths are the tested ones. `(lean-branch-refusal)` asserts a terminal **non-write** —
  rc=2, no progress record, no placeholder — which is the only shape that distinguishes "refused"
  from "refused after recording a claim".
- AC-16 is handled as a data correction with the coverage cost stated out loud rather than a raised
  timeout, and the mutation-baseline notes explain *which line* each re-keyed ordinal now names.
