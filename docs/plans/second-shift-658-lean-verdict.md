# lean review verdict — #658

verdict=needs-work
run_id: review-658-3
session_id: f8994023-dffd-4df6-bc28-164e1a629303
rounds: 3
pr: #683
reviewed_head: e266d6783de438615f26c5a7eb887382ed297ed2
reviewed_patch_id: df88b275329e3aee27a077ca77b1a4a3ab5af293
inherited_patch_id: 7333cb7e09ccfd5f09cb8f95d05f2fb6c7882714
inherited_from_verdict: 4773ae94724cbf1bf919c5c16c178a59a743e97f
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 3 — delta `4773ae94..HEAD` (one fix commit `e266d678`; two files, `docs/testing.md` and
`plugins/dev-pipeline/skills/review-lean/SKILL.md`; 11 insertions, 8 deletions), inheriting
round 2's coverage of patch `7333cb7e09cc`. Read **wider than the delta**: the blocker below is
in text untouched since round 1, and the delta alone cannot show it. Panel: scope-completeness +
an adversarial fact-checker briefed to verify every claim against named source files rather than
the prose describing them, 2/2 returned. Every factual claim below was re-verified first-hand in
this checkout against `ci.yml`, `nightly-guards.yml`, `run-selftests.sh` and the #643/#650 specs.

**Verdict: needs-work — 1 blocker, 2 warnings.** Round 2's blocker and warning are both genuinely
resolved. The blocker below is new to this round's reading, not carried, and it sits inside an
AC-1 deliverable.

## Round-2 findings, re-scored

- **B1 — resolved at both named sites.** `git grep -n verbatim` returns zero hits in
  `review-lean/SKILL.md` and zero in the CI-citation subsection; the survivors are
  `CHANGELOG.md`, unrelated plans, `ci.yml:138`'s lockstep comment, and `docs/testing.md`'s
  `verbatim` relation-name section at `:704+`. `SKILL.md:55` now reads "a CI run whose command and
  head both match this review"; `docs/testing.md:502` now reads "any command that differs from
  what CI ran". This clears issue #658's own AC-1 bar ("same command AND same head = cite;
  otherwise execute"), not merely the spec's.
- **W1 — resolved, and with round 2's own suggested shape.** `:485-487` drops the absolute clause,
  concedes that an under-declared `tools/selftest-cache-inputs.tsv` row *is* the gap, and names
  the nightly cold sweep as what catches it. The backstop checks out: `nightly-guards.yml:46` is
  `cron: '41 2 * * *'` (daily) and both lanes (`:104`, `:149`) sweep with no `--cache-dir`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — guidance in `review-lean/SKILL.md` with the discriminator inline, **full rationale and worked examples** in a new `docs/testing.md` subsection it links to, both committed | **unsatisfied** | The surface, the inline discriminator and the link are all correct: `SKILL.md:55-57`, anchor `#citing-a-ci-run-instead-of-re-running-it-review-side` matching the heading at `docs/testing.md:468`, `../../../../` resolving to repo root. The **worked examples** clause is where B1 lands — the sole illustration of the `Command differs` branch (`:492-494`) is refuted by `ci.yml` at this same head. Two of three bullets are sound; the one that is not inverts the rule for this repo's most common oracle shape. |
| AC-2 (oracle) — no new gate/script; `git diff --stat main...HEAD -- '*.sh' '*.mjs'` empty, guard-budget delta zero, no `Guard-mass:` trailer | **satisfied** | Re-run in this checkout at this head: scoped diff empty. `scripts/check-guard-budget.sh fe257f5f` → `✓ guard/test shell mass: base 51793, HEAD 51793 (delta 0)`. Branch touches four files, all markdown. |
| AC-3 (critic) — a `Changelog:` trailer stating the guidance in consumer terms | **satisfied** | `6fcc43b8` carries `Changelog: a review session verifying an oracle AC may now cite a CI run …`. `scripts/check-changelog-trailer.sh fe257f5f` → OK. |

Do-not-touch honored: `scripts/check-frozen-files.sh fe257f5f` → clean. Also green here:
`check-lockstep-pairs.sh` (29 anchors, 0 failed — no anchor binds the two edited files),
`stack-generality-lint.sh` (it scans `review-lean/SKILL.md` by name). Fidelity `not-applicable` —
the spec arms no `## Design` section and the repo declares no `design.provider`.

The red `pr-gates` check is **not a branch defect**: `check-lean-chain.sh` reads round 2's
`verdict=needs-work` record (`✗ … reads 'verdict=needs-work', not 'verdict=approve'`). Expected
for a PR awaiting its round; it clears when an `approve` record lands. Both cited lanes are green
at this exact head — run 32867765464, `lint-and-selftests` 4m27s, `selftests (macos, bash 3.2)`
7m9s, `mutation-sweep-pr` 13s, all at `e266d678`.

## B1 (blocker) — `docs/testing.md:492-494`: the only worked example of the `Command differs` branch tells the reader to Execute in a case the rule says to Cite

> - **Command differs** — the AC's recipe carries a flag or exclusion CI's invocation does not (the
>   #650 campaign's AC-4 case: the AC asserted `--full`, the configured lane runs without it). CI's
>   green proves a different claim than the AC makes. Execute.

**CI's invocation carries `--full`.** Both selftest lanes, identically, and these are the only two
`run-selftests.sh` invocations in the file:

```
.github/workflows/ci.yml:121  args=(--full --exclude tools/install-topology-selftest.sh --cache-dir "$RUNNER_TEMP/selftest-cache")
.github/workflows/ci.yml:414  args=(--full --exclude tools/install-topology-selftest.sh --cache-dir "$RUNNER_TEMP/selftest-cache")
```

So an AC asserting `--full` does **not** differ from CI's invocation, and by the bullet's own
stated comparator it is a **cite** case. The lane that runs without `--full` is the dogfood
lean-gate milestone-3 `test` lane — `CLAUDE.md:96-99`, "`lean-gate.sh 3` is the exception: it runs
the sweep inline, bounded by `tools/selftest-suite-timings.tsv`". That is a *build-gate*
comparator, not CI's, and the bullet's leading clause names CI.

Why this is a blocker and not a nit: this is the subsection's single concrete illustration of the
branch that sends a reviewer back to execution, and the mandated `--full` sweep is the most
common oracle shape in this repo. A reviewer who pattern-matches the example — "the AC asserted
`--full`, so execute" — spends exactly the sweep #658 was filed to stop, on the exact AC class it
was filed about. The example does not merely fail to illustrate the rule; it contradicts it, and
one `grep -n 'args=(' .github/workflows/ci.yml` at this head refutes it. Same failure class as
rounds 1 and 2: a sentence reaching past its measurement.

**Attribution is also wrong**, independently: #650's AC-4 is "variant `c` exists as a time-boxed
instrument: the attended drive-mode" (`docs/plans/second-shift-650-lean.md:48`); #650's `--full`
sweep oracle is **AC-9** (`:68`). The AC-4 that *is* the `--full` sweep oracle belongs to **#643**
(`docs/plans/second-shift-643-lean.md:43`).

**Remedy — replace the example with one that is genuinely a CI-comparator mismatch**, which this
repo supplies directly: both CI lanes pass `--exclude tools/install-topology-selftest.sh`, so an
AC asserting `bash tools/install-topology-selftest.sh` is green is *not* proved by the PR run and
must be executed (or cited from `nightly-guards.yml`). That instantiates the bullet's rule exactly,
against the comparator it names, and is checkable from the same two argv lines. If the #643 case is
kept instead, it has to be re-framed as a *build-gate* mismatch and moved out from under a bullet
whose comparator is CI.

## W1 (warning) — `docs/testing.md:485-487`: "the PR recipe" is a coinage that collides with the paragraph's own fixed term, and over-generalizes

> An *under-declared* row is exactly that gap; it is the nightly's cold sweep, **not the PR
> recipe**, that catches it (within a day, per the containment above).

Two problems in one clause.

*The referent.* `the recipe` is a fixed term used five other times in this subsection for
`CLAUDE.md`'s mandated **local** sweep, which runs cold (`docs/testing.md:382`) and therefore
*does* run an under-declared suite. `the PR recipe` occurs exactly once in the repo. Read with the
paragraph's own vocabulary it means "the recipe, run against the PR" — under which the sentence is
false and contradicts its own preceding clause. The doc already has a term for what it means:
`PR lane`, used four times elsewhere in this file. One word fixes it.

*The scope.* Even read charitably as CI's PR lane, "not the PR lane catches it" over-generalizes.
The cache key is content-addressed over the declared set (`tools/run-selftests.sh:469-487`), and a
row must name the suite itself and its subject script (`tools/selftest-cache-inputs.tsv:19-22`,
enforced at `run-selftests.sh:443-448`). A PR that moves an undeclared input *and* any declared one
moves the key, misses the cache, and runs the suite on the PR lane. The escaping case is narrower:
the PR touched *only* undeclared inputs.

The ruling survives — `--cache-dir` is still correctly classified "same command", and the
concession round 2 asked for is present and correct. Only this clause needs narrowing.

## W2 (warning) — `docs/testing.md:476-478`: `gh pr checks` cannot supply the head SHA the sentence says it does

> `gh pr checks <pr>` or `gh run view <run-id> --json headSha,conclusion,jobs` names the job, the
> head SHA, and the conclusion; citing those three IS the verification.

Measured against the installed `gh` in this checkout: `gh pr checks 683 --json` offers
`bucket, completedAt, description, event, link, name, startedAt, state, workflow` — **no head
SHA** — and the plain form prints name / state / elapsed / link only. The `gh run view` half is
correct. The "or" distributes over a three-item list that the first alternative supplies only two
of, and the missing item is **head match, half the discriminator**. A reviewer taking the
`gh pr checks` branch produces a citation with no head evidence, which is the "Head differs"
failure the bullet at `:495-496` exists to prevent.

The practical bite is bounded — `gh pr checks` is scoped to the PR's current head by construction,
and the reviewer has `git rev-parse HEAD` — which is why this is a warning, not a blocker. Remedy:
give the head SHA to the `gh run view` alternative only, or append `git rev-parse HEAD` to the
`gh pr checks` branch. Note the run's own ledger `D-4` claims only
`gh run view --json headSha,conclusion,jobs` was "verified runnable"; the `gh pr checks` half was
never checked.

## Noted, not findings

- **Exposure bound dropped.** `:485-487` states the under-declaration residual without the bound
  round 2 recorded: `tools/selftest-cache-inputs.tsv` is four rows, all one suite
  (`cost-block-selftest.sh`), and a suite with no row is always run. The new prose overstates the
  residual in the opposite direction from the sentence it replaced. Worth a clause if the paragraph
  is touched for W1 anyway.
- **The nightly's containment is post-merge.** `schedule:` events run on the default branch, so the
  cold sweep sees this PR's content only after it lands — "within a day" is "within a day of
  merge", not "before the reviewer signs off". Consistent with the pre-existing "against a tree
  nobody is waiting on" (`:395`), but the new sentence sits inside an argument about whether *this*
  review can skip execution, where the distinction is material.
- `:474` "have both run the recipe's suite set" versus `:483-487`'s concession that a cached suite
  was *served from a marker* rather than executed — the runner's own summary distinguishes them
  (`run-selftests.sh:697`: "`$RAN scored, $((RAN - CACHED)) run, $CACHED served from cache`").
  Round 2 scored this a nit and left it; the delta sharpens the tension without creating it.
- `:475-476` describes "the reviewer's own checkout (bash 5.x + BSD)" as given — true of this
  machine, stated universally. Round 2 explicitly ruled it not worth a round; unchanged, and I
  concur.
- **No deviation row is owed** for the departure from the issue Problem section's "verbatim": the
  spec's own "What this slice is" already states the two-part discriminator ("same command AND same
  head ⇒ cite; either differs ⇒ execute"), so the shipped text matches the spec. Only the spec's
  title echoes the issue's word, as a restated problem statement.
- Second-shift has no markdown format gate in `ci.yml`, so an unformatted record carries no
  obligation here.

## Strengths

- Round 2's blocker was fixed at **both** sites it named rather than only the one quoted first —
  the failure mode that cost round 2 did not recur.
- The W1 repair is stronger than the remedy asked for: it names the exception outright and points
  at the mechanism that catches it, instead of hedging the claim.
- Every load-bearing claim in the tolerance paragraph holds against source. I re-verified all of
  them: `--cache-dir` on both lanes; `--cache-write` gated to `push` with `push: branches: [main]`;
  the `SKIP_STRESS` asymmetry, with `audit-selftest.sh:105` the only suite-level gate in the
  discovered sweep, so unset runs strictly more; and "skips only when every declared input is
  byte-unchanged" correct as a necessary condition, the real key being broader.
- The citation mechanic the PR introduces is demonstrably usable on the PR that introduces it —
  both cited lanes are green at `e266d678`.
