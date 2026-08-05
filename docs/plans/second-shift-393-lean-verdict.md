# lean review verdict — #393

verdict=needs-work
run_id: review-393-1
session_id: 578f459c-9302-426e-861d-e97fc96cd3f3
rounds: 1
pr: #401
reviewed_head: 3e68c55619513111290743b62408f0d81e8b375c
reviewed_patch_id: 3174bef65ff3c0e5d3f0d4cf713d2cf3f6db7166
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

# Review round 1 — PR #401 (issue #393), lean/second-shift-393

Range read: `3eb0e53..HEAD` (full branch diff — chain root, nothing verifiable to inherit).
Spec of record: `docs/plans/second-shift-393-lean.md`. Pre-flight ledger
`.claude/pipeline-state/393-ledger.md` read as binding (D-1..D-11, OR-1..OR-3).

Verdict: **needs-work** — 3 blockers, 3 warnings.

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:189-204` | The Step 1.5 title check keys on **bracket shape**, not on the configured `ticketTag` values. Three failure modes follow. |
| B2 | blocker | commit `476b96c` `Changelog:` trailer | The only trailer that renders describes the design D-1 **rejected**; it ships verbatim into the release notes. |
| B3 | blocker | commit `3e68c55` `Changelog:` trailer | `Changelog: none — corrects an in-progress diff …` is not the no-op form, so it renders as a consumer-facing release-note bullet about an internal in-progress correction. |
| W1 | warning | `scripts/lockstep-manifest.tsv:376-394` | The new DROPPED block was inserted **above** the intake-receipt entry's closing line, stealing it. |
| W2 | warning | `plugins/second-shift/skills/onboard/SKILL.md:290-300` | OR-2's flag — the duplicated FE command table — is never said out loud in the hand-off step. |
| W3 | warning | `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:211-214` | "structural improvement on the staged lane's `targetRepos-ambiguous` failure" is true of only one of the two rejects. |

### B1 — the title check's predicate is bracket shape, not the configured tags

`**The check.** Scan the issue title for bracket-shaped tags (`\[[A-Za-z0-9_-]+\]`)` — then
three bullets keyed on *how many bracket tokens* the title has. The ratified contract (spec
§ Ratified contract, AC-2) is keyed on the two **configured `ticketTag` values**. The staged
lane's Stage 1.T does it correctly, in this same file family: `select((.value.ticketTag //
"") as $tag | $tag != "" and ($t | contains($tag)))` — it matches the configured values and
ignores everything else in the title. Three consequences:

1. **Every plain-titled ticket in an onboard-drafted pair repo is terminally rejected.**
   `ticketTag` is optional in the schema
   (`.properties.topology.properties.repos.additionalProperties.required == ["path","baseBranch"]`),
   `config-lint.sh:70` only rejects *unknown* keys, and
   `plugins/second-shift/skills/onboard/SKILL.md` contains **zero** `ticketTag` mentions —
   its confirmed-pair draft (`SKILL.md:59`) emits `be`+`fe` entries with `path` and
   `baseBranch` only. So the config the shipped onboard skill emits for a pair carries no
   tags at all. Title `Fix session cookie expiry` → no bracket token → bullet 3 → terminal
   `needs-spec-work`. That is every ticket in that repo. D-6 reasoned exactly this way for
   `standalone`/`monorepo` and stopped one step short of the pair itself.
2. **The contract's "neither" case has no branch when the title carries one non-pair tag.**
   Title `[BUG] session cookie expires early`, config tags `[BE]`/`[FE]`: bullet 1 needs a
   match (no), bullet 2 needs ≥2 distinct tags (no), bullet 3 needs *no recognizable tag at
   all* (there is one). Nothing applies — the step falls through to Step 2 and the ticket
   enters spec review naming neither side of the pair, which is the ambiguity AC-2 makes
   terminal.
3. **A correctly-tagged ticket with any second bracket token is mis-rejected.** Title
   `[BE] [urgent] rotate the signing key` → "two or more distinct tags" → rejected with a
   comment saying "a pair ticket is never worked as one artifact", which is false for that
   ticket.

Fix shape: match against `topology.repos.<id>.ticketTag` values (Stage 1.T's `contains`
semantics), branch on *how many of the configured tags* the title carries — 1 → proceed
(wrong-side → routing-mistake stop), 2 → cross-repo reject, 0 → "neither" reject — and say
what happens when the pair config declares no `ticketTag` at all (skip, or escalate; do not
reject).

The Step 4 cross-repo admission rule itself is correct and complete: sibling identity
resolved from `topology.repos.<sibling-id>.path`, `needs-intake-review` escalation on
unresolvable rather than a guessed slug, BE-first default, the D-3 reconcile obligation as a
body line beside the existing "queue when `<predecessor>` is closed" note, single-tag slice
titles, and the Step 6 `--repo <resolved-sibling>` note. No finding there.

### B2 — the rendering `Changelog:` trailer describes the design the ledger rejected

`476b96c` trailer: *"…the lean lane's BE/FE pair model — **per-repo standalone onboards
instead of a combined be-fe-pair config**…"*. `3e68c55` then reversed exactly that: *"The
prior commit drafted onboard as if a confirmed pair should onboard THIS repo standalone-only.
The pre-flight ledger's D-1 settled it the other way: the host's existing be-fe-pair config
is unchanged."* What shipped is host-keeps-its-pair-config **plus** an additional sibling
onboard. `3e68c55`'s own trailer asserts "the net consumer-visible change is unchanged from
the previous commit's trailer" — it is not.

Trailers are extracted grep-anywhere and survive the squash (CLAUDE.md;
`scripts/derive-release.sh:29-35`), and `check-changelog-trailer.sh` asserts *presence* only
— it passes here. Ran the production extractor + renderer over the branch
(`derive-release.sh:117-121` then `:239-242`) against the squash body:

```
  onboard, intake-orchestrator, and the onboarding/config-schema/team-rollout
  docs now document the lean lane's BE/FE pair model — per-repo standalone onboards
  instead of a combined be-fe-pair config, and a terminal reject for ambiguously-tagged
  pair-ticket titles at intake. No gate behavior changed; staged-lane semantics untouched.
  Migration: none.
  none — corrects an in-progress diff before its first review; the net
  consumer-visible change is unchanged from the previous commit's trailer.
```

That is the release note consumers get. No lane can red on it.

### B3 — the correction commit's trailer is not the no-op form

Second paragraph of the render above. `render_bullet`'s no-op test
(`derive-release.sh:239-242`) is **whole-block** after normalizing case, trailing whitespace
and a trailing period — deliberately, so that "none of the public helpers changed" stays a
real entry. `none — corrects an in-progress diff …` is not `none`, so it renders. Use a bare
`Changelog: none.` and move the rationale into the commit body prose.

### W1 — the new manifest block stole the neighboring entry's closing line

On `origin/main` the intake-receipt-vocabulary DROPPED entry ends
`# Revisit if a third site starts parsing either enum.`. The new block was inserted between
that entry's `NOTE the deliberate NON-COUPLING` line and it, so the file now reads: the enum
entry ends at the NOTE with no revisit trigger, and the ticketTag entry ends with **two**
revisit lines — its own `# Revisit if a fourth site starts parsing or restating ticketTag's
semantics.` followed by an orphaned `# Revisit if a third site starts parsing either enum.`
naming an enum the ticketTag entry never mentions. Append the new block after that line, not
before it. (`check-lockstep-pairs.sh` passes either way — comments are not parsed.)

### W2 — OR-2's flag is not in the hand-off step

Spec OR-2's accepted default is "the duplication stands, **and onboard's hand-off step says
so out loud**", ledger OR-2 the same. Step 8 item 7 says the sibling drafts "its own
independent config, bot identity, and worktrees dir" — the reader learns there are two
configs, but not that `commands.fe` and `commands.<fe-id>` are the same command table with
nothing keeping them in sync. Not an AC, so not a blocker; one clause closes it.

### W3 — the "structural improvement" claim covers only one of the two rejects

Verified against `plugins/dev-pipeline/skills/run/stages/1-intake.md:28-40`: Stage 1.T raises
`targetRepos-ambiguous` only when `TARGET_REPOS` resolves **empty**; both tags present is an
explicitly supported case (`# both tags present ⇒ cross-repo, i.e. TARGET_REPOS="be fe"`).
So for the two-tag reject there is no staged-lane runtime failure being improved on — the
staged lane runs it. The spec carries the same phrasing, so the diff is faithful to it;
flagged as an accuracy warning, not an implementation defect.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | `onboard/SKILL.md` Step 8 item 7 carries all three required clauses: (a) "This run's `be-fe-pair` config (drafted at Step 3) is unchanged and still covers both sides for the deprecated staged lane", (b) the `cd <sibling path>` + `/second-shift:onboard` direction with "Detection reports `standalone` from that side … with no further prompts", (c) "**FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo**, not from here." The confirmed-pair draft at `SKILL.md:57-69` is untouched, as AC-1 requires. See W2 for the OR-2 clause. |
| AC-2 | **unsatisfied** | Both halves are written, but the title check does not implement the contract's predicate — B1. The cross-repo admission rule half is correct and complete (Step 4 + the Step 6 `--repo` note). |
| AC-3 | **satisfied** | `docs/config-schema.md:21-30` states both readings side by side and names Stage 1.T as unchanged; `docs/onboarding.md:51-73` adds the two-onboard section plus the same two-reading paragraph; `docs/team-rollout.md:23-29` adds "A BE/FE pair needs Day 0 a second time, in the sibling repo" and the FE-repo rule, which also repairs the singular "Run `/second-shift:onboard` in the target repo" at `:12`. Cross-doc anchor `#pair-repos-befe-under-the-lean-lane` resolves against `### Pair repos (BE/FE) under the lean lane`. |
| AC-4 | **unsatisfied** | Second half holds — grepped the full diff for consumer-repo names, company JIRA keys and the branch-prefix token: zero hits. First half fails: the trailer that renders describes a rejected design (B2) and a second block renders internal process prose (B3). |
| AC-5 | **satisfied** | `schema/second-shift.config.schema.json` `ticketTag.description` now reads "…The staged lane (/dev-pipeline:run) reads this as a gate input at Stage 1.T; the lean lane (/dev-pipeline:run-lean, the default) never gates on it — it's advisory routing for whoever launches the session, read by the intake-orchestrator skill as ticket-filing policy." Same diff as AC-3's docs. `check-configversion-migration-doc.sh` passes (D-9 confirmed: description strings are invisible to it). |
| AC-6 | **satisfied** | The DROPPED block is present and mirrors the intake-receipt entry's shape (coupling statement → "Considered for a row and DROPPED" with the per-relation reasoning → "Guarded behaviorally instead" → revisit trigger), and its behavioral-guard leg cites the right pin (`check-config-shadowing.sh:34`, verified clean). W1 is collateral damage to the neighbor, not a defect in this entry. |

## Gates run from this checkout

`check-lockstep-pairs.sh` 16 pairs / 0 failed · `check-frozen-files.sh origin/main` clean ·
`check-changelog-trailer.sh origin/main` OK (presence only — see B2) ·
`check-configversion-migration-doc.sh` unchanged (2) · `check-config-shadowing.sh` clean ·
schema parses. No shell or `.mjs` file is in the diff, so the selftest sweep is unaffected.

## Open regions

OR-1 (`pause-and-ask`) is untouched by the diff — correct; it belongs to #348. OR-2 and OR-3
are `reversible-default-and-flag`; OR-3's flag lands as the D-3 body line in the Step 4 rule
as specified. OR-2's flag is missing — W2.
