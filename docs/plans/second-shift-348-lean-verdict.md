# lean review verdict — #348

verdict=approve
run_id: review-348-5
session_id: c4d7b1e3-5ac0-4545-a0ab-1ed6d24c0df7
rounds: 5
pr: #568
reviewed_head: bb08d4c958eb740097614511c6fe7d83d29b4ffa
reviewed_patch_id: 5dee498e23ef17db01dcd155915b84d55b470758
inherited_patch_id: 2402f48229b934a34c6fe8d6532f7ec435ff93b4
inherited_from_verdict: 9b406c8a14960e23af9af253563c382221e3d567
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 5 over the delta `9b406c8..HEAD` (1 commit, `bb08d4c`, 6 files, +26/−6), inheriting
rounds 1–4 by reference to the committed round-4 record. Read wider than the range wherever
the delta's own subject reached past it: all four orphan-check kinds whole-tree, every mutation
register cross-checked against the surviving tree, `doctor.sh`'s per-operator matched-site
sequences diffed base-vs-head, and the two factual claims the new `doctor.sh` comment makes
checked against `lean-gate.sh`.

**All three round-4 findings are closed, each verified against the code rather than the PR body.**

| Round-4 finding | Verified how |
| --- | --- |
| Blocker 1 — the kind-4 remedy satisfied namespaces rule 1 and violated rule 3(a) | `git grep 'dev-pipeline:'` over the four toolkit roots returns **0 hits** at this head (4 at `f59de2f`). `lint-and-selftests` is **green** at `bb08d4c`, `namespace direction check` included. The second half is paid too: the spec's kind-4 clause now carries the carve-out naming the four toolkit roots, the bare-lane remedy, and the generalization. I re-read `ci.yml`'s (a) grep — no exemption mechanism, and unlike (b) it carries no `--exclude-dir`, so the clause's root-scoped wording is the correct one. |
| Blocker 2 — two orphan `catalog::` baseline rows | Both dropped. Re-ran the check the round-4 record prescribed over **every** `catalog::` key in `tools/mutation-baseline.tsv` against `tools/mutation-catalog.tsv`: **0 orphans**. Extended it past the reported two to the whole AC-2 clause — see AC-2 below. |
| Nit 3 — the unredacted `state_excerpt()` tail | Comment landed, and its two load-bearing claims are true at this head, not just plausible: `lean-gate.sh:2979` does append `check-frozen-files.sh`'s captured `$out` verbatim as `milestone-2 \| advisory`, and `doctor.sh:104` does tell the reader to review before posting. It names the future-widening obligation, which is what the nit asked for. |

**The delta touches a guard whose mutants the PR lane defers, so this round owns its ordinals.**
`mutation-sweep-pr` is green at head with 50 verdicts computed, but `doctor.sh` is
`deferred-to-nightly` (0/0/0) — the nightly, not this lane, will grade it, so a silent re-key
would surface a day after merge. I diffed the matched-site sequence for all six operators in
`tools/mutation-operators.tsv` between `9b406c8` and `bb08d4c`: **byte-identical for every one**
(`fail-open` 0/0, `cmp-eq` 7, `cmp-z` 25, `logic` 59, `detector` 2, `default` 12). The added
block is comment lines matching no operator, so no ordinal moved and no re-baseline is owed.
`prose-budget.sh` — also nightly-only — is green at head with `doctor.sh` at 33.0% `ok`.

## Findings

**None.** No blocker, no warning, no nit.

**Triaged, and recorded so the disposition does not have to be re-derived.** The scope gate
returned PASS with three minor items; none is a finding, and each is settled by a different
thing:

1. **AC-3's issue-side pin literal** — correct, and *scheduled*: the committed spec (lines 19–23)
   and AC-3 both put the literal on the issue **at merge**, not in the diff. It is a merge
   precondition, recorded below, not a round.
2. **The manifesto P1/P2 pointer** — the **fourth consecutive round** this has been raised. The
   disposition lives at the committed spec's lines 19–23 and ledger D-9/D-18, and the round-4
   record states it in full. The gate scores against the issue body; the committed spec is the
   definition of done. Settled, not re-opened.
3. **`visualCapture` retired without a `configVersion` bump** — new this round, and I verified it
   independently rather than accepting the reviewer's own "accept as-is". `check-configversion-migration-doc.sh:37-40`
   passes on `OLD == NEW`, so it cannot enforce the pairing in this direction; `configVersion`'s
   `const` has been `2` since `78c975a` (v2.0.0) and was untouched by `36630a8`, the commit that
   removed three dead keys including `gates.costTracking`. The repo's actual precedent is
   no-bump-for-dead-key-removal, which is exactly what the spec's D-17 assessment declares and
   justifies. The issue's parenthetical mis-states the pattern it names; the spec is right and
   AC-7 is satisfied on it.

## Acceptance criteria

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** — sweep green, shellcheck/jq clean, orphan check (all four kinds) | **satisfied** | All named oracles green at `bb08d4c`: `lint-and-selftests` **success** (the round-4 red is gone — that job carries `run all selftests`, `shellcheck`, `validate JSON` and the namespace check), `selftests (macos, bash 3.2)` **success**, `mutation-sweep-pr` **success**. I re-ran all four orphan kinds whole-tree myself: kind 1 — 117 `skills/run/` hits across exactly the seven declared classes and no eighth; kind 2 — every `/dev-pipeline:run` hit in `CHANGELOG.md`, the migration/onboarding docs' past-tense removal notices, or the historical plan corpus; kind 3 — nothing in this delta moves a link; kind 4 — **no shipped artifact instructs the bare form**, every remaining hit being `plugins/dev-pipeline/…` path noise in `check-model-tiers.sh` or a doc describing the check itself. |
| **AC-2** — no register row names a deleted guard | **satisfied** | The clause verified in full, not just at the two reported rows. `catalog::` baseline keys vs `tools/mutation-catalog.tsv`: 0 orphans. Generic baseline rows vs the tree: every guard file resolves. `tools/mutation-catalog.tsv` guard column: every path resolves. `tools/mutation-exclusions.tsv`, `tools/mutation-pair-map.tsv`, `tools/mutation-slow-suites.tsv`, `scripts/lockstep-manifest.tsv`: every referenced path resolves. "Every re-keyed row lands in this same diff" holds because none needed re-keying — the `doctor.sh` sequence diff above proves it rather than asserting it. `tools/mutation-sweep.sh` runs clean on the PR lane with 50 real verdicts. |
| **AC-3** — keep list, demotion register, D-3 override, pin in the body | **satisfied** | Unchanged by this delta and re-confirmed rather than inherited: the PR body carries the keep/drop table with a per-scenario justification, the demotion register, the flagged D-3 override, and `Pin release: v5.2.2` with its re-confirm-at-merge caveat. `v5.2.2` is still the latest release (`gh api …/releases` → v5.2.2, v5.2.1, v5.2.0) and still the last commit on `main`, so the literal is not yet stale. The issue-side half is a declared merge precondition — see below. |
| **AC-4** — frozen-files green; breaking verb; `Changelog:` + `Migration:` | **satisfied** | Both guards green inside `lint-and-selftests` at head. PR **title** is `feat(dev-pipeline)!: delete stage choreography from main` — the load-bearing surface under squash merge. `74562a0`'s `Migration:` line names both the pin and the relocated `config-lint.sh` path. This delta's own commit carries `Changelog: none.`, correct for a review-response commit. |
| **AC-5** — `capability-parity-check.sh` green, coverage clause vacuous | **satisfied** | Re-run by me at this head: `note: …/skills/run/stages does not exist — the coverage clause is vacuous (expected once #348 has landed)` then `OK — 37 capability row(s)`. That note **is** the pass condition its LIFETIME note declares. |
| **AC-6** — every doc naming deleted machinery updated in the same diff | **satisfied** | The class is closed at every layer rounds 1–4 chased. This delta's three toolkit `SKILL.md` edits are the *wording* correction to documents round 4 already accepted as correctly updated, and the spec's own kind-4 clause is amended in the same commit — which is the AC's "in the same diff" requirement applied to the spec itself. |
| **AC-7** — `visualCapture` retirement follows the dead-key pattern | **satisfied** | Untouched by this delta, and the one live question about it settled above on the repo's own precedent (`36630a8`) rather than on the spec's assertion. |

## Merge preconditions

These are remedies **outside the tree**; neither is a round, and both are recorded here because
the committed record is the only place a merge boundary reads.

1. **Post `v5.2.2` on issue #348** — AC-3's issue-side half, scheduled at merge by the spec's own
   lines 19–23.
2. **Re-confirm the pin immediately before merging.** The literal must be the last release
   *preceding* this merge. If a `v5.2.3` lands first, `74562a0`'s `Migration:` trailer and the PR
   body line are stale for the ablation's staged arm and must be re-stamped — the PR body already
   states this and owns it.

One verification I could not complete: GitHub's GraphQL endpoint returned HTTP 503 throughout this
round, so `closingIssuesReferences` could not be queried. The body check that stands in for it is
positive — `Closes #348` sits unbackticked at the start of body line 10, which is the shape that
links.

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no design.provider is configured for this
repo, and the diff has no UI surface`. Re-verified at this head: `design` and
`stageParams.webComponentGlobs` are both `null` in the effective config, and this delta is
`.md`/`.sh`/`.tsv` only. The disarm is justified.

## Panel

Four reviewers selected, four returned — **no dark reviewer, no coverage gap**.
`maintainability`, `test-coverage` and `security` returned clean approves; `scope-completeness`
returned PASS with three minor items, all triaged above. Lineup reduced per the prior-round rule
to the two domains that carried round-4 blockers plus `security` (the nit's subject was a
redaction boundary) and the unconditional scope gate; `complexity`, `db`, `pipeline` and
`unit-test-mutation` were not triggered by a 26-line comment-and-prose delta. `a11y-reviewer` and
the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset ⇒ default `apps/web/**/*.{tsx,jsx}`). The scope gate
flagged, correctly, that its dispatch base was the round-scoped `9b406c8` and re-based itself on
the merge-base `33e6187` — the right call for a whole-issue scope question, and it is why its
three items address the branch rather than the delta.
