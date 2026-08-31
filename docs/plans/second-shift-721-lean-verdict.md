# lean review verdict — #721

verdict=approve
run_id: review-721-1
session_id: 5bbd63e7-cb7c-4d2c-8f3d-dad313233afd
rounds: 1
pr: #749
reviewed_head: 981bedfd48ae85321243f54d8e5418b03f5e6464
reviewed_patch_id: c9613b79b4fd5de70106181f4bebf58fb14a30f8
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 covered the whole branch diff (`d901b05b..981bedfd`, 5 files, +192/-5) — `bash G delta 721` printed the FULL range, nothing verifiable to inherit.

## Verdict

`approve`. No blockers. All seven ACs are satisfied; the two majors below are prose and test-strength, neither of which leaves an AC unmet.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — accepted in every mode, opt-in, inert when omitted; `ci.yml` / `mutation-merge.yml` unaffected | satisfied | The `--verdict-log` arg-parse case (`mutation-sweep.sh:285`) sits in the mode-independent parse loop, and `VERDICT_LOG=""` makes both write sites no-ops. No new code touches `REPORT_SINK`, so the report is unaffected by construction. `ci.yml:232` and `mutation-merge.yml:96` both run `--mode pr` with no such flag. Selftest `(at1)` asserts identical rc with and without. |
| AC-2 — header + one TAB row per scored mutant, both tiers, `-` for a survivor | satisfied | Header is byte-exact `mutant_id\tverdict\tkiller_suite` (`:857`). Catalog mutants are appended to the same `mut.todo` / `MUT_SID` / `GL_FIRST..GL_COUNT` indexing as generic ones (`:1936-1940`), so the PHASE 5 loop is tier-agnostic. Selftest `(at2)` asserts a generic `killed` row naming `./guard-selftest.sh` **and** a `catalog::echo-flip survived -` row. Probe P4 (killer column hardwired to `-`) is KILLED by `(at2)`+`(at3)` — the column assertion is live, not decorative. |
| AC-3 — unwritable path is a hard red | satisfied | `printf … > "$VERDICT_LOG" \|\| die "cannot write the verdict log: …"` (`:857-858`), matching the report sink's guard two lines above. Selftest `(at4)` reds by name on `/no/such/dir/`. See major 2 for what actually kills that assertion. |
| AC-4 — a cache-served verdict logs its real killer, re-verify correction included | satisfied | A cache hit writes the full record straight to `verdict.$j` (`:1930` region), and PHASE 5 reads `vsuite` out of it. The row `printf` is placed **after** the pool-disagreement block and after its `IFS read` re-fetch (`:2149-2153`), so a corrected `killed` logs the corrected verdict and suite. Selftest `(at3)` covers the cache half (`computed=0`, warm row names the real killer). The re-verify half is unguarded — major 2. |
| AC-5 — `mutation-sweep.yml` passes the flag at both shard invocations, inside the published `sweep-out/` | satisfied | Seed branch `mutation-sweep.yml:148`, non-seed `:152`. The shard artifact is `name: mutation-sweep-shard-${{ matrix.shard }}`, `path: sweep-out/` (`:188-189`) — no new upload step needed. Checked the merge job for collateral: `--mode merge` globs only `*/mutation-report.tsv`, `*/mutation-baseline.tsv`, `*/mutation-slow-suites.tsv` (`mutation-sweep.sh:953,987,1029`), so the extra file in each shard dir is inert there. |
| AC-6 — covered by `tools/mutation-sweep-selftest.sh`, contract in `docs/testing.md` | satisfied | New `(at)` case, 4 assertions. Run COLD locally at this head (`SKIP_STRESS=1`, no `--cache-dir`): `[mutation-sweep-selftest] all cases passed`. CI at `981bedfd`: `lint-and-selftests` pass (4m47s, all 16 steps green incl. shellcheck 0.9.0 and actionlint) and `selftests (macos, bash 3.2)` pass (8m8s). The doc paragraph covers shape, both tiers, the cache-hit guarantee and the hard-red path — the four AC-6 enumerates. |
| AC-7 — `feat(dev-pipeline):` verb, `Changelog:` trailer, no frozen-file edits | satisfied | `981bedfd` subject is `feat(dev-pipeline): mutation-sweep gains an opt-in --verdict-log`, body carries `Changelog: … Migration: none.` `pr-gates` steps 3 and 4 (frozen files, changelog trailer) both green. Diff touches no `plugin.json`, `CHANGELOG.md` or `marketplace.json`. |

Design fidelity: **not-applicable**. The spec's `## Design` reads `Design: none — this is a shell-flag and CI-wiring change with no web surface`, and the repo config declares no `design.provider` (`jq '.design' → null`), so the disarm is justified rather than an under-declared table.

## Findings

### Major — no blockers

- **[Maintainability] `docs/testing.md:1448`** — the new paragraph's bold lead, `**What the monthly lane is FOR: per-operator kill rate, on demand.**`, contradicts the paragraph immediately above it, which already answers that question differently ("The monthly lane no longer grades anybody's change… What is left for it is the classes no diff-scoped run can see"). The route the new paragraph then describes is a `workflow_dispatch` (D-4), not the monthly `cron: '17 3 1 * *'` schedule. Both paragraphs are individually true; read in sequence the second asserts an exclusivity that displaces the first. Suggested: "**A second thing the full-universe lane can now answer: per-operator kill rate, on demand.**"
- **[Test coverage] `tools/mutation-sweep-selftest.sh:2581`** — mutant-probed the new `(at)` case in an isolated worktree, four mutants, 2 killed / 2 survived:
  - KILLED — dropping the row `printf` entirely → `(at2)` + `(at3)` fail.
  - KILLED — hardwiring the killer column to `-` → `(at2)` + `(at3)` fail.
  - **SURVIVED** — logging the *pre-correction* `verdict`/`vsuite` (i.e. undoing the placement the code comment at `:2146-2148` calls load-bearing) leaves the suite fully green. AC-4's re-verify clause has no killer; the `(at)` fixture never triggers a pool disagreement.
  - **SURVIVED** — turning the header write's `|| die` into a silent skip leaves the suite green: `(at4)` still reds, but via the *row-append*'s or-die, not the header's. The case cannot tell the two guards apart, so the header guard is the one that actually matters for a zero-mutants-scored run and is the one with no independent killer.

  The behavior AC-3 and AC-4 describe is present in the code as written — I verified both by reading, and the placement comment is correct. What is missing is the regression guard, which is why this is a major and not a blocker. Cheap follow-up: extend `(at)` with a pool-disagreement fixture asserting the corrected row, and a zero-mutant `--mode pr` run against an unwritable path.

### Minor

- `mutation-sweep.sh:11` — the USAGE line advertises `[--verdict-log F]` for `--mode merge`, where the run reaches the header write (`:857`) and then the merge branch (`:951`) without scoring a single mutant, so the file is always header-only. Nothing false is claimed ("one row per SCORED mutant", and merge scores none), but a one-clause note would save a reader the trip.
- `docs/testing.md:1456` — the operator route says to "concatenate their `mutation-verdict-log.tsv` files by hand"; ten shard files means ten header rows in the concatenation. A `tail -n +2` hint would make the recipe directly usable.

### Recorded, not a finding

- `pr-gates` is red at step 6, "lean chain reconciliation". Expected: no verdict record exists on the branch yet. A merge-boundary policy state, not a code finding.
- `mutation-sweep-pr` is green in 12s and covers **nothing** on this diff: `tools/mutation-sweep.sh` carries a recursion-guard row in `tools/mutation-exclusions.tsv:22`, and the only other changed shell file is a selftest, so zero in-universe guards were swept. Structural and by design — recorded so the green is not credited as mutation evidence. The hand probes above are what stands in for it.

## Panel

Six reviewers dispatched via `code-review.mjs`, all returned usable results, none dark: security, performance, maintainability, complexity, test-coverage, scope-completeness — every one `approve` with zero findings. Two suppressed notes were worth chasing and are folded in above: the merge-mode-advertisement point (scope-completeness) and a TSV-framing note on mutant ids containing tabs (security, confidence 35 — ids are paths plus operator ids plus hex digests, so not reachable). a11y and the design-fidelity dimension were not routed: no changed path matches `stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).

## Strengths

- The placement of the row `printf` after the pool-disagreement correction is the one non-obvious correctness point in the change, and it is both correct and commented as to why — the comment states the reason rather than the fact.
- The change buys its measurement with no new computation: `sid` and `vsuite` were already in scope in the tally loop, so this is a `printf` and not an instrument, exactly as the ticket argued.
- Checking that merge mode enumerates shard files by exact name is the kind of collateral a new file in a published artifact directory could plausibly have broken; it does not.
- The scope discipline holds — no operator or baseline row is deleted here, and the ratification comment's obligation (the deletion re-enters under #717 against these numbers) is restated in both the spec and the commit body.
