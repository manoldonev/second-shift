# lean review verdict — #666

verdict=approve
run_id: review-666-4
session_id: 686fc2c8-a569-4218-92b5-33f4dd8d8315
rounds: 4
pr: #735
reviewed_head: 917e79ddef7d62fceed9c1d8ed9fa9226fb721f1
reviewed_patch_id: 426b1ba231fd67b8e57bd78bde40dc11d48ae07c
inherited_patch_id: 3d3aaa738ad5047368798d4d94ee4fb665474d32
inherited_from_verdict: 5c1c1fa6284edcf61261419fa887a251acd0ebf9
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 4 read the delta `5c1c1fa6..HEAD` (1 commit, `917e79dd`, 2 files — prose and one header
comment, zero code); `lean-gate delta` reported inheritance of patch `3d3aaa738ad5` from round 3.
Round 3's findings were read first. As in rounds 2 and 3, the delta was read but not trusted as
the boundary: every figure the fix touches was re-derived from `git`/`gh` rather than inherited —
including the ones round 3's own record certified — and the whole paragraph around each edit was
re-read for the class this branch keeps producing.

Verdict: **approve** — 0 blockers, 1 major, 2 minors. **Both round-3 findings are closed at the
site each named, and closed in the right direction.** Every `AC-n` is satisfied; every correctness
CI lane is green at this head.

The class did recur once more, three lines above the fix (`docs/testing.md:692`, the Major below).
It is not scored a blocker, and the reasoning is stated rather than assumed: round 3's blocker was
in the **current contract description**, which AC-4's third bullet makes an AC; this one is a
comparative to the **retired** regime, which that bullet's own parenthetical explicitly carves out
("historical/incident prose referring to the guard's past behavior is fine"). The guard's
going-forward behavior is now stated accurately at six independent sites. Recording it and
approving is the honest call here, not a softened blocker — see **On not spending a fifth round**.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Untouched by the delta; all five oracles re-run at `917e79dd`. File exists; no `schedule:`; `push:`/`pull_request:`/`workflow_dispatch:` all present; neither `install-topology:` nor `install-topology-bash32:` remains in `nightly-guards.yml`. YAML parses — note the spec's own oracle is fail-open on this machine (`YAML.unsafe_load` is undefined on the local Psych, and the `rescue YAML.load(STDIN.read)` arm re-reads an already-consumed STDIN, yielding `nil` and exit 0), so it was re-run in a form that aborts on `nil`: top keys `[true, "permissions", "jobs"]`, jobs `["install-topology", "install-topology-bash32", "file-issue-on-red"]`. Scope boundary re-verified: `nightly-guards.yml:30-33` still carries `schedule:` / `cron: '41 2 * * *'`, with `wholesale-selftests` (`:47`) and `prose-budget` (`:84`) intact. |
| AC-2 | **satisfied** | Untouched by the delta; re-checked at head. `file-issue-on-red` (`:107`) gated `always() && contains(needs.*.result, 'failure')` (`:109`); `gh issue list` (`:128`) precedes `gh issue create` (`:158`); `SHA: ${{ github.sha }}` (`:120`), `${SHA:0:12}` in body (`:144`) and title (`:159`); failing lanes (`:134-136`) and suite names (`:140`, `:148-155`) both named. |
| AC-3 | **satisfied** | Untouched by the delta; all four amended oracles re-run at head: push-block family count → **2**; `marketplace.json` in the push block → **0**; `grep -c 'PATH FILTER'` → **1**; the header (`:29-41`) names both in-scope families and both deliberate exclusions. |
| AC-4 | **satisfied** | Both literal greps pass (`guard runs nightly` absent from both files, rc 1; `install-topology.yml` present in both). Round 3's blocker site (`docs/testing.md:700-705`) is fixed and every figure in the replacement re-derives exactly — table below. The third, judgment bullet now holds: the *current* contract description is accurate at `docs/testing.md:158-160`, `:673-681`, `:691-696`, `:700-705`, `CLAUDE.md:99-106`, `:127-131`, `ci.yml:99-101`, `:231-237`, `nightly-guards.yml:14-19`. `grep -n 'nightly\|cron' CLAUDE.md` returns exactly one line, `:103`, explicitly retrospective. |
| AC-5 | **satisfied** | `917e79dd` carries `Changelog: none — doc/comment prose correction, no consumer-visible behavior change.`; `ac59ff5` carries the branch's consumer-visible `Changelog:`. Trailers extract grep-anywhere, so the squash survives. |

## Round 3's findings, re-checked

**Blocker 1 (`docs/testing.md:702`, "with zero push triggers firing") — CLOSED, and the
replacement re-derives claim by claim.** Measured at head, independently and again by
scope-completeness with its own commands:

| claim | command | result |
| --- | --- | --- |
| 5 first-parent merges touched the staged surface | per-commit `git show --name-only -m --first-parent $c -- 'plugins/**'` over `fae20baa..808aa295` | **5 of 6** (`3175cb7f` → 0) |
| 4 of them non-release, matching no push-filter family | same loop against `'plugins/*/.claude-plugin/plugin.json' 'tools/install-topology-selftest.sh'` | `6dd9f70`, `609a22c`, `d601689`, `8935157` → **all empty** |
| the fifth is the closing release merge, and its `plugin.json` bump matches the filter | `git show --format= 808aa295 -- 'plugins/*/.claude-plugin/plugin.json'` | `4.0.2→4.0.3`, `12.1.0→12.2.0` — **two real version bumps at filter-matching paths** |
| "redundantly with the release-PR trigger already covering it" | `gh pr view 698 --json headRefName,isCrossRepository` | `release/next`, `isCrossRepository: false` → satisfies `install-topology.yml:70-71`, so **both arms fire** |
| the retired cron ran 4 times in that window | 02:41 UTC on 08-27/28/29/30 within `08-26 10:39Z … 08-30 13:33Z`; corroborated against real `gh run list --event schedule` history | **4** |
| `4.12 days` | `2026-08-26 10:39:29 +0000` → `2026-08-30 16:33:35 +0300` | **4.1209** |

The fix is also the *stronger* statement, which is what round 3 asked for: it names the one firing
and says why it is redundant, rather than asserting a bare zero.

**Major (`tools/install-topology-detail-selftest.sh:29`, the wrong half of the trade) — CLOSED,
and in the correct direction.** The counterfactual now reads "at the next push to `main`". Verified:
the guarded `red-detail` block lives at `tools/install-topology-selftest.sh:255,283` — which *is*
push-filter family 2 (`install-topology.yml:54`) — so an edit to it fires the push arm at the next
merge to `main`, not at a release PR. The previous text overstated the lag; this does not. The
"runs late" comparison it rests on also holds: the detail suite runs on the PR lane today (both CI
selftest jobs exclude the exact path `tools/install-topology-selftest.sh`, not a glob, and nothing
excludes the detail suite), so PR-time-today vs next-push-in-the-counterfactual is genuinely later.

## Major — recorded, not blocking

### `docs/testing.md:692` — "same as before" asserts a cadence the branch's own measurements disprove

```
docs/testing.md:691-692
**The trade, stated plainly — and the two halves of it differ.** A manifest-version bump or a
change to the guard script itself is caught at the very next push to `main`, same as before.
```

The main clause is correct. The trailing comparative is not, under either historical regime:

- **Before #666** the guard ran on `nightly-guards.yml`'s 02:41 UTC cron and nothing else
  (`git show 1d714d48:.github/workflows/nightly-guards.yml` → `schedule:` at `:47`, `cron: '41 2 * * *'`
  at `:50`, no `push:`). A manifest bump merged at 10:00 UTC was caught ~16.7 h later, at the next
  firing — not at the next push. The scheduled-run history shows the clock re-reading one unchanged
  tree three nights running (`headSha 6dd9f705` on 08-28, 08-29, 08-30), which is the shape of a
  clock-bound trigger, not a push-bound one.
- **Before #620** it ran on the PR lane, i.e. *earlier* than the next push to `main`. Also not "same".

The sentence's next clause — "A change to a *shipped suite's own content* **is not**" — negates the
push-cadence predicate, which confirms that predicate is what "same" attaches to. So the reading
under which the clause is false is the natural one.

Fix (one clause): `… caught at the very next push to `main`, same as before.` → `… caught at the
very next push to `main` — sooner than the retired cron, which answered once a night.`

**Why this is not a blocker.** AC-4's third bullet is explicit: *"historical/incident prose
referring to the guard's past behavior is fine; the current contract description is not."* This
clause is a comparative about the retired regime; the current contract it sits beside is accurate,
as it is at every other site. The error is also in the safe direction — it *understates* the
improvement this PR delivers — so no reader is led to act wrongly. Round 3's blocker was the
opposite on both counts: it was the current-contract sentence, and it had no true reading.

## Minors — recorded, not blocking

- **`tools/install-topology-detail-selftest.sh:30` — "an edit here" has a false reading.** Under the
  intended reading ("an edit to that block / that file") the sentence is correct. Under "an edit in
  *this* file" it is false: `install-topology-detail-selftest.sh` matches neither push-filter family.
  That reading is live because the same header uses "here" to mean *this file* twelve lines below
  (`:35-36`, "is re-hosted **here** against fixture logs"). Fix: `so an edit to it is …`.
- **The `version`-vs-path minor round 3 recorded recurs, and still fails safe.** The new sentence
  says "whose own `plugin.json` version bump does match the push filter" (`:703`), alongside the
  pre-existing `:674-675`, `:691-692` and `CLAUDE.md:129`. The filter is path-based, so *any* edit
  to a manifest fires it — an extra run, never a missed one. Unchanged in kind from round 3's
  assessment; flagged again only so a later round does not re-discover it as new.

## Recorded, not findings

- **The `23 / 4 / 3` figure at `:697-699` is anchor-sensitive, and the prose does not pin the anchor.**
  Re-derived at three anchorings: **23**/4/3 at the branch's merge-base `1d714d48` (equivalently
  `--before=2026-08-31T00:00:00Z`, the reading round 3 used and the one that reproduces exactly);
  **22**/4/3 with a strict local-midnight pin; **25**/4/3 at today's `origin/main`. Watch out for
  the bare `--before=2026-08-31` form — git's approxidate fills in the current time-of-day, so it
  does *not* cut at midnight and leaves today's merges in the window. The two figures the argument
  actually rests on — **4** filter-matching merges, **3** of them releases — are invariant across
  all three anchorings, so the paragraph's conclusion is unaffected. Untouched by this delta and
  certified by round 3; recorded so a later round does not re-open it.
- **CI at `917e79dd`, cited not re-run** (run `33399005837`, head `917e79ddef7d`):
  `lint-and-selftests` **success**, `selftests (macos, bash 3.2)` **success**, `mutation-sweep-pr`
  **success**, `release-pr-gates` skipped. No correctness lane contradicts an `AC-n`.
- **`pr-gates` red at `917e79dd`** — step "lean chain reconciliation". Read from the failing log,
  not assumed: the only failures are `[lean-evidence] ✗ verdict record … reads 'verdict=needs-work',
  not 'verdict=approve'` and the `[lean-chain]` restatement of it, which further states that
  "freshness is undefined for a non-approve record, so the changed-files and patch-id/reviewed-head
  arms are not evaluated". That is the expected pre-approval state; nothing else is hiding behind it.
- **`install-topology` workflow run `33399005781` at this head: `skipped`** — the non-release-PR
  `if:` guard behaving as designed, observed live for the fourth round running.
- `bash tools/install-topology-detail-selftest.sh` run directly at this head: **20 passed, 0 failed**.
  The delta's edit to that file is comment-only and does not disturb the sentinel extraction.
- **Design fidelity: `not-applicable`** — the spec carries no `## Design` section
  (`grep -c '^## Design' docs/plans/second-shift-666-lean.md` → 0), so step 5b does not arm.
- **Residual-cadence sweep, widened past the delta.** Every branch-touched file was re-grepped for
  `nightly|cron|within a day|day late`. `docs/testing.md:158-160`, `:396-398`, `:486-492`, `:602-610`,
  `:326`, `nightly-guards.yml:1-25` and `ci.yml:198` are either past-tense incident narrative,
  correctly re-dated, or about a different guard (`check-sweep-bound.sh` / the wholesale sweep /
  the mutation nightly) that the scope boundary deliberately left on the cron. No live-contract
  contradiction outside the Major above.

## On not spending a fifth round

Stated plainly, because approving with a known-false clause in the tree deserves a reason and not
a shrug.

The ticket's subject — moving the guard off a clock onto event triggers — has been correct and
untouched since round 1. Rounds 2, 3 and 4 have all been prose. Three for three, a fix that
corrected one sentence introduced an error in the sentence beside it; two of those errors were
introduced by following a *review record's own* instruction. A fifth round has a poor prior on that
record, and it would cost a full build-and-review pair (measured at 58% of a run in `docs/lane-latency.md`)
to apply two one-clause edits that no `AC-n` requires and that mislead in the safe direction.

Both fixes are given verbatim above. A commit applying them now would change lines this record
hashes and void it, so the honest options are: land as-is and fold the two clauses into a follow-up,
or accept a fifth round deliberately. That is the operator's call, not something this round should
force by withholding an approval every acceptance criterion has earned.

## Panel

Scoped rather than run whole, on the same basis as rounds 2 and 3 and with their outcome as
evidence: round 1 dispatched the full panel and the core five (security / performance /
maintainability / complexity / test-coverage) returned **zero findings each**; this round's delta
changes no code path at all — one prose paragraph and one header comment. **scope-completeness** was
run alone. It re-derived every figure with its own commands rather than accepting the paragraph's or
round 3's, confirmed both fixes independently, and is the origin of the Major: it read three lines
above the fix and caught the cadence-equivalence claim, supplying the scheduled-run history
(`headSha 6dd9f705` three nights running) that makes it falsifiable rather than a matter of reading.
Both of its findings were re-verified here against the workflow files before being recorded.

## Strengths

- Both round-3 findings fixed at the exact sites named, with no collateral edit — the delta is 7
  added lines and 3 removed.
- The window sentence's replacement is the *stronger* claim, not the minimal one that would have
  passed: it names the single firing, identifies it as the release merge, and explains why that
  firing is redundant with a trigger already covering the same merge. Every one of those four
  sub-claims re-derives.
- The detail-selftest comment now agrees with `docs/testing.md:691-693` and `CLAUDE.md:127-131` on
  which half of the two-halves trade applies, which is exactly what round 3 said was inverted.
- The branch's six independent statements of the new trigger contract are now mutually consistent —
  a property none of the previous three heads had.
