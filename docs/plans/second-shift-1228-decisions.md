# Decision record — #1228 `reviewers.default` is deprecated with removal promised at the next major, and v18 does not remove it

Receipt: v4

## Summary

The deprecated `reviewers.default` key leaves the schema. config-lint rejects it by name and points at a new dead-key-removal section in `docs/migrations/v2-to-v3.md`. `configVersion` stays 3. config-grill trigger 7 retires. Doctor names the key in its removed-key list. Every description of the key goes from the skills and docs.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | configVersion bump, and where the migration note lives | No bump. `configVersion` stays 3. The note is a `Dead-key removal` section in `docs/migrations/v2-to-v3.md`, and config-lint points there. `docs/migrations/README.md:6` and `docs/config-schema.md:21-22` are amended to state the rule: a key with no reader leaves the schema at a major, with no configVersion bump. The README's `v2-to-v3.md` index entry names the key. | user-answered | intent |
| D-2 | How config-lint rejects the key | Keep `default` in the reviewers allowlist (`config-lint.sh:255`) as message routing. Delete the type checks at `:261-262`. Add `err(has("default"); …)` naming the key, saying to delete it, and pointing at `docs/migrations/v2-to-v3.md`. It fires on any value, `[]` included. cited (convention): plugins/dev-pipeline/tools/config-lint.sh:86-89 | codebase-derived | fact |
| D-3 | config-lint fixtures and selftest | `valid-reviewers-default.json` cannot stay in the `valid-*.json` loop, so it becomes the rejected-by-name case (an `invalid-removed-*` fixture). The two `invalid-reviewers-default-*` fixtures and selftest lines `:82-87` retire. run: `grep -n 'valid-\*' plugins/dev-pipeline/tools/config-lint-selftest.sh` → `28:for f in "$FIX"/valid-*.json; do` | codebase-derived | fact |
| D-4 | Schema change | Delete `properties.reviewers.properties.default`. The block has `additionalProperties: false`, so the schema then rejects the key. run: `jq -c '.properties.reviewers.additionalProperties' schema/second-shift.config.schema.json` → `false` | codebase-derived | fact |
| D-5 | What review-lead says about the key | Nothing. Delete `:54` and the key clause at `:283`. The `review panel` row clause at `:283` stays. This overturns `docs/plans/second-shift-1219-decisions.md` D-10, which kept the "Do not read it" line. | user-answered | intent |
| D-6 | The fate of `docs/extending.md` §3.3b | Delete the section. Its second paragraph, on the retired `review panel` row, moves into §3.3. Nothing links to the §3.3b anchor. | user-answered | intent |
| D-7 | Where a consumer meets the rejection | Doctor's §7.1 removed-key list (`doctor.sh:465-485`) names the key: one FAIL, pointing at `docs/migrations/v2-to-v3.md`, with a doctor-selftest case. This covers a second-shift updated before dev-pipeline. Onboard meets it through config-lint. `run.sh` stays untouched. | user-answered | intent |
| D-8 | check-reviewer-references coverage of the key | Retire the `default-unknown` and `default-green` selftest cases, their two `consumer-default-*` fixture dirs, and the header comment at `check-reviewer-references.sh:38-39`. | user-answered | intent |
| D-9 | Other prose that describes the key | Drop the key from `plugins/second-shift/skills/onboard/SKILL.md:159`, `docs/onboarding.md:133` and the `reviewers` row of `docs/config-schema.md:11`. Each says the key is valid or reported by the grill. run: `git grep -l 'reviewers\.default' -- plugins/second-shift/skills/onboard/SKILL.md docs/onboarding.md` → both files | codebase-derived | fact |
| D-10 | Files that keep their mentions | `CHANGELOG.md` is derived at release and frozen. `verdict-check-fixtures/pr983-round{1,2}.md` are recorded review transcripts that a selftest reads. cited (convention): CLAUDE.md "Never edit release artifacts in a feature PR"; run: `grep -c 'pr983-round' plugins/dev-pipeline/tools/verdict-check-selftest.sh` → 2 | codebase-derived | fact |
| D-11 | Release metadata | The PR title carries `!` after its type and scope. So does the branch commit subject, because a single-commit squash takes the commit subject. The body has a column-zero `BREAKING CHANGE:` line and a `Changelog:` trailer with a `Migration:` line saying to delete the key. Without `!`, dev-pipeline derives only a minor. run: `bash scripts/derive-release.sh manifest \| jq -c '.plugins["dev-pipeline"]'` → `{"old":"17.13.1","new":"17.14.0","level":"minor"}` | codebase-derived | fact |
| D-12 | Sequencing against release PR #1211 | The bot regenerates release/next on every push to main. No hand re-derive is needed. Merging this before #1211 is the operator's merge order. run: `sed -n 1p .github/workflows/release-pr.yml` → `open/update the accumulating release PR from every push to main` | codebase-derived | fact |
| D-13 | config-grill trigger 7 | Delete the trigger-7 block in `config-grill.sh` and its cases in `config-grill-selftest.sh`. run: `grep -n 'trigger 7' plugins/second-shift/skills/onboard/tools/config-grill*.sh` → `config-grill.sh:231`, `config-grill-selftest.sh:299` | codebase-derived | fact |
| D-14 | Test-intent exemptions | AC-3 and AC-4 are exempt. Both are prose, and the repo bans prose-presence guards. | user-answered | intent |

Options weighed:
- D-1: no bump with a section in v2-to-v3.md, or a bump to configVersion 4 with v3-to-v4.md. The operator chose no bump.
- D-5: delete both mentions, or keep one "removed, ignore it" line. The operator chose delete.
- D-6: delete the section and move the panel paragraph, or a short REMOVED stub. The operator chose delete.
- D-7: doctor §7.1 entry, config-lint only, or doctor plus a run.sh refusal. The operator chose the doctor §7.1 entry.
- D-8: retire the cases, fixtures and comment, or keep the cases and fix the comment. The operator chose retire.
- D-14: exempt AC-3 and AC-4, or exempt AC-3 only. The operator chose both.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: config-lint rejects a config carrying `reviewers.default` with a message naming the key and `docs/migrations/v2-to-v3.md`, and prints no bare `reviewers: unknown keys`
AC-2: config-grill reports no trigger-7 finding for a config that sets `reviewers.default`
AC-3: exempt — prose in review-lead SKILL.md and the docs; the repo bans prose-presence guards
AC-4: exempt — the migration note is prose; the repo bans prose-presence guards

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | config-lint message for a config carrying the key | decided (D-2) |
| S-2 | Doctor output for a config carrying the key | decided (D-7) |
| S-3 | Onboard's config-lint loop on a carried key | decided (D-7) |
| S-4 | config-grill output in doctor and onboard | decided (D-13) |
| S-5 | Editor schema validation of the key | decided (D-4) |
| S-6 | The migration note a consumer reads | decided (D-1) |
| S-7 | `docs/extending.md` reviewer sections | decided (D-6) |
| S-8 | review-lead's effective-registry instructions | decided (D-5) |
| S-9 | Release notes "What breaks" entry | decided (D-11) |
| S-10 | A lane run on a config carrying the key | decided (D-7) |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written. spec-reviewer: one blocker on configVersion, and resolvable gaps. The interview resolved them.

Split: not triggered. The ticket has no epic label and one deliverable.

Explore: done. Read config-lint, config-grill, doctor, check-reviewer-references, review-lead, the migration docs and derive-release.

Fan-out: ran — 28 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: residue-census opus 4/6 · migration-contract fable 6/6 · lint-rejection-mechanics opus 6/6 · release-sequencing fable 6/6 · premortem fable 6/6
Tally: rows added 3 · snapshot claims overturned 0 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | residue-census | `onboard/SKILL.md:159` and `docs/onboarding.md:133` turn false and are not in the ACs | already-had | became D-9 |
| F-2 | residue-census | check-reviewer-references comment `:38-39` and two selftest cases keep testing the key (`selftest:122-137`) | already-had | became D-8 |
| F-3 | residue-census | The migrations README and the dead-key precedent disagree; AC-4 picks neither (`README.md:6-8`) | already-had | became D-1 |
| F-4 | residue-census | Doctor's own removed-key list omits the key (`doctor.sh:473-488`) | new | became D-7 |
| F-5 | migration-contract | The README contract implies configVersion 4 and `v3-to-v4.md` (`README.md:6-8`) | already-had | became D-1 |
| F-6 | migration-contract | The release gate keys only on configVersion, so a no-bump removal passes it (`check-configversion-migration-doc.sh:37-42`) | new | became D-1 |
| F-7 | migration-contract | Two `!` releases removed keys with no bump, in `v1-to-v2.md:104-108` | already-had | became D-1 |
| F-8 | migration-contract | The removal rule is written three ways that disagree (`config-schema.md:21-22`) | already-had | became D-1 |
| F-9 | migration-contract | A bump breaks every consumer config; the no-bump route touches the allowlist only (`config-lint.sh:91-95`) | already-had | became D-1 |
| F-10 | migration-contract | Open question: which migration route, and does the contract change (`README.md:6-8`) | already-had | became D-1 |
| F-11 | lint-rejection-mechanics | Retired keys get `err(has(...))` plus an allowlist entry (`config-lint.sh:86-89`) | already-had | became D-2 |
| F-12 | lint-rejection-mechanics | Today an array of strings passes config-lint (`config-lint.sh:261-262`) | not material | not material — current behavior that D-2 replaces |
| F-13 | lint-rejection-mechanics | Dropping the allowlist entry alone gives a bare `reviewers: unknown keys` (`config-lint.sh:255`) | already-had | became D-2 |
| F-14 | lint-rejection-mechanics | `valid-reviewers-default.json` reds the `valid-*.json` loop (`config-lint-selftest.sh:28`) | already-had | became D-3 |
| F-15 | lint-rejection-mechanics | Doctor FAILs and onboard loops on a lint violation; run.sh never lints (`doctor.sh:489-503`) | new | became D-7 |
| F-16 | lint-rejection-mechanics | Open question: should doctor §7.1 name the key (`doctor.sh:465-485`) | new | became D-7 |
| F-17 | release-sequencing | Plugin attribution comes from paths, not the title scope (`derive-release.sh:136`) | already-had | became D-11 |
| F-18 | release-sequencing | dev-pipeline derives minor today; only `!` makes it major (`derive-release.sh manifest`) | new | became D-11 |
| F-19 | release-sequencing | A single-commit squash takes the commit subject, so it needs `!` too (repo squash settings) | new | became D-11 |
| F-20 | release-sequencing | "What breaks" needs a `BREAKING CHANGE:` or `Migration:` line (`derive-release.sh:323-335`) | new | became D-11 |
| F-21 | release-sequencing | release/next regenerates on every push to main (`release-pr.yml:16-18`) | new | became D-12 |
| F-22 | release-sequencing | Open question: does the removal bump configVersion (`check-configversion-migration-doc.sh:29-46`) | already-had | became D-1 |
| F-23 | premortem | run.sh never runs config-lint, so lane runs still launch (`run.sh:289`) | already-had | became D-7 |
| F-24 | premortem | A partial upgrade leaves the key reported by nothing (`doctor.sh:465-467`) | new | became D-7 |
| F-25 | premortem | Bump or no bump is unstated; the gate passes either way (`README.md:6-8`) | already-had | became D-1 |
| F-26 | premortem | More files describe the key than the ACs list (`config-schema.md:11`) | already-had | became D-9 |
| F-27 | premortem | `!` alone makes no BREAKING changelog line (`derive-release.sh:245-246`) | new | became D-11 |
| F-28 | premortem | Deleting review-lead `:54` overturns 1219 D-10's kept line (`second-shift-1219-decisions.md:28`) | new | became D-5 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | S-1 | How config-lint rejects the key | The retired-key pattern (config-lint.sh:86-105): keep "default" in the reviewers allowlist (:255), replace the type checks (:261-262) with err(has("default"); "...removed... Delete the key (docs/migrations/...)") |
    | S-2 | configVersion bump | OPEN, operator: no bump (precedent: v1-to-v2.md dead-key removals #569/#574) vs bump to 4 (README contract; 76 files carry configVersion 3) |
    | S-3 | Where the migration note goes | follows S-2: no bump -> a "Dead-key removal" section in v2-to-v3.md; bump -> new v3-to-v4.md |
    | S-4 | What AC-3's config-schema.md:21 clause changes | follows S-2; README.md contract must agree with config-schema.md:21-22 |
    | S-5 | Fate of extending.md §3.3b | OPEN, operator: delete vs "removed" stub; the second paragraph (retired review-panel row) needs a home; nothing links to the anchor |
    | S-6 | Existing config-lint fixtures/selftest | valid-reviewers-default.json becomes the rejected-by-name case; the two invalid-type fixtures and their cases retire |
    | S-7 | check-reviewer-references comment :38 and default-unknown/default-green cases + fixtures | retire (the key no longer exists) |
    | S-8 | Other mentions outside the ACs | onboard/SKILL.md:159, docs/onboarding.md:133, docs/config-schema.md:11 lose the key |
    | S-9 | Leave alone | CHANGELOG.md, docs/plans/*-decisions.md, verdict-check-fixtures/pr983-round*.md |
    | S-10 | Release bump scope | derive-release.sh maps plugins from paths, not scope: every touched plugin bumps major; title takes !; Changelog trailer carries Migration: delete reviewers.default |
    | S-11 | run.sh behavior on a config with the key | run.sh does not run config-lint (only env-config-stale for v2 keys); doctor surfaces config-lint |

</details>
