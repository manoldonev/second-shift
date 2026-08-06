# lean review verdict — #393

verdict=approve
run_id: review-393-2
session_id: cf6129d1-41a2-444e-aa51-f83e4c67042b
rounds: 2
pr: #401
reviewed_head: 24148d73c502e244ac2cd0cb6c0b61fd46ac0403
reviewed_patch_id: 887a299cc66b7500919193c08df4b287ee7a3d55
inherited_patch_id: 3174bef65ff3c0e5d3f0d4cf713d2cf3f6db7166
inherited_from_verdict: d3d9ea47bc626748e059024de3745df86ab9a98c
model: unknown

# Review round 2 — PR #401 (issue #393), lean/second-shift-393

Range read: `d3d9ea4..HEAD` (commit `24148d7`), inheriting the coverage of patch
`3174bef65ff3` from round 1. Read wider than the range in two places, deliberately:

- **Commit messages across the whole branch.** Round 1's B2/B3 were trailer defects, and
  the fix for them is a message-only history rewrite — invisible in a tree-diff delta. The
  four pre-verdict commits were replayed with new messages (trees byte-identical, which is
  why the patch-id inheritance holds).
- **The inherited docs half.** The delta changed the rule `docs/onboarding.md` and the
  release-note trailer describe, so the inherited prose had to be re-read against the new
  behavior.

Spec of record: `docs/plans/second-shift-393-lean.md`. Pre-flight ledger
`.claude/pipeline-state/393-ledger.md` read as binding (D-1..D-11, OR-1..OR-3).

Verdict: **approve** — 0 blockers, 3 warnings.

## Round-1 findings — disposition

| # | Round-1 class | Status | Evidence |
| --- | --- | --- | --- |
| B1 | blocker | **fixed** | Predicate re-keyed to the configured values with Stage 1.T's own `contains` jq. Drove the shipped snippet against three synthetic pair configs, one branch at a time (below). |
| B2 | blocker | **fixed** | The trailer describing the ledger-rejected design is gone: `ba14c5f` now carries a bare `Changelog: none.` and says in its body *why* it is neutered, so the next reader does not "restore" it. |
| B3 | blocker | **fixed** | `0b977d0` likewise. Exactly one block now renders, and it describes what shipped. |
| W1 | warning | **fixed** | `# Revisit if a third site starts parsing either enum.` is back on the intake-receipt entry; the `ticketTag` entry ends with its own trigger only. |
| W2 | warning | **fixed** | OR-2's duplication is stated out loud in onboard Step 8's printed hand-off, with the "edit the FE repo's own copy" direction. |
| W3 | warning | **fixed** | The claim is now split per reject and is accurate — verified against `stages/1-intake.md:26-40`, which does support `TARGET_REPOS="be fe"` and fails closed only on empty. |

### B1 — verification

Ran the shipped snippet verbatim (`MATCHED` + `DECLARED`) against a fully-tagged, an
untagged and a half-tagged `be-fe-pair` config:

| config | title | `DECLARED` | `MATCHED` | branch taken |
| --- | --- | --- | --- | --- |
| be+fe tagged | `[BE] rotate the signing key` | 2 | `be` | exactly one → proceed |
| be+fe tagged | `[BE] [FE] end-to-end thing` | 2 | `be fe` | both → reject |
| be+fe tagged | `[BUG] session cookie expires early` | 2 | *(empty)* | neither → reject |
| be+fe tagged | `[BE] [urgent] rotate the signing key` | 2 | `be` | exactly one → proceed |
| neither tagged | `Fix session cookie expiry` | 0 | *(empty)* | under 2 → skip |
| be only | `Fix session cookie expiry` | 1 | *(empty)* | under 2 → skip |

All three round-1 failure modes are closed: the onboard-drafted (untagged) pair no longer
terminally rejects every ticket, `[BUG] …` now lands on the *neither* branch instead of
falling through to Step 2, and `[BE] [urgent] …` is no longer mis-rejected as cross-repo.
The half-tagged case — one config key beyond what round 1 reported — is covered by the same
`DECLARED < 2` threshold.

### B2/B3 — verification

Piped `git log 3eb0e53..HEAD --reverse --format='* %s%n%n%b'` through
`derive-release.sh`'s `extract_trailers` awk (`:117-121`) and then `render_bullet`'s `RS=""`
no-op awk (`:239-242`). Exactly one block renders now (round 1: two, both wrong), and it
describes the shipped design — host keeps its `be-fe-pair` config, sibling onboards
separately, pair-gated title check, cross-repo admission rule, `ticketTag` advisory under
the lean lane, no gate behavior changed, `Migration: none.` The verdict commit's own
`Changelog: none` normalizes to the no-op form and does not render.

## Spec amendment — judged legitimate

`24148d7` amends the spec's § Ratified contract and AC-2 in the same commit as the fix.
Scored explicitly rather than waved through, because an after-the-fact amendment that makes
a spec match its diff is itself a blocker:

- Every edit **adds** an obligation or **corrects** an inaccuracy. AC-2 now additionally
  requires the predicate to be the configured values with Stage 1.T's semantics, and
  requires the not-declared-on-both branch to be stated. Nothing was removed except the
  W3 phrasing, which was wrong on the facts.
- Both additions are traceable to inputs that predate the diff: round 1's stated B1 fix
  shape, and ledger D-6's own reasoning (a rule keyed on tags cannot fire where the config
  declares none — the reason the step is `be-fe-pair`-gated in the first place).
- The issue's own contract is not contradicted: #393 says "both tags, or neither, is a
  reject", which presupposes tags exist; the amendment fills a case the issue never reached.

## New findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `scripts/lockstep-manifest.tsv:377-393` + `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:194-198` | The `ticketTag` DROPPED entry's "three sites / revisit at a fourth" is stale on arrival, and the delta added a fourth site that *is* byte-anchorable. |
| W2 | warning | `plugins/second-shift/skills/onboard/SKILL.md` (whole file) | The title check is inert for every pair config `/second-shift:onboard` drafts, and nothing tells the operator the one edit that turns it on. |
| W3 | warning | `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:199` | `DECLARED` counts `ticketTag` across *all* `topology.repos` entries; the ratified predicate is "declared on **both** [pair] entries". |

### W1 — the register denies a coupling the same branch creates

The entry names three sites (`docs/config-schema.md`, the schema `description`,
`stages/1-intake.md`'s Stage 1.T) and closes with *"Revisit if a fourth site starts parsing
or restating `ticketTag`'s semantics."* This branch adds at least two more:

- `docs/onboarding.md`'s new § Pair repos restates the two-lane reading in full. (The
  ledger records that `docs/onboarding.md` carried zero `ticketTag` mentions before this
  diff, so it is new.)
- `intake-orchestrator/SKILL.md` Step 1.5 does not merely restate it — as of the delta it
  **parses** it, and with the same expression. Stripped of leading whitespace, the two
  predicate lines are one line:

  ```
  | select((.value.ticketTag // "") as $tag | $tag != "" and ($t | contains($tag)))
  ```

  present in both `stages/1-intake.md` and `intake-orchestrator/SKILL.md`, and nowhere else.

The entry's DROPPED reasoning — *"no single quoted literal is common to all three"* — was
true of the three sites it names and is false of the fourth. This repo already couples
markdown block to markdown block (`ac-id-rule`, `decomposition-economy`,
`artifact-reviewer-baseline-deltas`), so the mechanism exists; only the shared predicate
would go between the markers, since `verbatim` compares the whole block and the two
snippets differ in variable names (`TARGET_REPOS`/`MATCHED`, `$SECOND_SHIFT_CONFIG`/
`$CONFIG`).

Consequence if left: Stage 1.T's matching changes — anchored, trimmed, case-folded — CI
stays green, and the lean lane's intake check silently routes the same title differently
from the staged lane it was written to mirror. That is the drift class CLAUDE.md's tier map
sends to a lockstep row.

Scored a warning, not a blocker: AC-6's letter asks for a DROPPED entry recording the
three-site coupling and why no relation expresses it, and that entry exists in the right
shape with a verified behavioral-guard leg. The remedy is a row (or a corrected entry), not
a rewrite of what shipped. Same class as round 1's W3.

### W2 — the check never fires in the shape onboard emits

`grep -rn ticketTag plugins/second-shift/` returns **zero** hits: the confirmed-pair draft
emits `path` + `baseBranch` only. So `DECLARED` is 0 for every freshly onboarded pair, the
`DECLARED < 2` branch takes it, and AC-2's headline capability is unreachable until someone
hand-adds `ticketTag` to both entries. That inertness is correct — it is exactly what round
1 asked for, and rejecting instead is the failure D-6 gates out — but no surface in the diff
names the enabling edit. `docs/onboarding.md`'s new section and the rendered release-note
bullet both describe the reject without it. One clause in onboard's Step 8 print ("declare
`ticketTag` on both entries if you want intake to enforce the split") closes it.

AC-1 forbids changing the confirmed-pair draft itself, so emitting the tags is not the
remedy available here.

### W3 — the count spans the wrong set of entries

```
DECLARED=$(jq -r '[ .topology.repos[] | .ticketTag // "" | select(. != "") ] | length' "$CONFIG")
```

`config-lint.sh:73-74` requires a `be-fe-pair` config to *contain* `be` and `fe`; it does
not forbid a third entry, and `additionalProperties` in the schema permits one. Given a
tagged third entry alongside a tagged `be` and an untagged `fe`, `DECLARED` is 2, the check
fires, and every plain-titled FE ticket lands on the *neither* branch — the round-1 terminal
reject, reachable again through a config shape the linter admits. `MATCHED` spans the same
set, so a `[ADMIN]`-tagged title reads as "exactly one declared tag matched" and proceeds as
though it belonged to a side of the pair.

Nothing drafts a three-entry pair today, which is why this is a warning and not a blocker.
Restricting both expressions to the pair's two entries makes the code say what the spec
already says.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Step 8 item 7 carries all three required clauses unchanged from round 1 — (a) "This run's `be-fe-pair` config (drafted at Step 3) is unchanged and still covers both sides for the deprecated staged lane", (b) the `cd <sibling path>` + `/second-shift:onboard` direction with "Detection reports `standalone` from that side … with no further prompts", (c) "**FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo**, not from here." The confirmed-pair draft is still untouched; the delta only appends the OR-2 clause to the printed text. |
| AC-2 | **satisfied** | Both halves now hold. The title check resolves the configured values first (`MATCHED`/`DECLARED`), branches on how many of the *declared* tags matched, and states the not-declared-on-both case as skip-and-proceed — verified by driving the snippet across all six branches above. The cross-repo admission rule half was already complete and is unchanged: sibling identity from `topology.repos.<sibling-id>.path`, `needs-intake-review` on unresolvable rather than a guessed slug, BE-first default, the D-3 reconcile obligation beside the existing "queue when `<predecessor>` is closed" line, single-tag slice titles, `--repo <resolved-sibling>` at Step 6. |
| AC-3 | **satisfied** | Inherited from round 1, unchanged in the delta. `docs/config-schema.md:21-30` states both readings side by side and names Stage 1.T as unchanged; `docs/onboarding.md:51-73` adds the two-onboard section and the same two-reading paragraph; `docs/team-rollout.md:23-29` adds the second Day 0 and the FE-repo rule. The `#pair-repos-befe-under-the-lean-lane` anchor resolves. |
| AC-4 | **satisfied** | Both halves. One `Changelog:` block renders and it describes what shipped — confirmed by running the production extractor + renderer, not by reading the trailer. Re-ran the identity scrub over the full branch diff (consumer repo names, company tracker keys, org names, branch-prefix tokens): zero hits. |
| AC-5 | **satisfied** | Inherited. `schema/second-shift.config.schema.json`'s `ticketTag.description` carries the two-lane reading; `check-configversion-migration-doc.sh` reports unchanged (2), confirming D-9. |
| AC-6 | **satisfied (letter)** | The DROPPED entry is present, mirrors the intake-receipt entry's shape, and its behavioral-guard leg is real — `check-config-shadowing.sh:34` does pin `stages/1-intake.md` to `ticketTag`, and the gate runs clean from this checkout. Its "three sites, revisit at a fourth" reasoning is already overtaken by this same branch — W1, reported rather than scored against the AC's letter. W1's collateral damage to the neighbor entry is repaired. |

## Gates run from this checkout

`check-lockstep-pairs.sh` 16 pairs / 0 failed · `check-frozen-files.sh origin/main` clean ·
`check-changelog-trailer.sh origin/main` OK (presence only) ·
`check-configversion-migration-doc.sh` unchanged (2) · `check-config-shadowing.sh` clean ·
`jq empty` on the schema OK. No shell or `.mjs` file is in the branch diff, so the selftest
sweep is unaffected; both CI selftest lanes (incl. macOS bash 3.2) are green on `24148d7`.
`pr-gates` is red on the round-1 `verdict=needs-work` arm only — its authorship arm passes
and every other artifact arm is ✓.

## Open regions

OR-1 (`pause-and-ask`) remains untouched by the diff — correct, it belongs to #348. OR-2's
flag is now written into the hand-off print (round 1's W2). OR-3's flag lands as the D-3
body line in the Step 4 admission rule, as specified.
