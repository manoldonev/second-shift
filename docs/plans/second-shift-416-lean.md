# the lean entry gate's ledger precondition is unenforced

Issue: https://github.com/manoldonev/second-shift/issues/416
Pre-flight receipt: `.claude/pipeline-state/416-ledger.md` (D-1 … D-16, OR-1, OR-2) — binding input.

## Problem

`lean-gate.sh cmd_entry` fails closed on a missing or empty per-session audit ledger, and its own
comment states the stake: a run whose tool calls left no ledger cannot be reconciled at the merge
boundary. But nothing enforces that it ran. `entry` appears in `lean-gate.sh` only at its
definition and its dispatch arm, `check-lean-chain.sh` never mentions it, and `cmd_entry` writes
nothing durable — it `say`s and `warn`s and never calls `append_satisfied`. A run that simply never
calls it reaches five green milestones, a committed verdict record and a merged PR, and no artifact
records that the precondition was skipped.

Two runs in a jira-tracked consumer that does not enable `audit-toolkit` — where no ledger can
exist, so `entry` would have refused — did exactly that. `lean-reconcile.sh`'s central arm ("the
review session has a live ledger") is the one check separating a review that ran from a verdict
file someone wrote; where the ledger cannot exist that arm is dead on arrival, and today it is
discovered post-hoc, after merge, by an operator who chose to run reconcile.

## Approach

Make the entry precondition **observable** rather than trusted, in `lean-gate.sh` only (D-2).
`cmd_entry` leaves a durable progress-file row; every build-role subcommand refuses before any
evaluation when that row is absent; `lean-reconcile.sh` gains a failing arm reading the same row;
and `doctor.sh` turns the `audit-toolkit` opt-out that makes the lane unusable into a failure
instead of a shrug.

Three shapes the receipt **rejected**, recorded so the diff is not re-litigated:

- Enforcing at `check-lean-chain.sh` (D-2) — it is second-shift-only, reconciles against tracker
  comments a `writes: false` tracker never posts, and cannot read the gitignored progress file
  from a CI checkout. It is blind to the very repo class that motivated this.
- Re-evaluating the ledger predicate at a later milestone (D-3) — that reads
  `$MAIN_ROOT/.claude/audit/$sid.jsonl` while the hook writes into the worktree, false-reding
  every honest run until #417 lands. Later readers therefore check **presence only**.
- A symmetric ledger precondition on `cmd_verdict` (D-5) — out of scope, gated on #417 for the
  same reason: `review-lean` step 3 puts the review session in the build run's leftover worktree.

Refusal point: the **precondition** (D-4), not milestone 4. The issue's binding constraint is "the
failure must be reachable before a verdict record exists", and milestone 4's input *is* the
committed verdict record; the milestone-4 wording in its exit-evidence section is an illustration
of the same refusal, kept here as a backstop fixture (D-13).

## Open-region defaults taken (both `reversible-default-and-flag`)

- **OR-1 — attestation granularity across a resumed run: per-RUN.** The row attests that the run
  *started* attested; a session resuming it inherits the row without proving its own ledger is
  live. `entry` is idempotent, so an operator wanting the stronger property just re-runs it.
  Tightening to per-session is one comparison against the session id the row already carries, but
  cannot be done honestly until #417 lands — a resumed session working in the worktree would
  compare against a ledger the readers cannot find.
- **OR-2 — `audit-toolkit` opt-out on already-onboarded consumers: AC-5 FAILs, no escape hatch.**
  The size of the affected set is unknown to the receipt and taking an inventory is not this
  ticket's work. Reversal is one condition in one loop in `doctor.sh`; a documented escape hatch
  or a demotion back to `warn` can be added later without moving any contract established here.
  What must not happen is softening it to a `warn` to keep a consumer green — that is the failure
  mode D-1 exists to close.

## Acceptance criteria

- **AC-1** — On a passing predicate, `cmd_entry` appends **one** durable row to the progress file
  recording the resolved ledger path, its line count and the session id. The line shape is added
  to `lean-gate.sh`'s progress-file-primitives comment block, which is where every consumed shape
  is pinned (D-10). The row is written only when the predicate holds at that moment, and appending
  is idempotent: repeated `entry` calls never produce a second row (D-11).

- **AC-2** — `cmd_entry`'s refusal *wording* distinguishes "the plugin that writes ledgers is off"
  from "the ledger is missing" by best-effort reading `enabledPlugins` from `.claude/settings.json`
  and `.claude/settings.local.json`; a missing, unreadable or silent settings file yields the
  generic message. The ledger predicate stays the sole decider of the verdict — this adds a
  diagnostic source, never a second authority (D-9). Delivers the issue's third scope bullet.

- **AC-3** — Every **build-role** subcommand — `claim`, `1`…`5`, `all`, `delta` — refuses with
  **exit 2** before any evaluation when the progress file carries no AC-1 row, naming
  `bash G entry <issue>` as the remedy. No fix-budget attempt is recorded and no `attempt` line is
  written: "you skipped step 1" is not a code fix, and charging it would silently shorten the real
  budget (D-4). `entry` itself and the review-role `verdict` are exempt. Recorded consequence:
  `delta` is invoked by the **review** session, so a review of an unattested build is refused with
  a remedy only the build side can apply — intended, since a reviewer must not certify a run whose
  ledger never existed. The refusal names its **second** cause as well: the progress file is
  host-local and gitignored, so from a checkout that does not share the build host's state dir an
  attested run is indistinguishable from an unattested one. `review-lean` step 4 says the same,
  since "hand it back" is the wrong move when the record merely cannot be reached from here.

- **AC-4** — `lean-reconcile.sh` gains a **failing** arm asserting the build entry row, running
  under both tracker adapters (it reads only the progress file it already opens). It is the only
  mechanical route to detecting this on runs that already merged — which is how #416 was found
  (D-6).

- **AC-5** — `doctor.sh`'s opt-out scan FAILs (`bad`, exit-code-affecting) when `audit-toolkit` is
  disabled **and** `dev-pipeline` is enabled; every other opt-out keeps the existing `warn`. A repo
  that adopted only review-toolkit or intake-toolkit has no lane to protect (D-7). The condition is
  unqualified by **file**: the scan reads the committed `.claude/settings.json` alongside
  `settings.local.json` and the user settings, because the committed file is the one onboard writes
  and therefore where a hand edit lands. Reading only the local/user pair left that flip silently
  green — not even the pre-existing `warn` — while the identical flip one file over FAILed.

- **AC-6** — Onboard's review/consent screen states the lane requirement, and step 6 says plainly
  that a hand-edited settings block disabling `audit-toolkit` breaks the lean lane. Onboard already
  pins `audit-toolkit` unconditionally, so there is no opt-out path to close there — this is a
  guard against hand editing, not a new decision point (D-8). Prose only; per CLAUDE.md it gets no
  presence guard.

- **AC-7** — `lean-gate-selftest.sh` covers, as behavioral fixtures: the AC-1 row written and not
  duplicated on re-run; the AC-2 wording split (plugin-off vs generic) with the verdict unchanged
  in both; the AC-3 refusal on a build-role subcommand with its remedy string, exit 2 and **no**
  `attempt` line; and the D-13 backstop — a run reaching **milestone 4** with no entry trace reds,
  paired with the same call passing once the row exists.

- **AC-8** — The lean legs of `scenario-liveness-selftest.sh` compose production `entry`: the
  fixture tree carries a per-session ledger under a leg-controlled `CLAUDE_CODE_SESSION_ID` (so the
  legs are deterministic whether or not the ambient one is set), and every leg's progress file
  acquires its row by *calling the gate*, not by seeding the line. A new leg composes the refusal
  end to end: a lean progress file with no entry row refuses at `all` and at a single milestone
  with exit 2 while the fix budget stays untouched (D-12; CLAUDE.md's rule that a new gate contract
  extends the liveness scenario for every verdict path it touches).

- **AC-9** — `lean-reconcile-selftest.sh` reds AC-4's arm on a progress file without the row and
  passes it with one — the arm must be fixture-reddable, or it is coverage in appearance only
  (reconcile's own bar).

- **AC-10** — `doctor-selftest.sh`'s `opt-out` scenario is re-keyed to AC-5's FAIL, and two paired
  scenarios cover what a single re-key would leave untested: the surviving `warn` path
  (`audit-toolkit` off with `dev-pipeline` off), and the same FAIL reached through the committed
  `.claude/settings.json` rather than `settings.local.json`. Only the file moves between that last
  pair — which is the one variable a scenario keyed to a single file cannot vary.

- **AC-11** — `tools/mutation-catalog.tsv` gains a row for each new guard the generic tier cannot
  reach, each verified killed by its paired suite; generic survivor ordinals re-keyed by editing
  these guards are re-baselined in `tools/mutation-baseline.tsv` in the same diff.

- **AC-12** — Docs made accurate by the change: `run-lean/SKILL.md` step 1 (entry leaves the record
  every later subcommand demands) and its `lean-reconcile.sh` arm count; `lean-gate.sh`'s usage
  header for `entry` and the exit-code table; `lean-reconcile.sh`'s header enumeration of what it
  checks. The `Changelog:` trailer states D-14's rollout: **no grandfather window** — an in-flight
  lean PR whose build ran without the row reds at `all`/`delta` and at reconcile, and the remedy is
  one idempotent `bash G entry <issue>` wherever the hook is live.

  **Every arm COUNT and RANGE goes too**, wherever it sits — AC-4's arm moves both the numerator
  and the denominator, since it is adapter-insensitive and runs in full under jira. That reaches
  `lean-reconcile.sh`'s two range statements, the `tracker/README.md` reconcile row and its
  jira-backstop note, and `lean-reconcile-selftest.sh`'s `(P)` prose. The remedy is #414's on this
  same README, not a re-pin: **drop the count**, so the next arm cannot leave them stale again.

- **AC-13** — The progress header's `run_id` cannot freeze. Making `entry` create the record again
  reopens #322's `unset` freeze, because SKILL.md orders `entry` (step 1) before the `RUN_ID`
  export (step 2) — so the header is born `unset` on an ordinary run, and `lean-reconcile.sh` arm
  (1) then compares the claim comment's real id against it and reds a clean github run. The
  progress-file writer heals the placeholder instead: the first call to ESTABLISH an identity
  rewrites it, where "establish" means the value in the build cache — only `entry` and `claim`
  persist there, so an ad-hoc `RUN_ID` on a non-persisting milestone call never reaches the header,
  and a review identity (never in that cache, P10) could not stamp it even if `verdict` grew a
  write. That cache compare is the whole of the guard; matching the literal `unset` narrows the
  rewrite but cannot be red on its own, and the code says so rather than presenting it as a second
  check. Paired `lean-gate-selftest.sh` cases cover both directions, the jira claim case asserts
  the healed value rather than being handed one, and `tools/mutation-catalog.tsv` carries the row
  for the heal's removal.

## Out of scope

- `cmd_verdict`'s symmetric review-side ledger precondition (D-5) — follow-up, gated on #417.
- The writer/reader ledger-path split (#417). Nothing here re-resolves a ledger path from inside a
  worktree, which is what lets this land independently.
- `check-lean-chain.sh` (D-2). Accepted cost: the merge boundary stays blind to this fact; AC-4 is
  the compensating reader.
- Any inventory of which consumers enable `audit-toolkit` (OR-2).
