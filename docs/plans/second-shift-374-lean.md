# lean spec — issue #374

Three reporting/ordering fixes to the lean lane's gates. No logic defect: the verdicts these
gates reach are correct today, they just arrive late (`all` pays the ~15-minute green gate
before a cheap, already-knowable milestone-4 refusal) or loud (one committed fact printed as
three merge-boundary violations), and a `pause-and-ask` Open Region can be closed by the build
session itself when nothing stops it before code is written.

## What changes

1. **`lean-gate.sh cmd_all`** grows a cheap, read-only pre-pass: before the real 1→5
   progression, it evaluates milestone 1's and milestone 4's assertions in a `PRECHECK=1` mode
   that reports but never writes to the progress file (no fix-budget attempt, no `satisfied`
   record — recording stays the real loop's job). If either is already unsatisfiable, `all`
   reports every such finding and returns without running milestones 2 or 3. If both are clean,
   `all` proceeds through the real 1→5 progression unchanged.
2. **`check-lean-chain.sh` evidence 5** (the freshness check) becomes vacuity-aware: when the
   committed verdict record's value is not `approve`, it prints exactly one refusal naming the
   value and does not evaluate or print the inferred/declared freshness arms — a `needs-work`
   record is undefined territory for "is it fresh", not a place for two more independent
   findings that restate the same fact.
3. **`lean-gate.sh cmd_1`** grows a new assertion, live (not part of the pre-pass — it reads
   the tracker, so it stays outside the pre-pass's no-network bound): the issue must not
   declare an `## Open Regions` (interviewing-baseline's Decision Ledger contract) row
   dispositioned `pause-and-ask` with no resolution artifact. A resolution is either a non-bot
   issue comment naming the region's ID, or a committed intent-gap record (pinned as
   `$PLANS_DIR/$REPO_SLUG-<issue>-lean-intent-gap.md`, the same suffix
   `check-lean-chain.sh` already recognizes) whose `region:` key names that ID and whose
   `ratified:` key reads `yes`.

## Acceptance criteria

- **AC-1** (oracle — `lean-gate-selftest.sh`): `bash G all <issue>` on a tree whose committed
  verdict record reads `verdict=needs-work` reports the milestone-4 refusal without having run
  milestone 3's body. Proven via a seam the fixture can observe (the config's `test` command
  writes a marker file; the marker's absence after the sweep is the assertion), not by timing.
- **AC-2** (oracle): `all` on a tree where milestone 1's and milestone 4's assertions both
  pass still runs milestone 3 for real and reports its actual verdict — the pre-pass must not
  become a way to skip the green gate.
- **AC-3** (oracle): the pre-pass reports every already-unsatisfiable cheap assertion in one
  pass (both milestone 1's and milestone 4's, when both are broken), not just the first, so
  fixing one does not require a second run to discover the other.
- **AC-4** (oracle — `check-lean-chain-selftest.sh`): a `needs-work` verdict record at a stale
  head (a commit landed after it) produces exactly one evidence-5 refusal, naming the verdict
  value; the changed-files (inferred) and patch-id/reviewed-head (declared) arms neither
  evaluate nor print.
- **AC-5** (oracle): an `approve` record at a stale head still produces the freshness refusal
  it does today (both arms independently evaluated as before) — collapsing the non-approve case
  must not weaken the case the arms exist for.
- **AC-6** (oracle): the evidence count in the merge-boundary summary line
  (`N evidence artifact(s) missing`) matches the number of `✗`-prefixed violation lines printed,
  so the collapse in AC-4 does not leave a stale count over fewer printed lines.
- **AC-7** (critic): the pre-pass added in AC-1 performs **no network call**, and no subprocess
  beyond local text utilities over committed files — milestone 1's new pause-and-ask check
  (AC-8) is explicitly NOT part of the pre-pass for this reason, and runs only in milestone 1's
  real, non-`PRECHECK` body. The network clause is the binding one; the utility set is
  `git`/`grep`/`jq` plus the `sed`/`head`/`wc`/`tr`/`cat` that `cmd_4` already spawns, since
  "What changes" mandates reusing that body verbatim under `PRECHECK=1` — the earlier three-name
  enumeration was narrower than any implementation this spec permits.
- **AC-8** (oracle): `bash G 1 <issue>` refuses when the issue's `## Open Regions` table
  declares a region dispositioned `pause-and-ask` for which neither a non-bot issue comment
  naming the region's ID nor a ratified intent-gap record naming it exists; the refusal names
  the region ID. It passes once either resolution artifact exists.
- **AC-9** (oracle): a region dispositioned `reversible-default-and-flag` does not refuse —
  only `pause-and-ask` does.
- **AC-10** (oracle): an issue with no `## Open Regions` section at all passes milestone 1
  unchanged (additive to the existing spec/AC-n check).
- **AC-11** (critic): `SKILL.md`'s "two tracker writes per clean run" rule is amended in place
  to name the third write a `pause-and-ask` region's resolution costs, without growing the
  file past its 60-line cap (`wc -l`).
- **AC-12** (oracle — CI): the generic mutation survivor ordinals of every guard this diff
  edits (`lean-gate.sh`, `check-lean-chain.sh`) are checked against `tools/mutation-baseline.tsv`
  and re-baselined if they moved, with the site-level evidence recorded in the PR body either
  way. Adding a selftest case can also kill a previously-baselined mutant and shrink the
  survivor set — checked after adding coverage, not only after editing a guard.
- **AC-13** (critic): the PR carries a `Changelog:` trailer.

### Amended at round 2

Round 1 returned `needs-work` on a lane rule no `AC-n` named, plus two coverage gaps and two
notes. Scope changed, so the `AC-n` set is amended here before the re-handoff, per the lane's
"amend the `AC-n` set before milestone 5".

- **AC-14** (doc — the round-1 blocker): `SKILL.md`'s Resume section describes what `all`
  actually reports while the verdict is outstanding — that the pre-pass names milestone 4 and
  stops without evaluating 2 or 3, and that those are run directly until an `approve` record is
  committed. Still within the 60-line cap (`wc -l`). The old text ("continue at the first
  unsatisfied milestone") was made untrue by AC-1's pre-pass and shipped uncovered.
- **AC-15** (oracle — `lean-gate-selftest.sh`): a `pause-and-ask` row in an `## Open Regions`
  table written **without** a trailing pipe still refuses milestone 1. The disposition is the
  last non-empty cell, not `$(NF-1)`; GFM does not require the trailing pipe, and the `$(NF-1)`
  form fails **open** on markup a renderer accepts.
- **AC-16** (oracle): an issue declaring **two** unresolved `pause-and-ask` regions names both
  in exactly one refusal — the AC-3 ergonomic applied to this check. The refusal count is
  asserted, not just the presence of both ids.
- **AC-17** (oracle): milestone 1 under `tracker.type: jira` passes on an issue carrying an
  unresolved `pause-and-ask` region — pinning that `check_pause_and_ask`'s jira short-circuit is
  reached. Without it the jira lane has no readable tracker, and the function's failure branch
  prints a reason, which *is* the refusal; the entire jira lane's milestone 1 would break.
- **AC-18** (oracle): an intent-gap record naming the region but reading `ratified: no` does
  **not** clear it. `ratified: no` and file-absent are indistinguishable to every pre-existing
  case, so the `ratified` conjunct was droppable with the suite green — the inverse of the merge
  boundary's own `ratified: no` refusal (P9).

## Open regions

No open regions — every decision in scope is codebase-derived: the pre-pass's scope (milestones
1 and 4 only, matching OR-2's resolved default of keeping milestone 5's tracker-reading
assertions in the expensive tier), the resolution-artifact shape for AC-8 (mirrors the existing
bot-claim trust filter and the intent-gap record's own `region:`/`ratified:` keys), and the
always-on pre-pass (OR-1's resolved default: the pre-pass output is a strict superset of what
`all` reports today, arriving sooner, so it adds no new refusal) are all derived from the source
issue's own resolved Open Regions and existing code conventions.
