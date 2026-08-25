# lean review verdict — #658

verdict=approve
run_id: review-658-4
session_id: 42c56fcf-ab39-4cb6-88f3-889f0376bdd3
rounds: 4
pr: #683
reviewed_head: 716767046cf9b1c0dad5090537c64517b6fe963c
reviewed_patch_id: 0df81552818a3273332d8c1dd17c9bfee844b688
inherited_patch_id: df88b275329e3aee27a077ca77b1a4a3ab5af293
inherited_from_verdict: a4395419c533bd94f2973dbdbee6b2fc3c0ed445
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 4 — delta `a4395419..HEAD` (one fix commit `71676704`; one file, `docs/testing.md`; 13
insertions, 8 deletions), inheriting round 3's coverage of patch `df88b275329e`. Read **wider than
the delta**, as rounds 2 and 3 both had to: this branch's defects have twice sat in text the delta
did not touch. Panel: scope-completeness, plus a fact-checker briefed to *enumerate every
falsifiable claim in the subsection and adjudicate each against a named source file* — the brief
that found round 3's blocker where a role-shaped reviewer returned PASS. 2/2 returned. Every claim
adopted below was re-verified first-hand in this checkout.

**Verdict: approve — 0 blockers, 5 warnings.** Round 3's blocker and both warnings are genuinely
resolved, each verified against the source that decides it rather than against the prose. All three
ACs are satisfied. The warnings are wording precision and one release-artifact hygiene item with a
merge-time fix; none of them makes the shipped guidance produce a wrong verdict when the bullet is
read in full.

## Round-3 findings, re-scored

- **B1 — resolved.** The `Command differs` worked example no longer names the `--full` case. The
  replacement is checked against the comparator the bullet names: `.github/workflows/ci.yml:121`
  and `:414` are byte-identical —
  `args=(--full --exclude tools/install-topology-selftest.sh --cache-dir "$RUNNER_TEMP/selftest-cache")`
  — and `:125`/`:418` are the only two `bash tools/run-selftests.sh` invocations in the file. So an
  AC asserting `tools/install-topology-selftest.sh` is green genuinely is *not* proved by the PR
  run: that path appears in `ci.yml` only as the `--exclude` argument, and the suite executes only
  at `nightly-guards.yml:63` and `:80`. The bogus `#650 AC-4` attribution is removed rather than
  re-pointed. The enclosing paragraph's delta enumeration is still complete at this head:
  `CLAUDE.md:60` is `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`,
  so `--cache-dir` and the ubuntu lane's missing `SKIP_STRESS` remain CI's only two.
- **W1 — resolved, both halves.** `the PR recipe` no longer occurs in `docs/testing.md` (the only
  repo-wide hits left are this record's own round-3 section quoting it). `:487` now uses `PR lane`,
  the file's established term (`:394`, `:404`, `:643`, `:1476`). The scope narrowing is true against
  the implementation: the key is content-addressed over the declared set (`tools/run-selftests.sh:32`,
  `:470`), so moving a declared input in the same PR moves the key, misses the cache, and runs the
  suite — and the escaping case really is "only under-declared inputs moved".
- **W2 — resolved on the fact it named.** `:477-478` now reads "its own `--json` has no head SHA
  field", which is exactly right: `gh pr checks 683 --json` (gh 2.96.0) offers
  `bucket, completedAt, description, event, link, name, startedAt, state, workflow`. The residue is
  **W4** below, and the remedy round 3 prescribed carries **W3**.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — guidance in `review-lean/SKILL.md` with the discriminator inline, full rationale and **worked examples** in a new `docs/testing.md` subsection it links to, both committed | **satisfied** | `SKILL.md:55-57` states both conditions inline inside step 5, the AC-scoring step. Link `../../../../docs/testing.md#citing-a-ci-run-instead-of-re-running-it-review-side` resolves (four `../` from `plugins/dev-pipeline/skills/review-lean/` is the repo root) and the anchor matches the heading at `docs/testing.md:468`. The worked-examples clause — where round 3's blocker landed — is now correct against `ci.yml`'s real argv. Precedent for the outward link depth: `run-lean/SKILL.md:47`. |
| AC-2 (oracle) — no new gate/script; `git diff --stat main...HEAD -- '*.sh' '*.mjs'` empty, guard-budget delta zero, no `Guard-mass:` trailer | **satisfied** | Re-run in this checkout at this head: scoped diff empty. `scripts/check-guard-budget.sh fe257f5f` → `✓ guard/test shell mass: base 51793, HEAD 51793 (delta 0)`. The branch touches four files, all markdown. |
| AC-3 (critic) — a `Changelog:` trailer stating the guidance in consumer terms | **satisfied** | `6fcc43b8` carries `Changelog: a review session verifying an oracle AC may now cite a CI run (job, head SHA, conclusion) instead of re-executing the sweep, when the run's command and head both match the reviewed commit. Migration: none.` `scripts/check-changelog-trailer.sh fe257f5f` → OK. A *second* trailer on the branch renders unintentionally — **W1**, which does not unsatisfy this AC. |

Do-not-touch honored: `scripts/check-frozen-files.sh fe257f5f` → clean; the branch touches no
`plugin.json`, `CHANGELOG.md` or `marketplace.json`. Also green here:
`check-lockstep-pairs.sh` (29 anchors, 0 failed — no anchor binds the edited files),
`stack-generality-lint.sh` (which scans `review-lean/SKILL.md` by name). Fidelity
`not-applicable` — the spec arms no `## Design` section and the repo declares no `design.provider`.

**CI at this exact head** (`71676704`, run 32870611395): `lint-and-selftests` pass 4m37s,
`selftests (macos, bash 3.2)` pass 6m46s, `mutation-sweep-pr` pass 12s. The red `pr-gates` is
**not a branch defect and masks nothing** — `--log-failed` shows its only failure is
`check-lean-chain.sh` reading round 3's `verdict=needs-work`, and the job states outright that
"freshness is undefined for a non-approve record, so the changed-files and patch-id/reviewed-head
arms are not evaluated". It clears when this `approve` record lands.

## W1 (warning) — the fix commit's `Changelog:` trailer renders internal review narrative into `CHANGELOG.md` and the Release notes

`71676704`'s trailer is not the opt-out it opens with:

```
Changelog: none. Round-3 review fixes only: the Command-differs worked example named an AC
  shape (#650's --full assertion) that both CI selftest lanes actually satisfy, and instead
  points at a shape they genuinely don't cover (an AC asserting
  …
```

The continuation lines are two-space indented, so `derive-release.sh`'s `extract_trailers`
(`:115-121`) folds the whole paragraph into one block. The no-op test (`:240-243`) strips trailing
whitespace and **one** trailing period, then compares to `none` — `none. Round-3 review fixes
only: …` is not `none`, so the block renders. I extracted both awk programs verbatim and ran them
over this branch's squash body:

```
$ git log --reverse --format=%B main..HEAD | bash /tmp/probe683-trailer.sh
  a review session verifying an oracle AC may now cite a CI run (job, head SHA,
  conclusion) instead of re-executing the sweep … Migration: none.
  none. Round-3 review fixes only: the Command-differs worked example named an AC
  shape (#650's --full assertion) that both CI selftest lanes actually satisfy, …
```

Both blocks render. The repo's squash prefill is `COMMIT_MESSAGES`
(`gh api repos/manoldonev/second-shift`), and merged commits on main confirm bodies concatenate —
`a7a9a383` carries nine `Changelog:` lines, `93b857fe` five. Per `docs/releasing.md:17` the trailer
becomes "the CHANGELOG bullet body **and** the Release 'What…'", so this lands in two public
artifacts. `derive-release.sh:35-36` records that this exact class — a trailer whose "none" the
matcher misses — "shipped literal `  none.` bullets into CHANGELOG.md for 12 commits before anyone
noticed", so the human checklist at `:437` is an empirically weak backstop.

Not a blocker: AC-3's bar is a trailer stating the guidance in consumer terms, and `6fcc43b8`
supplies it; the branch's *diff* is clean; and the squash body is authored at merge, not carried by
the branch. **The fix is at the merge boundary and costs nothing:** when squashing, delete the
`none. Round-3 review fixes only: …` block from the prefilled body (or reduce it to a bare
`Changelog: none` on its own line, with the narrative unindented above it). Rewriting `71676704`'s
message on the branch would work too and changes no `+`/`-` line, but it is the more expensive path
and is not required.

## W2 (warning) — `docs/testing.md:496`: the `Command differs` bullet's lead clause states one direction, and its own worked example is the other one

> - **Command differs** — the AC's recipe carries a flag or exclusion CI's invocation does not (e.g.
>   an AC asserting `tools/install-topology-selftest.sh` is green: both CI selftest jobs run
>   `--exclude tools/install-topology-selftest.sh` …)

The clause's possessor is *the AC's recipe*; in the example the possessor is **CI**, and the AC's
recipe (`bash tools/install-topology-selftest.sh`) carries no flag or exclusion at all. Asked the
clause's literal question about its own example, the honest answer is "no" — which falls through
`Head differs` to `:502` **Neither differs — cite the run and stop**, the opposite of what the
parenthetical says. Both panel members raised this independently; the fact-checker adds the sharper
observation that **the clause's stated direction has no positive instance in the repo**: the one
AC-side extra that exists is `SKIP_STRESS=1`, and `:483`/`:492` explicitly rule it *same command*.

Why warning and not blocker, and this is a close call. Round 3's B1 was worse in kind: the example
asserted something false about `ci.yml`, so a reader who checked the fact was misled. Here every
fact is true, and the bullet read in full is self-correcting twice over — its own heading
("Command differs") is direction-neutral, and its closing sentence states the correct
direction-neutral test outright: *"CI's green proves a different claim than the AC makes."* The
narrow clause is the middle third of a bullet whose first and last thirds are right.

One-clause fix, since this is the third consecutive round to land in this same bullet: make the
lead clause symmetric — *"the AC's recipe and CI's invocation differ in any flag, exclusion, or
suite set"*. That also stops the clause from describing an empty set.

## W3 (warning) — `docs/testing.md:477-478`: `git rev-parse HEAD` is the *local* head, not the head the cited run executed at

> `gh pr checks <pr>` names the job and conclusion for the PR's current head — its own `--json` has
> no head SHA field, so pair it with `git rev-parse HEAD`

Round 3 prescribed exactly this remedy, so the fix did what it was asked; the residue is that the
two halves read different trees. `gh pr checks` reports the *remote* PR head; `git rev-parse HEAD`
reports the reviewer's worktree. When they diverge — a stale lane worktree, or a fix commit not yet
pushed — the pairing manufactures a "same head" match for a run that executed against a different
tree, which is precisely the `Head differs` failure the next bullet exists to prevent. This branch's
own history contains that shape: the round-3 build spawn exited 0 with its edit uncommitted. The
one-field fix is already available and reads the same tree as `gh pr checks`:
`gh pr view <pr> --json headRefOid`.

## W4 (warning) — `docs/testing.md:476-478`: the `--json` gap the sentence names is not the only one

The sentence pivots into `--json` register and names exactly one absent field, which reads as an
exhaustive gap list. Measured against gh 2.96.0 in this checkout, `conclusion` is absent too:

```
$ gh pr checks 683 --json name,conclusion
Unknown JSON field: "conclusion"
Available fields:
  bucket, completedAt, description, event, link, name, startedAt, state, workflow
```

The field is `state` (`SUCCESS`/`FAILURE`/…) or `bucket` (`pass`/`fail`/…). `SKILL.md:56` mandates
citing `(job, head SHA, conclusion)` *by that name*, so a reviewer assembling the citation from
`gh pr checks --json` finds two of the three absent and hits a hard error on the field the doc just
said that command supplies. The plain (non-`--json`) output does carry an unlabeled state column, so
the prose half is defensible in isolation — the defect is the pairing. Remedy: name `state`/`bucket`
alongside the head-SHA caveat, or scope the `--json` clause to `gh run view` only.

## W5 (warning) — the PR body still advertises the worked example round 3 removed

The description of record on PR 683 still reads:

> `docs/testing.md` carries the worked cases — a command mismatch (the #650 AC-4 shape: an AC naming
> `--full` where the config lane runs without it) …

The doc no longer carries that case, and the `#650 AC-4` attribution is the one round 3 refuted
(#650's AC-4 is the attended drive-mode; the `--full` sweep oracle is #650's AC-9, and the AC-4 that
*is* a `--full` oracle belongs to #643). The body does not reach `main` — the squash prefill is
`COMMIT_MESSAGES`, not the PR body — so this is a shared-artifact accuracy item, not a shipped one.
A reader who trusts the body would expect the doc to contain exactly the text round 3 blocked on.
`gh pr edit 683 --body-file …` fixes it.

## Noted, not findings

- **`:475` "have both run the recipe's suite set"** versus the next paragraph's concession that a
  cached suite was served from a marker rather than executed. Round 3 scored this a nit and left it;
  I concur and note the bound: `tools/selftest-cache-inputs.tsv` has four non-comment rows, all for
  `cost-block-selftest.sh`, and `tools/selftest-cache-inputs.tsv:7` — "A suite with NO row is ALWAYS
  RUN" — is implemented at `run-selftests.sh:556-559`. At most one of the discovered suites can be
  skipped today.
- **`:476` "ubuntu is bash 5.x"** is not repo-decidable. The repo's own nearest statement is
  `ci.yml:390` ("the stress legs run once, under bash 4+"); `tools/mutation-sweep.sh:92` supports the
  GNU half only. Externally true for ubuntu-24.04, and rounds 1 and 3 both declined to spend a round
  on this sentence. Unchanged.
- **`:472` "a *third* execution"** is internally consistent with the two CI jobs the sentence itself
  enumerates, even though `CLAUDE.md:82-84` puts the same sweep on the lean lane's milestone-3 too.
  Not a defect.
- **`:470` "the *build* lane"** is loose — the pass cache's two main consumers are the CI PR lanes,
  with the lean lane named separately at `:397` as "the third participant". The build-vs-review
  contrast the topic sentence draws is still the right one.
- **`:472` "oracle `AC-n`"** uses the AC-verification-rung sense (`spec-reviewer.md:120`) in a file
  that elsewhere (`:1094`, `:1100`, `:1181`) uses "oracle" in the classic testing sense. Both senses
  are current repo usage; no gloss is owed.
- **`ci.yml:121`/`:414` are unguarded line-number citations** — exact at this head (verified by
  `sed -n '121p;414p'`), but nothing reds if an edit above them re-points the reference, and
  `docs/testing.md` carries only one other `file:line` citation (`:201`). Not this PR's to solve;
  `CLAUDE.md`'s route for a real-but-not-byte-anchorable coupling is a *Couplings considered and
  declined* row, if anyone thinks it earns one.
- **The nightly's containment is post-merge** (`schedule:` runs on the default branch). Rounds 2 and
  3 both settled this; unchanged. The backstop itself is real and two-laned:
  `nightly-guards.yml:104` and `:149` both sweep cold, `:46` is `cron: '41 2 * * *'`.
- Second-shift has no markdown format gate in `ci.yml`, so an unformatted record carries no
  obligation here.

## Strengths

- Round 3's blocker was fixed **against the comparator the rule names**, not merely at the sentence
  the finding quoted — the failure mode that cost round 2 did not recur, and the remedy chose the
  one exclusion in this repo that genuinely escapes the PR lanes' green.
- The wrong `#650 AC-4` attribution was deleted rather than re-pointed at #643, which is the right
  call for a doc whose worked example should be checkable from `ci.yml` alone.
- Both W-fixes were verified against the tool, not the docs: the `gh pr checks` field list is
  reproduced accurately, and the cache-key narrowing matches `run-selftests.sh`'s actual key
  derivation rather than the summary of it.
- The citation mechanic this PR introduces is demonstrably usable on the PR that introduces it —
  both named lanes are green at `71676704`, and this record cites them rather than re-running the
  sweep, which is the behavior #658 exists to produce.
