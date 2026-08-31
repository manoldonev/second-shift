# Changelog

All notable changes to the second-shift marketplace. Versions are per-plugin (`plugins/*/.claude-plugin/plugin.json`);
this file tracks the marketplace release. `configVersion` stays `const 1` — v2 is fully backward-compatible for a
consumer with an empty config; the migration notes below are only for consumers using the changed features.

## v12.2.1

### `design-toolkit` 4.0.3 → 4.0.4

- **design-toolkit gets evals: three fixture sets, three recorded baselines, one prompt fix (#713)** (#713)
  design-toolkit ships evals for figma-faithful-reviewer,
  figma-faithful-plan-reviewer and figma-faithful-spec-reviewer —
  four labeled fixtures and a locked 3-dimension rubric each, run with
  the agent-eval-kit loop. Operator-run and model-billed; never in CI.
  Migration: none.
  each design-toolkit eval dir now carries a CLOSEOUT-BASELINE.md
  recording its measured pre-edit pass rates, per-fixture and
  per-dimension, with the provenance a later run needs to compare
  against it. Migration: none.
  figma-faithful-spec-reviewer now reviews a lean-lane spec
  instead of returning `N/A` on it — the `N/A` condition is narrowed to
  an input that is not a design artifact at all, and a design artifact
  missing sections is reviewed with the un-runnable checks named.
  figma-faithful-plan-reviewer's deferrals to it are corrected in step.
  Migration: none.
- **The translation plan is asserted for shape and graded by nobody (#741)** (#741)
  on an armed lean run, milestone 3 now refuses to render until the
  provider's translation-plan reviewer's verdict is committed at
  `<plansDir>/<key>-lean-plan-review.md`. The build session dispatches the
  reviewer and writes the record with `lean-gate.sh plan-review <issue>
  --verdict <pass|fix-and-go|block> --summary-file <findings> --model <m>`;
  `block` reds the milestone quoting the first finding, `pass` and `fix-and-go`
  proceed. A design family with no plan-stage reviewer agent is declared
  unreviewed instead of blocked.
  Migration: none — the artifact is required only on a ticket whose committed
  spec arms the design lane against a figma handoff.

### `dev-pipeline` 12.2.0 → 12.2.1

- **pipeline-doctor-selftest's sibling arm asks resolve_sibling, not the monorepo path (#706)** (#706)
  pipeline-doctor-selftest's sibling-delegation check resolves through the
  real resolve_sibling ladder instead of a monorepo path join, so it no longer reports
  every sibling selftest as deleted when the plugin runs from an install cache; and a
  red from install-topology-selftest now quotes the failing suite's own FAIL line
  rather than the first line that merely contains the word 'failed'.
  Migration: none.
  a red from install-topology-selftest now reports a signal-killed suite as
  infra with its signal number, instead of quoting the last line it happened to print —
  which for a suite killed mid-run is a passing assertion.
  Migration: none.
- **An unrunnable-pair red names its failing cases, and lean-gate's mutation coverage comes back (#715)** (#715)
  an `unrunnable pair` red now names the paired suite's failing case(s)
  instead of printing a blind tail of its log, and says so explicitly when the
  suite failed without naming one.
  Migration: none.
  the shipped lean-gate selftest no longer fails when its own scratch
  directory path contains the word "mutation" — #580's assertions read the gate's
  words rather than the fixture's path — and its dangling-symlink never-clobber
  case now fires under GNU cp as well as BSD cp.
  Migration: none.
- **design-toolkit gets evals: three fixture sets, three recorded baselines, one prompt fix (#713)** (#713)
  design-toolkit ships evals for figma-faithful-reviewer,
  figma-faithful-plan-reviewer and figma-faithful-spec-reviewer —
  four labeled fixtures and a locked 3-dimension rubric each, run with
  the agent-eval-kit loop. Operator-run and model-billed; never in CI.
  Migration: none.
  each design-toolkit eval dir now carries a CLOSEOUT-BASELINE.md
  recording its measured pre-edit pass rates, per-fixture and
  per-dimension, with the provenance a later run needs to compare
  against it. Migration: none.
  figma-faithful-spec-reviewer now reviews a lean-lane spec
  instead of returning `N/A` on it — the `N/A` condition is narrowed to
  an input that is not a design artifact at all, and a design artifact
  missing sections is reviewed with the un-runnable checks named.
  figma-faithful-plan-reviewer's deferrals to it are corrected in step.
  Migration: none.
- **Telemetry that is on but exporting nowhere costs a whole run before anyone finds out (#727)** (#727)
  run-lean's preflight now reports whether a run's spend will be
  priceable, naming `OTEL_METRICS_EXPORTER` when telemetry is enabled with no
  exporter configured — before any session is spawned, rather than as a
  `totalUsd: null` cost block hours later. Advisory only; no exit code changes.
  Migration: none.
- **Milestone 1 reads the open-region shapes tickets actually use, and refuses the ones it cannot (#716)** (#716)
  build-lean's milestone 1 now reads a bullet-form `## Open regions` section — including
  a disposition token on a bullet's continuation line — and a section heading carrying trailing
  text, in both the issue body and the pre-flight ledger. A section that declares regions in no
  recognized shape, or an `OR-n` with no recognizable disposition, is now refused as an
  environment error naming every affected source and region, where it previously passed the gate
  silently. The refusal spends no fix attempt. Migration: a ticket whose open-regions section is
  prose without `OR-n` ids, or whose disposition is stated without its token, will now stop
  milestone 1 — rewrite the section as a table row or an id-bearing bullet. The accepted shapes
  are documented in intake-toolkit's interviewing-baseline skill.
- **close-out's merged-PR reachability, and the seven sites stating its rule wrongly (#728)** (#728)
  close-out now completes when an operator merges the PR before the run
  reaches milestone 5. Previously the identity stamp still required an open PR, so
  the run's cost-log row was never written and its PR kept a stale cost block. The
  claimed label's release is unchanged — the unclaim workflow still fires on the
  tracker item's close.
  Migration: none.
- **check-guard-budget.sh and the Guard-mass trailer are deleted (#732)** (#732)
  none (repo CI only). Migration: drop Guard-mass: trailers.
- **The provider's fidelity reviewer is mandatory on an armed run, and the verdict names who reviewed (#729)** (#729)
  on an armed design ticket the provider's fidelity reviewer is now
  dispatched unconditionally rather than on a path-glob judgment, a round that
  loses it to a dark reviewer is voided instead of recorded, and the verdict
  record carries a new `panel:` header naming the reviewers the round got a
  result back from. `bash G verdict` requires `--panel` on an armed spec and
  refuses one omitting the reviewer the handoff host implies; milestone 4 and
  the merge boundary's evidence arm 8 assert the same. The reviewer family comes
  from the `## Design` handoff link's host (a figma.com URL, or claude.ai under
  /design), never from config, and milestone 1 refuses an armed spec whose
  handoff host is unrecognisable or disagrees with `design.provider`.
  Migration: none. No repo in this marketplace arms a design lane today, and
  consumers fetch the merge boundary at their own pinned ref, so nothing in
  flight turns red until a consumer bumps.
- **The continuation stack is deleted: one BUILD spawn, then a human (#734)** (#734)
  `/dev-pipeline:run-lean` spawns BUILD once per round. A build session
  that ends without an open PR, or with one and uncommitted or unpushed work in
  its lane worktree, now stops the run for a human to read rather than being
  re-spawned on a budget. `lean-gate.sh progress <issue>` requires `--satisfied`
  or `--obligations`; the bare form and `--infra` are removed.
  Migration: `--max-continuations` is removed and refuses with a message naming
  the removal. A lane that relied on the recovery spawn pushes from the lane
  worktree by hand and re-launches.
- **`Design: none` on a provider repo needs a gate-visible design-disarm override (#736)** (#736)
  on a repo configured with design.provider, a spec that disarms the design render
  lane with `Design: none — <reason>` now requires a gate-visible `design-disarm` operator
  override (`operator-override.sh record --gate design-disarm --scope design-disarm --issue <n>
  …`) — milestone 1 reds naming the exact command until one is recorded. The committed verdict
  on a disarmed, overridden ticket carries `fidelity: not-applicable (override: <ref>)`, and the
  merge boundary refuses a PR whose cited ref does not resolve to a real record.
  Migration: none — a repo with no design.provider configured is unaffected, and an already-armed
  or already-unarmed ticket is unaffected.
- **refactor(dev-pipeline): milestone 4 stops re-checking what the merge boundary already checks (#738)** (#738)
  milestone 4 no longer re-checks the verdict record's reconciliation keys
  or its patch freshness; lean-evidence.sh at the merge boundary remains the check of
  record for both. A commit pushed after an approve now leaves `bash G 4` green and
  reds the PR instead, so land fixes before the handoff.
  Migration: none.
- **The enforced mutation sweep moves off the nightly cron onto the merge, and a red becomes a filed issue (#740)** (#740)
  the mutation sweep's enforced tier moves off the nightly cron onto a
  merge-time, diff-scoped run with deferral disabled (MUTATION_SWEEP_NO_DEFER),
  and a red merge-time or monthly-audit run now files a deduplicated GitHub
  issue carrying the survivor ids instead of reddening a cron dashboard. The PR
  lane's deferral decisions and report enum are unchanged.
  Migration: none.
- **The translation plan is asserted for shape and graded by nobody (#741)** (#741)
  on an armed lean run, milestone 3 now refuses to render until the
  provider's translation-plan reviewer's verdict is committed at
  `<plansDir>/<key>-lean-plan-review.md`. The build session dispatches the
  reviewer and writes the record with `lean-gate.sh plan-review <issue>
  --verdict <pass|fix-and-go|block> --summary-file <findings> --model <m>`;
  `block` reds the milestone quoting the first finding, `pass` and `fix-and-go`
  proceed. A design family with no plan-stage reviewer agent is declared
  unreviewed instead of blocked.
  Migration: none — the artifact is required only on a ticket whose committed
  spec arms the design lane against a figma handoff.

### `intake-toolkit` 4.2.0 → 4.2.1

- **Milestone 1 reads the open-region shapes tickets actually use, and refuses the ones it cannot (#716)** (#716)
  build-lean's milestone 1 now reads a bullet-form `## Open regions` section — including
  a disposition token on a bullet's continuation line — and a section heading carrying trailing
  text, in both the issue body and the pre-flight ledger. A section that declares regions in no
  recognized shape, or an `OR-n` with no recognizable disposition, is now refused as an
  environment error naming every affected source and region, where it previously passed the gate
  silently. The refusal spends no fix attempt. Migration: a ticket whose open-regions section is
  prose without `OR-n` ids, or whose disposition is stated without its token, will now stop
  milestone 1 — rewrite the section as a table row or an id-bearing bullet. The accepted shapes
  are documented in intake-toolkit's interviewing-baseline skill.

### `review-toolkit` 7.2.2 → 7.2.3

- **The provider's fidelity reviewer is mandatory on an armed run, and the verdict names who reviewed (#729)** (#729)
  on an armed design ticket the provider's fidelity reviewer is now
  dispatched unconditionally rather than on a path-glob judgment, a round that
  loses it to a dark reviewer is voided instead of recorded, and the verdict
  record carries a new `panel:` header naming the reviewers the round got a
  result back from. `bash G verdict` requires `--panel` on an armed spec and
  refuses one omitting the reviewer the handoff host implies; milestone 4 and
  the merge boundary's evidence arm 8 assert the same. The reviewer family comes
  from the `## Design` handoff link's host (a figma.com URL, or claude.ai under
  /design), never from config, and milestone 1 refuses an armed spec whose
  handoff host is unrecognisable or disagrees with `design.provider`.
  Migration: none. No repo in this marketplace arms a design lane today, and
  consumers fetch the merge boundary at their own pinned ref, so nothing in
  flight turns red until a consumer bumps.
- **review-lead's always-spawn core becomes a checklist-structured lead pass, and security-reviewer spawns on surface triggers (#733)** (#733)
  review-lead no longer spawns performance-reviewer, maintainability-reviewer,
  complexity-reviewer or test-coverage-reviewer; those four dimensions are now reviewed
  in-session by the review-lead pass, and security-reviewer spawns only on a security
  surface in the diff or when the repo carries a security-reviewer review-context file.
  Every reviewer remains registered and spawnable, so no config change is required.
  Consumers carrying `.claude/second-shift/review-context/<reviewer>.md` files for the
  four collapsed reviewers should know the lead pass now reads them itself — those files
  keep working and need no edit. Migration: none.

### `second-shift` 8.0.2 → 8.0.3

- **chore(docs): retire the spec and intent-gap records of closed lean runs from docs/plans (#725)** (#725)
- **close-out's merged-PR reachability, and the seven sites stating its rule wrongly (#728)** (#728)
  close-out now completes when an operator merges the PR before the run
  reaches milestone 5. Previously the identity stamp still required an open PR, so
  the run's cost-log row was never written and its PR kept a stale cost block. The
  claimed label's release is unchanged — the unclaim workflow still fires on the
  tracker item's close.
  Migration: none.

## v12.2.0

### `design-toolkit` 4.0.2 → 4.0.3

- **`fidelity: pass` must cite evidence, not assert it (#696)** (#696)
  an armed `--fidelity pass` verdict write is refused unless its
  summary carries a `## Design fidelity evidence` table scoring every declared
  render state — six named columns, every cell populated, and any deviation
  citing an AC-n or D-n the spec declares. The grammar is published in
  review-lean step 5b. This is tamper-evidence, not fidelity: it makes the
  claim falsifiable by a human reader and verifies nothing against the design.
  Already-committed verdict records are unaffected. Migration: a design-armed
  consumer must emit the table from its next review round onward.
- **The translation plan becomes an artifact milestone 3 asserts (#701)** (#701)
  an armed design ticket now owes a committed translation plan at
  `<plansDir>/<key>-lean-plan.md` — a `planned_from:` header the gate stamps, a
  `why this component` table and a `dimensions` table, every cell filled.
  Milestone 3 refuses without it, before the render pass. The figma-faithful
  plan reviewer now owns component-resolution suitability and blocks a
  control-bearing screen whose plan records no dimension row at all.
  Migration: none — unarmed and non-figma tickets are unaffected.

### `dev-pipeline` 12.1.0 → 12.2.0

- **Recover a cost block from the session transcript (#697)** (#697)
  a cost block is now recovered from the session transcript when the
  local OTel metrics file has no rows for the run — tokens, tiers, duration
  and cache-hit rate, with no USD (the transcript carries none). cost-log rows
  gain `source` and `tokens`; `totalUsd` is null on transcript-sourced rows,
  so a spend report should filter on `source == "otel"`.
  Migration: none.
- **`fidelity: pass` must cite evidence, not assert it (#696)** (#696)
  an armed `--fidelity pass` verdict write is refused unless its
  summary carries a `## Design fidelity evidence` table scoring every declared
  render state — six named columns, every cell populated, and any deviation
  citing an AC-n or D-n the spec declares. The grammar is published in
  review-lean step 5b. This is tamper-evidence, not fidelity: it makes the
  claim falsifiable by a human reader and verifies nothing against the design.
  Already-committed verdict records are unaffected. Migration: a design-armed
  consumer must emit the table from its next review round onward.
- **feat(dev-pipeline): price the transcript fallback from the session's cost-state record (#699)** (#699)
  the cost block's transcript fallback now carries the run's USD when every
  session in the set wrote a cost-state record; otherwise it states how many did.
  Migration: none.
- **The translation plan becomes an artifact milestone 3 asserts (#701)** (#701)
  an armed design ticket now owes a committed translation plan at
  `<plansDir>/<key>-lean-plan.md` — a `planned_from:` header the gate stamps, a
  `why this component` table and a `dimensions` table, every cell filled.
  Milestone 3 refuses without it, before the render pass. The figma-faithful
  plan reviewer now owns component-resolution suitability and blocks a
  control-bearing screen whose plan records no dimension row at all.
  Migration: none — unarmed and non-figma tickets are unaffected.

## v12.1.0

### `dev-pipeline` 12.0.0 → 12.1.0

- **feat(dev-pipeline): gate the scheduler's own overhead, and stop spending a round on a policy CI red (#690)** (#690)
  adds `tools/lane-latency.sh`, which measures how much of a lean run's wall-clock the
  scheduler itself is responsible for and fails above a ceiling; the launch ledger now closes every
  spawn with a `spawn-end` row so a payload's duration is derivable. review-lean records a red
  policy CI check (guard-budget, changelog trailer, frozen files) instead of blocking on it — a red
  correctness lane still blocks. Migration: ledgers written before this cannot be measured and are
  reported as such, never scored.

## v12.0.0

### `dev-pipeline` 11.0.0 → 12.0.0

- **feat(dev-pipeline): P4/P5 get a mechanical counterpart, and 180 measurement rows retire (#648)** (#648)
  `scripts/check-guard-budget.sh` reds a PR whose guard/test shell mass grows with no
  `Guard-mass: +<n> <reason>` commit trailer, replacing PR #645's abandoned committed-ceiling
  design. `.claude/prose-budget.baseline.tsv`, `.claude/prose-budget-shell.baseline.tsv`,
  `tools/selftest-slow-suites.tsv`, `tools/mutation-slow-suites.tsv`,
  `tools/selftest-sweep-baseline.tsv`, and `tools/install-topology-known-red.tsv` are deleted;
  the three suite-timing files are replaced by `tools/selftest-suite-timings.tsv`.
  `prose-budget.sh --update-baseline` is now an accepted no-op. Migration: none — no consumer
  reads the deleted files directly.
- **The campaign's instruments: per-launch spawn evidence, a mid-run staleness re-check, and variant (c) (#653)** (#653)
  run-lean's payload transcripts are now stamped with a per-launch
  token, so re-launching a ticket no longer truncates the previous launch's
  transcript, and a <issue>-lean-launches.tsv beside them enumerates every
  launch with its spawns and its terminal outcome.
  Migration: none - transcript names gain a field and still match the
  <issue>-lean-spawn-*.log glob every shipped reader uses.
  lean-gate.sh's 'mark' now refuses with exit 7 when the ticket
  closed under the run, so a build session whose premise expired mid-flight
  stops before the handoff instead of costing a review round. An unreadable
  tracker refuses with exit 2 (fail closed). Milestone 5 and close-out are
  unaffected: a ticket that closes mid-review still lands its PR.
  Migration: none.
  run-lean gains --attended, an operator-driven drive-mode that
  runs every check as a direct gate call, spawns nothing, and hands each
  model turn to the operator (exit 9 = your turn). Built as the measured
  third arm of #643's drive-mode campaign; the default behaviour of
  run-lean is unchanged.
  Migration: none - the flag is opt-in and the existing loop is untouched.
- **The lane worktree inherits the operator's Claude settings, so a build session no longer gambles on the permission classifier (#657)** (#657)
  a lean lane worktree now inherits the operator's Claude settings
  from the checkout it was cut from, so a build session launched with the
  worktree as its cwd runs under the posture the operator consented to instead
  of falling through to the permission classifier. Copied, never symlinked, and
  never over a file the worktree already carries.
  Migration: none — consumers gain the behavior with no action. An operator who
  keeps a hand-written settings file inside a lane worktree keeps it: an
  existing destination is left alone.
  `lean-gate.sh entry` no longer copies the checkout's Claude settings into a
  lane worktree when the destination path is not covered by an ignore rule — it says
  which `.gitignore` line would earn the copy instead. Without this, the copy left the
  worktree permanently unclean, which stopped the entry sweep from ever reaping it.
  Migration: none — a consumer wanting the copy adds `.claude/settings.local.json` to
  their `.gitignore`; until then the gate declines and says so.
- **The lane's gate stops refusing what it cannot change (#660)** (#660)
  milestone 3's lint, test and extraLanes lanes now REPORT a red instead of refusing
  — they record a `| milestone-3 | advisory |` row, charge no fix attempt, and the milestone
  exits 0; the merge boundary is what blocks on them. Six announcement-class refusals across
  milestones 4 and 5 moved to the `absent` verb and no longer charge the fix budget. Milestone
  5 now accepts a MERGED pull request as satisfying the same obligation an open one does, so
  `close-out` stays reachable after a merge. A verdict record carrying no `reviewed_patch_id`
  is now refused at milestone 4 instead of falling through to a SHA-keyed comparison the merge
  boundary rejected anyway.
  Migration: a consumer whose verify lane relies on milestone 3 refusing must move that
  enforcement to its own CI, or configure the lane under `typecheck`, which still blocks.
  the lean gate's `close-out` no longer charges a fix attempt when the lane has no open
  or merged PR, or when an earlier milestone left no satisfied record — both announce that a
  checklist step has not happened yet, and both already behaved this way at milestone 5.
  Migration: none.
- **A review session cites a matching CI run instead of re-executing an oracle AC (#683)** (#683)
  a review session verifying an oracle AC may now cite a CI run (job, head SHA,
  conclusion) instead of re-executing the sweep, when the run's command and head both match
  the reviewed commit. Migration: none.
  none. Round-3 review fixes only: the Command-differs worked example named an AC
  shape (#650's --full assertion) that both CI selftest lanes actually satisfy, and instead
  points at a shape they genuinely don't cover (an AC asserting
  tools/install-topology-selftest.sh is green, which both lanes exclude). Also clarifies the
  gh pr checks / gh run view citation split (the former has no head-SHA field) and replaces a
  coined term ('the PR recipe') with the doc's established 'PR lane', narrowing an over-general
  claim about when the PR lane itself catches an under-declared cache-input row.
- **Milestone 3's terminal line states its advisory count (#685)** (#685)
  milestone 3's terminal line now reads "green gate (2 advisory)" when demoted lanes
  reported red, instead of an unqualified green. No rc, verdict or consumer change.
  Migration: none.
- **Lane latency: measure it, remove the human from the recovery, delete arm c (#689)** (#689)
  the `--attended` drive-mode and its exit code 9 are removed from run-lean's
  orchestrator. It shipped as a measured spike under #650 and the campaign's frozen criterion
  cannot select it. Drive the lane by hand with build-lean and review-lean directly, which is
  unchanged. Migration: drop `--attended` from any wrapper; nothing returns exit 9 any more.
  run-lean now recovers a BUILD session that exits 0 leaving uncollected work in the
  lane worktree — it re-spawns BUILD once to collect it instead of stopping the run and asking
  for a manual push. A second identical answer still stops, unchanged. Migration: none.
  run-lean's launch ledger now records WHY a launch ended, not just its outcome slug and
  exit code — a rejected or hard-stopped launch can be classified from the ledger alone instead of
  from a terminal that has scrolled away. Adds docs/lane-latency.md, the ledger-derived account of
  where a run's wall-clock actually goes. Migration: none; existing ledger rows keep parsing, the
  reason is appended inside the existing final column.
  **BREAKING:** `orchestrate-lean.sh --attended` is removed, along with its exit code 9. A wrapper that passed the flag now gets the ordinary usage refusal (exit 2), and no path returns 9. The manual two-terminal lane — invoking build-lean and review-lean directly — is unchanged and remains the supported way to drive the lane by hand.

### `intake-toolkit` 4.1.2 → 4.2.0

- **feat(dev-pipeline): P4/P5 get a mechanical counterpart, and 180 measurement rows retire (#648)** (#648)
  `scripts/check-guard-budget.sh` reds a PR whose guard/test shell mass grows with no
  `Guard-mass: +<n> <reason>` commit trailer, replacing PR #645's abandoned committed-ceiling
  design. `.claude/prose-budget.baseline.tsv`, `.claude/prose-budget-shell.baseline.tsv`,
  `tools/selftest-slow-suites.tsv`, `tools/mutation-slow-suites.tsv`,
  `tools/selftest-sweep-baseline.tsv`, and `tools/install-topology-known-red.tsv` are deleted;
  the three suite-timing files are replaced by `tools/selftest-suite-timings.tsv`.
  `prose-budget.sh --update-baseline` is now an accepted no-op. Migration: none — no consumer
  reads the deleted files directly.

### `review-toolkit` 7.2.1 → 7.2.2

- **Three consecutive rounds of panel reviews yielded zero blockers while a third of the panel goes dark (#679)** (#679)
  test-coverage-reviewer and maintainability-reviewer now carry a turn-10 write-by
  deadline, so a dispatch that would have died at the cap emits a partial review naming what it
  could not verify instead of returning nothing. Migration: none.

## v11.0.0

### `design-toolkit` 4.0.1 → 4.0.2

- **Every prose blocking construct now carries a disposition (#625)** (#625)
  prose blockers that only restated a gate's refusal are gone from
  seventeen skills' SKILL.md — the gates are unchanged, and each deletion names
  the gate that already enforced it in docs/prose-blocker-triage.tsv. Four
  copies of the dup-scan rc-2 rule are now one contract held by a LOCKSTEP
  anchor. Migration: none.
  the dup-scan rc-2 guidance no longer tells intake-interviewer to hand nothing
  off while its next line hands the draft over; the shared line now pins only the
  hard-stop and the rc report, and each skill states what does or does not go out.
  Migration: none.

### `dev-pipeline` 10.0.1 → 11.0.0

- **The lean cost block derives its own time fence and session set (#615)** (#615)
  `pipeline-cost-block.sh` gains `--issue <n>`, which derives the time fence
  (first to last timestamped progress row) and the session set (`build_session_set`
  UNION the verdict record's session) rather than taking either from the caller;
  `--start`, `--end` and `--sessions` remain as individual overrides, and an
  underivable fence is a named refusal instead of a plausible default. A set that
  counts the review session retitles its total row "Run total (build + review)".
  `--close-out` writes one `cost-log.jsonl` row per run again, keyed on (ticketKey,
  runId) so a re-entered close-out replaces its own row while a retry under a new run
  id appends; the row carries `byTier` where staged-era rows carried `byLabel`, and no
  row is written on any skip verdict.
  Migration: none. build-lean step 7 now passes `--issue <issue>`, and step 9
  re-computes with `--close-out` and replaces the snapshot in the PR body.
- **build-lean refuses a ticket argument it cannot resolve (#616)** (#616)
  build-lean refuses to start a run on a ticket its caller did not name.
  `entry`/`claim` exit 10 on an absent, malformed, nonexistent or closed ticket,
  on an unreadable tracker, or when a lane-branch checkout names a different one
  (`mark`/`teardown` get that last arm too). Milestone calls are unchanged.
  Migration: none.
- **The Decision Ledger carry-forward is a projection, not a retype (#620)** (#620)
  build-lean's milestone-1 step now names ledger-carry-forward.sh as
  the route for carrying a pre-flight receipt's Decision Ledger into the
  committed spec, instead of leaving the rows to be retyped between two arities
  the lint enforces exactly. ledger-lint.sh is unchanged apart from lockstep
  markers over the empty-form literal the new helper must emit.
  Migration: none.
- **The close-out is a gate command, not a third model session (#627)** (#627)
  the lean lane closes a run out with a gate command instead of a third
  model session. The close-out re-computes the published cost block, writes its
  cross-run corpus row, replaces the stale block in the PR description and posts
  the closing comment, each recorded as its own milestone-5 obligation and
  degrading to met-with-the-skip-named on a host with no telemetry collector.
  `bash G 5` is unchanged and stays a pure verifier.
  Migration: none.
- **An attended session may pause and ask, and a recorded operator answer is what yields (#626)** (#626)
  a gate that exists only because nobody is assumed to be watching can
  now yield to an operator who is. An operator-minted attendance token unlocks
  the affordance to pause and ask instead of reject; the yield itself needs a
  committed per-decision override record quoting the operator's answer, which
  the merge boundary validates. Two consumers ship wired: the scheduler's
  unintaken-ticket reject (now the distinguishable resumable exit 3, and
  acceptable on a recorded override with no re-labelling) and the spec gate's
  unresolved pause-and-ask region.
  Migration: none. Headless behavior is unchanged on both consumers, except that
  the unintaken-ticket preflight reject now exits 3 rather than 2.
  `operator-override.sh record` no longer writes a record it is about
  to refuse — a bad --issue or --gate now leaves the tree untouched.
  Migration: none.
  an attended session refusing on two open regions now prints the
  record command for both, not just the first.
  Migration: none.
- **milestone 3 stops running the full sweep locally, and the supervision stratum goes with it (#621)** (#621)
  milestone 3 now runs its verify lanes inline instead of spawning a detached
  runner, and defers the suites listed in tools/selftest-slow-suites.tsv to CI. The lane
  registry and job ceiling are removed. Migration: a consumer whose test command reads
  LEAN_JOB_CEILING should drop it — the variable is no longer exported. Repos that want a
  bounded local sweep add rows to tools/selftest-slow-suites.tsv; pass --full to
  run-selftests.sh anywhere the whole suite set must run.
  tools/selftest-slow-suites.tsv defers every selftest measured at or above 9s from
  the local milestone-3 check; CI still runs all of them. Migration: none.
  gate-ablation.sh no longer reads a lane registry to exclude in-flight
  runs from the corpus — that registry was retired with milestone 3's supervision
  stratum, and the read had become a permanent silent no-op. --exclude is the
  single exclusion source; name every live lane when you re-cut the pin.
  Migration: an operator regenerating docs/gate-ablation-manifest.tsv must pass
  every in-flight issue id to --exclude. A lane left unnamed is not silently
  absorbed — the next 'gate-ablation.sh emit' exits 3 naming its drifted record.
  **BREAKING:** lean-gate.sh no longer accepts the m3-run subcommand or --m3-token, and LEAN_GATE_M3_NEW_SESSION, LEAN_LANE_REGISTRY, LEAN_LANE_PID, LEAN_JOB_CEILING and LEAN_GATE_WAIT_CEILING_SECS are no longer read. A consumer mapping LEAN_JOB_CEILING onto its own test command's concurrency flag will stop receiving it.
- **fix(dev-pipeline): the override record's issue key is the tracker's shape, not github's (#634)** (#634)
  `operator-override.sh record` and `check` now accept a tracker key of any
  alphanumeric/`.`/`_`/`-` shape, not just digits — so an attended session under a
  non-numeric tracker can resolve a pause-and-ask Open Region with the command the gate
  prints, instead of that command failing as malformed. Migration: none.
- **fix(dev-pipeline): the cost block's issue key is the tracker's shape, not github's (#635)** (#635)
  `pipeline-cost-block.sh --issue` now accepts a tracker key of any
  alphanumeric/`.`/`_`/`-` shape, not just digits — so the lean lane's close-out can publish
  a cost figure under a non-numeric tracker instead of hard-stopping with milestone 5's
  cost-block obligation unmet. Migration: none.
- **Every prose blocking construct now carries a disposition (#625)** (#625)
  prose blockers that only restated a gate's refusal are gone from
  seventeen skills' SKILL.md — the gates are unchanged, and each deletion names
  the gate that already enforced it in docs/prose-blocker-triage.tsv. Four
  copies of the dup-scan rc-2 rule are now one contract held by a LOCKSTEP
  anchor. Migration: none.
  the dup-scan rc-2 guidance no longer tells intake-interviewer to hand nothing
  off while its next line hands the draft over; the shared line now pins only the
  hard-stop and the rc report, and each skill states what does or does not go out.
  Migration: none.

### `intake-toolkit` 4.1.1 → 4.1.2

- **The Decision Ledger carry-forward is a projection, not a retype (#620)** (#620)
  build-lean's milestone-1 step now names ledger-carry-forward.sh as
  the route for carrying a pre-flight receipt's Decision Ledger into the
  committed spec, instead of leaving the rows to be retyped between two arities
  the lint enforces exactly. ledger-lint.sh is unchanged apart from lockstep
  markers over the empty-form literal the new helper must emit.
  Migration: none.
- **fix(intake-toolkit): dup-scan's not-applicable arm is reachable from --issue (#630)** (#630)
  dup-scan.sh under `tracker.type: jira` now exits 0 with its not-applicable
  line when the subject is supplied as `--issue <key>`, instead of failing with
  "--issue takes a number" (rc 2) — which callers read as a hard-stop. Migration: none.
- **Every prose blocking construct now carries a disposition (#625)** (#625)
  prose blockers that only restated a gate's refusal are gone from
  seventeen skills' SKILL.md — the gates are unchanged, and each deletion names
  the gate that already enforced it in docs/prose-blocker-triage.tsv. Four
  copies of the dup-scan rc-2 rule are now one contract held by a LOCKSTEP
  anchor. Migration: none.
  the dup-scan rc-2 guidance no longer tells intake-interviewer to hand nothing
  off while its next line hands the draft over; the shared line now pins only the
  hard-stop and the rc report, and each skill states what does or does not go out.
  Migration: none.

### `second-shift` 8.0.1 → 8.0.2

- **Every prose blocking construct now carries a disposition (#625)** (#625)
  prose blockers that only restated a gate's refusal are gone from
  seventeen skills' SKILL.md — the gates are unchanged, and each deletion names
  the gate that already enforced it in docs/prose-blocker-triage.tsv. Four
  copies of the dup-scan rc-2 rule are now one contract held by a LOCKSTEP
  anchor. Migration: none.
  the dup-scan rc-2 guidance no longer tells intake-interviewer to hand nothing
  off while its next line hands the draft over; the shared line now pins only the
  hard-stop and the rc report, and each skill states what does or does not go out.
  Migration: none.

## v10.0.1

### `audit-toolkit` 4.0.0 → 4.0.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

### `design-toolkit` 4.0.0 → 4.0.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

### `dev-pipeline` 10.0.0 → 10.0.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

### `intake-toolkit` 4.1.0 → 4.1.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

### `review-toolkit` 7.2.0 → 7.2.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

### `second-shift` 8.0.0 → 8.0.1

- **Lockstep pairs are discovered from their markers, not declared twice (#606)** (#606)
  lockstep contract blocks are now discovered from their LOCKSTEP markers
  rather than listed in scripts/lockstep-manifest.tsv, which is deleted. An anchor
  with only one site is now a failure. A marker must occupy its whole line, and a
  subset-of relation is declared on the marker as `superset`/`subset`.
  Migration: none for consumers — the checker is repo-level and ships in no plugin.
  check-lockstep-pairs.sh now refuses loudly when it cannot resolve its own
  directory or its repo root, instead of walking nowhere and reporting a green check.
  Migration: none.

## v10.0.0

### `dev-pipeline` 9.0.1 → 10.0.0

- **feat(dev-pipeline): reconcile the committed lean spec against the pre-flight Decision Ledger at milestone 1 (#592)** (#592)
  milestone 1 now refuses a committed lean spec that drops a pre-flight
  Decision Ledger row whose provenance is `user-answered` or `user-delegated`, or that
  re-decides one without a `DEPARTURE — <reason>` marker carrying a reason. It runs in
  the observe pass, is inert when the ticket has no `<issue>-ledger.md`, spends a fix
  attempt on a refusal and an envfail (never budget) on a receipt it cannot read.
  Migration: a run on a ticket that HAS a pre-flight receipt must carry its
  `user-answered`/`user-delegated` rows into a `## Decision Ledger` table row with the
  same `D-n` id and Resolution text, or mark the row `DEPARTURE — <reason>`. Measured
  over the 27 receipt/spec pairs on disk in this repo, 1 passes as written.
  milestone 1's receipt-reconciliation disclosure is no longer dropped when the
  design lane is armed or disarmed — consumers with a `design.provider` configured now
  see the carry-forward counts on the pass line in every design state.
  Migration: none.
- **feat(dev-pipeline)!: milestone 3 no longer runs the diff-scoped mutation sweep PR CI already runs (#595)** (#595)
  milestone 3 no longer runs a repo-carried tools/mutation-sweep.sh.
  The lane made the identical diff-scoped invocation a PR CI job already makes,
  so it was duplicated work blocking an interactive build session. `gates.mutation`
  is unchanged and still declares intent for config-grill/doctor advisories.
  Migration: a consumer repo carrying its own tools/mutation-sweep.sh must wire
  its own nightly or PR sweep; the shipped gate no longer runs one.
  **BREAKING:** lean-gate.sh milestone 3 no longer executes a repo-carried tools/mutation-sweep.sh, and no longer emits the "mutation sweep SKIPPED" notice or its progress row.
- **feat(dev-pipeline): resolve model tiers through config instead of vendor tokens (#596)** (#596)
  model tiers are now vendor-neutral. Dispatch sites name a tier and
  reviewers.tierMap resolves it, so a repo whose subscription lacks a model class
  retargets it in one config line instead of forking the plugin; reviewers.modelOverrides
  additionally accepts a tier name, and the structured-emitter sink is overridable for
  the first time. Defaults are unchanged - every tier resolves to the model dispatched
  before this change. Migration: none, configVersion stays 2.
- **fix(dev-pipeline): lean-gate refuses to grade a tree that is not the lane's (#599)** (#599)
  lean-gate.sh's milestone (`1`-`5`, `all`) and review-role (`delta`,
  `verdict`) subcommands now refuse with exit 9 when the checkout they run in is
  not on the run's lane branch, instead of grading whatever tree they landed in
  and reporting a confident verdict about it. A detached HEAD refuses on the same
  path. `LEAN_GATE_ANY_TREE=1` disarms the assertion and announces that it did.
  Migration: none — the main-checkout roles are unguarded, so no scheduler or
  operator call site changes; a manual `bash G <n> <issue>` typed from the shared
  checkout, which used to answer about `main`, now says so.
- **A base advance no longer voids a verdict whose reviewed lines never moved (#601)** (#601)
  a base merge that alters none of the PR's own added or removed lines
  no longer invalidates its approve verdict — milestone 4 and pr-gates both say
  which of the branch's lines they judged, and let the verdict stand when they
  cannot name one. run-lean no longer spawns a review round against an unmoved
  head after its own close-out tore the lane worktree down.
  Migration: none — no verdict-record key changes and no record needs a re-stamp.
- **perf-retro: derive the lean timing profile from milestone timestamps (#603)** (#603)
  `retro-corpus.sh timing` derives a per-run timing profile from the lean
  progress records, and perf-retro now produces a populated profile on a lean-only
  corpus instead of triaging on fields no run writes.
  Migration: none.

### `intake-toolkit` 4.0.0 → 4.1.0

- **feat(dev-pipeline): reconcile the committed lean spec against the pre-flight Decision Ledger at milestone 1 (#592)** (#592)
  milestone 1 now refuses a committed lean spec that drops a pre-flight
  Decision Ledger row whose provenance is `user-answered` or `user-delegated`, or that
  re-decides one without a `DEPARTURE — <reason>` marker carrying a reason. It runs in
  the observe pass, is inert when the ticket has no `<issue>-ledger.md`, spends a fix
  attempt on a refusal and an envfail (never budget) on a receipt it cannot read.
  Migration: a run on a ticket that HAS a pre-flight receipt must carry its
  `user-answered`/`user-delegated` rows into a `## Decision Ledger` table row with the
  same `D-n` id and Resolution text, or mark the row `DEPARTURE — <reason>`. Measured
  over the 27 receipt/spec pairs on disk in this repo, 1 passes as written.
  milestone 1's receipt-reconciliation disclosure is no longer dropped when the
  design lane is armed or disarmed — consumers with a `design.provider` configured now
  see the carry-forward counts on the pass line in every design state.
  Migration: none.

### `review-toolkit` 7.1.0 → 7.2.0

- **feat(dev-pipeline): resolve model tiers through config instead of vendor tokens (#596)** (#596)
  model tiers are now vendor-neutral. Dispatch sites name a tier and
  reviewers.tierMap resolves it, so a repo whose subscription lacks a model class
  retargets it in one config line instead of forking the plugin; reviewers.modelOverrides
  additionally accepts a tier name, and the structured-emitter sink is overridable for
  the first time. Defaults are unchanged - every tier resolves to the model dispatched
  before this change. Migration: none, configVersion stays 2.

### `second-shift` 7.0.1 → 8.0.0

- **feat(dev-pipeline)!: milestone 3 no longer runs the diff-scoped mutation sweep PR CI already runs (#595)** (#595)
  milestone 3 no longer runs a repo-carried tools/mutation-sweep.sh.
  The lane made the identical diff-scoped invocation a PR CI job already makes,
  so it was duplicated work blocking an interactive build session. `gates.mutation`
  is unchanged and still declares intent for config-grill/doctor advisories.
  Migration: a consumer repo carrying its own tools/mutation-sweep.sh must wire
  its own nightly or PR sweep; the shipped gate no longer runs one.
  **BREAKING:** lean-gate.sh milestone 3 no longer executes a repo-carried tools/mutation-sweep.sh, and no longer emits the "mutation sweep SKIPPED" notice or its progress row.
- **feat(dev-pipeline): resolve model tiers through config instead of vendor tokens (#596)** (#596)
  model tiers are now vendor-neutral. Dispatch sites name a tier and
  reviewers.tierMap resolves it, so a repo whose subscription lacks a model class
  retargets it in one config line instead of forking the plugin; reviewers.modelOverrides
  additionally accepts a tier name, and the structured-emitter sink is overridable for
  the first time. Defaults are unchanged - every tier resolves to the model dispatched
  before this change. Migration: none, configVersion stays 2.

## v9.1.0

### `dev-pipeline` 9.0.0 → 9.0.1

- **fix(second-shift): close every live cause of the nightly sweep's redness, at the site (#588)** (#588)
  the shipped doctor selftest's lean-progress newest-file case no
  longer passes when the selection is inverted, and run-lean's terminal-taxonomy
  comment no longer registers as a mutation site for two operators.
  Migration: none.

### `review-toolkit` 7.0.0 → 7.1.0

- **feat(second-shift): comment lines stop enumerating as mutation sites (#589)** (#589)

### `second-shift` 7.0.0 → 7.0.1

- **fix(second-shift): close every live cause of the nightly sweep's redness, at the site (#588)** (#588)
  the shipped doctor selftest's lean-progress newest-file case no
  longer passes when the selection is inverted, and run-lean's terminal-taxonomy
  comment no longer registers as a mutation site for two operators.
  Migration: none.

## v9.0.0

### `design-toolkit` 3.0.0 → 4.0.0

- **feat(dev-pipeline)!: retire the five #348-stranded engines and the config keys they read (#584)** (#584)
  the four #348-stranded Workflow engines (design-sync, figma, mutation-gate,
  unit-tests) and pipeline-cost-block.sh's unreachable stateful branch are removed; the
  design-faithful/figma-faithful skills and the advisory unit-test-mutation-reviewer
  are unaffected.
  Migration: delete commands.<repo>.unitTestScope and commands.<repo>.testFile from
  your config — config-lint now rejects both by name (docs/migrations/v1-to-v2.md,
  'Dead-key removal (#574)'). gates.mutation and the repo-carried tools/mutation-sweep.sh
  seam are unchanged.
  BREAKING — the config keys commands.<repo>.unitTestScope and
  commands.<repo>.testFile are removed; config-lint now rejects each by name
  with a pointer to docs/migrations/v1-to-v2.md (fail closed). Their only
  functional reader, the co-located unit-test mutation engine
  (workflows/mutation-gate.mjs), lost its dispatcher when #348 deleted the
  staged lane, so a configured unitTestScope armed nothing — the same
  silently-disarmed-gate class as the #569 retirement.
  Migration: delete unitTestScope and testFile from
  .claude/second-shift.config.json. No configVersion bump, and no drop-in
  replacement: the mutation seam is repo-carried — ship an executable
  tools/mutation-sweep.sh at your repo root and lean-gate milestone 3 runs it;
  gates.mutation remains the declared intent and is unchanged. testFile was the
  retired engine's per-spec runner template; a repo-carried sweep invokes its
  own runner however it chooses.
  **BREAKING:** commands.<repo>.unitTestScope and commands.<repo>.testFile are removed from the config schema and rejected by name; the four Workflow engines and the pipeline-cost-block.sh stateful mode (positional-issue invocation) are removed from the shipped plugin.

### `dev-pipeline` 8.0.0 → 9.0.0

- **feat(dev-pipeline)!: retire the five #348-stranded engines and the config keys they read (#584)** (#584)
  the four #348-stranded Workflow engines (design-sync, figma, mutation-gate,
  unit-tests) and pipeline-cost-block.sh's unreachable stateful branch are removed; the
  design-faithful/figma-faithful skills and the advisory unit-test-mutation-reviewer
  are unaffected.
  Migration: delete commands.<repo>.unitTestScope and commands.<repo>.testFile from
  your config — config-lint now rejects both by name (docs/migrations/v1-to-v2.md,
  'Dead-key removal (#574)'). gates.mutation and the repo-carried tools/mutation-sweep.sh
  seam are unchanged.
  BREAKING — the config keys commands.<repo>.unitTestScope and
  commands.<repo>.testFile are removed; config-lint now rejects each by name
  with a pointer to docs/migrations/v1-to-v2.md (fail closed). Their only
  functional reader, the co-located unit-test mutation engine
  (workflows/mutation-gate.mjs), lost its dispatcher when #348 deleted the
  staged lane, so a configured unitTestScope armed nothing — the same
  silently-disarmed-gate class as the #569 retirement.
  Migration: delete unitTestScope and testFile from
  .claude/second-shift.config.json. No configVersion bump, and no drop-in
  replacement: the mutation seam is repo-carried — ship an executable
  tools/mutation-sweep.sh at your repo root and lean-gate milestone 3 runs it;
  gates.mutation remains the declared intent and is unchanged. testFile was the
  retired engine's per-spec runner template; a repo-carried sweep invokes its
  own runner however it chooses.
  **BREAKING:** commands.<repo>.unitTestScope and commands.<repo>.testFile are removed from the config schema and rejected by name; the four Workflow engines and the pipeline-cost-block.sh stateful mode (positional-issue invocation) are removed from the shipped plugin.
- **feat(dev-pipeline): milestone 3 hands its lane commands the selftest pass cache (#586)** (#586)
  `lean-gate.sh` milestone 3 exports `LEAN_SELFTEST_CACHE_DIR`, and
  `tools/run-selftests.sh` activates #448's pass cache from it, so a milestone re-evaluated on
  an unchanged head serves every declared-inputs suite instead of re-running it. Argv
  `--cache-dir` still wins and an unset variable changes nothing, so both CI lanes and the
  nightly leg are unaffected; `LEAN_SELFTEST_CACHE=0` runs the lane cold. Migration: none.

### `review-toolkit` 6.0.0 → 7.0.0

- **feat(dev-pipeline)!: retire the five #348-stranded engines and the config keys they read (#584)** (#584)
  the four #348-stranded Workflow engines (design-sync, figma, mutation-gate,
  unit-tests) and pipeline-cost-block.sh's unreachable stateful branch are removed; the
  design-faithful/figma-faithful skills and the advisory unit-test-mutation-reviewer
  are unaffected.
  Migration: delete commands.<repo>.unitTestScope and commands.<repo>.testFile from
  your config — config-lint now rejects both by name (docs/migrations/v1-to-v2.md,
  'Dead-key removal (#574)'). gates.mutation and the repo-carried tools/mutation-sweep.sh
  seam are unchanged.
  BREAKING — the config keys commands.<repo>.unitTestScope and
  commands.<repo>.testFile are removed; config-lint now rejects each by name
  with a pointer to docs/migrations/v1-to-v2.md (fail closed). Their only
  functional reader, the co-located unit-test mutation engine
  (workflows/mutation-gate.mjs), lost its dispatcher when #348 deleted the
  staged lane, so a configured unitTestScope armed nothing — the same
  silently-disarmed-gate class as the #569 retirement.
  Migration: delete unitTestScope and testFile from
  .claude/second-shift.config.json. No configVersion bump, and no drop-in
  replacement: the mutation seam is repo-carried — ship an executable
  tools/mutation-sweep.sh at your repo root and lean-gate milestone 3 runs it;
  gates.mutation remains the declared intent and is unchanged. testFile was the
  retired engine's per-spec runner template; a repo-carried sweep invokes its
  own runner however it chooses.
  **BREAKING:** commands.<repo>.unitTestScope and commands.<repo>.testFile are removed from the config schema and rejected by name; the four Workflow engines and the pipeline-cost-block.sh stateful mode (positional-issue invocation) are removed from the shipped plugin.

### `second-shift` 6.0.0 → 7.0.0

- **feat(dev-pipeline)!: retire the five #348-stranded engines and the config keys they read (#584)** (#584)
  the four #348-stranded Workflow engines (design-sync, figma, mutation-gate,
  unit-tests) and pipeline-cost-block.sh's unreachable stateful branch are removed; the
  design-faithful/figma-faithful skills and the advisory unit-test-mutation-reviewer
  are unaffected.
  Migration: delete commands.<repo>.unitTestScope and commands.<repo>.testFile from
  your config — config-lint now rejects both by name (docs/migrations/v1-to-v2.md,
  'Dead-key removal (#574)'). gates.mutation and the repo-carried tools/mutation-sweep.sh
  seam are unchanged.
  BREAKING — the config keys commands.<repo>.unitTestScope and
  commands.<repo>.testFile are removed; config-lint now rejects each by name
  with a pointer to docs/migrations/v1-to-v2.md (fail closed). Their only
  functional reader, the co-located unit-test mutation engine
  (workflows/mutation-gate.mjs), lost its dispatcher when #348 deleted the
  staged lane, so a configured unitTestScope armed nothing — the same
  silently-disarmed-gate class as the #569 retirement.
  Migration: delete unitTestScope and testFile from
  .claude/second-shift.config.json. No configVersion bump, and no drop-in
  replacement: the mutation seam is repo-carried — ship an executable
  tools/mutation-sweep.sh at your repo root and lean-gate milestone 3 runs it;
  gates.mutation remains the declared intent and is unchanged. testFile was the
  retired engine's per-spec runner template; a repo-carried sweep invokes its
  own runner however it chooses.
  **BREAKING:** commands.<repo>.unitTestScope and commands.<repo>.testFile are removed from the config schema and rejected by name; the four Workflow engines and the pipeline-cost-block.sh stateful mode (positional-issue invocation) are removed from the shipped plugin.

## v8.0.0

### `audit-toolkit` 3.0.0 → 4.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.

### `design-toolkit` 2.2.1 → 3.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.

### `dev-pipeline` 7.0.0 → 8.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.
- **feat(second-shift): delta-aware consumer CI guard — the verdict-record push re-runs the whole lane, and can cancel the code commit's run (#576)** (#576)
  /second-shift:onboard now emits a third optional CI pair —
  .github/workflows/second-shift-delta-guard.yml plus
  .claude/tools/second-shift-delta-guard.sh — which lets a consumer skip its
  heavy jobs on the lean lane's docs-only verdict-record commit, but only
  against a completed successful run on the parent SHA. Read-only, and inert
  until the consumer wires its own jobs to the guard's skip output. Onboarding
  guidance also now states the pull_request concurrency rule: do not key
  cancel-in-progress: true bare on the ref.
  Migration: none — existing consumers are unaffected until they re-run
  /second-shift:onboard or copy the pair by hand.
- **feat(dev-pipeline): lint the committed Decision Ledger's provenance at milestone 1 (#573)** (#573)
  lean-gate.sh milestone 1 now lints a committed spec's Decision
  Ledger provenance column against the interviewing-baseline enum when the
  section is present, refusing an invented value (e.g. "issue-specified")
  that previously reached a committed artifact undetected. Reuses
  intake-toolkit's ledger-lint.sh; no new artifact, no schema change.
  Migration: none.
  none — the trailer on 0c09b21 already carries this PR's consumer-visible
  change; this commit only discharges round 1's review blockers on it.
  none — round-1 blocker follow-through on 0c09b21's consumer-visible
  change; this commit only re-greens the guard accounting 813a275 disturbed.

### `intake-toolkit` 3.0.0 → 4.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.

### `review-toolkit` 5.0.0 → 6.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.

### `second-shift` 5.0.0 → 6.0.0

- **fix(dev-pipeline)!: delete the staged-lane residue #348 left behind, and the dead checks that outlived it (#577)** (#577)
  pipeline-doctor no longer reports a permanent FAIL for the retired plan-lint
  gate, and no longer probes for the retired visual-capture substrate; preflight no longer
  emits an unreachable-lane warning for an inert lane the lean gate does not have.
  intake-orchestrator no longer promises an automatic promotion reminder that nothing
  writes.
  Migration: the staged-run readers `tools/stage-times.sh` and `tools/stage-envelopes.sh`
  and the `state-schema.md` reference are removed, along with perf-retro's per-stage timing
  profile. They only ever read staged-lane state files, which no lane has written since
  #348.
  docs/extending.md no longer claims preflight.sh reads
  stageParams.inertPattern — it does not, and the key cannot cause a verify-lane skip
  under the lean gate. pipeline-doctor's selftest now asserts its
  every-delegate-exists invariant over all three of the doctor's delegation forms, so
  a deleted suite behind a $PLUGIN_DIR invocation is caught rather than shipped as a
  permanent FAIL.
  Migration: none.
  docs/extending.md and is-inert-diff.sh now state that
  stageParams.inertPattern has no runtime consumer, instead of naming callers that
  do not read it. pipeline-doctor's every-delegate-exists invariant now also fails
  when a delegation form has no arm, or when an arm is dropped, so the guard cannot
  silently narrow.
  Migration: none.
  **BREAKING:** `plugins/dev-pipeline/state-schema.md`, `tools/stage-times.sh` and `tools/stage-envelopes.sh` are removed from the shipped plugin, and perf-retro no longer produces a per-stage timing profile.
- **feat(second-shift): delta-aware consumer CI guard — the verdict-record push re-runs the whole lane, and can cancel the code commit's run (#576)** (#576)
  /second-shift:onboard now emits a third optional CI pair —
  .github/workflows/second-shift-delta-guard.yml plus
  .claude/tools/second-shift-delta-guard.sh — which lets a consumer skip its
  heavy jobs on the lean lane's docs-only verdict-record commit, but only
  against a completed successful run on the parent SHA. Read-only, and inert
  until the consumer wires its own jobs to the guard's skip output. Onboarding
  guidance also now states the pull_request concurrency rule: do not key
  cancel-in-progress: true bare on the ref.
  Migration: none — existing consumers are unaffected until they re-run
  /second-shift:onboard or copy the pair by hand.

## v7.0.0

### `dev-pipeline` 6.0.0 → 7.0.0

- **feat(dev-pipeline)!: retire the EP-6/EP-7/EP-8 config keys — a kept dead key silently disarms a consumer's blocking gate (#571)** (#571)
  the config keys stageWorkflows (EP-6), implementDelegates (EP-7) and
  planGates (EP-8) are removed; config-lint now rejects each by name.
  check-extensions.sh no longer reads the consumer config at all — its EP-3
  manifest lint is unchanged — and /second-shift:onboard no longer raises the
  T1.extension-points grill row.
  Migration: delete stageWorkflows, implementDelegates and planGates from
  .claude/second-shift.config.json. No configVersion bump. There is no drop-in
  replacement: a blocking check of your own is commands.<repo>.extraLanes; a
  plan gate has no lean equivalent. See docs/migrations/v1-to-v2.md.

### `second-shift` 4.0.0 → 5.0.0

- **feat(dev-pipeline)!: retire the EP-6/EP-7/EP-8 config keys — a kept dead key silently disarms a consumer's blocking gate (#571)** (#571)
  the config keys stageWorkflows (EP-6), implementDelegates (EP-7) and
  planGates (EP-8) are removed; config-lint now rejects each by name.
  check-extensions.sh no longer reads the consumer config at all — its EP-3
  manifest lint is unchanged — and /second-shift:onboard no longer raises the
  T1.extension-points grill row.
  Migration: delete stageWorkflows, implementDelegates and planGates from
  .claude/second-shift.config.json. No configVersion bump. There is no drop-in
  replacement: a blocking check of your own is commands.<repo>.extraLanes; a
  plan gate has no lean equivalent. See docs/migrations/v1-to-v2.md.

## v6.0.0

### `audit-toolkit` 2.1.2 → 3.0.0

- **feat(dev-pipeline)!: delete stage choreography from main (#568)** (#568)
  the staged `run` lane and its stage choreography are removed; the lean
  lane (`/dev-pipeline:run-lean`) is the only lane. Shared tooling moved out of
  `skills/run/` to the plugin root: `tools/*` and `workflows/*`.
  Migration: consumers still running the staged lane pin the marketplace to
  **v5.2.2**, the last stage-carrying release (re-confirm at merge that no later
  release has landed — the pin must be the last release preceding this one).
  Consumers whose CI hardcodes the config-lint path must re-point
  `plugins/dev-pipeline/skills/run/tools/config-lint.sh` to
  `plugins/dev-pipeline/tools/config-lint.sh`; the shipped consumer CI template
  (`second-shift-ci-check.sh`) treats a moved linter path as drift by design.
  /second-shift:doctor --report now carries the lean lane's progress-record
  tail in its pipeline-state excerpt, so the abort issue form's bundle claim holds; a
  pre-lean JSON state file is still projected as before. The config schema and the
  extending/config-schema guides now name each key's real reader instead of a deleted
  stage, and the three inert extension points say so in the schema a consumer's editor
  renders. Migration: none.
  **BREAKING:** the staged `run` lane is deleted. `/dev-pipeline:run` no longer exists, and every tool shipped under `plugins/dev-pipeline/skills/run/` has moved to `plugins/dev-pipeline/{tools,workflows}/`. Consumers that pinned the lane keep it via the marketplace pin named below.

### `dev-pipeline` 5.2.2 → 6.0.0

- **feat(dev-pipeline)!: delete stage choreography from main (#568)** (#568)
  the staged `run` lane and its stage choreography are removed; the lean
  lane (`/dev-pipeline:run-lean`) is the only lane. Shared tooling moved out of
  `skills/run/` to the plugin root: `tools/*` and `workflows/*`.
  Migration: consumers still running the staged lane pin the marketplace to
  **v5.2.2**, the last stage-carrying release (re-confirm at merge that no later
  release has landed — the pin must be the last release preceding this one).
  Consumers whose CI hardcodes the config-lint path must re-point
  `plugins/dev-pipeline/skills/run/tools/config-lint.sh` to
  `plugins/dev-pipeline/tools/config-lint.sh`; the shipped consumer CI template
  (`second-shift-ci-check.sh`) treats a moved linter path as drift by design.
  /second-shift:doctor --report now carries the lean lane's progress-record
  tail in its pipeline-state excerpt, so the abort issue form's bundle claim holds; a
  pre-lean JSON state file is still projected as before. The config schema and the
  extending/config-schema guides now name each key's real reader instead of a deleted
  stage, and the three inert extension points say so in the schema a consumer's editor
  renders. Migration: none.
  **BREAKING:** the staged `run` lane is deleted. `/dev-pipeline:run` no longer exists, and every tool shipped under `plugins/dev-pipeline/skills/run/` has moved to `plugins/dev-pipeline/{tools,workflows}/`. Consumers that pinned the lane keep it via the marketplace pin named below.

### `intake-toolkit` 2.3.5 → 3.0.0

- **feat(dev-pipeline)!: delete stage choreography from main (#568)** (#568)
  the staged `run` lane and its stage choreography are removed; the lean
  lane (`/dev-pipeline:run-lean`) is the only lane. Shared tooling moved out of
  `skills/run/` to the plugin root: `tools/*` and `workflows/*`.
  Migration: consumers still running the staged lane pin the marketplace to
  **v5.2.2**, the last stage-carrying release (re-confirm at merge that no later
  release has landed — the pin must be the last release preceding this one).
  Consumers whose CI hardcodes the config-lint path must re-point
  `plugins/dev-pipeline/skills/run/tools/config-lint.sh` to
  `plugins/dev-pipeline/tools/config-lint.sh`; the shipped consumer CI template
  (`second-shift-ci-check.sh`) treats a moved linter path as drift by design.
  /second-shift:doctor --report now carries the lean lane's progress-record
  tail in its pipeline-state excerpt, so the abort issue form's bundle claim holds; a
  pre-lean JSON state file is still projected as before. The config schema and the
  extending/config-schema guides now name each key's real reader instead of a deleted
  stage, and the three inert extension points say so in the schema a consumer's editor
  renders. Migration: none.
  **BREAKING:** the staged `run` lane is deleted. `/dev-pipeline:run` no longer exists, and every tool shipped under `plugins/dev-pipeline/skills/run/` has moved to `plugins/dev-pipeline/{tools,workflows}/`. Consumers that pinned the lane keep it via the marketplace pin named below.

### `review-toolkit` 4.2.1 → 5.0.0

- **feat(dev-pipeline)!: delete stage choreography from main (#568)** (#568)
  the staged `run` lane and its stage choreography are removed; the lean
  lane (`/dev-pipeline:run-lean`) is the only lane. Shared tooling moved out of
  `skills/run/` to the plugin root: `tools/*` and `workflows/*`.
  Migration: consumers still running the staged lane pin the marketplace to
  **v5.2.2**, the last stage-carrying release (re-confirm at merge that no later
  release has landed — the pin must be the last release preceding this one).
  Consumers whose CI hardcodes the config-lint path must re-point
  `plugins/dev-pipeline/skills/run/tools/config-lint.sh` to
  `plugins/dev-pipeline/tools/config-lint.sh`; the shipped consumer CI template
  (`second-shift-ci-check.sh`) treats a moved linter path as drift by design.
  /second-shift:doctor --report now carries the lean lane's progress-record
  tail in its pipeline-state excerpt, so the abort issue form's bundle claim holds; a
  pre-lean JSON state file is still projected as before. The config schema and the
  extending/config-schema guides now name each key's real reader instead of a deleted
  stage, and the three inert extension points say so in the schema a consumer's editor
  renders. Migration: none.
  **BREAKING:** the staged `run` lane is deleted. `/dev-pipeline:run` no longer exists, and every tool shipped under `plugins/dev-pipeline/skills/run/` has moved to `plugins/dev-pipeline/{tools,workflows}/`. Consumers that pinned the lane keep it via the marketplace pin named below.

### `second-shift` 3.1.6 → 4.0.0

- **feat(dev-pipeline)!: delete stage choreography from main (#568)** (#568)
  the staged `run` lane and its stage choreography are removed; the lean
  lane (`/dev-pipeline:run-lean`) is the only lane. Shared tooling moved out of
  `skills/run/` to the plugin root: `tools/*` and `workflows/*`.
  Migration: consumers still running the staged lane pin the marketplace to
  **v5.2.2**, the last stage-carrying release (re-confirm at merge that no later
  release has landed — the pin must be the last release preceding this one).
  Consumers whose CI hardcodes the config-lint path must re-point
  `plugins/dev-pipeline/skills/run/tools/config-lint.sh` to
  `plugins/dev-pipeline/tools/config-lint.sh`; the shipped consumer CI template
  (`second-shift-ci-check.sh`) treats a moved linter path as drift by design.
  /second-shift:doctor --report now carries the lean lane's progress-record
  tail in its pipeline-state excerpt, so the abort issue form's bundle claim holds; a
  pre-lean JSON state file is still projected as before. The config schema and the
  extending/config-schema guides now name each key's real reader instead of a deleted
  stage, and the three inert extension points say so in the schema a consumer's editor
  renders. Migration: none.
  **BREAKING:** the staged `run` lane is deleted. `/dev-pipeline:run` no longer exists, and every tool shipped under `plugins/dev-pipeline/skills/run/` has moved to `plugins/dev-pipeline/{tools,workflows}/`. Consumers that pinned the lane keep it via the marketplace pin named below.

## v5.2.2

### `dev-pipeline` 5.2.1 → 5.2.2

- **fix(dev-pipeline): the pause-and-ask guard reads the pre-flight ledger too (#556)** (#556)
  milestone 1's pause-and-ask guard now also reads the pre-flight
  ledger's Open Regions table (in addition to the issue body), and is now
  reachable under tracker.type: jira via the ledger. New seam: --ledger-file.
  Migration: none.
- **Teardown and inflight account for every worktree on the lane branch (#559)** (#559)
  cmd_teardown and cmd_inflight in the lean-gate now account for every
  worktree registered on the lane branch instead of only the first
  git-worktree-list match, so a review session's own checkout no longer orphans
  the build tree (or vice versa) and no longer hides in-flight work behind a
  clean sibling. Migration: none.
- **prose-budget.sh measures shell comment density, so the lane's guards stop growing unwatched (#561)** (#561)
  prose-budget.sh now ratchets shell comment density alongside markdown
  size, with its own baseline at .claude/prose-budget-shell.baseline.tsv, a
  PROSE_SHELL_TOLERANCE_PP tolerance in percentage points, and a nightly
  prose-budget job. pipeline-doctor.sh gains an arm per shell failure state.
  Migration: run 'prose-budget.sh --update-baseline' once per repo to snapshot
  the shell baseline; without it every shell file reports NEW and warns.
  pipeline-doctor no longer reports "prose-budget: nothing to measure" in a repo
  where the shell ratchet did measure files — the shape of every consumer whose skills and
  agents come from the plugin cache.
  Migration: none.

## v5.2.1

### `dev-pipeline` 5.2.0 → 5.2.1

- **Every phase boundary infers completion from exit 0 instead of asserting terminal state (#548)** (#548)
  the lean scheduler now names each terminal state with a stable slug, refuses to
  hand a review a PR whose remote head is missing work the build session left behind,
  continues a partially finished close-out once, and skips the review on a head that
  already carries an approve. Milestone 5 reports the closing comment and the exit
  artifacts as separate obligations, and teardown records its own outcome.
  Migration: none.

### `intake-toolkit` 2.3.4 → 2.3.5

- **intake: plan-interview elicits the product surface, and the receipt proves it (#507)** (#507)
  plan-interview leads its materiality list with product/UX
  categories and enumerates the surfaces a ticket implies, each decided or
  explicitly scoped out. Intake receipts carry a mandated
  `## Surface Inventory` section, enforced by `ledger-lint.sh --receipt`;
  in-plan Decision Ledgers are unaffected. Batch-blessing is named as a
  prohibited interview move, and design-handoff presence is checked before
  the intake router dispatches.
  Migration: an existing intake receipt needs a `## Surface Inventory`
  section — rows, or the empty form
  `No user-visible surface — this change renders nothing a user reads.`
  `intake-orchestrator` and `intake-interviewer` now describe the intake
  receipt's mandated `## Surface Inventory` section, so `intake-orchestrator`'s Receipt
  Exit Gate passes on the shape it prescribes.
  Migration: none.

## v5.2.0

### `dev-pipeline` 5.1.0 → 5.2.0

- **feat(dev-pipeline): signal-killed suites no longer orphan their fixtures, and same-issue progress writes are atomic (#540)** (#540)
  milestone-3 sweeps no longer red on fixture litter left by a
  signal-killed suite, and concurrent same-issue gate calls no longer write
  duplicate satisfied rows. lean-gate.sh now announces its resolved config
  path on stderr for every subcommand except progress.
  Migration: none.
  the lean gate's fixture reaper no longer deletes a running suite's working
  directory on platforms whose `ps` renders start times without trailing padding, and a
  concurrent same-issue progress write can no longer drop a recorded fix attempt.
  Migration: none.
  the mutation sweep's warning summary no longer tells you to shrink
  the baseline when the warning was not about the baseline.
  Migration: none.
- **An infrastructure kill is told apart from an idle session (#545)** (#545)
  a lean run whose milestone-3 sweep is killed by infrastructure no longer
  stops with its continuations unspent, and no longer spends a fix attempt on a
  verdict nothing produced. tools/run-selftests.sh exits 3 when every failing suite
  died without writing a verdict; lean-gate.sh milestone 3 reads that from any verify
  lane as 'nothing was evaluated'.
  Migration: a consumer whose lint/typecheck/test/extraLanes command already exits 3
  for a genuine failure should change it to any other non-zero code — see
  docs/config-schema.md.
- **The milestone-3 runner can outlive the turn that launched it (#547)** (#547)
  milestone 3's detached evaluation can now be spawned in its own
  session, behind `LEAN_GATE_M3_NEW_SESSION=1`, so it survives the turn boundary
  that used to kill it in a headless build child; teardown reaps that runner, and
  the infrastructure-death read counts a surviving one as recoverable.
  Migration: none — unset, the seam leaves the shipped shape unchanged. A
  scheduler comparing the `progress --infra` token across a gate upgrade will see
  the token space move from `m3infra-v1:` to `m3infra-v2:` once and route that
  spawn as an infrastructure death.

## v5.1.0

### `audit-toolkit` 2.1.1 → 2.1.2

- **fix: assertion pipelines read a matching grep as a miss under pipefail (#522)** (#522)
  gate, hook and lint predicates no longer read a matching `grep -q` as a
  miss when the producing `printf` takes SIGPIPE under `pipefail`, which could flip
  a verdict or skip a check at random.
  Migration: none.

### `dev-pipeline` 5.0.0 → 5.1.0

- **fix: assertion pipelines read a matching grep as a miss under pipefail (#522)** (#522)
  gate, hook and lint predicates no longer read a matching `grep -q` as a
  miss when the producing `printf` takes SIGPIPE under `pipefail`, which could flip
  a verdict or skip a check at random.
  Migration: none.
- **The lean scheduler's re-entry admission, composed to a terminal write (#521)** (#521)
  the shipped liveness suite now composes the lean lane's scheduler end
  to end, so a regression in preflight's re-entry admission fails a scenario
  rather than only a component checked against itself.
  Migration: none.
- **The lean lane re-checks its own premise before every build spawn (#534)** (#534)
  /dev-pipeline:run-lean now stops a run whose premise expired while it was
  in flight — exit 7, distinct from a phase failure's 1 — when the ticket has closed or
  the base has moved into files the branch is also editing. Detection only: nothing is
  rebased or reverted, and the worktree and claim are left in place.
  Migration: none.
- **The green gate outlives the turn that started it (#535)** (#535)
  build-lean's milestone-3 green gate now runs as a detached process the
  gate call blocks on, so a reaped or timed-out call rejoins the same evaluation
  instead of abandoning it or starting a second. New exit code 7 means the
  evaluation did not complete (dead runner, or the 3600s
  LEAN_GATE_WAIT_CEILING_SECS ceiling) — it charges no fix attempt and the remedy
  is to re-invoke. Migration: none.
  a milestone-3 call that joins a running evaluation can no longer be ended by
  an exit code some earlier evaluation stamped, which on a reused pid returned a stale
  verdict instantly; and a completed evaluation no longer leaves its pid record behind.
  Migration: none.
  a milestone-3 call no longer joins a runner whose own evaluation has
  already finished — after a ceiling breach or a reaped waiter, the leftover pid
  record and the marker that launch stamped share a token, and joining them
  returned a previous evaluation's exit code instantly on a reused pid. Such a
  call now re-evaluates the tree instead.
  Migration: none.
- **feat(dev-pipeline): a lean lane sizes its milestone-3 sweep to its share of the machine (#536)** (#536)
  concurrent lean lanes no longer each size their verification sweep to
  the whole machine. The build gate now counts live lanes and hands each one a
  job ceiling, announced on milestone-3 output. A consumer whose test command
  reads LEAN_JOB_CEILING gets the benefit; one that ignores it is unaffected.
  Migration: none.
- **A dead call stops reading as a negative result (#538)** (#538)
  a failed shell call is no longer reported as a genuine negative result.
  `detect.sh` leaves the tracker ambiguous when `claude mcp list` cannot be read
  instead of electing github; `pipeline-doctor.sh` reports an unprobeable gh or MCP as
  UNKNOWN rather than absent; and lean-gate's milestone 1 treats an unreadable issue as
  an environment error (rc 2) that spends no fix budget, where it used to charge a fix
  attempt. Migration: none.

### `intake-toolkit` 2.3.3 → 2.3.4

- **fix: assertion pipelines read a matching grep as a miss under pipefail (#522)** (#522)
  gate, hook and lint predicates no longer read a matching `grep -q` as a
  miss when the producing `printf` takes SIGPIPE under `pipefail`, which could flip
  a verdict or skip a check at random.
  Migration: none.
- **Intake scans for duplicates before a ticket becomes eligible to run (#523)** (#523)
  every intake exit now scans a new ticket against the open queue —
  including tickets already claimed for a build — and reports likely duplicates
  for the operator to judge. A scan that cannot run (unauthenticated, offline)
  hard-stops intake instead of labeling the ticket.
  Migration: none.
  intake's duplicate scan now runs on each sub-issue a decomposition
  creates, not only on the parent it strips the queue label from — so a slice
  can no longer reach the queue unscanned.
  Migration: none.

### `review-toolkit` 4.2.0 → 4.2.1

- **fix: assertion pipelines read a matching grep as a miss under pipefail (#522)** (#522)
  gate, hook and lint predicates no longer read a matching `grep -q` as a
  miss when the producing `printf` takes SIGPIPE under `pipefail`, which could flip
  a verdict or skip a check at random.
  Migration: none.

### `second-shift` 3.1.5 → 3.1.6

- **fix: assertion pipelines read a matching grep as a miss under pipefail (#522)** (#522)
  gate, hook and lint predicates no longer read a matching `grep -q` as a
  miss when the producing `printf` takes SIGPIPE under `pipefail`, which could flip
  a verdict or skip a check at random.
  Migration: none.
- **A dead call stops reading as a negative result (#538)** (#538)
  a failed shell call is no longer reported as a genuine negative result.
  `detect.sh` leaves the tracker ambiguous when `claude mcp list` cannot be read
  instead of electing github; `pipeline-doctor.sh` reports an unprobeable gh or MCP as
  UNKNOWN rather than absent; and lean-gate's milestone 1 treats an unreadable issue as
  an environment error (rc 2) that spends no fix budget, where it used to charge a fix
  attempt. Migration: none.

## v5.0.0

### `dev-pipeline` 4.2.2 → 5.0.0

- **the lean scheduler stops asking the operator to attest intake (#518)** (#518)
  `--intake-attested` is retired. Under a tracker with no queue label the
  scheduler now states that intake is not gated and proceeds, matching what
  lean-gate.sh already does for the same condition; under github the flag's refusal
  arm is gone with it.
  Migration: drop `--intake-attested` from any lean invocation — it is now an
  unknown option and exits 2.
  **BREAKING:** `--intake-attested` is no longer accepted.
- **test(dev-pipeline): cover the state-dir derivation the STATECTL_STATE_DIR override bypasses (#520)** (#520)

## v4.2.2

### `dev-pipeline` 4.2.1 → 4.2.2

- **The lane re-enters a run it stopped itself (#510)** (#510)
  a stopped lean run can be re-launched. `run-lean` preflight now
  accepts a ticket already claimed by a run it stopped — the claimed label plus
  the lane's own bot-authored `lean-claimed` marker — so recovery needs no
  tracker write and no re-labelling. `--intake-attested` is refused under
  `tracker.type: github`, where it was the only way past the old reject.
  Migration: none. Operators who were passing `--intake-attested` on a github
  ticket should drop the flag; a genuinely unintaken ticket still rejects.
- **A gate evaluation that begins leaves a trace before it can be cut off (#512)** (#512)
  an interrupted lean-gate milestone is now visible in the progress record — a
  `started` row with no `concluded` — instead of being indistinguishable from a milestone
  that was never run. Repeated interruption of one milestone hard-stops at 5.
  Migration: none.

## v4.2.1

### `dev-pipeline` 4.2.0 → 4.2.1

- **The verdict gate's rc carries a taxonomy, and the scheduler routes on it (#508)** (#508)
  the lean scheduler tells a dark or build-authored review apart from a
  review that found problems. A review producing no usable record re-spawns
  REVIEW once instead of spending a round on a BUILD session with nothing to fix,
  and a P10 authorship refusal stops the run naming the violation instead of
  being retried. orchestrate-lean.sh gains exit codes 5 and 6; lean-gate.sh's
  milestone 4 gains the matching 5/6 alongside its existing 0/1/2/4.
  Migration: none.

## v4.2.0

### `dev-pipeline` 4.1.5 → 4.2.0

- **feat(dev-pipeline): a downgraded review model now costs a stated reason (#491)** (#491)
  --review-model-basis makes a downgraded --review-model in the lean
  lane's scheduler a stated decision instead of a silent one — a value other
  than the shipped default now requires a reason via the new flag, or the run
  refuses before spawning anything. Migration: none; the shipped default keeps
  working unchanged.
- **Milestone 1's absent spec is recorded, not charged to the fix budget (#504)** (#504)
  a lean-lane milestone-1 red that only means the spec is not written yet is
  recorded as `absent` and no longer spends the 3-attempt fix budget, so a run that follows
  the checklist arrives at its first real fix with the whole budget intact. Absence carries
  its own 10-call bound. Migration: none.
- **feat(dev-pipeline): the lean scheduler reads an artifact, not a spawn's exit status (#501)** (#501)
  run-lean re-spawns a BUILD session that exited 0 with work in flight and no
  PR yet, instead of ending the lane at exit 1 — bounded by the new `--max-continuations`
  (default 2, reset per build phase, `0` restores the old behavior). It also no longer
  reports `done` on a close-out that never satisfied milestone 5, exiting non-zero and
  naming what is unmet. Both read a new read-only `lean-gate.sh progress <issue>`
  subcommand, which prints an opaque token and writes nothing.
  Migration: none.
- **Wrapper commits attribute AI co-authorship (#489)** (#489)
  commits made through the dev-pipeline bot-commit wrapper now carry a
  Co-Authored-By trailer when the calling session supplied none, so a run's
  commits render as AI-co-authored even in a bot-disabled consumer. A
  caller-supplied trailer naming a precise model is preserved, not duplicated.
  Needs git >= 2.32; an older git commits without the trailer rather than
  failing.
  Migration: none.

### `review-toolkit` 4.1.3 → 4.2.0

- **feat(dev-pipeline): a downgraded review model now costs a stated reason (#491)** (#491)
  --review-model-basis makes a downgraded --review-model in the lean
  lane's scheduler a stated decision instead of a silent one — a value other
  than the shipped default now requires a reason via the new flag, or the run
  refuses before spawning anything. Migration: none; the shipped default keeps
  working unchanged.

## v4.1.5

### `dev-pipeline` 4.1.4 → 4.1.5

- **fix(dev-pipeline): the last install-topology red, and newest-version means highest (#484)** (#484)
  suites and lints that resolve a sibling plugin from a version-keyed
  install cache now select the highest version rather than the lexically-last
  one, so a 10.x plugin is no longer passed over for a 9.x one. cost-block's
  selftest no longer depends on a git repo above the install cache.
  Migration: none.
- **The retro corpus counts a ticket once, whatever its quarantined snapshots are named (#485)** (#485)
  perf-retro's corpus no longer double-counts a ticket whose earlier run was
  quarantined by an operator rename; an orphan snapshot with no live counterpart is
  still counted. Migration: none.
- **the thin orchestrator: run-lean becomes the lane's front door, the build payload moves to build-lean (#488)** (#488)
  /dev-pipeline:run-lean now schedules the whole lane end to end -
  build, review, fix rounds and close-out - in fresh sessions, with no operator
  wait between phases. The build checklist it used to carry is now
  /dev-pipeline:build-lean and is unchanged.
  Migration: consumers taking the new second-shift-ci-check.sh template must move
  their marketplace pin to this release or later in the same PR - the template
  fetches lean-evidence.sh by path at the pinned ref, and that path moved from
  skills/run-lean/ to skills/build-lean/.

### `intake-toolkit` 2.3.2 → 2.3.3

- **Eval-harness model identity is operator-supplied, not repo-carried (#475)** (#475)
  the agent-eval harnesses no longer ship a default model. Set
  REVIEWER_MODEL and JUDGE_MODEL (plus MOCK_MODEL for the intake-orchestrator
  eval) to version-pinned model ids before invoking any evals/*/run*.sh; the
  runner refuses a missing value and refuses the floating aliases opus, sonnet,
  haiku and fable.
  Migration: operators of the eval harnesses must now export the role variables;
  no consumer or CI path invokes them.
- **the thin orchestrator: run-lean becomes the lane's front door, the build payload moves to build-lean (#488)** (#488)
  /dev-pipeline:run-lean now schedules the whole lane end to end -
  build, review, fix rounds and close-out - in fresh sessions, with no operator
  wait between phases. The build checklist it used to carry is now
  /dev-pipeline:build-lean and is unchanged.
  Migration: consumers taking the new second-shift-ci-check.sh template must move
  their marketplace pin to this release or later in the same PR - the template
  fetches lean-evidence.sh by path at the pinned ref, and that path moved from
  skills/run-lean/ to skills/build-lean/.

### `review-toolkit` 4.1.2 → 4.1.3

- **Eval-harness model identity is operator-supplied, not repo-carried (#475)** (#475)
  the agent-eval harnesses no longer ship a default model. Set
  REVIEWER_MODEL and JUDGE_MODEL (plus MOCK_MODEL for the intake-orchestrator
  eval) to version-pinned model ids before invoking any evals/*/run*.sh; the
  runner refuses a missing value and refuses the floating aliases opus, sonnet,
  haiku and fable.
  Migration: operators of the eval harnesses must now export the role variables;
  no consumer or CI path invokes them.
- **fix(dev-pipeline): the last install-topology red, and newest-version means highest (#484)** (#484)
  suites and lints that resolve a sibling plugin from a version-keyed
  install cache now select the highest version rather than the lexically-last
  one, so a 10.x plugin is no longer passed over for a 9.x one. cost-block's
  selftest no longer depends on a git repo above the install cache.
  Migration: none.

### `second-shift` 3.1.4 → 3.1.5

- **config-grill's web-surface checks measure applicability before demanding a glob (#474)** (#474)
  `/second-shift:doctor` and `/second-shift:onboard` no longer demand
  `stageParams.webComponentGlobs` and `stageParams.visualCapture.triggerGlobs`
  from a repo with no rendering surface — a shell, CLI or library consumer gets
  two informational "not evaluated" notes instead of two FAILs that could only
  be answered with a waiver restating what the tool just measured. A repo that
  does render still gets the finding, including where no shipped candidate
  matches. `stageParams.formatGlob` is unchanged. Migration: none — a
  `grillWaivers` entry written for either key stays valid and simply has nothing
  left to suppress.
- **doctor's remediation names the scope of the record it actually resolved (#479)** (#479)
  /second-shift:doctor now reports a project-scope plugin record that a user-scope
  record already serves as redundant, and its version-drift fixes name the scope of the record
  they graded — the update verb and the marketplace-registration ref for a user-scope record,
  the project-scope install only where that install is genuinely the pin contract.
  /second-shift:local-dev-refresh declines to realign a redundant project record and reports it
  instead; /second-shift:onboard says which plugins user scope already serves rather than
  printing an install for them.
  Migration: none.
- **The grill and onboard name only mechanisms the default lane runs (#481)** (#481)
  config-grill now flags a config that declares mutation intent while the
  repo carries no tools/mutation-sweep.sh, and notes the unadopted seam once a test
  lane is configured; the testFile-plumbing and visualCapture-triggerGlobs checks are
  gone, and no emitted remediation names a stage the default lane does not run.
  Migration: a repo waiving T4.mutation-plumbing keeps its waiver — the id is
  unchanged. A waiver for T4.testfile-plumbing or T2.visualCaptureTriggerGlobs is now
  inert and can be deleted.
- **fix(dev-pipeline): the last install-topology red, and newest-version means highest (#484)** (#484)
  suites and lints that resolve a sibling plugin from a version-keyed
  install cache now select the highest version rather than the lexically-last
  one, so a 10.x plugin is no longer passed over for a 9.x one. cost-block's
  selftest no longer depends on a git repo above the install cache.
  Migration: none.
- **the thin orchestrator: run-lean becomes the lane's front door, the build payload moves to build-lean (#488)** (#488)
  /dev-pipeline:run-lean now schedules the whole lane end to end -
  build, review, fix rounds and close-out - in fresh sessions, with no operator
  wait between phases. The build checklist it used to carry is now
  /dev-pipeline:build-lean and is unchanged.
  Migration: consumers taking the new second-shift-ci-check.sh template must move
  their marketplace pin to this release or later in the same PR - the template
  fetches lean-evidence.sh by path at the pinned ref, and that path moved from
  skills/run-lean/ to skills/build-lean/.

## v4.1.4

### `dev-pipeline` 4.1.3 → 4.1.4

- **Suites that resolve a cross-plugin path by a fixed hop count (#469)** (#469)
  cross-plugin sibling resolution in check-emit-deadline.sh,
  doctor-selftest.sh and preflight-selftest.sh now works from a version-keyed
  install cache instead of only from the monorepo, and check-emit-deadline.sh
  refuses to report a clean verdict over zero linted agents.
  Migration: none. A suite run from a partial checkout that genuinely lacks the
  sibling plugin now fails instead of printing a skip.
  check-emit-deadline.sh run from an install cache now lints only the
  newest cached version of each plugin, instead of every version it finds — a
  cache holding more than one version of a plugin no longer reds the lint on
  agents that are no longer shipped.
  Migration: none.

### `review-toolkit` 4.1.1 → 4.1.2

- **Suites that resolve a cross-plugin path by a fixed hop count (#469)** (#469)
  cross-plugin sibling resolution in check-emit-deadline.sh,
  doctor-selftest.sh and preflight-selftest.sh now works from a version-keyed
  install cache instead of only from the monorepo, and check-emit-deadline.sh
  refuses to report a clean verdict over zero linted agents.
  Migration: none. A suite run from a partial checkout that genuinely lacks the
  sibling plugin now fails instead of printing a skip.
  check-emit-deadline.sh run from an install cache now lints only the
  newest cached version of each plugin, instead of every version it finds — a
  cache holding more than one version of a plugin no longer reds the lint on
  agents that are no longer shipped.
  Migration: none.

### `second-shift` 3.1.3 → 3.1.4

- **Suites that resolve a cross-plugin path by a fixed hop count (#469)** (#469)
  cross-plugin sibling resolution in check-emit-deadline.sh,
  doctor-selftest.sh and preflight-selftest.sh now works from a version-keyed
  install cache instead of only from the monorepo, and check-emit-deadline.sh
  refuses to report a clean verdict over zero linted agents.
  Migration: none. A suite run from a partial checkout that genuinely lacks the
  sibling plugin now fails instead of printing a skip.
  check-emit-deadline.sh run from an install cache now lints only the
  newest cached version of each plugin, instead of every version it finds — a
  cache holding more than one version of a plugin no longer reds the lint on
  agents that are no longer shipped.
  Migration: none.

## v4.1.3

### `dev-pipeline` 4.1.2 → 4.1.3

- **The lean lane destroys its worktrees (#467)** (#467)
  the lean lane now removes its worktree at approval (`bash G teardown
  <issue>`, checklist step 9) and sweeps abandoned lane worktrees at `bash G entry`.
  Both refuse on unclean or unpushed work, and neither deletes a branch.
  Migration: none.
- **Suites that need a repo-only artifact declare a counted skip from an install (#466)** (#466)
  a shipped selftest that needs a repo-only artifact now reports a
  named skip from an install instead of a false failure.
  Migration: none.
- **Gate arms declare when their contract took effect (#470)** (#470)
  a lean gate arm can declare the instant its contract took effect, and
  a run whose PR opened (or whose branch started) before that instant is
  reported as outside the arm's window instead of failing it. The consumer CI
  template now supplies PR_CREATED_AT; a workflow that does not is not red, its
  lean PRs just take the declining path until it is updated.
  Migration: none.
- **An arm enforces only what its producer's generation ships (#471)** (#471)
  a lean merge-boundary arm can declare the producer capability it depends
  on, and a PR built by a harness generation that does not ship that capability is
  reported as outside the arm's contract instead of failing it. The build harness
  stamps its capabilities onto the claim comment and the verdict record. A repo
  whose lean PRs were built before this ships takes the declining path until it is
  re-run; no consumer workflow change is required.
  Migration: none.

### `review-toolkit` 4.1.0 → 4.1.1

- **Suites that need a repo-only artifact declare a counted skip from an install (#466)** (#466)
  a shipped selftest that needs a repo-only artifact now reports a
  named skip from an install instead of a false failure.
  Migration: none.

### `second-shift` 3.1.2 → 3.1.3

- **onboard names the benefit for every unadopted capability, and forces a disposition (#462)** (#462)
  onboard and doctor now name the three extension-point seams no
  question ever mentioned, and say what each buys. Onboard blocks its
  accept-or-edit screen until you adopt one or declare a grillWaivers entry;
  doctor reports it as a note and its exit code is unchanged.
  Migration: none — no schema or configVersion change. An already-onboarded repo
  gains one doctor note until it adopts a seam or declares the waiver.
- **Gate arms declare when their contract took effect (#470)** (#470)
  a lean gate arm can declare the instant its contract took effect, and
  a run whose PR opened (or whose branch started) before that instant is
  reported as outside the arm's window instead of failing it. The consumer CI
  template now supplies PR_CREATED_AT; a workflow that does not is not red, its
  lean PRs just take the declining path until it is updated.
  Migration: none.
- **A re-onboard cannot silently destroy an existing config value (#463)** (#463)
  a re-onboard no longer silently reverts a human-set config value. /second-shift:onboard
  now carries testFile and unitTestScope forward from the existing config, and blocks its
  accept-or-edit screen on any existing non-null value the draft would remove or change until
  each one is fixed or explicitly confirmed.
  Migration: none.
- **An arm enforces only what its producer's generation ships (#471)** (#471)
  a lean merge-boundary arm can declare the producer capability it depends
  on, and a PR built by a harness generation that does not ship that capability is
  reported as outside the arm's contract instead of failing it. The build harness
  stamps its capabilities onto the claim comment and the verdict record. A repo
  whose lean PRs were built before this ships takes the declining path until it is
  re-run; no consumer workflow change is required.
  Migration: none.

## v4.1.2

### `dev-pipeline` 4.1.1 → 4.1.2

- **The bot is a code-host capability, not a tracker one (#457)** (#457)
  `tracker.bot` is now legal under `tracker.type: jira`. The bot
  configures write identity on the CODE HOST, which is GitHub under every
  tracker adapter, so a Jira-tracked repo can now carry bot identity on its PR
  comments, the build-identity marker, the cost-block amend and its git commits
  — and its lean PRs are gated by the merge boundary's identity arm at full
  strength instead of the announced reduced-strength degrade. That degrade now
  keys on whether a bot is configured rather than on the tracker, so it is
  reachable from github too (set `tracker.bot.enabled: false`). review-lean
  posts its findings comment through the bot wrapper.
  Migration: none. Existing configs behave exactly as before — a config that
  declares no bot keeps its old posture per tracker. Jira consumers who want
  the stronger gate add a `tracker.bot` block and install the wrapper.
- **The lean PR marker's session id comes from a recorded build session, not from whoever ran the command (#456)** (#456)
  the lean build harness refuses to stamp a PR marker from a session it
  never recorded as a build session, instead of writing whichever session ran the
  command. This removes the case where the documented manual `mark` recovery, run
  from the review session, made the merge boundary report an independent review as
  a P10 self-review — an error that could only be cleared by deleting bot-authored
  evidence. The refusal names the build session ids the harness itself recorded and
  the exact re-invocation.
  Migration: none. A run already in flight, whose progress file carries a header
  but no session rows, still marks — the header is part of the set.
- **The gate's own markdown no longer reds the consumer's format check (#452)** (#452)
  lean-gate.sh now writes its render receipt in Prettier's table form
  and formats the verdict record with a locally resolved prettier (never npx,
  never the network), reverting if formatting would damage the record's header.
  Both commit instructions now name the formatting obligation for the spec and
  intent-gap record, which the gate does not author.
  Migration: none.
- **Cost attribution says which of the three ways it failed (#459)** (#459)
  a run whose session was launched without CLAUDE_CODE_ENABLE_TELEMETRY
  is told so before the work starts, not after the cost is unrecoverable, and the
  cost block now reads metrics files that have rotated. `costBlockApplied` gains
  `skipped-session-not-exporting` and `skipped-rotated-out`;
  `skipped-zero-datapoints` narrows to its literal meaning.
  Migration: none.
- **onboard and doctor grill the config for capability that is detectably off (#455)** (#455)
  /second-shift:onboard and /second-shift:doctor now grill the config for
  capability that is detectably off — an unmatched webComponentGlobs/formatGlob/
  triggerGlobs default, a mutation gate with no plumbing behind it, a design
  provider with no render harness, and a configured command that names a missing
  manifest script or resolves to a watch-mode one. Onboard blocks its accept
  screen on unwaived findings; doctor reports each as a FAIL.
  Migration: none — a repo with a real gap goes non-zero on its first doctor run
  after upgrading; adopt the capability or declare the opt-out in the new
  top-level grillWaivers object (configVersion stays at 2).
  the config grill no longer reports `jest -w`, `tsup -w`, `esbuild … -w`,
  `parcel … -w` or `karma … -w` as watch-mode commands — none of those runners defines `-w`
  as watch, so each finding was a doctor FAIL on a valid config. `jest --watch` and
  `jest --watchAll` still fire.
  Migration: none.

### `second-shift` 3.1.1 → 3.1.2

- **The bot is a code-host capability, not a tracker one (#457)** (#457)
  `tracker.bot` is now legal under `tracker.type: jira`. The bot
  configures write identity on the CODE HOST, which is GitHub under every
  tracker adapter, so a Jira-tracked repo can now carry bot identity on its PR
  comments, the build-identity marker, the cost-block amend and its git commits
  — and its lean PRs are gated by the merge boundary's identity arm at full
  strength instead of the announced reduced-strength degrade. That degrade now
  keys on whether a bot is configured rather than on the tracker, so it is
  reachable from github too (set `tracker.bot.enabled: false`). review-lean
  posts its findings comment through the bot wrapper.
  Migration: none. Existing configs behave exactly as before — a config that
  declares no bot keeps its old posture per tracker. Jira consumers who want
  the stronger gate add a `tracker.bot` block and install the wrapper.
- **onboard and doctor grill the config for capability that is detectably off (#455)** (#455)
  /second-shift:onboard and /second-shift:doctor now grill the config for
  capability that is detectably off — an unmatched webComponentGlobs/formatGlob/
  triggerGlobs default, a mutation gate with no plumbing behind it, a design
  provider with no render harness, and a configured command that names a missing
  manifest script or resolves to a watch-mode one. Onboard blocks its accept
  screen on unwaived findings; doctor reports each as a FAIL.
  Migration: none — a repo with a real gap goes non-zero on its first doctor run
  after upgrading; adopt the capability or declare the opt-out in the new
  top-level grillWaivers object (configVersion stays at 2).
  the config grill no longer reports `jest -w`, `tsup -w`, `esbuild … -w`,
  `parcel … -w` or `karma … -w` as watch-mode commands — none of those runners defines `-w`
  as watch, so each finding was a doctor FAIL on a valid config. `jest --watch` and
  `jest --watchAll` still fire.
  Migration: none.

## v4.1.1

### `dev-pipeline` 4.1.0 → 4.1.1

- **Gate output classes: silent when satisfied, loud when it could not evaluate (#451)** (#451)
  the lean lane's two merge-boundary gates no longer recite the arms they
  checked on a passing run — a green PR now produces no gate output at all, and the
  only line a passing run can print is a one-line disclosure that some arm could not
  be evaluated (with a disposition of not-applicable, reduced-strength, postdated or
  inert). Failure output is unchanged.
  Migration: a workflow or script that greps the gates' green-path text must move to
  the new tokens — the whole-gate decline is now 'lean-chain: not-applicable' /
  'lean-evidence: not-applicable' rather than the prose 'chain check not applicable'.
  the consumer CI template's 'lean evidence' OK line now names the
  'lean-evidence: not-applicable' decline as the thing that distinguishes a
  complete lean PR from a non-lean one, instead of pointing at payload output a
  satisfied run no longer produces.
  Migration: none.

### `second-shift` 3.1.0 → 3.1.1

- **Gate output classes: silent when satisfied, loud when it could not evaluate (#451)** (#451)
  the lean lane's two merge-boundary gates no longer recite the arms they
  checked on a passing run — a green PR now produces no gate output at all, and the
  only line a passing run can print is a one-line disclosure that some arm could not
  be evaluated (with a disposition of not-applicable, reduced-strength, postdated or
  inert). Failure output is unchanged.
  Migration: a workflow or script that greps the gates' green-path text must move to
  the new tokens — the whole-gate decline is now 'lean-chain: not-applicable' /
  'lean-evidence: not-applicable' rather than the prose 'chain check not applicable'.
  the consumer CI template's 'lean evidence' OK line now names the
  'lean-evidence: not-applicable' decline as the thing that distinguishes a
  complete lean PR from a non-lean one, instead of pointing at payload output a
  satisfied run no longer produces.
  Migration: none.

## v4.1.0

### `audit-toolkit` 2.1.0 → 2.1.1

- **the audit hook writes the ledger where its readers look (#420)** (#420)
  the audit ledger now lives under the MAIN checkout's .claude/audit/ for
  every session in a repo family, including sessions running in a linked worktree —
  previously a worktree session wrote beside the worktree, where /audit,
  /audit-history and the lean-lane evidence gates could not find it.
  Migration: none. Ledgers already written beside a worktree are abandoned, not
  migrated — most are already gone with the worktrees that held them, and the rest
  are tamper-evidence for runs that have already merged. A run in flight across the
  upgrade loses continuity between its old and its new ledger.

### `dev-pipeline` 4.0.0 → 4.1.0

- **feat(review-toolkit): flag test coverage that cannot fail (#411)** (#411)
  test-coverage-reviewer gains a stack-neutral "coverage that cannot
  fail" axis — seven decorative test shapes, a cost signal that flags a raised
  per-file test timeout as a symptom, and a composed-contract rule generalized
  off its former pipeline-gate scoping. unit-test-mutation-reviewer gains a
  decorative-test audit over tests added in the range, reported on
  mockAuditFindings with a delete-or-fold remedy. Both are advisory-only and
  never discount an existing coverage floor.
  Migration: none.
- **docs(dev-pipeline): tracker README's lean-lane branch-site counts are stale for both scripts (#414)** (#414)
- **plan-lint-selftest borrowed the repo it was authored in; ship a class guard for it (#425)** (#425)
  shipped selftests that silently depended on the second-shift
  checkout now pass from a marketplace install, so pipeline-doctor and
  preflight stop reporting a FAIL on a clean consumer repo.
  Migration: none.
- **feat(dev-pipeline): bucket pipeline cost by resolved model tier (#429)** (#429)
  the pipeline cost block buckets spend by resolved model tier
  (`reasoning` / `code` / `emit`, with `unknown` for unmapped ids and for
  datapoints carrying no model attribute) beside the stage label. The PR cost
  table gains a Tier column, and each `cost-log.jsonl` row gains a top-level
  `tiers` array beside the unchanged `models`. The map is a script constant —
  no config key, no schema edit, no configVersion change.
  Migration: none. Already-written cost-log rows stay readable, and
  `stage-envelopes.sh` re-groups by label so the extra rows fold correctly.
- **feat(dev-pipeline): enforce the lean entry gate's ledger precondition (#422)** (#422)
  `lean-gate.sh entry` now records a durable attestation row in the run's
  progress file, and `claim`, `1..5`, `all` and `delta` refuse with exit 2 until it
  exists — naming `bash G entry <issue>` as the remedy and charging no fix-budget
  attempt. Its refusal names `audit-toolkit` when the repo's settings show the plugin
  disabled. `lean-reconcile.sh` gains an arm asserting that row, and
  `/second-shift:doctor` now FAILs (not warns) when `audit-toolkit` is disabled while
  `dev-pipeline` is enabled — that combination makes the lean lane unusable.
  Migration: no grandfather window. An in-flight lean PR whose build ran before this
  reds at `all`/`delta` and at reconcile; the remedy is one idempotent
  `bash G entry <issue>` wherever the hook is live. A repo that deliberately disabled
  `audit-toolkit` alongside `dev-pipeline` must re-enable it or disable the lane.
  `docs/onboarding.md` records that `audit-toolkit` disabled while
  `dev-pipeline` is enabled is not a supported combination — the lean lane's entry
  gate cannot start without the ledger audit-toolkit's hook writes.
  Migration: none.
  `review-lean` step 4 documents what an exit 2 from `bash G delta`
  means: no entry attestation is READABLE. That record is host-local and
  gitignored, so a review re-runs from the build worktree before concluding
  anything; only a genuinely absent row is handed back, since a run whose audit
  ledger was never established cannot be reconciled.
  Migration: none.
- **fix(second-shift): re-verify a lane-redding survivor serially before reporting it (#433)** (#433)
- **feat(second-shift): release the pipeline's run-state labels when a tracker item closes (#428)** (#428)
  the pipeline's two run-state labels (`tracker.labels.claimed` and
  `tracker.labels.queue`) are now released when a tracker item closes, instead of
  staying on every merged ticket forever. `tracker.labels.blockers` is never
  touched. `/second-shift:onboard` emits the workflow that does it under the same
  acceptance as the CI evidence workflow, adding
  `.github/workflows/second-shift-unclaim.yml` and
  `.claude/tools/second-shift-unclaim.sh`. It is the only emitted workflow that
  writes (`issues: write`, two labels on one closing issue), it is a stated no-op
  under a tracker declaring `writes: false` or a non-github tracker, and it needs
  the repo's Actions workflow permissions set to read-and-write.
  Migration: none. Existing repos opt in at the next onboard run.
- **fix+feat: preflight portability fixes, onboard topology detection, doctor selftest caching (#418)** (#418)
  pipeline-doctor's plan-lint selftest no longer depends on the
  invoking repo having a top-level plugins/ directory, so its Check 5a
  ghost-path case now passes in any consumer repo. Migration: none.
  /second-shift:onboard's topology detection now (a) doesn't
  misclassify a repo with test-only workspaces as a monorepo, (b) always
  surfaces a real sibling-repo pair candidate for confirmation even when a
  workspaces manifest is also present, and (c) finds a bare-base-name BE
  sibling from an FE-suffixed repo (e.g. shop next to shop-ui).
  Migration: none.
  pipeline-doctor.sh now caches a clean internal-selftest sweep by
  environment fingerprint (installed plugin tree + bash/jq/node versions),
  so a consumer's repeat preflight/doctor invocation in an unchanged
  environment completes in seconds instead of re-paying the full sweep
  (~4 min) every time. Delete .claude/pipeline-state/doctor-selftest-cache.json
  to force a re-run. Migration: none.
- **Consumer-side lean chain gate — merge-boundary evidence ships as plugin payload (#430)** (#430)
  /dev-pipeline:run-lean's merge-boundary evidence check is now
  consumable by a consumer repo's own CI. The second-shift evidence workflow
  emitted by /second-shift:onboard gains a third check that, on a lean-lane PR,
  refuses a merge without a committed approve-verdict carrying reconciliation
  keys, a review identity distinct from the build run's, a verdict covering the
  head being merged, and a ratified intent-gap record. It is model-free and
  fail-closed: a moved payload path at the pinned ref (HTTP 404) or a shallow
  checkout is reported as drift, never waved through. Under `tracker.type: jira`
  the identity arm reports itself unavailable at reduced strength — printed,
  never silently skipped — because config-lint forbids a `tracker.bot` there.
  Migration: re-run /second-shift:onboard to pick up the updated
  `.github/workflows/second-shift-ci.yml` (it now needs `fetch-depth: 0` and the
  PR context in the step env) and `.claude/tools/second-shift-ci-check.sh`.
  the consumer CI evidence workflow now grants `issues: read` and
  `pull-requests: read`; without them its lean-evidence check failed on every pull request
  it applied to. A non-approve verdict is reported as one violation rather than two.
  Migration: an already-emitted `.github/workflows/second-shift-ci.yml` needs the two
  scopes added to its `permissions:` block, by hand or by re-running
  `/second-shift:onboard`.
- **the audit hook writes the ledger where its readers look (#420)** (#420)
  the audit ledger now lives under the MAIN checkout's .claude/audit/ for
  every session in a repo family, including sessions running in a linked worktree —
  previously a worktree session wrote beside the worktree, where /audit,
  /audit-history and the lean-lane evidence gates could not find it.
  Migration: none. Ledgers already written beside a worktree are abandoned, not
  migrated — most are already gone with the worktrees that held them, and the rest
  are tamper-evidence for runs that have already merged. A run in flight across the
  upgrade loses continuity between its old and its new ledger.
- **A review that reviewed nothing could still answer 'Ready to merge?' (#437)** (#437)
  a standalone review-lead round in which every selected reviewer goes dark
  now voids instead of answering 'Ready to merge?' over zero coverage, and bare
  plugin reviewer names are normalized at dispatch rather than dying. Stage 8 records
  such a round as codeReviewVoided and hands it to needs-deep-review without retrying.
  Migration: none.
- **run-lean branches join the staged lane's namespace; the lean discriminator moves onto the artifact (#438)** (#438)
  run-lean branches are now `<tracker.branchPrefix><key>`, the same
  namespace the staged lane uses — the `lean/` prefix is retired, as is the
  `claude/acme-` fallback for an unset prefix (it now fails, naming the candidates
  it considered). Both merge-boundary gates classify on the committed lean spec
  rather than on a branch name.
  Migration: a consumer whose CI workflow still sets `LEAN_BRANCH_PREFIX` gets a
  deprecation notice and can drop the constant; it is ignored, never an error.
  lean classification refuses (exit 2) when it cannot read the PR's changed files,
  instead of reporting the PR as non-lean. A workflow that omits PR_BASE_REF now reds both
  chain gates rather than silently exempting the PR from them.
  Migration: none — both shipped workflows already pass PR_BASE_REF under fetch-depth: 0.

### `review-toolkit` 4.0.0 → 4.1.0

- **feat(review-toolkit): flag test coverage that cannot fail (#411)** (#411)
  test-coverage-reviewer gains a stack-neutral "coverage that cannot
  fail" axis — seven decorative test shapes, a cost signal that flags a raised
  per-file test timeout as a symptom, and a composed-contract rule generalized
  off its former pipeline-gate scoping. unit-test-mutation-reviewer gains a
  decorative-test audit over tests added in the range, reported on
  mockAuditFindings with a delete-or-fold remedy. Both are advisory-only and
  never discount an existing coverage floor.
  Migration: none.
- **A review that reviewed nothing could still answer 'Ready to merge?' (#437)** (#437)
  a standalone review-lead round in which every selected reviewer goes dark
  now voids instead of answering 'Ready to merge?' over zero coverage, and bare
  plugin reviewer names are normalized at dispatch rather than dying. Stage 8 records
  such a round as codeReviewVoided and hands it to needs-deep-review without retrying.
  Migration: none.

### `second-shift` 3.0.0 → 3.1.0

- **feat(dev-pipeline): enforce the lean entry gate's ledger precondition (#422)** (#422)
  `lean-gate.sh entry` now records a durable attestation row in the run's
  progress file, and `claim`, `1..5`, `all` and `delta` refuse with exit 2 until it
  exists — naming `bash G entry <issue>` as the remedy and charging no fix-budget
  attempt. Its refusal names `audit-toolkit` when the repo's settings show the plugin
  disabled. `lean-reconcile.sh` gains an arm asserting that row, and
  `/second-shift:doctor` now FAILs (not warns) when `audit-toolkit` is disabled while
  `dev-pipeline` is enabled — that combination makes the lean lane unusable.
  Migration: no grandfather window. An in-flight lean PR whose build ran before this
  reds at `all`/`delta` and at reconcile; the remedy is one idempotent
  `bash G entry <issue>` wherever the hook is live. A repo that deliberately disabled
  `audit-toolkit` alongside `dev-pipeline` must re-enable it or disable the lane.
  `docs/onboarding.md` records that `audit-toolkit` disabled while
  `dev-pipeline` is enabled is not a supported combination — the lean lane's entry
  gate cannot start without the ledger audit-toolkit's hook writes.
  Migration: none.
  `review-lean` step 4 documents what an exit 2 from `bash G delta`
  means: no entry attestation is READABLE. That record is host-local and
  gitignored, so a review re-runs from the build worktree before concluding
  anything; only a genuinely absent row is handed back, since a run whose audit
  ledger was never established cannot be reconciled.
  Migration: none.
- **feat(second-shift): release the pipeline's run-state labels when a tracker item closes (#428)** (#428)
  the pipeline's two run-state labels (`tracker.labels.claimed` and
  `tracker.labels.queue`) are now released when a tracker item closes, instead of
  staying on every merged ticket forever. `tracker.labels.blockers` is never
  touched. `/second-shift:onboard` emits the workflow that does it under the same
  acceptance as the CI evidence workflow, adding
  `.github/workflows/second-shift-unclaim.yml` and
  `.claude/tools/second-shift-unclaim.sh`. It is the only emitted workflow that
  writes (`issues: write`, two labels on one closing issue), it is a stated no-op
  under a tracker declaring `writes: false` or a non-github tracker, and it needs
  the repo's Actions workflow permissions set to read-and-write.
  Migration: none. Existing repos opt in at the next onboard run.
- **fix+feat: preflight portability fixes, onboard topology detection, doctor selftest caching (#418)** (#418)
  pipeline-doctor's plan-lint selftest no longer depends on the
  invoking repo having a top-level plugins/ directory, so its Check 5a
  ghost-path case now passes in any consumer repo. Migration: none.
  /second-shift:onboard's topology detection now (a) doesn't
  misclassify a repo with test-only workspaces as a monorepo, (b) always
  surfaces a real sibling-repo pair candidate for confirmation even when a
  workspaces manifest is also present, and (c) finds a bare-base-name BE
  sibling from an FE-suffixed repo (e.g. shop next to shop-ui).
  Migration: none.
  pipeline-doctor.sh now caches a clean internal-selftest sweep by
  environment fingerprint (installed plugin tree + bash/jq/node versions),
  so a consumer's repeat preflight/doctor invocation in an unchanged
  environment completes in seconds instead of re-paying the full sweep
  (~4 min) every time. Delete .claude/pipeline-state/doctor-selftest-cache.json
  to force a re-run. Migration: none.
- **Consumer-side lean chain gate — merge-boundary evidence ships as plugin payload (#430)** (#430)
  /dev-pipeline:run-lean's merge-boundary evidence check is now
  consumable by a consumer repo's own CI. The second-shift evidence workflow
  emitted by /second-shift:onboard gains a third check that, on a lean-lane PR,
  refuses a merge without a committed approve-verdict carrying reconciliation
  keys, a review identity distinct from the build run's, a verdict covering the
  head being merged, and a ratified intent-gap record. It is model-free and
  fail-closed: a moved payload path at the pinned ref (HTTP 404) or a shallow
  checkout is reported as drift, never waved through. Under `tracker.type: jira`
  the identity arm reports itself unavailable at reduced strength — printed,
  never silently skipped — because config-lint forbids a `tracker.bot` there.
  Migration: re-run /second-shift:onboard to pick up the updated
  `.github/workflows/second-shift-ci.yml` (it now needs `fetch-depth: 0` and the
  PR context in the step env) and `.claude/tools/second-shift-ci-check.sh`.
  the consumer CI evidence workflow now grants `issues: read` and
  `pull-requests: read`; without them its lean-evidence check failed on every pull request
  it applied to. A non-approve verdict is reported as one violation rather than two.
  Migration: an already-emitted `.github/workflows/second-shift-ci.yml` needs the two
  scopes added to its `permissions:` block, by hand or by re-running
  `/second-shift:onboard`.
- **run-lean branches join the staged lane's namespace; the lean discriminator moves onto the artifact (#438)** (#438)
  run-lean branches are now `<tracker.branchPrefix><key>`, the same
  namespace the staged lane uses — the `lean/` prefix is retired, as is the
  `claude/acme-` fallback for an unset prefix (it now fails, naming the candidates
  it considered). Both merge-boundary gates classify on the committed lean spec
  rather than on a branch name.
  Migration: a consumer whose CI workflow still sets `LEAN_BRANCH_PREFIX` gets a
  deprecation notice and can drop the constant; it is ignored, never an error.
  lean classification refuses (exit 2) when it cannot read the PR's changed files,
  instead of reporting the PR as non-lean. A workflow that omits PR_BASE_REF now reds both
  chain gates rather than silently exempting the PR from them.
  Migration: none — both shipped workflows already pass PR_BASE_REF under fetch-depth: 0.

## v4.0.0

### `dev-pipeline` 3.8.5 → 4.0.0

- **tracker README counts the lean lane's operations correctly (#407)** (#407)
- **design live-render verification has no gate in the lean lane (#404)** (#404)
  the lean lane now gates design live-render fidelity. With
  `design.provider` configured, a ticket's spec must carry a `## Design` section
  — either armed (a provider handoff link plus `| RS-n | route | state | AC refs |`
  render-state rows) or an explicit `Design: none — <reason>` disarm. Armed runs
  render every declared state at milestone 3, commit a hash manifest beside the
  spec at `<plansDir>/<key>-lean-renders.md`, and require a `fidelity: pass`
  verdict at milestone 4; the merge boundary re-checks that the manifest is
  present and still current. `design.liveRender.command` gains an optional
  `{state}` placeholder, and `G verdict` gains `--fidelity <pass|fail|not-applicable>`.
  Screenshot bytes never enter history.
  Migration: repos with `design.provider` configured must add a `## Design`
  section to each lean spec, armed or explicitly disarmed. Runs that were green
  before will red at milestone 1 until it is present; the refusal names both
  accepted forms. Repos with no `design.provider` are unaffected.
  **BREAKING:** with `design.provider` configured, a lean spec carrying no `## Design` section now reds at milestone 1, and there is no config-level opt-out — the disarm is per-ticket and deliberate (D-8). Previously-green runs in such a repo require a spec edit before they pass.

### `review-toolkit` 3.0.5 → 4.0.0

- **design live-render verification has no gate in the lean lane (#404)** (#404)
  the lean lane now gates design live-render fidelity. With
  `design.provider` configured, a ticket's spec must carry a `## Design` section
  — either armed (a provider handoff link plus `| RS-n | route | state | AC refs |`
  render-state rows) or an explicit `Design: none — <reason>` disarm. Armed runs
  render every declared state at milestone 3, commit a hash manifest beside the
  spec at `<plansDir>/<key>-lean-renders.md`, and require a `fidelity: pass`
  verdict at milestone 4; the merge boundary re-checks that the manifest is
  present and still current. `design.liveRender.command` gains an optional
  `{state}` placeholder, and `G verdict` gains `--fidelity <pass|fail|not-applicable>`.
  Screenshot bytes never enter history.
  Migration: repos with `design.provider` configured must add a `## Design`
  section to each lean spec, armed or explicitly disarmed. Runs that were green
  before will red at milestone 1 until it is present; the refusal names both
  accepted forms. Repos with no `design.provider` are unaffected.
  **BREAKING:** with `design.provider` configured, a lean spec carrying no `## Design` section now reds at milestone 1, and there is no config-level opt-out — the disarm is per-ticket and deliberate (D-8). Previously-green runs in such a repo require a spec edit before they pass.

### `second-shift` 2.1.1 → 3.0.0

- **design live-render verification has no gate in the lean lane (#404)** (#404)
  the lean lane now gates design live-render fidelity. With
  `design.provider` configured, a ticket's spec must carry a `## Design` section
  — either armed (a provider handoff link plus `| RS-n | route | state | AC refs |`
  render-state rows) or an explicit `Design: none — <reason>` disarm. Armed runs
  render every declared state at milestone 3, commit a hash manifest beside the
  spec at `<plansDir>/<key>-lean-renders.md`, and require a `fidelity: pass`
  verdict at milestone 4; the merge boundary re-checks that the manifest is
  present and still current. `design.liveRender.command` gains an optional
  `{state}` placeholder, and `G verdict` gains `--fidelity <pass|fail|not-applicable>`.
  Screenshot bytes never enter history.
  Migration: repos with `design.provider` configured must add a `## Design`
  section to each lean spec, armed or explicitly disarmed. Runs that were green
  before will red at milestone 1 until it is present; the refusal names both
  accepted forms. Repos with no `design.provider` are unaffected.
  **BREAKING:** with `design.provider` configured, a lean spec carrying no `## Design` section now reds at milestone 1, and there is no config-level opt-out — the disarm is per-ticket and deliberate (D-8). Previously-green runs in such a repo require a spec edit before they pass.

## v3.8.5

### `dev-pipeline` 3.8.4 → 3.8.5

- **review-lean carries a jira tracker delta (#399)** (#399)
  `review-lean`'s SKILL.md now documents the jira tracker delta —
  issue-key resolution from `Closes [<KEY>]` under `### Jira Items` instead
  of `Closes #N`, and confirmation that the findings-comment step is
  tracker-write-independent. Migration: none.
- **lean-gate milestone 3 reds on zero verifying lanes with no explicit opt-out (#400)** (#400)
  lean-gate.sh milestone 3 now reds when zero verifying lanes
  (lint/typecheck/test/extraLanes) are configured for the resolved host and
  commands.<host>.allowUnverified is not set to true, instead of silently
  passing having verified nothing. Set the opt-out explicitly to keep a
  genuinely lane-less repo green. Migration: none.

### `intake-toolkit` 2.3.1 → 2.3.2

- **pair topology under the lean lane: two standalone onboards, cross-repo split at intake (#401)** (#401)
  a BE/FE pair repo now gets a hand-off from `/second-shift:onboard` to a second
  onboard run in the sibling repo — the host's `be-fe-pair` config is unchanged and still
  serves the staged lane, while the sibling gains its own standalone config so it can be
  worked with `/dev-pipeline:run-lean` from its own checkout. `intake-orchestrator` gains a
  pair-gated title check that terminally rejects a ticket whose title carries both of the
  configured `ticketTag` values or neither, plus an admission rule splitting genuine
  cross-repo scope into ordered per-repo tickets filed in each repo's own tracker.
  `ticketTag` is now documented as advisory routing under the lean lane, distinct from the
  staged lane's gate-enforced reading at Stage 1.T, which is unchanged. No gate behavior
  changed. Migration: none.
- **test(intake-toolkit): exercise the ledger gate's TMPDIR fallback (#405)** (#405)

### `second-shift` 2.1.0 → 2.1.1

- **pair topology under the lean lane: two standalone onboards, cross-repo split at intake (#401)** (#401)
  a BE/FE pair repo now gets a hand-off from `/second-shift:onboard` to a second
  onboard run in the sibling repo — the host's `be-fe-pair` config is unchanged and still
  serves the staged lane, while the sibling gains its own standalone config so it can be
  worked with `/dev-pipeline:run-lean` from its own checkout. `intake-orchestrator` gains a
  pair-gated title check that terminally rejects a ticket whose title carries both of the
  configured `ticketTag` values or neither, plus an admission rule splitting genuine
  cross-repo scope into ordered per-repo tickets filed in each repo's own tracker.
  `ticketTag` is now documented as advisory routing under the lean lane, distinct from the
  staged lane's gate-enforced reading at Stage 1.T, which is unchanged. No gate behavior
  changed. Migration: none.

## v3.8.4

### `dev-pipeline` 3.8.3 → 3.8.4

- **lean-reconcile runs its five tracker-independent checks under jira (#389)** (#389)
  `lean-reconcile.sh` no longer exits 2 before any check on a
  `tracker.type: jira` consumer. It skips the claim-comment arm — that adapter
  posts no claim comment — and runs its other five, including the P10 authorship
  check, naming the dropped arm in its output and on its closing line. An
  unrecognized `tracker.type`, and `--comments-file` under jira, are now loud
  environment errors. Migration: none.

## v3.8.3

### `dev-pipeline` 3.8.2 → 3.8.3

- **fix(dev-pipeline): lean-gate runs setup lanes in the schema's shape (#386)** (#386)
  the lean lane's milestone 3 now runs `commands.<host>.lanes[]`
  setup steps instead of dying on them; a lane declaring no commands fails
  the milestone rather than being skipped silently.
  Migration: none.

## v3.8.2

### `dev-pipeline` 3.8.1 → 3.8.2

- **The mutation sweep re-derives every verdict on one core, including the ones that cannot have changed (#384)** (#384)
  the mutation sweep memoizes mutant verdicts, scores mutants in a
  worker pool, and stops a killed mutant at the first FAIL: line. New knobs:
  MUTATION_SWEEP_JOBS, MUTATION_SWEEP_CACHE, MUTATION_SWEEP_CACHE_DIR,
  MUTATION_SWEEP_CACHE_MAX, MUTATION_SWEEP_EARLY_EXIT, MUTATION_SWEEP_FAIL_PATTERN.
  The cache is advisory-lane only — never read or written under GITHUB_ACTIONS.
  Three selftests that wrote to a fixed /tmp path now write under their own mktemp
  tree, since two mutants of one guard run the same suite concurrently.
  Migration: none.
- **lean-gate milestone 3 runs the config's extra verify lanes (#383)** (#383)
  /dev-pipeline:run-lean's milestone 3 now runs commands.<repo>.extraLanes
  (when-scoped, sequential, fail-fast) and strips the pipeline's own seam vars from
  every milestone-3 lane child's environment. The dead `build` fixed key is gone.
  Migration: none — extraLanes is additive and was previously silently ignored
  under lean; a consumer with a `build`-only fixed-key command should move it to
  extraLanes (config-lint.sh has rejected `build` there since #113).
  none -- test-only, closes a coverage gap on already-shipped
  behavior (lanes[] seam-scrub was already correct, per the reviewer's own
  hand-verified fixture).

### `review-toolkit` 3.0.4 → 3.0.5

- **Relocate the design-fidelity reviewer routing into review-lead, and teach the registry lint a third root (#382)** (#382)
  review-lead now routes a design-fidelity reviewer on the repo's web-component
  surface, alongside a11y-reviewer — figma-faithful-reviewer under `design.provider:
  figma`, design-faithful-reviewer under `claude-design` or with no provider configured.
  The trigger is `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`).
  Repos without the design-toolkit plugin are unaffected: the dimension is skipped with a
  note and commits are never denied for it.
  Migration: none.
  the SHADOW drift tripwire covers the design-toolkit-shipped reviewer names,
  installed or not, so a repo-local file carrying one is still rejected. Consumers with no
  `design.provider` configured now get the same toolkit-absent note as those that declare
  one, instead of the dimension going silently unrun.
  Migration: none.

## v3.8.1

### `dev-pipeline` 3.8.0 → 3.8.1

- **The lean gate pays its most expensive milestone before a cheap one that already failed, and reports one fact three times (#376)** (#376)
  lean-gate.sh all now runs a cheap, read-only pre-pass over milestones
  1 and 4 before milestone 3's green gate, so a stale verdict record is reported
  before the ~15-minute sweep runs instead of after. check-lean-chain.sh's
  evidence-5 freshness check collapses to one refusal (naming the verdict value)
  for a non-approve record instead of three independent findings restating the
  same fact. lean-gate.sh milestone 1 now refuses when the issue declares an
  Open Region dispositioned pause-and-ask with no resolution artifact.
  Migration: none.
  none — the lean-green scenario leg was hitting a live gh issue view
  the moment milestone 1 grew a network-touching check; it now passes the same
  no-Open-Regions --issue-file default lean-gate-selftest.sh uses, restoring
  the zero-network property.
  `lean-gate.sh` milestone 1 now reads an Open Regions disposition
  from the row's last non-empty cell, so a table written without a trailing
  pipe no longer passes an unresolved pause-and-ask region; and it names every
  unresolved region in one refusal instead of one per run. The run-lean skill's
  Resume guidance now describes what `all` reports while the verdict is
  outstanding. Migration: none.
- **A lean fix round reviews the delta since the reviewed patch (#377)** (#377)
  a lean review round after a fix now reads only the delta since the
  patch the previous round covered, inheriting the rest by reference to that
  round's committed record. The verdict record gains `inherited_patch_id` and
  `inherited_from_verdict`, both derived — there is no flag — and every reader
  refuses a link that resolves to no record on the branch. `lean-gate.sh delta
  <issue>` prints the range a round must read. Migration: none; round-1 records
  and every record predating the key are unchanged and still accepted.
  milestone 4's pass line now states whether the verdict covers the whole
  branch diff itself or inherits N verified earlier rounds. Migration: none.
  a lean verdict record's own findings can no longer supply the inheritance key its
  three readers gate on — the key is written on every round (`none` on a chain root) and read
  from the record's header block. A round never inherits coverage from its own earlier version,
  and an uncommitted verdict record is reported as uncommitted rather than as a broken chain.
  Migration: none — records written before the sentinel are read as chain roots, as they were.

## v3.8.0

### `dev-pipeline` 3.7.0 → 3.8.0

- **feat(dev-pipeline): give run-lean a jira tracker adapter (#365)** (#365)
  /dev-pipeline:run-lean now runs on a read-only jira tracker. The
  claim step makes no tracker write and no longer requires GH_BOT, and the
  exit gate reads the PR body for `Closes [<KEY>]` plus the verdict-record
  path instead of a closing comment. GitHub behavior is unchanged; a config
  without `tracker.type` still takes the github arm.
  Migration: none.
- **feat(dev-pipeline): bind the lean verdict record to the head it reviewed (#367)** (#367)
  the lean verdict record now names the commit it reviewed (`reviewed_head`),
  and the build gate, the merge boundary and lean-reconcile.sh all refuse a record whose
  declared head is not the head being gated. Any push after an approve — a rebase, a
  force-push or a docs-only commit included — reopens the review round.
  Migration: verdict records written before this key carry none, and are refused at all
  three readers rather than grandfathered, because a remedy exists — one more review
  round on a dev-pipeline that writes the key (`/dev-pipeline:review-lean <pr>`). There
  is no waiver. No in-flight lean PR currently carries an approve verdict record, so
  nothing open is stranded by this.
- **Re-key retros to the artifact schema; lean runs enter the retro corpus (#369)** (#369)
  pipeline-retro and perf-retro now read lean/block runs (previously
  invisible to both). lean-gate.sh's progress and verdict records gain an optional
  `model:` field. New tool: `retro-corpus.sh`. Migration: none.
  none — dev-pipeline internal tooling.
  none — review record.
- **The receipt discovers intent — ratification bar, open regions, intent-gap channel, implementability probe (#368)** (#368)
  intake receipts carry a ratification bar. `ledger-lint.sh --receipt`
  adds a Kind axis (intent | fact | open) checked against provenance, plus a
  mandated Open Regions section with a per-region disposition (pause-and-ask |
  reversible-default-and-flag). A decision surfacing mid-build routes back through
  a committed intent-gap record, and scripts/check-lean-chain.sh refuses a merge
  while it is unratified. New intake-toolkit:implementability-probe agent reads a
  spec cold and enumerates what an implementer would have to guess; spec-reviewer's
  checklist gains a Discovery Coverage section (ratified-provenance share, a
  verification rung per AC, open regions with dispositions, zero-open-regions as a
  finding rather than a merit).
  Migration: none. The Kind cell is receipt-mode only, so in-plan Decision Ledgers
  and every existing lint path are unchanged.
  the receipt lint's Kind/open-region refusals and both `--help` ranges now have
  behavioral coverage, and run-lean's milestone-4 handoff message names the intent-gap
  ratification the merge boundary will refuse without.
  Migration: none.
- **fix(dev-pipeline): stop lean-gate-selftest's (o) case from comparing free disk space (#370)** (#370)
  none — selftest harness only.
- **Bind the lean verdict to the branch's patch identity, not a commit SHA (#373)** (#373)
  a rebase no longer voids a lean review verdict. The record now
  carries the patch identity of the branch's own diff, which is invariant
  under a replay and still moves when a commit — or a conflict resolution —
  changes a line. It does not cover a base change that breaks the branch
  with no textual conflict; that stays CI's job.
  Migration: none. Verdict records lacking the key keep their old behavior.
  `lean-gate.sh --help` again prints its full header, including the Seams
  block documenting the selftest override variables, which a header edit had truncated.
  Migration: none.

### `intake-toolkit` 2.3.0 → 2.3.1

- **The receipt discovers intent — ratification bar, open regions, intent-gap channel, implementability probe (#368)** (#368)
  intake receipts carry a ratification bar. `ledger-lint.sh --receipt`
  adds a Kind axis (intent | fact | open) checked against provenance, plus a
  mandated Open Regions section with a per-region disposition (pause-and-ask |
  reversible-default-and-flag). A decision surfacing mid-build routes back through
  a committed intent-gap record, and scripts/check-lean-chain.sh refuses a merge
  while it is unratified. New intake-toolkit:implementability-probe agent reads a
  spec cold and enumerates what an implementer would have to guess; spec-reviewer's
  checklist gains a Discovery Coverage section (ratified-provenance share, a
  verification rung per AC, open regions with dispositions, zero-open-regions as a
  finding rather than a merit).
  Migration: none. The Kind cell is receipt-mode only, so in-plan Decision Ledgers
  and every existing lint path are unchanged.
  the receipt lint's Kind/open-region refusals and both `--help` ranges now have
  behavioral coverage, and run-lean's milestone-4 handoff message names the intent-gap
  ratification the merge boundary will refuse without.
  Migration: none.

### `review-toolkit` 3.0.3 → 3.0.4

- **The receipt discovers intent — ratification bar, open regions, intent-gap channel, implementability probe (#368)** (#368)
  intake receipts carry a ratification bar. `ledger-lint.sh --receipt`
  adds a Kind axis (intent | fact | open) checked against provenance, plus a
  mandated Open Regions section with a per-region disposition (pause-and-ask |
  reversible-default-and-flag). A decision surfacing mid-build routes back through
  a committed intent-gap record, and scripts/check-lean-chain.sh refuses a merge
  while it is unratified. New intake-toolkit:implementability-probe agent reads a
  spec cold and enumerates what an implementer would have to guess; spec-reviewer's
  checklist gains a Discovery Coverage section (ratified-provenance share, a
  verification rung per AC, open regions with dispositions, zero-open-regions as a
  finding rather than a merit).
  Migration: none. The Kind cell is receipt-mode only, so in-plan Decision Ledgers
  and every existing lint path are unchanged.
  the receipt lint's Kind/open-region refusals and both `--help` ranges now have
  behavioral coverage, and run-lean's milestone-4 handoff message names the intent-gap
  ratification the merge boundary will refuse without.
  Migration: none.

## v3.7.0

### `dev-pipeline` 3.6.0 → 3.7.0

- **fix(dev-pipeline): make otel collector a stable global daemon, not a per-repo pane (#340)** (#340)
  none — docs-only fix to the cost-tracking-setup skill guide.
- **feat(dev-pipeline): promote the lean lane to default; deprecate the staged run (#349)** (#349)
  run-lean is no longer EXPERIMENTAL and is now the default
  dev-pipeline lane; /dev-pipeline:run is deprecated as an ablation/rollback
  lane. Descriptions and docs updated accordingly; no behavioral change to
  either lane's gates. Migration: none — new work should route
  /dev-pipeline:run-lean; /dev-pipeline:run keeps working unchanged.
  none — corrects the review-evidence trail for #344's PR, no consumer-visible
  change.
  none — corrects onboarding routing text and a review-record
  wording issue on #344; no behavioral change.
- **feat(dev-pipeline): resolve bot wrapper from config via gh-bot.sh (#358)** (#358)
  the bot wrapper now self-resolves from tracker.bot.envVar,
  wrapperPath, or the install default — operators no longer re-export
  GH_BOT on every harness Bash call, and pre-flight/doctor no longer
  abort with an empty path.
  Migration: none (tracker.bot.envVar default remains GH_BOT).
  gh-bot.sh's config-supplied envVar no longer reaches an eval — indirect
  expansion (${!name}) plus identifier validation replaces the shell-injection sink a
  review flagged. intake-orchestrator/SKILL.md's five write sites now resolve
  dev-pipeline's gh-bot.sh via the plugin-install-path convention instead of a bare
  $GH_BOT, closing AC-7 repo-wide. Adds real (non-overridden) git-common-dir coverage
  for gh-bot.sh's root-derivation branch (main checkout, subdirectory, and linked
  worktree), a doctor (d7-bot) case for the ok status, a claim-issue.sh
  disabled-resolver case, rc assertions on all five gh-bot.sh --path statuses, and
  anchors the claim-issue.sh parity guard on the actual invocation instead of a
  comment-matchable substring. Migration: none.
- **test(dev-pipeline): kill claim-issue's missing-resolver fail-open, re-key its baseline (#360)** (#360)
- **feat(dev-pipeline): author lean review verdicts outside the build session (#361)** (#361)
  lean review verdicts are now authored by a separate top-level review
  session (/dev-pipeline:review-lean <pr>) instead of by the build run. The build
  gate and the merge boundary both refuse a verdict record carrying the build
  run's identity, and the in-build reviewer workflow is removed.
  Migration: none for existing runs — milestone numbering and progress-file shape
  are unchanged; new runs hand off at milestone 4 instead of dispatching.
  milestone 4 no longer refuses a valid verdict record when the review
  session evaluates it, and evaluating the gate no longer overwrites the build
  run's cached identity. `lean-gate.sh verdict` now rejects a non-numeric --pr
  and --rounds 0.
  Migration: none.
  a lean verdict record must now be committed and must cover the head it
  is read against — milestone 4 and the merge boundary both refuse an approve with
  later code commits, so anything pushed after an approve costs another review
  round. The `verdict=` value is read first-match rather than counted, so a
  needs-work record whose summary quotes `verdict=approve` no longer passes. The
  claim comment now carries the build session id; claims posted before this pass
  with a note.
  Migration: none.

### `intake-toolkit` 2.2.2 → 2.3.0

- **feat(dev-pipeline): resolve bot wrapper from config via gh-bot.sh (#358)** (#358)
  the bot wrapper now self-resolves from tracker.bot.envVar,
  wrapperPath, or the install default — operators no longer re-export
  GH_BOT on every harness Bash call, and pre-flight/doctor no longer
  abort with an empty path.
  Migration: none (tracker.bot.envVar default remains GH_BOT).
  gh-bot.sh's config-supplied envVar no longer reaches an eval — indirect
  expansion (${!name}) plus identifier validation replaces the shell-injection sink a
  review flagged. intake-orchestrator/SKILL.md's five write sites now resolve
  dev-pipeline's gh-bot.sh via the plugin-install-path convention instead of a bare
  $GH_BOT, closing AC-7 repo-wide. Adds real (non-overridden) git-common-dir coverage
  for gh-bot.sh's root-derivation branch (main checkout, subdirectory, and linked
  worktree), a doctor (d7-bot) case for the ok status, a claim-issue.sh
  disabled-resolver case, rc assertions on all five gh-bot.sh --path statuses, and
  anchors the claim-issue.sh parity guard on the actual invocation instead of a
  comment-matchable substring. Migration: none.

### `second-shift` 2.0.2 → 2.1.0

- **feat(dev-pipeline): promote the lean lane to default; deprecate the staged run (#349)** (#349)
  run-lean is no longer EXPERIMENTAL and is now the default
  dev-pipeline lane; /dev-pipeline:run is deprecated as an ablation/rollback
  lane. Descriptions and docs updated accordingly; no behavioral change to
  either lane's gates. Migration: none — new work should route
  /dev-pipeline:run-lean; /dev-pipeline:run keeps working unchanged.
  none — corrects the review-evidence trail for #344's PR, no consumer-visible
  change.
  none — corrects onboarding routing text and a review-record
  wording issue on #344; no behavioral change.
- **fix(tools): bound the killer's process population; pin doctor.sh's report re-entry (#364)** (#364)
- **feat(dev-pipeline): author lean review verdicts outside the build session (#361)** (#361)
  lean review verdicts are now authored by a separate top-level review
  session (/dev-pipeline:review-lean <pr>) instead of by the build run. The build
  gate and the merge boundary both refuse a verdict record carrying the build
  run's identity, and the in-build reviewer workflow is removed.
  Migration: none for existing runs — milestone numbering and progress-file shape
  are unchanged; new runs hand off at milestone 4 instead of dispatching.
  milestone 4 no longer refuses a valid verdict record when the review
  session evaluates it, and evaluating the gate no longer overwrites the build
  run's cached identity. `lean-gate.sh verdict` now rejects a non-numeric --pr
  and --rounds 0.
  Migration: none.
  a lean verdict record must now be committed and must cover the head it
  is read against — milestone 4 and the merge boundary both refuse an approve with
  later code commits, so anything pushed after an approve costs another review
  round. The `verdict=` value is read first-match rather than counted, so a
  needs-work record whose summary quotes `verdict=approve` no longer passes. The
  claim comment now carries the build session id; claims posted before this pass
  with a note.
  Migration: none.

## v3.6.0

### `dev-pipeline` 3.5.0 → 3.6.0

- **feat(dev-pipeline): lint that doc-routing.md's routed paths resolve (#334)** (#334)
  `check-doc-routing.sh` (dev-pipeline tools) is a new fail-closed
  lint for `doc-routing.md` content, run at pre-flight and Stage-7 entry.
  Migration: none — the check is a no-op for repos with no doc-routing.md.
  none — fixes to an unreleased change on this branch.
- **fix(dev-pipeline): pipeline-retro resumes a dark retro-scorer before falling back (#336)** (#336)
  none — spec doc, no behavior change yet.
  pipeline-retro Step 2 now treats an empty retro-scorer return (no
  emit deadline covers this Task-tool dispatch) as a named failure mode:
  resume the same agent from its transcript before anything else, and if the
  resume also returns empty, the report records DARK — no output after
  resume instead of a blank cell or the self-score standing in unchallenged.
  Migration: none.
  none — verdict record, no behavior change.
- **fix(second-shift): broaden be/fe sibling detection; flag npm-run lintAutofixes no-op (#337)** (#337)
  onboard's pair-sibling detection now recognizes adjacent BE/FE
  checkouts whose names do not share a common prefix (e.g. fastapi-be +
  vue-fe), and config-lint rejects lintAutofixes:true combined with a plain
  `npm run` lint command that cannot forward the appended --fix flag.
  Migration: none.
- **fix(dev-pipeline): retire dead commands.<repo>.build, route onboarding through ext:build extraLane (#339)** (#339)
  none (spec only, no plugin behavior yet).
  `commands.<repo>.build` is removed (it was never executed by any
  verify lane); `/second-shift:onboard` now drafts a build/compile check as a
  `commands.<repo>.extraLanes` entry instead, which actually runs.
  Migration: docs/migrations/v1-to-v2.md — replace a committed
  `commands.<repo>.build` with an `extraLanes` entry.
  none (verdict record only).

### `intake-toolkit` 2.2.1 → 2.2.2

- **fix(intake-toolkit): exitplan-ledger-gate tier 3 works on GNU find (#338)** (#338)
  the ExitPlanMode ledger gate's session-fresh-plan fallback (tier 3)
  now works under GNU find instead of silently allowing every plan. A scan
  that errors for any reason now blocks instead of allowing.
  Migration: none.

### `second-shift` 2.0.1 → 2.0.2

- **fix(second-shift): broaden be/fe sibling detection; flag npm-run lintAutofixes no-op (#337)** (#337)
  onboard's pair-sibling detection now recognizes adjacent BE/FE
  checkouts whose names do not share a common prefix (e.g. fastapi-be +
  vue-fe), and config-lint rejects lintAutofixes:true combined with a plain
  `npm run` lint command that cannot forward the appended --fix flag.
  Migration: none.
- **fix(dev-pipeline): retire dead commands.<repo>.build, route onboarding through ext:build extraLane (#339)** (#339)
  none (spec only, no plugin behavior yet).
  `commands.<repo>.build` is removed (it was never executed by any
  verify lane); `/second-shift:onboard` now drafts a build/compile check as a
  `commands.<repo>.extraLanes` entry instead, which actually runs.
  Migration: docs/migrations/v1-to-v2.md — replace a committed
  `commands.<repo>.build` with an `extraLanes` entry.
  none (verdict record only).

## v3.5.0

### `dev-pipeline` 3.4.3 → 3.5.0

- **feat(dev-pipeline): reconcile a non-terminal state file against the tracker on resume (#325)** (#325)
  none — spec only, no plugin behavior yet.
  /dev-pipeline:run's resume logic now detects when the tracker
  already shows an in_progress issue closed via a merged PR and quarantines
  the stale state file via the existing statectl reclaim --release mechanism
  instead of blindly resuming stage work — see issue #149. No schema change;
  no new state fields. Migration: none.
  none — internal mutation-sweep hardening for #149's tool, no
  behavior change (verified via the pr-mode scoped sweep and the full selftest).
  none — verdict record only.
- **feat(dev-pipeline): harden statectl deviations[] ledger validation (#109) (#330)** (#330)
  statectl.sh now enum-validates Stage-5 checkpoint deviations[].kind,
  and (opt-in, via build-checkpoint-7 --affected-files/--out-of-scope-files)
  refuses a Stage-7 checkpoint whose changedFiles diverges from the plan's
  Affected-files/Out-of-scope sections without a matching deviations[] entry.
  Migration: none — both checks are additive and the scope-drift gate is inert
  until a caller passes the new flags.
  none — plan-scope-paths.sh has not shipped in a release yet
  (introduced earlier in this same #109 branch).
- **fix(dev-pipeline): config-lint rejects undriveable two-id monorepo configs (#329)** (#329)
  config-lint now rejects a topology.type=="monorepo" config with
  more than one topology.repos entry, or no entry with path==".", pointing
  at commands.<id>.lanes/extraLanes for a second independently-verified
  workspace. Migration: none — a two-id monorepo config was already
  undriveable at verify time; this surfaces the failure at lint time instead.
- **fix(dev-pipeline): verifyctl fails closed with CONFIG when a run verifies nothing (#331)** (#331)
  verifyctl.sh now emits status:"fail" with a CONFIG failure entry,
  instead of status:"pass", when a run has zero verify lanes configured and no
  allowUnverified opt-out set. Migration: none — this only affects a repo whose
  commands.<host> has lint/typeCheck/test/extraLanes all unset without also
  setting allowUnverified: true, which previously silently green-lit.
- **fix(dev-pipeline): lean-gate-selftest's gate() helper no longer leaks ambient RUN_ID (#332)** (#332)
  none — a selftest-only isolation fix, no consumer-visible behavior
  change. Migration: none.
- **fix(dev-pipeline): verifyctl scrubs pipeline seam vars from configured lane children (#333)** (#333)
  verifyctl.sh (dev-pipeline) no longer leaks SECOND_SHIFT_CONFIG,
  SECOND_SHIFT_REPO_ROOT, STATECTL_STATE_DIR, and related pipeline seam vars into a
  consumer's configured lane commands (setup/format/lint/type-check/test/extraLanes).
  preflight.sh's existing scrub is widened to match. No config or CLI surface change.
  Migration: none.

### `second-shift` 2.0.0 → 2.0.1

- **fix(dev-pipeline): config-lint rejects undriveable two-id monorepo configs (#329)** (#329)
  config-lint now rejects a topology.type=="monorepo" config with
  more than one topology.repos entry, or no entry with path==".", pointing
  at commands.<id>.lanes/extraLanes for a second independently-verified
  workspace. Migration: none — a two-id monorepo config was already
  undriveable at verify time; this surfaces the failure at lint time instead.

## v3.4.3

### `dev-pipeline` 3.4.2 → 3.4.3

- **fix(dev-pipeline): comment-add validates the receipt is an issue-comment permalink for its own ticket (#318)** (#318)
  `statectl comment-add` now rejects a --url that is not an
  issue-comment permalink for the ticket's own issue number (a PR URL, a PR
  review URL, a PR conversation comment, or a comment on a different issue
  are all refused); --force remains the crash-recovery escape and records a
  waiver. Migration: none.
- **fix(dev-pipeline): pipeline-doctor block 8 now flags missing lastUpdatedAt as stale (#321)** (#321)
  pipeline-doctor.sh's stale-claim check (block 8) now surfaces an
  in_progress state file with a missing lastUpdatedAt as a stale claim,
  instead of silently skipping it. Migration: none.
- **fix(dev-pipeline): lean-gate.sh entry no longer freezes run_id: unset into the progress header (#322)** (#322)
  run-lean's `entry` step no longer creates the progress file —
  milestone 1 does, after `claim` has cached RUN_ID, so the header's
  run_id field no longer freezes at "unset" on a normal run.
  Migration: none.
- **fix(dev-pipeline): resolve worktreesDir instead of interpolating it undefined (#323)** (#323)
  dev-pipeline's Stage-10 intake-pin cleanup and Stage-2 worktree
  creation now resolve topology.repos.<host>.worktreesDir's documented
  default instead of silently operating against an undefined variable;
  a resolution failure is now surfaced instead of swallowed.
  Migration: none.
- **fix(dev-pipeline): drop hostname from the RUN_ID recipe (#324)** (#324)
  the Pre-flight RUN_ID recipe no longer reads `hostname` — it
  frequently resolved to a personally identifying value (e.g. macOS's
  `<FirstName>-<LastName>s-<Model>` default) and landed verbatim in every
  `<!-- run_id: ... -->` marker posted to public tracker comments. The
  timestamp and random hex suffix already disambiguate concurrent runs, and
  a run stays correlatable via `pipelineSessions[].sessionId`, so the host
  component is dropped rather than hashed. Migration: none.
  none — same-PR follow-up to the RUN_ID hostname fix; the
  Public-repo-hygiene comment above FAMILY_SHORT described the old 3-part
  format and its hostname-redaction rationale, both now stale.

### `review-toolkit` 3.0.2 → 3.0.3

- **fix(review-toolkit): lockstep-validate MAP-file inline model: literals (#320)** (#320)
  check-model-tiers.sh now lockstep-checks an in-enum inline
  `model: '<tier>'` literal in the three MAP workflow files (code-review.mjs,
  intake-review.mjs, design-sync.mjs) against the dispatched agent's
  frontmatter, closing a gap where such a literal reached neither the MAP
  loop (which can't parse an unquoted `model:` key) nor the scalar loop
  (scoped to unit-tests.mjs/plan-review.mjs only) — so in-enum drift on one
  of these dispatches (e.g. structured-emitter) went undetected.
  Migration: none.

## v3.4.2

### `dev-pipeline` 3.4.1 → 3.4.2

- **fix(dev-pipeline): intake-review.mjs injects referencedDocs content instead of disclaiming it (#314)** (#314)
  intake-review.mjs's referencedDocs[].content now reaches the
  spec-reviewer and codebase-explorer dispatch prompts instead of being
  silently discarded while the prompt claimed the docs were already read.
  Migration: none.
- **fix(dev-pipeline): run-lean cost-block visibility + RUN_ID persistence (#315)** (#315)
  run-lean's step 8 now appends the pipeline cost block to the
  opened PR's description, not only the closing issue comment.
  Migration: none.
  lean-gate.sh no longer loses RUN_ID between separate `bash G ...`
  invocations — it caches the id to `<issue>-run-id` on first sight and
  reuses it, so the progress-file header stays consistent with the claim
  comment and verdict record instead of silently falling back to "unset".
  Migration: none.

## v3.4.1

### `dev-pipeline` 3.4.0 → 3.4.1

- **fix(dev-pipeline): statectl-selftest ledger-corroboration fixtures date-rolled (#312)** (#312)
  none (test-only fix; no consumer-visible behavior change).
- **dev-pipeline: emit-deadline stack for intake-review.mjs + plan-review.mjs (#283) (#310)** (#310)
  none (spec-only commit; no consumer-visible change yet).
  intake-review.mjs and plan-review.mjs no longer risk a full
  Stage-1/4 abort on a spec-reviewer or plan-reviewer turn-cap stall — a
  hung leg is now declared dark on a 15-minute wall-clock ceiling instead.
  Migration: none.
  none (verdict record only).
- **fix(dev-pipeline): lean-gate.sh claim helper resolves the wrong path (#311)** (#311)
  `/dev-pipeline:run-lean claim` no longer fails to locate
  claim-issue.sh. Migration: none.

### `review-toolkit` 3.0.1 → 3.0.2

- **dev-pipeline: emit-deadline stack for intake-review.mjs + plan-review.mjs (#283) (#310)** (#310)
  none (spec-only commit; no consumer-visible change yet).
  intake-review.mjs and plan-review.mjs no longer risk a full
  Stage-1/4 abort on a spec-reviewer or plan-reviewer turn-cap stall — a
  hung leg is now declared dark on a 15-minute wall-clock ceiling instead.
  Migration: none.
  none (verdict record only).

## v3.4.0

### `dev-pipeline` 3.3.0 → 3.4.0

- **feat(dev-pipeline): /dev-pipeline:run-lean — outcome-gated lean harness (experimental) (#307)** (#307)
  new experimental `/dev-pipeline:run-lean` skill — an outcome-gated lean
  alternative to `run`, gated by five artifact milestones and a CI merge-boundary
  evidence check. Off by default; `run` is unchanged.
  Migration: none.
  pipeline-cost-block.sh gains an additive --stateless mode (session ids +
  a time fence as arguments, session-window totals to stdout or a file, no
  cost-log.jsonl row) for harnesses with no state file. Existing invocations are
  behavior-unchanged.
  Migration: none.

## v3.3.0

### `dev-pipeline` 3.2.0 → 3.3.0

- **feat(dev-pipeline): harness-corroborated stage preconditions (#305)** (#305)
  statectl now verifies each stage's claimed skill loads, stage-file
  reads and stage-8 dispatch against the audit ledger before accepting the
  completion write, recording the outcome in stages.N.ledgerCorroboration.
  Repos without the audit hook are unaffected — corroboration fails open.
  Migration: none.

## v3.2.0

### `dev-pipeline` 3.1.0 → 3.2.0

- **feat(dev-pipeline): per-stage time + per-bucket cost envelopes from the run corpus (#302)** (#302)
  dev-pipeline gains `stage-envelopes.sh`, which derives per-stage time and
  per-cost-bucket USD envelopes from the recorded run corpus and flags over-envelope
  values. perf-retro's report gains a p90 column, a cost-envelope table and an
  over-envelope section that declares its corpus; pipeline-doctor gains a WARN-only
  section 9 on the most recent run. `stage-times.sh` gains an additive `--json` emit
  mode; its default text output is unchanged.
  Migration: none — advisory only, nothing gates on the output.

## v3.1.0

### `dev-pipeline` 3.0.0 → 3.1.0

- **fix(dev-pipeline,intake-toolkit): pass each Workflow script only the config keys it reads (#294)** (#294)
  Workflow dispatch sites now pass only the config keys each script reads,
  so `reviewers.modelOverrides` reaches dispatches instead of silently resolving to
  empty, and a config carrying shell-command strings can no longer break dispatch
  serialization. Migration: none.
- **feat(dev-pipeline): register pipeline sessions in the statectl write seam (#123) (#295)** (#295)
  session registration for cost attribution is now automatic — statectl's
  write seam records each contributing Claude session on its first state write, so a
  resume at any stage is attributed instead of silently dropped. pipeline-session-add
  remains for post-terminal manual backfill.
  Migration: none. Existing state files are not rewritten.

### `intake-toolkit` 2.2.0 → 2.2.1

- **fix(dev-pipeline,intake-toolkit): pass each Workflow script only the config keys it reads (#294)** (#294)
  Workflow dispatch sites now pass only the config keys each script reads,
  so `reviewers.modelOverrides` reaches dispatches instead of silently resolving to
  empty, and a config carrying shell-command strings can no longer break dispatch
  serialization. Migration: none.

### `review-toolkit` 3.0.0 → 3.0.1

- **fix(review-toolkit): a11y-reviewer states rules in HTML/ARIA/CSS, not JSX/Tailwind (#143)** (#143)
  a11y-reviewer now states its rules in framework-neutral HTML/ARIA/CSS
  terms, so it applies on Angular, Vue, and plain-CSS front ends instead of
  reading as React/Tailwind-only. Migration: none.

## v3.0.0

### `audit-toolkit` 2.0.1 → 2.1.0

- **feat(audit-toolkit): record what each tool call ran on in the ledger `target` field (#270)** (#270)
  audit ledger rows now carry a `target` field naming what each tool
  call ran on, making the ledger usable as gate evidence rather than only as a
  count. Additive — existing readers are unaffected.
  Migration: none.

### `design-toolkit` 2.2.0 → 2.2.1

- **refactor(design-toolkit): single-home the figma duplication and adopt reviewer-baseline (slice 2 of 3 for #167) (#278)** (#278)
  the two figma artifact reviewers now inherit the shared reviewer
  baseline (grounding, confidence scoring, tool discipline) while keeping their
  artifact-grading severity ladder and verdict contract unchanged; the figma
  skills single-home their capability and node-resolution sections.
  Migration: none.

### `dev-pipeline` 2.9.0 → 3.0.0

- **fix(dev-pipeline): document statectl --repo on its CLI surface; make pr-add fail closed and self-heal on be-fe-pair (#246)** (#246)
  statectl's CLI surface now documents `--repo` on `worktree-set`,
  `pr-add`, `verify-attempts` and `verify-summary-set`, and `pr-add --repo` now
  replaces a same-URL entry recorded under a different key instead of adding a
  duplicate — so a be-fe-pair run that recorded a PR with the wrong keying is
  repaired by re-running the correct call. Migration: none.
  `statectl pr-add` now fails with a clear error instead of writing a
  mis-keyed record when `--repo` is omitted on a `be-fe-pair` topology, where the
  branch-keyed form silently loses a PR on a dual-target run. Single-repo and
  monorepo consumers are unaffected. Migration: none — pair-topology callers
  following the Stage-9 per-repo loop already pass `--repo`.
- **feat(dev-pipeline): operator-authorized --force — reason-carrying waivers, auto-mode refusal, terminal blocking (PR 1 of 2 for #243) (#255)** (#255)
  statectl --force is now operator-authorized: it requires
  --force-reason, is refused outright in autonomous mode (state-transported
  .mode from init --mode), records one waivers[] entry per bypassed guard, and
  mark-completed refuses a waived run until an explicit --accept-waivers.
  Migration: scripted statectl callers that pass --force must add
  --force-reason "<why>" (>=20 chars); pipeline init call sites should pass
  --mode <resolved>.
- **feat: accept `fable` as an override-only model tier; close the unknown-token hole in check-model-tiers (#252)** (#252)
  reviewers.modelOverrides accepts `fable` as an override-only model tier
  (subscription-gated; shipped defaults unchanged; an inaccessible tier surfaces as a
  dead reviewer and the gate fails closed). check-model-tiers.sh now errors
  (UNKNOWN-MODEL) on unrecognized model tokens in shipped dispatch tables and inline
  literals instead of silently skipping them.
  Migration: none.
- **feat(dev-pipeline): make the Stage-6 INERT classifier overridable for non-JS/TS consumers (#256)** (#256)
  the Stage-6 INERT classifier accepts an optional pattern override, so
  repos whose surface is shell/Markdown can stop being classified inert; an
  uncompilable pattern now fails closed to the full suite instead of silently
  reporting inert.
  Migration: none -- absent config reproduces today's behavior exactly.
  verifyctl reads stageParams.inertPattern and applies it to Stage-6 lane
  classification.
  Migration: none.
  stageParams.inertPattern is validated by config-lint and documented in
  the config schema; an empty or uncompilable value is rejected before a run.
  Migration: none.
  preflight warns when a repo's configured verify lanes can never run
  because its whole tracked tree classifies inert, and stops reporting such a repo
  as pipeline-ready.
  Migration: none.
- **fix(dev-pipeline): anchor the Stage-9 cost-block helper to the plugin checkout (#261)** (#261)
- **feat(dev-pipeline): per-stage evidence legs + stage-file read receipts (PR 2 of 2 for #243) (#269)** (#269)
  stages 3/5/7/9 now carry machine-checked completion evidence on
  both tracker adapters (unitTestSurface, renderVerify, the Stage-7
  checkpoint, costBlockApplied + per-repo PR keys), and every stage 1-9
  requires its stage-file read receipt (statectl stage-file-read). A waived
  run's report must carry a ## Waivers section.
  Migration: fixture walks that complete stages directly must write the new
  evidence (see scenario-lib.sh stage_evidence); the cost-block sub-step must
  run before set-stage 9 --status completed.
- **feat(audit-toolkit): record what each tool call ran on in the ledger `target` field (#270)** (#270)
  audit ledger rows now carry a `target` field naming what each tool
  call ran on, making the ledger usable as gate evidence rather than only as a
  count. Additive — existing readers are unaffected.
  Migration: none.
- **feat(dev-pipeline): enum-validate the whole Decision Ledger provenance cell at plan-lint Check 4 (#239) (#274)** (#274)
  `plan-lint.sh` Check 4 now enum-validates the entire Decision Ledger
  provenance cell, not just the human-attributed subset. A plan whose provenance
  cell carries `assumed`, free prose, or a legal value with a trailing annotation
  (`codebase-derived (discovered at Stage 5)`) now fails the Stage-4 hard gate, as
  does a ledger row whose column count is outside the canonical
  `ID | Decision | Resolution | Provenance` schema.
  Migration: author each provenance cell as the bare enum value and move any
  annotation into the Resolution cell; keep the ledger table in the canonical
  column order. Committed plans are never re-linted, so no historical plan needs
  changing.
- **feat(intake-toolkit,dev-pipeline): sequential sub-issues verdict + predecessor gate (PR 1 of 3 for #262) (#275)** (#275)
  new `predecessor-gate.sh` backstop that keeps a sequential sub-issue from
  being claimed while its predecessor is still open. Migration: none.
  sequential decompositions now produce ordered sub-issues instead of
  stacked PRs. Each sub-issue is a plain single-PR run against the base branch and
  carries its own scope contract; ordering rides Predecessor:/Successor: trailers,
  with successors held out of the queue until the operator promotes them at merge.
  Migration: none — the stacked execution path still exists and is removed
  separately.
- **feat(dev-pipeline): record the session-resume pause span at statectl's write seam (#279)** (#279)
  a dev-pipeline run resumed by a fresh session now records its idle gap
  automatically at every stage, not just at the Stage-8 crash-recovery entry, so
  effective (compute) time in stage-times.sh and perf-retro stops counting the
  time a dead session was not running. The `statectl pause-add` subcommand is
  removed — nothing needs to call it.
  Migration: none. State files written before this change have no
  lastWriteSessionId; the first write stamps it and records no span.
- **refactor(dev-pipeline,review-toolkit): delete the stacked-PR machinery — execution path + state/scope contracts (#282)** (#282)
  the stacked-PR execution path is removed from the dev-pipeline
  skill. Runs branch from and target the configured baseBranch only; sequential
  decompositions are ordered sub-issues. tools/max-pushed-slice.sh and
  tools/start-slice.sh are deleted.
  Migration: none — intake stopped emitting the stacked verdict in the prior
  release, so no live run reaches the deleted path.
  the stacked AC-partition state and every slice-scoped grading path
  are removed. `decomposition`, `currentSlice`, `sliceBranch`,
  `priorSliceBranch` and `prBase` no longer exist; `statectl slice-set` and
  `slice-partition-set` are gone; plan-lint and the Stage-8 scope gate grade
  against the full AC snapshot, which for a sub-issue is already its own scope
  contract. `worktreeBase` is retained and re-documented as the be-fe-pair
  flat mirror.
  Migration: none — no live run wrote the removed fields.
- **refactor(dev-pipeline)!: retire the plan-pattern slice token — configVersion 1 to 2 (#285)** (#285)
  the planFilePattern {slice} token is retired and configVersion moves
  to 2. Pattern substitution now strips unknown tokens defensively, so an
  unmigrated override degrades to a valid plan path rather than embedding a
  literal token.
  Migration: set "configVersion": 2; if you override stageParams.planFilePattern,
  delete {slice} from it. See docs/migrations/v1-to-v2.md part 2.
  **BREAKING:** stageParams.planFilePattern no longer accepts the {slice} token and configVersion is now 2. Configs at configVersion 1 are rejected with a pointer to docs/migrations/v1-to-v2.md. Consumers who override planFilePattern delete the token; everyone else sets configVersion to 2 and is done.

### `intake-toolkit` 2.1.0 → 2.2.0

- **refactor(review-toolkit): centralize cross-agent boilerplate into reviewer-baseline (slice 1 of 3 for #167) (#254)** (#254)
  reviewer agents now inherit the extension-file contract and review-process
  boilerplate from the auto-loaded reviewer-baseline skill instead of restating it; the
  sub-agent trust model is now canonical in review-lead.
  Migration: none.
  reviewer agents no longer restate the shared scope and output-format
  boilerplate; both now come from the auto-loaded reviewer-baseline skill.
  Migration: none.
- **feat(dev-pipeline): enum-validate the whole Decision Ledger provenance cell at plan-lint Check 4 (#239) (#274)** (#274)
  `plan-lint.sh` Check 4 now enum-validates the entire Decision Ledger
  provenance cell, not just the human-attributed subset. A plan whose provenance
  cell carries `assumed`, free prose, or a legal value with a trailing annotation
  (`codebase-derived (discovered at Stage 5)`) now fails the Stage-4 hard gate, as
  does a ledger row whose column count is outside the canonical
  `ID | Decision | Resolution | Provenance` schema.
  Migration: author each provenance cell as the bare enum value and move any
  annotation into the Resolution cell; keep the ledger table in the canonical
  column order. Committed plans are never re-linted, so no historical plan needs
  changing.
- **feat(intake-toolkit,dev-pipeline): sequential sub-issues verdict + predecessor gate (PR 1 of 3 for #262) (#275)** (#275)
  new `predecessor-gate.sh` backstop that keeps a sequential sub-issue from
  being claimed while its predecessor is still open. Migration: none.
  sequential decompositions now produce ordered sub-issues instead of
  stacked PRs. Each sub-issue is a plain single-PR run against the base branch and
  carries its own scope contract; ordering rides Predecessor:/Successor: trailers,
  with successors held out of the queue until the operator promotes them at merge.
  Migration: none — the stacked execution path still exists and is removed
  separately.
- **refactor(intake-toolkit): single-home the jira delta and trim rationale prose (slice 3 of 3 for #167) (#280)** (#280)
  intake-orchestrator's jira delta, Step 0.5 rationale, dispatch mandate
  and threshold examples are de-duplicated — every rule keeps a home, and the
  jira delta is now stated once with short pointer tags at its former restatement
  sites. Migration: none.

### `review-toolkit` 2.4.0 → 3.0.0

- **feat(review-toolkit): bring plan-reviewer under the emit-deadline lint (#249)** (#249)
  plan-reviewer now carries an emit deadline at turn 10 of 15 and is
  covered by check-emit-deadline.sh, which grew a DEADLINE_AT_DEFAULT enrollment
  list so a named agent at the default turn cap can be held to the deadline
  contract. Agents above the default cap are unaffected.
  Migration: none.
- **feat: accept `fable` as an override-only model tier; close the unknown-token hole in check-model-tiers (#252)** (#252)
  reviewers.modelOverrides accepts `fable` as an override-only model tier
  (subscription-gated; shipped defaults unchanged; an inaccessible tier surfaces as a
  dead reviewer and the gate fails closed). check-model-tiers.sh now errors
  (UNKNOWN-MODEL) on unrecognized model tokens in shipped dispatch tables and inline
  literals instead of silently skipping them.
  Migration: none.
- **refactor(review-toolkit): centralize cross-agent boilerplate into reviewer-baseline (slice 1 of 3 for #167) (#254)** (#254)
  reviewer agents now inherit the extension-file contract and review-process
  boilerplate from the auto-loaded reviewer-baseline skill instead of restating it; the
  sub-agent trust model is now canonical in review-lead.
  Migration: none.
  reviewer agents no longer restate the shared scope and output-format
  boilerplate; both now come from the auto-loaded reviewer-baseline skill.
  Migration: none.
- **refactor(dev-pipeline,review-toolkit): delete the stacked-PR machinery — execution path + state/scope contracts (#282)** (#282)
  the stacked-PR execution path is removed from the dev-pipeline
  skill. Runs branch from and target the configured baseBranch only; sequential
  decompositions are ordered sub-issues. tools/max-pushed-slice.sh and
  tools/start-slice.sh are deleted.
  Migration: none — intake stopped emitting the stacked verdict in the prior
  release, so no live run reaches the deleted path.
  the stacked AC-partition state and every slice-scoped grading path
  are removed. `decomposition`, `currentSlice`, `sliceBranch`,
  `priorSliceBranch` and `prBase` no longer exist; `statectl slice-set` and
  `slice-partition-set` are gone; plan-lint and the Stage-8 scope gate grade
  against the full AC snapshot, which for a sub-issue is already its own scope
  contract. `worktreeBase` is retained and re-documented as the be-fe-pair
  flat mirror.
  Migration: none — no live run wrote the removed fields.
- **refactor(dev-pipeline)!: retire the plan-pattern slice token — configVersion 1 to 2 (#285)** (#285)
  the planFilePattern {slice} token is retired and configVersion moves
  to 2. Pattern substitution now strips unknown tokens defensively, so an
  unmigrated override degrades to a valid plan path rather than embedding a
  literal token.
  Migration: set "configVersion": 2; if you override stageParams.planFilePattern,
  delete {slice} from it. See docs/migrations/v1-to-v2.md part 2.
  **BREAKING:** stageParams.planFilePattern no longer accepts the {slice} token and configVersion is now 2. Configs at configVersion 1 are rejected with a pointer to docs/migrations/v1-to-v2.md. Consumers who override planFilePattern delete the token; everyone else sets configVersion to 2 and is done.

### `second-shift` 1.7.0 → 2.0.0

- **refactor(dev-pipeline)!: retire the plan-pattern slice token — configVersion 1 to 2 (#285)** (#285)
  the planFilePattern {slice} token is retired and configVersion moves
  to 2. Pattern substitution now strips unknown tokens defensively, so an
  unmigrated override degrades to a valid plan path rather than embedding a
  literal token.
  Migration: set "configVersion": 2; if you override stageParams.planFilePattern,
  delete {slice} from it. See docs/migrations/v1-to-v2.md part 2.
  **BREAKING:** stageParams.planFilePattern no longer accepts the {slice} token and configVersion is now 2. Configs at configVersion 1 are rejected with a pointer to docs/migrations/v1-to-v2.md. Consumers who override planFilePattern delete the token; everyone else sets configVersion to 2 and is done.

## v2.11.0

### `audit-toolkit` 2.0.0 → 2.0.1

- **test(dev-pipeline): prune the mirror-harness/prose class, add the Workflow runtime shim, fix CI reachability (PR 1 of 5 for #213) (#220)** (#220)
  the audit-toolkit smoke suite and the design-toolkit lib test suites
  now execute in CI; both were shipped but unreachable by the discovery glob.
  Migration: none.
  fixed the dev-pipeline design-sync gate path, which raised
  ReferenceError on every reviewer dispatch and could never have run.
  Migration: none.
  reviewer agents flag mirror-harness selftests and no longer sanction
  behavioral greps on Workflow .mjs seams, which are now executable via the
  runtime shim. Migration: none.

### `design-toolkit` 2.1.2 → 2.2.0

- **test(dev-pipeline): prune the mirror-harness/prose class, add the Workflow runtime shim, fix CI reachability (PR 1 of 5 for #213) (#220)** (#220)
  the audit-toolkit smoke suite and the design-toolkit lib test suites
  now execute in CI; both were shipped but unreachable by the discovery glob.
  Migration: none.
  fixed the dev-pipeline design-sync gate path, which raised
  ReferenceError on every reviewer dispatch and could never have run.
  Migration: none.
  reviewer agents flag mirror-harness selftests and no longer sanction
  behavioral greps on Workflow .mjs seams, which are now executable via the
  runtime shim. Migration: none.
- **feat(intake-toolkit): ticket-sourced provenance for operator decisions in comments (#152)** (#152)
  Decision Ledger provenance gains a fifth value, ticket-sourced,
  for decisions the operator resolved in a ticket comment and the run
  adopted. Its Resolution cell must cite the comment URL or ledger-lint
  fails the plan. Autonomous runs may now originate this value, unlike
  user-answered / user-delegated.
  Migration: none — existing four-value ledgers are unaffected.

### `dev-pipeline` 2.8.0 → 2.9.0

- **test(dev-pipeline): verdict-path liveness harness + CI holes + prose-presence prune (PR 1 of 2 for #205) (#208)** (#208)
  dev-pipeline selftests now assert composed verdict-path liveness
  (no-split, sub-issues, failure-path, stacked-prs) rather than only per-tool
  contracts, and the two previously CI-invisible workflows .mjs selftests run in
  CI. Migration: none.
- **test(dev-pipeline): contract-lockstep manifest + containment policy (PR 2 of 2 for #205) (#209)** (#209)
  dev-pipeline selftests now assert composed verdict-path liveness
  (no-split, sub-issues, failure-path, stacked-prs) rather than only per-tool
  contracts, and the two previously CI-invisible workflows .mjs selftests run in
  CI. Migration: none.
  contract pairs that were previously kept in sync by prose alone (the
  Decision-Ledger provenance enum, the AC-ID fallback rule, the FINDINGS_SCHEMA
  triple, and the stage-7/8 dual-target mirrors) are now mechanically enforced in
  CI. Migration: none.
- **test(dev-pipeline): prune the mirror-harness/prose class, add the Workflow runtime shim, fix CI reachability (PR 1 of 5 for #213) (#220)** (#220)
  the audit-toolkit smoke suite and the design-toolkit lib test suites
  now execute in CI; both were shipped but unreachable by the discovery glob.
  Migration: none.
  fixed the dev-pipeline design-sync gate path, which raised
  ReferenceError on every reviewer dispatch and could never have run.
  Migration: none.
  reviewer agents flag mirror-harness selftests and no longer sanction
  behavioral greps on Workflow .mjs seams, which are now executable via the
  runtime shim. Migration: none.
- **feat(intake-toolkit): ticket-sourced provenance for operator decisions in comments (#152)** (#152)
  Decision Ledger provenance gains a fifth value, ticket-sourced,
  for decisions the operator resolved in a ticket comment and the run
  adopted. Its Resolution cell must cite the comment URL or ledger-lint
  fails the plan. Autonomous runs may now originate this value, unlike
  user-answered / user-delegated.
  Migration: none — existing four-value ledgers are unaffected.
- **docs(dev-pipeline): name in-progress merge/rebase in the non-base-branch posture (#223)** (#223)
  the non-base-branch posture now places an in-progress merge or rebase
  (conflicts and all) in the dirty-working-tree WARN-and-proceed predicate, and states
  that merge and index state is per-worktree so `worktree add` neither reads nor
  disturbs it. Such a state is never a stop.
  Migration: none.
- **test: cover the dark enforcing gates — version-bump gate, exitplan ledger hook, mutation-gate parser, pipeline-doctor (PR 2 of 5 for #213) (#224)** (#224)
- **fix(dev-pipeline): plan-lint Check 6 tolerates formatter-owned byte differences (#226)** (#226)
  plan-lint Check 6 no longer fails Decision Ledger hydration on
  formatting-only differences between the backing ledger and the plan --
  whitespace runs and paired markdown emphasis delimiters are normalized
  before comparison, while any wording change still fails the gate.
  Migration: none.
- **feat(dev-pipeline): gate Stage-6 completion on a verifyctl attestation (#231)** (#231)
  Stage 6 of the dev-pipeline now refuses to complete unless
  verifyctl.sh actually ran for the current run, proven by its runId-scoped
  sidecar (per-target on a be-fe-pair run). A hand-composed verifySummary no
  longer closes the stage. Migration: none — any run that invokes verifyctl as
  the stage already mandates satisfies the gate; --force remains the
  crash-recovery escape for state files predating the sidecar convention.
- **test(dev-pipeline): extend scenario-liveness reach — circuit breaker, exhausted-review terminal, be-fe-pair, boundary header (PR 3 of 5 for #213) (#236)** (#236)
  the stacked-PR starting-slice precedence rule moves out of the
  Stage-1 stage doc into tools/start-slice.sh, which the doc now invokes; the
  rule is unchanged, including doing no remote derivation when a persisted
  currentSlice wins. Migration: none.
- **feat(dev-pipeline): perf-retro — cross-run execution-latency retrospective skill (#233)** (#233)
  new skill /dev-pipeline:perf-retro — a cross-run performance
  retrospective that profiles per-stage execution latency across recorded runs
  and proposes optimizations, each required to name an existing regression guard
  so speed is never bought by weakening a gate.
  Migration: none.
- **fix(dev-pipeline): key the implementation_resilience PASS gate on charged evidence (#235)** (#235)
  mark-completed now refuses `implementation_resilience: PASS` on any
  run that charged no TEST_FAILURE, not just on inert-lane runs — a green suite
  run exercised the resilience breaker no more than an inert one did, and scores
  N/A. The refusal message names the missing evidence instead of the lane, and
  `--force` still bypasses for crash recovery.
  Migration: none.
- **feat(dev-pipeline): order the Stage-8 review-lead load before its synthesis receipt (#234)** (#234)
  the Stage-8 skill-load gate now enforces ordering, not just presence
  — the review-lead load must be recorded before the synthesis comment's receipt
  is written, so loading the skill afterwards no longer satisfies it. The
  refusal message asks for a re-synthesis rather than a re-ordering.
  Migration: none.
  pipeline-retro's mandated-loads audit item now names what the new
  Stage-8 ordering gate enforces vs what still needs manual comparison — a
  review-lead load that post-dates the published synthesis is still a deviation
  even though its receipt was accepted.
  Migration: none.
- **test(dev-pipeline): E2E null-model full-run replay — gh shim, verdict-payload fixtures, crash-recovery resume (PR 4 of 5 for #213) (#238)** (#238)

### `intake-toolkit` 2.0.2 → 2.1.0

- **test(dev-pipeline): contract-lockstep manifest + containment policy (PR 2 of 2 for #205) (#209)** (#209)
  dev-pipeline selftests now assert composed verdict-path liveness
  (no-split, sub-issues, failure-path, stacked-prs) rather than only per-tool
  contracts, and the two previously CI-invisible workflows .mjs selftests run in
  CI. Migration: none.
  contract pairs that were previously kept in sync by prose alone (the
  Decision-Ledger provenance enum, the AC-ID fallback rule, the FINDINGS_SCHEMA
  triple, and the stage-7/8 dual-target mirrors) are now mechanically enforced in
  CI. Migration: none.
- **feat(intake-toolkit): ticket-sourced provenance for operator decisions in comments (#152)** (#152)
  Decision Ledger provenance gains a fifth value, ticket-sourced,
  for decisions the operator resolved in a ticket comment and the run
  adopted. Its Resolution cell must cite the comment URL or ledger-lint
  fails the plan. Autonomous runs may now originate this value, unlike
  user-answered / user-delegated.
  Migration: none — existing four-value ledgers are unaffected.
- **test: cover the dark enforcing gates — version-bump gate, exitplan ledger hook, mutation-gate parser, pipeline-doctor (PR 2 of 5 for #213) (#224)** (#224)

### `review-toolkit` 2.3.5 → 2.4.0

- **test(dev-pipeline): contract-lockstep manifest + containment policy (PR 2 of 2 for #205) (#209)** (#209)
  dev-pipeline selftests now assert composed verdict-path liveness
  (no-split, sub-issues, failure-path, stacked-prs) rather than only per-tool
  contracts, and the two previously CI-invisible workflows .mjs selftests run in
  CI. Migration: none.
  contract pairs that were previously kept in sync by prose alone (the
  Decision-Ledger provenance enum, the AC-ID fallback rule, the FINDINGS_SCHEMA
  triple, and the stage-7/8 dual-target mirrors) are now mechanically enforced in
  CI. Migration: none.
- **test(dev-pipeline): prune the mirror-harness/prose class, add the Workflow runtime shim, fix CI reachability (PR 1 of 5 for #213) (#220)** (#220)
  the audit-toolkit smoke suite and the design-toolkit lib test suites
  now execute in CI; both were shipped but unreachable by the discovery glob.
  Migration: none.
  fixed the dev-pipeline design-sync gate path, which raised
  ReferenceError on every reviewer dispatch and could never have run.
  Migration: none.
  reviewer agents flag mirror-harness selftests and no longer sanction
  behavioral greps on Workflow .mjs seams, which are now executable via the
  runtime shim. Migration: none.
- **feat(intake-toolkit): ticket-sourced provenance for operator decisions in comments (#152)** (#152)
  Decision Ledger provenance gains a fifth value, ticket-sourced,
  for decisions the operator resolved in a ticket comment and the run
  adopted. Its Resolution cell must cite the comment URL or ledger-lint
  fails the plan. Autonomous runs may now originate this value, unlike
  user-answered / user-delegated.
  Migration: none — existing four-value ledgers are unaffected.

### `second-shift` 1.6.2 → 1.7.0

- **feat(dev-pipeline): perf-retro — cross-run execution-latency retrospective skill (#233)** (#233)
  new skill /dev-pipeline:perf-retro — a cross-run performance
  retrospective that profiles per-stage execution latency across recorded runs
  and proposes optimizations, each required to name an existing regression guard
  so speed is never bought by weakening a gate.
  Migration: none.

## v2.10.0

### `dev-pipeline` 2.7.1 → 2.8.0

- **fix: namespace-agnostic Atlassian MCP at intake/Stage-1 fetch sites (#198)** (#198)
  intake-toolkit jira-fetch prose (intake-orchestrator / intake /
  intake-interviewer) references all three Atlassian MCP namespaces and the
  ToolSearch discovery step, not just mcp__atlassian__*.
  Migration: none.
  dev-pipeline Stage-1 / tracker-adapter fetch prose references all three
  Atlassian MCP namespaces + ToolSearch discovery, not just mcp__atlassian__*; a new
  scripts/check-intake-tracker-namespaces.sh guards the whole intake/Stage-1 surface
  against regressing to a single hardcoded prefix.
  Migration: none.
- **fix(dev-pipeline): cost block never leaves a bare null; uniform prs value shape (#201)** (#201)
  Stage-9 cost block no longer skips silently — a no-PRs run records
  costBlockApplied "skipped-no-prs" and an unresolvable state file fails loud
  (exit 2, never bare null); the sub-step is anchored at the control repo so
  cross-repo runs resolve the right state. statectl pr-add records a uniform
  { url, branch, repo } value across single-repo and be-fe-pair runs.
  Migration: none — readers key off .url; legacy url-only entries stay readable.
- **fix(dev-pipeline): verifyctl keys the command table on a single-target .targetRepos (#203)** (#203)
  a bare `verifyctl run` (no --repo) on a single-target be-fe-pair run now
  derives the command table from that one target repo instead of the path="." host, so
  Stage 8's re-verify and the Stage 6 safety-net stop running the host's commands against
  the target's flat-mirror worktree (a false TYPE_ERROR, an unrequested format mutation,
  and lost verify accounting). Absent / empty / >1-entry .targetRepos is unchanged;
  base/worktree/sidecar/budget resolution is untouched.
  Migration: none.
- **fix(dev-pipeline): mark-completed refuses a generous implementation_resilience PASS on an inert-lane run (#202)** (#202)
  mark-completed now refuses a Post-Run Eval scoring
  implementation_resilience: PASS on an inert-lane run (no test lane ran, no
  TEST_FAILURE charged) and requires N/A, closing a self-score inflation hole;
  suite-lane runs are unaffected. Migration: none.
- **feat(dev-pipeline): persist the Stage-9 run report before narrating it (#150)** (#150)
  the Stage-9 run report is now persisted to
  .claude/pipeline-state/{issue}-report.md before the pipeline narrates it, so
  an API disconnect during the final response no longer destroys the record of
  a successful run. mark-completed refuses the terminal write when the report
  is missing.
  Migration: none.
- **fix(dev-pipeline): slice-scope the gates that dead-ended every stacked-prs run (#206)** (#206)
  stacked-prs runs persist the intake AC->slice partition into
  state (decomposition.slices[].acIds) so downstream gates can scope by
  slice. Migration: none (field is additive; absent = full-ticket behavior).

### `intake-toolkit` 2.0.1 → 2.0.2

- **fix: namespace-agnostic Atlassian MCP at intake/Stage-1 fetch sites (#198)** (#198)
  intake-toolkit jira-fetch prose (intake-orchestrator / intake /
  intake-interviewer) references all three Atlassian MCP namespaces and the
  ToolSearch discovery step, not just mcp__atlassian__*.
  Migration: none.
  dev-pipeline Stage-1 / tracker-adapter fetch prose references all three
  Atlassian MCP namespaces + ToolSearch discovery, not just mcp__atlassian__*; a new
  scripts/check-intake-tracker-namespaces.sh guards the whole intake/Stage-1 surface
  against regressing to a single hardcoded prefix.
  Migration: none.
- **fix(dev-pipeline): slice-scope the gates that dead-ended every stacked-prs run (#206)** (#206)
  stacked-prs runs persist the intake AC->slice partition into
  state (decomposition.slices[].acIds) so downstream gates can scope by
  slice. Migration: none (field is additive; absent = full-ticket behavior).

### `review-toolkit` 2.3.4 → 2.3.5

- **fix(dev-pipeline): slice-scope the gates that dead-ended every stacked-prs run (#206)** (#206)
  stacked-prs runs persist the intake AC->slice partition into
  state (decomposition.slices[].acIds) so downstream gates can scope by
  slice. Migration: none (field is additive; absent = full-ticket behavior).

## v2.9.2

### `second-shift` 1.6.1 → 1.6.2

- **fix(second-shift): scope local-dev-refresh to the second-shift marketplace (#196)** (#196)
  /second-shift:local-dev-refresh now refreshes only the
  second-shift marketplace and the plugins installed from it, instead of
  every marketplace on the machine. Use `claude plugin update <id>@<mkt>`
  for other marketplaces.
  Migration: none.

## v2.9.1

### `dev-pipeline` 2.7.0 → 2.7.1

- **fix(review-toolkit): scope-completeness-reviewer namespace-agnostic Atlassian MCP (#189)** (#189)
  scope-completeness-reviewer now discovers the Atlassian MCP under any
  of its three registration namespaces (top-level, plugin-bundled, or claude.ai
  Rovo) instead of a single hardcoded prefix, so the Scope Completeness Gate is no
  longer unsatisfiable for plugin/Rovo-registered JIRA consumers.
  Migration: none.

### `review-toolkit` 2.3.3 → 2.3.4

- **fix(review-toolkit): scope-completeness-reviewer namespace-agnostic Atlassian MCP (#189)** (#189)
  scope-completeness-reviewer now discovers the Atlassian MCP under any
  of its three registration namespaces (top-level, plugin-bundled, or claude.ai
  Rovo) instead of a single hardcoded prefix, so the Scope Completeness Gate is no
  longer unsatisfiable for plugin/Rovo-registered JIRA consumers.
  Migration: none.

## v2.9.0

### `dev-pipeline` 2.6.4 → 2.7.0

- **feat(dev-pipeline): plan-lint Check 6 hard-verifies pre-flight ledger hydration (#193)** (#193)
  plan-lint now hard-verifies that a pre-flight /plan-interview ledger's
  decisions were actually hydrated into the plan verbatim — a run that ignores or
  drifts from an existing {issue}-ledger.md now fails the Stage-4 plan gate instead
  of passing silently. Runs with no backing ledger are unaffected.
  Migration: none.
- **fix(dev-pipeline): pre-flight abort recovery is a hard handoff (#192)** (#192)
  dev-pipeline now documents that recovery from a pre-flight
  abort is a hard handoff — re-run /dev-pipeline:run from the top rather
  than continuing in-place, so early setup steps (RUN_ID, claim, Stage-2
  session record) are not silently skipped.
  Migration: none.

## v2.8.4

### `design-toolkit` 2.1.1 → 2.1.2

- **refactor(dev-pipeline): run-surface prose debloat — dedup, ceremony cuts, audit defect fixes (#172)** (#172)
  the dev-pipeline run-surface instruction layer is ~1.9k words slimmer —
  duplicated contracts collapsed to a single canonical site, the inert-lane rationale
  relocated into tools/is-inert-diff.sh (guarded by its selftest's 28-case golden-master
  parity check), and narrative issue-number references dropped from operational prose.
  Also corrects three documentation defects: stale stage references in hooks.md, a
  duplicated sentence in stages/2-worktree.md, and an off-by-one step citation in
  second-shift/onboard. Migration: none.

### `dev-pipeline` 2.6.3 → 2.6.4

- **fix(dev-pipeline): plan-lint mechanically enforces [NEW] grounding tags (#181)** (#181)
  dev-pipeline plan-lint now fails a plan that creates files or
  helpers without the literal [NEW] grounding tags (eval criterion 2 is
  grep-scored, so untagged plans scored FAIL at retro time despite passing
  the Stage-4 gate). Migration: none for existing merged plans; new plans
  must tag planned creations with [NEW].
- **fix(dev-pipeline): genericize the Stage-3/5 prose contracts off the birth stack (#154)** (#154)
  the Stage-3/5 prompt contracts and doc-update surfaces no longer name
  the birth stack as normative — .project/, Drizzle, *.spec.ts, and apps/api
  literals are config-resolved or labeled illustrative, and dead unit-testing
  skill references are repointed to review-toolkit:mutation-review.
  Migration: none.
- **fix(review-toolkit): exhaustive reviewers need an emit deadline, not a bigger maxTurns cap (#184)** (#184)
  scope-completeness and mutation reviewers now emit their result
  incrementally and write by a turn-numbered deadline, so a large diff yields a
  partial verdict instead of a dark reviewer. Dark-reviewer errors now distinguish a
  turn-cap death from a malformed result. Migration: none.
  new check-emit-deadline.sh gate - an agent whose maxTurns exceeds the
  default must declare a turn-numbered emit deadline below it, and the cap cited in
  the agent doc must match frontmatter. Migration: none; the shipped panel already
  complies.
- **refactor(dev-pipeline): run-surface prose debloat — dedup, ceremony cuts, audit defect fixes (#172)** (#172)
  the dev-pipeline run-surface instruction layer is ~1.9k words slimmer —
  duplicated contracts collapsed to a single canonical site, the inert-lane rationale
  relocated into tools/is-inert-diff.sh (guarded by its selftest's 28-case golden-master
  parity check), and narrative issue-number references dropped from operational prose.
  Also corrects three documentation defects: stale stage references in hooks.md, a
  duplicated sentence in stages/2-worktree.md, and an off-by-one step citation in
  second-shift/onboard. Migration: none.

### `review-toolkit` 2.3.2 → 2.3.3

- **fix(dev-pipeline): genericize the Stage-3/5 prose contracts off the birth stack (#154)** (#154)
  the Stage-3/5 prompt contracts and doc-update surfaces no longer name
  the birth stack as normative — .project/, Drizzle, *.spec.ts, and apps/api
  literals are config-resolved or labeled illustrative, and dead unit-testing
  skill references are repointed to review-toolkit:mutation-review.
  Migration: none.
- **fix(review-toolkit): exhaustive reviewers need an emit deadline, not a bigger maxTurns cap (#184)** (#184)
  scope-completeness and mutation reviewers now emit their result
  incrementally and write by a turn-numbered deadline, so a large diff yields a
  partial verdict instead of a dark reviewer. Dark-reviewer errors now distinguish a
  turn-cap death from a malformed result. Migration: none.
  new check-emit-deadline.sh gate - an agent whose maxTurns exceeds the
  default must declare a turn-numbered emit deadline below it, and the cap cited in
  the agent doc must match frontmatter. Migration: none; the shipped panel already
  complies.

### `second-shift` 1.6.0 → 1.6.1

- **refactor(dev-pipeline): run-surface prose debloat — dedup, ceremony cuts, audit defect fixes (#172)** (#172)
  the dev-pipeline run-surface instruction layer is ~1.9k words slimmer —
  duplicated contracts collapsed to a single canonical site, the inert-lane rationale
  relocated into tools/is-inert-diff.sh (guarded by its selftest's 28-case golden-master
  parity check), and narrative issue-number references dropped from operational prose.
  Also corrects three documentation defects: stale stage references in hooks.md, a
  duplicated sentence in stages/2-worktree.md, and an off-by-one step citation in
  second-shift/onboard. Migration: none.

## v2.8.3

### `dev-pipeline` 2.6.2 → 2.6.3

- **fix(review-toolkit): raise exhaustive-agent turn caps out of the deterministic death zone (#179)** (#179)
  review-toolkit's scope-completeness-reviewer and
  unit-test-mutation-reviewer no longer die at their turn caps on large
  surfaces (caps raised 15/12 to 30); dev-pipeline's bounded-exploration lint
  now requires dormant nudge constants to be declared with a dormancy marker.
  Migration: none.

### `review-toolkit` 2.3.1 → 2.3.2

- **fix(review-toolkit): raise exhaustive-agent turn caps out of the deterministic death zone (#179)** (#179)
  review-toolkit's scope-completeness-reviewer and
  unit-test-mutation-reviewer no longer die at their turn caps on large
  surfaces (caps raised 15/12 to 30); dev-pipeline's bounded-exploration lint
  now requires dormant nudge constants to be declared with a dormancy marker.
  Migration: none.

## v2.8.2

### `dev-pipeline` 2.6.1 → 2.6.2

- **fix: cost-block stage labels, resumed-session cost attribution, and a commit-blocking model-tier false positive (#177)** (#177)
  Pipeline cost blocks now label stages correctly (Implement was reported as "Plan", Verify as "Implementation", Doc Update as "Verify") and include the cost of a resumed session, which was previously dropped entirely.
  Migration: none for new runs. Cost blocks on already-open PRs keep the old labels and totals until regenerated — delete the block from the PR body and re-run pipeline-cost-block.sh <issue>.
  check-model-tiers no longer reports false drift for a workflow dispatch that re-states its model inline (e.g. structured-emitter dispatched model: 'haiku' from a file whose scalar default is sonnet or opus). As a PreToolUse hook, that false positive denied every commit in an affected repo.

### `review-toolkit` 2.3.0 → 2.3.1

- **fix: cost-block stage labels, resumed-session cost attribution, and a commit-blocking model-tier false positive (#177)** (#177)
  Pipeline cost blocks now label stages correctly (Implement was reported as "Plan", Verify as "Implementation", Doc Update as "Verify") and include the cost of a resumed session, which was previously dropped entirely.
  Migration: none for new runs. Cost blocks on already-open PRs keep the old labels and totals until regenerated — delete the block from the PR body and re-run pipeline-cost-block.sh <issue>.
  check-model-tiers no longer reports false drift for a workflow dispatch that re-states its model inline (e.g. structured-emitter dispatched model: 'haiku' from a file whose scalar default is sonnet or opus). As a PreToolUse hook, that false positive denied every commit in an affected repo.

## v2.8.1

### `dev-pipeline` 2.6.0 → 2.6.1

- **fix(dev-pipeline): validateShape honors string-typed array items (#174)** (#174)
  reviewers that record sub-threshold notes in suppressed[] are no
  longer declared dark — validateShape now checks the schema's declared
  items.type instead of requiring every array element to be an object.
  Migration: none.

## v2.8.0

### `dev-pipeline` 2.5.0 → 2.6.0

- **feat(dev-pipeline): eliminate the StructuredOutput stall class via explorer/emitter transport (#170)** (#170)
  schema-forced dev-pipeline dispatchers now carry a dispatch-time
  bounding nudge, and a new lint fails CI when one is added without a declared
  disposition. Plan-review and unit-test dispatches retry once instead of twice,
  with an escalated emit-early retry prompt.
  Migration: none.
  none.
  none.
  none.
  Stage 4/5 reviewer dispatches no longer force a structured-output
  call on the exploring agent — reviewers emit a parsed text contract, with a
  tool-less transcription agent as the schema fallback. Eliminates the
  StructuredOutput stall class on those stages (measured 7/8 -> 0/8 on the
  worst-case plan at a third of the token cost). Migration: none.
  all schema-forced reviewer/produce dispatches across the six
  workflow dispatchers now use the schema-free explorer text contract with a
  tool-less transcription fallback; reviewer-visible envelopes are unchanged.
  Migration: none.
  the bounded-exploration lint now fails any schema-carrying dispatch
  in production workflow files that is not the tool-less emitter or a declared
  validator reference — reintroducing a schema onto an exploring agent is a CI
  failure, not a style choice. Migration: none.
  none.
  none.
  none.

### `review-toolkit` 2.2.1 → 2.3.0

- **feat(dev-pipeline): eliminate the StructuredOutput stall class via explorer/emitter transport (#170)** (#170)
  schema-forced dev-pipeline dispatchers now carry a dispatch-time
  bounding nudge, and a new lint fails CI when one is added without a declared
  disposition. Plan-review and unit-test dispatches retry once instead of twice,
  with an escalated emit-early retry prompt.
  Migration: none.
  none.
  none.
  none.
  Stage 4/5 reviewer dispatches no longer force a structured-output
  call on the exploring agent — reviewers emit a parsed text contract, with a
  tool-less transcription agent as the schema fallback. Eliminates the
  StructuredOutput stall class on those stages (measured 7/8 -> 0/8 on the
  worst-case plan at a third of the token cost). Migration: none.
  all schema-forced reviewer/produce dispatches across the six
  workflow dispatchers now use the schema-free explorer text contract with a
  tool-less transcription fallback; reviewer-visible envelopes are unchanged.
  Migration: none.
  the bounded-exploration lint now fails any schema-carrying dispatch
  in production workflow files that is not the tool-less emitter or a declared
  validator reference — reintroducing a schema onto an exploring agent is a CI
  failure, not a style choice. Migration: none.
  none.
  none.
  none.

## v2.7.0

### `dev-pipeline` 2.4.0 → 2.5.0

- **fix(dev-pipeline): prose-budget distinguishes no-instruction-layer from vacuous coverage (#151)** (#151)
  prose-budget.sh now reports a distinct failure when its instruction-layer
  roots exist but match no files, and reports n/a (passing) when a repo has no local
  instruction layer at all — previously both cases silently exited 0. Baselines are now
  per-repo at .claude/prose-budget.baseline.tsv.
  Migration: run 'prose-budget.sh --update-baseline' once per repo to snapshot a local
  baseline; until then files report NEW, which is a warning and not a failure.
- **fix(dev-pipeline): reviewer diff ranges resolve the merge-base (#130) (#155)** (#155)
  reviewer prompts now describe a three-dot diff range, so a review branch
  is never reported as deleting commits that only exist on its base branch.
  Migration: none.
  reviewer agents and the review-lead / mutation-review skills now specify
  a three-dot diff range, so reviewers see only the branch's own changes.
  Migration: none.
- **fix(dev-pipeline): mandated skill loads are recorded completion evidence (#158)** (#158)
  Stage 1 and Stage 8 completion now require the mandated skill load
  (intake-toolkit:intake-orchestrator / review-toolkit:review-lead) to be
  recorded via the new statectl skill-load-add subcommand; the interactive
  inline-approved intake carve-out and the be-fe-pair cross-boundary/skip
  paths remain exempt, --force bypasses for crash-recovery. pipeline-retro now
  diffs skillsLoaded[] against the session audit ledger. Migration: runs
  started before this version resume with --force at the stage-1/8 boundary.
- **fix(dev-pipeline): scope-compliance eval credits deviations[]-disclosed edits (#161)** (#161)
  scope-compliance eval criterion now treats a Stage-6 edit
  disclosed in deviations[] before commit as in-scope (the auto-mode analog
  of user approval); silent unplanned edits still fail. Migration: none.
- **fix(dev-pipeline): mandated stage comments gate completion via recorded receipts (#162)** (#162)
  stages that mandate an issue comment (1: claimed+intake, 3: plan,
  7: doc-update, 8: code-review when a primary round ran, 9: pr) cannot
  complete without the posted comment's URL recorded via the new statectl
  comment-add subcommand, so a dropped backgrounded post surfaces at the stage
  boundary instead of vanishing; read-only trackers (tracker.writes: false)
  are exempt; Stage 8 additionally files its consolidated report as a real PR
  review on every terminating path. Migration: pre-existing runs resume with
  --force at the gated boundaries.
- **fix(dev-pipeline): plan-lint gates Decision Ledger provenance (#163)** (#163)
  dev-pipeline Stage-4 plan-lint now hard-fails a plan whose
  Decision Ledger asserts a human decision (user-answered/user-delegated)
  without a pre-flight {issue}-ledger.md backing it — mechanizing the
  pipeline-retro provenance contract into the mechanical gate. An
  autonomous run must use codebase-derived/deferred provenance only.
  Migration: none.
  none.
  none.
- **feat(dev-pipeline): statectl reclaim — detect and release stale orphaned claims (#164)** (#164)
  new statectl reclaim subcommand detects a run stranded in_progress
  by an infra drop (age-based staleness, read-only verdict naming the
  resumable stage) and --release quarantines the state file so the queue can
  re-pick the issue; pipeline-doctor lists stale claims with the exact
  remediation commands; failed/completed runs are never reclaimable.
  Migration: none.

### `review-toolkit` 2.2.0 → 2.2.1

- **fix(dev-pipeline): reviewer diff ranges resolve the merge-base (#130) (#155)** (#155)
  reviewer prompts now describe a three-dot diff range, so a review branch
  is never reported as deleting commits that only exist on its base branch.
  Migration: none.
  reviewer agents and the review-lead / mutation-review skills now specify
  a three-dot diff range, so reviewers see only the branch's own changes.
  Migration: none.

## v2.6.0

### `dev-pipeline` 2.3.0 → 2.4.0

- **feat(dev-pipeline): stage-8 a11y/design trigger reads stageParams.webComponentGlobs (#132)** (#132)
  the Stage-8 accessibility and design-fidelity reviewers now trigger on the
  globs in stageParams.webComponentGlobs instead of a hardcoded apps/web React path,
  so non-React or non-apps/web frontends get that reviewer class. An unmatched surface
  is now reported instead of silently skipped.
  Migration: none — the key defaults to the previous literal.
- **fix(dev-pipeline): plan-lint trims AC cells without xargs quote semantics (#135)** (#135)
  plan-lint no longer aborts with "xargs: unterminated quote" when an
  acceptance-criteria traceability cell contains an apostrophe, so a plan naming
  a test like coverage-can't-fail clears the Stage-4 plan-structure gate instead
  of hard-failing it.
  Migration: none.
  none.
- **feat(second-shift): flag the false-green all-null command table and document setup lanes (#137)** (#137)
  preflight now warns and withholds its "pipeline-ready" verdict when a
  repo has no verifying lane configured, instead of reporting green while
  verifying nothing. Set commands.<id>.allowUnverified=true to declare a
  deliberate zero-lane opt-out and restore the green verdict.
  Migration: none.
  onboarding now flags an all-null command table instead of presenting it
  as finished, and documents that a fresh pipeline worktree needs a
  commands.<id>.lanes[] setup step before dependency-requiring verify lanes can run.
  Migration: none.
  none.
  the config JSON schema now documents commands.<id>.allowUnverified,
  so editors stop flagging a valid zero-lane opt-out.
  Migration: none.
- **fix(dev-pipeline): is-inert-diff treats .known-extensions as inert (#139)** (#139)
  the dev-pipeline INERT lane now covers
  `.claude/second-shift/.known-extensions`, so a diff that only touches the
  extension allowlist no longer pays the full verify suite. A same-named file
  at any other path still selects SUITE.
  Migration: none.
- **fix(dev-pipeline): cost-block amends via plain gh when the bot is disabled (#142)** (#142)
  the Stage-9 cost block now lands on repos that do not run a GitHub
  App bot, amended under operator identity instead of being skipped. A missing
  gh CLI now records skipped-no-gh-cli rather than skipped-otel-error, and
  skipped-no-bot-wrapper is recorded only when a bot is actually enabled.
  Migration: none.
- **fix(dev-pipeline): per-repo fix-attempt budget is enforced and reported (#99) (#138)** (#138)
  the fix-attempt budget now actually stops a runaway verify lane on
  be-fe-pair and monorepo consumers, and per-repo verdicts report their charge
  counts instead of an empty map. Single-repo behavior is unchanged.
  Migration: none.
  none.
- **fix(dev-pipeline): anchor bot-commit.sh config resolution at the git common dir (#144)** (#144)
  pipeline commits now carry the bot identity in worktrees where the
  consumer config is gitignored, instead of silently falling back to the
  operator's git identity; the fallback that remains announces itself on
  stderr. Migration: none.
  none.
- **fix(dev-pipeline): pipeline-retro files only meaningful issues (#148)** (#148)
  pipeline-retro no longer files an issue per finding — "Record
  only" (the retro report) is the default route, and new issues require
  recurrence-or-corruption, a known fix, and no existing coverage.
  Migration: none.
- **fix(dev-pipeline): mark-completed enforces the locked eval criteria shape (#153)** (#153)
  mark-completed now refuses a self-eval whose criteria do not score
  exactly the five locked keys from eval-criteria.md with PASS|FAIL|N/A values,
  naming the offending keys; --force bypasses the shape check only
  (crash-recovery escape). Migration: none — eval files already following the
  eval-criteria.md example shape are unaffected.

### `second-shift` 1.5.0 → 1.6.0

- **feat(second-shift): flag the false-green all-null command table and document setup lanes (#137)** (#137)
  preflight now warns and withholds its "pipeline-ready" verdict when a
  repo has no verifying lane configured, instead of reporting green while
  verifying nothing. Set commands.<id>.allowUnverified=true to declare a
  deliberate zero-lane opt-out and restore the green verdict.
  Migration: none.
  onboarding now flags an all-null command table instead of presenting it
  as finished, and documents that a fresh pipeline worktree needs a
  commands.<id>.lanes[] setup step before dependency-requiring verify lanes can run.
  Migration: none.
  none.
  the config JSON schema now documents commands.<id>.allowUnverified,
  so editors stop flagging a valid zero-lane opt-out.
  Migration: none.

## v2.5.0

### `dev-pipeline` 2.2.7 → 2.3.0

- **Verified calibration claims — expiry + declarative probes (#68).** New `claims-lint.sh`: severity-downgrading
  maturity claims declared in fenced `second-shift-claims` blocks under `.claude/second-shift/**/*.md` carry a
  MANDATORY date-form `reverify-by`; an expired or malformed claim FAILs the per-run pipeline pre-flight (new
  step 0c) and onboarding `preflight.sh`. Optional declarative probe DSL (`path-exists:` / `path-absent:` /
  `pattern-absent:<ere> in <target>`) — literal find/grep args, never eval; failing probe = WARN with remediation,
  vanished probe root = `probe-broken` WARN, a passing probe reports `not-yet-contradicted` (never "verified").
  Fixture + selftest triad mirrors config-lint. Contract: `docs/extension-points.md` "Verified calibration claims".
  Migration: none — no claims fences reproduces prior behavior byte-for-byte.


- **Stage-1 intake terminal stops now write pipeline state.** The failure-shaped Stage-1 intake
  verdicts (spec-reviewer true blockers, >5 resolvable gaps, escalation) previously ended the run
  via tracker comment + label swap but wrote nothing to `.claude/pipeline-state/{issue}.json` —
  the file was left at `status: in_progress` forever, so under `tracker.type: jira`
  (`tracker.writes: false`) the run left zero durable record. Two new `failureContext.reason`
  values — `intake-spec-blocked` (blockers / gap-overflow, disambiguated by an `outcome` detail)
  and `intake-needs-human-input` (escalation, carrying the `question`) — added to the
  `valid_failure_reason` closed enum (state-schema.md table → regenerated `statectl.sh` via
  `gen-statectl-validators.sh`; drift-check byte-match). Stage-1 (`stages/1-intake.md`) now calls
  `mark-failed` after the orchestrator's tracker actions for these stops. The `SKILL.md`
  "No silent failures" contract is corrected: the three intake stops are no longer undeclared
  state-less failures; the one remaining state-less carve-out — the `sub-issues` split verdict
  (success-shaped, tracker-recorded) — is now explicitly declared, with a follow-up tracked for
  its success-shaped state termination. **Re-queue note:** an intake-stopped issue leaves
  `status: failed` locally; re-running requires the originating machine to clear its state file
  (`rm .claude/pipeline-state/{issue}.json`) — `statectl init` will not reset a `failed` file.
  The Stage-1 read-pin teardown now runs at EVERY Stage-1 exit, not only the completion path —
  intake stops never reach Stage 10, so the stop paths previously leaked the pin worktree.
  Migration: none — additive enum values + a new state write on paths that previously wrote none.


- **A mis-shaped setup lane is no longer a silent false green (#100).** `commands.<id>.lanes[]` is
  declared object-only in the schema, but `config-lint` never enforced it and `verifyctl` silently
  skipped what it could not read — so a config with `lanes: ["npm ci"]` linted clean, installed
  nothing, and still reported `status: pass`.
  - `config-lint.sh` now rejects a non-object `lanes[]` / `extraLanes[]` entry with a clean
    `must be an object {...}` violation. Previously a string/number/array entry produced **zero
    findings** (jq evaluates `+` right-to-left, and `.name?` on a non-object yields `empty`, which
    collapsed the whole check chain before the `keys` call was reached), while `null` and a
    non-object `extraLane` crashed jq with rc=5 instead of reporting.
  - `verifyctl.sh` now records an **INFRA** failure for a non-object entry in both the setup-lane
    and `extraLanes` loops, instead of leaving the command count empty and skipping the lane.
  - `preflight.sh`'s lane read is guarded with `select(type == "object")` — one malformed entry
    used to abort the whole jq stream (its error hidden by `2>/dev/null`), silently dropping
    **every** lane including well-formed ones.
  - Migration: a config using the undocumented string shorthand now **fails config-lint**. This
    surfaces an existing break rather than creating one — such a lane never executed under any
    consumer. Rewrite `["npm ci"]` as `[{"name": "install", "commands": ["npm ci"]}]`.

- Pre-flight surfaces the section gate + coverage line (cross-plugin review-toolkit resolution
  with a hermetic env override); a missing review-toolkit is a disclosed skip, not a silent pass (#67).


- **The verify verdict can no longer claim lanes that never ran (#98).** Three convergent defects
  let a run assert verification it did not perform — release-blocking for the generality claim.
  - `verifyctl.sh` lane verdicts now initialize `skipped` and are **promoted on execution** — a
    setup- or format-lane failure that short-circuits the trio leaves the un-run lanes `skipped`,
    never their old optimistic `clean`/`passed` inits.
  - `verifySummary.build` → **`setup`** (`clean|failed|skipped`): the field only ever reported the
    `lanes[]` setup outcome; the misleading name and its `"clean"` default are gone. The **config
    key** `commands.<id>.build` is retained unchanged — executing it as a real lane is #113.
  - `statectl set-stage 6 --status completed` now enforces a **content gate** on object summaries:
    at least one verifying lane (`lint`/`typeCheck`/`test`/`ext:*`) must have actually run. The
    predicate is positive over present keys (absent keys fail — `{"format":"clean"}` is refused);
    `format`/`setup` never satisfy it; a `setup:"failed"` summary gets a die naming the setup
    failure. Applied per-target in the be-fe-pair branch too. String summaries are untouched.
  - Two legitimate skips ride the existing string path: `commands.<repo-id>.allowUnverified: true`
    (zero-lane safety valve — inert when any verifying lane is configured, and never emitted over
    a recorded failure) and the when-gated `extraLanes` miss (verification configured, diff matched
    no glob — the INERT posture). `config-lint` accepts `allowUnverified` (boolean, type-checked).
  - Out of scope, tracked separately: executing `commands.<id>.build` (#113); the verdict's own
    top-level `status` staying `pass` on a zero-verification run (#115).
  - Migration: a consumer whose config has **no verifying lane** (`lint`/`typecheck`/`test`/
    `extraLanes` all null/absent) will now fail Stage-6 completion; configure a lane or set
    `commands.<repo-id>.allowUnverified: true`. Consumers reading `verifySummary.build` (none
    known in-tree) read `setup` instead.
- **feat(dev-pipeline): record intake terminal verdicts in pipeline state (#117)** (#117)
- **fix(dev-pipeline): a mis-shaped setup lane must be loud, not a false green (#100) (#114)** (#114)
- **feat: review-context section catalog, exact-name lint, coverage report + onboard scaffold (#86)** (#86)
- **fix(dev-pipeline): verify verdict never claims a lane that did not run (#98) (#120)** (#120)
- **feat(dev-pipeline): verified calibration claims — claims-lint expiry + declarative probe DSL (#68) (#87)** (#87)
- **docs(dev-pipeline): Stage-1 started-write instruction + Post-Run Eval file shape (#121)** (#121)

### `review-toolkit` 2.1.4 → 2.2.0

- security-reviewer: Maturity calibration now points at the `second-shift-claims` contract — a claim past its
  `reverify-by` is not honored for `[Pre-existing]` downgrades when a claims block is present (#68).

- **Review-context section catalog + exact-name lint (#67).** `scripts/section-catalog.txt` is the
  machine-readable source of truth for the named `review-context.md` sections reviewers key on
  (`section-name | readers | status`, plus a `deprecated-alias-of` tombstone table).
  `scripts/check-review-context-sections.sh` lints against it: `--preflight` fails closed on alias
  drift and present-but-empty catalog sections, `--report` prints an exit-neutral coverage line
  (which reviewers run degraded), default mid-run is advisory; `.known-sections` (and `section:`
  lines in `.known-extensions`) whitelist intentional off-catalog headings. The effective-registry
  computation is shared with the basename lint via `scripts/_effective-registry.sh`.
  `reviewer-baseline` treats an empty/TODO-bodied section as absent (infer conservatively AND
  disclose). Migration: none — repos without off-catalog headings lint clean as-is.
- **feat: review-context section catalog, exact-name lint, coverage report + onboard scaffold (#86)** (#86)
- **feat(dev-pipeline): verified calibration claims — claims-lint expiry + declarative probe DSL (#68) (#87)** (#87)

### `second-shift` 1.4.2 → 1.5.0

- **Onboard emits a consumer-repo CI evidence workflow (on request) — the server-side backstop (#33).** New
  templates `templates/consumer/second-shift-ci.yml` + `second-shift-ci-check.sh` (+ hermetic selftest): on
  every PR the check **(a)** config-lints the committed config with the `config-lint.sh` shipped AT the pinned
  marketplace ref (fetched fresh — CI runners have no plugin cache; mirrors onboard Step 5's fetch-at-ref) and
  **(b)** asserts the settings ref and lockfile ref agree (ports `doctor.sh`'s lockstep check), so a half-done
  upgrade PR is caught. Exit = FAIL count; a real drift/violation is a FAIL, a "couldn't verify" fetch/tool
  failure is a non-fatal WARN. The workflow only reports a red check — marking it a required status check in
  branch protection (the repo admin's step; onboard never configures branch protection) is what blocks merge.
  Onboard offers it in the Step-3 elicitation batch and emits both files verbatim (the check reads repo+ref from
  the committed lockfile — no emit-time substitution). The `Second-Shift:` PR trailer + `gates-unverified` label
  from the issue's second paragraph are deferred (out of scope). `docs/onboarding.md` + the consent doc updated.

- doctor: quiet `claims-lint` summary line (claim count + probe-less slugs) when calibration claims exist;
  FAILs when a claim is expired/malformed (#68).

- `doctor --report` gains a one-line section-coverage summary; `/second-shift:onboard` offers a
  `review-context.md` scaffold (accept-or-edit, default "later"; only human-confirmed sections,
  never a TODO body, never a fabricated `## Maturity stage`) (#67).
- **feat: review-context section catalog, exact-name lint, coverage report + onboard scaffold (#86)** (#86)
- **feat(dev-pipeline): verified calibration claims — claims-lint expiry + declarative probe DSL (#68) (#87)** (#87)
- **feat(second-shift): onboard emits on-request consumer CI evidence workflow (#33) (#73)** (#73)
- **feat: derive plugin versions + CHANGELOG at release time (#125)** (#125)
  PRs stop bumping plugin.json / editing CHANGELOG.md; versions and the
  changelog section are derived at release time on the release PR from conventional
  commits and Changelog: trailers.
  Migration: put consumer-visible change notes in a Changelog: commit trailer
  (or Changelog: none); never edit CHANGELOG.md or version fields in a feature PR.
  releases are cut by merging the auto-generated release PR; /release is gone.
  Migration: maintainers trigger a release with 'gh workflow run release-pr.yml' (or just
  merge the open release/next PR) instead of running /release, and refresh their machine
  with /second-shift:local-dev-refresh. Contributors must stop editing plugin.json
  versions and CHANGELOG.md, and must add a 'Changelog:' trailer (or 'Changelog: none')
  to any PR touching plugins/**.

## v2.4.1 — tool-discipline contract for reviewers; consent doc defers to the lockfile

### `second-shift` 1.4.1 → 1.4.2
- Consent-doc template (`SECOND-SHIFT.md`) no longer renders a `| plugin | version |` table — a
  second copy of the lockfile's `plugins` map that drifted on every release. It now names the
  enabled plugins (`{{PLUGIN_LIST}}`) and defers versions to `second-shift.lock.json`, which
  doctor already verifies; the template's design-toolkit skill list also gains the missed
  `figma-iterate` (#96). Migration: none — the doc regenerates on the next
  `/second-shift:onboard`; existing consumer docs keep working as-is.

### `review-toolkit` 2.1.3 → 2.1.4

- **Tool Discipline contract in `reviewer-baseline` (#95).** New `## Tool Discipline` section: an
  availability-conditional preference (prefer `Grep`/`Glob`/`Read` where the harness exposes them;
  where it does not — the current condition, `Bash` present + `Grep`/`Glob` withheld — batched Bash
  search is **sanctioned**, explicitly NOT one-command-per-call), a substitution-into-variable ban
  scoped to locating/reading files (`F=$(find …); grep "$F"`), and a four-part Bash sanction list
  (git; tests/linters/build; mandated config-resolution one-liners — the base-branch resolvers stay
  as-is; mandated tracker fetches). It is a documented contract, not a dispatch-time nudge (the nudge
  measured null/harmful — #95). The test-coverage grounding bullet no longer models `wc -l` → `Read`.
  `review-lead-synth` now declares `tools: Read` (the eval dispatcher needs no Bash/Grep/Glob) and
  cites the plugin-shipped `review-lead` source path. Availability-conditional wording on
  `codebase-explorer`'s search step. Migration: none — documentation/agent-metadata only.

### `design-toolkit` 2.1.0 → 2.1.1

- **Availability-conditional search wording (#95).** The `Grep`/`Glob` search lines in
  `figma-faithful-reviewer` (3), `figma-faithful-spec-reviewer` (1), and the `figma-faithful` skill
  (1) now read as availability-conditional (Grep/Glob where exposed, otherwise batched Bash search).
  The sanctioned base-branch `BASE=$(jq …)` config idioms are byte-unchanged. Migration: none —
  agent/skill-doc wording only.

### `dev-pipeline` 2.2.6 → 2.2.7

- **`tool-discipline-probe.mjs` — the measurement instrument (#95).** New Workflow probe beside
  `stall-probe.mjs`: dispatches shell-touching reviewers under one selected instruction arm
  (`baseline` | `grep-nudge` | `strict-one-command`) over a shell-heavy diff and captures
  StructuredOutput deaths, so a future tool-preference proposal is A/B'd, not asserted. Its header
  documents the measured three-arm baseline (~71% compound-shaped Bash; grep-nudge null; strict
  one-command 3/6 turn-cap reviewer deaths). Migration: none — additive instrument.
## v2.4.0 — figma-iterate: the interactive fast-path over figma-faithful

### `design-toolkit` 2.0.2 → 2.1.0
- **New skill `figma-iterate`: an interactive fast-path over `figma-faithful` for quick UX
  iteration.** Takes Figma node URL(s) + optional override notes and produces a structurally
  faithful implementation, but swaps the dev-pipeline ceremony (ticket → branch → plan-reviewer
  gate → review panel → PR) for **one batched discrepancy checkpoint** (`AskUserQuestion`:
  follow-Figma / follow-my-note / skip, per row) and leaves the tree dirty (never commits). A
  hard **interactive-only guard** rejects a non-interactive context (Workflow/pipeline-dispatched
  or no `AskUserQuestion`) before any Figma read. Precedence: override notes beat Figma; Figma
  beats code for structure; code beats Figma only for mechanical token/component mapping (mapped
  and noted, never silent). Optional `review` flag runs `figma-faithful-reviewer` on the
  uncommitted working-tree diff (`git add -N . && git diff HEAD`). Reuses figma-faithful's
  discipline by reference — no new config keys, no new agents, no pipeline plumbing. Migration:
  none — additive; `figma-faithful` and the pipeline path are untouched.

## v2.3.0 — design.liveRender: the live-render verify gate executes

### `dev-pipeline` 2.2.5 → 2.2.6
- **`design.liveRender` — the Stage-5 live-render verify gate actually executes (#84).** New optional config
  block `design.liveRender = { command, cwd?, readyProbe? }`: `command` is a repo-owned render script with
  `{route}`/`{out}` placeholders; the consumer harness owns boot/auth/screenshot and emits a PNG the gate
  semantically diffs against the cached design frame. Config absent / probe failure / command failure all
  degrade to `render-verify-unavailable` **with a detail** — non-blocking, exactly the pre-existing posture.
  Schema + config-lint (+ fixtures/selftest), Stage-5 gate rewrite, state-schema vocabulary update, new
  consumer guide `docs/live-render.md`. Migration: none — key absent reproduces prior behavior byte-for-byte.

### `design-toolkit` 2.0.1 → 2.0.2
- figma-faithful step-9 live-render note: when consumer config defines `design.liveRender`, its command is
  the canonical render mechanism (#84).

### `second-shift` 1.4.0 → 1.4.1
- `/second-shift:onboard` design step: when design is accepted, detect a `render:verify`-shaped script in the
  FE repo and offer a pre-filled `design.liveRender` block (#84).

## v2.2.0 — read-only preflight: the onboarding finish line

### `dev-pipeline` 2.1.8 → 2.2.0
- **New tool `skills/run/tools/preflight.sh` (+ selftest): read-only onboarding finish line (#30).** Echoes the
  resolved targets (tracker/repos/branches + string-only worktree paths — no `statectl init`, no `git worktree
  add`), runs the config gates (`config-lint`, `check-extensions`), invokes the config-aware `pipeline-doctor.sh`
  as its environment section (the #17 layer — reused, not duplicated), performs ONE tracker READ (no claim;
  queue head without a ticket key; jira SKIPs with a note — its fetch is session-side MCP), executes every
  non-null command lane once in the current checkout (source-mutating lanes — `format` as a string, `lint`
  with `lintAutofixes: true` — SKIP-with-note, never run), and writes `.claude/pipeline-state/preflight-report.md`.
  Exit code = FAIL count. Zero tracker/git/remote mutations — proven by `preflight-selftest.sh`'s zero-write
  suite (git-state diff + mock-gh verb recording). Tracker README gains the `preflight-read` operation row.

### `dev-pipeline` 2.2.0 → 2.2.1
- **#48 (Phase 2) — dual-target Stage 3 plan grouping + Stage 7 per-repo checkpoint.** Consumes the Phase-1
  statectl foundation. When `.targetRepos` has more than one repo: **Stage 3** groups the plan's "Affected
  files/modules" section by repo (`### <repoId> files`, paths relative to each repo's worktree — one plan
  file still covers the whole ticket); **Stage 7** builds a per-repo checkpoint — one
  `build-checkpoint-7-perrepo` fragment per target (branch/worktreePath from the `worktrees` map, HEAD +
  changed files recomputed per worktree, INERT-lane verifySummary wrapped to an object), merged and given the
  shared envelope, written through the dual-mode `validate_stage7_payload`. The `deviations[]` ledger gains a
  required `repo` field per entry when `targetRepos > 1`. New `stage7-perrepo-checkpoint-selftest.sh`:
  integration (two synthetic git worktrees → the exact Stage-7 block → an accepted per-repo checkpoint) + a
  drift guard on the `.md` block's load-bearing tokens. Single-target pairs and non-pair topologies are
  unchanged (the flat path). Stage 5 (per-repo implement) and Stage 8 (per-repo review) land in Phases 3–4.

### `dev-pipeline` 2.2.1 → 2.2.2
- **#48 (Phase 3) — dual-target Stage 5 per-repo implement.** The behavioral fix: for a dual `[BE]+[FE]` ticket
  Stage 5 now authors code in **every** target worktree, not just the primary. Following Stage 3's repo-grouped
  plan, each repo's work is done in that repo's own worktree (resolved from the `worktrees` map) and committed
  there with `git -C <repo worktree>` — one commit lands in exactly one repo, never mixing files from two repos.
  Downstream stays per-repo (Stage 6 verify, Stage 7 checkpoint, Stage 8 review, Stage 9 PR). The unit-test
  mutation gate is unchanged — it operates on the mutation-surface (host) worktree, which the flat mirror
  already points `WT` at. Mirrors the vendored be-fe-pair reference. Gated on `targetRepos > 1`; single-target
  pairs and non-pair topologies implement in the one flat worktree exactly as before. New
  `stage5-perrepo-implement-selftest.sh` drift-guards the per-repo commit instruction (a silent removal would
  regress dual-target to primary-only). Stage 8 per-repo review is the final phase (4).

### `dev-pipeline` 2.2.2 → 2.2.3
- **#48 (Phase 4, CLOSES #48) — dual-target Stage 8 per-repo review.** The finish line. For a dual `[BE]+[FE]`
  ticket Stage 8 now reviews **every** target repo, not just the primary. The main review loop covers the
  primary (flat-mirror) worktree unchanged; a new secondary-review loop then, for each other target repo,
  asserts a clean worktree, and — if that repo's branch has a diff — reviews it in-session via the same
  `code-review.mjs` fan-out scoped to its worktree (review-lead routing auto-selects design/FE reviewers by
  diff), recording `crossBoundaryReviews[].status="completed-in-session"`; a no-diff repo records
  `skippedReviews[]`, and a repo that can't be reviewed in-session records a non-blocking `pending` handoff
  (Stage 9 already surfaces these as PR "review pending" bullets). Two new statectl writers
  (`cross-boundary-review-add`, `skipped-review-add`) — array-append, idempotent per `--repo`, a `pending`
  handoff requires the boundary triple — replacing the vendored's raw-jq state writes (second-shift bans them).
  6 new statectl-selftest cases (cbr1–cbr5, skr1) + `stage8-perrepo-review-selftest.sh` (integration over three
  synthetic worktrees: primary skipped, diff repo → completed-in-session, no-diff repo → skipped, Stage 8
  completes; plus a drift guard). The Stage-8 completion escape hatch (Phase 1) and Stage-9 handoff consumer
  already existed. Gated on `targetRepos > 1`; single-target pairs and non-pair topologies are unchanged.
  **With this, a `[BE]+[FE]` cross-repo ticket implements, reviews, and opens PRs in both repos — #48 done.**

### `dev-pipeline` 2.2.3 → 2.2.4
- **#59 — Stage-1 reads pin to `origin/<baseBranch>`; the non-main-base reject becomes a graded posture.**
  New Step 1.P (stages/1-intake.md): after the claim, fetch the configured base and create a throwaway
  detached worktree (`<worktreesDir>/intake-pin-<issue>`); the intake fan-out reads ONLY under it —
  `workflows/intake-review.mjs` gains a `readRoot` arg that prefixes both dispatch prompts with the
  pinned-read instruction. With reads pinned, a non-base current branch is no longer a reject: clean tree →
  proceed silently; dirty tree → WARN ("a human appears to be mid-work in this checkout") and proceed; pin
  unestablishable → fail closed with the retained `non-main-base-autonomous` reason (re-semanticized to the
  pin-failure trigger in state-schema.md — value neither renamed nor retired, so statectl validators and the
  selftest are untouched). Stage 10 removes a surviving pin worktree as the crash backstop. New
  `tools/intake-readroot-selftest.sh` pins the seam's load-bearing tokens in the green gate.
  `eval-criteria.md` criterion 1 rewords to the pin posture (wrong-repo/branch/diff detection unchanged).
- **Hermetic-selftest env hygiene (#34, found while dogfooding).** A Stage-6 verify run exports pipeline
  seam vars (`SECOND_SHIFT_CONFIG`, `BRANCH_PREFIX`) into the test command; the tools under test honor them
  as documented overrides, which clobbered the fixtures of four hermetic selftests (`check-extensions`,
  `preflight`, `statectl`, `slice-derivation`) — spuriously red under the pipeline while green in CI. Each
  now `unset`s the seam vars at its top so it controls its own environment. No tool/verifyctl behavior changed.

### `dev-pipeline` 2.2.4 → 2.2.5
- **#1 — persist a Stage-1 pre-flight attestation and gate Stage-1 completion on it.** Converts eval criterion 1
  (correct base / clean-tree pre-flight) from executor-self-asserted to **state-machine-enforced**. Step 1.P
  (stages/1-intake.md) now records `preflight: { baseBranch, workingTreeClean, guardOutcome }` into the Stage-1
  checkpoint payload, and `statectl set-stage 1 --status completed` refuses unless
  `stageCheckpoint["1"].preflight` is present and **well-formed** — a shared `preflight_wellformed` jq predicate
  checks *shape* (`baseBranch` non-empty string, `workingTreeClean` boolean, `guardOutcome` non-empty string),
  **not truthiness**: `workingTreeClean:false` is valid, the blessed dirty-tree WARN-and-proceed state.
  `checkpoint 1` additionally rejects a present-but-malformed `preflight` at write time (`validate_stage1_payload`,
  mirroring `validate_stage7_payload`). `guardOutcome` is deliberately **free-form** (canonical `proceed-clean` /
  `proceed-dirty-warn`) — not a closed enum — so the change stays off the `gen-statectl-validators.sh` drift
  contract; the edited gate lives above the generated region, so the drift-check is unaffected. `--force` still
  bypasses the gate (crash-recovery escape for pre-attestation state files). `statectl-selftest.sh` gains `sc1`
  negative/positive cases (`workingTreeClean:false` allowed) + an `sc1b` write-time-validation case; the
  `complete_stage` helper, the `(r4)` drift-check round-trip, the `(u)` stress case, both jira fixtures, and
  `stage8-perrepo-review-selftest.sh`'s setup loop all seed a well-formed preflight so the strengthened gate does
  not cascade the suite. Tracker-agnostic (the attestation is written by the shared Stage-1 path).

### `intake-toolkit` 2.0.0 → 2.0.1
- **#59 (docs) — intake fan-out arg contract gains `readRoot`.** The intake-orchestrator transport
  description now documents the optional pinned-read-surface arg the dev-pipeline passes from Step 1.P.

### `review-toolkit` 2.1.2 → 2.1.3
- **Hermetic-selftest env hygiene (#34).** `check-review-context-selftest.sh` now unsets the pipeline seam
  vars (`SECOND_SHIFT_CONFIG` et al.) at its top — a leaked ambient `SECOND_SHIFT_CONFIG` (exported by a
  dev-pipeline Stage-6 verify run) previously clobbered its fixture config. Same class of fix as the four
  dev-pipeline selftests above; no reviewer behavior changed.

### `second-shift` 1.3.1 → 1.4.0
- **Onboard Step 8.5 now runs the preflight as the finish line** (resolves the dev-pipeline install path via
  `claude plugin list --json` — never a cache path from memory), surfacing the report verdict before the
  first-run instructions. The "until a read-only preflight ships" hedge is gone; `docs/onboarding.md` names
  preflight as the step between validation and the first real ticket.
- **Feedback channel: `/second-shift:doctor --report` + issue forms (#34).** `doctor.sh` gains a `--report`
  flag that assembles a paste-ready bundle in one command — the normal doctor output (captured from a nested
  no-arg run), `claude plugin list --json`, the **auto-redacted** config (secret-shaped keys masked; `clientId`
  / `appName` / `installationId` preserved), and the newest `.claude/pipeline-state/` excerpt (the
  `.failureContext` a fail-fast abort writes). Always exits 0 — it assembles, it does not gate. Covered by two
  new `doctor-selftest.sh` scenarios (`report-sections`, `report-redaction`) + a `config-with-secret.json`
  fixture. For a zero-telemetry project, structured issues ARE the analytics.

### Repo-local (not shipped in any plugin)
- **Three GitHub issue forms (#34)** under `.github/ISSUE_TEMPLATE/` — `pipeline-aborted`,
  `config-lint-disagreement`, `review-false-positive` — YAML issue forms (so evidence fields are `required`),
  each asking for the `/second-shift:doctor --report` bundle plus its scenario-specific evidence, with a
  `config.yml` chooser (blank issues stay enabled). New dependency-free `tests/issue-forms-selftest.sh`
  structurally validates them (grep + optional `ruby -ryaml`; GitHub's form schema isn't locally validatable).
- **Repo dogfood config declares `tracker.bot` explicitly (#66).** The self-consumption config
  (`.claude/second-shift.config.json`) now declares the bot block (`enabled` / `envVar` / `wrapperPath` / `app`)
  instead of relying on convention discovery — the repo runs its own pipeline under its bot identity.
- **README onboarding-first restructure + `.envrc` gitignore (#63).** The README now leads with onboarding;
  `.gitignore` adds `.envrc` (per-machine direnv OTel telemetry export — local-only, opt-in per engineer).
- **Gitignore `.claude/worktrees/` (#80).** The pipeline creates its own linked worktrees there; an untracked
  entry made `git status --porcelain` non-empty and mis-recorded the Stage-1 pre-flight `workingTreeClean`
  attestation on this repo's own dogfooding runs (surfaced by the #1 retro).

## v2.1.8 — /second-shift:local-dev-refresh (release)

### `second-shift` 1.2.0 → 1.3.0
- **New skill `local-dev-refresh`: the dogfooding ladder, one command.** Machine-level refresh of the local
  dev plugin state: updates EVERY registered marketplace, then EVERY installed plugin across all marketplaces
  (`claude plugin update` — the verb that actually upgrades; `install` no-ops as "already installed"), fixes
  project-scope stragglers in the current repo (scoped uninstall+install — `update` only touches user scope),
  prints one before → after version-delta table, and states the restart verdict. Encodes the sharp edges as
  hard rules: never remove/re-add a marketplace to change a ref (last-scope removal uninstalls everything;
  the sanctioned re-point is `marketplace add owner/repo@ref`, in-place), and warns — never silently fixes —
  when the machine registration's ref differs from the current repo's lockfile pin. Cross-referenced from
  team-rollout's Upgrades section; namespaces rule 1 gains the invocation.

### `dev-pipeline` 2.1.6 → 2.1.8
- **#48 (Phase 1) — be-fe-pair dual-target Stage-7/8 statectl foundation.** Groundwork for looping the
  middle stages per-repo on a dual `[BE]+[FE]` ticket, additive and gated on `targetRepos > 1` (single-target
  pairs and non-pair topologies are byte-for-byte unchanged). New `statectl build-checkpoint-7-perrepo`
  emits a `{perRepo:{<repo>:{…}}}` fragment (merged caller-side into one Stage-7 manifest); `validate_stage7_payload`
  is now **dual-mode** — per-repo schema (a well-formed `perRepo[<id>]` for every `targetRepos` id, fail-closed
  on a missing one) when a `perRepo` object is present, flat schema otherwise; and the **Stage-8 completion gate**
  gains an escape hatch — a non-empty `crossBoundaryReviews[]` or `skippedReviews[]` completes the stage for a
  secondary repo reviewed-via-handoff or explicitly skipped, without a primary-worktree review round. 8 new
  statectl-selftest cases (dt1–dt8); state-schema.md documents the per-repo manifest + the two new arrays. The
  Stage 3/5/7/8 producers that consume this land in follow-on phases.
- **#6 (F26) — claude-design produce dispatch now passes the worktree.** Stage 5's `claude-design`
  produce dispatch omitted `worktree`, so `implement:true` commits landed on the session's default
  checkout (the wrong branch) — the R7 fix that was mirrored to the figma twin but never the
  claude-design one. Stage 5 now passes `worktree: "$WT"`, and `design-sync.mjs` **fails closed** when
  `implement:true` arrives without a worktree (a worktree-less implement is rejected loudly, not silently
  committed to the wrong branch). New selftest cases A8–A10 + a drift-guard token.
- **#7 (F16) — claude-design dispatch prompts de-hardwired.** `design-sync.mjs` baked the original org's
  FE stack (`apps/web`, "acme tokens + shadcn + cn()", "acme FE spec", "apps/web design change") into every
  dispatched prompt, so a consumer with a different FE got prompts grounded in a stack it doesn't have. The
  prompts are now **neutral** and delegate grounding to the `design-faithful` skill, which already reads the
  FE app dir + primitives + token vocabulary from `.claude/second-shift/design-tokens/*.md` (mirroring the
  figma family). No `apps/web`/`acme`/`shadcn`/`cn()` literals remain in dispatched prompts.

### `second-shift` 1.3.0 → 1.3.1 (release-absorbed bump)
- **Onboard no longer emits the removed dead keys.** The #15 dead-key removal (see v2.1.7,
  `dev-pipeline` 2.1.6) also touched the onboard skill — the drafted `commands.<repo>` block no longer
  contains `integrationTest` / `apiTest` and the drafted `gates` block no longer contains `costTracking`,
  so a fresh onboard can't emit a config that config-lint 2.1.6+ rejects. The change shipped in the #15 PR
  without a `second-shift` bump; this release absorbs it (the version string is the update cache key).

## v2.1.7 — canary self-consumption: lockfile "latest"

### `second-shift` 1.1.0 → 1.2.0
- **The canary exception, mechanized.** The marketplace repo consuming itself must track latest, not a pinned
  release (a frozen pin fights the dogfooding loop: fix on N → bump → reinstall → next issue on N+1). The
  lockfile now supports the literal version `"latest"`: `doctor.sh` treats it as presence-only (any installed
  version is correct by definition — new `latest-lock` selftest scenario proves a drifted install stays green),
  and the consumer thin check accepts any cached version dir (`cache/<p>/` instead of `cache/<p>/<v>` — new
  selftest cases). Onboard's Step 2 gains **canary mode**: when the target repo IS the marketplace checkout,
  emit `ref: "main"` + all-"latest" lockfile instead of the release pin, and say so in the consent doc.
  This repo's own onboard artifacts (#51) converted accordingly; docs note the canary form in onboarding.md §1.

### `dev-pipeline` 2.1.4 → 2.1.5
- **#11 (F75) — config-driven label roles via `tracker.labels`.** `stageParams.requiredLabels` was validated
  at pre-flight but every functional site (queue query, claim swap, do-not-pick-up guard, `claim-issue.sh`,
  doctor) hardcoded the six shipped label literals — a consumer with custom labels passed pre-flight, then
  the queue was permanently empty. New named role object (github-only): `tracker.labels =
  { queue, claimed, blockers[] }`, validated by schema + config-lint. Stage 1's queue query, claim swap, and
  blocker guard all resolve from it; `claim-issue.sh` gains `--queue`/`--claimed`; the pre-flight/doctor
  existence-check set is DERIVED from the `tracker.labels` union when set — the validated set can never
  drift from the used set again. Strictly additive: absent `tracker.labels` reproduces the shipped six
  byte-for-byte; JIRA repos untouched.

### `review-toolkit` 2.1.1 → 2.1.2
- **#14 (F17/F57) — commit-gate hooks fail OPEN in a standalone repo.** The two PreToolUse git-commit gates
  claimed to no-op in repos without a `second-shift.config.json` but emitted `permissionDecision:"deny"`
  unconditionally, so a repo adopting review-toolkit ALONE (an advertised path) had every Claude-driven
  commit denied — `check-reviewer-references.sh` scanned `.claude/agents` regardless of config, and
  `check-model-tiers.sh` denied everything when the sibling dev-pipeline plugin was absent. Both hooks now
  fail open (allow) in hook mode when the lockstep contract isn't in force: no config (reviewer-references)
  or no sibling dev-pipeline (model-tiers). The standalone CLI path still checks (advisory exit 1);
  onboarded repos keep the deny gates.

### Repo-local (not shipped in any plugin)
- **`/release` skill (#50):** the release-cut runbook operationalizing `docs/releasing.md` — completeness
  audit, green gate, publish, post-release verification, maintainer-machine refresh. Deliberately
  repo-local: consumers can't cut releases.
- **Dogfood onboard (#51):** this repo onboarded as its own consumer via the shipped `/second-shift:onboard`
  at v2.1.6 — the five artifacts (config, settings pin, lockfile, SessionStart thin check, consent doc),
  labels + bot wrapper provisioned; converted to canary form by #54 above.
- **Chore (#53):** untracked two machine-local `.claude/audit/*.jsonl` session-telemetry logs committed by
  an earlier `git add -A`; the `.gitignore` entry now takes effect for fresh clones.

### `dev-pipeline` 2.1.5 → 2.1.6
- **#15 — validator/schema integrity (F83/F81).** Four fixes closing the gap between what the schema
  publishes and what the pipeline enforces:
  - **`check-extensions.sh` now runs at pre-flight** (SKILL.md step 0b), fail closed — restoring the EP-3
    guarantee that a typo'd `.claude/second-shift/` extension file (e.g. `blocker-mutants.md.md`) is LOUD,
    not silently degraded, and that every `stageWorkflows[].workflow` / `implementDelegates[].agent`
    reference resolves. Previously it was shipped but invoked by nothing.
  - **12 config-lint type-check gaps closed** (`stageWorkflows[].stage` integer; `smokeRoutes` /
    `reviewers.remove` / `extraLanes[].when` / lane `commands` array-ness; `paths.*` /
    `implementDelegates[].surface` / `planGates[].surface` / `visualCapture.baseUrl` / lane `cwd`
    string-ness; `bot.enabled` boolean; lane `commands` min-1; `requiredLabels` item strings) — the
    no-node config-lint now matches the schema's stricter contract (packed mutant fixture kills all 12).
    Schema gains `minLength: 1` on `topology.repos.<id>.{path,baseBranch}` to match.
  - **Removed 3 dead keys** (**BREAKING**, config-lint rejects with a migration pointer):
    `commands.<repo>.integrationTest` / `apiTest` (no verify lane ever ran them — use `extraLanes` /
    EP-6/EP-7) and `gates.costTracking` (toggled nothing; cost attribution is unconditional/passive).
    `check-config-shadowing.sh` extended beyond `stageParams` (now also asserts readers for
    `commands.<host>.format`, `ticketTag`, `gates.mutation`) so the dead-key class can't ship again.
  - **`gates.mutation` wired as a real off-switch** — `false` now disables the Stage-5 unit-test mutation
    gate even when `unitTestScope` is set (previously ignored in both directions).
  - **F81 — `commands.<repo>.lanes` documented as SETUP-only** (INFRA-classed on failure) in the schema;
    a verify/test command belongs in `extraLanes` (real `failureClass`, correct fix budget), not `lanes`.

## v2.1.6 — be-fe-pair: pair runs end-to-end (release)

The be-fe-pair series (#4/#5, PRs 3–5 + flat-mirror) shipped as logic-only PRs with the version bump deferred
to release, per the series convention. This section is that bump plus the deferred coverage.

### `dev-pipeline` 2.1.3 → 2.1.4
- **#4 PR 3 — Stage 2 per-repo worktree creation.** A pair ticket creates one worktree per target repo, each
  cut from that repo's OWN `baseBranch` (BE `alpha` / FE `main` may differ) or the prior slice branch when
  stacked, persisted via `worktree-set --repo`; new `statectl target-repos-set` persists Stage-1 routing as
  `.targetRepos` (`(trs1)` selftest). Single-repo creation blocks are guarded to a no-op for pairs.
- **#5 (PR 4) — per-repo verify, never a silent green.** `verifyctl run <issue> --repo <id>` keys the command
  table, worktree, base ref, sidecar, and retry budget on `<id>`; `verify-summary-set --repo` writes
  `worktrees.<id>.verifySummary`; the Stage-6 completion precondition requires a per-repo summary for EVERY
  target — a repo whose verify never ran cannot complete the stage. `--repo` omitted = byte-for-byte the prior
  single-repo path.
- **#4 PR 5 — Stage 9/10 pair-aware.** `statectl pr-add --repo` keys `.prs` by repo id (pair PRs share a
  branch); Stage 9 pushes each target to ITS origin and opens the PR against ITS base with a per-repo freshness
  gate; Stage 10 cleans up over the `worktrees` map.
- **#4 — flat-mirror the primary target.** Stage 2 mirrors the primary target (host repo when it's a target,
  else the first target) into the flat `worktreePath`/`worktreeBase` fields, so the middle stages (3/4/5/7/8)
  run unchanged on it — the piece that makes a single-target pair run flow end-to-end.

### `review-toolkit` 2.1.0 → 2.1.1
- Selftest fixture in `check-review-context-selftest.sh` renamed to the generic `orders-reviewer` (canonical
  example from review-lead's SKILL) — removes an org-traceable fixture name; test semantics unchanged.

## v2.1.5 — review-context per-reviewer split

### `review-toolkit` 2.0.2 → 2.1.0
- **Per-reviewer review-context files.** New extension surface `.claude/second-shift/review-context/<reviewer-name>.md`: each panel reviewer self-loads its own file after the shared `review-context.md` (additive, never protocol-weakening). All ten panel reviewer prompts carry the self-load line; review-lead no longer instructs handing the shared file to every reviewer (agents self-load; review-lead honors context in triage only). Placement rule documented in `docs/extension-points.md`: single-consumer prose → per-reviewer file; multi-consumer contracts (`security-rules.md`, `blocker-mutants.md`) stay standalone; cross-cutting calibration stays in the shared core.
- **New lint `scripts/check-review-context.sh` (+ selftest).** Fails closed when a file under `review-context/` has a basename that is not a reviewer in the effective registry (panel − `reviewers.remove` + `reviewers.add`) or is not markdown — a typo'd filename is loud instead of silently read by nobody. Wired into review-lead pre-flight so interactive sessions lint too; registry extraction mirrors `check-reviewer-references.sh`.

### `dev-pipeline` 2.1.2 → 2.1.3
- **Extension manifest: `review-context/*.md` glob** added to `extension-manifest.txt` (+ selftest scenario) so the per-reviewer files pass config-lint. Consumers on cached manifests older than 2.1.3 can bridge with a `.known-extensions` line until they update.

## v2.1.4 — consumer docs, July-2026 grade

Docs-only (no plugin content changed): the #18 docs pass merged with the onboarding program's Phase E — one
rewrite, closing the last confirmed doc gaps.

- **`docs/team-rollout.md` (new):** Day-0 champion flow, every-engineer first contact (trust dialog →
  enabled-but-not-installed → the nudge), personal opt-out (settings.local.json; why user-scope false can't
  override), upgrades (atomic ref+lockfile PR; laggards converge via doctor; the marketplace-removal sharp
  edge), rollback (version-AHEAD symmetry — read before the incident), the managed-settings regulated variant,
  and what-is-a-gate (client plugins = fast local feedback; the gate of record is server-side).
- **`docs/onboarding.md`:** new §2b — the GitHub-tracker prerequisites the first run enforces (six queue labels
  with the copy-paste loop, until #11 makes `stageParams.requiredLabels` authoritative; GitHub-App bot identity
  + `install-gh-bot.sh` bootstrap + the no-bot outcome; node/gh scoping), a **non-JS persona example**
  (poetry/pytest on JIRA with `format: null`) beside the yarn one — both examples verified lint-green verbatim —
  §4 restructured as the three verification layers (config-lint / `/second-shift:doctor` / `pipeline-doctor.sh`
  + `check-extensions.sh`), and the team-rollout cross-link.
- **`docs/extension-points.md`:** an "Authoring `review-context.md`" template documenting the ~8 named sections
  the shipped reviewers actually read (stack, DB stack, maturity stage, invariants, intentional complexity,
  convention-required structure, UI stack/design system, naming, perf budgets); **EP-4 documented** —
  `reviewers.modelOverrides` accepts named workflow agents like `mutation-executor`, not only panel reviewers
  (schema description corrected to match).
- **`docs/namespaces.md`:** rule 1 gains `/second-shift:onboard` + `/second-shift:doctor`; rule 3 documents the
  sanctioned second arrow (second-shift → dev-pipeline via installPath / pinned-ref contents API) and why
  `second-shift` is deliberately NOT in the CI grep's TOOLKITS list.

## v2.1.3 — release contract: configVersion migrations + release discipline

### `dev-pipeline` 2.1.1 → 2.1.2
- **config-lint learns the migration contract (issue #32).** `configVersion` errors now carry pointers instead
  of the bare "must be 1": a number > 1 → "newer than this plugin understands — upgrade the marketplace pin
  (docs/releasing.md)"; < 1 → "predates this plugin — see docs/migrations/"; non-number → "required number
  (current: 1)". The two v1 keys removed in v2.0.0 are special-cased with their exact migration pointers
  (`gates.figma` → `design: {"provider": ...}`; `gates.apiTests` → EP-6/EP-7 companion pack — both →
  docs/migrations/v1-to-v2.md), and the generic gates unknown-keys message now names the offending keys.
  Three new invalid fixtures. Docs: `docs/releasing.md` (maintainer checklist: version-bump discipline,
  CHANGELOG step, metadata lockstep, mandatory "What breaks / what to do" Release body, official `renames`
  map (≥ v2.1.193, append-only), doc-pin-example refresh — the v1.1.0 lesson), `docs/migrations/README.md`
  (the contract + the honest v2.0.0 history line), and the retroactive `docs/migrations/v1-to-v2.md`.

## v2.1.2 — one blessed bundle + the consent doc

### `second-shift` 1.0.0 → 1.1.0
- **One blessed bundle + the consent doc (issue #31).** Onboard now also emits `.claude/SECOND-SHIFT.md`
  (from `templates/consumer/SECOND-SHIFT.md`): per-plugin component inventory — what installs, which hooks
  fire on which events, when code actually runs — plus the sanctioned personal opt-out recipe
  (`settings.local.json`) and the support boundary, so the trust-dialog decision is made BEFORE the scary
  prompt. Docs now bless exactly one artifact (full suite at a pinned tag, design-toolkit sole conditional)
  with review-only as the single documented community-supported downgrade.

## v2.1.1 — be-fe-pair: target routing (#4, PR 2)

### `dev-pipeline` 2.1.0 → 2.1.1
- **#4 — Stage 1 `targetRepos` routing + the multi-repo failure reasons.** Added `targetRepos-ambiguous` + `fe-repo-unreachable` to the `valid_failure_reason` closed enum (state-schema.md table → regenerated `statectl.sh` via `gen-statectl-validators.sh`; drift-check byte-match verified). New topology-gated Stage-1 **Step 1.T** (runs only for `topology.type: be-fe-pair`) resolves `TARGET_REPOS` from the fetched ticket **title** matched against each repo's `topology.repos.<id>.ticketTag` — a single tag → that repo, both tags → cross-repo (`"be fe"`), no recognizable tag → fail closed `targetRepos-ambiguous` (never guess); each target repo's `path` must be reachable in the session (`claude --add-dir`), else `fe-repo-unreachable`. `ticketTag` finally has readers (was dead config). Strictly additive — a `standalone`/`monorepo` consumer skips Step 1.T entirely. Per-repo worktree creation (Stage 2) lands in the next PR.
## v2.1.0 — onboarding release: the marketplace writes its own consumer config

### `second-shift` (new) 1.0.0
- **New sixth plugin: the user-scope onboarding micro-plugin (issue #28).** `/second-shift:onboard` runs in the
  target consumer repo: provenance-first detection (`detect.sh` — tracker from origin host + MCP evidence, topology
  from workspaces/siblings, baseBranch from origin/HEAD only — an undetectable base branch is a written abort,
  never a guess), release-pin resolution (`pin-resolve.sh` — latest GitHub Release, highest-semver-tag fallback,
  per-plugin versions read AT the pinned ref via the contents API), ONE accept-or-edit elicitation batch
  (branchPrefix, mutation/costTracking gates, design provider, reviewer deltas, and — github tracker — the
  bot-identity decision plus optional creation of the six queue labels, absorbing the previously undocumented
  first-run wall), then emits `.claude/second-shift.config.json` (with a `$schema` first key at the pinned ref),
  a merged `.claude/settings.json` pin block (`.second-shift-proposed` fallback when blocked), and
  `.claude/second-shift.lock.json` (lockfileVersion 1) — lint-looped green with the plugin-shipped config-lint
  before anything lands. Zero agents, zero hooks. Both shell tools ship hermetic bash-3.2-safe selftests.
- **`/second-shift:doctor` + the consumer lockfile contract (issue #29).** `doctor.sh` verifies install state
  against the committed lockfile — never-installed, enabled-but-not-installed (the v2.1.195 fresh-clone default,
  the most common finding), version-behind, version-AHEAD (rollback), settings-ref↔lockfile-ref drift — plus
  ref-less marketplace shadowing (via `claude plugin marketplace list --json`, text-parse fallback), repo-local
  skill/agent shadow collisions, opt-out scan, and config-lint. Every FAIL prints its exact remediation; exit
  code = FAIL count. Hermetic 8-scenario selftest with env-injected data sources. Onboard now also emits the
  repo-committed thin check (`.claude/tools/second-shift-doctor.sh` + SessionStart nudge — presence check only,
  always exits 0, <50ms) — with the lockfile, the sanctioned exception to no-vendoring.

### `dev-pipeline` 2.0.10 → 2.1.0
- **config-lint + schema accept a top-level `$schema` key.** `/second-shift:onboard` emits it for live editor
  validation at the pinned ref; both the lint's unknown-top-level-keys check and the JSON schema
  (`additionalProperties: false`) rejected it before. New `valid-schema-key-standalone.json` fixture.

## v2.0.10 — be-fe-pair foundation: additive per-repo state (#4/#5, PR 1 of 4)

First of a 4-PR series restoring full multi-repo (be-fe-pair) support to the generic core (the de-orging had collapsed it to single-repo). **Strictly additive and topology-gated** — no stage touched yet, so single-repo behavior is byte-for-byte unchanged.

### `dev-pipeline` 2.0.9 → 2.0.10
- **statectl `worktree-set --repo <id>` / `verify-attempts --repo <id>`** — a `be-fe-pair` run persists boundary fields and the per-class retry budget **per repo** at `worktrees.<repoId>.{worktreePath, branch, base, verifyAttempts}`, rather than the flat top-level `worktreePath`/`branch`/`verifyAttempts`. With `--repo` omitted (every standalone/monorepo consumer) the flat fields are written exactly as before — the `worktrees` map is absent. New `(va5)`/`(ws-repo)` selftests assert per-repo independence and that the flat path is untouched; the generated-validator drift-check is unaffected (no new enums). Documented in state-schema.md ("be-fe-pair note"). Stages 1/2/6/7/9/10 that consume the map land in PRs 2–4.

## v2.0.9 — docs hotfixes: onboarding path rot

### `dev-pipeline` 2.0.8 → 2.0.9
- **Docs/comment-only: stale pre-v2 paths purged from tool headers and executed docs.** The README quick-start's
  config-lint step was unrunnable (`<dev-pipeline plugin root>/tools/` — the tool lives under `skills/run/tools/`;
  the command now resolves the install path via `claude plugin list --json`), and the settings-pin example in
  `docs/onboarding.md` pointed at the dead pre-recreation tag `v1.1.0` (→ `v2.0.0`). Inside the plugin, usage
  headers and generated banners still claimed the vendored `.claude/skills/run/` layout: `pipeline-doctor.sh`,
  `stage-times.sh`, `gen-statectl-validators.sh` (+ the three banners it prints into `statectl.sh`, kept in
  byte-lockstep for the regeneration selftest), `statectl-selftest.sh`, the cost-tracking fixtures README,
  `otel-collector-config.yaml`, and a `check-config-shadowing.sh` comment. `SKILL.md`'s model-tier section now
  names the real `check-model-tiers.sh` home (review-toolkit `scripts/`). Root docs: README no longer promises
  JIRA content in `docs/onboarding.md` (links the JIRA tracker README instead), `docs/extending.md` drops the
  phantom `second-shift sync` command (phase-1 vendoring is a manual copy), and the changelog's pre-2.0 pointer
  states the history was not carried over. The stale `.claude/scripts/` hook paths in `hooks.md` are left for
  #14 (review-toolkit commit-gate rework) to avoid a collision.

## v2.0.8 — generalization-audit fixes: JIRA scope-gate parity

Restores the JIRA-aware ticket fetch the vendored (pre-second-shift) skills carried — the generic reviewer had regressed to GitHub-only.

### `dev-pipeline` 2.0.7 → 2.0.8
- **#16 (F13/F78) — the Stage-8 scope-completeness gate could only `gh issue view`, so every JIRA run returned BLOCKED→FAIL.** `code-review.mjs` now tracker-branches the scope-reviewer dispatch prompt on `config.tracker.type`: GitHub → `gh issue view #N`; JIRA → fetch via `mcp__atlassian__getJiraIssue` (key from `$ISSUE_NUMBER`, `cloudId` via `getAccessibleAtlassianResources`). Stage 8's reviewer-selection note generalized to spawn the gate on JIRA runs (always ticket-driven). README requirements corrected: `gh` is needed on **every** tracker (Stage 9 `gh pr create`), and `node` (the Workflow gates) is now listed.

### `review-toolkit` 2.0.1 → 2.0.2
- **#16 — `agents/scope-completeness-reviewer.md`** Step 1 now tracker-branches the fetch (github `gh issue view` / jira Atlassian MCP `getJiraIssue` + `getJiraIssueRemoteIssueLinks`, `cloudId` via `getAccessibleAtlassianResources`), with the MCP tools added to the agent frontmatter and the BLOCKED verdict + description generalized from "GitHub issue" to "issue/ticket". Mirrors the vendored JIRA reviewer (capability parity).

## v2.0.7 — generalization-audit fixes: config-aware doctor

### `dev-pipeline` 2.0.6 → 2.0.7
- **#17 (F05 + tracker-blindness + wrapperPath drift) — `pipeline-doctor.sh` read no config and was permanently red for every non-yarn / non-GitHub consumer.** node + yarn were unconditional hard FAILs (a JIRA/pnpm/poetry consumer failed prerequisites it never uses, masking real FAILs by inflating the count); the gh/bot/label sections ran regardless of tracker; the label set was hardcoded; and the bot-wrapper path ignored `tracker.bot.wrapperPath` (reader/prober drift vs claim-issue.sh). Doctor now loads the consumer config first: **node** stays a real probe (the Workflow gates `code-review.mjs`/`mutation-gate.mjs` need it), but **package managers are probed from the configured command table** (first word of each `commands.<host>.*` entry — a pnpm repo probes pnpm, a poetry repo probes poetry) instead of a hardcoded yarn; the **gh auth / feature-probe / bot-wrapper / required-label** sections gate on `tracker.type == github`; **required labels** read from `stageParams.requiredLabels`; and the bot wrapper honors `tracker.bot.wrapperPath`. Green on a pnpm-GitHub repo and a poetry-JIRA repo; red only for genuinely missing prerequisites.

## v2.0.6 — generalization-audit fixes: config-driven format lane

### `dev-pipeline` 2.0.5 → 2.0.6
- **#12 (F06/F20 + dead `commands.format`) — the format lane was hardwired to prettier and imposed node/npx on every consumer, on every run.** `resolve_prettier` was the only formatter path (with a `npx --yes prettier@x` fallback), so a Python consumer got `npx prettier --write src/app.py` (FORMAT fail, budget-charged) and a no-node machine got rc-127 → INFRA → run kill even on a docs-only diff (the plan `.md` Stage 3 always commits reached npx prettier). Meanwhile `commands.<host>.format` was published, fixture-set, config-lint-validated — and read by nothing. Now `verifyctl` resolves `FORMAT_MODE` from `commands.<host>.format`: **string** → run it verbatim as the repo's own formatter (`black .`, `yarn format`; no node assumption; the command owns its scope); **null** → skip the format lane entirely (prettier + npx never run); **absent** → the documented scoped-prettier default (byte-for-byte prior behavior — the ONLY path needing node/npx). The INERT-lane prettier check now runs only in prettier mode, so a config/`null` consumer's inert docs run never reaches npx. New `(v12)`/`(v13)` selftests assert the config command runs verbatim (not prettier) and that `null` skips with `verifySummary.format: "skipped"`.

## v2.0.5 — generalization-audit fixes: mutation-gate null-off semantics

### `dev-pipeline` 2.0.4 → 2.0.5
- **#9 (F03) — null/absent `commands.<host>.testFile` / `unitTestScope` fell back to the acme yarn/`apps/api/src/**` literals, violating the schema's null=off contract.** The `//` operator mapped explicit-null AND absent to the acme literal, so a pytest consumer that left `testFile: null` per the schema got `yarn --cwd apps/api test tests/test_x.py` (rc 127 → every mutant INFRA → run halts), and a null `unitTestScope` scoped the diff to a nonexistent path (gate self-waives). Stage 5 now resolves both with `// empty`: null/absent `unitTestScope` ⇒ gate **OFF** (recorded, skipped); `unitTestScope` set but `testFile` null ⇒ **fail closed** (explicit config error, never a silent green or a hardcoded yarn). `mutation-gate.mjs` throws if executable mutants exist without a `testFileCommand` (defense-in-depth; dropped the `|| 'yarn …'` default). Genericized the Stage-3/4 prose gate rules to "the configured `unitTestScope` surface" (acme `apps/api/src/**` kept as illustration).

## v2.0.4 — generalization-audit fixes: Stage-3/4 state-path resolution

### `dev-pipeline` 2.0.3 → 2.0.4
- **#10 (F24) — Stage-4 plan gate ignored `paths.pipelineStateDir` + used the raw uppercase ticket key.** Stages 3 and 4 handed plan-lint the reconstructed literal `$MAIN_ROOT/.claude/pipeline-state/${ISSUE_NUMBER}.json`, but statectl honors `paths.pipelineStateDir` and lowercases the key — so for a Jira-keyed ticket (`AB-123`) or a custom state dir the real file is elsewhere, plan-lint exits "state file not found", and the run aborts spuriously with `plan-structure-invalid`. Added a read-only `statectl state-path <ticket>` subcommand (prints the resolved absolute path via the existing `state_path()`/`state_dir()` logic) and switched both plan-lint call sites to it. New `(sp1)` selftest asserts default dir, custom `pipelineStateDir`, Jira-key lowercasing, and the no-arg usage error. Outside statectl's generated validator region — drift-check unaffected.

## v2.0.3 — generalization-audit fixes: residual base-branch literals

Residual `main` base-branch literals off the C1 critical path — silent no-ops and rubric noise on non-`main`-based consumers.

### `dev-pipeline` 2.0.2 → 2.0.3
- **#13 (F31/F77) — `doc-update.md`** Steps 7.A/7.C diffed `git diff main...HEAD`, so a develop/alpha-based repo produced an empty changed-file set and the doc-staleness sweep silently reported "0 candidates" every run. Now resolves `$BASE_REF` from the host repo's configured `baseBranch` (default `main`).
- **#13 (F80) — `eval-criteria.md`** Autonomous-Pre-flight rubric required "a clean **`main`** base", so every legitimately non-`main` run scored a spurious FAIL into the pipeline-retro keep-or-revert loop. Reworded to "the configured base branch".

### `review-toolkit` 2.0.0 → 2.0.1
- **#13 — `review-lead/SKILL.md`** (base default) + **`agents/doc-updater.md`** (`git diff main...HEAD`) now resolve the base from the repo-local `.claude/second-shift.config.json` host `baseBranch` (default `main`), self-contained (no dev-pipeline path — honors the namespace-direction rule).

### `design-toolkit` 2.0.0 → 2.0.1
- **#13 — `agents/figma-faithful-reviewer.md`** `git diff main..HEAD` now resolves the configured base branch from repo-local config (default `main`).

## v2.0.2 — generalization-audit fixes: base/prefix generalization (Wave 1)

### `dev-pipeline` 2.0.1 → 2.0.2

- **#8 — executed stage bash hardcoded `main` + `claude/acme-` despite config `baseBranch`/`branchPrefix`.** Branch creation and verification disagreed about the base on the same run for any consumer whose mainline ≠ `main` or branch prefix ≠ `claude/acme-` (e.g. a `develop`-based, `team/`-prefixed repo). Threaded one shared resolution idiom — `PREFIX = tracker.branchPrefix // "claude/acme-"`, `BASE = state field // host(path==".").baseBranch // "main"` (the model verifyctl already uses) — through the executed blocks of **Stage 1** (outer-loop slice branch/base), **Stage 2** (single-PR fallback, resume-guard glob + `$BRANCH_PREFIX`, mainline cut-from-`origin/<base>` discriminator, worktree dir name now the branch basename `${BRANCH##*/}` instead of an `acme-` literal; **Stage 10** cleanup removes the worktree at the persisted `worktreePath` rather than reconstructing the `acme-` literal, which would orphan a non-default consumer's worktree), **Stage 5** (mutation-gate range base — a wrong base silently emptied the changed-file set and waived the blocking gate), and **Stage 9** (stale-branch freshness gate + `--base` PR target). Extended `check-config-shadowing.sh` to assert `tracker.branchPrefix` + `baseBranch` are read per owning stage, with a new selftest strip-case, so the class can't regress. Defaults reproduce prior behavior byte-for-byte (verified against empty and `main`-based configs).

## v2.0.1 — generalization-audit fixes

Consumer-generalization fixes from the v2.0.0 audit. Patch-level: no schema change, `configVersion` stays `const 1`, all defaults reproduce prior behavior.

### `dev-pipeline` 2.0.0 → 2.0.1

- **#3 — Stage-6 verifyctl path rot (breaks every de-vendored consumer + blocked dogfooding).** Stage 6 resolved `verifyctl.sh` via the git-common-dir idiom, which points at the **consumer repo root** — but `verifyctl.sh` ships in the plugin checkout, so the path was nonexistent for every de-vendored consumer. Now anchored to `${CLAUDE_PLUGIN_ROOT}/skills/run/verifyctl.sh` (the resolution SKILL.md pre-flight already uses for `config-lint.sh`), with a `statectl.sh`-sibling fallback. Swept the same class across the executed stage blocks: `claim-issue.sh` (Stage 1), `max-pushed-slice.sh` (Stages 1/2), `plan-lint.sh` (Stages 3/4), `bot-commit.sh` (Stages 3/6), and the SKILL.md pre-flight onboarding hints — all now `${CLAUDE_PLUGIN_ROOT}`-anchored instead of CWD-relative.

## v2.0.0 — "the extensible core"

The de-orged, extensible core: a genuinely generic marketplace + the Extension Contract v1. Semver-major.

**Run the pipeline with `/dev-pipeline:run <issue>`** — the `dev-pipeline` plugin's flagship `run` skill (plugin = namespace, skill = action; consistent with the other toolkits).

### Extension Contract v1 (all optional; defaults reproduce v1 behavior byte-for-byte)
- **EP-1 `stageParams`** — stage-prose constants promoted to config (`planFilePattern`, `requiredLabels`,
  `visualCapture{baseUrl,devServerCommand,smokeRoutes,viewports,triggerGlobs}`, `formatGlob`). New lockstep
  validator `check-config-shadowing.sh` guards against a published-but-unread key.
- **EP-2 `commands.<repo>.extraLanes`** — additive, blocking verify lanes; run after the SUITE trio, `when`-glob
  gated, results under namespaced `ext:<name>` keys, `failureClass` from the existing closed taxonomy. No advisory mode.
- **EP-3 extension-file manifest + `check-extensions.sh`** — fail-closed lint of `.claude/second-shift/` against a
  shipped manifest (a typo'd `blocker-mutants.md.md` is loud). Companion/repo-local extensions declared in a
  `.known-extensions` allowlist.
- **EP-4 named-agent `modelOverrides`** — the mutation executor is now the logical agent `mutation-executor`,
  its tier overridable via `reviewers.modelOverrides`. `check-model-tiers.sh` asserts the lookup.
- **EP-5 companion packs** — the org-overlay distribution contract (two-pin model, namespaced agents/workflows,
  `.known-extensions` vendoring). See `docs/extending.md`.
- **EP-6 `stageWorkflows`** — register a blocking Workflow as a gate-owned stage sub-step; new closed reason
  `ext-workflow-failed`; `ext:`-namespaced state only. **EP-7 `implementDelegates`** — route Stage-5 work items to
  a delegate agent; output flows through the unchanged scope + downstream gates.
- **EP-8 `planGates`** — additive Stage-4 plan-review gates: register a plan-reviewer agent that runs after the
  built-in plan gates; additive-only (a `block` maps to `plan-reviewer-block`, never waives a gate). Completes the
  additive-gate symmetry: `planGates` (Stage 4) · `extraLanes` (Stage 6) · `reviewers.add` (Stage 8).
- New consumer guide **`docs/extending.md`**; `extension-points.md` is its field reference; the disposition test
  is codified in `context-model.md`.

### Design-provider axis (breaking)
- **`gates.figma` → top-level `design: { provider: "figma" | "claude-design" }`** (key absent = design fidelity off).
  The **figma** adapter is now internalized as a first-class provider (Stage 1/3/4/5/8), no longer consumer glue.

### De-org: removals (capabilities move, they don't disappear)
- **`skills/playwright-cli` removed** from design-toolkit → restore repo-local under `.claude/skills/playwright-cli/`.
- **api-test tier removed** (`api-test-{coder,reviewer,plan-reviewer}` + `api-testing` skill + `api-tests.mjs` +
  `gates.apiTests`) → re-attach as a companion pack via EP-6/EP-7 + `.known-extensions`.

### Genericization (stack specifics move to `review-context.md`)
- **db-reviewer** engine-agnostic (relational + document stores); **pipeline-reviewer** queue-agnostic;
  **performance / complexity / maintainability / test-coverage** reviewers stack-neutral; **design-faithful**
  reads its stack from `design-tokens`; **intake-toolkit** honors `tracker.type` (github default + jira deltas).
- `plugin.json` corrected: design-faithful / figma-faithful are the **claude-design / figma provider adapters**
  (dropped the false "(generic)" label on design-faithful).

### Fixes
- **`paths.plansDir` is now honored** by Stage 3 (was published but ignored — the config-drift defect).
- Base-branch, format-glob, viewport, and label constants routed through config (EP-1) instead of hardcoded.
- De-anonymization: removed a shipped private-repo inventory, real GitHub App identifiers, and domain-fingerprint
  substance from the stock and its examples.
- `pipeline-doctor.sh` locates sibling-plugin selftests in both the monorepo and the version-keyed install-cache
  layout (previously reported spurious FAILs from the cache; the checks always passed).

### v1 → v2 migration (consumers)
1. Bump the marketplace `ref` and each `plugin.json` version pin to `v2.0.0`.
2. **`gates.figma: true` → `design: { provider: "figma" }`** — **except** a Claude-Design (DesignSync) shop, which
   is **`design: { provider: "claude-design" }`** (the old `gates.figma` flag did not imply figma).
3. **`gates.apiTests`**: remove; carry the api-test tier as a companion pack / repo-local agents+workflow and wire
   it via `implementDelegates` + `stageWorkflows`, declaring `api-testing/*.md` in `.claude/second-shift/.known-extensions`.
4. If you relied on `design-toolkit:playwright-cli`, restore it repo-local under `.claude/skills/playwright-cli/`.
5. Declare your stack in `.claude/second-shift/review-context.md` (database engine/ORM, queue broker, FE stack,
   toolchain) so the now-generic reviewers keep their prior review depth.
6. If you set `paths.plansDir`, note it is now honored — plans move to that directory.

## v1.1.1 and earlier
Pre-extensible-core history (per-plugin evolution) was not carried over in the 2026-07 tree recreation — v2.0.0 is the earliest commit in this repository's history.
