# lean review verdict — #658

verdict=needs-work
run_id: review-658-1
session_id: 2d0c92bc-23fe-4f02-ab0c-ab96a58d9e71
rounds: 1
pr: #683
reviewed_head: 6fcc43b8584ca26e048950302f122968f3944c2f
reviewed_patch_id: 85a92796bf2bad4aefda3e3d9b0ab7408e1c564a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 — full branch range `fe257f5f..6fcc43b8` (nothing to inherit). Panel: security,
performance, maintainability, scope-completeness — 4/4 returned, all `approve`, **zero
findings**, consistent with the standing prose-diff pattern. Every finding below is
hand-derived.

**Verdict: needs-work — 1 blocker, 2 warnings. All three ACs satisfied; the blocker is a
defect the ACs do not reach.**

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — guidance in `review-lean/SKILL.md` with the discriminator inline, rationale + worked examples in a new `docs/testing.md` subsection it links to, both committed | **satisfied** | `SKILL.md:55-57` states it inline and links `docs/testing.md#citing-a-ci-run-instead-of-re-running-it-review-side`; the anchor matches the new `### Citing a CI run instead of re-running it (review side)` heading (`docs/testing.md:468`), placed under `## How the sweep runs` directly after `### The pass cache` as D-3 says. Link depth `../../../../docs/` matches the file's own precedent (`run-lean/SKILL.md:47` → `../../../../docs/pipeline-manifesto.md`). Both worked examples (command-differs, head-differs) are present and correct. B1 is a defect in the section's framing sentence, not a missing AC element. |
| AC-2 (oracle) — no new gate/script; `git diff --stat main...HEAD -- '*.sh' '*.mjs'` empty, guard-budget delta zero, no `Guard-mass:` trailer needed | **satisfied** | Re-run in this checkout: the diff is empty. `scripts/check-guard-budget.sh fe257f5f` → `✓ guard/test shell mass: base 51793, HEAD 51793 (delta 0)`. |
| AC-3 (critic) — a `Changelog:` trailer stating the guidance in consumer terms | **satisfied** | `6fcc43b8` carries `Changelog: a review session verifying an oracle AC may now cite a CI run (job, head SHA, conclusion) …`. `scripts/check-changelog-trailer.sh fe257f5f` → OK. |

Do-not-touch honored: `scripts/check-frozen-files.sh fe257f5f` → clean. Also green in this
checkout: `stack-generality-lint.sh` (which scans `review-lean/SKILL.md` by name),
`check-lockstep-pairs.sh` (29 anchors, 0 failed). Fidelity `not-applicable` — the spec arms
no `## Design` section and the repo declares no `design.provider`.

## B1 (blocker) — `docs/testing.md:472-474`: the "verbatim" premise is refuted by three sources at this same head

The new subsection asserts that `lint-and-selftests` (ubuntu) and `selftests-bash32` (macos)
"have both run **it**, verbatim, at the commit under review", where *it* is CLAUDE.md's
mandated recipe:

```
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

Neither lane runs that command. Both build, unconditionally:

```
args=(--full --exclude tools/install-topology-selftest.sh --cache-dir "$RUNNER_TEMP/selftest-cache")
```

— `.github/workflows/ci.yml:121` (ubuntu) and `:414` (macos). The ubuntu lane additionally
sets no `SKIP_STRESS`, which the recipe does set (`ci.yml:389` names that asymmetry as
deliberate). Two further same-head sources say so outright:

- `CLAUDE.md:105` — "**The recipe above runs COLD, and that is deliberate.** CI additionally
  passes `--cache-dir` …"
- `tools/run-selftests.sh:38-40` — "the cache as a whole is off unless `--cache-dir` is
  passed, so the mandated local recipe in CLAUDE.md is still a cold sweep"; `:69` —
  "Absent, no suite is ever skipped."

Why this is a blocker rather than a nit: this sentence is the doc's **only** instance of the
`cite` branch — the branch the ticket exists to create. It is load-bearing, and it fails in
both directions.

- A reviewer who checks `ci.yml` reads `--cache-dir` as a command difference. The doc's own
  first bullet then sends them to **Execute** — and that bullet sets the granularity at a
  *single flag* (`--full` present vs absent). Under the doc's own bar, `--cache-dir` is a
  command difference, so the change is inert for the case that motivated the ticket (#647's
  killed sweep).
- A reviewer who takes the doc at its word cites a run that **read a pass cache the mandated
  recipe deliberately does not**. Restore is unconditional on PRs (`ci.yml:111-118`,
  `restore-keys: selftest-pass-${{ runner.os }}-`), and `--cache-dir` reads even without
  `--cache-write`, so suites with unchanged declared inputs are skipped in the very run being
  cited.

Today's exposure is bounded — `tools/selftest-cache-inputs.tsv` has 4 rows naming exactly one
suite, `plugins/dev-pipeline/tools/cost-block-selftest.sh` — but that table is designed to
grow ("add a row there only when you can enumerate a suite's inputs exactly"), and nothing
re-derives this sentence when it does.

**Remedy (keeps the conclusion, makes the discriminator checkable):** name the two deltas and
rule on them instead of claiming there are none — CI's invocation adds `--cache-dir`, and the
ubuntu lane omits `SKIP_STRESS=1`; classify both as *same command* (the cache skips only a
suite whose declared inputs are byte-unchanged, and a missing `SKIP_STRESS` runs strictly
more), and reserve "command differs" for anything else.

## W1 (warning) — `docs/testing.md:474-475, 485-487`: the coverage claim overstates, cell-by-cell

"both are stronger than the reviewer's own checkout, which is bash 5.x" and "CI's two lanes
already cover more (ubuntu, and macos under bash 3.2) than a single bash-5.x retry ever will".

The two lanes are **ubuntu = bash 5.x + GNU coreutils** and **macos = bash 3.2 + BSD**
(`ci.yml:18`, `:384`, `:410-412`). The reviewer's checkout is **bash 5.3.9 + BSD/macOS**
(measured here). That third cell — the bash-4+ arm taken *with BSD tools* — is occupied by
neither lane, and it is the maintainer's own environment. The repo already has the matching
failure class on record (a BSD/GNU dual form that fails dirty).

The conclusion still holds on the union, and I am not asking for it to change. "Covers two
environments the local checkout does not" is true and sufficient; "more than a local retry
ever will" is not.

## W2 (warning) — `docs/testing.md:473`: `selftests-bash32` does not appear in the output the doc tells you to match it against

`selftests-bash32` is the YAML **job id**; the job's display `name:` is
`selftests (macos, bash 3.2)` (`ci.yml:383`). `gh pr checks <pr>` — the doc's own recommended
command, one line below — prints the display name. Verified on this PR:

```
$ gh pr checks 683
lint-and-selftests            pending
selftests (macos, bash 3.2)   pending
```

No `selftests-bash32` anywhere in it, and `gh run view --json jobs` reports display names too.
The PR body states the two names are there "to make a citation checkable"; one of them isn't
findable from the recommended command. One-word fix: give the display name, or give both.

## Strengths

- The discriminator is stated as a conjunction and then *enumerated* as three exhaustive
  bullets, so the reader cannot satisfy it by halves — and the closing paragraph explicitly
  refuses the over-read ("narrows … does not repeal", single-suite probes stay review-side).
- Correct restraint on surface: SKILL.md gets one sentence, the rationale goes to the
  overflow doc, and D-5 declines a selftest by citing CLAUDE.md's own tier-map row for prose.
  AC-2's oracle is genuinely zero-delta, not merely trailer-satisfied.
- The `#650` AC-4 worked example is a real prior incident, not an invented one, which is what
  makes the command-differs bullet checkable at all.
