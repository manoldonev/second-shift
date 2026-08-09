# second-shift #440 — the bot is a code-host capability, not a tracker one

## Problem

`config-lint.sh:44` rejects a `tracker.bot` block whenever `tracker.type` is `jira`:

```jq
err((.tracker.bot? != null) and (.tracker.type? == "jira"); "tracker.bot is github-only")
```

The stated rationale (`tools/tracker/jira/README.md:74`) is about **claiming** — a Jira
consumer has no issue queue, so it never races for one. That is true. But claiming is not
what the block configures. Every key the schema allows under `tracker.bot` is an **identity**
key, and none of them is claim-specific:

| key | what it configures |
| --- | --- |
| `enabled` | whether writes carry bot identity at all |
| `envVar` | the env override naming the wrapper |
| `wrapperPath` | where the wrapper lives |
| `app.*` | the GitHub App the identity belongs to — `bot-commit.sh` derives the git committer from `app.appName` |

Issue tracker and code host are orthogonal axes. A repo may track work in Jira read-only
while its source lives on GitHub, where the pipeline writes on every run. Today that config is
unserviceable, and the consequence is not cosmetic: under `tracker.type: jira` the bot block
is illegal, so `.tracker.bot.enabled` reads `false` structurally, and every code-host write
lands as the operator —

- `pipeline-cost-block.sh:232` gates the PR-body cost-block PATCH on that key;
- `lean-gate.sh cmd_mark` (`:921`) early-returns on `tracker.type = jira`, so no PR marker is
  ever posted;
- `lean-evidence.sh arm_identity` (`:433`) therefore reports the merge boundary's identity arm
  UNAVAILABLE AT REDUCED STRENGTH for every Jira consumer, forever.

None of those is a tracker write, so none is covered by `tracker.writes: false`. The lint
does not merely misname a key — it makes a whole class of consumer permanently
identity-blind at the one boundary the lane exists to defend.

Separately, and on the same theme: `review-lean` step 8 posts its findings comment with bare
`gh`, while `pr-revision/SKILL.md:31` mandates the wrapper for exactly `pr comment`. On a
bot-enabled github consumer that one write already lands under the operator while every
other pipeline comment lands under the bot.

## Scope

No pre-flight ledger exists for this issue (`.claude/pipeline-state/440-ledger.md` absent);
the issue body is the binding input.

**Which of the issue's two fixes.** The issue offers (1) move `bot` to a code-host scope —
correct modelling, needs a `configVersion` migration — or (2) narrow the lint so only the
claim-related sub-keys are rejected. Option 2 is taken, and the table above is why it is not
the lesser fix it looks like: **there are no claim-related sub-keys**, so "narrow the lint to
the claim keys" is exactly "drop the rule". The rule has no residue to keep.

Option 1 is declined on cost-for-value, not on principle. It is a `configVersion` 2→3 bump
plus a migration doc plus a rewrite of ten `.tracker.bot.*` readers plus every consumer
config in the wild — and it does **not** fix the reported behavior, because both degrade
paths key off `tracker.type`, not off where the block is spelled. It buys a better name and
leaves a Jira consumer exactly as identity-blind as before. The correct-parent rename remains
a legitimate successor; this ticket makes the capability work first.

The secondary item is **in scope**: the issue offered to split it out and nobody took the
offer, and it is the same axis mistake one layer up.

**Not in scope.** `gh pr create` authorship. The issue lists it under blast radius, and after
AC-1 it has the same identity story under both trackers — a bot-enabled Jira consumer can
carry bot identity everywhere a github one can. Whether the pipeline *should* open PRs as the
bot rather than the operator is a tracker-independent policy question about PR ownership
(review-request routing, `author_association`, who can edit the body), not an axis conflation,
and it is not this ticket's defect. No `configVersion` change and no config migration.

## Acceptance criteria

**AC-1 — `config-lint.sh` accepts `tracker.bot` under `tracker.type: jira`.** The
`tracker.bot is github-only` rule is deleted from `plugins/dev-pipeline/skills/run/tools/config-lint.sh`.
The per-key shape rules underneath it (`tracker.bot: unknown keys`, the three type checks,
`tracker.bot.app: unknown keys`) are unchanged and still fire under both trackers. The
sibling `tracker.labels is github-only` rule stays: a label vocabulary really is queue
machinery, and a Jira consumer has no queue.

**AC-2 — the acceptance is fixtured, in both directions.** A new
`config-lint-fixtures/valid-standalone-jira-bot.json` — the issue's reproduction config,
`tracker.type: jira` + `writes: false` + a `bot` block with `enabled` and `app.appName` —
passes `config-lint.sh` with rc 0. The existing `invalid-bot-app-unknown-key.json` and
`invalid-type-gaps.json` expectations are unchanged, proving the shape rules survived the
deletion. Today no fixture exercises the deleted rule at all, so its removal would otherwise
be invisible to the suite.

**AC-3 — the merge boundary's identity arm keys on bot availability, not on tracker type.**
`lean-evidence.sh arm_identity` evaluates the marker comparison whenever a bot is available
and degrades — with the same announced UNAVAILABLE AT REDUCED STRENGTH line, reworded to name
the real cause — whenever one is not. Availability resolves by the file's existing idiom: an
optional `LEAN_BOT_ENABLED` env override first, then the committed config's
`.tracker.bot.enabled`. **An unresolvable config resolves to available**, preserving the
posture stated at `:182` that an unreadable config lands on the strict side — this repo
gitignores its own config, so its CI reads nothing and must keep gating at full strength. A
Jira consumer with a bot enabled is gated at full strength; a consumer of either tracker with
no bot gets the announced degrade.

**AC-4 — `lean-gate.sh mark` posts the marker whenever a bot is configured.** `cmd_mark`'s
early return is re-keyed from `tracker.type = jira` to "no bot enabled in config", and its
announcement names that cause. Under `tracker.type: jira` with a bot enabled the marker is
posted exactly as under github. `cmd_claim`'s jira branch is **unchanged** — it skips the two
writes because a read-only tracker has no comment surface, which is a tracker fact and stays
keyed on the tracker; only its parenthetical rationale ("documented github-only") is
corrected.

**AC-5 — `review-lean` step 8 posts through the bot wrapper.** The findings comment uses the
bot wrapper when the bot is enabled, matching `pr-revision/SKILL.md:31`'s mandate for
`pr comment`, and falls back to plain `gh` when it is not. The skill's tracker-delta note no
longer claims the step is "posted via `gh`" under both adapters.

**AC-6 — no shipped prose still asserts the prohibition.** Every non-derived file that states
`tracker.bot` is github-only, or reasons from that premise, is corrected:
`schema/second-shift.config.schema.json` (the `bot` description), `tools/tracker/README.md:92`,
`tools/tracker/jira/README.md:74`, `plugins/second-shift/templates/consumer/SECOND-SHIFT.md:59`,
and the in-file rationale comments at `lean-evidence.sh:45`, `lean-evidence-selftest.sh:373`,
`lean-gate.sh:841`, and `lean-gate-selftest.sh:3029`. `CHANGELOG.md` is derived at release
time and is not touched.

**AC-7 — the new behavior is covered by the existing suites, not by prose greps.**
`lean-evidence-selftest.sh` gains cases pinning AC-3's three-way resolution: bot enabled under
jira ⇒ arm evaluated; bot absent under github ⇒ announced degrade; config unreadable ⇒ arm
evaluated. `lean-gate-selftest.sh` gains a case pinning AC-4: `mark` under jira with a
bot-enabled config attempts the post rather than short-circuiting. Each new assertion is
probed by mutating the production line it guards and confirming the case fails.
