# second-shift #611 — build-lean refuses an unresolvable ticket argument

## Problem

A build session invoked with no ticket argument does not refuse. Observed 2026-08-20: a spawn
whose ticket argument was lost to shell quoting listed the queue, self-selected a different open
ticket, claimed it, built it and opened a PR — while the operator believed another ticket was in
flight. Claiming a ticket the caller never named is a write under a false premise, the same class
as authoring your own verdict, and it has no gate today.

`lean-gate.sh` takes `<issue>` as a given: the only assertion is the shared
`[ -n "$ISSUE" ] || envfail usage` at parse time, which every subcommand answers identically with
exit 2, and no subcommand ever asks whether the named ticket exists, is open, or is the one whose
tree it is standing in.

## Scope

Enforcement lands in the gate; the skill states the contract. The contract binds `entry` and
`claim` — the run boundary — plus the cwd-agreement arm on `mark` and `teardown`, the two
non-milestone calls the existing wrong-tree refusal (`rc=9`) does not bind. Milestone calls
`1`..`5`, `all`, `delta` and `verdict` are untouched: same usage error on an absent argument, same
`rc=9`, same no-network property.

1. **`lean-gate.sh`** — a new `rc=10` refusal class (`UNRESOLVABLE TICKET ARGUMENT`), a
   `--ticket-source` flag, four network-free arms evaluated before any path derivation, and one
   tracker arm evaluated at dispatch before either command writes anything.
2. **`branch-prefix.sh`** — `bp_branch_key`, the inverse of `bp_is_work_branch`, so the cwd's
   ticket is derived by the one parse that already decides namespace membership.
3. **`SKILL.md`** — the resolution contract in two lines under checklist step 1.
4. **Tests** — `lean-gate-selftest.sh` gains the five failure cases and the two legal paths;
   `branch-prefix-selftest.sh` gains `bp_branch_key` cases. Both stay network-free.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Bucket and yield behavior | This refusal is gates-llm: it defends against the model acting under a false premise (claiming a ticket the caller never named), so it fires always — attended or not — alongside the never-author-your-own-verdict class. | user-answered |
| D-2 | Resolution semantics | The contract binds entry and claim only; milestone calls keep their usage error, their wrong-tree refusal and their no-network property. Validation is adapter-aware (integer under github, configured key pattern under jira); the exists-open read runs once at the run boundary; an unreadable tracker fails closed with its own named reason; re-entry evidence is the claimed label plus the lane's bot marker, exempting only the open check, with a closed-but-marked ticket routing to close-out paths; inference is legal only from a lane cwd and is passed back to the gate explicitly as a checked control. | codebase-derived |
| D-3 | Enforcement home | The gate enforces; the skill states the contract within its line budget; failure messages live in the gate. | codebase-derived |
| D-4 | OR-1 — the refusal's exit-code number | `10`. The register's taken values are 0,1,2,4,5,6,7,8,9; `3` is reserved cross-repo as a verify lane's INPUT code and is deliberately not reused as a gate exit. No selftest case needed re-anchoring: the one case that expects the usage code drives subcommand `1`, which keeps it. | codebase-derived |
| D-5 | OR-2 — inference-source precedence | The branch name wins; the lane registry is advisory. The gate is standing in a tree whose identity the branch asserts, whereas the registry is one machine-global file every worktree shares — it can be stale, and a second declaration of a fact already carried by the checkout is the shape that goes blind rather than red. So `--ticket-source lane-registry` is accepted, recorded, and still checked against the branch name; a disagreement is AC-4's refusal, not a fallback. | codebase-derived |
| D-6 | One code, five named reasons | Every arm refuses with `10`. The remedy for all five is the same — re-invoke naming the right ticket — so a second integer would buy the caller no different action, where 5/6/7/8/9 each exist because the caller's response differs. | codebase-derived |

## Acceptance Criteria

- **AC-1** A ticket argument is *resolvable* iff it validates against the tracker adapter's key
  shape (a positive integer under github; `tracker.keyPattern` under jira) and names a ticket
  that exists and is open — where *open* is waived for this run's own re-entry, evidenced by the
  claimed label plus this lane's bot-authored `lean-claimed` marker. A closed ticket carrying
  that evidence admits `entry` (so close-out and `teardown` still run) and refuses `claim`. The
  resolution order and each failure case's message live in the gate.
- **AC-2** With no argument, `entry` and `claim` refuse with `rc=10` and a message naming what was
  missing. The gate never resolves a ticket itself: from a lane-branch cwd the message names the
  derived key and the exact re-invocation, but still refuses. The refusal path performs no tracker
  read beyond validating a named ticket.
- **AC-3** Inference is legal only from a lane-branch cwd. `--ticket-source lane-branch` or
  `lane-registry` from a cwd that does not parse as this repo's work branch refuses with `rc=10`;
  from a lane cwd the ticket and its declared source are both recorded in the progress file.
  `--ticket-source` on any subcommand other than `entry`/`claim`, or with a value outside
  `argument|lane-branch|lane-registry`, is a usage error (`rc=2`).
- **AC-4** An explicit argument and a lane-branch cwd that disagree refuse with `rc=10` on
  `entry`, `claim`, `mark` and `teardown`. The milestone calls' existing `rc=9` is not duplicated
  with a second code, and a cwd that is not a work branch of this repo's namespace constrains
  nothing.
- **AC-5** A key-shape-invalid argument, an argument naming a nonexistent ticket, one naming a
  closed ticket with no re-entry evidence, and an unreadable tracker each refuse with their own
  named reason before any label swap, marker comment, attestation row or progress-file write. The
  unreadable-tracker arm fails closed.
- **AC-6** `lean-gate-selftest.sh` covers the five failure cases (absent, key-shape-invalid,
  closed/nonexistent, tracker-unreadable, cwd-disagreement) and the two legal paths
  (argument-only; inference-with-declared-source), driven through the gate's existing gh-CLI
  fixture seam. The suite stays network-free; `branch-prefix-selftest.sh` covers `bp_branch_key`.
- **AC-7** `build-lean/SKILL.md` states the resolution contract inside checklist step 1; the
  enforcement lives entirely in the gate, and no prose-presence guard is added for it.
- **AC-8** `shellcheck -e SC1091,SC2015,SC2181` and the full `tools/run-selftests.sh` sweep are
  green.

## Out of scope

- The attended-session affordance and override record (a sibling slice owns them).
- The scheduler's spawn path — it quotes its prompt correctly and calls none of the four bound
  subcommands.
- A classification register for gates-llm vs gates-human; a later slice of the parent epic owns it.
