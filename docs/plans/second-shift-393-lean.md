# Pair topology under the lean lane: two standalone onboards, cross-repo split at intake

Spec of record for issue #393. The definition of done is the `AC-n` set below.
`.claude/pipeline-state/393-ledger.md` is the pre-flight receipt for this run and is
binding; its decisions (D-1 through D-11) are transcribed below where they shape the design.

## Problem

`lean-gate.sh` routes entirely by invocation cwd: it resolves the host repo as the
`topology.repos` entry whose `path` is `"."` and reads only that entry's commands and base
branch. It has no `ticketTag` routing and no per-repo worktree map — those are staged-lane
Stage 1/2 mechanics (`topology.type: be-fe-pair`, `TARGET_REPOS`, the per-repo `worktrees`
map) with no lean successor, by design.

`plugins/second-shift/skills/onboard/SKILL.md` already drafts a confirmed pair as a
combined `be`+`fe` config, and that draft is **not wrong** — it is what the deprecated
staged lane still needs (D-1). What's missing is a hand-off telling the operator the lean
lane needs more: the sibling repo onboarded *again*, on its own, as its own standalone host
(D-1, D-5 — `detect.sh`'s sibling-candidate probe is directional, so the sibling side
already reports plain `standalone` with no code change required). Nothing in
`intake-orchestrator` handles a ticket whose scope crosses a pair's repo boundary. `ticketTag`
docs describe only the staged lane's gate-enforced reading, not the lean lane's advisory one
— and that re-scope has a fourth surface beyond the three docs the issue names: the schema's
own `ticketTag` description, which renders live in every consumer's editor (D-4).

## Ratified contract (binding, from the epic walkthrough)

- Each repo of a pair gets its own onboard: its own config (itself at `path: "."`), its own
  bot identity, its own worktrees dir. **Concretely (D-1):** the host's existing `be-fe-pair`
  config is unchanged — it still serves the staged lane. The sibling gains an *additional*,
  independent standalone onboard so it can also be worked with `/dev-pipeline:run-lean` from
  its own checkout. Two onboard runs, two configs, one host repo pair.
- FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo.
- `ticketTag` is a routing hint for whoever launches the session (operator today, the thin
  orchestrator later) — never a gate concern under the lean lane. It stays exactly where it
  already lives, on the host's `be`/`fe` entries; the sibling's own standalone config carries
  no `ticketTag` of its own.
- A ticket whose scope spans both repos never enters the queue: intake splits it into one
  BE-tagged and one FE-tagged ticket, ordered by dependency (typically BE first; the FE
  ticket pins the landed API contract in its own spec, plus a reconcile obligation at
  promotion time — D-3). Same principle as the stacked-PR retirement: ordered per-repo
  tickets, never one multi-part artifact. **This is an admission rule on the existing
  `sub-issues-sequential` decomposition flavor, not a new verdict (D-7).**
- A title carrying both tags, or neither, is a reject at intake exit (`needs-spec-work` on
  github; present-and-STOP under jira — D-2), gated on `topology.type: be-fe-pair` (D-6) —
  the ambiguity stop moves earlier than today's staged-lane runtime failure
  (`targetRepos-ambiguous`) and becomes terminal rather than something interactive mode can
  talk its way past.

## Scope

Prose and skill guidance, plus two small non-prose artifacts the ledger requires: the
schema's `ticketTag` description (D-4, AC-5) and a `scripts/lockstep-manifest.tsv`
DROPPED entry recording why the three-site `ticketTag`-semantics coupling isn't
byte-anchorable (D-10). No `lean-gate.sh` change, no `configVersion` bump, no
`detect.sh` change (D-5, D-9). The staged lane's own `be-fe-pair`/`ticketTag`/`TARGET_REPOS`
mechanics (`state-schema.md`, `stages/1-intake.md`, the Stage 2/6/7/8/9 per-repo mechanics)
are untouched by this issue (D-8) — they remain the correct reference for anyone still on
`/dev-pipeline:run`. `run-lean/SKILL.md` is out of scope (D-11).

## AC-n

**AC-1** (critic). `plugins/second-shift/skills/onboard/SKILL.md`: the confirmed-pair draft
(be+fe combined config) is **unchanged** — no code or elicitation change there. The skill
gains a hand-off step (Step 8) that (a) states the host's pair config already covers the
staged lane, (b) directs the operator to run `/second-shift:onboard` again in the sibling
repo, noting detection there reports plain `standalone` with no further prompts, and (c)
states plainly that FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo.

**AC-2** (critic). `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` documents:
- A title check gated on `topology.type: be-fe-pair` (not any new config field): a title
  carrying both pair tags, or neither, is rejected at intake exit before spec review starts
  — `needs-spec-work` on github, present-and-STOP under jira (D-2, D-6).
- The cross-repo case is documented as an **admission rule** on the existing
  `sub-issues-sequential` verdict (D-7), not a new verdict: the sibling's slice is filed in
  **its own repo's tracker**, resolved from the host's own `topology.repos.<sibling-id>.path`
  entry; unresolvable → escalate `needs-intake-review`, never guess a repo slug. The FE
  slice's body carries the BE contract as currently specified plus the reconcile obligation
  at promotion time (D-3).

**AC-3** (critic). `docs/onboarding.md`, `docs/config-schema.md`, and `docs/team-rollout.md`
re-scope `ticketTag` consistently: the staged lane's existing gate-enforced reading
(`topology.repos.<id>.ticketTag` resolving `TARGET_REPOS` at Stage 1.T) is called out as
unchanged, alongside the lean lane's advisory reading — both stated side by side, not as a
migration. `docs/onboarding.md` gains a section covering the two-onboard model (host keeps
its pair config; sibling onboards separately); `docs/team-rollout.md` notes a pair repo
needs Day 0 a second time, in the sibling.

**AC-4** (critic). Commit carries a `Changelog:` trailer describing the doc/guidance change;
no consumer-repo identity tokens appear anywhere in the diff.

**AC-5** (critic, added from D-4). `schema/second-shift.config.schema.json`'s `ticketTag`
description is re-scoped in the same diff as AC-3's three docs — the fourth, most
consumer-visible surface (it renders live in every consumer's editor via the config's
`$schema` key).

**AC-6** (critic, added from D-10). `scripts/lockstep-manifest.tsv` gains a DROPPED entry
recording the three-site `ticketTag`-semantics coupling (`docs/config-schema.md`, the
schema description, `stages/1-intake.md`'s Stage 1.T) and why no `lockstep-manifest.tsv`
relation can express it — mirroring the existing intake-receipt-vocabulary DROPPED entry's
shape and reasoning.

## Open regions

- OR-1 (pause-and-ask, carried forward verbatim from the issue): whether
  `topology.type: be-fe-pair` itself retires with the staged lane is out of scope here —
  belongs to #348.
- OR-2 (reversible-default-and-flag): the FE command table now exists in two files
  (`commands.fe` in the host's pair config, `commands.<fe-id>` in the FE repo's own
  standalone config) with no machine check keeping them in sync. Accepted default: the
  duplication stands, and onboard's hand-off step says so out loud. Free to reverse once
  #348 deletes the staged lane — the host's `fe` entry loses its only reader at that point.
- OR-3 (reversible-default-and-flag): nothing verifies the operator actually reconciled the
  FE spec against the landed BE contract before promotion — the reconcile obligation (D-3)
  is a body line, enforced the same way the rest of sequential ordering is (the missing
  queue label), not a machine gate. Matches the flavor's existing posture, where ordering
  has never had one.
