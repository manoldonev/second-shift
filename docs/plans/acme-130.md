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

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Fix via three-dot rendering, NOT by computing `merge-base` inside the script | codebase-derived | The issue's first proposed bullet is unimplementable: Workflow scripts have no Bash/fs (`stages/8-code-review.md:62`; `code-review.mjs` imports nothing). The issue offered three-dot as an "equivalent" alternative — equivalent in effect, but the only one that is implementable. Taking the issue's own second option, not inventing a third |
| D-2 | Change the single shared `const range`, not the three prompt sites | codebase-derived | All three prompts (`:222`, `:228`, `:239`) interpolate the same `range` const. Editing prompt sites individually is how a partial fix reintroduces the bug asymmetrically — `codebase-explorer` flagged exactly this |
| D-3 | `plan-review.mjs` is recorded as confirmed-unaffected, not modified | codebase-derived | AC-5 names it, but it takes no `base`/`head` args and constructs no range at all — a full-file grep returns only an unrelated prose match at `:228`. Touching it would be churn |
| D-4 | Also fix `design-sync.mjs:293` and `unit-tests.mjs:190` | codebase-derived | Both carry the identical `` `${base}..${head}` `` construction AND render it into a reviewer prompt (`design-sync.mjs:300`, `unit-tests.mjs:196`). AC-5's catch-all ("any other diff-rendering workflow") covers them; leaving them is a literal-but-hollow AC-5 pass |
| D-5 | `stall-probe.mjs` / `tool-discipline-probe.mjs` left unchanged | codebase-derived | Their `base` defaults are `<sha>^` against `<sha>` (`stall-probe.mjs:30-31`, `tool-discipline-probe.mjs:52-53`). `merge-base(X^, X) == X^`, so three-dot and two-dot are identical there — unaffected by construction, and these are token-costing eval probes best left byte-stable for cross-run comparability |
| D-6 | `mutation-gate.mjs:83` updated even though it is only a `log()` line | codebase-derived | It reports the range it delegates to `unit-tests.mjs` (`:99`). Once the child renders three-dot, a `..` log line misreports what actually ran — a small honesty fix, zero behavioral risk |
| D-7 | AC-4's selftest is a NEW `*-selftest.sh`, not an added case in `null-reviewer-selftest.mjs` | codebase-derived | `.github/workflows/ci.yml:39-46` discovers selftests by `find . -name '*-selftest.sh'`. The `.mjs` selftest is invoked only by `pipeline-doctor.sh:251` (operator-run), so an AC-4 test added there would gate **nothing** in CI — no protection against the exact regression this issue exists to prevent. Precedent: `tools/intake-readroot-selftest.sh` |
| D-8 | The selftest proves semantics on a real git fixture, not just grep tokens | codebase-derived | AC-4 requires asserting "the constructed range excludes base-only commits" — a token grep cannot show that. A throwaway `git init` fixture with an ahead base can, and it also pins AC-2's equivalence claim. Grep-token drift guards are added *in addition*, per the `intake-readroot-selftest.sh` / Case-F pattern |
| D-9 | Also fix the two-dot `--stat` at `stages/8-code-review.md:85` | codebase-derived | It builds `changedFiles`, which rides in the *same reviewer prompt* as the range (`code-review.mjs:229`, `:239`). Fixing only the script leaves the prompt's `Changed files:` line listing base-only files — AC-1 says the prompt's diff must contain only the branch's own changes, so this is in scope by AC-1's letter, not scope creep |

## Affected files/modules

Module: `dev-pipeline / skills/run` (workflows + stages + tools).

- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — arg-contract comment (`:71`), `range` const (`:98`)
- `plugins/dev-pipeline/skills/run/workflows/design-sync.mjs` — arg-contract comment (`:169`), `range` const (`:293`)
- `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` — arg-contract comment (`:127`), `range` const (`:190`)
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
3. **`unit-tests.mjs`** — same two edits (`:190` const, `:127` contract line); relax the "git SHAs" wording to "git refs (branch/ref/SHA)" so its contract matches `code-review.mjs`'s.
4. **`mutation-gate.mjs`** — update the `:83` log range and the `:68` contract line for consistency with the child it dispatches.
5. **`stages/8-code-review.md`** — change the `--stat` range at `:85` to three-dot so `changedFiles` and the size class match the range the reviewers are given (D-9).
6. **`null-reviewer-selftest.mjs`** — add `` `${base}...${head}` `` to the Case-F token list so the drift guard fails if production reverts to two-dot.
7. **`tools/diff-range-selftest.sh` [NEW]** — behavioral fixture + drift guards (below).

## Test strategy

Verify-after (infra/behavior-preserving-at-the-contract-level change); the new selftest is the regression gate.

`tools/diff-range-selftest.sh` — CI-discovered by the `*-selftest.sh` glob, exit code = failure count:

- **Case A (AC-1, the bug):** build a throwaway `git init` fixture — a base commit, a branch commit touching `feature.txt`, then an *ahead* base commit touching `unrelated.txt`. Assert `git diff base...head --name-only` yields **only** `feature.txt`, and assert `git diff base..head --name-only` **does** include `unrelated.txt` (proving the fixture genuinely reproduces the bug — a fixture that cannot fail the old way proves nothing).
- **Case B (AC-2):** with `MB=$(git merge-base base head)`, assert `git diff $MB...head --name-only` equals `git diff $MB..head --name-only` — explicit-SHA callers are unaffected.
- **Case C–E (drift guards):** assert `code-review.mjs`, `design-sync.mjs`, `unit-tests.mjs` each carry `` `${base}...${head}` `` and no longer carry the two-dot form.
- **Case F (AC-5 registration):** assert `plan-review.mjs` still constructs no range, so its confirmed-unaffected status is mechanically re-checked rather than trusted to this plan's prose.
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
```

## Risks / rollback notes

- **Unrelated-histories edge case.** `A...B` errors when `A` and `B` share no common ancestor, where `A..B` would have produced output. Not reachable in the pipeline (every review branch is cut from its base), and a hard error is preferable to a silently wrong diff. Accepted, not mitigated.
- **Returned/logged `range` string shape changes** (`a..b` → `a...b`). Surfaced in `code-review.mjs:163` logs and the `{ range, ... }` return. Assumption 4 records that no consumer parses it; if one is later added, it reads the corrected semantics.
- **Rollback:** revert the commit — every edit is a one-operator change plus an additive selftest; no state-shape, config, or schema change, so there is nothing to migrate back.

## Out-of-scope

- Reviewer prompt content beyond the diff-range expression (issue's own boundary).
- The Stage 9 stale-branch abort (already merge-base-correct).
- `stall-probe.mjs` / `tool-discipline-probe.mjs` (D-5 — unaffected by construction).
- `plan-review.mjs` (D-3 — constructs no range).
- Tracing which specific #119 caller supplied a raw branch literal. The rung-2 fix makes the range correct regardless of caller, so caller archaeology is not needed to close this issue.
