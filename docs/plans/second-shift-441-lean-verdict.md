# lean review verdict — #441

verdict=approve
run_id: review-441-3
session_id: 73459623-f8fa-4091-ac50-0ac979b98771
rounds: 3
pr: #455
reviewed_head: eb5f50f9c550422ec499a811bc4bce92063eedc8
reviewed_patch_id: 0fb0dae3e0527bf4f710a5a3c0eeab1adea1f9b1
inherited_patch_id: 50ae0580a67e913ef7ba7dea5e60990b1c9c725f
inherited_from_verdict: 5d0ae7e0e43090318d4cb02d209847c3f4b3f0ad
fidelity: not-applicable
model: unknown

Round 3 review of PR #455 (issue #441) over `5d0ae7e..HEAD` — the range `lean-gate delta`
printed, inheriting the coverage of patch `50ae0580a67e` (round 2's record). Round 2's findings
were read first. Head `eb5f50f` is a merge of `origin/main` on top of the round-3 fix
`da3e27d`; diffed as a diff-of-diffs, the contribution against the new base is unchanged in
content — only three `index` lines and three `@@` offsets move, because main's own edits to
`config-lint.sh` and `lockstep-manifest.tsv` sit above this branch's appended blocks. Nothing
was dropped and no conflict was resolved.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness.
a11y + design-fidelity not routed — no changed path matched `stageParams.webComponentGlobs`
(resolved default `apps/web/**/*.{tsx,jsx}`; the repo config declares none). The spec carries
no `## Design` section, so the design arm scores `not-applicable`.

Verdict: **approve** — no blockers. Round 2's blocker and both warnings are closed, and the
remedy went further than the one prescribed: rather than dropping the one wrong entry, the fix
re-derived all fourteen against each runner's own CLI and made the allowlist a per-member test
surface. I re-verified every membership claim independently (below) rather than inheriting the
build's audit — that enumeration is the thing round 2 got wrong, and a second reading of it is
the whole point of this round.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 checker contract | satisfied | Unchanged in the delta. Envelope re-verified live at the merged head against this repo's own committed config: `findings[]` + `notEvaluated[]`, exit 0 with findings present. `shellcheck -e SC1091,SC2015,SC2181` clean on `config-grill.sh`, `config-grill-selftest.sh`, `doctor.sh`. |
| AC-2 per-key table | satisfied | Unchanged in the delta; inherited from round 2, which closed round 1's B1. Suite green at the merged head. |
| AC-3 finding text + counting | satisfied | Unchanged in the delta; inherited. |
| AC-4 inconsistent config | satisfied | Unchanged in the delta; live run on this repo's config still emits `T4.mutation-plumbing.second-shift`. |
| AC-5 command reality | **satisfied** (was unsatisfied) | The `-w` bullet's enumeration now matches the predicate it instantiates. All eight members verified against each runner's own CLI, independently of the build's audit: `vitest` and `vite` from the installed CLIs' own `--help` (`-w, --watch`); `tsc` from `typescript`'s `optionDeclarations` (`watch.shortName === 'w'`); `rollup` from its installed `dist/shared/rollup.js` (`w: 'watch'`); `webpack` from webpack-cli's README help block (`-w, --watch`); `mocha` from `lib/cli/run-option-metadata.cjs` (`watch: ["w"]`); `sass` from dart-sass `options.dart` (`abbr: 'w'`); `ava` from its CLI docs (`-w, --watch`). Exclusions verified the same way: `tsup` and `esbuild` from the installed CLIs' `--help` (both define `--watch` and no `-w`), `karma` from `lib/cli.js` (`--auto-watch`, no single-letter alias), `jest` from round 2's source reading. `nodemon`'s removal is provably answer-preserving: the allowlist arm reads `$first`, and any body whose first token is `nodemon` already returned from the token arm above — so the row was unreachable, which the suite now pins. |
| AC-6 `grillWaivers` | satisfied | Unchanged in the delta and re-verified against the moved base: main edited `config-lint.sh` in the merge, and `config-lint-selftest.sh` is green at the merged head, so the appended allowlist block still composes. `jq empty` clean on the schema. |
| AC-7 onboard | satisfied | Unchanged in the delta; inherited from round 2. |
| AC-8 doctor | satisfied | Unchanged in the delta; `doctor-selftest.sh` green at the merged head. Blast radius on this repo's own config is unchanged across all three rounds: `T2.webComponentGlobs`, `T2.visualCaptureTriggerGlobs`, `T4.mutation-plumbing.second-shift`, `formatGlob` correctly silent, `T5.second-shift` not-evaluated (no root manifest). |
| AC-9 tests | satisfied | The amended AC's own addition is met and live: one firing case per member (eight), one silent case per excluded runner (five), and `nodemon -w` pinned as still firing. All fourteen probed — see below. `config-grill-selftest.sh`, `doctor-selftest.sh`, `config-lint-selftest.sh` and `check-lockstep-pairs.sh` (24 pairs) all green at the merged head. See W1 for the enumeration this AC does **not** yet cover. |
| AC-10 docs | satisfied | Unchanged in the delta; inherited from round 1. |

## Blockers

None.

## Warnings

**W1 — the `--watch` bullet is the same untested-enumeration shape the `-w` bullet just
outgrew.** The fix's stated principle is that an allowlist is a test surface, not prose,
because "reviewed as a bullet it reads as one rule". The adjacent bullet enumerates three
tokens — `--watch`, `--watchAll`, `--watch=true` — and the suite exercises exactly one of them
(`jest --watch`, `T5.watcher.app.lanes.0.0`). `--watchAll` and `--watch=true` have no case in
either direction, so a typo in either would ship green. AC-9 asks for "every **bullet** of the
watcher taxonomy" and reserves the per-member reading for the `-w` allowlist, so this does not
make AC-9 unsatisfied — and the failure direction is under-firing (a mistyped token goes
silent), which is OR-1's subject and the cheaper error by AC-5's own principle. That is why it
is a warning and not a blocker. It is also two lines: add `"watchall": "jest --watchAll"` and
`"watcheq": "vitest --watch=true"` to an existing fixture manifest and assert both fire.

## Not blockers

- **`parcel` is the one runner-membership claim I could not verify at its source.** The other
  twelve are cited above. Parcel's v2 CLI source did not resolve at the paths I tried, so its
  exclusion rests on the build round's own reading plus the fixture's assertion. The direction
  makes this cheap: if `parcel` does define `-w` as watch, excluding it is under-firing (OR-1),
  not a false FAIL — the error class AC-5 ranks as the worse one is only reachable by a wrong
  *inclusion*, and every inclusion is verified.
- **`scope-completeness-reviewer` (confidence 92) flagged that GitHub issue #441's AC-5 text
  still reads "any `-w` flag" while the shipped predicate is an eight-runner allowlist.**
  Dismissed on the same grounds as round 2's equivalent: under the lean lane the **committed
  spec** is the definition of done, and that spec is amended in the same commit with the
  per-runner reasoning stated. Its verdict on the ACs themselves agrees with the table above.
  Worth noting the reviewer disclosed that the dispatch base it was handed (`5d0ae7e`) is an
  intra-branch commit and it re-classified against the real merge-base — correct behavior, and
  the reason its scope read is usable rather than an artifact of the delta range.
- **The spec amendment is narrowing-only, and its accuracy claim is now measured.** Diffed for
  removals: no prose was dropped, and round 2's W1 sentence ("nothing the original wording
  caught is lost") is replaced by the measured collateral (`rm -rf dist && tsc -w`,
  `tailwindcss … -w`), stated as under-firing under OR-1. AC-9's amendment **adds** a
  requirement the diff then meets — a strengthening, not a spec bent to match the code.
- **`lint-and-selftests` red at this head was the concurrent-sweep broken-pipe flake, and a
  re-run proved it.** The first run at `eb5f50f` failed one suite — `check-lean-chain-selftest.sh`,
  which this branch does not touch — on `printf: write error: Broken pipe` at its line 450,
  producing the tell-tale `expected rc=1 …, got rc=1` (the rc matched; the truncated message
  did not). Three pieces of evidence before re-running: the suite is green locally at this exact
  head, `main`'s own `ci` is green at `a885111` (the commit this branch merged), and the round-3
  build round hit the identical signature on a *different* untouched suite. I re-ran the failed
  jobs rather than reason about it: `lint-and-selftests` is now **green** at `eb5f50f`. Not this
  PR's debt.
- **`pr-gates` red is the designed pre-verdict state** — the `lean-chain` arm reading round 2's
  committed `verdict=needs-work`. `mutation-sweep-pr` and `selftests (macos, bash 3.2)` both
  pass at this head.
- Security, performance, maintainability, complexity and test-coverage all returned clean.
  Security's single suppressed item (fixture heredocs written into `mktemp`-scoped dirs,
  confidence 30) is below threshold and matches every sibling case in the same suite — agreed.

## Probes run

Each of the fourteen new assertions was mutated and scored on the full case label, with the
whole red list printed so a mis-keyed lookup could not read as a false survivor. The mutant was
applied by verbatim line replacement, `cmp`-checked as actually applied, `bash -n`-checked as
still parsing, and the file's exec bit restored on every path.

| Probe | Mutant | Reds | Verdict |
| --- | --- | --- | --- |
| P1 | restore the pre-fix allowlist (`jest`/`tsup`/`esbuild`/`parcel`/`karma`/`nodemon` back in) | exactly the five non-member cases | all five exclusions live |
| P2 | empty the `-w` allowlist | exactly the eight member cases, plus the pre-existing `tsc -w` case that asserts the same rule | all eight members live |
| P3 | drop `nodemon` from the token arm | the `nodemon -w` case and the pre-existing `nodemon` lanes case | the unreachability claim is live |

An early version of the probe scorer read only grep's exit status through a `pipefail`
pipeline and printed "SURVIVED" on a run that had reds; it was rewritten to count `✗` lines
from captured output before any verdict was drawn. Recording that because a scorer that can
print SURVIVED for the wrong reason invalidates every row above it.

## Verification at the merged head

`config-grill-selftest.sh` (53 cases), `doctor-selftest.sh`, `config-lint-selftest.sh`,
`check-lean-chain-selftest.sh` and `check-lockstep-pairs.sh` all green locally with
`env -u CLAUDE_CODE_SESSION_ID`. `shellcheck` clean. Live run against this repo's own committed
config re-verified the stated blast radius.
