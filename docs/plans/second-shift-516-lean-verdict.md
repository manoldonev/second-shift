# lean review verdict — #516

verdict=approve
run_id: review-516-2
session_id: d3911724-4ef4-47c6-bc4f-a63f2502589b
rounds: 2
pr: #523
reviewed_head: 6ecb07ef9805646a50d43a82a88a24110ab29176
reviewed_patch_id: d0aa14a7f15e5973a9e6ba62860fed3b80021564
inherited_patch_id: aad82870d64bba388c7bb06ff1b6c0eff2759376
inherited_from_verdict: 31b1ff59e6cc3199358156c1318777d6dcbc1d68
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #523 (issue #516)

Range reviewed: `31b1ff5..6ecb07e` (the fix delta since round 1's verdict commit),
inheriting the coverage of patch `aad82870d64b` and read against round 1's findings.
Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.
Verified independently: 33/33 suite green, shellcheck clean, and the round's new
assertions kill-probed in an isolated copy and scored by case id.

## Verdict: approve — 0 blockers

## Round 1 findings — disposition

**B-1 (blocker) — closed, and closed at the right rung.** `intake-orchestrator`
Step 6 now scans each synthesized slice in its unfiled `--title` / `--body-file`
form as item 4, *before* item 5's `issue create --label ready-for-dev`
(SKILL.md:468-491). Blocked successors are explicitly included, with the reason
stated — promotion at merge time is a bare operator label edit that runs no scan,
so creation is the only point a successor is ever looked at. The rc-2 hard-stop is
restated for this exit in its own vocabulary ("create nothing, label nothing"). The
sibling-slice exclusion is reasoned rather than assumed. Step 5.5 gains a pointer
paragraph so the parent scan no longer reads as the whole obligation. Checked the
generalization round 1 asked for: `--label ready-for-dev` is applied at exactly two
sites, both inside this Step-6 flow, and both are now downstream of the scan.

**W-1 — closed and probe-verified.** (ds-b2) covers `--issue` with `--body-file`.
Measured: deleting the guard at `dup-scan.sh:127-130` flips (ds-b2) PASS→FAIL with
`cases-seen=33` on both runs, so the case is live rather than decorative.

**W-2 — closed.** The header now cites (ds-k)/(ds-l); confirmed those are the
calibration pair (real duplicate surfaced / nearest non-duplicate held below), and
(ds-i)/(ds-j) are the non-array and unparseable-config cases round 1 named.

**S-3 — addressed.** `scripts/lockstep-manifest.tsv` gains a DROPPED annotation for
the 0/10/2 taxonomy (28 → 29), in the established comment form, and AC-10 is
corrected to match rather than left asserting the line that did not survive contact.
The annotation's "four SKILL blocks" count is accurate — four invocation sites.

## Warnings

**W-3 — the per-slice scan scores each slice against its own parent, which is still
queue-labeled at that moment.** Step 6 item 4 runs before item 6 strips
`ready-for-dev` from the parent, so the parent is in the corpus for every slice
scan. The item's own reasoning covers the sibling slices ("scoring them against one
another would report the split itself as a duplicate") and that reasoning applies to
the parent at least as strongly — a slice is a part of its parent by construction —
but the parent is the one corpus member the exclusion does not reach: siblings are
excluded automatically by being unfiled, while the parent is filed and labeled.

Measured against real decompositions in this repo, scoring each child as the unfiled
draft subject the new step scans, against a corpus holding its own parent:

| Epic | Children at/above `THRESHOLD=12` | Range |
| --- | --- | --- |
| #213 | 5 of 5 | 16–83 |
| #290 | 2 of 4 | 6–14 |
| #525 | 0 of 8 | 4–11 |

7 of 17 pairs trip the threshold, the strongest at 83. Consequences are bounded —
rc is `10`, not `2`, so nothing hard-stops and no label goes wrong — but two costs
land. AC-8 makes each of those a Decision Ledger row, so a decomposition pads its
register with rows recording that a slice is not a duplicate of its own epic, which
is the shape AC-8's second sentence exists to prevent. And the JUDGE block's "the
same work → do not queue this one; fold it into the candidate" is the reading an
83-scoring parent invites, on a route whose whole purpose is to create those slices.
The step gives the reader no instruction to expect the parent among the candidates.

Not a blocker: no AC is unmet, the invariant AC-7 asserts holds, and the output is
noisier than designed rather than wrong. The remedy is small either way — exclude
the parent from the corpus for the per-slice scan (the tool self-excludes only on
`--issue`, so this needs a flag), or tell the reader at this exit that the parent is
expected and is never the answer.

## Suggestions

- **S-1 / S-2 carried forward, unaddressed and still correct.** The `-ss`
  de-pluralization exception (`dup-scan.sh:218`) and the `sort … -k2,2n` tie-break
  direction (`dup-scan.sh:339`) remain unexercised. Both were suggestions in round 1
  and neither was escalated here.
- **S-4** — the fixture normalization is sound and was re-measured, not taken on
  the spec's word: reverting #166's title to the literal `dev-pipeline:` colon in an
  isolated copy leaves the suite's full output byte-identical, so the change is
  provably score-neutral and the spec's note is accurate. Worth keeping the spec
  paragraph exactly where it is — it is the only thing standing between a future
  re-capture and a red CI nobody would connect to a title.

## Dismissed

- **Stale `(Step 4, pair topology)` ordinal after the renumbering**
  (maintainability, confidence 90) — false positive, checked directly. That
  back-reference names the **top-level** `### Step 4: Make Decomposition Decision`,
  where the cross-repo admission rule is actually defined, not the renumbered
  sub-item. The file's convention throughout is that "Step N" is a top-level
  heading — the same block cites "(Step 1.5)" the same way. Swept the rest of the
  renumbering for genuine stale references and found none; "step 2 above" under
  Brief persistence still resolves to item 2, which did not move.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited. The "before a new one is labeled" clause now holds at the decomposition exit too, which is what round 1 charged to AC-7. |
| AC-2 | satisfied | Inherited; no write path added in this delta. |
| AC-3 | satisfied | Inherited. |
| AC-4 | satisfied | Inherited; the taxonomy is unchanged in this delta and the tool-side rc+message assertions still pin it. |
| AC-5 | satisfied | Inherited. |
| AC-6 | satisfied | Inherited. |
| AC-7 | **satisfied** | The invariant is now keyed to the item that carries the label. Each slice is scanned pre-creation, blocked successors included, under the same rc-2 hard-stop; both `--label ready-for-dev` sites are downstream of it. The spec amendment adds this clause and removes nothing — not a retrofit. |
| AC-8 | satisfied | The per-slice exit restates the one-row-per-judged-candidate obligation. See W-3 for what that costs on this route. |
| AC-9 | satisfied | 33/33 against the `PATH`-stubbed tracker; the round's new case probe-verified live. |
| AC-10 | satisfied | Manifest description carries `dup-scan`; the DROPPED annotation lands in the established form; `plugin.json` `version` unchanged at 2.3.3 against the merge-base. |

Design fidelity: `not-applicable` — the spec declares no `## Design` section and the
repo configures no design provider. a11y and the design-fidelity dimension were not
routed: no changed path matched `stageParams.webComponentGlobs`
(`apps/web/**/*.{tsx,jsx}`).

CI on the reviewed head: `lint-and-selftests`, `mutation-sweep-pr` and
`selftests (macos, bash 3.2)` all green; `pr-gates` red solely on this record's
absence, which this record resolves.

## Strengths

- The fix is wired where the label is minted, not where the exit was pointed — and
  it says so in the SKILL text, so the next reader inherits the distinction rather
  than the conclusion.
- The blocked-successor case is handled with its reason attached: promotion is an
  operator label edit that runs no scan, so creation is the last chance. That is the
  half a narrower fix would have missed.
- The fixture normalization is defended by measurement (byte-identical suite output)
  rather than by argument, and the spec records it so a re-capture re-applies it
  instead of re-reding CI.
- S-3 was answered by doing the work and then correcting the AC that had claimed it
  was unnecessary, rather than by leaving the claim standing.
