# lean review verdict — #753

verdict=approve
run_id: review-753-1
session_id: 2794f9d0-b7e7-4ed5-90b9-f76af513d1dc
rounds: 1
pr: #776
reviewed_head: ae1349fca4949199f685b1dc45a709e3917ed562
reviewed_patch_id: 11e15f5160893ca212e0f3c5a8a2a10d25991a42
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:complexity-reviewer,review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 1 (root). Range read: the whole branch diff, `18c1f8c9..HEAD` — 3 files, +27/-3.
Nothing inherited; no prior record exists for this issue.

The ratified spec (`docs/plans/second-shift-753-lean.md`, re-cut at
issue #753 comment 5506836099) narrows the ticket to a prose deletion plus a
triage-record reconciliation. The dropped design — the amendment gate, the
zero-deletion proxy, the override carve-out — is confirmed absent from the diff.

## AC scorecard

| AC-n | score | evidence |
| ---- | ----- | -------- |
| AC-1 | satisfied | `plugins/dev-pipeline/skills/review-lean/SKILL.md:168` — the second clause is deleted and the bullet stands as a complete directive. The negative half is verified against the whole change set, not asserted: the diff is exactly 3 files, so no selftest arm, no `tools/`+`scripts/` change, no `lean-gate.sh`/`lean-evidence.sh` change, no override-enum widening was added in its place. Census corroborates the deletion is total and creates no successor: base 18c1f8c9 to head, stop 30 to 29, bold 91 to 90, all 362 to 361 — exactly one construct leaves at every tier, and the surviving bullet re-keys into no tier (`census --tier all` matches it 0 times). |
| AC-2 | divergent-inert | Reconciliation and the census arms are met: the row is `deleted` + `prose-deleted` with enforcer `-`, and `bash tools/prose-blockers.sh check` exits 0 with zero undispositioned, no UNPRUNED and no STALE. Both arms are live, not vacuous — the UNPRUNED arm scores this row against a census that really dropped from 30 to 29. The `sites` conjunct diverges. measured: the AC's regeneration oracle is the census, which emits one line anchor per site (`tools/prose-blockers.sh:296`, `$1 ":" $2`) and at the base commit prints `plugins/dev-pipeline/skills/review-lean/SKILL.md:168`; the committed cell is `:168-169`, a range census cannot produce, and the record's own committed column contract (`docs/prose-blocker-triage.tsv:14`) declares the format as "comma-joined path:line, regenerated from the census command". It is the only range-form cell among 52 rows. Inert because nothing reads the column: `check()` uses `$1`, `$2`, `$3`, `$5` and `NF` only — `$4` appears in no arm — and the row is now a tombstone over a construct absent from the tree at every tier, so it will never be re-censused. follow-up: #776 review comment names the one-token repair (`:168-169` to `:168`). |

## Findings

**Blockers: none.**

### Major 1 — the branch's `Changelog:` trailer renders into CHANGELOG.md and the Release notes

Commit `ae1349fc` writes `Changelog: none — deletes dead prose and reconciles a triage
record; no` with a two-space-indented continuation line. That is not the opt-out form.
`scripts/derive-release.sh` folds indented continuations into the trailer block
(`extract_trailers`, `:115-121`) and its no-op test compares the WHOLE block to `none`
after stripping one trailing period (`:240-243`), so the block does not match and renders.

Measured, not inferred — the two awk programs were extracted and run over the real squash
body (`git log --reverse --format=%B 18c1f8c9..HEAD`; the repo's
`squash_merge_commit_message` is `COMMIT_MESSAGES`, so both commit bodies concatenate):

```
[RENDERED]   none — deletes dead prose and reconciles a triage record; no
[RENDERED]   consumer-visible behavior change.
```

Control arm, same body with the trailer rewritten to a bare `Changelog: none`: 0 rendered
lines. So the probe is live. `ae1349fc` leaks; `a59ebdd3`'s bare `Changelog: none.` is clean.

`scripts/check-changelog-trailer.sh` is presence-only and passes (verified, rc 0), so CI
will not catch this.

**Not a blocker, deliberately.** This is the policy class the skill's "a merge-boundary
refusal is not a review round" rule covers: no AC governs the trailer, the branch diff is
clean, and the repair is free at the merge boundary — the squash body is authored in the
merge dialog, so deleting the two lines there costs nothing and needs no history rewrite.
Refusing here would buy when it is fixed, not whether, at the price of a build-and-review
pair.

**Repair at merge:** in the squash dialog, replace the leaking trailer with a bare
`Changelog: none` on its own line (narrative above it, unindented).

### Major 2 — the reconciled `sites` cell is hand-formed, not regenerated

Scored on AC-2 above. `:168-169` where the census produces `:168`, against a column the
file itself documents as regenerated from that command. Zero mechanical consequence — no
consumer parses column 4 — but it is the only row in the record not in census form, and
"regenerated from the census command" is the property the record's value rests on.

**Repair:** one token, `docs/prose-blocker-triage.tsv:51`, `:168-169` to `:168`.

### Minor — the surviving bullet is the only bodyless bold headline in the list

`plugins/dev-pipeline/skills/review-lean/SKILL.md:168` is now the sole terminal
`- **...**` bullet with no elaborating clause in "Rules that are not negotiable"; every
sibling pairs its headline with a body. It reads as a complete, actionable imperative and
the deleted clause was a corollary, not a definition it depends on — so this is house-style
discord, not a comprehension gap. No change requested.

## Verified clean

- No cross-reference to the deleted sentence survives: `amended`, `after the fact`,
  `spec's promises`, `Approve on the diff` grepped across `plugins/` and `docs/` — the only
  hits are unrelated senses. `build-lean/SKILL.md` and `lean-gate.sh` reference neither the
  clause nor its language.
- AC-1's premise holds: the enforcer `pb-dd909897` names is real and load-bearing —
  `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` `ac_scorecard_violations` and
  the `scorecard` subcommand, called at verdict-write validation.
- Both spec AC line citations are accurate against the base commit.
- No frozen release artifact touched: `scripts/check-frozen-files.sh` rc 0 — no
  `plugin.json` version, no `CHANGELOG.md`, no `marketplace.json` metadata.version.
- No scope overshoot against the ratified narrowing.
- Correctness lanes at this head are green: `lint-and-selftests` pass, `mutation-sweep-pr`
  pass. `pr-gates` is red on the absent verdict record, which is the expected pre-approve
  state of the lean chain, not a finding.

## Design fidelity

Not applicable. The spec declares `Design: none` and the disarm is justified: this repo's
`.claude/second-shift.config.json` configures no `design.provider` (verified), and the
change touches only skill prose and a triage record. No RS rows are declared and none are
owed.

## Panel

`review-toolkit:complexity-reviewer` (prose coherence, dead cross-references, enforcer
reality) and `review-toolkit:scope-completeness-reviewer` (per-AC scoring against the
ratified spec). Both returned usable results; neither went dark. Both independently
reproduced the `sites` divergence and the changelog-trailer leak reported above.
