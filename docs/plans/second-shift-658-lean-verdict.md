# lean review verdict — #658

verdict=needs-work
run_id: review-658-2
session_id: 3659ff5e-23a3-42a3-85e9-e2d894a0b6f8
rounds: 2
pr: #683
reviewed_head: 828166e1ebc6aefde2aaae1253afe4046cbe166c
reviewed_patch_id: 7333cb7e09ccfd5f09cb8f95d05f2fb6c7882714
inherited_patch_id: 85a92796bf2bad4aefda3e3d9b0ab7408e1c564a
inherited_from_verdict: 59b5e8e7fb446eb70c96ea061d9f5cfe42cff16f
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2 — delta `59b5e8e7..HEAD` (one file, `docs/testing.md`; 16 insertions, 6 deletions),
inheriting round 1's coverage of patch `85a92796bf2b`. Read **wider than the delta**:
`review-lean/SKILL.md` is untouched since round 1, and it is where the surviving blocker lives —
a defect the delta alone cannot show. Panel: maintainability + scope-completeness, 2/2 returned,
and **both independently reached the same blocker** (round 1's panel of four returned zero
findings). Every factual claim below was checked against the source file, not the prose
describing it.

**Verdict: needs-work — 1 blocker, 1 warning. All three ACs satisfied; the blocker is a defect
the ACs do not reach.**

## Round-1 findings, re-scored

- **W2 — resolved.** `docs/testing.md:473-474` now gives the job id *and* the display name
  `selftests (macos, bash 3.2)` (`ci.yml:383`). Confirmed print-accurate against this PR:
  `gh pr checks 683` emits exactly that string. `lint-and-selftests` carries no `name:` key
  (`ci.yml:17-18`), so its job id *is* its display name.
- **W1 — resolved.** `:475-476` and `:495-497` are now cell-accurate — "two environments the
  local checkout does not", not "more than a local retry ever will". The union-level conclusion
  is retained, exactly as W1 asked.
- **B1 — the paragraph is fixed; the defect is not.** See below.

The new paragraph at `:480-486` is itself sound, and I verified each of its load-bearing claims:
`--cache-dir` on both lanes (`ci.yml:121`, `:414`); `--cache-write` gated to `push`, and
`push: branches: [main]` (`ci.yml:3-5`, `:122-123`, `:415-416`), so "push-only" holds; the
`SKIP_STRESS` asymmetry, deliberate and named at `ci.yml:389`, set at `:408`, absent on ubuntu;
"runs strictly *more*, never less" — exactly one site honors it as a gate
(`plugins/audit-toolkit/scripts/audit-selftest.sh:103`), none runs extra when it is set. The
"skips a suite only when every declared input is byte-unchanged" framing is a *necessary*
condition, which is correct and conservative: the real key is broader
(`tools/run-selftests.sh:32-36`).

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — guidance in `review-lean/SKILL.md` with the discriminator inline, rationale + worked examples in a new `docs/testing.md` subsection it links to, both committed | **satisfied** (structurally; the shipped wording carries B1) | `SKILL.md:55-57` states it inline and links `docs/testing.md#citing-a-ci-run-instead-of-re-running-it-review-side`; the anchor slug matches the heading at `docs/testing.md:468`, placed under `## How the sweep runs` after `### The pass cache`; three worked bullets at `:490-497`. Both files in the branch diff. |
| AC-2 (oracle) — no new gate/script; `git diff --stat main...HEAD -- '*.sh' '*.mjs'` empty, guard-budget delta zero, no `Guard-mass:` trailer | **satisfied** | Re-run in this checkout at this head: the scoped diff is empty. `scripts/check-guard-budget.sh fe257f5f` → `✓ guard/test shell mass: base 51793, HEAD 51793 (delta 0)`. |
| AC-3 (critic) — a `Changelog:` trailer stating the guidance in consumer terms | **satisfied** | `6fcc43b8` carries `Changelog: a review session verifying an oracle AC may now cite a CI run …`. `scripts/check-changelog-trailer.sh fe257f5f` → OK; the fix commit's `Changelog: none` is fine, the gate is grep-anywhere. |

Do-not-touch honored: `scripts/check-frozen-files.sh fe257f5f` → clean. Also green here:
`check-lockstep-pairs.sh` (29 anchors, 0 failed), `stack-generality-lint.sh` (it scans
`review-lean/SKILL.md` by name). Fidelity `not-applicable` — the spec arms no `## Design`
section and the repo declares no `design.provider`.

The red `pr-gates` check on this PR is **not a branch defect**: `check-lean-chain.sh` reads
round 1's `verdict=needs-work` record. That is the expected shape for a PR awaiting its next
round, and it clears when an `approve` record lands.

## B1 (blocker, carried) — the refuted `verbatim` premise survives at the two sentences that govern the cite branch

The round-1 remedy was applied to the paragraph B1 was filed against. **The fix commit
`828166e1` touched `docs/testing.md` and nothing else** — so the word the blocker was about is
still load-bearing in both places it decides behavior:

1. **`plugins/dev-pipeline/skills/review-lean/SKILL.md:55`** — "**An oracle `AC-n` CI already ran
   verbatim at this reviewed head** is verified by citing that run". This is the primary surface:
   the file D-1 identifies as "the surface a review session loads first", and the one AC-1 exists
   to populate. `docs/testing.md` is one link away and may not be opened.
2. **`docs/testing.md:500`** — "any command CI never ran **verbatim**, is still review-side work",
   framed as binding ("not a discretion call").

Both are refuted by this branch's own newly added text, fourteen lines above the second one:

```
docs/testing.md:480-486
CI's own invocation is not byte-identical to the recipe — it adds `--cache-dir …`, and the
ubuntu lane sets no `SKIP_STRESS` where the recipe sets `SKIP_STRESS=1` … Both classify as
same command.
```

CI never runs the mandated recipe verbatim — the PR itself now says so, and `ci.yml:121`/`:414`
confirm it. So the condition `SKILL.md:55` gates the cite branch on is **never satisfied**, and
under the literal test the guidance is inert for the case that motivated the ticket (#647's
killed sweep). That is round 1's B1 failure mode exactly — "a reviewer who checks `ci.yml` reads
a command difference and executes anyway" — relocated from the overflow doc to the surface that
matters more.

The same sentence is internally inconsistent, which is why this is not a stylistic quibble: its
second clause ("execute only when the command or the head differs from what CI ran") is the
**correct** rule, sitting beside a leading clause that states a stricter one.

**It also misses the ticket's own bar.** Issue #658 AC-1 asks for "the cite-vs-execute
discriminator stated (**same command** AND same head = cite; otherwise execute)". `same command`
is an equivalence class with named tolerances; `verbatim` is byte-identity, a test CI's real argv
fails. The issue's *Problem* section does use "verbatim" — that is precisely the premise round 1
refuted, and it should not survive into the AC's deliverable.

**Remedy — one clause at each site**, no restructuring:

- `SKILL.md:55` → "An oracle `AC-n` CI already ran at this reviewed head (same command, per the
  discriminator) is verified by citing that run …"
- `docs/testing.md:500` → "… or any command CI never ran, per the same-command test above, is
  still review-side work".

Both panel reviewers reached this independently and scored it confidence 85.

## W1 (warning) — `docs/testing.md:484-485`: the cache-skip justification is stated absolutely, and this same page names its exception

"…skips a suite only when every input `tools/selftest-cache-inputs.tsv` declares for it is
byte-unchanged from an already-passed run, **so the skip is not a gap the recipe would have
caught differently**."

The final clause overreaches. A cached skip is exactly a gap the mandated recipe would have
caught differently when a row **under-declares** its inputs: the undeclared file changes, the key
does not move, CI skips the suite — and the recipe, which runs cold, runs it. The repo treats
that as a live risk, not a theoretical one, and says so in two places at this same head:

- `docs/testing.md:393-395` — "**The nightly ignores it.** … runs the whole sweep with no
  `--cache-dir` … An under-declaration surfaces within a day". The cold run exists *because* the
  cached run can miss this.
- `tools/selftest-cache-inputs.tsv` header — "under-declaring a suite's inputs produces a
  silently-skipped gate, **which is the cardinal failure mode in this repo**"; "A suite typically
  reads more than an eyeball would list — exactly the under-declaration the self-inclusion rule
  cannot catch"; and the one existing row "needed a depth-2 input the first revision missed".

The **ruling survives** — classifying `--cache-dir` as "same command" is still right, exposure is
bounded (4 rows, one suite), and the nightly backstops it. Only the absolute clause needs
narrowing, e.g. "…so the skip is bounded to suites whose declared inputs are unchanged; the
residual is an under-declared row, which the nightly cold leg surfaces within a day."

Same root, worth fixing in the same pass: `:474-475` says the two lanes "have both **run the
recipe's suite set**", while `:483-484` concedes a cached skip means a suite in that set was not
executed in the cited run. Disclosed a paragraph later, so it is a wording nit rather than a
second defect.

## Noted, not findings

- `:475-476` describes "the reviewer's own checkout (bash 5.x + BSD)" as given. True of the
  maintainer's machine and of the r1 measurement, but stated universally; a contributor on Linux
  reads a claim that does not hold for them. The conclusion is unaffected — the macos bash-3.2
  lane covers ground no local checkout does — so this is not worth a round.
- `SKILL.md:57`'s `../../../../docs/testing.md` resolves in-repo but not from the installed
  plugin cache. **Pre-existing pattern**, already settled in round 1: `run-lean/SKILL.md:47` does
  the same to `docs/pipeline-manifesto.md`, as do two tracker READMEs.
- Second-shift has no markdown format gate in `ci.yml`, so an unformatted record carries no
  obligation here.

## Strengths

- The fix did not merely delete the refuted sentence — it **named both deltas and ruled on each**,
  which is the stronger repair, and every one of those rulings holds against source.
- W1 and W2 were folded into the same commit rather than deferred, and W1's narrowing kept the
  conclusion while dropping only the superlative — precisely what the warning asked for.
- The two CI lanes did pass at this exact head (run 32864236255, `lint-and-selftests` 4m38s,
  `selftests (macos, bash 3.2)` 7m29s, headSha `828166e1`), so the citation mechanic the PR
  describes is demonstrably usable on the PR that introduces it.
