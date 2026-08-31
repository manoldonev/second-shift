# lean review verdict — #666

verdict=needs-work
run_id: review-666-3
session_id: 7eb10966-8ea8-4b68-9b27-65b2b4646344
rounds: 3
pr: #735
reviewed_head: 0a2bc734ff61ca5c6f8d3a884c454c96562de046
reviewed_patch_id: 3d3aaa738ad5047368798d4d94ee4fb665474d32
inherited_patch_id: 349d207f7adcd3672262b69efb36bc03c4edb7a9
inherited_from_verdict: 69b750cfc2c5f985a2a6da3010e045fce02abfc7
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 3 read the delta `69b750c..HEAD` (1 commit, `0a2bc73`, 3 files — prose and comments only);
`lean-gate delta` reported inheritance of patch `349d207f7adc` from round 2. Round 2's findings
were read first. As in round 2, the delta was read but not trusted as the boundary: every claim
the fix touches was re-checked against the passages it did **not** touch, and every figure in the
paragraph it rewrote was re-derived from `git log` rather than inherited.

Verdict: **needs-work** — 1 blocker, 1 major. **All three round-2 findings are closed at the site
each named.** What fails is, for the third round running, the same class: the fix that corrected
one sentence introduced a new false claim in the sentence next to it, and picked the wrong half of
this PR's own two-halves trade in the comment it reworded. Both are one-clause edits.

I want to be explicit about provenance on the blocker: **the false clause is one my own round-2
record told the build to keep** ("`zero triggers firing` is TRUE and should be kept"). It was not
true then either. The build did exactly what the record said.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Untouched by the delta; all five oracles re-run at `0a2bc73`. File exists; no `schedule:`; `push:`/`pull_request:`/`workflow_dispatch:` present; neither `install-topology:` nor `install-topology-bash32:` remains in `nightly-guards.yml`; `ruby -ryaml` parses `HEAD:.github/workflows/install-topology.yml`. Scope boundary re-verified: `nightly-guards.yml:30-33` still carries `schedule:` / `cron: '41 2 * * *'`, `wholesale-selftests` and `prose-budget` intact. |
| AC-2 | **satisfied** | Untouched by the delta; re-checked at head. `file-issue-on-red` (`:107`) gated `always() && contains(needs.*.result, 'failure')` (`:109`); `gh issue list` (`:128`) precedes `gh issue create` (`:158`); `SHA: ${{ github.sha }}` (`:120`), `${SHA:0:12}` in body (`:144`) and title (`:159`). |
| AC-3 | **satisfied** | All four amended oracles re-run at head: push-block family count → **2**; `marketplace.json` in the push block → **0**; `grep -c 'PATH FILTER'` → **1**; the header (`:29-41`) names both in-scope families and both deliberate exclusions. The amendment's faithfulness was scored in round 2 and re-confirmed unchanged. |
| AC-4 | **unsatisfied** | Both literal greps pass at head (`guard runs nightly` absent from both files; `install-topology.yml` present in both). Round 2's Blocker 1 site is fixed — `CLAUDE.md:102` no longer names `marketplace.json`, and `grep -n marketplace CLAUDE.md` now returns only the frozen-files table (`:13`) and the repo tagline (`:3`). The third, judgment bullet — the *current* contract description must be accurate — fails at `docs/testing.md:701-703`. See **Blocker 1**. |
| AC-5 | **satisfied** | `0a2bc73` carries `Changelog: none.`; `ac59ff5` carries the branch's consumer-visible `Changelog:`. Trailers extract grep-anywhere, so the squash survives. |

## Round 2's findings, re-checked

**Blocker 1 (`CLAUDE.md:102`, the stale `marketplace.json` family) — CLOSED.** `` `marketplace.json`, ``
is deleted; `CLAUDE.md:101-102` now reads "(plugin manifests, the guard script itself)", matching
`install-topology.yml:52-54` exactly. The two CLAUDE.md install-topology passages (`:97-106` and
`:121-131`) now agree with each other, with the workflow header, and with `docs/testing.md:673-677`.

**Blocker 2 (`docs/testing.md:701`, the unreproducible figures) — CLOSED for the figures, and the
replacements re-derive exactly.** Measured at head:

| claim | command | result |
| --- | --- | --- |
| window is 6 commits | `git log --format=%H fae20ba..808aa29 \| wc -l` | **6** |
| 5 first-parent merges touch `plugins/**` | loop over `git log --first-parent fae20ba..808aa29` | **5** (`8935157`, `d601689`, `609a22c`, `6dd9f70`, `808aa29`) |
| one of them is the closing release merge | `808aa29 release: v12.2.0 (#698)` | **yes** |
| `4.12 days` | `2026-08-26 10:39:29 +0000` → `2026-08-30 16:33:35 +0300` = `13:33:35Z` | **4.1209** |
| cron ran 4× in the window | 02:41 UTC on 08-27/28/29/30 | **4** |

The 40-merge figures earlier in the same paragraph were re-derived too, at the base the sentence
dates itself to (`1d714d4`, "before 2026-08-31"): **23** touch `plugins/**`, **4** match the
two-family filter, **3 of those 4** are release merges. All three reproduce. (At today's
`origin/main` the sliding window reads 24/4/3 — the sentence's date pin is what keeps it correct,
and it should stay pinned.)

**Major (`tools/install-topology-detail-selftest.sh:27-28`) — CLOSED as to the retired cadence,
but the replacement names the wrong trigger.** "nightly-only since #620" → "excluded from the PR
lane since #620 (nightly then; event-triggered since #666)" is right. The second half is not — see
the **Major** below.

## Blocker

### 1. AC-4 — `docs/testing.md:702` "with zero push triggers firing" is false for the set the same sentence names

```
docs/testing.md:700-703
… Between the `v12.1.0` and `v12.2.0`
releases (2026-08-26 → 2026-08-30, 4.12 days) 5 first-parent merges touched the guard's staged
surface — one of them the closing release merge — with zero push triggers firing; the retired cron
ran 4 times in that same window.
```

Of those 5 merges, exactly one matches the push filter — and it is the release merge the clause
explicitly counts in:

```
$ git show --name-only --format= 808aa29
.claude-plugin/marketplace.json
CHANGELOG.md
docs/onboarding.md
plugins/design-toolkit/.claude-plugin/plugin.json
plugins/dev-pipeline/.claude-plugin/plugin.json
```

Two of those paths match `plugins/*/.claude-plugin/plugin.json` (`install-topology.yml:53`), on a
push to `main` (`:51`). The push arm fires. **One trigger, not zero.**

The round-2 text ("12 merges … with zero triggers firing") did not name the release merge as a
member, so the contradiction was latent. This fix added `— one of them the closing release merge —`,
which is the honest disclosure, and that is exactly what makes the trailing clause false: the
sentence now asserts that a set containing a filter-matching release merge produced no firings.

It also contradicts its own paragraph three lines up (`:698-700`): "4 that touched the push
filter's two families, 3 of those 4 being release merges themselves — so in practice the push arm
rarely fires outside a release". The paragraph's thesis is *release merges are what fire it*; the
window sentence then says a window containing a release merge fired nothing.

The correct statement is stronger than the one written, and is the point the paragraph is making:
the four interior merges touched the staged surface and would have triggered nothing; only the
closing release merge would have fired the push arm.

Fix (one clause): `… — one of them the closing release merge — with zero push triggers firing;` →
`… : the four interior merges matched no trigger at all, and only the closing release merge would
have fired the push arm;`

**Provenance, stated plainly.** This clause survived because round 2's record instructed the build
to keep it: "**`zero triggers firing` is TRUE** and should be kept: the only merge in
`fae20ba..808aa29` matching the two-family filter is `808aa29`, the release merge closing the
window." That reasoning names the counter-example and then draws the opposite conclusion from it.
The build was right to trust the record; the record was wrong. This is the second time on this
branch that a review-record assertion has become a defect the next round blocks on.

## Major — must ride along, per the spec's own scope boundary

### `tools/install-topology-detail-selftest.sh:28-29` names the release-PR half of a trade whose other half applies

```
# WHY NOT INSIDE install-topology-selftest.sh ITSELF: that file stages and runs every shipped
# suite — ~5 to 10 minutes, excluded from the PR lane since #620 (nightly then; event-triggered
# since #666). A guard for three lines of grep must not inherit that cost, or it runs late — at
# the next release PR, not on the branch that caused it.
```

The counterfactual is: *if this detail guard lived inside `install-topology-selftest.sh`, when
would it catch a drift?* The drift it guards is a change to the `red-detail` composition block —
which lives in `install-topology-selftest.sh` itself:

```
$ grep -n 'red-detail' tools/install-topology-selftest.sh
255:  # >>> red-detail
283:  # <<< red-detail
```

`tools/install-topology-selftest.sh` is the **second push-filter family**
(`install-topology.yml:54`). So a change to it is caught at the **very next push to `main`** — not
at the next release PR. This PR's own docs say so in as many words:

- `docs/testing.md:691-693`: "A manifest-version bump or a change to the guard script itself is
  caught at the very next push to `main`, same as before."
- `CLAUDE.md:129-131`: "a manifest-version or guard-script change is caught at the next push to
  `main`, but a shipped suite's own content is caught only at the next release PR".

The comment took the shipped-suite-content half of the trade and applied it to a file that is in
the filter. The pre-fix text ("runs a day late") was correct under the cron; the replacement is
incorrect under the new triggers, in the opposite direction — it *overstates* the lag.

**The branch measured the counter-example and did not connect it.** `docs/testing.md:698-699`
cites 4 filter-matching merges in the last 40, "3 of those 4 being release merges". The fourth —
the one non-release firing of the push arm in the whole sample — is:

```
$ git show --format= --name-only f9eeb28 -- 'plugins/*/.claude-plugin/plugin.json' 'tools/install-topology-selftest.sh'
tools/install-topology-selftest.sh
```

`f9eeb28` (#706) is an edit to this exact file firing the push arm outside a release. The comment
claims that class waits for a release PR; the paragraph two files over documents it not waiting.

The argument for the separate suite is untouched and still holds; only the named cadence is wrong.

Fix: `or it runs late — at the next release PR, not on the branch that caused it` → `or it runs
late — only after the merge, not on the branch that caused it`.

Scored major rather than blocker on the same basis round 2 used for this file: a rationale comment
inside a suite header, not a contract statement a reader acts on to change CI. `docs/testing.md`
and `CLAUDE.md` both state the trade correctly, so a reader who follows the comment's own pointer
lands on the right answer.

## Recorded, not blocking

- **`pr-gates` red at `0a2bc73`** — run `33394329267`, step "lean chain reconciliation". Read from
  the failing log, not assumed: the only failures are `[lean-evidence] ✗ verdict record … reads
  'verdict=needs-work', not 'verdict=approve'` and the `[lean-chain]` restatement of it. That is
  the expected pre-approval state; nothing else is hiding behind it.
- **CI at `0a2bc73`, cited not re-run** (run `33394329267`, head `0a2bc734ff61…`):
  `lint-and-selftests` **success**, `selftests (macos, bash 3.2)` **success**, `mutation-sweep-pr`
  **success**, `release-pr-gates` skipped. No correctness lane contradicts an `AC-n`.
- **`install-topology` workflow run `33394329269` at this head: `skipped`** — the non-release-PR
  `if:` guard behaving as designed, observed live for the third round running.
- `bash tools/install-topology-detail-selftest.sh` run directly at this head: **20 passed, 0
  failed**. The delta's edit to that file is comment-only and does not disturb it.
- **Design fidelity: `not-applicable`** — the spec carries no `## Design` section
  (`grep -c '^## Design' docs/plans/second-shift-666-lean.md` → 0), so step 5b does not arm.
- **Minor, deliberately not blocking.** Three branch-authored sites describe the push arm as
  firing on a manifest **`version`** change — `docs/testing.md:674-675`, `:691-692`, and
  `CLAUDE.md:129`. The filter is path-based (`paths: plugins/*/.claude-plugin/plugin.json`), so
  *any* edit to that file fires it, and CLAUDE.md's own frozen-files rule guarantees non-`version`
  edits exist ("Other plugin manifest fields (description, etc.) are freely editable"). Two real
  ones: `dc6021f` (#568) and `322ef75` (#523) both touch a `plugin.json` with zero `"version"`
  lines in the hunk. This fails **safe** — an extra run, never a missed one — it predates this
  round's delta, and `docs/testing.md:674` parenthesizes the real path immediately after. Left for
  a later pass rather than spent on this round; flagged so a future round does not re-discover it
  as new.
- Residual `nightly` mentions across the branch's files were re-swept
  (`grep -inE 'nightly|a day|day late|within a day'`): `docs/testing.md:605-606`, `:158-160`,
  `tools/install-topology-detail-selftest.sh:10-19`, `:91`, and `ci.yml:198` are either past-tense
  incident narrative or about a different guard (`check-sweep-bound.sh`, the wholesale sweep,
  the mutation nightly). `docs/testing.md:326` ("Runs in `nightly-guards.yml`'s ubuntu wholesale
  lane, and nowhere else") is `check-sweep-bound.sh` and is still correct — the scope boundary
  kept that job on the cron.

## Panel

Scoped rather than run whole, on the same basis as round 2 and with round 2's outcome as evidence:
round 1 dispatched the full panel on this branch and the core five (security / performance /
maintainability / complexity / test-coverage) returned **zero findings each**; round 2's narrower
delta changed no code path and this round's changes none either — three prose/comment hunks. I ran
**scope-completeness** alone. It converged independently on both findings, with the same two
one-clause fixes, and hardened each: it supplied the `f9eeb28` counter-example for the Major and
the two non-`version` manifest edits for the Minor. It re-derived every figure with its own
commands rather than accepting the paragraph's, which is the discipline round 2 found it lacking.

## Strengths

- Every one of round 2's three findings was fixed at the exact site named, and the two figure
  corrections re-derive exactly against `git log` — including the `4.12` day computation, which
  required getting the `+0300` timezone right.
- The fix chose to *disclose* that one of the five merges is the release merge rather than quietly
  excluding it to make the count support the sentence. That disclosure is what makes the remaining
  error visible at all; the shape is right even though the clause it sits beside is now wrong.
- The `CLAUDE.md` fix left the two install-topology passages mutually consistent, which is the
  specific failure round 2 caught. That class did not recur in `CLAUDE.md` this round.

## Minimal path to green

Two clause edits, no code change: `docs/testing.md:702` and
`tools/install-topology-detail-selftest.sh:29`. Both replacement strings are given verbatim above.
AC-1, AC-2, AC-3 and AC-5 need nothing; AC-3's amendment stands as written.
