# Plan — #130: `code-review.mjs` must resolve the merge-base

## Context

`workflows/code-review.mjs` builds one shared range string, `` const range = `${base}..${head}` `` (`code-review.mjs:98`), and interpolates it into **three** reviewer-prompt sites: the scope-completeness prompt (`:222`), the mutation-review prompt (`:228`), and the generic domain-reviewer prompt (`:239`). When a caller passes a *branch name* whose tip has advanced past the review branch's merge-base, a two-dot range renders the base branch's newer commits as **deletions in the branch under review**.

Observed in run #119 (PR #125): `scope-completeness-reviewer` returned two confidently-argued BLOCKER findings, both false, and criterion 5 (Review Precision) went to FAIL.

The issue frames this as ladder rung 2 — the script should own the computation rather than trusting caller discipline. That framing is right, and it is what makes the fix caller-independent.

## Assumptions

1. **Workflow scripts cannot execute git.** They run in a sandboxed async JS context with no filesystem or child-process access — `stages/8-code-review.md:62` states it outright, and `code-review.mjs` has no imports, using only runtime-injected globals (`agent`, `parallel`, `args`, `log`, `phase`, `budget`). Verified independently against the Workflow tool contract.
2. **Three-dot is merge-base semantics by definition.** `git diff A...B` diffs from `merge-base(A,B)` to `B`. This is what makes the fix possible *inside* the script despite (1).
3. **Three-dot is a no-op when `base` is already an ancestor of `head`.** If `base` is an explicit merge-base SHA, `merge-base(base, head) == base`, so `base...head` is byte-identical to `base..head`. This is what makes AC-2 hold by construction rather than by testing luck.
4. Reviewers consume the range only as a shell command inside a prompt; no consumer parses the returned `range` string. (Checked: `code-review.mjs:181`, `:323` return it; `8-code-review.md:110` documents the shape; no caller destructures or parses it.)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | How does the script resolve the merge-base given it cannot run git? | Render three-dot `${base}...${head}`; do NOT attempt an internal `merge-base` call | codebase-derived |
| D-2 | Edit the shared `range` const, or the individual prompt sites? | Change the single shared `const range` only | codebase-derived |
| D-3 | Is `plan-review.mjs` (named by AC-5) fixed or confirmed unaffected? | Confirmed unaffected; recorded, not modified | codebase-derived |
| D-4 | Are the other range-rendering workflows in scope for AC-5? | Yes — fix `design-sync.mjs` and `unit-tests.mjs` | codebase-derived |
| D-5 | Are `stall-probe.mjs` / `tool-discipline-probe.mjs` in scope? | No — left byte-stable, unaffected by construction | codebase-derived |
| D-6 | Is the `mutation-gate.mjs:83` log-only range worth changing? | Yes — updated for consistency with the child it dispatches | codebase-derived |
| D-7 | Where does AC-4's selftest live so it actually gates? | A NEW `tools/diff-range-selftest.sh`, not a case in `null-reviewer-selftest.mjs` | codebase-derived |
| D-8 | Can a grep-token test satisfy AC-4? | No — add a real throwaway-git-fixture behavioral test, with token guards on top | codebase-derived |
| D-9 | Is the two-dot `--stat` at `stages/8-code-review.md:85` in scope? | Yes — in scope by AC-1's letter | codebase-derived |
| D-10 | What about the remaining stage-level two-dot ranges? | Confirmed safe and recorded in the AC-5 audit; not modified | codebase-derived |
| D-11 | `$BASE`/`$HEAD` are undefined in the Stage-8 single-repo lane — define or leave? | Define them explicitly via merge-base in that lane | codebase-derived |
| D-12 | How do the drift-guard greps match the range tokens? | Pin fixed-string mode (`grep -F`) at every guard site | codebase-derived |

**Rationale.**

**D-1.** The issue's first proposed bullet is unimplementable: Workflow scripts have no Bash or filesystem access (`stages/8-code-review.md:62`; `code-review.mjs` imports nothing and uses only injected globals). The issue offered three-dot as an "equivalent" alternative — equivalent in effect, but the only one that is implementable. This takes the issue's own second option rather than inventing a third.

**D-2.** All three reviewer prompts (`:222`, `:228`, `:239`) interpolate the same `range` const. Editing prompt sites individually is precisely how a partial fix reintroduces the bug asymmetrically.

**D-3.** AC-5 names `plan-review.mjs`, but it takes no `base`/`head` args and constructs no range at all — a full-file grep returns only an unrelated prose match at `:228`. Modifying it would be churn; the audit records it instead.

**D-4.** `design-sync.mjs:293` and `unit-tests.mjs:190` carry the identical construction *and* render it into a reviewer prompt (`design-sync.mjs:300`, `unit-tests.mjs:196`). AC-5's catch-all covers them; leaving them would be a literal-but-hollow AC-5 pass.

**D-5.** Their `base` defaults are `<sha>^` against `<sha>` (`stall-probe.mjs:30-31`, `tool-discipline-probe.mjs:52-53`). Since `merge-base(X^, X) == X^`, three-dot and two-dot are identical there. They are also token-costing eval probes best left byte-stable for cross-run comparability. They are therefore **excluded from the drift guard's no-two-dot assertion**.

**D-6.** `mutation-gate.mjs:83` reports the range it delegates to `unit-tests.mjs` (`:99`). Once the child renders three-dot, a `..` log line misreports what actually ran — an honesty fix with zero behavioral risk.

**D-7.** `.github/workflows/ci.yml:39-46` discovers selftests by `find . -name '*-selftest.sh'`. `null-reviewer-selftest.mjs` is invoked only by the operator-run `pipeline-doctor.sh:251`, so an AC-4 test added there would gate **nothing** in CI — no protection against the exact regression this issue exists to prevent. Precedent: `tools/intake-readroot-selftest.sh`.

**D-8.** AC-4 requires asserting "the constructed range excludes base-only commits" — a token grep cannot demonstrate that. A throwaway `git init` fixture with an ahead base can, and it also pins AC-2's equivalence claim.

**D-9.** `stages/8-code-review.md:85` builds `changedFiles`, which rides in the *same reviewer prompt* as the range (`code-review.mjs:229`, `:239`). Fixing only the script would leave the prompt's `Changed files:` line listing base-only files — AC-1 requires the prompt's diff to contain only the branch's own changes, so this is in scope by AC-1's letter, not scope creep.

**D-11.** `stages/8-code-review.md` uses `$BASE` and `$HEAD` at `:85` and `:107` but never assigns them anywhere in its single-repo lane — they are inherited in-session from `5-implement.md:53`. That silent inheritance is a plausible mechanism for run #119's stale ref: a resume or a long session can carry a `$BASE` that no longer reflects the branch point. Since step 5 edits `:85` anyway, defining the pair explicitly (mirroring the be-fe-pair lane's correct `R_MB` derivation at `:245`) closes the gap at its source rather than leaving the corrected range dependent on an undeclared variable.

**D-12.** Adopted as hardening on plan review's recommendation. Note honestly: the specific inversion the reviewer described does not reproduce — with these tokens neither `grep` mode actually cross-matches the two-dot and three-dot forms (checked both directions). But `-F` removes the class of question entirely at zero cost, and these tokens are punctuation-dense (`$`, `{`, `}`, `.`), so fixed-string is the right default regardless of whether today's exact strings happen to be safe.

**D-10.** Three stage-level two-dot ranges survive: `stages/5-implement.md:82`, `stages/7-doc-update.md:40`, and `stages/8-code-review.md:253`. All three are safe because their left operand is *already* a merge-base SHA (`5-implement.md:53` computes `BASE` via `git merge-base`; `7-doc-update.md` and `8-code-review.md:245` use `R_MB`), so three-dot would be a no-op. They are recorded here rather than changed, so AC-5's audit is complete rather than silently partial.

## Affected files/modules

Module: `dev-pipeline / skills/run` (workflows + stages + tools).

- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — arg-contract comment (`:71`), `range` const (`:98`)
- `plugins/dev-pipeline/skills/run/workflows/design-sync.mjs` — arg-contract comment (`:169`), `range` const (`:293`)
- `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` — arg-contract comment (`:127`), `log()` range (`:153`), `range` const (`:190`)
- `plugins/dev-pipeline/skills/run/workflows/mutation-gate.mjs` — arg-contract comment (`:68`), `log()` range (`:83`)
- `plugins/dev-pipeline/skills/run/workflows/null-reviewer-selftest.mjs` — Case-F drift-guard token list (`:222`)
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` — `--stat` range (`:85`)
- `plugins/dev-pipeline/skills/run/tools/diff-range-selftest.sh` **[NEW]**

Unverified references: none — every path and line above was read in the pinned checkout.

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/intake-readroot-selftest.sh` — the shape the new selftest follows (`ok`/`bad` helpers, `FAILS` counter, exit code = failure count, grep-token assertions against a Workflow `.mjs`). Reused as the structural template.
- `plugins/dev-pipeline/skills/run/workflows/null-reviewer-selftest.mjs:211-234` — the Case-F drift-guard token-list pattern; extended with one new token rather than reinvented.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh:1932-1958` — precedent for a `.sh` selftest reaching into a `.mjs` and degrading to SKIP when `node` is unavailable; reused as the guard idiom.
- No new helpers introduced — the change is a range-operator edit plus one selftest built from the existing selftest conventions.

## Implementation steps

1. **`code-review.mjs`** — change `` const range = `${base}..${head}` `` → `` `${base}...${head}` ``; update the `:71` arg-contract comment to state `base` accepts a branch/ref and the three-dot render applies merge-base semantics, so base-only commits never appear (AC-3).
2. **`design-sync.mjs`** — same two edits (`:293` const, `:169` contract line).
3. **`unit-tests.mjs`** — three edits: the `:190` range const, the **`:153` `log()` range** (a second two-dot site in the same file), and the `:127` contract line; relax the "git SHAs" wording to "git refs (branch/ref/SHA)" so its contract matches `code-review.mjs`'s. Both range sites must change together — the file must contain zero two-dot forms or the Case D/E guard below goes red.
4. **`mutation-gate.mjs`** — update the `:83` log range and the `:68` contract line for consistency with the child it dispatches.
5. **`stages/8-code-review.md`** — change the `--stat` range at `:85` to three-dot so `changedFiles` and the size class match the range the reviewers are given (D-9). **Also define `$BASE`/`$HEAD` in this lane** (D-11): they are used at `:85` and `:107` but never assigned anywhere in the single-repo lane — they are silently inherited in-session from `5-implement.md:53`. Add an explicit merge-base derivation mirroring the be-fe-pair lane's already-correct `R_MB` pattern (`:245`).
6. **`null-reviewer-selftest.mjs`** — add `` `${base}...${head}` `` to the Case-F token list so the drift guard fails if production reverts to two-dot.
7. **`tools/diff-range-selftest.sh` [NEW]** — behavioral fixture + drift guards (below).

## Test strategy

Verify-after (infra/behavior-preserving-at-the-contract-level change); the new selftest is the regression gate.

`tools/diff-range-selftest.sh` — CI-discovered by the `*-selftest.sh` glob, exit code = failure count:

- **Case A (AC-1, the bug):** build a throwaway `git init` fixture — a base commit, a branch commit touching `feature.txt`, then an *ahead* base commit touching `unrelated.txt`. Assert `git diff base...head --name-only` yields **only** `feature.txt`, and assert `git diff base..head --name-only` **does** include `unrelated.txt` (proving the fixture genuinely reproduces the bug — a fixture that cannot fail the old way proves nothing).
- **Case B (AC-2):** with `MB=$(git merge-base base head)`, assert `git diff $MB...head --name-only` equals `git diff $MB..head --name-only` — explicit-SHA callers are unaffected.
- **Case C–E (drift guards):** assert `code-review.mjs`, `design-sync.mjs`, `unit-tests.mjs` and `mutation-gate.mjs` each carry the three-dot form and contain **zero** occurrences of `` `${base}..${head}` ``. All guard greps use **`grep -F`** (D-12). The guard is **scoped to exactly these four files** — the two eval probes (D-5) intentionally retain two-dot, so a repo-wide assertion would be wrong. Note `unit-tests.mjs` has *two* sites (`:153`, `:190`); the zero-occurrence form catches a partial fix that a "carries three-dot" check alone would pass.
- **Case G (AC-5 registration):** assert `plan-review.mjs` still constructs no range, so its confirmed-unaffected status is mechanically re-checked rather than trusted to this plan's prose. (Named `G`, not `F`, to avoid colliding with the existing Case F drift-guard in `null-reviewer-selftest.mjs`, which step 6 also edits.)
- Fixture is created under `mktemp -d` and removed on exit; degrades to SKIP if `git` is unavailable.

Unit-test surface: **skip** — this repo configures `commands.second-shift.unitTestScope: null`, so there is no mutation surface.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Ahead base → prompt diff has only branch's own changes | 1, 2, 3, 5 | Case A (both directions), Case C–E |
| AC-2 | Explicit merge-base SHA behaves identically | 1 (three-dot is a no-op on an ancestor base) | Case B |
| AC-3 | `base` semantics documented at the arg contract | 1, 2, 3, 4 | Case C–E (token presence) |
| AC-4 | Selftest covers ahead-base, asserts range excludes base-only commits | 7 | Case A — and it runs in CI (D-7) |
| AC-5 | Sibling diff-rendering workflows audited; fixed or confirmed unaffected | 2, 3, 4 (fixed); D-3/D-5 (confirmed unaffected) | Case C–F |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# repo CI gates that specifically police a plugins/** PR:
bash scripts/check-frozen-files.sh
bash scripts/check-changelog-trailer.sh
```

**Release-artifact discipline.** This PR must NOT touch `plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`, or `.claude-plugin/marketplace.json` `metadata.version` — those are derived on the release PR and a feature PR touching them is rejected by `scripts/check-frozen-files.sh`. Changelog intent rides a commit trailer instead:

```
Changelog: reviewer prompts now describe a three-dot diff range, so a review branch
  is never reported as deleting commits that only exist on its base branch.
  Migration: none.
```

## Risks / rollback notes

- **Unrelated-histories edge case.** `A...B` errors when `A` and `B` share no common ancestor, where `A..B` would have produced output. Not reachable in the pipeline (every review branch is cut from its base), and a hard error is preferable to a silently wrong diff. Accepted, not mitigated.
- **Returned/logged `range` string shape changes** (`a..b` → `a...b`). Surfaced in `code-review.mjs:163` logs and the `{ range, ... }` return. Assumption 4 records that no consumer parses it; if one is later added, it reads the corrected semantics.
- **Rollback:** revert the commit — every edit is a one-operator change plus an additive selftest; no state-shape, config, or schema change, so there is nothing to migrate back.

## Out-of-scope

- Reviewer prompt content beyond the diff-range expression (issue's own boundary). This specifically covers the scope-completeness prompt's `` Branch head `${head}` vs base `${base}` `` line (`code-review.mjs:222`), which hands reviewers the raw refs alongside the corrected range. Plan review flagged it as a residual risk — a reviewer could reconstruct a two-dot diff from those refs instead of running the command given. It is a genuine (if smaller) instance of the same failure mode, but rewording it is prompt-content work the issue explicitly fenced off. Recorded here as a known residual rather than silently absorbed; worth a follow-up issue.
- The three stage-level two-dot ranges at `stages/5-implement.md:82`, `stages/7-doc-update.md:40`, `stages/8-code-review.md:253` — audited and confirmed safe (D-10), left unchanged.
- The Stage 9 stale-branch abort (already merge-base-correct).
- `stall-probe.mjs` / `tool-discipline-probe.mjs` (D-5 — unaffected by construction).
- `plan-review.mjs` (D-3 — constructs no range).
- Tracing which specific #119 caller supplied a raw branch literal. The rung-2 fix makes the range correct regardless of caller, so caller archaeology is not needed to close this issue.
