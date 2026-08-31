# lean review verdict — #666

verdict=needs-work
run_id: review-666-2
session_id: f08d7e8f-d240-4b50-9037-465fe4b7ccbb
rounds: 2
pr: #735
reviewed_head: 79cedf63a9a8c6ee27b8e760a6c8349725f2506e
reviewed_patch_id: 349d207f7adcd3672262b69efb36bc03c4edb7a9
inherited_patch_id: 6ad651796fc56a6d2834e8d83626a0a0ed738b17
inherited_from_verdict: 1c158378b454d005afca487633bf554b6084ebf2
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2 read the delta `1c15837..79cedf6` (4 files) — `lean-gate delta` reported inheritance of
patch `6ad651796fc5` from round 1. Round 1's findings were read first; the whole branch
(`1d714d4..79cedf6`, 8 files) was read where the delta was misleading, which it was: the fix
commit edits one of two CLAUDE.md passages and one of two `install-topology-detail-selftest.sh`
regions, and only reading the unchanged halves shows what it missed.

Verdict: **needs-work** — 2 blockers and 1 major. Round 1's three blockers are all genuinely
closed, and the AC-3 amendment is sound. What fails is the same defect class round 1 named,
surviving in the two places the fix did not look: a sentence this PR authored still names a
trigger path the workflow no longer has, and a measured figure this PR ships does not
reproduce.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Unchanged by the delta; all five oracles re-run at `79cedf6`. File exists; no `schedule:`; `push:`/`pull_request:`/`workflow_dispatch:` all present; neither `install-topology:` nor `install-topology-bash32:` remains in `nightly-guards.yml`; `ruby -ryaml` parses `HEAD:.github/workflows/install-topology.yml`. Scope boundary holds — `nightly-guards.yml:30,33` still carries `schedule:` / `cron: '41 2 * * *'` with `wholesale-selftests` and `prose-budget` intact. |
| AC-2 | **satisfied** | Untouched by the delta (the fix's only workflow edits are the header comment and one deleted `paths:` entry), inherited from round 1 and re-checked: `file-issue-on-red` at `:107`, gated `always() && contains(needs.*.result, 'failure')` at `:109`; `gh issue list` (`:128`) precedes `gh issue create` (`:158`); `SHA: ${{ github.sha }}` (`:120`), `${SHA:0:12}` in body (`:144`) and title (`:159`). |
| AC-3 | **satisfied** | All four amended oracles pass at head: push-block family count → **2**; `marketplace.json` in the push block → **0** (`install-topology.yml:50-54` lists only the two families); `grep -c 'PATH FILTER'` → **1**. The header (`:29-41`) names both in-scope families *and* both deliberate exclusions. The amendment itself is faithful — see below. |
| AC-4 | **unsatisfied** | Both literal greps pass (`guard runs nightly` absent from both files; `install-topology.yml` present in both). The third, judgment bullet — the *current* contract description must be accurate — fails at `CLAUDE.md:102`. See **Blocker 1**. The paragraph that replaced the round-1 falsehood carries a measured claim that does not reproduce — see **Blocker 2**. |
| AC-5 | **satisfied** | `79cedf6` carries `Changelog: none.`; `ac59ff5` carries the branch's consumer-visible `Changelog:`. Trailers are extracted grep-anywhere, so the squash survives. |

## Round 1's three blockers

**Blocker 1 (AC-3, the false `marketplace.json` rationale) — CLOSED.** The fix took the second
remedy round 1 offered ("restate it … or drop the family"). The `- '.claude-plugin/marketplace.json'`
path entry is deleted, and the false sentence is replaced by an explicit exclusion note at
`install-topology.yml:36-41`. Round 1's underlying measurement re-verified at head:
`grep -c marketplace tools/install-topology-selftest.sh` → **0**, and the guard iterates the glob
directly at `tools/install-topology-selftest.sh:158`.

**The AC-3 amendment is faithful, not a spec bent to match the diff.** It implements a remedy the
round-1 record named in writing; the code moved with it in the same commit (this is not an oracle
relaxed around unchanged code); it is *tighter* than the form it replaces, adding a new
`marketplace.json` → 0 assertion that did not exist before; it is disclosed in the spec with its
provenance (`docs/plans/second-shift-666-lean.md:42-44`); and the adversarial table's counter-botch
row moved in lockstep (`:71`, "three-family" → "two-family"), so the anti-`plugins/**` guard is not
weakened. It also loses no coverage: adding a plugin necessarily adds a
`plugins/*/.claude-plugin/plugin.json`, and the release-time `metadata.version` bump rides the
release-PR trigger regardless of paths.

**Blocker 2 (AC-4, docs claimed the push trigger catches a suite regression) — CLOSED in substance.**
`CLAUDE.md:128-131` and `docs/testing.md:691-708` now state the two-halves trade honestly, and the
workflow header matches at `:17-21` and `:39-41`. The replacement text carries a figure that does
not survive re-derivation, which is **Blocker 2** below — a new finding against the new prose, not
a re-opening of the old one.

**Blocker 3 (AC-4, stale present-tense cadence in `docs/testing.md`) — CLOSED at all three sites
round 1 named.** `:158-160` now reads "its own event-triggered jobs … it ran nightly before #666";
`:604-606` re-dated; `:623-626` generalized to "a guard excluded from the PR lane". The class
survives one file over — see the **Major**.

## Blockers

### 1. AC-4 — `CLAUDE.md:102` still names `marketplace.json` as a filtered packaging path

```
CLAUDE.md:100-103
selftest jobs pass the same exclusion, and the guard runs in
`.github/workflows/install-topology.yml` on push to `main` when the diff touches packaging paths
(plugin manifests, `marketplace.json`, the guard script itself), on the release PR, and via
`workflow_dispatch` (#666 retired the nightly cron …
```

`.github/workflows/install-topology.yml:50-54` lists exactly two path entries; `marketplace.json`
is not one of them. **The sentence was true at `ac59ff5` and is false at `79cedf6`** — the fix
made it false and did not follow through. `git show 79cedf6 -- CLAUDE.md` has exactly one hunk, at
`@@ -126,8 +126,9 @@`: the *second* install-topology passage was rewritten, the first was not.

It now contradicts three artifacts the same commit wrote or preserved: the workflow header
(`install-topology.yml:36-41`, "deliberately NOT a family"), `docs/testing.md:674-677` (same), and
AC-3's own amended oracle asserting that family absent. This is precisely the harm round 1's
Blocker 1 articulated — a rationale a future reader consults before widening or narrowing the
filter, pointing at the wrong file — reproduced at a fourth sentence.

Fix: delete `` `marketplace.json`, `` from `CLAUDE.md:102`.

### 2. AC-4 — `docs/testing.md:701`'s "12 merges" does not reproduce; the window holds 6 commits total

```
docs/testing.md:700-702
… Between the `v12.1.0` and `v12.2.0`
releases (2026-08-26 → 2026-08-30, 4.25 days) 12 merges changed the guard's staged surface with
zero triggers firing; the retired cron ran 4 times in that same window.
```

Measured at head, `fae20ba..808aa29` (v12.1.0 → v12.2.0):

| reading | count |
| --- | --- |
| all commits in the window | **6** |
| first-parent merges touching `plugins/**` | **5** (one of which is the closing release merge) |
| all non-merge commits touching `plugins/` | **5** |
| date-window variant (`--since 08-26 10:39 --until 08-30 16:34`) | 7 |
| widest nearby window (`fae20ba..1d714d4`, past v12.2.0) | 14 |

The window contains **six commits in total**, so twelve is not merely unmeasured, it is
arithmetically impossible for the range the sentence names. No reading tried reproduces it.

**The figure's origin is round 1's own verdict record** (`second-shift-666-lean-verdict.md:96-98`),
which the build shipped verbatim into permanent documentation. I asserted that number; it is wrong,
and it became a build input nothing re-derived. Flagging that explicitly because it is the failure
mode, not just this line: a review record's asserted measurement is treated downstream as evidence.

Two further accuracy notes in the same sentence, to fix together:

- **`4.25 days` is `4.12`.** `fae20ba` is `2026-08-26 10:39:29 +0000`; `808aa29` is
  `2026-08-30 16:33:35 +0300` = `13:33:35 UTC`. That is 4d 2h 54m. The 4.25 figure comes from
  reading the `+0300` stamp as UTC (which yields 4.246). `CLAUDE.md` does not repeat the number,
  but `tools/install-topology-detail-selftest.sh` reasoning depends on the same magnitude.
- **`zero triggers firing` is TRUE** and should be kept: the only merge in `fae20ba..808aa29`
  matching the two-family filter is `808aa29`, the release merge closing the window.

**The rest of the paragraph's figures re-derive exactly** and should be left alone. Over the 40
first-parent merges ending at `1d714d4`: **23** touch `plugins/**`; **4** match the two-family
filter; **3 of those 4** are release merges (CHANGELOG-touching); the single non-release firing is
`f9eeb28` (#706), which changed the guard script. The cron's 4 runs in the window is also correct
(02:41 UTC on 08-27/28/29/30). Re-derived here against the **two-family** filter, not inherited
from round 1's three-family measurement — the counts happen to coincide because release merges
touch both `marketplace.json` and the plugin manifests.

## Major — must ride along, per the spec's own scope boundary

### `tools/install-topology-detail-selftest.sh:27-28` states the retired cadence as a standing fact

```
# WHY NOT INSIDE install-topology-selftest.sh ITSELF: that file stages and runs every shipped
# suite — ~5 to 10 minutes, nightly-only since #620. A guard for three lines of grep must not
# inherit that cost, or it runs a day late for a defect the PR lane could have caught.
```

Present tense, and "runs a day late" is the cron cadence specifically — under the new triggers the
lag is the release cadence, which this PR's own `docs/testing.md` paragraph measures in days, not a
day. The branch re-dated `:10-19` of *this very file* correctly and stopped seventeen lines short,
so one file now describes the guard both ways. `ci.yml` got the same ride-along treatment at both
its sites (`:99-100`, `:231-232`) and is correct.

`docs/plans/second-shift-666-lean.md:61-63` names this file explicitly as a ride-along consequence
of AC-4, so it is in scope for the ticket even though AC-4's literal oracle covers only two files.
Scored major rather than blocker: it is a rationale comment inside a suite header, not a contract
statement a reader acts on to change CI.

Suggested: `nightly-only since #620` → `excluded from the PR lane since #620 (nightly then;
event-triggered since #666)`, and `runs a day late` → `runs late — at the next release PR, not on
the branch that caused it`.

## Recorded, not blocking

- **`pr-gates` red at `79cedf6`** — `check-lean-chain.sh`, "lean chain reconciliation". The
  expected pre-approval state: it reds until a verdict record exists on the branch. Confirmed from
  the failing job's log, not assumed.
- **CI at `79cedf6`, cited not re-run** (run `33390572973`, head
  `79cedf63a9a8c6ee27b8e760a6c8349725f2506e`): `lint-and-selftests` **success** (4m52s),
  `selftests (macos, bash 3.2)` **success** (6m48s), `mutation-sweep-pr` **success** (16s).
  `release-pr-gates` skipped. No correctness lane contradicts an `AC-n`.
- **`install-topology` / `install-topology (macos, bash 3.2)` / `file-issue-on-red` all report
  `skipping`** at this head (run `33390572967`) — the non-release-PR `if:` guard behaving as
  designed, observed live for the second round running.
- **Design fidelity: `not-applicable`** — the spec carries no `## Design` section
  (`grep -c '^## Design'` → 0), so step 5b does not arm.
- Residual `nightly` mentions in `plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh:678,807`
  and `tools/install-topology-selftest.sh` are past-tense incident narrative about the seven
  consecutive reds. Historical and correct — AC-4's carve-out reaches them.
- `nightly-guards.yml:14-19` records the move as history with a pointer to the new file. Correct.

## Panel

Scoped deliberately rather than run whole. Round 1 dispatched the full panel on this branch and the
core five (security / performance / maintainability / complexity / test-coverage) returned
**zero findings each**; only scope-completeness fired, and it converged with 2 of 3 blockers. This
round's delta is four files of comments and prose plus one deleted YAML line — no code path
changed — so the core five have nothing to read that they returned nothing on last time. I ran
**scope-completeness** alone. It independently found Blocker 1 and contributed the Major; it
accepted the "12 merges" figure at face value, which is Blocker 2 and was caught by re-derivation
rather than by review.

## Strengths

- The fix chose deletion over a restated pretext. Dropping the family is the stronger of the two
  remedies round 1 offered, and it took the one that removes the claim rather than the one that
  rewords it.
- The new PATH FILTER block explains both *inclusions* and both *exclusions*, and says why the
  suite-content gap is deliberate rather than leaving a reader to infer it. The workflow header now
  routes to the docs for the honest trade instead of restating it in a third place that could drift.
- `docs/testing.md`'s replacement paragraph splits the trade into its two halves explicitly rather
  than averaging them into one comfortable sentence. That is the right shape; only one figure in it
  is wrong.
- The `if:`-gated release-PR routing continues to behave as designed, verified live at this head.

## Minimal path to green

Three prose edits, no code change: `CLAUDE.md:102`, `docs/testing.md:701` (the figure, the
`4.25`), and `tools/install-topology-detail-selftest.sh:27-28`. AC-3's amendment stands as
written; AC-1, AC-2, AC-3, AC-5 need nothing.
