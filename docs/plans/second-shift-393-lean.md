# Pair topology under the lean lane: two standalone onboards, cross-repo split at intake

Spec of record for issue #393. The definition of done is the `AC-n` set below.

## Problem

`lean-gate.sh` routes entirely by invocation cwd: it resolves the host repo as the
`topology.repos` entry whose `path` is `"."` and reads only that entry's commands and base
branch. It has no `ticketTag` routing and no per-repo worktree map — those are staged-lane
Stage 1/2 mechanics (`topology.type: be-fe-pair`, `TARGET_REPOS`, the per-repo `worktrees`
map) with no lean successor, by design (staged-choreography stages don't survive into the
lean lane).

`plugins/second-shift/skills/onboard/SKILL.md` was written before the lean lane existed and
still confirms a pair candidate and then drafts a single combined config with `be` + `fe`
entries — the staged lane's shape. Nothing tells an operator that the lean lane wants the
opposite: two independent standalone onboards, one per repo. Nothing in
`intake-orchestrator` handles a ticket whose scope crosses a pair's repo boundary — today it
would either decompose it into same-repo sub-issues (wrong tracker) or let it through as one
ticket the lean lane cannot resolve. `ticketTag` docs describe only the staged lane's
gate-enforced reading, not the lean lane's advisory one.

## Ratified contract (binding, from the epic walkthrough)

- Each repo of a pair gets its own onboard: its own config (itself at `path: "."`), its own
  bot identity, its own worktrees dir.
- FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo.
- `ticketTag` is a routing hint for whoever launches the session (operator today, the thin
  orchestrator later) — never a gate concern under the lean lane.
- A ticket whose scope spans both repos never enters the queue: intake splits it into one
  BE-tagged and one FE-tagged ticket, ordered by dependency (typically BE first; the FE
  ticket pins the landed API contract in its own spec and is not queue-labeled until the BE
  PR merges). Same principle as the stacked-PR retirement: ordered per-repo tickets, never
  one multi-part artifact.
- A title carrying both tags, or neither, is a reject at intake exit — the ambiguity stop
  moves earlier than today's staged-lane runtime failure (`targetRepos-ambiguous`) and
  becomes terminal rather than something interactive mode can talk its way past.

## Scope

Prose and skill guidance only — no gate code, no schema change, no `lean-gate.sh` change.
The staged lane's own `be-fe-pair`/`ticketTag`/`TARGET_REPOS` mechanics (`state-schema.md`,
`stages/1-intake.md`, the Stage 2/6/7/8/9 per-repo mechanics) are untouched by this issue —
they remain the correct reference for anyone still on `/dev-pipeline:run`.

## AC-n

**AC-1** (critic). `plugins/second-shift/skills/onboard/SKILL.md`:
- Confirming a pair (`topology.value == "be-fe-pair-candidate"`, confirmed) drafts THIS
  repo's config as `topology.type: standalone` — a single entry for itself at `path: "."` —
  never the combined `be`+`fe` draft. The combined shape is called out as the staged lane's
  own onboarding path, not something this skill drafts from a pair confirmation.
- The pair-confirm elicitation captures which side this repo is (BE/FE) and an optional
  `ticketTag` for it, documented explicitly as an advisory routing hint, not a gate input.
- The hand-off (Step 8) offers/instructs onboarding the sibling as its own standalone host,
  and states plainly that FE-tagged tickets run `/dev-pipeline:run-lean` from the FE repo.

**AC-2** (critic). `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` documents:
- The cross-repo split rule: scope spanning a confirmed pair's two repos never becomes one
  queued ticket. It splits via the existing `sub-issues-sequential` mechanism into one
  BE-tagged and one FE-tagged sub-issue, ordered by dependency (BE before FE by default),
  each filed in **its own repo's tracker** (not this repo's), with the FE ticket withheld
  from the queue until the BE PR merges (mirrors the existing "blocked successor" mechanics
  in Step 6 — no new mechanism invented).
- The terminal reject: at intake exit, a ticket title carrying both pair tags, or neither,
  is rejected outright — never proceeds to spec review, never becomes a mid-pipeline
  ambiguity escalation. Distinguished explicitly from the staged lane's runtime
  `targetRepos-ambiguous` failure, which this is not a replacement for.
- Where the sibling repo's identity is not resolvable in-session (standalone configs carry
  no cross-repo pointer), escalate `needs-intake-review` and ask the operator — never guess
  a repo slug.

**AC-3** (critic). `docs/onboarding.md`, `docs/config-schema.md`, `docs/team-rollout.md`
re-scope `ticketTag`: under the lean lane it is an advisory routing hint read by a human or
the future thin orchestrator, never by any gate. The staged lane's existing gate-enforced
reading (`topology.repos.<id>.ticketTag` resolving `TARGET_REPOS` at Stage 1.T) is called
out as unchanged and unaffected by this re-scoping — both readings of the same field are
named side by side, not presented as a migration. `docs/onboarding.md` gains a short section
covering the two-standalone-onboards model; `docs/team-rollout.md` notes a pair repo needs
its Day-0 onboard run twice, once per repo.

**AC-4** (critic). Commit carries a `Changelog:` trailer describing the doc/guidance change;
no consumer-repo identity tokens appear anywhere in the diff.

## Open regions

- Whether `topology.type: be-fe-pair` itself retires with the staged lane is out of scope
  here (belongs to #348) — this issue documents the lean lane's own model alongside it,
  it does not remove or deprecate the staged-lane shape.
